"""Serialize remaining existing-page batches and checkpoint each finished run.

串行执行剩余已有验证页，并在每批结束立即落盘。
"""
from pathlib import Path
import subprocess
import sys
import time
import json
from coverage_record import update

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
out=HERE/'coverage_evidence'

jobs=[
    ('batch8-standby-native','standby','S7,S8,S8B,S14',1,700),
    ('batch9-standby-cpu-drift','standby','S4,S5,S5C',3,700),
    ('batch10-mute','mute','Q13A,Q13B,Q13C',5,700),
    ('batch11-review','review','all',3,850),
    ('batch12-pump','pump','',1,220),
    ('batch13-subtitles','subtitles','',1,90),
    ('batch14-api-launch','api','',1,40),
]

for name,group,only,runs,timeout in jobs:
    cmd=[sys.executable,str(HERE/'coverage_suite_device.py'),group,'--only',only,'--runs',str(runs),'--timeout',str(timeout),'--name',name]
    print('START_BATCH',name,flush=True)
    with (out/(name+'.driver.log')).open('w',encoding='utf-8') as log:
        result=subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
    path=out/(name+'.log')
    lines=path.read_text(encoding='utf-8',errors='replace').splitlines() if path.exists() else []
    selected=[s for s in lines if any(x in s for x in ['VERDICT','SUMMARY',' PASS',' FAIL','RFV2|','sub-text=','ALL_DONE','AUTORUN DONE'])]
    metadata=(out/(name+'.run.json')).read_text() if (out/(name+'.run.json')).exists() else 'no run metadata'
    update(name+' 自动检查点',[],['- 复用页运行；逐编号最终结论需结合下面原始断言复核。',f'- driver exit={result.returncode}；`{metadata}`。','- 日志：`example/tool/coverage_evidence/'+name+'.log`；截图/系统读回/采样同前缀。','```text',*selected,'```'])
    print('END_BATCH',name,result.returncode,flush=True)
