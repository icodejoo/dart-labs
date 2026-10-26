import 'package:countman/countman.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// 本批组件回归以真实重建验证动态配置与插件拥有权。
Widget host(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    Countman.destroy();
    StartScheduler.instance.groupBatchSize.clear();
  });

  for (final family in ['counter', 'countdown', 'elapsed']) {
    regressionWidgetTest('#6 two owned $family providers coexist with defaults',
        (tester) async {
      Widget provider() {
        switch (family) {
          case 'counter':
            return CounterProvider(
                onGroupReady: () {},
                child: Builder(builder: (c) {
                  CountmanScope.maybeOf<Counter>(c)!
                      .plugin!
                      .add(const CounterOptions(to: 1));
                  return const SizedBox();
                }));
          case 'countdown':
            return CountdownProvider(
                onGroupReady: () {},
                child: Builder(builder: (c) {
                  CountmanScope.maybeOf<Countdown>(c)!.plugin!.add(
                      const CountdownOptions(duration: Duration(seconds: 1)));
                  return const SizedBox();
                }));
          default:
            return ElapsedProvider(
                onGroupReady: () {},
                child: Builder(builder: (c) {
                  CountmanScope.maybeOf<Elapsed>(c)!
                      .plugin!
                      .add(const ElapsedOptions());
                  return const SizedBox();
                }));
        }
      }

      switch (family) {
        case 'counter':
          counter(const CounterOptions(to: 1));
        case 'countdown':
          countdown(const CountdownOptions(duration: Duration(seconds: 1)));
        case 'elapsed':
          elapsed(const ElapsedOptions());
      }
      await tester.pumpWidget(host(Column(children: [provider(), provider()])));
      expect(tester.takeException(), isNull);
      expect(Countman.pluginCount, 3);
      await tester.pumpWidget(const SizedBox());
      expect(Countman.pluginCount, 1);
    });
  }

  regressionWidgetTest(
      '#12 callback update and plugin replacement detach old subscription',
      (tester) async {
    final a = Counter(name: 'a');
    final b = Counter(name: 'b');
    var old = 0;
    var current = 0;
    Widget provider(Counter p, VoidCallback ready) => CounterProvider(
        plugin: p, onGroupReady: ready, child: const SizedBox());
    await tester.pumpWidget(provider(a, () => old++));
    await tester.pumpWidget(provider(a, () => current++));
    a.add(const CounterOptions(to: 1)).cancel();
    expect(old, 0);
    expect(current, 1);
    await tester.pumpWidget(provider(b, () => current++));
    a.add(const CounterOptions(to: 1)).cancel();
    expect(current, 1);
    b.add(const CounterOptions(to: 1)).cancel();
    expect(current, 2);
  });

  regressionWidgetTest(
      '#12 shared plugin subscriptions and legacy callback are independent',
      (tester) async {
    final p = Counter();
    var legacy = 0;
    var first = 0;
    var second = 0;
    p.onFirstEnqueued = () => legacy++;
    Widget tree(bool both) => Column(children: [
          if (both)
            CounterProvider(
                key: const ValueKey('a'),
                plugin: p,
                onGroupReady: () => first++,
                child: const SizedBox()),
          CounterProvider(
              key: const ValueKey('b'),
              plugin: p,
              onGroupReady: () => second++,
              child: const SizedBox()),
        ]);
    await tester.pumpWidget(tree(true));
    p.add(const CounterOptions(to: 1)).cancel();
    expect([legacy, first, second], [1, 1, 1]);
    await tester.pumpWidget(tree(false));
    p.add(const CounterOptions(to: 1)).cancel();
    expect([legacy, first, second], [2, 1, 2]);
  });

  regressionWidgetTest(
      'architecture 2 owned groups unregister and release batch settings',
      (tester) async {
    late Counter owned;
    await tester.pumpWidget(CounterProvider(
        onGroupReady: () {},
        child: Builder(builder: (c) {
          owned = CountmanScope.maybeOf<Counter>(c)!.plugin!;
          StartScheduler.instance.groupBatchSize[owned] = 2;
          return const SizedBox();
        })));
    expect(Countman.pluginCount, 1);
    await tester.pumpWidget(const SizedBox());
    expect(Countman.pluginCount, 0);
    expect(StartScheduler.instance.groupBatchSize.containsKey(owned), isFalse);
    expect(() => owned.add(const CounterOptions(to: 1)), throwsStateError);
  });

  for (final family in ['countdown', 'elapsed']) {
    regressionWidgetTest(
        '#13 $family callbacks and threshold update without resetting time',
        (tester) async {
      var now = DateTime(2024);
      var mono = Duration.zero;
      final oldMono = elapsedClock;
      countdownClock = () => now;
      elapsedClock = () => mono;
      addTearDown(() {
        countdownClock = DateTime.now;
        elapsedClock = oldMono;
      });
      final cd = Countdown(interval: 0);
      final el = Elapsed(interval: 0);
      final cc = CountdownController();
      final ec = ElapsedController();
      var old = 0;
      var threshold = 0;
      var pause = 0;
      var complete = 0;
      Widget build(bool updated) {
        if (family == 'countdown') {
          return CountdownBuilder(
              plugin: cd,
              controller: cc,
              duration: const Duration(seconds: 10),
              threshold: updated ? const Duration(seconds: 7) : null,
              onThreshold: updated ? () => threshold++ : () => old++,
              onPause: updated ? () => pause++ : () => old++,
              onComplete: updated ? () => complete++ : () => old++,
              builder: (_, p, child) => const SizedBox());
        }
        return ElapsedBuilder(
            plugin: el,
            controller: ec,
            threshold: updated ? const Duration(seconds: 3) : null,
            onThreshold: updated ? () => threshold++ : () => old++,
            onPause: updated ? () => pause++ : () => old++,
            builder: (_, p, child) => const SizedBox());
      }

      await tester.pumpWidget(build(false));
      now = now.add(const Duration(seconds: 3));
      mono += const Duration(seconds: 3);
      await tester.pumpWidget(build(true));
      await tester.pump(const Duration(milliseconds: 10));
      expect(threshold, 1);
      if (family == 'countdown') {
        expect(cc.remaining, const Duration(seconds: 7));
        cc.pause();
        cc.resume();
        now = now.add(const Duration(seconds: 8));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));
        expect(complete, 1);
      } else {
        expect(ec.elapsed, const Duration(seconds: 3));
        ec.pause();
      }
      expect(pause, 1);
      expect(old, 0);
    });
  }

  regressionWidgetTest(
      'architecture 2 independent unuse preserves borrowed groups and defaults',
      (tester) async {
    // 注销只按实例生效，重复注销幂等，默认实例可独立重建。
    final a = defaultCounter;
    final b = defaultCountdown;
    a.add(const CounterOptions(to: 1));
    b.add(const CountdownOptions(duration: Duration(seconds: 10)));
    expect(Countman.unuse(Counter()), isFalse);
    expect(Countman.pluginCount, 2);
    expect(Countman.unuse(a), isTrue);
    expect(Countman.unuse(a), isFalse);
    expect(Countman.pluginCount, 1);
    expect(identical(defaultCountdown, b), isTrue);
    expect(identical(defaultCounter, a), isFalse);
    defaultCounter.add(const CounterOptions(to: 2));
    expect(Countman.pluginCount, 2);
  });

  regressionWidgetTest(
      'architecture 2 unuse releases queued starts only for its group',
      (tester) async {
    // 分组注销同时移除待启动闭包，其他分组照常执行。
    final a = Counter(name: 'a');
    final b = Counter(name: 'b');
    Countman.use(a);
    Countman.use(b);
    final scheduler = StartScheduler.instance;
    scheduler.groupBatchSize[a] = 1;
    scheduler.groupBatchSize[b] = 1;
    var aStarts = 0;
    var bStarts = 0;
    scheduler.enqueue(() => aStarts++, tag: Object(), group: a);
    scheduler.enqueue(() => bStarts++, tag: Object(), group: b);
    expect(Countman.unuse(a), isTrue);
    await tester.pump();
    expect(aStarts, 0);
    expect(bStarts, 1);
    expect(scheduler.groupBatchSize.containsKey(a), isFalse);
    expect(scheduler.groupBatchSize[b], 1);
  });

  regressionWidgetTest(
      '#12 adding callbacks later creates and releases an owned group',
      (tester) async {
    // 初始仅样式的 Provider 后续增加事件时，也应获得可用的自建分组。
    Widget tree(bool callbacks) => CounterProvider(
        onGroupReady: callbacks ? () {} : null, child: const SizedBox());
    await tester.pumpWidget(tree(false));
    expect(Countman.pluginCount, 0);
    await tester.pumpWidget(tree(true));
    expect(Countman.pluginCount, 1);
    await tester.pumpWidget(const SizedBox());
    expect(Countman.pluginCount, 0);
  });

  regressionWidgetTest(
      '#14 simultaneous target controller and plugin replacement detaches old controller',
      (tester) async {
    // 同时更新截止、插件与控制器时，旧绑定不能再控制新任务。
    final a = Countdown(name: 'a');
    final b = Countdown(name: 'b');
    final ca = CountdownController();
    final cb = CountdownController();
    await tester.pumpWidget(host(CardCountdown(
        to: const Duration(seconds: 10), plugin: a, controller: ca)));
    await tester.pumpWidget(host(CardCountdown(
        to: const Duration(seconds: 20), plugin: b, controller: cb)));
    expect(ca.isDone, isTrue);
    expect(a.activeTaskCount, 0);
    expect(b.activeTaskCount, 1);
    ca.cancel();
    expect(b.activeTaskCount, 1);
    expect(cb.remaining.inSeconds, inInclusiveRange(19, 20));
    cb.cancel();
    expect(b.activeTaskCount, 0);
  });

  regressionWidgetTest(
      '#14 card migrates controllers and plugins preserving paused remaining',
      (tester) async {
    var now = DateTime(2024);
    countdownClock = () => now;
    addTearDown(() => countdownClock = DateTime.now);
    final a = Countdown(name: 'a', interval: 0);
    final b = Countdown(name: 'b', interval: 0);
    final ca = CountdownController();
    final cb = CountdownController();
    Widget card(Countdown p, CountdownController c) => host(CardCountdown(
        to: const Duration(seconds: 10), plugin: p, controller: c));
    await tester.pumpWidget(card(a, ca));
    now = now.add(const Duration(seconds: 3));
    ca.pause();
    await tester.pumpWidget(card(a, cb));
    expect(ca.isDone, isTrue);
    expect(cb.isPaused, isTrue);
    ca.cancel();
    expect(a.activeTaskCount, 1);
    await tester.pumpWidget(card(b, cb));
    expect(a.activeTaskCount, 0);
    expect(b.activeTaskCount, 1);
    expect(cb.remaining, const Duration(seconds: 7));
    expect(cb.isPaused, isTrue);
    cb.cancel();
    expect(b.activeTaskCount, 0);
  });
}

// 外部借用组在测试结束时显式停帧，避免测试框架先于 tearDown 检查调度残留。
void regressionWidgetTest(String name, WidgetTesterCallback callback) {
  testWidgets(name, (tester) async {
    try {
      await callback(tester);
    } finally {
      Countman.stop();
    }
  });
}
