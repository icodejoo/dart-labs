// 未上机。网络闸门的 entered/released 作为重开在途的证据。
import 'package:mova/mova.dart';
import 'cp1_harness.dart';
import 'cp1_wakeswap_auto.dart' show cp1Live;

Future<void> runEdgepause(Cp1Harness h) async {
  for (final fallback in [false, true]) {
    for (var run = 0; run < h.runs; run++) {
      await h.control('reset');
      final a = createMovaEngine(
        preciseFirstFrame: true,
        options: const MovaOpts(
          live: MovaLiveConfig(backToLive: MovaBackToLive.reopen),
          keepAlive: MovaKeepAliveConfig(allowHls: false),
        ),
      );
      await h.mount(a);
      await a.open(cp1Live('live'));
      await h.until(() => a.state.rendered);
      if (fallback) {
        await (a as MovaKeepAlive).setKeepAlive(true);
      }
      final phase = a.state.keepAlivePhase.name;
      await h.control('arm', {'kind': 'reopen'});
      var returned = false;
      final reopen = a.backToLiveEdge().whenComplete(() => returned = true);
      await h.until(
        () async => (await h.control('stats'))['reopenEntered'] == true,
      );
      final window = await h.control('stats');
      final pending =
          window['reopenEntered'] == true && window['gateReleased'] == false;
      final futurePending = !returned;
      final begin = h.records.length;
      final pauseUs = h.clock.elapsedMicroseconds;
      if (!fallback) {
        await a.pause();
      }
      final at = h.snapshot();
      await h.control('release');
      await reopen;
      await h.until(() async => (await h.native())['pause'] == 'yes');
      final reads = <Map<String, Object?>>[];
      await h.until(() async {
        reads.add(await h.native());
        return h.clock.elapsedMicroseconds - pauseUs > 6000000;
      });
      h.check(
        '${fallback ? 'fallback' : 'pause'}.$run',
        {
          'pendingAtPause': pending,
          'futurePending': futurePending,
          'networkWindow': window,
          'phase': phase,
          'pauseUs': pauseUs,
          'atPause': at,
          'nativeSamples': reads,
          'after': h.snapshot(),
          'bufferEvents': h.events('MovaBufferChange', begin),
        },
        pass:
            pending &&
            reads.every((r) => r['pause'] == 'yes') &&
            !a.state.playing &&
            (fallback
                ? a.state.keepAlivePhase == MovaKeepAlivePhase.fallback
                : !a.state.playbackIntent),
      );
      await h.release();
    }
  }
}
