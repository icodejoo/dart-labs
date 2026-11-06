"""Read-only quiet batch monitor: never launches or retries test processes."""
import json
from pathlib import Path
import time

OUT=Path(__file__).resolve().parent/'coverage_evidence/cp0-windows-quiet'

def summary():
    results=[]
    for p in OUT.glob('*.result.json'):
        results.append(json.loads(p.read_text(encoding='utf-8')))
    return dict(resultCount=len(results),completed=sum(r['completed'] for r in results),
                foregroundViolations=sum(len(r.get('foregroundViolations',[])) for r in results),
                blocked=[r['item'] for r in results if r.get('status')=='BLOCKED'])

if __name__=='__main__':
    print(json.dumps(summary(),ensure_ascii=False,indent=2))
