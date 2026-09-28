# CLAUDE.md — mova

在 mova 子工程内工作时的指引。详见 [doc/PRD.md](doc/PRD.md)（需求/决策）、
[doc/SPEC.md](doc/SPEC.md)（架构/实现/命令/验证缺口）、[doc/ROADMAP.md](doc/ROADMAP.md)（里程碑）。

> **换机器接手先读这三条**
>
> 1. **构造 engine 一律用 `createMovaEngine()`**（`lib/src/platform_impl/wiring.dart`，已从
>    barrel 导出），**不要直接 `MovaEngine()`**——后者的平台端口默认是 noop，会导致亮度手势
>    不生效、`enterPip()` 恒 false、全屏不转屏。`MovaEngine()` 保留裸构造只为单测注入假端口。
> 2. **[doc/DESIGN-0.2.0.md](doc/DESIGN-0.2.0.md) 有约 10 处已过期**（阶段 A 落地后未回写：
>    kernel 签名、`MovaState.sourceTitle`、`MovaApi.renderHandle`、`MovaAbrPolicy` 落点、
>    sha1→FNV-1a，以及 4 处为守住 core 纯净性而必须挪到 `platform_impl/` 的结构调整）。
>    **设计意图看 DESIGN，签名与落点一律以代码和 [doc/SPEC.md](doc/SPEC.md) 末节为准。**
> 3. **各阶段的逐 Task 实现计划都在 [doc/plans/](doc/plans/)**，按功能分文件存放，按 Task
>    顺序执行即可。
> 4. **pub.dev 上的已发布版本落后于本仓库 main 分支**：`pub.dev/packages/mova` 当前挂的
>    是 `0.1.0`（2026-09-25 核实，依赖官方 `media_kit`/`media_kit_video`/
>    `media_kit_libs_video`，非本仓库自建瘦身版 libmpv），本地 `pubspec.yaml` 的
>    `version:` 字段也仍是 `0.1.0`——而下文"当前状态"记录的功能（小窗、广告编排、
>    无缝切换、清晰度自适应、仅音频模式等）**已合并进 main 但从未随新版本号重新
>    发布**。引用方从 pub.dev 拿到的包不含这些能力，回答"能不能用某功能"前
>    先确认对方拿到的是 pub.dev 版本还是本仓库 path/git 依赖。

## 是什么

基于 media_kit（libmpv/ffmpeg）的 Flutter 视频播放插件，自研手势与控制层，
支持点播/直播，发布到 pub.dev。属于 `dart-labs` monorepo 的子工程。

## 当前状态（0.2.0）

> **测试基线：815 项全绿**（最后一次明确记录的推进链路是 803→809→811→815，出自
> 「无缝引擎切换」真机排查过程中的多轮修复+回归测试；这是本文档能查证到的最新数字，
> 但距今已有后续改动，**建议以当次 `flutter test` 实跑结果为准重新核实**）、
> `flutter analyze` 0 issues（仅剩一条既有 `feed_player.dart` 警告，与近期改动均无关）。

以下按功能分组呈现已完成能力（原按 0.2.0–0.6.0 版本号分阶段记录，现已合并，
版本号统一记为 0.2.0；具体日期/commit/测试数字均为客观事实，原样保留）。

### core/ui 分层重构

功能与最初版本保持一致（零可见变化），架构重写为 `MovaApi`/`MovaEngine`（取代
`MovaCtrl`，后者已 `@Deprecated`）+ `MovaKernel` 内核抽象 + 组件树/皮肤/补丁
（`MovaComponent`/`MovaSkin`/`MovaDefaultSkin`/`MovaPatch`）+ 文案与主题外置
（`MovaStrs`/`MovaTheme`，经 `MovaOpts` 注入）+ 拦截点（`MovaHook`）。

### 拖动预览缩略图

`MovaApi.preview`/`MovaOpts.preview`/`MovaPreviewBlock` 三个新公开面，WebVTT 雪碧图 +
libmpv 抽帧兜底的有序来源链，内存+磁盘两级缓存，`connectivity_plus` 网络策略，
`PreviewComponent` 气泡（水平位置随拖动比例跟随）。已完成（2026-07-31），计划与实测
结论见 [doc/plans/2026-07-31-phase-b-preview.md](doc/plans/2026-07-31-phase-b-preview.md)
（15 Task 全部完成，附录 A/B 记录实测结论与真机验证结果）。

### 直播时移

`MovaLiveConfig` 新增 `urlBuilder`/`backToLive`/`autoBackToLiveOnStall`/`windowResolver`；
`lib/src/core/live/timeshift.dart` 纯函数 `resolveWindow`/`behindOf`/`atLiveEdge`；
`MovaState.timeshiftBehind` 真正写入并伴随 `MovaTimeShiftChange`/`MovaLiveEdgeReach` 事件；
`backToLiveEdge()` 从占位（`reload()`）变为按策略执行；新增 `MovaApi.pipSupported`/
`MovaState.pipSupported`，PiP 按钮在不支持的平台自动隐藏；直播底栏加
`seekBar`/`timeshift`/`backToLive`（原 `backToEdge` 已改名删除）。已完成（2026-07-31），
计划见 [doc/plans/2026-07-31-phase-c-timeshift.md](doc/plans/2026-07-31-phase-c-timeshift.md)
（Task 1–9 全部完成）。iOS podspec 元数据已对齐 pubspec（注意版本号需手动同步）、
example 已加直播/时移两个 demo（仅桌面冒烟，未做交互验证）。**真机验证部分完成**
（2026-09-23，STG AL00 arm64 Android 12）：HLS 联网切档——加载后事件序列出现两次独立
`MovaSizeChange`（伴随 `MovaBufferChange`/`MovaDurationChange`/`MovaReady`），符合分辨率
切换的真实信号，确认真实发生；Android PiP——`engine.pipSupported = true`、
`enterPip() = true`，触发后收到 `MovaPipChange` 事件，`adb shell dumpsys activity` 确认
`mIsInPictureInPictureMode=true`、`mWindowingMode=pinned`，**真机确认真实生效**。
**仍未测**：手势手感（左亮度/右音量的实际触感，主观）、直播/时移 UI 交互、iOS 整体
（历次只有 Android 设备）。

