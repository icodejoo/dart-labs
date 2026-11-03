"""Read-only local CP1 progress and host diagnostics; no device mutation."""
from pathlib import Path
from datetime import datetime
import json
import sys
import urllib.request

print(datetime.now().isoformat(), flush=True)
for name in sys.argv[1:]:
    path=Path(name)
    print(str(path), flush=True)
    if path.is_file():
        raw=path.read_text(encoding='utf-8',errors='replace')
        if path.suffix=='.json':
            obj=json.loads(raw)
            if isinstance(obj,dict):
                print({k:obj.get(k) for k in ('completed','executed','passes','below200Percent','failureFeatures','counts','masterCounts')},flush=True)
                print('harness',str(obj.get('harness',[]))[:1000],'missing',len(obj.get('missing',[])),flush=True)
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
        else:print(raw[-1800:],flush=True)
    else: print('absent',flush=True)
try:
    data=json.load(urllib.request.urlopen('http://127.0.0.1:18083/',timeout=3))
    print('completed',data.get('completed'),'records',len(data.get('records',[])),flush=True)
    recent=data.get('records',[])[-1:]
    if recent:
        r=recent[0]
        print('last',{k:r.get(k) for k in ('kind','scene','event','action','us')},
            'state',{k:r.get('state',{}).get(k) for k in ('positionMs','playing','buffering','rendered','quality')},flush=True)
    for i,r in enumerate(data.get('records',[])):
        if r.get('kind') in ('CHECK','ERROR','HLS_RESULT'):
            print(i,r.get('id'),r.get('kind'),r.get('status'),r.get('run'),r.get('error'),flush=True)
except Exception as error:print(repr(error),flush=True)
