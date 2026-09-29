# 播放器埋点上报的业界实践调研（对照 `MovaReporter` 现状）

> 2026-09-29 · 调研笔记 · 对应刚落地的 `lib/src/core/report/`（`MovaReporter`）
>
> 结论先行：**`MovaReporter` 的"只标准化、不发送"这条主干设计是对的，与 ExoPlayer
> `AnalyticsListener` / CMCD v2 Event Mode 的分层一致；但当前白名单是一份"UI 动作
> 流水"，而不是"播放质量数据源"——业界公认的四大 QoE 指标（起播耗时 TTFF、卡顿次数
> 与时长、播放失败、会话开始/结束）在 mova 现有的 12 个 `MovaReportName` 里一个都
> 拿不到。**`MovaReportName` 纯枚举、运行时不可扩展也是真实缺陷，业界（CMCD 自定义
> 键、Bitmovin customData、ExoPlayer `getCustomData()`）无一例外都留了自定义双轨。

本文所有结论都标注了一手来源（规范原文 / 官方 API 文档 / 厂商文档），链接见文末。

---

## 0. mova 现状速览（作为对照基准）

读的是 `lib/src/core/report/report.dart`、`lib/src/core/report/translator.dart`、
`lib/src/core/events/events.dart`、`lib/src/core/api.dart`：

- 事件类别：`MovaReportKind{action, event, error}` 三分。
- 优先级：`MovaReportPriority{immediate, batched}` 二分，**仅打标签**，mova 自身不调度。
- 名称：`MovaReportName` 枚举 **12 项**（`sourceChange`/`play`/`pause`/`seek`/`seeked`/
  `done`/`error`/`qualityChange`/`abrDownShift`/`fullScreenChange`/`pipChange`/
  `miniChange`/`liveEdgeReach`——实为 13 个常量，去掉 `error` 后 12 个非错误项）。
- 两条产出路径：`translateMovaEvent()` 白名单自动映射 + `MovaApi.report(name, params)`
  手动上报。
- `MovaEvent` 全集实为 **29 个**（`events.dart` 逐个数：Ready/SourceChange/Play/Pause/
  Done/Seek/Seeked/BufferChange/DurationChange/SizeChange/VolumeChange/BrightChange/
  RateChange/QualityListChange/QualityChange/AbrDownShift/FitChange/ZoomChange/
  LockChange/FullScreenChange/OrientationChange/PipChange/MiniChange/TimeShiftChange/
  LiveEdgeReach/PreviewBlock/SttBlock/SwapChange/ErrorEvent），白名单覆盖 13 个。

---

## 1. 业界方案的事件分类体系

### 1.1 CMCD / CMSD（CTA-5004-B，v2）——按**数据生命周期**分类，不是按语义

CMCD 把每个键归入四类，判据是"这个值多久变一次"（[CTA-5004-B 规范正文][cta5004b]，
[ExoPlayer CMCD 文档][exo-cmcd]复述同一四分法）：

| 类别 | 含义 | 例子 |
|---|---|---|
| **CMCD-Object** | 随请求的**对象**变化 | `br` 编码码率、`d` 对象时长、`ot` 对象类型、`tb` 最高档码率 |
| **CMCD-Request** | 随**每次请求**变化 | `bl` 缓冲长度、`mtp` 实测吞吐、`dl` 截止时间、`nor` 下一个对象 |
| **CMCD-Status** | 不随每次请求变，但会变 | `bs` 缓冲饥饿、`rtp` 请求最大吞吐、`pr` 播放速率、`ec` 播放器错误码 |
| **CMCD-Session** | 整个会话内**不变** | `sid` 会话 ID、`cid` 内容 ID、`sf` 流格式、`st` 流类型、`v` 版本 |

> 对 mova 的直接启示：`MovaReportKind{action,event,error}` 是**语义分类**，
> CMCD 的四分是**生命周期分类**。两者正交，不冲突，但 mova 目前缺的正是
> "Session 级不变字段"这一层——见第 6 节。

### 1.2 ExoPlayer / Media3——**双层**：原始事件层 + 聚合指标层

这是本次调研里对 mova 最有参照价值的一条。[Media3 Analytics 官方指南][exo-analytics]
明确把分析拆成两层：

- **`AnalyticsListener`（原始事件层）**：实时逐条回调，每条带 `EventTime`（墙钟时间 +
  播放列表位置 + media item）。回调按域分组（[AnalyticsListener 源码][exo-al]）：
  - 播放状态：`onPlaybackStateChanged`、`onIsPlayingChanged`、`onPlayWhenReadyChanged`、
    `onPlaybackParametersChanged`、`onPositionDiscontinuity`
  - 媒体/轨道：`onTimelineChanged`、`onMediaItemTransition`、`onTracksChanged`、
    `onMediaMetadataChanged`
  - 加载/网络：`onLoadStarted`/`onLoadCompleted`/`onLoadCanceled`/`onLoadError`、
    `onDownstreamFormatChanged`、`onUpstreamDiscarded`、**`onBandwidthEstimate`**
  - 视频：**`onRenderedFirstFrame`**、**`onDroppedVideoFrames`**、
    `onVideoFrameProcessingOffset`、`onVideoDecoderInitialized`、`onVideoSizeChanged`、
    `onVideoCodecError`
  - 音频：**`onAudioUnderrun`**、`onAudioDecoderInitialized`、`onAudioSinkError`
  - DRM：`onDrmSessionAcquired`/`onDrmKeysLoaded`/`onDrmSessionManagerError`/…
  - 错误：`onPlayerError`、`onPlayerErrorChanged`
- **`PlaybackStatsListener`（聚合指标层）**：在端上做四步——事件解释（区分首次缓冲 vs
  再缓冲）、状态追踪、跨播放聚合、汇总指标计算；一次播放结束回调一次。字段含
  `totalPlayTimeMs`、`totalWaitTimeMs`、**`totalRebufferCount`**、
  `totalVideoFormatHeightTimeProduct`、`meanVideoFormatBitrate`、
  `meanTimeBetweenRebuffers`、`fatalErrorHistory`/`nonFatalErrorHistory`，派生方法
  `getRebufferRate()` 等。([Media3 Analytics 指南][exo-analytics])

