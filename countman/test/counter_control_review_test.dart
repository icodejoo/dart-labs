import 'package:countman/countman.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// 计数器控制流与绘制配置的回归测试。
Widget _host(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

// 取出当前计数器使用的默认 CounterPainter。
CounterPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<CounterPainter>()
    .first;

CounterPainter _barePainter({
  required int fractionDigits,
  required List<double> values,
  bool hide = true,
  bool fast = false,
  List<int> fastFrom = const [],
  List<int> fastTo = const [],
  Color color = const Color(0xFF000000),
}) =>
    CounterPainter(
      repaint: ValueNotifier<int>(0),
      digitValues: values,
      style: TextStyle(fontSize: 20, color: color),
      digitSize: const Size(12, 20),
      transition: CounterTransition.slide,
      flipDirection: AxisDirection.up,
      increasing: true,
      fractionDigits: fractionDigits,
      groupingPattern: const [3],
      hideLeadingZeroes: hide,
      numeralSystem: NumeralSystem.latin,
      decimalSeparator: '.',
      fast: fast,
      fastFrom: fastFrom,
      fastTo: fastTo,
    );

void main() {
  tearDown(Countman.destroy);

  group('#9 隐藏前导零保留个位与小数', () {
    test('普通模式 0.05 保留个位 0', () {
      final p = _barePainter(fractionDigits: 2, values: [0, 0.5, 5]);
      expect(p.buildColumns().map((c) => c.index), [0, 1, 2]);
    });

    test('fast 模式 0.05 保留个位 0', () {
      final p = _barePainter(
        fractionDigits: 2,
        values: [0, 0, 0],
        fast: true,
        fastFrom: [0, 0, 0],
        fastTo: [0, 0, 5],
      );
      expect(p.buildColumns().map((c) => c.index), [0, 1, 2]);
    });

    test('首个可见列不变时复用列布局，变化时重算', () {
      final p = _barePainter(fractionDigits: 0, values: [0, 5]);
      final first = p.buildColumns();
      expect(identical(first, p.buildColumns()), isTrue);
      p.update([3, 5], true);
      expect(p.buildColumns().map((c) => c.index), [0, 1]);
    });

    test('整数部分仍隐藏前导零', () {
      final p = _barePainter(fractionDigits: 1, values: [0, 12, 1.5]);
      expect(p.buildColumns().map((c) => c.index), [1, 2]);
    });
  });

  group('#8 jumpTo 取消旧动画', () {
    testWidgets('跳转后旧任务不再回退状态', (tester) async {
      final c = AnimatedCounterController();
      var ends = 0;
      await tester.pumpWidget(_host(AnimatedCounter(
        controller: c,
        initialValue: 0,
        duration: const Duration(seconds: 1),
        onAnimationEnd: () => ends++,
      )));
      c.animateTo(1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      c.jumpTo(5);
      await tester.pump();
      final endsAfterJump = ends;
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 2));
      expect(c.status, AnimationStatus.completed);
      expect(ends, endsAfterJump);
    });
  });

  group('#16 pause/stop 覆盖延迟启动', () {
    testWidgets('startDelay 期间 stop 不再启动动画', (tester) async {
      final c = AnimatedCounterController();
      var starts = 0;
      await tester.pumpWidget(_host(AnimatedCounter(
        controller: c,
        initialValue: 0,
        startDelay: const Duration(milliseconds: 500),
        duration: const Duration(milliseconds: 200),
        onAnimationStart: () => starts++,
      )));
      c.animateTo(10);
      await tester.pump(const Duration(milliseconds: 100));
      c.stop();
      await tester.pump(const Duration(seconds: 2));
      expect(starts, 0);
    });

    testWidgets('startDelay 期间 pause 暂缓，resume 后启动', (tester) async {
      final c = AnimatedCounterController();
      var starts = 0;
      await tester.pumpWidget(_host(AnimatedCounter(
        controller: c,
        initialValue: 0,
        startDelay: const Duration(milliseconds: 500),
        duration: const Duration(milliseconds: 200),
        onAnimationStart: () => starts++,
      )));
      c.animateTo(10);
      await tester.pump(const Duration(milliseconds: 100));
      c.pause();
      await tester.pump(const Duration(seconds: 2));
      expect(starts, 0);
      c.resume();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(starts, 1);
      expect(c.status, AnimationStatus.completed);
    });
  });

  group('#17 speedMultiplier 与 stagger', () {
    testWidgets('总时长只按倍速缩放一次', (tester) async {
      final c = AnimatedCounterController();
      await tester.pumpWidget(_host(AnimatedCounter(
        controller: c,
        initialValue: 0,
        speedMultiplier: 2,
        duration: const Duration(milliseconds: 1000),
        staggerDelay: const Duration(milliseconds: 100),
      )));
      c.animateTo(100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 560));
      expect(c.status, isNot(AnimationStatus.completed));
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.status, AnimationStatus.completed);
    });
  });

  group('#18 repeat / reverse', () {
    testWidgets('repeat(reverse: true) 持续往返播放', (tester) async {
      final c = AnimatedCounterController();
      var ends = 0;
      await tester.pumpWidget(_host(AnimatedCounter(
        controller: c,
        initialValue: 0,
        duration: const Duration(milliseconds: 100),
        onAnimationEnd: () => ends++,
      )));
      c.animateTo(50);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final base = ends;
      c.repeat(reverse: true);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(ends - base, greaterThanOrEqualTo(3));
      c.stop();
      await tester.pump(const Duration(milliseconds: 50));
      final stopped = ends;
      await tester.pump(const Duration(seconds: 1));
      expect(ends, stopped);
    });

    testWidgets('fast 模式 reverse 交换端点数位', (tester) async {
      final c = AnimatedCounterController();
      await tester.pumpWidget(_host(AnimatedCounter(
        controller: c,
        initialValue: 0,
        fast: true,
        duration: const Duration(milliseconds: 100),
      )));
      c.animateTo(5);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      c.reverse();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final (cur, nxt, _) = _painter(tester).resolveColumnPhase(0);
      expect((cur, nxt), (5, 0));
    });
  });

  group('#20 减少动画', () {
    testWidgets('系统减少动画时主动画直接落位', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final c = AnimatedCounterController();
      await tester.pumpWidget(_host(AnimatedCounter(
        controller: c,
        initialValue: 0,
        duration: const Duration(seconds: 2),
      )));
      c.animateTo(100);
      await tester.pump();
      expect(c.status, AnimationStatus.completed);
    });

    testWidgets('减少动画叠加错峰时各位直接落到目标值', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final c = AnimatedCounterController();
      await tester.pumpWidget(_host(AnimatedCounter(
        controller: c,
        initialValue: 0,
        duration: const Duration(seconds: 2),
        staggerDelay: const Duration(milliseconds: 100),
      )));
      c.animateTo(55);
      await tester.pump();
      expect(c.status, AnimationStatus.completed);
      final p = _painter(tester);
      for (var i = 0; i < 2; i++) {
        expect(p.resolveColumnPhase(i).$1, 5, reason: '第 $i 位应已落位');
      }
    });
  });

  group('#10 Painter 配置变化', () {
    testWidgets('分隔符变化重建 Painter 且 shouldRepaint 为真', (tester) async {
      Widget build(String sep) => _host(AnimatedCounter(
            value: 1234567,
            initialValue: 1234567,
            thousandSeparator: sep,
          ));
      await tester.pumpWidget(build(','));
      final old = _painter(tester);
      await tester.pumpWidget(build(' '));
      final fresh = _painter(tester);
      expect(identical(old, fresh), isFalse);
      expect(fresh.thousandSeparator, ' ');
      expect(fresh.shouldRepaint(old), isTrue);
    });

    testWidgets('对齐、数字系统变化都重建', (tester) async {
      Widget build({double align = 0, NumeralSystem n = NumeralSystem.latin}) =>
          _host(AnimatedCounter(
            value: 12,
            initialValue: 12,
            numberAlignment: align,
            numeralSystem: n,
          ));
      await tester.pumpWidget(build());
      var p = _painter(tester);
      await tester.pumpWidget(build(align: 1));
      expect(identical(p, _painter(tester)), isFalse);
      p = _painter(tester);
      await tester.pumpWidget(build(align: 1, n: NumeralSystem.persian));
      expect(identical(p, _painter(tester)), isFalse);
    });
  });

  group('#11 排版一致', () {
    testWidgets('文字缩放进入绘制样式', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _host(const AnimatedCounter(
          value: 12,
          initialValue: 12,
          textStyle: TextStyle(fontSize: 20),
        )),
      ));
      expect(_painter(tester).style.fontSize, 40);
    });

    test('半透明文字色不被替换为不透明', () {
      final p = _barePainter(
        fractionDigits: 0,
        values: [1],
        color: const Color(0x80000000),
      );
      addTearDown(p.disposeCache);
      expect(p.digitColorFor(1.0).a, closeTo(0.5, 0.01));
    });
  });
}
