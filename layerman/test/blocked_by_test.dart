import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/src/overlay_manager.dart';
import 'package:layerman/src/overlay_types.dart';
import 'package:layerman/testing.dart';

/// 固定测试身份或分支：m1。
const _firstModal = 'm1';

/// 固定测试身份或分支：m2。
const _secondModal = 'm2';

/// 固定测试身份或分支：current。
const _current = 'current';

/// 固定测试身份或分支：normal。
const _normal = 'normal';

/// 固定测试身份或分支：replace。
const _replacement = 'replace';

/// 固定测试身份或分支：old。
const _old = 'old';

/// 固定测试身份或分支：new。
const _new = 'new';

/// 固定测试身份或分支：serial。
const _serial = 'serial';

/// 固定测试身份或分支：overlap。
const _overlap = 'overlap';

/// 固定测试身份或分支：释放。
const _released = '释放';

/// 固定测试身份或分支：条件。
const _conditionChanged = '条件';

/// 固定测试身份或分支：移除。
const _removed = '移除';

/// 固定测试身份或分支：same。
const _same = 'same';

/// 固定测试身份或分支：priority。
const _priority = 'priority';

/// 固定测试身份或分支：a。
const _a = 'a';

/// 固定测试身份或分支：b。
const _b = 'b';

/// 固定测试身份或分支：banner。
const _banner = 'banner';

/// 固定测试身份或分支：unknown。
const _unknown = 'unknown';

/// 固定测试身份或分支：delayed。
const _delayed = 'delayed';

/// 固定测试身份或分支：condition。
const _unmet = 'condition';

/// 固定测试身份或分支：suppressed。
const _suppressed = 'suppressed';

/// 固定测试身份或分支：broken。
const _broken = 'broken';

/// 固定阻塞来源。
const _modal = 'modal';

/// 固定受阻槽位。
const _toast = 'toast';

/// 时间边界。
const _tick = Duration(seconds: 1);

/// 复用的单向配置。
const _options = {
  _toast: OverlaySlotOptions(blockedBy: {_modal})
};

/// 独立后端，观察激活与关闭。
class _Backend {
  /// 后端自行结束的信号。
  final done = Completer<int?>();

  /// 展示次数。
  int calls = 0;

  /// 管理器关闭请求次数。
  int dismisses = 0;

  /// 定向关闭适配器。
  PresentedOverlay<int> present(PresentContext<int> ctx) {
    calls++;
    return PresentedOverlay(
        visible: Future<void>.value(),
        dismissed: done.future,
        dismiss: ([value]) async {
          dismisses++;
          if (!done.isCompleted) done.complete(value);
        });
  }
}

/// build 中执行真实操作，检查帧后激活。
class _DuringBuild extends StatelessWidget {
  /// 保存单次构建回调。
  const _DuringBuild(this.run);

  /// 测试操作。
  final VoidCallback run;
  @override
  Widget build(BuildContext context) {
    run();
    return const SizedBox.shrink();
  }
}

