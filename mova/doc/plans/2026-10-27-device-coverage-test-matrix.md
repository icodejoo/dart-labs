# mova 真机完整覆盖测试矩阵

> 2026-10-27 · 读者：Codex（无本次会话上下文）。依据：`lib/mova.dart` 导出面、`lib/src/core/api.dart`、`events.dart`、`options.dart`、`CLAUDE.md`。
> 编号规则：`A*` 公开 API，`C*` 配置对象，`E*` 事件，`U*` UI 组件，`F*` 功能场景。每条都要在真机给出 PASS / FAIL / BLOCKED + 证据。

## 0. 通用约束

- 设备：`adb devices` 里的 `7NQBB23606003715`（Android，arm64）。测前确认**亮屏且已解锁**（`adb shell dumpsys window | grep isKeyguardShowing`），锁屏时渲染面相关结果作废。
- 构造引擎一律 `createMovaEngine()`，不要裸 `MovaEngine()`；验证脚本里涉及无界面的引擎用 `audioOnly: true`（避免 media_kit 的 VideoController 卡死）。
- 判据必须基于**真实事件/状态**（`events`/`states`/`renderEpoch`/`MovaDone` 时间戳），不用墙钟猜、不用临近 EOF 的 seek；URL 加时间戳防缓存，时间类数字多次取平均。
- 验证页新建在 `example/lib/verify_auto/` 与 `example/lib/main_coverage_*.dart`；**不改 `lib/**`**。发现 bug 只记录复现步骤与证据。
- 本地源：`example/tool/verify_sources/` 有本地 HTTP 源服务，经 `adb reverse` 映射；联网源可用 `https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8`（多码率 HLS）。
- 先跑 `flutter test`（基线 1472 项全绿）与 `flutter analyze lib test`，确认起点干净再上真机。

## A. 公开 API（`MovaApi`，覆盖 `MovaEngine` 与 `MovaSwapEngine` 两种实现）

