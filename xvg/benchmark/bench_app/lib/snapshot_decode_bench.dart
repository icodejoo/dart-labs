// 基准直接读取 xvg 的 Picture 冷录制统计。
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

// 沿用 bench_app 的 Material Spinner 与页面外壳。
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:xvg/xvg.dart';

import 'mdi_icons_1000.dart';
import 'raster_233kb_bench.dart' show retainFinitePathPrefixes;

/// ADB 通过应用 UID 写入的私有目录。
const _data = '/data/user/0/com.example.bench_app/files/xvg-snapshot';

/// 设备上生成的 PNG 文件名。
const _capture = 'capture.png';

/// 冷向量路径使用的作业模式。
const _vectorMode = 'vector';

/// 生成 PNG 使用的作业模式。
const _captureMode = 'capture';

/// 手机启动后等待首个 Spinner 帧稳定的时间。
const _warmup = Duration(milliseconds: 450);

/// 自请求起记录帧的时间窗。
const _sample = Duration(milliseconds: 1150);

/// 等待引擎交付最后一批 FrameTiming 的时间。
const _flushTimings = Duration(milliseconds: 1050);

/// 一轮只处理一张图，确保向量和图片缓存均为进程内冷态。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final job = jsonDecode(
    File('$_data/job.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final mode = job['mode'] as String;
  final id = job['id'] as String;
  try {
    final isIcon = job['sample'] == 'icon';
    final needsSource = mode == _vectorMode || mode == _captureMode;
    String? source;
    int? sourceBytes;
    if (needsSource) {
      final text = isIcon
          ? mdiIcons1000.first
          : await File('$_data/input.svg').readAsString();
      sourceBytes = utf8.encode(text).length;
      source = job['normalize'] == true ? retainFinitePathPrefixes(text) : text;
    }
    await RustLib.init();
    runApp(
      MaterialApp(
        home: _SnapshotBench(
          id: id,
          mode: mode,
          isIcon: isIcon,
          viewportOnly: job['view'] == true,
          intrinsic: Size(
            (job['width'] as num).toDouble(),
            (job['height'] as num).toDouble(),
          ),
          sourceBytes: sourceBytes,
          source: source,
        ),
      ),
    );
  } catch (error) {
    _writeReport({'id': id, 'error': error.runtimeType.toString()});
  }
}

/// 原子发布仅含指标的报告。
void _writeReport(Map<String, Object?> report) {
  File('$_data/result.tmp')
    ..writeAsStringSync(jsonEncode(report))
    ..renameSync('$_data/result.json');
}

/// 计算物理像素宽高和顶部裁剪高度。
({int width, int fullHeight, int viewHeight}) snapshotGeometry({
  required double logicalWidth,
  required double dpr,
  required Size intrinsic,
  required int viewportHeight,
}) {
  final width = (logicalWidth * dpr).round();
  final fullHeight = (logicalWidth * dpr / intrinsic.aspectRatio).round();
  return (
    width: width,
    fullHeight: fullHeight,
    viewHeight: math.min(fullHeight, viewportHeight),
  );
}

/// 在相同帧的 build 区间内匹配真正绘制图像的 paint。
bool snapshotPaintInFrame(int paintUs, int buildStartUs, int buildFinishUs) =>
    buildStartUs <= paintUs && paintUs <= buildFinishUs;

/// 以固定画面采集单次冷启动或快照写出。
class _SnapshotBench extends StatefulWidget {
  /// 接收同一轮的模式、尺寸以及按需读入的向量。
  const _SnapshotBench({
    required this.id,
    required this.mode,
    required this.isIcon,
    required this.viewportOnly,
    required this.intrinsic,
    required this.sourceBytes,
    required this.source,
  });

  /// ADB 关联本次进程输出的编号。
  final String id;

  /// 当前采集模式或位图扩展名。
  final String mode;

  /// 是否为单个 48 逻辑像素图标。
  final bool isIcon;

  /// 快照是否限于顶部可见区域。
  final bool viewportOnly;

  /// 向量标称宽高。
  final Size intrinsic;

  /// 读入的原始向量字节数。
  final int? sourceBytes;

  /// 当前进程需要解析时才提供的向量。
  final String? source;

  /// 创建一轮运行状态。
  @override
  State<_SnapshotBench> createState() => _SnapshotBenchState();
}

/// 关联请求、实际 paint 与 Flutter 引擎帧时序。
class _SnapshotBenchState extends State<_SnapshotBench> {
  /// 当前轮收到的原始帧。
  final _frames = <ui.FrameTiming>[];

  /// 当前视口的设备像素比。
  late double _dpr;

  /// 当前 Flutter 渲染视口的逻辑宽高。
  late Size _viewport;

