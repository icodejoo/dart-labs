import 'dart:async';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:layerman/layerman.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'manager.dart';

// ── Overlay card ────────────────────────────────────────────────────────────
//
// The old self-rendering `builder:` path (and its `OverlayHandle`) is gone —
// `present:` is the sole rendering hook now. These demo cards are rendered
// through a real `showDialog` route (see [presentCard]) so the manager still
// never touches the widget tree; it only sequences when each dialog opens.

/// Card content for a demo overlay. [close] is bound to the dialog route this
/// card is shown in (see [presentCard]) — calling it pops that route with an
/// optional [T] result, mirroring the old `OverlayHandle.close(result)`.
Widget buildCard(
  String text,
  void Function([Object? result]) close, {
  String? hint,
  List<Widget> actions = const [],
  Offset offset = Offset.zero,
}) =>
    Center(
      child: Transform.translate(
        offset: offset,
        child: Card(
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      hint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    ...actions,
                    FilledButton(
                      onPressed: () => close(),
                      child: Text('close $text'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

/// Presents a demo card via a real Navigator route (`showDialog`) — the UI
/// backend every simple demo page uses now that the manager renders nothing
/// itself. [contentBuilder] gets the dialog's own [BuildContext] plus a
/// `close([result])` callback wired to ctx.close for this entry
/// (never "whatever's on top"), so the manager can preempt it (replace) or
/// close it (close/remove/clear) without touching sibling routes.
PresentedOverlay<T> presentCard<T>(
  PresentContext<T> ctx,
  Widget Function(BuildContext context, void Function([Object? result]) close)
      contentBuilder, {
  Color barrierColor = const Color(0x00000000),
  bool barrierDismissible = false,
}) {
  final name = 'om://${ctx.id}';
  // Captured once the dialog actually builds, so `dismiss` can remove THIS
  // route directly — see the comment on [_removeRouteDismiss] for why that
  // beats popping by name.
  final captured = RouteCapture<T>();
  final future = showDialog<T>(
    context: Get.overlayContext!,
    useRootNavigator: true,
    barrierColor: barrierColor,
    barrierDismissible: barrierDismissible,
    routeSettings: RouteSettings(name: name),
    builder: (dialogCtx) {
      captured.capture(dialogCtx);
      return contentBuilder(dialogCtx, ([Object? r]) {
        // 通过条目身份关闭，遵守 beforeClose 并避免误关后来者。
        ctx.close(r as T?);
      });
    },
  );
  return PresentedOverlay<T>(
    dismissed: future,
    dismiss: ([T? r]) async => captured.dismiss(),
  );
}

/// Removes the route captured by a `presentCard`/`presentRouteDialog`/
/// `presentShadDialog` builder directly, instead of the tempting
/// `Get.until((rt) => rt.settings.name != name)` shortcut.
///
/// That shortcut only pops from the TOP of the stack, so it silently does
/// nothing for an overlay that isn't topmost (e.g. `clearWhere` removing one
/// of several stacked `mode: OverlayMode.overlap` cards while a sibling is still shown).
/// It also reaches into GetX's global navigator, which throws
/// ("contextless navigation without a GetMaterialApp") if called while no
/// app is mounted (e.g. `om.clear()` racing a widget-tree teardown between
/// tests). Dismissing the captured [Route] through its own [Route.navigator]
/// works regardless of stack position and simply no-ops once the route (or
/// its navigator) is already gone.
///
/// 与官方 DialogManager 一致：位于栈顶且没有内部历史时 pop，保留退场动画；
/// 被覆盖或带内部历史时只移除这一条。卡片的关闭按钮走 ctx.close，最终也经过这里。
void _removeRouteDismiss(Route<Object?>? rt) {
  final nav = rt?.navigator;
  if (rt == null || nav == null || !rt.isActive) return;
  if (rt.isCurrent && !rt.willHandlePopInternally) {
    nav.pop();
  } else {
    nav.removeRoute(rt);
  }
}

/// Captures the [ModalRoute] of a dialog once its builder runs, and removes
/// exactly that route on [dismiss].
/// 首帧前的关闭请求会保留，供对话框和 sheet 共用。
///
/// A dismiss that arrives before the first build (e.g. `replace` preempting a
/// card in the same frame it opened) is remembered and applied right after the
/// route is captured, instead of silently doing nothing and leaving a ghost.
class RouteCapture<T> {
  Route<T>? route;
  bool _dismissEarly = false;

  /// Call from the dialog's builder with its own [BuildContext].
  void capture(BuildContext context) {
    route ??= ModalRoute.of(context) as Route<T>?;
    if (_dismissEarly) {
      _dismissEarly = false;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _removeRouteDismiss(route),
      );
    }
  }

  /// Removes the captured route, or defers until it is captured.
  void dismiss() {
    if (route == null) {
      _dismissEarly = true;
    } else {
      _removeRouteDismiss(route);
    }
  }
}

/// Convenience wrapper around `om.open(present: (ctx) => presentCard(...))`
/// for the common case: a static-text demo card with no data driven by
/// [PresentContext.data]. Pages that need to read `ctx.data` (resolve/data
/// demos) or live-update their content after presenting call [presentCard]
/// directly instead.
Future<T?> openCard<T>(
  String id, {
  required String text,
  String? hint,
  List<Widget> Function(void Function([Object? result]) close)? actions,
  Offset offset = Offset.zero,
  String slot = '',
  int priority = 0,
  Duration? delay,
  Duration? duration,
  OverlayMode mode = OverlayMode.queue,
  bool affix = false,
  OverlayPredicate? when,
  RouteMatcher? route,
  OverlayPredicate? auth,
  bool dismissWhenUnmet = true,
  OverlayCooldown? cooldown,
  FutureOr<bool> Function()? beforeClose,
  Duration? exitDuration,
  Color barrierColor = const Color(0x00000000),
  bool barrierDismissible = false,
}) =>
    om.open<T>(
      id: id,
      slot: slot,
      priority: priority,
      delay: delay,
      duration: duration,
      mode: mode,
      affix: affix,
      when: when,
      route: route,
      auth: auth,
      dismissWhenUnmet: dismissWhenUnmet,
      cooldown: cooldown,
      beforeClose: beforeClose,
      exitDuration: exitDuration,
      present: (ctx) => presentCard<T>(
        ctx,
        (context, close) => buildCard(
          text,
          close,
          hint: hint,
          actions: actions?.call(close) ?? const [],
          offset: offset,
        ),
        barrierColor: barrierColor,
        barrierDismissible: barrierDismissible,
      ),
    );

/// Presents a demo card as a bare, non-modal [OverlayEntry] — no route, no
/// barrier. Unlike [presentCard] (a real `showDialog` route, which always
/// blocks input to whatever is behind it), this never steals touches outside
/// its own bounds — the right backend for the Overlap page's `mode: OverlayMode.overlap`
/// demos, where several cards AND the page underneath (e.g. its
/// `clearWhere` buttons) must all stay reachable at the same time.
PresentedOverlay<T> presentEntry<T>(
  Widget Function(void Function([Object? result]) close) contentBuilder,
) {
  final completer = Completer<T?>();
  late final OverlayEntry entry;
  void close([Object? result]) {
    if (completer.isCompleted) return;
    completer.complete(result as T?);
    entry.remove();
  }

  entry = OverlayEntry(builder: (_) => contentBuilder(close));
  // Get.overlayContext turns out to BE the app's OverlayState's own context
  // (GetX's internal `_Theater`) -- walking UP from it via Overlay.of (with
  // or without rootOverlay) finds nothing, since it IS the overlay, not a
  // descendant of one. NavigatorState.overlay reads the field directly, no
  // ancestor search involved.
  Get.key.currentState!.overlay!.insert(entry);
  return PresentedOverlay<T>(
    dismissed: completer.future,
    dismiss: ([T? r]) async => close(r),
  );
}

/// Convenience wrapper around `om.open(present: (ctx) => presentEntry(...))`
/// for a static-text demo card rendered via [presentEntry] — see its doc for
/// when a non-modal entry is the right choice over [openCard]. Mirrors
/// [openCard]'s queueing/condition params (everything but the barrier ones,
/// which don't apply to a bare, non-modal [OverlayEntry]).
///
/// 路由条件演示使用非模态 entry，便于继续操作页面导航。
/// LayermanNavigatorObserver 默认只跟踪 PageRoute，忽略 DialogRoute；
/// 自定义 routeFilter 若接受所有路由，需自行过滤合成的 om:// 路由。
Future<T?> openEntry<T>(
  String id, {
  required String text,
  String? hint,
  List<Widget> Function(void Function([Object? result]) close)? actions,
  Offset offset = Offset.zero,
  String slot = '',
  int priority = 0,
  Duration? delay,
  Duration? duration,
  OverlayMode mode = OverlayMode.queue,
  bool affix = false,
  OverlayPredicate? when,
  RouteMatcher? route,
  OverlayPredicate? auth,
  bool dismissWhenUnmet = true,
  OverlayCooldown? cooldown,
  FutureOr<bool> Function()? beforeClose,
  Duration? exitDuration,
  Object? data,
}) =>
    om.open<T>(
      id: id,
      slot: slot,
      priority: priority,
      delay: delay,
      duration: duration,
      mode: mode,
      affix: affix,
      when: when,
      route: route,
      auth: auth,
      dismissWhenUnmet: dismissWhenUnmet,
      cooldown: cooldown,
      beforeClose: beforeClose,
      exitDuration: exitDuration,
      data: data,
      present: (ctx) => presentEntry<T>(
        (close) => buildCard(
          text,
          close,
          hint: hint,
          actions: actions?.call(close) ?? const [],
          offset: offset,
        ),
      ),
    );

// ── Shared UI helpers ────────────────────────────────────────────────────────

Widget demoButton(String key, String label, VoidCallback onTap) =>
    FilledButton.tonal(key: Key(key), onPressed: onTap, child: Text(label));

Widget pageHeader(BuildContext context, String title, String desc) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          desc,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
        ),
        const SizedBox(height: 20),
      ],
    );

Widget pageSection(
  BuildContext context,
  String title,
  List<Widget> buttons, {
  String? subtitle,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: buttons),
          const SizedBox(height: 12),
          const Divider(),
        ],
      ),
    );

