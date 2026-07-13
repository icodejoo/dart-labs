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
              'Named slots each have their own independent serial queue.'),
          pageSection(
            context,
            'overlap — stack multiple overlays simultaneously',
            [
              demoButton('btn-ovl-a', 'open OVA (then stack OVB from inside)', () {
                om.open(
                  id: 'ova',
                  builder: (c, h) => buildCard(
                    'OVA',
                    h,
                    hint: 'Tap "stack OVB" to layer a second overlay on top',
                    offset: const Offset(0, -60),
                    actions: [
                      FilledButton.tonal(
                        onPressed: () => om.open(
                          id: 'ovb',
                          overlap: true,
                          builder: (c2, h2) => buildCard('OVB (overlap)', h2,
                              offset: const Offset(0, 60),
                              hint: 'Both OVA and OVB are visible simultaneously'),
                        ),
                        child: const Text('stack OVB'),
                      ),
                    ],
                  ),
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
                const a = {'group': 'a'};
                const b = {'group': 'b'};
                om.open(
                    id: 'a1', overlap: true, data: a,
                    builder: (c, h) => buildCard('A1', h, offset: const Offset(-130, -70)));
                om.open(
                    id: 'a2', overlap: true, data: a,
                    builder: (c, h) => buildCard('A2', h, offset: const Offset(-130, 70)));
                om.open(
                    id: 'b1', overlap: true, data: b,
                    builder: (c, h) => buildCard('B1', h, offset: const Offset(130, -70)));
                om.open(
                    id: 'b2', overlap: true, data: b,
                    builder: (c, h) => buildCard('B2', h, offset: const Offset(130, 70)));
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
                om.open(
                    id: 'sx-${DateTime.now().millisecondsSinceEpoch}',
                    slot: 'X',
                    builder: (c, h) => buildCard('SLOT-X', h,
                        offset: const Offset(-110, 0)));
              }),
              demoButton('btn-slot-y', 'open in slot "Y"', () {
                om.open(
                    id: 'sy-${DateTime.now().millisecondsSinceEpoch}',
                    slot: 'Y',
                    builder: (c, h) => buildCard('SLOT-Y', h,
                        offset: const Offset(110, 0)));
              }),
              demoButton('btn-queue-both-slots', 'queue 2 in each slot', () {
                for (var i = 1; i <= 2; i++) {
                  om.open(
                      id: 'sx$i', slot: 'X',
                      builder: (c, h) => buildCard('X$i', h, offset: const Offset(-110, 0)));
                  om.open(
                      id: 'sy$i', slot: 'Y',
                      builder: (c, h) => buildCard('Y$i', h, offset: const Offset(110, 0)));
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
