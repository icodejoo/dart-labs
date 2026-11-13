import 'package:mova/mova.dart';
import 'cp2_harness.dart';
import 'cp2_common.dart';
import 'cp2_criteria.dart';
// Selected by the shared suite's host selector for a five-CHECK fixture rerun.
bool cp2BgownerViewOnly = false;
Future<void> runBgowner(Cp2Harness h) async {
  for(final variant in cp2BgownerViewOnly ? ['view'] : ['plain','view']) {
    for(var run=0;run<h.runs;run++) {
      final api=cp2Mova(h);final source=cp2Source('long');
      if(variant=='view') {
        // A null source renders only the placeholder, without MovaAutoPause.
        // Let the view own opening the same source whose lifecycle we verify.
        h.customSurface=MovaView(source:source,movaFactory:(_)=>api,autoPause:const MovaAutoPauseOpts());
      } else { h.guarded=variant!='plain'; }
      await h.mount(api);
      try {
        if(variant=='plain') await api.open(source);
        await cp2At(h,source.uri);
        await h.waitPosition(1000);
        if(variant=='view') await h.until(()=>h.hasMountedGuard(api));
        final guardMounted=h.hasMountedGuard(api);
        h.mark('GUARD_MOUNT',{'variant':variant,'mounted':guardMounted,'uri':source.uri});
        final begin=h.records.length;
        final before=await h.native();
        final samples=await cp2Background(h,'owner.$variant.$run',6);
        if(variant!='plain') await h.until(()=>api.state.playing);
        final after=await h.native();
        final paused=cp2PausedSamples(samples);
        final foreground=h.snapshot();
        final pass=variant=='plain' ? paused&&!api.state.playing&&!api.state.playbackIntent : paused&&api.state.playing&&api.state.playbackIntent;
        h.check('$variant.$run',{'guardMounted':guardMounted,'source':source.uri,'before':before,'backgroundSamples':samples,'after':after,'foreground':foreground,
          'lifecycle':h.records.skip(begin).where((r)=>r['kind']=='LIFECYCLE').toList()},pass:pass && (variant=='view' ? guardMounted : !guardMounted));
      } finally {

        await h.release();
      }
    }
  }
}
