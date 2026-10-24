import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../support/fake_kernel.dart';
import '../support/standby_rig.dart';

const _high = MovaQuality(label: '720p', uri: 'https://h/720.m3u8', height: 720);
const _low = MovaQuality(label: '480p', uri: 'https://h/480.m3u8', height: 480);

void main() {
  test('1. defaults: standby is configured but never on, the guard pauses, the state is off', () {
    expect(const MovaOpts().standby, const MovaStandbyConfig());
    expect(const MovaAutoPauseConfig().hiddenMode, MovaHiddenMode.pause);
    expect(const MovaState().standby, MovaStandbyPhase.off);
  });

  test('2. zero-change anchor: the whole basic flow never reaches a standby kernel call or event', () {
    fakeAsync((async) {
      for (final type in MovaStreamType.values) {
        final k = FakeStandbyKernel();
        final r = StandbyRig(async, k);
        r.playLive(type: type);
        r.land();
        r.engine.pause();
        r.settle();
        r.engine.play();
        r.settle();
        r.engine.seek(const Duration(seconds: 1));
        r.settle();
        r.engine.setVolume(40);
        r.settle();
        r.engine.debugSetQualities(const [_high, _low], current: _high);
        r.engine.switchQuality(_low);
        r.settle();
        r.engine.backToLiveEdge();
        r.settle();
        r.engine.reload();
        r.settle();
        r.engine.dispose().ignore();
        async.elapse(const Duration(seconds: 1));
        r.settle();

        expect(k.calls, contains('open'), reason: type.name);
        for (final c in k.calls) {
          expect(c.startsWith('inspectStandby') || c.startsWith('enterStandby') || c.startsWith('exitStandby'), isFalse,
              reason: '${type.name}: $c');
        }
        expect(r.events.whereType<MovaStandbyChange>(), isEmpty, reason: type.name);
        expect(r.events.whereType<MovaStandbyResume>(), isEmpty, reason: type.name);
        expect(r.engine.state.standby, MovaStandbyPhase.off, reason: type.name);
      }
    });
  });

  test('3. MovaOpts.copyWith(standby:) swaps only the standby section', () {
    const custom = MovaStandbyConfig(maxDuration: Duration(seconds: 7), allowHls: true);
    const base = MovaOpts(recovery: MovaRecoveryConfig(enabled: true));
    final next = base.copyWith(standby: custom);
    expect(next.standby, custom);
    expect(next, const MovaOpts(recovery: MovaRecoveryConfig(enabled: true), standby: custom));
    expect(next.recovery, base.recovery);
    expect(next.live, base.live);
  });
}