`PlaybackStats` 还用了一套**扩展播放状态**（比 `Player.State` 更细，为的是区分"用户
在等"和"用户主动暂停"）：`JOINING_FOREGROUND`/`JOINING_BACKGROUND`/`NOT_STARTED` →
`PLAYING` → `BUFFERING`/`SEEKING`/`PAUSED`/`PAUSED_BUFFERING`/`SUPPRESSED`/
`INTERRUPTED_BY_AD` → `ENDED`/`STOPPED`/`FAILED`/`ABANDONED`。

### 1.3 hls.js——按**流水线阶段** + 独立错误分类轴

[hls.js API 文档][hlsjs]的事件按管线阶段命名：`MANIFEST_LOADING`/`MANIFEST_PARSED`、
`LEVEL_UPDATED`/`LEVELS_UPDATED`、`FRAG_LOADING`/`FRAG_PARSING_METADATA`/
`FRAG_BUFFERED`、`AUDIO_TRACK_SWITCHING`、`MEDIA_ATTACHED`、`FPS_DROP`、`ERROR`。

错误是**独立一条轴**，双维度：
- `ErrorTypes`：`NETWORK_ERROR` / `MEDIA_ERROR` / `KEY_SYSTEM_ERROR` / `MUX_ERROR` /
  `OTHER_ERROR`；
- `fatal` 布尔：`false` = hls.js 会自行恢复，`true` = 恢复手段耗尽，需要外部介入。

统计量另走属性而非事件：`hls.bandwidthEstimate`、`hls.latency`/`targetLatency`/`drift`、
`maxTimeToFirstByteMs`/`maxLoadTimeMs`、`hls.inFlightFragments`。

> 启示：**"错误是否致命"是与"错误类型"正交的第二个维度**。mova 当前把所有
> `MovaErrorEvent` 一律映射成 `name: error, priority: immediate`，没有 fatal/非 fatal
> 之分——而 ABR 降档失败、单个分片 404 这类可恢复错误若也 immediate 上报，会给宿主
> 制造噪声。

### 1.4 Shaka Player——事件 + 一个**统一 stats 快照**

Shaka 的做法是"少量事件 + 一个 `getStats()` 快照对象"。快照字段
（[shaka.extern.Stats][shaka-stats]）很值得逐个看，因为它几乎就是一份 QoE 字段清单：

`width`/`height`、`streamBandwidth`、`decodedFrames`、`droppedFrames`、
`corruptedFrames`、`estimatedBandwidth`、`completionPercent`、**`loadLatency`**、
`manifestTimeSeconds`、`drmTimeSeconds`、**`playTime`**、**`pauseTime`**、
**`bufferingTime`**、`licenseTime`、`liveLatency`、`maxSegmentDuration`、
**`gapsJumped`**、**`stallsDetected`**、`manifestSizeBytes`、`bytesDownloaded`、
**`switchHistory`**、**`stateHistory`**。

### 1.5 video.js——**薄壳**：原样转发 HTML5 媒体事件 + 任意字符串自定义事件

video.js 自身不定义 QoE 体系，`Player` 事件基本就是 HTML5 `HTMLMediaElement` 那一套加
几个 UI 事件：`loadstart`/`loadedmetadata`/`loadeddata`/`canplay`/`play`/`playing`/
`pause`/`waiting`/`stalled`/`suspend`/`seeking`/`seeked`/`timeupdate`/`progress`/
`durationchange`/`ended`/`error`/`ratechange`/`volumechange`/`resize`/`playerresize`/
`fullscreenchange`/`texttrackchange`，外加 `useractive`/`userinactive`/`sourceset`/
`ready`/`tap`。自定义事件走 `EventTarget` 的 `trigger`/`on`，**事件名是任意字符串**
（[video.js Player API][videojs-player]、[EventTarget][videojs-et]）。

> 启示：video.js 这条路线说明"纯字符串事件名"在插件层是可接受的常见选择——但它
> 也因此把 QoE 语义完全外包给了 mux.js/videojs-contrib-quality-levels 之类的上层。

### 1.6 Google IMA SDK——广告有**自己独立的一套生命周期事件**

[google.ima.AdEvent.Type][ima] 的分组：

- 生命周期：`LOADED`、`STARTED`、`COMPLETE`、`ALL_ADS_COMPLETED`、`AD_BREAK_READY`、
  `AD_BREAK_FETCH_ERROR`、`CONTENT_PAUSE_REQUESTED`、`CONTENT_RESUME_REQUESTED`
- 进度/四分位：`AD_PROGRESS`、`FIRST_QUARTILE`、`MIDPOINT`、`THIRD_QUARTILE`、
  `AD_BUFFERING`、`AD_CAN_PLAY`、`PAUSED`/`RESUMED`、`DURATION_CHANGE`
- 用户交互：`CLICK`、`VIDEO_CLICKED`、`VIDEO_ICON_CLICKED`、`SKIPPED`、
  `SKIPPABLE_STATE_CHANGED`、`USER_CLOSE`、`VOLUME_CHANGED`/`VOLUME_MUTED`、
  `LINEAR_CHANGED`、`INTERACTION`
- 计费/元数据：`IMPRESSION`、`AD_METADATA`、`LOG`（非致命错误）

**四分位（25%/50%/75%）是广告计费的行业刚需**，不是可选装饰。

### 1.7 国内厂商

- **阿里云点播播放质量监控**（[文档][aliyun-qos]）明确分 **QoS / QoE 两组**：
  QoS = 播放量、实际播放量（= 总播放量 − 播放失败 − 起播放弃）、**首帧时间（ms）**；
  QoE = 访问用户数、人均播放次数、平均视频时长。上报维度含终端类型、系统类型、
  分辨率、网络类型、SDK 版本、视频格式、是否硬解、运营商、域名、国家/省份。新版另加
  卡顿率、网络延迟、播放成功率。**埋点开关由 `setTraceId` 控制**（不传=默认开启埋点，
  传 traceId 则额外解锁单点追查）。
