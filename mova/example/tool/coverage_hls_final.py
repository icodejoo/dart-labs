"""Measure HLS native resume positions with a fresh process for each mode."""
import json,subprocess,sys
from pathlib import Path
from coverage_record import journal,update
h=Path(__file__).resolve().parent
for mode,args in [('normal',[]),('swap',['--arg','swap=true']),('paused',['--arg','paused=true'])]:
    name='batch21-hls-'+mode
    subprocess.run([sys.executable,str(h/'coverage_suite_device.py'),'api','--name',name+'-launch','--timeout','60'],cwd=h.parents[1],check=True)
    subprocess.run([sys.executable,str(h/'coverage_device.py'),'new','--arg','case=hls','--name',name,'--timeout','180',*args],cwd=h.parents[1],check=True)
    rows=[r for r in journal(name) if r['kind']!='EVENT']
    update(name+' 原生位置复核',[],['- 每模式重启独立进程；HTTP源无流量节流。','```json',json.dumps(rows,ensure_ascii=False,indent=2),'```'])
