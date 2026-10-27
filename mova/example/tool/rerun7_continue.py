"""Restart the same rerun7 package after an interrupted batch and add evidence."""
from rerun7_extra import call,unlocked,adb,note,request
import sys,time
mode=sys.argv[1];count=sys.argv[2];suffix=sys.argv[3] if len(sys.argv)>3 else 'extra'
assert mode in ['cutover','normal','paused']
note('开始中断恢复：保留先前原始批次及SCRIPT_ERROR，核对屏幕后重启同一rerun7包，补跑独立批次，不覆盖旧证据。')
unlocked();adb('shell','am','force-stop','com.icodejoo.mova.mova_example.coverage')
adb('shell','am','start','-n','com.icodejoo.mova.mova_example.coverage/com.icodejoo.mova.mova_example.MainActivity')
for _ in range(100):
 try:
  d=request('/');assert any(x.get('build')=='rerun7-20261027' for x in d['records']);break
 except Exception:time.sleep(.25)
else:raise RuntimeError('page missing')
args={'count':count}
if mode=='cutover':args['cutover']='true'
if mode=='paused':args['paused']='true'
call('rerun7-hls-'+mode+'-'+suffix,'new',case='hls',**args)
