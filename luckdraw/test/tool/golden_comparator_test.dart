import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/golden_comparator.dart';

/// 创建灰度 PNG 字节，用于精确控制通道误差。
Future<Uint8List> _png(int channel, {int width = 1}) async {
  final image = await createLuckyTestImage(
      color: ui.Color.fromARGB(255, channel, channel, channel), width: width);
  try {
    return await luckyTestPng(image);
  } finally {
    image.dispose();
  }
}

/// 创建恰好 [differentPixels] 个白色像素的两百像素对照图。
Future<Uint8List> _sparsePng(int differentPixels) async {
  const width = 200;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFF000000), ui.BlendMode.src);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, differentPixels.toDouble(), 1),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, 1);
  try {
    return await luckyTestPng(image);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// 验证像素阈值、平均误差、尺寸及失败产物。
void main() {
  group('LuckyToleranceComparator', () {
    late Directory directory;
    late LuckyToleranceComparator comparator;
    final golden = Uri.parse('fixture.png');
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('luckdraw-golden-');
      comparator =
          LuckyToleranceComparator(directory.uri.resolve('fixture_test.dart'));
      await comparator.update(golden, await _png(0));
    });
    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test('passes within the pixel tolerance and fails beyond it', () async {
      expect(await comparator.compare(await _png(2), golden), isTrue);
      await expectLater(
          comparator.compare(await _png(kLuckyPixelTolerance + 1), golden),
          throwsA(isA<FlutterError>()));
      final boundary = LuckyToleranceComparator(
          directory.uri.resolve('boundary_test.dart'),
          maxMeanError: 255);
      expect(await boundary.compare(await _png(kLuckyPixelTolerance), golden),
          isTrue);
      await expectLater(
          boundary.compare(await _png(kLuckyPixelTolerance + 1), golden),
          throwsA(isA<FlutterError>()));
    });
    test('writes a diff image on failure', () async {
      await expectLater(comparator.compare(await _png(255), golden),
          throwsA(isA<FlutterError>()));
      final files = Directory.fromUri(directory.uri.resolve('failures/'))
          .listSync()
          .whereType<File>()
          .toList();
      expect(files.any((f) => f.path.endsWith('_isolatedDiff.png')), isTrue);
      expect(files.every((f) => f.lengthSync() > 0), isTrue);
    });
    test('enforces mean error independently and rejects dimensions', () async {
      final meanOnly = LuckyToleranceComparator(
          directory.uri.resolve('mean_test.dart'),
          maxDiffRatio: 1);
      await expectLater(meanOnly.compare(await _png(3), golden),
          throwsA(isA<FlutterError>()));
      await expectLater(comparator.compare(await _png(0, width: 2), golden),
          throwsA(isA<FlutterError>()));
    });
    test('includes the exact differing pixel ratio boundary', () async {
      await comparator.update(golden, await _sparsePng(0));
      final ratioOnly = LuckyToleranceComparator(
          directory.uri.resolve('ratio_test.dart'),
          maxMeanError: 255);
      expect(await ratioOnly.compare(await _sparsePng(1), golden), isTrue);
      await expectLater(ratioOnly.compare(await _sparsePng(2), golden),
          throwsA(isA<FlutterError>()));
    });
    test('preserves local comparator base directory', () async {
      final local =
          LocalFileComparator(directory.uri.resolve('nested/test.dart'));
      final fromLocal = LuckyToleranceComparator.fromLocal(local);
      expect(fromLocal.basedir, local.basedir);
      expect(fromLocal.maxDiffRatio, kLuckyMaxDiffRatio);
      expect(fromLocal.maxMeanError, kLuckyMaxMeanError);
    });
  });
}
