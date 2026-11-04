"""CP0 transport guard: reconnect for at most fifteen minutes, retaining checks."""
import json
from pathlib import Path
import subprocess
import time

_offline_since=None

def wait_online(serial):
    global _offline_since
    while True:
        try:
            r=subprocess.run(['adb','-s',serial,'get-state'],capture_output=True,timeout=15)
            state=(r.stdout+r.stderr).decode(errors='replace').strip()
        except subprocess.TimeoutExpired:
            state='get-state timeout'
        if state=='device':
            _offline_since=None
            return
        if 'unauthorized' in state:
            subprocess.run(['adb','kill-server'],capture_output=True,timeout=30)
        if _offline_since is None:_offline_since=time.monotonic()
        deadline=_offline_since+900
        row=dict(at=time.time(),serial=serial,state=state)
        with (Path(__file__).parent/'coverage_evidence/cp0-reconnect.jsonl').open('a') as f:
            f.write(json.dumps(row)+'\n')
        print('CP0 device offline; retry in 30s:',state,flush=True)
        if time.monotonic()>=deadline:raise RuntimeError('CP0_DEVICE_OFFLINE_15_MINUTES')
        time.sleep(min(30,max(0,deadline-time.monotonic())))
