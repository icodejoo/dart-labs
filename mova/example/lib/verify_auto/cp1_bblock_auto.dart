// 未上机。宿主证据通过 /ack 回传；解析失败必须 BLOCKED。
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mova/mova.dart';
import 'cp1_harness.dart';

Future<void> runBblock(Cp1Harness h) async {
  for (var run = 0; run < h.runs; run++) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await h.hostSample('before.$run', 'system-before');
    final a = createMova(
      orientOpts: const MovaOrientOpts(
        allowedOrients: [DeviceOrientation.portraitUp],
      ),
    );
    await h.mount(a);
    await a.open(h.source('a'));
    await h.until(() => a.state.rendered);
    final seed = a.state.brightness;
    await h.hostSample('gesture.$run', 'brightness-gesture');
    final changed = a.state.brightness;
    await h.hostSample('changed.$run', 'system-changed');
    await a.setFullscreen(true);
    await h.hostSample('full.$run', 'system-full');
    await a.setFullscreen(false);
    await h.hostSample('exit.$run', 'system-exit');
    await h.release();
    await h.hostSample('after.$run', 'system-after');
    final before = h.hostData['before.$run']!,
        after = h.hostData['after.$run']!;
    final exited = h.hostData['exit.$run']!;
    final changedNative = h.hostData['changed.$run']!;
    final parsed =
        before['parsed'] == true &&
        after['parsed'] == true &&
        exited['parsed'] == true;
    h.check(
      'restore.$run',
      {
        'seed': seed,
        'changed': changed,
        'before': before,
        'after': after,
        'seedTolerance': 0.02,
        'changedNative': changedNative,
        'fullscreen': h.hostData['full.$run'],
        'exit': exited,
      },
      pass:
          parsed &&
          seed != changed &&
          (seed - (before['seedBrightness'] as num)).abs() <= 0.02 &&
          changedNative['brightnessOverride'] != before['brightnessOverride'] &&
          before['brightnessOverride'] == after['brightnessOverride'] &&
          before['brightness'] == after['brightness'] &&
          before['displayBrightness'] == after['displayBrightness'] &&
          before['rotation'] == exited['rotation'] &&
          before['insets'] == exited['insets'] &&
          before['rotation'] == after['rotation'] &&
          before['insets'] == after['insets'],
      missing: parsed ? null : 'dumpsys 亮度/rotation/InsetsSource 解析不完整',
    );
    await h.control('reset');
    final b = createMova(
      options: const MovaOpts(
        preview: MovaPreviewOpts(
          vttUrl: 'http://127.0.0.1:18194/hang.vtt',
          debounce: Duration.zero,
          extractFallback: false,
        ),
      ),
    );
    await h.mount(b);
    await b.open(h.source('a'));
    await h.until(() => b.state.rendered);
    final player = (b.renderHandle as VideoController).player;
    b.preview.requestAt(const Duration(seconds: 2));
    await h.until(
      () async => (await h.control('stats'))['hangingBody'] == true,
    );
    final start = h.clock.elapsedMicroseconds;
    var disposed = false;
    try {
      await b.dispose().timeout(const Duration(seconds: 5));
      disposed = true;
    } catch (e) {
      h.mark('DISPOSE_ERROR', {'error': '$e'});
    }
    final elapsed = h.clock.elapsedMicroseconds - start;
    // media_kit exposes NativePlayer.disposed as the primary native owner flag.
    final released = (player.platform as NativePlayer).disposed;
    h.check('preview.$run', {
      'disposeUs': elapsed,
      'disposeCompleted': disposed,
      'nativeReleased': released,
      'fixture': await h.control('stats'),
    }, pass: disposed && elapsed <= 5000000 && released);
    await h.control('release');
    await h.release(disposeMova: !disposed);
  }
}
