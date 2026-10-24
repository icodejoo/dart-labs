# mova：低功耗待机模式（standby）— 实现计划

> 2026-10-23 · 落地计划 · 依据：调研笔记 [2026-10-23-libmpv-low-power-standby.md](../notes/2026-10-23-libmpv-low-power-standby.md)
> （下称"调研 §x"）· 前置：[2026-10-23-host-ergonomics.md](2026-10-23-host-ergonomics.md)（下称"HE 计划"）全部 Task 1–15 已落地。

**Goal:** 播放器被隐藏（切 Tab、滚出屏、被路由盖住）时，不出画面、不出声，但**保持流连接与播放进度**（直播一直贴着边缘走），
重新显示时只需"恢复视频解码"，不再走 open → 请求 → 首片 → 解码器 → 首帧的整条重连链路。做成守卫的一个可选模式
（`hiddenMode: standby`）+ 一个命令式能力入口（`MovaStandbyController.setStandby`），默认关闭。

**一句话机制（调研结论）：** 流里有音频 → `vid=no` + `mute=yes`（组合 B，音频链当时钟、demuxer 继续追边缘）；
流里没音频 → 继续解码、只静音（组合 C 的安全变体）；点播、进后台、媒体信息未知、HLS（默认）→ 退回普通暂停；
待机最长 `maxDuration`（默认 30s）后自动退回暂停（组合 G）。**网络不省**，省的是解码/渲染/电；恢复要等关键帧（0~1 个 GOP）。

**主干原则不变：** core/ui 分层纯净（`purity_test` 的 `_mediaKitExceptions` 恒为 `{'kernel/mpv_kernel.dart'}`）、
**新功能默认关闭、不传参数时行为逐字节不变**、运行时可恢复错误走"策略 + 事件"不 `throw`、**不引入任何新第三方依赖**、
`MovaApi` 与 `MovaKernel` **零新增成员**（能力全部经"能力接口 + `is` 探测"接入，照 `MovaStatsProbe`/`MovaSwapController` 先例）。

**Baseline（2026-10-23 本机实跑，作为本计划起点）：**

```
$ cd mova && flutter test -r compact
... 00:54 +1158: All tests passed!          （real 1m01s，exit 0）
```

即 **1158 项全绿**，与 HE 计划文首"Task 9–15 已完成，最终 1158"一致（工作区含 HE 计划 Task 1–15 的未提交实现）。
`flutter analyze lib test` 以 HE 计划记录的 0 issues 为准，落地 agent 开工前自己再跑一次确认。

**执行约束：**

1. **真机（STG AL00）暂不可用。** Task 1–9 的验收**只依赖** `flutter analyze` / `flutter test` / 纯逻辑单测 / WidgetTester / 假内核，
   任何 Task 都不得把真机结果当前置条件。真机测量集中在 Task 10，标注【待定：等真机】，不阻塞合入。
2. **本计划排在 HE 计划之后落地。** 开工前提：HE 计划 Task 1–15 已按"每 Task 一个 commit"提交（当前仍是未提交工作区），
   `flutter test` 实跑数作为本计划 Task 1 的起点；若与 1158 不同，以实跑为准并顺延下表。依赖点逐条见 §7。
3. **还依赖 HE 落地代码的评审修复（2026-10-23 评审发现 11 个缺陷，修复进行中，写本计划时代码尚未定型）。** 本计划按协调方给出的
   修复要点对接，**以下述描述为准，落地时以实际代码的命名为准**（下文记作 R1–R4）：
   - **R1 统一"播放意图"**：引擎新增播放意图（`play()`/`open(autoPlay: true)` 置 true，`pause()`/`open(autoPlay: false)` 置 false），
     recovery 重试/切备选按**最新意图**决定加载后播不播。下文记作 `intent`。
   - **R2 恢复任务绑定"已接受会话世代 + 失败尝试编号"**，任何新的内部加载（`switchQuality`/`backToLiveEdge` 等）会取消待执行的恢复。
   - **R3 守卫订阅引擎状态**：隐藏期间播放意图变 true 时重新决策（暂停并记为"隐藏前在播"）；直播恢复带世代，每个 `await` 后校验可见性。
   - **R4 续播位置跨失败保留**。
   R1–R4 任一在落地时命名或形态与上述不同，落地 agent 按实际代码对接本计划的规则，并在本文"落地偏差"里记一笔。

## 落地偏差

> 落地过程中与上文不一致之处在此逐条记录（以实跑和实际代码为准）。

**实跑进度（起点 1177）：**

| Task | 新增 | 累计（实跑） | 备注 |
|---|---|---|---|
| 1 | +28 | 1205 | 纯逻辑；计划预计 1186，差值 +19 是 HE 评审修复回归（起点 1177 而非 1158） |
| 2 | +9 | 1214 | MovaMpvKernel 实现 MovaStandbyKernel，只增不改 |
| 3 | +14 | 1228 | state/事件/进入/退回/超时；对应计划预计 1209，差 +19 同上 |
| 4 | +14 | 1242 | 唤醒与恢复计时（闸门 resume 武装） |
| 5 | +15 | 1257 | 与宿主调用/recovery/ABR/自动回边缘的交互规则 |
| 6 | +5 | 1262 | swap 引擎透传与提交时同步，与计划一致 |
| 7 | +16 | 1278 | gate +10、widget +6，与计划一致 |
| 8 | +5 | 1283 | 封面待机两态覆盖 + MovaTestKernel 支持待机 |
| 9 | +3 | 1286 | 开放性对账；Task 1–9 合计 +109，与计划一致 |

- **HE 计划没有按"每 Task 一个 commit"提交。** HE Task 1–15 与评审修复的改动交错在同一批文件里（`engine.dart`、`state.dart`、`options.dart` 等被多个 Task 反复改动），
  交互式 `git add -p` 在本环境不可用，按 hunk 硬拆既不现实也容易拆出编译不过的中间提交。因此合并为两个提交：先提交文档（调研笔记与两份计划），再提交全部 HE 实现（含评审修复）。
  本计划（执行约束第 2 条）要求的"HE 已提交"前提据此改为"HE 已合并提交"，起点以实跑为准：**1177 项全绿**（HE 的 +19 评审修复回归已含在内），不是文首的 1158。
- **R1–R4 的实际命名（对接结果）：** R1 播放意图就是 `MovaState.playbackIntent`（引擎内 getter `_playIntent`，已存在，本计划直接读）；R2 的"有待执行恢复"在代码里就是 `_recoverTimer != null`，取消入口是丢弃该 Timer，本计划新增只读 getter `_recoveryPending` 与 `_cancelRecovery()` 包装它；R3 的守卫改造见 Task 7 的偏差。
- **Task 3：时钟注入。** 计划里"暂停多久 / 唤醒耗时"用 `DateTime.now()` 测量，但 `DateTime.now()` 不跟随 `fakeAsync`，计划里的 `elapsed == 5s`、`pausedFor >= 3s` 断言在测试里无从成立。引擎新增 `@visibleForTesting DateTime Function() debugClock`（默认 `DateTime.now`），待机计时全部走它，测试里替换成 `() => t0.add(async.elapsed)`。不新增依赖，生产路径行为不变。
- **Task 3：`play()` 的待机分支多处理一种情形。** 请求存在期间 `play()` 走 `_enterStandby(viaPlay: true)`，若判定为 `skip`（例如画面在 PiP/小窗里，`exempt`），计划草图会直接 `return` 而不播放，导致 PiP 里无法播放；实现改为 `skip` 时落回普通播放路径，只有 `holding`（播）和 `fallback`（保持暂停）才提前返回。
- **Task 3：`_standbyMode`/`_standbySince`/`_fallbackCause` 三个字段在本 Task 仅被写入、未被读取**（读取点在 Task 4 的唤醒路径），为保持 analyze 0 issues 临时加了带说明的 `// ignore: unused_field`，Task 4 去掉。
- **Task 3/4：测试夹具抽成共享文件。** 计划把 `_Rig` 写在各测试文件里，实际抽成 `test/support/standby_rig.dart`（`StandbyRig`/`YesPip`，时钟跟随 `fakeAsync`），Task 3 的测试随之改用它，Task 5–9 沿用。
- **Task 4：** `MovaStandbyResume.elapsed` 与 fallback 的 `pausedFor` 均经 `debugClock` 测量（见 Task 3 偏差）；计划 Task 4 引擎断言第 11 条（宿主换源后唤醒只归位）在本 Task 里用"fallback 期间 `open(autoPlay: false)`"实现，`reloaded` 的 phase 切换要到 Task 5 才有，但断言（意图为 false → settle，不 play、不多 open）与阶段无关，在两个 Task 下都成立。
- **Task 5：`open()` 里的待机等待是条件式的。** 计划草图写成无条件 `await _standbyBeforeOpen()`；实现改成仅当 `_standbyRequested` 为真时才 await，未涉及待机时 `open()` 不多一次微任务让出，保证"关闭态逐字节不变"。同时 `_armAttempt(autoPlay:)` 与 `_loadKernel(play:)` 在内部重载路径（`_recover`/`switchQuality`/`_seekTimeshift`/`_reopenLiveSource`）一并改读 `_loadPlays`（草图只提了 `play:`），使暂停加载的闸门启用尺寸兜底。
- **Task 7：R3 的实际入口与世代。** 守卫里 R3 的"隐藏期间意图变 true 重新决策"落在 gate 的 `observe({playing, exempt})`（widget 在 `_bindState` 的订阅里调用），不叫 `redecide`；`reconfigure`/`update` 沿用原名。为让 `observe` 也能选 standby，给它加了两个带默认值的可选参数 `live`（默认 false）与 `standbyCapable`（默认 false），旧调用逐字不变。widget 的"可见性世代"是 `_resumeGen`（只在隐藏/重绑/回边缘时自增），而 `standby`/`wake` 的补偿校验用 `!_gate.hidden && identical(api, widget.api)` 判断（进待机返回后若已不再隐藏则补一次 `setStandby(false)`；引擎侧队列保证顺序，重复唤醒幂等），没有复用 `_resumeGen`，因为"变可见"并不推进它。
- **Task 9：** 开放性对账 ② 里没有断言内核 `dispose` 已记入 `calls`——`MovaEngine.dispose()` 在 fakeAsync 里要等预览服务等异步收尾，断言不稳；改为"整套基础流程（点播/直播各一遍）里内核 `calls` 没有任何 `inspectStandby`/`enterStandby`/`exitStandby`、事件流没有待机事件、`state.standby` 恒为 off"。验证页 `main_standby_verify.dart` 为了读 `MovaStatsProbe.sample()` 的 `inputBps`，自己构造 `MovaMpvKernel`（引用 `package:mova/src/...`，与既有 example 验证页同样的做法）再交给 `createMovaEngine(kernel:)`；`MovaApi` 没有暴露探针，这是唯一取得 `cache-speed` 的办法，不需要新增任何公开成员。
- **Task 1–9 未触发"必须新增 `MovaApi`/`MovaKernel` 成员"或"既有测试语义变化"：** 当时既有测试里唯一被改动的是 `openness_audio_test.dart` 的节清单追加 `standby`（计划允许的那一处）；`test/support/fake_kernel.dart`、`fake_api.dart` 只追加新类/mixin，既有类体未动。计划 §6 的 Q1–Q15 按括号里的推荐默认落地，当时 Q13 未碰。
- **Q13 后续修复（2026-10-24）：已修复（代码层），待真机确认。** 开工前实跑 **1286 全绿**；修复后实跑 **1302 全绿（+16）**，`flutter analyze lib test` **0 issues**。新增 `MovaPlayerMute` 能力，经引擎转发、swap `is` 探测；mpv 复用 standby 串行属性队列，仅改 `mute`。不支持能力时不静音，绝不回退系统端口；恢复失败走放弃切换策略、发出 `MovaErrorEvent` 并清理影子。新增测试：真实引擎的预热/提交端口零写入（开/关两组）、不支持能力降级、standby 跨提交、恢复失败（5 项）；原生播放器替身验证幂等、失败重试、并发排队，以及原值 yes/no × 进入顺序 × 退出顺序（11 项）。既有 swap 测试改为断言不再调用 `setVolume`。本次不提交、不 build、不连设备；Android 音频与系统音量仍待真机确认。

---

## 0. 现状核实（均已在源码中确认）

| # | 事实 | 证据 | 对设计的影响 |
|---|---|---|---|
| 1 | media_kit `Player` 默认 `vid=no`，只有 `VideoController.create()` 把它改回 `auto`；Android 控制器另设 `force-window=yes`、先 `vo=null` 再由 `widListener` 设回 | `media_kit-1.2.6/.../native/player/real.dart:2323-2325`；`media_kit_video-2.0.1/.../android_video_controller/real.dart:185-205`、`native_video_controller/real.dart:158-160` | `vid` 是"受控属性"，待机要**读出原值、精确还原**，不能写死 `auto`（audioOnly / 懒创建从未挂界面的引擎原值就是 `no`，写成 `auto` 会在没有渲染面时开视频解码） |
| 2 | `NativePlayer.setProperty/getProperty(waitForInitialization: true)` 会先等播放器初始化与"已挂接的 VideoController 初始化" | `real.dart:1223-1245` | 只在"音频已在解码 / 轨道已加载"之后才动属性（D4 的判定天然保证播放器已初始化），并给每次属性读写加超时兜底 |
| 3 | `MovaState.width/height` 来自 media_kit `video-params`，且**只处理 `MPV_FORMAT_NODE`**；`vid=no` 时 `video-params` 变为不可用（`FORMAT_NONE`）被忽略，宽高**不归零**；`vid=auto` 后新解码器出首帧，`video-params` 重新可用，media_kit 会**再推一次**宽高（值可能相同） | `real.dart:1976-2049` | ① 待机期间封面判据 `rendered && w>0` 不会自己翻转；② "退出待机后首个尺寸事件"≈新解码器的首帧，可作恢复落地信号（D7）。**[源码+推断]**，Task 10 S7/S15 核对 |
| 4 | `Player.open()` 内部先 `stop()`，`state = PlayerState().copyWith(volume, rate, …)` 整体重置，`tracks`/`track`/`audioParams` 每个文件从空开始 | `real.dart:250-275, 325-342` | 轨道/音频参数可按"当前文件"可信读取；`audioParams.sampleRate != null` ⇔ 本文件的音频确实在解码（D4） |
| 5 | Android `widListener`：surface 变化时先 `vo=null`，再设 `android-surface-size`、`wid`、`vo=<配置值，或 wid=0 时 null>`，仅 `mediacodec_embed` 才改 `vid`，最后**无条件** `player.seek(position)`；注释："When --wid is 0, vo=null is required to avoid SIGSEGV" | `android_video_controller/real.dart:48-77` | **待机绝不碰 `vo`/`wid`**：碰了会被它覆盖；在 `wid=0`（进后台、surface 已回收）时把 `vo` 设回非 null 会原生崩溃。因此组合 C 只做"静音 + 继续解码渲染"，`vo=null` 变体排除（§5） |
| 6 | Android `AndroidVideoController.setSize` 直接 `throw UnsupportedError` | `android_video_controller/real.dart:221-228` | 桌面 `setSize(2,2)` 降载不做（§5） |
| 7 | `createMovaEngine()` 在 Android 默认接 `MovaSystemVolumePort`，`MovaEngine.setVolume` 走端口时改的是**系统媒体音量** | `platform_impl/wiring.dart:34-36, 220`；`engine.dart:1288-1303` | 待机静音**必须**走 mpv `mute` 属性（内核内部），**不能**复用 `setVolume(0)`。旁支发现见 Q13 |
| 8 | `MovaKernel` 未从主 barrel 导出；`MovaEngine` 已用 `_kernel is MovaStatsProbe` 能力探测订阅 RESTART/END_FILE | `lib/mova.dart`（无 `core/kernel` 导出）；`engine.dart:535-545, 598-601` | 内核待机能力照同一模式做成 `MovaStandbyKernel`，`MovaKernel` 零新增成员，`FakeKernel` 不用改 |
| 9 | `MovaApi` 的实现者：`MovaEngine`、`MovaSwapEngine`、`test/support` 的 `FakeMovaApi`；`MovaSwapEngine` 另实现能力接口 `MovaSwapController` | `engine.dart:60`；`swap/swap_engine.dart:44`；`swap/ctl.dart` | 命令式入口做成 `MovaStandbyController` 能力接口，`MovaApi` 零新增成员（Q1） |
| 10 | 首帧闸门：`onSize` 只在 `arm(autoPlay:false)` 时落地；原生可用时兜底信号进 1.5s 宽限；`onProgress` 两个递增样本即落地 | `core/render/first_frame.dart:78-158` | 待机期间位置一直在走，默认武装会在两个位置样本后**立刻误落地**；尺寸信号又会被宽限拖 1.5s。需要一个"恢复专用"的武装方式（D7） |
| 11 | 看门狗 `disarm()` 后 `onPlaying`/`onBuffering` 不会重新起表；起播期限在 `_loadKernel` 返回后才武装 | `core/recovery/watchdog.dart:83-115`；`engine.dart:606-619` | "待机期间不计时"可直接 `disarm()`；待机中由宿主触发的同源重载要跳过 `armStart`（D9） |
| 12 | 守卫 gate：首个隐藏原因 → `pause`；全部消失 → `resume`/`reloadEdge`；`inactive` 快照意图；`exempt`（pip/mini）不动作 | `core/guard/auto_pause.dart:190-293`；`ui/guard/auto_pause.dart:209-252` | 在 gate 上加 `hiddenMode` 与两个新动作 `standby`/`wake`（D10）；`routeObservers` 是**列表**（HE 偏差清单） |
| 13 | `MovaView._sync()` 在源变化时直接 `engine.open(src, autoPlay: widget.autoPlay)`，不看守卫是否判定隐藏 | `ui/view.dart`（`_sync`，约 L205-230） | **HE Task 13 的既有缺口**：隐藏期间换源会在看不见的卡片里出声。pause 模式下由评审修复 R3 补上（换源 → 意图 false→true → 守卫重新决策）；待机模式下意图本来就是 true，R3 不触发，由引擎侧"待机请求跨 `open()` 保留、以暂停态加载"补（D8，Q9） |
| 14 | feed 池 `focus()`：焦点页 `play()`、其余 `pause()` | `core/feed/engine_pool.dart:295-314` | feed 页不套待机（D12） |
| 15 | QoE collector 按 `MovaPlay`/`MovaPause` 计 `watchedMs` | `core/report/collector.dart:468-479` | 待机期间 `playing` 仍为 true，会被计成观看（Q8，本期不改 collector） |
| 16 | `test/core/openness_audio_test.dart` 从源码读出 `MovaOpts` 的节清单并逐字比对 | `openness_audio_test.dart:80-92` | 新增 `standby` 节必须在该清单追加 `'standby'`——本计划**唯一**允许的既有测试改动 |
| 17 | 评审修复 R1–R4（文首执行约束 3）：播放意图、恢复任务按世代取消、守卫在隐藏期间意图变 true 时重新决策、续播位置跨失败保留 | 协调方修复要点（代码修改中） | 待机的"在不在播"一律读 `intent` 而非内核回报的 `state.playing`；fallback 期间的内部加载不能按意图开播（D9）；R3 只在意图 **false→true** 时触发，覆盖不了"待机中换源"（意图本来就是 true），由引擎规则补（D8）。§0 #13 的缺口在 pause 模式下已由 R3 修掉 |

