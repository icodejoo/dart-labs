// Transfer diagnosis (LIB=anim_transfer): seven unique cold sources per mode.
// 传递定位：每模式七次唯一注释冷源；I/O、计数、注释、筛选及校验不计时。
//
// M1/M2 share a persistent worker initialized like document_parse_worker.dart.
// M1 returns only an int; M2 sends (id, document), then separate send timing.
// M3 spawns per call and Isolate.exit transfers the document plus small metrics.
// M1/M2 共用常驻 worker，初始化同库；M1 仅回整数，M2 先发文档再发 send 计时；
// M3 每次 spawn，exit 转移文档和小型诊断。无缓存；唯一源不代表清空原生状态。
// M5 exercises getOrParseAsync with a separately warmed library worker; M2/M5
// alternate first position each round and both clear the cache before probing.
// M6 runs serial CPU phases after all async probes, with signed cache estimates.
// M5 测已预热库 worker 的缓存全路径；M2/M5 每轮交替先后，探针前均清缓存。
// M6 在全部异步探针后串行测 CPU 分段，缓存成本估算保留负值。
//
// Reading guide / 读数指引：
// Compare each mode with its seven latency-matched M0 windows. M1 excess
// suggests allocation/GC or scheduling interference. Extra M2 over M1, reduced
// in M3, supports copying costs but cannot isolate receiver deserialization.
// M3 also changes lifetime, GC and startup work. send_us includes sender copy
// and scheduling pauses, not receiver CPU. M1/M3 order can still introduce drift.
// 对比各模式匹配的七个 M0；M1 超额提示分配/GC 或调度干扰；M2 比 M1 更高且 M3
// 降低支持传递成本假说，但不能单独归因接收端反序列化。M3 也改变生命周期、GC
// 和启动成本；send_us 含发送端复制及暂停；M1/M3 顺序仍可能引入漂移。
// M6 cache_delta includes the image walk; subtract it for remember_insert_est
// before summing. CPU phase sums and M5-M2 maximum-gap differences are proxies,
// not an additive decomposition; string hashing, Futures, GC and drift remain.
// M6 的 cache_delta 含图片遍历，先扣除它得到 remember_insert_est 再求和。
// CPU 分段和与 M5-M2 最大间隙差仅作对照，不能线性归因；仍有字符串哈希、
// Future、GC 及设备漂移，且差值包含不同解析调用的噪声，可能为负。
// The 1ms timer includes start and first post-completion tick, as anim_async.
// This is a scheduling-gap proxy, NOT frame time; GC/OS scheduling add noise.
// 1ms 定时器同 anim_async，含起点和完成后首 tick；是调度间隙代理，非帧耗时。
// M4 receiver-only deserialization: unavailable / 不可测：VM has no Dart hook
// before deserialization; listener-to-Future timing already misses that phase.
// VM 无反序列化前的 Dart 钩子，监听器到 Future 的计时已错过该阶段。
//
// Reproduce in benchmark/bench_app PowerShell / 在该目录复现：
// Windows (external read-only corpus / 外部语料仅读):
//   $corpusDir = 'C:\Users\jelon\AppData\Local\Temp\claude\E--workspaces-dart-labs-svgx\93aa9a18-7032-40b5-84a7-7704e2b7f8bf\scratchpad\css_samples'
//   $reportFile = Join-Path $PWD 'build\anim_transfer_report.txt'
//   $env:PATH = 'E:\workspaces\dart-labs-svgx\svgx\prebuilt\windows\x64;' + $env:PATH
//   flutter run -d windows --profile --dart-define=LIB=anim_transfer "--dart-define=CORPUS_DIR=$corpusDir" "--dart-define=REPORT_FILE=$reportFile" --dart-define=AUTOEXIT=true
// Android (device operator only / 仅供真机操作者):
//   flutter build apk --profile --dart-define=LIB=anim_transfer --dart-define=AUTOEXIT=true --dart-define=REPORT_FILE=/sdcard/Android/data/com.example.bench_app/files/anim_transfer_report.txt
//   adb -s 7NQBB23606003715 install -r build/app/outputs/flutter-apk/app-profile.apk
//   adb -s 7NQBB23606003715 shell am start -n com.example.bench_app/.MainActivity
//   adb -s 7NQBB23606003715 shell mkdir -p /sdcard/Android/data/com.example.bench_app/files/corpus_css
//   adb -s 7NQBB23606003715 push "$corpusDir/." /sdcard/Android/data/com.example.bench_app/files/corpus_css
//   adb -s 7NQBB23606003715 logcat -c
//   adb -s 7NQBB23606003715 shell am start -n com.example.bench_app/.MainActivity
//   adb -s 7NQBB23606003715 logcat -s flutter:I
//   adb -s 7NQBB23606003715 pull /sdcard/Android/data/com.example.bench_app/files/anim_transfer_report.txt build/anim_transfer_android_report.txt
// Wait for missing-corpus AUTOEXIT before mkdir/push; MainActivity creates the
// owned parent. dir/. avoids nesting. Reports append; use a fresh path.
// 缺语料启动退出后再 mkdir/push；MainActivity 创建属主父目录，/. 避免嵌套。
// 报告追加写入，可换路径或按 BEGIN/END 分轮。

// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:svgx/src/animation/document_parse_worker.dart';
import 'package:svgx/src/animation/native_svg_values.dart';
import 'package:svgx/src/animation/svg_document_cache.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svgx_animation_info.dart';
import 'package:svgx/src/rust/frb_generated.dart';

import 'report_sink.dart';
import 'stats.dart';

/// External corpus and measurement constants. / 外部语料及测量常量。
const _corpusDir = String.fromEnvironment(
  'CORPUS_DIR',
  defaultValue: '/sdcard/Android/data/com.example.bench_app/files/corpus_css',
);
const _trials = 7;
const _threshold = 128;
const _tickPeriod = Duration(milliseconds: 1);
const _settle = Duration(milliseconds: 20);
const _timeout = Duration(minutes: 2);
const _svgClose = '</svg>';
const _m0 = 'M0';
const _m1 = 'M1';
const _m2 = 'M2';
const _m3 = 'M3';
const _m5 = 'M5';
const _m6 = 'M6';
const _modes = [_m1, _m2, _m5, _m3];
const _ok = 'ok';
const _mismatch = 'MISMATCH';
const _totalMetric = 'total';
const _gapMetric = 'gap';
const _estimateMetric = 'estimate';
const _imageRegexMetric = 'image_regex';
const _documentImagesMetric = 'document_images';
const _syncParseMetric = 'sync_parse';
const _syncCacheMetric = 'sync_cache';
const _cacheDeltaMetric = 'cache_delta';
const _rememberInsertMetric = 'remember_insert_est';
const _extraSumMetric = 'extra_sum';
const _extraMetrics = [
  _estimateMetric,
  _imageRegexMetric,
  _documentImagesMetric,
  _syncParseMetric,
  _syncCacheMetric,
  _cacheDeltaMetric,
  _rememberInsertMetric,
  _extraSumMetric,
];
// Copied verbatim from svg_document_cache.dart; keep this literal in sync.
// 照抄 svg_document_cache.dart 的私有正则字面量，必须与库保持一致。
final _imageElement = RegExp(r'<(?:[^<>\s/:]+:)?image(?=[\s/>])');

/// Initializes and checks the same native values as the library worker.
/// 初始化并自检，与库 worker 相同。
Future<int> _initNative() async {
  final init = Stopwatch()..start();
  await RustLib.init();
  init.stop();
  final color = resolveColorToHex('cornflowerblue');
  final transform = parseTransformMatrix('translate(10,20)');
  if (color != '#6495EDFF' ||
      transform == null ||
      !listEquals(transform, const [1.0, 0.0, 0.0, 1.0, 10.0, 20.0])) {
    throw StateError(
      'native color/transform self-check returned invalid values',
    );
  }
  return init.elapsedMicroseconds;
}

/// String-only errors remain sendable for native exceptions. / 异常转字符串以便传递。
class _Failure {
  const _Failure(this.description);
  final String description;
}

/// Sent after the M2 document, outside its latency. / M2 文档后发的诊断，不计入延迟。
class _SendTiming {
  const _SendTiming(this.us);
  final int us;
}

/// Exit-transferred document and worker-local phases. / exit 转移文档及内部计时。
class _ExitReply {
  const _ExitReply(
    this.document,
    this.startUs,
    this.initUs,
    this.initSelfCheckUs,
    this.parseUs,
  );
  final SvgDocument document;
  final int startUs, initUs, initSelfCheckUs, parseUs;
}

