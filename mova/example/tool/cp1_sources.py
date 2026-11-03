"""CP1 local fixture service. Never starts a device or a build on import.

Only the future device driver calls prepare/start. Response gates prove that
pause/manual selection/dispose occur while the relevant native request is pending.
"""
import http.server
import json
from pathlib import Path
import threading
import time
import urllib.parse


class Fixtures:
    def __init__(self, root):
        self.root = Path(root)
        self.lock = threading.Lock()
        self.gate = threading.Event()
        self.gate.set()
        self.reset()

    def reset(self):
        self.gate.set()
        self.kind = ''
        self.reopen_entered = False
        self.swap_entered = False
        self.probe_entered = False
        self.hanging_body = False
        self.probes = {}
        self.requests = []
        self.bps = 0
        self.fail_primary = False
        self.segment_entered = False

    def stats(self):
        with self.lock:
            return dict(reopenEntered=self.reopen_entered, swapEntered=self.swap_entered, probeEntered=self.probe_entered,
                        hangingBody=self.hanging_body, gateReleased=self.gate.is_set(), probes=dict(self.probes),
                        requests=list(self.requests), bytesPerSecond=self.bps, segmentEntered=self.segment_entered)

    def handler(self):
        fixture = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                parsed = urllib.parse.urlparse(self.path)
                query = urllib.parse.parse_qs(parsed.query)
                path = parsed.path
                if path == '/control':
                    action = query.get('action', ['stats'])[0]
                    if action == 'reset': fixture.reset()
                    elif action == 'arm':
                        fixture.kind = query['kind'][0]
                        fixture.gate.clear()
                    elif action == 'release': fixture.gate.set()
                    elif action == 'fail-primary': fixture.fail_primary = True
                    elif action == 'throttle': fixture.bps = int(query['bytesPerSecond'][0])
                    self.reply(json.dumps(fixture.stats()).encode(), 'application/json')
                    return
                probe = 'Dart' in self.headers.get('User-Agent', '') and path.endswith('.m3u8')
                with fixture.lock:
                    fixture.requests.append(dict(path=self.path, probe=probe,
                        userAgent=self.headers.get('User-Agent'), monotonicNs=time.monotonic_ns()))
                    if probe: fixture.probes[self.path] = fixture.probes.get(self.path, 0) + 1
                if probe and fixture.kind == 'probe':
                    fixture.probe_entered = True
                    fixture.gate.wait(60)
                if not probe and path == '/live.m3u8' and fixture.kind == 'reopen':
                    fixture.reopen_entered = True
                    fixture.gate.wait(60)
                if not probe and path == '/new.m3u8' and fixture.kind == 'swap':
                    fixture.swap_entered = True
                    fixture.gate.wait(60)
                if path.endswith('.ts') and fixture.kind == 'recovery' and not fixture.gate.is_set():
                    fixture.segment_entered = True
                    # Real response hangs until the page observes a recovery event.
                    fixture.gate.wait(120)
                if path == '/hang.vtt':
                    self.send_response(404)
                    self.send_header('Content-Length', '1000000')
                    self.end_headers()
                    self.wfile.write(b'not found\n'); self.wfile.flush()
                    fixture.hanging_body = True
                    fixture.gate.clear()
                    fixture.gate.wait(60)
                    return
                if fixture.fail_primary and path.startswith('/primary'):
                    self.reply(b'primary disconnected', 'text/plain', 404); return
                if path.startswith('/missing') or path == '/bad.srt':
                    self.reply(b'not a subtitle or media', 'text/plain', 404)
                    return
                if path in ('/master.m3u8','/primary.m3u8'):
                    body = '#EXTM3U\n' + ''.join(
                        f'#EXT-X-STREAM-INF:BANDWIDTH={bw},RESOLUTION={w}x{h}\n/{h}/index.m3u8?t={time.time_ns()}\n'
                        for h,w,bw in [(1080,1920,3000000),(720,1280,1500000),(360,640,400000)])
                    if path=='/primary.m3u8': body=body.replace('\n/','\n/primary/')
                    self.reply(body.encode(), 'application/vnd.apple.mpegurl')
                    return
                if path in ('/live.m3u8','/new.m3u8'):
                    # Absolute segment URIs preserve base resolution under the alias.
                    body=(fixture.root/'720/index.m3u8').read_text().splitlines()
                    self.reply(('\n'.join('/720/'+line if line and not line.startswith('#') else line for line in body)+'\n').encode(),
                               'application/vnd.apple.mpegurl')
                    return
                target = (fixture.root/path.removeprefix('/primary/').lstrip('/')).resolve()
                if not target.is_relative_to(fixture.root.resolve()) or not target.is_file():
                    self.reply(b'missing', 'text/plain', 404); return
                payload = target.read_bytes()
                if path.startswith('/primary/') and path.endswith('.m3u8'):
                    payload=('\n'.join('/primary/'+path.split('/')[2]+'/'+line if line and not line.startswith('#') else line for line in payload.decode().splitlines())+'\n').encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/vnd.apple.mpegurl' if path.endswith('.m3u8') else 'video/mp2t')
                self.send_header('Content-Length', str(len(payload)))
                self.send_header('Cache-Control', 'no-store'); self.end_headers()
                try:
                    for offset in range(0,len(payload),8192):
                        self.wfile.write(payload[offset:offset+8192]); self.wfile.flush()
                        if fixture.bps and path.endswith('.ts'): time.sleep(8192/fixture.bps)
                except (ConnectionError, OSError): pass

            def reply(self, payload, content_type, status=200):
                self.send_response(status)
                self.send_header('Content-Type', content_type)
                self.send_header('Content-Length', str(len(payload)))
                self.send_header('Cache-Control', 'no-store'); self.end_headers()
                try: self.wfile.write(payload)
                except (ConnectionError, OSError): pass

            def log_message(self, *args): pass
        return Handler


