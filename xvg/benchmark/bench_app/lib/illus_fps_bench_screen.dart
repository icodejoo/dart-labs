// Full-width illustration playback benchmark (`LIB=illus_fps`), one external
// SVGator CSS file at a time, rather than a scrolling grid of small icons.
// Reports real raster-finish FPS and build/raster costs for business animations.
// 全屏宽插画播放基准：逐个播放外部 SVGator CSS 文件，测业务动画的实际帧率与
// build/raster 成本，区别于小图标滚动网格；第三方素材始终留在仓库之外。
//
// Each ready sample warms up for WARMUP_MS (1500), then measures PHASE_MS (5000).
// Finite samples restart at zero AFTER warmup, measuring min(PHASE_MS, settleTime)
// so completed/idle time never dilutes their costs. Infinite samples continue.
// Missing public duration information is reported as loops=unknown finite=unknown.
// CONC=2 uses independent controllers but the normal shared document cache:
// it measures two copies of the SAME source, not two distinct illustrations.
// 每份就绪样本先预热，再测量；有限动画预热后从零重播，仅测定格前的窗口，
// 无限动画连续测满窗口。公开时长信息不可用则标 unknown。CONC=2 使用独立控制器，
// 沿用正常文档缓存；测的是同源两份，不代表两个不同插画的成本。
// Fewer than two timed frames gives real_fps=n/a and is excluded from FPS ranks;
// a zero settling time has no active window. FPS measures engine throughput,
// not physical display presentation; delayed begins remain inside settleTime.
// 不足两帧时 FPS 标 n/a 并排除于 FPS 排名；稳定时刻为零则无活动窗口。
// FPS 表示引擎产帧吞吐，不是屏幕实际呈现；开始前的时间线延迟仍包含在稳定时刻内。
//
// One copy fills the logical screen width, centered with its intrinsic aspect
// ratio (very tall art may extend beyond the screen). Two copies fit into the
// upper/lower half-screen without distortion. Metadata parsing, I/O, warmup,
// unmount and the 300ms settling gap are outside the measurement window.
// 单份按固有比例铺满逻辑屏宽并居中（极高插画可能超出屏幕），双份等比适配上下
// 半屏；元数据解析、读文件、预热、卸载和 300ms 稳定间隔均不计入测量。
//
// Reproduce in benchmark/bench_app; commands for the device operator ONLY.
// 在 benchmark/bench_app 复现；以下命令仅由真机操作者执行。
//   $corpusDir = 'C:\path\outside-repository\css_samples'
//   flutter build apk --profile --target-platform android-arm64 --dart-define=LIB=illus_fps --dart-define=AUTOEXIT=true --dart-define=REPORT_FILE=/sdcard/Android/data/com.example.bench_app/files/illus_fps_report.txt
// Optional defines / 可选参数：CORPUS_DIR=<path> PHASE_MS=5000 WARMUP_MS=1500 QUALITY=exact|balanced CONC=1|2
//   adb -s 7NQBB23606003715 install -r build/app/outputs/flutter-apk/app-profile.apk
//   adb -s 7NQBB23606003715 shell am start -n com.example.bench_app/.MainActivity
// Wait for this first, missing-corpus launch to exit before mkdir/push.
// 首次无语料运行退出后再推送，MainActivity 会先创建属主正确的 files 父目录。
//   adb -s 7NQBB23606003715 shell mkdir -p /sdcard/Android/data/com.example.bench_app/files/corpus_css
//   adb -s 7NQBB23606003715 push "$corpusDir/." /sdcard/Android/data/com.example.bench_app/files/corpus_css
//   adb -s 7NQBB23606003715 logcat -c
//   adb -s 7NQBB23606003715 shell am start -n com.example.bench_app/.MainActivity
//   adb -s 7NQBB23606003715 logcat -s flutter:I
//   adb -s 7NQBB23606003715 pull /sdcard/Android/data/com.example.bench_app/files/illus_fps_report.txt build/illus_fps_android_report.txt
// Push dir/. copies contents without a nested directory; no storage permission.
// Reports append: use a fresh REPORT_FILE or separate runs by BEGIN/END markers.
// 推送目录末尾 /. 避免多套一层目录；不需存储权限。报告追加，换文件或按标记分轮。

