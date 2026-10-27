"""Read native volume at every boundary and measure open's immediate video state."""
from pathlib import Path
import json,time,urllib.parse
from coverage_device import request,capture,unlocked,adb
import coverage_record
from coverage_record import update
H=Path(__file__).resolve().parent
O=H/'coverage_evidence'
coverage_record.RESULT=H.parents[1]/'doc/plans/2026-10-27-device-coverage-rerun.md'
def call(name,action='snapshot',**args):
    unlocked()
    d=request('/run?'+urllib.parse.urlencode({'group':'video','action':action,**args}))
    end=time.monotonic()+50
    while d['status']=='running' and time.monotonic()<end:time.sleep(.1);d=request('/')
    if d['status']!='done':raise RuntimeError((name,d['status']))
    capture(name)
    return d
for proxy in [False,True]:
    name='rerun-native-'+('cutover' if proxy else 'engine')
    update('开始 '+name,[],['- 逐个音量边界读回Android媒体音量；在非audioOnly画面尺寸就绪后立即读open同步状态，补齐A8/A5/N12。'])
    call(name+'-dispose','dispose')
    call(name+'-start',cutover=str(proxy).lower())
    call(name+'-pause','pause')
    for v in [-10,0,1,50,100,110,30]:
        call(name+'-volume'+str(v),'volume',value=str(v))
        (O/(name+'-volume'+str(v)+'.native.txt')).write_text(adb('shell','cmd','media_session','volume','--stream','3','--get'),encoding='utf-8')
    call(name+'-open-sync','openSync')
    call(name+'-end','dispose')
    update('结束 '+name,[],['- 同前缀JSON中VIDEO_OPEN_BEFORE/VIDEO_OPEN_SYNC/VIDEO_OPEN_ACCEPTED保存真实宽高；*.native.txt保存媒体音量读回，截图/window/audio旁证均保留。'])
