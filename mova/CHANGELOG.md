## Unreleased

* **Fix：恢复层真机复测的两处问题**。
  * **默认配置下 404 等确定性失败仍等满 `startTimeout` 才重试**：原生 `END_FILE` 订阅只在有 reporter 或 `preciseFirstFrame: true` 时才打开，`recovery.enabled` 不会打开它，README 写的"坏地址秒判"对不上。现在 `createMovaEngine` 在 `recovery.enabled` 时自动订阅 `END_FILE`；`MovaMpvKernel` 新增 `observeRestarts`（默认 `true`），恢复机制只开 END_FILE、不转发 `PLAYBACK_RESTART`，首帧判据与未开 recovery 时一致（不转发 RESTART 时 `nativeRestartAvailable` 为 `false`，首帧闸门不会白等宽限）。`movaObserveFlags` 新增 `recovery` 参数与 `restart` 字段。
  * **`whepMediaTimeout`/`demuxerOptions` 整体覆盖 `demuxer-lavf-o`，还原又失败**：此前整串 set，media_kit 默认的 `seg_max_retry`/`allowed_extensions`/`protocol_whitelist` 等被冲掉；还原时把读出的串原样写回，而 `protocol_whitelist` 的值带逗号没法再解析，mpv 报 `Expected '=' and a value.`，错误进 `state.error` 并发 `MovaErrorEvent`，之后的点播源还带着 `media_timeout`。现改为 `change-list add` 只并入本源的键，还原时 `remove` 这些键、被同名键顶掉的原值用 `append` 补回，不再读回整串；写入失败或语法不合法的项整项跳过。`MovaMpvKernel` 对 `demuxer-lavf-o`/`stream-lavf-o` 这类键值列表走此路径，其余 `mpvOptions` 仍是整值写入、还原为读到的原值。

* **Fix：恢复层（`MovaOpts.recovery`）六处问题**（来自 Android 真机拉 WebRTC/WHEP 直播、推流端掉线再恢复的场景）：
  * **恢复成功后 `state.error` 不清**：`MovaRecovered` 发出时同步清掉失败期间遗留的内核错误（此前只有 `open()` 会清，画面正常了仍带着旧的 "Failed to recognize file format"）。
  * **放弃后 `state.buffering` 一直为 true**：`giveUp` 时把 `buffering` 置回 false，并补发一次 `MovaBufferChange(false)`（本来就不在缓冲则不多发），转圈不再永远挂着。
  * **重试失败要等满 `startTimeout` 才发下一次**：根因是加载在途（`_kernelOpening`）时到达的 `END_FILE(error)`（如 404）被直接丢弃，只能靠 10s 起播超时兜底。现在先记下，`open()` 返回后立刻按策略处理；被更新的 `open()` 取代的会话则丢弃。
  * **直播默认只重试 1 次**：新增 `MovaLiveReconnect`（指数退避，默认 1s 起、×2、封顶 30s，永不放弃，`maxAttempts` 可设上限；多地址时前面的地址各重试 `retriesPerAddress` 次再切，最后一个持续重连）与 `MovaDefaultRecovery`（点播 `MovaRetryThenFailover`、直播 `MovaLiveReconnect`），`MovaRecoveryConfig.policy` 为 `null` 时生效；新增开关 `MovaRecoveryConfig.liveReconnect`（默认 `true`，设 `false` 直播回到旧的重试 1 次）；`MovaPlayFail` 新增 `isLive`。**行为变化**：直播源在 recovery 开启且没传自定义 `policy` 时不再在第二次失败后放弃；点播默认行为不变。`MovaRecoveryConfig.effectivePolicy` 的默认类型由 `MovaRetryThenFailover` 变为 `MovaDefaultRecovery`。
  * **公开 API 无法传源级 libmpv/ffmpeg 选项**：`MovaSource` 新增 `mpvOptions`（任意 mpv 选项）、`demuxerOptions`（合成 `demuxer-lavf-o`）、`whepMediaTimeout`（WHEP `media_timeout`，自动换算微秒、只对 `whep…` 地址生效）与 `mpvOptionsFor(address)`；`MovaSource.pick`/`sameAs` 同步支持。内核侧新增可选能力 `MovaSourceOptionsKernel`（`MovaMpvKernel` 与 `MovaTestKernel` 实现）：引擎在每次内核 `open` 前暂存该地址的选项，内核在 open 前下发，下一次 open 先还原原值，不泄漏到下一个源。`MovaTestKernel.stagedSourceOptions` 供宿主测试断言。
  * **直播 `MovaDurationChange` 过于频繁**：新增 `MovaLiveConfig.durationStep`（默认 2s），直播源时长变化不足一个步长不上报（state 与事件都跳过；首个非零值、回落到 0、重新 open/重载后的第一个值一律放行），`Duration.zero` 关闭节流；点播不变。
  * 新增 48 项回归（`recovery_fixes_test`/`live_reconnect_test`/`duration_throttle_test`/`source_options_test`/`engine_source_options_test`/`mpv_kernel_source_options_test` 等），全量 1472 项通过。

