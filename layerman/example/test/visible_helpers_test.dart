import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:layerman/layerman.dart';

import 'package:layerman_example/helpers.dart';

/// 验证示例的真实后端提供首帧确认，尤其保留 Positioned 的父数据契约。
void main() {
  testWidgets('示例 entry、原生/GetX dialog、snackbar、bot_toast 都等首帧计数', (
    tester,
  ) async {
    Get.testMode = true;
    await tester.pumpWidget(
      GetMaterialApp(
        builder: BotToastInit(),
        navigatorObservers: [BotToastNavigatorObserver()],
        home: const Scaffold(body: Text('home')),
      ),
    );
    await tester.pumpAndSettle();
    final manager = Layerman();
    addTearDown(manager.dispose);
    await manager.ready();
    final presenters = <Present<void>>[
      (_) => presentEntry<void>(
        (close) => const Positioned(
          top: 20,
          right: 20,
          child: Card(child: Text('entry')),
        ),
      ),
      (ctx) => presentCard<void>(
        ctx,
        (context, close) => const AlertDialog(content: Text('card')),
      ),
      (ctx) => presentRouteDialog<void>(
        ctx,
        const AlertDialog(content: Text('native')),
      ),
      (ctx) => presentRouteDialog<void>(
        ctx,
        const AlertDialog(content: Text('GetX')),
        useGetx: true,
      ),
      (_) => presentGetxSnackbar(
        'title',
        'snackbar',
        duration: const Duration(seconds: 1),
      ),
      (_) => presentBotToastText('bot', duration: const Duration(seconds: 1)),
    ];
    const cd = OverlayCooldown(session: 1);
    for (var i = 0; i < presenters.length; i++) {
      final id = 'presenter$i';
      final ticket = manager.submit(
        id: id,
        present: presenters[i],
        cooldown: cd,
      );
      expect(manager.cooldownStatus(id, cd).canShow, isTrue, reason: id);
      await tester.pumpAndSettle();
      expect(
        manager.cooldownStatus(id, cd).permanentlyBlocked,
        isTrue,
        reason: id,
      );
      ticket.remove();
      await tester.pumpAndSettle();
      manager.debugCheckInvariants();
    }
    manager.dispose();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    Get.reset();
  });
}
