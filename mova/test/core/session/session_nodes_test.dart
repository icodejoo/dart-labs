import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/session/timeline.dart'
    show movaBuildNodes, movaDueMid;

import '../../support/fake_api.dart';
import '../cutover/cutover_operation_test.dart' show settleOperations;
import 'session_test.dart' show a, b, pre, sessionFor, done;

/// 无需预热的中插，便于单独观察节点身份。
const instant = MovaAdBreak(
  kind: MovaAdBreakKind.mid,
  source: MovaSource('https://host/node-ad.mp4'),
  waitForReady: false,
);

void main() {
  test('pod 里两条 const 同参数广告各播一次', () async {
    final hook = <MovaAdEvent>[];
    final api = FakeMovaApi(
      options: MovaOpts(
        ads: MovaAdOpts(
          enabled: true,
          breaks: const [instant, instant],
          onAdEvent: hook.add,
        ),
      ),
    );
    final session = sessionFor(api);
    final events = <MovaSessionEvent>[];
    session.events.listen(events.add);
    await session.load(a);
    api.pushProgress(const MovaProg(position: Duration(seconds: 1)));
    await settleOperations();
    await done(api);
    await done(api);
    final starts = events.whereType<MovaNodeStart>().where(
      (e) => e.node.kind == MovaNodeKind.mid,
    );
    final ends = events.whereType<MovaNodeEnd>().where(
      (e) => e.node.kind == MovaNodeKind.mid,
    );
    expect(starts.map((e) => e.node.ordinal), [0, 1]);
    expect(ends.map((e) => e.node.ordinal), [0, 1]);
    expect(ends.every((e) => e.reason == MovaNodeEndReason.completed), isTrue);
    expect(hook.where((e) => e.type == MovaAdEventType.started), hasLength(2));
    expect(hook.every((e) => identical(e.adBreak, instant)), isTrue);
  });

  test('同实例两条：第一条计时器不会结算第二条', () {
    fakeAsync((clock) {
      const ad = MovaAdBreak(
        kind: MovaAdBreakKind.pre,
        source: a,
        duration: Duration(seconds: 10),
      );
      final api = FakeMovaApi(
        options: const MovaOpts(
          ads: MovaAdOpts(
            enabled: true,
            breaks: [ad, ad],
            durationFromFirstFrame: false,
          ),
        ),
      );
      final session = MovaSession(api)
        ..debugClock = () => DateTime.utc(2026).add(clock.elapsed);
      final events = <MovaSessionEvent>[];
      final endTimes = <Duration>[];
      session.events.listen((event) {
        events.add(event);
        if (event is MovaNodeEnd) endTimes.add(clock.elapsed);
      });
      unawaited(session.load(b));
      clock.flushMicrotasks();
      api.pushEvent(
        const MovaFirstFrame(
          sinceOpen: Duration.zero,
          signal: MovaFirstFrameSignal.restart,
        ),
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 5));
      api.pushEvent(const MovaDone());
      clock.flushMicrotasks();
      api.pushEvent(
        const MovaFirstFrame(
          sinceOpen: Duration.zero,
          signal: MovaFirstFrameSignal.restart,
        ),
      );
      clock.flushMicrotasks();
      expect(session.cursor.node, const MovaNodeId(0, MovaNodeKind.pre, 1));
      clock.elapse(const Duration(seconds: 5));
      expect(session.isShowingAd, isTrue);
      expect(events.whereType<MovaNodeEnd>(), hasLength(1));
      clock.elapse(const Duration(seconds: 4, milliseconds: 999));
      expect(events.whereType<MovaNodeEnd>(), hasLength(1));
      clock.elapse(const Duration(milliseconds: 1));
      expect(endTimes, [
        const Duration(seconds: 5),
        const Duration(seconds: 15),
      ]);
      expect(
        events.whereType<MovaNodeEnd>().every(
          (event) => event.reason == MovaNodeEndReason.completed,
        ),
        isTrue,
      );
      expect(events.whereType<MovaNodeEnd>().map((e) => e.node.ordinal), [
        0,
        1,
      ]);
      unawaited(session.dispose());
      clock.flushMicrotasks();
      unawaited(api.dispose());
      clock.flushMicrotasks();
    });
  });

  test('节点序号按排期原顺序，并按完整身份比较及查找中插', () {
    const later = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: a,
      offset: Duration(seconds: 20),
    );
    final nodes = movaBuildNodes(2, [later, pre, instant, pre]);
    expect(nodes.map((n) => n.id), const [
      MovaNodeId(2, MovaNodeKind.mid, 0),
      MovaNodeId(2, MovaNodeKind.pre, 0),
      MovaNodeId(2, MovaNodeKind.mid, 1),
      MovaNodeId(2, MovaNodeKind.pre, 1),
      MovaNodeId(2, MovaNodeKind.content, 0),
    ]);
    final played = {const MovaNodeId(2, MovaNodeKind.mid, 1)};
    expect(movaDueMid(nodes, const Duration(seconds: 1), played), isNull);
    expect(
      movaDueMid(nodes, const Duration(seconds: 20), played),
      same(nodes.first),
    );
    expect(played.contains(const MovaNodeId(2, MovaNodeKind.mid, 1)), isTrue);
    expect(played.contains(const MovaNodeId(1, MovaNodeKind.mid, 1)), isFalse);
    expect(played.contains(const MovaNodeId(2, MovaNodeKind.pre, 1)), isFalse);
    expect(played.contains(const MovaNodeId(2, MovaNodeKind.mid, 0)), isFalse);
  });

  test('插播负序号递减且不占排期序号', () async {
    final api = FakeMovaApi();
    final session = sessionFor(api);
    final events = <MovaSessionEvent>[];
    session.events.listen(events.add);
    await session.load(a);
    await session.playAdNow(instant);
    await done(api);
    await session.playAdNow(instant);
    await done(api);
    expect(
      events
          .whereType<MovaNodeStart>()
          .where((e) => e.node.kind == MovaNodeKind.mid)
          .map((e) => e.node.ordinal),
      [-1, -2],
    );
    await session.load(b);
    await session.playAdNow(instant);
    expect(session.cursor.node?.ordinal, -1);
  });

  test('换集结束旧节点携带旧纪元，此后只出现新纪元', () async {
    final api = FakeMovaApi(
      options: const MovaOpts(ads: MovaAdOpts(enabled: true)),
    );
    final session = sessionFor(
      api,
      items: const [
        MovaPlaylistItem(source: a, adBreaks: [pre]),
        MovaPlaylistItem(source: b, adBreaks: []),
      ],
    );
    final events = <MovaSessionEvent>[];
    session.events.listen(events.add);
    await session.jumpTo(0);
    final oldEpoch = session.cursor.epoch;
    await session.jumpTo(1);
    await settleOperations();
    final superseded = events.whereType<MovaNodeEnd>().single;
    expect(superseded.epoch, oldEpoch);
    expect(superseded.reason, MovaNodeEndReason.superseded);
    final tail = events.skipWhile((e) => !identical(e, superseded)).skip(1);
    expect(tail, isNotEmpty);
    expect(tail.every((e) => e.epoch == session.cursor.epoch), isTrue);
    expect(events.whereType<MovaItemChange>().last.index, 1);
    expect(events.whereType<MovaNodeStart>().last.node.item, 1);
  });

  test('正片开始结束各一次，重复 Done 不补发', () async {
    final api = FakeMovaApi();
    final session = sessionFor(api);
    final events = <MovaSessionEvent>[];
    session.events.listen(events.add);
    await session.load(a);
    await done(api);
    await done(api);
    expect(events.whereType<MovaNodeStart>(), hasLength(1));
    expect(events.whereType<MovaNodeEnd>(), hasLength(1));
    expect(
      events.whereType<MovaNodeEnd>().single.reason,
      MovaNodeEndReason.completed,
    );
    expect(session.cursor.node, isNull);
  });

  test('跳过发 skipped 且重复 skip 不重复结算', () async {
    const ad = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: b,
      skippableAfter: Duration.zero,
    );
    final api = FakeMovaApi(
      options: const MovaOpts(ads: MovaAdOpts(enabled: true, breaks: [ad])),
    );
    final session = sessionFor(api);
    final events = <MovaSessionEvent>[];
    session.events.listen(events.add);
    await session.load(a);
    session.skip();
    session.skip();
    await settleOperations();
    expect(events.whereType<MovaNodeEnd>(), hasLength(1));
    expect(
      events.whereType<MovaNodeEnd>().single.reason,
      MovaNodeEndReason.skipped,
    );

    // 钩子同步重载同一节点，旧 skip 的尾部不得续播新尝试。
    late final MovaSession reentrant;
    final reentrantApi = FakeMovaApi(
      options: MovaOpts(
        ads: MovaAdOpts(
          enabled: true,
          breaks: const [ad],
          onAdEvent: (event) {
            if (event.type == MovaAdEventType.skipped) {
              unawaited(reentrant.load(a));
            }
          },
        ),
      ),
    );
    reentrant = sessionFor(reentrantApi);
    await reentrant.load(a);
    final oldEpoch = reentrant.cursor.epoch;
    reentrant.skip();
    await settleOperations();
    expect(reentrant.cursor.epoch, oldEpoch + 1);
    expect(reentrant.isShowingAd, isTrue);
    expect(reentrant.currentBreak, same(ad));
    expect(reentrantApi.source, ad.source);
  });

  test('游标节点随 content pending ad 更新', () {
    fakeAsync((clock) {
      const ad = MovaAdBreak(
        kind: MovaAdBreakKind.mid,
        source: b,
        delay: Duration(seconds: 1),
        waitForReady: false,
      );
      final api = FakeMovaApi(
        options: const MovaOpts(ads: MovaAdOpts(enabled: true, breaks: [ad])),
      );
      final session = MovaSession(api)
        ..debugClock = () => DateTime.utc(2026).add(clock.elapsed);
      unawaited(session.load(a));
      clock.flushMicrotasks();
      expect(session.cursor.node, const MovaNodeId(0, MovaNodeKind.content, 0));
      api.pushProgress(const MovaProg(position: Duration(seconds: 2)));
      clock.flushMicrotasks();
      expect(session.cursor.phase, MovaSessionPhase.pending);
      expect(session.cursor.node, const MovaNodeId(0, MovaNodeKind.mid, 0));
      clock.elapse(const Duration(seconds: 1));
      expect(session.cursor.phase, MovaSessionPhase.ad);
      expect(session.cursor.node, const MovaNodeId(0, MovaNodeKind.mid, 0));
      api.pushEvent(const MovaDone());
      clock.flushMicrotasks();
      expect(session.cursor.phase, MovaSessionPhase.content);
      expect(session.cursor.node?.kind, MovaNodeKind.content);
      unawaited(session.dispose());
      clock.flushMicrotasks();
      unawaited(api.dispose());
      clock.flushMicrotasks();
    });
  });
}
