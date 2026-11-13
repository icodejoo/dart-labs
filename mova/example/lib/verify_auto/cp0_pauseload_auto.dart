import 'dart:async';
import 'package:mova/mova.dart';
import 'cp0_harness.dart';
Future<void> runPauseLoad(Cp0Harness h) async {
  for(final gate in ['loading','ready','firstFrame']) {
    for(var run=0;run<h.runs;run++) {
      final reports=<Map<String,Object?>>[];
      final api=createMova(preciseFirstFrame:true,options:const MovaOpts(report:MovaReportOpts(qoe:true)),
        reporter:MovaCallbackReporter((r){final row=<String,Object?>{'name':r.name.value,'params':r.params};reports.add(row);h.mark('REPORT',row);}));
      await h.mount(api);await h.call('open(A)',null,()=>api.open(h.source('a')));await h.waitPosition(1500);await h.call('pause',null,api.pause);
      final before=await h.native();final begin=h.records.length;
      final b=h.source('b',slow:true);
      final load=h.call('open(B,autoPlay:false)',b.uri,()=>api.open(b,autoPlay:false));
      if(gate=='loading') await h.until(()=>api.state.buffering);
      if(gate=='ready') await h.until(()=>h.records.skip(begin).any((r)=>r['event']=='MovaReady'));
      if(gate=='firstFrame') await h.until(()=>h.records.skip(begin).any((r)=>r['event']=='MovaFirstFrame'));
      final trigger=h.clock.elapsedMicroseconds;
      final at=h.snapshot();await h.call('play.$gate',null,api.play);await load;
      await h.until(() async=>(await h.native())['path']==b.uri&&api.state.rendered);
      final finalRead=await h.native();
      final frame=h.records.skip(begin).where((r)=>r['event']=='MovaFirstFrame').first;
      h.check('$gate.$run',{'before':before,'playState':at,'playUs':trigger,
        'firstFrameUs':frame['us'],'playToFirstFrameUs':(frame['us'] as int)-trigger,
        'after':finalRead,'reports':reports.where((r)=>r['name']=='sessionStart').toList(),
        'playingAfterLoad':api.state.playing?1:0});
      await h.release();
    }
  }
}
