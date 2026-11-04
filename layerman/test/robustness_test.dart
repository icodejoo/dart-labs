import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';

/// 沿用现有测试的双向假后端。
class _FakeBackend<T> {
  /// 后端实际关闭的完成信号。
  final Completer<T?> _dismissed = Completer<T?>();

  /// 是否获得过展示许可。
  bool presented = false;

  /// 是否收到定向关闭请求。
  bool dismissCalled = false;

  /// 记录展示并提供定向关闭句柄。
  PresentedOverlay<T> present(PresentContext context) {
    presented = true;
    return PresentedOverlay<T>(
      dismissed: _dismissed.future,
      dismiss: ([T? result]) async {
        dismissCalled = true;
        if (!_dismissed.isCompleted) _dismissed.complete(result);
      },
    );
  }
}

/// 用读取与写入闸门重现存储竞态。
class _ControlledStorage implements OverlayCooldownStorage {
  /// 控制初次读取完成时机。
  final Completer<String?> readGate = Completer<String?>();

  /// 捕获每次直接写入的快照。
  final List<Map<String, dynamic>> snapshots = [];

  /// 分别控制每次写入完成时机。
  final List<Completer<void>> writes = [];

  @override
  Future<String?> read(String key) => readGate.future;

  @override
  Future<void> write(String key, String value) {
    snapshots.add(jsonDecode(value) as Map<String, dynamic>);
    final gate = Completer<void>();
    writes.add(gate);
    return gate.future;
  }
}

