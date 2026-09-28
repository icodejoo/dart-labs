import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/ui/video_rect.dart';

void main() {
  group('computeVideoContentRect', () {
    test('contain: video wider than container letterboxes top/bottom', () {
      // Portrait container (400x800), landscape video (1920x1080) — classic
      // "竖屏播放横屏内容" bug scenario this fix targets.
      final rect = computeVideoContentRect(
        container: const Size(400, 800),
        videoSize: const Size(1920, 1080),
        fit: MovaFit.contain,
      );
      // Scaled to fit width: 400 / (1920/1080) = 225 tall, centered.
      expect(rect.left, closeTo(0, 0.001));
      expect(rect.width, closeTo(400, 0.001));
      expect(rect.height, closeTo(225, 0.001));
      expect(rect.top, closeTo((800 - 225) / 2, 0.001));
    });

    test('contain: video taller than container pillarboxes left/right', () {
      final rect = computeVideoContentRect(
        container: const Size(800, 400),
        videoSize: const Size(1080, 1920),
        fit: MovaFit.contain,
      );
      // Scaled to fit height: 400 * (1080/1920) = 225 wide, centered.
      expect(rect.top, closeTo(0, 0.001));
      expect(rect.height, closeTo(400, 0.001));
      expect(rect.width, closeTo(225, 0.001));
      expect(rect.left, closeTo((800 - 225) / 2, 0.001));
    });

    test('cover fills the whole container (may overflow video bounds)', () {
      final rect = computeVideoContentRect(
        container: const Size(400, 800),
        videoSize: const Size(1920, 1080),
        fit: MovaFit.cover,
      );
      expect(rect, Rect.fromLTWH(0, 0, 400, 800));
    });

    test('fill stretches to exactly the container', () {
      final rect = computeVideoContentRect(
        container: const Size(400, 800),
        videoSize: const Size(1920, 1080),
        fit: MovaFit.fill,
      );
      expect(rect, Rect.fromLTWH(0, 0, 400, 800));
    });

    test('matching aspect ratio fills the container exactly under contain', () {
      final rect = computeVideoContentRect(
        container: const Size(400, 225),
        videoSize: const Size(1920, 1080),
        fit: MovaFit.contain,
      );
      expect(rect, Rect.fromLTWH(0, 0, 400, 225));
    });

    test('null videoSize falls back to the whole container', () {
      final rect = computeVideoContentRect(
        container: const Size(400, 800),
        videoSize: null,
        fit: MovaFit.contain,
      );
      expect(rect, Rect.fromLTWH(0, 0, 400, 800));
    });

    test('zero-sized videoSize falls back to the whole container', () {
      final rect = computeVideoContentRect(
        container: const Size(400, 800),
        videoSize: const Size(0, 0),
        fit: MovaFit.contain,
      );
      expect(rect, Rect.fromLTWH(0, 0, 400, 800));
    });

    test('zero-sized container yields an empty rect at the origin', () {
      final rect = computeVideoContentRect(
        container: Size.zero,
        videoSize: const Size(1920, 1080),
        fit: MovaFit.contain,
      );
      expect(rect, Rect.zero);
    });
  });
}
