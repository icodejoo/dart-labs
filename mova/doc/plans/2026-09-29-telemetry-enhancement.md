# mova：埋点上报增强（QoE 四大指标 + 可扩展事件名） — 实现计划

> 2026-09-29 · 落地计划 · 承接调研笔记
> [doc/notes/2026-09-29-player-telemetry-best-practices.md](../notes/2026-09-29-player-telemetry-best-practices.md)

**Goal:** 把 `MovaReporter` 从"UI 动作流水"补成"播放质量数据源"——补齐业界必测四件套
（**TTFF 首帧耗时 / 卡顿次数与时长 / 播放失败（fatal 区分）/ 会话开始与结束（含结束原因四分）**），
并把 `MovaReportName` 从纯枚举改成"内置 + 自定义"双轨。

**主干设计不变：mova 只标准化、只打标签，绝不做网络发送/批处理/调度。** 本计划新增的
聚合全部是纯内存计数，不引入任何 HTTP 客户端、不引入任何新依赖。

**Baseline:** 本次实测 `flutter test` = **859 项全绿**（2026-09-29 实跑；`CLAUDE.md`
里记的 815 已过期，Task 11 顺带回写）、`flutter analyze` 0 issues（仅剩既有
`feed_player.dart` 警告）。

---

## 0. 一手调研结论：libmpv 能给什么、不能给什么

用户要求"优先用 libmpv/ffmpeg 自身能力，缺了再自实现"。下表是本轮逐条核实的结果，
**每一条都区分了"libmpv 有没有"与"经 media_kit 拿不拿得到"——这两件事在本项目里
经常不一致，而决定架构的是后者。**

| 需求 | libmpv 原生能力 | 经 media_kit 1.2.6 可达性 | 结论 |
|---|---|---|---|
| 首帧就绪 | `MPV_EVENT_PLAYBACK_RESTART`（"playback was reinitialized… usually happens on start of playback and after seeking"） | ❌ **不可达**：media_kit 不暴露任何原始 mpv event 钩子，公开面只有 `observeProperty`/`getProperty`/`command` | 退而用 `core-idle`（下详） |
| 首帧就绪（次选） | 属性 `core-idle`："it's only `no`/`false` if there's actually video playing" | ✅ media_kit 内建观察，并直接体现在 `Player.stream.buffering` | **选它**，零新增观察 |
| 卡顿瞬时态 | 属性 `paused-for-cache`（"playback is paused because of waiting for the cache"）、`cache-buffering-state`（0–100） | ⚠️ media_kit 内建观察，但**与 `core-idle` 合并成同一个 `buffering` 布尔**，无法区分"真卡顿"与"暂停/seek/起播" | 需二次观察 `paused-for-cache` |
| 卡顿**累计**次数/时长 | ❌ **libmpv 完全没有**——手册只给瞬时状态，无任何累计计数器 | — | **必须 mova 自实现聚合**（与 ExoPlayer `PlaybackStatsListener` 同构） |
| 结束原因四分 | `mpv_event_end_file.reason`（EOF/STOP/QUIT/ERROR/REDIRECT）+ `error` 错误码 + `playlist_entry_id` | ❌ **不可达**：media_kit 把 `MPV_EVENT_END_FILE` 的处理整段注释掉了（`real.dart:1486-1503`，注释原文 "Now, `--keep-open=yes` is used. Thus, `eof-reached` property is used instead"）。而且 `keep-open=yes` 下 mpv 到 EOF 根本不结束文件，该事件本就不会正常触发 | **必须 mova 自实现状态机** |
| 错误码（可聚类） | `mpv_event_end_file.error` 给 mpv error code | ❌ 同上不可达。`Player.stream.error` 实为 **mpv 日志行**（`real.dart:2084-2118`：level=`error` 且 prefix ∈ {`file`,`ffmpeg`(tcp:),`vd`,`ad`,`cplayer`,`stream`} 的 `text`），**prefix 被丢掉了** | ✅ 但 `Player.stream.log` 公开 `PlayerLog{prefix, level, text}`，**prefix 就是 mpv 自己的子系统分类**，可直接当 `code` 用 |
| 编码码率（CMCD `br`） | `video-bitrate`/`audio-bitrate`："calculated on the packet level… unit is bits per second"，mpv 自己已做节流 | ✅ `video-bitrate` **不在** media_kit 内建观察表，可自行 `getProperty` | 可用 |
| 实测吞吐（CMCD `mtp`） | `cache-speed`："number bytes per seconds over a 1 second window"（= `demuxer-cache-state` 的 `raw-input-rate`） | ✅ 不在内建表 | 可用 |
| 丢帧 | `frame-drop-count`（VO 侧丢帧）/ `decoder-frame-drop-count`（解码器因落后音频丢帧）/ `vo-delayed-frame-count`（**延迟**而非丢帧，display-sync 专用估计值） | ✅ 不在内建表 | 可用，但**手册未声明换片是否清零** → 用"会话首尾各采一次取差值"规避 |
| 硬解/网络流判定 | `hwdec-current`、`demuxer-via-network`、`file-format` | ✅ | 可用（会话级字段） |
| 自定义业务事件名 | ❌ **libmpv 无此概念** | — | **mova 自实现**（`MovaReportName.custom`） |
| sessionId | ❌ **libmpv 无此概念** | — | **mova 自实现**（纯 Dart 生成） |

**一手来源**：mpv 手册 Properties 章节 <https://mpv.io/manual/master/#property-list>
（`core-idle`/`paused-for-cache`/`cache-buffering-state`/`demuxer-cache-state`/
`video-bitrate`/`cache-speed`/`frame-drop-count`/`decoder-frame-drop-count`/
`vo-delayed-frame-count`/`hwdec-current`/`demuxer-via-network`）、libmpv 客户端头
<https://github.com/mpv-player/mpv/blob/master/include/mpv/client.h>
（`MPV_EVENT_PLAYBACK_RESTART`/`MPV_EVENT_FILE_LOADED`/`mpv_end_file_reason`/
`mpv_observe_property` 的合并语义）。
media_kit 侧代码引用均指
`~/AppData/Local/Pub/Cache/hosted/pub.dev/media_kit-1.2.6/lib/src/player/native/player/real.dart`。

### 0.1 两条必须写进代码注释的 media_kit 约束

**约束 A：属性可以重复观察，但永远不许 `unobserveProperty`。**
media_kit 内建观察表（`real.dart:2458-2478`）已经占用了：`pause`、`time-pos`、
`duration`、`playlist-playing-pos`、`volume`、`speed`、`core-idle`、
`paused-for-cache`、`demuxer-cache-time`、`cache-buffering-state`、`audio-params`、
`audio-bitrate`、`audio-device`、`audio-device-list`、`video-params`、`track-list`、
`eof-reached`、`idle-active`、`sub-text`、`secondary-sub-text`。
内建表与 `NativePlayer.observeProperty()` 用的是**同一个 `property.hashCode` 作为
reply userdata**，但事件分发按"名字 + format"二次判别（内建用 FLAG/DOUBLE/NODE，
`observeProperty` 固定用 `MPV_FORMAT_NONE`），所以**重复观察是安全的**；
而 `mpv_unobserve_property(ctx, reply)` 会按 reply id 一次性注销**全部**同名注册——
一旦调用，media_kit 自己的 `buffering`/`position` 流会静默死掉。
→ mova 只 observe、不 unobserve，生命周期交给 `Player.dispose()`。

**约束 B：`mpv_observe_property` 的变更通知是合并（coalesced）的。**
client.h 原文："change events are returned only once the event queue becomes empty,
and then only one event per changed property is returned."
→ 任何基于"数边沿"的聚合都必须容忍丢失中间值；`paused-for-cache` 的 false→true→false
一对边沿在极端情况下可能被压成一次通知。默认卡顿策略因此按"状态翻转 + 墙钟差值"
而不是"计数每一次通知"实现，并对 `< minStall` 的抖动做吞噬。

---

## 1. 架构决策

### D1 — TTFF：起点 `open()` 入口，终点 `core-idle` 转 false，**不新增任何 libmpv 观察**

**为什么不用 `MovaReady`：** `engine.dart:688` 的 `MovaReady` 是在
`await _kernel.open()` 返回后立刻发的，而 media_kit 的 `Player.open()` 完成于
`loadfile` 命令下发/初始化完毕，**离首帧还差整个网络握手 + 解封装 + 解码**。
把它当 TTFF 终点会系统性地把首帧耗时低估成接近 0。调研笔记 A2 建议"用首个
`MovaReady`"，**本计划推翻这一条**，理由即上。

