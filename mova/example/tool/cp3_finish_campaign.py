"""Wait for the owned campaign, restore its device state, compare and commit."""
import ctypes
from ctypes import wintypes
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import traceback

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / 'example/tool'
SUMMARY = ROOT / 'doc/plans/2026-11-05-cp3-results'
OUT = TOOL / 'coverage_evidence/cp3-finalization'
OUT.mkdir(exist_ok=True)
DONE = OUT / 'final.json'
SERIAL = '7NQBB23606003715'


def run(argv, log, timeout=180):
    with (OUT / log).open('wb') as stream:
        result = subprocess.run(list(map(str, argv)), cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                                timeout=timeout, creationflags=subprocess.CREATE_NO_WINDOW)
    return result.returncode


def save(data):
    Path(str(SUMMARY) + '.json').write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def checks(data, label):
    commands = [[sys.executable, '-B', TOOL / 'run_matrix.py', '--check']]
    commands += [[sys.executable, '-B', '-m', 'unittest', 'discover', '-s', TOOL, '-p', name]
                 for name in ('test_run_matrix.py', 'test_win_policy.py', 'test_win_job.py')]
    rows = []
    for index, cmd in enumerate(commands):
        log = label + f'-{index}.log'
        rows.append(dict(command=' '.join(map(str, cmd)), exit=run(cmd, log), log=str((OUT / log).relative_to(ROOT))))
    data['checks'].append(dict(label=label, results=rows))
    save(data)
    if any(r['exit'] for r in rows):
        raise RuntimeError(label + ' offline gate failed')


def wait_campaign(pid):
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel.OpenProcess(0x00100000, False, pid)
    if not handle:
        return
    try:
        while kernel.WaitForSingleObject(handle, 5000) == 258:
            if (OUT / 'cancel').exists():
                raise RuntimeError('Finalization cancelled before campaign exit')
    finally:
        kernel.CloseHandle(handle)


def adb(*args):
    return subprocess.check_output(['adb', '-s', SERIAL, *args], cwd=ROOT,
                                   creationflags=subprocess.CREATE_NO_WINDOW, timeout=90).decode('utf-8', errors='replace').strip()