/// Permanent parser with the library's document envelope. / 常驻解析器，文档封套同库。
void _persistentMain(SendPort replies) async {
  try {
    await _initNative();
  } catch (error, stack) {
    replies.send(_Failure('initialization: $error\n$stack'));
    Isolate.exit();
  }
  final commands = ReceivePort();
  commands.listen((dynamic message) {
    final (id, mode, source) = message as (int, String, String);
    try {
      final document = parseAnimatedSvgDocument(source);
      if (mode == _m1) {
        replies.send(document.timelines.length);
      } else {
        final sendWatch = Stopwatch()..start();
        replies.send((id, document));
        sendWatch.stop();
        replies.send(_SendTiming(sendWatch.elapsedMicroseconds));
      }
    } catch (error, stack) {
      replies.send(_Failure('parse/send: $error\n$stack'));
    }
  });
  replies.send(commands.sendPort);
}

/// A copied running Stopwatch carries its monotonic origin into the entry.
/// 复制运行中的 Stopwatch，将单调时钟起点带进入口，不使用墙钟。
void _exitMain((SendPort, String, Stopwatch) arguments) async {
  final (replies, source, startup) = arguments;
  final startUs = startup.elapsedMicroseconds;
  try {
    final init = Stopwatch()..start();
    final initUs = await _initNative();
    init.stop();
    final parse = Stopwatch()..start();
    final document = parseAnimatedSvgDocument(source);
    parse.stop();
    Isolate.exit(
      replies,
      _ExitReply(
        document,
        startUs,
        initUs,
        init.elapsedMicroseconds,
        parse.elapsedMicroseconds,
      ),
    );
  } catch (error, stack) {
    Isolate.exit(replies, _Failure('one-shot: $error\n$stack'));
  }
}

/// Shared port lifecycle; all requests are serial. / 共用端口生命周期；请求均串行。
class _Connection {
  _Connection() {
    _messages.listen(_onMessage);
    unawaited(_ready.future.then<void>((_) {}, onError: (Object _) {}));
  }
  final ReceivePort _messages = ReceivePort();
  final Completer<SendPort> _ready = Completer<SendPort>();
  final Completer<void> _stopped = Completer<void>();
  Completer<Object>? _result;
  Completer<int>? _send;
  Isolate? _isolate;
  Future<void>? _spawning;
  bool _exitTransferred = false;
  Object? _fatal;
  int _id = 0;

  /// Resolves usability at document arrival, before diagnostics.
  /// 文档到达即标记可用，不等待诊断。
  void _onMessage(dynamic message) {
    if (message == null) {
      _fatal = StateError('isolate exited');
      _fail(_fatal!);
      _messages.close();
      if (!_stopped.isCompleted) _stopped.complete();
    } else if (message is _Failure || message is List) {
      final error = StateError(
        message is _Failure ? message.description : '$message',
      );
      if (!_ready.isCompleted || message is List) _fatal = error;
      _fail(error);
    } else if (message is SendPort) {
      _ready.complete(message);
    } else if (message is _SendTiming) {
      if (!(_send?.isCompleted ?? true)) _send!.complete(message.us);
    } else if (message is (int, SvgDocument)) {
      _completeResult(message.$2);
    } else if (message is int || message is _ExitReply) {
      _exitTransferred = message is _ExitReply;
      _completeResult(message as Object);
    }
  }

  /// Releases the connection's graph reference on delivery. / 交付时释放连接的图引用。
  void _completeResult(Object value) {
    final result = _result!;
    _result = null;
    result.complete(value);
  }

  /// Rejects outstanding futures once. / 一次性拒绝在途 Future。
  void _fail(Object error) {
    if (!_ready.isCompleted) _ready.completeError(error);
    if (!(_result?.isCompleted ?? true)) _result!.completeError(error);
    if (!(_send?.isCompleted ?? true)) _send!.completeError(error);
  }

  /// Starts outside timing, including native init/self-check. / 计时外启动含自检。
  Future<void> start() async {
    try {
      _isolate = await Isolate.spawn(
        _persistentMain,
        _messages.sendPort,
        onError: _messages.sendPort,
        onExit: _messages.sendPort,
      );
      await _ready.future.timeout(_timeout);
    } catch (_) {
      await close();
      rethrow;
    }
  }

