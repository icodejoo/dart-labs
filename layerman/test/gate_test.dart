import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';
import 'package:layerman/testing.dart';

import 'support/headless_backend.dart';

/// 测试中的业务等待单位。
const _second = Duration(seconds: 1);

/// 手动控制 hydrate 完成时刻的存储。
class _DelayedStorage implements OverlayCooldownStorage {
  /// 待读取的完整冷却快照。
  final readResult = Completer<String?>();

  /// 保持读取未决，直到测试显式完成。
  @override
  Future<String?> read(String key) => readResult.future;

  /// 接受写回，不影响本组资格测试。
  @override
  Future<void> write(String key, String value) async {}
}

/// 验证业务资格、共享唤醒及原有激活约束的组合。
void main() {
  for (final mode in [OverlayMode.queue, OverlayMode.overlap]) {
    group('$mode', () {
      test('pass 读取 setContext 只读视图并允许展示', () async {
        final manager = Layerman();
        addTearDown(manager.dispose);
        await manager.ready();
        manager.setContext({'user': 'member'});
        final backend = HeadlessBackend<int>();
        final result = manager.open<int>(
          present: backend.present,
          mode: mode,
          gate: (ctx) {
            expect(ctx['user'], 'member');
            expect(() => ctx['user'] = 'other', throwsUnsupportedError);
            return const OverlayVerdict.pass();
          },
        );
        expect(backend.shown, isTrue);
        backend.context!.close(7);
        expect(await result, 7);
      });

      test('waitUntil 在截止时刻自动激活且不多留冷却余量', () async {
        final clock = FakeOverlayClock();
        final manager = Layerman(clock: clock);
        addTearDown(manager.dispose);
        await manager.ready();
        final deadline = clock.now().add(_second);
        final backend = HeadlessBackend<void>();
        manager.submit<void>(
          id: 'waiting',
          present: backend.present,
          mode: mode,
          gate: (_) => OverlayVerdict.waitUntil(deadline),
        );
        expect(manager.queuedIds, ['waiting']);
        expect(clock.pendingTimers, 1);
        clock.advance(const Duration(milliseconds: 999));
        expect(backend.shown, isFalse);
        clock.advance(const Duration(milliseconds: 1));
        expect(backend.shown, isTrue);
        expect(clock.pendingTimers, 0);
        manager.debugCheckInvariants();
      });

      test('waitUntil 期间上下文可提前放行或延后等待', () async {
        final clock = FakeOverlayClock();
        final manager = Layerman(clock: clock);
        addTearDown(manager.dispose);
        await manager.ready();
        manager.setContext({'deadline': clock.now().add(_second)});
        final backend = HeadlessBackend<void>();
        manager.submit<void>(
          present: backend.present,
          mode: mode,
          gate: (ctx) => ctx['allow'] == true
              ? const OverlayVerdict.pass()
              : OverlayVerdict.waitUntil(ctx['deadline']! as DateTime),
        );
        clock.advance(const Duration(milliseconds: 500));
        manager.setContext({'deadline': clock.now().add(_second)});
        clock.advance(const Duration(milliseconds: 500));
        expect(backend.shown, isFalse);
        manager.setContext({'allow': true});
        expect(backend.shown, isTrue);
        expect(clock.pendingTimers, 0);
      });

      test('drop 的默认及自选原因交付 outcome 与 ended，且不计冷却', () async {
        final manager = Layerman();
        addTearDown(manager.dispose);
        await manager.ready();
        final events = <OverlayEvent>[];
        final subscription = manager.events.listen(events.add);
        addTearDown(subscription.cancel);
        for (final reason in [OverlayEndReason.gated, OverlayEndReason.unmet]) {
          final backend = HeadlessBackend<int>();
          final ticket = manager.submit<int>(
            id: reason.name,
            present: backend.present,
            mode: mode,
            cooldown: const OverlayCooldown(total: 1),
            gate: (_) => reason == OverlayEndReason.gated
                ? const OverlayVerdict.drop()
                : OverlayVerdict.drop(reason),
          );
          final outcome = await ticket.outcome;
          expect(outcome.reason, reason);
          expect(outcome.value, isNull);
          expect(await ticket.result, isNull);
          expect(ticket.isActive, isFalse);
          expect(backend.shown, isFalse);
          expect(
              manager
                  .cooldownStatus(reason.name, const OverlayCooldown(total: 1))
                  .canShow,
              isTrue);
        }
        await flushAsync();
        expect(events.map((e) => e.type), [
          OverlayEventType.queued,
          OverlayEventType.ended,
          OverlayEventType.queued,
          OverlayEventType.ended,
        ]);
        expect(
            events
                .where((e) => e.type == OverlayEventType.ended)
                .map((e) => e.reason),
            [OverlayEndReason.gated, OverlayEndReason.unmet]);
      });

      test('等待期间 setContext 可永久拒绝，即使暂停或被 blockedBy 阻塞', () async {
        final clock = FakeOverlayClock();
        final manager = Layerman(clock: clock, slots: const {
          'target': OverlaySlotOptions(blockedBy: {'modal'}),
        });
        addTearDown(manager.dispose);
        await manager.ready();
        final blocker = manager.submit<void>(
            slot: 'modal', present: HeadlessBackend<void>().present);
        final deadline = clock.now().add(_second);
        final ticket = manager.submit<void>(
          slot: 'target',
          present: HeadlessBackend<void>().present,
          mode: mode,
          gate: (ctx) => ctx['drop'] == true
              ? const OverlayVerdict.drop()
              : OverlayVerdict.waitUntil(deadline),
        );
        manager.pauseAll();
        manager.setContext({'drop': true});
        expect((await ticket.outcome).reason, OverlayEndReason.gated);
        expect(manager.queuedIds, isEmpty);
        expect(blocker.isActive, isTrue);
        expect(clock.pendingTimers, 0);
      });

      test('gate 异常隔离并按条目只上报一次', () async {
        final manager = Layerman();
        addTearDown(manager.dispose);
        await manager.ready();
        final errors = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = errors.add;
        addTearDown(() => FlutterError.onError = previous);
        var fail = true;
        final backend = HeadlessBackend<void>();
        final ticket = manager.submit<void>(
          present: backend.present,
          mode: mode,
          gate: (_) {
            if (fail) throw StateError('gate failure');
            return const OverlayVerdict.pass();
          },
        );
        manager.setContext({});
        manager.setContext({});
        manager.debugCheckInvariants();
        expect(errors, hasLength(1));
        expect(errors.single.exception, isStateError);
        expect(backend.shown, isFalse);
        if (mode == OverlayMode.overlap) {
          expect((await ticket.outcome).reason, OverlayEndReason.dropped);
        } else {
          fail = false;
          manager.setContext({});
          expect(backend.shown, isTrue);
        }
      });

      test('截止到点仍须等待 pause 与 blockedBy 释放', () async {
        final clock = FakeOverlayClock();
        final manager = Layerman(clock: clock, slots: const {
          'target': OverlaySlotOptions(blockedBy: {'modal'}),
        });
        addTearDown(manager.dispose);
        await manager.ready();
        final blocker = manager.submit<void>(
            slot: 'modal', present: HeadlessBackend<void>().present);
        final backend = HeadlessBackend<void>();
        final deadline = clock.now().add(_second);
        manager.submit<void>(
          slot: 'target',
          present: backend.present,
          mode: mode,
          gate: (_) => OverlayVerdict.waitUntil(deadline),
        );
        manager.pauseAll();
        clock.advance(_second);
        blocker.remove();
        expect(backend.shown, isFalse);
        expect(clock.pendingTimers, 0);
        manager.resumeAll();
        expect(backend.shown, isTrue);
        expect(clock.pendingTimers, 0);
      });

      test('expireAfter 继续只约束串行，overlap 可等业务截止时刻', () async {
        final clock = FakeOverlayClock();
        final manager = Layerman(clock: clock);
        addTearDown(manager.dispose);
        await manager.ready();
        final backend = HeadlessBackend<void>();
        final deadline = clock.now().add(const Duration(seconds: 2));
        final ticket = manager.submit<void>(
          present: backend.present,
          mode: mode,
          expireAfter: _second,
          gate: (_) => OverlayVerdict.waitUntil(deadline),
        );
        clock.advance(_second);
        expect(backend.shown, isFalse);
        if (mode == OverlayMode.queue) {
          expect((await ticket.outcome).reason, OverlayEndReason.queueExpired);
          expect(clock.pendingTimers, 0);
        }
        clock.advance(_second);
        expect(backend.shown, mode == OverlayMode.overlap);
      });

      test('已激活条目不再调用 gate，dismissWhenUnmet 不使用 gate', () async {
        final manager = Layerman();
        addTearDown(manager.dispose);
        await manager.ready();
        var calls = 0;
        final backend = HeadlessBackend<void>();
        manager.submit<void>(
          present: backend.present,
          mode: mode,
          gate: (ctx) {
            calls++;
            return ctx['drop'] == true
                ? const OverlayVerdict.drop()
                : const OverlayVerdict.pass();
          },
        );
        final before = calls;
        manager.setContext({'drop': true});
        manager.pauseAll();
        manager.resumeAll();
        expect(calls, before);
        expect(backend.shown, isTrue);
        expect(manager.activeIds, hasLength(1));
      });

      for (final missing in ['route', 'auth', 'when']) {
        test('$missing 不通过时与 gate 按 AND 组合', () async {
          final manager = Layerman();
          addTearDown(manager.dispose);
          await manager.ready();
          manager.setContext({'route': '/home', 'auth': true, 'when': true});
          manager.setContext({missing: missing == 'route' ? '/other' : false});
          final backend = HeadlessBackend<void>();
          var gateCalls = 0;
          manager.submit<void>(
            present: backend.present,
            mode: mode,
            route: const RouteMatcher.exact('/home'),
            auth: (ctx) => ctx['auth'] == true,
            when: (ctx) => ctx['when'] == true,
            gate: (_) {
              gateCalls++;
              return const OverlayVerdict.pass();
            },
          );
          expect(backend.shown, isFalse);
          expect(gateCalls, 0);
          if (mode == OverlayMode.queue) {
            manager.setContext({missing: missing == 'route' ? '/home' : true});
            expect(backend.shown, isTrue);
          }
        });
      }
    });
  }

  for (final businessSeconds in [1, 3]) {
    test('业务等待 $businessSeconds 秒与冷却 2 秒取更晚截止', () async {
      final clock = FakeOverlayClock();
      final manager = Layerman(clock: clock);
      addTearDown(manager.dispose);
      await manager.ready();
      const cooldown = OverlayCooldown(minGap: Duration(seconds: 2));
      manager
          .submit<void>(
              id: 'same',
              cooldown: cooldown,
              present: HeadlessBackend<void>().present)
          .remove();
      final backend = HeadlessBackend<void>();
      final deadline = clock.now().add(Duration(seconds: businessSeconds));
      manager.submit<void>(
          id: 'same',
          cooldown: cooldown,
          present: backend.present,
          gate: (_) => OverlayVerdict.waitUntil(deadline));
      final wait = businessSeconds == 1
          ? const Duration(milliseconds: 2016)
          : const Duration(seconds: 3);
      clock.advance(wait - const Duration(microseconds: 1));
      expect(backend.shown, isFalse);
      clock.advance(const Duration(microseconds: 1));
      expect(backend.shown, isTrue);
    });
  }

  for (final mode in [OverlayMode.queue, OverlayMode.overlap]) {
    for (final permanent in [false, true]) {
      test('$mode gate 与 suppress 组合，永久=$permanent', () async {
        final clock = FakeOverlayClock();
        final manager = Layerman(clock: clock);
        addTearDown(manager.dispose);
        await manager.ready();
        manager.suppress('suppressed', duration: permanent ? null : _second);
        final backend = HeadlessBackend<void>();
        final deadline = clock.now().add(_second);
        final ticket = manager.submit<void>(
          id: 'suppressed',
          mode: mode,
          present: backend.present,
          cooldown: const OverlayCooldown(),
          gate: (_) => OverlayVerdict.waitUntil(deadline),
        );
        if (permanent || mode == OverlayMode.overlap) {
          expect((await ticket.outcome).reason, OverlayEndReason.suppressed);
          expect(manager.queuedIds, isEmpty);
        } else {
          clock.advance(const Duration(milliseconds: 1016));
          expect(backend.shown, isTrue);
        }
      });
    }
  }

  test('共享计时器兼顾串行等待与多个 overlap，其他提交不推迟截止', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    await manager.ready();
    final backends = <HeadlessBackend<void>>[];
    for (var i = 1; i <= 3; i++) {
      final backend = HeadlessBackend<void>();
      backends.add(backend);
      final deadline = clock.now().add(Duration(seconds: i));
      manager.submit<void>(
        mode: i == 2 ? OverlayMode.queue : OverlayMode.overlap,
        present: backend.present,
        gate: (_) => OverlayVerdict.waitUntil(deadline),
      );
    }
    expect(clock.pendingTimers, 1);
    clock.advance(const Duration(milliseconds: 500));
    final occupant =
        manager.submit<void>(present: HeadlessBackend<void>().present);
    expect(clock.pendingTimers, 1);
    clock.advance(const Duration(milliseconds: 500));
    expect(backends.map((b) => b.shown), [true, false, false]);
    occupant.remove();
    clock.advance(_second);
    expect(backends.map((b) => b.shown), [true, true, false]);
    clock.advance(_second);
    expect(backends.every((b) => b.shown), isTrue);
    expect(clock.pendingTimers, 0);
  });

  test('一次扫描每项只求值一次，唤醒和不变量检查不额外调用条件', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    await manager.ready();
    var whenCalls = 0;
    var gateCalls = 0;
    final deadline = clock.now().add(_second);
    manager.submit<void>(
        present: HeadlessBackend<void>().present,
        when: (_) {
          whenCalls++;
          return true;
        },
        gate: (_) {
          gateCalls++;
          return OverlayVerdict.waitUntil(deadline);
        });
    whenCalls = gateCalls = 0;
    manager.setContext({});
    manager.debugCheckInvariants();
    expect(whenCalls, 1);
    expect(gateCalls, 1);
    clock.advance(_second);
    expect(whenCalls, 2);
    expect(gateCalls, 2);
  });

  for (final operation in [
    'setContext',
    'pauseAll',
    'submit',
    'dispose',
    'ticket.remove',
    'context.close',
    'hold.release'
  ]) {
    test('gate 禁止修改管理器：$operation', () async {
      final manager = Layerman();
      addTearDown(manager.dispose);
      await manager.ready();
      final backend = HeadlessBackend<void>();
      final active = manager.submit<void>(present: backend.present);
      final hold = manager.hold();
      final action = switch (operation) {
        'setContext' => () => manager.setContext({'mutated': true}),
        'pauseAll' => manager.pauseAll,
        'submit' => () =>
            manager.submit<void>(present: HeadlessBackend<void>().present),
        'dispose' => manager.dispose,
        'ticket.remove' => active.remove,
        'context.close' => () => backend.context!.close(),
        _ => hold.release,
      };
      final ticket = manager.submit<void>(
        present: HeadlessBackend<void>().present,
        gate: (_) {
          expect(action, throwsStateError);
          return const OverlayVerdict.drop();
        },
      );
      expect((await ticket.outcome).reason, OverlayEndReason.gated);
      expect(active.isActive, isTrue);
      expect(hold.isReleased, isFalse);
      expect(manager.isDisposed, isFalse);
      hold.release();
    });
  }

  for (final operation in [
    'remove',
    'clear',
    'clearWhere',
    'supersede',
    'dispose'
  ]) {
    test('清理业务等待取消共享唤醒：$operation', () async {
      final clock = FakeOverlayClock();
      final manager = Layerman(clock: clock);
      addTearDown(manager.dispose);
      await manager.ready();
      final deadline = clock.now().add(_second);
      final backend = HeadlessBackend<void>();
      final ticket = manager.submit<void>(
          id: 'waiting',
          mode: OverlayMode.overlap,
          present: backend.present,
          gate: (_) => OverlayVerdict.waitUntil(deadline));
      switch (operation) {
        case 'remove':
          ticket.remove();
        case 'clear':
          manager.clear();
        case 'clearWhere':
          manager.clearWhere((r) => r.id == 'waiting');
        case 'supersede':
          manager.submit<void>(
              id: 'waiting', present: HeadlessBackend<void>().present);
        case 'dispose':
          manager.dispose();
      }
      expect(clock.pendingTimers, 0);
      expect(
          (await ticket.outcome).reason,
          switch (operation) {
            'dispose' => OverlayEndReason.disposed,
            'supersede' => OverlayEndReason.superseded,
            _ => OverlayEndReason.removed,
          });
      clock.advance(_second);
      expect(backend.shown, isFalse);
      manager.debugCheckInvariants();
    });
  }

  test('已承诺 resolve 的条目不因 gate 改变而被取消', () async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    await manager.ready();
    final resolved = Completer<int?>();
    final backend = HeadlessBackend<int>();
    manager.submit<int>(
        present: backend.present,
        resolve: () => resolved.future,
        gate: (ctx) => ctx['drop'] == true
            ? const OverlayVerdict.drop()
            : const OverlayVerdict.pass());
    manager.setContext({'drop': true});
    resolved.complete(1);
    await flushAsync();
    expect(backend.shown, isTrue);
  });

  for (final mode in [OverlayMode.queue, OverlayMode.overlap]) {
    for (final hydrateFirst in [false, true]) {
      test('$mode 业务截止与慢 hydrate 的先后顺序：读取先完成=$hydrateFirst', () async {
        final clock = FakeOverlayClock();
        final storage = _DelayedStorage();
        final manager = Layerman(clock: clock, cooldownStorage: storage);
        addTearDown(manager.dispose);
        final deadline = clock.now().add(_second);
        final backend = HeadlessBackend<void>();
        manager.submit<void>(
          id: 'hydrate',
          mode: mode,
          present: backend.present,
          cooldown: const OverlayCooldown(),
          gate: (_) => OverlayVerdict.waitUntil(deadline),
        );
        expect(clock.pendingTimers, 0);
        if (!hydrateFirst) clock.advance(_second);
        expect(backend.shown, isFalse);
        storage.readResult.complete(null);
        await manager.ready();
        if (hydrateFirst) {
          expect(backend.shown, isFalse);
          expect(clock.pendingTimers, 1);
          clock.advance(_second);
        }
        expect(backend.shown, isTrue);
        expect(clock.pendingTimers, 0);
      });
    }
  }

  test('overlap 在 delay 到期才执行 gate，并可继续等业务截止', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    await manager.ready();
    final deadline = clock.now().add(const Duration(seconds: 2));
    var calls = 0;
    final backend = HeadlessBackend<void>();
    manager.submit<void>(
        mode: OverlayMode.overlap,
        delay: _second,
        present: backend.present,
        gate: (_) {
          calls++;
          return OverlayVerdict.waitUntil(deadline);
        });
    manager.setContext({});
    expect(calls, 0);
    clock.advance(_second);
    expect(calls, 1);
    expect(backend.shown, isFalse);
    clock.advance(_second);
    expect(calls, 2);
    expect(backend.shown, isTrue);
  });

  test('串行 appear delay 到点重判 gate，可再次等待而不重计 delay', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    await manager.ready();
    final backend = HeadlessBackend<void>();
    final deadline = clock.now().add(const Duration(seconds: 2));
    manager.submit<void>(
        delay: _second,
        present: backend.present,
        gate: (ctx) => ctx['wait'] == true
            ? OverlayVerdict.waitUntil(deadline)
            : const OverlayVerdict.pass());
    manager.setContext({'wait': true});
    clock.advance(_second);
    expect(backend.shown, isFalse);
    clock.advance(_second);
    expect(backend.shown, isTrue);
  });

  test('replace 等待或 drop 不抢占，资格通过后沿用原有前排顺序', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    await manager.ready();
    final active =
        manager.submit<void>(present: HeadlessBackend<void>().present);
    final ordinary = HeadlessBackend<void>();
    manager.submit<void>(present: ordinary.present, priority: 100);
    final rejected = manager.submit<void>(
        mode: OverlayMode.replace,
        present: HeadlessBackend<void>().present,
        gate: (_) => const OverlayVerdict.drop());
    expect((await rejected.outcome).reason, OverlayEndReason.gated);
    expect(active.isActive, isTrue);
    final deadline = clock.now().add(_second);
    final replacer = HeadlessBackend<void>();
    manager.submit<void>(
        mode: OverlayMode.replace,
        present: replacer.present,
        gate: (_) => OverlayVerdict.waitUntil(deadline));
    clock.advance(_second);
    expect(active.isActive, isTrue);
    active.remove();
    expect(replacer.shown, isTrue);
    expect(ordinary.shown, isFalse);
  });

  test('未捕获的 gate 修改重入按条件异常隔离，原有条目不受影响', () async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    await manager.ready();
    final active =
        manager.submit<void>(present: HeadlessBackend<void>().present);
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);
    final ticket = manager.submit<void>(
        present: HeadlessBackend<void>().present,
        gate: (_) {
          manager.clear();
          return const OverlayVerdict.pass();
        });
    manager.setContext({});
    expect(errors, hasLength(1));
    expect(errors.single.exception, isStateError);
    expect(active.isActive, isTrue);
    expect(manager.queuedIds, [ticket.id]);
  });

  test('移除最后一个串行业务等待项立即取消唤醒并回收空 slot', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    await manager.ready();
    final deadline = clock.now().add(_second);
    final ticket = manager.submit<void>(
        present: HeadlessBackend<void>().present,
        gate: (_) => OverlayVerdict.waitUntil(deadline));
    expect(clock.pendingTimers, 1);
    ticket.remove();
    expect(clock.pendingTimers, 0);
    expect(manager.debugSlotCount, 0);
  });

  for (final byContext in [false, true]) {
    test('批量释放业务 overlap 时 presenter 重入上下文，每项仅展示一次：context=$byContext',
        () async {
      final clock = FakeOverlayClock();
      final manager = Layerman(clock: clock);
      addTearDown(manager.dispose);
      await manager.ready();
      final deadline = clock.now().add(_second);
      var firstCalls = 0;
      var secondCalls = 0;
      manager.submit<void>(
          mode: OverlayMode.overlap,
          present: (ctx) {
            firstCalls++;
            manager.setContext({'allow': true});
            return HeadlessBackend<void>().present(ctx);
          },
          gate: (ctx) => ctx['allow'] == true
              ? const OverlayVerdict.pass()
              : OverlayVerdict.waitUntil(deadline));
      manager.submit<void>(
          mode: OverlayMode.overlap,
          present: (ctx) {
            secondCalls++;
            return HeadlessBackend<void>().present(ctx);
          },
          gate: (ctx) => ctx['allow'] == true
              ? const OverlayVerdict.pass()
              : OverlayVerdict.waitUntil(deadline));
      if (byContext) {
        manager.setContext({'allow': true});
      } else {
        clock.advance(_second);
      }
      expect(firstCalls, 1);
      expect(secondCalls, 1);
      expect(manager.activeIds.toSet(), hasLength(2));
      expect(clock.pendingTimers, 0);
      manager.debugCheckInvariants();
    });
  }
}