**为什么不用 `MPV_EVENT_PLAYBACK_RESTART`（虽然它才是 libmpv 的标准答案）：**
media_kit 没有任何暴露原始 mpv event 的公开面（见 §0 表）。要拿到它只能 fork
media_kit 或自己写 FFI 事件循环——代价远超收益，且会把"core 层只有
`mpv_kernel.dart` 碰 media_kit"这条硬约束撑破。**记录为已知取舍，不做。**

**为什么 `core-idle` 是合格的替身：** 手册原文 "it's only `no`/`false` if there's
actually video playing"——即它转 false 的那一刻，核心确实已经在输出画面了，
语义上与 PLAYBACK_RESTART 高度重合（后者本就是"核心重新开始输出"）。
它已经被 media_kit 内建观察，并经 `Player.stream.buffering` → `MovaKernel.buffering`
一路透传到 `MovaEngine`，**因此 TTFF 的实现是纯 Dart 边沿检测，零新增原生观察**。

**为什么不用 `vo-configured`：** 手册明确它只表示"VO 当前是否已配置 / 视频窗口是否
可见"，不是逐帧精确信号；且 `audioOnly` 模式下根本没有 VO。

**为什么不用首个 `time-pos > 0`：** mpv 可能在实际输出前就报告 `time-pos`，且
`time-pos` 在 seek 后也会跳变，边界不干净。

**定义（对齐 CMCD `msd` / 腾讯云"首帧耗时"）：**

```
ttffMs = t(首个 buffering==false 边沿) − t(MovaApi.open() 进入的第一行)
```

- 起点取 `open()` **方法体第一行**（在 `_chain.beforeOpen` 拦截器之前），因为
  宿主拦截器的耗时是用户等待的一部分。
- 仅当 `autoPlay == true` 时测量：`autoPlay: false` 下 `core-idle` 本就恒为 true，
  测出来的数没有意义（`MovaTtffTracker` 直接不进入 armed 态）。
- `audioOnly` 下同样成立，语义变成"首个音频输出"，在 `params` 里带
  `audioOnly: true` 让分析侧能分桶。
- 起播失败/放弃：armed 后在拿到首帧前会话就终止（新 `open()`、`dispose()`、
  fatal 错误），发 `startupFail`（`priority: immediate`），`params.reason` 取
  `failed`（有 fatal 错误）或 `abandoned`（没有，即 Mux 的 Exits Before Video Start）。

**2026-09-29 更新：`MPV_EVENT_PLAYBACK_RESTART` 已可达，改为首选终点，
`core-idle` 退为兜底。** 上面"为什么不用 `MPV_EVENT_PLAYBACK_RESTART`"一节的
论证（"要拿到它只能 fork media_kit 或自己写 FFI 事件循环，代价远超收益"）
在**当时调研的 media_kit 1.2.6（pub.dev 发布版）** 下依然成立、依然是正确的
论证——**但前提变了**：media_kit **master 分支**（commit
`c533e446755f51cf53c7e57aea873f2aa5355f81`）新增了官方公开 API
`observeEvent`/`unobserveEvent`，可直接订阅任意 `mpv_event_id`（含
`MPV_EVENT_PLAYBACK_RESTART`），**不需要 fork、不需要自己写 FFI**——上面否决
它的两个理由都不再适用。用户已拍板 mova 直接依赖该 git 提交（见 `pubspec.yaml`），
接受"暂时无法发布到 pub.dev"的已知代价（与 `CLAUDE.md` 记录的现状一致）。

**新实现**：`MovaMpvKernel`（唯一允许碰 media_kit 的文件）新增
`implements MovaStatsProbe` 的 `playbackRestarts`（`Stream<void>`）与
`endFiles`（见 D3），构造期用 `native.observeEvent(MPV_EVENT_PLAYBACK_RESTART, …)`
订阅；`MovaTtffTracker` 新增 `onNativeRestart(DateTime at)`，语义与
`onBuffering` 的下降沿相同（落地即武装态转已落地），返回武装到落地的耗时。
`MovaQoeCollector` 同时喂两路信号——`playbackRestarts` 与 `buffering` 边沿都会
调用 tracker，`isArmed` 守卫保证无论哪个先到都不会重复上报，`firstFrame` 的
`params` 里加一个 `signal: 'restart' | 'buffering'` 字段区分精度来源（与 D2 的
`rebuffer.signal` 同一模式）。**`core-idle`/`buffering` 边沿没有被移除**——它是
`observeEvent` 订阅失败（该 API 只在这一个被锁定的 git 提交上有，除 Windows 外
其余平台的运行时行为未经验证）时的静默退化路径，见
`MovaMpvKernel._observeNativeEvents` 的 try/catch 包裹与本文档"平台守卫"一节。
上面"为什么 `core-idle` 是合格的替身"的论证因此原样保留——它现在是退化路径的
理由，而非首选路径的理由。

### D2 — 卡顿聚合：信号取 `paused-for-cache`（新增观察），聚合器是可注入纯逻辑对象

**为什么不能直接复用 `MovaBufferChange`：** media_kit 把 `core-idle` 与
`paused-for-cache` **两个语义完全不同的属性合并成同一个 `buffering` 布尔**
（`real.dart:1517-1543`）。`core-idle` 在暂停、seek、起播、EOF 时都为 true，
拿它数"卡顿次数"会系统性高估。真正的 rebuffer 信号只有 `paused-for-cache`
（手册："playback is paused because of waiting for the cache"）。

**为什么必须自己聚合：** libmpv **没有任何累计卡顿计数器/累计卡顿时长属性**
（§0 已核实）。这正是 ExoPlayer `PlaybackStatsListener` 存在的理由——官方把它拆成
"事件解释（区分首次缓冲 vs 再缓冲）→ 状态追踪 → 聚合 → 汇总"四步。mova 照抄这个
分层，但按本仓库既有范式落地：**抽象策略 + 默认实现 + 可注入**，与
`MovaAbrPolicy`/`MovaBufferAbr`（`options/abr_config.dart`）逐字同构。

```dart
/// Turns a stream of "stalled right now" observations into completed stall
/// records. Mirrors [MovaAbrPolicy]: mova ships a default, hosts can inject.
///
/// 把一连串"此刻是否卡住"的观测，转换成一条条"已结束的卡顿"记录。
/// 与 [MovaAbrPolicy] 同一范式：mova 给默认实现，宿主可注入替换。
abstract class MovaStallPolicy {
  /// Feeds one observation; returns the finished stall when [stalled] just
  /// fell back to false, otherwise `null`.
  ///
  /// 输入一次观测；仅当 [stalled] 刚刚落回 false 时返回本次已结束的卡顿，
  /// 否则返回 `null`。
  MovaStall? onStall(bool stalled, DateTime at);

  /// Drops accumulated state (new source / quality switch).
  ///
  /// 丢弃累积状态（换源 / 换清晰度）。
  void reset();
}

/// Default edge-based policy: counts a stall from the rising edge to the
/// falling edge, swallowing anything shorter than [minStall] (mpv coalesces
/// property-change notifications, so sub-frame flaps are noise, not stalls).
///
/// 默认的边沿策略：从上升沿计到下降沿，吞掉短于 [minStall] 的抖动
/// （mpv 会合并属性变更通知，亚帧级翻转是噪声而非卡顿）。
class MovaEdgeStall implements MovaStallPolicy { ... }
```

**"首次缓冲 vs 再缓冲"的判据**：`MovaQoeCollector` 只在 **TTFF 已落地之后**才把观测
喂给 `MovaStallPolicy`——首帧之前的等待属于起播耗时，不计入卡顿，否则同一段时间会
被两个指标重复计费（ExoPlayer 官方文档点名的第一步"事件解释"就是这件事）。

**为什么单次卡顿仍然出事件**：调研笔记 §2 的担心（高频）指的是 `buffering` 布尔抖动，
而"一次卡顿**结束**"本身是低频的（真卡才有）。所以：翻转不上报，**卡顿结束**上报一条
`rebuffer`（带 `durationMs`/`positionMs`/`index`，`batched`），累计量另随 `sessionEnd`
与 `heartbeat` 汇总。既保住了降噪意图，又不丢数据。

### D3 — 会话结束原因四分：**libmpv 路径不可达，mova 自实现状态机**

