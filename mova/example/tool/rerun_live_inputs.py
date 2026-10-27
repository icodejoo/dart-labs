"""Exercise the existing live DVR page using state-based readiness."""
from pathlib import Path
import json,time,urllib.parse
from coverage_device import request,capture,unlocked
import coverage_record
from coverage_record import update
H=Path(__file__).resolve().parent
O=H/'coverage_evidence'
coverage_record.RESULT=H.parents[1]/'doc/plans/2026-10-27-device-coverage-rerun.md'
def call(name,action='snapshot',shot=False,**args):
    unlocked()
    d=request('/run?'+urllib.parse.urlencode({'group':'video','action':action,**args}))
    end=time.monotonic()+50
    while d['status']=='running' and time.monotonic()<end:
        time.sleep(.15);d=request('/')
    if d['status']!='done':raise RuntimeError((name,d['status']))
    (O/(name+'.json')).write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
    if shot:capture(name)
    rows=d['records'];return next((r['state'] for r in reversed(rows) if r['kind']=='VIDEO'),{})
for run in range(3):
    name=f'rerun-live-{run}'
    update('开始 '+name,[],['- 播放真实18081滑动HLS，等待liveSeekable/进度就绪再seek与backEdge，核验TimeShiftChange和LiveEdgeReach；不将该滑动流当作历史回看服务。'])
    call(name+'-dispose','dispose')
    st=call(name+'-start',url=f'http://127.0.0.1:18081/live.m3u8?t={time.time_ns()}',live='true')
    end=time.monotonic()+25
    while (not st.get('liveSeekable') or st.get('position',0)<9000) and time.monotonic()<end:
        time.sleep(.4);st=call(name+'-ready')
    call(name+'-controls','controls',value='sticky',shot=True)
    behind=call(name+'-behind','seek',value='3000',shot=True)
    edge=call(name+'-backedge','backEdge',shot=True)
    update('结束 '+name,[],['- seek后state='+json.dumps(behind,ensure_ascii=False)+'；backEdge后state='+json.dumps(edge,ensure_ascii=False)+'。原始事件/载荷见同前缀JSON。'])
    call(name+'-end','dispose')
