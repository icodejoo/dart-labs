# 实时源限制 demuxer 后向缓冲

日期：2026-10-24。机器：Windows 11 Pro 10.0.26100，真实桌面。证据原件在 `D:\tmp\w15\ev\`（不入库）。承接 [windows-render-memory-growth](2026-10-24-windows-render-memory-growth.md) 的结论 2。

## 改动（mova）

- `MovaKernel.open` 新增 `{bool live = false}`；`MovaEngine` 四处 `_kernel.open` 按源类型传值（`open` 用 `source.type == live`，时移重开、`_reopenLiveSource` 恒为 live，`switchQuality` 用 `state.type`）。复用 mova 现有的 `MovaStreamType`，没有新增 URL 判定（代码里没有 whep 的专门映射，WHEP 靠宿主把源标成 `live`）。
- `MovaMpvKernel._applyLiveCache(live)`：只在实时/点播**切换**时动属性，点播到点播、实时到实时都不碰。
  - 进入实时：先读并记下 `demuxer-max-back-bytes`、`demuxer-seekable-cache` 的原值，再写 `0` / `no`，之后才 `player.open`。
  - 回到点播：写回记下的原值（读不到时用兜底常量），再 `open`。
  - 失败被吞掉，不影响播放。
- 常量在 `mpv_defaults.dart`：`kDemuxerMaxBackBytes`、`kDemuxerSeekableCache`、`kLiveMaxBackBytes`、`kLiveSeekableCache`，以及读不到原值时的兜底 `kVodMaxBackBytes`、`kVodSeekableCache`。
- 测试：`test/core/kernel/mpv_kernel_live_cache_test.dart`（6 项：点播不动、实时先写后 open、实时重复不重写、实时到点播还原原值、实时到点播到实时再限制、点播到点播不动）、`test/core/engine_live_flag_test.dart`（2 项）；`test/support/fake_kernel.dart` 加 `lastLive`。全量 1031 项绿（基线 1023），`flutter analyze lib test` 无问题。

## 一个差点踩的坑

media_kit 在 Windows 上已把 `demuxer-max-back-bytes` 设成 32 MiB（实测 `33554432`），**不是** mpv 默认的 150 MiB。第一版写死 150 MiB 还原，实测切回点播后值变成 157286400，与切换前不一致，所以改成"限制前读原值、还原时写回"。上面的 6~7 MiB/min 增长在 32 MiB 封顶前才成立，之前笔记里"封顶 150 MiB"的说法应以 32 MiB 为准（`nocap` 对照里 630s 时 `backBytes=33554432`）。

## 数据（release，WHEP，本机 MediaMTX chunked 配置，640x360 25fps，660s，每 15s 采样，t=60s 之后算斜率）

| 编号 | 配置 | 私有 MiB/min | WS MiB/min | 私有起止 MiB |
|---|---|---|---|---|
| cap_bundled | 限制开 + 随包 ANGLE（2022-08，620BB6E3） | 9.56 | 9.48 | 310 → 388（t=546） |
| cap_emu | 限制开 + 较新 ANGLE（模拟器 2025-08，2E34ABC7，仅本地对照） | 0.36 | 0.41 | 300 → 303 |
| nocap_emu | 限制关（点播参数，同源）+ 较新 ANGLE | 7.84 | 7.74 | 309 → 374 |

- 限制开后 `seekable-ranges` 为空、`backBytes=0`、`seekCache=no`；限制关时 `backBytes=33554432`。
- 随包 ANGLE 下剩 9.5 MiB/min，与上一份笔记的 ANGLE 泄漏（9~10 MiB/min）吻合。
- 两者叠加（限制开 + 新 ANGLE）11 分钟私有只涨约 3 MiB，句柄 1733 到 1729 持平，掉帧 0/0。
- 起播正常：640x360、`hwdec=d3d11va-copy`、`vid=1`。

## 回归

- 实时 到 点播 到 实时 到 HLS 点播 到 实时 到 HTTP mp4（各 10s，`switch2`）：实时段 `backBytes=0 seekCache=no`；每个点播段均为 `33554432 / auto`（与限制前原值一致），全部出画，`pos` 正常推进。
- 纯点播（HTTP mp4、本地 HLS 各 15s，`vod`）：属性始终是原值，未被写入，行为不变。
- 5 轮起播/停止（每轮 8s，重建 engine，`stress`）：5/5 出画，pos 6080/6400/6360/6360/6280ms。
- 构建方式：`D:\tmp\w15\app` 最小工程依赖 `mova`（path）+ 本地 slim_pkg 的 WHEP libmpv（sha256 前缀 25d621eb），经 explorer 代启动构建；未改仓库 example，未留 `pubspec_overrides.yaml`，未碰 ANGLE/CMake。

## 风险与未决

- **HLS 直播（`type: live`）也会被限制**：后向缓冲为 0 且关闭缓存内 seek。对不可 seek 的 WHEP/TS 无影响；对可 seek 的直播（HLS DVR），mpv 仍可通过解复用器本身 seek，只是不能在已播缓存里回拉。本次没有在真实 HLS 直播上验证时移回拉，由 `urlBuilder` 重开路径做的时移不受影响（重开本来就是新 open）。若要对可时移的直播放开，可在 `MovaLiveConfig` 上加开关，需要用户决定。
- 宿主若把 WHEP 源标成 `vod`，不会被限制（靠 `MovaSource.type`，没有按 URL 前缀自动判）。
- 没有真机（Android/iOS）回归；属性是 mpv 通用属性，预期一致，未验证。
- 仓库内没有 generated 文件或 `pubspec.lock` 的新增改动（构建都在 `D:\tmp\w15`）；没有 git commit。

## 按格式判断（取代按 `MovaSource.type`）

日期：2026-10-24。动机：上面"风险与未决"第一条的问题成立，HLS 直播同样是 `live`，被一并限制后不能在已播缓存里回拉。真正不需要后向缓冲的只有 WHEP 这类实时流，所以改成按打开后的真实格式判断。证据原件在 `D:\tmp\w17\ev\`（不入库）。

### 判断依据（真实 libmpv，WHEP 版 DLL，Windows，打开后 6s 读取）

| 源 | `file-format` | `current-demuxer` | `demuxer-lavf-format` | `path` |
|---|---|---|---|---|
| WHEP（`whep+http://...`） | `whep` | `lavf` | 空 | 原 URL |
| 本地 HLS（http m3u8） | `hls` | `lavf` | 空 | 原 URL |
| HTTP mp4 | `mov,mp4,m4a,3gp,3g2,mj2` | `lavf` | 空 | 原 URL |