- **腾讯云点播播放质量监控**（[文档][tencent-qos]）核心三指标：**平均首帧耗时**
  （发起播放→首帧渲染完成）、**平均卡顿率**（卡顿时长 / 总播放时长）、**播放失败率**；
  另有人均观看时长、人均播放次数、Top100 视频。注意其**强约束**：只支持腾讯云超级
  播放器 SDK + 必须用 FileID 播放，直接 URL 播放不可统计。

> 启示：两家国内厂商的"必测三件套"完全一致——**首帧耗时、卡顿率、播放失败率**。
> mova 当前这三个一个都测不出来。

---

## 2. 高频 vs 低频事件，及业界对高频事件的处理

mova 的 `translateMovaEvent()` 注释里已经列了排除理由（拖动手势逐像素触发、缓冲抖动
等），方向对，但业界的做法是**"排除"之外还有三档手段**：

1. **端上聚合成计数/时长，只报汇总**（最主流）。ExoPlayer 的 `PlaybackStatsListener`
   就是干这个的：`onDroppedVideoFrames` 是逐次回调的高频事件，但对外暴露的是
   `totalRebufferCount`、`meanTimeBetweenRebuffers`、时间加权的
   `totalVideoFormatHeightTimeProduct`。官方文档特别点明：**时间加权乘积字段单看没
   意义，但它是"多段 PlaybackStats 能正确合并求均值"的必要条件**；而事件历史
   （`playbackStateHistory`/`mediaTimeHistory`/错误列表）**不可聚合**，合并后的
   `PlaybackStats` 只保留计数器，丢弃逐条历史。([Media3 Analytics 指南][exo-analytics])
2. **快照轮询替代事件流**。Shaka 的 `getStats()` 把 `droppedFrames`/`bufferingTime`/
   `stallsDetected` 等做成随时可读的累计量，由宿主决定采样频率。([shaka.extern.Stats][shaka-stats])
3. **心跳 / 时间间隔上报**。CMCD v2 的 Event Mode 直接把"心跳"定义成一个事件类型：
   `e=t`（Time interval），与错误 `e=e`、码率变化 `e=bc` 平级；Event Mode 的语义就是
   "由预定义事件或**心跳间隔**触发，用 HTTP POST 批量发送到独立端点"。
   ([CTA-5004-B][cta5004b])
4. **节流/降采样**：hls.js 的 `FPS_DROP` 只在丢帧超阈值时抛，而非每帧。([hls.js][hlsjs])

> 对 mova 的启示：**"高频就不报"是一刀切，业界的标准答案是"高频事件端上聚合成
> 低频汇总"**。mova 现在把 `MovaBufferChange` 整个丢掉，代价是**连"卡了几次、卡了
> 多久"这个最核心的 QoE 指标都无法从上报流里还原**——这不是省噪声，是丢数据。

---

## 3. 紧急 vs 非紧急的划分标准

业界没有一个叫 "priority" 的通用字段，但**等价机制存在，且判据比 mova 当前的
"error/done 即 immediate" 细**：

- **CMCD v2 Event Mode 的触发条件即事实上的"紧急清单"**（[CTA-5004-B][cta5004b]）：
  `e` 键取值 `abs`(广告段开始)/`abe`(广告段结束)/`as`(广告开始)/`ae`(广告结束)/
  `sk`(跳过广告)/`b`(进入/退出后台)/`bc`(**码率变化**)/`c`(内容 ID 变化)/
  `e`(**播放器错误**)/`h`(主机名变化)/`m`(静音)/`um`(取消静音)/`pc`(播放器收起)/
  `pe`(播放器展开)/`pr`(播放速率变化)/`ps`(**播放状态变化**)/`rr`(收到响应)/
  `t`(**心跳**)/`ce`(自定义事件)。
  → 值得注意的是：**码率变化、播放状态变化、进入后台**都被列为需要独立触发上报的
  事件，而不是攒批。
- **hls.js 的 `fatal` 标志**是最直接的紧急度判据：非 fatal 错误播放器自恢复、无需惊动
  宿主；fatal 错误必须立即处理。([hls.js][hlsjs])
- **TTFF 超时 / 起播放弃**：阿里云把"起播放弃"单列进"实际播放量"的减项
  （[阿里云][aliyun-qos]）；Mux 的 **Exits Before Video Start** 指标定义是"点了播放、
  从未记录到 Video Startup Time、且不属于播放失败"——即**用户等不及走了**，与
  playback failure 明确区分开。([Mux 指标定义][mux-metrics]、[Mux Playback Success][mux-success])
- **连续 rebuffer**：Mux 的 Rebuffer Percentage = 再缓冲时长 ÷ 观看时长；腾讯云的
  "平均卡顿率"同式。([Mux][mux-metrics]、[腾讯云][tencent-qos])

> 结论：除 error/done 外，**至少这几类应算紧急**——① 致命错误（区别于可恢复错误）；
> ② 起播失败 / TTFF 超时 / 起播放弃；③ 会话结束（宿主进程可能随时被杀，必须立刻冲刷）；
> ④ 进入后台。反过来，mova 现在把**所有** `MovaErrorEvent` 一律 immediate，缺 fatal
> 维度，是噪声源。

---

## 4. 比 action/event/error 更精细的分类维度

三种在业界真实存在的更细维度，都比 mova 当前的三分更有信息量：

1. **QoS / QoE / 业务事件 三分**——阿里云文档就是这么组织的：QoS 是技术侧
   （首帧时间、播放量、失败量），QoE 是体验/业务侧（访问用户数、人均播放次数、
   平均观看时长）。([阿里云][aliyun-qos]) Mux 的六大顶层指标同构：Viewer Engagement
   （业务）、Overall Viewer Experience、Playback Success、Startup Time、Smoothness、
   Video Quality。([Mux][mux-metrics])
