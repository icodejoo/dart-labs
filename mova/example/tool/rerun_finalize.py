"""Write an explicit 135-item rerun ledger, comparisons and reviewable reproductions."""
from pathlib import Path
from collections import Counter,defaultdict
import json,re,statistics
H=Path(__file__).resolve().parent;O=H/'coverage_evidence';D=H.parents[1]/'doc/plans/2026-10-27-device-coverage-rerun.md'
previous=json.loads((O/'rerun-previous-ledger.json').read_text(encoding='utf-8'))
audit=json.loads((O/'rerun-event-review.json').read_text(encoding='utf-8'))
verdicts={}
def put(ids,status,detail):
    """Record reviewed device evidence explicitly; never inherit a previous PASS.

    显式写入已复核真机证据，不继承上次PASS。
    """
    for ident in ids.split():verdicts[ident]=(status,detail)
put('A1','FAIL','两实现broadcast=[true,false,true,false]；两订阅均收到、八订阅均关闭。标志契约差异。rerun-batch15-basic/basic-cutover.json。')
put('A2','FAIL','接收事件时state快照仍可不同：Buffer/Size及本次新增Quality对账差异；详见rerun-event-review.json的逐条mismatchExamples。')
put('A3','PASS','audioOnly handle=null/size0x0；lazy构造0/open0/首次handle1；真实视频挂树非空、宽高640x360。rerun-batch15-lazy/basic、rerun-batch16-engine-start.json。')
put('A4','PASS','普通/代理pipSupported=true且state一致。rerun-batch15-basic/basic-cutover.json CHECK A4。')
put('A5','FAIL','两实现VIDEO_OPEN_SYNC仍640x360/duration40000/rendered=true；404恢复关时accepted=true、不抛，随后error事件。同步/错误契约差异，N8接受语义仍通过。rerun-native-engine/cutover-open-sync.json、rerun-extra-edges.json。')
put('A6','PASS','两实现play/pause/playOrPause、重复pause与独立intent检查通过，真实事件与进度均保存。rerun-batch15-basic/basic-cutover.json。')
put('A7','PASS','两实现5个精确seek误差0；负值/seekBy、加载中7s寄存与超时长钳制有实际读数；直播禁seek。rerun-batch15-basic/basic-cutover/live-*.json、rerun-extra-edges.json。超界seek仅测钳制，不用来伪造自然EOF。')
put('A8','PASS','两实现越界state钳0..100；逐值原生媒体音量读回0/中间/20（1%受系统离散级量化）。rerun-batch15-basic/basic-cutover.json、rerun-native-engine/cutover-volume*.json及.native.txt。')
put('A9','PASS','两实现clamp全部true；原生brightness：输入-1/0/.25/.75/1/2→0/0/.25/.75/1/1；代理手势窗口sbrt=.7530023。rerun-extra-edges.json、rerun-batch16-cutover-left-check.window.txt。')
put('A10','PASS','0.5/1/1.5/2、非法-1/0拒绝、换源保留；广告1x并恢复2x/1.5x各3轮。rerun-batch15-basic/basic-cutover.json、rerun-batch11-review.log V13a/b。')
put('A11','PASS','两实现contain/cover/fill状态、事件及真实画面不同；见rerun-batch16-engine/cutover-fit-*.png/json、rerun-safe-contact-1.jpg。')
put('A12','FAIL','setZoom(-1/0/100)仍接受并改变画面，未使用手势maxZoom钳制。矩阵边界假设差异；非法低值可使画面塌缩。rerun-batch3-05..10-zoom-*.json/png。')
put('A13','PASS','两实现锁定后左右触摸不改变亮度/音量，解锁后可用，LockChange/state一致。rerun-batch16-checks.json及locked/unlock原始文件。')
put('A14','PASS','两实现进/出全屏状态与事件、系统栏隐藏/恢复，进入按宽高比横屏；退出原生恢复FULL_USER。rerun-batch16-*-fullscreen-*.json/window.txt；方向探针的“自动必竖屏”误判另列。')
put('A15 F5','FAIL','真实MiniHost→enterPip后mini=false但controller仍showing=true/persistent；展开后pip=false/mini=false而小窗仍可见。全新进程复现，真实UI与状态衔接缺口。rerun-mini-pip-repro-show/enter/holding/expanded.json/png/activity.txt。')
put('A16','PASS','两实现landscape/portrait/auto事件及真实窗口尺寸/原生方向有读回。rerun-batch16-*-orientation-*.json/window.txt、rerun-batch3-24..26-orientation-*。自动不承诺强制竖屏。')
put('A17 F3','FAIL','HLS累计39/40切档通过，成功落点误差均0ms；长进程代理run3 target10183→RESTART[23,23]，未续播。ABR真实限速降档通过但不抵消失败。rerun-hls/ measured-summary.json、rerun-batch17-hls-playing-cutover.json、rerun-final-hls-cutover/abr.json。')
put('A18 N9','PASS','进入true、原生pinned；展开及真正X关闭均收到PipChange(false)/state复位。rerun-manual-pip-enter/expanded/third/x-confirmed.json/activity.txt/png。先前x-closed只是菜单消失，未当关闭证据。')
put('A19','PASS','两实现reload真实重载，进度归零及事件序列已记录。rerun-batch15-basic/basic-cutover.json RELOAD。')
put('A20 F2','PASS','真实滑动HLS三轮：DVR窗口12s，seek后behind约8s，backEdge position12000、LiveEdgeReach；点播回边缘无副作用。rerun-live-0/1/2-behind/backedge.json、rerun-batch15-basic.json。此项是本地DVR，不冒充按URL历史服务。')
put('A21','PASS','hide/show sticky、HUD文字类型、dragging/previewAt，自动隐藏及sticky延迟检查通过。rerun-batch15-basic/basic-cutover、rerun-batch16-checks、rerun-manual2-preview-held/released.json。')
put('A22','PASS','custom覆盖probe42与内置play透传probe43，value相等/hash检查通过。rerun-batch15-basic/basic-cutover.json CHECK A22。')
put('A23','FAIL','两实现第二次dispose仍抛[Player] has been disposed；首次关闭及disposed open=false正常，120轮首次创建/销毁完成。二次调用安全的矩阵契约差异。rerun-batch15-basic/basic-cutover/dispose120.json及round*.meminfo.txt。')
put('A24 C11','PASS','关闭直通、开启prepare/commit/abandon、短窗口/超时降级、epoch与影子释放7项检查通过。rerun-batch15-cutover.json；真实视频换指另见rerun-batch11-review.log。')
put('A25 C15 F6 N20','PASS','off/holding/fallback/resuming、pause结束、默认maxDuration30s到期、allowHls两分支各3轮；硬解恢复20/20、后台降级/恢复、重载与隐藏换源均完成。rerun-keepalive-core.log、rerun-batch8-keepAlive-native.log、rerun-batch16-checks.json。grace及强制无音轨探针FAIL另列，不隐藏。')
put('A26 C12 U8','PASS','A/B挂载互斥、hide/close/setRect、回调、真实拖动/吸边/转屏均有证据。安全实触：left12→90ms甩动left231.5294且showing=true，MINI_TAPPED与MINI_CLOSED实际到达。rerun-batch16/22-mini*、rerun-manual2-mini-*.json/png。')
put('A27 C9','PASS','默认关、pre/mid/post/manual、deferred、clicked/skip、pod、waitsFor三层覆盖；两种404失败策略完成。rerun-batch15-ads/adResume.json、rerun-extra-ad-failure.json、rerun-batch11-review.log。')
put('A28','PASS','next/previous/jumpTo/边界及自然完播自动下一条3项检查通过；拒绝jumpTo不前进另见hooks。rerun-extra-playlist.json、rerun-batch15-hooks/hooks-cutover.json。')
put('A29','PASS','100次串行+20次并发滑动最终active120、原生池3引擎，回收完成；实际Feed触摸另测。rerun-batch15-feed.json、rerun-batch22-feed*.json/png。')
put('A30 C1 F10','PASS','VTT优先/crop不缓存、实际原生抽帧、内存2上限、磁盘/内存命中、cancel/clear、never阻断；真实connectivity与拒连VTT抽帧兜底通过。rerun-batch15-preview-*.json、rerun-extra-preview-probe/offline.json及thumb*.jpg。')
put('A31 C7','BLOCKED','已测disabled/noEngine阻断、注入引擎首启失败回滚/二次重试。未提供真实识别模型/模型下载服务，设备旧seed目录不存在；真实转写、下载失败链、SRT导出/分块落盘未完成。rerun-batch15-stt.json、rerun-stt-device-seed.txt。')
put('A32','PASS','普通/代理各9项异步hooks检查通过：放行/拒绝/被取代、pause期间stalePlay、换源staleSeek、异常后继续播放及error隔离。rerun-batch15-hooks/hooks-cutover.json。')
put('A33 N21','PASS','真机安装MovaTesting后平台端口空操作、stagedSourceOptions读回通过；Android实际转场/换指未出现Windows快照路径副作用。rerun-batch15-testing.json、rerun-batch11-review.log及rerun-batch16-view-*.json。')
put('C2','BLOCKED','已测真实FLV/HLS durationStep、12s本地DVR、behind/回边缘三轮；未提供按behind URL返回历史且可控卡顿服务。urlBuilder历史语义、自定义windowResolver/autoBackToLiveOnStall完整联动未完成。rerun-live-*.json、rerun-batch15-live-step*.json；条件与上次相同。')
put('C3 U6','FAIL','真实长按1800ms期间仍1x，当前无长按倍速；侧别/轴向改配、seek、默认双击seek、Douyin Feed点击/like及锁定屏蔽已实测。能力假设差异。rerun-batch18-longpress-*.json、rerun-batch22-remap/feed*.json、rerun-batch16-checks.json。')
put('C4','PASS','真实HTTP ts限速触发MovaAbrDownShift，高→低后紧接手切，reset生效；两轮有实际轨迹。rerun-batch15-abr.json、rerun-final-abr.json；使用threshold1门控配置，不宣称默认阈值性能。')
put('C5','PASS','showOnStart、800ms自动隐藏、sticky保持与皮肤控件显隐通过；原始uiStates/截图齐全。rerun-batch16-checks.json、rerun-batch18-autohide.json、rerun-safe-visual-*.png。')
put('C6','FAIL','真实滚动弹幕可见，但发送API/输入框未提供（display-only），矩阵要求的发送不能满足。rerun-safe-visual-danmaku.png/json。')
put('C8','FAIL','自动连播、NextUp卡片/取消/立即播放实测；卡片没有数字倒计时。rerun-extra-playlist.json、rerun-safe-visual-nextup/nextup-click.png/json。')
put('C10 N16','PASS','COVERAGE FIT文案实际可见；60/8/红色spinner及开关、错误层显隐、Minimal无栏无手势通过。rerun-safe-visual-controls/spinner-custom/spinner-disabled/error-visible/error-disabled.png，controls-*.xml与组件清单。')
put('C13 F7 N23','PASS','qoe:false零QoE；四类结束原因、restart TTFF、cache卡顿/截断均取得真实报告。完整释放卡顿sessionEnd stallCount1/stallMs5496。rerun-batch15-qoe-*.json、rerun-batch17-qoe-failed/qoe-stall-release.json；custom另见A22。')
put('C14','PASS','默认关，有限重试/地址切换、超时和源级mpv选项读回、默认直播持续重连/legacy分支均完成。rerun-batch15-options/recovery*.json、rerun-extra-failover/live-backoff-*.json、rerun-he-recovery.log。')
put('C16','FAIL','实时戳最终矩阵35/40；合法IP SAN verify=true仍5/5拒绝。独立探针合法DNS6/6通过、合法IP0/6；CA属性正确，OpenSSL两证书OK。原生TLS兼容缺陷，未定位具体责任层。rerun-final-tls/tls-probe.json、rerun-openssl-verify.txt。')
put('C17 N4','PASS','alternatives/uris/pick/sameAs、headers、sourceIndex；network/cache/demux按源应用并恢复，默认白名单保留，非法项不写error，WHEP微秒选项读回。rerun-batch15-options.json及服务端HEADERS、rerun-extra-failover.json。')
put('E1','FAIL','真实Play意图事件早于Ready/FirstFrame，不满足矩阵示意箭头严格顺序。不是提前出画；自然Done1/无错误的生命周期仍通过F1。rerun-batch15-lifecycle.json。')
put('E2','PASS','两实现默认关闭功能事件count0、qoe:false无QoE。rerun-batch15-basic/basic-cutover.json。')
put('U1 U2','PASS','Player/View/Feed实际挂卸、surface、五皮肤/patch组件，View route/ticker与Impeller渲染均留有设备证据。rerun-batch16-view-*.json、rerun-batch16-*-customSurface/patch.png、rerun-batch22-feed*.json/png及safe视觉。')
put('U3','FAIL','实际TopBar只有标题及功能按钮，没有返回按钮；Android BACK能退路由。能力假设差异。rerun-safe-visual-route-player/route-back.png/json；PiP/方向另见A16/A18。')
put('U4','PASS','真实live/VOD栏、底栏拖动与悬停彩色预览气泡通过。dragging=true、previewAt25987、previewCurrent20000；UP后释放。rerun-live-*-controls.png、rerun-manual2-preview-held/released.json/png。')
put('U5','FAIL','语义点击1x后直接1.25x、没有倍速菜单；CenterPlay实际点击播放，HUD另有真实手势读回。能力形态差异。rerun-safe-visual-speed-button/center-play.json/png、rerun-batch16-*-left/right*.png。')
put('U7','PASS','弹幕/四格式字幕、NextUp立即播放、广告倒计时/点击/跳过、Feed输入均实际完成。rerun-safe-visual-*（SKIP_BUTTON=true）、rerun-extra-subtitles.*、rerun-batch22-feed*.json。上次把C8的NextUp数字倒计时缺失重复记到U7；本次按该组合中的广告倒计时判，纠正口径。')
put('U9','PASS','HE前后台/route/Ticker/PiP各3轮，真实Feed滚动；View的RouteObserver与ticker路径通过。rerun-he-recovery.log、rerun-batch16-view-*.json、rerun-batch22-feed*.json。主观手感不伪造成人工评价。')
put('F1','PASS','真实open/播放/seek/rate/fullscreen/换源/自然Done/dispose无异常。rerun-batch15-lifecycle.json naturalDone1/errors0；E1的意图事件严格箭头另判。')
put('F4','PASS','广告回正片5次原生续播误差全部0ms、epoch2；pod/失败降级/关闭态已测。rerun-batch15-adResume/cutover.json、rerun-batch11-review.log、rerun-extra-ad-failure.json。')
put('F8 N19','PASS','坏地址nativeEndError、三轮failover/giveUp、多地址及卡顿后续播通过。最终V6连续区间5/5，位置误差40/40/0/0/40ms，平均24ms；超时offset1/14/2/1/1ms，平均3.8ms。rerun-he-v6-final.log、rerun-he-recovery.log、rerun-extra-failover.json。旧V6计时/锚点误判已纠正。')
put('F9','PASS','audioOnly handle=null、size0x0、进度/AudioTrack；与视频窗口的实际截图和CPU/内存对照已采样。rerun-batch15-basic.json、rerun-batch16-audio/video*.json/png/cpu.txt。未冒充人耳音质评价。')
put('F11','PASS','四格式SRT/ASS/WebVTT外挂及mov_text内封：4个CHECK全部true、原生sub-text非空/decoder轨道与实际字幕PNG齐全。rerun-extra-subtitles.json、rerun-extra-subtitles.srt.png、rerun-extra-subtitles.ass.png、rerun-extra-subtitles.vtt.png、rerun-extra-subtitles.movtext.png。')
put('F12','PASS','四模式各3轮top/batterystats及音频模式对照完成。单核均值normal99.64%、muted7.70%、decodeOnly112.67%、pause6.50%。rerun-cpu-review.json、rerun-batch9-keepAlive-cpu-drift.samples.txt、rerun-batch16-audio/video.cpu.txt。USB供电，不推导电池能耗。')
put('F13','PASS','feed100+20次最终3引擎，三引擎RESTART互不串扰；销毁最大帧间隔46/55ms<100。rerun-batch15-feed.json、rerun-batch12-pump.log；120轮仅报告资源趋势，不声称绝无泄漏。')
put('F14','PASS','release RESTART与END_FILE实际到达，qoe:false建客户端0，created14/destroyed14。rerun-batch12-pump.log、rerun-he-recovery.log。')
put('F15','BLOCKED','WHEP端点38889/test/whep拒连，相关端口探测不可用；缺publisher/信令/UDP38189及relay38190服务。只完成WHEP选项读回，未完成15s播放。rerun-external-prerequisites.json、rerun-batch15-options.json；与上次条件相同。')
put('F16','PASS','历史PiP退出state已修复，两退出路径到false；广告方向/内容倍速恢复、pod第二条换指已测各3轮。rerun-manual-pip-*.json、rerun-batch11-review.log。此项表示历史缺陷复核完成；新MiniHost/PiP残留另列A15/F5。')
put('N1','PASS','真实默认黑洞5259/5279/5279ms，均值5272.3ms；network2s为2249/2237/2263ms，均值2249.7ms。65s是Dart兜底非mpv实际默认。原生整数/WHEP微秒/源优先读回见rerun-batch15-options与hang-*.json。')
put('N2','PASS','派生HTTP65s/WHEP85s/10s、override/clear、stallWatchdog关闭真卡顿均实测；END_FILE先判。rerun-batch15-options/watchoff/hang*.json、rerun-he-v6-final.log连续缓冲期限。')
put('N3','PASS','liveDefault第三次仍重试、legacy有限放弃、alternatives每地址策略；cap7退避三轮间隔均值1038.67/2107.33/4070.67/8058.33/15067/15086.67/15103ms，符合1/2/4/8/15/15/15s。rerun-reconnect-summary.json、rerun-extra-live-backoff-0/1/2.json、rerun-batch15-recovery-live*.json。')
put('N5','PASS','404/拒连均真实nativeEndError，HE V8各3轮：404为73/86/96ms，均值85ms；拒连86/88/85ms，均值86.33ms。recovery错误订阅不代替精确首帧，V1 precise on/off各3轮。rerun-he-recovery.log、rerun-he-firstframe.log。')
put('N6','PASS','Recovered后error=null、giveUp后buffering=false与false事件；真实加载在途END_FILE可处理。rerun-extra-failover.json、rerun-batch15-recovery*.json及hang*.json。')
put('N7','PASS','真实直播durationStep0/2000各3轮事件时间戳、首非零/open归零放行；VOD不受节流。rerun-batch15-live-step*.json、rerun-batch15-basic.json。')
put('N8','PASS','普通/代理接受true、拒绝/被取代/已销毁false、playlist拒绝不前进。rerun-batch15-hooks/hooks-cutover.json；404 accepted不表示播放成功。')
put('N10','PASS','广告max1x，回正片2x/1.5x各3轮；pod第二条真正epoch换指，退役未重置继任者的全屏/方向。rerun-batch11-review.log V10/V12/V12b/V13a/b/V14。自动方向不等于竖屏的探针误判另列。')
put('N11','PASS','Q13A/B/C各5/5；41份阶段dumpsys audio媒体音量恒6/20，静音只影响mpv mute且退出顺序均还原。rerun-batch10-mute.log、rerun-mute-volume-review.json。')
put('N12','FAIL','精确首帧/换源重置/过期RESTART通过，但两实现open同步快照仍旧640x360；符合异步beforeOpen后再归零的现行行为，不符合矩阵字面同步要求。rerun-native-engine/cutover-open-sync.json、rerun-he-firstframe.log。')
put('N13','PASS','precise on/off各3轮、native弱客户端数量与懒创建实际计数通过。rerun-he-firstframe.log、rerun-batch12-pump.log、rerun-batch15-lazy.json。')
put('N14','PASS','declarative cover→用户contain→重建仍contain，两实现CHECK均true。rerun-batch16-checks.json及*-declarativeFit/userFit/rebuild.json。')
put('N15','PASS','video换源重盖/实际中间渐隐、audioOnly封面常驻、Feed首帧前封面→视频完成。只用全尺寸前台安全截图。rerun-safe-transition-poster-covered/fade-*.png、rerun-safe-visual-feed-poster-*.png、rerun-batch16-audio-poster.png及对应事件。')
put('N17','PASS','View自建/复用、同源、null暂停、options重建/销毁及onOpenError，sameAs包括alternatives。rerun-batch16-view-*.json、rerun-batch15-options.json、rerun-batch16-widget-unmount.json。')
flags=json.loads((O/'rerun-debug-assert.json').read_text(encoding='utf-8'))
assert all(flags.values()),flags
put('N22','PASS','异步hooks两实现、轴向重映射、STT失败回滚、crop零缓存；慢VTT确在换源后完成，晚到非空thumb0。debug真机VM断言开启且两个非法构造均捕获。rerun-batch15-hooks/stt.json、rerun-batch22-remap*.json、rerun-safe-transition-stale-audit.json、rerun-debug-assert.json/logcat.txt。')
guard_path=O/'rerun-he-guard-extra.log'
guard_log=guard_path.read_text(encoding='utf-8',errors='replace') if guard_path.exists() else ''
mini_guard=re.findall(r'VERDICT V11M (PASS|FAIL)',guard_log)
closed_guard=re.findall(r'VERDICT V10C (PASS|FAIL)',guard_log)
if mini_guard==['PASS']*3 and closed_guard==['PASS']*3:
    put('N18','PASS','独立mini守卫V11M与guard关闭V10C各3/3，另有前后台/route/Ticker/PiP、Feed滚动、直播隐藏回边缘的本次证据。rerun-he-guard-extra.log、rerun-he-recovery.log、rerun-batch16-view-*.json。')
