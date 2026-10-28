"""Select existing release pages and archive their real device logs.

选择已有 release 验证页，保存真机原始日志及系统证据。
"""
import argparse
import http.server
import json
from pathlib import Path
import subprocess
import threading
import time
import urllib.request
from coverage_device import adb, unlocked, capture

PKG = 'com.icodejoo.mova.mova_example.coverage'
HERE = Path(__file__).resolve().parent


def main():
    """Host a one-run selector; lifecycle actions follow emitted markers.

    提供本次运行选择器，生命周期动作由真实日志标记触发。
    """
    parser = argparse.ArgumentParser()
    parser.add_argument('group')
    parser.add_argument('--only', default='')
    parser.add_argument('--runs', type=int, default=5)
    parser.add_argument('--timeout', type=int, default=900)
    parser.add_argument('--name')
    args = parser.parse_args()
    unlocked()
    name = args.name or (args.group + '-' + (args.only or 'all'))
    out = HERE / 'coverage_evidence'
    selector = f'{args.group}|{args.only}|{args.runs}'

    class Handler(http.server.BaseHTTPRequestHandler):
        calls=0
        def do_GET(self):
            Handler.calls+=1
            self.send_response(200)
            self.end_headers()
            value=(args.only or 'all') if args.group=='review' and Handler.calls>1 else selector
            self.wfile.write(value.encode())

        def log_message(self, *unused):
            pass

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 18082), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    adb('reverse', 'tcp:18082', 'tcp:18082')
    adb('forward', 'tcp:18083', 'tcp:18083')
    adb('shell', 'am', 'force-stop', PKG)
    print(adb('shell', 'am', 'start', '-n', PKG + '/com.icodejoo.mova.mova_example.MainActivity'), flush=True)
    end = time.monotonic() + args.timeout
    pid = ''
    while not pid and time.monotonic() < end:
        try:
            pid = adb('shell', 'pidof', PKG).strip()
        except subprocess.CalledProcessError:
            time.sleep(.2)
    stream = subprocess.Popen(['adb', '-s', '7NQBB23606003715', 'logcat', '-v', 'threadtime', '--pid='+pid], stdout=subprocess.PIPE)
    lines = []
    finished = threading.Event()
    acted = set()

    def read():
        with (out / (name+'.log')).open('w', encoding='utf-8') as log:
            for raw in stream.stdout:
                line = raw.decode('utf-8', errors='replace')
                log.write(line)
                log.flush()
                lines.append(line)
                if any(s in line for s in ['VERDICT', 'RESULT', 'AUTORUN DONE', 'FAIL ', 'UNCAUGHT', 'SCRIPT_ERROR']):
                    print(line.strip()[:500], flush=True)
                if 'WAIT_HOME' in line and line not in acted:
                    acted.add(line)
                    adb('shell','input','keyevent','KEYCODE_HOME')
                    time.sleep(5)
                    adb('shell','am','start','-n',PKG+'/com.icodejoo.mova.mova_example.MainActivity')
                if 'WAIT_RESTORE' in line:
                    time.sleep(2)
                    adb('shell','am','start','-n',PKG+'/com.icodejoo.mova.mova_example.MainActivity')
                if ' SHOT ' in line or ' MARK ' in line:
                    stamp = str(time.time_ns())
                    (out/(name+'-'+stamp+'.png')).write_bytes(adb('exec-out','screencap','-p',binary=True))
                    (out/(name+'-'+stamp+'.audio.txt')).write_text(adb('shell','dumpsys','audio'),encoding='utf-8')
                if 'AUTORUN DONE' in line or 'Q13 DONE' in line or 'ALL DONE' in line or 'ALL_DONE' in line or ('RFV2|' in line and '|DONE|' in line):
                    finished.set()

    threading.Thread(target=read, daemon=True).start()
    def sample():
        with (out/(name+'.samples.txt')).open('w',encoding='utf-8') as log:
            while not finished.is_set() and time.monotonic()<end:
                log.write('SAMPLE '+str(time.time())+'\n')
                for cmd in [('shell','top','-b','-n','1','-p',pid),('shell','dumpsys','meminfo',PKG)]:
                    try:
                        log.write(adb(*cmd))
                        log.flush()
                    except Exception as error:
                        log.write(str(error)+'\n')
                finished.wait(5)
    threading.Thread(target=sample,daemon=True).start()
    while time.monotonic() < end and not finished.wait(.5):
        if args.group == 'api':
            try:
                with urllib.request.urlopen('http://127.0.0.1:18083/', timeout=1) as response:
                    print('API_READY', response.status, flush=True)
                    finished.set()
            except Exception:
                pass
    for category in ['window','activity','audio','meminfo','batterystats']:
        cmd=['shell','dumpsys',category]
        if category=='meminfo': cmd.append(PKG)
        if category=='batterystats': cmd.append(PKG)
        (out/(name+'.'+category+'.txt')).write_text(adb(*cmd),encoding='utf-8')
    (out/(name+'.png')).write_bytes(adb('exec-out','screencap','-p',binary=True))
    (out/(name+'.run.json')).write_text(json.dumps({'selector':selector,'completed':finished.is_set(),'lines':len(lines),'pid':pid}),encoding='utf-8')
    stream.terminate()
    server.shutdown()
    print('FINISHED', name, finished.is_set(), len(lines), flush=True)


if __name__ == '__main__':
    main()
