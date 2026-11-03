"""Read-only local CP1 progress and host diagnostics; no device mutation."""
from pathlib import Path
from datetime import datetime
import json
import sys
import urllib.request

print(datetime.now().isoformat(), flush=True)
for name in sys.argv[1:]:
    path=Path(name)
    print(str(path), flush=True)
    if path.is_file():
        print(path.read_text(encoding='utf-8',errors='replace')[-1800:],flush=True)
    else: print('absent',flush=True)
try:
    data=json.load(urllib.request.urlopen('http://127.0.0.1:18083/',timeout=3))
    print('completed',data.get('completed'),'records',len(data.get('records',[])),flush=True)
    for i,r in enumerate(data.get('records',[])):
        if r.get('kind') in ('CHECK','ERROR','HLS_RESULT'):
            print(i,r.get('id'),r.get('kind'),r.get('status'),r.get('run'),r.get('error'),flush=True)
except Exception as error:print(repr(error),flush=True)
