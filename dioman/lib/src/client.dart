import 'dart:async';
import 'package:dio/dio.dart';
import 'clock.dart';
import 'config.dart';
import 'context.dart';
import 'context_state.dart';
import 'key.dart';
import 'options.dart';
import 'pipeline.dart';
import 'plugin.dart';
import 'request.dart';
import 'response.dart';
import 'stages.dart';
import 'transport.dart';

part 'client_internal.dart';

/// 关闭 debug 时复用的空日志器。
void _noLog(String _) {}

/// 以 Dio 为引擎的洋葱管线客户端；旧入口与本库完全独立。
class Dioman<R extends DiomanResponse<dynamic>> {
  /// 创建客户端，例如 `Dioman(dio: Dio(), debug: true)`。
  /// [deadline] 设置默认整体预算，null 不设截止；请求级非空值优先。
  /// [response] 控制归一化，[reject] 只转换动词方法的可预期失败。
  /// R 非基础响应时必须提供 response.create，否则在 setup 前抛 ArgumentError。
  Dioman(
      {required this.dio,
      List<DiomanPlugin<R>> plugins = const [],
      DiomanResponseFactory<R>? response,
      this.key = const DiomanKeyOptions(),
      this.reject,
      this.statusOf,
      this.deadline,
      Object? debug,
      this.clock = const DiomanClock.system()})
      : response = response ?? DiomanResponseFactory<R>(),
        _debug = debug != null && debug != false,
        _logger =
            debug is DiomanLogger ? debug : (debug == true ? print : _noLog) {
    if (debug != null && debug is! bool && debug is! DiomanLogger) {
      throw ArgumentError.value(debug, 'debug');
    }
    if (this.response.create == null && R != DiomanResponse<dynamic>) {
      throw ArgumentError(
          'Dioman<$R> 需要 response: DiomanResponseFactory<$R>(create: ...)');
    }
    validateDiomanPlugins(plugins);
    try {
      for (final plugin in plugins) {
        _registrations.add(DiomanRegistration(
            plugin, plugin.enabled ? plugin.setup(this) : null));
      }
      _compile();
    } catch (_) {
      for (final registration in _registrations.reversed) {
        try {
          final cleanup = registration.instance?.dispose();
          if (cleanup is Future<void>) cleanup.ignore();
        } catch (_) {/* 保留安装时首次异常。 */}
      }
      rethrow;
    }
  }

  /// 底层 Dio；用户拦截器在每次传输时运行。
  final Dio dio;

  /// 客户端的归一化服务。
  final DiomanResponseFactory<R> response;

  /// 客户端构键配置。
  final DiomanKeyOptions key;

  /// 可预期失败的最终异常转换器。
  final Object Function(R)? reject;

  /// 有效状态映射；省略时插件读取 HTTP status，例如 `(r) => r.status`。
  final int Function(DiomanResponse<dynamic>)? statusOf;

  /// 判断异常是否为取消结果，例如 `api.isCancel(error)`。
  bool isCancel(Object? error) => isDiomanCancel(error);

  /// 可注入时间服务。
  final DiomanClock clock;

  /// 默认逻辑请求预算；null 不设截止，由请求级非空值覆盖。
  /// 含排队、重试、共享等待与传输；零或负值立即到期。
  /// 例如 `Dioman(dio: Dio(), deadline: Duration(seconds: 5))`。
  final Duration? deadline;

  /// 是否记录调用点。
  final bool _debug;

  /// 用户日志器或默认输出。
  final DiomanLogger _logger;

  /// 注册顺序，供生命周期和 extend 使用。
  final _registrations = <DiomanRegistration<R>>[];

  /// 已排序的执行层快照。
  List<DiomanRegistration<R>> _layers = [];

  /// 编译后的链，在途请求捕获当前值。
  late DiomanRunner<R> _run;

  /// 活跃逻辑请求。
  final _pending = <DiomanContextState>{};

  /// 仍可取消的请求状态，包含逻辑调用已结束的共享传输。
  final _cancellable = <DiomanContextState>{};

  /// 每客户端只报告一次的未安装选项。
  final _warnedOptions = <DiomanOptionKey>{};

  /// 已移除实例仍在进行的异步清理。
  final _ejectedCleanups = <Future<void>>{};

  /// 按观测顺序保存清理异常，供最终销毁原栈报告。
  final _cleanupErrors = <(Object, StackTrace)>[];

  /// 请求序号。
  int _sequence = 0;

  /// 生命周期状态。
  bool _disposed = false;

