// 动画路径测试共用的像素渲染工具：在指定时间线位置渲染一份 SVG 文档，
// 并按像素读取 RGBA / alpha。

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animated_svg_painter.dart';
import 'package:xvg/src/animation/svg_document_parser.dart';
import 'package:xvg/src/animation/svg_dom.dart';
import 'package:xvg/src/animation/svg_theme.dart';

/// 渲染画布边长（像素）。
const int kPixelSize = 100;

/// Reads raw RGBA from [key]'s repaint boundary and disposes the image.
/// 从 [key] 的重绘边界读取原始 RGBA 并释放图像。
Future<ByteData> captureBoundaryPixels(
  WidgetTester tester,
  GlobalKey key,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    } finally {
      image.dispose();
    }
  }))!;
}

/// 把 [body] 包进 100x100 的 `<svg>` 并解析成动画文档。
SvgDocument parsePixelDoc(String body) => parseAnimatedSvgDocument(
  '<svg xmlns="http://www.w3.org/2000/svg" width="$kPixelSize" '
  'height="$kPixelSize" viewBox="0 0 $kPixelSize $kPixelSize">$body</svg>',
);

/// 在时间线 [time] 处把 [document] 绘制进 [canvas]。
void _paintAt(Canvas canvas, SvgDocument document, Duration time) {
  AnimatedSvgPainter(
    root: document.root,
    intrinsicSize: Size(document.width, document.height),
    rootViewBoxTransform: document.rootViewBoxTransform,
    clock: ValueNotifier(time),
    theme: const XvgTheme(),
    fit: BoxFit.fill,
    alignment: Alignment.center,
    gradients: document.gradients,
    clipPaths: document.clipPaths,
    masks: document.masks,
    backgroundColor: document.backgroundColor,
  ).paint(canvas, Size(kPixelSize.toDouble(), kPixelSize.toDouble()));
}

/// 只录制不光栅化：执行一遍 [document] 在 [time] 处的绘制逻辑，用于验证绘制
/// 阶段不抛异常。比 [renderAt] 轻，不需要读回像素时用它。
void paintAt(SvgDocument document, Duration time) {
  final recorder = ui.PictureRecorder();
  _paintAt(Canvas(recorder), document, time);
  recorder.endRecording().dispose();
}

/// 在时间线 [time] 处渲染 [document]，返回 rawRgba 像素字节。
Future<ByteData> renderAt(SvgDocument document, Duration time) async {
  final recorder = ui.PictureRecorder();
  _paintAt(Canvas(recorder), document, time);
  final picture = recorder.endRecording();
  final image = await picture.toImage(kPixelSize, kPixelSize);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  return bytes!;
}

/// 直接渲染手工节点树，返回 100x100 的 rawRgba 像素字节。
Future<ByteData> renderRootAt(
  SvgNode root,
  Duration time, {
  Map<String, SvgNode> clipPaths = const {},
  Map<String, SvgNode> masks = const {},
  bool approximateMasks = false,
}) async {
  final clock = ValueNotifier(time);
  final recorder = ui.PictureRecorder();
  final size = Size(kPixelSize.toDouble(), kPixelSize.toDouble());
  AnimatedSvgPainter(
    root: root,
    intrinsicSize: size,
    clock: clock,
    theme: const XvgTheme(),
    fit: BoxFit.fill,
    alignment: Alignment.center,
    clipPaths: clipPaths,
    masks: masks,
    approximateMasks: () => approximateMasks,
  ).paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(kPixelSize, kPixelSize);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  clock.dispose();
  return bytes!;
}

/// ([x], [y]) 处的 alpha。
int alphaAt(ByteData pixels, int x, int y) =>
    pixels.getUint8((y * kPixelSize + x) * 4 + 3);

/// ([x], [y]) 处的红色通道。
int redAt(ByteData pixels, int x, int y) =>
    pixels.getUint8((y * kPixelSize + x) * 4);
