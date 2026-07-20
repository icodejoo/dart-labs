import 'package:flutter/material.dart';
import 'package:layerman/layerman.dart';
import '../helpers.dart';
import '../manager.dart';

class CooldownPage extends StatelessWidget {
  const CooldownPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          pageHeader(context, 'Cooldown',
              'OverlayCooldown caps overlay frequency. '
              'session/total count total shows; day/hour/minute cap per calendar window; '
              'minGap enforces a minimum elapsed time between shows. '
              'Combine caps — the most restrictive wins.'),
          pageSection(
            context,
            'session — max shows per app session',
            [
              demoButton('btn-cds', 'session: 1 (once per session)', () {
                openCard('cd-s',
                    text: 'SESSION 1',
                    cooldown: const OverlayCooldown(session: 1),
                    hint: 'Tap again — blocked until app restarts');
              }),
              demoButton('btn-cds3', 'session: 3', () {
                openCard('cd-s3-${DateTime.now().millisecondsSinceEpoch}',
                    text: 'SESSION 3',
                    cooldown: const OverlayCooldown(session: 3),
                    hint: 'Up to 3 shows per session');
              }),
            ],
            subtitle:
                'session count resets on app restart (in-memory; not persisted). '
                'Use the Setup → restart to reset it.',
          ),
          pageSection(
            context,
            'total — lifetime show cap (requires persistent storage)',
            [
              demoButton('btn-cdt', 'total: 2', () {
                openCard('cd-t',
                    text: 'TOTAL 2',
                    cooldown: const OverlayCooldown(total: 2),
                    hint: 'Shown at most 2 times ever (persisted)');
              }),
            ],
            subtitle:
                'total persists via OverlayCooldownStorage. '
                'Default MemoryCooldownStorage resets each session; '
                'plug in SharedPreferences adapter for true persistence.',
          ),
          pageSection(
            context,
            'minGap — minimum time between shows',
            [
              demoButton('btn-cdg', 'minGap: 5s', () {
                openCard('cd-g',
                    text: 'GAP 5s',
                    cooldown: const OverlayCooldown(minGap: Duration(seconds: 5)),
                    hint:
                        'Close then try again within 5s → queued, auto-shows at 5s');
              }),
            ],
            subtitle:
                'minGap arms a self-wake timer: when the gap expires the entry '
                'activates automatically without needing another user action.',
          ),
          pageSection(
            context,
            'day — max shows per calendar day',
            [
              demoButton('btn-cdd', 'day: 1 (once per day)', () {
                openCard('cd-d',
                    text: 'DAY 1',
                    cooldown: const OverlayCooldown(day: 1),
                    hint: 'Max 1 show per calendar day');
              }),
              demoButton('btn-cdd3', 'day: 3', () {
                openCard('cd-d3-${DateTime.now().millisecondsSinceEpoch}',
                    text: 'DAY 3',
                    cooldown: const OverlayCooldown(day: 3),
                    hint: 'Max 3 shows per calendar day');
              }),
            ],
          ),
          pageSection(
            context,
            'hour — max shows per clock hour',
            [
              demoButton('btn-cdh', 'hour: 2', () {
                openCard('cd-h-${DateTime.now().millisecondsSinceEpoch}',
                    text: 'HOUR 2',
                    cooldown: const OverlayCooldown(hour: 2),
                    hint: 'Max 2 shows per clock hour');
              }),
            ],
          ),
          pageSection(
            context,
            'minute — max shows per clock minute',
            [
              demoButton('btn-cdm', 'minute: 1', () {
                openCard('cd-m',
                    text: 'MIN 1',
                    cooldown: const OverlayCooldown(minute: 1),
                    hint: 'Max 1 show per clock minute');
              }),
            ],
          ),
          pageSection(
            context,
            'Combine caps — most restrictive wins',
            [
              demoButton('btn-cdcombine', 'session:2 + minGap:3s', () {
                openCard('cd-combo-${DateTime.now().millisecondsSinceEpoch}',
                    text: 'COMBO',
                    cooldown: const OverlayCooldown(
                        session: 2, minGap: Duration(seconds: 3)),
                    hint: 'session:2 AND minGap:3s — both must pass');
              }),
            ],
          ),
          pageSection(
            context,
            'ready() — await persisted cooldown hydration',
            [
              demoButton('btn-ready', 'await om.ready() then open', () async {
                await om.ready();
                openCard('cd-ready',
                    text: 'READY',
                    cooldown: const OverlayCooldown(total: 5),
                    hint: 'Opened after ready() resolved — '
                        'persisted total/day/hour counts are now hydrated');
              }),
            ],
            subtitle:
                'await om.ready() before relying on total/day/hour caps '
                'that persist across restarts. session/minGap are in-memory and do not need ready().',
          ),
        ],
      ),
    );
  }
}
