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

  // --- "How it's drawn" instrumentation (deep-dive six): save/restore
  // nesting, transform-family calls, and Paint churn — added once deep-dive
  // four/five had ruled out "what's drawn" (command count, per-path
  // verb/point complexity) as the cause of the Android raster gap.
  //
  // "怎么画"的插桩（深挖六）：save/restore 嵌套、变换类调用、Paint 状态切换——
  // 在深挖四/五排除了"画什么"（命令数、单条路径 verb/点复杂度）作为 Android
  // raster 差距的根因之后加入。

  /// `save()` call count. / `save()` 调用次数。
  int saveCount = 0;

  /// `restore()` call count. / `restore()` 调用次数。
  int restoreCount = 0;

  /// `saveLayer()` call count — counted separately from [saveCount] since it
  /// implies an offscreen layer, a materially different cost.
  /// `saveLayer()` 调用次数——与 [saveCount] 分开计，因为它意味着一次离屏层，
  /// 成本量级不同。
  int saveLayerCount = 0;

  /// Peak `save()` nesting depth reached (relative to this canvas' starting
  /// depth). / `save()` 嵌套深度的峰值（相对本 canvas 的起始深度）。
  int peakSaveDepth = 0;

  int _saveDepth = 0;

  /// `translate()`/`scale()`/`transform()` call count, combined.
  /// `translate()`/`scale()`/`transform()` 调用次数之和。
  int transformCallCount = 0;

  /// Number of draw calls that carried a non-null [ui.Paint].
  /// 携带非空 [ui.Paint] 的绘制调用次数。
  int paintArgCount = 0;

  /// Number of consecutive draw-call Paint arguments whose (color, blend
  /// mode, style, stroke width) tuple differs from the previous draw call's —
  /// a proxy for how often the GPU backend has to re-bind paint state instead
  /// of reusing what's already bound.
  ///
  /// 相邻两次绘制调用的 Paint（颜色、混合模式、style、描边宽度）元组不同的
  /// 次数——用作 GPU 后端要重新绑定 paint 状态、而非复用已绑定状态的频率代理。
  int paintChangeCount = 0;

  (int, ui.BlendMode, ui.PaintingStyle, double)? _lastPaintDescriptor;

  void _trackPaint(ui.Paint? paint) {
    if (paint == null) return;
    paintArgCount++;
    final descriptor = (paint.color.toARGB32(), paint.blendMode, paint.style, paint.strokeWidth);
    if (_lastPaintDescriptor != null && _lastPaintDescriptor != descriptor) {
      paintChangeCount++;
    }
    _lastPaintDescriptor = descriptor;
  }

  /// Every [ui.Path] handed to [drawPath], in call order — the exact objects
  /// the rasterizer will have to fill, kept so geometry/topology (contour
  /// count, fill rule, arc length, bounds) can be measured off the real
  /// path rather than off either library's intermediate representation.
  ///
  /// 按调用顺序记录交给 [drawPath] 的每个 [ui.Path]——正是光栅化器要填充的那些
  /// 对象，留存下来以便直接在真实 path 上测量几何/拓扑（contour 数、填充规则、
  /// 弧长、包围盒），而不是在两个库各自的中间表示上测。
  final List<ui.Path> recordedPaths = <ui.Path>[];

  @override
  void drawPath(ui.Path path, ui.Paint paint) {
    _bump('drawPath');
    _trackPaint(paint);
    recordedPaths.add(path);
    _inner.drawPath(path, paint);
  }

  @override
  void drawImage(ui.Image image, ui.Offset offset, ui.Paint paint) {
    _bump('drawImage');
    _trackPaint(paint);
    _inner.drawImage(image, offset, paint);
  }

  @override
  void drawImageRect(ui.Image image, ui.Rect src, ui.Rect dst, ui.Paint paint) {
    _bump('drawImageRect');
    _trackPaint(paint);
    _inner.drawImageRect(image, src, dst, paint);
  }

  @override
  void drawImageNine(ui.Image image, ui.Rect center, ui.Rect dst, ui.Paint paint) {
    _bump('drawImageNine');
    _trackPaint(paint);
    _inner.drawImageNine(image, center, dst, paint);
  }

  @override
  void drawRect(ui.Rect rect, ui.Paint paint) {
    _bump('drawRect');
    _trackPaint(paint);
    _inner.drawRect(rect, paint);
  }

  @override
  void drawRRect(ui.RRect rrect, ui.Paint paint) {
    _bump('drawRRect');
    _trackPaint(paint);
    _inner.drawRRect(rrect, paint);
  }

  @override
  void drawOval(ui.Rect rect, ui.Paint paint) {
    _bump('drawOval');
    _trackPaint(paint);
    _inner.drawOval(rect, paint);
  }

  @override
  void drawCircle(ui.Offset c, double radius, ui.Paint paint) {
    _bump('drawCircle');
    _trackPaint(paint);
    _inner.drawCircle(c, radius, paint);
  }

  @override
  void drawArc(ui.Rect rect, double startAngle, double sweepAngle, bool useCenter, ui.Paint paint) {
    _bump('drawArc');
    _trackPaint(paint);
    _inner.drawArc(rect, startAngle, sweepAngle, useCenter, paint);
  }

  @override
  void drawLine(ui.Offset p1, ui.Offset p2, ui.Paint paint) {
    _bump('drawLine');
    _trackPaint(paint);
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
    _trackPaint(paint);
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
        saveCount++;
        _saveDepth++;
        if (_saveDepth > peakSaveDepth) peakSaveDepth = _saveDepth;
        c.save();
        return null;
      case #restore:
        restoreCount++;
        if (_saveDepth > 0) _saveDepth--;
        c.restore();
        return null;
      case #translate:
        transformCallCount++;
        c.translate(positional[0] as double, positional[1] as double);
        return null;
      case #scale:
        transformCallCount++;
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
        saveLayerCount++;
        // `saveLayer` also opens a save-stack frame — count it toward the
        // nesting depth alongside plain `save()`.
        // `saveLayer` 同样会开启一层保存栈——与普通 `save()` 一起计入嵌套深度。
        _saveDepth++;
        if (_saveDepth > peakSaveDepth) peakSaveDepth = _saveDepth;
        c.saveLayer(positional[0] as ui.Rect?, positional[1] as ui.Paint);
        return null;
      case #transform:
        transformCallCount++;
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

  /// The verb opcodes in stream order, using svgx's `SvgPath.verbs` encoding
  /// (0=move 1=line 2=quad 3=cubic 4=close) so the two sides' sequences can be
  /// diffed element by element.
  ///
  /// 按流顺序记录的动词操作码，采用 svgx `SvgPath.verbs` 的编码
  /// （0 移动 1 直线 2 二次 3 三次 4 闭合），以便两侧序列可逐元素 diff。
  final List<int> verbs = <int>[];

  /// Flattened x,y coordinate pairs in stream order, matching [verbs].
  /// 与 [verbs] 对应、按流顺序展平的 x,y 坐标对。
  final List<double> points = <double>[];

  /// `fillType` raw values seen on `onPathStart` (0=nonZero, 1=evenOdd, per
  /// the codec's encoding). / `onPathStart` 上看到的 `fillType` 原始值
  /// （按编解码器编码：0 非零环绕，1 奇偶）。
  final List<int> fillTypes = <int>[];

  @override
  void onPathMoveTo(double x, double y) {
    verbCount++;
    pointCount++;
    verbs.add(0);
    points..add(x)..add(y);
  }

  @override
  void onPathLineTo(double x, double y) {
    verbCount++;
    pointCount++;
    verbs.add(1);
    points..add(x)..add(y);
  }

  @override
  void onPathCubicTo(double x1, double y1, double x2, double y2, double x3, double y3) {
    verbCount++;
    pointCount += 3;
    verbs.add(3);
    points..add(x1)..add(y1)..add(x2)..add(y2)..add(x3)..add(y3);
  }

  @override
  void onPathClose() {
    verbCount++;
    verbs.add(4);
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
  void onPathStart(int id, int fillType) {
    fillTypes.add(fillType);
  }

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

/// One side's raw verb/point/fill-rule stream for a single icon, flattened
/// across all of that icon's paths — the input to the element-by-element diff
/// that upgrades deep-dive five's "totals are equal" into "sequences are
/// identical".
///
/// 单个图标在某一侧的原始动词/坐标/填充规则流，跨该图标全部路径展平——用于逐元素
/// diff，把深挖五的"总量相等"升级成"序列完全一致"。
class VerbStream {
  /// Wraps the three parallel streams. / 包装三条并行的流。
  const VerbStream(this.verbs, this.points, this.fillTypes);

  /// Verb opcodes (0=move 1=line 2=quad 3=cubic 4=close). / 动词操作码。
  final List<int> verbs;

  /// Flattened x,y coordinate pairs. / 展平的 x,y 坐标对。
  final List<double> points;

  /// Per-path fill rule: 0=nonZero, 1=evenOdd. / 逐路径填充规则：0 非零，1 奇偶。
  final List<int> fillTypes;
}

/// Reads svgx's parsed scene into a [VerbStream] at the same granularity
/// [_VerbCountingListener] produces for flutter_svg.
///
/// 把 svgx 解析出的场景读成 [VerbStream]，粒度与 [_VerbCountingListener] 为
/// flutter_svg 产出的一致。
VerbStream _svgxVerbStream(String source) {
  final scene = parseSvg(data: source);
  final verbs = <int>[];
  final points = <double>[];
  final fillTypes = <int>[];
  for (final path in scene.paths) {
    fillTypes.add(path.evenOdd ? 1 : 0);
    verbs.addAll(path.verbs);
    points.addAll(path.points);
  }
  return VerbStream(verbs, points, fillTypes);
}

/// Geometry/topology of one icon's real [ui.Path] objects — the variables that
/// actually drive fill tessellation cost, as opposed to the verb/point totals
/// deep-dive five already proved equal.
///
/// [contours] counts independent sub-paths (one per `moveTo`), which is also
/// exactly what `Path.computeMetrics()` enumerates; [arcLength] sums every
/// contour's perimeter, a direct proxy for the anti-aliased edge work; and
/// [evenOddPaths] tracks the fill rule, since even-odd fills take a more
/// expensive stencil route than non-zero on both Skia and Impeller.
///
/// 单个图标真实 [ui.Path] 对象的几何/拓扑——真正决定填充 tessellation 成本的变量，
/// 而非深挖五已证明相等的动词/点总量。[contours] 统计独立子路径数（每个 `moveTo`
/// 一个），也正是 `Path.computeMetrics()` 枚举出来的东西；[arcLength] 汇总各
/// contour 周长，是抗锯齿边缘工作量的直接代理；[evenOddPaths] 记录填充规则，因为
/// 奇偶填充在 Skia 与 Impeller 上都走比非零环绕更贵的 stencil 路径。
class GeomStats {
  /// Measures [paths] (one icon's worth of `drawPath` arguments).
  /// 测量 [paths]（一个图标的全部 `drawPath` 参数）。
  factory GeomStats.from(List<ui.Path> paths) {
    var contours = 0;
    var arcLength = 0.0;
    var evenOdd = 0;
    var minL = double.infinity, minT = double.infinity;
    var maxR = -double.infinity, maxB = -double.infinity;
    for (final path in paths) {
      if (path.fillType == ui.PathFillType.evenOdd) evenOdd++;
      for (final metric in path.computeMetrics()) {
        contours++;
        arcLength += metric.length;
      }
      final b = path.getBounds();
      if (b.left < minL) minL = b.left;
      if (b.top < minT) minT = b.top;
      if (b.right > maxR) maxR = b.right;
      if (b.bottom > maxB) maxB = b.bottom;
    }
    final bounds = paths.isEmpty || minL == double.infinity
        ? ui.Rect.zero
        : ui.Rect.fromLTRB(minL, minT, maxR, maxB);
    return GeomStats._(paths.length, contours, arcLength, evenOdd, bounds);
  }

  const GeomStats._(this.pathCount, this.contours, this.arcLength, this.evenOddPaths, this.bounds);

  /// Number of `drawPath` calls this icon made. / 该图标的 `drawPath` 调用数。
  final int pathCount;

  /// Total independent sub-paths across those paths. / 这些路径的独立子路径总数。
  final int contours;

  /// Summed contour perimeter, in the picture's own coordinate space.
  /// contour 周长之和（在 picture 自身坐标空间内）。
  final double arcLength;

  /// How many of those paths use the even-odd fill rule. / 其中使用奇偶填充规则的路径数。
  final int evenOddPaths;

  /// Union of every path's bounds — catches a coordinate-space mismatch
  /// between the two libraries. / 所有路径包围盒的并集——用于发现两个库之间的
  /// 坐标空间差异。
  final ui.Rect bounds;
}

/// Snapshot of a [CountingCanvas]'s "how it's drawn" counters at the end of
/// one icon's recording — save/restore/transform/Paint-churn, the deep-dive-
/// six metrics (see [CountingCanvas]'s corresponding fields for what each
/// one measures).
///
/// [CountingCanvas] 一个图标录制结束时的"怎么画"计数快照——save/restore/
/// transform/Paint 状态切换，深挖六的几项指标（各自含义见 [CountingCanvas]
/// 对应字段）。
class DrawStateCounts {
  /// Captures the current counter values off [canvas]. / 从 [canvas] 上捕获当前计数值。
  DrawStateCounts.from(CountingCanvas canvas)
    : saveCount = canvas.saveCount,
      restoreCount = canvas.restoreCount,
      saveLayerCount = canvas.saveLayerCount,
      peakSaveDepth = canvas.peakSaveDepth,
      transformCallCount = canvas.transformCallCount,
      paintArgCount = canvas.paintArgCount,
      paintChangeCount = canvas.paintChangeCount;

  final int saveCount;
  final int restoreCount;
  final int saveLayerCount;
  final int peakSaveDepth;
  final int transformCallCount;
  final int paintArgCount;
  final int paintChangeCount;
}

/// One icon's measured draw-op count, path complexity, and draw-state churn
/// for each library.
/// 单个图标在两个库下各自测得的绘制指令数、路径复杂度与绘制状态切换。
class CmdCountRow {
  const CmdCountRow(
    this.svgx,
    this.flutterSvg,
    this.svgxVerbs,
    this.svgxPoints,
    this.flutterSvgVerbs,
    this.flutterSvgPoints,
    this.svgxState,
    this.flutterSvgState, {
    required this.index,
    required this.svgxGeom,
    required this.flutterSvgGeom,
    required this.svgxStream,
    required this.flutterSvgStream,
  });

  /// Index into `mdiIcons1000`, so an outlier can be traced back to its source
  /// string. / 在 `mdiIcons1000` 中的下标，便于把离群图标追溯回源串。
  final int index;

  /// svgx's real-`ui.Path` geometry for this icon. / 该图标在 svgx 下真实 `ui.Path` 的几何。
  final GeomStats svgxGeom;

  /// flutter_svg's real-`ui.Path` geometry for this icon. / 该图标在 flutter_svg 下真实 `ui.Path` 的几何。
  final GeomStats flutterSvgGeom;

  /// svgx's raw verb/point/fill-rule stream for this icon. / 该图标在 svgx 下的原始动词/坐标/填充规则流。
  final VerbStream svgxStream;

  /// flutter_svg's raw verb/point/fill-rule stream for this icon. / 该图标在 flutter_svg 下的原始动词/坐标/填充规则流。
  final VerbStream flutterSvgStream;

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

  /// svgx's save/restore/transform/Paint-churn counts for this icon.
  /// 该图标在 svgx 下的 save/restore/transform/Paint 切换计数。
  final DrawStateCounts svgxState;

  /// flutter_svg's save/restore/transform/Paint-churn counts for this icon.
  /// 该图标在 flutter_svg 下的 save/restore/transform/Paint 切换计数。
  final DrawStateCounts flutterSvgState;
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
  for (var iconIndex = 0; iconIndex < mdiIcons1000.length; iconIndex++) {
    final source = mdiIcons1000[iconIndex];
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
    // Geometry is measured before `toPicture()`/`dispose()` so the captured
    // `ui.Path` objects are read while the decode that produced them is still
    // the most recent state.
    // 几何在 `toPicture()`/`dispose()` 之前测量，确保读取捕获到的 `ui.Path`
    // 对象时，产生它们的那次解码仍是最近状态。
    final flutterSvgGeom = GeomStats.from(factory.lastCanvas!.recordedPaths);
    final svgxGeom = GeomStats.from(svgxCounter.canvas!.recordedPaths);

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
        DrawStateCounts.from(svgxCounter.canvas!),
        DrawStateCounts.from(factory.lastCanvas!),
        index: iconIndex,
        svgxGeom: svgxGeom,
        flutterSvgGeom: flutterSvgGeom,
        svgxStream: _svgxVerbStream(source),
        flutterSvgStream: VerbStream(verbListener.verbs, verbListener.points, verbListener.fillTypes),
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
    ..writeln('point ratio (svgx/flutter_svg) = ${pointRatio.toStringAsFixed(3)}');

  // "How it's drawn": save/restore/saveLayer/transform-family call counts,
  // peak save-nesting depth (max across icons, not summed — depth doesn't
  // add up across icons the way a call count does), and Paint churn.
  //
  // "怎么画"：save/restore/saveLayer/变换类调用次数、save 嵌套深度峰值
  // （跨图标取最大值而非求和——深度不像调用次数那样可以跨图标累加）、以及
  // Paint 状态切换。
  final svgxSaves = rows.fold<int>(0, (a, r) => a + r.svgxState.saveCount);
  final flutterSaves = rows.fold<int>(0, (a, r) => a + r.flutterSvgState.saveCount);
  final svgxRestores = rows.fold<int>(0, (a, r) => a + r.svgxState.restoreCount);
  final flutterRestores = rows.fold<int>(0, (a, r) => a + r.flutterSvgState.restoreCount);
  final svgxSaveLayers = rows.fold<int>(0, (a, r) => a + r.svgxState.saveLayerCount);
  final flutterSaveLayers = rows.fold<int>(0, (a, r) => a + r.flutterSvgState.saveLayerCount);
  final svgxPeakDepth = rows.fold<int>(0, (a, r) => a > r.svgxState.peakSaveDepth ? a : r.svgxState.peakSaveDepth);
  final flutterPeakDepth = rows.fold<int>(
    0,
    (a, r) => a > r.flutterSvgState.peakSaveDepth ? a : r.flutterSvgState.peakSaveDepth,
  );
  final svgxTransforms = rows.fold<int>(0, (a, r) => a + r.svgxState.transformCallCount);
  final flutterTransforms = rows.fold<int>(0, (a, r) => a + r.flutterSvgState.transformCallCount);
  final svgxPaintArgs = rows.fold<int>(0, (a, r) => a + r.svgxState.paintArgCount);
  final flutterPaintArgs = rows.fold<int>(0, (a, r) => a + r.flutterSvgState.paintArgCount);
  final svgxPaintChanges = rows.fold<int>(0, (a, r) => a + r.svgxState.paintChangeCount);
  final flutterPaintChanges = rows.fold<int>(0, (a, r) => a + r.flutterSvgState.paintChangeCount);

  double ratioOf(num svgxVal, num flutterVal) => flutterVal == 0 ? double.infinity : svgxVal / flutterVal;

  buf
    ..writeln()
    ..writeln('--- draw-state churn: save/restore/transform/Paint (deep-dive six) ---')
    ..writeln(
      'save        : svgx=$svgxSaves flutter_svg=$flutterSaves ratio=${ratioOf(svgxSaves, flutterSaves).toStringAsFixed(3)}',
    )
    ..writeln(
      'restore     : svgx=$svgxRestores flutter_svg=$flutterRestores ratio=${ratioOf(svgxRestores, flutterRestores).toStringAsFixed(3)}',
    )
    ..writeln(
      'saveLayer   : svgx=$svgxSaveLayers flutter_svg=$flutterSaveLayers ratio=${ratioOf(svgxSaveLayers, flutterSaveLayers).toStringAsFixed(3)}',
    )
    ..writeln('peakSaveDepth (max across icons): svgx=$svgxPeakDepth flutter_svg=$flutterPeakDepth')
    ..writeln(
      'transform*  : svgx=$svgxTransforms flutter_svg=$flutterTransforms ratio=${ratioOf(svgxTransforms, flutterTransforms).toStringAsFixed(3)}',
    )
    ..writeln(
      'paintArgs   : svgx=$svgxPaintArgs flutter_svg=$flutterPaintArgs ratio=${ratioOf(svgxPaintArgs, flutterPaintArgs).toStringAsFixed(3)}',
    )
    ..writeln(
      'paintChange : svgx=$svgxPaintChanges flutter_svg=$flutterPaintChanges ratio=${ratioOf(svgxPaintChanges, flutterPaintChanges).toStringAsFixed(3)}',
    )
    ;
  _appendGeometryReport(buf, rows);
  buf.writeln('=== END CMD COUNT REPORT ===');
  emitReport(buf.toString());
  exit(0);
}

/// Appends the deep-dive-thirteen geometry/topology section to [buf]: contour
/// counts, fill-rule split, contour arc length, path bounds, and an
/// element-by-element verb/coordinate diff — all per icon, not just summed, so
/// a systematic difference concentrated in a subset of icons can't hide inside
/// an equal total (which is exactly what deep-dive five could not rule out).
///
/// 把深挖十三的几何/拓扑小节追加进 [buf]：contour 数、填充规则占比、contour 弧长、
/// 路径包围盒，以及逐元素的动词/坐标 diff——全部**逐图标**统计而非只看总和，
/// 这样"集中在一部分图标上的系统性差异"就无法藏在相等的总量里（这正是深挖五
/// 排除不掉的东西）。
void _appendGeometryReport(StringBuffer buf, List<CmdCountRow> rows) {
  var svgxContours = 0, fsvgContours = 0;
  var svgxArc = 0.0, fsvgArc = 0.0;
  var svgxEvenOdd = 0, fsvgEvenOdd = 0;
  var svgxPaths = 0, fsvgPaths = 0;
  var contourMismatch = 0, fillRuleMismatch = 0, boundsMismatch = 0;
  var verbSeqMismatch = 0, verbLenMismatch = 0, pointLenMismatch = 0;
  var maxCoordDelta = 0.0;
  var maxCoordDeltaIcon = -1;
  final contourDiffs = <(int index, int delta)>[];
  final arcRatios = <(int index, double ratio)>[];

  for (final r in rows) {
    svgxContours += r.svgxGeom.contours;
    fsvgContours += r.flutterSvgGeom.contours;
    svgxArc += r.svgxGeom.arcLength;
    fsvgArc += r.flutterSvgGeom.arcLength;
    svgxEvenOdd += r.svgxGeom.evenOddPaths;
    fsvgEvenOdd += r.flutterSvgGeom.evenOddPaths;
    svgxPaths += r.svgxGeom.pathCount;
    fsvgPaths += r.flutterSvgGeom.pathCount;

    final cDelta = r.svgxGeom.contours - r.flutterSvgGeom.contours;
    if (cDelta != 0) {
      contourMismatch++;
      contourDiffs.add((r.index, cDelta));
    }
    if (r.svgxGeom.evenOddPaths != r.flutterSvgGeom.evenOddPaths) fillRuleMismatch++;

    final sb = r.svgxGeom.bounds, fb = r.flutterSvgGeom.bounds;
    // 0.05px: well below anything that could change tessellation, but above
    // the float32 round-trip the Rust FFI bridge imposes on coordinates.
    // 0.05px：远低于任何能改变 tessellation 的量级，但高于 Rust FFI 桥对坐标做的
    // float32 往返误差。
    if ((sb.left - fb.left).abs() > 0.05 ||
        (sb.top - fb.top).abs() > 0.05 ||
        (sb.right - fb.right).abs() > 0.05 ||
        (sb.bottom - fb.bottom).abs() > 0.05) {
      boundsMismatch++;
    }

    if (r.flutterSvgGeom.arcLength > 0) {
      arcRatios.add((r.index, r.svgxGeom.arcLength / r.flutterSvgGeom.arcLength));
    }

    final sv = r.svgxStream.verbs, fv = r.flutterSvgStream.verbs;
    if (sv.length != fv.length) {
      verbLenMismatch++;
      verbSeqMismatch++;
    } else {
      for (var i = 0; i < sv.length; i++) {
        if (sv[i] != fv[i]) {
          verbSeqMismatch++;
          break;
        }
      }
    }
    final sp = r.svgxStream.points, fp = r.flutterSvgStream.points;
    if (sp.length != fp.length) {
      pointLenMismatch++;
    } else {
      for (var i = 0; i < sp.length; i++) {
        final d = (sp[i] - fp[i]).abs();
        if (d > maxCoordDelta) {
          maxCoordDelta = d;
          maxCoordDeltaIcon = r.index;
        }
      }
    }
  }

  contourDiffs.sort((a, b) => b.$2.abs().compareTo(a.$2.abs()));
  arcRatios.sort((a, b) => b.$2.compareTo(a.$2));

  String pct(int n, int d) => d == 0 ? 'n/a' : '${(100 * n / d).toStringAsFixed(2)}%';
  double ratio(num a, num b) => b == 0 ? double.infinity : a / b;

  buf
    ..writeln()
    ..writeln('--- geometry & topology of the real ui.Path objects (deep-dive 13) ---')
    ..writeln(
      'contours    : svgx=$svgxContours (avg ${(svgxContours / rows.length).toStringAsFixed(3)})  '
      'flutter_svg=$fsvgContours (avg ${(fsvgContours / rows.length).toStringAsFixed(3)})  '
      'ratio=${ratio(svgxContours, fsvgContours).toStringAsFixed(4)}',
    )
    ..writeln('contours per-icon mismatch: $contourMismatch / ${rows.length} icons')
    ..writeln(
      'arcLength   : svgx=${svgxArc.toStringAsFixed(1)} flutter_svg=${fsvgArc.toStringAsFixed(1)} '
      'ratio=${ratio(svgxArc, fsvgArc).toStringAsFixed(4)}',
    )
    ..writeln(
      'fillRule    : svgx evenOdd=$svgxEvenOdd/$svgxPaths (${pct(svgxEvenOdd, svgxPaths)})  '
      'flutter_svg evenOdd=$fsvgEvenOdd/$fsvgPaths (${pct(fsvgEvenOdd, fsvgPaths)})',
    )
    ..writeln('fillRule per-icon mismatch: $fillRuleMismatch / ${rows.length} icons')
    ..writeln('bounds per-icon mismatch (>0.05px): $boundsMismatch / ${rows.length} icons')
    ..writeln()
    ..writeln('--- element-by-element verb/coordinate diff (upgrades deep-dive 5) ---')
    ..writeln('verb-sequence mismatch : $verbSeqMismatch / ${rows.length} icons '
        '(of which length differs: $verbLenMismatch)')
    ..writeln('point-count mismatch   : $pointLenMismatch / ${rows.length} icons')
    ..writeln('max |coord delta| over length-matched icons: '
        '${maxCoordDelta.toStringAsFixed(6)} (icon #$maxCoordDeltaIcon)');

  if (contourDiffs.isNotEmpty) {
    buf.writeln('top contour-count outliers (icon: svgx-flutter_svg):');
    for (final d in contourDiffs.take(10)) {
      final r = rows.firstWhere((e) => e.index == d.$1);
      buf.writeln(
        '  #${d.$1}: delta=${d.$2}  svgx=${r.svgxGeom.contours} flutter_svg=${r.flutterSvgGeom.contours}',
      );
    }
  }
  if (arcRatios.isNotEmpty) {
    buf.writeln('top arcLength ratio outliers (svgx/flutter_svg):');
    for (final a in arcRatios.take(5)) {
      buf.writeln('  #${a.$1}: ratio=${a.$2.toStringAsFixed(4)}');
    }
    final worst = arcRatios.last;
    buf.writeln('  lowest: #${worst.$1}: ratio=${worst.$2.toStringAsFixed(4)}');
  }
  // `Rect.toString()` is stripped in profile builds, so format the numbers by
  // hand — the absolute coordinate space matters here (it is what the
  // tessellator's flatness tolerance is applied in).
  // profile 构建下 `Rect.toString()` 会被裁掉，所以手工格式化数字——这里的绝对
  // 坐标空间很关键（tessellator 的平坦度容差正是在这个空间里生效的）。
  String fmt(ui.Rect r) =>
      'LTRB(${r.left.toStringAsFixed(3)},${r.top.toStringAsFixed(3)},'
      '${r.right.toStringAsFixed(3)},${r.bottom.toStringAsFixed(3)})';
  buf.writeln(
    'sample bounds (icon #${rows.first.index}): svgx=${fmt(rows.first.svgxGeom.bounds)} '
    'flutter_svg=${fmt(rows.first.flutterSvgGeom.bounds)}',
  );
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
