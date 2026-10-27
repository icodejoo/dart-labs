"""Checkpoint verified UI and lifecycle results, preserving remaining gaps."""
from coverage_record import update
c=[]
def put(ids,status,detail):
    c.extend((i,status,detail) for i in ids.split())
put('A1','FAIL','batch15-basic/basic-cutover STREAM_FLAGS均[true,false,true,false]：states/uiStates.isBroadcast=false，events/progress=true。两订阅计数相等且八订阅均关闭；是标志/矩阵契约差异，不是已证实的多订阅失败。')
put('A2','FAIL','事件接收快照并非始终与载荷一致：E.BufferChange在batch1-basic-cutover 7次中3次不同；E.SizeChange在batch15-abr 7次中1次不同。其余可对账字段正常；见event-audit.json及复现记录，可能为异步队列快照语义。')
put('A10','PASS','batch15-basic/basic-cutover：0.5/1/1.5/2实际相同；-1/0均抛Invalid argument(rate)；换源及reload保持1.5x；batch11广告最大采样1x、恢复2x/1.5x。')
put('A14 A16','PASS','batch16-engine及cutover fullscreen/orientation原始JSON+window+PNG：横屏2266x1080、竖屏1080x2376；fullscreen topPadding110→0，退出恢复110；auto/portrait/landscape事件/state一致，两实现已测。')
put('A15','PASS','batch16-engine/cutover mini及mini-host/page各动作：位置继续、epoch始终0，非重新解码；batch18-mini→pip-enter：mini=true→false且pip=true，进入PiP返回true。')
put('A18 F5 N9','PASS','batch18-pip-visible.activity.txt：mode=pinned、mLastReportedPictureInPictureMode=true；enter返回true。展开pip=false且继续播放。X路径用adb tap(750,2050)后等450ms、tap(960,1965)，before-x.png有系统X，after-x.png关闭；pip-x-final state.pip=false/playing=false，native无pinned。原始JSON含true/false变更。')
put('A20 F2','PASS','batch19-live-dvr/behind/backedge：真实18081/live.m3u8；seek3s，TimeShiftChange behind随播放变化；backEdge到position12000ms、LiveEdgeReach，窗口12s；点播backEdge无副作用见basic，holding重载保护5/5见batch7 S13。')
put('C3 U6','FAIL','矩阵要求长按倍速：batch18-longpress-during在真实播放中注入1800ms长按，during/after rate均1；默认GestureLayer无longPress配置/处理。双击实际为±10s seek（batch18-doubletap-seek），左右亮度/音量、横滑、锁定均通过。此项为矩阵能力假设差异；Douyin另测。')
put('C5','PASS','batch18-normal-start/custom controls：showOnStart=true，800ms隐藏后batch18-autohide controls=false；batch16-cutover sticky保持，normal自动隐藏true；可见栏淡入/淡出截图及default/minimal组件组合有证据。')
put('C14','PASS','batch15-basic禁用恢复零Failure/Failover/Recovered；batch6 finite retry/failover/native END_FILE，batch15直播默认持续重连；batch19-options所有原生选项CHECK=true。续播位置缺陷另列F8/N19。')
put('C16','FAIL','batch15-tls 40格：verify=false四种证书均接收，verify=true拒绝expired/wrong/self；原合法IP SAN证书也5/5被拒。batch17-tls-probe 3轮×MP4/HLS：合法DNS localhost证书6/6通过、合法IP127.0.0.1证书6/6失败；原生tls-verify=yes/CA路径1150bytes读回正确；openssl verify IP成功。限定为IP证书兼容问题，未定位到Dart或原生层。')
put('E.MovaPipChange','PASS','batch18-pip-x-final.json累计记录：进入true、展开false、再进入true、点X false（438447–438448ms）；各载荷与state.pip一致。观察到同一次原生转换多条通知，不承诺exactly-once；进入/退出截图及activity对账见A18。')
put('E.MovaKeepAliveResume','PASS','batch7-keepAlive-core.log S1 GOP25/50/100各5次共15：elapsed约5000ms、signal=grace；随后state=off；batch8 C decodeOnly为1ms/signal=null 5/5。恢复事件时间是兜底时间，另有实际出画属性约百余ms，不能混用。')
put('F6 N20','PASS','batch7/8/16：off/holding/fallback/resuming迁移，pause结束、hiddenTicker/source变化重hold、后台降级；S7 mediacodec-copy恢复20/20、无codecopen失败；S13 vid=no/mute=yes保护5/5。S1主信号未落地15/15 grace≈5s，是允许的超时兜底；保留性能/信号缺口，不再把它当作功能FAIL。S14 Android holding黑屏，恢复正常。')
put('U9 N18','PASS','batch6 HE V9前后台5/5、V10 route/Ticker/关闭守卫各5次、V11 PiP豁免5/5；batch16-view-route配置root RouteObserver、ticker隐藏/恢复有ROUTE_HIDDEN及状态，feed滚动池见batch15+16；小窗连续播放见batch16，不要求外部业务go_router才能验证此库API。')
put('F16','PASS','已逐项复测历史缺陷：PiP展开和X现均复位（batch18）；广告1x/恢复用户2x或1.5x、退役不复位方向、pod第二条真换指均batch11每项3次。旧缺陷本轮未复现；F16的PASS表示复现任务完成，不表示保留旧bug。')
put('N12','FAIL','首帧功能通过batch4，但矩阵要求open同步归零：batch15-basic OPEN_SYNC调用open后立即读仍duration40000/rendered=true/旧title，之后异步归零；两实现均有记录。属于同步时机的矩阵期望差异，实际open是异步接口。')
put('A23','FAIL','batch15-basic/basic-cutover第二次dispose均抛[Player] has been disposed；disposed open=false。首次销毁正常且8流关闭；batch15-dispose120完成120轮，round20..120 meminfo与RSS约227→247MB尾部平台，不能据此证明绝无泄漏；batch11加载/换指期间销毁通过。')
update('批次18/19：PiP双退出、手势、转屏、直播与历史结论复核',c,['- X关闭前/后截图及native活动状态已取得，先前点错坐标的batch18-pip-closed-x不得作为关闭成功证据。','- 修正此前将grace兜底归为F6/N20失败的过严判定：矩阵允许状态机恢复，保留信号未落地的测量事实。','- HLS旧脚本错误等待被契约抑制的Seeked；第二版又用跨引擎latest和duration流变化作门控，均作为验证器问题保留，不计库FAIL；最终版本使用每引擎progress和原生位置直接读回，待最后一次复跑。'])