`current-demuxer` 三者都是 `lavf`，`demuxer-lavf-format` 恒空，`path` 只是输入 URL，都不能区分，所以选 `file-format`：WHEP 稳定给出 `whep`，HLS 给出 `hls`，mp4 给出一串容器名。

### 改动（mova）

- 撤销上一版的 `live` 参数：`MovaKernel.open` 恢复为 `open(uri, {play})`，`MovaEngine` 四处调用恢复原样，`engine_live_flag_test.dart` 和 `FakeKernel.lastLive` 一并删除。公开 API 语义（`MovaSource.type` 等）未动，宿主不用做任何标记。
- `MovaMpvKernel`：
  - 每次 `open` 先还原（如果当前处于限制状态），再 `player.open`。这样打开失败、切到别的源都不会残留限制。
  - 订阅 `player.stream.tracks`（首次 open 时才订阅）。文件加载完成后 mpv 刷新 track-list，出现 auto/no 之外的真实轨道时，读一次 `file-format`；等于 `whep` 才记下 `demuxer-max-back-bytes` / `demuxer-seekable-cache` 的原值并写 `0` / `no`。空轨道（切源重置）忽略。
  - `_openSeq` 保证中途换源时旧的判断结果被丢弃；限制落地期间如果已换源，立即还原。
  - 还原值读不到时用兜底常量 `kVodMaxBackBytes` / `kVodSeekableCache`；所有属性读写失败都吞掉，不影响播放。
