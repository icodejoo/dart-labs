"""Bounded CP1 Windows native sampling, exclusively through win_policy.

Run once per evidence directory. All attempts, including crashes and missing
stimuli, are retained. No input injection or foreground correction is used.
"""
import ctypes
from ctypes import wintypes
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

import win_policy
from win_job import KillOnCloseJob

TOOL = Path(__file__).resolve().parent
ROOT = TOOL.parents[1]
EXE = ROOT/'example/build/windows/x64/runner/Release/mova_example.exe'
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))
U32 = ctypes.WinDLL('user32', use_last_error=True)
U32.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
U32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
U32.GetWindowLongPtrW.argtypes = [wintypes.HWND, ctypes.c_int]
U32.GetWindowLongPtrW.restype = ctypes.c_ssize_t


def windows(pid):
    found = []
    callback = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def visit(hwnd, param):
        owner = wintypes.DWORD()
        U32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid:
            rect = wintypes.RECT()
            U32.GetWindowRect(hwnd, ctypes.byref(rect))
            style = U32.GetWindowLongPtrW(hwnd, -20)
            found.append(dict(hwnd=int(hwnd), width=rect.right-rect.left,
                height=rect.bottom-rect.top, exStyle=style,
                noActivate=bool(style & 0x08000000), toolWindow=bool(style & 0x80)))
        return True
    U32.EnumWindows(callback(visit), 0)
    return found


def request(path='/'):
    with OPENER.open('http://127.0.0.1:18093'+path, timeout=3) as response:
        return json.load(response)


class Watch:
    def __init__(self, app, path):
        self.app, self.path = app, path
        self.stop = threading.Event()
        self.samples, self.violation = [], None
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self):
        start = time.monotonic()
        with self.path.open('w', encoding='utf-8') as stream:
            while not self.stop.is_set():
                elapsed = time.monotonic()-start
                foreground = win_policy.foreground_pid()
                hit = self.app.sample_foreground()
                frames = windows(self.app.pid)
                bad = elapsed > 2 and any(
                    f['width'] > 0 and f['height'] > 0 and
                    (f['width'], f['height'], f['noActivate'], f['toolWindow']) != (640, 360, True, True)
                    for f in frames)
                row = dict(ms=round(elapsed*1000), foregroundPid=foreground,
                    appPid=self.app.pid, foregroundViolation=hit, windows=frames)
                self.samples.append(row)
                stream.write(json.dumps(row)+'\n'); stream.flush()
                if hit or bad:
                    self.violation = 'foreground' if hit else 'window policy'
                    self.app.terminate()
                    break
                self.stop.wait(.1)

    def close(self):
        self.stop.set(); self.thread.join(5)
        return dict(samples=len(self.samples), foregroundViolations=len(self.app.foreground_violations),
            violation=self.violation, windows=[f for r in self.samples for f in r['windows']
                if r['ms'] >= 2000 and (f['width'], f['height']) == (640, 360)][:3],
            evidence=str(self.path))


def require_free(port):
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', port))


