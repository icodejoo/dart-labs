// 0.3.0：Ring/Bar 常驻 painter——60 帧内 painter / Semantics 实例不变，
// 进度经 repaint 原地更新；样式变化才更新 painter；自定义 painterBuilder 保持原有行为。

import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_clock.dart';

/// 帧间隔，60 帧约 1 秒。
const _frame = Duration(milliseconds: 16);

/// 总帧数。
const _frames = 60;

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

/// 取组件内的常驻 CustomPaint（取第一个，ring 的中心子树里没有别的 CustomPaint）。
CustomPaint _paintOf(WidgetTester tester, Type type) => tester.widget<CustomPaint>(
    find.descendant(of: find.byType(type), matching: find.byType(CustomPaint)).first);

/// 取组件内带百分比的 Semantics 部件。
Semantics _semanticsOf(WidgetTester tester, Type type) => tester.widget<Semantics>(
    find
        .descendant(
          of: find.byType(type),
          matching: find.byWidgetPredicate((w) =>
              w is Semantics && (w.properties.value?.endsWith('%') ?? false)),
        )
        .first);

/// 读取 painter 当前进度（Ring / Bar 通用）。
double _progress(CustomPainter p) =>
    p is RingPainter ? p.progress : (p as BarPainter).progress;

void main() {
  late ManualCountmanClock clock;

  setUp(() => clock = installManualClock());
  tearDown(Countman.destroy);

  /// 逐帧推进并同步手动时钟，返回每帧后 [probe] 的取值。
  Future<List<T>> runFrames<T>(WidgetTester tester, T Function() probe) async {
    final seen = <T>[];
    for (var i = 0; i < _frames; i++) {
      clock.advance(_frame);
      await tester.pump(_frame);
      seen.add(probe());
    }
    return seen;
  }

  group('计数器：RingCounter / BarCounter', () {
    for (final entry in <String, (Widget, Type)>{
      'RingCounter': (
        const RingCounter(to: 100, duration: Duration(seconds: 1), curve: Curves.linear),
        RingCounter
      ),
      'BarCounter': (
        const BarCounter(to: 100, duration: Duration(seconds: 1), curve: Curves.linear),
        BarCounter
      ),
    }.entries) {
      testWidgets('${entry.key}：60 帧内 painter 与 CustomPaint 实例不变，进度原地推进',
          (tester) async {
        await tester.pumpWidget(_host(entry.value.$1));
        await tester.pump();
        final type = entry.value.$2;
        final first = _paintOf(tester, type);
        final painter = first.painter!;
        final progress = await runFrames(tester, () {
          final current = _paintOf(tester, type);
          expect(identical(current, first), isTrue, reason: 'CustomPaint 没有被重建');
          expect(identical(current.painter, painter), isTrue, reason: 'painter 实例不变');
          return _progress(current.painter!);
        });
        expect(progress.first, greaterThan(0));
        // 60 帧 × 16ms = 0.96 秒，线性 1 秒时长下进度为 0.96。
        expect(progress.last, closeTo(0.96, 1e-9));
        for (var i = 1; i < progress.length; i++) {
          expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
        }
        // 结束后进度到 1，painter 仍是同一个实例。
        clock.advance(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(identical(_paintOf(tester, type).painter, painter), isTrue);
        expect(_progress(painter), closeTo(1, 1e-9));
      });

      testWidgets('${entry.key}：Semantics 只在整数百分比变化时重建', (tester) async {
        await tester.pumpWidget(_host(entry.value.$1));
        await tester.pump();
        final type = entry.value.$2;
        final instances = <Semantics>[];
        final values = <String>[];
        await runFrames(tester, () {
          final s = _semanticsOf(tester, type);
          if (instances.isEmpty || !identical(instances.last, s)) {
            instances.add(s);
            values.add(s.properties.value!);
          }
          return 0;
        });
        // 每个新实例对应一个不同的百分比值；每个整数百分比至多重建一次。
        expect(values.toSet().length, values.length, reason: '同一百分比不会重复重建');
        expect(values.last, '96%');
        await tester.pump(const Duration(milliseconds: 100));
        expect(_semanticsOf(tester, type).properties.value, '100%');
        expect(instances.length, lessThanOrEqualTo(101));
        // 百分比逐步递增。
        final pct = values.map((v) => int.parse(v.replaceAll('%', ''))).toList();
        for (var i = 1; i < pct.length; i++) {
          expect(pct[i], greaterThan(pct[i - 1]));
        }
      });
    }

    testWidgets('样式变化才更新 painter；无关重建复用同一个实例', (tester) async {
      final key = GlobalKey();
      Widget build(RingCounterStyle style, {int salt = 0}) => _host(
            Column(children: [
              Text('$salt'),
              RingCounter(
                key: key,
                to: 100,
                duration: const Duration(seconds: 1),
                curve: Curves.linear,
                style: style,
              ),
            ]),
          );
      await tester.pumpWidget(build(const RingCounterStyle(size: 80)));
      await tester.pump();
      final painter1 = _paintOf(tester, RingCounter).painter!;
      // 同样式、父级重建：painter 不变。
      await tester.pumpWidget(build(const RingCounterStyle(size: 80), salt: 1));
      expect(identical(_paintOf(tester, RingCounter).painter, painter1), isTrue);
      // 样式变化：新 painter，配置更新，进度保持连续。
      await advanceHalf(tester);
      final before = _progress(painter1);
      await tester.pumpWidget(
          build(const RingCounterStyle(size: 80, strokeWidth: 12, clockwise: false)));
      final painter2 = _paintOf(tester, RingCounter).painter! as RingPainter;
      expect(identical(painter2, painter1), isFalse);
      expect(painter2.strokeWidth, 12);
      expect(painter2.clockwise, isFalse);
      expect(painter2.progress, closeTo(before, 1e-9), reason: '换 painter 不丢进度');
      // 之后帧里新 painter 常驻。
      await tester.pump(_frame);
      expect(identical(_paintOf(tester, RingCounter).painter, painter2), isTrue);
    });

    testWidgets('to 变化后进度按新跨度换算', (tester) async {
      Widget build(double to) => _host(RingCounter(
          to: to, duration: const Duration(seconds: 1), curve: Curves.linear));
      await tester.pumpWidget(build(100));
      await tester.pump();
      for (var i = 0; i < 70; i++) {
        clock.advance(_frame);
        await tester.pump(_frame);
      }
      expect(_progress(_paintOf(tester, RingCounter).painter!), closeTo(1, 1e-9));
      // 目标翻倍：当前值 100 对应 50%。
      await tester.pumpWidget(build(200));
      expect(_progress(_paintOf(tester, RingCounter).painter!), closeTo(0.5, 1e-9));
    });

    testWidgets('animate-once 跳过入场时直接显示满进度', (tester) async {
      Widget page(bool show) => _host(CounterProvider(
            animateOnce: true,
            child: show
                ? const RingCounter(
                    key: ValueKey('r'),
                    to: 100,
                    duration: Duration(seconds: 1),
                  )
                : const SizedBox(),
          ));
      await tester.pumpWidget(page(true));
      await tester.pump();
      await tester.pumpWidget(page(false));
      await tester.pumpWidget(page(true));
      expect(_progress(_paintOf(tester, RingCounter).painter!), 1);
      expect(_semanticsOf(tester, RingCounter).properties.value, '100%');
    });

    testWidgets('自定义 painterBuilder 保持原有行为：随进度逐次调用', (tester) async {
      var calls = 0;
      final progresses = <double>[];
      await tester.pumpWidget(_host(RingCounter(
        to: 100,
        duration: const Duration(seconds: 1),
        curve: Curves.linear,
        painterBuilder: (context, progress) {
          calls++;
          progresses.add(progress);
          return _FakePainter(progress);
        },
      )));
      await tester.pump();
      final callsAtStart = calls;
      await runFrames(tester, () => 0);
      expect(calls, greaterThan(callsAtStart + 20));
      expect(progresses.last, closeTo(0.96, 1e-9));
      final painter = _paintOf(tester, RingCounter).painter;
      expect(painter, isA<_FakePainter>());
      // 自定义路径同样有语义百分比。
      expect(_semanticsOf(tester, RingCounter).properties.value, '96%');
    });
  });

  group('倒计时：RingCountdown / BarCountdown', () {
    for (final isRing in [true, false]) {
      final name = isRing ? 'RingCountdown' : 'BarCountdown';
      final type = isRing ? RingCountdown : BarCountdown;
      testWidgets('$name：60 帧内 painter 实例不变，进度随剩余时间原地下降', (tester) async {
        final plugin = Countdown(name: 'resident-$name', interval: 0, clock: clock);
        const to = Duration(seconds: 2);
        await tester.pumpWidget(_host(isRing
            ? RingCountdown(to: to, plugin: plugin)
            : BarCountdown(to: to, plugin: plugin)));
        await tester.pump();
        final first = _paintOf(tester, type);
        final painter = first.painter!;
        final progress = await runFrames(tester, () {
          final current = _paintOf(tester, type);
          expect(identical(current, first), isTrue);
          expect(identical(current.painter, painter), isTrue);
          return _progress(current.painter!);
        });
        expect(progress.first, lessThan(1));
        for (var i = 1; i < progress.length; i++) {
          expect(progress[i], lessThanOrEqualTo(progress[i - 1]));
        }
        // 60 帧约 0.96 秒，2 秒总时长下剩余约 52%。
        expect(progress.last, closeTo(1 - 0.96 / 2, 0.03));
      });
    }

    testWidgets('RingCountdown 默认带前导游标、锚定远端；Semantics 稳定', (tester) async {
      final plugin = Countdown(name: 'ring-thumb', interval: 0, clock: clock);
      await tester.pumpWidget(_host(
          RingCountdown(to: const Duration(seconds: 2), plugin: plugin)));
      await tester.pump();
      final painter = _paintOf(tester, RingCountdown).painter! as RingPainter;
      expect(painter.showThumb, isTrue);
      expect(painter.anchorAtEnd, isTrue);
      final semantics = _semanticsOf(tester, RingCountdown);
      clock.advance(_frame);
      await tester.pump(_frame);
      // 一帧内整数百分比可能不变：此时 Semantics 实例必须复用。
      final next = _semanticsOf(tester, RingCountdown);
      if (next.properties.value == semantics.properties.value) {
        expect(identical(next, semantics), isTrue);
      }
    });

    testWidgets('自定义 painterBuilder 保持原有行为', (tester) async {
      final plugin = Countdown(name: 'bar-custom', interval: 0, clock: clock);
      var calls = 0;
      await tester.pumpWidget(_host(BarCountdown(
        to: const Duration(seconds: 2),
        plugin: plugin,
        painterBuilder: (context, progress) {
          calls++;
          return _FakePainter(progress);
        },
      )));
      await tester.pump();
      final start = calls;
      await runFrames(tester, () => 0);
      expect(calls, greaterThan(start + 20));
      expect(_paintOf(tester, BarCountdown).painter, isA<_FakePainter>());
    });
  });
}

/// 推进约半秒。
Future<void> advanceHalf(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(_frame);
  }
}

/// 自定义 painter 占位，仅记录进度。
class _FakePainter extends CustomPainter {
  _FakePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(_FakePainter old) => old.progress != progress;
}