---

## 1. 架构决策

### D1 — 定位：待机是"隐藏时的另一种处理方式"，两个 opt-in 入口，默认 pause

- **守卫入口**：`MovaAutoPauseConfig.hiddenMode`（`MovaHiddenMode.pause` 默认 / `.standby`）。宿主只改这一个值。
- **命令式入口**：`MovaStandbyController.setStandby(bool on)`——`MovaEngine` 与 `MovaSwapEngine` 实现它。语义是
  "这块画面现在看不见 / 又看得见了"，引擎自己选最便宜且正确的做法：能待机就待机，不能就暂停（`fallback`），超时也退回暂停；
  `setStandby(false)` 从任一状态恢复（待机 → 恢复解码；暂停 → 续播或回边缘）。
- **以播放意图（R1）为基础**：进不进待机看 `intent`（不是内核回报的 `state.playing`——缓冲、系统自动暂停都会让后者短暂为 false）；
  待机自己做的暂停（fallback、超时、失败降级）**不改** `intent`，它只表示"用户/宿主想让它播"；退出待机时**按意图**决定出不出画面、播不播：
  `intent` 为 true 才恢复播放，为 false（例如请求待机时本来就没在播）则只把状态归位。
- **待机请求**：`setStandby(true)` 记下一个请求标记 `_standbyRequested`，直到 `setStandby(false)` 或宿主 `pause()` 才清除。请求存在期间，
  意图由 false 变 true（`play()`、swap 提交）会直接以待机态开播；`open()` 换源也不清除请求（D8）。
- **引擎级调参**：`MovaOpts.standby`（`MovaStandbyConfig`），只有调参没有开关——不调用 `setStandby` 就一行代码都不会走到。
- 不传任何参数：`hiddenMode == pause`、没人调 `setStandby`，**行为逐字节不变**（Task 9 的开放性测试锚定"基础流程从不触达待机内核调用"）。

### D2 — 三层分工：内核执行、引擎决策与状态机、守卫决定"何时"

| 层 | 文件 | 职责 | 纯净性 |
|---|---|---|---|
| 内核能力 | `core/kernel/standby_kernel.dart`（接口）+ `core/kernel/mpv_kernel.dart`（实现） | 报告媒体事实（音频在不在、demuxer 格式）；按指定组合**保存→改写→精确还原** `mute`/`vid`；不做任何决策 | 接口纯 Dart；实现是唯一碰 media_kit 的地方 |
| 决策 | `core/standby/plan.dart` | 两个纯函数：`decideStandbyEntry`（进不进、用 B 还是 C、为何退回暂停）、`decideStandbyWake`（怎么醒） | 纯 Dart，无 Timer 无时钟 |
| 引擎状态机 | `core/engine.dart` | 串行化迁移、调内核、计时（`maxDuration`/`resumeTimeout`）、写 `MovaState.standby`、发事件、与 recovery/ABR/看门狗协调 | 纯 Dart |
| 守卫 | `core/guard/auto_pause.dart`（gate）+ `ui/guard/auto_pause.dart`（widget） | 何时 `standby`/`wake`；进后台一律降级为 `pause` | gate 纯 Dart |

### D3 — 内核扩展：新的、独立的改动面，对 `MovaKernel` 向后兼容

HE 计划 Task 12 写过"`mpv_kernel.dart` 任何 Task 不许改"——那是 HE 计划**自身**的约束（守卫只需 `MovaApi` 就能做完）。
待机必须改写 mpv 属性，而 `purity_test` 只允许 `mpv_kernel.dart` 碰 media_kit，所以**本计划显式开一个新的改动面**，并把改动限制为**只增不改**：

- `MovaMpvKernel` 的 `implements` 列表追加 `MovaStandbyKernel`；新增 3 个公开方法 + 若干私有字段/私有方法；
- **构造函数签名、既有方法体、既有字段一行不动**；不新增构造参数（能力常驻、零成本：不调用就不发生任何 FFI 往返）；
- `_mediaKitExceptions` 不变；`MovaKernel` 零新增成员；`FakeKernel`/`FakeStatsKernel` 不改，新能力用新的测试替身（`FakeStandbyKernel`）。

```dart
// core/kernel/standby_kernel.dart（纯 Dart，不进主 barrel，与 MovaKernel 同级可见性）

/// Whether the current media has audio that is actually being decoded.
///
/// 当前媒体是否有**正在解码**的音频。
enum MovaAudioPresence {
  /// Not known yet: tracks not loaded, or an audio track exists but its
  /// decoder has not produced output (it may still be starting, or the
  /// codec may be unsupported by a slim libmpv build).
  ///
  /// 尚不知道：轨道未加载；或有音轨但解码器还没输出（可能仍在起播，也可能瘦身版
  /// libmpv 不支持该编码）。
  unknown,

  /// An audio track is selected and decoding.
  ///
  /// 有选中的音轨且正在解码。
  present,

  /// Tracks are loaded and there is no usable audio.
  ///
  /// 轨道已加载，且没有可用音频。
  absent,
}

/// Facts about the current media that decide whether and how to hold it.
///
/// 决定当前媒体能否待机、以何种方式待机的事实。
class MovaStandbyMedia {
  /// Creates the facts.
  ///
  /// 创建事实。
  const MovaStandbyMedia({required this.audio, this.format});

  /// Audio presence, see [MovaAudioPresence].
  ///
  /// 音频存在性，见 [MovaAudioPresence]。
  final MovaAudioPresence audio;

  /// mpv's `file-format` (demuxer name, e.g. `flv`, `hls`); `null` when unreadable.
  ///
  /// mpv 的 `file-format`（demuxer 名，如 `flv`、`hls`）；读不到时为 `null`。
  final String? format;
}

/// Optional kernel capability: hold the stream with video and/or sound off.
/// Never throws; a kernel that lacks it simply makes standby fall back to a pause.
///
/// 可选的内核能力：在关掉画面和/或声音的情况下维持流。绝不抛异常；不具备此能力的内核
/// 只会让待机退回为普通暂停。
abstract class MovaStandbyKernel {
  /// Reads the facts standby decides on. 读取待机决策所需的事实。
  Future<MovaStandbyMedia> inspectStandby();

  /// Applies [mode], saving every property it changes. Returns false (after
  /// rolling back) when a write failed or timed out.
  ///
  /// 应用 [mode]，并保存它改动的每一个属性。写入失败或超时则回滚并返回 false。
  Future<bool> enterStandby(MovaStandbyMode mode);

  /// Restores exactly what [enterStandby] changed. Returns whether video
  /// decoding was restarted (so a fresh first frame is coming). Idempotent.
  ///
  /// 精确还原 [enterStandby] 改动的内容。返回视频解码是否被重新启动（即接下来会有新的
  /// 首帧）。幂等。
  Future<bool> exitStandby();
}
```

### D4 — B/C 判定：音频存在性三态，来源是 media_kit 的轨道表 + 音频参数

- **轨道信息来源**：`Player.state.tracks.audio/video`（由 mpv `track-list` 解析，含 `auto`/`no` 两个伪轨）、
  `Player.state.track.audio`（当前选中）、`Player.state.audioParams.sampleRate`（由 mpv `audio-params` 解析，**音频解码器有输出才有值**）。
  三者每次 `open()` 都随 `PlayerState()` 重置（§0 #4），读到的就是当前文件。
- **为什么还要看 `audio-params`**：mova 用的瘦身版 libmpv 裁过解码器。"有音轨"但解码器打不开时，mpv 实际没有音频链；
  此时做 `vid=no` 就成了调研 §1.3 说的"`aid`/`vid` 全关 = 停读"，直播会停在原地、回来落后整段隐藏时长。只有"有音轨 **且**
  `sampleRate > 0`"才算 `present`。
- 判定写成纯函数（无 media_kit 类型，可单测），内核只负责把 media_kit 状态映射成字符串/整数喂进去：

```dart
/// Classifies audio presence from plain track facts. Pure; see [MovaAudioPresence].
///
/// 用朴素的轨道事实判定音频存在性。纯函数；见 [MovaAudioPresence]。
///
/// - [audioIds]/[videoIds]: track ids from mpv's track list (`auto`/`no` are pseudo tracks) / mpv 轨道表的 id（`auto`/`no` 是伪轨）
/// - [selectedAudio]: the selected audio id / 当前选中的音轨 id
/// - [sampleRate]: from `audio-params`; null until the audio decoder outputs / 来自 `audio-params`；音频解码器有输出前为 null
MovaAudioPresence movaAudioPresence({
  required Iterable<String> audioIds,
  required Iterable<String> videoIds,
  required String selectedAudio,
  required int? sampleRate,
}) {
  bool real(String id) => id != 'auto' && id != 'no';
  final audio = audioIds.where(real).toList();
  final loaded = audio.isNotEmpty || videoIds.any(real);
  if (!loaded) return MovaAudioPresence.unknown;
  if (selectedAudio == 'no' || audio.isEmpty) return MovaAudioPresence.absent;
  return (sampleRate ?? 0) > 0 ? MovaAudioPresence.present : MovaAudioPresence.unknown;
}
```

- **选组合**（`decideStandbyEntry`，D6 表）：`present` → B（`MovaStandbyMode.muted`）；`absent` → 按
  `MovaStandbyConfig.silentStreams`：`keepDecoding`（默认）→ C（`MovaStandbyMode.decodeOnly`），`pause` → 退回暂停；
  `unknown` → 退回暂停（`mediaUnknown`）。
- **HLS/DASH**：`format ∈ {'hls','dash'}` 且 `allowHls == false`（默认）→ 退回暂停（`hls`）。理由：可 seek 的 HLS 切回 `vid=auto` 会触发
  demuxer 的 refresh seek，是否回读网络、是否在直播窗口滑走后出问题都还没测（调研 §1.2、§3，Task 10 S2）。bingo 直播卡片走 HTTP-FLV，
  不受影响。`file-format` 的实际取值本身也要真机核对（S2）。

### D5 — 内核属性操作：保存 → 改写 → 精确还原；只碰 `mute` 与 `vid`

| 组合 | 进入（顺序） | 退出（顺序） | `exitStandby()` 返回 |
|---|---|---|---|
| B `muted` | 读 `mute`、读 `vid` → 写 `mute=yes` → 原 `vid != no` 时写 `vid=no` | 原 `vid != no` 时写回原 `vid` → 写回原 `mute` | 写回了 `vid` 则 `true` |
| C `decodeOnly` | 读 `mute` → 写 `mute=yes` | 写回原 `mute` | `false`（解码从未停） |

- **先静音、后拆视频**：避免拆视频那几十毫秒里漏声。**退出时先恢复视频、紧接着恢复声音**（不等首帧，Q7）。
- **绝不碰**：`volume`（Android 是系统音量，§0 #7）、`vo`/`wid`（§0 #5，会被 `widListener` 覆盖、`wid=0` 时有 SIGSEGV 风险）、
  `aid`（全关 = 停读）、`VideoController`（绝不销毁/重建，调研 §4.4）、`demuxer-*`/`cache-*`（二阶优化，调研 §1.6）。
- **原值为 `no` 的 `vid` 不动**：audioOnly 内核、懒创建且从未挂界面的内核，`vid` 原本就是 `no`，B 退化为"只静音"，退出返回 `false`，
  不会在没有渲染面的情况下开视频解码。
- **串行化**：内核自己用一条 Future 链串起 enter/exit，不会交错写属性；重复 `enterStandby` 幂等（已在待机直接返回 `true`）。
- **超时与回滚**：每次属性读写 `timeout(_standbyOpTimeout = 2s)`（待真机校准）；任一步失败 → 尽力还原已改的属性 → 返回 `false`，
  引擎退回暂停。已知残余风险：media_kit 的 `setProperty` 先 `await` 初始化再同步写原生，超时后底层写入仍可能晚到；D4 的判定
  （音频已在解码 / 轨道已加载）保证此时播放器早已初始化，`await` 实际立即返回，残余风险只剩理论上的。
- **销毁**：`dispose()` 不做还原（播放器整个销毁）；之后的 `exitStandby()` 不写任何属性、返回 `false`。
- **mpv 属性跨文件保留**：`vid`/`mute` 是全局选项，`loadfile` 不会重置（media_kit 本身就依赖这一点：初始化设一次 `vid=no`、控制器设一次
  `auto`，之后每次 `open` 都沿用）。所以待机中同一源的重载（换档、回边缘重开）会**自然保持**待机。**[文档/源码推断]**，Task 10 S13 核对。

### D6 — 状态机：`MovaState.standby`（四态）+ 两个事件

```dart
/// Where a player is in the standby lifecycle.
///
/// 播放器处于待机生命周期的哪一段。
enum MovaStandbyPhase {
  /// Not in standby (the default). 不在待机（默认）。
  off,
  /// Holding the stream: still playing, with video and/or sound off. 正在待机：仍在播放，画面和/或声音已关。
  holding,
  /// Standby was asked for but the engine paused instead (VOD, unknown media,
  /// HLS, silent stream with `pause`, kernel without the capability, or a
  /// hold that hit `maxDuration` / failed / ended).
  /// 请求了待机但引擎改为暂停（点播、媒体信息未知、HLS、配置为暂停的无声流、内核无此能力，
  /// 或待机超过 `maxDuration` / 失败 / 结束）。
  fallback,
  /// Standby ended; waiting for the first fresh frame. 待机已结束，等待第一帧新画面。
  resuming,
}

/// How a held stream is kept running. 被待机的流以何种方式维持。
enum MovaStandbyMode {
  /// Video decoding off, sound muted; audio keeps the clock (stream has audio).
  /// 关视频解码、静音；由音频维持时钟（流里有音频）。
  muted,
  /// Decoding and rendering go on, sound muted (stream has no audio).
  /// 继续解码与渲染、静音（流里没有音频）。
  decodeOnly,
}
```

`MovaStandbyReason`（事件与决策共用；标"仅决策"的三个只出现在 `decideStandbyEntry` 的返回里，不会出现在事件里）：

| 值 | 含义 | 出现在 |
|---|---|---|
| `requested` | 进入待机 | off/resuming → holding |
| `vod` / `hls` / `silentStream` / `mediaUnknown` / `unsupported` | 退回暂停的原因 | off → fallback |
| `maxDuration` / `failed` / `ended` | 待机中途退回暂停；`failed` 也用于"请求待机时 recovery 正有待执行的重试" | holding → fallback，或 off → fallback |
| `reloaded` | 待机请求存在期间宿主 `open()`/`reload()` 换源：以暂停态加载新源 | 任意 → fallback |
| `woke` | `setStandby(false)` 开始恢复 | holding/fallback → resuming，或 fallback → off（点播/短暂停直接续播/意图为 false） |
| `resumed` | 恢复完成（落地或超时） | resuming → off |
| `paused` | 宿主 `pause()` | 任意 → off |
| `already` / `exempt` / `notPlaying` | 仅决策：已在待机、画面在 pip/小窗、意图为 false | — |

**迁移表**（引擎实现；`decideStandbyEntry`/`decideStandbyWake` 是其中的纯判定部分）：

| 当前 | 触发 | 动作 | 新状态 |
|---|---|---|---|
| off | `setStandby(true)`，可待机 | 取消待执行的恢复（R2 的同一入口）；`kernel.enterStandby(mode)`；`disarm` 看门狗；起 `maxDuration` 计时 | holding |
| off | `setStandby(true)`，不可待机（含 recovery 有待执行重试 → `failed`） | 取消待执行的恢复；`kernel.pause()`（**不改** `intent`） | fallback |
| off | `setStandby(true)`，`intent` 为 false / pip / mini | 无（`intent` 为 false 时请求标记照记，之后 `play()` 直接以待机态开播） | off |
| holding | `maxDuration` 到点 | `kernel.pause()` → `kernel.exitStandby()` | fallback(`maxDuration`) |
| holding | 播放失败 / 直播结束 | 同上，不咨询 recovery 策略 | fallback(`failed`/`ended`) |
| holding | `setStandby(false)` | 武装恢复闸门 → `kernel.exitStandby()` → 看门狗回到卡顿监视 | resuming（解码未停则立即 off） |
| fallback | `setStandby(false)` | 见 D7/D9 的 `decideStandbyWake`：`intent` 为 false → 只归位；否则续播 / 回边缘 / 重开 | resuming 或 off |
| fallback(`reloaded`) | 新源首帧落地（`rendered` 变 true）且 `intent` 为 true、请求仍在 | 以 `intent: true` 再判定一次：能待机 → `enterStandby` 后 `kernel.play()` | holding，或保持 fallback |
| resuming | 首帧落地 / `resumeTimeout` | 发 `MovaStandbyResume` | off(`resumed`) |
| 任意非 off | `pause()` | `kernel.pause()` → holding 时再 `exitStandby()`；清除请求 | off(`paused`) |
| 任意（请求存在） | `open()`/`reload()` | holding 时先 `exitStandby()`；新源以 `play: false` 加载（`intent` 按 `autoPlay` 照常更新，留给唤醒用） | fallback(`reloaded`) |