## 0.3.1

* **Breaking（公开签名）：`MovaApi.open()` 由 `Future<void>` 改为 `Future<bool>`**，`true` 表示该源已被接受为当前源；`beforeOpen` 钩子拒绝、被更晚的 `open()` 取代、引擎已销毁时为 `false`。加载失败不算 `false`（照旧经事件/恢复上报，未处理的仍抛出）。只 `await`/`unawaited` 调用的代码无需改动；自己实现 `MovaApi` 的类（含测试替身）须把 `open` 的返回类型改成 `Future<bool>`。`MovaPlaylistController.jumpTo` 据此在 `open` 被拒绝时不再前进下标，列表与实际在播源不再错位。
* **Fix：宿主异步钩子、预览队列与手势改配的三处边界**。① `play()`/`seek()` 在宿主异步 `beforePlay`/`beforeSeek` 返回后复查：期间用户 `pause()` 或换源，晚到的 play/seek 不再覆盖（此前会把暂停改回播放，或对新源执行旧跳转）。② 预览服务队列单次解析抛错不再让后续请求全被跳过，`dispose` 各步骤相互隔离（宿主注入的缓存/探针抛错不再拖垮销毁）。③ 手势动作改配后按选中该模式的那根轴取位移：`horizontal: volume/brightness` 向右为增，`leftVertical/rightVertical: seek` 向上为快进（此前读错轴，位移约为 0）；默认配置行为不变。
* **Fix：三处小问题**。`MovaDanmakuConfig` 加 `assert(trackCount > 0)`（原先为 0 时弹幕取模除零）；`MovaGestureConfig` 加 `assert(maxZoom >= 1)`（原先小于 1 会在捏合中途让 `clamp` 抛 `ArgumentError`）；`MovaSttService.start()` 在引擎 `start` 失败时回滚 `isRunning`，失败后可直接重试，不必先 `stop()`。另补全 `MovaPatch*` 与 `MovaPlatform` 的公开成员注释。
* **Refactor：无缝切换的倍速改由预热计划声明**。`MovaWarmPlan` 新增 `rate`（null 继承旧引擎，行为不变），`MovaSwapController.swapTo` 新增可选 `rate`；广告方向（内置 `effectiveWarmPlan` 与 pod 的 `swapTo`）声明 1x，回正片方向声明广告前的倍速，换指时直接写到继任者上，不再有"换指后到复位生效之间广告短暂跑用户倍速"的窗口。广告控制器里原有的 `setRate` 复位保留为兜底，只服务回落成普通 `open()`、或宿主自定义 `adWarmPlan` 没带 `rate` 的路径。Android 真机 V12/V13a(2x)/V13b(1.5x) 通过。
* **Fix：广告 pod 里第二条广告的 `swapTo` 被悄悄降级成普通 `open()`**。两处竞态：① `MovaSwapEngine.abandon()` 在第一个 `await` 之后才复位 `_warmPlan`/订阅、把阶段置回 `idle`、唤醒就绪 completer，`unawaited(abandon())` 后紧跟 `swapTo` 时会冲掉新预热，现改为共享状态在 `await` 之前同步复位；② `MovaAdController` 在 `swapTo` 等待期间，旧引擎的进度 tick 会触发"广告背后预热正片"，把 `swapTo` 正在等的广告影子挤掉，现 `swapTo` 在途时不预热正片。Android 真机（STG-AL00）V12/V12b：第二条广告走真换指（`renderEpoch` 递增），槽位时长 5970–5999ms（配置 6000ms）。
* **Fix：系统 PiP 被用户展开/关闭后 `state.pip` 不复位**。新增可选端口能力 `MovaPipObservable.changes`（引擎用 `is` 探测，既有 `MovaPipPort` 实现无需改动），Android 插件监听 Activity 配置变化并推送 `pipChanged`（退出时 PiP 标志晚于配置变化翻转，故延迟复查并去重）；引擎据此更新 `state.pip` 并发 `MovaPipChange`。Android 真机（STG-AL00）`am start` 展开路径已验证 `true→false`；点 X 关闭路径未能注入点击，未测。
* **Fix：全量评审（Codex + 人工终审）修复一批异步过期/资源所有权问题**，新增约 45 项回归，Android 真机（STG-AL00）逐项对照修复前基线复测：
  * **无缝切换**：预热超时改由独立计时器兜底，不再依赖进度事件（`readyTimeout` 此前在影子完全无进度时不生效）；影子 `open`/`seek` 失败会清理并回退为普通打开，且不再往主事件流发 `MovaErrorEvent`（否则会把健康的在播广告误判失败）；已有影子时 `swapTo` 换了源会先丢弃再预热，不再提交旧影子；提交中途 `dispose` 会销毁影子；提交时把 rate/fit/zoom/音量/锁定/全屏/小窗/方向迁给继任者，旧引擎经 `MovaHandoffRetirable` 标记退役，退役引擎 `dispose` 不再复位全局方向。
  * **引擎**：`beforeOpen` 之后校验 `dispose`；`dispose` 后不再向已关闭的事件流 `add`；全屏/强制方向下 `dispose` 会复位设备方向与沉浸模式；`MovaMpvKernel.open()` 在异步恢复后复查序号，旧请求不再覆盖新源；`MovaVolumeChange.value` 注释订正为 0–100。
  * **广告**：加会话号与销毁标志，延迟解析的旧结果不再重开旧正片；广告加载超时与槽位计时改以真正的首帧（`rendered`/`MovaFirstFrame`，回退为连续两次递增的非零位置）为准，不再被零位置/残留进度提前取消；swap 路径下广告期间复位 1x、返回后恢复用户倍速。
  * **其余**：Feed 池同索引换源先释放旧引擎；QoE 会话累计器每次 `open()` 清零；播放列表 `jumpTo` 交错时丢弃过期结果；预览缩略图带 crop 时不入缓存（否则命中后显示整张雪碧图）、换源后丢弃旧请求结果、swap 提交后气泡随 `renderEpoch` 重订阅。
  * 已知未修见 `CLAUDE.md`「全量评审遗留」（PiP 退出状态不复位等）。

