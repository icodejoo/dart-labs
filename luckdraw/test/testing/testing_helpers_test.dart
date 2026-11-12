import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/testing.dart';

/// 可记录数值的假帧。
final class _Frame extends LuckyFrame {
  /// 当前采样值。
  double value = 0;
}

/// 验证手动时钟、确定性随机源与帧记录器。
void main() {
  group('testing helpers', () {
    test('ManualLuckyClock ticks only while started', () {
      final clock = ManualLuckyClock();
      final ticks = <Duration>[];
      clock.tick(const Duration(milliseconds: 5));
      expect(clock.isTicking, isFalse);
      clock.start(ticks.add);
      clock.advance(const Duration(milliseconds: 10));
      expect(ticks, [const Duration(milliseconds: 15)]);
      clock.advanceFrames(2);
      expect(ticks.last, const Duration(milliseconds: 47));
      final replaced = <Duration>[];
      clock.start(replaced.add);
      clock.advanceFrames(1, step: const Duration(milliseconds: 3));
      expect(replaced.single, const Duration(milliseconds: 50));
      clock.stop();
      clock.advanceFrames(2);
      expect(ticks, hasLength(3));
      clock.dispose();
      expect(clock.isTicking, isFalse);
    });
    test('SequenceRandom replays values and throws when exhausted', () {
      final values = <double>[0.2, 0.7, 0.1, 0.9];
      final random = SequenceRandom(values);
      values[0] = 0.8;
      expect(random.nextDouble(), 0.2);
      expect(random.nextInt(10), 7);
      expect(random.nextBool(), isTrue);
      expect(random.nextBool(), isFalse);
      expect(random.nextDouble, throwsStateError);
      expect(() => random.nextInt(0), throwsArgumentError);
      expect(() => SequenceRandom([-0.1]), throwsArgumentError);
      expect(() => SequenceRandom([1]), throwsArgumentError);
      expect(() => SequenceRandom([double.nan]), throwsArgumentError);
    });
    test('LuckyFrameRecorder records one entry per tick', () {
      final frames = LuckyFrameNotifier();
      final frame = _Frame();
      final recorder =
          LuckyFrameRecorder(frames, frame, (value) => value.value);
      frame.value = 1;
      frames.notify();
      frame.value = 2;
      frames.notify();
      expect(recorder.values, [1, 2]);
      expect(() => recorder.values.add(3), throwsUnsupportedError);
      recorder.dispose();
      frame.value = 3;
      frames.notify();
      expect(recorder.values, [1, 2]);
      frames.dispose();
    });
  });
}
