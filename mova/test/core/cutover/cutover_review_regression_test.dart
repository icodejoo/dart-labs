import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../../support/fake_api.dart';
import 'cutover_operation_test.dart'
    show OperationRig, DetachGatedApi, settleOperations;

/// Verifies late commands and fatal errors throughout the hand-off window.
///
/// 验证整个提交窗口内后到的播放命令与终结错误。
void main() {
  for (final point in ['play', 'detach']) {
    test('C1 pause during $point leaves the promoted shadow paused', () async {
      final rig = OperationRig();
      addTearDown(rig.api.dispose);
      final old = rig.engines.first as DetachGatedApi;
      old.pushPlayingOnVerbs = true;
      await rig.api.play();
      final shadow = await rig.warm('successor');
      shadow.pushPlayingOnVerbs = true;
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      if (point == 'play') shadow.playGate = gate;
      if (point == 'detach') old.detachGate = gate;
      final committing = rig.api.commit();
      await settleOperations();
      await rig.api.pause();
      gate.complete();
      expect(await committing, isTrue);
      expect(rig.api.active, same(shadow));
      expect(shadow.state.playbackIntent, isFalse);
      expect(shadow.state.playing, isFalse);
    });

    test('C3 fatal shadow error during $point prevents promotion', () async {
      final rig = OperationRig();
      addTearDown(rig.api.dispose);
      final old = rig.engines.first as DetachGatedApi;
      final shadow = await rig.warm('failed');
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      if (point == 'play') shadow.playGate = gate;
      if (point == 'detach') old.detachGate = gate;
      final reasons = <MovaCutoverEndReason?>[];
      rig.api.events.listen((e) {
        if (e is MovaCutoverChange) reasons.add(e.reason);
      });
      final committing = rig.api.commit();
      await settleOperations();
      shadow.pushEvent(const MovaErrorEvent('fatal shadow'));
      await settleOperations();
      gate.complete();
      expect(await committing, isFalse);
      await settleOperations();
      expect(rig.api.active, same(old));
      expect(rig.api.state.renderEpoch, 0);
      expect(shadow.disposeCount, 1);
      expect(reasons.last, MovaCutoverEndReason.shadowError);
    });
  }

  test('C1 pause then play during detach promotes a playing shadow', () async {
    final rig = OperationRig();
    addTearDown(rig.api.dispose);
    final old = rig.engines.first as DetachGatedApi;
    old.pushPlayingOnVerbs = true;
    await rig.api.pause();
    final shadow = await rig.warm('successor');
    shadow.pushPlayingOnVerbs = true;
    final gate = old.detachGate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final committing = rig.api.commit();
    await settleOperations();
    expect(rig.api.active, same(old));
    expect(shadow.calls, contains('pause'));
    expect(shadow.state.playing, isFalse);
    await rig.api.pause();
    await rig.api.play();
    expect(old.state.playbackIntent, isTrue);
    expect(shadow.state.playbackIntent, isFalse);
    gate.complete();
    expect(await committing, isTrue);
    expect(rig.api.active, same(shadow));
    expect(shadow.state.playbackIntent, isTrue);
    expect(shadow.state.playing, isTrue);
    expect(rig.api.state.playbackIntent, isTrue);
    expect(rig.api.state.playing, isTrue);
  });

  test(
    'C10 pause then play clears the keepAlive wish for the next engine',
    () async {
      final made = <FakeKeepAliveApi>[];
      final api = MovaCutoverEngine(
        engineFactory: () {
          final engine = FakeKeepAliveApi(
            options: const MovaOpts(
              cutover: MovaCutoverConfig(enabled: true, muteWhileWarm: false),
            ),
          );
          made.add(engine);
          return engine;
        },
      );
      addTearDown(api.dispose);
      await api.setKeepAlive(true);
      await api.pause();
      await api.play();
      await api.prepare(
        const MovaSource('https://host/live', type: MovaStreamType.live),
        plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
      );
      const tick = MovaProg(
        position: Duration(seconds: 1),
        buffer: Duration(seconds: 10),
      );
      made.last.pushProgress(tick);
      await settleOperations();
      made.last.pushProgress(tick);
      await settleOperations();
      expect(await api.commit(), isTrue);
      expect(made.last.calls, isNot(contains('setKeepAlive:true')));
      expect(made.last.state.playbackIntent, isTrue);
    },
  );
}
