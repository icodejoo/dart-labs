"""Rebuild only the completed CP3 ledger after an evidence-reader failure."""
from collections import Counter
from datetime import datetime
import json
from pathlib import Path
import subprocess

import cp3_compare
import cp3_finish_campaign as finish
import run_matrix as matrix


def main():
    root=matrix.ROOT
    summary=root/'doc/plans/2026-11-05-cp3-results.json'
    data=json.loads(summary.read_text(encoding='utf-8'))
    manifest=json.loads(matrix.MANIFEST.read_text(encoding='utf-8'))
    rows_run=[r for r in data['batches'] if r['stage']=='full']
    expected=set(manifest['aliases']['cp3-full']['batches'])
    if len(rows_run)!=len(expected) or {r['batch'] for r in rows_run}!=expected:
        raise RuntimeError('Recovery requires every frozen batch to have returned')
    run_ids={r['runId'] for r in rows_run}
    if len(run_ids)!=1:raise RuntimeError('Mixed full run IDs')
    run_id=run_ids.pop()
    evidence=matrix.TOOL/'coverage_evidence'/('matrix-'+run_id)
    results={r['batch']:dict(kind=r['kind'],exit=r['exit'],driver=r['evidence'],error=r['error']) for r in rows_run}
    # Same reducer and rule set as the original run; no observations or booleans
    # are changed. Lazy TXT reads avoid loading unrelated 5.7 GB logcat captures.
    explicit=matrix.reduce_evidence(manifest,evidence,'matrix-'+run_id+'-')
    rows=matrix.make_rows(manifest,results,explicit)
    baseline=json.loads((root/data['baseline']).read_text(encoding='utf-8'))
    raw=dict(run_id=run_id,rows=rows,counts=dict(Counter(r['status'] for r in rows)),
             comparison=matrix.compare_ledgers(rows,baseline),batches=results,
             baseline=data['baseline'],evidence=str(evidence),cp3Gate=cp3_compare.compare(baseline,dict(rows=rows)),
             recovery=dict(at=datetime.now().astimezone().isoformat(),originalError='MemoryError loading unrelated TXT captures',
                           evidenceUnchanged=True,batchMetadataSource=str(summary),deviceSamplesRerun=False))
    target=root/'doc/plans'/('2026-11-05-matrix-run-'+run_id)
    target.with_suffix('.json').write_text(json.dumps(raw,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    target.with_suffix('.md').write_text(matrix.render_summary(run_id,rows,raw['comparison'],results,data['baseline']),encoding='utf-8')
    data['stages'].append(dict(stage='full',exit=1,rawReport=str(target.with_suffix('.json').relative_to(root)),offlineLedgerRecovery=True))
    data['comparison']=raw['cp3Gate']
    data['ledgerCounts']=raw['counts']
    data['ledger']=[dict(id=r['id'],status=r['status']) for r in rows]
    data['complete']=True
    data['stopReason']='67/67 frozen full batches returned; ledger MemoryError recovered offline, original FAIL/BLOCKED retained.'
    data['deviations'].append('全量设备批次完成后，归并器预读约5.7GB TXT触发MemoryError；改为TXT路径索引/按规则读取，64项回归验证后从同一原始证据与规则离线重建ledger，未重跑手机样本。')
    finish.save(data)
    finish.checks(data,'full-after-ledger-recovery')
    markdown=summary.with_suffix('.md')
    with markdown.open('a',encoding='utf-8') as stream:
        stream.write('\n\n全量67/67已返回；归并内存错误已离线恢复，原始证据不变。ledger统计：'+str(raw['counts'])+'；比较：'+json.dumps(raw['cp3Gate'],ensure_ascii=False)+'。\n')
    paths=['example/tool/matrix_evidence.py','example/tool/test_run_matrix.py','example/tool/cp3_recover_ledger.py',
           str(summary.relative_to(root)),str(markdown.relative_to(root))]
    subprocess.run(['git','add','--',*paths],cwd=root,check=True)
    subprocess.run(['git','diff','--cached','--check'],cwd=root,check=True)
    subprocess.run(['git','-c','maintenance.auto=false','-c','gc.auto=0','commit','-m',
                    'test(mova): recover CP3 full ledger with lazy evidence reads\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'],cwd=root,check=True)
    print('RECOVERED',raw['counts'],raw['cp3Gate'],flush=True)


if __name__=='__main__':main()
