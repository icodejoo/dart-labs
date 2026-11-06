"""Recover the completed Q13 device log after adb logcat transport loss.

This is evidence recovery from the same physical attempt, never a new run.
Original host results and volume samples remain untouched.
"""
from collections import Counter
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess

from cp2_alias import reduce_alias
import run_matrix as matrix

E = matrix.TOOL / 'coverage_evidence'
RUN = 'cp2-warmmute-resume-20261104-183712'
STEM = f'matrix-{RUN}-cp2-warmmute'
SOURCE = E / 'cp2-warmmute-adb-recovered-1842.log'
OUT = E / ('matrix-' + RUN) / (STEM + '.recovered.json')
raw = SOURCE.read_text(encoding='utf-8-sig', errors='replace')
assert '14351 14351 I flutter' in raw and 'AUTORUN DONE' in raw
assert len(re.findall(r'VERDICT Q13[ABC] (?:PASS|FAIL) ', raw)) == 15
volumes = json.loads((E / (STEM + '.volume.json')).read_text(encoding='utf-8'))
after = subprocess.check_output(['adb', '-s', '7NQBB23606003715', 'shell', 'cmd',
    'media_session', 'volume', '--stream', '3', '--get'], text=True)
volumes.append(dict(marker='after recovered device AUTORUN DONE', at=datetime.now().astimezone().isoformat(), raw=after))
checks = reduce_alias('warmmute', 5, raw, volumes)
source_results = [dict(variant=v, status=s, detail=d) for v, s, d in
                  re.findall(r'VERDICT (Q13[ABC]) (PASS|FAIL) ([^\r\n]*)', raw)]
result = dict(run_id=RUN, group='warmmute', completed=True, evidenceRecovery=True,
    recoveryReason='adb server restarted; original logcat stream ended without forwarding final markers; collector PID40432 stopped only after real device AUTORUN DONE was recovered',
    source=str(SOURCE.relative_to(matrix.ROOT)), sourceSha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    volumeSamples=volumes, volumeCount=len(volumes), expectedMinimumVolumeSamples=16,
    sourceResults=source_results,
    harness=['logcat transport lost; original host result retained',
             f'CP2 system volume proof incomplete: {len(volumes)}/16 samples; no retrospective samples invented'],
    missing=[r['id'] for r in checks if r['status']=='BLOCKED'], records=checks,
    verdicts=[dict(case=r['id'], status=r['status'], numbers=r['numbers']) for r in checks])
OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
target = matrix.ROOT / 'doc/plans/2026-11-04-cp2-warmmute-log-recovery.json'
target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
text = '# CP2 Q13 同次运行日志恢复\n\n'
text += f'原run-id `{RUN}`；设备进程14351，真实 AUTORUN DONE 于18:42:39。adb重启后从设备logcat缓冲补取全部15条原页VERDICT，不增加真机轮次。原主机结果保留，没有改写。\n\n'
text += f'原页结果：`{dict(Counter(r["status"] for r in source_results))}`。正式CP2加严结果：`{dict(Counter(r["status"] for r in checks))}`。\n\n'
text += f'系统音量只有原11条采样加恢复完成后的1条，共{len(volumes)}/16，不足门禁；所有已采值为0。不得用当前重复读数补造历史采样，故正式15条均BLOCKED，不能称5条CP2 PASS。原页Q13B/C的10条FAIL保留为夹具资源污染线索。\n\n'
text += f'原始恢复日志 `{SOURCE.relative_to(matrix.ROOT)}`；SHA-256 `{result["sourceSha256"]}`；派生记录 `{OUT.relative_to(matrix.ROOT)}`。B/C期间有SL_RESULT_MEMORY_FAILURE，旧页未移交注入内核所有权，源码修复未进入原APK。\n'
target.with_suffix('.md').write_text(text, encoding='utf-8')
print(json.dumps(dict(sourceCounts=dict(Counter(r['status'] for r in source_results)), formalCounts=dict(Counter(r['status'] for r in checks)), volumeCount=len(volumes)), ensure_ascii=False))
