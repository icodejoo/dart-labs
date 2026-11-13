"""CP0 stage 3; reuse the stage-1 APK and the rerun6/gap native journals."""
import argparse
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import subprocess
import threading
import time
import urllib.parse
import urllib.request
from types import SimpleNamespace

import run_matrix as matrix
from coverage_gap import GapDriver

TOOL=Path(__file__).resolve().parent
FIX=TOOL/'verify_sources/cp0-extra'

def prepare():
    FIX.mkdir(parents=True,exist_ok=True)
    commands=[]
    def ff(*args):
        cmd=['ffmpeg','-v','error','-y',*map(str,args)]
        r=subprocess.run(cmd,capture_output=True,timeout=300)
        commands.append(dict(argv=cmd,code=r.returncode,stderr=r.stderr.decode(errors='replace')))
        if r.returncode:raise RuntimeError(commands[-1])
    if not (FIX/'generation.json').exists():
        ff('-f','lavfi','-i','testsrc2=size=640x360:rate=25','-f','lavfi','-i','sine=frequency=440',
           '-t','48','-c:v','libx264','-threads','1','-preset','ultrafast','-g','200',
           '-c:a','aac','-movflags','+faststart',FIX/'long.mp4')
        for label,scale,bitrate in [('low','320:180','250k'),('high','640:360','1000k')]:
            d=FIX/label;d.mkdir(exist_ok=True)
            ff('-i',FIX/'long.mp4','-vf','scale='+scale,'-c:v','libx264','-threads','1',
               '-preset','ultrafast','-b:v',bitrate,'-g','200','-sc_threshold','0','-c:a','aac',
               '-f','hls','-hls_time','8','-hls_playlist_type','vod',d/'index.m3u8')
        (FIX/'master.m3u8').write_text('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=350000,RESOLUTION=320x180\nlow/index.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=640x360\nhigh/index.m3u8\n')
        (FIX/'generation.json').write_text(json.dumps(commands,indent=2))
    (FIX/'hashes.json').write_text(json.dumps({str(p.relative_to(FIX)):hashlib.sha256(p.read_bytes()).hexdigest() for p in FIX.rglob('*') if p.is_file() and p.suffix in ('.mp4','.ts','.m3u8')},indent=2))

class Selector(http.server.BaseHTTPRequestHandler):
    scene='rerun6'
    def do_GET(self):
        self.send_response(200);self.end_headers();self.wfile.write((Selector.scene+'||30').encode())
    def log_message(self,*a):pass

def serve(port,handler):
    s=http.server.ThreadingHTTPServer(('127.0.0.1',port),handler)
    threading.Thread(target=s.serve_forever,daemon=True).start()
    return s

def fetch(port,path='/'):
    with urllib.request.build_opener(urllib.request.ProxyHandler({})).open('http://127.0.0.1:'+str(port)+path,timeout=10) as r:return json.load(r)

