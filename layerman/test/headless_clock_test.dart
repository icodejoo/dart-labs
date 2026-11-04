import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';
import 'package:layerman/testing.dart';

const _second = Duration(seconds: 1);
const _half = Duration(milliseconds: 500);

/// 排空引擎依赖的异步续体，不创建 Flutter 绑定。
Future<void> _flush() => Future<void>.delayed(Duration.zero);

/// 无界面的可控后端，显式确认 dismissed。
class _Backend<T> {
  /// 后端结束信号。
  final done = Completer<T?>();

  /// 展示时绑定的类型化上下文。
  PresentContext<T>? context;

  /// 记录是否已出场。
  bool get shown => context != null;

  /// 模拟展示与定向关闭。
  PresentedOverlay<T> present(PresentContext<T> ctx) {
    context = ctx;
    return PresentedOverlay<T>(
        dismissed: done.future,
        dismiss: ([result]) async {
          if (!done.isCompleted) done.complete(result);
        });
  }
}

void main() {
  test('duration 到期自动关闭，未到期保持展示', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    final backend = _Backend<int>();
    final ticket = manager.submit(present: backend.present, duration: _second);
    clock.advance(_half);
    expect(manager.activeIds, [ticket.id]);
    clock.advance(_half);
    expect((await ticket.outcome).reason, OverlayEndReason.expired);
    await _flush();
    expect(manager.activeIds, isEmpty);
    expect(clock.pendingTimers, 0);
  });

  test('gap 满足前不推进，满足后推进队列', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock, gap: _second);
    addTearDown(manager.dispose);
    final a = manager.submit(present: _Backend<void>().present);
    final b = _Backend<void>();
    manager.open(present: b.present);
    a.close();
    await _flush();
    clock.advance(_half);
    expect(b.shown, isFalse);
    clock.advance(_half);
    expect(b.shown, isTrue);
    manager.dispose();
    expect(clock.pendingTimers, 0);
  });

  test('minGap 自唤醒，未到期仍在排队', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    await manager.ready();
    const cooldown = OverlayCooldown(minGap: _second);
    final first = manager.submit(
        id: 'cap', present: _Backend<void>().present, cooldown: cooldown);
    first.remove();
    final backend = _Backend<void>();
    manager.open(id: 'cap', present: backend.present, cooldown: cooldown);
    clock.advance(_second);
    expect(backend.shown, isFalse);
    clock.advance(const Duration(milliseconds: 16));
    expect(backend.shown, isTrue);
    expect(clock.pendingTimers, 0);
  });

  test('暂停冻结剩余 duration，恢复后只等待剩余时长', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    final ticket =
        manager.submit(present: _Backend<void>().present, duration: _second);
    clock.advance(_half);
    manager.pauseAll();
    expect(clock.pendingTimers, 0);
    clock.advance(const Duration(hours: 1));
    expect(manager.activeIds, [ticket.id]);
    manager.resumeAll();
    clock.advance(const Duration(milliseconds: 499));
    expect(manager.activeIds, [ticket.id]);
    clock.advance(const Duration(milliseconds: 1));
    expect((await ticket.outcome).reason, OverlayEndReason.expired);
    await _flush();
    expect(clock.pendingTimers, 0);
  });

  test('expireAfter 仅作用串行排队，不影响已出场条目', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    final active =
        manager.submit(present: _Backend<void>().present, expireAfter: _half);
    final backend = _Backend<void>();
    final queued =
        manager.submit(present: backend.present, expireAfter: _second);
    clock.advance(_second);
    expect((await queued.outcome).reason, OverlayEndReason.queueExpired);
    expect(backend.shown, isFalse);
    expect(manager.activeIds, [active.id]);
    expect(clock.pendingTimers, 0);
  });

  test('overlap delay 到点才判条件，expireAfter 不影响等待', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    final backend = _Backend<void>();
    manager.setContext({'ready': false});
    final ticket = manager.submit(
        present: backend.present,
        mode: OverlayMode.overlap,
        delay: _second,
        expireAfter: _half,
        when: (ctx) => ctx['ready'] == true);
    expect(manager.recordOf(ticket.id)!.phase, OverlayPhase.pending);
    expect(manager.queuedIds, [ticket.id]);
    expect(manager.records.single.active, isFalse);
    ticket.close();
    clock.advance(_half);
    expect(backend.shown, isFalse);
    manager.setContext({'ready': true});
    clock.advance(_half);
    expect(backend.shown, isTrue);
    expect(clock.pendingTimers, 0);
  });

  test('假时钟按时间和创建顺序触发，窗口内新计时器也触发', () {
    final clock = FakeOverlayClock();
    final order = <int>[];
    final timer = clock.createTimer(_half, () {
      order.add(1);
      clock.createTimer(_half, () => order.add(3));
    });
    clock.createTimer(_second, () => order.add(2));
    expect(timer.tick, 0);
    clock.advance(_second);
    expect(order, [1, 2, 3]);
    expect(timer.tick, 1);
    expect(timer.isActive, isFalse);
    expect(clock.now(), DateTime(2000).add(_second));
    expect(clock.pendingTimers, 0);
  });

  test('假时钟取消幂等、负时长拒绝、零与负计时器立即到期', () {
    final clock = FakeOverlayClock();
    var calls = 0;
    final timer = clock.createTimer(_second, () => calls++);
    timer.cancel();
    timer.cancel();
    expect(timer.tick, 0);
    expect(timer.isActive, isFalse);
    expect(() => clock.advance(-_second), throwsArgumentError);
    clock.createTimer(-_second, () => calls++);
    clock.advance(Duration.zero);
    expect(calls, 1);
    expect(clock.pendingTimers, 0);
  });
}