### UI 插件化

把组件树/皮肤/补丁沉淀为 **Plugin / Component / Skin** 三层契约——`MovaPlugin` 能力
mixin（`api` + `bind()`，`ui/scope/plugin.dart`）、组件树静态化（`MovaSkin.components()`
无参，VOD/直播底栏合并为自适应 `BottomBarComponent`，`live_bar.dart` 已删）、
`MovaDefaultSkin.assemble` 拆为可覆写三层（`buildPlaybackLayer`/`buildOperableLayer`/
`buildPersistentLayer`）、`MovaSlot` 加 `left`/`right`。**手势侧别→动作改配**：
`MovaGestureConfig` 用 `MovaGestureAction` 映射，默认翻转为左亮度/右音量（对齐主流）。
设计见 [doc/DESIGN-0.3.0-plugin-skin.md](doc/DESIGN-0.3.0-plugin-skin.md)。后续增量：
系统音量端口 `MovaVolumePort`、强制横竖屏 `MovaApi.setOrientation`
（`MovaOrientation{auto,portrait,landscape}` + 顶栏仅移动端的 `orientationButton`，独立于
全屏；`auto` 保持按宽高比定向）。**横竖屏按钮真机仍未验证**（手势/音量/亮度线已在
Android 真机过；方向按钮与 PiP/直播/时移 UI 等仍未系统走真机）。

### 无缝引擎切换（默认关闭）

新增 `MovaSwapEngine`（`lib/src/core/swap/`）——一个本身实现 `MovaApi` 的代理，持有生效
引擎 + 短暂预热中的影子引擎，就绪后原子换指，把"广告播完回正片"从黑屏/loading 变成
逐帧无缝。`MovaOpts.swap`（`MovaSwapConfig`）默认 `enabled: false`，关闭时是纯直通代理，
行为与关闭前逐字节一致。预热拆成两层可插拔纯逻辑：触发策略 `MovaWarmTrigger`
（`MovaLeadWarm`/`MovaEagerWarm`）与就绪判据 `MovaWarmPolicy`（`MovaBufferWarm`，
`MovaBufferAbr` 的镜像）。新增 `MovaState.renderEpoch`（普通引擎恒 0，仅切换后递增，
触发渲染面重读 `renderHandle`）。`MovaAdController` 接了可选 `swap` 参数即可接入；
清晰度切换（`switchQuality`）后续已真正接入（见下）；feed 引擎池结构性不适用本模型，
明确排除。计划见 [doc/plans/2026-09-16-seamless-swap.md](doc/plans/2026-09-16-seamless-swap.md)。

**真机验证（Task 11，STG AL00 arm64 Android 12）**：
- 2026-09-23：用 `main_seamless_test.dart` 实测 skip 触发后 `renderEpoch` 1→2 确认切换
  机制真实生效；广告→正片切换间隔（skip 调用到 renderEpoch 落地，基于真实事件戳）= 806ms。
- 2026-09-24（`example/lib/main_seamless_swap_verify.dart`，未提交）：**中插续播点误差
  ——首次测量方向搞反了，已定位真实根因并修复**：`MovaAdController._warmContentBehindAd`
  用默认 `MovaWarmPlan`（`pauseWhenReady: false`），影子引擎以 `autoPlay: true` 按真实
  时间一路播，commit 时已漂移整个广告剩余时长——真机实测续播目标 6006ms、实际落点
  8842ms（偏差 +2836ms 偏晚）。同一机制在 content→ad 方向也在漏：`_holdAtTarget`
  对目标为 0 的情形跳过回绕，导致广告缺头约 300ms。**已修复**：`_warmContentBehindAd`
  显式传 `MovaWarmPlan(pauseWhenReady: true)`；`_holdAtTarget` 的回绕守卫从
  `_warmAt > 0` 改成 `!_warmLive`（直播源仍不 seek）。测试从 803 推进到 809。
  真机复测（`example/lib/main_resume_accuracy_verify.dart`，未提交）：修复前
  6006ms→8842ms（+2836ms）；修复后两次采样 5964ms→6006ms（+42ms）、5630ms→5672ms
  （+42ms）。顺带加固：`MovaEngine.open()` 同步重置 `state.duration`/`_lastPosition`/
  `_lastBuffer` 为 0，把"寄存还是直发"判据从隐性竞态变确定性；顺带修掉复用引擎播放
  新源时上一条素材 position 漏进新源第一个 `MovaProg` 的真 bug。测试从 809 推进到 811。
  **排查中顺带发现并修复第二个真 bug**：`MovaEngine.switchQuality` 此前无条件直接打
  内核、绕开寄存机制，会被 mpv 丢弃并卡死播放器。**已修复**：抽出共享 helper
  `_seekOrPark`/`_forgetMediaProgress`，`switchQuality` 换档续播 seek 走同一套安全保证。
  真机验证（真实多码率 HLS `https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8`）：
  修复前裸 `_kernel.seek()` 被 mpv 静默丢弃、position 归零重播；修复后续播误差
  66–166ms。顺带修复 ABR 与换档背靠背触发导致续播 seek 被冲掉的问题（`switchQuality`
  补 `_abrPolicy.reset()`），ABR 开启态真机复测续播误差 66–117ms。新增 4 项回归，
  测试从 811 推进到 815。
- 短广告降级路径——PASS：预热窗口压到 300ms、广告仅持有 250ms 即 `skip()`，未见卡死，
  `renderEpoch` 仍成功递增。
- 断网预热超时兜底——PASS：广告播放中真实断网，等过 `readyTimeout=5s` 后 `skip()`，
  未卡死，走非无缝路径正常完成续播。
