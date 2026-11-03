"""Monitor existing Windows batches without opening more terminal processes."""
import ctypes
import json
from pathlib import Path
import subprocess
import sys
import time

TOOL=Path(__file__).resolve().parent
OUT=TOOL/'coverage_evidence/cp0-windows-formal'

def desktop_ready():
    u=ctypes.WinDLL('user32',use_last_error=True)
    u.OpenInputDesktop.argtypes=[ctypes.c_ulong,ctypes.c_int,ctypes.c_ulong]
    u.OpenInputDesktop.restype=ctypes.c_void_p
    u.CloseDesktop.argtypes=[ctypes.c_void_p]
    u.GetForegroundWindow.restype=ctypes.c_void_p
    h=u.OpenInputDesktop(0,False,1)
    error=ctypes.get_last_error()
    if h:u.CloseDesktop(h)
    foreground=u.GetForegroundWindow()
    row=dict(at=time.time(),accessible=bool(h and foreground),error=error,foreground=foreground)
    with (TOOL/'coverage_evidence/cp0-windows-input-desktop.jsonl').open('a') as f:f.write(json.dumps(row)+'\n')
    return row

def summary():
    results=[]
    for p in OUT.glob('*.result.json'):
        try:results.append(json.loads(p.read_text(encoding='utf-8')))
        except (OSError,ValueError):pass
    progress=[]
    for p in OUT.glob('*.progress.json'):
        try:progress.append((p.stat().st_mtime,p))
        except OSError:pass
    progress.sort(key=lambda x:x[0])
    latest=None
    if progress:
        try:
            d=json.loads(progress[-1][1].read_text(encoding='utf-8'))
            latest=dict(item=d['item'],focusInterruptions=len(d.get('focusInterruptions',[])))
        except (OSError,ValueError):pass
    return dict(resultCount=len(results),crashes=sum(r['crashed'] for r in results),
      completed=sum(r['completed'] for r in results),
      focusAffected=[r['item'] for r in results if r.get('focusMismatchCount') or r.get('focusInterruptions') or (not r.get('focus') and not r.get('crashed'))],
      watchdogs=[r['item'] for r in results if r.get('watchdog')],latest=latest)

def main():
    ctypes.windll.kernel32.SetThreadExecutionState(0x80000003)
    child=None;stream=None
    try:
        deadline=time.monotonic()+600
        while True:
            state=desktop_ready()
            if state['accessible']:break
            print('WINDOWS DESKTOP WAIT',json.dumps(state),flush=True)
            if time.monotonic()>=deadline:
                final=dict(summary(),inputDesktopBlocked=True,reason='input desktop inaccessible for 10 minutes; remaining foreground samples BLOCKED')
                (TOOL/'coverage_evidence/cp0-windows-final-monitor.json').write_text(json.dumps(final,indent=2))
                print('WINDOWS FINAL',json.dumps(final),flush=True);return
            time.sleep(30)
        while not (OUT/'results.json').exists():
            print('WINDOWS MONITOR',json.dumps(summary()),flush=True);time.sleep(30)
        print('WINDOWS FOCUS RETRY START',json.dumps(summary()),flush=True)
        stream=(TOOL/'coverage_evidence/cp0-stage4-focus-retry-console.log').open('wb')
        child=subprocess.Popen([sys.executable,'-B',str(TOOL/'cp0_windows.py')],cwd=TOOL.parents[1],
          stdout=stream,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        while child.poll() is None:
            print('WINDOWS RETRY MONITOR',json.dumps(summary()),flush=True);time.sleep(30)
        print('WINDOWS FINAL',json.dumps(summary()),'exit',child.returncode,flush=True)
        (TOOL/'coverage_evidence/cp0-windows-final-monitor.json').write_text(json.dumps(summary(),indent=2))
    finally:
        ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
        if stream:stream.close()

if __name__=='__main__':main()