  /// Prepares bookkeeping and error handlers outside probes. / 探针外准备记账及异常处理。
  void prepare({bool copy = false, bool once = false}) {
    if (_fatal != null) throw _fatal!;
    _result = Completer<Object>();
    unawaited(_result!.future.then<void>((_) {}, onError: (Object _) {}));
    _send = copy ? Completer<int>() : null;
    if (copy) {
      unawaited(_send!.future.then<void>((_) {}, onError: (Object _) {}));
    }
    if (once) _ready.complete(_messages.sendPort);
  }

  /// Sends a cold source to the ready worker. / 向就绪 worker 发送冷源。
  Future<Object> request(String mode, String source) {
    _ready.future.then((port) => port.send((_id++, mode, source)));
    return _result!.future.timeout(_timeout);
  }

  /// Starts a Stopwatch just before spawn, read inside the entry.
  /// Stopwatch 紧邻 spawn 启动，在入口内部读取。
  Future<Object> transfer(String source) {
    final startup = Stopwatch()..start();
    _spawning =
        Isolate.spawn(
          _exitMain,
          (_messages.sendPort, source, startup),
          onError: _messages.sendPort,
          onExit: _messages.sendPort,
        ).then<void>(
          (isolate) {
            _isolate = isolate;
          },
          onError: (Object error) {
            _fatal = error;
            _fail(error);
            _messages.close();
            if (!_stopped.isCompleted) _stopped.complete();
          },
        );
    return _result!.future.timeout(_timeout);
  }

  /// Diagnostics are awaited after probes. / 探针结束后等待诊断。
  Future<int> get sendUs => _send!.future.timeout(_timeout);

  /// Confirms termination before the next lifetime. / 确认退出再进入下一生命周期。
  Future<void> close() async {
    await _spawning;
    if (_stopped.isCompleted) return;
    if (_exitTransferred) {
      await _stopped.future.timeout(_timeout);
      return;
    }
    final isolate = _isolate;
    if (isolate == null) {
      _messages.close();
      _stopped.complete();
    } else {
      isolate.kill(priority: Isolate.immediate);
      await _stopped.future.timeout(_timeout);
    }
  }
}

/// Same start/trailing-tick method as anim_async. / 与 anim_async 相同的起点及尾 tick 法。
class _Probe {
  _Probe() {
    _timer = Timer.periodic(_tickPeriod, (_) {
      final now = watch.elapsedMicroseconds;
      final gap = now - _lastUs;
      if (gap > maxGapUs) maxGapUs = gap;
      _lastUs = now;
      if (_finishing) {
        _timer.cancel();
        _stopped.complete();
      }
    });
  }
  final Stopwatch watch = Stopwatch()..start();
  final Completer<void> _stopped = Completer<void>();
  late final Timer _timer;
  int _lastUs = 0, maxGapUs = 0;
  bool _finishing = false;

  Future<void> finish() async {
    _finishing = true;
    await _stopped.future;
    watch.stop();
  }
}

/// Small correctness metadata, without the sync graph. / 小型正确性摘要，不保留同步图。
class _Signature {
  _Signature(SvgDocument document)
    : info = document.info,
      timelines = document.timelines.length;
  final SvgxAnimationInfo info;
  final int timelines;
  bool matches(SvgDocument document) =>
      document.info == info && document.timelines.length == timelines;
  @override
  String toString() => '$info timelines=$timelines';
}

/// Loaded sample and untimed metadata. / 样本及不计时元数据。
class _Sample {
  _Sample(this.name, this.source, this.tags, this.closeOffset);
  final String name, source;
  final int tags, closeOffset;
}

/// Scalar measurements, never retaining document graphs. / 标量测量，不持有文档图。
class _Timing {
  const _Timing(
    this.totalUs,
    this.gapUs, {
    this.sendUs,
    this.startUs,
    this.initUs,
    this.initSelfCheckUs,
    this.parseUs,
    this.check = _ok,
  });
  final int totalUs, gapUs;
  final int? sendUs, startUs, initUs, initSelfCheckUs, parseUs;
  final String check;
}

/// Transfer diagnosis screen. / 文档传递定位屏幕。
class AnimTransferBenchScreen extends StatefulWidget {
  const AnimTransferBenchScreen({super.key});
  @override
  State<AnimTransferBenchScreen> createState() =>
      _AnimTransferBenchScreenState();
}

