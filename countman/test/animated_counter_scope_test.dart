// ignore_for_file: deprecated_member_use_from_same_package
import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 为用例提供布局、文字与 MediaQuery 环境。
Widget host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

/// 取页面里唯一的 [CounterPainter]（AnimatedCounter 的 painter 路径）。
CounterPainter painterOf(WidgetTester t) => t
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<CounterPainter>()
    .single;

/// 以固定步长推进帧，直到总时长走完。
Future<void> settle(WidgetTester t,
    {Duration total = const Duration(seconds: 2)}) async {
  const step = Duration(milliseconds: 50);
  await t.pump();
  for (var elapsed = Duration.zero; elapsed < total; elapsed += step) {
    await t.pump(step);
  }
}

void main() {
  tearDown(Countman.destroy);

  group('AnimatedCounter 接入 CounterProvider', () {
    testWidgets('Provider 的 onGroupReady / onAllComplete 对 AnimatedCounter 生效且各触发一次',
        (t) async {
      var ready = 0;
      var done = 0;
      await t.pumpWidget(host(CounterProvider(
        onGroupReady: () => ready++,
        onAllComplete: () => done++,
        child: const AnimatedCounter(
            value: 120, duration: Duration(milliseconds: 200)),
      )));
      await settle(t);
      expect(ready, 1);
      expect(done, 1);
      expect(painterOf(t).digitValues.last, 120);
    });

    testWidgets('显式 plugin 优先于 Provider 的 plugin', (t) async {
      final mine = Counter(name: 'scope-test-mine');
      Countman.use(mine);
      var mineReady = 0;
      var mineDone = 0;
      mine.addGroupListener(onReady: () => mineReady++, onDrained: () => mineDone++);
      var providerReady = 0;
      await t.pumpWidget(host(CounterProvider(
        onGroupReady: () => providerReady++,
        child: AnimatedCounter(
            plugin: mine,
            value: 50,
            duration: const Duration(milliseconds: 200)),
      )));
      await settle(t);
      expect(mineReady, 1);
      expect(mineDone, 1);
      expect(providerReady, 0);
    });

    testWidgets('没有 Provider 也没有 plugin 时落到 defaultCounter', (t) async {
      var ready = 0;
      final off = defaultCounter.addGroupListener(onReady: () => ready++);
      addTearDown(off);
      await t.pumpWidget(host(const AnimatedCounter(
          value: 80, duration: Duration(milliseconds: 200))));
      await settle(t);
      expect(ready, 1);
    });

    testWidgets('AnimatedCounterBuilder 同样走解析出的插件', (t) async {
      var done = 0;
      await t.pumpWidget(host(CounterProvider(
        onAllComplete: () => done++,
        child: const AnimatedCounterBuilder(
            value: 70, duration: Duration(milliseconds: 200)),
      )));
      await settle(t);
      expect(done, 1);
    });

    testWidgets('回弹任务也在同一个插件上，整个分组只在全部结束后通知一次', (t) async {
      var ready = 0;
      var done = 0;
      await t.pumpWidget(host(CounterProvider(
        onGroupReady: () => ready++,
        onAllComplete: () => done++,
        child: const AnimatedCounter(
            value: 120,
            duration: Duration(milliseconds: 200),
            bounceOvershoot: 0.3),
      )));
      await settle(t, total: const Duration(seconds: 3));
      expect(ready, 1);
      expect(done, 1);
    });
  });

  group('AnimatedCounter animateOnce', () {
    Widget app(bool show,
            {bool? animateOnce, bool providerOnce = true, Key? key = const ValueKey('row-1'), VoidCallback? onStart, Widget? prefix}) =>
        host(CounterProvider(
          animateOnce: providerOnce,
          child: show
              ? AnimatedCounter(
                  key: key,
                  value: 500,
                  animateOnce: animateOnce,
                  prefixWidget: prefix,
                  duration: const Duration(milliseconds: 300),
                  onAnimationStart: onStart)
              : const SizedBox(),
        ));

    testWidgets('第一次挂载动画，同 key 再次挂载直接显示终值', (t) async {
      var starts = 0;
      await t.pumpWidget(app(true, onStart: () => starts++));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(painterOf(t).digitValues.last, lessThan(500));
      await settle(t);
      expect(starts, 1);
      expect(painterOf(t).digitValues.last, 500);

      await t.pumpWidget(app(false));
      await t.pumpWidget(app(true, onStart: () => starts++));
      expect(painterOf(t).digitValues.last, 500, reason: '挂载当帧就是终值');
      await settle(t);
      expect(starts, 1, reason: '不再播放入场动画');
      expect(painterOf(t).digitValues.last, 500);
    });

    testWidgets('widget 自身 animateOnce: false 覆盖 Provider，每次挂载都播放', (t) async {
      var starts = 0;
      await t.pumpWidget(app(true, animateOnce: false, onStart: () => starts++));
      await settle(t);
      await t.pumpWidget(app(false));
      await t.pumpWidget(app(true, animateOnce: false, onStart: () => starts++));
      await settle(t);
      expect(starts, 2);
    });

    testWidgets('widget 自身 animateOnce: true 在 Provider 未开启时也生效', (t) async {
      var starts = 0;
      await t.pumpWidget(app(true, animateOnce: true, providerOnce: false, onStart: () => starts++));
      await settle(t);
      await t.pumpWidget(app(false, providerOnce: false));
      await t.pumpWidget(app(true, animateOnce: true, providerOnce: false, onStart: () => starts++));
      await settle(t);
      expect(starts, 1);
    });

    testWidgets('不同 key 互不影响', (t) async {
      var starts = 0;
      await t.pumpWidget(app(true, onStart: () => starts++));
      await settle(t);
      await t.pumpWidget(app(false));
      await t.pumpWidget(app(true, key: const ValueKey('row-2'), onStart: () => starts++));
      await settle(t);
      expect(starts, 2);
    });

    testWidgets('没有 key 时不崩溃，退化为每次都动画', (t) async {
      var starts = 0;
      await t.pumpWidget(app(true, key: null, onStart: () => starts++));
      await settle(t);
      await t.pumpWidget(app(false));
      await t.pumpWidget(app(true, key: null, onStart: () => starts++));
      await settle(t);
      expect(t.takeException(), isNull);
      expect(starts, 2);
    });

    testWidgets('没有 Provider 时 animateOnce: true 也不崩溃', (t) async {
      await t.pumpWidget(host(const AnimatedCounter(
          key: ValueKey('solo'),
          value: 10,
          animateOnce: true,
          duration: Duration(milliseconds: 100))));
      await settle(t);
      expect(t.takeException(), isNull);
      expect(painterOf(t).digitValues.last, 10);
    });

    testWidgets('入口决策向后代传播：内部的 TextCounter 也直接显示终值', (t) async {
      await t.pumpWidget(app(true, prefix: const TextCounter(to: 7)));
      await settle(t, total: const Duration(seconds: 2));
      await t.pumpWidget(app(false));
      await t.pumpWidget(app(true, prefix: const TextCounter(to: 7)));
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('入场之后的 controller 命令仍然正常动画', (t) async {
      final c = AnimatedCounterController(initialValue: 500);
      await t.pumpWidget(host(CounterProvider(
        animateOnce: true,
        child: AnimatedCounter(
            key: const ValueKey('ctl'),
            controller: c,
            duration: const Duration(milliseconds: 300)),
      )));
      await settle(t);
      c.animateTo(900);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(c.status, AnimationStatus.forward);
      await settle(t);
      expect(painterOf(t).digitValues.last, 900);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  group('减弱动画感知 MediaQuery', () {
    testWidgets('MediaQuery.disableAnimations 为 true 时直接落位', (t) async {
      final c = AnimatedCounterController();
      await t.pumpWidget(host(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: AnimatedCounter(controller: c, duration: const Duration(seconds: 2)),
      )));
      c.animateTo(100);
      await t.pump();
      expect(c.status, AnimationStatus.completed);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('MediaQuery 明确为 false 时即使平台标志为 true 也照常动画', (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final c = AnimatedCounterController();
      await t.pumpWidget(host(MediaQuery(
        data: const MediaQueryData(disableAnimations: false),
        child: AnimatedCounter(controller: c, duration: const Duration(seconds: 2)),
      )));
      c.animateTo(100);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(c.status, AnimationStatus.forward);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('运行中 MediaQuery 变化：之后的命令按新设置执行', (t) async {
      final c = AnimatedCounterController();
      Widget build(bool disable) => host(MediaQuery(
            data: MediaQueryData(disableAnimations: disable),
            child: AnimatedCounter(controller: c, duration: const Duration(seconds: 2)),
          ));
      await t.pumpWidget(build(false));
      c.animateTo(100);
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(c.status, AnimationStatus.forward);
      await t.pumpWidget(build(true));
      c.animateTo(200);
      await t.pump();
      expect(c.status, AnimationStatus.completed);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}
