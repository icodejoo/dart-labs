"""Run one matrix batch with fixed CP1 APK and explicit tracked tool baseline."""
import contextlib
import json
import os
import sys
import run_matrix

os.environ['MOVA_MATRIX_UNLOCK_WAIT']='600'
batch,run_id=sys.argv[1:]
apk=json.loads((run_matrix.TOOL/'coverage_evidence/cp1-stage0.json').read_text(encoding='utf-8'))['apk']
log=run_matrix.TOOL/'coverage_evidence'/(run_id+'.host.log')
with log.open('w',encoding='utf-8') as stream, contextlib.redirect_stdout(stream), contextlib.redirect_stderr(stream):
    code=run_matrix.main(['--only',batch,'--run-id',run_id,'--reuse-apk',apk,
        '--baseline',str(run_matrix.ROOT/'doc/plans/2026-11-03-s00e-matrix-replay-r1030.json')])
print('BATCH_EXIT',code,'LOG',log,flush=True)
sys.exit(code)
