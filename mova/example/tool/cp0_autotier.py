"""CP0 auto-tier fixture: three CBR HLS variants and shared bandwidth pacing."""
import hashlib
import http.server
import json
from pathlib import Path
import threading
import time
import urllib.parse


def summarize(records):
    """Sample intervals are bounds, never invented event timestamps."""
    rows=[]
    for check in records:
        if check.get('kind')!='CHECK' or not check.get('id','').startswith('CP0.autotier.'):continue
        numbers=check.get('numbers',{})
        samples=numbers.get('samples',[])
        changes=[];first=None;last=None;cache_start=None;cache_intervals=[]
        for sample in samples:
            p=sample['properties'];stamp=sample['sinceOpenUs']
            width=p.get('video-params/w');height=p.get('video-params/h')
            tier=f'{width}x{height}' if isinstance(width,str) and width.isdigit() and width!='0' and isinstance(height,str) and height.isdigit() and height!='0' else None
            if tier:
                if first is None:first=dict(tier=tier,sinceOpenUs=stamp,scheduledSeconds=sample['scheduledSeconds'])
                if last and last['tier']!=tier:
                    changes.append(dict(before=last['tier'],after=tier,afterUs=last['us'],byUs=stamp))
                last=dict(tier=tier,us=stamp)
            paused=p.get('paused-for-cache')=='yes'
            if paused and cache_start is None:cache_start=stamp
            if not paused and cache_start is not None:
                cache_intervals.append(dict(firstObservedUs=cache_start,firstClearUs=stamp,rightCensored=False))
                cache_start=None
        if cache_start is not None:
            cache_intervals.append(dict(firstObservedUs=cache_start,lastObservedUs=samples[-1]['sinceOpenUs'],rightCensored=True))
        events=numbers.get('events',[])
        rows.append(dict(case=check['id'],firstObservedTier=first,observedSwitchCount=len(changes),switchIntervals=changes,
                         cacheIntervals=cache_intervals,qualityEvents=[e for e in events if e.get('event')=='MovaQualityChange'],
                         bufferEvents=[e for e in events if e.get('event')=='MovaBufferChange'],
                         failures=[e for e in events if e.get('event') in ('MovaErrorEvent','MovaPlayFailure','MovaFailover')],
                         note='每秒原生读回；切档次数为观测下界，时刻为区间。起播取首个有效尺寸；卡顿需结合 time-pos 与缓存事件复核。'))
    return rows


def prepare(root, command):
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    variants = [(256, 144, 160000), (640, 360, 700000), (1280, 720, 2400000)]
    master = ['#EXTM3U', '#EXT-X-VERSION:3']
    for width, height, bitrate in variants:
        name = f'v{height}'
        target = root / (name + '.m3u8')
        command(['ffmpeg', '-y', '-v', 'error', '-f', 'lavfi', '-i',
                 f'testsrc2=size={width}x{height}:rate=25', '-t', '120',
                 '-an', '-c:v', 'libx264', '-threads', '2', '-preset', 'veryfast',
                 '-b:v', str(bitrate), '-minrate', str(bitrate), '-maxrate', str(bitrate),
                 '-bufsize', str(bitrate * 2), '-x264-params', 'nal-hrd=cbr:force-cfr=1',
                 '-g', '50', '-keyint_min', '50', '-sc_threshold', '0', '-pix_fmt', 'yuv420p',
                 '-f', 'hls', '-hls_time', '2', '-hls_playlist_type', 'vod',
                 '-hls_segment_filename', str(root / (name + '_%03d.ts')), str(target)], timeout=600)
        master += [f'#EXT-X-STREAM-INF:BANDWIDTH={int(bitrate * 1.15)},RESOLUTION={width}x{height}', target.name]
    (root / 'master.m3u8').write_text('\n'.join(master) + '\n', encoding='utf-8')
    manifest = {'variants': variants, 'limitedBytesPerSecond': 112500,
                'durationSeconds': 120, 'fixtureSha256': {
                    p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in root.iterdir() if p.suffix in ('.ts', '.m3u8')}}
    (root / 'fixture.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    return manifest


def handler(root, request_log):
    lock = threading.Lock()
    log_lock = threading.Lock()
    next_send = [0.0]

    class Hls(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            uri = urllib.parse.urlparse(self.path)
            parts = uri.path.strip('/').split('/')
            if len(parts) != 2 or parts[0] not in ('limited', 'unlimited'):
                self.send_error(404)
                return
            path = Path(root) / Path(parts[1]).name
            if not path.is_file():
                self.send_error(404)
                return
            started = time.monotonic_ns()
            sent = 0
            data = path.read_bytes()
            token=urllib.parse.parse_qs(uri.query).get('t',[None])[0]
            if path.suffix=='.m3u8' and token is not None:
                suffix='?'+urllib.parse.urlencode({'t':token})
                data=('\n'.join(line+suffix if line and not line.startswith('#') else line
                                for line in data.decode('utf-8').splitlines())+'\n').encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/vnd.apple.mpegurl' if path.suffix == '.m3u8' else 'video/mp2t')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            try:
                for offset in range(0, len(data), 8192):
                    chunk = data[offset:offset + 8192]
                    if parts[0] == 'limited':
                        # One schedule shared by every concurrent request: 900 kbit/s aggregate.
                        with lock:
                            now = time.monotonic()
                            next_send[0] = max(now, next_send[0]) + len(chunk) / 112500
                            delay = next_send[0] - now
                        time.sleep(delay)
                    self.wfile.write(chunk)
                    self.wfile.flush()
                    sent += len(chunk)
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                pass
            finally:
                with log_lock, Path(request_log).open('a', encoding='utf-8') as log:
                    log.write(json.dumps(dict(path=self.path, bytes=sent, startNs=started,
                                              endNs=time.monotonic_ns())) + '\n')

        def log_message(self, *args):
            pass
    return Hls
