// `LIB=cmdcount` mode: quantifies the "svgx generates more draw commands per
// frame than flutter_svg" hypothesis from the Android raster-gap
// investigation (see CLAUDE.md / doc/performance-benchmarks.md). Renders all
// 1000 MDI icons through each library's own picture-recording code path —
// not through a live widget tree — and counts the primitive Canvas ops
// (drawPath/drawImage/etc.) each one records into its `ui.Picture`. That
// count is the thing Impeller's `SurfaceFrame::Encode` actually has to walk
// when a picture is later played back into a frame, so it is a direct proxy
// for the GPU command-encoding cost the trace investigation pointed at —
// unlike counting Canvas calls at paint time, which would see only one
// `drawPicture` per icon on both sides since both libraries cache a
// `ui.Picture` per source string.
//
// svgx: exercises `RustSvgxPictureCache.getOrRender`, the exact method
// `SvgxStatic` calls, via its `debugWrapRecordingCanvas` test hook.
// flutter_svg: exercises `vector_graphics_compiler`'s `encodeSvg` +
// `vector_graphics`'s `FlutterVectorGraphicsListener`, the same compile-then-
// decode path `SvgPicture.string` runs internally, via the codec's
// `PictureFactory` injection point (`@visibleForTesting` but not otherwise
// private) — no changes to either third-party package.
//
// `LIB=cmdcount` 模式：量化 Android raster 差距排查里"svgx 每帧生成的绘制命令数
// 明显多于 flutter_svg"这一假设（见 CLAUDE.md / doc/performance-benchmarks.md）。
// 让全部 1000 个 MDI 图标各自走一遍两个库自己的 picture 录制代码路径——而非真实
// 控件树——并统计每次录制进 `ui.Picture` 的原始 Canvas 指令数
// （drawPath/drawImage 等）。这正是 picture 被回放进一帧时 Impeller 的
// `SurfaceFrame::Encode` 真正要遍历的东西，是 trace 排查指向的 GPU 命令编码开销
// 的直接代理——不同于在 paint 时拦截 Canvas 调用，那样两边都只会看到每个图标
// 一次 `drawPicture`，因为两个库都按源串缓存了一份 `ui.Picture`。
//
// svgx：通过 `debugWrapRecordingCanvas` 测试钩子跑 `RustSvgxPictureCache.
// getOrRender`——与 `SvgxStatic` 调用的是同一个方法。
// flutter_svg：通过编解码器的 `PictureFactory` 注入点（标了
// `@visibleForTesting` 但并非语言层面私有）跑 `vector_graphics_compiler` 的
// `encodeSvg` + `vector_graphics` 的 `FlutterVectorGraphicsListener`——与
// `SvgPicture.string` 内部跑的是同一条"编译再解码"路径，不改动任何第三方包。

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' show Canvas;
import 'package:svgx/src/rust/api/svg.dart' show parseSvg;
import 'package:svgx/svgx.dart';
import 'package:vector_graphics/src/listener.dart' show FlutterVectorGraphicsListener, PictureFactory;
import 'package:vector_graphics_codec/vector_graphics_codec.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart' show encodeSvg;

import 'mdi_icons_1000.dart';
import 'report_sink.dart';

/// Wraps a real [Canvas], counting calls to the primitive draw methods a
/// recorded [ui.Picture] is actually made of, then forwarding every call
/// (draw or otherwise) unchanged to the wrapped canvas via [noSuchMethod] —
/// [Canvas] has ~40 methods and this tool only cares about a dozen of them.
///
/// 包装一个真实 [Canvas]，统计构成一份录制 [ui.Picture] 的原始绘制方法调用次数，
/// 再通过 [noSuchMethod] 把每次调用（无论是否被统计）原样转发给被包装的
/// canvas——[Canvas] 有约 40 个方法，本工具只关心其中一小部分。
///
/// Example:
/// ```dart
/// final counting = CountingCanvas(Canvas(recorder));
/// somePainter.paint(counting, size);
/// print(counting.total);
/// ```
class CountingCanvas implements Canvas {
  /// Creates a counting wrapper around [_inner]. / 创建对 [_inner] 的计数包装。
  CountingCanvas(this._inner);

  final Canvas _inner;

