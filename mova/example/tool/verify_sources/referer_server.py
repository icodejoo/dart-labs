"""Owned local anti-hotlink fixture with request receipts (no device I/O)."""
import base64
import http.server
import json
import threading
import urllib.parse
from range_server import Handler as RangeHandler

REFERER='https://cp3.example/authorized'
PNG=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC')

class Fixture:
    def __init__(self, root):
        self.root=str(root)
        self.requests=[]
        self.lock=threading.Lock()
    def stats(self):
        with self.lock: return {'requests':list(self.requests)}
    def handler(self):
        fixture=self
        class Handler(RangeHandler):
            root=fixture.root
            def do_GET(self):
                url=urllib.parse.urlsplit(self.path)
                if url.path=='/stats':
                    body=json.dumps(fixture.stats()).encode()
                    self.send_response(200); self.end_headers(); self.wfile.write(body); return
                allowed=self.headers.get('Referer')==REFERER
                with fixture.lock:
                    fixture.requests.append(dict(path=url.path,query=url.query,referer=self.headers.get('Referer'),
                        range=self.headers.get('Range'),status=200 if allowed else 403))
                if not allowed:
                    self.send_error(403,'Referer required'); return
                if url.path.endswith('.vtt'):
                    body=('WEBVTT\n\n00:00:00.000 --> 00:02:00.000\n/sprite.png?'+url.query+'\n').encode()
                elif url.path=='/sprite.png': body=PNG
                elif url.path=='/master.m3u8':
                    body=('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=640x360\n/index.m3u8?'+url.query+'\n').encode()
                else: return super().do_GET()
                self.send_response(200); self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
        return Handler
