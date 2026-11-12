import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/fonts.dart';
import '../support/recording_canvas.dart';
import '../support/test_images.dart';

/// 验证测试字体、绘制断言及可控图像流的实际行为。
void main() {
  group('test support', () {
    test('loads Roboto and reports missing SDK font paths', () async {
      expect(luckyTestFontsLoaded, isTrue);
      await loadLuckyTestFonts();
      final directory = await Directory.systemTemp.createTemp('luckdraw-font-');
      try {
        expect(
            () => findLuckyTestFont(
                flutterRoot: directory.path,
                executable: Platform.resolvedExecutable),
            throwsA(isA<FileSystemException>()
                .having((e) => e.message, 'message', contains('Roboto'))));
        final legacyFont = File('${directory.path}/$kLuckyLegacyRobotoPath');
        await legacyFont.parent.create(recursive: true);
        await legacyFont.writeAsBytes([2]);
        expect(
            findLuckyTestFont(
                    flutterRoot: directory.path,
                    executable: Platform.resolvedExecutable)
                .readAsBytesSync(),
            [2]);
        expect(
            findLuckyTestFont(
                    executable: '${directory.path}/bin/cache/dart-sdk/bin/dart')
                .readAsBytesSync(),
            [2]);
        await legacyFont.delete();
        final font = File('${directory.path}/$kLuckyRobotoPath');
        await font.parent.create(recursive: true);
        await font.writeAsBytes([1]);
        expect(
            findLuckyTestFont(
                    executable:
                        '${directory.path}/bin/cache/dart-sdk/bin/dart.exe')
                .path,
            font.path);
      } finally {
        await directory.delete(recursive: true);
      }
    });
    test('records balanced saves and picture replay counts', () {
      final canvas = TestRecordingCanvas();
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder);
      final picture = recorder.endRecording();
      try {
        canvas.save();
        canvas.drawPicture(picture);
        canvas.restore();
        canvas.expectBalancedWithoutSaveLayer();
        expect(canvas.countCalls(#drawPicture), 1);
        canvas.save();
        expect(
            canvas.expectBalancedWithoutSaveLayer, throwsA(isA<TestFailure>()));
        final layered = TestRecordingCanvas();
        layered.saveLayer(null, ui.Paint());
        layered.restore();
        expect(layered.expectBalancedWithoutSaveLayer,
            throwsA(isA<TestFailure>()));
      } finally {
        picture.dispose();
      }
    });
    test('supports delayed frames errors and listener removal', () async {
      final completer = LuckyTestImageCompleter();
      final provider = LuckyTestImageProvider(completer);
      expect(
          await provider.obtainKey(ImageConfiguration.empty), same(provider));
      final stream = provider.resolve(ImageConfiguration.empty);
      var frames = 0;
      Object? failure;
      final listener = ImageStreamListener((info, synchronousCall) {
        frames++;
        info.dispose();
      }, onError: (Object error, StackTrace? stack) {
        failure = error;
      });
      stream.addListener(listener);
      expect(frames, 0);
      expect(completer.listenerCount, greaterThanOrEqualTo(1));
      final image =
          await createLuckyTestImage(color: const ui.Color(0xFF123456));
      completer.succeed(image);
      completer.succeed(image);
      expect(frames, 2);
      final error = StateError('fixture failure');
      completer.fail(error);
      expect(failure, same(error));
      stream.removeListener(listener);
      expect(completer.listenerCount, 0);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      image.dispose();
    });
  });
}