def parse_system(brightness, display, window):
    """Conservative parser: ambiguous OEM output remains BLOCKED, raw text retained."""
    import re
    system = re.fullmatch(r'\s*(\d+)\s*', brightness)
    native = re.findall(r'(?m)^\s*mScreenBrightnessSetting=(\d+(?:\.\d+)?)\s*$', display)
    overrides = re.findall(r'\bmScreenBrightnessOverrideFromWindowManager=(NaN|-?\d+(?:\.\d+)?)', display)
    seed = None
    if len(set(overrides))==1 and len(set(native))==1:
        value=float(overrides[0])
        candidate=value if 0<=value<=1 else float(native[0])
        if 0<=candidate<=1: seed=candidate
    rotations = set(re.findall(r'\bmRotation=(?:ROTATION_)?(0|90|180|270|1|2|3)\b', window))
    # Only source type + visibility; coordinates differ legitimately on fullscreen.
    insets = sorted(set(re.findall(r'InsetsSource[^\n]*(?:type|mType)=(statusBars|navigationBars)[^\n]*(?:visible|mVisible)=(true|false)', window)))
    complete = system is not None and len(set(native)) == 1 and len(set(overrides)) == 1 and seed is not None and len(rotations) == 1 and {x[0] for x in insets} == {'statusBars','navigationBars'}
    return dict(parsed=complete, seedBrightness=seed, brightnessOverride=overrides[0] if len(set(overrides))==1 else None, brightness=int(system[1]) if system else None,
                displayBrightness=native[0] if len(set(native))==1 else None,
                rotation=next(iter(rotations)) if len(rotations)==1 else None, insets=insets)


def parse_pss(text):
    import re
    match = re.search(r'(?m)^\s*TOTAL PSS:\s*(\d+)', text)
    if not match: match = re.search(r'(?m)^\s*TOTAL\s+(\d+)\s+', text)
    return int(match[1]) if match else None
