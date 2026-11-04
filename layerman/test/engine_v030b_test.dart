import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/src/overlay_manager.dart';
import 'package:layerman/src/overlay_types.dart';

/// 可手动关闭、类型化并记录展示次数的假后端。
class _FakeBackend<T> {
  /// 后端关闭信号。
  final done = Completer<T?>();

  /// 实际展示次数。
  int shown = 0;

  /// 获准展示时提供定向关闭函数。
  PresentedOverlay<T> present(PresentContext context) {
    shown++;
    return PresentedOverlay<T>(
      dismissed: done.future,
      dismiss: ([T? value]) async => finish(value),
    );
  }

  /// 模拟后端主动关闭。
  void finish([T? value]) {
    if (!done.isCompleted) done.complete(value);
  }
}

/// 测试复用的短时限。
const _tick = Duration(milliseconds: 20);

/// 测试复用的长时限。
const _long = Duration(seconds: 1);

/// 测试复用的条目标识。
const _id = 'entry';

/// 测试复用的槽位或路由名称。
const _zone = 'zone';

/// 断言首次结果原因及值，并同时检查旧 Future 的值。
Future<void> _expectOutcome<T>(OverlayTicket<T> ticket, OverlayEndReason reason,
    [T? value]) async {
  final outcome = await ticket.outcome;
  expect(outcome.reason, reason);
  expect(outcome.value, value);
  expect(await ticket.result, value);
}