```dart
/// The standby phase changed.
///
/// 待机阶段发生变化。
///
/// Example / 示例:
/// ```dart
/// api.events.listen((e) {
///   if (e is MovaStandbyChange && e.phase == MovaStandbyPhase.fallback) {
///     log('standby fell back to pause: ${e.reason.name}');
///   }
/// });
/// ```
class MovaStandbyChange extends MovaEvent {
  /// Creates the event. 创建事件。
  const MovaStandbyChange({required this.phase, required this.reason, this.mode});
  /// The new phase. 新阶段。
  final MovaStandbyPhase phase;
  /// Why it changed. 变化原因。
  final MovaStandbyReason reason;
  /// The hold mode: set when entering [MovaStandbyPhase.holding], and on the
  /// `resuming` that follows it; null otherwise.
  /// 待机组合：进入 holding 时、以及紧随其后的 resuming 时有值；其余为 null。
  final MovaStandbyMode? mode;
}

/// Standby ended and playback is presenting again: how long it took from the
/// wake-up call to the first fresh frame.
///
/// 待机结束、重新出画面：从唤醒调用到第一帧新画面花了多久。
///
/// Example / 示例:
/// ```dart
/// api.events.listen((e) {
///   if (e is MovaStandbyResume) log('back in ${e.elapsed.inMilliseconds}ms via ${e.signal?.name ?? 'none'}');
/// });
/// ```
class MovaStandbyResume extends MovaEvent {
  /// Creates the event. 创建事件。
  const MovaStandbyResume({required this.elapsed, this.signal, this.from});
  /// From `setStandby(false)` to the landing. 从 `setStandby(false)` 到落地的耗时。
  final Duration elapsed;
  /// What landed it: `restart`/`size` (precise), `buffering`/`progress`
  /// (after a reconnect), `grace` (nothing within `resumeTimeout` — elapsed is
  /// then the timeout, not a measurement), or null (decoding never stopped).
  /// 由什么落地：`restart`/`size`（精确）、`buffering`/`progress`（重连之后）、`grace`（`resumeTimeout`
  /// 内什么都没等到——此时 elapsed 就是超时值，不是测量值），或 null（解码从未停过）。
  final MovaFirstFrameSignal? signal;
  /// The hold mode woken from; null when woken from a [MovaStandbyPhase.fallback] pause.
  /// 从哪种待机组合醒来；从 fallback 暂停醒来时为 null。
  final MovaStandbyMode? from;
}
```

### D7 — 恢复计时：复用首帧闸门，加一个"恢复武装"模式；`rendered` 不动

- `MovaFirstFrameGate.arm({required bool autoPlay, bool resume = false})`：`resume: true` 时
  - **只认** `onRestart()` 与 `onSize(w>0,h>0)`，二者都**立即落地**（不看 `autoPlay`、不进 1.5s 宽限）；
  - `onBuffering`/`onProgress` 一律返回 `null`——待机期间位置一直在推进，按默认规则两个样本就会误落地（§0 #10）。
  - 默认 `resume: false`，既有行为与 HE Task 1 的 14 项断言逐字不变。
- 信号依据：`vid=auto` 后 mpv 新建解码器，出首帧时 `video-params` 重新可用，media_kit 再推一次宽高（§0 #3）；
  `PLAYBACK_RESTART` 在切轨时**多半不会发**（mpv 只在 seek/起播重置 `restart_complete`，**[推断]**），若真发了也权威落地。Task 10 S15 统计实际信号分布。
- 只有组合 B 且 `exitStandby()` 返回 `true`（确实重启了视频解码）才武装恢复闸门，并起 `resumeTimeout`（默认 5s，待真机校准：要覆盖
  4s GOP + 解码器初始化）；到点以 `signal: grace` 收尾并 `reset()` 闸门。C、audioOnly、`vid` 原本是 `no` → 立即收尾（`signal: null`）。
- **闸门先武装、再写属性**：`vid=auto` 写入后尺寸事件可能在 `mute` 写入的 `await` 期间就到达，晚武装会漏掉。
- 从 fallback 醒来走"回边缘/重开"时，用**普通武装**（那是一次真正的重新加载，buffering/progress 兜底都有效），落地同样记为
  `MovaStandbyResume`（`from: null`）——这正好给出"待机恢复 vs 暂停重连"的同口径对比数据。
- `MovaState.rendered` 全程不动，不发 `MovaFirstFrame`（那是"每次 `open()` 一次"的语义）。`elapsed` 起点是唤醒调用开始处
  （含属性写入耗时），终点是落地回调。

### D8 — 与宿主调用的交互（引擎内规则）

| 调用 | holding 时 | fallback 时 | 说明 |
|---|---|---|---|
| `pause()` | `kernel.pause()` → `exitStandby()` → off(`paused`)，清除请求，`intent` 置 false（R1 原逻辑） | `kernel.pause()` → off(`paused`)，清除请求 | 先停再恢复属性，恢复时不漏声。phase 为 off 且无请求时仍是 `=> _kernel.pause()` 原路径（R1 的意图记账照旧） |
| `play()` | `intent` 置 true（已是 true）；不调内核，保持待机 | `intent` 置 true；以 `intent: true` 重新判定：能待机 → `enterStandby` 后 `kernel.play()`；否则保持暂停 | **唤醒只有 `setStandby(false)` 一个入口**——隐藏期间程序性的 `play()`（广告、播放列表、swap 提交）不会让看不见的卡片出声（Q10）。phase 为 off 且请求存在（请求时 `intent` 为 false）→ 同 fallback 列 |
| `open()`/`reload()` | 请求存在：先 `exitStandby()`，新源以 `play:false` 加载 → fallback(`reloaded`)；新源首帧落地后若 `intent` 为 true 再尝试进 holding | 同左（无需 `exitStandby`） | 加载前必须还原：新源若无音频，带着 `vid=no` 加载会被 mpv 判"没有可播的流"直接失败。以暂停态加载是因为 R3 只在意图 false→true 时重新决策，待机中意图一直是 true，`open(autoPlay:true)` 不会触发它（Q9） |
| `seek()`/`seekBy()` | 照常，保持待机 | 照常，保持 fallback（暂停中 seek 不会开播） | 直播 DVR 场景 |
| `backToLiveEdge()`/`switchQuality()` | 照常，保持待机（同源重载，`vid`/`mute` 跨文件保留，D5）；`_loadKernel` 不武装起播期限 | 照常执行但**以 `play:false` 加载**（D9 的 `_loadPlays`），保持 fallback；唤醒时再按意图播放 | 二者按 R2 会取消待执行的恢复，与待机无冲突 |
| `setVolume()`/`setRate()`/`setFit()`… | 照常 | 照常 | `mute` 与 `volume` 独立；退出时恢复原 `mute`，新音量自然生效 |
| `setMini(true)`/`enterPip()` | 先走唤醒（`setStandby(false)`），再执行 | 同左 | 画面要在别处露出来了 |
| `dispose()` | 同步前缀里取消 `maxDuration`/`resumeTimeout` 计时器；不还原属性、不发事件 | 同左 | 照 HE Task 2/10 的"拆树后不留挂起 Timer" |

### D9 — 与 recovery / 看门狗 / ABR / 自动回边缘

- **进入待机（holding 或 fallback）先取消待执行的恢复**（R2 引入的同一取消入口，绑定会话世代 + 失败尝试编号）：否则一个排队中的重试会按
  R1 的意图（true）以 `play:true` 加载，在看不见的卡片里出声。请求待机时若恰有待执行重试（流正在失败中），直接 fallback(`failed`)，唤醒时重开。
- **fallback 期间"按意图加载"的路径一律不开播**：R1 让 recovery 重试/切备选按最新意图加载，而 fallback 时 `intent` 仍为 true（D1）。引擎在 R1 的
  意图读取点统一改读
  ```dart
  /// Whether an internal load should start playing: the play intent, except
  /// while standby holds the engine paused (fallback), where loads stay paused
  /// until the wake-up plays them.
  ///
  /// 内部加载完是否开播：即播放意图；但待机让引擎停在暂停态（fallback）期间一律不开播，
  /// 留到唤醒时再播。
  bool get _loadPlays => _playIntent && state.standby != MovaStandbyPhase.fallback;
  ```
  覆盖：recovery `_recover`、`switchQuality`、`_reopenLiveSource`（目前写死 `play: true`）、`_seekTimeshift`。唤醒时先把 phase 切到 `resuming` 再加载，
  所以唤醒路径读到的是 `true`。（`_playIntent` 为 R1 的字段，名字以落地代码为准。）
- **fallback 期间的失败**：kernel 已暂停，看门狗不计时；若仍收到 `_onPlayFail`（如原生 `END_FILE(error)`），只把 `_fallbackCause` 改为 `failed`，
  不咨询策略、不发事件——唤醒时据此强制重开。
- **holding 期间看门狗 `disarm()`**：不计起播期限、不计卡顿期限（隐藏时的缓冲不是用户体验）。
- **唤醒后**：B/C → `armStart(playing: _playIntent)` + `onLanded()` + `onBuffering(state.buffering)`，即直接回到"已出画面"的卡顿监视，
  **不重计起播期限**（播放从未停）；fallback 走重开的 → 由 `_loadKernel` 照常武装起播期限（HE Task 10 的既有路径）。
- **holding 期间的失败延后处理**：`_onPlayFail`（`nativeEndError`/`liveEnded`/`openThrew`）与 recovery 关闭时的直播 `completed`
  → 不咨询策略、不发 `MovaPlayFailure`，引擎 `pause` + `exitStandby` → fallback(`failed`/`ended`)。唤醒时 `decideStandbyWake` 对这两个原因
  **强制重开**（`_reopenLiveSource` → `_loadKernel` 武装起播期限），重开还不行再进入正常 recovery。理由：看不见的卡片在后台反复重连只烧流量（Q11）。
- **holding 期间同源重载**（宿主 `switchQuality`/`backToLiveEdge`）：`_loadKernel` 跳过 `armStart`（`state.standby == holding` 时）。
- **ABR**：`_handleAbrBuffering` 在 holding 时直接返回；唤醒时 `_abrPolicy.reset()`（隐藏期间的缓冲不代表当前档位扛不住）。
- **`autoBackToLiveOnStall`**：`_maybeAutoBackToLive` 在 holding 时直接返回。
- **从 fallback 醒来**（`decideStandbyWake`）：`intent` 为 false → 只把 phase 归位为 off，不播；点播 → `kernel.play()`，直接 off；
  直播：原因是 `failed`/`ended` → 重开；原因是 `maxDuration`，或其他原因（含 `reloaded`）且暂停已 ≥ `liveResumeGrace`（默认 3s，与守卫默认一致）→ 内部
  `_backToLiveEdge()`（不再走公开方法的待机规则）+ 未在播则 `kernel.play()`；否则 → `kernel.play()`，直接 off。
- **R4（续播位置跨失败保留）**：只影响点播；点播从不进 holding，fallback 唤醒是普通 `play()`，与 R4 无交集。直播重开不 seek。

### D10 — 守卫：`hiddenMode` + 两个新动作；进后台一律暂停

- `MovaAutoPauseConfig.hiddenMode`（`MovaHiddenMode.pause` 默认）；`==`/`hashCode` 并入。
- `MovaGuardAction` 追加 `standby`、`wake`（对宿主里无 `default` 的穷尽 switch 是编译期 breaking，未发布版本，CHANGELOG 注明，Q12）。
- `MovaAutoPauseGate.update(..., {bool standbyCapable = false})`：新可选参数默认 false，既有调用与 12 项既有断言不变。gate 内部把
  `_pausedByGate` 换成三值 `_owe {none, resume, wake}`（pause 模式下语义等价）：
  - 首次隐藏、隐藏前在播、非豁免：`hiddenMode == standby && live && standbyCapable && 本次原因不是 background` → `standby`（欠 `wake`）；否则 `pause`（欠 `resume`）。
  - 已因待机隐藏（欠 `wake`）时 `background` 到来 → `pause`（降级，改欠 `resume`；引擎 `pause()` 会顺带结束待机）。之后回到前台但仍有其他隐藏原因 → 不动作，
    保持暂停直到真正显示——不重新进待机。
  - 全部原因消失：欠 `wake` → `resumeOnShow ? wake : pause`；欠 `resume` → 既有 `resume`/`reloadEdge` 逻辑不变。
  - **R3 的重新决策扩展到待机**：R3 在"隐藏期间意图变 true"时让 gate 重新决策（pause 模式：暂停并记为隐藏前在播）。本计划只改它的**动作选择**：
    走与首次隐藏相同的 `_hideAction`——standby 模式、直播、可待机、原因不含 background → `standby`（欠 `wake`），否则 `pause`（欠 `resume`）。
    R3 的入口方法名/参数以评审修复落地为准，本计划只要求它也接收 `standbyCapable`（默认 false）。
- widget：`_set` 与 R3 的重新决策都传 `standbyCapable: api is MovaStandbyController`；`standby`/`wake` → `setStandby(true/false)`，对非能力 api 退化为
  `pause()`/`play()`。**`standby`/`wake` 与 R3 的直播恢复走同一套世代 + 可见性校验**：`await setStandby(true)` 返回后若 gate 已不再隐藏 → 补一次
  `setStandby(false)`；`await setStandby(false)` 返回后若又被隐藏 → 不补动作（gate 已为新的隐藏发出了 `standby`，引擎内部按队列串行，顺序天然正确）。
- **本计划不再自己做"隐藏期间换源重新施加"**（初稿的 `reapply`）：pause 模式由 R3 覆盖；standby 模式由引擎"请求跨 `open()` 保留、以暂停态加载"覆盖（D8）。
- `MovaView` 无新参数：`autoPause: MovaAutoPauseConfig(hiddenMode: MovaHiddenMode.standby)` 即可；默认工厂产出的 `MovaEngine` 天然具备能力。

### D11 — swap 引擎：透传 + 提交时同步待机意图

- `MovaSwapEngine implements MovaApi, MovaSwapController, MovaStandbyController`。`setStandby(on)` 记 `_standbyWanted = on`，转发给 `_active`
  （非能力 active 退化为 `pause()`/`play()`，返回 `off`）。`MovaState.standby` 与两个事件经既有 `_attach` 原样转发，无需改转发逻辑。
- `_commitNow` 在 `_standbyWanted` 时，**在给影子恢复音量与 `play()` 之前**先 `shadow.setStandby(true)`：影子意图为 true（在播）→ 直接进 holding；
  影子停在目标帧（`pauseWhenReady`，意图 false）→ 只记请求，随后的 `shadow.play()`（意图 false→true）以待机态开播。旧引擎照旧 `pause()`
  （holding 时顺带结束待机，随即被 dispose）。swap 代理自己不持有意图，意图属于各引擎（R1）。
- 不在待机时 `_commitNow` 逐字不变（断言锚定）。预热中的影子在隐藏期间仍会解码视频，属既有行为，不在本期优化（§5）。

### D12 — 其他组件

| 组件 | 规则 |
|---|---|
| feed 池 / `MovaFeedPlayer` | 不套守卫的待机，池不调用 `setStandby`（`focus()` 已管"只有一页出声"）；"邻近页保温"是二期（§5） |
| 系统 PiP / `MovaMini` | 入口判定 `pip || mini` → 不待机（`exempt`）；守卫同样豁免；holding 时 `setMini(true)`/`enterPip()` 先唤醒 |
| 封面（`MovaPlayer(poster:)`） | `MovaPosterLayer` 的判据追加 `|| standby == holding || standby == resuming`：待机即瞬间盖上，恢复落地后淡出（B 期间 Android 画面多半是黑的，§0 #1 `force-window`，Q6）。fallback 不盖（与 pause 模式一致，停在暂停帧） |
| App 进后台 | 守卫一律降级为 `pause`（D10）。命令式使用者需自己在进后台时 `pause()`，文档写明（系统会限网限 CPU，`widListener` 还会在 surface 回收时无条件 seek，调研 §1.5） |
| QoE（`MovaReporter`） | 本期不改 collector：待机期间 `playing` 为 true，`watchedMs` 照计、卡顿照计。README 注明（Q8） |
| 预览 / STT | 不受影响（预览按位置抽帧、STT 跟位置走，待机期间位置照常推进） |
| `MovaTestKernel`（`package:mova/testing.dart`） | 实现 `MovaStandbyKernel`，可编程 `hasAudio`/`fileFormat`，宿主能在 widget 测试里验待机（Task 8） |

### D13 — 默认值（真机数据出来前一律取保守值）

| 项 | 默认 | 理由 | 校准依据 |
|---|---|---|---|
| `MovaAutoPauseConfig.hiddenMode` | `pause` | 不改变现有行为，待机是 opt-in | — |
| `MovaStandbyConfig.maxDuration` | 30s | 调研 §5.3；超过多半是长离开，退回暂停更省 | **待真机校准**（S4 功耗/流量） |
| `MovaStandbyConfig.allowHls` | `false` | refresh seek 行为未验证 | **待真机校准**（S2/S5） |
| `MovaStandbyConfig.silentStreams` | `keepDecoding` | C 的安全变体不改任何渲染属性、零正确性风险，代价被 `maxDuration` 封顶；不省电但保住"秒回" | **待真机校准**（S3/S6），Q2 |
| `MovaStandbyConfig.resumeTimeout` | 5s | 覆盖 4s GOP + 解码器初始化 | **待真机校准**（S1） |
| `MovaStandbyConfig.liveResumeGrace` | 3s | 与守卫 `liveResumeGrace` 默认一致 | — |
| 内核属性读写超时 `_standbyOpTimeout` | 2s（私有常量） | 兜底，正常 <10ms | 待真机校准 |
| 点播 | 一律退回暂停 | 无边缘问题，待机无收益 | — |
| 进后台 | 一律暂停 | 调研 §2 末两行 | S8 |

---

## 2. 文件结构

**新建**

| 文件 | 职责 | Task |
|---|---|---|
| `lib/src/core/standby/standby.dart` | `MovaStandbyPhase`/`MovaStandbyMode`/`MovaStandbyReason`/`MovaStandbyController`（导出） | 1 |
| `lib/src/core/standby/plan.dart` | `MovaStandbyEntry`/`decideStandbyEntry`/`MovaStandbyWake`/`decideStandbyWake`/`movaSegmentedFormats`（不导出） | 1 |
| `lib/src/core/kernel/standby_kernel.dart` | `MovaAudioPresence`/`MovaStandbyMedia`/`MovaStandbyKernel`/`movaAudioPresence`（不进主 barrel） | 1 |
| `lib/src/core/options/standby_config.dart` | `MovaStandbyConfig`/`MovaSilentStandby`（经 `options.dart` 导出） | 1 |
| `example/lib/main_standby_verify.dart` | Task 10 专用验证页 | 9 |

**修改**

| 文件 | 改动 | Task |
|---|---|---|
| `lib/src/core/options/options.dart` | `standby` 节 + `copyWith`/`==`/`hashCode` + export | 1 |
| `lib/mova.dart` | 导出 `core/standby/standby.dart` | 1 |
| `test/core/openness_audio_test.dart` | 节清单追加 `'standby'`（唯一允许的既有测试改动） | 1 |
| `lib/src/core/kernel/mpv_kernel.dart` | **只增不改**：`implements MovaStandbyKernel` + 3 方法 + 私有字段 | 2 |
| `lib/src/core/state/state.dart` | `standby` 字段 + `copyWith`/`==`/`hashCode` | 3 |
| `lib/src/core/events/events.dart` | `MovaStandbyChange`、`MovaStandbyResume` | 3 |
| `lib/src/core/engine.dart` | `implements MovaStandbyController`；状态机；D8/D9 接线 | 3, 4, 5 |
| `lib/src/core/render/first_frame.dart` | `arm(resume:)` | 4 |
| `test/support/fake_kernel.dart` | **追加** `StandbyKernelStub` mixin、`FakeStandbyKernel`、`FakeStandbyStatsKernel`（既有类不动） | 3 |
| `lib/src/core/swap/swap_engine.dart` | `implements MovaStandbyController`；`_commitNow` 同步 | 6 |
| `test/support/fake_api.dart` | **追加** `FakeStandbyApi extends FakeMovaApi implements MovaStandbyController`（既有类不动） | 6 |
| `lib/src/core/guard/auto_pause.dart` | `MovaHiddenMode`、`hiddenMode`、`MovaGuardAction.standby/wake`、`standbyCapable`；R3 重新决策改走 `_hideAction` | 7 |
| `lib/src/ui/guard/auto_pause.dart` | 新动作执行（带 R3 的世代/可见性校验）、`standbyCapable` 传参 | 7 |
| `lib/src/ui/poster.dart` | 判据追加待机两态 | 8 |
| `lib/src/testing/test_kernel.dart` | `implements MovaStandbyKernel` | 8 |
| `README.md`/`CHANGELOG.md`/`doc/SPEC.md`/`CLAUDE.md` | 文档、基线 | 9 |

**测试数量推进**（基线 **1158**，见文首）：

| Task | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| 新增 | +28 | +9 | +14 | +14 | +15 | +5 | +16 | +5 | +3 | 0 |
| 累计 | 1186 | 1195 | 1209 | 1223 | 1238 | 1243 | 1259 | 1264 | **1267** | 1267 |

起点 1158 不含评审修复（R1–R4）新增的回归测试；修复落地后以实跑数为起点整体顺延，各 Task 的"新增"不变。

预计数只是规划值；落地 agent 以每个 Task 提交时**实跑**的 `flutter test` 数为准，按 CLAUDE.md 约定立即回写 `CLAUDE.md` 与本文件。

---

## 3. Global Constraints

- 包名 `mova`，公开类前缀 `Mova`；`src/` 内文件名不带前缀；事件不带 `Event` 后缀。
- **`lib/src/core/**` 禁止 `import 'package:flutter/...'`；`_mediaKitExceptions` 恒为 `{'kernel/mpv_kernel.dart'}`。** 决策、状态机、gate 全是纯 Dart。
- **`mpv_kernel.dart` 只增不改**（D3）：构造函数签名、既有方法体、既有字段不动；不新增构造参数。
- **`MovaApi`、`MovaKernel` 零新增成员**；`FakeKernel`/`FakeStatsKernel`/`FakeMovaApi` 类体不动（只在同文件**追加**新类/mixin）。
- 注释（CLAUDE.md）：每个类/方法/getter/字段都要注释，**先英文、空行、后中文**；公开 API 带参数/返回/示例。事件示例用 `listen` + `is`
  （`Stream` 上没有 `whereType`，HE 偏差清单）。
- `MovaStandbyConfig` 是含 `Duration` 的 `const` 值类：初始化列表**不能**写 Duration 比较的 assert，提供 `assertValid()`，由 `MovaEngine` 构造时调用（照 `MovaRecoveryConfig`）。
- **不新增任何第三方依赖。**
- **既有 1158 项一项不删、断言语义不放松。** 允许的既有测试改动只有 `openness_audio_test.dart` 节清单追加 `'standby'`（照 HE Task 9 先例）。
- 时间相关断言一律 `fake_async`，不 sleep；引擎测试里"在播"= 意图为 true（`open(autoPlay: true)` 或 `play()`，R1）再加 `kernel.emitPlaying(true)`
  让 `state.playing` 一致；专门验证"读意图不读 `state.playing`"的断言（Task 3 #8）故意让二者不一致。
- 草图里的 `_playIntent`、`_recoveryPending`/`_cancelRecovery()`、R3 的 `redecide`/`_visibleGen` 都是评审修复 R1–R3 的占位名，落地时替换为实际名字。
- 每个 Task 一个 commit（`feat(mova): …`/`test(mova): …`），`flutter analyze lib test` 0 issues + `flutter test` 全绿再往下走；提交后用实测数字回写基线。
- `MovaEvent` 是 `sealed`：新增 2 个子类；`MovaGuardAction` 新增 2 个值。对宿主无 `default` 的穷尽 switch 是编译期 breaking，CHANGELOG 注明（Q12）。
  mova 内部 `translateMovaEvent`（有 `default`）与 collector 不受影响；`ui/guard/auto_pause.dart` 的 switch 在 Task 7 同步补齐。
- **验收只依赖 analyze/test/纯逻辑/WidgetTester，不依赖真机。**

---

## Task 1：纯逻辑——类型、配置、音频判定、进入/唤醒决策

**Files:** Create `lib/src/core/standby/standby.dart`、`lib/src/core/standby/plan.dart`、`lib/src/core/kernel/standby_kernel.dart`、
`lib/src/core/options/standby_config.dart`；Modify `lib/src/core/options/options.dart`、`lib/mova.dart`、`test/core/openness_audio_test.dart`；
Test: `test/core/standby/config_test.dart`、`test/core/standby/plan_test.dart`、`test/core/kernel/audio_presence_test.dart`。

**Produces（公开面）：** D6 的 `MovaStandbyPhase`/`MovaStandbyMode`/`MovaStandbyReason`（逐值注释）、D3 的 `standby_kernel.dart` 全部、D4 的 `movaAudioPresence`，以及：

```dart
// core/standby/standby.dart

/// Engines that can keep a stream warm while their picture is hidden.
/// A capability next to [MovaApi] (like [MovaSwapController]); check with `is`.
///
/// 能在画面被隐藏时让流保持热态的引擎。与 [MovaApi] 并列的能力接口（同
/// [MovaSwapController]）；用 `is` 判断。
abstract class MovaStandbyController {
  /// Tells the engine its picture is hidden ([on] true) or visible again.
  ///
  /// Hidden: a playing live stream is held — still playing with video
  /// decoding off and sound muted (or, without audio, decoding on and
  /// muted) — for at most `MovaStandbyConfig.maxDuration`, then paused. When
  /// it cannot be held (VOD, HLS by default, unknown media, no kernel
  /// support) it is paused right away. Not playing, or shown in PiP / the
  /// mini window: nothing happens. Visible again: a held stream resumes
  /// decoding (no reconnect); a paused live stream resumes, or reconnects to
  /// the edge when it was paused long enough. Network is NOT saved while held.
  ///
  /// 告诉引擎它的画面被隐藏了（[on] 为 true）或又可见了。
  ///
  /// 隐藏：正在播放的直播流进入待机——仍在播放，但关视频解码并静音（无音频的流则继续解码并静音），
  /// 最长 `MovaStandbyConfig.maxDuration`，之后转为暂停。无法待机（点播、默认下的 HLS、媒体信息未知、
  /// 内核不支持）时立即暂停。没在播，或画面在画中画/小窗里：什么都不做。重新可见：待机中的流恢复解码
  /// （不重连）；暂停中的直播续播，暂停够久则重连到直播边缘。待机期间**不省流量**。
  ///
  /// - [on]: true = hidden, false = visible again / true 为隐藏，false 为重新可见
  ///
  /// Returns the phase once this call has settled (see `MovaState.standby`).
  ///
  /// 返回本次调用落定后的阶段（见 `MovaState.standby`）。
  ///
  /// Example / 示例:
  /// ```dart
  /// final api = createMovaEngine();
  /// if (api is MovaStandbyController) {
  ///   await api.setStandby(true);   // card scrolled away / 卡片滑走
  ///   await api.setStandby(false);  // back on screen / 回到屏幕
  /// }
  /// ```
  Future<MovaStandbyPhase> setStandby(bool on);
}
```

```dart
// core/options/standby_config.dart

/// What standby does with a stream that has no audio.
///
/// 待机如何处理没有音频的流。
enum MovaSilentStandby {
  /// Keep decoding and rendering, muted: instant resume, little power saved.
  ///
  /// 继续解码与渲染并静音：恢复即时，但几乎不省电。
  keepDecoding,

  /// Pause instead, as if standby were off for this stream.
  ///
  /// 改为暂停，就像这条流没开待机一样。
  pause,
}

/// Tuning for standby (`MovaStandbyController.setStandby`). Nothing here
/// turns standby on — it only takes effect once something calls `setStandby`
/// (e.g. `MovaAutoPauseConfig(hiddenMode: MovaHiddenMode.standby)`).
///
/// 待机的调参（`MovaStandbyController.setStandby`）。这里没有开关——只有当有人调用
/// `setStandby`（例如 `MovaAutoPauseConfig(hiddenMode: MovaHiddenMode.standby)`）时才生效。
///
/// Example / 示例:
/// ```dart
/// createMovaEngine(options: const MovaOpts(
///   standby: MovaStandbyConfig(maxDuration: Duration(seconds: 20)),
/// ));
/// ```
class MovaStandbyConfig {
  /// Creates the config; every default is conservative until measured on device.
  ///
  /// 创建配置；在真机测量前每个默认值都取保守值。
  ///
  /// - [maxDuration]: longest hold before falling back to a pause, default 30s / 待机最长时长，超过转暂停，默认 30s
  /// - [silentStreams]: what to do without audio, default [MovaSilentStandby.keepDecoding] / 无音频时怎么办
  /// - [allowHls]: hold HLS/DASH too, default false (they pause) / HLS/DASH 也待机，默认 false（暂停）
  /// - [resumeTimeout]: stop waiting for the first fresh frame after this, default 5s / 等新首帧的上限，默认 5s
  /// - [liveResumeGrace]: a live stream paused at least this long reconnects to the edge on wake, default 3s / 暂停至少这么久的直播唤醒时回边缘，默认 3s
  const MovaStandbyConfig({
    this.maxDuration = const Duration(seconds: 30),
    this.silentStreams = MovaSilentStandby.keepDecoding,
    this.allowHls = false,
    this.resumeTimeout = const Duration(seconds: 5),
    this.liveResumeGrace = const Duration(seconds: 3),
  });

  final Duration maxDuration;          // 各字段均需中英注释，此处略
  final MovaSilentStandby silentStreams;
  final bool allowHls;
  final Duration resumeTimeout;
  final Duration liveResumeGrace;

  /// Debug-checks the durations; called by the engine on construction.
  ///
  /// debug 下检查各时长；由引擎构造时调用。
  void assertValid() {
    assert(maxDuration > Duration.zero, 'maxDuration must be positive');
    assert(resumeTimeout > Duration.zero, 'resumeTimeout must be positive');
    assert(liveResumeGrace >= Duration.zero, 'liveResumeGrace must not be negative');
  }

  MovaStandbyConfig copyWith({...});   // 单字段替换
  // == / hashCode
}
```

```dart
// core/standby/plan.dart（不导出）

/// Demuxers treated as segmented (HLS/DASH) for `MovaStandbyConfig.allowHls`.
/// mpv's `file-format` values — to be confirmed on device (S2).
///
/// 在 `MovaStandbyConfig.allowHls` 里视为分片流（HLS/DASH）的 demuxer。取自 mpv 的
/// `file-format`——实际取值待真机确认（S2）。
const Set<String> movaSegmentedFormats = {'hls', 'dash'};

/// What `setStandby(true)` should do. 进入待机该做什么。
enum MovaStandbyEntryKind { hold, fallback, skip }

/// One entry decision. 一次进入判定。
class MovaStandbyEntry {
  const MovaStandbyEntry.hold(MovaStandbyMode this.mode) : kind = MovaStandbyEntryKind.hold, reason = MovaStandbyReason.requested;
  const MovaStandbyEntry.fallback(this.reason) : kind = MovaStandbyEntryKind.fallback, mode = null;
  const MovaStandbyEntry.skip(this.reason) : kind = MovaStandbyEntryKind.skip, mode = null;
  final MovaStandbyEntryKind kind;
  final MovaStandbyMode? mode;
  final MovaStandbyReason reason;
}

/// Decides how to enter standby. Pure; the order of checks is the contract.
///
/// 判定如何进入待机。纯函数；检查顺序即契约。
///
/// - [intent]: the engine's play intent (R1), not the kernel's playing flag / 引擎的播放意图（R1），不是内核回报的播放标志
/// - [recovering]: a recovery retry is pending (R2) / recovery 有待执行的重试（R2）
MovaStandbyEntry decideStandbyEntry({
  required MovaStandbyPhase phase,
  required bool intent,
  required bool exempt,
  required MovaStreamType type,
  required bool recovering,
  required bool kernelCapable,
  required MovaStandbyMedia? media,
  required MovaStandbyConfig config,
}) {
  if (phase == MovaStandbyPhase.holding || phase == MovaStandbyPhase.fallback) {
    return const MovaStandbyEntry.skip(MovaStandbyReason.already);
  }
  if (exempt) return const MovaStandbyEntry.skip(MovaStandbyReason.exempt);
  if (!intent) return const MovaStandbyEntry.skip(MovaStandbyReason.notPlaying);
  if (type != MovaStreamType.live) return const MovaStandbyEntry.fallback(MovaStandbyReason.vod);
  if (recovering) return const MovaStandbyEntry.fallback(MovaStandbyReason.failed);
  if (!kernelCapable) return const MovaStandbyEntry.fallback(MovaStandbyReason.unsupported);
  final m = media;
  if (m == null || m.audio == MovaAudioPresence.unknown) {
    return const MovaStandbyEntry.fallback(MovaStandbyReason.mediaUnknown);
  }
  if (!config.allowHls) {
    final f = m.format;
    if (f == null) return const MovaStandbyEntry.fallback(MovaStandbyReason.mediaUnknown);
    if (movaSegmentedFormats.contains(f)) return const MovaStandbyEntry.fallback(MovaStandbyReason.hls);
  }
  if (m.audio == MovaAudioPresence.present) return const MovaStandbyEntry.hold(MovaStandbyMode.muted);
  return config.silentStreams == MovaSilentStandby.keepDecoding
      ? const MovaStandbyEntry.hold(MovaStandbyMode.decodeOnly)
      : const MovaStandbyEntry.fallback(MovaStandbyReason.silentStream);
}

/// How `setStandby(false)` brings playback back. 唤醒如何恢复播放。
enum MovaStandbyWake {
  /// Nothing to do. 无事可做。
  none,
  /// Undo the kernel hold. 撤销内核待机。
  restore,
  /// Just mark standby over; nobody wants playback (intent false). 只把待机归位；没人想播（意图为 false）。
  settle,
  /// Plain `play()` (VOD, or a live pause shorter than the grace). 普通续播（点播，或短于宽限的直播暂停）。
  resumePlay,
  /// Back to the live edge, then play. 回直播边缘再播放。
  reloadEdge,
  /// Reopen the live source (the hold failed or the stream ended). 重开直播源（待机期间失败或结束）。
  reopen,
}

/// Decides how to wake. Pure. 判定如何唤醒。纯函数。
///
/// - [intent]: the play intent right now (R1) / 此刻的播放意图（R1）
MovaStandbyWake decideStandbyWake({
  required MovaStandbyPhase phase,
  required bool intent,
  required MovaStreamType type,
  required MovaStandbyReason? cause,
  required Duration pausedFor,
  required MovaStandbyConfig config,
}) {
  switch (phase) {
    case MovaStandbyPhase.off:
    case MovaStandbyPhase.resuming:
      return MovaStandbyWake.none;
    case MovaStandbyPhase.holding:
      return MovaStandbyWake.restore;   // holding 必然意图为 true（D8：pause() 会结束待机）
    case MovaStandbyPhase.fallback:
      if (!intent) return MovaStandbyWake.settle;
      if (type != MovaStreamType.live) return MovaStandbyWake.resumePlay;
      if (cause == MovaStandbyReason.failed || cause == MovaStandbyReason.ended) return MovaStandbyWake.reopen;
      if (cause == MovaStandbyReason.maxDuration || pausedFor >= config.liveResumeGrace) return MovaStandbyWake.reloadEdge;
      return MovaStandbyWake.resumePlay;
  }
}
```

`MovaOpts`：新增 `final MovaStandbyConfig standby;`（默认 `const MovaStandbyConfig()`），并入构造、`copyWith`、`==`、`hashCode`，
`export 'standby_config.dart'`。`MovaEngine` 构造期调用 `options.standby.assertValid()`（Task 3 落）。

**断言（28）：**
- config（5）：默认值全覆盖；`copyWith` 单字段替换；`==`/`hashCode`；`MovaOpts().standby == const MovaStandbyConfig()` 且 `MovaOpts.copyWith(standby:)` 不影响其他节；`assertValid()` 对 `maxDuration: Duration.zero` 触发 assert。
- audio presence（4）：无真实轨 → `unknown`；真实音轨 + `sampleRate: 48000` → `present`；真实音轨 + `sampleRate: null` → `unknown`；只有真实视频轨 → `absent`，`selectedAudio: 'no'` → `absent`。
- entry（12）：holding/fallback → `skip(already)`；`exempt` → `skip(exempt)`；`intent:false` → `skip(notPlaying)`；点播 → `fallback(vod)`；直播 + `recovering:true` → `fallback(failed)`（先于能力/媒体检查）；
  `kernelCapable:false` → `fallback(unsupported)`；`media: null` → `fallback(mediaUnknown)`；`present` + `flv` → `hold(muted)`；`absent` + 默认 → `hold(decodeOnly)`；
  `absent` + `silentStreams: pause` → `fallback(silentStream)`；`hls` 默认 → `fallback(hls)`、`allowHls:true` → `hold(muted)`、`format: null` 且 `allowHls:false` → `fallback(mediaUnknown)`（同一测试三个 expect）；
  `phase: resuming` 按 off 判定 → `hold(muted)`。
- wake（7）：off/resuming → `none`；holding → `restore`；fallback + `intent:false` → `settle`（不论原因与类型）；fallback + 点播 → `resumePlay`；fallback + 直播 + `failed`/`ended` → `reopen`；
  fallback + 直播 + `maxDuration`（`pausedFor` 为 0 也算）→ `reloadEdge`、`reloaded` 且 `pausedFor >= 3s` → `reloadEdge`；`mediaUnknown`/`reloaded` 且 `pausedFor < 3s` → `resumePlay`。

**验收：** `purity_test` 原样通过（新文件全部纯 Dart）；`openness_audio_test` 仅节清单多一项 `'standby'`；analyze 0；测试 **1186**。

---

## Task 2：内核实现——`MovaMpvKernel implements MovaStandbyKernel`

**Files:** Modify `lib/src/core/kernel/mpv_kernel.dart`（只增不改，D3）；Test: `test/core/kernel/mpv_kernel_standby_test.dart`
（照 `mpv_kernel_tls_test.dart` / `mpv_kernel_events_test.dart` 的 `Fake implements Player/NativePlayer` 写法：假 `NativePlayer` 记录
`getProperty/setProperty` 调用序列、可编程返回值/抛错/永不完成；假 `Player.state` 返回按 media_kit 1.2.6 `PlayerState`/`Tracks`/`Track`/`AudioParams` 构造的状态）。

**代码草图（追加在 `MovaStatsProbe` 一节之后，自成一节注释）：**

```dart
  // ---------------------------------------------------------------------
  // MovaStandbyKernel — hold the stream with video/sound off. Only `mute`
  // and `vid` are touched, saved first and restored verbatim; never
  // `volume` (a system-volume port may own it), `vo`/`wid` (media_kit's
  // Android widListener owns them) or the VideoController.
  //
  // MovaStandbyKernel——关掉画面/声音维持流。只碰 `mute` 与 `vid`，先保存、再原样还原；
  // 绝不碰 `volume`（可能归系统音量端口管）、`vo`/`wid`（归 media_kit 的 Android
  // widListener 管）以及 VideoController。
  // ---------------------------------------------------------------------

  /// Upper bound for one standby property read/write.
  ///
  /// 单次待机属性读写的上限。
  static const Duration _standbyOpTimeout = Duration(seconds: 2);

  /// Values saved by [enterStandby]; null when not in standby.
  ///
  /// [enterStandby] 保存的原值；不在待机时为 null。
  Map<String, String>? _standbySaved;

  /// Serializes enter/exit so property writes never interleave.
  ///
  /// 串行化进入/退出，使属性写入永不交错。
  Future<void> _standbyQueue = Future<void>.value();

  /// Runs [step] after every earlier standby step has settled.
  ///
  /// 在之前所有待机步骤落定后执行 [step]。
  Future<T> _standbySerial<T>(Future<T> Function() step) {
    final next = _standbyQueue.then((_) => step());
    _standbyQueue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  @override
  Future<MovaStandbyMedia> inspectStandby() async {
    final s = _player.state;
    final audio = movaAudioPresence(
      audioIds: s.tracks.audio.map((t) => t.id),
      videoIds: s.tracks.video.map((t) => t.id),
      selectedAudio: s.track.audio.id,
      sampleRate: s.audioParams.sampleRate,
    );
    return MovaStandbyMedia(audio: audio, format: await _readNativeProperty('file-format'));
  }

  @override
  Future<bool> enterStandby(MovaStandbyMode mode) => _standbySerial(() async {
        if (_disposed) return false;
        if (_standbySaved != null) return true; // 幂等
        final native = _player.platform;
        if (native is! NativePlayer) return false;
        try {
          final mute = await native.getProperty('mute').timeout(_standbyOpTimeout);
          final vid = mode == MovaStandbyMode.muted
              ? await native.getProperty('vid').timeout(_standbyOpTimeout)
              : null;
          _standbySaved = {'mute': mute, if (vid != null) 'vid': vid};
          await native.setProperty('mute', 'yes').timeout(_standbyOpTimeout);
          if (vid != null && vid != 'no') {
            await native.setProperty('vid', 'no').timeout(_standbyOpTimeout);
          }
          return true;
        } on Object {
          await _restoreStandby(native);
          return false;
        }
      });

  @override
  Future<bool> exitStandby() => _standbySerial(() async {
        final native = _player.platform;
        if (_disposed || native is! NativePlayer) {
          _standbySaved = null;
          return false;
        }
        return _restoreStandby(native);
      });

  /// Writes back whatever [_standbySaved] holds, video first; best effort.
  /// Returns whether `vid` went from `no` back to a real value.
  ///
  /// 把 [_standbySaved] 里的值写回，先视频后声音；尽力而为。返回 `vid` 是否从 `no` 恢复成了实际值。
  Future<bool> _restoreStandby(NativePlayer native) async {
    final saved = _standbySaved;
    _standbySaved = null;
    if (saved == null) return false;
    var restarted = false;
    final vid = saved['vid'];
    if (vid != null && vid != 'no') {
      try {
        await native.setProperty('vid', vid).timeout(_standbyOpTimeout);
        restarted = true;
      } on Object {}
    }
    final mute = saved['mute'];
    if (mute != null) {
      try {
        await native.setProperty('mute', mute).timeout(_standbyOpTimeout);
      } on Object {}
    }
    return restarted;
  }
```

`dispose()` **不改方法体**——`_disposed` 已在首行置位，之后 `enterStandby`/`exitStandby` 自然短路（`_standbySaved` 留着无害，对象随之丢弃）。
类注释第一段补一句"同时实现 `MovaStandbyKernel`"（文档注释的增补不算改方法体）。

**断言（9）：**
1. `inspectStandby()`：`state.tracks` 含真实音轨（id `'1'`）+ `audioParams.sampleRate: 44100`，`getProperty('file-format')` 返回 `'flv'` → `audio == present`、`format == 'flv'`。
2. `enterStandby(muted)`：调用序列恰为 `get mute`、`get vid`、`set mute=yes`、`set vid=no`，返回 `true`。
3. 随后 `exitStandby()`：序列 `set vid=auto`（读到的原值）、`set mute=no`，返回 `true`；再调一次 `exitStandby()` → 无写入、返回 `false`。
4. 原 `vid` 为 `no`（模拟 audioOnly/懒创建未挂界面）：进入不写 `vid`；退出只写 `mute`、返回 `false`。
5. `enterStandby(decodeOnly)`：只读写 `mute`，从不读写 `vid`；退出返回 `false`。
6. 连续两次 `enterStandby(muted)` → 只有一组写入（幂等）。
7. `setProperty('vid', 'no')` 抛错 → 返回 `false`，且之后有一次 `set mute=<原值>`（回滚）。
8. `getProperty('mute')` 永不完成（`fake_async` 推进 2s）→ 返回 `false`，不抛。
9. 平台不是 `NativePlayer` → `enterStandby` 返回 `false`、`inspectStandby().format == null`；`lazyVideo: true` 的内核进入/退出后 `screenshot()` 仍为 `null`（证明没有创建 `VideoController`）；`dispose()` 后 `exitStandby()` 无任何写入。

**验收：** `mpv_kernel_events_test`/`mpv_kernel_tls_test` 原样通过；`purity_test` 原样通过；`git diff` 中 `mpv_kernel.dart` 只有新增行与类注释增补；测试 **1195**。

---

## Task 3：引擎接线（一）——状态、事件、进入 / 退回暂停 / 超时 / 待播即待机

**Files:** Modify `lib/src/core/state/state.dart`、`lib/src/core/events/events.dart`、`lib/src/core/engine.dart`、
`test/support/fake_kernel.dart`（追加）；Test: `test/core/standby/engine_standby_enter_test.dart`、`test/core/state_test.dart`（增补 1）。

**Produces：** D6 的 `MovaStandbyChange`/`MovaStandbyResume`（后者在 Task 4 才会被发出，类在本 Task 一并加）；

```dart
// state.dart
/// Where this player is in the standby lifecycle; [MovaStandbyPhase.off]
/// unless someone called `MovaStandbyController.setStandby`.
///
/// 本播放器处于待机生命周期的哪一段；除非有人调用了
/// `MovaStandbyController.setStandby`，否则恒为 [MovaStandbyPhase.off]。
///
/// Example / 示例:
/// ```dart
/// MovaSelect<bool>(selector: (s) => s.standby != MovaStandbyPhase.off, builder: (_, held) => ...)
/// ```
final MovaStandbyPhase standby;
```

`hashCode` 把 `standby` 并入第一组 `Object.hash`（10 个参数，上限 20）。

**测试替身（追加，既有类不动）：**

```dart
/// Scriptable [MovaStandbyKernel] behavior shared by the standby fakes;
/// records `inspectStandby`/`enterStandby:<mode>`/`exitStandby` into [calls].
///
/// 待机假内核共享的可编程行为；把 `inspectStandby`/`enterStandby:<mode>`/`exitStandby` 记进 [calls]。
mixin StandbyKernelStub on FakeKernel implements MovaStandbyKernel {
  MovaStandbyMedia media = const MovaStandbyMedia(audio: MovaAudioPresence.present, format: 'flv');
  bool enterResult = true;
  bool exitRestartsVideo = true;
  MovaStandbyMode? heldMode;
  @override
  Future<MovaStandbyMedia> inspectStandby() async { calls.add('inspectStandby'); return media; }
  @override
  Future<bool> enterStandby(MovaStandbyMode mode) async {
    calls.add('enterStandby:${mode.name}');
    if (enterResult) heldMode = mode;
    return enterResult;
  }
  @override
  Future<bool> exitStandby() async {
    calls.add('exitStandby');
    final was = heldMode;
    heldMode = null;
    return was == MovaStandbyMode.muted && exitRestartsVideo;
  }
}
class FakeStandbyKernel extends FakeKernel with StandbyKernelStub {}
class FakeStandbyStatsKernel extends FakeStatsKernel with StandbyKernelStub {}
```

**引擎改动草图：**

```dart
class MovaEngine implements MovaApi, MovaStandbyController {
  // ---- standby（字段，均需中英注释）----
  MovaStandbyMode? _standbyMode;            // holding 时的组合
  DateTime? _standbySince;                  // 当前阶段开始时刻（fallback 宽限计算）
  MovaStandbyReason? _fallbackCause;        // fallback 的原因；其他阶段为 null
  bool _standbyRequested = false;           // setStandby(true) 之后、setStandby(false)/pause() 之前为 true（D1）
  Timer? _standbyTimer;                     // maxDuration
  Future<void> _standbyQueue = Future<void>.value(); // 串行化所有待机迁移

  MovaStandbyKernel? get _standbyKernel {
    final k = _kernel;
    return k is MovaStandbyKernel ? k as MovaStandbyKernel : null;
  }

  Future<T> _enqueueStandby<T>(Future<T> Function() step) {
    final next = _standbyQueue.then((_) => step());
    _standbyQueue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  void _setStandbyPhase(MovaStandbyPhase phase, MovaStandbyReason reason, {MovaStandbyMode? mode}) {
    if (_disposed || _events.isClosed) return;
    _standbySince = DateTime.now();
    _fallbackCause = phase == MovaStandbyPhase.fallback ? reason : null;
    _state.emit(state.copyWith(standby: phase));
    _events.add(MovaStandbyChange(phase: phase, reason: reason, mode: mode));
  }

  @override
  Future<MovaStandbyPhase> setStandby(bool on) {
    _standbyRequested = on;                       // 同步置位：之后排队执行的 play()/open() 能看到
    return _enqueueStandby(() => on ? _enterStandby(viaPlay: false) : _leaveStandby());
  }

  /// [viaPlay]: called from play()/a reloaded source's landing while a request
  /// stands — decide with intent true, and never pause (the caller plays only
  /// when this returns holding).
  ///
  /// [viaPlay]：请求存在期间由 play()/换源落地调用——按意图为 true 判定，且从不暂停
  /// （只有返回 holding 时调用方才播放）。
  Future<MovaStandbyPhase> _enterStandby({required bool viaPlay}) async {
    if (_disposed || !_standbyRequested) return state.standby;
    final k = _standbyKernel;
    MovaStandbyMedia? media;
    if (k != null) {
      try {
        media = await k.inspectStandby();
      } on Object {
        media = null;
      }
    }
    final current = state.standby;
    final entry = decideStandbyEntry(
      phase: viaPlay ? MovaStandbyPhase.off : current,
      intent: viaPlay || _playIntent,             // R1 的播放意图
      exempt: state.pip || state.mini,
      type: state.type,
      recovering: _recoveryPending,               // R2：有绑定当前会话世代的待执行恢复
      kernelCapable: k != null,
      media: media,
      config: options.standby,
    );
    switch (entry.kind) {
      case MovaStandbyEntryKind.skip:
        return state.standby;                     // notPlaying 时请求标记已在 setStandby 里记下
      case MovaStandbyEntryKind.fallback:
        _cancelRecovery();                        // R2 的取消入口：排队中的重试不能按意图开播
        _cancelResume();                          // Task 4 提供；本 Task 先放空实现
        if (viaPlay && current == MovaStandbyPhase.fallback) return current; // 仍不能待机：保持暂停，不重复发事件
        if (!viaPlay) await _kernel.pause();      // 不改 _playIntent（D1）
        _setStandbyPhase(MovaStandbyPhase.fallback, entry.reason);
        return state.standby;
      case MovaStandbyEntryKind.hold:
        _cancelRecovery();
        _cancelResume();
        final ok = await k!.enterStandby(entry.mode!);
        if (_disposed) return MovaStandbyPhase.off;
        if (!ok) {
          if (!viaPlay) await _kernel.pause();
          _setStandbyPhase(MovaStandbyPhase.fallback, MovaStandbyReason.unsupported);
          return state.standby;
        }
        _standbyMode = entry.mode;
        _watchdog?.disarm();
        _standbyTimer?.cancel();
        _standbyTimer = Timer(options.standby.maxDuration, _expireStandby);
        _setStandbyPhase(MovaStandbyPhase.holding, MovaStandbyReason.requested, mode: entry.mode);
        return state.standby;
    }
  }

  /// maxDuration elapsed: stop first, then restore properties while paused.
  void _expireStandby() {
    _standbyTimer = null;
    unawaited(_enqueueStandby(() => _degradeStandby(MovaStandbyReason.maxDuration)));
  }

  /// holding → fallback(reason): pause, undo the kernel hold. No-op otherwise.
  Future<void> _degradeStandby(MovaStandbyReason reason) async {
    if (_disposed || state.standby != MovaStandbyPhase.holding) return;
    _standbyTimer?.cancel();
    _standbyTimer = null;
    await _kernel.pause();
    await _standbyKernel?.exitStandby();
    _standbyMode = null;
    _setStandbyPhase(MovaStandbyPhase.fallback, reason);
  }
```

`play()` 的待机分支（`beforePlay` 拦截与 R1 的"意图置 true"之后、既有内核调用之前；`!_standbyRequested && state.standby == off` 时直接落到原逻辑，逐字不变）：

```dart
    final phase = state.standby;
    if (phase == MovaStandbyPhase.holding) return;            // 已在播（静音无画），保持待机
    if (_standbyRequested && phase != MovaStandbyPhase.resuming) {
      final p = await _enqueueStandby(() => _enterStandby(viaPlay: true));
      if (p == MovaStandbyPhase.holding) await _kernel.play();
      return;                                                  // 判定不能待机：保持暂停（隐藏中）
    }
```

`_recoveryPending`/`_cancelRecovery()`：R2 引入的"有绑定当前会话世代的待执行恢复"判断与取消入口；R2 落地时若没有现成的判断 getter，就在本 Task
按它的世代/尝试编号字段补一个只读 getter（不改 R2 的语义）。`_playIntent` 同理取 R1 的字段。

构造期：`options.standby.assertValid();`。`dispose()` 同步前缀追加 `_standbyTimer?.cancel(); _standbyTimer = null;`。
本 Task 的 `_leaveStandby()` 先放最小实现（holding → `exitStandby` → off(`woke`)），Task 4 换成完整版。

**断言（14，`fake_async` + `FakeStandbyKernel`；"在播的直播"= `open(MovaSource(u, type: live))`（R1：意图 true）后 `emitPlaying(true)`）：**
1. `state_test`：`MovaState().standby == MovaStandbyPhase.off`；`copyWith(standby:)`、`==`、`hashCode` 覆盖新字段。
2. `FakeKernel`（无能力）在播直播 → `setStandby(true)` 返回 `fallback`；内核 `calls` 末尾为 `pause`；恰一条 `MovaStandbyChange(fallback, unsupported)`。
3. `FakeStandbyKernel`（默认 present/flv）→ 返回 `holding`；`calls` 含 `inspectStandby`、`enterStandby:muted`，**不含** `pause`；`state.standby == holding`；事件 `(holding, requested, mode: muted)`。
4. `media: absent` → `holding` + `enterStandby:decodeOnly`；同条件 `MovaOpts(standby: MovaStandbyConfig(silentStreams: pause))` → `fallback(silentStream)`。
5. `media: unknown` → `fallback(mediaUnknown)` + `pause`。
6. `format: 'hls'` → `fallback(hls)`；`allowHls: true` → `holding`。
7. 点播在播 → `fallback(vod)` + `pause`，从不调 `inspectStandby` 之外的待机内核方法。
8. `open(autoPlay: false)`（意图 false）→ `setStandby(true)` 返回 `off`，无事件、无 `enterStandby`；随后 `play()` → `calls` 中 `enterStandby:muted` 出现在 `play` **之前**，`state.standby == holding`。
   内核回报 `emitPlaying(false)`（如缓冲中系统暂停）但意图仍为 true 时 `setStandby(true)` 照常进 holding（证明读的是意图）。
9. `emitMini(true)`/`state.pip` 为 true（`FakePip.enter` 返回 true 后）→ `setStandby(true)` 返回 `off`；`setStandby(false)` 后 `play()` 走普通路径（`calls` 只多 `play`）。
10. holding 后推进 30s → `calls` 依次为 `pause`、`exitStandby`；`state.standby == fallback`；事件 `(fallback, maxDuration)`；意图仍为 true。
11. 连续两次 `setStandby(true)` → `enterStandby:muted` 恰一次；第二次返回 `holding`。`setStandby(true)` 紧跟 `setStandby(false)`（不 await）→ 最终 off，无 `enterStandby`。
12. `enterResult = false` → `pause` + `fallback(unsupported)`。
13. recovery 开启：`openError` 让首次加载失败、重试在 1s 延迟中 → `setStandby(true)` → `fallback(failed)`；推进 2s → 内核**没有**第二次 `open`（待执行恢复已取消）。
14. holding 中 `dispose()` → 推进 60s 无异常、无事件、无 `exitStandby`；测试结束无挂起 Timer。

**验收：** 既有 `engine_test`/`first_frame_engine_test`/`engine_recovery_test` 全部原样通过；测试 **1209**。

---

## Task 4：引擎接线（二）——唤醒与恢复计时（首帧闸门 `resume` 武装）

**Files:** Modify `lib/src/core/render/first_frame.dart`、`lib/src/core/engine.dart`；
Test: `test/core/render/first_frame_test.dart`（增补 3）、`test/core/standby/engine_standby_wake_test.dart`。

**闸门（向后兼容）：**

```dart
  /// Arms a fresh attempt; [autoPlay] false enables the size fallback.
  /// [resume] true arms a standby-resume attempt instead: only a native
  /// restart or a non-zero size lands it, immediately (no grace, regardless
  /// of [autoPlay]); buffering and position are ignored because playback kept
  /// moving during standby.
  ///
  /// 武装一次新尝试；[autoPlay] 为 false 时启用尺寸兜底。[resume] 为 true 时改为武装一次
  /// 待机恢复尝试：只有原生 RESTART 或非零尺寸能让它落地，且立即落地（不进宽限、不看
  /// [autoPlay]）；缓冲与位置一律忽略，因为待机期间播放一直在走。
  void arm({required bool autoPlay, bool resume = false}) {
    reset();
    _armed = true;
    _autoPlay = autoPlay;
    _resume = resume;
  }
  // onBuffering / onProgress：if (_resume) return null;
  // onSize：if (_resume) return (w > 0 && h > 0) ? _land(MovaFirstFrameSignal.size) : null;
  // reset() 里 _resume = false。
```

**引擎草图：**

```dart
  Timer? _resumeTimer;                // resumeTimeout
  DateTime? _resumeAt;                // 唤醒开始时刻
  MovaStandbyMode? _resumeFrom;       // 从哪种组合醒来；fallback 醒来为 null
  bool _resumeGateArmed = false;      // 闸门当前是否处于 resume 武装

  Future<MovaStandbyPhase> _leaveStandby() async {
    final phase = state.standby;                    // _standbyRequested 已在 setStandby(false) 里同步清除
    final since = _standbySince;
    final wake = decideStandbyWake(
      phase: phase,
      intent: _playIntent,                          // R1：按意图决定出不出画面
      type: state.type,
      cause: _fallbackCause,
      pausedFor: since == null ? Duration.zero : DateTime.now().difference(since),
      config: options.standby,
    );
    switch (wake) {
      case MovaStandbyWake.none:
        return phase;
      case MovaStandbyWake.restore:
        _standbyTimer?.cancel();
        _standbyTimer = null;
        final from = _standbyMode;
        _standbyMode = null;
        _beginResume(from: from);
        if (from == MovaStandbyMode.muted) _armResumeGate();      // 先武装，再写属性（D7）
        final restarted = await (_standbyKernel?.exitStandby() ?? Future<bool>.value(false));
        _resumeWatch();
        if (!restarted) _finishResume(null);
        return state.standby;
      case MovaStandbyWake.settle:
        _setStandbyPhase(MovaStandbyPhase.off, MovaStandbyReason.woke);   // 意图为 false：不播、不出新画面
        return state.standby;
      case MovaStandbyWake.resumePlay:
        _setStandbyPhase(MovaStandbyPhase.off, MovaStandbyReason.woke);
        await _kernel.play();
        _resumeWatch();
        return state.standby;
      case MovaStandbyWake.reloadEdge:
        _beginResume(from: null);
        _armAttempt(autoPlay: true);                                // 普通武装：这是一次真正的重新加载/seek
        final reopened = await _backToLiveEdge();
        if (!_lastPlaying) await _kernel.play();
        if (!reopened) _resumeWatch();                              // 重开时由 _loadKernel 武装起播期限
        return state.standby;
      case MovaStandbyWake.reopen:
        _beginResume(from: null);
        await _reopenLiveSource();
        return state.standby;
    }
  }

  void _beginResume({required MovaStandbyMode? from}) {
    _resumeAt = DateTime.now();
    _resumeFrom = from;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(options.standby.resumeTimeout, () {
      _resumeTimer = null;
      if (_resumeGateArmed) _frameGate.reset();
      _finishResume(MovaFirstFrameSignal.grace);
    });
    _setStandbyPhase(MovaStandbyPhase.resuming, MovaStandbyReason.woke, mode: from);
  }

  void _armResumeGate() {
    _graceTimer?.cancel();
    _graceTimer = null;
    _frameGate.arm(autoPlay: true, resume: true);
    _resumeGateArmed = true;
  }

  void _finishResume(MovaFirstFrameSignal? signal) {
    if (state.standby != MovaStandbyPhase.resuming) return;
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _resumeGateArmed = false;
    final at = _resumeAt;
    _events.add(MovaStandbyResume(
      elapsed: at == null ? Duration.zero : DateTime.now().difference(at),
      signal: signal,
      from: _resumeFrom,
    ));
    _setStandbyPhase(MovaStandbyPhase.off, MovaStandbyReason.resumed);
  }

  /// Drops a pending resume measurement (hidden again / host took over).
  void _cancelResume() {
    _resumeTimer?.cancel();
    _resumeTimer = null;
    if (_resumeGateArmed) _frameGate.reset();
    _resumeGateArmed = false;
  }

  /// Back to normal monitoring after standby: stall watch, no start deadline.
  void _resumeWatch() {
    _abrPolicy.reset();
    final wd = _watchdog;
    if (wd == null) return;
    wd
      ..armStart(playing: _playIntent)
      ..onLanded()
      ..onBuffering(state.buffering);
  }
```

`reloadEdge`/`reopen` 两条唤醒路径在加载前已把 phase 切到 `resuming`，D9 的 `_loadPlays` 因而为 true，重开后照常开播。

- `_onAttemptLanded` 开头插入：`if (state.standby == MovaStandbyPhase.resuming) _finishResume(signal);`（其后既有逻辑不变；`rendered` 已为 true 时照旧不发 `MovaFirstFrame`）。
- 公开 `backToLiveEdge()` 拆出私有 `Future<bool> _backToLiveEdge()`（返回是否走了 `_reopenLiveSource`），公开方法 = 待机规则（Task 5）+ 调它 + 原有的 `clearTimeshift`/`MovaLiveEdgeReach`；
  `_leaveStandby` 调私有版，同样补发 `clearTimeshift`/`MovaLiveEdgeReach`（与公开方法行为一致）。
- `dispose()` 同步前缀追加 `_resumeTimer?.cancel(); _resumeTimer = null;`。

**断言（14）：**
- 闸门（3，`first_frame_test.dart`）：`arm(autoPlay:true, resume:true)` 后 buffering true→false 与位置 40→80→120ms 均不落地；`onSize(1280,720, nativeLive:true)` 立即落地为 `size`（不进宽限、`awaitingGrace` 仍 false）；`onRestart()` 落地为 `restart`，之后再 `arm(autoPlay:true)`（默认）恢复 HE Task 1 的规则（buffering 下降沿可落地）。
- 引擎（11，`fake_async`）：
  1. holding(muted) → `setStandby(false)` 返回 `resuming`；`calls` 末尾 `exitStandby`；之后 `emitSize(1280,720)` → 恰一条 `MovaStandbyResume(signal: size, from: muted)`，`state.standby == off`，事件序列 `…(resuming, woke, muted) → Resume → (off, resumed)`；**没有** `MovaFirstFrame`，`rendered` 仍为 true。
  2. `exitRestartsVideo = false` → `setStandby(false)` 完成时已是 `off`，`MovaStandbyResume.signal == null`。
  3. decodeOnly → 唤醒即 off，`signal == null`，不武装闸门（之后 `emitSize` 不产生第二条 Resume）。
  4. `FakeStandbyStatsKernel` + `nativeRestartAvailable = true`：唤醒后 `emitRestart()` → `signal: restart`；推进 1500ms 无宽限残留事件。
  5. 唤醒后只推位置 0→40→80→120ms → 仍为 `resuming`；推进 5s → `MovaStandbyResume(signal: grace)`，`elapsed == 5s`；之后 `emitSize` 不再产生事件。
  6. holding 推进 30s 进入 `fallback(maxDuration)`（默认直播配置：`seekEnd` 且不可拖动 → 重开路径）→ `setStandby(false)` → 内核 `open` 收到当前地址（`openedUris` 末尾）、`play: true`；`emitBuffering(true)`→`false` → `MovaStandbyResume(signal: buffering, from: null)`；另有 `MovaLiveEdgeReach`。
  7. `fallback(mediaUnknown)` 后 1s 内唤醒 → `calls` 只多 `play`、无 `open`；直接 `(off, woke)`，无 `MovaStandbyResume`。
  8. 同上但推进 3s 后唤醒 → 走回边缘（`open`）且有 `MovaStandbyResume`。
  9. 点播 `fallback(vod)` → 唤醒 → `play`，直接 off，无 Resume。
  10. recovery 开启（`stallTimeout: 10s`）：holding 期间 `emitBuffering(true)` 推进 20s → 无 `MovaPlayFailure`；唤醒并落地后仍在缓冲 → 推进 10s → `MovaPlayFailure(stallTimeout)`（证明回到卡顿监视而非起播期限：推进 `startTimeout` 之前没有 `startTimeout` 失败）。
  11. `fallback(maxDuration)` 后宿主 `open(同源, autoPlay: false)`（意图 false，fallback(`reloaded`)）→ `setStandby(false)` → `(off, woke)`，内核无 `play`、无额外 `open`（`settle`）。

**断言总数（13 → 14）：** 闸门 3 + 引擎 11。

**验收：** HE Task 1/2 的 27 项闸门与首帧断言原样通过；测试 **1223**。

---

## Task 5：引擎接线（三）——与宿主调用、recovery、ABR、自动回边缘的交互规则（D8/D9）

**Files:** Modify `lib/src/core/engine.dart`；Test: `test/core/standby/engine_standby_rules_test.dart`。

**改动草图：**

```dart
  @override
  Future<void> pause() {
    // R1 的"意图置 false"保持在原位置（评审修复已有）。
    if (!_standbyRequested && state.standby == MovaStandbyPhase.off) return _kernel.pause(); // 原路径逐字不变
    _standbyRequested = false;
    return _pauseOutOfStandby();
  }

  Future<void> _pauseOutOfStandby() async {
    await _kernel.pause();                                          // 先停，再还原属性：不漏声
    await _enqueueStandby(() => _dropStandby(MovaStandbyReason.paused));
  }

  /// Leaves standby without waking: undo the hold if any, phase → off.
  ///
  /// 不唤醒地离开待机：有内核待机就撤销，phase 归 off。
  Future<void> _dropStandby(MovaStandbyReason reason) async {
    final phase = state.standby;
    if (phase == MovaStandbyPhase.off) return;
    _standbyTimer?.cancel();
    _standbyTimer = null;
    _cancelResume();
    if (phase == MovaStandbyPhase.holding) await _standbyKernel?.exitStandby();
    _standbyMode = null;
    _setStandbyPhase(MovaStandbyPhase.off, reason);
    _resumeWatch();
  }

  /// A new source arrives while standby is requested: undo any hold (a silent
  /// new source must not load with `vid=no`), then mark fallback so it loads
  /// paused. Returns whether the load must stay paused.
  ///
  /// 待机请求存在时来了新源：先撤销内核待机（无声新源不能带着 `vid=no` 加载），再标为
  /// fallback 使其以暂停态加载。返回本次加载是否必须保持暂停。
  Future<bool> _standbyBeforeOpen() {
    if (!_standbyRequested) return Future<bool>.value(false);
    return _enqueueStandby(() async {
      _standbyTimer?.cancel();
      _standbyTimer = null;
      _cancelResume();
      if (state.standby == MovaStandbyPhase.holding) await _standbyKernel?.exitStandby();
      _standbyMode = null;
      _setStandbyPhase(MovaStandbyPhase.fallback, MovaStandbyReason.reloaded);
      return true;
    });
  }

  /// The reloaded source showed its first frame while still hidden: try once
  /// to hold it instead of keeping it paused.
  ///
  /// 换来的新源在隐藏中出了首帧：尝试一次改为待机，而不是一直暂停。
  void _maybeUpgradeReloaded() {
    if (!_standbyRequested || !_playIntent) return;
    if (state.standby != MovaStandbyPhase.fallback || _fallbackCause != MovaStandbyReason.reloaded) return;
    unawaited(_enqueueStandby(() async {
      final p = await _enterStandby(viaPlay: true);
      if (p == MovaStandbyPhase.holding) await _kernel.play();
    }));
  }
```

接线点：
- `open()`：世代号检查通过后、`_armAttempt`/`_loadKernel` 之前 `final held = await _standbyBeforeOpen(); if (gen != _openGen) return;`；
  `_armAttempt(autoPlay: held ? false : autoPlay)` 与 `_loadKernel(source.uri, play: held ? false : autoPlay)`（以暂停态加载时闸门启用尺寸兜底）。
  R1 的意图仍按 `autoPlay` 更新（留给唤醒/升级用）。`reload()` 经 `open()` 覆盖。
- `_onAttemptLanded`：在 `rendered` 由 false 变 true、发出 `MovaFirstFrame` 之后调 `_maybeUpgradeReloaded()`。
- `backToLiveEdge()` / `switchQuality()` / `_reopenLiveSource()` / `_seekTimeshift()` / recovery 的 `_recover()`：加载时 `play:` 一律改读 D9 的 `_loadPlays`
  （fallback 期间不开播；holding 与 off 时即意图）。不结束待机。
- `setMini(true)` / `enterPip()`：`if (state.standby != MovaStandbyPhase.off) await setStandby(false);`（`setMini` 放在幂等检查之后）。
- `_loadKernel`：`if (_kernelOpening == 0 && !_disposed && state.standby != MovaStandbyPhase.holding) _watchdog?.armStart(playing: play);`
- `_handleAbrBuffering`、`_maybeAutoBackToLive`：首行 `if (state.standby == MovaStandbyPhase.holding) return;`
- `_onPlayFail`：在 `wd == null || src == null || …` 检查之后插入
  ```dart
  if (state.standby == MovaStandbyPhase.holding) {
    unawaited(_enqueueStandby(() => _degradeStandby(MovaStandbyReason.failed)));
    return;
  }
  if (state.standby == MovaStandbyPhase.fallback) {
    _fallbackCause = MovaStandbyReason.failed;   // 不咨询策略、不发事件；唤醒时强制重开
    return;
  }
  ```
- `_completedSub`：`if (v && state.standby == MovaStandbyPhase.holding) { unawaited(_enqueueStandby(() => _degradeStandby(MovaStandbyReason.ended))); } else if (v && live && liveEndIsFailure) _onPlayFail(liveEnded);`（`MovaDone` 照发）。

**断言（15）：**
1. holding → `pause()`：`calls` 依次 `pause`、`exitStandby`；`(off, paused)`；之后 `play()` 走普通路径（请求已清除，`calls` 只多 `play`）。
2. 从未待机的引擎 `pause()`：`calls` 只多一个 `pause`（与改前一致），无待机事件。
3. holding → `play()`：`calls` 不增 `play`，仍 holding。
4. `fallback(mediaUnknown)` 后把 `media` 改为 present → `play()` → `enterStandby:muted` 在 `play` 之前，进入 holding；若仍 unknown → 无 `play`、仍 fallback、不重复发事件。
5. holding → `open(新直播源, autoPlay: true)`：`exitStandby` 出现在新的 `open` **之前**；新 `open` 的 `lastPlay == false`；`(fallback, reloaded)`；
   随后 `emitSize(1280,720)`（暂停态尺寸兜底落地，`MovaFirstFrame` 照发）→ `calls` 追加 `enterStandby:muted`、`play` → `holding`。
6. holding → `reload()`，`media` 为 absent 且 `silentStreams: pause` → 以暂停态加载、落地后升级失败 → 保持 `fallback`、内核无 `play`。
7. holding → `setMini(true)`：先 `(resuming, woke)`，`state.mini == true`。
8. holding → `enterPip()`（`FakePip` 返回 true）：同样先唤醒。
9. holding → `seek(…)`（DVR 可拖动直播）与 `backToLiveEdge()`（重开路径）：无 `exitStandby`，仍 holding，重开 `lastPlay == true`；recovery 开启时推进超过 `startTimeout` 无 `MovaPlayFailure`。
10. `fallback(maxDuration)` → 宿主 `backToLiveEdge()`（重开路径）与 `switchQuality(…)` → 内核 `open` 的 `lastPlay == false`，仍 fallback；之后唤醒 → `play`。
11. ABR 开启 + `debugSetQualities` + holding 中缓冲反复跨阈值 → 无 `MovaAbrDownShift`、内核无额外 `open`；`autoBackToLiveOnStall: true` + 时移中 holding 缓冲 → 无额外 `open`/`seek`。
12. recovery 开启 + holding → `FakeStandbyStatsKernel.emitEndFile(error)` → 无 `MovaPlayFailure`；`calls` 末尾 `pause`、`exitStandby`；`(fallback, failed)`；唤醒 → 内核 `open` 当前地址（强制重开，即使不足 3s）。
13. recovery 开启 + `fallback(mediaUnknown)` → `emitEndFile(error)` → 无 `MovaPlayFailure`、无新的 `open`；1s 内唤醒 → 仍强制重开（原因已改为 `failed`）。
14. recovery 关闭 + 直播 holding → `emitCompleted(true)` → `MovaDone` 照发 + `(fallback, ended)`。
15. holding → `setVolume(50)` → 内核 `setVolume`，无 `exitStandby`，仍 holding，`state.volume == 50`。

**验收：** HE Task 10/11 的 recovery/failover 26 项与评审修复新增的回归测试原样通过；测试 **1238**。

---

## Task 6：swap 引擎——透传与提交时同步（D11）

**Files:** Modify `lib/src/core/swap/swap_engine.dart`、`test/support/fake_api.dart`（追加 `FakeStandbyApi`）；Test: `test/core/swap/swap_standby_test.dart`。

```dart
// fake_api.dart（追加）
/// A [FakeMovaApi] that also answers `setStandby`, recording `setStandby:<on>` into [calls].
/// 兼具 `setStandby` 的 [FakeMovaApi]，把 `setStandby:<on>` 记进 [calls]。
class FakeStandbyApi extends FakeMovaApi implements MovaStandbyController {
  MovaStandbyPhase answerOn = MovaStandbyPhase.holding;
  @override
  Future<MovaStandbyPhase> setStandby(bool on) async {
    calls.add('setStandby:$on');
    return on ? answerOn : MovaStandbyPhase.off;
  }
}
```

```dart
// swap_engine.dart
class MovaSwapEngine implements MovaApi, MovaSwapController, MovaStandbyController {
  /// The host's latest standby wish, re-applied to whichever engine becomes active.
  ///
  /// 宿主最近一次的待机意图，会重新施加到成为生效引擎的那一个上。
  bool _standbyWanted = false;

  @override
  Future<MovaStandbyPhase> setStandby(bool on) async {
    _standbyWanted = on;
    final a = _active;
    if (a is MovaStandbyController) return (a as MovaStandbyController).setStandby(on);
    if (on) {
      await a.pause();
    } else {
      await a.play();
    }
    return MovaStandbyPhase.off;
  }

  // _commitNow：
  //   final old = _active;
  //   await old.pause();
  //   await _holding;
  //   if (_standbyWanted && shadow is MovaStandbyController) {
  //     await (shadow as MovaStandbyController).setStandby(true);   // 在恢复音量与 play() 之前
  //   }
  //   await shadow.setVolume(old.state.volume);
  //   await shadow.play();
  //   …其余逐字不变
}
```

**断言（5，`MovaSwapEngine(engineFactory: () => FakeStandbyApi())`）：**
1. `MovaSwapEngine` 是 `MovaStandbyController`；`setStandby(true)` 转发给 active（`calls` 含 `setStandby:true`）并返回 active 的答复。
2. active 推 `state.copyWith(standby: holding)` 与 `MovaStandbyChange` → 代理的 `state.standby`/`events` 原样可见（`renderEpoch` 照旧合并）。
3. swap 开启、`setStandby(true)` 后 `prepare` → ready → `commit()`：影子的 `calls` 中 `setStandby:true` 位于 `setVolume` 与 `play` 之前；旧引擎收到 `pause`。
4. 未请求待机时提交：影子 `calls` 不含 `setStandby`，顺序与改前相同。
5. 工厂返回普通 `FakeMovaApi`：`setStandby(true)` → active 收到 `pause`、返回 `off`；`setStandby(false)` → `play`。

**验收：** 既有 swap 测试（含 HE 前的 seamless-swap 全部）原样通过；测试 **1243**。

---

## Task 7：守卫——`hiddenMode`、`standby`/`wake` 动作、R3 重新决策扩展到待机（D10）

**Files:** Modify `lib/src/core/guard/auto_pause.dart`、`lib/src/ui/guard/auto_pause.dart`；
Test: `test/core/guard/auto_pause_gate_test.dart`（增补 10）、`test/ui/auto_pause_test.dart`（增补 6）。

> 依赖评审修复 R3：gate 已有"隐藏期间意图变 true 时重新决策"的入口、widget 已订阅引擎状态、直播恢复已带世代并在每个 `await` 后校验可见性。
> 下文写作 `redecide(...)`/`_visibleGen`，**名字以 R3 落地代码为准**。

**Produces：**

```dart
/// What the guard does with a playing live stream while it is hidden.
///
/// 守卫在直播流被隐藏期间如何处理它。
enum MovaHiddenMode {
  /// Pause, and resume (or jump back to the edge) when shown. The default.
  ///
  /// 暂停，显示时续播（或回到边缘）。默认值。
  pause,

  /// Keep it in standby (`MovaStandbyController.setStandby`): still playing with
  /// video and sound off, so it comes back without reconnecting. Live only —
  /// VOD and backgrounding still pause. Costs full network while hidden.
  ///
  /// 让它待机（`MovaStandbyController.setStandby`）：仍在播放但关画面关声音，回来时无需重连。
  /// 仅对直播生效——点播与进后台仍是暂停。隐藏期间照常满速下载。
  standby,
}

// MovaAutoPauseConfig 新增：
/// How a playing live stream is handled while hidden; defaults to [MovaHiddenMode.pause].
///
/// 隐藏期间如何处理正在播放的直播流；默认 [MovaHiddenMode.pause]。
///
/// Example / 示例:
/// ```dart
/// MovaView(source: src, autoPause: const MovaAutoPauseConfig(hiddenMode: MovaHiddenMode.standby))
/// ```
final MovaHiddenMode hiddenMode;   // 默认 MovaHiddenMode.pause；并入 == / hashCode

// MovaGuardAction 追加：
/// Enter standby (`setStandby(true)`). 进入待机（`setStandby(true)`）。
standby,
/// Leave standby (`setStandby(false)`). 退出待机（`setStandby(false)`）。
wake,

// MovaAutoPauseGate：
MovaGuardAction update(MovaHideReason reason, bool active, {
  required bool playing, required bool live, required bool exempt, required DateTime now,
  bool standbyCapable = false,           // 新增，默认 false：既有调用与断言不变
});

// R3 的重新决策入口（名字以落地为准）追加同一个可选参数：
MovaGuardAction redecide({/* R3 既有参数 */ bool standbyCapable = false});
```

gate 内部草图（`_pausedByGate` → `_owe`）：

```dart
enum _Owe { none, resume, wake }
_Owe _owe = _Owe.none;

