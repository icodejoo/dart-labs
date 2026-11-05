import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

import '../rust/frb_generated.dart';
import 'native_svg_values.dart';
import 'svg_document_parser.dart';

/// Engine diagnostic for root-only UI calls. / 引擎对仅限主 isolate UI 调用的诊断。
const _rootUiDiagnostic = 'UI actions are only available on root isolate';

/// Lazily owns one persistent parser isolate. / 惰性持有一个常驻解析 isolate。
class DocumentParseWorker {
  /// Shared parser worker. / 共享解析 worker。
  static final instance = DocumentParseWorker._();

  /// Creates the owner without starting an isolate. / 创建持有者，不启动 isolate。
  DocumentParseWorker._();

  /// Current connection; discarded on termination. / 当前连接，终止后丢弃。
  _WorkerConnection? _connection;

  /// Includes failed workers until their exit is confirmed. / 保留失败 worker，直到确认退出。
  final _connections = <_WorkerConnection>{};

  /// Number of submitted requests for lifecycle tests. / 生命周期测试用请求计数。
  int _requestCount = 0;

  /// Number of spawned connections for lifecycle tests. / 生命周期测试用启动计数。
  int _startCount = 0;

  /// Overrides native loading for initialization-failure tests.
  /// 初始化失败测试用的原生库加载路径覆盖。
  @visibleForTesting
  String? debugNativeLibraryPath;

  /// Parses a fresh document without populating UI caches. / 解析新文档，不填充 UI 缓存。
  Future<SvgDocument> parse(String source) {
    final connection = _connection ??= _WorkerConnection(
      debugNativeLibraryPath,
      () {
        _connection = null;
      },
    );
    _requestCount++;
    if (!connection.started) {
      _connections.add(connection);
      connection.stopped.then((_) => _connections.remove(connection));
      _startCount++;
      connection.start();
    }
    return connection.parse(source);
  }

  /// Submitted request count. / 已提交请求数。
  @visibleForTesting
  int get debugRequestCount => _requestCount;

  /// Connection start count. / 连接启动次数。
  @visibleForTesting
  int get debugStartCount => _startCount;

  /// Kills the isolate and waits for its exit notification. / 强杀并等待退出通知。
  @visibleForTesting
  Future<void> debugKill() async {
    final connection = _connection;
    if (connection == null) return;
    connection.kill();
    await connection.stopped;
  }

  /// Fails pending work, closes ports and resets counters. / 拒绝在途请求、关闭端口并重置计数。
  @visibleForTesting
  Future<void> debugReset() => dispose();

  /// Stops all owned lifetimes and resets diagnostics. / 停止全部持有的生命周期并重置诊断。
  Future<void> dispose() async {
    final connections = _connections.toList();
    for (final connection in connections) {
      connection.dispose();
    }
    await Future.wait(connections.map((connection) => connection.stopped));
    _requestCount = 0;
    _startCount = 0;
    debugNativeLibraryPath = null;
  }
}

/// One isolated lifetime, including startup and queued work. / 单次生命周期，含启动及排队请求。
class _WorkerConnection {
  /// Installs listeners before spawning to catch early failures. / 启动前监听，捕获早期失败。
  _WorkerConnection(this._libraryPath, this._onFailure) {
    _messages.listen(_onMessage);
  }

  /// Invalidates the owner's connection after a failure. / 失败后使持有者的连接失效。
  final void Function() _onFailure;

  /// Optional native loading override captured at startup. / 启动时捕获的可选库路径覆盖。
  final String? _libraryPath;

  /// Receives readiness, responses, fatal errors and exit in order.
  /// 按顺序接收就绪、响应、致命错误和退出通知。
  final ReceivePort _messages = ReceivePort();

  /// Requests waiting for startup or a response. / 等待启动或响应的请求。
  final _pending = <int, ({String source, Completer<SvgDocument> result})>{};

  /// Completes only after the isolate has stopped. / 仅在 isolate 已停止后完成。
  final Completer<void> _stopped = Completer<void>();

  /// Underlying isolate once spawn completes. / spawn 完成后的 isolate。
  Isolate? _isolate;

  /// Worker command port after successful initialization. / 初始化成功后的命令端口。
  SendPort? _commands;

  /// Monotonic request identifier within this connection. / 本连接内单调增长的请求 id。
  int _nextId = 0;

  /// Whether spawning has begun. / 是否已开始启动。
  bool started = false;