void main() {
  const initial = '{"promo":{"t":5},"other":{"t":3}}';

  testWidgets('B1 错类型关闭不改变状态，正确结果可继续关闭', (tester) async {
    final manager = Layerman();
    final backend = _FakeBackend<bool>();
    final result = manager.open<bool>(id: 'a', present: backend.present);
    expect(() => manager.close('a', 'yes'), throwsArgumentError);
    expect(manager.activeIds, ['a']);
    expect(manager.isShowing('a'), isTrue);
    expect(backend.dismissCalled, isFalse);
    manager.close('a', true);
    expect(await result, isTrue);
    expect(backend.dismissCalled, isTrue);
    await tester.pump();
    expect(manager.activeIds, isEmpty);
    manager.dispose();
  });

  testWidgets('B3 已满上限在读取前后均等待且不覆盖其它计数', (tester) async {
    final storage = _ControlledStorage();
    final manager = Layerman(cooldownStorage: storage);
    final promo = _FakeBackend<Object>();
    manager.open(
        id: 'promo',
        cooldown: const OverlayCooldown(total: 1),
        present: promo.present);
    expect(promo.presented, isFalse);
    expect(storage.snapshots, isEmpty);
    storage.readGate.complete(initial);
    await manager.ready();
    expect(promo.presented, isFalse);
    expect(manager.queuedIds, contains('promo'));
    final fresh = _FakeBackend<Object>();
    manager.open(
        id: 'fresh',
        cooldown: const OverlayCooldown(total: 9),
        present: fresh.present);
    expect(fresh.presented, isTrue);
    for (final snapshot in storage.snapshots) {
      expect(snapshot['other']['t'], 3);
      expect(snapshot['promo']['t'], 5);
    }
    storage.writes.single.complete();
    await tester.pump();
    manager.dispose();
  });

  testWidgets('B3 新条目等待读取，ready 在重新调度通知之后完成', (tester) async {
    final storage = _ControlledStorage();
    final manager = Layerman(cooldownStorage: storage);
    final fresh = _FakeBackend<Object>();
    manager.open(
        id: 'fresh',
        cooldown: const OverlayCooldown(total: 9),
        present: fresh.present);
    var notified = false;
    manager.addListener(() => notified = true);
    expect(fresh.presented, isFalse);
    expect(storage.snapshots, isEmpty);
    storage.readGate.complete(initial);
    await manager.ready();
    expect(fresh.presented, isTrue);
    expect(notified, isTrue);
    final snapshot = storage.snapshots.single;
    expect(snapshot['fresh']['t'], 1);
    expect(snapshot['promo']['t'], 5);
    expect(snapshot['other']['t'], 3);
    storage.writes.single.complete();
    await tester.pump();
    manager.dispose();
  });

  testWidgets('B3 overlap 等待读取，暂停释放也不会提前丢弃', (tester) async {
    final storage = _ControlledStorage();
    final manager = Layerman(cooldownStorage: storage);
    final backend = _FakeBackend<Object>();
    final result = manager.open(
        id: 'fresh',
        overlap: true,
        cooldown: const OverlayCooldown(total: 9),
        present: backend.present);
    var settled = false;
    result.then((_) => settled = true);
    manager.pauseAll();
    manager.resumeAll();
    await tester.pump();
    expect(manager.queuedIds, ['fresh']);
    expect(backend.presented, isFalse);
    expect(settled, isFalse);
    storage.readGate.complete(initial);
    await manager.ready();
    expect(backend.presented, isTrue);
    storage.writes.single.complete();
    await tester.pump();
    manager.dispose();
  });

  testWidgets('B3 overlap 条件不满足立即丢弃，读取后上限不满足也丢弃', (tester) async {
    final storage = _ControlledStorage();
    final manager = Layerman(cooldownStorage: storage);
    final backend = _FakeBackend<Object>();
    final rejected = manager.open(
        id: 'bad',
        overlap: true,
        when: (_) => false,
        cooldown: const OverlayCooldown(total: 9),
        present: backend.present);
    expect(await rejected, isNull);
    final capped = manager.open(
        id: 'promo',
        overlap: true,
        cooldown: const OverlayCooldown(total: 1),
        present: backend.present);
    expect(manager.queuedIds, ['promo']);
    manager.pauseAll();
    storage.readGate.complete(initial);
    await manager.ready();
    expect(manager.queuedIds, ['promo']);
    manager.resumeAll();
    expect(await capped, isNull);
    expect(backend.presented, isFalse);
    expect(manager.queuedIds, isEmpty);
    manager.dispose();
  });

  testWidgets('B3 读取失败上报后按空计数继续展示', (tester) async {
    final storage = _ControlledStorage();
    final manager = Layerman(cooldownStorage: storage);
    final backend = _FakeBackend<Object>();
    manager.open(
        id: 'fresh',
        cooldown: const OverlayCooldown(total: 9),
        present: backend.present);
    storage.readGate.completeError(StateError('读取失败'));
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    await manager.ready();
    expect(backend.presented, isTrue);
    storage.writes.single.complete();
    await tester.pump();
    manager.dispose();
  });

  testWidgets('B3 写入串行且补写最新快照，写入失败不阻塞调度', (tester) async {
    final storage = _ControlledStorage();
    final manager = Layerman(cooldownStorage: storage);
    storage.readGate.complete(initial);
    await manager.ready();
    final a = _FakeBackend<Object>();
    final b = _FakeBackend<Object>();
    manager.open(
        id: 'a',
        overlap: true,
        cooldown: const OverlayCooldown(total: 9),
        present: a.present);
    manager.open(
        id: 'b',
        overlap: true,
        cooldown: const OverlayCooldown(total: 9),
        present: b.present);
    expect(a.presented && b.presented, isTrue);
    expect(storage.writes, hasLength(1));
    expect(storage.snapshots.single.containsKey('b'), isFalse);
    storage.writes.first.completeError(StateError('写入失败'));
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    expect(storage.writes, hasLength(2));
    final latest = storage.snapshots.last;
    expect(latest['a']['t'], 1);
    expect(latest['b']['t'], 1);
    expect(latest['promo']['t'], 5);
    expect(latest['other']['t'], 3);
    storage.writes.last.complete();
    await tester.pump();
    expect(storage.writes, hasLength(2));
    manager.dispose();
  });

  testWidgets('B3 仅 session 上限无需等待读取，销毁后读取不再展示', (tester) async {
    final storage = _ControlledStorage();
    final manager = Layerman(cooldownStorage: storage);
    final session = _FakeBackend<Object>();
    final persistent = _FakeBackend<Object>();
    manager.open(
        id: 'session',
        cooldown: const OverlayCooldown(session: 1),
        present: session.present);
    manager.open(
        id: 'fresh',
        overlap: true,
        cooldown: const OverlayCooldown(total: 9),
        present: persistent.present);
    expect(session.presented, isTrue);
    manager.dispose();
    storage.readGate.complete(initial);
    await manager.ready();
    expect(persistent.presented, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('B3 写入成功后补写同一 id 的最新累计次数', (tester) async {
    final storage = _ControlledStorage();
    final manager = Layerman(cooldownStorage: storage);
    storage.readGate.complete(initial);
    await manager.ready();
    final first = _FakeBackend<Object>();
    final second = _FakeBackend<Object>();
    manager.open(
        id: 'fresh',
        cooldown: const OverlayCooldown(total: 9),
        present: first.present);
    manager.close('fresh');
    await tester.pump();
    manager.open(
        id: 'fresh',
        cooldown: const OverlayCooldown(total: 9),
        present: second.present);
    expect(second.presented, isTrue);
    expect(storage.writes, hasLength(1));
    expect(storage.snapshots.single['fresh']['t'], 1);
    storage.writes.first.complete();
    await tester.pump();
    expect(storage.writes, hasLength(2));
    expect(storage.snapshots.last['fresh']['t'], 2);
    for (final snapshot in storage.snapshots) {
      expect(snapshot['promo']['t'], 5);
      expect(snapshot['other']['t'], 3);
    }
    storage.writes.last.complete();
    await tester.pump();
    expect(storage.writes, hasLength(2));
    manager.dispose();
  });

  testWidgets('B10 守卫未决时关闭和 dismiss 去重并保留首次结果', (tester) async {
    final manager = Layerman();
    final backend = _FakeBackend<String>();
    final gate = Completer<bool>();
    var calls = 0;
    final result = manager.open(
        id: 'a',
        present: backend.present,
        beforeClose: () {
          calls++;
          return gate.future;
        });
    manager.close('a', '首次');
    manager.close('a', '再次');
    manager.dismiss('a');
    expect(calls, 1);
    gate.complete(true);
    await tester.pump();
    expect(await result, '首次');
    expect(backend.dismissCalled, isTrue);
    manager.dispose();
  });

  for (final fails in [false, true]) {
    testWidgets('B10 守卫${fails ? '异常' : '拒绝'}后可再次关闭且 remove 绕过守卫',
        (tester) async {
      final manager = Layerman();
      final backend = _FakeBackend<Object>();
      var gate = Completer<bool>();
      var calls = 0;
      final result = manager.open(
          id: 'a',
          present: backend.present,
          beforeClose: () {
            calls++;
            return gate.future;
          });
      manager.close('a');
      if (fails) {
        gate.completeError(StateError('守卫失败'));
      } else {
        gate.complete(false);
      }
      await tester.pump();
      gate = Completer<bool>();
      manager.close('a');
      expect(calls, 2);
      manager.remove('a');
      gate.complete(true);
      await tester.pump();
      expect(await result, isNull);
      expect(manager.activeIds, isEmpty);
      manager.dispose();
    });
  }

  testWidgets('B11 谓词异常隔离且只上报一次，其它条目照常调度', (tester) async {
    final manager = Layerman();
    final bad = _FakeBackend<Object>();
    final good = _FakeBackend<Object>();
    expect(
        () => manager.open(
            id: 'bad',
            present: bad.present,
            when: (_) => throw StateError('条件失败')),
        returnsNormally);
    expect(tester.takeException(), isA<StateError>());
    var notified = false;
    manager.addListener(() => notified = true);
    expect(() => manager.setContext({'auth': true}), returnsNormally);
    manager.open(id: 'good', present: good.present);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(notified, isTrue);
    expect(manager.queuedIds, ['bad']);
    expect(bad.presented, isFalse);
    expect(good.presented, isTrue);
    manager.dispose();
  });

  testWidgets('B13 未提供 id 的冷却配置触发断言', (tester) async {
    final manager = Layerman();
    final backend = _FakeBackend<Object>();
    expect(
        () => manager.open(
            cooldown: const OverlayCooldown(session: 1),
            present: backend.present),
        throwsAssertionError);
    expect(backend.presented, isFalse);
    manager.dispose();
    await tester.pump();
  });

  testWidgets('B14 销毁后 open 断言且不展示，其它写操作静默返回', (tester) async {
    final manager = Layerman();
    final active = _FakeBackend<Object>();
    final backend = _FakeBackend<Object>();
    final result = manager.open(id: 'active', present: active.present);
    manager.dispose();
    expect(await result, isNull);
    expect(active.dismissCalled, isTrue);
    expect(() => manager.open(id: 'a', present: backend.present),
        throwsAssertionError);
    expect(backend.presented, isFalse);
    expect(() {
      manager.close('a', '错误类型');
      manager.dismiss('a');
      manager.remove('a');
      manager.clear();
      manager.clearWhere((_) => throw StateError('不应调用'));
      manager.update('a', {});
      manager.setContext({'route': '/'});
      manager.pauseAll();
      manager.resumeAll();
      manager.pause('a');
      manager.resume('a');
    }, returnsNormally);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
