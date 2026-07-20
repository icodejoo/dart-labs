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
              'replace: true preempts the current overlay of a slot and shows '
              'immediately. The preempted overlay is CLOSED (result null) — a '
              'dismissed backend cannot be faithfully re-presented, so it never '
              'comes back. affix: true protects an overlay from being preempted — '
              'replace requests queue behind it instead.'),
          pageSection(
            context,
            'replace — preempt and close the current overlay',
            [
              demoButton('btn-replace-demo', 'start replace demo', () {
                openCard(
                  'r1',
                  text: 'R1',
                  hint: 'Tap "replace with R2" to preempt.\n'
                      'R1 is closed for good — it does not come back.',
                  actions: (close) => [
                    FilledButton.tonal(
                      onPressed: () => openCard(
                        'r2',
                        text: 'R2',
                        replace: true,
                        hint: 'R2 preempted R1.\nClosing me does NOT bring R1 back.',
                      ),
                      child: const Text('replace with R2'),
                    ),
                  ],
                );
              }),
            ],
            subtitle:
                'replace: true → current is discarded (closed, result null). '
                'The replacer still front-bands ahead of anything already queued.',
          ),
          pageSection(
            context,
            'replace + priority — replacer sorts correctly',
            [
              demoButton(
                  'btn-replace-prio', 'queue A (prio 0) → replace with B (prio 5)',
                  () {
                openCard('ra',
                    text: 'A prio=0',
                    priority: 0,
                    hint: 'B will preempt and close me — I do not come back');
                openCard('rb',
                    text: 'B replace prio=5', replace: true, priority: 5,
                    hint: 'I preempted A. Closing me advances the queue, not A.');
              }),
            ],
          ),
          pageSection(
            context,
            'affix — prevent replacement',
            [
              demoButton('btn-affix-demo', 'start affix demo', () {
                openCard(
                  'fix',
                  text: 'FIX (affix)',
                  affix: true,
                  hint: 'I cannot be preempted by replace.\nClose me manually.',
                  actions: (close) => [
                    FilledButton.tonal(
                      onPressed: () => openCard(
                        'try',
                        text: 'TRY',
                        replace: true,
                        hint: 'I queued behind FIX instead of preempting',
                      ),
                      child: const Text('try to replace FIX'),
                    ),
                  ],
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
                _affixN.value = 0;
                om.open(
                  id: 'afix-upd',
                  affix: true,
                  present: (ctx) => presentCard(
                    ctx,
                    (c, close) => ValueListenableBuilder<int>(
                      valueListenable: _affixN,
                      builder: (context, n, _) =>
                          buildCard('FIX n=$n', close, hint: 'affix but update() still works'),
                    ),
                  ),
                );
              }),
              demoButton('btn-affix-update-n', 'update n (current second)', () {
                _affixN.value = DateTime.now().second;
                om.update('afix-upd', <String, Object?>{'n': _affixN.value});
              }),
            ],
            subtitle:
                // The manager stores `data` for `resolve`/`PresentContext` only —
                // it has no public "read current data" API once presented, so the
                // card mirrors the live value through its own ValueNotifier
                // (_affixN) while still calling om.update() to exercise the API.
                '_affixN drives the visible text; om.update() is called alongside it '
                'to demonstrate the call site.',
          ),
        ],
      ),
    );
  }
}

/// Local live-update source for the "affix + self-update" demo card — the
/// headless manager has no public way to read an entry's current `data` back
/// out once it is presented, so this mirrors what `om.update('afix-upd', ...)`
/// writes so the card can rebuild.
final ValueNotifier<int> _affixN = ValueNotifier<int>(0);
