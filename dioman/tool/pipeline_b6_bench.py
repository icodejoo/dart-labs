"""B6：固定顺序交错基准，不修改基准场景或门槛。"""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import argparse

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/reports/pipeline-b6-evidence'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--set', type=int, default=1)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    for round_id in range(1, 4):
        for implementation in ('legacy', 'pipeline'):
            prefix = 'bench' if args.set == 1 else f'bench-set-{args.set}'
            stem = OUT / f'{prefix}-{round_id}-{implementation}'
            command = ([sys.executable, 'tool/bench_legacy.py'] if implementation == 'legacy'
                       else [shutil.which('dart'), 'run', 'benchmark/pipeline.dart'])
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            stem.with_suffix('.json').write_text(result.stdout, encoding='utf-8')
            stem.with_suffix('.stderr.txt').write_text(result.stderr, encoding='utf-8')
            if result.returncode:
                raise RuntimeError(f'{implementation}: {result.returncode}: {result.stderr}')
            data = json.loads(result.stdout.strip())
            stem.with_suffix('.json').write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
            print(f'{round_id} {implementation} complete', flush=True)

if __name__ == '__main__':
    main()
