import 'package:flutter/material.dart';
import '../helpers.dart';
import '../manager.dart';

class BarrierPage extends StatelessWidget {
  const BarrierPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          pageHeader(context, 'Barrier & Close',
              'barrierColor paints a scrim behind the overlay. '
              'barrierDismissible: true lets the user tap the scrim to close. '
              'close(id) closes programmatically; isShowing(id) checks live status.'),
          pageSection(
            context,
            'barrierColor — scrim behind overlay',
            [
              demoButton('btn-barrier-light', 'light scrim', () {
                om.open(
                    id: 'bl',
                    barrierColor: const Color(0x44000000),
                    builder: (c, h) => buildCard('Light scrim', h,
                        hint: 'barrierColor: Color(0x44000000)'));
              }),
              demoButton('btn-barrier-dark', 'dark scrim', () {
                om.open(
                    id: 'bd',
                    barrierColor: const Color(0xAA000000),
                    builder: (c, h) => buildCard('Dark scrim', h,
                        hint: 'barrierColor: Color(0xAA000000)'));
              }),
              demoButton('btn-barrier-color', 'coloured scrim', () {
                om.open(
                    id: 'bc',
                    barrierColor: Colors.indigo.withValues(alpha: 0.4),
                    builder: (c, h) =>
                        buildCard('Coloured scrim', h, hint: 'Colors.indigo.withOpacity(0.4)'));
              }),
            ],
          ),
          pageSection(
            context,
            'barrierDismissible — tap scrim to close',
            [
              demoButton('btn-barrier-dismiss', 'dismissible barrier', () {
                om.open(
                    id: 'bdis',
                    barrierColor: const Color(0x66000000),
                    barrierDismissible: true,
                    builder: (c, h) => buildCard('Tap outside to close', h,
                        hint: 'barrierDismissible: true'));
              }),
              demoButton('btn-barrier-nodismiss', 'non-dismissible barrier', () {
                om.open(
                    id: 'bnodis',
                    barrierColor: const Color(0x66000000),
                    barrierDismissible: false,
                    builder: (c, h) => buildCard('Tap outside — nothing happens', h,
                        hint: 'barrierDismissible: false (default)'));
              }),
            ],
            subtitle: 'Tap outside the card — with dismissible it closes, without it stays.',
          ),
          pageSection(
            context,
            'Queue 3 + barrier (barrier-close advances the queue)',
            [
              demoButton('btn-queue3-barrier', 'queue 3 with barrier', () {
                for (var i = 1; i <= 3; i++) {
                  om.open(
                      id: 'c$i',
                      barrierColor: const Color(0x66000000),
                      barrierDismissible: true,
                      builder: (c, h) => buildCard('C$i', h,
                          hint: 'Tap the dark area to close and advance queue'));
                }
              }),
            ],
          ),
          pageSection(
            context,
            'close(id) — programmatic close by id',
            [
              demoButton('btn-open-target', 'open id: "target"', () {
                om.open(
                    id: 'target',
                    builder: (c, h) => buildCard('TARGET', h,
                        hint: 'Will be closed by the button below'));
              }),
              demoButton('btn-close-target', 'close("target")', () {
                om.close('target');
              }),
              demoButton('btn-close-with-result', 'close("target", "ok")', () {
                om.close('target', 'ok');
              }),
            ],
            subtitle:
                'close(id) closes the overlay identified by id. '
                'An optional result value completes the Future<T?> returned by open().',
          ),
          pageSection(
            context,
            'isShowing(id) — check live status',
            [
              demoButton('btn-showing-open', 'open id: "probe"', () {
                om.open(
                    id: 'probe',
                    builder: (c, h) => buildCard('PROBE', h));
              }),
              demoButton('btn-showing-check', 'check isShowing("probe")', () {
                final showing = om.isShowing('probe');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('isShowing("probe") = $showing')),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}