**libmpv 本来有标准答案**：`mpv_event_end_file.reason` ∈ {EOF, STOP, QUIT, ERROR,
REDIRECT}，还附带 `error`（mpv 错误码）与 `playlist_entry_id`，比自己维护状态机可靠得多。
**但它拿不到**，两重原因（§0 已核实）：
1. media_kit 把 `MPV_EVENT_END_FILE` 的处理整段注释掉了，公开面上不存在；
2. media_kit 强制 `--keep-open=yes`，该模式下 mpv 到 EOF **根本不结束文件**、改用
   `eof-reached` 属性表达——即便打通了事件通道，EOF 分支也不会按预期触发。

**所以本项不是"为了凑 libmpv 优先而牵强附会"，而是明确的"libmpv 有、但本技术栈
不可达 → 自实现"。** 自实现的四分**语义上与 mpv 枚举平行**（EOF→`ended`，
STOP/QUIT→`stopped`，ERROR→`failed`；REDIRECT 与 mova 无关，mova 不用 mpv 播放列表），
另外补一个 mpv 根本没有的 `abandoned`——它是 QoE 概念（Mux 的 Exits Before Video
Start），天然只能在消费侧定义。

```dart
/// Why a playback session ended. Parallel to ExoPlayer's
/// ENDED/STOPPED/FAILED/ABANDONED terminal states.
///
/// 一次播放会话的结束原因。与 ExoPlayer 的
/// ENDED/STOPPED/FAILED/ABANDONED 终止态一一对应。
enum MovaSessionEnd {
  /// Playback reached the end of the media ([MovaDone]).
  ///
  /// 播放到达媒体末尾（[MovaDone]）。
  ended,

  /// Torn down after the first frame — a new `open()` or `dispose()`.
  ///
  /// 首帧之后被拆掉——新的 `open()` 或 `dispose()`。
  stopped,

  /// A fatal error ended it.
  ///
  /// 被一次致命错误终结。
  failed,

  /// Torn down before the first frame ever arrived, with no fatal error —
  /// the user gave up waiting (Mux "exits before video start").
  ///
  /// 首帧还没出来就被拆掉，且没有致命错误——用户等不及走了
  /// （Mux 的 "exits before video start"）。
  abandoned,
}
```

判定优先级（纯函数，单测直接覆盖全部分支）：
`failed`（本会话记录过 fatal 错误）> `ended`（`completed == true`）> `abandoned`
（`firstFrameAt == null`）> `stopped`。

**2026-09-29 更新：`MPV_EVENT_END_FILE` 已可达，用于佐证而非替换自实现状态机。**
上面"libmpv 有、但本技术栈不可达"的论证在**当时的 media_kit 1.2.6** 下依然
成立——但同 D1，media_kit **master** 新增的 `observeEvent` 打破了这个前提，
`MPV_EVENT_END_FILE` 现在可以订阅到，`event.data` 转成
`generated.mpv_event_end_file` 后能读到 `.reason`（STOP/QUIT/ERROR，`EOF`
仍不可达——`--keep-open=yes` 下 mpv 到 EOF 根本不结束文件，这条约束原样保留，
没有变化）。

**没有把这条原生信号当成状态机的替代品，而是当成佐证/兜底，理由三条**：
1. `ended` 分支的唯一权威信号仍是 `MovaDone`/`completed`（`--keep-open=yes`
   下原生 `eof` 永远拿不到，`ended` 从设计上就不可能靠原生信号判定）；
2. `stopped` vs `abandoned` 的区分本就完全由"首帧是否落地"决定，原生
   `STOP`/`QUIT` 原因不携带比这更多的信息，替换掉旧的时序推断不会提升准确度，
   只会多引入一个"原生事件是否到达"的分支；
3. 唯一有实质增益的是 `failed`——原生 `ERROR` 原因可以在"配对的
   `MovaErrorEvent`/日志行分类（D4）漏判"时兜底把 `_fatalSeen` 兜回 `true`，
   这是真实的可靠性提升，也是`resolveSessionEndNative`存在的唯一理由。

新增纯函数 `resolveSessionEndNative`（`lib/src/core/report/session.dart`）：

```dart
MovaSessionEnd resolveSessionEndNative({
  required MovaEndFileReason? nativeReason,
  required bool fatalSeen,
  required bool completed,
  required bool firstFrame,
}) {
  final effectiveFatal = fatalSeen || nativeReason == MovaEndFileReason.error;
  return resolveSessionEnd(fatalSeen: effectiveFatal, completed: completed, firstFrame: firstFrame);
}
```

`nativeReason: null`（`observeEvent` 订阅失败、或该次 teardown 前原生事件还
没到达）时**精确退化为 `resolveSessionEnd` 本身**，包括"fatal 优先于
completed"这条优先级——这是一处严格增强，不是替换，旧函数与其全部既有单测
原样保留。`MovaEndFileReason` 定义在 `stats_probe.dart`（`stop`/`quit`/`error`/
`redirect`，刻意不含 `eof`，理由同上）。`MovaQoeCollector` 新增对
`MovaStatsProbe.endFiles` 的订阅：收到 `error` 原因时直接置位 `_fatalSeen`，
其余原因记入 `_lastEndFileReason` 供 `_emitSessionEnd` 调用
`resolveSessionEndNative` 时使用。

### D4 — 错误 fatal/非 fatal：判据用 **mpv 自己的日志 prefix**，策略可注入

**libmpv 的错误码不可达**（`mpv_event_end_file.error`，同 D3），但**还有一条 libmpv
自己的分类信息是可达的**：`Player.stream.log` 给的 `PlayerLog{prefix, level, text}` 里，
`prefix` 就是 mpv 的子系统名。media_kit 的 `stream.error` 恰恰把这个 prefix 丢了，
只转发 `text`（`real.dart:2084-2118`）——所以 mova 改从 `log` 流取，等于**把 libmpv
已经做好的分类捡回来**，而不是去正则匹配错误文案。

映射（与 hls.js 的 `ErrorTypes` 轴对齐）：

| mpv prefix | `params.code` | 语义 | 默认 fatal |
|---|---|---|---|
| `stream` / `file` | `stream` / `file` | 打不开源、IO 失败 | ✅ |
| `ffmpeg`（`tcp:` 开头） | `network` | 网络传输错误 | 首帧前 ✅ / 首帧后 ❌（可恢复重连） |
| `vd` / `ad` | `decode.video` / `decode.audio` | 单帧/单包解码失败 | ❌ |
| `cplayer` | `player` | 核心层 | ✅ |
| 其他 / 无 prefix | `unknown` | — | ❌ |

```dart
/// Decides whether a playback error is fatal and what stable code it carries.
///
/// 判定一次播放错误是否致命、以及它对应的稳定错误码。
abstract class MovaErrorPolicy {
  /// [subsystem] is mpv's own log prefix when known (`vd`/`ad`/`stream`/…),
  /// `null` when the error did not come from the log stream.
  /// [afterFirstFrame] says whether playback had already started.
  ///
  /// [subsystem] 为 mpv 自己的日志 prefix（已知时），错误不来自日志流时为 `null`。
  /// [afterFirstFrame] 表示首帧是否已经出来。
  MovaErrorVerdict classify(Object error, {String? subsystem, required bool afterFirstFrame});
}

/// Default policy built on mpv's log prefixes; see the table in
/// `doc/plans/2026-09-29-telemetry-enhancement.md` §D4.
///
/// 基于 mpv 日志 prefix 的默认策略；映射表见
/// `doc/plans/2026-09-29-telemetry-enhancement.md` §D4。
class MovaPrefixError implements MovaErrorPolicy { ... }
```

`MovaErrorEvent` 的上报改为：`params: {'error': …, 'fatal': bool, 'code': String}`；
**非 fatal 降为 `batched`**（调研 §3 的噪声问题），fatal 保持 `immediate`。

### D5 — `MovaReportName` 双轨：枚举改 **const 值类**，`==` 按 `value` 比

```dart
/// A report event name: one of mova's built-ins, or a host-defined custom
/// name via [MovaReportName.custom].
///
/// Was an `enum` before 0.2.x. Hosts that `switch` on a name must switch on
/// [value] (a `String`) — Dart forbids constant patterns of a type that
/// overrides `==`. Equality/`hashCode` are by [value], so `==` comparison and
/// `Map`/`Set` keys keep working unchanged.
///
/// 一个上报事件名：mova 内置项之一，或宿主经 [MovaReportName.custom] 自定义。
///
/// 0.2.x 之前是 `enum`。在名称上做 `switch` 的宿主请改成对 [value]（`String`）
/// 做 switch——Dart 不允许对重写了 `==` 的类型使用常量模式。相等性/`hashCode`
/// 按 [value] 计算，因此 `==` 比较与 `Map`/`Set` 键的用法完全不变。
///
/// Example / 示例:
/// ```dart
/// api.report(const MovaReportName.custom('com.acme-fav-tap'));
/// if (e.name == MovaReportName.play) { … }
/// switch (e.name.value) { case 'play': … }
/// ```
class MovaReportName {
  /// The wire name; what analytics backends see.
  ///
  /// 上报到分析后端时看到的名字。
  final String value;