MovaGuardAction _hideAction(bool live, bool standbyCapable) {
  final standby = config.hiddenMode == MovaHiddenMode.standby &&
      live && standbyCapable && !_reasons.contains(MovaHideReason.background);
  _owe = standby ? _Owe.wake : _Owe.resume;
  return standby ? MovaGuardAction.standby : MovaGuardAction.pause;
}

// update()：
//   首次隐藏：intent && !exempt ? _hideAction(live, standbyCapable) : (_owe = none, none)
//   仍隐藏且 reason == background && active && _owe == wake：_owe = resume; return pause;   // 进后台降级
//   全部消失：owe == wake → (config.resumeOnShow ? wake : pause)；owe == resume → 既有 resume/reloadEdge；none → none
// redecide()（R3）：R3 原本"暂停并记为隐藏前在播"的那一步改为调用 _hideAction(live, standbyCapable)；其余（触发条件、_hiddenAt 不重置）不动
```

widget：`_set` 与 R3 的重新决策调用都增 `standbyCapable: api is MovaStandbyController`；新动作：

```dart
      case MovaGuardAction.standby:
        unawaited(_standby(api, true));
      case MovaGuardAction.wake:
        unawaited(_standby(api, false));

  Future<void> _standby(MovaApi api, bool on) async {
    final gen = _visibleGen;                       // R3 的可见性世代
    try {
      if (api is MovaStandbyController) {
        await (api as MovaStandbyController).setStandby(on);
        // R3 同款校验：进待机途中又变可见了，补一次唤醒；唤醒途中又被隐藏，gate 已发出新的 standby，引擎队列保证顺序。
        if (on && !_disposed && gen != _visibleGen && !_gate.hidden) {
          await (api as MovaStandbyController).setStandby(false);
        }
      } else if (on) {
        await api.pause();
      } else {
        await api.play();
      }
    } on Object {
      // 引擎调用失败不能从可见性回调里冒出来。
    }
  }
