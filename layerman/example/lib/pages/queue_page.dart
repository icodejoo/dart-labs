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
              'Layerman serializes overlays one-at-a-time per slot. '
              'Configure gap between overlays, priority within the queue, '
              'and named slots that run independently.'),
          pageSection(context, 'open() — auto vs explicit id', [
            demoButton('btn-open-auto', 'open (auto id)', () {
              openCard(
                  'overlay:${DateTime.now().microsecondsSinceEpoch}',
                  text: 'AUTO',
                  hint: 'auto-generated id passed explicitly here for the demo');
            }),
            demoButton('btn-open-id', 'open id: "hello"', () {
              openCard('hello',
                  text: 'HELLO',
                  hint: 'duplicate id replaces the in-queue entry');
            }),
          ]),
          pageSection(
            context,
            'Serial queue — gap: 300ms between overlays',
            [
              demoButton('btn-queue3', 'queue 3 cards', () {
                for (var i = 1; i <= 3; i++) {
                  openCard('q$i', text: 'Q$i');
                }
              }),
            ],
            subtitle:
                'Close Q1 → 300ms gap → Q2 activates → close → Q3. '
                'gap is set on Layerman(gap: Duration(milliseconds: 300)).',
          ),
          pageSection(
            context,
            'slot — independent queues',
            [
              demoButton('btn-slot-default', 'default slot', () {
                openCard('sd-${DateTime.now().millisecondsSinceEpoch}',
                    text: 'DEFAULT', offset: const Offset(0, -60));
              }),
              demoButton('btn-slot-a', 'slot: "A"', () {
                openCard('sa-${DateTime.now().millisecondsSinceEpoch}',
                    text: 'SLOT-A', slot: 'A', offset: const Offset(-90, 60));
              }),
              demoButton('btn-slot-b', 'slot: "B"', () {
                openCard('sb-${DateTime.now().millisecondsSinceEpoch}',
                    text: 'SLOT-B', slot: 'B', offset: const Offset(90, 60));
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
                openCard('plo',
                    text: 'PRIO-0',
                    priority: 0,
                    hint: 'enqueued first, shows second');
              }),
              demoButton('btn-prio-hi', '2. enqueue priority 10', () {
                openCard('phi',
                    text: 'PRIO-10',
                    priority: 10,
                    hint: 'enqueued second, but higher priority → shows first');
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
                openCard('x1', text: 'X1', hint: 'X2 and X3 arrive in 2s');
                Timer(const Duration(seconds: 2), () {
                  if (!identical(m, om)) return;
                  openCard('x2', text: 'X2');
                  openCard('x3', text: 'X3');
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
