import 'cp2_harness.dart';
import 'cp2_common.dart';
import 'cp2_criteria.dart';
import 'auto_kit.dart' show coverageOnlyOverride;
Future<void> runAudioonlyBg(Cp2Harness h) async {
  for(final variant in ['audio','videoPlain','videoGuard']) {
    for(var run=0;run<h.runs;run++) {
      if (coverageOnlyOverride == 'missing-videoGuard' &&
          (variant != 'videoGuard' || run == 0)) { continue; }
      final api=cp2Engine(h,audioOnly:variant=='audio');h.guarded=variant=='videoGuard';await h.mount(api);
      try {
        await api.open(cp2Source('long'));await h.waitPosition(1000);
        final before=await h.native();final intent=api.state.playbackIntent;
        final samples=await cp2Background(h,'audio.$variant.$run',30);
        if(variant=='videoGuard') await h.until(()=>api.state.playing);
        final after=await h.native();
        final audioOk=cp2AudioSamples(samples,intent:intent)&&api.state.playbackIntent==intent;
        final videoOk=cp2PausedSamples(samples)&&(variant=='videoGuard'?api.state.playing&&api.state.playbackIntent:!api.state.playing&&!api.state.playbackIntent);
        h.check('$variant.$run',{'before':before,'backgroundSamples':samples,'after':after,'foreground':h.snapshot(),
          'intentBefore':intent,'audioEvidence':'native advancing + playing + unmuted active audio track; acoustic output requires listening'},
          pass:variant=='audio'?audioOk:videoOk);
      } finally {await h.release();}
    }
  }
}
