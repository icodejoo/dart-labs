"""mova 验证用本地源服务器（多客户端，依赖 PATH 里的 ffmpeg）。

用法: python live_server.py <port> <log_file> [stall_mp4] [bind]
  stall_mp4  点播素材路径，不存在时用 ffmpeg 自动生成（40s，约 1.7MB，faststart）；缺省为 <log_file 所在目录>/stall.mp4
  bind       监听地址，缺省 127.0.0.1（手机走 adb reverse 即可）；要让局域网里的手机直连填 0.0.0.0（并放行防火墙端口）
端点:
  /live.flv?gop=50&audio=1&freq=440
                             每个连接起一个 ffmpeg -re 实时推 testsrc2(+sine)，FLV 直播，GOP=帧数(25fps)，freq=音调(Hz)
  /hang                      接受连接，读完请求头后不回任何数据，直到客户端断开
  /vod.mp4                   同一素材，正常点播（支持 Range）
  /ad.mp4                    另一段点播（880Hz 音调、20s，素材与 vod.mp4 区分开，Q13 验收页用它当广告）
  /stall.mp4?t=KEY           同一 KEY 的所有连接只发前 STALL_FRAC 的字节然后挂住，直到 /release?t=KEY
  /release?t=KEY             放行该 KEY（之后的连接正常服务，支持 Range）
  其余                        404
"""
import os
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORT = int(sys.argv[1])
LOG = open(sys.argv[2], "a", buffering=1)
STALL_FILE = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(os.path.abspath(sys.argv[2])), "stall.mp4")
BIND = sys.argv[4] if len(sys.argv) > 4 else "127.0.0.1"
AD_FILE = os.path.join(os.path.dirname(os.path.abspath(STALL_FILE)), "ad.mp4")
STALL_FRAC = 0.10
_seen = set()
_released = set()
_lock = threading.Lock()
_seq = [0]


def log(msg):
    now = time.time()
    LOG.write("%s.%03d %s\n" % (time.strftime("%H:%M:%S", time.localtime(now)), int(now * 1000) % 1000, msg))


def next_id():
    with _lock:
        _seq[0] += 1
        return _seq[0]


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *a):
        pass

    def _wait_close(self, cid):
        """挂住直到客户端断开。"""
        self.connection.settimeout(1.0)
        while True:
            try:
                d = self.connection.recv(1024)
                if not d:
                    break
            except TimeoutError:
                continue
            except OSError:
                break

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        cid = next_id()
        log("c%d OPEN %s" % (cid, self.path))
        try:
            if u.path == "/live.flv":
                self._live(cid, q)
            elif u.path == "/hang":
                self._wait_close(cid)
            elif u.path == "/release":
                with _lock:
                    _released.add(q.get("t", [""])[0])
                self.send_response(200)
                self.send_header("Content-Length", "2")
                self.end_headers()
                self.wfile.write(b"ok")
                log("c%d RELEASE %s" % (cid, q.get("t", [""])[0]))
            elif u.path in ("/stall.mp4", "/vod.mp4"):
                self._stall(cid, q, u.path == "/stall.mp4", STALL_FILE)
            elif u.path == "/ad.mp4":
                self._stall(cid, q, False, AD_FILE)
            else:
                self.send_error(404)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            log("c%d CLOSE" % cid)

    def _live(self, cid, q):
        gop = int(q.get("gop", ["50"])[0])
        audio = q.get("audio", ["1"])[0] == "1"
        freq = q.get("freq", ["440"])[0]
        cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-re",
               "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=25"]
        if audio:
            cmd += ["-f", "lavfi", "-i", "sine=frequency=%s:sample_rate=44100" % freq]
        cmd += ["-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency",
                "-g", str(gop), "-keyint_min", str(gop), "-sc_threshold", "0",
                "-pix_fmt", "yuv420p", "-b:v", "600k"]
        cmd += ["-c:a", "aac", "-b:a", "64k"] if audio else ["-an"]
        cmd += ["-f", "flv", "-flvflags", "no_duration_filesize", "pipe:1"]
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.send_response(200)
        self.send_header("Content-Type", "video/x-flv")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        total, last = 0, time.time()
        try:
            while True:
                d = p.stdout.read1(16384)
                if not d:
                    break
                self.wfile.write(d)
                total += len(d)
                if time.time() - last >= 1.0:
                    last = time.time()
                    log("c%d BYTES %d" % (cid, total))
        finally:
            p.kill()
            log("c%d LIVE_END bytes=%d" % (cid, total))

    def _stall(self, cid, q, may_stall, path):
        """may_stall 时：该 KEY 的所有连接都只发前 STALL_FRAC 的字节然后挂住，直到收到 /release?t=KEY。"""
        key = q.get("t", [""])[0]
        size = os.path.getsize(path)
        rng = self.headers.get("Range")
        start = 0
        if rng and rng.startswith("bytes="):
            s = rng[6:].split("-")[0]
            start = int(s) if s else 0
        stalling = may_stall and key not in _released
        if start > 0:
            self.send_response(206)
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, size - 1, size))
        else:
            self.send_response(200)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(size - start))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        limit = int(size * STALL_FRAC) if stalling else size
        log("c%d STALL stalling=%s start=%d limit=%d size=%d" % (cid, stalling, start, limit, size))
        sent = start
        with open(path, "rb") as f:
            f.seek(start)
            while sent < limit:
                d = f.read(min(16384, limit - sent))
                if not d:
                    break
                self.wfile.write(d)
                sent += len(d)
        if stalling and sent < size:
            log("c%d STALL_HOLD at=%d" % (cid, sent))
            self.connection.settimeout(0.5)
            while key not in _released:
                try:
                    if not self.connection.recv(1024):
                        return
                except TimeoutError:
                    continue
                except OSError:
                    return
            log("c%d STALL_RELEASED" % cid)


def ensure_media(path, freq, seconds):
    """素材不存在时用 ffmpeg 生成：25fps、GOP=50、约 300kbps、moov 在前。"""
    if os.path.exists(path):
        return
    subprocess.run(
        ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
         "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=25",
         "-f", "lavfi", "-i", "sine=frequency=%d:sample_rate=44100" % freq, "-t", str(seconds),
         "-c:v", "libx264", "-preset", "veryfast", "-b:v", "300k", "-g", "50", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "48k", "-movflags", "+faststart", path],
        check=True,
    )


if __name__ == "__main__":
    ensure_media(STALL_FILE, 440, 40)
    ensure_media(AD_FILE, 880, 20)
    srv = ThreadingHTTPServer((BIND, PORT), H)
    srv.daemon_threads = True
    log("SERVER up bind=%s port=%d" % (BIND, PORT))
    srv.serve_forever()