```

不再订阅 `MovaSourceChange` 做"重新施加"（初稿的 `reapply` 删除）：pause 模式靠 R3（换源 → 意图 false→true）；standby 模式靠引擎 D8 的
"请求跨 `open()` 保留、以暂停态加载、落地后尝试升级"。

**断言（16）：**
- gate（10）：
  1. `hiddenMode: standby` + 直播 + `standbyCapable` + 在播 → 隐藏返回 `standby`；恢复返回 `wake`。
  2. 同上但点播 → `pause` / `resume`。
  3. 同上但 `standbyCapable: false` → `pause` / 既有 `reloadEdge`（隐藏 ≥ 3s）。
  4. 首个原因就是 `background` → `pause`（不进待机）。
  5. 先 `tickerOff` 进待机，再加 `background` → `pause`；去掉 `background`（仍 `tickerOff`）→ `none`；去掉 `tickerOff`（隐藏已 ≥ 3s）→ `reloadEdge`。
  6. `exempt` → 隐藏、恢复均 `none`。
  7. `resumeOnShow: false` + 待机 → 恢复返回 `pause`。
  8. 默认配置 `hiddenMode == pause`；`MovaAutoPauseConfig(hiddenMode: standby) != const MovaAutoPauseConfig()`，`hashCode` 不同。
  9. R3 重新决策 + pause 模式（或 `standbyCapable:false`）→ 仍返回 `pause`、恢复返回 `resume`/`reloadEdge`（R3 原语义不变）。
  10. R3 重新决策 + standby 模式 + 直播 + 可待机 → `standby`，恢复返回 `wake`；隐藏原因含 `background` 时 → `pause`。
- widget（6，`FakeStandbyApi`，`api.push(MovaState(playing: true, type: MovaStreamType.live))`，意图按 R3 落地后的状态字段推送）：
  1. `TickerMode(enabled:false)` 包住、`hiddenMode: standby` → `calls` 含 `setStandby:true`；恢复 → `setStandby:false`；无 `pause`/`play`。
  2. 普通 `FakeMovaApi`（无能力）+ `hiddenMode: standby` → `pause` / `play`（与 HE Task 13 相同）。
  3. 待机中 `resumed→inactive→hidden`（合法迁移，HE 偏差清单）→ `pause`。
  4. 隐藏时没在播（不欠账）→ 推送意图变 true（R3 触发）→ standby 模式下 `calls` 追加 `setStandby:true`；pause 模式下追加 `pause`（R3 原行为）。
  5. `setStandby(true)` 用 `Completer` 挂住，期间恢复可见、gate 发出 `wake`（引擎侧排队）→ 完成后 `calls` 末尾为 `setStandby:false`，且最终没有多余的第二次 `setStandby:true`。
  6. `MovaView(source: live, autoPause: MovaAutoPauseConfig(hiddenMode: standby), engineFactory: (_) => FakeStandbyApi())` 放进 `TickerMode(enabled:false)` → 引擎收到 `setStandby:true`。

**验收：** HE Task 12/13 的 25 项守卫断言与 R3 的回归测试原样通过（`update`/`redecide` 新参数有默认值；`MovaGuardAction` 只增值）；测试 **1259**。

---

## Task 8：封面在待机期间覆盖 + 公开测试内核支持待机

**Files:** Modify `lib/src/ui/poster.dart`、`lib/src/testing/test_kernel.dart`；Test: `test/ui/poster_test.dart`（增补 3）、`test/testing/testing_test.dart`（增补 2）。

```dart
// poster.dart
      selector: (s) =>
          !(s.rendered && s.width > 0 && s.height > 0) ||
          s.standby == MovaStandbyPhase.holding ||
          s.standby == MovaStandbyPhase.resuming,