/// Sequential runner with matched idle controls. / 串行运行及匹配空闲对照。
class _AnimTransferBenchScreenState extends State<AnimTransferBenchScreen> {
  final _worker = _Connection();
  final _gaps = <String, List<int>>{};
  final _idleGaps = <String, List<int>>{};
  final _extraTimes = <String, List<int>>{
    for (final metric in _extraMetrics) metric: [],
  };
  int _serial = 0, _errors = 0, _measured = 0;
  String _progress = 'Waiting for first frame';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  void _emit(String line) => emitReport('$line\n');
  void _error(Object error, {String? file}) {
    _errors++;
    _emit('ERROR file=${jsonEncode(file)} reason=${jsonEncode('$error')}');
  }

  /// Preparation is always outside timing. / 源串准备始终在计时外。
  String _fresh(_Sample sample) => sample.source.replaceRange(
    sample.closeOffset,
    sample.closeOffset,
    '<!--anim_transfer_r${_serial++}-->',
  );

  /// Warm unrelated data through the worker and full API, outside all probes.
  /// 用无关小型大源预热库 worker 及完整 API，全部位于探针外。
  Future<void> _warmLibraryWorker() async {
    final source =
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '${List.filled(documentParseWorkerNodeThreshold, '<g/>').join()}'
        '$_svgClose';
    // Direct warm-up surfaces startup failures instead of timing a fallback.
    // 直接预热可暴露启动失败，避免把启动回退混入测量。
    await DocumentParseWorker.instance.parse(source).timeout(_timeout);
    await SvgxDocumentCache.instance.getOrParseAsync(source).timeout(_timeout);
    SvgxDocumentCache.instance.clear();
  }

  /// Counts like the library, excludes images, then probes worker compatibility.
  /// 按库计数，排除图片，再试解析确认 worker 兼容。
  Future<List<_Sample>> _load() async {
    final directory = Directory(_corpusDir);
    if (!await directory.exists()) {
      throw FileSystemException('Corpus directory does not exist', _corpusDir);
    }
    final files = await directory
        .list(followLinks: false)
        .where(
          (entry) => entry is File && entry.path.toLowerCase().endsWith('.svg'),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    final samples = <_Sample>[];
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      try {
        final source = utf8.decode(await file.readAsBytes());
        // ignore: invalid_use_of_visible_for_testing_member
        final tags = estimateDocumentParseNodeCount(source);
        if (tags < _threshold) continue;
        if (_imageElement.hasMatch(source)) {
          _emit('SKIP name=${jsonEncode(name)} tags=$tags reason=image');
          continue;
        }
        final offset = source.lastIndexOf(_svgClose);
        if (offset < 0) throw FormatException('Missing $_svgClose');
        final sample = _Sample(name, source, tags, offset);
        _worker.prepare();
        await _worker.request(_m1, _fresh(sample));
        samples.add(sample);
      } catch (error) {
        _emit('SKIP name=${jsonEncode(name)} reason=${jsonEncode('$error')}');
      }
    }
    _emit('corpus_files=${files.length} selected_files=${samples.length}');
    if (samples.isEmpty) throw StateError('No worker-compatible SVG selected');
    return samples;
  }