  /// Per-method call counts, keyed by method name. / 按方法名计数的调用次数。
  final Map<String, int> counts = <String, int>{};

  /// Sum of every counted draw call. / 全部被统计的绘制调用之和。
  int get total => counts.values.fold(0, (a, b) => a + b);

  int _bump(String name) => counts[name] = (counts[name] ?? 0) + 1;

  @override
  void drawPath(ui.Path path, ui.Paint paint) {
    _bump('drawPath');
    _inner.drawPath(path, paint);
  }

  @override
  void drawImage(ui.Image image, ui.Offset offset, ui.Paint paint) {
    _bump('drawImage');
    _inner.drawImage(image, offset, paint);
  }

  @override
  void drawImageRect(ui.Image image, ui.Rect src, ui.Rect dst, ui.Paint paint) {
    _bump('drawImageRect');
    _inner.drawImageRect(image, src, dst, paint);
  }

  @override
  void drawImageNine(ui.Image image, ui.Rect center, ui.Rect dst, ui.Paint paint) {
    _bump('drawImageNine');
    _inner.drawImageNine(image, center, dst, paint);
  }

  @override
  void drawRect(ui.Rect rect, ui.Paint paint) {
    _bump('drawRect');
    _inner.drawRect(rect, paint);
  }

  @override
  void drawRRect(ui.RRect rrect, ui.Paint paint) {
    _bump('drawRRect');
    _inner.drawRRect(rrect, paint);
  }

  @override
  void drawOval(ui.Rect rect, ui.Paint paint) {
    _bump('drawOval');
    _inner.drawOval(rect, paint);
  }

  @override
  void drawCircle(ui.Offset c, double radius, ui.Paint paint) {
    _bump('drawCircle');
    _inner.drawCircle(c, radius, paint);
  }

  @override
  void drawArc(ui.Rect rect, double startAngle, double sweepAngle, bool useCenter, ui.Paint paint) {
    _bump('drawArc');
    _inner.drawArc(rect, startAngle, sweepAngle, useCenter, paint);
  }

  @override
  void drawLine(ui.Offset p1, ui.Offset p2, ui.Paint paint) {
    _bump('drawLine');
    _inner.drawLine(p1, p2, paint);
  }

  @override
  void drawPoints(ui.PointMode pointMode, List<ui.Offset> points, ui.Paint paint) {
    _bump('drawPoints');
    _inner.drawPoints(pointMode, points, paint);
  }

  @override
  void drawVertices(ui.Vertices vertices, ui.BlendMode blendMode, ui.Paint paint) {
    _bump('drawVertices');
    _inner.drawVertices(vertices, blendMode, paint);
  }

  @override
  void drawAtlas(
    ui.Image atlas,
    List<ui.RSTransform> transforms,
    List<ui.Rect> rects,
    List<ui.Color>? colors,
    ui.BlendMode? blendMode,
    ui.Rect? cullRect,
    ui.Paint paint,
  ) {
    _bump('drawAtlas');
    _inner.drawAtlas(atlas, transforms, rects, colors, blendMode, cullRect, paint);
  }

  @override
  void drawShadow(ui.Path path, ui.Color color, double elevation, bool transparentOccluder) {
    _bump('drawShadow');
    _inner.drawShadow(path, color, elevation, transparentOccluder);
  }

  @override
  void drawColor(ui.Color color, ui.BlendMode blendMode) {
    _bump('drawColor');
    _inner.drawColor(color, blendMode);
  }

  @override
  void drawPaint(ui.Paint paint) {
    _bump('drawPaint');
    _inner.drawPaint(paint);
  }

  @override
  void drawPicture(ui.Picture picture) {
    _bump('drawPicture');
    _inner.drawPicture(picture);
  }

