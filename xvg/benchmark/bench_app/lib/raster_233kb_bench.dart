// 基准直接使用 xvg 的录制和冷路径探针。
// ignore_for_file: implementation_imports, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

// 沿用 bench_app 的 Material 页面组件。
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xvg/src/rust_static_svg.dart';
import 'package:xvg/xvg.dart';

import 'cmd_count_bench.dart';

/// 运行时输入和纯数字结果所在的应用专属目录。
const _data = '/sdcard/Android/data/com.example.bench_app/files';

/// 设置各画法共用的逻辑宽度上限。
const _artWidth = 375.0;

/// 停止热路径采样前等待 Flutter 上报最后一批帧。
const _reportDelay = Duration(milliseconds: 220);

/// 只统计裁剪调用，不将其转发到实际画布的消融模式。
const _noClipMode = 'no_clip';

/// 只栅格化可见顶部的缓存模式。
const _bitmapViewMode = 'bitmap_view';

/// 使用外置重绘边界的模式。
const _boundaryMode = 'boundary';

/// 像素对齐加外置重绘边界的模式。
const _alignedBoundaryMode = 'aligned_boundary';

/// 只匹配 XML 路径数据属性及其中无法表示的 moveto。
final _pathData = RegExp(r'''(\sd\s*=\s*)(["'])(.*?)\2''', dotAll: true);
final _nonFiniteMove = RegExp(r'[Mm]\s*[-+]?nan\b', caseSensitive: false);

/// 在非法 moveto 处截断路径，保留 usvg 原先读到的有效前缀。
String retainFinitePathPrefixes(
  String source,
) => source.replaceAllMapped(_pathData, (attribute) {
  final commands = attribute[3]!;
  final failure = _nonFiniteMove.firstMatch(commands);
  if (failure == null) return attribute[0]!;
  final quote = attribute[2];
  return '${attribute[1]}$quote${commands.substring(0, failure.start).trimRight()}$quote';
});

/// 在固定几何和 spinner 场景下运行一个冷进程对照。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final run = File('$_data/raster-run.txt')
      .readAsStringSync()
      .trim()
      .split(' ');
  final input = await File('$_data/raster-input.svg').readAsString();
  final source = run.contains('normalize')
      ? retainFinitePathPrefixes(input)
      : input;
  await RustLib.init();
  if (run[1] == 'xvg_sync') {
    debugStaticSvgAsyncParseThreshold = source.length + 1;
  }
  runApp(
    MaterialApp(
      home: _RasterBench(source: source, run: run),
    ),
  );
}

/// 统计录制操作，可独立去掉一类效果以测量其成本。
class RasterRecordingCanvas extends CountingCanvas {
  /// [ablation] 支持 `no_clip`、`no_gradient` 和 `no_layer`。
  RasterRecordingCanvas(super.canvas, this.ablation);

  /// 当前录制消融名称。
  final String ablation;

  /// 接受或消融前观察到的效果调用次数。
  final effects = <String, int>{
    'clipPath': 0,
    'clipRect': 0,
    'saveLayer': 0,
    'maskDstIn': 0,
    'blurFilter': 0,
    'gradient': 0,
    'pattern': 0,
  };

  /// 记录一次命名效果。
  void _bumpEffect(String name) => effects.update(name, (count) => count + 1);

