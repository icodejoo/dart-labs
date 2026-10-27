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

## G. 覆盖缺口审计（2026-10-27 重审 v1+v2 后补充）

方法：对 v1 矩阵与首轮/复跑结果文档做关键词与场景对账（grep 命中 0 次的主题即视为未覆盖），再对照 CLAUDE.md 里“未验证/待真机”清单。优先级：**P0** 发版前应补，**P1** 建议补，**P2** 有条件再做。

### G1. 环境/平台维度（整张矩阵只在 1 台设备、1 个 ABI、1 个厂商上跑过）

| 编号 | 缺口 | 优先级 | 做法 |
|---|---|---|---|
| G1.1 | **只测了 STG-AL00（华为）arm64-v8a**。四架构 libmpv 里 armeabi-v7a/x86/x86_64 完全没跑过；Android 版本只有 12 | P0 | 至少补 x86_64 模拟器（有 mpv 软解/硬解差异）与一台 Android 13+ 真机；armeabi-v7a 用老机型或 32 位模式 |
| G1.2 | **release 构建全程 `-Pdart-obfuscation=false`**（见 `coverage_build.py`），混淆/R8 minify 下的 JNI、MethodChannel、反射路径没验过 | P0 | 用 `--obfuscate --split-debug-info` 与默认 R8 再跑 A/F 冒烟；重点 PiP 通道、音量/亮度端口 |
| G1.3 | **以 pub.dev 依赖方式接入没测**：验证全程走 path 依赖；0.3.0 发布版与当前 Unreleased 行为差异、`media_kit_libs_*` 官方包（非 slim fork）路径无人跑 | P1 | 新建最小 consumer 工程用 pub 版本与官方 libs 各跑一次冒烟 |
| G1.3b | iOS/macOS/Linux/Web 无任何通用功能矩阵（Windows 仅零散） | P1 | iOS/macOS 受无 Mac 限制，标 BLOCKED 并注明；Windows 按 A/F 组做一遍桌面矩阵 |
| G1.4 | 仅 Impeller（Vulkan/OpenGLES）；Android 上 Skia 后端、不同 Flutter 版本（只有 3.47.0）未覆盖 | P2 | `--no-enable-impeller` 对照一轮渲染类用例 |
| G1.5 | 折叠屏/平板/分屏/多窗口/画中画与分屏并存、刘海与手势导航模式 | P1 | 模拟器 `adb shell wm size/density` + 多窗口命令 |

### G2. 系统交互场景（v1 矩阵 0 命中）

| 编号 | 缺口 | 优先级 | 做法 |
|---|---|---|---|
| G2.1 | **音频焦点**：来电、闹钟、其他 App 抢焦点、耳机拔出/蓝牙断开后的暂停与恢复 | P0 | `adb shell` 模拟来电（模拟器 `adb emu gsm call`）、另起播放器抢焦点；记录 `MovaPause` 来源与恢复策略 |
| G2.2 | **网络变化**：播放中 Wi-Fi↔蜂窝、飞行模式开关、网络恢复后的续播（只测过断网预热/预览降级） | P0 | `adb shell svc wifi/data disable|enable`、`cmd connectivity airplane-mode`；判据用 `MovaPlayFailure`/`MovaRecovered`/位置 |
| G2.3 | **息屏/锁屏/解锁**：灭屏后播放、熄屏自动暂停与亮屏恢复（只测过切后台） | P0 | `KEYCODE_POWER`/`KEYCODE_SLEEP`/`WAKEUP`；锁屏下音频是否持续要有结论 |
| G2.4 | 低内存/`onTrimMemory`、进程被系统回收后的重建、旋转导致 Activity 重建 | P1 | `adb shell am send-trim-memory`、开发者选项“不保留活动”、`am kill` |
| G2.5 | **物理音量键 / 系统音量被外部改动**：`state.volume` 是否同步（现在只测了 App→系统） | P1 | `input keyevent KEYCODE_VOLUME_UP/DOWN` 后读 `state.volume` 与事件 |
| G2.6 | 系统亮度被外部改动、退出播放/全屏后窗口亮度是否还原 | P1 | `settings put system screen_brightness` 前后对账 |
| G2.7 | 系统手势冲突（边缘返回、状态栏下拉）与垂直手势区域 | P2 | 真机手滑 + `input swipe` |
| G2.8 | 深色模式、字体缩放、系统语言切换（`MovaStrs`）、RTL、TalkBack/Semantics | P2 | `cmd uimode night yes`、`settings put system font_scale`、`setprop persist.sys.locale` |
| G2.9 | 磁盘满/缓存目录不可写/无存储权限时预览磁盘缓存、STT 模型目录的降级 | P2 | 小容量分区或权限撤销，确认不崩溃、有降级事件 |

### G3. 媒体源与协议维度（只测过 mp4、HLS、FLV、WHEP 选项）