def build(tag, entry, out):
    with (out/(tag+'.build-host.log')).open('w') as log:
        done = subprocess.run([sys.executable, '-B', str(TOOL/'win_build.py'), tag, entry],
            cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    if done.returncode:
        raise RuntimeError('Windows build failed '+tag)
    return dict(entry=entry, exeSha256=hashlib.sha256(EXE.read_bytes()).hexdigest(),
        nativeSha256=hashlib.sha256((EXE.parent/'libmpv-2.dll').read_bytes()).hexdigest(),
        buildLog=str(TOOL/'coverage_evidence'/f'win-build-{tag}-complete.log'))


def retest(out, tag, record):
    require_free(18093)
    with (out/'retest.console.log').open('w') as console:
        app = win_policy.launch(EXE, EXE.parent, stdout=console)
        watch = Watch(app, out/'retest.quiet.jsonl')
        record['pid'] = app.pid
        try:
            end = time.monotonic()+45
            while True:
                if app.poll() is not None: raise RuntimeError('startup exit '+str(app.poll()))
                try:
                    data = request()
                    if data['pid'] != app.pid or data['build'] != tag: raise RuntimeError('foreign command host')
                    break
                except OSError:
                    if time.monotonic()>end: raise
                    time.sleep(.2)
            commands = [('F3', dict(case='hls', mode=m, count=1)) for m in ('normal', 'paused', 'cutover')]
            commands += [('dispose', dict(case='dispose')) for _ in range(min(3, win_policy.clamp_runs(3)))]
            for index, (item, args) in enumerate(commands):
                start = len(data['rows'])
                attempt = dict(item=item, attempt=index+1 if item=='F3' else index-2, args=args)
                record['attempts'].append(attempt)
                target = out/f'{item}-{attempt["attempt"]}.json'
                try:
                    data = request('/run?'+urllib.parse.urlencode(args))
                    end = time.monotonic()+150
                    while data['status'] == 'running':
                        target.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
                        if watch.violation: raise RuntimeError(watch.violation)
                        if app.poll() is not None: raise RuntimeError('process exit '+str(app.poll()))
                        if time.monotonic()>end: raise TimeoutError('command timeout')
                        time.sleep(.2); data=request()
                    target.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
                    rows = data['rows'][start:]
                    errors = [r for r in rows if r['kind'] in ('SCRIPT_ERROR', 'UNCAUGHT')]
                    values = [r for r in rows if r['kind'] == ('HLS_RESULT' if item=='F3' else 'DISPOSE_RETURN')]
                    ok = data['status']=='done' and not errors and len(values)==(1 if item=='F3' else 4)
                    ok = ok and all(r.get('pass') is True if item=='F3' else r.get('exception') is None for r in values)
                    attempt.update(status='PASS' if ok else 'FAIL', evidence=str(target),
                        rowIndices=[r['seq'] for r in values+errors], values=values, errors=errors)
                except Exception as error:
                    attempt.update(status='BLOCKED' if app.poll() is None or watch.violation else 'FAIL', error=repr(error), evidence=str(target))
                    if app.poll() is not None: break
        finally:
            record['quiet'] = watch.close()
            record['exitBeforeCleanup'] = app.poll()
            app.terminate()


def he(out, scene, iteration, build_info):
    log = out/f'{scene}-{iteration}.log'
    env = dict(os.environ, MOVA_ONLY=scene, MOVA_RUNS='1', MOVA_LOG=str(log.resolve()))
    row = dict(item='HE '+scene, attempt=iteration, build=build_info, evidence=str(log))
    with (out/f'{scene}-{iteration}.console.log').open('w') as console:
        app=win_policy.launch(EXE, EXE.parent, env=env, stdout=console)
        row['pid']=app.pid
        watch=Watch(app, out/f'{scene}-{iteration}.quiet.jsonl')
        try:
            end=time.monotonic()+150
            while True:
                text=log.read_text(encoding='utf-8', errors='replace') if log.exists() else ''
                if 'AUTORUN DONE' in text: break
                if watch.violation: raise RuntimeError(watch.violation)
                if app.poll() is not None: raise ChildProcessError('native exit '+str(app.poll()))
                if time.monotonic()>end: raise TimeoutError('missing DONE')
                time.sleep(.2)
            matches=re.findall(r'VERDICT '+scene+r' (PASS|FAIL) ([^\r\n]*)', text)
            row.update(status='PASS' if len(matches)==1 and matches[0][0]=='PASS' else 'FAIL', verdicts=matches,
                lineIndices=[i for i,line in enumerate(text.splitlines()) if 'VERDICT '+scene+' ' in line])
        except Exception as error:
            row.update(status='BLOCKED' if watch.violation or isinstance(error, TimeoutError) else 'FAIL', error=repr(error))
        finally:
            row['quiet']=watch.close(); row['exitBeforeCleanup']=app.poll(); app.terminate()
    return row


def main():
    out=TOOL/'coverage_evidence'/sys.argv[1]
    out.mkdir(exist_ok=False)
    result=dict(status='RUNNING', policy='win_policy window 640x360; max 3/item; observational focus only',
                cp0Comparison='BLOCKED: no matching Windows CP0 numerical baseline', attempts=[], launches=[])
    target=out/'result.json'
    def save(): target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    source=None
    try:
        for port in (18080,18093,18094): require_free(port)
        sources=out/'sources'; sources.mkdir()
        shutil.copyfile(TOOL/'verify_sources/cp0-extra/long.mp4', sources/'vod.mp4')
        shutil.copytree(TOOL/'verify_sources/cp0-extra', sources/'hls')
        handler=functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(sources))
        source=http.server.ThreadingHTTPServer(('127.0.0.1',18094), handler)
        threading.Thread(target=source.serve_forever, daemon=True).start()
        tag=out.name+'-retest'
        info=build(tag, 'lib/main_win_retest.dart', out)
        first=dict(item='retest', build=info, attempts=[]); result['launches'].append(first); save()
        retest(out,tag,first); result['attempts'].extend(first['attempts']); save()
        source.shutdown(); source.server_close(); source=None
        info=build(out.name+'-he', 'lib/main_host_ergonomics_verify.dart', out)
        with KillOnCloseJob() as job, (out/'source.console.log').open('w') as stream:
            helper=subprocess.Popen([sys.executable,'-B',str(TOOL/'verify_sources/live_server.py'),
                '18080',str(out/'live-source.log'),str(TOOL/'coverage_sources/stall.mp4')],
                stdout=stream,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
            assigned=job.assign(helper.pid)
            result['source']=dict(pid=helper.pid, jobAssigned=assigned)
            try:
                end=time.monotonic()+30
                while True:
                    try:
                        with OPENER.open('http://127.0.0.1:18080/vod.mp4',timeout=3) as response: response.read(1)
                        break
                    except OSError:
                        if time.monotonic()>end: raise
                        time.sleep(.1)
                for scene in ('V6','V10'):
                    for iteration in range(1,min(3,win_policy.clamp_runs(3))+1):
                        row=he(out,scene,iteration,info)
                        result['attempts'].append(row); result['launches'].append(row); save()
                        print(scene, iteration,row['status'], flush=True)
            finally:
                helper.terminate(); helper.wait(10)
        statuses=[r['status'] for r in result['attempts']]
        result['status']='FAIL' if 'FAIL' in statuses else 'BLOCKED' if 'BLOCKED' in statuses or len(statuses)!=12 else 'PASS'
    except Exception as error:
        result.update(status='BLOCKED', harness=repr(error))
    finally:
        if source: source.shutdown(); source.server_close()
        save(); print('WINDOWS_RESULT',target,result['status'],flush=True)
    return 0 if result['status']=='PASS' else 1


if __name__=='__main__': sys.exit(main())
