"""CP3 device driver: selector + owned local sources + raw measurements.

Run one scene at a time; --build installs the shared release suite first.
Product CHECKs use native evidence; missing observations are BLOCKED. 未上机。
"""
import argparse
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
SCENES=('cp1gap','fullscreen','theme','headers','feedplayer','c04chrome','precise-normal','precise-paused','precise-cutover')
from cp3_checks import validate_checks


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('scene',choices=SCENES)
    p.add_argument('--run-id',required=True)
    p.add_argument('--runs',type=int,default=5)
    p.add_argument('--build',action='store_true')
    p.add_argument('--timeout',type=int,default=900)
    args=p.parse_args()
    if not __import__('re').fullmatch(r'[A-Za-z0-9_.-]+',args.run_id) or args.runs<1:p.error('invalid run-id/runs')
    if args.scene.startswith('precise-'):
        from cp3_f3 import run
        return run(args)
    out=TOOL/'coverage_evidence'/('matrix-'+args.run_id);out.mkdir(exist_ok=True)
    stem='matrix-'+args.run_id+'-cp3-'+args.scene
    log=(out/(stem+'.commands.log')).open('w',encoding='utf-8')
    children=[];servers=[];original={};original_volume=None;records=[];harness=[];completed=False
    def command(cmd,timeout=120):
        log.write('CALL '+json.dumps(list(map(str,cmd)))+'\n');log.flush()
        r=subprocess.run(cmd,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
        text=r.stdout.decode('utf-8',errors='replace');log.write(f'RET exit={r.returncode}\n'+text+'\n');log.flush()
        if r.returncode:raise RuntimeError(f'{cmd}: exit={r.returncode}: {text[-1500:]}')
        return text
    def adb(*cmd):return command(['adb','-s',SERIAL,*cmd])
    def unlocked():
        window=adb('shell','dumpsys','window')
        if 'isKeyguardShowing=false' not in window or 'isKeyguardShowing=true' in window or 'mScreenOnFully=true' not in window:raise RuntimeError('设备锁屏/熄屏；停止，需要机主解锁')
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
                command([sys.executable,TOOL/'coverage_build.py','lib/main_cp3_suite_verify.dart','--no-daemon','--max-workers=1',
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
            hashes['sources']={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'example/lib').rglob('*cp1*.dart')}
            (out/(stem+'.build.json')).write_text(json.dumps(hashes),encoding='utf-8')
        for direction in ('reverse','forward'):
            original[direction]=adb(direction,'--list')
        def mapping(direction,port):adb(direction,f'tcp:{port}',f'tcp:{port}')
        for port in (18082,18190,18194):mapping('reverse',port)
        mapping('forward',18083)
        fixtures=out/(stem+'-sources');fixtures.mkdir(exist_ok=True)
        # All media fixtures live under the established verify_sources location.
        fixture_info={}
        for name,freq in [('a',440),('b',550)]:
            target=fixtures/(name+'.mp4')
            command(['ffmpeg','-v','error','-y','-f','lavfi','-i','testsrc2=size=640x360:rate=25',
              '-f','lavfi','-i',f'sine=frequency={freq}','-t','120','-c:v','libx264','-preset','ultrafast',
              '-c:a','aac','-movflags','+faststart','-threads','1','-g','25','-pix_fmt','yuv420p',target])
            fixture_info[name]=json.loads(command(['ffprobe','-v','error','-show_entries','format=format_name:stream=codec_name','-of','json',target]))
        (out/(stem+'.fixtures.json')).write_text(json.dumps(fixture_info,indent=2),encoding='utf-8')
        class Media(RangeHandler):
            root=str(fixtures)
            def do_GET(self):
                return super().do_GET()
        serve(http.server.ThreadingHTTPServer(('127.0.0.1',18190),Media))
        class Selector(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200);self.end_headers();self.wfile.write(f'cp3-{args.scene}||{args.runs}'.encode())
            def log_message(self,*args):pass
        serve(http.server.ThreadingHTTPServer(('127.0.0.1',18082),Selector))
        command(['ffmpeg','-v','error','-y','-i',fixtures/'a.mp4','-c','copy',
                 '-hls_time','4','-hls_list_size','0',fixtures/'index.m3u8'])
        from referer_server import Fixture
        fixture=Fixture(fixtures)
        serve(http.server.ThreadingHTTPServer(('127.0.0.1',18194),fixture.handler()))
        unlocked();adb('shell','am','force-stop',PKG);adb('logcat','-c');adb('shell','am','start','-W','-n',ACTIVITY)
        logcat=(out/(stem+'.log')).open('w',encoding='utf-8')
        pid=adb('shell','pidof',PKG).strip()
        if not pid:raise RuntimeError('app pid unavailable')
        proc=subprocess.Popen(['adb','-s',SERIAL,'logcat','-v','threadtime','--pid='+pid],stdout=logcat,stderr=subprocess.STDOUT,
           creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        children.append((proc,logcat))
        end=time.monotonic()+args.timeout;acted=set();last_error=''
        while time.monotonic()<end:
            try:data=fetch();records=data['records'];last_error=''
            except Exception as e:last_error=str(e);time.sleep(.25);continue
            for r in records:
                if r['kind']!='HOST' or r['id'] in acted:continue
                acted.add(r['id']);unlocked()
                action=r['action'];payload={}
                if action=='back':
                    adb('shell','input','keyevent','4')
                    payload={'keyevent':4}
                elif action=='brightness-gesture':
                    rect=r['rect'];x=round(rect['x']+rect['w']*.2)
                    adb('shell','input','swipe',str(x),str(round(rect['y']+rect['h']*.8)),str(x),str(round(rect['y']+rect['h']*.2)),'600')
                elif action=='meminfo':
                    raw=adb('shell','dumpsys','meminfo',PKG)
                    (out/(stem+'.'+r['id']+'.meminfo.txt')).write_text(raw,encoding='utf-8')
                    payload={'pssKb':parse_pss(raw)}
                elif action.startswith('system-'):
                    raw={name:adb('shell',*cmd) for name,cmd in {
                      'brightness':['settings','get','system','screen_brightness'],
                      'display':['dumpsys','display'],'window':['dumpsys','window']}.items()}
                    for name,value in raw.items():
                        (out/(stem+'.'+r['id']+'.'+name+'.txt')).write_text(value,encoding='utf-8')
                    payload=parse_system(raw['brightness'],raw['display'],raw['window'])
                else: raise RuntimeError('unknown CP1 host action '+action)
                fetch('/ack?id='+urllib.parse.quote(r['id'])+'&data='+urllib.parse.quote(json.dumps(payload)))
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
                for direction,ports in [('reverse',(18082,18190,18194)),('forward',(18083,))]:
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
        if 'fixture' in locals():
            (out/(stem+'.requests.json')).write_text(json.dumps(fixture.stats(),ensure_ascii=False,indent=2),encoding='utf-8')
        for server in servers:server.shutdown();server.server_close()
        checks=[r for r in records if r['kind']=='CHECK']
        missing=validate_checks(args.scene,args.runs,checks)
        result=dict(run_id=args.run_id,group=args.scene,completed=completed,harness=harness,missing=missing,records=records,
          verdicts=[dict(case=r['id'],status=r.get('status','BLOCKED'),numbers=r.get('numbers'),reason=r.get('missing')) for r in checks])
        target=out/(stem+'.json');target.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
        print('CP3 RESULT',target,'completed',completed,'CHECK',len(checks),'harness',harness,'missing',missing,flush=True)
        for r in checks:print(json.dumps(r,ensure_ascii=False),flush=True)
        log.close()
    return 2 if harness else 1 if missing or not completed or any(c.get('status')=='FAIL' for c in checks) else 0

if __name__=='__main__':sys.exit(main())
