"""B6：固定顺序交错基准，不修改基准场景或门槛。"""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import argparse
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/reports/pipeline-b6-evidence'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--set', type=int, default=1)
    parser.add_argument('--out', type=Path, default=OUT)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    for round_id in range(1, 4):
        for implementation in ('legacy', 'pipeline'):
            prefix = 'bench' if args.set == 1 else f'bench-set-{args.set}'
            stem = args.out / f'{prefix}-{round_id}-{implementation}'
            sample_load(stem, 'before')
            command = ([sys.executable, 'tool/bench_legacy.py'] if implementation == 'legacy'
                       else [shutil.which('dart'), 'run', 'benchmark/pipeline.dart'])
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            sample_load(stem, 'after')
            stem.with_suffix('.json').write_text(result.stdout, encoding='utf-8')
            stem.with_suffix('.stderr.txt').write_text(result.stderr, encoding='utf-8')
            if result.returncode:
                raise RuntimeError(f'{implementation}: {result.returncode}: {result.stderr}')
            data = json.loads(result.stdout.strip())
            stem.with_suffix('.json').write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
            print(f'{round_id} {implementation} complete', flush=True)

def sample_load(stem, phase):
    """记录每轮前后的系统负载和进程 CPU 增量。"""
    command = r"""$ErrorActionPreference = 'Stop'
$before = @{}
Get-Process | ForEach-Object { $before[$_.Id] = $_.CPU }
$cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 3).CounterSamples.CookedValue
$processes = Get-Process | ForEach-Object {
  if ($before.ContainsKey($_.Id)) {
    [pscustomobject]@{id=$_.Id; name=$_.ProcessName; cpuSeconds=($_.CPU-$before[$_.Id]); memoryMB=[math]::Round($_.WorkingSet64/1MB,1)}
  }
} | Sort-Object cpuSeconds -Descending | Select-Object -First 8
[pscustomobject]@{time=(Get-Date -Format o); cpuPercent=@($cpu); processes=@($processes)} | ConvertTo-Json -Depth 4
"""
    result = subprocess.run(['powershell', '-NoProfile', '-Command', command],
                            capture_output=True, text=True)
    stem.with_suffix(f'.load-{phase}.json').write_text(result.stdout, encoding='utf-8')
    if result.returncode:
        raise RuntimeError(result.stderr)
    if phase == 'before':
        samples = json.loads(result.stdout)['cpuPercent']
        if samples and sum(samples) / len(samples) > 30:
            time.sleep(15)
            sample_load(stem, 'before-retry')

if __name__ == '__main__':
    main()