* **Fix：Windows 上 push 不透明路由时进程原生崩溃（HE V10）**：根因不在 mova，而是 Flutter 3.47.0/3.47.1 引擎的 bug——Windows + Impeller 下，`MaterialPageRoute` 默认的 `ZoomPageTransitionsBuilder` 会给页面拍快照（`SnapshotWidget`），快照里带外部 GPU 纹理（media_kit 的 DXGI 共享句柄纹理）时，引擎 `LayerTree::Flatten` 里解引用空上下文，进程在 `flutter_windows.dll` 以 `0xC0000005` 退出（flutter/flutter#190774，Flutter 3.47.2 已修）。纯 media_kit `Video` 不带 mova 同样复现。mova 侧规避：`MovaPlayer` 的渲染面在 Windows 上套一层 `MovaSnapshotGuard`（加一个 `supportsRasterization()==false` 的图层，宽松快照据此退回普通绘制），其他平台行为不变。release 实测：修复前 6/6 崩溃、探针 2 轮内必崩；修复后验证页 V10A 20/20、V10 10/10、探针 20/20/20/30 轮不崩。**根治办法是宿主升级到 Flutter ≥ 3.47.2**；也可在主题里对转场关快照（`ZoomPageTransitionsBuilder(allowSnapshotting: false)`）。新增 8 项回归（`test/ui/snapshot_guard_test.dart`）。详见计划文档 `doc/plans/2026-10-23-host-ergonomics.md` V10 小节。

* **Fix：点播恢复重试丢失续播位置（HE V6）**：卡顿超时、`open()` 异常后的重试及原生 `END_FILE(error)` 恢复，改为等本次尝试首帧落地后再发送续播 seek，避免加载命令已返回但文件未就绪时 seek 被丢弃。同内容备选地址沿用续播点，跨失败继续保留；直播不 seek。代码回归已通过，待 Windows/Android 复测。

* **Fix：无缝切换预热误改系统音量（standby 计划 Q13）**：`muteWhileWarm` 改走可选的播放器静音能力，mpv 仅保存、改写、还原自身 `mute`；预热和提交均不写系统音量端口。不支持能力的内核不静音；与 standby 静音叠加时按各自所有权精确还原。恢复静音失败走放弃切换策略并发出错误事件。代码回归已通过，待真机音频确认。

