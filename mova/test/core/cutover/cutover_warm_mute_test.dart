import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../../support/fake_kernel.dart';
import '../../support/warm_mute_kernel.dart';

/// Lets kernel stream forwarding settle before checking readiness.
///
/// 等待内核流转发落定，再检查就绪状态。
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 220));

/// Drives a real player to the cutover policy's ready state.
///
/// 驱动真实播放器达到切换策略的就绪状态。
Future<void> _ready(FakeKernel k) async {
  k.emitBuffer(const Duration(seconds: 10));
  await _settle();
  for (var i = 1; i <= 4; i++) {
    k.emitPosition(Duration(seconds: i));
    await _settle();
  }
}

/// Runs warm-up and commit against real players with recording volume ports.
///
/// 用真实播放器和记录音量端口运行预热及提交。
void main() {
  for (final mute in [true, false]) {
    test(
      'warm mute $mute bypasses volume ports through prepare and commit',
      () async {
        final writes = <double>[];
        final kernels = <FakeWarmMuteKernel>[];
        final api = MovaCutover(
          movaFactory: () {
            final k = FakeWarmMuteKernel();
            kernels.add(k);
            return Mova(
              kernel: k, ownsKernel: true,
              volume: MovaCallbackVolume(writes.add, onGet: () async => 37),
              options: MovaOpts(
                cutover: MovaCutoverOpts(enabled: true, muteWhileWarm: mute),
                controls: const MovaCtrlsOpts(autoHide: false),
              ),
            );
          },
        );
        addTearDown(api.dispose);
        await api.play();
        await api.prepare(
          const MovaSource('https://host/shadow.flv'),
          plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
        );
        final shadow = kernels[1];
        expect(writes, isEmpty);
        expect(shadow.warmMuted, mute);
        if (mute) {
          expect(shadow.calls, containsAllInOrder(['warmMute:true', 'open']));
        }
        expect(kernels.first.warmMuted, isFalse);
        await _ready(shadow);
        expect(await api.commit(), isTrue);
        expect(shadow.warmMuted, isFalse);
        expect(writes, isEmpty);
        expect(shadow.calls, isNot(contains('setVolume')));
        if (mute) {
          expect(shadow.calls, containsAllInOrder(['warmMute:false', 'play']));
          await api.prepare(
            const MovaSource('https://host/cancelled.flv'),
            plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
          );
          final cancelled = kernels.last;
          expect(cancelled.warmMuted, isTrue);
          await api.abandon();
          expect(cancelled.calls, contains('dispose'));
          expect(writes, isEmpty);
        }
        if (!mute) {
          expect(shadow.calls.any((c) => c.startsWith('warmMute:')), isFalse);
        }
      },
    );
  }

  test(
    'unsupported kernel warms and commits without any volume writes',
    () async {
      final writes = <double>[];
      final kernels = <FakeKernel>[];
      final api = MovaCutover(
        movaFactory: () {
          final k = FakeKernel();
          kernels.add(k);
          return Mova(
            kernel: k, ownsKernel: true,
            volume: MovaCallbackVolume(writes.add, onGet: () async => 37),
            options: const MovaOpts(
              cutover: MovaCutoverOpts(enabled: true),
              controls: MovaCtrlsOpts(autoHide: false),
            ),
          );
        },
      );
      addTearDown(api.dispose);
      await api.prepare(
        const MovaSource('https://host/shadow.flv'),
        plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
      );
      await _ready(kernels[1]);
      expect(await api.commit(), isTrue);
      expect(writes, isEmpty);
      expect(kernels[1].calls, isNot(contains('setVolume')));
    },
  );

  test(
    'keepAlive commit releases warm mute before play without volume writes',
    () async {
      final writes = <double>[];
      final kernels = <FakeWarmMuteKernel>[];
      final api = MovaCutover(
        movaFactory: () {
          final k = FakeWarmMuteKernel();
          kernels.add(k);
          return Mova(
            kernel: k, ownsKernel: true,
            volume: MovaCallbackVolume(writes.add),
            options: const MovaOpts(
              cutover: MovaCutoverOpts(enabled: true),
              controls: MovaCtrlsOpts(autoHide: false),
            ),
          );
        },
      );
      addTearDown(api.dispose);
      await api.open(
        const MovaSource('https://host/active.flv', type: MovaStreamType.live),
      );
      kernels.first.emitPlaying(true);
      await _settle();
      expect(await api.setKeepAlive(true), MovaKeepAlivePhase.holding);
      await api.prepare(
        const MovaSource('https://host/shadow.flv', type: MovaStreamType.live),
        plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
      );
      final shadow = kernels[1];
      shadow.emitPlaying(true);
      await _ready(shadow);
      expect(await api.commit(), isTrue);
      expect(
        shadow.calls,
        containsAllInOrder([
          'warmMute:true',
          'enterKeepAlive:muted',
          'warmMute:false',
        ]),
      );
      expect(shadow.warmMuted, isFalse);
      expect(shadow.heldMode, MovaKeepAliveMode.muted);
      await api.setKeepAlive(false);
      expect(shadow.heldMode, isNull);
      expect(shadow.warmMuted, isFalse);
      expect(writes, isEmpty);
    },
  );

  test(
    'failed mute restoration emits an error and abandons the cutover',
    () async {
      final kernels = <FakeWarmMuteKernel>[];
      final writes = <double>[];
      final events = <MovaEvent>[];
      final api = MovaCutover(
        movaFactory: () {
          final k = FakeWarmMuteKernel();
          kernels.add(k);
          return Mova(
            kernel: k, ownsKernel: true,
            volume: MovaCallbackVolume(writes.add),
            options: const MovaOpts(
              cutover: MovaCutoverOpts(enabled: true),
              controls: MovaCtrlsOpts(autoHide: false),
            ),
          );
        },
      );
      addTearDown(api.dispose);
      final sub = api.events.listen(events.add);
      addTearDown(sub.cancel);
      kernels.first.emitPlaying(true);
      await api.play();
      await _settle();
      await api.prepare(
        const MovaSource('https://host/shadow.flv'),
        plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
      );
      final shadow = kernels[1]..releaseResult = false;
      await _ready(shadow);
      expect(await api.commit(), isFalse);
      await _settle();
      expect(api.cutoverPhase, MovaCutoverPhase.idle);
      expect(events.whereType<MovaErrorEvent>(), hasLength(1));
      expect(kernels.first.calls, containsAllInOrder(['pause', 'play']));
      expect(shadow.calls, contains('dispose'));
      expect(writes, isEmpty);
    },
  );
}