| 编号 | 成员 | 测试点 |
|---|---|---|
| A1 | `events`/`states`/`progress`/`uiStates` | 四条流均为 broadcast，多订阅者互不影响；dispose 后流关闭；progress 随播放单调推进 |
| A2 | `state` | 各字段与对应事件一致（position/duration/buffering/playing/size/volume/rate/fit/zoom/locked/fullscreen/pip/mini/rendered/sourceIndex/playbackIntent/standby/renderEpoch） |
| A3 | `renderHandle` | 普通引擎非空；`audioOnly` 为 null；懒创建：首次读取才建 VideoController |
| A4 | `pipSupported` | Android 为 true，与 `state.pipSupported` 一致 |
| A5 | `open(source, autoPlay)` | autoPlay true/false；返回值；同步归零宽高/duration；连续两次 open（换源）无残留 position；坏地址行为（recovery 关：抛出；开：走恢复）；`MovaSource.sameAs` |
| A6 | `play`/`pause`/`playOrPause` | 状态与 `MovaPlay`/`MovaPause` 事件；`playbackIntent` 独立于内核 playing；重复调用幂等 |
| A7 | `seek`/`seekBy` | 点播精确度（落点误差）；越界钳制（负数/超时长）；直播被拦；seek 后 `MovaSeek`/`MovaSeeked`；加载中 seek 被寄存后兑现 |
| A8 | `setVolume` | 0/中间/1 边界与钳制；`MovaVolumeChange`；经 `MovaVolumePort` 真写系统媒体音量（`adb shell dumpsys audio` 对账） |
| A9 | `setBrightness` | 边界钳制；`MovaBrightChange`；真实窗口亮度变化 |
| A10 | `setRate` | 0.5/1/1.5/2 与非法值；`MovaRateChange`；换源后倍速保持/复位策略；广告复位 1x |
| A11 | `setFit` | 全部 `MovaFit` 取值；`MovaFitChange`；画面真实变化（截图对比） |
| A12 | `setZoom` | 边界（含 maxZoom）；`MovaZoomChange`；缩放后手势平移 |
| A13 | `setLocked` | 锁定后手势与控件被屏蔽；`MovaLockChange` |
| A14 | `setFullscreen` | 进/出全屏；`MovaFullScreenChange`；系统栏隐藏/恢复；按宽高比转屏 |
| A15 | `setMini` | 进/出小窗；`MovaMiniChange`；与 PiP 互斥；不重新解码（position 连续、`renderEpoch` 不变） |
| A16 | `setOrientation` | `auto`/`portrait`/`landscape`；`MovaOrientationChange`；真实转屏（`dumpsys` 或截图宽高） |
| A17 | `loadQualities`/`switchQuality` | 多码率 HLS 列出档位；`MovaQualityListChange`/`MovaQualityChange`；换档续播误差；与 ABR 背靠背不丢 seek |
| A18 | `enterPip` | 返回 true；`MovaPipChange`；`dumpsys activity` 见 `mIsInPictureInPictureMode=true`；**退出后 `state.pip` 是否复位**（已知缺陷，需记录现状） |
| A19 | `reload` | 重载后位置策略；事件序列 |
| A20 | `backToLiveEdge` | 直播回边缘；`MovaLiveEdgeReach`；点播调用无副作用 |
| A21 | `showControls`/`hideControls`/`showHud`/`setDragging` | `uiStates` 反映变化；sticky；HUD 类型与文本；拖动预览位置 |
| A22 | `report(name, params)` | 内置名与 `MovaReportName.custom`；参数透传；`==`/`hashCode` 按 value |
| A23 | `dispose` | 播放中/加载中/换源中 dispose 不卡死、不抛；二次 dispose 安全；dispose 后调用的行为；120 轮创建销毁无泄漏（PSS 平台） |
| A24 | `MovaSwapEngine`（`swapTo`/`prepare`/`commit`/`abandon`） | 关闭态纯直通；开启态预热→提交 `renderEpoch` 递增；短窗口降级；断网预热超时兜底；影子引擎 dispose |
| A25 | `MovaStandbyController.setStandby` | on/off；状态机 `off/holding/fallback/resuming`；`pause()` 结束待机；`MovaStandbyChange`/`MovaStandbyResume` |
| A26 | `MovaMiniController` | `show`/`showInPage`/`hide`/`close`/`isShowing`/`setRect`；`onClosed`/`onTapContent`；方式 A/B 互斥 |
| A27 | `MovaAdController` | `load`/`loadDeferred`/`playAdNow`/`skip`/`notifyClicked`；前贴/中插/后贴；pod 串联；失败策略 `MovaAdFailPolicy`；等待策略 `MovaAdWaitByKind` |
| A28 | `MovaPlaylistController` | `next`/`previous`/`jumpTo`/`hasNext`；播完自动下一条；边界不越界；dispose |
| A29 | `MovaFeedController`/`MovaEnginePool`/`MovaFeedPrefetcher` | `ensure`/`activate`；邻居预热窗口；快速连续滑动的取消与最终一致；池回收 |
| A30 | 预览 `MovaPreviewApi` | `requestAt`/`cancel`/`clear`；VTT 雪碧图源、抽帧兜底源；内存+磁盘两级缓存命中；网络策略（`net_probe`）；断网降级 |
| A31 | STT `MovaSttApi` | `start`/`stop`；模型缺失/下载失败路径；`MovaSttBlock`；SRT 导出；分块字幕存储（若 STT 引擎不可用则标 BLOCKED 并说明原因） |
| A32 | 拦截点 `MovaHook` | `play`/`seek` 等钩子放行/拦截/异步返回；异常不拖垮引擎 |
| A33 | `package:mova/testing.dart` | `MovaTestKernel`/`MovaTesting` 安装后平台端口空实现（真机上仅做冒烟） |

## C. 配置对象（`MovaOpts` 全字段）

