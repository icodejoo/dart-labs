"""Observe a delayed old thumbnail across a source change and a 2s fade."""
import json,time,urllib.parse
from pathlib import Path
from coverage_device import request,adb,capture,shot
from coverage_record import update
out=Path(__file__).resolve().parent/'coverage_evidence'
def call(name,action='snapshot',**args):
    d=request('/run?'+urllib.parse.urlencode({'group':'video','action':action,**args}))
    end=time.monotonic()+40
    while d['status']=='running' and time.monotonic()<end:time.sleep(.1);d=request('/')
    (out/('batch28-'+name+'.json')).write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
    print(name,d['status'],flush=True)
    return d
def frame(name):shot(out/('batch28-'+name+'.png'))
call('slow-start',preview='true',slowPreview='true');call('slow-pause','pause');call('slow-controls','controls',value='sticky')
adb('shell','input','motionevent','DOWN','300','2307');adb('shell','input','motionevent','MOVE','400','2307');time.sleep(.7)
issued=time.time();call('source-change','open',path='ad.mp4');time.sleep(3.2)
d=call('stale-result');frame('stale-result');adb('shell','input','motionevent','UP','400','2307')
rows=d['records'];start=max(i for i,r in enumerate(rows) if r['kind']=='BEGIN' and r.get('args',{}).get('path')=='ad.mp4')
old_late=[r for r in rows[start:] if r['kind']=='PREVIEW_THUMB' and r.get('at') is not None]
(out/'batch28-stale-audit.json').write_text(json.dumps({'sourceChangeHostTime':issued,'lateNonNullThumbs':old_late,'lastVideo':next(r for r in reversed(rows) if r['kind']=='VIDEO')},ensure_ascii=False,indent=2),encoding='utf-8')
call('dispose','dispose');call('poster-start');call('poster-enable','poster',value='true');call('poster-hang','open',path='hang');frame('poster-covered')
request('/run?group=video&action=open&path=vod.mp4')
for i in range(12):frame('fade-'+str(i));time.sleep(.05)
call('fade-end');capture('batch28-final')
update('批次28：延迟缩略图竞态与自定义posterFade',[],['- slowthumbs.vtt服务人为延迟2.5s；拖动预览请求发起后0.7s换源，晚到的非空thumb统计见batch28-stale-audit.json；服务端BEGIN/END见coverage_media_final.log。','- MovaPlayer.posterFade设置2s以便真实截图观测中间透明度，12张连续PNG及最终state已保存。'])
