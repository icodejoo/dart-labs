import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/src/overlay_manager.dart';
import 'package:layerman/src/overlay_types.dart';

/// 测试复用的条目标识。
const _id = 'entry';

/// 测试复用的标签。
const _tag = 'group';

/// 测试复用的标识。
const _next = 'next';

/// 测试复用的标识。
const _other = 'other';

/// 测试复用的标识。
const _high = 'high';

/// 测试复用的标识。
const _slot = 's0';

/// 测试复用的标识。
const _empty = 'empty';

/// 测试复用的短等待。
const _tick = Duration(milliseconds: 20);

/// 测试复用的时间型冷却。
const _gapCooldown = OverlayCooldown(minGap: Duration(seconds: 1));

/// 不自行结束的后端，不创建计时器。
PresentedOverlay<Object?> _present(PresentContext context) =>
    PresentedOverlay<Object?>(dismissed: Completer<Object?>().future);

/// 可延迟读取、记录全部写入的测试存储。
class _Storage implements OverlayCooldownStorage {
  /// 调用方控制 hydrate 完成时机。
  final readResult = Completer<String?>();

  /// 实际落盘快照。
  final writes = <Map<String, dynamic>>[];

  /// 可选阻塞首个写入，验证串行补写。
  Completer<void>? firstWrite;

  /// 返回测试控制的读取结果。
  @override
  Future<String?> read(String key) => readResult.future;

  /// 保存快照并按需阻塞首次写入。
  @override
  Future<void> write(String key, String value) {
    writes.add(jsonDecode(value) as Map<String, dynamic>);
    return writes.length == 1 && firstWrite != null
        ? firstWrite!.future
        : Future<void>.value();
  }
}

/// 检查资格快照三个字段，避免遗漏 wait 的边界约定。
void _expectStatus(OverlayCooldownStatus status,
    {required bool canShow, bool permanent = false, Duration? wait}) {
  expect(status.canShow, canShow);
  expect(status.permanentlyBlocked, permanent);
  expect(status.wait, wait);
}

