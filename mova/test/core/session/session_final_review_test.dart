import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/cutover/acceptance.dart';
import '../ads_interleaving_test.dart' show AdOperationRig;
import '../cutover/cutover_operation_test.dart' show OperationRig, settleOperations;
import 'session_transition_test.dart' show waitingPre;
import 'session_test.dart' show a, b;

const frame = MovaFirstFrame(sinceOpen: Duration.zero, signal: MovaFirstFrameSignal.restart);

void main() {
  for (final kind in ['pre', 'content']) {
    test('宿主抢源结束原 $kind 节点一次并保留宿主新影子', () async {
      final rig = AdOperationRig(breaks: kind == 'pre' ? [waitingPre] : []);
      addTearDown(rig.dispose);
      final session = rig.ads.session;
      final events = <MovaSessionEvent>[];
      session.events.listen(events.add);
      Future<MovaLoadOutcome>? loading;
      if (kind == 'pre') {
        loading = session.load(a);
      } else {
        await session.load(a);
        await session.playAdNow(MovaAdBreak(kind: MovaAdBreakKind.mid,
          source: waitingPre.source, waitForReady: true));
      }
      await settleOperations();
      final start = events.whereType<MovaNodeStart>().single;
      final old = rig.engines.first;
      final staleShadow = rig.engines.last;
      final gate = old.pauseGate = Completer<void>();
      addTearDown(() { if (!gate.isCompleted) gate.complete(); });
      await rig.ready(staleShadow);
      await rig.api.open(b);
      const hostSource = MovaSource('https://host/new-host-shadow.mp4');
      final hostTicket = (await rig.api.prepareOwned(hostSource,
        plan: const MovaWarmPlan(trigger: MovaEagerWarm())))!;
      final hostShadow = rig.engines.last;
      await rig.ready(hostShadow);
      gate.complete();
      if (loading != null) expect(await loading, MovaLoadOutcome.superseded);
      await settleOperations();
      final end = events.whereType<MovaNodeEnd>().single;
      expect(end.node, start.node);
      expect(end.epoch, start.epoch);
      expect(end.reason, MovaNodeEndReason.superseded);
      expect(events.whereType<MovaNodeFail>(), isEmpty);
      expect(session.cursor.phase, MovaSessionPhase.idle);
      expect(session.cursor.node, isNull);
      expect(staleShadow.disposeCount, 1);
      expect(hostShadow.disposeCount, 0);
      expect(await rig.api.commitOwned(hostTicket), MovaWarmCommit.committed);
      expect(rig.api.active, same(hostShadow));
      expect(hostShadow.source, hostSource);
      await session.load(b, breaks: []);
      await settleOperations();
      expect(events.whereType<MovaNodeEnd>(), hasLength(1), reason: '后续加载不重复结束旧节点');
      expect(events.whereType<MovaNodeStart>().last.epoch, greaterThan(end.epoch));
    });
  }
  for (final command in ['load', 'jumpTo', 'setItems', 'dispose']) {
    test('会话 $command 取消挂在 old.pause 的已认领旧前贴片', () async {
      const nextPre = MovaAdBreak(kind: MovaAdBreakKind.pre,
        source: MovaSource('https://host/B-pre.mp4'), waitForReady: true);
      final rig = AdOperationRig(breaks: [waitingPre]);
      final session = rig.ads.session;
      addTearDown(rig.dispose);
      session.setItems([
        const MovaPlaylistItem(source: a, adBreaks: [waitingPre]),
        const MovaPlaylistItem(source: b, adBreaks: [nextPre]),
      ]);
      final loading = command == 'jumpTo' ? session.jumpTo(0) : session.load(a);
      await settleOperations();
      final old = rig.engines.first;
      final staleShadow = rig.engines.last;
      final gate = old.pauseGate = Completer<void>();
      addTearDown(() { if (!gate.isCompleted) gate.complete(); });
      await rig.ready(staleShadow);
      expect(old.calls, contains('pause'));
      Future<MovaLoadOutcome>? nextLoading;
      if (command == 'load') nextLoading = session.load(b, breaks: [nextPre]);
      if (command == 'jumpTo') nextLoading = session.jumpTo(1);
      if (command == 'setItems') session.setItems([const MovaPlaylistItem(source: b)]);
      if (command == 'dispose') await session.dispose();
      await settleOperations();
      expect(staleShadow.disposeCount, 1, reason: '无需等 old.pause 放行即可释放旧影子');
      MovaWarmTicket? hostTicket;
      if (command == 'setItems') {
        hostTicket = await rig.api.prepareOwned(b,
          plan: const MovaWarmPlan(trigger: MovaEagerWarm()));
      }
      final nextShadow = rig.engines.last;
      expect(rig.api.active, same(old));
      gate.complete();
      expect(await loading, command == 'dispose' ? MovaLoadOutcome.disposed : MovaLoadOutcome.superseded);
      await settleOperations();
      expect(rig.api.active, same(old), reason: '旧前贴片不得短暂提升上屏');
      expect(rig.api.state.renderEpoch, 0);
      if (nextLoading != null) {
        expect(nextShadow, isNot(same(staleShadow)));
        expect(nextShadow.disposeCount, 0);
        await rig.ready(nextShadow);
        expect(await nextLoading, MovaLoadOutcome.accepted);
        expect(rig.api.active, same(nextShadow));
        expect(nextShadow.source, nextPre.source);
        expect(rig.api.state.renderEpoch, 1);
      }
      if (hostTicket != null) {
        expect(nextShadow.disposeCount, 0);
        await rig.ready(nextShadow);
        expect(await rig.api.commitOwned(hostTicket), MovaWarmCommit.committed);
        expect(rig.api.active, same(nextShadow));
      }
    });
  }

  for (final takeover in [MovaSourceChange, MovaReady, MovaFirstFrame]) {
    test('补发 $takeover 回调抢源立即停止并返回 superseded', () async {
      final rig = OperationRig();
      addTearDown(rig.api.dispose);
      final ticket = (await rig.api.prepareOwned(a,
        plan: const MovaWarmPlan(trigger: MovaEagerWarm())))!;
      final shadow = rig.engines.last;
      shadow.pushEvent(const MovaSourceChange(a));
      shadow.pushEvent(const MovaReady());
      shadow.pushEvent(frame);
      await rig.ready(shadow);
      final lifecycle = <Type>[];
      Future<bool>? opening;
      rig.api.events.listen((e) {
        if (e is MovaSourceChange || e is MovaReady || e is MovaFirstFrame) {
          lifecycle.add(e.runtimeType);
          if (e.runtimeType == takeover) opening = rig.api.open(b);
        }
      });
      expect(await rig.api.commitOwned(ticket), MovaWarmCommit.superseded);
      expect(await opening, isTrue);
      await settleOperations();
      final sequence = [MovaSourceChange, MovaReady, MovaFirstFrame];
      expect(lifecycle, sequence.take(sequence.indexOf(takeover) + 1));
      expect(rig.api.active, same(shadow));
      expect(shadow.source, b);
      expect(rig.engines.first.disposeCount, 1);
      expect(shadow.disposeCount, 0);
      expect(rig.engines.where((e) => !e.disposed), [shadow]);
    });
  }
  test('广告补发 SourceChange 回调抢源后会话不登记宿主媒体为广告', () async {
    final rig = AdOperationRig(breaks: [waitingPre]);
    addTearDown(rig.dispose);
    final events = <MovaSessionEvent>[];
    rig.ads.session.events.listen(events.add);
    final loading = rig.ads.session.load(a);
    await settleOperations();
    final shadow = rig.engines.last;
    shadow.pushEvent(MovaSourceChange(waitingPre.source));
    shadow.pushEvent(const MovaReady());
    shadow.pushEvent(frame);
    await settleOperations();
    Future<bool>? opening;
    rig.api.events.listen((e) {
      if (e is MovaSourceChange) opening = rig.api.open(b);
    });
    final startsBeforeTakeover = events.whereType<MovaNodeStart>().length;
    await rig.ready(shadow);
    expect(await loading, MovaLoadOutcome.superseded);
    expect(await opening, isTrue);
    await settleOperations();
    expect(shadow.source, b);
    expect(rig.ads.session.cursor.phase, MovaSessionPhase.idle);
    expect(events.whereType<MovaNodeStart>(), hasLength(startsBeforeTakeover));
    expect(events.whereType<MovaNodeFail>(), isEmpty);
    expect(rig.engines.first.disposeCount, 1);
  });
}
