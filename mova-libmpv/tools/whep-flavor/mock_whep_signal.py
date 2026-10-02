#!/usr/bin/env python3
"""WHEP 信令 mock（只处理 HTTP 信令，不做 ICE/DTLS/媒体），仅用 Python 标准库。

用途：验证 libavformat/whep.c（T1.2）的信令与 SDP 解析。
  - POST  <path>   校验请求头与 offer，按路径返回不同场景的响应
  - DELETE /s/<id> 释放会话，并在日志里留下 DELETE 记录

场景（POST 的路径）：
  /x        正常：201 + 相对 Location + Link ice-server + 合法 answer（沿用 offer 的 payload type）
  /remap    正常：201 + 绝对 Location；answer 换成 opus=97、H264=99、rtx=100（证明 PT 取自 answer）
  /nf       404
  /unauth   401（无视 token）
  /nofp     201 + Location，但 answer 没有 fingerprint（客户端应拒绝，并 DELETE 回收）
  /badfp    201 + Location，fingerprint 格式非法
  /sha1     201 + Location，fingerprint 算法是 sha-1
  /nocand   201 + Location，answer 没有候选
  /bad      201 + Location，body 不是 SDP
  /slow     睡 SLOW_SECS 秒再回（测超时）
带 --token 时，/x /remap 等正常路径要求 Authorization: Bearer <token>，否则 401。

每个请求输出一行 JSON 到 stdout（并可写入 --log 文件）；启动后第一行是 "LISTEN <port>"。
"""
import argparse
import itertools
import json
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SLOW_SECS = 8
# 服务端"证书指纹"（固定值，只用于校验客户端是否按格式解析）
SERVER_FP = ":".join("%02X" % ((i * 7 + 3) & 0xFF) for i in range(32))
FP_RE = re.compile(r"^a=fingerprint:sha-256 ([0-9A-F]{2}:){31}[0-9A-F]{2}$")

_ids = itertools.count(1)
_sessions = set()
_lock = threading.Lock()
LOG_FILE = None


def log(**kw):
    """输出一行 JSON 日志（stdout + 可选文件）。"""
    kw["t"] = round(time.time(), 3)
    line = json.dumps(kw, ensure_ascii=False)
    with _lock:
        print(line, flush=True)
        if LOG_FILE:
            LOG_FILE.write(line + "\n")
            LOG_FILE.flush()


