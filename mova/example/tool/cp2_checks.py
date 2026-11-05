"""Run the four required host checks and retain individual exit codes."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'example/tool/coverage_evidence'/('cp2-checks-'+sys.argv[1])
OUT.mkdir(exist_ok=False)
rows = []
for script, args in [('run_matrix.py', ['--check']), ('test_run_matrix.py', []),
                     ('test_win_policy.py', []), ('test_win_job.py', [])]:
    argv = [sys.executable, '-B', str(ROOT/'example/tool'/script), *args]
    with (OUT/(script+'.log')).open('w', encoding='utf-8') as log:
        result = subprocess.run(argv, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    rows.append(dict(script=script, exit=result.returncode, evidence=str(OUT/(script+'.log'))))
(OUT/'results.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
print(json.dumps(rows), flush=True)
if any(row['exit'] for row in rows):
    raise SystemExit(1)