| 编号 | 缺口 | 优先级 | 做法 |
|---|---|---|---|
| G3.1 | **本地来源**：`file://`、`content://`（SAF/相册）、Flutter asset、应用沙盒路径 | P0 | 推文件到 `/sdcard`，`MovaSource` 各形态各一次 |
| G3.2 | **容器/编码**：mkv、webm、ts、mp3/aac/flac/ogg（纯音频）、H.265、AV1、10bit、VP9、杜比；4K/高码率/高帧率硬解与回退软解（libmpv 已裁剪 demuxer/decoder，裁剪面是否误伤是最大风险） | P0 | 按 `mova-libmpv` 保留清单列“应支持/应不支持”两列，逐个格式真机对账；不支持的要给出明确错误而非挂起 |
| G3.3 | 协议：RTMP/RTSP/DASH/HLS 加密（AES-128）/fMP4 HLS/多音轨/多字幕轨切换 | P1 | 对照白名单（`movaProtocolWhitelist`）与裁剪清单 |
| G3.4 | 服务端异常：302 重定向链、不支持 Range、缺 Content-Length、chunked、间歇性 5xx、慢速抖动（只测过恒定限速）、HTTP/2、IPv6、代理 | P1 | 扩展 `verify_sources` 的本地源服务，按开关注入故障 |
| G3.5 | 点播↔直播同引擎互换（type 切换时 UI、时移、seekable 状态机） | P1 | 同一 engine 先直播后点播再直播 |
| G3.6 | 超长/超大文件、时长为 0/未知、时长突变、损坏文件、截断文件 | P1 | 构造样本，确认不挂死且有 `MovaPlayFailure` |

### G4. 稳定性与并发（v1 全是单点用例）

| 编号 | 缺口 | 优先级 | 做法 |
|---|---|---|---|
| G4.1 | **随机序列/压力测试**：随机 API 调用序列（open/play/pause/seek/switchQuality/setFullscreen/setMini/dispose 交叉）+ 不变量断言（state 与事件一致、无未捕获异常、无泄漏）；快速连点 100 次 seek/换源/全屏 | P0 | 写 fuzz 验证页，固定随机种子可复现，日志按 L 规范 |
| G4.2 | **长时间浸泡**：点播/直播连续 1–2h，监控内存/发热/掉帧/句柄，直播跨天时间戳 | P1 | `dumpsys meminfo/gfxinfo` 定时采样；现有 120 轮创建销毁只覆盖生命周期 |
| G4.3 | 运行中热切换：换皮肤、换 `MovaOpts`、改 `MovaStrs/Theme`（v2 S14 仅皮肤） | P1 | `MovaView` options 变化重建路径的真机验证 |
| G4.4 | 多实例：同屏两个 `MovaPlayer`、Feed 滑动 100 次 + 同时小窗 + 广告 cutover 叠加 | P1 | 组合场景，而不是单项 |
| G4.5 | 上报回调抛异常/阻塞时不拖垮播放；事件洪泛的背压 | P2 | `MovaCallbackReporter` 注入故障 |

### G5. 矩阵自身的问题（会让下次回归继续“假失败”）

1. **预期与产品设计不一致的条目长期 FAIL**：A1（流 broadcast 标志）、A2/E.Buffer/E.Size/E.Quality（快照语义）、A5/N12（open 异步归零）、E1（Play 早于 Ready）、C3/C6/C8/U3/U5/U6/U7（能力假设）。应**改矩阵预期**，或明确产品决策（要改产品就开 issue，要保持就把预期写成现行行为），否则每轮都有 15+ 条噪音 FAIL 掩盖真回归。
2. v1 里 **BLOCKED 4 项可以解锁**：C2（本地写一个按 behind 参数返回历史段的时移服务，Python 即可）、F15/WHEP（本地起 mediamtx 之类的 WHEP 服务，需先征得依赖同意）、A31/C7（STT 用**脚本化假引擎**验证 cue→字幕→SRT 导出→分块存储这条管线，真实识别另列 BLOCKED，不要再把“没有真引擎”当成整项阻塞）、N22 已有独立 debug VM 路径。
3. v1 仍用旧名（Swap/Standby/Controller），复跑靠 Codex 手工映射；应把矩阵与台账改成新名，并在台账中单列旧名 typedef（P17）。
4. 判定粒度：多个编号一个结论、子项通过比例看不出来。台账应记录“子项通过数/总数”。
5. 没有**自动化的回归入口**：目前是 Codex 逐批手工拼命令，下次还要重新理一遍。建议做一个 `example/tool/run_matrix.py`，按批次清单一键跑完并出汇总（失败自动保留现场），清单与本文件编号绑定。

### G6. 建议的补测顺序

1. **先做 G5（改矩阵预期 + 一键入口）**，否则后面补的用例结果没法和基线比。
2. **P0 一批**：G1.1/G1.2（ABI 与混淆）、G2.1/G2.2/G2.3（音频焦点/网络切换/息屏）、G3.1/G3.2（本地源与格式裁剪面）、G4.1（fuzz）。
3. 再做 v2 的 S 皮肤与 P 台账。
4. P1/P2 看排期。
