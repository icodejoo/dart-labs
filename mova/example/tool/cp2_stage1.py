"""Run CP2 in mapping-table order, reusing the single verified release APK."""
import json
import os
from datetime import datetime
from pathlib import Path
import subprocess
import sys

import run_matrix as matrix

os.environ['MOVA_MATRIX_UNLOCK_WAIT'] = '600'
os.environ['ANDROID_SDK_ROOT'] = 'E:/sdk/android'
E = matrix.TOOL/'coverage_evidence'
stage0 = json.loads((E/'cp2-stage0.json').read_text(encoding='utf-8'))
if stage0['status'] != 'PASS':
    raise RuntimeError('No successful release build; stage 1 is forbidden')
apk = Path(stage0['apk'])
order = ['adpaths','adpause','adbg','pod2','playlist3','rate','warmmute',
         'bgowner','v9','pip','liveedge','audioonly-bg','events','qoe']
counts = [40,10,20,20,5,10,15,10,5,5,5,30,5,10]
rows = []
ledger = Path(stage0['sessionEvidence'])
baseline = matrix.ROOT/'doc/plans/2026-11-03-s00e-matrix-replay-r1030.json'
matrix.read_ledger(json.loads(baseline.read_text(encoding='utf-8')))

def save():
    result = dict(stage=1, batches=rows, plannedChecks=sum(counts),
                  executedChecks=sum(r['executed'] for r in rows), apk=str(apk))
    for target in (ledger/'stage1.json', E/'cp2-stage1.json'):
        target.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    md = '# CP2 阶段 1：第二次真机跑批\n\n'
    md += '每批仅使用阶段0同一APK，以 --reuse-apk 安装并拉包核对；按映射表顺序执行，原始失败保留。\n\n'
    md += '|批次|run-id|实测/计划|PASS/FAIL/BLOCKED（含缺测）|结论|证据|\n|---|---|---:|---|---|---|\n'
    md += ''.join(f"|{r['batch']}|{r['run_id']}|{r['executed']}/{r['planned']}|{r['counts']}|{r['status']}|{r['evidence']}|\n" for r in rows)
    (matrix.ROOT/'doc/plans/2026-11-04-cp2-stage1.md').write_text(md,encoding='utf-8')

for scene, planned in zip(order, counts):
    batch = 'cp2-'+scene
    run_id = batch+'-'+datetime.now().strftime('%Y%m%d-%H%M%S')
    print('BEGIN', batch, '确认解锁亮屏并复用APK，取得正式次数的原生事件证据', flush=True)
    log = ledger/(run_id+'.console.log')
    argv = [sys.executable,'-B',str(matrix.TOOL/'run_matrix.py'),
            '--run-id',run_id,'--only',batch,'--reuse-apk',str(apk),'--baseline',str(baseline)]
    with log.open('w',encoding='utf-8') as stream:
        proc = subprocess.run(argv,cwd=matrix.ROOT,stdout=stream,stderr=subprocess.STDOUT)
    report = matrix.ROOT/'doc/plans'/f'{datetime.now():%Y-%m-%d}-matrix-run-{run_id}.json'
    data = json.loads(report.read_text(encoding='utf-8')) if report.exists() else {}
    result = data.get('batches',{}).get(batch,{})
    raw = result.get('gap_result',{})
    checks = [r for r in raw.get('records',[]) if r.get('kind')=='CHECK']
    totals = {s:sum(r.get('status')==s for r in checks) for s in ('PASS','FAIL','BLOCKED')}
    totals['BLOCKED'] += max(0,planned-len(checks))
    status = 'FAIL' if totals['FAIL'] else 'PASS' if result.get('kind')=='OK' and len(checks)==planned and totals['PASS']==planned else 'BLOCKED'
    row = dict(batch=batch,run_id=run_id,planned=planned,executed=len(checks),counts=totals,
        status=status,exit=proc.returncode,kind=result.get('kind'),harness=raw.get('harness',[]),
        missing=raw.get('missing',[]),error=result.get('error'),
        evidence=f'example/tool/coverage_evidence/matrix-{run_id}',
        rawResult=f'example/tool/coverage_evidence/matrix-{run_id}/matrix-{run_id}-{batch}.json',
        report=str(report),console=str(log))
    rows.append(row)
    save()
    print('END',batch,json.dumps(row,ensure_ascii=False),flush=True)
    if 'CP0_DEVICE_OFFLINE_15_MINUTES' in log.read_text(encoding='utf-8',errors='replace'):
        print('STOP device offline for 15 minutes',flush=True)
        break
print('STAGE1 COMPLETE',flush=True)