def main():
    wait_campaign(34912)
    data = json.loads(Path(str(SUMMARY) + '.json').read_text(encoding='utf-8'))
    watcher = TOOL / 'coverage_evidence/cp3-source-watchdog.json'
    if watcher.exists():
        info = json.loads(watcher.read_text(encoding='utf-8'))
        work = Path(info['evidence']).resolve()
        if not work.is_relative_to(TOOL / 'coverage_evidence'):
            raise RuntimeError('Watchdog evidence path escaped this workspace')
        (work / 'stop').write_text('Campaign finished; stop owned fixture tree.\n', encoding='utf-8')
        deadline = time.monotonic() + 35
        while info.get('active') and time.monotonic() < deadline:
            time.sleep(1)
            info = json.loads(watcher.read_text(encoding='utf-8'))
        data['sourceWatchdog'] = info
        if info.get('active'):
            raise RuntimeError('Owned source watchdog did not stop')
    from cp0_device_guard import wait_online
    wait_online(SERIAL)
    first = next(r for r in data['batches'] if r['batch'] == 'cp3-fullscreen')
    original = json.loads((Path(first['evidence']).parent / ('matrix-' + first['runId'] + '-restore.json')).read_text())
    adb('shell', 'am', 'force-stop', 'com.icodejoo.mova.mova_example.coverage')
    adb('shell', 'cmd', 'media_session', 'volume', '--stream', '3', '--set', original['volume'])
    if original['power'] == 'null':
        adb('shell', 'settings', 'delete', 'global', 'stay_on_while_plugged_in')
    else:
        adb('shell', 'settings', 'put', 'global', 'stay_on_while_plugged_in', original['power'])
    owned = {18080, 18081, 18082, 18083, 18084, 18085, 18086, 18087, 18089, 18190, 18192, 18194, *range(18443, 18448)}
    actions = []
    for direction in ('reverse', 'forward'):
        current = {p[1]: p[2] for line in adb(direction, '--list').splitlines()
                   if len(p := line.split()) == 3 and (direction == 'reverse' or p[0] == SERIAL)}
        expected = original['mappings'][direction]
        for source, target in current.items():
            if source.startswith('tcp:') and int(source[4:]) in owned and source not in expected:
                adb(direction, '--remove', source)
                actions.append(dict(direction=direction, removed=source, target=target))
        for source, target in expected.items():
            if current.get(source) != target:
                adb(direction, source, target)
                actions.append(dict(direction=direction, restored=source, target=target))
    data['finalMappingRepairs'] = actions
    remote = adb('shell', 'pm', 'path', 'com.icodejoo.mova.mova_example.coverage').removeprefix('package:')
    pulled = OUT / 'final-installed.apk'
    adb('pull', remote, str(pulled))
    digest = hashlib.sha256(pulled.read_bytes()).hexdigest()
    apk_meta = OUT / 'final-apk.json'
    apk_meta.write_text(json.dumps(dict(device=SERIAL, sha256=digest, pulled=str(pulled)), indent=2), encoding='utf-8')
    data['apks'].append(dict(stage='final-device-verification', sha256=dict(device=digest), evidence=str(apk_meta.relative_to(ROOT))))
    save(data)
    checks(data, 'summary-before')
    full = next((r for r in data['stages'] if r['stage'] == 'full'), None)
    raw = ROOT / full['rawReport'] if full else None
    if raw is None or not raw.exists():
        raise RuntimeError('Full raw ledger absent; inspect original driver evidence before finalization')
    comparison = OUT / 'cp3-compare.json'
    compare_exit = run([sys.executable, '-B', TOOL / 'cp3_compare.py',
                        ROOT / data['baseline'], raw, '--output', comparison], 'cp3-compare.log')
    if compare_exit not in (0, 1):
        raise RuntimeError('cp3_compare rejected ledger input')
    data['comparison'] = json.loads(comparison.read_text(encoding='utf-8'))
    data['comparisonCommandExit'] = compare_exit
    data['comparisonEvidence'] = str(comparison.relative_to(ROOT))
    save(data)
    if run([sys.executable, '-B', TOOL / 'cp3_finalize.py'], 'summary-generation.log'):
        raise RuntimeError('Final summary generation failed; see summary-generation.log')
    data = json.loads(Path(str(SUMMARY) + '.json').read_text(encoding='utf-8'))
    checks(data, 'summary-after')
    from cp3_finalize import render
    render(data)
    pages = ROOT / 'doc/plans/2026-11-05-cp3-pages.md'
    text = pages.read_text(encoding='utf-8')
    text = text.replace('状态：离线实现完成，等待真机，未上机；此文不登记真机 PASS。仅修改 example/doc，由本人执行。',
                        '状态：真机跑批已执行，含 FAIL/BLOCKED；完成范围、次数与未完成原因见 [CP3 结果](2026-11-05-cp3-results.md)。以下“未上机/本次禁止执行”保留为原离线阶段历史记录。仅修改 example/doc，由本人执行。')
    pages.write_text(text, encoding='utf-8')
    paths = [str(Path(str(SUMMARY) + suffix).relative_to(ROOT)) for suffix in ('.md', '.json')]
    paths += [str(pages.relative_to(ROOT))]
    subprocess.run(['git', 'add', '--', *paths], cwd=ROOT, check=True, creationflags=subprocess.CREATE_NO_WINDOW)
    subprocess.run(['git', 'diff', '--cached', '--check'], cwd=ROOT, check=True, creationflags=subprocess.CREATE_NO_WINDOW)
    subprocess.run(['git', '-c', 'maintenance.auto=false', '-c', 'gc.auto=0', 'commit', '-m',
                    'test(mova): finalize CP3 Android evidence and explicit blockers\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'],
                   cwd=ROOT, check=True, creationflags=subprocess.CREATE_NO_WINDOW)
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, creationflags=subprocess.CREATE_NO_WINDOW).decode().strip()
    DONE.write_text(json.dumps(dict(success=True, at=datetime.now().astimezone().isoformat(), commit=commit,
                                    apkSha256=digest, comparison=data['comparison'], fullScope=data['fullScope'],
                                    restoration=data['restoration']), ensure_ascii=False, indent=2), encoding='utf-8')
    print('CP3 FINAL', commit, digest, flush=True)


if __name__ == '__main__':
    try:
        main()
    except BaseException as error:
        traceback.print_exc()
        DONE.write_text(json.dumps(dict(success=False, error=repr(error)), ensure_ascii=False, indent=2), encoding='utf-8')
        raise
