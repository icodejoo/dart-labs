import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/src/overlay_manager.dart';
import 'package:layerman/src/overlay_types.dart';
import 'package:layerman/testing.dart';

/// 固定测试标签：resident。
const _resident = 'resident';

/// 固定测试标签：other。
const _other = 'other';

/// 固定测试标签：forever。
const _foreverId = 'forever';

/// 固定测试标签：timed。
const _timedId = 'timed';

/// 固定测试标签：known。
const _known = 'known';

/// 固定测试标签：占用。
const _occupied = '占用';

/// 固定测试标签：暂停。
const _paused = '暂停';

/// 固定测试标签：未读取。
const _unhydrated = '未读取';

/// 固定测试标签：提交前。
const _beforeSubmit = '提交前';

/// 固定测试标签：延迟中。
const _delayed = '延迟中';

/// 固定测试标签：暂停中。
const _held = '暂停中';

/// 固定测试标签：su。
const _suppressionKey = 'su';

/// 固定测试标签：t。
const _totalKey = 't';

/// 复用的时间边界。
const _threeHours = Duration(hours: 3);

/// 复用的时间边界。
const _halfHour = Duration(minutes: 30);

/// 复用的时间边界。
const _foreverMs = 8640000000000000;

/// 无计数上限，只接受抑制。
const _cd = OverlayCooldown();

/// 测试用固定时间单位。
const _hour = Duration(hours: 1);

/// 冷却唤醒的既有宽限。
const _cushion = Duration(milliseconds: 16);

/// 被测身份。
const _id = 'promo';

/// 常驻后端与调用计数。
class _Backend {
  /// 后端关闭信号。
  final done = Completer<String?>();

  /// 展示次数。
  int calls = 0;

  /// 展示后由测试或管理器关闭。
  PresentedOverlay<String> present(PresentContext<String> ctx) {
    calls++;
    return PresentedOverlay(
        dismissed: done.future,
        dismiss: ([value]) async {
          if (!done.isCompleted) done.complete(value);
        });
  }
}

/// 可控制读取、记录实际写入的存储。
class _Storage implements OverlayCooldownStorage {
  /// 读取完成信号。
  final readDone = Completer<String?>();

  /// 已落盘快照。
  String? value;

  /// 写入次数。
  int writes = 0;
  @override
  Future<String?> read(String key) => readDone.future;
  @override
  Future<void> write(String key, String value) async {
    this.value = value;
    writes++;
  }
}

