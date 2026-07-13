import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:layerman/layerman.dart';

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

// ── External presenter helper ────────────────────────────────────────────────

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
