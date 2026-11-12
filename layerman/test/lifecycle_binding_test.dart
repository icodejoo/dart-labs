import 'support/manual_now_clock.dart';
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';

/// 最小假后端：present 后记录是否展示。
class _Backend {
  final Completer<String?> _dismissed = Completer<String?>();
  bool presented = false;

  PresentedOverlay<String> present(PresentContext context) {
    presented = true;
    return PresentedOverlay<String>(
      visible: Future<void>.value(),
      dismissed: _dismissed.future,
      dismiss: ([String? result]) async {
        if (!_dismissed.isCompleted) _dismissed.complete(result);
      },
    );
  }
}

void main() {
  testWidgets('进入后台暂停队列，回到前台恢复并出场排队条目', (tester) async {
    final manager = Layerman();
    final lifecycle = LayermanLifecycle(manager)..attach();
    addTearDown(() {
      lifecycle.detach();
      manager.dispose();
    });
    final backend = _Backend();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(manager.isPaused, isTrue);
    manager.open(id: 'a', present: backend.present);
    await tester.pump();
    expect(backend.presented, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(manager.isPaused, isFalse);
    expect(backend.presented, isTrue);
  });

  testWidgets('默认 hidden 也暂停，inactive 不暂停；可用 pauseOn 自定义', (tester) async {
    final manager = Layerman();
    final lifecycle = LayermanLifecycle(manager)..attach();
    final custom = Layerman();
    final customLifecycle = LayermanLifecycle(custom,
        pauseOn: const {AppLifecycleState.inactive})
      ..attach();
    addTearDown(() {
      lifecycle.detach();
      customLifecycle.detach();
      manager.dispose();
      custom.dispose();
    });

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(manager.isPaused, isFalse);
    expect(custom.isPaused, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(manager.isPaused, isTrue);
    expect(custom.isPaused, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(manager.isPaused, isFalse);
  });

  testWidgets('与手动 pauseAll 按 OR 组合：回到前台不会撤销手动暂停', (tester) async {
    final manager = Layerman();
    final lifecycle = LayermanLifecycle(manager)..attach();
    addTearDown(() {
      lifecycle.detach();
      manager.dispose();
    });

    manager.pauseAll();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(manager.isPaused, isTrue);
    expect(manager.holdCount, 0);

    manager.resumeAll();
    expect(manager.isPaused, isFalse);
  });

  testWidgets('detach 释放凭证并停止监听；重复 attach/detach 无副作用', (tester) async {
    final manager = Layerman();
    final lifecycle = LayermanLifecycle(manager);
    addTearDown(() {
      lifecycle.detach();
      manager.dispose();
    });
    expect(lifecycle.isAttached, isFalse);
    lifecycle.attach();
    lifecycle.attach();
    expect(lifecycle.isAttached, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(manager.holdCount, 1);

    lifecycle.detach();
    lifecycle.detach();
    expect(lifecycle.isAttached, isFalse);
    expect(manager.holdCount, 0);
    expect(manager.isPaused, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(manager.isPaused, isFalse); // 已不再监听
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('attach 时应用已在后台则立即暂停；manager 销毁后自动解除监听', (tester) async {
    final manager = Layerman();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final lifecycle = LayermanLifecycle(manager)..attach();
    expect(manager.isPaused, isTrue);

    manager.dispose();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(lifecycle.isAttached, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('进入后台时 duration 倒计时冻结，回到前台按剩余时间继续', (tester) async {
    // 引擎用注入的 now 计算冻结时的剩余时长；fake async 下 DateTime.now 是真实时钟，
    // 所以必须注入手动时钟，并和 pump 同步推进。
    var clock = DateTime(2026, 1, 1, 12);
    Future<void> advance(Duration d) async {
      clock = clock.add(d);
      await tester.pump(d);
    }

    final manager = Layerman(clock: ManualNowClock(() => clock));
    final lifecycle = LayermanLifecycle(manager)..attach();
    addTearDown(() {
      lifecycle.detach();
      manager.dispose();
    });
    final backend = _Backend();
    var closed = false;
    manager
        .open<String>(
            id: 'toast',
            duration: const Duration(seconds: 2),
            present: backend.present)
        .then((_) => closed = true);
    await tester.pump();
    await advance(const Duration(seconds: 1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await advance(const Duration(seconds: 5)); // 后台久放也不应关闭
    expect(manager.isShowing('toast'), isTrue);
    expect(closed, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await advance(const Duration(milliseconds: 500));
    expect(manager.isShowing('toast'), isTrue); // 还剩约 0.5 秒
    expect(closed, isFalse);
    await advance(const Duration(milliseconds: 600));
    expect(closed, isTrue);
  });
}
