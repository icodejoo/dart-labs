"""CP0 device driver: selector + owned local sources + raw measurements.

Run one scene at a time; --build installs the shared release suite first.
No product thresholds are applied at CP0. Missing observations are BLOCKED.
"""
import argparse
import base64
from contextlib import ExitStack
import hashlib
import http.server
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

TOOL=Path(__file__).resolve().parent
ROOT=TOOL.parents[1]
SERIAL=os.environ.get('MOVA_MATRIX_SERIAL','7NQBB23606003715')
PKG='com.icodejoo.mova.mova_example.coverage'
ACTIVITY=PKG+'/com.icodejoo.mova.mova_example.MainActivity'
sys.path.insert(0,str(TOOL/'verify_sources'))
from range_server import Handler as RangeHandler
SCENES=('p02','pod2','bgpause','pauseload','timeshift','pageview','autotier')


def validate_checks(scene, runs, checks):
    """Require every planned measurement; no numerical product pass line."""
    if scene=='autotier':
        missing=[]
        for mode,count in [('limited',runs),('unlimited',1)]:
            for run in range(count):
                ident=f'CP0.autotier.{mode}.{run}'
                rows=[r for r in checks if r.get('id')==ident]
                if len(rows)!=1 or rows[0].get('status')!='PASS':
                    missing.append(ident+': missing measurement');continue
                samples=rows[0].get('numbers',{}).get('samples',[])
                if [s.get('scheduledSeconds') for s in samples]!=list(range(91)):
                    missing.append(ident+': incomplete sample schedule')
                for key in ('path','time-pos','hls-bitrate','video-params','video-params/w','video-params/h',
                            'vid','track-list','demuxer-cache-state','paused-for-cache'):
                    if not any(isinstance(s.get('properties',{}).get(key),str) and s['properties'][key] for s in samples):
                        missing.append(ident+': native property unavailable: '+key)
        return missing
    variants={'p02':['contentWarm','midPending','postLoad'],'pod2':['wait.ad2','nowait.ad2'],
      'bgpause':['video.true','video.false'],'pauseload':['loading','ready','firstFrame'],
      'timeshift':['dvr','timeshift'],'pageview':['horizontal','vertical']}[scene]
    keys={'p02':['before','after','expectedPath','wrongEpisode','renderEpoch'],
      'pod2':['waitForAdReadyPre','epoch0','firstEpochDelta','firstFrame1Us','firstFrame2Us','firstFrame1','firstFrame2','epoch1','epoch2','epochDelta','first','second','firstFrameGapUs','doneEvents'],
      'bgpause':['before','after','videoAutoPause','manualResume'],
      'pauseload':['before','after','playUs','firstFrameUs','playToFirstFrameUs','reports'],
      'timeshift':['before','behind','advancing','edge','targetMs','builders'],
      'pageview':['before','after','pageIndex','seekEvents','pageEvents']}[scene]
    missing=[]
    for variant in variants:
        for run in range(runs):
            ident=f'CP0.{scene}.{variant}.{run}'
            samples=[r for r in checks if r.get('id')==ident]
            if len(samples)!=1:
                missing.append(f'{ident}: CHECK count={len(samples)}, expected=1');continue
            check=samples[0];numbers=check.get('numbers')
            if check.get('pass') is not True or check.get('status')!='PASS':missing.append(f'{ident}: 缺可用测量')
            if not isinstance(numbers,dict):missing.append(f'{ident}: 缺 numbers');continue
            absent=set(keys)-numbers.keys()
            if absent:missing.append(f'{ident}: 缺字段 {sorted(absent)}')
            for name in ('before','after','first','second','behind','edge','advancing'):
                if name not in numbers:continue
                read=numbers[name]
                if not isinstance(read,dict) or not isinstance(read.get('path'),str) or not read['path'] or type(read.get('timePosMs')) is not int:
                    missing.append(f'{ident}: {name} 缺原生 path/time-pos')
    if scene=='pageview' and not any(r.get('id')=='CP0.pageview.audioFocus' and r.get('status')=='BLOCKED' for r in checks):
        missing.append('缺 audioFocus manual BLOCKED marker')
    return missing


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('scene',choices=SCENES)
    p.add_argument('--run-id',required=True)
    p.add_argument('--runs',type=int,default=3)
    p.add_argument('--build',action='store_true')
    p.add_argument('--timeout',type=int,default=900)
    args=p.parse_args()
    if not __import__('re').fullmatch(r'[A-Za-z0-9_.-]+',args.run_id) or args.runs<1:p.error('invalid run-id/runs')
    out=TOOL/'coverage_evidence'/('matrix-'+args.run_id);out.mkdir(exist_ok=True)
    stem='matrix-'+args.run_id+'-cp0-'+args.scene
    log=(out/(stem+'.commands.log')).open('w',encoding='utf-8')
    children=[];servers=[];original={};original_volume=None;records=[];harness=[];completed=False
    def command(cmd,timeout=120):
        log.write('CALL '+json.dumps(list(map(str,cmd)))+'\n');log.flush()
        r=subprocess.run(cmd,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
        text=r.stdout.decode('utf-8',errors='replace');log.write(f'RET exit={r.returncode}\n'+text+'\n');log.flush()
        if r.returncode:raise RuntimeError(f'{cmd}: exit={r.returncode}: {text[-1500:]}')
        return text
    def adb(*cmd):
        from cp0_device_guard import wait_online
        wait_online(SERIAL)
        return command(['adb','-s',SERIAL,*cmd])
    def unlocked():
        deadline=time.monotonic()+600
        while True:
            window=adb('shell','dumpsys','window')
            if 'isKeyguardShowing=false' in window and 'isKeyguardShowing=true' not in window and 'mScreenOnFully=true' in window:return
            if 'mScreenOnFully=true' not in window:adb('shell','input','keyevent','KEYCODE_WAKEUP')
            if time.monotonic()>=deadline:raise RuntimeError('设备锁屏/熄屏满10分钟；停止，需要机主解锁')
            print('等待解锁亮屏；5秒后复查',flush=True);time.sleep(5)
    def fetch(path='/'):
        with urllib.request.urlopen('http://127.0.0.1:18083'+path,timeout=4) as r:return json.load(r)
    def serve(server):
        servers.append(server);threading.Thread(target=server.serve_forever,daemon=True).start()
    try:
        unlocked()
        volume=adb('shell','cmd','media_session','volume','--stream','3','--get')
        match=re.search(r'volume is (\d+)',volume)
        if not match:raise RuntimeError('无法保存原始媒体音量')
        original_volume=match[1]
        (out/(stem+'.restore.json')).write_text(json.dumps(dict(mediaVolume=original_volume)),encoding='utf-8')
        if args.build:
            native=TOOL/'coverage_native/arm64-v8a';native.mkdir(parents=True,exist_ok=True)
            for source in (ROOT/'packages/media_kit_libs_android_video_slim/android/src/main/jniLibs/arm64-v8a').glob('*.so'):
                if source.read_bytes().startswith(b'version https://git-lfs'):raise RuntimeError('libmpv LFS pointer')
                shutil.copy2(source,native/source.name)
            try:
                command([sys.executable,TOOL/'coverage_build.py','lib/main_cp0_suite_verify.dart','--no-daemon','--max-workers=1',
                         '-Dorg.gradle.jvmargs=-Xms128m -Xmx1024m -XX:MaxMetaspaceSize=384m -XX:ReservedCodeCacheSize=96m -XX:TieredStopAtLevel=1 -XX:ActiveProcessorCount=2 -XX:+UseSerialGC -XX:HeapBaseMinAddress=0x100000000','-Pkotlin.compiler.execution.strategy=in-process'],timeout=1800)
            finally:
                build_log=TOOL/'coverage_isolated_build.log'
                if build_log.exists():shutil.copy2(build_log,out/(stem+'.build.log'))
            apk=ROOT/'example/build/app/outputs/flutter-apk/app-release.apk'
            adb('install','-r',str(apk))
            remote=adb('shell','pm','path',PKG).strip().removeprefix('package:')
            pulled=out/(stem+'.installed.apk');adb('pull',remote,str(pulled))
            hashes={name:hashlib.sha256(path.read_bytes()).hexdigest() for name,path in [('local',apk),('device',pulled)]}
            if hashes['local']!=hashes['device']:raise RuntimeError('installed APK hash mismatch')
            hashes['sources']={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'example/lib').rglob('*cp0*.dart')}
            (out/(stem+'.build.json')).write_text(json.dumps(hashes),encoding='utf-8')
        for direction in ('reverse','forward'):
            original[direction]=adb(direction,'--list')
        def mapping(direction,port):adb(direction,f'tcp:{port}',f'tcp:{port}')
        for port in (18082,18190,18192):mapping('reverse',port)
        mapping('forward',18083)
        fixtures=out/(stem+'-sources');fixtures.mkdir(exist_ok=True)
        # All media fixtures live under the established verify_sources location.
        fixture_info={}
        for name,seconds,freq in [('a',9,440),('b',9,550),('ad',6,660),('ad2',6,770)]:
            webm=args.scene=='pauseload' and name=='b'
            target=fixtures/(name+('.webm' if webm else '.mp4'))
            codec=['-c:v','libvpx','-deadline','realtime','-cpu-used','8','-b:v','600k','-c:a','libvorbis'] if webm else ['-c:v','libx264','-preset','ultrafast','-c:a','aac','-movflags','+faststart']
            command(['ffmpeg','-v','error','-y','-f','lavfi','-i','testsrc2=size=640x360:rate=25','-f','lavfi','-i',f'sine=frequency={freq}',
                     '-t',str(seconds),*codec,'-threads','1','-g','25','-pix_fmt','yuv420p',target])
            fixture_info[name]=json.loads(command(['ffprobe','-v','error','-show_entries','format=format_name:stream=codec_name','-of','json',target]))
        (out/(stem+'.fixtures.json')).write_text(json.dumps(fixture_info,indent=2),encoding='utf-8')
        class Media(RangeHandler):
            root=str(fixtures)
            def do_GET(self):
                # The public B identity stays stable; Content-Type and actual
                # bytes are WebM so sessionStart sampling can distinguish A/B.
                if args.scene=='pauseload' and urllib.parse.urlparse(self.path).path=='/b.mp4':
                    self.path=self.path.replace('/b.mp4','/b.webm',1)
                if 'slow=1' in self.path:time.sleep(1) # stimulus only; no timing verdict uses this sleep
                return super().do_GET()
        serve(http.server.ThreadingHTTPServer(('127.0.0.1',18190),Media))
        class Selector(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200);self.end_headers();self.wfile.write(f'cp0-{args.scene}||{args.runs}'.encode())
            def log_message(self,*args):pass
        serve(http.server.ThreadingHTTPServer(('127.0.0.1',18082),Selector))
        if args.scene=='autotier':
            from cp0_autotier import prepare,handler
            hls=TOOL/'verify_sources'/stem
            info=prepare(hls,command)
            (out/(stem+'.fixtures.json')).write_text(json.dumps(info,indent=2),encoding='utf-8')
            serve(http.server.ThreadingHTTPServer(('127.0.0.1',18192),handler(hls,out/(stem+'.requests.jsonl'))))
        if args.scene=='timeshift':
            hls=fixtures/'hls';hls.mkdir(exist_ok=True)
            stream=(out/(stem+'.hls.log')).open('w')
            child=subprocess.Popen(['ffmpeg','-v','error','-re','-f','lavfi','-i','testsrc2=size=640x360:rate=25',
              '-f','lavfi','-i','sine=frequency=440','-c:v','libx264','-preset','ultrafast','-tune','zerolatency','-g','50','-sc_threshold','0',
              '-c:a','aac','-f','hls','-hls_time','2','-hls_list_size','6','-hls_flags','delete_segments+omit_endlist',str(hls/'live.m3u8')],stdout=stream,stderr=subprocess.STDOUT,
              creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
            children.append((child,stream))
            class Hls(http.server.SimpleHTTPRequestHandler):
                def __init__(self,*a,**kw):super().__init__(*a,directory=str(hls),**kw)
                def do_GET(self):
                    query=urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                    if 'behind' in query and self.path.startswith('/live.m3u8'):
                        text=(hls/'live.m3u8').read_text()
                        behind=int(query['behind'][0])/1000
                        text=text.replace('#EXTM3U',f'#EXTM3U\n#EXT-X-START:TIME-OFFSET=-{behind:.3f},PRECISE=YES')
                        payload=text.encode();self.send_response(200)
                        self.send_header('Content-Type','application/vnd.apple.mpegurl')
                        self.send_header('Content-Length',str(len(payload)));self.send_header('Cache-Control','no-store')
                        self.end_headers();self.wfile.write(payload)
                    else:super().do_GET()
                def log_message(self,*args):pass
            serve(http.server.ThreadingHTTPServer(('127.0.0.1',18192),Hls))
            end=time.monotonic()+45
            while len(list(hls.glob('*.ts')))<6:
                if time.monotonic()>end:raise RuntimeError('HLS fixtures unavailable')
                time.sleep(.25)
        unlocked();adb('shell','am','force-stop',PKG);adb('logcat','-c');adb('shell','am','start','-n',ACTIVITY)
        logcat=(out/(stem+'.log')).open('w',encoding='utf-8')
        pid=adb('shell','pidof',PKG).strip()
        if not pid:raise RuntimeError('app pid unavailable')
        proc=subprocess.Popen(['adb','-s',SERIAL,'logcat','-v','threadtime','--pid='+pid],stdout=logcat,stderr=subprocess.STDOUT,
           creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        children.append((proc,logcat))
        end=time.monotonic()+args.timeout;acted=set();last_error=''
        while time.monotonic()<end:
            try:data=fetch();records=data['records'];last_error=''
            except Exception as e:
                last_error=str(e)
                from cp0_device_guard import wait_online
                wait_online(SERIAL)
                if not adb('shell','pidof',PKG).strip():
                    (out/(stem+'.crash.logcat.txt')).write_text(adb('logcat','-d','-v','threadtime'),encoding='utf-8')
                    harness.append('app process exited; see crash.logcat.txt');break
                time.sleep(.25);continue
            for r in records:
                if r['kind']!='HOST' or r['id'] in acted:continue
                acted.add(r['id']);unlocked()
                if r['action']=='background':
                    adb('shell','input','keyevent','KEYCODE_HOME');time.sleep(3)
                    (out/(stem+'.'+r['id']+'.background.window.txt')).write_text(adb('shell','dumpsys','window'),encoding='utf-8')
                    adb('shell','am','start','-n',ACTIVITY)
                else:
                    rect=r['rect'];x=round(rect['x']+rect['w']*.75);y=round(rect['y']+rect['h']*.6)
                    if r['action']=='swipe-horizontal':ex=round(rect['x']+rect['w']*.2);ey=y
                    else:ex=x;ey=round(rect['y']+rect['h']*.1)
                    adb('shell','input','swipe',str(x),str(y),str(ex),str(ey),'600')
                fetch('/ack?id='+urllib.parse.quote(r['id']))
            if data.get('completed'):completed=True;break
            time.sleep(.1)
        if not completed:harness.append('缺 END/完成标记 '+last_error)
        harness.extend(str(r) for r in records if r['kind']=='ERROR')
        for category in ('window','audio'):
            (out/(stem+'.'+category+'.txt')).write_text(adb('shell','dumpsys',category),encoding='utf-8')
    except Exception as e:
        harness.append(str(e));print('HARNESS',e,flush=True)
    finally:
        if original:
            try:
                adb('shell','am','force-stop',PKG)
                for direction,ports in [('reverse',(18082,18190,18192)),('forward',(18083,))]:
                    for port in ports:
                        key=f'tcp:{port}';old=next((line.split()[-1] for line in original[direction].splitlines() if key in line.split()[:2]),None)
                        if old:adb(direction,key,old)
                        else:adb(direction,'--remove',key)
            except Exception as e:harness.append('cleanup '+str(e))
        if original_volume is not None:
            try:adb('shell','cmd','media_session','volume','--stream','3','--set',original_volume)
            except Exception as e:harness.append('volume restore '+str(e))
        for child,stream in children:
            child.terminate()
            try:child.wait(timeout=10)
            except subprocess.TimeoutExpired:child.kill();child.wait()
            stream.close()
        for server in servers:server.shutdown();server.server_close()
        checks=[r for r in records if r['kind']=='CHECK']
        missing=validate_checks(args.scene,args.runs,checks)
        result=dict(run_id=args.run_id,group=args.scene,completed=completed,harness=harness,missing=missing,records=records,
          verdicts=[dict(case=r['id'],status=r.get('status','BLOCKED'),numbers=r.get('numbers'),reason=r.get('missing')) for r in checks])
        if args.scene=='autotier':
            from cp0_autotier import summarize
            result['summary']=summarize(records)
        target=out/(stem+'.json');target.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
        print('CP0 RESULT',target,'completed',completed,'CHECK',len(checks),'harness',harness,'missing',missing,flush=True)
        for r in checks:print(json.dumps(r,ensure_ascii=False),flush=True)
        log.close()
    return 2 if harness else 1 if missing or not completed else 0

if __name__=='__main__':sys.exit(main())
