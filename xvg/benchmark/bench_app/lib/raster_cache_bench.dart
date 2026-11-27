import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

// 沿用 bench_app 的 Material 页面。
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
// ignore: implementation_imports
import 'package:xvg/src/xvg_raster_cache.dart';
import 'package:xvg/xvg.dart';

/// 应用专属目录中的运行参数和数字报告。
const _data = '/sdcard/Android/data/com.example.bench_app/files';

/// 基准在设备端使用的通用文件名前缀。
const _name = 'tile-raster';

/// 插画的逻辑像素宽度。
const _artWidth = 375.0;

/// 沿用上一轮判断长帧的总跨度阈值。
const _longFrameUs = 16600;

/// 观察静止绘制的时长。
const _steadyDuration = Duration(milliseconds: 1900);

/// 从顶部匀速滚到底部的时长。
const _scrollDuration = Duration(seconds: 5);

/// 明确保留亚像素位置的全分辨率模式。
const _neverMode = 'never';

/// 使用同一 spinner 场景冷启动一次向量或分块位图试验。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final run = File('$_data/$_name-run.txt')
      .readAsStringSync()
      .trim()
      .split(' ');
  final source = await File('$_data/$_name-input.svg').readAsString();
  await RustLib.init();
  debugXvgRasterizeTilesAsync = run[1] == 'async';
  runApp(
    MaterialApp(
      home: _TileRasterBench(run: run, source: source),
    ),
  );
}

/// 单次运行的场景和输入。
class _TileRasterBench extends StatefulWidget {
  /// 读取设备运行时提供的参数和插画。
  const _TileRasterBench({required this.run, required this.source});

  /// 轮次、绘制模式、宽高比和滚动模式。
  final List<String> run;

  /// 仅在运行时加载的 SVG 内容。
  final String source;

  /// 创建用于采样的页面。
  @override
  State<_TileRasterBench> createState() => _TileRasterBenchState();
}

/// 运行冷启动、稳态和定速滚动，并关联实际 raster 帧。
class _TileRasterBenchState extends State<_TileRasterBench> {
  /// 已由引擎上报的帧时间。
  final _frames = <ui.FrameTiming>[];

  /// 按帧后回调时间记录滚动位置、可见块齐备和驻留纹理字节数。
  final _scrollSamples = SplayTreeMap<int, (double, bool, int)>();

  /// 裁剪视口的滚动位置。
  final _scroll = ScrollController();

  /// 等待当前首屏位图全部提交。
  final _complete = Completer<void>();

  /// 冷请求时间以及首次向量、完整分块的提交时刻。
  int _requested = 0, _first = 0, _ready = 0;

  /// 稳态或滚动的计时区间。
  int _start = 0, _end = 0;

  /// 稳态开始前及滚动期间的纹理峰值。
  int _peakBytes = 0;

  /// 稳态开始时的驻留纹理估算。
  int _steadyBytes = 0;

  /// 原生 Picture 是否具有触发向量模式自动对齐的裁剪或遮罩。
  bool? _hasPixelSnapRisk;

  /// 解析完成后开始显示插画。
  bool _show = false;

  /// 报告完成后停止观察。
  bool _done = false;

  /// 错误类别用于验证有效轮次。
  String? _error;

  /// 本轮使用的静态缓存参数。
  XvgRasterCacheOverride? get _cache => switch (widget.run[1]) {
    'full' || 'async' || _neverMode => XvgRasterCacheOverride.enabled,
    'half' => XvgRasterCacheOverride.halfResolution,
    _ => null,
  };

  /// 本轮是否从顶部匀速滚到底。
  bool get _scrolling => widget.run[3] == 'scroll';