| 编号 | 对象 | 测试点 |
|---|---|---|
| C1 | `preview`/`MovaPreviewConfig` | 开关、来源顺序、缓存上限 |
| C2 | `live`/`MovaLiveConfig` | `urlBuilder`/`backToLive`/`autoBackToLiveOnStall`/`windowResolver`；时移窗口 `resolveWindow`/`behindOf`/`atLiveEdge` 真机直播流 |
| C3 | `gesture`/`MovaGestureConfig` | 左亮度/右音量默认；侧别映射改配；水平拖动 seek；双击；长按倍速；`douyin` 手势层 |
| C4 | `abr`/`MovaAbrConfig` | 限速下降档（`MovaAbrDownShift`）；`MovaBufferAbr` 触发与 reset |
| C5 | `controls`/`MovaCtrlsConfig` | 各控件显隐与自动隐藏时长 |
| C6 | `danmaku`/`MovaDanmakuConfig` | 弹幕发送/滚动/密度/开关 |
| C7 | `stt`/`MovaSttConfig` | 见 A31 |
| C8 | `playlist`/`MovaPlaylistConfig` | 自动连播、NextUp 倒计时 |
| C9 | `ads`/`MovaAdConfig` | 默认关；排期；`waitsFor` 三层覆盖 |
| C10 | `strings`/`MovaStrs`、`theme`/`MovaTheme` | 文案与主题替换生效；缓冲三字段 |
| C11 | `swap`/`MovaSwapConfig` | 默认关闭与开启 |
| C12 | `mini`/`MovaMiniConfig` | 默认关闭；吸边、`remapProportionally` 转屏不走位 |
| C13 | `report`/`MovaReportConfig` | `qoe:false` 零 QoE 事件；`qoe:true` 见 F7 |
| C14 | `recovery`/`MovaRecoveryConfig` | 默认关；超时/重试/切换；`MovaTimeouts` 透传 mpv（0.4.0 新增）；按源 mpv 选项 |
| C15 | `standby`/`MovaStandbyConfig` | `maxDuration`/`resumeTimeout`/`allowHls` 默认值 |
| C16 | TLS：`tlsVerify`/`tlsCaFile` | 默认关；开启后合法/非法证书矩阵 |
| C17 | `MovaSource` | `alternatives`/`uris`/`pick`/`sourceIndex`；请求头；按源 mpv 选项 |

## E. 事件（`MovaEvent` 全部子类，逐个真机触发并核对载荷）

`MovaReady` `MovaSourceChange` `MovaPlay` `MovaPause` `MovaDone` `MovaSeek` `MovaSeeked` `MovaBufferChange` `MovaDurationChange` `MovaFirstFrame` `MovaSizeChange` `MovaVolumeChange` `MovaBrightChange` `MovaRateChange` `MovaQualityListChange` `MovaQualityChange` `MovaAbrDownShift` `MovaFitChange` `MovaZoomChange` `MovaLockChange` `MovaFullScreenChange` `MovaOrientationChange` `MovaPipChange` `MovaMiniChange` `MovaTimeShiftChange` `MovaLiveEdgeReach` `MovaPreviewBlock` `MovaSttBlock` `MovaSwapChange` `MovaErrorEvent` `MovaPlayFailure` `MovaRecovered` `MovaFailover` `MovaStandbyChange` `MovaStandbyResume`。

每个事件要给出：触发动作、实际收到的载荷、是否重复发射、与 `state` 是否一致。**E1** 一次完整点播的事件序列顺序（open→Ready→SizeChange→FirstFrame→Play→…→Done）；**E2** 关闭态（各默认关闭功能）事件数为 0。

## U. UI 组件与皮肤（真机手势/视觉，必要时 `adb shell input` + 截图）

