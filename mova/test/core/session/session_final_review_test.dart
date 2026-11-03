import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/cutover/acceptance.dart';
import '../ads_interleaving_test.dart' show AdOperationRig;
import '../cutover/cutover_operation_test.dart' show OperationRig, settleOperations;
import 'session_transition_test.dart' show waitingPre;
import 'session_test.dart' show a, b;

const frame = MovaFirstFrame(sinceOpen: Duration.zero, signal: MovaFirstFrameSignal.restart);

void main() {
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
