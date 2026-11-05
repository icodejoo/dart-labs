import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';
import 'package:layerman/testing.dart';

import 'support/headless_backend.dart';

/// 单独控制可见、关闭与不响应关闭三种后端信号。
class _Backend {
  /// 默认收到关闭请求即确认关闭。
  _Backend({this.respond = true});

  /// 是否响应编排器关闭请求。
  final bool respond;

  /// 首次可见信号。
  final visible = Completer<void>();

  /// 完全关闭信号。
  final done = Completer<int?>();

  /// 实际收到的展示请求数。
  int presents = 0;

  /// 实际收到的定向关闭请求数。
  int dismisses = 0;

  /// 返回本次展示独立的两个通道。
  PresentedOverlay<int> present(PresentContext<int> ctx) {
    presents++;
    return PresentedOverlay<int>(
      visible: visible.future,
      dismissed: done.future,
      dismiss: ([result]) async {
        dismisses++;
        if (respond && !done.isCompleted) done.complete(result);
      },
    );
  }
}

/// 可控制 hydrate 完成时刻的持久化存储。
class _Storage implements OverlayCooldownStorage {
  /// 存储读取门闩。
  final loaded = Completer<String?>();

  /// 等待外部释放存储读取。
  @override
  Future<String?> read(String key) => loaded.future;

  /// 本测试只检查读取门控，写入即时完成。
  @override
  Future<void> write(String key, String value) async {}
}

/// 创建实例并收集其事件，测试结束时取消订阅和销毁。
Layerman _manager(List<OverlayEvent> events, {FakeOverlayClock? clock}) {
  final manager = Layerman(clock: clock ?? FakeOverlayClock());
  final subscription = manager.events.listen(events.add);
  addTearDown(() async {
    manager.dispose();
    await subscription.cancel();
  });
  return manager;
}