2. **按播放生命周期阶段分类**——ExoPlayer `PlaybackStats` 的扩展状态机就是一套阶段
   划分：加入期（JOINING_FOREGROUND/BACKGROUND）→ 播放期（PLAYING）→ 中断期
   （BUFFERING/SEEKING/PAUSED/INTERRUPTED_BY_AD）→ 终止期（ENDED/STOPPED/FAILED/
   ABANDONED）。**终止态区分 ENDED / STOPPED / FAILED / ABANDONED 是关键**：mova 只有
   `done`，无法区分"看完了""主动退出""失败退出""起播放弃"。([Media3][exo-analytics])
3. **数据生命周期分类**——CMCD 的 Object/Request/Status/Session 四分（见 1.1）。
   Session 类字段只需在会话开始时上报一次，这是 mova 完全缺失的一层。

另外 **CTA-2066《Streaming Quality of Experience Events, Properties and Metrics》**
是专门做这件事的行业标准：它定义一套统一的播放器事件、属性、QoE 指标**及其计算方法**，
目的就是"同一次会话在不同播放器/不同分析厂商那里算出同一个数"，涵盖 video start time、
video start failure、exits before video start、rebuffering ratio 等。
（[CTA 商店条目][cta2066-shop]、[公开版仓库][cta2066-gh]——注意公开版只提供 PDF，本次
未能逐字提取其完整指标表，此处引用的是仓库/商店页的范围描述，若要逐条对齐建议后续把
PDF 拉下来精读。）

---

## 5. 自定义扩展机制：业界一律是"内置 + 自定义"双轨

这是本次调研中结论最一致的一条——**没有任何一家是纯枚举、不可扩展的**：

| 方案 | 内置部分 | 自定义部分 | 约束 |
|---|---|---|---|
| **CMCD v2** | 保留键表（`br`/`bl`/`sid`/…，约 45 个） | **自定义键必须带连字符前缀**，`SHOULD` 用反向 DNS。格式 `<reverseDNS>-<namespaceAbbr>-<fieldAbbr>`，缩写只允许小写字母和数字，值类型必须是 STRING 或 TOKEN 且 **≤64 字符**。例：`org.svta-p-n`（player name）、`org.svta-a-ad`（audio-description）、`org.svta-co-g`（content genre） | SVTA 维护公共注册表（v1.1.0，16 条）避免撞名 ([key-schema][svta-schema]、[注册表仓库][svta-repo]) |
| **ExoPlayer CMCD** | `isKeyAllowed(key)` 过滤内置键 | `getCustomData(): ImmutableListMultimap<String,String>` 追加任意自定义键值，按 CMCD-Object/Request/Session/Status 归组 | ([ExoPlayer CMCD][exo-cmcd]) |
| **Bitmovin Analytics** | 固定的会话/QoE 字段 | `customData1` … `customData30`（订阅默认含 5 个，可扩至 50 个）；`setCustomData` / `setCustomDataOnce` 运行时可改；`DefaultMetadata` 与 `SourceMetadata` 按字段逐个合并、后者优先 | ([Bitmovin customData][bitmovin-cd1]、[字段数量][bitmovin-cd2]) |
| **Mux Data** | 固定指标 + 标准维度 | 自定义维度字段 | ([Mux][mux-metrics]) |
| **video.js** | HTML5 媒体事件 | `player.trigger('<任意字符串>')` | ([EventTarget][videojs-et]) |
| **IMA** | 固定 `AdEvent.Type` 枚举 | —（广告是强规范域，故意不开放） | ([IMA][ima]) |

> **所以：`MovaReportName` 纯枚举、运行时不可扩展，是真实设计缺陷。** mova 是一个
> 发布到 pub.dev 的**插件**，宿主 App 的业务事件（"点了收藏""弹幕开关""会员试看
> 到期"）永远不可能进 mova 的枚举，而这些恰恰是宿主最想和播放质量事件走同一条
> 上报管道的东西。唯一的反例 IMA 之所以能纯枚举，是因为广告事件受 VAST 规范约束、
> 本就不该由宿主扩展——mova 不是这种情况。

---

## 6. 标准字段清单

### 6.1 CMCD v2（CTA-5004-B）保留键全表 ([CTA-5004-B][cta5004b])

| 键 | 全名 | 类型 | 归类 |
|---|---|---|---|
| `ab` | Aggregate encoded bitrate | inner list (kbps) | Object |
| `br` | Encoded bitrate | inner list (kbps) | Object |
| `d` | Object duration | int (ms) | Object |
| `lab` | Lowest aggregated encoded bitrate | inner list (kbps) | Object |
| `lb` | Lowest encoded bitrate | inner list (kbps) | Object |
| `ot` | Object type | token | Object |
| `tab` | Top aggregated encoded bitrate | inner list (kbps) | Object |
| `tb` | Top encoded bitrate | inner list (kbps) | Object |
| `tpb` | Top playable bitrate | inner list (kbps) | Object |
| `bl` | Buffer length | inner list (ms) | Request |
| `cs` | Content signature | string | Request |
| `dfa` | Dropped frames absolute | int | Request |
| `dl` | Deadline | int (ms) | Request |
| `ltc` | Live stream latency | int (ms) | Request |
| `mtp` | Measured throughput | inner list (kbps) | Request |
| `nor` | Next object request | inner list | Request |
| `pb` | Playhead bitrate | inner list (kbps) | Request |
| `sn` | Sequence number | int | Request |
| `sta` | State | token | Request |
| `su` | Startup | bool | Request |
| `tbl` | Target buffer length | inner list (ms) | Request |
| `bg` | Backgrounded | bool | Status |
| `bs` | Buffer starvation | bool | Status |
| `bsa` | Buffer starvation absolute | inner list (int) | Status |
| `bsd` | Buffer starvation duration | inner list (ms) | Status |
| `bsda` | Buffer starvation duration absolute | inner list (ms) | Status |
| `ec` | Player error code | inner list (string) | Status |
| `nr` | Non rendered | bool | Status |
| `pr` | Playback rate | decimal | Status |
| `pt` | Playhead time | int (ms) | Status |
| `rtp` | Requested maximum throughput | int (kbps) | Status |
| `cid` | Content ID | string | Session |
| `msd` | **Media start delay**（即 TTFF） | int (ms) | Session |
| `sf` | Streaming format | token | Session |
| `sid` | Session ID | string | Session |
| `st` | Stream type | token | Session |
| `v` | Version | int | Session |
| `cen` | Custom event name | string | Event only |
| `cmsdd` / `cmsds` | CMSD 动态/静态头回传 | string | Event only |
| `e` | Event | token | Event only |
| `h` | Hostname | string | Event only |
| `rc` | Response code | int | Event only |
| `smrt` | SMRT-Data header | string | Event only |
| `ts` | Timestamp | int (ms) | Event only |
| `ttfb` / `ttfbb` / `ttlb` | 首字节 / 首正文字节 / 末字节耗时 | int (ms) | Event only |
| `url` | Request URL | string | Event only |

