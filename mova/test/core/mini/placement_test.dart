import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/mini/placement.dart';
import 'package:mova/src/core/options/mini_config.dart';

void main() {
  const bounds = MovaMiniRect(left: 0, top: 0, width: 400, height: 800);
  const insets = MovaMiniInsets();

  group('clampToBounds', () {
    test('fully inside bounds returns the same value', () {
      const r = MovaMiniRect(left: 100, top: 100, width: 100, height: 50);
      final c = clampToBounds(r, bounds: bounds, insets: insets);
      expect(c, r);
    });

    test('left overflow is pushed back to margin/inset', () {
      const r = MovaMiniRect(left: -50, top: 100, width: 100, height: 50);
      final c = clampToBounds(r, bounds: bounds, insets: insets, margin: 10);
      expect(c.left, 10);
    });

    test('top overflow is pushed back to margin/inset', () {
      const r = MovaMiniRect(left: 100, top: -50, width: 100, height: 50);
      final c = clampToBounds(r, bounds: bounds, insets: insets, margin: 10);
      expect(c.top, 10);
    });

    test('right overflow is pushed back so right edge sits at margin/inset', () {
      const r = MovaMiniRect(left: 350, top: 100, width: 100, height: 50);
      final c = clampToBounds(r, bounds: bounds, insets: insets, margin: 10);
      expect(c.right, bounds.right - 10);
    });

    test('bottom overflow is pushed back so bottom edge sits at margin/inset', () {
      const r = MovaMiniRect(left: 100, top: 780, width: 100, height: 50);
      final c = clampToBounds(r, bounds: bounds, insets: insets, margin: 10);
      expect(c.bottom, bounds.bottom - 10);
    });

    test('window larger than the available area falls back to top-left, never negative', () {
      const huge = MovaMiniRect(left: 0, top: 0, width: 1000, height: 1000);
      final c = clampToBounds(huge, bounds: bounds, insets: insets, margin: 0);
      expect(c.left, 0);
      expect(c.top, 0);
      expect(c.width, greaterThanOrEqualTo(0));
      expect(c.height, greaterThanOrEqualTo(0));
    });

    test(
        'insets/margin exceeding the raw bounds never produce a negative width/height '
        '(regression: availableWidth/availableHeight themselves could go negative — '
        'not just the window being larger than them — and that negative value flowed '
        'straight into the returned rect)', () {
      const r = MovaMiniRect(left: 50, top: 50, width: 100, height: 50);
      // Insets alone (600 worth on a 400-wide bounds) already push
      // maxRight below minLeft before the window's own size is even
      // considered.
      //
      // 仅 insets 本身（在 400 宽的 bounds 上共 600）就已经把 maxRight 推到
      // minLeft 之下，这发生在窗口自身尺寸被纳入考虑之前。
      const degenerateInsets = MovaMiniInsets(left: 300, right: 300, top: 500, bottom: 500);
      final c = clampToBounds(r, bounds: bounds, insets: degenerateInsets, margin: 0);
      expect(c.width, greaterThanOrEqualTo(0));
      expect(c.height, greaterThanOrEqualTo(0));
    });
  });

  group('rectForCorner', () {
    test('topLeft', () {
      final r = rectForCorner(MovaMiniCorner.topLeft,
          width: 100, height: 50, bounds: bounds, insets: insets, margin: 10);
      expect(r.left, 10);
      expect(r.top, 10);
    });

    test('topRight', () {
      final r = rectForCorner(MovaMiniCorner.topRight,
          width: 100, height: 50, bounds: bounds, insets: insets, margin: 10);
      expect(r.left, bounds.right - 10 - 100);
      expect(r.top, 10);
    });

    test('bottomLeft', () {
      final r = rectForCorner(MovaMiniCorner.bottomLeft,
          width: 100, height: 50, bounds: bounds, insets: insets, margin: 10);
      expect(r.left, 10);
      expect(r.top, bounds.bottom - 10 - 50);
    });

    test('bottomRight, with inset+margin stacking', () {
      const withInset = MovaMiniInsets(right: 20, bottom: 34);
      final r = rectForCorner(MovaMiniCorner.bottomRight,
          width: 100, height: 50, bounds: bounds, insets: withInset, margin: 10);
      expect(r.left, bounds.right - 20 - 10 - 100);
      expect(r.top, bounds.bottom - 34 - 10 - 50);
    });
  });

  group('MovaCornerSnap.settle', () {
    test('center in left half snaps left', () {
      const snap = MovaCornerSnap(snap: true, margin: 10);
      const r = MovaMiniRect(left: 50, top: 100, width: 100, height: 50);
      final s = snap.settle(r, bounds: bounds, insets: insets);
      expect(s.left, 10);
    });

    test('center in right half snaps right', () {
      const snap = MovaCornerSnap(snap: true, margin: 10);
      const r = MovaMiniRect(left: 250, top: 100, width: 100, height: 50);
      final s = snap.settle(r, bounds: bounds, insets: insets);
      expect(s.right, bounds.right - 10);
    });

    test('snap: false only clamps, does not slide horizontally', () {
      const snap = MovaCornerSnap(snap: false, margin: 10);
      const r = MovaMiniRect(left: 150, top: 100, width: 100, height: 50);
      final s = snap.settle(r, bounds: bounds, insets: insets);
      expect(s.left, 150);
    });

    test('vertical direction is always clamp-only, never snapped', () {
      const snap = MovaCornerSnap(snap: true, margin: 10);
      const r = MovaMiniRect(left: 50, top: 300, width: 100, height: 50);
      final s = snap.settle(r, bounds: bounds, insets: insets);
      expect(s.top, 300);
    });

    test('fast leftward fling wins over center-in-right-half', () {
      const snap = MovaCornerSnap(snap: true, margin: 10);
      const r = MovaMiniRect(left: 250, top: 100, width: 100, height: 50);
      final s = snap.settle(r, bounds: bounds, insets: insets, velocityX: -2000);
      expect(s.left, 10);
    });

    test('fast rightward fling wins over center-in-left-half', () {
      const snap = MovaCornerSnap(snap: true, margin: 10);
      const r = MovaMiniRect(left: 50, top: 100, width: 100, height: 50);
      final s = snap.settle(r, bounds: bounds, insets: insets, velocityX: 2000);
      expect(s.right, bounds.right - 10);
    });

    test('safe-area inset at the bottom keeps the window off the home indicator', () {
      const snap = MovaCornerSnap(snap: true, margin: 10);
      const insetsBottom = MovaMiniInsets(bottom: 34);
      const r = MovaMiniRect(left: 50, top: 700, width: 100, height: 80);
      final s = snap.settle(r, bounds: bounds, insets: insetsBottom);
      expect(s.bottom, bounds.bottom - 34 - 10);
    });
  });

  group('MovaMiniRect value semantics', () {
    test('shift translates both axes', () {
      const r = MovaMiniRect(left: 10, top: 10, width: 50, height: 50);
      final s = r.shift(5, -5);
      expect(s.left, 15);
      expect(s.top, 5);
      expect(s.width, 50);
    });

    test('== and hashCode are value-based', () {
      const a = MovaMiniRect(left: 1, top: 2, width: 3, height: 4);
      const b = MovaMiniRect(left: 1, top: 2, width: 3, height: 4);
      const c = MovaMiniRect(left: 9, top: 2, width: 3, height: 4);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('remapProportionally', () {
    test('preserves relative position across a rotation (bounds swap)', () {
      // Portrait 400x800, window snapped near the bottom-right corner.
      const portrait = MovaMiniRect(left: 0, top: 0, width: 400, height: 800);
      const r = MovaMiniRect(left: 280, top: 730, width: 120, height: 70);
      // Rotate to landscape: bounds swap width/height.
      const landscape = MovaMiniRect(left: 0, top: 0, width: 800, height: 400);
      final remapped = remapProportionally(r, oldBounds: portrait, newBounds: landscape);
      // Still ~"bottom-right": far right, far down — not stuck near the old
      // absolute pixel coordinates, which real-device verification
      // (2026-09-24) found drifting toward an edge across rotations.
      expect(remapped.left, closeTo(800 - 120, 1));
      expect(remapped.top, closeTo(400 - 70, 1));
    });

    test('round-trips back to (approximately) the original rect', () {
      const portrait = MovaMiniRect(left: 0, top: 0, width: 400, height: 800);
      const landscape = MovaMiniRect(left: 0, top: 0, width: 800, height: 400);
      const r = MovaMiniRect(left: 40, top: 600, width: 120, height: 70);
      final toLandscape = remapProportionally(r, oldBounds: portrait, newBounds: landscape);
      final backToPortrait =
          remapProportionally(toLandscape, oldBounds: landscape, newBounds: portrait);
      expect(backToPortrait.left, closeTo(r.left, 0.01));
      expect(backToPortrait.top, closeTo(r.top, 0.01));
    });

    test('degenerate old bounds (zero available space) does not divide by zero', () {
      const oldBounds = MovaMiniRect(left: 0, top: 0, width: 120, height: 70);
      const r = MovaMiniRect(left: 0, top: 0, width: 120, height: 70);
      const newBounds = MovaMiniRect(left: 0, top: 0, width: 400, height: 800);
      final remapped = remapProportionally(r, oldBounds: oldBounds, newBounds: newBounds);
      expect(remapped.left, 0);
      expect(remapped.top, 0);
    });
  });
}