| 编号 | 对象 | 测试点 |
|---|---|---|
| U1 | `MovaPlayer`/`MovaView`/`MovaFeedPlayer` | 挂载/卸载；`poster`/`posterUntilFirstFrame`；`surface`；`MovaView.autoPause` + `routeObservers`；Impeller 下渲染面 |
| U2 | 皮肤 | `MovaDefaultSkin`/`MovaBilibiliSkin`/`MovaDouyinSkin`/`MovaMinimalSkin`/`MovaMiniSkin`；`MovaPatch` 覆写；组件树 `components()` |
| U3 | 顶栏 `TopBar` | 返回/标题/方向按钮（仅移动端）/PiP 按钮（不支持时隐藏） |
| U4 | 底栏 `BottomBar` | VOD 与直播自适应（seekBar/timeshift/backToLive）；进度条拖动与预览气泡 `PreviewComponent` |
| U5 | `CenterPlay`、`SpeedButton`、`HudLayer` | 点击、倍速菜单、亮度/音量/进度 HUD |
| U6 | `GestureLayer`/`DouyinGestureLayer` | 单击/双击/长按/垂直左右半屏/水平拖动；锁定态屏蔽；手感记为主观项 |
| U7 | `Danmaku`、`Subtitle`、`NextUp`、`AdOverlay`、`FeedSocial` | 渲染、点击、倒计时、跳过广告 |
| U8 | `MovaMiniWindow` | 拖动跟手、吸边、甩动不误关、转屏钳回 |
| U9 | `MovaAutoPause` | 切后台/回前台/路由覆盖/`TickerMode` 隐藏；libmpv 切后台自暂停的时序 |

## F. 功能场景（端到端）

| 编号 | 场景 | 通过条件 |
|---|---|---|
| F1 | 点播完整生命周期 | open→播→seek→倍速→全屏→换源→播完→dispose，事件序列合理，无异常 |
| F2 | 直播与时移 | 直播流播放；时移回退/回边缘；`timeshiftBehind` 随动 |
| F3 | HLS 清晰度切换与 ABR | 档位切换续播误差 <200ms；ABR 限速下降档 |
| F4 | 无缝引擎切换 + 广告编排 | 广告→正片 `renderEpoch` 递增；续播误差 <100ms；失败降级；关闭态零事件 |
| F5 | 小窗 + PiP | 见 A15/A18；回前台后的暂停行为记录 |
| F6 | 低功耗待机 | 隐藏→待机→唤醒；`state.standby` 迁移；位置跳变量；`vid` 切回（`mediacodec-copy`）；进后台降级为暂停 |
| F7 | QoE 上报 | TTFF（`signal=restart`）、卡顿次数/时长、`ended/stopped/failed/abandoned` 四分、`truncatedBelow` |
| F8 | 超时与恢复 | 坏地址（404/拒连）；卡顿重试后**续播到失败前位置**（HE V6 在 Android 的复测）；多地址 failover |
| F9 | 仅音频 `audioOnly` | 出声不出画、`renderHandle=null`、`size=0x0`；内存对比 |
| F10 | 预览缩略图 | VTT 与抽帧两路；缓存命中；断网 |
| F11 | 字幕 | SRT/ASS/WebVTT 外挂 + mov_text 内封渲染 |
| F12 | 音频会话与耗电 | 待机/音频模式的耗电粗量级（`dumpsys batterystats` 或 CPU） |
| F13 | 多引擎并存与资源 | feed 引擎池滑动 100 次；三引擎并存互不串扰；dispose 期间帧间隔 <100ms |
| F14 | 原生事件泵（FFI 弱客户端） | release 下 RESTART/END_FILE 到达；`qoe:false` 建客户端数 0 |
| F15 | WHEP | 默认白名单打开 WHEP；播 15s `MovaErrorEvent` 0 次（需可达服务，不可达标 BLOCKED） |
| F16 | 已知遗留缺陷复现 | PiP 退出后 `state.pip` 不复位；`MovaWarmPlan` 方向缺失；pod 第二条广告 `swapTo` 回落——只复现并记录，不修 |

## 复用已有验证页（优先复用，别重写）

