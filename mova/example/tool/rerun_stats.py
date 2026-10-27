"""Summarize measured timing samples without treating timeout sentinels as positions."""
from pathlib import Path
import json,re,statistics
H=Path(__file__).resolve().parent
O=H/'coverage_evidence'
def rows(p):
    d=json.loads(p.read_text(encoding='utf-8'))
    if not isinstance(d,dict) or 'records' not in d:return []
    rs=d['records'];s=max((i for i,r in enumerate(rs) if r.get('kind')=='BEGIN'),default=0)
    return rs[s:]
summary={'hls':[],'hang':{},'adResume':[],'he':{},'keepAlive':{}}
for p in sorted(O.glob('rerun-*.json')):
    try:rs=rows(p)
    except Exception:continue
    cs=[r for r in rs if r.get('kind')=='CHECK' and r.get('id')=='F3.switch']
    if cs:
        ns=[r for r in rs if r.get('kind')=='HLS_NATIVE']
        diffs=[r['landed']-r['target'] for r in ns if r['landed']>=0]
        summary['hls'].append({'file':p.name,'passed':sum(r['pass'] for r in cs),'total':len(cs),'meanSignedErrorMs':statistics.mean(diffs) if diffs else None,'failures':[r['detail'] for r in cs if not r['pass']]})
    if re.match(r'rerun-batch15-hang-(default|2s)-\d.json',p.name):
        timing=[r['since'] for r in rs if 'since' in r and r.get('mode','').startswith('hang')]
        summary['hang'][p.name]=timing
    for r in rs:
        if r.get('kind')=='CHECK' and r.get('id')=='F4.adResume':summary['adResume'].append({'file':p.name,'detail':r['detail'],'pass':r['pass']})
for p in O.glob('rerun-he*.log'):
    t=p.read_text(encoding='utf-8',errors='replace')
    diffs=[int(x) for x in re.findall(r'V6 kind=.*?diff=(\d+)ms',t)]
    offsets=[int(x) for x in re.findall(r'VERDICT V6 (?:PASS|FAIL) offset=(-?\d+)ms',t)]
    summary['he'][p.name]={'resumeDiffsMs':diffs,'meanResumeDiffMs':statistics.mean(diffs) if diffs else None,'offsetsMs':offsets,'meanOffsetMs':statistics.mean(offsets) if offsets else None,'verdicts':re.findall(r'VERDICT (V\w+) (PASS|FAIL)',t)}
for p in O.glob('rerun-*keepAlive*.log'):
    t=p.read_text(encoding='utf-8',errors='replace')
    summary['keepAlive'][p.name]={'verdicts':re.findall(r'VERDICT (S\w+) (PASS|FAIL)',t)}
(O/'rerun-measured-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print('HLS',sum(x['passed'] for x in summary['hls']), '/',sum(x['total'] for x in summary['hls']))
print('HE',summary['he'])
print('HANG',summary['hang'])
