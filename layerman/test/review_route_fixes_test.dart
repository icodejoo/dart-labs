import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';
import 'package:layerman/testing.dart';

void main() {
  testWidgets('B1 带内部历史的当前页面直接移除，不停在 closing', (tester) async {
    final key = GlobalKey<NavigatorState>();
    final manager = Layerman(dismissTimeout: null, clock: FakeOverlayClock());
    addTearDown(manager.dispose);
    await tester.pumpWidget(MaterialApp(
        navigatorKey: key, home: const Scaffold(body: Text('home'))));
    final route = MaterialPageRoute<Object?>(
        builder: (_) => const Scaffold(body: Text('target')));
    final ticket = manager.submit<Object?>(
        id: 'a', present: (_) => presentRoute(key.currentState!, route));
    await tester.pumpAndSettle();
    route.addLocalHistoryEntry(LocalHistoryEntry());
    expect(route.willHandlePopInternally, isTrue);
    ticket.close('result');
    expect(await ticket.result, 'result');
    await tester.pumpAndSettle();
    expect(route.isActive, isFalse);
    expect(manager.records, isEmpty);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('B1 直接句柄关闭内部历史页面返回 null', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester
        .pumpWidget(MaterialApp(navigatorKey: key, home: const Scaffold()));
    final route = MaterialPageRoute<String>(builder: (_) => const Scaffold());
    final handle = presentRoute(key.currentState!, route);
    await tester.pumpAndSettle();
    route.addLocalHistoryEntry(LocalHistoryEntry());
    await handle.dismiss!('ignored');
    await tester.pumpAndSettle();
    expect(await handle.dismissed, isNull);
  });

  testWidgets('C2 build 提交在帧后激活之后再淘汰等待队尾', (tester) async {
    final manager = Layerman(
        clock: FakeOverlayClock(),
        slots: {'': const OverlaySlotOptions(maxQueued: 1)});
    addTearDown(manager.dispose);
    await manager.ready();
    PresentedOverlay<Object?> present(PresentContext<Object?> ctx) =>
        PresentedOverlay(
            visible: Future<void>.value(),
            dismissed: Completer<Object?>().future);
    manager.open(
        id: 'waiting', present: present, when: (_) => false, priority: 10);
    await tester.pumpWidget(Builder(builder: (_) {
      manager.open(id: 'new', present: present);
      return const SizedBox();
    }));
    expect(manager.activeIds, ['new']);
    expect(manager.queuedIds, ['waiting']);
  });
}