> 注意 `msd`（Media Start Delay）被归为 **Session** 类——即"每个会话只有一个起播
> 耗时"，这正是业界对 TTFF 的标准建模方式。

### 6.2 各家共有的、CMCD 之外的常见字段

汇总自 Shaka `getStats()`、Mux、阿里云、Bitmovin：

- **会话/身份**：sessionId（`sid`）、viewerId/deviceId、contentId（`cid`）、traceId
  （阿里云 `setTraceId`）、subPropertyId
- **环境**：playerName/playerVersion、sdkVersion、osName/osVersion、deviceModel、
  终端类型、**networkType**、运营商 ISP、国家/省份（阿里云维度列表[aliyun-qos]）
- **内容/编码**：videoId、videoTitle、streamType（vod/live）、videoFormat（hls/dash/mp4）、
  codec、resolution width/height、**是否硬解**（阿里云显式维度）
- **网络/CDN**：CDN 域名/节点、hostname（CMCD `h`）、responseCode（`rc`）、
  **bandwidthEstimate / estimatedBandwidth**、bytesDownloaded
- **缓冲/质量**：bufferLength（`bl`）、bufferHealth、**bufferingTime**、
  **stallsDetected**、gapsJumped、droppedFrames / decodedFrames / corruptedFrames
  （与 [W3C `VideoPlaybackQuality`][w3c-mpq] 的 `totalVideoFrames` /
  `droppedVideoFrames` / `creationTime` 一一对应；`corruptedVideoFrames` 已废弃）
- **时间**：playTime、pauseTime、watchTime、loadLatency、manifestTimeSeconds、
  drmTimeSeconds/licenseTime、liveLatency
- **播放进度**：playheadTime（`pt`）、completionPercent、**退出时完成度百分比**

---

## 7. mova 现状对照盘点表

### 7.1 `MovaEvent`（29） vs 上报白名单（13）

| `MovaEvent` | 已上报 | 业界怎么看 |
|---|---|---|
| `MovaSourceChange` | ✅ `sourceChange` | 对应 CMCD `e=c`（内容变化）+ `cid` |
| `MovaPlay` / `MovaPause` | ✅ | 对应 CMCD `e=ps`（播放状态变化） |
| `MovaSeek` / `MovaSeeked` | ✅ | ExoPlayer 有独立 SEEKING 状态并计入 `totalWaitTimeMs` |
| `MovaDone` | ✅ immediate | 但业界终止态分 ENDED/STOPPED/FAILED/ABANDONED 四种，mova 只有一种 |
| `MovaErrorEvent` | ✅ immediate | **缺 fatal/非 fatal 维度、缺错误码（CMCD `ec`）** |
| `MovaQualityChange` | ✅（只报 label） | **缺切换前后具体码率数值**（CMCD `br`/`tb`，Shaka `switchHistory`） |
| `MovaAbrDownShift` | ✅（from/to label） | 同上，缺码率数值与触发原因 |
| `MovaFullScreenChange` | ✅ | 对应 CMCD `e=pe`/`pc`（展开/收起） |
| `MovaPipChange` / `MovaMiniChange` | ✅ | mova 特有，合理 |
| `MovaLiveEdgeReach` | ✅ | 对应直播延迟指标（CMCD `ltc`、Shaka `liveLatency`） |
| **`MovaBufferChange`** | ❌ 被排除 | **最严重的一处**：全行业的卡顿率/rebuffer count 都从这里来（CMCD `bs`/`bsd`/`bsa`，ExoPlayer `totalRebufferCount`，Shaka `bufferingTime`/`stallsDetected`） |
| `MovaReady` | ❌（认为与 SourceChange 冗余） | **TTFF 的终点就在这里**：ExoPlayer 靠 `onRenderedFirstFrame`、CMCD 靠 `msd`。丢掉它就等于放弃首帧耗时 |
| `MovaDurationChange` / `MovaSizeChange` / `MovaQualityListChange` | ❌ 元数据 | Shaka 把 `width`/`height` 放进 stats；建议不作事件，而作**会话级属性**随其他事件带上 |
| `MovaRateChange` | ❌ 高频手势 | CMCD 明确列 `e=pr`（速率变化）为触发事件；建议**去抖后**保留 |
| `MovaVolumeChange` | ❌ 高频手势 | IMA 有 `VOLUME_CHANGED`/`VOLUME_MUTED`，CMCD 有 `e=m`/`e=um`；建议只报**静音/取消静音**这两个语义点 |
| `MovaTimeShiftChange` | ❌ 高频 | 建议聚合为"时移会话"（进入/退出 + 最大偏移） |
| `MovaBrightChange`/`MovaZoomChange`/`MovaLockChange`/`MovaFitChange`/`MovaOrientationChange` | ❌ | 纯 UI，排除合理（如需可走 `MovaApi.report` 手动上报） |
| `MovaPreviewBlock`/`MovaSttBlock`/`MovaSwapChange` | ❌ 内部诊断 | 排除合理；但 `MovaSwapChange` 在**广告场景**下等价于 IMA 的 `CONTENT_PAUSE/RESUME_REQUESTED`，宿主可能需要 |

