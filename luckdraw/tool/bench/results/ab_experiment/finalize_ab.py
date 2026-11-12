"""仅追加矩阵并拷回三处授权产物，保留真实只读门禁输出。"""

import datetime as dt
import hashlib
import json
from pathlib import Path
import shutil
import subprocess as sp

ROOT = Path(__file__).resolve().parent
PACKAGE = ROOT.parents[3]
REAL = Path(r'E:\workspaces\dart-labs\luckdraw')
DART = r'E:\sdk\flutter\bin\cache\dart-sdk\bin\dart.exe'


def write(path, text):
    """新增文本统一 LF。"""
    path.write_text(text.replace('\r\n', '\n').replace('\r', '\n'), encoding='utf-8', newline='\n')


def run(name, args):
    """有界执行轻量只读门禁，保存完整输出。"""
    process = sp.Popen(args, cwd=PACKAGE, stdout=sp.PIPE, stderr=sp.PIPE,
                       creationflags=sp.CREATE_NO_WINDOW)
    try:
        stdout, stderr = process.communicate(timeout=300)
    except sp.TimeoutExpired:
        sp.run(['taskkill.exe', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
        stdout, stderr = process.communicate(timeout=15)
    output = (stdout + stderr).decode('utf-8', errors='replace')
    write(ROOT / f'{name}.log', output)
    result = dict(command=args, exitCode=process.returncode, output=output)
    print(name, process.returncode, '\n'.join(output.strip().splitlines()[-3:]), flush=True)
    return result


def main():
    """完成报告、门禁、源哈希及三处交付校验。"""
    records = json.loads((ROOT / 'runs.json').read_text(encoding='utf-8'))
    assert sum(r['valid'] for r in records) == 9 and len(records) <= 15
    assert all(sum(r['valid'] and r['condition'] == c for r in records) == 3 for c in 'ABC')
    passed_logs = sum('All tests passed.' in (ROOT/r['directory']/'stdout.log').read_text(encoding='utf-8', errors='replace') for r in records if r['valid'])
    assert passed_logs == 9, f'Expected nine integrationDriver pass logs, got {passed_logs}'
    restored = json.loads((ROOT/'restored_settings.json').read_text(encoding='utf-8'))
    assert restored['verifiedAt'] > max(r['endedAt'] for r in records if r['valid'])
    before = json.loads((ROOT / 'source_hashes_before.json').read_text(encoding='utf-8'))
    changed = [name for name, digest in before.items()
               if hashlib.sha256((PACKAGE / name).read_bytes()).hexdigest() != digest]
    assert not changed, changed
    analysis = json.loads((ROOT / 'analysis.json').read_text(encoding='utf-8'))
    lines = ['\n## AB 真机双峰受控实验\n',
             '| ID | 需求 / 不变量 | 来源 | 用例 | 类型 | 结果 |',
             '| --- | --- | --- | --- | --- | --- |']
    for index, condition in enumerate('ABC', 1):
        group = analysis['summary'][condition]
        values = group['metrics']['Raster平均 ms']
        lines.append(f'| AB-0{index} | 条件{condition}固定Picture三轮 | AB；TEST_STRATEGY §5.3 R2-10、§7 | `tool/bench/integration_test/perf_bench_test.dart :: perf > selected device scenario` | 真机 | 已落地：3/3；Raster中位数{values["median"]:.3f}ms，高档{group["high"]}/3；见AB_REPORT |')
    lines += [
        '| AB-04 | 原值、极差、事后显示/合成/温度证据 | AB；TEST_STRATEGY §7 | `cmd: python tool/bench/results/ab_experiment/analyze_ab.py` | 工具/真机 | 已落地：9次有效；看护仍运行，A/C无可控差异；无法隔离看护效应 |',
        '| AB-05 | 结束恢复手动最低及USB常亮 | AB | `cmd: adb -s 10AE9K17UE0011S shell settings get system screen_brightness_mode`<br>`cmd: adb -s 10AE9K17UE0011S shell settings get system screen_brightness`<br>`cmd: adb -s 10AE9K17UE0011S shell settings get global stay_on_while_plugged_in` | 真机 | 已落地：实测0、1、2；见restored_settings.json |',
    ]
    delta = '\n'.join(lines) + '\n'
    write(ROOT / 'acceptance_append.md', delta)
    # 只追加同一段，不用副本的旧矩阵覆盖主会话追加记录。
    for package in (PACKAGE, REAL):
        path = package / 'test/ACCEPTANCE.md'
        if '| AB-01 |' not in path.read_text(encoding='utf-8'):
            with path.open('a', encoding='utf-8', newline='\n') as target:
                target.write(delta)
    results = {}
    results['format'] = run('format_gate', [DART, 'format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'tool'])
    results['imports'] = run('imports_gate', [DART, 'tool/check_imports.dart'])
    results['acceptance'] = run('acceptance_gate', [DART, 'tool/check_acceptance.dart'])
    results['coverageHistorical'] = run('coverage_gate_historical', [DART, 'tool/coverage.dart', '--min=100', '--lcov=coverage/PERF.lcov'])
    results['gitLog'] = run('git_log_final', ['git', '-C', r'E:\workspaces\dart-labs', 'log', '--oneline', '-2'])
    results['ownDartProcesses'] = run('process_check', ['powershell.exe', '-NoProfile', '-Command',
        "Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'dart|flutter_tester' -and $_.CommandLine -match 'ab_driver.dart|ab_experiment' } | Select-Object ProcessId,ParentProcessId,Name,CommandLine | ConvertTo-Json"])
    passed = all(results[k]['exitCode'] == 0 for k in ('format', 'imports', 'acceptance', 'coverageHistorical'))
    verification = dict(verifiedAt=dt.datetime.now(dt.timezone.utc).isoformat(),
        sourceFilesChecked=len(before), changedSourceFiles=changed, launches=len(records), validRuns=9, integrationPassLogs=passed_logs,
        unitTestsNotRun=True, analyzeNotRun=True, freshCoverageNotCollected=True,
        staticGatesPassed=passed, gates=results)
    write(ROOT / 'verification.json', json.dumps(verification, ensure_ascii=False, indent=2)+'\n')
    report = PACKAGE / 'docs/AB_REPORT.md'
    with report.open('a', encoding='utf-8', newline='\n') as target:
        target.write('\n## 本批实际门禁输出\n\n')
        target.write('不运行flutter analyze/flutter test/pub get/build；真机同名集成测试9次有效通过。\n\n')
        for key in ('format', 'imports', 'acceptance', 'coverageHistorical'):
            result = results[key]
            target.write(f'- `{ " ".join(result["command"][1:]) }`：exit={result["exitCode"]}；'+ ' / '.join(result['output'].strip().splitlines()[-2:])+'\n')
        target.write(f'\n覆盖率仅复核既有PERF.lcov，不是AB重新采集；源文件{len(before)}份哈希一致。用Dart直接执行门禁，避免dart run隐式pub副作用。\n')
        target.write('\n最终git log前两条：\n\n```text\n'+results['gitLog']['output'].strip()+'\n```\n')
    # 所有本批新建文本规范换行；不重写 lib/test/tool 其它文件。
    for path in ROOT.rglob('*'):
        if path.is_file() and path.suffix in {'.txt', '.log', '.json', '.py', '.dart', '.md'}:
            text = path.read_text(encoding='utf-8', errors='strict')
            if '\r' in text:
                write(path, text)
    shutil.copy2(report, REAL / 'docs/AB_REPORT.md')
    destination = REAL / 'tool/bench/results/ab_experiment'
    shutil.copytree(ROOT, destination, dirs_exist_ok=True)
    files = [p for p in ROOT.rglob('*') if p.is_file()]
    assert all(hashlib.sha256(p.read_bytes()).digest() == hashlib.sha256((destination/p.relative_to(ROOT)).read_bytes()).digest() for p in files)
    assert (REAL/'docs/AB_REPORT.md').read_bytes() == report.read_bytes()
    assert '| AB-05 |' in (REAL/'test/ACCEPTANCE.md').read_text(encoding='utf-8')
    print('COPY VERIFIED', len(files), 'result files;', sum(p.stat().st_size for p in files), 'bytes', flush=True)
    if not passed:
        raise SystemExit('Read-only gate failure; see logs, do not edit outside authorized paths')


if __name__ == '__main__':
    main()
