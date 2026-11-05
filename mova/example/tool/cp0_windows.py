"""Sequential Windows release batches; owns its processes and keeps focus evidence."""
import win_policy
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
OUT=TOOL/'coverage_evidence/cp0-windows-quiet'
EXE=TOOL.parents[1]/'example/build/windows/x64/runner/Release/mova_example.exe'
def request(path='/'):
    with urllib.request.build_opener(urllib.request.ProxyHandler({})).open('http://127.0.0.1:18093'+path,timeout=5) as r:return json.load(r)

def crash_evidence(stem):
    cmd="Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddHours(-2); Id=1000,1001} -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'mova_example' } | Format-List TimeCreated,Id,Message"
    r=subprocess.run(['powershell','-NoProfile','-Command',cmd],capture_output=True,timeout=30,creationflags=subprocess.CREATE_NO_WINDOW)
    (OUT/(stem+'.windows-errors.txt')).write_bytes(r.stdout+r.stderr)

def main():
    OUT.mkdir(parents=True, exist_ok=False)
    binaries={str(p.relative_to(EXE.parent)):hashlib.sha256(p.read_bytes()).hexdigest()
              for p in EXE.parent.rglob('*') if p.is_file() and (p.suffix in ('.exe','.dll','.so'))}
    (OUT/'build.json').write_text(json.dumps(dict(binaries=binaries,entry='lib/main_win_retest.dart',mode='release'),indent=2),encoding='utf-8')
    for port in (18093,18094,18080):
        with socket.socket() as s:s.bind(('127.0.0.1',port))
    from coverage_gap_media import Handler
    FIX=TOOL/'verify_sources/cp0-extra'
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
        env=dict(os.environ,MOVA_WIN_PAGE='he' if he else '',MOVA_ONLY=he or '',MOVA_RUNS=str(win_policy.clamp_runs(1)),MOVA_LOG=str(OUT/(stem+'.he.log')))
        console=(OUT/(stem+'.console.log')).open('wb')
        app=win_policy.launch(EXE, EXE.parent, env, console)
        result=dict(item=stem,pid=app.pid,completed=False,crashed=False,focus=[],exeSha256=hashlib.sha256(EXE.read_bytes()).hexdigest())
        stop_observing=threading.Event()
        def observe():
            with (OUT/(stem+'.foreground.jsonl')).open('a',encoding='utf-8',buffering=1) as journal:
                while not stop_observing.is_set() and app.poll() is None:
                    violation=app.sample_foreground()
                    row=dict(atMonotonicNs=time.monotonic_ns(),atUtc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),violation=violation)
                    result['focus'].append(row)
                    result['focusSampleCount']=len(result['focus'])
                    result['foregroundViolations']=list(app.foreground_violations)
                    journal.write(json.dumps(row)+'\n')
                    (OUT/(stem+'.progress.json')).write_text(json.dumps(result),encoding='utf-8')
                    if violation:
                        result.update(status='BLOCKED',reason='focus-violation')
                        app.terminate()
                        return
                    stop_observing.wait(1)
        observer=threading.Thread(target=observe,daemon=True)
        observer.start()
        try:
            ready=False;started=False;deadline=time.monotonic()+(240 if he else 600);last_focus=0;data={};terminal_at=None
            while time.monotonic()<deadline:
                if result.get('reason')=='focus-violation':break
                if app.poll() is not None:
                    result['exitCode']=app.poll()
                    result['crashed']=app.poll()!=0
                    if he:
                        log=OUT/(stem+'.he.log')
                        text=log.read_text(encoding='utf-8',errors='replace') if log.exists() else ''
                        result['completed']='=== SUMMARY' in text and ('VERDICT '+he+' ') in text
                    if result['crashed']:crash_evidence(stem)
                    break
                if not ready:
                    if he:ready=(OUT/(stem+'.he.log')).exists()
                    else:
                        try:ready=request()['pid']==app.pid
                        except OSError:pass
                result['ready']=ready
                if ready and not started and not he:
                    args=dict(case=case)
                    if mode:args['mode']=mode
                    if count:args['count']=win_policy.clamp_runs(count)
                    request('/run?'+urllib.parse.urlencode(args));started=True
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
            result['foregroundViolations']=list(app.foreground_violations)
            result['focusSampleCount']=len(result['focus'])
            if not result['completed'] and not result['crashed']:
                result.setdefault('reason','watchdog or script error; inspect journal/HE log')
        except Exception as e:
            result['error']=repr(e)
        finally:
            stop_observing.set()
            observer.join(timeout=21)
            app.terminate()
            if he:
                lp=OUT/(stem+'.he.log')
                text=lp.read_text(encoding='utf-8',errors='replace') if lp.exists() else ''
                result['verdict']='PASS' if 'VERDICT '+he+' PASS' in text else 'FAIL' if 'VERDICT '+he+' FAIL' in text else 'MISSING'
            elif case=='hls':
                measurements=[r for r in data.get('rows',[]) if r['kind']=='HLS_RESULT']
                result['measurements']=measurements
                result['verdict']='PASS' if len(measurements)==count and all(r['pass'] for r in measurements) else 'FAIL'
            else:
                calls=[r for r in data.get('rows',[]) if r['kind']=='DISPOSE_RETURN']
                result['disposeReturns']=calls
                result['verdict']='PASS' if len(calls)==4 and all(r.get('exception') is None for r in calls) else 'FAIL'
            result.setdefault('status','PASS' if result['completed'] and result['verdict']=='PASS' else 'FAIL')
            console.close();app=None
            (OUT/(stem+'.result.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
            print('WINDOWS RESULT',stem,'completed',result['completed'],'crashed',result['crashed'],'foregroundViolations',len(result.get('foregroundViolations',[])),flush=True)
        return result
    consecutive_violations=0
    def check_run(stem,**args):
        nonlocal consecutive_violations
        selected=run(stem,**args)
        results.append(selected)
        (OUT/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
        consecutive_violations=consecutive_violations+1 if selected.get('reason')=='focus-violation' else 0
        if consecutive_violations>=2:
            (OUT/'batch-blocked.json').write_text(json.dumps(dict(reason='two-consecutive-focus-violations',completedRounds=len(results))),encoding='utf-8')
            raise RuntimeError('two consecutive foreground violations; batch aborted without retry')
    try:
        for mode in ('normal','paused','cutover'):
            for i in range(win_policy.clamp_runs(10)):
                check_run('F3-'+mode+'-'+str(i),case='hls',mode=mode,count=1)
        for i in range(win_policy.clamp_runs(20)):check_run('dispose-'+str(i),case='dispose')
        for he,n in [('V6',5),('V10',20)]:
            for i in range(win_policy.clamp_runs(n)):check_run(he+'-'+str(i),he=he)
    finally:
        if app is not None and app.poll() is None:app.terminate()
        source.terminate();source.wait(timeout=20);source_log.close()
        server.shutdown();server.server_close()
        (OUT/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')

if __name__=='__main__':main()
