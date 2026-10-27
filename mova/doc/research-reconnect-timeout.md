# 调研：libmpv 底层断线重连 与 timeout 最佳实践

日期：2026-10-27　范围：mova 0.3.2（`MovaOpts.recovery`）+ mova-libmpv（ffmpeg n9.0.2 + whep 补丁 + mpv v0.41.0）

> 来源约定：`[S:路径]` 为本仓库或上游源码位置，`[U:URL]` 为文档地址。标"建议"的数值是本文的经验判断，不是出处里的默认值。查不到的写"未验证"，集中列在文末。

## 一、结论摘要

1. **mpv 已经默认给 stream-lavf 开了 ffmpeg HTTP 重连**：`reconnect=1`、`reconnect_delay_max=7`（`stream_lavf.c` L404-405）。退避序列 0/1/3/7s，合计约 11s 就放弃。但它对直播基本不生效（见 1.2），所以"直播断了靠底层自愈"这条路走不通，直播重连只能靠 Dart 层 `MovaLiveReconnect`。
2. **直播（非 seekable HTTP/HLS）想让底层重连，必须同时开 `reconnect_streamed=1` 和 `reconnect_at_eof=1`**（`http.c` L1754-1758）。点播（有 Content-Length）默认就会按 Range 续传，不用额外选项。
3. **rtmp/rtsp/srt/whep 在 ffmpeg 层都没有"重连"选项**，只有超时。断了就是 `END_FILE(error)`，必须由 Dart 层重开。WHEP 是 UDP，更与 http 的 `reconnect_*` 无关。
4. **两层重试会叠加**：ffmpeg 在 demuxer 线程里阻塞重连最长约 11s（默认）或 `reconnect_delay_max` 决定，这段时间 mpv 表现为 buffering；mova 的 `stallTimeout`（默认 10s）会先触发，把底层还没重连完的连接整个丢掉重开。建议明确分工：**点播让底层管"短抖动"（<=7s），Dart 管"硬失败"；直播底层不开 reconnect_streamed，全交给 Dart**。
5. **WHEP 补丁没有 ICE restart / 重协商**，也没必要为"推流端掉线"加：推流掉线后服务端会话多半已销毁，新 POST 重建（即现在的 Dart 重连）比 ICE restart 简单可靠。ICE restart 只对"本端网络切换（Wi-Fi/4G）"有价值，代价大，建议暂不做。
6. **补丁层有一个值得做的小改动**：`media_timeout` 的存活判据包含服务端发来的 STUN 检查（`0005` 补丁，README 阶段 B 第 6 条），推流端掉线而服务端会话还在时，STUN 继续到达，`media_timeout` 可能永远不触发，只能靠 Dart 的 `stallTimeout` 兜底。建议新增"只看 RTP/RTCP 数据"的 `rtp_timeout`（或让 `media_timeout` 只认媒体包）。**此条由代码阅读推得，未真机复现，见文末。**
7. **超时数值**：mpv `network-timeout` 默认 60s 对移动端偏长（ExoPlayer 连接/读取各 8s）；mova `startTimeout=10s` 对点播/HLS 合理，对 WHEP 偏紧（握手 10s + 等关键帧 10s 都在补丁默认值里，Dart 10s 会先于它们到期）。详见第三节表格与第四节建议。

---

## 二、问题 1：底层（libmpv/ffmpeg）能做什么

### 1.1 现状：mova 与 mpv 各层已有的东西

| 层 | 现有能力 | 来源 |
|---|---|---|
| mova Dart | `MovaLiveReconnect`（1s 起、x2、封顶 30s、永不放弃）、`MovaRetryThenFailover`（点播）、`startTimeout` 10s、`stallTimeout` 10s、`END_FILE(error)` 触发 | `lib/src/core/options/recovery_config.dart`、`recovery/fail.dart`、CHANGELOG 0.3.2 |
| mova 源级选项 | `MovaSource.mpvOptions` / `demuxerOptions` / `whepMediaTimeout`，`demuxer-lavf-o` 走 `change-list add/remove`，不冲掉 media_kit 默认的 `protocol_whitelist` 等 | `lib/src/core/kernel/mpv_keyvalue.dart`、CHANGELOG 0.3.2 |
| mpv | 对 stream 层默认 `reconnect=1`、`reconnect_delay_max=7`；`network-timeout`（默认 60s）折成 `timeout` 微秒注入 | `stream/stream_lavf.c` L404-405、L230-236（v0.41.0） |
| ffmpeg WHEP 补丁 | `timeout`(信令 HTTP，10s，但 mpv 会注入 60s)、`handshake_timeout` 10s、`first_frame_timeout` 10s、`media_timeout` 5s | `mova-libmpv/patches/ffmpeg-whep/README.md` 选项表 |