  /// Times result arrival; validation and diagnostics follow the probe.
  /// 测至可用结果到达；校验及诊断在探针后执行。
  Future<_Timing> _measure(
    String mode,
    String source,
    _Signature expected,
    String name,
    int trial,
  ) async {
    final connection = mode == _m3 ? _Connection() : _worker;
    if (mode == _m2 || mode == _m5) {
      SvgxDocumentCache.instance.clear();
    }
    if (mode != _m5) {
      connection.prepare(copy: mode == _m2, once: mode == _m3);
    }
    final probe = _Probe();
    final latency = Stopwatch()..start();
    late Object result;
    late int total;
    try {
      if (mode == _m5) {
        result =
            (await SvgxDocumentCache.instance
                    .getOrParseAsync(source)
                    .timeout(_timeout))
                .document;
      } else {
        result = await (mode == _m3
            ? connection.transfer(source)
            : connection.request(mode, source));
      }
      latency.stop();
      total = latency.elapsedMicroseconds;
    } finally {
      latency.stop();
      await probe.finish();
      if (mode == _m3) await connection.close();
    }
    final document = result is _ExitReply
        ? result.document
        : result is SvgDocument
        ? result
        : null;
    final valid = mode == _m1
        ? result is int && result == expected.timelines
        : document != null && expected.matches(document);
    if (!valid) {
      _errors++;
      _emit(
        '$_mismatch name=${jsonEncode(name)} mode=$mode trial=$trial '
        'expected=${jsonEncode('$expected')} '
        'actual=${jsonEncode(document == null ? '$result' : '${_Signature(document)}')}',
      );
    }
    return _Timing(
      total,
      probe.maxGapUs,
      sendUs: mode == _m2 ? await connection.sendUs : null,
      startUs: result is _ExitReply ? result.startUs : null,
      initUs: result is _ExitReply ? result.initUs : null,
      initSelfCheckUs: result is _ExitReply ? result.initSelfCheckUs : null,
      parseUs: result is _ExitReply ? result.parseUs : null,
      check: valid ? _ok : _mismatch,
    );
  }

  DurationStats _stats(Iterable<int> us) => DurationStats.fromDurations(
    us.map((v) => Duration(microseconds: v)).toList(),
  );

  String _pair(String label, Iterable<int> values) {
    final stats = _stats(values);
    return '${label}_median_us=${stats.p50Us.toInt()} ${label}_max_us=${stats.maxUs.toInt()}';
  }

  /// Time only the synchronous call; consume and check results afterwards.
  /// 仅计同步调用；返回值在停表后使用和校验。
  ({T value, int us}) _syncTime<T>(T Function() action) {
    final watch = Stopwatch()..start();
    final value = action();
    watch.stop();
    return (value: value, us: watch.elapsedMicroseconds);
  }

  /// A cold sync parse/cache pair; clearing and correctness checks are untimed.
  /// 冷源同步解析或缓存调用；清缓存及正确性校验不计时。
  int _syncParse(String source, _Signature expected, {required bool cached}) {
    SvgxDocumentCache.instance.clear();
    final timed = _syncTime(
      () => cached
          ? SvgxDocumentCache.instance.getOrParse(source).document
          : parseAnimatedSvgDocument(source),
    );
    if (!expected.matches(timed.value)) {
      throw StateError(
        '$_mismatch mode=$_m6 cached=$cached expected=$expected',
      );
    }
    return timed.us;
  }

  /// Seven serial CPU trials after async measurements, with no active probe.
  /// 异步测量结束后串行测七轮 CPU 分段，不运行定时器探针。
  Future<void> _measureExtras(_Sample sample) async {
    if (mounted) setState(() => _progress = '${sample.name} $_m6');
    final document = parseAnimatedSvgDocument(_fresh(sample));
    final expected = _Signature(document);
    final times = <String, List<int>>{
      for (final metric in _extraMetrics) metric: [],
    };
    for (var trial = 0; trial < _trials; trial++) {
      await Future<void>.delayed(_settle);
      final source = _fresh(sample);
      final estimate = _syncTime(() {
        // ignore: invalid_use_of_visible_for_testing_member
        return estimateDocumentParseNodeCount(source);
      });
      final regex = _syncTime(() => _imageElement.hasMatch(source));
      final images = _syncTime(() => documentHasImages(document));
      if (estimate.value != sample.tags || regex.value || images.value) {
        throw StateError('$_mismatch mode=$_m6 image/count checks');
      }
      final parseSource = _fresh(sample);
      final cacheSource = _fresh(sample);
      late int parseUs, cacheUs;
      // Alternate the sync pair too, reducing fixed parse/cache order bias.
      // 同步对也交替先后，减轻解析/缓存固定顺序偏差。
      if (trial.isEven) {
        parseUs = _syncParse(parseSource, expected, cached: false);
        cacheUs = _syncParse(cacheSource, expected, cached: true);
      } else {
        cacheUs = _syncParse(cacheSource, expected, cached: true);
        parseUs = _syncParse(parseSource, expected, cached: false);
      }
      final cacheDeltaUs = cacheUs - parseUs;
      // _remember includes documentHasImages: count the walk only once.
      // _remember 包含 documentHasImages：求和只计一次遍历，保留有符号噪声。
      final insertUs = cacheDeltaUs - images.us;
      final sumUs = estimate.us + regex.us + images.us + insertUs;
      final values = [
        estimate.us,
        regex.us,
        images.us,
        parseUs,
        cacheUs,
        cacheDeltaUs,
        insertUs,
        sumUs,
      ];
      for (var i = 0; i < _extraMetrics.length; i++) {
        times[_extraMetrics[i]]!.add(values[i]);
      }
      SvgxDocumentCache.instance.clear();
    }
    for (final metric in _extraMetrics) {
      _extraTimes[metric]!.addAll(times[metric]!);
    }
    _emit(
      'FILE name=${jsonEncode(sample.name)} tags=${sample.tags} mode=$_m6 n=$_trials '
      '${_extraMetrics.map((metric) => _pair(metric, times[metric]!)).join(' ')} '
      'check=$_ok',
    );
  }

