import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart' as barrel;
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/cutover/cutover.dart';
import 'package:mova/src/core/cutover/trigger.dart';
import 'package:mova/src/core/cutover/warm.dart';

import '../support/fake_api.dart';

void main() {
  group('seamless-cutover openness contract — every row needs default + knob + injection', () {
    test('whether cutover is enabled at all: off by default, enabled knob', () {
      expect(const MovaCutoverOpts().enabled, isFalse);
      expect(const MovaCutoverOpts(enabled: true).enabled, isTrue);
    });

    test('when warming starts: 2s lead by default, leadTime knob, trigger injection', () {
      expect(const MovaCutoverOpts().leadTime, const Duration(seconds: 2));
      expect(const MovaCutoverOpts(leadTime: Duration(seconds: 5)).leadTime, const Duration(seconds: 5));

      final calls = <MovaWarmCue>[];
      final custom = _RecordingTrigger(calls);
      final c = MovaCutoverOpts(trigger: custom);
      expect(c.effectiveTrigger, same(custom));
      c.effectiveTrigger.shouldWarm(const MovaWarmCue(remaining: Duration(seconds: 1)));
      expect(calls, hasLength(1));
    });

    test('how short a clip never warms: 5s by default, minWarmDuration knob (policy-owned decision)', () {
      expect(const MovaCutoverOpts().minWarmDuration, const Duration(seconds: 5));
      const c = MovaCutoverOpts(minWarmDuration: Duration(seconds: 20));
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
      expect(const MovaCutoverOpts().readyTimeout, const Duration(seconds: 8));
      expect(const MovaCutoverOpts(readyTimeout: Duration(seconds: 3)).readyTimeout, const Duration(seconds: 3));

      var calls = 0;
      final custom = _RecordingPolicy(() => calls++);
      final c = MovaCutoverOpts(readyPolicy: custom);
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
      expect(const MovaCutoverOpts().readyTimeout, const Duration(seconds: 8));
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
      expect(const MovaCutoverOpts().muteWhileWarm, isTrue);
      final made = <FakeMovaApi>[];
      final api = MovaCutover(movaFactory: () {
        final f = FakeMovaApi(
          options: const MovaOpts(cutover: MovaCutoverOpts(enabled: true, muteWhileWarm: false)),
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
    test('MovaCutover is reachable from package:mova/mova.dart', () {
      final api = barrel.MovaCutover(movaFactory: () => FakeMovaApi());
      expect(api, isA<barrel.IMovaApi>());
    });

    test('MovaCutoverOpts is reachable from package:mova/mova.dart', () {
      const c = barrel.MovaCutoverOpts(enabled: true);
      expect(c.enabled, isTrue);
      const opts = barrel.MovaOpts(cutover: c);
      expect(opts.cutover.enabled, isTrue);
    });
  });
}

/// A [IMovaWarmTrigger] that records every cue it is asked about.
///
/// 记录每次被询问的线索的 [IMovaWarmTrigger]。
class _RecordingTrigger implements IMovaWarmTrigger {
  _RecordingTrigger(this.calls);
  final List<MovaWarmCue> calls;

  @override
  bool shouldWarm(MovaWarmCue cue) {
    calls.add(cue);
    return true;
  }
}

/// A [IMovaWarmPolicy] that records how many times it was consulted.
///
/// 记录被咨询次数的 [IMovaWarmPolicy]。
class _RecordingPolicy implements IMovaWarmPolicy {
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
