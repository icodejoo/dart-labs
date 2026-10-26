#!/usr/bin/env python3
"""WHEP 篡改代理：转发到真实 MediaMTX，并按路径前缀改写 answer，用于 T1.3 失败路径验证。
用法：whep_proxy.py [port]；客户端 URL：http://127.0.0.1:<port>/<mode>/test/whep
mode：
  fp      把 answer 的 sha-256 指纹改掉一个字节（必须被拒绝）
  dead    把候选改成 127.0.0.1:9（端口不可达，ICE 应超时）
  silent  把候选改成 127.0.0.1:18199（静默 UDP，不回包，ICE 应超时）
  ok      原样转发
  lossy   候选改成本代理的 UDP 中继（18201），对 服务端->客户端 的 RTP 媒体包注入故障：
          丢包 LOSS%、相邻两包交换 SWAP%、重复 DUP%、翻转一个载荷字节 CORRUPT%（默认 2/2/1/1，
          环境变量 LOSS/SWAP/DUP/CORRUPT 可改），固定随机种子便于复现；退出时打印计数
  环境变量（均可选，默认值保持旧行为）：UP_URL（上游信令，默认 http://127.0.0.1:8889）、
  MEDIA_HOST（上游 UDP 主机，默认 127.0.0.1）、BIND（本代理监听地址，默认 127.0.0.1；真机走局域网时设 0.0.0.0）、
  LAN_IP（lossy/silent/dead 模式写进 answer 的候选地址，默认 127.0.0.1；真机时填 PC 局域网 IP）、
  MEDIA_PORT（上游 UDP，默认 8189）、RELAY_PORT（中继 UDP，默认 18201）、SILENT_PORT（默认 18199）、
  LOSS_PT（只对该 payload type 的 RTP 注入故障，默认全部；如只丢音频包）、
  SEED（随机种子，默认 12345）、TRACE（写每个 RTP 一行 CSV 的路径：序号,相对秒,seq,rtp时间戳,pt,marker,动作,长度）；
  收到 SIGTERM/SIGINT 时打印 "relay FINAL {...}" 后退出。
"""
import http.server, os, random, re, signal, socket, sys, threading, time, urllib.request

UP = os.environ.get('UP_URL', 'http://127.0.0.1:8889')
MEDIA_UDP = (os.environ.get('MEDIA_HOST', '127.0.0.1'), int(os.environ.get('MEDIA_PORT', 8189)))   # MediaMTX 的 WebRTC UDP 端口
RELAY_PORT = int(os.environ.get('RELAY_PORT', 18201))
BIND = os.environ.get('BIND', '127.0.0.1')
LAN_IP = os.environ.get('LAN_IP', '127.0.0.1')
SEED = int(os.environ.get('SEED', 12345))
TRACE = os.environ.get('TRACE')
# 静默 UDP：只绑定、不回包
SILENT = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
SILENT.bind(('127.0.0.1', int(os.environ.get('SILENT_PORT', 18199))))
STATS = {}


