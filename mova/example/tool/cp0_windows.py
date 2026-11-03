"""Sequential Windows release batches; owns its processes and keeps focus evidence."""
import ctypes
from ctypes import wintypes
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

TOOL=Path(__file__).resolve().parent
OUT=TOOL/'coverage_evidence/cp0-windows-formal'
EXE=TOOL.parents[1]/'example/build/windows/x64/runner/Release/mova_example.exe'
user32=ctypes.windll.user32
user32.GetForegroundWindow.restype=wintypes.HWND
user32.GetWindowThreadProcessId.argtypes=[wintypes.HWND,ctypes.POINTER(wintypes.DWORD)]

def foreground():
    p=wintypes.DWORD();user32.GetWindowThreadProcessId(user32.GetForegroundWindow(),ctypes.byref(p));return p.value

def focus(pid):
    msg=wintypes.MSG()
    user32.PeekMessageW(ctypes.byref(msg),None,0,0,0)
    callback=ctypes.WINFUNCTYPE(wintypes.BOOL,wintypes.HWND,wintypes.LPARAM)
    def visit(hwnd,param):
        p=wintypes.DWORD();user32.GetWindowThreadProcessId(hwnd,ctypes.byref(p))
        cls=ctypes.create_unicode_buffer(128)
        user32.GetClassNameW(hwnd,cls,128)
        if p.value==pid and cls.value=='FLUTTER_RUNNER_WIN32_WINDOW':
            thread=user32.GetWindowThreadProcessId(user32.GetForegroundWindow(),None)
            own=ctypes.windll.kernel32.GetCurrentThreadId()
            attached=bool(user32.AttachThreadInput(own,thread,True)) if own!=thread else False
            try:
                user32.ShowWindow(hwnd,9);user32.BringWindowToTop(hwnd);user32.SetForegroundWindow(hwnd)
            finally:
                if attached:user32.AttachThreadInput(own,thread,False)
        return True
    user32.EnumWindows(callback(visit),0)

def request(path='/'):
    with urllib.request.build_opener(urllib.request.ProxyHandler({})).open('http://127.0.0.1:18093'+path,timeout=5) as r:return json.load(r)

def crash_evidence(stem):
    cmd="Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddHours(-2); Id=1000,1001} -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'mova_example' } | Format-List TimeCreated,Id,Message"
    r=subprocess.run(['powershell','-NoProfile','-Command',cmd],capture_output=True,timeout=30,creationflags=subprocess.CREATE_NO_WINDOW)
    (OUT/(stem+'.windows-errors.txt')).write_bytes(r.stdout+r.stderr)