```

```dart
// test_kernel.dart：class MovaTestKernel implements MovaKernel, MovaStatsProbe, MovaStandbyKernel
/// Whether the scripted media has decodable audio: true/false, or null for
/// "not known yet" (the default — standby then falls back to a pause).
///
/// 编排的媒体是否有可解码的音频：true/false；null 表示"尚不知道"（默认——此时待机会退回暂停）。
bool? hasAudio;

/// The demuxer reported to standby, e.g. `flv` (default) or `hls`.
///
/// 报告给待机的 demuxer，例如 `flv`（默认）或 `hls`。
String? fileFormat = 'flv';
// inspectStandby/enterStandby/exitStandby 同 StandbyKernelStub，记入 calls（'enterStandby:muted' 等）
```

**断言（5）：**
- 封面（3）：推 `MovaState(rendered: true, width: 1280, height: 720, standby: holding)` → `opacity == 1` 且 `duration == Duration.zero`（瞬间盖上）；`standby: resuming` → 仍 `opacity == 1`；`standby: off` → `opacity == 0`、`duration == posterFade`。`standby: fallback` 不在断言里加覆盖（与 pause 模式一致，见 D12）。
- 测试内核（2）：`MovaTesting.useTestKernels()` 后 `hasAudio = true`、`MovaView(autoPause: standby)` 放进 `TickerMode(false)`，内核 `emitPlaying(true)` → `calls` 含 `enterStandby:muted`；`hasAudio` 默认 null → `calls` 含 `pause`、不含 `enterStandby`。

**验收：** HE Task 5/14 的封面与测试入口断言原样通过；测试 **1264**。

---

## Task 9：开放性对账、文档、验证 demo 页

**Files:**
- Test: `test/core/openness_standby_test.dart`（3）：① 默认值——`MovaOpts().standby == const MovaStandbyConfig()`、`const MovaAutoPauseConfig().hiddenMode == MovaHiddenMode.pause`、`const MovaState().standby == MovaStandbyPhase.off`；
  ② **零行为变化锚**：`MovaEngine(kernel: FakeStandbyKernel())` 跑一遍基础流程（`open` 直播/点播、`play`、`pause`、`seek`、`setVolume`、`switchQuality`、`backToLiveEdge`、`reload`、`dispose`）→ `calls` 中**没有**任何 `inspectStandby`/`enterStandby`/`exitStandby`，事件流中没有 `MovaStandbyChange`/`MovaStandbyResume`；
  ③ `MovaOpts.copyWith(standby:)` 只换 `standby` 节。
- `README.md`：新增"隐藏时待机（standby）"一节：机制、`hiddenMode` 与 `setStandby` 两个入口、**持续满速下载**、默认只对 FLV 类直播生效（HLS 默认暂停）、
  `maxDuration`、进后台一律暂停、命令式使用者需自己处理进后台、待机期间 QoE 仍计观看（Q8）、多卡片场景只给主卡片开。"已知限制"补：组合 C 不省电、`vo=null` 未做、iOS/macOS 未验证。
- `CHANGELOG.md`：未发布节——新公开面；**`MovaEvent` 新增 2 个子类、`MovaGuardAction` 新增 2 个值**（穷尽 switch 需补分支）；待机请求期间 `open()` 以暂停态加载新源（Q9）。
- `doc/SPEC.md`：新增一节「低功耗待机（2026-10-23）」，记 D1–D13 的签名、落点、迁移表、默认值表。
- `CLAUDE.md`："当前状态"加一节摘要 + 测试基线回写（实跑数字）。
- `example/lib/main_standby_verify.dart`：为 Task 10 单独建的验证页（不与其他 spike 混用）。三个源输入（FLV 有声 / FLV 无声 / HLS，URL 自动加 `?t=<timestamp>`），
  "隐藏"开关（`TickerMode(enabled:false)` 包住播放器，模拟切 Tab）、命令式 `setStandby` 开/关按钮、`hiddenMode` 与 `MovaStandbyConfig` 各项切换；
  日志用固定前缀 `[STANDBY]` + 毫秒时间戳（页面启动起算）打出 `MovaStandbyChange`/`MovaStandbyResume`/`MovaFirstFrame`/`MovaSizeChange`/`MovaBufferChange`/
  `MovaPlay`/`MovaPause`/`MovaPlayFailure`/`MovaLiveEdgeReach`，并每秒打一行 `position` 与 `MovaStatsProbe.sample()` 的 `inputBps`（`cache-speed`，看待机期间网络是否持续）。
  **本 Task 只要求 `flutter analyze` 通过，不要求上机。**

**验收：** analyze 0（example 下仅既有 `avoid_print` info）；测试 **1267**；基线数字回写 `CLAUDE.md` 与本文件。

---

## Task 10：真机测量与默认值校准【待定：等真机】

> **状态：待定。** STG AL00 当前不可用。本 Task 与 Task 1–9 完全解耦：不阻塞合入，也不是任何 Task 验收的前置条件。
> 真机回来后单独一轮执行，结果回写本节、D13 默认值表与 `feedback_real_device_verification`。

**前置检查：** 手机亮屏且已解锁（`adb shell dumpsys window | grep isKeyguardShowing` 为 false），锁屏/熄屏时一切涉及渲染面的结果作废；
release 与 debug 各跑一遍（debug 下原生事件走 100ms 轮询，RESTART 精度不同）。一律用 `example/lib/main_standby_verify.dart`，不混用其他 spike。

**测量方法（通用，全部基于真实事件时间戳，不用墙钟拍脑袋、不用临近 EOF 的 seek）：**
- **恢复耗时** = `MovaStandbyResume.elapsed`（引擎在唤醒调用开始处取时、在落地回调处取时，同一时钟），并记录 `signal`；
  对照组（D，暂停 + 回来重连）用 `hiddenMode: pause` 下"`MovaPlay` 之后第一次落地"——同页面同源，用 `fallback(maxDuration)` 唤醒得到的 `MovaStandbyResume(from: null)` 正好是同口径。
- **画面是否真的露出**：`adb shell screencap` 连续抓帧（约 250–330ms 一帧）与事件时间戳对齐，只做量级证据。
- **边缘保持**：待机前后各取一次 `MovaProg.position`，判据 `|Δposition − Δ待机时长| < 1s`；FLV 测试流用 ffmpeg `drawtext=text='%{localtime}'` 烧入时钟，
  唤醒后首帧截图读出时钟与设备时间的差。
- **功耗/流量/CPU**：`adb shell dumpsys batterystats --reset` → 跑 5 分钟 → `dumpsys batterystats <pkg>`；流量 `dumpsys netstats detail`（按 UID）；
  CPU `adb shell top -b -n 1 -p <pid>` 每 5s 采样；内存 `dumpsys meminfo <pkg>`。
- 每项至少 5 次（S1/S7 各 20 次）取 min/max/avg；测试流本机 nginx-flv/SRS 经 `adb reverse` 提供，GOP 可控。

| 编号 | 对应调研 | 验证项 | 方法 | 通过判据 / 产出 |
|---|---|---|---|---|
| S1 | T1 | B 恢复耗时（FLV，不可 seek） | GOP 1s/2s/4s × 待机 10s/30s，`setStandby(false)` 到 `MovaStandbyResume` | 中位数随 GOP 变化、≈ 解码器初始化 + ½GOP；`signal` 以 `size` 为主。**据此校准 `resumeTimeout`**（取 4s GOP 的 max + 1s） |
| S2 | T2 | HLS 是否可放开 | `allowHls:true` 跑 HLS 直播；`--msg-level=demux=v` 看 `refresh seek`；代理日志看是否回读分片；同时记 `file-format` 实际取值 | 无回读或回读不卡、恢复耗时不劣于 FLV → `allowHls` 默认可改 true；`file-format` 取值核对 `movaSegmentedFormats` |
| S3 | T3 | C（keepDecoding）恢复与开销 | 无声 FLV，待机 30s 后唤醒；同时采 CPU | `MovaStandbyResume.signal == null`、elapsed < 50ms；CPU 与正常播放同量级（确认"不省电"的说法）；`vo=null` 变体是否值得另立项的数据依据 |
| S4 | T4 | 功耗/流量/CPU：A / B / C / D | 同一直播流各跑 5 分钟 | B/C 流量≈满速、A 缓冲满后≈0；量化 B 相对正常播放省多少 CPU/电。**据此校准 `maxDuration`** |
| S5 | T5 | 边缘保持 | 待机 60s 后唤醒，按上面的边缘方法 | 与待机时长无关（落后 < 1s 量级） |
| S6 | T6 | 无声流判定与 B 的误判保护 | 无音轨直播：`inspectStandby().audio`；人为强制 B（调试开关）对照 `position` 是否停 | 判定为 `absent`；强制 B 时 `position` 停止推进（印证 §1.3 推断，说明 D4 的必要性） |
| S7 | T7 | `mediacodec-copy` 下 `vid` 切回能否出画 | 20 次来回 | 20/20 有 `MovaStandbyResume(signal: size)` 且截图有画面；logcat 无 `Could not open codec` |
| S8 | T8 | Android 进后台 | 守卫 standby 模式下 HOME 5s/60s/5min 回前台；另测命令式 holding 不处理进后台 | 守卫：后台前有 `MovaPause`、回来走 `reloadEdge`；命令式：记录 `widListener` 无条件 seek 后 `vid`/`mute`/`position` 的实际状态（不要求通过，记事实） |
| S9 | T9 | `skipframe`/`skiploopfilter` | **不在本计划实现**（§5） | 不测，记"不适用" |
| S10 | T10 | `drop-buffers` | **不在本计划实现**（§5） | 不测，记"不适用" |
| S11 | T11 | `mute` 时音频会话/耗电 | `dumpsys audio` 看 AudioTrack 是否仍在、`batterystats` 音频项 | 记录底噪，评估 B 的音频侧成本 |
| S12 | T12 | 桌面 `setSize(2,2)` | **不在本计划实现**（§5） | 可选：Windows 记录 B 期间 GPU 占用，作为是否另立项的依据 |
| S13 | 新 | `vid`/`mute` 跨重载保留（D5） | holding 中 `switchQuality`、`backToLiveEdge`（重开路径） | 重载后仍无声、无画（截图），`state.standby` 仍 holding；唤醒正常 |
| S14 | 新 | B 期间画面显示什么（D12/Q6） | holding 时临时取消隐藏（不唤醒）截图；Android 与 Windows 各一次 | 记录"黑 / 最后一帧"，决定封面覆盖默认是否保留 |
| S15 | 新 | 切回 `vid=auto` 是否发 RESTART（D7） | 开 `preciseFirstFrame`，统计 S1 里 `signal` 分布 | 记事实；若 RESTART 稳定先到，可把它作为首选信号写进文档 |
| S16 | 新 | `audio-params` 就绪时机（D4） | open 后 0.5/1/2/3s 调 `setStandby(true)` | 记录 `fallback(mediaUnknown)` 的比例与 `audio-params` 就绪的典型耗时；文档给出"打开后多久才能待机"的经验值 |
| S17 | 新 | 守卫端到端 | demo 内 `StatefulShellRoute.indexedStack` 两分支切换、push 半透明路由（带 `routeObservers`）、隐藏期间换源 | 切走即 `(holding, requested)`、切回即 `MovaStandbyResume`；隐藏期间换源后再次进入待机（Q9），全程无声音泄漏（人耳 + `dumpsys audio`） |

---

## 4. 宿主（bingo 直播卡片）用法示例（草图，本计划不改 bingo）

在 HE 计划 §4 的 `MovaView` 改造版基础上，只多两处：`MovaOpts.standby`（可省略，用默认值）与 `autoPause.hiddenMode`。
蜂窝网络下改回 `pause`，由宿主决定（待机持续满速下载）：

```dart
/// 直播卡片的播放配置：白色细转圈 + 超时重试/换档 + 隐藏时最多待机 30 秒。
static const MovaOpts _opts = MovaOpts(
  theme: MovaTheme(bufferingSize: 24, bufferingStrokeWidth: 2, bufferingColor: 0xFFFFFFFF),
  recovery: MovaRecoveryConfig(enabled: true, startTimeout: Duration(seconds: 8)),
  standby: MovaStandbyConfig(maxDuration: Duration(seconds: 30)),
);

