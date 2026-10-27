"""Print compact, current-command evidence summaries for review."""
from pathlib import Path
import json,sys
H=Path(__file__).resolve().parent
for p in sorted((H/'coverage_evidence').glob(sys.argv[1] if len(sys.argv)>1 else 'rerun-batch15-*.json')):
    try:d=json.loads(p.read_text(encoding='utf-8'))
    except Exception:continue
    if not isinstance(d,dict) or 'records' not in d:continue
    rows=d['records'];start=max((i for i,r in enumerate(rows) if r.get('kind')=='BEGIN'),default=0);rows=rows[start:]
    checks=[r for r in rows if r.get('kind')=='CHECK']
    errors=[r for r in rows if r.get('kind') in ['SCRIPT_ERROR','TIMEOUT']]
    extra=[{k:v for k,v in r.items() if k not in ['state','ms']} for r in rows if r.get('kind') in ['STREAM_FLAGS','HLS_NATIVE','RECOVERY_END','QOE_END','ABR_END','FEED_END','DISPOSE_DONE','OPEN_SYNC','BAD_OPEN_RESULT','STT_NO_ENGINE']]
    print(p.name,d['status'],'checks',len(checks),'false',[(r.get('id'),str(r.get('detail'))[:150]) for r in checks if not r['pass']],'errors',errors)
    if '--detail' in sys.argv:print(json.dumps(extra,ensure_ascii=False))
