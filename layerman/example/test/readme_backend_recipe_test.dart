import 'dart:async';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:layerman/layerman.dart';
import 'package:layerman_example/readme_recipes.dart';

/// 挂载真实 GetX Navigator 和 bot_toast 图层，并在卸载前清理后端。
Future<Layerman> _pumpBackends(WidgetTester tester) async {
  final manager = Layerman();
  await tester.pumpWidget(
    GetMaterialApp(
      builder: BotToastInit(),
      navigatorObservers: [BotToastNavigatorObserver()],
      home: const Scaffold(body: Text('home')),
    ),
  );
  await tester.pumpAndSettle();
  expect(Get.key.currentState, isNotNull);
  addTearDown(() async {
    manager.dispose();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    Get.reset();
  });
  return manager;
}

/// 运行 README 配方，而非其他演示中形状相似的 helper。
void main() {
  for (final sheet in [false, true]) {
    for (final covered in [false, true]) {
      testWidgets(
        'README Get.key ${sheet ? 'sheet' : 'dialog'} 定向关闭：covered=$covered',
        (tester) async {
          final manager = await _pumpBackends(tester);
          final result = sheet
              ? openReadmeGetxBottomSheet(manager)
              : openReadmeGetxDialog(manager);
          await tester.pumpAndSettle();
          final route = ModalRoute.of(
            tester.element(find.byType(ConfirmDialog)),
          )!;
          expect(route.navigator, same(Get.key.currentState));
          expect(route.settings.name, 'om://confirm');
          final cover = MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          );
          if (covered) {
            Get.key.currentState!.push(cover);
            await tester.pumpAndSettle();
          }

          manager.close('confirm', true);
          await tester.pumpAndSettle();

          expect(await result, isTrue);
          expect(route.navigator, isNull);
          expect(manager.recordOf('confirm'), isNull);
          expect(find.byType(ConfirmDialog, skipOffstage: false), findsNothing);
          if (covered) {
            expect(cover.isCurrent, isTrue);
            expect(find.text('cover'), findsOneWidget);
          } else {
            expect(find.text('home'), findsOneWidget);
          }
        },
      );
    }
  }

  for (final close in [false, true]) {
    testWidgets('README GetX snackbar ${close ? '定向关闭' : '自然退场'}后释放槽位', (
      tester,
    ) async {
      final manager = await _pumpBackends(tester);
      var ended = false;
      openReadmeGetxSnackbar(manager).then((_) => ended = true);
      var nextShown = false;
      manager.open<void>(
        id: 'next',
        slot: 'snack',
        present: (_) {
          nextShown = true;
          return PresentedOverlay(
            visible: Future<void>.value(),
            dismissed: Completer<void>().future,
          );
        },
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Saved'), findsOneWidget);
      expect(nextShown, isFalse);
      if (close) {
        manager.close('saved');
        expect(manager.recordOf('saved')!.phase, OverlayPhase.closing);
        expect(nextShown, isFalse);
      } else {
        expect(ended, isFalse);
        await tester.pump(const Duration(seconds: 5));
      }
      await tester.pumpAndSettle();
      expect(ended, isTrue);
      expect(nextShown, isTrue);
      expect(manager.recordOf('saved'), isNull);
      expect(find.text('Saved'), findsNothing);
    });

    testWidgets(
      'README bot_toast ${close ? 'CancelFunc 关闭' : '自然退场'}经 onClose 推进队列',
      (tester) async {
        final manager = await _pumpBackends(tester);
        var ended = false;
        openReadmeBotToast(manager).then((_) => ended = true);
        var nextShown = false;
        manager.open<void>(
          id: 'next',
          slot: 'toast',
          present: (_) {
            nextShown = true;
            return PresentedOverlay(
            visible: Future<void>.value(),
            dismissed: Completer<void>().future,
          );
          },
        );
        await tester.pumpAndSettle();
        expect(find.text('Copied to clipboard'), findsOneWidget);
        expect(nextShown, isFalse);
        if (close) {
          manager.close('tip');
          expect(manager.recordOf('tip')!.phase, OverlayPhase.closing);
          expect(nextShown, isFalse);
        } else {
          expect(ended, isFalse);
          await tester.pump(const Duration(seconds: 5));
        }
        await tester.pumpAndSettle();
        expect(ended, isTrue);
        expect(nextShown, isTrue);
        expect(manager.recordOf('tip'), isNull);
        expect(find.text('Copied to clipboard'), findsNothing);
      },
    );
  }
}
