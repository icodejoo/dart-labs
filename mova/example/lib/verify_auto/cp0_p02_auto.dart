import 'dart:async';
import 'package:mova/mova.dart';
import 'cp0_harness.dart';

Future<void> runP02(Cp0Harness h) async {
  for(final trigger in ['contentWarm','midPending','postLoad']) {
    for(var run=0;run<h.runs;run++) {
      final aSource=h.source('a');final bSource=h.source('b');final ad=h.source('ad');
      final kind=trigger=='midPending'?MovaAdBreakKind.mid:trigger=='postLoad'?MovaAdBreakKind.post:MovaAdBreakKind.pre;
      final opts=MovaOpts(cutover:const MovaCutoverOpts(enabled:true,minWarmDuration:Duration.zero,leadTime:Duration(seconds:20)),
        ads:MovaAdOpts(enabled:true,breaks:[MovaAdBreak(kind:kind,source:ad,
          offset:const Duration(milliseconds:500),delay:kind==MovaAdBreakKind.mid?const Duration(seconds:3):Duration.zero)]));
      final api=MovaCutover(movaFactory:()=>createMova(options:opts,preciseFirstFrame:true));
      await h.mount(api);final ads=MovaAds(api,cutover:api);
      final load=h.call('ads.load',aSource.uri,()=>ads.load(aSource));
      if(trigger=='contentWarm') {
        await h.until(()=>ads.isShowingAd && api.cutoverPhase!=MovaCutoverPhase.idle);
      } else if(trigger=='midPending') {
        await h.until(()=>ads.isAdPending);
      } else {
        await h.until(()=>ads.currentBreak?.kind==MovaAdBreakKind.post,seconds:45);
        await h.until(()=>!ads.isShowingAd,seconds:30);
      }
      final before=await h.native();
      h.mark('TRIGGER',{'trigger':trigger,'phase':api.cutoverPhase.name,'showingAd':ads.isShowingAd,'pending':ads.isAdPending});
      final cursor=h.records.length;
      await h.call('ads.load(B)',bSource.uri,()=>ads.load(bSource));
      await load;
      var observationLimit=0;
      try {
        await h.until(() async {
          final read=await h.native();
          return !ads.isShowingAd&&!ads.isAdPending&&api.state.rendered&&
            (read['path']==aSource.uri||read['path']==bSource.uri)&&
            h.records.skip(cursor).any((r)=>r['event']=='MovaFirstFrame');
        },seconds:20);
      } on TimeoutException {
        observationLimit=1;
        h.mark('OBSERVATION_LIMIT',{'trigger':trigger,'reason':'no content first-frame/path before watchdog'});
      }
      final after=await h.native();
      h.check('$trigger.$run',{'before':before,'after':after,'expectedPath':bSource.uri,
        'wrongEpisode':after['path']==aSource.uri?1:0,'stillAd':after['path']==ad.uri?1:0,
        'matchesB':after['path']==bSource.uri?1:0,'observationLimit':observationLimit,
        'firstFrameEventUs':h.records.skip(cursor).where((r)=>r['event']=='MovaFirstFrame').map((r)=>r['us']).toList(),
        'doneEventUs':h.records.skip(cursor).where((r)=>r['event']=='MovaDone').map((r)=>r['us']).toList(),
        'renderEpoch':api.state.renderEpoch});
      await h.call('ads.dispose',null,ads.dispose);await h.release();
    }
  }
}
