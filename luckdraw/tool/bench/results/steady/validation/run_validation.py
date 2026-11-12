"""串行执行STEADY本地门禁，单条五分钟上限，保存原始日志与退出码。"""
import hashlib
import json
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[5]
OUT = pathlib.Path(__file__).resolve().parent
GROUPS = {
    'steady-a': ['test/capsule', 'test/compat', 'test/core', 'test/grid'],
    'steady-b': ['test/lots', 'test/lotto', 'test/number_wheel', 'test/parity'],
    'steady-c': ['test/slot', 'test/testing', 'test/tool', 'test/wheel'],
    'steady-d': ['test/perf', 'test/example_pages_test.dart'],
}


def run(name, command, cwd=ROOT):
    """启动自有进程树，超时只结束该树，保存完整输出与退出码。"""
    started = time.monotonic()
    with (OUT / f'{name}.stdout.log').open('wb') as stdout, (OUT / f'{name}.stderr.log').open('wb') as stderr:
        process = subprocess.Popen(command, cwd=cwd, shell=True, stdout=stdout, stderr=stderr)
        try:
            code = process.wait(timeout=300)
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
            process.wait()
            code = 124
    record = {'command': command, 'cwd': str(cwd), 'exit_code': code,
              'seconds': round(time.monotonic() - started, 3)}
    (OUT / f'{name}.command.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(name, 'exit', code, 'seconds', record['seconds'], flush=True)
    if code:
        print((OUT / f'{name}.stdout.log').read_text(encoding='utf-8', errors='replace')[-4000:], flush=True)
        print((OUT / f'{name}.stderr.log').read_text(encoding='utf-8', errors='replace')[-2000:], flush=True)
        raise SystemExit(code)


def events(name):
    """读取真正的Flutter JSON事件，保留原日志，不伪造结果。"""
    parsed = []
    for line in (OUT / f'{name}.stdout.log').read_text(encoding='utf-8-sig').splitlines():
        line = line.strip()
        if line.startswith('{'):
            parsed.append(json.loads(line))
    return parsed


def merge():
    """核对四组并集和成功结束，偏移真实事件ID后合并JSON及LCOV。"""
    seen = set()
    merged = []
    summary = {}
    elapsed = 0
    for index, name in enumerate(GROUPS):
        data = events(name)
        ends = [e for e in data if e['type'] == 'done']
        assert len(ends) == 1 and ends[0]['success'] is True, name
        starts = {e['test']['id'] for e in data if e['type'] == 'testStart'}
        dones = {e['testID'] for e in data if e['type'] == 'testDone'}
        assert starts == dones, name
        outcomes = [e for e in data if e['type'] == 'testDone' and not e['hidden']]
        assert all(e['result'] == 'success' and not e['skipped'] for e in outcomes), name
        files = {pathlib.Path(e['suite']['path']).resolve() for e in data if e['type'] == 'suite'}
        assert not seen.intersection(files), name
        seen.update(files)
        summary[name] = {'passed': len(outcomes), 'skipped': 0, 'failed': 0, 'files': len(files),
                         'sha256': hashlib.sha256((OUT / f'{name}.stdout.log').read_bytes()).hexdigest()}
        def shift(value):
            """只偏移事件标识与时间，保留所有名称与成功失败字段。"""
            if isinstance(value, dict):
                return {k: v + index * 100000 if k in ['id', 'testID', 'suiteID', 'groupID'] and isinstance(v, int)
                        else [i + index * 100000 for i in v] if k == 'groupIDs'
                        else v + elapsed if k == 'time' and isinstance(v, int)
                        else shift(v) for k, v in value.items()}
            if isinstance(value, list):
                return [shift(v) for v in value]
            return value
        merged.extend(shift(e) for e in data if e['type'] != 'done')
        elapsed += ends[0]['time']
    expected = {f.resolve() for f in (ROOT / 'test').rglob('*_test.dart')}
    assert seen == expected, {'missing': sorted(map(str, expected - seen)), 'extra': sorted(map(str, seen - expected))}
    merged.append({**ends[0], 'time': elapsed})
    (OUT / 'all.tests.jsonl').write_text(''.join(json.dumps(e, ensure_ascii=False) + '\n' for e in merged), encoding='utf-8', newline='\n')
    (ROOT / 'coverage/steady.lcov').write_bytes(b''.join((ROOT / f'coverage/{name}.lcov').read_bytes() for name in GROUPS))
    summary['total'] = {'passed': sum(s['passed'] for s in summary.values()), 'files': len(seen), 'skipped': 0, 'failed': 0}
    (OUT / 'test_summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps(summary), flush=True)


def main():
    """按阶段执行，阶段间不并行启动Flutter测试或分析。"""
    phase = sys.argv[1]
    if phase == 'analyze':
        run('analyze', ['flutter', 'analyze', '--no-pub'])
        run('bench_analyze', ['flutter', 'analyze', '--no-pub'], ROOT / 'tool/bench')
        run('format', ['dart', 'format', 'lib', 'test', 'tool'])
        run('format_check', ['dart', 'format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'tool'])
    elif phase == 'tools':
        run('tools', ['flutter', 'test', 'test/tool', '--no-pub', '--concurrency=1', '--reporter=json'])
        outcomes = [e for e in events('tools') if e['type'] == 'testDone' and not e['hidden']]
        print('tools:', len(outcomes), 'passed', flush=True)
    elif phase == 'groups':
        for name, paths in GROUPS.items():
            run(name, ['flutter', 'test', '--no-pub', '--concurrency=1', '--coverage',
                       f'--coverage-path=coverage/{name}.lcov', '--reporter=json', *paths])
        merge()
    elif phase in GROUPS:
        run(phase, ['flutter', 'test', '--no-pub', '--concurrency=1', '--coverage',
                    f'--coverage-path=coverage/{phase}.lcov', '--reporter=json', *GROUPS[phase]])
        merge()
    elif phase == 'gates':
        run('coverage', ['dart', 'run', 'tool/coverage.dart', '--min=100', '--lcov=coverage/steady.lcov'])
        run('imports', ['dart', 'run', 'tool/check_imports.dart'])
        run('acceptance', ['dart', 'run', 'tool/check_acceptance.dart'])
        run('acceptance_json', ['dart', 'run', 'tool/check_acceptance.dart', '--from-json',
                                'tool/bench/results/steady/validation/all.tests.jsonl'])
        run('parity', ['dart', 'run', 'tool/parity/generate.dart', '--verify-manifest'])
        run('publish', ['dart', 'pub', 'publish', '--dry-run'])
    elif phase == 'real':
        run('real_format', ['dart', 'format', '--output=none', '--set-exit-if-changed', 'test/tool/bench_steady_test.dart', 'tool/bench/proc_cpu.dart', 'tool/bench/integration_test/bench_support.dart'])
        run('real_tools', ['flutter', 'test', 'test/tool', '--no-pub', '--concurrency=1', '--reporter=json'])
        run('real_imports', ['dart', 'run', 'tool/check_imports.dart'])
        run('real_acceptance', ['dart', 'run', 'tool/check_acceptance.dart'])
        outcomes = [e for e in events('real_tools') if e['type'] == 'testDone' and not e['hidden']]
        print('real tools:', len(outcomes), 'passed', flush=True)
    else:
        raise ValueError(phase)


if __name__ == '__main__':
    main()
