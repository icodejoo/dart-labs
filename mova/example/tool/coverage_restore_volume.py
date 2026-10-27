"""Restore the original volume via audioOnly; never claim locked UI evidence."""
import http.server,json,subprocess,threading,time,urllib.request
from pathlib import Path
from coverage_device import adb
class Selector(http.server.BaseHTTPRequestHandler):
    def do_GET(self):self.send_response(200);self.end_headers();self.wfile.write(b'api')
    def log_message(self,*args):pass
out=Path(__file__).resolve().parent/'coverage_evidence'
server=http.server.HTTPServer(('127.0.0.1',18082),Selector)
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
    adb('reverse','tcp:18082','tcp:18082');adb('forward','tcp:18083','tcp:18083')
    adb('shell','am','force-stop','com.icodejoo.mova.mova_example.coverage')
    adb('shell','am','start','-n','com.icodejoo.mova.mova_example.coverage/com.icodejoo.mova.mova_example.MainActivity')
    base='http://127.0.0.1:18083';data=None
    for attempt in range(80):
        try:data=json.load(urllib.request.urlopen(base+'/',timeout=2));break
        except Exception:time.sleep(.25)
    if data is None:raise RuntimeError('cleanup API did not start')
    data=json.load(urllib.request.urlopen(base+'/run?group=basic'))
    end=time.monotonic()+45
    while data['status']=='running' and time.monotonic()<end:
        time.sleep(.25);data=json.load(urllib.request.urlopen(base+'/'))
    (out/'cleanup-volume-audioOnly.json').write_text(json.dumps({'purpose':'settings restoration only; audioOnly; locked UI not coverage evidence','journal':data},ensure_ascii=False,indent=2),encoding='utf-8')
    result=adb('shell','cmd','media_session','volume','--stream','3','--get')
    (out/'final-volume-native-readback.txt').write_text(result,encoding='utf-8')
    print(data['status'],result,flush=True)
finally:
    adb('shell','am','force-stop','com.icodejoo.mova.mova_example.coverage')
    server.shutdown()
