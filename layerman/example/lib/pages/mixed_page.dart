import 'dart:async';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:layerman/layerman.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers.dart';
import '../manager.dart';

class MixedPage extends StatelessWidget {
  const MixedPage({super.key});

  // ── Inner helpers ──────────────────────────────────────────────────────────

  /// ShadDialog rendered as a layerman overlay CONTENT, presented through
  /// [presentCard] (a real `showDialog` route — see helpers.dart). [close] is
  /// bound to that route, mirroring the old `OverlayHandle.close()`.
  Widget _shadDialogContent(String title, void Function([Object? result]) close) =>
      Center(
        child: ShadDialog(
          title: Text(title),
          description: const Text(
            'ShadDialog widget presented through layerman\'s present() hook.\n'
            'ShadTheme is provided by the builder chain in AppRoot.',
          ),
          actions: [
            ShadButton.outline(
              onPressed: () => close(),
              child: const Text('Cancel'),
            ),
            ShadButton(
              onPressed: () => close('ok'),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );

  /// ShadSheet positioned at the bottom, presented through [presentCard].
  ///
  /// ShadSheet needs [ShadSheetInheritedWidget] (normally injected by
  /// showShadSheet's route builder). We inject it manually here so ShadSheet
  /// works without going through showShadSheet itself. [onClosing] bridges
  /// draggable-dismiss to [close] instead of Navigator.pop().
  Widget _bottomPanel(void Function([Object? result]) close) => Align(
        alignment: Alignment.bottomCenter,
        child: ShadSheetInheritedWidget(
          side: ShadSheetSide.bottom,
          child: ShadSheet(
            draggable: true,
            expandable: true,
            onClosing: () => close(), // draggable 向下拖 → close() 而非 pop()
            title: const Text('ShadSheet via present()'),
            description: const Text(
              '手动注入 ShadSheetInheritedWidget(side: bottom) 解锁完整功能。\n'
              'draggable: 向下拖关闭  expandable: 拖手柄展开',
            ),
            actions: [
              ShadButton.outline(
                onPressed: () => close(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          pageHeader(
            context,
            'Mixed UI Libraries',
            'layerman orchestrates GetX, bot_toast and shadcn/ui as equal peers '
            'through the present hook. Each library owns its own rendering '
            'and animations; layerman owns serialisation, cooldown, conditions and '
            'lifecycle.',
          ),

          // ── shadcn/ui toasts ──────────────────────────────────────────────
          pageSection(
            context,
            'shadcn/ui Toast — ShadSonner (present callback)',
            [
              demoButton('btn-shad-toast', 'shadcn toast (3s)', () {
                om.open<void>(
                  id: 'shad-toast-${DateTime.now().millisecondsSinceEpoch}',
                  present: (ctx) => presentShadToast(
                    ctx,
                    title: const Text('layerman'),
                    description: const Text('shadcn/ui toast — auto-dismisses in 3 s'),
                  ),
                );
              }),
              demoButton('btn-shad-toast-dest', 'destructive toast', () {
                om.open<void>(
                  id: 'shad-toast-d-${DateTime.now().millisecondsSinceEpoch}',
                  present: (ctx) => presentShadToast(
                    ctx,
                    variant: ShadToastVariant.destructive,
                    title: const Text('Error'),
                    description:
                        const Text('Destructive variant — still serialised by layerman'),
                  ),
                );
              }),
              demoButton('btn-shad-toast3', 'queue 3 toasts', () {
                for (var i = 1; i <= 3; i++) {
                  om.open<void>(
                    id: 'shad-t$i',
                    present: (ctx) => presentShadToast(
                      ctx,
                      description: Text('Toast $i/3 — layerman serialises these'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }),
            ],
            subtitle:
                'presentShadToast wraps ShadSonner.show() in a PresentedOverlay. '
                'shadSonnerKey (GlobalKey) gives the present-callback access to '
                'ShadSonnerState without a BuildContext.',
          ),

          // ── shadcn/ui Dialog — inline content via presentCard ─────────────
          pageSection(
            context,
            'shadcn/ui Dialog — overlay content (present → showDialog)',
            [
              demoButton('btn-shad-dlg', 'ShadDialog as overlay content', () {
                om.open(
                  id: 'shad-dlg',
                  present: (ctx) => presentCard(
                    ctx,
                    (c, close) => _shadDialogContent('shadcn/ui Dialog', close),
                    barrierColor: const Color(0x99000000),
                    barrierDismissible: true,
                  ),
                );
              }),
              demoButton('btn-shad-dlg-alert', 'ShadDialog.alert', () {
                om.open(
                  id: 'shad-dlg-alert',
                  present: (ctx) => presentCard<bool>(
                    ctx,
                    (c, close) => Center(
                      child: ShadDialog.alert(
                        title: const Text('Confirm action'),
                        description:
                            const Text('This action cannot be undone. Continue?'),
                        actions: [
                          ShadButton.outline(
                            onPressed: () => close(false),
                            child: const Text('Cancel'),
                          ),
                          ShadButton.destructive(
                            onPressed: () => close(true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    ),
                    barrierColor: const Color(0x99000000),
                  ),
                );
              }),
            ],
            subtitle:
                'presentCard wraps ShadDialog in a real showDialog route (no OverlayEntry). '
                'ShadTheme is inherited from AppRoot\'s builder chain. '
                'ShadButton variants (outline, destructive) style the actions.',
          ),

          // ── shadcn/ui Dialog — route-based via showShadDialog ─────────────
          pageSection(
            context,
            'shadcn/ui Dialog — route-based (present → showShadDialog)',
            [
              demoButton('btn-shad-rdlg', 'presentShadDialog', () {
                om.open<String>(
                  id: 'shad-rdlg',
                  exitDuration: const Duration(milliseconds: 250),
                  present: (ctx) => presentShadDialog<String>(
                    ctx,
                    ShadDialog(
                      title: const Text('Route-backed ShadDialog'),
                      description: const Text(
                        'showShadDialog pushes a real route.\n'
                        'layerman tracks it via unique route name om://shad-rdlg.',
                      ),
                      actions: [
                        ShadButton.outline(
                          onPressed: () => Navigator.of(
                                  Get.overlayContext!,
                                  rootNavigator: true)
                              .pop('cancel'),
                          child: const Text('Cancel'),
                        ),
                        ShadButton(
                          onPressed: () => Navigator.of(
                                  Get.overlayContext!,
                                  rootNavigator: true)
                              .pop('ok'),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
            subtitle:
                'presentShadDialog wraps showShadDialog in PresentedOverlay '
                'with a unique RouteSettings name for targeted dismiss '
                '(same pattern as presentRouteDialog for GetX/native dialogs).',
          ),

          // ── shadcn/ui Sheet ───────────────────────────────────────────────
          pageSection(
            context,
            'shadcn/ui Sheet',
            [
              // Route-based showShadSheet via present — proper slide animation
              demoButton('btn-shad-sheet', 'showShadSheet (present)', () {
                om.open(
                  id: 'shad-sheet',
                  present: (ctx) {
                    // Store the navigator before the async push so dismiss
                    // can pop precisely (same navigator that pushed the sheet).
                    final nav = Navigator.of(Get.overlayContext!);
                    final future = showShadSheet<void>(
                      context: Get.overlayContext!,
                      side: ShadSheetSide.bottom,
                      isDismissible: true,
                      builder: (sheetCtx) => ShadTheme(
                        data: ShadThemeData(
                            colorScheme: const ShadSlateColorScheme.light()),
                        child: ShadSheet(
                          title: const Text('layerman → showShadSheet'),
                          description: const Text(
                            'draggable: 向下拖可关闭\n'
                            'expandable: 拖动顶部手柄可展开/收起',
                          ),
                          draggable: true,   // 向下拖关闭
                          expandable: true,  // 拖动手柄展开
                          actions: [
                            ShadButton.outline(
                              onPressed: () => Navigator.of(sheetCtx).pop(),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
                    );
                    return PresentedOverlay<void>(
                      dismissed: future,
                      // nav was captured before push — same navigator, correct pop target
                      dismiss: ([_]) async {
                        if (nav.canPop()) nav.pop();
                      },
                    );
                  },
                );
              }),
              // ShadSheet as overlay content via presentCard
              demoButton('btn-shad-panel', 'ShadSheet in presentCard (draggable + expandable)', () {
                om.open(
                  id: 'shad-panel',
                  present: (ctx) => presentCard(
                    ctx,
                    (c, close) => _bottomPanel(close),
                    barrierColor: const Color(0x66000000),
                    barrierDismissible: true,
                  ),
                );
              }),
              // Two panels overlapping via overlap: true
              demoButton('btn-shad-panel-overlap', 'overlap 2 panels', () {
                om.open(
                  id: 'shad-p1',
                  overlap: true,
                  present: (ctx) => presentCard(
                    ctx,
                    (c, close) => Align(
                      alignment: Alignment.bottomCenter,
                      child: Material(
                        elevation: 8,
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Panel A (bottom, overlap)',
                                  style: TextStyle(fontWeight: FontWeight.w600)),
                              ShadButton(
                                  onPressed: () => close(),
                                  child: const Text('Close A')),
                            ],
                          ),
                        ),
                      ),
                    ),
                    barrierColor: const Color(0x33000000),
                  ),
                );
                om.open(
                  id: 'shad-p2',
                  overlap: true,
                  present: (ctx) => presentCard(
                    ctx,
                    (c, close) => Align(
                      alignment: Alignment.topCenter,
                      child: Material(
                        elevation: 8,
                        borderRadius:
                            const BorderRadius.vertical(bottom: Radius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Panel B (top, overlap)',
                                  style: TextStyle(fontWeight: FontWeight.w600)),
                              ShadButton(
                                  onPressed: () => close(),
                                  child: const Text('Close B')),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
            subtitle:
                '两种方式都用真实 ShadSheet:\n'
                '「showShadSheet」→ present 回调，推路由，有路由动画\n'
                '「presentCard」→ 手动注入 ShadSheetInheritedWidget(side:)，\n'
                '  onClosing: close 桥接拖拽关闭到 layerman',
          ),

          // ── shadcn/ui Button showcase ──────────────────────────────────────
          pageSection(
            context,
            'shadcn/ui Button variants inside overlay actions',
            [
              demoButton('btn-shad-buttons', 'showcase all ShadButton variants', () {
                om.open(
                  id: 'shad-btns',
                  present: (ctx) => presentCard(
                    ctx,
                    (c, close) => Center(
                      child: ShadCard(
                        title: const Text('ShadButton variants'),
                        description: const Text(
                            'All shadcn/ui button styles inside a layerman overlay'),
                        footer: ShadButton.outline(
                          onPressed: () => close(),
                          child: const Text('Close'),
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ShadButton(onPressed: () {}, child: const Text('Primary')),
                            ShadButton.secondary(onPressed: () {}, child: const Text('Secondary')),
                            ShadButton.outline(onPressed: () {}, child: const Text('Outline')),
                            ShadButton.ghost(onPressed: () {}, child: const Text('Ghost')),
                            ShadButton.destructive(onPressed: () {}, child: const Text('Destructive')),
                            ShadButton.link(onPressed: () {}, child: const Text('Link')),
                          ],
                        ),
                      ),
                    ),
                    barrierColor: const Color(0x88000000),
                  ),
                );
              }),
            ],
          ),

          // ── GetX + bot_toast recap ────────────────────────────────────────
          pageSection(
            context,
            'GetX dialog + snackbar (present)',
            [
              demoButton('btn-getx-dlg-mixed', 'GetX dialog', () {
                om.open<String>(
                  id: 'getx-dlg-m',
                  exitDuration: const Duration(milliseconds: 200),
                  present: (ctx) => presentRouteDialog(
                    ctx,
                    AlertDialog(
                      title: const Text('GetX Dialog'),
                      content: const Text('Scheduled by layerman via Get.dialog'),
                      actions: [
                        Builder(
                          builder: (c) => TextButton(
                            onPressed: () => Navigator.of(c).pop('ok'),
                            child: const Text('OK'),
                          ),
                        ),
                      ],
                    ),
                    useGetx: true,
                  ),
                );
              }),
              demoButton('btn-getx-snack-mixed', 'GetX snackbar (slot "snack")', () {
                om.open<void>(
                  id: 'snk-${DateTime.now().millisecondsSinceEpoch}',
                  slot: 'snack',
                  present: (ctx) {
                    final c = Get.snackbar(
                      'GetX Snackbar',
                      'Scheduled by layerman — slot "snack"',
                      duration: const Duration(seconds: 2),
                      animationDuration: const Duration(milliseconds: 300),
                    );
                    return PresentedOverlay<void>(
                      dismissed: c.future,
                      dismiss: ([_]) => c.close(),
                    );
                  },
                );
              }),
              demoButton('btn-botoast-mixed', 'bot_toast text', () {
                om.open<void>(
                  id: 'bt-${DateTime.now().millisecondsSinceEpoch}',
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
                  },
                );
              }),
            ],
          ),

          // ── Grand Finale ──────────────────────────────────────────────────
          pageSection(
            context,
            'Grand Finale — 4 UI systems, 1 queue',
            [
              demoButton('btn-grand', '▶ Run all 4 systems in sequence', () {
                // 1. Native showDialog
                om.open<String>(
                  id: 'gf-native',
                  exitDuration: const Duration(milliseconds: 200),
                  present: (ctx) => presentRouteDialog(
                    ctx,
                    AlertDialog(
                      title: const Text('1/4 — native showDialog'),
                      content: const Text('Tap OK to advance to shadcn dialog'),
                      actions: [
                        Builder(
                          builder: (c) => TextButton(
                            onPressed: () => Navigator.of(c).pop('ok'),
                            child: const Text('OK'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
                // 2. shadcn/ui ShadDialog (present → presentCard, no route push
                //    beyond the showDialog route presentCard itself uses)
                om.open(
                  id: 'gf-shad',
                  present: (ctx) => presentCard(
                    ctx,
                    (c, close) => Center(
                      child: ShadDialog(
                        title: const Text('2/4 — shadcn/ui ShadDialog'),
                        description: const Text(
                            'Tap Confirm to advance to shadcn toast'),
                        actions: [
                          ShadButton(
                            onPressed: () => close('ok'),
                            child: const Text('Confirm'),
                          ),
                        ],
                      ),
                    ),
                    barrierColor: const Color(0x99000000),
                  ),
                );
                // 3. shadcn/ui ShadSonner toast (auto-dismiss 3s)
                om.open<void>(
                  id: 'gf-toast',
                  present: (ctx) => presentShadToast(
                    ctx,
                    title: const Text('3/4 — shadcn/ui Toast'),
                    description:
                        const Text('Auto-dismisses in 3 s → bot_toast follows'),
                    duration: const Duration(seconds: 3),
                  ),
                );
                // 4. bot_toast (auto-dismiss 2s)
                om.open<void>(
                  id: 'gf-bot',
                  present: (ctx) {
                    final done = Completer<void>();
                    final cancel = BotToast.showText(
                      text: '4/4 — bot_toast ✓ all 4 systems done',
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
                  },
                );
                // GetX snackbar on 'snack' slot — runs in PARALLEL
                om.open<void>(
                  id: 'gf-snack',
                  slot: 'snack',
                  present: (ctx) {
                    final c = Get.snackbar(
                      'GetX Snackbar',
                      'Runs on "snack" slot — parallel with the main queue',
                      duration: const Duration(seconds: 8),
                      animationDuration: const Duration(milliseconds: 300),
                    );
                    return PresentedOverlay<void>(
                      dismissed: c.future,
                      dismiss: ([_]) => c.close(),
                    );
                  },
                );
              }),
            ],
            subtitle:
                'One button queues:\n'
                '  [default slot] native dialog → shadcn dialog → shadcn toast → bot_toast\n'
                '  [snack slot]   GetX snackbar (parallel, independent slot)\n\n'
                'layerman is the single arbiter of sequencing. '
                'No system knows about the others.',
          ),
        ],
      ),
    );
  }
}
