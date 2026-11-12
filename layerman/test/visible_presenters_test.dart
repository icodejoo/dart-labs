import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';

/// 不使用 ModalRoute 组件树的自定义路由，必须显式提供可见回报。
class _BareRoute extends TransitionRoute<void> {
  /// 自定义测试路由不响应返回手势。
  @override
  bool get popGestureEnabled => false;

  /// 本测试无需遮挡其它路由。
  @override
  bool get opaque => false;

  /// 避免测试依赖路由动画时长。
  @override
  Duration get transitionDuration => Duration.zero;

  /// 构建最小自定义路由内容。
  @override
  Iterable<OverlayEntry> createOverlayEntries() => [
        OverlayEntry(builder: (_) => const SizedBox()),
      ];
}

/// 返回待测的三种内置路由 presenter。
Present<void> _present(
        int kind, GlobalKey<NavigatorState> key, WidgetBuilder builder) =>
    switch (kind) {
      0 => DialogManager(key)<void>((ctx, close) => Builder(builder: builder)),
      1 => BottomSheetManager(key)<void>(
          (ctx, close) => Builder(builder: builder)),
      _ => (_) => presentRoute(
          key.currentState!, MaterialPageRoute<void>(builder: builder)),
    };

/// 验证内置路由及组件首帧确认。
void main() {
  testWidgets('自定义 TransitionRoute 无信号时拒绝 push，显式 visible 才确认', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester
        .pumpWidget(MaterialApp(navigatorKey: key, home: const SizedBox()));
    final rejected = _BareRoute();
    expect(
        () => presentRoute(key.currentState!, rejected), throwsArgumentError);
    expect(rejected.navigator, isNull);
    rejected.dispose();
    final visible = Completer<void>();
    final handle =
        presentRoute(key.currentState!, _BareRoute(), visible: visible.future);
    var confirmed = false;
    handle.visible.then((_) => confirmed = true);
    await tester.pump();
    expect(confirmed, isFalse);
    visible.complete();
    await tester.pump();
    expect(confirmed, isTrue);
    await handle.dismiss!();
    await tester.pumpAndSettle();
    await handle.dismissed;
  });

  for (final kind in [0, 1, 2]) {
    testWidgets('路由 $kind：首帧前不计数，被覆盖后等重新可见才 shown', (tester) async {
      final key = GlobalKey<NavigatorState>();
      final manager = Layerman();
      addTearDown(manager.dispose);
      final events = <OverlayEvent>[];
      manager.events.listen(events.add);
      await tester
          .pumpWidget(MaterialApp(navigatorKey: key, home: const SizedBox()));
      await manager.ready();
      const cd = OverlayCooldown(total: 1, session: 1);
      manager.submit<void>(
          id: 'a',
          cooldown: cd,
          present: _present(kind, key,
              (_) => const SizedBox(height: 80, child: Text('target'))));
      final cover = MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('cover')));
      key.currentState!.push(cover);
      expect(manager.cooldownStatus('a', cd).canShow, isTrue);
      await tester.pumpAndSettle();
      expect(manager.cooldownStatus('a', cd).canShow, isTrue);
      expect(events.map((e) => e.type), [OverlayEventType.queued]);
      key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(manager.cooldownStatus('a', cd).permanentlyBlocked, isTrue);
      expect(events.map((e) => e.type),
          [OverlayEventType.queued, OverlayEventType.shown]);
      manager.clear();
      await tester.pumpAndSettle();
    });

    testWidgets('路由 $kind：首帧前移除，没有 shown 且不消耗上限', (tester) async {
      final key = GlobalKey<NavigatorState>();
      final manager = Layerman();
      addTearDown(manager.dispose);
      final events = <OverlayEvent>[];
      manager.events.listen(events.add);
      await tester
          .pumpWidget(MaterialApp(navigatorKey: key, home: const SizedBox()));
      await manager.ready();
      const cd = OverlayCooldown(total: 1);
      final ticket = manager.submit<void>(
          id: 'a',
          cooldown: cd,
          present: _present(kind, key, (_) => const SizedBox(height: 80)));
      ticket.remove();
      await tester.pumpAndSettle();
      expect(manager.cooldownStatus('a', cd).canShow, isTrue);
      expect((await ticket.outcome).reason, OverlayEndReason.removed);
      expect(events.map((e) => e.type),
          [OverlayEventType.queued, OverlayEventType.ended]);
    });

    testWidgets('路由 $kind：构建失败不会确认可见，failed 结束并保留频次', (tester) async {
      final key = GlobalKey<NavigatorState>();
      final manager = Layerman();
      addTearDown(manager.dispose);
      await tester
          .pumpWidget(MaterialApp(navigatorKey: key, home: const SizedBox()));
      await manager.ready();
      const cd = OverlayCooldown(total: 1);
      final ticket = manager.submit<void>(
          id: 'a',
          cooldown: cd,
          present:
              _present(kind, key, (_) => throw StateError('builder failed')));
      final errors = <Object>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.exception);
      try {
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = previous;
      }
      expect(errors, isNotEmpty);
      expect((await ticket.outcome).reason, OverlayEndReason.failed);
      expect(manager.cooldownStatus('a', cd).canShow, isTrue);
      expect(manager.activeIds, isEmpty);
    });
  }

  testWidgets('OverlayVisibility：Offstage 不确认，成功绘制后只确认一次', (tester) async {
    final visible = Completer<void>();
    /// 构建可切换离屏状态的内容。
    Widget content(bool offstage) => Directionality(
        textDirection: TextDirection.ltr,
        child: Offstage(
            offstage: offstage,
            child: OverlayVisibility(
                visible: visible, child: const Text('content'))));
    await tester.pumpWidget(content(true));
    expect(visible.isCompleted, isFalse);
    await tester.pumpWidget(content(false));
    expect(visible.isCompleted, isTrue);
    await tester.pumpWidget(content(false));
    await visible.future;
  });

  testWidgets('OverlayVisibility：替换未绘制确认器，旧信号失败、新信号等实际绘制',
      (tester) async {
    final first = Completer<void>();
    final second = Completer<void>();
    final failed = expectLater(first.future, throwsStateError);

    /// 重建同一渲染对象，独立控制确认器和是否绘制。
    Widget content(Completer<void> visible, bool offstage) => Directionality(
        textDirection: TextDirection.ltr,
        child: Offstage(
            offstage: offstage,
            child: OverlayVisibility(
                visible: visible, child: const Text('content'))));
    await tester.pumpWidget(content(first, true));
    final render = tester.renderObject(find.byType(OverlayVisibility,
        skipOffstage: false));
    await tester.pumpWidget(content(second, true));
    await failed;
    expect(second.isCompleted, isFalse);
    expect(tester.renderObject(find.byType(OverlayVisibility,
        skipOffstage: false)), same(render));
    await tester.pumpWidget(content(second, false));
    await second.future;
  });

  testWidgets('OverlayVisibility：旧路由覆盖回调不能确认尚未绘制的新确认器', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final first = Completer<void>();
    final second = Completer<void>();
    var current = first;
    var hidden = false;
    late StateSetter rebuild;
    // 在首帧绘制之后、确认回调之前覆盖路由，留下旧确认器的待检查回调。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('cover'))));
    });
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: StatefulBuilder(builder: (_, setState) {
        rebuild = setState;
        return Offstage(
            offstage: hidden,
            child: OverlayVisibility(visible: current, child: const Text('tip')));
      }),
    ));
    await tester.pumpAndSettle();
    expect(first.isCompleted, isFalse);
    final failed = expectLater(first.future, throwsStateError);
    rebuild(() {
      current = second;
      hidden = true;
    });
    await tester.pump();
    await failed;
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(second.isCompleted, isFalse);
    rebuild(() => hidden = false);
    await tester.pump();
    await second.future;
  });

  testWidgets('OverlayVisibility：替换已完成确认器，新确认器正常完成', (tester) async {
    final first = Completer<void>();
    final second = Completer<void>();

    /// 保持组件位置不变，以复用同一个渲染对象。
    Widget content(Completer<void> visible) => Directionality(
        textDirection: TextDirection.ltr,
        child: OverlayVisibility(visible: visible, child: const Text('content')));
    await tester.pumpWidget(content(first));
    await first.future;
    await tester.pumpWidget(content(second));
    await second.future;
    expect(tester.takeException(), isNull);
  });

  testWidgets('OverlayVisibility：跨路由重挂载刷新捕获的路由', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final contentKey = GlobalKey();
    final moved = ValueNotifier<bool>(false);
    addTearDown(moved.dispose);
    final visible = Completer<void>();

    /// 同一 GlobalKey 从旧页面的 Offstage 移到新页面并参与绘制。
    Widget content(bool offstage) => Offstage(
        offstage: offstage,
        child: OverlayVisibility(
            key: contentKey, visible: visible, child: const Text('moved')));
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: ValueListenableBuilder<bool>(
        valueListenable: moved,
        builder: (_, value, child) => value ? const SizedBox() : content(true),
      ),
    ));
    final render = tester.renderObject(find.byKey(contentKey, skipOffstage: false));
    expect(visible.isCompleted, isFalse);
    moved.value = true;
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(body: content(false))));
    await tester.pumpAndSettle();
    expect(tester.renderObject(find.byKey(contentKey)), same(render));
    expect(visible.isCompleted, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('OverlayVisibility：构建失败以错误确认，不把 ErrorWidget 当展示', (tester) async {
    final visible = Completer<void>();
    final failure = expectLater(visible.future, throwsStateError);
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: OverlayVisibility(
            visible: visible,
            child:
                Builder(builder: (_) => throw StateError('content failed')))));
    expect(tester.takeException(), isA<StateError>());
    await failure;
  });
}