// The requested public tag-count helper needs an implementation import and is
// annotated visibleForTesting; this benchmark intentionally uses that helper.
// 指定的公开计数函数位于实现路径且标记为测试用途；本基准按要求使用它。
// ignore_for_file: implementation_imports, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FramePhase;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:xvg/src/animation/svg_document_cache.dart'
    show estimateDocumentParseNodeCount;
import 'package:xvg/xvg.dart';

import 'frame_timing.dart';
import 'report_sink.dart';
import 'stats.dart';

const _corpusDir = String.fromEnvironment(
  'CORPUS_DIR',
  defaultValue: '/sdcard/Android/data/com.example.bench_app/files/corpus_css',
);
const _phaseMs = int.fromEnvironment('PHASE_MS', defaultValue: 5000);
const _warmupMs = int.fromEnvironment('WARMUP_MS', defaultValue: 1500);
const _phaseDuration = Duration(milliseconds: _phaseMs);
const _single = 1;
const _double = 2;
const _concurrency = int.fromEnvironment('CONC', defaultValue: _single);
const _balanced = 'balanced';
const _exact = 'exact';
const _quality = String.fromEnvironment('QUALITY', defaultValue: _balanced);
const _unknown = 'unknown';
const _finite = 'finite';
const _infinite = 'infinite';
const _unavailable = 'n/a';
const _ok = 'ok';
const _error = 'error';
const _buildMetric = 'build';
const _rasterMetric = 'raster';
const _settle = Duration(milliseconds: 300);
const _timeout = Duration(seconds: 30);
const _timingTimeout = Duration(seconds: 5);
const _budgetUs = 16600;
const _topCount = 10;
const _p10 = 0.10;
const _p50 = 0.50;
const _p90 = 0.90;
const _p99 = 0.99;

/// Timestamp-filtered timings, retaining delayed engine batches after unmount.
/// 按时间戳筛选帧，卸载后仍接收引擎延迟交付的批次。
class _TimingWindow {
  _TimingWindow(this.startUs, Duration duration)
    : endUs = startUs + duration.inMicroseconds {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  final int startUs;
  final int endUs;
  final _frames = <FrameTiming>[];
  final drained = Completer<void>();

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final stamp = timing.timestampInMicroseconds(FramePhase.vsyncStart);
      if (stamp >= startUs && stamp < endUs) _frames.add(timing);
      // Seeing a later frame proves all earlier timing batches have arrived.
      // 见到窗口之后的帧，才确认更早的帧计时已全部送达。
      if (stamp >= endUs && !drained.isCompleted) drained.complete();
    }
  }

  void dispose() => SchedulerBinding.instance.removeTimingsCallback(_onTimings);

  _FrameStats summarize() {
    final finishes =
        _frames
            .map(
              (frame) => frame.timestampInMicroseconds(FramePhase.rasterFinish),
            )
            .toList()
          ..sort();
    final elapsed = finishes.length < _double
        ? 0
        : finishes.last - finishes.first;
    return _FrameStats(
      frames: _frames.length,
      fps: elapsed <= 0
          ? null
          : (finishes.length - _single) *
                Duration.microsecondsPerSecond /
                elapsed,
      build: DurationStats.fromDurations(
        _frames.map((frame) => frame.buildDuration).toList(),
      ),
      raster: DurationStats.fromDurations(
        _frames.map((frame) => frame.rasterDuration).toList(),
      ),
      buildOver: _frames
          .where((frame) => frame.buildDuration.inMicroseconds > _budgetUs)
          .length,
      rasterOver: _frames
          .where((frame) => frame.rasterDuration.inMicroseconds > _budgetUs)
          .length,
      over: _frames
          .where(
            (frame) =>
                frame.buildDuration.inMicroseconds > _budgetUs ||
                frame.rasterDuration.inMicroseconds > _budgetUs,
          )
          .length,
    );
  }
}

/// Immutable measurement summary. / 不可变的测量汇总。
class _FrameStats {
  const _FrameStats({
    required this.frames,
    required this.fps,
    required this.build,
    required this.raster,
    required this.buildOver,
    required this.rasterOver,
    required this.over,
  });

  final int frames;
  final double? fps;
  final DurationStats build;
  final DurationStats raster;
  final int buildOver;
  final int rasterOver;
  final int over;
}