- `mpv_defaults.dart` 新增 `kFileFormat`、`kRealtimeFileFormat`（`whep`）。
- 测试：`mpv_kernel_live_cache_test.dart` 重写为 11 项（mp4 不碰、HLS 不限制、whep 打开后才限制、重复事件只套一次、whep 到 hls 还原、whep 到 mp4 到 whep 再限制、读不到原值用兜底、限制中 open 失败不残留、whep 打开失败从未限制、加载中途换源不残留、空轨道不触发）；其余四个 kernel 测试的假 `PlayerStream` 补了 `tracks`。全量 1034 项绿，`flutter analyze lib test` 无问题。

### 实测回归（Windows，release，本机 MediaMTX chunked + 本地 ffmpeg 造的 live 风格 HLS，宿主不传任何 live 标记）

`D:\tmp\w17\app` 最小工程依赖 `mova`（path）+ 本地 slim_pkg 的 WHEP libmpv，经 explorer 代启动构建；同一个 engine 依次切源：

| 段 | `demuxer-max-back-bytes` / `seekable-cache` | 备注 |
|---|---|---|
| WHEP | `0` / `no`（t+3s 起） | 640x360 出画，`hwdec=d3d11va-copy` |
| 本地 live HLS（无 ENDLIST，2s 切片） | `33554432` / `auto` | 播到 11.8s 后 seek -4s，落点 9.56s（回退成功） |
| HTTP mp4 | `33554432` / `auto` | 播到 7.76s 后 seek -4s，落点 5.52s |
| 再 WHEP | `0` / `no` | 正常 |
| 再 HLS | `33554432` / `auto` | 正常 |

5 轮起播/停止（重建 engine，各 8s）：5/5 出画，pos 6120/5840/6120/6120/6320ms。

### 局限

- 限制在打开之后才生效，起播头几秒会多缓一点（32 MiB 封顶，WHEP 400kbps 量级下几秒只有几百 KiB），可接受；WHEP 的 `abr`/重开路径每次 open 都会先还原再重限制，中间有同样的短窗口。
- 依赖 track-list 刷新作为"文件已加载"信号；若某个源没有任何真实轨道（纯字幕等），不会触发判断，按未限制处理。
- 判断只认 `file-format == whep`。ffmpeg 里别的不可 seek 实时格式（裸 TS、RTP/RTSP 等）不受限制，需要的话往 `kRealtimeFileFormat` 扩成集合即可。
- 回归里的 `demuxer-cache-state/seekable-ranges` 读出恒为空（该节点属性在这里读不到有意义的值），回拉能力以 seek 实际落点为准。
- 没有真机（Android/iOS）回归；`file-format` 是 mpv 通用属性，预期一致，未验证。
- 仓库内没有 generated 文件或 `pubspec.lock` 的新增改动；没有 git commit；没有留 `pubspec_overrides.yaml`。

## 扩展判断（其他实时流格式）

