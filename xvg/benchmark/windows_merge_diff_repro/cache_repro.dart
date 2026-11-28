import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'cache_paths.dart';

/// Rust 输出的 SVG 视口宽度。
const svgWidth = 1027.5;

/// Rust 输出的 SVG 视口高度。
const svgHeight = 608.75;

/// 组件布局宽度。
const layoutWidth = 310.0;

/// 组件布局高度。
const layoutHeight = 450.0;

/// 组件内 BoxFit.contain 的等比缩放。
const fit = layoutWidth / svgWidth;

/// 绘制内容在组件内的上边缘。
const fittedTop = (layoutHeight - svgHeight * fit) / 2;

/// 原画笔在 SVG 坐标中的线宽。
const strokeWidth = 1.0627378225326538;

/// 原画笔的颜色。
const strokeColor = ui.Color(0xff9c9c9c);

/// 图像与两条录制路径共用的设备坐标。
typedef Target = ({
  int width,
  int height,
  int textureWidth,
  int textureHeight,
  int x,
  int y,
  double sx,
  double sy,
  double tx,
  double ty,
  double pasteX,
  double pasteY,
});

/// 归档 Windows 第三轮帧 67 和 Android 组件快照的参数。
Target targetFor(bool phone) => phone
    ? (
        width: 872,
        height: 1266,
        textureWidth: 872,
        textureHeight: 518,
        x: 451,
        y: 752,
        sx: 2.8125 * 1.0001433691756272,
        sy: 2.8125 * 1.0008734627188627,
        tx: -0.0625,
        ty: -0.42773812678017945,
        pasteX: -0.0625,
        pasteY: 374.4375,
      )
    : (
        width: 310,
        height: 450,
        textureWidth: 310,
        textureHeight: 184,
        x: 160,
        y: 267,
        sx: 1,
        sy: 1.0018414254487649,
        tx: 0,
        ty: -0.41432072597207503,
        pasteX: 0,
        pasteY: 133,
      );

/// 将 Rust 动词及原始浮点坐标追加到当前路径。
void appendPath(ui.Path path, List<dynamic> verbs, List<dynamic> points) {
  var index = 0;

  /// 消费下一个坐标，与动词要求的点数保持一致。
  double coord() => (points[index++] as num).toDouble();
  for (final verb in verbs) {
    switch (verb) {
      case 0:
        path.moveTo(coord(), coord());
      case 1:
        path.lineTo(coord(), coord());
      case 2:
        path.quadraticBezierTo(coord(), coord(), coord(), coord());
      case 3:
        path.cubicTo(coord(), coord(), coord(), coord(), coord(), coord());
      case 4:
        path.close();
      default:
        throw FormatException('Unknown path verb $verb');
    }
  }
  if (index != points.length) throw const FormatException('Extra path points');
}

/// 使用原视口变换包装 SVG 坐标下的画稿。
ui.Picture recordLayout(ui.Picture artwork, {required bool clip}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  if (clip) {
    canvas.clipRect(
      const ui.Rect.fromLTWH(0, fittedTop, layoutWidth, svgHeight * fit),
      doAntiAlias: false,
    );
  }
  canvas
    ..translate(0, fittedTop)
    ..scale(fit)
    ..drawPicture(artwork);
  return recorder.endRecording();
}

