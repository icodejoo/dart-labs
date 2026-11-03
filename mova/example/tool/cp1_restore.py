"""Restore only CP1-owned device changes, verify original values and installed APK."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
from cp0_device_guard import wait_online

ROOT=Path(__file__).resolve().parents[2]
E=ROOT/'example/tool/coverage_evidence'
stage0=json.loads((E/'cp1-stage0.json').read_text(encoding='utf-8'))
original=json.loads((Path(stage0['evidence'])/(stage0['run_id'].replace('cp1-build','matrix-cp1-build')+'-restore.json')).read_text(encoding='utf-8'))
serial='7NQBB23606003715'
commands=[]
def adb(*args):
    wait_online(serial)
    argv=['adb','-s',serial,*map(str,args)]
    r=subprocess.run(argv,capture_output=True,timeout=60,creationflags=subprocess.CREATE_NO_WINDOW)
    text=r.stdout.decode('utf-8',errors='replace')
    commands.append(dict(argv=argv,exit=r.returncode,stdout=text,stderr=r.stderr.decode('utf-8',errors='replace')))
    if r.returncode:raise RuntimeError(commands[-1])
    return text
def snapshot():
    volume=adb('shell','cmd','media_session','volume','--stream','3','--get')
    mappings={}
    for direction in ('reverse','forward'):
        mappings[direction]={}
        for line in adb(direction,'--list').splitlines():
            parts=line.split()
            if len(parts)==3 and (direction=='reverse' or parts[0]==serial):mappings[direction][parts[1]]=parts[2]
    return dict(volume=re.search(r'volume is (\d+)',volume,re.I)[1],
        power=adb('shell','settings','get','global','stay_on_while_plugged_in').strip(),mappings=mappings)
result=dict(original=original,status='FAIL')
try:
    adb('shell','am','force-stop','com.icodejoo.mova.mova_example.coverage')
    before=snapshot();result['before']=before
    if before['volume']!=original['volume']:adb('shell','cmd','media_session','volume','--stream','3','--set',original['volume'])
    if before['power']!=original['power']:
        adb('shell','settings','delete','global','stay_on_while_plugged_in') if original['power']=='null' else adb('shell','settings','put','global','stay_on_while_plugged_in',original['power'])
    owned={f'tcp:{port}' for port in (18080,18081,18082,18083,18084,18085,18086,18190,18192,18194)}
    for direction,current in before['mappings'].items():
        expected=original['mappings'][direction]
        for key in set(expected)|(set(current)&owned):
            if current.get(key)==expected.get(key):continue
            if key in expected:adb(direction,key,expected[key])
            else:adb(direction,'--remove',key)
    result['after']=snapshot()
    remote=adb('shell','pm','path','com.icodejoo.mova.mova_example.coverage').strip().removeprefix('package:')
    pulled=E/'cp1-final-device.apk';adb('pull',remote,pulled)
    actual=hashlib.sha256(pulled.read_bytes()).hexdigest()
    expected=stage0['metadata']['sha256']['signed']
    result['apk']=dict(expected=expected,actual=actual,matches=expected==actual)
    result['status']='VERIFIED' if result['after']==original and actual==expected else 'FAIL'
except Exception as error:result['error']=repr(error)
finally:
    result['commands']=commands
    evidence=E/'cp1-session-restored.json';evidence.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    target=ROOT/'doc/plans/2026-11-03-cp1-results.json'
    data=json.loads(target.read_text(encoding='utf-8'));data['restoration']=dict(status=result['status'],evidence=evidence.relative_to(ROOT).as_posix(),original=original,after=result.get('after'),apk=result.get('apk'),error=result.get('error'))
    target.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='commands'},ensure_ascii=False),flush=True)
if result['status']!='VERIFIED':raise SystemExit(1)