  const MovaReportName._(this.value);

  /// A host-defined name. Prefix it reverse-DNS style (CMCD's convention for
  /// custom keys) so it can never collide with a future mova built-in.
  ///
  /// 宿主自定义的名称。建议用反向 DNS 前缀（CMCD 对自定义键的约定），
  /// 以保证永远不会与 mova 未来的内置项撞名。
  const MovaReportName.custom(this.value) : assert(value != '');

  // 既有 13 项原样保留，调用点零改动
  static const sourceChange = MovaReportName._('sourceChange');
  static const play = MovaReportName._('play');
  // …

  // 本计划新增 6 项内置
  static const firstFrame = MovaReportName._('firstFrame');
  static const startupFail = MovaReportName._('startupFail');
  static const rebuffer = MovaReportName._('rebuffer');
  static const sessionStart = MovaReportName._('sessionStart');
  static const sessionEnd = MovaReportName._('sessionEnd');
  static const heartbeat = MovaReportName._('heartbeat');

  /// Every built-in name; custom names are not in here.
  ///
  /// 全部内置名称；自定义名称不在其中。
  static const List<MovaReportName> values = [ … ];

  /// Enum-source-compatible alias of [value].
  ///
  /// 与枚举写法兼容的 [value] 别名。
  String get name => value;