### 7.2 业界标配但 mova **完全拿不到**的指标

| 指标 | 业界来源 | mova 现状 |
|---|---|---|
| **TTFF / 起播耗时（Video Startup Time）** | CMCD `msd`；ExoPlayer `onRenderedFirstFrame`；阿里云"首帧时间"；腾讯云"平均首帧耗时"；Mux Startup Time | ❌ 无 |
| **卡顿次数 + 卡顿总时长 + 卡顿率** | CMCD `bs`/`bsa`/`bsd`；ExoPlayer `totalRebufferCount`/`getRebufferRate()`；Shaka `bufferingTime`/`stallsDetected`；腾讯云"平均卡顿率" | ❌ 无（`MovaBufferChange` 被整个排除） |
| **播放会话开始 / 结束（含终止原因）** | ExoPlayer `PlaybackStats` 的 ENDED/STOPPED/FAILED/ABANDONED；Mux "View" 概念 | ❌ 只有 `done` |
| **退出时完成度百分比 / 观看时长** | Shaka `completionPercent`/`playTime`；Mux Watch Time；阿里云"平均视频时长" | ❌ 无 |
| **心跳 / 周期进度上报** | CMCD v2 `e=t`；各家 heartbeat | ❌ 无 |
| **起播失败 / 起播放弃（Exits Before Video Start）** | Mux EBVS；阿里云"起播放弃" | ❌ 无 |
| **码率切换的具体数值（before/after bps）** | CMCD `br`/`tb`；Shaka `switchHistory` | ⚠️ 只有 label 字符串 |
| **丢帧数** | W3C `droppedVideoFrames`；ExoPlayer `onDroppedVideoFrames`；Shaka `droppedFrames` | ❌ 无（libmpv 有 `frame-drop-count` 属性可取） |
| **带宽估计 / 实测吞吐** | CMCD `mtp`；hls.js `bandwidthEstimate`；Shaka `estimatedBandwidth` | ❌ 无 |
| **错误码（可聚类的）** | CMCD `ec`；hls.js `ErrorDetails` | ⚠️ 只有 `error.toString()` |
| **会话级不变字段（sessionId/streamType/format/playerVersion/networkType）** | CMCD Session 类；各家标配 | ❌ 无 |
| **广告四分位（25/50/75%）** | IMA `FIRST_QUARTILE`/`MIDPOINT`/`THIRD_QUARTILE`；CMCD `e=as`/`ae`/`abs`/`abe`/`sk` | ❌ 无（mova 有 `MovaAdController` 但未接上报） |

---

## 8. 改进建议（分三档）

### A. 必须改

**A1. `MovaReportName` 必须可扩展 —— 改成"内置枚举 + 自定义字符串"双轨。**
依据：CMCD v2 强制要求自定义键带连字符前缀并由 SVTA 维护注册表（[key-schema][svta-schema]）；
ExoPlayer 提供 `getCustomData()`（[ExoPlayer CMCD][exo-cmcd]）；Bitmovin 给 30–50 个
`customDataN` 槽位（[Bitmovin][bitmovin-cd1]）；video.js 事件名本就是任意字符串
（[EventTarget][videojs-et]）。唯一纯枚举的 IMA 是因为广告受 VAST 规范约束、本不该扩展。
mova 作为插件，宿主业务事件永远进不了枚举。
建议形态（保持类型安全 + 留出逃生舱）：
```dart
class MovaReportName {
  final String value;
  const MovaReportName._(this.value);
  static const play = MovaReportName._('play');
  // …内置项保持不变，调用点零改动
  /// 宿主自定义事件名，建议带反向 DNS 前缀避免与未来内置项撞名（对齐 CMCD 约定）。
  const MovaReportName.custom(this.value);
}
```
同时 `params` 已经是 `Map<String,dynamic>`，自定义字段那一半天然满足，无需改动。

**A2. 补上 TTFF（首帧耗时）。**
依据：CMCD 把它建模成 Session 级键 `msd`（[CTA-5004-B][cta5004b]）；ExoPlayer 有
`onRenderedFirstFrame`（[AnalyticsListener][exo-al]）；阿里云、腾讯云各自的第一个
QoS 指标都是它（[阿里云][aliyun-qos]、[腾讯云][tencent-qos]）。
做法：`open()` 打点 → 首个 `MovaReady`（或首帧渲染）落地，产出
`MovaReportName.firstFrame` + `params: {'ttffMs': …}`，`priority: immediate`（因为
起播失败时这条数据最值钱）。**注意 `MovaReady` 目前被 translator 当作"与 sourceChange
冗余"排除掉了——这个判断在纯事件视角下成立，在 QoE 视角下不成立。**

**A3. 把 `MovaBufferChange` 从"排除"改成"端上聚合"。**
依据：ExoPlayer 的整个 `PlaybackStatsListener` 就是为此存在，官方明确"事件解释
（区分首次缓冲 vs 再缓冲）→ 状态追踪 → 聚合"四步（[Media3 Analytics][exo-analytics]）；
CMCD 的 `bs`/`bsa`/`bsd`/`bsda` 四个键专门描述缓冲饥饿的次数与时长
（[CTA-5004-B][cta5004b]）；腾讯云/Mux 的卡顿率定义都需要它（[腾讯云][tencent-qos]、
[Mux][mux-metrics]）。
做法：内部维护 rebufferCount / rebufferTotalMs，在**会话结束**和**心跳**时随汇总一起
上报；单次 buffer 翻转不上报（保留现有的降噪意图），但**每次卡顿结束**可出一条
`rebuffer` 事件带 `durationMs`（这是低频的——真正高频的是 buffering 布尔抖动，不是
"卡顿完成"）。