/// 覆盖新增 API 与现有引擎生命周期的组合边界。
void main() {
  testWidgets('类型化关闭携带结果，后端回调不覆盖首次原因', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final ticket = manager.submit<bool>(present: _FakeBackend<bool>().present);
    expect(ticket.isActive, isTrue);
    ticket.close(true);
    await tester.pump();
    await _expectOutcome(ticket, OverlayEndReason.closed, true);
    expect(ticket.isActive, isFalse);
  });

  testWidgets('后端主动关闭携带结果', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final backend = _FakeBackend<bool>();
    final ticket = manager.submit<bool>(present: backend.present);
    backend.finish(false);
    await tester.pump();
    await _expectOutcome(ticket, OverlayEndReason.dismissedByBackend, false);
  });

  testWidgets('自动到期绕过关闭守卫', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final ticket = manager.submit<bool>(
      present: _FakeBackend<bool>().present,
      duration: _tick,
      beforeClose: () => false,
    );
    ticket.close(true);
    expect(ticket.isActive, isTrue);
    await tester.pump(_tick);
    await _expectOutcome(ticket, OverlayEndReason.expired);
  });

  testWidgets('replace 抢占结束旧条目，affix 阻止抢占', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final first = manager.submit(present: _FakeBackend().present);
    final second = manager.submit(
        present: _FakeBackend().present, replace: true, affix: true);
    await _expectOutcome(first, OverlayEndReason.replaced);
    final third =
        manager.submit(present: _FakeBackend().present, replace: true);
    expect(second.isActive, isTrue);
    expect(manager.queuedIds, contains(third.id));
  });

  for (final queued in [false, true]) {
    testWidgets('同 id ${queued ? "排队" : "展示"}重开后旧票操作静默失效', (tester) async {
      final manager = Layerman();
      addTearDown(manager.dispose);
      if (queued) manager.pauseAll();
      final old = manager.submit(present: _FakeBackend().present, id: _id);
      final next =
          manager.submit(present: _FakeBackend().present, id: _id, data: 1);
      await _expectOutcome(old, OverlayEndReason.superseded);
      old.close();
      old.remove();
      old.update(2);
      expect(old.isActive, isFalse);
      expect(next.isActive, isTrue);
      expect(next.data.value, 1);
      next.update(3);
      expect(next.data.value, 3);
      next.remove();
      expect(next.isActive, isFalse);
      await _expectOutcome(next, OverlayEndReason.removed);
    });
  }

  for (final operation in ['remove', 'clear', 'clearWhere']) {
    testWidgets('$operation 移除排队条目并取消过期计时器', (tester) async {
      final manager = Layerman();
      addTearDown(manager.dispose);
      manager.pauseAll();
      final ticket =
          manager.submit(present: _FakeBackend().present, expireAfter: _long);
      switch (operation) {
        case 'remove':
          ticket.remove();
        case 'clear':
          manager.clear();
        case 'clearWhere':
          manager.clearWhere((_) => true);
      }
      await _expectOutcome(ticket, OverlayEndReason.removed);
      await tester.pump(_long);
      expect(ticket.isActive, isFalse);
    });
  }

  testWidgets('条件失效以 unmet 结束，禁用自动关闭则保留', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    manager.setContext({'auth': true});
    final first =
        manager.submit(present: _FakeBackend().present, requiresAuth: true);
    final kept = manager.submit(
        present: _FakeBackend().present,
        overlap: true,
        requiresAuth: true,
        dismissWhenUnmet: false);
    manager.setContext({'auth': false});
    await _expectOutcome(first, OverlayEndReason.unmet);
    expect(kept.isActive, isTrue);
  });

  for (final throws in [false, true]) {
    testWidgets('resolve ${throws ? "异常" : "空值"}以 skipped 结束', (tester) async {
      final manager = Layerman();
      addTearDown(manager.dispose);
      final backend = _FakeBackend<bool>();
      final ticket = manager.submit<bool>(
          present: backend.present,
          resolve: () async {
            if (throws) throw StateError(_id);
            return null;
          });
      await tester.pump();
      await _expectOutcome(ticket, OverlayEndReason.skipped);
      expect(backend.shown, 0);
    });
  }

  testWidgets('resolve 超时以 skipped 结束且晚到结果不展示', (tester) async {
    final manager = Layerman(resolveTimeout: _tick);
    addTearDown(manager.dispose);
    final resolver = Completer<bool?>();
    final backend = _FakeBackend<bool>();
    final ticket = manager.submit<bool>(
        present: backend.present, resolve: () => resolver.future);
    await tester.pump(_tick);
    expect(tester.takeException(), isA<TimeoutException>());
    await _expectOutcome(ticket, OverlayEndReason.skipped);
    resolver.complete(true);
    await tester.pump();
    expect(backend.shown, 0);
  });

  testWidgets('overlap 条件不满足丢弃，串行条目保留等待', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final dropped = manager.submit(
        present: _FakeBackend().present, overlap: true, when: (_) => false);
    await _expectOutcome(dropped, OverlayEndReason.dropped);
    final waiting =
        manager.submit(present: _FakeBackend().present, when: (_) => false);
    expect(waiting.isActive, isTrue);
  });

  for (final overlap in [false, true]) {
    testWidgets('永久上限以 capped 结束，overlap=$overlap', (tester) async {
      final manager = Layerman();
      addTearDown(manager.dispose);
      final ticket = manager.submit(
          present: _FakeBackend().present,
          id: _id,
          cooldown: const OverlayCooldown(session: 0),
          overlap: overlap);
      await _expectOutcome(ticket, OverlayEndReason.capped);
    });
  }

  testWidgets('present 异常以 failed 结束并让出槽位', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final ticket = manager.submit(present: (_) => throw StateError(_id));
    expect(tester.takeException(), isStateError);
    await _expectOutcome(ticket, OverlayEndReason.failed);
    final backend = _FakeBackend();
    manager.submit(present: backend.present);
    expect(backend.shown, 1);
  });

  testWidgets('dispose 结束所有条目且取消计时器，hold 随销毁释放', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final hold = manager.hold();
    final ticket =
        manager.submit(present: _FakeBackend().present, expireAfter: _long);
    manager.dispose();
    await _expectOutcome(ticket, OverlayEndReason.disposed);
    expect(ticket.isActive, isFalse);
    expect(hold.isReleased, isTrue);
    hold.release();
    expect(manager.holdCount, 0);
    expect(manager.hold().isReleased, isTrue);
    expect(() => manager.submit(present: _FakeBackend().present),
        throwsAssertionError);
    expect(() => manager.open(present: _FakeBackend().present),
        throwsAssertionError);
  });

  testWidgets('open 与 submit 的结果一致', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final result =
        manager.open<bool>(present: _FakeBackend<bool>().present, id: _id);
    manager.close(_id, true);
    await tester.pump();
    final ticket = manager.submit<bool>(present: _FakeBackend<bool>().present);
    ticket.close(true);
    expect(await result, await ticket.result);
  });

  for (final overlap in [false, true]) {
    testWidgets('事件顺序为入队、展示、结束，overlap=$overlap', (tester) async {
      final manager = Layerman();
      addTearDown(manager.dispose);
      final events = <OverlayEvent>[];
      var closed = false;
      manager.events.listen(events.add, onDone: () => closed = true);
      final ticket =
          manager.submit(present: _FakeBackend().present, overlap: overlap);
      ticket.close();
      await tester.pump();
      expect(events.map((e) => e.type), [
        OverlayEventType.queued,
        OverlayEventType.shown,
        OverlayEventType.ended
      ]);
      expect(events.map((e) => e.id), everyElement(ticket.id));
      expect(events.map((e) => e.slot), everyElement(ticket.slot));
      expect(events.take(2).map((e) => e.reason), everyElement(isNull));
      expect(events.last.reason, OverlayEndReason.closed);
      manager.dispose();
      await tester.pump();
      expect(closed, isTrue);
    });
  }

  testWidgets('被 replace 和同 id 重开顶掉的条目各有一次 ended', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final events = <OverlayEvent>[];
    manager.events.listen(events.add);
    manager.submit(present: _FakeBackend().present);
    manager.submit(present: _FakeBackend().present, id: _id, replace: true);
    manager.submit(present: _FakeBackend().present, id: _id);
    await tester.pump();
    expect(
        events
            .where((e) => e.type == OverlayEventType.ended)
            .map((e) => e.reason),
        [OverlayEndReason.replaced, OverlayEndReason.superseded]);
  });

  testWidgets('多个 hold 与手动、路由暂停按 OR 组合，释放幂等', (tester) async {
    final manager = Layerman(pauseOnRoutes: const [_zone]);
    addTearDown(manager.dispose);
    final first = manager.hold(_id);
    final second = manager.hold();
    expect(first.reason, _id);
    expect(manager.holdCount, 2);
    manager.pauseAll();
    manager.setContext({'route': _zone});
    final backend = _FakeBackend();
    manager.submit(present: backend.present);
    first.release();
    first.release();
    expect(manager.holdCount, 1);
    second.release();
    expect(manager.isPaused, isTrue);
    manager.resumeAll();
    expect(manager.isPaused, isTrue);
    manager.setContext({'route': null});
    expect(manager.isPaused, isFalse);
    expect(backend.shown, 1);
  });

  testWidgets('hold 全释放才恢复，时长按剩余时间继续', (tester) async {
    final manager = Layerman(now: () => tester.binding.clock.now());
    addTearDown(manager.dispose);
    final ticket =
        manager.submit(present: _FakeBackend().present, duration: _long);
    await tester.pump(_tick);
    final first = manager.hold();
    final second = manager.hold();
    await tester.pump(_long);
    first.release();
    expect(manager.isPaused, isTrue);
    second.release();
    expect(manager.isPaused, isFalse);
    await tester.pump(_long - _tick);
    await _expectOutcome(ticket, OverlayEndReason.expired);
  });

  testWidgets('排队到期在暂停期间仍然计时', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    manager.hold();
    final ticket =
        manager.submit(present: _FakeBackend().present, expireAfter: _tick);
    await tester.pump(_tick);
    await _expectOutcome(ticket, OverlayEndReason.queueExpired);
    expect(ticket.isActive, isFalse);
  });

  testWidgets('排队到期释放等待位置，不影响活动条目', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final active = manager.submit(present: _FakeBackend().present);
    final queued =
        manager.submit(present: _FakeBackend().present, expireAfter: _tick);
    await tester.pump(_tick);
    await _expectOutcome(queued, OverlayEndReason.queueExpired);
    expect(active.isActive, isTrue);
  });

  testWidgets('激活取消排队期限，overlap 不应用期限', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    manager.pauseAll();
    final backend = _FakeBackend();
    final ticket = manager.submit(present: backend.present, expireAfter: _tick);
    final overlap = manager.submit(
        present: _FakeBackend().present, overlap: true, expireAfter: _tick);
    manager.resumeAll();
    await tester.pump(_long);
    expect(backend.shown, 1);
    expect(ticket.isActive, isTrue);
    expect(overlap.isActive, isTrue);
  });

  testWidgets('每槽位 gap 覆盖全局 gap，其他槽位沿用全局', (tester) async {
    final manager = Layerman(gap: _long, slots: const {
      _zone: OverlaySlotOptions(gap: _tick),
    });
    addTearDown(manager.dispose);
    final first = manager.submit(present: _FakeBackend().present, slot: _zone);
    final global = manager.submit(present: _FakeBackend().present);
    final localNext = _FakeBackend();
    final globalNext = _FakeBackend();
    manager.submit(present: localNext.present, slot: _zone);
    manager.submit(present: globalNext.present);
    first.close();
    global.close();
    await tester.pump();
    await tester.pump(_tick);
    expect(localNext.shown, 1);
    expect(globalNext.shown, 0);
    await tester.pump(_long);
    expect(globalNext.shown, 1);
  });

  for (final priority in [-1, 1]) {
    testWidgets('排队上限挤掉队尾，新增优先级=$priority', (tester) async {
      final manager = Layerman(slots: const {
        '': OverlaySlotOptions(maxQueued: 1),
      });
      addTearDown(manager.dispose);
      manager.submit(present: _FakeBackend().present);
      final old =
          manager.submit(present: _FakeBackend().present, expireAfter: _long);
      final next = manager.submit(
          present: _FakeBackend().present,
          priority: priority,
          expireAfter: _long);
      final dropped = priority > 0 ? old : next;
      final kept = priority > 0 ? next : old;
      await _expectOutcome(dropped, OverlayEndReason.queueFull);
      expect(kept.isActive, isTrue);
      expect(manager.queuedIds, [kept.id]);
      manager.dispose();
    });
  }

  testWidgets('replace 在队首，不因低优先级被先挤掉', (tester) async {
    final manager = Layerman(slots: const {
      '': OverlaySlotOptions(maxQueued: 1),
    });
    addTearDown(manager.dispose);
    manager.submit(present: _FakeBackend().present, affix: true);
    final old = manager.submit(present: _FakeBackend().present, priority: 100);
    final replacer = manager.submit(
        present: _FakeBackend().present, priority: -100, replace: true);
    await _expectOutcome(old, OverlayEndReason.queueFull);
    expect(manager.queuedIds, [replacer.id]);
  });

  test('排队上限必须为正，未配置或正数允许构造', () {
    for (final max in [0, -1]) {
      expect(
          () => Layerman(slots: {
                '': OverlaySlotOptions(maxQueued: max),
              }),
          throwsAssertionError);
    }
    final manager = Layerman(slots: const {
      '': OverlaySlotOptions(maxQueued: 1),
      _zone: OverlaySlotOptions(),
    });
    addTearDown(manager.dispose);
  });

  testWidgets('无事件监听者时正常展示和结束，销毁后流立即结束', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final ticket = manager.submit(present: _FakeBackend().present);
    ticket.close();
    await tester.pump();
    await _expectOutcome(ticket, OverlayEndReason.closed);
    manager.dispose();
    expect(await manager.events.toList(), isEmpty);
    ticket.close();
    ticket.remove();
    ticket.update(1);
  });

  testWidgets('total 上限等待 hydrate 后以 capped 结束', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final ticket = manager.submit(
        present: _FakeBackend().present,
        id: _id,
        cooldown: const OverlayCooldown(total: 0),
        expireAfter: _long);
    await tester.pump();
    await _expectOutcome(ticket, OverlayEndReason.capped);
  });

  testWidgets('被暂停的 overlap 恢复时重新检查条件并报告 dropped', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    manager.pauseAll();
    var eligible = true;
    final backend = _FakeBackend();
    final ticket = manager.submit(
        present: backend.present, overlap: true, when: (_) => eligible);
    eligible = false;
    manager.resumeAll();
    await _expectOutcome(ticket, OverlayEndReason.dropped);
    expect(backend.shown, 0);
  });

  testWidgets('排队事件早于展示，dispose 发布唯一 ended 后关闭流', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    manager.pauseAll();
    final events = <OverlayEvent>[];
    var closed = false;
    manager.events.listen(events.add, onDone: () => closed = true);
    final ticket = manager.submit(present: _FakeBackend().present);
    await tester.pump();
    expect(events.map((e) => e.type), [OverlayEventType.queued]);
    manager.resumeAll();
    await tester.pump();
    expect(events.last.type, OverlayEventType.shown);
    manager.dispose();
    await tester.pump();
    await _expectOutcome(ticket, OverlayEndReason.disposed);
    expect(events.where((e) => e.type == OverlayEventType.ended).length, 1);
    expect(events.last.reason, OverlayEndReason.disposed);
    expect(closed, isTrue);
  });

  testWidgets('排队期限在进入 resolving 时取消，不会打断解析', (tester) async {
    final manager = Layerman(resolveTimeout: null);
    addTearDown(manager.dispose);
    manager.pauseAll();
    final resolver = Completer<bool?>();
    final ticket = manager.submit<bool>(
        present: _FakeBackend<bool>().present,
        expireAfter: _long,
        resolve: () => resolver.future);
    manager.resumeAll();
    expect(manager.resolvingIds, [ticket.id]);
    // 不推进时间且保留解析，测试框架会发现未取消的排队 Timer。
  });

  testWidgets('未配置上限允许持续排队，零 gap 覆盖全局等待', (tester) async {
    final manager = Layerman(gap: _long, slots: const {
      _zone: OverlaySlotOptions(gap: Duration.zero),
    });
    addTearDown(manager.dispose);
    final first = manager.submit(present: _FakeBackend().present, slot: _zone);
    final second = _FakeBackend();
    manager.submit(present: second.present, slot: _zone);
    manager.submit(present: _FakeBackend().present, slot: _zone);
    expect(manager.queuedIds.length, 2);
    first.close();
    await tester.pump();
    expect(second.shown, 1);
    manager.dispose();
  });
}