def check_offer(body, headers):
    """校验客户端 offer，返回问题列表（空表示合法）与解析出的编码信息。"""
    problems = []
    if headers.get("Content-Type", "").split(";")[0].strip() != "application/sdp":
        problems.append("Content-Type != application/sdp")
    if not body.startswith("v=0\r\n"):
        problems.append("offer 不是以 v=0 CRLF 开头")
    lines = body.split("\r\n")
    nb = body.replace("\r\n", "\n")  # 正则按 LF 匹配
    if not body.endswith("\r\n"):
        problems.append("offer 末尾没有 CRLF")
    # RFC 4566 o=<user> <sess-id> <sess-version> IN IP4 <addr>：id/version 必须纯十进制，
    # 且 <= 2^63-1（MediaMTX/pion 实测：十六进制 id 直接 400）
    o_line = lines[1] if len(lines) > 1 else ""
    om = re.match(r"^o=(\S+) (\S+) (\S+) IN IP4 (\S+)$", o_line)
    if not om:
        problems.append("o= 行格式不对: %r" % o_line)
    else:
        for nm, v in (("sess-id", om.group(2)), ("sess-version", om.group(3))):
            if not re.fullmatch(r"[0-9]+", v) or int(v) > 2**63 - 1:
                problems.append("o= %s 不是 <=2^63-1 的纯十进制数字: %r" % (nm, v))
    ms = [l for l in lines if l.startswith("m=")]
    if [l.split()[0] for l in ms] != ["m=audio", "m=video"]:
        problems.append("m= 段不是 audio,video: %r" % ms)
    if body.count("a=recvonly") != 2 or "a=sendonly" in body or "a=sendrecv" in body:
        problems.append("方向不是两段 recvonly")
    if body.count("a=setup:actpass") != 2:
        problems.append("setup 不是 actpass x2")
    fps = [l for l in lines if l.startswith("a=fingerprint:")]
    if len(fps) != 2 or not all(FP_RE.match(l) for l in fps):
        problems.append("fingerprint 缺失或格式不对: %r" % fps)
    uf = re.findall(r"^a=ice-ufrag:(\S+)$", nb, re.M)
    pw = re.findall(r"^a=ice-pwd:(\S+)$", nb, re.M)
    if not uf or not pw or len(uf[0]) < 4 or len(pw[0]) < 22:
        problems.append("ice-ufrag/pwd 缺失或过短")
    if body.count("a=rtcp-mux") != 2:
        problems.append("缺 rtcp-mux")
    opus = re.search(r"^a=rtpmap:(\d+) opus/48000/2$", nb, re.M)
    h264 = re.findall(r"^a=rtpmap:(\d+) H264/90000$", nb, re.M)
    rtx = re.findall(r"^a=fmtp:(\d+) apt=(\d+)$", nb, re.M)
    if not opus:
        problems.append("缺 opus rtpmap")
    if not h264:
        problems.append("缺 H264 rtpmap")
    for pt in h264:
        if not re.search(r"^a=rtcp-fb:%s nack$" % pt, nb, re.M):
            problems.append("H264 pt=%s 缺 rtcp-fb nack" % pt)
        if not re.search(r"^a=rtcp-fb:%s nack pli$" % pt, nb, re.M):
            problems.append("H264 pt=%s 缺 rtcp-fb nack pli" % pt)
    if not rtx:
        problems.append("缺 rtx apt")
    info = {
        "opus_pt": int(opus.group(1)) if opus else None,
        "h264_pts": [int(x) for x in h264],
        "rtx": [[int(a), int(b)] for a, b in rtx],
        "offer_ufrag": uf[0] if uf else None,
    }
    return problems, info


