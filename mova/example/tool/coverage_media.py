"""Create deterministic preview/HLS fixtures and serve them locally.

生成确定性预览/HLS素材并提供本地HTTP服务。
"""
from pathlib import Path
import http.server
import subprocess
import functools
import time

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'coverage_media'
OUT.mkdir(exist_ok=True)
source=ROOT/'coverage_sources/stall.mp4'


def ffmpeg(*args):
    """Generate fixtures from the exact local VOD used by the other scripts.

    从其他脚本共用的本地点播素材生成夹具。
    """
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y',*map(str,args)],check=True)


if not (OUT/'sprite.jpg').exists():
    ffmpeg('-ss','4','-i',source,'-frames:v','1','-vf','scale=320:180',OUT/'sprite.jpg')
    (OUT/'thumbs.vtt').write_text('WEBVTT\n\n00:00:00.000 --> 00:00:40.000\nsprite.jpg#xywh=0,0,160,90\n',encoding='utf-8')
    for size,label in [('320:180','low'),('640:360','high')]:
        folder=OUT/label
        folder.mkdir(exist_ok=True)
        ffmpeg('-i',source,'-vf','scale='+size,'-c:v','libx264','-preset','ultrafast','-g','50','-sc_threshold','0','-c:a','aac',
               '-f','hls','-hls_time','2','-hls_playlist_type','vod',folder/'index.m3u8')
    (OUT/'master.m3u8').write_text('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=250000,RESOLUTION=320x180\nlow/index.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=640x360\nhigh/index.m3u8\n',encoding='utf-8')
print('COVERAGE_MEDIA_READY 18084',flush=True)
class Handler(http.server.SimpleHTTPRequestHandler):
    slow=False
    def do_GET(self):
        if self.path.startswith('/slowthumbs.vtt'):
            print('SLOW_VTT_BEGIN',time.time(),flush=True)
            time.sleep(2.5)
            body=(OUT/'thumbs.vtt').read_bytes()
            self.send_response(200);self.send_header('Content-Type','text/vtt');self.end_headers();self.wfile.write(body)
            print('SLOW_VTT_END',time.time(),flush=True)
            return
        if self.path.startswith('/throttle/'):
            Handler.slow=self.path.split('?')[0].endswith('/on')
            print('THROTTLE',Handler.slow,flush=True)
            self.send_response(200);self.end_headers();self.wfile.write(b'ok');return
        print('HEADERS',self.path,'X-Coverage='+str(self.headers.get('X-Coverage')),flush=True)
        super().do_GET()
    def copyfile(self,source,outputfile):
        if self.path.split('?')[0].endswith('.ts'):
            while True:
                chunk=source.read(1024)
                if not chunk:return
                outputfile.write(chunk);outputfile.flush()
                if Handler.slow:time.sleep(.15)
        else:super().copyfile(source,outputfile)
http.server.ThreadingHTTPServer(('127.0.0.1',18084),functools.partial(Handler,directory=str(OUT))).serve_forever()