void main() {
  test('永久抑制只拦带冷却的提交且事件完整', () async {
    final m = Layerman();
    addTearDown(m.dispose);
    await m.ready();
    final events = <OverlayEvent>[];
    final sub = m.events.listen(events.add);
    addTearDown(sub.cancel);
    m.suppress(_id);
    final b = _Backend();
    final t = m.submit<String>(id: _id, cooldown: _cd, present: b.present);
    expect(await t.result, isNull);
    expect((await t.outcome).reason, OverlayEndReason.suppressed);
    await Future<void>.value();
    expect(events.map((e) => e.type),
        [OverlayEventType.queued, OverlayEventType.ended]);
    expect(b.calls, 0);
    m.submit<String>(id: _id, present: b.present);
    expect(b.calls, 1);
  });

  for (final state in [_occupied, _paused, _unhydrated]) {
    test('排队中永久抑制立即结束：$state', () async {
      final storage = _Storage();
      final m = Layerman(cooldownStorage: storage);
      addTearDown(m.dispose);
      if (state != _unhydrated) {
        storage.readDone.complete(null);
        await m.ready();
      }
      if (state == _occupied) {
        m.submit<String>(id: _resident, present: _Backend().present);
      }
      if (state == _paused) m.pauseAll();
      final b = _Backend();
      final t = m.submit<String>(id: _id, cooldown: _cd, present: b.present);
      expect(m.queuedIds, contains(_id));
      m.suppress(_id);
      expect(m.queuedIds, isNot(contains(_id)));
      expect(m.recordOf(_id), isNull);
      expect(await t.result, isNull);
      expect((await t.outcome).reason, OverlayEndReason.suppressed);
      expect(b.calls, 0);
      if (state == _unhydrated) {
        expect(storage.writes, 0);
        storage.readDone.complete(null);
        await m.ready();
      }
      m.resetCooldown(_id);
      if (state == _occupied) m.remove(_resident);
      if (state == _paused) m.resumeAll();
      m.submit<String>(id: _id, cooldown: _cd, present: b.present);
      expect(b.calls, 1);
    });
  }

  test('限时抑制等待并自唤醒，状态到期清除', () async {
    final clock = FakeOverlayClock();
    final m = Layerman(clock: clock);
    addTearDown(m.dispose);
    await m.ready();
    m.suppress(_id, duration: _hour);
    final b = _Backend();
    m.submit<String>(id: _id, cooldown: _cd, present: b.present);
    final status = m.cooldownStatus(_id, _cd);
    expect(status.suppressed, isTrue);
    expect(status.canShow, isFalse);
    expect(status.permanentlyBlocked, isFalse);
    expect(status.wait, _hour);
    clock.advance(_halfHour);
    expect(m.cooldownStatus(_id, _cd).wait, _halfHour);
    expect(b.calls, 0);
    clock.advance(_halfHour);
    expect(m.cooldownStatus(_id, _cd).canShow, isTrue);
    expect(m.cooldownStatus(_id, _cd).suppressed, isFalse);
    clock.advance(_cushion);
    expect(b.calls, 1);
  });

  test('抑制等待与其他时间冷却取最大值', () async {
    final clock = FakeOverlayClock();
    final m = Layerman(clock: clock);
    addTearDown(m.dispose);
    await m.ready();
    const cd = OverlayCooldown(minGap: Duration(hours: 3));
    m.submit<String>(id: _id, cooldown: cd, present: _Backend().present);
    m.remove(_id);
    m.suppress(_id, duration: _hour);
    expect(m.cooldownStatus(_id, cd).wait, _threeHours);
    m.suppress(_id, duration: const Duration(hours: 4));
    expect(m.cooldownStatus(_id, cd).wait, const Duration(hours: 4));
  });

  for (final durations in <List<Duration?>>[
    [null, const Duration(days: 3)],
    [_hour, _threeHours],
    [_threeHours, _hour],
  ]) {
    test('多次抑制只延长：$durations', () async {
      final m = Layerman(clock: FakeOverlayClock());
      addTearDown(m.dispose);
      await m.ready();
      for (final d in durations) {
        m.suppress(_id, duration: d);
      }
      final s = m.cooldownStatus(_id, _cd);
      expect(s.permanentlyBlocked, durations.first == null);
      expect(s.wait, durations.first == null ? null : _threeHours);
      expect(s.suppressed, isTrue);
    });
  }

  for (final all in [false, true]) {
    test('清除抑制立即释放限时队列并允许永久身份重开：全部=$all', () async {
      final m = Layerman(clock: FakeOverlayClock());
      addTearDown(m.dispose);
      await m.ready();
      final b = _Backend();
      m.suppress(_id, duration: _hour);
      m.submit<String>(id: _id, cooldown: _cd, present: b.present);
      m.suppress(_other);
      if (all) {
        m.clearCooldowns();
      } else {
        m.resetCooldown(_id);
      }
      expect(b.calls, 1);
      expect(m.cooldownStatus(_other, _cd).suppressed, !all);
      m.remove(_id);
      m.suppress(_id);
      if (all) {
        m.clearCooldowns();
      } else {
        m.resetCooldown(_id);
      }
      final next = _Backend();
      m.submit<String>(id: _id, cooldown: _cd, present: next.present);
      expect(next.calls, 1);
    });
  }

  for (final resolving in [false, true]) {
    test('抑制不影响已激活条目：解析=$resolving', () async {
      final m = Layerman();
      addTearDown(m.dispose);
      await m.ready();
      final data = Completer<String?>();
      final b = _Backend();
      final t = m.submit<String>(
          id: _id,
          cooldown: _cd,
          resolve: resolving ? () => data.future : null,
          present: b.present);
      m.suppress(_id);
      expect(m.recordOf(_id), isNotNull);
      if (resolving) {
        data.complete('data');
        await Future<void>.value();
      }
      expect(b.calls, 1);
      b.done.complete('ok');
      expect(await t.result, 'ok');
      expect((await t.outcome).reason, OverlayEndReason.dismissedByBackend);
      final next =
          m.submit<String>(id: _id, cooldown: _cd, present: _Backend().present);
      expect((await next.outcome).reason, OverlayEndReason.suppressed);
    });
  }

  for (final permanent in [false, true]) {
    for (final phase in [_beforeSubmit, _delayed, _held]) {
      test('overlap 一次性判定抑制：永久=$permanent 时机=$phase', () async {
        final clock = FakeOverlayClock();
        final m = Layerman(clock: clock);
        addTearDown(m.dispose);
        await m.ready();
        if (phase == _held) m.pauseAll();
        if (phase == _beforeSubmit) {
          m.suppress(_id, duration: permanent ? null : _hour);
        }
        final b = _Backend();
        final t = m.submit<String>(
            id: _id,
            cooldown: _cd,
            mode: OverlayMode.overlap,
            delay: phase == _delayed ? _hour : null,
            present: b.present);
        if (phase != _beforeSubmit) {
          m.suppress(_id, duration: permanent ? null : _threeHours);
        }
        if (phase == _delayed) clock.advance(_hour);
        if (phase == _held) m.resumeAll();
        expect((await t.outcome).reason, OverlayEndReason.suppressed);
        expect(b.calls, 0);
        m.resetCooldown(_id);
        m.submit<String>(
            id: _id,
            cooldown: _cd,
            mode: OverlayMode.overlap,
            present: b.present);
        expect(b.calls, 1);
      });
    }
  }

  test('跨实例持久化抑制并门控只有 session 的提交', () async {
    final memory = MemoryCooldownStorage();
    final clock = FakeOverlayClock();
    final first = Layerman(clock: clock, cooldownStorage: memory);
    await first.ready();
    first.suppress(_foreverId);
    first.suppress(_timedId, duration: _hour);
    await Future<void>.value();
    first.dispose();
    final storage = _Storage();
    final m = Layerman(clock: clock, cooldownStorage: storage);
    addTearDown(m.dispose);
    final a = _Backend();
    final b = _Backend();
    const session = OverlayCooldown(session: 1);
    final permanent =
        m.submit<String>(id: _foreverId, cooldown: session, present: a.present);
    m.submit<String>(id: _timedId, cooldown: session, present: b.present);
    expect([a.calls, b.calls], [0, 0]);
    storage.readDone.complete(await memory.read('layerman:cooldown'));
    await m.ready();
    expect((await permanent.outcome).reason, OverlayEndReason.suppressed);
    expect(b.calls, 0);
    clock.advance(_hour + _cushion);
    expect(b.calls, 1);
  });

  for (final stored in [null, 3, -1]) {
    test('读取合并取更晚抑制并兼容旧格式：$stored', () async {
      final clock = FakeOverlayClock();
      final storage = _Storage();
      final m = Layerman(clock: clock, cooldownStorage: storage);
      addTearDown(m.dispose);
      if (stored != null) m.suppress(_id, duration: _hour);
      storage.readDone.complete(jsonEncode({
        _id: {
          _totalKey: 0,
          if (stored != null)
            _suppressionKey: stored == -1
                ? _foreverMs
                : clock.now().add(_threeHours).millisecondsSinceEpoch,
        }
      }));
      await m.ready();
      final s = m.cooldownStatus(_id, _cd);
      expect(s.suppressed, stored != null);
      expect(s.permanentlyBlocked, stored == -1);
      expect(
          s.wait,
          stored == -1
              ? null
              : stored == null
                  ? Duration.zero
                  : _threeHours);
      if (stored != null) {
        final json = jsonDecode(storage.value!) as Map;
        expect(
            (json[_id] as Map)[_suppressionKey],
            stored == -1
                ? _foreverMs
                : clock.now().add(_threeHours).millisecondsSinceEpoch);
      }
    });
  }

  test('所有冷却等待读取而无冷却立即展示，已知永久状态仍可查询', () async {
    final storage = _Storage();
    final m = Layerman(cooldownStorage: storage);
    addTearDown(m.dispose);
    const session = OverlayCooldown(session: 1);
    final a = _Backend();
    final b = _Backend();
    m.submit<String>(id: _id, cooldown: session, present: a.present);
    m.submit<String>(id: 'manual', slot: _other, present: b.present);
    expect([a.calls, b.calls], [0, 1]);
    expect(m.cooldownStatus(_id, session).wait, isNull);
    expect(m.cooldownStatus(_id, session).canShow, isFalse);
    m.suppress(_known);
    final known = m.cooldownStatus(_known, session);
    expect(known.suppressed, isTrue);
    expect(known.permanentlyBlocked, isTrue);
    expect(
        m
            .cooldownStatus('zero', const OverlayCooldown(session: 0))
            .permanentlyBlocked,
        isTrue);
    storage.readDone.complete(null);
    await m.ready();
    expect(a.calls, 1);
  });

  test('抑制原因优先于永久上限，条件失败仍是 dropped', () async {
    final m = Layerman();
    addTearDown(m.dispose);
    await m.ready();
    m.suppress(_id);
    for (final conditions in [true, false]) {
      final t = m.submit<String>(
          id: _id,
          cooldown: const OverlayCooldown(total: 0),
          mode: OverlayMode.overlap,
          when: (_) => conditions,
          present: _Backend().present);
      expect((await t.outcome).reason,
          conditions ? OverlayEndReason.suppressed : OverlayEndReason.dropped);
    }
  });

  test('本地更晚或永久抑制不会被读取的较早记录缩短', () async {
    for (final forever in [false, true]) {
      final clock = FakeOverlayClock();
      final storage = _Storage();
      final m = Layerman(clock: clock, cooldownStorage: storage);
      addTearDown(m.dispose);
      m.suppress(_id, duration: forever ? null : _threeHours);
      storage.readDone.complete(jsonEncode({
        _id: {
          _suppressionKey: clock.now().add(_hour).millisecondsSinceEpoch,
        }
      }));
      await m.ready();
      final status = m.cooldownStatus(_id, _cd);
      expect(status.permanentlyBlocked, forever);
      expect(status.wait, forever ? null : _threeHours);
    }
  });

  test('重复限时抑制从本次时钟计时，缩短请求保留原截止点', () async {
    final clock = FakeOverlayClock();
    final m = Layerman(clock: clock);
    addTearDown(m.dispose);
    await m.ready();
    m.suppress(_id, duration: _threeHours);
    clock.advance(_hour);
    m.suppress(_id, duration: _hour);
    expect(m.cooldownStatus(_id, _cd).wait, const Duration(hours: 2));
    m.suppress(_id, duration: _threeHours);
    expect(m.cooldownStatus(_id, _cd).wait, _threeHours);
  });

  test('只有 session 的展示不写计数，suppress 仍持久化', () async {
    final storage = _Storage()..readDone.complete(null);
    final m = Layerman(cooldownStorage: storage);
    addTearDown(m.dispose);
    await m.ready();
    m.submit<String>(
        id: _id,
        cooldown: const OverlayCooldown(session: 1),
        present: _Backend().present);
    expect(storage.writes, 0);
    m.suppress(_id);
    expect(storage.writes, 1);
    expect((jsonDecode(storage.value!) as Map)[_id][_totalKey], 0);
  });

  for (final all in [false, true]) {
    test('读取前清除抑制的墓碑不会被旧记录恢复：全部=$all', () async {
      final storage = _Storage();
      final m = Layerman(cooldownStorage: storage);
      addTearDown(m.dispose);
      m.suppress(_id);
      if (all) {
        m.clearCooldowns();
      } else {
        m.resetCooldown(_id);
      }
      storage.readDone.complete(jsonEncode({
        _id: {_suppressionKey: _foreverMs}
      }));
      await m.ready();
      expect(m.cooldownStatus(_id, _cd).suppressed, isFalse);
      final b = _Backend();
      m.submit<String>(id: _id, cooldown: _cd, present: b.present);
      expect(b.calls, 1);
    });
  }

  test('零或负抑制时长断言，销毁后无操作', () async {
    final m = Layerman();
    await m.ready();
    expect(
        () => m.suppress(_id, duration: Duration.zero), throwsAssertionError);
    expect(() => m.suppress(_id, duration: const Duration(seconds: -1)),
        throwsAssertionError);
    m.dispose();
    expect(() => m.suppress(_id), returnsNormally);
    expect(() => m.suppress(_id, duration: Duration.zero), returnsNormally);
  });
}