  /// Seven work trials and seven latency-matched idle trials per mode.
  /// 每工作模式七次测量，各配七次等延迟空闲窗口。
  Future<void> _measureFile(_Sample sample) async {
    if (mounted) setState(() => _progress = sample.name);
    final expected = _Signature(parseAnimatedSvgDocument(_fresh(sample)));
    final timingsByMode = <String, List<_Timing>>{
      for (final mode in _modes) mode: [],
    };
    for (final mode in _modes) {
      final timings = timingsByMode[mode]!;
      if (mode != _m5) {
        for (var trial = 0; trial < _trials; trial++) {
          final roundModes = mode == _m2
              ? ((trial + _measured).isEven ? [_m2, _m5] : [_m5, _m2])
              : [mode];
          for (final roundMode in roundModes) {
            await Future<void>.delayed(_settle);
            timingsByMode[roundMode]!.add(
              await _measure(
                roundMode,
                _fresh(sample),
                expected,
                sample.name,
                trial + 1,
              ),
            );
          }
        }
      }
      final extras = switch (mode) {
        _m2 => _pair('send', timings.map((t) => t.sendUs!)),
        _m3 => [
          _pair('startup', timings.map((t) => t.startUs!)),
          _pair('init', timings.map((t) => t.initUs!)),
          _pair('init_selfcheck', timings.map((t) => t.initSelfCheckUs!)),
          _pair('parse', timings.map((t) => t.parseUs!)),
        ].join(' '),
        _m5 => 'reply=document',
        _ => 'reply=int',
      };
      _emit(
        'FILE name=${jsonEncode(sample.name)} tags=${sample.tags} mode=$mode n=${timings.length} '
        '${_pair(_totalMetric, timings.map((t) => t.totalUs))} '
        '${_pair(_gapMetric, timings.map((t) => t.gapUs))} $extras '
        'check=${timings.every((t) => t.check == _ok) ? _ok : _mismatch}',
      );
      (_gaps[mode] ??= []).addAll(timings.map((t) => t.gapUs));
      final idle = <_Timing>[];
      for (final timing in timings) {
        await Future<void>.delayed(_settle);
        final probe = _Probe();
        final latency = Stopwatch()..start();
        await Future<void>.delayed(Duration(microseconds: timing.totalUs));
        latency.stop();
        await probe.finish();
        idle.add(_Timing(latency.elapsedMicroseconds, probe.maxGapUs));
      }
      (_idleGaps[mode] ??= []).addAll(idle.map((t) => t.gapUs));
      _emit(
        'FILE name=${jsonEncode(sample.name)} tags=${sample.tags} mode=$_m0 matched=$mode n=${idle.length} '
        '${_pair('target', timings.map((t) => t.totalUs))} '
        '${_pair(_totalMetric, idle.map((t) => t.totalUs))} '
        '${_pair(_gapMetric, idle.map((t) => t.gapUs))}',
      );
    }
    _measured++;
  }

  void _summary(String mode, List<int> gaps, {String? matched}) {
    final stats = _stats(gaps);
    _emit(
      'SUMMARY mode=$mode${matched == null ? '' : ' matched=$matched'} n=${stats.count} '
      'gap_p50_us=${stats.p50Us.toInt()} gap_p90_us=${stats.p90Us.toInt()} '
      'gap_max_us=${stats.maxUs.toInt()}',
    );
  }

