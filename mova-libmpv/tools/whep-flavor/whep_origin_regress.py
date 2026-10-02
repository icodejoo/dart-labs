#!/usr/bin/env python3
"""WHEP 同源校验回归（patches/ffmpeg-whep/0006）：恶意信令 Location / 3xx 不得把 token 带到别的地址。

起三个本地服务：evil（记录收到的一切请求）、转发代理（把 POST 转给真实 WHEP 端点，
再按场景改写响应）、被测命令（ffprobe）。场景：
  same    Location 改成同源绝对地址：DELETE 应到达代理（对照组，证明测试链路有效）
  host    Location 指向 evil 的另一个端口（跨 host:port）：evil 必须收到 0 个请求
  redir   代理对 POST 回 307 跳到 evil：带 token 时不得跟随，evil 必须收到 0 个请求
用法：whep_origin_regress.py --ffprobe /path/to/ffprobe [--upstream http://127.0.0.1:8889] [--path test/whep]
退出码 0 = 全部通过。
"""
import argparse
import http.client
import subprocess
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = "secret-token-xyz"


class Evil(BaseHTTPRequestHandler):
    """记录收到的所有请求（含方法、路径、Authorization）。"""
    hits = []

    def _hit(self):
        Evil.hits.append((self.command, self.path, self.headers.get("Authorization")))
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    do_GET = do_POST = do_DELETE = do_PUT = _hit

    def log_message(self, *a):
        pass


def make_proxy(up, evil_port, mode_box, dels):
    class P(BaseHTTPRequestHandler):
        def do_POST(self):
            n = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(n)
            mode = mode_box[0]
            if mode == "redir":
                self.send_response(307)
                self.send_header("Location", "http://127.0.0.1:%d/redir" % evil_port)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            c = http.client.HTTPConnection(up.hostname, up.port, timeout=10)
            c.request("POST", self.path, body, {"Content-Type": "application/sdp"})
            r = c.getresponse()
            d = r.read()
            self.send_response(r.status)
            if mode == "same":
                loc = "http://127.0.0.1:%d/res/1" % self.server.server_port
            else:
                loc = "http://127.0.0.1:%d/res/1" % evil_port
            self.send_header("Location", loc)
            self.send_header("Content-Type", "application/sdp")
            self.send_header("Content-Length", str(len(d)))
            self.end_headers()
            self.wfile.write(d)

        def do_DELETE(self):
            dels.append((self.path, self.headers.get("Authorization")))
            self.send_response(200)
            self.send_header("Content-Length", "0")
            self.end_headers()

        def log_message(self, *a):
            pass
    return P


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ffprobe", required=True)
    ap.add_argument("--upstream", default="http://127.0.0.1:8889")
    ap.add_argument("--path", default="test/whep")
    a = ap.parse_args()
    up = urllib.parse.urlparse(a.upstream)

    evil = ThreadingHTTPServer(("127.0.0.1", 0), Evil)
    threading.Thread(target=evil.serve_forever, daemon=True).start()
    mode_box, dels = ["same"], []
    proxy = ThreadingHTTPServer(("127.0.0.1", 0), make_proxy(up, evil.server_port, mode_box, dels))
    threading.Thread(target=proxy.serve_forever, daemon=True).start()

    ok = True
    for mode, want_proxy_del, want_evil in (("same", 1, 0), ("host", 0, 0), ("redir", 0, 0)):
        mode_box[0] = mode
        Evil.hits.clear()
        dels.clear()
        url = "whep+http://127.0.0.1:%d/%s" % (proxy.server_port, a.path)
        # ffprobe 打开后立刻关闭 -> read_close 会发 DELETE（若 resource_url 被接受）
        subprocess.run([a.ffprobe, "-v", "warning", "-token", TOKEN, "-handshake_timeout", "8000000",
                        "-i", url], capture_output=True, timeout=60)
        got_del = len(dels)
        good = len(Evil.hits) == want_evil and got_del == want_proxy_del
        if mode == "same" and got_del == 1:
            good = good and dels[0][1] == "Bearer " + TOKEN
        print("%-6s evil_requests=%d proxy_DELETE=%d  %s" % (mode, len(Evil.hits), got_del,
                                                              "PASS" if good else "FAIL"))
        for h in Evil.hits:
            print("   EVIL GOT", h)
        ok &= good
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