void main() {
  setUp(() {
    testerErrors.clear();
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => testerErrors.add(details.exception);
    addTearDown(() => FlutterError.onError = previous);
  });
  test('visible 延迟：保持 open 占位，确认前不计数、不发 shown', () async {
    final events = <OverlayEvent>[];
    final manager = _manager(events);
    await manager.ready();
    final backend = _Backend();
    const cd = OverlayCooldown(session: 1, total: 1);
    final ticket =
        manager.submit(id: 'a', present: backend.present, cooldown: cd);
    await flushAsync();
    expect(manager.recordOf('a')!.phase, OverlayPhase.open);
    expect(manager.activeIds, ['a']);
    expect(manager.cooldownStatus('a', cd).canShow, isTrue);
    expect(events.map((e) => e.type), [OverlayEventType.queued]);
    backend.visible.complete();
    await flushAsync();
    expect(manager.cooldownStatus('a', cd).permanentlyBlocked, isTrue);
    expect(events.map((e) => e.type),
        [OverlayEventType.queued, OverlayEventType.shown]);
    ticket.close(42);
    expect((await ticket.outcome).value, 42);
    await flushAsync();
    expect(events.last.type, OverlayEventType.ended);
    expect(events.last.reason, OverlayEndReason.closed);
    manager.debugCheckInvariants();
  });

  for (final cd in [
    const OverlayCooldown(total: 1),
    const OverlayCooldown(session: 1),
    const OverlayCooldown(day: 1),
    const OverlayCooldown(hour: 1),
    const OverlayCooldown(minute: 1),
    const OverlayCooldown(minGap: Duration(days: 1)),
  ]) {
    final index = [cd.total, cd.session, cd.day, cd.hour, cd.minute, cd.minGap]
        .indexWhere((value) => value != null);
    test('频次 $index：未可见移除不消耗，再提交可见才消耗', () async {
      final events = <OverlayEvent>[];
      final manager = _manager(events);
      await manager.ready();
      final first = _Backend();
      final old = manager.submit(id: 'a', present: first.present, cooldown: cd);
      old.remove();
      first.visible.complete(); // 迟到确认不能影响新提交。
      await flushAsync();
      expect(manager.cooldownStatus('a', cd).canShow, isTrue);
      final next = _Backend();
      manager.submit(id: 'a', present: next.present, cooldown: cd);
      next.visible.complete();
      await flushAsync();
      expect(next.presents, 1);
      expect(manager.cooldownStatus('a', cd).canShow, isFalse);
      expect(
          events.where((e) => e.type == OverlayEventType.shown), hasLength(1));
    });
  }

  for (final ending in [
    'dismissed',
    'close',
    'remove',
    'clear',
    'replace',
    'supersede',
    'duration',
    'dismissTimeout',
    'dispose',
    'unmet'
  ]) {
    test('visible 前 $ending：只有 queued、ended，保留首次结果与原因', () async {
      final clock = FakeOverlayClock();
      final events = <OverlayEvent>[];
      final manager = _manager(events, clock: clock);
      await manager.ready();
      const cd = OverlayCooldown(session: 1, total: 1, day: 1);
      final backend = _Backend(respond: ending != 'dismissTimeout');
      final ticket = manager.submit(
        id: 'a',
        present: backend.present,
        cooldown: cd,
        duration: ending == 'duration' ? const Duration(seconds: 1) : null,
        when: ending == 'unmet' ? (ctx) => ctx['off'] != true : null,
        dismissWhenUnmet: true,
      );
      final expected = switch (ending) {
        'dismissed' => OverlayEndReason.dismissedByBackend,
        'close' || 'dismissTimeout' => OverlayEndReason.closed,
        'replace' => OverlayEndReason.replaced,
        'supersede' => OverlayEndReason.superseded,
        'duration' => OverlayEndReason.expired,
        'dispose' => OverlayEndReason.disposed,
        'unmet' => OverlayEndReason.unmet,
        _ => OverlayEndReason.removed,
      };
      switch (ending) {
        case 'dismissed':
          backend.done.complete(7);
        case 'close':
          ticket.close(7);
        case 'remove':
          ticket.remove();
        case 'clear':
          manager.clear();
        case 'replace':
          manager.submit(
              id: 'b', mode: OverlayMode.replace, present: _Backend().present);
        case 'supersede':
          manager.submit(id: 'a', present: _Backend().present);
        case 'duration':
          clock.advance(const Duration(seconds: 1));
        case 'dismissTimeout':
          ticket.close(7);
          clock.advance(const Duration(seconds: 10));
          expect(testerErrors.single, isA<TimeoutException>());
        case 'dispose':
          manager.dispose();
        case 'unmet':
          manager.setContext({'off': true});
      }
      final outcome = await ticket.outcome;
      expect(outcome.reason, expected);
      expect(outcome.value,
          ['dismissed', 'close', 'dismissTimeout'].contains(ending) ? 7 : null);
      backend.visible.complete();
      await flushAsync();
      expect(manager.cooldownStatus('a', cd).canShow, isTrue);
      expect(
          events.where((e) => e.id == 'a' && e.type == OverlayEventType.shown),
          isEmpty);
      final ended =
          events.where((e) => e.id == 'a' && e.type == OverlayEventType.ended);
      expect(ended, hasLength(1));
      expect(ended.single.reason, outcome.reason);
      manager.debugCheckInvariants();
    });
  }

  test('visible 失败：failed、尽力关闭、释放槽位，迟到错误隔离', () async {
    final events = <OverlayEvent>[];
    final manager = _manager(events);
    await manager.ready();
    final backend = _Backend();
    const cd = OverlayCooldown(total: 1);
    final ticket =
        manager.submit(id: 'a', present: backend.present, cooldown: cd);
    final next = _Backend();
    manager.submit(id: 'b', present: next.present);
    backend.visible.completeError(StateError('visible failed'));
    await flushAsync();
    expect((await ticket.outcome).reason, OverlayEndReason.failed);
    expect(testerErrors.single, isA<StateError>());
    expect(backend.dismisses, 1);
    expect(next.presents, 1);
    expect(manager.cooldownStatus('a', cd).canShow, isTrue);
    expect(events.where((e) => e.id == 'a').map((e) => e.type),
        [OverlayEventType.queued, OverlayEventType.ended]);
    next.visible.completeError(StateError('late error'));
    manager.clear();
    await flushAsync();
    expect(testerErrors, hasLength(1));
  });

  test('已完成的 dismissed 优先于已完成的 visible，不产生 shown', () async {
    final events = <OverlayEvent>[];
    final manager = _manager(events);
    final backend = _Backend()
      ..done.complete(8)
      ..visible.complete();
    final ticket = manager.submit(id: 'a', present: backend.present);
    expect((await ticket.outcome).reason, OverlayEndReason.dismissedByBackend);
    await flushAsync();
    expect(events.map((e) => e.type),
        [OverlayEventType.queued, OverlayEventType.ended]);
  });

  test('SynchronousFuture 与 present 同步 close：返回后也不补 shown', () async {
    final events = <OverlayEvent>[];
    final manager = _manager(events);
    final ticket = manager.submit<int>(
        id: 'a',
        present: (ctx) {
          ctx.close(9);
          return PresentedOverlay(
              visible: SynchronousFuture<void>(null),
              dismissed: Completer<int?>().future);
        });
    expect((await ticket.outcome).value, 9);
    await flushAsync();
    expect(events.map((e) => e.type),
        [OverlayEventType.queued, OverlayEventType.ended]);
  });

  test('hydrate 门控后才 present，visible 等待期间 suppress 不取消已激活项', () async {
    final storage = _Storage();
    final manager = Layerman(cooldownStorage: storage);
    addTearDown(manager.dispose);
    final backend = _Backend();
    const cd = OverlayCooldown(total: 1, session: 1);
    manager.submit(id: 'a', present: backend.present, cooldown: cd);
    expect(backend.presents, 0);
    storage.loaded.complete(null);
    await manager.ready();
    expect(backend.presents, 1);
    manager.suppress('a');
    backend.visible.complete();
    await flushAsync();
    expect(manager.activeIds, ['a']);
    manager.remove('a');
    expect(manager.cooldownStatus('a', cd).suppressed, isTrue);
    // 使用另一个没有抑制的上限查询，验证 session 也已计数。
    expect(manager.cooldownStatus('a', cd).permanentlyBlocked, isTrue);
  });

  test('等待 visible 仍 blockedBy 占用，关闭后含 exitDuration 才释放', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock, slots: const {
      'child': OverlaySlotOptions(blockedBy: {'parent'}),
    });
    addTearDown(manager.dispose);
    final backend = _Backend();
    final ticket = manager.submit(
        id: 'a',
        slot: 'parent',
        present: backend.present,
        exitDuration: const Duration(seconds: 1));
    final child = _Backend();
    manager.submit(id: 'b', slot: 'child', present: child.present);
    expect(child.presents, 0);
    ticket.close();
    await flushAsync();
    backend.visible.complete();
    await flushAsync();
    expect(child.presents, 0);
    clock.advance(const Duration(seconds: 1));
    expect(child.presents, 1);
    manager.debugCheckInvariants();
  });

  test('affix 阻止等待 visible 的项被 replace 抢占', () async {
    final events = <OverlayEvent>[];
    final manager = _manager(events);
    final first = _Backend();
    final ticket = manager.submit(id: 'a', affix: true, present: first.present);
    final next = _Backend();
    manager.submit(id: 'b', mode: OverlayMode.replace, present: next.present);
    expect(next.presents, 0);
    ticket.remove();
    expect(next.presents, 1);
    first.visible.complete();
    next.visible.complete();
    await flushAsync();
    expect(
        events.where((e) => e.type == OverlayEventType.shown).map((e) => e.id),
        ['b']);
  });

  test('overlap delay 结束才 present，可见时刻决定日桶与 minGap', () async {
    final clock = FakeOverlayClock(DateTime(2026, 1, 1, 23, 59, 58));
    final events = <OverlayEvent>[];
    final manager = _manager(events, clock: clock);
    await manager.ready();
    const cd = OverlayCooldown(day: 1, minGap: Duration(seconds: 5));
    final backend = _Backend();
    final ticket = manager.submit(
        id: 'a',
        mode: OverlayMode.overlap,
        delay: const Duration(seconds: 1),
        present: backend.present,
        cooldown: cd);
    clock.advance(const Duration(seconds: 1));
    expect(backend.presents, 1);
    clock.advance(const Duration(seconds: 2));
    backend.visible.complete();
    await flushAsync();
    ticket.remove();
    expect(manager.cooldownStatus('a', cd).canShow, isFalse);
    expect(
        manager
            .cooldownStatus(
                'a', const OverlayCooldown(minGap: Duration(seconds: 5)))
            .wait,
        const Duration(seconds: 5));
    expect(manager.cooldownStatus('a', const OverlayCooldown(day: 1)).wait,
        const Duration(hours: 23, minutes: 59, seconds: 59));
  });
}

/// 收集每个测试有意触发的 FlutterError，避免吞掉非预期异常。
final testerErrors = <Object>[];
