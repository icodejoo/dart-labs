import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/platform_impl/mpv_extractor_impl.dart';

void main() {
  for (final recovers in [true, false]) {
    test('首次 seek 超时后重发一次：恢复=$recovers', () async {
      var seeks = 1;
      var captures = 0;
      final frame = await movaCapturePreviewFrame(
        landed: () => movaWaitForPreviewFrame(
          () async => seeks == 2 && recovers,
          timeout: const Duration(milliseconds: 10),
          pollInterval: const Duration(milliseconds: 2),
        ),
        retrySeek: () async {
          seeks++;
          return true;
        },
        capture: () async {
          captures++;
          return Uint8List.fromList([7]);
        },
      );
      expect(seeks, 2);
      expect(captures, recovers ? 1 : 0);
      expect(frame, recovers ? [7] : isNull);
    });
  }

  test('释放后拒绝重发，且不截图', () async {
    var captures = 0;
    expect(
      await movaCapturePreviewFrame(
        landed: () async => false,
        retrySeek: () async => false,
        capture: () async {
          captures++;
          return Uint8List(1);
        },
      ),
      isNull,
    );
    expect(captures, 0);
  });
}
