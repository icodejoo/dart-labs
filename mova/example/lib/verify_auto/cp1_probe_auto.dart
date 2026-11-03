// 未上机。Dart 探测 UA 与 mpv 媒体请求分开计数。
import 'package:mova/mova.dart';
import 'cp1_harness.dart';

Future<void> runProbe(Cp1Harness h) async {
  for (final kind in ['list', 'manual', 'once', 'failover', 'disabled']) {
    final count = (kind == 'failover' || kind == 'disabled') ? 5 : h.runs;
    for (var run = 0; run < count; run++) {
      await h.control('reset');
      final a = createMovaEngine(
        preciseFirstFrame: true,
        options: MovaOpts(
          abr: MovaAbrConfig(probeVariants: kind != 'disabled'),
          recovery: MovaRecoveryConfig(
            enabled: kind == 'failover',
            policy: const MovaFailoverOnly(),
            stallTimeout: const Duration(seconds: 3),
            liveEndIsFailure: kind == 'failover',
          ),
        ),
      );
      // list is imperative; attach the video only after open returned.
      await h.mount(a, raw: kind == 'list');
      if (kind == 'manual') {
        await h.control('arm', {'kind': 'probe'});
      }
      final uri =
          'http://127.0.0.1:18194/master.m3u8?t=${DateTime.now().microsecondsSinceEpoch}';
      await a.open(
        MovaSource(
          kind == 'failover'
              ? 'http://127.0.0.1:18194/primary.m3u8?t=${DateTime.now().microsecondsSinceEpoch}'
              : uri,
          alternatives: kind == 'failover' ? [uri] : const [],
          type: kind == 'failover' ? MovaStreamType.live : MovaStreamType.vod,
          mpvOptions: kind == 'failover' ? const {
            'demuxer-readahead-secs': '1', 'demuxer-max-bytes': '524288',
            'cache-secs': '1', 'network-timeout': '2'} : const {},
        ),
      );

      if (kind == 'failover') {
        await a.loadQualities();
        await h.until(() => a.state.qualities.isNotEmpty && a.state.rendered);
        await h.control('fail-primary');
        await h.until(() => a.state.sourceIndex == 1, seconds: 90);
      }
      if (kind == 'manual') {
        await h.until(
          () async => (await h.control('stats'))['probeEntered'] == true,
        );
        await a.switchQuality(
          MovaQuality(
            label: '720p',
            uri:
                'http://127.0.0.1:18194/720/index.m3u8?t=${DateTime.now().microsecondsSinceEpoch}',
            height: 720,
          ),
        );
        await h.control('release');
      }
      if (kind == 'disabled') {
        await h.until(() => a.state.rendered);
        await h.frame();
      } else {
        await a.loadQualities();
        await h.until(() => a.state.qualities.isNotEmpty);
      }
      if (kind == 'once') {
        await a.loadQualities();
        await a.loadQualities();
      }
      final stats = await h.control('stats');
      final probes = stats['probes'] as Map;
      final total = probes.values.fold<int>(0, (n, v) => n + (v as int));
      final read = await h.native();
      h.check(
        '$kind.$run',
        {
          'qualities': a.state.qualities.map((q) => q.label).toList(),
          'currentQuality': a.state.currentQuality?.label,
          'probeCounts': probes,
          'probeTotal': total,
          'sourceIndex': a.state.sourceIndex,
          'native': read,
          'fixture': stats,
        },
        pass: kind == 'disabled'
            ? total == 0
            : a.state.qualities.isNotEmpty &&
                  (kind == 'manual'
                      ? a.state.currentQuality?.label == '720p' &&
                            (read['path'] as String).contains('/720/')
                      : true) &&
                  (kind == 'failover'
                      ? a.state.sourceIndex == 1 &&
                            probes.keys.any(
                              (k) => '$k'.contains('primary.m3u8'),
                            ) &&
                            probes.keys.any(
                              (k) => '$k'.contains('master.m3u8'),
                            ) &&
                            probes.values.every((v) => v == 1)
                      : total == 1),
      );
      await h.release();
    }
  }
}