/// 引擎补充的构建期、批次、槽位、冷却与标签回归。
void main() {
  for (final overlap in [false, true]) {
    testWidgets('构建期间登记${overlap ? '并行' : '串行'}条目，帧后展示且安全通知', (tester) async {
      final manager = Layerman();
      addTearDown(manager.dispose);
      await manager.ready();
      var shown = 0;
      var builds = 0;
      await tester.pumpWidget(ListenableBuilder(
        listenable: manager,
        builder: (_, __) {
          builds++;
          return Builder(builder: (_) {
            if (manager.recordOf(_id) == null) {
              manager.open(
                id: _id,
                mode: overlap ? OverlayMode.overlap : OverlayMode.queue,
                present: (context) {
                  shown++;
                  return _present(context);
                },
              );
              expect(shown, 0);
              expect(manager.queuedIds, contains(_id));
              expect(manager.recordOf(_id)!.phase, OverlayPhase.pending);
            }
            return const SizedBox();
          });
        },
      ));
      expect(tester.takeException(), isNull);
      expect(shown, 1);
      await tester.pump();
      expect(builds, 2);
      expect(shown, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('构建后仍暂停的并行条目等待释放', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    await tester.pumpWidget(Builder(builder: (_) {
      manager.open(id: _id, mode: OverlayMode.overlap, present: _present);
      manager.pauseAll();
      return const SizedBox();
    }));
    await manager.ready();
    expect(manager.activeIds, isEmpty);
    expect(manager.queuedIds, [_id]);
    manager.resumeAll();
    expect(manager.activeIds, [_id]);
  });

  testWidgets('构建期间重复提交与移除不会展示旧条目', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    var shown = 0;
    late OverlayTicket<Object?> old;
    await tester.pumpWidget(Builder(builder: (_) {
      old = manager.submit(
          id: _id,
          present: (c) {
            shown++;
            return _present(c);
          });
      manager.open(id: _id, present: _present);
      manager.remove(_id);
      return const SizedBox();
    }));
    expect((await old.outcome).reason, OverlayEndReason.superseded);
    expect(shown, 0);
    expect(manager.records, isEmpty);
    expect(manager.debugSlotCount, 0);
  });

  testWidgets('构建期间同 id 重开仍优先于高优先级队列', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    manager.open(id: _id, present: _present);
    manager.open(id: _high, priority: 100, present: _present);
    await tester.pumpWidget(Builder(builder: (_) {
      manager.open(id: _id, present: _present);
      expect(manager.activeIds, isEmpty);
      return const SizedBox();
    }));
    expect(manager.activeIds, [_id]);
    expect(manager.queuedIds, [_high]);
  });

  testWidgets('构建期间销毁使帧后回调静默失效', (tester) async {
    final manager = Layerman();
    var shown = 0;
    await tester.pumpWidget(Builder(builder: (_) {
      manager.open(
          id: _id,
          mode: OverlayMode.overlap,
          present: (c) {
            shown++;
            return _present(c);
          });
      manager.open(id: 'serial', present: _present);
      manager.dispose();
      return const SizedBox();
    }));
    expect(shown, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('立即展示只通知一次，清空二十条也只通知一次', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    await manager.ready();
    var notices = 0;
    manager.addListener(() => notices++);
    manager.open(id: _id, present: _present);
    expect(notices, 1);
    for (var i = 0; i < 19; i++) {
      manager.open(id: 'queued$i', present: _present);
    }
    notices = 0;
    manager.clear();
    expect(notices, 1);
    expect(manager.records, isEmpty);
    expect(manager.debugSlotCount, 0);
  });

  testWidgets('监听者重入提交时已能看到完整的外层状态', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    await manager.ready();
    var reentered = false;

    /// 重入时检查最外层提交已经完成。
    void listener() {
      expect(manager.activeIds, [_id]);
      expect(manager.recordOf(_id)!.phase, OverlayPhase.open);
      if (!reentered) {
        reentered = true;
        manager.open(id: 'nested', present: _present);
      }
    }

    manager.addListener(listener);
    manager.open(id: _id, present: _present);
    expect(manager.queuedIds, ['nested']);
    manager.removeListener(listener);
  });

  testWidgets('后端关闭推进队列的异步批次只通知一次', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    await manager.ready();
    final done = Completer<Object?>();
    manager.open(
        id: _id, present: (_) => PresentedOverlay(dismissed: done.future));
    manager.open(id: _next, present: _present);
    var notices = 0;
    final snapshots = <List<String>>[];
    manager.addListener(() {
      notices++;
      snapshots.add(manager.activeIds);
    });
    done.complete();
    await tester.pump();
    expect(notices, 1);
    expect(snapshots, [
      [_next]
    ]);
  });

  testWidgets('一百个临时槽位关闭后全部回收，配置仍保留', (tester) async {
    final manager =
        Layerman(slots: const {_slot: OverlaySlotOptions(maxQueued: 1)});
    addTearDown(manager.dispose);
    for (var i = 0; i < 100; i++) {
      manager.open(id: 'id$i', slot: 's$i', present: _present);
    }
    expect(manager.debugSlotCount, 100);
    for (var i = 0; i < 100; i++) {
      manager.close('id$i');
    }
    expect(manager.debugSlotCount, 0);
    expect(manager.slots[_slot]!.maxQueued, 1);
    manager.open(slot: _slot, present: _present);
    expect(manager.debugSlotCount, 1);
  });

  testWidgets('gap 等待槽位不能回收，完成后才回收', (tester) async {
    final manager = Layerman(gap: _tick);
    addTearDown(manager.dispose);
    manager.open(id: _id, present: _present);
    manager.close(_id);
    expect(manager.debugSlotCount, 1);
    manager.open(id: _next, present: _present);
    expect(manager.activeIds, isEmpty);
    await tester.pump(_tick);
    expect(manager.activeIds, [_next]);
    manager.close(_next);
    await tester.pump(_tick);
    expect(manager.debugSlotCount, 0);
  });

  testWidgets('条件排队和 delay 计时器保留槽位', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    manager.open(
        id: _id, when: (c) => c['ok'] == true, delay: _tick, present: _present);
    expect(manager.debugSlotCount, 1);
    manager.setContext({'ok': true});
    expect(manager.activeIds, isEmpty);
    expect(manager.debugSlotCount, 1);
    await tester.pump(_tick);
    expect(manager.activeIds, [_id]);
    manager.close(_id);
    expect(manager.debugSlotCount, 0);
  });

  testWidgets('冷却查询覆盖通过、时间等待与永久上限', (tester) async {
    var now = DateTime(2026, 1, 1, 12, 30, 30);
    final manager = Layerman(now: () => now);
    addTearDown(manager.dispose);
    await manager.ready();
    _expectStatus(manager.cooldownStatus(_id, _gapCooldown),
        canShow: true, wait: Duration.zero);
    manager.open(id: _id, cooldown: _gapCooldown, present: _present);
    _expectStatus(manager.cooldownStatus(_id, _gapCooldown),
        canShow: false, wait: const Duration(seconds: 1));
    _expectStatus(manager.cooldownStatus(_id, const OverlayCooldown(total: 1)),
        canShow: false, permanent: true);
    _expectStatus(
        manager.cooldownStatus(
            _id, const OverlayCooldown(day: 1, hour: 1, minute: 1)),
        canShow: false,
        wait: const Duration(hours: 11, minutes: 29, seconds: 30));
    now = now.add(const Duration(days: 1));
    _expectStatus(manager.cooldownStatus(_id, _gapCooldown),
        canShow: true, wait: Duration.zero);
    manager.open(
        id: 'session',
        cooldown: const OverlayCooldown(session: 1),
        present: _present,
        mode: OverlayMode.overlap);
    _expectStatus(
        manager.cooldownStatus('session', const OverlayCooldown(session: 1)),
        canShow: false,
        permanent: true);
  });

  testWidgets('hydrate 前持久化查询未知，session 仍可判断', (tester) async {
    final storage = _Storage();
    final manager = Layerman(cooldownStorage: storage);
    addTearDown(manager.dispose);
    _expectStatus(manager.cooldownStatus(_id, const OverlayCooldown(total: 0)),
        canShow: false);
    _expectStatus(
        manager.cooldownStatus(_id, const OverlayCooldown(session: 0)),
        canShow: false,
        permanent: true);
    manager.open(
        id: _id,
        mode: OverlayMode.overlap,
        cooldown: const OverlayCooldown(total: 1),
        present: _present);
    expect(manager.queuedIds, [_id]);
    storage.readResult.complete(null);
    await manager.ready();
    expect(manager.activeIds, [_id]);
    _expectStatus(manager.cooldownStatus(_id, const OverlayCooldown(total: 1)),
        canShow: false, permanent: true);
  });

  testWidgets('重置立即放行时间冷却队列，并从零重新计数', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    await manager.ready();
    manager.open(id: _id, cooldown: _gapCooldown, present: _present);
    manager.close(_id);
    manager.open(id: _id, cooldown: _gapCooldown, present: _present);
    expect(manager.queuedIds, [_id]);
    expect(manager.debugSlotCount, 1);
    manager.resetCooldown(_id);
    expect(manager.activeIds, [_id]);
    _expectStatus(manager.cooldownStatus(_id, const OverlayCooldown(total: 1)),
        canShow: false, permanent: true);
    manager.resetCooldown(_id);
    _expectStatus(manager.cooldownStatus(_id, const OverlayCooldown(total: 1)),
        canShow: true, wait: Duration.zero);
  });

  testWidgets('重置 session 后再次展示重新耗尽，清空对所有 id 生效', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    const cooldown = OverlayCooldown(session: 1);
    manager.open(id: _id, cooldown: cooldown, present: _present);
    manager.close(_id);
    manager.resetCooldown(_id);
    _expectStatus(manager.cooldownStatus(_id, cooldown),
        canShow: true, wait: Duration.zero);
    manager.open(id: _id, cooldown: cooldown, present: _present);
    _expectStatus(manager.cooldownStatus(_id, cooldown),
        canShow: false, permanent: true);
    manager.clearCooldowns();
    _expectStatus(manager.cooldownStatus(_id, cooldown),
        canShow: true, wait: Duration.zero);
  });

  testWidgets('重置持久化串行写回且保留其他 id', (tester) async {
    final storage = _Storage()..firstWrite = Completer<void>();
    storage.readResult.complete(null);
    final manager = Layerman(cooldownStorage: storage);
    addTearDown(manager.dispose);
    await manager.ready();
    for (final id in [_id, _other]) {
      manager.open(
          id: id,
          mode: OverlayMode.overlap,
          cooldown: const OverlayCooldown(total: 2),
          present: _present);
    }
    manager.resetCooldown(_id);
    expect(storage.writes.length, 1);
    storage.firstWrite!.complete();
    await tester.pump();
    expect(storage.writes.last.keys, [_other]);
    manager.clearCooldowns();
    await tester.pump();
    expect(storage.writes.last, isEmpty);
  });

  for (final clearAll in [false, true]) {
    testWidgets('hydrate 前${clearAll ? '全部清空' : '指定重置'}不恢复旧存储记录',
        (tester) async {
      final storage = _Storage();
      final manager = Layerman(cooldownStorage: storage);
      addTearDown(manager.dispose);
      if (clearAll) {
        manager.clearCooldowns();
      } else {
        manager.resetCooldown(_id);
      }
      expect(storage.writes, isEmpty);
      storage.readResult.complete(jsonEncode({
        _id: {'t': 10},
        _other: {'t': 5},
      }));
      await manager.ready();
      _expectStatus(
          manager.cooldownStatus(_id, const OverlayCooldown(total: 1)),
          canShow: true,
          wait: Duration.zero);
      expect(storage.writes.last.containsKey(_id), isFalse);
      expect(storage.writes.last.containsKey(_other), !clearAll);
    });
  }

  testWidgets('销毁后冷却重置无操作，排队槽位全部回收', (tester) async {
    final storage = _Storage()..readResult.complete(null);
    final manager = Layerman(cooldownStorage: storage);
    await manager.ready();
    manager.open(id: _id, cooldown: _gapCooldown, present: _present);
    manager.dispose();
    await tester.pump();
    final writes = storage.writes.length;
    manager.resetCooldown(_id);
    manager.clearCooldowns();
    manager.clearTag(_tag);
    expect(storage.writes.length, writes);
    expect(manager.debugSlotCount, 0);
  });

  testWidgets('按标签先移除展示和排队条目，再统一推进未匹配条目', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final shown = <String>[];
    final tickets = <OverlayTicket<Object?>>[];
    for (final id in [_id, 'queued']) {
      tickets.add(manager.submit(
          id: id,
          tags: {_tag},
          present: (c) {
            shown.add(c.id);
            return _present(c);
          }));
    }
    manager.open(id: 'keep', present: _present);
    manager.clearTag(_tag);
    expect(shown, [_id]);
    expect(manager.activeIds, ['keep']);
    for (final ticket in tickets) {
      expect((await ticket.outcome).reason, OverlayEndReason.removed);
    }
  });

  testWidgets('标签只读且复制输入，不存在标签无通知，clearWhere 可组合', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    await manager.ready();
    final tags = {_tag};
    manager.open(id: _id, tags: tags, present: _present);
    manager.open(id: _empty, present: _present);
    tags.clear();
    expect(manager.recordOf(_id)!.tags, {_tag});
    expect(() => manager.recordOf(_id)!.tags.clear(), throwsUnsupportedError);
    expect(manager.recordOf(_empty)!.tags, isEmpty);
    var notices = 0;
    manager.addListener(() => notices++);
    manager.clearTag('missing');
    expect(notices, 0);
    manager.clearWhere((r) => r.tags.contains(_tag) && r.active);
    expect(manager.activeIds, [_empty]);
    expect(notices, 1);
  });

  testWidgets('异步守卫通过后关闭和推进只发一次最终通知', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    await manager.ready();
    final guard = Completer<bool>();
    manager.open(id: _id, beforeClose: () => guard.future, present: _present);
    manager.open(id: _next, present: _present);
    var notices = 0;
    manager.addListener(() => notices++);
    manager.close(_id);
    expect(notices, 0);
    guard.complete(true);
    await tester.pump();
    expect(notices, 1);
    expect(manager.activeIds, [_next]);
  });

  testWidgets('解析跳过与后继展示合并通知，不占用解析槽位', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    await manager.ready();
    final resolved = Completer<Object?>();
    manager.open(id: _id, resolve: () => resolved.future, present: _present);
    manager.open(id: _next, present: _present);
    var notices = 0;
    manager.addListener(() => notices++);
    resolved.complete(null);
    await tester.pump();
    expect(notices, 1);
    expect(manager.activeIds, [_next]);
    expect(manager.resolvingIds, isEmpty);
  });

  testWidgets('暂停中重置冷却不能放行条目，释放 hold 只通知一次', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    await manager.ready();
    final hold = manager.hold();
    manager.open(id: _id, cooldown: _gapCooldown, present: _present);
    manager.resetCooldown(_id);
    expect(manager.activeIds, isEmpty);
    var notices = 0;
    manager.addListener(() => notices++);
    hold.release();
    expect(notices, 1);
    expect(manager.activeIds, [_id]);
    hold.release();
    expect(notices, 1);
  });

  testWidgets('暂停释放的首个后端重新暂停时，其余并行条目继续等待', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    await manager.ready();
    manager.pauseAll();
    manager.open(
        id: _id,
        mode: OverlayMode.overlap,
        present: (c) {
          manager.pauseAll();
          return _present(c);
        });
    manager.open(id: _next, mode: OverlayMode.overlap, present: _present);
    manager.resumeAll();
    expect(manager.activeIds, [_id]);
    expect(manager.queuedIds, [_next]);
    manager.resumeAll();
    expect(manager.activeIds, [_id, _next]);
  });

  testWidgets('按标签移除等待 hydrate 的并行条目，读取后不再展示', (tester) async {
    final storage = _Storage();
    final manager = Layerman(cooldownStorage: storage);
    addTearDown(manager.dispose);
    final ticket = manager.submit(
        id: _id,
        tags: {_tag},
        mode: OverlayMode.overlap,
        cooldown: _gapCooldown,
        present: _present);
    manager.clearTag(_tag);
    storage.readResult.complete(null);
    await manager.ready();
    expect(manager.activeIds, isEmpty);
    expect(manager.queuedIds, isEmpty);
    expect((await ticket.outcome).reason, OverlayEndReason.removed);
  });

  testWidgets('一次构建中的多次排队合并为一次帧后通知', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    await manager.ready();
    var notices = 0;
    manager.addListener(() => notices++);
    await tester.pumpWidget(Builder(builder: (_) {
      for (var i = 0; i < 20; i++) {
        manager.open(id: 'blocked$i', when: (_) => false, present: _present);
      }
      expect(notices, 0);
      expect(manager.queuedIds.length, 20);
      return const SizedBox();
    }));
    expect(notices, 1);
    expect(manager.activeIds, isEmpty);
  });

  testWidgets('队列已空但冷却计时器未到期的槽位继续保留', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    await manager.ready();
    manager.open(id: _id, cooldown: _gapCooldown, present: _present);
    manager.close(_id);
    manager.open(id: _id, cooldown: _gapCooldown, present: _present);
    manager.remove(_id);
    expect(manager.records, isEmpty);
    expect(manager.debugSlotCount, 1);
    await tester.pump(const Duration(seconds: 1) + _tick);
    expect(manager.debugSlotCount, 0);
  });

  testWidgets('异步守卫拒绝和异常均保留当前条目，不发状态通知', (tester) async {
    for (final fails in [false, true]) {
      final manager = Layerman();
      addTearDown(manager.dispose);
      await manager.ready();
      final guard = Completer<bool>();
      manager.open(id: _id, beforeClose: () => guard.future, present: _present);
      var notices = 0;
      manager.addListener(() => notices++);
      manager.close(_id);
      if (fails) {
        guard.completeError(StateError('guard'));
      } else {
        guard.complete(false);
      }
      await tester.pump();
      expect(manager.activeIds, [_id]);
      expect(notices, 0);
      manager.remove(_id);
      expect(notices, 1);
    }
  });
}
