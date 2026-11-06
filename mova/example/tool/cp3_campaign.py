"""Blocking CP3 Android campaign with per-batch commits and compact summaries.

Run from mova. Raw matrix reports and device evidence remain local.
"""
from collections import Counter
from datetime import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import traceback
import urllib.request
import shutil

import run_matrix as matrix

ROOT = matrix.ROOT
TOOL = matrix.TOOL
BASE = ROOT / 'doc/plans/2026-10-30-matrix-run-r1030.json'
SUMMARY = ROOT / 'doc/plans/2026-11-05-cp3-results'
SUFFIX = '\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n'
START = time.monotonic()
DEADLINE = START + 6 * 3600
STAMP = datetime.now().strftime('%m%d-%H%M%S')
OUT = TOOL / 'coverage_evidence' / ('cp3-campaign-' + STAMP)
OUT.mkdir(parents=True)
state = dict(started=datetime.now().astimezone().isoformat(), head='7b73146a',
             device='STG-AL00 / 7NQBB23606003715', baseline=str(BASE.relative_to(ROOT)),
             baselineCounts={}, batches=[], stages=[], checks=[], apks=[], commits=[],
             deviations=['Use one shared coverage suite release APK for all selectors, including nested gap prepare; source scene counts unchanged.',
                         'Full alias uses dependency-safe short-first ordering, based on manifest timeout; precise runs last.'],
             complete=False, evidence=str(OUT.relative_to(ROOT)))
old_batch = matrix.Driver.batch
old_select = matrix.select_batches
old_build = matrix.Driver.build
phase = ''
apk = None


def execute(argv, path, timeout=None):
    with Path(path).open('w', encoding='utf-8') as stream:
        p = subprocess.run(list(map(str, argv)), cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                           timeout=timeout, creationflags=subprocess.CREATE_NO_WINDOW)
    return p.returncode


def checks(label):
    commands = [[sys.executable, '-B', TOOL / 'run_matrix.py', '--check']]
    commands += [[sys.executable, '-B', '-m', 'unittest', 'discover', '-s', TOOL, '-p', name]
                 for name in ('test_run_matrix.py', 'test_win_policy.py', 'test_win_job.py')]
    rows = []
    for i, cmd in enumerate(commands):
        path = OUT / (label + f'-check-{i}.log')
        code = execute(cmd, path, 180)
        rows.append(dict(command=' '.join(map(str, cmd)), exit=code, log=str(path.relative_to(ROOT))))
    state['checks'].append(dict(label=label, results=rows))
    if any(r['exit'] for r in rows):
        raise RuntimeError('Offline gate failed: ' + label)


def compact_result(name, result, run_id):
    raw = result.get('gap_result', {})
    checks_ = [r for r in raw.get('records', []) if r.get('kind') == 'CHECK']
    verdicts = raw.get('verdicts', [])
    row = dict(stage=phase, batch=name, runId=run_id, kind=result.get('kind'),
               exit=result.get('exit'), seconds=round(result.get('seconds', 0), 2),
               evidence=result.get('driver'), error=result.get('error'),
               completed=raw.get('completed'), checkCounts=dict(Counter(r.get('status', 'BLOCKED') for r in checks_)),
               verdictCounts=dict(Counter(r.get('status', 'BLOCKED') for r in verdicts)),
               harness=raw.get('harness', []), missing=raw.get('missing', []),
               failures=[dict(id=r.get('id', r.get('case')), numbers=r.get('numbers'), reason=r.get('reason'))
                         for r in checks_ or verdicts if r.get('status') == 'FAIL'])
    if name.startswith('cp3-precise-'):
        row['precise'] = checks_[0].get('numbers') if checks_ else None
        row['sourceEvidence'] = raw.get('sourceEvidence')
    row['subcheckFailures'] = result.get('subcheck_failures', [])
    return row


