"""Authorized fourth round, sequential runs and immediate per-attempt commits."""
from datetime import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from types import SimpleNamespace

os.environ['ANDROID_SDK_ROOT']='E:/sdk/android'
os.environ['MOVA_MATRIX_UNLOCK_WAIT']='600'
import run_matrix as matrix
from cp2_resume import COUNTS
E=matrix.TOOL/'coverage_evidence'
TARGET=matrix.ROOT/'doc/plans/2026-11-04-cp2-r4'
STATE=E/'cp2-r4.json'
state=dict(startHead=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
           startedAt=datetime.now().astimezone().isoformat(),builds=[],attempts=[],commits=[])

def write(path,data):
    Path(path).write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')

def save():
    write(STATE,state);write(str(TARGET)+'.json',state)
    text='# CP2 第四轮（修复后）执行台账\n\n本人执行；Android release；Windows不运行。\n\nAPK SHA-256：`'+str(state.get('apkSha256'))+'`\n\n'
    text+='|批次|run-id|实测/计划|PASS/FAIL/BLOCKED|状态|\n|---|---|---:|---|---|\n'
    for r in state['attempts']:
        text+=f"|{r['batch']}|{r['run_id']}|{r['executed']}/{r['planned']}|{r['counts']}|{r['status']}|\n"
    text+='\n原始证据在各run-id的example/tool/coverage_evidence/matrix-*目录。每次尝试后立即提交；缺完成标记/缺CHECK的批次整批重试一次，历史FAIL保留。audioonly-bg仅补videoGuard.1–9，保留已PASS的21条。\n'
    Path(str(TARGET)+'.md').write_text(text,encoding='utf-8')

def commit(subject,extra=()):
    paths=['example/tool/cp2_r4.py','doc/plans/2026-11-04-cp2-r4.md','doc/plans/2026-11-04-cp2-r4.json',*extra]
    subprocess.run(['git','add','--',*paths],cwd=matrix.ROOT,check=True)
    subprocess.run(['git','commit','-m',subject,'-m','Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'],cwd=matrix.ROOT,check=True)
    result=subprocess.check_output(['git','rev-parse','HEAD'],cwd=matrix.ROOT,text=True).strip()
    state['commits'].append(dict(hash=result,subject=subject));write(STATE,state)
    return result

def memory_gate(out):
    end=time.monotonic()+2400
    while True:
        sample=json.loads(subprocess.check_output(['powershell','-NoProfile','-Command','Get-CimInstance Win32_OperatingSystem | Select-Object FreePhysicalMemory,FreeVirtualMemory | ConvertTo-Json'],text=True))
        sample['at']=datetime.now().astimezone().isoformat()
        with (out/'memory.jsonl').open('a',encoding='utf-8') as f:f.write(json.dumps(sample)+'\n')
        print('MEMORY',sample,flush=True)
        if sample['FreePhysicalMemory']>=4*1024*1024:return sample
        if time.monotonic()>=end:raise RuntimeError('FreePhysicalMemory below 4 GiB for 40 minutes')
        time.sleep(min(60,max(0,end-time.monotonic())))