注意：`MovaSource.mpvOptions` 目前只能设 **mpv 选项**（如 `stream-lavf-o`、`network-timeout`），可以直接用来下发下面推荐的 ffmpeg 选项，不需要改 mova 代码。

### 1.2 ffmpeg 协议选项对各协议是否生效

HTTP 重连选项定义，默认值取自 `libavformat/http.c`（n7.1，n9.0.2 未逐字对照，见未验证）[S:https://raw.githubusercontent.com/FFmpeg/FFmpeg/n7.1/libavformat/http.c L178-185]：

| 选项 | 默认 | 语义 |
|---|---|---|
| `reconnect` | 0 | 读取中途断开（EOF 前）后重连 |
| `reconnect_at_eof` | 0 | 把 EOF 也当作错误去重连（直播用） |
| `reconnect_streamed` | 0 | 允许对**不可 seek 的流**重连 |
| `reconnect_on_network_error` | 0 | 连接阶段 TCP/TLS 错误时重连 |
| `reconnect_on_http_error` | 空 | 逗号分隔状态码，如 `503,4xx,5xx` |
| `reconnect_delay_max` | 120s | 单次等待上限，超过即放弃 |
| `reconnect_max_retries` | -1(不限) | 最大重试次数 |
| `reconnect_delay_total_max` | 256s | 累计等待上限 |

文档：[U:https://ffmpeg.org/ffmpeg-protocols.html]

**重连判定与退避**（`http.c` L1735-1770，读路径）：

- `is_streamed`（无长度、不可 seek）且没开 `reconnect_streamed` -> 直接放弃，不重连。
- 否则需满足：`reconnect && filesize>0 && off<filesize`（点播中途断），或 `reconnect_at_eof && 读到 EOF`。
- 退避 `delay = 1 + 2*delay`，从 0 起：0、1、3、7、15……，当 `delay > reconnect_delay_max` 时放弃。mpv 设的 7 -> 只试 0/1/3/7 四次，累计等待约 11s（推算自源码，未实测）。

**按协议逐项**：

| 协议 | `reconnect*` | `rw_timeout`/`timeout` | 备注 |
|---|---|---|---|
| http/https（点播 MP4 等） | 生效；mpv 默认已开 | `timeout` 由 mpv `network-timeout` 注入（60s） | 有 Content-Length 才会按 Range 续传 |
| http/https（直播裸流，如 TS/FLV over HTTP） | 默认**不生效**（streamed）；需 `reconnect_streamed=1` + `reconnect_at_eof=1` | 同上 | 重连后是从当前位置重新拉流，不是续传，会有内容空洞，可接受 |
| HLS | 选项在 ffmpeg 的 hls demuxer 里转交给底层 http 取分片/播放列表；hls 自己的容错是 `seg_max_retry`(0)、`max_reload`(3)、`m3u8_hold_counters`(1000)、`live_start_index`(-3) [S:FFmpeg n7.1 libavformat/hls.c L2571-2592] | 同 http | `reconnect*` 是否被 hls 继承：`hls.c` 通过 `ffio_copy_url_options` 复制父 avio 的选项（L1943）[S:同文件]，按此推断会继承，**未实测** |
| rtmp | **无**（TCP 流，ffmpeg 无重连选项） | mpv 对 rtmp 强制 `timeout=0`，因为设了 timeout 会进入 listen 模式（`stream_lavf.c` L417-420） | 超时要靠 `rw_timeout`（通用选项）；断了就 END_FILE |
| rtsp | **无** | rtsp 的 `timeout` 是 socket I/O 超时(微秒)，mpv 对 rtsp **不设** `timeout`（L232，文档也警告 `network-timeout` 会破坏 RTSP）；ffmpeg 文档页未见 `stimeout` | 瘦身版 libmpv 无 rtsp/sdp demuxer（`mpv_defaults.dart` 注释），本项目基本不涉及 |
| srt | **无** | `timeout`(微秒，读/写/连接的错误超时)、`connect_timeout`(毫秒，文档称默认 3s)、`latency`(微秒)、`rcvbuf` | SRT 自身有重传与丢包恢复；是否编入瘦身版**未验证** |
| tcp（底层） | 无 | `timeout`(微秒，只读模式)、`listen_timeout`(毫秒) | 文档未列 connect_timeout |
| whep | **无**，且不走 http 层读路径 | `timeout`(仅信令 HTTP)、`handshake_timeout`、`first_frame_timeout`、`media_timeout` | 见 1.4 |

通用：`rw_timeout`（微秒）对所有协议的读写有效，ffmpeg 文档未给默认值 [U:https://ffmpeg.org/ffmpeg-protocols.html]。

### 1.3 mpv 自身选项

| 选项 | 默认 | 作用 / 与重连的关系 | 来源 |
|---|---|---|---|
| `network-timeout` | 60s；0=用 FFmpeg 默认 | 影响至少 HTTP；协议不支持则静默忽略；会破坏 RTSP | [U:https://mpv.io/manual/stable/#options-network-timeout] / `DOCS/man/options.rst` v0.41.0 |
| `stream-lavf-o` | 空 | 传 AVOptions 给 stream 层（可放 `reconnect_streamed=1` 等）；key/value 列表 | `stream_lavf.c` L57 |
| `demuxer-lavf-o` | 空 | 传给 demuxer 层（whep 的 `media_timeout` 等放这里）；注意 media_kit 默认已设了 `protocol_whitelist` 等，整串覆盖会冲掉（mova 已用 change-list 规避） | `DOCS/man/options.rst` |
| `cache-pause` | yes | 缓存见底则暂停等待（"buffering"） | `options/options.c` L1033 |
| `cache-pause-wait` | 1s | 重新开播前缓存需攒的秒数 | options.rst；`options.c` L1034 |
| `cache-pause-initial` | no | 开播前先缓冲 | options.rst |
| `demuxer-readahead-secs` | 1s（缓存开启时基本被 `cache-secs` 覆盖） | 预读时长 | options.rst |
| `cache-secs` | 很大，实际受 `demuxer-max-bytes` 限制 | 缓存开启时的预读上限，常用于限制 | options.rst |
| `keep-open` | no | 播到末尾不退出而是暂停。**直播断流后配合 `keep-open=yes` 能避免 mpv 直接结束文件，但 mova 靠 END_FILE 触发恢复，不应开** | options.rst |
| `force-seekable` | no | 强制允许 seek；对直播重连没有帮助，别开 | options.rst |
| `hls-bitrate` | max | 只管选档，与重连无关 | options.rst |
| `demuxer-lavf-probesize` / `-analyzeduration` | 无默认(用 ffmpeg) | 影响起播耗时；WHEP 已由补丁 0013 在 read_header 里等关键帧，不依赖它们 | `demux_lavf.c` L85-89 |

ytdl 不涉及。

### 1.4 WHEP 补丁：现状与能否加 ICE restart

现状（`mova-libmpv/patches/ffmpeg-whep/README.md`）：

- 流程：POST SDP -> 取 answer -> 单 UDP socket `connect` 到 answer **首个**候选 -> ICE（我方 controlling）-> DTLS（我方 server）-> SRTP。
- 存活：每 2.5s 发 consent STUN 检查；**任何经认证的对端数据（RTP/RTCP/STUN 请求或响应）都刷新存活时间**，`media_timeout`（默认 5s）内没有则返回 `ETIMEDOUT`（0005）。
- 起播：`read_header` 内等首个带 SPS/PPS 的 IDR，受 `first_frame_timeout`（默认 10s）约束，超时 `ETIMEDOUT`（0013）；等待期间不按 `media_timeout` 判死。
- 已知限制：握手后的 DTLS alert 被忽略，对端异常消失靠 `media_timeout`；**对端换 SSRC（发布端重连）后新包被当成"非首个 SSRC"丢弃，需要重新连接**（README 阶段 B 已知限制）；没有 RTX/TWCC。
- 没有 ICE restart，也没有 `PATCH` 方式的重协商；socket 一旦 connect 到固定候选，**本端网络切换后无法自愈**。
- 作为对照：RFC 7675 规定浏览器 consent 5s 一检（随机 0.8-1.2 倍）、30s 无响应即失效，失效后须新会话或 ICE restart 才能重新发包 [U:https://www.rfc-editor.org/rfc/rfc7675.html]。我们的 `media_timeout` 5s 比浏览器的 30s 严格得多，这是刻意偏向快速重连，合理。

**ICE restart 要不要加**（判断，非出处）：

| 场景 | 现行做法 | ICE restart 价值 |
|---|---|---|
| 推流端掉线再恢复 | `media_timeout`/END_FILE -> Dart 重新 POST | 低。服务端会话大概率已被回收，或 SSRC 已变，restart 也要重建 |
| 服务端重启 | 同上 | 无，会话丢了 |
| 本端 Wi-Fi/4G 切换 | 等 `media_timeout` 后 Dart 重连，空窗约 5s + 重连耗时 | 有，但需实现 PATCH + 新 ufrag/pwd + 重新选候选，且依赖服务端支持（WHEP 草案的 ICE restart 是否被 MediaMTX/SRS 实现**未验证**） |

结论：**不建议补 ICE restart**；真要优化切网，更便宜的办法是 Dart 层监听网络变化后主动重开（不等 5s），属于 Dart 层改动。

### 1.5 底层与 Dart 层如何分工，会不会重复重试

三类"失败路径"：

1. **ffmpeg 内部重连**（仅 http 系）：在 demuxer 线程里阻塞，mpv 侧看是 buffering，不发 END_FILE。
2. **ffmpeg 放弃**：读返回错误 -> mpv 结束文件 -> `END_FILE(error)` -> mova `recovery` 立即处理（0.3.2 起 `recovery.enabled` 自动订阅 END_FILE）。
3. **静默卡住**：数据不来但连接没断（如服务端会话在、推流端没了）-> 只有 mova `stallTimeout` 能发现。

冲突点：

- **Dart `stallTimeout`(10s) vs ffmpeg 重连(约 11s)**：Dart 先到期，会重开并丢掉 ffmpeg 正在退避的连接。结果不是"重复"而是"互相打断"，且会重复请求源站。直播本来就不让 ffmpeg 重连，不会撞；点播建议 `stallTimeout >= 15s` 或保持 `reconnect_delay_max=7` 不变并接受打断，二选一要有意为之。
- **点播断点续传的价值**：ffmpeg 的 Range 续传保持播放位置，Dart `MovaRetryThenFailover` 重开则要靠"首帧后补发续播 seek"（0.3.1 修过）。短抖动让 ffmpeg 处理体验更好，Dart 只处理它放弃之后的事。
- **WHEP**：ffmpeg 层无重连，不存在叠加；`media_timeout`(5s) 先于 `stallTimeout`(10s) 到期，报 END_FILE，由 Dart 重连。如果服务端 STUN 保活让 `media_timeout` 不触发（见摘要 5），`stallTimeout` 兜底，此时恢复要多等 10s。

### 1.6 推荐的底层选项组合（通过 `MovaSource.mpvOptions` / `demuxerOptions` 下发）

**点播（HTTP/HTTPS 文件、HLS VOD）**

```
network-timeout=15                       # 建议：默认 60 对移动端太长
stream-lavf-o=reconnect=1,reconnect_on_network_error=1,reconnect_delay_max=7   # reconnect/delay_max 即 mpv 默认；补上 network_error
# 不用 reconnect_on_http_error=5xx：5xx 交给 Dart 切备选地址更合适（建议）
```
- Dart：`MovaRetryThenFailover` 保持默认；`stallTimeout` 建议 15s（> ffmpeg 约 11s 重连窗口）。

**HTTP/HLS 直播**

```
network-timeout=10                       # 建议
# 不开 reconnect_streamed / reconnect_at_eof：让底层快速失败，交给 MovaLiveReconnect（带多地址切换）
```
- 原因：底层直播重连会在 demuxer 线程里悄悄卡住，且不能切换备选地址；Dart 的 `MovaLiveReconnect` 有退避、可切换、有事件可观测。
- 若确实想让底层抗 1-3 次短抖动：`stream-lavf-o=reconnect_streamed=1,reconnect_at_eof=1,reconnect_delay_max=3`（总等待约 4s），同时 `stallTimeout` 要 > 5s。**HLS 下这些选项是否传到分片请求未实测，不要依赖**。
- HLS 可选：`demuxer-lavf-o=seg_max_retry=2`（默认 0，即分片失败不重试直接跳过/报错；建议值，需实测对 live 追帧的影响）。

**WHEP 直播**

```
demuxer-lavf-o += handshake_timeout=5000000,first_frame_timeout=8000000,media_timeout=5000000   # 微秒；建议
```
- `MovaSource.whepMediaTimeout` 已封装 `media_timeout`；`handshake_timeout`/`first_frame_timeout` 目前须走 `demuxerOptions`。
- 不设任何 http `reconnect*`（无效）。底层无重连，全部由 Dart 层负责。
- mpv 会往 stream 层注入 `timeout=60000000`（README 选项表第 `timeout` 行注明），所以信令 HTTP 超时实际是 60s，而不是补丁默认的 10s。若要让信令 5-10s 内失败，需通过 `demuxer-lavf-o=timeout=8000000` 覆盖（**该覆盖是否优先于 mpv 注入的值未验证**）。

### 1.7 需要改 libmpv/ffmpeg 补丁才能做的项

| 优先级 | 项 | 适用 | 说明 |
|---|---|---|---|
| 中 | `rtp_timeout`（只认 RTP/RTCP 的无数据超时） | WHEP 直播 | 修摘要 5 的"STUN 保活掩盖推流端掉线"；先真机验证再做 |
| 中 | `ETIMEDOUT` 之外区分错误码/日志（握手超时 / 无关键帧 / 媒体超时） | WHEP | 让 Dart 层按原因调退避（例如握手失败退避大、媒体超时立即重连）。mpv 的 END_FILE 只带 error 字符串，需确认能读到（未验证） |
| 低 | ICE restart / 网络切换后重选路径 | WHEP | 见 1.4，不建议 |
| 低 | 对端换 SSRC 时自动接受新 SSRC（而不是丢弃） | WHEP | 推流端重连但服务端会话不重建的场景；MediaMTX 下通常会话也会重建，价值待验证 |
| 低 | RTX 支持 | WHEP | 与重连无关，属弱网质量 |
| 不需要 | http 层 reconnect 增强 | 点播/直播 | 选项已够用，不必改 ffmpeg |

---

## 三、问题 2：超时时长的业界默认值

### 2.1 各家默认值（有出处的）

| 项 | 来源 | 默认值 |
|---|---|---|
| mpv 网络超时 `network-timeout` | mpv options.rst / `stream_lavf.c` L74 | 60s（0=ffmpeg 默认） |
| mpv 缓冲暂停 `cache-pause-wait` | `options.c` L1034 | 1s（重缓冲后攒 1s 才续播） |
| mpv 预读 `demuxer-readahead-secs` | options.rst | 1s |
| mpv 重连 | `stream_lavf.c` L404-405 | `reconnect=1`，`reconnect_delay_max=7` |
| ffmpeg http 重连上限 | `http.c` L183-185 | delay_max 120s，max_retries 不限，total_max 256s（mpv 覆盖了 delay_max） |
| ffmpeg SRT 连接超时 | ffmpeg-protocols 文档 | 3s（`connect_timeout`，毫秒） |
| ffmpeg RTMP 客户端缓冲 | 同上 | `rtmp_buffer` 3000ms |
| ExoPlayer/Media3 HTTP 连接超时 | `DefaultHttpDataSource.java` L242 [U:https://github.com/androidx/media/blob/release/libraries/datasource/src/main/java/androidx/media3/datasource/DefaultHttpDataSource.java] | 8s |
| Media3 HTTP 读超时 | 同上 L245 | 8s |
| Media3 加载失败重试次数 | `DefaultLoadErrorHandlingPolicy.java` L37/L43 | 3 次；渐进式直播 6 次 |
| Media3 重试退避 | 同上 L125-131 | `min((errorCount-1)*1000, 5000)` ms，即 0/1s/2s/3s/4s/5s 封顶 |
| Media3 开播缓冲 | `DefaultLoadControl.java` L90/L102 | `bufferForPlaybackMs` 1000ms；卡顿后 `...AfterRebufferMs` 2000ms |
| Media3 缓冲上下限 | 同上 L64/L76 | min/max 均 50s |
| hls.js 播放列表加载 | `src/config.ts`（v1.5.20）`playlistLoadPolicy.default` [U:https://github.com/video-dev/hls.js/blob/v1.5.20/src/config.ts] | 首字节 10s、加载完成 20s；超时重试 2 次(0 延迟)，错误重试 2 次、1s 起、封顶 8s |
| hls.js 分片加载 | `fragLoadPolicy.default` | 首字节 10s、加载完成 120s；超时重试 4 次，错误重试 6 次、1s 起、封顶 8s |
| hls.js 清单加载 | `manifestLoadPolicy.default` | 首字节不限、完成 20s；超时重试 2 次，错误重试 1 次 |
| hls.js 直播同步 | `liveSyncDurationCount` | 3 个分片（落后直播边缘） |
| hls.js 卡顿微调 | `nudgeOffset`/`nudgeMaxRetry`/`maxBufferHole`/`highBufferWatchdogPeriod` | 0.1s / 3 次 / 0.1s / 2s |
| WebRTC consent（RFC 7675） | RFC 7675 | 检查间隔 5s（随机 0.8-1.2x，不得 <4s）；30s 无响应失效 |
| mova-whep 补丁 | README 选项表 | `handshake_timeout` 10s、`first_frame_timeout` 10s、`media_timeout` 5s、信令 `timeout` 10s（mpv 注入后 60s）、consent 周期 2.5s |

注：hls.js 的数值是读 config.ts 对应段落得到的（manifest/playlist/frag 三段的先后顺序与上表对应）；若升级后版本不同请重核。

### 2.2 mova 当前默认值 vs 业界

| mova 项 | 当前 | 判断 |
|---|---|---|
| `startTimeout` | 10s | 点播/HLS 合理（hls.js 首字节 10s、Media3 连接 8s）；**WHEP 偏紧**，因补丁默认握手 10s + 等关键帧 10s 都排在它后面，Dart 先到期则丢失 ffmpeg 给出的具体错误 |
| `stallTimeout` | 10s | 点播偏紧：与 ffmpeg 约 11s 重连窗口冲突；直播可更短 |
| `MovaLiveReconnect` | 1s 起、x2、封顶 30s、永不放弃 | 起点与 Media3(0/1s)、hls.js(1s) 一致，合理；封顶 30s 对推流端掉线再恢复略长，建议 10-15s（推流恢复后最多再等一个封顶间隔） |
| `MovaLiveConfig.durationStep` | 2s | 与超时无关 |
| mpv `network-timeout` | 60s（未改） | 偏长，建议 10-15s |
| WHEP `media_timeout` | 5s | 低延迟场景合理；弱网移动端偏短（见下） |

### 2.3 分场景建议值（**建议**，非出处默认；均需真机复测）

| 场景 | network-timeout | startTimeout | stallTimeout | 其他 |
|---|---|---|---|---|
| 点播（HTTP/HLS VOD，常规网络） | 15s | 10-12s | 15s | `reconnect_delay_max=7`(mpv 默认)；`cache-pause-wait` 默认 1s 即可 |
| HLS 直播 | 10s | 12-15s（首个播放列表+首片） | 8-10s（约 3 个分片时长以内） | 分片时长 2-6s，卡顿阈值应 >= 2 个分片时长，否则正常抖动也触发重开 |
| 低延迟 WHEP（局域网/稳定网络） | 信令 5-8s（覆盖 `timeout`） | 12-15s | 5s | `handshake_timeout=5s`、`first_frame_timeout=8s`（要 >= 推流 GOP；GOP 5s 时用 10s）、`media_timeout=3-5s` |
| 弱网移动端（含 WHEP） | 15s | 15-20s | 12-15s | `media_timeout=8-10s`（避免短暂弱网被误判）、`handshake_timeout=8-10s`、直播重连封顶 10-15s |
| 无数据判死（直播） | - | - | 以 `stallTimeout` 为准；WHEP 另以 `media_timeout`/(将来的) `rtp_timeout` 为准 | 参考 RFC 7675 的 30s 是上限，不是目标 |
| 缓冲卡顿判定 | - | - | mpv `paused-for-cache` 才是真卡顿（mova 已观察）；Dart 看 buffering 持续时长，不要看单次出现 | Media3 重缓冲后攒 2s 才续播，mpv 默认 1s；弱网可把 `cache-pause-wait` 调到 2s 减少抖动 |

---

## 四、对 mova 的具体改动建议（按优先级）

**P1（Dart 层，小改动、收益确定）**

1. `MovaRecoveryConfig` 允许按源类型取不同超时：至少给 WHEP 源的 `startTimeout` 默认放宽到 >= 15s（或文档明确"WHEP 请自行调大"）。现在 10s 会先于补丁的握手/等关键帧到期。
2. 点播的 `stallTimeout` 默认由 10s 提到 15s，或在文档里写明与 ffmpeg 重连窗口（约 11s）的关系。
3. `MovaLiveReconnect.maxDelay` 默认 30s 改为 15s（或在文档里给"推流端频繁重启"场景的建议值）。
4. README/文档补一节"分工"：直播不开 `reconnect_streamed`，点播保留 mpv 默认重连，对应 1.5。

**P2（选项层，不改库代码，靠 `mpvOptions`/`demuxerOptions` 下发）**

5. 在默认或示例配置里给出 `network-timeout` 10-15s 的建议（mpv 默认 60s）；点播补 `reconnect_on_network_error=1`。
6. WHEP 示例配置：`demuxerOptions` 里设 `handshake_timeout`、`first_frame_timeout`，并核实能否覆盖 mpv 注入的 `timeout=60s`（见未验证）。
7. 弱网移动端 profile：`media_timeout=8-10s`、`cache-pause-wait=2`。

**P3（libmpv/ffmpeg 补丁层）**

8. `rtp_timeout`：只用 RTP/RTCP 刷新的无数据超时，补掉"STUN 保活掩盖推流端掉线"。先在真机复现（MediaMTX/SRS 推流端断开后，客户端多久报错）再决定是否做。
9. 超时类错误区分原因（握手/无关键帧/无媒体），便于 Dart 层差异化退避；前提是先确认 mpv 的 END_FILE 能带出 ffmpeg 错误码。
10. 不建议做：ICE restart、http 层重连增强。

**另一个 Dart 层候选（P2）**：监听系统网络变化（connectivity）后，对直播/WHEP 主动触发一次重连，而不是等 `media_timeout` 5s。比 ICE restart 便宜得多，能覆盖"切网"场景大部分体验。

---

## 五、未验证项

1. **n9.0.2 的 `http.c`**：上面选项默认值读的是 n7.1 的 `http.c`；n9.0.2 理论上同名同值，但没有逐字对照。
2. **HLS 是否把 `stream-lavf-o` 的 `reconnect*` 传给分片请求**：按 `ffio_copy_url_options` 推断会继承，未实测；`seg_max_retry` 对直播追帧的影响未测。
3. **ffmpeg `rw_timeout`/`timeout` 默认值**：官方文档页没给默认值；`network-timeout=0`（"用 FFmpeg 默认"）具体是不是不限时，未验证。
4. **mpv 注入的 `timeout=60s` 能否被 `demuxer-lavf-o=timeout=...` 覆盖**：两个选项分属 stream 层与 demuxer 层，WHEP 信令 HTTP 取哪个未验证。
5. **STUN 保活是否真的掩盖推流端掉线**：由 README 阶段 B 第 6 条与 0005 补丁代码推得（`last_alive` 被任何认证数据刷新），没有用 MediaMTX/SRS 实测；也不知道 MediaMTX 在无推流时是否继续回 STUN。
6. **mpv 的 END_FILE 能否带出 ffmpeg 具体错误码/原因**：未验证。
7. **SRT/RTMP 是否编入当前瘦身版 libmpv**：未核对 flavors 配方；rtsp/sdp 按 `mpv_defaults.dart` 注释是没有的。
8. **VLC 默认值**（network-caching 等）：未查到可靠的官方文档页，本文不引用；WHEP 草案里的 ICE restart 及 MediaMTX/SRS 的支持情况：未验证。
9. **"分场景建议值"整张表**：属经验判断，只有与出处默认值对照的部分是有来源的，需真机（弱网、推流端断连）复测后再定默认值。
10. **hls.js 数值**取自 v1.5.20 的 `config.ts`；`API.md` 页面抓取失败，未用。
