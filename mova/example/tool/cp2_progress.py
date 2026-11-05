"""Read-only compact CP2 progress; never infer verdicts from elapsed time."""
import json
from pathlib import Path
import urllib.request
from collections import Counter

evidence = Path(__file__).parent/'coverage_evidence'
console = evidence/'cp2-resume.console.log'
if not console.exists():
    console = evidence/'cp2-retry2-stage1.console.log'
if console.exists():
    lines = console.read_text(encoding='utf-8',errors='replace').splitlines()
    print('\n'.join(line[:500] for line in lines[-2:]))
try:
    with urllib.request.urlopen('http://127.0.0.1:18083/',timeout=5) as response:
        data = json.load(response)
    records = data.get('records',[])
    checks = [r for r in records if r.get('kind')=='CHECK']
    print('LIVE',json.dumps(dict(completed=data.get('completed'),records=len(records),
        checks=dict(Counter(r.get('status') for r in checks))),ensure_ascii=False))
    for row in [r for r in records if r.get('kind') in ('CHECK','ERROR','BEGIN','HOST')][-3:]:
        print(json.dumps({k:v for k,v in row.items() if k not in ('numbers','state','stack')},ensure_ascii=False)[:600])
except Exception as error:
    print('LIVE unavailable:',error)
