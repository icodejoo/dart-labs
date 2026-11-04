import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

import 'support/manual_clock.dart';

// 0.3.0 正计时增强：起点 since/initial、上限 limit、圈速 lap。
// 全部用 ManualCountmanClock 控制时间；插件直接 tick，不依赖真实等待。

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  late ManualCountmanClock clock;

  setUp(() {
    clock = installManualClock();
  });

  /// 创建并挂载一个不依赖真实帧循环的正计时插件。
  Elapsed newPlugin({int interval = 1000}) {
    final plugin = Elapsed(name: 'elapsed-features', interval: interval);
    plugin.onAttach(CountmanContext(requestFrame: () {}));
    return plugin;
  }

  /// 推进手动时钟并以匹配的 dt 驱动一帧，返回 tick 的唤醒微秒数。
  int step(Elapsed plugin, Duration d) {
    clock.advance(d);
    return plugin.tick(Duration.zero, d);
  }

  /// 当前墙钟对应的 DateTime。
  DateTime wallNow() => DateTime.fromMicrosecondsSinceEpoch(clock.wallMicros());

  group('since / initial 起点', () {
    test('since = 现在 - 3 分钟：首帧显示 3 分钟', () {
      final plugin = newPlugin();
      TimeParts? got;
      plugin.add(ElapsedOptions(
        since: wallNow().subtract(const Duration(minutes: 3)),
        onUpdate: (p) => got = p,
      ));
      plugin.tick(Duration.zero, Duration.zero);
      expect(got!.value, const Duration(minutes: 3));
      expect(got!.minutes, 3);
    });

    test('since 按墙钟锚定：跟随 jumpWall，单调推进照常累计', () {
      final plugin = newPlugin();
      final shown = <Duration>[];
      plugin.add(ElapsedOptions(
        since: wallNow().subtract(const Duration(minutes: 3)),
        onUpdate: (p) => shown.add(p.value),
      ));
      plugin.tick(Duration.zero, Duration.zero);
      clock.jumpWall(const Duration(minutes: 1)); // 用户把系统时间调快 1 分钟
      plugin.tick(Duration.zero, Duration.zero);
      expect(shown.last, const Duration(minutes: 4));
      step(plugin, const Duration(seconds: 2));
      expect(shown.last, const Duration(minutes: 4, seconds: 2));
    });

    test('since 在未来：按 0 显示，不出现负值', () {
      final plugin = newPlugin();
      TimeParts? got;
      plugin.add(ElapsedOptions(
        since: wallNow().add(const Duration(minutes: 1)),
        onUpdate: (p) => got = p,
      ));
      plugin.tick(Duration.zero, Duration.zero);
      expect(got!.value, Duration.zero);
    });

    test('initial 从给定偏移开始，且不受 jumpWall 影响', () {
      final plugin = newPlugin();
      final shown = <Duration>[];
      plugin.add(ElapsedOptions(
        initial: const Duration(seconds: 90),
        onUpdate: (p) => shown.add(p.value),
      ));
      plugin.tick(Duration.zero, Duration.zero);
      expect(shown.single, const Duration(seconds: 90));
      clock.jumpWall(const Duration(hours: 5));
      plugin.tick(Duration.zero, Duration.zero);
      expect(shown.length, 1); // 同一桶，无更新
      step(plugin, const Duration(seconds: 10));
      expect(shown.last, const Duration(seconds: 100));
    });

    test('since 与 initial 互斥', () {
      expect(
        () => ElapsedOptions(since: DateTime(2024), initial: const Duration(seconds: 1)),
        throwsAssertionError,
      );
    });

    test('reset() 清零后改为单调钟锚定：之后 jumpWall 不再影响', () {
      final plugin = newPlugin();
      final shown = <Duration>[];
      final handle = plugin.add(ElapsedOptions(
        since: wallNow().subtract(const Duration(minutes: 3)),
        onUpdate: (p) => shown.add(p.value),
      ));
      plugin.tick(Duration.zero, Duration.zero);
      handle.reset();
      plugin.tick(Duration.zero, Duration.zero);
      expect(shown.last, Duration.zero);
      clock.jumpWall(const Duration(hours: 1));
      plugin.tick(Duration.zero, Duration.zero);
      expect(shown.last, Duration.zero);
      step(plugin, const Duration(seconds: 5));
      expect(shown.last, const Duration(seconds: 5));
    });

    test('暂停后恢复：since 任务转为单调钟计时，暂停期间不计时', () {
      final plugin = newPlugin();
      final shown = <Duration>[];
      final handle = plugin.add(ElapsedOptions(
        since: wallNow().subtract(const Duration(minutes: 3)),
        onUpdate: (p) => shown.add(p.value),
      ));
      plugin.tick(Duration.zero, Duration.zero);
      handle.pause();
      step(plugin, const Duration(minutes: 10));
      handle.resume();
      step(plugin, const Duration(seconds: 1));
      expect(shown.last, const Duration(minutes: 3, seconds: 1));
    });
  });

  group('limit 上限', () {
    test('到达 limit：最后一次更新值等于 limit，onComplete 触发一次并结束任务', () {
      final plugin = newPlugin();
      final shown = <Duration>[];
      var completed = 0;
      final handle = plugin.add(ElapsedOptions(
        limit: const Duration(seconds: 5),
        onUpdate: (p) => shown.add(p.value),
        onComplete: () => completed++,
      ));
      plugin.tick(Duration.zero, Duration.zero);
      step(plugin, const Duration(seconds: 3));
      expect(completed, 0);
      final wake = step(plugin, const Duration(seconds: 10)); // 远超 limit
      expect(shown.last, const Duration(seconds: 5));
      expect(completed, 1);
      expect(handle.isDone, isTrue);
      expect(plugin.activeTaskCount, 0);
      expect(wake, CountmanPlugin.idle);
      step(plugin, const Duration(seconds: 10));
      expect(completed, 1);
    });

    test('逐任务唤醒纳入 limit：limit 先于下一个整秒时以 limit 为准', () {
      final plugin = newPlugin();
      plugin.add(const ElapsedOptions(limit: Duration(milliseconds: 2500)));
      plugin.tick(Duration.zero, Duration.zero);
      step(plugin, const Duration(seconds: 2));
      // 下一个整秒边界在 1s 后，limit 在 0.5s 后。
      expect(plugin.tick(Duration.zero, Duration.zero), 500000);
    });

    test('limit 不是整秒时恰好在 limit 那一刻完成', () {
      final plugin = newPlugin();
      final shown = <int>[];
      var completed = 0;
      plugin.add(ElapsedOptions(
        limit: const Duration(milliseconds: 2500),
        onUpdate: (p) => shown.add(p.inMilliseconds),
        onComplete: () => completed++,
      ));
      plugin.tick(Duration.zero, Duration.zero);
      step(plugin, const Duration(milliseconds: 2499));
      expect(completed, 0);
      step(plugin, const Duration(milliseconds: 1));
      expect(completed, 1);
      expect(shown.last, 2500);
    });

    test('起点已超过 limit：首帧显示 limit 并立即完成，顺序为初值、onStart、完成', () {
      final plugin = newPlugin();
      final events = <String>[];
      plugin.add(ElapsedOptions(
        initial: const Duration(seconds: 10),
        limit: const Duration(seconds: 5),
        onUpdate: (p) => events.add('update:${p.inSeconds}'),
        onStart: () => events.add('start'),
        onComplete: () => events.add('complete'),
      ));
      plugin.tick(Duration.zero, Duration.zero);
      expect(events, ['update:5', 'start', 'complete']);
    });

    test('limit 之后 reset() 对已结束句柄无操作；重新添加任务从零开始', () {
      final plugin = newPlugin();
      var completed = 0;
      final handle = plugin.add(ElapsedOptions(
        limit: const Duration(seconds: 1),
        onComplete: () => completed++,
      ));
      plugin.tick(Duration.zero, Duration.zero);
      step(plugin, const Duration(seconds: 2));
      expect(handle.isDone, isTrue);
      handle.reset();
      expect(handle.isDone, isTrue);
      expect(completed, 1);
    });

    test('存活任务 reset() 清零后可再次到达 limit 并再次完成', () {
      final plugin = newPlugin();
      var completed = 0;
      final handle = plugin.add(ElapsedOptions(
        limit: const Duration(seconds: 5),
        onComplete: () => completed++,
      ));
      plugin.tick(Duration.zero, Duration.zero);
      step(plugin, const Duration(seconds: 4));
      handle.reset();
      step(plugin, const Duration(seconds: 4)); // 重置后才 4s，未到 limit
      expect(completed, 0);
      step(plugin, const Duration(seconds: 1));
      expect(completed, 1);
    });

    test('updateLimit 动态调整上限', () {
      final plugin = newPlugin();
      var completed = 0;
      final handle = plugin.add(ElapsedOptions(
        limit: const Duration(seconds: 100),
        onComplete: () => completed++,
      ));
      plugin.tick(Duration.zero, Duration.zero);
      step(plugin, const Duration(seconds: 3));
      handle.updateLimit(const Duration(seconds: 3));
      plugin.tick(Duration.zero, Duration.zero);
      expect(completed, 1);
    });

    test('limit 与 threshold 同时到达：先 onThreshold 再 onComplete', () {
      final plugin = newPlugin();
      final events = <String>[];
      plugin.add(ElapsedOptions(
        limit: const Duration(seconds: 2),
        threshold: const Duration(seconds: 2),
        onThreshold: () => events.add('threshold'),
        onComplete: () => events.add('complete'),
      ));
      plugin.tick(Duration.zero, Duration.zero);
      step(plugin, const Duration(seconds: 2));
      expect(events, ['threshold', 'complete']);
    });
  });

  group('lap 圈速', () {
    test('两次 lap 返回各自时长，laps 记录每圈', () {
      final plugin = newPlugin();
      final handle = plugin.add(const ElapsedOptions());
      plugin.tick(Duration.zero, Duration.zero);
      clock.advance(const Duration(seconds: 3));
      expect(handle.lap(), const Duration(seconds: 3));
      clock.advance(const Duration(seconds: 5));
      expect(handle.lap(), const Duration(seconds: 5));
      expect(handle.laps, const [Duration(seconds: 3), Duration(seconds: 5)]);
    });

    test('laps 是只读快照', () {
      final plugin = newPlugin();
      final handle = plugin.add(const ElapsedOptions());
      clock.advance(const Duration(seconds: 1));
      handle.lap();
      final snapshot = handle.laps;
      expect(() => snapshot.add(Duration.zero), throwsUnsupportedError);
      clock.advance(const Duration(seconds: 1));
      handle.lap();
      expect(snapshot.length, 1);
      expect(handle.laps.length, 2);
    });

    test('暂停期间不计入圈速', () {
      final plugin = newPlugin();
      final handle = plugin.add(const ElapsedOptions());
      plugin.tick(Duration.zero, Duration.zero);
      clock.advance(const Duration(seconds: 2));
      handle.pause();
      clock.advance(const Duration(seconds: 100));
      handle.resume();
      clock.advance(const Duration(seconds: 1));
      expect(handle.lap(), const Duration(seconds: 3));
    });

    test('暂停期间调用 lap 返回暂停前累计的本圈时长', () {
      final plugin = newPlugin();
      final handle = plugin.add(const ElapsedOptions());
      plugin.tick(Duration.zero, Duration.zero);
      clock.advance(const Duration(seconds: 2));
      handle.pause();
      clock.advance(const Duration(seconds: 50));
      expect(handle.lap(), const Duration(seconds: 2));
      expect(handle.lap(), Duration.zero);
    });

    test('reset 清空圈速，之后重新从零计圈', () {
      final plugin = newPlugin();
      final handle = plugin.add(const ElapsedOptions());
      plugin.tick(Duration.zero, Duration.zero);
      clock.advance(const Duration(seconds: 4));
      handle.lap();
      handle.reset();
      expect(handle.laps, isEmpty);
      clock.advance(const Duration(seconds: 2));
      expect(handle.lap(), const Duration(seconds: 2));
      expect(handle.laps, const [Duration(seconds: 2)]);
    });

    test('initial 起点下第一圈从起点偏移算起', () {
      final plugin = newPlugin();
      final handle = plugin.add(const ElapsedOptions(initial: Duration(seconds: 30)));
      plugin.tick(Duration.zero, Duration.zero);
      clock.advance(const Duration(seconds: 5));
      // 第一圈 = 距起点（时钟从 0 开始），即含起始偏移的 35s。
      expect(handle.lap(), const Duration(seconds: 35));
    });

    test('任务取消后 lap 返回 0 且不再记录，已记录的圈速仍可读取', () {
      final plugin = newPlugin();
      final handle = plugin.add(const ElapsedOptions());
      plugin.tick(Duration.zero, Duration.zero);
      clock.advance(const Duration(seconds: 1));
      handle.lap();
      handle.cancel();
      expect(handle.lap(), Duration.zero);
      expect(handle.laps, const [Duration(seconds: 1)]);
    });

    test('ElapsedController 未绑定：lap 返回 0，laps 为空', () {
      final controller = ElapsedController();
      expect(controller.lap(), Duration.zero);
      expect(controller.laps, isEmpty);
    });

    test('ElapsedController 绑定后转发 lap / laps', () {
      final plugin = newPlugin();
      final controller = ElapsedController();
      final handle = plugin.add(const ElapsedOptions());
      controller.attach(handle);
      plugin.tick(Duration.zero, Duration.zero);
      clock.advance(const Duration(seconds: 7));
      expect(controller.lap(), const Duration(seconds: 7));
      expect(controller.laps, const [Duration(seconds: 7)]);
    });
  });

  group('组件参数透传', () {
    testWidgets('ElapsedBuilder：since 首帧即显示已过时间，且跟随 jumpWall', (t) async {
      await t.pumpWidget(_wrap(ElapsedBuilder(
        since: wallNow().subtract(const Duration(minutes: 3)),
        builder: (_, p, __) => Text('${p.minutes}m'),
      )));
      // 首个 tick 之前就按 since 展示。
      expect(find.text('3m'), findsOneWidget);
      await t.pump();
      expect(find.text('3m'), findsOneWidget);
      clock.jumpWall(const Duration(minutes: 1));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('4m'), findsOneWidget);
      Countman.destroy();
    });

    testWidgets('ElapsedBuilder：initial 起点', (t) async {
      await t.pumpWidget(_wrap(ElapsedBuilder(
        initial: const Duration(seconds: 90),
        builder: (_, p, __) => Text('${p.totalSeconds}'),
      )));
      expect(find.text('90'), findsOneWidget);
      await t.pump();
      clock.advance(const Duration(seconds: 5));
      await t.pump(const Duration(seconds: 5));
      expect(find.text('95'), findsOneWidget);
      Countman.destroy();
    });

    testWidgets('ElapsedBuilder：limit + onComplete，reset 后从零重新开始', (t) async {
      final controller = ElapsedController();
      var completed = 0;
      await t.pumpWidget(_wrap(ElapsedBuilder(
        since: wallNow().subtract(const Duration(seconds: 10)),
        limit: const Duration(seconds: 12),
        controller: controller,
        onComplete: () => completed++,
        builder: (_, p, __) => Text('${p.totalSeconds}'),
      )));
      await t.pump();
      expect(find.text('10'), findsOneWidget);
      clock.advance(const Duration(seconds: 5));
      await t.pump(const Duration(seconds: 5));
      expect(completed, 1);
      expect(find.text('12'), findsOneWidget);

      // 结束后 reset 请求重启：从零开始，不再带 since 偏移。
      controller.reset();
      await t.pump();
      expect(find.text('0'), findsOneWidget);
      clock.advance(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('1'), findsOneWidget);
      Countman.destroy();
    });

    testWidgets('ElapsedBuilder：修改 limit 不重建任务', (t) async {
      var completed = 0;
      Widget build(Duration limit) => _wrap(ElapsedBuilder(
            limit: limit,
            onComplete: () => completed++,
            builder: (_, p, __) => Text('${p.totalSeconds}'),
          ));
      await t.pumpWidget(build(const Duration(seconds: 100)));
      await t.pump();
      clock.advance(const Duration(seconds: 4));
      await t.pump(const Duration(seconds: 4));
      expect(find.text('4'), findsOneWidget);
      await t.pumpWidget(build(const Duration(seconds: 5)));
      clock.advance(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('5'), findsOneWidget);
      expect(completed, 1);
      Countman.destroy();
    });

    testWidgets('TextElapsed：since / initial / limit / onComplete', (t) async {
      var completed = 0;
      await t.pumpWidget(_wrap(TextElapsed(
        since: wallNow().subtract(const Duration(seconds: 58)),
        limit: const Duration(seconds: 60),
        onComplete: () => completed++,
        formatter: CountdownFormat.ms,
      )));
      await t.pump();
      expect(find.text('00:58'), findsOneWidget);
      clock.advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      expect(find.text('01:00'), findsOneWidget);
      expect(completed, 1);

      await t.pumpWidget(_wrap(const TextElapsed(
        initial: Duration(seconds: 125),
        formatter: CountdownFormat.ms,
      )));
      await t.pump();
      expect(find.text('02:05'), findsOneWidget);
      Countman.destroy();
    });
  });
}