  /// 首次销毁的完成信号，重复调用共享。
  Future<void>? _disposeFuture;

  /// 当前活跃逻辑请求数。
  int get pending => _pending.length;

  /// 隔离日志回调异常，避免 debug 改变请求结果。
  void _log(String message) {
    try {
      _logger(message);
    } catch (_) {/* 日志通知不影响请求。 */}
  }

  /// 记录插件通知故障；[message] 交给用户日志器或默认输出，日志器异常会隔离。
  /// 例如插件捕获回调错误后调用 `client.logError('通知失败')`，不受 debug 开关抑制。
  void logError(String message) {
    if (_debug) {
      _log(message);
    } else {
      try {
        print(message);
      } catch (_) {/* 输出通知不影响请求。 */}
    }
  }

  /// 拒绝销毁后的操作。
  void _checkAlive() {
    if (_disposed) throw StateError('客户端已销毁');
  }

  /// 在配置变动时编译链，不在请求期间排序。
  void _compile() {
    _layers = sortDiomanPipeline(_registrations);
    _run = compileDiomanPipeline(_layers, (ctx) => diomanTransport(dio, ctx));
  }

  /// 添加插件；先校验再 setup，安装失败不修改当前链。
  void use(DiomanPlugin<R> plugin) {
    _checkAlive();
    validateDiomanPlugins([..._registrations.map((r) => r.plugin), plugin]);
    final instance = plugin.enabled ? plugin.setup(this) : null;
    _registrations.add(DiomanRegistration(plugin, instance));
    _compile();
  }

  /// 按 [name] 移除并启动释放；不存在返回 false，在途保留原链。
  /// 同步清理错误直接抛出；异步清理由后续 dispose 等待并原栈报告。
  /// 销毁开始后拒绝移除，避免重复清理，例如 api.eject(插件名)。
  bool eject(String name) {
    _checkAlive();
    final index = _registrations.indexWhere((r) => r.plugin.name == name);
    if (index < 0) return false;
    final removed = _registrations.removeAt(index);
    _compile();
    final cleanup = removed.instance?.dispose();
    if (cleanup is Future<void>) {
      late final Future<void> pending;
      pending =
          cleanup.then<void>((_) {}, onError: (Object error, StackTrace stack) {
        _cleanupErrors.add((error, stack));
      }).whenComplete(() => _ejectedCleanups.remove(pending));
      _ejectedCleanups.add(pending);
    }
    return true;
  }

  /// 返回实现 [A] 的第一个实例，例如 `api.plugin<CacheApi>()`。
  A? plugin<A>() {
    for (final r in _registrations) {
      if (r.instance is A) return r.instance as A;
    }
    return null;
  }

  /// 返回解析后的固定阶段和名称顺序，返回列表不可修改。
  List<(DiomanStage, String)> inspect() => List.unmodifiable(_layers.map((r) {
        final fixed = diomanBuiltinStages.entries
            .where((e) => e.value.contains(r.plugin.name));
        return (
          fixed.isEmpty ? r.plugin.stage : fixed.single.key,
          r.plugin.name
        );
      }));

  /// 中止尚未取消的请求状态（含保留的共享传输），返回本次中止数。
  /// 首次 [reason] 非空时转为失败标记的字符串原因，例如 `api.cancelAll('logout')`。
  int cancelAll([Object? reason]) {
    var count = 0;
    for (final state in _cancellable.toList()) {
      if (!state.token.isCancelled) {
        count++;
        state.cancel(reason);
      }
    }
    return count;
  }

  /// 创建继承配置的子客户端并返回它，各自重新安装插件、管理请求与链。
  /// 省略 [dio] 时克隆父 BaseOptions（容器不共用），新建默认引擎，
  /// 不复制拦截器、adapter、transformer；传入时直接使用并保留其配置。
  /// [options] 在安装后合并非空、非默认字段，容器按顶层键合并；
  /// 不能用默认值重置继承的非默认值，覆盖会修改传入引擎。
  /// [plugins] 替换继承列表；工厂、key、statusOf、reject、debug、clock 继承引用，deadline 继承值。
  /// 相同 TokenManager 的 auth 会话、相等回调的 loading 状态共享。
  /// 传父客户端的引擎会共享可变配置，覆盖也影响父客户端。
  /// 示例：`api.extend(dio: Dio(), options: BaseOptions(baseUrl: 'https://child.example'))`。
  Dioman<R> extend(
      {Dio? dio, BaseOptions? options, List<DiomanPlugin<R>>? plugins}) {
    _checkAlive();
    final child = Dioman<R>(
        dio: dio ?? Dio(cloneDiomanOptions(this.dio.options)),
        plugins: plugins ?? _registrations.map((r) => r.plugin).toList(),
        response: response,
        statusOf: statusOf,
        key: key,
        reject: reject,
        debug: _debug ? _logger : false,
        deadline: deadline,
        clock: clock);
    if (options != null) mergeDiomanOptions(child.dio.options, options);
    return child;
  }

