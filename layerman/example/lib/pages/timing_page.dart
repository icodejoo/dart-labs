import 'package:flutter/material.dart';
import '../helpers.dart';

class TimingPage extends StatelessWidget {
  const TimingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          pageHeader(context, 'Timing',
              'Three per-overlay timing parameters: delay defers activation, '
              'duration auto-dismisses after a countdown, exitDuration is the '
              'grace period between the backend closing and the entry actually '
              'being removed (lets a shared exit animation finish). '
              'gap is a constructor parameter of Layerman.'),
          pageSection(
            context,
            'delay — defer first activation',
            [
              demoButton('btn-delay-1s', 'delay: 1s', () {
                openCard('dly1',
                    text: 'DELAY 1s',
                    delay: const Duration(seconds: 1),
                    hint: 'Appeared 1s after open() was called');
              }),
              demoButton('btn-delay-3s', 'delay: 3s', () {
                openCard('dly3',
                    text: 'DELAY 3s',
                    delay: const Duration(seconds: 3),
                    hint: 'Appeared 3s after open() was called');
              }),
              demoButton('btn-delay-0', 'delay: none (immediate)', () {
                openCard('dly0', text: 'NO DELAY', hint: 'Immediate activation');
              }),
            ],
            subtitle:
                'delay: Duration postpones the overlay activation inside its slot. '
                'The entry sits in the queue until the delay elapses, '
                'then the gap starts (if configured).',
          ),
          pageSection(
            context,
            'duration — auto-dismiss countdown',
            [
              demoButton('btn-dur-2s', 'duration: 2s', () {
                openCard('dur2',
                    text: 'AUTO 2s',
                    duration: const Duration(seconds: 2),
                    hint: 'Closes automatically after 2 seconds');
              }),
              demoButton('btn-dur-5s', 'duration: 5s', () {
                openCard('dur5',
                    text: 'AUTO 5s',
                    duration: const Duration(seconds: 5),
                    hint: 'Closes automatically after 5 seconds');
              }),
              demoButton('btn-dur-manual', 'no duration (manual close)', () {
                openCard('durman',
                    text: 'MANUAL', hint: 'No auto-close — close button required');
              }),
            ],
            subtitle:
                'duration: Duration starts counting when the overlay becomes active. '
                'pause(id) / pauseAll() freeze the countdown; '
                'resumeAll() restores the remaining time.',
          ),
          pageSection(
            context,
            'exitDuration — grace before removal',
            [
              demoButton('btn-exit-0', 'exitDuration: none (immediate)', () {
                openCard('ex0',
                    text: 'EXIT none',
                    hint: 'Advances the queue as soon as the dialog reports closed');
              }),
              demoButton('btn-exit-600', 'exitDuration: 600ms', () {
                openCard('ex600',
                    text: 'EXIT 600ms',
                    exitDuration: const Duration(milliseconds: 600),
                    hint: 'Queue waits 600ms after close before the next overlay '
                        'activates — gives the backend room for its own exit '
                        'animation.');
              }),
            ],
            subtitle:
                'exitDuration is a per-open() grace between the backend reporting '
                '"dismissed" and the queue actually advancing. null (the default) '
                'advances immediately — there is no more phase/animation owned by '
                'the manager itself; the backend (showDialog here) plays its own.',
          ),
          pageSection(
            context,
            'Combine: delay + duration + exitDuration',
            [
              demoButton('btn-all-timing', 'delay 1s → show 3s → exit 500ms', () {
                openCard('alltm',
                    text: 'ALL TIMING',
                    delay: const Duration(seconds: 1),
                    duration: const Duration(seconds: 3),
                    exitDuration: const Duration(milliseconds: 500),
                    hint: 'delay 1s → auto-close after 3s → 500ms grace before '
                        'the next overlay activates');
              }),
            ],
          ),
        ],
      ),
    );
  }
}
