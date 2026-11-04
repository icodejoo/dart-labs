import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

import 'support/manual_clock.dart';

// 0.3.0 倒计时增强：进度分母 total 与显示取整 rounding。
// 全部用 ManualCountmanClock 控制时间，插件直接 tick，不依赖真实等待。

/// 不绘制任何内容的画笔，仅用来从 painterBuilder 里读取进度。
class _NoopPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  late ManualCountmanClock clock;

  setUp(() {
    clock = installManualClock();
  });

  /// 创建并挂载一个不依赖真实帧循环的倒计时插件。
  Countdown newPlugin({int interval = 1000}) {
    final plugin = Countdown(name: 'features', interval: interval);
    plugin.onAttach(CountmanContext(requestFrame: () {}));
    return plugin;
  }

  /// 推进手动时钟并以匹配的 dt 驱动一帧，返回 tick 的唤醒微秒数。
  int step(Countdown plugin, Duration d) {
    clock.advance(d);
    return plugin.tick(Duration.zero, d);
  }

  group('total 进度分母', () {
    test('deadline 剩 10s、total 100s：初始 progress = 0.1', () {
      final plugin = newPlugin();
      double? progress;
      Duration? total;
      plugin.add(CountdownOptions(
        deadline: clock.wallTimeNow().add(const Duration(seconds: 10)),
        total: const Duration(seconds: 100),
        onUpdate: (p) {
          progress = p.progress;
          total = p.total;
        },
      ));
      plugin.tick(Duration.zero, Duration.zero);
      expect(progress, closeTo(0.1, 1e-9));
      expect(total, const Duration(seconds: 100));
    });

    test('duration + total 同样生效，并随时间推进下降', () {
      final plugin = newPlugin();
      final progress = <double>[];
      plugin.add(CountdownOptions(
        duration: const Duration(seconds: 10),
        total: const Duration(seconds: 100),
        onUpdate: (p) => progress.add(p.progress),
      ));
      plugin.tick(Duration.zero, Duration.zero);
      step(plugin, const Duration(seconds: 5));
      expect(progress.first, closeTo(0.1, 1e-9));
      expect(progress.last, closeTo(0.05, 1e-9));
    });

    test('未提供 total 时沿用创建时的剩余时间（初始 progress = 1）', () {
      final plugin = newPlugin();
      double? progress;
      plugin.add(CountdownOptions(
        deadline: clock.wallTimeNow().add(const Duration(seconds: 10)),
        onUpdate: (p) => progress = p.progress,
      ));
      plugin.tick(Duration.zero, Duration.zero);
      expect(progress, 1.0);
    });

    test('reset() 恢复创建时的剩余时间，total 仍是进度分母', () {
      final plugin = newPlugin();
      final parts = <int>[];
      final progress = <double>[];
      final handle = plugin.add(CountdownOptions(
        duration: const Duration(seconds: 10),
        total: const Duration(seconds: 100),
        onUpdate: (p) {
          parts.add(p.inSeconds);
          progress.add(p.progress);
        },
      ));
      plugin.tick(Duration.zero, Duration.zero);
      step(plugin, const Duration(seconds: 6)); // 剩 4s
      handle.reset();
      step(plugin, const Duration(milliseconds: 1)); // 再来一帧，渲染重置后的值
      expect(handle.remaining, greaterThan(const Duration(seconds: 9)));
      expect(progress.last, closeTo(0.1, 1e-3));
    });

    test('reset(duration:) 在固定 total 下保持分母，未固定时分母跟随新时长', () {
      final plugin = newPlugin();
      Duration? fixedTotal;
      Duration? followTotal;
      final fixed = plugin.add(CountdownOptions(
        duration: const Duration(seconds: 10),
        total: const Duration(seconds: 100),
        onUpdate: (p) => fixedTotal = p.total,
      ));
      final follow = plugin.add(CountdownOptions(
        duration: const Duration(seconds: 10),
        onUpdate: (p) => followTotal = p.total,
      ));
      plugin.tick(Duration.zero, Duration.zero);
      fixed.reset(duration: const Duration(seconds: 20));
      follow.reset(duration: const Duration(seconds: 20));
      step(plugin, const Duration(milliseconds: 1));
      expect(fixedTotal, const Duration(seconds: 100));
      expect(followTotal, const Duration(seconds: 20));
    });
  });

  group('CountdownRounding.ceil', () {
    test('剩余 9.3s 显示 10', () {
      final plugin = newPlugin();
      TimeParts? got;
      plugin.add(CountdownOptions(
        duration: const Duration(milliseconds: 9300),
        rounding: CountdownRounding.ceil,
        onUpdate: (p) => got = p,
      ));
      plugin.tick(Duration.zero, Duration.zero);
      expect(got!.totalSeconds, 10);
      expect(got!.seconds, 10);
      expect(got!.millis, 0);
    });

    test('默认 floor 行为不变：剩余 9.3s 显示 9', () {
      final plugin = newPlugin();
      TimeParts? got;
      plugin.add(CountdownOptions(
        duration: const Duration(milliseconds: 9300),
        onUpdate: (p) => got = p,
      ));
      plugin.tick(Duration.zero, Duration.zero);
      expect(got!.totalSeconds, 9);
    });

    test('剩余 0.4s 显示 1，到 0 才完成且 onComplete 恰触发一次', () {
      final plugin = newPlugin();
      final shown = <int>[];
      var completed = 0;
      plugin.add(CountdownOptions(
        duration: const Duration(milliseconds: 400),
        rounding: CountdownRounding.ceil,
        onUpdate: (p) => shown.add(p.totalSeconds),
        onComplete: () => completed++,
      ));
      plugin.tick(Duration.zero, Duration.zero);
      expect(shown, [1]);
      step(plugin, const Duration(milliseconds: 399)); // 剩 1ms，仍显示 1 且未完成
      expect(completed, 0);
      expect(shown, [1]);
      step(plugin, const Duration(milliseconds: 1)); // 剩 0
      expect(completed, 1);
      expect(shown, [1, 0]);
      step(plugin, const Duration(seconds: 1));
      expect(completed, 1);
    });

    test('显示恰在剩余跨过整秒的那一帧变化（整秒本身已属于下一档）', () {
      final plugin = newPlugin();
      final shown = <int>[];
      plugin.add(CountdownOptions(
        duration: const Duration(milliseconds: 9300),
        rounding: CountdownRounding.ceil,
        onUpdate: (p) => shown.add(p.totalSeconds),
      ));
      plugin.tick(Duration.zero, Duration.zero);
      step(plugin, const Duration(milliseconds: 299)); // 剩 9.001s
      expect(shown, [10]);
      step(plugin, const Duration(milliseconds: 1)); // 剩 9.000s
      expect(shown, [10, 9]);
      step(plugin, const Duration(milliseconds: 999)); // 剩 8.001s
      expect(shown, [10, 9]);
      step(plugin, const Duration(milliseconds: 1)); // 剩 8.000s
      expect(shown, [10, 9, 8]);
    });

    test('整秒时长：10s 初始显示 10，9.999s 仍显示 10', () {
      final plugin = newPlugin();
      final shown = <int>[];
      plugin.add(CountdownOptions(
        duration: const Duration(seconds: 10),
        rounding: CountdownRounding.ceil,
        onUpdate: (p) => shown.add(p.totalSeconds),
      ));
      plugin.tick(Duration.zero, Duration.zero);
      step(plugin, const Duration(milliseconds: 1));
      expect(shown, [10]);
      step(plugin, const Duration(milliseconds: 999));
      expect(shown, [10, 9]);
    });

    test('tick 返回的唤醒时间与取整方式一致', () {
      final ceilPlugin = newPlugin();
      ceilPlugin.add(CountdownOptions(
        duration: const Duration(milliseconds: 9300),
        rounding: CountdownRounding.ceil,
      ));
      // 剩 9.3s：显示 10，需在剩余降到 9.0s 时换档，即 300ms 之后。
      expect(ceilPlugin.tick(Duration.zero, Duration.zero), 300000);

      final floorPlugin = Countdown(name: 'floor-wake');
      floorPlugin.onAttach(CountmanContext(requestFrame: () {}));
      floorPlugin.add(const CountdownOptions(duration: Duration(milliseconds: 9300)));
      // floor：剩余降到 8.999999s 才换档，即 300ms + 1us 之后。
      expect(floorPlugin.tick(Duration.zero, Duration.zero), 300001);
    });

    test('interval 为 0 时按 1 秒取整，且每帧都发更新', () {
      final plugin = newPlugin(interval: 0);
      final shown = <int>[];
      plugin.add(CountdownOptions(
        duration: const Duration(milliseconds: 2500),
        rounding: CountdownRounding.ceil,
        onUpdate: (p) => shown.add(p.inMilliseconds),
      ));
      plugin.tick(Duration.zero, Duration.zero);
      step(plugin, const Duration(milliseconds: 600)); // 剩 1.9s
      step(plugin, const Duration(milliseconds: 100)); // 剩 1.8s
      expect(shown, [3000, 2000, 2000]);
    });

    test('interval 非整秒时按 interval 向上取整', () {
      final plugin = newPlugin(interval: 100);
      TimeParts? got;
      plugin.add(CountdownOptions(
        duration: const Duration(milliseconds: 1050),
        rounding: CountdownRounding.ceil,
        onUpdate: (p) => got = p,
      ));
      plugin.tick(Duration.zero, Duration.zero);
      expect(got!.inMilliseconds, 1100);
    });

    test('阈值与完成仍按真实剩余判定，不受取整影响', () {
      final plugin = newPlugin();
      var fired = 0;
      plugin.add(CountdownOptions(
        duration: const Duration(seconds: 10),
        rounding: CountdownRounding.ceil,
        threshold: const Duration(seconds: 5),
        onThreshold: () => fired++,
      ));
      plugin.tick(Duration.zero, Duration.zero);
      step(plugin, const Duration(milliseconds: 4999)); // 剩 5.001s
      expect(fired, 0);
      step(plugin, const Duration(milliseconds: 1)); // 剩 5.000s
      expect(fired, 1);
    });

    test('暂停期间显示值保持取整后的冻结值', () {
      final plugin = newPlugin();
      TimeParts? got;
      final handle = plugin.add(CountdownOptions(
        duration: const Duration(milliseconds: 9300),
        rounding: CountdownRounding.ceil,
        onUpdate: (p) => got = p,
      ));
      plugin.tick(Duration.zero, Duration.zero);
      step(plugin, const Duration(milliseconds: 500)); // 剩 8.8s，显示 9
      expect(got!.totalSeconds, 9);
      handle.pause();
      step(plugin, const Duration(seconds: 30));
      expect(got!.totalSeconds, 9);
      handle.resume();
      step(plugin, const Duration(milliseconds: 1));
      expect(got!.totalSeconds, 9);
    });
  });

  group('组件参数透传', () {
    tearDown(Countman.destroy);

    testWidgets('CountdownBuilder：total 与 rounding', (t) async {
      TimeParts? seen;
      await t.pumpWidget(_wrap(CountdownBuilder(
        to: const Duration(milliseconds: 9300),
        total: const Duration(seconds: 100),
        rounding: CountdownRounding.ceil,
        builder: (_, p, __) {
          seen = p;
          return Text('${p.totalSeconds}/${p.progress.toStringAsFixed(2)}');
        },
      )));
      // 首个 tick 之前也已按取整与 total 展示。
      expect(find.text('10/0.10'), findsOneWidget);
      await t.pump();
      expect(seen!.total, const Duration(seconds: 100));
      expect(find.text('10/0.10'), findsOneWidget);
      Countman.destroy();
    });

    testWidgets('CountdownBuilder：ceil 显示在剩余跨过整秒时换档', (t) async {
      await t.pumpWidget(_wrap(CountdownBuilder(
        to: const Duration(milliseconds: 9300),
        rounding: CountdownRounding.ceil,
        builder: (_, p, __) => Text('${p.totalSeconds}'),
      )));
      await t.pump();
      expect(find.text('10'), findsOneWidget);
      clock.advance(const Duration(milliseconds: 400)); // 剩 8.9s -> 9
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('9'), findsOneWidget);
      Countman.destroy();
    });

    testWidgets('TextCountdown：total 与 rounding', (t) async {
      await t.pumpWidget(_wrap(TextCountdown(
        to: const Duration(milliseconds: 9300),
        total: const Duration(seconds: 100),
        rounding: CountdownRounding.ceil,
        formatter: (p) => '${p.totalSeconds}|${p.progress.toStringAsFixed(2)}',
      )));
      await t.pump();
      expect(find.text('10|0.10'), findsOneWidget);
      Countman.destroy();
    });

    testWidgets('RingCountdown：total 与 rounding', (t) async {
      final progress = <double>[];
      await t.pumpWidget(_wrap(RingCountdown(
        to: const Duration(milliseconds: 9300),
        total: const Duration(seconds: 10),
        rounding: CountdownRounding.ceil,
        painterBuilder: (_, p) {
          progress.add(p);
          return _NoopPainter();
        },
      )));
      await t.pump();
      // ceil 后显示 10s，分母 10s => 进度 1.0；floor 则是 0.9x。
      expect(progress.last, 1.0);
      Countman.destroy();
    });

    testWidgets('BarCountdown：total 与 rounding', (t) async {
      final progress = <double>[];
      await t.pumpWidget(_wrap(BarCountdown(
        to: const Duration(milliseconds: 9300),
        total: const Duration(seconds: 100),
        rounding: CountdownRounding.ceil,
        painterBuilder: (_, p) {
          progress.add(p);
          return _NoopPainter();
        },
      )));
      await t.pump();
      expect(progress.last, closeTo(0.1, 1e-9));
      Countman.destroy();
    });

    testWidgets('DialCountdown：total 与 rounding', (t) async {
      TimeParts? seen;
      await t.pumpWidget(_wrap(DialCountdown(
        to: const Duration(milliseconds: 9300),
        total: const Duration(seconds: 100),
        rounding: CountdownRounding.ceil,
        painterBuilder: (_, parts) {
          seen = parts;
          return _NoopPainter();
        },
      )));
      await t.pump();
      expect(seen!.total, const Duration(seconds: 100));
      expect(seen!.totalSeconds, 10);
      Countman.destroy();
    });

    testWidgets('CardCountdown：total 与 rounding', (t) async {
      TimeParts? first;
      Duration? shown;
      Duration? total;
      await t.pumpWidget(_wrap(CardCountdown(
        to: const Duration(milliseconds: 9300),
        total: const Duration(seconds: 100),
        rounding: CountdownRounding.ceil,
        onTick: (p) {
          first ??= p;
          shown = p.value;
          total = p.total;
        },
      )));
      await t.pump();
      expect(shown, const Duration(seconds: 10));
      expect(total, const Duration(seconds: 100));
      expect(first, isNotNull);
      Countman.destroy();
    });
  });

  group('CountdownRounding.apply', () {
    test('floor 原样返回，ceil 按间隔向上取整，间隔为 0 时按 1 秒', () {
      expect(CountdownRounding.floor.apply(9300000, 1000), 9300000);
      expect(CountdownRounding.ceil.apply(9300000, 1000), 10000000);
      expect(CountdownRounding.ceil.apply(10000000, 1000), 10000000);
      expect(CountdownRounding.ceil.apply(1, 1000), 1000000);
      expect(CountdownRounding.ceil.apply(0, 1000), 0);
      expect(CountdownRounding.ceil.apply(-5, 1000), 0);
      expect(CountdownRounding.ceil.apply(1050000, 100), 1100000);
      expect(CountdownRounding.ceil.apply(2500000, 0), 3000000);
    });
  });
}

/// 测试辅助：当前墙钟时间，等同 `DateTime.fromMicrosecondsSinceEpoch(wallMicros())`。
extension on ManualCountmanClock {
  DateTime wallTimeNow() => DateTime.fromMicrosecondsSinceEpoch(wallMicros());
}
