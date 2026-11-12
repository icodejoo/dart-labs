"""B6：固定顺序交错基准，不修改基准场景或门槛。"""
import json
from pathlib import Path
import sys
import argparse

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/reports/pipeline-b6-evidence'

def main():
    """采集三轮干净配对，污染时整对重跑。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--set', type=int, default=1)
    parser.add_argument('--out', type=Path, default=OUT)
    parser.add_argument('--high-priority', action='store_true')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    from dioman_bench_load import DiomanBenchGate, benchmark_command
    prefix = 'bench' if args.set == 1 else f'bench-set-{args.set}'
    if list(args.out.glob(f'{prefix}-*.json')):
        raise FileExistsError('本组已有记录，请使用新的 --out 或 --set，避免覆盖旧轮次')
    gate = DiomanBenchGate(ROOT / 'coverage/r4b-raw' / args.out.name / prefix, args.high_priority)
    data = gate.pairs(prefix, {
        'legacy': [sys.executable, 'tool/bench_legacy.py'],
        'pipeline': benchmark_command('benchmark/pipeline.dart'),
    })
    for label, rounds in data.items():
        for index, result in enumerate(rounds, 1):
            (args.out / f'{prefix}-{index}-{label}.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    (args.out / f'{prefix}-load-audit.json').write_text(json.dumps(gate.records, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