  /// 统计路径裁剪并按指定开关重放。
  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) {
    _bumpEffect('clipPath');
    if (ablation == _noClipMode) return;
    super.clipPath(path, doAntiAlias: doAntiAlias);
  }

  /// 统计矩形裁剪并按指定开关重放。
  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) {
    _bumpEffect('clipRect');
    if (ablation == _noClipMode) return;
    super.clipRect(rect, clipOp: clipOp, doAntiAlias: doAntiAlias);
  }

  /// 统计离屏层，消融时以普通 save 保持栈平衡。
  @override
  void saveLayer(Rect? bounds, Paint paint) {
    _bumpEffect('saveLayer');
    if (paint.blendMode == BlendMode.dstIn) _bumpEffect('maskDstIn');
    if (paint.imageFilter != null) _bumpEffect('blurFilter');
    if (ablation == 'no_layer') {
      save();
    } else {
      super.saveLayer(bounds, paint);
    }
  }

  /// 统计路径着色器，梯度消融保留原路径和描边属性。
  @override
  void drawPath(ui.Path path, Paint paint) {
    final shader = paint.shader;
    if (shader is ui.Gradient) {
      _bumpEffect('gradient');
      if (ablation == 'no_gradient') paint.shader = null;
    } else if (shader is ui.ImageShader) {
      _bumpEffect('pattern');
    }
    super.drawPath(path, paint);
  }
}

/// 基准页面，图片在静止图层中，只有 spinner 持续动画。
class _RasterBench extends StatefulWidget {
  /// 使用一次进程启动对应的场景配置和源串。
  const _RasterBench({required this.source, required this.run});

  /// 从设备读取的图像源。
  final String source;

  /// 本轮编号、绘制方案及可选长采样模式。
  final List<String> run;

  @override
  State<_RasterBench> createState() => _RasterBenchState();
}

/// 负责采样、绘制方案切换和一次性栅格化的资源管理。
class _RasterBenchState extends State<_RasterBench> {
  /// 引擎已上报的原始帧时间。
  final _frames = <ui.FrameTiming>[];

  /// 实际进入测试绘制的时间点，用于辨认 Flutter UI 的重绘。
  final _paintTimes = <int>[];

  /// 本轮第一次录制的操作计数。
  RasterRecordingCanvas? _recording;

  /// 位图方案使用的纹理。
  ui.Image? _image;

  /// 已解析内容的显示尺寸。
  late Size _artSize;

  /// 页面可见绘制区域。
  late Size _viewport;

  /// 运行时设备像素比。
  late double _dpr;

  /// 挂载前稳态区间起点，对应 Timeline 单调时钟。
  int _start = 0;

  /// 发起挂载请求的时间。
  int _requested = 0;

  /// xvg 冷路径进入回调的时间。
  int? _recorded;

  /// xvg 冷路径解析加录制的墙钟耗时。
  int? _parseRecordUs;

  /// 生成位图的墙钟耗时，包含排队与 future 回调返回。
  int? _rasterizeUs;

  /// 位图可提交绘制的时间。
  int? _imageReady;

  /// 截取原始帧的结束时间。
  int _end = 0;

  /// 挂载源图或开始缓存生成。
  bool _show = false;

  /// 报告生成后停止 spinner。
  bool _done = false;

  /// 仅存错误类别，避免记录源数据。
  String? _errorKind;

  /// 场景名称由设备端配置提供。
  String get _mode => widget.run[1];

  /// 长窗口只用于独立的 timeline 归因。
  bool get _trace => widget.run.contains('trace');

  /// 两种位图方案分别缓存整张插画与可见顶部。
  bool get _usesBitmap => _mode == 'bitmap_full' || _mode == _bitmapViewMode;

  /// 只改变绘制几何，用于拆解像素对齐和普通重绘边界的差异。
  bool get _manualSnap => _mode == 'aligned' || _mode == _alignedBoundaryMode;

