"""Run the reused fixture services with rerun-specific logs."""
from pathlib import Path
import subprocess,sys,shutil,json,time
H=Path(__file__).resolve().parent
O=H/'coverage_evidence'
W=H/'rerun-sources'
W.mkdir(exist_ok=True)
shutil.copyfile(H/'coverage_sources/stall.mp4',W/'stall.mp4')
jobs=[['verify_sources/start_sources.py','--workdir',str(W)],['coverage_media.py'],['coverage_tls.py']]
kids=[]
for index,args in enumerate(jobs):
    log=(O/f'rerun-service-{index}.log').open('w',encoding='utf-8')
    kids.append(subprocess.Popen([sys.executable,'-u',str(H/args[0]),*args[1:]],stdout=log,stderr=subprocess.STDOUT))
(O/'rerun-services.json').write_text(json.dumps([p.pid for p in kids]),encoding='utf-8')
try:
    while all(p.poll() is None for p in kids):time.sleep(1)
finally:
    for p in kids:p.terminate()
