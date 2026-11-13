// fill-rule / clip-rule / mask-type 三组测试共用的渲染工具：支持渐变表、
// 近似遮罩开关，并能直接拿到解析后的文档以便检查节点缓存。

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:xvg/src/animation/animated_svg_painter.dart';
import 'package:xvg/src/animation/svg_document_parser.dart';
import 'package:xvg/src/animation/svg_theme.dart';

import 'pixel_test_utils.dart';

/// 全画布红色矩形：被裁剪/遮罩的内容。
const String kRedFill = '<rect width="100" height="100" fill="#f00"/>';

/// 外框 10..90、内框 30..70、同向嵌套的双子路径 `d`。
const String kNestedSameDir = 'M10 10H90V90H10Z M30 30H70V70H30Z';

/// 外框 10..90、内框 30..70、反向嵌套的双子路径 `d`。
const String kNestedReverseDir = 'M10 10H90V90H10Z M30 30V70H70V30Z';

/// 把 [body] 包进 100x100 `<svg>` 并解析。
SvgDocument parseBody(String body) => parsePixelDoc(body);

/// 在 [time] 处渲染已解析的 [document]；[approximate] 控制 mask 近似管线。
Future<ByteData> renderDoc(
  SvgDocument document, {
  Duration time = Duration.zero,
  bool approximate = false,
}) async {
  final recorder = ui.PictureRecorder();
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
    approximateMasks: () => approximate,
  ).paint(Canvas(recorder), Size(kPixelSize.toDouble(), kPixelSize.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(kPixelSize, kPixelSize);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  return bytes!;
}

/// 解析 [body] 后渲染。
Future<ByteData> renderBody(
  String body, {
  Duration time = Duration.zero,
  bool approximate = false,
}) => renderDoc(parseBody(body), time: time, approximate: approximate);

/// 两张像素图是否逐字节相同。
bool samePixels(ByteData a, ByteData b) {
  if (a.lengthInBytes != b.lengthInBytes) return false;
  for (var i = 0; i < a.lengthInBytes; i++) {
    if (a.getUint8(i) != b.getUint8(i)) return false;
  }
  return true;
}
