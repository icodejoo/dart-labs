"""Interleaved A/B runner for the Q13 mute-verify page: alternate new-lib / old-lib packages, one process per slice.

Q13 验证页的新旧 lib 交错 A/B 跑法：新旧包轮流启动，每片一个新进程，抵消设备状态随时间漂移。

用法: python ab_run.py --only Q13V --runs 5 --repeat 2 --out ab-b [--pkgs new,old]
前置：本地源 18080 已起，adb reverse 已建，abnew/abold 两个包已装。设备锁屏/灭屏则立即停止，不解锁。
"""
import argparse
import http.server
import re
import subprocess
import threading
import time
from pathlib import Path
from coverage_device import adb, unlocked

PKGS = {
    'new': 'com.icodejoo.mova.mova_example.coverage.abnew',
    'old': 'com.icodejoo.mova.mova_example.coverage.abold',
}
HERE = Path(__file__).resolve().parent


def run_slice(label, pkg, selector, log_path, timeout):
    """Start `pkg` once with `selector`, tee its flutter log lines to `log_path`, return True on AUTORUN DONE.

    用 selector 启动 pkg 一次，只保留 flutter 行写入日志，见到 AUTORUN DONE 返回 True。
    """
    unlocked()

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
    adb('logcat', '-c')
    adb('shell', 'am', 'force-stop', pkg)
    adb('shell', 'am', 'start', '-n', pkg + '/com.icodejoo.mova.mova_example.MainActivity')
    end = time.monotonic() + timeout
    pid = ''
    while not pid and time.monotonic() < end:
        try:
            pid = adb('shell', 'pidof', pkg).strip()
        except subprocess.CalledProcessError:
            time.sleep(.2)
    stream = subprocess.Popen(['adb', '-s', '7NQBB23606003715', 'logcat', '-v', 'threadtime', '--pid=' + pid], stdout=subprocess.PIPE)
    done = threading.Event()

    def read():
        with log_path.open('w', encoding='utf-8') as log:
            for raw in stream.stdout:
                line = raw.decode('utf-8', errors='replace')
                if 'flutter :' not in line and 'UNCAUGHT' not in line:
                    continue
                log.write(line)
                log.flush()
                if 'VERDICT' in line or 'AUTORUN DONE' in line:
                    print(label, re.sub(r'\s+', ' ', line.strip())[-260:], flush=True)
                if 'AUTORUN DONE' in line:
                    done.set()

    threading.Thread(target=read, daemon=True).start()
    while time.monotonic() < end and not done.wait(.5):
        pass
    stream.terminate()
    server.shutdown()
    server.server_close()
    adb('shell', 'am', 'force-stop', pkg)
    return done.is_set()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', required=True)
    ap.add_argument('--runs', type=int, default=5)
    ap.add_argument('--repeat', type=int, default=2)
    ap.add_argument('--out', required=True)
    ap.add_argument('--pkgs', default='new,old')
    ap.add_argument('--timeout', type=int, default=1200)
    a = ap.parse_args()
    out = HERE / 'coverage_evidence' / 'zero-copy-ab' / a.out
    out.mkdir(parents=True, exist_ok=True)
    selector = f'mute|{a.only}|{a.runs}'
    for i in range(1, a.repeat + 1):
        for key in a.pkgs.split(','):
            label = f'{key}-{i}'
            ok = run_slice(label, PKGS[key], selector, out / f'{label}.log', a.timeout)
            print('SLICE', label, 'done' if ok else 'TIMEOUT', flush=True)
            if not ok:
                return


if __name__ == '__main__':
    main()
