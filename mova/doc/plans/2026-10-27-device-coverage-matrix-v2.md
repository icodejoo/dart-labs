# mova 真机覆盖测试矩阵 v2（增补）

> 2026-10-27 · 读者：Codex（无会话上下文）。**本文是 [v1 矩阵](2026-10-27-device-coverage-test-matrix.md) 的增补，不替代它**：v1 的 A/C/E/U/F/N 照旧要跑，本文新增 S（皮肤）、P（公开类型）、L（日志）三类要求。
> 动因：v1 的 U2 只对五套皮肤做了"截图 + 组件树"；v1 只显式提到 90 个公开类型，导出面共 285 个，其余没有逐个落到用例。
> 配套台账：[2026-10-27-device-coverage-ledger.md](2026-10-27-device-coverage-ledger.md)（285 个公开类型逐行，必须全部填满）。
> 通用约束沿用 v1 §0（设备 `7NQBB23606003715`、亮屏解锁、`createMovaEngine()`、真实事件判据、不改 `lib/`、不 commit/stash/reset）。

## L. 日志规范（所有验证页与脚本强制遵守）

目的：任何一条 FAIL 不用重跑就能定位。**日志不够详细本身算验证页缺陷。**

1. **统一前缀与格式**：每行 `[MOVA-COV] <ISO时间ms> <run=运行ID> <case=编号> <kind> <内容>`。`kind` 取 `BEGIN/STEP/CALL/RET/EVENT/STATE/EXPECT/ACTUAL/VERDICT/SHOT/ERROR/END`。
2. **每个 API 调用都打 `CALL`（方法名 + 实参）与 `RET`（返回值或抛出的异常类型+消息+栈）**，包括预期会抛的调用。不允许吞异常。
3. **每个判定必须成对输出 `EXPECT` 与 `ACTUAL`**（含数值、单位、容差），再输出 `VERDICT PASS|FAIL|BLOCKED`；FAIL 行要带差值。
4. **事件与状态**：用例期间订阅 `events`/`states`，把每个事件按到达顺序打 `EVENT`（类型名 + 全部字段 + 当时 `engine.state` 关键字段）；每个 STEP 前后各打一次 `STATE` 快照（position/duration/playing/buffering/rendered/size/volume/rate/fit/zoom/locked/fullscreen/pip/mini/keepAlivePhase/renderEpoch/sourceIndex/playbackIntent）。
5. **FAIL 现场**：FAIL 时自动补打最近 50 条事件、`dumpsys window`（亮屏/方向/焦点）、`dumpsys audio`（音量类）、一张 `screencap`，路径写进 `SHOT` 行。
6. **皮肤用例额外打**：当前皮肤类名、`components()` 的 `name` 列表、各 `MovaSlot` 实际挂载组件、触摸注入坐标与手势类型（`adb shell input` 的原始命令）。
7. **分层落盘**：设备端 logcat 全量（`--pid`）→ `coverage_evidence/rerun2-<run>.logcat`；宿主端脚本自身日志（含每次 adb 命令、退出码、耗时）→ `rerun2-<run>.driver.log`；逐用例 JSON 汇总 → `rerun2-<run>.json`。三份用 `run=` 关联。
8. **脚本自身错误**必须与产品 FAIL 区分：验证页/脚本异常一律打 `ERROR kind=HARNESS`，在报告里单列「验证器问题」，不得算作库缺陷。
9. **时间**：判据用事件时间戳差，不用墙钟；每个计时类数字至少 3 次取均值并打印全部样本。
10. 日志不得含密钥/账号；本地源 URL 带时间戳防缓存，打印完整 URL。

## S. 皮肤专项（五套皮肤各自完整跑一遍）

对象：`MovaDefaultSkin`、`MovaBilibiliSkin`、`MovaDouyinSkin`、`MovaMinimalSkin`、`MovaMiniSkin`。每套皮肤按下表逐项跑，**同一套检查对每套皮肤各出一行结论**（台账里 5 皮肤 × 项，不能只写“皮肤通过”）。皮肤本身不支持的能力记 `N/A` 并写明依据（读该皮肤 `components()`），不是 PASS。Douyin 必须有**独立的全屏播放页**用例，不能只在 Feed 里看。

