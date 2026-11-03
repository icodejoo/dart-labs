// 未上机。B=有声流 vid=no/mute=yes；延迟旧重开跨过新源 open。
import 'package:mova/mova.dart';
import 'cp1_harness.dart';

Future<void> runWakeswap(Cp1Harness h) async {
  for (var run = 0; run < h.runs; run++) {
    await h.control('reset');
    final a = createMovaEngine(
      preciseFirstFrame: true,
      options: const MovaOpts(
        keepAlive: MovaKeepAliveConfig(
          allowHls: true,
          liveResumeGrace: Duration.zero,
        ),
      ),
    );
    await h.mount(a);
    final old = cp1Live('live');
    await a.open(old);
    await h.until(() => a.state.rendered);
    await h.native();
    await (a as MovaKeepAlive).setKeepAlive(true);
    final phase = a.state.keepAlivePhase.name;
    final held = await h.native();
    await h.control('arm', {'kind': 'swap'});
    final begin = h.records.length;
    final wakeUs = h.clock.elapsedMicroseconds;
    final wake = (a as MovaKeepAlive).setKeepAlive(false);
    final next = cp1Live('new');
    final openUs = h.clock.elapsedMicroseconds;
    final load = a.open(next);
    await h.until(
      () async => (await h.control('stats'))['swapEntered'] == true,
    );
    await h.until(() => h.clock.elapsedMicroseconds - wakeUs > 6000000);
    await h.control('release');
    await load;
    await h.until(
      () => h
          .events('MovaFirstFrame', begin)
          .any((r) => r['uriAtEvent'] == next.uri),
    );
    await wake;
    // Observe beyond the old 5s resume timer while sampling actual native identity.
    final reads = <Map<String, Object?>>[];
    final observationStart = h.clock.elapsedMicroseconds;
    await h.until(() async {
      reads.add(await h.native());
      return h.clock.elapsedMicroseconds - observationStart > 6000000;
    });
    final frames = h
        .events('MovaFirstFrame', begin)
        .where((r) => r['uriAtEvent'] == next.uri)
        .toList();
    h.check(
      'swap.$run',
      {
        'wakeUs': wakeUs,
        'openUs': openUs,
        'deltaUs': openUs - wakeUs,
        'holdingPhase': phase,
        'held': held,
        'expectedPath': next.uri,
        'frames': frames,
        'nativeSamples': reads,
        'renderEpoch': a.state.renderEpoch,
      },
      pass:
          phase == 'holding' &&
          held['vid'] == 'no' &&
          held['mute'] == 'yes' &&
          openUs - wakeUs < 5000000 &&
          frames.isNotEmpty &&
          reads.every((r) => r['path'] == next.uri),
    );
    await h.release();
  }
}

MovaSource cp1Live(String name) => MovaSource(
  'http://127.0.0.1:18194/$name.m3u8?t=${DateTime.now().microsecondsSinceEpoch}',
  type: MovaStreamType.live,
  // The 6s race stimulus must outlive the old 5s wake timer without the
  // replacement source itself timing out first.
  mpvOptions: name == 'new' ? const {'network-timeout': '20'} : const {},
);