def main():
    write(E/'cp2-r4-previous-results.json',json.loads((matrix.ROOT/'doc/plans/2026-11-04-cp2-results.json').read_text(encoding='utf-8')))
    manifest=json.loads(matrix.MANIFEST.read_text(encoding='utf-8'))
    manifest['build']['argv']=['{python}','{tool}/coverage_build.py','lib/main_coverage_suite.dart','--no-daemon','--max-workers=2',
        '-Dorg.gradle.jvmargs=-Xms128m -Xmx1024m -XX:MaxMetaspaceSize=384m -XX:ReservedCodeCacheSize=96m -XX:TieredStopAtLevel=1 -XX:ActiveProcessorCount=2 -XX:+UseSerialGC -XX:HeapBaseMinAddress=0x100000000',
        '-Pkotlin.compiler.execution.strategy=in-process']
    for i in range(1,4):
        run_id='cp2-build-r4-'+datetime.now().strftime('%Y%m%d-%H%M%S')
        d=matrix.Driver(SimpleNamespace(run_id=run_id),manifest)
        row=dict(run_id=run_id,status='BLOCKED',attempt=i,evidence=str(d.out))
        print('BUILD_BEGIN',run_id,flush=True)
        try:
            row['memoryBefore']=memory_gate(d.out);d.preflight();d.build()
            row.update(status='PASS',apk=str(d.out/(d.prefix+'installed.apk')),metadata=json.loads((d.out/(d.prefix+'build.json')).read_text()))
            state['apk']=row['apk'];state['apkSha256']=row['metadata']['sha256']['signed']
        except Exception as error:row['error']=repr(error)
        finally:
            d.cleanup();row['cleanup']=d.results;state['builds'].append(row);save()
        logs='\n'.join(p.read_text(encoding='utf-8',errors='replace') for p in d.out.glob('*build*.log'))
        retry=any(s.lower() in logs.lower() for s in ['Could not reserve virtual memory','paging file is too small','not enough memory','虚拟内存','页面文件'])
        print('BUILD_END',json.dumps(row,ensure_ascii=False),flush=True)
        if row['status']=='PASS' or not retry:break
    commit('test(mova): CP2 fourth-round release rebuild evidence')
    for scene in ['rate','adpaths','pod2','playlist3','bgowner','adpause','adbg','warmmute','audioonly-bg']:
        planned=9 if scene=='audioonly-bg' else COUNTS[scene]
        for attempt in range(1,3):
            run_id='cp2-'+scene+'-r4-'+datetime.now().strftime('%Y%m%d-%H%M%S')
            print('BATCH_BEGIN',run_id,flush=True)
            env=dict(os.environ)
            if scene=='audioonly-bg':env['MOVA_CP2_AUDIO_MISSING']='1'
            if state.get('apk'):
                with (E/(run_id+'.console.log')).open('w',encoding='utf-8') as stream:
                    proc=subprocess.run([sys.executable,'-B',str(matrix.TOOL/'run_matrix.py'),'--run-id',run_id,'--only','cp2-'+scene,'--reuse-apk',state['apk'],'--baseline',str(matrix.ROOT/'doc/plans/2026-11-03-s00e-matrix-replay-r1030.json')],cwd=matrix.ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT)
                code=proc.returncode
            else:code=None
            reports=list((matrix.ROOT/'doc/plans').glob('*-matrix-run-'+run_id+'.json'))
            data=json.loads(reports[0].read_text(encoding='utf-8')) if reports else {}
            result=data.get('batches',{}).get('cp2-'+scene,{})
            raw=result.get('gap_result',{})
            checks=[r for r in raw.get('records',[]) if r.get('kind')=='CHECK' and r.get('id','').startswith('CP2.'+scene+'.') and not r['id'].endswith('.harness')]
            counts={s:sum(r.get('status')==s for r in checks) for s in ('PASS','FAIL','BLOCKED')}
            counts['BLOCKED']+=max(0,planned-len(checks))
            row=dict(batch='cp2-'+scene,run_id=run_id,attempt=attempt,planned=planned,executed=len(checks),counts=counts,
                status='FAIL' if counts['FAIL'] else 'PASS' if result.get('kind')=='OK' and counts['PASS']==planned else 'BLOCKED',
                exit=code,kind=result.get('kind'),completed=raw.get('completed',False),harness=raw.get('harness',[]),missing=raw.get('missing',[]),
                evidence='example/tool/coverage_evidence/matrix-'+run_id,report=str(reports[0].relative_to(matrix.ROOT)) if reports else None)
            state['attempts'].append(row);save()
            extra=[str(p.relative_to(matrix.ROOT)) for p in (matrix.ROOT/'doc/plans').glob('*-matrix-run-'+run_id+'.*')]
            row['commit']=commit('test(mova): CP2 '+scene+' fourth-round evidence '+str(attempt),extra)
            print('BATCH_END',json.dumps(row,ensure_ascii=False),flush=True)
            if not state.get('apk') or (row['completed'] and len(checks)==planned and not row['harness'] and not row['missing']):break
    from cp2_finalize import restore
    state['restoration']=restore(state['builds'][0])
    state['finishedAt']=datetime.now().astimezone().isoformat();save()
    commit('test(mova): record CP2 fourth-round restoration')
    print('R4_DONE',json.dumps(state['restoration'],ensure_ascii=False),flush=True)

if __name__=='__main__':main()
