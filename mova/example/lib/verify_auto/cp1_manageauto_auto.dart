// 未上机。真实三档限速流，策略阈值 1；不注入 buffering 事件。
import 'package:mova/mova.dart';
import 'cp1_harness.dart';

Future<void> runManageauto(Cp1Harness h) async {
  for (final mode in ['managed', 'default', 'disabled', 'lease']) {
    for (var run = 0; run < h.runs; run++) {
      await h.control('reset');
      final a = createMovaEngine(
        preciseFirstFrame: true,
        options: MovaOpts(
          abr: mode == 'default'
              ? const MovaAbrConfig(stallThreshold: 1)
              : MovaAbrConfig(
                  manageAuto: mode == 'managed' || mode == 'lease',
                  enabled: mode != 'disabled',
                  stallThreshold: 1,
                ),
        ),
      );
      await h.mount(a);
      final begin = h.records.length;
      await a.open(
        MovaSource(
          'http://127.0.0.1:18194/master.m3u8?t=${DateTime.now().microsecondsSinceEpoch}',
          type: MovaStreamType.live,
          mpvOptions: const {'hls-bitrate': 'max', 'cache': 'no'},
        ),
      );
      await a.loadQualities();
      await h.until(() => a.state.qualities.length >= 4);
      await h.until(() => a.state.rendered);
      await h.native();
      if (mode == 'lease') {
        final q = a.state.qualities.firstWhere((q) => q.height == 720);
        final leaseBegin = h.records.length;
        final beforeBuffering = a.state.buffering;
        final switching = a.switchQuality(q);
        await h.until(
          () => h
              .events('MovaBufferChange', leaseBegin)
              .any((r) => (r['payload'] as Map)['buffering'] == true),
        );
        await switching;
        await h.until(() => !a.state.buffering);
        final buffers = h.events('MovaBufferChange', leaseBegin);
        final shifts = h.events('MovaAbrDownShift', leaseBegin);
        h.check(
          'lease.$run',
          {
            'beforeBuffering': beforeBuffering,
            'bufferEvents': buffers,
            'downShiftCount': shifts.length,
            'quality': a.state.currentQuality?.label,
            'native': await h.native(),
          },
          pass:
              !beforeBuffering &&
              buffers.any((r) => (r['payload'] as Map)['buffering'] == true) &&
              buffers.any((r) => (r['payload'] as Map)['buffering'] == false) &&
              shifts.isEmpty &&
              a.state.currentQuality?.label == '720p',
        );
      } else {
        await h.control('throttle', {'bytesPerSecond': 16000});
        var observed = true;
        if (mode == 'managed') {
          try {
            await h.until(
              () => h.events('MovaAbrDownShift', begin).isNotEmpty,
              seconds: 90,
            );
          } catch (_) {
            observed = false;
          }
        } else {
          final start = h.clock.elapsedMicroseconds;
          await h.until(
            () => h.clock.elapsedMicroseconds - start >= 30000000,
            seconds: 40,
          );
        }
        final shifts = h.events('MovaAbrDownShift', begin);
        final tier = a.state.currentQuality?.label;
        await h.control('throttle', {'bytesPerSecond': 0});
        final manual = a.state.qualities.firstWhere((q) => q.height == 720);
        await a.switchQuality(manual);
        await h.until(
          () async => ((await h.native())['path'] as String).contains('/720/'),
        );
        final read = await h.native();
        h.check(
          '$mode.$run',
          {
            'downShifts': shifts,
            'downShiftCount': shifts.length,
            'autoTierAfter': tier,
            'manualAfter': a.state.currentQuality?.label,
            'native': read,
            'stats': await h.control('stats'),
          },
          pass:
              (mode == 'managed' ? observed : shifts.isEmpty) &&
              a.state.currentQuality?.label == '720p' &&
              (read['path'] as String).contains('/720/'),
        );
      }
      await h.release();
    }
  }
}
