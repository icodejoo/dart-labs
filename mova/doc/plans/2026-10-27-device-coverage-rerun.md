# 2026-10-27 Android 完整覆盖复跑结果

最终135项：**PASS 109 / FAIL 21 / BLOCKED 5**。上次107/23/5。

全部本次证据位于 `example/tool/coverage_evidence/`，下表文件名均相对该目录；均用 `rerun-` 前缀，未覆盖上次结果。仅新结果与验证页/脚本有本任务修改，库和测试未修复。

## 基线、构建与设备

- 7NQBB23606003715，STG-AL00 Android12/arm64；测前及各驱动确认亮屏解锁。`rerun-preflight-window/audio/power.txt`、`rerun-device-build.json`。起测USB常亮7、媒体speaker6/20。
- Flutter3.47.0 / Dart3.13.0。`flutter analyze lib test` **1 error + 1 warning（2 issues），exit1**；`flutter test` **1424通过、1测试文件加载失败，exit1**。已有 `test/core/engine_test.dart` 的 `_RecordingBrightPort` 在1959/1978重复定义，整文件未加载；不是79个测试断言失败，不能把上次1503或文档1510算成本次通过。原始 `rerun-baseline-analyze/test.log`，未改该文件。
- 修改的4个验证页单独analyze **0 issues，exit0**，`rerun-verifier-analyze.log`；额外守卫页变更后he_auto.dart再分析亦0 issues，`rerun-he-extra-analyze.log`。release隔离包构建/安装成功，真实libmpv6357872bytes、SHA256 `798cde9e27e3761dd5f8f065693e4669b5499d5807618f81a74e0d3a88dc230b`。主批次APK SHA256 `d4535851ebe9074860ba9772f501253d2043620655d61f40e320df32b98537ab`，保留原包`rerun-main-release.apk`，元数据`rerun-final-build-manifest.json`。最后安装的独立守卫补测APK见`rerun-guard-build-manifest.json`，该补测因锁屏未启动。
- 所有媒体/渲染判据来自release真实事件/状态/原生读回；仅N22构造断言用独立debug VM，`rerun-debug-build.log`、`rerun-debug-assert.*`。main库无改动。
- 编号仍为A33+C17+E37+U9+F16+N23=135。沿用旧编号：E.MovaSwapChange对应现MovaCutoverChange，E.MovaStandbyChange/Resume对应现MovaKeepAliveChange/Resume；只映射名称，不增减编号。

## 最终分组汇总

| 组 | 总数 | PASS | FAIL | BLOCKED |
|---|---:|---:|---:|---:|
| A | 33 | 25 | 7 | 1 |
| C | 17 | 11 | 4 | 2 |
| E | 37 | 33 | 4 | 0 |
| U | 9 | 6 | 3 | 0 |
| F | 16 | 13 | 2 | 1 |
| N | 23 | 21 | 1 | 1 |
| 总计 | 135 | 109 | 21 | 5 |

## 逐编号最终台账

事件计数已对累计JSON去重并保留命令之间的异步事件。同型同值次数包含合法重复动作/新会话，不自动等同异常重复。空载荷事件按触发动作及状态轨迹核对；有直接状态标量的事件逐条比较。详表 `rerun-event-review.json` 保存样例、全部来源、差异及原命令上下文。

| 编号 | 结论 | 本次原因与证据 |
|---|---|---|
| A1 | FAIL | 两实现broadcast=[true,false,true,false]；两订阅均收到、八订阅均关闭。标志契约差异。rerun-batch15-basic.json、rerun-batch15-basic-cutover.json。 |
| A2 | FAIL | 接收事件时state快照仍可不同：Buffer/Size及本次新增Quality对账差异；详见rerun-event-review.json的逐条mismatchExamples。 |
| A3 | PASS | audioOnly handle=null/size0x0；lazy构造0/open0/首次handle1；真实视频挂树非空、宽高640x360。rerun-batch15-lazy/basic、rerun-batch16-engine-start.json。 |
| A4 | PASS | 普通/代理pipSupported=true且state一致。rerun-batch15-basic.json、rerun-batch15-basic-cutover.json CHECK A4。 |
| A5 | FAIL | 两实现VIDEO_OPEN_SYNC仍640x360/duration40000/rendered=true；404恢复关时accepted=true、不抛，随后error事件。同步/错误契约差异，N8接受语义仍通过。rerun-native-engine-open-sync.json、rerun-native-cutover-open-sync.json、rerun-extra-edges.json。 |
| A6 | PASS | 两实现play/pause/playOrPause、重复pause与独立intent检查通过，真实事件与进度均保存。rerun-batch15-basic.json、rerun-batch15-basic-cutover.json。 |
| A7 | PASS | 两实现5个精确seek误差0；负值/seekBy、加载中7s寄存与超时长钳制有实际读数；直播禁seek。rerun-batch15-basic/basic-cutover/live-*.json、rerun-extra-edges.json。超界seek仅测钳制，不用来伪造自然EOF。 |
| A8 | PASS | 两实现越界state钳0..100；逐值原生媒体音量读回0/中间/20（1%受系统离散级量化）。rerun-batch15-basic.json、rerun-batch15-basic-cutover.json、rerun-native-engine/cutover-volume*.json及.native.txt。 |
| A9 | PASS | 两实现clamp全部true；原生brightness：输入-1/0/.25/.75/1/2→0/0/.25/.75/1/1；代理手势窗口sbrt=.7530023。rerun-extra-edges.json、rerun-batch16-cutover-left-check.window.txt。 |
| A10 | PASS | 0.5/1/1.5/2、非法-1/0拒绝、换源保留；广告1x并恢复2x/1.5x各3轮。rerun-batch15-basic.json、rerun-batch15-basic-cutover.json、rerun-batch11-review.log V13a/b。 |
| A11 | PASS | 两实现contain/cover/fill状态、事件及真实画面不同；见rerun-batch16-engine/cutover-fit-*.png/json、rerun-safe-contact-1.jpg。 |
| A12 | FAIL | setZoom(-1/0/100)仍接受并改变画面，未使用手势maxZoom钳制。矩阵边界假设差异；非法低值可使画面塌缩。rerun-batch3-05-zoom--1.json、rerun-batch3-06-zoom-0.json、rerun-batch3-09-zoom-100.png。 |
| A13 | PASS | 两实现锁定后左右触摸不改变亮度/音量，解锁后可用，LockChange/state一致。rerun-batch16-checks.json及locked/unlock原始文件。 |
| A14 | PASS | 两实现进/出全屏状态与事件、系统栏隐藏/恢复，进入按宽高比横屏；退出原生恢复FULL_USER。rerun-batch16-*-fullscreen-*.json/window.txt；方向探针的“自动必竖屏”误判另列。 |
| A15 | FAIL | 真实MiniHost→enterPip后mini=false但controller仍showing=true/persistent；展开后pip=false/mini=false而小窗仍可见。全新进程复现，真实UI与状态衔接缺口。rerun-mini-pip-repro-show/enter/holding/expanded.json/png/activity.txt。 |
| A16 | PASS | 两实现landscape/portrait/auto事件及真实窗口尺寸/原生方向有读回。rerun-batch16-*-orientation-*.json/window.txt、rerun-batch3-24..26-orientation-*。自动不承诺强制竖屏。 |
| A17 | FAIL | HLS累计39/40切档通过，成功落点误差均0ms；长进程代理run3 target10183→RESTART[23,23]，未续播。ABR真实限速降档通过但不抵消失败。rerun-measured-summary.json、rerun-batch17-hls-playing-cutover.json、rerun-final-hls-cutover/abr.json。 |
| A18 | PASS | 进入true、原生pinned；展开及真正X关闭均收到PipChange(false)/state复位。rerun-manual-pip-enter/expanded/third/x-confirmed.json/activity.txt/png。先前x-closed只是菜单消失，未当关闭证据。 |
| A19 | PASS | 两实现reload真实重载，进度归零及事件序列已记录。rerun-batch15-basic.json、rerun-batch15-basic-cutover.json RELOAD。 |
| A20 | PASS | 真实滑动HLS三轮：DVR窗口12s，seek后behind约8s，backEdge position12000、LiveEdgeReach；点播回边缘无副作用。rerun-live-0/1/2-behind/backedge.json、rerun-batch15-basic.json。此项是本地DVR，不冒充按URL历史服务。 |
| A21 | PASS | hide/show sticky、HUD文字类型、dragging/previewAt，自动隐藏及sticky延迟检查通过。rerun-batch15-basic/basic-cutover、rerun-batch16-checks、rerun-manual2-preview-held/released.json。 |
| A22 | PASS | custom覆盖probe42与内置play透传probe43，value相等/hash检查通过。rerun-batch15-basic.json、rerun-batch15-basic-cutover.json CHECK A22。 |
| A23 | FAIL | 两实现第二次dispose仍抛[Player] has been disposed；首次关闭及disposed open=false正常，120轮首次创建/销毁完成。二次调用安全的矩阵契约差异。rerun-batch15-basic.json、rerun-batch15-basic-cutover.json、rerun-batch15-dispose120.json及round*.meminfo.txt。 |
| A24 | PASS | 关闭直通、开启prepare/commit/abandon、短窗口/超时降级、epoch与影子释放7项检查通过。rerun-batch15-cutover.json；真实视频换指另见rerun-batch11-review.log。 |
| A25 | PASS | off/holding/fallback/resuming、pause结束、默认maxDuration30s到期、allowHls两分支各3轮；硬解恢复20/20、后台降级/恢复、重载与隐藏换源均完成。rerun-keepalive-core.log、rerun-batch8-keepAlive-native.log、rerun-batch16-checks.json。grace及强制无音轨探针FAIL另列，不隐藏。 |
| A26 | PASS | A/B挂载互斥、hide/close/setRect、回调、真实拖动/吸边/转屏均有证据。安全实触：left12→90ms甩动left231.5294且showing=true，MINI_TAPPED与MINI_CLOSED实际到达。rerun-batch16/22-mini*、rerun-manual2-mini-*.json/png。 |
| A27 | PASS | 默认关、pre/mid/post/manual、deferred、clicked/skip、pod、waitsFor三层覆盖；两种404失败策略完成。rerun-batch15-ads/adResume.json、rerun-extra-ad-failure.json、rerun-batch11-review.log。 |
| A28 | PASS | next/previous/jumpTo/边界及自然完播自动下一条3项检查通过；拒绝jumpTo不前进另见hooks。rerun-extra-playlist.json、rerun-batch15-hooks/hooks-cutover.json。 |
| A29 | PASS | 100次串行+20次并发滑动最终active120、原生池3引擎，回收完成；实际Feed触摸另测。rerun-batch15-feed.json、rerun-batch22-feed*.json/png。 |
| A30 | PASS | VTT优先/crop不缓存、实际原生抽帧、内存2上限、磁盘/内存命中、cancel/clear、never阻断；真实connectivity与拒连VTT抽帧兜底通过。rerun-batch15-preview-*.json、rerun-extra-preview-probe/offline.json及thumb*.jpg。 |
| A31 | BLOCKED | 已测disabled/noEngine阻断、注入引擎首启失败回滚/二次重试。未提供真实识别模型/模型下载服务，设备旧seed目录不存在；真实转写、下载失败链、SRT导出/分块落盘未完成。rerun-batch15-stt.json、rerun-stt-device-seed.txt。 |
| A32 | PASS | 普通/代理各9项异步hooks检查通过：放行/拒绝/被取代、pause期间stalePlay、换源staleSeek、异常后继续播放及error隔离。rerun-batch15-hooks/hooks-cutover.json。 |
| A33 | PASS | 真机安装MovaTesting后平台端口空操作、stagedSourceOptions读回通过；Android实际转场/换指未出现Windows快照路径副作用。rerun-batch15-testing.json、rerun-batch11-review.log及rerun-batch16-view-*.json。 |
| C1 | PASS | VTT优先/crop不缓存、实际原生抽帧、内存2上限、磁盘/内存命中、cancel/clear、never阻断；真实connectivity与拒连VTT抽帧兜底通过。rerun-batch15-preview-*.json、rerun-extra-preview-probe/offline.json及thumb*.jpg。 |
| C2 | BLOCKED | 已测真实FLV/HLS durationStep、12s本地DVR、behind/回边缘三轮；未提供按behind URL返回历史且可控卡顿服务。urlBuilder历史语义、自定义windowResolver/autoBackToLiveOnStall完整联动未完成。rerun-live-*.json、rerun-batch15-live-step*.json；条件与上次相同。 |
| C3 | FAIL | 真实长按1800ms期间仍1x，当前无长按倍速；侧别/轴向改配、seek、默认双击seek、Douyin Feed点击/like及锁定屏蔽已实测。能力假设差异。rerun-batch18-longpress-*.json、rerun-batch22-remap/feed*.json、rerun-batch16-checks.json。 |
| C4 | PASS | 真实HTTP ts限速触发MovaAbrDownShift，高→低后紧接手切，reset生效；两轮有实际轨迹。rerun-batch15-abr.json、rerun-final-abr.json；使用threshold1门控配置，不宣称默认阈值性能。 |
| C5 | PASS | showOnStart、800ms自动隐藏、sticky保持与皮肤控件显隐通过；原始uiStates/截图齐全。rerun-batch16-checks.json、rerun-batch18-autohide.json、rerun-safe-visual-*.png。 |
| C6 | FAIL | 真实滚动弹幕可见，但发送API/输入框未提供（display-only），矩阵要求的发送不能满足。rerun-safe-visual-danmaku.png/json。 |
| C7 | BLOCKED | 已测disabled/noEngine阻断、注入引擎首启失败回滚/二次重试。未提供真实识别模型/模型下载服务，设备旧seed目录不存在；真实转写、下载失败链、SRT导出/分块落盘未完成。rerun-batch15-stt.json、rerun-stt-device-seed.txt。 |
| C8 | FAIL | 自动连播、NextUp卡片/取消/立即播放实测；卡片没有数字倒计时。rerun-extra-playlist.json、rerun-safe-visual-nextup.png、rerun-safe-visual-nextup-click.json。 |
| C9 | PASS | 默认关、pre/mid/post/manual、deferred、clicked/skip、pod、waitsFor三层覆盖；两种404失败策略完成。rerun-batch15-ads/adResume.json、rerun-extra-ad-failure.json、rerun-batch11-review.log。 |
| C10 | PASS | COVERAGE FIT文案实际可见；60/8/红色spinner及开关、错误层显隐、Minimal无栏无手势通过。rerun-safe-visual-controls/spinner-custom/spinner-disabled/error-visible/error-disabled.png，controls-*.xml与组件清单。 |
| C11 | PASS | 关闭直通、开启prepare/commit/abandon、短窗口/超时降级、epoch与影子释放7项检查通过。rerun-batch15-cutover.json；真实视频换指另见rerun-batch11-review.log。 |
| C12 | PASS | A/B挂载互斥、hide/close/setRect、回调、真实拖动/吸边/转屏均有证据。安全实触：left12→90ms甩动left231.5294且showing=true，MINI_TAPPED与MINI_CLOSED实际到达。rerun-batch16/22-mini*、rerun-manual2-mini-*.json/png。 |
| C13 | PASS | qoe:false零QoE；四类结束原因、restart TTFF、cache卡顿/截断均取得真实报告。完整释放卡顿sessionEnd stallCount1/stallMs5496。rerun-batch15-qoe-*.json、rerun-batch17-qoe-failed/qoe-stall-release.json；custom另见A22。 |
| C14 | PASS | 默认关，有限重试/地址切换、超时和源级mpv选项读回、默认直播持续重连/legacy分支均完成。rerun-batch15-options/recovery*.json、rerun-extra-failover/live-backoff-*.json、rerun-he-recovery.log。 |
| C15 | PASS | off/holding/fallback/resuming、pause结束、默认maxDuration30s到期、allowHls两分支各3轮；硬解恢复20/20、后台降级/恢复、重载与隐藏换源均完成。rerun-keepalive-core.log、rerun-batch8-keepAlive-native.log、rerun-batch16-checks.json。grace及强制无音轨探针FAIL另列，不隐藏。 |
| C16 | FAIL | 实时戳最终矩阵35/40；合法IP SAN verify=true仍5/5拒绝。独立探针合法DNS6/6通过、合法IP0/6；CA属性正确，OpenSSL两证书OK。原生TLS兼容缺陷，未定位具体责任层。rerun-final-tls.json、rerun-final-tls-probe.json、rerun-openssl-verify.txt。 |
| C17 | PASS | alternatives/uris/pick/sameAs、headers、sourceIndex；network/cache/demux按源应用并恢复，默认白名单保留，非法项不写error，WHEP微秒选项读回。rerun-batch15-options.json及服务端HEADERS、rerun-extra-failover.json。 |
| E.MovaReady | PASS | MovaReady：去重283次，同型相邻同值55次；标量对账0条/差异0条；样例payload={}，动作={"group":"basic"}。证据rerun-batch15-basic.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaSourceChange | PASS | MovaSourceChange：去重283次，同型相邻同值3次；标量对账0条/差异0条；样例payload={"uri":"http://127.0.0.1:18080/vod.mp4?t=1793092972283789"}，动作={"group":"basic"}。证据rerun-batch15-basic.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaPlay | PASS | MovaPlay：去重338次，同型相邻同值125次；标量对账0条/差异0条；样例payload={}，动作={"group":"basic"}。证据rerun-batch15-basic.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaPause | PASS | MovaPause：去重405次，同型相邻同值177次；标量对账0条/差异0条；样例payload={}，动作={"group":"basic"}。证据rerun-batch15-basic.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaDone | PASS | MovaDone：去重14次，同型相邻同值0次；标量对账0条/差异0条；样例payload={}，动作={"group":"new","case":"lifecycle"}。证据rerun-batch15-lifecycle.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaSeek | PASS | MovaSeek：去重41次，同型相邻同值0次；标量对账0条/差异0条；样例payload={"target":5000}，动作={"group":"basic"}。证据rerun-batch15-basic.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaSeeked | PASS | MovaSeeked：去重41次，同型相邻同值0次；标量对账0条/差异0条；样例payload={"position":5000}，动作={"group":"basic"}。证据rerun-batch15-basic.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaBufferChange | FAIL | MovaBufferChange：去重1041次，同型相邻同值1次；标量对账1041条/差异8条；样例payload={"buffering":true}，动作={"group":"basic"}。证据rerun-batch15-basic-cutover.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaDurationChange | PASS | MovaDurationChange：去重908次，同型相邻同值0次；标量对账908条/差异0条；样例payload={"duration":40000}，动作={"group":"basic"}。证据rerun-batch15-basic.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaFirstFrame | PASS | MovaFirstFrame：去重189次，同型相邻同值0次；标量对账0条/差异0条；样例payload={"sinceOpen":86,"signal":"restart"}，动作={"group":"basic"}。证据rerun-batch15-basic.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaSizeChange | FAIL | MovaSizeChange：去重602次，同型相邻同值0次；标量对账602条/差异25条；样例payload={"width":640,"height":0}，动作={"group":"new","case":"lazy"}。证据rerun-batch15-lifecycle.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaVolumeChange | PASS | MovaVolumeChange：去重276次，同型相邻同值9次；标量对账276条/差异0条；样例payload={"value":1.0}，动作={"group":"basic"}。证据rerun-batch15-basic.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaBrightChange | PASS | MovaBrightChange：去重404次，同型相邻同值8次；标量对账404条/差异0条；样例payload={"value":0.5}，动作={"group":"basic"}。证据rerun-batch15-basic.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaRateChange | PASS | MovaRateChange：去重13次，同型相邻同值0次；标量对账13条/差异0条；样例payload={"value":0.5}，动作={"group":"basic"}。证据rerun-batch15-basic.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaQualityListChange | PASS | MovaQualityListChange：去重10次，同型相邻同值0次；标量对账2条/差异0条；样例payload={"qualities":["自动:","360p:http://127.0.0.1:18084/high/index.m3u8","180p:http://127.0.0.1:18084/low/index.m3u8"]}，动作={"group":"new","case":"hls"}。证据rerun-batch15-hls.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaQualityChange | FAIL | MovaQualityChange：去重56次，同型相邻同值0次；标量对账10条/差异1条；样例payload={"quality":"自动"}，动作={"group":"new","case":"hls"}。证据rerun-final-abr.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaAbrDownShift | PASS | MovaAbrDownShift：去重2次，同型相邻同值0次；标量对账0条/差异0条；样例payload={"from":"360p","to":"180p"}，动作={"group":"new","case":"abr"}。证据rerun-batch15-abr.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaFitChange | PASS | MovaFitChange：去重43次，同型相邻同值0次；标量对账43条/差异0条；样例payload={"fit":"cover"}，动作={"group":"video","action":"snapshot","audio":"true"}。证据rerun-batch16-audio-start.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaZoomChange | PASS | MovaZoomChange：去重6次，同型相邻同值0次；标量对账6条/差异0条；样例payload={"zoom":-1.0}，动作={"group":"video","action":"zoom","value":"-1"}。证据rerun-batch3-05-zoom--1.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaLockChange | PASS | MovaLockChange：去重6次，同型相邻同值0次；标量对账6条/差异0条；样例payload={"value":true}，动作={"group":"video","action":"lock","value":"true"}。证据rerun-batch16-cutover-lock.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaFullScreenChange | PASS | MovaFullScreenChange：去重8次，同型相邻同值0次；标量对账8条/差异0条；样例payload={"value":true}，动作={"group":"new","case":"lifecycle"}。证据rerun-batch15-lifecycle.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaOrientationChange | PASS | MovaOrientationChange：去重33次，同型相邻同值0次；标量对账33条/差异0条；样例payload={"orientation":"landscape"}，动作={"group":"video","action":"orientation","value":"landscape"}。证据rerun-batch16-cutover-mini-landscape.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaPipChange | PASS | MovaPipChange：去重19次，同型相邻同值0次；标量对账19条/差异0条；样例payload={"value":true}，动作={"group":"video","action":"pip"}。证据rerun-batch18-pip-enter.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaMiniChange | PASS | MovaMiniChange：去重27次，同型相邻同值0次；标量对账27条/差异0条；样例payload={"mini":true}，动作={"group":"video","action":"miniPage"}。证据rerun-batch16-cutover-mini-page.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaTimeShiftChange | PASS | MovaTimeShiftChange：去重63次，同型相邻同值1次；标量对账63条/差异0条；样例payload={"behind":10000}，动作={}。证据rerun-batch16-keepAlive-on.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaLiveEdgeReach | PASS | MovaLiveEdgeReach：去重15次，同型相邻同值5次；标量对账0条/差异0条；样例payload={}，动作={"group":"new","case":"live","step":"0"}。证据rerun-batch15-live-step0-0.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaPreviewBlock | PASS | MovaPreviewBlock：去重4次，同型相邻同值3次；标量对账0条/差异0条；样例payload={"reason":"network"}，动作={"group":"new","case":"preview","mode":"blocked"}。证据rerun-batch15-preview-blocked.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaSttBlock | PASS | MovaSttBlock：去重3次，同型相邻同值0次；标量对账0条/差异0条；样例payload={"reason":"disabled"}，动作={"group":"basic"}。证据rerun-batch15-basic.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaSwapChange | PASS | MovaCutoverChange：去重40次，同型相邻同值0次；标量对账0条/差异0条；样例payload={"phase":"warming"}，动作={"group":"new","case":"cutover"}。证据rerun-batch15-cutover.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaErrorEvent | PASS | MovaErrorEvent：去重115次，同型相邻同值29次；标量对账0条/差异0条；样例payload={"error":"Failed to open http://127.0.0.1:18080/404.mp4?t=1793093002285605."}，动作={"group":"new","case":"hooks"}。证据rerun-batch15-hooks.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaPlayFailure | PASS | MovaPlayFailure：去重42次，同型相邻同值0次；标量对账0条/差异0条；样例payload={"kind":"nativeEndError","action":"MovaRecoveryAction.retry","attempt":1,"isLive":true,"sourceIndex":0}，动作={"group":"new","case":"recovery","mode":"liveDefault"}。证据rerun-batch15-recovery-liveDefault.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaRecovered | PASS | MovaRecovered：去重1次，同型相邻同值0次；标量对账0条/差异0条；样例payload={"attempts":1}，动作={"group":"new","case":"recovery","mode":"failover"}。证据rerun-extra-failover.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaFailover | PASS | MovaFailover：去重2次，同型相邻同值0次；标量对账0条/差异0条；样例payload={"from":0,"to":1,"uri":"http://127.0.0.1:18080/other404.mp4?t=1793093021692738"}，动作={"group":"new","case":"recovery","mode":"liveAlternatives"}。证据rerun-batch15-recovery-liveAlternatives.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaStandbyChange | PASS | MovaKeepAliveChange：去重6次，同型相邻同值0次；标量对账6条/差异0条；样例payload={"phase":"resuming","reason":"woke","mode":"null"}，动作={"group":"video","action":"keepAlive","value":"false"}。证据rerun-batch16-keepAlive-off.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E.MovaStandbyResume | PASS | MovaKeepAliveResume：去重1次，同型相邻同值0次；标量对账0条/差异0条；样例payload={"elapsed":1960,"signal":"MovaFirstFrameSignal.grace"}，动作={}。证据rerun-batch16-keepAlive-on2.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| E1 | FAIL | 真实Play意图事件早于Ready/FirstFrame，不满足矩阵示意箭头严格顺序。不是提前出画；自然Done1/无错误的生命周期仍通过F1。rerun-batch15-lifecycle.json。 |
| E2 | PASS | 两实现默认关闭功能事件count0、qoe:false无QoE。rerun-batch15-basic.json、rerun-batch15-basic-cutover.json。 |
| U1 | PASS | Player/View/Feed实际挂卸、surface、五皮肤/patch组件，View route/ticker与Impeller渲染均留有设备证据。rerun-batch16-view-*.json、rerun-batch16-*-customSurface/patch.png、rerun-batch22-feed*.json/png及safe视觉。 |
| U2 | PASS | Player/View/Feed实际挂卸、surface、五皮肤/patch组件，View route/ticker与Impeller渲染均留有设备证据。rerun-batch16-view-*.json、rerun-batch16-*-customSurface/patch.png、rerun-batch22-feed*.json/png及safe视觉。 |
| U3 | FAIL | 实际TopBar只有标题及功能按钮，没有返回按钮；Android BACK能退路由。能力假设差异。rerun-safe-visual-route-player.png、rerun-safe-visual-route-back.png及同前缀JSON；PiP/方向另见A16/A18。 |
| U4 | PASS | 真实live/VOD栏、底栏拖动与悬停彩色预览气泡通过。dragging=true、previewAt25987、previewCurrent20000；UP后释放。rerun-live-*-controls.png、rerun-manual2-preview-held/released.json/png。 |
| U5 | FAIL | 语义点击1x后直接1.25x、没有倍速菜单；CenterPlay实际点击播放，HUD另有真实手势读回。能力形态差异。rerun-safe-visual-speed-button.json、rerun-safe-visual-center-play.json及PNG、rerun-batch16-*-left/right*.png。 |
| U6 | FAIL | 真实长按1800ms期间仍1x，当前无长按倍速；侧别/轴向改配、seek、默认双击seek、Douyin Feed点击/like及锁定屏蔽已实测。能力假设差异。rerun-batch18-longpress-*.json、rerun-batch22-remap/feed*.json、rerun-batch16-checks.json。 |
| U7 | PASS | 弹幕/四格式字幕、NextUp立即播放、广告倒计时/点击/跳过、Feed输入均实际完成。rerun-safe-visual-*（SKIP_BUTTON=true）、rerun-extra-subtitles.*、rerun-batch22-feed*.json。上次把C8的NextUp数字倒计时缺失重复记到U7；本次按该组合中的广告倒计时判，纠正口径。 |
| U8 | PASS | A/B挂载互斥、hide/close/setRect、回调、真实拖动/吸边/转屏均有证据。安全实触：left12→90ms甩动left231.5294且showing=true，MINI_TAPPED与MINI_CLOSED实际到达。rerun-batch16/22-mini*、rerun-manual2-mini-*.json/png。 |
| U9 | PASS | HE前后台/route/Ticker/PiP各3轮，真实Feed滚动；View的RouteObserver与ticker路径通过。rerun-he-recovery.log、rerun-batch16-view-*.json、rerun-batch22-feed*.json。主观手感不伪造成人工评价。 |
| F1 | PASS | 真实open/播放/seek/rate/fullscreen/换源/自然Done/dispose无异常。rerun-batch15-lifecycle.json naturalDone1/errors0；E1的意图事件严格箭头另判。 |
| F2 | PASS | 真实滑动HLS三轮：DVR窗口12s，seek后behind约8s，backEdge position12000、LiveEdgeReach；点播回边缘无副作用。rerun-live-0/1/2-behind/backedge.json、rerun-batch15-basic.json。此项是本地DVR，不冒充按URL历史服务。 |
| F3 | FAIL | HLS累计39/40切档通过，成功落点误差均0ms；长进程代理run3 target10183→RESTART[23,23]，未续播。ABR真实限速降档通过但不抵消失败。rerun-measured-summary.json、rerun-batch17-hls-playing-cutover.json、rerun-final-hls-cutover/abr.json。 |
| F4 | PASS | 广告回正片5次原生续播误差全部0ms、epoch2；pod/失败降级/关闭态已测。rerun-batch15-adResume/cutover.json、rerun-batch11-review.log、rerun-extra-ad-failure.json。 |
| F5 | FAIL | 真实MiniHost→enterPip后mini=false但controller仍showing=true/persistent；展开后pip=false/mini=false而小窗仍可见。全新进程复现，真实UI与状态衔接缺口。rerun-mini-pip-repro-show/enter/holding/expanded.json/png/activity.txt。 |
| F6 | PASS | off/holding/fallback/resuming、pause结束、默认maxDuration30s到期、allowHls两分支各3轮；硬解恢复20/20、后台降级/恢复、重载与隐藏换源均完成。rerun-keepalive-core.log、rerun-batch8-keepAlive-native.log、rerun-batch16-checks.json。grace及强制无音轨探针FAIL另列，不隐藏。 |
| F7 | PASS | qoe:false零QoE；四类结束原因、restart TTFF、cache卡顿/截断均取得真实报告。完整释放卡顿sessionEnd stallCount1/stallMs5496。rerun-batch15-qoe-*.json、rerun-batch17-qoe-failed/qoe-stall-release.json；custom另见A22。 |
| F8 | PASS | 坏地址nativeEndError、三轮failover/giveUp、多地址及卡顿后续播通过。最终V6连续区间5/5，位置误差40/40/0/0/40ms，平均24ms；超时offset1/14/2/1/1ms，平均3.8ms。rerun-he-v6-final.log、rerun-he-recovery.log、rerun-extra-failover.json。旧V6计时/锚点误判已纠正。 |
| F9 | PASS | audioOnly handle=null、size0x0、进度/AudioTrack；与视频窗口的实际截图和CPU/内存对照已采样。rerun-batch15-basic.json、rerun-batch16-audio/video*.json/png/cpu.txt。未冒充人耳音质评价。 |
| F10 | PASS | VTT优先/crop不缓存、实际原生抽帧、内存2上限、磁盘/内存命中、cancel/clear、never阻断；真实connectivity与拒连VTT抽帧兜底通过。rerun-batch15-preview-*.json、rerun-extra-preview-probe/offline.json及thumb*.jpg。 |
| F11 | PASS | 四格式SRT/ASS/WebVTT外挂及mov_text内封：4个CHECK全部true、原生sub-text非空/decoder轨道与实际字幕PNG齐全。rerun-extra-subtitles.json、rerun-extra-subtitles.srt.png、rerun-extra-subtitles.ass.png、rerun-extra-subtitles.vtt.png、rerun-extra-subtitles.movtext.png。 |
| F12 | PASS | 四模式各3轮top/batterystats及音频模式对照完成。单核均值normal99.64%、muted7.70%、decodeOnly112.67%、pause6.50%。rerun-cpu-review.json、rerun-batch9-keepAlive-cpu-drift.samples.txt、rerun-batch16-audio/video.cpu.txt。USB供电，不推导电池能耗。 |
| F13 | PASS | feed100+20次最终3引擎，三引擎RESTART互不串扰；销毁最大帧间隔46/55ms<100。rerun-batch15-feed.json、rerun-batch12-pump.log；120轮仅报告资源趋势，不声称绝无泄漏。 |
| F14 | PASS | release RESTART与END_FILE实际到达，qoe:false建客户端0，created14/destroyed14。rerun-batch12-pump.log、rerun-he-recovery.log。 |
| F15 | BLOCKED | WHEP端点38889/test/whep拒连，相关端口探测不可用；缺publisher/信令/UDP38189及relay38190服务。只完成WHEP选项读回，未完成15s播放。rerun-external-prerequisites.json、rerun-batch15-options.json；与上次条件相同。 |
| F16 | PASS | 历史PiP退出state已修复，两退出路径到false；广告方向/内容倍速恢复、pod第二条换指已测各3轮。rerun-manual-pip-*.json、rerun-batch11-review.log。此项表示历史缺陷复核完成；新MiniHost/PiP残留另列A15/F5。 |
| N1 | PASS | 真实默认黑洞5259/5279/5279ms，均值5272.3ms；network2s为2249/2237/2263ms，均值2249.7ms。65s是Dart兜底非mpv实际默认。原生整数/WHEP微秒/源优先读回见rerun-batch15-options与hang-*.json。 |
| N2 | PASS | 派生HTTP65s/WHEP85s/10s、override/clear、stallWatchdog关闭真卡顿均实测；END_FILE先判。rerun-batch15-options/watchoff/hang*.json、rerun-he-v6-final.log连续缓冲期限。 |
| N3 | PASS | liveDefault第三次仍重试、legacy有限放弃、alternatives每地址策略；cap7退避三轮间隔均值1038.67/2107.33/4070.67/8058.33/15067/15086.67/15103ms，符合1/2/4/8/15/15/15s。rerun-reconnect-summary.json、rerun-extra-live-backoff-0/1/2.json、rerun-batch15-recovery-live*.json。 |
| N4 | PASS | alternatives/uris/pick/sameAs、headers、sourceIndex；network/cache/demux按源应用并恢复，默认白名单保留，非法项不写error，WHEP微秒选项读回。rerun-batch15-options.json及服务端HEADERS、rerun-extra-failover.json。 |
| N5 | PASS | 404/拒连均真实nativeEndError，HE V8各3轮：404为73/86/96ms，均值85ms；拒连86/88/85ms，均值86.33ms。recovery错误订阅不代替精确首帧，V1 precise on/off各3轮。rerun-he-recovery.log、rerun-he-firstframe.log。 |
| N6 | PASS | Recovered后error=null、giveUp后buffering=false与false事件；真实加载在途END_FILE可处理。rerun-extra-failover.json、rerun-batch15-recovery*.json及hang*.json。 |
| N7 | PASS | 真实直播durationStep0/2000各3轮事件时间戳、首非零/open归零放行；VOD不受节流。rerun-batch15-live-step*.json、rerun-batch15-basic.json。 |
| N8 | PASS | 普通/代理接受true、拒绝/被取代/已销毁false、playlist拒绝不前进。rerun-batch15-hooks/hooks-cutover.json；404 accepted不表示播放成功。 |
| N9 | PASS | 进入true、原生pinned；展开及真正X关闭均收到PipChange(false)/state复位。rerun-manual-pip-enter/expanded/third/x-confirmed.json/activity.txt/png。先前x-closed只是菜单消失，未当关闭证据。 |
| N10 | PASS | 广告max1x，回正片2x/1.5x各3轮；pod第二条真正epoch换指，退役未重置继任者的全屏/方向。rerun-batch11-review.log V10/V12/V12b/V13a/b/V14。自动方向不等于竖屏的探针误判另列。 |
| N11 | PASS | Q13A/B/C各5/5；41份阶段dumpsys audio媒体音量恒6/20，静音只影响mpv mute且退出顺序均还原。rerun-batch10-mute.log、rerun-mute-volume-review.json。 |
| N12 | FAIL | 精确首帧/换源重置/过期RESTART通过，但两实现open同步快照仍旧640x360；符合异步beforeOpen后再归零的现行行为，不符合矩阵字面同步要求。rerun-native-engine-open-sync.json、rerun-native-cutover-open-sync.json、rerun-he-firstframe.log。 |
| N13 | PASS | precise on/off各3轮、native弱客户端数量与懒创建实际计数通过。rerun-he-firstframe.log、rerun-batch12-pump.log、rerun-batch15-lazy.json。 |
| N14 | PASS | declarative cover→用户contain→重建仍contain，两实现CHECK均true。rerun-batch16-checks.json及*-declarativeFit/userFit/rebuild.json。 |
| N15 | PASS | video换源重盖/实际中间渐隐、audioOnly封面常驻、Feed首帧前封面→视频完成。只用全尺寸前台安全截图。rerun-safe-transition-poster-covered/fade-*.png、rerun-safe-visual-feed-poster-*.png、rerun-batch16-audio-poster.png及对应事件。 |
| N16 | PASS | COVERAGE FIT文案实际可见；60/8/红色spinner及开关、错误层显隐、Minimal无栏无手势通过。rerun-safe-visual-controls/spinner-custom/spinner-disabled/error-visible/error-disabled.png，controls-*.xml与组件清单。 |
| N17 | PASS | View自建/复用、同源、null暂停、options重建/销毁及onOpenError，sameAs包括alternatives。rerun-batch16-view-*.json、rerun-batch15-options.json、rerun-batch16-widget-unmount.json。 |
| N18 | BLOCKED | 已测HE前后台/route/Ticker/PiP各3轮，inactive意图及直播隐藏>=3s回边缘LiveEdgeReach、真实Feed滚动和View RouteObserver。小窗连续播放原证据未独立证明MovaAutoPause豁免；新增V11M/V10C补测APK已构建，但起测前isKeyguardShowing=true，驱动拒绝执行，按用户约束停止，缺该联动的真机结论。rerun-he-guard-extra-driver.log、rerun-final-locked-window.txt、rerun-he-recovery.log。 |
| N19 | PASS | 坏地址nativeEndError、三轮failover/giveUp、多地址及卡顿后续播通过。最终V6连续区间5/5，位置误差40/40/0/0/40ms，平均24ms；超时offset1/14/2/1/1ms，平均3.8ms。rerun-he-v6-final.log、rerun-he-recovery.log、rerun-extra-failover.json。旧V6计时/锚点误判已纠正。 |
| N20 | PASS | off/holding/fallback/resuming、pause结束、默认maxDuration30s到期、allowHls两分支各3轮；硬解恢复20/20、后台降级/恢复、重载与隐藏换源均完成。rerun-keepalive-core.log、rerun-batch8-keepAlive-native.log、rerun-batch16-checks.json。grace及强制无音轨探针FAIL另列，不隐藏。 |
| N21 | PASS | 真机安装MovaTesting后平台端口空操作、stagedSourceOptions读回通过；Android实际转场/换指未出现Windows快照路径副作用。rerun-batch15-testing.json、rerun-batch11-review.log及rerun-batch16-view-*.json。 |
| N22 | PASS | 异步hooks两实现、轴向重映射、STT失败回滚、crop零缓存；慢VTT确在换源后完成，晚到非空thumb0。debug真机VM断言开启且两个非法构造均捕获。rerun-batch15-hooks/stt.json、rerun-batch22-remap*.json、rerun-safe-transition-stale-audit.json、rerun-debug-assert.json、rerun-debug-assert.logcat.txt。 |
| N23 | PASS | qoe:false零QoE；四类结束原因、restart TTFF、cache卡顿/截断均取得真实报告。完整释放卡顿sessionEnd stallCount1/stallMs5496。rerun-batch15-qoe-*.json、rerun-batch17-qoe-failed/qoe-stall-release.json；custom另见A22。 |

## 上次23个FAIL与5个BLOCKED逐条对比

| 编号 | 上次 | 本次结论 | 变化 | 原因与证据 |
|---|---|---|---|---|
| `A1` | FAIL | FAIL | 仍失败 | 两实现broadcast=[true,false,true,false]；两订阅均收到、八订阅均关闭。标志契约差异。rerun-batch15-basic.json、rerun-batch15-basic-cutover.json。 |
| `A2` | FAIL | FAIL | 仍失败 | 接收事件时state快照仍可不同：Buffer/Size及本次新增Quality对账差异；详见rerun-event-review.json的逐条mismatchExamples。 |
| `A5` | FAIL | FAIL | 仍失败 | 两实现VIDEO_OPEN_SYNC仍640x360/duration40000/rendered=true；404恢复关时accepted=true、不抛，随后error事件。同步/错误契约差异，N8接受语义仍通过。rerun-native-engine-open-sync.json、rerun-native-cutover-open-sync.json、rerun-extra-edges.json。 |
| `A8` | FAIL | PASS | 已修复 | 两实现越界state钳0..100；逐值原生媒体音量读回0/中间/20（1%受系统离散级量化）。rerun-batch15-basic.json、rerun-batch15-basic-cutover.json、rerun-native-engine/cutover-volume*.json及.native.txt。 |
| `A9` | FAIL | PASS | 已修复 | 两实现clamp全部true；原生brightness：输入-1/0/.25/.75/1/2→0/0/.25/.75/1/1；代理手势窗口sbrt=.7530023。rerun-extra-edges.json、rerun-batch16-cutover-left-check.window.txt。 |
| `A12` | FAIL | FAIL | 仍失败 | setZoom(-1/0/100)仍接受并改变画面，未使用手势maxZoom钳制。矩阵边界假设差异；非法低值可使画面塌缩。rerun-batch3-05-zoom--1.json、rerun-batch3-06-zoom-0.json、rerun-batch3-09-zoom-100.png。 |
| `A17` | FAIL | FAIL | 仍失败 | HLS累计39/40切档通过，成功落点误差均0ms；长进程代理run3 target10183→RESTART[23,23]，未续播。ABR真实限速降档通过但不抵消失败。rerun-measured-summary.json、rerun-batch17-hls-playing-cutover.json、rerun-final-hls-cutover/abr.json。 |
| `A23` | FAIL | FAIL | 仍失败 | 两实现第二次dispose仍抛[Player] has been disposed；首次关闭及disposed open=false正常，120轮首次创建/销毁完成。二次调用安全的矩阵契约差异。rerun-batch15-basic.json、rerun-batch15-basic-cutover.json、rerun-batch15-dispose120.json及round*.meminfo.txt。 |
| `A31` | BLOCKED | BLOCKED | 仍阻塞 | 已测disabled/noEngine阻断、注入引擎首启失败回滚/二次重试。未提供真实识别模型/模型下载服务，设备旧seed目录不存在；真实转写、下载失败链、SRT导出/分块落盘未完成。rerun-batch15-stt.json、rerun-stt-device-seed.txt。 |
| `C2` | BLOCKED | BLOCKED | 仍阻塞 | 已测真实FLV/HLS durationStep、12s本地DVR、behind/回边缘三轮；未提供按behind URL返回历史且可控卡顿服务。urlBuilder历史语义、自定义windowResolver/autoBackToLiveOnStall完整联动未完成。rerun-live-*.json、rerun-batch15-live-step*.json；条件与上次相同。 |
| `C3` | FAIL | FAIL | 仍失败 | 真实长按1800ms期间仍1x，当前无长按倍速；侧别/轴向改配、seek、默认双击seek、Douyin Feed点击/like及锁定屏蔽已实测。能力假设差异。rerun-batch18-longpress-*.json、rerun-batch22-remap/feed*.json、rerun-batch16-checks.json。 |
| `C6` | FAIL | FAIL | 仍失败 | 真实滚动弹幕可见，但发送API/输入框未提供（display-only），矩阵要求的发送不能满足。rerun-safe-visual-danmaku.png/json。 |
| `C7` | BLOCKED | BLOCKED | 仍阻塞 | 已测disabled/noEngine阻断、注入引擎首启失败回滚/二次重试。未提供真实识别模型/模型下载服务，设备旧seed目录不存在；真实转写、下载失败链、SRT导出/分块落盘未完成。rerun-batch15-stt.json、rerun-stt-device-seed.txt。 |
| `C8` | FAIL | FAIL | 仍失败 | 自动连播、NextUp卡片/取消/立即播放实测；卡片没有数字倒计时。rerun-extra-playlist.json、rerun-safe-visual-nextup.png、rerun-safe-visual-nextup-click.json。 |
| `C16` | FAIL | FAIL | 仍失败 | 实时戳最终矩阵35/40；合法IP SAN verify=true仍5/5拒绝。独立探针合法DNS6/6通过、合法IP0/6；CA属性正确，OpenSSL两证书OK。原生TLS兼容缺陷，未定位具体责任层。rerun-final-tls.json、rerun-final-tls-probe.json、rerun-openssl-verify.txt。 |
| `E.MovaBufferChange` | FAIL | FAIL | 仍失败 | MovaBufferChange：去重1041次，同型相邻同值1次；标量对账1041条/差异8条；样例payload={"buffering":true}，动作={"group":"basic"}。证据rerun-batch15-basic-cutover.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| `E.MovaSizeChange` | FAIL | FAIL | 仍失败 | MovaSizeChange：去重602次，同型相邻同值0次；标量对账602条/差异25条；样例payload={"width":640,"height":0}，动作={"group":"new","case":"lazy"}。证据rerun-batch15-lifecycle.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| `E1` | FAIL | FAIL | 仍失败 | 真实Play意图事件早于Ready/FirstFrame，不满足矩阵示意箭头严格顺序。不是提前出画；自然Done1/无错误的生命周期仍通过F1。rerun-batch15-lifecycle.json。 |
| `U3` | FAIL | FAIL | 仍失败 | 实际TopBar只有标题及功能按钮，没有返回按钮；Android BACK能退路由。能力假设差异。rerun-safe-visual-route-player.png、rerun-safe-visual-route-back.png及同前缀JSON；PiP/方向另见A16/A18。 |
| `U5` | FAIL | FAIL | 仍失败 | 语义点击1x后直接1.25x、没有倍速菜单；CenterPlay实际点击播放，HUD另有真实手势读回。能力形态差异。rerun-safe-visual-speed-button.json、rerun-safe-visual-center-play.json及PNG、rerun-batch16-*-left/right*.png。 |
| `U6` | FAIL | FAIL | 仍失败 | 真实长按1800ms期间仍1x，当前无长按倍速；侧别/轴向改配、seek、默认双击seek、Douyin Feed点击/like及锁定屏蔽已实测。能力假设差异。rerun-batch18-longpress-*.json、rerun-batch22-remap/feed*.json、rerun-batch16-checks.json。 |
| `U7` | FAIL | PASS | 已修复（验证器/判据纠正，真机重测） | 弹幕/四格式字幕、NextUp立即播放、广告倒计时/点击/跳过、Feed输入均实际完成。rerun-safe-visual-*（SKIP_BUTTON=true）、rerun-extra-subtitles.*、rerun-batch22-feed*.json。上次把C8的NextUp数字倒计时缺失重复记到U7；本次按该组合中的广告倒计时判，纠正口径。 |
| `F3` | FAIL | FAIL | 仍失败 | HLS累计39/40切档通过，成功落点误差均0ms；长进程代理run3 target10183→RESTART[23,23]，未续播。ABR真实限速降档通过但不抵消失败。rerun-measured-summary.json、rerun-batch17-hls-playing-cutover.json、rerun-final-hls-cutover/abr.json。 |
| `F8` | FAIL | PASS | 已修复（验证器/判据纠正，真机重测） | 坏地址nativeEndError、三轮failover/giveUp、多地址及卡顿后续播通过。最终V6连续区间5/5，位置误差40/40/0/0/40ms，平均24ms；超时offset1/14/2/1/1ms，平均3.8ms。rerun-he-v6-final.log、rerun-he-recovery.log、rerun-extra-failover.json。旧V6计时/锚点误判已纠正。 |
| `F15` | BLOCKED | BLOCKED | 仍阻塞 | WHEP端点38889/test/whep拒连，相关端口探测不可用；缺publisher/信令/UDP38189及relay38190服务。只完成WHEP选项读回，未完成15s播放。rerun-external-prerequisites.json、rerun-batch15-options.json；与上次条件相同。 |
| `N12` | FAIL | FAIL | 仍失败 | 精确首帧/换源重置/过期RESTART通过，但两实现open同步快照仍旧640x360；符合异步beforeOpen后再归零的现行行为，不符合矩阵字面同步要求。rerun-native-engine-open-sync.json、rerun-native-cutover-open-sync.json、rerun-he-firstframe.log。 |
| `N19` | FAIL | PASS | 已修复（验证器/判据纠正，真机重测） | 坏地址nativeEndError、三轮failover/giveUp、多地址及卡顿后续播通过。最终V6连续区间5/5，位置误差40/40/0/0/40ms，平均24ms；超时offset1/14/2/1/1ms，平均3.8ms。rerun-he-v6-final.log、rerun-he-recovery.log、rerun-extra-failover.json。旧V6计时/锚点误判已纠正。 |
| `N22` | BLOCKED | PASS | 已修复/解除阻塞（debug补测） | 异步hooks两实现、轴向重映射、STT失败回滚、crop零缓存；慢VTT确在换源后完成，晚到非空thumb0。debug真机VM断言开启且两个非法构造均捕获。rerun-batch15-hooks/stt.json、rerun-batch22-remap*.json、rerun-safe-transition-stale-audit.json、rerun-debug-assert.json、rerun-debug-assert.logcat.txt。 |

## 上次PASS、本次FAIL（新增回归观测）

“新增”指本次台账新增FAIL，不等同已经定位为最近提交引入；没有使用静态代码来证明代码回归。

| 编号 | 本次 | 原因与证据 |
|---|---|---|
| `A15` | FAIL | 真实MiniHost→enterPip后mini=false但controller仍showing=true/persistent；展开后pip=false/mini=false而小窗仍可见。全新进程复现，真实UI与状态衔接缺口。rerun-mini-pip-repro-show/enter/holding/expanded.json/png/activity.txt。 |
| `E.MovaQualityChange` | FAIL | MovaQualityChange：去重56次，同型相邻同值0次；标量对账10条/差异1条；样例payload={"quality":"自动"}，动作={"group":"new","case":"hls"}。证据rerun-final-abr.json，全部载荷/状态/上下文见rerun-event-review.json。 |
| `F5` | FAIL | 真实MiniHost→enterPip后mini=false但controller仍showing=true/persistent；展开后pip=false/mini=false而小窗仍可见。全新进程复现，真实UI与状态衔接缺口。rerun-mini-pip-repro-show/enter/holding/expanded.json/png/activity.txt。 |

其中A15/F5是同一个真实组合功能缺口，已在全新进程复现；E.MovaQualityChange是本次补充质量state字段后首次捕获的接收快照不符，旧验证器未记录该标量，因此不能断言其代码引入时间。
新增阻塞：N18。

## 本次FAIL最小复现与分类

| 涉及编号 | 分类 | 最小复现、实际结果与原因判断 |
|---|---|---|
| A15 / F5 | 真实UI集成缺陷 | 全新api进程，`mini.show(api)`→`api.enterPip()`→am start展开。mini=false/pip=false，但controller showing=true/persistent，小窗仍可见。`rerun-mini-pip-repro-expanded.json/png`；Host依据controller api/mount绘制，API清mini位未收起controller。责任衔接点已缩小，未修库。 |
| A17 / F3 | 真实续播缺陷（间歇） | `new case=hls cutover=true`，原生进度>=8s后交替360p/180p五次。长进程run3目标10183ms，两次RESTART均23ms，15s无目标附近落点，continued14623ms。`rerun-batch17-hls-playing-cutover.json`。40次合计仅1次失败仍必须FAIL；疑似duration/首呈现竞态仍有未覆盖分支，未插桩定因，不把推测写成已定位根因。 |
| C16 | 真实原生TLS兼容缺陷（责任层未定） | tlsVerify=true且CA正确，打开带实时戳的合法IP SAN本地MP4/HLS失败；同CA localhost DNS证书成功，OpenSSL两者OK。`rerun-final-tls-probe.json`与`rerun-openssl-verify.txt`。不凭记忆归责某版mbedtls。 |
| A1 | 矩阵流契约差异 | 两实现读取四流isBroadcast为true/false/true/false；多订阅与关闭实测正常。`rerun-batch15-basic/basic-cutover.json` STREAM_FLAGS。 |
| A2 / E.MovaBufferChange / E.MovaSizeChange / E.MovaQualityChange | 矩阵接收快照契约差异 | event订阅内立即读state并保留载荷。Buffer、Size与Quality存在不符；Quality在ABR序列收到“自动”时state为360p。`rerun-event-review.json`含原ms/engine/原命令/完整state。差异真实，但不能直接推出画面错误或新的代码回归。 |
| A5 / N12 | 矩阵同步/错误契约差异 | 可见视频640x360后`f=api.open(other);`立即读仍旧宽高/时长，再await才异步归零；恢复关闭404返回true，error另发事件。`rerun-native-engine/cutover-open-sync.json`、`rerun-extra-edges.json`。与N8 true=接受相容，不应把true当播放成功。 |
| A12 | 边界/能力假设差异 | 在真实画面上setZoom(-1/0/100)，state保留输入，0可塌缩；maxZoom只控制手势。`rerun-batch3-05..10-zoom-*`。保留非法值无保护现象，不将其等同有效输入播放故障。 |
| A23 | 生命周期契约差异 | audioOnly普通/代理open后连续dispose两次，第二次抛disposed。首次销毁/8流关闭、120轮完成。`rerun-batch15-basic/basic-cutover/dispose120.json`。公开生命周期约定一次销毁，矩阵额外要求幂等。 |
| C3 / U6 | 能力假设差异 | 全尺寸前台视频长按1800ms，rate仍1，无长按倍速。双击实际seek、左右及重映射有效。`rerun-batch18-longpress-during/after.json`、`rerun-batch22-remap*`。 |
| C6 | 能力假设差异 | 宿主items弹幕真实滚动，但无发送接口/输入框。`rerun-safe-visual-danmaku.png`，当前设计display-only。 |
| C8 | 能力假设差异 | 自然连播与NextUp立即播放有效，但卡片无数字倒计时。`rerun-safe-visual-nextup.png`、`rerun-extra-playlist.json`。 |
| U3 | 能力假设差异 | 真路由MovaPlayer顶栏无返回按钮；Android BACK退出正常。`rerun-safe-visual-route-player/route-back.png`。 |
| U5 | 能力假设差异 | 按语义1x点击，rate变1.25而未弹菜单。`rerun-safe-visual-speed-button.json/png`。中心播放与HUD通过不能代替菜单子项。 |
| E1 | 意图事件顺序与矩阵箭头差异 | 完整自然生命周期中Play先于Ready/FirstFrame。`rerun-batch15-lifecycle.json`；Play是意图，不是首帧。 |

## BLOCKED条件与已测子项

- **A31/C7**：仍缺真实识别模型和下载服务；设备旧seed目录不存在。已测noEngine/disabled、失败回滚重试；未测真实识别、模型下载完整失败链、SRT导出/分块存储。未把注入Noop当真实转写。
- **C2**：仍缺按behind URL返回历史且可控卡顿的服务。已测FLV/HLS与本地DVR、12s窗口/behind/backEdge/durationStep；历史urlBuilder、windowResolver与autoBackToLiveOnStall完整联动未完成。
- **F15**：仍缺可达WHEP publisher/信令和UDP/relay链。`rerun-external-prerequisites.json`记录HTTP拒连和端口探测，TCP探测不冒充UDP可用；选项读回不冒充15s播放。
- **N22已解除**：当前SDK的debug APK在真机启用断言，两个非法构造均捕获；其余异步hooks/轴向/crop/STT回滚/慢VTT换源竞态均有本次设备证据。不再尝试已知不支持的AOT enable-asserts。
- **N18本次新增阻塞**：初轮没有独立的小窗自动暂停守卫联动证据，最终核对后补建V11M/V10C验证页。安装成功后、起测前检查变为isKeyguardShowing=true，驱动在启动前拒绝执行；未尝试唤醒/解锁、未产生锁屏渲染结论。已测部分见台账，缺少的mini守卫子项不拿纯逻辑单测补PASS。

## 验证器问题、作废证据与测量边界

- 初轮V6以第一个buffering=true计时，出现一次offset2757ms；连续区间补测5/5通过，捕捉到true→false→约2.8s后true，最终期限offset仅1/14/2/1/1ms。这是计时锚点问题，不能再误报续播回零。上次Stamped/indexOf旧错误也没有重用。
- review V10/V10x/V11 的restoredPortrait=false保留原始FAIL；原生已FULL_USER，系统自动旋转开、userRotation0。把自动等同竖屏是验证器假设。交接期间全屏/方向/系统栏及显式方向API另有通过读回。`rerun-review-rotation-window.txt`。
- 旧视觉脚本把固定(600,230)点到PiP，之后触点落到其他应用；**rerun-batch25及rerun-batch28在该误触后的视觉/竞态结论全部作废**，未用其截图判PASS。安全重跑改用1x/立即播放/跳过语义，输入前检查原生测试包前台且全尺寸；有效文件为rerun-safe-visual、rerun-safe-transition及rerun-manual2。误触留下的安装提示未作确认，测试包最终返回HOME。
- 慢VTT必须证明确有在途请求：BEGIN1793097684.006 < 换源1793097684.960 < END1793097686.514；换源后非空旧thumb0。`rerun-service-1.log`、`rerun-safe-transition-stale-audit.json`。不以“没看到图”代替丢弃旧结果验证。
- 旧subtitle suite只完成部分后未发完成标记/切换停滞，completed=false未用于F11；以已修正的HTTP外挂字幕、先卸载再dispose的rerun-extra-subtitles四格式CHECK/原生sub-text/PNG为准。无screenrecord继续用PNG；驱动已限制只消费当前命令的MEM/SUBTITLE标记，避免重拍历史字幕。
- S1的9个严格信号探针FAIL均为grace≈5s，但原生解码属性约百余ms恢复；S6强制绕过策略对无音轨流进muted仍EOF/重载，3/3探针FAIL。均如实保留于rerun-keepalive-core.log；它们不等同默认引擎守卫失效。F6按矩阵状态迁移/恢复/后台/位置要求判定，通过同时保留性能/信号缺口。
- 20s待机漂移149/625/567ms，均值447ms；无待机对照2/43/-5ms，绝对均值16.7ms。不能据此宣布Windows60s漂移已修。CPU剔除每阶段边界±2s，完整样本与均值见rerun-cpu-review.json；USB供电不推出电池结论。120轮RSS197332992→222294016bytes，尾部仍有增长，仅报告趋势，不声称绝无泄漏。
- U7纠正的是上一轮把C8数字倒计时要求重复扩展到U7：本次广告倒计时、点击和跳过均实测成功，C8继续FAIL。其余不存在的菜单、返回、长按、发送能力仍按矩阵字面FAIL，没有静态阅读补PASS。
- CLAUDE中的F3“已修、15/15”不能覆盖本次间歇反例；V6续播已确认；PiP退出state与广告rate/pod旧问题未复现。Darwin瘦身包仍待Mac验证，本次不涉及。

## 收尾与复跑入口

第一次收尾已返回HOME且亮屏解锁，见`rerun-final-window.txt`。随后N18补测前设备变为锁屏，按约束停测；最终状态以`rerun-final-locked-window.txt`为准（isKeyguardShowing=true）。独立包再次force-stop，pid为空（rerun-final-locked-process.txt）；USB常亮原值7、媒体音量原值6/20均已原生确认，见`rerun-final-locked-power.txt`、`rerun-final-locked-volume.txt`。测试夹具含临时守卫源均已停止，见`rerun-final-services.txt`，adb映射保留。锁屏发生在已完成主批次及N22断言之后，不反向作废有各自解锁证据的已完成测试；N18补测明确没有运行。

复跑入口：先起夹具并确认亮屏解锁，隔离release走`coverage_build.py lib/main_coverage_suite.dart`，再`coverage_suite_device.py api`；HLS用`coverage_device.py new --arg case=hls --arg cutover=true --name rerun-<新名>`；新Mini/PiP缺口按本节最小复现，不修库。安全视觉用rerun_visual_safe.py（包含前台/尺寸检查与语义触点），不要重用旧倍速坐标。

## 逐批计划与检查点（执行原始追加记录）

## 基线与前置

- 设备 7NQBB23606003715，STG_AL00 Android 12 arm64；已亮屏解锁，原始 window/audio/power 见 `example/tool/coverage_evidence/rerun-preflight-*`。
- 起测 USB 常亮=7；媒体 speaker 音量=6/20。收尾恢复这两个原值。
- Flutter 3.47.0 / Dart 3.13.0。保留已有 `test/core/engine_test.dart` 改动；禁止改库和测试。
- 批次0：运行 flutter analyze lib test 与 flutter test，确认实际基线；随后隔离 release 构建。

## 批次0基线检查点

- analyze exit=1：2 issues（1 error duplicate_definition、1 warning unused_element），test/core/engine_test.dart:1978 与1959重复定义 _RecordingBrightPort；原始日志 rerun-baseline-analyze.log。
- flutter test exit=1：00:47 +1424 -1，1424通过/1测试文件加载失败；engine_test.dart 编译失败，因此无本次全绿总数；不能用上次1503或CLAUDE的1510替代。本次未修改该文件。原始日志 rerun-baseline-test.log。
- 本地源18080/18081、预览/HLS18084、TLS18443–18447已启动，日志 rerun-service-0/1/2.log。

## 开始 api-launch

- 复用现有验证器，检查真实事件/状态/原生读回；命令：`python example/tool/coverage_suite_device.py api --name rerun-api-launch --timeout 60`。完成后仅按实际证据回填编号。

## 结束 api-launch

- exit=0；驱动输出 `example/tool/coverage_evidence/rerun-plan-api-launch.log`；原始结果均用 rerun- 前缀。异常/超时不得推断为 PASS。

## 开始 api

- 复用现有验证器，检查真实事件/状态/原生读回；命令：`python example/tool/rerun_batch.py coverage_api_batches.py`。完成后仅按实际证据回填编号。

## 开始 rerun-batch15-basic

- 执行 basic {}；以真实事件和原生读回检查对应子项。

## 构建检查点

- 隔离 release 构建成功，BUILD SUCCESSFUL in 2m39s，安装成功。APK SHA256=BEDA6E4325F3E0BCF526BC9AC2B9F1AE7AF0163D200D297A6B35C548345A8DA1；构建日志 rerun-build.log。独立包 com.icodejoo.mova.mova_example.coverage。
- 安装后再次确认 isKeyguardShowing=false / mScreenOnFully=true。adb reverse 已映射媒体、直播、HLS与TLS端口。

## rerun-batch15-basic 自动检查点

- 命令 `basic {}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-basic.json` 及同前缀文件。
```json
[
  {
    "ms": 2332,
    "kind": "BEGIN",
    "group": "basic",
    "args": {
      "group": "basic"
    }
  },
  {
    "ms": 2344,
    "kind": "STREAM_FLAGS",
    "broadcast": [
      true,
      false,
      true,
      false
    ],
    "types": [
      "_BroadcastStream<MovaEvent>",
      "_MultiStream<MovaState>",
      "_BroadcastStream<MovaProg>",
      "_MultiStream<MovaUiState>"
    ],
    "cutover": false
  },
  {
    "ms": 2344,
    "kind": "CHECK",
    "id": "A1.broadcast",
    "pass": false,
    "detail": "all streams broadcast cutover=false"
  },
  {
    "ms": 2344,
    "kind": "CHECK",
    "id": "A3.audio",
    "pass": true,
    "detail": "handle=null"
  },
  {
    "ms": 2345,
    "kind": "PREVIEW_THUMB",
    "engine": 1069834183,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 2438,
    "kind": "CHECK",
    "id": "A5.paused",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 0, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: true, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 4646,
    "kind": "CHECK",
    "id": "A4",
    "pass": true,
    "detail": "supported=true"
  },
  {
    "ms": 5652,
    "kind": "CHECK",
    "id": "A1.progress",
    "pass": true,
    "detail": "0:00:02.144650 -> 0:00:03.144660"
  },
  {
    "ms": 5810,
    "kind": "CHECK",
    "id": "A6.pause",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 3144, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 5922,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=5000 landed=5000"
  },
  {
    "ms": 5973,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=10000 landed=10000"
  },
  {
    "ms": 6024,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=15000 landed=15000"
  },
  {
    "ms": 6071,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=5000 landed=5000"
  },
  {
    "ms": 6115,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=10000 landed=10000"
  },
  {
    "ms": 6427,
    "kind": "CHECK",
    "id": "A7.negative",
    "pass": true,
    "detail": "0:00:00.000000"
  },
  {
    "ms": 6623,
    "kind": "SAMPLE",
    "name": "volume-10.0",
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 23,
      "size": "0x0",
      "volume": 0.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 6624,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 0.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 6813,
    "kind": "SAMPLE",
    "name": "volume0.0",
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 23,
      "size": "0x0",
      "volume": 0.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 6814,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 0.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 6996,
    "kind": "SAMPLE",
    "name": "volume1.0",
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 23,
      "size": "0x0",
      "volume": 1.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 6997,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 1.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 7202,
    "kind": "SAMPLE",
    "name": "volume50.0",
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 23,
      "size": "0x0",
      "volume": 50.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 7202,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 50.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 7384,
    "kind": "SAMPLE",
    "name": "volume100.0",
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 23,
      "size": "0x0",
      "volume": 100.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 7386,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 100.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 7566,
    "kind": "SAMPLE",
    "name": "volume110.0",
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 23,
      "size": "0x0",
      "volume": 100.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 7567,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 100.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 7790,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 0.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 7944,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 0.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 8101,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 0.5, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 8259,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 8415,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 8423,
    "kind": "RATE",
    "input": 0.5,
    "actual": 0.5
  },
  {
    "ms": 8425,
    "kind": "RATE",
    "input": 1.0,
    "actual": 1.0
  },
  {
    "ms": 8428,
    "kind": "RATE",
    "input": 1.5,
    "actual": 1.5
  },
  {
    "ms": 8430,
    "kind": "RATE",
    "input": 2.0,
    "actual": 2.0
  },
  {
    "ms": 8432,
    "kind": "RATE_REJECT",
    "input": -1.0,
    "error": "Invalid argument (rate): Must be greater than 0.0: -1.0"
  },
  {
    "ms": 8432,
    "kind": "RATE_REJECT",
    "input": 0.0,
    "error": "Invalid argument (rate): Must be greater than 0.0: 0.0"
  },
  {
    "ms": 8452,
    "kind": "CHECK",
    "id": "A21.hide",
    "pass": true,
    "detail": "false"
  },
  {
    "ms": 8604,
    "kind": "CHECK",
    "id": "A21.hud",
    "pass": true,
    "detail": "MovaHud.seek"
  },
  {
    "ms": 8605,
    "kind": "CHECK",
    "id": "A22",
    "pass": true,
    "detail": "[pause:{}, sourceChange:{uri: http://127.0.0.1:18080/vod.mp4?t=1793092972283789}, play:{}, pause:{}, play:{}, pause:{}, seek:{targetMs: 5000}, seeked:{positionMs: 5000}, seek:{targetMs: 10000}, seeked:{positionMs: 10000}, seek:{targetMs: 15000}, seeked:{positionMs: 15000}, seek:{targetMs: 5000}, seeked:{positionMs: 5000}, seek:{targetMs: 10000}, seeked:{positionMs: 10000}, seek:{targetMs: 8000}, seeked:{positionMs: 8000}, seek:{targetMs: 0}, seeked:{positionMs: 0}, coverage:{probe: 42}, play:{probe: 43}]"
  },
  {
    "ms": 9262,
    "kind": "PREVIEW_THUMB",
    "engine": 1069834183,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 9273,
    "kind": "OPEN_SYNC",
    "playing": false,
    "intent": false,
    "buffering": false,
    "duration": 40000,
    "position": 150,
    "size": "0x0",
    "volume": 30.0,
    "brightness": 0.5,
    "rate": 1.5,
    "fit": "contain",
    "zoom": 1.0,
    "locked": false,
    "fullscreen": false,
    "orientation": "auto",
    "pip": false,
    "mini": false,
    "rendered": true,
    "epoch": 0,
    "sourceIndex": 0,
    "keepAlive": "off",
    "type": "vod",
    "title": "Coverage vod.mp4",
    "pipSupported": true,
    "controls": false,
    "hud": "none",
    "previewCurrent": null,
    "timeshiftBehind": null,
    "liveSeekable": false,
    "seekableWindow": 40000,
    "hudText": null,
    "dragging": false,
    "previewAt": null
  },
  {
    "ms": 9274,
    "kind": "PREVIEW_THUMB",
    "engine": 1069834183,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 9274,
    "kind": "PREVIEW_THUMB",
    "engine": 1069834183,
    "at": null,
    "bytes": null,
    "title": "Coverage ad.mp4"
  },
  {
    "ms": 9500,
    "kind": "CHECK",
    "id": "A10.persist",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 20000, position: 0, size: 0x0, volume: 30.0, brightness: 0.5, rate: 1.5, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: false, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage ad.mp4, pipSupported: true, controls: true, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 20000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 9501,
    "kind": "PREVIEW_THUMB",
    "engine": 1069834183,
    "at": null,
    "bytes": null,
    "title": "Coverage ad.mp4"
  },
  {
    "ms": 9659,
    "kind": "RELOAD",
    "playing": false,
    "intent": false,
    "buffering": false,
    "duration": 20000,
    "position": 0,
    "size": "0x0",
    "volume": 30.0,
    "brightness": 0.5,
    "rate": 1.5,
    "fit": "contain",
    "zoom": 1.0,
    "locked": false,
    "fullscreen": false,
    "orientation": "auto",
    "pip": false,
    "mini": false,
    "rendered": false,
    "epoch": 0,
    "sourceIndex": 0,
    "keepAlive": "off",
    "type": "vod",
    "title": "Coverage ad.mp4",
    "pipSupported": true,
    "controls": true,
    "hud": "none",
    "previewCurrent": null,
    "timeshiftBehind": null,
    "liveSeekable": false,
    "seekableWindow": 20000,
    "hudText": null,
    "dragging": false,
    "previewAt": null
  },
  {
    "ms": 9659,
    "kind": "CHECK",
    "id": "E2.disabled",
    "pass": true,
    "detail": "count=0"
  },
  {
    "ms": 9659,
    "kind": "CHECK",
    "id": "C13.off",
    "pass": true,
    "detail": "QoE reports=24"
  },
  {
    "ms": 9821,
    "kind": "CHECK",
    "id": "A1.closed",
    "pass": true,
    "detail": "counts=[59, 59, 43, 43, 22, 22, 9, 9] closed=[true, true, true, true, true, true, true, true]"
  },
  {
    "ms": 9822,
    "kind": "CHECK",
    "id": "A23.doubleDispose",
    "pass": false,
    "detail": "Assertion failed: \"[Player] has been disposed\""
  },
  {
    "ms": 9823,
    "kind": "CHECK",
    "id": "A23.postOpen",
    "pass": true,
    "detail": "disposed open=false"
  },
  {
    "ms": 9823,
    "kind": "BASIC_DONE",
    "cutover": false,
    "events": 59
  },
  {
    "ms": 9823,
    "kind": "END",
    "group": "basic",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-basic-cutover

- 执行 basic {'cutover': 'true'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-basic-cutover 自动检查点

- 命令 `basic {'cutover': 'true'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-basic-cutover.json` 及同前缀文件。
```json
[
  {
    "ms": 12939,
    "kind": "BEGIN",
    "group": "basic",
    "args": {
      "group": "basic",
      "cutover": "true"
    }
  },
  {
    "ms": 12978,
    "kind": "STREAM_FLAGS",
    "broadcast": [
      true,
      false,
      true,
      false
    ],
    "types": [
      "_BroadcastStream<MovaEvent>",
      "_MultiStream<MovaState>",
      "_BroadcastStream<MovaProg>",
      "_MultiStream<MovaUiState>"
    ],
    "cutover": true
  },
  {
    "ms": 12978,
    "kind": "CHECK",
    "id": "A1.broadcast",
    "pass": false,
    "detail": "all streams broadcast cutover=true"
  },
  {
    "ms": 12978,
    "kind": "CHECK",
    "id": "A3.audio",
    "pass": true,
    "detail": "handle=null"
  },
  {
    "ms": 12983,
    "kind": "PREVIEW_THUMB",
    "engine": 281003599,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 13170,
    "kind": "CHECK",
    "id": "A5.paused",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 0, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: false, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: true, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 15489,
    "kind": "CHECK",
    "id": "A4",
    "pass": true,
    "detail": "supported=true"
  },
  {
    "ms": 16567,
    "kind": "CHECK",
    "id": "A1.progress",
    "pass": true,
    "detail": "0:00:02.144819 -> 0:00:03.195048"
  },
  {
    "ms": 16720,
    "kind": "CHECK",
    "id": "A6.pause",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 3195, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 16783,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=5000 landed=5000"
  },
  {
    "ms": 16827,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=10000 landed=10000"
  },
  {
    "ms": 16870,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=15000 landed=15000"
  },
  {
    "ms": 16912,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=5000 landed=5000"
  },
  {
    "ms": 16956,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=10000 landed=10000"
  },
  {
    "ms": 17262,
    "kind": "CHECK",
    "id": "A7.negative",
    "pass": true,
    "detail": "0:00:00.000000"
  },
  {
    "ms": 17454,
    "kind": "SAMPLE",
    "name": "volume-10.0",
    "state": {
      "playing": false,
      "intent": false,
      "buffering": true,
      "duration": 40000,
      "position": 23,
      "size": "0x0",
      "volume": 0.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 17454,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 0.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 17625,
    "kind": "SAMPLE",
    "name": "volume0.0",
    "state": {
      "playing": false,
      "intent": false,
      "buffering": true,
      "duration": 40000,
      "position": 23,
      "size": "0x0",
      "volume": 0.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 17625,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 0.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 17792,
    "kind": "SAMPLE",
    "name": "volume1.0",
    "state": {
      "playing": false,
      "intent": false,
      "buffering": true,
      "duration": 40000,
      "position": 23,
      "size": "0x0",
      "volume": 1.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 17792,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 1.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 17974,
    "kind": "SAMPLE",
    "name": "volume50.0",
    "state": {
      "playing": false,
      "intent": false,
      "buffering": true,
      "duration": 40000,
      "position": 23,
      "size": "0x0",
      "volume": 50.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 17974,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 50.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 18146,
    "kind": "SAMPLE",
    "name": "volume100.0",
    "state": {
      "playing": false,
      "intent": false,
      "buffering": true,
      "duration": 40000,
      "position": 23,
      "size": "0x0",
      "volume": 100.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 18147,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 100.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 18310,
    "kind": "SAMPLE",
    "name": "volume110.0",
    "state": {
      "playing": false,
      "intent": false,
      "buffering": true,
      "duration": 40000,
      "position": 23,
      "size": "0x0",
      "volume": 100.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 18310,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 100.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 18490,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 0.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 18645,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 0.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 18799,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 0.5, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 18952,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 19106,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 19110,
    "kind": "RATE",
    "input": 0.5,
    "actual": 1.0
  },
  {
    "ms": 19111,
    "kind": "RATE",
    "input": 1.0,
    "actual": 0.5
  },
  {
    "ms": 19113,
    "kind": "RATE",
    "input": 1.5,
    "actual": 1.0
  },
  {
    "ms": 19114,
    "kind": "RATE",
    "input": 2.0,
    "actual": 1.5
  },
  {
    "ms": 19114,
    "kind": "RATE_REJECT",
    "input": -1.0,
    "error": "Invalid argument (rate): Must be greater than 0.0: -1.0"
  },
  {
    "ms": 19115,
    "kind": "RATE_REJECT",
    "input": 0.0,
    "error": "Invalid argument (rate): Must be greater than 0.0: 0.0"
  },
  {
    "ms": 19115,
    "kind": "CHECK",
    "id": "A21.hide",
    "pass": true,
    "detail": "false"
  },
  {
    "ms": 19268,
    "kind": "CHECK",
    "id": "A21.hud",
    "pass": true,
    "detail": "MovaHud.seek"
  },
  {
    "ms": 19269,
    "kind": "CHECK",
    "id": "A22",
    "pass": true,
    "detail": "[pause:{}, sourceChange:{uri: http://127.0.0.1:18080/vod.mp4?t=1793092982917350}, play:{}, pause:{}, play:{}, pause:{}, seek:{targetMs: 5000}, seeked:{positionMs: 5000}, seek:{targetMs: 10000}, seeked:{positionMs: 10000}, seek:{targetMs: 15000}, seeked:{positionMs: 15000}, seek:{targetMs: 5000}, seeked:{positionMs: 5000}, seek:{targetMs: 10000}, seeked:{positionMs: 10000}, seek:{targetMs: 7999}, seeked:{positionMs: 7999}, seek:{targetMs: 0}, seeked:{positionMs: 0}, coverage:{probe: 42}, play:{probe: 43}]"
  },
  {
    "ms": 19947,
    "kind": "PREVIEW_THUMB",
    "engine": 281003599,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 19958,
    "kind": "OPEN_SYNC",
    "playing": false,
    "intent": false,
    "buffering": true,
    "duration": 40000,
    "position": 0,
    "size": "0x0",
    "volume": 30.0,
    "brightness": 0.5,
    "rate": 1.5,
    "fit": "contain",
    "zoom": 1.0,
    "locked": false,
    "fullscreen": false,
    "orientation": "auto",
    "pip": false,
    "mini": false,
    "rendered": true,
    "epoch": 0,
    "sourceIndex": 0,
    "keepAlive": "off",
    "type": "vod",
    "title": "Coverage vod.mp4",
    "pipSupported": true,
    "controls": false,
    "hud": "none",
    "previewCurrent": null,
    "timeshiftBehind": null,
    "liveSeekable": false,
    "seekableWindow": 40000,
    "hudText": null,
    "dragging": false,
    "previewAt": null
  },
  {
    "ms": 19960,
    "kind": "PREVIEW_THUMB",
    "engine": 281003599,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 19960,
    "kind": "PREVIEW_THUMB",
    "engine": 281003599,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 20173,
    "kind": "CHECK",
    "id": "A10.persist",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 20000, position: 0, size: 0x0, volume: 30.0, brightness: 0.5, rate: 1.5, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: false, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage ad.mp4, pipSupported: true, controls: true, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 20000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 20176,
    "kind": "PREVIEW_THUMB",
    "engine": 281003599,
    "at": null,
    "bytes": null,
    "title": "Coverage ad.mp4"
  },
  {
    "ms": 20304,
    "kind": "RELOAD",
    "playing": false,
    "intent": false,
    "buffering": false,
    "duration": 20000,
    "position": 0,
    "size": "0x0",
    "volume": 30.0,
    "brightness": 0.5,
    "rate": 1.5,
    "fit": "contain",
    "zoom": 1.0,
    "locked": false,
    "fullscreen": false,
    "orientation": "auto",
    "pip": false,
    "mini": false,
    "rendered": true,
    "epoch": 0,
    "sourceIndex": 0,
    "keepAlive": "off",
    "type": "vod",
    "title": "Coverage ad.mp4",
    "pipSupported": true,
    "controls": true,
    "hud": "none",
    "previewCurrent": null,
    "timeshiftBehind": null,
    "liveSeekable": false,
    "seekableWindow": 20000,
    "hudText": null,
    "dragging": false,
    "previewAt": null
  },
  {
    "ms": 20305,
    "kind": "CHECK",
    "id": "E2.disabled",
    "pass": true,
    "detail": "count=0"
  },
  {
    "ms": 20305,
    "kind": "CHECK",
    "id": "C13.off",
    "pass": true,
    "detail": "QoE reports=24"
  },
  {
    "ms": 20472,
    "kind": "CHECK",
    "id": "A1.closed",
    "pass": true,
    "detail": "counts=[62, 62, 46, 46, 25, 25, 9, 9] closed=[true, true, true, true, true, true, true, true]"
  },
  {
    "ms": 20473,
    "kind": "CHECK",
    "id": "A23.doubleDispose",
    "pass": false,
    "detail": "Assertion failed: \"[Player] has been disposed\""
  },
  {
    "ms": 20473,
    "kind": "CHECK",
    "id": "A23.postOpen",
    "pass": true,
    "detail": "disposed open=false"
  },
  {
    "ms": 20474,
    "kind": "BASIC_DONE",
    "cutover": true,
    "events": 62
  },
  {
    "ms": 20474,
    "kind": "END",
    "group": "basic",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-testing

- 执行 testing {}；以真实事件和原生读回检查对应子项。

## rerun-batch15-testing 自动检查点

- 命令 `testing {}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-testing.json` 及同前缀文件。
```json
[
  {
    "ms": 22867,
    "kind": "BEGIN",
    "group": "testing",
    "args": {
      "group": "testing"
    }
  },
  {
    "ms": 22905,
    "kind": "CHECK",
    "id": "A33",
    "pass": true,
    "detail": "kernels=1 pip=false"
  },
  {
    "ms": 22905,
    "kind": "STAGED_OPTIONS",
    "options": [
      {
        "network-timeout": "7"
      }
    ]
  },
  {
    "ms": 22906,
    "kind": "END",
    "group": "testing",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-options

- 执行 new {'case': 'options'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-options 自动检查点

- 命令 `new {'case': 'options'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-options.json` 及同前缀文件。
```json
[
  {
    "ms": 26004,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "options"
    }
  },
  {
    "ms": 26054,
    "kind": "PREVIEW_THUMB",
    "engine": 349385964,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 26231,
    "kind": "CHECK",
    "id": "N4.applied",
    "pass": true,
    "detail": "{network-timeout: 7.000000, demuxer-lavf-o: seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto,analyzeduration=123456, cache: no, vid: no, mute: no}"
  },
  {
    "ms": 26231,
    "kind": "PREVIEW_THUMB",
    "engine": 349385964,
    "at": null,
    "bytes": null,
    "title": "Coverage ad.mp4"
  },
  {
    "ms": 26391,
    "kind": "CHECK",
    "id": "N1.network",
    "pass": true,
    "detail": "{network-timeout: 2.000000, demuxer-lavf-o: seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto, cache: yes, vid: no, mute: no}"
  },
  {
    "ms": 26392,
    "kind": "CHECK",
    "id": "N4.restore",
    "pass": true,
    "detail": "{before: {network-timeout: 5.000000, demuxer-lavf-o: seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto, cache: yes, vid: no, mute: no}, custom: {network-timeout: 7.000000, demuxer-lavf-o: seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto,analyzeduration=123456, cache: no, vid: no, mute: no}, restored: {network-timeout: 2.000000, demuxer-lavf-o: seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto, cache: yes, vid: no, mute: no}}"
  },
  {
    "ms": 26392,
    "kind": "PREVIEW_THUMB",
    "engine": 349385964,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 26422,
    "kind": "WHEP_OPTIONS_READBACK",
    "network-timeout": "1.000000",
    "demuxer-lavf-o": "seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto,first_frame_timeout=8000000,media_timeout=6000000,handshake_timeout=2000000",
    "cache": "yes",
    "vid": "no",
    "mute": "no"
  },
  {
    "ms": 26422,
    "kind": "CHECK",
    "id": "N4.whepOptions",
    "pass": true,
    "detail": "readback={network-timeout: 1.000000, demuxer-lavf-o: seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto,first_frame_timeout=8000000,media_timeout=6000000,handshake_timeout=2000000, cache: yes, vid: no, mute: no}"
  },
  {
    "ms": 26422,
    "kind": "PREVIEW_THUMB",
    "engine": 349385964,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 26549,
    "kind": "WHEP_OPTIONS_RESTORED",
    "network-timeout": "2.000000",
    "demuxer-lavf-o": "seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto",
    "cache": "yes",
    "vid": "no",
    "mute": "no"
  },
  {
    "ms": 26549,
    "kind": "CHECK",
    "id": "N2.derived",
    "pass": true,
    "detail": "http=65,whepStart=85,whepStall=10,watchdogOff=null,clear=null"
  },
  {
    "ms": 26549,
    "kind": "NEW_CONFIG",
    "whep": {
      "demuxer-lavf-o": "media_timeout=8000000,handshake_timeout=2000000,first_frame_timeout=3000000"
    },
    "http": {
      "demuxer-lavf-o": "media_timeout=8000000"
    },
    "defaults": {}
  },
  {
    "ms": 26549,
    "kind": "CHECK",
    "id": "C17.pick",
    "pass": true,
    "detail": "[http://a, http://b]"
  },
  {
    "ms": 26549,
    "kind": "PREVIEW_THUMB",
    "engine": 349385964,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 27050,
    "kind": "HEADERS_NATIVE",
    "options": "X-Coverage: 42"
  },
  {
    "ms": 27133,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-hooks

- 执行 new {'case': 'hooks'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-hooks 自动检查点

- 命令 `new {'case': 'hooks'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-hooks.json` 及同前缀文件。
```json
[
  {
    "ms": 30315,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hooks"
    }
  },
  {
    "ms": 30349,
    "kind": "CHECK",
    "id": "N8.reject",
    "pass": true,
    "detail": "beforeOpen=false"
  },
  {
    "ms": 30349,
    "kind": "PREVIEW_THUMB",
    "engine": 47672277,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 30401,
    "kind": "CHECK",
    "id": "N8.accept",
    "pass": true,
    "detail": "accepted=true"
  },
  {
    "ms": 30790,
    "kind": "CHECK",
    "id": "N22.stalePlay",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: true, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 30945,
    "kind": "PREVIEW_THUMB",
    "engine": 47672277,
    "at": null,
    "bytes": null,
    "title": "Coverage ad.mp4"
  },
  {
    "ms": 32011,
    "kind": "HOOK_SEEK_FINAL",
    "playing": false,
    "intent": false,
    "buffering": false,
    "duration": 20000,
    "position": 23,
    "size": "0x0",
    "volume": 30.0,
    "brightness": 1.0,
    "rate": 1.0,
    "fit": "contain",
    "zoom": 1.0,
    "locked": false,
    "fullscreen": false,
    "orientation": "auto",
    "pip": false,
    "mini": false,
    "rendered": true,
    "epoch": 0,
    "sourceIndex": 0,
    "keepAlive": "off",
    "type": "vod",
    "title": "Coverage ad.mp4",
    "pipSupported": true,
    "controls": true,
    "hud": "none",
    "previewCurrent": null,
    "timeshiftBehind": null,
    "liveSeekable": false,
    "seekableWindow": 20000,
    "hudText": null,
    "dragging": false,
    "previewAt": null
  },
  {
    "ms": 32013,
    "kind": "HOOK_PLAYLIST",
    "index": 0
  },
  {
    "ms": 32013,
    "kind": "CHECK",
    "id": "N8.playlistRejected",
    "pass": true,
    "detail": "rejected jumpTo(1), index=0"
  },
  {
    "ms": 32118,
    "kind": "PREVIEW_THUMB",
    "engine": 47672277,
    "at": null,
    "bytes": null,
    "title": "Coverage ad.mp4"
  },
  {
    "ms": 32193,
    "kind": "CHECK",
    "id": "N8.superseded",
    "pass": true,
    "detail": "first=false second=true"
  },
  {
    "ms": 32193,
    "kind": "HOOK_EXPECTED_THROW",
    "error": "Bad state: coverage hook failure"
  },
  {
    "ms": 32194,
    "kind": "CHECK",
    "id": "A32.afterThrow",
    "pass": true,
    "detail": "play works after hook exception"
  },
  {
    "ms": 32346,
    "kind": "CHECK",
    "id": "A32.seekVeto",
    "pass": true,
    "detail": "seek cancelled"
  },
  {
    "ms": 32347,
    "kind": "PREVIEW_THUMB",
    "engine": 47672277,
    "at": null,
    "bytes": null,
    "title": "Coverage 404.mp4"
  },
  {
    "ms": 32427,
    "kind": "CHECK",
    "id": "A32.onErrorIsolation",
    "pass": true,
    "detail": "firstHook=1 secondHook=1"
  },
  {
    "ms": 32428,
    "kind": "PREVIEW_THUMB",
    "engine": 47672277,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 32605,
    "kind": "CHECK",
    "id": "N8.disposed",
    "pass": true,
    "detail": "disposed=false"
  },
  {
    "ms": 32605,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-hooks-cutover

- 执行 new {'case': 'hooks', 'cutover': 'true'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-hooks-cutover 自动检查点

- 命令 `new {'case': 'hooks', 'cutover': 'true'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-hooks-cutover.json` 及同前缀文件。
```json
[
  {
    "ms": 35868,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hooks",
      "cutover": "true"
    }
  },
  {
    "ms": 35929,
    "kind": "CHECK",
    "id": "N8.reject",
    "pass": true,
    "detail": "beforeOpen=false"
  },
  {
    "ms": 35929,
    "kind": "PREVIEW_THUMB",
    "engine": 912520638,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 35982,
    "kind": "CHECK",
    "id": "N8.accept",
    "pass": true,
    "detail": "accepted=true"
  },
  {
    "ms": 36372,
    "kind": "CHECK",
    "id": "N22.stalePlay",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, keepAlive: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: true, hud: none, previewCurrent: null, timeshiftBehind: null, liveSeekable: false, seekableWindow: 40000, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 36524,
    "kind": "PREVIEW_THUMB",
    "engine": 912520638,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 37615,
    "kind": "HOOK_SEEK_FINAL",
    "playing": false,
    "intent": false,
    "buffering": false,
    "duration": 20000,
    "position": 23,
    "size": "0x0",
    "volume": 30.0,
    "brightness": 1.0,
    "rate": 1.0,
    "fit": "contain",
    "zoom": 1.0,
    "locked": false,
    "fullscreen": false,
    "orientation": "auto",
    "pip": false,
    "mini": false,
    "rendered": true,
    "epoch": 0,
    "sourceIndex": 0,
    "keepAlive": "off",
    "type": "vod",
    "title": "Coverage ad.mp4",
    "pipSupported": true,
    "controls": true,
    "hud": "none",
    "previewCurrent": null,
    "timeshiftBehind": null,
    "liveSeekable": false,
    "seekableWindow": 20000,
    "hudText": null,
    "dragging": false,
    "previewAt": null
  },
  {
    "ms": 37629,
    "kind": "HOOK_PLAYLIST",
    "index": 0
  },
  {
    "ms": 37629,
    "kind": "CHECK",
    "id": "N8.playlistRejected",
    "pass": true,
    "detail": "rejected jumpTo(1), index=0"
  },
  {
    "ms": 37732,
    "kind": "PREVIEW_THUMB",
    "engine": 912520638,
    "at": null,
    "bytes": null,
    "title": "Coverage ad.mp4"
  },
  {
    "ms": 37786,
    "kind": "CHECK",
    "id": "N8.superseded",
    "pass": true,
    "detail": "first=false second=true"
  },
  {
    "ms": 37786,
    "kind": "HOOK_EXPECTED_THROW",
    "error": "Bad state: coverage hook failure"
  },
  {
    "ms": 37787,
    "kind": "CHECK",
    "id": "A32.afterThrow",
    "pass": true,
    "detail": "play works after hook exception"
  },
  {
    "ms": 37939,
    "kind": "CHECK",
    "id": "A32.seekVeto",
    "pass": true,
    "detail": "seek cancelled"
  },
  {
    "ms": 37940,
    "kind": "PREVIEW_THUMB",
    "engine": 912520638,
    "at": null,
    "bytes": null,
    "title": "Coverage ad.mp4"
  },
  {
    "ms": 38018,
    "kind": "CHECK",
    "id": "A32.onErrorIsolation",
    "pass": true,
    "detail": "firstHook=1 secondHook=1"
  },
  {
    "ms": 38019,
    "kind": "PREVIEW_THUMB",
    "engine": 912520638,
    "at": null,
    "bytes": null,
    "title": "Coverage 404.mp4"
  },
  {
    "ms": 38215,
    "kind": "CHECK",
    "id": "N8.disposed",
    "pass": true,
    "detail": "disposed=false"
  },
  {
    "ms": 38215,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-recovery-liveDefault

- 执行 new {'case': 'recovery', 'mode': 'liveDefault'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-recovery-liveDefault 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'liveDefault'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-recovery-liveDefault.json` 及同前缀文件。
```json
[
  {
    "ms": 41445,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "liveDefault"
    }
  },
  {
    "ms": 41505,
    "kind": "PREVIEW_THUMB",
    "engine": 96757936,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 41559,
    "kind": "RECOVERY_OPEN",
    "mode": "liveDefault",
    "accepted": true
  },
  {
    "ms": 41570,
    "kind": "nativeEndError",
    "mode": "liveDefault",
    "since": 125,
    "attempt": 1,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 42655,
    "kind": "nativeEndError",
    "mode": "liveDefault",
    "since": 1210,
    "attempt": 2,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 44714,
    "kind": "nativeEndError",
    "mode": "liveDefault",
    "since": 3269,
    "attempt": 3,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 44715,
    "kind": "CHECK",
    "id": "N3.defaultLive",
    "pass": true,
    "detail": "third failure still retries"
  },
  {
    "ms": 44715,
    "kind": "RECOVERY_END",
    "mode": "liveDefault",
    "state": {
      "playing": true,
      "intent": true,
      "buffering": true,
      "duration": 0,
      "position": 0,
      "size": "0x0",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": false,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "live",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 0,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "Failed to open http://127.0.0.1:18080/not-found.mp4?t=1793093011423546."
  },
  {
    "ms": 44724,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-recovery-liveLegacy

- 执行 new {'case': 'recovery', 'mode': 'liveLegacy'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-recovery-liveLegacy 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'liveLegacy'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-recovery-liveLegacy.json` 及同前缀文件。
```json
[
  {
    "ms": 47390,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "liveLegacy"
    }
  },
  {
    "ms": 47454,
    "kind": "PREVIEW_THUMB",
    "engine": 214741108,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 47515,
    "kind": "RECOVERY_OPEN",
    "mode": "liveLegacy",
    "accepted": true
  },
  {
    "ms": 47529,
    "kind": "nativeEndError",
    "mode": "liveLegacy",
    "since": 138,
    "attempt": 1,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 48624,
    "kind": "nativeEndError",
    "mode": "liveLegacy",
    "since": 1233,
    "attempt": 2,
    "live": true,
    "action": "giveUp"
  },
  {
    "ms": 48649,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/not-found.mp4?t=1793093017371009) buffering=false"
  },
  {
    "ms": 48649,
    "kind": "RECOVERY_END",
    "mode": "liveLegacy",
    "state": {
      "playing": false,
      "intent": true,
      "buffering": false,
      "duration": 0,
      "position": 0,
      "size": "0x0",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": false,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "live",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 0,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/not-found.mp4?t=1793093017371009)"
  },
  {
    "ms": 48660,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-recovery-liveAlternatives

- 执行 new {'case': 'recovery', 'mode': 'liveAlternatives'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-recovery-liveAlternatives 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'liveAlternatives'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-recovery-liveAlternatives.json` 及同前缀文件。
```json
[
  {
    "ms": 51718,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "liveAlternatives"
    }
  },
  {
    "ms": 51773,
    "kind": "PREVIEW_THUMB",
    "engine": 924088001,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 51821,
    "kind": "RECOVERY_OPEN",
    "mode": "liveAlternatives",
    "accepted": true
  },
  {
    "ms": 51832,
    "kind": "nativeEndError",
    "mode": "liveAlternatives",
    "since": 114,
    "attempt": 1,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 51905,
    "kind": "nativeEndError",
    "mode": "liveAlternatives",
    "since": 187,
    "attempt": 2,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 52042,
    "kind": "nativeEndError",
    "mode": "liveAlternatives",
    "since": 323,
    "attempt": 3,
    "live": true,
    "action": "failover"
  },
  {
    "ms": 52095,
    "kind": "nativeEndError",
    "mode": "liveAlternatives",
    "since": 377,
    "attempt": 1,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 52183,
    "kind": "nativeEndError",
    "mode": "liveAlternatives",
    "since": 465,
    "attempt": 2,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 52348,
    "kind": "nativeEndError",
    "mode": "liveAlternatives",
    "since": 630,
    "attempt": 3,
    "live": true,
    "action": "giveUp"
  },
  {
    "ms": 52386,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/other404.mp4?t=1793093021692738) buffering=false"
  },
  {
    "ms": 52387,
    "kind": "RECOVERY_END",
    "mode": "liveAlternatives",
    "state": {
      "playing": false,
      "intent": true,
      "buffering": false,
      "duration": 0,
      "position": 0,
      "size": "0x0",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": false,
      "epoch": 0,
      "sourceIndex": 1,
      "keepAlive": "off",
      "type": "live",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 0,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/other404.mp4?t=1793093021692738)"
  },
  {
    "ms": 52403,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-hang-default-0

- 执行 new {'case': 'recovery', 'mode': 'hangDefault'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-hang-default-0 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'hangDefault'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-hang-default-0.json` 及同前缀文件。
```json
[
  {
    "ms": 55392,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "hangDefault"
    }
  },
  {
    "ms": 55465,
    "kind": "PREVIEW_THUMB",
    "engine": 400540436,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 55509,
    "kind": "RECOVERY_OPEN",
    "mode": "hangDefault",
    "accepted": true
  },
  {
    "ms": 60651,
    "kind": "nativeEndError",
    "mode": "hangDefault",
    "since": 5259,
    "attempt": 1,
    "live": false,
    "action": "giveUp"
  },
  {
    "ms": 60663,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793093025370223) buffering=false"
  },
  {
    "ms": 60664,
    "kind": "RECOVERY_END",
    "mode": "hangDefault",
    "state": {
      "playing": false,
      "intent": true,
      "buffering": false,
      "duration": 0,
      "position": 0,
      "size": "0x0",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": false,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 0,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793093025370223)"
  },
  {
    "ms": 60677,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-hang-2s-0

- 执行 new {'case': 'recovery', 'mode': 'hang'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-hang-2s-0 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'hang'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-hang-2s-0.json` 及同前缀文件。
```json
[
  {
    "ms": 63789,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "hang"
    }
  },
  {
    "ms": 63838,
    "kind": "PREVIEW_THUMB",
    "engine": 128417599,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 63899,
    "kind": "RECOVERY_OPEN",
    "mode": "hang",
    "accepted": true
  },
  {
    "ms": 66038,
    "kind": "nativeEndError",
    "mode": "hang",
    "since": 2249,
    "attempt": 1,
    "live": false,
    "action": "giveUp"
  },
  {
    "ms": 66048,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793093033753713) buffering=false"
  },
  {
    "ms": 66049,
    "kind": "RECOVERY_END",
    "mode": "hang",
    "state": {
      "playing": false,
      "intent": true,
      "buffering": false,
      "duration": 0,
      "position": 0,
      "size": "0x0",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": false,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 0,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793093033753713)"
  },
  {
    "ms": 66061,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-hang-default-1

- 执行 new {'case': 'recovery', 'mode': 'hangDefault'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-hang-default-1 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'hangDefault'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-hang-default-1.json` 及同前缀文件。
```json
[
  {
    "ms": 68727,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "hangDefault"
    }
  },
  {
    "ms": 68785,
    "kind": "PREVIEW_THUMB",
    "engine": 342451355,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 68860,
    "kind": "RECOVERY_OPEN",
    "mode": "hangDefault",
    "accepted": true
  },
  {
    "ms": 74007,
    "kind": "nativeEndError",
    "mode": "hangDefault",
    "since": 5279,
    "attempt": 1,
    "live": false,
    "action": "giveUp"
  },
  {
    "ms": 74029,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793093038694506) buffering=false"
  },
  {
    "ms": 74029,
    "kind": "RECOVERY_END",
    "mode": "hangDefault",
    "state": {
      "playing": false,
      "intent": true,
      "buffering": false,
      "duration": 0,
      "position": 0,
      "size": "0x0",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": false,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 0,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793093038694506)"
  },
  {
    "ms": 74045,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-hang-2s-1

- 执行 new {'case': 'recovery', 'mode': 'hang'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-hang-2s-1 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'hang'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-hang-2s-1.json` 及同前缀文件。
```json
[
  {
    "ms": 77681,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "hang"
    }
  },
  {
    "ms": 77731,
    "kind": "PREVIEW_THUMB",
    "engine": 688750727,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 77790,
    "kind": "RECOVERY_OPEN",
    "mode": "hang",
    "accepted": true
  },
  {
    "ms": 79918,
    "kind": "nativeEndError",
    "mode": "hang",
    "since": 2237,
    "attempt": 1,
    "live": false,
    "action": "giveUp"
  },
  {
    "ms": 79930,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793093047646925) buffering=false"
  },
  {
    "ms": 79930,
    "kind": "RECOVERY_END",
    "mode": "hang",
    "state": {
      "playing": false,
      "intent": true,
      "buffering": false,
      "duration": 0,
      "position": 0,
      "size": "0x0",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": false,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 0,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793093047646925)"
  },
  {
    "ms": 79943,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-hang-default-2

- 执行 new {'case': 'recovery', 'mode': 'hangDefault'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-hang-default-2 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'hangDefault'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-hang-default-2.json` 及同前缀文件。
```json
[
  {
    "ms": 82799,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "hangDefault"
    }
  },
  {
    "ms": 82862,
    "kind": "PREVIEW_THUMB",
    "engine": 288665010,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 82927,
    "kind": "RECOVERY_OPEN",
    "mode": "hangDefault",
    "accepted": true
  },
  {
    "ms": 88079,
    "kind": "nativeEndError",
    "mode": "hangDefault",
    "since": 5279,
    "attempt": 1,
    "live": false,
    "action": "giveUp"
  },
  {
    "ms": 88106,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793093052772101) buffering=false"
  },
  {
    "ms": 88106,
    "kind": "RECOVERY_END",
    "mode": "hangDefault",
    "state": {
      "playing": false,
      "intent": true,
      "buffering": false,
      "duration": 0,
      "position": 0,
      "size": "0x0",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": false,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 0,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793093052772101)"
  },
  {
    "ms": 88114,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-hang-2s-2

- 执行 new {'case': 'recovery', 'mode': 'hang'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-hang-2s-2 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'hang'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-hang-2s-2.json` 及同前缀文件。
```json
[
  {
    "ms": 91113,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "hang"
    }
  },
  {
    "ms": 91178,
    "kind": "PREVIEW_THUMB",
    "engine": 336870188,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 91235,
    "kind": "RECOVERY_OPEN",
    "mode": "hang",
    "accepted": true
  },
  {
    "ms": 93376,
    "kind": "nativeEndError",
    "mode": "hang",
    "since": 2263,
    "attempt": 1,
    "live": false,
    "action": "giveUp"
  },
  {
    "ms": 93394,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793093061090555) buffering=false"
  },
  {
    "ms": 93394,
    "kind": "RECOVERY_END",
    "mode": "hang",
    "state": {
      "playing": false,
      "intent": true,
      "buffering": false,
      "duration": 0,
      "position": 0,
      "size": "0x0",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": false,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 0,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793093061090555)"
  },
  {
    "ms": 93405,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-watchoff

- 执行 new {'case': 'watchoff'}；以真实事件和原生读回检查对应子项。

## API首批判定检查点

- 已完成项目即时回填；其他编号继续保留本次未完成。

## rerun-batch15-watchoff 自动检查点

- 命令 `new {'case': 'watchoff'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-watchoff.json` 及同前缀文件。
```json
[
  {
    "ms": 96072,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "watchoff"
    }
  },
  {
    "ms": 96137,
    "kind": "PREVIEW_THUMB",
    "engine": 693932308,
    "at": null,
    "bytes": null,
    "title": "Coverage stall.mp4"
  },
  {
    "ms": 104069,
    "kind": "CHECK",
    "id": "N2.watchoff",
    "pass": true,
    "detail": "rendered=true buffering=true failures=0"
  },
  {
    "ms": 104147,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-stt

- 执行 new {'case': 'stt'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-stt 自动检查点

- 命令 `new {'case': 'stt'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-stt.json` 及同前缀文件。
```json
[
  {
    "ms": 107084,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "stt"
    }
  },
  {
    "ms": 107157,
    "kind": "PREVIEW_THUMB",
    "engine": 670137041,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 107218,
    "kind": "STT_NO_ENGINE",
    "running": false,
    "languages": []
  },
  {
    "ms": 107241,
    "kind": "PREVIEW_THUMB",
    "engine": 507856863,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 107288,
    "kind": "STT_EXPECTED_THROW",
    "error": "Bad state: coverage missing model",
    "running": false
  },
  {
    "ms": 107288,
    "kind": "CHECK",
    "id": "N22.sttRollback",
    "pass": true,
    "detail": "after first failure running=false"
  },
  {
    "ms": 107289,
    "kind": "CHECK",
    "id": "N22.sttRetry",
    "pass": true,
    "detail": "calls=2 running=true"
  },
  {
    "ms": 107297,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-live-step0-0

- 执行 new {'case': 'live', 'step': '0'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-live-step0-0 自动检查点

- 命令 `new {'case': 'live', 'step': '0'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-live-step0-0.json` 及同前缀文件。
```json
[
  {
    "ms": 110305,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "live",
      "step": "0"
    }
  },
  {
    "ms": 110365,
    "kind": "PREVIEW_THUMB",
    "engine": 672154639,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 112302,
    "kind": "CHECK",
    "id": "A7.live",
    "pass": true,
    "detail": "seek events before=7 after=7"
  },
  {
    "ms": 123370,
    "kind": "LIVE_DURATION",
    "step": 0,
    "samples": [
      {
        "ms": 110414,
        "duration": 0
      },
      {
        "ms": 112260,
        "duration": 720
      },
      {
        "ms": 112317,
        "duration": 1695
      },
      {
        "ms": 112357,
        "duration": 1764
      },
      {
        "ms": 112512,
        "duration": 1927
      },
      {
        "ms": 112763,
        "duration": 2182
      },
      {
        "ms": 112776,
        "duration": 2206
      },
      {
        "ms": 112813,
        "duration": 2252
      },
      {
        "ms": 113013,
        "duration": 2461
      },
      {
        "ms": 113283,
        "duration": 2740
      },
      {
        "ms": 113313,
        "duration": 2763
      },
      {
        "ms": 113514,
        "duration": 2972
      },
      {
        "ms": 113764,
        "duration": 3251
      },
      {
        "ms": 114016,
        "duration": 3483
      },
      {
        "ms": 114265,
        "duration": 3761
      },
      {
        "ms": 114515,
        "duration": 4017
      },
      {
        "ms": 114766,
        "duration": 4295
      },
      {
        "ms": 115046,
        "duration": 4574
      },
      {
        "ms": 115276,
        "duration": 4806
      },
      {
        "ms": 115321,
        "duration": 4853
      },
      {
        "ms": 115526,
        "duration": 5085
      },
      {
        "ms": 115569,
        "duration": 5131
      },
      {
        "ms": 115771,
        "duration": 5340
      },
      {
        "ms": 115785,
        "duration": 5364
      },
      {
        "ms": 115820,
        "duration": 5410
      },
      {
        "ms": 116023,
        "duration": 5619
      },
      {
        "ms": 116069,
        "duration": 5642
      },
      {
        "ms": 116289,
        "duration": 5851
      },
      {
        "ms": 116321,
        "duration": 5921
      },
      {
        "ms": 116524,
        "duration": 6130
      },
      {
        "ms": 116569,
        "duration": 6176
      },
      {
        "ms": 116803,
        "duration": 6408
      },
      {
        "ms": 116820,
        "duration": 6432
      },
      {
        "ms": 117024,
        "duration": 6641
      },
      {
        "ms": 117038,
        "duration": 6687
      },
      {
        "ms": 117278,
        "duration": 6919
      },
      {
        "ms": 117320,
        "duration": 6966
      },
      {
        "ms": 117523,
        "duration": 7175
      },
      {
        "ms": 117539,
        "duration": 7221
      },
      {
        "ms": 117774,
        "duration": 7453
      },
      {
        "ms": 117820,
        "duration": 7500
      },
      {
        "ms": 118021,
        "duration": 7686
      },
      {
        "ms": 118046,
        "duration": 7732
      },
      {
        "ms": 118076,
        "duration": 7778
      },
      {
        "ms": 118274,
        "duration": 7964
      },
      {
        "ms": 118320,
        "duration": 8011
      },
      {
        "ms": 118524,
        "duration": 8220
      },
      {
        "ms": 118585,
        "duration": 8289
      },
      {
        "ms": 118774,
        "duration": 8498
      },
      {
        "ms": 118805,
        "duration": 8522
      },
      {
        "ms": 119025,
        "duration": 8777
      },
      {
        "ms": 119059,
        "duration": 8800
      },
      {
        "ms": 119274,
        "duration": 9009
      },
      {
        "ms": 119306,
        "duration": 9056
      },
      {
        "ms": 119523,
        "duration": 9288
      },
      {
        "ms": 119569,
        "duration": 9334
      },
      {
        "ms": 119773,
        "duration": 9520
      },
      {
        "ms": 119807,
        "duration": 9566
      },
      {
        "ms": 119820,
        "duration": 9613
      },
      {
        "ms": 120025,
        "duration": 9845
      },
      {
        "ms": 120058,
        "duration": 9891
      },
      {
        "ms": 120332,
        "duration": 10124
      },
      {
        "ms": 120524,
        "duration": 10333
      },
      {
        "ms": 120559,
        "duration": 10379
      },
      {
        "ms": 120769,
        "duration": 10565
      },
      {
        "ms": 120808,
        "duration": 10611
      },
      {
        "ms": 120816,
        "duration": 10658
      },
      {
        "ms": 121030,
        "duration": 10843
      },
      {
        "ms": 121059,
        "duration": 10890
      },
      {
        "ms": 121272,
        "duration": 11099
      },
      {
        "ms": 121309,
        "duration": 11122
      },
      {
        "ms": 121526,
        "duration": 11331
      },
      {
        "ms": 121562,
        "duration": 11378
      },
      {
        "ms": 121575,
        "duration": 11401
      },
      {
        "ms": 121774,
        "duration": 11610
      },
      {
        "ms": 121820,
        "duration": 11656
      },
      {
        "ms": 122025,
        "duration": 11842
      },
      {
        "ms": 122106,
        "duration": 11865
      },
      {
        "ms": 122273,
        "duration": 12097
      },
      {
        "ms": 122314,
        "duration": 12121
      },
      {
        "ms": 122524,
        "duration": 12330
      },
      {
        "ms": 122564,
        "duration": 12376
      },
      {
        "ms": 122770,
        "duration": 12608
      },
      {
        "ms": 123025,
        "duration": 12817
      },
      {
        "ms": 123028,
        "duration": 12840
      },
      {
        "ms": 123068,
        "duration": 12887
      },
      {
        "ms": 123273,
        "duration": 13096
      },
      {
        "ms": 123313,
        "duration": 0
      }
    ]
  },
  {
    "ms": 123375,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-live-step2000-0

- 执行 new {'case': 'live', 'step': '2000'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-live-step2000-0 自动检查点

- 命令 `new {'case': 'live', 'step': '2000'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-live-step2000-0.json` 及同前缀文件。
```json
[
  {
    "ms": 126573,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "live",
      "step": "2000"
    }
  },
  {
    "ms": 126652,
    "kind": "PREVIEW_THUMB",
    "engine": 465614527,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 128579,
    "kind": "CHECK",
    "id": "A7.live",
    "pass": true,
    "detail": "seek events before=7 after=7"
  },
  {
    "ms": 139673,
    "kind": "LIVE_DURATION",
    "step": 2000,
    "samples": [
      {
        "ms": 126708,
        "duration": 0
      },
      {
        "ms": 128545,
        "duration": 882
      },
      {
        "ms": 129797,
        "duration": 2972
      },
      {
        "ms": 131811,
        "duration": 5085
      },
      {
        "ms": 133810,
        "duration": 7175
      },
      {
        "ms": 135813,
        "duration": 9288
      },
      {
        "ms": 137813,
        "duration": 11354
      },
      {
        "ms": 139634,
        "duration": 0
      }
    ]
  },
  {
    "ms": 139688,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-live-step0-1

- 执行 new {'case': 'live', 'step': '0'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-live-step0-1 自动检查点

- 命令 `new {'case': 'live', 'step': '0'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-live-step0-1.json` 及同前缀文件。
```json
[
  {
    "ms": 142875,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "live",
      "step": "0"
    }
  },
  {
    "ms": 142952,
    "kind": "PREVIEW_THUMB",
    "engine": 118091165,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 144815,
    "kind": "CHECK",
    "id": "A7.live",
    "pass": true,
    "detail": "seek events before=7 after=7"
  },
  {
    "ms": 155866,
    "kind": "LIVE_DURATION",
    "step": 0,
    "samples": [
      {
        "ms": 142998,
        "duration": 0
      },
      {
        "ms": 144814,
        "duration": 1695
      },
      {
        "ms": 144856,
        "duration": 1741
      },
      {
        "ms": 145003,
        "duration": 1881
      },
      {
        "ms": 145023,
        "duration": 1904
      },
      {
        "ms": 145054,
        "duration": 1973
      },
      {
        "ms": 145254,
        "duration": 2182
      },
      {
        "ms": 145504,
        "duration": 2415
      },
      {
        "ms": 145522,
        "duration": 2461
      },
      {
        "ms": 145755,
        "duration": 2693
      },
      {
        "ms": 145781,
        "duration": 2740
      },
      {
        "ms": 146006,
        "duration": 2925
      },
      {
        "ms": 146022,
        "duration": 2972
      },
      {
        "ms": 146056,
        "duration": 2995
      },
      {
        "ms": 146262,
        "duration": 3204
      },
      {
        "ms": 146521,
        "duration": 3483
      },
      {
        "ms": 146768,
        "duration": 3738
      },
      {
        "ms": 147025,
        "duration": 3970
      },
      {
        "ms": 147079,
        "duration": 4040
      },
      {
        "ms": 147279,
        "duration": 4295
      },
      {
        "ms": 147324,
        "duration": 4342
      },
      {
        "ms": 147524,
        "duration": 4528
      },
      {
        "ms": 147569,
        "duration": 4574
      },
      {
        "ms": 147781,
        "duration": 4783
      },
      {
        "ms": 147822,
        "duration": 4853
      },
      {
        "ms": 148024,
        "duration": 5062
      },
      {
        "ms": 148033,
        "duration": 5085
      },
      {
        "ms": 148276,
        "duration": 5340
      },
      {
        "ms": 148318,
        "duration": 5364
      },
      {
        "ms": 148525,
        "duration": 5619
      },
      {
        "ms": 148570,
        "duration": 5642
      },
      {
        "ms": 148774,
        "duration": 5851
      },
      {
        "ms": 148858,
        "duration": 5898
      },
      {
        "ms": 149025,
        "duration": 6130
      },
      {
        "ms": 149071,
        "duration": 6176
      },
      {
        "ms": 149275,
        "duration": 6362
      },
      {
        "ms": 149286,
        "duration": 6408
      },
      {
        "ms": 149525,
        "duration": 6641
      },
      {
        "ms": 149570,
        "duration": 6687
      },
      {
        "ms": 149777,
        "duration": 6919
      },
      {
        "ms": 149828,
        "duration": 6966
      },
      {
        "ms": 150054,
        "duration": 7175
      },
      {
        "ms": 150072,
        "duration": 7221
      },
      {
        "ms": 150273,
        "duration": 7407
      },
      {
        "ms": 150289,
        "duration": 7453
      },
      {
        "ms": 150321,
        "duration": 7500
      },
      {
        "ms": 150521,
        "duration": 7686
      },
      {
        "ms": 150571,
        "duration": 7732
      },
      {
        "ms": 150798,
        "duration": 7941
      },
      {
        "ms": 150802,
        "duration": 7964
      },
      {
        "ms": 150822,
        "duration": 8011
      },
      {
        "ms": 151021,
        "duration": 8220
      },
      {
        "ms": 151051,
        "duration": 8243
      },
      {
        "ms": 151272,
        "duration": 8498
      },
      {
        "ms": 151323,
        "duration": 8522
      },
      {
        "ms": 151521,
        "duration": 8730
      },
      {
        "ms": 151550,
        "duration": 8777
      },
      {
        "ms": 151817,
        "duration": 9009
      },
      {
        "ms": 151825,
        "duration": 9056
      },
      {
        "ms": 152024,
        "duration": 9241
      },
      {
        "ms": 152051,
        "duration": 9288
      },
      {
        "ms": 152070,
        "duration": 9334
      },
      {
        "ms": 152274,
        "duration": 9520
      },
      {
        "ms": 152302,
        "duration": 9566
      },
      {
        "ms": 152540,
        "duration": 9822
      },
      {
        "ms": 152778,
        "duration": 10100
      },
      {
        "ms": 152822,
        "duration": 10124
      },
      {
        "ms": 153055,
        "duration": 10379
      },
      {
        "ms": 153276,
        "duration": 10565
      },
      {
        "ms": 153303,
        "duration": 10611
      },
      {
        "ms": 153523,
        "duration": 10820
      },
      {
        "ms": 153554,
        "duration": 10843
      },
      {
        "ms": 153773,
        "duration": 11052
      },
      {
        "ms": 153806,
        "duration": 11099
      },
      {
        "ms": 153820,
        "duration": 11122
      },
      {
        "ms": 154024,
        "duration": 11331
      },
      {
        "ms": 154273,
        "duration": 11563
      },
      {
        "ms": 154306,
        "duration": 11610
      },
      {
        "ms": 154525,
        "duration": 11819
      },
      {
        "ms": 154557,
        "duration": 11842
      },
      {
        "ms": 154776,
        "duration": 12097
      },
      {
        "ms": 154838,
        "duration": 12121
      },
      {
        "ms": 155024,
        "duration": 12330
      },
      {
        "ms": 155060,
        "duration": 12376
      },
      {
        "ms": 155281,
        "duration": 12562
      },
      {
        "ms": 155309,
        "duration": 12608
      },
      {
        "ms": 155524,
        "duration": 12817
      },
      {
        "ms": 155560,
        "duration": 12840
      },
      {
        "ms": 155570,
        "duration": 12864
      },
      {
        "ms": 155773,
        "duration": 13096
      },
      {
        "ms": 155826,
        "duration": 0
      }
    ]
  },
  {
    "ms": 155872,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-live-step2000-1

- 执行 new {'case': 'live', 'step': '2000'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-live-step2000-1 自动检查点

- 命令 `new {'case': 'live', 'step': '2000'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-live-step2000-1.json` 及同前缀文件。
```json
[
  {
    "ms": 158705,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "live",
      "step": "2000"
    }
  },
  {
    "ms": 158779,
    "kind": "PREVIEW_THUMB",
    "engine": 730181815,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 160634,
    "kind": "CHECK",
    "id": "A7.live",
    "pass": true,
    "detail": "seek events before=7 after=7"
  },
  {
    "ms": 171723,
    "kind": "LIVE_DURATION",
    "step": 2000,
    "samples": [
      {
        "ms": 158813,
        "duration": 0
      },
      {
        "ms": 160633,
        "duration": 1695
      },
      {
        "ms": 162597,
        "duration": 3761
      },
      {
        "ms": 164599,
        "duration": 5805
      },
      {
        "ms": 166597,
        "duration": 7941
      },
      {
        "ms": 168594,
        "duration": 10077
      },
      {
        "ms": 170618,
        "duration": 12097
      },
      {
        "ms": 171641,
        "duration": 0
      }
    ]
  },
  {
    "ms": 171731,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-live-step0-2

- 执行 new {'case': 'live', 'step': '0'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-live-step0-2 自动检查点

- 命令 `new {'case': 'live', 'step': '0'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-live-step0-2.json` 及同前缀文件。
```json
[
  {
    "ms": 174915,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "live",
      "step": "0"
    }
  },
  {
    "ms": 174998,
    "kind": "PREVIEW_THUMB",
    "engine": 695974669,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 176855,
    "kind": "CHECK",
    "id": "A7.live",
    "pass": true,
    "detail": "seek events before=7 after=7"
  },
  {
    "ms": 187933,
    "kind": "LIVE_DURATION",
    "step": 0,
    "samples": [
      {
        "ms": 175036,
        "duration": 0
      },
      {
        "ms": 176803,
        "duration": 1648
      },
      {
        "ms": 176853,
        "duration": 1695
      },
      {
        "ms": 176893,
        "duration": 1741
      },
      {
        "ms": 177046,
        "duration": 1881
      },
      {
        "ms": 177295,
        "duration": 2182
      },
      {
        "ms": 177545,
        "duration": 2415
      },
      {
        "ms": 177796,
        "duration": 2670
      },
      {
        "ms": 177808,
        "duration": 2693
      },
      {
        "ms": 177846,
        "duration": 2740
      },
      {
        "ms": 178046,
        "duration": 2925
      },
      {
        "ms": 178059,
        "duration": 2972
      },
      {
        "ms": 178300,
        "duration": 3204
      },
      {
        "ms": 178598,
        "duration": 3483
      },
      {
        "ms": 178818,
        "duration": 3738
      },
      {
        "ms": 179056,
        "duration": 4017
      },
      {
        "ms": 179105,
        "duration": 4040
      },
      {
        "ms": 179323,
        "duration": 4249
      },
      {
        "ms": 179357,
        "duration": 4342
      },
      {
        "ms": 179566,
        "duration": 4528
      },
      {
        "ms": 179615,
        "duration": 4574
      },
      {
        "ms": 179814,
        "duration": 4783
      },
      {
        "ms": 179822,
        "duration": 4806
      },
      {
        "ms": 179855,
        "duration": 4853
      },
      {
        "ms": 180064,
        "duration": 5062
      },
      {
        "ms": 180074,
        "duration": 5085
      },
      {
        "ms": 180317,
        "duration": 5340
      },
      {
        "ms": 180417,
        "duration": 5364
      },
      {
        "ms": 180560,
        "duration": 5573
      },
      {
        "ms": 180578,
        "duration": 5619
      },
      {
        "ms": 180817,
        "duration": 5851
      },
      {
        "ms": 180860,
        "duration": 5898
      },
      {
        "ms": 181058,
        "duration": 6083
      },
      {
        "ms": 181082,
        "duration": 6130
      },
      {
        "ms": 181107,
        "duration": 6153
      },
      {
        "ms": 181311,
        "duration": 6362
      },
      {
        "ms": 181331,
        "duration": 6408
      },
      {
        "ms": 181602,
        "duration": 6641
      },
      {
        "ms": 181630,
        "duration": 6687
      },
      {
        "ms": 181816,
        "duration": 6896
      },
      {
        "ms": 181833,
        "duration": 6919
      },
      {
        "ms": 182065,
        "duration": 7175
      },
      {
        "ms": 182106,
        "duration": 7221
      },
      {
        "ms": 182310,
        "duration": 7407
      },
      {
        "ms": 182334,
        "duration": 7453
      },
      {
        "ms": 182355,
        "duration": 7500
      },
      {
        "ms": 182561,
        "duration": 7686
      },
      {
        "ms": 182606,
        "duration": 7732
      },
      {
        "ms": 182862,
        "duration": 7964
      },
      {
        "ms": 182870,
        "duration": 8011
      },
      {
        "ms": 183061,
        "duration": 8220
      },
      {
        "ms": 183085,
        "duration": 8243
      },
      {
        "ms": 183314,
        "duration": 8498
      },
      {
        "ms": 183357,
        "duration": 8522
      },
      {
        "ms": 183580,
        "duration": 8777
      },
      {
        "ms": 183815,
        "duration": 9009
      },
      {
        "ms": 183861,
        "duration": 9032
      },
      {
        "ms": 184089,
        "duration": 9288
      },
      {
        "ms": 184311,
        "duration": 9520
      },
      {
        "ms": 184336,
        "duration": 9566
      },
      {
        "ms": 184557,
        "duration": 9822
      },
      {
        "ms": 184588,
        "duration": 9845
      },
      {
        "ms": 184812,
        "duration": 10054
      },
      {
        "ms": 184837,
        "duration": 10100
      },
      {
        "ms": 185060,
        "duration": 10286
      },
      {
        "ms": 185088,
        "duration": 10333
      },
      {
        "ms": 185105,
        "duration": 10379
      },
      {
        "ms": 185320,
        "duration": 10542
      },
      {
        "ms": 185344,
        "duration": 10611
      },
      {
        "ms": 185568,
        "duration": 10820
      },
      {
        "ms": 185588,
        "duration": 10843
      },
      {
        "ms": 185818,
        "duration": 11052
      },
      {
        "ms": 185839,
        "duration": 11099
      },
      {
        "ms": 186062,
        "duration": 11331
      },
      {
        "ms": 186107,
        "duration": 11378
      },
      {
        "ms": 186311,
        "duration": 11563
      },
      {
        "ms": 186339,
        "duration": 11610
      },
      {
        "ms": 186558,
        "duration": 11819
      },
      {
        "ms": 186592,
        "duration": 11842
      },
      {
        "ms": 186812,
        "duration": 12051
      },
      {
        "ms": 186841,
        "duration": 12097
      },
      {
        "ms": 186859,
        "duration": 12121
      },
      {
        "ms": 187118,
        "duration": 12376
      },
      {
        "ms": 187310,
        "duration": 12562
      },
      {
        "ms": 187341,
        "duration": 12608
      },
      {
        "ms": 187562,
        "duration": 12817
      },
      {
        "ms": 187593,
        "duration": 12840
      },
      {
        "ms": 187811,
        "duration": 13049
      },
      {
        "ms": 187847,
        "duration": 13096
      },
      {
        "ms": 187857,
        "duration": 13142
      },
      {
        "ms": 187865,
        "duration": 0
      }
    ]
  },
  {
    "ms": 187938,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-live-step2000-2

- 执行 new {'case': 'live', 'step': '2000'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-live-step2000-2 自动检查点

- 命令 `new {'case': 'live', 'step': '2000'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-live-step2000-2.json` 及同前缀文件。
```json
[
  {
    "ms": 191407,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "live",
      "step": "2000"
    }
  },
  {
    "ms": 191477,
    "kind": "PREVIEW_THUMB",
    "engine": 813098265,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 193345,
    "kind": "CHECK",
    "id": "A7.live",
    "pass": true,
    "detail": "seek events before=7 after=7"
  },
  {
    "ms": 204413,
    "kind": "LIVE_DURATION",
    "step": 2000,
    "samples": [
      {
        "ms": 191519,
        "duration": 0
      },
      {
        "ms": 193327,
        "duration": 1648
      },
      {
        "ms": 195316,
        "duration": 3761
      },
      {
        "ms": 197320,
        "duration": 5851
      },
      {
        "ms": 199314,
        "duration": 7964
      },
      {
        "ms": 201304,
        "duration": 10054
      },
      {
        "ms": 203360,
        "duration": 12121
      },
      {
        "ms": 204373,
        "duration": 0
      }
    ]
  },
  {
    "ms": 204424,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-lazy

- 执行 new {'case': 'lazy'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-lazy 自动检查点

- 命令 `new {'case': 'lazy'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-lazy.json` 及同前缀文件。
```json
[
  {
    "ms": 211289,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "lazy"
    }
  },
  {
    "ms": 211331,
    "kind": "CHECK",
    "id": "A3.lazyBefore",
    "pass": true,
    "detail": "controllers=0"
  },
  {
    "ms": 211382,
    "kind": "PREVIEW_THUMB",
    "engine": 356332348,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 211774,
    "kind": "CHECK",
    "id": "A3.lazyOpened",
    "pass": true,
    "detail": "controllers=0 size=0x0"
  },
  {
    "ms": 212509,
    "kind": "CHECK",
    "id": "A3.lazyRead",
    "pass": true,
    "detail": "controllers=1 handle=VideoController size=640x360"
  },
  {
    "ms": 213045,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-lifecycle

- 执行 new {'case': 'lifecycle'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-lifecycle 自动检查点

- 命令 `new {'case': 'lifecycle'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-lifecycle.json` 及同前缀文件。
```json
[
  {
    "ms": 219020,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "lifecycle"
    }
  },
  {
    "ms": 219352,
    "kind": "PREVIEW_THUMB",
    "engine": 943990159,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 223249,
    "kind": "PREVIEW_THUMB",
    "engine": 943990159,
    "at": null,
    "bytes": null,
    "title": "Coverage ad.mp4"
  },
  {
    "ms": 234551,
    "kind": "LIFECYCLE",
    "events": [
      "MovaPause",
      "MovaDurationChange",
      "MovaBufferChange",
      "MovaSizeChange",
      "MovaPlay",
      "MovaSourceChange",
      "MovaReady",
      "MovaBufferChange",
      "MovaDurationChange",
      "MovaBufferChange",
      "MovaSizeChange",
      "MovaSizeChange",
      "MovaFirstFrame",
      "MovaBufferChange",
      "MovaBufferChange",
      "MovaSeek",
      "MovaSeeked",
      "MovaBufferChange",
      "MovaRateChange",
      "MovaBufferChange",
      "MovaFullScreenChange",
      "MovaFullScreenChange",
      "MovaPause",
      "MovaDurationChange",
      "MovaSizeChange",
      "MovaSizeChange",
      "MovaPlay",
      "MovaSourceChange",
      "MovaReady",
      "MovaBufferChange",
      "MovaRateChange",
      "MovaDurationChange",
      "MovaBufferChange",
      "MovaSizeChange",
      "MovaSizeChange",
      "MovaFirstFrame",
      "MovaPause",
      "MovaBufferChange",
      "MovaDone",
      "MovaBufferChange"
    ],
    "errors": []
  },
  {
    "ms": 234551,
    "kind": "CHECK",
    "id": "F1",
    "pass": true,
    "detail": "natural done=1 errors=0"
  },
  {
    "ms": 234783,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-feed

- 执行 new {'case': 'feed'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-feed 自动检查点

- 命令 `new {'case': 'feed'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-feed.json` 及同前缀文件。
```json
[
  {
    "ms": 240346,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "feed"
    }
  },
  {
    "ms": 242043,
    "kind": "FEED_SAMPLE",
    "index": 20,
    "engines": 3,
    "rss": 185782272
  },
  {
    "ms": 242566,
    "kind": "FEED_SAMPLE",
    "index": 40,
    "engines": 3,
    "rss": 177545216
  },
  {
    "ms": 243071,
    "kind": "FEED_SAMPLE",
    "index": 60,
    "engines": 3,
    "rss": 177819648
  },
  {
    "ms": 243475,
    "kind": "FEED_SAMPLE",
    "index": 80,
    "engines": 3,
    "rss": 176373760
  },
  {
    "ms": 244053,
    "kind": "FEED_SAMPLE",
    "index": 100,
    "engines": 3,
    "rss": 186179584
  },
  {
    "ms": 244071,
    "kind": "CHECK",
    "id": "A29.final",
    "pass": true,
    "detail": "active=120 engines=3"
  },
  {
    "ms": 244071,
    "kind": "FEED_ENGINES",
    "states": [
      {
        "playing": false,
        "intent": false,
        "buffering": true,
        "duration": 0,
        "position": 19982,
        "size": "0x0",
        "volume": 30.0,
        "brightness": 1.0,
        "rate": 1.0,
        "fit": "contain",
        "zoom": 1.0,
        "locked": false,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": false,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4?feed=99",
        "pipSupported": true,
        "controls": true,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 0,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      },
      {
        "playing": true,
        "intent": true,
        "buffering": false,
        "duration": 0,
        "position": 19982,
        "size": "0x0",
        "volume": 30.0,
        "brightness": 1.0,
        "rate": 1.0,
        "fit": "contain",
        "zoom": 1.0,
        "locked": false,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": false,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4?feed=120",
        "pipSupported": true,
        "controls": true,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 0,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      },
      {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 19982,
        "size": "0x0",
        "volume": 30.0,
        "brightness": 1.0,
        "rate": 1.0,
        "fit": "contain",
        "zoom": 1.0,
        "locked": false,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": true,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4?feed=98",
        "pipSupported": true,
        "controls": true,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 40000,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      }
    ]
  },
  {
    "ms": 244131,
    "kind": "CHECK",
    "id": "A29.dispose",
    "pass": true,
    "detail": "controller and 3 native engines disposed"
  },
  {
    "ms": 244131,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-cutover

- 执行 new {'case': 'cutover'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-cutover 自动检查点

- 命令 `new {'case': 'cutover'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-cutover.json` 及同前缀文件。
```json
[
  {
    "ms": 248061,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "cutover"
    }
  },
  {
    "ms": 248150,
    "kind": "PREVIEW_THUMB",
    "engine": 805244138,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 248294,
    "kind": "PREVIEW_THUMB",
    "engine": 805244138,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 248382,
    "kind": "CHECK",
    "id": "C11.off",
    "pass": true,
    "detail": "engines=1 epoch=0"
  },
  {
    "ms": 248402,
    "kind": "PREVIEW_THUMB",
    "engine": 762969307,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 249638,
    "kind": "CHECK",
    "id": "A24.commit",
    "pass": true,
    "detail": "epoch=1 rate=1.5 position=6048"
  },
  {
    "ms": 249639,
    "kind": "CHECK",
    "id": "A24.retired",
    "pass": true,
    "detail": "retired engine rejects open"
  },
  {
    "ms": 249639,
    "kind": "CHECK",
    "id": "A24.short",
    "pass": true,
    "detail": "short warm declined engines=2"
  },
  {
    "ms": 249715,
    "kind": "CHECK",
    "id": "A24.abandon",
    "pass": true,
    "detail": "shadow disposed"
  },
  {
    "ms": 251785,
    "kind": "CHECK",
    "id": "A24.timeout",
    "pass": true,
    "detail": "commit timeout returned=false"
  },
  {
    "ms": 252775,
    "kind": "CHECK",
    "id": "A24.cutoverTo",
    "pass": true,
    "detail": "epoch=2 rate=1.0"
  },
  {
    "ms": 252807,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-ads

- 执行 new {'case': 'ads'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-ads 自动检查点

- 命令 `new {'case': 'ads'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-ads.json` 及同前缀文件。
```json
[
  {
    "ms": 256597,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "ads"
    }
  },
  {
    "ms": 256598,
    "kind": "CHECK",
    "id": "C9.waits",
    "pass": true,
    "detail": "pre=false mid=true post=false breakOverride=false"
  },
  {
    "ms": 256636,
    "kind": "pre",
    "type": "started",
    "title": "PRE",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 256693,
    "kind": "PREVIEW_THUMB",
    "engine": 285312042,
    "at": null,
    "bytes": null,
    "title": "PRE"
  },
  {
    "ms": 256742,
    "kind": "pre",
    "type": "clicked",
    "title": "PRE",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 256742,
    "kind": "pre",
    "type": "skipped",
    "title": "PRE",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 256743,
    "kind": "PREVIEW_THUMB",
    "engine": 285312042,
    "at": null,
    "bytes": null,
    "title": "Coverage ad.mp4"
  },
  {
    "ms": 257731,
    "kind": "mid",
    "type": "started",
    "title": "MANUAL",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 257732,
    "kind": "PREVIEW_THUMB",
    "engine": 285312042,
    "at": null,
    "bytes": null,
    "title": "MANUAL"
  },
  {
    "ms": 257781,
    "kind": "mid",
    "type": "skipped",
    "title": "MANUAL",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 257782,
    "kind": "PREVIEW_THUMB",
    "engine": 285312042,
    "at": null,
    "bytes": null,
    "title": "Coverage ad.mp4"
  },
  {
    "ms": 260377,
    "kind": "mid",
    "type": "started",
    "title": "MID",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 260377,
    "kind": "PREVIEW_THUMB",
    "engine": 285312042,
    "at": null,
    "bytes": null,
    "title": "MID"
  },
  {
    "ms": 261571,
    "kind": "mid",
    "type": "completed",
    "title": "MID",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 261572,
    "kind": "PREVIEW_THUMB",
    "engine": 285312042,
    "at": null,
    "bytes": null,
    "title": "Coverage ad.mp4"
  },
  {
    "ms": 278249,
    "kind": "post",
    "type": "started",
    "title": "POST",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 278250,
    "kind": "PREVIEW_THUMB",
    "engine": 285312042,
    "at": null,
    "bytes": null,
    "title": "POST"
  },
  {
    "ms": 279368,
    "kind": "post",
    "type": "completed",
    "title": "POST",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 279371,
    "kind": "CHECK",
    "id": "A27.rolls",
    "pass": true,
    "detail": "events=[PRE:started, PRE:clicked, PRE:skipped, MANUAL:started, MANUAL:skipped, MID:started, MID:completed, POST:started, POST:completed]"
  },
  {
    "ms": 279385,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-adResume

- 执行 new {'case': 'adResume'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-adResume 自动检查点

- 命令 `new {'case': 'adResume'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-adResume.json` 及同前缀文件。
```json
[
  {
    "ms": 283195,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "adResume"
    }
  },
  {
    "ms": 283542,
    "kind": "PREVIEW_THUMB",
    "engine": 448484005,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 292695,
    "kind": "CHECK",
    "id": "F4.adResume",
    "pass": true,
    "detail": "run=0 target=5240 nativeAfter=5240 error=0 nativeReadLatency=5 epoch=2"
  },
  {
    "ms": 293361,
    "kind": "PREVIEW_THUMB",
    "engine": 832592713,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 302359,
    "kind": "CHECK",
    "id": "F4.adResume",
    "pass": true,
    "detail": "run=1 target=4840 nativeAfter=4840 error=0 nativeReadLatency=5 epoch=2"
  },
  {
    "ms": 302914,
    "kind": "PREVIEW_THUMB",
    "engine": 994313695,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 312332,
    "kind": "CHECK",
    "id": "F4.adResume",
    "pass": true,
    "detail": "run=2 target=5040 nativeAfter=5040 error=0 nativeReadLatency=22 epoch=2"
  },
  {
    "ms": 312958,
    "kind": "PREVIEW_THUMB",
    "engine": 137468596,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 322161,
    "kind": "CHECK",
    "id": "F4.adResume",
    "pass": true,
    "detail": "run=3 target=5040 nativeAfter=5040 error=0 nativeReadLatency=1 epoch=2"
  },
  {
    "ms": 322774,
    "kind": "PREVIEW_THUMB",
    "engine": 757993282,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 332150,
    "kind": "CHECK",
    "id": "F4.adResume",
    "pass": true,
    "detail": "run=4 target=4800 nativeAfter=4800 error=0 nativeReadLatency=4 epoch=2"
  },
  {
    "ms": 332452,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-dispose120

- 执行 dispose {}；以真实事件和原生读回检查对应子项。

## rerun-batch15-dispose120 自动检查点

- 命令 `dispose {}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-dispose120.json` 及同前缀文件。
```json
[
  {
    "ms": 337078,
    "kind": "BEGIN",
    "group": "dispose",
    "args": {
      "group": "dispose"
    }
  },
  {
    "ms": 338753,
    "kind": "MEM_SAMPLE",
    "round": 20,
    "rss": 197332992
  },
  {
    "ms": 340274,
    "kind": "MEM_SAMPLE",
    "round": 40,
    "rss": 206086144
  },
  {
    "ms": 341815,
    "kind": "MEM_SAMPLE",
    "round": 60,
    "rss": 215646208
  },
  {
    "ms": 343433,
    "kind": "MEM_SAMPLE",
    "round": 80,
    "rss": 219086848
  },
  {
    "ms": 344770,
    "kind": "MEM_SAMPLE",
    "round": 100,
    "rss": 221073408
  },
  {
    "ms": 346228,
    "kind": "MEM_SAMPLE",
    "round": 120,
    "rss": 222294016
  },
  {
    "ms": 346228,
    "kind": "CHECK",
    "id": "A23.120",
    "pass": true,
    "detail": "120 native create/open/dispose completed"
  },
  {
    "ms": 346228,
    "kind": "END",
    "group": "dispose",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-preview-vtt

- 执行 new {'case': 'preview', 'mode': 'vtt'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-preview-vtt 自动检查点

- 命令 `new {'case': 'preview', 'mode': 'vtt'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-preview-vtt.json` 及同前缀文件。
```json
[
  {
    "ms": 351622,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "preview",
      "mode": "vtt"
    }
  },
  {
    "ms": 351727,
    "kind": "PREVIEW_THUMB",
    "engine": 29813514,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 354450,
    "kind": "PREVIEW_THUMB",
    "engine": 29813514,
    "at": 4000,
    "bytes": 8001,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 354469,
    "kind": "THUMB",
    "requested": 4,
    "at": 4000,
    "bytes": 8001,
    "crop": "MovaThumbCrop(0,0,160,90)",
    "peek": false
  },
  {
    "ms": 354475,
    "kind": "PREVIEW_THUMB",
    "engine": 29813514,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 354600,
    "kind": "PREVIEW_THUMB",
    "engine": 29813514,
    "at": 8000,
    "bytes": 8001,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 354640,
    "kind": "THUMB",
    "requested": 8,
    "at": 8000,
    "bytes": 8001,
    "crop": "MovaThumbCrop(0,0,160,90)",
    "peek": false
  },
  {
    "ms": 354649,
    "kind": "PREVIEW_THUMB",
    "engine": 29813514,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 354773,
    "kind": "PREVIEW_THUMB",
    "engine": 29813514,
    "at": 12000,
    "bytes": 8001,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 354778,
    "kind": "THUMB",
    "requested": 12,
    "at": 12000,
    "bytes": 8001,
    "crop": "MovaThumbCrop(0,0,160,90)",
    "peek": false
  },
  {
    "ms": 354785,
    "kind": "PREVIEW_THUMB",
    "engine": 29813514,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 354908,
    "kind": "PREVIEW_THUMB",
    "engine": 29813514,
    "at": 4000,
    "bytes": 8001,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 354911,
    "kind": "THUMB",
    "requested": 4,
    "at": 4000,
    "bytes": 8001,
    "crop": "MovaThumbCrop(0,0,160,90)",
    "peek": false
  },
  {
    "ms": 354915,
    "kind": "PREVIEW_END",
    "mode": "vtt",
    "thumbs": 7,
    "current": "null",
    "extractCalls": 0,
    "writes": 0,
    "diskHits": 0,
    "memoryHits": 0
  },
  {
    "ms": 354915,
    "kind": "CHECK",
    "id": "N22.crop",
    "pass": true,
    "detail": "cropped VTT writes=0"
  },
  {
    "ms": 354915,
    "kind": "PREVIEW_THUMB",
    "engine": 29813514,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 354919,
    "kind": "PREVIEW_THUMB",
    "engine": 29813514,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 355067,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-preview-extract

- 执行 new {'case': 'preview', 'mode': 'extract'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-preview-extract 自动检查点

- 命令 `new {'case': 'preview', 'mode': 'extract'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-preview-extract.json` 及同前缀文件。
```json
[
  {
    "ms": 360950,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "preview",
      "mode": "extract"
    }
  },
  {
    "ms": 361070,
    "kind": "PREVIEW_THUMB",
    "engine": 355190718,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 362170,
    "kind": "PREVIEW_THUMB",
    "engine": 355190718,
    "at": 4000,
    "bytes": 99796,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 362174,
    "kind": "THUMB",
    "requested": 4,
    "at": 4000,
    "bytes": 99796,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 362182,
    "kind": "PREVIEW_THUMB",
    "engine": 355190718,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 363001,
    "kind": "PREVIEW_THUMB",
    "engine": 355190718,
    "at": 8000,
    "bytes": 98103,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 363033,
    "kind": "THUMB",
    "requested": 8,
    "at": 8000,
    "bytes": 98103,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 363041,
    "kind": "PREVIEW_THUMB",
    "engine": 355190718,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 363868,
    "kind": "PREVIEW_THUMB",
    "engine": 355190718,
    "at": 12000,
    "bytes": 95382,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 363898,
    "kind": "THUMB",
    "requested": 12,
    "at": 12000,
    "bytes": 95382,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 363904,
    "kind": "PREVIEW_THUMB",
    "engine": 355190718,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 364031,
    "kind": "PREVIEW_THUMB",
    "engine": 355190718,
    "at": 4000,
    "bytes": 99796,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 364074,
    "kind": "THUMB",
    "requested": 4,
    "at": 4000,
    "bytes": 99796,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 364085,
    "kind": "PREVIEW_END",
    "mode": "extract",
    "thumbs": 7,
    "current": "null",
    "extractCalls": 3,
    "writes": 3,
    "diskHits": 1,
    "memoryHits": 4
  },
  {
    "ms": 364085,
    "kind": "CHECK",
    "id": "A30.diskHit",
    "pass": true,
    "detail": "extractCalls=3 diskHits=1"
  },
  {
    "ms": 364086,
    "kind": "PREVIEW_THUMB",
    "engine": 355190718,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 364100,
    "kind": "PREVIEW_THUMB",
    "engine": 355190718,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 364162,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-preview-fallback

- 执行 new {'case': 'preview', 'mode': 'fallback'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-preview-fallback 自动检查点

- 命令 `new {'case': 'preview', 'mode': 'fallback'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-preview-fallback.json` 及同前缀文件。
```json
[
  {
    "ms": 369141,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "preview",
      "mode": "fallback"
    }
  },
  {
    "ms": 369250,
    "kind": "PREVIEW_THUMB",
    "engine": 338532246,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 374918,
    "kind": "PREVIEW_THUMB",
    "engine": 338532246,
    "at": 4000,
    "bytes": 86894,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 374933,
    "kind": "THUMB",
    "requested": 4,
    "at": 4000,
    "bytes": 86894,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 374937,
    "kind": "PREVIEW_THUMB",
    "engine": 338532246,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 375683,
    "kind": "PREVIEW_THUMB",
    "engine": 338532246,
    "at": 8000,
    "bytes": 98103,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 375698,
    "kind": "THUMB",
    "requested": 8,
    "at": 8000,
    "bytes": 98103,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 375709,
    "kind": "PREVIEW_THUMB",
    "engine": 338532246,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 376592,
    "kind": "PREVIEW_THUMB",
    "engine": 338532246,
    "at": 12000,
    "bytes": 95382,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 376618,
    "kind": "THUMB",
    "requested": 12,
    "at": 12000,
    "bytes": 95382,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 376623,
    "kind": "PREVIEW_THUMB",
    "engine": 338532246,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 376751,
    "kind": "PREVIEW_THUMB",
    "engine": 338532246,
    "at": 4000,
    "bytes": 86894,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 376779,
    "kind": "THUMB",
    "requested": 4,
    "at": 4000,
    "bytes": 86894,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 376783,
    "kind": "PREVIEW_END",
    "mode": "fallback",
    "thumbs": 7,
    "current": "null",
    "extractCalls": 3,
    "writes": 3,
    "diskHits": 1,
    "memoryHits": 4
  },
  {
    "ms": 376783,
    "kind": "CHECK",
    "id": "A30.diskHit",
    "pass": true,
    "detail": "extractCalls=3 diskHits=1"
  },
  {
    "ms": 376783,
    "kind": "PREVIEW_THUMB",
    "engine": 338532246,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 376792,
    "kind": "PREVIEW_THUMB",
    "engine": 338532246,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 376885,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-preview-blocked

- 执行 new {'case': 'preview', 'mode': 'blocked'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-preview-blocked 自动检查点

- 命令 `new {'case': 'preview', 'mode': 'blocked'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-preview-blocked.json` 及同前缀文件。
```json
[
  {
    "ms": 380788,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "preview",
      "mode": "blocked"
    }
  },
  {
    "ms": 380901,
    "kind": "PREVIEW_THUMB",
    "engine": 820238060,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 383001,
    "kind": "PREVIEW_END",
    "mode": "blocked",
    "thumbs": 0,
    "current": "null",
    "extractCalls": 0,
    "writes": 0,
    "diskHits": 0,
    "memoryHits": 0
  },
  {
    "ms": 383006,
    "kind": "PREVIEW_THUMB",
    "engine": 820238060,
    "at": null,
    "bytes": null,
    "title": "Coverage vod.mp4"
  },
  {
    "ms": 383015,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-qoe-ended

- 执行 new {'case': 'qoe', 'mode': 'ended'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-qoe-ended 自动检查点

- 命令 `new {'case': 'qoe', 'mode': 'ended'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-qoe-ended.json` 及同前缀文件。
```json
[
  {
    "ms": 391016,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "qoe",
      "mode": "ended"
    }
  },
  {
    "ms": 391119,
    "kind": "PREVIEW_THUMB",
    "engine": 824880966,
    "at": null,
    "bytes": null,
    "title": "Coverage ad.mp4"
  },
  {
    "ms": 391158,
    "kind": "REPORT",
    "name": "sessionStart",
    "params": {
      "uri": "http://127.0.0.1:18080/ad.mp4?t=1793093360991914",
      "streamType": "vod",
      "audioOnly": true,
      "swapEnabled": false,
      "title": "Coverage ad.mp4"
    }
  },
  {
    "ms": 391164,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 391188,
    "kind": "REPORT",
    "name": "play",
    "params": {}
  },
  {
    "ms": 391188,
    "kind": "REPORT",
    "name": "sourceChange",
    "params": {
      "uri": "http://127.0.0.1:18080/ad.mp4?t=1793093360991914"
    }
  },
  {
    "ms": 391340,
    "kind": "REPORT",
    "name": "firstFrame",
    "params": {
      "ttffMs": 224,
      "audioOnly": true,
      "streamType": "vod",
      "signal": "restart"
    }
  },
  {
    "ms": 410818,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 410819,
    "kind": "REPORT",
    "name": "done",
    "params": {}
  },
  {
    "ms": 410853,
    "kind": "REPORT",
    "name": "sessionEnd",
    "params": {
      "reason": "ended",
      "watchedMs": 19477,
      "stallCount": 0,
      "stallMs": 0,
      "rebufferRate": 0.0,
      "completionPercent": 96.975
    }
  },
  {
    "ms": 411186,
    "kind": "QOE_END",
    "mode": "ended",
    "reports": 8
  },
  {
    "ms": 411187,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-qoe-stopped

- 执行 new {'case': 'qoe', 'mode': 'stopped'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-qoe-stopped 自动检查点

- 命令 `new {'case': 'qoe', 'mode': 'stopped'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-qoe-stopped.json` 及同前缀文件。
```json
[
  {
    "ms": 415137,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "qoe",
      "mode": "stopped"
    }
  },
  {
    "ms": 415241,
    "kind": "PREVIEW_THUMB",
    "engine": 145271063,
    "at": null,
    "bytes": null,
    "title": "Coverage ad.mp4"
  },
  {
    "ms": 415277,
    "kind": "REPORT",
    "name": "sessionStart",
    "params": {
      "uri": "http://127.0.0.1:18080/ad.mp4?t=1793093385118290",
      "streamType": "vod",
      "audioOnly": true,
      "swapEnabled": false,
      "title": "Coverage ad.mp4"
    }
  },
  {
    "ms": 415279,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 415302,
    "kind": "REPORT",
    "name": "play",
    "params": {}
  },
  {
    "ms": 415302,
    "kind": "REPORT",
    "name": "sourceChange",
    "params": {
      "uri": "http://127.0.0.1:18080/ad.mp4?t=1793093385118290"
    }
  },
  {
    "ms": 415448,
    "kind": "REPORT",
    "name": "firstFrame",
    "params": {
      "ttffMs": 207,
      "audioOnly": true,
      "streamType": "vod",
      "signal": "restart"
    }
  },
  {
    "ms": 419727,
    "kind": "REPORT",
    "name": "sessionEnd",
    "params": {
      "reason": "stopped",
      "watchedMs": 4279,
      "stallCount": 0,
      "stallMs": 0,
      "rebufferRate": 0.0,
      "completionPercent": 20.72
    }
  },
  {
    "ms": 420055,
    "kind": "QOE_END",
    "mode": "stopped",
    "reports": 6
  },
  {
    "ms": 420056,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-qoe-failed

- 执行 new {'case': 'qoe', 'mode': 'failed'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-qoe-failed 自动检查点

- 命令 `new {'case': 'qoe', 'mode': 'failed'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-qoe-failed.json` 及同前缀文件。
```json
[
  {
    "ms": 424281,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "qoe",
      "mode": "failed"
    }
  },
  {
    "ms": 424353,
    "kind": "PREVIEW_THUMB",
    "engine": 979904940,
    "at": null,
    "bytes": null,
    "title": "Coverage 404.mp4"
  },
  {
    "ms": 424389,
    "kind": "REPORT",
    "name": "sessionStart",
    "params": {
      "uri": "http://127.0.0.1:18080/404.mp4?t=1793093394243946",
      "streamType": "vod",
      "audioOnly": true,
      "swapEnabled": false,
      "title": "Coverage 404.mp4"
    }
  },
  {
    "ms": 424391,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 424422,
    "kind": "REPORT",
    "name": "play",
    "params": {}
  },
  {
    "ms": 424422,
    "kind": "REPORT",
    "name": "sourceChange",
    "params": {
      "uri": "http://127.0.0.1:18080/404.mp4?t=1793093394243946"
    }
  },
  {
    "ms": 424434,
    "kind": "REPORT",
    "name": "error",
    "params": {
      "error": "Failed to open http://127.0.0.1:18080/404.mp4?t=1793093394243946.",
      "fatal": true,
      "code": "stream"
    }
  },
  {
    "ms": 424464,
    "kind": "REPORT",
    "name": "startupFail",
    "params": {
      "reason": "failed",
      "waitedMs": 111
    }
  },
  {
    "ms": 424465,
    "kind": "REPORT",
    "name": "sessionEnd",
    "params": {
      "reason": "failed",
      "watchedMs": 0,
      "stallCount": 0,
      "stallMs": 0,
      "rebufferRate": 0.0
    }
  },
  {
    "ms": 424779,
    "kind": "QOE_END",
    "mode": "failed",
    "reports": 7
  },
  {
    "ms": 424779,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-qoe-abandoned

- 执行 new {'case': 'qoe', 'mode': 'abandoned'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-qoe-abandoned 自动检查点

- 命令 `new {'case': 'qoe', 'mode': 'abandoned'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-qoe-abandoned.json` 及同前缀文件。
```json
[
  {
    "ms": 429609,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "qoe",
      "mode": "abandoned"
    }
  },
  {
    "ms": 429702,
    "kind": "PREVIEW_THUMB",
    "engine": 554992176,
    "at": null,
    "bytes": null,
    "title": "Coverage hang"
  },
  {
    "ms": 429704,
    "kind": "REPORT",
    "name": "startupFail",
    "params": {
      "reason": "abandoned",
      "waitedMs": 1
    }
  },
  {
    "ms": 429704,
    "kind": "REPORT",
    "name": "sessionEnd",
    "params": {
      "reason": "abandoned",
      "watchedMs": 0,
      "stallCount": 0,
      "stallMs": 0,
      "rebufferRate": 0.0
    }
  },
  {
    "ms": 429744,
    "kind": "REPORT",
    "name": "sessionStart",
    "params": {
      "uri": "http://127.0.0.1:18080/hang?t=1793093399580347",
      "streamType": "vod",
      "audioOnly": true,
      "swapEnabled": false,
      "title": "Coverage hang"
    }
  },
  {
    "ms": 430081,
    "kind": "QOE_END",
    "mode": "abandoned",
    "reports": 3
  },
  {
    "ms": 430082,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-qoe-stall

- 执行 new {'case': 'qoe', 'mode': 'stall'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-qoe-stall 自动检查点

- 命令 `new {'case': 'qoe', 'mode': 'stall'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-qoe-stall.json` 及同前缀文件。
```json
[
  {
    "ms": 435605,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "qoe",
      "mode": "stall"
    }
  },
  {
    "ms": 435703,
    "kind": "PREVIEW_THUMB",
    "engine": 986106147,
    "at": null,
    "bytes": null,
    "title": "Coverage stall.mp4"
  },
  {
    "ms": 435761,
    "kind": "REPORT",
    "name": "sessionStart",
    "params": {
      "uri": "http://127.0.0.1:18080/stall.mp4?t=1793093405582195",
      "streamType": "vod",
      "audioOnly": true,
      "swapEnabled": false,
      "title": "Coverage stall.mp4"
    }
  },
  {
    "ms": 435763,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 435797,
    "kind": "REPORT",
    "name": "play",
    "params": {}
  },
  {
    "ms": 435798,
    "kind": "REPORT",
    "name": "sourceChange",
    "params": {
      "uri": "http://127.0.0.1:18080/stall.mp4?t=1793093405582195"
    }
  },
  {
    "ms": 435913,
    "kind": "REPORT",
    "name": "firstFrame",
    "params": {
      "ttffMs": 209,
      "audioOnly": true,
      "streamType": "vod",
      "signal": "restart"
    }
  },
  {
    "ms": 460801,
    "kind": "REPORT",
    "name": "sessionEnd",
    "params": {
      "reason": "stopped",
      "watchedMs": 2727,
      "stallCount": 0,
      "stallMs": 22160,
      "rebufferRate": 0.890424719733194,
      "completionPercent": 7.545
    }
  },
  {
    "ms": 461201,
    "kind": "QOE_END",
    "mode": "stall",
    "reports": 6
  },
  {
    "ms": 461201,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-qoe-truncated

- 执行 new {'case': 'qoe', 'mode': 'truncated'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-qoe-truncated 自动检查点

- 命令 `new {'case': 'qoe', 'mode': 'truncated'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-qoe-truncated.json` 及同前缀文件。
```json
[
  {
    "ms": 465000,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "qoe",
      "mode": "truncated"
    }
  },
  {
    "ms": 465094,
    "kind": "PREVIEW_THUMB",
    "engine": 978559549,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 465135,
    "kind": "REPORT",
    "name": "sessionStart",
    "params": {
      "uri": "http://127.0.0.1:18084/truncated.mp4?t=1793093434968890",
      "streamType": "vod",
      "audioOnly": true,
      "swapEnabled": false
    }
  },
  {
    "ms": 465137,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 465161,
    "kind": "REPORT",
    "name": "play",
    "params": {}
  },
  {
    "ms": 465161,
    "kind": "REPORT",
    "name": "sourceChange",
    "params": {
      "uri": "http://127.0.0.1:18084/truncated.mp4?t=1793093434968890"
    }
  },
  {
    "ms": 465412,
    "kind": "REPORT",
    "name": "firstFrame",
    "params": {
      "ttffMs": 318,
      "audioOnly": true,
      "streamType": "vod",
      "signal": "restart"
    }
  },
  {
    "ms": 484147,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 484148,
    "kind": "REPORT",
    "name": "done",
    "params": {}
  },
  {
    "ms": 484185,
    "kind": "REPORT",
    "name": "error",
    "params": {
      "error": "truncated: EOF at 18644/40000 ms",
      "fatal": true,
      "code": "truncated"
    }
  },
  {
    "ms": 484186,
    "kind": "REPORT",
    "name": "sessionEnd",
    "params": {
      "reason": "failed",
      "watchedMs": 18734,
      "stallCount": 0,
      "stallMs": 0,
      "rebufferRate": 0.0,
      "completionPercent": 46.61
    }
  },
  {
    "ms": 484514,
    "kind": "QOE_END",
    "mode": "truncated",
    "reports": 9
  },
  {
    "ms": 484514,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-hls

- 执行 new {'case': 'hls'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-hls 自动检查点

- 命令 `new {'case': 'hls'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-hls.json` 及同前缀文件。
```json
[
  {
    "ms": 487428,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hls"
    }
  },
  {
    "ms": 487867,
    "kind": "PREVIEW_THUMB",
    "engine": 915145668,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 497297,
    "kind": "HLS_QUALITIES",
    "qualities": [
      {
        "label": "自动",
        "uri": ""
      },
      {
        "label": "360p",
        "uri": "http://127.0.0.1:18084/high/index.m3u8"
      },
      {
        "label": "180p",
        "uri": "http://127.0.0.1:18084/low/index.m3u8"
      }
    ]
  },
  {
    "ms": 498008,
    "kind": "HLS_RESTART",
    "run": 0,
    "position": 23,
    "target": 8103,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 498097,
    "kind": "HLS_RESTART",
    "run": 0,
    "position": 8103,
    "target": 8103,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 498831,
    "kind": "HLS_NATIVE",
    "run": 0,
    "target": 8103,
    "landed": 8103,
    "continued": 8743,
    "samples": [
      23,
      8103
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 8703,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 498831,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=0 target=8103 landed=8103 error=0 continued=8743"
  },
  {
    "ms": 500005,
    "kind": "HLS_RESTART",
    "run": 1,
    "position": 23,
    "target": 8743,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 500168,
    "kind": "HLS_RESTART",
    "run": 1,
    "position": 8743,
    "target": 8743,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 500874,
    "kind": "HLS_NATIVE",
    "run": 1,
    "target": 8743,
    "landed": 8743,
    "continued": 9383,
    "samples": [
      23,
      8743
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 9183,
      "size": "320x180",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 500874,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=1 target=8743 landed=8743 error=0 continued=9383"
  },
  {
    "ms": 502004,
    "kind": "HLS_RESTART",
    "run": 2,
    "position": 23,
    "target": 9383,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 502248,
    "kind": "HLS_RESTART",
    "run": 2,
    "position": 9383,
    "target": 9383,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 502965,
    "kind": "HLS_NATIVE",
    "run": 2,
    "target": 9383,
    "landed": 9383,
    "continued": 10063,
    "samples": [
      23,
      9383
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 10023,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 502965,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=2 target=9383 landed=9383 error=0 continued=10063"
  },
  {
    "ms": 504082,
    "kind": "HLS_RESTART",
    "run": 3,
    "position": 23,
    "target": 10063,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 504165,
    "kind": "HLS_RESTART",
    "run": 3,
    "position": 10063,
    "target": 10063,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 504869,
    "kind": "HLS_NATIVE",
    "run": 3,
    "target": 10063,
    "landed": 10063,
    "continued": 10743,
    "samples": [
      23,
      10063
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 10663,
      "size": "320x180",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 504869,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=3 target=10063 landed=10063 error=0 continued=10743"
  },
  {
    "ms": 505941,
    "kind": "HLS_RESTART",
    "run": 4,
    "position": 23,
    "target": 10743,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 506091,
    "kind": "HLS_RESTART",
    "run": 4,
    "position": 10743,
    "target": 10743,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 506813,
    "kind": "HLS_NATIVE",
    "run": 4,
    "target": 10743,
    "landed": 10743,
    "continued": 11423,
    "samples": [
      23,
      10743
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 11343,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 506814,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=4 target=10743 landed=10743 error=0 continued=11423"
  },
  {
    "ms": 510817,
    "kind": "HLS_END",
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 15343,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "downshifts": 0
  },
  {
    "ms": 511122,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-abr

- 执行 new {'case': 'abr'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-abr 自动检查点

- 命令 `new {'case': 'abr'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-abr.json` 及同前缀文件。
```json
[
  {
    "ms": 514621,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "abr"
    }
  },
  {
    "ms": 514915,
    "kind": "PREVIEW_THUMB",
    "engine": 216200820,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 523464,
    "kind": "ABR_REAL",
    "before": 5223,
    "from": "360p",
    "to": "180p",
    "resets": 3,
    "state": {
      "playing": true,
      "intent": true,
      "buffering": true,
      "duration": 0,
      "position": 5703,
      "size": "0x0",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 0,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 524373,
    "kind": "CHECK",
    "id": "F3.abrBackToBack",
    "pass": true,
    "detail": "beforeStall=5223 afterSwitch=5743"
  },
  {
    "ms": 524556,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-batch15-tls

- 执行 new {'case': 'tls'}；以真实事件和原生读回检查对应子项。

## rerun-batch15-tls 自动检查点

- 命令 `new {'case': 'tls'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/rerun-batch15-tls.json` 及同前缀文件。
```json
[
  {
    "ms": 527927,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "tls"
    }
  },
  {
    "ms": 528047,
    "kind": "PREVIEW_THUMB",
    "engine": 813662117,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 528666,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=0 verify=false cert=0 rendered=true errors=[]"
  },
  {
    "ms": 528698,
    "kind": "PREVIEW_THUMB",
    "engine": 895311553,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 529208,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=0 verify=false cert=1 rendered=true errors=[]"
  },
  {
    "ms": 529288,
    "kind": "PREVIEW_THUMB",
    "engine": 975868354,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 529789,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=0 verify=false cert=2 rendered=true errors=[]"
  },
  {
    "ms": 529857,
    "kind": "PREVIEW_THUMB",
    "engine": 825100223,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 530352,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=0 verify=false cert=3 rendered=true errors=[]"
  },
  {
    "ms": 530383,
    "kind": "PREVIEW_THUMB",
    "engine": 729194666,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 530587,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": false,
    "detail": "run=0 verify=true cert=0 rendered=false errors=[Failed to open https://127.0.0.1:18443/low/index.m3u8?t=0.]"
  },
  {
    "ms": 530610,
    "kind": "PREVIEW_THUMB",
    "engine": 177384795,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 530745,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=0 verify=true cert=1 rendered=false errors=[Failed to open https://127.0.0.1:18444/low/index.m3u8?t=0.]"
  },
  {
    "ms": 530793,
    "kind": "PREVIEW_THUMB",
    "engine": 787018244,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 530961,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=0 verify=true cert=2 rendered=false errors=[Failed to open https://127.0.0.1:18445/low/index.m3u8?t=0.]"
  },
  {
    "ms": 531032,
    "kind": "PREVIEW_THUMB",
    "engine": 150809037,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 531155,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=0 verify=true cert=3 rendered=false errors=[Failed to open https://127.0.0.1:18446/low/index.m3u8?t=0.]"
  },
  {
    "ms": 531273,
    "kind": "PREVIEW_THUMB",
    "engine": 996995537,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 531770,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=1 verify=false cert=0 rendered=true errors=[]"
  },
  {
    "ms": 531811,
    "kind": "PREVIEW_THUMB",
    "engine": 374728603,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 532430,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=1 verify=false cert=1 rendered=true errors=[]"
  },
  {
    "ms": 532577,
    "kind": "PREVIEW_THUMB",
    "engine": 980627285,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 533128,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=1 verify=false cert=2 rendered=true errors=[]"
  },
  {
    "ms": 533238,
    "kind": "PREVIEW_THUMB",
    "engine": 188313957,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 533743,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=1 verify=false cert=3 rendered=true errors=[]"
  },
  {
    "ms": 533760,
    "kind": "PREVIEW_THUMB",
    "engine": 304730950,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 533991,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": false,
    "detail": "run=1 verify=true cert=0 rendered=false errors=[Failed to open https://127.0.0.1:18443/low/index.m3u8?t=1.]"
  },
  {
    "ms": 534033,
    "kind": "PREVIEW_THUMB",
    "engine": 156357078,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 534201,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=1 verify=true cert=1 rendered=false errors=[Failed to open https://127.0.0.1:18444/low/index.m3u8?t=1.]"
  },
  {
    "ms": 534250,
    "kind": "PREVIEW_THUMB",
    "engine": 786953540,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 534371,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=1 verify=true cert=2 rendered=false errors=[Failed to open https://127.0.0.1:18445/low/index.m3u8?t=1.]"
  },
  {
    "ms": 534410,
    "kind": "PREVIEW_THUMB",
    "engine": 769648350,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 534611,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=1 verify=true cert=3 rendered=false errors=[Failed to open https://127.0.0.1:18446/low/index.m3u8?t=1.]"
  },
  {
    "ms": 534649,
    "kind": "PREVIEW_THUMB",
    "engine": 1031347235,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 535174,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=2 verify=false cert=0 rendered=true errors=[]"
  },
  {
    "ms": 535215,
    "kind": "PREVIEW_THUMB",
    "engine": 887620649,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 535802,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=2 verify=false cert=1 rendered=true errors=[]"
  },
  {
    "ms": 535860,
    "kind": "PREVIEW_THUMB",
    "engine": 383165350,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 536437,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=2 verify=false cert=2 rendered=true errors=[]"
  },
  {
    "ms": 536481,
    "kind": "PREVIEW_THUMB",
    "engine": 757789051,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 537079,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=2 verify=false cert=3 rendered=true errors=[]"
  },
  {
    "ms": 537139,
    "kind": "PREVIEW_THUMB",
    "engine": 614050088,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 537275,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": false,
    "detail": "run=2 verify=true cert=0 rendered=false errors=[Failed to open https://127.0.0.1:18443/low/index.m3u8?t=2.]"
  },
  {
    "ms": 537323,
    "kind": "PREVIEW_THUMB",
    "engine": 910313021,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 537445,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=2 verify=true cert=1 rendered=false errors=[Failed to open https://127.0.0.1:18444/low/index.m3u8?t=2.]"
  },
  {
    "ms": 537473,
    "kind": "PREVIEW_THUMB",
    "engine": 394177630,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 537689,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=2 verify=true cert=2 rendered=false errors=[Failed to open https://127.0.0.1:18445/low/index.m3u8?t=2.]"
  },
  {
    "ms": 537724,
    "kind": "PREVIEW_THUMB",
    "engine": 949006384,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 537854,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=2 verify=true cert=3 rendered=false errors=[Failed to open https://127.0.0.1:18446/low/index.m3u8?t=2.]"
  },
  {
    "ms": 537910,
    "kind": "PREVIEW_THUMB",
    "engine": 233397588,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 538420,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=3 verify=false cert=0 rendered=true errors=[]"
  },
  {
    "ms": 538479,
    "kind": "PREVIEW_THUMB",
    "engine": 499521753,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 539015,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=3 verify=false cert=1 rendered=true errors=[]"
  },
  {
    "ms": 539081,
    "kind": "PREVIEW_THUMB",
    "engine": 771428849,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 539638,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=3 verify=false cert=2 rendered=true errors=[]"
  },
  {
    "ms": 539699,
    "kind": "PREVIEW_THUMB",
    "engine": 855602923,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 540298,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=3 verify=false cert=3 rendered=true errors=[]"
  },
  {
    "ms": 540359,
    "kind": "PREVIEW_THUMB",
    "engine": 503397449,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 540497,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": false,
    "detail": "run=3 verify=true cert=0 rendered=false errors=[Failed to open https://127.0.0.1:18443/low/index.m3u8?t=3.]"
  },
  {
    "ms": 540529,
    "kind": "PREVIEW_THUMB",
    "engine": 1066765856,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 540658,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=3 verify=true cert=1 rendered=false errors=[Failed to open https://127.0.0.1:18444/low/index.m3u8?t=3.]"
  },
  {
    "ms": 540710,
    "kind": "PREVIEW_THUMB",
    "engine": 478178193,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 540920,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=3 verify=true cert=2 rendered=false errors=[Failed to open https://127.0.0.1:18445/low/index.m3u8?t=3.]"
  },
  {
    "ms": 540951,
    "kind": "PREVIEW_THUMB",
    "engine": 436574506,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 541109,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=3 verify=true cert=3 rendered=false errors=[Failed to open https://127.0.0.1:18446/low/index.m3u8?t=3.]"
  },
  {
    "ms": 541151,
    "kind": "PREVIEW_THUMB",
    "engine": 707761057,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 541641,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=4 verify=false cert=0 rendered=true errors=[]"
  },
  {
    "ms": 541686,
    "kind": "PREVIEW_THUMB",
    "engine": 1003648510,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 542263,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=4 verify=false cert=1 rendered=true errors=[]"
  },
  {
    "ms": 542359,
    "kind": "PREVIEW_THUMB",
    "engine": 492796793,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 542899,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=4 verify=false cert=2 rendered=true errors=[]"
  },
  {
    "ms": 542942,
    "kind": "PREVIEW_THUMB",
    "engine": 856295574,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 543559,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=4 verify=false cert=3 rendered=true errors=[]"
  },
  {
    "ms": 543653,
    "kind": "PREVIEW_THUMB",
    "engine": 799836349,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 543813,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": false,
    "detail": "run=4 verify=true cert=0 rendered=false errors=[Failed to open https://127.0.0.1:18443/low/index.m3u8?t=4.]"
  },
  {
    "ms": 543871,
    "kind": "PREVIEW_THUMB",
    "engine": 472213397,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 543992,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=4 verify=true cert=1 rendered=false errors=[Failed to open https://127.0.0.1:18444/low/index.m3u8?t=4.]"
  },
  {
    "ms": 544019,
    "kind": "PREVIEW_THUMB",
    "engine": 880446719,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 544190,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=4 verify=true cert=2 rendered=false errors=[Failed to open https://127.0.0.1:18445/low/index.m3u8?t=4.]"
  },
  {
    "ms": 544211,
    "kind": "PREVIEW_THUMB",
    "engine": 781660965,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 544316,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=4 verify=true cert=3 rendered=false errors=[Failed to open https://127.0.0.1:18446/low/index.m3u8?t=4.]"
  },
  {
    "ms": 544323,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 结束 api

- exit=0；驱动输出 `example/tool/coverage_evidence/rerun-plan-api.log`；原始结果均用 rerun- 前缀。异常/超时不得推断为 PASS。

## 开始 followups

- 复用现有验证器，检查真实事件/状态/原生读回；命令：`python example/tool/rerun_batch.py coverage_final_batches.py`。完成后仅按实际证据回填编号。

## rerun-batch17-qoe-failed 复核

- driver exit=0；证据 `example/tool/coverage_evidence/rerun-batch17-qoe-failed.json`。
```json
[
  {
    "ms": 548377,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "qoe",
      "mode": "failed"
    }
  },
  {
    "ms": 548486,
    "kind": "PREVIEW_THUMB",
    "engine": 292556440,
    "at": null,
    "bytes": null,
    "title": "Coverage 404.mp4"
  },
  {
    "ms": 548528,
    "kind": "REPORT",
    "name": "sessionStart",
    "params": {
      "uri": "http://127.0.0.1:18080/404.mp4?t=1793093518351942",
      "streamType": "vod",
      "audioOnly": true,
      "swapEnabled": false,
      "title": "Coverage 404.mp4"
    }
  },
  {
    "ms": 548530,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 548550,
    "kind": "REPORT",
    "name": "play",
    "params": {}
  },
  {
    "ms": 548551,
    "kind": "REPORT",
    "name": "sourceChange",
    "params": {
      "uri": "http://127.0.0.1:18080/404.mp4?t=1793093518351942"
    }
  },
  {
    "ms": 548565,
    "kind": "REPORT",
    "name": "error",
    "params": {
      "error": "Failed to open http://127.0.0.1:18080/404.mp4?t=1793093518351942.",
      "fatal": true,
      "code": "stream"
    }
  },
  {
    "ms": 548593,
    "kind": "REPORT",
    "name": "startupFail",
    "params": {
      "reason": "failed",
      "waitedMs": 106
    }
  },
  {
    "ms": 548593,
    "kind": "REPORT",
    "name": "sessionEnd",
    "params": {
      "reason": "failed",
      "watchedMs": 0,
      "stallCount": 0,
      "stallMs": 0,
      "rebufferRate": 0.0
    }
  },
  {
    "ms": 548927,
    "kind": "QOE_END",
    "mode": "failed",
    "reports": 7
  },
  {
    "ms": 548927,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## rerun-batch17-qoe-stall-release 复核

- driver exit=0；证据 `example/tool/coverage_evidence/rerun-batch17-qoe-stall-release.json`。
```json
[
  {
    "ms": 553740,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "stallRelease"
    }
  },
  {
    "ms": 553857,
    "kind": "PREVIEW_THUMB",
    "engine": 499436268,
    "at": null,
    "bytes": null,
    "title": "Coverage stall.mp4"
  },
  {
    "ms": 553900,
    "kind": "REPORT",
    "name": "sessionStart",
    "params": {
      "uri": "http://127.0.0.1:18080/stall.mp4?t=1793093523713419",
      "streamType": "vod",
      "audioOnly": true,
      "swapEnabled": false,
      "title": "Coverage stall.mp4"
    }
  },
  {
    "ms": 553906,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 553947,
    "kind": "REPORT",
    "name": "play",
    "params": {}
  },
  {
    "ms": 553948,
    "kind": "REPORT",
    "name": "sourceChange",
    "params": {
      "uri": "http://127.0.0.1:18080/stall.mp4?t=1793093523713419"
    }
  },
  {
    "ms": 554044,
    "kind": "REPORT",
    "name": "firstFrame",
    "params": {
      "ttffMs": 187,
      "audioOnly": true,
      "streamType": "vod",
      "signal": "restart"
    }
  },
  {
    "ms": 562270,
    "kind": "REPORT",
    "name": "rebuffer",
    "params": {
      "durationMs": 5496,
      "positionMs": 3018,
      "index": 1,
      "signal": "cache"
    }
  },
  {
    "ms": 562276,
    "kind": "STALL_MEASURE",
    "observedBufferWindow": 5469
  },
  {
    "ms": 562778,
    "kind": "REPORT",
    "name": "sessionEnd",
    "params": {
      "reason": "stopped",
      "watchedMs": 3236,
      "stallCount": 1,
      "stallMs": 5496,
      "rebufferRate": 0.6294090700870362,
      "completionPercent": 8.475000000000001
    }
  },
  {
    "ms": 563108,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## rerun-batch17-hls-playing 复核

- driver exit=0；证据 `example/tool/coverage_evidence/rerun-batch17-hls-playing.json`。
```json
[
  {
    "ms": 566377,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hls"
    }
  },
  {
    "ms": 566807,
    "kind": "PREVIEW_THUMB",
    "engine": 964885028,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 576034,
    "kind": "HLS_QUALITIES",
    "qualities": [
      {
        "label": "自动",
        "uri": ""
      },
      {
        "label": "360p",
        "uri": "http://127.0.0.1:18084/high/index.m3u8"
      },
      {
        "label": "180p",
        "uri": "http://127.0.0.1:18084/low/index.m3u8"
      }
    ]
  },
  {
    "ms": 576649,
    "kind": "HLS_RESTART",
    "run": 0,
    "position": 23,
    "target": 8023,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 577102,
    "kind": "HLS_RESTART",
    "run": 0,
    "position": 8023,
    "target": 8023,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 577846,
    "kind": "HLS_NATIVE",
    "run": 0,
    "target": 8023,
    "landed": 8023,
    "continued": 8783,
    "samples": [
      23,
      8023
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 8703,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 577846,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=0 target=8023 landed=8023 error=0 continued=8783"
  },
  {
    "ms": 579079,
    "kind": "HLS_RESTART",
    "run": 1,
    "position": 178,
    "target": 8783,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 579241,
    "kind": "HLS_RESTART",
    "run": 1,
    "position": 8783,
    "target": 8783,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 579964,
    "kind": "HLS_NATIVE",
    "run": 1,
    "target": 8783,
    "landed": 8783,
    "continued": 9463,
    "samples": [
      178,
      8783
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 9303,
      "size": "320x180",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 579964,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=1 target=8783 landed=8783 error=0 continued=9463"
  },
  {
    "ms": 581138,
    "kind": "HLS_RESTART",
    "run": 2,
    "position": 23,
    "target": 9463,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 581452,
    "kind": "HLS_RESTART",
    "run": 2,
    "position": 9463,
    "target": 9463,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 582178,
    "kind": "HLS_NATIVE",
    "run": 2,
    "target": 9463,
    "landed": 9463,
    "continued": 10143,
    "samples": [
      23,
      9463
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 9983,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 582178,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=2 target=9463 landed=9463 error=0 continued=10143"
  },
  {
    "ms": 583247,
    "kind": "HLS_RESTART",
    "run": 3,
    "position": 23,
    "target": 10143,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 583301,
    "kind": "HLS_RESTART",
    "run": 3,
    "position": 10143,
    "target": 10143,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 584031,
    "kind": "HLS_NATIVE",
    "run": 3,
    "target": 10143,
    "landed": 10143,
    "continued": 10823,
    "samples": [
      23,
      10143
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 10663,
      "size": "320x180",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 584032,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=3 target=10143 landed=10143 error=0 continued=10823"
  },
  {
    "ms": 585204,
    "kind": "HLS_RESTART",
    "run": 4,
    "position": 85,
    "target": 10823,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 585420,
    "kind": "HLS_RESTART",
    "run": 4,
    "position": 10823,
    "target": 10823,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 586132,
    "kind": "HLS_NATIVE",
    "run": 4,
    "target": 10823,
    "landed": 10823,
    "continued": 11503,
    "samples": [
      85,
      10823
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 11383,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 586132,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=4 target=10823 landed=10823 error=0 continued=11503"
  },
  {
    "ms": 590135,
    "kind": "HLS_END",
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 15263,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "downshifts": 0
  },
  {
    "ms": 590425,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## rerun-batch17-hls-playing-cutover 复核

- driver exit=0；证据 `example/tool/coverage_evidence/rerun-batch17-hls-playing-cutover.json`。
```json
[
  {
    "ms": 593670,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hls",
      "cutover": "true"
    }
  },
  {
    "ms": 594109,
    "kind": "PREVIEW_THUMB",
    "engine": 768294718,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 603586,
    "kind": "HLS_QUALITIES",
    "qualities": [
      {
        "label": "自动",
        "uri": ""
      },
      {
        "label": "360p",
        "uri": "http://127.0.0.1:18084/high/index.m3u8"
      },
      {
        "label": "180p",
        "uri": "http://127.0.0.1:18084/low/index.m3u8"
      }
    ]
  },
  {
    "ms": 604193,
    "kind": "HLS_RESTART",
    "run": 0,
    "position": 23,
    "target": 8223,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 604278,
    "kind": "HLS_RESTART",
    "run": 0,
    "position": 8223,
    "target": 8223,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 605000,
    "kind": "HLS_NATIVE",
    "run": 0,
    "target": 8223,
    "landed": 8223,
    "continued": 8823,
    "samples": [
      23,
      8223
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 8703,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 605000,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=0 target=8223 landed=8223 error=0 continued=8823"
  },
  {
    "ms": 606245,
    "kind": "HLS_RESTART",
    "run": 1,
    "position": 23,
    "target": 8823,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 606407,
    "kind": "HLS_RESTART",
    "run": 1,
    "position": 8823,
    "target": 8823,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 607143,
    "kind": "HLS_NATIVE",
    "run": 1,
    "target": 8823,
    "landed": 8823,
    "continued": 9503,
    "samples": [
      23,
      8823
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 9423,
      "size": "320x180",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 607144,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=1 target=8823 landed=8823 error=0 continued=9503"
  },
  {
    "ms": 608367,
    "kind": "HLS_RESTART",
    "run": 2,
    "position": 23,
    "target": 9503,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 608614,
    "kind": "HLS_RESTART",
    "run": 2,
    "position": 9503,
    "target": 9503,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 609324,
    "kind": "HLS_NATIVE",
    "run": 2,
    "target": 9503,
    "landed": 9503,
    "continued": 10183,
    "samples": [
      23,
      9503
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 10103,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 609325,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=2 target=9503 landed=9503 error=0 continued=10183"
  },
  {
    "ms": 609887,
    "kind": "HLS_RESTART",
    "run": 3,
    "position": 23,
    "target": 10183,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 610514,
    "kind": "HLS_RESTART",
    "run": 3,
    "position": 23,
    "target": 10183,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 625177,
    "kind": "HLS_NATIVE",
    "run": 3,
    "target": 10183,
    "landed": -1,
    "continued": 14623,
    "samples": [
      23,
      23
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 14503,
      "size": "320x180",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 625177,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": false,
    "detail": "run=3 target=10183 landed=-1 error=-10184 continued=14623"
  },
  {
    "ms": 626395,
    "kind": "HLS_RESTART",
    "run": 4,
    "position": 23,
    "target": 14623,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 626510,
    "kind": "HLS_RESTART",
    "run": 4,
    "position": 14623,
    "target": 14623,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 627228,
    "kind": "HLS_NATIVE",
    "run": 4,
    "target": 14623,
    "landed": 14623,
    "continued": 15223,
    "samples": [
      23,
      14623
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 15143,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 627228,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=4 target=14623 landed=14623 error=0 continued=15223"
  },
  {
    "ms": 631231,
    "kind": "HLS_END",
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 19183,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "downshifts": 0
  },
  {
    "ms": 631525,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## rerun-batch17-hls-paused 复核

- driver exit=0；证据 `example/tool/coverage_evidence/rerun-batch17-hls-paused.json`。
```json
[
  {
    "ms": 636185,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hls",
      "paused": "true"
    }
  },
  {
    "ms": 636645,
    "kind": "PREVIEW_THUMB",
    "engine": 664777085,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 645961,
    "kind": "HLS_QUALITIES",
    "qualities": [
      {
        "label": "自动",
        "uri": ""
      },
      {
        "label": "360p",
        "uri": "http://127.0.0.1:18084/high/index.m3u8"
      },
      {
        "label": "180p",
        "uri": "http://127.0.0.1:18084/low/index.m3u8"
      }
    ]
  },
  {
    "ms": 646554,
    "kind": "HLS_RESTART",
    "run": 0,
    "position": 23,
    "target": 8063,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 646633,
    "kind": "HLS_RESTART",
    "run": 0,
    "position": 8063,
    "target": 8063,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 647348,
    "kind": "HLS_NATIVE",
    "run": 0,
    "target": 8063,
    "landed": 8063,
    "continued": 8063,
    "samples": [
      23,
      8063
    ],
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 8063,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 647348,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=0 target=8063 landed=8063 error=0 continued=8063"
  },
  {
    "ms": 648588,
    "kind": "HLS_RESTART",
    "run": 1,
    "position": 23,
    "target": 8063,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 648645,
    "kind": "HLS_RESTART",
    "run": 1,
    "position": 8063,
    "target": 8063,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 649370,
    "kind": "HLS_NATIVE",
    "run": 1,
    "target": 8063,
    "landed": 8063,
    "continued": 8063,
    "samples": [
      23,
      8063
    ],
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40007,
      "position": 8063,
      "size": "320x180",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 649371,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=1 target=8063 landed=8063 error=0 continued=8063"
  },
  {
    "ms": 650612,
    "kind": "HLS_RESTART",
    "run": 2,
    "position": 23,
    "target": 8063,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 650706,
    "kind": "HLS_RESTART",
    "run": 2,
    "position": 8063,
    "target": 8063,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 651448,
    "kind": "HLS_NATIVE",
    "run": 2,
    "target": 8063,
    "landed": 8063,
    "continued": 8063,
    "samples": [
      23,
      8063
    ],
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40007,
      "position": 8063,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 651448,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=2 target=8063 landed=8063 error=0 continued=8063"
  },
  {
    "ms": 652643,
    "kind": "HLS_RESTART",
    "run": 3,
    "position": 23,
    "target": 8063,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 652680,
    "kind": "HLS_RESTART",
    "run": 3,
    "position": 8063,
    "target": 8063,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 653421,
    "kind": "HLS_NATIVE",
    "run": 3,
    "target": 8063,
    "landed": 8063,
    "continued": 8063,
    "samples": [
      23,
      8063
    ],
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40007,
      "position": 8063,
      "size": "320x180",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 653421,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=3 target=8063 landed=8063 error=0 continued=8063"
  },
  {
    "ms": 654616,
    "kind": "HLS_RESTART",
    "run": 4,
    "position": 23,
    "target": 8063,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 654654,
    "kind": "HLS_RESTART",
    "run": 4,
    "position": 8063,
    "target": 8063,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 655374,
    "kind": "HLS_NATIVE",
    "run": 4,
    "target": 8063,
    "landed": 8063,
    "continued": 8063,
    "samples": [
      23,
      8063
    ],
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40007,
      "position": 8063,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 655374,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=4 target=8063 landed=8063 error=0 continued=8063"
  },
  {
    "ms": 659424,
    "kind": "HLS_END",
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 11903,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "downshifts": 0
  },
  {
    "ms": 659652,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## rerun-batch17-tls-probe 复核

- driver exit=0；证据 `example/tool/coverage_evidence/rerun-batch17-tls-probe.json`。
```json
[
  {
    "ms": 663106,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "tlsProbe"
    }
  },
  {
    "ms": 663321,
    "kind": "PREVIEW_THUMB",
    "engine": 374902173,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 663357,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 663462,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "ffmpeg",
    "text": "tls: mbedtls_ssl_get_verify_result reported problems with the certificate verification, returned flags: 4"
  },
  {
    "ms": 663463,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "stream",
    "text": "Failed to open https://127.0.0.1:18443/vod.mp4?t=0."
  },
  {
    "ms": 663472,
    "kind": "TLS_READBACK",
    "endpoint": "127.0.0.1:18443",
    "path": "vod.mp4",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 663473,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": false,
    "detail": "run=0 endpoint=127.0.0.1:18443 path=vod.mp4 errors=[Failed to open https://127.0.0.1:18443/vod.mp4?t=0.]"
  },
  {
    "ms": 663506,
    "kind": "PREVIEW_THUMB",
    "engine": 519743829,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 663518,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 663641,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "stream",
    "text": "Failed to open https://127.0.0.1:18443/low/index.m3u8?t=0."
  },
  {
    "ms": 663683,
    "kind": "TLS_READBACK",
    "endpoint": "127.0.0.1:18443",
    "path": "low/index.m3u8",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 663685,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": false,
    "detail": "run=0 endpoint=127.0.0.1:18443 path=low/index.m3u8 errors=[Failed to open https://127.0.0.1:18443/low/index.m3u8?t=0.]"
  },
  {
    "ms": 663755,
    "kind": "PREVIEW_THUMB",
    "engine": 537122699,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 663769,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 664874,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "lavf",
    "text": "Failed to create file cache."
  },
  {
    "ms": 664914,
    "kind": "TLS_READBACK",
    "endpoint": "localhost:18447",
    "path": "vod.mp4",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 664914,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": true,
    "detail": "run=0 endpoint=localhost:18447 path=vod.mp4 errors=[]"
  },
  {
    "ms": 665040,
    "kind": "PREVIEW_THUMB",
    "engine": 623642523,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 665051,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 665569,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "lavf",
    "text": "Failed to create file cache."
  },
  {
    "ms": 665592,
    "kind": "TLS_READBACK",
    "endpoint": "localhost:18447",
    "path": "low/index.m3u8",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 665592,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": true,
    "detail": "run=0 endpoint=localhost:18447 path=low/index.m3u8 errors=[]"
  },
  {
    "ms": 665637,
    "kind": "PREVIEW_THUMB",
    "engine": 600879732,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 665660,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 665770,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "stream",
    "text": "Failed to open https://127.0.0.1:18443/vod.mp4?t=1."
  },
  {
    "ms": 665810,
    "kind": "TLS_READBACK",
    "endpoint": "127.0.0.1:18443",
    "path": "vod.mp4",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 665810,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": false,
    "detail": "run=1 endpoint=127.0.0.1:18443 path=vod.mp4 errors=[Failed to open https://127.0.0.1:18443/vod.mp4?t=1.]"
  },
  {
    "ms": 665854,
    "kind": "PREVIEW_THUMB",
    "engine": 847112254,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 665871,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 665973,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "stream",
    "text": "Failed to open https://127.0.0.1:18443/low/index.m3u8?t=1."
  },
  {
    "ms": 665987,
    "kind": "TLS_READBACK",
    "endpoint": "127.0.0.1:18443",
    "path": "low/index.m3u8",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 665987,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": false,
    "detail": "run=1 endpoint=127.0.0.1:18443 path=low/index.m3u8 errors=[Failed to open https://127.0.0.1:18443/low/index.m3u8?t=1.]"
  },
  {
    "ms": 666033,
    "kind": "PREVIEW_THUMB",
    "engine": 504431100,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 666042,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 666206,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "lavf",
    "text": "Failed to create file cache."
  },
  {
    "ms": 666268,
    "kind": "TLS_READBACK",
    "endpoint": "localhost:18447",
    "path": "vod.mp4",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 666268,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": true,
    "detail": "run=1 endpoint=localhost:18447 path=vod.mp4 errors=[]"
  },
  {
    "ms": 666300,
    "kind": "PREVIEW_THUMB",
    "engine": 578018056,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 666313,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 666757,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "lavf",
    "text": "Failed to create file cache."
  },
  {
    "ms": 666790,
    "kind": "TLS_READBACK",
    "endpoint": "localhost:18447",
    "path": "low/index.m3u8",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 666791,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": true,
    "detail": "run=1 endpoint=localhost:18447 path=low/index.m3u8 errors=[]"
  },
  {
    "ms": 666876,
    "kind": "PREVIEW_THUMB",
    "engine": 71959820,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 666882,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 666972,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "stream",
    "text": "Failed to open https://127.0.0.1:18443/vod.mp4?t=2."
  },
  {
    "ms": 666992,
    "kind": "TLS_READBACK",
    "endpoint": "127.0.0.1:18443",
    "path": "vod.mp4",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 666992,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": false,
    "detail": "run=2 endpoint=127.0.0.1:18443 path=vod.mp4 errors=[Failed to open https://127.0.0.1:18443/vod.mp4?t=2.]"
  },
  {
    "ms": 667027,
    "kind": "PREVIEW_THUMB",
    "engine": 35043428,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 667033,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 667145,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "stream",
    "text": "Failed to open https://127.0.0.1:18443/low/index.m3u8?t=2."
  },
  {
    "ms": 667149,
    "kind": "TLS_READBACK",
    "endpoint": "127.0.0.1:18443",
    "path": "low/index.m3u8",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 667150,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": false,
    "detail": "run=2 endpoint=127.0.0.1:18443 path=low/index.m3u8 errors=[Failed to open https://127.0.0.1:18443/low/index.m3u8?t=2.]"
  },
  {
    "ms": 667185,
    "kind": "PREVIEW_THUMB",
    "engine": 269044235,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 667192,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 667488,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "lavf",
    "text": "Failed to create file cache."
  },
  {
    "ms": 667540,
    "kind": "TLS_READBACK",
    "endpoint": "localhost:18447",
    "path": "vod.mp4",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 667540,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": true,
    "detail": "run=2 endpoint=localhost:18447 path=vod.mp4 errors=[]"
  },
  {
    "ms": 667560,
    "kind": "PREVIEW_THUMB",
    "engine": 576202300,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 667567,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 668030,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "lavf",
    "text": "Failed to create file cache."
  },
  {
    "ms": 668046,
    "kind": "TLS_READBACK",
    "endpoint": "localhost:18447",
    "path": "low/index.m3u8",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 668046,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": true,
    "detail": "run=2 endpoint=localhost:18447 path=low/index.m3u8 errors=[]"
  },
  {
    "ms": 668050,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 结束 followups

- exit=0；驱动输出 `example/tool/coverage_evidence/rerun-plan-followups.log`；原始结果均用 rerun- 前缀。异常/超时不得推断为 PASS。

## 开始 hls-native

- 复用现有验证器，检查真实事件/状态/原生读回；命令：`python example/tool/rerun_batch.py coverage_hls_final.py`。完成后仅按实际证据回填编号。

## HLS间歇失败检查点

- 不能用其他成功样本抵消这次真实原生失败；分类暂记真实续播缺陷，未修改库。

## rerun-batch21-hls-normal 原生位置复核

- 每模式重启独立进程；HTTP源无流量节流。
```json
[
  {
    "ms": 2954,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hls"
    }
  },
  {
    "ms": 3369,
    "kind": "PREVIEW_THUMB",
    "engine": 192246473,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 11940,
    "kind": "HLS_QUALITIES",
    "qualities": [
      {
        "label": "自动",
        "uri": ""
      },
      {
        "label": "360p",
        "uri": "http://127.0.0.1:18084/high/index.m3u8"
      },
      {
        "label": "180p",
        "uri": "http://127.0.0.1:18084/low/index.m3u8"
      }
    ]
  },
  {
    "ms": 12584,
    "kind": "HLS_RESTART",
    "run": 0,
    "position": 23,
    "target": 8103,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 12897,
    "kind": "HLS_RESTART",
    "run": 0,
    "position": 8103,
    "target": 8103,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 13630,
    "kind": "HLS_NATIVE",
    "run": 0,
    "target": 8103,
    "landed": 8103,
    "continued": 8783,
    "samples": [
      23,
      8103
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 8743,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 13630,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=0 target=8103 landed=8103 error=0 continued=8783"
  },
  {
    "ms": 14970,
    "kind": "HLS_RESTART",
    "run": 1,
    "position": 23,
    "target": 8783,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 15106,
    "kind": "HLS_RESTART",
    "run": 1,
    "position": 8783,
    "target": 8783,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 15825,
    "kind": "HLS_NATIVE",
    "run": 1,
    "target": 8783,
    "landed": 8783,
    "continued": 9423,
    "samples": [
      23,
      8783
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 9223,
      "size": "320x180",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 15825,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=1 target=8783 landed=8783 error=0 continued=9423"
  },
  {
    "ms": 17064,
    "kind": "HLS_RESTART",
    "run": 2,
    "position": 23,
    "target": 9423,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 17376,
    "kind": "HLS_RESTART",
    "run": 2,
    "position": 9423,
    "target": 9423,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 18096,
    "kind": "HLS_NATIVE",
    "run": 2,
    "target": 9423,
    "landed": 9423,
    "continued": 10103,
    "samples": [
      23,
      9423
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 9983,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 18097,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=2 target=9423 landed=9423 error=0 continued=10103"
  },
  {
    "ms": 19468,
    "kind": "HLS_RESTART",
    "run": 3,
    "position": 23,
    "target": 10103,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 19512,
    "kind": "HLS_RESTART",
    "run": 3,
    "position": 10103,
    "target": 10103,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 20217,
    "kind": "HLS_NATIVE",
    "run": 3,
    "target": 10103,
    "landed": 10103,
    "continued": 10703,
    "samples": [
      23,
      10103
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 10543,
      "size": "320x180",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 20217,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=3 target=10103 landed=10103 error=0 continued=10703"
  },
  {
    "ms": 21440,
    "kind": "HLS_RESTART",
    "run": 4,
    "position": 23,
    "target": 10703,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 21552,
    "kind": "HLS_RESTART",
    "run": 4,
    "position": 10703,
    "target": 10703,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 22270,
    "kind": "HLS_NATIVE",
    "run": 4,
    "target": 10703,
    "landed": 10703,
    "continued": 11343,
    "samples": [
      23,
      10703
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 11263,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 22271,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=4 target=10703 landed=10703 error=0 continued=11343"
  },
  {
    "ms": 26277,
    "kind": "HLS_END",
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 15303,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "downshifts": 0
  },
  {
    "ms": 26589,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## rerun-batch21-hls-cutover 原生位置复核

- 每模式重启独立进程；HTTP源无流量节流。
```json
[
  {
    "ms": 3882,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hls",
      "cutover": "true"
    }
  },
  {
    "ms": 4298,
    "kind": "PREVIEW_THUMB",
    "engine": 693416108,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 13449,
    "kind": "HLS_QUALITIES",
    "qualities": [
      {
        "label": "自动",
        "uri": ""
      },
      {
        "label": "360p",
        "uri": "http://127.0.0.1:18084/high/index.m3u8"
      },
      {
        "label": "180p",
        "uri": "http://127.0.0.1:18084/low/index.m3u8"
      }
    ]
  },
  {
    "ms": 14089,
    "kind": "HLS_RESTART",
    "run": 0,
    "position": 23,
    "target": 8223,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 14193,
    "kind": "HLS_RESTART",
    "run": 0,
    "position": 8223,
    "target": 8223,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 14918,
    "kind": "HLS_NATIVE",
    "run": 0,
    "target": 8223,
    "landed": 8223,
    "continued": 8823,
    "samples": [
      23,
      8223
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 8783,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 14918,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=0 target=8223 landed=8223 error=0 continued=8823"
  },
  {
    "ms": 16302,
    "kind": "HLS_RESTART",
    "run": 1,
    "position": 23,
    "target": 8823,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 16489,
    "kind": "HLS_RESTART",
    "run": 1,
    "position": 8823,
    "target": 8823,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 17193,
    "kind": "HLS_NATIVE",
    "run": 1,
    "target": 8823,
    "landed": 8823,
    "continued": 9503,
    "samples": [
      23,
      8823
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 9383,
      "size": "320x180",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 17193,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=1 target=8823 landed=8823 error=0 continued=9503"
  },
  {
    "ms": 18453,
    "kind": "HLS_RESTART",
    "run": 2,
    "position": 23,
    "target": 9503,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 18713,
    "kind": "HLS_RESTART",
    "run": 2,
    "position": 9503,
    "target": 9503,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 19415,
    "kind": "HLS_NATIVE",
    "run": 2,
    "target": 9503,
    "landed": 9503,
    "continued": 10143,
    "samples": [
      23,
      9503
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 10023,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 19416,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=2 target=9503 landed=9503 error=0 continued=10143"
  },
  {
    "ms": 20660,
    "kind": "HLS_RESTART",
    "run": 3,
    "position": 23,
    "target": 10143,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 20711,
    "kind": "HLS_RESTART",
    "run": 3,
    "position": 10143,
    "target": 10143,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 21452,
    "kind": "HLS_NATIVE",
    "run": 3,
    "target": 10143,
    "landed": 10143,
    "continued": 10823,
    "samples": [
      23,
      10143
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 10703,
      "size": "320x180",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 21453,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=3 target=10143 landed=10143 error=0 continued=10823"
  },
  {
    "ms": 22805,
    "kind": "HLS_RESTART",
    "run": 4,
    "position": 23,
    "target": 10823,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 22966,
    "kind": "HLS_RESTART",
    "run": 4,
    "position": 10823,
    "target": 10823,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 23697,
    "kind": "HLS_NATIVE",
    "run": 4,
    "target": 10823,
    "landed": 10823,
    "continued": 11503,
    "samples": [
      23,
      10823
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 11463,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 23697,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=4 target=10823 landed=10823 error=0 continued=11503"
  },
  {
    "ms": 27702,
    "kind": "HLS_END",
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 15303,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "downshifts": 0
  },
  {
    "ms": 27933,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## rerun-batch21-hls-paused 原生位置复核

- 每模式重启独立进程；HTTP源无流量节流。
```json
[
  {
    "ms": 6364,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hls",
      "paused": "true"
    }
  },
  {
    "ms": 6808,
    "kind": "PREVIEW_THUMB",
    "engine": 202682970,
    "at": null,
    "bytes": null,
    "title": null
  },
  {
    "ms": 16271,
    "kind": "HLS_QUALITIES",
    "qualities": [
      {
        "label": "自动",
        "uri": ""
      },
      {
        "label": "360p",
        "uri": "http://127.0.0.1:18084/high/index.m3u8"
      },
      {
        "label": "180p",
        "uri": "http://127.0.0.1:18084/low/index.m3u8"
      }
    ]
  },
  {
    "ms": 16915,
    "kind": "HLS_RESTART",
    "run": 0,
    "position": 23,
    "target": 8223,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 17000,
    "kind": "HLS_RESTART",
    "run": 0,
    "position": 8223,
    "target": 8223,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 17710,
    "kind": "HLS_NATIVE",
    "run": 0,
    "target": 8223,
    "landed": 8223,
    "continued": 8223,
    "samples": [
      23,
      8223
    ],
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40007,
      "position": 8223,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 17711,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=0 target=8223 landed=8223 error=0 continued=8223"
  },
  {
    "ms": 18877,
    "kind": "HLS_RESTART",
    "run": 1,
    "position": 23,
    "target": 8223,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 18957,
    "kind": "HLS_RESTART",
    "run": 1,
    "position": 8223,
    "target": 8223,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 19675,
    "kind": "HLS_NATIVE",
    "run": 1,
    "target": 8223,
    "landed": 8223,
    "continued": 8223,
    "samples": [
      23,
      8223
    ],
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40007,
      "position": 8223,
      "size": "320x180",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 19675,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=1 target=8223 landed=8223 error=0 continued=8223"
  },
  {
    "ms": 21016,
    "kind": "HLS_RESTART",
    "run": 2,
    "position": 23,
    "target": 8223,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 21072,
    "kind": "HLS_RESTART",
    "run": 2,
    "position": 8223,
    "target": 8223,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 21814,
    "kind": "HLS_NATIVE",
    "run": 2,
    "target": 8223,
    "landed": 8223,
    "continued": 8223,
    "samples": [
      23,
      8223
    ],
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40007,
      "position": 8223,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 21814,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=2 target=8223 landed=8223 error=0 continued=8223"
  },
  {
    "ms": 23019,
    "kind": "HLS_RESTART",
    "run": 3,
    "position": 23,
    "target": 8223,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 23075,
    "kind": "HLS_RESTART",
    "run": 3,
    "position": 8223,
    "target": 8223,
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 23801,
    "kind": "HLS_NATIVE",
    "run": 3,
    "target": 8223,
    "landed": 8223,
    "continued": 8223,
    "samples": [
      23,
      8223
    ],
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40007,
      "position": 8223,
      "size": "320x180",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 23802,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=3 target=8223 landed=8223 error=0 continued=8223"
  },
  {
    "ms": 25035,
    "kind": "HLS_RESTART",
    "run": 4,
    "position": 23,
    "target": 8223,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 25103,
    "kind": "HLS_RESTART",
    "run": 4,
    "position": 8223,
    "target": 8223,
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 25845,
    "kind": "HLS_NATIVE",
    "run": 4,
    "target": 8223,
    "landed": 8223,
    "continued": 8223,
    "samples": [
      23,
      8223
    ],
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40007,
      "position": 8223,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/high/index.m3u8"
  },
  {
    "ms": 25846,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=4 target=8223 landed=8223 error=0 continued=8223"
  },
  {
    "ms": 29900,
    "kind": "HLS_END",
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 12063,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40007,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "downshifts": 0
  },
  {
    "ms": 30198,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 结束 hls-native

- exit=0；驱动输出 `example/tool/coverage_evidence/rerun-plan-hls-native.log`；原始结果均用 rerun- 前缀。异常/超时不得推断为 PASS。

## 开始 he-firstframe

- 复用现有验证器，检查真实事件/状态/原生读回；命令：`python example/tool/coverage_suite_device.py he --only V1,V2,V3,V4 --runs 3 --timeout 900 --name rerun-he-firstframe`。完成后仅按实际证据回填编号。

## 结束 he-firstframe

- exit=0；驱动输出 `example/tool/coverage_evidence/rerun-plan-he-firstframe.log`；原始结果均用 rerun- 前缀。异常/超时不得推断为 PASS。

## 开始 he-recovery

- 复用现有验证器，检查真实事件/状态/原生读回；命令：`python example/tool/coverage_suite_device.py he --only V5,V6,V7,V8,V9,V10,V11 --runs 3 --timeout 1200 --name rerun-he-recovery`。完成后仅按实际证据回填编号。

## API主要路径完成检查点

- 更完整UI、事件载荷和性能分组仍在运行；本次所有引用均为rerun证据。

## 结束 he-recovery

- exit=0；驱动输出 `example/tool/coverage_evidence/rerun-plan-he-recovery.log`；原始结果均用 rerun- 前缀。异常/超时不得推断为 PASS。

## 开始 keepalive-core

- 复用现有验证器，检查真实事件/状态/原生读回；命令：`python example/tool/coverage_suite_device.py keepAlive --only S1,S2,S3,S6,S13,S17 --runs 3 --timeout 1200 --name rerun-keepalive-core`。完成后仅按实际证据回填编号。

## 结束 keepalive-core

- exit=0；驱动输出 `example/tool/coverage_evidence/rerun-plan-keepalive-core.log`；原始结果均用 rerun- 前缀。异常/超时不得推断为 PASS。

## 开始 existing-pages

- 复用现有验证器，检查真实事件/状态/原生读回；命令：`python example/tool/rerun_batch.py coverage_followup_batches.py`。完成后仅按实际证据回填编号。

## 开始 rerun-batch8-keepAlive-native

- 复用 keepAlive 页面，核验事件与设备状态；多轮计时取平均。

## rerun-batch8-keepAlive-native 自动检查点

- 复用页运行；逐编号最终结论需结合下面原始断言复核。
- driver exit=0；`{"selector": "keepAlive|S7,S8,S8B,S14|1", "completed": true, "lines": 1832, "pid": "5116"}`。
- 日志：`example/tool/coverage_evidence/rerun-batch8-keepAlive-native.log`；截图/系统读回/采样同前缀。
```text
10-27 17:50:01.581  5116  5116 I flutter : [STANDBY] 17:50:01.581   17560ms VERDICT S14 PASS screenshots taken by the external script (normal / holding1 / holding2 / restored)
10-27 17:53:15.349  5116  5116 I flutter : [STANDBY] 17:53:15.349  211328ms VERDICT S7 PASS videoCameBack=20/20 signalLanded=0/20
10-27 17:53:36.603  5116  5116 I flutter : [STANDBY] 17:53:36.603  232582ms VERDICT S8 PASS fact: playing=true advance=3040ms
10-27 17:53:52.016  5116  5116 I flutter : [STANDBY] 17:53:52.016  247995ms VERDICT S8B PASS fact recorded
10-27 17:53:52.817  5116  5116 I flutter : [STANDBY] 17:53:52.816  248795ms === SUMMARY (samples in ms) ===
10-27 17:53:52.817  5116  5116 I flutter : [STANDBY] 17:53:52.817  248796ms SUMMARY S14 pass=1 fail=0
10-27 17:53:52.817  5116  5116 I flutter : [STANDBY] 17:53:52.817  248796ms SUMMARY S7 pass=1 fail=0
10-27 17:53:52.817  5116  5116 I flutter : [STANDBY] 17:53:52.817  248796ms SUMMARY S8 pass=1 fail=0
10-27 17:53:52.817  5116  5116 I flutter : [STANDBY] 17:53:52.817  248796ms SUMMARY S8B pass=1 fail=0
10-27 17:53:52.817  5116  5116 I flutter : [STANDBY] 17:53:52.817  248796ms AUTORUN DONE
```

## 开始 rerun-batch9-keepAlive-cpu-drift

- 复用 keepAlive 页面，核验事件与设备状态；多轮计时取平均。

## rerun-batch9-keepAlive-cpu-drift 自动检查点

- 复用页运行；逐编号最终结论需结合下面原始断言复核。
- driver exit=0；`{"selector": "keepAlive|S4,S5,S5C|3", "completed": true, "lines": 3406, "pid": "5123"}`。
- 日志：`example/tool/coverage_evidence/rerun-batch9-keepAlive-cpu-drift.log`；截图/系统读回/采样同前缀。
```text
10-27 17:54:28.404  5123  5123 I flutter : [STANDBY] 17:54:28.404   32186ms VERDICT S5 PASS drift=149ms
10-27 17:55:01.966  5123  5123 I flutter : [STANDBY] 17:55:01.966   65748ms VERDICT S5 PASS drift=625ms
10-27 17:55:35.530  5123  5123 I flutter : [STANDBY] 17:55:35.529   99311ms VERDICT S5 PASS drift=567ms
10-27 17:56:08.907  5123  5123 I flutter : [STANDBY] 17:56:08.907  132689ms VERDICT S5C PASS control drift=2ms
10-27 17:56:42.326  5123  5123 I flutter : [STANDBY] 17:56:42.326  166108ms VERDICT S5C PASS control drift=43ms
10-27 17:57:16.106  5123  5123 I flutter : [STANDBY] 17:57:16.106  199888ms VERDICT S5C PASS control drift=-5ms
10-27 17:57:37.594  5123  5123 I flutter : [STANDBY] 17:57:37.594  221376ms VERDICT S4 PASS normal recorded (see PHASE lines + external CPU/traffic)
10-27 17:57:59.171  5123  5123 I flutter : [STANDBY] 17:57:59.171  242953ms VERDICT S4 PASS B recorded (see PHASE lines + external CPU/traffic)
10-27 17:58:23.279  5123  5123 I flutter : [STANDBY] 17:58:23.279  267061ms VERDICT S4 PASS C recorded (see PHASE lines + external CPU/traffic)
10-27 17:58:44.476  5123  5123 I flutter : [STANDBY] 17:58:44.476  288258ms VERDICT S4 PASS D recorded (see PHASE lines + external CPU/traffic)
10-27 17:59:05.881  5123  5123 I flutter : [STANDBY] 17:59:05.881  309663ms VERDICT S4 PASS normal recorded (see PHASE lines + external CPU/traffic)
10-27 17:59:27.163  5123  5123 I flutter : [STANDBY] 17:59:27.162  330944ms VERDICT S4 PASS B recorded (see PHASE lines + external CPU/traffic)
10-27 17:59:51.217  5123  5123 I flutter : [STANDBY] 17:59:51.216  354998ms VERDICT S4 PASS C recorded (see PHASE lines + external CPU/traffic)
10-27 18:00:12.594  5123  5123 I flutter : [STANDBY] 18:00:12.594  376376ms VERDICT S4 PASS D recorded (see PHASE lines + external CPU/traffic)
10-27 18:00:33.820  5123  5123 I flutter : [STANDBY] 18:00:33.820  397602ms VERDICT S4 PASS normal recorded (see PHASE lines + external CPU/traffic)
10-27 18:00:55.277  5123  5123 I flutter : [STANDBY] 18:00:55.277  419059ms VERDICT S4 PASS B recorded (see PHASE lines + external CPU/traffic)
10-27 18:01:19.359  5123  5123 I flutter : [STANDBY] 18:01:19.359  443141ms VERDICT S4 PASS C recorded (see PHASE lines + external CPU/traffic)
10-27 18:01:40.811  5123  5123 I flutter : [STANDBY] 18:01:40.811  464593ms VERDICT S4 PASS D recorded (see PHASE lines + external CPU/traffic)
10-27 18:01:41.613  5123  5123 I flutter : [STANDBY] 18:01:41.613  465395ms === SUMMARY (samples in ms) ===
10-27 18:01:41.613  5123  5123 I flutter : [STANDBY] 18:01:41.613  465395ms SUMMARY S5.driftMs values=[149,625,567] n=3 min=149 max=625 avg=447.0 median=567.0
10-27 18:01:41.614  5123  5123 I flutter : [STANDBY] 18:01:41.614  465395ms SUMMARY S5C.driftMs values=[2,43,5] n=3 min=2 max=43 avg=16.7 median=5.0
10-27 18:01:41.614  5123  5123 I flutter : [STANDBY] 18:01:41.614  465396ms SUMMARY S4 pass=12 fail=0
10-27 18:01:41.614  5123  5123 I flutter : [STANDBY] 18:01:41.614  465396ms SUMMARY S5 pass=3 fail=0
10-27 18:01:41.614  5123  5123 I flutter : [STANDBY] 18:01:41.614  465396ms SUMMARY S5C pass=3 fail=0
10-27 18:01:41.614  5123  5123 I flutter : [STANDBY] 18:01:41.614  465396ms AUTORUN DONE
```

## 开始 rerun-batch10-mute

- 复用 mute 页面，核验事件与设备状态；多轮计时取平均。

## rerun-batch10-mute 自动检查点

- 复用页运行；逐编号最终结论需结合下面原始断言复核。
- driver exit=0；`{"selector": "mute|Q13A,Q13B,Q13C|5", "completed": true, "lines": 7921, "pid": "5126"}`。
- 日志：`example/tool/coverage_evidence/rerun-batch10-mute.log`；截图/系统读回/采样同前缀。
```text
10-27 18:02:02.154  5126  5126 I flutter : [Q13] 18:02:02.154   16106ms VERDICT Q13A PASS warming: active(k1).mute=no shadow(k2).mute=yes swapped=true committed(live k2).mute=no
10-27 18:02:18.741  5126  5126 I flutter : [Q13] 18:02:18.741   32693ms VERDICT Q13A PASS warming: active(k1).mute=no shadow(k2).mute=yes swapped=true committed(live k2).mute=no
10-27 18:02:35.005  5126  5126 I flutter : [Q13] 18:02:35.005   48956ms VERDICT Q13A PASS warming: active(k1).mute=no shadow(k2).mute=yes swapped=true committed(live k2).mute=no
10-27 18:02:51.318  5126  5126 I flutter : [Q13] 18:02:51.318   65270ms VERDICT Q13A PASS warming: active(k1).mute=no shadow(k2).mute=yes swapped=true committed(live k2).mute=no
10-27 18:03:07.730  5126  5126 I flutter : [Q13] 18:03:07.730   81682ms VERDICT Q13A PASS warming: active(k1).mute=no shadow(k2).mute=yes swapped=true committed(live k2).mute=no
10-27 18:03:30.901  5126  5126 I flutter : [Q13] 18:03:30.901  104853ms VERDICT Q13B PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=yes live.vid=no keepAlive=holding afterWake.mute=no
10-27 18:03:54.181  5126  5126 I flutter : [Q13] 18:03:54.181  128133ms VERDICT Q13B PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=yes live.vid=no keepAlive=holding afterWake.mute=no
10-27 18:04:17.688  5126  5126 I flutter : [Q13] 18:04:17.688  151640ms VERDICT Q13B PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=yes live.vid=no keepAlive=holding afterWake.mute=no
10-27 18:04:41.313  5126  5126 I flutter : [Q13] 18:04:41.313  175265ms VERDICT Q13B PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=yes live.vid=no keepAlive=holding afterWake.mute=no
10-27 18:05:04.464  5126  5126 I flutter : [Q13] 18:05:04.464  198415ms VERDICT Q13B PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=yes live.vid=no keepAlive=holding afterWake.mute=no
10-27 18:05:20.910  5126  5126 I flutter : [Q13] 18:05:20.910  214862ms VERDICT Q13C PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=no shadow.mute after wake=yes
10-27 18:05:37.368  5126  5126 I flutter : [Q13] 18:05:37.368  231320ms VERDICT Q13C PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=no shadow.mute after wake=yes
10-27 18:05:53.593  5126  5126 I flutter : [Q13] 18:05:53.593  247545ms VERDICT Q13C PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=no shadow.mute after wake=yes
10-27 18:06:09.446  5126  5126 I flutter : [Q13] 18:06:09.446  263398ms VERDICT Q13C PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=no shadow.mute after wake=yes
10-27 18:06:23.903  5126  5126 I flutter : [Q13] 18:06:23.903  277854ms VERDICT Q13C PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=no shadow.mute after wake=yes
10-27 18:06:24.987  5126  5126 I flutter : [Q13] 18:06:24.987  278939ms SUMMARY Q13A pass=5 fail=0
10-27 18:06:24.988  5126  5126 I flutter : [Q13] 18:06:24.988  278939ms SUMMARY Q13B pass=5 fail=0
10-27 18:06:24.988  5126  5126 I flutter : [Q13] 18:06:24.988  278939ms SUMMARY Q13C pass=5 fail=0
10-27 18:06:24.988  5126  5126 I flutter : [Q13] 18:06:24.988  278940ms AUTORUN DONE
```

## 开始 rerun-batch11-review

- 复用 review 页面，核验事件与设备状态；多轮计时取平均。

## rerun-batch11-review 自动检查点

- 复用页运行；逐编号最终结论需结合下面原始断言复核。
- driver exit=0；`{"selector": "review|all|3", "completed": true, "lines": 12366, "pid": "8701"}`。
- 日志：`example/tool/coverage_evidence/rerun-batch11-review.log`；截图/系统读回/采样同前缀。
```text
10-27 18:06:30.949  8701  8701 I flutter : RFV2|1793095590949|START|group=all win=1080x2376 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:06:30.949  8701  8701 I flutter : RFV2|1793095590949|GROUP|begin v10
10-27 18:06:33.865  8701  8701 I flutter : RFV2|1793095593865|V10|run1 before: fs=true ori=auto video=640x360 epoch=0 win=2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 18:06:33.866  8701  8701 I flutter : RFV2|1793095593866|SAMPLE|V10_run1_before_swap
10-27 18:06:36.068  8701  8701 I flutter : RFV2|1793095596068|WIN|V10_run1_before_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 18:06:38.318  8701  8701 I flutter : RFV2|1793095598318|V10|run1 cutoverTo=true in 1048ms; successor fs=true ori=auto title=B epoch=1 landscape=true immersive=true
10-27 18:06:38.318  8701  8701 I flutter : RFV2|1793095598318|SAMPLE|V10_run1_after_swap
10-27 18:06:40.520  8701  8701 I flutter : RFV2|1793095600520|WIN|V10_run1_after_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 18:06:41.943  8701  8701 I flutter : RFV2|1793095601943|V10|run1 after dispose: landscape=true immersive=false
10-27 18:06:41.943  8701  8701 I flutter : RFV2|1793095601943|SAMPLE|V10_run1_after_dispose
10-27 18:06:44.146  8701  8701 I flutter : RFV2|1793095604146|WIN|V10_run1_after_dispose 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:06:44.148  8701  8701 I flutter : RFV2|1793095604147|RESULT|V10|run1|FAIL|preFsLandscapeImmersive=true cutoverTo=true successorFs=true landscapeAfterCutover=true immersiveAfterCutover=true restoredPortrait=false barsRestored=true
10-27 18:06:47.312  8701  8701 I flutter : RFV2|1793095607312|V10|run2 before: fs=true ori=auto video=640x360 epoch=0 win=2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 18:06:47.313  8701  8701 I flutter : RFV2|1793095607313|SAMPLE|V10_run2_before_swap
10-27 18:06:49.515  8701  8701 I flutter : RFV2|1793095609515|WIN|V10_run2_before_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 18:06:51.588  8701  8701 I flutter : RFV2|1793095611588|V10|run2 cutoverTo=true in 871ms; successor fs=true ori=auto title=B epoch=1 landscape=true immersive=true
10-27 18:06:51.588  8701  8701 I flutter : RFV2|1793095611588|SAMPLE|V10_run2_after_swap
10-27 18:06:53.792  8701  8701 I flutter : RFV2|1793095613792|WIN|V10_run2_after_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 18:06:55.221  8701  8701 I flutter : RFV2|1793095615221|V10|run2 after dispose: landscape=true immersive=false
10-27 18:06:55.222  8701  8701 I flutter : RFV2|1793095615222|SAMPLE|V10_run2_after_dispose
10-27 18:06:57.424  8701  8701 I flutter : RFV2|1793095617424|WIN|V10_run2_after_dispose 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:06:57.425  8701  8701 I flutter : RFV2|1793095617425|RESULT|V10|run2|FAIL|preFsLandscapeImmersive=true cutoverTo=true successorFs=true landscapeAfterCutover=true immersiveAfterCutover=true restoredPortrait=false barsRestored=true
10-27 18:07:00.890  8701  8701 I flutter : RFV2|1793095620890|V10|run3 before: fs=true ori=auto video=640x360 epoch=0 win=2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 18:07:00.890  8701  8701 I flutter : RFV2|1793095620890|SAMPLE|V10_run3_before_swap
10-27 18:07:03.092  8701  8701 I flutter : RFV2|1793095623092|WIN|V10_run3_before_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 18:07:05.195  8701  8701 I flutter : RFV2|1793095625195|V10|run3 cutoverTo=true in 901ms; successor fs=true ori=auto title=B epoch=1 landscape=true immersive=true
10-27 18:07:05.196  8701  8701 I flutter : RFV2|1793095625195|SAMPLE|V10_run3_after_swap
10-27 18:07:07.397  8701  8701 I flutter : RFV2|1793095627397|WIN|V10_run3_after_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 18:07:08.883  8701  8701 I flutter : RFV2|1793095628883|V10|run3 after dispose: landscape=true immersive=false
10-27 18:07:08.883  8701  8701 I flutter : RFV2|1793095628883|SAMPLE|V10_run3_after_dispose
10-27 18:07:11.086  8701  8701 I flutter : RFV2|1793095631085|WIN|V10_run3_after_dispose 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:07:11.087  8701  8701 I flutter : RFV2|1793095631087|RESULT|V10|run3|FAIL|preFsLandscapeImmersive=true cutoverTo=true successorFs=true landscapeAfterCutover=true immersiveAfterCutover=true restoredPortrait=false barsRestored=true
10-27 18:07:11.087  8701  8701 I flutter : RFV2|1793095631087|GROUP|end v10 uncaught=0
10-27 18:07:11.087  8701  8701 I flutter : RFV2|1793095631087|GROUP|begin v10x
10-27 18:07:14.585  8701  8701 I flutter : RFV2|1793095634585|V10x|run1 before: fs=true ori=auto video=640x360 epoch=0 win=2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 18:07:14.585  8701  8701 I flutter : RFV2|1793095634585|SAMPLE|V10x_run1_before_swap
10-27 18:07:16.787  8701  8701 I flutter : RFV2|1793095636787|WIN|V10x_run1_before_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 18:07:18.824  8701  8701 I flutter : RFV2|1793095638824|V10x|run1 cutoverTo=true in 835ms; successor fs=true ori=auto title=B epoch=1 landscape=true immersive=true
10-27 18:07:18.824  8701  8701 I flutter : RFV2|1793095638824|SAMPLE|V10x_run1_after_swap
10-27 18:07:21.025  8701  8701 I flutter : RFV2|1793095641025|WIN|V10x_run1_after_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 18:07:22.239  8701  8701 I flutter : RFV2|1793095642239|V10x|run1 after setFullscreen(false): fs=false landscape=true immersive=false
10-27 18:07:22.240  8701  8701 I flutter : RFV2|1793095642239|SAMPLE|V10x_run1_after_exit
10-27 18:07:24.441  8701  8701 I flutter : RFV2|1793095644441|WIN|V10x_run1_after_exit 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:07:24.706  8701  8701 I flutter : RFV2|1793095644706|RESULT|V10x|run1|FAIL|preFsLandscapeImmersive=true cutoverTo=true successorFs=true landscapeAfterCutover=true immersiveAfterCutover=true restoredPortrait=false barsRestored=true
10-27 18:07:28.036  8701  8701 I flutter : RFV2|1793095648036|V10x|run2 before: fs=true ori=auto video=640x360 epoch=0 win=2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 18:07:28.036  8701  8701 I flutter : RFV2|1793095648036|SAMPLE|V10x_run2_before_swap
10-27 18:07:30.242  8701  8701 I flutter : RFV2|1793095650242|WIN|V10x_run2_before_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 18:07:32.496  8701  8701 I flutter : RFV2|1793095652496|V10x|run2 cutoverTo=true in 1051ms; successor fs=true ori=auto title=B epoch=1 landscape=true immersive=true
10-27 18:07:32.496  8701  8701 I flutter : RFV2|1793095652496|SAMPLE|V10x_run2_after_swap
10-27 18:07:34.698  8701  8701 I flutter : RFV2|1793095654698|WIN|V10x_run2_after_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 18:07:35.910  8701  8701 I flutter : RFV2|1793095655910|V10x|run2 after setFullscreen(false): fs=false landscape=true immersive=false
10-27 18:07:35.910  8701  8701 I flutter : RFV2|1793095655910|SAMPLE|V10x_run2_after_exit
10-27 18:07:38.111  8701  8701 I flutter : RFV2|1793095658111|WIN|V10x_run2_after_exit 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:07:38.274  8701  8701 I flutter : RFV2|1793095658274|RESULT|V10x|run2|FAIL|preFsLandscapeImmersive=true cutoverTo=true successorFs=true landscapeAfterCutover=true immersiveAfterCutover=true restoredPortrait=false barsRestored=true
10-27 18:07:38.274  8701  8701 I flutter : RFV2|1793095658274|GROUP|end v10x uncaught=0
10-27 18:07:38.274  8701  8701 I flutter : RFV2|1793095658274|GROUP|begin v10c
10-27 18:07:41.632  8701  8701 I flutter : RFV2|1793095661632|V10c|run1 before plain dispose of E1: landscape=true immersive=true e2.fs=true
10-27 18:07:41.632  8701  8701 I flutter : RFV2|1793095661632|SAMPLE|V10c_run1_before
10-27 18:07:43.835  8701  8701 I flutter : RFV2|1793095663835|WIN|V10c_run1_before 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 18:07:45.120  8701  8701 I flutter : RFV2|1793095665120|V10c|run1 after plain dispose of E1: landscape=true immersive=false e2.fs=true
10-27 18:07:45.121  8701  8701 I flutter : RFV2|1793095665121|SAMPLE|V10c_run1_after_plain_dispose
10-27 18:07:47.324  8701  8701 I flutter : RFV2|1793095667324|WIN|V10c_run1_after_plain_dispose 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:07:47.325  8701  8701 I flutter : RFV2|1793095667325|RESULT|V10c|run1|PASS|baselineFsOk=true platformResetByPlainDispose=true (PASS 表示"确认旧引擎普通 dispose 会复位", 即退役标记确有必要)
10-27 18:07:51.523  8701  8701 I flutter : RFV2|1793095671523|V10c|run2 before plain dispose of E1: landscape=true immersive=true e2.fs=true
10-27 18:07:51.524  8701  8701 I flutter : RFV2|1793095671524|SAMPLE|V10c_run2_before
10-27 18:07:53.725  8701  8701 I flutter : RFV2|1793095673725|WIN|V10c_run2_before 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 18:07:55.026  8701  8701 I flutter : RFV2|1793095675025|V10c|run2 after plain dispose of E1: landscape=true immersive=false e2.fs=true
10-27 18:07:55.026  8701  8701 I flutter : RFV2|1793095675026|SAMPLE|V10c_run2_after_plain_dispose
10-27 18:07:57.227  8701  8701 I flutter : RFV2|1793095677227|WIN|V10c_run2_after_plain_dispose 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:07:57.227  8701  8701 I flutter : RFV2|1793095677227|RESULT|V10c|run2|PASS|baselineFsOk=true platformResetByPlainDispose=true (PASS 表示"确认旧引擎普通 dispose 会复位", 即退役标记确有必要)
10-27 18:07:58.300  8701  8701 I flutter : RFV2|1793095678300|GROUP|end v10c uncaught=0
10-27 18:07:58.301  8701  8701 I flutter : RFV2|1793095678300|GROUP|begin v11
10-27 18:08:01.677  8701  8701 I flutter : RFV2|1793095681677|V11|run1 before: fs=false ori=landscape landscape=true win=2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:08:01.677  8701  8701 I flutter : RFV2|1793095681677|SAMPLE|V11_run1_before_swap
10-27 18:08:03.878  8701  8701 I flutter : RFV2|1793095683878|WIN|V11_run1_before_swap 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:08:05.935  8701  8701 I flutter : RFV2|1793095685935|V11|run1 cutoverTo=true successor ori=landscape fs=false title=B landscape=true
10-27 18:08:05.935  8701  8701 I flutter : RFV2|1793095685935|SAMPLE|V11_run1_after_swap
10-27 18:08:08.138  8701  8701 I flutter : RFV2|1793095688138|WIN|V11_run1_after_swap 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:08:09.540  8701  8701 I flutter : RFV2|1793095689540|V11|run1 after dispose: landscape=true
10-27 18:08:09.541  8701  8701 I flutter : RFV2|1793095689540|SAMPLE|V11_run1_after_dispose
10-27 18:08:11.743  8701  8701 I flutter : RFV2|1793095691743|WIN|V11_run1_after_dispose 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:08:11.745  8701  8701 I flutter : RFV2|1793095691745|RESULT|V11|run1|FAIL|preLandscape=true cutoverTo=true successorOrientation=landscape landscapeAfterCutover=true restoredPortrait=false
10-27 18:08:15.205  8701  8701 I flutter : RFV2|1793095695205|V11|run2 before: fs=false ori=landscape landscape=true win=2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:08:15.205  8701  8701 I flutter : RFV2|1793095695205|SAMPLE|V11_run2_before_swap
10-27 18:08:17.408  8701  8701 I flutter : RFV2|1793095697408|WIN|V11_run2_before_swap 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:08:19.489  8701  8701 I flutter : RFV2|1793095699489|V11|run2 cutoverTo=true successor ori=landscape fs=false title=B landscape=true
10-27 18:08:19.489  8701  8701 I flutter : RFV2|1793095699489|SAMPLE|V11_run2_after_swap
10-27 18:08:21.690  8701  8701 I flutter : RFV2|1793095701690|WIN|V11_run2_after_swap 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:08:23.164  8701  8701 I flutter : RFV2|1793095703164|V11|run2 after dispose: landscape=true
10-27 18:08:23.165  8701  8701 I flutter : RFV2|1793095703164|SAMPLE|V11_run2_after_dispose
10-27 18:08:25.368  8701  8701 I flutter : RFV2|1793095705367|WIN|V11_run2_after_dispose 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:08:25.369  8701  8701 I flutter : RFV2|1793095705369|RESULT|V11|run2|FAIL|preLandscape=true cutoverTo=true successorOrientation=landscape landscapeAfterCutover=true restoredPortrait=false
10-27 18:08:28.474  8701  8701 I flutter : RFV2|1793095708474|V11|run3 before: fs=false ori=landscape landscape=true win=2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:08:28.474  8701  8701 I flutter : RFV2|1793095708474|SAMPLE|V11_run3_before_swap
10-27 18:08:30.675  8701  8701 I flutter : RFV2|1793095710675|WIN|V11_run3_before_swap 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:08:32.763  8701  8701 I flutter : RFV2|1793095712763|V11|run3 cutoverTo=true successor ori=landscape fs=false title=B landscape=true
10-27 18:08:32.764  8701  8701 I flutter : RFV2|1793095712764|SAMPLE|V11_run3_after_swap
10-27 18:08:34.965  8701  8701 I flutter : RFV2|1793095714965|WIN|V11_run3_after_swap 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:08:36.363  8701  8701 I flutter : RFV2|1793095716363|V11|run3 after dispose: landscape=true
10-27 18:08:36.364  8701  8701 I flutter : RFV2|1793095716364|SAMPLE|V11_run3_after_dispose
10-27 18:08:38.566  8701  8701 I flutter : RFV2|1793095718566|WIN|V11_run3_after_dispose 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 18:08:38.567  8701  8701 I flutter : RFV2|1793095718567|RESULT|V11|run3|FAIL|preLandscape=true cutoverTo=true successorOrientation=landscape landscapeAfterCutover=true restoredPortrait=false
10-27 18:08:38.567  8701  8701 I flutter : RFV2|1793095718567|GROUP|end v11 uncaught=0
10-27 18:08:38.567  8701  8701 I flutter : RFV2|1793095718567|GROUP|begin v12
10-27 18:08:38.713  8701  8701 I flutter : RFV2|1793095718713|V12|run1 st title=C epoch=0 rendered=false playing=true buffering=true phase=idle
10-27 18:08:39.390  8701  8701 I flutter : RFV2|1793095719390|V12|run1 st title=C epoch=0 rendered=true playing=true buffering=false phase=idle
10-27 18:08:42.622  8701  8701 I flutter : RFV2|1793095722621|V12|run1 adEvent pending:AD1
10-27 18:08:42.717  8701  8701 I flutter : RFV2|1793095722717|V12|run1 cutoverPhase=warming
10-27 18:08:42.813  8701  8701 I flutter : RFV2|1793095722813|V12|run1 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 18:08:43.650  8701  8701 I flutter : RFV2|1793095723650|V12|run1 cutoverPhase=ready
10-27 18:08:43.668  8701  8701 I flutter : RFV2|1793095723668|V12|run1 adEvent started:AD1
10-27 18:08:43.668  8701  8701 I flutter : RFV2|1793095723668|V12|run1 cutoverPhase=idle
10-27 18:08:43.713  8701  8701 I flutter : RFV2|1793095723713|V12|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 18:08:43.780  8701  8701 I flutter : RFV2|1793095723780|V12|run1 cutoverPhase=warming
10-27 18:08:43.813  8701  8701 I flutter : RFV2|1793095723813|V12|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 18:08:47.670  8701  8701 I flutter : RFV2|1793095727670|V12|run1 adEvent completed:AD1
10-27 18:08:47.670  8701  8701 I flutter : RFV2|1793095727670|V12|run1 adEvent started:AD2
10-27 18:08:47.696  8701  8701 I flutter : RFV2|1793095727696|V12|run1 cutoverPhase=idle
10-27 18:08:47.716  8701  8701 I flutter : RFV2|1793095727716|V12|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 18:08:47.817  8701  8701 I flutter : RFV2|1793095727817|V12|run1 cutoverPhase=warming
10-27 18:08:47.913  8701  8701 I flutter : RFV2|1793095727913|V12|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 18:08:48.572  8701  8701 I flutter : RFV2|1793095728572|V12|run1 cutoverPhase=ready
10-27 18:08:48.577  8701  8701 I flutter : RFV2|1793095728577|V12|run1 cutoverPhase=idle
10-27 18:08:48.631  8701  8701 I flutter : RFV2|1793095728631|V12|run1 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=idle
10-27 18:08:48.745  8701  8701 I flutter : RFV2|1793095728745|V12|run1 cutoverPhase=warming
10-27 18:08:48.814  8701  8701 I flutter : RFV2|1793095728814|V12|run1 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=warming
10-27 18:08:53.298  8701  8701 I flutter : RFV2|1793095733298|V12|run1 cutoverPhase=ready
10-27 18:08:53.316  8701  8701 I flutter : RFV2|1793095733316|V12|run1 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=ready
10-27 18:08:54.581  8701  8701 I flutter : RFV2|1793095734581|V12|run1 adEvent completed:AD2
10-27 18:08:54.616  8701  8701 I flutter : RFV2|1793095734616|V12|run1 st title=AD2 epoch=2 rendered=true playing=false buffering=false phase=ready
10-27 18:08:54.617  8701  8701 I flutter : RFV2|1793095734617|V12|run1 cutoverPhase=idle
10-27 18:08:54.713  8701  8701 I flutter : RFV2|1793095734713|V12|run1 st title=C epoch=3 rendered=true playing=true buffering=false phase=idle
10-27 18:08:57.091  8701  8701 I flutter : RFV2|1793095737091|V12|run1 epochs=3 epochRelToAD2Started=[-3965, 934, 6966] AD2 started->epochChange=934ms started->completed=6911ms adFirstFrame->completed=5977ms oldTicksInWindow=3 failed=0([])
10-27 18:08:57.091  8701  8701 I flutter : RFV2|1793095737091|RESULT|V12|run1|PASS|failed=0 AD2completed=true adFirstFrame->completed=5977ms (cfg 6000) started->completed=6911ms started->epochChange=934ms oldTicksBeforeEpoch=3
10-27 18:08:57.473  8701  8701 I flutter : RFV2|1793095737472|V12|run2 st title=C epoch=0 rendered=false playing=true buffering=true phase=idle
10-27 18:08:57.841  8701  8701 I flutter : RFV2|1793095737841|V12|run2 st title=C epoch=0 rendered=true playing=true buffering=false phase=idle
10-27 18:09:01.449  8701  8701 I flutter : RFV2|1793095741449|V12|run2 adEvent pending:AD1
10-27 18:09:01.539  8701  8701 I flutter : RFV2|1793095741539|V12|run2 cutoverPhase=warming
10-27 18:09:01.570  8701  8701 I flutter : RFV2|1793095741570|V12|run2 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 18:09:02.433  8701  8701 I flutter : RFV2|1793095742433|V12|run2 cutoverPhase=ready
10-27 18:09:02.441  8701  8701 I flutter : RFV2|1793095742441|V12|run2 adEvent started:AD1
10-27 18:09:02.441  8701  8701 I flutter : RFV2|1793095742441|V12|run2 cutoverPhase=idle
10-27 18:09:02.482  8701  8701 I flutter : RFV2|1793095742482|V12|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 18:09:02.598  8701  8701 I flutter : RFV2|1793095742598|V12|run2 cutoverPhase=warming
10-27 18:09:02.670  8701  8701 I flutter : RFV2|1793095742670|V12|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 18:09:03.469  8701  8701 I flutter : RFV2|1793095743469|V12|run2 cutoverPhase=ready
10-27 18:09:03.470  8701  8701 I flutter : RFV2|1793095743470|V12|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=ready
10-27 18:09:06.448  8701  8701 I flutter : RFV2|1793095746448|V12|run2 adEvent completed:AD1
10-27 18:09:06.449  8701  8701 I flutter : RFV2|1793095746449|V12|run2 adEvent started:AD2
10-27 18:09:06.484  8701  8701 I flutter : RFV2|1793095746484|V12|run2 cutoverPhase=idle
10-27 18:09:06.487  8701  8701 I flutter : RFV2|1793095746487|V12|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 18:09:06.612  8701  8701 I flutter : RFV2|1793095746612|V12|run2 cutoverPhase=warming
10-27 18:09:06.676  8701  8701 I flutter : RFV2|1793095746676|V12|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 18:09:07.425  8701  8701 I flutter : RFV2|1793095747424|V12|run2 cutoverPhase=ready
10-27 18:09:07.436  8701  8701 I flutter : RFV2|1793095747436|V12|run2 cutoverPhase=idle
10-27 18:09:07.473  8701  8701 I flutter : RFV2|1793095747473|V12|run2 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=idle
10-27 18:09:07.622  8701  8701 I flutter : RFV2|1793095747622|V12|run2 cutoverPhase=warming
10-27 18:09:07.670  8701  8701 I flutter : RFV2|1793095747670|V12|run2 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=warming
10-27 18:09:08.530  8701  8701 I flutter : RFV2|1793095748530|V12|run2 cutoverPhase=ready
10-27 18:09:08.570  8701  8701 I flutter : RFV2|1793095748570|V12|run2 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=ready
10-27 18:09:13.438  8701  8701 I flutter : RFV2|1793095753438|V12|run2 adEvent completed:AD2
10-27 18:09:13.482  8701  8701 I flutter : RFV2|1793095753482|V12|run2 st title=AD2 epoch=2 rendered=true playing=false buffering=false phase=ready
10-27 18:09:13.483  8701  8701 I flutter : RFV2|1793095753483|V12|run2 cutoverPhase=idle
10-27 18:09:13.570  8701  8701 I flutter : RFV2|1793095753570|V12|run2 st title=C epoch=3 rendered=true playing=true buffering=false phase=idle
10-27 18:09:15.984  8701  8701 I flutter : RFV2|1793095755984|V12|run2 epochs=3 epochRelToAD2Started=[-3988, 1024, 7048] AD2 started->epochChange=1024ms started->completed=6989ms adFirstFrame->completed=5965ms oldTicksInWindow=4 failed=0([])
10-27 18:09:15.984  8701  8701 I flutter : RFV2|1793095755984|RESULT|V12|run2|PASS|failed=0 AD2completed=true adFirstFrame->completed=5965ms (cfg 6000) started->completed=6989ms started->epochChange=1024ms oldTicksBeforeEpoch=4
10-27 18:09:16.339  8701  8701 I flutter : RFV2|1793095756339|V12|run3 st title=C epoch=0 rendered=false playing=true buffering=true phase=idle
10-27 18:09:16.566  8701  8701 I flutter : RFV2|1793095756566|V12|run3 st title=C epoch=0 rendered=true playing=true buffering=false phase=idle
10-27 18:09:20.145  8701  8701 I flutter : RFV2|1793095760145|V12|run3 adEvent pending:AD1
10-27 18:09:20.232  8701  8701 I flutter : RFV2|1793095760232|V12|run3 cutoverPhase=warming
10-27 18:09:20.245  8701  8701 I flutter : RFV2|1793095760245|V12|run3 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 18:09:21.120  8701  8701 I flutter : RFV2|1793095761120|V12|run3 cutoverPhase=ready
10-27 18:09:21.138  8701  8701 I flutter : RFV2|1793095761138|V12|run3 adEvent started:AD1
10-27 18:09:21.138  8701  8701 I flutter : RFV2|1793095761138|V12|run3 cutoverPhase=idle
10-27 18:09:21.139  8701  8701 I flutter : RFV2|1793095761139|V12|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 18:09:21.295  8701  8701 I flutter : RFV2|1793095761295|V12|run3 cutoverPhase=warming
10-27 18:09:21.339  8701  8701 I flutter : RFV2|1793095761339|V12|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 18:09:25.139  8701  8701 I flutter : RFV2|1793095765139|V12|run3 adEvent completed:AD1
10-27 18:09:25.139  8701  8701 I flutter : RFV2|1793095765139|V12|run3 adEvent started:AD2
10-27 18:09:25.165  8701  8701 I flutter : RFV2|1793095765165|V12|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 18:09:25.166  8701  8701 I flutter : RFV2|1793095765166|V12|run3 cutoverPhase=idle
10-27 18:09:25.245  8701  8701 I flutter : RFV2|1793095765244|V12|run3 cutoverPhase=warming
10-27 18:09:25.339  8701  8701 I flutter : RFV2|1793095765339|V12|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 18:09:26.230  8701  8701 I flutter : RFV2|1793095766230|V12|run3 cutoverPhase=ready
10-27 18:09:26.235  8701  8701 I flutter : RFV2|1793095766235|V12|run3 cutoverPhase=idle
10-27 18:09:26.265  8701  8701 I flutter : RFV2|1793095766265|V12|run3 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=idle
10-27 18:09:26.444  8701  8701 I flutter : RFV2|1793095766444|V12|run3 cutoverPhase=warming
10-27 18:09:26.540  8701  8701 I flutter : RFV2|1793095766539|V12|run3 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=warming
10-27 18:09:27.699  8701  8701 I flutter : RFV2|1793095767699|V12|run3 cutoverPhase=ready
10-27 18:09:27.739  8701  8701 I flutter : RFV2|1793095767739|V12|run3 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=ready
10-27 18:09:32.237  8701  8701 I flutter : RFV2|1793095772237|V12|run3 adEvent completed:AD2
10-27 18:09:32.243  8701  8701 I flutter : RFV2|1793095772243|V12|run3 st title=AD2 epoch=2 rendered=true playing=false buffering=false phase=ready
10-27 18:09:32.249  8701  8701 I flutter : RFV2|1793095772249|V12|run3 cutoverPhase=idle
10-27 18:09:32.343  8701  8701 I flutter : RFV2|1793095772343|V12|run3 st title=C epoch=3 rendered=true playing=true buffering=false phase=idle
10-27 18:09:34.779  8701  8701 I flutter : RFV2|1793095774779|V12|run3 epochs=3 epochRelToAD2Started=[-4000, 1126, 7139] AD2 started->epochChange=1126ms started->completed=7098ms adFirstFrame->completed=5972ms oldTicksInWindow=4 failed=0([])
10-27 18:09:34.780  8701  8701 I flutter : RFV2|1793095774780|RESULT|V12|run3|PASS|failed=0 AD2completed=true adFirstFrame->completed=5972ms (cfg 6000) started->completed=7098ms started->epochChange=1126ms oldTicksBeforeEpoch=4
10-27 18:09:35.015  8701  8701 I flutter : RFV2|1793095775015|GROUP|end v12 uncaught=0
10-27 18:09:35.015  8701  8701 I flutter : RFV2|1793095775015|GROUP|begin v12b
10-27 18:09:35.139  8701  8701 I flutter : RFV2|1793095775139|V12b|run1 st title=C epoch=0 rendered=false playing=true buffering=true phase=idle
10-27 18:09:35.572  8701  8701 I flutter : RFV2|1793095775572|V12b|run1 st title=C epoch=0 rendered=true playing=true buffering=false phase=idle
10-27 18:09:39.112  8701  8701 I flutter : RFV2|1793095779112|V12b|run1 adEvent pending:AD1
10-27 18:09:39.203  8701  8701 I flutter : RFV2|1793095779203|V12b|run1 cutoverPhase=warming
10-27 18:09:39.232  8701  8701 I flutter : RFV2|1793095779232|V12b|run1 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 18:09:40.135  8701  8701 I flutter : RFV2|1793095780135|V12b|run1 cutoverPhase=ready
10-27 18:09:40.149  8701  8701 I flutter : RFV2|1793095780149|V12b|run1 st title=C epoch=0 rendered=true playing=true buffering=false phase=ready
10-27 18:09:40.297  8701  8701 I flutter : RFV2|1793095780296|V12b|run1 cutoverPhase=warming
10-27 18:09:40.339  8701  8701 I flutter : RFV2|1793095780339|V12b|run1 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 18:09:41.647  8701  8701 I flutter : RFV2|1793095781647|V12b|run1 adEvent started:AD1
10-27 18:09:41.647  8701  8701 I flutter : RFV2|1793095781647|V12b|run1 cutoverPhase=idle
10-27 18:09:41.737  8701  8701 I flutter : RFV2|1793095781737|V12b|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 18:09:41.903  8701  8701 I flutter : RFV2|1793095781903|V12b|run1 cutoverPhase=warming
10-27 18:09:41.933  8701  8701 I flutter : RFV2|1793095781933|V12b|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 18:09:45.648  8701  8701 I flutter : RFV2|1793095785648|V12b|run1 adEvent completed:AD1
10-27 18:09:45.648  8701  8701 I flutter : RFV2|1793095785648|V12b|run1 adEvent started:AD2
10-27 18:09:45.672  8701  8701 I flutter : RFV2|1793095785672|V12b|run1 cutoverPhase=idle
10-27 18:09:45.733  8701  8701 I flutter : RFV2|1793095785733|V12b|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 18:09:45.813  8701  8701 I flutter : RFV2|1793095785813|V12b|run1 cutoverPhase=warming
10-27 18:09:45.833  8701  8701 I flutter : RFV2|1793095785833|V12b|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 18:09:46.635  8701  8701 I flutter : RFV2|1793095786635|V12b|run1 cutoverPhase=ready
10-27 18:09:46.759  8701  8701 I flutter : RFV2|1793095786759|V12b|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=ready
10-27 18:09:48.149  8701  8701 I flutter : RFV2|1793095788149|V12b|run1 cutoverPhase=idle
10-27 18:09:48.233  8701  8701 I flutter : RFV2|1793095788233|V12b|run1 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=idle
10-27 18:09:48.359  8701  8701 I flutter : RFV2|1793095788358|V12b|run1 cutoverPhase=warming
10-27 18:09:48.433  8701  8701 I flutter : RFV2|1793095788433|V12b|run1 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=warming
10-27 18:09:49.828  8701  8701 I flutter : RFV2|1793095789828|V12b|run1 cutoverPhase=ready
10-27 18:09:49.845  8701  8701 I flutter : RFV2|1793095789845|V12b|run1 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=ready
10-27 18:09:54.152  8701  8701 I flutter : RFV2|1793095794152|V12b|run1 adEvent completed:AD2
10-27 18:09:55.686  8701  8701 I flutter : RFV2|1793095795686|V12b|run1 cutoverPhase=idle
10-27 18:09:55.734  8701  8701 I flutter : RFV2|1793095795734|V12b|run1 st title=C epoch=3 rendered=true playing=true buffering=false phase=idle
10-27 18:09:56.675  8701  8701 I flutter : RFV2|1793095796675|V12b|run1 epochs=3 epochRelToAD2Started=[-3996, 2507, 10054] AD2 started->epochChange=2507ms started->completed=8504ms adFirstFrame->completed=5997ms oldTicksInWindow=11 failed=0([])
10-27 18:09:56.675  8701  8701 I flutter : RFV2|1793095796675|RESULT|V12b|run1|PASS|failed=0 AD2completed=true adFirstFrame->completed=5997ms (cfg 6000) started->completed=8504ms started->epochChange=2507ms oldTicksBeforeEpoch=11
10-27 18:09:57.046  8701  8701 I flutter : RFV2|1793095797046|V12b|run2 st title=C epoch=0 rendered=false playing=true buffering=true phase=idle
10-27 18:09:57.396  8701  8701 I flutter : RFV2|1793095797396|V12b|run2 st title=C epoch=0 rendered=true playing=true buffering=false phase=idle
10-27 18:09:57.850  8701  8701 I flutter : RFV2|1793095797850|V12b|run2 st title=C epoch=0 rendered=true playing=true buffering=true phase=idle
10-27 18:09:58.044  8701  8701 I flutter : RFV2|1793095798043|V12b|run2 st title=C epoch=0 rendered=true playing=true buffering=false phase=idle
10-27 18:10:01.135  8701  8701 I flutter : RFV2|1793095801135|V12b|run2 adEvent pending:AD1
10-27 18:10:01.225  8701  8701 I flutter : RFV2|1793095801225|V12b|run2 cutoverPhase=warming
10-27 18:10:01.244  8701  8701 I flutter : RFV2|1793095801244|V12b|run2 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 18:10:02.202  8701  8701 I flutter : RFV2|1793095802202|V12b|run2 cutoverPhase=ready
10-27 18:10:02.244  8701  8701 I flutter : RFV2|1793095802244|V12b|run2 st title=C epoch=0 rendered=true playing=true buffering=false phase=ready
10-27 18:10:02.336  8701  8701 I flutter : RFV2|1793095802336|V12b|run2 cutoverPhase=warming
10-27 18:10:02.343  8701  8701 I flutter : RFV2|1793095802343|V12b|run2 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 18:10:03.192  8701  8701 I flutter : RFV2|1793095803192|V12b|run2 cutoverPhase=ready
10-27 18:10:03.247  8701  8701 I flutter : RFV2|1793095803247|V12b|run2 st title=C epoch=0 rendered=true playing=true buffering=false phase=ready
10-27 18:10:03.744  8701  8701 I flutter : RFV2|1793095803744|V12b|run2 st title=C epoch=0 rendered=true playing=false buffering=false phase=ready
10-27 18:10:04.720  8701  8701 I flutter : RFV2|1793095804720|V12b|run2 adEvent started:AD1
10-27 18:10:04.720  8701  8701 I flutter : RFV2|1793095804720|V12b|run2 cutoverPhase=idle
10-27 18:10:04.745  8701  8701 I flutter : RFV2|1793095804745|V12b|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 18:10:04.813  8701  8701 I flutter : RFV2|1793095804813|V12b|run2 cutoverPhase=warming
10-27 18:10:04.846  8701  8701 I flutter : RFV2|1793095804846|V12b|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 18:10:06.072  8701  8701 I flutter : RFV2|1793095806072|V12b|run2 cutoverPhase=ready
10-27 18:10:06.144  8701  8701 I flutter : RFV2|1793095806144|V12b|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=ready
10-27 18:10:08.721  8701  8701 I flutter : RFV2|1793095808721|V12b|run2 adEvent completed:AD1
10-27 18:10:08.722  8701  8701 I flutter : RFV2|1793095808722|V12b|run2 adEvent started:AD2
10-27 18:10:08.756  8701  8701 I flutter : RFV2|1793095808756|V12b|run2 cutoverPhase=idle
10-27 18:10:08.759  8701  8701 I flutter : RFV2|1793095808759|V12b|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 18:10:08.864  8701  8701 I flutter : RFV2|1793095808864|V12b|run2 cutoverPhase=warming
10-27 18:10:08.944  8701  8701 I flutter : RFV2|1793095808944|V12b|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 18:10:09.644  8701  8701 I flutter : RFV2|1793095809644|V12b|run2 cutoverPhase=ready
10-27 18:10:09.767  8701  8701 I flutter : RFV2|1793095809767|V12b|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=ready
10-27 18:10:11.153  8701  8701 I flutter : RFV2|1793095811153|V12b|run2 cutoverPhase=idle
10-27 18:10:11.249  8701  8701 I flutter : RFV2|1793095811249|V12b|run2 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=idle
10-27 18:10:11.354  8701  8701 I flutter : RFV2|1793095811354|V12b|run2 cutoverPhase=warming
10-27 18:10:11.444  8701  8701 I flutter : RFV2|1793095811444|V12b|run2 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=warming
10-27 18:10:12.258  8701  8701 I flutter : RFV2|1793095812258|V12b|run2 cutoverPhase=ready
10-27 18:10:12.344  8701  8701 I flutter : RFV2|1793095812344|V12b|run2 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=ready
10-27 18:10:17.154  8701  8701 I flutter : RFV2|1793095817154|V12b|run2 adEvent completed:AD2
10-27 18:10:18.699  8701  8701 I flutter : RFV2|1793095818698|V12b|run2 cutoverPhase=idle
10-27 18:10:18.745  8701  8701 I flutter : RFV2|1793095818745|V12b|run2 st title=C epoch=3 rendered=true playing=true buffering=false phase=idle
10-27 18:10:19.689  8701  8701 I flutter : RFV2|1793095819689|V12b|run2 epochs=3 epochRelToAD2Started=[-3996, 2472, 9982] AD2 started->epochChange=2472ms started->completed=8432ms adFirstFrame->completed=5960ms oldTicksInWindow=11 failed=0([])
10-27 18:10:19.690  8701  8701 I flutter : RFV2|1793095819689|RESULT|V12b|run2|PASS|failed=0 AD2completed=true adFirstFrame->completed=5960ms (cfg 6000) started->completed=8432ms started->epochChange=2472ms oldTicksBeforeEpoch=11
10-27 18:10:20.044  8701  8701 I flutter : RFV2|1793095820044|V12b|run3 st title=C epoch=0 rendered=false playing=true buffering=true phase=idle
10-27 18:10:20.493  8701  8701 I flutter : RFV2|1793095820493|V12b|run3 st title=C epoch=0 rendered=true playing=true buffering=false phase=idle
10-27 18:10:20.945  8701  8701 I flutter : RFV2|1793095820945|V12b|run3 st title=C epoch=0 rendered=true playing=true buffering=true phase=idle
10-27 18:10:21.046  8701  8701 I flutter : RFV2|1793095821046|V12b|run3 st title=C epoch=0 rendered=true playing=true buffering=false phase=idle
10-27 18:10:24.045  8701  8701 I flutter : RFV2|1793095824045|V12b|run3 adEvent pending:AD1
10-27 18:10:24.137  8701  8701 I flutter : RFV2|1793095824137|V12b|run3 cutoverPhase=warming
10-27 18:10:24.150  8701  8701 I flutter : RFV2|1793095824149|V12b|run3 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 18:10:25.248  8701  8701 I flutter : RFV2|1793095825248|V12b|run3 cutoverPhase=ready
10-27 18:10:25.361  8701  8701 I flutter : RFV2|1793095825361|V12b|run3 st title=C epoch=0 rendered=true playing=true buffering=false phase=ready
10-27 18:10:25.405  8701  8701 I flutter : RFV2|1793095825405|V12b|run3 cutoverPhase=warming
10-27 18:10:25.444  8701  8701 I flutter : RFV2|1793095825444|V12b|run3 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 18:10:26.681  8701  8701 I flutter : RFV2|1793095826681|V12b|run3 cutoverPhase=ready
10-27 18:10:26.744  8701  8701 I flutter : RFV2|1793095826744|V12b|run3 st title=C epoch=0 rendered=true playing=true buffering=false phase=ready
10-27 18:10:26.844  8701  8701 I flutter : RFV2|1793095826844|V12b|run3 st title=C epoch=0 rendered=true playing=false buffering=false phase=ready
10-27 18:10:28.217  8701  8701 I flutter : RFV2|1793095828217|V12b|run3 adEvent started:AD1
10-27 18:10:28.217  8701  8701 I flutter : RFV2|1793095828217|V12b|run3 cutoverPhase=idle
10-27 18:10:28.248  8701  8701 I flutter : RFV2|1793095828248|V12b|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 18:10:28.368  8701  8701 I flutter : RFV2|1793095828368|V12b|run3 cutoverPhase=warming
10-27 18:10:28.444  8701  8701 I flutter : RFV2|1793095828444|V12b|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 18:10:32.218  8701  8701 I flutter : RFV2|1793095832218|V12b|run3 adEvent completed:AD1
10-27 18:10:32.219  8701  8701 I flutter : RFV2|1793095832219|V12b|run3 adEvent started:AD2
10-27 18:10:32.252  8701  8701 I flutter : RFV2|1793095832252|V12b|run3 cutoverPhase=idle
10-27 18:10:32.256  8701  8701 I flutter : RFV2|1793095832256|V12b|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 18:10:32.372  8701  8701 I flutter : RFV2|1793095832372|V12b|run3 cutoverPhase=warming
10-27 18:10:32.444  8701  8701 I flutter : RFV2|1793095832444|V12b|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 18:10:34.242  8701  8701 I flutter : RFV2|1793095834242|V12b|run3 cutoverPhase=ready
10-27 18:10:34.244  8701  8701 I flutter : RFV2|1793095834244|V12b|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=ready
10-27 18:10:35.747  8701  8701 I flutter : RFV2|1793095835747|V12b|run3 st title=AD1 epoch=1 rendered=true playing=false buffering=false phase=ready
10-27 18:10:35.795  8701  8701 I flutter : RFV2|1793095835795|V12b|run3 cutoverPhase=idle
10-27 18:10:35.844  8701  8701 I flutter : RFV2|1793095835844|V12b|run3 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=idle
10-27 18:10:35.934  8701  8701 I flutter : RFV2|1793095835934|V12b|run3 cutoverPhase=warming
10-27 18:10:35.944  8701  8701 I flutter : RFV2|1793095835944|V12b|run3 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=warming
10-27 18:10:41.796  8701  8701 I flutter : RFV2|1793095841796|V12b|run3 adEvent completed:AD2
10-27 18:10:42.712  8701  8701 I flutter : RFV2|1793095842712|V12b|run3 cutoverPhase=ready
10-27 18:10:42.744  8701  8701 I flutter : RFV2|1793095842744|V12b|run3 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=ready
10-27 18:10:44.243  8701  8701 I flutter : RFV2|1793095844243|V12b|run3 cutoverPhase=idle
10-27 18:10:44.245  8701  8701 I flutter : RFV2|1793095844244|V12b|run3 st title=C epoch=3 rendered=true playing=true buffering=false phase=idle
10-27 18:10:44.318  8701  8701 I flutter : RFV2|1793095844318|V12b|run3 epochs=3 epochRelToAD2Started=[-3989, 3596, 12026] AD2 started->epochChange=3596ms started->completed=9577ms adFirstFrame->completed=5981ms oldTicksInWindow=17 failed=0([])
10-27 18:10:44.318  8701  8701 I flutter : RFV2|1793095844318|RESULT|V12b|run3|PASS|failed=0 AD2completed=true adFirstFrame->completed=5981ms (cfg 6000) started->completed=9577ms started->epochChange=3596ms oldTicksBeforeEpoch=17
10-27 18:10:44.570  8701  8701 I flutter : RFV2|1793095844569|GROUP|end v12b uncaught=0
10-27 18:10:44.570  8701  8701 I flutter : RFV2|1793095844570|GROUP|begin v13a
10-27 18:10:44.687  8701  8701 I flutter : RFV2|1793095844687|V13a|run1 state rate=1.0 title=C epoch=0
10-27 18:10:46.588  8701  8701 I flutter : RFV2|1793095846588|V13a|run1 setRate(2.0) -> state.rate=1.0
10-27 18:10:46.687  8701  8701 I flutter : RFV2|1793095846687|V13a|run1 state rate=2.0 title=C epoch=0
10-27 18:10:49.449  8701  8701 I flutter : RFV2|1793095849449|V13a|run1 adEvent pending
10-27 18:10:50.505  8701  8701 I flutter : RFV2|1793095850505|V13a|run1 adEvent started
10-27 18:10:50.587  8701  8701 I flutter : RFV2|1793095850587|V13a|run1 state rate=1.0 title=AD epoch=1
10-27 18:10:55.508  8701  8701 I flutter : RFV2|1793095855508|V13a|run1 adEvent completed
10-27 18:10:58.596  8701  8701 I flutter : RFV2|1793095858596|V13a|run1 state rate=1.0 title=C epoch=1
10-27 18:10:58.787  8701  8701 I flutter : RFV2|1793095858787|V13a|run1 state rate=2.0 title=C epoch=1
10-27 18:11:02.194  8701  8701 I flutter : RFV2|1793095862194|V13a|run1 completedAt=1793095855508 adRateSamples=48 adMaxRate=1.0 adSettled1x=true backRate=2.0 title=C
10-27 18:11:02.194  8701  8701 I flutter : RFV2|1793095862194|RESULT|V13a|run1|PASS|adRate settled1x=true (max seen 1.0x over 48 samples) rateAfterReturn=2.0 want=2.0
10-27 18:11:02.498  8701  8701 I flutter : RFV2|1793095862498|V13a|run2 state rate=1.0 title=C epoch=0
10-27 18:11:04.403  8701  8701 I flutter : RFV2|1793095864403|V13a|run2 setRate(2.0) -> state.rate=1.0
10-27 18:11:04.499  8701  8701 I flutter : RFV2|1793095864498|V13a|run2 state rate=2.0 title=C epoch=0
10-27 18:11:07.257  8701  8701 I flutter : RFV2|1793095867257|V13a|run2 adEvent pending
10-27 18:11:08.443  8701  8701 I flutter : RFV2|1793095868443|V13a|run2 adEvent started
10-27 18:11:08.508  8701  8701 I flutter : RFV2|1793095868508|V13a|run2 state rate=1.0 title=AD epoch=1
10-27 18:11:13.447  8701  8701 I flutter : RFV2|1793095873447|V13a|run2 adEvent completed
10-27 18:11:13.517  8701  8701 I flutter : RFV2|1793095873517|V13a|run2 state rate=2.0 title=C epoch=2
10-27 18:11:16.540  8701  8701 I flutter : RFV2|1793095876540|V13a|run2 completedAt=1793095873447 adRateSamples=47 adMaxRate=1.0 adSettled1x=true backRate=2.0 title=C
10-27 18:11:16.541  8701  8701 I flutter : RFV2|1793095876541|RESULT|V13a|run2|PASS|adRate settled1x=true (max seen 1.0x over 47 samples) rateAfterReturn=2.0 want=2.0
10-27 18:11:16.909  8701  8701 I flutter : RFV2|1793095876909|V13a|run3 state rate=1.0 title=C epoch=0
10-27 18:11:18.576  8701  8701 I flutter : RFV2|1793095878576|V13a|run3 setRate(2.0) -> state.rate=1.0
10-27 18:11:18.614  8701  8701 I flutter : RFV2|1793095878613|V13a|run3 state rate=2.0 title=C epoch=0
10-27 18:11:21.440  8701  8701 I flutter : RFV2|1793095881440|V13a|run3 adEvent pending
10-27 18:11:22.398  8701  8701 I flutter : RFV2|1793095882398|V13a|run3 adEvent started
10-27 18:11:22.437  8701  8701 I flutter : RFV2|1793095882437|V13a|run3 state rate=1.0 title=AD epoch=1
10-27 18:11:27.400  8701  8701 I flutter : RFV2|1793095887400|V13a|run3 adEvent completed
10-27 18:11:27.514  8701  8701 I flutter : RFV2|1793095887514|V13a|run3 state rate=2.0 title=C epoch=2
10-27 18:11:30.512  8701  8701 I flutter : RFV2|1793095890512|V13a|run3 completedAt=1793095887400 adRateSamples=48 adMaxRate=1.0 adSettled1x=true backRate=2.0 title=C
10-27 18:11:30.513  8701  8701 I flutter : RFV2|1793095890512|RESULT|V13a|run3|PASS|adRate settled1x=true (max seen 1.0x over 48 samples) rateAfterReturn=2.0 want=2.0
10-27 18:11:30.752  8701  8701 I flutter : RFV2|1793095890752|GROUP|end v13a uncaught=0
10-27 18:11:30.752  8701  8701 I flutter : RFV2|1793095890752|GROUP|begin v13b
10-27 18:11:30.876  8701  8701 I flutter : RFV2|1793095890876|V13b|run1 state rate=1.0 title=C epoch=0
10-27 18:11:34.400  8701  8701 I flutter : RFV2|1793095894400|V13b|run1 setRate(1.5) -> state.rate=1.0
10-27 18:11:34.400  8701  8701 I flutter : RFV2|1793095894400|V13b|run1 adEvent pending
10-27 18:11:34.475  8701  8701 I flutter : RFV2|1793095894475|V13b|run1 state rate=1.5 title=C epoch=0
10-27 18:11:35.522  8701  8701 I flutter : RFV2|1793095895522|V13b|run1 adEvent started
10-27 18:11:35.583  8701  8701 I flutter : RFV2|1793095895583|V13b|run1 state rate=1.0 title=AD epoch=1
10-27 18:11:39.524  8701  8701 I flutter : RFV2|1793095899523|V13b|run1 adEvent completed
10-27 18:11:39.578  8701  8701 I flutter : RFV2|1793095899578|V13b|run1 state rate=1.5 title=C epoch=2
10-27 18:11:42.608  8701  8701 I flutter : RFV2|1793095902608|V13b|run1 completedAt=1793095899523 adRateSamples=37 adMaxRate=1.0 adSettled1x=true backRate=1.5 title=C
10-27 18:11:42.608  8701  8701 I flutter : RFV2|1793095902608|RESULT|V13b|run1|PASS|adRate settled1x=true (max seen 1.0x over 37 samples) rateAfterReturn=1.5 want=1.5
10-27 18:11:42.984  8701  8701 I flutter : RFV2|1793095902984|V13b|run2 state rate=1.0 title=C epoch=0
10-27 18:11:46.406  8701  8701 I flutter : RFV2|1793095906406|V13b|run2 setRate(1.5) -> state.rate=1.0
10-27 18:11:46.406  8701  8701 I flutter : RFV2|1793095906406|V13b|run2 adEvent pending
10-27 18:11:46.481  8701  8701 I flutter : RFV2|1793095906481|V13b|run2 state rate=1.5 title=C epoch=0
10-27 18:11:47.509  8701  8701 I flutter : RFV2|1793095907509|V13b|run2 adEvent started
10-27 18:11:47.581  8701  8701 I flutter : RFV2|1793095907581|V13b|run2 state rate=1.0 title=AD epoch=1
10-27 18:11:51.512  8701  8701 I flutter : RFV2|1793095911512|V13b|run2 adEvent completed
10-27 18:11:51.581  8701  8701 I flutter : RFV2|1793095911581|V13b|run2 state rate=1.5 title=C epoch=2
10-27 18:11:54.602  8701  8701 I flutter : RFV2|1793095914602|V13b|run2 completedAt=1793095911512 adRateSamples=37 adMaxRate=1.0 adSettled1x=true backRate=1.5 title=C
10-27 18:11:54.603  8701  8701 I flutter : RFV2|1793095914603|RESULT|V13b|run2|PASS|adRate settled1x=true (max seen 1.0x over 37 samples) rateAfterReturn=1.5 want=1.5
10-27 18:11:55.019  8701  8701 I flutter : RFV2|1793095915019|V13b|run3 state rate=1.0 title=C epoch=0
10-27 18:11:58.320  8701  8701 I flutter : RFV2|1793095918320|V13b|run3 setRate(1.5) -> state.rate=1.0
10-27 18:11:58.321  8701  8701 I flutter : RFV2|1793095918321|V13b|run3 adEvent pending
10-27 18:11:58.421  8701  8701 I flutter : RFV2|1793095918421|V13b|run3 state rate=1.5 title=C epoch=0
10-27 18:11:59.266  8701  8701 I flutter : RFV2|1793095919266|V13b|run3 adEvent started
10-27 18:11:59.319  8701  8701 I flutter : RFV2|1793095919319|V13b|run3 state rate=1.0 title=AD epoch=1
10-27 18:12:03.269  8701  8701 I flutter : RFV2|1793095923269|V13b|run3 adEvent completed
10-27 18:12:03.419  8701  8701 I flutter : RFV2|1793095923419|V13b|run3 state rate=1.5 title=C epoch=2
10-27 18:12:06.361  8701  8701 I flutter : RFV2|1793095926361|V13b|run3 completedAt=1793095923269 adRateSamples=37 adMaxRate=1.0 adSettled1x=true backRate=1.5 title=C
10-27 18:12:06.361  8701  8701 I flutter : RFV2|1793095926361|RESULT|V13b|run3|PASS|adRate settled1x=true (max seen 1.0x over 37 samples) rateAfterReturn=1.5 want=1.5
10-27 18:12:06.609  8701  8701 I flutter : RFV2|1793095926609|GROUP|end v13b uncaught=0
10-27 18:12:06.609  8701  8701 I flutter : RFV2|1793095926609|GROUP|begin v14
10-27 18:12:06.627  8701  8701 I flutter : RFV2|1793095926627|V14|run1 adEvent started
10-27 18:12:14.980  8701  8701 I flutter : RFV2|1793095934980|V14|run1 adEvent completed
10-27 18:12:15.057  8701  8701 I flutter : RFV2|1793095935057|V14|run1 started->completed=8353ms failed=0 skipped=0 errorEventsDuringAd=0 shadowThrowFired=true contentPlaying=true title=C adDoneAt=1793095935016
10-27 18:12:15.057  8701  8701 I flutter : RFV2|1793095935057|RESULT|V14|run1|PASS|failed=0 skipped=0 adPlayed=8353ms (cfg 8000) errorEventsDuringAd=0 shadowOpenThrew=true contentReached=true
10-27 18:12:15.293  8701  8701 I flutter : RFV2|1793095935293|V14|run2 adEvent started
10-27 18:12:23.600  8701  8701 I flutter : RFV2|1793095943600|V14|run2 adEvent completed
10-27 18:12:23.616  8701  8701 I flutter : RFV2|1793095943616|V14|run2 started->completed=8307ms failed=0 skipped=0 errorEventsDuringAd=0 shadowThrowFired=true contentPlaying=true title=C adDoneAt=1793095943615
10-27 18:12:23.616  8701  8701 I flutter : RFV2|1793095943616|RESULT|V14|run2|PASS|failed=0 skipped=0 adPlayed=8307ms (cfg 8000) errorEventsDuringAd=0 shadowOpenThrew=true contentReached=true
10-27 18:12:23.865  8701  8701 I flutter : RFV2|1793095943864|V14|run3 adEvent started
10-27 18:12:32.128  8701  8701 I flutter : RFV2|1793095952128|V14|run3 adEvent completed
10-27 18:12:32.160  8701  8701 I flutter : RFV2|1793095952160|V14|run3 started->completed=8264ms failed=0 skipped=0 errorEventsDuringAd=0 shadowThrowFired=true contentPlaying=true title=C adDoneAt=1793095952160
10-27 18:12:32.161  8701  8701 I flutter : RFV2|1793095952160|RESULT|V14|run3|PASS|failed=0 skipped=0 adPlayed=8264ms (cfg 8000) errorEventsDuringAd=0 shadowOpenThrew=true contentReached=true
10-27 18:12:32.322  8701  8701 I flutter : RFV2|1793095952322|GROUP|end v14 uncaught=0
10-27 18:12:32.322  8701  8701 I flutter : RFV2|1793095952322|DONE|group=all uncaught=0
```

## 开始 rerun-batch12-pump

- 复用 pump 页面，核验事件与设备状态；多轮计时取平均。

## rerun-batch12-pump 自动检查点

- 复用页运行；逐编号最终结论需结合下面原始断言复核。
- driver exit=0；`{"selector": "pump||1", "completed": true, "lines": 707, "pid": "8702"}`。
- 日志：`example/tool/coverage_evidence/rerun-batch12-pump.log`；截图/系统读回/采样同前缀。
```text
10-27 18:12:58.993  8702  8702 I flutter : V3 PASS
10-27 18:13:03.241  8702  8702 I flutter : V6 PASS
10-27 18:13:05.322  8702  8702 I flutter : V9 PASS
10-27 18:15:23.441  8702  8702 I flutter : V7 PASS
10-27 18:15:23.441  8702  8702 I flutter : COUNTS created=14 destroyed=14 PASS
10-27 18:15:23.441  8702  8702 I flutter : ALL_DONE
```

## 开始 rerun-batch13-subtitles

- 复用 subtitles 页面，核验事件与设备状态；多轮计时取平均。

## 原生泵与交接完成检查点

- 方向脚本V10/V10x/V11的restoredPortrait=false单独保留：rerun-review-rotation-window.txt原生已FULL_USER；accelerometer_rotation=1、user_rotation=0。不据此误判自动方向API失败。

## rerun-batch13-subtitles 自动检查点

- 复用页运行；逐编号最终结论需结合下面原始断言复核。
- driver exit=0；`{"selector": "subtitles||1", "completed": false, "lines": 369, "pid": "8703"}`。
- 日志：`example/tool/coverage_evidence/rerun-batch13-subtitles.log`；截图/系统读回/采样同前缀。
```text
10-27 18:15:28.809  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=1 pos=0.066667 sub-text=""
10-27 18:15:29.309  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=2 pos=0.633333 sub-text=""
10-27 18:15:29.810  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=3 pos=1.133333 sub-text="ASS regression check line 1 - MOVA SUBTITLE TEST"
10-27 18:15:30.309  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=4 pos=1.633333 sub-text="ASS regression check line 1 - MOVA SUBTITLE TEST"
10-27 18:15:30.809  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=5 pos=2.133333 sub-text="ASS regression check line 1 - MOVA SUBTITLE TEST"
10-27 18:15:31.309  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=6 pos=2.633333 sub-text="ASS regression check line 1 - MOVA SUBTITLE TEST"
10-27 18:15:31.809  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=7 pos=3.133333 sub-text="ASS regression check line 1 - MOVA SUBTITLE TEST"
10-27 18:15:32.309  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=8 pos=3.633333 sub-text=""
10-27 18:15:32.825  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=9 pos=4.166667 sub-text=""
10-27 18:15:33.309  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=10 pos=4.633333 sub-text=""
10-27 18:15:33.809  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=11 pos=5.133333 sub-text="ASS regression check line 2 - libass render OK"
10-27 18:15:34.310  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=12 pos=5.633333 sub-text="ASS regression check line 2 - libass render OK"
10-27 18:15:34.809  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=13 pos=6.133333 sub-text="ASS regression check line 2 - libass render OK"
10-27 18:15:35.309  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=14 pos=6.633333 sub-text="ASS regression check line 2 - libass render OK"
10-27 18:15:35.812  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=15 pos=7.133333 sub-text="ASS regression check line 2 - libass render OK"
10-27 18:15:36.309  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=16 pos=7.633333 sub-text=""
10-27 18:15:36.816  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=17 pos=8.133333 sub-text=""
10-27 18:15:37.309  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=18 pos=8.633333 sub-text=""
10-27 18:15:37.836  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=19 pos=9.166667 sub-text="ASS regression check line 3 - overlay/equalizer removed, subs still work"
10-27 18:15:38.309  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=20 pos=9.633333 sub-text="ASS regression check line 3 - overlay/equalizer removed, subs still work"
10-27 18:15:38.821  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=21 pos=10.166667 sub-text="ASS regression check line 3 - overlay/equalizer removed, subs still work"
10-27 18:15:39.326  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=22 pos=10.666667 sub-text="ASS regression check line 3 - overlay/equalizer removed, subs still work"
10-27 18:15:39.818  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=23 pos=11.166667 sub-text="ASS regression check line 3 - overlay/equalizer removed, subs still work"
10-27 18:15:40.309  8703  8703 I flutter : SUBFMT_PROBE[ASS] t=24 pos=11.633333 sub-text=""
```

## 开始 rerun-batch14-api-launch

- 复用 api 页面，核验事件与设备状态；多轮计时取平均。

## rerun-batch14-api-launch 自动检查点

- 复用页运行；逐编号最终结论需结合下面原始断言复核。
- driver exit=0；`{"selector": "api||1", "completed": true, "lines": 164, "pid": "14731"}`。
- 日志：`example/tool/coverage_evidence/rerun-batch14-api-launch.log`；截图/系统读回/采样同前缀。
```text
```

## 结束 existing-pages

- exit=0；驱动输出 `example/tool/coverage_evidence/rerun-plan-existing-pages.log`；原始结果均用 rerun- 前缀。异常/超时不得推断为 PASS。

## 开始 widgets

- 复用现有验证器，检查真实事件/状态/原生读回；命令：`python example/tool/rerun_batch.py coverage_widgets_ui.py`。完成后仅按实际证据回填编号。

## rerun-batch16-engine 可视/API阶段检查点

- 逐动作原始状态/事件及截图见同前缀；控件/手势断言：
```json
[
  {
    "id": "rerun-batch16-engine.fit.contain",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3240,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.fit.cover",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3240,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "cover",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.fit.fill",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3240,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.sticky",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3240,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.autohide",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3240,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.lock",
    "pass": true,
    "detail": {
      "before": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 3240,
        "size": "640x360",
        "volume": 50.0,
        "brightness": 0.5,
        "rate": 1.0,
        "fit": "fill",
        "zoom": 1.0,
        "locked": true,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": true,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 12000,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      },
      "after": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 3240,
        "size": "640x360",
        "volume": 50.0,
        "brightness": 0.5,
        "rate": 1.0,
        "fit": "fill",
        "zoom": 1.0,
        "locked": true,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": true,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 12000,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      }
    }
  },
  {
    "id": "rerun-batch16-engine.doubletap",
    "pass": false,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 10000,
      "size": "640x360",
      "volume": 50.0,
      "brightness": 0.5,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "seek",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": "00:10",
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.leftBrightness",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 10000,
      "size": "640x360",
      "volume": 50.0,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "brightness",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.rightVolume",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 10000,
      "size": "640x360",
      "volume": 75.35440069273764,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "volume",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.horizontalSeek",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 19000,
      "size": "640x360",
      "volume": 75.35440069273764,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "seek",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.longpress",
    "pass": false,
    "detail": {
      "during": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 19000,
        "size": "640x360",
        "volume": 75.35440069273764,
        "brightness": 0.7530022682495624,
        "rate": 1.0,
        "fit": "fill",
        "zoom": 1.0,
        "locked": false,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": true,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 12000,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      },
      "after": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 19000,
        "size": "640x360",
        "volume": 75.35440069273764,
        "brightness": 0.7530022682495624,
        "rate": 1.0,
        "fit": "fill",
        "zoom": 1.0,
        "locked": false,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": true,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 12000,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      }
    }
  },
  {
    "id": "rerun-batch16-engine.fullscreen.true",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 19000,
      "size": "640x360",
      "volume": 75.35440069273764,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": true,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.fullscreen.false",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 19000,
      "size": "640x360",
      "volume": 75.35440069273764,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.fitRebuild",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 19000,
      "size": "640x360",
      "volume": 75.35440069273764,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  }
]
```

## rerun-batch16-cutover 可视/API阶段检查点

- 逐动作原始状态/事件及截图见同前缀；控件/手势断言：
```json
[
  {
    "id": "rerun-batch16-cutover.fit.contain",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3840,
      "size": "640x360",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.fit.cover",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3840,
      "size": "640x360",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "cover",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.fit.fill",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3840,
      "size": "640x360",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.sticky",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3840,
      "size": "640x360",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.autohide",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3840,
      "size": "640x360",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.lock",
    "pass": true,
    "detail": {
      "before": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 3840,
        "size": "640x360",
        "volume": 50.0,
        "brightness": 0.5,
        "rate": 1.0,
        "fit": "fill",
        "zoom": 1.0,
        "locked": true,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": true,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 12000,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      },
      "after": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 3840,
        "size": "640x360",
        "volume": 50.0,
        "brightness": 0.5,
        "rate": 1.0,
        "fit": "fill",
        "zoom": 1.0,
        "locked": true,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": true,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 12000,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      }
    }
  },
  {
    "id": "rerun-batch16-cutover.doubletap",
    "pass": false,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 10000,
      "size": "640x360",
      "volume": 50.0,
      "brightness": 0.5,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "seek",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": "00:10",
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.leftBrightness",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 10000,
      "size": "640x360",
      "volume": 50.0,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "brightness",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.rightVolume",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 10000,
      "size": "640x360",
      "volume": 75.30022682495624,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "volume",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.horizontalSeek",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 19000,
      "size": "640x360",
      "volume": 75.30022682495624,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "seek",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.longpress",
    "pass": false,
    "detail": {
      "during": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 19000,
        "size": "640x360",
        "volume": 75.30022682495624,
        "brightness": 0.7530022682495624,
        "rate": 1.0,
        "fit": "fill",
        "zoom": 1.0,
        "locked": false,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": true,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 12000,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      },
      "after": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 19000,
        "size": "640x360",
        "volume": 75.30022682495624,
        "brightness": 0.7530022682495624,
        "rate": 1.0,
        "fit": "fill",
        "zoom": 1.0,
        "locked": false,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": true,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 12000,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      }
    }
  },
  {
    "id": "rerun-batch16-cutover.fullscreen.true",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 19000,
      "size": "640x360",
      "volume": 75.30022682495624,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": true,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.fullscreen.false",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 19000,
      "size": "640x360",
      "volume": 75.30022682495624,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.fitRebuild",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 19000,
      "size": "640x360",
      "volume": 75.30022682495624,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  }
]
```

## 批次16 可视与组件检查点

- 完整动作证据位于 `example/tool/coverage_evidence/rerun-batch16-*`。逐项最终结论由事件/系统读回/截图复核，脚本断言不替代视觉证据。
```json
[
  {
    "id": "rerun-batch16-engine.fit.contain",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3240,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.fit.cover",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3240,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "cover",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.fit.fill",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3240,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.sticky",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3240,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.autohide",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3240,
      "size": "640x360",
      "volume": 30.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.lock",
    "pass": true,
    "detail": {
      "before": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 3240,
        "size": "640x360",
        "volume": 50.0,
        "brightness": 0.5,
        "rate": 1.0,
        "fit": "fill",
        "zoom": 1.0,
        "locked": true,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": true,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 12000,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      },
      "after": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 3240,
        "size": "640x360",
        "volume": 50.0,
        "brightness": 0.5,
        "rate": 1.0,
        "fit": "fill",
        "zoom": 1.0,
        "locked": true,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": true,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 12000,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      }
    }
  },
  {
    "id": "rerun-batch16-engine.doubletap",
    "pass": false,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 10000,
      "size": "640x360",
      "volume": 50.0,
      "brightness": 0.5,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "seek",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": "00:10",
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.leftBrightness",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 10000,
      "size": "640x360",
      "volume": 50.0,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "brightness",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.rightVolume",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 10000,
      "size": "640x360",
      "volume": 75.35440069273764,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "volume",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.horizontalSeek",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 19000,
      "size": "640x360",
      "volume": 75.35440069273764,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "seek",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.longpress",
    "pass": false,
    "detail": {
      "during": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 19000,
        "size": "640x360",
        "volume": 75.35440069273764,
        "brightness": 0.7530022682495624,
        "rate": 1.0,
        "fit": "fill",
        "zoom": 1.0,
        "locked": false,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": true,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 12000,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      },
      "after": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 19000,
        "size": "640x360",
        "volume": 75.35440069273764,
        "brightness": 0.7530022682495624,
        "rate": 1.0,
        "fit": "fill",
        "zoom": 1.0,
        "locked": false,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": true,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 12000,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      }
    }
  },
  {
    "id": "rerun-batch16-engine.fullscreen.true",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 19000,
      "size": "640x360",
      "volume": 75.35440069273764,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": true,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.fullscreen.false",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 19000,
      "size": "640x360",
      "volume": 75.35440069273764,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-engine.fitRebuild",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 19000,
      "size": "640x360",
      "volume": 75.35440069273764,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.fit.contain",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3840,
      "size": "640x360",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.fit.cover",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3840,
      "size": "640x360",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "cover",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.fit.fill",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3840,
      "size": "640x360",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.sticky",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3840,
      "size": "640x360",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.autohide",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 3840,
      "size": "640x360",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.lock",
    "pass": true,
    "detail": {
      "before": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 3840,
        "size": "640x360",
        "volume": 50.0,
        "brightness": 0.5,
        "rate": 1.0,
        "fit": "fill",
        "zoom": 1.0,
        "locked": true,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": true,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 12000,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      },
      "after": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 3840,
        "size": "640x360",
        "volume": 50.0,
        "brightness": 0.5,
        "rate": 1.0,
        "fit": "fill",
        "zoom": 1.0,
        "locked": true,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": true,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 12000,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      }
    }
  },
  {
    "id": "rerun-batch16-cutover.doubletap",
    "pass": false,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 10000,
      "size": "640x360",
      "volume": 50.0,
      "brightness": 0.5,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "seek",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": "00:10",
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.leftBrightness",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 10000,
      "size": "640x360",
      "volume": 50.0,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "brightness",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.rightVolume",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 10000,
      "size": "640x360",
      "volume": 75.30022682495624,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "volume",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.horizontalSeek",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 19000,
      "size": "640x360",
      "volume": 75.30022682495624,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "seek",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.longpress",
    "pass": false,
    "detail": {
      "during": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 19000,
        "size": "640x360",
        "volume": 75.30022682495624,
        "brightness": 0.7530022682495624,
        "rate": 1.0,
        "fit": "fill",
        "zoom": 1.0,
        "locked": false,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": true,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 12000,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      },
      "after": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 19000,
        "size": "640x360",
        "volume": 75.30022682495624,
        "brightness": 0.7530022682495624,
        "rate": 1.0,
        "fit": "fill",
        "zoom": 1.0,
        "locked": false,
        "fullscreen": false,
        "orientation": "auto",
        "pip": false,
        "mini": false,
        "rendered": true,
        "epoch": 0,
        "sourceIndex": 0,
        "keepAlive": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "previewCurrent": null,
        "timeshiftBehind": null,
        "liveSeekable": false,
        "seekableWindow": 12000,
        "hudText": null,
        "dragging": false,
        "previewAt": null
      }
    }
  },
  {
    "id": "rerun-batch16-cutover.fullscreen.true",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 19000,
      "size": "640x360",
      "volume": 75.30022682495624,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": true,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.fullscreen.false",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 19000,
      "size": "640x360",
      "volume": 75.30022682495624,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "fill",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "rerun-batch16-cutover.fitRebuild",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 19000,
      "size": "640x360",
      "volume": 75.30022682495624,
      "brightness": 0.7530022682495624,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "C15.maxDuration",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": true,
      "buffering": false,
      "duration": 37895,
      "position": 38663,
      "size": "640x360",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "cover",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "fallback",
      "type": "live",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": true,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "A25.pause",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 44343,
      "position": 44263,
      "size": "640x360",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "cover",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "type": "live",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": true,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  }
]
```

## 结束 widgets

- exit=0；驱动输出 `example/tool/coverage_evidence/rerun-plan-widgets.log`；原始结果均用 rerun- 前缀。异常/超时不得推断为 PASS。

## 开始 ui

- 复用现有验证器，检查真实事件/状态/原生读回；命令：`python example/tool/rerun_batch.py coverage_ui.py`。完成后仅按实际证据回填编号。

## 结束 ui

- exit=0；驱动输出 `example/tool/coverage_evidence/rerun-plan-ui.log`；原始结果均用 rerun- 前缀。异常/超时不得推断为 PASS。

## 开始 gesture-pip

- 复用现有验证器，检查真实事件/状态/原生读回；命令：`python example/tool/rerun_batch.py coverage_ui_final.py`。完成后仅按实际证据回填编号。

## 批次18 PiP与手势第一阶段

- rerun-batch18-normal/autohide/doubletap-seek/longpress-*保存真实注入后状态与截图；默认双击seek判据已纠正。
- rerun-batch18-pip-*保存进入、展开及第二次进入的原生activity状态；X关闭需根据实际系统控件定位后补测。

## 结束 gesture-pip

- exit=0；驱动输出 `example/tool/coverage_evidence/rerun-plan-gesture-pip.log`；原始结果均用 rerun- 前缀。异常/超时不得推断为 PASS。

## 开始 interactive

- 复用现有验证器，检查真实事件/状态/原生读回；命令：`python example/tool/rerun_batch.py coverage_interactive.py`。完成后仅按实际证据回填编号。

## 批次22：重映射、实际小窗拖动、NextUp及Feed输入

- 原始动作/状态与PNG：`example/tool/coverage_evidence/rerun-batch22-*`。
- 控件树语义转储：rerun-batch22-controls.xml；双击改用同一adb shell连续注入，避免两个adb进程的延迟。

## 结束 interactive

- exit=0；驱动输出 `example/tool/coverage_evidence/rerun-plan-interactive.log`；原始结果均用 rerun- 前缀。异常/超时不得推断为 PASS。

## 开始 visual

- 复用现有验证器，检查真实事件/状态/原生读回；命令：`python example/tool/rerun_batch.py coverage_visual_final.py`。完成后仅按实际证据回填编号。

## 批次25 可视第一阶段

- 逐动作日志/PNG及封面连续帧已保存rerun-batch25-*；包括真实preview气泡、custom红色spinner及显隐、错误层、mini默认禁用。

## 批次25 可视第二阶段

- rerun-batch25-nextup*、ad-countdown/ad-skippable/ad-skip、route-player/back及feed-poster连续帧保存；跳过按钮通过真实语义树定位。
- 矩阵里不存在的发送框、长按倍速、倍速菜单、NextUp数字倒计时/TopBar返回不能用别的动作冒充通过。

## 结束 visual

- exit=0；驱动输出 `example/tool/coverage_evidence/rerun-plan-visual.log`；原始结果均用 rerun- 前缀。异常/超时不得推断为 PASS。

## 开始 transition

- 复用现有验证器，检查真实事件/状态/原生读回；命令：`python example/tool/rerun_batch.py coverage_transition_final.py`。完成后仅按实际证据回填编号。

## 批次28：延迟缩略图竞态与自定义posterFade

- slowthumbs.vtt服务人为延迟2.5s；拖动预览请求发起后0.7s换源，晚到的非空thumb统计见rerun-batch28-stale-audit.json；服务端BEGIN/END见coverage_media_final.log。
- MovaPlayer.posterFade设置2s以便真实截图观测中间透明度，12张连续PNG及最终state已保存。

## 结束 transition

- exit=0；驱动输出 `example/tool/coverage_evidence/rerun-plan-transition.log`；原始结果均用 rerun- 前缀。异常/超时不得推断为 PASS。

## 开始最终补测包

- 安装最终隔离release：新增实时戳TLS、亮度越界原生读回、可见宽高同步快照、质量字段、V6连续缓冲区间取证。此前证据保留；不改库。

## 开始 final-api

- 命令：`python example/tool/coverage_suite_device.py api --name rerun-final-api --timeout 60`。补齐编号剩余子项；按真实状态/事件判断。

## 结束 final-api

- exit=0；驱动输出 rerun-post-final-api.log；编号判定在最终台账中汇总。

## 开始 final-tls

- 命令：`python example/tool/coverage_device.py new --arg case=tls --name rerun-final-tls --timeout 180`。补齐编号剩余子项；按真实状态/事件判断。

## 结束 final-tls

- exit=0；驱动输出 rerun-post-final-tls.log；编号判定在最终台账中汇总。

## 开始 final-tls-probe

- 命令：`python example/tool/coverage_device.py new --arg case=tlsProbe --name rerun-final-tls-probe --timeout 180`。补齐编号剩余子项；按真实状态/事件判断。

## 结束 final-tls-probe

- exit=0；驱动输出 rerun-post-final-tls-probe.log；编号判定在最终台账中汇总。

## 开始 final-hls

- 命令：`python example/tool/coverage_device.py new --arg case=hls --arg cutover=true --name rerun-final-hls-cutover --timeout 180`。补齐编号剩余子项；按真实状态/事件判断。

## 结束 final-hls

- exit=0；驱动输出 rerun-post-final-hls.log；编号判定在最终台账中汇总。

## 开始 final-abr

- 命令：`python example/tool/coverage_device.py new --arg case=abr --name rerun-final-abr --timeout 180`。补齐编号剩余子项；按真实状态/事件判断。

## 结束 final-abr

- exit=0；驱动输出 rerun-post-final-abr.log；编号判定在最终台账中汇总。

## 开始 extras

- 命令：`python example/tool/rerun_extra.py`。补齐编号剩余子项；按真实状态/事件判断。

## 开始 rerun-extra-playlist

- 补齐 playlist {}，使用真实设备状态；字幕使用已修复的素材下载与先卸载后销毁路径。

## 结束 rerun-extra-playlist

- exit=0；原始证据 `rerun-extra-playlist.json`。
```json
[
  {
    "ms": 68386,
    "kind": "BEGIN",
    "group": "playlist",
    "args": {
      "group": "playlist"
    }
  },
  {
    "ms": 68519,
    "kind": "CHECK",
    "id": "A28.start",
    "pass": true,
    "detail": "index=0"
  },
  {
    "ms": 68535,
    "kind": "CHECK",
    "id": "A28.end",
    "pass": true,
    "detail": "index=1"
  },
  {
    "ms": 88265,
    "kind": "CHECK",
    "id": "A28.auto",
    "pass": true,
    "detail": "index=1"
  },
  {
    "ms": 88271,
    "kind": "END",
    "group": "playlist",
    "status": "done"
  }
]
```

## 开始 rerun-extra-edges

- 补齐 new {'case': 'edges'}，使用真实设备状态；字幕使用已修复的素材下载与先卸载后销毁路径。

## 结束 rerun-extra-edges

- exit=0；原始证据 `rerun-extra-edges.json`。
```json
[
  {
    "ms": 91178,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "edges"
    }
  },
  {
    "ms": 91215,
    "kind": "OPEN_IMMEDIATE",
    "playing": false,
    "intent": false,
    "buffering": false,
    "duration": 0,
    "position": 19194,
    "size": "0x0",
    "volume": 100.0,
    "brightness": 1.0,
    "rate": 1.0,
    "fit": "contain",
    "zoom": 1.0,
    "locked": false,
    "fullscreen": false,
    "orientation": "auto",
    "pip": false,
    "mini": false,
    "rendered": false,
    "epoch": 0,
    "sourceIndex": 0,
    "keepAlive": "off",
    "quality": null,
    "qualities": [],
    "error": null,
    "type": "vod",
    "title": null,
    "pipSupported": false,
    "controls": true,
    "hud": "none",
    "previewCurrent": null,
    "timeshiftBehind": null,
    "liveSeekable": false,
    "seekableWindow": 0,
    "hudText": null,
    "dragging": false,
    "previewAt": null
  },
  {
    "ms": 91768,
    "kind": "SEEK_LOADING",
    "playing": false,
    "intent": false,
    "buffering": false,
    "duration": 40000,
    "position": 6999,
    "size": "0x0",
    "volume": 75.0,
    "brightness": 1.0,
    "rate": 1.0,
    "fit": "contain",
    "zoom": 1.0,
    "locked": false,
    "fullscreen": false,
    "orientation": "auto",
    "pip": false,
    "mini": false,
    "rendered": true,
    "epoch": 0,
    "sourceIndex": 0,
    "keepAlive": "off",
    "quality": null,
    "qualities": [],
    "error": null,
    "type": "vod",
    "title": "Coverage vod.mp4",
    "pipSupported": true,
    "controls": true,
    "hud": "none",
    "previewCurrent": null,
    "timeshiftBehind": null,
    "liveSeekable": false,
    "seekableWindow": 40000,
    "hudText": null,
    "dragging": false,
    "previewAt": null
  },
  {
    "ms": 92078,
    "kind": "SEEK_BY",
    "playing": false,
    "intent": false,
    "buffering": false,
    "duration": 40000,
    "position": 8998,
    "size": "0x0",
    "volume": 75.0,
    "brightness": 1.0,
    "rate": 1.0,
    "fit": "contain",
    "zoom": 1.0,
    "locked": false,
    "fullscreen": false,
    "orientation": "auto",
    "pip": false,
    "mini": false,
    "rendered": true,
    "epoch": 0,
    "sourceIndex": 0,
    "keepAlive": "off",
    "quality": null,
    "qualities": [],
    "error": null,
    "type": "vod",
    "title": "Coverage vod.mp4",
    "pipSupported": true,
    "controls": true,
    "hud": "none",
    "previewCurrent": null,
    "timeshiftBehind": null,
    "liveSeekable": false,
    "seekableWindow": 40000,
    "hudText": null,
    "dragging": false,
    "previewAt": null
  },
  {
    "ms": 92384,
    "kind": "SEEK_BEYOND",
    "playing": false,
    "intent": false,
    "buffering": false,
    "duration": 40000,
    "position": 40000,
    "size": "0x0",
    "volume": 75.0,
    "brightness": 1.0,
    "rate": 1.0,
    "fit": "contain",
    "zoom": 1.0,
    "locked": false,
    "fullscreen": false,
    "orientation": "auto",
    "pip": false,
    "mini": false,
    "rendered": true,
    "epoch": 0,
    "sourceIndex": 0,
    "keepAlive": "off",
    "quality": null,
    "qualities": [],
    "error": null,
    "type": "vod",
    "title": "Coverage vod.mp4",
    "pipSupported": true,
    "controls": true,
    "hud": "none",
    "previewCurrent": null,
    "timeshiftBehind": null,
    "liveSeekable": false,
    "seekableWindow": 40000,
    "hudText": null,
    "dragging": false,
    "previewAt": null
  },
  {
    "ms": 92401,
    "kind": "BRIGHTNESS_NATIVE",
    "input": -1.0,
    "state": 0.0,
    "native": 0.0
  },
  {
    "ms": 92430,
    "kind": "BRIGHTNESS_NATIVE",
    "input": 0.0,
    "state": 0.0,
    "native": 0.0
  },
  {
    "ms": 92435,
    "kind": "BRIGHTNESS_NATIVE",
    "input": 0.25,
    "state": 0.25,
    "native": 0.25
  },
  {
    "ms": 92506,
    "kind": "BRIGHTNESS_NATIVE",
    "input": 0.75,
    "state": 0.75,
    "native": 0.75
  },
  {
    "ms": 92512,
    "kind": "BRIGHTNESS_NATIVE",
    "input": 1.0,
    "state": 1.0,
    "native": 1.0
  },
  {
    "ms": 92513,
    "kind": "BRIGHTNESS_NATIVE",
    "input": 2.0,
    "state": 1.0,
    "native": 1.0
  },
  {
    "ms": 93112,
    "kind": "BAD_OPEN_RESULT",
    "threw": false,
    "accepted": true,
    "error": "Failed to open http://127.0.0.1:18080/404.mp4?t=1793097024720006."
  },
  {
    "ms": 93117,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-extra-failover

- 补齐 new {'case': 'recovery', 'mode': 'failover'}，使用真实设备状态；字幕使用已修复的素材下载与先卸载后销毁路径。

## 结束 rerun-extra-failover

- exit=0；原始证据 `rerun-extra-failover.json`。
```json
[
  {
    "ms": 97256,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "failover"
    }
  },
  {
    "ms": 97392,
    "kind": "RECOVERY_OPEN",
    "mode": "failover",
    "accepted": true
  },
  {
    "ms": 97407,
    "kind": "nativeEndError",
    "mode": "failover",
    "since": 151,
    "attempt": 1,
    "live": false,
    "action": "failover"
  },
  {
    "ms": 97557,
    "kind": "CHECK",
    "id": "N6.clear",
    "pass": true,
    "detail": "sourceIndex=1 error=null"
  },
  {
    "ms": 97558,
    "kind": "CHECK",
    "id": "N19.failover",
    "pass": true,
    "detail": "[MovaPause, MovaDurationChange, MovaBufferChange, MovaSizeChange, MovaPlay, MovaSourceChange, MovaReady, MovaBufferChange, MovaErrorEvent, MovaPlayFailure, MovaFailover, MovaPause, MovaBufferChange, MovaPlay, MovaBufferChange, MovaDurationChange, MovaBufferChange, MovaRecovered, MovaFirstFrame]"
  },
  {
    "ms": 97558,
    "kind": "RECOVERY_END",
    "mode": "failover",
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40000,
      "position": 0,
      "size": "0x0",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 1,
      "keepAlive": "off",
      "quality": null,
      "qualities": [],
      "error": null,
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "null"
  },
  {
    "ms": 97620,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-extra-ad-failure

- 补齐 new {'case': 'adFailure'}，使用真实设备状态；字幕使用已修复的素材下载与先卸载后销毁路径。

## 结束 rerun-extra-ad-failure

- exit=0；原始证据 `rerun-extra-ad-failure.json`。
```json
[
  {
    "ms": 101639,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "adFailure"
    }
  },
  {
    "ms": 101678,
    "kind": "AD_POLICY_EVENT",
    "policy": "MovaAdRetrySkip",
    "type": "started",
    "uri": "http://127.0.0.1:18080/404.mp4?t=1793097033846878",
    "error": "null"
  },
  {
    "ms": 101827,
    "kind": "AD_POLICY_EVENT",
    "policy": "MovaAdRetrySkip",
    "type": "failed",
    "uri": "http://127.0.0.1:18080/404.mp4?t=1793097033846878",
    "error": "Failed to open http://127.0.0.1:18080/404.mp4?t=1793097033846878."
  },
  {
    "ms": 101827,
    "kind": "AD_POLICY_EVENT",
    "policy": "MovaAdRetrySkip",
    "type": "started",
    "uri": "http://127.0.0.1:18080/404.mp4?t=1793097033846878",
    "error": "null"
  },
  {
    "ms": 101884,
    "kind": "AD_POLICY_EVENT",
    "policy": "MovaAdRetrySkip",
    "type": "failed",
    "uri": "http://127.0.0.1:18080/404.mp4?t=1793097033846878",
    "error": "Failed to open http://127.0.0.1:18080/404.mp4?t=1793097033846878."
  },
  {
    "ms": 101884,
    "kind": "AD_POLICY_EVENT",
    "policy": "MovaAdRetrySkip",
    "type": "started",
    "uri": "http://127.0.0.1:18080/ad.mp4?t=1793097033846950",
    "error": "null"
  },
  {
    "ms": 102981,
    "kind": "AD_POLICY_EVENT",
    "policy": "MovaAdRetrySkip",
    "type": "completed",
    "uri": "http://127.0.0.1:18080/ad.mp4?t=1793097033846950",
    "error": "null"
  },
  {
    "ms": 102991,
    "kind": "AD_POLICY_END",
    "policy": "MovaAdRetrySkip",
    "events": [
      "started",
      "failed",
      "started",
      "failed",
      "started",
      "completed"
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 0,
      "position": 645,
      "size": "0x0",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": false,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "quality": null,
      "qualities": [],
      "error": null,
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 20000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 103055,
    "kind": "AD_POLICY_EVENT",
    "policy": "MovaAdAbandonPod",
    "type": "started",
    "uri": "http://127.0.0.1:18080/404.mp4?t=1793097035240472",
    "error": "null"
  },
  {
    "ms": 103108,
    "kind": "AD_POLICY_EVENT",
    "policy": "MovaAdAbandonPod",
    "type": "failed",
    "uri": "http://127.0.0.1:18080/404.mp4?t=1793097035240472",
    "error": "Failed to open http://127.0.0.1:18080/404.mp4?t=1793097035240472."
  },
  {
    "ms": 103137,
    "kind": "AD_POLICY_END",
    "policy": "MovaAdAbandonPod",
    "events": [
      "started",
      "failed"
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": true,
      "duration": 0,
      "position": 0,
      "size": "0x0",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": false,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "quality": null,
      "qualities": [],
      "error": null,
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 0,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 103146,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-extra-preview-probe

- 补齐 new {'case': 'preview', 'mode': 'probe'}，使用真实设备状态；字幕使用已修复的素材下载与先卸载后销毁路径。

## 结束 rerun-extra-preview-probe

- exit=0；原始证据 `rerun-extra-preview-probe.json`。
```json
[
  {
    "ms": 106921,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "preview",
      "mode": "probe"
    }
  },
  {
    "ms": 106997,
    "kind": "NETWORK_PROBE",
    "allowHeavy": true
  },
  {
    "ms": 107251,
    "kind": "THUMB",
    "requested": 4,
    "at": 4000,
    "bytes": 8001,
    "crop": "MovaThumbCrop(0,0,160,90)",
    "peek": false
  },
  {
    "ms": 107421,
    "kind": "THUMB",
    "requested": 8,
    "at": 8000,
    "bytes": 8001,
    "crop": "MovaThumbCrop(0,0,160,90)",
    "peek": false
  },
  {
    "ms": 107660,
    "kind": "THUMB",
    "requested": 12,
    "at": 12000,
    "bytes": 8001,
    "crop": "MovaThumbCrop(0,0,160,90)",
    "peek": false
  },
  {
    "ms": 107837,
    "kind": "THUMB",
    "requested": 4,
    "at": 4000,
    "bytes": 8001,
    "crop": "MovaThumbCrop(0,0,160,90)",
    "peek": false
  },
  {
    "ms": 107841,
    "kind": "PREVIEW_END",
    "mode": "probe",
    "thumbs": 7,
    "current": "null",
    "extractCalls": 0,
    "writes": 0,
    "diskHits": 0,
    "memoryHits": 0
  },
  {
    "ms": 107842,
    "kind": "CHECK",
    "id": "N22.crop",
    "pass": true,
    "detail": "cropped VTT writes=0"
  },
  {
    "ms": 107853,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-extra-preview-offline

- 补齐 new {'case': 'preview', 'mode': 'offline'}，使用真实设备状态；字幕使用已修复的素材下载与先卸载后销毁路径。

## 结束 rerun-extra-preview-offline

- exit=0；原始证据 `rerun-extra-preview-offline.json`。
```json
[
  {
    "ms": 111368,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "preview",
      "mode": "offline"
    }
  },
  {
    "ms": 112762,
    "kind": "THUMB",
    "requested": 4,
    "at": 4000,
    "bytes": 99796,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 113578,
    "kind": "THUMB",
    "requested": 8,
    "at": 8000,
    "bytes": 98103,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 114529,
    "kind": "THUMB",
    "requested": 12,
    "at": 12000,
    "bytes": 95382,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 114700,
    "kind": "THUMB",
    "requested": 4,
    "at": 4000,
    "bytes": 99796,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 114709,
    "kind": "PREVIEW_END",
    "mode": "offline",
    "thumbs": 7,
    "current": "null",
    "extractCalls": 3,
    "writes": 3,
    "diskHits": 1,
    "memoryHits": 4
  },
  {
    "ms": 114710,
    "kind": "CHECK",
    "id": "A30.diskHit",
    "pass": true,
    "detail": "extractCalls=3 diskHits=1"
  },
  {
    "ms": 114785,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-extra-subtitles

- 补齐 new {'case': 'subtitles'}，使用真实设备状态；字幕使用已修复的素材下载与先卸载后销毁路径。

## 结束 rerun-extra-subtitles

- exit=0；原始证据 `rerun-extra-subtitles.json`。
```json
[
  {
    "ms": 118290,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "subtitles"
    }
  },
  {
    "ms": 120223,
    "kind": "CHECK",
    "id": "F11.srt",
    "pass": true,
    "detail": "native sub-text=avfilter regression check line 1 - MOVA SUBTITLE TEST"
  },
  {
    "ms": 120225,
    "kind": "SUBTITLE_SHOT",
    "format": "srt",
    "text": "avfilter regression check line 1 - MOVA SUBTITLE TEST",
    "position": "0.666667",
    "tracks": "[{\"id\":1,\"type\":\"video\",\"src-id\":1,\"image\":false,\"albumart\":false,\"default\":true,\"forced\":false,\"dependent\":false,\"visual-impaired\":false,\"hearing-impaired\":false,\"external\":false,\"selected\":true,\"main-selection\":0,\"ff-index\":0,\"decoder\":\"h264_mediacodec\",\"codec\":\"h264\",\"demux-w\":640,\"demux-h\":360,\"demux-fps\":30.000000,\"demux-par\":1.000000,\"metadata\":{\"language\":\"und\",\"handler_name\":\"VideoHandler\",\"encoder\":\"Lavc62.11.100 libx264\"}},{\"id\":1,\"type\":\"audio\",\"src-id\":2,\"audio-channels\":1,\"image\":false,\"albumart\":false,\"default\":true,\"forced\":false,\"dependent\":false,\"visual-impaired\":false,\"hearing-impaired\":false,\"external\":false,\"selected\":true,\"main-selection\":0,\"ff-index\":1,\"decoder\":\"aac\",\"codec\":\"aac\",\"demux-channel-count\":1,\"demux-channels\":\"mono\",\"demux-samplerate\":44100,\"demux-bitrate\":69221,\"metadata\":{\"language\":\"und\",\"handler_name\":\"SoundHandler\"}},{\"id\":1,\"type\":\"sub\",\"title\":\"coverage-sub.srt\",\"image\":false,\"albumart\":false,\"default\":false,\"forced\":false,\"dependent\":false,\"visual-impaired\":false,\"hearing-impaired\":false,\"external\":true,\"selected\":true,\"main-selection\":0,\"external-filename\":\"/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-sub.srt\",\"ff-index\":0,\"decoder\":\"subrip\",\"codec\":\"subrip\",\"codec-profile\":\"Advanced Sub Station Alpha\"}]",
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 12000,
      "position": 666,
      "size": "640x360",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "quality": null,
      "qualities": [],
      "error": null,
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 124030,
    "kind": "CHECK",
    "id": "F11.ass",
    "pass": true,
    "detail": "native sub-text=ASS regression check line 1 - MOVA SUBTITLE TEST"
  },
  {
    "ms": 124036,
    "kind": "SUBTITLE_SHOT",
    "format": "ass",
    "text": "ASS regression check line 1 - MOVA SUBTITLE TEST",
    "position": "1.000000",
    "tracks": "[{\"id\":1,\"type\":\"video\",\"src-id\":1,\"image\":false,\"albumart\":false,\"default\":true,\"forced\":false,\"dependent\":false,\"visual-impaired\":false,\"hearing-impaired\":false,\"external\":false,\"selected\":true,\"main-selection\":0,\"ff-index\":0,\"decoder\":\"h264_mediacodec\",\"codec\":\"h264\",\"demux-w\":640,\"demux-h\":360,\"demux-fps\":30.000000,\"demux-par\":1.000000,\"metadata\":{\"language\":\"und\",\"handler_name\":\"VideoHandler\",\"encoder\":\"Lavc62.11.100 libx264\"}},{\"id\":1,\"type\":\"audio\",\"src-id\":2,\"audio-channels\":1,\"image\":false,\"albumart\":false,\"default\":true,\"forced\":false,\"dependent\":false,\"visual-impaired\":false,\"hearing-impaired\":false,\"external\":false,\"selected\":true,\"main-selection\":0,\"ff-index\":1,\"decoder\":\"aac\",\"codec\":\"aac\",\"demux-channel-count\":1,\"demux-channels\":\"mono\",\"demux-samplerate\":44100,\"demux-bitrate\":69221,\"metadata\":{\"language\":\"und\",\"handler_name\":\"SoundHandler\"}},{\"id\":1,\"type\":\"sub\",\"title\":\"coverage-sub.ass\",\"image\":false,\"albumart\":false,\"default\":false,\"forced\":false,\"dependent\":false,\"visual-impaired\":false,\"hearing-impaired\":false,\"external\":true,\"selected\":true,\"main-selection\":0,\"external-filename\":\"/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-sub.ass\",\"ff-index\":0,\"codec\":\"ass\",\"codec-desc\":\"Advanced Sub Station Alpha\"}]",
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 12000,
      "position": 933,
      "size": "640x360",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "quality": null,
      "qualities": [],
      "error": null,
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 127792,
    "kind": "CHECK",
    "id": "F11.vtt",
    "pass": true,
    "detail": "native sub-text=VTT regression check line 1 - MOVA SUBTITLE TEST"
  },
  {
    "ms": 127794,
    "kind": "SUBTITLE_SHOT",
    "format": "vtt",
    "text": "VTT regression check line 1 - MOVA SUBTITLE TEST",
    "position": "0.900000",
    "tracks": "[{\"id\":1,\"type\":\"video\",\"src-id\":1,\"image\":false,\"albumart\":false,\"default\":true,\"forced\":false,\"dependent\":false,\"visual-impaired\":false,\"hearing-impaired\":false,\"external\":false,\"selected\":true,\"main-selection\":0,\"ff-index\":0,\"decoder\":\"h264_mediacodec\",\"codec\":\"h264\",\"demux-w\":640,\"demux-h\":360,\"demux-fps\":30.000000,\"demux-par\":1.000000,\"metadata\":{\"language\":\"und\",\"handler_name\":\"VideoHandler\",\"encoder\":\"Lavc62.11.100 libx264\"}},{\"id\":1,\"type\":\"audio\",\"src-id\":2,\"audio-channels\":1,\"image\":false,\"albumart\":false,\"default\":true,\"forced\":false,\"dependent\":false,\"visual-impaired\":false,\"hearing-impaired\":false,\"external\":false,\"selected\":true,\"main-selection\":0,\"ff-index\":1,\"decoder\":\"aac\",\"codec\":\"aac\",\"demux-channel-count\":1,\"demux-channels\":\"mono\",\"demux-samplerate\":44100,\"demux-bitrate\":69221,\"metadata\":{\"language\":\"und\",\"handler_name\":\"SoundHandler\"}},{\"id\":1,\"type\":\"sub\",\"title\":\"coverage-sub.vtt\",\"image\":false,\"albumart\":false,\"default\":false,\"forced\":false,\"dependent\":false,\"visual-impaired\":false,\"hearing-impaired\":false,\"external\":true,\"selected\":true,\"main-selection\":0,\"external-filename\":\"/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-sub.vtt\",\"ff-index\":0,\"decoder\":\"webvtt\",\"codec\":\"webvtt\",\"codec-profile\":\"Advanced Sub Station Alpha\"}]",
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 12000,
      "position": 766,
      "size": "640x360",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "quality": null,
      "qualities": [],
      "error": null,
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 131520,
    "kind": "CHECK",
    "id": "F11.movtext",
    "pass": true,
    "detail": "native sub-text=avfilter regression check line 1 - MOVA SUBTITLE TEST"
  },
  {
    "ms": 131522,
    "kind": "SUBTITLE_SHOT",
    "format": "movtext",
    "text": "avfilter regression check line 1 - MOVA SUBTITLE TEST",
    "position": "0.633333",
    "tracks": "[{\"id\":1,\"type\":\"video\",\"src-id\":1,\"image\":false,\"albumart\":false,\"default\":true,\"forced\":false,\"dependent\":false,\"visual-impaired\":false,\"hearing-impaired\":false,\"external\":false,\"selected\":true,\"main-selection\":0,\"ff-index\":0,\"decoder\":\"h264_mediacodec\",\"codec\":\"h264\",\"demux-w\":640,\"demux-h\":360,\"demux-fps\":30.000000,\"demux-par\":1.000000,\"metadata\":{\"language\":\"und\",\"handler_name\":\"VideoHandler\",\"encoder\":\"Lavc62.11.100 libx264\"}},{\"id\":1,\"type\":\"audio\",\"src-id\":2,\"audio-channels\":1,\"image\":false,\"albumart\":false,\"default\":true,\"forced\":false,\"dependent\":false,\"visual-impaired\":false,\"hearing-impaired\":false,\"external\":false,\"selected\":true,\"main-selection\":0,\"ff-index\":1,\"decoder\":\"aac\",\"codec\":\"aac\",\"demux-channel-count\":1,\"demux-channels\":\"mono\",\"demux-samplerate\":44100,\"demux-bitrate\":69221,\"metadata\":{\"language\":\"und\",\"handler_name\":\"SoundHandler\"}},{\"id\":1,\"type\":\"sub\",\"src-id\":3,\"image\":false,\"albumart\":false,\"default\":true,\"forced\":false,\"dependent\":false,\"visual-impaired\":false,\"hearing-impaired\":false,\"external\":false,\"selected\":true,\"main-selection\":0,\"ff-index\":2,\"decoder\":\"mov_text\",\"codec\":\"mov_text\",\"codec-profile\":\"Advanced Sub Station Alpha\",\"metadata\":{\"language\":\"und\",\"handler_name\":\"SubtitleHandler\"}}]",
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 12000,
      "position": 466,
      "size": "640x360",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "quality": null,
      "qualities": [],
      "error": null,
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 12000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 133260,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-extra-live-backoff-0

- 补齐 new {'case': 'recovery', 'mode': 'live'}，使用真实设备状态；字幕使用已修复的素材下载与先卸载后销毁路径。

## 结束 rerun-extra-live-backoff-0

- exit=0；原始证据 `rerun-extra-live-backoff-0.json`。
```json
[
  {
    "ms": 136690,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "live"
    }
  },
  {
    "ms": 136862,
    "kind": "RECOVERY_OPEN",
    "mode": "live",
    "accepted": true
  },
  {
    "ms": 136879,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 188,
    "attempt": 1,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 137918,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 1227,
    "attempt": 2,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 140025,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 3334,
    "attempt": 3,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 144080,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 7389,
    "attempt": 4,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 152149,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 15458,
    "attempt": 5,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 167204,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 30513,
    "attempt": 6,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 182263,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 45572,
    "attempt": 7,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 197363,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 60672,
    "attempt": 8,
    "live": true,
    "action": "giveUp"
  },
  {
    "ms": 197375,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/not-found.mp4?t=1793097068936199) buffering=false"
  },
  {
    "ms": 197375,
    "kind": "RECOVERY_END",
    "mode": "live",
    "state": {
      "playing": false,
      "intent": true,
      "buffering": false,
      "duration": 0,
      "position": 0,
      "size": "0x0",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": false,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "quality": null,
      "qualities": [],
      "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/not-found.mp4?t=1793097068936199)",
      "type": "live",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 0,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/not-found.mp4?t=1793097068936199)"
  },
  {
    "ms": 197390,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-extra-live-backoff-1

- 补齐 new {'case': 'recovery', 'mode': 'live'}，使用真实设备状态；字幕使用已修复的素材下载与先卸载后销毁路径。

## 结束 rerun-extra-live-backoff-1

- exit=0；原始证据 `rerun-extra-live-backoff-1.json`。
```json
[
  {
    "ms": 200416,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "live"
    }
  },
  {
    "ms": 200594,
    "kind": "RECOVERY_OPEN",
    "mode": "live",
    "accepted": true
  },
  {
    "ms": 200609,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 192,
    "attempt": 1,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 201646,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 1229,
    "attempt": 2,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 203747,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 3330,
    "attempt": 3,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 207799,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 7382,
    "attempt": 4,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 215861,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 15444,
    "attempt": 5,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 230912,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 30495,
    "attempt": 6,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 245973,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 45556,
    "attempt": 7,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 261148,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 60731,
    "attempt": 8,
    "live": true,
    "action": "giveUp"
  },
  {
    "ms": 261188,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/not-found.mp4?t=1793097132663530) buffering=false"
  },
  {
    "ms": 261189,
    "kind": "RECOVERY_END",
    "mode": "live",
    "state": {
      "playing": false,
      "intent": true,
      "buffering": false,
      "duration": 0,
      "position": 0,
      "size": "0x0",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": false,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "quality": null,
      "qualities": [],
      "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/not-found.mp4?t=1793097132663530)",
      "type": "live",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 0,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/not-found.mp4?t=1793097132663530)"
  },
  {
    "ms": 261199,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 开始 rerun-extra-live-backoff-2

- 补齐 new {'case': 'recovery', 'mode': 'live'}，使用真实设备状态；字幕使用已修复的素材下载与先卸载后销毁路径。

## 结束 rerun-extra-live-backoff-2

- exit=0；原始证据 `rerun-extra-live-backoff-2.json`。
```json
[
  {
    "ms": 264451,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "live"
    }
  },
  {
    "ms": 264601,
    "kind": "RECOVERY_OPEN",
    "mode": "live",
    "accepted": true
  },
  {
    "ms": 264618,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 166,
    "attempt": 1,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 265658,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 1206,
    "attempt": 2,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 267772,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 3320,
    "attempt": 3,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 271877,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 7425,
    "attempt": 4,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 279921,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 15469,
    "attempt": 5,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 295016,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 30564,
    "attempt": 6,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 310156,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 45704,
    "attempt": 7,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 325190,
    "kind": "nativeEndError",
    "mode": "live",
    "since": 60738,
    "attempt": 8,
    "live": true,
    "action": "giveUp"
  },
  {
    "ms": 325209,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/not-found.mp4?t=1793097196693954) buffering=false"
  },
  {
    "ms": 325210,
    "kind": "RECOVERY_END",
    "mode": "live",
    "state": {
      "playing": false,
      "intent": true,
      "buffering": false,
      "duration": 0,
      "position": 0,
      "size": "0x0",
      "volume": 75.0,
      "brightness": 1.0,
      "rate": 1.0,
      "fit": "contain",
      "zoom": 1.0,
      "locked": false,
      "fullscreen": false,
      "orientation": "auto",
      "pip": false,
      "mini": false,
      "rendered": false,
      "epoch": 0,
      "sourceIndex": 0,
      "keepAlive": "off",
      "quality": null,
      "qualities": [],
      "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/not-found.mp4?t=1793097196693954)",
      "type": "live",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "previewCurrent": null,
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 0,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/not-found.mp4?t=1793097196693954)"
  },
  {
    "ms": 325229,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 外部服务检查点

- WHEP端点/端口探测见 rerun-external-prerequisites.json；UDP端口不能通过TCP结果断言可用。未提供STT真实识别模型/下载服务和按behind返回历史的服务。

## 结束 extras

- exit=0；驱动输出 rerun-post-extras.log；编号判定在最终台账中汇总。

## 开始 live-inputs

- 命令：`python example/tool/rerun_live_inputs.py`。补齐编号剩余子项；按真实状态/事件判断。

## 开始 rerun-live-0

- 播放真实18081滑动HLS，等待liveSeekable/进度就绪再seek与backEdge，核验TimeShiftChange和LiveEdgeReach；不将该滑动流当作历史回看服务。

## 结束 rerun-live-0

- seek后state={"playing": true, "intent": true, "buffering": false, "duration": 17998, "position": 3000, "size": "640x360", "volume": 75.0, "brightness": 1.0, "rate": 1.0, "fit": "contain", "zoom": 1.0, "locked": false, "fullscreen": false, "orientation": "auto", "pip": false, "mini": false, "rendered": true, "epoch": 0, "sourceIndex": 0, "keepAlive": "off", "quality": null, "qualities": [], "error": null, "type": "live", "title": null, "pipSupported": true, "controls": true, "hud": "none", "previewCurrent": null, "timeshiftBehind": 8000, "liveSeekable": true, "seekableWindow": 12000, "hudText": null, "dragging": false, "previewAt": null}；backEdge后state={"playing": true, "intent": true, "buffering": false, "duration": 20320, "position": 12000, "size": "640x360", "volume": 75.0, "brightness": 1.0, "rate": 1.0, "fit": "contain", "zoom": 1.0, "locked": false, "fullscreen": false, "orientation": "auto", "pip": false, "mini": false, "rendered": true, "epoch": 0, "sourceIndex": 0, "keepAlive": "off", "quality": null, "qualities": [], "error": null, "type": "live", "title": null, "pipSupported": true, "controls": true, "hud": "none", "previewCurrent": null, "timeshiftBehind": null, "liveSeekable": true, "seekableWindow": 12000, "hudText": null, "dragging": false, "previewAt": null}。原始事件/载荷见同前缀JSON。

## 开始 rerun-live-1

- 播放真实18081滑动HLS，等待liveSeekable/进度就绪再seek与backEdge，核验TimeShiftChange和LiveEdgeReach；不将该滑动流当作历史回看服务。

## 结束 rerun-live-1

- seek后state={"playing": true, "intent": true, "buffering": false, "duration": 21978, "position": 3080, "size": "640x360", "volume": 75.0, "brightness": 1.0, "rate": 1.0, "fit": "contain", "zoom": 1.0, "locked": false, "fullscreen": false, "orientation": "auto", "pip": false, "mini": false, "rendered": true, "epoch": 0, "sourceIndex": 0, "keepAlive": "off", "quality": null, "qualities": [], "error": null, "type": "live", "title": null, "pipSupported": true, "controls": true, "hud": "none", "previewCurrent": null, "timeshiftBehind": 8000, "liveSeekable": true, "seekableWindow": 12000, "hudText": null, "dragging": false, "previewAt": null}；backEdge后state={"playing": true, "intent": true, "buffering": false, "duration": 23999, "position": 12000, "size": "640x360", "volume": 75.0, "brightness": 1.0, "rate": 1.0, "fit": "contain", "zoom": 1.0, "locked": false, "fullscreen": false, "orientation": "auto", "pip": false, "mini": false, "rendered": true, "epoch": 0, "sourceIndex": 0, "keepAlive": "off", "quality": null, "qualities": [], "error": null, "type": "live", "title": null, "pipSupported": true, "controls": true, "hud": "none", "previewCurrent": null, "timeshiftBehind": null, "liveSeekable": true, "seekableWindow": 12000, "hudText": null, "dragging": false, "previewAt": null}。原始事件/载荷见同前缀JSON。

## 开始 rerun-live-2

- 播放真实18081滑动HLS，等待liveSeekable/进度就绪再seek与backEdge，核验TimeShiftChange和LiveEdgeReach；不将该滑动流当作历史回看服务。

## 结束 rerun-live-2

- seek后state={"playing": true, "intent": true, "buffering": false, "duration": 19988, "position": 3000, "size": "640x360", "volume": 75.0, "brightness": 1.0, "rate": 1.0, "fit": "contain", "zoom": 1.0, "locked": false, "fullscreen": false, "orientation": "auto", "pip": false, "mini": false, "rendered": true, "epoch": 0, "sourceIndex": 0, "keepAlive": "off", "quality": null, "qualities": [], "error": null, "type": "live", "title": null, "pipSupported": true, "controls": true, "hud": "none", "previewCurrent": null, "timeshiftBehind": 8000, "liveSeekable": true, "seekableWindow": 12000, "hudText": null, "dragging": false, "previewAt": null}；backEdge后state={"playing": true, "intent": true, "buffering": true, "duration": 19988, "position": 12000, "size": "640x360", "volume": 75.0, "brightness": 1.0, "rate": 1.0, "fit": "contain", "zoom": 1.0, "locked": false, "fullscreen": false, "orientation": "auto", "pip": false, "mini": false, "rendered": true, "epoch": 0, "sourceIndex": 0, "keepAlive": "off", "quality": null, "qualities": [], "error": null, "type": "live", "title": null, "pipSupported": true, "controls": true, "hud": "none", "previewCurrent": null, "timeshiftBehind": null, "liveSeekable": true, "seekableWindow": 12000, "hudText": null, "dragging": false, "previewAt": null}。原始事件/载荷见同前缀JSON。

## 结束 live-inputs

- exit=0；驱动输出 rerun-post-live-inputs.log；编号判定在最终台账中汇总。

## 开始 native-inputs

- 命令：`python example/tool/rerun_native_inputs.py`。补齐编号剩余子项；按真实状态/事件判断。

## 开始 rerun-native-engine

- 逐个音量边界读回Android媒体音量；在非audioOnly画面尺寸就绪后立即读open同步状态，补齐A8/A5/N12。

## 结束 rerun-native-engine

- 同前缀JSON中VIDEO_OPEN_BEFORE/VIDEO_OPEN_SYNC/VIDEO_OPEN_ACCEPTED保存真实宽高；*.native.txt保存媒体音量读回，截图/window/audio旁证均保留。

## 开始 rerun-native-cutover

- 逐个音量边界读回Android媒体音量；在非audioOnly画面尺寸就绪后立即读open同步状态，补齐A8/A5/N12。

## 结束 rerun-native-cutover

- 同前缀JSON中VIDEO_OPEN_BEFORE/VIDEO_OPEN_SYNC/VIDEO_OPEN_ACCEPTED保存真实宽高；*.native.txt保存媒体音量读回，截图/window/audio旁证均保留。

## 结束 native-inputs

- exit=0；驱动输出 rerun-post-native-inputs.log；编号判定在最终台账中汇总。

## 开始 he-v6-final

- 命令：`python example/tool/coverage_suite_device.py he --only V6 --runs 5 --timeout 300 --name rerun-he-v6-final`。补齐编号剩余子项；按真实状态/事件判断。

## 结束 he-v6-final

- exit=0；驱动输出 rerun-post-he-v6-final.log；编号判定在最终台账中汇总。

## 开始 manual-ready

- 命令：`python example/tool/coverage_suite_device.py api --name rerun-manual-ready --timeout 60`。补齐编号剩余子项；按真实状态/事件判断。

## 结束 manual-ready

- exit=0；驱动输出 rerun-post-manual-ready.log；编号判定在最终台账中汇总。

## 开始安全视觉复跑

- 排除rerun-batch25/batch28在误触PiP后的视觉结论；使用原生前台/完整窗口守卫和语义定位重新执行visual。慢VTT必须有服务端BEGIN/END后才可判竞态。

## 批次25 可视第一阶段

- 逐动作日志/PNG及封面连续帧已保存rerun-safe-visual-*；包括真实preview气泡、custom红色spinner及显隐、错误层、mini默认禁用。

## 批次25 可视第二阶段

- rerun-safe-visual-nextup*、ad-countdown/ad-skippable/ad-skip、route-player/back及feed-poster连续帧保存；跳过按钮通过真实语义树定位。
- 矩阵里不存在的发送框、长按倍速、倍速菜单、NextUp数字倒计时/TopBar返回不能用别的动作冒充通过。

## 开始安全慢VTT与封面补测

- 安全视觉复跑已完成；接下来在全尺寸前台页面发起慢VTT，必须先有服务端请求标记，再以换源后的thumb状态判定旧结果丢弃。

## 批次28：延迟缩略图竞态与自定义posterFade

- slowthumbs.vtt服务人为延迟2.5s；拖动预览请求发起后0.7s换源，晚到的非空thumb统计见rerun-safe-transition-stale-audit.json；服务端BEGIN/END见coverage_media_final.log。
- MovaPlayer.posterFade设置2s以便真实截图观测中间透明度，12张连续PNG及最终state已保存。

## 开始安全实触 mini

- 触点来自实际mini矩形，预览等待真实thumb；仅测试包前台时注入，原始证据rerun-manual-*。

## 开始安全实触 preview

- 触点来自实际mini矩形，预览等待真实thumb；仅测试包前台时注入，原始证据rerun-manual-*。

## 结束安全实触 preview

- 本批完成；真实mini回调/矩形/epoch或previewCurrent/dragging见rerun-manual-*原始JSON/PNG。

## 开始安全实触 mini

- 触点来自实际mini矩形，预览等待真实thumb；仅测试包前台时注入，原始证据rerun-manual-*。

## 结束安全实触 mini

- 本批完成；真实mini回调/矩形/epoch或previewCurrent/dragging见rerun-manual-*原始JSON/PNG。

## 开始安全实触 preview

- 触点来自实际mini矩形，预览等待真实thumb；仅测试包前台时注入，原始证据rerun-manual-*。

## 结束安全实触 preview

- 本批完成；真实mini回调/矩形/epoch或previewCurrent/dragging见rerun-manual-*原始JSON/PNG。

## 开始PiP双退出收尾

- 真机进入PiP前先显示App内小窗，核验互斥；展开后再次进入，X只点击原生pinned窗口内已确认的关闭控件。

## 新发现小窗/PiP衔接缺陷

- 最小复现无需固定触点：Mini.show(api)→api.enterPip()→am start恢复；不是此前误触PiP的验证器问题。

## 开始N22真机debug断言

- 隔离debug APK已由Gradle真实构建；安装到同一独立包，读取VM断言启用与两个非法构造捕获结果。其他矩阵结果仍只引用release。

## 结束N22真机debug断言

- {"foundMarker": true, "assertionsEnabled": true, "trackCountRejected": true, "maxZoomRejected": true}；证据rerun-debug-assert.json/logcat.txt/png。

