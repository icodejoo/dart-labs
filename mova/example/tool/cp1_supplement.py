"""CP1 supplemental Android runs using the already installed shared APK."""
import argparse
import functools
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from types import SimpleNamespace
import urllib.parse
import urllib.request
import run_matrix as matrix
import cp0_android_extra as extra


def keepalive(run_id):
    manifest=json.loads(matrix.MANIFEST.read_text(encoding='utf-8'))
    manifest['ports']=[18080,18082,18083]
    d=matrix.Driver(SimpleNamespace(run_id=run_id),manifest)
    try:
        d.preflight()
        source=d.out/'sources';source.mkdir()
        shutil.copyfile(matrix.TOOL/'coverage_sources/stall.mp4',source/'stall.mp4')
        stream=(d.out/'live-source.driver.log').open('w',encoding='utf-8')
        proc=subprocess.Popen([sys.executable,'-B',str(matrix.TOOL/'verify_sources/live_server.py'),
            '18080',str(d.out/'live-source.log'),str(source/'stall.mp4')],stdout=stream,
            stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        d.children.append((proc,stream))
        import socket,time
        deadline=time.monotonic()+30
        while True:
            try:
                with socket.create_connection(('127.0.0.1',18080),timeout=.2): break
            except OSError:
                if time.monotonic()>deadline: raise RuntimeError('FLV fixture unavailable')
                time.sleep(.2)
        d.adb('reverse','tcp:18080','tcp:18080');d.mappings.append(('reverse',18080))
        d.mappings.append(('forward',18083))
        job=next(j.copy() for j in manifest['batches'] if j['id']=='keepalive-core')
        job['argv']=job['argv'].copy()
        job['argv'][job['argv'].index('--only')+1]='S1,S13'
        job['argv'][job['argv'].index('--runs')+1]='5'
        d.batch(job)
    except Exception as error:
        d.results['driver']=dict(kind='HARNESS',error=repr(error))
        d.capture_failure('keepalive-core')
    finally:
        d.cleanup()
        (d.out/'supplement-result.json').write_text(json.dumps(d.results,ensure_ascii=False,indent=2),encoding='utf-8')


def extract(run_id):
    from coverage_gap import GapDriver
    from coverage_gap_media import Handler
    manifest=json.loads(matrix.MANIFEST.read_text(encoding='utf-8'))
    manifest['ports']=[18082,18083,18084]
    d=GapDriver(SimpleNamespace(run_id=run_id),manifest)
    d.logical_run_id=run_id;d.gsm=False
    servers=[];results=[]
    try:
        d.preflight()
        extra.prepare()
        fixtures=d.out/'sources';fixtures.mkdir()
        shutil.copyfile(extra.FIX/'long.mp4',fixtures/'vod.mp4')
        extra.Selector.scene='rerun6'
        servers.append(extra.serve(18082,extra.Selector))
        servers.append(extra.serve(18084,functools.partial(Handler,directory=str(fixtures))))
        for port in (18082,18084):
            d.adb('reverse',f'tcp:{port}',f'tcp:{port}');d.mappings.append(('reverse',port))
        d.adb('forward','tcp:18083','tcp:18083');d.mappings.append(('forward',18083))
        d.screen();d.adb('shell','am','force-stop',matrix.PACKAGE)
        d.adb('shell','am','start','-n',matrix.MAIN_ACTIVITY)
        d.wait(lambda:extra.fetch(18083)['status']=='idle')
        import time
        for i in range(3):
            d.screen();result=dict(run=i,status='BLOCKED')
            try:
                query=urllib.parse.urlencode(dict(group='new',case='preview',mode='extract'))
                data=extra.fetch(18083,'/run?'+query)
                end=time.monotonic()+120
                while data['status']=='running' and time.monotonic()<end:
                    time.sleep(.25);data=extra.fetch(18083)
                    (d.out/f'extract.{i}.json').write_text(json.dumps(data,ensure_ascii=False),encoding='utf-8')
                result['completed']=data['status']=='done'
                start=max((n for n,r in enumerate(data['records']) if r.get('kind')=='BEGIN'),default=0)
                rows=data['records'][start:]
                result['checks']=[r for r in rows if r.get('kind')=='CHECK']
                result['errors']=[r for r in rows if r.get('kind') in ('UNCAUGHT','SCRIPT_ERROR')]
                result['thumbs']=[r for r in rows if r.get('kind')=='THUMB']
                result['status']='FAIL' if any(r.get('pass') is False for r in result['checks']) else 'BLOCKED'
                result['reason']='B07 原生抽帧 seek 落点未由旧页导出；保留字节与缓存检查，不据图片存在判完整通过'
                for sec in (4,8,12):
                    url=f'http://127.0.0.1:18083/artifact?name=coverage-thumb-{sec}.jpg'
                    with urllib.request.urlopen(url,timeout=5) as response:
                        (d.out/f'extract.{i}.{sec}.jpg').write_bytes(response.read())
            except Exception as error:
                result['error']=repr(error)
                d.capture_failure('extract.'+str(i))
            results.append(result)
            (d.out/'extract-results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    finally:
        d.cleanup()
        for server in servers:server.shutdown();server.server_close()


def skin(run_id):
    # Reuse the CP0 native host; run the existing skin group three independent times.
    original=extra.Selector.scene
    extra.prepare()
    for i in range(3):
        extra.run_one(run_id+'-'+str(i),'skin',1,skins='default,bilibili')
    extra.Selector.scene=original


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('group',choices=['keepalive-core','extract','skin']);p.add_argument('--run-id',required=True)
    args=p.parse_args()
    {'keepalive-core':keepalive,'extract':extract,'skin':skin}[args.group](args.run_id)
