"""Align actual top samples to explicit phase markers, excluding boundaries."""
from pathlib import Path
import re,json,datetime,statistics,collections
O=Path(__file__).resolve().parent/'coverage_evidence'
log=O/'rerun-batch9-keepAlive-cpu-drift.log'
text=log.read_text(encoding='utf-8',errors='replace')
zone=datetime.timezone(datetime.timedelta(hours=8))
windows={}
for line in text.splitlines():
    m=re.search(r'^10-27 (\d\d:\d\d:\d\d\.\d+).*PHASE (S4\.(\w+)\.run\d+) (begin|end)',line)
    if not m:continue
    at=datetime.datetime.fromisoformat('2026-10-27T'+m[1]).replace(tzinfo=zone).timestamp()
    windows.setdefault(m[2],{'mode':m[3]})[m[4]]=at
samples=[]
for block in re.split(r'(?m)^SAMPLE ',(O/'rerun-batch9-keepAlive-cpu-drift.samples.txt').read_text(encoding='utf-8',errors='replace'))[1:]:
    at=float(block.splitlines()[0])
    for line in block.splitlines():
        if line.strip().endswith('com.icodejoo.mova.mova_example.coverage') and re.match(r'\s*\d+\s',line):
            try:cpu=float(line.split()[-4])
            except (ValueError,IndexError):continue
            samples.append({'at':at,'cpu':cpu,'raw':line})
            break
groups=collections.defaultdict(list)
for name,w in windows.items():
    if 'begin' not in w or 'end' not in w:continue
    selected=[s for s in samples if w['begin']+2<=s['at']<=w['end']-2]
    w['samples']=selected
    groups[w['mode']].extend(s['cpu'] for s in selected)
summary={'phaseBoundaryExclusionSeconds':2,'units':'top single-core CPU percent; USB powered, not battery energy','windows':windows,'groups':{k:{'samples':v,'count':len(v),'mean':statistics.mean(v) if v else None} for k,v in groups.items()}}
(O/'rerun-cpu-review.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print(summary['groups'])
