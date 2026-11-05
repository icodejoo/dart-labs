import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';
import 'package:layerman/testing.dart';

import 'support/headless_backend.dart' show flushAsync;

/// 提供可控的无界面展示与关闭信号。
class _Backend {
  /// 后端完成信号。
  final done = Completer<Object?>();

  /// 出场次数。
  int shows = 0;

  /// 已展示的上下文。
  PresentContext<Object?>? context;

  /// 返回自动确认关闭的句柄。
  PresentedOverlay<Object?> present(PresentContext<Object?> ctx) {
    shows++;
    context = ctx;
    return PresentedOverlay(
        visible: Future<void>.value(),
        dismissed: done.future,
        dismiss: ([r]) async {
          if (!done.isCompleted) done.complete(r);
        });
  }
}

/// 保存原始 JSON，供损坏记录的往返验证。
class _Storage implements OverlayCooldownStorage {
  /// 初始原始记录。
  _Storage(this.raw);

  /// 最近一次完整写入。
  String raw;

  @override
  Future<String?> read(String key) async => raw;

  @override
  Future<void> write(String key, String value) async {
    raw = value;
  }
}

void main() {
  for (final predicate in ['when', 'auth', 'clearWhere']) {
    test('A1 $predicate 禁止所有修改入口并允许只读查询', () async {
      final manager = Layerman(clock: FakeOverlayClock());
      addTearDown(manager.dispose);
      await manager.ready();
      // when / auth 里的 expect 失败会被引擎当作条件异常吞掉、只上报一次，
      // 所以收集上报，在谓词外面再断言一次，避免用例假通过。
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      var checked = false;
      final active = _Backend();
      final ticket = manager.submit(id: 'active', present: active.present);
      final hold = manager.hold();
      final mutations = <void Function()>[
        () => manager.open(present: _Backend().present),
        () => manager.submit(present: _Backend().present),
        () => manager.setContext({}),
        manager.pauseAll,
        manager.resumeAll,
        () => manager.pause('active'),
        () => manager.resume('active'),
        () => manager.close('active'),
        () => manager.dismiss('active'),
        () => manager.remove('active'),
        manager.clear,
        () => manager.clearTag('tag'),
        () => manager.clearWhere((_) => true),
        () => manager.update('active', 1),
        () => manager.suppress('active'),
        () => manager.resetCooldown('active'),
        manager.clearCooldowns,
        () => manager.hold(),
        ticket.close,
        ticket.remove,
        () => ticket.update(1),
        active.context!.close,
        hold.release,
        manager.dispose,
      ];
      bool check(Map<String, Object?> _) {
        checked = true;
        expect(manager.records, hasLength(1));
        expect(manager.queuedIds, isEmpty);
        expect(manager.isPaused, isTrue);
        manager.cooldownStatus('active', const OverlayCooldown());
        for (final mutation in mutations) {
          expect(
              mutation,
              throwsA(isA<StateError>().having(
                  (e) => e.message, '说明', contains('判断函数内不能修改 Layerman'))));
        }
        expect(hold.isReleased, isFalse);
        return false;
      }

      if (predicate == 'clearWhere') {
        manager.clearWhere((_) => check({}));
      } else {
        // overlap 即使暂停也先判断资格，不产生额外队列成员。
        manager.submit(
            present: _Backend().present,
            mode: OverlayMode.overlap,
            when: predicate == 'when' ? check : null,
            auth: predicate == 'auth' ? check : null);
      }
      expect(checked, isTrue, reason: '判断函数必须真的被调用');
      expect(reported, isEmpty, reason: '谓词内的断言没有被引擎吞掉的失败');
      hold.release();
      expect(hold.isReleased, isTrue);
      expect(manager.activeIds, ['active']);
      manager.debugCheckInvariants();
    });
  }

  test('A1 谓词异常每条目仅上报一次，clearWhere 异常向外传播', () async {
    final manager = Layerman(clock: FakeOverlayClock());
    addTearDown(manager.dispose);
    await manager.ready();
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);
    manager.open(
        id: 'a',
        present: _Backend().present,
        when: (_) {
          manager.remove('a');
          return true;
        });
    manager.setContext({});
    expect(errors, hasLength(1));
    expect(manager.queuedIds, ['a']);
    expect(
        () => manager.clearWhere((_) {
              manager.clear();
              return true;
            }),
        throwsStateError);
    expect(manager.queuedIds, ['a']);
  });

  test('A2 dispose 后端重入提交立即以 disposed 结算且不进入容器', () async {
    final manager = Layerman(clock: FakeOverlayClock());
    await manager.ready();
    late OverlayTicket<Object?> nested;
    final events = <OverlayEvent>[];
    manager.events.listen(events.add);
    final current = manager.submit<Object?>(
        id: 'a',
        present: (_) => PresentedOverlay(
              visible: Future<void>.value(),
              dismissed: Completer<Object?>().future,
              dismiss: ([_]) async {
                nested =
                    manager.submit(id: 'nested', present: _Backend().present);
                manager.setContext({'route': '/ignored'});
                manager.clear();
              },
            ));
    await flushAsync(); // 此回归验证已可见条目的销毁重入。
    manager.dispose();
    expect((await current.outcome).reason, OverlayEndReason.disposed);
    expect((await nested.outcome).reason, OverlayEndReason.disposed);
    await flushAsync();
    expect(manager.records, isEmpty);
    expect(manager.currentRoute, isNull);
    expect(events.where((e) => e.id == 'a').map((e) => e.type), [
      OverlayEventType.queued,
      OverlayEventType.shown,
      OverlayEventType.ended
    ]);
    manager.debugCheckInvariants();
  });

  for (final path in [
    'remove',
    'overwrite',
    'expire',
    'suppress',
    'clearWhere',
    'clearTag'
  ]) {
    test('A3 delay 属主离队 $path 取消旧等待并重新调度', () async {
      final clock = FakeOverlayClock();
      final manager = Layerman(clock: clock);
      addTearDown(manager.dispose);
      await manager.ready();
      final old = manager.submit(
          id: 'old',
          present: _Backend().present,
          delay: const Duration(seconds: 10),
          tags: {'old'},
          cooldown: const OverlayCooldown(),
          expireAfter: path == 'expire' ? const Duration(seconds: 1) : null);
      final next = _Backend();
      manager.open(id: 'next', present: next.present);
      clock.advance(const Duration(seconds: 1));
      switch (path) {
        case 'remove':
          old.remove();
        case 'overwrite':
          final replacement = _Backend();
          manager.open(
              id: 'old',
              priority: 1,
              present: replacement.present,
              delay: const Duration(seconds: 2));
          clock.advance(const Duration(seconds: 2));
          expect(replacement.shows, 1);
          expect(next.shows, 0);
          manager.remove('old');
        case 'expire':
          break;
        case 'suppress':
          manager.suppress('old');
        case 'clearWhere':
          manager.clearWhere((r) => r.id == 'old');
        case 'clearTag':
          manager.clearTag('old');
      }
      expect(next.shows, 1);
      expect(clock.pendingTimers, 0);
      expect((await old.outcome).reason, isNot(OverlayEndReason.closed));
      manager.debugCheckInvariants();
    });
  }

  test('A4 resolve 数据监听移除后不展示不计冷却不发 shown', () async {
    final manager = Layerman(clock: FakeOverlayClock());
    addTearDown(manager.dispose);
    await manager.ready();
    final resolver = Completer<Object?>();
    final backend = _Backend();
    final events = <OverlayEvent>[];
    manager.events.listen(events.add);
    final ticket = manager.submit(
        id: 'a',
        present: backend.present,
        resolve: () => resolver.future,
        cooldown: const OverlayCooldown(session: 1));
    ticket.data.addListener(ticket.remove);
    resolver.complete('resolved');
    await flushAsync();
    expect((await ticket.outcome).reason, OverlayEndReason.removed);
    expect(backend.shows, 0);
    expect(
        manager.cooldownStatus('a', const OverlayCooldown(session: 1)).canShow,
        isTrue);
    expect(events.map((e) => e.type),
        [OverlayEventType.queued, OverlayEventType.ended]);
  });

  for (final path in ['idle', 'takeover', 'replace']) {
    test('C2 maxQueued 在 $path 激活后约束等待项', () async {
      final manager = Layerman(
          clock: FakeOverlayClock(),
          slots: {'': const OverlaySlotOptions(maxQueued: 1)});
      addTearDown(manager.dispose);
      await manager.ready();
      if (path != 'idle') {
        manager.open(id: 'current', present: _Backend().present);
      }
      // idle：排队项不合格，slot 空闲；takeover：合格的高优先级项在等；
      // replace：排在前排带的 replace 项不合格，新的 replace 原本会成为被挤掉的队尾。
      manager.open(
          id: 'waiting',
          when: (_) => path == 'takeover',
          priority: 10,
          mode: path == 'replace' ? OverlayMode.replace : OverlayMode.queue,
          present: _Backend().present);
      final backend = _Backend();
      manager.open(
          id: path == 'takeover' ? 'current' : 'new',
          present: backend.present,
          mode: path == 'replace' ? OverlayMode.replace : OverlayMode.queue);
      expect(backend.shows, 1);
      expect(manager.queuedIds, ['waiting']);
    });
  }

  test('C2 等 delay 的本次提交仍可被容量淘汰，随后取消其计时器', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(
        clock: clock, slots: {'': const OverlaySlotOptions(maxQueued: 1)});
    addTearDown(manager.dispose);
    await manager.ready();
    manager.open(
        id: 'waiting',
        priority: 10,
        when: (_) => false,
        present: _Backend().present);
    final backend = _Backend();
    final ticket = manager.submit(
        id: 'new',
        delay: const Duration(seconds: 10),
        present: backend.present);
    expect((await ticket.outcome).reason, OverlayEndReason.queueFull);
    expect(clock.pendingTimers, 0);
    expect(backend.shows, 0);
    expect(manager.queuedIds, ['waiting']);
  });

  test('C7 close 与 dismiss 对排队及解析条目无操作，remove 可取消', () async {
    final manager = Layerman(clock: FakeOverlayClock());
    addTearDown(manager.dispose);
    final resolver = Completer<int?>();
    final resolving = manager.submit<int>(
        id: 'resolving',
        resolve: () => resolver.future,
        present: (_) => PresentedOverlay<int>(
            visible: Future<void>.value(),
            dismissed: Completer<int?>().future));
    final waiting = manager.submit<int>(
        id: 'waiting',
        present: (_) => PresentedOverlay<int>(
            visible: Future<void>.value(),
            dismissed: Completer<int?>().future));
    manager.close('resolving', 'invalid but ignored');
    manager.dismiss('waiting');
    resolving.close(1);
    waiting.close(2);
    expect(manager.resolvingIds, ['resolving']);
    expect(manager.queuedIds, ['waiting']);
    waiting.remove();
    resolving.remove();
    expect((await waiting.outcome).reason, OverlayEndReason.removed);
    expect((await resolving.outcome).reason, OverlayEndReason.removed);
    resolver.complete(3);
    await flushAsync();
    expect(manager.records, isEmpty);
  });

  test('C3 字符串 Map 合并保留类型，其他 Map 保留通用键', () async {
    final manager = Layerman(clock: FakeOverlayClock());
    addTearDown(manager.dispose);
    final ticket = manager.submit(
        id: 'a', present: _Backend().present, data: <String, dynamic>{'a': 1});
    ticket.update(<String, Object?>{'b': 2});
    expect(ticket.data.value as Map<String, dynamic>, {'a': 1, 'b': 2});
    ticket.update(<int, Object?>{3: 'three'});
    expect(ticket.data.value, {'a': 1, 'b': 2, 3: 'three'});
  });

  for (final unit in ['day', 'hour', 'minute']) {
    test('C4 UTC 时钟的 $unit 上限按本地日历等待与持久化', () async {
      final local = DateTime(2026, 11, 4, 10, 20, 30);
      final clock = FakeOverlayClock(local.toUtc());
      final storage = _Storage('{}');
      final manager = Layerman(clock: clock, cooldownStorage: storage);
      addTearDown(manager.dispose);
      await manager.ready();
      final cd = OverlayCooldown(
          day: unit == 'day' ? 1 : null,
          hour: unit == 'hour' ? 1 : null,
          minute: unit == 'minute' ? 1 : null);
      final ticket =
          manager.submit(id: 'a', present: _Backend().present, cooldown: cd);
      await flushAsync(); // 先确认可见，再验证日历桶的冷却。
      ticket.remove();
      final next = unit == 'day'
          ? DateTime(2026, 11, 5)
          : unit == 'hour'
              ? DateTime(2026, 11, 4, 11)
              : DateTime(2026, 11, 4, 10, 21);
      expect(manager.cooldownStatus('a', cd).wait, next.difference(local));
      await flushAsync();
      final record = (jsonDecode(storage.raw) as Map)['a'] as Map;
      expect(record['db'], '2026-11-04');
      expect(record['hb'], '2026-11-04T10');
      expect(record['mb'], '2026-11-04T10:20');
      clock.advance(next.difference(local));
      expect(manager.cooldownStatus('a', cd).canShow, isTrue);
    });
  }

  test('C5 损坏记录独立上报并原样保留，后续永久抑制正常读取', () async {
    final storage = _Storage(jsonEncode({
      'bad': {'t': 'broken'},
      'scalar': 42,
      'never': {'su': 8640000000000000},
      'valid': {'t': 4}
    }));
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);
    final manager =
        Layerman(clock: FakeOverlayClock(), cooldownStorage: storage);
    addTearDown(manager.dispose);
    await manager.ready();
    expect(errors, hasLength(2));
    expect(manager.cooldownStatus('never', const OverlayCooldown()).suppressed,
        isTrue);
    expect(
        manager
            .cooldownStatus('valid', const OverlayCooldown(total: 4))
            .permanentlyBlocked,
        isTrue);
    manager.suppress('new');
    await flushAsync();
    expect((jsonDecode(storage.raw) as Map)['bad'], {'t': 'broken'});
    expect((jsonDecode(storage.raw) as Map)['scalar'], 42);
    manager.resetCooldown('bad');
    await flushAsync();
    expect((jsonDecode(storage.raw) as Map).containsKey('bad'), isFalse);
    expect((jsonDecode(storage.raw) as Map)['scalar'], 42);
    manager.clearCooldowns();
    await flushAsync();
    expect(jsonDecode(storage.raw), isEmpty);
  });

  test('C5 同 id 的损坏记录被新记录取代后写回有效记录，重启仍保持抑制', () async {
    final storage = _Storage(jsonEncode({
      'promo': {'t': 'broken'}
    }));
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);
    final first = Layerman(clock: FakeOverlayClock(), cooldownStorage: storage);
    await first.ready();
    first.suppress('promo');
    await flushAsync();
    expect((jsonDecode(storage.raw) as Map)['promo'], isNot({'t': 'broken'}));
    first.dispose();
    final second =
        Layerman(clock: FakeOverlayClock(), cooldownStorage: storage);
    addTearDown(second.dispose);
    await second.ready();
    expect(second.cooldownStatus('promo', const OverlayCooldown()).suppressed,
        isTrue,
        reason: '“不再提示”在重启后仍然有效');
    expect(errors, hasLength(1), reason: '只有第一次读取时上报损坏记录');
  });

  for (final fails in [false, true]) {
    test('C8 present 同步嵌套结束时事件有序，抛错=$fails', () async {
      final manager = Layerman(clock: FakeOverlayClock());
      addTearDown(manager.dispose);
      await manager.ready();
      final previous = FlutterError.onError;
      final errors = <FlutterErrorDetails>[];
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);
      final events = <OverlayEvent>[];
      manager.events.listen(events.add);
      final ticket = manager.submit<Object?>(
          id: 'a',
          present: (ctx) {
            manager.open<Object?>(
                id: 'b',
                mode: OverlayMode.overlap,
                present: (inner) {
                  inner.close();
                  return PresentedOverlay(
                      visible: Future<void>.value(),
                      dismissed: Completer<Object?>().future);
                });
            if (fails) throw StateError('present failure');
            ctx.close();
            return PresentedOverlay(
                visible: Future<void>.value(),
                dismissed: Completer<Object?>().future);
          });
      await ticket.outcome;
      await flushAsync();
      expect(events.where((e) => e.id == 'a').map((e) => e.type),
          [OverlayEventType.queued, OverlayEventType.ended]);
      expect(events.where((e) => e.id == 'b').map((e) => e.type),
          [OverlayEventType.queued, OverlayEventType.ended]);
      expect(errors.length, fails ? 1 : 0);
    });
  }
}
