import 'package:mova/mova.dart';
import 'cp0_harness.dart';

Future<void> runPod2(Cp0Harness h) async {
  for(var run=0;run<h.runs;run++) {
    final ad1=h.source('ad');final ad2=h.source('ad2');
    final opts=MovaOpts(cutover:const MovaCutoverConfig(enabled:true,minWarmDuration:Duration.zero),
      ads:MovaAdConfig(enabled:true,breaks:[
        MovaAdBreak(kind:MovaAdBreakKind.pre,source:ad1),
        MovaAdBreak(kind:MovaAdBreakKind.pre,source:ad2)]));
    final api=MovaCutoverEngine(engineFactory:()=>createMovaEngine(options:opts,preciseFirstFrame:true));
    await h.mount(api);final ads=MovaAds(api,cutover:api);
    await h.call('ads.load',null,()=>ads.load(h.source('a')));
    await h.until(()=>ads.currentBreak?.source.uri==ad1.uri&&api.state.rendered);
    final epoch1=api.state.renderEpoch;final first=await h.native();
    final firstEvent=h.records.lastWhere((r)=>r['kind']=='EVENT'&&r['event']=='MovaFirstFrame');
    await h.until(()=>ads.currentBreak?.source.uri==ad2.uri&&api.state.rendered,seconds:30);
    await h.until(() async=>(await h.native())['path']==ad2.uri,seconds:20);
    await h.until(()=>h.records.any((r)=>r['event']=='MovaFirstFrame'&&(r['us'] as int)>(firstEvent['us'] as int)));
    final second=await h.native();
    final event=h.records.lastWhere((r)=>r['kind']=='EVENT'&&r['event']=='MovaFirstFrame');
    h.check('ad2.$run',{'epoch1':epoch1,'epoch2':api.state.renderEpoch,'epochDelta':api.state.renderEpoch-epoch1,
      'first':first,'second':second,'firstFrameGapUs':(event['us'] as int)-(firstEvent['us'] as int),
      'doneEvents':h.records.where((r)=>r['event']=='MovaDone').map((r)=>r['us']).toList()});
    await ads.dispose();await h.release();
  }
}
