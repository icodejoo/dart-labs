import 'package:countman/countman.dart';
import 'package:countman/src/widgets/animated_counter/digit_column.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 将 [child] 放入有文本方向的环境。
Widget _host(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

/// 读取 [tester] 中的计数画笔。
CounterPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<CounterPainter>()
    .single;

/// 读取 [tester] 中个位的当前动画值；[builder] 选择渲染路径。
double _units(WidgetTester tester, bool builder) => builder
    ? tester
        .widgetList<DigitColumn>(find.byType(DigitColumn))
        .last
        .animationValue
    : _painter(tester).digitValues.last;

void main() {
  tearDown(Countman.destroy);

  test('CounterTimeline 全字段 copyWith、相等性与哈希', () {
    Curve? digitCurve(int index) => Curves.easeIn;
    double interpolate(double from, double to, double t) =>
        from + (to - from) * t;
    final a = CounterTimeline(
      duration: const Duration(seconds: 1),
      curve: Curves.easeIn,
      reverseDuration: const Duration(seconds: 2),
      reverseCurve: Curves.easeOut,
      startDelay: const Duration(milliseconds: 20),
      speedMultiplier: 2,
      staggerDelay: const Duration(milliseconds: 30),
      staggerDirection: StaggerDirection.leftToRight,
      autoEaseThreshold: 500,
      curveForDigit: digitCurve,
      interpolation: interpolate,
      bounceOvershoot: 0.5,
      fast: true,
    );
    final b = CounterTimeline(
      duration: const Duration(seconds: 1),
      curve: Curves.easeIn,
      reverseDuration: const Duration(seconds: 2),
      reverseCurve: Curves.easeOut,
      startDelay: const Duration(milliseconds: 20),
      speedMultiplier: 2,
      staggerDelay: const Duration(milliseconds: 30),
      staggerDirection: StaggerDirection.leftToRight,
      autoEaseThreshold: 500,
      curveForDigit: digitCurve,
      interpolation: interpolate,
      bounceOvershoot: 0.5,
      fast: true,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.copyWith(), a);
    final variants = [
      a.copyWith(duration: Duration.zero),
      a.copyWith(curve: Curves.linear),
      a.copyWith(reverseDuration: Duration.zero),
      a.copyWith(reverseCurve: Curves.linear),
      a.copyWith(startDelay: Duration.zero),
      a.copyWith(speedMultiplier: 1),
      a.copyWith(staggerDelay: Duration.zero),
      a.copyWith(staggerDirection: StaggerDirection.rightToLeft),
      a.copyWith(autoEaseThreshold: 0),
      a.copyWith(curveForDigit: (i) => Curves.easeIn),
      a.copyWith(interpolation: (from, to, t) => from + (to - from) * t),
      a.copyWith(bounceOvershoot: 0),
      a.copyWith(fast: false),
    ];
    expect(variants, everyElement(isNot(a)));
    expect(
        a.copyWith(duration: Duration.zero).copyWith(duration: a.duration), a);
    expect(a.copyWith(fast: false).fast, isFalse);
    expect(a.copyWith(fast: false).duration, a.duration);
    expect(a.copyWith(duration: null), a);
  });

  for (final builder in [false, true]) {
    /// 用 [timeline] 和平铺参数挂载选定路径，回调记录动画起止。
    Future<void> mount(
      WidgetTester tester, {
      CounterTimeline? timeline,
      num value = 8,
      num initialValue = 0,
      Duration duration = const Duration(milliseconds: 100),
      Duration? startDelay,
      bool fast = false,
      VoidCallback? onStart,
      VoidCallback? onEnd,
    }) =>
        tester.pumpWidget(_host(builder
            ? AnimatedCounterBuilder(
                value: value,
                initialValue: initialValue,
                timeline: timeline,
                duration: duration,
                startDelay: startDelay,
                fast: fast,
                onAnimationStart: onStart,
                onAnimationEnd: onEnd)
            : AnimatedCounter(
                value: value,
                initialValue: initialValue,
                timeline: timeline,
                duration: duration,
                startDelay: startDelay,
                fast: fast,
                onAnimationStart: onStart,
                onAnimationEnd: onEnd)));

    testWidgets('timeline 时长覆盖平铺 builder=$builder', (tester) async {
      var ends = 0;
      await mount(tester,
          timeline:
              const CounterTimeline(duration: Duration(milliseconds: 400)),
          onEnd: () => ends++);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(ends, 0);
      expect(_units(tester, builder), closeTo(4, 0.1));
      await tester.pump(const Duration(milliseconds: 220));
      expect(ends, 1);
      expect(_units(tester, builder), 8);
    });

    testWidgets('timeline 空字段回退平铺时长和延迟 builder=$builder', (tester) async {
      var starts = 0;
      var ends = 0;
      await mount(tester,
          timeline: const CounterTimeline(curve: Curves.linear),
          duration: const Duration(milliseconds: 400),
          startDelay: const Duration(milliseconds: 200),
          onStart: () => starts++,
          onEnd: () => ends++);
      await tester.pump(const Duration(milliseconds: 150));
      expect(starts, 0);
      await tester.pump(const Duration(milliseconds: 50));
      expect(starts, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(ends, 0);
      expect(_units(tester, builder), closeTo(4, 0.1));
      await tester.pumpAndSettle();
      expect(ends, 1);
    });

    testWidgets('timeline 延迟和倍速生效 builder=$builder', (tester) async {
      var starts = 0;
      var ends = 0;
      await mount(tester,
          timeline: const CounterTimeline(
              startDelay: Duration(milliseconds: 400),
              duration: Duration(milliseconds: 800),
              speedMultiplier: 2),
          startDelay: const Duration(seconds: 2),
          onStart: () => starts++,
          onEnd: () => ends++);
      await tester.pump(const Duration(milliseconds: 150));
      expect(starts, 0);
      await tester.pump(const Duration(milliseconds: 50));
      expect(starts, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_units(tester, builder), closeTo(4, 0.1));
      expect(ends, 0);
      await tester.pump(const Duration(milliseconds: 220));
      expect(ends, 1);
    });

    testWidgets('timeline 更新重算，等值实例保持动画进度 builder=$builder', (tester) async {
      var starts = 0;
      void onStart() => starts++;
      await mount(tester,
          timeline:
              CounterTimeline(duration: const Duration(milliseconds: 800)),
          onStart: onStart);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final before = builder ? null : _painter(tester);
      final progress = _units(tester, builder);
      await mount(tester,
          timeline:
              CounterTimeline(duration: const Duration(milliseconds: 800)),
          onStart: onStart);
      expect(starts, 1);
      expect(_units(tester, builder), progress);
      if (!builder) expect(identical(before, _painter(tester)), isTrue);
      await mount(tester,
          timeline: const CounterTimeline(
              duration: Duration(milliseconds: 400), fast: true),
          onStart: onStart);
      expect(starts, 2);
      if (builder) {
        expect(
            tester.widget<DigitColumn>(find.byType(DigitColumn)).fast, isTrue);
      } else {
        final after = _painter(tester);
        expect(identical(before, after), isFalse);
        expect(after.shouldRepaint(before!), isTrue);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_units(tester, builder), closeTo(0.5, 0.05));
      await tester.pumpAndSettle();
    });

    testWidgets('同值切换 fast 在启动延迟期间安全更新 builder=$builder', (tester) async {
      await mount(tester, value: 12, initialValue: 12);
      await mount(tester,
          value: 12,
          initialValue: 12,
          timeline: const CounterTimeline(
              fast: true, startDelay: Duration(seconds: 1)));
      if (builder) {
        final columns =
            tester.widgetList<DigitColumn>(find.byType(DigitColumn));
        expect(columns.every((c) => c.fast && c.animationValue == 1), isTrue);
      } else {
        expect(_painter(tester).digitValues, [1, 1]);
      }
      await tester.pumpAndSettle();
    });

    testWidgets('timeline 曲线、逐位曲线与插值生效 builder=$builder', (tester) async {
      final calls = <int>[];
      await mount(tester,
          timeline: CounterTimeline(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeIn,
            curveForDigit: (index) {
              calls.add(index);
              return Curves.linear;
            },
            interpolation: (from, to, t) => from + (to - from) * t * t,
          ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(calls, contains(0));
      expect(_units(tester, builder), closeTo(2, 0.1));
      await tester.pumpAndSettle();
    });

    testWidgets('timeline 反向时长与反向曲线生效 builder=$builder', (tester) async {
      var ends = 0;
      await mount(tester,
          initialValue: 8,
          value: 0,
          timeline: const CounterTimeline(
              reverseDuration: Duration(milliseconds: 400),
              reverseCurve: Curves.easeIn),
          onEnd: () => ends++);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(ends, 0);
      expect(_units(tester, builder),
          closeTo(8 * (1 - Curves.easeIn.transform(0.5)), 0.1));
      await tester.pump(const Duration(milliseconds: 220));
      expect(ends, 1);
      expect(_units(tester, builder), 0);
    });

    testWidgets('timeline 错峰方向与倍速只缩放一次 builder=$builder', (tester) async {
      await mount(tester,
          value: 88,
          timeline: const CounterTimeline(
              duration: Duration(milliseconds: 800),
              staggerDelay: Duration(milliseconds: 400),
              staggerDirection: StaggerDirection.leftToRight,
              speedMultiplier: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final values = builder
          ? tester
              .widgetList<DigitColumn>(find.byType(DigitColumn))
              .map((c) => c.animationValue)
              .toList()
          : _painter(tester).digitValues;
      // 十位端点为整数 8，100 / 400 的进度对应 2。
      expect(values.first, closeTo(2, 0.1));
      expect(values.last, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_units(tester, builder), closeTo(22, 0.1));
      await tester.pumpAndSettle();
    });

    testWidgets('被覆盖平铺参数不重启动画，移除 timeline 恢复平铺 builder=$builder',
        (tester) async {
      var starts = 0;
      void onStart() => starts++;
      const timeline = CounterTimeline(duration: Duration(milliseconds: 400));
      await mount(tester, timeline: timeline, onStart: onStart);
      final before = builder ? null : _painter(tester);
      await mount(tester,
          timeline: timeline,
          duration: const Duration(milliseconds: 200),
          onStart: onStart);
      expect(starts, 1);
      if (!builder) expect(identical(before, _painter(tester)), isTrue);
      await mount(tester,
          duration: const Duration(milliseconds: 200), onStart: onStart);
      expect(starts, 2);
      if (!builder) {
        final after = _painter(tester);
        expect(identical(before, after), isFalse);
        expect(after.shouldRepaint(before!), isTrue);
      }
      await tester.pumpAndSettle();
    });
    testWidgets('运行中更新时间轴会取消旧调度并等待新延迟 builder=$builder', (tester) async {
      var starts = 0;
      void onStart() => starts++;
      await mount(tester,
          timeline:
              const CounterTimeline(duration: Duration(milliseconds: 800)),
          onStart: onStart);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final progress = _units(tester, builder);
      await mount(tester,
          timeline: const CounterTimeline(
              duration: Duration(milliseconds: 400),
              startDelay: Duration(milliseconds: 200)),
          onStart: onStart);
      await tester.pump(const Duration(milliseconds: 150));
      expect(starts, 1);
      expect(_units(tester, builder), progress);
      await tester.pump(const Duration(milliseconds: 50));
      expect(starts, 2);
      await tester.pumpAndSettle();
    });
  }
}