* **宿主易用性增强（第一批，对应 `doc/plans/2026-10-23-host-ergonomics.md` Task 1–8）**——全部默认关闭或与旧行为一致：
  * **"已出画面"信号**：新增 `MovaState.rendered`（当前源已呈现首帧/首段音频，每次 `open()` 重置）与
    `MovaFirstFrame(sinceOpen, signal)` 事件（每次 `open()` 一次，可重复）；判据纯逻辑在 `MovaFirstFrameGate`/
    `MovaFirstFrameSignal`（原生 RESTART 为权威，兜底为 buffering 下降沿/连续递增位置/暂停态首个尺寸，原生在工作时
    兜底信号先到则最多等 1.5s 宽限）。内部重载（换档、回直播边缘、时移）不重置 `rendered`。
    **行为微调**：`open()` 现在会同步把 `state.width/height` 归零（此前要等内核异步发 null），换源后旧画面比例不再漏进新源。
  * **原生事件订阅与 QoE 解耦**：`MovaMpvKernel(observeNativeEvents:)`（默认跟随 `observeQoeSignals`，既有调用点不变）；
    `createMovaEngine(preciseFirstFrame:)`（默认 `false`；`true` 时即使没有 reporter 也订阅原生 RESTART，首帧更准，
    代价是每引擎一个 mpv 弱客户端）。
  * **填充模式可声明**：`MovaEngine`/`createMovaEngine` 新增 `fit` 初值参数；`MovaPlayer(fit:)` 挂载时应用一次，
    之后仅在该值变化（或换了 `api`）时再应用，用户用 fit 按钮选的值不会被无关重建覆盖。
  * **内置封面**：`MovaPlayer(poster:, posterFade:)`，封面放在交给皮肤的 `video` 里（缓冲转圈/错误层/控制条画在其上），
    `rendered` 且画面尺寸已知后淡出，换源瞬间重新盖上；仅音频源常驻。`MovaFeedPlayer(posterUntilFirstFrame:)`
    （默认 `false`）把 placeholder 当封面盖到首帧。
  * **极简皮肤** `MovaMinimalSkin(showBuffering:, showError:)`：只有画面与可选转圈/错误层，无手势层与任何栏；
    `MovaTheme` 新增可空的 `bufferingSize`/`bufferingStrokeWidth`/`bufferingColor`（默认 `null` = 与旧外观一致）。
  * **声明式组件** `MovaView`：传 `source` 即可，自己创建/复用/重建（`options` 变化）/销毁引擎，源变 `null` 时暂停，
    打开失败走 `onOpenError`（缺省交给 `FlutterError.reportError`）；有 `poster` 时默认开启原生首帧订阅。
    新增 `MovaSource.sameAs()`（比较 uri 与 type，忽略 title）；`MovaSource` 刻意不重写 `==`。
  * **破坏性变更（编译期）**：`MovaEvent` 是 `sealed`，新增子类 `MovaFirstFrame` 会让宿主里**没有 `default` 分支的
    穷尽 `switch`** 编译报错，补一个分支或 `default` 即可；mova 自己的事件翻译已有 `default`，不受影响。
* **宿主易用性增强（第二批，对应同一计划 Task 9–15）**——全部默认关闭：
  * **起播/卡顿超时与恢复** `MovaOpts.recovery`（`MovaRecoveryConfig`，默认 `enabled: false`）：起播超时（默认 10s）、
    卡顿超时（默认 10s，`null` 关闭）、`open()` 抛异常、原生 `END_FILE(error)`、直播走到结尾（`liveEndIsFailure`）。
    决策由可注入的 `MovaRecoveryPolicy` 给出（默认 `MovaRetryThenFailover`：每地址 1s 后重试 1 次再切备选，用尽放弃；
    另有 `MovaFailoverOnly`），产出 `MovaRecoveryDecision.retry/failover/giveUp`。新事件 `MovaPlayFailure(fail, action)`、
    `MovaRecovered(attempts)`；放弃时写 `state.error = MovaGiveUpError` 并发 `MovaErrorEvent`，同时暂停内核。
    重试/切换是内核重载而非新会话（不过拦截器、不发 `MovaSourceChange`、不动 QoE 会话）。**关闭时不创建任何 Timer、
    不订阅任何新流，`open()` 失败仍照旧抛给调用方**（`MovaAdController` 依赖它区分 `openThrew`）。
  * **多地址兜底**：`MovaSource(alternatives:)`、`MovaSource.uris`、`MovaSource.pick()`（清洗并去重保序）、
    `MovaState.sourceIndex`、`MovaFailover(from, to, uri)` 事件。`sameAs()` 现在也比较备选地址（含顺序）。
    **仅在 `recovery.enabled` 时才会用到备选**，关闭时被忽略。mova 不提供排序/过滤钩子，由宿主排好序。
  * **自动暂停守卫** `MovaAutoPause` 与纯逻辑 `MovaAutoPauseGate`/`MovaAutoPauseConfig`（`MovaHideReason`/`MovaLiveResume`/
    `MovaGuardAction`）；`MovaView(autoPause:, routeObservers:)`。覆盖滚出视口、非活跃 Tab（`TickerMode`）、被路由盖住、进后台；
    `inactive` 不暂停但先快照播放意图；画中画/小窗里不暂停；直播隐藏 ≥ 3s 回边缘再播。只用 Flutter SDK，无新依赖。
    **注意**：`routeObservers` 是**列表**，每个 navigator 一个观察者——`NavigatorObserver` 不能同时挂到两个 navigator 上。
  * **宿主测试替身** `package:mova/testing.dart`：`MovaTestKernel`、`MovaTesting.useTestKernels()/reset()/lastKernel`；
    安装后 `createMovaEngine()` 改用可编程内核、平台端口全部空实现，widget 测试不再需要 `MediaKit.ensureInitialized`。
    不在主 barrel 里。
  * **破坏性变更（编译期）**：`MovaEvent` 再新增三个子类 `MovaPlayFailure`、`MovaRecovered`、`MovaFailover`
    （连同上一批的 `MovaFirstFrame` 共 4 个），宿主里没有 `default` 分支的穷尽 `switch` 需要补分支。
    `MovaOpts` 新增 `recovery` 节（有默认值，既有调用点不受影响）。
  * 验证页：`example/lib/main_host_ergonomics_verify.dart`（真机验证用，尚未上机）。