- 内存/解码 session 三阶段采样——方法论问题已解决（独立进程测量），**结论：不是内存
  泄漏**：`example/lib/main_swap_leak_probe.dart` 8 轮插播/skip/切回，逐轮增量
  −0.25~+0.77MiB（噪声量级，非线性累加）；`dumpsys meminfo` 显示 Native Heap 首轮峰值
  53.0MB、第 2 轮起稳定 39.5–41.0MB；EGL mtrack 全程恒定，纹理泄漏路径可排除。真实现象
  是"第 1-2 轮一次性抬升约 35MiB 后进入平台"（native 分配器高水位一次性推高，非累积
  泄漏），代码层面 `MovaSwapEngine._commitNow()` 所有分支均正确 dispose 旧引擎。
- 广告黑屏是否真的消除、画面是否跳变——已实测确认（2026-09-25）：`adb shell screencap`
  连续抓帧 + logcat 事件时间戳对齐（约 250–330ms 一帧），**未观察到黑屏帧**、**未见
  撕裂/跳变**（受限于采样间隔，不能做逐 ms 级穷尽证明，但已是当前工具条件下能拿到的
  最强客观证据）。**音频跳变仍实测不了**（该设备无可用音频采集路径）。

### 仅音频模式（`audioOnly`，默认关闭）

`MpvKernel`/`MovaEngine`/`createMovaEngine()` 新增 `bool audioOnly = false` 构造参数。
为 `true` 时完全跳过 `VideoController` 的创建——media_kit 的 `Player` 默认就是 mpv 的
`--vid=no`，只有 `VideoController.create()` 会把它改回 `vid=auto`，因此不挂接它就等于
让 libmpv 只解音频：解码帧缓冲/GPU 纹理/Flutter `Texture` 注册三项是 0 而非变小。
`createMovaEngine()` 在此模式下也不再默认注入 `MpvFrameExtractor`。`MovaKernel.
renderHandle` 由 `Object` 放宽为 `Object?`。不新增任何公开类、barrel 一行未改、UI 层
零改动。`audioOnly` 刻意不进 `MovaOpts`（构造期资源决策），也不加 `MovaStreamType.audio`
（与流类型正交）。计划见 [doc/plans/2026-09-16-audio-only.md](doc/plans/2026-09-16-audio-only.md)。

**真机验证（Task 5，STG AL00 arm64 Android 12）**：
- 桌面端（`ProcessInfo.currentRss`）：播放期内存增量视频 197 MiB vs 音频 96 MiB，
  省约 101 MiB、约 2.05×；`audioOnly` 下 `MovaState.size` 为 `0x0`、`renderHandle` 为
  `null`。数据见 [doc/notes/2026-09-16-audio-only-feasibility.md](doc/notes/2026-09-16-audio-only-feasibility.md) §1.5。
- 2026-09-23 三阶段内存对账（两次独立运行）：video baseline 108.89→playing 156.73
  （+47.84）→disposed 155.63 MiB，audio baseline 99.45→playing 117.18（+17.73）→
  disposed 121.73 MiB，真机播放期增量比约 2.7×（桌面约 2.05×，量级一致、真机差距
  更大）。dispose 后内存几乎未回落——不能排除泄漏，也非直接证据。
- 2026-09-25 追加验证（`example/lib/main_audio_only_round2_verify.dart`，未提交）：
  带视频轨源在 audioOnly 下确认只出声不出画（`playing=true`、`renderHandle=null`、
  `size=0x0`）；`dumpsys meminfo` 分栏对账（单点）TOTAL PSS≈112MiB，EGL/Graphics 占比
  最大；电量/CPU 粗量级抽查（CPU 58.0%，样本时间太短未积累出电量数字）；连播 6 轮
  内存爬升——playing 首末 +3.50MiB、disposed 首末 +5.25MiB，无单调爬升趋势，6 轮样本内
  未见明显泄漏迹象；关闭态（`audioOnly:false`）回归确认零改变。`example/lib/
  perf_probe_audio_only.dart` 两处探针缺陷已修复（`print()` 替代 `stdout.writeln`；
  `String.fromEnvironment` 编译期常量替代运行时 `Platform.environment`，此前
  Android 上模式切换从未真正生效）。
另：`MovaAudioSkin`（封面/歌词/波形专用皮肤）**明确不做**，当前用 `MovaPlayer.surface`
已够。

### 广告编排增强（默认关闭/默认不改变行为）

把 `MovaAdController` 从"能按排期播广告"推进到"能按广告业务的真实时序播广告"——
正片源延迟解析（`loadDeferred`/`contentError`）、广告位 `duration`/`delay` 与素材
时间轴解耦（一律 `Timer` 驱动，绝不碰 `state.duration`/尾部 seek）、按广告位类型决定
是否等待就绪（`MovaAdWaitByKind` 默认 pre 否 / **mid 是** / post 否，三层覆盖收在
`MovaAdConfig.waitsFor()` 一处）、加载失败兜底（`MovaAdFailPolicy`）、以及
`MovaWarmPlan`（给 `prepare` 加可选具名参数，让同一个 `MovaSwapEngine` 服务两个预热
方向）。不新建任何预热机制，三个既有抽象零类型改动直接复用。控制器新增第四态
`_Phase.pending`。顺带修掉三处潜伏缺陷（注入判据从不 `reset()`、`at==0` 仍下发无谓
`seek(0)`、影子 `MovaErrorEvent` 无人监听）与"中插 pod 根本没串联、会闪回正片"。
等待要生效还需宿主接了 `swap` 且 `MovaSwapConfig.enabled` 为 true，两者默认都是关的。
计划见 [doc/plans/2026-09-16-ad-swap-enhancements.md](doc/plans/2026-09-16-ad-swap-enhancements.md)。

