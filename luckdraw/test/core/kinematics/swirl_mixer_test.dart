import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/src/core/kinematics/swirl_mixer.dart';

/// 验证装填与确定性搅拌契约。
void main() {
  group('LuckySwirlMixer', () {
    test('F2 feasible circle packing avoids overlap before compression', () {
      final cases = [
        (2, 10.0, 5.0),
        (3, 11.0, 5.0),
        (4, 13.0, 5.0),
        (7, 15.0, 5.0),
        (10, 50.0, 5.0)
      ];
      for (final (count, radius, body) in cases) {
        final points = packCirclesInCircle(
            count: count, containerRadius: radius, bodyRadius: body);
        expect(points, hasLength(count));
        expect(points.every((p) => p.distance + body <= radius + 1e-8), isTrue);
        for (var a = 0; a < count; a++) {
          for (var b = a + 1; b < count; b++) {
            expect((points[a] - points[b]).distance,
                greaterThanOrEqualTo(body * 2 - 1e-8),
                reason: '$count circles');
          }
        }
      }
    });
    test('rest packing is deterministic and keeps bodies inside the container',
        () {
      final rest =
          packCirclesInCircle(count: 100, containerRadius: 50, bodyRadius: 10);
      expect(rest,
          packCirclesInCircle(count: 100, containerRadius: 50, bodyRadius: 10));
      expect(rest.length, 100);
      final loose =
          packCirclesInCircle(count: 10, containerRadius: 50, bodyRadius: 5);
      for (var a = 0; a < loose.length; a++) {
        for (var b = a + 1; b < loose.length; b++) {
          expect(
              (loose[a] - loose[b]).distance, greaterThanOrEqualTo(9.999999));
        }
      }
      expect(rest.every((p) => p.distance <= 40.000001), isTrue);
      expect(packCirclesInCircle(count: 0, containerRadius: 1, bodyRadius: 1),
          isEmpty);
      expect(packCirclesInCircle(count: 2, containerRadius: 1, bodyRadius: 2),
          [Offset.zero, Offset.zero]);
    });
    test('zero mix leaves bodies at rest positions', () {
      final rest =
          packCirclesInCircle(count: 10, containerRadius: 50, bodyRadius: 5);
      final mixer =
          LuckySwirlMixer(rest: rest, containerRadius: 50, bodyRadius: 5)
            ..update(9876, 0);
      for (var i = 0; i < rest.length; i++) {
        expect(mixer.x[i], closeTo(rest[i].dx, 1e-12));
        expect(mixer.y[i], closeTo(rest[i].dy, 1e-12));
        expect(mixer.angle[i], 0);
      }
    });
    test('positions stay inside the container for any swirl angle and mix', () {
      final mixer = LuckySwirlMixer(
          rest: const [Offset(0, 45), Offset(0, -45)],
          containerRadius: 50,
          bodyRadius: 5);
      for (var deg = -720; deg <= 720; deg += 7) {
        for (final mix in const <double>[-1.0, 0.0, 0.3, 0.8, 1.0, 2.0]) {
          mixer.update(deg.toDouble(), mix);
          for (var i = 0; i < mixer.x.length; i++) {
            expect(math.sqrt(mixer.x[i] * mixer.x[i] + mixer.y[i] * mixer.y[i]),
                lessThanOrEqualTo(45.000001));
          }
        }
      }
      final tight = LuckySwirlMixer(
          rest: const [Offset(0, 10)], containerRadius: 100, bodyRadius: 90);
      var touchedBoundary = false;
      for (var deg = 0; deg < 360; deg++) {
        tight.update(deg.toDouble(), 1);
        final distance = Offset(tight.x[0], tight.y[0]).distance;
        expect(distance, lessThanOrEqualTo(10.000001));
        if (distance > 9.999999) touchedBoundary = true;
      }
      expect(touchedBoundary, isTrue);
    });
    test('writes positions into caller-provided Float64List buffers', () {
      final mixer = LuckySwirlMixer(
          rest: const [Offset.zero], containerRadius: 10, bodyRadius: 1);
      final x = mixer.x, y = mixer.y, angle = mixer.angle;
      mixer.update(100, 1);
      expect(
          identical(x, mixer.x) &&
              identical(y, mixer.y) &&
              identical(angle, mixer.angle),
          isTrue);
      final saved = (x[0], y[0], angle[0]);
      mixer.update(200, 1, excluded: [true]);
      expect((x[0], y[0], angle[0]), saved);
      mixer.update(100, 1, excluded: [false]);
      expect((x[0], y[0], angle[0]), saved);
    });
  });
}
