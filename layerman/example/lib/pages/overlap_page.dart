import 'package:flutter/material.dart';
import '../helpers.dart';
import '../manager.dart';

class OverlapPage extends StatelessWidget {
  const OverlapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          pageHeader(context, 'Overlap',
              'overlap: true bypasses the serial queue and stacks the overlay '
              'immediately on top. Ineligible overlap entries are dropped (null result). '
              'Named slots each have their own independent serial queue.\n\n'
              'These demos present via a bare OverlayEntry (presentEntry), not a '
              'showDialog route — overlap is meant to coexist with everything else '
              'on screen, and a real modal barrier would block that.'),
          pageSection(
            context,
            'overlap — stack multiple overlays simultaneously',
            [
              demoButton('btn-ovl-a', 'open OVA (then stack OVB from inside)', () {
                openEntry(
                  'ova',
                  text: 'OVA',
                  hint: 'Tap "stack OVB" to layer a second overlay on top',
                  offset: const Offset(0, -60),
                  actions: (close) => [
                    FilledButton.tonal(
                      onPressed: () => openEntry(
                        'ovb',
                        text: 'OVB (overlap)',
                        overlap: true,
                        offset: const Offset(0, 60),
                        hint: 'Both OVA and OVB are visible simultaneously',
                      ),
                      child: const Text('stack OVB'),
                    ),
                  ],
                );
              }),
            ],
            subtitle:
                'overlap: true → activates immediately regardless of what else is shown.',
          ),
          pageSection(
            context,
            '2×2 groups — clearWhere by group tag',
            [
              demoButton('btn-groups', 'open 4 overlapping cards', () {
                openEntry('a1',
                    text: 'A1',
                    overlap: true,
                    data: const {'group': 'a'},
                    offset: const Offset(-130, -70));
                openEntry('a2',
                    text: 'A2',
                    overlap: true,
                    data: const {'group': 'a'},
                    offset: const Offset(-130, 70));
                openEntry('b1',
                    text: 'B1',
                    overlap: true,
                    data: const {'group': 'b'},
                    offset: const Offset(130, -70));
                openEntry('b2',
                    text: 'B2',
                    overlap: true,
                    data: const {'group': 'b'},
                    offset: const Offset(130, 70));
              }),
              demoButton('btn-clear-a-grp', 'clearWhere group == "a"', () {
                om.clearWhere(
                    (r) => r.data is Map && (r.data as Map)['group'] == 'a');
              }),
              demoButton('btn-clear-b-grp', 'clearWhere group == "b"', () {
                om.clearWhere(
                    (r) => r.data is Map && (r.data as Map)['group'] == 'b');
              }),
            ],
            subtitle:
                'data: {"group": "a"} tags overlays; clearWhere filters by predicate. '
                'A and B columns are each 2 overlapping overlays.',
          ),
          pageSection(
            context,
            'Named slots — two independent queues side-by-side',
            [
              demoButton('btn-slot-x', 'open in slot "X"', () {
                openCard('sx-${DateTime.now().millisecondsSinceEpoch}',
                    text: 'SLOT-X', slot: 'X', offset: const Offset(-110, 0));
              }),
              demoButton('btn-slot-y', 'open in slot "Y"', () {
                openCard('sy-${DateTime.now().millisecondsSinceEpoch}',
                    text: 'SLOT-Y', slot: 'Y', offset: const Offset(110, 0));
              }),
              demoButton('btn-queue-both-slots', 'queue 2 in each slot', () {
                for (var i = 1; i <= 2; i++) {
                  openCard('sx$i',
                      text: 'X$i', slot: 'X', offset: const Offset(-110, 0));
                  openCard('sy$i',
                      text: 'Y$i', slot: 'Y', offset: const Offset(110, 0));
                }
              }),
            ],
            subtitle:
                'Each named slot runs its own serial queue. X and Y advance independently.',
          ),
        ],
      ),
    );
  }
}
