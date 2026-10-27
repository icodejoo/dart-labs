# 2026-10-27 Android 真机覆盖结果

> 当前有效总计 135：PASS 107 / FAIL 23 / BLOCKED 5。最终计数；历史计数仅为当时快照。

## 最终汇总

| 组 | 总数 | PASS | FAIL | BLOCKED |
|---|---:|---:|---:|---:|
| A | 33 | 24 | 8 | 1 |
| C | 17 | 11 | 4 | 2 |
| E | 37 | 34 | 3 | 0 |
| U | 9 | 5 | 4 | 0 |
| F | 16 | 13 | 2 | 1 |
| N | 23 | 20 | 2 | 1 |

FAIL编号：A1, A2, A5, A8, A9, A12, A17, A23, C3, C6, C8, C16, E.MovaBufferChange, E.MovaSizeChange, E1, U3, U5, U6, U7, F3, F8, N12, N19。

BLOCKED编号：A31, C2, C7, F15, N22。

FAIL含真实播放/生命周期问题及矩阵契约/能力差异，文末分开列最小复现；不代表同样数量的独立bug。全部原始证据在 `example/tool/coverage_evidence/`，每批均已追加检查点。

执行设备：`7NQBB23606003715`（STG_AL00）。本轮仅改验证页、example/tool 脚本及本文档；不修改库、测试或其他子工程，不执行 commit/stash/reset。

**最终口径**：下方主台账已按135个编号完成判定。设备解锁后完成release测试，历史锁屏/构建记录仅为过程快照；详细FAIL最小复现、BLOCKED条件和CLAUDE对照见文末“最终批次”。

## 批次 0：前置与基线（进行中）

- 原有未提交改动：`packages/media_kit_libs_macos_video_slim/macos/Frameworks/Mpv.xcframework/macos-arm64_x86_64/Mpv.framework/Mpv`；原有未跟踪矩阵与 `../proxy/`，均保留。
- 已读取根目录 `CLAUDE.md`（用户所称 `mova/CLAUDE.md`）、完整测试矩阵与 Android 交接文档。旧交接中的 reset/提交/改其他文档等步骤不适用于本轮。
- `adb devices -l`：目标设备 `device product:STG-AL00 model:STG_AL00 device:HWSTG-Q transport_id:1`。
- 初始 `dumpsys window`：`isKeyguardShowing=true`，AOD/NotificationShade；尝试 WAKEUP、`wm dismiss-keyguard` 和上滑后仍为 true，已请求人工解锁。在确认解锁前不产生渲染测试结论。
- `flutter analyze lib test`：`No issues found! (ran in 20.8s)`；原始日志 `example/tool/coverage_baseline_analyze.log`。
- `flutter test`：运行中；日志 `example/tool/coverage_baseline_test.log`。

判定规则：完整满足某编号所有子项才记 PASS；明确违背预期记 FAIL；未完成、缺服务/模型/交互证据记 BLOCKED，并列出已测子项。历史结果与静态代码阅读不当作本轮真机 PASS。

## 批次 0 结论与本轮台账

- 基线最终结果：`00:52 +1503: All tests passed!`；分析 `No issues found! (ran in 20.8s)`。
- 环境：Flutter 3.47.0 / Dart 3.13.0；Android 12 / arm64-v8a。
- 公共阻塞 K：`isKeyguardShowing=true`，WAKEUP / dismiss-keyguard / swipe 后仍锁定；未获得人工解锁完成信号。
- K 证据：`example/tool/coverage_evidence/preflight.devices.txt`、`preflight.window.txt`、`preflight.locked.png`（同目录）。
- 以下 BLOCKED 是**本轮未执行**，不是功能失败，也不是历史测试结论。解除 K 后逐批更新，不能把单元测试当真机验证。
- 矩阵计数口径：A 33、C 17、E 37（每个事件单列 + E1/E2）、U 9、F 16；总计 112。当前 PASS 0 / FAIL 0 / BLOCKED 112。

### A 组

| 编号 | 结论 | 测试点与缺失证据 |
|---|---|---|
| A1 | FAIL | batch15-basic/basic-swap STREAM_FLAGS均[true,false,true,false]：states/uiStates.isBroadcast=false，events/progress=true。两订阅计数相等且八订阅均关闭；是标志/矩阵契约差异，不是已证实的多订阅失败。 |
| A2 | FAIL | 事件接收快照并非始终与载荷一致：E.BufferChange在batch1-basic-swap 7次中3次不同；E.SizeChange在batch15-abr 7次中1次不同。其余可对账字段正常；见event-audit.json及复现记录，可能为异步队列快照语义。 |
| A3 | PASS | batch15-lazy.json：VideoController计数构造0/open后0/首次renderHandle后1，真实640x360；batch15-basic两实现audioOnly handle=null。 |
| A4 | PASS | 普通及 swap 的 pipSupported=true、state.pipSupported=true；两份 batch1-basic*.json 的 A4 检查。 |
| A5 | FAIL | batch20-edges BAD_OPEN_RESULT：recovery关闭、404返回accepted=true/threw=false，错误随后进入state/error事件；batch15-basic两实现OPEN_SYNC立即读仍旧duration40000/title，异步后归零。与矩阵同步清零/坏地址抛出预期不同；按当前异步API属契约预期差异，open true仅代表接受（N8通过）。 |
| A6 | PASS | 普通及 swap 的 play/pause/playOrPause 有事件，重复 pause 后 playing=false/intent=false；暂停态 open 后 intent=false。batch1-basic*.json。 |
| A7 | PASS | batch15-basic两实现5个精确seek误差0ms、负值落0，live0/2s组seek被拦；batch20-edges加载中寄存7s→6999ms，seekBy(+2s)→8998ms，超长1h→duration40000ms。最后一项仅测越界钳制，不作为EOF/性能判据。 |
| A8 | FAIL | 越界state未钳制（batch1）；有效值真实写系统媒体音量：0/50/100/30→STREAM_MUSIC speaker=0/10/20/6，Max=20；batch3-15…18.audio.txt。 |
| A9 | FAIL | batch15-basic两实现越界state=-1/2未钳制；batch20-edges真实ScreenBrightness.application读回0/.25/.75/1与state逐项完全一致。FAIL限越界state契约，不是正常亮度失效。 |
| A10 | PASS | batch15-basic/basic-swap：0.5/1/1.5/2实际相同；-1/0均抛Invalid argument(rate)；换源及reload保持1.5x；batch11广告最大采样1x、恢复2x/1.5x。 |
| A11 | PASS | 全部3个MovaFit：contain/cover/fill事件与state一致；batch3-02/03/04截图已目视核对，分别留黑边/裁切铺满/纵向拉伸，同一暂停帧时间码00:00:02.760。 |
| A12 | FAIL | setZoom(-1/0/100)接受并使state.zoom=-1/0/100，超出maxZoom的100未钳制；有MovaZoomChange。batch3-09/10/13-zoom*.json；缩放平移手势另测。 |
| A13 | PASS | batch16-engine/swap-lock及locked-check：locked=true，注入左右竖滑后volume=50/brightness=.5不变，LockChange与state一致；截图同前缀。 |
| A14 | PASS | batch16-engine及swap fullscreen/orientation原始JSON+window+PNG：横屏2266x1080、竖屏1080x2376；fullscreen topPadding110→0，退出恢复110；auto/portrait/landscape事件/state一致，两实现已测。 |
| A15 | PASS | batch16-engine/swap mini及mini-host/page各动作：位置继续、epoch始终0，非重新解码；batch18-mini→pip-enter：mini=true→false且pip=true，进入PiP返回true。 |
| A16 | PASS | batch16-engine及swap fullscreen/orientation原始JSON+window+PNG：横屏2266x1080、竖屏1080x2376；fullscreen topPadding110→0，退出恢复110；auto/portrait/landscape事件/state一致，两实现已测。 |
| A17 | FAIL | 原生FFI最终版：batch23-hls-native普通首切8183→8143ms(-40)，第二切target8823但RESTART=23ms并从头走；普通5切1通过4失败。batch24-hls-native-swap也1/5；paused第二切8263→23ms丢位置，之后目标已0附近的“通过”不算有效续播样本。ABR限速下调通过，不抵消重复手切缺陷。旧batch17/19/21的等待/瞬时读回判据作废，非库失败依据。 |
| A18 | PASS | batch18-pip-visible.activity.txt：mode=pinned、mLastReportedPictureInPictureMode=true；enter返回true。展开pip=false且继续播放。X路径用adb tap(750,2050)后等450ms、tap(960,1965)，before-x.png有系统X，after-x.png关闭；pip-x-final state.pip=false/playing=false，native无pinned。原始JSON含true/false变更。 |
| A19 | PASS | batch15-basic/basic-swap.json：RELOAD快照及SourceChange/Ready/DurationChange重发，暂停策略保持，position归零；重新open后rate=1.5。 |
| A20 | PASS | batch19-live-dvr/behind/backedge：真实18081/live.m3u8；seek3s，TimeShiftChange behind随播放变化；backEdge到position12000ms、LiveEdgeReach，窗口12s；点播backEdge无副作用见basic，holding重载保护5/5见batch7 S13。 |
| A21 | PASS | batch15-basic两实现：A21.hide/hud=true，dragging及previewAt=5s、HUD文本一致；batch16-swap sticky保持/800ms自动隐藏均true。 |
| A22 | PASS | 两实现 custom(coverage) 的相等及 hashCode 一致，probe=42 透传；内置 play probe=43 可见，batch1-basic*.json。 |
| A23 | FAIL | batch15-basic/basic-swap第二次dispose均抛[Player] has been disposed；disposed open=false。首次销毁正常且8流关闭；batch15-dispose120完成120轮，round20..120 meminfo与RSS约227→247MB尾部平台，不能据此证明绝无泄漏；batch11加载/换指期间销毁通过。 |
| A24 | PASS | batch15-swap.json：默认关闭1引擎epoch0；prepare→commit epoch1 position6048/rate1.5；短预热拒绝、abandon关闭影子、2s超时false、swapTo epoch2、退役open=false。 |
| A25 | PASS | batch7/8 standby原生日志含off/holding/fallback/resuming；batch16-checks A25.pause=true（pause结束holding），maxDuration到期true；恢复信号不足单列F6。 |
| A26 | PASS | batch16/22 show/showInPage/hide/close及A/B互斥、setRect读回30/90/180/110；batch25-mini-tap有MINI_TAPPED，close有MINI_CLOSED，位置继续/epoch0；isShowing与mount有日志。setRect是窗口回写矩形接口，未把它当强制移动UI的命令。 |
| A27 | PASS | batch15-ads前/中/后/手动、deferred、clicked、skip、waitsFor覆盖，batch11 pod真实换指；batch20-ad-failure：RetrySkip(maxRetries1)真实404两次failed后继续下一条，AbandonPod首次failed后直接正片。 |
| A28 | PASS | batch1-playlist.json：start index=0 hasNext=true、end index=1 hasNext=false、边界 previous/next 不越界；真实 MovaDone 后自动 index=1，controller 与 engine dispose 完成。 |
| A29 | PASS | batch15-feed.json：100次串行+20次重叠activate，最终active=120，created=3；ensure及邻居预热、controller/pool dispose通过。 |
| A30 | PASS | batch15 preview真实VTT/原生抽帧及cache两层命中、cancel/clear；batch23-preview-probe真实connectivity插件allowHeavy=true、wifiOnly获得7次thumb通知；offline把VTT源指向拒连127.0.0.1:9，抽帧兜底3次/磁盘命中1/内存命中4无崩。此处断网是缩略图源网络不可达，视频18080仍可达；未把never策略冒充断网。 |
| A31 | BLOCKED | batch15-stt.json已实际触发MovaSttBlock(disabled/noEngine)，注入引擎start失败回滚后重试成功；缺可用真实STT模型、识别引擎及模型下载服务，无法验证真实转写/SRT导出/分块落盘。 |
| A32 | PASS | batch15-hooks和hooks-swap各9项true：异步open/play/seek放行/否决/失效返回/换源，jumpTo拒绝不前进；hook异常后可继续play，onError抛出隔离。 |
| A33 | PASS | 真机 release 安装 testing 替身后 kernels=1、pip=false、renderHandle=null；亮度/全屏操作完成，batch1-testing.json。 |
### C 组

| 编号 | 结论 | 测试点与缺失证据 |
|---|---|---|
| C1 | PASS | batch15-preview-vtt/extract/fallback/blocked.json：VTT优先且crop零缓存；抽帧4请求实际3次，memory上限2、memoryHits4/diskHits1；never策略0缩略图并PreviewBlock(network)。 |
| C2 | BLOCKED | 已在真实FLV/HLS测试durationStep、DVR窗口12s、seek退后/LiveEdgeReach/回边缘（batch15-live*、batch19-live*）；未提供可按behind URL取历史的服务，现有18081仅滑动live HLS、FLV忽略历史时间参数，不能证明urlBuilder时移语义；自定义windowResolver/autoBackToLiveOnStall完整联动仍缺此服务。 |
| C3 | FAIL | 矩阵要求长按倍速：batch18-longpress-during在真实播放中注入1800ms长按，during/after rate均1；默认GestureLayer无longPress配置/处理。双击实际为±10s seek（batch18-doubletap-seek），左右亮度/音量、横滑、锁定均通过。此项为矩阵能力假设差异；Douyin另测。 |
| C4 | PASS | batch15-abr.json：真实HTTP ts限速约6.8KB/s，MovaBufferAbr threshold=1、首次5s门控后360p→180p；手动紧接回高档5023→5743ms，未回零；非默认threshold=3性能结论。 |
| C5 | PASS | batch18-normal-start/custom controls：showOnStart=true，800ms隐藏后batch18-autohide controls=false；batch16-swap sticky保持，normal自动隐藏true；可见栏淡入/淡出截图及default/minimal组件组合有证据。 |
| C6 | FAIL | 矩阵要求“发送”，当前设计为仅展示固定host items，没有发送API/输入框（danmaku_config.dart明确Display-only）。batch16 custom配置8条定时弹幕，实际滚动截图在最终batch25补；不把设计不提供的能力称为已通过。 |
| C7 | BLOCKED | batch15-stt.json已实际触发MovaSttBlock(disabled/noEngine)，注入引擎start失败回滚后重试成功；缺可用真实STT模型、识别引擎及模型下载服务，无法验证真实转写/SRT导出/分块落盘。 |
| C8 | FAIL | batch22-nextup.png显示COVERAGE NEXT EPISODE和取消/立即播放，A28自然完成后连播已通过；卡片实现仅lead-time显隐，无可见数字倒计时，矩阵“NextUp倒计时”未实现。 |
| C9 | PASS | batch15-ads.json：默认关零事件、PRE/MANUAL/MID/POST实际started/clicked/skipped/completed；waitsFor pre=false/mid=true/post=false及breakOverride=false；pod见batch11。 |
| C10 | PASS | batch22-controls.xml实际COVERAGE FIT文案；batch25-spinner-custom.png为60逻辑尺寸/8 stroke/#FFFF0000红圈，spinner-disabled.png消失；minimal无栏无手势，error-visible/error-disabled.png分别有/无原生404错误文字。默认外观见batch3及batch25 normal。 |
| C11 | PASS | batch15-swap.json：默认off纯直通epoch0，一次工厂调用；enabled提交epoch1/2及影子释放见A24。 |
| C12 | PASS | batch22真实拖动吸左left12/top434.20；转屏PNG钳回。修正原甩动坐标：batch27-mini-real-fling从窗口内(200,1200)→(950,1200)90ms，仍showing=true、吸右left231.5294/top435.1814；无误关。batch25-mini-disabled-info：enabled=false时Host无小窗，isShowing仍true/mini=true是controller持有状态，符合“开关仅控制Host渲染”。 |
| C13 | PASS | batch15-basic两实现qoe=false零QoE；batch15-qoe-ended/stopped/abandoned/truncated及batch17-qoe-failed/stall-release：四结束原因、restart TTFF；完整卡顿5468ms，sessionEnd stallCount=1/stallMs=5468；truncatedBelow过滤有独立日志。 |
| C14 | PASS | batch15-basic禁用恢复零Failure/Failover/Recovered；batch6 finite retry/failover/native END_FILE，batch15直播默认持续重连；batch19-options所有原生选项CHECK=true。续播位置缺陷另列F8/N19。 |
| C15 | PASS | batch8 allowHls=false回退/true holding各5次；batch7默认resumeTimeout实测grace约5000ms 15/15；batch16-live-expired及checks：默认maxDuration30s到期、pause结束待机。 |
| C16 | FAIL | batch15-tls 40格：verify=false四种证书均接收，verify=true拒绝expired/wrong/self；原合法IP SAN证书也5/5被拒。batch17-tls-probe 3轮×MP4/HLS：合法DNS localhost证书6/6通过、合法IP127.0.0.1证书6/6失败；原生tls-verify=yes/CA路径1150bytes读回正确；openssl verify IP成功。限定为IP证书兼容问题，未定位到Dart或原生层。 |
| C17 | PASS | batch15-options.json原生读回network=7→2、cache=no→yes、analyzeduration增删且protocol_whitelist保留；WHEP first_frame=8000000/media=6000000/handshake=2000000，再开HTTP全部还原；X-Coverage:42服务端确认。旧CHECK把7.000000与7字符串比错，原始数值为准；batch18重跑数值判据。 |

### E 组

| 编号/事件 | 结论 | 动作、载荷、重复与状态一致性 |
|---|---|---|
| E.MovaReady | PASS | batch1-basic-swap.json：本命令MovaReady=3次，同型相邻载荷相同=2；样例ms=20262 payload={}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaSourceChange | PASS | batch1-basic-swap.json：本命令MovaSourceChange=3次，同型相邻载荷相同=1；样例ms=20262 payload={"uri":"http://127.0.0.1:18080/vod.mp4?t=1793063996403193"}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaPlay | PASS | batch1-basic-swap.json：本命令MovaPlay=2次，同型相邻载荷相同=1；样例ms=20408 payload={}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaPause | PASS | batch1-basic-swap.json：本命令MovaPause=3次，同型相邻载荷相同=2；样例ms=20240 payload={}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaDone | PASS | batch1-playlist.json：本命令MovaDone=1次，同型相邻载荷相同=0；样例ms=54365 payload={}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaSeek | PASS | batch1-basic-swap.json：本命令MovaSeek=7次，同型相邻载荷相同=0；样例ms=24110 payload={"target":5000}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaSeeked | PASS | batch1-basic-swap.json：本命令MovaSeeked=7次，同型相邻载荷相同=0；样例ms=24113 payload={"position":5000}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaBufferChange | FAIL | batch1-basic-swap.json：本命令MovaBufferChange=7次，同型相邻载荷相同=0；样例ms=20262 payload={"buffering":true}。逐事件接收时state对账差异=3。 |
| E.MovaDurationChange | PASS | batch1-basic-swap.json：本命令MovaDurationChange=6次，同型相邻载荷相同=0；样例ms=20347 payload={"duration":40000}。逐事件接收时state对账差异=0。 |
| E.MovaFirstFrame | PASS | batch1-basic-swap.json：本命令MovaFirstFrame=1次，同型相邻载荷相同=0；样例ms=20409 payload={"sinceOpen":191,"signal":"restart"}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaSizeChange | FAIL | batch15-abr.json：本命令MovaSizeChange=7次，同型相邻载荷相同=0；样例ms=553931 payload={"width":640,"height":0}。逐事件接收时state对账差异=1。 |
| E.MovaVolumeChange | PASS | batch1-basic-swap.json：本命令MovaVolumeChange=7次，同型相邻载荷相同=0；样例ms=24673 payload={"value":-10.0}。逐事件接收时state对账差异=0。 |
| E.MovaBrightChange | PASS | batch1-basic-swap.json：本命令MovaBrightChange=6次，同型相邻载荷相同=0；样例ms=25736 payload={"value":-1.0}。逐事件接收时state对账差异=0。 |
| E.MovaRateChange | PASS | batch1-basic-swap.json：本命令MovaRateChange=5次，同型相邻载荷相同=0；样例ms=25749 payload={"value":0.5}。逐事件接收时state对账差异=0。 |
| E.MovaQualityListChange | PASS | batch15-abr.json：本命令MovaQualityListChange=1次，同型相邻载荷相同=0；样例ms=553491 payload={"qualities":["自动:","360p:http://127.0.0.1:18084/high/index.m3u8","180p:http://127.0.0.1:18084/low/index.m3u8"]}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaQualityChange | PASS | batch15-abr.json：本命令MovaQualityChange=4次，同型相邻载荷相同=0；样例ms=553491 payload={"quality":"自动"}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaAbrDownShift | PASS | batch15-abr.json：本命令MovaAbrDownShift=1次，同型相邻载荷相同=0；样例ms=562586 payload={"from":"360p","to":"180p"}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaFitChange | PASS | batch16-audio-start.json：本命令MovaFitChange=1次，同型相邻载荷相同=0；样例ms=248659 payload={"fit":"cover"}。逐事件接收时state对账差异=0。 |
| E.MovaZoomChange | PASS | batch3-09-zoom--1.json：本命令MovaZoomChange=1次，同型相邻载荷相同=0；样例ms=212400 payload={"zoom":-1.0}。逐事件接收时state对账差异=0。 |
| E.MovaLockChange | PASS | batch16-engine-lock.json：本命令MovaLockChange=1次，同型相邻载荷相同=0；样例ms=35029 payload={"value":true}。逐事件接收时state对账差异=0。 |
| E.MovaFullScreenChange | PASS | batch15-lifecycle.json：本命令MovaFullScreenChange=2次，同型相邻载荷相同=0；样例ms=220411 payload={"value":true}。逐事件接收时state对账差异=0。 |
| E.MovaOrientationChange | PASS | batch16-engine-mini-landscape.json：本命令MovaOrientationChange=1次，同型相邻载荷相同=0；样例ms=99278 payload={"orientation":"landscape"}。逐事件接收时state对账差异=0。 |
| E.MovaPipChange | PASS | batch18-pip-x-final.json累计记录：进入true、展开false、再进入true、点X false（438447–438448ms）；各载荷与state.pip一致。同一次原生转换有3个存活engine各收到1条，engine标识分别513470000/745521959/834304684，未见同一engine重复；进入/退出截图及activity对账见A18。 |
| E.MovaMiniChange | PASS | batch16-engine-mini-host.json：本命令MovaMiniChange=1次，同型相邻载荷相同=0；样例ms=92721 payload={"mini":true}。逐事件接收时state对账差异=0。 |
| E.MovaTimeShiftChange | PASS | batch16-live-start.json：本命令MovaTimeShiftChange=2次，同型相邻载荷相同=0；样例ms=272467 payload={"behind":12000}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaLiveEdgeReach | PASS | batch15-live-step0-0.json：本命令MovaLiveEdgeReach=1次，同型相邻载荷相同=0；样例ms=125432 payload={}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaPreviewBlock | PASS | batch15-preview-blocked.json：本命令MovaPreviewBlock=4次，同型相邻载荷相同=3；样例ms=370641 payload={"reason":"network"}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaSttBlock | PASS | batch1-basic-swap.json：本命令MovaSttBlock=1次，同型相邻载荷相同=0；样例ms=25765 payload={"reason":"disabled"}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaSwapChange | PASS | batch15-adResume.json：本命令MovaSwapChange=30次，同型相邻载荷相同=0；样例ms=281519 payload={"phase":"warming"}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaErrorEvent | PASS | batch15-hang-2s-0.json：本命令MovaErrorEvent=2次，同型相邻载荷相同=0；样例ms=68013 payload={"error":"Failed to open http://127.0.0.1:18080/hang?t=1793068221654008."}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaPlayFailure | PASS | batch15-hang-2s-0.json：本命令MovaPlayFailure=1次，同型相邻载荷相同=0；样例ms=68016 payload={"kind":"nativeEndError","action":"MovaRecoveryAction.giveUp","attempt":1,"isLive":false,"sourceIndex":0}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaRecovered | PASS | batch2-failover.json：本命令MovaRecovered=1次，同型相邻载荷相同=0；样例ms=78247 payload={"attempts":1}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaFailover | PASS | batch15-recovery-liveAlternatives.json：本命令MovaFailover=1次，同型相邻载荷相同=0；样例ms=54097 payload={"from":0,"to":1,"uri":"http://127.0.0.1:18080/other404.mp4?t=1793068209673598"}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。 |
| E.MovaStandbyChange | PASS | batch16-standby-off.json：本命令MovaStandbyChange=1次，同型相邻载荷相同=0；样例ms=317110 payload={"phase":"resuming","reason":"woke","mode":"null"}。逐事件接收时state对账差异=0。 |
| E.MovaStandbyResume | PASS | batch7-standby-core.log S1 GOP25/50/100各5次共15：elapsed约5000ms、signal=grace；随后state=off；batch8 C decodeOnly为1ms/signal=null 5/5。恢复事件时间是兜底时间，另有实际出画属性约百余ms，不能混用。 |
| E1 | FAIL | batch15-lifecycle.json真实序列：open清理Pause/Duration(0)/Size(0)→Play→SourceChange→Ready→Duration/Size→FirstFrame(restart)→…→Pause/Done。若按矩阵箭头Ready→Size→FirstFrame→Play严格判定则不符；Play表达请求意图、早于真实首帧，不等于播放器提前出画。生命周期F1仍无异常完成。 |
| E2 | PASS | HE V12 foreignEvents=[] ×5，默认关闭swap/standby/recovery无相关事件；batch1-basic*.json也count=0（功能动作报告不计QoE）。 |

### U 组

| 编号 | 结论 | 测试点与缺失证据 |
|---|---|---|
| U1 | PASS | batch16 View复用/options/route/ticker/surface及卸载；batch22 Feed滚动真实视频/like回调；Default/Bilibili/Minimal/Mini与Douyin(Feed)均有PNG、components输出，patch显示PATCH VISIBLE。batch20启动日志Impeller Vulkan/OpenGLES；封面完整分支另列N15。 |
| U2 | PASS | batch16 View复用/options/route/ticker/surface及卸载；batch22 Feed滚动真实视频/like回调；Default/Bilibili/Minimal/Mini与Douyin(Feed)均有PNG、components输出，patch显示PATCH VISIBLE。batch20启动日志Impeller Vulkan/OpenGLES；封面完整分支另列N15。 |
| U3 | FAIL | batch25-route-player.png：TopBar有标题、PiP/fit/方向/全屏，无返回按钮；Android BACK能正常退路由（route-back），不是TopBar返回动作。矩阵要求的TopBar返回能力未提供；支持态PiP与真实方向切换已测，不支持平台隐藏分支没有自然设备样本。 |
| U4 | PASS | batch19-live-controls.png为DVR/behind/backToLive形态；batch25 preview-during dragging=true/previewAt=13647；连续移动会防抖等待，batch26-preview-held.png在真实DOWN/MOVE后停留显示彩色VTT crop气泡/00:25。UP后正常seek、气泡消失；VOD与live栏均有真实截图。 |
| U5 | FAIL | batch25-speed-button实际点击1→1.25x，为循环切档按钮，无倍速菜单；CenterPlay真实点击可播放、state及Play事件有记录，HUD亮度/音量/进度见batch16/18。FAIL限矩阵要求的菜单形态。 |
| U6 | FAIL | 矩阵要求长按倍速：batch18-longpress-during在真实播放中注入1800ms长按，during/after rate均1；默认GestureLayer无longPress配置/处理。双击实际为±10s seek（batch18-doubletap-seek），左右亮度/音量、横滑、锁定均通过。此项为矩阵能力假设差异；Douyin另测。 |
| U7 | FAIL | 实际通过：batch25-danmaku滚动文本；batch17四格式字幕；NextUp立即播放点击后title=Coverage vod.mp4/position40ms；广告countdown/跳过PNG且VISUAL_AD_EVENT started→clicked→skipped，语义定位SKIP_BUTTON=true；batch22 Feed双击like=true/count1。FAIL限C8中NextUp不含数字倒计时。 |
| U8 | PASS | batch22真实拖动吸左left12/top434.20；转屏PNG钳回。修正原甩动坐标：batch27-mini-real-fling从窗口内(200,1200)→(950,1200)90ms，仍showing=true、吸右left231.5294/top435.1814；无误关。batch25-mini-disabled-info：enabled=false时Host无小窗，isShowing仍true/mini=true是controller持有状态，符合“开关仅控制Host渲染”。 |
| U9 | PASS | batch6 HE V9前后台5/5、V10 route/Ticker/关闭守卫各5次、V11 PiP豁免5/5；batch16-view-route配置root RouteObserver、ticker隐藏/恢复有ROUTE_HIDDEN及状态，feed滚动池见batch15+16；小窗连续播放见batch16，不要求外部业务go_router才能验证此库API。 |

### F 组

| 编号 | 结论 | 测试点与缺失证据 |
|---|---|---|
| F1 | PASS | batch15-lifecycle.json：真实open/seek/rate/fullscreen/change/naturalDone/dispose无异常，done=1；原始序列包含open前Pause/归零、Play在Ready前、Size分宽高两次更新、FirstFrame(restart)后Done；不强加示意箭头顺序。 |
| F2 | PASS | batch19-live-dvr/behind/backedge：真实18081/live.m3u8；seek3s，TimeShiftChange behind随播放变化；backEdge到position12000ms、LiveEdgeReach，窗口12s；点播backEdge无副作用见basic，holding重载保护5/5见batch7 S13。 |
| F3 | FAIL | 原生FFI最终版：batch23-hls-native普通首切8183→8143ms(-40)，第二切target8823但RESTART=23ms并从头走；普通5切1通过4失败。batch24-hls-native-swap也1/5；paused第二切8263→23ms丢位置，之后目标已0附近的“通过”不算有效续播样本。ABR限速下调通过，不抵消重复手切缺陷。旧batch17/19/21的等待/瞬时读回判据作废，非库失败依据。 |
| F4 | PASS | batch15-adResume.json：5次广告→正片epoch=2，首个原生time-pos对比误差全部0ms（读取延迟0–14ms）；batch11 V12/V14及batch15-swap验证pod/失败降级/关闭态。 |
| F5 | PASS | batch18-pip-visible.activity.txt：mode=pinned、mLastReportedPictureInPictureMode=true；enter返回true。展开pip=false且继续播放。X路径用adb tap(750,2050)后等450ms、tap(960,1965)，before-x.png有系统X，after-x.png关闭；pip-x-final state.pip=false/playing=false，native无pinned。原始JSON含true/false变更。 |
| F6 | PASS | batch7/8/16：off/holding/fallback/resuming迁移，pause结束、hiddenTicker/source变化重hold、后台降级；S7 mediacodec-copy恢复20/20、无codecopen失败；S13 vid=no/mute=yes保护5/5。S1主信号未落地15/15 grace≈5s，是允许的超时兜底；保留性能/信号缺口，不再把它当作功能FAIL。S14 Android holding黑屏，恢复正常。 |
| F7 | PASS | batch15-basic两实现qoe=false零QoE；batch15-qoe-ended/stopped/abandoned/truncated及batch17-qoe-failed/stall-release：四结束原因、restart TTFF；完整卡顿5468ms，sessionEnd stallCount=1/stallMs=5468；truncatedBelow过滤有独立日志。 |
| F8 | FAIL | 有限重试策略复跑：V5 5/5、V7 10/10（好/坏备用各5）、V8 10/10；V6 0/5，首帧后40ms起从头增长，前位置2520–2680ms。batch6-he-recovery-guard.log；明确与CLAUDE.md待真机确认的续播修复不一致。 |
| F9 | PASS | batch15-basic两实现audioOnly handle=null/size0x0、position推进；batch16-audio-start/poster与video对照截图、audio/video.cpu.txt和meminfo采样；音量系统保持可见。 |
| F10 | PASS | batch15 preview真实VTT/原生抽帧及cache两层命中、cancel/clear；batch23-preview-probe真实connectivity插件allowHeavy=true、wifiOnly获得7次thumb通知；offline把VTT源指向拒连127.0.0.1:9，抽帧兜底3次/磁盘命中1/内存命中4无崩。此处断网是缩略图源网络不可达，视频18080仍可达；未把never策略冒充断网。 |
| F11 | PASS | batch17-subtitles.json：SRT/ASS/WebVTT/mov_text各native sub-text非空、轨道decoder明确；batch17-subtitles.srt/ass/vtt/movtext.png保留实际画面。 |
| F12 | PASS | batch9-cpu-summary.json：normal CPU样本[92.8,92.8,96.4,85.7,96.4]；B[7.1,10.7,10.7,7.1,10.7]；C[135,113,121,114,114,114]；D[7.1,10.7,3.5,7.1,7.1,7.1]。每阶段15s×3，边界±2s剔除；为单核百分比，USB供电不能据此报电池能耗。audioOnly对照见batch16。 |
| F13 | PASS | batch15-feed：100+20次切换池3引擎回收；batch12-pump V6三引擎restart=[1,1,1]→[2,1,2]；销毁时ctrl/on最差间隔62/60ms<100；batch15-dispose120完成。 |
| F14 | PASS | batch12-pump.log：release native restart实际2次、三个引擎隔离、qoe:false客户端0；created=14 destroyed=14；END_FILE真实触发见batch6 V8及batch15-recovery。 |
| F15 | BLOCKED | external-prerequisites.json：WHEP模板127.0.0.1:38889/test/whep不可达，未提供publisher/信令服务/UDP38189及relay38190；无15s真实播放证据。仅N4的WHEP选项原生读回通过。 |
| F16 | PASS | 已逐项复测历史缺陷：PiP展开和X现均复位（batch18）；广告1x/恢复用户2x或1.5x、退役不复位方向、pod第二条真换指均batch11每项3次。旧缺陷本轮未复现；F16的PASS表示复现任务完成，不表示保留旧bug。 |

## FAIL 最小复现

（批次 0 的旧快照已作废）最终 23 个 FAIL 的最小复现见文末「最终批次」，**终审判定见文末「终审（Claude + opus 复核）」**：其中只有 F3/A17 是真库缺陷（已修），A8/A9 是两个小钳制缺陷（已修），其余为降级或误报。

## 与 CLAUDE.md 的差异

（批次 0 的旧快照已作废）起点 `flutter test` 为 1503（CLAUDE.md 记 1472，其后多了 31 项）。F3/F8 两条与 CLAUDE.md 的差异见文末「终审」：F8 是验证脚本缺陷，CLAUDE.md 的 V6 修复结论在 Android 真机上成立。

## 批次 0 追加：解除锁屏与构建前置

- 设备已解锁，证据 `example/tool/coverage_evidence/preflight.unlocked.window.txt`：两处 `isKeyguardShowing=false`，屏幕 fully on。临时设置 USB 亮屏常驻；原 `stay_on_while_plugged_in=0`，结束时恢复。
- 发现依赖包 arm64 `libmpv.so` 仅 132 字节 LFS 指针，所需对象 SHA-256 `798cde9e27e3761dd5f8f065693e4669b5499d5807618f81a74e0d3a88dc230b`、6357872 字节。各 ABI 清单见 `example/tool/coverage_evidence/native_artifacts.json`。
- 没有改写 `packages/`：从设备已安装同包 APK（先备份到 `example/tool/coverage_evidence/installed-before.apk`）只读提取二进制，SHA-256 与 LFS 逐项核对完全一致。`coverage_repack.py` 仅替换构建 APK 中的指针条目，zipalign + 原 debug keystore 重签，`apksigner verify` 成功；日志 `example/tool/coverage_evidence/repack.log`。
- 首次 `--no-pub` release 构建失败：GeneratedPluginRegistrant.java 引用缺失的 `integration_test.IntegrationTestPlugin`；重新标准 `flutter build apk --release --target-platform android-arm64 -t lib/main_coverage_api.dart` 自动重新生成后成功（246.5s、91.8MB）。原始日志 `coverage_build.log` / `coverage_build_retry.log`，均在 `example/tool/`。
- 新增验证页 `example/lib/main_coverage_api.dart`：`flutter analyze --no-pub lib/main_coverage_api.dart` 0 issues。此为验证工具检查，尚不是任何库功能 PASS。
- 发现另一非本会话启动的同入口构建、flutter test 与 `coverage_*_restart.log`。未终止或改写其工作；已请求确认设备是否被其他会话同时使用。后续真机操作需保证无安装/启动冲突，否则相关证据作废。

## 第二次启动：批次 0 更新

- 已解除上次锁屏阻塞：`restart.unlocked.window.txt` 中两个显示区域均 `isKeyguardShowing=false`、`mScreenOnFully=true`；截图 `example/tool/coverage_evidence/restart.unlocked.png`。上文 K 是历史快照，以下批次取代。
- 重跑基线：`02:00 +1503: All tests passed!`；`No issues found! (ran in 34.6s)`。日志 `example/tool/coverage_baseline_test_restart.log` / `coverage_baseline_analyze_restart.log`。
- 已复用上次仍运行的源服务（18080 的 vod.mp4 返回 HTTP 200，Content-Length=1789058）；adb reverse 18080/18081 已设。
- 原有 Windows generated_plugin_registrant.cc/.h/generated_plugins.cmake 与 packages 中二进制改动均在本次开始时已存在，未覆盖。
- release 构建 `coverage_build_retry.log` 成功（91.8MB）；安装原包名返回 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`。改由 tool/coverage.init.gradle 赋独立 coverage 应用 ID 构建，保留原安装及数据。
- 总口径补齐 N23：A33+C17+E38+U9+F16+N23=136。以下 N 表为待执行台账，逐批更新。

### N 组（第二次启动新增台账）

| 编号 | 结论 | 测试点及证据缺口 |
|---|---|---|
| N1 | PASS | batch15-options原生network默认5s/配置1.2s向上取整2；源7优先、WHEP单位微秒及复原见N4。hangDefault-0..2和hang-2s-0..2真实黑洞END_FILE；默认3次[5282,5274,5256]ms均值5270.7ms；network=2s三次[2247,2254,2250]ms均值2250.3ms，65s是Dart派生兜底，并非mpv实际默认5s。 |
| N2 | PASS | batch15-options N2.derived=true：http65/whep起播85/卡顿10/watchdogOff=null/clear=null；batch15-watchoff：1s卡顿阈值关闭后持续buffering5s无failure；真实黑洞以nativeEndError先到。 |
| N3 | PASS | batch15-recovery-liveDefault/liveLegacy/liveAlternatives与batch2-live-reconnect：默认直播第3次仍retry；显式cap7退避1078/2059/4067/8092/15064/15088/15064ms；legacy有限giveUp，多地址retriesPerAddress=2有sourceIndex事件。 |
| N4 | PASS | batch15-options.json原生读回network=7→2、cache=no→yes、analyzeduration增删且protocol_whitelist保留；WHEP first_frame=8000000/media=6000000/handshake=2000000，再开HTTP全部还原；X-Coverage:42服务端确认。旧CHECK把7.000000与7字符串比错，原始数值为准；batch18重跑数值判据。 |
| N5 | PASS | batch6-he-recovery-guard.log V8拒连约79ms、404约120ms（各5次），均nativeEndError；与Windows约5s不同；batch4首帧信号restart，错误订阅不代替首帧。 |
| N6 | PASS | batch2-failover Recovered后error=null；batch15-recovery多模式giveup CHECK=true且buffering=false，BufferChange(false)有原始event；拒连及404均真实END_FILE。 |
| N7 | PASS | batch15-live-step0/2000-0..2.json：真实直播各11s，durationStep=0/2s有时间戳对比，首非零/open归零即时放行；VOD basic的duration不受节流。 |
| N8 | PASS | batch15-hooks及hooks-swap：open放行true，beforeOpen拒绝/被取代/已销毁false；jumpTo拒绝不前进；batch15-recovery RECOVERY_OPEN坏地址accepted=true，之后走恢复。 |
| N9 | PASS | batch18-pip-visible.activity.txt：mode=pinned、mLastReportedPictureInPictureMode=true；enter返回true。展开pip=false且继续播放。X路径用adb tap(750,2050)后等450ms、tap(960,1965)，before-x.png有系统X，after-x.png关闭；pip-x-final state.pip=false/playing=false，native无pinned。原始JSON含true/false变更。 |
| N10 | PASS | batch11-review.log V10/V12/V12b/V13a/V13b/V14每项3次：广告采样最高1x，内容恢复2x/1.5x；退役dispose不复位全局方向；pod第二条真epoch提交。batch15-swap rate1.5/1明确；采样不声称穷尽微任务窗口。 |
| N11 | PASS | Q13A/B/C各5/5：仅影子mute=yes、active=no；提交中holding时live mute=yes/vid=no；先唤醒影子仍mute=yes，提交后恢复no。40个MARK系统音量快照一致，见batch10-volume-summary.json；无写系统音量证据。 |
| N12 | FAIL | 首帧功能通过batch4，但矩阵要求open同步归零：batch15-basic OPEN_SYNC调用open后立即读仍duration40000/rendered=true/旧title，之后异步归零；两实现均有记录。属于同步时机的矩阵期望差异，实际open是异步接口。 |
| N13 | PASS | batch12-pump客户端开关计数及created14/destroyed14；batch15-lazy构造0/open0/首次handle1，VideoController懒创建。 |
| N14 | PASS | batch16-engine/swap fitRebuild检查均true：declarative cover→用户contain→rebuild仍contain；三种fit初值/按钮截图已保存。 |
| N15 | PASS | batch25 Feed连续帧1封面teal占92.12%，帧2首帧后0；video换源重盖占92.93%、恢复后0；audioOnly封面teal像素2079525常驻。batch28自定义posterFade=2s真实中间帧像素(500,600)：(0,150,136)→(0,99,90)→(0,37,34)→黑，证明渐隐，未用墙钟报精确时长。 |
| N16 | PASS | batch22-controls.xml实际COVERAGE FIT文案；batch25-spinner-custom.png为60逻辑尺寸/8 stroke/#FFFF0000红圈，spinner-disabled.png消失；minimal无栏无手势，error-visible/error-disabled.png分别有/无原生404错误文字。默认外观见batch3及batch25 normal。 |
| N17 | PASS | batch16-view-same/null/source/options/error等：同源复用、null暂停、options重建、source变化，故意beforeOpen抛出收到onOpenError；batch15-options sameAs考虑alternatives；卸载见widget-unmount-final。 |
| N18 | PASS | batch6 HE V9前后台5/5、V10 route/Ticker/关闭守卫各5次、V11 PiP豁免5/5；batch16-view-route配置root RouteObserver、ticker隐藏/恢复有ROUTE_HIDDEN及状态，feed滚动池见batch15+16；小窗连续播放见batch16，不要求外部业务go_router才能验证此库API。 |
| N19 | FAIL | 重试/切换事件及sourceIndex子项通过；卡顿重试后续播失败：batch6-he-recovery-guard.log HE V6 0/5，失败前2520–2680ms，恢复后从40ms增长，1.5s内未回原位置；与F8同一缺陷。 |
| N20 | PASS | batch7/8/16：off/holding/fallback/resuming迁移，pause结束、hiddenTicker/source变化重hold、后台降级；S7 mediacodec-copy恢复20/20、无codecopen失败；S13 vid=no/mute=yes保护5/5。S1主信号未落地15/15 grace≈5s，是允许的超时兜底；保留性能/信号缺口，不再把它当作功能FAIL。S14 Android holding黑屏，恢复正常。 |
| N21 | PASS | batch15-testing.json stagedSourceOptions包含network-timeout=7，平台端口替身无操作；batch11 Android换指/转场无Windows快照守卫副作用。 |
| N22 | BLOCKED | 除assert外均已实测：hooks异步保护、重映射横向volume/左竖seek、STT失败回滚重试、crop零写。batch28延迟VTT BEGIN=1793072460.8985/END=2463.3994，换源在2461.4741；晚到非空thumb=0、previewCurrent=null。release两种入口及profile尝试--enable-asserts均在Flutter SDK defaultTargetPlatform/_environmentCache常量求值失败，见assert-aot-*-build-failed.log；断言设备分支不能记PASS，未改SDK/库来绕过。 |
| N23 | PASS | batch15-basic两实现qoe=false零QoE；batch15-qoe-ended/stopped/abandoned/truncated及batch17-qoe-failed/stall-release：四结束原因、restart TTFF；完整卡顿5468ms，sessionEnd stallCount=1/stallMs=5468；truncatedBelow过滤有独立日志。 |

## 批次 1：A 基础、playlist/testing 与 N 配置子项

- 原始证据统一在 `example/tool/coverage_evidence/`，每次含 `.json`、`.logcat.txt`、`.window.txt`、`.audio.txt`、`.activity.txt`、`.meminfo.txt` 与 `.png`。
- 本次 LFS Codeup 404，GitHub smudge 成功；原生产物 SHA-256 与指针一致 `798cde9e27e3761dd5f8f065693e4669b5499d5807618f81a74e0d3a88dc230b`，APK 核验见 `isolated-apk.json`。未写 packages 文件。

### batch1-basic

- `A1.broadcast` 子项 FAIL：`all streams broadcast swap=false`
- `A3.audio` 子项 PASS：`handle=null`
- `A5.paused` 子项 PASS：`{playing: false, intent: false, buffering: false, duration: 40000, position: 0, size: 0x0, volume: 65.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: false, epoch: 0, sourceIndex: 0, standby: off}`
- `A4` 子项 PASS：`supported=true`
- `A1.progress` 子项 PASS：`0:00:02.144778 -> 0:00:03.144866`
- `A6.pause` 子项 PASS：`{playing: false, intent: false, buffering: false, duration: 40000, position: 3144, size: 0x0, volume: 65.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A7.seek` 子项 PASS：`target=5000 landed=5000`
- `A7.seek` 子项 PASS：`target=10000 landed=10000`
- `A7.seek` 子项 PASS：`target=15000 landed=15000`
- `A7.seek` 子项 PASS：`target=5000 landed=5000`
- `A7.seek` 子项 PASS：`target=10000 landed=10000`
- `A7.negative` 子项 PASS：`0:00:00.000000`
- `A8.clamp` 子项 FAIL：`{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: -10.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A8.clamp` 子项 PASS：`{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 0.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A8.clamp` 子项 PASS：`{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 1.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A8.clamp` 子项 PASS：`{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 50.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A8.clamp` 子项 PASS：`{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 100.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A8.clamp` 子项 FAIL：`{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 110.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A9.clamp` 子项 FAIL：`{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: -1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A9.clamp` 子项 PASS：`{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 0.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A9.clamp` 子项 PASS：`{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 0.5, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A9.clamp` 子项 PASS：`{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A9.clamp` 子项 FAIL：`{playing: false, intent: false, buffering: true, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 2.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A21.hide` 子项 PASS：`false`
- `A21.hud` 子项 PASS：`MovaHud.seek`
- `A22` 子项 PASS：`[pause:{}, sourceChange:{uri: http://127.0.0.1:18080/vod.mp4?t=1793063978464421}, play:{}, pause:{}, play:{}, pause:{}, seek:{targetMs: 5000}, seeked:{positionMs: 5000}, seek:{targetMs: 10000}, seeked:{positionMs: 10000}, seek:{targetMs: 15000}, seeked:{positionMs: 15000}, seek:{targetMs: 5000}, seeked:{positionMs: 5000}, seek:{targetMs: 10000}, seeked:{positionMs: 10000}, seek:{targetMs: 8000}, seeked:{positionMs: 8000}, seek:{targetMs: 0}, seeked:{positionMs: 0}, coverage:{probe: 42}, play:{probe: 43}]`
- `A10.persist` 子项 PASS：`{playing: false, intent: false, buffering: false, duration: 20000, position: 0, size: 0x0, volume: 30.0, brightness: 0.5, rate: 1.5, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: false, epoch: 0, sourceIndex: 0, standby: off}`
- `E2.disabled` 子项 PASS：`count=0`
- `C13.off` 子项 PASS：`QoE reports=24`
- `A1.closed` 子项 PASS：`counts=[61, 61, 49, 49, 23, 23, 9, 9] closed=[true, true, true, true, true, true, true, true]`
- 脚本终止：`Assertion failed: "[Player] has been disposed"`；调用栈见对应 JSON。

### batch1-basic-swap

- `A1.broadcast` 子项 FAIL：`all streams broadcast swap=true`
- `A3.audio` 子项 PASS：`handle=null`
- `A5.paused` 子项 PASS：`{playing: false, intent: false, buffering: false, duration: 40000, position: 0, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: false, epoch: 0, sourceIndex: 0, standby: off}`
- `A4` 子项 PASS：`supported=true`
- `A1.progress` 子项 PASS：`0:00:02.146366 -> 0:00:03.195118`
- `A6.pause` 子项 PASS：`{playing: false, intent: false, buffering: false, duration: 40000, position: 3195, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A7.seek` 子项 PASS：`target=5000 landed=5000`
- `A7.seek` 子项 PASS：`target=10000 landed=10000`
- `A7.seek` 子项 PASS：`target=15000 landed=15000`
- `A7.seek` 子项 PASS：`target=5000 landed=5000`
- `A7.seek` 子项 PASS：`target=10000 landed=10000`
- `A7.negative` 子项 PASS：`0:00:00.000000`
- `A8.clamp` 子项 FAIL：`{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: -10.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A8.clamp` 子项 PASS：`{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 0.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A8.clamp` 子项 PASS：`{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 1.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A8.clamp` 子项 PASS：`{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 50.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A8.clamp` 子项 PASS：`{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 100.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A8.clamp` 子项 FAIL：`{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 110.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A9.clamp` 子项 FAIL：`{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 110.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A9.clamp` 子项 FAIL：`{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: -1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A9.clamp` 子项 FAIL：`{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 0.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A9.clamp` 子项 FAIL：`{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 0.5, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A9.clamp` 子项 FAIL：`{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 0.5, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}`
- `A21.hide` 子项 PASS：`false`
- `A21.hud` 子项 FAIL：`MovaHud.none`
- `A22` 子项 PASS：`[pause:{}, sourceChange:{uri: http://127.0.0.1:18080/vod.mp4?t=1793063996403193}, play:{}, pause:{}, play:{}, pause:{}, seek:{targetMs: 5000}, seeked:{positionMs: 5000}, seek:{targetMs: 10000}, seeked:{positionMs: 10000}, seek:{targetMs: 15000}, seeked:{positionMs: 15000}, seek:{targetMs: 5000}, seeked:{positionMs: 5000}, seek:{targetMs: 10000}, seeked:{positionMs: 10000}, seek:{targetMs: 7999}, seeked:{positionMs: 7999}, seek:{targetMs: 0}, seeked:{positionMs: 0}, coverage:{probe: 42}, play:{probe: 43}]`
- `A10.persist` 子项 PASS：`{playing: false, intent: false, buffering: false, duration: 20000, position: 0, size: 0x0, volume: 30.0, brightness: 0.5, rate: 1.5, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: false, epoch: 0, sourceIndex: 0, standby: off}`
- `E2.disabled` 子项 PASS：`count=0`
- `C13.off` 子项 PASS：`QoE reports=24`
- `A1.closed` 子项 PASS：`counts=[59, 59, 47, 47, 24, 24, 9, 9] closed=[true, true, true, true, true, true, true, true]`
- 脚本终止：`Assertion failed: "[Player] has been disposed"`；调用栈见对应 JSON。

### batch1-testing

- `A33` 子项 PASS：`kernels=1 pip=false`

### batch1-playlist

- `A28.start` 子项 PASS：`index=0`
- `A28.end` 子项 PASS：`index=1`
- `A28.auto` 子项 PASS：`index=1`

### batch2-options

- `N4.applied` 子项 FAIL：`{network-timeout: 7.000000, demuxer-lavf-o: seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto,analyzeduration=123456, cache: no, vid: no, mute: no}`
- `N1.network` 子项 FAIL：`{network-timeout: 2.000000, demuxer-lavf-o: seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto, cache: yes, vid: no, mute: no}`
- `N4.restore` 子项 PASS：`{before: {network-timeout: 5.000000, demuxer-lavf-o: seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto, cache: yes, vid: no, mute: no}, custom: {network-timeout: 7.000000, demuxer-lavf-o: seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto,analyzeduration=123456, cache: no, vid: no, mute: no}, restored: {network-timeout: 2.000000, demuxer-lavf-o: seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto, cache: yes, vid: no, mute: no}}`
- `N2.derived` 子项 PASS：`http=65,whepStart=85,whepStall=10,watchdogOff=null,clear=null`
- `C17.pick` 子项 PASS：`[http://a, http://b]`

## 批次 2：恢复、直播退避与异步拦截

### batch2-failover

- PlayFailure 事件戳 ms：`[78138]`；间距：`[]`。
- `{"ms": 78288, "kind": "CHECK", "id": "N6.clear", "pass": true, "detail": "sourceIndex=1 error=null"}`
- `{"ms": 78288, "kind": "CHECK", "id": "N19.failover", "pass": true, "detail": "[MovaPause, MovaDurationChange, MovaBufferChange, MovaSizeChange, MovaPlay, MovaSourceChange, MovaReady, MovaBufferChange, MovaErrorEvent, MovaPlayFailure, MovaFailover, MovaPause, MovaBufferChange, MovaPlay, MovaBufferChange, MovaDurationChange, MovaBufferChange, MovaRecovered, MovaFirstFrame]"}`
- `{"ms": 78289, "kind": "RECOVERY_END", "mode": "failover", "state": {"playing": true, "intent": true, "buffering": false, "duration": 40000, "position": 0, "size": "0x0", "volume": 30.0, "brightness": 1.0, "rate": 1.0, "fit": "contain", "zoom": 1.0, "locked": false, "fullscreen": false, "orientation": "auto", "pip": false, "mini": false, "rendered": true, "epoch": 0, "sourceIndex": 1, "standby": "off"}, "error": "null"}`

### batch2-live-reconnect

- PlayFailure 事件戳 ms：`[83281, 84359, 86418, 90485, 98577, 113641, 128729, 143793]`；间距：`[1078, 2059, 4067, 8092, 15064, 15088, 15064]`。
- `{"ms": 143811, "kind": "CHECK", "id": "N6.giveup", "pass": true, "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/not-found.mp4?t=1793064059413157) buffering=false"}`
- `{"ms": 143811, "kind": "RECOVERY_END", "mode": "live", "state": {"playing": false, "intent": true, "buffering": false, "duration": 0, "position": 0, "size": "0x0", "volume": 30.0, "brightness": 1.0, "rate": 1.0, "fit": "contain", "zoom": 1.0, "locked": false, "fullscreen": false, "orientation": "auto", "pip": false, "mini": false, "rendered": false, "epoch": 0, "sourceIndex": 0, "standby": "off"}, "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/not-found.mp4?t=1793064059413157)"}`

### batch2-network-hang

- PlayFailure 事件戳 ms：`[149780]`；间距：`[]`。
- `{"ms": 149822, "kind": "CHECK", "id": "N6.giveup", "pass": true, "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793064123693978) buffering=false"}`
- `{"ms": 149823, "kind": "RECOVERY_END", "mode": "hang", "state": {"playing": false, "intent": true, "buffering": false, "duration": 0, "position": 0, "size": "0x0", "volume": 30.0, "brightness": 1.0, "rate": 1.0, "fit": "contain", "zoom": 1.0, "locked": false, "fullscreen": false, "orientation": "auto", "pip": false, "mini": false, "rendered": false, "epoch": 0, "sourceIndex": 0, "standby": "off"}, "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793064123693978)"}`

### batch2-hooks

- PlayFailure 事件戳 ms：`[]`；间距：`[]`。
- `{"ms": 153607, "kind": "CHECK", "id": "N8.reject", "pass": true, "detail": "beforeOpen=false"}`
- `{"ms": 153669, "kind": "CHECK", "id": "N8.accept", "pass": true, "detail": "accepted=true"}`
- `{"ms": 154099, "kind": "CHECK", "id": "N22.stalePlay", "pass": true, "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off}"}`
- `{"ms": 155315, "kind": "HOOK_SEEK_FINAL", "playing": false, "intent": false, "buffering": false, "duration": 20000, "position": 23, "size": "0x0", "volume": 30.0, "brightness": 1.0, "rate": 1.0, "fit": "contain", "zoom": 1.0, "locked": false, "fullscreen": false, "orientation": "auto", "pip": false, "mini": false, "rendered": true, "epoch": 0, "sourceIndex": 0, "standby": "off"}`
- `{"ms": 155315, "kind": "HOOK_PLAYLIST", "index": 0}`
- `{"ms": 155346, "kind": "CHECK", "id": "N8.disposed", "pass": true, "detail": "disposed=false"}`

## 批次 3：真实画面、填充/缩放、音量/亮度与方向

- batch3 JSON 的 `window`/`padding` 仅输出 Instance of，不能当尺寸证据；尺寸取 PNG IHDR 与 dumpsys。
- 脚本误枚举 fitWidth/fitHeight/none/scaleDown（MovaFit 只有 contain/cover/fill）产生4条 ArgumentError，已修验证脚本；这4条不是库 FAIL。
- `batch3-26-fullscreen-true.png`：2376×1080；窗口标志：`    mAttrs={(0,330)(fillx750) sim={adjust=pan} layoutInDisplayCutoutMode=always ty=NAVIGATION_BAR_PANEL hwFlags=#0 hwExtFlags=#0 ohWindowId=0 isEmuiStyle=0 statusBarColor=#0 navigationBarColor=#0 fmt=TRANSLUCENT;     mHasSurface=false isReadyForDisplay()=false mWindowRemovalAllowed=false;     mAttrs={(110,1130)(162x415) gr=TOP LEFT CENTER sim={state=unchanged adjust=nothing} ty=NAVIGATION_BAR_PANEL hwFlags=#8000000 hwExtFlags=#0 ohWindowId=0 isEmuiStyle=0 statusBarColor=#0 navigationBarColor=#0 fmt=TRANSPARENT;     mHasSurface=false isReadyForDisplay()=false mWindowRemovalAllowed=false`。
- `batch3-27-fullscreen-false.png`：1080×2376；窗口标志：`    mAttrs={(0,1626)(fillx750) sim={adjust=pan} layoutInDisplayCutoutMode=always ty=NAVIGATION_BAR_PANEL hwFlags=#0 hwExtFlags=#0 ohWindowId=0 isEmuiStyle=0 statusBarColor=#0 navigationBarColor=#0 fmt=TRANSLUCENT;     mHasSurface=false isReadyForDisplay()=false mWindowRemovalAllowed=false;     mAttrs={(0,1130)(162x415) gr=TOP LEFT CENTER sim={state=unchanged adjust=nothing} ty=NAVIGATION_BAR_PANEL hwFlags=#8010000 hwExtFlags=#0 ohWindowId=0 isEmuiStyle=0 statusBarColor=#0 navigationBarColor=#0 fmt=TRANSPARENT;     mHasSurface=false isReadyForDisplay()=false mWindowRemovalAllowed=false`。
- `batch3-28-orientation-landscape.png`：2376×1080；窗口标志：`    mAttrs={(0,330)(fillx750) sim={adjust=pan} layoutInDisplayCutoutMode=always ty=NAVIGATION_BAR_PANEL hwFlags=#0 hwExtFlags=#0 ohWindowId=0 isEmuiStyle=0 statusBarColor=#0 navigationBarColor=#0 fmt=TRANSLUCENT;     mHasSurface=false isReadyForDisplay()=false mWindowRemovalAllowed=false;     mAttrs={(110,1130)(162x415) gr=TOP LEFT CENTER sim={state=unchanged adjust=nothing} ty=NAVIGATION_BAR_PANEL hwFlags=#8000000 hwExtFlags=#0 ohWindowId=0 isEmuiStyle=0 statusBarColor=#0 navigationBarColor=#0 fmt=TRANSPARENT;     mHasSurface=false isReadyForDisplay()=false mWindowRemovalAllowed=false`。
- `batch3-29-orientation-portrait.png`：1080×2376；窗口标志：`    mAttrs={(0,1626)(fillx750) sim={adjust=pan} layoutInDisplayCutoutMode=always ty=NAVIGATION_BAR_PANEL hwFlags=#0 hwExtFlags=#0 ohWindowId=0 isEmuiStyle=0 statusBarColor=#0 navigationBarColor=#0 fmt=TRANSLUCENT;     mHasSurface=false isReadyForDisplay()=false mWindowRemovalAllowed=false;     mAttrs={(0,1130)(162x415) gr=TOP LEFT CENTER sim={state=unchanged adjust=nothing} ty=NAVIGATION_BAR_PANEL hwFlags=#8010000 hwExtFlags=#0 ohWindowId=0 isEmuiStyle=0 statusBarColor=#0 navigationBarColor=#0 fmt=TRANSPARENT;     mHasSurface=false isReadyForDisplay()=false mWindowRemovalAllowed=false`。
- `batch3-30-orientation-auto.png`：1080×2376；窗口标志：`    mAttrs={(0,1626)(fillx750) sim={adjust=pan} layoutInDisplayCutoutMode=always ty=NAVIGATION_BAR_PANEL hwFlags=#0 hwExtFlags=#0 ohWindowId=0 isEmuiStyle=0 statusBarColor=#0 navigationBarColor=#0 fmt=TRANSLUCENT;     mHasSurface=false isReadyForDisplay()=false mWindowRemovalAllowed=false;     mAttrs={(0,1130)(162x415) gr=TOP LEFT CENTER sim={state=unchanged adjust=nothing} ty=NAVIGATION_BAR_PANEL hwFlags=#8010000 hwExtFlags=#0 ohWindowId=0 isEmuiStyle=0 statusBarColor=#0 navigationBarColor=#0 fmt=TRANSPARENT;     mHasSurface=false isReadyForDisplay()=false mWindowRemovalAllowed=false`。
- `batch3-19-brightness-0.window.txt`：`[]`。
- `batch3-20-brightness-.25.window.txt`：`[]`。
- `batch3-21-brightness-.75.window.txt`：`[]`。
- `batch3-22-brightness-1.window.txt`：`[]`。

## 批次 4：HE 首帧、换源与过期 RESTART（release）

- V1 pass=10（true/false各5）、V2 pass=5、V3 pass=5、V4 pass=1（内部20次）。日志原始数字如下：
```text
10-27 09:24:38.284 13053 13053 I flutter : [MOVA-HE] 09:24:38.284 --- V1 first-frame precision run 1/5
10-27 09:24:40.897 13053 13053 I flutter : [MOVA-HE] 09:24:40.897 V1 precise=true signal=restart sinceOpen=2097ms qoeTtff=2097ms
10-27 09:24:40.897 13053 13053 I flutter : [MOVA-HE] 09:24:40.897 VERDICT V1 PASS precise=true signal=restart diff=0ms
10-27 09:24:45.025 13053 13053 I flutter : [MOVA-HE] 09:24:45.025 V1 precise=false signal=buffering sinceOpen=2894ms
10-27 09:24:45.025 13053 13053 I flutter : [MOVA-HE] 09:24:45.025 VERDICT V1 PASS precise=false signal=buffering
10-27 09:24:45.025 13053 13053 I flutter : [MOVA-HE] 09:24:45.025 --- V1 first-frame precision run 2/5
10-27 09:24:48.830 13053 13053 I flutter : [MOVA-HE] 09:24:48.830 V1 precise=true signal=restart sinceOpen=2552ms qoeTtff=2552ms
10-27 09:24:48.831 13053 13053 I flutter : [MOVA-HE] 09:24:48.830 VERDICT V1 PASS precise=true signal=restart diff=0ms
10-27 09:24:52.606 13053 13053 I flutter : [MOVA-HE] 09:24:52.606 V1 precise=false signal=buffering sinceOpen=2528ms
10-27 09:24:52.606 13053 13053 I flutter : [MOVA-HE] 09:24:52.606 VERDICT V1 PASS precise=false signal=buffering
10-27 09:24:52.606 13053 13053 I flutter : [MOVA-HE] 09:24:52.606 --- V1 first-frame precision run 3/5
10-27 09:24:56.545 13053 13053 I flutter : [MOVA-HE] 09:24:56.545 V1 precise=true signal=restart sinceOpen=2681ms qoeTtff=2681ms
10-27 09:24:56.546 13053 13053 I flutter : [MOVA-HE] 09:24:56.546 VERDICT V1 PASS precise=true signal=restart diff=0ms
10-27 09:25:04.080 13053 13053 I flutter : [MOVA-HE] 09:25:04.080 V1 precise=false signal=buffering sinceOpen=6258ms
10-27 09:25:04.080 13053 13053 I flutter : [MOVA-HE] 09:25:04.080 VERDICT V1 PASS precise=false signal=buffering
10-27 09:25:04.080 13053 13053 I flutter : [MOVA-HE] 09:25:04.080 --- V1 first-frame precision run 4/5
10-27 09:25:08.198 13053 13053 I flutter : [MOVA-HE] 09:25:08.198 V1 precise=true signal=restart sinceOpen=2861ms qoeTtff=2861ms
10-27 09:25:08.199 13053 13053 I flutter : [MOVA-HE] 09:25:08.199 VERDICT V1 PASS precise=true signal=restart diff=0ms
10-27 09:25:11.971 13053 13053 I flutter : [MOVA-HE] 09:25:11.971 V1 precise=false signal=buffering sinceOpen=2529ms
10-27 09:25:11.971 13053 13053 I flutter : [MOVA-HE] 09:25:11.971 VERDICT V1 PASS precise=false signal=buffering
10-27 09:25:11.971 13053 13053 I flutter : [MOVA-HE] 09:25:11.971 --- V1 first-frame precision run 5/5
10-27 09:25:15.846 13053 13053 I flutter : [MOVA-HE] 09:25:15.846 V1 precise=true signal=restart sinceOpen=2608ms qoeTtff=2608ms
10-27 09:25:15.846 13053 13053 I flutter : [MOVA-HE] 09:25:15.846 VERDICT V1 PASS precise=true signal=restart diff=0ms
10-27 09:25:19.869 13053 13053 I flutter : [MOVA-HE] 09:25:19.869 V1 precise=false signal=buffering sinceOpen=2752ms
10-27 09:25:19.870 13053 13053 I flutter : [MOVA-HE] 09:25:19.870 VERDICT V1 PASS precise=false signal=buffering
10-27 09:25:20.572 13053 13053 I flutter : [MOVA-HE] 09:25:20.572 --- V2 paused open signal run 1/5
10-27 09:25:23.208 13053 13053 I flutter : [MOVA-HE] 09:25:23.208 V2 autoPlay=false signal=restart sinceOpen=2567ms
10-27 09:25:23.208 13053 13053 I flutter : [MOVA-HE] 09:25:23.208 VERDICT V2 PASS fact signal=restart
10-27 09:25:23.209 13053 13053 I flutter : [MOVA-HE] 09:25:23.209 --- V2 paused open signal run 2/5
10-27 09:25:26.451 13053 13053 I flutter : [MOVA-HE] 09:25:26.451 V2 autoPlay=false signal=restart sinceOpen=2476ms
10-27 09:25:26.452 13053 13053 I flutter : [MOVA-HE] 09:25:26.452 VERDICT V2 PASS fact signal=restart
10-27 09:25:26.452 13053 13053 I flutter : [MOVA-HE] 09:25:26.452 --- V2 paused open signal run 3/5
10-27 09:25:29.691 13053 13053 I flutter : [MOVA-HE] 09:25:29.691 V2 autoPlay=false signal=restart sinceOpen=2474ms
10-27 09:25:29.691 13053 13053 I flutter : [MOVA-HE] 09:25:29.691 VERDICT V2 PASS fact signal=restart
10-27 09:25:29.691 13053 13053 I flutter : [MOVA-HE] 09:25:29.691 --- V2 paused open signal run 4/5
10-27 09:25:33.103 13053 13053 I flutter : [MOVA-HE] 09:25:33.103 V2 autoPlay=false signal=restart sinceOpen=2654ms
10-27 09:25:33.103 13053 13053 I flutter : [MOVA-HE] 09:25:33.103 VERDICT V2 PASS fact signal=restart
10-27 09:25:33.103 13053 13053 I flutter : [MOVA-HE] 09:25:33.103 --- V2 paused open signal run 5/5
10-27 09:25:36.262 13053 13053 I flutter : [MOVA-HE] 09:25:36.262 V2 autoPlay=false signal=restart sinceOpen=2403ms
10-27 09:25:36.262 13053 13053 I flutter : [MOVA-HE] 09:25:36.262 VERDICT V2 PASS fact signal=restart
10-27 09:25:36.964 13053 13053 I flutter : [MOVA-HE] 09:25:36.964 --- V3 source change reset run 1/5
10-27 09:25:42.881 13053 13053 I flutter : [MOVA-HE] 09:25:42.881 V3 renderedFalseAfter=14ms newFirstFrame=2182ms signal=restart firstFrameEvents=1 renderedNow=true
10-27 09:25:42.881 13053 13053 I flutter : [MOVA-HE] 09:25:42.881 VERDICT V3 PASS reset=true ff=true events=1
10-27 09:25:42.881 13053 13053 I flutter : [MOVA-HE] 09:25:42.881 --- V3 source change reset run 2/5
10-27 09:25:50.001 13053 13053 I flutter : [MOVA-HE] 09:25:50.001 V3 renderedFalseAfter=21ms newFirstFrame=2281ms signal=restart firstFrameEvents=1 renderedNow=true
10-27 09:25:50.001 13053 13053 I flutter : [MOVA-HE] 09:25:50.001 VERDICT V3 PASS reset=true ff=true events=1
10-27 09:25:50.001 13053 13053 I flutter : [MOVA-HE] 09:25:50.001 --- V3 source change reset run 3/5
10-27 09:25:57.097 13053 13053 I flutter : [MOVA-HE] 09:25:57.097 V3 renderedFalseAfter=23ms newFirstFrame=2135ms signal=restart firstFrameEvents=1 renderedNow=true
10-27 09:25:57.098 13053 13053 I flutter : [MOVA-HE] 09:25:57.098 VERDICT V3 PASS reset=true ff=true events=1
10-27 09:25:57.098 13053 13053 I flutter : [MOVA-HE] 09:25:57.098 --- V3 source change reset run 4/5
10-27 09:26:04.070 13053 13053 I flutter : [MOVA-HE] 09:26:04.070 V3 renderedFalseAfter=30ms newFirstFrame=2268ms signal=restart firstFrameEvents=1 renderedNow=true
10-27 09:26:04.071 13053 13053 I flutter : [MOVA-HE] 09:26:04.071 VERDICT V3 PASS reset=true ff=true events=1
10-27 09:26:04.071 13053 13053 I flutter : [MOVA-HE] 09:26:04.071 --- V3 source change reset run 5/5
10-27 09:26:12.970 13053 13053 I flutter : [MOVA-HE] 09:26:12.970 V3 renderedFalseAfter=17ms newFirstFrame=3751ms signal=restart firstFrameEvents=1 renderedNow=true
10-27 09:26:12.970 13053 13053 I flutter : [MOVA-HE] 09:26:12.970 VERDICT V3 PASS reset=true ff=true events=1
10-27 09:26:13.672 13053 13053 I flutter : [MOVA-HE] 09:26:13.672 --- V4 stale RESTART race run 1/1
10-27 09:26:17.496 13053 13053 I flutter : [MOVA-HE] 09:26:17.496 V4 rep=0 seekToOpenGap=10ms B.sinceOpen=2161ms signal=restart
10-27 09:26:22.796 13053 13053 I flutter : [MOVA-HE] 09:26:22.796 V4 rep=1 seekToOpenGap=20ms B.sinceOpen=4252ms signal=restart
10-27 09:26:26.103 13053 13053 I flutter : [MOVA-HE] 09:26:26.103 V4 rep=2 seekToOpenGap=30ms B.sinceOpen=2279ms signal=restart
10-27 09:26:29.494 13053 13053 I flutter : [MOVA-HE] 09:26:29.494 V4 rep=3 seekToOpenGap=40ms B.sinceOpen=2352ms signal=restart
10-27 09:26:32.881 13053 13053 I flutter : [MOVA-HE] 09:26:32.881 V4 rep=4 seekToOpenGap=50ms B.sinceOpen=2334ms signal=restart
10-27 09:26:36.161 13053 13053 I flutter : [MOVA-HE] 09:26:36.161 V4 rep=5 seekToOpenGap=10ms B.sinceOpen=2296ms signal=restart
10-27 09:26:39.296 13053 13053 I flutter : [MOVA-HE] 09:26:39.296 V4 rep=6 seekToOpenGap=20ms B.sinceOpen=2123ms signal=restart
10-27 09:26:42.540 13053 13053 I flutter : [MOVA-HE] 09:26:42.540 V4 rep=7 seekToOpenGap=30ms B.sinceOpen=2186ms signal=restart
10-27 09:26:45.813 13053 13053 I flutter : [MOVA-HE] 09:26:45.813 V4 rep=8 seekToOpenGap=40ms B.sinceOpen=2283ms signal=restart
10-27 09:26:48.955 13053 13053 I flutter : [MOVA-HE] 09:26:48.955 V4 rep=9 seekToOpenGap=50ms B.sinceOpen=2116ms signal=restart
10-27 09:26:52.161 13053 13053 I flutter : [MOVA-HE] 09:26:52.161 V4 rep=10 seekToOpenGap=10ms B.sinceOpen=2198ms signal=restart
10-27 09:26:55.286 13053 13053 I flutter : [MOVA-HE] 09:26:55.286 V4 rep=11 seekToOpenGap=20ms B.sinceOpen=2116ms signal=restart
10-27 09:26:58.568 13053 13053 I flutter : [MOVA-HE] 09:26:58.568 V4 rep=12 seekToOpenGap=30ms B.sinceOpen=2245ms signal=restart
10-27 09:27:01.765 13053 13053 I flutter : [MOVA-HE] 09:27:01.765 V4 rep=13 seekToOpenGap=40ms B.sinceOpen=2174ms signal=restart
10-27 09:27:04.978 13053 13053 I flutter : [MOVA-HE] 09:27:04.978 V4 rep=14 seekToOpenGap=50ms B.sinceOpen=2152ms signal=restart
10-27 09:27:08.084 13053 13053 I flutter : [MOVA-HE] 09:27:08.084 V4 rep=15 seekToOpenGap=10ms B.sinceOpen=2105ms signal=restart
10-27 09:27:11.257 13053 13053 I flutter : [MOVA-HE] 09:27:11.256 V4 rep=16 seekToOpenGap=20ms B.sinceOpen=2150ms signal=restart
10-27 09:27:14.499 13053 13053 I flutter : [MOVA-HE] 09:27:14.499 V4 rep=17 seekToOpenGap=30ms B.sinceOpen=2224ms signal=restart
10-27 09:27:17.748 13053 13053 I flutter : [MOVA-HE] 09:27:17.748 V4 rep=18 seekToOpenGap=40ms B.sinceOpen=2190ms signal=restart
10-27 09:27:20.959 13053 13053 I flutter : [MOVA-HE] 09:27:20.959 V4 rep=19 seekToOpenGap=50ms B.sinceOpen=2151ms signal=restart
10-27 09:27:20.960 13053 13053 I flutter : [MOVA-HE] 09:27:20.960 VERDICT V4 PASS reps=20 tooEarly(<100ms)=0 missing=0 min=2105.0ms
10-27 09:27:21.662 13053 13053 I flutter : [MOVA-HE] 09:27:21.662 === SUMMARY (samples in ms) ===
10-27 09:27:21.665 13053 13053 I flutter : [MOVA-HE] 09:27:21.664 SUMMARY V1.precise=true.sinceOpenMs values=[2097,2552,2681,2861,2608] n=5 min=2097 max=2861 avg=2559.8 median=2608.0
10-27 09:27:21.665 13053 13053 I flutter : [MOVA-HE] 09:27:21.665 SUMMARY V1.precise=true.diffToQoeMs values=[0,0,0,0,0] n=5 min=0 max=0 avg=0.0 median=0.0
10-27 09:27:21.665 13053 13053 I flutter : [MOVA-HE] 09:27:21.665 SUMMARY V1.precise=false.sinceOpenMs values=[2894,2528,6258,2529,2752] n=5 min=2528 max=6258 avg=3392.2 median=2752.0
10-27 09:27:21.665 13053 13053 I flutter : [MOVA-HE] 09:27:21.665 SUMMARY V2.sinceOpenMs values=[2567,2476,2474,2654,2403] n=5 min=2403 max=2654 avg=2514.8 median=2476.0
10-27 09:27:21.666 13053 13053 I flutter : [MOVA-HE] 09:27:21.666 SUMMARY V2.signal.restart values=[1,1,1,1,1] n=5 min=1 max=1 avg=1.0 median=1.0
10-27 09:27:21.666 13053 13053 I flutter : [MOVA-HE] 09:27:21.666 SUMMARY V3.renderedFalseDelayMs values=[14,21,23,30,17] n=5 min=14 max=30 avg=21.0 median=21.0
10-27 09:27:21.666 13053 13053 I flutter : [MOVA-HE] 09:27:21.666 SUMMARY V3.sinceOpenMs values=[2182,2281,2135,2268,3751] n=5 min=2135 max=3751 avg=2523.4 median=2268.0
10-27 09:27:21.666 13053 13053 I flutter : [MOVA-HE] 09:27:21.666 SUMMARY V4.sinceOpenMs values=[2161,4252,2279,2352,2334,2296,2123,2186,2283,2116,2198,2116,2245,2174,2152,2105,2150,2224,2190,2151] n=20 min=2105 max=4252 avg=2304.3 median=2188.0
10-27 09:27:21.667 13053 13053 I flutter : [MOVA-HE] 09:27:21.667 SUMMARY V1 pass=10 fail=0
10-27 09:27:21.667 13053 13053 I flutter : [MOVA-HE] 09:27:21.667 SUMMARY V2 pass=5 fail=0
10-27 09:27:21.667 13053 13053 I flutter : [MOVA-HE] 09:27:21.667 SUMMARY V3 pass=5 fail=0
10-27 09:27:21.667 13053 13053 I flutter : [MOVA-HE] 09:27:21.667 SUMMARY V4 pass=1 fail=0
```

## 批次 5 初跑：旧脚本策略不兼容与V6续播失败证据

- V5初跑默认liveReconnect持续重试，不满足旧脚本giveUp一次的假设；这部分VERDICT FAIL为脚本不兼容，不算库bug。_recovery显式加入MovaRetryThenFailover后重跑。
- VOD V6不受直播默认策略影响；当前已见真实续播问题。原跑在第4轮V6期间停止，后续V7/V8/V12尚未执行；本次未记完成。
```text
10-27 09:28:34.023 13054 13054 I flutter : [MOVA-HE] 09:28:34.023 V5 firstFailure=4067ms startTimeout=4000ms deviation=67ms failures=4 retries=4 giveUpEvents=0 state.error=Failed to open http://127.0.0.1:18080/hang?t=1793064488993248.
10-27 09:28:34.024 13054 13054 I flutter : [MOVA-HE] 09:28:34.024 VERDICT V5 FAIL deviation=67ms giveUps=0
10-27 09:28:59.805 13054 13054 I flutter : [MOVA-HE] 09:28:59.805 V5 firstFailure=4078ms startTimeout=4000ms deviation=78ms failures=4 retries=4 giveUpEvents=0 state.error=Failed to open http://127.0.0.1:18080/hang?t=1793064514024719.
10-27 09:28:59.805 13054 13054 I flutter : [MOVA-HE] 09:28:59.805 VERDICT V5 FAIL deviation=78ms giveUps=0
10-27 09:29:25.583 13054 13054 I flutter : [MOVA-HE] 09:29:25.582 V5 firstFailure=4075ms startTimeout=4000ms deviation=75ms failures=4 retries=4 giveUpEvents=0 state.error=Failed to open http://127.0.0.1:18080/hang?t=1793064539805932.
10-27 09:29:25.583 13054 13054 I flutter : [MOVA-HE] 09:29:25.583 VERDICT V5 FAIL deviation=75ms giveUps=0
10-27 09:29:51.369 13054 13054 I flutter : [MOVA-HE] 09:29:51.369 V5 firstFailure=4088ms startTimeout=4000ms deviation=88ms failures=4 retries=4 giveUpEvents=0 state.error=Failed to open http://127.0.0.1:18080/hang?t=1793064565583886.
10-27 09:29:51.370 13054 13054 I flutter : [MOVA-HE] 09:29:51.369 VERDICT V5 FAIL deviation=88ms giveUps=0
10-27 09:30:17.153 13054 13054 I flutter : [MOVA-HE] 09:30:17.153 V5 firstFailure=4092ms startTimeout=4000ms deviation=92ms failures=4 retries=4 giveUpEvents=0 state.error=Failed to open http://127.0.0.1:18080/hang?t=1793064591370259.
10-27 09:30:17.153 13054 13054 I flutter : [MOVA-HE] 09:30:17.153 VERDICT V5 FAIL deviation=92ms giveUps=0
10-27 09:30:31.247 13054 13054 I flutter : [MOVA-HE] 09:30:31.247 V6 kind=stallTimeout bufferingTrueToFailure=6830ms (stallTimeout=4000ms, offset=2830ms) posBefore=2640ms posAfterRetry=2200ms diff=440ms recovered=1 samplesAfterRetryFirstFrame=[+0ms:0 +849ms:600 +1655ms:1400 +2459ms:2200]
10-27 09:30:31.248 13054 13054 I flutter : [MOVA-HE] 09:30:31.248 VERDICT V6 FAIL offset=2830ms posDiff=440ms
10-27 09:30:45.131 13054 13054 I flutter : [MOVA-HE] 09:30:45.130 V6 kind=stallTimeout bufferingTrueToFailure=4003ms (stallTimeout=4000ms, offset=3ms) posBefore=2680ms posAfterRetry=2200ms diff=480ms recovered=1 samplesAfterRetryFirstFrame=[+63ms:40 +868ms:800 +1674ms:1600 +2483ms:2400]
10-27 09:30:45.131 13054 13054 I flutter : [MOVA-HE] 09:30:45.131 VERDICT V6 FAIL offset=3ms posDiff=480ms
10-27 09:30:59.042 13054 13054 I flutter : [MOVA-HE] 09:30:59.041 V6 kind=stallTimeout bufferingTrueToFailure=4009ms (stallTimeout=4000ms, offset=9ms) posBefore=2680ms posAfterRetry=2200ms diff=480ms recovered=1 samplesAfterRetryFirstFrame=[+51ms:40 +863ms:800 +1670ms:1600 +2479ms:2400]
10-27 09:30:59.042 13054 13054 I flutter : [MOVA-HE] 09:30:59.042 VERDICT V6 FAIL offset=9ms posDiff=480ms
```

## 批次 6：HE 恢复、前后台、PiP豁免与路由（完整5轮）

- 策略仅在example/lib/verify_auto/he_auto.dart旧有限重试场景显式选择MovaRetryThenFailover；库实现未改。
- V10A/B/C总计15次无原生崩溃；Android未复现历史Windows路由崩溃。
```text
10-27 09:33:31.648 17961 17961 I flutter : [MOVA-HE] 09:33:31.648 V5 firstFailure=4091ms startTimeout=4000ms deviation=91ms failures=2 retries=1 giveUpEvents=1 state.error=Failed to open http://127.0.0.1:18080/hang?t=1793064799452938.
10-27 09:33:44.549 17961 17961 I flutter : [MOVA-HE] 09:33:44.549 V5 firstFailure=4069ms startTimeout=4000ms deviation=69ms failures=2 retries=1 giveUpEvents=1 state.error=Failed to open http://127.0.0.1:18080/hang?t=1793064811649681.
10-27 09:33:57.437 17961 17961 I flutter : [MOVA-HE] 09:33:57.437 V5 firstFailure=4065ms startTimeout=4000ms deviation=65ms failures=2 retries=1 giveUpEvents=1 state.error=Failed to open http://127.0.0.1:18080/hang?t=1793064824549297.
10-27 09:34:10.345 17961 17961 I flutter : [MOVA-HE] 09:34:10.345 V5 firstFailure=4093ms startTimeout=4000ms deviation=93ms failures=2 retries=1 giveUpEvents=1 state.error=Failed to open http://127.0.0.1:18080/hang?t=1793064837437756.
10-27 09:34:23.257 17961 17961 I flutter : [MOVA-HE] 09:34:23.257 V5 firstFailure=4081ms startTimeout=4000ms deviation=81ms failures=2 retries=1 giveUpEvents=1 state.error=Failed to open http://127.0.0.1:18080/hang?t=1793064850345808.
10-27 09:34:37.320 17961 17961 I flutter : [MOVA-HE] 09:34:37.320 V6 kind=stallTimeout bufferingTrueToFailure=4001ms (stallTimeout=4000ms, offset=1ms) posBefore=2680ms posAfterRetry=2240ms diff=440ms recovered=1 samplesAfterRetryFirstFrame=[+105ms:0 +915ms:600 +1721ms:1400 +2531ms:2240]
10-27 09:34:51.182 17961 17961 I flutter : [MOVA-HE] 09:34:51.181 V6 kind=stallTimeout bufferingTrueToFailure=4009ms (stallTimeout=4000ms, offset=9ms) posBefore=2680ms posAfterRetry=2200ms diff=480ms recovered=1 samplesAfterRetryFirstFrame=[+19ms:40 +826ms:800 +1633ms:1600 +2439ms:2400]
10-27 09:35:05.002 17961 17961 I flutter : [MOVA-HE] 09:35:05.002 V6 kind=stallTimeout bufferingTrueToFailure=4001ms (stallTimeout=4000ms, offset=1ms) posBefore=2520ms posAfterRetry=2040ms diff=480ms recovered=1 samplesAfterRetryFirstFrame=[+96ms:40 +899ms:840 +1704ms:1640 +2515ms:2440]
10-27 09:35:18.745 17961 17961 I flutter : [MOVA-HE] 09:35:18.745 V6 kind=stallTimeout bufferingTrueToFailure=4008ms (stallTimeout=4000ms, offset=8ms) posBefore=2680ms posAfterRetry=2320ms diff=360ms recovered=1 samplesAfterRetryFirstFrame=[+173ms:80 +977ms:920 +1790ms:1720 +2594ms:2520]
10-27 09:35:32.647 17961 17961 I flutter : [MOVA-HE] 09:35:32.646 V6 kind=stallTimeout bufferingTrueToFailure=4013ms (stallTimeout=4000ms, offset=13ms) posBefore=2680ms posAfterRetry=2200ms diff=480ms recovered=1 samplesAfterRetryFirstFrame=[+0ms:0 +809ms:600 +1613ms:1400 +2418ms:2200]
10-27 09:36:11.034 17961 17961 I flutter : [MOVA-HE] 09:36:11.034 --- V8 bad address verdict run 1/5
10-27 09:36:11.200 17961 17961 I flutter : [MOVA-HE] 09:36:11.200 V8 refused kind=nativeEndError at=108ms waited=0ms openErrors=0
10-27 09:36:11.200 17961 17961 I flutter : [MOVA-HE] 09:36:11.200 VERDICT V8 PASS refused kind=nativeEndError 108ms
10-27 09:36:12.070 17961 17961 I flutter : [MOVA-HE] 09:36:12.070 V8 404 kind=nativeEndError at=99ms waited=0ms openErrors=0
10-27 09:36:12.070 17961 17961 I flutter : [MOVA-HE] 09:36:12.070 VERDICT V8 PASS 404 kind=nativeEndError 99ms
10-27 09:36:12.070 17961 17961 I flutter : [MOVA-HE] 09:36:12.070 --- V8 bad address verdict run 2/5
10-27 09:36:12.938 17961 17961 I flutter : [MOVA-HE] 09:36:12.937 V8 refused kind=nativeEndError at=107ms waited=0ms openErrors=0
10-27 09:36:12.938 17961 17961 I flutter : [MOVA-HE] 09:36:12.938 VERDICT V8 PASS refused kind=nativeEndError 107ms
10-27 09:36:13.811 17961 17961 I flutter : [MOVA-HE] 09:36:13.811 V8 404 kind=nativeEndError at=100ms waited=0ms openErrors=0
10-27 09:36:13.811 17961 17961 I flutter : [MOVA-HE] 09:36:13.811 VERDICT V8 PASS 404 kind=nativeEndError 100ms
10-27 09:36:13.811 17961 17961 I flutter : [MOVA-HE] 09:36:13.811 --- V8 bad address verdict run 3/5
10-27 09:36:14.669 17961 17961 I flutter : [MOVA-HE] 09:36:14.669 V8 refused kind=nativeEndError at=98ms waited=0ms openErrors=0
10-27 09:36:14.669 17961 17961 I flutter : [MOVA-HE] 09:36:14.669 VERDICT V8 PASS refused kind=nativeEndError 98ms
10-27 09:36:15.538 17961 17961 I flutter : [MOVA-HE] 09:36:15.538 V8 404 kind=nativeEndError at=97ms waited=0ms openErrors=0
10-27 09:36:15.538 17961 17961 I flutter : [MOVA-HE] 09:36:15.538 VERDICT V8 PASS 404 kind=nativeEndError 97ms
10-27 09:36:15.538 17961 17961 I flutter : [MOVA-HE] 09:36:15.538 --- V8 bad address verdict run 4/5
10-27 09:36:16.404 17961 17961 I flutter : [MOVA-HE] 09:36:16.403 V8 refused kind=nativeEndError at=111ms waited=0ms openErrors=0
10-27 09:36:16.404 17961 17961 I flutter : [MOVA-HE] 09:36:16.404 VERDICT V8 PASS refused kind=nativeEndError 111ms
10-27 09:36:17.272 17961 17961 I flutter : [MOVA-HE] 09:36:17.272 V8 404 kind=nativeEndError at=119ms waited=0ms openErrors=0
10-27 09:36:17.272 17961 17961 I flutter : [MOVA-HE] 09:36:17.272 VERDICT V8 PASS 404 kind=nativeEndError 119ms
10-27 09:36:17.272 17961 17961 I flutter : [MOVA-HE] 09:36:17.272 --- V8 bad address verdict run 5/5
10-27 09:36:18.129 17961 17961 I flutter : [MOVA-HE] 09:36:18.129 V8 refused kind=nativeEndError at=79ms waited=0ms openErrors=0
10-27 09:36:18.130 17961 17961 I flutter : [MOVA-HE] 09:36:18.130 VERDICT V8 PASS refused kind=nativeEndError 79ms
10-27 09:36:19.013 17961 17961 I flutter : [MOVA-HE] 09:36:19.013 V8 404 kind=nativeEndError at=120ms waited=0ms openErrors=0
10-27 09:36:19.013 17961 17961 I flutter : [MOVA-HE] 09:36:19.013 VERDICT V8 PASS 404 kind=nativeEndError 120ms
10-27 09:37:08.081 17961 17961 I flutter : [MOVA-HE] 09:37:08.081 V9 lifecycle=[inactive,hidden,paused,hidden,inactive,resumed] play=true liveEdgeReach=true positionAdvanceOver3s=3000ms rendered=true playing=true
10-27 09:37:23.675 17961 17961 I flutter : [MOVA-HE] 09:37:23.675 V9 lifecycle=[inactive,hidden,paused,hidden,inactive,resumed] play=true liveEdgeReach=true positionAdvanceOver3s=2800ms rendered=true playing=true
10-27 09:37:39.753 17961 17961 I flutter : [MOVA-HE] 09:37:39.753 V9 lifecycle=[inactive,hidden,paused,hidden,inactive,resumed] play=true liveEdgeReach=true positionAdvanceOver3s=3000ms rendered=true playing=true
10-27 09:37:55.282 17961 17961 I flutter : [MOVA-HE] 09:37:55.281 V9 lifecycle=[inactive,hidden,paused,hidden,inactive,resumed] play=true liveEdgeReach=true positionAdvanceOver3s=3000ms rendered=true playing=true
10-27 09:38:11.158 17961 17961 I flutter : [MOVA-HE] 09:38:11.158 V9 lifecycle=[inactive,hidden,paused,hidden,inactive,resumed] play=true liveEdgeReach=true positionAdvanceOver3s=3000ms rendered=true playing=true
10-27 09:41:43.853 17961 17961 I flutter : [MOVA-HE] 09:41:43.853 === SUMMARY (samples in ms) ===
10-27 09:41:43.856 17961 17961 I flutter : [MOVA-HE] 09:41:43.856 SUMMARY V5.firstFailureDeviationMs values=[91,69,65,93,81] n=5 min=65 max=93 avg=79.8 median=81.0
10-27 09:41:43.856 17961 17961 I flutter : [MOVA-HE] 09:41:43.856 SUMMARY V6.failureMinusBufferingMinusTimeoutMs values=[1,9,1,8,13] n=5 min=1 max=13 avg=6.4 median=8.0
10-27 09:41:43.857 17961 17961 I flutter : [MOVA-HE] 09:41:43.857 SUMMARY V6.resumePositionDiffMs values=[440,480,480,360,480] n=5 min=360 max=480 avg=448.0 median=480.0
10-27 09:41:43.857 17961 17961 I flutter : [MOVA-HE] 09:41:43.857 SUMMARY V8.refused.failureMs values=[108,107,98,111,79] n=5 min=79 max=111 avg=100.6 median=107.0
10-27 09:41:43.858 17961 17961 I flutter : [MOVA-HE] 09:41:43.858 SUMMARY V8.404.failureMs values=[99,100,97,119,120] n=5 min=97 max=120 avg=107.0 median=100.0
10-27 09:41:43.858 17961 17961 I flutter : [MOVA-HE] 09:41:43.858 SUMMARY V10A.route.pauseMs values=[14,41,53,44,29] n=5 min=14 max=53 avg=36.2 median=41.0
10-27 09:41:43.859 17961 17961 I flutter : [MOVA-HE] 09:41:43.859 SUMMARY V10A.route.playMs values=[15,50,37,58,36] n=5 min=15 max=58 avg=39.2 median=37.0
10-27 09:41:43.859 17961 17961 I flutter : [MOVA-HE] 09:41:43.859 SUMMARY V10B.ticker.pauseMs values=[34,51,46,46,45] n=5 min=34 max=51 avg=44.4 median=46.0
10-27 09:41:43.859 17961 17961 I flutter : [MOVA-HE] 09:41:43.859 SUMMARY V10B.ticker.playMs values=[45,47,49,52,47] n=5 min=45 max=52 avg=48.0 median=47.0
10-27 09:41:43.860 17961 17961 I flutter : [MOVA-HE] 09:41:43.860 SUMMARY V10A pass=5 fail=0
10-27 09:41:43.860 17961 17961 I flutter : [MOVA-HE] 09:41:43.860 SUMMARY V10B pass=5 fail=0
10-27 09:41:43.861 17961 17961 I flutter : [MOVA-HE] 09:41:43.861 SUMMARY V10C pass=0 fail=5
10-27 09:41:43.861 17961 17961 I flutter : [MOVA-HE] 09:41:43.861 SUMMARY V11 pass=5 fail=0
10-27 09:41:43.861 17961 17961 I flutter : [MOVA-HE] 09:41:43.861 SUMMARY V12 pass=5 fail=0
10-27 09:41:43.862 17961 17961 I flutter : [MOVA-HE] 09:41:43.862 SUMMARY V5 pass=5 fail=0
10-27 09:41:43.862 17961 17961 I flutter : [MOVA-HE] 09:41:43.862 SUMMARY V6 pass=0 fail=5
10-27 09:41:43.862 17961 17961 I flutter : [MOVA-HE] 09:41:43.862 SUMMARY V7 pass=10 fail=0
10-27 09:41:43.862 17961 17961 I flutter : [MOVA-HE] 09:41:43.862 SUMMARY V8 pass=10 fail=0
10-27 09:41:43.863 17961 17961 I flutter : [MOVA-HE] 09:41:43.863 SUMMARY V9 pass=5 fail=0
```

## 批次 7 中间检查点：Android待机恢复信号

- 本批仍运行中，此处先保存已完成S1（15个样本）及S16/HLS发现；后续会追加完整汇总。
- GOP=25帧/25fps，hold=3s：resume=[5000, 5001, 5002, 5002, 5000]ms，avg=5001.0ms；独立decodedProp=[131, 199, 120, 159, 124]ms，avg=146.6ms；signal=['grace', 'grace', 'grace', 'grace', 'grace']。
- GOP=50帧/25fps，hold=3s：resume=[5001, 5001, 5006, 5001, 5002]ms，avg=5002.2ms；独立decodedProp=[145, 126, 115, 156, 122]ms，avg=132.8ms；signal=['grace', 'grace', 'grace', 'grace', 'grace']。
- GOP=100帧/25fps，hold=3s：resume=[5001, 5001, 5000, 5001, 5000]ms，avg=5000.6ms；独立decodedProp=[146, 147, 99, 155, 128]ms，avg=135.0ms；signal=['grace', 'grace', 'grace', 'grace', 'grace']。
- HLS true持有、false回退均有真实format=hls/audio=present/hwdec=mediacodec-copy读回；也走grace 5000ms，解码属性约百余ms。
- 无声C路径目前已完成4次，resume=1ms且signal=null；完整计数后补。

## 计数口径校正

直接按矩阵逐行统计：A33+C17+E37（35个事件类型+E1/E2）+U9+F16+N23=**135**。先前113/136计数把事件数多算1；当前顶部有效计数及135条台账为准。锁屏K已解除，仍标BLOCKED的行表示该编号证据尚未完整，不再沿用锁屏原因。

## 批次 7 完整结果：待机核心5轮

- 参数：release；GOPS=25,50,100、HOLDS=3、S3_SECONDS=15、RUNS=5。日志完成标记已收到；不是交接原始10/30秒持有网格，未据此修改默认值。
- S1 0/15满足size主信号判据；S2 5/5配置行为通过；S3 5/5 decodeOnly/null信号/1ms恢复；S6强制绕过无声保护5/5失败，位置回到0并重新加载，和Windows同类EOF路径；正常无声保护S3通过。
- S13 5/5，S17 5/5。S6属于直接内核强制B反例，不当作正常引擎待机误判。
```text
10-27 09:57:10.448 17962 17962 I flutter : [STANDBY] 09:57:10.448  641498ms --- S6 silent stream detection run 1/5
10-27 09:57:29.691 17962 17962 I flutter : [STANDBY] 09:57:29.690  660741ms S6 forced-B trace(position/eof-reached/core-idle every 500ms)=[5520/eof=yes/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes] eventsDuringForcedB=[MovaBufferChange, MovaPause, MovaDone, MovaPlayFailure, MovaBufferChange, MovaDurationChange, MovaSizeChange, MovaSizeChange, MovaPlay, MovaBufferChange]
10-27 09:57:29.691 17962 17962 I flutter : [STANDBY] 09:57:29.691  660741ms S6 audio=absent format=flv entered=true normal3sAdvance=2840ms forcedB4sAdvance=-5520ms exitRestartedVideo=true
10-27 09:57:29.691 17962 17962 I flutter : [STANDBY] 09:57:29.691  660742ms VERDICT S6 FAIL audio=absent forcedAdvance=-5520ms
10-27 09:57:29.692 17962 17962 I flutter : [STANDBY] 09:57:29.691  660742ms --- S6 silent stream detection run 2/5
10-27 09:57:47.103 17962 17962 I flutter : [STANDBY] 09:57:47.102  678153ms S6 forced-B trace(position/eof-reached/core-idle every 500ms)=[5600/eof=yes/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes] eventsDuringForcedB=[MovaBufferChange, MovaPause, MovaDone, MovaPlayFailure, MovaBufferChange, MovaDurationChange, MovaSizeChange, MovaSizeChange, MovaPlay, MovaBufferChange]
10-27 09:57:47.103 17962 17962 I flutter : [STANDBY] 09:57:47.103  678153ms S6 audio=absent format=flv entered=true normal3sAdvance=3040ms forcedB4sAdvance=-5600ms exitRestartedVideo=true
10-27 09:57:47.104 17962 17962 I flutter : [STANDBY] 09:57:47.104  678154ms VERDICT S6 FAIL audio=absent forcedAdvance=-5600ms
10-27 09:57:47.105 17962 17962 I flutter : [STANDBY] 09:57:47.104  678155ms --- S6 silent stream detection run 3/5
10-27 09:58:03.882 17962 17962 I flutter : [STANDBY] 09:58:03.882  694933ms S6 forced-B trace(position/eof-reached/core-idle every 500ms)=[5680/eof=yes/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes] eventsDuringForcedB=[MovaBufferChange, MovaPause, MovaDone, MovaPlayFailure, MovaBufferChange, MovaDurationChange, MovaSizeChange, MovaSizeChange, MovaPlay, MovaBufferChange]
10-27 09:58:03.883 17962 17962 I flutter : [STANDBY] 09:58:03.883  694933ms S6 audio=absent format=flv entered=true normal3sAdvance=3000ms forcedB4sAdvance=-5680ms exitRestartedVideo=true
10-27 09:58:03.883 17962 17962 I flutter : [STANDBY] 09:58:03.883  694933ms VERDICT S6 FAIL audio=absent forcedAdvance=-5680ms
10-27 09:58:03.883 17962 17962 I flutter : [STANDBY] 09:58:03.883  694933ms --- S6 silent stream detection run 4/5
10-27 09:58:20.925 17962 17962 I flutter : [STANDBY] 09:58:20.925  711976ms S6 forced-B trace(position/eof-reached/core-idle every 500ms)=[5840/eof=yes/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes] eventsDuringForcedB=[MovaBufferChange, MovaPause, MovaDone, MovaPlayFailure, MovaBufferChange, MovaDurationChange, MovaSizeChange, MovaSizeChange, MovaPlay, MovaBufferChange]
10-27 09:58:20.926 17962 17962 I flutter : [STANDBY] 09:58:20.926  711976ms S6 audio=absent format=flv entered=true normal3sAdvance=3000ms forcedB4sAdvance=-5840ms exitRestartedVideo=true
10-27 09:58:20.926 17962 17962 I flutter : [STANDBY] 09:58:20.926  711976ms VERDICT S6 FAIL audio=absent forcedAdvance=-5840ms
10-27 09:58:20.927 17962 17962 I flutter : [STANDBY] 09:58:20.926  711977ms --- S6 silent stream detection run 5/5
10-27 09:58:37.715 17962 17962 I flutter : [STANDBY] 09:58:37.715  728765ms S6 forced-B trace(position/eof-reached/core-idle every 500ms)=[5480/eof=yes/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes, 0/eof=/idle=yes] eventsDuringForcedB=[MovaBufferChange, MovaPause, MovaDone, MovaPlayFailure, MovaBufferChange, MovaDurationChange, MovaSizeChange, MovaSizeChange, MovaPlay, MovaBufferChange]
10-27 09:58:37.715 17962 17962 I flutter : [STANDBY] 09:58:37.715  728766ms S6 audio=absent format=flv entered=true normal3sAdvance=3040ms forcedB4sAdvance=-5480ms exitRestartedVideo=true
10-27 09:58:37.715 17962 17962 I flutter : [STANDBY] 09:58:37.715  728766ms VERDICT S6 FAIL audio=absent forcedAdvance=-5480ms
10-27 09:58:38.518 17962 17962 I flutter : [STANDBY] 09:58:38.517  729568ms --- S13 reload during B run 1/5
10-27 09:58:48.404 17962 17962 I flutter : [STANDBY] 09:58:48.404  739455ms S13 phase=holding vid/mute before=no/yes after backToLiveEdge=no/yes stillHolding=true wake=247ms signal=size eventsDuringReload=[MovaPause, MovaDurationChange, MovaSizeChange, MovaSizeChange, MovaPlay, MovaLiveEdgeReach, MovaBufferChange, MovaBufferChange, MovaDurationChange, MovaDurationChange]
10-27 09:58:48.405 17962 17962 I flutter : [STANDBY] 09:58:48.404  739455ms VERDICT S13 PASS after=no/yes stillHolding=true
10-27 09:58:48.405 17962 17962 I flutter : [STANDBY] 09:58:48.405  739455ms --- S13 reload during B run 2/5
10-27 09:58:59.503 17962 17962 I flutter : [STANDBY] 09:58:59.503  750553ms S13 phase=holding vid/mute before=no/yes after backToLiveEdge=no/yes stillHolding=true wake=216ms signal=size eventsDuringReload=[MovaPause, MovaDurationChange, MovaSizeChange, MovaSizeChange, MovaPlay, MovaLiveEdgeReach, MovaBufferChange, MovaBufferChange, MovaDurationChange, MovaDurationChange]
10-27 09:58:59.503 17962 17962 I flutter : [STANDBY] 09:58:59.503  750553ms VERDICT S13 PASS after=no/yes stillHolding=true
10-27 09:58:59.503 17962 17962 I flutter : [STANDBY] 09:58:59.503  750553ms --- S13 reload during B run 3/5
10-27 09:59:10.235 17962 17962 I flutter : [STANDBY] 09:59:10.235  761285ms S13 phase=holding vid/mute before=no/yes after backToLiveEdge=no/yes stillHolding=true wake=216ms signal=size eventsDuringReload=[MovaPause, MovaDurationChange, MovaSizeChange, MovaSizeChange, MovaPlay, MovaLiveEdgeReach, MovaBufferChange, MovaBufferChange, MovaDurationChange]
10-27 09:59:10.235 17962 17962 I flutter : [STANDBY] 09:59:10.235  761286ms VERDICT S13 PASS after=no/yes stillHolding=true
10-27 09:59:10.235 17962 17962 I flutter : [STANDBY] 09:59:10.235  761286ms --- S13 reload during B run 4/5
10-27 09:59:20.785 17962 17962 I flutter : [STANDBY] 09:59:20.785  771835ms S13 phase=holding vid/mute before=no/yes after backToLiveEdge=no/yes stillHolding=true wake=215ms signal=size eventsDuringReload=[MovaPause, MovaDurationChange, MovaSizeChange, MovaSizeChange, MovaPlay, MovaLiveEdgeReach, MovaBufferChange, MovaBufferChange, MovaDurationChange, MovaDurationChange]
10-27 09:59:20.785 17962 17962 I flutter : [STANDBY] 09:59:20.785  771835ms VERDICT S13 PASS after=no/yes stillHolding=true
10-27 09:59:20.785 17962 17962 I flutter : [STANDBY] 09:59:20.785  771836ms --- S13 reload during B run 5/5
10-27 09:59:31.294 17962 17962 I flutter : [STANDBY] 09:59:31.294  782344ms S13 phase=holding vid/mute before=no/yes after backToLiveEdge=no/yes stillHolding=true wake=204ms signal=size eventsDuringReload=[MovaPause, MovaDurationChange, MovaSizeChange, MovaSizeChange, MovaPlay, MovaLiveEdgeReach, MovaBufferChange, MovaBufferChange, MovaDurationChange, MovaDurationChange]
10-27 09:59:31.294 17962 17962 I flutter : [STANDBY] 09:59:31.294  782345ms VERDICT S13 PASS after=no/yes stillHolding=true
10-27 09:59:32.097 17962 17962 I flutter : [STANDBY] 09:59:32.096  783147ms --- S17 guard end-to-end (TickerMode) run 1/5
10-27 09:59:37.734 17962 17962 I flutter : [STANDBY] 09:59:37.734  788785ms S17 hide -> holding=true reason=requested mode=muted state=holding
10-27 09:59:44.757 17962 17962 I flutter : [STANDBY] 09:59:44.757  795807ms S17 show -> resume=5002ms signal=grace state=off
10-27 09:59:49.838 17962 17962 I flutter : [STANDBY] 09:59:49.838  800889ms S17 hidden source change: state=holding playing=true events=[Standby(fallback,reloaded), MovaPause, MovaFirstFrame, Standby(holding,requested), MovaPlay]
10-27 09:59:54.840 17962 17962 I flutter : [STANDBY] 09:59:54.840  805891ms S17 show after source change: state=resuming playing=true rendered=true events=[Standby(resuming,woke)]
10-27 09:59:54.941 17962 17962 I flutter : [STANDBY] 09:59:54.941  805992ms S17 hide again -> holding=true state=holding
10-27 09:59:57.942 17962 17962 I flutter : [STANDBY] 09:59:57.942  808993ms VERDICT S17 PASS holding=true resume=true holdAgain=true
10-27 09:59:57.943 17962 17962 I flutter : [STANDBY] 09:59:57.943  808993ms --- S17 guard end-to-end (TickerMode) run 2/5
10-27 10:00:04.487 17962 17962 I flutter : [STANDBY] 10:00:04.487  815538ms S17 hide -> holding=true reason=requested mode=muted state=holding
10-27 10:00:11.502 17962 17962 I flutter : [STANDBY] 10:00:11.502  822552ms S17 show -> resume=5001ms signal=grace state=off
10-27 10:00:16.605 17962 17962 I flutter : [STANDBY] 10:00:16.605  827655ms S17 hidden source change: state=holding playing=true events=[Standby(fallback,reloaded), MovaPause, MovaFirstFrame, Standby(holding,requested), MovaPlay]
10-27 10:00:21.607 17962 17962 I flutter : [STANDBY] 10:00:21.607  832658ms S17 show after source change: state=resuming playing=true rendered=true events=[Standby(resuming,woke)]
10-27 10:00:21.692 17962 17962 I flutter : [STANDBY] 10:00:21.691  832742ms S17 hide again -> holding=true state=holding
10-27 10:00:24.695 17962 17962 I flutter : [STANDBY] 10:00:24.695  835745ms VERDICT S17 PASS holding=true resume=true holdAgain=true
10-27 10:00:24.695 17962 17962 I flutter : [STANDBY] 10:00:24.695  835745ms --- S17 guard end-to-end (TickerMode) run 3/5
10-27 10:00:31.215 17962 17962 I flutter : [STANDBY] 10:00:31.215  842266ms S17 hide -> holding=true reason=requested mode=muted state=holding
10-27 10:00:38.235 17962 17962 I flutter : [STANDBY] 10:00:38.234  849285ms S17 show -> resume=5001ms signal=grace state=off
10-27 10:00:43.315 17962 17962 I flutter : [STANDBY] 10:00:43.314  854365ms S17 hidden source change: state=holding playing=true events=[Standby(fallback,reloaded), MovaPause, MovaFirstFrame, Standby(holding,requested), MovaPlay]
10-27 10:00:48.316 17962 17962 I flutter : [STANDBY] 10:00:48.316  859367ms S17 show after source change: state=resuming playing=true rendered=true events=[Standby(resuming,woke)]
10-27 10:00:48.420 17962 17962 I flutter : [STANDBY] 10:00:48.420  859470ms S17 hide again -> holding=true state=holding
10-27 10:00:51.422 17962 17962 I flutter : [STANDBY] 10:00:51.422  862472ms VERDICT S17 PASS holding=true resume=true holdAgain=true
10-27 10:00:51.422 17962 17962 I flutter : [STANDBY] 10:00:51.422  862472ms --- S17 guard end-to-end (TickerMode) run 4/5
10-27 10:00:57.766 17962 17962 I flutter : [STANDBY] 10:00:57.766  868817ms S17 hide -> holding=true reason=requested mode=muted state=holding
10-27 10:01:04.782 17962 17962 I flutter : [STANDBY] 10:01:04.781  875832ms S17 show -> resume=5001ms signal=grace state=off
10-27 10:01:09.875 17962 17962 I flutter : [STANDBY] 10:01:09.874  880925ms S17 hidden source change: state=holding playing=true events=[Standby(fallback,reloaded), MovaPause, MovaFirstFrame, Standby(holding,requested), MovaPlay]
10-27 10:01:14.878 17962 17962 I flutter : [STANDBY] 10:01:14.878  885928ms S17 show after source change: state=resuming playing=true rendered=true events=[Standby(resuming,woke)]
10-27 10:01:14.967 17962 17962 I flutter : [STANDBY] 10:01:14.967  886017ms S17 hide again -> holding=true state=holding
10-27 10:01:17.970 17962 17962 I flutter : [STANDBY] 10:01:17.969  889020ms VERDICT S17 PASS holding=true resume=true holdAgain=true
10-27 10:01:17.970 17962 17962 I flutter : [STANDBY] 10:01:17.970  889021ms --- S17 guard end-to-end (TickerMode) run 5/5
10-27 10:01:24.499 17962 17962 I flutter : [STANDBY] 10:01:24.498  895549ms S17 hide -> holding=true reason=requested mode=muted state=holding
10-27 10:01:31.529 17962 17962 I flutter : [STANDBY] 10:01:31.529  902579ms S17 show -> resume=5001ms signal=grace state=off
10-27 10:01:36.616 17962 17962 I flutter : [STANDBY] 10:01:36.616  907667ms S17 hidden source change: state=holding playing=true events=[Standby(fallback,reloaded), MovaPause, MovaFirstFrame, Standby(holding,requested), MovaPlay]
10-27 10:01:41.620 17962 17962 I flutter : [STANDBY] 10:01:41.620  912671ms S17 show after source change: state=resuming playing=true rendered=true events=[Standby(resuming,woke)]
10-27 10:01:41.701 17962 17962 I flutter : [STANDBY] 10:01:41.701  912751ms S17 hide again -> holding=true state=holding
10-27 10:01:44.703 17962 17962 I flutter : [STANDBY] 10:01:44.703  915753ms VERDICT S17 PASS holding=true resume=true holdAgain=true
10-27 10:01:45.507 17962 17962 I flutter : [STANDBY] 10:01:45.506  916557ms === SUMMARY (samples in ms) ===
10-27 10:01:45.510 17962 17962 I flutter : [STANDBY] 10:01:45.509  916560ms SUMMARY S16.delay=500ms.holding values=[0,0,0,0,0] n=5 min=0 max=0 avg=0.0 median=0.0
10-27 10:01:45.510 17962 17962 I flutter : [STANDBY] 10:01:45.510  916560ms SUMMARY S16.delay=1000ms.holding values=[0,0,0,0,0] n=5 min=0 max=0 avg=0.0 median=0.0
10-27 10:01:45.510 17962 17962 I flutter : [STANDBY] 10:01:45.510  916560ms SUMMARY S16.delay=2000ms.holding values=[0,1,1,0,1] n=5 min=0 max=1 avg=0.6 median=1.0
10-27 10:01:45.510 17962 17962 I flutter : [STANDBY] 10:01:45.510  916561ms SUMMARY S16.delay=3000ms.holding values=[1,1,1,1,1] n=5 min=1 max=1 avg=1.0 median=1.0
10-27 10:01:45.511 17962 17962 I flutter : [STANDBY] 10:01:45.511  916561ms SUMMARY S16.audioPresentAfterOpenMs(100ms poll) values=[2417,2419,2406,2456,2056] n=5 min=2056 max=2456 avg=2350.8 median=2417.0
10-27 10:01:45.511 17962 17962 I flutter : [STANDBY] 10:01:45.511  916561ms SUMMARY S1.gop=25.hold=3s.elapsedMs values=[5000,5001,5002,5002,5000] n=5 min=5000 max=5002 avg=5001.0 median=5001.0
10-27 10:01:45.511 17962 17962 I flutter : [STANDBY] 10:01:45.511  916562ms SUMMARY S1.gop=25.hold=3s.decodedPropMs values=[131,199,120,159,124] n=5 min=120 max=199 avg=146.6 median=131.0
10-27 10:01:45.512 17962 17962 I flutter : [STANDBY] 10:01:45.511  916562ms SUMMARY S15.signal.grace values=[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1] n=15 min=1 max=1 avg=1.0 median=1.0
10-27 10:01:45.512 17962 17962 I flutter : [STANDBY] 10:01:45.512  916562ms SUMMARY S1.gop=50.hold=3s.elapsedMs values=[5001,5001,5006,5001,5002] n=5 min=5001 max=5006 avg=5002.2 median=5001.0
10-27 10:01:45.512 17962 17962 I flutter : [STANDBY] 10:01:45.512  916563ms SUMMARY S1.gop=50.hold=3s.decodedPropMs values=[145,126,115,156,122] n=5 min=115 max=156 avg=132.8 median=126.0
10-27 10:01:45.513 17962 17962 I flutter : [STANDBY] 10:01:45.512  916563ms SUMMARY S1.gop=100.hold=3s.elapsedMs values=[5001,5001,5000,5001,5000] n=5 min=5000 max=5001 avg=5000.6 median=5001.0
10-27 10:01:45.513 17962 17962 I flutter : [STANDBY] 10:01:45.513  916563ms SUMMARY S1.gop=100.hold=3s.decodedPropMs values=[146,147,99,155,128] n=5 min=99 max=155 avg=135.0 median=146.0
10-27 10:01:45.513 17962 17962 I flutter : [STANDBY] 10:01:45.513  916563ms SUMMARY S2.allowHls.resumeMs values=[5001,5000,5000,5001,5000] n=5 min=5000 max=5001 avg=5000.4 median=5000.0
10-27 10:01:45.513 17962 17962 I flutter : [STANDBY] 10:01:45.513  916564ms SUMMARY S2.allowHls.decodedPropMs values=[142,110,122,108,128] n=5 min=108 max=142 avg=122.0 median=122.0
10-27 10:01:45.514 17962 17962 I flutter : [STANDBY] 10:01:45.514  916564ms SUMMARY S3.resumeMs values=[0,1,1,1,0] n=5 min=0 max=1 avg=0.6 median=1.0
10-27 10:01:45.514 17962 17962 I flutter : [STANDBY] 10:01:45.514  916565ms SUMMARY S1 pass=0 fail=15
10-27 10:01:45.515 17962 17962 I flutter : [STANDBY] 10:01:45.514  916565ms SUMMARY S13 pass=5 fail=0
10-27 10:01:45.515 17962 17962 I flutter : [STANDBY] 10:01:45.515  916565ms SUMMARY S16 pass=20 fail=0
10-27 10:01:45.515 17962 17962 I flutter : [STANDBY] 10:01:45.515  916565ms SUMMARY S17 pass=5 fail=0
10-27 10:01:45.515 17962 17962 I flutter : [STANDBY] 10:01:45.515  916566ms SUMMARY S2 pass=10 fail=0
10-27 10:01:45.516 17962 17962 I flutter : [STANDBY] 10:01:45.516  916566ms SUMMARY S3 pass=5 fail=0
10-27 10:01:45.516 17962 17962 I flutter : [STANDBY] 10:01:45.516  916566ms SUMMARY S6 pass=0 fail=5
```

## batch8-standby-native 自动检查点

- 复用页运行；逐编号最终结论需结合下面原始断言复核。
- driver exit=0；`{"selector": "standby|S7,S8,S8B,S14|1", "completed": true, "lines": 1812, "pid": "17963"}`。
- 日志：`example/tool/coverage_evidence/batch8-standby-native.log`；截图/系统读回/采样同前缀。
```text
10-27 10:02:08.263 17963 17963 I flutter : [STANDBY] 10:02:08.263   17732ms VERDICT S14 PASS screenshots taken by the external script (normal / holding1 / holding2 / restored)
10-27 10:05:21.999 17963 17963 I flutter : [STANDBY] 10:05:21.999  211467ms VERDICT S7 PASS videoCameBack=20/20 signalLanded=0/20
10-27 10:05:43.263 17963 17963 I flutter : [STANDBY] 10:05:43.263  232732ms VERDICT S8 PASS fact: playing=true advance=3040ms
10-27 10:05:58.925 17963 17963 I flutter : [STANDBY] 10:05:58.925  248394ms VERDICT S8B PASS fact recorded
10-27 10:05:59.726 17963 17963 I flutter : [STANDBY] 10:05:59.726  249195ms === SUMMARY (samples in ms) ===
10-27 10:05:59.726 17963 17963 I flutter : [STANDBY] 10:05:59.726  249195ms SUMMARY S14 pass=1 fail=0
10-27 10:05:59.726 17963 17963 I flutter : [STANDBY] 10:05:59.726  249195ms SUMMARY S7 pass=1 fail=0
10-27 10:05:59.726 17963 17963 I flutter : [STANDBY] 10:05:59.726  249195ms SUMMARY S8 pass=1 fail=0
10-27 10:05:59.726 17963 17963 I flutter : [STANDBY] 10:05:59.726  249195ms SUMMARY S8B pass=1 fail=0
10-27 10:05:59.727 17963 17963 I flutter : [STANDBY] 10:05:59.727  249195ms AUTORUN DONE
```

## batch9-standby-cpu-drift 自动检查点

- 复用页运行；逐编号最终结论需结合下面原始断言复核。
- driver exit=0；`{"selector": "standby|S4,S5,S5C|3", "completed": true, "lines": 3282, "pid": "22474"}`。
- 日志：`example/tool/coverage_evidence/batch9-standby-cpu-drift.log`；截图/系统读回/采样同前缀。
```text
10-27 10:06:35.570 22474 22474 I flutter : [STANDBY] 10:06:35.570   32199ms VERDICT S5 PASS drift=137ms
10-27 10:07:09.142 22474 22474 I flutter : [STANDBY] 10:07:09.142   65770ms VERDICT S5 PASS drift=681ms
10-27 10:07:42.607 22474 22474 I flutter : [STANDBY] 10:07:42.607   99235ms VERDICT S5 PASS drift=410ms
10-27 10:08:16.100 22474 22474 I flutter : [STANDBY] 10:08:16.100  132728ms VERDICT S5C PASS control drift=-10ms
10-27 10:08:49.258 22474 22474 I flutter : [STANDBY] 10:08:49.258  165886ms VERDICT S5C PASS control drift=10ms
10-27 10:09:22.754 22474 22474 I flutter : [STANDBY] 10:09:22.754  199382ms VERDICT S5C PASS control drift=16ms
10-27 10:09:44.135 22474 22474 I flutter : [STANDBY] 10:09:44.135  220763ms VERDICT S4 PASS normal recorded (see PHASE lines + external CPU/traffic)
10-27 10:10:05.391 22474 22474 I flutter : [STANDBY] 10:10:05.390  242019ms VERDICT S4 PASS B recorded (see PHASE lines + external CPU/traffic)
10-27 10:10:29.479 22474 22474 I flutter : [STANDBY] 10:10:29.479  266107ms VERDICT S4 PASS C recorded (see PHASE lines + external CPU/traffic)
10-27 10:10:51.513 22474 22474 I flutter : [STANDBY] 10:10:51.513  288142ms VERDICT S4 PASS D recorded (see PHASE lines + external CPU/traffic)
10-27 10:11:13.024 22474 22474 I flutter : [STANDBY] 10:11:13.024  309652ms VERDICT S4 PASS normal recorded (see PHASE lines + external CPU/traffic)
10-27 10:11:34.721 22474 22474 I flutter : [STANDBY] 10:11:34.721  331349ms VERDICT S4 PASS B recorded (see PHASE lines + external CPU/traffic)
10-27 10:12:01.455 22474 22474 I flutter : [STANDBY] 10:12:01.455  358084ms VERDICT S4 PASS C recorded (see PHASE lines + external CPU/traffic)
10-27 10:12:22.788 22474 22474 I flutter : [STANDBY] 10:12:22.788  379417ms VERDICT S4 PASS D recorded (see PHASE lines + external CPU/traffic)
10-27 10:12:44.451 22474 22474 I flutter : [STANDBY] 10:12:44.451  401080ms VERDICT S4 PASS normal recorded (see PHASE lines + external CPU/traffic)
10-27 10:13:08.720 22474 22474 I flutter : [STANDBY] 10:13:08.720  425348ms VERDICT S4 PASS B recorded (see PHASE lines + external CPU/traffic)
10-27 10:13:33.587 22474 22474 I flutter : [STANDBY] 10:13:33.587  450215ms VERDICT S4 PASS C recorded (see PHASE lines + external CPU/traffic)
10-27 10:13:54.937 22474 22474 I flutter : [STANDBY] 10:13:54.937  471565ms VERDICT S4 PASS D recorded (see PHASE lines + external CPU/traffic)
10-27 10:13:55.740 22474 22474 I flutter : [STANDBY] 10:13:55.740  472368ms === SUMMARY (samples in ms) ===
10-27 10:13:55.741 22474 22474 I flutter : [STANDBY] 10:13:55.741  472370ms SUMMARY S5.driftMs values=[137,681,410] n=3 min=137 max=681 avg=409.3 median=410.0
10-27 10:13:55.742 22474 22474 I flutter : [STANDBY] 10:13:55.742  472370ms SUMMARY S5C.driftMs values=[10,10,16] n=3 min=10 max=16 avg=12.0 median=10.0
10-27 10:13:55.742 22474 22474 I flutter : [STANDBY] 10:13:55.742  472370ms SUMMARY S4 pass=12 fail=0
10-27 10:13:55.742 22474 22474 I flutter : [STANDBY] 10:13:55.742  472371ms SUMMARY S5 pass=3 fail=0
10-27 10:13:55.743 22474 22474 I flutter : [STANDBY] 10:13:55.742  472371ms SUMMARY S5C pass=3 fail=0
10-27 10:13:55.743 22474 22474 I flutter : [STANDBY] 10:13:55.743  472371ms AUTORUN DONE
```

## 批次 8/9 证据复核：黑屏/硬解与CPU/位置漂移

- S5持有20s，3次漂移137/681/410ms，avg=409.3ms，均<1s；无待机对照-10/10/16ms，avg=5.3ms。本轮没有复测Windows原60s持有条件，不能声称60s漂移已解决。
- S4每模式15s×3；CPU是单核百分比（top总上限800%），按真实PHASE窗口对齐；排除边界2s以减小采样启动延迟。不是电池续航的能量测量。
- normal CPU samples=[92.8, 92.8, 96.4, 85.7, 96.4]%；min=85.7 max=96.4 avg=92.8%
- B CPU samples=[7.1, 10.7, 10.7, 7.1, 10.7]%；min=7.1 max=10.7 avg=9.3%
- C CPU samples=[135.0, 113.0, 121.0, 114.0, 114.0, 114.0]%；min=113.0 max=135.0 avg=118.5%
- D CPU samples=[7.1, 10.7, 3.5, 7.1, 7.1, 7.1]%；min=3.5 max=10.7 avg=7.1%
- S14真机截图已目视：normal为彩条时间码00:00:03.280；holding1/holding2的视频区域均纯黑；restored恢复彩条时间码00:00:14.520。证据为batch8-standby-native-1793066516146766700/1793066519499103800/1793066522002058700/1793066526106932300.png。Android表现为黑屏，Windows历史为冻结最后帧。
- S7实际hwdec=mediacodec-copy，20/20属性/截图恢复画面、signalLanded=0/20；当前进程日志未见Could not open codec。S8守卫5s回前台自动续播，S8B命令式后台实际状态见原始日志。

## batch10-mute 自动检查点

- 复用页运行；逐编号最终结论需结合下面原始断言复核。
- driver exit=0；`{"selector": "mute|Q13A,Q13B,Q13C|5", "completed": true, "lines": 7792, "pid": "22475"}`。
- 日志：`example/tool/coverage_evidence/batch10-mute.log`；截图/系统读回/采样同前缀。
```text
10-27 10:14:15.720 22475 22475 I flutter : [Q13] 10:14:15.720   15399ms VERDICT Q13A PASS warming: active(k1).mute=no shadow(k2).mute=yes swapped=true committed(live k2).mute=no
10-27 10:14:32.017 22475 22475 I flutter : [Q13] 10:14:32.017   31697ms VERDICT Q13A PASS warming: active(k1).mute=no shadow(k2).mute=yes swapped=true committed(live k2).mute=no
10-27 10:14:48.380 22475 22475 I flutter : [Q13] 10:14:48.380   48060ms VERDICT Q13A PASS warming: active(k1).mute=no shadow(k2).mute=yes swapped=true committed(live k2).mute=no
10-27 10:15:04.729 22475 22475 I flutter : [Q13] 10:15:04.729   64408ms VERDICT Q13A PASS warming: active(k1).mute=no shadow(k2).mute=yes swapped=true committed(live k2).mute=no
10-27 10:15:21.418 22475 22475 I flutter : [Q13] 10:15:21.418   81098ms VERDICT Q13A PASS warming: active(k1).mute=no shadow(k2).mute=yes swapped=true committed(live k2).mute=no
10-27 10:15:45.465 22475 22475 I flutter : [Q13] 10:15:45.465  105145ms VERDICT Q13B PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=yes live.vid=no standby=holding afterWake.mute=no
10-27 10:16:08.772 22475 22475 I flutter : [Q13] 10:16:08.772  128451ms VERDICT Q13B PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=yes live.vid=no standby=holding afterWake.mute=no
10-27 10:16:32.499 22475 22475 I flutter : [Q13] 10:16:32.499  152178ms VERDICT Q13B PASS shadow.mute while warming=yes swapped=true committed(live k3).mute=yes live.vid=no standby=holding afterWake.mute=no
10-27 10:16:55.987 22475 22475 I flutter : [Q13] 10:16:55.987  175666ms VERDICT Q13B PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=yes live.vid=no standby=holding afterWake.mute=no
10-27 10:17:17.419 22475 22475 I flutter : [Q13] 10:17:17.419  197098ms VERDICT Q13B PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=yes live.vid=no standby=holding afterWake.mute=no
10-27 10:17:34.181 22475 22475 I flutter : [Q13] 10:17:34.181  213860ms VERDICT Q13C PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=no shadow.mute after wake=yes
10-27 10:17:50.799 22475 22475 I flutter : [Q13] 10:17:50.799  230479ms VERDICT Q13C PASS shadow.mute while warming=yes swapped=true committed(live k3).mute=no shadow.mute after wake=yes
10-27 10:18:07.040 22475 22475 I flutter : [Q13] 10:18:07.040  246720ms VERDICT Q13C PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=no shadow.mute after wake=yes
10-27 10:18:23.396 22475 22475 I flutter : [Q13] 10:18:23.396  263076ms VERDICT Q13C PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=no shadow.mute after wake=yes
10-27 10:18:39.123 22475 22475 I flutter : [Q13] 10:18:39.123  278803ms VERDICT Q13C PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=no shadow.mute after wake=yes
10-27 10:18:40.203 22475 22475 I flutter : [Q13] 10:18:40.203  279883ms SUMMARY Q13A pass=5 fail=0
10-27 10:18:40.204 22475 22475 I flutter : [Q13] 10:18:40.204  279883ms SUMMARY Q13B pass=5 fail=0
10-27 10:18:40.204 22475 22475 I flutter : [Q13] 10:18:40.204  279883ms SUMMARY Q13C pass=5 fail=0
10-27 10:18:40.204 22475 22475 I flutter : [Q13] 10:18:40.204  279883ms AUTORUN DONE
```

## 批次 10 复核：预热静音与待机叠加

- 15次属性级判据全部通过；真实事件/属性读回日志 `batch10-mute.log`。
- 系统STREAM_MUSIC各MARK读回：`[('batch10-mute-1793067250831362000.audio.txt', 6), ('batch10-mute-1793067256062372100.audio.txt', 6), ('batch10-mute-1793067266980730900.audio.txt', 6), ('batch10-mute-1793067272361263800.audio.txt', 6), ('batch10-mute-1793067283118146400.audio.txt', 6), ('batch10-mute-1793067288703427500.audio.txt', 6), ('batch10-mute-1793067299680383800.audio.txt', 6), ('batch10-mute-1793067305077198800.audio.txt', 6), ('batch10-mute-1793067316169865500.audio.txt', 6), ('batch10-mute-1793067321767062600.audio.txt', 6), ('batch10-mute-1793067333603125400.audio.txt', 6), ('batch10-mute-1793067338699071100.audio.txt', 6), ('batch10-mute-1793067345811265400.audio.txt', 6), ('batch10-mute-1793067357355991600.audio.txt', 6), ('batch10-mute-1793067362000747100.audio.txt', 6), ('batch10-mute-1793067369120646400.audio.txt', 6), ('batch10-mute-1793067380794624000.audio.txt', 6), ('batch10-mute-1793067385729869200.audio.txt', 6), ('batch10-mute-1793067392839831000.audio.txt', 6), ('batch10-mute-1793067404414155200.audio.txt', 6), ('batch10-mute-1793067409260156700.audio.txt', 6), ('batch10-mute-1793067416332415400.audio.txt', 6), ('batch10-mute-1793067427092050200.audio.txt', 6), ('batch10-mute-1793067430700869400.audio.txt', 6), ('batch10-mute-1793067437765993900.audio.txt', 6), ('batch10-mute-1793067450138312700.audio.txt', 6), ('batch10-mute-1793067451796168000.audio.txt', 6), ('batch10-mute-1793067454529617900.audio.txt', 6), ('batch10-mute-1793067466186344500.audio.txt', 6), ('batch10-mute-1793067467257163800.audio.txt', 6), ('batch10-mute-1793067471149112800.audio.txt', 6), ('batch10-mute-1793067482851511900.audio.txt', 6), ('batch10-mute-1793067483898028600.audio.txt', 6), ('batch10-mute-1793067487394952200.audio.txt', 6), ('batch10-mute-1793067499062038100.audio.txt', 6), ('batch10-mute-1793067500134557800.audio.txt', 6), ('batch10-mute-1793067503742815300.audio.txt', 6), ('batch10-mute-1793067515220296800.audio.txt', 6), ('batch10-mute-1793067516297771100.audio.txt', 6), ('batch10-mute-1793067519471772900.audio.txt', 6)]`。
- 人耳听感/微小漏音没有可用音频采集，不将属性及系统音量等同于人耳波形验证。
```text
10-27 10:14:15.720 22475 22475 I flutter : [Q13] 10:14:15.720   15399ms VERDICT Q13A PASS warming: active(k1).mute=no shadow(k2).mute=yes swapped=true committed(live k2).mute=no
10-27 10:14:32.017 22475 22475 I flutter : [Q13] 10:14:32.017   31697ms VERDICT Q13A PASS warming: active(k1).mute=no shadow(k2).mute=yes swapped=true committed(live k2).mute=no
10-27 10:14:48.380 22475 22475 I flutter : [Q13] 10:14:48.380   48060ms VERDICT Q13A PASS warming: active(k1).mute=no shadow(k2).mute=yes swapped=true committed(live k2).mute=no
10-27 10:15:04.729 22475 22475 I flutter : [Q13] 10:15:04.729   64408ms VERDICT Q13A PASS warming: active(k1).mute=no shadow(k2).mute=yes swapped=true committed(live k2).mute=no
10-27 10:15:21.418 22475 22475 I flutter : [Q13] 10:15:21.418   81098ms VERDICT Q13A PASS warming: active(k1).mute=no shadow(k2).mute=yes swapped=true committed(live k2).mute=no
10-27 10:15:45.465 22475 22475 I flutter : [Q13] 10:15:45.465  105145ms VERDICT Q13B PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=yes live.vid=no standby=holding afterWake.mute=no
10-27 10:16:08.772 22475 22475 I flutter : [Q13] 10:16:08.772  128451ms VERDICT Q13B PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=yes live.vid=no standby=holding afterWake.mute=no
10-27 10:16:32.499 22475 22475 I flutter : [Q13] 10:16:32.499  152178ms VERDICT Q13B PASS shadow.mute while warming=yes swapped=true committed(live k3).mute=yes live.vid=no standby=holding afterWake.mute=no
10-27 10:16:55.987 22475 22475 I flutter : [Q13] 10:16:55.987  175666ms VERDICT Q13B PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=yes live.vid=no standby=holding afterWake.mute=no
10-27 10:17:17.419 22475 22475 I flutter : [Q13] 10:17:17.419  197098ms VERDICT Q13B PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=yes live.vid=no standby=holding afterWake.mute=no
10-27 10:17:34.181 22475 22475 I flutter : [Q13] 10:17:34.181  213860ms VERDICT Q13C PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=no shadow.mute after wake=yes
10-27 10:17:50.799 22475 22475 I flutter : [Q13] 10:17:50.799  230479ms VERDICT Q13C PASS shadow.mute while warming=yes swapped=true committed(live k3).mute=no shadow.mute after wake=yes
10-27 10:18:07.040 22475 22475 I flutter : [Q13] 10:18:07.040  246720ms VERDICT Q13C PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=no shadow.mute after wake=yes
10-27 10:18:23.396 22475 22475 I flutter : [Q13] 10:18:23.396  263076ms VERDICT Q13C PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=no shadow.mute after wake=yes
10-27 10:18:39.123 22475 22475 I flutter : [Q13] 10:18:39.123  278803ms VERDICT Q13C PASS shadow.mute while warming=yes swapped=true committed(live k2).mute=no shadow.mute after wake=yes
10-27 10:18:40.203 22475 22475 I flutter : [Q13] 10:18:40.203  279883ms SUMMARY Q13A pass=5 fail=0
10-27 10:18:40.204 22475 22475 I flutter : [Q13] 10:18:40.204  279883ms SUMMARY Q13B pass=5 fail=0
10-27 10:18:40.204 22475 22475 I flutter : [Q13] 10:18:40.204  279883ms SUMMARY Q13C pass=5 fail=0
```

## batch11-review 自动检查点

- 复用页运行；逐编号最终结论需结合下面原始断言复核。
- driver exit=0；`{"selector": "review|all|3", "completed": true, "lines": 12864, "pid": "22476"}`。
- 日志：`example/tool/coverage_evidence/batch11-review.log`；截图/系统读回/采样同前缀。
```text
10-27 10:18:46.304 22476 22476 I flutter : RFV2|1793067526304|START|group=all win=1080x2376 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:18:46.304 22476 22476 I flutter : RFV2|1793067526304|GROUP|begin v10
10-27 10:18:49.205 22476 22476 I flutter : RFV2|1793067529205|V10|run1 before: fs=true ori=auto video=640x360 epoch=0 win=2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 10:18:49.205 22476 22476 I flutter : RFV2|1793067529205|SAMPLE|V10_run1_before_swap
10-27 10:18:51.407 22476 22476 I flutter : RFV2|1793067531407|WIN|V10_run1_before_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 10:18:53.557 22476 22476 I flutter : RFV2|1793067533557|V10|run1 swapTo=true in 949ms; successor fs=true ori=auto title=B epoch=1 landscape=true immersive=true
10-27 10:18:53.557 22476 22476 I flutter : RFV2|1793067533557|SAMPLE|V10_run1_after_swap
10-27 10:18:55.760 22476 22476 I flutter : RFV2|1793067535760|WIN|V10_run1_after_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 10:18:57.272 22476 22476 I flutter : RFV2|1793067537272|V10|run1 after dispose: landscape=false immersive=false
10-27 10:18:57.272 22476 22476 I flutter : RFV2|1793067537272|SAMPLE|V10_run1_after_dispose
10-27 10:18:59.475 22476 22476 I flutter : RFV2|1793067539475|WIN|V10_run1_after_dispose 1080x2376 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:18:59.477 22476 22476 I flutter : RFV2|1793067539476|RESULT|V10|run1|PASS|preFsLandscapeImmersive=true swapTo=true successorFs=true landscapeAfterSwap=true immersiveAfterSwap=true restoredPortrait=true barsRestored=true
10-27 10:19:02.923 22476 22476 I flutter : RFV2|1793067542923|V10|run2 before: fs=true ori=auto video=640x360 epoch=0 win=2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 10:19:02.924 22476 22476 I flutter : RFV2|1793067542924|SAMPLE|V10_run2_before_swap
10-27 10:19:05.126 22476 22476 I flutter : RFV2|1793067545126|WIN|V10_run2_before_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 10:19:07.294 22476 22476 I flutter : RFV2|1793067547294|V10|run2 swapTo=true in 966ms; successor fs=true ori=auto title=B epoch=1 landscape=true immersive=true
10-27 10:19:07.295 22476 22476 I flutter : RFV2|1793067547295|SAMPLE|V10_run2_after_swap
10-27 10:19:09.497 22476 22476 I flutter : RFV2|1793067549496|WIN|V10_run2_after_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 10:19:11.002 22476 22476 I flutter : RFV2|1793067551001|V10|run2 after dispose: landscape=false immersive=false
10-27 10:19:11.002 22476 22476 I flutter : RFV2|1793067551002|SAMPLE|V10_run2_after_dispose
10-27 10:19:13.204 22476 22476 I flutter : RFV2|1793067553204|WIN|V10_run2_after_dispose 1080x2376 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:19:13.205 22476 22476 I flutter : RFV2|1793067553205|RESULT|V10|run2|PASS|preFsLandscapeImmersive=true swapTo=true successorFs=true landscapeAfterSwap=true immersiveAfterSwap=true restoredPortrait=true barsRestored=true
10-27 10:19:16.578 22476 22476 I flutter : RFV2|1793067556578|V10|run3 before: fs=true ori=auto video=640x360 epoch=0 win=2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 10:19:16.578 22476 22476 I flutter : RFV2|1793067556578|SAMPLE|V10_run3_before_swap
10-27 10:19:18.780 22476 22476 I flutter : RFV2|1793067558780|WIN|V10_run3_before_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 10:19:20.923 22476 22476 I flutter : RFV2|1793067560922|V10|run3 swapTo=true in 942ms; successor fs=true ori=auto title=B epoch=1 landscape=true immersive=true
10-27 10:19:20.923 22476 22476 I flutter : RFV2|1793067560923|SAMPLE|V10_run3_after_swap
10-27 10:19:23.125 22476 22476 I flutter : RFV2|1793067563125|WIN|V10_run3_after_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 10:19:24.633 22476 22476 I flutter : RFV2|1793067564633|V10|run3 after dispose: landscape=false immersive=false
10-27 10:19:24.634 22476 22476 I flutter : RFV2|1793067564634|SAMPLE|V10_run3_after_dispose
10-27 10:19:26.837 22476 22476 I flutter : RFV2|1793067566836|WIN|V10_run3_after_dispose 1080x2376 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:19:26.837 22476 22476 I flutter : RFV2|1793067566837|RESULT|V10|run3|PASS|preFsLandscapeImmersive=true swapTo=true successorFs=true landscapeAfterSwap=true immersiveAfterSwap=true restoredPortrait=true barsRestored=true
10-27 10:19:26.838 22476 22476 I flutter : RFV2|1793067566838|GROUP|end v10 uncaught=0
10-27 10:19:26.838 22476 22476 I flutter : RFV2|1793067566838|GROUP|begin v10x
10-27 10:19:30.405 22476 22476 I flutter : RFV2|1793067570405|V10x|run1 before: fs=true ori=auto video=640x360 epoch=0 win=2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 10:19:30.405 22476 22476 I flutter : RFV2|1793067570405|SAMPLE|V10x_run1_before_swap
10-27 10:19:32.606 22476 22476 I flutter : RFV2|1793067572606|WIN|V10x_run1_before_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 10:19:34.827 22476 22476 I flutter : RFV2|1793067574827|V10x|run1 swapTo=true in 1019ms; successor fs=true ori=auto title=B epoch=1 landscape=true immersive=true
10-27 10:19:34.827 22476 22476 I flutter : RFV2|1793067574827|SAMPLE|V10x_run1_after_swap
10-27 10:19:37.029 22476 22476 I flutter : RFV2|1793067577029|WIN|V10x_run1_after_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 10:19:38.340 22476 22476 I flutter : RFV2|1793067578340|V10x|run1 after setFullscreen(false): fs=false landscape=false immersive=false
10-27 10:19:38.341 22476 22476 I flutter : RFV2|1793067578340|SAMPLE|V10x_run1_after_exit
10-27 10:19:40.542 22476 22476 I flutter : RFV2|1793067580542|WIN|V10x_run1_after_exit 1080x2376 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:19:40.805 22476 22476 I flutter : RFV2|1793067580805|RESULT|V10x|run1|PASS|preFsLandscapeImmersive=true swapTo=true successorFs=true landscapeAfterSwap=true immersiveAfterSwap=true restoredPortrait=true barsRestored=true
10-27 10:19:44.295 22476 22476 I flutter : RFV2|1793067584295|V10x|run2 before: fs=true ori=auto video=640x360 epoch=0 win=2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 10:19:44.295 22476 22476 I flutter : RFV2|1793067584295|SAMPLE|V10x_run2_before_swap
10-27 10:19:46.497 22476 22476 I flutter : RFV2|1793067586497|WIN|V10x_run2_before_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 10:19:48.690 22476 22476 I flutter : RFV2|1793067588690|V10x|run2 swapTo=true in 992ms; successor fs=true ori=auto title=B epoch=1 landscape=true immersive=true
10-27 10:19:48.690 22476 22476 I flutter : RFV2|1793067588690|SAMPLE|V10x_run2_after_swap
10-27 10:19:50.891 22476 22476 I flutter : RFV2|1793067590891|WIN|V10x_run2_after_swap 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 10:19:52.225 22476 22476 I flutter : RFV2|1793067592225|V10x|run2 after setFullscreen(false): fs=false landscape=false immersive=false
10-27 10:19:52.225 22476 22476 I flutter : RFV2|1793067592225|SAMPLE|V10x_run2_after_exit
10-27 10:19:54.428 22476 22476 I flutter : RFV2|1793067594428|WIN|V10x_run2_after_exit 1080x2376 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:19:54.601 22476 22476 I flutter : RFV2|1793067594601|RESULT|V10x|run2|PASS|preFsLandscapeImmersive=true swapTo=true successorFs=true landscapeAfterSwap=true immersiveAfterSwap=true restoredPortrait=true barsRestored=true
10-27 10:19:54.602 22476 22476 I flutter : RFV2|1793067594602|GROUP|end v10x uncaught=0
10-27 10:19:54.602 22476 22476 I flutter : RFV2|1793067594602|GROUP|begin v10c
10-27 10:19:58.098 22476 22476 I flutter : RFV2|1793067598098|V10c|run1 before plain dispose of E1: landscape=true immersive=true e2.fs=true
10-27 10:19:58.098 22476 22476 I flutter : RFV2|1793067598098|SAMPLE|V10c_run1_before
10-27 10:20:00.301 22476 22476 I flutter : RFV2|1793067600301|WIN|V10c_run1_before 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 10:20:01.637 22476 22476 I flutter : RFV2|1793067601637|V10c|run1 after plain dispose of E1: landscape=false immersive=false e2.fs=true
10-27 10:20:01.637 22476 22476 I flutter : RFV2|1793067601637|SAMPLE|V10c_run1_after_plain_dispose
10-27 10:20:03.839 22476 22476 I flutter : RFV2|1793067603839|WIN|V10c_run1_after_plain_dispose 1080x2376 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:20:03.839 22476 22476 I flutter : RFV2|1793067603839|RESULT|V10c|run1|PASS|baselineFsOk=true platformResetByPlainDispose=true (PASS 表示"确认旧引擎普通 dispose 会复位", 即退役标记确有必要)
10-27 10:20:08.093 22476 22476 I flutter : RFV2|1793067608093|V10c|run2 before plain dispose of E1: landscape=true immersive=true e2.fs=true
10-27 10:20:08.093 22476 22476 I flutter : RFV2|1793067608093|SAMPLE|V10c_run2_before
10-27 10:20:10.294 22476 22476 I flutter : RFV2|1793067610294|WIN|V10c_run2_before 2266x1080 padTop=0 viewPadTop=0 viewPadBot=0
10-27 10:20:11.683 22476 22476 I flutter : RFV2|1793067611683|V10c|run2 after plain dispose of E1: landscape=false immersive=false e2.fs=true
10-27 10:20:11.684 22476 22476 I flutter : RFV2|1793067611683|SAMPLE|V10c_run2_after_plain_dispose
10-27 10:20:13.884 22476 22476 I flutter : RFV2|1793067613884|WIN|V10c_run2_after_plain_dispose 1080x2376 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:20:13.885 22476 22476 I flutter : RFV2|1793067613884|RESULT|V10c|run2|PASS|baselineFsOk=true platformResetByPlainDispose=true (PASS 表示"确认旧引擎普通 dispose 会复位", 即退役标记确有必要)
10-27 10:20:14.989 22476 22476 I flutter : RFV2|1793067614989|GROUP|end v10c uncaught=0
10-27 10:20:14.990 22476 22476 I flutter : RFV2|1793067614990|GROUP|begin v11
10-27 10:20:18.463 22476 22476 I flutter : RFV2|1793067618463|V11|run1 before: fs=false ori=landscape landscape=true win=2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:20:18.463 22476 22476 I flutter : RFV2|1793067618463|SAMPLE|V11_run1_before_swap
10-27 10:20:20.669 22476 22476 I flutter : RFV2|1793067620669|WIN|V11_run1_before_swap 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:20:22.819 22476 22476 I flutter : RFV2|1793067622819|V11|run1 swapTo=true successor ori=landscape fs=false title=B landscape=true
10-27 10:20:22.819 22476 22476 I flutter : RFV2|1793067622819|SAMPLE|V11_run1_after_swap
10-27 10:20:25.020 22476 22476 I flutter : RFV2|1793067625020|WIN|V11_run1_after_swap 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:20:26.530 22476 22476 I flutter : RFV2|1793067626530|V11|run1 after dispose: landscape=false
10-27 10:20:26.531 22476 22476 I flutter : RFV2|1793067626531|SAMPLE|V11_run1_after_dispose
10-27 10:20:28.733 22476 22476 I flutter : RFV2|1793067628733|WIN|V11_run1_after_dispose 1080x2376 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:20:28.735 22476 22476 I flutter : RFV2|1793067628735|RESULT|V11|run1|PASS|preLandscape=true swapTo=true successorOrientation=landscape landscapeAfterSwap=true restoredPortrait=true
10-27 10:20:31.955 22476 22476 I flutter : RFV2|1793067631955|V11|run2 before: fs=false ori=landscape landscape=true win=2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:20:31.955 22476 22476 I flutter : RFV2|1793067631955|SAMPLE|V11_run2_before_swap
10-27 10:20:34.157 22476 22476 I flutter : RFV2|1793067634157|WIN|V11_run2_before_swap 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:20:36.328 22476 22476 I flutter : RFV2|1793067636327|V11|run2 swapTo=true successor ori=landscape fs=false title=B landscape=true
10-27 10:20:36.328 22476 22476 I flutter : RFV2|1793067636328|SAMPLE|V11_run2_after_swap
10-27 10:20:38.529 22476 22476 I flutter : RFV2|1793067638529|WIN|V11_run2_after_swap 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:20:40.049 22476 22476 I flutter : RFV2|1793067640049|V11|run2 after dispose: landscape=false
10-27 10:20:40.050 22476 22476 I flutter : RFV2|1793067640050|SAMPLE|V11_run2_after_dispose
10-27 10:20:42.252 22476 22476 I flutter : RFV2|1793067642252|WIN|V11_run2_after_dispose 1080x2376 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:20:42.253 22476 22476 I flutter : RFV2|1793067642253|RESULT|V11|run2|PASS|preLandscape=true swapTo=true successorOrientation=landscape landscapeAfterSwap=true restoredPortrait=true
10-27 10:20:45.746 22476 22476 I flutter : RFV2|1793067645746|V11|run3 before: fs=false ori=landscape landscape=true win=2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:20:45.747 22476 22476 I flutter : RFV2|1793067645747|SAMPLE|V11_run3_before_swap
10-27 10:20:47.948 22476 22476 I flutter : RFV2|1793067647948|WIN|V11_run3_before_swap 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:20:50.006 22476 22476 I flutter : RFV2|1793067650006|V11|run3 swapTo=true successor ori=landscape fs=false title=B landscape=true
10-27 10:20:50.007 22476 22476 I flutter : RFV2|1793067650007|SAMPLE|V11_run3_after_swap
10-27 10:20:52.209 22476 22476 I flutter : RFV2|1793067652209|WIN|V11_run3_after_swap 2266x1080 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:20:53.686 22476 22476 I flutter : RFV2|1793067653686|V11|run3 after dispose: landscape=false
10-27 10:20:53.687 22476 22476 I flutter : RFV2|1793067653687|SAMPLE|V11_run3_after_dispose
10-27 10:20:55.891 22476 22476 I flutter : RFV2|1793067655890|WIN|V11_run3_after_dispose 1080x2376 padTop=110 viewPadTop=110 viewPadBot=0
10-27 10:20:55.892 22476 22476 I flutter : RFV2|1793067655892|RESULT|V11|run3|PASS|preLandscape=true swapTo=true successorOrientation=landscape landscapeAfterSwap=true restoredPortrait=true
10-27 10:20:55.892 22476 22476 I flutter : RFV2|1793067655892|GROUP|end v11 uncaught=0
10-27 10:20:55.892 22476 22476 I flutter : RFV2|1793067655892|GROUP|begin v12
10-27 10:20:56.037 22476 22476 I flutter : RFV2|1793067656036|V12|run1 st title=C epoch=0 rendered=false playing=true buffering=true phase=idle
10-27 10:20:56.570 22476 22476 I flutter : RFV2|1793067656570|V12|run1 st title=C epoch=0 rendered=true playing=true buffering=false phase=idle
10-27 10:20:59.819 22476 22476 I flutter : RFV2|1793067659819|V12|run1 adEvent pending:AD1
10-27 10:20:59.900 22476 22476 I flutter : RFV2|1793067659900|V12|run1 swapPhase=warming
10-27 10:20:59.937 22476 22476 I flutter : RFV2|1793067659937|V12|run1 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 10:21:00.712 22476 22476 I flutter : RFV2|1793067660712|V12|run1 swapPhase=ready
10-27 10:21:00.730 22476 22476 I flutter : RFV2|1793067660730|V12|run1 adEvent started:AD1
10-27 10:21:00.730 22476 22476 I flutter : RFV2|1793067660730|V12|run1 swapPhase=idle
10-27 10:21:00.750 22476 22476 I flutter : RFV2|1793067660750|V12|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 10:21:00.875 22476 22476 I flutter : RFV2|1793067660875|V12|run1 swapPhase=warming
10-27 10:21:00.937 22476 22476 I flutter : RFV2|1793067660937|V12|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 10:21:04.603 22476 22476 I flutter : RFV2|1793067664603|V12|run1 swapPhase=ready
10-27 10:21:04.636 22476 22476 I flutter : RFV2|1793067664636|V12|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=ready
10-27 10:21:04.731 22476 22476 I flutter : RFV2|1793067664731|V12|run1 adEvent completed:AD1
10-27 10:21:04.731 22476 22476 I flutter : RFV2|1793067664731|V12|run1 adEvent started:AD2
10-27 10:21:04.755 22476 22476 I flutter : RFV2|1793067664755|V12|run1 swapPhase=idle
10-27 10:21:04.759 22476 22476 I flutter : RFV2|1793067664759|V12|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 10:21:04.890 22476 22476 I flutter : RFV2|1793067664890|V12|run1 swapPhase=warming
10-27 10:21:04.937 22476 22476 I flutter : RFV2|1793067664937|V12|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 10:21:05.665 22476 22476 I flutter : RFV2|1793067665665|V12|run1 swapPhase=ready
10-27 10:21:05.674 22476 22476 I flutter : RFV2|1793067665674|V12|run1 swapPhase=idle
10-27 10:21:05.737 22476 22476 I flutter : RFV2|1793067665737|V12|run1 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=idle
10-27 10:21:05.841 22476 22476 I flutter : RFV2|1793067665841|V12|run1 swapPhase=warming
10-27 10:21:06.038 22476 22476 I flutter : RFV2|1793067666038|V12|run1 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=warming
10-27 10:21:06.579 22476 22476 I flutter : RFV2|1793067666579|V12|run1 swapPhase=ready
10-27 10:21:06.637 22476 22476 I flutter : RFV2|1793067666637|V12|run1 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=ready
10-27 10:21:11.676 22476 22476 I flutter : RFV2|1793067671676|V12|run1 adEvent completed:AD2
10-27 10:21:11.724 22476 22476 I flutter : RFV2|1793067671724|V12|run1 swapPhase=idle
10-27 10:21:11.736 22476 22476 I flutter : RFV2|1793067671736|V12|run1 st title=C epoch=3 rendered=true playing=true buffering=false phase=idle
10-27 10:21:14.215 22476 22476 I flutter : RFV2|1793067674215|V12|run1 epochs=3 epochRelToAD2Started=[-3981, 946, 7006] AD2 started->epochChange=946ms started->completed=6945ms adFirstFrame->completed=5999ms oldTicksInWindow=3 failed=0([])
10-27 10:21:14.216 22476 22476 I flutter : RFV2|1793067674216|RESULT|V12|run1|PASS|failed=0 AD2completed=true adFirstFrame->completed=5999ms (cfg 6000) started->completed=6945ms started->epochChange=946ms oldTicksBeforeEpoch=3
10-27 10:21:14.617 22476 22476 I flutter : RFV2|1793067674617|V12|run2 st title=C epoch=0 rendered=false playing=true buffering=true phase=idle
10-27 10:21:15.164 22476 22476 I flutter : RFV2|1793067675164|V12|run2 st title=C epoch=0 rendered=true playing=true buffering=false phase=idle
10-27 10:21:18.396 22476 22476 I flutter : RFV2|1793067678396|V12|run2 adEvent pending:AD1
10-27 10:21:18.493 22476 22476 I flutter : RFV2|1793067678493|V12|run2 swapPhase=warming
10-27 10:21:18.498 22476 22476 I flutter : RFV2|1793067678498|V12|run2 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 10:21:19.369 22476 22476 I flutter : RFV2|1793067679369|V12|run2 swapPhase=ready
10-27 10:21:19.397 22476 22476 I flutter : RFV2|1793067679397|V12|run2 adEvent started:AD1
10-27 10:21:19.397 22476 22476 I flutter : RFV2|1793067679397|V12|run2 swapPhase=idle
10-27 10:21:19.399 22476 22476 I flutter : RFV2|1793067679399|V12|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 10:21:19.552 22476 22476 I flutter : RFV2|1793067679552|V12|run2 swapPhase=warming
10-27 10:21:19.598 22476 22476 I flutter : RFV2|1793067679598|V12|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 10:21:23.398 22476 22476 I flutter : RFV2|1793067683398|V12|run2 adEvent completed:AD1
10-27 10:21:23.399 22476 22476 I flutter : RFV2|1793067683399|V12|run2 adEvent started:AD2
10-27 10:21:23.428 22476 22476 I flutter : RFV2|1793067683428|V12|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 10:21:23.429 22476 22476 I flutter : RFV2|1793067683429|V12|run2 swapPhase=idle
10-27 10:21:23.578 22476 22476 I flutter : RFV2|1793067683578|V12|run2 swapPhase=warming
10-27 10:21:23.598 22476 22476 I flutter : RFV2|1793067683598|V12|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 10:21:24.451 22476 22476 I flutter : RFV2|1793067684451|V12|run2 swapPhase=ready
10-27 10:21:24.479 22476 22476 I flutter : RFV2|1793067684479|V12|run2 swapPhase=idle
10-27 10:21:24.505 22476 22476 I flutter : RFV2|1793067684505|V12|run2 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=idle
10-27 10:21:24.709 22476 22476 I flutter : RFV2|1793067684709|V12|run2 swapPhase=warming
10-27 10:21:24.904 22476 22476 I flutter : RFV2|1793067684904|V12|run2 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=warming
10-27 10:21:28.992 22476 22476 I flutter : RFV2|1793067688992|V12|run2 swapPhase=ready
10-27 10:21:28.999 22476 22476 I flutter : RFV2|1793067688998|V12|run2 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=ready
10-27 10:21:30.480 22476 22476 I flutter : RFV2|1793067690480|V12|run2 adEvent completed:AD2
10-27 10:21:30.517 22476 22476 I flutter : RFV2|1793067690517|V12|run2 st title=AD2 epoch=2 rendered=true playing=false buffering=false phase=ready
10-27 10:21:30.535 22476 22476 I flutter : RFV2|1793067690535|V12|run2 swapPhase=idle
10-27 10:21:30.599 22476 22476 I flutter : RFV2|1793067690599|V12|run2 st title=C epoch=3 rendered=true playing=true buffering=false phase=idle
10-27 10:21:32.990 22476 22476 I flutter : RFV2|1793067692989|V12|run2 epochs=3 epochRelToAD2Started=[-4002, 1106, 7151] AD2 started->epochChange=1106ms started->completed=7081ms adFirstFrame->completed=5975ms oldTicksInWindow=3 failed=0([])
10-27 10:21:32.990 22476 22476 I flutter : RFV2|1793067692990|RESULT|V12|run2|PASS|failed=0 AD2completed=true adFirstFrame->completed=5975ms (cfg 6000) started->completed=7081ms started->epochChange=1106ms oldTicksBeforeEpoch=3
10-27 10:21:33.358 22476 22476 I flutter : RFV2|1793067693358|V12|run3 st title=C epoch=0 rendered=false playing=true buffering=true phase=idle
10-27 10:21:33.914 22476 22476 I flutter : RFV2|1793067693914|V12|run3 st title=C epoch=0 rendered=true playing=true buffering=false phase=idle
10-27 10:21:37.154 22476 22476 I flutter : RFV2|1793067697153|V12|run3 adEvent pending:AD1
10-27 10:21:37.254 22476 22476 I flutter : RFV2|1793067697254|V12|run3 swapPhase=warming
10-27 10:21:37.263 22476 22476 I flutter : RFV2|1793067697263|V12|run3 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 10:21:38.115 22476 22476 I flutter : RFV2|1793067698115|V12|run3 swapPhase=ready
10-27 10:21:38.125 22476 22476 I flutter : RFV2|1793067698125|V12|run3 adEvent started:AD1
10-27 10:21:38.125 22476 22476 I flutter : RFV2|1793067698125|V12|run3 swapPhase=idle
10-27 10:21:38.160 22476 22476 I flutter : RFV2|1793067698160|V12|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 10:21:38.240 22476 22476 I flutter : RFV2|1793067698240|V12|run3 swapPhase=warming
10-27 10:21:38.263 22476 22476 I flutter : RFV2|1793067698263|V12|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 10:21:42.127 22476 22476 I flutter : RFV2|1793067702127|V12|run3 adEvent completed:AD1
10-27 10:21:42.127 22476 22476 I flutter : RFV2|1793067702127|V12|run3 adEvent started:AD2
10-27 10:21:42.159 22476 22476 I flutter : RFV2|1793067702159|V12|run3 swapPhase=idle
10-27 10:21:42.163 22476 22476 I flutter : RFV2|1793067702163|V12|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 10:21:42.281 22476 22476 I flutter : RFV2|1793067702281|V12|run3 swapPhase=warming
10-27 10:21:42.534 22476 22476 I flutter : RFV2|1793067702534|V12|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 10:21:43.043 22476 22476 I flutter : RFV2|1793067703043|V12|run3 swapPhase=ready
10-27 10:21:43.047 22476 22476 I flutter : RFV2|1793067703047|V12|run3 swapPhase=idle
10-27 10:21:43.069 22476 22476 I flutter : RFV2|1793067703069|V12|run3 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=idle
10-27 10:21:43.231 22476 22476 I flutter : RFV2|1793067703231|V12|run3 swapPhase=warming
10-27 10:21:43.259 22476 22476 I flutter : RFV2|1793067703259|V12|run3 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=warming
10-27 10:21:47.459 22476 22476 I flutter : RFV2|1793067707459|V12|run3 swapPhase=ready
10-27 10:21:47.558 22476 22476 I flutter : RFV2|1793067707558|V12|run3 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=ready
10-27 10:21:49.049 22476 22476 I flutter : RFV2|1793067709049|V12|run3 adEvent completed:AD2
10-27 10:21:49.067 22476 22476 I flutter : RFV2|1793067709067|V12|run3 st title=AD2 epoch=2 rendered=true playing=false buffering=false phase=ready
10-27 10:21:49.099 22476 22476 I flutter : RFV2|1793067709099|V12|run3 swapPhase=idle
10-27 10:21:49.158 22476 22476 I flutter : RFV2|1793067709158|V12|run3 st title=C epoch=3 rendered=true playing=true buffering=false phase=idle
10-27 10:21:51.569 22476 22476 I flutter : RFV2|1793067711569|V12|run3 epochs=3 epochRelToAD2Started=[-3967, 942, 6987] AD2 started->epochChange=942ms started->completed=6922ms adFirstFrame->completed=5980ms oldTicksInWindow=4 failed=0([])
10-27 10:21:51.569 22476 22476 I flutter : RFV2|1793067711569|RESULT|V12|run3|PASS|failed=0 AD2completed=true adFirstFrame->completed=5980ms (cfg 6000) started->completed=6922ms started->epochChange=942ms oldTicksBeforeEpoch=4
10-27 10:21:51.810 22476 22476 I flutter : RFV2|1793067711810|GROUP|end v12 uncaught=0
10-27 10:21:51.810 22476 22476 I flutter : RFV2|1793067711810|GROUP|begin v12b
10-27 10:21:51.928 22476 22476 I flutter : RFV2|1793067711928|V12b|run1 st title=C epoch=0 rendered=false playing=true buffering=true phase=idle
10-27 10:21:52.619 22476 22476 I flutter : RFV2|1793067712619|V12b|run1 st title=C epoch=0 rendered=true playing=true buffering=true phase=idle
10-27 10:21:52.828 22476 22476 I flutter : RFV2|1793067712828|V12b|run1 st title=C epoch=0 rendered=true playing=true buffering=false phase=idle
10-27 10:21:55.844 22476 22476 I flutter : RFV2|1793067715844|V12b|run1 adEvent pending:AD1
10-27 10:21:55.946 22476 22476 I flutter : RFV2|1793067715946|V12b|run1 swapPhase=warming
10-27 10:21:56.237 22476 22476 I flutter : RFV2|1793067716237|V12b|run1 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 10:21:57.213 22476 22476 I flutter : RFV2|1793067717213|V12b|run1 swapPhase=ready
10-27 10:21:57.228 22476 22476 I flutter : RFV2|1793067717228|V12b|run1 st title=C epoch=0 rendered=true playing=true buffering=false phase=ready
10-27 10:21:57.305 22476 22476 I flutter : RFV2|1793067717305|V12b|run1 swapPhase=warming
10-27 10:21:57.328 22476 22476 I flutter : RFV2|1793067717328|V12b|run1 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 10:21:58.477 22476 22476 I flutter : RFV2|1793067718477|V12b|run1 swapPhase=ready
10-27 10:21:58.528 22476 22476 I flutter : RFV2|1793067718528|V12b|run1 st title=C epoch=0 rendered=true playing=true buffering=false phase=ready
10-27 10:21:58.828 22476 22476 I flutter : RFV2|1793067718828|V12b|run1 st title=C epoch=0 rendered=true playing=false buffering=false phase=ready
10-27 10:22:00.010 22476 22476 I flutter : RFV2|1793067720010|V12b|run1 adEvent started:AD1
10-27 10:22:00.010 22476 22476 I flutter : RFV2|1793067720010|V12b|run1 swapPhase=idle
10-27 10:22:00.035 22476 22476 I flutter : RFV2|1793067720035|V12b|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 10:22:00.148 22476 22476 I flutter : RFV2|1793067720148|V12b|run1 swapPhase=warming
10-27 10:22:00.228 22476 22476 I flutter : RFV2|1793067720228|V12b|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 10:22:04.012 22476 22476 I flutter : RFV2|1793067724012|V12b|run1 adEvent completed:AD1
10-27 10:22:04.012 22476 22476 I flutter : RFV2|1793067724012|V12b|run1 adEvent started:AD2
10-27 10:22:04.040 22476 22476 I flutter : RFV2|1793067724040|V12b|run1 swapPhase=idle
10-27 10:22:04.042 22476 22476 I flutter : RFV2|1793067724042|V12b|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 10:22:04.120 22476 22476 I flutter : RFV2|1793067724120|V12b|run1 swapPhase=warming
10-27 10:22:04.139 22476 22476 I flutter : RFV2|1793067724139|V12b|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 10:22:04.869 22476 22476 I flutter : RFV2|1793067724869|V12b|run1 swapPhase=ready
10-27 10:22:04.930 22476 22476 I flutter : RFV2|1793067724930|V12b|run1 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=ready
10-27 10:22:06.381 22476 22476 I flutter : RFV2|1793067726381|V12b|run1 swapPhase=idle
10-27 10:22:06.443 22476 22476 I flutter : RFV2|1793067726443|V12b|run1 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=idle
10-27 10:22:06.488 22476 22476 I flutter : RFV2|1793067726488|V12b|run1 swapPhase=warming
10-27 10:22:06.528 22476 22476 I flutter : RFV2|1793067726528|V12b|run1 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=warming
10-27 10:22:07.848 22476 22476 I flutter : RFV2|1793067727848|V12b|run1 swapPhase=ready
10-27 10:22:07.935 22476 22476 I flutter : RFV2|1793067727935|V12b|run1 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=ready
10-27 10:22:12.383 22476 22476 I flutter : RFV2|1793067732383|V12b|run1 adEvent completed:AD2
10-27 10:22:13.907 22476 22476 I flutter : RFV2|1793067733907|V12b|run1 swapPhase=idle
10-27 10:22:13.930 22476 22476 I flutter : RFV2|1793067733930|V12b|run1 st title=C epoch=3 rendered=true playing=true buffering=false phase=idle
10-27 10:22:14.918 22476 22476 I flutter : RFV2|1793067734918|V12b|run1 epochs=3 epochRelToAD2Started=[-3977, 2406, 9897] AD2 started->epochChange=2406ms started->completed=8371ms adFirstFrame->completed=5965ms oldTicksInWindow=10 failed=0([])
10-27 10:22:14.918 22476 22476 I flutter : RFV2|1793067734918|RESULT|V12b|run1|PASS|failed=0 AD2completed=true adFirstFrame->completed=5965ms (cfg 6000) started->completed=8371ms started->epochChange=2406ms oldTicksBeforeEpoch=10
10-27 10:22:15.297 22476 22476 I flutter : RFV2|1793067735297|V12b|run2 st title=C epoch=0 rendered=false playing=true buffering=true phase=idle
10-27 10:22:15.950 22476 22476 I flutter : RFV2|1793067735950|V12b|run2 st title=C epoch=0 rendered=true playing=true buffering=false phase=idle
10-27 10:22:19.176 22476 22476 I flutter : RFV2|1793067739176|V12b|run2 adEvent pending:AD1
10-27 10:22:19.269 22476 22476 I flutter : RFV2|1793067739269|V12b|run2 swapPhase=warming
10-27 10:22:19.284 22476 22476 I flutter : RFV2|1793067739284|V12b|run2 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 10:22:19.839 22476 22476 I flutter : RFV2|1793067739839|V12b|run2 swapPhase=ready
10-27 10:22:19.884 22476 22476 I flutter : RFV2|1793067739884|V12b|run2 st title=C epoch=0 rendered=true playing=true buffering=false phase=ready
10-27 10:22:20.129 22476 22476 I flutter : RFV2|1793067740129|V12b|run2 swapPhase=warming
10-27 10:22:20.185 22476 22476 I flutter : RFV2|1793067740185|V12b|run2 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 10:22:20.774 22476 22476 I flutter : RFV2|1793067740774|V12b|run2 swapPhase=ready
10-27 10:22:20.786 22476 22476 I flutter : RFV2|1793067740786|V12b|run2 st title=C epoch=0 rendered=true playing=true buffering=false phase=ready
10-27 10:22:21.385 22476 22476 I flutter : RFV2|1793067741385|V12b|run2 st title=C epoch=0 rendered=true playing=false buffering=false phase=ready
10-27 10:22:22.314 22476 22476 I flutter : RFV2|1793067742314|V12b|run2 adEvent started:AD1
10-27 10:22:22.314 22476 22476 I flutter : RFV2|1793067742314|V12b|run2 swapPhase=idle
10-27 10:22:22.384 22476 22476 I flutter : RFV2|1793067742384|V12b|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 10:22:22.494 22476 22476 I flutter : RFV2|1793067742494|V12b|run2 swapPhase=warming
10-27 10:22:22.584 22476 22476 I flutter : RFV2|1793067742584|V12b|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 10:22:23.268 22476 22476 I flutter : RFV2|1793067743268|V12b|run2 swapPhase=ready
10-27 10:22:23.289 22476 22476 I flutter : RFV2|1793067743289|V12b|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=ready
10-27 10:22:26.316 22476 22476 I flutter : RFV2|1793067746316|V12b|run2 adEvent completed:AD1
10-27 10:22:26.317 22476 22476 I flutter : RFV2|1793067746317|V12b|run2 adEvent started:AD2
10-27 10:22:26.351 22476 22476 I flutter : RFV2|1793067746351|V12b|run2 swapPhase=idle
10-27 10:22:26.391 22476 22476 I flutter : RFV2|1793067746391|V12b|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 10:22:26.428 22476 22476 I flutter : RFV2|1793067746428|V12b|run2 swapPhase=warming
10-27 10:22:26.484 22476 22476 I flutter : RFV2|1793067746484|V12b|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 10:22:27.018 22476 22476 I flutter : RFV2|1793067747018|V12b|run2 swapPhase=ready
10-27 10:22:27.084 22476 22476 I flutter : RFV2|1793067747084|V12b|run2 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=ready
10-27 10:22:28.530 22476 22476 I flutter : RFV2|1793067748530|V12b|run2 swapPhase=idle
10-27 10:22:28.585 22476 22476 I flutter : RFV2|1793067748585|V12b|run2 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=idle
10-27 10:22:28.717 22476 22476 I flutter : RFV2|1793067748717|V12b|run2 swapPhase=warming
10-27 10:22:28.787 22476 22476 I flutter : RFV2|1793067748787|V12b|run2 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=warming
10-27 10:22:34.156 22476 22476 I flutter : RFV2|1793067754155|V12b|run2 swapPhase=ready
10-27 10:22:34.184 22476 22476 I flutter : RFV2|1793067754184|V12b|run2 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=ready
10-27 10:22:34.531 22476 22476 I flutter : RFV2|1793067754531|V12b|run2 adEvent completed:AD2
10-27 10:22:36.075 22476 22476 I flutter : RFV2|1793067756075|V12b|run2 swapPhase=idle
10-27 10:22:36.090 22476 22476 I flutter : RFV2|1793067756090|V12b|run2 st title=C epoch=3 rendered=true playing=true buffering=false phase=idle
10-27 10:22:37.056 22476 22476 I flutter : RFV2|1793067757056|V12b|run2 epochs=3 epochRelToAD2Started=[-3989, 2214, 9773] AD2 started->epochChange=2214ms started->completed=8214ms adFirstFrame->completed=6000ms oldTicksInWindow=9 failed=0([])
10-27 10:22:37.056 22476 22476 I flutter : RFV2|1793067757056|RESULT|V12b|run2|PASS|failed=0 AD2completed=true adFirstFrame->completed=6000ms (cfg 6000) started->completed=8214ms started->epochChange=2214ms oldTicksBeforeEpoch=9
10-27 10:22:37.427 22476 22476 I flutter : RFV2|1793067757426|V12b|run3 st title=C epoch=0 rendered=false playing=true buffering=true phase=idle
10-27 10:22:38.094 22476 22476 I flutter : RFV2|1793067758094|V12b|run3 st title=C epoch=0 rendered=true playing=true buffering=false phase=idle
10-27 10:22:41.325 22476 22476 I flutter : RFV2|1793067761325|V12b|run3 adEvent pending:AD1
10-27 10:22:41.421 22476 22476 I flutter : RFV2|1793067761421|V12b|run3 swapPhase=warming
10-27 10:22:41.423 22476 22476 I flutter : RFV2|1793067761423|V12b|run3 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 10:22:42.088 22476 22476 I flutter : RFV2|1793067762088|V12b|run3 swapPhase=ready
10-27 10:22:42.123 22476 22476 I flutter : RFV2|1793067762123|V12b|run3 st title=C epoch=0 rendered=true playing=true buffering=false phase=ready
10-27 10:22:42.345 22476 22476 I flutter : RFV2|1793067762345|V12b|run3 swapPhase=warming
10-27 10:22:42.558 22476 22476 I flutter : RFV2|1793067762558|V12b|run3 st title=C epoch=0 rendered=true playing=true buffering=false phase=warming
10-27 10:22:43.033 22476 22476 I flutter : RFV2|1793067763033|V12b|run3 swapPhase=ready
10-27 10:22:43.131 22476 22476 I flutter : RFV2|1793067763131|V12b|run3 st title=C epoch=0 rendered=true playing=true buffering=false phase=ready
10-27 10:22:43.625 22476 22476 I flutter : RFV2|1793067763625|V12b|run3 st title=C epoch=0 rendered=true playing=false buffering=false phase=ready
10-27 10:22:44.579 22476 22476 I flutter : RFV2|1793067764579|V12b|run3 adEvent started:AD1
10-27 10:22:44.580 22476 22476 I flutter : RFV2|1793067764580|V12b|run3 swapPhase=idle
10-27 10:22:44.625 22476 22476 I flutter : RFV2|1793067764625|V12b|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 10:22:44.680 22476 22476 I flutter : RFV2|1793067764680|V12b|run3 swapPhase=warming
10-27 10:22:44.723 22476 22476 I flutter : RFV2|1793067764722|V12b|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 10:22:48.582 22476 22476 I flutter : RFV2|1793067768582|V12b|run3 adEvent completed:AD1
10-27 10:22:48.582 22476 22476 I flutter : RFV2|1793067768582|V12b|run3 adEvent started:AD2
10-27 10:22:48.614 22476 22476 I flutter : RFV2|1793067768614|V12b|run3 swapPhase=idle
10-27 10:22:48.624 22476 22476 I flutter : RFV2|1793067768624|V12b|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=idle
10-27 10:22:48.729 22476 22476 I flutter : RFV2|1793067768729|V12b|run3 swapPhase=warming
10-27 10:22:48.917 22476 22476 I flutter : RFV2|1793067768917|V12b|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=warming
10-27 10:22:49.389 22476 22476 I flutter : RFV2|1793067769389|V12b|run3 swapPhase=ready
10-27 10:22:49.427 22476 22476 I flutter : RFV2|1793067769427|V12b|run3 st title=AD1 epoch=1 rendered=true playing=true buffering=false phase=ready
10-27 10:22:50.896 22476 22476 I flutter : RFV2|1793067770896|V12b|run3 swapPhase=idle
10-27 10:22:50.929 22476 22476 I flutter : RFV2|1793067770928|V12b|run3 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=idle
10-27 10:22:51.070 22476 22476 I flutter : RFV2|1793067771070|V12b|run3 swapPhase=warming
10-27 10:22:51.122 22476 22476 I flutter : RFV2|1793067771122|V12b|run3 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=warming
10-27 10:22:51.937 22476 22476 I flutter : RFV2|1793067771937|V12b|run3 swapPhase=ready
10-27 10:22:52.022 22476 22476 I flutter : RFV2|1793067772022|V12b|run3 st title=AD2 epoch=2 rendered=true playing=true buffering=false phase=ready
10-27 10:22:56.897 22476 22476 I flutter : RFV2|1793067776897|V12b|run3 adEvent completed:AD2
10-27 10:22:58.442 22476 22476 I flutter : RFV2|1793067778442|V12b|run3 st title=AD2 epoch=2 rendered=true playing=false buffering=false phase=ready
10-27 10:22:58.443 22476 22476 I flutter : RFV2|1793067778443|V12b|run3 swapPhase=idle
10-27 10:22:58.522 22476 22476 I flutter : RFV2|1793067778522|V12b|run3 st title=C epoch=3 rendered=true playing=true buffering=false phase=idle
10-27 10:22:59.421 22476 22476 I flutter : RFV2|1793067779421|V12b|run3 epochs=3 epochRelToAD2Started=[-4000, 2346, 9863] AD2 started->epochChange=2346ms started->completed=8315ms adFirstFrame->completed=5969ms oldTicksInWindow=11 failed=0([])
10-27 10:22:59.422 22476 22476 I flutter : RFV2|1793067779422|RESULT|V12b|run3|PASS|failed=0 AD2completed=true adFirstFrame->completed=5969ms (cfg 6000) started->completed=8315ms started->epochChange=2346ms oldTicksBeforeEpoch=11
10-27 10:22:59.685 22476 22476 I flutter : RFV2|1793067779685|GROUP|end v12b uncaught=0
10-27 10:22:59.685 22476 22476 I flutter : RFV2|1793067779685|GROUP|begin v13a
10-27 10:22:59.812 22476 22476 I flutter : RFV2|1793067779812|V13a|run1 state rate=1.0 title=C epoch=0
10-27 10:23:01.353 22476 22476 I flutter : RFV2|1793067781353|V13a|run1 setRate(2.0) -> state.rate=1.0
10-27 10:23:01.404 22476 22476 I flutter : RFV2|1793067781403|V13a|run1 state rate=2.0 title=C epoch=0
10-27 10:23:04.219 22476 22476 I flutter : RFV2|1793067784219|V13a|run1 adEvent pending
10-27 10:23:05.113 22476 22476 I flutter : RFV2|1793067785113|V13a|run1 adEvent started
10-27 10:23:05.203 22476 22476 I flutter : RFV2|1793067785203|V13a|run1 state rate=1.0 title=AD epoch=1
10-27 10:23:10.114 22476 22476 I flutter : RFV2|1793067790114|V13a|run1 adEvent completed
10-27 10:23:13.211 22476 22476 I flutter : RFV2|1793067793211|V13a|run1 state rate=1.0 title=C epoch=1
10-27 10:23:13.520 22476 22476 I flutter : RFV2|1793067793520|V13a|run1 state rate=2.0 title=C epoch=1
10-27 10:23:16.570 22476 22476 I flutter : RFV2|1793067796570|V13a|run1 completedAt=1793067790114 adRateSamples=47 adMaxRate=1.0 adSettled1x=true backRate=2.0 title=C
10-27 10:23:16.570 22476 22476 I flutter : RFV2|1793067796570|RESULT|V13a|run1|PASS|adRate settled1x=true (max seen 1.0x over 47 samples) rateAfterReturn=2.0 want=2.0
10-27 10:23:16.881 22476 22476 I flutter : RFV2|1793067796881|V13a|run2 state rate=1.0 title=C epoch=0
10-27 10:23:18.590 22476 22476 I flutter : RFV2|1793067798590|V13a|run2 setRate(2.0) -> state.rate=1.0
10-27 10:23:18.682 22476 22476 I flutter : RFV2|1793067798682|V13a|run2 state rate=2.0 title=C epoch=0
10-27 10:23:21.400 22476 22476 I flutter : RFV2|1793067801400|V13a|run2 adEvent pending
10-27 10:23:22.468 22476 22476 I flutter : RFV2|1793067802468|V13a|run2 adEvent started
10-27 10:23:22.504 22476 22476 I flutter : RFV2|1793067802504|V13a|run2 state rate=1.0 title=AD epoch=1
10-27 10:23:27.473 22476 22476 I flutter : RFV2|1793067807473|V13a|run2 adEvent completed
10-27 10:23:30.581 22476 22476 I flutter : RFV2|1793067810581|V13a|run2 state rate=1.0 title=C epoch=1
10-27 10:23:30.684 22476 22476 I flutter : RFV2|1793067810684|V13a|run2 state rate=2.0 title=C epoch=1
10-27 10:23:33.857 22476 22476 I flutter : RFV2|1793067813857|V13a|run2 completedAt=1793067807473 adRateSamples=47 adMaxRate=1.0 adSettled1x=true backRate=2.0 title=C
10-27 10:23:33.857 22476 22476 I flutter : RFV2|1793067813857|RESULT|V13a|run2|PASS|adRate settled1x=true (max seen 1.0x over 47 samples) rateAfterReturn=2.0 want=2.0
10-27 10:23:34.228 22476 22476 I flutter : RFV2|1793067814228|V13a|run3 state rate=1.0 title=C epoch=0
10-27 10:23:35.738 22476 22476 I flutter : RFV2|1793067815738|V13a|run3 setRate(2.0) -> state.rate=1.0
10-27 10:23:35.829 22476 22476 I flutter : RFV2|1793067815829|V13a|run3 state rate=2.0 title=C epoch=0
10-27 10:23:38.744 22476 22476 I flutter : RFV2|1793067818744|V13a|run3 adEvent pending
10-27 10:23:39.677 22476 22476 I flutter : RFV2|1793067819677|V13a|run3 adEvent started
10-27 10:23:39.730 22476 22476 I flutter : RFV2|1793067819730|V13a|run3 state rate=1.0 title=AD epoch=1
10-27 10:23:44.679 22476 22476 I flutter : RFV2|1793067824679|V13a|run3 adEvent completed
10-27 10:23:44.727 22476 22476 I flutter : RFV2|1793067824727|V13a|run3 state rate=2.0 title=C epoch=2
10-27 10:23:47.726 22476 22476 I flutter : RFV2|1793067827726|V13a|run3 completedAt=1793067824678 adRateSamples=46 adMaxRate=1.0 adSettled1x=true backRate=2.0 title=C
10-27 10:23:47.727 22476 22476 I flutter : RFV2|1793067827727|RESULT|V13a|run3|PASS|adRate settled1x=true (max seen 1.0x over 46 samples) rateAfterReturn=2.0 want=2.0
10-27 10:23:47.903 22476 22476 I flutter : RFV2|1793067827903|GROUP|end v13a uncaught=0
10-27 10:23:47.904 22476 22476 I flutter : RFV2|1793067827904|GROUP|begin v13b
10-27 10:23:48.027 22476 22476 I flutter : RFV2|1793067828027|V13b|run1 state rate=1.0 title=C epoch=0
10-27 10:23:51.252 22476 22476 I flutter : RFV2|1793067831252|V13b|run1 setRate(1.5) -> state.rate=1.0
10-27 10:23:51.253 22476 22476 I flutter : RFV2|1793067831253|V13b|run1 adEvent pending
10-27 10:23:51.327 22476 22476 I flutter : RFV2|1793067831327|V13b|run1 state rate=1.5 title=C epoch=0
10-27 10:23:52.110 22476 22476 I flutter : RFV2|1793067832110|V13b|run1 adEvent started
10-27 10:23:52.136 22476 22476 I flutter : RFV2|1793067832136|V13b|run1 state rate=1.0 title=AD epoch=1
10-27 10:23:56.113 22476 22476 I flutter : RFV2|1793067836113|V13b|run1 adEvent completed
10-27 10:23:56.228 22476 22476 I flutter : RFV2|1793067836228|V13b|run1 state rate=1.5 title=C epoch=2
10-27 10:23:59.190 22476 22476 I flutter : RFV2|1793067839189|V13b|run1 completedAt=1793067836113 adRateSamples=38 adMaxRate=1.0 adSettled1x=true backRate=1.5 title=C
10-27 10:23:59.190 22476 22476 I flutter : RFV2|1793067839190|RESULT|V13b|run1|PASS|adRate settled1x=true (max seen 1.0x over 38 samples) rateAfterReturn=1.5 want=1.5
10-27 10:23:59.584 22476 22476 I flutter : RFV2|1793067839584|V13b|run2 state rate=1.0 title=C epoch=0
10-27 10:24:02.779 22476 22476 I flutter : RFV2|1793067842779|V13b|run2 setRate(1.5) -> state.rate=1.0
10-27 10:24:02.779 22476 22476 I flutter : RFV2|1793067842779|V13b|run2 adEvent pending
10-27 10:24:02.813 22476 22476 I flutter : RFV2|1793067842813|V13b|run2 state rate=1.5 title=C epoch=0
10-27 10:24:03.761 22476 22476 I flutter : RFV2|1793067843761|V13b|run2 adEvent started
10-27 10:24:03.780 22476 22476 I flutter : RFV2|1793067843780|V13b|run2 state rate=1.0 title=AD epoch=1
10-27 10:24:07.763 22476 22476 I flutter : RFV2|1793067847763|V13b|run2 adEvent completed
10-27 10:24:07.981 22476 22476 I flutter : RFV2|1793067847981|V13b|run2 state rate=1.5 title=C epoch=2
10-27 10:24:11.004 22476 22476 I flutter : RFV2|1793067851004|V13b|run2 completedAt=1793067847763 adRateSamples=36 adMaxRate=1.0 adSettled1x=true backRate=1.5 title=C
10-27 10:24:11.005 22476 22476 I flutter : RFV2|1793067851005|RESULT|V13b|run2|PASS|adRate settled1x=true (max seen 1.0x over 36 samples) rateAfterReturn=1.5 want=1.5
10-27 10:24:11.303 22476 22476 I flutter : RFV2|1793067851303|V13b|run3 state rate=1.0 title=C epoch=0
10-27 10:24:14.554 22476 22476 I flutter : RFV2|1793067854554|V13b|run3 setRate(1.5) -> state.rate=1.0
10-27 10:24:14.555 22476 22476 I flutter : RFV2|1793067854555|V13b|run3 adEvent pending
10-27 10:24:14.610 22476 22476 I flutter : RFV2|1793067854610|V13b|run3 state rate=1.5 title=C epoch=0
10-27 10:24:15.717 22476 22476 I flutter : RFV2|1793067855717|V13b|run3 adEvent started
10-27 10:24:15.805 22476 22476 I flutter : RFV2|1793067855805|V13b|run3 state rate=1.0 title=AD epoch=1
10-27 10:24:19.718 22476 22476 I flutter : RFV2|1793067859718|V13b|run3 adEvent completed
10-27 10:24:20.417 22476 22476 I flutter : RFV2|1793067860417|V13b|run3 state rate=1.5 title=C epoch=2
10-27 10:24:23.380 22476 22476 I flutter : RFV2|1793067863380|V13b|run3 completedAt=1793067859718 adRateSamples=36 adMaxRate=1.0 adSettled1x=true backRate=1.5 title=C
10-27 10:24:23.380 22476 22476 I flutter : RFV2|1793067863380|RESULT|V13b|run3|PASS|adRate settled1x=true (max seen 1.0x over 36 samples) rateAfterReturn=1.5 want=1.5
10-27 10:24:23.561 22476 22476 I flutter : RFV2|1793067863561|GROUP|end v13b uncaught=0
10-27 10:24:23.561 22476 22476 I flutter : RFV2|1793067863561|GROUP|begin v14
10-27 10:24:23.581 22476 22476 I flutter : RFV2|1793067863581|V14|run1 adEvent started
10-27 10:24:31.894 22476 22476 I flutter : RFV2|1793067871894|V14|run1 adEvent completed
10-27 10:24:31.938 22476 22476 I flutter : RFV2|1793067871938|V14|run1 started->completed=8313ms failed=0 skipped=0 errorEventsDuringAd=0 shadowThrowFired=true contentPlaying=true title=C adDoneAt=1793067871938
10-27 10:24:31.938 22476 22476 I flutter : RFV2|1793067871938|RESULT|V14|run1|PASS|failed=0 skipped=0 adPlayed=8313ms (cfg 8000) errorEventsDuringAd=0 shadowOpenThrew=true contentReached=true
10-27 10:24:32.172 22476 22476 I flutter : RFV2|1793067872172|V14|run2 adEvent started
10-27 10:24:40.415 22476 22476 I flutter : RFV2|1793067880415|V14|run2 adEvent completed
10-27 10:24:40.463 22476 22476 I flutter : RFV2|1793067880463|V14|run2 started->completed=8243ms failed=0 skipped=0 errorEventsDuringAd=0 shadowThrowFired=true contentPlaying=true title=C adDoneAt=1793067880462
10-27 10:24:40.463 22476 22476 I flutter : RFV2|1793067880463|RESULT|V14|run2|PASS|failed=0 skipped=0 adPlayed=8243ms (cfg 8000) errorEventsDuringAd=0 shadowOpenThrew=true contentReached=true
10-27 10:24:40.707 22476 22476 I flutter : RFV2|1793067880707|V14|run3 adEvent started
10-27 10:24:49.029 22476 22476 I flutter : RFV2|1793067889029|V14|run3 adEvent completed
10-27 10:24:49.081 22476 22476 I flutter : RFV2|1793067889081|V14|run3 started->completed=8322ms failed=0 skipped=0 errorEventsDuringAd=0 shadowThrowFired=true contentPlaying=true title=C adDoneAt=1793067889081
10-27 10:24:49.081 22476 22476 I flutter : RFV2|1793067889081|RESULT|V14|run3|PASS|failed=0 skipped=0 adPlayed=8322ms (cfg 8000) errorEventsDuringAd=0 shadowOpenThrew=true contentReached=true
10-27 10:24:49.310 22476 22476 I flutter : RFV2|1793067889310|GROUP|end v14 uncaught=0
10-27 10:24:49.310 22476 22476 I flutter : RFV2|1793067889310|DONE|group=all uncaught=0
```

## batch12-pump 自动检查点

- 复用页运行；逐编号最终结论需结合下面原始断言复核。
- driver exit=0；`{"selector": "pump||1", "completed": true, "lines": 701, "pid": "5044"}`。
- 日志：`example/tool/coverage_evidence/batch12-pump.log`；截图/系统读回/采样同前缀。
```text
10-27 10:25:06.885  5044  5044 I flutter : V3 PASS
10-27 10:25:11.138  5044  5044 I flutter : V6 PASS
10-27 10:25:13.210  5044  5044 I flutter : V9 PASS
10-27 10:27:31.371  5044  5044 I flutter : V7 PASS
10-27 10:27:31.371  5044  5044 I flutter : COUNTS created=14 destroyed=14 PASS
10-27 10:27:31.371  5044  5044 I flutter : ALL_DONE
```

## batch13-subtitles 自动检查点

- 复用页运行；逐编号最终结论需结合下面原始断言复核。
- driver exit=0；`{"selector": "subtitles||1", "completed": false, "lines": 368, "pid": "5045"}`。
- 日志：`example/tool/coverage_evidence/batch13-subtitles.log`；截图/系统读回/采样同前缀。
```text
10-27 10:27:36.744  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=1 pos=0.066667 sub-text=""
10-27 10:27:37.244  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=2 pos=0.633333 sub-text=""
10-27 10:27:37.744  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=3 pos=1.133333 sub-text="ASS regression check line 1 - MOVA SUBTITLE TEST"
10-27 10:27:38.244  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=4 pos=1.633333 sub-text="ASS regression check line 1 - MOVA SUBTITLE TEST"
10-27 10:27:38.744  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=5 pos=2.133333 sub-text="ASS regression check line 1 - MOVA SUBTITLE TEST"
10-27 10:27:39.244  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=6 pos=2.633333 sub-text="ASS regression check line 1 - MOVA SUBTITLE TEST"
10-27 10:27:39.745  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=7 pos=3.133333 sub-text="ASS regression check line 1 - MOVA SUBTITLE TEST"
10-27 10:27:40.245  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=8 pos=3.633333 sub-text=""
10-27 10:27:40.749  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=9 pos=4.133333 sub-text=""
10-27 10:27:41.247  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=10 pos=4.633333 sub-text=""
10-27 10:27:41.756  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=11 pos=5.166667 sub-text="ASS regression check line 2 - libass render OK"
10-27 10:27:42.244  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=12 pos=5.633333 sub-text="ASS regression check line 2 - libass render OK"
10-27 10:27:42.750  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=13 pos=6.166667 sub-text="ASS regression check line 2 - libass render OK"
10-27 10:27:43.251  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=14 pos=6.633333 sub-text="ASS regression check line 2 - libass render OK"
10-27 10:27:43.745  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=15 pos=7.133333 sub-text="ASS regression check line 2 - libass render OK"
10-27 10:27:44.245  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=16 pos=7.633333 sub-text=""
10-27 10:27:44.765  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=17 pos=8.166667 sub-text=""
10-27 10:27:45.251  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=18 pos=8.633333 sub-text=""
10-27 10:27:45.745  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=19 pos=9.133333 sub-text="ASS regression check line 3 - overlay/equalizer removed, subs still work"
10-27 10:27:46.251  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=20 pos=9.633333 sub-text="ASS regression check line 3 - overlay/equalizer removed, subs still work"
10-27 10:27:46.751  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=21 pos=10.133333 sub-text="ASS regression check line 3 - overlay/equalizer removed, subs still work"
10-27 10:27:47.245  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=22 pos=10.633333 sub-text="ASS regression check line 3 - overlay/equalizer removed, subs still work"
10-27 10:27:47.770  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=23 pos=11.166667 sub-text="ASS regression check line 3 - overlay/equalizer removed, subs still work"
10-27 10:27:48.247  5045  5045 I flutter : SUBFMT_PROBE[ASS] t=24 pos=11.633333 sub-text=""
```

## batch14-api-launch 自动检查点

- 复用页运行；逐编号最终结论需结合下面原始断言复核。
- driver exit=0；`{"selector": "api||1", "completed": true, "lines": 163, "pid": "5046"}`。
- 日志：`example/tool/coverage_evidence/batch14-api-launch.log`；截图/系统读回/采样同前缀。
```text
```

## batch15-basic 自动检查点

- 命令 `basic {}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-basic.json` 及同前缀文件。
```json
[
  {
    "ms": 2789,
    "kind": "BEGIN",
    "group": "basic",
    "args": {
      "group": "basic"
    }
  },
  {
    "ms": 2803,
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
    "swap": false
  },
  {
    "ms": 2803,
    "kind": "CHECK",
    "id": "A1.broadcast",
    "pass": false,
    "detail": "all streams broadcast swap=false"
  },
  {
    "ms": 2803,
    "kind": "CHECK",
    "id": "A3.audio",
    "pass": true,
    "detail": "handle=null"
  },
  {
    "ms": 2871,
    "kind": "CHECK",
    "id": "A5.paused",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 0, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: false, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: true, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 5111,
    "kind": "CHECK",
    "id": "A4",
    "pass": true,
    "detail": "supported=true"
  },
  {
    "ms": 6285,
    "kind": "CHECK",
    "id": "A1.progress",
    "pass": true,
    "detail": "0:00:02.144893 -> 0:00:03.195336"
  },
  {
    "ms": 6449,
    "kind": "CHECK",
    "id": "A6.pause",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 3195, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 6509,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=5000 landed=5000"
  },
  {
    "ms": 6563,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=10000 landed=10000"
  },
  {
    "ms": 6606,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=15000 landed=15000"
  },
  {
    "ms": 6649,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=5000 landed=5000"
  },
  {
    "ms": 6692,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=10000 landed=10000"
  },
  {
    "ms": 7005,
    "kind": "CHECK",
    "id": "A7.negative",
    "pass": true,
    "detail": "0:00:00.000000"
  },
  {
    "ms": 7193,
    "kind": "SAMPLE",
    "name": "volume-10.0",
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 23,
      "size": "0x0",
      "volume": -10.0,
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 7194,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": false,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: -10.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 7380,
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 7381,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 0.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 7561,
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 7561,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 1.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 7765,
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 7766,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 50.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 7957,
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 7958,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 100.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 8129,
    "kind": "SAMPLE",
    "name": "volume110.0",
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 23,
      "size": "0x0",
      "volume": 110.0,
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 8130,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": false,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 110.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 8325,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": false,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: -1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 8486,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 0.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 8640,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 0.5, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 8795,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 8948,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": false,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 2.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 8956,
    "kind": "RATE",
    "input": 0.5,
    "actual": 0.5
  },
  {
    "ms": 8960,
    "kind": "RATE",
    "input": 1.0,
    "actual": 1.0
  },
  {
    "ms": 8963,
    "kind": "RATE",
    "input": 1.5,
    "actual": 1.5
  },
  {
    "ms": 8965,
    "kind": "RATE",
    "input": 2.0,
    "actual": 2.0
  },
  {
    "ms": 8967,
    "kind": "RATE_REJECT",
    "input": -1.0,
    "error": "Invalid argument (rate): Must be greater than 0.0: -1.0"
  },
  {
    "ms": 8968,
    "kind": "RATE_REJECT",
    "input": 0.0,
    "error": "Invalid argument (rate): Must be greater than 0.0: 0.0"
  },
  {
    "ms": 8989,
    "kind": "CHECK",
    "id": "A21.hide",
    "pass": true,
    "detail": "false"
  },
  {
    "ms": 9141,
    "kind": "CHECK",
    "id": "A21.hud",
    "pass": true,
    "detail": "MovaHud.seek"
  },
  {
    "ms": 9142,
    "kind": "CHECK",
    "id": "A22",
    "pass": true,
    "detail": "[pause:{}, sourceChange:{uri: http://127.0.0.1:18080/vod.mp4?t=1793068158657289}, play:{}, pause:{}, play:{}, pause:{}, seek:{targetMs: 5000}, seeked:{positionMs: 5000}, seek:{targetMs: 10000}, seeked:{positionMs: 10000}, seek:{targetMs: 15000}, seeked:{positionMs: 15000}, seek:{targetMs: 5000}, seeked:{positionMs: 5000}, seek:{targetMs: 10000}, seeked:{positionMs: 10000}, seek:{targetMs: 8000}, seeked:{positionMs: 8000}, seek:{targetMs: 0}, seeked:{positionMs: 0}, coverage:{probe: 42}, play:{probe: 43}]"
  },
  {
    "ms": 9806,
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
    "standby": "off",
    "type": "vod",
    "title": "Coverage vod.mp4",
    "pipSupported": true,
    "controls": false,
    "hud": "none",
    "hudText": null,
    "dragging": false,
    "previewAt": null
  },
  {
    "ms": 10028,
    "kind": "CHECK",
    "id": "A10.persist",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 20000, position: 0, size: 0x0, volume: 30.0, brightness: 0.5, rate: 1.5, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: false, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage ad.mp4, pipSupported: true, controls: true, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 10177,
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
    "standby": "off",
    "type": "vod",
    "title": "Coverage ad.mp4",
    "pipSupported": true,
    "controls": true,
    "hud": "none",
    "hudText": null,
    "dragging": false,
    "previewAt": null
  },
  {
    "ms": 10178,
    "kind": "CHECK",
    "id": "E2.disabled",
    "pass": true,
    "detail": "count=0"
  },
  {
    "ms": 10178,
    "kind": "CHECK",
    "id": "C13.off",
    "pass": true,
    "detail": "QoE reports=24"
  },
  {
    "ms": 10349,
    "kind": "CHECK",
    "id": "A1.closed",
    "pass": true,
    "detail": "counts=[59, 59, 47, 47, 23, 23, 9, 9] closed=[true, true, true, true, true, true, true, true]"
  },
  {
    "ms": 10350,
    "kind": "CHECK",
    "id": "A23.doubleDispose",
    "pass": false,
    "detail": "Assertion failed: \"[Player] has been disposed\""
  },
  {
    "ms": 10351,
    "kind": "CHECK",
    "id": "A23.postOpen",
    "pass": true,
    "detail": "disposed open=false"
  },
  {
    "ms": 10351,
    "kind": "BASIC_DONE",
    "swap": false,
    "events": 59
  },
  {
    "ms": 10351,
    "kind": "END",
    "group": "basic",
    "status": "done"
  }
]
```

## batch15-basic-swap 自动检查点

- 命令 `basic {'swap': 'true'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-basic-swap.json` 及同前缀文件。
```json
[
  {
    "ms": 13616,
    "kind": "BEGIN",
    "group": "basic",
    "args": {
      "group": "basic",
      "swap": "true"
    }
  },
  {
    "ms": 13643,
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
    "swap": true
  },
  {
    "ms": 13644,
    "kind": "CHECK",
    "id": "A1.broadcast",
    "pass": false,
    "detail": "all streams broadcast swap=true"
  },
  {
    "ms": 13644,
    "kind": "CHECK",
    "id": "A3.audio",
    "pass": true,
    "detail": "handle=null"
  },
  {
    "ms": 13879,
    "kind": "CHECK",
    "id": "A5.paused",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 0, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: false, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: true, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 16181,
    "kind": "CHECK",
    "id": "A4",
    "pass": true,
    "detail": "supported=true"
  },
  {
    "ms": 17135,
    "kind": "CHECK",
    "id": "A1.progress",
    "pass": true,
    "detail": "0:00:02.144748 -> 0:00:03.145888"
  },
  {
    "ms": 17291,
    "kind": "CHECK",
    "id": "A6.pause",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 3145, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 17349,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=5000 landed=5000"
  },
  {
    "ms": 17401,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=10000 landed=10000"
  },
  {
    "ms": 17445,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=15000 landed=15000"
  },
  {
    "ms": 17493,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=5000 landed=5000"
  },
  {
    "ms": 17537,
    "kind": "CHECK",
    "id": "A7.seek",
    "pass": true,
    "detail": "target=10000 landed=10000"
  },
  {
    "ms": 17849,
    "kind": "CHECK",
    "id": "A7.negative",
    "pass": true,
    "detail": "0:00:00.000000"
  },
  {
    "ms": 18081,
    "kind": "SAMPLE",
    "name": "volume-10.0",
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 23,
      "size": "0x0",
      "volume": -10.0,
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 18082,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": false,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: -10.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 18276,
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 18277,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 0.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 18489,
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 18489,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 1.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 18676,
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 18677,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 50.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 18868,
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 18869,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 100.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 19058,
    "kind": "SAMPLE",
    "name": "volume110.0",
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 23,
      "size": "0x0",
      "volume": 110.0,
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 19058,
    "kind": "CHECK",
    "id": "A8.clamp",
    "pass": false,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 110.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 19271,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": false,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: -1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 19424,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 0.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 19580,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 0.5, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 19735,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 19887,
    "kind": "CHECK",
    "id": "A9.clamp",
    "pass": false,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 2.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: false, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 19919,
    "kind": "RATE",
    "input": 0.5,
    "actual": 1.0
  },
  {
    "ms": 19922,
    "kind": "RATE",
    "input": 1.0,
    "actual": 0.5
  },
  {
    "ms": 19925,
    "kind": "RATE",
    "input": 1.5,
    "actual": 1.0
  },
  {
    "ms": 19927,
    "kind": "RATE",
    "input": 2.0,
    "actual": 1.5
  },
  {
    "ms": 19928,
    "kind": "RATE_REJECT",
    "input": -1.0,
    "error": "Invalid argument (rate): Must be greater than 0.0: -1.0"
  },
  {
    "ms": 19929,
    "kind": "RATE_REJECT",
    "input": 0.0,
    "error": "Invalid argument (rate): Must be greater than 0.0: 0.0"
  },
  {
    "ms": 19931,
    "kind": "CHECK",
    "id": "A21.hide",
    "pass": true,
    "detail": "false"
  },
  {
    "ms": 20084,
    "kind": "CHECK",
    "id": "A21.hud",
    "pass": true,
    "detail": "MovaHud.seek"
  },
  {
    "ms": 20084,
    "kind": "CHECK",
    "id": "A22",
    "pass": true,
    "detail": "[pause:{}, sourceChange:{uri: http://127.0.0.1:18080/vod.mp4?t=1793068169497603}, play:{}, pause:{}, play:{}, pause:{}, seek:{targetMs: 5000}, seeked:{positionMs: 5000}, seek:{targetMs: 10000}, seeked:{positionMs: 10000}, seek:{targetMs: 15000}, seeked:{positionMs: 15000}, seek:{targetMs: 5000}, seeked:{positionMs: 5000}, seek:{targetMs: 10000}, seeked:{positionMs: 10000}, seek:{targetMs: 8000}, seeked:{positionMs: 8000}, seek:{targetMs: 0}, seeked:{positionMs: 0}, coverage:{probe: 42}, play:{probe: 43}]"
  },
  {
    "ms": 20749,
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
    "standby": "off",
    "type": "vod",
    "title": "Coverage vod.mp4",
    "pipSupported": true,
    "controls": false,
    "hud": "none",
    "hudText": null,
    "dragging": false,
    "previewAt": null
  },
  {
    "ms": 20908,
    "kind": "CHECK",
    "id": "A10.persist",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 20000, position: 0, size: 0x0, volume: 30.0, brightness: 0.5, rate: 1.5, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: false, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage ad.mp4, pipSupported: true, controls: true, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 21127,
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
    "standby": "off",
    "type": "vod",
    "title": "Coverage ad.mp4",
    "pipSupported": true,
    "controls": true,
    "hud": "none",
    "hudText": null,
    "dragging": false,
    "previewAt": null
  },
  {
    "ms": 21128,
    "kind": "CHECK",
    "id": "E2.disabled",
    "pass": true,
    "detail": "count=0"
  },
  {
    "ms": 21128,
    "kind": "CHECK",
    "id": "C13.off",
    "pass": true,
    "detail": "QoE reports=24"
  },
  {
    "ms": 21294,
    "kind": "CHECK",
    "id": "A1.closed",
    "pass": true,
    "detail": "counts=[59, 59, 47, 47, 24, 24, 9, 9] closed=[true, true, true, true, true, true, true, true]"
  },
  {
    "ms": 21295,
    "kind": "CHECK",
    "id": "A23.doubleDispose",
    "pass": false,
    "detail": "Assertion failed: \"[Player] has been disposed\""
  },
  {
    "ms": 21295,
    "kind": "CHECK",
    "id": "A23.postOpen",
    "pass": true,
    "detail": "disposed open=false"
  },
  {
    "ms": 21296,
    "kind": "BASIC_DONE",
    "swap": true,
    "events": 59
  },
  {
    "ms": 21296,
    "kind": "END",
    "group": "basic",
    "status": "done"
  }
]
```

## batch15-testing 自动检查点

- 命令 `testing {}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-testing.json` 及同前缀文件。
```json
[
  {
    "ms": 24222,
    "kind": "BEGIN",
    "group": "testing",
    "args": {
      "group": "testing"
    }
  },
  {
    "ms": 24237,
    "kind": "CHECK",
    "id": "A33",
    "pass": true,
    "detail": "kernels=1 pip=false"
  },
  {
    "ms": 24237,
    "kind": "STAGED_OPTIONS",
    "options": [
      {
        "network-timeout": "7"
      }
    ]
  },
  {
    "ms": 24237,
    "kind": "END",
    "group": "testing",
    "status": "done"
  }
]
```

## batch15-options 自动检查点

- 命令 `new {'case': 'options'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-options.json` 及同前缀文件。
```json
[
  {
    "ms": 27534,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "options"
    }
  },
  {
    "ms": 27841,
    "kind": "CHECK",
    "id": "N4.applied",
    "pass": false,
    "detail": "{network-timeout: 7.000000, demuxer-lavf-o: seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto,analyzeduration=123456, cache: no, vid: no, mute: no}"
  },
  {
    "ms": 28030,
    "kind": "CHECK",
    "id": "N1.network",
    "pass": false,
    "detail": "{network-timeout: 2.000000, demuxer-lavf-o: seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto, cache: yes, vid: no, mute: no}"
  },
  {
    "ms": 28031,
    "kind": "CHECK",
    "id": "N4.restore",
    "pass": true,
    "detail": "{before: {network-timeout: 5.000000, demuxer-lavf-o: seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto, cache: yes, vid: no, mute: no}, custom: {network-timeout: 7.000000, demuxer-lavf-o: seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto,analyzeduration=123456, cache: no, vid: no, mute: no}, restored: {network-timeout: 2.000000, demuxer-lavf-o: seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto, cache: yes, vid: no, mute: no}}"
  },
  {
    "ms": 28064,
    "kind": "WHEP_OPTIONS_READBACK",
    "network-timeout": "1.000000",
    "demuxer-lavf-o": "seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto,first_frame_timeout=8000000,media_timeout=6000000,handshake_timeout=2000000",
    "cache": "yes",
    "vid": "no",
    "mute": "no"
  },
  {
    "ms": 28064,
    "kind": "CHECK",
    "id": "N4.whepOptions",
    "pass": true,
    "detail": "readback={network-timeout: 1.000000, demuxer-lavf-o: seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto,first_frame_timeout=8000000,media_timeout=6000000,handshake_timeout=2000000, cache: yes, vid: no, mute: no}"
  },
  {
    "ms": 28206,
    "kind": "WHEP_OPTIONS_RESTORED",
    "network-timeout": "2.000000",
    "demuxer-lavf-o": "seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=udp,rtp,tcp,tls,data,file,http,https,crypto",
    "cache": "yes",
    "vid": "no",
    "mute": "no"
  },
  {
    "ms": 28206,
    "kind": "CHECK",
    "id": "N2.derived",
    "pass": true,
    "detail": "http=65,whepStart=85,whepStall=10,watchdogOff=null,clear=null"
  },
  {
    "ms": 28207,
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
    "ms": 28207,
    "kind": "CHECK",
    "id": "C17.pick",
    "pass": true,
    "detail": "[http://a, http://b]"
  },
  {
    "ms": 28562,
    "kind": "HEADERS_NATIVE",
    "options": "X-Coverage: 42"
  },
  {
    "ms": 28623,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-hooks 自动检查点

- 命令 `new {'case': 'hooks'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-hooks.json` 及同前缀文件。
```json
[
  {
    "ms": 31409,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hooks"
    }
  },
  {
    "ms": 31453,
    "kind": "CHECK",
    "id": "N8.reject",
    "pass": true,
    "detail": "beforeOpen=false"
  },
  {
    "ms": 31519,
    "kind": "CHECK",
    "id": "N8.accept",
    "pass": true,
    "detail": "accepted=true"
  },
  {
    "ms": 31912,
    "kind": "CHECK",
    "id": "N22.stalePlay",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: true, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 33156,
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
    "standby": "off",
    "type": "vod",
    "title": "Coverage ad.mp4",
    "pipSupported": true,
    "controls": true,
    "hud": "none",
    "hudText": null,
    "dragging": false,
    "previewAt": null
  },
  {
    "ms": 33156,
    "kind": "HOOK_PLAYLIST",
    "index": 0
  },
  {
    "ms": 33157,
    "kind": "CHECK",
    "id": "N8.playlistRejected",
    "pass": true,
    "detail": "rejected jumpTo(1), index=0"
  },
  {
    "ms": 33320,
    "kind": "CHECK",
    "id": "N8.superseded",
    "pass": true,
    "detail": "first=false second=true"
  },
  {
    "ms": 33320,
    "kind": "HOOK_EXPECTED_THROW",
    "error": "Bad state: coverage hook failure"
  },
  {
    "ms": 33321,
    "kind": "CHECK",
    "id": "A32.afterThrow",
    "pass": true,
    "detail": "play works after hook exception"
  },
  {
    "ms": 33473,
    "kind": "CHECK",
    "id": "A32.seekVeto",
    "pass": true,
    "detail": "seek cancelled"
  },
  {
    "ms": 33555,
    "kind": "CHECK",
    "id": "A32.onErrorIsolation",
    "pass": true,
    "detail": "firstHook=1 secondHook=1"
  },
  {
    "ms": 33753,
    "kind": "CHECK",
    "id": "N8.disposed",
    "pass": true,
    "detail": "disposed=false"
  },
  {
    "ms": 33753,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-hooks-swap 自动检查点

- 命令 `new {'case': 'hooks', 'swap': 'true'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-hooks-swap.json` 及同前缀文件。
```json
[
  {
    "ms": 37148,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hooks",
      "swap": "true"
    }
  },
  {
    "ms": 37208,
    "kind": "CHECK",
    "id": "N8.reject",
    "pass": true,
    "detail": "beforeOpen=false"
  },
  {
    "ms": 37270,
    "kind": "CHECK",
    "id": "N8.accept",
    "pass": true,
    "detail": "accepted=true"
  },
  {
    "ms": 37665,
    "kind": "CHECK",
    "id": "N22.stalePlay",
    "pass": true,
    "detail": "{playing: false, intent: false, buffering: false, duration: 40000, position: 23, size: 0x0, volume: 30.0, brightness: 1.0, rate: 1.0, fit: contain, zoom: 1.0, locked: false, fullscreen: false, orientation: auto, pip: false, mini: false, rendered: true, epoch: 0, sourceIndex: 0, standby: off, type: vod, title: Coverage vod.mp4, pipSupported: true, controls: true, hud: none, hudText: null, dragging: false, previewAt: null}"
  },
  {
    "ms": 38895,
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
    "standby": "off",
    "type": "vod",
    "title": "Coverage ad.mp4",
    "pipSupported": true,
    "controls": true,
    "hud": "none",
    "hudText": null,
    "dragging": false,
    "previewAt": null
  },
  {
    "ms": 38896,
    "kind": "HOOK_PLAYLIST",
    "index": 0
  },
  {
    "ms": 38896,
    "kind": "CHECK",
    "id": "N8.playlistRejected",
    "pass": true,
    "detail": "rejected jumpTo(1), index=0"
  },
  {
    "ms": 39057,
    "kind": "CHECK",
    "id": "N8.superseded",
    "pass": true,
    "detail": "first=false second=true"
  },
  {
    "ms": 39058,
    "kind": "HOOK_EXPECTED_THROW",
    "error": "Bad state: coverage hook failure"
  },
  {
    "ms": 39059,
    "kind": "CHECK",
    "id": "A32.afterThrow",
    "pass": true,
    "detail": "play works after hook exception"
  },
  {
    "ms": 39214,
    "kind": "CHECK",
    "id": "A32.seekVeto",
    "pass": true,
    "detail": "seek cancelled"
  },
  {
    "ms": 39296,
    "kind": "CHECK",
    "id": "A32.onErrorIsolation",
    "pass": true,
    "detail": "firstHook=1 secondHook=1"
  },
  {
    "ms": 39487,
    "kind": "CHECK",
    "id": "N8.disposed",
    "pass": true,
    "detail": "disposed=false"
  },
  {
    "ms": 39487,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-recovery-liveDefault 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'liveDefault'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-recovery-liveDefault.json` 及同前缀文件。
```json
[
  {
    "ms": 42650,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "liveDefault"
    }
  },
  {
    "ms": 42789,
    "kind": "RECOVERY_OPEN",
    "mode": "liveDefault",
    "accepted": true
  },
  {
    "ms": 42801,
    "kind": "nativeEndError",
    "mode": "liveDefault",
    "since": 150,
    "attempt": 1,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 43909,
    "kind": "nativeEndError",
    "mode": "liveDefault",
    "since": 1258,
    "attempt": 2,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 45995,
    "kind": "nativeEndError",
    "mode": "liveDefault",
    "since": 3344,
    "attempt": 3,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 46033,
    "kind": "CHECK",
    "id": "N3.defaultLive",
    "pass": true,
    "detail": "third failure still retries"
  },
  {
    "ms": 46034,
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
      "standby": "off",
      "type": "live",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "Failed to open http://127.0.0.1:18080/not-found.mp4?t=1793068198552452."
  },
  {
    "ms": 46090,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-recovery-liveLegacy 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'liveLegacy'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-recovery-liveLegacy.json` 及同前缀文件。
```json
[
  {
    "ms": 49224,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "liveLegacy"
    }
  },
  {
    "ms": 49312,
    "kind": "RECOVERY_OPEN",
    "mode": "liveLegacy",
    "accepted": true
  },
  {
    "ms": 49327,
    "kind": "nativeEndError",
    "mode": "liveLegacy",
    "since": 103,
    "attempt": 1,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 50438,
    "kind": "nativeEndError",
    "mode": "liveLegacy",
    "since": 1214,
    "attempt": 2,
    "live": true,
    "action": "giveUp"
  },
  {
    "ms": 50455,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/not-found.mp4?t=1793068205113607) buffering=false"
  },
  {
    "ms": 50455,
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
      "standby": "off",
      "type": "live",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/not-found.mp4?t=1793068205113607)"
  },
  {
    "ms": 50463,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-recovery-liveAlternatives 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'liveAlternatives'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-recovery-liveAlternatives.json` 及同前缀文件。
```json
[
  {
    "ms": 53791,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "liveAlternatives"
    }
  },
  {
    "ms": 53900,
    "kind": "RECOVERY_OPEN",
    "mode": "liveAlternatives",
    "accepted": true
  },
  {
    "ms": 53912,
    "kind": "nativeEndError",
    "mode": "liveAlternatives",
    "since": 121,
    "attempt": 1,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 53987,
    "kind": "nativeEndError",
    "mode": "liveAlternatives",
    "since": 196,
    "attempt": 2,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 54097,
    "kind": "nativeEndError",
    "mode": "liveAlternatives",
    "since": 306,
    "attempt": 3,
    "live": true,
    "action": "failover"
  },
  {
    "ms": 54120,
    "kind": "nativeEndError",
    "mode": "liveAlternatives",
    "since": 329,
    "attempt": 1,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 54201,
    "kind": "nativeEndError",
    "mode": "liveAlternatives",
    "since": 410,
    "attempt": 2,
    "live": true,
    "action": "retry"
  },
  {
    "ms": 54309,
    "kind": "nativeEndError",
    "mode": "liveAlternatives",
    "since": 518,
    "attempt": 3,
    "live": true,
    "action": "giveUp"
  },
  {
    "ms": 54321,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/other404.mp4?t=1793068209673598) buffering=false"
  },
  {
    "ms": 54321,
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
      "standby": "off",
      "type": "live",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/other404.mp4?t=1793068209673598)"
  },
  {
    "ms": 54329,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-hang-default-0 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'hangDefault'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-hang-default-0.json` 及同前缀文件。
```json
[
  {
    "ms": 57202,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "hangDefault"
    }
  },
  {
    "ms": 57321,
    "kind": "RECOVERY_OPEN",
    "mode": "hangDefault",
    "accepted": true
  },
  {
    "ms": 62484,
    "kind": "nativeEndError",
    "mode": "hangDefault",
    "since": 5282,
    "attempt": 1,
    "live": false,
    "action": "giveUp"
  },
  {
    "ms": 62520,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793068213095145) buffering=false"
  },
  {
    "ms": 62520,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793068213095145)"
  },
  {
    "ms": 62536,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-hang-2s-0 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'hang'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-hang-2s-0.json` 及同前缀文件。
```json
[
  {
    "ms": 65770,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "hang"
    }
  },
  {
    "ms": 65883,
    "kind": "RECOVERY_OPEN",
    "mode": "hang",
    "accepted": true
  },
  {
    "ms": 68017,
    "kind": "nativeEndError",
    "mode": "hang",
    "since": 2247,
    "attempt": 1,
    "live": false,
    "action": "giveUp"
  },
  {
    "ms": 68046,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793068221654008) buffering=false"
  },
  {
    "ms": 68047,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793068221654008)"
  },
  {
    "ms": 68072,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-hang-default-1 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'hangDefault'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-hang-default-1.json` 及同前缀文件。
```json
[
  {
    "ms": 70814,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "hangDefault"
    }
  },
  {
    "ms": 70937,
    "kind": "RECOVERY_OPEN",
    "mode": "hangDefault",
    "accepted": true
  },
  {
    "ms": 76088,
    "kind": "nativeEndError",
    "mode": "hangDefault",
    "since": 5274,
    "attempt": 1,
    "live": false,
    "action": "giveUp"
  },
  {
    "ms": 76107,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793068226704505) buffering=false"
  },
  {
    "ms": 76108,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793068226704505)"
  },
  {
    "ms": 76126,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-hang-2s-1 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'hang'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-hang-2s-1.json` 及同前缀文件。
```json
[
  {
    "ms": 79385,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "hang"
    }
  },
  {
    "ms": 79502,
    "kind": "RECOVERY_OPEN",
    "mode": "hang",
    "accepted": true
  },
  {
    "ms": 81640,
    "kind": "nativeEndError",
    "mode": "hang",
    "since": 2254,
    "attempt": 1,
    "live": false,
    "action": "giveUp"
  },
  {
    "ms": 81647,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793068235273263) buffering=false"
  },
  {
    "ms": 81648,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793068235273263)"
  },
  {
    "ms": 81665,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-hang-default-2 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'hangDefault'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-hang-default-2.json` 及同前缀文件。
```json
[
  {
    "ms": 84448,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "hangDefault"
    }
  },
  {
    "ms": 84560,
    "kind": "RECOVERY_OPEN",
    "mode": "hangDefault",
    "accepted": true
  },
  {
    "ms": 89705,
    "kind": "nativeEndError",
    "mode": "hangDefault",
    "since": 5256,
    "attempt": 1,
    "live": false,
    "action": "giveUp"
  },
  {
    "ms": 89739,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793068240342856) buffering=false"
  },
  {
    "ms": 89740,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793068240342856)"
  },
  {
    "ms": 89758,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-hang-2s-2 自动检查点

- 命令 `new {'case': 'recovery', 'mode': 'hang'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-hang-2s-2.json` 及同前缀文件。
```json
[
  {
    "ms": 92951,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "recovery",
      "mode": "hang"
    }
  },
  {
    "ms": 93065,
    "kind": "RECOVERY_OPEN",
    "mode": "hang",
    "accepted": true
  },
  {
    "ms": 95201,
    "kind": "nativeEndError",
    "mode": "hang",
    "since": 2250,
    "attempt": 1,
    "live": false,
    "action": "giveUp"
  },
  {
    "ms": 95205,
    "kind": "CHECK",
    "id": "N6.giveup",
    "pass": true,
    "detail": "error=MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793068248834004) buffering=false"
  },
  {
    "ms": 95206,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "error": "MovaGiveUpError(nativeEndError, http://127.0.0.1:18080/hang?t=1793068248834004)"
  },
  {
    "ms": 95225,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-watchoff 自动检查点

- 命令 `new {'case': 'watchoff'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-watchoff.json` 及同前缀文件。
```json
[
  {
    "ms": 97977,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "watchoff"
    }
  },
  {
    "ms": 105995,
    "kind": "CHECK",
    "id": "N2.watchoff",
    "pass": true,
    "detail": "rendered=true buffering=true failures=0"
  },
  {
    "ms": 106024,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-stt 自动检查点

- 命令 `new {'case': 'stt'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-stt.json` 及同前缀文件。
```json
[
  {
    "ms": 108931,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "stt"
    }
  },
  {
    "ms": 109038,
    "kind": "STT_NO_ENGINE",
    "running": false,
    "languages": []
  },
  {
    "ms": 109078,
    "kind": "STT_EXPECTED_THROW",
    "error": "Bad state: coverage missing model",
    "running": false
  },
  {
    "ms": 109078,
    "kind": "CHECK",
    "id": "N22.sttRollback",
    "pass": true,
    "detail": "after first failure running=false"
  },
  {
    "ms": 109078,
    "kind": "CHECK",
    "id": "N22.sttRetry",
    "pass": true,
    "detail": "calls=2 running=true"
  },
  {
    "ms": 109081,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-live-step0-0 自动检查点

- 命令 `new {'case': 'live', 'step': '0'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-live-step0-0.json` 及同前缀文件。
```json
[
  {
    "ms": 112403,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "live",
      "step": "0"
    }
  },
  {
    "ms": 114360,
    "kind": "CHECK",
    "id": "A7.live",
    "pass": true,
    "detail": "seek events before=7 after=7"
  },
  {
    "ms": 125431,
    "kind": "LIVE_DURATION",
    "step": 0,
    "samples": [
      {
        "ms": 112511,
        "duration": 0
      },
      {
        "ms": 114348,
        "duration": 859
      },
      {
        "ms": 114404,
        "duration": 1741
      },
      {
        "ms": 114447,
        "duration": 1764
      },
      {
        "ms": 114596,
        "duration": 1927
      },
      {
        "ms": 114847,
        "duration": 2182
      },
      {
        "ms": 115098,
        "duration": 2461
      },
      {
        "ms": 115347,
        "duration": 2693
      },
      {
        "ms": 115356,
        "duration": 2740
      },
      {
        "ms": 115398,
        "duration": 2763
      },
      {
        "ms": 115598,
        "duration": 2972
      },
      {
        "ms": 115849,
        "duration": 3251
      },
      {
        "ms": 116099,
        "duration": 3483
      },
      {
        "ms": 116350,
        "duration": 3738
      },
      {
        "ms": 116362,
        "duration": 3761
      },
      {
        "ms": 116400,
        "duration": 3808
      },
      {
        "ms": 116601,
        "duration": 4017
      },
      {
        "ms": 116851,
        "duration": 4295
      },
      {
        "ms": 117101,
        "duration": 4574
      },
      {
        "ms": 117354,
        "duration": 4806
      },
      {
        "ms": 117631,
        "duration": 5085
      },
      {
        "ms": 117654,
        "duration": 5131
      },
      {
        "ms": 117855,
        "duration": 5340
      },
      {
        "ms": 118111,
        "duration": 5619
      },
      {
        "ms": 118357,
        "duration": 5851
      },
      {
        "ms": 118406,
        "duration": 5921
      },
      {
        "ms": 118616,
        "duration": 6130
      },
      {
        "ms": 118864,
        "duration": 6408
      },
      {
        "ms": 118913,
        "duration": 6455
      },
      {
        "ms": 119114,
        "duration": 6641
      },
      {
        "ms": 119158,
        "duration": 6687
      },
      {
        "ms": 119372,
        "duration": 6919
      },
      {
        "ms": 119410,
        "duration": 6966
      },
      {
        "ms": 119612,
        "duration": 7175
      },
      {
        "ms": 119658,
        "duration": 7221
      },
      {
        "ms": 119864,
        "duration": 7407
      },
      {
        "ms": 119866,
        "duration": 7453
      },
      {
        "ms": 119951,
        "duration": 7523
      },
      {
        "ms": 120111,
        "duration": 7686
      },
      {
        "ms": 120121,
        "duration": 7732
      },
      {
        "ms": 120157,
        "duration": 7778
      },
      {
        "ms": 120365,
        "duration": 7964
      },
      {
        "ms": 120408,
        "duration": 8011
      },
      {
        "ms": 120615,
        "duration": 8243
      },
      {
        "ms": 120659,
        "duration": 8289
      },
      {
        "ms": 120862,
        "duration": 8498
      },
      {
        "ms": 120907,
        "duration": 8522
      },
      {
        "ms": 121117,
        "duration": 8730
      },
      {
        "ms": 121127,
        "duration": 8777
      },
      {
        "ms": 121157,
        "duration": 8800
      },
      {
        "ms": 121362,
        "duration": 9009
      },
      {
        "ms": 121377,
        "duration": 9056
      },
      {
        "ms": 121607,
        "duration": 9288
      },
      {
        "ms": 121656,
        "duration": 9334
      },
      {
        "ms": 121862,
        "duration": 9520
      },
      {
        "ms": 121878,
        "duration": 9566
      },
      {
        "ms": 121908,
        "duration": 9613
      },
      {
        "ms": 122111,
        "duration": 9822
      },
      {
        "ms": 122157,
        "duration": 9891
      },
      {
        "ms": 122362,
        "duration": 10100
      },
      {
        "ms": 122409,
        "duration": 10124
      },
      {
        "ms": 122612,
        "duration": 10333
      },
      {
        "ms": 122629,
        "duration": 10379
      },
      {
        "ms": 122873,
        "duration": 10611
      },
      {
        "ms": 122914,
        "duration": 10658
      },
      {
        "ms": 123112,
        "duration": 10843
      },
      {
        "ms": 123158,
        "duration": 10890
      },
      {
        "ms": 123361,
        "duration": 11099
      },
      {
        "ms": 123451,
        "duration": 11122
      },
      {
        "ms": 123621,
        "duration": 11331
      },
      {
        "ms": 123631,
        "duration": 11378
      },
      {
        "ms": 123862,
        "duration": 11563
      },
      {
        "ms": 123882,
        "duration": 11610
      },
      {
        "ms": 123910,
        "duration": 11656
      },
      {
        "ms": 124112,
        "duration": 11819
      },
      {
        "ms": 124133,
        "duration": 11842
      },
      {
        "ms": 124156,
        "duration": 11888
      },
      {
        "ms": 124362,
        "duration": 12097
      },
      {
        "ms": 124408,
        "duration": 12121
      },
      {
        "ms": 124613,
        "duration": 12330
      },
      {
        "ms": 124635,
        "duration": 12376
      },
      {
        "ms": 124870,
        "duration": 12608
      },
      {
        "ms": 125163,
        "duration": 12887
      },
      {
        "ms": 125360,
        "duration": 13096
      },
      {
        "ms": 125372,
        "duration": 0
      }
    ]
  },
  {
    "ms": 125440,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-live-step2000-0 自动检查点

- 命令 `new {'case': 'live', 'step': '2000'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-live-step2000-0.json` 及同前缀文件。
```json
[
  {
    "ms": 128511,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "live",
      "step": "2000"
    }
  },
  {
    "ms": 130396,
    "kind": "CHECK",
    "id": "A7.live",
    "pass": true,
    "detail": "seek events before=7 after=7"
  },
  {
    "ms": 141483,
    "kind": "LIVE_DURATION",
    "step": 2000,
    "samples": [
      {
        "ms": 128601,
        "duration": 0
      },
      {
        "ms": 130395,
        "duration": 1648
      },
      {
        "ms": 132360,
        "duration": 3761
      },
      {
        "ms": 134364,
        "duration": 5851
      },
      {
        "ms": 136366,
        "duration": 7941
      },
      {
        "ms": 138360,
        "duration": 10054
      },
      {
        "ms": 140388,
        "duration": 12097
      },
      {
        "ms": 141460,
        "duration": 0
      }
    ]
  },
  {
    "ms": 141489,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-live-step0-1 自动检查点

- 命令 `new {'case': 'live', 'step': '0'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-live-step0-1.json` 及同前缀文件。
```json
[
  {
    "ms": 144877,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "live",
      "step": "0"
    }
  },
  {
    "ms": 146840,
    "kind": "CHECK",
    "id": "A7.live",
    "pass": true,
    "detail": "seek events before=7 after=7"
  },
  {
    "ms": 157914,
    "kind": "LIVE_DURATION",
    "step": 0,
    "samples": [
      {
        "ms": 144987,
        "duration": 0
      },
      {
        "ms": 146878,
        "duration": 1068
      },
      {
        "ms": 146882,
        "duration": 1695
      },
      {
        "ms": 146923,
        "duration": 1741
      },
      {
        "ms": 147070,
        "duration": 1881
      },
      {
        "ms": 147091,
        "duration": 1927
      },
      {
        "ms": 147320,
        "duration": 2159
      },
      {
        "ms": 147335,
        "duration": 2182
      },
      {
        "ms": 147372,
        "duration": 2206
      },
      {
        "ms": 147571,
        "duration": 2415
      },
      {
        "ms": 147586,
        "duration": 2461
      },
      {
        "ms": 147824,
        "duration": 2693
      },
      {
        "ms": 148072,
        "duration": 2925
      },
      {
        "ms": 148090,
        "duration": 2972
      },
      {
        "ms": 148122,
        "duration": 3018
      },
      {
        "ms": 148324,
        "duration": 3181
      },
      {
        "ms": 148340,
        "duration": 3204
      },
      {
        "ms": 148373,
        "duration": 3251
      },
      {
        "ms": 148575,
        "duration": 3460
      },
      {
        "ms": 148592,
        "duration": 3483
      },
      {
        "ms": 148624,
        "duration": 3529
      },
      {
        "ms": 148825,
        "duration": 3738
      },
      {
        "ms": 149078,
        "duration": 3994
      },
      {
        "ms": 149091,
        "duration": 4017
      },
      {
        "ms": 149126,
        "duration": 4040
      },
      {
        "ms": 149330,
        "duration": 4249
      },
      {
        "ms": 149345,
        "duration": 4295
      },
      {
        "ms": 149380,
        "duration": 4342
      },
      {
        "ms": 149623,
        "duration": 4528
      },
      {
        "ms": 149828,
        "duration": 4760
      },
      {
        "ms": 149843,
        "duration": 4806
      },
      {
        "ms": 149878,
        "duration": 4853
      },
      {
        "ms": 150092,
        "duration": 5062
      },
      {
        "ms": 150106,
        "duration": 5085
      },
      {
        "ms": 150342,
        "duration": 5340
      },
      {
        "ms": 150388,
        "duration": 5364
      },
      {
        "ms": 150591,
        "duration": 5573
      },
      {
        "ms": 150607,
        "duration": 5619
      },
      {
        "ms": 150839,
        "duration": 5851
      },
      {
        "ms": 150857,
        "duration": 5874
      },
      {
        "ms": 150886,
        "duration": 5898
      },
      {
        "ms": 151093,
        "duration": 6107
      },
      {
        "ms": 151095,
        "duration": 6130
      },
      {
        "ms": 151139,
        "duration": 6176
      },
      {
        "ms": 151366,
        "duration": 6362
      },
      {
        "ms": 151386,
        "duration": 6408
      },
      {
        "ms": 151591,
        "duration": 6641
      },
      {
        "ms": 151637,
        "duration": 6687
      },
      {
        "ms": 151836,
        "duration": 6896
      },
      {
        "ms": 151860,
        "duration": 6919
      },
      {
        "ms": 152092,
        "duration": 7175
      },
      {
        "ms": 152137,
        "duration": 7221
      },
      {
        "ms": 152340,
        "duration": 7407
      },
      {
        "ms": 152361,
        "duration": 7453
      },
      {
        "ms": 152600,
        "duration": 7686
      },
      {
        "ms": 152645,
        "duration": 7732
      },
      {
        "ms": 152839,
        "duration": 7941
      },
      {
        "ms": 152862,
        "duration": 7964
      },
      {
        "ms": 153123,
        "duration": 8220
      },
      {
        "ms": 153140,
        "duration": 8243
      },
      {
        "ms": 153342,
        "duration": 8452
      },
      {
        "ms": 153365,
        "duration": 8498
      },
      {
        "ms": 153595,
        "duration": 8730
      },
      {
        "ms": 153615,
        "duration": 8777
      },
      {
        "ms": 153846,
        "duration": 9009
      },
      {
        "ms": 153888,
        "duration": 9056
      },
      {
        "ms": 154091,
        "duration": 9241
      },
      {
        "ms": 154115,
        "duration": 9288
      },
      {
        "ms": 154346,
        "duration": 9520
      },
      {
        "ms": 154366,
        "duration": 9566
      },
      {
        "ms": 154603,
        "duration": 9799
      },
      {
        "ms": 154616,
        "duration": 9845
      },
      {
        "ms": 154874,
        "duration": 10100
      },
      {
        "ms": 154887,
        "duration": 10124
      },
      {
        "ms": 155092,
        "duration": 10333
      },
      {
        "ms": 155137,
        "duration": 10356
      },
      {
        "ms": 155342,
        "duration": 10565
      },
      {
        "ms": 155368,
        "duration": 10611
      },
      {
        "ms": 155592,
        "duration": 10820
      },
      {
        "ms": 155618,
        "duration": 10843
      },
      {
        "ms": 155638,
        "duration": 10890
      },
      {
        "ms": 155844,
        "duration": 11099
      },
      {
        "ms": 155892,
        "duration": 11122
      },
      {
        "ms": 156093,
        "duration": 11308
      },
      {
        "ms": 156120,
        "duration": 11331
      },
      {
        "ms": 156136,
        "duration": 11378
      },
      {
        "ms": 156341,
        "duration": 11563
      },
      {
        "ms": 156372,
        "duration": 11610
      },
      {
        "ms": 156600,
        "duration": 11819
      },
      {
        "ms": 156607,
        "duration": 11842
      },
      {
        "ms": 156680,
        "duration": 11888
      },
      {
        "ms": 156843,
        "duration": 12051
      },
      {
        "ms": 156877,
        "duration": 12097
      },
      {
        "ms": 156888,
        "duration": 12121
      },
      {
        "ms": 157091,
        "duration": 12330
      },
      {
        "ms": 157136,
        "duration": 12376
      },
      {
        "ms": 157349,
        "duration": 12562
      },
      {
        "ms": 157377,
        "duration": 12608
      },
      {
        "ms": 157592,
        "duration": 12817
      },
      {
        "ms": 157628,
        "duration": 12840
      },
      {
        "ms": 157842,
        "duration": 13073
      },
      {
        "ms": 157892,
        "duration": 0
      }
    ]
  },
  {
    "ms": 157918,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-live-step2000-1 自动检查点

- 命令 `new {'case': 'live', 'step': '2000'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-live-step2000-1.json` 及同前缀文件。
```json
[
  {
    "ms": 161613,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "live",
      "step": "2000"
    }
  },
  {
    "ms": 163619,
    "kind": "CHECK",
    "id": "A7.live",
    "pass": true,
    "detail": "seek events before=7 after=7"
  },
  {
    "ms": 174742,
    "kind": "LIVE_DURATION",
    "step": 2000,
    "samples": [
      {
        "ms": 161716,
        "duration": 0
      },
      {
        "ms": 163616,
        "duration": 603
      },
      {
        "ms": 164654,
        "duration": 2740
      },
      {
        "ms": 166617,
        "duration": 4806
      },
      {
        "ms": 168634,
        "duration": 6919
      },
      {
        "ms": 170637,
        "duration": 9009
      },
      {
        "ms": 172631,
        "duration": 11099
      },
      {
        "ms": 174664,
        "duration": 0
      }
    ]
  },
  {
    "ms": 174757,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-live-step0-2 自动检查点

- 命令 `new {'case': 'live', 'step': '0'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-live-step0-2.json` 及同前缀文件。
```json
[
  {
    "ms": 177938,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "live",
      "step": "0"
    }
  },
  {
    "ms": 179846,
    "kind": "CHECK",
    "id": "A7.live",
    "pass": true,
    "detail": "seek events before=7 after=7"
  },
  {
    "ms": 190916,
    "kind": "LIVE_DURATION",
    "step": 0,
    "samples": [
      {
        "ms": 178058,
        "duration": 0
      },
      {
        "ms": 179891,
        "duration": 1741
      },
      {
        "ms": 179936,
        "duration": 1764
      },
      {
        "ms": 180088,
        "duration": 1927
      },
      {
        "ms": 180382,
        "duration": 2206
      },
      {
        "ms": 180390,
        "duration": 2229
      },
      {
        "ms": 180591,
        "duration": 2461
      },
      {
        "ms": 180604,
        "duration": 2484
      },
      {
        "ms": 180841,
        "duration": 2740
      },
      {
        "ms": 181092,
        "duration": 2972
      },
      {
        "ms": 181342,
        "duration": 3251
      },
      {
        "ms": 181594,
        "duration": 3483
      },
      {
        "ms": 181606,
        "duration": 3529
      },
      {
        "ms": 181644,
        "duration": 3576
      },
      {
        "ms": 181845,
        "duration": 3738
      },
      {
        "ms": 181853,
        "duration": 3761
      },
      {
        "ms": 181894,
        "duration": 3808
      },
      {
        "ms": 182160,
        "duration": 4040
      },
      {
        "ms": 182360,
        "duration": 4342
      },
      {
        "ms": 182605,
        "duration": 4574
      },
      {
        "ms": 182651,
        "duration": 4621
      },
      {
        "ms": 182848,
        "duration": 4806
      },
      {
        "ms": 182864,
        "duration": 4830
      },
      {
        "ms": 182906,
        "duration": 4899
      },
      {
        "ms": 183105,
        "duration": 5085
      },
      {
        "ms": 183152,
        "duration": 5131
      },
      {
        "ms": 183356,
        "duration": 5364
      },
      {
        "ms": 183402,
        "duration": 5410
      },
      {
        "ms": 183606,
        "duration": 5619
      },
      {
        "ms": 183617,
        "duration": 5642
      },
      {
        "ms": 183906,
        "duration": 5921
      },
      {
        "ms": 184120,
        "duration": 6130
      },
      {
        "ms": 184122,
        "duration": 6176
      },
      {
        "ms": 184355,
        "duration": 6408
      },
      {
        "ms": 184403,
        "duration": 6455
      },
      {
        "ms": 184609,
        "duration": 6641
      },
      {
        "ms": 184624,
        "duration": 6664
      },
      {
        "ms": 184651,
        "duration": 6687
      },
      {
        "ms": 184856,
        "duration": 6919
      },
      {
        "ms": 184902,
        "duration": 6966
      },
      {
        "ms": 185128,
        "duration": 7221
      },
      {
        "ms": 185167,
        "duration": 7244
      },
      {
        "ms": 185356,
        "duration": 7453
      },
      {
        "ms": 185403,
        "duration": 7500
      },
      {
        "ms": 185600,
        "duration": 7686
      },
      {
        "ms": 185627,
        "duration": 7732
      },
      {
        "ms": 185649,
        "duration": 7778
      },
      {
        "ms": 185856,
        "duration": 7964
      },
      {
        "ms": 185877,
        "duration": 8011
      },
      {
        "ms": 185904,
        "duration": 8034
      },
      {
        "ms": 186104,
        "duration": 8220
      },
      {
        "ms": 186128,
        "duration": 8243
      },
      {
        "ms": 186150,
        "duration": 8289
      },
      {
        "ms": 186367,
        "duration": 8498
      },
      {
        "ms": 186383,
        "duration": 8522
      },
      {
        "ms": 186412,
        "duration": 8545
      },
      {
        "ms": 186614,
        "duration": 8777
      },
      {
        "ms": 186627,
        "duration": 8800
      },
      {
        "ms": 186859,
        "duration": 9056
      },
      {
        "ms": 186944,
        "duration": 9102
      },
      {
        "ms": 187106,
        "duration": 9288
      },
      {
        "ms": 187129,
        "duration": 9334
      },
      {
        "ms": 187361,
        "duration": 9543
      },
      {
        "ms": 187379,
        "duration": 9566
      },
      {
        "ms": 187401,
        "duration": 9613
      },
      {
        "ms": 187609,
        "duration": 9845
      },
      {
        "ms": 187629,
        "duration": 9891
      },
      {
        "ms": 187856,
        "duration": 10100
      },
      {
        "ms": 187880,
        "duration": 10124
      },
      {
        "ms": 187901,
        "duration": 10170
      },
      {
        "ms": 188144,
        "duration": 10379
      },
      {
        "ms": 188157,
        "duration": 10402
      },
      {
        "ms": 188370,
        "duration": 10611
      },
      {
        "ms": 188405,
        "duration": 10658
      },
      {
        "ms": 188612,
        "duration": 10843
      },
      {
        "ms": 188636,
        "duration": 10867
      },
      {
        "ms": 188652,
        "duration": 10890
      },
      {
        "ms": 188854,
        "duration": 11099
      },
      {
        "ms": 188882,
        "duration": 11122
      },
      {
        "ms": 189105,
        "duration": 11331
      },
      {
        "ms": 189132,
        "duration": 11378
      },
      {
        "ms": 189150,
        "duration": 11401
      },
      {
        "ms": 189366,
        "duration": 11610
      },
      {
        "ms": 189406,
        "duration": 11656
      },
      {
        "ms": 189606,
        "duration": 11842
      },
      {
        "ms": 189652,
        "duration": 11888
      },
      {
        "ms": 189855,
        "duration": 12097
      },
      {
        "ms": 189883,
        "duration": 12121
      },
      {
        "ms": 190125,
        "duration": 12353
      },
      {
        "ms": 190133,
        "duration": 12376
      },
      {
        "ms": 190154,
        "duration": 12422
      },
      {
        "ms": 190356,
        "duration": 12608
      },
      {
        "ms": 190384,
        "duration": 12655
      },
      {
        "ms": 190604,
        "duration": 12840
      },
      {
        "ms": 190635,
        "duration": 12887
      },
      {
        "ms": 190862,
        "duration": 13119
      },
      {
        "ms": 190867,
        "duration": 0
      }
    ]
  },
  {
    "ms": 190927,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-live-step2000-2 自动检查点

- 命令 `new {'case': 'live', 'step': '2000'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-live-step2000-2.json` 及同前缀文件。
```json
[
  {
    "ms": 194618,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "live",
      "step": "2000"
    }
  },
  {
    "ms": 196743,
    "kind": "CHECK",
    "id": "A7.live",
    "pass": true,
    "detail": "seek events before=7 after=7"
  },
  {
    "ms": 207850,
    "kind": "LIVE_DURATION",
    "step": 2000,
    "samples": [
      {
        "ms": 194743,
        "duration": 0
      },
      {
        "ms": 196793,
        "duration": 1486
      },
      {
        "ms": 198506,
        "duration": 3529
      },
      {
        "ms": 200525,
        "duration": 5642
      },
      {
        "ms": 202546,
        "duration": 7778
      },
      {
        "ms": 204526,
        "duration": 9845
      },
      {
        "ms": 206529,
        "duration": 11888
      },
      {
        "ms": 207824,
        "duration": 0
      }
    ]
  },
  {
    "ms": 207856,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-lazy 自动检查点

- 命令 `new {'case': 'lazy'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-lazy.json` 及同前缀文件。
```json
[
  {
    "ms": 211288,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "lazy"
    }
  },
  {
    "ms": 211320,
    "kind": "CHECK",
    "id": "A3.lazyBefore",
    "pass": true,
    "detail": "controllers=0"
  },
  {
    "ms": 211736,
    "kind": "CHECK",
    "id": "A3.lazyOpened",
    "pass": true,
    "detail": "controllers=0 size=0x0"
  },
  {
    "ms": 212552,
    "kind": "CHECK",
    "id": "A3.lazyRead",
    "pass": true,
    "detail": "controllers=1 handle=VideoController size=640x360"
  },
  {
    "ms": 213270,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-lifecycle 自动检查点

- 命令 `new {'case': 'lifecycle'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-lifecycle.json` 及同前缀文件。
```json
[
  {
    "ms": 216710,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "lifecycle"
    }
  },
  {
    "ms": 231280,
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
    "ms": 231280,
    "kind": "CHECK",
    "id": "F1",
    "pass": true,
    "detail": "natural done=1 errors=0"
  },
  {
    "ms": 231598,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-feed 自动检查点

- 命令 `new {'case': 'feed'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-feed.json` 及同前缀文件。
```json
[
  {
    "ms": 234743,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "feed"
    }
  },
  {
    "ms": 236451,
    "kind": "FEED_SAMPLE",
    "index": 20,
    "engines": 3,
    "rss": 184700928
  },
  {
    "ms": 237639,
    "kind": "FEED_SAMPLE",
    "index": 40,
    "engines": 3,
    "rss": 177876992
  },
  {
    "ms": 238110,
    "kind": "FEED_SAMPLE",
    "index": 60,
    "engines": 3,
    "rss": 177082368
  },
  {
    "ms": 238620,
    "kind": "FEED_SAMPLE",
    "index": 80,
    "engines": 3,
    "rss": 175738880
  },
  {
    "ms": 239035,
    "kind": "FEED_SAMPLE",
    "index": 100,
    "engines": 3,
    "rss": 175575040
  },
  {
    "ms": 239056,
    "kind": "CHECK",
    "id": "A29.final",
    "pass": true,
    "detail": "active=120 engines=3"
  },
  {
    "ms": 239057,
    "kind": "FEED_ENGINES",
    "states": [
      {
        "playing": false,
        "intent": false,
        "buffering": true,
        "duration": 0,
        "position": 19960,
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
        "standby": "off",
        "type": "vod",
        "title": "Coverage vod.mp4?feed=99",
        "pipSupported": true,
        "controls": true,
        "hud": "none",
        "hudText": null,
        "dragging": false,
        "previewAt": null
      },
      {
        "playing": true,
        "intent": true,
        "buffering": true,
        "duration": 0,
        "position": 19960,
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
        "standby": "off",
        "type": "vod",
        "title": "Coverage vod.mp4?feed=120",
        "pipSupported": true,
        "controls": true,
        "hud": "none",
        "hudText": null,
        "dragging": false,
        "previewAt": null
      },
      {
        "playing": false,
        "intent": false,
        "buffering": true,
        "duration": 0,
        "position": 19960,
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
        "standby": "off",
        "type": "vod",
        "title": "Coverage vod.mp4?feed=98",
        "pipSupported": true,
        "controls": true,
        "hud": "none",
        "hudText": null,
        "dragging": false,
        "previewAt": null
      }
    ]
  },
  {
    "ms": 239069,
    "kind": "CHECK",
    "id": "A29.dispose",
    "pass": true,
    "detail": "controller and 3 native engines disposed"
  },
  {
    "ms": 239069,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-swap 自动检查点

- 命令 `new {'case': 'swap'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-swap.json` 及同前缀文件。
```json
[
  {
    "ms": 242257,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "swap"
    }
  },
  {
    "ms": 242609,
    "kind": "CHECK",
    "id": "C11.off",
    "pass": true,
    "detail": "engines=1 epoch=0"
  },
  {
    "ms": 243860,
    "kind": "CHECK",
    "id": "A24.commit",
    "pass": true,
    "detail": "epoch=1 rate=1.5 position=6048"
  },
  {
    "ms": 243861,
    "kind": "CHECK",
    "id": "A24.retired",
    "pass": true,
    "detail": "retired engine rejects open"
  },
  {
    "ms": 243861,
    "kind": "CHECK",
    "id": "A24.short",
    "pass": true,
    "detail": "short warm declined engines=2"
  },
  {
    "ms": 243943,
    "kind": "CHECK",
    "id": "A24.abandon",
    "pass": true,
    "detail": "shadow disposed"
  },
  {
    "ms": 245990,
    "kind": "CHECK",
    "id": "A24.timeout",
    "pass": true,
    "detail": "commit timeout returned=false"
  },
  {
    "ms": 246970,
    "kind": "CHECK",
    "id": "A24.swapTo",
    "pass": true,
    "detail": "epoch=2 rate=1.0"
  },
  {
    "ms": 247000,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-ads 自动检查点

- 命令 `new {'case': 'ads'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-ads.json` 及同前缀文件。
```json
[
  {
    "ms": 249974,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "ads"
    }
  },
  {
    "ms": 249975,
    "kind": "CHECK",
    "id": "C9.waits",
    "pass": true,
    "detail": "pre=false mid=true post=false breakOverride=false"
  },
  {
    "ms": 250019,
    "kind": "pre",
    "type": "started",
    "title": "PRE",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 250119,
    "kind": "pre",
    "type": "clicked",
    "title": "PRE",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 250120,
    "kind": "pre",
    "type": "skipped",
    "title": "PRE",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 251048,
    "kind": "mid",
    "type": "started",
    "title": "MANUAL",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 251082,
    "kind": "mid",
    "type": "skipped",
    "title": "MANUAL",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 253720,
    "kind": "mid",
    "type": "started",
    "title": "MID",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 254844,
    "kind": "mid",
    "type": "completed",
    "title": "MID",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 271573,
    "kind": "post",
    "type": "started",
    "title": "POST",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 272698,
    "kind": "post",
    "type": "completed",
    "title": "POST",
    "error": "null",
    "click": "https://example.invalid/coverage"
  },
  {
    "ms": 272711,
    "kind": "CHECK",
    "id": "A27.rolls",
    "pass": true,
    "detail": "events=[PRE:started, PRE:clicked, PRE:skipped, MANUAL:started, MANUAL:skipped, MID:started, MID:completed, POST:started, POST:completed]"
  },
  {
    "ms": 272729,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-adResume 自动检查点

- 命令 `new {'case': 'adResume'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-adResume.json` 及同前缀文件。
```json
[
  {
    "ms": 276147,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "adResume"
    }
  },
  {
    "ms": 285668,
    "kind": "CHECK",
    "id": "F4.adResume",
    "pass": true,
    "detail": "run=0 target=4760 nativeAfter=4760 error=0 nativeReadLatency=13 epoch=2"
  },
  {
    "ms": 299994,
    "kind": "CHECK",
    "id": "F4.adResume",
    "pass": true,
    "detail": "run=1 target=5520 nativeAfter=5520 error=0 nativeReadLatency=9 epoch=2"
  },
  {
    "ms": 312230,
    "kind": "CHECK",
    "id": "F4.adResume",
    "pass": true,
    "detail": "run=2 target=4760 nativeAfter=4760 error=0 nativeReadLatency=3 epoch=2"
  },
  {
    "ms": 324491,
    "kind": "CHECK",
    "id": "F4.adResume",
    "pass": true,
    "detail": "run=3 target=4880 nativeAfter=4880 error=0 nativeReadLatency=14 epoch=2"
  },
  {
    "ms": 334451,
    "kind": "CHECK",
    "id": "F4.adResume",
    "pass": true,
    "detail": "run=4 target=4880 nativeAfter=4880 error=0 nativeReadLatency=0 epoch=2"
  },
  {
    "ms": 334726,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-dispose120 自动检查点

- 命令 `dispose {}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-dispose120.json` 及同前缀文件。
```json
[
  {
    "ms": 337810,
    "kind": "BEGIN",
    "group": "dispose",
    "args": {
      "group": "dispose"
    }
  },
  {
    "ms": 339500,
    "kind": "MEM_SAMPLE",
    "round": 20,
    "rss": 227037184
  },
  {
    "ms": 340982,
    "kind": "MEM_SAMPLE",
    "round": 40,
    "rss": 232460288
  },
  {
    "ms": 342539,
    "kind": "MEM_SAMPLE",
    "round": 60,
    "rss": 241020928
  },
  {
    "ms": 343864,
    "kind": "MEM_SAMPLE",
    "round": 80,
    "rss": 245993472
  },
  {
    "ms": 345263,
    "kind": "MEM_SAMPLE",
    "round": 100,
    "rss": 246718464
  },
  {
    "ms": 346697,
    "kind": "MEM_SAMPLE",
    "round": 120,
    "rss": 247193600
  },
  {
    "ms": 346697,
    "kind": "CHECK",
    "id": "A23.120",
    "pass": true,
    "detail": "120 native create/open/dispose completed"
  },
  {
    "ms": 346697,
    "kind": "END",
    "group": "dispose",
    "status": "done"
  }
]
```

## batch15-preview-vtt 自动检查点

- 命令 `new {'case': 'preview', 'mode': 'vtt'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-preview-vtt.json` 及同前缀文件。
```json
[
  {
    "ms": 349799,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "preview",
      "mode": "vtt"
    }
  },
  {
    "ms": 350248,
    "kind": "THUMB",
    "requested": 4,
    "at": 4000,
    "bytes": 8001,
    "crop": "MovaThumbCrop(0,0,160,90)",
    "peek": false
  },
  {
    "ms": 350389,
    "kind": "THUMB",
    "requested": 8,
    "at": 8000,
    "bytes": 8001,
    "crop": "MovaThumbCrop(0,0,160,90)",
    "peek": false
  },
  {
    "ms": 350518,
    "kind": "THUMB",
    "requested": 12,
    "at": 12000,
    "bytes": 8001,
    "crop": "MovaThumbCrop(0,0,160,90)",
    "peek": false
  },
  {
    "ms": 350645,
    "kind": "THUMB",
    "requested": 4,
    "at": 4000,
    "bytes": 8001,
    "crop": "MovaThumbCrop(0,0,160,90)",
    "peek": false
  },
  {
    "ms": 350647,
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
    "ms": 350647,
    "kind": "CHECK",
    "id": "N22.crop",
    "pass": true,
    "detail": "cropped VTT writes=0"
  },
  {
    "ms": 350679,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-preview-extract 自动检查点

- 命令 `new {'case': 'preview', 'mode': 'extract'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-preview-extract.json` 及同前缀文件。
```json
[
  {
    "ms": 355678,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "preview",
      "mode": "extract"
    }
  },
  {
    "ms": 356930,
    "kind": "THUMB",
    "requested": 4,
    "at": 4000,
    "bytes": 99796,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 357792,
    "kind": "THUMB",
    "requested": 8,
    "at": 8000,
    "bytes": 98103,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 358726,
    "kind": "THUMB",
    "requested": 12,
    "at": 12000,
    "bytes": 95382,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 358903,
    "kind": "THUMB",
    "requested": 4,
    "at": 4000,
    "bytes": 99796,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 358908,
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
    "ms": 358908,
    "kind": "CHECK",
    "id": "A30.diskHit",
    "pass": true,
    "detail": "extractCalls=3 diskHits=1"
  },
  {
    "ms": 359120,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-preview-fallback 自动检查点

- 命令 `new {'case': 'preview', 'mode': 'fallback'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-preview-fallback.json` 及同前缀文件。
```json
[
  {
    "ms": 362630,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "preview",
      "mode": "fallback"
    }
  },
  {
    "ms": 363924,
    "kind": "THUMB",
    "requested": 4,
    "at": 4000,
    "bytes": 99796,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 364702,
    "kind": "THUMB",
    "requested": 8,
    "at": 8000,
    "bytes": 98103,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 365624,
    "kind": "THUMB",
    "requested": 12,
    "at": 12000,
    "bytes": 95382,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 365794,
    "kind": "THUMB",
    "requested": 4,
    "at": 4000,
    "bytes": 99796,
    "crop": "null",
    "peek": true
  },
  {
    "ms": 365803,
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
    "ms": 365804,
    "kind": "CHECK",
    "id": "A30.diskHit",
    "pass": true,
    "detail": "extractCalls=3 diskHits=1"
  },
  {
    "ms": 366079,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-preview-blocked 自动检查点

- 命令 `new {'case': 'preview', 'mode': 'blocked'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-preview-blocked.json` 及同前缀文件。
```json
[
  {
    "ms": 370361,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "preview",
      "mode": "blocked"
    }
  },
  {
    "ms": 372528,
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
    "ms": 372591,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-qoe-ended 自动检查点

- 命令 `new {'case': 'qoe', 'mode': 'ended'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-qoe-ended.json` 及同前缀文件。
```json
[
  {
    "ms": 382358,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "qoe",
      "mode": "ended"
    }
  },
  {
    "ms": 382482,
    "kind": "REPORT",
    "name": "sessionStart",
    "params": {
      "uri": "http://127.0.0.1:18080/ad.mp4?t=1793068538251025",
      "streamType": "vod",
      "audioOnly": true,
      "swapEnabled": false,
      "title": "Coverage ad.mp4"
    }
  },
  {
    "ms": 382484,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 382512,
    "kind": "REPORT",
    "name": "play",
    "params": {}
  },
  {
    "ms": 382513,
    "kind": "REPORT",
    "name": "sourceChange",
    "params": {
      "uri": "http://127.0.0.1:18080/ad.mp4?t=1793068538251025"
    }
  },
  {
    "ms": 382682,
    "kind": "REPORT",
    "name": "firstFrame",
    "params": {
      "ttffMs": 235,
      "audioOnly": true,
      "streamType": "vod",
      "signal": "restart"
    }
  },
  {
    "ms": 402158,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 402158,
    "kind": "REPORT",
    "name": "done",
    "params": {}
  },
  {
    "ms": 402189,
    "kind": "REPORT",
    "name": "sessionEnd",
    "params": {
      "reason": "ended",
      "watchedMs": 19475,
      "stallCount": 0,
      "stallMs": 0,
      "rebufferRate": 0.0,
      "completionPercent": 96.97
    }
  },
  {
    "ms": 402531,
    "kind": "QOE_END",
    "mode": "ended",
    "reports": 8
  },
  {
    "ms": 402532,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-qoe-stopped 自动检查点

- 命令 `new {'case': 'qoe', 'mode': 'stopped'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-qoe-stopped.json` 及同前缀文件。
```json
[
  {
    "ms": 408622,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "qoe",
      "mode": "stopped"
    }
  },
  {
    "ms": 408762,
    "kind": "REPORT",
    "name": "sessionStart",
    "params": {
      "uri": "http://127.0.0.1:18080/ad.mp4?t=1793068564514305",
      "streamType": "vod",
      "audioOnly": true,
      "swapEnabled": false,
      "title": "Coverage ad.mp4"
    }
  },
  {
    "ms": 408764,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 408788,
    "kind": "REPORT",
    "name": "play",
    "params": {}
  },
  {
    "ms": 408788,
    "kind": "REPORT",
    "name": "sourceChange",
    "params": {
      "uri": "http://127.0.0.1:18080/ad.mp4?t=1793068564514305"
    }
  },
  {
    "ms": 408936,
    "kind": "REPORT",
    "name": "firstFrame",
    "params": {
      "ttffMs": 217,
      "audioOnly": true,
      "streamType": "vod",
      "signal": "restart"
    }
  },
  {
    "ms": 413158,
    "kind": "REPORT",
    "name": "sessionEnd",
    "params": {
      "reason": "stopped",
      "watchedMs": 4222,
      "stallCount": 0,
      "stallMs": 0,
      "rebufferRate": 0.0,
      "completionPercent": 20.724999999999998
    }
  },
  {
    "ms": 413485,
    "kind": "QOE_END",
    "mode": "stopped",
    "reports": 6
  },
  {
    "ms": 413486,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-qoe-failed 自动检查点

- 命令 `new {'case': 'qoe', 'mode': 'failed'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-qoe-failed.json` 及同前缀文件。
```json
[
  {
    "ms": 418901,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "qoe",
      "mode": "failed"
    }
  },
  {
    "ms": 419019,
    "kind": "REPORT",
    "name": "sessionStart",
    "params": {
      "uri": "http://127.0.0.1:18080/404.mp4?t=1793068574791895",
      "streamType": "vod",
      "audioOnly": true,
      "swapEnabled": false,
      "title": "Coverage 404.mp4"
    }
  },
  {
    "ms": 419026,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 419051,
    "kind": "REPORT",
    "name": "play",
    "params": {}
  },
  {
    "ms": 419052,
    "kind": "REPORT",
    "name": "sourceChange",
    "params": {
      "uri": "http://127.0.0.1:18080/404.mp4?t=1793068574791895"
    }
  },
  {
    "ms": 419068,
    "kind": "REPORT",
    "name": "error",
    "params": {
      "error": "Failed to open http://127.0.0.1:18080/404.mp4?t=1793068574791895.",
      "fatal": true,
      "code": "stream"
    }
  },
  {
    "ms": 439084,
    "kind": "SCRIPT_ERROR",
    "group": "new",
    "error": "TimeoutException: condition",
    "stack": "#0      until (package:mova_example/main_coverage_api.dart:54)\n<asynchronous suspension>\n#1      qoe (package:mova_example/verify_auto/coverage_new.dart:365)\n<asynchronous suspension>\n#2      runNew (package:mova_example/verify_auto/coverage_new.dart:23)\n<asynchronous suspension>\n#3      _CoverageHomeState.run (package:mova_example/main_coverage_api.dart:173)\n<asynchronous suspension>\n"
  },
  {
    "ms": 439085,
    "kind": "END",
    "group": "new",
    "status": "error"
  }
]
```

## batch15-qoe-abandoned 自动检查点

- 命令 `new {'case': 'qoe', 'mode': 'abandoned'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-qoe-abandoned.json` 及同前缀文件。
```json
[
  {
    "ms": 443151,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "qoe",
      "mode": "abandoned"
    }
  },
  {
    "ms": 443218,
    "kind": "REPORT",
    "name": "startupFail",
    "params": {
      "reason": "abandoned",
      "waitedMs": 1
    }
  },
  {
    "ms": 443218,
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
    "ms": 443250,
    "kind": "REPORT",
    "name": "sessionStart",
    "params": {
      "uri": "http://127.0.0.1:18080/hang?t=1793068599027473",
      "streamType": "vod",
      "audioOnly": true,
      "swapEnabled": false,
      "title": "Coverage hang"
    }
  },
  {
    "ms": 443577,
    "kind": "QOE_END",
    "mode": "abandoned",
    "reports": 3
  },
  {
    "ms": 443577,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-qoe-stall 自动检查点

- 命令 `new {'case': 'qoe', 'mode': 'stall'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-qoe-stall.json` 及同前缀文件。
```json
[
  {
    "ms": 449358,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "qoe",
      "mode": "stall"
    }
  },
  {
    "ms": 449490,
    "kind": "REPORT",
    "name": "sessionStart",
    "params": {
      "uri": "http://127.0.0.1:18080/stall.mp4?t=1793068605250498",
      "streamType": "vod",
      "audioOnly": true,
      "swapEnabled": false,
      "title": "Coverage stall.mp4"
    }
  },
  {
    "ms": 449491,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 449516,
    "kind": "REPORT",
    "name": "play",
    "params": {}
  },
  {
    "ms": 449516,
    "kind": "REPORT",
    "name": "sourceChange",
    "params": {
      "uri": "http://127.0.0.1:18080/stall.mp4?t=1793068605250498"
    }
  },
  {
    "ms": 449641,
    "kind": "REPORT",
    "name": "firstFrame",
    "params": {
      "ttffMs": 192,
      "audioOnly": true,
      "streamType": "vod",
      "signal": "restart"
    }
  },
  {
    "ms": 474542,
    "kind": "REPORT",
    "name": "sessionEnd",
    "params": {
      "reason": "stopped",
      "watchedMs": 2721,
      "stallCount": 0,
      "stallMs": 22179,
      "rebufferRate": 0.890722891566265,
      "completionPercent": 7.545
    }
  },
  {
    "ms": 474903,
    "kind": "QOE_END",
    "mode": "stall",
    "reports": 6
  },
  {
    "ms": 474904,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-qoe-truncated 自动检查点

- 命令 `new {'case': 'qoe', 'mode': 'truncated'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-qoe-truncated.json` 及同前缀文件。
```json
[
  {
    "ms": 480754,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "qoe",
      "mode": "truncated"
    }
  },
  {
    "ms": 480889,
    "kind": "REPORT",
    "name": "sessionStart",
    "params": {
      "uri": "http://127.0.0.1:18084/truncated.mp4?t=1793068636650541",
      "streamType": "vod",
      "audioOnly": true,
      "swapEnabled": false
    }
  },
  {
    "ms": 480896,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 480920,
    "kind": "REPORT",
    "name": "play",
    "params": {}
  },
  {
    "ms": 480920,
    "kind": "REPORT",
    "name": "sourceChange",
    "params": {
      "uri": "http://127.0.0.1:18084/truncated.mp4?t=1793068636650541"
    }
  },
  {
    "ms": 481309,
    "kind": "REPORT",
    "name": "firstFrame",
    "params": {
      "ttffMs": 460,
      "audioOnly": true,
      "streamType": "vod",
      "signal": "restart"
    }
  },
  {
    "ms": 500032,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 500033,
    "kind": "REPORT",
    "name": "done",
    "params": {}
  },
  {
    "ms": 500048,
    "kind": "REPORT",
    "name": "error",
    "params": {
      "error": "truncated: EOF at 18645/40000 ms",
      "fatal": true,
      "code": "truncated"
    }
  },
  {
    "ms": 500048,
    "kind": "REPORT",
    "name": "sessionEnd",
    "params": {
      "reason": "failed",
      "watchedMs": 18722,
      "stallCount": 0,
      "stallMs": 0,
      "rebufferRate": 0.0,
      "completionPercent": 46.612500000000004
    }
  },
  {
    "ms": 500421,
    "kind": "QOE_END",
    "mode": "truncated",
    "reports": 9
  },
  {
    "ms": 500422,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-hls 自动检查点

- 命令 `new {'case': 'hls'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-hls.json` 及同前缀文件。
```json
[
  {
    "ms": 504140,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hls"
    }
  },
  {
    "ms": 514161,
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
    "ms": 549332,
    "kind": "SCRIPT_ERROR",
    "group": "new",
    "error": "TimeoutException: condition",
    "stack": "#0      until (package:mova_example/main_coverage_api.dart:54)\n<asynchronous suspension>\n#1      hls (package:mova_example/verify_auto/coverage_new.dart:393)\n<asynchronous suspension>\n#2      runNew (package:mova_example/verify_auto/coverage_new.dart:24)\n<asynchronous suspension>\n#3      _CoverageHomeState.run (package:mova_example/main_coverage_api.dart:173)\n<asynchronous suspension>\n"
  },
  {
    "ms": 549334,
    "kind": "END",
    "group": "new",
    "status": "error"
  }
]
```

## batch15-abr 自动检查点

- 命令 `new {'case': 'abr'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-abr.json` 及同前缀文件。
```json
[
  {
    "ms": 553093,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "abr"
    }
  },
  {
    "ms": 562612,
    "kind": "ABR_REAL",
    "before": 5023,
    "from": "360p",
    "to": "180p",
    "resets": 3,
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
      "rendered": true,
      "epoch": 0,
      "sourceIndex": 0,
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "ms": 563584,
    "kind": "CHECK",
    "id": "F3.abrBackToBack",
    "pass": true,
    "detail": "beforeStall=5023 afterSwitch=5743"
  },
  {
    "ms": 563878,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch15-tls 自动检查点

- 命令 `new {'case': 'tls'}`；driver exit=0。
- 原始事件/状态/系统证据：`example/tool/coverage_evidence/batch15-tls.json` 及同前缀文件。
```json
[
  {
    "ms": 567375,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "tls"
    }
  },
  {
    "ms": 568271,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=0 verify=false cert=0 rendered=true errors=[]"
  },
  {
    "ms": 568907,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=0 verify=false cert=1 rendered=true errors=[]"
  },
  {
    "ms": 569515,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=0 verify=false cert=2 rendered=true errors=[]"
  },
  {
    "ms": 570061,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=0 verify=false cert=3 rendered=true errors=[]"
  },
  {
    "ms": 570213,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": false,
    "detail": "run=0 verify=true cert=0 rendered=false errors=[Failed to open https://127.0.0.1:18443/low/index.m3u8?t=0.]"
  },
  {
    "ms": 570379,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=0 verify=true cert=1 rendered=false errors=[Failed to open https://127.0.0.1:18444/low/index.m3u8?t=0.]"
  },
  {
    "ms": 570569,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=0 verify=true cert=2 rendered=false errors=[Failed to open https://127.0.0.1:18445/low/index.m3u8?t=0.]"
  },
  {
    "ms": 570827,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=0 verify=true cert=3 rendered=false errors=[Failed to open https://127.0.0.1:18446/low/index.m3u8?t=0.]"
  },
  {
    "ms": 571458,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=1 verify=false cert=0 rendered=true errors=[]"
  },
  {
    "ms": 572092,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=1 verify=false cert=1 rendered=true errors=[]"
  },
  {
    "ms": 572733,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=1 verify=false cert=2 rendered=true errors=[]"
  },
  {
    "ms": 573331,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=1 verify=false cert=3 rendered=true errors=[]"
  },
  {
    "ms": 573520,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": false,
    "detail": "run=1 verify=true cert=0 rendered=false errors=[Failed to open https://127.0.0.1:18443/low/index.m3u8?t=1.]"
  },
  {
    "ms": 573687,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=1 verify=true cert=1 rendered=false errors=[Failed to open https://127.0.0.1:18444/low/index.m3u8?t=1.]"
  },
  {
    "ms": 573948,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=1 verify=true cert=2 rendered=false errors=[Failed to open https://127.0.0.1:18445/low/index.m3u8?t=1.]"
  },
  {
    "ms": 574113,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=1 verify=true cert=3 rendered=false errors=[Failed to open https://127.0.0.1:18446/low/index.m3u8?t=1.]"
  },
  {
    "ms": 574673,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=2 verify=false cert=0 rendered=true errors=[]"
  },
  {
    "ms": 575336,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=2 verify=false cert=1 rendered=true errors=[]"
  },
  {
    "ms": 575934,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=2 verify=false cert=2 rendered=true errors=[]"
  },
  {
    "ms": 576522,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=2 verify=false cert=3 rendered=true errors=[]"
  },
  {
    "ms": 576740,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": false,
    "detail": "run=2 verify=true cert=0 rendered=false errors=[Failed to open https://127.0.0.1:18443/low/index.m3u8?t=2.]"
  },
  {
    "ms": 576956,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=2 verify=true cert=1 rendered=false errors=[Failed to open https://127.0.0.1:18444/low/index.m3u8?t=2.]"
  },
  {
    "ms": 577284,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=2 verify=true cert=2 rendered=false errors=[Failed to open https://127.0.0.1:18445/low/index.m3u8?t=2.]"
  },
  {
    "ms": 577470,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=2 verify=true cert=3 rendered=false errors=[Failed to open https://127.0.0.1:18446/low/index.m3u8?t=2.]"
  },
  {
    "ms": 578088,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=3 verify=false cert=0 rendered=true errors=[]"
  },
  {
    "ms": 578686,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=3 verify=false cert=1 rendered=true errors=[]"
  },
  {
    "ms": 579215,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=3 verify=false cert=2 rendered=true errors=[]"
  },
  {
    "ms": 579781,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=3 verify=false cert=3 rendered=true errors=[]"
  },
  {
    "ms": 579975,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": false,
    "detail": "run=3 verify=true cert=0 rendered=false errors=[Failed to open https://127.0.0.1:18443/low/index.m3u8?t=3.]"
  },
  {
    "ms": 580130,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=3 verify=true cert=1 rendered=false errors=[Failed to open https://127.0.0.1:18444/low/index.m3u8?t=3.]"
  },
  {
    "ms": 580414,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=3 verify=true cert=2 rendered=false errors=[Failed to open https://127.0.0.1:18445/low/index.m3u8?t=3.]"
  },
  {
    "ms": 580577,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=3 verify=true cert=3 rendered=false errors=[Failed to open https://127.0.0.1:18446/low/index.m3u8?t=3.]"
  },
  {
    "ms": 581181,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=4 verify=false cert=0 rendered=true errors=[]"
  },
  {
    "ms": 581800,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=4 verify=false cert=1 rendered=true errors=[]"
  },
  {
    "ms": 582451,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=4 verify=false cert=2 rendered=true errors=[]"
  },
  {
    "ms": 583001,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=4 verify=false cert=3 rendered=true errors=[]"
  },
  {
    "ms": 583176,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": false,
    "detail": "run=4 verify=true cert=0 rendered=false errors=[Failed to open https://127.0.0.1:18443/low/index.m3u8?t=4.]"
  },
  {
    "ms": 583343,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=4 verify=true cert=1 rendered=false errors=[Failed to open https://127.0.0.1:18444/low/index.m3u8?t=4.]"
  },
  {
    "ms": 583585,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=4 verify=true cert=2 rendered=false errors=[Failed to open https://127.0.0.1:18445/low/index.m3u8?t=4.]"
  },
  {
    "ms": 583763,
    "kind": "CHECK",
    "id": "C16.matrix",
    "pass": true,
    "detail": "run=4 verify=true cert=3 rendered=false errors=[Failed to open https://127.0.0.1:18446/low/index.m3u8?t=4.]"
  },
  {
    "ms": 583778,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch16-engine 可视/API阶段检查点

- 逐动作原始状态/事件及截图见同前缀；控件/手势断言：
```json
[
  {
    "id": "batch16-engine.fit.contain",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 12000,
      "position": 0,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-engine.fit.cover",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 12000,
      "position": 0,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-engine.fit.fill",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 12000,
      "position": 0,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-engine.sticky",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 12000,
      "position": 0,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-engine.autohide",
    "pass": false,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 12000,
      "position": 0,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-engine.lock",
    "pass": true,
    "detail": {
      "before": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 12000,
        "position": 0,
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
        "standby": "off",
        "type": "vod",
        "title": null,
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "hudText": null,
        "dragging": false,
        "previewAt": null
      },
      "after": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 12000,
        "position": 0,
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
        "standby": "off",
        "type": "vod",
        "title": null,
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "hudText": null,
        "dragging": false,
        "previewAt": null
      }
    }
  },
  {
    "id": "batch16-engine.doubletap",
    "pass": false,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 12000,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "seek",
      "hudText": "00:10",
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-engine.leftBrightness",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 12000,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "brightness",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-engine.rightVolume",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 12000,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "volume",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-engine.horizontalSeek",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 12000,
      "position": 11966,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "seek",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-engine.longpress",
    "pass": false,
    "detail": {
      "during": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 12000,
        "position": 11966,
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
        "standby": "off",
        "type": "vod",
        "title": null,
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "hudText": null,
        "dragging": false,
        "previewAt": null
      },
      "after": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 12000,
        "position": 11966,
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
        "standby": "off",
        "type": "vod",
        "title": null,
        "pipSupported": true,
        "controls": true,
        "hud": "none",
        "hudText": null,
        "dragging": false,
        "previewAt": null
      }
    }
  },
  {
    "id": "batch16-engine.fullscreen.true",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 12000,
      "position": 11966,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-engine.fullscreen.false",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 12000,
      "position": 11966,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-engine.fitRebuild",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 12000,
      "position": 11966,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  }
]
```

## batch16-swap 可视/API阶段检查点

- 逐动作原始状态/事件及截图见同前缀；控件/手势断言：
```json
[
  {
    "id": "batch16-swap.fit.contain",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 2760,
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-swap.fit.cover",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 2760,
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-swap.fit.fill",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 2760,
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-swap.sticky",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 2760,
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": true,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-swap.autohide",
    "pass": true,
    "detail": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 2760,
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-swap.lock",
    "pass": true,
    "detail": {
      "before": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 2760,
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
        "standby": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "hudText": null,
        "dragging": false,
        "previewAt": null
      },
      "after": {
        "playing": false,
        "intent": false,
        "buffering": false,
        "duration": 40000,
        "position": 2760,
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
        "standby": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "hudText": null,
        "dragging": false,
        "previewAt": null
      }
    }
  },
  {
    "id": "batch16-swap.doubletap",
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "seek",
      "hudText": "00:10",
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-swap.leftBrightness",
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "brightness",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-swap.rightVolume",
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "volume",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-swap.horizontalSeek",
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "seek",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-swap.longpress",
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
        "standby": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
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
        "standby": "off",
        "type": "vod",
        "title": "Coverage vod.mp4",
        "pipSupported": true,
        "controls": false,
        "hud": "none",
        "hudText": null,
        "dragging": false,
        "previewAt": null
      }
    }
  },
  {
    "id": "batch16-swap.fullscreen.true",
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-swap.fullscreen.false",
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  },
  {
    "id": "batch16-swap.fitRebuild",
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
      "standby": "off",
      "type": "vod",
      "title": "Coverage vod.mp4",
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "hudText": null,
      "dragging": false,
      "previewAt": null
    }
  }
]
```

## batch17-qoe-failed 复核

- driver exit=0；证据 `example/tool/coverage_evidence/batch17-qoe-failed.json`。
```json
[
  {
    "ms": 42813,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "qoe",
      "mode": "failed"
    }
  },
  {
    "ms": 42851,
    "kind": "REPORT",
    "name": "sessionStart",
    "params": {
      "uri": "http://127.0.0.1:18080/404.mp4?t=1793069848001639",
      "streamType": "vod",
      "audioOnly": true,
      "swapEnabled": false,
      "title": "Coverage 404.mp4"
    }
  },
  {
    "ms": 42854,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 42878,
    "kind": "REPORT",
    "name": "play",
    "params": {}
  },
  {
    "ms": 42879,
    "kind": "REPORT",
    "name": "sourceChange",
    "params": {
      "uri": "http://127.0.0.1:18080/404.mp4?t=1793069848001639"
    }
  },
  {
    "ms": 42890,
    "kind": "REPORT",
    "name": "error",
    "params": {
      "error": "Failed to open http://127.0.0.1:18080/404.mp4?t=1793069848001639.",
      "fatal": true,
      "code": "stream"
    }
  },
  {
    "ms": 42920,
    "kind": "REPORT",
    "name": "startupFail",
    "params": {
      "reason": "failed",
      "waitedMs": 83
    }
  },
  {
    "ms": 42920,
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
    "ms": 43226,
    "kind": "QOE_END",
    "mode": "failed",
    "reports": 7
  },
  {
    "ms": 43226,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch17-qoe-stall-release 复核

- driver exit=0；证据 `example/tool/coverage_evidence/batch17-qoe-stall-release.json`。
```json
[
  {
    "ms": 48943,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "stallRelease"
    }
  },
  {
    "ms": 49028,
    "kind": "REPORT",
    "name": "sessionStart",
    "params": {
      "uri": "http://127.0.0.1:18080/stall.mp4?t=1793069854151389",
      "streamType": "vod",
      "audioOnly": true,
      "swapEnabled": false,
      "title": "Coverage stall.mp4"
    }
  },
  {
    "ms": 49031,
    "kind": "REPORT",
    "name": "pause",
    "params": {}
  },
  {
    "ms": 49052,
    "kind": "REPORT",
    "name": "play",
    "params": {}
  },
  {
    "ms": 49052,
    "kind": "REPORT",
    "name": "sourceChange",
    "params": {
      "uri": "http://127.0.0.1:18080/stall.mp4?t=1793069854151389"
    }
  },
  {
    "ms": 49187,
    "kind": "REPORT",
    "name": "firstFrame",
    "params": {
      "ttffMs": 197,
      "audioOnly": true,
      "streamType": "vod",
      "signal": "restart"
    }
  },
  {
    "ms": 57378,
    "kind": "REPORT",
    "name": "rebuffer",
    "params": {
      "durationMs": 5468,
      "positionMs": 3018,
      "index": 1,
      "signal": "cache"
    }
  },
  {
    "ms": 57379,
    "kind": "STALL_MEASURE",
    "observedBufferWindow": 5433
  },
  {
    "ms": 57882,
    "kind": "REPORT",
    "name": "sessionEnd",
    "params": {
      "reason": "stopped",
      "watchedMs": 3225,
      "stallCount": 1,
      "stallMs": 5468,
      "rebufferRate": 0.6290118486138272,
      "completionPercent": 8.475000000000001
    }
  },
  {
    "ms": 58203,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch17-hls-playing 复核

- driver exit=0；证据 `example/tool/coverage_evidence/batch17-hls-playing.json`。
```json
[
  {
    "ms": 60987,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hls"
    }
  },
  {
    "ms": 70616,
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
    "ms": 105740,
    "kind": "SCRIPT_ERROR",
    "group": "new",
    "error": "TimeoutException: condition",
    "stack": "#0      until (package:mova_example/main_coverage_api.dart:54)\n<asynchronous suspension>\n#1      hls (package:mova_example/verify_auto/coverage_new.dart:465)\n<asynchronous suspension>\n#2      runNew (package:mova_example/verify_auto/coverage_new.dart:25)\n<asynchronous suspension>\n#3      _CoverageHomeState.run (package:mova_example/main_coverage_api.dart:173)\n<asynchronous suspension>\n"
  },
  {
    "ms": 105741,
    "kind": "END",
    "group": "new",
    "status": "error"
  }
]
```

## batch17-hls-playing-swap 复核

- driver exit=0；证据 `example/tool/coverage_evidence/batch17-hls-playing-swap.json`。
```json
[
  {
    "ms": 109019,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hls",
      "swap": "true"
    }
  },
  {
    "ms": 118667,
    "kind": "HLS_QUALITIES",
    "qualities": []
  },
  {
    "ms": 118668,
    "kind": "SCRIPT_ERROR",
    "group": "new",
    "error": "RangeError (length): Invalid value: Valid value range is empty: 1",
    "stack": "#0      _Array.[] (dart:core-patch/array.dart)\n#1      hls (package:mova_example/verify_auto/coverage_new.dart:464)\n<asynchronous suspension>\n#2      runNew (package:mova_example/verify_auto/coverage_new.dart:25)\n<asynchronous suspension>\n#3      _CoverageHomeState.run (package:mova_example/main_coverage_api.dart:173)\n<asynchronous suspension>\n"
  },
  {
    "ms": 118668,
    "kind": "END",
    "group": "new",
    "status": "error"
  }
]
```

## batch17-hls-paused 复核

- driver exit=0；证据 `example/tool/coverage_evidence/batch17-hls-paused.json`。
```json
[
  {
    "ms": 121764,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hls",
      "paused": "true"
    }
  },
  {
    "ms": 123416,
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
    "ms": 158510,
    "kind": "SCRIPT_ERROR",
    "group": "new",
    "error": "TimeoutException: condition",
    "stack": "#0      until (package:mova_example/main_coverage_api.dart:54)\n<asynchronous suspension>\n#1      hls (package:mova_example/verify_auto/coverage_new.dart:465)\n<asynchronous suspension>\n#2      runNew (package:mova_example/verify_auto/coverage_new.dart:25)\n<asynchronous suspension>\n#3      _CoverageHomeState.run (package:mova_example/main_coverage_api.dart:173)\n<asynchronous suspension>\n"
  },
  {
    "ms": 158511,
    "kind": "END",
    "group": "new",
    "status": "error"
  }
]
```

## batch17-tls-probe 复核

- driver exit=0；证据 `example/tool/coverage_evidence/batch17-tls-probe.json`。
```json
[
  {
    "ms": 161544,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "tlsProbe"
    }
  },
  {
    "ms": 161625,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 161736,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "stream",
    "text": "Failed to open https://127.0.0.1:18443/vod.mp4?t=0."
  },
  {
    "ms": 161740,
    "kind": "TLS_READBACK",
    "endpoint": "127.0.0.1:18443",
    "path": "vod.mp4",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 161741,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": false,
    "detail": "run=0 endpoint=127.0.0.1:18443 path=vod.mp4 errors=[Failed to open https://127.0.0.1:18443/vod.mp4?t=0.]"
  },
  {
    "ms": 161789,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 161909,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "stream",
    "text": "Failed to open https://127.0.0.1:18443/low/index.m3u8?t=0."
  },
  {
    "ms": 161923,
    "kind": "TLS_READBACK",
    "endpoint": "127.0.0.1:18443",
    "path": "low/index.m3u8",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 161924,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": false,
    "detail": "run=0 endpoint=127.0.0.1:18443 path=low/index.m3u8 errors=[Failed to open https://127.0.0.1:18443/low/index.m3u8?t=0.]"
  },
  {
    "ms": 161973,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 162229,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "lavf",
    "text": "Failed to create file cache."
  },
  {
    "ms": 162297,
    "kind": "TLS_READBACK",
    "endpoint": "localhost:18447",
    "path": "vod.mp4",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 162297,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": true,
    "detail": "run=0 endpoint=localhost:18447 path=vod.mp4 errors=[]"
  },
  {
    "ms": 162331,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 162773,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "lavf",
    "text": "Failed to create file cache."
  },
  {
    "ms": 162807,
    "kind": "TLS_READBACK",
    "endpoint": "localhost:18447",
    "path": "low/index.m3u8",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 162807,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": true,
    "detail": "run=0 endpoint=localhost:18447 path=low/index.m3u8 errors=[]"
  },
  {
    "ms": 162883,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 162978,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "stream",
    "text": "Failed to open https://127.0.0.1:18443/vod.mp4?t=1."
  },
  {
    "ms": 162994,
    "kind": "TLS_READBACK",
    "endpoint": "127.0.0.1:18443",
    "path": "vod.mp4",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 162994,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": false,
    "detail": "run=1 endpoint=127.0.0.1:18443 path=vod.mp4 errors=[Failed to open https://127.0.0.1:18443/vod.mp4?t=1.]"
  },
  {
    "ms": 163026,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 163125,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "stream",
    "text": "Failed to open https://127.0.0.1:18443/low/index.m3u8?t=1."
  },
  {
    "ms": 163139,
    "kind": "TLS_READBACK",
    "endpoint": "127.0.0.1:18443",
    "path": "low/index.m3u8",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 163139,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": false,
    "detail": "run=1 endpoint=127.0.0.1:18443 path=low/index.m3u8 errors=[Failed to open https://127.0.0.1:18443/low/index.m3u8?t=1.]"
  },
  {
    "ms": 163208,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 163381,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "lavf",
    "text": "Failed to create file cache."
  },
  {
    "ms": 163431,
    "kind": "TLS_READBACK",
    "endpoint": "localhost:18447",
    "path": "vod.mp4",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 163431,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": true,
    "detail": "run=1 endpoint=localhost:18447 path=vod.mp4 errors=[]"
  },
  {
    "ms": 163459,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 163885,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "lavf",
    "text": "Failed to create file cache."
  },
  {
    "ms": 163935,
    "kind": "TLS_READBACK",
    "endpoint": "localhost:18447",
    "path": "low/index.m3u8",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 163935,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": true,
    "detail": "run=1 endpoint=localhost:18447 path=low/index.m3u8 errors=[]"
  },
  {
    "ms": 164022,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 164151,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "stream",
    "text": "Failed to open https://127.0.0.1:18443/vod.mp4?t=2."
  },
  {
    "ms": 164189,
    "kind": "TLS_READBACK",
    "endpoint": "127.0.0.1:18443",
    "path": "vod.mp4",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 164190,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": false,
    "detail": "run=2 endpoint=127.0.0.1:18443 path=vod.mp4 errors=[Failed to open https://127.0.0.1:18443/vod.mp4?t=2.]"
  },
  {
    "ms": 164253,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 164351,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "stream",
    "text": "Failed to open https://127.0.0.1:18443/low/index.m3u8?t=2."
  },
  {
    "ms": 164362,
    "kind": "TLS_READBACK",
    "endpoint": "127.0.0.1:18443",
    "path": "low/index.m3u8",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 164363,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": false,
    "detail": "run=2 endpoint=127.0.0.1:18443 path=low/index.m3u8 errors=[Failed to open https://127.0.0.1:18443/low/index.m3u8?t=2.]"
  },
  {
    "ms": 164417,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 164565,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "lavf",
    "text": "Failed to create file cache."
  },
  {
    "ms": 164630,
    "kind": "TLS_READBACK",
    "endpoint": "localhost:18447",
    "path": "vod.mp4",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 164630,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": true,
    "detail": "run=2 endpoint=localhost:18447 path=vod.mp4 errors=[]"
  },
  {
    "ms": 164664,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "media_kit",
    "text": "error: property not found _setProperty(osc, 1)"
  },
  {
    "ms": 165169,
    "kind": "TLS_NATIVE_LOG",
    "prefix": "lavf",
    "text": "Failed to create file cache."
  },
  {
    "ms": 165201,
    "kind": "TLS_READBACK",
    "endpoint": "localhost:18447",
    "path": "low/index.m3u8",
    "verify": "yes",
    "ca": "/data/user/0/com.icodejoo.mova.mova_example.coverage/code_cache/coverage-ca-probe.pem",
    "caBytes": 1150
  },
  {
    "ms": 165201,
    "kind": "CHECK",
    "id": "C16.probe",
    "pass": true,
    "detail": "run=2 endpoint=localhost:18447 path=low/index.m3u8 errors=[]"
  },
  {
    "ms": 165269,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 批次17：已完成证据回填（其余UI/TLS/HLS继续复核）

- 以上结论来自指定设备release实测，原始JSON/截图/adb输出在 `example/tool/coverage_evidence/`。
- 字幕四格式与完整卡顿上报补测完成；所有未能完整满足编号的项继续保留BLOCKED，不以静态阅读补PASS。

## 事件逐型载荷、重复与state核对

- 去掉各JSON中此前命令的累计记录；每行引用一份具体动作日志。统计的是该证据文件内次数，非去重后的全运行总数。
- MovaPause：batch1-basic-swap.json：本命令MovaPause=3次，同型相邻载荷相同=2；样例ms=20240 payload={}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaDurationChange：batch1-basic-swap.json：本命令MovaDurationChange=6次，同型相邻载荷相同=0；样例ms=20347 payload={"duration":40000}。逐事件接收时state对账差异=0。
- MovaBufferChange：batch1-basic-swap.json：本命令MovaBufferChange=7次，同型相邻载荷相同=0；样例ms=20262 payload={"buffering":true}。逐事件接收时state对账差异=3。
- MovaSizeChange：batch15-abr.json：本命令MovaSizeChange=7次，同型相邻载荷相同=0；样例ms=553931 payload={"width":640,"height":0}。逐事件接收时state对账差异=1。
- MovaSourceChange：batch1-basic-swap.json：本命令MovaSourceChange=3次，同型相邻载荷相同=1；样例ms=20262 payload={"uri":"http://127.0.0.1:18080/vod.mp4?t=1793063996403193"}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaReady：batch1-basic-swap.json：本命令MovaReady=3次，同型相邻载荷相同=2；样例ms=20262 payload={}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaPlay：batch1-basic-swap.json：本命令MovaPlay=2次，同型相邻载荷相同=1；样例ms=20408 payload={}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaFirstFrame：batch1-basic-swap.json：本命令MovaFirstFrame=1次，同型相邻载荷相同=0；样例ms=20409 payload={"sinceOpen":191,"signal":"restart"}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaSeek：batch1-basic-swap.json：本命令MovaSeek=7次，同型相邻载荷相同=0；样例ms=24110 payload={"target":5000}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaSeeked：batch1-basic-swap.json：本命令MovaSeeked=7次，同型相邻载荷相同=0；样例ms=24113 payload={"position":5000}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaVolumeChange：batch1-basic-swap.json：本命令MovaVolumeChange=7次，同型相邻载荷相同=0；样例ms=24673 payload={"value":-10.0}。逐事件接收时state对账差异=0。
- MovaBrightChange：batch1-basic-swap.json：本命令MovaBrightChange=6次，同型相邻载荷相同=0；样例ms=25736 payload={"value":-1.0}。逐事件接收时state对账差异=0。
- MovaRateChange：batch1-basic-swap.json：本命令MovaRateChange=5次，同型相邻载荷相同=0；样例ms=25749 payload={"value":0.5}。逐事件接收时state对账差异=0。
- MovaSttBlock：batch1-basic-swap.json：本命令MovaSttBlock=1次，同型相邻载荷相同=0；样例ms=25765 payload={"reason":"disabled"}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaDone：batch1-playlist.json：本命令MovaDone=1次，同型相邻载荷相同=0；样例ms=54365 payload={}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaQualityListChange：batch15-abr.json：本命令MovaQualityListChange=1次，同型相邻载荷相同=0；样例ms=553491 payload={"qualities":["自动:","360p:http://127.0.0.1:18084/high/index.m3u8","180p:http://127.0.0.1:18084/low/index.m3u8"]}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaQualityChange：batch15-abr.json：本命令MovaQualityChange=4次，同型相邻载荷相同=0；样例ms=553491 payload={"quality":"自动"}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaAbrDownShift：batch15-abr.json：本命令MovaAbrDownShift=1次，同型相邻载荷相同=0；样例ms=562586 payload={"from":"360p","to":"180p"}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaSwapChange：batch15-adResume.json：本命令MovaSwapChange=30次，同型相邻载荷相同=0；样例ms=281519 payload={"phase":"warming"}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaErrorEvent：batch15-hang-2s-0.json：本命令MovaErrorEvent=2次，同型相邻载荷相同=0；样例ms=68013 payload={"error":"Failed to open http://127.0.0.1:18080/hang?t=1793068221654008."}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaPlayFailure：batch15-hang-2s-0.json：本命令MovaPlayFailure=1次，同型相邻载荷相同=0；样例ms=68016 payload={"kind":"nativeEndError","action":"MovaRecoveryAction.giveUp","attempt":1,"isLive":false,"sourceIndex":0}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaFullScreenChange：batch15-lifecycle.json：本命令MovaFullScreenChange=2次，同型相邻载荷相同=0；样例ms=220411 payload={"value":true}。逐事件接收时state对账差异=0。
- MovaLiveEdgeReach：batch15-live-step0-0.json：本命令MovaLiveEdgeReach=1次，同型相邻载荷相同=0；样例ms=125432 payload={}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaPreviewBlock：batch15-preview-blocked.json：本命令MovaPreviewBlock=4次，同型相邻载荷相同=3；样例ms=370641 payload={"reason":"network"}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaFailover：batch15-recovery-liveAlternatives.json：本命令MovaFailover=1次，同型相邻载荷相同=0；样例ms=54097 payload={"from":0,"to":1,"uri":"http://127.0.0.1:18080/other404.mp4?t=1793068209673598"}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaFitChange：batch16-audio-start.json：本命令MovaFitChange=1次，同型相邻载荷相同=0；样例ms=248659 payload={"fit":"cover"}。逐事件接收时state对账差异=0。
- MovaLockChange：batch16-engine-lock.json：本命令MovaLockChange=1次，同型相邻载荷相同=0；样例ms=35029 payload={"value":true}。逐事件接收时state对账差异=0。
- MovaMiniChange：batch16-engine-mini-host.json：本命令MovaMiniChange=1次，同型相邻载荷相同=0；样例ms=92721 payload={"mini":true}。逐事件接收时state对账差异=0。
- MovaOrientationChange：batch16-engine-mini-landscape.json：本命令MovaOrientationChange=1次，同型相邻载荷相同=0；样例ms=99278 payload={"orientation":"landscape"}。逐事件接收时state对账差异=0。
- MovaTimeShiftChange：batch16-live-start.json：本命令MovaTimeShiftChange=2次，同型相邻载荷相同=0；样例ms=272467 payload={"behind":12000}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaStandbyChange：batch16-standby-off.json：本命令MovaStandbyChange=1次，同型相邻载荷相同=0；样例ms=317110 payload={"phase":"resuming","reason":"woke","mode":"null"}。逐事件接收时state对账差异=0。
- MovaRecovered：batch2-failover.json：本命令MovaRecovered=1次，同型相邻载荷相同=0；样例ms=78247 payload={"attempts":1}。接收时完整state见同条JSON；空载荷是事件定义，重复动作可重复发射。
- MovaZoomChange：batch3-09-zoom--1.json：本命令MovaZoomChange=1次，同型相邻载荷相同=0；样例ms=212400 payload={"zoom":-1.0}。逐事件接收时state对账差异=0。

## 批次18 PiP与手势第一阶段

- batch18-normal/autohide/doubletap-seek/longpress-*保存真实注入后状态与截图；默认双击seek判据已纠正。
- batch18-pip-*保存进入、展开及第二次进入的原生activity状态；X关闭需根据实际系统控件定位后补测。

## 批次18/19：PiP双退出、手势、转屏、直播与历史结论复核

- X关闭前/后截图及native活动状态已取得，先前点错坐标的batch18-pip-closed-x不得作为关闭成功证据。
- 修正此前将grace兜底归为F6/N20失败的过严判定：矩阵允许状态机恢复，保留信号未落地的测量事实。
- HLS旧脚本错误等待被契约抑制的Seeked；第二版又用跨引擎latest和duration流变化作门控，均作为验证器问题保留，不计库FAIL；最终版本使用每引擎progress和原生位置直接读回，待最后一次复跑。

## batch21-hls-normal 原生位置复核

- 每模式重启独立进程；HTTP源无流量节流。
```json
[
  {
    "ms": 2217,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hls"
    }
  },
  {
    "ms": 11198,
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
    "ms": 11880,
    "kind": "HLS_NATIVE",
    "run": 0,
    "target": 8063,
    "landed": 8063,
    "samples": [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      8063
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40000,
      "position": 8063,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
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
    "ms": 11881,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=0 target=8063 landed=8063 error=0"
  },
  {
    "ms": 13215,
    "kind": "HLS_NATIVE",
    "run": 1,
    "target": 8223,
    "landed": 8223,
    "samples": [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      8223
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40000,
      "position": 8223,
      "size": "320x180",
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 13216,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=1 target=8223 landed=8223 error=0"
  },
  {
    "ms": 14605,
    "kind": "HLS_NATIVE",
    "run": 2,
    "target": 8263,
    "landed": 8263,
    "samples": [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      8263
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": true,
      "duration": 40000,
      "position": 8263,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
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
    "ms": 14606,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=2 target=8263 landed=8263 error=0"
  },
  {
    "ms": 16035,
    "kind": "HLS_NATIVE",
    "run": 3,
    "target": 23,
    "landed": 79,
    "samples": [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      79
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40000,
      "position": 0,
      "size": "320x180",
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 16035,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=3 target=23 landed=79 error=56"
  },
  {
    "ms": 17445,
    "kind": "HLS_NATIVE",
    "run": 4,
    "target": 63,
    "landed": 63,
    "samples": [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      63
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": true,
      "duration": 40000,
      "position": 63,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
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
    "ms": 17446,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=4 target=63 landed=63 error=0"
  },
  {
    "ms": 21718,
    "kind": "HLS_END",
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 4103,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
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
    "ms": 22014,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch21-hls-swap 原生位置复核

- 每模式重启独立进程；HTTP源无流量节流。
```json
[
  {
    "ms": 2221,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hls",
      "swap": "true"
    }
  },
  {
    "ms": 11232,
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
    "ms": 11965,
    "kind": "HLS_NATIVE",
    "run": 0,
    "target": 8143,
    "landed": 8143,
    "samples": [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      8143
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40000,
      "position": 8143,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
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
    "ms": 11965,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=0 target=8143 landed=8143 error=0"
  },
  {
    "ms": 13254,
    "kind": "HLS_NATIVE",
    "run": 1,
    "target": 8303,
    "landed": 8303,
    "samples": [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      8303
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": true,
      "duration": 40000,
      "position": 8303,
      "size": "320x180",
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 13254,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=1 target=8303 landed=8303 error=0"
  },
  {
    "ms": 14078,
    "kind": "HLS_NATIVE",
    "run": 2,
    "target": 103,
    "landed": 0,
    "samples": [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": true,
      "duration": 40000,
      "position": 103,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
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
    "ms": 14078,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=2 target=103 landed=0 error=-103"
  },
  {
    "ms": 15808,
    "kind": "HLS_NATIVE",
    "run": 3,
    "target": 103,
    "landed": 103,
    "samples": [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      103
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": true,
      "duration": 40000,
      "position": 103,
      "size": "320x180",
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 15808,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=3 target=103 landed=103 error=0"
  },
  {
    "ms": 16715,
    "kind": "HLS_NATIVE",
    "run": 4,
    "target": 103,
    "landed": 103,
    "samples": [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      103
    ],
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40000,
      "position": 103,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
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
    "ms": 16715,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=4 target=103 landed=103 error=0"
  },
  {
    "ms": 21337,
    "kind": "HLS_END",
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 3903,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
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
    "ms": 21555,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## batch21-hls-paused 原生位置复核

- 每模式重启独立进程；HTTP源无流量节流。
```json
[
  {
    "ms": 2232,
    "kind": "BEGIN",
    "group": "new",
    "args": {
      "group": "new",
      "case": "hls",
      "paused": "true"
    }
  },
  {
    "ms": 11207,
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
    "ms": 11932,
    "kind": "HLS_NATIVE",
    "run": 0,
    "target": 8103,
    "landed": 8063,
    "samples": [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      8063
    ],
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 8063,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
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
    "ms": 11933,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=0 target=8103 landed=8063 error=-40"
  },
  {
    "ms": 13229,
    "kind": "HLS_NATIVE",
    "run": 1,
    "target": 8063,
    "landed": 8063,
    "samples": [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      8063
    ],
    "state": {
      "playing": false,
      "intent": false,
      "buffering": true,
      "duration": 40000,
      "position": 8063,
      "size": "320x180",
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 13229,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=1 target=8063 landed=8063 error=0"
  },
  {
    "ms": 14680,
    "kind": "HLS_NATIVE",
    "run": 2,
    "target": 23,
    "landed": 23,
    "samples": [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      23
    ],
    "state": {
      "playing": false,
      "intent": false,
      "buffering": true,
      "duration": 40000,
      "position": 23,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
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
    "ms": 14681,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=2 target=23 landed=23 error=0"
  },
  {
    "ms": 16047,
    "kind": "HLS_NATIVE",
    "run": 3,
    "target": 23,
    "landed": 23,
    "samples": [
      0,
      0,
      0,
      0,
      0,
      0,
      23
    ],
    "state": {
      "playing": false,
      "intent": false,
      "buffering": true,
      "duration": 40000,
      "position": 23,
      "size": "320x180",
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
      "timeshiftBehind": null,
      "liveSeekable": false,
      "seekableWindow": 40000,
      "hudText": null,
      "dragging": false,
      "previewAt": null
    },
    "path": "http://127.0.0.1:18084/low/index.m3u8"
  },
  {
    "ms": 16047,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=3 target=23 landed=23 error=0"
  },
  {
    "ms": 17435,
    "kind": "HLS_NATIVE",
    "run": 4,
    "target": 23,
    "landed": 23,
    "samples": [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      23
    ],
    "state": {
      "playing": false,
      "intent": false,
      "buffering": false,
      "duration": 40000,
      "position": 23,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
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
    "ms": 17436,
    "kind": "CHECK",
    "id": "F3.switch",
    "pass": true,
    "detail": "run=4 target=23 landed=23 error=0"
  },
  {
    "ms": 21812,
    "kind": "HLS_END",
    "state": {
      "playing": true,
      "intent": true,
      "buffering": false,
      "duration": 40007,
      "position": 3943,
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
      "standby": "off",
      "type": "vod",
      "title": null,
      "pipSupported": true,
      "controls": false,
      "hud": "none",
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
    "ms": 22119,
    "kind": "END",
    "group": "new",
    "status": "done"
  }
]
```

## 批次22：重映射、实际小窗拖动、NextUp及Feed输入

- 原始动作/状态与PNG：`example/tool/coverage_evidence/batch22-*`。
- 控件树语义转储：batch22-controls.xml；双击改用同一adb shell连续注入，避免两个adb进程的延迟。

## 批次20–23：边界、广告失败策略、真实网络探针、HLS原生结论

- 每条引用的JSON含真实事件及state；HLS失败的原生path也记录，排除仅UI标签切换。
- 后续只补最终视觉与HLS swap/暂停态，当前已测数据先落盘。

## 批次25 可视第一阶段

- 逐动作日志/PNG及封面连续帧已保存batch25-*；包括真实preview气泡、custom红色spinner及显隐、错误层、mini默认禁用。

## 批次25 可视第二阶段

- batch25-nextup*、ad-countdown/ad-skippable/ad-skip、route-player/back及feed-poster连续帧保存；跳过按钮通过真实语义树定位。
- 矩阵里不存在的发送框、长按倍速、倍速菜单、NextUp数字倒计时/TopBar返回不能用别的动作冒充通过。

## 批次28：延迟缩略图竞态与自定义posterFade

- slowthumbs.vtt服务人为延迟2.5s；拖动预览请求发起后0.7s换源，晚到的非空thumb统计见batch28-stale-audit.json；服务端BEGIN/END见coverage_media_final.log。
- MovaPlayer.posterFade设置2s以便真实截图观测中间透明度，12张连续PNG及最终state已保存。

## 最终批次：可视证据核对、FAIL复现与BLOCKED条件

### 最小复现与FAIL分类

下表是同类问题合并后的复现；**FAIL编号数不是独立bug数**。特别是“矩阵契约/能力差异”不能直接理解为有效输入下播放故障。所有命令仅操作独立包 `com.icodejoo.mova.mova_example.coverage`。

| 涉及编号 | 分类与最小复现 | 本轮证据 |
|---|---|---|
| A23 | 生命周期问题：`a=createMovaEngine(audioOnly:true)`，open后`await a.dispose(); await a.dispose();`；第二次抛`[Player] has been disposed`，普通/swap均复现。120轮首次创建/销毁完成，不能替代幂等要求。 | batch15-basic/basic-swap.json 的A23.doubleDispose=false；batch15-dispose120.json及round20..120.meminfo.txt |
| F8/N19 | 续播问题：本地stall.mp4播放到约2.52–2.68s，有限重试`MovaRetryThenFailover`；卡顿恢复后首采样40ms并从头增长，1.5s内未回原位置，5次0通过。 | batch6-he-recovery-guard.log，HE V6；不要用旧默认无限直播重连脚本的超时冒充本缺陷 |
| A17/F3 | 续播问题：打开18084/master.m3u8，原生位置>=8s，loadQualities，先360p再180p。首切恢复，第二次原生RESTART落23ms，从头播；普通和默认关闭的swap代理均复现，暂停态也丢位置。 | batch23-hls-native.json、batch24-hls-native-swap/paused.json，HLS_RESTART含原生path；三模式首个切档误差[-40,0,-40]ms，第二切均失败 |
| C16 | 原生TLS兼容问题：`tlsVerify:true,tlsCaFile:<ca.pem>`，打开https://127.0.0.1:18443/vod.mp4或low/index.m3u8；合法IP SAN证书被拒。改localhost:18447合法DNS证书能播放。未定位Dart/mpv/mbedtls具体责任层。 | batch15-tls40格35符合预期；batch17-tls-probe合法DNS 6/6通过、IP 6/6失败；CA/tls属性读回；openssl verify IP证书成功 |
| A1 | 矩阵流契约差异：直接读events/states/progress/uiStates.isBroadcast为[true,false,true,false]；两个订阅仍都收到，dispose后八订阅全关闭。 | batch15-basic/basic-swap.json STREAM_FLAGS，不是已证实的订阅互相干扰 |
| A2/E.MovaBufferChange/E.MovaSizeChange | 异步交付快照差异：订阅event时同时读`a.state`，连续更新时载荷与“接收这一刻”的最新state可不同。不能由此推断解码状态错误。 | event-audit.json；batch1-basic-swap BufferChange 7次中3次，batch15-abr SizeChange 7次中1次不符；原始ms/engine/state齐全 |
| A5/N12 | 矩阵同步/错误契约差异：已播放40s源时`f=a.open(other);`立刻读state仍为旧duration/rendered/title，随后异步清零；恢复关闭的404 `await open`为true且不抛，错误通过event/state报告。 | batch15-basic两实现OPEN_SYNC；batch20-edges BAD_OPEN_RESULT accepted=true/threw=false。与N8的true=接受语义一致 |
| A8/A9/A12 | 越界输入契约差异：setVolume(-10/110)、setBrightness(-1/2)、setZoom(-1/0/100)的state保留输入。合法范围音量/亮度原生写回正常；maxZoom是手势上限，直接setZoom不使用该上限。 | batch15-basic及batch3-zoom JSON；音量0/50/100/30→系统0/10/20/6(max20)；batch20亮度原生0/.25/.75/1逐项一致 |
| C3/U6 | 能力假设差异：真实播放时在视频上长按1800ms，rate仍1；当前GestureLayer没有长按倍速处理。双击实际是左右±10s seek，不是播放切换。 | batch18-longpress-during/after、doubletap-seek；batch22轴向改配通过 |
| C6 | 能力假设差异：弹幕只展示宿主固定items，故意不含发送API/输入框。滚动已实际截图。 | batch25-danmaku.png；MovaDanmakuConfig设计为Display-only |
| C8/U7 | 能力假设差异：NextUp在提前窗口显示卡片及取消/立即播放，未显示数字倒计时。立即播放点击有效，自动连播另已测。 | batch22-nextup.png、batch25-nextup-click.json（新title/position40ms）；广告自身倒计时/跳过正常 |
| U3 | 能力假设差异：TopBar未提供返回按钮；路由可用Android BACK退出。 | batch25-route-player/route-back.png，TopBar组件树只有title/PiP/quality/subtitle/fit/orientation/fullscreen |
| U5 | 能力假设差异：SpeedButton点击循环倍速，未弹菜单；实际1x→1.25x。 | batch25-speed-button.json/png；CenterPlay/HUD子项通过 |
| E1 | 顺序契约差异：实际Play意图事件早于Ready/FirstFrame，不符合矩阵示意箭头的严格顺序；不能将Play当首帧证据。 | batch15-lifecycle.json LIFECYCLE数组、逐条EVENT；naturalDone=1/errors=0，F1通过 |

复跑入口（先启动本地源与adb reverse，设备亮屏解锁）：`python example/tool/coverage_suite_device.py api --name repro-launch`，再`python example/tool/coverage_device.py new --arg case=hls --name repro-hls --timeout 180`；双dispose用`basic`及`basic --arg swap=true`；V6用`coverage_suite_device.py he --only V6 --runs 5`。库代码不改。

### BLOCKED所缺条件

- A31/C7：缺真实STT识别引擎、模型与可用下载服务。disabled/noEngine及失败回滚重试已测，未把注入的Noop派生引擎当作真实转写；SRT导出/分块存储没有真机通过证据。
- C2：现有FLV/HLS源支持播放/本地DVR窗口，未提供按behind URL返回历史时刻、且可控卡顿的服务。urlBuilder历史语义、自定义windowResolver及autoBackToLiveOnStall完整联动未完成；需要该服务才能继续，不能用忽略参数的live源冒充历史回看。
- F15：WHEP 38889/test/whep不可达，缺publisher、信令及UDP38189/relay38190映射。WHEP选项读回不等于15s真实播放。
- N22：assert启用的AOT构建在当前Flutter 3.47 SDK编译失败；release及profile日志已保存。除assert子项外，异步钩子、轴向改配、STT回滚、crop、换源旧结果丢弃均有实际证据。不能用单测结果补真机PASS。

### 与CLAUDE.md/交接结论的对照

- 单测基线为1503通过，较文档1472多31；`flutter analyze lib test` 0问题。复启基线分别见coverage_baseline_test_restart.log/analyze_restart.log；不是本轮新增库测试。
- HE V6“续播就绪修复待Android复测”：本轮仍0/5，从40ms起播放，与期望修复行为不一致。
- PiP退出state不复位的历史段落已过期：本轮展开及X均收到false/state复位；X会暂停，展开继续播。
- 历史WarmPlan方向/广告短暂用户倍速窗口/pod第二条回落：本轮广告采样1x、内容恢复2x/1.5x、pod真换指，退役dispose不复位全局方向。每项3轮，未声称穷尽所有微任务时间窗口。
- Android 404约120ms、拒连约79ms即nativeEndError，非Windows约5s；默认黑洞约5.28s先由mpv network-timeout结束，65s是Dart兜底派生值。
- standby功能迁移/mediacodec-copy唤醒20/20通过，但S1跨GOP15/15仍靠grace约5s，不能将StandbyResume.elapsed当实际出画耗时；实际属性恢复约百余ms。该兜底受配置允许，最终F6/N20记PASS并保留信号/延迟观察。
- S14 Android holding为黑屏、恢复正常，区别于Windows保留帧；S5只测20s，漂移137/681/410ms，均值409.3ms，不能据此宣称Windows 60s约2.5s漂移已修复。
- 首帧证据使用native restart与实际事件。qoe:false零QoE、弱客户端0；完整卡顿释放后stallCount1/stallMs5468；120次首次销毁完成。上述均不以截止时间、UI标签、临近EOF seek推断性能。

### 证据与环境边界

- 所有主功能设备测试为release；profile只尝试assert构建且未安装失败产物。独立APK身份保留原示例包的数据/签名，真机仍为7NQBB23606003715。
- 原packages Android libmpv是132bytes LFS指针。仅在example/tool/coverage_native中取匹配二进制；SHA256=798cde9e27e3761dd5f8f065693e4669b5499d5807618f81a74e0d3a88dc230b，6357872bytes。JNI重定向、appId、ABI与integration_test依赖均通过tool/coverage.init.gradle，不改Android工程/库源码。
- CPU为top采样、单核百分比；USB充电下没有给出电池能耗结论。120轮RSS从227037184到247193600bytes，后60/80/100/120轮为241020928/245993472/246718464/247193600；PSS原始文件在同目录。不声称绝对无泄漏。
- 系统没有screenrecord（inaccessible or not found），已用adb PNG连拍取代；posterFade=2s有中间颜色而非只拍前后两态。主观手感、真实人耳听感未作测量结论。
- 每个主台账编号只有一个结论；批次历史中旧锁屏/构建阻塞、验证器误判及中间计数均保留，**当前台账和本节优先**。旧HE V5默认无限重试、字幕asset缺失/挂载时dispose、HLS等待Seeked/跨引擎latest/瞬时读回均是验证器问题，未作为库bug。

## 收尾核验

- 最终验证页分析：xample/tool/coverage_final_analyze.log，5项文件分析0 issues（3.0s）；24个coverage Python脚本语法编译通过。
- git diff --name-only -- lib test为空；未修改库/测试源码，未执行commit/stash/reset；其他会话产生的计划文档、原有packages/macOS二进制及Windows生成文件改动均保留。
- 最终dispose证据 xample/tool/coverage_evidence/final-dispose.*；已force-stop独立测试包，inal-process.txt为空，未影响原示例包。USB常亮设置恢复0，见final-power-setting.txt；解锁/亮屏收尾状态见final-device.txt。本地夹具服务和adb端口映射保留便于复跑。
- TLS IP证书独立校验输出：xample/tool/coverage_evidence/tls-ip-openssl-verify.txt，good.pem: OK。
- 构建证据：最后成功suite release见coverage_build_transition.log及其测试启动日志；后续assert AOT失败仅属于验证环境，未安装失败产物；主测试均为release。

- 收尾补充：恢复USB常亮后设备已自动锁屏（final-device.txt为isKeyguardShowing=true），发生在全部测试、final-dispose及force-stop之后；该锁屏截图/状态不作为渲染PASS证据。媒体音量收尾尝试设回起测前6/20，但Huawei shell命令读回仍15/20；未将尝试当作恢复成功，见final-volume-restore.txt及final-volume-readback.txt。

- 媒体音量最终已通过audioOnly端口恢复6/20，见final-volume-native-readback.txt；之前shell恢复尝试不生效。收尾audioOnly日志cleanup-volume-audioOnly.json仅用于设置恢复，不计入锁屏下的覆盖测试结果。启动选择器补齐后恢复成功，最终独立测试App再次force-stop。

## 终审（Claude + opus 复核，2026-10-27）

Codex 的 23 个 FAIL 经两个 opus (high) 只读子代理逐条核对源码与证据，主会话抽查关键结论。**判定与处理**：

| 条目 | 终审判定 | 处理 |
|---|---|---|
| F3/A17 | **成立（P1）**：切档后续播 seek 在时长到达时就发，此时 mpv 播放尚未初始化，seek 被静默丢弃；潜伏竞态，非回归 | **已修**：`engine.dart` 换档续播 seek 等新档位落地（首帧/RESTART）再发，4s 兜底；+3 单测、改 1 条旧测。真机复测（`f3fix-hls-normal/swap/paused`，各 5 次）**15/15 落点误差 0ms**（修复前每组 1/5） |
| F8/N19 | **误报（验证脚本缺陷）**：`he_auto.dart` V6 用 `log.indexOf(pf)` 找事件，`Stamped` 无 `==`、`wait()` 返回新副本，恒为 -1，匹配到会话最初首帧；且重试不会再发 `MovaFirstFrame` | **已修脚本**（以 `MovaRecovered` 为锚点）。真机复测 V6 **5/5 PASS**，续播误差 0–40ms，CLAUDE.md 的 V6 修复结论在 Android 成立。10-24 Windows 上"V6 从头播"很可能是同一脚本假象 |
| A8 | 成立（P3）：`setVolume` 越界值写进 state，系统音量被端口钳到 0–100 | **已修**：入口钳 0–100，+1 单测 |
| A9 | 成立（P3）：越界亮度被插件拒绝并吞掉，真实亮度没变而 state 已变 | **已修**：入口钳 0–1，+1 单测 |
| A1 | 降级（P3）：`states`/`uiStates` 用 `Stream.multi`，`isBroadcast=false`，多订阅实测正常 | 未改，可选标 `isBroadcast: true` |
| A2 / E.BufferChange / E.SizeChange | 降级（P3）：普通引擎载荷与 state 一致；仅 swap 代理 state 与事件分两条订阅转发，state 短暂落后（`swap_engine.dart:207/209`）；另有半更新尺寸事件（`mpv_kernel.dart:169-178`） | 未改 |
| A12 | 降级（P3）：`maxZoom` 只限手势；但 `setZoom(≤0)` 会让画面塌缩 | 未改，建议加下限 |
| C16 | 降级（P3）：Android mbedtls 3.4 对 IP 类 SAN 的主机名校验不支持（子代理凭记忆，未核对源码） | 未改，建议 README「已知限制」写明：开启 `tlsVerify` 时用域名并签发含 DNS SAN 的证书 |
| E1 / A5 / A23 / N12 | 误报：Play 必早于 FirstFrame；`open()` true 仅表示"源被接受"；`dispose` 契约是只能调一次；N12 只承诺宽高归零且 audioOnly 无尺寸（清零在 `beforeOpen` 之后，非严格同步） | 未改；A23 可选加 `_disposed` 早退加固 |
| C3/U6 C6 C8 U3 U5 U7 | 误报：库没有长按倍速、弹幕发送、NextUp 数字倒计时、顶栏返回按钮；倍速按钮是循环切档；U7 应判 PASS | 未改 |
| BLOCKED ×5 | 理由合理。A31/C7 可用注入引擎补测 SRT/分片存储；C2 可扩 `live_server.py`；F15 缺 WHEP 服务；N22 是 Flutter SDK 不支持 AOT 加断言，应改用 debug 构建 | 待补测 |

**修复后基线**：`flutter analyze lib test` 0 issues，`flutter test` **1508 全绿**（1503 + A8/A9 共 2 + F3 共 3）。

**测试方法教训**：`flutter run` 打出的包里 `libmpv.so` 是 LFS 指针（132 字节），应用在 media_kit 初始化即失败；真机包必须走 `example/tool/coverage_build.py` 的隔离构建（用 `tool/coverage_native` 里的真实 `.so`，独立包名 `.coverage`）。
