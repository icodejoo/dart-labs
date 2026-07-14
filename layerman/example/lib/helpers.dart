import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:layerman/layerman.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'manager.dart';

// ── Overlay card ────────────────────────────────────────────────────────────

Widget buildCard(
  String text,
  OverlayHandle<Object?> handle, {
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
                      onPressed: () => handle.close(),
                      child: const Text('close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
  final Future<T?> future = useGetx
      ? Get.dialog<T>(dialog, routeSettings: RouteSettings(name: name))
      : showDialog<T>(
          context: Get.overlayContext!,
          useRootNavigator: true,
          routeSettings: RouteSettings(name: name),
          builder: (_) => dialog,
        );
  return PresentedOverlay<T>(
    dismissed: future,
    dismiss: ([T? r]) async => Get.until((rt) => rt.settings.name != name),
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
  final future = showShadDialog<T>(
    context: Get.overlayContext!,
    routeSettings: RouteSettings(name: name),
    // Wrap with ShadTheme so dialog widgets get the correct shadcn theme
    // even inside a GetX route (which does not automatically inherit from
    // the builder chain's ShadTheme).
    builder: (_) => ShadTheme(
      data: ShadThemeData(colorScheme: const ShadSlateColorScheme.light()),
      child: dialog,
    ),
  );
  return PresentedOverlay<T>(
    dismissed: future,
    dismiss: ([T? r]) async => Get.until((rt) => rt.settings.name != name),
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
