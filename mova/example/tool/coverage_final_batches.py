"""Complete follow-up probes sequentially, checkpointing each real result."""
import json
import subprocess
import sys
from pathlib import Path
from coverage_record import update, journal

here=Path(__file__).resolve().parent
jobs=[('qoe-failed',{'case':'qoe','mode':'failed'}),('qoe-stall-release',{'case':'stallRelease'}),('hls-playing',{'case':'hls'}),('hls-playing-cutover',{'case':'hls','cutover':'true'}),('hls-paused',{'case':'hls','paused':'true'}),('tls-probe',{'case':'tlsProbe'})]
for suffix,args in jobs:
    name='batch17-'+suffix
    cmd=[sys.executable,str(here/'coverage_device.py'),'new','--name',name,'--timeout','180']
    for k,v in args.items():cmd+=['--arg',f'{k}={v}']
    print('BEGIN',name,flush=True)
    result=subprocess.run(cmd,cwd=here.parents[1],stdout=(here/'coverage_evidence'/(name+'.driver.log')).open('w'),stderr=subprocess.STDOUT)
    rows=journal(name)
    selected=[r for r in rows if r['kind'] not in ['EVENT','PROGRESS','STATE']]
    update(name+' 复核',[],['- driver exit='+str(result.returncode)+'；证据 `example/tool/coverage_evidence/'+name+'.json`。','```json',json.dumps(selected,ensure_ascii=False,indent=2),'```'])
    print('END',name,result.returncode,flush=True)