**A4. 补"播放会话"的开始与结束，结束事件带终止原因和完成度。**
依据：ExoPlayer `PlaybackStats` 的终止态四分 ENDED/STOPPED/FAILED/ABANDONED
（[Media3][exo-analytics]）；Mux 的 "View" 定义与 Exits-Before-Video-Start 指标
（[Mux][mux-metrics]、[Mux Playback Success][mux-success]）；阿里云"实际播放量 = 总
播放量 − 播放失败 − 起播放弃"（[阿里云][aliyun-qos]）。
做法：新增 `sessionStart` / `sessionEnd`，`sessionEnd` 的 `params` 带
`{reason: ended|stopped|failed|abandoned, watchedMs, completionPercent,
rebufferCount, rebufferMs}`，`priority: immediate`（进程随时可能被杀）。

**A5. 错误事件补 fatal 维度与可聚类的错误码。**
依据：hls.js 的 `ErrorTypes` × `fatal` 双维度（[hls.js][hlsjs]）；ExoPlayer 分
`fatalErrorHistory` / `nonFatalErrorHistory`（[Media3][exo-analytics]）；CMCD 有
专门的 `ec`（Player error code）键（[CTA-5004-B][cta5004b]）。
做法：`params` 加 `{'fatal': bool, 'code': String}`；非 fatal 降为 `batched`。
（`error.toString()` 不可聚类，做不了 Top-N 错误排行。）

### B. 建议改

**B1. 增加会话级不变字段（Session 类）一次性上报。**
依据：CMCD 的 Session 分类与 `sid`/`cid`/`sf`/`st`/`v`（[CTA-5004-B][cta5004b]）；
阿里云的维度清单（SDK 版本/网络类型/是否硬解/分辨率/运营商）（[阿里云][aliyun-qos]）。
做法：mova 生成 `sessionId`（UUID），`sessionStart` 的 params 带
`{sessionId, streamType(vod/live), playerVersion, audioOnly, swapEnabled}`；
networkType 已有 `connectivity_plus` 依赖（preview 模块在用），可复用；deviceId/
viewerId 属宿主身份信息，**不要 mova 采集**，让宿主自己往 params 合并。

**B2. 增加心跳/周期进度上报（默认关闭，可配间隔）。**
依据：CMCD v2 Event Mode 把心跳 `e=t` 列为一等事件类型（[CTA-5004-B][cta5004b]）。
做法：`MovaReportConfig(heartbeat: Duration?)`，默认 `null` 关闭；开启时按间隔产出
`heartbeat` 事件，`params` 带累计 watchedMs / rebufferCount / 当前码率 / bufferHealth。

**B3. 码率切换带上前后的具体数值，而不只是 label。**
依据：CMCD `br`/`tb`/`lb`（[CTA-5004-B][cta5004b]）、Shaka `switchHistory` +
`streamBandwidth`（[Shaka Stats][shaka-stats]）、CMCD 事件 `e=bc`（Bitrate change）。
做法：`qualityChange`/`abrDownShift` 的 params 补 `fromBps`/`toBps`/`width`/`height`/
`reason(manual|abr)`。

**B4. 优先级从二值扩成"带 fatal/紧急判据"的分档，或至少记录判据。**
依据：CMCD Event Mode 的触发事件清单把"码率变化、播放状态变化、进入后台"都列为独立
触发（[CTA-5004-B][cta5004b]）；hls.js 的 fatal 语义（[hls.js][hlsjs]）。
做法：保持 `immediate/batched` 两值（够用），但**把归类判据写进文档并覆盖**：致命错误、
sessionEnd、firstFrame（含失败）、进入后台 → immediate；其余 batched。

**B5. 广告事件接入上报（四分位 + 广告段边界）。**
依据：IMA 的 `FIRST_QUARTILE`/`MIDPOINT`/`THIRD_QUARTILE`/`IMPRESSION`/`SKIPPED`
（[IMA][ima]）；CMCD v2 的 `e=abs/abe/as/ae/sk`（[CTA-5004-B][cta5004b]）。
mova 已有 `MovaAdController`，缺的只是接线。四分位是广告计费刚需，做广告业务的宿主
一定会问。

**B6. 丢帧数上报（低频聚合）。**
依据：W3C `VideoPlaybackQuality.droppedVideoFrames`/`totalVideoFrames`
（[W3C][w3c-mpq]）、ExoPlayer `onDroppedVideoFrames`、Shaka `droppedFrames`。
libmpv 侧有 `frame-drop-count` / `decoder-frame-drop-count` 属性可直接读，成本低。

### C. 可以不改

**C1. "mova 不做网络发送/批处理调度"——保持。**
依据：ExoPlayer 的 `AnalyticsListener` 同样只回调不发送，发送策略完全由宿主决定
（[Media3][exo-analytics]）。这条设计与业界一致，**不要**因为要加心跳/聚合就把
HTTP 客户端引进 mova。聚合（rebufferCount 之类）是纯内存计数，不违背这条原则。

**C2. 高频手势事件（音量/亮度/缩放/锁定/fit）继续排除。**
依据：无一家把逐像素手势事件纳入 QoE 体系。唯一例外是**静音/取消静音**语义点
（CMCD `e=m`/`e=um`、IMA `VOLUME_MUTED`），如需可单独加，不必放开整个
`MovaVolumeChange`。

**C3. `MovaReportKind{action,event,error}` 三分保留。**
虽然业界有更细维度（QoS/QoE/业务，或生命周期阶段），但那些维度**与 kind 正交**，
更适合放进 params 或另加字段，而不是把 kind 撑成七八个值。若要补，加一个
`MovaReportDomain{qos, qoe, business}` 的可选字段比改 kind 更干净。

