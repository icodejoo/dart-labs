import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

// 沿用既有真机基准的 Material spinner。
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
// ignore: implementation_imports
import 'package:xvg/src/rust/api/svg.dart';
// ignore: implementation_imports
import 'package:xvg/src/xvg_raster_cache.dart';
import 'package:xvg/xvg.dart';

import 'raster_cache_auto_samples.dart';

import 'svg_gen.dart';

part 'raster_cache_auto_r2.dart';
part 'raster_cache_auto_mode.dart';

/// 设备端的临时输入和测量文件。
const _prefix = '/sdcard/Android/data/com.example.bench_app/files/auto-raster';

/// 缓存必须收齐的稳态帧数下限。
const _minFrames = 18;

/// 每组切换后的预热及稳态窗口的最短时长。
const _settle = Duration(milliseconds: 300);
const _window = Duration(milliseconds: 650);

/// 等待 GPU 齐备或帧上报的截止时间。
const _timeout = Duration(seconds: 20);

/// 尺寸键的固定顺序，用于跨轮完整轮换三个模式。
const _sizeOrder = ['48', '200', 'full', '16'];

/// 每个尺寸的三个独立测量阶段。
enum _Mode { baseline, vector, cached, automatic }

/// 第一轮基准沿用三个强制对照。
const _historicalModes = [_Mode.baseline, _Mode.vector, _Mode.cached];

/// 从引擎帧取同一单调时钟的时间戳。
int _timestamp(ui.FrameTiming frame, ui.FramePhase phase) =>
    frame.timestampInMicroseconds(phase);

/// 截取窗口时使用帧的 vsync 时间。
int _vsync(ui.FrameTiming frame) => _timestamp(frame, ui.FramePhase.vsyncStart);

/// 用完成时间把分块齐备落到已提交的 raster 帧。
int _finish(ui.FrameTiming frame) =>
    _timestamp(frame, ui.FramePhase.rasterFinish);

/// 从指定真机读取运行时输入并执行一轮。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final args = File('$_prefix-run.txt').readAsStringSync().trim().split(' ');
    final round = int.parse(args.first);
    final samples = autoSamples(
      await File('$_prefix-aurora.svg').readAsString(),
      await File('$_prefix-input.svg').readAsString(),
    );
    await RustLib.init();
    final clipArtwork = args.skip(1).firstOrNull == 'clip';
    final ids = args.skip(clipArtwork ? 2 : 1).toSet();
    final selected = ids.isEmpty
        ? samples
        : samples.where((sample) => ids.contains(sample.id)).toList();
    if (selected.isEmpty || (ids.isNotEmpty && selected.length != ids.length)) {
      throw StateError('Invalid sample ids');
    }
    runApp(
      MaterialApp(
        home: _AutoBench(
          round: round,
          samples: selected,
          clipArtwork: clipArtwork,
        ),
      ),
    );
  } catch (error) {
    _status('error startup ${error.runtimeType}');
  }
}

/// 原子写入可由主机安全轮询的状态。
void _status(String value) {
  final file = File('$_prefix-status.tmp')..writeAsStringSync(value);
  file.renameSync('$_prefix-status.txt');
}

/// 在一个稳定的页面上依次挂载不同样本和模式。
class _AutoBench extends StatefulWidget {
  /// 一轮内部复用场景和动画。
  const _AutoBench({
    required this.round,
    required this.samples,
    required this.clipArtwork,
    this.batch,
    this.automaticRun,
  });

  /// 当前轮次从 1 开始。
  final int round;

  /// 待测试的输入。
  final List<AutoSample> samples;

  /// 对照场景是否将裁剪收紧到图像布局盒。
  final bool clipArtwork;

  /// 第二轮的逐批计划，含各图实际需要测量的尺寸。
  final _Batch? batch;

  /// 自动模式真机复测的单轮计划。
  final _AutomaticRun? automaticRun;

  /// 挂载采样状态。
  @override
  State<_AutoBench> createState() => _AutoBenchState();
}

/// 运行测量并将每组的原始 raster 时间追加到设备报告。
class _AutoBenchState extends State<_AutoBench> {
  /// 当前模式的帧时间，由引擎异步批量上报。
  final _frames = <ui.FrameTiming>[];

  /// 当前挂载的图像及其逻辑尺寸。
  Widget? _artwork;

  /// 测量结束后停住动画。
  bool _done = false;

