import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/cutover/acceptance.dart';

import '../ads_interleaving_test.dart' show AdOperationRig;
import '../cutover/cutover_operation_test.dart' show settleOperations;
import 'session_test.dart' show a, b;

/// Verifies legacy cleanup without cancelling another owner's warm-up or commit.
///
/// 验证清理旧式影子时保留其他所有者的预热与提交。
void main() {
  for (final cleanup in ['idle', 'dispose']) {
    for (final owned in [false, true]) {
      test('session $cleanup cleans legacy warm only / 会话清理仅放弃无主影子 '
          'owned=$owned', () async {
        final rig = AdOperationRig();
        addTearDown(rig.dispose);
        await rig.ads.load(a);
        const plan = MovaWarmPlan(trigger: MovaEagerWarm());
        MovaWarmTicket? ticket;
        if (owned) {
          ticket = await rig.api.prepareOwned(b, plan: plan);
          expect(ticket, isNotNull);
        } else {
          await rig.api.prepare(b, plan: plan);
        }
        final shadow = rig.movas.last;
        expect(rig.api.cutoverPhase, MovaCutoverPhase.warming);
        if (cleanup == 'idle') {
          rig.movas.first.emitDone();
          await settleOperations();
          expect(rig.ads.session.cursor.phase, MovaSessionPhase.idle);
        } else {
          await rig.ads.dispose();
        }
        if (owned) {
          expect(shadow.disposeCount, 0);
          expect(rig.api.cutoverPhase, MovaCutoverPhase.warming);
          await rig.ready(shadow);
          expect(await rig.api.commitOwned(ticket!), MovaWarmCommit.committed);
          expect(rig.api.active, same(shadow));
        } else {
          expect(shadow.disposeCount, 1);
          expect(rig.api.cutoverPhase, MovaCutoverPhase.idle);
        }
      });
    }
  }

  test(
    'session disposal preserves claimed host commit / 会话销毁保留宿主已认领提交',
    () async {
      final rig = AdOperationRig();
      addTearDown(rig.dispose);
      await rig.ads.load(a);
      final ticket = (await rig.api.prepareOwned(
        b,
        plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
      ))!;
      final shadow = rig.movas.last;
      await rig.ready(shadow);
      final gate = rig.movas.first.pauseGate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final committing = rig.api.commitOwned(ticket);
      await settleOperations();
      expect(rig.movas.first.calls, contains('pause'));
      await rig.ads.dispose();
      expect(shadow.disposeCount, 0);
      gate.complete();
      expect(await committing, MovaWarmCommit.committed);
      expect(rig.api.active, same(shadow));
    },
  );
}
