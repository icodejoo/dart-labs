import 'dart:async';
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
                Text(text,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(hint,
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
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
/// `close([result])` callback wired to pop precisely this overlay's route
/// (never "whatever's on top"), so the manager can preempt it (replace) or
/// close it (close/remove/clear) without touching sibling routes.
PresentedOverlay<T> presentCard<T>(
  PresentContext ctx,
  Widget Function(BuildContext context, void Function([Object? result]) close)
      contentBuilder, {
  Color barrierColor = const Color(0x00000000),
  bool barrierDismissible = false,
}) {
  final name = 'om://${ctx.id}';
  // Captured once the dialog actually builds, so `dismiss` can remove THIS
  // route directly — see the comment on [_removeRouteDismiss] for why that
  // beats popping by name.
  Route<T>? route;
  final future = showDialog<T>(
    context: Get.overlayContext!,
    useRootNavigator: true,
    barrierColor: barrierColor,
    barrierDismissible: barrierDismissible,
    routeSettings: RouteSettings(name: name),
    builder: (dialogCtx) {
      route ??= ModalRoute.of(dialogCtx) as Route<T>?;
      return contentBuilder(
        dialogCtx,
        ([Object? r]) {
          final nav = Navigator.of(dialogCtx, rootNavigator: true);
          if (nav.canPop()) nav.pop(r as T?);
        },
      );
    },
  );
  return PresentedOverlay<T>(
    dismissed: future,
    dismiss: ([T? r]) async => _removeRouteDismiss(() => route),
  );
}

/// Removes the route captured by a `presentCard`/`presentRouteDialog`/
/// `presentShadDialog` builder directly, instead of the tempting
/// `Get.until((rt) => rt.settings.name != name)` shortcut.
///
/// That shortcut only pops from the TOP of the stack, so it silently does
/// nothing for an overlay that isn't topmost (e.g. `clearWhere` removing one
/// of several stacked `overlap: true` cards while a sibling is still shown).
/// It also reaches into GetX's global navigator, which throws
/// ("contextless navigation without a GetMaterialApp") if called while no
/// app is mounted (e.g. `om.clear()` racing a widget-tree teardown between
/// tests). Removing the captured [Route] straight from its own
/// [Route.navigator] works regardless of stack position and simply no-ops
/// once the route (or its navigator) is already gone.
void _removeRouteDismiss(Route<Object?>? Function() route) {
  final rt = route();
  final nav = rt?.navigator;
  if (rt != null && nav != null) nav.removeRoute(rt);
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
  bool replace = false,
  bool affix = false,
  bool overlap = false,
  OverlayPredicate? when,
  Object? route,
  bool? requiresAuth,
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
      replace: replace,
      affix: affix,
      overlap: overlap,
      when: when,
      route: route,
      requiresAuth: requiresAuth,
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
/// its own bounds — the right backend for the Overlap page's `overlap: true`
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
/// Route-conditioned cards in particular MUST use this instead of [openCard]:
/// a route-backed presentCard/showDialog pushes its own synthetic
/// `om://<id>` route onto the SAME navigator `LayermanNavigatorObserver`
/// watches, which briefly becomes the "current route" the moment it's
/// shown — instantly failing the card's own `route:` condition and
/// self-dismissing via `dismissWhenUnmet` (a documented interaction, not a
/// bug — see the layerman README). A non-modal `presentEntry` pushes no
/// route at all, so it never perturbs the tracked route.
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
  bool replace = false,
  bool affix = false,
  bool overlap = false,
  OverlayPredicate? when,
  Object? route,
  bool? requiresAuth,
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
      replace: replace,
      affix: affix,
      overlap: overlap,
      when: when,
      route: route,
      requiresAuth: requiresAuth,
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
    FilledButton.tonal(
      key: Key(key),
      onPressed: onTap,
      child: Text(label),
    );

Widget pageHeader(BuildContext context, String title, String desc) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(desc,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[700])),
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
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
  PresentContext ctx,
  Widget dialog, {
  bool useGetx = false,
}) {
  final name = 'om://${ctx.id}';
  Route<T>? route;
  // A Builder around the caller's static `dialog` widget is enough to grab
  // its ModalRoute once built, for both the showDialog and Get.dialog paths
  // — see [_removeRouteDismiss] for why a captured Route beats popping by name.
  final wrapped = Builder(builder: (dialogCtx) {
    route ??= ModalRoute.of(dialogCtx) as Route<T>?;
    return dialog;
  });
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
    dismiss: ([T? r]) async => _removeRouteDismiss(() => route),
  );
}

// ── shadcn/ui presenters ────────────────────────────────────────────────────

/// Wraps [showShadDialog] in a [PresentedOverlay].
/// Uses a unique route name so [dismiss] can pop it precisely
/// without touching sibling routes.
PresentedOverlay<T> presentShadDialog<T>(
  PresentContext ctx,
  Widget dialog,
) {
  final name = 'om://${ctx.id}';
  Route<T>? route;
  final future = showShadDialog<T>(
    context: Get.overlayContext!,
    routeSettings: RouteSettings(name: name),
    // Wrap with ShadTheme so dialog widgets get the correct shadcn theme
    // even inside a GetX route (which does not automatically inherit from
    // the builder chain's ShadTheme).
    builder: (dialogCtx) {
      route ??= ModalRoute.of(dialogCtx) as Route<T>?;
      return ShadTheme(
        data: ShadThemeData(colorScheme: const ShadSlateColorScheme.light()),
        child: dialog,
      );
    },
  );
  return PresentedOverlay<T>(
    dismissed: future,
    dismiss: ([T? r]) async => _removeRouteDismiss(() => route),
  );
}

/// Shows a [ShadSonner] toast via the global [shadSonnerKey] — no BuildContext
/// needed in the present callback.
///
/// [duration] must match the [ShadToast.duration] so the [PresentedOverlay]
/// knows when the toast has auto-dismissed.  The completer is also completed
/// immediately when [dismiss] is called (programmatic close from layerman).
PresentedOverlay<void> presentShadToast(
  PresentContext ctx, {
  Widget? title,
  required Widget description,
  ShadToastVariant variant = ShadToastVariant.primary,
  Duration duration = const Duration(seconds: 3),
}) {
  final sonner = shadSonnerKey.currentState!;
  final completer = Completer<void>();

  // A small buffer after `duration` covers the exit animation so the next
  // overlay activates only once the toast has visually cleared the screen.
  final autoCompleteDelay = duration + const Duration(milliseconds: 400);

  final toastId = sonner.show(
    ShadToast.raw(
      variant: variant,
      title: title,
      description: description,
      duration: duration,
    ),
  );

  Future.delayed(autoCompleteDelay, () {
    if (!completer.isCompleted) completer.complete();
  });

  return PresentedOverlay<void>(
    dismissed: completer.future,
    dismiss: ([_]) async {
      await sonner.hide(toastId);
      if (!completer.isCompleted) completer.complete();
    },
  );
}