**真机验证（Task 12，STG AL00 arm64 Android 12）**：
- 2026-09-23：前贴片默认不等待路径正常播完、swap ready→ad completed→swap idle 事件
  全部触发；失败降级——中插换坏地址后 15.94s 触发加载、16.05s 即失败，确认真机上坏
  URL 走 openThrew（`open()` 直接失败），非 playerError，正片自动无缝续播、未见卡死；
  同一广告位失败事件只触发一次、未见重复弹出。
- 2026-09-24（`example/lib/main_ad_orchestration_verify.dart`，未提交）：A 组——中插
  "等待就绪"从 `pending` 到 `started` 的事件时间戳差，5 次采样 min=1310ms,
  max=1993ms, avg=1599ms；澄清：这段等待期间**不是黑屏**，正片持续正常播放、广告在
  影子引擎里静默预热。E 组——`duration=5000ms` 场景下 `started`→`completed` 实测间隔
  5013ms（误差仅 13ms），PASS。F 组——关闭态（`MovaAdConfig.enabled=false`+
  `MovaSwapConfig.enabled=false`）8 秒观察窗内 `adEventsFired=0`、`renderEpoch` 恒为
  0，PASS。C 组（倒计时期间正片流畅度）已查清并 PASS：`pending`→`started` 实测
  3050ms（与理论值 3000ms 吻合），期间 position 平滑推进、`buffering` 全程 `false`；
  此前一轮 `SUSPECT STALL` 是测试判据缺陷（把广告 `started` 时刻的合法 position 重置
  误判成卡顿），已定位，产品行为正常。

### App 内小窗（`MovaMini`，默认关闭）

不依赖任何系统 PiP API，让画面从页面里"缩"成一个可拖拽的悬浮小窗——不重新解码、不
黑屏。默认关闭（`MovaMiniConfig.enabled` 为 `false`）。两种挂载方式并存：方式 A 页内
悬浮（`MovaMiniController.showInPage`，mova 实现 `OverlayEntry` 插入）、方式 B 跨路由
持久（`MovaMiniController.show` + `MovaMiniHost` 便利壳）。核心逻辑收在挂载无关的
`MovaMiniWindow` 一处（自身是撑满外部约束的 `Stack`，两种外壳只是"放到哪里"的差异）。
core 层仅加 `MovaState.mini`/`MovaApi.setMini`/`MovaMiniChange`/`MovaMiniConfig`/
`core/mini/placement.dart` 五处，播放链路一行不动。计划见
[doc/plans/2026-09-23-app-inline-pip-overlay.md](doc/plans/2026-09-23-app-inline-pip-overlay.md)、
[doc/SPEC.md](doc/SPEC.md)「App 内小窗（MovaMini）」一节（该文件被系统进程持续锁定
写入失败，结论暂未同步进去，待解锁后补）。

**真机验证已完成（Task 12，Windows 桌面 + Android 真机）**：
- 2026-09-24（Windows 桌面，`--no-enable-impeller` 强制 Skia 后端）用户手工走完 A–F
  六组，均目测通过：A 组不重新解码——位置连续、交接无跳变（未记录具体
  `position`/`renderEpoch` 数值，只是目测确认，不满足项目"基于真实事件数字"的验证
  约定）；B 组交接无黑帧、音频不中断；C 组页内小窗滚动零漂移、跨路由两层小窗全程
  最上层持续播放、方式 A/B 互斥；D 组拖动跟手、吸边正常、甩动无误触发关闭；E 组
  debug assert 正确触发并被捕获上报，未发生原生崩溃；F 组既有 demo 无回归。
- 同日 Android 真机（STG AL00）补测 C 组三项专属项，**发现并修复一个真实 bug**：
  ① **转屏钳回——发现真实 bug，已修复**：连续横竖屏切换后小窗从贴住的角落逐渐"走位"，
  根因是原逻辑对 bounds 变化只做 `clampToBounds`（合法性钳制，不保证相对位置），转屏
  导致 bounds 宽高互换时旧的绝对 left/top 不再对应原视觉位置。已加
  `core/mini/placement.dart` 的 `remapProportionally` 纯函数（按旧 bounds 里的相对
  比例重新映射到新 bounds，再钳制兜底），新增 3 项单测，复测确认转屏后稳定贴住原
  角落附近。② **与系统 PiP 互斥——真机确认通过**：小窗态下触发 `enterPip()`，先
  `setMini(false)` 收起小窗再进系统 PiP，未叠加/花屏。③ **切后台再回前台——播放会
  自动暂停，需手动点续播**：排查确认这不是 mini window 引入的 bug，是 Android 系统级
  行为（切后台 GPU 渲染 Surface 被回收，libmpv 检测到 surface 丢失自动暂停），全屏
  播放切后台同样会暂停，非小窗特有——若要"前后台自动续播"需单独立项评估。
  顺带修复一个 demo 自身次生 bug：`_MisuseDemoState` 触发 assert 后若同一帧内又导航
  到别的入口，新引擎事件流回调会在 widget 树锁定期间同步刷新，已改为
  `addPostFrameCallback` 推迟通知。

## 剩余任务