  /// 同步拒绝新请求并取消在途请求，再逆注册顺序等待全部实例清理。
  /// 返回清理完成信号，亦等待已移除实例；尽力全部执行后原栈抛出首个观测错误。
  /// 重复调用返回同一信号；不 await 也立即取消和拒绝，例如 await api.dispose()。
  Future<void> dispose() {
    final previous = _disposeFuture;
    if (previous != null) return previous;
    final completion = Completer<void>();
    _disposeFuture = completion.future;
    _disposed = true;
    cancelAll();
    _disposeInstances()
        .then(completion.complete, onError: completion.completeError);
    return completion.future;
  }

  /// 串行等待异步清理，同步实例仍在调用栈内完成。
  Future<void> _disposeInstances() async {
    for (final r in _registrations.reversed.toList()) {
      try {
        final pending = r.instance?.dispose();
        if (pending is Future<void>) await pending;
      } catch (e, s) {
        _cleanupErrors.add((e, s));
      }
    }
    for (final cleanup in _ejectedCleanups.toList()) {
      await cleanup;
    }
    if (_cleanupErrors.isNotEmpty) {
      Error.throwWithStackTrace(
          _cleanupErrors.first.$1, _cleanupErrors.first.$2);
    }
  }

  /// 执行请求并返回结果；可预期失败不抛，internal 原异常原栈抛出。
  /// [decode] 仅转换成功落定的数据，其余字段保持；省略时保留原行为。
  /// 解码异常原样原栈抛出，不经过插件或改为解析失败。
  /// 例如 `await api.send<Object?>('GET', '/pets')`。
  Future<DiomanResponse<T>> send<T>(String method, String path,
      {Map<String, dynamic>? query,
      Object? data,
      DiomanCall? call,
      T Function(Object? data)? decode}) async {
    final result =
        await _dispatch(method, path, query: query, data: data, call: call);
    if (result.ok && decode != null) {
      return DiomanResponseInternal.decoded(result, decode(result.data));
    }
    if (result is DiomanResponse<T>) return result;
    return result.copy<T>();
  }

  /// 执行任意 [method] 并返回数据；可预期失败经 reject 后抛出。
  /// [decode] 仅转换成功落定的数据，省略时直接转型；异常原样原栈抛出，
  /// 不经过插件或改为解析失败，例如 `api.request<int>('GET', '/count', decode: (v) => v as int)`。
  Future<T> request<T>(String method, String path,
      {Map<String, dynamic>? query,
      Object? data,
      DiomanCall? call,
      T Function(Object? data)? decode}) async {
    final result = await _dispatch(method, path,
        query: query, data: data, call: call, rejectFailure: true);
    return decode == null ? result.data as T : decode(result.data);
  }

  /// [decode] 仅转换成功落定的数据，异常原样原栈抛出，不经过插件或改为解析失败。
  /// 发送 GET 并返回数据；参数与 request 相同，例如 `api.get<Object?>('/pets')`。
  Future<T> get<T>(String path,
          {Map<String, dynamic>? query,
          Object? data,
          DiomanCall? call,
          T Function(Object? data)? decode}) =>
      request<T>('GET', path,
          query: query, data: data, call: call, decode: decode);

  /// [decode] 仅转换成功落定的数据，异常原样原栈抛出，不经过插件或改为解析失败。
  /// 发送 POST 并返回数据；参数与 request 相同，例如 `api.post<Object?>('/pets')`。
  Future<T> post<T>(String path,
          {Map<String, dynamic>? query,
          Object? data,
          DiomanCall? call,
          T Function(Object? data)? decode}) =>
      request<T>('POST', path,
          query: query, data: data, call: call, decode: decode);

  /// [decode] 仅转换成功落定的数据，异常原样原栈抛出，不经过插件或改为解析失败。
  /// 发送 PUT 并返回数据；参数与 request 相同，例如 `api.put<Object?>('/pets')`。
  Future<T> put<T>(String path,
          {Map<String, dynamic>? query,
          Object? data,
          DiomanCall? call,
          T Function(Object? data)? decode}) =>
      request<T>('PUT', path,
          query: query, data: data, call: call, decode: decode);