日期：2026-10-24。证据原件在 `D:\tmp\w18\ev\`（probe*/trans/reg/stress，不入库）。真实 libmpv（WHEP 版 Windows DLL，sha256 前缀 25d621eb）；源：本机 MediaMTX（chunked 配置，路径 `w18`）、ffmpeg 造的 live HLS（无 ENDLIST，两种：列表无限增长 / 滑窗 5 片）、HLS 点播、裸 TS 直播（http 长连接，ffmpeg `-re -stream_loop -1` 经管道推出）、点播 `.ts`、HTTP mp4（支持 Range）、无 Range 的 `.ts`/mp4（`python http.server`）。

### 实测值（打开后取值，`file-format` / `seekable` / `duration`）

| 源 | file-format | seekable | duration | 缓存内回拉（限制关） |
|---|---|---|---|---|
| WHEP | `whep` | no | 随时间增长（2.6s、4.2s、5.7s、7.7s，约 1s/s） | 能 |
| 裸 TS 直播（http） | `mpegts` | no | 随时间增长（0.9、1.2、2.2、3.1、4.7、6.3、8.3s） | 能 |
| 点播 `.ts`（Range） | `mpegts` | yes | 恒 40.0 | 能 |
| HLS 直播（无 ENDLIST，两种） | `hls` | **no** | 恒 ~30（不随播放增长） | **能** |
| HLS 点播 | `hls` | yes | 恒 40.0 | 能 |
| HTTP mp4（Range） | `mov,mp4,m4a,3gp,3g2,mj2` | yes | 恒 40.0 | 能 |
| 无 Range 的点播 `.ts` / mp4 | `mpegts` / mov 串 | **no** | 恒 40.0 | **能** |
| RTSP / SDP / RTP | 打不开（见下） | - | - | - |
| 裸 TS over UDP | 打不开（见下） | - | - | - |

关键发现：**`seekable=no` 不等于"不能回拉"**。mpv 在解复用缓存里仍能回拉（`partially-seekable` 恒为 no），HLS 直播、无 Range 的点播都是 `seekable=no` 却能回拉（实测 seek -3s 全部落在目标附近）。所以"不可 seek 且无时长"这条原假设不成立：实时流的 `duration` **不是空**，mpegts/WHEP 会按已解析时间估算并持续增长。

### 时序（打开后到 track-list 出现真实轨道，再往后）

- track-list 真实轨道出现：mp4/点播 ts/HLS 30~120ms；WHEP 1.5~2.2s（要等 DTLS+首包）；裸 TS 直播约 0.4s。
- 点播（mp4/点播 ts/HLS 点播）从轨道出现的第 0ms 起 `seekable=yes`、`duration=40`，没观察到先 no 后 yes 的瞬态。
- 但**无 Range 点播与直播在最初约 100ms 内 duration 是半截值**：无 Range ts 0ms 时 0.23s，100ms 后跳到 40；HLS 直播 0.62s 跳到 30.0；裸 TS 直播 0.28s 到 0.90s。所以不能在轨道事件当刻读，必须等一段时间。
- 轨道事件后 3s、6s、8s 的取值与上表一致，稳定。

### 判断规则（mova 实现）

1. `file-format` 命中 `kRealtimeFileFormats`（目前只有 `whep`）：直接限制，不等探测。
2. 否则（且格式不在 `kPlaylistFileFormats`，即 `hls`）进兜底：track-list 出现真实轨道后，间隔 `kLiveProbeInterval`（1.5s）采样两次 `seekable`/`duration`，**同时满足才限制**：两次 `seekable` 都是 `no`；并且（两次 `duration` 都读不到，或第二次比第一次至少多 间隔x0.5 秒）。任何一次读到 `seekable=yes`、时长恒定、一有一无、中途换源或销毁，都放弃。
3. 因此裸 TS 直播约在轨道出现后 3s 被限制（回归里 t+4s 已是 `0/no`）；点播 mp4、点播 `.ts`、HLS 点播、HLS 直播、无 Range 点播（时长恒定）都不受影响，回归里 seek -3s 全部成功。
4. `MovaMpvKernel` 新增可选构造参数 `realtimeFormats`（默认 `kRealtimeFileFormats`）与 `liveProbeInterval`（默认 1.5s，测试里压短）。
5. 为什么不把 `mpegts` 放进集合：点播 `.ts` 也是 `mpegts`；为什么 `hls` 不进兜底：HLS 直播 `seekable=no` 且滑窗时时长可能变化，宁可漏限制也不能破坏它的回拉。

### 局限

- 兜底靠"时长随时间增长"这个启发式：暂停状态下的直播（时长不增长）不会被限制；"无 Range 且时长未知的 ts 点播"在解析期间时长也会增长，可能被误限制（回拉退化为不可回拉，不影响播放，本次没有这类源）。
- 生效更晚：裸 TS 约轨道后 3s，起播头几秒多缓一点（32 MiB 封顶）。
- 裸 TS over UDP 本机没打通（见下），属性值只能按 http 直播推断，未验证。
- 没有真机（Android/iOS）回归。

### rtsp / sdp / rtp / udp 的发现（只记录，未改白名单或构建）

- 白名单不是主因：临时在验证入口放行 `rtsp`、`sdp` 后，`rtsp://127.0.0.1:18554/w18`（MediaMTX，ffprobe 确认可读）仍报 `No protocol handler found to open URL rtsp://`、`Failed to recognize file format`；SDP 文件（`http://.../live.sdp`）被当成纯文本播放列表（`Reading plaintext playlist`）。
- 根因在瘦身版 ffmpeg：`tools/whep-flavor/build-windows.sh` 的 demuxer 列表只有 `mov,matroska,webm_dash_manifest,mpegts,hls,flv,live_flv,data,mp3,flac,ogg,wav,aac,ac3,eac3,ass,srt,webvtt(+whep)`，**没有 `rtsp`/`sdp`/`rtp` demuxer**（protocol 里有 `udp,rtp`，但没有 demuxer 也打不开）。所以 RTSP/SDP/RTP 在当前 libmpv 里根本播不了，改 mova 白名单没有意义；要支持得改 ffmpeg 构建加 demuxer（还会涨体积），需用户决定。没有实测值，所以没往 `kRealtimeFileFormats` 里加。
- `udp://127.0.0.1:28091`（ffmpeg 推 mpegts，试过 `pkt_size=1316`、`fifo_size`/`overrun_nonfatal`）同样打不开（`Reading plaintext playlist`，`Failed to recognize file format`），原因没查清，待查；属于另一个问题，不影响 http 直播。

