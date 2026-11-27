import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// 逐条或合并绘制同一组轮廓，返回两份预乘 RGBA 的最大差与变化像素数。
Future<({int maxDelta, int changedPixels})> compare(
  List<void Function(ui.Path)> contours,
  ui.Paint paint, {
  required int width,
  required int height,
  bool whiteBackground = false,
}) async {
  Future<List<int>> capture(bool merged) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..clipRect(
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        doAntiAlias: false,
      );
    if (whiteBackground) {
      canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
    }
    final compound = ui.Path();
    for (final contour in contours) {
      final path = merged ? compound : ui.Path();
      contour(path);
      if (!merged) canvas.drawPath(path, paint);
    }
    if (merged) canvas.drawPath(compound, paint);

    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        final rgba = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        return rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  final separate = await capture(false);
  final merged = await capture(true);
  var maxDelta = 0;
  var changedPixels = 0;
  for (var pixel = 0; pixel < separate.length; pixel += 4) {
    var changed = false;
    for (var channel = pixel; channel < pixel + 4; channel++) {
      final delta = (separate[channel] - merged[channel]).abs();
      if (delta > maxDelta) maxDelta = delta;
      changed |= delta > 0;
    }
    if (changed) changedPixels++;
  }
  return (maxDelta: maxDelta, changedPixels: changedPixels);
}

/// 生成两条同向的闭合矩形轮廓，可选用共线曲线绕开矩形识别。
void Function(ui.Path) rect(double left, {bool curve = false}) => (path) {
  const top = 4.0;
  const bottom = 4.7;
  final right = left + 18;
  path.moveTo(left, top);
  if (curve) {
    path.quadraticBezierTo((left + right) / 2, top, right, top);
  } else {
    path.lineTo(right, top);
  }
  path
    ..lineTo(right, bottom)
    ..lineTo(left, bottom)
    ..close();
};

/// Draws a polygon from coordinates in device pixels. / 按设备像素坐标绘制多边形。
void Function(ui.Path) polygon(List<ui.Offset> points, ui.Offset offset) =>
    (path) {
      final first = points.first + offset;
      path.moveTo(first.dx, first.dy);
      for (final point in points.skip(1)) {
        final shifted = point + offset;
        path.lineTo(shifted.dx, shifted.dy);
      }
      path.close();
    };

/// Compares separated primitives and nonconvex fills under analytic antialiasing. / 对比解析式抗锯齿下相离的图元和非凸填充。
Future<Map<String, ({int maxDelta, int changedPixels})>>
scanConversionCases() async {
  const noOffset = ui.Offset.zero;
  const separateRows = ui.Offset(0, 54);
  const sameRows = ui.Offset(70, 1.32);
  const triangle = [
    ui.Offset(4.53, 4.07),
    ui.Offset(18.71, 5.18),
    ui.Offset(9.04, 16.55),
  ];
  const concave = [
    ui.Offset(4.23, 4.37),
    ui.Offset(44.71, 7.37),
    ui.Offset(43.71, 9.41),
    ui.Offset(12.02, 9.41),
    ui.Offset(23.02, 21.81),
    ui.Offset(4.23, 20.81),
  ];
  final fill = ui.Paint()..color = const ui.Color(0xff000000);
  final pairs = {
    'convexSeparateRows': [
      polygon(triangle, noOffset),
      polygon(triangle, separateRows),
    ],
    'concaveSameRows': [polygon(concave, noOffset), polygon(concave, sameRows)],
    'concaveSeparateRows': [
      polygon(concave, noOffset),
      polygon(concave, sameRows + separateRows),
    ],
  };
  return {
    for (final entry in pairs.entries)
      entry.key: await compare(entry.value, fill, width: 180, height: 120),
  };
}

/// 在空窗口启动后执行纯 dart:ui 绘制，并将像素统计写给安静启动器。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.expand());
  await WidgetsBinding.instance.endOfFrame;

  final fill = ui.Paint()..color = const ui.Color(0xff2a2a2a);
  final rectangles = await compare(
    [rect(4), rect(28)],
    fill,
    width: 50,
    height: 16,
    whiteBackground: true,
  );
  final collinearCurves = await compare(
    [rect(4, curve: true), rect(28, curve: true)],
    fill,
    width: 50,
    height: 16,
    whiteBackground: true,
  );
  final clipEdgeStroke = await compare(
    [
      (path) => path
        ..moveTo(-0.33, 3)
        ..lineTo(-0.31, 4)
        ..lineTo(-0.33, 5),
      (path) => path
        ..moveTo(3, 9)
        ..lineTo(4, 10)
        ..lineTo(3, 11),
    ],
    ui.Paint()
      ..color = const ui.Color(0xff9c9c9c)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 0.32
      ..strokeCap = ui.StrokeCap.square
      ..strokeJoin = ui.StrokeJoin.bevel,
    width: 28,
    height: 16,
  );
  final result = jsonEncode({
    for (final (name, pixels) in [
      ('rectangles', rectangles),
      ('collinearCurves', collinearCurves),
      ('clipEdgeStroke', clipEdgeStroke),
    ])
      name: {
        'max_delta': pixels.maxDelta,
        'changed_pixels': pixels.changedPixels,
      },
  });
  final output = Platform.environment['XVG_MICRO_OUT'];
  if (output == null) {
    stdout.writeln(result);
  } else {
    File(output).writeAsStringSync('$result\n');
  }
  exit(0);
}
