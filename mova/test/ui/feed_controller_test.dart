import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../support/fake_api.dart';

Future<MovaFeedItem?> _load(int index) async =>
    MovaFeedItem(source: MovaSource('https://h/$index.mp4'));

void main() {
  // 非零页的引擎打开失败后，页面状态和显式重试必须一起保留。
  for (final throws in [false, true]) {
    testWidgets('P2 非零页打开失败保留页码并可重试 throws=$throws', (t) async {
      final controller = MovaFeedPlayerController();
      addTearDown(controller.dispose);
      final api = FakeMovaApi();
      await t.pumpWidget(
        MaterialApp(
          home: MovaFeedPlayer(
            controller: controller,
            poolSize: 1,
            prefetchDepth: 0,
            engineFactory: () => api,
            loader: _load,
            errorBuilder: (_, index, error, retry) =>
                TextButton(onPressed: retry, child: Text('retry $index')),
          ),
        ),
      );
      await t.pumpAndSettle();
      final pageState = t.state(find.byType(PageView));
      if (throws) {
        api.openThrows = StateError('open');
      } else {
        api.acceptOpens = false;
      }
      controller.jumpToPage(3);
      await t.pumpAndSettle();
      expect(controller.activeApi, isNull);
      expect(t.state(find.byType(PageView)), same(pageState));
      expect(t.widget<PageView>(find.byType(PageView)).controller!.page, 3);
      expect(find.text('retry 3'), findsOneWidget);
      api.openThrows = null;
      api.acceptOpens = true;
      await t.tap(find.text('retry 3'));
      await t.pumpAndSettle();
      expect(controller.activeIndex, 3);
      expect(api.source?.uri, 'https://h/3.mp4');
      expect(find.text('retry 3'), findsNothing);
    });
  }

  // 守卫已暂停时重复的宿主 pause 仍是新的暂停决定；后续 play 仍可恢复。
  for (final background in [false, true]) {
    testWidgets('P2 守卫暂停期间宿主暂停撤销前台恢复 background=$background', (t) async {
      final controller = MovaFeedPlayerController();
      addTearDown(controller.dispose);
      var visible = true;
      Widget app() => MaterialApp(
        home: TickerMode(
          enabled: background || visible,
          child: MovaFeedPlayer(
            controller: controller,
            engineFactory: FakeMovaApi.new,
            loader: _load,
          ),
        ),
      );
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      final api = controller.activeApi! as FakeMovaApi;
      visible = false;
      if (background) {
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      expect(api.state.playbackIntent, isFalse);
      await controller.pause();
      api.calls.clear();
      visible = true;
      if (background) {
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      expect(api.calls, isNot(contains('play')));
      expect(api.state.playbackIntent, isFalse);
      await controller.play();
      await t.pumpAndSettle();
      expect(api.state.playbackIntent, isTrue);
      visible = false;
      if (background) {
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      visible = true;
      if (background) {
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
      await t.pumpWidget(app());
      await t.pumpAndSettle();
      expect(api.state.playbackIntent, isTrue);
    });
  }
  testWidgets('C14 控制器查询当前页、播放暂停与跳页', (t) async {
    final controller = MovaFeedPlayerController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);
    await t.pumpWidget(
      MaterialApp(
        home: MovaFeedPlayer(
          controller: controller,
          engineFactory: FakeMovaApi.new,
          loader: _load,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(controller.feed?.peek(0)?.source.uri, 'https://h/0.mp4');
    expect(controller.activeIndex, 0);
    final first = controller.activeApi! as FakeMovaApi;
    await controller.pause();
    expect(first.state.playbackIntent, isFalse);
    await controller.play();
    expect(first.state.playbackIntent, isTrue);
    controller.jumpToPage(1);
    await t.pumpAndSettle();
    expect(controller.activeIndex, 1);
    expect(
      (controller.activeApi as FakeMovaApi?)?.source?.uri,
      'https://h/1.mp4',
    );
    expect(first.state.playbackIntent, isFalse);
    expect(notifications, greaterThan(0));
    controller.jumpToPage(-1);
    expect(controller.activeIndex, 1);
  });

  testWidgets('C14 控制器替换与卸载解绑，控制器不持有引擎所有权', (t) async {
    final first = MovaFeedPlayerController();
    final second = MovaFeedPlayerController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget build(MovaFeedPlayerController c) => MaterialApp(
      home: MovaFeedPlayer(
        controller: c,
        engineFactory: FakeMovaApi.new,
        loader: _load,
      ),
    );
    await t.pumpWidget(build(first));
    await t.pumpAndSettle();
    final api = first.activeApi! as FakeMovaApi;
    await t.pumpWidget(build(second));
    await t.pumpAndSettle();
    expect(first.feed, isNull);
    expect(first.activeApi, isNull);
    expect(second.activeApi, same(api));
    await first.pause();
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    await t.pumpAndSettle();
    expect(second.activeApi, isNull);
    expect(second.feed, isNull);
    expect(api.calls.where((c) => c == 'dispose'), hasLength(1));
    second.jumpToPage(2);
    await second.play();
    expect(t.takeException(), isNull);
  });

  testWidgets('C14 后台暂停整条 feed，前台只恢复当前页', (t) async {
    final controller = MovaFeedPlayerController();
    addTearDown(controller.dispose);
    final fleet = <FakeMovaApi>[];
    await t.pumpWidget(
      MaterialApp(
        home: MovaFeedPlayer(
          controller: controller,
          engineFactory: () {
            final a = FakeMovaApi();
            fleet.add(a);
            return a;
          },
          loader: _load,
        ),
      ),
    );
    await t.pumpAndSettle();
    final active = controller.activeApi! as FakeMovaApi;
    for (final a in fleet) {
      a.calls.clear();
    }
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pumpAndSettle();
    expect(active.calls.where((c) => c == 'pause'), hasLength(1));
    expect(active.state.playbackIntent, isFalse);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(active.calls.where((c) => c == 'play'), hasLength(1));
    expect(
      fleet
          .where((a) => !identical(a, active))
          .every((a) => !a.calls.contains('play')),
      isTrue,
    );
  });

  testWidgets('C14 非活跃 Tab 暂停并恢复，禁用守卫后沿用池行为', (t) async {
    final controller = MovaFeedPlayerController();
    addTearDown(controller.dispose);
    var enabled = true;
    MovaAutoPauseConfig? config = const MovaAutoPauseConfig();
    Widget build() => MaterialApp(
      home: TickerMode(
        enabled: enabled,
        child: MovaFeedPlayer(
          controller: controller,
          autoPause: config,
          engineFactory: FakeMovaApi.new,
          loader: _load,
        ),
      ),
    );
    await t.pumpWidget(build());
    await t.pumpAndSettle();
    final api = controller.activeApi! as FakeMovaApi;
    api.calls.clear();
    enabled = false;
    await t.pumpWidget(build());
    await t.pumpAndSettle();
    expect(api.state.playbackIntent, isFalse);
    enabled = true;
    await t.pumpWidget(build());
    await t.pumpAndSettle();
    expect(api.state.playbackIntent, isTrue);
    config = null;
    await t.pumpWidget(build());
    await t.pumpAndSettle();
    api.calls.clear();
    enabled = false;
    await t.pumpWidget(build());
    await t.pumpAndSettle();
    expect(api.calls, isNot(contains('pause')));
  });

  testWidgets('C14 loader 失败可自定义展示且仅显式重试，不阻塞下一页', (t) async {
    final controller = MovaFeedPlayerController();
    addTearDown(controller.dispose);
    var fail = true;
    var loads = 0;
    var failedIndex = 0;
    await t.pumpWidget(
      MaterialApp(
        home: MovaFeedPlayer(
          controller: controller,
          engineFactory: FakeMovaApi.new,
          loader: (i) async {
            if (i == failedIndex) {
              loads++;
              if (fail) throw StateError('loader');
            }
            return _load(i);
          },
          errorBuilder: (context, index, error, retry) =>
              TextButton(onPressed: retry, child: Text('failed $index')),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('failed 0'), findsOneWidget);
    final count = loads;
    await t.pump();
    await t.pump();
    expect(loads, count);
    fail = false;
    await t.tap(find.text('failed 0'));
    await t.pumpAndSettle();
    expect(
      (controller.activeApi as FakeMovaApi?)?.source?.uri,
      'https://h/0.mp4',
    );
    expect(find.text('failed 0'), findsNothing);
    final previous = controller.activeApi!;
    failedIndex = 5; // 邻页 1 已预热，选择尚未缓存的页验证 loader 失败。
    fail = true;
    controller.jumpToPage(5);
    await t.pumpAndSettle();
    expect(find.text('failed 5'), findsOneWidget);
    expect(previous.state.playbackIntent, isFalse);
    controller.jumpToPage(6);
    await t.pumpAndSettle();
    expect(controller.activeIndex, 6);
    expect(t.takeException(), isNull);
  });

  testWidgets('C14 打开拒绝、抛错与播放中失败均显示单页错误并可重试', (t) async {
    for (final throws in [false, true]) {
      final controller = MovaFeedPlayerController();
      final api = FakeMovaApi()..acceptOpens = throws;
      if (throws) api.openThrows = StateError('open');
      await t.pumpWidget(
        MaterialApp(
          key: ValueKey(throws),
          home: MovaFeedPlayer(
            controller: controller,
            poolSize: 1,
            engineFactory: () => api,
            loader: (i) => i == 0 ? _load(i) : Future.value(null),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('播放失败，请重试'), findsOneWidget);
      expect(t.takeException(), isNull);
      api.acceptOpens = true;
      api.openThrows = null;
      await t.tap(find.text('重试'));
      await t.pumpAndSettle();
      expect(find.text('播放失败，请重试'), findsNothing);
      expect(controller.activeApi, same(api));
      api.emitError(StateError('runtime'));
      await t.pumpAndSettle();
      expect(find.text('播放失败，请重试'), findsOneWidget);
      api.calls.clear();
      await t.tap(find.text('重试'));
      await t.pumpAndSettle();
      expect(api.calls, contains('reload'));
      api.push(api.state.copyWith(clearError: true));
      await t.pumpAndSettle();
      expect(find.text('播放失败，请重试'), findsNothing);
      await t.pumpWidget(const MaterialApp(home: SizedBox()));
      await t.pumpAndSettle();
      controller.dispose();
    }
  });
}