@override
Widget build(BuildContext context) {
  final source = MovaSource.pick(
    orderStreamUrls(filterPlayableStreamUrls(streamUrls)).map((u) => u.addr),
    type: MovaStreamType.live,
    title: title,
  );
  return ValueListenableBuilder<bool>(
    valueListenable: onWifi, // 宿主自己的网络状态（如 connectivity_plus），mova 不替宿主判断
    builder: (context, wifi, _) => MovaView(
      source: source,
      fit: MovaFit.cover,
      poster: cover.isEmpty ? null : UrlImage(imageUrl: cover, fit: BoxFit.cover),
      skin: const MovaMinimalSkin(),
      options: _opts,
      autoPause: MovaAutoPauseConfig(
        hiddenMode: wifi ? MovaHiddenMode.standby : MovaHiddenMode.pause,
      ),
      routeObservers: [rootRouteObserver, homeBranchRouteObserver], // 每个 navigator 一个（HE 偏差清单）
    ),
  );
}
```

效果：切到别的 Tab / 被登录页盖住 → 卡片静音无画面但流还在跑（封面瞬间盖上）；30 秒内切回 → 恢复视频解码，FLV 典型等待
0~1 个 GOP，不重连、不重新请求；超过 30 秒或期间进后台 → 已转为暂停，切回时回到直播边缘（与今天的 pause 模式相同）。
需要埋点的宿主可监听 `MovaStandbyResume.elapsed` 对比两种恢复耗时。**列表里多张直播卡片时只给主卡片开待机**——每张待机卡片都在满速下载。

宿主 widget 测试（`package:mova/testing.dart`）：

```dart
setUp(MovaTesting.useTestKernels);
tearDown(MovaTesting.reset);