else:
    put('N18','BLOCKED','已测HE前后台/route/Ticker/PiP各3轮，inactive意图及直播隐藏>=3s回边缘LiveEdgeReach、真实Feed滚动和View RouteObserver。小窗连续播放原证据未独立证明MovaAutoPause豁免；新增V11M/V10C补测APK已构建，但起测前isKeyguardShowing=true，驱动拒绝执行，按用户约束停止，缺该联动的真机结论。rerun-he-guard-extra-driver.log、rerun-final-locked-window.txt、rerun-he-recovery.log。')
for ident,v in audit.items():
    sample=v['sample'];payload=json.dumps(sample['payload'],ensure_ascii=False,separators=(',',':'))
    origin=json.dumps(sample.get('origin',{}).get('args',{}),ensure_ascii=False,separators=(',',':'))
    ref=v['mismatchExamples'][0] if v['mismatchExamples'] else sample
    detail=f"{v['runtimeName']}：去重{v['count']}次，同型相邻同值{v['repeatedAdjacentPayloads']}次；标量对账{v['compared']}条/差异{v['mismatches']}条；样例payload={payload}，动作={origin}。证据{ref['file']}，全部载荷/状态/上下文见rerun-event-review.json。"
    put(ident,v['verdict'],detail)
ids=[i for i,_,_ in previous]
assert len(ids)==135 and len(set(ids))==135
assert set(ids)==set(verdicts),(set(ids)-set(verdicts),set(verdicts)-set(ids))
replacements={
 'rerun-batch15-basic/basic-cutover/dispose120.json':'rerun-batch15-basic.json、rerun-batch15-basic-cutover.json、rerun-batch15-dispose120.json',
 'rerun-batch15-basic/basic-cutover.json':'rerun-batch15-basic.json、rerun-batch15-basic-cutover.json',
 'rerun-native-engine/cutover-open-sync.json':'rerun-native-engine-open-sync.json、rerun-native-cutover-open-sync.json',
 'rerun-final-tls/tls-probe.json':'rerun-final-tls.json、rerun-final-tls-probe.json',
 'rerun-hls/ measured-summary.json':'rerun-measured-summary.json',
 'rerun-batch3-05..10-zoom-*.json/png':'rerun-batch3-05-zoom--1.json、rerun-batch3-06-zoom-0.json、rerun-batch3-09-zoom-100.png',
 'rerun-safe-visual-route-player/route-back.png/json':'rerun-safe-visual-route-player.png、rerun-safe-visual-route-back.png及同前缀JSON',
 'rerun-safe-visual-nextup/nextup-click.png/json':'rerun-safe-visual-nextup.png、rerun-safe-visual-nextup-click.json',
 'rerun-safe-visual-speed-button/center-play.json/png':'rerun-safe-visual-speed-button.json、rerun-safe-visual-center-play.json及PNG',
 'rerun-debug-assert.json/logcat.txt':'rerun-debug-assert.json、rerun-debug-assert.logcat.txt',
}
for ident,(status,detail) in list(verdicts.items()):
    for a,b in replacements.items():detail=detail.replace(a,b)
    verdicts[ident]=(status,detail)
