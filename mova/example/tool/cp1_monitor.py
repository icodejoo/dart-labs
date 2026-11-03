"""Read-only local CP1 progress and host diagnostics; no device mutation."""
from pathlib import Path
from datetime import datetime
import json
import sys
import urllib.request
from collections import Counter

print(datetime.now().isoformat(), flush=True)
for name in sys.argv[1:]:
    if name.isdigit():continue
    path=Path(name)
    print(str(path), flush=True)
    if path.is_file():
        raw=path.read_text(encoding='utf-8',errors='replace')
        if path.suffix=='.json':
            obj=json.loads(raw)
            if isinstance(obj,dict):
                print({k:obj.get(k) for k in ('completed','executed','passes','below200Percent','failureFeatures','counts','masterCounts')},flush=True)
                print('harness',str(obj.get('harness',[]))[:1000],'missing',len(obj.get('missing',[])),flush=True)
                for row in obj.get('masterRows',[]):print('MASTER',row['id'],row['status'],row['executed'], '/',row['planned'],flush=True)
                for row in obj.get('rows',[]):print('ROW',row['id'],row['status'],row['executed'],'/',row['planned'],str(row.get('result',''))[:500],flush=True)
                if 'failures' in obj:print('FAILED_SAMPLES',len(obj['failures']),flush=True)
                for i,r in enumerate(obj.get('verdicts',[])):
                    if r.get('status')=='FAIL':print('verdict',i,r.get('case'),str(r)[:2200],flush=True)
                for i,r in enumerate(obj.get('records',[])):
                    if r.get('kind') in ('CHECK','ERROR'):
                        numbers=r.get('numbers',{})
                        values={k:v for k,v in numbers.items() if k not in ('nativeSamples','frames','frameTimings','rounds','samples','fixture','errors','seeked','recovered','failures','bufferEvents','posterSamples','shots')}
                        print(i,r.get('id'),r.get('status'),r.get('error'),str(values)[:1800],flush=True)
                fixtures=[r for r in obj.get('records',[]) if r.get('kind')=='FIXTURE']
                for r in fixtures[:1]+fixtures[-1:]:
                    d=r.get('data',{})
                    print('fixture',r.get('action'),{k:d.get(k) for k in ('segmentEntered','reopenEntered','swapEntered','gateReleased','hangingBody')},'requests',len(d.get('requests',[])),flush=True)
                errors=[(i,r) for i,r in enumerate(obj.get('records',[])) if r.get('kind')=='KERNEL_LOG' and r.get('level')=='error']
                for i,r in errors[-12:]:print('kernel',i,r.get('us'),r.get('prefix'),r.get('text'),flush=True)
            else:print(str(obj)[-1800:],flush=True)
        elif '.round' in path.name and path.suffix=='.log':
            marks=[line for line in raw.splitlines() if any(s in line for s in ('S7 cycle=','VERDICT','AUTORUN DONE','S7 hwdec='))]
            print('\n'.join(marks[-6:]) if marks else raw[-1800:],flush=True)
        else:print(raw[-1800:],flush=True)
    else: print('absent',flush=True)
try:
    port=next((int(s) for s in sys.argv[1:] if s.isdigit()),18083)
    data=json.load(urllib.request.urlopen(f'http://127.0.0.1:{port}/',timeout=3))
    if 'rows' in data and 'records' not in data:data['records']=data['rows']
    print('completed',data.get('completed'),'records',len(data.get('records',[])),flush=True)
    print('phase',data.get('phase',data.get('status')),'verdictCounts',dict(Counter(
        r.get('status',r.get('data',{}).get('status')) for r in data.get('records',[]) if r.get('kind') in ('CHECK','VERDICT'))),flush=True)
    recent=data.get('records',[])[-1:]
    if recent:
        r=recent[0]
        print('last',{k:r.get(k) for k in ('kind','scene','event','action','us')},
            'state',{k:r.get('state',{}).get(k) for k in ('positionMs','playing','buffering','rendered','quality')},flush=True)
    checks=[(i,r) for i,r in enumerate(data.get('records',[])) if r.get('kind') in ('CHECK','ERROR','HLS_RESULT','VERDICT')]
    hls=[r for r in data.get('records',[]) if r.get('kind')=='HLS_RESULT']
    if hls:print('HLS_RESULT count',len(hls),'rawFail',sum(r.get('pass') is False for r in hls),'last',str(hls[-1])[:1000],flush=True)
    for i,r in checks:
        if (i,r) in checks[-4:] or r.get('kind')=='ERROR' or r.get('status',r.get('data',{}).get('status'))=='FAIL':
            print(i,r.get('id',r.get('case')),r.get('kind'),r.get('status',r.get('data',{}).get('status')),r.get('run'),r.get('error'),flush=True)
            if r.get('kind')=='VERDICT' and r.get('data',{}).get('status')=='FAIL':print('failure detail',str(r.get('data'))[:2200],flush=True)
            if r.get('kind')=='CHECK' and str(r.get('id','')).startswith(('CP0.p02.','CP0.pod2.')):
                n=r.get('numbers',{})
                print('native comparison',{k:n.get(k) for k in ('wrongEpisode','stillAd','matchesB','observationLimit','epochDelta')},
                    'after',n.get('after',n.get('second')),flush=True)
except Exception as error:print(repr(error),flush=True)
