"""Reuse CP0 rerun6 batches, applying the exact CP1 precise comparison."""
import json
from pathlib import Path

COUNTS={'normal':60,'paused':60,'cutover':160}

def judge(mode, data):
    samples=data.get('results',[])
    n=COUNTS[mode]
    failures=sum(not r.get('cp0Pass') for r in samples)
    below=sum(r.get('cp0DeltaMs') is not None and abs(r['cp0DeltaMs'])<200 and r.get('cp0PathCorrect') for r in samples)
    pct=100*below/len(samples) if samples else None
    basepct=99.375 if mode=='cutover' else 100
    fromstart=sum(r.get('landed',-1)>=0 and r.get('landed',-1)<1000 and r.get('target',0)>5000 for r in samples)
    wrong=sum(not r.get('cp0PathCorrect') and not r.get('harnessInvalid') for r in samples)
    continued=sum(not r.get('continuedOk',False) and not r.get('harnessInvalid') for r in samples)
    landing=sum(not r.get('cp0Pass') and not r.get('harnessInvalid') for r in samples)
    fail=failures>1 or pct is not None and pct<basepct-5 or fromstart or wrong or continued or landing
    complete=len(samples)==n and len({r.get('run') for r in samples})==n and data.get('completed') and not data.get('harness') and not data.get('errors')
    return dict(status='FAIL' if fail else 'PASS' if complete else 'BLOCKED',
        planned=n,executed=len(samples),failures=failures,below200=below,below200Percent=pct,
        baselineBelow200Percent=basepct,deltaPercentagePoints=None if pct is None else pct-basepct,
        fromStart=fromstart,newWrongPath=wrong,newContinuedFailure=continued,newNonTransportLandingFailure=landing)

def run(args):
    import cp0_android_extra as source
    source.prepare()
    mode=args.scene.removeprefix('precise-')
    data=source.run_one(args.run_id,args.scene,COUNTS[mode])
    numbers=judge(mode,data)
    ident='CP3.'+args.scene+'.summary'
    check=dict(kind='CHECK',id=ident,status=numbers['status'],numbers=numbers)
    result=dict(run_id=args.run_id,group=args.scene,completed=data.get('completed',False),
        harness=data.get('harness',[])+data.get('errors',[]),records=[check],
        verdicts=[dict(case=ident,status=numbers['status'],numbers=numbers)],
        missing=[] if numbers['executed']==COUNTS[mode] else ['incomplete precise samples'],sourceEvidence=data.get('evidence'))
    from coverage_cp3 import TOOL
    out=TOOL/'coverage_evidence'/('matrix-'+args.run_id)
    out.mkdir(exist_ok=True)
    target=out/('matrix-'+args.run_id+'-cp3-'+args.scene+'.json')
    target.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False))
    return 0 if numbers['status']=='PASS' else 1