/// One source and its independent playback instances. / 一个源及其独立播放实例。
class _Sample {
  _Sample(this.name, this.source, this.aspectRatio, this.hasTimelines)
    : controllers = List.generate(
        _concurrency,
        (_) => XvgAnimationController(),
      );

  final String name;
  final String source;
  final double aspectRatio;
  final bool hasTimelines;
  final List<XvgAnimationController> controllers;
  final ready = Completer<void>();
  final _loaded = <int>{};
  Object? error;

  void onLoaded(int index) {
    _loaded.add(index);
    if (_loaded.length == _concurrency && !ready.isCompleted) ready.complete();
  }

  void fail(Object value) {
    error ??= value;
    if (!ready.isCompleted) ready.complete();
  }

  void check() {
    if (error != null) throw StateError('$error');
  }
}

/// Per-file data used by the final distributions and rankings.
/// 用于最终分布与排名的逐文件数据。
class _Result {
  const _Result(this.name, this.stats);

  final String name;
  final _FrameStats stats;
}

/// Sequential full-width illustration benchmark. / 顺序执行的全屏宽插画基准。
class IllusFpsBenchScreen extends StatefulWidget {
  const IllusFpsBenchScreen({super.key});

  @override
  State<IllusFpsBenchScreen> createState() => _IllusFpsBenchScreenState();
}

class _IllusFpsBenchScreenState extends State<IllusFpsBenchScreen> {
  _Sample? _sample;
  String _progress = 'illus_fps: starting';
  final _results = <_Result>[];
  int _errors = 0;
  int _fileCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  void _emit(String line) => emitReport('$line\n');

  void _reportError(Object error, {String? name}) {
    _errors++;
    _emit('ERROR name=${jsonEncode(name)} message=${jsonEncode('$error')}');
  }

