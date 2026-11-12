// Cold large-document benchmark (`LIB=anim_async`), on the UI isolate.
// Select ALL sources with estimateDocumentParseNodeCount >= the library cutoff.
// I/O, decoding, tag counting, unique comments, cache clears and resets are untimed.
// Sync: one warmup + seven cold parses. Async: one unrelated worker warmup for
// the whole corpus, then seven cold sources per file. Cold worker: three resets
// and first requests on the largest selected source, including Rust init/self-check.
// Main already initializes Rust; the worker initializes its own native backend.
//
// 大文档冷解析基准，全部选择标签估算数达到库阈值的源。读文件、解码、计数、唯一
// 注释、清缓存及重置不计时。同步预热一次测七次；worker 用无关源只预热一次，逐文件
// 测七次；最大样本另重置三次测冷 worker，包含独立 Rust 初始化及自检。
//
// A 1ms periodic timer measures actual callback gaps using Stopwatch, including
// the start boundary and the first tick AFTER completion (not Future latency).
// Thus even synchronous fallback/short futures cannot hide a blocked first tick.
// It is a scheduling proxy, not frame timing or exact CPU time: OS resolution,
// GC, other UI work and the final tick contribute. Seven idle windows match the
// longest warm-async latency at each trial index across files. Report raw gaps
// plus max(0, gap - idle max) as a conservative noise comparison, not causality.
// The timer/Zone observer also adds small measurement overhead.
//
// 1ms 定时器用 Stopwatch 测实际回调间隙，包含起点和完成后的第一个 tick，防止同步
// 回退或短 Future 漏测。它是调度指标，受系统粒度、GC、其他 UI 工作及尾 tick 影响，
// 不等于帧耗时或精确 CPU 时间。七次空闲窗口逐次匹配所有文件同轮异步延迟的最大值；
// 保留原值并报告扣空闲 max 后的非负差，仅供噪声比较，不能作因果归因。
// 定时器及 Zone 观察器自身也会引入少量测量开销。
//
// A Zone observes (id, SvgDocument) delivery and async errors WITHOUT replacing
// errors. request/start deltas alone only prove an attempt: a delivered document
// with no worker/root-only error proves worker use. Cooldown/image bypass and
// handled worker errors are explicitly fallback. receive_to_future_us spans
// listener entry through dispatch, microtasks and cache insertion to completion;
// VM message copying before listener entry is excluded. Exact cache CPU time has
// no public hook, so cache_only_us=unavailable; no library instrumentation added.
//
// Zone 观察返回消息及异步错误，不替换错误；请求/启动计数只证明尝试，收到文档且无
// worker/主 isolate 限制错误才确认 worker used；冷却、图片绕过或内部错误均报 fallback。
// receive_to_future_us 从监听入口到 Future 完成，包含分发、微任务及缓存入库，排除
// 入口前 VM 消息复制；库无独立缓存计时钩子，cache_only_us 明示不可用，不修改库。
//
// Reproduce from benchmark/bench_app in PowerShell / 在该目录复现：
// Windows (third-party corpus stays external / 第三方素材不入库):
//   $corpusDir = 'C:\Users\jelon\AppData\Local\Temp\claude\E--workspaces-dart-labs-xvg\93aa9a18-7032-40b5-84a7-7704e2b7f8bf\scratchpad\css_samples'
//   $reportFile = Join-Path $PWD 'build\anim_async_report.txt'
//   $env:PATH = 'E:\workspaces\dart-labs-xvg\xvg\prebuilt\windows\x64;' + $env:PATH
//   flutter run -d windows --profile --dart-define=LIB=anim_async "--dart-define=CORPUS_DIR=$corpusDir" "--dart-define=REPORT_FILE=$reportFile" --dart-define=AUTOEXIT=true
// Android (device operator only / 仅供真机操作者执行):
//   flutter build apk --profile --dart-define=LIB=anim_async --dart-define=AUTOEXIT=true --dart-define=REPORT_FILE=/sdcard/Android/data/com.example.bench_app/files/anim_async_report.txt
//   adb -s 7NQBB23606003715 install -r build/app/outputs/flutter-apk/app-profile.apk
//   adb -s 7NQBB23606003715 shell am start -n com.example.bench_app/.MainActivity
//   adb -s 7NQBB23606003715 shell mkdir -p /sdcard/Android/data/com.example.bench_app/files/corpus_css
//   adb -s 7NQBB23606003715 push "$corpusDir/." /sdcard/Android/data/com.example.bench_app/files/corpus_css
//   adb -s 7NQBB23606003715 logcat -c
//   adb -s 7NQBB23606003715 shell am start -n com.example.bench_app/.MainActivity
//   adb -s 7NQBB23606003715 logcat -s flutter:I
//   adb -s 7NQBB23606003715 pull /sdcard/Android/data/com.example.bench_app/files/anim_async_report.txt build/anim_async_android_report.txt
// Wait for the initial missing-corpus launch to exit before mkdir/push; existing
// MainActivity creates the owned external parent. dir/. avoids nesting. No storage
// permission needed. Reports append: use a fresh path or BEGIN/END delimiters.
// 首次缺语料启动退出后再 mkdir/push；现有 MainActivity 创建属主正确的外部父目录。
// 推送 /. 避免多套目录，无需存储权限。报告追加写入，可换路径或按 BEGIN/END 分轮。

// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:xvg/src/animation/document_parse_worker.dart';
import 'package:xvg/src/animation/svg_document_cache.dart';
import 'package:xvg/src/animation/svg_document_parser.dart';

import 'report_sink.dart';
import 'stats.dart';

/// External corpus, never bundled. / 外部语料，不打包。
const _corpusDir = String.fromEnvironment(
  'CORPUS_DIR',
  defaultValue: '/sdcard/Android/data/com.example.bench_app/files/corpus_css',
);

/// Sync warmups per file. / 每文件同步预热次数。
const _warmups = 1;

/// Measured trials per file and idle control. / 每文件及空闲对照的轮数。
const _trials = 7;

/// Independent cold worker lifetimes. / 独立冷 worker 生命周期数。
const _coldTrials = 3;

/// Requested timer period, not guaranteed precision. / 请求周期，不保证精度。
const _tickPeriod = Duration(milliseconds: 1);

/// Untimed yield for pending frames between trials. / 轮间让帧完成，不计时。
const _settle = Duration(milliseconds: 20);

/// Comment insertion point. / 唯一注释插入点。
const _svgClose = '</svg>';

/// Confirmed worker success label. / 确认 worker 成功的标签。
const _workerUsed = 'worker used';

/// Local parse or failed-worker label. / 本地解析或 worker 失败标签。
const _fallback = 'fallback';

/// Missing measurement label. / 不可测标签。
const _unavailable = 'unavailable';

/// Shared cache entry point. / 共用缓存入口。
final _cache = XvgDocumentCache.instance;

/// Loaded source with untimed metadata. / 已加载源及不计时元数据。
class _Sample {
  /// Retains one external file. / 保存一个外部文件。
  const _Sample(
    this.name,
    this.source,
    this.bytes,
    this.tags,
    this.closeOffset,
  );

  /// File name, source, byte size, tag estimate and comment offset.
  /// 文件名、源串、字节数、标签估算数及注释位置。
  final String name, source;
  final int bytes, tags, closeOffset;
}

/// UI timer probe and passive worker diagnostics. / UI 定时器及被动 worker 诊断。
class _Probe {
  /// Starts immediately before the async call or idle window. / 紧邻异步调用或空闲窗口启动。
  _Probe() {
    timer = Timer.periodic(_tickPeriod, (_) {
      final now = watch.elapsedMicroseconds;
      final gap = now - lastUs;
      if (gap > maxGapUs) maxGapUs = gap;
      lastUs = now;
      ticks++;
      if (finishing) {
        timer.cancel();
        stopped.complete();
      }
    });
  }

  /// Monotonic window clock and actual callback statistics. / 单调窗口时钟及实际回调统计。
  final Stopwatch watch = Stopwatch()..start();
  late final Timer timer;
  int lastUs = 0, maxGapUs = 0, ticks = 0;