def main():
    OUT.mkdir(exist_ok=True)
    binaries={str(p.relative_to(EXE.parent)):hashlib.sha256(p.read_bytes()).hexdigest()
              for p in EXE.parent.rglob('*') if p.is_file() and (p.suffix in ('.exe','.dll','.so'))}
    (OUT/'build.json').write_text(json.dumps(dict(binaries=binaries,entry='lib/main_win_retest.dart',mode='release'),indent=2),encoding='utf-8')
    for port in (18093,18094,18080):
        with socket.socket() as s:s.bind(('127.0.0.1',port))
    from coverage_gap_media import Handler
    from cp0_android_extra import FIX
    sources=TOOL/'verify_sources/cp0-windows';sources.mkdir(exist_ok=True)
    shutil.copy2(FIX/'long.mp4',sources/'vod.mp4')
    shutil.copytree(FIX,sources/'hls',dirs_exist_ok=True)
    server=http.server.ThreadingHTTPServer(('127.0.0.1',18094),functools.partial(Handler,directory=str(sources)))
    threading.Thread(target=server.serve_forever,daemon=True).start()
    source_log=(OUT/'live-source-console.log').open('wb')
    source=subprocess.Popen([sys.executable,'-B',str(TOOL/'verify_sources/live_server.py'),'18080',str(OUT/'live-source.requests.log'),str(sources/'stall.mp4')],stdout=source_log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
    (OUT/'processes.json').write_text(json.dumps(dict(sourcePid=source.pid,exe=str(EXE)),indent=2))
    results=[];app=None
    def run(stem,case=None,mode=None,count=None,he=None):
        nonlocal app
        print('START WINDOWS',stem,'retain event/native/focus evidence',flush=True)
        env=dict(os.environ,MOVA_WIN_PAGE='he' if he else '',MOVA_ONLY=he or '',MOVA_RUNS='1',MOVA_LOG=str(OUT/(stem+'.he.log')))
        console=(OUT/(stem+'.console.log')).open('wb')
        app=subprocess.Popen([str(EXE)],cwd=EXE.parent,env=env,stdout=console,stderr=subprocess.STDOUT)
        result=dict(item=stem,pid=app.pid,completed=False,crashed=False,focus=[],exeSha256=hashlib.sha256(EXE.read_bytes()).hexdigest())
        try:
            ready=False;started=False;deadline=time.monotonic()+(240 if he else 600);last_focus=0;data={};terminal_at=None
            while time.monotonic()<deadline:
                if app.poll() is not None:
                    result['exitCode']=app.returncode
                    result['crashed']=app.returncode!=0
                    if he:
                        log=OUT/(stem+'.he.log')
                        text=log.read_text(encoding='utf-8',errors='replace') if log.exists() else ''
                        result['completed']='=== SUMMARY' in text and ('VERDICT '+he+' ') in text
                    if result['crashed']:crash_evidence(stem)
                    break
                if not ready:
                    focus(app.pid)
                    if he:ready=foreground()==app.pid
                    else:
                        try:ready=request()['pid']==app.pid and foreground()==app.pid
                        except OSError:pass
                if ready and not started and not he:
                    args=dict(case=case)
                    if mode:args['mode']=mode
                    if count:args['count']=count
                    request('/run?'+urllib.parse.urlencode(args));started=True
                if ready and foreground()!=app.pid:
                    result.setdefault('focusInterruptions',[]).append(dict(atMonotonicNs=time.monotonic_ns(),foregroundPid=foreground()))
                    focus(app.pid)
                if ready and time.monotonic()-last_focus>=1:
                    result['focus'].append(dict(atMonotonicNs=time.monotonic_ns(),foregroundPid=foreground(),expectedPid=app.pid));last_focus=time.monotonic()
                    (OUT/(stem+'.progress.json')).write_text(json.dumps(result),encoding='utf-8')
                if started:
                    try:
                        data=request();(OUT/(stem+'.json')).write_text(json.dumps(data,ensure_ascii=False),encoding='utf-8')
                        if data['status']!='running':result['completed']=data['status']=='done';break
                        enough=sum(r['kind']=='HLS_RESULT' for r in data['rows']) >= count if case=='hls' else sum(r['kind']=='DISPOSE_RETURN' for r in data['rows'])>=4
                        if enough and terminal_at is None:terminal_at=time.monotonic()
                    except OSError:pass
                if he:
                    lp=OUT/(stem+'.he.log')
                    if lp.exists() and 'VERDICT '+he+' ' in lp.read_text(encoding='utf-8',errors='replace') and terminal_at is None:terminal_at=time.monotonic()
                if terminal_at is not None and time.monotonic()-terminal_at>=30:
                    result['watchdog']=True;result['reason']='measurement verdicts/results exist but teardown has no END/process exit after 30 seconds';break
                time.sleep(.25)
            if app.poll() is None:
                capture=subprocess.run(['powershell','-NoProfile','-File',str(TOOL/'win_capture.ps1'),'-TargetPid',str(app.pid),'-OutputPath',str(OUT/(stem+'.png'))],capture_output=True,timeout=30,creationflags=subprocess.CREATE_NO_WINDOW)
                (OUT/(stem+'.window.json')).write_bytes(capture.stdout+capture.stderr)
            result['focusMismatchCount']=sum(r['foregroundPid']!=app.pid for r in result['focus'])
            result['focusAcquired']=ready
            result['focusSampleCount']=len(result['focus'])
            if not result['completed'] and not result['crashed']:
                result.setdefault('reason','watchdog or script error; inspect journal/HE log')
        except Exception as e:
            result['error']=repr(e)
        finally:
            if app.poll() is None:app.terminate();app.wait(timeout=20)
            console.close();app=None
            (OUT/(stem+'.result.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
            print('WINDOWS RESULT',stem,'completed',result['completed'],'crashed',result['crashed'],'focusMismatch',result.get('focusMismatchCount'),flush=True)
        return result
    def check_run(stem,**args):
        final=OUT/(stem+'.result.json')
        selected=None
        for attempt in range(1,6):
            if final.exists():
                selected=json.loads(final.read_text(encoding='utf-8'))
                affected=bool(selected.get('focusMismatchCount') or selected.get('focusInterruptions') or (not selected.get('focus') and not selected.get('crashed')))
                if not affected:break
                archive=OUT/'focus-retries'/(stem+'-'+str(time.monotonic_ns()))
                archive.mkdir(parents=True)
                for old in OUT.glob(stem+'.*'):
                    if old.is_file():shutil.move(str(old),str(archive/old.name))
                print('RETRY FOCUS',stem,'attempt',attempt,'prior evidence',archive,flush=True)
            selected=run(stem,**args)
            if not selected.get('focusMismatchCount') and not selected.get('focusInterruptions') and (selected.get('focus') or selected.get('crashed')):break
        results.append(selected)
    try:
        for mode in ('normal','paused','cutover'):check_run('F3-'+mode,case='hls',mode=mode,count=10)
        for i in range(20):check_run('dispose-'+str(i),case='dispose')
        for he,n in [('V6',5),('V10',20)]:
            for i in range(n):check_run(he+'-'+str(i),he=he)
    finally:
        if app is not None and app.poll() is None:app.terminate();app.wait(timeout=20)
        source.terminate();source.wait(timeout=20);source_log.close()
        server.shutdown();server.server_close()
        (OUT/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')

if __name__=='__main__':main()
