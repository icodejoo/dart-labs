import 'package:mova/mova.dart';
import 'cp0_harness.dart';
Future<void> runBgPause(Cp0Harness h) async {
  for(final enabled in [true,false]) {
    for(var run=0;run<h.runs;run++) {
      final api=createMovaEngine(preciseFirstFrame:true);
      await h.mount(api,raw:true,pause:enabled);
      await h.call('open',null,()=>api.open(h.source('a')));await h.waitPosition(500);
      final before=await h.native();
      await h.host('home.$enabled.$run','background');
      final after=await h.native();
      final index=h.records.length;
      if(!api.state.playing) await h.call('play.manualResume',null,api.play);
      await h.waitPosition(1000);
      h.check('video.$enabled.$run',{'videoAutoPause':enabled,'before':before,'after':after,
        'manualResume':h.records.skip(index).any((r)=>r['method']=='play.manualResume')?1:0,
        'lifecycle':h.records.where((r)=>r['kind']=='LIFECYCLE').toList()});
      await h.release();
    }
  }
}
