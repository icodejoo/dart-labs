import 'dart:io';
import 'dart:ui' as ui;

import 'cache_paths.dart';
import 'cache_repro.dart';

/// 黑色填充叠在白色外层上，白色内层覆盖黑色填充的内部。
const edgeColors = [
  ui.Color(0xffffffff),
  ui.Color(0xff000000),
  ui.Color(0xffffffff),
];

/// 黑色填充外的极细黑边在 Rust 输出中的线宽。
const outlineWidth = 0.056575000286102295;

/// 绘制目标附近三层填充，可换成无原图坐标的合成圆角轮廓。
ui.Picture recordEdges({
  bool clip = true,
  bool synthetic = false,
  int? omit,
  bool outline = true,
  bool addStrokes = false,
  bool splitContours = false,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, svgWidth, svgHeight),
    ui.Paint()..color = const ui.Color(0xfff7f7ed),
  );
  if (addStrokes) {
    drawStrokeGroups(canvas, splitContours ? 'C1' : 'B', strokeWidth * fit);
  }
  const insets = [0.0, 0.5657, 1.4142];
  for (var i = 0; i < cacheEdgeContours.length; i++) {
    if (i == omit) continue;
    final path = ui.Path();
    if (synthetic) {
      final inset = insets[i];
      // A cubic path keeps the same general path route as the extracted edge.
      final rect = const ui.Rect.fromLTRB(
        528.05,
        411.58,
        562,
        445.525,
      ).deflate(inset);
      final x = rect.left;
      final y = rect.bottom;
      final r = 2.82 - inset;
      const tangent = 0.5522847498;
      path
        ..moveTo(x, rect.top)
        ..lineTo(rect.right, rect.top)
        ..lineTo(rect.right, y)
        ..lineTo(x + r, y)
        ..cubicTo(x + r * (1 - tangent), y, x, y - r * (1 - tangent), x, y - r)
        ..close();
    } else {
      final (verbs, points) = cacheEdgeContours[i];
      appendPath(path, verbs, points);
    }
    canvas.drawPath(path, ui.Paint()..color = edgeColors[i]);
    if (i == 0 && outline) {
      canvas.drawPath(
        path,
        ui.Paint()
          ..color = edgeColors[1]
          ..style = ui.PaintingStyle.stroke
          ..strokeCap = ui.StrokeCap.round
          ..strokeJoin = ui.StrokeJoin.round
          ..strokeMiterLimit = 3.86368989944458
          ..strokeWidth = outlineWidth,
      );
    }
  }
  final art = recorder.endRecording();
  try {
    return recordLayout(art, clip: clip);
  } finally {
    art.dispose();
  }
}

/// 用同一份 Dart 用例对比填充边、合成素材及 Vulkan 像素相位。
Future<Map<String, Object?>> runEdgeProbe({required bool phone}) async {
  final target = targetFor(phone);
  final rows = <String, Object?>{};
  for (final (name, vector) in [
    ('edge', recordEdges()),
    ('synthetic', recordEdges(synthetic: true)),
    ('no_clip', recordEdges(clip: false)),
    ('no_outer_white', recordEdges(omit: 0)),
    ('no_black', recordEdges(omit: 1)),
    ('no_inner_white', recordEdges(omit: 2)),
    ('no_outline', recordEdges(outline: false)),
    ('with_B', recordEdges(addStrokes: true)),
    ('with_C1', recordEdges(addStrokes: true, splitContours: true)),
  ]) {
    try {
      for (var i = 0; i < (phone ? 2 : 12); i++) {
        rows['$name/base/$i'] = await capturePair(vector, target);
      }
      if (phone) {
        rows['$name/aligned_phase'] = await capturePair(
          vector,
          target,
          dx: -target.pasteX,
          dy: target.pasteY.floor() - target.pasteY,
        );
      } else if (name == 'edge' || name == 'synthetic') {
        for (final dy in [-24.0, -1.0, -0.5, -0.25, 0.25, 0.49, 1.0, 16.0]) {
          rows['$name/dy=$dy'] = await capturePair(vector, target, dy: dy);
        }
        for (final h in [160, 183, 185, 220, 450]) {
          rows['$name/h=$h'] = await capturePair(
            vector,
            target,
            textureHeight: h,
          );
        }
        rows['$name/scale=1'] = await capturePair(
          vector,
          target,
          unitScale: true,
        );
      }
    } finally {
      vector.dispose();
    }
  }
  return rows;
}

/// 运行边缘覆盖对照并写出预乘 RGBA 统计。
Future<void> main() async {
  await bootProbe();
  writeReport(await runEdgeProbe(phone: Platform.isAndroid));
  if (Platform.isWindows) exit(0);
}
