import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/src/overlay_manager.dart';
import 'package:layerman/src/overlay_types.dart';

/// 重复提交以观察计数的固定身份。
const _id = 'limited';

/// 常驻占位条目的固定身份。
const _resident = 'resident';

/// 单次会话上限。
const _sessionOnce = OverlayCooldown(session: 1);

/// 单次历史上限。
const _totalOnce = OverlayCooldown(total: 1);

/// 时间桶耗尽仍可恢复，不能当作永久受阻。
const _dayBlocked = OverlayCooldown(day: 0);

/// 用于验证队列期限不会覆盖 capped 原因。
const _later = Duration(seconds: 1);

/// 等待测试显式完成读取，不依赖真实时间。
class _Storage implements OverlayCooldownStorage {
  /// 存储读取的可控完成信号。
  final done = Completer<String?>();

  @override
  Future<String?> read(String key) => done.future;

  @override
  Future<void> write(String key, String value) async {}
}

/// 常驻后端，直到测试显式移除才确认关闭。
class _Backend {
  /// 记录真实出场次数。
  int presents = 0;

  /// 后端完成信号。
  final done = Completer<int?>();

  /// 提供可被管理器定向关闭的常驻条目。
  PresentedOverlay<int> present(PresentContext<int> context) {
    presents++;
    return PresentedOverlay<int>(
      dismissed: done.future,
      dismiss: ([result]) async {
        if (!done.isCompleted) done.complete(result);
      },
    );
  }
}

void main() {
  for (final paused in [false, true]) {
    for (final exhausted in [false, true]) {
      testWidgets('session 占位时提交：暂停=$paused 耗尽=$exhausted', (tester) async {
        final manager = Layerman();
        addTearDown(manager.dispose);
        await tester.pump();
        if (exhausted) {
          manager.submit<int>(
              id: _id, cooldown: _sessionOnce, present: _Backend().present);
          manager.remove(_id);
        }
        manager.submit<int>(id: _resident, present: _Backend().present);
        if (paused) manager.pauseAll();
        final backend = _Backend();
        final events = <OverlayEvent>[];
        final subscription = manager.events.listen(events.add);
        addTearDown(subscription.cancel);
        final ticket = manager.submit<int>(
            id: _id,
            cooldown: _sessionOnce,
            expireAfter: _later,
            present: backend.present);
        final values = <int?>[];
        ticket.result.then(values.add);
        expect(manager.queuedIds.contains(_id), !exhausted);
        expect(ticket.isActive, !exhausted);
        await tester.pump();
        expect(values, exhausted ? <int?>[null] : <int?>[]);
        expect(backend.presents, 0);
        expect(manager.activeIds, contains(_resident));
        if (exhausted) {
          expect((await ticket.outcome).reason, OverlayEndReason.capped);
          expect(events.where((e) => e.id == _id).map((e) => e.type),
              [OverlayEventType.queued, OverlayEventType.ended]);
          expect(events.last.reason, OverlayEndReason.capped);
          await tester.pump(_later);
          expect(events.where((e) => e.id == _id).length, 2);
        } else {
          if (paused) manager.resumeAll();
          manager.remove(_resident);
          expect(backend.presents, 1);
        }
      });
    }
  }
  for (final paused in [false, true]) {
    for (final exhausted in [false, true]) {
      testWidgets('慢 hydrate 扫描所有占用槽：暂停=$paused total耗尽=$exhausted',
          (tester) async {
        final storage = _Storage();
        final manager = Layerman(cooldownStorage: storage);
        addTearDown(manager.dispose);
        final tickets = <OverlayTicket<int>>[];
        final backends = <_Backend>[];
        var completed = 0;
        for (final slot in ['', 'other']) {
          manager.submit<int>(
              id: '$_resident$slot', slot: slot, present: _Backend().present);
          final backend = _Backend();
          backends.add(backend);
          final ticket = manager.submit<int>(
              id: '$_id$slot',
              slot: slot,
              cooldown: _totalOnce,
              expireAfter: _later,
              present: backend.present);
          tickets.add(ticket);
          ticket.result.then((value) {
            completed++;
          });
        }
        if (paused) manager.pauseAll();
        await tester.pump();
        expect(manager.queuedIds.length, 2);
        expect(completed, 0);
        storage.done.complete(exhausted
            ? '{"limited":{"t":1},"limitedother":{"t":1}}'
            : '{"limited":{"t":0},"limitedother":{"t":0}}');
        await tester.pump();
        expect(completed, exhausted ? 2 : 0);
        expect(manager.queuedIds.length, exhausted ? 0 : 2);
        expect(backends.map((b) => b.presents), [0, 0]);
        expect(manager.isPaused, paused);
        expect(manager.activeIds.length, 2);
        if (exhausted) {
          for (final ticket in tickets) {
            expect(ticket.isActive, isFalse);
            expect(await ticket.result, isNull);
            expect((await ticket.outcome).reason, OverlayEndReason.capped);
          }
          await tester.pump(_later);
          expect(completed, 2);
        } else {
          if (paused) manager.resumeAll();
          for (final slot in ['', 'other']) {
            manager.remove('$_resident$slot');
          }
          expect(backends.map((b) => b.presents), [1, 1]);
        }
      });
    }
  }
  testWidgets('hydrate 发现时间桶耗尽仍保留等待条目', (tester) async {
    final storage = _Storage();
    final manager = Layerman(cooldownStorage: storage);
    addTearDown(manager.dispose);
    manager.submit<int>(id: _resident, present: _Backend().present);
    final backend = _Backend();
    final ticket = manager.submit<int>(
        id: _id, cooldown: _dayBlocked, present: backend.present);
    var completed = false;
    ticket.result.then((_) => completed = true);
    storage.done.complete(null);
    await tester.pump();
    expect(manager.queuedIds, contains(_id));
    expect(completed, isFalse);
    expect(backend.presents, 0);
    expect(
        manager.cooldownStatus(_id, _dayBlocked).permanentlyBlocked, isFalse);
  });
}