**C4. `MovaPreviewBlock`/`MovaSttBlock`/`MovaSizeChange`/`MovaDurationChange` 继续不做事件。**
Shaka 的做法是把 width/height/duration 放进 stats 快照而非事件流（[Shaka][shaka-stats]），
mova 可在会话级属性里带上，无需独立事件。

---

## 9. 参考链接

**规范类**

- `cta5004b` — CTA-5004-B《Web Application Video Ecosystem — Common Media Client Data》：
  <https://cta-wave.github.io/Resources/common-media-client-data--cta-5004-b.html>
  （正式 PDF：<https://cdn.cta.tech/cta/media/media/resources/standards/pdfs/cta-5004-final.pdf>）
- `cta2066-shop` — CTA-2066《Streaming Quality of Experience Events, Properties and Metrics》：
  <https://shop.cta.tech/products/cta-2066>
- `cta2066-gh` — CTA-2066 公开版仓库：<https://github.com/mlevine84/CTA-2066_Public_Version>
- `w3c-mpq` — W3C Media Playback Quality：<https://w3c.github.io/media-playback-quality/>
- `svta-schema` — SVTA CMCD 自定义键命名规范：
  <https://github.com/streaming-video-technology-alliance/common-media-client-data-custom-keys/blob/main/docs/key-schema.md>
- `svta-repo` — SVTA CMCD 自定义键注册表：
  <https://github.com/streaming-video-technology-alliance/common-media-client-data-custom-keys>

**播放器 / SDK 官方文档**

- `exo-analytics` — Media3/ExoPlayer Analytics 指南（AnalyticsListener vs PlaybackStatsListener）：
  <https://developer.android.com/media/media3/exoplayer/analytics>
- `exo-al` — AnalyticsListener 源码：
  <https://github.com/androidx/media/blob/release/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/analytics/AnalyticsListener.java>
- `exo-cmcd` — ExoPlayer CMCD 实现：<https://developer.android.com/media/media3/exoplayer/cmcd>
- `hlsjs` — hls.js API 文档（Events / ErrorTypes / fatal）：
  <https://github.com/video-dev/hls.js/blob/master/docs/API.md>
- `shaka-stats` — shaka.extern.Stats：
  <https://shaka-project.github.io/shaka-player/docs/api/shaka.extern.html>
- `videojs-player` — video.js Player API：<https://docs.videojs.com/player>
- `videojs-et` — video.js EventTarget（trigger/on 自定义事件）：<https://docs.videojs.com/eventtarget>
- `ima` — google.ima.AdEvent：
  <https://developers.google.com/interactive-media-ads/docs/sdks/html5/client-side/reference/namespace/google.ima.AdEvent>
- `dashjs-cmcd` — dash.js CMCD 使用文档：<https://dashif.org/dash.js/pages/usage/cmcd.html>

**分析厂商 / 云厂商**

- `mux-metrics` — Mux Data 指标定义：<https://www.mux.com/docs/guides/understand-metric-definitions>
- `mux-success` — Mux Playback Success：<https://docs.mux.com/guides/data-playback-success-metric>
- `bitmovin-cd1` — Bitmovin customData 修改方式：
  <https://developer.bitmovin.com/playback/docs/how-can-values-of-customdata-and-other-metadata-fields-be-changed>
- `bitmovin-cd2` — Bitmovin customData 字段数量：
  <https://developer.bitmovin.com/playback/docs/how-many-custom-data-fields-are-included>
- `aliyun-qos` — 阿里云点播 查看视频播放质量 QoS 和 QoE 指标数据：
  <https://help.aliyun.com/zh/vod/user-guide/playback-quality-monitoring>
- `tencent-qos` — 腾讯云点播 播放质量监控：<https://cloud.tencent.com/document/product/266/68146>

[cta5004b]: https://cta-wave.github.io/Resources/common-media-client-data--cta-5004-b.html
[cta2066-shop]: https://shop.cta.tech/products/cta-2066
[cta2066-gh]: https://github.com/mlevine84/CTA-2066_Public_Version
[w3c-mpq]: https://w3c.github.io/media-playback-quality/
[svta-schema]: https://github.com/streaming-video-technology-alliance/common-media-client-data-custom-keys/blob/main/docs/key-schema.md
[svta-repo]: https://github.com/streaming-video-technology-alliance/common-media-client-data-custom-keys
[exo-analytics]: https://developer.android.com/media/media3/exoplayer/analytics
[exo-al]: https://github.com/androidx/media/blob/release/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/analytics/AnalyticsListener.java
[exo-cmcd]: https://developer.android.com/media/media3/exoplayer/cmcd
[hlsjs]: https://github.com/video-dev/hls.js/blob/master/docs/API.md
[shaka-stats]: https://shaka-project.github.io/shaka-player/docs/api/shaka.extern.html
[videojs-player]: https://docs.videojs.com/player
[videojs-et]: https://docs.videojs.com/eventtarget
[ima]: https://developers.google.com/interactive-media-ads/docs/sdks/html5/client-side/reference/namespace/google.ima.AdEvent
[dashjs-cmcd]: https://dashif.org/dash.js/pages/usage/cmcd.html
[mux-metrics]: https://www.mux.com/docs/guides/understand-metric-definitions
[mux-success]: https://docs.mux.com/guides/data-playback-success-metric
[bitmovin-cd1]: https://developer.bitmovin.com/playback/docs/how-can-values-of-customdata-and-other-metadata-fields-be-changed
[bitmovin-cd2]: https://developer.bitmovin.com/playback/docs/how-many-custom-data-fields-are-included
[aliyun-qos]: https://help.aliyun.com/zh/vod/user-guide/playback-quality-monitoring
[tencent-qos]: https://cloud.tencent.com/document/product/266/68146

> **调研局限**：CTA-2066 只有 PDF 公开版，本次未逐字提取其完整指标表，第 4 节引用的是
> 仓库/商店页的范围描述。若要把 mova 的指标计算口径与标准逐条对齐（尤其是 rebuffering
> ratio、video start time 的精确计算边界），需要单独把该 PDF 拉下来精读。
