"""Final targeted visual probes; retain rapid frames where transitions matter."""
import json,re,subprocess,time,urllib.parse,xml.etree.ElementTree as ET
from pathlib import Path
from coverage_device import request,adb,capture,unlocked,shot
from coverage_record import update
out=Path(__file__).resolve().parent/'coverage_evidence'
def call(name,action='snapshot',group='video',shot=False,**args):
    d=request('/run?'+urllib.parse.urlencode({'group':group,'action':action,**args}))
    end=time.monotonic()+45
    while d['status']=='running' and time.monotonic()<end:time.sleep(.1);d=request('/')
    if shot:capture('batch25-'+name)
    else:(out/('batch25-'+name+'.json')).write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
    print(name,d['status'],flush=True)
    return d
def frame(name):
    shot(out/('batch25-'+name+'.png'))
def frames(name,n):
    for i in range(n):frame(name+str(i));time.sleep(.05)
def click_text(label):
    adb('shell','uiautomator','dump','/sdcard/coverage-final.xml');xml=adb('shell','cat','/sdcard/coverage-final.xml')
    (out/('batch25-controls-'+str(time.time_ns())+'.xml')).write_text(xml,encoding='utf-8')
    for node in ET.fromstring(xml).iter('node'):
        if label in (node.get('content-desc','')+node.get('text','')):
            v=list(map(int,re.findall(r'\d+',node.get('bounds',''))))
            if len(v)==4 and v[2]>v[0]:adb('shell','input','tap',str((v[0]+v[2])//2),str((v[1]+v[3])//2));return True
    return False
unlocked()
call('start',style='custom',preview='true');call('pause','pause');call('bilibili','skin',value='bilibili');call('controls','controls',value='sticky',shot=True)
adb('shell','input','tap','600','230');call('speed-button',shot=True)
adb('shell','input','tap','540','1269');call('center-play',shot=True)
call('danmaku-seek','seek',value='2000');call('danmaku-play','play');time.sleep(1);call('danmaku',shot=True)
call('drag-pause','pause');call('drag-controls','controls',value='sticky')
p=subprocess.Popen(['adb','-s','7NQBB23606003715','shell','input','swipe','300','2307','650','2307','1800'])
time.sleep(.35);call('preview-during');frame('preview-bubble');p.wait();call('preview-after',shot=True)
call('poster','poster',value='true');call('poster-hang','open',path='hang');frames('poster-cover-',3)
request('/run?group=video&action=open&path=vod.mp4');frames('poster-fade-',8);time.sleep(.5);call('poster-after',shot=True)
call('poster-off','poster',value='false');call('minimal','skin',value='minimal');call('spinner-hang','open',path='hang');frame('spinner-custom')
call('spinner-off','skin',value='minimalEmpty');frame('spinner-disabled')
call('error-on','skin',value='minimalError');call('error-open','open',path='404.mp4');frame('error-visible')
call('error-off','skin',value='minimal');frame('error-disabled')
call('recover','open');call('normal','skin',value='default');call('mini','miniHost')
adb('shell','input','swipe','800','2200','400','1200','800');call('mini-drag','miniInfo')
adb('shell','input','tap','80','1150');call('mini-tap',shot=True)
call('mini-close','miniClose');call('dispose','dispose')
call('mini-disabled-start',miniEnabled='false');call('mini-disabled-show','miniHost');call('mini-disabled-info','miniInfo',shot=True);call('mini-disabled-dispose','dispose')
update('批次25 可视第一阶段',[],['- 逐动作日志/PNG及封面连续帧已保存batch25-*；包括真实preview气泡、custom红色spinner及显隐、错误层、mini默认禁用。'])
call('nextup',group='new',case='nextUp',shot=True);adb('shell','input','tap','915','2120');call('nextup-click',shot=True)
call('ad',group='new',case='visualAd');frame('ad-countdown');time.sleep(2);frame('ad-skippable')
adb('shell','input','tap','540','1200');call('ad-click');print('SKIP_BUTTON',click_text('跳过'),flush=True);call('ad-skip',shot=True)
call('route-player','routePlayer',group='widgets',shot=True);adb('shell','input','keyevent','KEYCODE_BACK');call('route-back',group='widgets',shot=True)
request('/run?group=widgets&action=feed');frames('feed-poster-',8);time.sleep(1);call('feed-after',group='widgets',shot=True)
update('批次25 可视第二阶段',[],['- batch25-nextup*、ad-countdown/ad-skippable/ad-skip、route-player/back及feed-poster连续帧保存；跳过按钮通过真实语义树定位。','- 矩阵里不存在的发送框、长按倍速、倍速菜单、NextUp数字倒计时/TopBar返回不能用别的动作冒充通过。'])
