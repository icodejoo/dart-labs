"""Independently audit rerun4, retaining raw timelines and harness exclusions."""
import json
from pathlib import Path
from collections import Counter
H=Path(__file__).resolve().parent;O=H/'coverage_evidence';D=H.parents[1]/'doc/plans/2026-10-27-device-coverage-android-retest3.md'
def save(n,x): (O/n).write_text(json.dumps(x,ensure_ascii=False,indent=2),encoding='utf-8')
summary={};failures=[];allrows=[];retrySuccesses=[];excluded=[]
files=[]
for base in ['cutover','normal','paused']:
 files.append(O/f'rerun4-hls-{base}.json')
 files.extend(sorted(p for p in O.glob(f'rerun4-hls-{base}-extra*.json') if not p.name.endswith('-inflight.json')))
for file in files:
 mode=file.stem.removeprefix('rerun4-hls-')
 data=json.loads(file.read_text(encoding='utf-8'));rows=data['records'];begin=max(i for i,r in enumerate(rows) if r.get('kind')=='BEGIN');rows=rows[begin:]
 switches=[(i,r) for i,r in enumerate(rows) if r.get('kind')=='HLS_SWITCH'];results=[(i,r) for i,r in enumerate(rows) if r.get('kind')=='HLS_RESULT']
 assert len(switches)==len(results),(mode,data['status'])
 audited=[]
 for j,((idx,s),(end,r)) in enumerate(zip(switches,results)):
  timeline=rows[idx:end+1]
  restarts=[v for v in timeline if v.get('kind')=='HLS_RESTART']
  seeks=[v for v in timeline if v.get('kind')=='KERNEL_SEEK_CALL']
  gates=[v for v in timeline if v.get('kind')=='HLS_VARIANT_READY' and v['run']==j]
  assert s['run']==r['run']==j and s['target']==r['target']
  assert [v['position'] for v in restarts]==r['restarts']
  quality=[v for v in timeline if v.get('kind')=='HLS_EVENT' and v.get('type')=='MovaQualityChange' and v.get('qualityUri')==s['uri']]
  early=not gates or not quality or gates[0]['ms']>r['ms'] or quality[0]['ms']>r['ms']
  if gates:
   assert gates[0]['path']==s['uri'] and gates[0]['duration']>0 and quality[0]['ms']<=gates[0]['ms']
  eligible=[v for v in restarts if v.get('eligible') and v['path']==s['uri'] and gates and v['ms']>=gates[0]['ms']]
  assert [v['position'] for v in eligible]==r['observedRestarts']
  matched=next((v for v in eligible if abs(v['position']-r['target'])<=500),None)
  landed=matched['position'] if matched else -1
  continued=(abs(r['continued']-r['target'])<=500 and r['pause']=='yes') if mode.startswith('paused') else r['continued']>=landed+250 and r['pause']=='no'
  passed=not early and landed>=0 and continued and r['path']==s['uri']
  assert r['landed']==landed and r['pass']==passed,(mode,j,r,passed)
  assert s['quality']==('360p' if j%2==0 else '180p')
  valid=r['target']>=8000 and not early and not r['harnessInvalid']
  # A new quality change (including ABR) starts another resume chain.
  chains=[];chain=[]
  for v in timeline:
   if v.get('kind')=='HLS_EVENT' and v.get('type') in ['MovaQualityChange','MovaAbrDownShift']:
    if chain:chains.append(chain);chain=[]
   if v.get('kind')=='KERNEL_SEEK_CALL':chain.append(v)
  if chain:chains.append(chain)
  retryCalls=[v for chain in chains for prev,v in zip(chain,chain[1:]) if v['target']==prev['target'] and v['ms']-prev['ms']>=1500]
  threeAttemptChains=[chain for chain in chains if len(chain)>=3 and len({v['target'] for v in chain})==1 and all(b['ms']-a['ms']>=1500 for a,b in zip(chain,chain[1:]))]
  retrySuccess=bool(passed and retryCalls and matched and timeline.index(matched)>timeline.index(retryCalls[0]))
  abr=[v for v in timeline if v.get('kind')=='HLS_EVENT' and v.get('type')=='MovaAbrDownShift']
  suppressed=[v for v in restarts if not v.get('eligible') and abs(v['position']-r['target'])<=500 and v['path']!=s['uri'] and (not gates or v['ms']<gates[0]['ms'])]
  entry={**r,'mode':mode,'validTarget':r['target']>=8000,'valid':valid,'earlyResult':early,'seekCount':len(seeks),'retrySuccess':retrySuccess,'retryCallCount':len(retryCalls),'threeAttemptChains':threeAttemptChains,'abrEvents':abr,'seekCalls':seeks,'nativeRestarts':r['restarts'],'quality':s['quality'],'suppressedOldPathCandidates':suppressed}
  audited.append(entry);allrows.append(entry)
  record={'mode':mode,'run':j,'result':entry,'timeline':timeline,'abrPresent':bool(abr),'fullSession':str(file.relative_to(H.parents[1]))}
  if not valid:
   reason=[]
   if r['target']<8000:reason.append('target<8000ms：沿用前次失败后复位竞争剔除规则')
   if early or r['harnessInvalid']:reason.append('harness-invalid：结果早于目标档位切换完成或未观测到切换完成')
   entry['exclusionReason']=reason;excluded.append(entry)
   contextStart=results[j-1][0] if j else idx
   save(f'rerun4-excluded-{mode}-{j}.json',dict(record,context=rows[contextStart:end+1]))
  elif not passed:
   failures.append(record);save(f'rerun4-failure-{mode}-{j}.json',record)
  if valid and retrySuccess:
   retrySuccesses.append(record);save(f'rerun4-retry-success-{mode}-{j}.json',record)
 valid=[x for x in audited if x['valid']];failed=[x for x in valid if not x['pass']]
 dist=lambda a:{str(n):sum(x['seekCount']==n for x in a) for n in sorted({0,1,2,3}|{x['seekCount'] for x in a})}
 summary[mode]={'total':len(audited),'validTotal':len(valid),'validPassed':sum(x['pass'] for x in valid),'validFailed':len(failed),'excluded':len(audited)-len(valid),'invalidTargets':[x['run'] for x in audited if not x['validTarget']],'harnessInvalid':[x['run'] for x in audited if x['earlyResult'] or x['harnessInvalid']],'seekDistribution':dist(valid),'failedSeekDistribution':dist(failed),'retrySuccesses':[x['run'] for x in valid if x['retrySuccess']],'abrRuns':[x['run'] for x in valid if x['abrEvents']],'failedAbrRuns':[x['run'] for x in failed if x['abrEvents']],'failedThreeCalls':[x['run'] for x in failed if x['seekCount']>=3],'failedThreeAttempts':[x['run'] for x in failed if x['threeAttemptChains']],'suppressedOldPathRuns':[x['run'] for x in audited if x['suppressedOldPathCandidates']],'errors':[x for x in rows if x.get('kind') in ['UNCAUGHT','SCRIPT_ERROR']]}
 summary[mode]['sessionStatus']=data['status']
for base,minimum in [('cutover',150),('normal',60),('paused',60)]:
 assert sum(v['validTotal'] for k,v in summary.items() if k.startswith(base))>=minimum,(base,summary)
for n,x in [('summary',summary),('audit',allrows),('failures',failures),('excluded',excluded),('retry-successes',retrySuccesses)]:save(f'rerun4-hls-{n}.json',x)
print(json.dumps(summary,ensure_ascii=False,indent=2))
with D.open('a',encoding='utf-8') as f:f.write('\n- 独立审计检查点：逐个复算目标档位门槛、eligible RESTART首个目标落点、原生continued/pause/path，与页面一致；失败、剔除上下文及重发成功完整事件已分别导出，详见rerun4-hls-summary/audit/failures/excluded/retry-successes.json。\n')
