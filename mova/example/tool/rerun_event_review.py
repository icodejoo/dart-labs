"""Audit all current-command events; retain mismatch examples, not just a passing sample."""
from pathlib import Path
import json,collections
H=Path(__file__).resolve().parent
O=H/'coverage_evidence'
seen={};events=collections.defaultdict(list)
for p in sorted(O.glob('rerun-*.json')):
    try:d=json.loads(p.read_text(encoding='utf-8'))
    except Exception:continue
    if not isinstance(d,dict) or 'records' not in d:continue
    # All records in these newly launched processes belong to this rerun.
    # Deduplicate cumulative snapshots, retaining events between commands too.
    # 本次进程全量记录去重，保留命令结束到下次命令开始之间的异步事件。
    rs=d['records'];last_begin=max((r['ms'] for r in rs if r.get('kind')=='BEGIN'),default=-1)
    origin={}
    for r in rs:
        if r.get('kind')=='BEGIN':origin={'ms':r['ms'],'group':r.get('group'),'args':r.get('args')}
        if r.get('kind')!='EVENT':continue
        key=json.dumps(r,sort_keys=True)
        direct=origin.get('ms')==last_begin
        if key in seen:
            if direct and not seen[key]['directCommand']:
                seen[key].update(file=p.name,origin=origin,directCommand=True)
            continue
        row={'file':p.name,**r,'origin':origin,'directCommand':direct}
        seen[key]=row;events[r['event']].append(row)
match={'MovaDurationChange':('duration','duration'),'MovaBufferChange':('buffering','buffering'),
 'MovaVolumeChange':('value','volume'),'MovaBrightChange':('value','brightness'),
 'MovaRateChange':('value','rate'),'MovaFitChange':('fit','fit'),'MovaZoomChange':('zoom','zoom'),
 'MovaLockChange':('value','locked'),'MovaFullScreenChange':('value','fullscreen'),
 'MovaOrientationChange':('orientation','orientation'),'MovaMiniChange':('mini','mini'),
 'MovaPipChange':('value','pip'),'MovaKeepAliveChange':('phase','keepAlive'),
 'MovaQualityChange':('quality','quality'),'MovaQualityListChange':('qualities','qualities'),
 'MovaTimeShiftChange':('behind','timeshiftBehind')}
aliases={'MovaCutoverChange':'MovaSwapChange','MovaKeepAliveChange':'MovaStandbyChange','MovaKeepAliveResume':'MovaStandbyResume'}
audit={}
for name,rs in events.items():
    bad=[];compared=0
    for r in rs:
        if name in match:
            a,b=match[name]
            if b not in r['state']:continue
            compared+=1
            if r['payload'].get(a)!=r['state'].get(b):bad.append(r)
        elif name=='MovaSizeChange':
            compared+=1
            if f"{r['payload']['width']}x{r['payload']['height']}"!=r['state'].get('size'):bad.append(r)
    per_engine=collections.defaultdict(list)
    for r in rs:per_engine[r['engine']].append(r)
    repeats=0
    for engine_rows in per_engine.values():
        engine_rows.sort(key=lambda r:r['ms'])
        repeats+=sum(a['payload']==b['payload'] for a,b in zip(engine_rows,engine_rows[1:]))
    sample=next((r for r in rs if r['payload'] and any(r['payload'].values())),rs[0])
    audit['E.'+aliases.get(name,name)]={'runtimeName':name,'count':len(rs),'compared':compared,'mismatches':len(bad),'repeatedAdjacentPayloads':repeats,'sample':sample,'mismatchExamples':bad[:5],'files':dict(collections.Counter(r['file'] for r in rs)),'verdict':'FAIL' if bad else 'PASS'}
(O/'rerun-event-review.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding='utf-8')
print('event types',len(audit))
for k,v in audit.items():print(k,v['verdict'],v['count'],'compared',v['compared'],'mismatches',v['mismatches'])
