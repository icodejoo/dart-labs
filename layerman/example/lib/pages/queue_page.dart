import 'dart:async';
import 'package:flutter/material.dart';
import '../helpers.dart';
import '../manager.dart';

class QueuePage extends StatelessWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          pageHeader(context, 'Queue Basics',
              'OverlayManager serializes overlays one-at-a-time per slot. '
              'Configure gap between overlays, priority within the queue, '
              'and named slots that run independently.'),
          pageSection(context, 'open() — auto vs explicit id', [
            demoButton('btn-open-auto', 'open (auto id)', () {
              om.open(builder: (c, h) => buildCard('AUTO', h,
                  hint: 'id = "overlay:N" (auto-generated)'));
            }),
            demoButton('btn-open-id', 'open id: "hello"', () {
              om.open(
                  id: 'hello',
                  builder: (c, h) => buildCard('HELLO', h,
                      hint: 'duplicate id replaces the in-queue entry'));
            }),
          ]),
          pageSection(
            context,
            'Serial queue — gap: 300ms between overlays',
            [
              demoButton('btn-queue3', 'queue 3 cards', () {
                for (var i = 1; i <= 3; i++) {
                  om.open(
                      id: 'q$i', builder: (c, h) => buildCard('Q$i', h));
                }
              }),
            ],
            subtitle:
                'Close Q1 → 300ms gap → Q2 activates → close → Q3. '
                'gap is set on OverlayManager(gap: Duration(milliseconds: 300)).',
          ),
          pageSection(
            context,
            'slot — independent queues',
            [
              demoButton('btn-slot-default', 'default slot', () {
                om.open(
                    id: 'sd-${DateTime.now().millisecondsSinceEpoch}',
                    builder: (c, h) => buildCard('DEFAULT', h,
                        offset: const Offset(0, -60)));
              }),
              demoButton('btn-slot-a', 'slot: "A"', () {
                om.open(
                    id: 'sa-${DateTime.now().millisecondsSinceEpoch}',
                    slot: 'A',
                    builder: (c, h) => buildCard('SLOT-A', h,
                        offset: const Offset(-90, 60)));
              }),
              demoButton('btn-slot-b', 'slot: "B"', () {
                om.open(
                    id: 'sb-${DateTime.now().millisecondsSinceEpoch}',
                    slot: 'B',
                    builder: (c, h) => buildCard('SLOT-B', h,
                        offset: const Offset(90, 60)));
              }),
            ],
            subtitle:
                'Each named slot has its own independent queue. '
                'Default slot is "" (empty string).',
          ),
          pageSection(
            context,
            'priority — higher int shows first',
            [
              demoButton('btn-prio-lo', '1. enqueue priority 0', () {
                om.open(
                    id: 'plo',
                    priority: 0,
                    builder: (c, h) => buildCard('PRIO-0', h,
                        hint: 'enqueued first, shows second'));
              }),
              demoButton('btn-prio-hi', '2. enqueue priority 10', () {
                om.open(
                    id: 'phi',
                    priority: 10,
                    builder: (c, h) => buildCard('PRIO-10', h,
                        hint: 'enqueued second, but higher priority → shows first'));
              }),
            ],
            subtitle:
                'Tap LOW first, then HIGH while LOW is visible — HIGH jumps to the front.',
          ),
          pageSection(
            context,
            'Programmatic enqueue with Timer',
            [
              demoButton('btn-prog', 'show X1 now + X2/X3 after 2s', () {
                final m = om;
                m.open(
                    id: 'x1',
                    builder: (c, h) =>
                        buildCard('X1', h, hint: 'X2 and X3 arrive in 2s'));
                Timer(const Duration(seconds: 2), () {
                  if (!identical(m, om)) return;
                  m.open(id: 'x2', builder: (c, h) => buildCard('X2', h));
                  m.open(id: 'x3', builder: (c, h) => buildCard('X3', h));
                });
              }),
            ],
            subtitle: 'The manager holds the slot; late arrivals queue naturally.',
          ),
        ],
      ),
    );
  }
}
