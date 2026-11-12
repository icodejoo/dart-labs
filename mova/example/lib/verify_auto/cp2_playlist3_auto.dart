import 'package:mova/mova.dart';
import 'cp2_harness.dart';
import 'cp2_common.dart';
Future<void> runPlaylist3(Cp2Harness h) async {
  for(var run=0;run<h.runs;run++) {
    final items=List.generate(3,(i)=>MovaPlaylistItem(source:cp2Source('episode$i'),adBreaks:[
      MovaAdBreak(kind:MovaAdBreakKind.pre,source:cp2Source('ad'),duration:const Duration(seconds:4)),
      MovaAdBreak(kind:MovaAdBreakKind.mid,offset:const Duration(seconds:4),source:cp2Source('ad2'),duration:const Duration(seconds:4))]));
    final callbacks=<Map<String,Object?>>[];
    final rows=<Map<String,Object?>>[]; final ends=<int>[];
    final endEpochs=<int>[];
    MovaPlaylist? list;
    final opts=MovaOpts(cutover:cp2CutoverConfig,playlist:MovaPlaylistConfig(enabled:true,items:items),
      ads:MovaAdConfig(enabled:true,onAdEvent:(e){
        cp2AdEvent(h,e);
        // The next item's pre-roll starts before jumpTo updates currentIndex.
        // Attribute the callback using the scheduled break's unique source.
        final item=items.indexWhere((item)=>(item.adBreaks??const<MovaAdBreak>[]).any((b)=>b.source.uri==e.adBreak.source.uri));
        callbacks.add({'item':item,'uri':e.adBreak.source.uri,'kind':e.adBreak.kind.name,'type':e.type.name});
      }));
    final api=cp2Cutover(h,opts);await h.mount(api);
    final ads=MovaAds(api,cutover:api);list=MovaPlaylist(api,ads:ads);
    final endedNodes=<MovaNodeEnd>[];
    final nodeSub=ads.session.events.listen((e){
      if(e is MovaNodeStart || e is MovaNodeEnd) {
        final node=e is MovaNodeStart ? e.node : (e as MovaNodeEnd).node;
        final type=e is MovaNodeStart ? 'started' : (e as MovaNodeEnd).reason.name;
        final row=<String,Object?>{'item':node.item,'epoch':e.epoch,
          'ordinal':node.ordinal,'kind':node.kind.name,'type':type};
        h.mark('SESSION_NODE',row);
        if(node.kind!=MovaNodeKind.content) { rows.add(row); }
        if(e is MovaNodeEnd && node.kind==MovaNodeKind.content &&
          e.reason==MovaNodeEndReason.completed) { endedNodes.add(e); }
      }
    });
    final sub=ads.contentEnded.listen((_){
      final node=endedNodes.isEmpty?null:endedNodes.removeAt(0);
      ends.add(node?.node.item??-1);endEpochs.add(node?.epoch??-1);
      h.mark('CONTENT_ENDED',{'item':ends.last,'epoch':endEpochs.last});
    });
    final begin=h.records.length;
    try {
      await list.jumpTo(0);await h.until(()=>ends.length>=3,seconds:180);
      await Future<void>.delayed(const Duration(seconds:1));
      final ok=List.generate(3,(i)=>ends.where((e)=>e==i).length==1 && ['pre','mid'].every((k)=>rows.where((r)=>r['item']==i&&r['kind']==k&&r['type']=='started').length==1 && rows.where((r)=>r['item']==i&&r['kind']==k&&r['type']=='completed').length==1)).every((v)=>v);
      final attributed=List.generate(3,(i){
        final epochs=rows.where((r)=>r['item']==i).map((r)=>r['epoch']).toSet();
        final endIndex=ends.indexOf(i);
        return epochs.length==1 && endIndex>=0 && epochs.single==endEpochs[endIndex] &&
          ['pre','mid'].every((k)=>['started','completed'].every((t)=>
            callbacks.where((r)=>r['item']==i&&r['kind']==k&&r['type']==t).length==1));
      }).every((v)=>v);
      h.check('series.$run',{'ads':rows,'adCallbacks':callbacks,'contentEndedEpochs':endEpochs,'contentEnded':ends,'native':await h.native(),'events':h.events('MovaDone',begin)},pass:ok && attributed);
    } finally {await sub.cancel();await nodeSub.cancel();await list.dispose();await ads.dispose();await h.release();}
  }
}
