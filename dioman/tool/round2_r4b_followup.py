"""R4b 后续实验：沿用已启动任务的截止时间，不重置等待预算。"""
import hashlib
import json
import statistics
import subprocess
import sys

from dioman_bench_load import DiomanBenchGate, ROOT, dart_executable, benchmark_command
from round2_r4b_campaign import OUT, LEGACY, PIPELINE, save

DART = dart_executable()
MICRO = benchmark_command('benchmark/round2_r4_micro.dart')
PREREGISTERED = ROOT / 'docs/reports/round2-r4-evidence/preregistered.json'


def metrics(rounds):
    """按吞吐中位数选整行，并保留三轮极差。"""
    result = {}
    for index, row in enumerate(rounds[0]['results']):
        samples = [run['results'][index] for run in rounds]
        def throughput(sample):
            """微基准按操作数与时间计算吞吐。"""
            return sample.get('opsPerSecond', sample['operations'] / sample['elapsedSeconds'])
        selected = sorted(samples, key=throughput)[1]
        spread = (max(map(throughput, samples)) / min(map(throughput, samples))-1)*100
        result[row['scenario']] = {'selected': selected, 'selectedRound': samples.index(selected)+1,
                                   'spreadPercent': spread,
                                   'means': [sample['meanMicros'] for sample in samples]}
    return result


def candidate(gate, name, files, target, micro):
    """原补丁重新应用；回归先行，只有满足全部事前阈值才保留。"""
    paths = [ROOT / file for file in files]
    before = {path: path.read_bytes() for path in paths}
    decision = {'keep': False, 'target': target, 'reason': '尚未完成干净三轮'}
    save(f'{name}/threshold.json', json.loads(PREREGISTERED.read_text(encoding='utf-8')))
    try:
        subprocess.run(['git', 'apply', str(ROOT / f'docs/reports/round2-r4-evidence/{name}/candidate.patch')],
                       cwd=ROOT, check=True)
        after = {path: path.read_bytes() for path in paths}
        with (ROOT / f'coverage/r4b-{name}-regression.log').open('w', encoding='utf-8') as log:
            subprocess.run([DART, 'test', '--concurrency=1', 'test/unit/request_snapshot_test.dart'],
                           cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)

        def prepare(variant):
            """每次起跑使用同一候选的固定前后快照。"""
            for path, content in (before if variant == 'A' else after).items():
                path.write_bytes(content)

        pipeline = gate.pairs(name, {'A': PIPELINE, 'B': PIPELINE}, prepare)
        save(f'{name}/pipeline.json', pipeline)
        standard = {label: metrics(rounds) for label, rounds in pipeline.items()}
        measured = standard
        if micro:
            data = gate.pairs(name+'-micro', {'A': MICRO + micro, 'B': MICRO + micro}, prepare)
            save(f'{name}/micro.json', data)
            measured = {label: metrics(rounds) for label, rounds in data.items()}
        a = measured['A'][target]['selected']['meanMicros']
        b = measured['B'][target]['selected']['meanMicros']
        regression = {scenario: (standard['B'][scenario]['selected']['meanMicros'] /
                                 standard['A'][scenario]['selected']['meanMicros']-1)*100
                      for scenario in standard['A'] if scenario != target or micro}
        stable = all(row['spreadPercent'] < 10 for group in (standard, measured)
                     for rows in group.values() for row in rows.values())
        keep = stable and (a-b >= 2 or (a-b)/a >= .05) and all(v <= 3 for v in regression.values())
        decision = {'keep': keep, 'target': target, 'improvementMicros': a-b,
                    'improvementPercent': (a-b)/a*100, 'regressionsPercent': regression,
                    'stable': stable, 'pipeline': standard, 'targetMetrics': measured,
                    'reason': '满足全部阈值' if keep else '未满足全部事前阈值'}
    finally:
        chosen = after if decision['keep'] else before
        for path, content in chosen.items():
            path.write_bytes(content)
            assert hashlib.sha256(path.read_bytes()).digest() == hashlib.sha256(content).digest()
        decision['finalSha256'] = {str(path.relative_to(ROOT)): hashlib.sha256(content).hexdigest()
                                  for path, content in chosen.items()}
        save(f'{name}/decision.json', decision)


def main():
    """只接续已完成基线的任务；超时停止且保留污染证据。"""
    state = json.loads((OUT / 'campaign-state.json').read_text(encoding='utf-8'))
    if state['stopped']:
        raise RuntimeError('前序门控任务已停止，不重置截止时间')
    gate = DiomanBenchGate(ROOT / 'coverage/r4b-raw/followup')
    gate.deadline = state['deadlineMonotonic']
    gate.high = json.loads((OUT / 'priority-decision.json').read_text())['highPriority']
    try:
        candidate(gate, 'request-copy', ['lib/src/request.dart'], 'S3', [])
        candidate(gate, 'strict-json', ['lib/src/request.dart', 'lib/src/response.dart'], 'strict-json', ['strict-json'])
        data = gate.pairs('clone', {mode: MICRO + [mode] for mode in ('clone-off', 'clone-on')})
        save('clone/data.json', data)
        differences = [b['results'][0]['meanMicros']-a['results'][0]['meanMicros']
                       for a, b in zip(data['clone-off'], data['clone-on'])]
        save('clone/summary.json', {'differencesMicros': differences,
                                   'medianDifferenceMicros': statistics.median(differences),
                                   'metrics': {label: metrics(rounds) for label, rounds in data.items()}})
        data = gate.pairs('final', {'legacy': LEGACY, 'pipeline': PIPELINE})
        for label, rounds in data.items():
            for index, run in enumerate(rounds, 1):
                save(f'final/bench-{index}-{label}.json', run)
        save('final/bench-load-audit.json', [r for r in gate.records if r['name'] == 'final'])
        subprocess.run([sys.executable, 'tool/pipeline_b6_bench_summary.py', '--out', str(OUT / 'final')],
                       cwd=ROOT, check=True)
        state['completed'].append('followup')
    except TimeoutError as error:
        state['stopped'] = str(error)
    finally:
        save('followup-state.json', state)
        for name in {r['name'] for r in gate.records}:
            save(f'load/{name}.json', [r for r in gate.records if r['name'] == name])


if __name__ == '__main__':
    main()