* **评审修复（11 条）**：`MovaState.playbackIntent` 独立于内核 `playing`，内部重载与看门狗遵循最新播放意图；恢复绑定已接受会话与失败尝试，跨失败保留续播点；自动暂停守卫订阅状态并重绑引擎、保留配置更新前的隐藏周期；直播恢复、视图加载、档位请求均校验异步过期。逐条说明见 `doc/plans/2026-10-23-host-ergonomics.md`「评审修复」。

* **低功耗待机（standby，对应 `doc/plans/2026-10-23-standby-mode.md` Task 1–9）**——默认关闭，不调用就一行代码都不会走到：
  * **入口**：`MovaAutoPauseConfig(hiddenMode: MovaHiddenMode.standby)`（守卫自动处理，默认 `pause`）与命令式的 `MovaStandbyController.setStandby(bool)`
    （`MovaEngine`/`MovaSwapEngine` 实现；`MovaApi`、`MovaKernel` 零新增成员，用 `is` 探测）。调参 `MovaOpts.standby`（`MovaStandbyConfig`：`maxDuration` 默认 30s、
    `silentStreams`、`allowHls` 默认 false、`resumeTimeout` 默认 5s、`liveResumeGrace` 默认 3s）。
  * **机制**：有音频的直播 → 关视频解码并静音（`mute`/`vid`，保存后原样还原，绝不碰 `volume`/`vo`/`wid`/`VideoController`）；无音频 → 继续解码只静音；
    点播、进后台、媒体信息未知、HLS（默认）→ 普通暂停；到 `maxDuration` 自动退回暂停。**网络不省，省的是解码/渲染/电。**
  * **状态与事件**：`MovaState.standby`（`MovaStandbyPhase`：`off`/`holding`/`fallback`/`resuming`）、`MovaStandbyChange(phase, reason, mode)`、
    `MovaStandbyResume(elapsed, signal, from)`；`MovaStandbyMode`/`MovaStandbyReason`/`MovaSilentStandby` 随之公开。
  * **恢复计时**：`MovaFirstFrameGate.arm(resume: true)` 只认原生 RESTART 与非零尺寸、立即落地；`rendered` 全程不动，不发 `MovaFirstFrame`。
  * **与既有能力的交互**：待机期间看门狗不计时、ABR 与自动回边缘不触发、失败延到唤醒时强制重开；待机请求期间 `open()` 换源以暂停态加载，首帧落地后再尝试待机；
    `setMini(true)`/`enterPip()` 先唤醒；`MovaSwapEngine` 透传并在提交时把待机施加到新引擎；封面在待机与恢复期间瞬间盖上；`MovaTestKernel` 支持待机（`hasAudio`/`fileFormat`）。
  * **破坏性变更（编译期）**：`MovaEvent` 再新增 `MovaStandbyChange`、`MovaStandbyResume`，`MovaGuardAction` 新增 `standby`/`wake`，宿主里没有 `default` 分支的穷尽 `switch` 需要补分支。
  * 验证页：`example/lib/main_standby_verify.dart`（真机验证用，尚未上机）。

## 0.3.0