// ── GetX / native route-dialog presenter ───────────────────────────────────

PresentedOverlay<T> presentRouteDialog<T>(
  PresentContext<T> ctx,
  Widget dialog, {
  bool useGetx = false,
}) {
  final name = 'om://${ctx.id}';
  final captured = RouteCapture<T>();
  // A Builder around the caller's static `dialog` widget is enough to grab
  // its ModalRoute once built, for both the showDialog and Get.dialog paths
  // — see [_removeRouteDismiss] for why a captured Route beats popping by name.
  final wrapped = Builder(
    builder: (dialogCtx) {
      captured.capture(dialogCtx);
      return dialog;
    },
  );
  final Future<T?> future = useGetx
      ? Get.dialog<T>(wrapped, routeSettings: RouteSettings(name: name))
      : showDialog<T>(
          context: Get.overlayContext!,
          useRootNavigator: true,
          routeSettings: RouteSettings(name: name),
          builder: (_) => wrapped,
        );
  return PresentedOverlay<T>(
    dismissed: future,
    dismiss: ([T? r]) async => captured.dismiss(),
  );
}

// ── GetX snackbar / bot_toast presenters ───────────────────────────────────

/// Presents a GetX snackbar; [SnackbarController.close] is the dismiss path
/// (never `Get.back()`, which would pop the top route).
PresentedOverlay<void> presentGetxSnackbar(
  String title,
  String message, {
  Duration duration = const Duration(seconds: 2),
}) {
  final c = Get.snackbar(
    title,
    message,
    duration: duration,
    animationDuration: const Duration(milliseconds: 300),
  );
  return PresentedOverlay<void>(
    dismissed: c.future,
    dismiss: ([_]) => c.close(),
  );
}