  /// Whether pending work has been failed. / 是否已拒绝在途工作。
  bool _failed = false;

  /// Records a test kill requested before spawn returns. / 记录 spawn 返回前请求的测试强杀。
  bool _killRequested = false;

  /// Waits for full termination, including native ports. / 等待完全终止，含原生端口。
  Future<void> get stopped => _stopped.future;

  /// Starts once and handles disposal during spawn. / 启动一次，并处理启动中的释放。
  void start() {
    started = true;
    Future<Isolate>.sync(
      () => Isolate.spawn(
        _parseWorkerMain,
        (_messages.sendPort, _libraryPath),
        onError: _messages.sendPort,
        onExit: _messages.sendPort,
        debugName: 'svgx-document-parser',
      ),
    ).then(
      (isolate) {
        _isolate = isolate;
        if (_failed || _killRequested) {
          isolate.kill(priority: Isolate.immediate);
        }
      },
      onError: (Object error, StackTrace stack) {
        _fail(
          DocumentParseWorkerUnavailable(
            error,
            kind: DocumentParseWorkerFailureKind.spawn,
          ),
          stack,
        );
        _finish();
      },
    );
  }

  /// Queues a request even while Rust is initializing. / Rust 初始化期间也可排队。
  Future<SvgDocument> parse(String source) {
    final id = _nextId++;
    final result = Completer<SvgDocument>();
    _pending[id] = (source: source, result: result);
    _commands?.send((id, source));
    return result.future;
  }

  /// Dispatches the wire protocol and rejects all work on termination.
  /// 分发端口协议，终止时拒绝全部工作。
  void _onMessage(dynamic message) {
    if (message == null) {
      _fail(
        DocumentParseWorkerUnavailable(
          StateError('SVGX document parse worker exited'),
          kind: DocumentParseWorkerFailureKind.unexpectedExit,
        ),
        StackTrace.current,
      );
      _finish();
      return;
    }
    if (_failed || _killRequested) return;
    if (message is SendPort) {
      _commands = message;
      for (final entry in _pending.entries) {
        message.send((entry.key, entry.value.source));
      }
    } else if (message is (int, SvgDocument)) {
      _pending.remove(message.$1)?.result.complete(message.$2);
    } else if (message is _WorkerFailure) {
      if (message.id == null) {
        _fail(message.error as DocumentParseWorkerUnavailable, message.stack);
      } else {
        _pending
            .remove(message.id)
            ?.result
            .completeError(
              message.rootOnly
                  ? RootIsolateParseError(message.error)
                  : message.error,
              message.stack,
            );
      }
    } else if (message is List) {
      // The VM sends uncaught errors as [description, stack].
      // VM 将未捕获错误发送为 [描述, 堆栈]。
      _fail(
        DocumentParseWorkerUnavailable(
          RemoteError('${message[0]}', '${message[1]}'),
          kind: DocumentParseWorkerFailureKind.unexpectedExit,
        ),
        StackTrace.fromString('${message[1]}'),
      );
    }
  }

  /// Fails all callers once, leaving the port open for exit. / 一次性拒绝所有调用，留端口接收退出。
  void _fail(DocumentParseWorkerUnavailable error, StackTrace stack) {
    if (_failed) return;
    _failed = true;
    _onFailure();
    for (final request in _pending.values) {
      request.result.completeError(error, stack);
    }
    _pending.clear();
    _isolate?.kill(priority: Isolate.immediate);
  }

  /// Closes the final port after exit or spawn failure. / 退出或启动失败后关闭最后的端口。
  void _finish() {
    _messages.close();
    if (!_stopped.isCompleted) _stopped.complete();
  }

  /// Simulates an unexpected exit, including during startup. / 模拟意外退出，含启动阶段。
  void kill() {
    _killRequested = true;
    _isolate?.kill(priority: Isolate.immediate);
  }

  /// Disposes pending work and the isolate. / 释放在途请求和 isolate。
  void dispose() {
    _fail(
      DocumentParseWorkerUnavailable(
        StateError('SVGX document parse worker disposed'),
        kind: DocumentParseWorkerFailureKind.disposed,
      ),
      StackTrace.current,
    );
  }
}

/// Infrastructure failure categories, separate from parse errors.
/// 基础设施失败分类，与文档解析错误分开。
enum DocumentParseWorkerFailureKind {
  /// Native loading or self-check failed. / 原生加载或自检失败。
  initialization,

  /// The isolate could not be spawned. / isolate 无法启动。
  spawn,

