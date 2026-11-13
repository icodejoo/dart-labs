import 'package:mova/mova.dart';
import 'cp2_common.dart';
import 'cp2_harness.dart';

Future<void> runPod2(Cp2Harness h) async {
  for (final wait in [true, false]) {
    for (var run = 0; run < h.runs; run++) {
      final ad1 = cp2Source('ad');
      final ad2 = cp2Source('ad2');
      final opts = MovaOpts(
        cutover: const MovaCutoverOpts(
          enabled: true,
          minWarmDuration: Duration.zero,
        ),
        ads: MovaAdOpts(
          enabled: true,
          waitForAdReady: MovaAdWaitByKind(pre: wait),
          breaks: [
            MovaAdBreak(
              kind: MovaAdBreakKind.pre,
              source: ad1,
              duration: const Duration(seconds: 6),
            ),
            MovaAdBreak(
              kind: MovaAdBreakKind.pre,
              source: ad2,
              duration: const Duration(seconds: 6),
            ),
          ],
          onAdEvent: (e) => cp2AdEvent(h, e),
        ),
      );
      final api = MovaCutover(
        movaFactory: () => cp2Mova(h, options: opts),
      );
      await h.mount(api);
      final ads = MovaAds(api, cutover: api);
      final start = h.records.length;
      final epoch0 = api.state.renderEpoch;
      Map<String, Object?>? firstFrame(String uri) {
        for (final r in h.records.skip(start).toList().reversed) {
          final state = r['state'];
          if (r['kind'] == 'EVENT' &&
              r['event'] == 'MovaFirstFrame' &&
              state is Map &&
              state['renderEpoch'] == api.state.renderEpoch &&
              r['uriAtEvent'] == uri) {
            return r;
          }
        }
        return null;
      }

      try {
        await h.call('ads.load', {
          'waitForAdReady.pre': wait,
        }, () => ads.load(cp2Source('content')));
        await h.until(
          () => ads.currentBreak?.source.uri == ad1.uri && api.state.rendered,
        );
        await h.until(() async => (await h.native())['path'] == ad1.uri);
        await h.until(() => firstFrame(ad1.uri) != null);
        final epoch1 = api.state.renderEpoch;
        final first = await h.native();
        final firstEvent = firstFrame(ad1.uri)!;
        await h.until(
          () => ads.currentBreak?.source.uri == ad2.uri && api.state.rendered,
        );
        await h.until(() async => (await h.native())['path'] == ad2.uri);
        await h.until(() {
          final event = firstFrame(ad2.uri);
          return event != null &&
              (event['us'] as int) > (firstEvent['us'] as int);
        });
        final second = await h.native();
        final event = firstFrame(ad2.uri)!;
        h.check(
          '${wait ? 'wait' : 'nowait'}.ad2.$run',
          {
            'waitForAdReadyPre': wait,
            'epoch0': epoch0,
            'epoch1': epoch1,
            'epoch2': api.state.renderEpoch,
            'firstEpochDelta': epoch1 - epoch0,
            'epochDelta': api.state.renderEpoch - epoch1,
            'first': first,
            'second': second,
            'firstFrame1Us': firstEvent['us'],
            'firstFrame2Us': event['us'],
            'firstFrame1': firstEvent,
            'firstFrame2': event,
            'firstFrameGapUs': (event['us'] as int) - (firstEvent['us'] as int),
            'doneEvents': h.records
                .skip(start)
                .where((r) => r['event'] == 'MovaDone')
                .map((r) => r['us'])
                .toList(),
            'sameMova': first['mova'] == second['mova'],
          },
          pass:
              (wait ? epoch1 > epoch0 : epoch1 >= epoch0) &&
              (!wait || api.state.renderEpoch > epoch1) &&
              (wait || first['mova'] == second['mova']) &&
              first['path'] == ad1.uri &&
              second['path'] == ad2.uri,
        );
      } finally {
        try {
          await ads.dispose();
        } finally {
          await h.release();
        }
      }
    }
  }
}