  // Everything else (save/restore/clip/transform/…) is forwarded verbatim,
  // uncounted — this tool measures draw-op volume, not the full command
  // stream.
  // 其余方法（save/restore/clip/transform/……）原样转发、不计数——本工具只测
  // 绘制指令的数量，不是完整指令流。
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (!invocation.isMethod) {
      throw UnsupportedError('CountingCanvas: unsupported invocation $invocation');
    }
    return _invokeMethod(_inner, invocation.memberName, invocation.positionalArguments, invocation.namedArguments);
  }

  dynamic _invokeMethod(
    Canvas c,
    Symbol name,
    List<dynamic> positional,
    Map<Symbol, dynamic> named,
  ) {
    // dart:ui's Canvas is a concrete class (not dynamic-dispatch friendly via
    // reflection on AOT/Flutter), so route the handful of non-draw methods we
    // actually need (save/restore/clip*/transform/…) through an explicit
    // switch instead of a generic reflective call.
    //
    // dart:ui 的 Canvas 是具体类（AOT/Flutter 下不便走反射动态派发），所以把
    // 实际会用到的少数几个非绘制方法（save/restore/clip*/transform/……）走
    // 显式 switch 转发，而不是通用反射调用。
    switch (name) {
      case #save:
        c.save();
        return null;
      case #restore:
        c.restore();
        return null;
      case #translate:
        c.translate(positional[0] as double, positional[1] as double);
        return null;
      case #scale:
        c.scale(positional[0] as double, positional.length > 1 ? positional[1] as double : positional[0] as double);
        return null;
      case #clipRect:
        c.clipRect(
          positional[0] as ui.Rect,
          clipOp: (named[#clipOp] as ui.ClipOp?) ?? ui.ClipOp.intersect,
          doAntiAlias: (named[#doAntiAlias] as bool?) ?? true,
        );
        return null;
      case #clipPath:
        c.clipPath(positional[0] as ui.Path, doAntiAlias: (named[#doAntiAlias] as bool?) ?? true);
        return null;
      case #saveLayer:
        c.saveLayer(positional[0] as ui.Rect?, positional[1] as ui.Paint);
        return null;
      case #transform:
        c.transform(positional[0] as Float64List);
        return null;
      case #getSaveCount:
        return c.getSaveCount();
    }
    throw UnimplementedError('CountingCanvas: unforwarded Canvas member $name');
  }
}

/// [PictureFactory] that hands back a [CountingCanvas] and remembers it, so
/// the caller can read [CountingCanvas.total] once the codec has finished
/// decoding into it.
///
/// [PictureFactory]，返回一个 [CountingCanvas] 并记住它，调用方在编解码器完成
/// 解码之后读取其 [CountingCanvas.total]。
class _CountingPictureFactory implements PictureFactory {
  CountingCanvas? lastCanvas;

  @override
  ui.PictureRecorder createPictureRecorder() => ui.PictureRecorder();

  @override
  Canvas createCanvas(ui.PictureRecorder recorder) {
    final counting = CountingCanvas(Canvas(recorder));
    lastCanvas = counting;
    return counting;
  }
}

/// A no-op [VectorGraphicsCodecListener] that only counts path-building
/// callbacks (`onPathMoveTo`/`onPathLineTo`/`onPathCubicTo`/`onPathClose`),
/// giving an exact, per-verb count of what the compiled vector_graphics
/// binary asks a `ui.Path` to do — the same granularity as svgx's
/// `SvgPath.verbs`/`SvgPath.points` (see `_svgxVerbAndPointCount`), so the two
/// counts are directly comparable rather than proxied through a runtime API
/// like `Path.computeMetrics()`.
///
/// 只统计路径构建回调（`onPathMoveTo`/`onPathLineTo`/`onPathCubicTo`/
/// `onPathClose`）的空操作 [VectorGraphicsCodecListener]，给出编译后的
/// vector_graphics 二进制要求 `ui.Path` 做什么的精确逐动词计数——与 svgx 的
/// `SvgPath.verbs`/`SvgPath.points`（见 `_svgxVerbAndPointCount`）粒度一致，
/// 两侧计数因此可以直接比较，而不必借助 `Path.computeMetrics()` 这类运行时
/// 代理指标。
class _VerbCountingListener extends VectorGraphicsCodecListener {
  int verbCount = 0;
  int pointCount = 0;

  @override
  void onPathMoveTo(double x, double y) {
    verbCount++;
    pointCount++;
  }

  @override
  void onPathLineTo(double x, double y) {
    verbCount++;
    pointCount++;
  }

  @override
  void onPathCubicTo(double x1, double y1, double x2, double y2, double x3, double y3) {
    verbCount++;
    pointCount += 3;
  }

  @override
  void onPathClose() {
    verbCount++;
  }

  // Everything below is irrelevant to verb/point counting and intentionally
  // a no-op. / 以下均与逐动词/坐标点计数无关，刻意留空。
  @override
  void onSize(double width, double height) {}
  @override
  void onPaintObject({
    required int color,
    required int? strokeCap,
    required int? strokeJoin,
    required int blendMode,
    required double? strokeMiterLimit,
    required double? strokeWidth,
    required int paintStyle,
    required int id,
    required int? shaderId,
  }) {}
  @override
  void onPathStart(int id, int fillType) {}
  @override
  void onPathFinished() {}
  @override
  void onDrawPath(int pathId, int? paintId, int? patternId) {}
  @override
  void onDrawVertices(Float32List vertices, Uint16List? indices, int? paintId) {}
  @override
  void onSaveLayer(int paintId) {}
  @override
  void onClipPath(int pathId) {}
  @override
  void onRestoreLayer() {}
  @override
  void onMask() {}
  @override
  void onRadialGradient(
    double centerX,
    double centerY,
    double radius,
    double? focalX,
    double? focalY,
    Int32List colors,
    Float32List? offsets,
    Float64List? transform,
    int tileMode,
    int id,
  ) {}
  @override
  void onLinearGradient(
    double fromX,
    double fromY,
    double toX,
    double toY,
    Int32List colors,
    Float32List? offsets,
    int tileMode,
    int id,
  ) {}
  @override
  void onTextConfig(
    String text,
    String? fontFamily,
    double xAnchorMultiplier,
    int fontWeight,
    double fontSize,
    int decoration,
    int decorationStyle,
    int decorationColor,
    int id,
  ) {}
  @override
  void onDrawText(int textId, int? fillId, int? strokeId, int? patternId) {}
  @override
  void onImage(int imageId, int format, Uint8List data, {VectorGraphicsErrorListener? onError}) {}
  @override
  void onDrawImage(int imageId, double x, double y, double width, double height, Float64List? transform) {}
  @override
  void onPatternStart(int patternId, double x, double y, double width, double height, Float64List transform) {}
  @override
  void onTextPosition(
    int textPositionId,
    double? x,
    double? y,
    double? dx,
    double? dy,
    bool reset,
    Float64List? transform,
  ) {}
  @override
  void onUpdateTextPosition(int textPositionId) {}
}

/// Sums `verbs.length`/`points.length ~/ 2` across every path in [source]'s
/// parsed `SvgScene` — the exact verb/point counts svgx's Rust parser
/// produced, at the same granularity `_VerbCountingListener` counts for
/// flutter_svg (moveTo/lineTo/cubicTo/close, 1/1/3/0 points respectively).
///
/// 汇总 [source] 解析出的 `SvgScene` 里每条路径的 `verbs.length`/
/// `points.length ~/ 2`——svgx Rust 解析器产出的精确动词/坐标点数，与
/// `_VerbCountingListener` 给 flutter_svg 计数的粒度一致（moveTo/lineTo/
/// cubicTo/close 分别对应 1/1/3/0 个坐标点）。
(int verbs, int points) _svgxVerbAndPointCount(String source) {
  final scene = parseSvg(data: source);
  var verbs = 0;
  var points = 0;
  for (final path in scene.paths) {
    verbs += path.verbs.length;
    points += path.points.length ~/ 2;
  }
  return (verbs, points);
}

/// One icon's measured draw-op count and path complexity for each library.
/// 单个图标在两个库下各自测得的绘制指令数与路径复杂度。
class CmdCountRow {
  const CmdCountRow(
    this.svgx,
    this.flutterSvg,
    this.svgxVerbs,
    this.svgxPoints,
    this.flutterSvgVerbs,
    this.flutterSvgPoints,
  );

  /// svgx's `getOrRender` draw-op count for this icon. / 该图标在 svgx `getOrRender` 下的绘制指令数。
  final int svgx;

  /// flutter_svg's compile+decode draw-op count for this icon. / 该图标在 flutter_svg 编译+解码下的绘制指令数。
  final int flutterSvg;

  /// svgx path verb count (moveTo/lineTo/cubicTo/close) for this icon.
  /// 该图标在 svgx 下的路径动词数（moveTo/lineTo/cubicTo/close）。
  final int svgxVerbs;

  /// svgx path coordinate-pair count for this icon. / 该图标在 svgx 下的路径坐标点数。
  final int svgxPoints;

  /// flutter_svg path verb count for this icon. / 该图标在 flutter_svg 下的路径动词数。
  final int flutterSvgVerbs;

  /// flutter_svg path coordinate-pair count for this icon. / 该图标在 flutter_svg 下的路径坐标点数。
  final int flutterSvgPoints;
}

/// Runs the draw-op count comparison over every icon in [mdiIcons1000],
/// through each library's own picture-recording code path (no widget tree,
/// no GPU rasterization — see the file header). Prints one report to stdout
/// via [emitReport] and exits.
///
/// 让 [mdiIcons1000] 里的每个图标各自走一遍两个库自己的 picture 录制代码路径
/// （无控件树、无 GPU 光栅化——见文件头）来跑绘制指令数对比。通过 [emitReport]
/// 把一份报告打印到 stdout 后退出。
Future<void> runCmdCountBench() async {
  final rows = <CmdCountRow>[];
  for (final source in mdiIcons1000) {
    // Fresh render every time: a cache hit would skip picture recording
    // entirely and read back 0.
    // 每次都强制重新渲染：缓存命中会完全跳过 picture 录制，读回 0。
    RustSvgxPictureCache.instance.clear();
    final svgxCounter = _CountingCanvasCapture();
    RustSvgxPictureCache.debugWrapRecordingCanvas = (c) {
      final counting = CountingCanvas(c);
      svgxCounter.canvas = counting;
      return counting;
    };
    RustSvgxPictureCache.instance.getOrRender(source);
    final svgxCount = svgxCounter.canvas!.total;

    // Match flutter_svg's own runtime call (`loaders.dart`'s `SvgStringLoader`):
    // both path-boolean-op optimizers are off on-device because they require
    // the native `libpathops` library, which flutter_svg never initializes at
    // runtime (only the build-time asset transformer does). Leaving them on
    // here would throw "PathOps library was not initialized" — not a real
    // difference between the two libraries' production behavior.
    //
    // 与 flutter_svg 自己运行时的调用一致（`loaders.dart` 的
    // `SvgStringLoader`）：两个路径布尔运算优化器在真机上都关闭，因为它们依赖
    // 原生 `libpathops` 库，而 flutter_svg 运行时从不初始化它（只有构建期资源
    // 转换器才会）。这里若开着会抛 "PathOps library was not initialized"——
    // 不是两个库生产行为的真实差异。
    final bytes = encodeSvg(
      xml: source,
      debugName: 'cmdcount',
      enableClippingOptimizer: false,
      enableMaskingOptimizer: false,
      enableOverdrawOptimizer: false,
    );
    final factory = _CountingPictureFactory();
    final listener = FlutterVectorGraphicsListener(pictureFactory: factory);
    const VectorGraphicsCodec().decode(ByteData.sublistView(bytes), listener);
    final pictureInfo = listener.toPicture();
    pictureInfo.picture.dispose();
    final flutterSvgCount = factory.lastCanvas!.total;

    // Verb/point complexity, at the codec's own decode granularity — reuses
    // the same compiled `bytes` from the draw-op count above rather than
    // re-encoding.
    // 逐动词/坐标点复杂度，用编解码器自身的解码粒度——复用上面绘制指令计数
    // 时已经编译好的 `bytes`，不重新编译。
    final verbListener = _VerbCountingListener();
    const VectorGraphicsCodec().decode(ByteData.sublistView(bytes), verbListener);
    final (svgxVerbs, svgxPoints) = _svgxVerbAndPointCount(source);

    rows.add(
      CmdCountRow(
        svgxCount,
        flutterSvgCount,
        svgxVerbs,
        svgxPoints,
        verbListener.verbCount,
        verbListener.pointCount,
      ),
    );
  }
  RustSvgxPictureCache.debugWrapRecordingCanvas = null;
  RustSvgxPictureCache.instance.clear();

  final svgxTotal = rows.fold<int>(0, (a, r) => a + r.svgx);
  final flutterSvgTotal = rows.fold<int>(0, (a, r) => a + r.flutterSvg);
  final svgxAvg = svgxTotal / rows.length;
  final flutterSvgAvg = flutterSvgTotal / rows.length;
  final ratio = flutterSvgTotal == 0 ? double.infinity : svgxTotal / flutterSvgTotal;

  final svgxVerbTotal = rows.fold<int>(0, (a, r) => a + r.svgxVerbs);
  final flutterVerbTotal = rows.fold<int>(0, (a, r) => a + r.flutterSvgVerbs);
  final svgxPointTotal = rows.fold<int>(0, (a, r) => a + r.svgxPoints);
  final flutterPointTotal = rows.fold<int>(0, (a, r) => a + r.flutterSvgPoints);
  final verbRatio = flutterVerbTotal == 0 ? double.infinity : svgxVerbTotal / flutterVerbTotal;
  final pointRatio = flutterPointTotal == 0 ? double.infinity : svgxPointTotal / flutterPointTotal;

  final buf = StringBuffer()
    ..writeln('=== CMD COUNT REPORT (icons=${rows.length}) ===')
    ..writeln('svgx        : total=$svgxTotal avg=${svgxAvg.toStringAsFixed(2)}')
    ..writeln('flutter_svg : total=$flutterSvgTotal avg=${flutterSvgAvg.toStringAsFixed(2)}')
    ..writeln('ratio (svgx/flutter_svg) = ${ratio.toStringAsFixed(3)}')
    ..writeln()
    ..writeln('--- per-drawPath complexity (verb/point counts, moveTo/lineTo/cubicTo/close granularity) ---')
    ..writeln(
      'svgx        : verbs_total=$svgxVerbTotal verbs_avg=${(svgxVerbTotal / rows.length).toStringAsFixed(2)} '
      'points_total=$svgxPointTotal points_avg=${(svgxPointTotal / rows.length).toStringAsFixed(2)}',
    )
    ..writeln(
      'flutter_svg : verbs_total=$flutterVerbTotal verbs_avg=${(flutterVerbTotal / rows.length).toStringAsFixed(2)} '
      'points_total=$flutterPointTotal points_avg=${(flutterPointTotal / rows.length).toStringAsFixed(2)}',
    )
    ..writeln('verb ratio (svgx/flutter_svg)  = ${verbRatio.toStringAsFixed(3)}')
    ..writeln('point ratio (svgx/flutter_svg) = ${pointRatio.toStringAsFixed(3)}')
    ..writeln('=== END CMD COUNT REPORT ===');
  emitReport(buf.toString());
  exit(0);
}

/// Tiny mutable box so the `debugWrapRecordingCanvas` closure below can hand
/// its [CountingCanvas] back to the caller after `getOrRender` returns.
///
/// 小型可变容器，让下面的 `debugWrapRecordingCanvas` 闭包能在 `getOrRender`
/// 返回后把它的 [CountingCanvas] 交回调用方。
class _CountingCanvasCapture {
  CountingCanvas? canvas;
}

/// Minimal screen for `LIB=cmdcount`: shows a status label and kicks off
/// [runCmdCountBench] after the first frame, purely so the engine has
/// something to paint while the (CPU-only, no-GPU) counting runs — a bare
/// `await runCmdCountBench()` with no widget tree at all left the real device
/// on a black screen with no visible sign the run was progressing.
///
/// `LIB=cmdcount` 的最小界面：显示一个状态文案，首帧之后启动
/// [runCmdCountBench]——单纯是为了让引擎在（纯 CPU、无 GPU）计数运行期间有
/// 东西可画；完全没有控件树、直接 `await runCmdCountBench()` 会让真机停在黑屏，
/// 看不出运行是否在推进。
class CmdCountScreen extends StatefulWidget {
  /// Creates the cmdcount status screen. / 创建 cmdcount 状态界面。
  const CmdCountScreen({super.key});

  @override
  State<CmdCountScreen> createState() => _CmdCountScreenState();
}

class _CmdCountScreenState extends State<CmdCountScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => runCmdCountBench());
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('counting draw ops for 1000 icons...')),
    );
  }
}
