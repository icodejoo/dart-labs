"""Generate gap fixtures outside git; serve Range-capable HTTP on 18085.

No work runs at import time. Full ffmpeg required; encoder failures are HARNESS,
never evidence that the device does not support a codec.
"""
import argparse
import functools
import http.server
import json
from pathlib import Path
import subprocess
import time
import urllib.parse


def generate(out):
    out.mkdir(parents=True, exist_ok=True)
    commands = []

    def ff(*args):
        argv = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', *map(str, args)]
        commands.append(argv)
        subprocess.run(argv, check=True, timeout=600)

    base = out / 'long.mp4'
    ff('-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=25', '-f', 'lavfi', '-i',
       'sine=frequency=660:sample_rate=48000', '-t', '120', '-c:v', 'libx264',
       '-preset', 'ultrafast', '-g', '200', '-keyint_min', '200', '-sc_threshold', '0',
       '-c:a', 'aac', '-movflags', '+faststart', base)
    for label, scale, bitrate in [('low', '320:180', '250k'), ('high', '640:360', '1000k')]:
        folder = out / label
        folder.mkdir(exist_ok=True)
        ff('-i', base, '-vf', 'scale=' + scale, '-c:v', 'libx264', '-preset', 'ultrafast',
           '-b:v', bitrate, '-g', '200', '-sc_threshold', '0', '-c:a', 'aac',
           '-f', 'hls', '-hls_time', '8', '-hls_playlist_type', 'vod', folder / 'index.m3u8')
    (out / 'master.m3u8').write_text(
        '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=350000,RESOLUTION=320x180\nlow/index.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=640x360\nhigh/index.m3u8\n', encoding='utf-8')
    variants = [
        ('sample.mkv', ['-c', 'copy']), ('sample.ts', ['-c', 'copy']),
        ('vp8.webm', ['-an', '-c:v', 'libvpx', '-deadline', 'realtime', '-cpu-used', '8']),
        ('sample.webm', ['-an', '-c:v', 'libvpx-vp9', '-deadline', 'realtime', '-cpu-used', '8']),
        ('vp9.webm', ['-an', '-c:v', 'libvpx-vp9', '-deadline', 'realtime', '-cpu-used', '8']),
        ('hevc.mp4', ['-an', '-c:v', 'libx265', '-preset', 'ultrafast']),
        ('tenbit.mkv', ['-an', '-pix_fmt', 'yuv420p10le', '-c:v', 'libx265', '-preset', 'ultrafast']),
        ('av1.mkv', ['-an', '-c:v', 'libaom-av1', '-cpu-used', '8', '-crf', '45']),
        ('sample.mp3', ['-vn', '-c:a', 'libmp3lame']),
        ('sample.aac', ['-vn', '-c:a', 'aac']), ('sample.flac', ['-vn', '-c:a', 'flac']),
        ('sample.ogg', ['-vn', '-c:a', 'libvorbis']),
        ('sample.ac3', ['-vn', '-c:a', 'ac3']), ('sample.eac3', ['-vn', '-c:a', 'eac3']),
        ('excluded.avi', ['-an', '-c:v', 'mpeg4']),
        ('excluded.wmv', ['-an', '-c:v', 'wmv2']),
    ]
    for name, args in variants:
        ff('-i', base, '-t', '48', *args, out / name)
    ff('-f', 'lavfi', '-i', 'testsrc2=size=3840x2160:rate=10', '-t', '16', '-an', '-c:v', 'libx265', '-preset', 'ultrafast', '-b:v', '20M', out / 'uhd.mp4')
    (out / 'generation.json').write_text(json.dumps(commands, indent=2), encoding='utf-8')


class Handler(http.server.SimpleHTTPRequestHandler):
    """Serve deterministic delayed manifests and late 404s plus byte ranges."""
    def end_headers(self):
        self.send_header('Cache-Control','no-store')
        super().end_headers()

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        if path == '/late-error':
            time.sleep(2)  # Fault injection only; never a timing verdict.
            self.server.late_error = True
            try:
                self.send_error(404)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if path == '/status':
            body = json.dumps({'late_error': getattr(self.server, 'late_error', False)}).encode()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(body)
            return
        if path.startswith('/delayed/'):
            if path == '/delayed/master.m3u8':
                time.sleep(2)  # Makes first-open parked seek reproducible.
            self.path = self.path.replace('/delayed/', '/', 1)
            path = urllib.parse.urlsplit(self.path).path
        file = Path(self.translate_path(self.path))
        if file.is_file() and file.suffix=='.m3u8':
            token=urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query).get('t',[str(time.time_ns())])[0]
            lines=file.read_text(encoding='utf-8').splitlines()
            body=('\n'.join(line if not line or line.startswith('#') else
                line+('&' if '?' in line else '?')+'t='+urllib.parse.quote(token) for line in lines)+'\n').encode()
            self.send_response(200)
            self.send_header('Content-Type','application/vnd.apple.mpegurl')
            self.send_header('Content-Length',str(len(body)))
            self.end_headers()
            try:self.wfile.write(body)
            except (BrokenPipeError,ConnectionResetError):pass
            return
        # Range support matters: native readback must not be limited by this harness.
        if file.is_file() and 'Range' in self.headers:
            value = self.headers['Range']
            if not value.startswith('bytes=') or ',' in value:
                self.send_error(416)
                return
            left, right = value[6:].split('-', 1)
            size = file.stat().st_size
            start = int(left) if left else max(0, size-int(right))
            end = min(int(right), size-1) if right and left else size-1
            if start >= size or end < start:
                self.send_error(416)
                return
            self.send_response(206)
            self.send_header('Content-Type', self.guess_type(str(file)))
            self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
            self.send_header('Content-Length', str(end-start+1))
            self.send_header('Accept-Ranges', 'bytes')
            self.end_headers()
            try:
                with file.open('rb') as stream:
                    stream.seek(start)
                    remaining = end-start+1
                    while remaining:
                        chunk = stream.read(min(65536, remaining))
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                        remaining -= len(chunk)
            except (BrokenPipeError, ConnectionResetError):
                pass  # A player abort is expected on open replacement.
            return
        try:
            super().do_GET()
        except (BrokenPipeError, ConnectionResetError):
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--generate-only', action='store_true')
    parser.add_argument('--reuse', action='store_true')
    args = parser.parse_args()
    if not args.reuse:
        generate(args.out)
    if args.generate_only:
        return
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 18085), functools.partial(Handler, directory=str(args.out)))
    print('GAP_MEDIA_READY 18085', flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