`example/lib/` 下：`main_host_ergonomics_verify.dart`（F8/U9）、`main_standby_verify.dart`（F6）、`main_qoe_verify.dart`/`main_qoe_video_verify.dart`（F7）、`main_seamless_swap_verify.dart`/`main_ad_orchestration_verify.dart`（F4）、`main_quality_switch_verify.dart`（F3）、`mini_window_demo.dart`（F5/U8）、`audio_only_demo.dart`（F9）、`main_tls_matrix_verify.dart`（C16）、`main_subtitle_formats_probe.dart`（F11）、`main_whep_verify.dart`（F15）、`main_review_fixes_verify*.dart`（A 组回归）。上面未覆盖的条目（尤其 A1–A4、A8–A16、A28–A33、C 组、U 组）需新建验证页。

## 交付物

1. `doc/plans/2026-10-27-device-coverage-results.md`：按上表编号逐条填 PASS/FAIL/BLOCKED + 证据（事件序列、数字、截图路径、`adb` 输出）。
2. FAIL 项附最小复现步骤；BLOCKED 项写明缺什么。
3. 汇总：总条数、PASS/FAIL/BLOCKED 计数、与 CLAUDE.md 已记录结论不一致之处。

## N. 新增 API 补充（0.3.1 / 0.3.2 / 0.4.0 及 Unreleased；同样要求逐条 PASS/FAIL/BLOCKED）

