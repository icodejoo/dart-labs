import 'package:mova/mova.dart';
import 'cp0_harness.dart';
Future<void> runTimeshift(Cp0Harness h) async {
  for(final mode in [MovaLiveSeekMode.dvr,MovaLiveSeekMode.timeshift]) {
    for(var run=0;run<h.runs;run++) {
      final builds=<Map<String,Object?>>[];
      final api=createMovaEngine(preciseFirstFrame:true,options:MovaOpts(live:MovaLiveConfig(
        seekMode:mode,dvrWindow:const Duration(seconds:12),edgeThreshold:const Duration(seconds:1),durationStep:Duration.zero,
        urlBuilder:(uri,behind,wallClock){
          final shifted=Uri.parse(uri).replace(queryParameters:{'behind':'${behind.inMilliseconds}',
            't':'${DateTime.now().microsecondsSinceEpoch}'}).toString();
          final row=<String,Object?>{'source':uri,'behindMs':behind.inMilliseconds,'shifted':shifted};
          builds.add(row);h.mark('URL_BUILDER',row);return shifted;
        })));
      await h.mount(api);await h.call('open.liveHls',null,()=>api.open(h.source('live',live:true)));
      await h.until(()=>api.state.rendered&&api.state.duration>Duration.zero);
      final before=await h.native();final cursor=h.records.length;
      // Pick the same in-window target for both modes, independent of mpv's
      // potentially growing/absolute native timeline. Record the mismatch.
      const target=Duration(seconds:4);
      await h.call('seek.${mode.name}',target.inMilliseconds,()=>api.seek(target));
      await h.until(()=>h.records.skip(cursor).any((r)=>r['event']=='MovaTimeShiftChange'));
      await h.until(()=>api.state.rendered);
      final behind=await h.native();
      final behindState=api.state.timeshiftBehind?.inMilliseconds;
      final p=(behind['timePosMs'] as int);
      await h.until(() async=>(await h.native())['timePosMs'] as int>=p+500);
      final advancing=await h.native();
      final edgeCursor=h.records.length;
      await h.call('backToLiveEdge',null,api.backToLiveEdge);
      await h.until(()=>h.records.skip(edgeCursor).any((r)=>r['event']=='MovaLiveEdgeReach'));
      final after=await h.native();
      h.check('${mode.name}.$run',{'before':before,'targetMs':target.inMilliseconds,'behind':behind,
        'behindStateMs':behindState,'advancing':advancing,'edge':after,'builders':builds,
        'timeshiftEvents':h.records.skip(cursor).where((r)=>r['event']=='MovaTimeShiftChange'||r['event']=='MovaLiveEdgeReach').toList()});
      await h.release();
    }
  }
}
