"""Drive visual/gesture cases on the authorized device and checkpoint each phase.

在指定真机执行可视与手势场景，并逐阶段保存证据。
"""
import json
from pathlib import Path
import subprocess
import time
import urllib.parse
from coverage_device import adb, request, capture, unlocked
from coverage_record import update

HERE=Path(__file__).resolve().parent
OUT=HERE/'coverage_evidence'
cursor=0
checks=[]


def check(ident,ok,detail):
    checks.append({'id':ident,'pass':bool(ok),'detail':detail})
    (OUT/'batch16-checks.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2),encoding='utf-8')
    print('UI_CHECK',ident,ok,str(detail)[:350],flush=True)


def call(name,action='snapshot',group='video',shot=False,**args):
    global cursor
    params={'group':group,'action':action,**args}
    d=request('/run?'+urllib.parse.urlencode(params))
    end=time.monotonic()+40
    while d['status']=='running' and time.monotonic()<end:
        time.sleep(.1);d=request('/')
    rows=d['records'][cursor:];cursor=len(d['records'])
    data={'status':d['status'],'records':rows}
    if shot:capture(name)
    (OUT/(name+'.json')).write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    if d['status']!='done':check(name+'.runner',False,[r for r in rows if r['kind']=='SCRIPT_ERROR'])
    video=next((r for r in reversed(rows) if r['kind']=='VIDEO'),None)
    return video['state'] if video else data


def gesture(name,coords,duration=500):
    try:
        output=adb('shell','input','swipe',*map(str,coords),str(duration))
        (OUT/(name+'.adb.txt')).write_text(output,encoding='utf-8')
    except subprocess.CalledProcessError as error:
        check(name+'.injection',False,str(error));raise


def record(name):
    remote='/sdcard/'+name+'.mp4'
    proc=subprocess.Popen(['adb','-s','7NQBB23606003715','shell','screenrecord','--time-limit','5',remote],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    return proc,remote


def finish_record(name,item):
    proc,remote=item
    proc.wait(timeout=15)
    (OUT/(name+'.pull.txt')).write_text(adb('pull',remote,str(OUT/(name+'.mp4'))),encoding='utf-8')


unlocked()
for cutover in [False,True]:
    tag='batch16-cutover' if cutover else 'batch16-engine'
    call(tag+'-start',cutover=str(cutover).lower(),style='custom',shot=True)
    call(tag+'-pause','pause')
    for fit in ['contain','cover','fill']:
        st=call(tag+'-fit-'+fit,'fit',value=fit,shot=True)
        check(tag+'.fit.'+fit,st['fit']==fit,st)
    call(tag+'-sticky','controls',value='sticky');time.sleep(1.3)
    st=call(tag+'-sticky-check');check(tag+'.sticky',st['controls'],st)
    call(tag+'-autohide','controls',value='normal');time.sleep(1.3)
    st=call(tag+'-autohide-check');check(tag+'.autohide',not st['controls'],st)
    call(tag+'-volume','volume',value='50');call(tag+'-brightness','brightness',value='.5')
    before=call(tag+'-lock','lock',value='true',shot=True)
    gesture(tag+'-locked-left',(200,1600,200,1000));gesture(tag+'-locked-right',(850,1600,850,1000))
    after=call(tag+'-locked-check',shot=True)
    check(tag+'.lock',after['locked'] and after['brightness']==before['brightness'] and after['volume']==before['volume'],{'before':before,'after':after})
    call(tag+'-unlock','lock',value='false')
    adb('shell','input','tap','540','1200');adb('shell','input','tap','540','1200')
    st=call(tag+'-doubletap',shot=True);check(tag+'.doubletap',st['playing'],st)
    call(tag+'-pause-again','pause')
    gesture(tag+'-left',(200,1600,200,1000))
    st=call(tag+'-left-check',shot=True);check(tag+'.leftBrightness',st['brightness']>.5 and st['volume']==50,st)
    gesture(tag+'-right',(850,1600,850,1000))
    st=call(tag+'-right-check',shot=True);check(tag+'.rightVolume',st['volume']>50,st)
    gesture(tag+'-seek',(300,1200,450,1200))
    st=call(tag+'-seek-check',shot=True);check(tag+'.horizontalSeek',st['position']>1000,st)
    proc=subprocess.Popen(['adb','-s','7NQBB23606003715','shell','input','swipe','540','1200','540','1200','1600'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    time.sleep(.7);during=call(tag+'-longpress-during',shot=True);proc.wait(timeout=5)
    after=call(tag+'-longpress-after');check(tag+'.longpress',during['rate']>1 and after['rate']==1,{'during':during,'after':after})
    for value in ['true','false']:
        st=call(tag+'-fullscreen-'+value,'fullscreen',value=value,shot=True);check(tag+'.fullscreen.'+value,st['fullscreen']==(value=='true'),st)
    for orientation in ['landscape','portrait','auto']:
        call(tag+'-orientation-'+orientation,'orientation',value=orientation,shot=True)
    call(tag+'-declarativeFit','declarativeFit',value='cover');call(tag+'-userFit','fit',value='contain');st=call(tag+'-rebuild','rebuild')
    check(tag+'.fitRebuild',st['fit']=='contain',st)
    call(tag+'-patch','skin',value='patch',shot=True)
    call(tag+'-customSurface','surface',value='true',shot=True);call(tag+'-surface-back','surface',value='false')
    call(tag+'-bilibili','skin',value='bilibili');call(tag+'-play','play');time.sleep(3)
    call(tag+'-danmaku','controls',value='sticky',shot=True)
    call(tag+'-mini-page','miniPage',shot=True);call(tag+'-mini-info','miniInfo')
    call(tag+'-mini-host','miniHost',shot=True);call(tag+'-mini-rect','miniRect',shot=True)
    call(tag+'-mini-landscape','orientation',value='landscape',shot=True)
    call(tag+'-mini-portrait','orientation',value='portrait',shot=True)
    gesture(tag+'-mini-drag',(300,370,700,1500),600)
    call(tag+'-mini-after-drag','miniInfo',shot=True)
    call(tag+'-mini-hide','miniHide',shot=True);call(tag+'-mini-page2','miniPage');call(tag+'-mini-close','miniClose',shot=True)
    call(tag+'-minimal','skin',value='minimal',shot=True);call(tag+'-default','skin',value='default')
    call(tag+'-dispose','dispose')
    update(tag+' 可视/API阶段检查点',[],['- 逐动作原始状态/事件及截图见同前缀；控件/手势断言：','```json',json.dumps([r for r in checks if r['id'].startswith(tag)],ensure_ascii=False,indent=2),'```'])

# Equivalent warm-process audio/video windows; CPU is sampled, not inferred.
for audio in [False,True]:
    tag='batch16-audio' if audio else 'batch16-video'
    call(tag+'-start',audio=str(audio).lower())
    call(tag+'-poster','poster',value='true',shot=True);time.sleep(3)
    pid=adb('shell','pidof','com.icodejoo.mova.mova_example.coverage').strip()
    with (OUT/(tag+'.cpu.txt')).open('w',encoding='utf-8') as log:
        for sample in range(3):
            log.write('SAMPLE '+str(sample)+'\n'+adb('shell','top','-b','-n','1','-p',pid));log.flush();time.sleep(1)
    call(tag+'-playing',shot=True)
    call(tag+'-dispose','dispose')

# Default keepAlive deadline and explicit pause, using actual state transitions.
call('batch16-live-start',url='http://127.0.0.1:18080/live.flv?gop=50&audio=1',live='true',shot=True)
time.sleep(3);st=call('batch16-keepAlive-on','keepAlive',value='true',shot=True)
end=time.monotonic()+38
while st['keepAlive']=='holding' and time.monotonic()<end:
    time.sleep(.5);st=call('batch16-keepAlive-wait')
check('C15.maxDuration',st['keepAlive']=='fallback',st)
call('batch16-keepAlive-off','keepAlive',value='false');time.sleep(3)
call('batch16-keepAlive-on2','keepAlive',value='true');st=call('batch16-keepAlive-pause','pause',shot=True)
check('A25.pause',st['keepAlive']=='off' and not st['intent'],st)
call('batch16-live-dispose','dispose')

# MovaView owns creation, reuse, options changes, null source and disposal.
call('batch16-view-start',group='widgets',shot=True)
time.sleep(2);same=call('batch16-view-same','same',group='widgets',shot=True)
call('batch16-view-null','null',group='widgets',shot=True)
call('batch16-view-source','source',group='widgets')
call('batch16-view-options','options',group='widgets',shot=True)
call('batch16-view-hidden','ticker',group='widgets',value='false',shot=True)
call('batch16-view-visible','ticker',group='widgets',value='true',shot=True)
call('batch16-view-route','route',group='widgets',shot=True)
call('batch16-view-error','error',group='widgets',shot=True)
call('batch16-view-restored','source',group='widgets')
film=record('batch16-feed-recording')
call('batch16-feed','feed',group='widgets',shot=True)
finish_record('batch16-feed-recording',film)
for i in range(3):gesture('batch16-feed-swipe'+str(i),(540,1800,540,500),250)
adb('shell','input','tap','540','1200');adb('shell','input','tap','540','1200')
call('batch16-feed-social',group='widgets',shot=True)
call('batch16-widget-unmount','unmount',group='widgets',shot=True)
update('批次16 可视与组件检查点',[],['- 完整动作证据位于 `example/tool/coverage_evidence/batch16-*`。逐项最终结论由事件/系统读回/截图复核，脚本断言不替代视觉证据。','```json',json.dumps(checks,ensure_ascii=False,indent=2),'```'])
print('UI_BATCH_DONE',flush=True)