| 编号 | 新增成员 | 测试点 |
|---|---|---|
| N1 | `MovaTimeouts`（`MovaRecoveryConfig.timeouts`）：`network`/`whepHandshake`/`whepFirstFrame`/`whepMedia`、`kMovaWatchdogMargin` | 每次 open 前真下发 mpv（`network-timeout` 整秒、WHEP 项微秒，只对 `whep…` 生效）；默认全 null 不动 mpv；源级显式设置优先；黑洞主机真实判失败耗时（设 `network` 后 vs 未设 65s 派生） |
| N2 | `MovaRecoveryConfig.startTimeout/stallTimeout`（`Duration?`）、`stallWatchdog`、`startTimeoutFor(uri)`/`stallTimeoutFor(uri)`、`copyWith(clearStallTimeout)` | null=派生（非 WHEP 65s/WHEP 起播 85s 卡顿 10s）；`stallWatchdog:false` 关闭卡顿看门狗；显式值优先；mpv END_FILE 为主路径、Dart 看门狗仅兜底 |
| N3 | `MovaLiveReconnect`、`MovaDefaultRecovery`、`MovaRecoveryConfig.liveReconnect`、`MovaPlayFail.isLive`、`maxDelay` 默认 15s | 直播断流持续重连（退避 1,2,4,8,15,15…）；`maxAttempts`/`retriesPerAddress`；`liveReconnect:false` 回到旧行为；点播默认 `MovaRetryThenFailover` 不变 |
| N4 | `MovaSource.mpvOptions`/`demuxerOptions`/`whepMediaTimeout`/`mpvOptionsFor`、`MovaSourceOptionsKernel` | open 前下发、下一源还原不泄漏；`demuxer-lavf-o` 按键增删不冲掉默认 `protocol_whitelist` 等（`mpv_kernel` 读回对账）；非法项整项跳过且不进 `state.error`；`pick`/`sameAs` 支持 |
| N5 | recovery 自动订阅 END_FILE；`observeRestarts`；`movaObserveFlags(recovery:)` | 404 秒判（约几十 ms）、拒连约 5s；不转发 RESTART，首帧判据不变 |
| N6 | 恢复后清错误/放弃后清 buffering | `MovaRecovered` 后 `state.error==null`；`giveUp` 后 `buffering=false` 并补发 `MovaBufferChange(false)`；加载在途收到的 END_FILE 在 open 返回后立即处理 |
| N7 | `MovaLiveConfig.durationStep`（默认 2s） | 直播 `MovaDurationChange` 节流；0 关闭；首个非零/回落 0/重新 open 放行；点播不变 |
| N8 | `MovaApi.open()` 返回 `Future<bool>` | true=接受；`beforeOpen` 拒绝/被取代/已销毁为 false；失败不算 false；`jumpTo` 被拒不前进下标 |
| N9 | `MovaPipObservable.changes` | PiP 被展开/关闭后 `state.pip` 复位并发 `MovaPipChange`（展开路径与点 X 关闭路径各测，点 X 需想办法注入） |
| N10 | `MovaWarmPlan.rate`、`swapTo(rate:)`、`MovaHandoffRetirable` | 广告方向 1x、回正片恢复广告前倍速（2x/1.5x）；换指后无短暂跑用户倍速窗口；退役引擎 dispose 不复位全局方向；pod 第二条广告真换指 |
| N11 | `MovaPlayerMute` 能力 | 预热/待机静音只改 mpv `mute`，不写系统音量（`dumpsys audio` 对账）；两方叠加任意退出顺序还原 |
| N12 | `MovaState.rendered`、`MovaFirstFrame(sinceOpen, signal)`、`MovaFirstFrameGate` | 每次 open 重置并重发；信号为 `restart`；内部重载不重置；open 同步归零宽高 |
| N13 | `createMovaEngine(preciseFirstFrame:)`、`MovaMpvKernel(observeNativeEvents:/observeRestarts:/lazyVideo:)` | 开关对应的弱客户端数；懒创建 VideoController |
| N14 | `fit` 初值参数、`MovaPlayer(fit:)` | 挂载应用一次，用户按钮改的值不被重建覆盖 |
| N15 | `MovaPlayer(poster:, posterFade:)`、`MovaFeedPlayer(posterUntilFirstFrame:)` | 封面首帧后淡出、换源重盖、仅音频常驻 |
| N16 | `MovaMinimalSkin`、`MovaTheme.bufferingSize/StrokeWidth/Color` | 无手势层无栏；转圈/错误层可选；默认外观不变 |
| N17 | `MovaView`、`MovaSource.sameAs` | 自建/复用/`options` 变化重建/销毁；source 为 null 暂停；`onOpenError`；`alternatives` 参与 sameAs |
| N18 | `MovaAutoPause`/`MovaAutoPauseGate`/`MovaAutoPauseConfig`、`MovaView(autoPause:, routeObservers:)`、`MovaHideReason`/`MovaLiveResume`/`MovaGuardAction` | 滚出视口、`TickerMode`、路由覆盖、进后台；`inactive` 快照意图；PiP/小窗不暂停；直播隐藏 ≥3s 回边缘 |
| N19 | `MovaFailover`、`MovaPlayFailure`、`MovaRecovered`、`MovaSource.alternatives/uris/pick`、`MovaState.sourceIndex`、`MovaRecoveryPolicy`/`MovaFailoverOnly`/`MovaRetryThenFailover` | 重试/切换事件序列；备选只在 recovery 开启时用；卡顿重试后续播到失败前位置 |
| N20 | standby：`MovaHiddenMode.standby`、`MovaStandbyController`、`MovaStandbyConfig`、`MovaStandbyKernel`、`MovaState.standby` | 见 A25/F6 |
| N21 | `MovaSnapshotGuard`（仅 Windows）、`testing.dart` 的 `stagedSourceOptions` | Android 上确认为空操作无副作用 |
| N22 | 0.3.1 小修 | 异步 `beforePlay/beforeSeek` 返回后复查（期间 pause/换源不被覆盖）；手势改配轴向（`horizontal: volume`、`leftVertical: seek`）；`trackCount>0`/`maxZoom>=1` assert；STT `start()` 失败回滚可重试；预览带 crop 不入缓存、换源丢弃旧结果 |
| N23 | 统一上报 QoE 新增：`MovaStatsProbe.nativeRestartAvailable`、`truncatedBelow`、`MovaReportName.custom` | 见 F7 |
