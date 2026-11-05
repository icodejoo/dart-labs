"""Resume incomplete CP2 batches, checkpointing and committing each result."""
import argparse
from collections import Counter
from datetime import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import time

import run_matrix as matrix

E = matrix.TOOL / 'coverage_evidence'
STATE = E / 'cp2-resume.json'
COUNTS = dict(zip(['adpaths', 'adpause', 'adbg', 'pod2', 'playlist3', 'rate',
                  'warmmute', 'bgowner', 'v9', 'pip', 'liveedge', 'audioonly-bg',
                  'events', 'qoe'], [40, 10, 20, 20, 5, 10, 15, 10, 5, 5, 5, 30, 5, 10]))


def command(argv, **kwargs):
    return subprocess.run(list(map(str, argv)), cwd=matrix.ROOT, check=True, **kwargs)


def save(state):
    STATE.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding='utf-8')
    target = matrix.ROOT / 'doc/plans/2026-11-04-cp2-resume.json'
    target.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding='utf-8')
    text = '# CP2 续跑台账\n\n原始阶段1结果保留；仅续跑缺失或不完整批次。每批前读取 FreePhysicalMemory，低于2 GiB等待。全程复用阶段0 APK。\n\n'
    text += '|批次|run-id|实测/计划|PASS/FAIL/BLOCKED|结论|\n|---|---|---:|---|---|\n'
    for row in state['attempts']:
        text += f"|{row['batch']}|{row['run_id']}|{row['executed']}/{row['planned']}|{row['counts']}|{row['status']}|\n"
    text += '\n已完成的 V9、PiP 不重跑。原驱动不支持按 CHECK 断点选择，不完整批次以新 run-id 整批重试；汇总按完整 CHECK ID 去重，保留全部尝试。\n'
    (target.with_suffix('.md')).write_text(text, encoding='utf-8')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('scenes', nargs='+', choices=list(COUNTS))
    args = p.parse_args()
    os.environ['MOVA_MATRIX_UNLOCK_WAIT'] = '600'
    os.environ['ANDROID_SDK_ROOT'] = 'E:/sdk/android'
    stage0 = json.loads((E / 'cp2-stage0.json').read_text(encoding='utf-8'))
    assert stage0['status'] == 'PASS'
    state = json.loads(STATE.read_text(encoding='utf-8')) if STATE.exists() else dict(apk=stage0['apk'], attempts=[])
    for scene in args.scenes:
        memory = []
        while True:
            raw = subprocess.check_output(['powershell', '-NoProfile', '-Command',
                'Get-CimInstance Win32_OperatingSystem | Select-Object FreePhysicalMemory,FreeVirtualMemory | ConvertTo-Json'], text=True)
            sample = json.loads(raw)
            sample['at'] = datetime.now().isoformat()
            memory.append(sample)
            print('MEMORY', json.dumps(sample), flush=True)
            if sample['FreePhysicalMemory'] >= 2 * 1024 * 1024:
                break
            time.sleep(30)
        batch = 'cp2-' + scene
        run_id = batch + '-resume-' + datetime.now().strftime('%Y%m%d-%H%M%S')
        console = E / (run_id + '.console.log')
        print('BEGIN', run_id, flush=True)
        with console.open('w', encoding='utf-8') as log:
            proc = subprocess.run([sys.executable, '-B', str(matrix.TOOL / 'run_matrix.py'),
                '--run-id', run_id, '--only', batch, '--reuse-apk', stage0['apk'],
                '--baseline', str(matrix.ROOT / 'doc/plans/2026-11-03-s00e-matrix-replay-r1030.json')],
                cwd=matrix.ROOT, stdout=log, stderr=subprocess.STDOUT)
        reports = list((matrix.ROOT / 'doc/plans').glob('*-matrix-run-' + run_id + '.json'))
        data = json.loads(reports[0].read_text(encoding='utf-8')) if reports else {}
        result = data.get('batches', {}).get(batch, {})
        raw_result = result.get('gap_result', {})
        checks = [r for r in raw_result.get('records', []) if r.get('kind') == 'CHECK' and r.get('id', '').startswith('CP2.' + scene + '.') and not r['id'].endswith('.harness')]
        totals = {s: sum(r.get('status') == s for r in checks) for s in ('PASS', 'FAIL', 'BLOCKED')}
        totals['BLOCKED'] += max(0, COUNTS[scene] - len(checks))
        row = dict(batch=batch, run_id=run_id, planned=COUNTS[scene], executed=len(checks), counts=totals,
            status='FAIL' if totals['FAIL'] else 'PASS' if result.get('kind') == 'OK' and totals['PASS'] == COUNTS[scene] else 'BLOCKED',
            exit=proc.returncode, kind=result.get('kind'), memory=memory,
            evidence=f'example/tool/coverage_evidence/matrix-{run_id}',
            report=str(reports[0].relative_to(matrix.ROOT)) if reports else None,
            console=str(console.relative_to(matrix.ROOT)), harness=raw_result.get('harness', []), missing=raw_result.get('missing', []))
        state['attempts'].append(row)
        save(state)
        paths = ['example/tool/cp2_resume.py', 'doc/plans/2026-11-04-cp2-resume.json', 'doc/plans/2026-11-04-cp2-resume.md']
        paths += [str(f.relative_to(matrix.ROOT)) for f in (matrix.ROOT / 'doc/plans').glob('*-matrix-run-' + run_id + '.*')]
        command(['git', 'add', '--', *paths])
        command(['git', 'commit', '-m', f'test(mova): CP2 {scene} 续跑证据', '-m', 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'])
        print('END', json.dumps(row, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