* 埋点上报增强：`MovaReporter` 补齐 TTFF 首帧耗时、卡顿次数与时长、播放失败
  fatal/非 fatal 区分、会话开始/结束（含四分结束原因）四大 QoE 指标；新增
  `MovaReportConfig`（`MovaOpts.report`，默认 `qoe: false`，关闭态事件流与之前
  逐字节相同）。信号优先取 libmpv 原生能力（`paused-for-cache`/`video-bitrate`/
  `cache-speed`/丢帧计数/日志 prefix 错误分类），并顺带修了 `MovaEngine.open()`
  的会话边界时序竞态与 `MovaMpvKernel.dispose()` 的原生资源竞态两个真实 bug。
  * **破坏性变更**：
    1. `MovaReportName` 从 `enum` 改为 const 值类——不再有
       `MovaReportName.values.byName()`；`.index` 消失；在名称上 `switch` 的调用点
       须改为对 `.value`（`String`）做 switch，Dart 不允许对重写了 `==` 的类型使用
       常量模式。`==`/`hashCode` 按 `.value` 计算，`Map`/`Set` 键用法与
       `MovaApi.report(name, ...)` 签名不变，普通比较调用点零改动。
    2. `MovaErrorEvent` 的产出从 `translator.dart` 移到 `MovaQoeCollector`，
       `qoe: true` 时 `params` 从 `{'error'}` 增补为 `{'error', 'fatal', 'code'}`
       且非 fatal 错误降级为 `batched`（`qoe: false` 时旧行为不变）。
  * 原生 mpv 事件（`PLAYBACK_RESTART` 精确首帧、`END_FILE` 会话结束原因）由自建的
    `dart:ffi` 弱客户端订阅（`mpv_create_weak_client`），`media_kit` 依赖保持 pub.dev
    的 `^1.2.6`，**不再依赖 git 提交，可正常发布**。debug 模式下走 100ms 轮询，release
    走原生回调。Android 与 Windows 已验证；iOS/macOS 未验证（订阅失败时静默退化）。
  * QoE 修复（Android 真机跑通后发现）：首帧不再把 open 后 `buffering` 的初始 `false`
    当成首帧（需要 `true→false` 下降沿，外加"连续两个递增位置样本"兜底）；
    `sessionEnd.stallMs` 不再重复累计（此前是真实值的 2 倍）；首帧落地前不计
    `watchedMs`。原生 RESTART 订阅在工作时（新增 `MovaStatsProbe.nativeRestartAvailable`），
    首帧只认 RESTART，忽略更早但更粗的 buffering/位置兜底。
* **`VideoController` 改为懒创建**：`MovaMpvKernel` 新增 `lazyVideo`（默认 `false`）；
  `createMovaEngine()` 与默认 `MovaEngine` 内核使用 `lazyVideo: true`，在第一次读取
  `renderHandle`（`MovaPlayer` 挂上树）时才创建 `VideoController`。创建了却从未挂到界面
  的控制器会让 media_kit 的 `Player.dispose()` 一直等待（真机 Windows 3/6、Android 4/5 次
  撞 8 秒超时），懒创建后"创建 engine 却不展示"的销毁只需十几毫秒。无缝切换的影子引擎
  创建后会主动读一次 `renderHandle`，预热期间仍有画面管线。**若调用方自己创建并注入
  `VideoController`，需自行保证它挂到 UI 后再销毁**（见 README「已知限制」）。
* **截断结束判定**：`qoe: true` 时，点播会话以 EOF 结束但完播率低于 `MovaReportConfig.truncatedBelow`（默认 `0.9`，`<=0` 关闭）
  不再记 `ended`，改为先发 fatal 的 `MovaErrorEvent`（`code: truncated`）、再记 `failed`；直播无 duration，
  仅在 `MovaDone` 前 5 秒内有 ffmpeg 错误日志时才判截断。修正首帧后断网/服务端中途断流被误记 `ended` 的问题
  （Android 真机中途断流复测通过）。
* **TLS 严格校验开关**：`createMovaEngine()`/`MovaMpvKernel` 新增 `tlsVerify`（默认 `false`，行为不变）与
  `tlsCaFile`。开启后证书过期/自签/域名不符的 HTTPS 流被拒绝（stream 错误，会话 `failed`），HLS 分片与
  AES key 同样受校验。**Android 瘦身 libmpv 用 mbedtls、无系统信任库，开启时必须同时传 `tlsCaFile`（PEM），
  否则所有 HTTPS 都会失败**；`tlsCaFile` 里放自签证书即可信任该证书。IP 直连（如 `127.0.0.1`）不比对证书主机名。
  Android 真机本机 HTTPS 矩阵 144 次全部符合预期；iOS/macOS 未验证。
* **预览抽帧器修复**：`MovaFrameExtractor` 不再创建 `VideoController`（无界面下它的初始化
  永远完不成，Android 上 `extract` 曾 5/5 超时），改为 `vid=auto` + `vo=null` 解码；首次
  seek 前等待时长就绪，并轮询 `seeking`/`time-pos` 判定 seek 落地再截图。
  * **行为变化**：`settleDelay` 的含义从"seek 之后固定等待"变为"seek **落地之后**的额外
    等待"，默认值从 250ms 降为 60ms；若你显式传入了自己的值，请按新含义重新评估。