def write():
    # Summaries carry identifiers and aggregate measurements, never raw CHECK
    # payloads (full expected/actual event snapshots remain in local evidence).
    for row in state['batches']:
        row['failures'] = [dict(id=f.get('id'), reason=f.get('reason')) for f in row.get('failures', [])]
        for failure in row.get('subcheckFailures', []):
            check = failure.get('check', {})
            failure['check'] = {key: check[key] for key in ('id', 'kind', 'differences') if key in check}
    state['elapsedSeconds'] = round(time.monotonic() - START)
    Path(str(SUMMARY) + '.json').write_text(json.dumps(state, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    lines = ['# CP3 真机结果（2026-11-05）', '',
             f"设备：{state['device']}；起点：7b73146a；已运行 {state['elapsedSeconds'] / 3600:.2f} 小时。",
             f"完成：{state['complete']}；原因：{state.get('stopReason', '持续执行中')}。", '',
             '基线：`doc/plans/2026-10-30-matrix-run-r1030.json`，不提交原始 ledger / matrix-run 报告。', '',
             '|阶段|批次|运行器结论|CHECK PASS/FAIL/BLOCKED|秒|证据|', '|---|---|---|---|---|---|']
    for r in state['batches']:
        c = r['checkCounts']
        lines.append(f"|{r['stage']}|{r['batch']}|{r['kind']}|{c.get('PASS', 0)}/{c.get('FAIL', 0)}/{c.get('BLOCKED', 0)}|{r['seconds']}|`{r['evidence']}`|")
    lines += ['', 'APK SHA-256：']
    lines += [f"- `{a.get('sha256')}`，`{a.get('evidence')}`" for a in state['apks']]
    lines += ['', '运行器 OK 只表示批次完成；完整编号和子项结论独立，不把缺完整判据的旧编号直接升 PASS。', '',
              '## 总计划 CP3 逐行判定', '',
              '|标准|状态|依据|', '|---|---|---|']
    for r in state.get('criteria', []):
        lines.append(f"|{r['criterion']}|{r['status']}|{r['detail']}|")
    lines += ['', '## F3 数字', '', 'CP0：normal 60/60、paused 60/60、cutover 159/160（<200ms）。']
    for r in state['batches']:
        if r.get('precise'):
            lines.append(f"- {r['stage']} / {r['batch']}: `{json.dumps(r['precise'], ensure_ascii=False)}`")
    lines += ['', '## CP1 遗留与人工项', '',
              '- 终审7b/fallback：绝对 URI CHECK 不能关闭相对 URI 历史协议归因，仍需同源/内核最小复现和网络日志。',
              '- B块：restore 需要完整 OEM 亮度/display/InsetsSource；弹幕性能缺 CP0 同口径分布或批准硬线；extract 缺原生 seek 探针；底栏 VOD 补证单列，直播 DVR 仍需夹具。',
              '- Windows（C05 20 次、F3/dispose/HE V6）：BLOCKED-待安静模式，本次未运行 Windows 应用。',
              '- 人工：听音、视觉、PiP 系统交互、真实锁屏提示、GSM/真实路由切换、STT/WHEP/守卫专包；自动 CHECK 不代替这些验收。', '',
              '## FAIL / HARNESS', '']
    for r in state['batches']:
        if r['failures'] or r['kind'] != 'OK' or r.get('subcheckFailures'):
            lines.append(f"- {r['stage']} / {r['batch']}: {r['kind']}; {r['error']}; harness={r['harness']}; FAIL={json.dumps(r['failures'], ensure_ascii=False)}; 证据 `{r['evidence']}`。")
    lines += ['', '## 比较、恢复与偏差', '', f"cp3_compare：`{json.dumps(state.get('comparison'), ensure_ascii=False)}`。",
              f"恢复：`{json.dumps(state.get('restoration'), ensure_ascii=False)}`。"]
    lines += ['- ' + s for s in state['deviations']]
    lines += ['', '阶段提交：' + ', '.join(state['commits']), '',
              f"离线门禁 {len(state['checks'])} 组，详情在摘要 JSON（仅命令、退出码、日志路径）。"]
    Path(str(SUMMARY) + '.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')


def commit(label):
    write()
    paths = ['mova/example/tool/cp3_campaign.py', 'mova/example/tool/cp3_runtime.py',
             'mova/example/tool/coverage_build.py', 'mova/doc/plans/2026-11-05-cp3-results.md',
             'mova/doc/plans/2026-11-05-cp3-results.json']
    subprocess.run(['git', 'add', '--', *paths], cwd=ROOT.parent, check=True, creationflags=subprocess.CREATE_NO_WINDOW)
    subprocess.run(['git', 'diff', '--cached', '--check'], cwd=ROOT, check=True, creationflags=subprocess.CREATE_NO_WINDOW)
    subprocess.run(['git', '-c', 'maintenance.auto=false', '-c', 'gc.auto=0', 'commit', '-m', 'test(mova): ' + label + SUFFIX], cwd=ROOT, check=True, creationflags=subprocess.CREATE_NO_WINDOW)
    sha = subprocess.check_output(['git', 'rev-parse', '--short=10', 'HEAD'], cwd=ROOT, creationflags=subprocess.CREATE_NO_WINDOW).decode().strip()
    state['commits'].append(sha)
    print('CP3 COMMIT', label, sha, flush=True)


def wrapped_batch(driver, job):
    if time.monotonic() >= DEADLINE:
        raise RuntimeError('CP3_SIX_HOUR_LIMIT')
    label = phase + '-' + job['id']
    checks(label + '-before')
    bounded = dict(job, timeout=max(1, min(job['timeout'], DEADLINE - time.monotonic())))
    try:
        ensure_shared_source(driver, job)
        result = old_batch(driver, bounded)
    except Exception as error:
        driver.results.setdefault(job['id'], dict(kind='HARNESS', error=repr(error), driver=str(driver.log)))
        result = False
    state['batches'].append(compact_result(job['id'], driver.results[job['id']], driver.args.run_id))
    checks(label + '-after')
    commit('CP3 ' + phase + ' ' + job['id'] + ' device evidence')
    return result


def ensure_shared_source(driver, job):
    if phase != 'full' or 'services' not in job.get('dependencies', []):
        return
    recovery = TOOL / 'coverage_evidence/cp3-source-recovery.json'
    if recovery.exists():
        state['sourceRecovery'] = json.loads(recovery.read_text(encoding='utf-8'))
    def healthy():
        try:
            with urllib.request.urlopen('http://127.0.0.1:18080/vod.mp4', timeout=2) as response:
                return response.status == 200 and len(response.read(16)) == 16
        except OSError:
            return False
    if healthy():
        return
    watcher = TOOL / 'coverage_evidence/cp3-source-watchdog.json'
    if watcher.exists():
        info = json.loads(watcher.read_text(encoding='utf-8'))
        if info.get('active') and time.time() - info.get('at', 0) < 20:
            for _ in range(6):
                time.sleep(2)
                if healthy():
                    return
            raise RuntimeError('Owned source watchdog could not restore fixture before ' + job['id'])
    stamp = datetime.now().strftime('%H%M%S')
    work = driver.out / (driver.prefix + 'sources-restart-' + stamp)
    work.mkdir()
    shutil.copy2(TOOL / 'coverage_sources/stall.mp4', work / 'stall.mp4')
    service = next(s for s in driver.manifest['services'] if s['id'] == 'sources')
    argv = matrix.expand(service['argv'], driver.args.run_id)
    argv[argv.index('--workdir') + 1] = str(work)
    stream = (work / 'process.log').open('w', encoding='utf-8')
    child = subprocess.Popen(driver.wrapped(argv, 'sources-restart-' + stamp), cwd=ROOT, env=driver.env,
                             stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT,
                             creationflags=subprocess.CREATE_NO_WINDOW)
    driver.children.append((child, stream))
    incident = dict(at=datetime.now().astimezone().isoformat(), beforeBatch=job['id'], pid=child.pid, evidence=str(work))
    state.setdefault('sourceRestarts', []).append(incident)
    driver.note('STEP', 'Restart owned shared source before next batch: ' + json.dumps(incident))
    deadline = time.monotonic() + 30
    while not healthy():
        if child.poll() is not None or time.monotonic() >= deadline:
            raise RuntimeError('Shared source restart failed before ' + job['id'])
        time.sleep(.5)


def select(manifest, only=None, start=None, fast=False):
    jobs = old_select(manifest, only, start, fast)
    if only != 'cp3-full':
        return jobs
    return order_jobs(jobs)


def estimated_seconds(job):
    measured = {
        'cp3-theme': 15, 'cp3-cp1gap-bottom': 20, 'cp3-headers': 25,
        'cp3-feedplayer': 30, 'cp3-fullscreen': 40, 'cp3-c04chrome': 45,
        'cp1-danmaku': 60, 'cp1-bblock': 65, 'cp1-errclass': 90,
        'cp1-pool': 90, 'cp1-manageauto': 120, 'cp1-probe': 140,
        'cp1-edgepause': 175, 'cp1-recovery': 180, 'cp1-wakeswap': 240,
        'cp1-dispose120': 360, 'cp1-keepalive-s7s14': 600,
        'gap-prepare': 160, 'gap-local': 60, 'gap-focus': 20,
        'gap-network': 20, 'gap-lifecycle': 180, 'gap-random': 240,
        'gap-formats': 300, 'gap-skin': 300, 'gap-assumptions': 1200,
        'touch-mini': 180, 'touch-preview': 180,
    }
    return measured.get(job['id'], min(job['timeout'], 600))


def order_jobs(jobs):
    remaining = jobs[:]
    result = []
    while remaining:
        ready = [j for j in remaining if not (set(j['dependencies']) & {b['id'] for b in remaining})]
        job = min(ready, key=lambda j: (j['id'].startswith('cp3-precise-'), estimated_seconds(j), jobs.index(j)))
        result.append(job)
        remaining.remove(job)
    return result


def build(driver):
    driver.manifest['build']['argv'][2] = 'lib/main_coverage_suite.dart'
    return old_build(driver)


def stage(name, only):
    global phase, apk
    phase = name
    checks(name + '-before')
    run_id = 'cp3-' + name + '-' + STAMP
    argv = ['--only', only, '--run-id', run_id, '--baseline', str(BASE)]
    if apk:
        argv += ['--reuse-apk', str(apk)]
    code = matrix.main(argv)
    folder = TOOL / 'coverage_evidence' / ('matrix-' + run_id)
    metadata = folder / ('matrix-' + run_id + '-build.json')
    if metadata.exists():
        data = json.loads(metadata.read_text())
        state['apks'].append(dict(stage=name, sha256=data.get('sha256'), evidence=str(metadata.relative_to(ROOT))))
    if not apk:
        candidate = folder / ('matrix-' + run_id + '-installed.apk')
        if candidate.exists():
            apk = candidate
    report = ROOT / 'doc/plans' / (datetime.now().strftime('%Y-%m-%d') + '-matrix-run-' + run_id + '.json')
    state['stages'].append(dict(stage=name, exit=code, rawReport=str(report.relative_to(ROOT))))
    checks(name + '-after')
    if name == 'full' and report.exists():
        from cp3_compare import compare
        raw = json.loads(report.read_text(encoding='utf-8'))
        state['comparison'] = compare(json.loads(BASE.read_text(encoding='utf-8')), raw)
        state['ledgerCounts'] = raw['counts']
        state['ledger'] = [dict(id=r['id'], status=r['status']) for r in raw['rows']]
    commit('CP3 ' + name + ' stage summary and restoration')


def main():
    os.environ.update(MOVA_CP3_CAMPAIGN='1', MOVA_MATRIX_SERIAL='7NQBB23606003715',
                      ANDROID_SERIAL='7NQBB23606003715', ANDROID_SDK_ROOT='E:/sdk/android',
                      ANDROID_HOME='E:/sdk/android', PYTHONDONTWRITEBYTECODE='1')
    state['baselineCounts'] = dict(Counter(r['status'] for r in matrix.read_ledger(json.loads(BASE.read_text(encoding='utf-8'))).values()))
    matrix.Driver.batch = wrapped_batch
    matrix.Driver.build = build
    matrix.select_batches = select
    checks('campaign-before')
    # Local replacement fixture; encoding differs from legacy defaults (reported).
    source = TOOL / 'coverage_sources/stall.mp4'
    if not source.exists():
        source.parent.mkdir(exist_ok=True)
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=25',
                        '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100', '-t', '40',
                        '-c:v', 'libx264', '-preset', 'ultrafast', '-g', '25', '-pix_fmt', 'yuv420p',
                        '-c:a', 'aac', '-movflags', '+faststart', '-threads', '1', str(source)],
                       check=True, creationflags=subprocess.CREATE_NO_WINDOW)
        state['deviations'].append('Missing ignored stall.mp4 regenerated locally (40s H264/AAC testsrc2/sine); no media committed.')
    try:
        for name, only in [('fullscreen', 'cp3-fullscreen'), ('theme', 'cp3-theme'),
                           ('headers', 'cp3-headers'), ('feedplayer', 'cp3-feedplayer'),
                           ('c04chrome', 'cp3-c04chrome'), ('cp1gap', 'cp3-cp1gap'),
                           ('f3', 'cp3-f3'), ('full', 'cp3-full')]:
            if time.monotonic() >= DEADLINE:
                state['stopReason'] = 'CP3_SIX_HOUR_LIMIT'
                break
            stage(name, only)
        else:
            state['complete'] = True
            state['stopReason'] = 'All requested stages returned; failed/blocked batches retained.'
    except BaseException as error:
        state['stopReason'] = repr(error)
        traceback.print_exc()
    finally:
        checks('campaign-after')
        write()
        commit('CP3 campaign final checkpoint')


if __name__ == '__main__':
    main()