**瘦身版 libmpv 独立包发布——Android/Windows 已落地并验证，iOS/macOS 结构已落地但完全
未验证（没有 Mac，不能算完成），每次启动请提醒用户此项仍有待实现的计划**：
`packages/media_kit_libs_ios_video_slim`/`_macos_video_slim` 是在没有 Xcode 工具链
（`otool`/`install_name_tool`/`xcodebuild`/`lipo`）的 Windows 机器上手工拼装的
`Mpv.xcframework`（直接拷贝 `libmpv.dylib`，未做任何二进制层面改写），从未跑过
`pod install`，`example/pubspec.yaml` 也**没有**加上这两个 override——**不要把这两个
fork 包当成已验证可用，上线前必须在 Mac 上补跑 `pod install`+真机验证**，详见
[doc/plans/2026-09-25-libmpv-pub-package.md](doc/plans/2026-09-25-libmpv-pub-package.md)
「Darwin（iOS/macOS）同名替换设计」一节的"已知未验证项"清单。2026-09-28 落地方案是
"同名整包替换 + `dependency_overrides`"（拓扑 B）——**Android 已完成**：新建
`packages/media_kit_libs_android_video_slim`（同名 fork `media_kit_libs_android_video`，
含 mova-libmpv 自建四架构 `libmpv.so` + 从官方 release jar 逐字节提取的
`libmediakitandroidhelper.so`，2026-09-28 更新），`example/pubspec.yaml` 用
`dependency_overrides` 把 `media_kit_libs_android_video` 整体指向这个 fork 包，官方包
完全退出依赖图（不需要 pickFirst）。APK 内 `.so` sha256 与 `libmpv/<abi>/` 逐字节一致
（arm64-v8a/armeabi-v7a/x86_64/x86 均已验证），关闭 override 可干净回退官方（体积精确
等于官方 12,369,680 字节）。Windows 早已用同一思路落地（`media_kit_libs_windows_video_slim`）。
iOS/macOS 机制上同样可行（读了 `media_kit_video` 的 `media_kit_utils.rb` 确认同名替换
不受"多 pod 共存"限制），但需要新增"裸 `libmpv.dylib` 包装成 `Mpv.xcframework`"这一步
打包工作，**没有 Mac 无法验证**，与「iOS PiP」共用同一道门槛，设计草案见
[doc/plans/2026-09-25-libmpv-pub-package.md](doc/plans/2026-09-25-libmpv-pub-package.md)
决策 6。**原计划书里"发布到 pub.dev 独立包 + LGPL 合规四件套"那条路线用户已不再采纳**
（该路线出自 2026-09-25 的初版规划，取代更早的"构建时自动下载"方向，已否决，仅供参考
现状调研部分），该计划文档里的 Task 1–9（pub.dev 发布流水线、LGPL 合规四件套）视为
废弃，仅决策 0/2/4（拓扑判断、默认值方向、三个切换开关的设计思路）仍有参考价值——
**因为发布到 pub.dev 才会触发 LGPL 公开分发义务，同名替换走 `dependency_overrides`
（path/git）不经过 pub.dev，不受此约束**。

**四架构 libmpv/ffmpeg 瘦身构建——已全部构建完成，avfilter 真机验证（SRT 字幕 + OSD）
已完成，mov_text/ASS/WebVTT 与音量均衡仍待办**：
自建 libmpv/ffmpeg 裁剪 demuxer/decoder，替换 `media_kit_libs_video`；构建卡 LGPL，
避开 GPL-only 组件。**Android 四架构均已构建完成并核实为真实产出**（`libmpv/` 下
arm64-v8a 6.05MB、armeabi-v7a 5.68MB、x86 6.19MB、x86_64 7.73MB，对应 commit
`83633e4`/`cea74e1`/`8750b1e`/`8898ced`，2026-09-25 左右）；2026-08-06 首次在 WSL2 上
跑通完整构建链时，arm64-v8a 从 media_kit 现状 11.80MiB 压到 6.61MiB（省 44%）——依次
叠加格式裁剪（去 VP8/VP9 软解）+ 编译器/链接器手段（`gc-sections`/`-Os`/
`-fvisibility=hidden`/跨库 LTO/去 avfilter），逐项都有实测数字。核验通过 MediaCodec
硬解 JavaVM 绑定符号（`mpv_lavc_set_java_vm`）、VP9 硬解符号。构建配方（flavor 脚本、
buildscripts 补丁、CI）在独立子工程 [../mova-libmpv/README.md](../mova-libmpv/README.md)
（"⭐ 2026-08-06 定稿结果"一节）；构建产物落在本工程 [libmpv/](libmpv/)（按平台分
目录）。mpv 构建选项完整盘点见
[../mova-libmpv/doc/notes/2026-07-31-libmpv-slimming-options.md](../mova-libmpv/doc/notes/2026-07-31-libmpv-slimming-options.md)，
ffmpeg 格式范围盘点见
[../mova-libmpv/doc/notes/2026-07-31-ffmpeg-slimming-options.md](../mova-libmpv/doc/notes/2026-07-31-ffmpeg-slimming-options.md)。
**① 去掉 avfilter（`overlay`/`equalizer`）的真机播放验证——已完成（2026-09-28，
STG-AL00）**：字幕合成（libass）与 OSD 叠加均 PASS，音量均衡因 mova 产品层压根没有
调用路径（已 grep 确认）而是代码审查排除、非播放验证。**字幕四种格式（SRT/ASS/WebVTT
外挂 + mov_text 内封）已于 2026-09-28 同批补测完成，全部 PASS**（ASS/WebVTT 走
`sub-add` 与 SRT 同一路径；mov_text 不需 `sub-add`，容器自带字幕轨，`open()` 后
`track-list` 有一次性查询到空数组 `[]` 的时序现象，但紧接着 `set_property('sid','1')`
仍生效、字幕正常渲染）。详细实测数字（pos 时间戳命中窗口、
sub-text 轮询证据、截图路径）见
[../mova-libmpv/README.md](../mova-libmpv/README.md)「真机测试（进行中）」一节。
`--disable-runtime-cpudetect` 这类 arm64 专属优化仍未验证能否照搬到其余架构；② 历史 Windows
spike 数据（ffmpeg 单独 6.26MB，省 79%）已被 Android 真机数据取代，仅供参考，见
[../mova-libmpv/doc/plans/2026-07-31-ffmpeg-slim-build-windows.md](../mova-libmpv/doc/plans/2026-07-31-ffmpeg-slim-build-windows.md)。
**字幕相关选项（libass/subrandr/uchardet）明确保留待定，不要关**——用户认为 mpv
原生字幕渲染可能有用，等瘦身构建实测出体积数字后再权衡（与
[doc/notes/2026-07-31-stt-subtitle-feasibility.md](doc/notes/2026-07-31-stt-subtitle-feasibility.md)
的"Flutter 侧字幕组件 vs mpv 原生渲染"架构决策一并拍板）。**顺带待办**：自建时可直接
导出一个轻量 FFI 抽帧函数（如 `vm_extract_thumbnail(uri, atMs, width) -> jpegBytes`，
内部走 `libavformat`+`libswscale`），替换现有"开一个完整隐藏 `Player` 抽帧"的重量级
方案（受限于 mpv `screenshot()` 不支持缩放，见
[doc/plans/2026-07-31-phase-b-preview.md](doc/plans/2026-07-31-phase-b-preview.md) 附录 A）。