def run_one(run_id,group,count,ui_kits=''):
    manifest=json.loads(matrix.MANIFEST.read_text(encoding='utf-8'))
    manifest['ports']=[18085,18086,18082,18083,18084]
    d=GapDriver(SimpleNamespace(run_id=run_id+'-'+group),manifest)
    d.logical_run_id=run_id;d.gsm=False
    d.gap_harness=[];d.gap_verdicts=[];d.gap_completed=False
    servers=[];data={};complete=False
    try:
        d.preflight()
        Selector.scene='rerun6' if group.startswith('precise-') else 'gap'
        servers.append(serve(18082,Selector))
        d.adb('reverse','tcp:18082','tcp:18082');d.mappings.append(('reverse',18082))
        if Selector.scene=='gap':
            d.media(FIX);d.launch()
            args=SimpleNamespace(group=group,run_id=run_id,iterations=count,seed=20261103,actions=0,ui_kits=ui_kits,timeout=3600)
            d.run_cases(args)
            complete=d.gap_completed
        else:
            from coverage_gap_media import Handler
            servers.append(serve(18084,functools.partial(Handler,directory=str(FIX))))
            d.adb('reverse','tcp:18084','tcp:18084');d.mappings.append(('reverse',18084))
            d.adb('forward','tcp:18083','tcp:18083');d.mappings.append(('forward',18083))
            d.screen();d.adb('shell','am','force-stop',matrix.PACKAGE)
            d.adb('shell','am','start','-n',matrix.MAIN_ACTIVITY)
            d.wait(lambda:fetch(18083)['status']=='idle')
            pid=d.adb('shell','pidof',matrix.PACKAGE).strip()
            stream=(d.out/'native.logcat.txt').open('wb')
            proc=subprocess.Popen(['adb','-s',d.serial,'logcat','--pid='+pid,'-v','threadtime'],stdout=stream,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
            d.children.append((proc,stream))
            mode=group.removeprefix('precise-')
            args=dict(group='new',case='hls',count=count,paused=str(mode=='paused').lower(),cutover=str(mode=='cutover').lower())
            fetch(18083,'/run?'+urllib.parse.urlencode(args))
            deadline=time.monotonic()+2400;last=-1;last_guard=0
            while time.monotonic()<deadline:
                try:data=fetch(18083)
                except OSError:
                    from cp0_device_guard import wait_online
                    wait_online(d.serial)
                    if not d.adb('shell','pidof',matrix.PACKAGE).strip():raise RuntimeError('app process exited; inspect native.logcat.txt')
                    time.sleep(1);continue
                (d.out/'journal.json').write_text(json.dumps(data,ensure_ascii=False),encoding='utf-8')
                n=sum(r.get('kind')=='HLS_RESULT' for r in data['records'])
                if n!=last:print(group,'results',n,flush=True);last=n
                if time.monotonic()-last_guard>30:d.screen();last_guard=time.monotonic()
                if data['status']!='running':complete=data['status']=='done';break
                time.sleep(.5)
            d.capture(group,'final')
    except Exception as e:
        d.gap_harness.append(repr(e));print('CP0 EXTRA ERROR',group,repr(e),flush=True)
        d.capture_failure(group)
    finally:
        d.cleanup()
        for s in servers:s.shutdown();s.server_close()
        partial=d.out/'gap.jsonl'
        actuals={};operations={}
        if partial.exists():
            rows=[json.loads(line) for line in partial.read_text(encoding='utf-8').splitlines() if line.strip()]
            last={};expected_paths={};d.gap_verdicts=[]
            for r in rows:
                case=r['case']
                if r['kind']=='ACTUAL':
                    last[case]=r['data'];actuals.setdefault(case,[]).append(r['data'])
                if r['kind']=='CALL':
                    operations.setdefault(case,[]).append(r['data'])
                    if r['data'].get('method')=='switchQuality':expected_paths[case]=r['data'].get('args',{}).get('uri')
                if r['kind']=='VERDICT':d.gap_verdicts.append(dict(case=case,**r['data'],actual=last.get(case),expectedPath=expected_paths.get(case)))
        result=dict(group=group,planned=count,completed=complete,harness=d.gap_harness,verdicts=d.gap_verdicts,actuals=actuals,operations=operations,evidence=str(d.out))
        if data:
            rows=data.get('records',[]);start=max((i for i,r in enumerate(rows) if r.get('kind')=='BEGIN'),default=0)
            results=[r for r in rows[start:] if r.get('kind')=='HLS_RESULT']
            switches=[r for r in rows[start:] if r.get('kind')=='HLS_SWITCH']
            for r in results:
                switch=next((s for s in switches if s.get('run')==r.get('run')),None)
                r['cp0PathCorrect']=bool(switch and switch.get('uri')==r.get('path'))
                r['cp0DeltaMs']=r['landed']-r['target'] if r.get('landed',-1)>=0 else None
                r['cp0Pass']=bool(r['cp0PathCorrect'] and r['cp0DeltaMs'] is not None and abs(r['cp0DeltaMs'])<=500)
            below200=sum(r['cp0DeltaMs'] is not None and abs(r['cp0DeltaMs'])<200 and r['cp0PathCorrect'] for r in results)
            features=dict(noEligibleLanding=sum(r.get('landed',-1)<0 for r in results),wrongPath=sum(not r['cp0PathCorrect'] for r in results),harnessInvalid=sum(bool(r.get('harnessInvalid')) for r in results),continuedFailed=sum(not r.get('continuedOk',False) for r in results))
            result.update(executed=len(results),passes=sum(r['cp0Pass'] for r in results),below200=below200,below200Percent=100*below200/len(results) if results else None,failureFeatures=features,results=results,errors=[r for r in rows[start:] if r.get('kind') in ('SCRIPT_ERROR','UNCAUGHT')])
        (d.out/'cp0-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
        print('CP0 EXTRA RESULT',json.dumps({k:v for k,v in result.items() if k not in ('results','verdicts')},ensure_ascii=False),flush=True)
    return result

def main():
    p=argparse.ArgumentParser();p.add_argument('--run-id',required=True);p.add_argument('--only');p.add_argument('--cutover-count',type=int,default=160);a=p.parse_args()
    prepare()
    groups=[('precise-normal',60),('precise-paused',60),('precise-cutover',a.cutover_count),('cp0-h28',30),('cp0-parked',30),('cp0-assumptions',3),('lifecycle',3)]
    results=[]
    for g,n in groups:
        if a.only and g not in a.only.split(','):continue
        print('START',g,n,'native readback; continue after individual failures',flush=True)
        r=run_one(a.run_id,g,n);results.append(r)
        if any('CP0_DEVICE_OFFLINE_15_MINUTES' in s for s in r['harness']):break
    (TOOL/'coverage_evidence'/('cp0-extra-'+a.run_id+'.json')).write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')

if __name__=='__main__':main()