  /// 启动后先预热引擎和 spinner。
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_frames.addAll);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  /// 替换当前被测的图层。
  void _showArtwork(Widget? artwork) => setState(() => _artwork = artwork);

  /// 停止驱动场景合成。
  void _finishRun() => setState(() => _done = true);

  /// 让上一阶段的图层脱离，直到所有历史缓存块释放。
  Future<void> _unmountArtwork() async {
    _showArtwork(null);
    await SchedulerBinding.instance.endOfFrame;
    if (XvgRasterCache.bytesUsed != 0 || debugXvgRasterTilesReady) {
      throw StateError('A previous cache is still attached');
    }
  }

  /// 等待帧时间上报条件，超时后把该组标为失败。
  Future<void> _waitFor(bool Function() condition) async {
    final watch = Stopwatch()..start();
    while (!condition()) {
      if (watch.elapsed >= _timeout) throw TimeoutException('Frame timing');
      await Future<void>.delayed(const Duration(milliseconds: 35));
    }
  }

  /// 保留首次挂载和齐备之间的时序，并提取稳态窗口内的每帧 raster。
  Future<Map<String, Object?>> _measure({
    required _Mode mode,
    required String source,
    required Size artSize,
  }) async {
    final automatic = mode == _Mode.automatic;
    final cached = mode == _Mode.cached || automatic;
    // ignore: invalid_use_of_visible_for_testing_member
    debugXvgRasterCacheOverride = switch (mode) {
      _Mode.automatic => null,
      _Mode.cached => XvgRasterCacheOverride.enabled,
      _ => XvgRasterCacheOverride.disabled,
    };
    final submissions = <(int, int)>[];
    final first = Completer<int>();
    final ready = Completer<int>();
    var previousSubmit = 0;
    var beforeReady = 0;
    var tracking = cached;
    var steadyStart = 0;
    var steadyEnd = 0;
    var missingInWindow = 0;
    _frames.clear();
    final requested = developer.Timeline.now;
    setState(() {
      if (mode == _Mode.baseline) {
        _artwork = null;
        return;
      }
      final svg = StaticXvg(
        source,
        width: artSize.width,
        height: artSize.height,
      );
      _artwork = Positioned(
        left: 0,
        top: 0,
        width: artSize.width,
        height: artSize.height,
        child: widget.clipArtwork ? ClipRect(child: svg) : svg,
      );
    });

    /// 记录实际提交的 UI 帧边界，不能把同一帧的 build 和 raster 混为一谈。
    void submitted(Duration _) {
      final now = developer.Timeline.now;
      if (!first.isCompleted) first.complete(now);
      if (!tracking) return;
      if (automatic) submissions.add((now, XvgRasterCache.tileCount));
      final hasTiles = debugXvgRasterTilesReady;
      if (hasTiles && !ready.isCompleted) {
        beforeReady = previousSubmit == 0 ? requested : previousSubmit;
        ready.complete(now);
      }
      if (!hasTiles &&
          steadyStart != 0 &&
          (steadyEnd == 0 || now < steadyEnd)) {
        missingInWindow++;
      }
      previousSubmit = now;
      WidgetsBinding.instance.addPostFrameCallback(submitted);
    }

    WidgetsBinding.instance.addPostFrameCallback(submitted);
    try {
      await first.future.timeout(_timeout);
      if (cached) await ready.future.timeout(_timeout);
      await Future<void>.delayed(_settle);
      final bytes = XvgRasterCache.bytesUsed;
      final tiles = XvgRasterCache.tileCount;
      if (cached ? bytes <= 0 || tiles <= 0 : bytes != 0 || tiles != 0) {
        throw StateError('Wrong cache residency');
      }
      steadyStart = developer.Timeline.now;
      await Future<void>.delayed(_window);
      await _waitFor(
        () =>
            _frames.where((frame) => _vsync(frame) >= steadyStart).length >=
            _minFrames,
      );
      steadyEnd = developer.Timeline.now;
      await _waitFor(() => _frames.any((frame) => _vsync(frame) >= steadyEnd));
      if (missingInWindow != 0 || XvgRasterCache.bytesUsed != bytes) {
        throw StateError('Cache changed during steady sampling');
      }
      final frames = _frames.where((frame) {
        final vsync = _vsync(frame);
        return vsync >= steadyStart && vsync < steadyEnd;
      }).toList();
      final preparation = cached
          ? _frames
                .where(
                  (frame) =>
                      _timestamp(frame, ui.FramePhase.buildStart) >=
                          requested &&
                      _timestamp(frame, ui.FramePhase.buildFinish) <
                          steadyStart,
                )
                .toList()
          : const <ui.FrameTiming>[];
      final readyIndex = preparation.indexWhere(
        (frame) => _timestamp(frame, ui.FramePhase.buildStart) >= beforeReady,
      );
      if (frames.length < _minFrames ||
          (cached &&
              (readyIndex < 0 ||
                  _finish(preparation[readyIndex]) <= requested))) {
        throw StateError('Could not match submitted frames');
      }
      final rasters = [
        for (final frame in frames) frame.rasterDuration.inMicroseconds,
      ];
      final sorted = [...rasters]..sort();
      return {
        'mode': mode.name,
        'raster_us': rasters,
        'p50_us': sorted[(sorted.length - 1) ~/ 2],
        'p95_us': sorted[(sorted.length * .95).ceil() - 1],
        'fps':
            (frames.length - 1) *
            1e6 /
            (_finish(frames.last) - _finish(frames.first)),
        'bytes': bytes,
        'tiles': tiles,
        'generation_us': cached
            ? _finish(preparation[readyIndex]) - requested
            : null,
        'first_output_us': cached
            ? _finish(preparation.first) - requested
            : null,
        if (automatic)
          'preparation_frames': _generationFrames(preparation, submissions),
        'preparation_raster_us': [
          for (final frame in preparation.take(readyIndex + 1))
            frame.rasterDuration.inMicroseconds,
        ],
      };
    } finally {
      tracking = false;
      await _unmountArtwork();
    }
  }

  /// 轮换顺序后以相同的裁剪视口测试每个样本的各档宽度。
  Future<void> _run() async {
    if (widget.automaticRun case final run?) {
      await _runAutomatic(this, run);
      return;
    }
    if (widget.batch case final batch?) {
      await _runBatch(this, batch);
      return;
    }
    var current = 'warmup';
    final output = File('$_prefix-frames.jsonl').openWrite();
    try {
      await Future<void>.delayed(const Duration(seconds: 2));
      await _waitFor(() => _frames.isNotEmpty);
      if (!mounted) return;
      final view = View.of(context);
      final dpr = view.devicePixelRatio;
      final screen = view.physicalSize / dpr;
      final samples = [...widget.samples]
        ..shuffle(math.Random(3140 + widget.round));
      for (var index = 0; index < samples.length; index++) {
        final sample = samples[index];
        current = sample.id;
        _status('running $current ${index + 1}/${samples.length}');
        final scene = await parseSvgAsync(data: sample.source);
        final features = autoFeatures(scene);
        if (features['paths'] == 0 || scene.width <= 0 || scene.height <= 0) {
          throw StateError('Unexpected empty scene');
        }
        await RustXvgPictureCache.instance.getOrRenderAsync(sample.source);
        final widths = <String, double>{
          '48': 48,
          '200': 200,
          'full': screen.width,
          if (sample.id.contains('-20000-') ||
              sample.id == 'aurora' ||
              sample.id == '233KB')
            '16': 16,
        }.entries.toList()..shuffle(math.Random(7200 + index + widget.round));
        final sampleOrder = widget.samples.indexOf(sample);
        for (final width in widths) {
          final size = Size(
            width.value,
            width.value * scene.height / scene.width,
          );
          final rows = <Map<String, Object?>>[];
          final firstMode =
              sampleOrder + _sizeOrder.indexOf(width.key) + widget.round - 1;
          for (var offset = 0; offset < _historicalModes.length; offset++) {
            final mode =
                _historicalModes[(firstMode + offset) %
                    _historicalModes.length];
            current = '${sample.id}/${width.key}/${mode.name}';
            final result = await _measure(
              mode: mode,
              source: sample.source,
              artSize: size,
            );
            rows.add({
              'sample': sample.id,
              'validation': sample.validation,
              'round': widget.round,
              'size': width.key,
              'width_dp': size.width,
              'height_dp': size.height,
              'dpr': dpr,
              'display_hz': view.display.refreshRate,
              'area_px': (size.width * size.height * dpr * dpr).round(),
              'visible_px':
                  (size.width *
                          math.min(size.height, screen.height) *
                          dpr *
                          dpr)
                      .round(),
              ...features,
              ...result,
            });
          }
          for (final row in rows) {
            output.writeln(jsonEncode(row));
          }
          await output.flush();
        }
        RustXvgPictureCache.instance.clear();
      }
      await output.close();
      _finishRun();
      _status('done ${widget.round}');
    } catch (error) {
      await output.close();
      _finishRun();
      _status(
        'error $current ${error.runtimeType} ${error is StateError ? error.message : ''}',
      );
    }
  }

  /// 固定的根裁剪和独立 spinner 使每一帧重新合成包含静态图的场景。
  @override
  Widget build(BuildContext context) => Scaffold(
    body: ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ?_artwork,
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
      ),
    ),
  );

  /// 从引擎解除帧上报。
  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_frames.addAll);
    // ignore: invalid_use_of_visible_for_testing_member
    debugXvgRasterCacheOverride = null;
    super.dispose();
  }
}