def relay_udp():
    """UDP 中继：客户端<->MediaMTX，对服务端发来的 RTP 媒体包按比例注入故障"""
    pct = {k: float(os.environ.get(k, d)) for k, d in (('LOSS', 2), ('SWAP', 2), ('DUP', 1), ('CORRUPT', 1))}
    rnd = random.Random(SEED)
    cli = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    cli.bind((BIND, RELAY_PORT))
    srv = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    srv.bind(('0.0.0.0', 0))   # 上游可能是非回环地址（如 WSL 的 NAT 地址）
    client = [None]
    st = STATS
    st.update(rtp=0, drop=0, swap=0, dup=0, corrupt=0)
    t0 = time.time()
    tr = open(TRACE, 'w') if TRACE else None

    traced = [0]   # 最近一个已写 trace 的 RTP 序号，用来给"没被改动的包"补一行 pass

    def trace(act, d):
        traced[0] = st['rtp']
        if tr:
            tr.write('%d,%.4f,%d,%d,%d,%d,%s,%d\n' % (st['rtp'], time.time() - t0, int.from_bytes(d[2:4], 'big'),
                                                 int.from_bytes(d[4:8], 'big'), d[1] & 0x7f, d[1] >> 7, act, len(d)))
            tr.flush()
    held = [None]

    def c2s():
        while True:
            try:
                d, a = cli.recvfrom(2048)
                client[0] = a
                srv.sendto(d, MEDIA_UDP)
            except (ConnectionResetError, ConnectionAbortedError):
                continue   # Windows 上对端端口已关会收到 WSAECONNRESET，吞掉继续服务

    def s2c():
        while True:
            try:
                d, _ = srv.recvfrom(2048)
            except (ConnectionResetError, ConnectionAbortedError):
                continue   # 同上：上一会话的 ICMP 不可达不应让中继线程退出
            if client[0] is None:
                continue
            is_rtp = len(d) > 12 and 128 <= d[0] <= 191 and not 192 <= d[1] <= 223
            if is_rtp and os.environ.get('LOSS_PT') and (d[1] & 0x7f) != int(os.environ['LOSS_PT']):
                is_rtp = False   # 只对指定 payload type 注入故障（如只丢音频包）
            if is_rtp:
                st['rtp'] += 1
                r = rnd.random() * 100
                if r < pct['LOSS']:
                    st['drop'] += 1
                    trace('drop', d)
                    continue
                if r < pct['LOSS'] + pct['CORRUPT']:
                    b = bytearray(d)
                    b[len(b) // 2] ^= 0x55
                    d = bytes(b)
                    st['corrupt'] += 1
                    trace('corrupt', d)
                elif r < pct['LOSS'] + pct['CORRUPT'] + pct['DUP']:
                    cli.sendto(d, client[0])
                    st['dup'] += 1
                    trace('dup', d)
                elif r < pct['LOSS'] + pct['CORRUPT'] + pct['DUP'] + pct['SWAP'] and held[0] is None:
                    held[0] = d          # 扣下这个包，等下一个发出去后再补发
                    st['swap'] += 1
                    trace('swap', d)
                    continue
            if is_rtp and traced[0] != st['rtp']:
                trace('pass', d)
            try:
                cli.sendto(d, client[0])
                if held[0] is not None and is_rtp:
                    cli.sendto(held[0], client[0])
                    held[0] = None
            except (ConnectionResetError, ConnectionAbortedError, OSError):
                pass

    def stats():
        import time
        while True:
            time.sleep(5)
            print('relay', st, flush=True)

    for f in (c2s, s2c, stats):
        threading.Thread(target=f, daemon=True).start()


class H(http.server.BaseHTTPRequestHandler):
    def _mode(self):
        m = re.match(r'/(fp|dead|silent|ok|lossy)(/.*)$', self.path)
        return m.group(1), m.group(2)

    def do_POST(self):
        mode, path = self._mode()
        dbg = os.environ.get('PROXY_DEBUG')
        if dbg:
            print('POST', self.path, dict(self.headers), flush=True)
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        if dbg:
            print('POST body bytes', len(body), flush=True)
        req = urllib.request.Request(UP + path, data=body, method='POST',
                                     headers={'Content-Type': 'application/sdp'})
        r = urllib.request.urlopen(req)
        ans = r.read().decode()
        if dbg:
            print('upstream answered', r.status, len(ans), flush=True)
        if mode == 'fp':
            def flip(m):
                fp = m.group(1)
                return 'a=fingerprint:sha-256 ' + ('00' if not fp.startswith('00') else '11') + fp[2:]
            ans = re.sub(r'a=fingerprint:sha-256 (\S+)', flip, ans)
        elif mode in ('dead', 'silent', 'lossy'):
            port = {'dead': '9', 'silent': os.environ.get('SILENT_PORT', '18199'), 'lossy': str(RELAY_PORT)}[mode]
            ans = re.sub(r'(a=candidate:\S+ \d+ udp \d+ )\S+ \d+', r'\g<1>' + LAN_IP + ' ' + port, ans)
        out = ans.encode()
        loc = re.sub(r'^https?://[^/]+', '', r.headers.get('Location', ''))   # 上游给绝对地址（SRS）时去掉主机，保持同源
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
        print('relay FINAL', STATS, flush=True)   # 每个会话结束输出累计计数（Windows 上收不到 SIGTERM 处理器）

    def log_message(self, *a):
        pass



def _final(*_):
    print('relay FINAL', STATS, flush=True)
    os._exit(0)


signal.signal(signal.SIGTERM, _final)
signal.signal(signal.SIGINT, _final)
relay_udp()
http.server.ThreadingHTTPServer((BIND, int(sys.argv[1]) if len(sys.argv) > 1 else 18100), H).serve_forever()
