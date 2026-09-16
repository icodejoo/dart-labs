import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart' as barrel;
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/swap/swap_engine.dart';
import 'package:mova/src/core/swap/trigger.dart';
import 'package:mova/src/core/swap/warm.dart';

import '../support/fake_api.dart';

void main() {
  group('seamless-swap openness contract — every row needs default + knob + injection', () {
    test('whether swapping is enabled at all: off by default, enabled knob', () {
      expect(const MovaSwapConfig().enabled, isFalse);
      expect(const MovaSwapConfig(enabled: true).enabled, isTrue);
    });

    test('when warming starts: 2s lead by default, leadTime knob, trigger injection', () {
      expect(const MovaSwapConfig().leadTime, const Duration(seconds: 2));
      expect(const MovaSwapConfig(leadTime: Duration(seconds: 5)).leadTime, const Duration(seconds: 5));

      final calls = <MovaWarmCue>[];
      final custom = _RecordingTrigger(calls);
      final c = MovaSwapConfig(trigger: custom);
      expect(c.effectiveTrigger, same(custom));
      c.effectiveTrigger.shouldWarm(const MovaWarmCue(remaining: Duration(seconds: 1)));
      expect(calls, hasLength(1));
    });

    test('how short a clip never warms: 5s by default, minWarmDuration knob (policy-owned decision)', () {
      expect(const MovaSwapConfig().minWarmDuration, const Duration(seconds: 5));
      const c = MovaSwapConfig(minWarmDuration: Duration(seconds: 20));
      expect(c.minWarmDuration, const Duration(seconds: 20));
      final t = c.effectiveTrigger;
      expect(
        t.shouldWarm(const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10))),
        isFalse,
        reason: 'a 10s clip is shorter than the 20s minWarmDuration knob',
      );
    });

    test('when warming counts as ready: buffer 1s + 2 stable ticks by default, readyTimeout knob, readyPolicy injection',
        () {
      expect(const MovaSwapConfig().readyTimeout, const Duration(seconds: 8));
      expect(const MovaSwapConfig(readyTimeout: Duration(seconds: 3)).readyTimeout, const Duration(seconds: 3));

      var calls = 0;
      final custom = _RecordingPolicy(() => calls++);
      final c = MovaSwapConfig(readyPolicy: custom);
      expect(c.newReadyPolicy(), same(custom));
      c.newReadyPolicy().onSignal(const MovaWarmSignal(
            position: Duration.zero,
            buffer: Duration.zero,
            target: Duration.zero,
            buffering: false,
            elapsed: Duration.zero,
          ));
      expect(calls, 1);
    });

    test('how long to wait before giving up: 8s by default, readyTimeout knob', () {
      expect(const MovaSwapConfig().readyTimeout, const Duration(seconds: 8));
      final policy = MovaBufferWarm(timeout: const Duration(seconds: 1));
      final verdict = policy.onSignal(const MovaWarmSignal(
        position: Duration.zero,
        buffer: Duration.zero,
        target: Duration.zero,
        buffering: false,
        elapsed: Duration(seconds: 1),
      ));
      expect(verdict, MovaWarmVerdict.giveUp);
    });

    test('whether the shadow is muted while warming: true by default, muteWhileWarm knob, actually honoured', () async {
      expect(const MovaSwapConfig().muteWhileWarm, isTrue);
      final made = <FakeMovaApi>[];
      final api = MovaSwapEngine(engineFactory: () {
        final f = FakeMovaApi(
          options: const MovaOpts(swap: MovaSwapConfig(enabled: true, muteWhileWarm: false)),
        );
        made.add(f);
        return f;
      });
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(made[1].lastVolume, isNull, reason: 'muteWhileWarm: false must not mute the shadow');
    });
  });

  group('barrel visibility', () {
    test('MovaSwapEngine is reachable from package:mova/mova.dart', () {
      final api = barrel.MovaSwapEngine(engineFactory: () => FakeMovaApi());
      expect(api, isA<barrel.MovaApi>());
    });

    test('MovaSwapConfig is reachable from package:mova/mova.dart', () {
      const c = barrel.MovaSwapConfig(enabled: true);
      expect(c.enabled, isTrue);
      const opts = barrel.MovaOpts(swap: c);
      expect(opts.swap.enabled, isTrue);
    });
  });
}

/// A [MovaWarmTrigger] that records every cue it is asked about.
///
/// 记录每次被询问的线索的 [MovaWarmTrigger]。
class _RecordingTrigger implements MovaWarmTrigger {
  _RecordingTrigger(this.calls);
  final List<MovaWarmCue> calls;

  @override
  bool shouldWarm(MovaWarmCue cue) {
    calls.add(cue);
    return true;
  }
}

/// A [MovaWarmPolicy] that records how many times it was consulted.
///
/// 记录被咨询次数的 [MovaWarmPolicy]。
class _RecordingPolicy implements MovaWarmPolicy {
  _RecordingPolicy(this.onCall);
  final void Function() onCall;

  @override
  MovaWarmVerdict onSignal(MovaWarmSignal signal) {
    onCall();
    return MovaWarmVerdict.waiting;
  }

  @override
  void reset() {}
}