testWidgets('切走 Tab 时直播卡片进入待机', (t) async {
  await t.pumpWidget(MaterialApp(home: TickerMode(enabled: true, child: PinoyLivePanel(streamUrls: urls))));
  final k = MovaTesting.lastKernel!..hasAudio = true..emitPlaying(true);
  await t.pumpWidget(MaterialApp(home: TickerMode(enabled: false, child: PinoyLivePanel(streamUrls: urls))));
  await t.pump();
  expect(k.calls, contains('enterStandby:muted'));
});
```

---

## 5. 明确排除项

- **组合 C 的 `vo=null` 变体**（调研 §1.5，mpv-android 做法）：会被 media_kit Android `widListener` 覆盖，且 `wid=0` 时把 `vo` 设回非 null 有 SIGSEGV 风险（§0 #5）。
  本期 C = 静音 + 继续解码渲染。是否另立项看 S3/S8/S14。
- **桌面 `VideoController.setSize(2,2)` 降载**（调研 §1.5/§4.6）：Android 不支持；桌面收益看 S12。
- **`vd-lavc-skipframe`/`skiploopfilter`/`framedrop`**（调研 §1.4）：`mediacodec-copy` 下大概率无效。
- **组合 F（暂停 + `drop-buffers`）**：实验性命令，可能被 mpv 删除。
- **`MPV_RENDER_PARAM_SKIP_RENDERING`**：需要 fork media_kit_video 原生层。
- **App 进后台时待机**：系统限网限 CPU，一律暂停（守卫已保证；命令式使用者自理）。
- **省流量**：待机期间满速下载是本模式的固有代价，不做"待机时压低 `demuxer-max-bytes`/`cache-secs`"等二阶优化（调研 §1.6）。
- **feed 池"邻近页保温"**（调研 §5.2）：二期。
- **QoE collector 识别待机**（Q8）：本期不改已真机验证的 collector。
- **swap 预热中的影子在隐藏期间降载**：影子按既有逻辑预热（含视频管线），不在本期。
- **swap `muteWhileWarm` 走 `setVolume(0)` 的问题**（Q13）：后续已修复（代码层），待真机确认，见文首修复记录。
- **`MovaApi`/`MovaKernel` 新增成员**：全部经能力接口。
- **iOS/macOS**：未验证；`MovaStandbyKernel` 的属性操作平台无关，但 Darwin 上 `vid` 切回的硬解行为没人测过。

---

## 6. 开放问题（需用户拍板；括号内为推荐默认，不反对就按它走）

1. **Q1 命令式入口放哪？**（推荐：能力接口 `MovaStandbyController`，`MovaEngine`/`MovaSwapEngine` 实现，`MovaApi` 零新增成员。
   备选是给 `MovaApi` 加 `setStandby`——更直白，但会让所有自定义 `MovaApi` 实现者（含宿主测试里的假对象）编译失败。）
2. **Q2 无音频流默认怎么处理？**（推荐：`keepDecoding`，即自动选 C——零正确性风险、保住秒回，代价被 30s 封顶；备选 `pause` 更省电。待 S3/S6 校准。）
3. **Q3 HLS/DASH 默认是否待机？**（推荐：否，`allowHls: false`，HLS 退回暂停；bingo 走 FLV 不受影响。待 S2 校准后再考虑放开。）
4. **Q4 `maxDuration` 默认 30s？**（推荐：是，待 S4 校准。）
5. **Q5 `resumeTimeout` 默认 5s？**（推荐：是，覆盖 4s GOP；待 S1 校准。）
6. **Q6 有封面时，待机与恢复期间是否默认盖封面？**（推荐：盖，不加开关——Android B 期间画面多半是黑的，盖封面比露黑块/冻帧好；不传 `poster` 的宿主不受影响。S14 出数据后再看要不要做成可选。）
7. **Q7 唤醒时何时恢复声音？**（推荐：立即，与恢复视频同一步——音频是时钟，先听到声音是直播播放器的常见表现；备选是等首帧落地再取消静音，A/V 同时出现但声音晚 0~1 个 GOP。）
8. **Q8 待机期间 QoE 怎么计？**（推荐：本期不改 collector，README 注明"待机期间计为观看、卡顿照计"；若宿主同时开 QoE 与待机，再另立项让 collector 把 holding 当暂停。）
9. **Q9 待机请求期间换源怎么办？**（推荐：引擎保留请求、以暂停态加载新源，首帧落地后若意图为 true 再尝试一次进待机（D8）。理由：pause 模式的同类缺口
   已由评审修复 R3 补上，但 R3 只在意图 false→true 时触发，而待机中意图一直是 true，换源不会触发它。备选是让守卫在 `MovaSourceChange` 时重新施加，
   但那样新源会先出声几十到几百毫秒。）
10. **Q10 holding 期间收到 `play()` 怎么办？**（推荐：保持待机，唤醒只认 `setStandby(false)`——隐藏卡片里程序性的 `play()`（广告、swap 提交）不会出声；备选是把 `play()` 当唤醒。）
11. **Q11 holding 期间播放失败怎么办？**（推荐：降级为暂停、延到唤醒时强制重开，不在看不见的时候反复重连；备选是照常走 recovery 策略。）
12. **Q12 新增 2 个 sealed 事件子类 + `MovaGuardAction` 2 个新值**，对宿主无 `default` 的穷尽 switch 是编译期 breaking（推荐：接受，与 HE 计划 Q10 一致，CHANGELOG 注明。）
13. **Q13（旁支发现，后续已处理：已修复（代码层），待真机确认）** 原 `MovaSwapEngine` 的 `muteWhileWarm` 用 `shadow.setVolume(0)` 静音、提交时 `setVolume(old.state.volume)` 恢复
    （`swap_engine.dart:395, 533`）；而 Android 上 `createMovaEngine()` 默认接系统音量端口，`setVolume` 改的是整机媒体音量——疑似预热期间会把**正在播放的那一路**也静音。
    真机从未测过音频（CLAUDE.md："音频跳变仍实测不了"）。2026-10-24 已从调用链确认推断成立；现经可选 `MovaPlayerMute` 仅操作播放器 `mute`，不支持能力就不静音。与 standby 分别持有静音、共用串行队列，任意退出顺序均正确还原；新增 16 项回归，最终 1302 全绿，尚未真机验证。
14. **Q14 待机自己做的暂停（fallback/超时/失败降级）要不要把播放意图置 false？**（推荐：不置——意图只表示用户/宿主想不想播，唤醒按它决定出不出画面；
    代价是 fallback 期间所有"按意图加载"的内部路径要改读 `_loadPlays`（D9），否则会在隐藏中开播。备选是 fallback 时把意图置 false、另存一份、唤醒时还原：
    R1 的加载路径自然不开播、不用 `_loadPlays`，但意图对外不再等于用户意愿（fallback 期间读到 false），用户在 fallback 期间 `pause()` 还得额外清掉另存值，
    两份意图容易记串。）
15. **Q15 请求待机时 recovery 正有待执行重试，怎么办？**（推荐：取消重试、直接 fallback(`failed`)，唤醒时强制重开；备选是让重试照常进行、成功后再进待机，
    但重试按意图会以 `play:true` 加载，在隐藏中出声。）

---

## 7. 与 HE 计划的依赖点

| 本计划用到的 | 来自 HE 计划 | 用法 |
|---|---|---|
| `MovaFirstFrameGate`（`arm`/`onSize`/`onRestart`/宽限） | Task 1 | Task 4 加 `resume` 武装 |
| `_feedGate`/`_armAttempt`/`_onAttemptLanded`/`_kernelOpening`/`_graceTimer`、`MovaState.rendered` | Task 2 | 恢复落地挂在 `_onAttemptLanded` 开头；`rendered` 不动 |
| `observeNativeEvents`/`preciseFirstFrame`、`nativeRestartAvailable` | Task 3 | 恢复信号可用 RESTART；S15 统计 |
| `MovaPlayer(poster:)`、`MovaPosterLayer` | Task 5 | Task 8 改判据 |
| `MovaView`（`autoPause`/`routeObservers`/`engineFactory`） | Task 8/13 | 无新参数，`hiddenMode` 经 `autoPause` 传入 |
| `MovaPlayWatchdog`、`_loadKernel` 后武装起播期限、`_onPlayFail`、`_completedSub` 的 `liveEnded` | Task 9/10 | D9：holding 期间 disarm、失败降级、唤醒后回到卡顿监视 |
| `_activeUri`、`_reopenLiveSource`、`MovaFailover` | Task 11 | 唤醒重开用当前地址 |
| `MovaAutoPauseGate`/`MovaAutoPause`（`_owe` 重构、`routeObservers` 列表、`getValuesNotifier`、合法生命周期迁移） | Task 12/13 | Task 7 在其上扩展；测试沿用其迁移写法 |
| `MovaTestKernel`/`MovaTesting`（`package:mova/testing.dart`） | Task 14 | Task 8 加待机能力 |
| `openness_audio_test` 节清单（HE Task 9 偏差） | Task 9 | Task 1 追加 `'standby'` |
| 测试基线 1158 | Task 15 | 本计划起点 |
| **R1 播放意图**（`play()`/`open(autoPlay)` 置 true、`pause()` 置 false） | 评审修复 | 进入判定读意图；唤醒按意图（`settle`）；`_loadPlays` 在 fallback 期间屏蔽意图（D9）；看门狗按意图武装 |
| **R2 恢复任务绑定会话世代 + 失败尝试编号、内部加载取消待执行恢复** | 评审修复 | 进入待机调用同一取消入口；有待执行恢复 → fallback(`failed`)；`_recoveryPending` 只读判断 |
| **R3 守卫订阅引擎状态、隐藏期间意图变 true 重新决策、直播恢复带世代与可见性校验** | 评审修复 | Task 7 把它的动作选择扩展为 `_hideAction`；`standby`/`wake` 沿用同一世代校验；不再自做 `reapply` |
| **R4 续播位置跨失败保留** | 评审修复 | 仅点播，与待机无交集（D9 末条） |

**落地顺序要求：** HE 计划 Task 1–15 **连同评审修复 R1–R4** 先提交（目前是未提交工作区），再开始本计划 Task 1；本计划内部严格按 Task 1→9 顺序，Task 10 等真机。
开工时先核对 R1–R4 的实际命名（`_playIntent`、恢复取消入口、R3 的重新决策入口与可见性世代），把本文草图里的占位名替换掉并记入"落地偏差"。
