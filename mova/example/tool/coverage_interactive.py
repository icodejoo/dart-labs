"""Additional real inputs, with source journals and per-action screenshots."""
import json,time,urllib.parse
from pathlib import Path
from coverage_device import request,adb,capture,unlocked
from coverage_record import update
out=Path(__file__).resolve().parent/'coverage_evidence'
def call(name,action='snapshot',group='video',shot=True,**args):
    d=request('/run?'+urllib.parse.urlencode({'group':group,'action':action,**args}))
    end=time.monotonic()+40
    while d['status']=='running' and time.monotonic()<end:time.sleep(.1);d=request('/')
    if shot:capture(name)
    else:(out/(name+'.json')).write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
    print(name,d['status'],flush=True)
    return d
def doubletap(x,y):adb('shell',f'input tap {x} {y}; input tap {x} {y}')
unlocked()
call('batch22-clean','dispose',shot=False)
call('batch22-remap-start',mapping='remap',style='custom')
call('batch22-remap-pause','pause',shot=False);call('batch22-remap-volume','volume',value='50',shot=False);call('batch22-remap-seek','seek',value='5000',shot=False)
adb('shell','input','swipe','300','1200','600','1200','600');call('batch22-remap-horizontal')
adb('shell','input','swipe','200','1600','200','1100','600');call('batch22-remap-left-seek')
call('batch22-minimal','skin',value='minimal');doubletap(540,1200);call('batch22-minimal-no-gesture')
call('batch22-bilibili','skin',value='bilibili');call('batch22-controls','controls',value='sticky')
adb('shell','uiautomator','dump','/sdcard/coverage-controls.xml');(out/'batch22-controls.xml').write_text(adb('shell','cat','/sdcard/coverage-controls.xml'),encoding='utf-8')
call('batch22-mini-show','miniHost')
adb('shell','input','swipe','800','2200','400','1200','800');call('batch22-mini-drag','miniInfo')
call('batch22-mini-landscape','orientation',value='landscape');call('batch22-mini-portrait','orientation',value='portrait')
adb('shell','input','swipe','800','2100','100','900','90');call('batch22-mini-fling','miniInfo')
call('batch22-mini-hide','miniHide');call('batch22-mini-page','miniPage');call('batch22-mini-close','miniClose')
call('batch22-dispose','dispose',shot=False)
call('batch22-nextup',group='new',case='nextUp')
call('batch22-nextup-controls','controls',value='sticky')
call('batch22-feed','feed',group='widgets')
doubletap(540,1200);call('batch22-feed-double-like',group='widgets')
adb('shell','input','tap','55','1910');adb('shell','input','tap','55','2080');call('batch22-feed-social',group='widgets')
adb('shell','input','tap','540','1200');call('batch22-feed-single-pause',group='widgets')
update('批次22：重映射、实际小窗拖动、NextUp及Feed输入',[],['- 原始动作/状态与PNG：`example/tool/coverage_evidence/batch22-*`。','- 控件树语义转储：batch22-controls.xml；双击改用同一adb shell连续注入，避免两个adb进程的延迟。'])