### 回归（Windows，release，WHEP 版 DLL，`D:\tmp\w18\app` 最小工程，同一个 engine 依次切源，640x360 出画，`hwdec=d3d11va-copy`）

| 段 | `demuxer-max-back-bytes` / `seekable-cache` | 回拉 |
|---|---|---|
| WHEP | `0` / `no` | 不适用 |
| 裸 TS 直播 | `0` / `no`（t+4s 已生效） | 不适用 |
| HLS 直播（增长列表） | `33554432` / `auto` | seek -3s：9824 到约 6404ms，成功 |
| HTTP mp4 | `33554432` / `auto` | 成功（7680 到约 4220） |
| 点播 `.ts` | `33554432` / `auto` | 成功 |
| HLS 点播 | `33554432` / `auto` | 成功 |
| HLS 直播（滑窗） | `33554432` / `auto` | 成功 |
| 无 Range 的 `.ts` | `33554432` / `auto`（`seekable=no`，时长恒 40） | 成功 |
| 再 WHEP / 再 mp4 | `0/no`、`33554432/auto` | mp4 成功 |

5 轮起播/停止（WHEP 与裸 TS 直播交替，各 8s，重建 engine）：5/5 出画，属性均为 `0/no`。构建在 `D:\tmp\w18`（explorer 代启动），未改仓库 example，没有 `pubspec_overrides.yaml`，没有提交产物。

### 测试

`mpv_kernel_live_cache_test.dart` 在原 11 项上加 14 项（注入 rtsp 进集合限制、默认集合不含 rtsp、直播 TS 增长/无时长限制、点播 ts 不限、seekable=no 时长恒定不限、时长一有一无不限、hls 不进兜底、mp4 瞬态 no 到 yes 不限、首次 yes 即放弃、探测中换源、限制后换源还原、限制后 open 失败不残留、探测中 dispose）。全量 1048 项绿（基线 1034），`flutter analyze lib test` 无问题。
