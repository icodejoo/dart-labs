#!/usr/bin/env python3
"""Local Chrome fake-device -> WHEP ffprobe / 仅 Python 标准库，无 MediaMTX 依赖。

Windows host: python whep_browser_e2e.py --ffprobe /mnt/e/.../ffprobe --out /path/to/logs
Chrome sends VP8 or H264; ffprobe runs in WSL Ubuntu. No Android/device access.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PAGE = r'''<!doctype html><meta charset="utf-8"><title>WHEP codec regression</title>
<pre id="log"></pre><script>
const log = s => { document.querySelector('#log').textContent += s + '\n';
  fetch('/log', {method:'POST', body:s}).catch(()=>{}); };
(async () => {
 const media = await navigator.mediaDevices.getUserMedia({video:{width:{exact:640},height:{exact:360},frameRate:25},audio:false});
 await fetch('/ready', {method:'POST'});
 const peers = new Map();
 while (true) {
  const job = await (await fetch('/pending')).json();
  if (!job.id) { await new Promise(r=>setTimeout(r,100)); continue; }
  try {
   const pc = new RTCPeerConnection({iceServers:[]}); peers.set(job.id,pc);
   pc.onconnectionstatechange = () => log(job.codec+': '+pc.connectionState);
   await pc.setRemoteDescription({type:'offer',sdp:job.offer});
   const tx = pc.getTransceivers().find(t=>t.receiver.track.kind==='video');
   const codecs = RTCRtpSender.getCapabilities('video').codecs.filter(c=>c.mimeType.toLowerCase()==='video/'+job.codec.toLowerCase());
   if (!codecs.length) throw Error('Chrome has no '+job.codec+' sender');
   tx.setCodecPreferences(codecs); tx.direction='sendonly';
   await tx.sender.replaceTrack(media.getVideoTracks()[0]);
   const answer = await pc.createAnswer(); await pc.setLocalDescription(answer);
   await new Promise(resolve => {if(pc.iceGatheringState==='complete') resolve();
    else pc.onicegatheringstatechange=()=>{if(pc.iceGatheringState==='complete')resolve();};});
   await fetch('/answer/'+job.id,{method:'POST',body:pc.localDescription.sdp});
  } catch(e) {log(String(e)); await fetch('/answer/'+job.id,{method:'POST',body:'ERROR '+e});}
 }
})().catch(e=>log(String(e)));
</script>'''


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--ffprobe', required=True, help='WSL path to the tested ffprobe')
    ap.add_argument('--chrome', default=r'C:\Program Files\Google\Chrome\Application\chrome.exe')
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--codec', choices=['VP8','H264','both'], default='both')
    ap.add_argument('--candidate-host', help='Prefer the reachable Windows adapter (default: WSL gateway)')
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    ready = threading.Event()
    lock = threading.Lock()
    jobs = {}
    browser_log = []
    if a.candidate_host:
        candidate_host = a.candidate_host
    else:
        route_cmd = (['wsl','-d','Ubuntu','--'] if os.name=='nt' else []) + ['ip','route','show','default']
        route = subprocess.check_output(route_cmd,text=True)
        candidate_host = re.search(r'default via ([\d.]+)',route).group(1)

    class Handler(BaseHTTPRequestHandler):
        def send(self, status, body, kind='text/plain', headers=None):
            body = body.encode() if isinstance(body,str) else body
            self.send_response(status)
            self.send_header('Content-Type',kind)
            self.send_header('Content-Length',str(len(body)))
            for k,v in (headers or {}).items():
                self.send_header(k,v)
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == '/pending':
                with lock:
                    job = next((j for j in jobs.values() if not j['taken']),None)
                    if job:
                        job['taken'] = True
                    data = {k:job[k] for k in ('id','codec','offer')} if job else {}
                self.send(200,json.dumps(data),'application/json')
            else:
                self.send(200,PAGE,'text/html')

        def do_OPTIONS(self):
            self.send(204,b'')

        def do_DELETE(self):
            self.send(200,b'')

        def do_POST(self):
            body = self.rfile.read(int(self.headers.get('Content-Length','0'))).decode()
            if self.path == '/ready':
                ready.set(); self.send(200,b''); return
            if self.path == '/log':
                browser_log.append(body); self.send(200,b''); return
            if self.path.startswith('/answer/'):
                with lock:
                    job = jobs[self.path.split('/')[-1]]
                    (a.out/(job['codec']+'-answer-native.sdp')).write_text(body,encoding='utf-8',newline='')
                    # WHEP currently uses the first UDP host candidate; prefer the WSL adapter.
                    lines = body.splitlines()
                    positions = [i for i,line in enumerate(lines) if line.startswith('a=candidate:')]
                    candidates = sorted((lines[i] for i in positions),key=lambda line: candidate_host not in line.split())
                    for i,line in zip(positions,candidates):
                        lines[i] = line
                    body = '\r\n'.join(lines)+'\r\n'
                    job['answer'] = body
                    job['event'].set()
                self.send(200,b''); return
            codec = self.path.split('/')[1]
            ident = str(len(jobs)+1)
            job = dict(id=ident,codec=codec,offer=body,taken=False,event=threading.Event())
            with lock:
                jobs[ident] = job
            (a.out/(codec+'-offer.sdp')).write_text(body,encoding='utf-8',newline='')
            if not job['event'].wait(20):
                self.send(504,'Chrome answer timed out'); return
            answer = job['answer']
            (a.out/(codec+'-answer.sdp')).write_text(answer,encoding='utf-8',newline='')
            if answer.startswith('ERROR'):
                self.send(500,answer); return
            self.send(201,answer,'application/sdp',{'Location':'/session/'+ident})

        def log_message(self, *args):
            pass

    srv = ThreadingHTTPServer(('0.0.0.0',0),Handler)
    srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever,daemon=True).start()
    profile = str((a.out/'chrome-profile').resolve())
    if os.name == 'nt':
        route = subprocess.check_output(['wsl','-d','Ubuntu','--','ip','route','show','default'],text=True)
        gateway = re.search(r'default via ([\d.]+)',route).group(1)
        runner = ['wsl','-d','Ubuntu','--']
    else:
        # WSL hosts HTTP; Windows Chrome reaches it through localhost forwarding.
        gateway, runner = '127.0.0.1', []
        profile = subprocess.check_output(['wslpath','-w',profile],text=True).strip()
        if a.chrome.startswith('C:'):
            a.chrome = subprocess.check_output(['wslpath','-u',a.chrome],text=True).strip()
    log_file = (a.out/'chrome.log').open('wb')
    chrome = subprocess.Popen([a.chrome,'--headless=new','--no-first-run','--no-default-browser-check',
        '--use-fake-device-for-media-stream','--use-fake-ui-for-media-stream',
        '--disable-features=WebRtcHideLocalIpsWithMdns',
        '--force-webrtc-ip-handling-policy=default_public_and_private_interfaces',
        '--user-data-dir='+profile,
        'http://127.0.0.1:'+str(srv.server_port)],stdout=log_file,stderr=log_file,
        creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    success = True
    try:
        if not ready.wait(30):
            raise RuntimeError('Chrome fake-device page did not become ready; see chrome.log')
        for codec in (['VP8','H264'] if a.codec=='both' else [a.codec]):
            cmd = runner + [a.ffprobe,'-v','verbose','-handshake_timeout','12000000',
                   '-first_frame_timeout','15000000','-analyzeduration','1000000',
                   '-read_intervals','%+10','-count_frames','-show_entries',
                   'stream=codec_name,width,height,nb_read_frames','-of','json','-f','whep',
                   '-i',f'whep+http://{gateway}:{srv.server_port}/{codec}/whep']
            (a.out/(codec+'-command.json')).write_text(json.dumps(cmd,ensure_ascii=False),encoding='utf-8')
            result = subprocess.run(cmd,capture_output=True,text=True,timeout=60)
            (a.out/(codec+'-stdout.json')).write_text(result.stdout,encoding='utf-8')
            (a.out/(codec+'-stderr.log')).write_text(result.stderr,encoding='utf-8')
            data = json.loads(result.stdout or '{}')
            streams = data.get('streams',[])
            video = next((s for s in streams if s.get('codec_name')==codec.lower()),{})
            ok = result.returncode==0 and video.get('width')==640 and video.get('height')==360 and int(video.get('nb_read_frames','0')) >= 200
            print(('PASS' if ok else 'FAIL'),codec,'exit='+str(result.returncode),json.dumps(video),flush=True)
            success &= ok
    finally:
        (a.out/'browser-events.log').write_text('\n'.join(browser_log),encoding='utf-8')
        chrome.terminate()
        try:
            chrome.wait(timeout=10)
        except subprocess.TimeoutExpired:
            chrome.kill()
        srv.shutdown()
        log_file.close()
    return 0 if success else 1


if __name__ == '__main__':
    raise SystemExit(main())