**libmpv 瘦身产物接入 mova 实际构建——Android/Windows 已完成，iOS 未接线**：
- **Android**：接入方式已从"Gradle `syncMovaLibmpv` task 做 jniLibs 拷贝"升级为
  **fork 包整体替换**（`build.gradle.kts` 里原来的 `syncMovaLibmpv` task 已不存在）：
  `packages/media_kit_libs_android_video_slim/`（内置四架构 `libmpv.so` +
  `libmediakitandroidhelper.so`，2026-09-28 更新），`example/pubspec.yaml` 用
  `dependency_overrides` 把 `media_kit_libs_android_video` 整体指向这个 fork 包，官方
  包完全退出依赖图。已验证 APK 内 `.so` sha256 与 `libmpv/<abi>/` 逐字节一致。**此条
  已完成**（详见上文"瘦身版 libmpv 独立包发布"）。
- **Windows（2026-09-24 确认，随「真机播放验证」一起落地）**：`example/pubspec.yaml`
  用 `dependency_overrides` 把 `media_kit_libs_windows_video` 指到本地 fork 包
  `packages/media_kit_libs_windows_video_slim`。该 fork 的 `windows/CMakeLists.txt`
  跳过官方 7z 下载，直接指向 `libmpv/windows-x86_64/libmpv-2.dll`（mova-libmpv CI
  产出的自研瘦身版），并从 `windows-devlib/libmpv.dll.a`（用 `gendef`+`dlltool` 针对
  该 dll 导出表手工生成，dll 换版本要重新生成）+ `mpv-headers/*.h` 拼出
  `media_kit_video` 链接期需要的目录结构。真机验证（`flutter run -d windows` 画面+
  声音正常）用的就是这条链路，是真实生效的接线。
- **iOS 尚未接线**（podspec 还没引用 `dist/darwin/` 产物，留待 iOS PiP/真机验证一起
  处理时再补）。

**libmpv 瘦身产物的 CI/git 集成——2026-09-17 全平台 CI 首次全绿**（8/8 job，含此前
一直失败的 Android x86——根因是共享 build 缓存跨架构污染导致 meson 复用 stale 配置
构建出静态库，已修复）。**同日追加 Windows/Linux 的编译器级瘦身**（Windows 14.66→
13.41 MiB −8.5%，Linux 8,189,568→7,550,784 字节 −7.8%，均为 `-Os` 级别；`-Oz` 在
Windows 上本地测出 −11.2% 但 CI 复现失败，已回退）。**iOS 已于同日追加完成**：先复用
`media-kit/libmpv-darwin-build` 的默认 flavor 拿到第一次真实全绿（18.48MiB/18 个独立
dylib），再叠加 mova 自己的 `movaslim` flavor（`mova-libmpv/libmpv-darwin-build-mova-
slim.patch`，decoder/demuxer 裁剪 + securetransport 替 mbedtls）降到 10.76MiB/13 个
文件，最后把 ffmpeg/dav1d/freetype/fribidi/harfbuzz/libpng/libass 全部改成静态链接进
单一 `libmpv.dylib`（跟 Android 同一种"单文件"形态才可比）+ 编译器级瘦身，CI 实测
7,489,408 字节 ≈7.14MiB，仅比 Android 的 6.52MiB 高约 9.5%。**再叠加 audio/protocol
白名单收窄**后，**当前记录：CI 实测 6,534,448 字节 ≈6.23MiB，反超 Android 的 6.52MiB
约 4.4%**。静态化过程连环踩坑（5 层 pkg-config `Requires:` 传递依赖、libtool
`ar`/`ranlib` 被替换成 `false`、meson `-Dc_args=` 会替换而非追加 cross-file 的
`-arch`/`-isysroot` 导致 libpng 头文件检测失败）详见 `mova-libmpv/README.md`「多平台
进度」表 iOS 那一行的完整记录。macOS/其余平台仍是 upstream 默认 flavor 未裁剪，是
独立于本轮的更大工作量。

为了让"随包发布"（构建产物随仓库/包直接分发，不做构建时下载，理由是内网构建环境不
应该依赖运行时联网下载）不至于把 `.git` 历史撑爆，拍板方案是 **Git LFS**：已在独立
临时 clone 里用 `git filter-repo` 把 `mova/tools/ffmpeg-slim/dist/` 从 main 的全部
历史里剥离（`.git` 898M→68M），重新用 `.gitattributes` + `git lfs track` 接管当前
`dist/` 内容并 force push（GitHub 与 codeup 两个远程均已完成、历史一致、都在 LFS
之下）。pre-push 钩子已手动合并进 lefthook。

