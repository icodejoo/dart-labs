"""Range-capable local fixture server plus a real-time sliding HLS live source.

ffmpeg is required as in coverage_gap_media.py. All artifacts go to --out, not
the repository. Use --reuse to serve a previously generated H.264 fixture.
"""
import argparse
import functools
import http.server
from pathlib import Path
import subprocess
import threading
import time
from coverage_gap_media import Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--reuse', action='store_true')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    vod = args.out / 'perf-1080.mp4'
    if not args.reuse:
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
            '-f', 'lavfi', '-i', 'testsrc2=size=1920x1080:rate=30',
            '-f', 'lavfi', '-i', 'sine=frequency=660:sample_rate=48000',
            '-t', '30', '-c:v', 'libx264', '-preset', 'veryfast', '-pix_fmt', 'yuv420p',
            '-g', '60', '-keyint_min', '60', '-sc_threshold', '0', '-b:v', '6M',
            '-c:a', 'aac', '-movflags', '+faststart', str(vod)], check=True, timeout=600)
    if not vod.exists():
        parser.error('missing perf-1080.mp4')
    # feed 场景三路并发：设备 AVC 硬解同时开 3 路 1080p 时第三路 configureCodec 报 -12，
    # 并不断重试、卡死 App 主线程，所以 feed 用 720p 源（--reuse 时缺失也会补生成）。
    feed = args.out / 'perf-720.mp4'
    if not feed.exists():
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
            '-f', 'lavfi', '-i', 'testsrc2=size=1280x720:rate=30',
            '-f', 'lavfi', '-i', 'sine=frequency=660:sample_rate=48000',
            '-t', '30', '-c:v', 'libx264', '-preset', 'veryfast', '-pix_fmt', 'yuv420p',
            '-g', '60', '-keyint_min', '60', '-sc_threshold', '0', '-b:v', '3M',
            '-c:a', 'aac', '-movflags', '+faststart', str(feed)], check=True, timeout=600)
    live = args.out / 'live'
    live.mkdir(exist_ok=True)
    # Unique segment prefix prevents accidentally serving stale prior-run TS.
    prefix = str(time.time_ns())
    argv = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-re',
            '-stream_loop', '-1', '-i', str(vod), '-c', 'copy', '-f', 'hls',
            '-hls_time', '2', '-hls_list_size', '6', '-hls_flags',
            'delete_segments+omit_endlist+independent_segments',
            '-hls_segment_filename', str(live / (prefix + '-%06d.ts')),
            str(live / 'index.m3u8')]
    process = subprocess.Popen(argv)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 18085),
        functools.partial(Handler, directory=str(args.out)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print('PERF_MEDIA_READY :18085 (allow 14s for live window)', flush=True)
    try:
        while process.poll() is None:
            time.sleep(1)
        raise RuntimeError('live ffmpeg exited: ' + str(process.returncode))
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == '__main__':
    main()