rows=[(i,*verdicts[i]) for i in ids]
counts=Counter(s for _,s,_ in rows);groups=defaultdict(Counter)
for i,s,_ in rows:groups[i[0]][s]+=1
old_status={i:s for i,s,_ in previous}
old_problem=[i for i,s,_ in previous if s!='PASS']
regressions=[i for i,s,_ in rows if old_status[i]=='PASS' and s=='FAIL']
new_blocked=[i for i,s,_ in rows if old_status[i]=='PASS' and s=='BLOCKED']
fixed=[i for i,s,_ in rows if old_status[i]=='FAIL' and s=='PASS']
journal=D.read_text(encoding='utf-8');journal=journal[journal.find('## 基线与前置'):]
# Preserve batch starts/checkpoints while avoiding a second numbered ledger.
journal=re.sub(r'## 逐编号台账.*?(?=\n## )','',journal,flags=re.S)
journal=re.sub(r'\n{3,}','\n\n',journal)
lines=['# 2026-10-27 Android 完整覆盖复跑结果','',f"最终135项：**PASS {counts['PASS']} / FAIL {counts['FAIL']} / BLOCKED {counts['BLOCKED']}**。上次107/23/5。",'',
'全部本次证据位于 `example/tool/coverage_evidence/`，下表文件名均相对该目录；均用 `rerun-` 前缀，未覆盖上次结果。仅新结果与验证页/脚本有本任务修改，库和测试未修复。',
'','## 基线、构建与设备','',
'- 7NQBB23606003715，STG-AL00 Android12/arm64；测前及各驱动确认亮屏解锁。`rerun-preflight-window/audio/power.txt`、`rerun-device-build.json`。起测USB常亮7、媒体speaker6/20。',
'- Flutter3.47.0 / Dart3.13.0。`flutter analyze lib test` **1 error + 1 warning（2 issues），exit1**；`flutter test` **1424通过、1测试文件加载失败，exit1**。已有 `test/core/engine_test.dart` 的 `_RecordingBrightPort` 在1959/1978重复定义，整文件未加载；不是79个测试断言失败，不能把上次1503或文档1510算成本次通过。原始 `rerun-baseline-analyze/test.log`，未改该文件。',
'- 修改的4个验证页单独analyze **0 issues，exit0**，`rerun-verifier-analyze.log`；额外守卫页变更后he_auto.dart再分析亦0 issues，`rerun-he-extra-analyze.log`。release隔离包构建/安装成功，真实libmpv6357872bytes、SHA256 `798cde9e27e3761dd5f8f065693e4669b5499d5807618f81a74e0d3a88dc230b`。主批次APK SHA256 `d4535851ebe9074860ba9772f501253d2043620655d61f40e320df32b98537ab`，保留原包`rerun-main-release.apk`，元数据`rerun-final-build-manifest.json`。最后安装的独立守卫补测APK见`rerun-guard-build-manifest.json`，该补测因锁屏未启动。',
'- 所有媒体/渲染判据来自release真实事件/状态/原生读回；仅N22构造断言用独立debug VM，`rerun-debug-build.log`、`rerun-debug-assert.*`。main库无改动。',
'- 编号仍为A33+C17+E37+U9+F16+N23=135。沿用旧编号：E.MovaSwapChange对应现MovaCutoverChange，E.MovaStandbyChange/Resume对应现MovaKeepAliveChange/Resume；只映射名称，不增减编号。',
'','## 最终分组汇总','', '| 组 | 总数 | PASS | FAIL | BLOCKED |','|---|---:|---:|---:|---:|']
for g in ['A','C','E','U','F','N']:
    c=groups[g];lines.append(f"| {g} | {sum(c.values())} | {c['PASS']} | {c['FAIL']} | {c['BLOCKED']} |")
