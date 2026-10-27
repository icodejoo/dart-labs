"""Finish actual mini-window fling and held-preview inputs with native foreground checks."""
from pathlib import Path
import json,time,sys,urllib.parse
from coverage_device import adb,unlocked,request,capture
import coverage_record
from coverage_record import update
H=Path(__file__).resolve().parent;O=H/'coverage_evidence'
prefix='rerun-manual'+(sys.argv[2] if len(sys.argv)>2 else '')+'-'
coverage_record.RESULT=H.parents[1]/'doc/plans/2026-10-27-device-coverage-rerun.md'
def call(name,action='snapshot',**args):
    """Use the existing device command API and capture its completed state.

    复用设备命令API，并保存完成后的真实状态。
    """
    unlocked();d=request('/run?'+urllib.parse.urlencode({'group':'video','action':action,**args}));end=time.monotonic()+45
    while d['status']=='running' and time.monotonic()<end:time.sleep(.1);d=request('/')
    if d['status']!='done':raise RuntimeError((name,d['status']))
    capture(prefix+name)
    return d
def touch(*args):
    """Reject coordinates when the authorized activity is not in front.

    测试活动不在前台时拒绝坐标注入。
    """
    unlocked();a=adb('shell','dumpsys','activity','activities')
    if not any('mResumedActivity:' in s and 'com.icodejoo.mova.mova_example.coverage/' in s for s in a.splitlines()):
        raise RuntimeError('foreground guard rejected input')
    return adb('shell','input',*args)
def mini_point(data,fraction=.5):
    """Map the actual controller rectangle to this device's physical pixels.

    将控制器实际矩形按本机2.55像素比映射为触点。
    """
    row=next(r for r in reversed(data['records']) if r['kind']=='MINI_INFO');r=row['rect']
    if not row['showing']:raise RuntimeError('mini not visible')
    # The initial rect is nullable until the window reports a drag. The native
    # screenshot confirms the initial bottom-right window covers this point.
    # 初始rect在首次拖动前可为空；已实看原生截图确认该点位于右下小窗内。
    if r is None:return '800','2200'
    return str(round((r['left']+r['width']*fraction)*2.55)),str(round((r['top']+r['height']*.5)*2.55))
mode=sys.argv[1] if len(sys.argv)>1 else 'mini'
update('开始安全实触 '+mode,[],['- 触点来自实际mini矩形，预览等待真实thumb；仅测试包前台时注入，原始证据rerun-manual-*。'])
call(mode+'-hide','miniHide');call(mode+'-cleanup','dispose');call(mode+'-start',style='custom',preview='true');call(mode+'-portrait','orientation',value='portrait');call(mode+'-auto','orientation',value='auto')
if mode=='mini':
    call('mini-show','miniHost');d=call('mini-before','miniInfo');x,y=mini_point(d)
    touch('swipe',x,y,'400','1200','800');d=call('mini-drag','miniInfo')
    x,y=mini_point(d,.25);touch('tap',x,y);d=call('mini-tap','miniInfo')
    x,y=mini_point(d,.25);touch('swipe',x,y,'950',y,'90');call('mini-real-fling','miniInfo')
    call('mini-landscape','orientation',value='landscape');call('mini-portrait','orientation',value='portrait');call('mini-close','miniClose')
elif mode=='preview':
    call('preview-pause','pause');call('preview-controls','controls',value='sticky')
    touch('motionevent','DOWN','300','2307');touch('motionevent','MOVE','650','2307')
    try:
        end=time.monotonic()+12
        while True:
            d=call('preview-held')
            row=next(r for r in reversed(d['records']) if r['kind']=='VIDEO')
            if row['state']['previewCurrent'] is not None:break
            if time.monotonic()>end:raise RuntimeError('held preview produced no thumbnail')
        if not row['state']['dragging']:raise RuntimeError('preview not dragging')
    finally:touch('motionevent','UP','650','2307')
    call('preview-released')
update('结束安全实触 '+mode,[],['- 本批完成；真实mini回调/矩形/epoch或previewCurrent/dragging见rerun-manual-*原始JSON/PNG。'])