  /// 注册引擎帧采样并预热 spinner。
  @override
  void initState() {
    super.initState();
    // ignore: invalid_use_of_visible_for_testing_member
    debugXvgRasterCacheOverride = _cache ?? XvgRasterCacheOverride.disabled;
    SchedulerBinding.instance.addTimingsCallback(_frames.addAll);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  /// 在每次提交后记录位图覆盖与纹理峰值。
  void _sample() {
    if (!mounted || _done) return;
    final now = developer.Timeline.now;
    final tilesReady = _cache != null && debugXvgRasterTilesReady;
    final bytes = XvgRasterCache.bytesUsed;
    if (_first == 0) _first = now;
    if (!_complete.isCompleted && (_cache == null || tilesReady)) {
      _ready = now;
      _complete.complete();
    }
    if (_end == 0) _peakBytes = math.max(_peakBytes, bytes);
    if (_scrolling && _start != 0 && _scroll.hasClients) {
      _scrollSamples[now] = (
        _scroll.offset * View.of(context).devicePixelRatio,
        tilesReady,
        bytes,
      );
    }
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sample());
    });
  }

  /// 统一冷解析和视口，采样完成后等待帧上报批次。
  Future<void> _run() async {
    await Future<void>.delayed(const Duration(milliseconds: 950));
    if (!mounted) return;
    _requested = developer.Timeline.now;
    try {
      final info = await RustXvgPictureCache.instance.getOrRenderAsync(
        widget.source,
      );
      if (!mounted) return;
      _hasPixelSnapRisk = info.hasPixelSnapRisk;
      setState(() => _show = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _sample());
      await _complete.future.timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 480));
      if (!mounted) return;
      _steadyBytes = XvgRasterCache.bytesUsed;
      _peakBytes = _steadyBytes;
      _start = developer.Timeline.now;
      if (_scrolling) {
        await _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: _scrollDuration,
          curve: Curves.linear,
        );
      } else {
        await Future<void>.delayed(_steadyDuration);
      }
      _end = developer.Timeline.now;
      await Future<void>.delayed(
        _scrolling
            ? const Duration(seconds: 1)
            : const Duration(milliseconds: 260),
      );
    } catch (error) {
      _error = '${error.runtimeType}';
    }
    if (!mounted) return;
    setState(() => _done = true);
    _report();
  }

  /// 记录可复算的每帧数据及本轮统计。
  void _report() {
    int phase(ui.FrameTiming frame, ui.FramePhase phase) =>
        frame.timestampInMicroseconds(phase);
    int vsync(ui.FrameTiming frame) => phase(frame, ui.FramePhase.vsyncStart);
    int finish(ui.FrameTiming frame) =>
        phase(frame, ui.FramePhase.rasterFinish);
    int submittedFrame(int at) {
      final frames = _frames.where(
        (frame) => phase(frame, ui.FramePhase.buildStart) <= at,
      );
      return frames.isEmpty ? 0 : finish(frames.last);
    }

    final first = submittedFrame(_first);
    final ready = submittedFrame(_ready);
    final window = _frames
        .where((frame) => vsync(frame) >= _start && vsync(frame) < _end)
        .toList();
    final scrollFrames = <List<Object>>[];
    int? postScrollReady;
    if (_scrolling) {
      // 引擎提交场景后才运行本帧的 post-frame 回调。按 buildStart
      // 找到首个回调，避免将未被 raster 线程消费的 UI 帧当成完成帧。
      for (final frame in _frames.where((frame) => vsync(frame) >= _start)) {
        final sampledAt = _scrollSamples.firstKeyAfter(
          phase(frame, ui.FramePhase.buildStart),
        );
        if (sampledAt == null ||
            sampledAt < phase(frame, ui.FramePhase.buildFinish)) {
          continue;
        }
        final (offset, ready, bytes) = _scrollSamples[sampledAt]!;
        if (vsync(frame) < _end) {
          scrollFrames.add([vsync(frame), offset, ready, bytes, sampledAt]);
        } else if (ready) {
          postScrollReady ??= finish(frame) - _end;
        }
      }
    }
    final preparation = _frames
        .where(
          (frame) =>
              phase(frame, ui.FramePhase.buildFinish) >= _requested &&
              finish(frame) <= ready,
        )
        .toList();
    final rasters = [
      for (final frame in window) frame.rasterDuration.inMicroseconds,
    ]..sort();
    int percentile(double quantile) =>
        rasters.isEmpty ? 0 : rasters[(quantile * rasters.length).ceil() - 1];
    final report = <String, Object?>{
      'run': widget.run,
      'error': _error,
      'has_pixel_snap_risk': _hasPixelSnapRisk,
      'display_hz': View.of(context).display.refreshRate,
      'dpr': View.of(context).devicePixelRatio,
      'requested_us': _requested,
      'first_submit_us': _first,
      'ready_submit_us': _ready,
      'start_us': _start,
      'end_us': _end,
      'first_us': first - _requested,
      'ready_us': ready - _requested,
      'prepare_raster_max_us': preparation.fold<int>(
        0,
        (peak, frame) => math.max(peak, frame.rasterDuration.inMicroseconds),
      ),
      'prepare_total_max_us': preparation.fold<int>(
        0,
        (peak, frame) => math.max(peak, frame.totalSpan.inMicroseconds),
      ),
      'raster_p50_us': percentile(0.50),
      'raster_p95_us': percentile(0.95),
      'over_16600_us': window
          .where((frame) => frame.totalSpan.inMicroseconds > _longFrameUs)
          .length,
      'steady_bytes': _steadyBytes,
      'peak_bytes': _peakBytes,
      if (_scrolling) ...{
        'scroll_extent_px': _scroll.hasClients
            ? _scroll.position.maxScrollExtent *
                  View.of(context).devicePixelRatio
            : 0,
        'scroll_frames': scrollFrames,
        'scroll_finished_frames': window.length,
        'post_scroll_ready_us': postScrollReady,
      },
      'completed_per_second': window.length < 2
          ? 0
          : (window.length - 1) *
                1000000 /
                (finish(window.last) - finish(window.first)),
      'frames': [
        for (final frame in _frames)
          if (phase(frame, ui.FramePhase.buildFinish) >= _requested &&
              vsync(frame) < _end)
            [
              for (final phase in ui.FramePhase.values.take(5))
                frame.timestampInMicroseconds(phase),
            ],
      ],
    };
    final temporary = File('$_data/$_name-report.tmp')
      ..writeAsStringSync(jsonEncode(report));
    temporary.renameSync('$_data/$_name-report.json');
  }

  /// 同尺寸视口夹住插画，spinner 独立持续请求画面。
  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(_artWidth, constraints.maxWidth);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (_show)
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: width,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    physics: const NeverScrollableScrollPhysics(),
                    child: StaticXvg(
                      widget.source,
                      width: width,
                      height: width / double.parse(widget.run[2]),
                      pixelSnap: widget.run[1] == _neverMode
                          ? XvgPixelSnap.never
                          : XvgPixelSnap.auto,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 40,
              right: 10,
              width: 24,
              height: 24,
              child: TickerMode(
                enabled: !_done,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        );
      },
    ),
  );

  /// 停止帧采样并释放滚动控制器。
  @override
  void dispose() {
    // ignore: invalid_use_of_visible_for_testing_member
    debugXvgRasterCacheOverride = null;
    SchedulerBinding.instance.removeTimingsCallback(_frames.addAll);
    _scroll.dispose();
    super.dispose();
  }
}
