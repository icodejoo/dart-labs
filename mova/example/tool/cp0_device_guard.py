"""CP0 transport guard: reconnect for at most fifteen minutes, retaining checks."""
import json
from pathlib import Path
import subprocess
import time

def wait_online(serial):
    deadline=time.monotonic()+900
    while True:
        try:
            r=subprocess.run(['adb','-s',serial,'get-state'],capture_output=True,timeout=15)
            state=r.stdout.decode(errors='replace').strip()
        except subprocess.TimeoutExpired:
            state='get-state timeout'
        if state=='device':return
        row=dict(at=time.time(),serial=serial,state=state)
        with (Path(__file__).parent/'coverage_evidence/cp0-reconnect.jsonl').open('a') as f:
            f.write(json.dumps(row)+'\n')
        print('CP0 device offline; retry in 30s:',state,flush=True)
        if time.monotonic()>=deadline:raise RuntimeError('CP0_DEVICE_OFFLINE_15_MINUTES')
        time.sleep(min(30,max(0,deadline-time.monotonic())))