  /// Starts at worker reply listener entry, when observable. / 可观察时从 worker 回包监听入口开始。
  Stopwatch? receiveWatch;

  /// Internal errors that the cache can handle by falling back. / 缓存可能内部捕获并回退的错误。
  final List<Object> failures = [];

  /// Includes the first post-completion timer tick. / 包含完成后的第一个定时 tick。
  bool finishing = false;
  final Completer<void> stopped = Completer<void>();

  /// Closes only after the trailing tick, even for synchronous futures.
  /// 即使 Future 同步完成，也等尾 tick 后关闭。
  Future<void> finish() {
    finishing = true;
    return stopped.future;
  }
}

/// One async request, including routing evidence. / 单次异步请求，包含路由证据。
class _AsyncTiming {
  /// Stores completed measurements. / 保存完成的测量。
  const _AsyncTiming(
    this.total,
    this.gap,
    this.receive,
    this.requests,
    this.starts,
    this.route,
    this.reason,
  );

  /// Latency, maximum UI gap and receive-to-completion interval.
  /// 总延迟、UI 最大间隙、接收到完成的区间。
  final Duration total, gap;
  final Duration? receive;

  /// Counter deltas, confirmed route and fallback reason. / 计数增量、确认的路由及回退原因。
  final int requests, starts;
  final String route, reason;
}

/// First-parse sync versus worker benchmark screen. / 同步与 worker 首次解析基准屏幕。
class AnimAsyncBenchScreen extends StatefulWidget {
  /// Creates the benchmark. / 创建基准。
  const AnimAsyncBenchScreen({super.key});

  @override
  State<AnimAsyncBenchScreen> createState() => _AnimAsyncBenchScreenState();
}

/// Runs sequentially to avoid overlapping requests or timers. / 串行运行，避免请求或定时器重叠。
class _AnimAsyncBenchScreenState extends State<AnimAsyncBenchScreen> {
  /// Unique comments across every warmup and measurement. / 所有预热和测量的唯一注释序号。
  int _serial = 0;

  /// Active measurement observed by the runner's Zone. / 由运行 Zone 观察的当前测量。
  _Probe? _active;

  /// Error count, measured-file count and visible progress. / 错误数、已测文件数和界面进度。
  int _errors = 0, _measured = 0;
  String _progress = 'Waiting for first frame';