def build_answer(mode, info):
    """按场景生成 answer SDP。"""
    if mode == "remap":
        opus_pt, h264_pt, rtx_pt = 97, 99, 100
    else:
        opus_pt = info["opus_pt"]
        h264_pt = info["h264_pts"][0]
        rtx_pt = next((r for r, a in info["rtx"] if a == h264_pt), 112)
    fp = "" if mode == "nofp" else "a=fingerprint:sha-256 %s\r\n" % SERVER_FP
    if mode == "badfp":
        fp = "a=fingerprint:sha-256 ZZ:11\r\n"
    if mode == "sha1":
        fp = "a=fingerprint:sha-1 %s\r\n" % ":".join(SERVER_FP.split(":")[:20])
    cand = "" if mode == "nocand" else \
        "a=candidate:1 1 udp 2130706431 127.0.0.1 38000 typ host\r\n"
    return (
        "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n"
        "a=group:BUNDLE 0 1\r\na=ice-lite\r\n"
        "m=audio 9 UDP/TLS/RTP/SAVPF %d\r\nc=IN IP4 0.0.0.0\r\n"
        "a=ice-ufrag:srvu\r\na=ice-pwd:srvpwd0123456789abcdefghij\r\n%s"
        "a=setup:passive\r\na=mid:0\r\na=sendonly\r\na=rtcp-mux\r\n"
        "a=rtpmap:%d opus/48000/2\r\na=fmtp:%d minptime=10;useinbandfec=1\r\n%s"
        "m=video 9 UDP/TLS/RTP/SAVPF %d %d\r\nc=IN IP4 0.0.0.0\r\n"
        "a=ice-ufrag:srvu\r\na=ice-pwd:srvpwd0123456789abcdefghij\r\n%s"
        "a=setup:passive\r\na=mid:1\r\na=sendonly\r\na=rtcp-mux\r\na=rtcp-rsize\r\n"
        "a=rtpmap:%d H264/90000\r\na=rtcp-fb:%d nack\r\na=rtcp-fb:%d nack pli\r\n"
        "a=fmtp:%d level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f\r\n"
        "a=rtpmap:%d rtx/90000\r\na=fmtp:%d apt=%d\r\n"
    ) % (opus_pt, fp, opus_pt, opus_pt, cand,
         h264_pt, rtx_pt, fp,
         h264_pt, h264_pt, h264_pt, h264_pt, rtx_pt, rtx_pt, h264_pt)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    token = None

    def log_message(self, fmt, *args):  # 关掉默认访问日志，改用 JSON 日志
        pass

    def _send(self, code, body=b"", headers=None):
        self.send_response(code)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(n).decode("utf-8", "replace")
        mode = self.path.strip("/").split("/")[0]
        auth = self.headers.get("Authorization")
        rec = {"ev": "POST", "path": self.path, "len": n, "auth": auth and "Bearer ***",
               "ctype": self.headers.get("Content-Type"), "ua": self.headers.get("User-Agent")}
        if mode == "nf":
            log(**rec, status=404)
            return self._send(404, b"not found")
        if mode == "unauth":
            log(**rec, status=401)
            return self._send(401, b"unauthorized", {"WWW-Authenticate": "Bearer"})
        if self.token and auth != "Bearer " + self.token:
            log(**rec, status=401, why="token mismatch")
            return self._send(401, b"unauthorized", {"WWW-Authenticate": "Bearer"})
        problems, info = check_offer(body, self.headers)
        if problems:
            log(**rec, status=400, problems=problems)
            return self._send(400, ("; ".join(problems)).encode())
        if mode == "slow":
            time.sleep(SLOW_SECS)
        sid = "s%d" % next(_ids)
        with _lock:
            _sessions.add(sid)
        host = self.headers.get("Host")
        loc = ("http://%s/s/%s" % (host, sid)) if mode == "remap" else "/s/%s" % sid
        hdr = {"Location": loc, "Content-Type": "application/sdp",
               "Link": '<stun:stun.example.org:3478>; rel="ice-server", '
                       '<turn:turn.example.org:3478?transport=udp>; rel="ice-server"; '
                       'username="u1"; credential="secretcred"; credential-type="password"'}
        answer = "garbage, not sdp" if mode == "bad" else \
            "" if mode == "empty" else build_answer(mode, info)
        log(**rec, status=201, sid=sid, offer_ok=True, mode=mode,
            opus_pt=info["opus_pt"], h264_pts=info["h264_pts"], rtx=info["rtx"],
            offer_ufrag=info["offer_ufrag"], location=loc)
        self._send(201, answer.encode(), hdr)

    def do_DELETE(self):
        m = re.match(r"^/s/(s\d+)$", self.path)
        rec = {"ev": "DELETE", "path": self.path,
               "auth": self.headers.get("Authorization") and "Bearer ***"}
        with _lock:
            ok = bool(m) and m.group(1) in _sessions
            if ok:
                _sessions.discard(m.group(1))
        log(**rec, status=200 if ok else 404, sid=m.group(1) if m else None)
        self._send(200 if ok else 404)


def main():
    global LOG_FILE
    ap = argparse.ArgumentParser(description="WHEP 信令 mock（仅标准库）")
    ap.add_argument("--port", type=int, default=0, help="监听端口，0=自动")
    ap.add_argument("--token", help="要求的 Bearer token")
    ap.add_argument("--log", help="JSON 日志文件")
    a = ap.parse_args()
    Handler.token = a.token
    if a.log:
        LOG_FILE = open(a.log, "w", encoding="utf-8")
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), Handler)
    print("LISTEN %d" % srv.server_address[1], flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())
