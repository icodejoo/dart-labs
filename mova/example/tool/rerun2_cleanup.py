"""Restore device settings and stop only this retest's fixture processes."""
from pathlib import Path
import json,subprocess,hashlib,time
from coverage_device import adb,unlocked,request,capture
H=Path(__file__).resolve().parent;O=H/'coverage_evidence';D=H.parents[1]/'doc/plans/2026-10-27-device-coverage-android-retest.md'
def note(s):
    with D.open('a',encoding='utf-8') as f:f.write('\n- '+s+'\n')
    print(s,flush=True)
note('开始收尾：经现有验证页恢复媒体音量30%=6/20，USB常亮恢复7，force-stop隔离包；保留原生设置、进程与屏幕状态，再结束仅本次启动的两个源进程。')
unlocked()
d=request('/run?group=video&action=volume&value=30')
for _ in range(160):
    if d['status']!='running':break
    time.sleep(.25);d=request('/')
assert d['status']=='done'
capture('rerun2-cleanup-volume')
adb('shell','settings','put','global','stay_on_while_plugged_in','7')
adb('shell','am','force-stop','com.icodejoo.mova.mova_example.coverage')
state={}
for key,args in {'window':['shell','dumpsys','window'],'audio':['shell','dumpsys','audio'],'power':['shell','settings','get','global','stay_on_while_plugged_in'],'package':['shell','dumpsys','package','com.icodejoo.mova.mova_example.coverage'],'pid':['shell','pidof','com.icodejoo.mova.mova_example.coverage']}.items():
    p=subprocess.run(['adb','-s','7NQBB23606003715',*args],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    state[key]={'exit':p.returncode,'text':p.stdout};(O/f'rerun2-final-{key}.txt').write_text(p.stdout,encoding='utf-8')
assert state['power']['text'].strip()=='7'
assert 'streamVolume:6' in state['audio']['text']
assert not state['pid']['text'].strip()
assert 'isKeyguardShowing=false' in state['window']['text'] and 'mScreenOnFully=true' in state['window']['text']
pids=json.loads((O/'rerun2-services.json').read_text(encoding='utf-8'))
for pid in pids:
    # The exact owned PID must still be our Python HTTP fixture before termination.
    q=subprocess.check_output(['powershell','-NoProfile','-Command',f'(Get-CimInstance Win32_Process -Filter "ProcessId = {pid}").CommandLine'],text=True)
    assert 'http.server' in q and 'rerun-sources' in q,q
    subprocess.run(['taskkill','/PID',str(pid),'/T','/F'],check=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
state['ownedServicePids']=pids
state['engineSha256']=hashlib.sha256((H.parents[1]/'lib/src/core/engine.dart').read_bytes()).hexdigest()
assert state['engineSha256']==json.loads((O/'rerun2-build-manifest.json').read_text(encoding='utf-8'))['engineSha256']
(O/'rerun2-final-state.json').write_text(json.dumps(state,ensure_ascii=False,indent=2),encoding='utf-8')
note('收尾检查点：隔离包pid为空（force-stop），USB常亮=7，媒体streamVolume=6/20；仍isKeyguardShowing=false、mScreenOnFully=true；本次两个源PID已结束，engine.dart哈希与安装时一致。证据 rerun2-final-state.json / rerun2-final-*.txt。')