  /// A running or starting isolate died unexpectedly. / 运行或启动中的 isolate 意外退出。
  unexpectedExit,

  /// The owner explicitly stopped the worker. / 持有者主动停止 worker。
  disposed,
}

/// Unavailable worker infrastructure; XML/parser exceptions stay unwrapped.
/// worker 基础设施不可用；XML 或解析器异常不使用此包装。
class DocumentParseWorkerUnavailable implements Exception {
  /// Retains the cause and lifecycle category. / 保留原因及生命周期分类。
  const DocumentParseWorkerUnavailable(this.cause, {required this.kind});

  /// Original infrastructure error. / 原始基础设施错误。
  final Object cause;

  /// Failure phase used for retry policy. / 决定重试策略的失败阶段。
  final DocumentParseWorkerFailureKind kind;

  /// Startup failures cool down; isolated crashes allow an immediate rebuild.
  /// 启动失败进入冷却；单次崩溃不代表环境不可用，允许立即重建。
  bool get shouldCooldown =>
      kind == DocumentParseWorkerFailureKind.initialization ||
      kind == DocumentParseWorkerFailureKind.spawn;

  @override
  String toString() => 'DocumentParseWorkerUnavailable(${kind.name}): $cause';
}

/// Explicitly identifies a root-only parser failure. / 明确标识仅可在主 isolate 解析的失败。
class RootIsolateParseError implements Exception {
  /// Retains the original UI failure. / 保留原始 UI 错误。
  const RootIsolateParseError(this.cause);

  /// Original engine failure. / 原始引擎错误。
  final Object cause;
}

/// Sendable failure packet; initialization uses a null id. / 可发送的失败包，初始化用空 id。
class _WorkerFailure {
  /// Captures the original exception and stack. / 保存原异常与堆栈。
  const _WorkerFailure(
    this.id,
    this.error,
    this.stack, {
    this.rootOnly = false,
  });

  /// Request id, or null for initialization. / 请求 id，初始化时为空。
  final int? id;

  /// Original exception when sendable. / 可发送时为原异常。
  final Object error;

  /// Original worker stack. / 原始 worker 堆栈。
  final StackTrace stack;

  /// Whether the parser hit an explicit UI restriction. / 解析器是否触发明确的 UI 限制。
  final bool rootOnly;
}

/// Initializes native values before accepting any source. / 接收源串前初始化原生取值。
void _parseWorkerMain((SendPort, String?) arguments) async {
  final (replies, libraryPath) = arguments;
  try {
    // Use FRB's platform loader inside this isolate (bundled app library or
    // the host's library search path); never inherit a root-isolate FFI handle.
    // 在本 isolate 使用 FRB 平台加载器（应用内置库或主机搜索路径），不继承主 isolate 句柄。
    await RustLib.init(
      externalLibrary: libraryPath == null
          ? null
          : ExternalLibrary.open(libraryPath),
    );
    final color = resolveColorToHex('cornflowerblue');
    final transform = parseTransformMatrix('translate(10,20)');
    if (color != '#6495EDFF' ||
        transform == null ||
        !listEquals(transform, const [1.0, 0.0, 0.0, 1.0, 10.0, 20.0])) {
      throw StateError(
        'native color/transform self-check returned invalid values',
      );
    }
  } catch (error, stack) {
    replies.send(
      _WorkerFailure(
        null,
        DocumentParseWorkerUnavailable(
          error,
          kind: DocumentParseWorkerFailureKind.initialization,
        ),
        stack,
      ),
    );
    Isolate.exit();
  }
  final commands = ReceivePort();
  commands.listen((dynamic message) {
    final (id, source) = message as (int, String);
    try {
      replies.send((id, parseAnimatedSvgDocument(source)));
    } catch (error, stack) {
      // Require both the engine diagnostic and a dart:ui frame: XML text
      // containing the diagnostic must never trigger a fallback.
      // 同时要求引擎诊断及 dart:ui 堆栈，避免 XML 文本碰巧包含诊断而触发回退。
      final rootOnly =
          error.toString().contains(_rootUiDiagnostic) &&
          stack.toString().contains('dart:ui/');
      try {
        replies.send(_WorkerFailure(id, error, stack, rootOnly: rootOnly));
      } catch (_) {
        replies.send(
          _WorkerFailure(
            id,
            RemoteError(error.toString(), stack.toString()),
            stack,
          ),
        );
      }
    }
  });
  replies.send(commands.sendPort);
}
