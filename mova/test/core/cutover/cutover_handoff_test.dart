import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/player_mute.dart';
import '../../support/fake_api.dart';
import 'cutover_operation_test.dart' show OperationRig, settleOperations;

const source = MovaSource('https://host/handoff.mp4');
const frame = MovaFirstFrame(
  sinceOpen: Duration.zero,
  signal: MovaFirstFrameSignal.restart,
);

void main() {
  test('换指窗口不转发旧播放器暂停态', () async {
    final rig = OperationRig();
    addTearDown(rig.api.dispose);
    final old = rig.movas.first..pushPlayingOnVerbs = true;
    await old.play();
    await settleOperations();
    final shadow = await rig.warm('successor');
    final gate = shadow.playGate = Completer<void>();
    final playing = <bool>[];
    rig.api.states.listen((s) => playing.add(s.playing));
    final committing = rig.api.commit();
    await settleOperations();
    expect(old.state.playing, isFalse);
    expect(rig.api.state.playing, isTrue);
    expect(playing, isNot(contains(false)));
    gate.complete();
    expect(await committing, isTrue);
  });
  test('换指窗口不转发旧播放器 MovaPause', () async {
    final rig = OperationRig();
    addTearDown(rig.api.dispose);
    final old = rig.movas.first;
    await rig.warm('successor');
    final gate = old.pauseGate = Completer<void>();
    final events = <MovaEvent>[];
    rig.api.events.listen(events.add);
    final committing = rig.api.commit();
    await settleOperations();
    old.pushEvent(const MovaPause());
    await settleOperations();
    expect(events.whereType<MovaPause>(), isEmpty);
    gate.complete();
    expect(await committing, isTrue);
  });
  test('提交放弃补发旧播放器真实状态', () async {
    final rig = OperationRig();
    addTearDown(rig.api.dispose);
    final old = rig.movas.first..pushPlayingOnVerbs = true;
    await old.play();
    final shadow = await rig.warm('successor');
    final gate = shadow.playGate = Completer<void>();
    final values = <bool>[];
    rig.api.states.listen((s) => values.add(s.playing));
    final committing = rig.api.commit();
    await settleOperations();
    expect(old.state.playing, isFalse);
    expect(rig.api.state.playing, isTrue);
    await rig.api.open(source);
    gate.complete();
    expect(await committing, isFalse);
    await settleOperations();
    expect(rig.api.state.playing, isFalse);
    expect(values, contains(false));
    // 放弃后继续转发新观测，不能永久冻结。
    old.push(old.state.copyWith(playing: true));
    await settleOperations();
    expect(rig.api.state.playing, isTrue);
  });
  test('影子 open 内生命周期换指后按顺序各补一次', () async {
    final movas = <LifecycleApi>[];
    final api = MovaCutover(
      movaFactory: () {
        final mova = LifecycleApi(
          options: const MovaOpts(cutover: MovaCutoverOpts(enabled: true)),
        );
        movas.add(mova);
        return mova;
      },
    );
    addTearDown(api.dispose);
    final seen = <Type>[];
    api.events.listen((e) {
      if (e is MovaSourceChange || e is MovaReady || e is MovaFirstFrame) {
        seen.add(e.runtimeType);
        expect(api.state.renderEpoch, movas.length - 1);
        expect(api.state.sourceTitle, 'new title');
      }
    });
    await api.play();
    await api.prepare(
      const MovaSource('https://host/new.mp4', title: 'new title'),
      plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
    );
    await settleOperations();
    expect(seen, isEmpty);
    const tick = MovaProg(
      position: Duration(seconds: 1),
      buffer: Duration(seconds: 10),
    );
    movas.last.pushProgress(tick);
    await settleOperations();
    movas.last.pushProgress(tick);
    await settleOperations();
    expect(await api.commit(), isTrue);
    expect(seen, [MovaSourceChange, MovaReady, MovaFirstFrame]);
    // 槽认领后才出现的首帧也属于影子期，不能因为 _slot 已换空而漏记。
    await api.prepare(const MovaSource('https://host/late.mp4', title: 'new title'),
      plan: const MovaWarmPlan(trigger: MovaEagerWarm()));
    final late = movas.last;
    late.pushProgress(tick); await settleOperations();
    late.pushProgress(tick); await settleOperations();
    final gate = late.playGate = Completer<void>();
    final committing = api.commit(); await settleOperations();
    late.pushEvent(frame); await settleOperations();
    gate.complete(); expect(await committing, isTrue);
    expect(seen, [MovaSourceChange, MovaReady, MovaFirstFrame,
      MovaSourceChange, MovaReady, MovaFirstFrame]);
  });
  test('影子放弃不补发生命周期并报告 abandoned', () async {
    final rig = OperationRig();
    addTearDown(rig.api.dispose);
    final events = <MovaEvent>[];
    rig.api.events.listen(events.add);
    final shadow = await rig.warm('abandon');
    shadow.pushEvent(const MovaSourceChange(source));
    shadow.pushEvent(const MovaReady());
    shadow.pushEvent(frame);
    await settleOperations();
    await rig.api.abandon();
    await settleOperations();
    expect(events.whereType<MovaFirstFrame>(), isEmpty);
    expect(
      events.whereType<MovaCutoverChange>().last.reason,
      MovaCutoverEndReason.abandoned,
    );
  });
  test('结束原因区分 timeout、shadowError 与宿主 superseded', () {
    fakeAsync((clock) {
      final rig = OperationRig();
      final reasons = <MovaCutoverEndReason?>[];
      rig.api.events.listen((e) {
        if (e is MovaCutoverChange && e.phase == MovaCutoverPhase.idle) {
          reasons.add(e.reason);
        }
      });
      unawaited(
        rig.api.prepare(
          source,
          plan: MovaWarmPlan(
            trigger: const MovaEagerWarm(),
            policy: MovaBufferWarm(timeout: const Duration(seconds: 1)),
          ),
        ),
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(reasons.last, MovaCutoverEndReason.timeout);
      unawaited(
        rig.api.prepare(
          source,
          plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
        ),
      );
      clock.flushMicrotasks();
      rig.movas.last.pushEvent(const MovaErrorEvent('shadow'));
      clock.flushMicrotasks();
      expect(reasons.last, MovaCutoverEndReason.shadowError);
      unawaited(
        rig.api.prepare(
          source,
          plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
        ),
      );
      clock.flushMicrotasks();
      unawaited(rig.api.open(source));
      clock.flushMicrotasks();
      expect(reasons.last, MovaCutoverEndReason.superseded);
      unawaited(
        rig.api.prepare(
          source,
          plan: MovaWarmPlan(
            trigger: const MovaEagerWarm(),
            policy: GiveUpPolicy(),
          ),
        ),
      );
      clock.flushMicrotasks();
      rig.movas.last.pushProgress(const MovaProg(position: Duration(seconds: 1)));
      clock.flushMicrotasks();
      expect(reasons.last, MovaCutoverEndReason.notReady);
      unawaited(rig.api.dispose());
      clock.flushMicrotasks();
    });
  });
  test('成功提交与销毁分别报告 committed/disposed', () async {
    final rig = OperationRig();
    final reasons = <MovaCutoverEndReason?>[];
    rig.api.events.listen((e) {
      if (e is MovaCutoverChange && e.phase == MovaCutoverPhase.idle) {
        reasons.add(e.reason);
      }
    });
    await rig.warm('commit');
    expect(await rig.api.commit(), isTrue);
    expect(reasons.last, MovaCutoverEndReason.committed);
    await rig.warm('dispose', readyNow: false);
    await rig.api.dispose();
    expect(reasons.last, MovaCutoverEndReason.disposed);
    final muted = <MuteRejectApi>[];
    final proxy = MovaCutover(
      movaFactory: () {
        final e = MuteRejectApi();
        muted.add(e);
        return e;
      },
    );
    addTearDown(proxy.dispose);
    final endings = <MovaCutoverEndReason?>[];
    proxy.events.listen((e) {
      if (e is MovaCutoverChange && e.phase == MovaCutoverPhase.idle) {
        endings.add(e.reason);
      }
    });
    await proxy.prepare(
      source,
      plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
    );
    const ready = MovaProg(
      position: Duration(seconds: 1),
      buffer: Duration(seconds: 10),
    );
    muted.last.pushProgress(ready);
    await settleOperations();
    muted.last.pushProgress(ready);
    await settleOperations();
    expect(await proxy.commit(), isFalse);
    expect(endings.last, MovaCutoverEndReason.muteRestoreFailed);
  });
  test('MovaCutoverChange 兼容旧 const 调用并保留可选原因', () {
    expect(const MovaCutoverChange(MovaCutoverPhase.idle).reason, isNull);
    expect(
      const MovaCutoverChange(
        MovaCutoverPhase.idle,
        reason: MovaCutoverEndReason.committed,
      ).reason,
      MovaCutoverEndReason.committed,
    );
  });
}

class LifecycleApi extends FakeMovaApi {
  LifecycleApi({super.options});
  @override
  Future<bool> open(MovaSource source, {bool autoPlay = true}) async {
    final accepted = await super.open(source, autoPlay: autoPlay);
    pushEvent(MovaSourceChange(source));
    pushEvent(const MovaReady());
    if (!source.uri.contains('late')) pushEvent(frame);
    push(state.copyWith(rendered: true));
    return accepted;
  }
}

class GiveUpPolicy implements IMovaWarmPolicy {
  @override
  MovaWarmVerdict onSignal(MovaWarmSignal signal) => MovaWarmVerdict.giveUp;
  @override
  void reset() {}
}

class MuteRejectApi extends FakeMovaApi implements IMovaPlayerMute {
  MuteRejectApi()
    : super(options: const MovaOpts(cutover: MovaCutoverOpts(enabled: true)));
  @override
  Future<bool> setWarmMute(bool on) async => on;
}