lines += [f"| 总计 | 135 | {counts['PASS']} | {counts['FAIL']} | {counts['BLOCKED']} |",'','## 逐编号最终台账','',
'事件计数已对累计JSON去重并保留命令之间的异步事件。同型同值次数包含合法重复动作/新会话，不自动等同异常重复。空载荷事件按触发动作及状态轨迹核对；有直接状态标量的事件逐条比较。详表 `rerun-event-review.json` 保存样例、全部来源、差异及原命令上下文。',
'','| 编号 | 结论 | 本次原因与证据 |','|---|---|---|']
lines += [f'| {i} | {s} | {d.replace(chr(124),chr(47))} |' for i,s,d in rows]
lines += ['','## 上次23个FAIL与5个BLOCKED逐条对比','', '| 编号 | 上次 | 本次结论 | 变化 | 原因与证据 |','|---|---|---|---|---|']
for i in old_problem:
    s,d=verdicts[i]
    change='已修复/解除阻塞（debug补测）' if old_status[i]=='BLOCKED' and s=='PASS' else '已修复' if s=='PASS' else '仍失败' if s=='FAIL' else '仍阻塞'
    if i in ['F8','N19','U7'] and s=='PASS':change+='（验证器/判据纠正，真机重测）'
    lines.append(f'| `{i}` | {old_status[i]} | {s} | {change} | {d.replace(chr(124),chr(47))} |')
