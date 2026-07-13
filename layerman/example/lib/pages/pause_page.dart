import 'package:flutter/material.dart';
import '../helpers.dart';
import '../manager.dart';

class PausePage extends StatelessWidget {
  const PausePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          pageHeader(context, 'Pause & Resume',
              'pauseAll() freezes the entire queue — no new overlays activate, '
              'pending overlaps are held, duration countdowns freeze. '
              'resumeAll() releases everything. '
              'pause(id)/resume(id) freeze a single overlay\'s duration timer. '
              'pauseOnRoutes auto-freezes when the tracked route matches a pattern.'),
          pageSection(
            context,
            'pauseAll() / resumeAll()',
            [
              demoButton('btn-queue-3-for-pause', 'queue 3 cards first', () {
                for (var i = 1; i <= 3; i++) {
                  om.open(id: 'p$i', builder: (c, h) => buildCard('P$i', h));
                }
              }),
              demoButton('btn-pause-all', 'pauseAll()', () {
                om.pauseAll();
              }),
              demoButton('btn-resume-all', 'resumeAll()', () {
                om.resumeAll();
              }),
            ],
            subtitle:
                'Queue 3 cards, then pauseAll — no more activations. '
                'resumeAll releases and the queue advances.',
          ),
          pageSection(
            context,
            'pause(id) / resume(id) — freeze one overlay\'s duration',
            [
              demoButton('btn-dur-for-pause', 'open id:"timer" with duration: 10s', () {
                om.open(
                    id: 'timer',
                    duration: const Duration(seconds: 10),
                    builder: (c, h) =>
                        buildCard('TIMER 10s', h, hint: 'Countdown can be paused/resumed'));
              }),
              demoButton('btn-pause-id', 'pause("timer")', () {
                om.pause('timer');
              }),
              demoButton('btn-resume-id', 'resume("timer")', () {
                om.resume('timer');
              }),
            ],
            subtitle:
                'pause(id) freezes the duration countdown for one overlay only. '
                'resume(id) restores the remaining time. '
                'Unaffected overlays continue normally.',
          ),
          pageSection(
            context,
            'pauseOnRoutes — auto-freeze zone',
            [
              demoButton('btn-queue-in-zone', 'queue a card (stays queued in /zone)', () {
                om.open(
                    id: 'zone-card',
                    builder: (c, h) => buildCard('ZONE CARD', h,
                        hint: 'Queued now; will activate when you leave /zone'));
              }),
              demoButton('btn-goto-zone', '→ navigate to /zone', () {
                Navigator.of(context).push(MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/zone'),
                  builder: (_) => const _ZonePage(),
                ));
              }),
            ],
            subtitle:
                '1. Queue a card above\n'
                '2. Navigate to /zone — queue auto-freezes (OverlayNavigatorObserver + pauseOnRoutes: ["/zone"])\n'
                '3. Navigate back — queue auto-resumes, card activates\n\n'
                'Manual pauseAll and route-zone pausing compose via OR — neither overrides the other.',
          ),
          pageSection(
            context,
            'Manual pause + route zone compose independently',
            [
              demoButton('btn-manual-then-zone', 'pauseAll then navigate to /zone', () {
                om.pauseAll();
                Navigator.of(context).push(MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/zone'),
                  builder: (_) => const _ZonePage(),
                ));
              }),
            ],
            subtitle:
                'Leaving /zone only clears the route-zone pause. '
                'Manual pauseAll stays active — resumeAll() is still needed.',
          ),
          pageSection(
            context,
            'isPaused getter',
            [
              demoButton('btn-check-paused', 'check om.isPaused', () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('om.isPaused = ${om.isPaused}')),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}

class _ZonePage extends StatelessWidget {
  const _ZonePage();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('/zone — no-overlay zone')),
        body: const Center(
          child: Text(
            'pauseOnRoutes: ["/zone"] auto-froze the queue.\n\nPop back to resume.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}
