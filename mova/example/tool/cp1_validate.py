"""Persist the three required offline checks at each CP1 stage boundary."""
from datetime import datetime
import json
from pathlib import Path
import subprocess
import sys

root=Path(__file__).resolve().parents[2]
label=sys.argv[1]
results=[]
for name,args in [('matrixCheck',['run_matrix.py','--check']),('test_run_matrix',['test_run_matrix.py']),('test_win_policy',['test_win_policy.py'])]:
    argv=[sys.executable,'-B',str(root/'example/tool'/args[0]),*args[1:]]
    result=subprocess.run(argv,cwd=root,capture_output=True,creationflags=subprocess.CREATE_NO_WINDOW)
    row=dict(name=name,argv=argv,exit=result.returncode,stdout=result.stdout.decode('utf-8',errors='replace'),stderr=result.stderr.decode('utf-8',errors='replace'))
    results.append(row)
    print(name,'exit',result.returncode,flush=True)
stamp=datetime.now().strftime('%Y%m%d-%H%M%S')
path=root/'example/tool/coverage_evidence'/f'cp1-validation-{label}-{stamp}.json'
path.write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
target=root/'doc/plans/2026-11-03-cp1-results.json'
data=json.loads(target.read_text(encoding='utf-8'))
data.setdefault('validations',[]).append(dict(stage=label,passed=all(r['exit']==0 for r in results),evidence=path.relative_to(root).as_posix()))
target.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
print(path,flush=True)
sys.exit(0 if all(r['exit']==0 for r in results) else 1)
