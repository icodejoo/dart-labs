import 'dart:async';
import 'package:mova/mova.dart';
import 'cp2_harness.dart';
import 'cp2_common.dart';
import 'cp2_criteria.dart';

/// HLS resume tolerance: one keyframe interval of the fixture (1s GOP), because an HLS seek
/// lands on the keyframe at or before the target.
///
/// HLS 续播容差：素材的一个关键帧间隔（GOP 1 秒）——HLS seek 落在目标处或之前的关键帧上。
const int kHlsResumeToleranceMs = 1000;

Future<void> runAdpaths(Cp2Harness h) async {
  for (final format in ['mp4', 'hls']) {
    for (final path in ['pre', 'mid', 'post', 'pod']) {
      for (var run = 0; run < h.runs; run++) {
        final kind = path == 'mid' ? MovaAdBreakKind.mid : path == 'post' ? MovaAdBreakKind.post : MovaAdBreakKind.pre;
        final content = cp2Source(format == 'mp4' ? 'content' : 'vod', hls: format != 'mp4');
        final breaks = List.generate(path == 'pod' ? 2 : 1, (i) => MovaAdBreak(kind: kind,
          source: cp2Source(i == 0 ? 'ad' : 'ad2'), offset: const Duration(seconds: 4), duration: const Duration(seconds: 6)));
        final opts = MovaOpts(cutover: cp2CutoverOpts, ads: MovaAdOpts(enabled: true,
          breaks: breaks, waitForAdReady: const MovaAdWaitByKind(pre:true,mid:true,post:true), onAdEvent: (e) => cp2AdEvent(h,e)));
        final api = cp2Cutover(h, opts);
        await h.mount(api);
        final ads = MovaAds(api, cutover: api);
        final begin = h.records.length;
        final epochs = <int>[api.state.renderEpoch];
        final reads = <Map<String,Object?>>[];
        final frames = <Map<String,Object?>>[];
        Map<String,Object?>? lastContent;
        Map<String,Object?>? entryContent;
        Map<String,Object?>? resumed;
        var ended = 0;
        final endSub = ads.contentEnded.listen((_) { ended++; h.mark('CONTENT_ENDED', {'count':ended}); });
        var sampling = true;
        final sampler = (() async {
          while (sampling) {
            final read = await h.native();
            reads.add(read);
            if (read['path'] == content.uri && !ads.isShowingAd) {
              lastContent = read;
              if (epochs.length > 1) resumed ??= read;
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        })();
        // Observe epoch changes synchronously; readbacks are separately identity fenced.
        final sub = api.states.listen((s) {
          if (s.renderEpoch != epochs.last) {
            if (epochs.length == 1) entryContent = lastContent;
            epochs.add(s.renderEpoch);
          }
        });
        try {
          await ads.load(content);
          for (final b in breaks) {
            await cp2At(h,b.source.uri);
            await h.until(() => h.events('MovaFirstFrame',begin).any((r) => r['uriAtEvent'] == b.source.uri));
            frames.add(h.events('MovaFirstFrame',begin).lastWhere((r) => r['uriAtEvent'] == b.source.uri));
          }
          if (path == 'post') {
            await h.until(() => ended == 1, seconds: 90);
          } else {
            await h.until(() => resumed != null && !ads.isShowingAd, seconds: 90);
          }
          final target = path == 'mid' ? (entryContent?['timePosMs'] as int?) : 0;
          final error = path == 'post' ? null : target == null || resumed == null ? null : (resumed!['timePosMs'] as int) - target;
          final adRows = h.records.skip(begin).where((r) => r['event']=='MovaAdEvent').toList();
          final completed = adRows.where((r) => r['type']=='completed').toList();
          final lifecycle=breaks.every((b)=>cp2AdLifecycle(adRows,b.source.uri,
            kind:b.kind.name,pending:path=='mid')) &&
            adRows.every((r)=>breaks.any((b)=>b.source.uri==r['uri']));
          final expectedCutovers = breaks.length + (path == 'post' ? 0 : 1);
          final increasing = List.generate(epochs.length-1,(i) => epochs[i+1]>epochs[i]).every((v)=>v);
          h.check('$format.$path.$run', {'epochs':epochs,'frames':frames,'nativeSamples':reads,
            'entryContent':entryContent,'resumed':resumed,'resumeErrorMs':error,'ads':adRows,'contentEnded':ended,
            'adLifecycleValid':lifecycle,'expectedAdEvents':path=='mid' ? ['pending','started','completed'] : ['started','completed'],
            'postCriterion':'natural EOF then idle; no content resume is scheduled'},
            missing: path != 'post' && error == null ? 'missing native resume target/readback' : null,
            pass: lifecycle && increasing && epochs.length-1 >= expectedCutovers && frames.length == breaks.length &&
              completed.length == breaks.length && (path == 'post' ? ended == 1 : error != null && error.abs() <= (format == 'hls' ? kHlsResumeToleranceMs : 500)));
        } finally {
          sampling=false; await sampler; await sub.cancel(); await endSub.cancel(); await ads.dispose(); await h.release();
        }
      }
    }
  }
}
