"""Independent weak-network audit, original timestamps and per-run event evidence."""
from pathlib import Path
import json
H=Path(__file__).resolve().parent;O=H/'coverage_evidence'
allrows=[];sessionErrors={}
for mode in ['automatic','manual']:
 p=O/f'rerun6-weak-{mode}.json';data=json.loads(p.read_text(encoding='utf-8'));rows=data['records'];rows=rows[max(i for i,r in enumerate(rows) if r.get('kind')=='BEGIN'):]
 sessionErrors[mode]=[r for r in rows if r.get('kind') in ['UNCAUGHT','SCRIPT_ERROR']]
 starts=[(i,r) for i,r in enumerate(rows) if r.get('kind')=='WEAK_START']
 results=[(i,r) for i,r in enumerate(rows) if r.get('kind')=='WEAK_RESULT']
 assert len(results)>=10 and len(starts)==len(results),(mode,len(results),len(starts))
 for (idx,start),(end,result) in zip(starts,results):
  assert start['run']==result['run'] and start['threshold']==3 and not start['customPolicy']
  timeline=rows[idx:end+1]
  events=[r for r in timeline if r.get('kind')=='EVENT' and r.get('event') in ['MovaQualityChange','MovaAbrDownShift','MovaBufferChange']]
  shifts=[r for r in events if r['event']=='MovaAbrDownShift']
  manuals=[r for r in timeline if r.get('kind')=='WEAK_MANUAL']
  assert bool(manuals)==(mode=='manual')
  passed=bool(shifts) and result.get('uri')==start['low']
  assert passed==result['pass'] and len(shifts)==result['abrCount']
  if shifts:
   assert shifts[0]['payload']=={'from':'360p','to':'180p'}
   assert any(r['event']=='MovaQualityChange' and r['payload']['quality']=='180p' for r in events)
  previousEnd=next((k for k,v in results if v['run']==start['run']-1),-1)
  engine=shifts[0]['engine'] if shifts else next((e['engine'] for e in events),None)
  initializationEvents=[e for e in rows[previousEnd+1:idx] if e.get('kind')=='EVENT' and e.get('engine')==engine and e.get('event') in ['MovaQualityChange','MovaAbrDownShift','MovaBufferChange']]
  record={'initializationEvents':initializationEvents,'mode':mode,'run':start['run'],'pass':passed,'startMs':start['ms'],'manualMs':manuals[0]['ms'] if manuals else None,'downshiftMs':[r['ms'] for r in shifts],'downshiftDelayMs':shifts[0]['ms']-(manuals[0]['ms'] if manuals else start['ms']) if shifts else None,'bufferRisingMs':[r['ms'] for r in events if r['event']=='MovaBufferChange' and r['payload']['buffering']],'finalQuality':result.get('quality'),'error':result.get('error'),'events':events,'result':result}
  allrows.append(record)
  (O/f'rerun6-weak-timeline-{mode}-{start["run"]}.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
summary={mode:{'total':sum(r['mode']==mode for r in allrows),'passed':sum(r['mode']==mode and r['pass'] for r in allrows),'failed':sum(r['mode']==mode and not r['pass'] for r in allrows),'sessionErrors':sessionErrors[mode]} for mode in ['automatic','manual']}
(O/'rerun6-weak-audit.json').write_text(json.dumps(allrows,ensure_ascii=False,indent=2),encoding='utf-8')
(O/'rerun6-weak-summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
print(json.dumps(summary,indent=2))
