"""支持 Range（206）的静态文件服务器，供零拷贝/编解码样本验证用。

用法: python range_server.py [--dir DIR] [--port 18090]
`python -m http.server` 不支持 Range，mp4/webm seek 会落不了地，所以单独写这个。
"""
import argparse
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TYPES = {".mp4": "video/mp4", ".webm": "video/webm", ".mkv": "video/x-matroska"}


class Handler(BaseHTTPRequestHandler):
    """按 Range 头返回 200/206，忽略查询串（防缓存用）。"""

    root = "."

    def do_GET(self):
        path = os.path.join(self.root, os.path.basename(self.path.split("?")[0]))
        if not os.path.isfile(path):
            self.send_error(404)
            return
        size = os.path.getsize(path)
        start, end = 0, size - 1
        m = re.match(r"bytes=(\d*)-(\d*)", self.headers.get("Range", ""))
        if m:
            if m.group(1):
                start = int(m.group(1))
                if m.group(2):
                    end = min(int(m.group(2)), size - 1)
            elif m.group(2):
                start = max(0, size - int(m.group(2)))
        partial = m is not None
        self.send_response(206 if partial else 200)
        if partial:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Type", TYPES.get(os.path.splitext(path)[1], "application/octet-stream"))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            with open(path, "rb") as f:
                f.seek(start)
                left = end - start + 1
                while left > 0:
                    chunk = f.read(min(65536, left))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    left -= len(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "rerun-sources", "codec"))
    ap.add_argument("--port", type=int, default=18090)
    a = ap.parse_args()
    Handler.root = os.path.abspath(a.dir)
    ThreadingHTTPServer(("127.0.0.1", a.port), Handler).serve_forever()