  /// Corpus distributions and matched idle targets. / 语料分布及匹配的空闲目标窗口。
  final List<Duration> _syncMaxima = [], _asyncGaps = [];
  final _idleTargets = List<Duration>.filled(_trials, _tickPeriod);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        runZoned(
          _run,
          zoneSpecification: ZoneSpecification(
            registerUnaryCallback: _observeCallback,
            errorCallback: (self, parent, zone, error, stack) {
              if (error is DocumentParseWorkerUnavailable ||
                  error is RootIsolateParseError) {
                _active?.failures.add(error);
              }
              return parent.errorCallback(zone, error, stack);
            },
          ),
        ),
      );
    });
  }

  /// Observes the existing receive listener without changing its result.
  /// 观察现有接收监听，不改变返回值。
  R Function(T) _observeCallback<R, T>(
    Zone self,
    ZoneDelegate parent,
    Zone zone,
    R Function(T) callback,
  ) => parent.registerUnaryCallback(zone, (T value) {
    if (value is (int, SvgDocument)) {
      _active?.receiveWatch ??= Stopwatch()..start();
    }
    return callback(value);
  });

  /// Short lines for both logcat and REPORT_FILE. / 同时供 logcat 和 REPORT_FILE 使用的短行。
  void _emit(String line) => emitReport('$line\n');

  /// Records explicit failure instead of a plausible zero. / 明确失败，避免貌似有效的零结果。
  void _error(Object error, {String? file}) {
    _errors++;
    _emit('ERROR file=${jsonEncode(file)} message=${jsonEncode('$error')}');
  }

  /// Fresh source and cleared cache, always outside timing. / 新源串及清缓存，始终不计时。
  String _fresh(_Sample sample) {
    final source = sample.source.replaceRange(
      sample.closeOffset,
      sample.closeOffset,
      '<!--anim_async_r${_serial++}-->',
    );
    _cache.clear();
    return source;
  }

  /// Bench-only reset also clears failure cooldown; clear/dispose alone cannot.
  /// 基准专用重置还清除失败冷却，单纯 clear/dispose 无法做到。
  Future<void> _reset() async {
    // ignore: invalid_use_of_visible_for_testing_member
    await _cache.debugResetAsyncParsing();
  }

  /// Reads lifecycle hooks only; attempts are not treated as successes.
  /// 仅读取生命周期钩子，不把尝试等同成功。
  ({int requests, int starts}) _counters() {
    final worker = DocumentParseWorker.instance;
    return (
      // ignore: invalid_use_of_visible_for_testing_member
      requests: worker.debugRequestCount,
      // ignore: invalid_use_of_visible_for_testing_member
      starts: worker.debugStartCount,
    );
  }

  /// Measures a cold API call, retaining a trailing timer tick on every outcome.
  /// 测冷源 API 调用，任何结果都保留尾 tick。
  Future<_AsyncTiming> _measureAsync(String source) async {
    final before = _counters();
    final probe = _Probe();
    _active = probe;
    final latencyWatch = Stopwatch()..start();
    late Duration total;
    Duration? receive;
    try {
      await _cache.getOrParseAsync(source);
      latencyWatch.stop();
      total = latencyWatch.elapsed;
      receive = probe.receiveWatch?.elapsed;
    } finally {
      latencyWatch.stop();
      _active = null;
      await probe.finish();
      probe.watch.stop();
    }
    final after = _counters();
    final requests = after.requests - before.requests;
    final starts = after.starts - before.starts;
    final used = requests == 1 && receive != null && probe.failures.isEmpty;
    final reason = used
        ? 'reply_observed_no_worker_error'
        : probe.failures.isNotEmpty
        ? probe.failures
              .map((error) {
                if (error is DocumentParseWorkerUnavailable) {
                  return '${error.kind.name}: ${error.cause}';
                }
                return 'root_only: ${(error as RootIsolateParseError).cause}';
              })
              .join(' | ')
        : requests == 0
        ? 'local_bypass_image_or_cooldown'
        : 'reply_not_observed';
    if (requests > 0 && receive == null && probe.failures.isEmpty) {
      throw StateError('Cannot confirm worker result: $reason');
    }
    return _AsyncTiming(
      total,
      Duration(microseconds: probe.maxGapUs),
      receive,
      requests,
      starts,
      used ? _workerUsed : _fallback,
      reason,
    );
  }

  /// Reports a distribution with the shared rounded-index percentile helper.
  /// 使用共用四舍五入索引分位算法报告分布。
  void _summary(String metric, List<Duration> values) {
    if (values.isEmpty) return;
    final stats = DurationStats.fromDurations(values);
    _emit(
      'SUMMARY metric=$metric n=${stats.count} '
      'p50_us=${stats.p50Us.toInt()} p90_us=${stats.p90Us.toInt()} '
      'p99_us=${stats.p99Us.toInt()} max_us=${stats.maxUs.toInt()}',
    );
  }

  /// Reads all eligible external SVGs, counting tags before measurements.
  /// 读取所有符合条件的外部 SVG，计数在测量前完成。
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
        final bytes = await file.readAsBytes();
        final source = utf8.decode(bytes);
        // Bench selection must exactly match the library heuristic.
        // 基准筛选须与库的估算方法一致。
        // ignore: invalid_use_of_visible_for_testing_member
        final tags = estimateDocumentParseNodeCount(source);
        if (tags < documentParseWorkerNodeThreshold) continue;
        final closeOffset = source.lastIndexOf(_svgClose);
        if (closeOffset < 0) {
          throw FormatException('Missing closing $_svgClose tag');
        }
        samples.add(_Sample(name, source, bytes.length, tags, closeOffset));
      } catch (error) {
        _error(error, file: name);
      }
    }
    _emit('corpus_files=${files.length} selected_files=${samples.length}');
    if (samples.isEmpty) {
      throw StateError('No SVG meets the worker tag threshold');
    }
    return samples;
  }

  /// Measures one sync warmup, seven sync calls and seven warm-worker calls.
  /// 测一次同步预热、七次同步调用及七次已预热 worker 调用。
  Future<void> _measureFile(_Sample sample) async {
    if (mounted) setState(() => _progress = sample.name);
    final sync = <Duration>[];
    for (var trial = 0; trial < _warmups + _trials; trial++) {
      await Future<void>.delayed(_settle);
      final source = _fresh(sample);
      final watch = Stopwatch()..start();
      _cache.getOrParse(source);
      watch.stop();
      if (trial >= _warmups) sync.add(watch.elapsed);
    }
    final async = <_AsyncTiming>[];
    for (var trial = 0; trial < _trials; trial++) {
      await Future<void>.delayed(_settle);
      final timing = await _measureAsync(_fresh(sample));
      async.add(timing);
      if (timing.total > _idleTargets[trial]) {
        _idleTargets[trial] = timing.total;
      }
    }
    final syncStats = DurationStats.fromDurations(sync);
    final totalStats = DurationStats.fromDurations(
      async.map((t) => t.total).toList(),
    );
    final gaps = async.map((t) => t.gap).toList();
    final gapStats = DurationStats.fromDurations(gaps);
    final receive = async.map((t) => t.receive).whereType<Duration>().toList();
    final receiveMedian = receive.isEmpty
        ? _unavailable
        : '${DurationStats.fromDurations(receive).p50Us.toInt()}';
    final minUs = sync
        .map((d) => d.inMicroseconds)
        .reduce((a, b) => a < b ? a : b);
    final used = async.where((t) => t.route == _workerUsed).length;
    _syncMaxima.add(Duration(microseconds: syncStats.maxUs.toInt()));
    _asyncGaps.addAll(gaps);
    _measured++;
    _emit(
      'FILE name=${jsonEncode(sample.name)} tags=${sample.tags} '
      'chars=${sample.source.length} bytes=${sample.bytes} '
      'sync_min_us=$minUs sync_median_us=${syncStats.p50Us.toInt()} '
      'sync_max_us=${syncStats.maxUs.toInt()} '
      'async_total_median_us=${totalStats.p50Us.toInt()} '
      'async_gap_median_us=${gapStats.p50Us.toInt()} async_gap_max_us=${gapStats.maxUs.toInt()} '
      'worker_used=$used/$_trials fallback=${_trials - used}/$_trials',
    );
    _emit(
      'RECEIVE name=${jsonEncode(sample.name)} receive_to_future_median_us=$receiveMedian '
      'observed=${receive.length}/$_trials cache_only_us=$_unavailable',
    );
    for (var trial = 0; trial < async.length; trial++) {
      final timing = async[trial];
      if (timing.route == _fallback) {
        _emit(
          'FALLBACK name=${jsonEncode(sample.name)} trial=${trial + 1} '
          'requests=${timing.requests} starts=${timing.starts} '
          'reason=${jsonEncode(timing.reason)}',
        );
      }
    }
  }

  /// Seven matched idle controls, then corpus and noise-adjusted summaries.
  /// 七次匹配的空闲对照，再输出语料与扣噪声汇总。
  Future<void> _idleAndSummaries() async {
    final idleGaps = <Duration>[];
    for (var trial = 0; trial < _trials; trial++) {
      await Future<void>.delayed(_settle);
      final probe = _Probe();
      await Future<void>.delayed(_idleTargets[trial]);
      await probe.finish();
      probe.watch.stop();
      idleGaps.add(Duration(microseconds: probe.maxGapUs));
      _emit(
        'IDLE trial=${trial + 1} target_us=${_idleTargets[trial].inMicroseconds} '
        'actual_us=${probe.watch.elapsedMicroseconds} ticks=${probe.ticks} '
        'gap_max_us=${probe.maxGapUs}',
      );
    }
    _summary('per_file_sync_max', _syncMaxima);
    _summary('all_warm_async_trial_max_gaps', _asyncGaps);
    _summary('idle_trial_max_gaps', idleGaps);
    final idleMax = DurationStats.fromDurations(idleGaps).maxUs.toInt();
    _summary(
      'warm_async_gap_minus_idle_max_clamped',
      _asyncGaps.map((gap) {
        final excess = gap.inMicroseconds - idleMax;
        return Duration(microseconds: excess > 0 ? excess : 0);
      }).toList(),
    );
  }

  /// Coordinates warm-worker, idle and cold-worker phases and always closes.
  /// 编排热 worker、空闲和冷 worker 阶段，并始终收尾。
  Future<void> _run() async {
    _emit('=== BEGIN ANIM ASYNC BENCH REPORT ===');
    _emit('corpus_dir=${jsonEncode(_corpusDir)}');
    _emit(
      'threshold=$documentParseWorkerNodeThreshold warmups=$_warmups trials=$_trials cold_trials=$_coldTrials unit=us',
    );
    _emit(
      'cold=unique_comment cache=clear_before_each_call excludes=io,decode,comment,clear,count,reset',
    );
    _emit(
      'gap=1ms_periodic_start_and_post_completion_tick percentiles=rounded_index',
    );
    _emit(
      'receive_to_future=listener_dispatch_microtasks_cache cache_only_us=$_unavailable excludes=vm_message_copy',
    );
    _emit(
      'worker_used=reply_observed_and_no_internal_worker_error counters=attempts_only',
    );
    try {
      final samples = await _load();
      await _reset();
      final warmSource =
          '<svg xmlns="http://www.w3.org/2000/svg">'
          '${List.filled(documentParseWorkerNodeThreshold, '<g/>').join()}'
          '$_svgClose';
      final warmSample = _Sample(
        'unrelated_warmup',
        warmSource,
        utf8.encode(warmSource).length,
        documentParseWorkerNodeThreshold + 1,
        warmSource.lastIndexOf(_svgClose),
      );
      final warmup = await _measureAsync(_fresh(warmSample));
      _emit(
        'WARMUP route=${jsonEncode(warmup.route)} requests=${warmup.requests} starts=${warmup.starts} reason=${jsonEncode(warmup.reason)}',
      );
      for (final sample in samples) {
        try {
          await _measureFile(sample);
        } catch (error) {
          _error(error, file: sample.name);
        } finally {
          _cache.clear();
        }
      }
      await _idleAndSummaries();
      final largest = samples.reduce((a, b) => a.tags >= b.tags ? a : b);
      for (var trial = 0; trial < _coldTrials; trial++) {
        try {
          await _reset();
          await Future<void>.delayed(_settle);
          final timing = await _measureAsync(_fresh(largest));
          _emit(
            'COLD_WORKER trial=${trial + 1} name=${jsonEncode(largest.name)} tags=${largest.tags} '
            'total_us=${timing.total.inMicroseconds} gap_max_us=${timing.gap.inMicroseconds} '
            'receive_to_future_us=${timing.receive?.inMicroseconds ?? _unavailable} '
            'route=${jsonEncode(timing.route)} requests=${timing.requests} starts=${timing.starts} '
            'reason=${jsonEncode(timing.reason)}',
          );
        } catch (error) {
          _error(error, file: largest.name);
        }
      }
    } catch (error) {
      _error(error);
    } finally {
      try {
        await _reset();
      } catch (error) {
        _error(error);
      }
    }
    _emit(
      'status=${_errors == 0 ? 'ok' : 'error'} measured_files=$_measured errors=$_errors',
    );
    _emit('=== END ANIM ASYNC BENCH REPORT ===');
    if (mounted) {
      setState(
        () => _progress = _errors == 0 ? 'done' : 'failed: $_errors error(s)',
      );
    }
    if (autoExitAfterReport) exit(_errors == 0 ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: Text('anim_async: $_progress'))),
  );
}
