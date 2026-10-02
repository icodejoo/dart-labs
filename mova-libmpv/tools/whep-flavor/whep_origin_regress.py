#!/usr/bin/env python3
"""WHEP 同源校验回归（patches/ffmpeg-whep/0006）：恶意信令 Location / 3xx 不得把 token 带到别的地址。

起本地服务：evil（统计收到的连接与请求）、转发代理（把 POST 转给真实 WHEP 端点，
再按场景改写响应）、被测命令（ffprobe）。场景：
  same    Location 改成同源绝对地址：DELETE 应到达代理（对照组，证明测试链路有效）
  host    Location 指向 evil 的另一个端口（跨 host:port）：evil 必须收到 0 个连接
  redir   代理对 POST 回 307 跳到 evil：带 token 时不得跟随，evil 必须收到 0 个连接

https 模式（--https --cert server.crt --key server.key，upstream 填 https://...）：
evil 与代理都用 TLS；并额外验证降级（https -> http）：
  downgrade   Location 改成同 host:port 的 http:// 地址：代理除 POST 外不得再收到任何连接，
              DELETE 不得发出
  dg_other    Location 指向另一个纯 http 明文监听器：明文监听器必须收到 0 个连接
  redir_http  代理对 POST 回 307 跳到明文 http://：明文监听器必须收到 0 个连接
  （明文监听器一旦收到连接，还会检查字节里是否带 token，用于证明没有明文泄漏）

用法：whep_origin_regress.py --ffprobe /path/to/ffprobe [--upstream http://127.0.0.1:8889] [--path test/whep]
      [--https --cert C --key K]
退出码 0 = 全部通过。仅用标准库。
"""
import argparse
import http.client
import socket
import socketserver
import ssl
import subprocess
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = "secret-token-xyz"


class CountingServer(ThreadingHTTPServer):
    """统计 TCP accept 次数（含握手失败/没发请求的连接）；可选 TLS（握手在处理线程里做）。"""
    daemon_threads = True

    def __init__(self, addr, handler, ctx=None):
        super().__init__(addr, handler)
        self.ctx = ctx
        self.accepts = 0

    def get_request(self):
        sock, addr = super().get_request()
        self.accepts += 1
        if self.ctx:
            sock = self.ctx.wrap_socket(sock, server_side=True, do_handshake_on_connect=False)
        return sock, addr

    def handle_error(self, request, client_address):
        pass


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


class PlainSink:
    """纯 TCP 明文监听器：记录连接数与收到的原始字节（用于查 token 是否明文泄漏）。"""

    def __init__(self):
        self.sock = socket.socket()
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(8)
        self.port = self.sock.getsockname()[1]
        self.conns = 0
        self.data = b""
        threading.Thread(target=self._run, daemon=True).start()

    def _run(self):
        while True:
            c, _ = self.sock.accept()
            self.conns += 1
            c.settimeout(1.0)
            try:
                self.data += c.recv(65536)
            except OSError:
                pass
            c.close()

    def reset(self):
        self.conns = 0
        self.data = b""


def make_proxy(up, scheme, evil_port, plain_port, mode_box, dels):
    class P(BaseHTTPRequestHandler):
        def do_POST(self):
            n = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(n)
            mode = mode_box[0]
            if mode in ("redir", "redir_http"):
                if mode == "redir":
                    to = "%s://127.0.0.1:%d/redir" % (scheme, evil_port)
                else:
                    to = "http://127.0.0.1:%d/redir" % plain_port
                self.send_response(307)
                self.send_header("Location", to)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if up.scheme == "https":
                c = http.client.HTTPSConnection(up.hostname, up.port, timeout=10,
                                                context=ssl._create_unverified_context())
            else:
                c = http.client.HTTPConnection(up.hostname, up.port, timeout=10)
            c.request("POST", self.path, body, {"Content-Type": "application/sdp"})
            r = c.getresponse()
            d = r.read()
            self.send_response(r.status)
            me = self.server.server_port
            loc = {
                "same": "%s://127.0.0.1:%d/res/1" % (scheme, me),
                "host": "%s://127.0.0.1:%d/res/1" % (scheme, evil_port),
                "downgrade": "http://127.0.0.1:%d/res/1" % me,
                "dg_other": "http://127.0.0.1:%d/res/1" % plain_port,
            }[mode]
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
    ap.add_argument("--https", action="store_true", help="evil 与代理用 TLS，并增加降级场景")
    ap.add_argument("--cert")
    ap.add_argument("--key")
    a = ap.parse_args()
    up = urllib.parse.urlparse(a.upstream)
    ctx = None
    if a.https:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(a.cert, a.key)
    scheme = "https" if a.https else "http"

    evil = CountingServer(("127.0.0.1", 0), Evil, ctx)
    threading.Thread(target=evil.serve_forever, daemon=True).start()
    plain = PlainSink()
    mode_box, dels = ["same"], []
    proxy = CountingServer(("127.0.0.1", 0),
                           make_proxy(up, scheme, evil.server_port, plain.port, mode_box, dels), ctx)
    threading.Thread(target=proxy.serve_forever, daemon=True).start()

    # (场景, 期望代理 DELETE 数, 期望 evil 连接数, 期望明文监听器连接数)
    cases = [("same", 1, 0, 0), ("host", 0, 0, 0), ("redir", 0, 0, 0)]
    if a.https:
        cases += [("downgrade", 0, 0, 0), ("dg_other", 0, 0, 0), ("redir_http", 0, 0, 0)]
    ok = True
    for mode, want_del, want_evil, want_plain in cases:
        mode_box[0] = mode
        Evil.hits.clear()
        dels.clear()
        plain.reset()
        evil.accepts = 0
        proxy.accepts = 0
        url = "whep+%s://127.0.0.1:%d/%s" % (scheme, proxy.server_port, a.path)
        # ffprobe 打开后立刻关闭 -> read_close 会发 DELETE（若 resource_url 被接受）
        subprocess.run([a.ffprobe, "-v", "warning", "-token", TOKEN, "-handshake_timeout", "8000000",
                        "-i", url], capture_output=True, timeout=60)
        got_del = len(dels)
        # 代理除 POST（redir 类场景里 POST 之后也只有这一个连接）外的额外连接
        extra = proxy.accepts - 1
        leaked = TOKEN.encode() in plain.data
        good = (len(Evil.hits) == 0 and evil.accepts == want_evil and got_del == want_del
                and plain.conns == want_plain and not leaked
                and extra == (1 if mode == "same" else 0))
        if mode == "same" and got_del == 1:
            good = good and dels[0][1] == "Bearer " + TOKEN
        print("%-10s evil_conns=%d evil_requests=%d proxy_extra_conns=%d proxy_DELETE=%d plain_conns=%d "
              "token_in_plain=%s  %s" % (mode, evil.accepts, len(Evil.hits), extra, got_del, plain.conns,
                                         leaked, "PASS" if good else "FAIL"))
        for h in Evil.hits:
            print("   EVIL GOT", h)
        ok &= good
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