  /// 启动 spinner、注册采样以及只读的冷录制统计钩子。
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_frames.addAll);
    RustXvgPictureCache.debugWrapRecordingCanvas = (canvas) =>
        _recording = RasterRecordingCanvas(canvas, _mode);
    RustXvgPictureCache.instance.onParseMiss = (elapsed) {
      _recorded = developer.Timeline.now;
      _parseRecordUs = elapsed.inMicroseconds;
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  /// 运行挂载前、首次显示以及稳态采样窗口。
  Future<void> _run() async {
    await Future<void>.delayed(const Duration(milliseconds: 330));
    if (!mounted) return;
    _start = developer.Timeline.now;
    await Future<void>.delayed(const Duration(milliseconds: 720));
    if (!mounted) return;
    _requested = developer.Timeline.now;
    developer.Timeline.instantSync('raster_bench.mount');
    setState(() => _show = true);
    if (_usesBitmap) unawaited(_prepareBitmap());
    await Future<void>.delayed(Duration(milliseconds: _trace ? 18000 : 2700));
    if (!mounted) return;
    _end = developer.Timeline.now;
    await Future<void>.delayed(_reportDelay);
    if (!mounted) return;
    setState(() => _done = true);
    _writeReport();
  }

  /// 在同一显示比例下缓存全图，或只生成固定视口的顶部区域。
  Future<void> _prepareBitmap() async {
    try {
      final info = await RustXvgPictureCache.instance.getOrRenderAsync(
        widget.source,
      );
      if (!mounted) return;
      final width = (_artSize.width * _dpr).ceil();
      final fullHeight = (_artSize.height * _dpr).ceil();
      final height = _mode == _bitmapViewMode
          ? math.min(fullHeight, (_viewport.height * _dpr).ceil())
          : fullHeight;
      final timer = Stopwatch()..start();
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..scale(width / info.size.width, fullHeight / info.size.height)
        ..drawPicture(info.picture);
      final picture = recorder.endRecording();
      final ui.Image image;
      try {
        image = await picture.toImage(width, height);
      } finally {
        picture.dispose();
      }
      _rasterizeUs = timer.elapsedMicroseconds;
      if (!mounted) {
        image.dispose();
        return;
      }
      _imageReady = developer.Timeline.now;
      setState(() => _image = image);
    } catch (error) {
      _recordError(error);
    }
  }

  /// 保留各阶段时间戳与引擎位图缓存计数，供离线统计。
  void _writeReport() {
    final view = View.of(context);
    final picture = RustXvgPictureCache.instance.peek(widget.source)?.picture;
    final report = <String, Object?>{
      'run': widget.run,
      'start_us': _start,
      'requested_us': _requested,
      'recorded_us': _recorded,
      'parse_record_us': _parseRecordUs,
      'rasterize_us': _rasterizeUs,
      'image_ready_us': _imageReady,
      'end_us': _end,
      'display_hz': view.display.refreshRate,
      'dpr': _dpr,
      'viewport': [_viewport.width, _viewport.height],
      'art_size': [_artSize.width, _artSize.height],
      'image_size': [_image?.width, _image?.height],
      'picture_bytes': picture?.approximateBytesUsed,
      'error_kind': _errorKind,
      'counts': {
        ...?_recording?.effects,
        ...?_recording?.counts,
        'save': _recording?.saveCount,
        'restore': _recording?.restoreCount,
      },
      'paint_us': _paintTimes,
      'columns': [
        'vsyncStart',
        'buildStart',
        'buildFinish',
        'rasterStart',
        'rasterFinish',
        'layerCacheCount',
        'pictureCacheCount',
        'layerCacheBytes',
        'pictureCacheBytes',
      ],
      'frames': [
        for (final frame in _frames)
          if (frame.timestampInMicroseconds(ui.FramePhase.vsyncStart) >=
                  _start &&
              frame.timestampInMicroseconds(ui.FramePhase.vsyncStart) < _end)
            [
              for (final phase in ui.FramePhase.values.take(5))
                frame.timestampInMicroseconds(phase),
              frame.layerCacheCount,
              frame.pictureCacheCount,
              frame.layerCacheBytes,
              frame.pictureCacheBytes,
            ],
      ],
    };
    final temporary = File('$_data/raster-report.tmp');
    temporary.writeAsStringSync(jsonEncode(report));
    temporary.renameSync('$_data/raster-report.json');
  }

  /// 停止采样并释放生成的图像句柄。
  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_frames.addAll);
    RustXvgPictureCache.debugWrapRecordingCanvas = null;
    RustXvgPictureCache.instance.onParseMiss = null;
    _image?.dispose();
    super.dispose();
  }

  /// 将图像和 spinner 放在同一个静止视口里。
  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.biggest;
        _dpr = View.of(context).devicePixelRatio;
        final width = math.min(_artWidth, _viewport.width);
        final intrinsicAspect = double.parse(widget.run[2]);
        final fitAll = _mode == 'fit_all';
        final fullHeight = width / intrinsicAspect;
        final height = fitAll
            ? math.min(_viewport.height, fullHeight)
            : fullHeight;
        final nominalSize = Size(
          fitAll ? height * intrinsicAspect : width,
          height,
        );
        final nominalLeft = (_viewport.width - nominalSize.width) / 2;
        _artSize = _manualSnap
            ? Size(_snap(nominalSize.width), _snap(nominalSize.height))
            : nominalSize;
        final left = _manualSnap ? _snap(nominalLeft) : nominalLeft;
        final top = _mode == 'offscreen' ? _viewport.height + 16 : 0.0;
        return ClipRect(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (_show && _mode != 'spinner')
                Positioned(
                  top: top,
                  left: left,
                  width: _artSize.width,
                  height: _usesBitmap && _image != null
                      ? _artSize.height *
                            _image!.height /
                            (_artSize.height * _dpr).ceil()
                      : _artSize.height,
                  child: _artwork(),
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
          ),
        );
      },
    ),
  );

  /// 对齐到最邻近的设备物理像素。
  double _snap(double value) => (value * _dpr).round() / _dpr;

  /// 为向量、消融和图像策略使用一致的尺寸和绘制探针。
  Widget _artwork() {
    Widget art;
    if (_usesBitmap) {
      art = RawImage(image: _image, fit: BoxFit.fill);
    } else if (_mode == 'flutter_svg') {
      art = SvgPicture.string(widget.source, errorBuilder: _onArtworkError);
    } else {
      art = StaticXvg(
        widget.source,
        width: _artSize.width,
        height: _artSize.height,
        fit: _manualSnap ? BoxFit.fill : BoxFit.contain,
        pixelSnap:
            _manualSnap || _mode == 'no_boundary' || _mode == _boundaryMode
            ? XvgPixelSnap.never
            : XvgPixelSnap.auto,
        errorBuilder: _onArtworkError,
      );
    }
    art = _PaintProbe(onPaint: _onPaint, child: art);
    return _mode == _boundaryMode || _mode == _alignedBoundaryMode
        ? RepaintBoundary(child: art)
        : art;
  }

  /// 记录矢量绘制错误并沿用空白占位。
  Widget _onArtworkError(BuildContext _, Object error, StackTrace _) {
    _recordError(error);
    return const SizedBox();
  }

  /// 仅记录异常的类型名。
  void _recordError(Object error) => _errorKind = '${error.runtimeType}';

  /// 记录测试子树进入 paint，包含占位帧，也包含默认内置边界外的访问。
  void _onPaint() => _paintTimes.add(developer.Timeline.now);
}

/// 放在受控重绘边界内侧的 Flutter paint 探针。
class _PaintProbe extends SingleChildRenderObjectWidget {
  /// 在转发 paint 时调用 [onPaint]。
  const _PaintProbe({required this.onPaint, required super.child});

  /// paint 观察者。
  final VoidCallback onPaint;

  @override
  _RenderPaintProbe createRenderObject(BuildContext context) =>
      _RenderPaintProbe(onPaint);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPaintProbe renderObject,
  ) {
    renderObject.onPaint = onPaint;
  }
}

/// 在 Flutter 框架层观察重复 paint。
class _RenderPaintProbe extends RenderProxyBox {
  /// 设置轻量回调并原样转发绘制。
  _RenderPaintProbe(this.onPaint);

  /// paint 观察者。
  VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}
