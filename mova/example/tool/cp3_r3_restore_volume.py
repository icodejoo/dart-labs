"""Use the existing installed app's volume API when OEM shell writes are ignored.

Restoration only: no matrix result or assertion is produced.
"""
import http.server
import json
from pathlib import Path
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

from cp0_device_guard import wait_online

ROOT = Path(__file__).resolve().parents[2]
SERIAL = '7NQBB23606003715'
PKG = 'com.icodejoo.mova.mova_example.coverage'


def main():
    out = Path(sys.argv[1])
    initial = json.loads((out/'initial-settings.json').read_text(encoding='utf-8'))
    commands = []
    def adb(*args):
        wait_online(SERIAL)
        argv = ['adb','-s',SERIAL,*args]
        r = subprocess.run(argv, capture_output=True, timeout=120)
        text = r.stdout.decode('utf-8', errors='replace')
        commands.append(dict(argv=argv, at=time.time(), exit=r.returncode, stdout=text,
                             stderr=r.stderr.decode('utf-8', errors='replace')))
        if r.returncode: raise RuntimeError(str(commands[-1]))
        return text
    original = {d:adb(d,'--list') for d in ['reverse','forward']}
    media = (ROOT/'example/assets/test_video.mp4').read_bytes()
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            data = b'api' if self.path == '/group' else media
            self.send_response(200)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            try: self.wfile.write(data)
            except (ConnectionError, OSError): pass
        def log_message(self, *args): pass
    server = http.server.ThreadingHTTPServer(('127.0.0.1',18082),Handler)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    response = None
    try:
        from coverage_device import unlocked
        unlocked()
        adb('reverse','tcp:18082','tcp:18082')
        adb('forward','tcp:18083','tcp:18083')
        adb('shell','am','start','-n',PKG+'/com.icodejoo.mova.mova_example.MainActivity')
        def fetch(path='/'):
            with urllib.request.urlopen('http://127.0.0.1:18083'+path,timeout=5) as stream:
                return json.load(stream)
        end = time.monotonic()+45
        while True:
            try:
                response = fetch()
                if 'status' in response: break
            except Exception: pass
            if time.monotonic()>end: raise TimeoutError('restoration API unavailable')
            time.sleep(.3)
        args = dict(group='video',audio='true',url='http://127.0.0.1:18082/restore.mp4',
                    action='volume',value=str(int(initial['volume'])/20*100))
        response = fetch('/run?'+urllib.parse.urlencode(args))
        while response['status'] == 'running':
            if time.monotonic()>end: raise TimeoutError('restoration command did not finish')
            time.sleep(.3)
            response = fetch()
        adb('shell','cmd','media_session','volume','--stream','3','--get')
        time.sleep(2)
        adb('shell','cmd','media_session','volume','--stream','3','--get')
    finally:
        adb('shell','am','force-stop',PKG)
        for direction, port in [('reverse',18082),('forward',18083)]:
            key = f'tcp:{port}'
            old = next((line.split()[-1] for line in original[direction].splitlines() if key in line.split()[:-1]),None)
            if old: adb(direction,key,old)
            else: adb(direction,'--remove',key)
        server.shutdown(); server.server_close()
        adb('shell','cmd','media_session','volume','--stream','3','--get')
        (out/'volume-app-restoration.json').write_text(json.dumps(dict(initial=initial, commands=commands,
                 apiResponse=response),ensure_ascii=False,indent=2),encoding='utf-8')
    print(commands[-1]['stdout'])


if __name__=='__main__': main()
