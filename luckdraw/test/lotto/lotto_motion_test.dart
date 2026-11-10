import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/lotto.dart';
import 'package:luckdraw/src/core/motion/motion.dart';
import 'package:luckdraw/src/lotto/motion/lotto_motion.dart';

import '../support/lotto_fixtures.dart';

/// 将状态机推进到开奖序列起点。
LottoMotion drawingMotion({bool sorted = false}) {
  final config =
      lottoConfig.copyWith(options: lottoOptions.copyWith(sortResults: sorted));
  final motion = LottoMotion()..configure(config, lottoLayout(config));
  expect(motion.start(), isTrue);
  expect(motion.stopWith(lottoDraw), isTrue);
  motion.tick(40, 40);
  expect(motion.phase, LuckyPhase.cruising);
  motion.tick(50, 10);
  expect(motion.phase, LuckyPhase.decelerating);
  return motion;
}

/// 验证开奖序列、几何落点与缓冲复用。
void main() {
  group('LottoMotion', () {
    test('balls are drawn one by one at drawInterval in pool order', () {
      final motion = drawingMotion();
      final passed = <List<int>>[];
      final times = <int>[];
      for (var ms = 0; ms <= 500; ms += 10) {
        final events = motion.tick(ms.toDouble(), ms == 0 ? 0 : 10);
        if (events & LuckyMotionEvents.itemPassed != 0) {
          passed.add([motion.passedReel, motion.passedIndex]);
          times.add(ms);
        }
      }
      expect(passed, [
        [0, 7],
        [0, 1],
        [0, 4],
        [1, 14],
        [1, 11]
      ]);
      expect(times, [80, 140, 200, 260, 320]);
    });
    test('each drawn ball lands in its result slot', () {
      final motion = drawingMotion();
      final layout = lottoLayout();
      for (var ms = 10; ms <= 360; ms += 10) {
        motion.tick(ms.toDouble(), 10);
      }
      expect(motion.frame.drawnCount, 5);
      for (var p = 0; p < lottoDraw.numbers.length; p++) {
        final drum = layout.drums[p];
        for (var i = 0; i < lottoDraw.numbers[p].length; i++) {
          final b = lottoDraw.numbers[p][i] - drum.min;
          expect(motion.frame.x[p][b] + drum.center.dx, drum.slots[i].dx);
          expect(motion.frame.y[p][b] + drum.center.dy, drum.slots[i].dy);
          expect(motion.frame.slotOf[p][b], i);
        }
      }
      expect(motion.frame.flight, everyElement(1));
    });
    test('sortResults orders each pool after the last ball lands', () {
      final motion = drawingMotion(sorted: true);
      motion.tick(200, 200);
      final layout = lottoLayout();
      final drum = layout.drums.first;
      expect(motion.frame.slotOf[0][6], 0);
      motion.tick(350, 150);
      final x = motion.frame.x[0][6] + drum.center.dx;
      expect(x, closeTo((drum.slots[0].dx + drum.slots[2].dx) / 2, 1e-8));
      for (var i = 0; i < 10; i++) {
        motion.tick(1000, 100);
      }
      expect(motion.phase, LuckyPhase.settled);
      for (var p = 0; p < lottoDraw.numbers.length; p++) {
        final sorted = [...lottoDraw.numbers[p]]..sort();
        for (var j = 0; j < sorted.length; j++) {
          final b = sorted[j] - layout.drums[p].min;
          expect(motion.frame.slotOf[p][b], j);
          expect(motion.frame.x[p][b] + layout.drums[p].center.dx,
              layout.drums[p].slots[j].dx);
        }
      }
      expect(motion.takeResult()!.draw, lottoDraw);
      expect(motion.takeResult(), isNull);
    });
    test('settles after the last ball and the drum stops mixing', () {
      final motion = drawingMotion();
      motion.tick(100, 100);
      expect(motion.frame.mix, lottoOptions.drawMix);
      expect(motion.phase, LuckyPhase.decelerating);
      for (var i = 0; i < 40; i++) {
        motion.tick(i * 10, 10);
      }
      expect(motion.phase, LuckyPhase.settled);
      expect(motion.frame.mix, 0);
      expect(motion.tick(1000, 100), LuckyMotionEvents.none);
      expect(motion.takeResult()!.cancelled, isFalse);
    });
    test('positions are written into reused buffers without allocation', () {
      final a = drawingMotion();
      final b = drawingMotion();
      final frame = a.frame;
      final xs = a.frame.x;
      final flight = a.frame.flight;
      final slots = a.frame.slotOf;
      final buffers = [...a.frame.x, ...a.frame.y, ...a.frame.angle];
      for (var ms = 1; ms < 80; ms++) {
        a.tick(ms.toDouble(), 1);
        b.tick(ms.toDouble(), 1);
        expect(identical(a.frame, frame), isTrue);
        expect(identical(a.frame.x, xs), isTrue);
        expect(identical(a.frame.flight, flight), isTrue);
        expect(identical(a.frame.slotOf, slots), isTrue);
        final current = [...a.frame.x, ...a.frame.y, ...a.frame.angle];
        for (var i = 0; i < buffers.length; i++) {
          expect(identical(buffers[i], current[i]), isTrue);
        }
        expect(a.frame.x, b.frame.x);
      }
      final layout = lottoLayout();
      for (var p = 0; p < layout.drums.length; p++) {
        for (var j = 0; j < frame.x[p].length; j++) {
          if (frame.slotOf[p][j] >= 0) continue;
          final dx = frame.x[p][j];
          final dy = frame.y[p][j];
          final limit = layout.drums[p].radius - layout.drums[p].ballRadius;
          expect(dx * dx + dy * dy, lessThanOrEqualTo(limit * limit + 1e-8));
        }
      }
    });
    test('a 10 minute frame gap keeps positions finite and still settles', () {
      final motion = drawingMotion(sorted: true);
      final passed = <int>[];
      for (var i = 0; i < 5; i++) {
        final events = motion.tick(600000, i == 0 ? 600000 : 0);
        if (events & LuckyMotionEvents.itemPassed != 0) {
          passed.add(motion.passedIndex);
        }
      }
      expect(passed, [7, 1, 4, 14, 11]);
      expect(motion.phase, LuckyPhase.settled);
      for (final buffer in <Iterable<double>>[
        ...motion.frame.x,
        ...motion.frame.y,
        ...motion.frame.angle
      ]) {
        expect(buffer.every((n) => n.isFinite), isTrue);
      }
      expect(motion.takeResult()!.draw, lottoDraw);
    });
  });
}
