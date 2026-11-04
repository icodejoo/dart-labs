import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/src/overlay_manager.dart';
import 'package:layerman/src/overlay_types.dart';

/// 可手动完成关闭并捕获展示上下文的测试后端。
class _Backend {
  /// 关闭完成信号。
  final done = Completer<Object?>();

  /// 最近一次展示上下文，未展示时为 null。
  PresentContext? context;

  /// 关闭时是否自动报告 dismissed。
  bool completeOnDismiss = true;

  /// 接收展示许可并提供定向关闭函数。
  PresentedOverlay<Object> present(PresentContext ctx) {
    context = ctx;
    return PresentedOverlay<Object>(
      dismissed: done.future,
      dismiss: ([Object? result]) async {
        if (completeOnDismiss && !done.isCompleted) done.complete(result);
      },
    );
  }
}

/// 控制持久化读取完成时机，验证 hydrate 门控。
class _Storage implements OverlayCooldownStorage {
  /// 初次读取的闸门。
  final gate = Completer<String?>();

  @override
  Future<String?> read(String key) => gate.future;

  @override
  Future<void> write(String key, String value) async {}
}

/// 引擎 0.3.0 的契约与边界回归。
void main() {
  /// 测试中复用的 a 标识或数据。
  const entryId = 'a';

  /// 测试中复用的 b 标识或数据。
  const secondId = 'b';

  /// 测试中复用的 closing 标识或数据。
  const closingId = 'closing';

  /// 测试中复用的 high 标识或数据。
  const highId = 'high';

  /// 测试中复用的 replace 标识或数据。
  const replacement = 'replace';

  /// 测试中复用的 next 标识或数据。
  const nextId = 'next';

  /// 测试中复用的 cap 标识或数据。
  const cappedId = 'cap';

  /// 测试中复用的 change 标识或数据。
  const changedKey = 'change';

  /// 测试中复用的 low 标识或数据。
  const lowId = 'low';

  /// 测试中复用的 day 标识或数据。
  const dayId = 'day';

  /// 测试中复用的 resolving 标识或数据。
  const resolvingId = 'resolving';

  /// 测试中复用的 other 标识或数据。
  const otherSlot = 'other';

  /// 测试中复用的 overlap 标识或数据。
  const overlapId = 'overlap';

  /// 测试中复用的 held 标识或数据。
  const heldId = 'held';

  /// 测试中复用的 first 标识或数据。
  const firstId = 'first';

  /// 测试中复用的 stuck 标识或数据。
  const stuckId = 'stuck';

  /// 测试中复用的 dispose 标识或数据。
  const disposeOperation = 'dispose';

  /// 测试中复用的 keep 标识或数据。
  const keptKey = 'keep';

  /// 测试中复用的 second 标识或数据。
  const secondQueuedId = 'second';

  /// 测试中复用的 zero 标识或数据。
  const unlimitedId = 'zero';

  /// 测试中复用的 payload 标识或数据。
  const resolvedData = 'payload';

  /// 测试中复用的 remove 标识或数据。
  const removeOperation = 'remove';

  /// 测试中复用的 clear 标识或数据。
  const clearOperation = 'clear';

  /// 测试中复用的 resolve 标识或数据。
  const resolveSlot = 'resolve';

  /// 测试中复用的 current 标识或数据。
  const currentId = 'current';

  const tick = Duration(seconds: 1);
  const longWait = Duration(minutes: 1);

  testWidgets('E1-1 total 读取前等待，读取后永久达限丢弃并继续队列', (tester) async {
    final storage = _Storage();
    final manager = Layerman(cooldownStorage: storage);
    addTearDown(manager.dispose);
    final capped = _Backend();
    final next = _Backend();
    final result = manager.open<Object>(
      id: cappedId,
      cooldown: const OverlayCooldown(total: 1),
      present: capped.present,
    );
    expect(manager.queuedIds, [cappedId]);
    expect(manager.recordOf(cappedId), isNotNull);
    storage.gate.complete('{"cap":{"t":1}}');
    await manager.ready();
    expect(await result, isNull);
    expect(manager.queuedIds, isEmpty);
    expect(manager.recordOf(cappedId), isNull);
    expect(capped.context, isNull);
    manager.open(id: nextId, present: next.present);
    expect(next.context, isNotNull);
  });

  testWidgets('E1-1 day 达限保留排队并在跨日时自唤醒', (tester) async {
    var now = DateTime(2026, 1, 1, 23, 59, 59);
    final manager = Layerman(now: () => now);
    addTearDown(manager.dispose);
    await manager.ready();
    const cd = OverlayCooldown(day: 1);
    manager.open(id: dayId, cooldown: cd, present: _Backend().present);
    manager.remove(dayId);
    final next = _Backend();
    var settled = false;
    manager
        .open(id: dayId, cooldown: cd, present: next.present)
        .then((_) => settled = true);
    await tester.pump();
    expect(settled, isFalse);
    expect(manager.queuedIds, [dayId]);
    now = now.add(tick + tick);
    await tester.pump(tick + tick);
    expect(next.context, isNotNull);
    expect(manager.queuedIds, isEmpty);
  });

  testWidgets('E1-1 session 永久丢弃后扫描下一合格条目且不增加计数', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    await manager.ready();
    const cd = OverlayCooldown(session: 1);
    manager.open(id: cappedId, cooldown: cd, present: _Backend().present);
    manager.remove(cappedId);
    manager.pauseAll();
    final dropped = manager.open(
        id: cappedId, priority: 9, cooldown: cd, present: _Backend().present);
    final next = _Backend();
    manager.open(id: nextId, present: next.present);
    manager.resumeAll();
    expect(await dropped, isNull);
    expect(next.context, isNotNull);
    manager.remove(nextId);
    final allowed = _Backend();
    manager.open(
        id: cappedId,
        cooldown: const OverlayCooldown(session: 2),
        present: allowed.present);
    expect(allowed.context, isNotNull);
  });

  testWidgets('E1-2 默认 dismiss 十秒超时推进队列并忽略迟到关闭', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final stuck = _Backend()..completeOnDismiss = false;
    final next = _Backend();
    manager.open(id: stuckId, present: stuck.present);
    manager.open(id: nextId, present: next.present);
    manager.dismiss(stuckId);
    await tester.pump(const Duration(seconds: 9));
    expect(manager.recordOf(stuckId)!.phase, OverlayPhase.closing);
    await tester.pump(tick);
    expect(tester.takeException(), isA<TimeoutException>());
    expect(manager.activeIds, [nextId]);
    stuck.done.complete(null);
    await tester.pump();
    expect(manager.activeIds, [nextId]);
  });

  testWidgets('E1-2 dismissed 提前完成取消兜底且保留退出宽限', (tester) async {
    final manager = Layerman(dismissTimeout: tick);
    addTearDown(manager.dispose);
    final backend = _Backend();
    manager.open(
        id: entryId, present: backend.present, exitDuration: tick + tick);
    manager.dismiss(entryId);
    await tester.pump();
    await tester.pump(tick);
    expect(tester.takeException(), isNull);
    expect(manager.recordOf(entryId)!.phase, OverlayPhase.closing);
    await tester.pump(tick);
    expect(manager.records, isEmpty);
  });

  testWidgets('E1-2 null 关闭时限允许后端无限等待', (tester) async {
    final manager = Layerman(dismissTimeout: null);
    addTearDown(manager.dispose);
    final backend = _Backend()..completeOnDismiss = false;
    manager.open(id: entryId, present: backend.present);
    manager.dismiss(entryId);
    await tester.pump(longWait);
    expect(manager.recordOf(entryId)!.phase, OverlayPhase.closing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E1-2 默认 resolve 三十秒跳过不记冷却，迟到结果丢弃', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final resolver = Completer<Object?>();
    final backend = _Backend();
    final result = manager.open<Object>(
        id: entryId,
        resolve: () => resolver.future,
        cooldown: const OverlayCooldown(session: 1),
        present: backend.present);
    final next = _Backend();
    manager.open(id: nextId, present: next.present);
    await tester.pump(const Duration(seconds: 29));
    expect(manager.resolvingIds, [entryId]);
    await tester.pump(tick);
    expect(tester.takeException(), isA<TimeoutException>());
    expect(await result, isNull);
    expect(manager.activeIds, [nextId]);
    manager.remove(nextId);
    final reopened = _Backend();
    manager.open(
        id: entryId,
        cooldown: const OverlayCooldown(session: 1),
        present: reopened.present);
    resolver.complete('late');
    await tester.pump();
    expect(backend.context, isNull);
    expect(reopened.context, isNotNull);
  });

  testWidgets('E1-2 resolve 覆盖时限、zero 禁用和构造 null 均生效', (tester) async {
    final manager = Layerman(resolveTimeout: tick);
    addTearDown(manager.dispose);
    final short = manager.open<Object>(
        id: 'short',
        mode: OverlayMode.overlap,
        resolveTimeout: const Duration(milliseconds: 1),
        resolve: () => Completer<Object?>().future,
        present: _Backend().present);
    manager.open<Object>(
        id: unlimitedId,
        mode: OverlayMode.overlap,
        resolveTimeout: Duration.zero,
        resolve: () => Completer<Object?>().future,
        present: _Backend().present);
    await tester.pump(tick);
    expect(tester.takeException(), isA<TimeoutException>());
    expect(await short, isNull);
    await tester.pump(longWait);
    expect(manager.resolvingIds, [unlimitedId]);
    final unlimited = Layerman(resolveTimeout: null);
    addTearDown(unlimited.dispose);
    unlimited.open<Object>(
        id: entryId,
        resolve: () => Completer<Object?>().future,
        present: _Backend().present);
    await tester.pump(longWait);
    expect(unlimited.resolvingIds, [entryId]);
  });

  testWidgets('E1-2 正常 resolve 在暂停中返回后取消解析时限', (tester) async {
    final manager = Layerman(resolveTimeout: tick);
    addTearDown(manager.dispose);
    final resolver = Completer<Object?>();
    final backend = _Backend();
    manager.open<Object>(
        id: entryId, resolve: () => resolver.future, present: backend.present);
    manager.pauseAll();
    resolver.complete(resolvedData);
    await tester.pump();
    await tester.pump(tick + tick);
    expect(tester.takeException(), isNull);
    expect(backend.context, isNull);
    manager.resumeAll();
    expect(backend.context!.dataListenable.value, resolvedData);
  });

  for (final operation in [
    removeOperation,
    clearOperation,
    replacement,
    disposeOperation
  ]) {
    testWidgets('E1-2 $operation 取消 resolve 和 dismiss 的计时器', (tester) async {
      final manager = Layerman(resolveTimeout: tick, dismissTimeout: tick);
      if (operation != disposeOperation) addTearDown(manager.dispose);
      manager.open<Object>(
          id: resolvingId,
          slot: resolveSlot,
          resolve: () => Completer<Object?>().future,
          present: _Backend().present);
      final backend = _Backend()..completeOnDismiss = false;
      manager.open(id: closingId, present: backend.present);
      manager.dismiss(closingId);
      switch (operation) {
        case removeOperation:
          manager.remove(resolvingId);
          manager.remove(closingId);
        case clearOperation:
          manager.clear();
        case replacement:
          manager.open(
              id: resolvingId, slot: resolveSlot, present: _Backend().present);
          manager.open(id: closingId, present: _Backend().present);
        case disposeOperation:
          manager.dispose();
      }
      await tester.pump(tick + tick);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('E1-3 同 id 重开接管原槽位，越过高优先级和延迟', (tester) async {
    final manager = Layerman(gap: tick);
    addTearDown(manager.dispose);
    final old =
        manager.open(id: entryId, affix: true, present: _Backend().present);
    manager.open(id: highId, priority: 100, present: _Backend().present);
    final replacement = _Backend();
    manager.open(id: entryId, delay: longWait, present: replacement.present);
    expect(await old, isNull);
    expect(replacement.context, isNotNull);
    expect(manager.activeIds, [entryId]);
    expect(manager.queuedIds, [highId]);
  });

  testWidgets('E1-3 不合格或暂停时重开仍按队列竞争', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    manager.open(id: entryId, present: _Backend().present);
    manager.open(id: highId, priority: 100, present: _Backend().present);
    final blocked = _Backend();
    manager.open(id: entryId, requiresAuth: true, present: blocked.present);
    expect(manager.activeIds, [highId]);
    expect(manager.queuedIds, [entryId]);
    expect(blocked.context, isNull);
    manager.clear();
    manager.open(id: entryId, present: _Backend().present);
    manager.open(id: highId, priority: 100, present: _Backend().present);
    manager.pauseAll();
    manager.open(id: entryId, present: _Backend().present);
    expect(manager.activeIds, isEmpty);
    manager.resumeAll();
    expect(manager.activeIds, [highId]);
  });

  testWidgets('E1-3 换 slot 或改 overlap 不接管旧槽位', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    manager.open(id: entryId, present: _Backend().present);
    manager.open(id: highId, priority: 100, present: _Backend().present);
    manager.open(id: otherSlot, slot: otherSlot, present: _Backend().present);
    manager.open(id: entryId, slot: otherSlot, present: _Backend().present);
    expect(manager.activeIds, contains(highId));
    expect(manager.queuedIds, [entryId]);
    manager.open(
        id: entryId, mode: OverlayMode.overlap, present: _Backend().present);
    expect(manager.activeIds, containsAll([highId, otherSlot, entryId]));
  });

  testWidgets('E1-4 map 浅合并通知实时通道，展示快照保持原值', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final backend = _Backend();
    manager.open(
        id: entryId,
        data: {keptKey: 1, changedKey: 2},
        present: backend.present);
    final ctx = backend.context!;
    var calls = 0;
    ctx.dataListenable.addListener(() => calls++);
    manager.update(entryId, {changedKey: 3});
    expect(ctx.dataListenable.value, {keptKey: 1, changedKey: 3});
    expect(ctx.data, {keptKey: 1, changedKey: 2});
    expect(calls, 1);
    manager.update(entryId, replacement);
    expect(ctx.dataListenable.value, replacement);
    expect(calls, 2);
    manager.remove(entryId);
    manager.update(entryId, 'ignored');
    expect(ctx.dataListenable.value, replacement);
    ctx.dataListenable.addListener(() {});
  });

  testWidgets('E1-5 records 覆盖各阶段且 queuedIds 保持真实出场顺序', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final resolver = Completer<Object?>();
    manager.open<Object>(
        id: entryId,
        resolve: () => resolver.future,
        present: _Backend().present);
    manager.open(id: lowId, present: _Backend().present);
    manager.open(id: highId, priority: 10, present: _Backend().present);
    manager.open(
        id: replacement,
        mode: OverlayMode.replace,
        requiresAuth: true,
        present: _Backend().present);
    manager.open<Object>(
        id: overlapId,
        mode: OverlayMode.overlap,
        resolve: () => Completer<Object?>().future,
        present: _Backend().present);
    expect(manager.activeIds, isEmpty);
    expect(manager.isShowing(entryId), isFalse);
    expect(manager.resolvingIds, [entryId, overlapId]);
    expect(manager.queuedIds, [replacement, highId, lowId]);
    expect(manager.records.map((r) => r.id),
        [entryId, replacement, highId, lowId, overlapId]);
    expect(manager.recordOf(entryId)!.phase, OverlayPhase.resolving);
    expect(manager.recordOf(entryId)!.active, isTrue);
    expect(manager.recordOf(lowId)!.active, isFalse);
    expect(manager.recordOf('missing'), isNull);
    resolver.complete(null);
    await tester.pump();
    expect(manager.activeIds, [highId]);
    expect(manager.records.map((r) => r.id),
        [highId, replacement, lowId, overlapId]);
    manager.clear();
  });

  testWidgets('E1-5 closing 与暂停的 overlap 均有快照，移除后查询为空', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final backend = _Backend()..completeOnDismiss = false;
    manager.open(id: closingId, present: backend.present);
    manager.dismiss(closingId);
    expect(manager.activeIds, [closingId]);
    expect(manager.isShowing(closingId), isTrue);
    expect(manager.resolvingIds, isEmpty);
    expect(manager.recordOf(closingId)!.phase, OverlayPhase.closing);
    manager.pauseAll();
    manager.open(
        id: heldId, mode: OverlayMode.overlap, present: _Backend().present);
    expect(manager.queuedIds, [heldId]);
    expect(manager.recordOf(heldId)!.phase, OverlayPhase.pending);
    expect(manager.records.map((r) => r.id), [closingId, heldId]);
    manager.clear();
    expect(manager.recordOf(closingId), isNull);
    expect(manager.records, isEmpty);
  });

  testWidgets('E1-6 有序队列保留 replace 前带和同优先级 FIFO', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    manager.open(id: currentId, affix: true, present: _Backend().present);
    manager.open(id: firstId, priority: 10, present: _Backend().present);
    manager.open(id: secondQueuedId, priority: 10, present: _Backend().present);
    manager.open(
        id: replacement,
        mode: OverlayMode.replace,
        present: _Backend().present);
    expect(manager.queuedIds, [replacement, firstId, secondQueuedId]);
    manager.remove(currentId);
    expect(manager.activeIds, [replacement]);
    manager.remove(replacement);
    expect(manager.activeIds, [firstId]);
    manager.remove(firstId);
    expect(manager.activeIds, [secondQueuedId]);
  });

  testWidgets('E1-6 when 共享不可变视图，空 setContext 也重新评估', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    await manager.ready();
    final views = <Map<String, Object?>>[];
    var allowed = false;

    /// 捕获视图身份并使用外部条件决定资格。
    bool when(Map<String, Object?> ctx) {
      views.add(ctx);
      return allowed;
    }

    manager.open(id: entryId, when: when, present: _Backend().present);
    manager.open(id: secondId, when: when, present: _Backend().present);
    expect(views.every((v) => identical(v, views.first)), isTrue);
    expect(() => views.first[changedKey] = true, throwsUnsupportedError);
    final previous = views.last;
    allowed = true;
    manager.setContext({});
    expect(identical(previous, views.last), isFalse);
    expect(manager.activeIds, [entryId]);
    expect(manager.queuedIds, [secondId]);
  });
}