**CI 的"提交产物回 dist/"重试逻辑——三个连环 bug，均已修复（2026-09-17）**：
a) rebase-on-dirty-tree：改成"每次重试先 `fetch + reset --hard origin/main` 拿干净
基线"；b) LFS 内容从未真正上传（`actions/checkout` 不装 LFS 钩子，五个 job 原先只推了
LFS 指针提交），修复：commit 后、push 前显式插入 `git lfs push origin main`；c) windows
job 因 `shell: msys2 {0}` 的 PATH 不含 `git-lfs.exe` 导致 pre-push 报错，修复：该步骤
单独覆盖成 `shell: bash`。三处改动都在 `.github/workflows/build-mova-libmpv.yml`。
**已过真实 CI 验证**（run 35172861864：8 个 job 里 7 个绿；唯一失败的 Android x86
是共享 `deps` 缓存跨架构污染导致 meson 复用 stale 配置构建出静态库，已在
`build.sh` 调用前先删掉架构专属的 mpv `_build-<suffix>` 目录修复，commit
`fe6a8c8`）。**截至 2026-09-24（run 35948800700）全部 10 个平台/架构 job 已连续多轮
保持全绿**，x86 产出真实 `libmpv.so`（6,190,732 字节），已随该轮同步进 jniLibs。

**⚠️ 运维踩坑记录（2026-09-17）——`git lfs push --object-id origin` 在双 push-url
remote 下不可靠**：本仓库 `origin` 同时配置了 codeup（fetch+push）与 GitHub
（仅 push）两个 push URL。手工补传缺失 LFS 对象时只会实际传到其中一个端点（报告
全部成功但另一端仍可能 404）。CI 五个 job 各自只 push 到 GitHub，所以**每次 CI 重建
产物后，codeup 端总会比 GitHub 缺新对象**——需手动从 GitHub 拉真实内容、再显式推到
一个单独指向 codeup 的 remote（不要用 `origin`）才能补齐。**验证方法**：
`git clone --branch main --single-branch <url> <tmpdir>` 全新 clone 一次，比对
`dist/*/*` 每个文件的字节数，这是唯一可靠的验证手段——`git lfs pull` 在本地已有
`.git/lfs/objects/` 缓存时会掩盖远端缺失对象的问题。

**Windows 真机播放中途 libmpv 原生崩溃——已解决（用户 2026-09-24 拍板标记解决，
规避手段：`--no-enable-impeller` 强制走 Skia 后端）**。注意这是**规避手段而非
调用栈级根因**（未拿到带符号 dll + 崩溃转储做最终确认，样本量也只有 3 次以上
未复现），后续如复现请先怀疑 Impeller 相关改动或 Flutter 升级带来的默认值变化。
`mini_window_demo` 在播放中途（非引擎刚创建时）触发
`0xc0000005` 访问越界，故障模块是自研瘦身版 `libmpv-2.dll`，Windows 事件日志三次复现
故障偏移完全一致（`libmpv-2.dll+0x94d927`）。已排除：不是已用 clang 修复的
`mpv_create()` 崩溃（位置、时机都不同，且已确认 CI 产物确实是 clang 编译）、不是网络
流本身、不是小尺寸渲染面、不是 `createMovaEngine()`/`MovaPlayer` 封装本身、不是
`showInPage()` 挂载动作本身、不是 `MovaMiniController.show()`+`Navigator.pop()` 的路由转场
竞态——这几种场景自动化复现均不崩，**崩溃似乎只在真人鼠标/拖拽交互下触发**。故障地址
落在静态链接的 ffmpeg/libav 内部（非 mpv 导出符号区间），dll 无调试符号，反汇编看不出
函数名。**新发现**：Flutter 3.47 起 Windows 桌面端 Impeller 已非纯 opt-in（`--no-
enable-impeller` 是真实变量切换，不是空操作），用该参数强制走 legacy Skia 后端启动
demo 后，同样的"播放中途+真人拖拽"场景连续 3 次以上未复现崩溃（此前是 100% 必现）——
指向 libmpv 的 GPU 纹理/渲染句柄与 Impeller（可能是其 ANGLE/D3D 层）交互时的资源竞争
或生命周期问题，但**尚未确认是否 100% 规避**（样本量仍小）、**尚未定位到具体触发
机制**（仍需带符号 dll + 崩溃转储配合 cdb/gdb 拿真实调用栈）。已配置
`HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\mova_example.exe`
收集转储到 `_crash_dumps/`（本轮未复现崩溃故未拿到 `.dmp`，配置仍保留）。详见
[doc/SPEC.md](doc/SPEC.md)「App 内小窗（MovaMini）」一节的详细排查记录。
**注意区分**：`_MisuseDemo` 页面故意触发的 debug assert 会导致窗口无声消失但
**没有**崩溃弹窗/事件日志/原生故障——那是另一个已在 demo 里修复的问题
（`_engine.dispose()` 缺 `catchError`），不要和这个原生崩溃混为一谈。

**承自 fvideo（改名前）的遗留任务**——mova 就是 fvideo，遗留任务全部承接：

1. **iOS PiP 未实现——待定任务，每次启动请提醒用户此项未完成**：当前返回不支持
   （libmpv 纹理限制）。**可行性已调研,方向定为 `AVSampleBufferDisplayLayer` +
   `CVPixelBuffer`**（Android 是 Activity 级 PiP、无需取帧；iOS 必须自渲染取帧）；
   落地卡在一次**需 Mac + iOS 15+ 真机**的门槛 spike。研究 + 落地计划 + 渲染机制/性能
   澄清见 [doc/notes/2026-07-31-ios-pip-feasibility.md](doc/notes/2026-07-31-ios-pip-feasibility.md)。
   不需 Mac 也能先做的：跨平台"应用内悬浮窗"降级方案（已用 `MovaMini` 落地）。
