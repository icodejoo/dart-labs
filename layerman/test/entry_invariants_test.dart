import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';
import 'package:layerman/testing.dart';

import 'support/headless_backend.dart';

/// 可暂停和推进的完整展示时长。
const _duration = Duration(seconds: 2);

/// 已消耗或待退场的半秒时间片。
const _slice = Duration(milliseconds: 500);

/// 收到关闭请求后仍等待显式退场确认的后端。
class _SlowBackend {
  /// 后端实际退场信号。
  final done = Completer<int?>();

  /// 仅返回句柄，不在 dismiss 时自动确认退场。
  PresentedOverlay<int> present(PresentContext<int> ctx) => PresentedOverlay(
        visible: Future<void>.value(),
        dismissed: done.future,
        dismiss: ([_]) async {},
      );
}

/// 验证非法状态可检测，以及异步关闭和暂停交错的合法边界。
void main() {
  for (final entry in {
    'n': 'externalDone',
    'o': 'hasHeldData',
    'p': 'durationRemaining',
    'q': '已结束',
  }.entries) {
    test('反向不变量 ${entry.key}：${entry.value} 非法状态被自动和显式检查捕获', () async {
      final manager = Layerman(clock: FakeOverlayClock());
      addTearDown(manager.dispose);
      await manager.ready();
      manager.submit<int>(id: 'broken', present: _SlowBackend().present);
      await flushAsync();
      manager.debugCheckInvariants();
      final failure = throwsA(isA<StateError>()
          .having((error) => error.message, '编号', contains('不变量 ${entry.key}'))
          .having((error) => error.message, '条目', contains('broken'))
          .having((error) => error.message, '原因', contains(entry.value)));
      expect(() => manager.debugCorruptInvariant(entry.key, 'broken'), failure);
      expect(manager.debugCheckInvariants, failure);
    });
  }

  test('不变量 q：未结算却进入 closing 被自动和显式检查捕获', () async {
    final manager = Layerman(clock: FakeOverlayClock());
    addTearDown(manager.dispose);
    await manager.ready();
    final ticket =
        manager.submit<int>(id: 'unsettled', present: _SlowBackend().present);
    await flushAsync();
    final failure = throwsA(isA<StateError>()
        .having((error) => error.message, '编号', contains('不变量 q'))
        .having((error) => error.message, '条目', contains('unsettled'))
        .having((error) => error.message, '原因', contains('不等价')));
    expect(
        () => manager.debugCorruptInvariant('q-unsettled', ticket.id), failure);
    expect(manager.debugCheckInvariants, failure);
    ticket.remove();
    expect((await ticket.outcome).reason, OverlayEndReason.removed);
  });

  test('已交付结果的 closing 条目继续占位，后端退场后还可等待宽限', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    final backend = _SlowBackend();
    final ticket = manager.submit<int>(
        id: 'closing', present: backend.present, exitDuration: _slice);
    final next = HeadlessBackend<int>();
    manager.submit<int>(id: 'next', present: next.present);

    ticket.close(42);
    expect(await ticket.result, 42);
    expect((await ticket.outcome).reason, OverlayEndReason.closed);
    expect(manager.recordOf(ticket.id)!.phase, OverlayPhase.closing);
    expect(next.shown, isFalse);
    manager.debugCheckInvariants();

    backend.done.complete(99);
    await flushAsync();
    expect(manager.recordOf(ticket.id)!.phase, OverlayPhase.closing);
    manager.debugCheckInvariants();
    clock.advance(_slice);
    expect(manager.recordOf(ticket.id), isNull);
    expect(next.shown, isTrue);
    expect(await ticket.result, 42);
    expect((await ticket.outcome).reason, OverlayEndReason.closed);
  });

  for (final overlap in [false, true]) {
    test('暂停期间解析完成只暂存于 resolving：overlap=$overlap', () async {
      final manager = Layerman(clock: FakeOverlayClock());
      addTearDown(manager.dispose);
      final data = Completer<int?>();
      final backend = HeadlessBackend<int>();
      final ticket = manager.submit<int>(
          present: backend.present,
          mode: overlap ? OverlayMode.overlap : OverlayMode.queue,
          resolve: () => data.future);
      manager.pauseAll();
      data.complete(17);
      await flushAsync();
      expect(manager.resolvingIds, [ticket.id]);
      expect(backend.shown, isFalse);
      manager.debugCheckInvariants();
      manager.resumeAll();
      expect(backend.context!.data, 17);
      expect(manager.recordOf(ticket.id)!.phase, OverlayPhase.open);
      manager.debugCheckInvariants();
    });
  }

  for (final global in [false, true]) {
    test('异步关闭守卫拒绝时保留暂停时长，恢复后按剩余时长关闭：global=$global', () async {
      final clock = FakeOverlayClock();
      final manager = Layerman(clock: clock);
      addTearDown(manager.dispose);
      final guard = Completer<bool>();
      final ticket = manager.submit<int>(
          present: HeadlessBackend<int>().present,
          duration: _duration,
          beforeClose: () => guard.future);
      clock.advance(_slice);
      if (global) {
        manager.pauseAll();
      } else {
        manager.pause(ticket.id);
      }
      ticket.close(42);
      clock.advance(_duration);
      manager.debugCheckInvariants();
      guard.complete(false);
      await flushAsync();
      expect(manager.recordOf(ticket.id)!.phase, OverlayPhase.open);
      manager.debugCheckInvariants();
      if (global) {
        manager.resumeAll();
      } else {
        manager.resume(ticket.id);
      }
      clock.advance(const Duration(milliseconds: 1499));
      expect(manager.isShowing(ticket.id), isTrue);
      clock.advance(const Duration(milliseconds: 1));
      expect((await ticket.outcome).reason, OverlayEndReason.expired);
      await flushAsync();
      expect(manager.recordOf(ticket.id), isNull);
    });
  }

  test('异步守卫等待期间后端先退场，closing 不必等待守卫完成', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    final guard = Completer<bool>();
    final backend = _SlowBackend();
    final ticket = manager.submit<int>(
        present: backend.present,
        duration: _duration,
        exitDuration: _slice,
        beforeClose: () => guard.future);
    manager.pauseAll();
    ticket.close(42);
    backend.done.complete(7);
    await flushAsync();
    manager.resumeAll();
    expect(manager.recordOf(ticket.id)!.phase, OverlayPhase.closing);
    expect((await ticket.outcome).reason, OverlayEndReason.dismissedByBackend);
    manager.debugCheckInvariants();
    guard.complete(true);
    await flushAsync();
    expect(await ticket.result, 7);
    clock.advance(_slice);
    expect(manager.recordOf(ticket.id), isNull);
  });

  test('已移除条目的晚到 dismissed 不影响同 id 的新条目', () async {
    final manager = Layerman(clock: FakeOverlayClock());
    addTearDown(manager.dispose);
    final old = _SlowBackend();
    final first = manager.submit<int>(id: 'same', present: old.present);
    first.remove();
    manager.submit<int>(id: 'same', present: HeadlessBackend<int>().present);
    old.done.complete(7);
    await flushAsync();
    expect((await first.outcome).reason, OverlayEndReason.removed);
    expect(manager.recordOf('same')!.phase, OverlayPhase.open);
    manager.debugCheckInvariants();
  });

  testWidgets('build 期间恢复全局暂停，在帧后恢复前允许暂存剩余时长', (tester) async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    await manager.ready();
    final ticket = manager.submit<int>(
        present: HeadlessBackend<int>().present, duration: _duration);
    clock.advance(_slice);
    manager.pauseAll();
    var checkedDuringBuild = false;
    await tester.pumpWidget(Builder(builder: (_) {
      manager.resumeAll();
      expect(manager.isPaused, isFalse);
      expect(clock.pendingTimers, 0);
      manager.debugCheckInvariants();
      checkedDuringBuild = true;
      return const SizedBox();
    }));
    expect(checkedDuringBuild, isTrue);
    expect(clock.pendingTimers, 1);
    manager.debugCheckInvariants();
    clock.advance(const Duration(milliseconds: 1500));
    expect((await ticket.outcome).reason, OverlayEndReason.expired);
    await tester.pump();
    expect(manager.recordOf(ticket.id), isNull);
  });
}
