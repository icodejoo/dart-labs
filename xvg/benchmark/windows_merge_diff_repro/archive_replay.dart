import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'cache_edge_probe.dart' as edge;
import 'cache_repro.dart' as probe;

/// 从本机 Rust 输出重放全图，可消融、移除裁剪或重复指定的填充轮廓。
Future<ui.Picture> archive(
  String stem, {
  int? omit,
  bool clip = true,
  bool Function(int, List)? includes,
  int? duplicateNonZeroFill,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final folder = Platform.isAndroid
      ? null
      : Platform.environment['XVG_ARCHIVE'];
  if (!Platform.isAndroid && folder == null) {
    throw StateError('Set XVG_ARCHIVE to the local Rust dump directory');
  }
  final lines = Platform.isAndroid
      ? const LineSplitter().convert(
          await rootBundle.loadString('assets/$stem-web-481.jsonl'),
        )
      : File('$folder/$stem-web-481.jsonl').readAsLinesSync();
  final head = jsonDecode(lines.first) as Map;
  final clips =
      (jsonDecode(
            Platform.isAndroid
                ? await rootBundle.loadString('assets/clips-481.json')
                : File('$folder/clips-481.json').readAsStringSync(),
          ) as Map)['clips']
          as List;
  for (final [kind as int, i as int, _] in head['commands'] as List) {
    if (kind == 4) {
      final [verbs as List, pts as List, even as bool] = clips[i] as List;
      final p = ui.Path()
        ..fillType = even ? ui.PathFillType.evenOdd : ui.PathFillType.nonZero;
      probe.appendPath(p, verbs, pts);
      canvas.save();
      if (clip) canvas.clipPath(p);
    } else if (kind == 5) {
      canvas.restore();
    } else {
      if (kind != 0) throw StateError('Unexpected command $kind');
      if (i == omit) continue;
      final row = jsonDecode(lines[i + 1]) as List;
      if (includes != null && !includes(i, row)) continue;
      if (row.skip(8).take(7).any((value) => value != null && value != false)) {
        throw StateError('Unexpected paint $i');
      }
      final p = ui.Path()
        ..fillType = row[3] == true
            ? ui.PathFillType.evenOdd
            : ui.PathFillType.nonZero;
      probe.appendPath(p, row[0] as List, row[1] as List);
      if (row[2] case final int fill) {
        final fillPath = i == duplicateNonZeroFill ? repeatNonZeroPath(p) : p;
        canvas.drawPath(fillPath, ui.Paint()..color = ui.Color(fill));
      }
      if (row[4] case final int stroke) {
        final flags = row[6] as int;
        canvas.drawPath(
          p,
          ui.Paint()
            ..color = ui.Color(stroke)
            ..strokeWidth = (row[5] as num).toDouble()
            ..style = ui.PaintingStyle.stroke
            ..strokeCap = ui.StrokeCap.values[flags & 3]
            ..strokeJoin = ui.StrokeJoin.values[(flags >> 2) & 3]
            ..strokeMiterLimit = (row[7] as num).toDouble(),
        );
      }
    }
  }
  final art = recorder.endRecording();
  try {
    return probe.recordLayout(art, clip: clip);
  } finally {
    art.dispose();
  }
}

/// 同向追加轮廓，使非零绕数的填充区域和全部边坐标保持一致。
ui.Path repeatNonZeroPath(ui.Path path) {
  if (path.fillType != ui.PathFillType.nonZero) {
    throw ArgumentError('Repeating an even-odd path would erase its fill');
  }
  return ui.Path.from(path)..addPath(path, ui.Offset.zero);
}

/// 保留全图回放及有限路径复现结果。
Future<void> main() async {
  await probe.bootProbe();
  final phone = Platform.isAndroid;
  final target = probe.targetFor(phone);
  final selected = phone ? ['Final', 'C1'] : ['ActualB'];
  final result = <String, Object?>{};
  for (final stem in selected) {
    final vector = await archive(stem);
    try {
      for (var i = 0; i < (phone ? 3 : 10); i++) {
        result['full/$stem/base/$i'] = await probe.capturePair(vector, target);
      }
      result['full/$stem/async'] = await probe.capturePair(
        vector,
        target,
        sync: false,
      );
      result['full/$stem/picture'] = await probe.capturePair(
        vector,
        target,
        scene: false,
      );
      if (phone) {
        result['full/$stem/aligned'] = await probe.capturePair(
          vector,
          target,
          dx: -target.pasteX,
          dy: target.pasteY.floor() - target.pasteY,
        );
        result['full/$stem/linear'] = await probe.capturePair(
          vector,
          target,
          linear: true,
        );
        result['full/$stem/aligned_at_world'] = await probe.capturePair(
          vector,
          (
            width: target.width,
            height: target.height,
            textureWidth: target.textureWidth,
            textureHeight: target.textureHeight,
            x: target.x,
            y: target.y,
            sx: target.sx,
            sy: target.sy,
            tx: 0,
            ty: target.ty + 0.5625,
            pasteX: 0,
            pasteY: 375,
          ),
        );
      }
      if (!phone) {
        result['full/$stem/h450'] = await probe.capturePair(
          vector,
          target,
          textureHeight: 450,
        );
        result['full/$stem/dy-1'] = await probe.capturePair(
          vector,
          target,
          dy: -1,
        );
      }
    } finally {
      vector.dispose();
    }
  }
  if (!phone) {
    for (final (name, omit, clip) in [
      ('omit_black', 5944, true),
      ('omit_outer_white', 5942, true),
      ('omit_inner_white', 5945, true),
      ('omit_black_outline', 5943, true),
      ('no_clip', null, false),
    ]) {
      final vector = await archive('ActualB', omit: omit, clip: clip);
      try {
        for (var i = 0; i < 6; i++) {
          result['full/ActualB/$name/$i'] = await probe.capturePair(
            vector,
            target,
          );
        }
      } finally {
        vector.dispose();
      }
    }
  } else {
    result.addAll(await probe.runCacheProbe(phone: true));
  }
  result.addAll(await edge.runEdgeProbe(phone: phone));
  probe.writeReport(result);
  if (!phone) exit(0);
}