/// 录制 C1、H、历史 B 分组或含 2/5/23 条轮廓的前缀。
ui.Picture recordStrokes(
  String group,
  double deviceWidth, {
  required bool clip,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  if (clip) {
    canvas.clipPath(
      ui.Path()
        ..fillType = ui.PathFillType.evenOdd
        ..moveTo(0, 0)
        ..lineTo(1027.3199462890625, 0)
        ..lineTo(1027.3199462890625, 609.2999877929688)
        ..lineTo(0, 609.2999877929688)
        ..lineTo(0, 0)
        ..close(),
    );
  }
  drawStrokeGroups(canvas, group, deviceWidth);
  final artwork = recorder.endRecording();
  try {
    return recordLayout(artwork, clip: clip);
  } finally {
    artwork.dispose();
  }
}

/// 在 SVG 坐标下绘制指定的描边分组。
void drawStrokeGroups(ui.Canvas canvas, String group, double deviceWidth) {
  final paint = ui.Paint()
    ..color = strokeColor
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = deviceWidth / fit
    ..strokeCap = ui.StrokeCap.square
    ..strokeJoin = ui.StrokeJoin.bevel
    ..strokeMiterLimit = 10;
  final partitions = switch (group) {
    'C1' => [List.filled(5, 1), List.filled(23, 1)],
    'B' => [
      [2, 1, 2],
      [19, 1, 3],
    ],
    'H' => [
      [5],
      [23],
    ],
    'first2' => [
      [2],
      <int>[],
    ],
    'first5' => [
      [5],
      <int>[],
    ],
    'second2' => [
      <int>[],
      [2],
    ],
    'second5' => [
      <int>[],
      [5],
    ],
    'second23' => [
      <int>[],
      [23],
    ],
    _ => throw ArgumentError.value(group),
  };
  for (var g = 0; g < partitions.length; g++) {
    var member = 0;
    for (final count in partitions[g]) {
      final path = ui.Path();
      for (var i = 0; i < count; i++) {
        final (verbs, points) = cacheStrokeMembers[g][member++];
        appendPath(path, verbs, points);
      }
      canvas.drawPath(path, paint);
    }
  }
}

/// 复刻 OffsetLayer 快照的外层 Scene，或用纯 Picture.toImage 作对照。
Future<ui.Image> toImage(ui.Picture picture, Target target, bool scene) async {
  if (!scene) return picture.toImage(target.width, target.height);
  final builder = ui.SceneBuilder()
    ..pushOffset(0, 0)
    ..addPicture(ui.Offset.zero, picture)
    ..pop();
  final snapshot = builder.build();
  try {
    return await snapshot.toImage(target.width, target.height);
  } finally {
    snapshot.dispose();
  }
}

/// 读取预乘 RGBA8；同步句柄仍在光栅线程完成渲染。
Future<Uint8List> rgba(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// 获取图中某个物理像素的四个通道。
List<int> pixel(Uint8List data, int width, int x, int y) {
  final start = (y * width + x) * 4;
  return data.sublist(start, start + 4);
}

/// 统计两张等尺寸图片的变化像素和最大通道差。
({int changed, int maxDelta}) diff(Uint8List a, Uint8List b) {
  var changed = 0;
  var maxDelta = 0;
  for (var i = 0; i < a.length; i += 4) {
    var delta = 0;
    for (var j = i; j < i + 4; j++) {
      delta = math.max(delta, (a[j] - b[j]).abs());
    }
    if (delta > 0) changed++;
    maxDelta = math.max(maxDelta, delta);
  }
  return (changed: changed, maxDelta: maxDelta);
}

/// 使用组件坐标与贴图原点记录缓存纹理的绘制。
ui.Picture recordCachePicture(
  ui.Picture vector,
  Target target, {
  required ui.Offset paste,
  bool unitScale = false,
}) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..translate(target.tx - paste.dx, target.ty - paste.dy)
    ..scale(unitScale ? 1.0 : target.sx, unitScale ? 1.0 : target.sy)
    ..drawPicture(vector);
  return recorder.endRecording();
}

/// 渲染全尺寸矢量、缓存纹理及贴回结果，并分别探测三个像素。
Future<Map<String, Object?>> capturePair(
  ui.Picture vector,
  Target target, {
  double dx = 0,
  double dy = 0,
  int? textureHeight,
  bool sync = true,
  bool scene = true,
  bool unitScale = false,
  bool linear = false,
  ui.TargetPixelFormat targetFormat = ui.TargetPixelFormat.dontCare,
}) async {
  final sx = unitScale ? 1.0 : target.sx;
  final sy = unitScale ? 1.0 : target.sy;
  final width = target.textureWidth;
  final height = textureHeight ?? target.textureHeight;
  final paste = ui.Offset(target.pasteX + dx, target.pasteY + dy);
  final outputPoint = (target.x, target.y);
  final texturePoint = (
    (target.x + 0.5 - paste.dx).floor(),
    (target.y + 0.5 - paste.dy).floor(),
  );

  final directRecorder = ui.PictureRecorder();
  ui.Canvas(directRecorder)
    ..translate(target.tx, target.ty)
    ..scale(sx, sy)
    ..drawPicture(vector);
  final direct = directRecorder.endRecording();
  ui.Image? directImage;
  ui.Image? texture;
  ui.Image? pasted;
  try {
    try {
      directImage = await toImage(direct, target, scene);
    } finally {
      direct.dispose();
    }
    final cachePicture = recordCachePicture(
      vector,
      target,
      paste: paste,
      unitScale: unitScale,
    );
    try {
      texture = sync
          ? cachePicture.toImageSync(width, height, targetFormat: targetFormat)
          : await cachePicture.toImage(width, height);
    } finally {
      cachePicture.dispose();
    }

    final pasteRecorder = ui.PictureRecorder();
    final src = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    ui.Canvas(pasteRecorder).drawImageRect(
      texture,
      src,
      src.shift(paste),
      ui.Paint()
        ..isAntiAlias = false
        ..filterQuality = linear ? ui.FilterQuality.low : ui.FilterQuality.none,
    );
    final pastePicture = pasteRecorder.endRecording();
    try {
      pasted = await toImage(pastePicture, target, scene);
    } finally {
      pastePicture.dispose();
    }
    final a = await rgba(directImage);
    final b = await rgba(pasted);
    final t = await rgba(texture);
    final stats = diff(a, b);
    return {
      'direct': pixel(a, target.width, outputPoint.$1, outputPoint.$2),
      'texel': pixel(t, width, texturePoint.$1, texturePoint.$2),
      'pasted': pixel(b, target.width, outputPoint.$1, outputPoint.$2),
      'texel_xy': [texturePoint.$1, texturePoint.$2],
      'changed': stats.changed,
      'max_delta': stats.maxDelta,
    };
  } finally {
    directImage?.dispose();
    pasted?.dispose();
    texture?.dispose();
  }
}

/// 扫描目标原点、高度、裁剪、变换、线宽与轮廓组合。
Future<Map<String, Object?>> runCacheProbe({required bool phone}) async {
  final target = targetFor(phone);
  final out = <String, Object?>{};
  for (final group in ['C1', 'B', 'H']) {
    final vector = recordStrokes(group, strokeWidth * fit, clip: true);
    try {
      out['$group/base'] = await capturePair(vector, target);
      if (phone) continue;
      out['$group/async'] = await capturePair(vector, target, sync: false);
      out['$group/picture'] = await capturePair(vector, target, scene: false);
      for (final dy in [-24.0, -1.0, -0.5, -0.25, 0.25, 0.49, 1.0, 16.0]) {
        out['$group/dy=$dy'] = await capturePair(vector, target, dy: dy);
      }
      for (final dx in [-0.49, -0.25, 0.25, 0.49]) {
        out['$group/dx=$dx'] = await capturePair(vector, target, dx: dx);
      }
      for (final h in [160, 185, 220, 450]) {
        out['$group/h=$h'] = await capturePair(
          vector,
          target,
          textureHeight: h,
        );
      }
      out['$group/scale=1'] = await capturePair(
        vector,
        target,
        unitScale: true,
      );
    } finally {
      vector.dispose();
    }
    if (phone) continue;
    final noClip = recordStrokes(group, strokeWidth * fit, clip: false);
    try {
      out['$group/no_clip'] = await capturePair(noClip, target);
    } finally {
      noClip.dispose();
    }
    for (final width in [0.2, 0.30, 0.32, 0.34, 0.45, 0.99, 1.0, 1.1]) {
      final otherWidth = recordStrokes(group, width, clip: true);
      try {
        out['$group/width=$width'] = await capturePair(otherWidth, target);
      } finally {
        otherWidth.dispose();
      }
    }
  }
  if (!phone) {
    for (final group in [
      'first2',
      'first5',
      'second2',
      'second5',
      'second23',
    ]) {
      final vector = recordStrokes(group, strokeWidth * fit, clip: true);
      try {
        out['$group/base'] = await capturePair(vector, target);
      } finally {
        vector.dispose();
      }
    }
  }
  return out;
}

/// 启动最小 Flutter 宿主，离屏用例不依赖组件或 XVG。
Future<void> bootProbe() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.expand());
  await WidgetsBinding.instance.endOfFrame;
}

/// 在 Windows 写启动器报告，在 Android 写应用缓存目录。
void writeReport(Map<String, Object?> result) {
  final output = Platform.isAndroid
      ? '${Directory.systemTemp.path}/xvg-cache-repro.json'
      : Platform.environment['XVG_MICRO_OUT'];
  final content = const JsonEncoder.withIndent('  ').convert(result);
  if (output != null) File(output).writeAsStringSync('$content\n');
  stdout.writeln('xvg-cache-repro complete');
}

/// 运行独立复现并写出报告。
Future<void> main() async {
  await bootProbe();
  writeReport(await runCacheProbe(phone: Platform.isAndroid));
  if (Platform.isWindows) exit(0);
}
