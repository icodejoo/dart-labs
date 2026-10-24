"""一键起 mova 验证用的全部本地源（依赖 PATH 里的 ffmpeg 与 python）。

用法:
  python start_sources.py [--workdir DIR] [--live-port 18080] [--hls-port 18081] [--bind 127.0.0.1]

起三个进程，Ctrl-C 一起关：
  1. live_server.py   多客户端 FLV 直播 / 挂住 / 卡顿 / 点播（见该文件头注释），端口 --live-port
  2. ffmpeg           HLS 滑动窗口直播写到 <workdir>/hls（-g 50，2s 分片，保留 6 片，删旧片）
  3. python -m http.server  把 <workdir>/hls 在 --hls-port 上提供出去

GOP 固定：FLV 由 URL 参数 gop=<帧数> 决定（25fps，gop=50 即 2s），HLS 固定 -g 50（2s）。
日志写到 <workdir>/server.log（live_server）与 <workdir>/hls_http.log（http.server）。
"""
import argparse
import os
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def _raise_interrupt(*_):
    raise KeyboardInterrupt


def main():
    # Ctrl-Break (Windows) / SIGTERM 也走和 Ctrl-C 一样的收尾，免得留下孤儿进程
    for name in ("SIGBREAK", "SIGTERM"):
        if hasattr(signal, name):
            signal.signal(getattr(signal, name), _raise_interrupt)
    ap = argparse.ArgumentParser()
    ap.add_argument("--workdir", default=os.path.join(HERE, "_work"))
    ap.add_argument("--live-port", type=int, default=18080)
    ap.add_argument("--hls-port", type=int, default=18081)
    ap.add_argument("--bind", default="127.0.0.1")
    a = ap.parse_args()
    hls = os.path.join(a.workdir, "hls")
    os.makedirs(hls, exist_ok=True)
    kids = []
    try:
        kids.append(subprocess.Popen([
            sys.executable, "-u", os.path.join(HERE, "live_server.py"), str(a.live_port),
            os.path.join(a.workdir, "server.log"), os.path.join(a.workdir, "stall.mp4"), a.bind]))
        kids.append(subprocess.Popen([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-re",
            "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=25",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100",
            "-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency",
            "-g", "50", "-keyint_min", "50", "-sc_threshold", "0", "-pix_fmt", "yuv420p", "-b:v", "600k",
            "-c:a", "aac", "-b:a", "64k",
            "-f", "hls", "-hls_time", "2", "-hls_list_size", "6",
            "-hls_flags", "delete_segments+omit_endlist",
            "-hls_segment_filename", "seg%05d.ts", "live.m3u8"], cwd=hls))
        kids.append(subprocess.Popen(
            [sys.executable, "-u", "-m", "http.server", str(a.hls_port), "--bind", a.bind, "--directory", hls],
            stderr=open(os.path.join(a.workdir, "hls_http.log"), "w")))
        print("sources up: live http://%s:%d/live.flv?gop=50&audio=1 | hls http://%s:%d/live.m3u8 | Ctrl-C to stop"
              % (a.bind, a.live_port, a.bind, a.hls_port), flush=True)
        while all(k.poll() is None for k in kids):
            time.sleep(1)
        print("a child exited, shutting down", flush=True)
    except KeyboardInterrupt:
        pass
    finally:
        for k in kids:
            if k.poll() is None:
                k.terminate()
        for k in kids:
            try:
                k.wait(5)
            except subprocess.TimeoutExpired:
                k.kill()


if __name__ == "__main__":
    main()
