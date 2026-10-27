"""Finish matrix paths absent from the original main batch, retaining exact commands."""
from pathlib import Path
import subprocess,sys,json,urllib.request,socket
import coverage_record
from coverage_record import update,journal
H=Path(__file__).resolve().parent
O=H/'coverage_evidence'
coverage_record.RESULT=H.parents[1]/'doc/plans/2026-10-27-device-coverage-rerun.md'
jobs=[('playlist','playlist',{}),('edges','new',{'case':'edges'}),('failover','new',{'case':'recovery','mode':'failover'}),('ad-failure','new',{'case':'adFailure'}),('preview-probe','new',{'case':'preview','mode':'probe'}),('preview-offline','new',{'case':'preview','mode':'offline'}),('subtitles','new',{'case':'subtitles'})]
jobs += [(f'live-backoff-{run}','new',{'case':'recovery','mode':'live'}) for run in range(3)]
for tag,group,args in jobs:
    name='rerun-extra-'+tag
    cmd=[sys.executable,str(H/'coverage_device.py'),group,'--name',name,'--timeout','180']
    for k,v in args.items():cmd+=['--arg',f'{k}={v}']
    update('开始 '+name,[],['- 补齐 '+group+' '+str(args)+'，使用真实设备状态；字幕使用已修复的素材下载与先卸载后销毁路径。'])
    with (O/(name+'.driver.log')).open('w',encoding='utf-8') as log:p=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
    rows=journal(name) if (O/(name+'.json')).exists() else []
    selected=[r for r in rows if r.get('kind') not in ['EVENT','STATE','PROGRESS','PREVIEW_THUMB']]
    update('结束 '+name,[],[f'- exit={p.returncode}；原始证据 `{name}.json`。','```json',json.dumps(selected,ensure_ascii=False,indent=2),'```'])
prereqs={}
for port in [38889,38189,38190]:
    try:
        with socket.create_connection(('127.0.0.1',port),timeout=2):prereqs[str(port)]='TCP reachable (not proof of WHEP playback)'
    except Exception as e:prereqs[str(port)]=str(e)
try:
    with urllib.request.urlopen('http://127.0.0.1:38889/test/whep',timeout=3) as r:prereqs['whep_http']=r.status
except Exception as e:prereqs['whep_http']=str(e)
(O/'rerun-external-prerequisites.json').write_text(json.dumps(prereqs,indent=2),encoding='utf-8')
update('外部服务检查点',[],['- WHEP端点/端口探测见 rerun-external-prerequisites.json；UDP端口不能通过TCP结果断言可用。未提供STT真实识别模型/下载服务和按behind返回历史的服务。'])
