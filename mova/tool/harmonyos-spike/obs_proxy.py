"""本地 OBS 回源代理：把 Flutter-OH 的 OBS 下载变成「分块并行 + 无限重试 + 落盘缓存」。
用法：python -I obs_proxy.py  （监听 127.0.0.1:8099），再设 FLUTTER_OHOS_STORAGE_BASE_URL=http://127.0.0.1:8099
"""
import os, sys, ssl, threading, urllib.request, urllib.error, time
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UP = 'https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com'
CACHE = r'E:\sdk\_dl\obs-cache'
CHUNK = 2 * 1024 * 1024
WORKERS = 12
os.makedirs(CACHE, exist_ok=True)
locks = {}
glock = threading.Lock()
CTX = ssl.create_default_context()


def log(*a):
    print(time.strftime('%H:%M:%S'), *a, flush=True)


def ranged(path, start, end, tries=10**6):
    """带重试的 Range 取块；404 直接抛出。"""
    req = urllib.request.Request(UP + path, headers={'Range': f'bytes={start}-{end}'})
    n = 0
    while True:
        try:
            with urllib.request.urlopen(req, timeout=40, context=CTX) as r:
                data = r.read()
                cr = r.headers.get('Content-Range', '')
                total = int(cr.split('/')[-1]) if '/' in cr else len(data)
                return data, total
        except urllib.error.HTTPError as e:
            if e.code in (404, 403):
                raise
            n += 1
        except Exception:
            n += 1
        time.sleep(0.5)


def fetch(path):
    """确保 path 对应文件完整落盘，返回本地路径；不存在则抛 HTTPError。"""
    local = os.path.join(CACHE, path.strip('/').replace('/', os.sep))
    with glock:
        lk = locks.setdefault(path, threading.Lock())
    with lk:
        if os.path.exists(local):
            return local
        os.makedirs(os.path.dirname(local), exist_ok=True)
        first, total = ranged(path, 0, CHUNK - 1)
        log('GET', path, total)
        parts = {0: first[:CHUNK]}
        offs = list(range(CHUNK, total, CHUNK))

        def one(o):
            d, _ = ranged(path, o, min(o + CHUNK, total) - 1)
            parts[o] = d
        with ThreadPoolExecutor(WORKERS) as ex:
            list(ex.map(one, offs))
        tmp = local + '.part'
        with open(tmp, 'wb') as f:
            for o in sorted(parts):
                f.write(parts[o])
        assert os.path.getsize(tmp) == total, (os.path.getsize(tmp), total)
        os.replace(tmp, local)
        log('DONE', path)
        return local


class H(BaseHTTPRequestHandler):
    def _serve(self, head):
        try:
            local = fetch(self.path.split('?')[0])
        except urllib.error.HTTPError as e:
            self.send_response(e.code); self.send_header('Content-Length', '0'); self.end_headers(); return
        size = os.path.getsize(local)
        self.send_response(200)
        self.send_header('Content-Length', str(size))
        self.send_header('Content-Type', 'application/octet-stream')
        self.end_headers()
        if not head:
            with open(local, 'rb') as f:
                while True:
                    b = f.read(1 << 20)
                    if not b:
                        break
                    self.wfile.write(b)

    def do_GET(self): self._serve(False)
    def do_HEAD(self): self._serve(True)
    def log_message(self, *a): pass


if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 8099), H).serve_forever()
