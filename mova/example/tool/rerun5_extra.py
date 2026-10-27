"""Run authorized Android retests, journal every step and retain all native events."""
from pathlib import Path
import json,time,urllib.parse,subprocess,sys
from coverage_device import adb,unlocked,request,capture
H=Path(__file__).resolve().parent;O=H/'coverage_evidence';D=H.parents[1]/'doc/plans/2026-10-27-device-coverage-android-retest4.md'
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
if __name__=='__main__':
    mode=sys.argv[1];count=sys.argv[2];suffix=sys.argv[3] if len(sys.argv)>3 else 'extra'
    assert mode in ['cutover','normal','paused']
    args={'count':count}
    if mode=='cutover':args['cutover']='true'
    if mode=='paused':args['paused']='true'
    call('rerun5-hls-'+mode+'-'+suffix,'new',case='hls',**args)
