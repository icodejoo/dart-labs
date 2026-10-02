#!/usr/bin/env python3
"""WHEP 篡改代理：转发到真实 MediaMTX，并按路径前缀改写 answer，用于 T1.3 失败路径验证。
用法：whep_proxy.py [port]；客户端 URL：http://127.0.0.1:<port>/<mode>/test/whep
mode：
  fp      把 answer 的 sha-256 指纹改掉一个字节（必须被拒绝）
  dead    把候选改成 127.0.0.1:9（端口不可达，ICE 应超时）
  silent  把候选改成 127.0.0.1:18199（静默 UDP，不回包，ICE 应超时）
  ok      原样转发
"""
import http.server, re, socket, sys, urllib.request

UP = 'http://127.0.0.1:8889'
# 静默 UDP：只绑定、不回包
SILENT = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
SILENT.bind(('127.0.0.1', 18199))


class H(http.server.BaseHTTPRequestHandler):
    def _mode(self):
        m = re.match(r'/(fp|dead|silent|ok)(/.*)$', self.path)
        return m.group(1), m.group(2)

    def do_POST(self):
        mode, path = self._mode()
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        req = urllib.request.Request(UP + path, data=body, method='POST',
                                     headers={'Content-Type': 'application/sdp'})
        r = urllib.request.urlopen(req)
        ans = r.read().decode()
        if mode == 'fp':
            def flip(m):
                fp = m.group(1)
                return 'a=fingerprint:sha-256 ' + ('00' if not fp.startswith('00') else '11') + fp[2:]
            ans = re.sub(r'a=fingerprint:sha-256 (\S+)', flip, ans)
        elif mode in ('dead', 'silent'):
            port = '9' if mode == 'dead' else '18199'
            ans = re.sub(r'(a=candidate:\S+ \d+ udp \d+ )\S+ \d+', r'\g<1>127.0.0.1 ' + port, ans)
        out = ans.encode()
        loc = r.headers.get('Location', '')
        self.send_response(201)
        self.send_header('Content-Type', 'application/sdp')
        self.send_header('Location', '/%s%s' % (mode, loc))
        self.send_header('Content-Length', str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def do_DELETE(self):
        mode, path = self._mode()
        req = urllib.request.Request(UP + path, method='DELETE')
        try:
            code = urllib.request.urlopen(req).status
        except urllib.error.HTTPError as e:
            code = e.code
        self.send_response(code)
        self.send_header('Content-Length', '0')
        self.end_headers()
        print('DELETE', path, code, flush=True)

    def log_message(self, *a):
        pass


http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1]) if len(sys.argv) > 1 else 18100), H).serve_forever()
