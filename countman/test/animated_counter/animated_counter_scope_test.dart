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

  group('AnimatedCounterController.runState', () {
    /// 记录 runStateListenable 每次通知时的状态。
    List<CountmanRunState> record(AnimatedCounterController c) {
      final seen = <CountmanRunState>[];
      c.runStateListenable.addListener(() => seen.add(c.runState));
      return seen;
    }

    testWidgets('初始 idle；animateTo → running → completed，各通知一次', (t) async {
      final c = AnimatedCounterController();
      final seen = record(c);
      await t.pumpWidget(host(
          AnimatedCounter(controller: c, duration: const Duration(milliseconds: 300))));
      expect(c.runState, CountmanRunState.idle);
      expect(seen, isEmpty);
      c.animateTo(100);
      await t.pump();
      expect(c.runState, CountmanRunState.running);
      await t.pump(const Duration(milliseconds: 100));
      expect(c.runState, CountmanRunState.running);
      await settle(t);
      expect(c.runState, CountmanRunState.completed);
      expect(seen, [CountmanRunState.running, CountmanRunState.completed]);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('pause / resume 依次切换，重复调用不重复通知', (t) async {
      final c = AnimatedCounterController();
      final seen = record(c);
      await t.pumpWidget(host(
          AnimatedCounter(controller: c, duration: const Duration(milliseconds: 400))));
      c.animateTo(100);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      c.pause();
      expect(c.runState, CountmanRunState.paused);
      c.pause();
      await t.pump(const Duration(milliseconds: 200));
      expect(c.runState, CountmanRunState.paused);
      c.resume();
      expect(c.runState, CountmanRunState.running);
      c.resume();
      await settle(t);
      expect(c.runState, CountmanRunState.completed);
      expect(seen, [
        CountmanRunState.running,
        CountmanRunState.paused,
        CountmanRunState.running,
        CountmanRunState.completed,
      ]);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('stop 回到 idle，之后的 animateTo 重新 running', (t) async {
      final c = AnimatedCounterController();
      final seen = record(c);
      await t.pumpWidget(host(
          AnimatedCounter(controller: c, duration: const Duration(milliseconds: 400))));
      c.animateTo(100);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      c.stop();
      expect(c.runState, CountmanRunState.idle);
      c.animateTo(200);
      await t.pump();
      expect(c.runState, CountmanRunState.running);
      expect(seen, [
        CountmanRunState.running,
        CountmanRunState.idle,
        CountmanRunState.running,
      ]);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('jumpTo 零时长命令直接 completed', (t) async {
      final c = AnimatedCounterController();
      await t.pumpWidget(host(AnimatedCounter(controller: c)));
      c.jumpTo(50);
      await t.pump();
      expect(c.runState, CountmanRunState.completed);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('restart / reverse / repeat 重新进入 running，完成后 completed', (t) async {
      final c = AnimatedCounterController();
      await t.pumpWidget(host(
          AnimatedCounter(controller: c, duration: const Duration(milliseconds: 200))));
      c.animateTo(100);
      await settle(t);
      expect(c.runState, CountmanRunState.completed);
      c.restart();
      await t.pump();
      expect(c.runState, CountmanRunState.running);
      await settle(t);
      expect(c.runState, CountmanRunState.completed);
      c.reverse();
      await t.pump();
      expect(c.runState, CountmanRunState.running);
      await settle(t);
      expect(c.runState, CountmanRunState.completed);
      c.repeat();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(c.runState, CountmanRunState.running);
      c.stop();
      expect(c.runState, CountmanRunState.idle);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('挂载即有入场动画时（controller 初值非零）已是 running', (t) async {
      final c = AnimatedCounterController(initialValue: 80);
      await t.pumpWidget(host(
          AnimatedCounter(controller: c, duration: const Duration(milliseconds: 300))));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(c.runState, CountmanRunState.running);
      await settle(t);
      expect(c.runState, CountmanRunState.completed);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('组件卸载后控制器回到 idle；之后释放控制器不抛异常', (t) async {
      final c = AnimatedCounterController();
      await t.pumpWidget(host(
          AnimatedCounter(controller: c, duration: const Duration(milliseconds: 400))));
      c.animateTo(100);
      await t.pump();
      expect(c.runState, CountmanRunState.running);
      await t.pumpWidget(const SizedBox());
      expect(c.runState, CountmanRunState.idle);
      c.dispose();
      expect(t.takeException(), isNull);
    });

    testWidgets('换绑控制器：旧的回到 idle，新的同步当前状态', (t) async {
      final a = AnimatedCounterController();
      final b = AnimatedCounterController();
      Widget app(AnimatedCounterController c) => host(AnimatedCounter(
          controller: c, duration: const Duration(milliseconds: 400)));
      await t.pumpWidget(app(a));
      a.animateTo(100);
      await t.pump();
      expect(a.runState, CountmanRunState.running);
      await t.pumpWidget(app(b));
      expect(a.runState, CountmanRunState.idle);
      expect(b.runState, CountmanRunState.running);
      await t.pumpWidget(const SizedBox());
      a.dispose();
      b.dispose();
    });

    testWidgets('AnimatedCounterBuilder 同样同步 runState', (t) async {
      final c = AnimatedCounterController();
      await t.pumpWidget(host(AnimatedCounterBuilder(
          controller: c, duration: const Duration(milliseconds: 200))));
      c.animateTo(100);
      await t.pump();
      expect(c.runState, CountmanRunState.running);
      await settle(t);
      expect(c.runState, CountmanRunState.completed);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  group('方向变色由共享 ticker 驱动', () {
    const green = Color(0xFF00C853);
    const blue = Color(0xFF2962FF);

    /// 统计测试期间所有被重建的元素个数。
    int Function() countRebuilds() {
      var n = 0;
      debugOnRebuildDirtyWidget = (element, builtOnce) => n++;
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      return () => n;
    }

    AnimatedCounter counter(AnimatedCounterController c, {Duration? fade}) =>
        AnimatedCounter(
          controller: c,
          duration: const Duration(milliseconds: 300),
          style: AnimatedCounterStyle(
            textStyle: const TextStyle(color: blue),
            increasingColor: green,
            colorFadeDuration: fade ?? const Duration(milliseconds: 800),
          ),
        );

    testWidgets('渐变期间不触发任何重建，只在开始时 build 一次', (t) async {
      final c = AnimatedCounterController();
      await t.pumpWidget(host(counter(c)));
      final rebuilds = countRebuilds();
      c.animateTo(100);
      await t.pump(); // 开始：setState 触发的那一次 build
      final atStart = rebuilds();
      expect(atStart, greaterThan(0));
      for (var i = 0; i < 60; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(rebuilds(), atStart, reason: '共约 960ms，覆盖整个滚动与渐变，期间不应有任何 build');
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('颜色从方向色渐变回原色，并在时间轴结束时精确落到原色', (t) async {
      final c = AnimatedCounterController();
      await t.pumpWidget(host(counter(c)));
      c.animateTo(100);
      await t.pump();
      await t.pump(const Duration(milliseconds: 16));
      final painter = painterOf(t);
      expect(painter.digitColorFor(1.0), green, reason: '开始时为方向色');
      await t.pump(const Duration(milliseconds: 350));
      final mid = painter.digitColorFor(1.0);
      expect(mid, isNot(green));
      expect(mid, isNot(blue));
      await t.pump(const Duration(milliseconds: 600));
      expect(painter.digitColorFor(1.0), blue, reason: '渐变结束回到原色');
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('colorFadeDuration 为 0 时立即用原色', (t) async {
      final c = AnimatedCounterController();
      await t.pumpWidget(host(counter(c, fade: Duration.zero)));
      c.animateTo(100);
      await t.pump();
      await t.pump(const Duration(milliseconds: 16));
      expect(painterOf(t).digitColorFor(1.0), blue);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('方向色任务走解析出的插件，并随分组一起结算', (t) async {
      var ready = 0;
      var done = 0;
      final c = AnimatedCounterController();
      await t.pumpWidget(host(CounterProvider(
        onGroupReady: () => ready++,
        onAllComplete: () => done++,
        child: counter(c),
      )));
      c.animateTo(100);
      await settle(t, total: const Duration(seconds: 3));
      expect(ready, 1);
      expect(done, 1, reason: '渐变任务结束后分组才算空闲');
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('渐变中途卸载不留悬挂任务也不抛异常', (t) async {
      final c = AnimatedCounterController();
      await t.pumpWidget(host(counter(c)));
      c.animateTo(100);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
      expect(t.takeException(), isNull);
      c.dispose();
    });

    testWidgets('连续两次同方向更新：新渐变从方向色重新开始', (t) async {
      final c = AnimatedCounterController();
      await t.pumpWidget(host(counter(c)));
      c.animateTo(100);
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      c.animateTo(200);
      await t.pump();
      await t.pump(const Duration(milliseconds: 16));
      expect(painterOf(t).digitColorFor(1.0), green);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('AnimatedCounterBuilder 路径同样渐变回原色', (t) async {
      final c = AnimatedCounterController();
      await t.pumpWidget(host(AnimatedCounterBuilder(
        controller: c,
        duration: const Duration(milliseconds: 200),
        style: const AnimatedCounterStyle(
          textStyle: TextStyle(color: blue),
          increasingColor: green,
          colorFadeDuration: Duration(milliseconds: 400),
        ),
      )));
      c.animateTo(5);
      await t.pump();
      await t.pump(const Duration(milliseconds: 16));
      final digit = find.byWidgetPredicate(
          (w) => w is Text && RegExp(r'^\d$').hasMatch(w.data ?? ''));
      // 数字自带交叉淡入的 alpha，这里只比较色相：开始时偏绿，结束时回到蓝。
      Color inkOf(Finder f) => t.widget<Text>(f.first).style!.color!;
      expect(inkOf(digit).g, greaterThan(inkOf(digit).b));
      await settle(t);
      expect(inkOf(find.text('5')), blue);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}
