"""Run authorized Android retests, journal every step and retain all native events."""
from pathlib import Path
import json,time,urllib.parse,subprocess,sys
from coverage_device import adb,unlocked,request,capture
H=Path(__file__).resolve().parent;O=H/'coverage_evidence';D=H.parents[1]/'doc/plans/2026-10-27-device-coverage-android-retest6.md'
def unlocked():
    w=adb('shell','dumpsys','window')
    if 'isKeyguardShowing=false' not in w or 'isKeyguardShowing=true' in w or 'mScreenOnFully=true' not in w:
        raise RuntimeError('STOP: keyguard or screen precondition failed; do not unlock')
    return w

def note(s):
    with D.open('a',encoding='utf-8') as f:f.write('\n- '+s+'\n')
    print(s,flush=True)
def call(name,group='video',**args):
    unlocked();note('开始 '+name+'：'+str({'group':group,**args})+'；保留真实事件、原生读回及画面，以对应判据核验。')
    data=request('/run?'+urllib.parse.urlencode({'group':group,**args}));end=time.monotonic()+1800;lastguard=0;lastcount=-1
    while data['status']=='running':
        if time.monotonic()>end:raise TimeoutError(name)
        if time.monotonic()-lastguard>8:unlocked();lastguard=time.monotonic()
        (O/(name+'-inflight.json')).write_text(json.dumps(data,ensure_ascii=False),encoding='utf-8')
        n=sum(x.get('kind')=='HLS_RESULT' for x in data['records'])
        if n!=lastcount and n%10==0:print(name,'cumulative switches',n,flush=True);lastcount=n
        time.sleep(.3);data=request('/')
    unlocked();capture(name)
    start=max(i for i,r in enumerate(data['records']) if r.get('kind')=='BEGIN')
    rows=data['records'][start:];results=[r for r in rows if r.get('kind')=='HLS_RESULT'];errors=[r for r in rows if r.get('kind') in ['UNCAUGHT','SCRIPT_ERROR']]
    note(name+' 检查点：status='+data['status']+f'，本轮切档 {len(results)}，失败 {sum(not r["pass"] for r in results)}，脚本异常 {len(errors)}；证据 '+name+'.json/.png/.logcat.txt。')
    if errors or data['status']!='done':raise RuntimeError((name,errors))
    return rows
try:
    mode=sys.argv[1] if len(sys.argv)>1 else 'hls'
    if mode=='hls':
        call('rerun7-hls-paused','new',case='hls',cutover='false',paused='true',count='60')
    elif mode=='extra':
        call('rerun7-extra-prepare',action='dispose')
        call('rerun7-hls-cutover-extra','new',case='hls',cutover='true',count='20')
    elif mode=='other':
        call('rerun7-a23','new',case='retestDispose')
        call('rerun7-a12-start');call('rerun7-a12-pause',action='pause')
        for v in ['-1','0','NaN','100']:
            call('rerun7-a12-'+v,action='zoom',value=v)
        call('rerun7-a12-reset',action='zoom',value='1')
        call('rerun7-a12-end',action='dispose')
        adb('shell','am','force-stop','com.icodejoo.mova.mova_example.coverage');unlocked()
        adb('shell','am','start','-n','com.icodejoo.mova.mova_example.coverage/com.icodejoo.mova.mova_example.MainActivity')
        for _ in range(80):
            try:request('/');break
            except Exception:time.sleep(.25)
        call('rerun7-mini-pip-repro-start');call('rerun7-mini-pip-repro-show',action='miniHost')
        call('rerun7-mini-pip-repro-show-info',action='miniInfo')
        call('rerun7-mini-pip-repro-enter',action='pip')
        call('rerun7-mini-pip-repro-holding',action='miniInfo')
        unlocked();note('开始 PiP 展开：通过原生 am start 恢复同一Activity，检查展开后 controller api 与可视小窗。')
        adb('shell','am','start','-n','com.icodejoo.mova.mova_example.coverage/com.icodejoo.mova.mova_example.MainActivity')
        call('rerun7-mini-pip-repro-expanded',action='miniInfo')
except Exception as e:
    note('停止检查点：'+repr(e)+'；若为锁屏立即停止，不解锁、不继续交互。')
    raise
