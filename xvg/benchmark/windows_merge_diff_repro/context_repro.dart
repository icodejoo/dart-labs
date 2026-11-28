import 'dart:io';

import 'archive_replay.dart';
import 'cache_repro.dart';

/// 保留所有原始 clip，裁减不同类别的绘制操作。
Future<void> main() async {
  await bootProbe();
  final result = <String, Object?>{};
  final target = targetFor(false);
  const tail = 5940;
  const gray = 0xff9c9c9c;
  final cases = <String, bool Function(int, List)>{
    'no-gray': (i, row) => row[4] != gray || row[2] != null,
    'no-stroke-except-outline': (i, row) =>
        row[4] == null || row[2] != null || i == 5943,
    'last59': (i, _) => i >= tail - 45,
  };
  for (final keep in [40, 128, 512, 2048, 4096, 5300]) {
    cases['prefix=$keep'] = (i, _) => i < keep || i >= tail;
  }
  for (final item in cases.entries) {
    final picture = await archive('ActualB', includes: item.value);
    try {
      for (var i = 0; i < 8; i++) {
        result['${item.key}/$i'] = await capturePair(picture, target);
      }
    } finally {
      picture.dispose();
    }
  }
  writeReport(result);
  exit(0);
}