void main() {
  for (final path in ['close', '后端', 'remove']) {
    test('基本阻塞与解除路径：$path，未配置槽位独立展示', () async {
      final clock = FakeOverlayClock();
      final m = Layerman(clock: clock, slots: _options);
      addTearDown(m.dispose);
      await m.ready();
      final modal = _Backend();
      m.submit<int>(
          id: _modal,
          slot: _modal,
          exitDuration: _tick,
          present: modal.present);
      final toast = _Backend();
      m.submit<int>(id: _toast, slot: _toast, present: toast.present);
      final independent = _Backend();
      m.submit<int>(id: 'free', slot: 'free', present: independent.present);
      expect(toast.calls, 0);
      expect(independent.calls, 1);
      if (path == 'close') m.close(_modal);
      if (path == '后端') modal.done.complete(1);
      if (path == 'remove') m.remove(_modal);
      await Future<void>.value();
      if (path != 'remove') {
        expect(toast.calls, 0);
        clock.advance(_tick);
      }
      expect(toast.calls, 1);
    });
  }

  test('解析占用会阻塞，gap 与排队不占用', () async {
    final clock = FakeOverlayClock();
    final m = Layerman(clock: clock, slots: _options, gap: _tick);
    addTearDown(m.dispose);
    await m.ready();
    final data = Completer<int?>();
    final modal = _Backend();
    m.submit<int>(
        id: _modal,
        slot: _modal,
        resolve: () => data.future,
        present: modal.present);
    final toast = _Backend();
    m.submit<int>(id: _toast, slot: _toast, present: toast.present);
    expect(toast.calls, 0);
    m.submit<int>(id: 'next', slot: _modal, present: _Backend().present);
    data.complete(1);
    await Future<void>.value();
    expect(modal.calls, 1);
    expect(toast.calls, 0);
    m.remove(_modal);
    expect(toast.calls, 1);
    expect(m.recordOf('next')!.active, isFalse);
  });

  test('多个 overlap 都离开才解除，等待容器不算占用', () async {
    final clock = FakeOverlayClock();
    final m = Layerman(clock: clock, slots: _options);
    addTearDown(m.dispose);
    await m.ready();
    for (final id in [_firstModal, _secondModal]) {
      m.submit<int>(
          id: id,
          slot: _modal,
          mode: OverlayMode.overlap,
          present: _Backend().present);
    }
    final b = _Backend();
    m.submit<int>(id: _toast, slot: _toast, present: b.present);
    m.remove(_firstModal);
    expect(b.calls, 0);
    m.remove(_secondModal);
    expect(b.calls, 1);
    m.remove(_toast);
    m.submit<int>(
        id: _delayed,
        slot: _modal,
        mode: OverlayMode.overlap,
        delay: _tick,
        present: _Backend().present);
    final next = _Backend();
    m.submit<int>(id: _toast, slot: _toast, present: next.present);
    expect(next.calls, 1);
  });

  test('受阻 replace 不抢占现有条目，解除后排在最前', () async {
    final m = Layerman(slots: _options);
    addTearDown(m.dispose);
    await m.ready();
    final current = _Backend();
    m.submit<int>(id: _current, slot: _toast, present: current.present);
    m.submit<int>(id: _modal, slot: _modal, present: _Backend().present);
    m.submit<int>(
        id: _normal, slot: _toast, priority: 99, present: _Backend().present);
    final replacer = _Backend();
    m.submit<int>(
        id: _replacement,
        slot: _toast,
        mode: OverlayMode.replace,
        present: replacer.present);
    expect(current.dismisses, 0);
    expect(m.isShowing(_current), isTrue);
    m.remove(_current);
    expect(replacer.calls, 0);
    m.remove(_modal);
    expect(replacer.calls, 1);
    expect(m.queuedIds, [_normal]);
  });

  test('回归：阻塞来源 replace 交接不能让 toast 插入', () async {
    final m = Layerman(slots: _options);
    addTearDown(m.dispose);
    await m.ready();
    m.submit<int>(id: _old, slot: _modal, present: _Backend().present);
    final b = _Backend();
    m.submit<int>(id: _toast, slot: _toast, present: b.present);
    m.submit<int>(
        id: _new,
        slot: _modal,
        mode: OverlayMode.replace,
        present: _Backend().present);
    expect(b.calls, 0);
    expect(m.isShowing(_new), isTrue);
    m.remove(_new);
    expect(b.calls, 1);
  });

  test('已展示与已提交解析均不被后来阻塞影响，duration 正常', () async {
    final clock = FakeOverlayClock();
    final m = Layerman(clock: clock, slots: _options);
    addTearDown(m.dispose);
    await m.ready();
    final data = Completer<int?>();
    final b = _Backend();
    m.submit<int>(
        id: _toast,
        slot: _toast,
        duration: _tick,
        resolve: () => data.future,
        present: b.present);
    m.submit<int>(id: _modal, slot: _modal, present: _Backend().present);
    data.complete(1);
    await Future<void>.value();
    expect(b.calls, 1);
    expect(b.dismisses, 0);
    clock.advance(_tick);
    expect(b.dismisses, 1);
    await Future<void>.value();
    expect(m.recordOf(_toast), isNull);
  });

  for (final change in [_released, _conditionChanged, _removed]) {
    test('overlap 持有与解除重判：$change', () async {
      final m = Layerman(slots: _options);
      addTearDown(m.dispose);
      await m.ready();
      var allowed = true;
      m.submit<int>(id: _modal, slot: _modal, present: _Backend().present);
      final b = _Backend();
      final t = m.submit<int>(
          id: _toast,
          slot: _toast,
          mode: OverlayMode.overlap,
          when: (_) => allowed,
          present: b.present);
      expect(m.queuedIds, contains(_toast));
      expect(b.calls, 0);
      if (change == _conditionChanged) allowed = false;
      if (change == _removed) m.remove(_toast);
      m.remove(_modal);
      expect(b.calls, change == _released ? 1 : 0);
      if (change != _released) {
        expect(
            (await t.outcome).reason,
            change == _conditionChanged
                ? OverlayEndReason.dropped
                : OverlayEndReason.removed);
      }
    });
  }

  test('解除时暂停继续持有，恢复后释放串行和 overlap', () async {
    final m = Layerman(slots: _options);
    addTearDown(m.dispose);
    await m.ready();
    m.submit<int>(id: _modal, slot: _modal, present: _Backend().present);
    final a = _Backend();
    final b = _Backend();
    m.submit<int>(id: _serial, slot: _toast, present: a.present);
    m.submit<int>(
        id: _overlap,
        slot: _toast,
        mode: OverlayMode.overlap,
        present: b.present);
    m.pauseAll();
    m.remove(_modal);
    expect([a.calls, b.calls], [0, 0]);
    m.resumeAll();
    expect([a.calls, b.calls], [1, 1]);
  });

  testWidgets('构建期间解除推迟到帧后', (tester) async {
    final m = Layerman(slots: _options);
    addTearDown(m.dispose);
    await tester.pump();
    m.submit<int>(id: _modal, slot: _modal, present: _Backend().present);
    final a = _Backend();
    final b = _Backend();
    m.submit<int>(id: _serial, slot: _toast, present: a.present);
    m.submit<int>(
        id: _overlap,
        slot: _toast,
        mode: OverlayMode.overlap,
        present: b.present);
    await tester.pumpWidget(_DuringBuild(() {
      m.remove(_modal);
      expect([a.calls, b.calls], [0, 0]);
    }));
    expect([a.calls, b.calls], [1, 1]);
  });

  test('appear delay 到点受阻，解除立即激活且不重计延迟', () async {
    final clock = FakeOverlayClock();
    final m = Layerman(clock: clock, slots: _options);
    addTearDown(m.dispose);
    await m.ready();
    final b = _Backend();
    m.submit<int>(id: _toast, slot: _toast, delay: _tick, present: b.present);
    m.submit<int>(id: _modal, slot: _modal, present: _Backend().present);
    clock.advance(_tick);
    expect(b.calls, 0);
    m.remove(_modal);
    expect(b.calls, 1);
  });

  test('受阻 replace 保留 gap 和 appear delay', () async {
    for (final gap in [false, true]) {
      final clock = FakeOverlayClock();
      final m = Layerman(
          clock: clock, slots: _options, gap: gap ? _tick : Duration.zero);
      addTearDown(m.dispose);
      await m.ready();
      if (gap) {
        m.submit<int>(id: _old, slot: _toast, present: _Backend().present);
        m.remove(_old);
      } else {
        m.submit<int>(
            id: _delayed,
            slot: _toast,
            delay: _tick,
            present: _Backend().present);
      }
      m.submit<int>(id: _modal, slot: _modal, present: _Backend().present);
      final b = _Backend();
      m.submit<int>(
          id: _replacement,
          slot: _toast,
          mode: OverlayMode.replace,
          present: b.present);
      m.remove(_modal);
      expect(b.calls, 0);
      clock.advance(_tick);
      expect(b.calls, 1);
    }
  });

  test('受阻同 id 接管优先于更高优先级队列', () async {
    final m = Layerman(slots: _options);
    addTearDown(m.dispose);
    await m.ready();
    m.submit<int>(id: _same, slot: _toast, present: _Backend().present);
    m.submit<int>(
        id: _priority,
        slot: _toast,
        priority: 100,
        present: _Backend().present);
    m.submit<int>(id: _modal, slot: _modal, present: _Backend().present);
    final b = _Backend();
    m.submit<int>(id: _same, slot: _toast, present: b.present);
    expect(b.calls, 0);
    m.remove(_modal);
    expect(b.calls, 1);
    expect(m.queuedIds, [_priority]);
  });

  test('互相阻塞先激活者占用，离开后另一方继续', () async {
    for (final first in [_a, _b]) {
      final m = Layerman(slots: const {
        _a: OverlaySlotOptions(blockedBy: {_b}),
        _b: OverlaySlotOptions(blockedBy: {_a}),
      });
      addTearDown(m.dispose);
      await m.ready();
      final second = first == _a ? _b : _a;
      m.submit<int>(id: first, slot: first, present: _Backend().present);
      final b = _Backend();
      m.submit<int>(id: second, slot: second, present: b.present);
      expect(b.calls, 0);
      m.remove(first);
      expect(b.calls, 1);
    }
  });

  test('阻塞期间 expireAfter 和 maxQueued 继续生效', () async {
    final clock = FakeOverlayClock();
    final m = Layerman(clock: clock, slots: const {
      _toast: OverlaySlotOptions(blockedBy: {_modal}, maxQueued: 1),
    });
    addTearDown(m.dispose);
    await m.ready();
    m.submit<int>(id: _modal, slot: _modal, present: _Backend().present);
    final first =
        m.submit<int>(id: 'first', slot: _toast, present: _Backend().present);
    final second = m.submit<int>(
        id: 'second',
        slot: _toast,
        priority: 1,
        expireAfter: _tick,
        present: _Backend().present);
    expect((await first.outcome).reason, OverlayEndReason.queueFull);
    clock.advance(_tick);
    expect((await second.outcome).reason, OverlayEndReason.queueExpired);
    m.remove(_modal);
    expect(m.queuedIds, isEmpty);
  });

  test('不存在来源无效果，自己阻塞自己断言，配置复制可变集合', () async {
    expect(
        () => Layerman(slots: const {
              _a: OverlaySlotOptions(blockedBy: {_a})
            }),
        throwsAssertionError);
    final blockers = {_modal};
    final m = Layerman(slots: {
      _toast: OverlaySlotOptions(blockedBy: blockers),
      _unknown: const OverlaySlotOptions(blockedBy: {'missing'}),
    });
    addTearDown(m.dispose);
    await m.ready();
    blockers.clear();
    m.submit<int>(id: _modal, slot: _modal, present: _Backend().present);
    final a = _Backend();
    final b = _Backend();
    m.submit<int>(id: _toast, slot: _toast, present: a.present);
    m.submit<int>(id: _unknown, slot: _unknown, present: b.present);
    expect([a.calls, b.calls], [0, 1]);
    m.remove(_modal);
    expect(a.calls, 1);
  });

  test('多级阻塞逐级解除', () async {
    final m = Layerman(slots: const {
      ..._options,
      _banner: OverlaySlotOptions(blockedBy: {_toast}),
    });
    addTearDown(m.dispose);
    await m.ready();
    m.submit<int>(id: _modal, slot: _modal, present: _Backend().present);
    final toast = _Backend();
    m.submit<int>(id: _toast, slot: _toast, present: toast.present);
    // toast 还未占用，因此先用条件保留 banner；解除时再提交。
    m.remove(_modal);
    final banner = _Backend();
    m.submit<int>(id: _banner, slot: _banner, present: banner.present);
    expect(toast.calls, 1);
    expect(banner.calls, 0);
    m.remove(_toast);
    expect(banner.calls, 1);
  });

  test('阻塞来源仅等待 appear delay 或冷却时不占用', () async {
    for (final delay in [false, true]) {
      final clock = FakeOverlayClock();
      final m = Layerman(clock: clock, slots: _options);
      addTearDown(m.dispose);
      await m.ready();
      if (!delay) m.suppress(_modal, duration: _tick);
      m.submit<int>(
          id: _modal,
          slot: _modal,
          delay: delay ? _tick : null,
          cooldown: delay ? null : const OverlayCooldown(),
          present: _Backend().present);
      final b = _Backend();
      m.submit<int>(id: _toast, slot: _toast, present: b.present);
      expect(b.calls, 1);
      expect(m.recordOf(_modal)!.active, isFalse);
    }
  });

  test('被阻塞的 overlap 仍先按条件和冷却执行一次性丢弃', () async {
    final m = Layerman(slots: _options);
    addTearDown(m.dispose);
    await m.ready();
    m.submit<int>(id: _modal, slot: _modal, present: _Backend().present);
    m.suppress(_suppressed);
    for (final id in [_unmet, _suppressed]) {
      final b = _Backend();
      final t = m.submit<int>(
          id: id,
          slot: _toast,
          mode: OverlayMode.overlap,
          when: (_) => id != _unmet,
          cooldown: const OverlayCooldown(),
          present: b.present);
      expect(m.recordOf(id), isNull);
      expect(
          (await t.outcome).reason,
          id == _unmet
              ? OverlayEndReason.dropped
              : OverlayEndReason.suppressed);
      expect(b.calls, 0);
    }
  });

  test('overlap 解析也占用阻塞来源', () async {
    final m = Layerman(slots: _options);
    addTearDown(m.dispose);
    await m.ready();
    final data = Completer<int?>();
    m.submit<int>(
        id: _modal,
        slot: _modal,
        mode: OverlayMode.overlap,
        resolve: () => data.future,
        present: _Backend().present);
    final b = _Backend();
    m.submit<int>(id: _toast, slot: _toast, present: b.present);
    expect(b.calls, 0);
    data.complete(null);
    await Future<void>.value();
    expect(b.calls, 1);
  });

  test('解除来源不会重判无关 slot 的推模式条件', () async {
    final m = Layerman(slots: _options);
    addTearDown(m.dispose);
    await m.ready();
    var pass = false;
    final b = _Backend();
    m.submit<int>(
        id: 'unrelated', slot: 'free', when: (_) => pass, present: b.present);
    m.submit<int>(id: _modal, slot: _modal, present: _Backend().present);
    pass = true;
    m.remove(_modal);
    expect(b.calls, 0);
    m.setContext({});
    expect(b.calls, 1);
  });

  test('解除时只重排因阻塞而等待的 slot，未受阻条目的推模式条件不被重判', () async {
    final m = Layerman(slots: _options);
    addTearDown(m.dispose);
    await m.ready();
    var pass = false;
    final b = _Backend();
    // toast 条目在 modal 出现前提交：当时未受阻，只因条件不满足而等待。
    m.submit<int>(
        id: _unmet, slot: _toast, when: (_) => pass, present: b.present);
    m.submit<int>(id: _modal, slot: _modal, present: _Backend().present);
    pass = true;
    m.remove(_modal);
    expect(b.calls, 0);
    m.setContext({});
    expect(b.calls, 1);
  });

  for (final kind in ['i', 'j', 'k']) {
    test('反向不变量 $kind 人为破坏后抛错', () async {
      final m = Layerman();
      await m.ready();
      if (kind == 'i') m.pauseAll();
      m.submit<int>(
          id: _broken,
          cooldown: kind == 'i' ? const OverlayCooldown() : null,
          mode: kind == 'k' ? OverlayMode.overlap : OverlayMode.queue,
          present: _Backend().present);
      m.debugCheckInvariants();
      expect(
          () => m.debugCorruptInvariant(kind, _broken),
          throwsA(isA<StateError>()
              .having((e) => e.message, '编号', contains('不变量 $kind'))));
      expect(
          m.debugCheckInvariants,
          throwsA(isA<StateError>()
              .having((e) => e.message, '编号', contains('不变量 $kind'))));
      m.dispose();
    });
  }
}
