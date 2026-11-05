"""Keep only this campaign's local 18080/18081 fixture alive; retain restarts."""
from datetime import datetime
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'example/tool/coverage_evidence/cp3-source-watchdog'
OUT.mkdir(exist_ok=True)
STATE = OUT.parent / 'cp3-source-watchdog.json'
STOP = OUT / 'stop'


def main():
    child = stream = None
    failures = 0
    events = []

    def record(kind, **details):
        event = dict(at=datetime.now().astimezone().isoformat(), kind=kind, **details)
        events.append(event)
        with (OUT / 'events.jsonl').open('a', encoding='utf-8') as log:
            log.write(json.dumps(event, ensure_ascii=False) + '\n')

    def finish_child():
        if child is not None and child.poll() is None:
            subprocess.run(['taskkill', '/PID', str(child.pid), '/T', '/F'],
                           capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
            child.wait(timeout=15)
        if stream is not None:
            stream.close()

    try:
        while not STOP.exists():
            healthy = False
            try:
                with urllib.request.urlopen('http://127.0.0.1:18080/vod.mp4', timeout=2) as response:
                    healthy = response.status == 200 and len(response.read(16)) == 16
            except OSError:
                pass
            failures = 0 if healthy else failures + 1
            if not healthy and (child is None or child.poll() is not None or failures >= 3):
                if child is not None:
                    record('UNHEALTHY', pid=child.pid, exit=child.poll(), consecutive=failures)
                    finish_child()
                    child = stream = None
                # Never stop a foreign listener; only restart into free ports.
                available = True
                for port in (18080, 18081):
                    with socket.socket() as probe:
                        try:
                            probe.bind(('127.0.0.1', port))
                        except OSError:
                            available = False
                if available:
                    work = OUT / datetime.now().strftime('%H%M%S')
                    work.mkdir()
                    shutil.copy2(ROOT / 'example/tool/coverage_sources/stall.mp4', work / 'stall.mp4')
                    stream = (work / 'process.log').open('wb')
                    argv = [sys.executable, '-u', str(ROOT / 'example/tool/verify_sources/start_sources.py'), '--workdir', str(work)]
                    child = subprocess.Popen(argv, cwd=ROOT, stdin=subprocess.DEVNULL, stdout=stream,
                                             stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
                    record('START', pid=child.pid, evidence=str(work))
                    failures = 0
            STATE.write_text(json.dumps(dict(active=True, pid=os.getpid(), at=time.time(), healthy=healthy,
                                              starts=sum(e['kind'] == 'START' for e in events),
                                              evidence=str(OUT)), indent=2), encoding='utf-8')
            time.sleep(5)
    finally:
        finish_child()
        record('STOP')
        STATE.write_text(json.dumps(dict(active=False, pid=os.getpid(), at=time.time(),
                                         starts=sum(e['kind'] == 'START' for e in events), evidence=str(OUT))), encoding='utf-8')


if __name__ == '__main__':
    main()
