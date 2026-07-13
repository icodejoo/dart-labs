import 'package:flutter/material.dart';
import '../helpers.dart';
import '../manager.dart';

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
              'duration auto-dismisses after a countdown, exitDuration controls '
              'how long the closing phase lasts before the entry is removed. '
              'gap is a constructor parameter of OverlayManager.'),
          pageSection(
            context,
            'delay — defer first activation',
            [
              demoButton('btn-delay-1s', 'delay: 1s', () {
                om.open(
                    id: 'dly1',
                    delay: const Duration(seconds: 1),
                    builder: (c, h) => buildCard('DELAY 1s', h,
                        hint: 'Appeared 1s after open() was called'));
              }),
              demoButton('btn-delay-3s', 'delay: 3s', () {
                om.open(
                    id: 'dly3',
                    delay: const Duration(seconds: 3),
                    builder: (c, h) => buildCard('DELAY 3s', h,
                        hint: 'Appeared 3s after open() was called'));
              }),
              demoButton('btn-delay-0', 'delay: none (immediate)', () {
                om.open(
                    id: 'dly0',
                    builder: (c, h) =>
                        buildCard('NO DELAY', h, hint: 'Immediate activation'));
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
                om.open(
                    id: 'dur2',
                    duration: const Duration(seconds: 2),
                    builder: (c, h) => buildCard('AUTO 2s', h,
                        hint: 'Closes automatically after 2 seconds'));
              }),
              demoButton('btn-dur-5s', 'duration: 5s', () {
                om.open(
                    id: 'dur5',
                    duration: const Duration(seconds: 5),
                    builder: (c, h) => buildCard('AUTO 5s', h,
                        hint: 'Closes automatically after 5 seconds'));
              }),
              demoButton('btn-dur-manual', 'no duration (manual close)', () {
                om.open(
                    id: 'durman',
                    builder: (c, h) => buildCard('MANUAL', h,
                        hint: 'No auto-close — close button required'));
              }),
            ],
            subtitle:
                'duration: Duration starts counting when the overlay becomes active. '
                'pause(id) / pauseAll() freeze the countdown; '
                'resumeAll() restores the remaining time.',
          ),
          pageSection(
            context,
            'exitDuration — closing phase length',
            [
              demoButton('btn-exit-0', 'exitDuration: 0ms', () {
                om.open(
                    id: 'ex0',
                    exitDuration: Duration.zero,
                    builder: (c, h) =>
                        buildCard('EXIT 0ms', h, hint: 'Disappears instantly on close'));
              }),
              demoButton('btn-exit-600', 'exitDuration: 600ms', () {
                om.open(
                    id: 'ex600',
                    exitDuration: const Duration(milliseconds: 600),
                    builder: (c, h) => buildCard('EXIT 600ms', h,
                        hint: 'Stays in "closing" phase for 600ms.\n'
                            'The phase listenable lets you animate the exit.'));
              }),
              demoButton('btn-exit-default', 'exitDuration: default (200ms)', () {
                om.open(
                    id: 'exdef',
                    builder: (c, h) =>
                        buildCard('EXIT default', h, hint: 'Default exitDuration = 200ms'));
              }),
            ],
            subtitle:
                'exitDuration controls the closing phase before final removal. '
                'Use ValueListenableBuilder on handle.phaseListenable to drive exit animations.',
          ),
          pageSection(
            context,
            'Combine: delay + duration + exitDuration',
            [
              demoButton('btn-all-timing', 'delay 1s → show 3s → exit 500ms', () {
                om.open(
                    id: 'alltm',
                    delay: const Duration(seconds: 1),
                    duration: const Duration(seconds: 3),
                    exitDuration: const Duration(milliseconds: 500),
                    builder: (c, h) => buildCard('ALL TIMING', h,
                        hint: 'delay 1s → auto-close after 3s → exit 500ms'));
              }),
            ],
          ),
        ],
      ),
    );
  }
}
