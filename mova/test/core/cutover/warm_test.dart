import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/cutover/warm.dart';

MovaWarmSignal _sig({
  Duration position = Duration.zero,
  Duration buffer = Duration.zero,
  Duration target = Duration.zero,
  bool buffering = false,
  Duration elapsed = Duration.zero,
  bool live = false,
}) =>
    MovaWarmSignal(
      position: position,
      buffer: buffer,
      target: target,
      buffering: buffering,
      elapsed: elapsed,
      live: live,
    );

void main() {
  group('MovaBufferWarm', () {
    test('a single satisfying tick still returns waiting (stableTicks defaults to 2)', () {
      final p = MovaBufferWarm();
      final v = p.onSignal(_sig(
        position: const Duration(seconds: 5),
        buffer: const Duration(seconds: 6),
        target: const Duration(seconds: 5),
      ));
      expect(v, MovaWarmVerdict.waiting);
    });

    test('two consecutive satisfying ticks return ready', () {
      final p = MovaBufferWarm();
      final sig = _sig(
        position: const Duration(seconds: 5),
        buffer: const Duration(seconds: 6),
        target: const Duration(seconds: 5),
      );
      expect(p.onSignal(sig), MovaWarmVerdict.waiting);
      expect(p.onSignal(sig), MovaWarmVerdict.ready);
    });

    test('a buffering tick in the middle resets the consecutive count', () {
      final p = MovaBufferWarm();
      final sig = _sig(
        position: const Duration(seconds: 5),
        buffer: const Duration(seconds: 6),
        target: const Duration(seconds: 5),
      );
      expect(p.onSignal(sig), MovaWarmVerdict.waiting);
      expect(p.onSignal(sig.let(buffering: true)), MovaWarmVerdict.waiting);
      expect(p.onSignal(sig), MovaWarmVerdict.waiting);
      expect(p.onSignal(sig), MovaWarmVerdict.ready);
    });

    test('position not yet within tolerance of target is always waiting', () {
      final p = MovaBufferWarm();
      final sig = _sig(
        position: const Duration(seconds: 1),
        buffer: const Duration(seconds: 6),
        target: const Duration(seconds: 5),
      );
      expect(p.onSignal(sig), MovaWarmVerdict.waiting);
      expect(p.onSignal(sig), MovaWarmVerdict.waiting);
    });

    test('position exactly at the tolerance boundary counts as arrived (inclusive)', () {
      final p = MovaBufferWarm(tolerance: const Duration(milliseconds: 800));
      final sig = _sig(
        position: const Duration(milliseconds: 4200), // target - tolerance exactly
        buffer: const Duration(seconds: 6),
        target: const Duration(seconds: 5),
      );
      expect(p.onSignal(sig), MovaWarmVerdict.waiting);
      expect(p.onSignal(sig), MovaWarmVerdict.ready);
    });

    test('insufficient lookahead buffer is always waiting', () {
      final p = MovaBufferWarm(lookahead: const Duration(seconds: 2));
      final sig = _sig(
        position: const Duration(seconds: 5),
        buffer: const Duration(seconds: 5, milliseconds: 500),
        target: const Duration(seconds: 5),
      );
      expect(p.onSignal(sig), MovaWarmVerdict.waiting);
      expect(p.onSignal(sig), MovaWarmVerdict.waiting);
    });

    test('elapsed at or beyond timeout gives up, taking priority over ready', () {
      final p = MovaBufferWarm(timeout: const Duration(seconds: 8));
      final v = p.onSignal(_sig(
        position: const Duration(seconds: 5),
        buffer: const Duration(seconds: 6),
        target: const Duration(seconds: 5),
        elapsed: const Duration(seconds: 8),
      ));
      expect(v, MovaWarmVerdict.giveUp);
    });

    test('once ready, further signals still return ready (idempotent)', () {
      final p = MovaBufferWarm();
      final sig = _sig(
        position: const Duration(seconds: 5),
        buffer: const Duration(seconds: 6),
        target: const Duration(seconds: 5),
      );
      p.onSignal(sig);
      expect(p.onSignal(sig), MovaWarmVerdict.ready);
      expect(p.onSignal(sig.let(buffering: true)), MovaWarmVerdict.ready);
    });

    test('reset() zeroes the consecutive count so the instance can be reused', () {
      final p = MovaBufferWarm();
      final sig = _sig(
        position: const Duration(seconds: 5),
        buffer: const Duration(seconds: 6),
        target: const Duration(seconds: 5),
      );
      p.onSignal(sig);
      p.reset();
      expect(p.stable, 0);
      expect(p.onSignal(sig), MovaWarmVerdict.waiting);
      expect(p.onSignal(sig), MovaWarmVerdict.ready);
    });

    test('stableTicks: 1 is ready on the first satisfying tick', () {
      final p = MovaBufferWarm(stableTicks: 1);
      final v = p.onSignal(_sig(
        position: const Duration(seconds: 5),
        buffer: const Duration(seconds: 6),
        target: const Duration(seconds: 5),
      ));
      expect(v, MovaWarmVerdict.ready);
    });

    test('zero target (from the start) works the same way', () {
      final p = MovaBufferWarm(stableTicks: 1);
      final v = p.onSignal(_sig(
        position: Duration.zero,
        buffer: const Duration(seconds: 1, milliseconds: 200),
        target: Duration.zero,
      ));
      expect(v, MovaWarmVerdict.ready);
    });

    test('position far past target still counts as arrived', () {
      final p = MovaBufferWarm(stableTicks: 1);
      final v = p.onSignal(_sig(
        position: const Duration(seconds: 50),
        buffer: const Duration(seconds: 51),
        target: const Duration(seconds: 5),
      ));
      expect(v, MovaWarmVerdict.ready);
    });

    test('live: a shadow far behind the on-screen position is still ready (it starts at the live edge)', () {
      final p = MovaBufferWarm();
      // 正片已播 7s，直播影子刚从边缘起播，位置只有 1s：非直播会一直 waiting
      final s = _sig(
        position: const Duration(seconds: 1),
        buffer: const Duration(milliseconds: 2500),
        target: const Duration(seconds: 7),
        live: true,
      );
      expect(p.onSignal(s), MovaWarmVerdict.waiting); // 仍要连续 2 次
      expect(p.onSignal(s), MovaWarmVerdict.ready);
    });

    test('non-live control: the same observation never becomes ready', () {
      final p = MovaBufferWarm();
      final s = _sig(
        position: const Duration(seconds: 1),
        buffer: const Duration(milliseconds: 2500),
        target: const Duration(seconds: 7),
      );
      expect(p.onSignal(s), MovaWarmVerdict.waiting);
      expect(p.onSignal(s), MovaWarmVerdict.waiting);
    });

    test('live: still needs the lookahead buffer', () {
      final p = MovaBufferWarm(stableTicks: 1);
      final v = p.onSignal(_sig(
        position: const Duration(milliseconds: 500),
        buffer: const Duration(milliseconds: 900), // 提前量 400ms < 1s
        target: const Duration(seconds: 7),
        live: true,
      ));
      expect(v, MovaWarmVerdict.waiting);
    });

    test('live: a stalled shadow is not ready', () {
      final p = MovaBufferWarm(stableTicks: 1);
      final v = p.onSignal(_sig(
        position: const Duration(seconds: 1),
        buffer: const Duration(seconds: 3),
        target: const Duration(seconds: 7),
        buffering: true,
        live: true,
      ));
      expect(v, MovaWarmVerdict.waiting);
    });

    test('live: still gives up at the timeout', () {
      final p = MovaBufferWarm();
      final v = p.onSignal(_sig(
        position: const Duration(seconds: 1),
        buffer: const Duration(seconds: 3),
        target: const Duration(seconds: 7),
        elapsed: const Duration(seconds: 8),
        live: true,
      ));
      expect(v, MovaWarmVerdict.giveUp);
    });

    test('live: MovaWarmSignal.live defaults to false', () {
      const s = MovaWarmSignal(
        position: Duration.zero,
        buffer: Duration.zero,
        target: Duration.zero,
        buffering: false,
        elapsed: Duration.zero,
      );
      expect(s.live, isFalse);
    });
  });
}

/// Test-only helper: returns a copy of this signal with [buffering] replaced.
///
/// 测试专用辅助：返回一个替换了 [buffering] 的信号拷贝。
extension _WarmSignalCopy on MovaWarmSignal {
  MovaWarmSignal let({bool? buffering}) => MovaWarmSignal(
        position: position,
        buffer: buffer,
        target: target,
        buffering: buffering ?? this.buffering,
        elapsed: elapsed,
        live: live,
      );
}
