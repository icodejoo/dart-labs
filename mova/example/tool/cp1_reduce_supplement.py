"""Reduce supplementary page observations without claiming missing B03/B07 coverage."""
from collections import Counter
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[2]
E=ROOT/'example/tool/coverage_evidence'
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def rel(p):return p.relative_to(ROOT).as_posix()


def rows():
    out=[]
    extracts=[(p,read(p)) for p in sorted(E.glob('matrix-cp1-b-extract-*/extract-results.json'))]
    runs=[(p,i,r) for p,rs in extracts for i,r in enumerate(rs)]
    failures=[dict(id='extract.'+str(i),evidence=rel(p),recordArray='root',recordIndex=i,status='FAIL',
        reason='既有A30抽帧/缓存CHECK失败',numbers=r) for p,i,r in runs if r.get('status')=='FAIL']
    out.append(dict(id='B.extract',stage=1,planned=3,executed=len(runs),status='FAIL' if failures else 'BLOCKED',
        criterion='真实抽帧字节/图片、缓存命中及B07原生seek落点，各3次',cp0='无同口径独立定量基线',
        difference='既有页不导出抽帧原生seek落点，A30辅助结果不能关闭B07',
        result=json.dumps([dict(run=i,completed=r.get('completed'),checks=r.get('checks'),thumbs=r.get('thumbs'),error=r.get('error')) for p,i,r in runs],ensure_ascii=False),
        evidence=[rel(p) for p,d in extracts],issues=failures,measurements=[r for p,i,r in runs]))
    datasets=[(p,read(p)) for p in sorted(E.glob('matrix-cp1-b-skin-*/cp0-result.json'))]
    patches=[(p,i,v) for p,d in datasets for i,v in enumerate(d.get('verdicts',[])) if v.get('case','').startswith(('gap:S12.default.patches','gap:S12.bilibili.patches'))]
    counts=Counter(v['status'] for p,i,v in patches)
    failures=[dict(id=v['case'],evidence=rel(p),recordArray='verdicts',recordIndex=i,status='FAIL',
        reason=v.get('reason') or '辅助skin树快照/交互判据失败；B03本体未刺激，保留原始FAIL',numbers=v)
        for p,d in datasets for i,v in enumerate(d.get('verdicts',[])) if v['status']=='FAIL']
    out.append(dict(id='B.bottomPatch',stage=1,planned=3,executed=0,status='FAIL' if failures else 'BLOCKED',
        criterion='底栏每个子节点remove/insertAfter、点击与直播布局，3次',cp0='无同口径独立定量基线',
        difference='CP1页映射声称底栏覆盖，但已构建gap-skin仅有顶栏patch；B03专属刺激缺失',
        result='辅助顶栏patch判据='+str(dict(counts))+'；独立case数='+str(len({(str(p),v['case']) for p,i,v in patches}))+'；辅助skin全部原始FAIL='+str(len(failures)),
        evidence=[rel(p) for p,d in datasets],issues=failures,measurements=[dict(evidence=rel(p),recordIndex=i,verdict=v) for p,i,v in patches]))
    logs=sorted(E.glob('matrix-cp1-keepalive-core-*/matrix-*-keepalive-core.log'))
    for scene in ('S1','S13'):
        samples=[];events=[]
        for p in logs:
            current=None
            for index,line in enumerate(p.read_text(encoding='utf-8',errors='replace').splitlines()):
                start=re.search(r'--- (S\w+) ',line)
                if start:current=start[1]
                match=re.search(r'VERDICT '+scene+r' (PASS|FAIL) (.*)',line)
                if match:samples.append(dict(evidence=rel(p),line=index+1,status=match[1],detail=match[2]))
                if current==scene and 'MATRIX_RECORD ' in line:
                    try:
                        record=json.loads(line.split('MATRIX_RECORD ',1)[1])
                        if record.get('event')=='MovaKeepAliveResume':events.append(record)
                    except ValueError:pass
        counts=Counter(s['status'] for s in samples)
        failures=[dict(id=scene+'.'+str(i),evidence=s['evidence'],recordArray='logLines1Based',recordIndex=s['line'],status='FAIL',reason=s['detail'],numbers=s)
            for i,s in enumerate(samples) if s['status']=='FAIL']
        out.append(dict(id='keepalive-core.'+scene,stage=2,planned=5,executed=len(samples),status='FAIL' if failures else 'BLOCKED',
            criterion='每场景5次原生判据通过，且与CP0同口径一致',cp0='CP0仅有H42约5004ms/grace事实，缺S1/S13逐轮对应台账',
            difference='保留原生判据与elapsed/signal；缺相同场景的CP0台账，不宣称完整比较通过',
            result='原生VERDICT='+str(dict(counts))+'；唤醒='+str([e.get('payload') for e in events]),
            evidence=[rel(p) for p in logs],issues=failures,measurements=samples,wakeEvents=events))
    return out
