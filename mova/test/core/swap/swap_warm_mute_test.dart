import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../../support/fake_kernel.dart';
import '../../support/warm_mute_kernel.dart';

/// Lets kernel stream forwarding settle before checking readiness.
///
/// 等待内核流转发落定，再检查就绪状态。
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 220));

/// Drives a real engine to the swap policy's ready state.
///
/// 驱动真实引擎达到切换策略的就绪状态。
Future<void> _ready(FakeKernel k) async {
  k.emitBuffer(const Duration(seconds: 10));
  await _settle();
  for (var i = 1; i <= 4; i++) {
    k.emitPosition(Duration(seconds: i));
    await _settle();
  }
}

/// Runs warm-up and commit against real engines with recording volume ports.
///
/// 用真实引擎和记录音量端口运行预热及提交。
void main() {
  for (final mute in [true, false]) {
    test(
      'warm mute $mute bypasses volume ports through prepare and commit',
      () async {
        final writes = <double>[];
        final kernels = <FakeWarmMuteKernel>[];
        final api = MovaSwapEngine(
          engineFactory: () {
            final k = FakeWarmMuteKernel();
            kernels.add(k);
            return MovaEngine(
              kernel: k,
              volume: MovaCallbackVolumePort(writes.add, onGet: () async => 37),
              options: MovaOpts(
                swap: MovaSwapConfig(enabled: true, muteWhileWarm: mute),
                controls: const MovaCtrlsConfig(autoHide: false),
              ),
            );
          },
        );
        addTearDown(api.dispose);
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
      final api = MovaSwapEngine(
        engineFactory: () {
          final k = FakeKernel();
          kernels.add(k);
          return MovaEngine(
            kernel: k,
            volume: MovaCallbackVolumePort(writes.add, onGet: () async => 37),
            options: const MovaOpts(
              swap: MovaSwapConfig(enabled: true),
              controls: MovaCtrlsConfig(autoHide: false),
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
    'standby commit releases warm mute before play without volume writes',
    () async {
      final writes = <double>[];
      final kernels = <FakeWarmMuteKernel>[];
      final api = MovaSwapEngine(
        engineFactory: () {
          final k = FakeWarmMuteKernel();
          kernels.add(k);
          return MovaEngine(
            kernel: k,
            volume: MovaCallbackVolumePort(writes.add),
            options: const MovaOpts(
              swap: MovaSwapConfig(enabled: true),
              controls: MovaCtrlsConfig(autoHide: false),
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
      expect(await api.setStandby(true), MovaStandbyPhase.holding);
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
          'enterStandby:muted',
          'warmMute:false',
        ]),
      );
      expect(shadow.warmMuted, isFalse);
      expect(shadow.heldMode, MovaStandbyMode.muted);
      await api.setStandby(false);
      expect(shadow.heldMode, isNull);
      expect(shadow.warmMuted, isFalse);
      expect(writes, isEmpty);
    },
  );

  test(
    'failed mute restoration emits an error and abandons the swap',
    () async {
      final kernels = <FakeWarmMuteKernel>[];
      final writes = <double>[];
      final events = <MovaEvent>[];
      final api = MovaSwapEngine(
        engineFactory: () {
          final k = FakeWarmMuteKernel();
          kernels.add(k);
          return MovaEngine(
            kernel: k,
            volume: MovaCallbackVolumePort(writes.add),
            options: const MovaOpts(
              swap: MovaSwapConfig(enabled: true),
              controls: MovaCtrlsConfig(autoHide: false),
            ),
          );
        },
      );
      addTearDown(api.dispose);
      final sub = api.events.listen(events.add);
      addTearDown(sub.cancel);
      kernels.first.emitPlaying(true);
      await _settle();
      await api.prepare(
        const MovaSource('https://host/shadow.flv'),
        plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
      );
      final shadow = kernels[1]..releaseResult = false;
      await _ready(shadow);
      expect(await api.commit(), isFalse);
      await _settle();
      expect(api.swapPhase, MovaSwapPhase.idle);
      expect(events.whereType<MovaErrorEvent>(), hasLength(1));
      expect(kernels.first.calls, containsAllInOrder(['pause', 'play']));
      expect(shadow.calls, contains('dispose'));
      expect(writes, isEmpty);
    },
  );
}