  /// Always stops both resident workers before finishing. / 完成前始终停止两个常驻 worker。
  Future<void> _run() async {
    _emit('=== BEGIN ANIM TRANSFER BENCH REPORT ===');
    _emit(
      'corpus_dir=${jsonEncode(_corpusDir)} threshold=$_threshold trials=$_trials unit=us',
    );
    _emit(
      'cold=unique_comment cache=M5_clear_before_each_M2_and_M5 '
      'excludes=io,decode,precount,comment,selection,validation,clear,warmup '
      'M5_includes=library_count,image_regex,remember',
    );
    _emit(
      'gap=1ms_periodic_start_and_post_completion_tick idle=seven_per_file_per_mode_matched_by_trial_latency',
    );
    _emit(
      'order=M1,M0(M1),interleaved_7_rounds(M2/M5_alternate_first),'
      'M0(M2),M0(M5),M3,M0(M3);after_all_files=M6_serial '
      'percentiles=rounded_index',
    );
    _emit(
      'M3_startup=spawn_to_entry_copied_running_Stopwatch init=RustLib.init_only init_selfcheck=init_plus_native_checks',
    );
    _emit('M4=不可测/unavailable reason=no_Dart_hook_before_VM_deserialization');
    _emit(
      'GUIDE M1-M0: allocation/GC/scheduling proxy; M2-M1 reduced in M3: copying hypothesis, not proof.',
    );
    _emit('GUIDE 调度间隙非帧耗时；GC/调度噪声影响差值；M3 另含启动及初始化，send 不等于接收端反序列化。');
    _emit(
      'GUIDE M5=getOrParseAsync_full_path_warmed_library_worker '
      'M6=serial_CPU_Stopwatch_phases_seven_cold_trials '
      'M5 为库全路径（预热 worker），M6 为主线程串行分段微秒计时；M5 无库内 send 计时。',
    );
    try {
      await _worker.start();
      final samples = await _load();
      await _warmLibraryWorker();
      for (final sample in samples) {
        try {
          await _measureFile(sample);
        } catch (error) {
          _error(error, file: sample.name);
        }
      }
      for (final mode in _modes) {
        _summary(mode, _gaps[mode] ?? []);
        _summary(_m0, _idleGaps[mode] ?? [], matched: mode);
      }
      _summary(_m0, _idleGaps.values.expand((values) => values).toList());
      for (final sample in samples) {
        try {
          await _measureExtras(sample);
        } catch (error) {
          _error(error, file: sample.name);
        }
      }
      final gapDeltaUs =
          _stats(_gaps[_m5] ?? []).p50Us.toInt() -
          _stats(_gaps[_m2] ?? []).p50Us.toInt();
      _emit(
        'SUMMARY mode=$_m6 n=${_extraTimes[_extraSumMetric]!.length} '
        '${_extraMetrics.map((metric) => _pair(metric, _extraTimes[metric]!)).join(' ')} '
        'm5_minus_m2_gap_median_us=$gapDeltaUs',
      );
    } catch (error) {
      _error(error);
    } finally {
      try {
        await _worker.close();
      } catch (error) {
        _error(error);
      }
      SvgxDocumentCache.instance.clear();
      try {
        await DocumentParseWorker.instance.dispose();
      } catch (error) {
        _error(error);
      }
    }
    _emit(
      '读数指引/READING_GUIDE: M6 extra_sum=estimate+image_regex+document_images+'
      'remember_insert_est=estimate+image_regex+cache_delta; '
      'cache_delta=sync_cache-sync_parse 已含图片遍历，remember_insert_est 扣除遍历以免重复；'
      '将 extra_sum_median_us 与 (M5 − M2) 的 m5_minus_m2_gap_median_us 对照。'
      'CPU sum vs maximum-gap difference is not additive attribution / '
      'CPU 分段和与最大调度间隙的中位差不能线性归因；差值可为负，'
      '仍含冷串哈希、Future、GC、设备漂移及两次解析噪声；空缓存不覆盖淘汰成本。',
    );
    _emit(
      'status=${_errors == 0 ? _ok : 'error'} measured_files=$_measured errors=$_errors',
    );
    _emit('=== END ANIM TRANSFER BENCH REPORT ===');
    if (mounted) {
      setState(() => _progress = _errors == 0 ? 'done' : 'failed: $_errors');
    }
    if (autoExitAfterReport) exit(_errors == 0 ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: Text('anim_transfer: $_progress'))),
  );
}
