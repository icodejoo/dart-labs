import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'cp0_harness.dart';
Future<void> runPageView(Cp0Harness h) async {
  for(final axis in [Axis.horizontal,Axis.vertical]) {
    for(var run=0;run<h.runs;run++) {
      final api=createMovaEngine(preciseFirstFrame:true);
      await h.mount(api,axis:axis);await h.call('open',null,()=>api.open(h.source('a')));await h.waitPosition(1000);await h.call('pause',null,api.pause);
      final before=await h.native();final cursor=h.records.length;
      await h.host('gesture.${axis.name}.$run','swipe-${axis.name}');
      final after=await h.native();
      h.check('${axis.name}.$run',{'before':before,'after':after,'pageIndex':h.pageIndex,
        'seekEvents':h.records.skip(cursor).where((r)=>r['event']=='MovaSeek').length,
        'pageEvents':h.records.skip(cursor).where((r)=>r['kind']=='PAGE').length});
      await h.release();
    }
  }
  h.check('audioFocus',{},missing:'manual：需来电设备或可抢音频焦点的其他 App；步骤见 CP0 文档');
}
