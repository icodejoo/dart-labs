"""R4b 串行任务：共享门控预算、优先级试验与旧版干净对照。"""
import json
import statistics
import subprocess
import sys
import time
import argparse

from dioman_bench_load import DiomanBenchGate, ROOT, benchmark_command

OUT = ROOT / 'docs/reports/round2-r4b-evidence'
RAW = ROOT / 'coverage/r4b-raw/campaign-vm'
LEGACY = [sys.executable, 'tool/bench_legacy.py']
PIPELINE = benchmark_command('benchmark/pipeline.dart')


def save(name, data):
    """小摘要写证据目录，完整逐轮负载仍在 coverage。"""
    dest = OUT / name
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(data, indent=2)+'\n', encoding='utf-8')


def spreads(rounds):
    """按六场景计算独立三轮吞吐极差。"""
    return [(max(r['results'][i]['opsPerSecond'] for r in rounds) /
             min(r['results'][i]['opsPerSecond'] for r in rounds)-1)*100
            for i in range(6)]


def main():
    """先完成优先级试验，再最多运行三组基线；超时留档。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-only', action='store_true')
    args = parser.parse_args()
    gate = DiomanBenchGate(RAW.parent / 'baseline-continuation' if args.baseline_only else RAW)
    deadline = ROOT / 'coverage/r4b-campaign-deadline.json'
    if deadline.exists():
        original = json.loads(deadline.read_text(encoding='utf-8'))
        gate.deadline = original['deadlineMonotonic']
    state = {'completed': [], 'stopped': None, 'startedEpoch': time.time(),
             'deadlineMonotonic': gate.deadline}
    if deadline.exists():
        state['startedEpoch'] = original['startedEpoch']
    if args.baseline_only and (OUT / 'campaign-state.json').exists():
        save('priority-campaign-state.json', json.loads((OUT / 'campaign-state.json').read_text(encoding='utf-8')))
    try:
        if not args.baseline_only:
            pilot = {}
            for high in (False, True):
                gate.high = high
                name = 'priority-high' if high else 'priority-normal'
                data = gate.pairs(name, {'A': LEGACY, 'B': LEGACY})
                save(f'{name}.json', data)
                pilot[name] = spreads(data['A'])
                state['completed'].append(name)
                print(name + ' complete', flush=True)
            gate.high = statistics.median(pilot['priority-high']) < statistics.median(pilot['priority-normal'])
            save('priority-decision.json', {'spreads': pilot, 'highPriority': gate.high})
        else:
            decision = OUT / 'priority-decision.json'
            if decision.exists():
                gate.high = json.loads(decision.read_text())['highPriority']
            else:
                save('priority-decision.json', {'highPriority': False,
                     'reason': '优先级试验未取得完整干净三轮，未证明有帮助，保持普通优先级；不把未判定当作没有帮助'})
        for group in range(1, 4):
            prefix = 'bench' if group == 1 else f'bench-set-{group}'
            data = gate.pairs(f'baseline-{group}', {'legacy': LEGACY, 'pipeline': PIPELINE})
            for label, rounds in data.items():
                for index, run in enumerate(rounds, 1):
                    save(f'baseline/{prefix}-{index}-{label}.json', run)
            save(f'baseline/{prefix}-load-audit.json',
                 [r for r in gate.records if r['name'] == f'baseline-{group}'])
            subprocess.run([sys.executable, 'tool/pipeline_b6_bench_summary.py', '--out',
                            str(OUT / 'baseline'), '--set', str(group)], cwd=ROOT, check=True)
            state['completed'].append(f'baseline-{group}')
            if all(v < 10 for rounds in data.values() for v in spreads(rounds)):
                break
    except TimeoutError as error:
        state['stopped'] = str(error)
    finally:
        save('campaign-state.json', state)
        # 分文件保持每个证据小于约五十 KB。
        for name in {r['name'] for r in gate.records}:
            save(f'load/{name}.json', [r for r in gate.records if r['name'] == name])


if __name__ == '__main__':
    main()