  /// [decode] 仅转换成功落定的数据，异常原样原栈抛出，不经过插件或改为解析失败。
  /// 发送 PATCH 并返回数据；参数与 request 相同，例如 `api.patch<Object?>('/pets')`。
  Future<T> patch<T>(String path,
          {Map<String, dynamic>? query,
          Object? data,
          DiomanCall? call,
          T Function(Object? data)? decode}) =>
      request<T>('PATCH', path,
          query: query, data: data, call: call, decode: decode);

  /// [decode] 仅转换成功落定的数据，异常原样原栈抛出，不经过插件或改为解析失败。
  /// 发送 DELETE 并返回数据；参数与 request 相同，例如 `api.delete<Object?>('/pets')`。
  Future<T> delete<T>(String path,
          {Map<String, dynamic>? query,
          Object? data,
          DiomanCall? call,
          T Function(Object? data)? decode}) =>
      request<T>('DELETE', path,
          query: query, data: data, call: call, decode: decode);

  /// [decode] 仅转换成功落定的数据，异常原样原栈抛出，不经过插件或改为解析失败。
  /// 发送 HEAD 并返回数据；参数与 request 相同，例如 `api.head<Object?>('/pets')`。
  Future<T> head<T>(String path,
          {Map<String, dynamic>? query,
          Object? data,
          DiomanCall? call,
          T Function(Object? data)? decode}) =>
      request<T>('HEAD', path,
          query: query, data: data, call: call, decode: decode);

  /// 入口仅 compose 一次；登记后所有可能抛错的构造都在 finally 保护内。
  Future<DiomanResponse<dynamic>> _dispatch(String method, String path,
      {Map<String, dynamic>? query,
      Object? data,
      DiomanCall? call,
      bool rejectFailure = false}) async {
    _checkAlive();
    final run = _run;
    final site = _debug ? StackTrace.current : null;
    late final DiomanContextState state;
    state = DiomanContextState(CancelToken(),
        onDispose: () => _cancellable.remove(state));
    _cancellable.add(state);
    DiomanCancelLink? userLink;
    Timer? deadlineTimer;
    _pending.add(state);
    try {
      final c = call ?? const DiomanCall();
      if (c.cancelToken != null) {
        userLink = DiomanCancelLink(c.cancelToken!, state.cancel);
      }
      final budget = c.deadline ?? deadline;
      if (budget != null) {
        if (budget <= Duration.zero) {
          state.expireDeadline();
        } else {
          deadlineTimer = clock.createTimer(budget, state.expireDeadline);
        }
      }
      if (_debug) {
        for (final option in c.options.keys) {
          if (!_registrations.any((r) => r.plugin.name == option.description) &&
              _warnedOptions.add(option)) {
            _log('请求选项 ${option.description} 对应的插件未安装');
          }
        }
      }
      final options = Options(
              method: method,
              headers: c.headers,
              extra: c.extra,
              sendTimeout: c.sendTimeout,
              receiveTimeout: c.receiveTimeout)
          .compose(dio.options, path, queryParameters: query, data: data);
      if (c.connectTimeout != null) options.connectTimeout = c.connectTimeout;
      final ctx = DiomanContextInternal.create<R>(
          id: ++_sequence,
          client: this,
          request: DiomanRequest(options, call: c),
          state: state,
          factory: response,
          keyService: DiomanKeyService(key),
          clock: clock,
          log: _log);
      var result = await run(ctx);
      if (failureOf(result)?.kind != DiomanFailureKind.internal) {
        result = ctx.cancelled() ?? result;
      }
      ctx.observeNative(result);
      final native = ctx.native;
      if (!result.ok &&
          site != null &&
          failureOf(result)?.kind != DiomanFailureKind.internal) {
        result = response.withCallSite(result, site);
      }
      if (c.raw && native != null) {
        result = response.withNative(result, native.raw, native.error);
      }
      if (failureOf(result)?.kind == DiomanFailureKind.internal) {
        Error.throwWithStackTrace(
            failureOf(result)?.error ??
                StateError('internal result without error'),
            failureOf(result)?.errorStack ?? StackTrace.current);
      }
      ctx.observeNative(result);
      if (rejectFailure && !result.ok) {
        throw (reject?.call(result as R) ?? result);
      }
      return result;
    } finally {
      deadlineTimer?.cancel();
      state.closeNative();
      userLink?.dispose();
      state.dispose();
      _pending.remove(state);
    }
  }
}
