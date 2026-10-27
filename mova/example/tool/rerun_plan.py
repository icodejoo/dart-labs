"""Run existing coverage batches serially, checkpointing before and after each batch."""
from pathlib import Path
import subprocess,sys,json,time
from coverage_record import update
import coverage_record
H=Path(__file__).resolve().parent
O=H/'coverage_evidence'
coverage_record.RESULT=H.parents[1]/'doc/plans/2026-10-27-device-coverage-rerun.md'
jobs=[
 ('api-launch',['coverage_suite_device.py','api','--name','rerun-api-launch','--timeout','60']),
 ('api',['rerun_batch.py','coverage_api_batches.py']),
 ('followups',['rerun_batch.py','coverage_final_batches.py']),
 ('hls-native',['rerun_batch.py','coverage_hls_final.py']),
 ('he-firstframe',['coverage_suite_device.py','he','--only','V1,V2,V3,V4','--runs','3','--timeout','900','--name','rerun-he-firstframe']),
 ('he-recovery',['coverage_suite_device.py','he','--only','V5,V6,V7,V8,V9,V10,V11','--runs','3','--timeout','1200','--name','rerun-he-recovery']),
 ('keepalive-core',['coverage_suite_device.py','keepAlive','--only','S1,S2,S3,S6,S13,S17','--runs','3','--timeout','1200','--name','rerun-keepalive-core']),
 ('existing-pages',['rerun_batch.py','coverage_followup_batches.py']),
 ('widgets',['rerun_batch.py','coverage_widgets_ui.py']),
 ('ui',['rerun_batch.py','coverage_ui.py']),
 ('gesture-pip',['rerun_batch.py','coverage_ui_final.py']),
 ('interactive',['rerun_batch.py','coverage_interactive.py']),
 ('visual',['rerun_batch.py','coverage_visual_final.py']),
 ('transition',['rerun_batch.py','coverage_transition_final.py']),
]
for name,args in jobs:
    update('开始 '+name,[],['- 复用现有验证器，检查真实事件/状态/原生读回；命令：`python example/tool/'+' '.join(args)+'`。完成后仅按实际证据回填编号。'])
    print('BEGIN',name,flush=True)
    with (O/('rerun-plan-'+name+'.log')).open('w',encoding='utf-8') as log:
        p=subprocess.run([sys.executable,str(H/args[0]),*args[1:]],cwd=H.parents[1],stdout=log,stderr=subprocess.STDOUT)
    update('结束 '+name,[],[f'- exit={p.returncode}；驱动输出 `example/tool/coverage_evidence/rerun-plan-{name}.log`；原始结果均用 rerun- 前缀。异常/超时不得推断为 PASS。'])
    print('END',name,p.returncode,flush=True)
print('RERUN_PLAN_DONE',flush=True)