lines += ['','## 上次PASS、本次FAIL（新增回归观测）','',
'“新增”指本次台账新增FAIL，不等同已经定位为最近提交引入；没有使用静态代码来证明代码回归。', '', '| 编号 | 本次 | 原因与证据 |','|---|---|---|']
for i in regressions:lines.append(f'| `{i}` | FAIL | {verdicts[i][1]} |')
lines += ['', '其中A15/F5是同一个真实组合功能缺口，已在全新进程复现；E.MovaQualityChange是本次补充质量state字段后首次捕获的接收快照不符，旧验证器未记录该标量，因此不能断言其代码引入时间。',
    '新增阻塞：'+(', '.join(new_blocked) if new_blocked else '无')+'。',
    '', '## 本次FAIL最小复现与分类','', '| 涉及编号 | 分类 | 最小复现、实际结果与原因判断 |','|---|---|---|',
    '| A15 / F5 | 真实UI集成缺陷 | 全新api进程，`mini.show(api)`→`api.enterPip()`→am start展开。mini=false/pip=false，但controller showing=true/persistent，小窗仍可见。`rerun-mini-pip-repro-expanded.json/png`；Host依据controller api/mount绘制，API清mini位未收起controller。责任衔接点已缩小，未修库。 |',
    '| A17 / F3 | 真实续播缺陷（间歇） | `new case=hls cutover=true`，原生进度>=8s后交替360p/180p五次。长进程run3目标10183ms，两次RESTART均23ms，15s无目标附近落点，continued14623ms。`rerun-batch17-hls-playing-cutover.json`。40次合计仅1次失败仍必须FAIL；疑似duration/首呈现竞态仍有未覆盖分支，未插桩定因，不把推测写成已定位根因。 |',
    '| C16 | 真实原生TLS兼容缺陷（责任层未定） | tlsVerify=true且CA正确，打开带实时戳的合法IP SAN本地MP4/HLS失败；同CA localhost DNS证书成功，OpenSSL两者OK。`rerun-final-tls-probe.json`与`rerun-openssl-verify.txt`。不凭记忆归责某版mbedtls。 |',
    '| A1 | 矩阵流契约差异 | 两实现读取四流isBroadcast为true/false/true/false；多订阅与关闭实测正常。`rerun-batch15-basic/basic-cutover.json` STREAM_FLAGS。 |',
    '| A2 / E.MovaBufferChange / E.MovaSizeChange / E.MovaQualityChange | 矩阵接收快照契约差异 | event订阅内立即读state并保留载荷。Buffer、Size与Quality存在不符；Quality在ABR序列收到“自动”时state为360p。`rerun-event-review.json`含原ms/engine/原命令/完整state。差异真实，但不能直接推出画面错误或新的代码回归。 |',
    '| A5 / N12 | 矩阵同步/错误契约差异 | 可见视频640x360后`f=api.open(other);`立即读仍旧宽高/时长，再await才异步归零；恢复关闭404返回true，error另发事件。`rerun-native-engine/cutover-open-sync.json`、`rerun-extra-edges.json`。与N8 true=接受相容，不应把true当播放成功。 |',
    '| A12 | 边界/能力假设差异 | 在真实画面上setZoom(-1/0/100)，state保留输入，0可塌缩；maxZoom只控制手势。`rerun-batch3-05..10-zoom-*`。保留非法值无保护现象，不将其等同有效输入播放故障。 |',
    '| A23 | 生命周期契约差异 | audioOnly普通/代理open后连续dispose两次，第二次抛disposed。首次销毁/8流关闭、120轮完成。`rerun-batch15-basic/basic-cutover/dispose120.json`。公开生命周期约定一次销毁，矩阵额外要求幂等。 |',
    '| C3 / U6 | 能力假设差异 | 全尺寸前台视频长按1800ms，rate仍1，无长按倍速。双击实际seek、左右及重映射有效。`rerun-batch18-longpress-during/after.json`、`rerun-batch22-remap*`。 |',
    '| C6 | 能力假设差异 | 宿主items弹幕真实滚动，但无发送接口/输入框。`rerun-safe-visual-danmaku.png`，当前设计display-only。 |',
    '| C8 | 能力假设差异 | 自然连播与NextUp立即播放有效，但卡片无数字倒计时。`rerun-safe-visual-nextup.png`、`rerun-extra-playlist.json`。 |',
    '| U3 | 能力假设差异 | 真路由MovaPlayer顶栏无返回按钮；Android BACK退出正常。`rerun-safe-visual-route-player/route-back.png`。 |',
    '| U5 | 能力假设差异 | 按语义1x点击，rate变1.25而未弹菜单。`rerun-safe-visual-speed-button.json/png`。中心播放与HUD通过不能代替菜单子项。 |',
    '| E1 | 意图事件顺序与矩阵箭头差异 | 完整自然生命周期中Play先于Ready/FirstFrame。`rerun-batch15-lifecycle.json`；Play是意图，不是首帧。 |',
    '', '## BLOCKED条件与已测子项','',
    '- **A31/C7**：仍缺真实识别模型和下载服务；设备旧seed目录不存在。已测noEngine/disabled、失败回滚重试；未测真实识别、模型下载完整失败链、SRT导出/分块存储。未把注入Noop当真实转写。',
    '- **C2**：仍缺按behind URL返回历史且可控卡顿的服务。已测FLV/HLS与本地DVR、12s窗口/behind/backEdge/durationStep；历史urlBuilder、windowResolver与autoBackToLiveOnStall完整联动未完成。',
    '- **F15**：仍缺可达WHEP publisher/信令和UDP/relay链。`rerun-external-prerequisites.json`记录HTTP拒连和端口探测，TCP探测不冒充UDP可用；选项读回不冒充15s播放。',
    '- **N22已解除**：当前SDK的debug APK在真机启用断言，两个非法构造均捕获；其余异步hooks/轴向/crop/STT回滚/慢VTT换源竞态均有本次设备证据。不再尝试已知不支持的AOT enable-asserts。',
    '- **N18本次新增阻塞**：初轮没有独立的小窗自动暂停守卫联动证据，最终核对后补建V11M/V10C验证页。安装成功后、起测前检查变为isKeyguardShowing=true，驱动在启动前拒绝执行；未尝试唤醒/解锁、未产生锁屏渲染结论。已测部分见台账，缺少的mini守卫子项不拿纯逻辑单测补PASS。',
    '', '## 验证器问题、作废证据与测量边界','',
    '- 初轮V6以第一个buffering=true计时，出现一次offset2757ms；连续区间补测5/5通过，捕捉到true→false→约2.8s后true，最终期限offset仅1/14/2/1/1ms。这是计时锚点问题，不能再误报续播回零。上次Stamped/indexOf旧错误也没有重用。',
    '- review V10/V10x/V11 的restoredPortrait=false保留原始FAIL；原生已FULL_USER，系统自动旋转开、userRotation0。把自动等同竖屏是验证器假设。交接期间全屏/方向/系统栏及显式方向API另有通过读回。`rerun-review-rotation-window.txt`。',
    '- 旧视觉脚本把固定(600,230)点到PiP，之后触点落到其他应用；**rerun-batch25及rerun-batch28在该误触后的视觉/竞态结论全部作废**，未用其截图判PASS。安全重跑改用1x/立即播放/跳过语义，输入前检查原生测试包前台且全尺寸；有效文件为rerun-safe-visual、rerun-safe-transition及rerun-manual2。误触留下的安装提示未作确认，测试包最终返回HOME。',
    '- 慢VTT必须证明确有在途请求：BEGIN1793097684.006 < 换源1793097684.960 < END1793097686.514；换源后非空旧thumb0。`rerun-service-1.log`、`rerun-safe-transition-stale-audit.json`。不以“没看到图”代替丢弃旧结果验证。',
    '- 旧subtitle suite只完成部分后未发完成标记/切换停滞，completed=false未用于F11；以已修正的HTTP外挂字幕、先卸载再dispose的rerun-extra-subtitles四格式CHECK/原生sub-text/PNG为准。无screenrecord继续用PNG；驱动已限制只消费当前命令的MEM/SUBTITLE标记，避免重拍历史字幕。',
    '- S1的9个严格信号探针FAIL均为grace≈5s，但原生解码属性约百余ms恢复；S6强制绕过策略对无音轨流进muted仍EOF/重载，3/3探针FAIL。均如实保留于rerun-keepalive-core.log；它们不等同默认引擎守卫失效。F6按矩阵状态迁移/恢复/后台/位置要求判定，通过同时保留性能/信号缺口。',
    '- 20s待机漂移149/625/567ms，均值447ms；无待机对照2/43/-5ms，绝对均值16.7ms。不能据此宣布Windows60s漂移已修。CPU剔除每阶段边界±2s，完整样本与均值见rerun-cpu-review.json；USB供电不推出电池结论。120轮RSS197332992→222294016bytes，尾部仍有增长，仅报告趋势，不声称绝无泄漏。',
    '- U7纠正的是上一轮把C8数字倒计时要求重复扩展到U7：本次广告倒计时、点击和跳过均实测成功，C8继续FAIL。其余不存在的菜单、返回、长按、发送能力仍按矩阵字面FAIL，没有静态阅读补PASS。',
    '- CLAUDE中的F3“已修、15/15”不能覆盖本次间歇反例；V6续播已确认；PiP退出state与广告rate/pod旧问题未复现。Darwin瘦身包仍待Mac验证，本次不涉及。',
    '', '## 收尾与复跑入口','',
    '第一次收尾已返回HOME且亮屏解锁，见`rerun-final-window.txt`。随后N18补测前设备变为锁屏，按约束停测；最终状态以`rerun-final-locked-window.txt`为准（isKeyguardShowing=true）。独立包再次force-stop，pid为空（rerun-final-locked-process.txt）；USB常亮原值7、媒体音量原值6/20均已原生确认，见`rerun-final-locked-power.txt`、`rerun-final-locked-volume.txt`。测试夹具含临时守卫源均已停止，见`rerun-final-services.txt`，adb映射保留。锁屏发生在已完成主批次及N22断言之后，不反向作废有各自解锁证据的已完成测试；N18补测明确没有运行。',
    '', '复跑入口：先起夹具并确认亮屏解锁，隔离release走`coverage_build.py lib/main_coverage_suite.dart`，再`coverage_suite_device.py api`；HLS用`coverage_device.py new --arg case=hls --arg cutover=true --name rerun-<新名>`；新Mini/PiP缺口按本节最小复现，不修库。安全视觉用rerun_visual_safe.py（包含前台/尺寸检查与语义触点），不要重用旧倍速坐标。',
    '', '## 逐批计划与检查点（执行原始追加记录）','',journal]
final='\n'.join(lines)+'\n'
final=re.sub(r'\n{3,}','\n\n',final)
D.write_text(final,encoding='utf-8')
(O/'rerun-final-ledger.json').write_text(json.dumps({'rows':[{'id':i,'status':s,'evidence':d} for i,s,d in rows],'counts':counts,'groups':groups,'fixedPreviousFailures':fixed,'regressions':regressions,'newBlocked':new_blocked},ensure_ascii=False,indent=2),encoding='utf-8')
print('FINAL',dict(counts),'FIXED',fixed,'REGRESSIONS',regressions)
