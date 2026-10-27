from rerun4_extra import call,unlocked,adb,note,request
import time
note('开始中断恢复：首批cutover已产出76个结果，run75目标流打开失败且无门槛，后续复位20s超时；保留原始批次与SCRIPT_ERROR，核对屏幕后重启同一隔离包，独立补跑cutover90、normal60、paused60，不覆盖旧证据。')
unlocked()
adb('shell','am','force-stop','com.icodejoo.mova.mova_example.coverage')
adb('shell','am','start','-n','com.icodejoo.mova.mova_example.coverage/com.icodejoo.mova.mova_example.MainActivity')
for _ in range(100):
 try:
  d=request('/');assert any(x.get('build')=='rerun4-20261027' for x in d['records']);break
 except Exception:time.sleep(.25)
else:raise RuntimeError('page missing')
note('恢复检查点：同一rerun4包已启动，继续独立补跑批次；首批SCRIPT_ERROR不隐去。')
call('rerun4-hls-cutover-extra','new',case='hls',cutover='true',count='90')
call('rerun4-hls-normal','new',case='hls',count='60')
call('rerun4-hls-paused','new',case='hls',paused='true',count='60')
