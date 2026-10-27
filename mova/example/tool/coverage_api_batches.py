"""Run remaining API cases serially and checkpoint the exact command journal.

串行执行剩余API场景，每条命令后立即保存真实日志检查点。
"""
from pathlib import Path
import subprocess
import sys
from coverage_record import update, journal

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
OUT=HERE/'coverage_evidence'
jobs=[]


def new(name,case,**args):
    jobs.append((name,'new',{'case':case,**args}))


jobs += [('batch15-basic','basic',{}),('batch15-basic-cutover','basic',{'cutover':'true'}),('batch15-testing','testing',{})]
new('batch15-options','options')
new('batch15-hooks','hooks')
new('batch15-hooks-cutover','hooks',cutover='true')
for mode in ['liveDefault','liveLegacy','liveAlternatives']:
    new('batch15-recovery-'+mode,'recovery',mode=mode)
for run in range(3):
    new(f'batch15-hang-default-{run}','recovery',mode='hangDefault')
    new(f'batch15-hang-2s-{run}','recovery',mode='hang')
new('batch15-watchoff','watchoff')
new('batch15-stt','stt')
for run in range(3):
    for step in ['0','2000']:
        new(f'batch15-live-step{step}-{run}','live',step=step)
for case in ['lazy','lifecycle','feed','cutover','ads','adResume']:
    new('batch15-'+case,case)
jobs.append(('batch15-dispose120','dispose',{}))
for mode in ['vtt','extract','fallback','blocked']:
    new('batch15-preview-'+mode,'preview',mode=mode)
for mode in ['ended','stopped','failed','abandoned','stall','truncated']:
    new('batch15-qoe-'+mode,'qoe',mode=mode)
new('batch15-hls','hls')
new('batch15-abr','abr')
new('batch15-tls','tls')

for name,group,args in jobs:
    cmd=[sys.executable,str(HERE/'coverage_device.py'),group,'--name',name,'--timeout','150']
    for k,v in args.items():cmd += ['--arg',f'{k}={v}']
    print('START_CASE',name,flush=True)
    with (OUT/(name+'.driver.log')).open('w',encoding='utf-8') as log:
        result=subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
    if (OUT/(name+'.json')).exists():
        rows=journal(name)
        selected=[r for r in rows if r['kind'] not in ['EVENT']]
        reports=[r for r in rows if r['kind']=='REPORT' and r['name'] in ['sessionEnd','firstFrame','rebuffer']]
        import json
        notes=[f'- 命令 `{group} {args}`；driver exit={result.returncode}。','- 原始事件/状态/系统证据：`example/tool/coverage_evidence/'+name+'.json` 及同前缀文件。','```json',json.dumps(selected,ensure_ascii=False,indent=2),'```']
    else:
        notes=[f'- driver exit={result.returncode}，未取得命令JSON；详见 `example/tool/coverage_evidence/{name}.driver.log`，本项不得推断通过。']
    update(name+' 自动检查点',[],notes)
    print('END_CASE',name,result.returncode,flush=True)
