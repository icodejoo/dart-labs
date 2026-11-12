// 未上机：补 B06 5000 条弹幕前后跳，帧耗时仅记录，无硬线。
import 'package:flutter/scheduler.dart';
import 'package:mova/mova.dart';
import 'cp1_harness.dart';

Future<void> runDanmaku(Cp1Harness h) async {
  for (var run = 0; run < h.runs; run++) {
    final timings = <Map<String, Object?>>[];
    void collect(List<FrameTiming> frames) {
      for (final f in frames) {
        timings.add({
          'buildUs': f.buildDuration.inMicroseconds,
          'rasterUs': f.rasterDuration.inMicroseconds,
          'totalUs': f.totalSpan.inMicroseconds,
        });
      }
    }

    final a = createMovaEngine(
      preciseFirstFrame: true,
      options: MovaOpts(
        danmaku: MovaDanmakuConfig(
          enabled: true,
          items: List.generate(
            5000,
            (i) => MovaDanmakuItem(
              text: 'CP1 $i',
              time: Duration(milliseconds: i * 10),
            ),
          ),
        ),
      ),
    );
    await h.mount(a);
    await a.open(h.source('a'));
    await h.until(() => a.state.rendered);
    SchedulerBinding.instance.addTimingsCallback(collect);
    try {
      for (final ms in [30000, 2000, 45000, 10000]) {
        final begin = h.records.length;
        await a.seek(Duration(milliseconds: ms));
        await h.until(() => h.events('MovaSeeked', begin).isNotEmpty);
        h.mark('JUMP', {
          'targetMs': ms,
          'events': h.events('MovaSeeked', begin),
          'native': await h.native(),
        });
        final start = h.clock.elapsedMicroseconds;
        await h.until(() => h.clock.elapsedMicroseconds - start > 1500000);
      }
      h.check(
        'jump.$run',
        {
          'items': 5000,
          'frameTimings': timings,
          'frameCount': timings.length,
          'criterion':
              'record build/raster/total distributions; compare CP0 manually, no hard line',
        },
        pass: timings.isNotEmpty,
        missing: timings.isEmpty ? '缺 FrameTiming' : null,
      );
    } finally {
      SchedulerBinding.instance.removeTimingsCallback(collect);
      await h.release();
    }
  }
}
