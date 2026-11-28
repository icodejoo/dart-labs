import 'dart:io';
import 'dart:ui' as ui;

import 'archive_replay.dart';
import 'cache_edge_probe.dart';
import 'cache_repro.dart';

/// 使用显式 RGBA32F 目标做同后端的单样本对照。
Future<void> main() async {
  await bootProbe();
  final target = targetFor(false);
  final results = <String, Object?>{};
  final artwork = <String, ui.Picture>{
    'B': await archive('ActualB'),
    'C1': await archive('C1'),
    'edge': recordEdges(),
    'synthetic': recordEdges(synthetic: true),
  };
  for (final item in artwork.entries) {
    try {
      for (var i = 0; i < 6; i++) {
        results['${item.key}/float/$i'] = await capturePair(
          item.value,
          target,
          targetFormat: ui.TargetPixelFormat.rgbaFloat32,
        );
      }
    } catch (error) {
      results['${item.key}/error'] = error.runtimeType.toString();
    } finally {
      item.value.dispose();
    }
  }
  writeReport(results);
  exit(0);
}
