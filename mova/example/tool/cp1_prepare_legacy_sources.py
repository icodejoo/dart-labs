"""Generate the legacy fixture through its existing generator, without serving."""
import hashlib
import json
from pathlib import Path
import runpy
import sys

tool=Path(__file__).resolve().parent
out=tool/'coverage_sources';out.mkdir(exist_ok=True)
sys.argv=[str(tool/'verify_sources/live_server.py'),'18080',str(out/'cp1-generation.log'),str(out/'stall.mp4')]
scope=runpy.run_path(sys.argv[0],run_name='cp1_fixture_generation')
scope['ensure_media'](str(out/'stall.mp4'),440,40)
scope['ensure_media'](str(out/'ad.mp4'),880,20)
result={p.name:dict(bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
    for p in [out/'stall.mp4',out/'ad.mp4']}
(tool/'coverage_evidence/cp1-legacy-fixtures.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result),flush=True)