## 0.2.0

* 瘦身版 libmpv 接入支持：提供轻量二进制替换方案（覆盖 Android / Windows / iOS / macOS），体积缩减约 50%。
* Feed 沉浸式流播放器增强：包含短视频滑动、预加载与抖音风格皮肤定制。
* 修复 `MovaFeedPlayer` 中 `ensure()` 异步回调类型推断警告。
* 完善文档与接入范式。

## 0.1.0

首次发布 / First release.

基于 media_kit（libmpv/ffmpeg）的 Flutter 视频播放器插件，自研手势与控制层，支持
点播 / 直播，可作为独立 UI 使用，也可按 Plugin / Component / Skin 三层契约深度定制。

### 核心播放能力

* 播放内核封装：`MovaApi`（能力面抽象）+ `MovaEngine`（生产实现）+ `MovaKernel`
  （内核抽象，唯一依赖 media_kit 的实现细节收在 `MovaMpvKernel`）。
* 构造引擎请使用 `createMovaEngine()`（`lib/src/platform_impl/wiring.dart`），
  它会接入亮度 / 画中画 / 方向等平台适配器的真实实现；裸构造 `MovaEngine()` 的平台端口
  默认是 noop，仅用于单测注入假端口。
* 清晰度：HLS master 解析、手动切换（保位续播）、缓冲卡顿自动降档（ABR）。
* 观看模式 `contain` / `cover` / `fill`；锁定/解锁防误触 + 沉浸式；全屏按视频宽高比
  自动横/竖屏，也可用 `MovaApi.setOrientation` 强制横竖屏（独立于全屏）。
* 仅音频模式（`audioOnly`）：`createMovaEngine(audioOnly: true)` 完全跳过视频解码
  管线（不建 `VideoController`、不注册 GPU 纹理），`renderHandle`/`size` 相应变为
  `null`/`0x0`，UI 层无需改动（封面/歌词等自定义画面用 `MovaPlayer.surface` 传入）。
  实测省内存约 2–2.7 倍（视场景而异）。

### 手势与 UI

* 手势层：横滑进度 / 双击快进退 / 双指缩放，带 HUD；左右侧竖滑默认分别对应
  亮度 / 音量（对齐 bilibili 等主流），可经 `MovaGestureConfig` 的侧别→动作映射
  （`MovaGestureAction`）任意重映射或用 `MovaGestureAction.none` 禁用某侧。
* 组件树 / 皮肤 / 补丁三层契约：`MovaComponent` 组件树由 `MovaSkin`（默认实现
  `MovaDefaultSkin`）依据 `MovaState` 出树，通过 `MovaPatch`（`replace`/`remove`/
  `insertAfter`/`add`）做结构级定制，无需派生子类；`MovaDefaultSkin.assemble` 也可按
  `buildPlaybackLayer`/`buildOperableLayer`/`buildPersistentLayer` 三层半覆写。
* `MovaPlugin` 能力 mixin：为有状态组件提供 `api`（稳定句柄）与 `bind()`
  （订阅并在 `dispose` 自动回收）。
* 文案与主题：`MovaStrs`（默认简体中文文案）与 `MovaTheme`（默认配色/尺寸）经
  `MovaOpts` 注入，可整体替换。
* 系统音量端口 `MovaVolumePort`：右滑音量可驱动系统媒体音量而非仅播放器音量，
  Android 默认接原生 `MovaSystemVolumePort`，其余平台可传
  `MovaCallbackVolumePort` 自行接管。
* 渲染性能：播放层 / 操作层 / 常驻层各自 `RepaintBoundary` 隔离，互不牵连重绘。

### 直播特性

* 点播 / 直播两套控制条自适应合并为 `MovaBottomBarComponent`。
* 直播时移：`MovaLiveSeekMode.dvr` / `.timeshift` 两种可拖模式，
  `MovaLiveConfig.urlBuilder`/`backToLive`/`autoBackToLiveOnStall`/`windowResolver`
  可配置；`MovaState.timeshiftBehind` 配合 `MovaTimeShiftChange`/`MovaLiveEdgeReach`
  事件，`MovaApi.backToLiveEdge()` 按策略执行。
* `MovaApi.pipSupported`/`MovaState.pipSupported`：PiP 按钮在不支持的平台自动隐藏。

### 画中画 / App 内小窗

* Android 系统级画中画（`MovaApi.enterPip()`）；iOS/桌面暂不支持
  （libmpv 纹理渲染方式下系统级 PiP 依赖 AVPlayer 路径，未实现，`pipSupported`
  返回 `false`）。
