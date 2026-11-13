// 未上机。audioOnly 避免循环创建 VideoController；持续挂树动画提供真实 UI 帧。
import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'cp1_harness.dart';

class _DisposePulse extends StatefulWidget {
  const _DisposePulse(this.onFrame);
  final VoidCallback onFrame;
  @override
  State<_DisposePulse> createState() => _DisposePulseState();
}

class _DisposePulseState extends State<_DisposePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  @override
  void initState() {
    super.initState();
    // Registered once for this mounted widget, never once per mova/round.
    WidgetsBinding.instance.addPersistentFrameCallback((_) {
      if (mounted) widget.onFrame();
    });
    controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: RotationTransition(
      turns: controller,
      child: const Icon(Icons.sync, size: 48),
    ),
  );
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

Future<void> runDispose120(Cp1Harness h) async {
  final ticks = <int>[];
  h.customSurface = _DisposePulse(() => ticks.add(h.clock.elapsedMicroseconds));
  h.refresh();
  await h.frame();
  await h.frame();
  final rounds = <Map<String, Object?>>[];
  final pss = <Map<String, Object?>>[];
  for (var run = 0; run < h.runs; run++) {
    final a = createMova(audioOnly: true, preciseFirstFrame: true);
    h.api = a;
    h.observe(a);
    final begin = h.records.length;
    var disposed = false;
    String? error;
    var start = 0;
    var end = 0;
    try {
      await a.open(h.source('a'));
      await h.until(() => h.events('MovaFirstFrame', begin).isNotEmpty);
      await h.frame();
      start = h.clock.elapsedMicroseconds;
      await a.dispose().timeout(const Duration(seconds: 15));
      end = h.clock.elapsedMicroseconds;
      disposed = true;
    } catch (e) {
      end = h.clock.elapsedMicroseconds;
      error = '$e';
    }
    // Include both boundaries: the frame before dispose and the first one after it.
    await h.frame();
    await h.frame();
    final gaps = <int>[];
    for (var i = 1; i < ticks.length; i++) {
      if (ticks[i] >= start && ticks[i - 1] <= end) {
        gaps.add(ticks[i] - ticks[i - 1]);
      }
    }
    final maxGap = gaps.isEmpty ? null : gaps.reduce((a, b) => a > b ? a : b);
    final frames = h.events('MovaFirstFrame', begin);
    final pass =
        disposed && frames.isNotEmpty && maxGap != null && maxGap < 100000;
    final row = <String, Object?>{
      'round': run + 1,
      'firstFrames': frames,
      'disposeUs': end - start,
      'disposeStartUs': start,
      'disposeEndUs': end,
      'frameIntervalsUs': gaps,
      'maxFrameIntervalUs': maxGap,
      'disposed': disposed,
      'error': error,
      'pass': pass,
    };
    rounds.add(row);
    h.check(
      'round.$run',
      row,
      pass: pass,
      missing: gaps.isEmpty ? 'dispose 区间缺 UI 帧样本' : null,
    );
    if (!disposed) {
      // Do not stack leaked native players after a failed dispose.
      break;
    }
    await h.release(disposeMova: false);
    h.positions.remove(a);
    h.sourceUris.remove(a);
    if ((run + 1) % 20 == 0) {
      final id = 'dispose120.pss.${run + 1}';
      await h.hostSample(id, 'meminfo');
      pss.add({'round': run + 1, ...h.hostData[id]!});
    }
    ticks.removeRange(0, ticks.length > 2 ? ticks.length - 2 : 0);
  }
  final failed = rounds
      .where((r) => r['pass'] != true)
      .map((r) => r['round'])
      .toList();
  final validPss = pss.length == 6 && pss.every((r) => r['pssKb'] is int);
  h.check(
    'summary.0',
    {
      'rounds': rounds,
      'successful': rounds.where((r) => r['pass'] == true).length,
      'failedRounds': failed,
      'pssSamples': pss,
      'criterion':
          '120/120 && every(disposeFrameIntervalUs<100000) && six PSS samples',
    },
    pass: rounds.length == 120 && failed.isEmpty && validPss,
    missing: validPss ? null : '缺每20轮 dumpsys meminfo PSS，共6点',
  );
  h.customSurface = null;
  h.refresh();
  await h.frame();
}
