"""Targeted gesture, PiP and live-DVR real-device follow-ups."""
import json, subprocess, time, urllib.parse
from pathlib import Path
from coverage_device import adb,request,capture,unlocked
from coverage_record import update

out=Path(__file__).resolve().parent/'coverage_evidence'
def call(name,action='snapshot',**args):
    d=request('/run?'+urllib.parse.urlencode({'group':'video','action':action,**args}))
    end=time.monotonic()+35
    while d['status']=='running' and time.monotonic()<end:
        time.sleep(.1);d=request('/')
    capture(name)
    row=next((r for r in reversed(d['records']) if r['kind']=='VIDEO'),{})
    print(name,d['status'],json.dumps(row.get('state'),ensure_ascii=False),flush=True)
    return row.get('state',{})
unlocked()
# Drop the paused HLS view left by the prior measurement, then create clean config.
call('batch18-clean-dispose','dispose')
call('batch18-normal-start',style='custom')
call('batch18-controls','controls',value='normal');time.sleep(1.2);call('batch18-autohide')
call('batch18-seek5','seek',value='5000');call('batch18-pause','pause')
adb('shell','input','tap','780','1200');adb('shell','input','tap','780','1200')
call('batch18-doubletap-seek')
call('batch18-seek2','seek',value='2000');call('batch18-play','play')
proc=subprocess.Popen(['adb','-s','7NQBB23606003715','shell','input','swipe','540','1200','540','1200','1800'])
time.sleep(.8);call('batch18-longpress-during');proc.wait();call('batch18-longpress-after')
call('batch18-mini','mini',value='true');call('batch18-pip-enter','pip')
time.sleep(1);capture('batch18-pip-visible')
adb('shell','am','start','-n','com.icodejoo.mova.mova_example.coverage/com.icodejoo.mova.mova_example.MainActivity')
time.sleep(1);call('batch18-pip-expanded')
call('batch18-pip-enter2','pip');time.sleep(.5)
adb('shell','input','tap','870','1900')
adb('shell','uiautomator','dump','/sdcard/coverage-pip.xml')
(out/'batch18-pip-ui.xml').write_text(adb('shell','cat','/sdcard/coverage-pip.xml'),encoding='utf-8')
capture('batch18-pip-controls')
update('批次18 PiP与手势第一阶段',[],['- batch18-normal/autohide/doubletap-seek/longpress-*保存真实注入后状态与截图；默认双击seek判据已纠正。','- batch18-pip-*保存进入、展开及第二次进入的原生activity状态；X关闭需根据实际系统控件定位后补测。'])
