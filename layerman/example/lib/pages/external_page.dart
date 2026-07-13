import 'dart:async';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:layerman/layerman.dart';
import '../helpers.dart';
import '../manager.dart';

class ExternalPage extends StatelessWidget {
  const ExternalPage({super.key});

  Widget _dialog(String title, String okKey) => AlertDialog(
        title: Text(title),
        content: const Text('Scheduled by layerman — tap OK to close.'),
        actions: [
          Builder(
            builder: (context) => TextButton(
              key: Key(okKey),
              onPressed: () => Navigator.of(context).pop('ok'),
              child: Text(okKey),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          pageHeader(context, 'External Presenters',
              'present: (ctx) => PresentedOverlay(...) lets layerman orchestrate '
              'any overlay system — showDialog, GetX dialogs/snackbars, bot_toast — '
              'without owning the rendering. The manager owns sequencing; '
              'each backend owns its own rendering and animations.'),
          pageSection(
            context,
            'present with showDialog',
            [
              demoButton('btn-native-dlg', 'open native showDialog', () {
                om.open<String>(
                    id: 'native-dlg',
                    exitDuration: const Duration(milliseconds: 200),
                    present: (ctx) =>
                        presentRouteDialog(ctx, _dialog('Native showDialog', 'OK-native')));
              }),
            ],
            subtitle:
                'presentRouteDialog wraps showDialog in PresentedOverlay. '
                'dismissed: is the Future<T?> from showDialog; '
                'dismiss: calls Get.until to pop the dialog route.',
          ),
          pageSection(
            context,
            'present with GetX Get.dialog',
            [
              demoButton('btn-getx-dlg', 'open GetX dialog', () {
                om.open<String>(
                    id: 'getx-dlg',
                    exitDuration: const Duration(milliseconds: 200),
                    present: (ctx) => presentRouteDialog(
                          ctx,
                          _dialog('GetX Get.dialog', 'OK-getx'),
                          useGetx: true,
                        ));
              }),
            ],
            subtitle:
                'Get.dialog routes through the GetX navigator. '
                'Same PresentedOverlay wrapper — dismissed/dismiss pattern is identical.',
          ),
          pageSection(
            context,
            'present with GetX snackbar (named slot)',
            [
              demoButton('btn-snack', 'GetX snackbar via slot "snack"', () {
                om.open<void>(
                    id: 'snack-${DateTime.now().millisecondsSinceEpoch}',
                    slot: 'snack',
                    present: (ctx) {
                      final c = Get.snackbar(
                        'Saved',
                        'Sequenced by layerman — slot: "snack"',
                        duration: const Duration(seconds: 2),
                        animationDuration: const Duration(milliseconds: 300),
                      );
                      return PresentedOverlay<void>(
                        dismissed: c.future,
                        dismiss: ([_]) => c.close(),
                      );
                    });
              }),
              demoButton('btn-snack-3', 'queue 3 snackbars', () {
                for (var i = 1; i <= 3; i++) {
                  om.open<void>(
                      id: 'snk$i',
                      slot: 'snack',
                      present: (ctx) {
                        final c = Get.snackbar(
                          'Message $i',
                          'Snackbar $i of 3',
                          duration: const Duration(seconds: 2),
                          animationDuration: const Duration(milliseconds: 300),
                        );
                        return PresentedOverlay<void>(
                            dismissed: c.future, dismiss: ([_]) => c.close());
                      });
                }
              }),
            ],
            subtitle:
                'Snackbars use a dedicated "snack" slot so they don\'t block dialog queue. '
                'SnackbarController.close() is the dismiss path — never Get.back() (which pops the top route).',
          ),
          pageSection(
            context,
            'present with bot_toast',
            [
              demoButton('btn-toast', 'bot_toast text', () {
                om.open<void>(
                    id: 'toast-${DateTime.now().millisecondsSinceEpoch}',
                    present: (ctx) {
                      final done = Completer<void>();
                      final cancel = BotToast.showText(
                        text: 'bot_toast — sequenced by layerman',
                        duration: const Duration(seconds: 2),
                        onlyOne: false,
                        onClose: () {
                          if (!done.isCompleted) done.complete();
                        },
                      );
                      return PresentedOverlay<void>(
                        dismissed: done.future,
                        dismiss: ([_]) async => cancel(),
                      );
                    });
              }),
            ],
            subtitle:
                'onlyOne: false + dedicated groupKey bypass bot_toast\'s internal queue. '
                'onClose completer drives dismissed. CancelFunc drives dismiss.',
          ),
          pageSection(
            context,
            'Three systems strictly serialised — one tap',
            [
              demoButton('btn-mixed', 'native → GetX → bot_toast (one tap)', () {
                om.open<String>(
                    id: 'nat',
                    exitDuration: const Duration(milliseconds: 200),
                    present: (ctx) =>
                        presentRouteDialog(ctx, _dialog('1/3 Native dialog', 'OK1')));
                om.open<String>(
                    id: 'gtx',
                    exitDuration: const Duration(milliseconds: 200),
                    present: (ctx) => presentRouteDialog(
                          ctx,
                          _dialog('2/3 GetX dialog', 'OK2'),
                          useGetx: true,
                        ));
                om.open<void>(
                    id: 'tst',
                    present: (ctx) {
                      final done = Completer<void>();
                      final cancel = BotToast.showText(
                        text: '3/3 bot_toast — layerman wins',
                        duration: const Duration(seconds: 2),
                        onlyOne: false,
                        onClose: () {
                          if (!done.isCompleted) done.complete();
                        },
                      );
                      return PresentedOverlay<void>(
                          dismissed: done.future, dismiss: ([_]) async => cancel());
                    });
              }),
            ],
            subtitle:
                'All three systems share the same default serial slot. '
                'The manager dismisses system N before activating system N+1.',
          ),
          pageSection(
            context,
            'PresentContext — id and slot access inside present callback',
            [
              demoButton('btn-ctx-inspect', 'inspect PresentContext', () {
                om.open<void>(
                    id: 'ctx-insp',
                    slot: 'inspect-slot',
                    present: (ctx) {
                      final done = Completer<void>();
                      BotToast.showText(
                        text: 'ctx.id=${ctx.id}  ctx.slot=${ctx.slot}',
                        duration: const Duration(seconds: 3),
                        onlyOne: false,
                        onClose: () {
                          if (!done.isCompleted) done.complete();
                        },
                      );
                      return PresentedOverlay<void>(
                          dismissed: done.future, dismiss: ([_]) async {});
                    });
              }),
            ],
            subtitle:
                'PresentContext carries id and slot — '
                'use ctx.id for route-backed dismiss (RouteSettings name: "om://\${ctx.id}").',
          ),
        ],
      ),
    );
  }
}

