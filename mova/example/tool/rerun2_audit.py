"""Audit every switch using raw native events and save comparison evidence."""
import json,hashlib
from pathlib import Path
H=Path(__file__).resolve().parent;O=H/'coverage_evidence';D=H.parents[1]/'doc/plans/2026-10-27-device-coverage-android-retest.md'
summary={};failures=[];allrows=[]
for mode,expected in [('cutover',100),('normal',30),('paused',30),('cutover-extra',20)]:
    file=O/f'rerun2-hls-{mode}.json';data=json.loads(file.read_text(encoding='utf-8'));rows=data['records'];begin=max(i for i,r in enumerate(rows) if r.get('kind')=='BEGIN');rows=rows[begin:]
    switches=[(i,r) for i,r in enumerate(rows) if r.get('kind')=='HLS_SWITCH'];results=[r for r in rows if r.get('kind')=='HLS_RESULT']
    assert len(switches)==len(results)==expected,(mode,len(results))
    audited=[]
    for j,((idx,s),r) in enumerate(zip(switches,results)):
        stop=rows.index(r)+1
        timeline=rows[idx:stop];restart=[v['position'] for v in timeline if v.get('kind')=='HLS_RESTART'];seeks=[v for v in timeline if v.get('kind')=='KERNEL_SEEK_CALL']
        assert s['run']==r['run']==j and s['target']==r['target']
        assert restart==r['restarts'],(mode,j,restart,r['restarts'])
        landed=next((p for p in restart if abs(p-r['target'])<=500),-1)
        continued=(abs(r['continued']-r['target'])<=500 and r['pause']=='yes') if mode=='paused' else r['continued']>=landed+250 and r['pause']=='no'
        expectedPath='/high/index.m3u8' if j%2==0 else '/low/index.m3u8'
        pathOk=r['path'].endswith(expectedPath)
        passed=landed>=0 and continued
        assert not r['pass'] or pathOk,(mode,j,'wrong native path')
        assert r['pass']==passed and r['landed']==landed
        assert s['quality']==('360p' if j%2==0 else '180p'),s['quality']
        entry={'mode':mode,'validTarget':r['target']>=8000,**r,'quality':s['quality'],'seekCalls':seeks,'nativeRestarts':restart};audited.append(entry);allrows.append(entry)
        if not passed:
            failure={'mode':mode,'run':j,'result':r,'timeline':timeline,'fullSession':str(file.relative_to(H.parents[1]))}
            failures.append(failure)
            (O/f'rerun2-failure-{mode}-{j}.json').write_text(json.dumps(failure,ensure_ascii=False,indent=2),encoding='utf-8')
    summary[mode]={'total':len(results),'passed':sum(v['pass'] for v in results),'failed':sum(not v['pass'] for v in results),'validTotal':sum(r['target']>=8000 for r in results),'validPassed':sum(r['target']>=8000 and r['pass'] for r in results),'validFailed':sum(r['target']>=8000 and not r['pass'] for r in results),'invalidTargets':[r['run'] for r in results if r['target']<8000],'minValidTarget':min(r['target'] for r in results if r['target']>=8000),'seekCalls':sum(len(x['seekCalls']) for x in audited),'errors':[r for r in rows if r.get('kind') in ['UNCAUGHT','SCRIPT_ERROR']]}
assert summary['cutover']['validTotal']+summary['cutover-extra']['validTotal']>=100
assert all(not v['errors'] for v in summary.values())
(O/'rerun2-hls-audit.json').write_text(json.dumps(allrows,ensure_ascii=False,indent=2),encoding='utf-8')
(O/'rerun2-hls-failures.json').write_text(json.dumps(failures,ensure_ascii=False,indent=2),encoding='utf-8')
(O/'rerun2-hls-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(summary,ensure_ascii=False,indent=2))
with D.open('a',encoding='utf-8') as f:f.write('\n- HLS独立审计检查点：逐次复算target、交替档位、完整RESTART序列、落点与原生continued判据均一致；统计 rerun2-hls-summary.json，逐次表 rerun2-hls-audit.json，失败完整时间线 rerun2-hls-failures.json。\n')
