"""Retain the event/epoch ordering behind the blocked first pod2 sample."""
import json
from pathlib import Path

root=Path(__file__).resolve().parents[2]
source=root/'example/tool/coverage_evidence/matrix-cp1-cp0-pod2-20261103-1730/matrix-cp1-cp0-pod2-20261103-1730-cp0-pod2.json'
data=json.loads(source.read_text(encoding='utf-8'))
rows=[]
for i,r in enumerate(data['records']):
    if r.get('kind') not in ('CALL','RET','EVENT','NATIVE','ERROR'):continue
    state=r.get('state',{})
    row=dict(recordIndex=i,kind=r['kind'],us=r.get('us'),event=r.get('event'),method=r.get('method'),
        path=r.get('path'),timePosMs=r.get('timePosMs'),renderEpoch=state.get('renderEpoch'),
        rendered=state.get('rendered'),payload=r.get('payload'),error=r.get('error'))
    rows.append(row)
    print(row)
target=root/'example/tool/coverage_evidence/cp1-pod2-event-epoch-audit.json'
target.write_text(json.dumps(dict(source=source.relative_to(root).as_posix(),rows=rows),ensure_ascii=False,indent=2),encoding='utf-8')