  /// Schedules a boundary on the same raw engine clock as FrameTiming.
  /// 在与 FrameTiming 相同的引擎原始时钟上安排边界。
  Future<int> _frameBoundary(VoidCallback action) {
    final boundary = Completer<int>();
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (!mounted) {
        boundary.completeError(StateError('Benchmark screen disposed'));
        return;
      }
      try {
        action();
        boundary.complete(
          SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds,
        );
      } catch (error, stack) {
        boundary.completeError(error, stack);
      }
    });
    return boundary.future.timeout(_timingTimeout);
  }

  /// Measures playback only; dimensions come from the library's parsed viewport.
  /// 只测播放；显示比例取自库解析的视口尺寸。
  Future<void> _measureFile(File file) async {
    final name = file.uri.pathSegments.last;
    _Sample? sample;
    _TimingWindow? window;
    final previousErrorHandler = FlutterError.onError;
    try {
      final source = utf8.decode(await file.readAsBytes());
      final parsed = await XvgDocumentCache.instance
          .getOrParseAsync(source)
          .timeout(_timeout);
      final width = parsed.document.width;
      final height = parsed.document.height;
      if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
        throw FormatException('Invalid intrinsic SVG size: $width x $height');
      }
      final current = _Sample(
        name,
        source,
        width / height,
        parsed.document.timelines.isNotEmpty,
      );
      sample = current;
      // Framework paint/layout failures bypass Xvg.onError; retain both paths.
      // 框架绘制/布局异常不经过 Xvg.onError，两条错误路径都要记录。
      FlutterError.onError = (details) {
        current.fail(details.exception);
        previousErrorHandler?.call(details);
      };
      if (!mounted) return;
      setState(() {
        _sample = current;
        _progress = name;
      });
      await WidgetsBinding.instance.endOfFrame;
      // Static/no-timeline sources need not issue onLoaded: keep unknown metadata.
      // 静态/无时间线源不保证调用 onLoaded；保留 unknown 元数据回退。
      if (current.hasTimelines) await current.ready.future.timeout(_timeout);
      current.check();
      await Future<void>.delayed(Duration(milliseconds: _warmupMs));
      current.check();
      final info = current.controllers.first.info;
      final loops = info == null
          ? _unknown
          : info.loops
          ? _infinite
          : _finite;
      final duration = info != null && !info.loops
          ? Duration(
              microseconds: math.min(
                _phaseDuration.inMicroseconds,
                info.settleTime.inMicroseconds,
              ),
            )
          : _phaseDuration;
      await _frameBoundary(() {
        if (info != null && !info.loops) {
          for (final controller in current.controllers) {
            controller.stop();
            controller.play();
          }
        }
      }).then((start) => window = _TimingWindow(start, duration));
      await Future<void>.delayed(duration);
      current.check();
      await _unmount();
      // Unmount produces the later frame that flushes the final timing batch.
      // 卸载产生窗口之后的帧，用它确认最后一批帧计时已送达。
      await Future.wait([
        window!.drained.future.timeout(_timingTimeout),
        Future<void>.delayed(_settle),
      ]);
      current.check();
      final stats = window!.summarize();
      if (duration > Duration.zero && stats.frames == 0 && info != null) {
        throw StateError('No FrameTiming samples in active playback window');
      }
      _results.add(_Result(name, stats));
      final tags = estimateDocumentParseNodeCount(source);
      _emit(
        'FILE name=${jsonEncode(name)} tags=$tags chars=${source.length} '
        'loops=$loops finite=${info == null ? _unknown : !info.loops} '
        'settle_us=${info?.settleTime.inMicroseconds ?? _unavailable} '
        'window_us=${duration.inMicroseconds} restart=${info != null && !info.loops} '
        'conc=$_concurrency frames=${stats.frames} real_fps=${_number(stats.fps)} '
        '${_statsFields(_buildMetric, stats.build)} '
        '${_statsFields(_rasterMetric, stats.raster)} '
        'over16.6=${stats.over} framesOver16.6ms=${stats.over} '
        'build_over16.6=${stats.buildOver} raster_over16.6=${stats.rasterOver} '
        'fps_valid=${stats.fps != null}',
      );
    } catch (error) {
      _reportError(error, name: name);
    } finally {
      if (_sample != null && mounted) {
        await _unmount();
        await Future<void>.delayed(_settle);
      }
      window?.dispose();
      FlutterError.onError = previousErrorHandler;
      if (sample != null) {
        for (final controller in sample.controllers) {
          controller.dispose();
        }
      }
    }
  }

  Future<void> _unmount() async {
    if (!mounted) return;
    setState(() => _sample = null);
    await WidgetsBinding.instance.endOfFrame;
  }

  String _number(double? value) => value?.toStringAsFixed(3) ?? _unavailable;

  String _statsFields(String prefix, DurationStats stats) =>
      '${prefix}_avg=${_number(stats.avgUs)} '
      '${prefix}_p50=${_number(stats.p50Us)} '
      '${prefix}_p90=${_number(stats.p90Us)} '
      '${prefix}_p99=${_number(stats.p99Us)} '
      '${prefix}_max=${_number(stats.maxUs)} ${prefix}_n=${stats.count}';

  /// Rounded-index percentiles match stats.dart; each file has equal weight.
  /// 分位数沿用 stats.dart 的四舍五入索引；每文件等权重。
  void _distribution(String metric, List<double> values) {
    values.sort();
    double? percentile(double p) =>
        values.isEmpty ? null : values[((values.length - _single) * p).round()];
    _emit(
      'SUMMARY metric=$metric n=${values.length} '
      'min=${_number(values.isEmpty ? null : values.first)} '
      'p10=${_number(percentile(_p10))} p50=${_number(percentile(_p50))} '
      'p90=${_number(percentile(_p90))} p99=${_number(percentile(_p99))} '
      'max=${_number(values.isEmpty ? null : values.last)}',
    );
  }

  void _ranking(String order, List<_Result> results) {
    _emit('TABLE order=$order limit=$_topCount');
    for (var index = 0; index < math.min(_topCount, results.length); index++) {
      final result = results[index];
      _emit(
        'RANK order=$order rank=${index + _single} name=${jsonEncode(result.name)} '
        'real_fps=${_number(result.stats.fps)} '
        'raster_avg=${_number(result.stats.raster.avgUs)} '
        'build_avg=${_number(result.stats.build.avgUs)} frames=${result.stats.frames}',
      );
    }
  }

  Future<void> _run() async {
    _emit('=== BEGIN ILLUS FPS BENCH REPORT ===');
    _emit(
      'corpus_dir=${jsonEncode(_corpusDir)} phase_ms=$_phaseMs warmup_ms=$_warmupMs '
      'quality=$_quality conc=$_concurrency duration_unit=us fps_unit=frames_per_second',
    );
    _emit(
      'fps=(n-1)*1e6/(last_rasterFinish-first_rasterFinish) '
      'window=vsyncStart_in_[start,end) percentiles=rounded_index '
      'over16.6=build_or_raster_gt_16600us finite=restart_after_warmup '
      'rankings_exclude_unavailable_fps_or_empty_timings',
    );
    try {
      if (_phaseMs <= 0 ||
          _warmupMs < 0 ||
          (_concurrency != _single && _concurrency != _double) ||
          (_quality != _exact && _quality != _balanced)) {
        throw ArgumentError(
          'Expected PHASE_MS>0 WARMUP_MS>=0 CONC=1|2 QUALITY=exact|balanced',
        );
      }
      XvgAnimationQuality.defaultQuality = _quality == _exact
          ? XvgAnimationQuality.exact
          : XvgAnimationQuality.balanced;
      final channel = FrameTimingCollector();
      try {
        await warmUpFrameTimingChannel(channel);
        if (!channel.hasReceivedAnyTiming) {
          throw StateError('Engine FrameTiming channel did not become ready');
        }
      } finally {
        channel.dispose();
      }
      final directory = Directory(_corpusDir);
      final files = await directory
          .list(followLinks: false)
          .where(
            (entry) =>
                entry is File && entry.path.toLowerCase().endsWith('.svg'),
          )
          .cast<File>()
          .toList();
      files.sort(
        (a, b) => a.uri.pathSegments.last.compareTo(b.uri.pathSegments.last),
      );
      _fileCount = files.length;
      if (files.isEmpty) {
        throw FileSystemException('Corpus contains no *.svg files', _corpusDir);
      }
      _emit('corpus_files=$_fileCount');
      for (final file in files) {
        if (!mounted) return;
        await _measureFile(file);
      }
    } catch (error) {
      _reportError(error);
    }
    final fpsResults = _results.where((r) => r.stats.fps != null).toList()
      ..sort((a, b) {
        final order = a.stats.fps!.compareTo(b.stats.fps!);
        return order != 0 ? order : a.name.compareTo(b.name);
      });
    final timed = _results.where((r) => r.stats.frames > 0).toList();
    _distribution('real_fps', fpsResults.map((r) => r.stats.fps!).toList());
    _distribution(
      'raster_avg',
      timed.map((r) => r.stats.raster.avgUs).toList(),
    );
    _distribution('build_avg', timed.map((r) => r.stats.build.avgUs).toList());
    _ranking('real_fps_asc', fpsResults);
    timed.sort((a, b) {
      final order = b.stats.raster.avgUs.compareTo(a.stats.raster.avgUs);
      return order != 0 ? order : a.name.compareTo(b.name);
    });
    _ranking('raster_avg_desc', timed);
    _emit(
      'status=${_errors == 0 ? _ok : _error} samples=$_fileCount '
      'measured_files=${_results.length} fps_samples=${fpsResults.length} errors=$_errors',
    );
    _emit('=== END ILLUS FPS BENCH REPORT ===');
    if (mounted) {
      setState(
        () => _progress =
            'illus_fps: done (${_results.length}/$_fileCount), errors=$_errors',
      );
    }
    if (autoExitAfterReport) exit(_errors == 0 ? 0 : _single);
  }

  /// No changing progress overlay is painted during a measurement window.
  /// 测量窗口内不绘制变化的进度叠层。
  @override
  Widget build(BuildContext context) {
    final sample = _sample;
    return Scaffold(
      backgroundColor: Colors.white,
      body: sample == null
          ? Center(child: Text(_progress))
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = width / sample.aspectRatio;
                Widget illustration(int index) => Xvg.string(
                  sample.source,
                  key: ValueKey('${sample.name}/$index'),
                  width: width,
                  height: height,
                  controller: sample.controllers[index],
                  onLoaded: (_) => sample.onLoaded(index),
                  onError: (error, _) => sample.fail(error),
                );
                if (_concurrency == _single) {
                  return Center(
                    child: OverflowBox(
                      minWidth: width,
                      maxWidth: width,
                      minHeight: height,
                      maxHeight: height,
                      child: illustration(0),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (var i = 0; i < _concurrency; i++)
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: illustration(i),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}