| 编号 | 检查项 | 测试点（真机） |
|---|---|---|
| S1 | 组件树 | `components()` 名单与 `MovaSlot` 分布；与源码声明逐个对账；`componentName` 常量与 `name` getter 一致 |
| S2 | 点播布局 | 点播源：顶栏/底栏/中心播放/进度条/时间标签各可见且可点；截图基线（亮度归一后对比） |
| S3 | 直播布局 | 直播源：底栏自适应（`seekBar`/`timeshift`/`backToLive`/直播徽标）；点播控件按预期隐藏 |
| S4 | 手势：单击/双击 | 单击显隐控件；双击实际是左右 ±10s seek（已知非播放切换），逐皮肤确认 |
| S5 | 手势：水平拖动 | 拖动 seek + 预览缩略图气泡 + `setDragging`；松手后落点误差 |
| S6 | 手势：竖滑 | 左/右侧竖滑 → 亮度/音量（默认左亮度右音量，按 `MovaGestureConfig`）；系统音量/亮度原生读回对账；HUD 类型与文本 |
| S7 | 手势：捏合/锁定 | 捏合缩放到 `maxZoom`；`setLocked(true)` 后手势与控件被屏蔽，锁定遮罩可解锁 |
| S8 | 手势：长按/其他 | 长按（已知无倍速）、Douyin 手势层 `MovaDouyinGestureLayerComponent` 的特有手势（上下滑、双击点赞）逐项 |
| S9 | 按钮逐个点击 | 播放暂停、倍速（点击循环 1x→1.25x…）、清晰度、字幕、PiP、Fit、方向、全屏、分享/点赞/评论/头像（有则测）；每次点击对应 `engine` 状态与事件 |
| S10 | 全屏与转屏 | 进/出全屏；横竖屏布局不错位；刘海/安全区；系统栏隐藏/恢复 |
| S11 | 覆盖层 | 缓冲圈（`MovaTheme.buffering*`）、错误层（404 源）、NextUp 卡片（取消/立即播放）、广告覆盖层（倒计时/跳过）、弹幕轨 |
| S12 | `MovaPatch` | 对本皮肤依次做 `Add`/`Replace`/`Remove`/`InsertAfter` 四种补丁；组件树与截图双确认 |
| S13 | 主题与文案 | `MovaTheme`、`MovaStrs` 经 `MovaOpts` 注入后各皮肤文案/颜色真实变化；默认外观不变 |
| S14 | 皮肤切换 | 运行中换皮肤（重建 `MovaPlayer`）：播放位置连续、不黑屏、引擎不重建；事件无重复 |
| S15 | 已知失败项交叉 | v1 的 U3/U5/U6/U7 在**每套皮肤**上是否同样成立，逐皮肤出结论 |
| S16 | Mini 专项 | `MovaMiniSkin`：拖拽跟手、吸边（`MovaCornerSnap`）、甩动不误关、`MovaMiniCloseComponent` 关闭、转屏后相对位置稳定（`remapProportionally`）、方式 A/B（`showInPage`/`show`+`MovaMiniHost`）互斥 |

## P. 公开类型覆盖（对账台账）

规则：[台账](2026-10-27-device-coverage-ledger.md) 的 285 个类型**每行必须有结论**。下表给出各家族的最低测试点，家族内每个类型至少被其中一个用例**直接触发**（有 `CALL`/`EVENT` 日志证据），否则标 `INDIRECT` 并给出间接证据。

