"""CP0-compatible comparisons for the current CP1 evidence namespace."""
from collections import Counter
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
E=ROOT/'example/tool/coverage_evidence'


def load(p): return json.loads(p.read_text(encoding='utf-8'))
def rel(p): return p.relative_to(ROOT).as_posix()


def rows():
    output=[]
    def add(ident,planned,executed,status,criterion,baseline,metrics,evidence,issues=None):
        output.append(dict(id=ident,stage=2,planned=planned,executed=executed,status=status,
            criterion=criterion,cp0=baseline,difference=json.dumps(metrics,ensure_ascii=False),
            metrics=metrics,evidence=evidence,issues=issues or []))
    extra=[(p,load(p)) for p in sorted(E.glob('matrix-cp1-android-*/cp0-result.json'))]
    for mode,n,basefail,basepct in [('normal',60,0,100),('paused',60,0,100),('cutover',160,1,99.375)]:
        datasets=[(p,d) for p,d in extra if d['group']=='precise-'+mode]
        samples=[(p,i,r) for p,d in datasets for i,r in enumerate(d.get('results',[]))]
        failures=sum(not r.get('cp0Pass') for p,i,r in samples)
        below=sum(r.get('cp0DeltaMs') is not None and abs(r['cp0DeltaMs'])<200 and r.get('cp0PathCorrect') for p,i,r in samples)
        pct=100*below/len(samples) if samples else None
        fromstart=[(p,i,r) for p,i,r in samples if r.get('landed',-1)>=0 and r.get('landed',-1)<1000 and r.get('target',0)>5000]
        wrong=[(p,i,r) for p,i,r in samples if not r.get('cp0PathCorrect') and not r.get('harnessInvalid')]
        continued=[(p,i,r) for p,i,r in samples if not r.get('continuedOk',False) and not r.get('harnessInvalid')]
        landing=[(p,i,r) for p,i,r in samples if not r.get('cp0Pass') and not r.get('harnessInvalid')]
        fail=bool(failures>max(basefail,1) or pct is not None and pct<basepct-5 or fromstart or wrong or continued or landing)
        complete=len(samples)==n and all(d.get('completed') and not d.get('harness') for p,d in datasets)
        status='FAIL' if fail else 'PASS' if complete else 'BLOCKED'
        metrics=dict(passes=len(samples)-failures,failures=failures,below200=below,below200Percent=pct,
            deltaPercentagePoints=None if pct is None else pct-basepct,fromStart=len(fromstart),newWrongPath=len(wrong),newContinuedFailure=len(continued),newNonTransportLandingFailure=len(landing),
            harness=[d.get('harness') for p,d in datasets],errors=[d.get('errors') for p,d in datasets])
        issues=[dict(evidence=rel(p),recordArray='results',recordIndex=i,id='precise-'+mode+'.'+str(r.get('run')),status='FAIL',
            reason='落点/地址/续播判据不满足，或<200ms占比下降超过5百分点的原始样本',numbers=r) for p,i,r in samples
            if not r.get('cp0Pass') or not r.get('continuedOk',False)
            or pct is not None and pct<basepct-5 and (r.get('cp0DeltaMs') is None or abs(r['cp0DeltaMs'])>=200)]
        add('F3/A17 precise.'+mode,n,len(samples),status,'失败≤max(CP0失败,1)，无新失败特征；<200ms降幅≤5百分点',
            f'{n-basefail}/{n}，<200ms={basepct}%，失败{basefail}',metrics,[rel(p) for p,d in datasets],issues)
    for group,prefix,n,baseline in [('cp0-h28','H28.default.playing',30,'30/30 PASS'),('cp0-h28','H28.default.paused',30,'30/30 PASS'),
        ('cp0-h28','H28.default.cutover',30,'30/30 PASS'),('cp0-parked','H20.hlsSeek',30,'30/30 PASS'),('cp0-parked','H50.hlsSeek',30,'30/30 PASS')]:
        datasets=[(p,d) for p,d in extra if d['group']==group]
        samples=[(p,i,v) for p,d in datasets for i,v in enumerate(d.get('verdicts',[])) if v['case']=='gap:'+prefix or v['case'].startswith('gap:'+prefix+'.')]
        executed=len({v['case'] for p,i,v in samples}) if group=='cp0-parked' else len(samples)
        counts=Counter(v['status'] for p,i,v in samples)
        status='FAIL' if counts['FAIL'] else 'PASS' if executed==n and counts['BLOCKED']==0 and all(not d.get('harness') for p,d in datasets) else 'BLOCKED'
        deltas=[v['actual']['deltaMs'] for p,i,v in samples if isinstance(v.get('actual'),dict) and isinstance(v['actual'].get('deltaMs'),(int,float))]
        metrics=dict(verdictCounts=dict(counts),deltaMs=deltas,harness=[d.get('harness') for p,d in datasets])
        issues=[dict(evidence=rel(p),recordArray='verdicts',recordIndex=i,id=v['case'],status=v['status'],
            reason=v.get('reason') or json.dumps(v.get('actual',v.get('difference')),ensure_ascii=False),numbers=v) for p,i,v in samples if v['status']!='PASS']
        add(prefix,n,executed,status,'失败数≤CP0（0）；缺样本BLOCKED',baseline,metrics,[rel(p) for p,d in datasets],issues)
    for scene,variants in [('p02',['contentWarm','midPending','postLoad']),('pod2',['wait.ad2','nowait.ad2'])]:
        datasets=[(p,load(p)) for p in sorted(E.glob('matrix-cp1-*/matrix-*-cp0-'+scene+'.json'))]
        for variant in variants:
            prefix='CP0.'+scene+'.'+variant+'.'
            samples=[(p,i,r) for p,d in datasets for i,r in enumerate(d.get('records',[])) if r.get('kind')=='CHECK' and r.get('id','').startswith(prefix)]
            def good(r):
                z=r['numbers']
                if scene=='p02':return z.get('matchesB')==1 and z.get('wrongEpisode')==0 and z.get('stillAd')==0 and z.get('observationLimit')==0
                return '/ad2.mp4' in str(z.get('second',{}).get('path')) and z.get('firstFrame2Us',0)>z.get('firstFrame1Us',0) and (variant!='wait.ad2' or z.get('epochDelta',0)>0)
            passed=sum(good(r) for p,i,r in samples)
            status='FAIL' if passed<len(samples) else 'PASS' if len(samples)==10 and all(not d.get('harness') for p,d in datasets) else 'BLOCKED'
            metrics=dict(passes=passed,failures=len(samples)-passed,harness=[d.get('harness') for p,d in datasets])
            for key in ['matchesB','wrongEpisode','stillAd','observationLimit','epochDelta','firstFrameGapUs']:
                metrics[key]=[r['numbers'].get(key) for p,i,r in samples]
            issues=[dict(evidence=rel(p),recordIndex=i,id=r['id'],status='FAIL',reason='原生地址/首帧/等待型epoch判据不满足',numbers=r['numbers']) for p,i,r in samples if not good(r)]
            baseline='CP0 跳过，无等待型基线' if scene=='pod2' else '10/10 停广告尾帧，20秒未进B' if variant=='postLoad' else '10/10 播B'
            criterion='真实ad2地址与第二次首帧；wait型renderEpoch递增' if scene=='pod2' else '播B 10/10，播错集0，仍停广告0，20秒观察窗无超限'
            add(scene+'.'+variant,10,len(samples),status,criterion,baseline,metrics,[rel(p) for p,d in datasets],issues)
    return output
