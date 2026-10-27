"""Rerun6 owned HLS service: throttle only high TS bytes, low remains viable."""
from pathlib import Path
import http.server,functools,time,json
ROOT=Path(__file__).resolve().parent/'rerun-sources/hls'
class Handler(http.server.SimpleHTTPRequestHandler):
 slow=False
 def do_GET(self):
  if self.path.startswith('/throttle/'):
   Handler.slow=self.path.split('?')[0].endswith('/on')
   print(json.dumps({'time':time.time(),'throttle':Handler.slow}),flush=True)
   self.send_response(200);self.end_headers();self.wfile.write(b'ok');return
  print(json.dumps({'time':time.time(),'path':self.path,'slow':Handler.slow}),flush=True)
  try:super().do_GET()
  except (ConnectionAbortedError,ConnectionResetError,BrokenPipeError):pass
 def copyfile(self,source,outputfile):
  if '/high/' in self.path and self.path.split('?')[0].endswith('.ts'):
   while True:
    chunk=source.read(32768)
    if not chunk:return
    if Handler.slow:time.sleep(.65)
    outputfile.write(chunk);outputfile.flush()
  else:super().copyfile(source,outputfile)
print('RERUN6_WEAK_READY 18085 high=32768bytes/650ms low=unlimited',flush=True)
http.server.ThreadingHTTPServer(('127.0.0.1',18085),functools.partial(Handler,directory=str(ROOT))).serve_forever()
