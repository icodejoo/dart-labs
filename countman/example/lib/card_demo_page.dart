import 'package:flutter/material.dart';
import 'package:countman/countman.dart';

/// Single-widget demo — CountdownCard only. Iterate here before spreading
/// changes to the other countdown widgets.
class CardDemoPage extends StatefulWidget {
  const CardDemoPage({super.key});
  @override
  State<CardDemoPage> createState() => _CardDemoPageState();
}

class _CardDemoPageState extends State<CardDemoPage> {
  int _seed = 0;
  void _restart() => setState(() => _seed++);

  @override
  Widget build(BuildContext context) {
    const to = Duration(minutes: 1, seconds: 30);

    Widget labeled(String label, Widget card) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 6),
            card,
          ],
        );

    return Scaffold(
      appBar: AppBar(title: const Text('CountdownCard Demo')),
      body: Center(
        child: KeyedSubtree(
          key: ValueKey(_seed),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 24,
              runSpacing: 24,
              alignment: WrapAlignment.center,
              children: [
                labeled('calendar (default)', const CountdownCard(to: to)),
                labeled(
                  'slide: none',
                  const CountdownCard(to: to, transitionType: CountdownType.slide),
                ),
                labeled(
                  'slide: scale both',
                  const CountdownCard(
                    to: to,
                    transitionType: CountdownType.slide,
                    scaleEffect: SlideEffect.both,
                  ),
                ),
                labeled(
                  'slide: opacity both',
                  const CountdownCard(
                    to: to,
                    transitionType: CountdownType.slide,
                    opacityEffect: SlideEffect.both,
                  ),
                ),
                labeled(
                  'slide: scale+opacity both',
                  const CountdownCard(
                    to: to,
                    transitionType: CountdownType.slide,
                    scaleEffect: SlideEffect.both,
                    opacityEffect: SlideEffect.both,
                  ),
                ),
                labeled(
                  'slide: scaleFactor 2.5',
                  const CountdownCard(
                    to: to,
                    transitionType: CountdownType.slide,
                    scaleEffect: SlideEffect.both,
                    scaleFactor: 2.5,
                  ),
                ),
                labeled(
                  'slide: enter-only scale+opacity',
                  const CountdownCard(
                    to: to,
                    transitionType: CountdownType.slide,
                    scaleEffect: SlideEffect.enter,
                    opacityEffect: SlideEffect.enter,
                  ),
                ),
                labeled(
                  'slide: exit-only scale+opacity',
                  const CountdownCard(
                    to: to,
                    transitionType: CountdownType.slide,
                    scaleEffect: SlideEffect.exit,
                    opacityEffect: SlideEffect.exit,
                  ),
                ),
                labeled(
                  'flip: none (pure rotate)',
                  const CountdownCard(to: to, transitionType: CountdownType.flip),
                ),
                labeled(
                  'flip: perspective 0.02 (stronger 3D)',
                  const CountdownCard(
                    to: to,
                    transitionType: CountdownType.flip,
                    perspective: 0.02,
                  ),
                ),
                labeled(
                  'flip: scale+opacity both',
                  const CountdownCard(
                    to: to,
                    transitionType: CountdownType.flip,
                    scaleEffect: SlideEffect.both,
                    opacityEffect: SlideEffect.both,
                  ),
                ),
                labeled(
                  'flip: enter-only scale+opacity',
                  const CountdownCard(
                    to: to,
                    transitionType: CountdownType.flip,
                    scaleEffect: SlideEffect.enter,
                    opacityEffect: SlideEffect.enter,
                  ),
                ),
                labeled(
                  'flip: exit-only scale+opacity',
                  const CountdownCard(
                    to: to,
                    transitionType: CountdownType.flip,
                    scaleEffect: SlideEffect.exit,
                    opacityEffect: SlideEffect.exit,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _restart,
        icon: const Icon(Icons.refresh),
        label: const Text('restart'),
      ),
    );
  }
}
