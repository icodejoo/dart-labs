import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:layerman/layerman.dart';
import 'package:layerman/testing.dart';

import 'support/headless_backend.dart';

const _second = Duration(seconds: 1);

/// 控制持久化水合完成时机。
class _Storage implements OverlayCooldownStorage {
  /// 未完成的读取信号。
  final readResult = Completer<String?>();

  @override
  Future<String?> read(String key) => readResult.future;

  @override
  Future<void> write(String key, String value) async {}
}

void main() {
  for (final action in [
    'remove',
    'clear',
    'clearWhere',
    'clearTag',
    'dispose',
    'reopen'
  ]) {
    test('overlap 等待中 $action 取消计时并结束旧票', () async {
      final clock = FakeOverlayClock();
      final manager = Layerman(clock: clock);
      addTearDown(manager.dispose);
      final old = HeadlessBackend<int>();
      final ticket = manager.submit(
          id: 'a',
          present: old.present,
          mode: OverlayMode.overlap,
          delay: _second,
          tags: {'tag'});
      switch (action) {
        case 'remove':
          manager.remove('a');
        case 'clear':
          manager.clear();
        case 'clearWhere':
          manager.clearWhere((r) => r.id == 'a');
        case 'clearTag':
          manager.clearTag('tag');
        case 'dispose':
          manager.dispose();
        case 'reopen':
          manager.open(id: 'a', present: HeadlessBackend<int>().present);
      }
      expect(
          (await ticket.outcome).reason,
          action == 'dispose'
              ? OverlayEndReason.disposed
              : action == 'reopen'
                  ? OverlayEndReason.superseded
                  : OverlayEndReason.removed);
      expect(clock.pendingTimers, 0);
      clock.advance(_second);
      expect(old.shown, isFalse);
      manager.debugCheckInvariants();
    });
  }

  test('overlap 到点条件不满足时 dropped，即使提交时满足', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    manager.setContext({'ok': true});
    final backend = HeadlessBackend<int>();
    final ticket = manager.submit(
        present: backend.present,
        mode: OverlayMode.overlap,
        delay: _second,
        when: (ctx) => ctx['ok'] == true,
        cooldown: const OverlayCooldown(session: 0),
        id: 'a');
    manager.setContext({'ok': false});
    clock.advance(_second);
    expect((await ticket.outcome).reason, OverlayEndReason.dropped);
    expect(backend.shown, isFalse);
    expect(clock.pendingTimers, 0);
  });

  test('overlap 到点冷却不满足时沿用 capped 或 dropped', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    await manager.ready();
    final capped = manager.submit(
        id: 'cap',
        present: HeadlessBackend<int>().present,
        mode: OverlayMode.overlap,
        delay: _second,
        cooldown: const OverlayCooldown(session: 0));
    final first = manager.submit(
        id: 'gap',
        present: HeadlessBackend<int>().present,
        cooldown: const OverlayCooldown(minGap: Duration(seconds: 2)));
    first.remove();
    final dropped = manager.submit(
        id: 'gap',
        present: HeadlessBackend<int>().present,
        mode: OverlayMode.overlap,
        delay: _second,
        cooldown: const OverlayCooldown(minGap: Duration(seconds: 2)));
    clock.advance(_second);
    expect((await capped.outcome).reason, OverlayEndReason.capped);
    expect((await dropped.outcome).reason, OverlayEndReason.dropped);
    expect(clock.pendingTimers, 0);
  });

  test('overlap 等待中暂停，到点挂起，恢复后出场', () {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    final backend = HeadlessBackend<int>();
    final ticket = manager.submit(
        present: backend.present, mode: OverlayMode.overlap, delay: _second);
    manager.pauseAll();
    clock.advance(_second);
    expect(backend.shown, isFalse);
    expect(manager.queuedIds, [ticket.id]);
    manager.debugCheckInvariants();
    manager.resumeAll();
    expect(backend.shown, isTrue);
    expect(clock.pendingTimers, 0);
  });

  test('auth 自定义用户与角色键，无需保留 auth 键', () {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final backend = HeadlessBackend<int>();
    manager.open(
        present: backend.present,
        auth: (ctx) =>
            ctx['user'] != null &&
            ((ctx['roles'] as Set?)?.contains('vip') ?? false));
    manager.setContext({
      'auth': true,
      'user': 'user',
      'roles': {'reader'}
    });
    expect(backend.shown, isFalse);
    manager.setContext({
      'roles': {'vip'}
    });
    expect(backend.shown, isTrue);
    manager.setContext({
      'roles': {'reader'}
    });
    expect(manager.activeIds, isEmpty);
  });

  for (final failed in ['route', 'auth', 'when']) {
    test('AND 条件 $failed 单独不满足也不能出场', () {
      final manager = Layerman();
      addTearDown(manager.dispose);
      final backend = HeadlessBackend<int>();
      manager.setContext({
        'route': failed == 'route' ? '/other' : '/home',
        'user': failed != 'auth',
        'ok': failed != 'when'
      });
      manager.open(
          present: backend.present,
          route: const RouteMatcher.exact('/home'),
          auth: (ctx) => ctx['user'] == true,
          when: (ctx) => ctx['ok'] == true);
      expect(backend.shown, isFalse);
      manager.setContext({'route': '/home', 'user': true, 'ok': true});
      expect(backend.shown, isTrue);
    });
  }

  test('auth 与 when 异常共用每条目一次上报，异常视为不满足', () {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final previous = FlutterError.onError;
    final errors = <FlutterErrorDetails>[];
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);
    var throwAuth = true;
    final backend = HeadlessBackend<int>();
    manager.open(
        present: backend.present,
        auth: (_) {
          if (throwAuth) throw StateError('auth');
          return true;
        },
        when: (_) => throw StateError('when'));
    expect(errors, hasLength(1));
    throwAuth = false;
    manager.setContext({});
    manager.setContext({});
    expect(errors, hasLength(1));
    expect(backend.shown, isFalse);
  });

  test('auth 不再满足时 dismissWhenUnmet false 保留条目', () {
    final manager = Layerman();
    addTearDown(manager.dispose);
    manager.setContext({'user': true});
    final ticket = manager.submit(
        present: HeadlessBackend<int>().present,
        auth: (ctx) => ctx['user'] == true,
        dismissWhenUnmet: false);
    manager.setContext({'user': false});
    expect(manager.activeIds, [ticket.id]);
  });

  test('自建后端通过 ctx.close 交付结果', () async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final backend = HeadlessBackend<int>();
    final ticket = manager.submit(present: backend.present);
    backend.context!.close(42);
    expect(await ticket.result, 42);
    expect((await ticket.outcome).reason, OverlayEndReason.closed);
    await flushAsync();
    expect(manager.activeIds, isEmpty);
  });

  test('ctx.close 被守卫拒绝，同 id 重开后旧上下文不能关闭新票', () async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final old = HeadlessBackend<int>();
    manager.open(id: 'a', present: old.present, beforeClose: () => false);
    old.context!.close(1);
    expect(manager.activeIds, ['a']);
    final current = HeadlessBackend<int>();
    final ticket = manager.submit(id: 'a', present: current.present);
    old.context!.close(2);
    expect(current.done.isCompleted, isFalse);
    expect(ticket.isActive, isTrue);
    current.context!.close(3);
    expect(await ticket.result, 3);
  });

  test('ctx.close 守卫未决时重复调用仅执行一次，首次结果生效', () async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final backend = HeadlessBackend<int>();
    final guard = Completer<bool>();
    var calls = 0;
    final ticket = manager.submit(
        present: backend.present,
        beforeClose: () {
          calls++;
          return guard.future;
        });
    backend.context!.close(1);
    backend.context!.close(2);
    expect(calls, 1);
    guard.complete(true);
    expect(await ticket.result, 1);
    backend.context!.close(3);
    expect(calls, 1);
  });

  test('复杂状态下显式检查不变量，后端自行退场取消 duration', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    final backend = HeadlessBackend<int>();
    manager.open(
        present: backend.present, duration: _second, exitDuration: _second);
    backend.done.complete(1);
    await flushAsync();
    manager.open(present: HeadlessBackend<int>().present);
    final resolver = Completer<int?>();
    manager.open(
        slot: 'resolve',
        present: HeadlessBackend<int>().present,
        resolve: () => resolver.future);
    final hold = manager.hold();
    manager.open(present: HeadlessBackend<int>().present, mode: OverlayMode.overlap);
    manager.open(
        present: HeadlessBackend<int>().present,
        mode: OverlayMode.overlap,
        delay: _second);
    manager.debugCheckInvariants();
    clock.advance(_second);
    manager.debugCheckInvariants();
    resolver.complete(2);
    await flushAsync();
    manager.debugCheckInvariants();
    hold.release();
    manager.debugCheckInvariants();
    manager.dispose();
    manager.debugCheckInvariants();
    expect(clock.pendingTimers, 0);
  });
  test('overlap 延迟到期仍等 hydrate，完成后出场且无残留计时器', () async {
    final clock = FakeOverlayClock();
    final storage = _Storage();
    final manager = Layerman(clock: clock, cooldownStorage: storage);
    addTearDown(manager.dispose);
    final backend = HeadlessBackend<int>();
    final ticket = manager.submit(
        id: 'hydrate',
        present: backend.present,
        delay: _second,
        mode: OverlayMode.overlap,
        cooldown: const OverlayCooldown(total: 1));
    clock.advance(_second);
    expect(backend.shown, isFalse);
    expect(manager.queuedIds, [ticket.id]);
    manager.debugCheckInvariants();
    storage.readResult.complete(null);
    await manager.ready();
    expect(backend.shown, isTrue);
    expect(clock.pendingTimers, 0);
  });

  test('overlap 延迟到期等 hydrate，水合发现 total 耗尽则 capped', () async {
    final clock = FakeOverlayClock();
    final storage = _Storage();
    final manager = Layerman(clock: clock, cooldownStorage: storage);
    addTearDown(manager.dispose);
    final backend = HeadlessBackend<int>();
    final ticket = manager.submit(
        id: 'hydrate',
        present: backend.present,
        delay: _second,
        mode: OverlayMode.overlap,
        cooldown: const OverlayCooldown(total: 1));
    clock.advance(_second);
    storage.readResult.complete('{"hydrate":{"t":1}}');
    await manager.ready();
    expect((await ticket.outcome).reason, OverlayEndReason.capped);
    expect(backend.shown, isFalse);
    expect(clock.pendingTimers, 0);
  });

  test('present 内同步 ctx.close 仍交付结果并清理后端，不启动 duration', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    final done = Completer<int?>();
    var dismissCalls = 0;
    final ticket = manager.submit<int>(
        duration: _second,
        present: (ctx) {
          ctx.close(7);
          return PresentedOverlay<int>(
              visible: Future<void>.value(),
              dismissed: done.future,
              dismiss: ([result]) async {
                dismissCalls++;
                done.complete(result);
              });
        });
    expect(await ticket.result, 7);
    expect(dismissCalls, 1);
    expect(clock.pendingTimers, 0);
    expect(manager.records, isEmpty);
    manager.debugCheckInvariants();
  });
  testWidgets('overlap 延迟在 build 内到期，帧后才展示且不变量成立', (tester) async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    final backend = HeadlessBackend<int>();
    await tester.pumpWidget(Builder(builder: (_) {
      manager.open(
          present: backend.present, mode: OverlayMode.overlap, delay: _second);
      clock.advance(_second);
      expect(backend.shown, isFalse);
      manager.debugCheckInvariants();
      return const SizedBox();
    }));
    expect(backend.shown, isTrue);
    manager.debugCheckInvariants();
    expect(clock.pendingTimers, 0);
  });
}
