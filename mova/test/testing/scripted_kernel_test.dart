import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/testing.dart';
import 'package:mova/src/testing/hooks.dart';

Mova _mova(MovaTestKernel kernel) => Mova(
  kernel: kernel,
  ownsKernel: true,
  fetcher: const MovaTestHttpFetch(),
  options: const MovaOpts(
    controls: MovaCtrlsOpts(autoHide: false),
    abr: MovaAbrOpts(probeVariants: false),
  ),
);
const _source = MovaSource('https://host/a.mp4');
void main() {
  test(
    'C15 default kernel stays passive while scripted mode lands the first frame',
    () {
      fakeAsync((async) {
        final passiveKernel = MovaTestKernel();
        final passiveSignals = <bool>[];
        passiveKernel.playing.listen(passiveSignals.add);
        final passive = _mova(passiveKernel),
            active = _mova(MovaTestKernel.scripted());
        passive.open(_source);
        active.open(_source);
        async.flushMicrotasks();
        passiveKernel.play();
        passiveKernel.pause();
        async.flushMicrotasks();
        expect(passiveSignals, isEmpty);
        expect(passive.state.rendered, isFalse);
        expect(active.state.rendered, isTrue);
        expect(active.state.width, 1280);
        expect(active.state.playing, isTrue);
        expect(
          async.pendingTimers,
          isEmpty,
          reason: async.pendingTimersDebugString.join(),
        );
        passive.dispose();
        active.dispose();
        async.flushMicrotasks();
      });
    },
  );
  test('C15 delayed ready obeys timing metadata and paused open', () {
    fakeAsync((async) {
      final mova = _mova(
        MovaTestKernel.scripted(
          script: const [
            MovaTestStep.ready(
              after: Duration(seconds: 1),
              width: 640,
              height: 360,
              duration: Duration(seconds: 90),
            ),
          ],
        ),
      );
      mova.open(_source, autoPlay: false);
      async.flushMicrotasks();
      expect(mova.state.rendered, isFalse);
      async.elapse(const Duration(milliseconds: 999));
      expect(mova.state.rendered, isFalse);
      async.elapse(const Duration(milliseconds: 1));
      expect(mova.state.rendered, isTrue);
      expect(mova.state.playing, isFalse);
      expect(mova.state.width, 640);
      expect(mova.state.duration, const Duration(seconds: 90));
      mova.dispose();
      async.flushMicrotasks();
    });
  });
  for (final scenario in [
    (initial: true, commands: [false]),
    (initial: false, commands: [true]),
    (initial: true, commands: [false, true, false]),
    (initial: false, commands: [true, false, true]),
  ]) {
    test('review P2 delayed ready uses latest intent ${scenario.initial} ${scenario.commands}', () {
      fakeAsync((async) {
        final kernel = MovaTestKernel.scripted(script: const [
          MovaTestStep.ready(after: Duration(seconds: 1)),
        ]);
        final mova = _mova(kernel);
        mova.open(_source, autoPlay: scenario.initial);
        async.flushMicrotasks();
        for (final play in scenario.commands) {
          if (play) { mova.play(); } else { mova.pause(); }
          async.flushMicrotasks();
        }
        expect(mova.state.rendered, isFalse);
        async.elapse(const Duration(seconds: 1));
        expect(mova.state.rendered, isTrue);
        expect(mova.state.playing, scenario.commands.last);
        expect(mova.state.playbackIntent, scenario.commands.last);
        expect(kernel.lastPlay, scenario.initial, reason: 'open 诊断仍保留原始参数');
        mova.dispose();
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });
  }
  test(
    'C15 buffering and progress steps use delays relative to the previous step',
    () {
      fakeAsync((async) {
        final mova = _mova(
          MovaTestKernel.scripted(
            script: const [
              MovaTestStep.ready(),
              MovaTestStep.buffering(true, after: Duration(seconds: 1)),
              MovaTestStep.position(
                Duration(seconds: 7),
                after: Duration(seconds: 1),
              ),
              MovaTestStep.buffering(false),
            ],
          ),
        );
        final positions = <Duration>[];
        mova.progress.listen((p) => positions.add(p.position));
        mova.open(_source);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        expect(mova.state.buffering, isTrue);
        async.elapse(const Duration(seconds: 1));
        expect(mova.state.buffering, isFalse);
        expect(positions, contains(const Duration(seconds: 7)));
        mova.dispose();
        async.flushMicrotasks();
      });
    },
  );
  test('C15 scripted failure reaches normal player error handling', () {
    fakeAsync((async) {
      final mova = _mova(
        MovaTestKernel.scripted(
          script: const [
            MovaTestStep.error('Failed to initialize a decoder for codec h264'),
          ],
        ),
      );
      final errors = <MovaErrorEvent>[];
      mova.events
          .where((e) => e is MovaErrorEvent)
          .listen((e) => errors.add(e as MovaErrorEvent));
      mova.open(_source);
      async.flushMicrotasks();
      expect(errors, hasLength(1));
      expect(mova.state.error, isNotNull);
      expect(mova.state.rendered, isFalse);
      mova.dispose();
      async.flushMicrotasks();
    });
  });
  test(
    'C15 scripted completion stops playback and restarts from the first step on reopen',
    () {
      fakeAsync((async) {
        final kernel = MovaTestKernel.scripted(
          script: const [
            MovaTestStep.ready(),
            MovaTestStep.completed(after: Duration(seconds: 2)),
          ],
        );
        final mova = _mova(kernel);
        mova.open(_source);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        expect(mova.state.completed, isTrue);
        expect(mova.state.playing, isFalse);
        mova.open(_source);
        async.flushMicrotasks();
        expect(mova.state.completed, isFalse);
        expect(mova.state.playing, isTrue);
        kernel.dispose();
        mova.dispose();
        async.flushMicrotasks();
        expect(
          async.pendingTimers,
          isEmpty,
          reason: async.pendingTimersDebugString.join(),
        );
      });
    },
  );
  test('C15 reopen and dispose cancel stale delayed and queued steps', () {
    fakeAsync((async) {
      final kernel = MovaTestKernel.scripted(
        script: const [MovaTestStep.ready(after: Duration(seconds: 2))],
      );
      final mova = _mova(kernel);
      mova.open(_source);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      mova.open(const MovaSource('https://host/b.mp4'));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      expect(mova.state.rendered, isFalse);
      async.elapse(const Duration(seconds: 1));
      expect(mova.state.rendered, isTrue);
      mova.open(_source);
      async.flushMicrotasks();
      kernel.dispose();
      mova.dispose();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 250));
      expect(
        async.pendingTimers,
        isEmpty,
        reason: async.pendingTimersDebugString.join(),
      );
      async.elapse(const Duration(seconds: 10));
      expect(kernel.calls.where((c) => c == 'dispose'), hasLength(1));
      // 零延迟步骤也必须受代际保护，销毁后不写入已经关闭的控制器。
      final queued = MovaTestKernel.scripted();
      queued.open('file:///a');
      queued.dispose();
      async.flushMicrotasks();
    });
  });
}
