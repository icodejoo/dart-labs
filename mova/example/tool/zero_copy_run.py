"""Drive main_hwdec_matrix_verify through the coverage suite and sample device evidence at its markers.

驱动 hwdec 矩阵验证页：在页面打出的标记行处采集设备侧证据（CPU、解码器 dumpsys、截图），回桌面/回前台由标记触发。

用法: python zero_copy_run.py <name> --only codec,shot --runs 3 [--timeout 1500]
前置：start_sources.py（18080）与 range_server.py（18090）已起，adb reverse 已建，已安装 coverage 包。
"""
import argparse
import http.server
import re
import subprocess
import threading
import time
from pathlib import Path
from coverage_device import adb, unlocked, shot

PKG = 'com.icodejoo.mova.mova_example.coverage'
HERE = Path(__file__).resolve().parent
OUT = HERE / 'coverage_evidence' / 'zero-copy'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('name')
    ap.add_argument('--only', default='codec')
    ap.add_argument('--runs', type=int, default=3)
    ap.add_argument('--timeout', type=int, default=1500)
    a = ap.parse_args()
    unlocked()
    OUT.mkdir(parents=True, exist_ok=True)
    selector = f'hwdec|{a.only}|{a.runs}'

    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(selector.encode())

        def log_message(self, *u):
            pass

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 18082), H)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    adb('reverse', 'tcp:18082', 'tcp:18082')
    adb('shell', 'am', 'force-stop', PKG)
    adb('shell', 'am', 'start', '-n', PKG + '/com.icodejoo.mova.mova_example.MainActivity')
    end = time.monotonic() + a.timeout
    pid = ''
    while not pid and time.monotonic() < end:
        try:
            pid = adb('shell', 'pidof', PKG).strip()
        except subprocess.CalledProcessError:
            time.sleep(.2)
    stream = subprocess.Popen(['adb', '-s', '7NQBB23606003715', 'logcat', '-v', 'threadtime', '--pid=' + pid], stdout=subprocess.PIPE)
    done = threading.Event()

    def save(name, text):
        (OUT / name).write_text(text, encoding='utf-8')

    def safe(*cmd):
        try:
            return adb(*cmd)
        except Exception as e:  # noqa
            return f'ERR {e}'

    def read():
        with (OUT / f'{a.name}.log').open('w', encoding='utf-8') as log:
            for raw in stream.stdout:
                line = raw.decode('utf-8', errors='replace')
                log.write(line)
                log.flush()
                if 'HWM_ROW' in line or 'AUTORUN DONE' in line or 'UNCAUGHT' in line:
                    print(line.strip()[-400:], flush=True)
                m = re.search(r'HWM_PROBE (\S+)', line)
                if m:
                    i = m.group(1)
                    shot(OUT / f'hwm-{i}.png')
                    save(f'hwm-{i}.codec.txt', safe('shell', 'dumpsys', 'media.codec'))
                    save(f'hwm-{i}.rm.txt', safe('shell', 'dumpsys', 'media.resource_manager'))
                    save(f'hwm-{i}.toph.txt', safe('shell', 'top', '-H', '-b', '-n', '2', '-d', '1', '-m', '12', '-p', pid))
                    save(f'hwm-{i}.top.txt', safe('shell', 'top', '-b', '-n', '4', '-d', '1', '-m', '6'))
                m = re.search(r'HWM_SHOT (\S+)', line)
                if m:
                    shot(OUT / f'hwm-{m.group(1)}.png')
                m = re.search(r'HWM_PIPCHECK (\S+)', line)
                if m:
                    save(f'hwm-{m.group(1)}.pip.txt', safe('shell', 'dumpsys', 'activity', 'activities'))
                if 'WAIT_HOME' in line:
                    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
                    time.sleep(5)
                    adb('shell', 'am', 'start', '-n', PKG + '/com.icodejoo.mova.mova_example.MainActivity')
                if 'WAIT_RESTORE' in line:
                    time.sleep(1)
                    adb('shell', 'am', 'start', '-n', PKG + '/com.icodejoo.mova.mova_example.MainActivity')
                if 'AUTORUN DONE' in line:
                    done.set()

    threading.Thread(target=read, daemon=True).start()
    while time.monotonic() < end and not done.wait(.5):
        pass
    stream.terminate()
    server.shutdown()
    print('FINISHED', a.name, done.is_set(), flush=True)


if __name__ == '__main__':
    main()
