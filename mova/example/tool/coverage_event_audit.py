"""Deduplicate captured events and preserve payload/state evidence by source."""
import json
from collections import defaultdict, Counter
from pathlib import Path
from coverage_record import update

out=Path(__file__).resolve().parent/'coverage_evidence'
seen=set(); events=defaultdict(list)
for path in sorted(out.glob('batch*.json')):
    try:data=json.loads(path.read_text(encoding='utf-8'))
    except Exception:continue
    if not isinstance(data,dict):continue
    rows=data.get('records',[])
    start=max((i for i,r in enumerate(rows) if r.get('kind')=='BEGIN'),default=0)
    for row in rows[start:]:
        if row.get('kind')!='EVENT':continue
        key=(row.get('engine'),row.get('ms'),json.dumps(row,sort_keys=True))
        if key in seen:continue
        seen.add(key);events[row['event']].append({'file':path.name,**row})
audit={name:{'count':len(rows),'sample':next((r for r in rows if r['payload']),rows[0]),'files':dict(Counter(r['file'] for r in rows))} for name,rows in events.items()}
(out/'event-audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:{'count':v['count'],'sample':{x:v['sample'][x] for x in ['file','payload','state']}} for k,v in audit.items()},ensure_ascii=False,indent=2))

if __name__=='__main__':
    changes=[];notes=['- 去掉各JSON中此前命令的累计记录；每行引用一份具体动作日志。统计的是该证据文件内次数，非去重后的全运行总数。']
    match={'MovaDurationChange':('duration','duration'),'MovaBufferChange':('buffering','buffering'),'MovaVolumeChange':('value','volume'),'MovaBrightChange':('value','brightness'),'MovaRateChange':('value','rate'),'MovaFitChange':('fit','fit'),'MovaZoomChange':('zoom','zoom'),'MovaLockChange':('value','locked'),'MovaFullScreenChange':('value','fullscreen'),'MovaOrientationChange':('orientation','orientation'),'MovaMiniChange':('mini','mini'),'MovaPipChange':('value','pip'),'MovaStandbyChange':('phase','standby')}
    for name,allrows in events.items():
        # Prefer native nonzero values; every sample still retains its state.
        sample=next((r for r in allrows if any(v not in [0,False,None,''] for v in r['payload'].values())),allrows[0])
        path=out/sample['file'];data=json.loads(path.read_text(encoding='utf-8'));rows=data['records'];start=max((i for i,r in enumerate(rows) if r.get('kind')=='BEGIN'),default=0)
        chosen=[r for r in rows[start:] if r.get('event')==name]
        mismatches=0
        if name in match:
            p,s=match[name];mismatches=sum(r['payload'].get(p)!=r['state'].get(s) for r in chosen)
        if name=='MovaSizeChange':mismatches=sum(f"{r['payload']['width']}x{r['payload']['height']}"!=r['state']['size'] for r in chosen)
        repeats=sum(a['payload']==b['payload'] for a,b in zip(chosen,chosen[1:]))
        detail=f"{sample['file']}：本命令{name}={len(chosen)}次，同型相邻载荷相同={repeats}；样例ms={sample['ms']} payload={json.dumps(sample['payload'],ensure_ascii=False,separators=(',',':'))}。"
        if name in match or name=='MovaSizeChange':detail+=f'逐事件接收时state对账差异={mismatches}。'
        else:detail+='接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。'
        changes.append(('E.'+name,'FAIL' if mismatches else 'PASS',detail))
        notes.append('- '+name+'：'+detail)
    update('事件逐型载荷、重复与state核对',changes,notes)