  @override
  bool operator ==(Object other) => other is MovaReportName && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
```

**已评估并否决的备选**：保留 `enum` 再加一个 `String? customName` 字段。否决理由——
消费方每次都要检查两个字段，且 `name` 对自定义事件而言是个谎（只能填一个占位项），
业界（CMCD 自定义键、ExoPlayer `getCustomData()`、video.js 任意字符串事件名）没有
一家是这么做的。

**破坏面**（必须写进 CHANGELOG）：① 不再有 `MovaReportName.values.byName()`；
② 不能再把它用作 `switch` 的常量模式（改 switch `.value`）；③ `.index` 消失。
`MovaApi.report(MovaReportName name, …)` 签名不变，既有调用点一行不改。

### D6 — 会话级不变字段：只加 `sessionId` 一个顶层字段，其余留给宿主

**加**：`MovaReportEvent.sessionId`（`String?`，默认 `null`，由 collector 统一注入
到本会话的每一条事件上）。理由：CMCD 把 `sid` 列为 Session 类必备；而它是宿主
**唯一无法自行重建**的字段——攒批发送时，宿主手上只有一堆 `MovaReportEvent`，没有
会话边界信息。生成用纯 Dart（时间戳 + `Random` 十六进制），**不引入 `uuid` 依赖**，
与本仓库此前 sha1→FNV-1a 的取舍一脉相承；工厂函数可经 `MovaReportConfig` 注入，
单测得以拿到确定值。

**放进 `sessionStart.params` 的会话常量**（一次性，不随每条事件重复）：
`streamType`（vod/live）、`audioOnly`、`swapEnabled`、`uri`、`title`、
以及从 `MovaStatsProbe.sample()` 取到的 `hwdec`/`viaNetwork`/`fileFormat`。

**明确不加、留给宿主**：`viewerId`/`deviceId`（身份信息，插件不该采集）、
`networkType`/`osVersion`/`deviceModel`/`isp`/`地域`（宿主的分析 SDK 本来就有；
为它们把 `connectivity_plus`/`device_info_plus` 变成 mova 的硬依赖，违反本仓库
"引入新依赖需用户同意"与 preview 模块刻意做的 tree-shaking 取舍）。
宿主要带就在自己的 `MovaReporter.onReport` 里往 `params` 合并——这正是
"mova 只标准化不发送"分层的好处。

### D7 — 默认开关：维持"新功能默认关闭"约定（2026-09-29 用户拍板：`qoe` 默认 `false`）

规划阶段曾建议 `MovaReportConfig.qoe` 默认 `true`（理由：上报子系统本身已是
opt-in，`reporter == null` 时连订阅都不创建；再加一层默认关闭会让宿主接了
reporter 仍拿不到四大指标）。**用户已否决该建议，改回项目一贯的默认关闭约定**：

- **`MovaReportConfig.qoe` 默认 `false`**——宿主须显式
  `MovaOpts(report: MovaReportConfig(qoe: true))` 才会启用 TTFF/卡顿/会话/致命
  错误四大指标；默认状态下事件流与本计划落地前逐字节相同。
  **每个 Task 都要有一条"`qoe` 默认值（不传该参数）时事件流与基线逐条相同"的测试**。
- 心跳 `heartbeat` 默认 `null`（关闭），同样遵循默认关闭约定。
- `reporter == null` 时整条链路仍然一个订阅都不建、一个 `Timer` 都不起（两层
  开关叠加，任一层关闭都是零开销）。

### D8 — `MovaSwapEngine` 下的会话边界：明确不跨引擎合并

`MovaSwapEngine` 是 `MovaApi` 代理，真实 `MovaEngine` 由宿主的 `MovaEngineFact`
创建；无缝切换会把生效引擎整个换掉。本计划**不做跨引擎会话合并**：
QoE 会话的边界恒等于"**一个 `MovaEngine` 的一次 `open()`**"，广告→正片的无缝切换
因此产生两段会话。关联手段：`sessionStart.params` 带 `swapEnabled` 与
`renderEpoch`，宿主按 `sessionId` + 时间相邻性自行串联。
理由：跨引擎合并要求 `MovaSwapEngine` 自己持有一份聚合状态并在换指时迁移，这会把
`swap_engine.dart` 从"纯代理"变成"有状态的指标持有者"，与它现有设计冲突，风险面
远大于收益。**列为明确排除项**，如确有需求单独立项。

---

## 2. 文件结构

**新建（纯 Dart，`lib/src/core/report/`）**

| 文件 | 职责 | Task |
|---|---|---|
| `report/session_id.dart` | `newMovaSessionId()` 纯函数 + `MovaSessionIdFactory` typedef | 2 |
| `report/stats_probe.dart` | `MovaStatsProbe` 可选内核能力 + `MovaStatsSnapshot` + `MovaLogLine` | 3 |
| `report/collector.dart` | `MovaQoeCollector`（取代 `MovaReportTranslator` 的持有位，内部仍复用 `translateMovaEvent`） | 4 |
| `report/ttff.dart` | `MovaTtffTracker` 纯逻辑 | 5 |
| `report/stall.dart` | `MovaStallPolicy` / `MovaEdgeStall` / `MovaStall` | 6 |
| `report/session.dart` | `MovaSessionEnd` + `resolveSessionEnd()` 纯函数 + `MovaSessionTally` | 7 |
| `report/error_policy.dart` | `MovaErrorPolicy` / `MovaPrefixError` / `MovaErrorVerdict` | 8 |
| `options/report_config.dart` | `MovaReportConfig` | 2 |

**修改**

| 文件 | 改动 | Task |
|---|---|---|
| `lib/src/core/report/report.dart` | `MovaReportName` 枚举→值类 + 6 个新内置；`MovaReportEvent` 加 `sessionId` | 1, 2 |
| `lib/src/core/options/options.dart` | 加 `report` 节 + `copyWith`/`==`/`hashCode` + export | 2 |
| `lib/src/core/kernel/mpv_kernel.dart` | `implements MovaStatsProbe`：观察 `paused-for-cache`、转发 `stream.log`、实现 `sample()` | 3 |
| `lib/src/core/engine.dart` | `_reportTranslator` → `_qoe`；`open()` 首行打点；首帧/错误/完成/dispose 喂给 collector | 4–8 |
| `lib/src/core/report/translator.dart` | `MovaErrorEvent` 分支改由 collector 决定 fatal/code；`MovaQualityChange`/`MovaAbrDownShift` 补码率 | 8, 9 |
| `lib/mova.dart` | barrel 增补导出 | 1–8 |
| `test/support/fake_api.dart` | `FakeMovaApi.report` 适配新 `MovaReportName`；加 `FakeStatsProbe` | 1, 3 |
| `README.md` / `CHANGELOG.md` / `doc/SPEC.md` / `CLAUDE.md` | 文档 + 测试基线回写 | 11 |

**测试**：`test/core/report/{name,config,session_id,stats_probe,collector,ttff,stall,session,error_policy,bitrate,heartbeat}_test.dart`
+ 既有 `report_engine_test.dart`/`report_swap_test.dart`/`translator_test.dart` 增补
+ `test/core/openness_report_test.dart`（三件套对账）。

**测试数量推进**（基线 **859**）：
Task 1 → 869、2 → 879、3 → 886、4 → 894、5 → 906、6 → 920、7 → 936、8 → 948、
9 → 956、10 → 963、11 → 967。

---

## 3. Global Constraints

- 包名 `mova`，公开类前缀 `Mova`；`src/` 内文件名不带前缀。
- **`lib/src/core/**` 禁止 `import 'package:flutter/...'`；`test/core/purity_test.dart`
  的 `_mediaKitExceptions` 必须恒等于 `{'kernel/mpv_kernel.dart'}`，本计划任何 Task
  都不许改它。** 这直接决定了 Task 3 的形态：`MovaStatsProbe` **抽象**放在
  `core/report/`（纯 Dart），**实现**只能在 `mpv_kernel.dart` 里。
- 注释规则（`CLAUDE.md`）：每个类/方法/getter/字段都要注释，**先英文一句、空行、
  后中文**；公开 API 带参数/返回/示例。本计划代码块里的注释按原样抄。
- **不新增任何第三方依赖**（这是硬约束：sessionId 自己生成，不引 `uuid`；
  网络类型不采集，不引 `connectivity_plus`）。
- 每个 Task 一个 commit，`flutter analyze` 0 issues + `flutter test` 全绿再往下走，
  commit 信息用 `type(mova): message`。
- **既有 859 项测试一项都不许删。** 唯一允许的既有测试改动是 Task 1 因
  `MovaReportName` 类型变化产生的机械适配（若确有 `switch`/`.index` 用法）。
- 开放性契约：每个替用户做的决策必须齐**默认值 + 配置项 + 可注入策略**三样
  （Task 10 做成可执行对账测试）。

---

## Task 1：`MovaReportName` 双轨化

**Files:** Modify `lib/src/core/report/report.dart`、`lib/mova.dart`；
Test: `test/core/report/name_test.dart`（新建）+ 既有 `translator_test.dart` 机械适配。

**Produces:** §D5 的完整类定义（13 个既有内置常量值与今天的枚举名逐字相同，
保证 `event.name.name` 上报出去的字符串一字不变）+ 6 个新内置常量。

**Steps:**
1. 先写失败测试。
2. 枚举改 const 值类，`_('…')` 私有构造 + `custom` 公开构造。
3. `values` 静态列表按今天枚举顺序排列。
4. 全仓 `grep -rn "MovaReportName\." lib test example` 逐处确认编译通过。

**断言：**
- `MovaReportName.play.value == 'play'`、`.name == 'play'`、`.toString() == 'play'`；
- `MovaReportName.values.length == 19` 且不含任何 custom；
- `const MovaReportName.custom('x') == const MovaReportName.custom('x')` 且
  `identical(...)` 为 true（const 规范化）；
- 运行时构造的 `MovaReportName.custom(someVar)` 与 const 版本 `==` 相等（`==` 按
  `value`，非 identity）；
- 可作 `Map`/`Set` 键：`{MovaReportName.play: 1}[MovaReportName.custom('play')] == 1`；
- `MovaReportName.custom('')` 触发 assert（debug）。

**验收：** `flutter analyze` 0 issues；既有 `translator_test.dart` 全部断言**语义不变**
（仅在语法上适配）；测试 869。

---

## Task 2：`MovaReportConfig`、`MovaOpts.report`、`sessionId`

**Files:** Create `lib/src/core/options/report_config.dart`、
`lib/src/core/report/session_id.dart`；Modify `report.dart`（`MovaReportEvent.sessionId`）、
`options/options.dart`、`lib/mova.dart`；
Test: `test/core/report/config_test.dart`、`session_id_test.dart`、`test/core/options_test.dart`（增补）。

**Produces:**

```dart
/// Telemetry configuration: what mova computes on-device before handing
/// events to [MovaReporter]. Everything here is pure in-memory aggregation —
/// mova still never sends, batches, or schedules anything.
///
/// 埋点配置：mova 在把事件交给 [MovaReporter] 之前，在端上算哪些东西。
/// 这里的一切都是纯内存聚合——mova 依然从不发送、不攒批、不调度。
class MovaReportConfig {
  /// Master switch for the QoE layer (TTFF / rebuffer / session / fatal).
  /// `true` by default: the whole reporting subsystem is already opt-in
  /// behind a `null` reporter, so a second default-off layer would just
  /// reproduce the gap this exists to fill. Defaults to `false` per this
  /// project's opt-in convention for new capabilities.
  ///
  /// QoE 层（首帧/卡顿/会话/致命错误）的总开关。默认 `false`，遵循项目"新
  /// 功能默认关闭"的一贯约定；不传该参数时事件流与本功能落地前逐字节相同。
  /// 显式设为 `true` 才会启用 TTFF/卡顿/会话/致命错误四大指标。
  final bool qoe;

  /// Stalls shorter than this are swallowed as noise; mpv coalesces
  /// property-change notifications, so sub-frame flaps are not real stalls.
  ///
  /// 短于此值的卡顿按噪声吞掉；mpv 会合并属性变更通知，亚帧级翻转不是真卡顿。
  final Duration minStall;

  /// Emits a periodic `heartbeat` report when non-null. `null` (off) by
  /// default — long sessions that never end would otherwise be the only way
  /// to lose aggregates, and that is the host's call, not mova's.
  ///
  /// 非空时按周期发 `heartbeat` 上报。默认 `null`（关闭）——只有"长会话迟迟
  /// 不结束"才会丢掉汇总量，要不要为此付出一个常驻 Timer 是宿主的决定。
  final Duration? heartbeat;

  /// Injectable stall aggregator; `null` selects [MovaEdgeStall] seeded from
  /// [minStall].
  ///
  /// 可注入的卡顿聚合器；为 `null` 时选用由 [minStall] 构造的 [MovaEdgeStall]。
  final MovaStallPolicy? stallPolicy;

  /// Injectable fatal/code classifier; `null` selects [MovaPrefixError].
  ///
  /// 可注入的致命性/错误码判据；为 `null` 时选用 [MovaPrefixError]。
  final MovaErrorPolicy? errorPolicy;

  /// Injectable session-id factory; `null` selects [newMovaSessionId].
  ///
  /// 可注入的会话 ID 工厂；为 `null` 时选用 [newMovaSessionId]。
  final MovaSessionIdFactory? sessionId;

  const MovaReportConfig({
    this.qoe = false,
    this.minStall = const Duration(milliseconds: 200),
    this.heartbeat,
    this.stallPolicy,
    this.errorPolicy,
    this.sessionId,
  });

  /// A fresh stall policy instance; policies carry per-session state.
  ///
  /// 新建一个卡顿策略实例；策略带有每会话的累积状态。
  MovaStallPolicy newStallPolicy() => stallPolicy ?? MovaEdgeStall(minStall: minStall);

  /// The error policy actually in effect.
  ///
  /// 实际生效的错误判据。
  MovaErrorPolicy get effectiveErrorPolicy => errorPolicy ?? const MovaPrefixError();

  MovaReportConfig copyWith({...});
}
```

`MovaReportEvent` 追加 `final String? sessionId;`（构造参数可选、默认 `null`，
不破坏任何既有构造点）。

`newMovaSessionId()`：`'${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
'-${Random().nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0')}'`，
**不引入 `uuid`**。

**断言：** 默认值全覆盖；`newStallPolicy()` 每次返回不同实例；
`MovaOpts().report == const MovaReportConfig()`；`copyWith` 单字段替换；
`MovaOpts.copyWith(report: …)` 不影响其他节；`newMovaSessionId()` 连续 1000 次无重复；
注入的工厂被真正使用。

**验收：** 测试 879；`MovaReportEvent` 既有构造点一处未改。

---

## Task 3：`MovaStatsProbe` 可选内核能力

**为什么做成"可选接口"而不是给 `MovaKernel` 加抽象成员：** `MovaKernel` 是 core 层
的核心抽象，所有测试假内核都实现它——加抽象成员会一次性打断数十个测试替身。
改用 `implements MovaStatsProbe` 的**可选能力**，`MovaEngine` 做
`final p = _kernel; if (p is MovaStatsProbe) …`，既有假内核一行不动。
（这是本仓库既有范式的延伸：`renderHandle` 放宽为 `Object?` 时用的也是"不加必选
契约"的思路。）

**Files:** Create `lib/src/core/report/stats_probe.dart`；
Modify `lib/src/core/kernel/mpv_kernel.dart`、`lib/mova.dart`、`test/support/fake_api.dart`；
Test: `test/core/report/stats_probe_test.dart`、既有 `test/core/purity_test.dart`（**不改**，
只需仍然通过）。

**Produces:**

```dart
/// Optional kernel capability exposing libmpv's own statistics. A kernel that
/// does not implement it simply degrades the QoE layer — never an error.
///
/// 可选的内核能力，暴露 libmpv 自己的统计量。未实现它的内核只会让 QoE 层降级，
/// 绝不构成错误。
abstract class MovaStatsProbe {
  /// True exactly while playback is stopped waiting for the cache — mpv's
  /// `paused-for-cache`. This is the *real* rebuffer signal; the kernel's
  /// `buffering` stream is media_kit's merge of `core-idle` and
  /// `paused-for-cache` and also fires on pause/seek/startup.
  ///
  /// 恰在"播放因等待缓存而停住"期间为 true——即 mpv 的 `paused-for-cache`。
  /// 这才是真正的卡顿信号；内核的 `buffering` 流是 media_kit 把 `core-idle` 与
  /// `paused-for-cache` 合并后的产物，暂停/seek/起播时也会触发。
  Stream<bool> get stalling;

  /// mpv's error-level log lines, with the subsystem prefix the kernel's
  /// `error` stream throws away.
  ///
  /// mpv 的 error 级日志行，带上内核 `error` 流丢掉的那个子系统 prefix。
  Stream<MovaLogLine> get logs;

  /// One-shot sample of libmpv's counters; `null` when unavailable.
  ///
  /// 对 libmpv 各计数器取一次样；取不到时返回 `null`。
  Future<MovaStatsSnapshot?> sample();
}

/// A single sample of libmpv's playback counters.
///
/// libmpv 各播放计数器的一次采样。
class MovaStatsSnapshot {
  /// Encoded video bitrate in bps (mpv `video-bitrate`, CMCD `br`).
  ///
  /// 视频编码码率（bps；mpv `video-bitrate`，对应 CMCD `br`）。
  final int? videoBps;

  /// Measured network throughput in bytes/s over a 1s window
  /// (mpv `cache-speed`, CMCD `mtp`).
  ///
  /// 1 秒窗口内的实测网络吞吐（字节/秒；mpv `cache-speed`，对应 CMCD `mtp`）。
  final int? inputBps;

  /// Frames dropped by the video output (mpv `frame-drop-count`).
  ///
  /// 视频输出侧丢帧数（mpv `frame-drop-count`）。
  final int? voDrops;

  /// Frames dropped by the decoder (mpv `decoder-frame-drop-count`).
  ///
  /// 解码器侧丢帧数（mpv `decoder-frame-drop-count`）。
  final int? decoderDrops;

  /// Active hardware decoder, or `no` for software (mpv `hwdec-current`).
  ///
  /// 当前生效的硬解方式，软解时为 `no`（mpv `hwdec-current`）。
  final String? hwdec;

  /// Whether the stream is most likely played over the network
  /// (mpv `demuxer-via-network`).
  ///
  /// 该流是否很可能走网络播放（mpv `demuxer-via-network`）。
  final bool? viaNetwork;

  /// Container format name (mpv `file-format`).
  ///
  /// 容器格式名（mpv `file-format`）。
  final String? fileFormat;
  …
}
```

**`MovaMpvKernel` 侧实现要点（必须逐条写成代码注释）：**
1. `stalling`：构造期
   `(_player.platform as NativePlayer).observeProperty('paused-for-cache', cb)`，
   `cb` 收到的是字符串 `'yes'`/`'no'`（media_kit 固定用 `MPV_FORMAT_NONE` 注册、
   回调里 `mpv_get_property_string` 取值）。
   **永不调用 `unobserveProperty`**——reply id 是 `property.hashCode`，与 media_kit
   内建注册撞号，注销会一次性干掉 media_kit 自己的 `buffering` 流（§0.1 约束 A）。
   `platform` 不是 `NativePlayer`（web）时，`stalling` 退化为空流。
2. `logs`：`_player.stream.log`（`PlayerLog{prefix, level, text}`）过滤
   `level == 'error'` 后映射成 `MovaLogLine`。media_kit 的默认
   `PlayerConfiguration.logLevel` 就是 `MPVLogLevel.error`，无需额外配置。
3. `sample()`：并发 `getProperty()` 七个属性，逐个 try/catch 吞掉不可用项
   （手册：多数属性在无视频/无网络时"unavailable"）。`audioOnly` 时视频侧三项
   直接返回 `null`，不发无谓请求。
4. **丢帧计数不做绝对值上报**：手册**未声明**换片是否清零，因此只在会话首尾各采
   一次、上报差值；差值为负（说明确实清零过）时退化为上报末次绝对值。

**断言（用 `FakeStatsProbe`，不碰真 mpv）：**
- `MovaStatsProbe` 未实现时 collector 正常降级、无异常；
- `stalling` 的 `'yes'`/`'no'` 解析；
- `logs` 只透传 `level == 'error'`；
- `sample()` 单项失败不影响其余项（返回带 `null` 字段的快照，而非整体 `null`）；
- `audioOnly` 快照的 `videoBps`/`voDrops`/`decoderDrops` 恒为 `null`；
- `test/core/purity_test.dart` 仍然通过且 `_mediaKitExceptions` 未改。

**验收：** 测试 886。

---

## Task 4：`MovaQoeCollector` 骨架接线（空指标，关闭态零改变）

**Files:** Create `lib/src/core/report/collector.dart`；
Modify `lib/src/core/engine.dart`、`lib/mova.dart`；
Test: `test/core/report/collector_test.dart`、既有 `report_engine_test.dart`（增补）。

**Produces:** `MovaQoeCollector` 取代 `MovaEngine._reportTranslator` 的持有位。
它**内部仍然复用 `translateMovaEvent()`**（白名单逻辑一行不动），只是在外面套上
会话状态：持有 `sessionId`、`MovaStallPolicy`、`MovaTtffTracker`、`MovaSessionTally`，
并给每一条出站事件补上 `sessionId`。

```dart
/// Owns one playback session's QoE state and turns raw signals into report
/// events. Constructed by [MovaEngine] only when a reporter is present;
/// `MovaReportConfig.qoe == false` makes it a pure passthrough that behaves
/// byte-for-byte like the old `MovaReportTranslator`.
///
/// 持有一次播放会话的 QoE 状态，把原始信号转成上报事件。仅当存在 reporter 时
/// 由 [MovaEngine] 构造；`MovaReportConfig.qoe` 为 `false` 时它退化为纯直通，
/// 行为与旧的 `MovaReportTranslator` 逐字节一致。
class MovaQoeCollector {
  MovaQoeCollector({
    required Stream<MovaEvent> events,
    required MovaReporter reporter,
    required MovaReportConfig config,
    MovaStatsProbe? probe,
    DateTime Function() now = DateTime.now,
  });

  /// Marks the start of a new session; called from the first line of
  /// [MovaEngine.open].
  ///
  /// 标记一次新会话的开始；由 [MovaEngine.open] 的第一行调用。
  void onOpen(MovaSource source, {required bool autoPlay});

  /// Terminates the current session (new `open()` or `dispose()`).
  ///
  /// 终结当前会话（新的 `open()` 或 `dispose()`）。
  void onTeardown();

  Future<void> cancel();
}
```

`engine.dart` 改动（全部是增量，不动既有语句顺序）：
- `open()` **第一行**（`final gen = ++_openGen;` 之前）插 `_qoe?.onOpen(source, autoPlay: autoPlay)`；
- `open()` 在 `onOpen` 之前先 `_qoe?.onTeardown()`（上一段会话的终结）；
- `dispose()` 里 `_qoe?.onTeardown()` 后再 `cancel()`。

**断言：**
- `reporter == null` 时 collector 不被构造、`MovaStatsProbe` 不被订阅（用一个会在
  被订阅时置位的假 probe 断言）；
- `qoe: false` 时，一段"open→play→pause→seek→done"的事件序列产出的
  `MovaReportEvent` 列表与 Task 0 基线**逐条相同**（名称/kind/priority/params 全等），
  且 `sessionId` 为 `null`；
- `qoe: true` 时同一序列的既有 13 条事件**名称/kind/priority/params 不变**，仅多出
  `sessionId` 且同一会话内恒定；
- 跨两次 `open()` 的 `sessionId` 不同。

**验收：** 测试 894。这是"关闭态零改变"的锚点 Task，后续每个 Task 都要复跑它。

---

## Task 5：TTFF（`firstFrame` / `startupFail`）

**Files:** Create `lib/src/core/report/ttff.dart`；Modify `collector.dart`、`engine.dart`、`lib/mova.dart`；
Test: `test/core/report/ttff_test.dart`。

**Produces:** `MovaTtffTracker` 纯逻辑（无 `Timer`、无 `DateTime.now()` 内部调用，
时间一律由调用方传入，便于确定性单测）：

```dart
/// Measures "open() called → first frame actually playing" per §D1.
///
/// Armed on `open(autoPlay: true)`; lands on the first falling edge of the
/// kernel's `buffering` flag, which media_kit derives from mpv's `core-idle`
/// ("only false if there's actually video playing").
///
/// 按 §D1 测量"open() 调用 → 画面真正开始播"。
///
/// 在 `open(autoPlay: true)` 时武装；落在内核 `buffering` 标志的首个下降沿上——
/// 该标志由 media_kit 从 mpv 的 `core-idle` 推导（"只有真的在播画面时才为 false"）。
class MovaTtffTracker {
  void arm(DateTime at, {required bool autoPlay});
  Duration? onBuffering(bool buffering, DateTime at); // 非 null = 首帧刚落地
  bool get landed;
  void reset();
}
```

产出事件：
- `firstFrame`：`kind: event`，`priority: immediate`（起播失败时这条最值钱），
  `params: {'ttffMs': int, 'audioOnly': bool, 'streamType': 'vod'|'live'}`；
- `startupFail`：`kind: error`，`priority: immediate`，
  `params: {'reason': 'failed'|'abandoned', 'waitedMs': int}`，在 armed 未 land 的
  会话终结时发（`onTeardown`/fatal 错误）。

**断言：**
- `autoPlay: false` 时 `arm` 不进入 armed 态，后续 `buffering` 下降沿不产出任何事件；
- 只产出**一次** `firstFrame`（后续的 buffering 下降沿是卡顿恢复，不是首帧）；
- `ttffMs` 等于注入的两个时刻差；
- armed 未 land 就 `onTeardown()` → 一条 `startupFail{reason: 'abandoned'}`；
- armed 期间收到 fatal 错误 → `startupFail{reason: 'failed'}`，且**不再**额外发
  `abandoned`；
- `reset()` 后可重新 arm；
- `qoe: false` 时这两个名字一次都不出现。

**验收：** 测试 906。

---

## Task 6：卡顿聚合（`rebuffer`）

**Files:** Create `lib/src/core/report/stall.dart`；Modify `collector.dart`、`lib/mova.dart`；
Test: `test/core/report/stall_test.dart`。

**Produces:** §D2 的 `MovaStallPolicy` / `MovaEdgeStall` / `MovaStall{durationMs, at}`。

信号源优先级（collector 内）：
1. `MovaStatsProbe.stalling`（`paused-for-cache`）——**首选**，语义精确；
2. probe 不可用时退化到 `MovaBufferChange`，并在 `params` 打
   `'signal': 'buffering'` 标明精度较低（会把暂停/seek 误算进去），
   便于分析侧分桶——**宁可标注降级，也不悄悄给出一个口径不同的数**。

产出 `rebuffer`：`kind: event`，`priority: batched`，
`params: {'durationMs': int, 'positionMs': int, 'index': int, 'signal': 'cache'|'buffering'}`。

**断言：**
- 上升沿不产出事件，只有下降沿产出；
- 短于 `minStall` 的整段卡顿被吞掉、`index` 不递增；
- **首帧落地之前的卡顿一律不计**（属于 TTFF），`index` 从 1 开始于首帧之后；
- 换源 / `switchQuality` 后 `reset()`，`index` 归零；
- 注入自定义 `MovaStallPolicy` 时默认实现不被构造；
- probe 缺席时 `signal` 为 `'buffering'`，probe 在场时为 `'cache'`；
- 连续两次卡顿的 `durationMs` 各自独立、不累加。

**验收：** 测试 920。

---

## Task 7：会话开始与结束（`sessionStart` / `sessionEnd`，结束原因四分）

**Files:** Create `lib/src/core/report/session.dart`；Modify `collector.dart`、`lib/mova.dart`；
Test: `test/core/report/session_test.dart`。

**Produces:** §D3 的 `MovaSessionEnd` 枚举 + 纯函数：

```dart
/// Classifies how a session ended, per §D3. Pure: every input is explicit so
/// the whole four-way split is unit-testable without a kernel.
///
/// 按 §D3 判定会话结束原因。纯函数：所有输入都显式传入，四个分支无需内核即可单测。
///
/// - [fatalSeen]: a fatal error was recorded / 本会话记录过致命错误
/// - [completed]: playback reached the end / 播放已到达末尾
/// - [firstFrame]: whether the first frame ever landed / 首帧是否曾经落地
///
/// Returns the terminal reason / 返回终止原因。
MovaSessionEnd resolveSessionEnd({
  required bool fatalSeen,
  required bool completed,
  required bool firstFrame,
}) => fatalSeen
    ? MovaSessionEnd.failed
    : completed
        ? MovaSessionEnd.ended
        : firstFrame
            ? MovaSessionEnd.stopped
            : MovaSessionEnd.abandoned;
```

`MovaSessionTally`：累计 `watchedMs`（只在 `playing && !stalled` 期间累加）、
`stallCount`、`stallMs`、`maxPositionMs`、`durationMs`。

事件：
- `sessionStart`：`kind: event`，`priority: batched`，
  `params: {'uri', 'streamType', 'audioOnly', 'swapEnabled', 'title'?, 'hwdec'?,
  'viaNetwork'?, 'fileFormat'?}`（后三项来自 `sample()`，取不到就不放键）；
- `sessionEnd`：`kind: event`，**`priority: immediate`**（宿主进程随时可能被杀，
  必须立刻冲刷），`params: {'reason', 'watchedMs', 'completionPercent',
  'stallCount', 'stallMs', 'rebufferRate', 'ttffMs'?, 'voDrops'?, 'decoderDrops'?}`。
  - `rebufferRate = stallMs / (watchedMs + stallMs)`（腾讯云"平均卡顿率"、Mux
    Rebuffer Percentage 同式），分母为 0 时置 0；
  - `completionPercent = maxPositionMs / durationMs * 100`，直播或时长未知时不放该键；
  - 丢帧走 §Task 3 的首尾差值口径。

**断言：**
- 四个分支各一条用例，含 `failed` 优先于 `ended`（播完前先 fatal）；
- `abandoned` 仅在 `firstFrame == false` 且无 fatal 时出现；
- `watchedMs` 不把卡顿时间算进去；
- `rebufferRate` 的分母为 0 时不抛、返回 0；
- 直播源的 `sessionEnd` 无 `completionPercent` 键；
- `sessionEnd` 的 `priority` 恒为 `immediate`；
- 一次会话恰好一条 `sessionStart` + 一条 `sessionEnd`；`dispose()` 后再无事件。

**验收：** 测试 936。

---

## Task 8：错误 fatal/非 fatal 与可聚类错误码

**Files:** Create `lib/src/core/report/error_policy.dart`；
Modify `collector.dart`、`translator.dart`、`lib/mova.dart`；
Test: `test/core/report/error_policy_test.dart`、既有 `translator_test.dart`（增补）。

**Produces:** §D4 的 `MovaErrorPolicy` / `MovaPrefixError` / `MovaErrorVerdict{fatal, code}`。

`MovaErrorEvent` 的上报从 translator 里**移出**（translator 不再为它产出事件，
改由 collector 出，因为 fatal 判定需要"首帧是否已落地"这一会话状态）。
产出：`kind: error`，`params: {'error': String, 'fatal': bool, 'code': String}`，
`priority: fatal ? immediate : batched`。

collector 通过 `MovaStatsProbe.logs` 与 `MovaErrorEvent` 做**时间近邻配对**
（同一次错误既会进 mpv 日志流也会进 `stream.error`，媒体内容相同、prefix 只在日志流里），
配对窗口 200ms；配不上就以 `subsystem: null` 调用策略。

**断言：**
- 五类 prefix → 五种 `code` 的映射逐条覆盖；
- `ffmpeg`+`tcp:` 在首帧前判 fatal、首帧后判非 fatal；
- 非 fatal 的 `priority` 是 `batched`（这是本 Task 的降噪目的）；
- fatal 错误会让 `MovaSessionEnd` 变 `failed`（与 Task 7 的联动）；
- 注入自定义 `MovaErrorPolicy` 时默认实现不被构造；
- 日志流缺席（无 probe）时仍产出事件，`code == 'unknown'`、按首帧状态判 fatal；
- `qoe: false` 时 `MovaErrorEvent` 仍走**旧**路径（`params` 只有 `error`、恒
  `immediate`）——关闭态零改变。

**验收：** 测试 948。

---

## Task 9：码率数值补全（`qualityChange` / `abrDownShift`）

**Files:** Modify `collector.dart`、`translator.dart`；
Test: `test/core/report/bitrate_test.dart`、既有 `translator_test.dart`（增补）。

`qualityChange` 的 `params` 从 `{'quality': label}` 增补为
`{'quality', 'toBps'?, 'fromBps'?, 'width'?, 'height'?, 'reason': 'manual'}`；
`abrDownShift` 同构、`reason: 'abr'`。数值来自切换前后各一次
`MovaStatsProbe.sample()` 的 `videoBps`（mpv `video-bitrate`，CMCD `br`）。
`inputBps`（CMCD `mtp`）随 `heartbeat`/`sessionEnd` 走，不挂在切换事件上——
它是"请求级"量，挂在离散切换点上没有统计意义。

**断言：** probe 缺席时**不放**这些键（既有断言原样通过，这是向后兼容的关键）；
probe 在场时 `fromBps`/`toBps` 取自切换前后两次采样；
`reason` 在两个事件上分别为 `'manual'`/`'abr'`；`label` 键原样保留。

**验收：** 测试 956。

---

## Task 10：心跳（默认关闭）+ 开放性对账

**Files:** Modify `collector.dart`；Test: `test/core/report/heartbeat_test.dart`、
`test/core/openness_report_test.dart`（新建）。

`MovaReportConfig.heartbeat` 非空时起一个 `Timer.periodic`，产出 `heartbeat`：
`kind: event`，`priority: batched`，`params: {'watchedMs', 'positionMs', 'stallCount',
'stallMs', 'videoBps'?, 'inputBps'?}`。**暂停期间不发**（没有新信息，纯噪声）。
`dispose()` 必须取消 Timer。

`openness_report_test.dart`：对账本轮每个"替用户做的决策"都齐**默认值 + 配置项 +
可注入策略**三样——`stallPolicy`/`errorPolicy`/`sessionId` 三个注入点各一条，
`qoe`/`minStall`/`heartbeat` 三个配置项各一条。

**断言：** 默认 `heartbeat == null` 时**不创建任何 Timer**（用 `fakeAsync` 断言
`pendingTimers` 为空）；开启后按间隔产出；暂停期间不产出；`dispose()` 后不再产出。

**验收：** 测试 963。

---

## Task 11：文档与 example

**Files:** `README.md`、`CHANGELOG.md`、`doc/SPEC.md`、`CLAUDE.md`、
`example/lib/main_telemetry_verify.dart`（新建 demo 页）。

- `CHANGELOG.md` 必须显式写出 §D5 的**破坏性变更**三条；
- `README.md` 补"QoE 指标"一节，给一个把 `MovaReportEvent` 转成常见分析 SDK 调用的
  示例，并重申"mova 不发送"；
- `doc/SPEC.md` 加"埋点与 QoE"一节，收录 §0 的 libmpv 能力对照表与 §0.1 的两条
  media_kit 约束（这两条是后来者最容易踩的坑）；
- `CLAUDE.md`：**用当次实测数字回写测试基线**（815 → 本轮最终数），并补一条
  "埋点 QoE 层"的当前状态；
- example 新建**独立** demo 页（不与其他 spike 混用），把每条 `MovaReportEvent`
  连同 `at`/`sessionId` 打到屏幕与 logcat，供真机验证取真实时间戳。

**验收：** 测试 967；`flutter analyze` 0 issues。

---

## 4. 真机验证（单独一轮，不计入上述 Task）

按 `CLAUDE.md` 的硬约定，**先设计基于真实事件的测量方法，再上机**：

| 验证项 | 测量方法（不用墙钟、不用临近 EOF 的 seek） | 通过判据 |
|---|---|---|
| TTFF 真实性 | demo 页记录 `open()` 调用时刻与 `firstFrame` 事件的 `at`，同时用 `adb shell screencap` 连续抓帧对齐首个非黑帧 | `ttffMs` 与抓帧结论同量级（抓帧间隔约 250–330ms，只做量级对账） |
| 卡顿计数准确性 | 真机真实断网/限速（不是构造 buffering 布尔），对比 `rebuffer` 事件条数与 logcat 里 `paused-for-cache` 的翻转次数 | 条数一致，`durationMs` 之和与断网时长同量级 |
| 卡顿信号优劣对账 | 同一段播放同时记录 `signal: 'cache'` 与退化路径的 `'buffering'` 计数 | `buffering` 路径应**明显高估**（暂停/seek 被计入），证实 §D2 的判断 |
| 四分终止态 | 四个场景各跑一次：看完 / 中途 `dispose()` / 坏 URL / 起播中途退出 | 四条 `sessionEnd.reason` 分别为 ended/stopped/failed/abandoned |
| 错误 prefix 分类 | 坏地址（`stream`）、坏码流（`vd`）各一次，读 `code` | 与 §D4 表一致 |
| 关闭态零改变 | `qoe: false` 跑一遍完整流程，逐条比对事件 | 与基线逐条相同 |

防缓存：所有测试 URL 加 timestamp 查询参数；每项多次取平均。

---

## 5. 明确排除项

**本次不做，且不应被后续 Task 悄悄纳入：**

1. **网络发送 / 攒批 / 调度 / 重试 / 落盘**——这是宿主职责，与 ExoPlayer
   `AnalyticsListener` 的分层一致。本计划新增的一切聚合都是纯内存计数，
   **不引入任何 HTTP 客户端**。
2. **设备/网络/系统/地域维度采集**（`networkType`/`osVersion`/`deviceModel`/`isp`/
   `viewerId`/`deviceId`）——见 §D6，采集它们要么引新依赖、要么触及身份信息，
   宿主的分析 SDK 本来就有。
3. **广告四分位（25/50/75%）与广告段边界事件**（调研 B5）——`MovaAdController` 已有
   全部时序信息，接线不难，但它是**广告计费**域、有 VAST/IMA 自己的规范约束，
   与 QoE 指标正交，单独立项更干净。
4. **CMCD/CMSD 线格式的生成与发送**（`CMCD-Request` 头、Event Mode POST）——
   本计划只借用 CMCD 的**字段语义与分类**，不产出符合 CTA-5004-B 的报文。
5. **`MovaReportKind` 扩成 QoS/QoE/business 三分**（调研 C3）——那是与 kind 正交的
   维度，硬塞进 kind 会把它撑成七八个值。要补就另加可选字段，不在本轮。
6. **高频手势事件放开**（音量/亮度/缩放/锁定/fit/rate/时移）——继续排除。
   唯一可考虑的语义点是静音/取消静音（CMCD `e=m`/`e=um`），本轮也不做。
7. **跨 `MovaSwapEngine` 的会话合并**——见 §D8，会话边界恒为"一个 `MovaEngine` 的
   一次 `open()`"，广告切换产生两段会话。
8. **`feed` 引擎池的会话归属**——引擎池是"多引擎同时在场"模型，与单会话模型结构性
   不匹配，与无缝切换计划当初排除 feed 的理由相同。
9. **fork media_kit 以拿到 `MPV_EVENT_PLAYBACK_RESTART` / `MPV_EVENT_END_FILE`**——
   §D1/§D3 已论证代价远超收益。若将来自建 libmpv 的 FFI 层（见 `CLAUDE.md` 里
   "自建时导出轻量 FFI 抽帧函数"那条待办），可一并重估这两条通道。
10. **CTA-2066 逐条口径对齐**——该标准只有 PDF 公开版，调研笔记末尾已注明未逐字
    提取。本计划的 `rebufferRate`/`completionPercent` 口径取的是腾讯云/Mux 的公开
    定义，若将来要与 CTA-2066 严格对齐需单独一轮。
