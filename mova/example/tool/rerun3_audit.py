"""Audit every switch using raw native events and save comparison evidence."""
import json,hashlib
from pathlib import Path
H=Path(__file__).resolve().parent;O=H/'coverage_evidence';D=H.parents[1]/'doc/plans/2026-10-27-device-coverage-android-retest2.md'
summary={};failures=[];allrows=[];retrySuccesses=[];excluded=[]
cases=[('cutover',160),('normal',60),('paused',60)]
for base in ['cutover','normal','paused']:
    for extra in sorted(O.glob(f'rerun3-hls-{base}-extra*.json')):
        if not extra.name.endswith('-inflight.json'):
            d=json.loads(extra.read_text(encoding='utf-8'));begin=max(i for i,r in enumerate(d['records']) if r['kind']=='BEGIN')
            cases.append((extra.stem.removeprefix('rerun3-hls-'),sum(r['kind']=='HLS_RESULT' for r in d['records'][begin:])))
for mode,expected in cases:
    file=O/f'rerun3-hls-{mode}.json';data=json.loads(file.read_text(encoding='utf-8'));rows=data['records'];begin=max(i for i,r in enumerate(rows) if r.get('kind')=='BEGIN');rows=rows[begin:]
    switches=[(i,r) for i,r in enumerate(rows) if r.get('kind')=='HLS_SWITCH'];results=[r for r in rows if r.get('kind')=='HLS_RESULT']
    assert len(switches)==len(results)==expected,(mode,len(results))
    audited=[]
    for j,((idx,s),r) in enumerate(zip(switches,results)):
        stop=rows.index(r)+1
        timeline=rows[idx:stop];restart=[v['position'] for v in timeline if v.get('kind')=='HLS_RESTART'];seeks=[v for v in timeline if v.get('kind')=='KERNEL_SEEK_CALL']
        assert s['run']==r['run']==j and s['target']==r['target']
        assert restart==r['restarts'],(mode,j,restart,r['restarts'])
        landed=next((p for p in restart if abs(p-r['target'])<=500),-1)
        continued=(abs(r['continued']-r['target'])<=500 and r['pause']=='yes') if mode.startswith('paused') else r['continued']>=landed+250 and r['pause']=='no'
        expectedPath='/high/index.m3u8' if j%2==0 else '/low/index.m3u8'
        pathOk=r['path'].endswith(expectedPath)
        passed=landed>=0 and continued and pathOk
        assert r['landed']==landed,(mode,j,'landed mismatch')
        assert s['quality']==('360p' if j%2==0 else '180p'),s['quality']
        matched=next((v for v in timeline if v.get('kind')=='HLS_RESTART' and abs(v['position']-r['target'])<=500),None)
        retrySuccess=bool(passed and len(seeks)>=2 and seeks[0]['target']==seeks[1]['target'] and seeks[1]['ms']-seeks[0]['ms']>=1500 and matched and timeline.index(matched)>timeline.index(seeks[1]))
        abr=[v for v in timeline if v.get('event',v.get('type'))=='MovaAbrDownShift']
        entry={'seekCount':len(seeks),'retrySuccess':retrySuccess,'abrEvents':abr,'mode':mode,'validTarget':r['target']>=8000,**r,'pagePass':r['pass'],'pass':passed,'quality':s['quality'],'seekCalls':seeks,'nativeRestarts':restart};audited.append(entry);allrows.append(entry)
        if r['target']<8000:
            excluded.append(entry)
            contextStart=rows.index(results[j-1]) if j else idx
            (O/f'rerun3-excluded-{mode}-{j}.json').write_text(json.dumps({'entry':entry,'context':rows[contextStart:stop]},ensure_ascii=False,indent=2),encoding='utf-8')
        if retrySuccess and r['target']>=8000:
            retrySuccesses.append({'mode':mode,'run':j,'timeline':timeline})
            (O/f'rerun3-retry-success-{mode}-{j}.json').write_text(json.dumps(retrySuccesses[-1],ensure_ascii=False,indent=2),encoding='utf-8')
        if not passed and r['target']>=8000:
            failure={'mode':mode,'run':j,'result':{**r,'pagePass':r['pass'],'pass':passed},'timeline':timeline,'abrPresent':bool(abr),'validTarget':r['target']>=8000,'fullSession':str(file.relative_to(H.parents[1]))}
            failures.append(failure)
            (O/f'rerun3-failure-{mode}-{j}.json').write_text(json.dumps(failure,ensure_ascii=False,indent=2),encoding='utf-8')
    summary[mode]={'total':len(results),'passed':sum(v['pass'] for v in audited),'failed':sum(not v['pass'] for v in audited),'validTotal':sum(r['target']>=8000 for r in audited),'validPassed':sum(r['target']>=8000 and r['pass'] for r in audited),'validFailed':sum(r['target']>=8000 and not r['pass'] for r in audited),'invalidTargets':[r['run'] for r in results if r['target']<8000],'minValidTarget':min(r['target'] for r in results if r['target']>=8000),'seekCalls':sum(len(x['seekCalls']) for x in audited),'errors':[r for r in rows if r.get('kind') in ['UNCAUGHT','SCRIPT_ERROR']]}
assert sum(x['validTotal'] for k,x in summary.items() if k.startswith('cutover'))>=150
for mode in summary:
    valid=[x for x in allrows if x['mode']==mode and x['validTarget']]
    summary[mode]['seekDistribution']={str(n):sum(x['seekCount']==n for x in valid) for n in sorted({0,1,2,3}|{x['seekCount'] for x in valid})}
    summary[mode]['retrySuccesses']=[x['run'] for x in valid if x['retrySuccess']]
    summary[mode]['abrRuns']=[x['run'] for x in valid if x['abrEvents']]
assert all(sum(x['validTotal'] for k,x in summary.items() if k.startswith(base))>=60 for base in ['normal','paused'])
(O/'rerun3-hls-excluded.json').write_text(json.dumps(excluded,ensure_ascii=False,indent=2),encoding='utf-8')
(O/'rerun3-hls-retry-successes.json').write_text(json.dumps(retrySuccesses,ensure_ascii=False,indent=2),encoding='utf-8')
assert all(not v['errors'] for v in summary.values())
(O/'rerun3-hls-audit.json').write_text(json.dumps(allrows,ensure_ascii=False,indent=2),encoding='utf-8')
(O/'rerun3-hls-failures.json').write_text(json.dumps(failures,ensure_ascii=False,indent=2),encoding='utf-8')
(O/'rerun3-hls-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(summary,ensure_ascii=False,indent=2))
with D.open('a',encoding='utf-8') as f:f.write('\n- HLS独立审计检查点：逐次复算target、交替档位、完整RESTART序列、落点与原生continued判据均一致；统计 rerun3-hls-summary.json，逐次表 rerun3-hls-audit.json，失败完整时间线 rerun3-hls-failures.json。\n')
