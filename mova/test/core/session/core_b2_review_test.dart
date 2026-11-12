import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/cutover/acceptance.dart';

import '../../support/fake_api.dart';
import '../ads_interleaving_test.dart' show AdOperationRig;
import '../cutover/cutover_operation_test.dart' show settleOperations;
import 'session_test.dart' show a, b, mid;

/// Covers pending-ad ownership and callback reentrancy from coreB2.
///
/// 覆盖 coreB2 的待播广告归属与回调重入问题。
void main() {
  for (final committing in [false, true]) {
    for (final giveUp in [false, true]) {
      test('content failure cancels pending ad / 正片失败取消待播广告 '
          'committing=$committing giveUp=$giveUp', () async {
        final rig = AdOperationRig(breaks: [mid]);
        addTearDown(rig.dispose);
        final session = rig.ads.session;
        final errors = <Object>[];
        final ended = <void>[];
        final nodes = <MovaSessionEvent>[];
        session.contentError.listen(errors.add);
        session.contentEnded.listen(ended.add);
        session.events.listen(nodes.add);
        await session.load(a);
        final content = rig.engines.first;
        content.pushProgress(const MovaProg(position: Duration(seconds: 2)));
        await settleOperations();
        final shadow = rig.engines.last;
        final gate = content.pauseGate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        if (committing) await rig.ready(shadow);
        expect(session.isAdPending, isTrue);
        content.pushEvent(
          giveUp
              ? MovaPlayFailure(
                  MovaPlayFail(
                    kind: MovaPlayFailKind.nativeEndError,
                    sourceIndex: 0,
                    uri: a.uri,
                    sourceCount: 1,
                    attempt: 1,
                    streak: 1,
                    error: 'content failed',
                  ),
                  MovaRecoveryAction.giveUp,
                )
              : const MovaErrorEvent.classified(
                  'content failed',
                  fatal: true,
                  source: a,
                ),
        );
        await settleOperations();
        expect(errors, ['content failed']);
        expect(ended, isEmpty);
        expect(
          nodes.whereType<MovaNodeFail>().single.node.kind,
          MovaNodeKind.content,
        );
        expect(session.cursor.phase, MovaSessionPhase.idle);
        expect(shadow.disposeCount, 1);
        gate.complete();
        await settleOperations();
        expect(rig.api.active, same(content));
        expect(rig.api.state.renderEpoch, 0);
        expect(session.cursor.phase, MovaSessionPhase.idle);
        expect(nodes.whereType<MovaNodeStart>(), hasLength(1));
        expect(errors, hasLength(1));
      });
    }
  }

  test(
    'recoverable content failure keeps pending commit / 恢复中的正片错误保留待播提交',
    () async {
      final api = FakeMovaApi(
        options: const MovaOpts(
          recovery: MovaRecoveryConfig(enabled: true),
          ads: MovaAdConfig(enabled: true, breaks: [mid]),
        ),
      );
      final cutover = FakeCutoverCtl();
      final ads = MovaAds(api, cutover: cutover);
      final gate = Completer<void>();
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await ads.dispose();
        await api.dispose();
        await cutover.dispose();
      });
      final errors = <Object>[];
      ads.session.contentError.listen(errors.add);
      await ads.load(a);
      cutover.commitResult = true;
      cutover.commitGate = gate;
      api.pushProgress(const MovaProg(position: Duration(seconds: 2)));
      await settleOperations();
      api.pushEvent(
        const MovaErrorEvent.classified('recovering', fatal: true, source: a),
      );
      await settleOperations();
      expect(errors, isEmpty);
      expect(ads.isAdPending, isTrue);
      gate.complete();
      await settleOperations();
      expect(ads.isShowingAd, isTrue);
    },
  );

  test('content EOF cancels claimed midroll / 正片结束取消已认领中插', () async {
    final rig = AdOperationRig(breaks: [mid]);
    addTearDown(rig.dispose);
    final session = rig.ads.session;
    final ends = <void>[];
    final nodes = <MovaSessionEvent>[];
    session.contentEnded.listen(ends.add);
    session.events.listen(nodes.add);
    await session.load(a);
    final content = rig.engines.first;
    content.push(content.state.copyWith(duration: const Duration(seconds: 10)));
    content.pushProgress(const MovaProg(position: Duration(seconds: 9)));
    await settleOperations();
    final shadow = rig.engines.last;
    final gate = content.pauseGate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await rig.ready(shadow);
    expect(content.calls, contains('pause'));
    content.pushEvent(const MovaDone());
    await settleOperations();
    expect(ends, hasLength(1));
    expect(shadow.disposeCount, 1);
    gate.complete();
    await settleOperations();
    expect(rig.api.active, same(content));
    expect(rig.api.state.renderEpoch, 0);
    expect(session.cursor.phase, MovaSessionPhase.idle);
    expect(nodes.whereType<MovaNodeStart>(), hasLength(1));
    expect(
      nodes.whereType<MovaNodeEnd>().single.reason,
      MovaNodeEndReason.completed,
    );
  });

  test('content EOF cancels late prepare / 正片结束取消迟到预热', () async {
    final gate = Completer<void>();
    final rig = AdOperationRig(breaks: [mid], gateShadow: gate);
    addTearDown(rig.dispose);
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await rig.ads.load(a);
    final content = rig.engines.first;
    content.push(content.state.copyWith(duration: const Duration(seconds: 10)));
    content.pushProgress(const MovaProg(position: Duration(seconds: 9)));
    await settleOperations();
    final shadow = rig.engines.last;
    expect(shadow, isNot(same(content)));
    content.pushEvent(const MovaDone());
    await settleOperations();
    gate.complete();
    await settleOperations();
    expect(shadow.disposeCount, 1);
    expect(rig.api.active, same(content));
    expect(rig.api.cutoverPhase, MovaCutoverPhase.idle);
    expect(rig.ads.session.cursor.phase, MovaSessionPhase.idle);
  });

  test('late legacy commit cannot revive ad / 旧式提交迟到不激活广告', () async {
    final api = FakeMovaApi(
      options: const MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [mid])),
    );
    final cutover = FakeCutoverCtl();
    final gate = Completer<void>();
    final ads = MovaAds(api, cutover: cutover);
    addTearDown(() async {
      if (!gate.isCompleted) gate.complete();
      await ads.dispose();
      await api.dispose();
      await cutover.dispose();
    });
    await ads.load(a);
    cutover.commitResult = true;
    cutover.commitGate = gate;
    api.push(api.state.copyWith(duration: const Duration(seconds: 10)));
    api.pushProgress(const MovaProg(position: Duration(seconds: 9)));
    await settleOperations();
    expect(ads.isAdPending, isTrue);
    api.pushEvent(const MovaDone());
    await settleOperations();
    gate.complete();
    await settleOperations();
    expect(ads.session.cursor.phase, MovaSessionPhase.idle);
    expect(ads.isShowingAd, isFalse);
    expect(api.openedUris, [a.uri]);
  });

  for (final delay in [Duration.zero, const Duration(hours: 1)]) {
    test('pending callback load invalidates ad / 待播回调加载使旧广告失效 '
        'delay=$delay', () async {
      Future<MovaLoadOutcome>? reloading;
      late final MovaAds ads;
      final api = FakeMovaApi(
        options: MovaOpts(
          ads: MovaAdConfig(
            enabled: true,
            breaks: [
              MovaAdBreak(
                kind: MovaAdBreakKind.mid,
                source: mid.source,
                offset: mid.offset,
                delay: delay,
              ),
            ],
            onAdEvent: (event) {
              if (event.type == MovaAdEventType.pending) {
                reloading = ads.session.load(b, breaks: []);
              }
            },
          ),
        ),
      );
      final cutover = FakeCutoverCtl();
      ads = MovaAds(api, cutover: cutover);
      addTearDown(() async {
        await ads.dispose();
        await api.dispose();
        await cutover.dispose();
      });
      await ads.load(a);
      api.pushProgress(const MovaProg(position: Duration(seconds: 2)));
      await settleOperations();
      expect(await reloading, MovaLoadOutcome.accepted);
      expect(cutover.preparedSources, isEmpty);
      expect(api.openedUris, [a.uri, b.uri]);
      expect(ads.session.cursor.phase, MovaSessionPhase.content);
      expect(ads.currentBreak, isNull);
    });
  }

  test(
    'disposed superseded session preserves host warm / 让位后销毁保留宿主预热',
    () async {
      final rig = AdOperationRig();
      addTearDown(rig.dispose);
      await rig.ads.load(a);
      await rig.api.open(b);
      rig.engines.first.pushEvent(const MovaSourceChange(b));
      await settleOperations();
      expect(rig.ads.session.cursor.phase, MovaSessionPhase.idle);
      final ticket = (await rig.api.prepareOwned(
        mid.source,
        plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
      ))!;
      final hostShadow = rig.engines.last;
      await rig.ready(hostShadow);
      await rig.ads.dispose();
      expect(hostShadow.disposeCount, 0);
      expect(await rig.api.commitOwned(ticket), MovaWarmCommit.committed);
      expect(rig.api.active, same(hostShadow));
    },
  );
}
