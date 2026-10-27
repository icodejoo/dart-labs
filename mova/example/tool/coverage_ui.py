"""Exercise visible API actions with a screenshot and OS readback per action.

每次可视 API 操作后采集截图与系统读回。
"""
import time
import urllib.parse
from coverage_device import unlocked, request, capture, adb

unlocked()
adb('forward','tcp:18083','tcp:18083')
actions = [('snapshot',''),('pause','')]
actions += [('fit',v) for v in ['contain','cover','fill']]
actions += [('zoom',v) for v in ['-1','0','1','2','100','1']]
actions += [('volume',v) for v in ['0','50','100','30']]
actions += [('brightness',v) for v in ['0','.25','.75','1','.5']]
actions += [('lock','true'),('lock','false'),('fullscreen','true'),('fullscreen','false')]
actions += [('orientation',v) for v in ['landscape','portrait','auto']]
actions += [('skin',v) for v in ['bilibili','minimal','mini','default']]
for i,(action,value) in enumerate(actions):
    d=request('/run?'+urllib.parse.urlencode({'group':'video','action':action,'value':value}))
    end=time.monotonic()+40
    while d['status']=='running' and time.monotonic()<end:
        time.sleep(.2)
        d=request('/')
    name=f'batch3-{i:02}-{action}-{value or "state"}'
    capture(name)
    print(name,d['status'],flush=True)