2. **实时语音转文字字幕——可行性 + 音频抽取 spike + 动态加载调研均已完成；方向 2026-08-01
   倾向 whisper.cpp，待用户确认依赖后拆 Task**：方向是**各平台原生轻量抽取 API**（Android
   `MediaExtractor`+`MediaCodec`、iOS `AVAssetReader`）+ **平台原生 STT**（Android
   ML Kit / iOS `SFSpeechAudioBufferRecognitionRequest`，均系统自带、走原生插件代码，
   不算新依赖）+ 字幕叠层组件；PCM 抽取与 STT 调用同一次原生方法内完成，不过 Dart 侧。
   spike 验证过"起第二个 media_kit `Player` 用 `Media(start:,end:)` 分块"技术上可行，
   但双播放器 CPU/内存翻倍，**已否决**，改走上述原生 API 路线。曾建议默认依赖
   whisper.cpp，已推翻；曾评估 MCP 兜底转写，**已否决**（请求/响应协议非实时流式、
   延迟不可控，且与 MCP 钩子"被动暴露上下文"的本职冲突）——缺口复用既有
   `MovaVolumePort`/`CallbackVolumePort` 的注入模式给宿主一个通用 `MovaSttEngine` 口子
   即可，不专门补 MCP。完整调研 + spike 实测数据见
   [doc/notes/2026-07-31-stt-subtitle-feasibility.md](doc/notes/2026-07-31-stt-subtitle-feasibility.md)
   附录 A，回写见 [doc/PRD.md](doc/PRD.md) ADR。**macOS（无原生插件，需从零搭建）与
   Windows（SAPI/COM，无项目内先例）暂缓**，逐 Task 落地计划见 `doc/plans/`。AI MCP
   接入钩子（被动暴露上下文/接受指令，与字幕转写解耦）仍是纯架构预留，未评估、未排期。
   **⚠️ 2026-08-01 方向调整（覆盖上文"平台原生优先"）**：动态加载调研
   [doc/notes/2026-08-01-dynamic-loading.md](doc/notes/2026-08-01-dynamic-loading.md)
   厘清「引擎=代码 / 模型=数据」——whisper.cpp 引擎仅几 MB 随包，模型是数据、运行时下载、
   全平台合规（iOS 有官方 ODR/Background Assets）、天然满足"不内置模型"，**化解了此前对
   whisper.cpp 的两个顾虑**，方向倾向 whisper.cpp（四端统一、避开 Android ML Kit alpha 坑）；
   **引入 whisper.cpp 依赖仍需用户正式确认后才拆落地 Task**。

## 约定

- 结构分层：`lib/src/core/`（薄封装 media_kit/内核抽象，无 UI 依赖）与
  `lib/src/ui/`（组件树 `slots/`、皮肤 `skins/`、叶子组件 `components/`、
  手势层、`MovaPlayer` 门面）；新逻辑按层归位，别塞回 barrel。UI 层只准依赖
  `MovaApi` 抽象，不得直接触达 `MovaKernel`/media_kit。
- 注释：每个类/方法/函数都要注释，先英文后中文、空行分隔、简短；公开 API 带参数/返回/示例。
- 值对象的构造期不变量用 `assert`（release 下零成本，风险面只在开发者机器上）；运行时的
  可恢复错误一律走策略对象 + 事件回调，不许 `throw`。**注意 `const` 构造器的限制**：
  Dart 常量求值器只支持 num/String/bool 上的原生运算，`Duration` 的 `>`/`==`/
  `.inMicroseconds` 都不可用，在 `const` 构造器的初始化列表里写这类 assert 会让**每一处**
  `const` 调用点变成编译错误。这种情况改为公开一个 `assertValid()` 方法、由持有者在入口
  处调用（见 `MovaAdBreak.assertValid()`）。
- 校验用 `flutter analyze`（不用 build），除非要真跑 app。长机械改动先批量改、最后一次性校验。
- 手势侧别（左亮度/右音量，对齐 bilibili 等主流）经 `MovaGestureConfig` 的
  侧别→动作映射（`leftVertical`/`rightVertical`/`horizontal` 取 `MovaGestureAction`）配置，
  非写死；默认值即上述主流约定。（更早版本是"左音量/右亮度"，已翻转，别按旧注释改回。）
- 新函数/模块配单测；纯逻辑（解析/ABR/映射/格式化）务必抽出来测，UI 用 WidgetTester。
- 组件类必须暴露 `static const String componentName`（值与 `name` getter 一致），
  `MovaPatch` 调用方应优先引用该常量而非手写字符串字面量，避免拼写错误且获得 IDE 补全。
- **完成一个 Task/里程碑并提交后，立刻用当次实测的 `flutter test` 输出更新 `CLAUDE.md` 与相关 `doc/plans/*.md` 里的测试基线数字。** 这个数字过时会让下一次规划文档（尤其是 Opus 拆的计划）从错误的起点开始推导任务数与验收标准，多次发生过。
- **真机验证前必须先设计基于真实事件的测量方法**（如 `renderEpoch`/`MovaDone` 事件戳），不用墙钟计时、不用临近素材 EOF 的 seek——这两种方法在本项目里已反复导致"测试工具自己的 bug 被误判为产品 bug"的返工。验收 demo 要为该功能单独建一个页面，不与其他 spike 混用；每次测量注意防缓存（URL 加 timestamp）、多次取平均。详见 `feedback_real_device_verification` 记忆。

## 落地工作流：Opus 拆方案 + Sonnet 落地

本项目验证有效的标准流程，新功能默认按此走：

1. **Opus 规划 agent**（只读探索 + 写文档，不动 `lib/`）把需求拆成 `doc/plans/<date>-<feature>.md`：架构决策、逐 Task 的文件改动、代码块、单测断言、验收标准、测试数量推进表。
2. 主 agent 把计划文档落盘到仓库。
3. **Sonnet（或 Opus，视复杂度）落地 agent** 按计划逐 Task 实现，每个 Task 一个 commit，`flutter analyze` 0 issues + `flutter test` 全绿再往下走。
4. 真机验证单独一轮，产出实测数字回写计划文档与 `feedback_real_device_verification`。

## 命令

```bash
flutter analyze
flutter test
cd example && flutter run -d windows        # 最快的实跑
flutter pub publish --dry-run
```

## Git

`dart-labs` 是 monorepo，mova 是子目录。`origin` 同时推 codeup 与 github(icodejoo/dart-labs)。
提交信息用 `type(scope): message`，scope 用 `mova`。装了 lefthook 钩子（本机若无 lefthook 会跳过）。