  /// 实际使用的位图及向量物理尺寸。
  late ({int width, int fullHeight, int viewHeight}) _geometry;

  /// 由页面挂载的解码结果。
  ui.Image? _image;

  /// 开始请求的单调时钟时间。
  int? _requestUs;

  /// 真实内容首次 paint 的单调时钟时间。
  int? _paintUs;

  /// xvg 从缓存未命中到 Picture 完成的耗时。
  int? _parseRecordUs;

  /// 向量录制或位图解码完成的单调时钟时间。
  int? _readyUs;

  /// 生产向量控件的错误类型。
  String? _vectorError;

  /// 是否开始采样。
  bool _showVector = false;

  /// 是否停止 Spinner 和逐帧采集。
  bool _done = false;

  /// 首帧布局完成后启动计时。
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_frames.addAll);
    RustXvgPictureCache.instance.onParseMiss = (elapsed) {
      _parseRecordUs = elapsed.inMicroseconds;
      _readyUs = developer.Timeline.now;
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  /// 采集一次编码，或一次请求和后续逐帧时间。
  Future<void> _run() async {
    await Future<void>.delayed(_warmup);
    if (!mounted) return;
    try {
      if (widget.mode == _captureMode) {
        _writeReport({'id': widget.id, ...await _encode()});
        return;
      }
      _requestUs = developer.Timeline.now;
      final metrics = <String, Object?>{};
      if (widget.mode == _vectorMode) {
        setState(() => _showVector = true);
      } else {
        metrics.addAll(await _decode());
      }

      final end = _requestUs! + _sample.inMicroseconds;
      final remaining = end - developer.Timeline.now;
      if (remaining > 0) {
        await Future<void>.delayed(Duration(microseconds: remaining));
      }
      if (!mounted) return;
      setState(() => _done = true);
      await Future<void>.delayed(_flushTimings);
      if (!mounted) return;
      _writeReport({'id': widget.id, ...metrics, ..._frameReport(end)});
    } catch (error) {
      _writeReport({'id': widget.id, 'error': error.runtimeType.toString()});
    }
  }

  /// 按实测尺寸光栅化，单独计量 PNG 回读编码和应用目录写入。
  Future<Map<String, Object?>> _encode() async {
    final info = await RustXvgPictureCache.instance.getOrRenderAsync(
      widget.source!,
    );
    final width = _geometry.width;
    final fullHeight = _geometry.fullHeight;
    final height = widget.viewportOnly ? _geometry.viewHeight : fullHeight;
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..clipRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()))
      ..scale(width / info.size.width, fullHeight / info.size.height)
      ..drawPicture(info.picture);
    final picture = recorder.endRecording();
    final timer = Stopwatch()..start();
    final ui.Image image;
    try {
      image = await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
    final rasterUs = timer.elapsedMicroseconds;
    timer.reset();
    final ByteData? png;
    try {
      png = await image.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      image.dispose();
    }
    final pngUs = timer.elapsedMicroseconds;
    if (png == null) throw StateError('PNG encoding failed');
    final bytes = png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    timer.reset();
    await File('$_data/$_capture').writeAsBytes(bytes, flush: true);
    return {
      'size': [width, height],
      'bytes': bytes.length,
      'rasterize_us': rasterUs,
      'encode_us': pngUs,
      'write_us': timer.elapsedMicroseconds,
      'source_bytes': widget.sourceBytes,
      'parse_record_us': _parseRecordUs,
    };
  }

  /// 分段计量应用私有文件读取、codec 创建和首帧解码。
  Future<Map<String, Object?>> _decode() async {
    final timer = Stopwatch()..start();
    final bytes = await File('$_data/input.${widget.mode}').readAsBytes();
    final readUs = timer.elapsedMicroseconds;
    timer.reset();
    final ui.Image image;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        image = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } catch (error) {
      return {'decode_error': error.toString(), 'read_us': readUs};
    }
    final decodeUs = timer.elapsedMicroseconds;
    final height = widget.viewportOnly
        ? _geometry.viewHeight
        : _geometry.fullHeight;
    if (!mounted || image.width != _geometry.width || image.height != height) {
      image.dispose();
      throw StateError('Unexpected image dimensions');
    }
    _readyUs = developer.Timeline.now;
    setState(() => _image = image);
    return {
      'size': [image.width, image.height],
      'bytes': bytes.length,
      'resident_rgba_bytes': image.width * image.height * 4,
      'read_us': readUs,
      'decode_us': decodeUs,
    };
  }

  /// 发布首帧及窗口内每一帧的原始引擎时间。
  Map<String, Object?> _frameReport(int end) {
    final paintUs = _paintUs;
    final request = _requestUs!;
    int? firstRasterFinish;
    final rows = <List<int>>[];
    for (final frame in _frames) {
      final buildStart = frame.timestampInMicroseconds(
        ui.FramePhase.buildStart,
      );
      if (buildStart < request || buildStart >= end) continue;
      final buildFinish = frame.timestampInMicroseconds(
        ui.FramePhase.buildFinish,
      );
      final rasterStart = frame.timestampInMicroseconds(
        ui.FramePhase.rasterStart,
      );
      final rasterFinish = frame.timestampInMicroseconds(
        ui.FramePhase.rasterFinish,
      );
      if (paintUs != null &&
          snapshotPaintInFrame(paintUs, buildStart, buildFinish)) {
        firstRasterFinish = rasterFinish;
      }
      rows.add([buildStart, buildFinish, rasterStart, rasterFinish]);
    }
    final source = widget.source;
    return {
      'error': _vectorError,
      'source_bytes': widget.sourceBytes,
      'picture_bytes': source == null
          ? null
          : RustXvgPictureCache.instance
                .peek(source)
                ?.picture
                .approximateBytesUsed,
      'parse_record_us': _parseRecordUs,
      'requested_us': request,
      'ready_us': _readyUs,
      'image_paint_us': paintUs,
      'first_raster_finish_us': firstRasterFinish,
      'request_to_raster_us': firstRasterFinish == null
          ? null
          : firstRasterFinish - request,
      'viewport_px': [
        (_viewport.width * _dpr).round(),
        (_viewport.height * _dpr).round(),
      ],
      'art_px': [_geometry.width, _geometry.fullHeight, _geometry.viewHeight],
      'dpr': _dpr,
      'hz': View.of(context).display.refreshRate,
      'frame_columns': [
        'build_start',
        'build_finish',
        'raster_start',
        'raster_finish',
      ],
      'frames': rows,
    };
  }

  /// 只在生产控件已有录制结果或位图已经解码时打点。
  void _markPaint() {
    if (_readyUs != null) _paintUs ??= developer.Timeline.now;
  }

  /// 记录向量错误并保留空白占位。
  Widget _recordVectorError(BuildContext _, Object error, StackTrace _) {
    _vectorError = error.runtimeType.toString();
    return const SizedBox();
  }

  /// 共用像素对齐几何、白底及持续驱动合成的 Spinner。
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.biggest;
        _dpr = View.of(context).devicePixelRatio;
        _geometry = snapshotGeometry(
          logicalWidth: math.min(widget.isIcon ? 48 : 375, _viewport.width),
          dpr: _dpr,
          intrinsic: widget.intrinsic,
          viewportHeight: (_viewport.height * _dpr).round(),
        );
        final image = _image;
        final width = _geometry.width / _dpr;
        final height = (image?.height ?? _geometry.fullHeight) / _dpr;
        return ClipRect(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (_showVector || image != null)
                Positioned(
                  top: 0,
                  left:
                      ((_viewport.width * _dpr - _geometry.width) / 2).round() /
                      _dpr,
                  width: width,
                  height: height,
                  child: RepaintBoundary(
                    child: _PaintProbe(
                      onPaint: _markPaint,
                      child: image == null
                          ? StaticXvg(
                              widget.source!,
                              fit: BoxFit.fill,
                              pixelSnap: XvgPixelSnap.never,
                              errorBuilder: _recordVectorError,
                            )
                          : RawImage(image: image, fit: BoxFit.fill),
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
          ),
        );
      },
    ),
  );

  /// 释放帧订阅与解码图像。
  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_frames.addAll);
    RustXvgPictureCache.instance.onParseMiss = null;
    _image?.dispose();
    super.dispose();
  }
}

/// 在实际子树进入 paint 时取单调时钟。
class _PaintProbe extends SingleChildRenderObjectWidget {
  /// 接收画布绘制回调及被测子树。
  const _PaintProbe({required this.onPaint, required super.child});

  /// 在调用子树 paint 前执行的回调。
  final VoidCallback onPaint;

  /// 创建绘制探针。
  @override
  _RenderPaintProbe createRenderObject(BuildContext context) =>
      _RenderPaintProbe(onPaint);

  /// 更新绘制回调。
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPaintProbe renderObject,
  ) {
    renderObject.onPaint = onPaint;
  }
}

/// 转发普通绘制并记录进入时刻。
class _RenderPaintProbe extends RenderProxyBox {
  /// 初始化绘制回调。
  _RenderPaintProbe(this.onPaint);

  /// 记录当前帧的回调。
  VoidCallback onPaint;

  /// 采集时间并继续常规 paint。
  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}
