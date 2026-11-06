"""Summarize the completed R4 evidence without rerunning any device batch."""
import json,statistics,sys
from pathlib import Path
import cp3_r4 as campaign

def main():
    campaign.OUT=out=Path(sys.argv[1]).resolve()
    s=json.loads((out/'state.json').read_text(encoding='utf-8'))
    head=__import__('subprocess').check_output(['git','rev-parse','HEAD'],cwd=campaign.ROOT,text=True).strip()
    if head not in s['commits']:s['commits'].append(head)
    a=campaign.analyze(campaign.ROOT/s['row']['evidence']);s['analysis']=a
    e,p=a['extract'],a['pool']
    e['successRate']=e['success']/e['total'];e['previousSuccessRate']=28/30
    e['elapsedMsRange']=[min(e['elapsedMs']),max(e['elapsedMs'])]
    # A timeout retry cannot occur before the entire first 5-second landing
    # poll expires. A shorter end-to-end call rules it out, but this is an
    # inference from the product control flow, not an internal counter.
    e['retryHitsInferredFromElapsed']=0 if e['elapsedMsRange'][1]<5000 else None
    e['retryInference']='调用总耗时不足5000ms时，可按源码排除首次5s落地超时后的重发；超过5s的成功只能列候选，无直接回执'
    e['retryHitCandidates']=len(e['slowOver5s'])
    e['retryHitBoundsFromElapsed']=[0,len(e['slowOver5s'])]
    recovered=[]
    for row in p['samples']:
        shots=row.get('shots',[])
        if not shots or not shots[0]['null']:continue
        first=next((x for x in shots if x.get('bytes')),None)
        recovered.append(dict(bindReturnedMs=row['bindReturnedMs'],initial=shots[0],firstSuccess=first,
          additionalWaitToSuccessMs=first['atMs']-shots[0]['returnedMs'] if first else None,
          sinceBindReturnedMs=first['atMs']-row['bindReturnedMs'] if first else None))
    p['nullRecoveries']=recovered
    p['nullRecoverySinceBindReturnMsRange']=[min(x['sinceBindReturnedMs'] for x in recovered if x['firstSuccess']),max(x['sinceBindReturnedMs'] for x in recovered if x['firstSuccess'])] if recovered else []
    p['nullRecoveryAdditionalWaitMsRange']=[min(x['additionalWaitToSuccessMs'] for x in recovered if x['firstSuccess']),max(x['additionalWaitToSuccessMs'] for x in recovered if x['firstSuccess'])] if recovered else []
    p['nullRecovered']=sum(x['firstSuccess'] is not None for x in recovered)
    old=json.loads(campaign.SUMMARY.with_suffix('.json').read_text(encoding='utf-8'))['thirdRoundRevalidation']
    previous=[]
    for row in old['attempts']:
        if row['batch']=='cp3-headers':
            for c in row['observations']['headerChecks']:
                previous.append(c['nativePaths']['pool']['observations']['authorized'])
    p['previous']=dict(total=len(previous),null=sum(x.get('imageBytes') is None for x in previous))
    phases=p['phases'];gate=phases.get('renderer-first-frame-gate',{});later=phases.get('additional-wait-100',{})
    s['conclusion']=('仍待定：抽帧本轮 '+str(e['success'])+'/'+str(e['total'])+'，上轮28/30；'
      f"约5s以上成功{e['retryHitCandidates']}次，与重发后恢复相容；精确重试命中未知（耗时仅能约束0至{e['retryHitCandidates']}），不能排除open本身延迟，修复有效性仍待定。"
      f"池原始null {p['originalNull']}/{p['total']}（上轮{p['previous']['null']}/{p['previous']['total']}）；"
      f"首帧gate后null {gate.get('null')}/{gate.get('total')}，再等100ms后null {later.get('null')}/{later.get('total')}。"
      f"原始null恢复{p['nullRecovered']}/{len(recovered)}，支持夹具截图时机窗口；首帧future不足以保证截图就绪，原始问题未关闭。")
    s['row']['suspectedLocations']='example/lib/verify_auto/cp3_pages_auto.dart:runHeaders; lib/src/core/engine_pool.dart:_openBinding; lib/src/platform_impl/mpv_extractor_impl.dart:_extractNow'
    s['row']['classification']='原始CHECK失败保留；扩样与等待对照单列，不用延迟成功覆盖原始null'
    s['row']['comparison']=f"抽帧28/30→{e['success']}/{e['total']}；池原始null {p['previous']['null']}/{p['previous']['total']}→{p['originalNull']}/{p['total']}"
    verification=campaign.ROOT/s['row']['evidence']/(Path(s['row']['evidence']).name+'-build.json')
    s['installationVerification']=json.loads(verification.read_text(encoding='utf-8'))
    deviation='未重跑失败批次；同一批次逐样本捕获失败继续，严格只运行一次headers。'
    if deviation not in s['deviations']:s['deviations'].append(deviation)
    s['finished']=__import__('datetime').datetime.now().astimezone().isoformat()
    campaign.PATHS.append('example/tool/cp3_r4_audit.py')
    campaign.commit(s,'audited timing comparison and conclusion')
    print(json.dumps(dict(conclusion=s['conclusion'],extract={k:v for k,v in e.items() if k!='elapsedMs'},poolPhases=p['phases'],restoration=s.get('restoration'),commits=s['commits']),ensure_ascii=False,indent=2))
if __name__=='__main__':main()
