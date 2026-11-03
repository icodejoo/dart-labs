"""R4 串行测量：复测组、改前/改后交错与 SHA256 恢复。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from dioman_bench_load import DiomanBenchGate, benchmark_command

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'docs/reports/round2-r4b-evidence'


def run(command, log):
    """大日志保留在 coverage，失败立即终止。"""
    with log.open('w', encoding='utf-8') as stream:
        subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                       check=True)


def sets(name, start, maximum):
    """按原顺序保留完整组，不挑选轮次。"""
    dest = EVIDENCE / name
    for group in range(start, maximum + 1):
        prefix = 'bench' if group == 1 else f'bench-set-{group}'
        if not (dest / f'{prefix}-3-pipeline.json').exists():
            run([sys.executable, 'tool/pipeline_b6_bench.py', '--set', str(group),
                 '--out', str(dest)], ROOT / f'coverage/r4-{name}-{group}.log')
        run([sys.executable, 'tool/pipeline_b6_bench_summary.py', '--set', str(group),
             '--out', str(dest)], ROOT / f'coverage/r4-{name}-{group}-summary.log')
        data = json.loads((dest / f'{prefix}-summary.json').read_text())
        print(f'{name} set {group} complete', flush=True)
        if all(v['stable'] for row in data.values() for v in row.values()):
            break


def paired(name, files, micro):
    """每次新 JIT 进程，变体间只替换登记文件，最终恢复 B 原字节。"""
    dest = EVIDENCE / name / ('micro' if micro else 'pipeline')
    dest.mkdir(parents=True, exist_ok=True)
    paths = [ROOT / file for file in files]
    final = {path: path.read_bytes() for path in paths}
    digests = {str(path.relative_to(ROOT)): hashlib.sha256(data).hexdigest()
               for path, data in final.items()}
    def prepare(variant):
        """仅替换已登记候选文件。"""
        for path in paths:
            snapshot = ROOT / 'coverage/r4-variants' / name / variant / path.relative_to(ROOT)
            path.write_bytes(snapshot.read_bytes())

    try:
        command = benchmark_command('benchmark/pipeline.dart')
        if micro:
            command = benchmark_command('benchmark/round2_r4_micro.dart', *micro)
        gate = DiomanBenchGate(ROOT / 'coverage/r4b-raw' / name / ('micro' if micro else 'pipeline'))
        data = gate.pairs(name, {'before': command, 'after': command}, prepare)
        for variant, rounds in data.items():
            for index, result in enumerate(rounds, 1):
                (dest / f'{index}-{variant}.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
        (dest / 'load-audit.json').write_text(json.dumps(gate.records, indent=2)+'\n', encoding='utf-8')
    finally:
        for path, content in final.items():
            path.write_bytes(content)
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digests[str(path.relative_to(ROOT))]
        (dest / 'restored.json').write_text(json.dumps(digests, indent=2)+'\n', encoding='utf-8')


def clone():
    """克隆开关三轮交错；库策略不变。"""
    dest = EVIDENCE / 'clone'
    dest.mkdir(parents=True, exist_ok=True)
    gate = DiomanBenchGate(ROOT / 'coverage/r4b-raw/clone')
    data = gate.pairs('clone', {mode: benchmark_command('benchmark/round2_r4_micro.dart', mode)
                                for mode in ('clone-off', 'clone-on')})
    for mode, rounds in data.items():
        for index, result in enumerate(rounds, 1):
            (dest / f'{index}-{mode}.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    (dest / 'load-audit.json').write_text(json.dumps(gate.records, indent=2)+'\n', encoding='utf-8')


def main():
    """选择测量任务，全部子进程串行。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['sets', 'paired', 'clone'])
    parser.add_argument('--name', default='baseline')
    parser.add_argument('--start', type=int, default=1)
    parser.add_argument('--maximum', type=int, default=3)
    parser.add_argument('--files', nargs='*', default=[])
    parser.add_argument('--micro', nargs='*', default=[])
    args = parser.parse_args()
    if args.mode == 'sets':
        sets(args.name, args.start, args.maximum)
    elif args.mode == 'paired':
        paired(args.name, args.files, args.micro)
    else:
        clone()


if __name__ == '__main__':
    main()