/// Presents a bot_toast text toast. `onlyOne: false` bypasses bot_toast's own
/// queue; `onClose` drives `dismissed`, the [CancelFunc] drives `dismiss`.
PresentedOverlay<void> presentBotToastText(
  String text, {
  Duration duration = const Duration(seconds: 2),
}) {
  final done = Completer<void>();
  final cancel = BotToast.showText(
    text: text,
    duration: duration,
    onlyOne: false,
    onClose: () {
      if (!done.isCompleted) done.complete();
    },
  );
  return PresentedOverlay<void>(
    dismissed: done.future,
    dismiss: ([_]) async => cancel(),
  );
}

// ── shadcn/ui presenters ────────────────────────────────────────────────────

/// Wraps [showShadDialog] in a [PresentedOverlay].
/// 保存 Route 对象供 dismiss 精确移除；路由名称仅用于标识。
PresentedOverlay<T> presentShadDialog<T>(PresentContext<T> ctx, Widget dialog) {
  final name = 'om://${ctx.id}';
  final captured = RouteCapture<T>();
  final future = showShadDialog<T>(
    context: Get.overlayContext!,
    routeSettings: RouteSettings(name: name),
    // Wrap with ShadTheme so dialog widgets get the correct shadcn theme
    // even inside a GetX route (which does not automatically inherit from
    // the builder chain's ShadTheme).
    builder: (dialogCtx) {
      captured.capture(dialogCtx);
      return ShadTheme(
        data: ShadThemeData(colorScheme: const ShadSlateColorScheme.light()),
        child: dialog,
      );
    },
  );
  return PresentedOverlay<T>(
    dismissed: future,
    dismiss: ([T? r]) async => captured.dismiss(),
  );
}

/// Shows a [ShadSonner] toast via the global [shadSonnerKey] — no BuildContext
/// needed in the present callback.
///
/// [duration] must match the [ShadToast.duration] so the [PresentedOverlay]
/// knows when the toast has auto-dismissed.  The completer is also completed
/// after hide() finishes its exit animation on programmatic dismissal.
PresentedOverlay<void> presentShadToast(
  PresentContext<void> ctx, {
  Widget? title,
  required Widget description,
  ShadToastVariant variant = ShadToastVariant.primary,
  Duration duration = const Duration(seconds: 3),
}) {
  final sonner = shadSonnerKey.currentState!;
  final completer = Completer<void>();
  Timer? lifetime;

  // We own the toast's lifetime instead of trusting ShadSonner's own timer:
  // sonner restarts its countdown on hover (so a fixed delay would advance the
  // queue while the toast is still visible) and offers no "gone" callback.
  // `hide()` returns a Future that completes once the exit animation is done,
  // which is exactly when the next overlay may activate.
  final toastId = sonner.show(
    ShadToast.raw(
      variant: variant,
      title: title,
      description: description,
      duration: const Duration(days: 1), // effectively "until we hide it"
    ),
  );

  Future<void> finish() async {
    lifetime?.cancel();
    await sonner.hide(toastId);
    if (!completer.isCompleted) completer.complete();
  }

  lifetime = Timer(duration, finish);

  return PresentedOverlay<void>(
    dismissed: completer.future,
    dismiss: ([_]) => finish(),
  );
}