| 编号 | 家族 | 台账分组 | 最低测试点 |
|---|---|---|---|
| P1 | 引擎与状态 | core, core/state, core/model, core/render | `MovaApi`/`MovaEngine`/`MovaCutoverEngine` 每个公开成员各一次调用；`MovaState` 全部字段读回；`MovaProg`/`MovaSelect`/`MovaUiSelect`/`MovaUiState`；`MovaStreamType`、`MovaPlatformKind`、`MovaFirstFrameSignal`、`MovaEndFileReason` 取值各至少观察到一次 |
| P2 | 事件 | core/events | 每个事件类至少触发一次并打字段；不能触发的（如平台特有）标 BLOCKED+原因；`MovaLogLine`、`MovaStatsSnapshot` |
| P3 | 配置 | core/options | `MovaOpts` 每个字段、每个子配置对象的每个字段：默认值读回 + 改值后行为变化（或明确“仅构造期”） |
| P4 | 广告 | core/ad | `MovaAds` 前贴/中插/后贴；`MovaAdBreak`/`MovaAdBreakKind`/`MovaAdEvent`/`MovaAdEventType`；`MovaAdFailAction`/`MovaAdFailKind`；`MovaAdRetrySkip`/`MovaAdAbandonPod`；`MovaAdOverlayComponent`；等待策略 pre/mid/post |
| P5 | 无缝切换 | core/cutover | `MovaCutover`、`MovaCutoverChange`、`MovaCutoverPhase`、`MovaWarmTrigger`（`MovaLeadWarm`/`MovaEagerWarm`）、`MovaWarmPolicy`/`MovaBufferWarm`、`MovaWarmCue/Signal/Verdict`；清晰度切换接入；关闭态直通 |
| P6 | 保活 | core/keep_alive | `MovaKeepAlive`、`MovaKeepAliveMode/Phase/Reason/Change/Resume`、`MovaSilentStandby`；`setKeepAlive` 命令式与 `MovaHiddenMode.keepAlive` 两个入口 |
| P7 | 恢复 | core/recovery | `MovaRecovery*`、`MovaPlayFail*`、`MovaRetry*`、`MovaGiveUpError`、`MovaPrefixError`、`MovaErrorPolicy/Verdict`、`MovaStallPolicy`、`MovaEdgeStall`、`MovaStall` |
| P8 | 上报 | core/report | `MovaReporter`、`MovaCallbackReporter`、`MovaReportEvent/Kind/Priority`、`MovaSessionEnd`、`MovaSessionTally`、`MovaSessionIdFactory`；`qoe:true/false`；自定义名 |
| P9 | 预览缩略图 | core/preview | `MovaPreviewService`、`MovaThumbSource` 三类（`MovaVttThumbSource`/`MovaPullerThumbSource`/抽帧）、`MovaThumbCache`/`MovaMemoryThumbCache`/`MovaDiskThumbCache`/`MovaTwoLevelCache`、`MovaThumbDirProvider` 三种、`MovaThumbCrop/Cue/Index`、`MovaNetProbe` 三种、`MovaFrameExtractor`/`MovaFramePuller`、`MovaVttUrlSolver`、`MovaCacheKeyBuilder` |
| P10 | STT | core/stt | `MovaSttService`、`MovaSttEngine`/`MovaNoopSttEngine`、字幕仓库三种、模型加载/提供者/目录提供者全部、`MovaSttCue`；无引擎/失败回滚按 v1 已知 BLOCKED 处理，必须注明 |
| P11 | Feed 与 Playlist | core/feed, core/playlist | `MovaFeedEnginePool`、`MovaFeedItem/Slot/Loader/HolderBuilder`、`MovaFeedLikeChange`、`MovaNetworkWarmFeedPrefetcher`；`MovaPlaylist*`、`MovaPlaylistItem`；滚动真实视频 |
| P12 | 平台端口 | core/platform, platform_impl | 音量/亮度/PiP/方向各端口的真实实现与 Noop/Fallback：`MovaSystemVolumePort`、`MovaScreenBrightnessPort`、`MovaChannelPipPort`、`MovaSystemChromeOrientationPort`、`MovaFallback*`、`MovaCallback*`、`MovaNoop*`；原生读回对账 |
| P13 | 拦截与守卫 | core/interceptor, core/guard, ui/guard | `MovaHook`/`MovaHookChain` 各钩子点（play/seek/open 等）改写与拒绝；`MovaAutoPause*`、路由观察器、`TickerMode` 路径 |
| P14 | 小窗 | core/mini, ui/mini | `MovaMini*`（`Rect/Insets/Placement/Mount/Host`）、`MovaCornerSnap`；见 S16 |
| P15 | UI 组件逐个 | ui/components, ui/slots, ui/scope | 台账中每个 `*Component`（含 `MovaIconButton`、`MovaGradBar`、`MovaSheetItem`、`MovaSlotBundle`、`MovaPlugin`、`MovaScope`、`MovaSelect`）：在至少一套皮肤里真实挂载并交互；`componentName` 常量逐个读 |
| P16 | HUD | ui | `MovaHud` 各类型（音量/亮度/Seek/缩放）真实触发并截图 |
| P17 | 旧名兼容 | `deprecated_names.dart` | 每个 `@Deprecated` typedef（`Swap*`/`Standby*`/`*Controller`/`MovaCtrl` 等）可构造/可调用，行为与新名一致；编译期警告不算失败 |
| P18 | 测试替身 | `package:mova/testing.dart` | `MovaTestKernel`/`MovaTesting` 安装后 `createMovaEngine()` 行为（平台端口全空实现）；与真内核互不污染 |
| P19 | 顶层函数 | `lib/mova.dart` | `createMovaEngine`（各参数组合：`audioOnly`、`preciseFirstFrame`、`pollInDebug`、tls、recovery）、`movaObserveFlags`、`movaProtocolWhitelist`（含 `dtls`） |

## 执行顺序建议

1. 先修补/新建验证页与日志框架（L 全部落实），在一个无关用例上自测日志是否足以定位问题。
2. 跑 S 皮肤专项（每皮肤一个独立验证页入口，不与其他 spike 混用）。
3. 跑 P 家族，边跑边填台账。
4. v1 的矩阵照旧重跑（若 Codex 已在跑，不要中断，另起一轮）。
5. 汇总：新建 `2026-10-27-device-coverage-v2-results.md`，包含皮肤 × 检查项 结论矩阵、台账完成率（必须 285/285 有结论）、与 v1 结果的差异、FAIL 的最小复现与归因（真实库缺陷 / 契约差异 / 验证器问题）。

## 验收标准

- 台账 285 行全部有结论，无空行；INDIRECT 占比需在报告里说明且每条有证据。
- 皮肤矩阵 5 × S1–S16 全部有结论（含 N/A+依据）。
- 每条 FAIL 在 `rerun2-*.logcat`/`.driver.log`/`.json` 里能单靠日志定位，无需重跑；抽查 3 条 FAIL 验证。
- 验证器问题与库缺陷分开统计。
