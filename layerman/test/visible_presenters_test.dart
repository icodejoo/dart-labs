import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';

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

void main() {
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