* App 内小窗 `MovaMini`：不依赖任何系统 PiP API，让画面从页面里"缩"成一个可拖拽
  的悬浮小窗，不重新解码、不黑屏。默认 **关闭**（`MovaMiniConfig.enabled` 为
  `false` 时全链路零行为变化）。两种挂载方式并存：`MovaMiniController.showInPage`
  （页内悬浮）与 `MovaMiniController.show` + `MovaMiniHost`（跨路由持久）。支持吸边/
  钳制/安全区避让、惯性拖拽甩出关闭。与系统 PiP 互斥（进入小窗会先退出系统 PiP，
  反之亦然）。

### 拖动预览缩略图

* 拖动进度条或横滑手势时，在进度条上方显示目标时刻的缩略图气泡
  （`MovaPreviewComponent`）。
* 缩略图来源按序：服务端 WebVTT 雪碧图（`<video-url>.vtt`，支持 `#xywh` 裁剪）→
  libmpv 隐藏 `Player` 抽帧兜底，来源链可经 `MovaPreviewConfig.sources` 整体替换。
* 内存 + 磁盘两级缓存；网络策略默认 `wifiOnly`（`connectivity_plus` 探针判定，
  未知连接与桌面一律放行），被拦时静默不请求并发出 `MovaPreviewBlock` 事件。
* `createMovaEngine()` 的 `extractor`/`probe` 默认值为 `null`（不默认引入
  `media_kit_video`/`connectivity_plus` 的静态可达依赖，便于 tree-shake）。要启用
  抽帧兜底与 `wifiOnly` 网络策略，需显式传入
  `extractor: MovaFrameExtractor()`/`probe: MovaConnectivityNetProbe()`；不传
  `probe` 时内核兜底为纯 Dart 的 `MovaAlwaysAllowNetProbe()`，`wifiOnly` 策略不会
  被强制执行（其余网络策略不受影响）。

### 广告编排

* `MovaAdController` 支持按真实业务时序播广告：正片源可延迟解析
  （`loadDeferred(MovaSourceResolver)`），广告位 `duration`/`delay` 与素材时间轴
  解耦（统一 `Timer` 驱动，不查询/依赖 `state.duration`，不做尾部 seek）。
* 按广告位类型决定是否等待就绪（`MovaAdWaitPolicy`，内置 `MovaAdWaitByKind`
  默认 `pre` 否 / `mid` 是 / `post` 否），三层覆盖收在 `MovaAdConfig.waitsFor()`。
* 广告加载失败兜底：`MovaAdFailPolicy`（内置 `MovaAdRetrySkip`/`MovaAdAbandonPod`）
  统一处理打开失败、播放器报错、无首帧超时、预热未就绪四类场景。
* 等待/无缝切换需要宿主同时接入下节的 `MovaSwapEngine` 并开启
  `MovaSwapConfig.enabled`，否则退化为传统"到点直接切"的行为。

### 无缝引擎切换（可选）

* `MovaSwapEngine`：本身实现 `MovaApi` 的代理层，持有生效引擎与预热中的影子引擎，
  就绪后原子换指，把"广告播完回正片"从黑屏/loading 变成逐帧无缝。默认
  `MovaSwapConfig.enabled: false`，关闭时是纯直通代理，行为与不接入时一致。
  `MovaState.renderEpoch` 在切换后递增，用于触发渲染面重新读取 `renderHandle`。
* 预热触发策略（`MovaWarmTrigger`：`MovaLeadWarm`/`MovaEagerWarm`）与就绪判据
  （`MovaWarmPolicy`：`MovaBufferWarm`）两层可插拔；`MovaWarmPlan` 可按预热方向
  分别配置。
* **已知限制**：清晰度切换（`switchQuality`）与 feed 场景的引擎池未接入无缝切换——
  前者已走安全的寄存续播路径但未经过无缝切换本身的验证，后者结构性不适用
  （双画面并存需求）。

### 依赖

* `media_kit` / `media_kit_video` / `media_kit_libs_video`：播放内核。
* `path_provider`：拖动预览磁盘缓存目录。
* `connectivity_plus`：拖动预览的 `wifiOnly` 网络策略探针。
* `screen_brightness`：亮度手势的系统亮度端口。

### 已知限制

* iOS 系统级画中画未实现（见上文）。
* `switchQuality` 尚未接入无缝引擎切换（见上文"无缝引擎切换"小节）。
* `MovaAudioSkin`（封面/歌词/波形专用皮肤）未提供，仅音频场景请用
  `MovaPlayer.surface` 自行传入占位画面。

## 0.0.1

* 初始脚手架 / Initial scaffold.
