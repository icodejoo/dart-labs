import 'package:flutter/material.dart';
import '../helpers.dart';
import '../manager.dart';

class ReplaceAffixPage extends StatelessWidget {
  const ReplaceAffixPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          pageHeader(context, 'Replace & Affix',
              'replace: true preempts the current overlay and sends it back to '
              'the front of the queue. affix: true protects an overlay from being '
              'preempted — replace requests queue behind it instead.'),
          pageSection(
            context,
            'replace — preempt the current overlay',
            [
              demoButton('btn-replace-demo', 'start replace demo', () {
                om.open(
                  id: 'r1',
                  builder: (c, h) => buildCard(
                    'R1',
                    h,
                    hint: 'Tap "replace with R2" to preempt.\nR1 returns to queue when R2 closes.',
                    actions: [
                      FilledButton.tonal(
                        onPressed: () => om.open(
                          id: 'r2',
                          replace: true,
                          builder: (c2, h2) => buildCard('R2', h2,
                              hint: 'R2 replaced R1.\nClose me — R1 comes back.'),
                        ),
                        child: const Text('replace with R2'),
                      ),
                    ],
                  ),
                );
              }),
            ],
            subtitle:
                'replace: true → current displaced to front of queue. '
                'replaceBand ensures the replacer sorts ahead of the displaced entry.',
          ),
          pageSection(
            context,
            'replace + priority — replacer sorts correctly',
            [
              demoButton('btn-replace-prio', 'queue A (prio 0) → replace with B (prio 5)', () {
                om.open(
                    id: 'ra',
                    priority: 0,
                    builder: (c, h) => buildCard('A prio=0', h,
                        hint: 'B will preempt me; I return to queue behind B'));
                om.open(
                    id: 'rb',
                    replace: true,
                    priority: 5,
                    builder: (c, h) => buildCard('B replace prio=5', h,
                        hint: 'I preempted A. Close me → A shows'));
              }),
            ],
          ),
          pageSection(
            context,
            'affix — prevent replacement',
            [
              demoButton('btn-affix-demo', 'start affix demo', () {
                om.open(
                  id: 'fix',
                  affix: true,
                  builder: (c, h) => buildCard(
                    'FIX (affix)',
                    h,
                    hint: 'I cannot be preempted by replace.\nClose me manually.',
                    actions: [
                      FilledButton.tonal(
                        onPressed: () => om.open(
                          id: 'try',
                          replace: true,
                          builder: (c2, h2) =>
                              buildCard('TRY', h2, hint: 'I queued behind FIX instead of preempting'),
                        ),
                        child: const Text('try to replace FIX'),
                      ),
                    ],
                  ),
                );
              }),
            ],
            subtitle:
                'affix: true → replace only queues at the front band; '
                'the current overlay is not displaced. '
                'Duplicate-id self-update still works (not blocked by affix).',
          ),
          pageSection(
            context,
            'affix + self-update (not blocked)',
            [
              demoButton('btn-affix-update', 'open affix overlay', () {
                om.open(
                    id: 'afix-upd',
                    affix: true,
                    data: {'n': 0},
                    builder: (c, h) => buildCard(
                        'FIX n=${(h.data as Map)["n"]}', h,
                        hint: 'affix but update() still works'));
              }),
              demoButton('btn-affix-update-n', 'update n (current second)', () {
                om.update('afix-upd', <String, Object?>{'n': DateTime.now().second});
              }),
            ],
          ),
        ],
      ),
    );
  }
}
