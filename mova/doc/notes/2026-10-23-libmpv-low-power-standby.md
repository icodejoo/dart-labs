# libmpv "低功耗待机"可行性调研（替代"暂停 + 回来重连"）

> 2026-10-23 · 调研笔记 · 对应计划 [host-ergonomics D9/Task 12-13](../plans/2026-10-23-host-ergonomics.md)（自动暂停守卫）
>
> **结论先行：** libmpv 没有"待机"这个一等公民模式，但**能拼出来**。可行且最划算的是
> **"保持播放 + 只关视频这一侧"**，分两种，按流里有没有音频选：
> - 流**有音频**：`vid=no` + `mute=yes`（组合 B）。视频解码器与渲染整条链被拆掉，音频链继续当"时钟"，
>   demuxer 继续追直播边缘；回来 `vid=auto`。
> - 流**无音频**（纯视频直播）：B 不成立（见 §2.3），只能走"不上屏但继续解码"（组合 C，`vo=null` /
>   桌面端把纹理缩到最小）。
>
> 但有三个必须摆在台面上的代价：**(1) 网络没省**——B/C 都照常以满码率下载，只省 CPU/GPU/电；
> **(2) 回来不是 0 延迟**——B 要新建解码器 + 等下一个关键帧（直播不可 seek 时），延迟量级 = 解码器初始化
> + 0~1 个 GOP；C 才是真·近即时（等下一帧）；**(3) App 进后台不适用**——进程网络/调度会被系统限制，待机只
> 适合"App 仍在前台，只是这块播放器不可见"（切 Tab / 滚出屏 / 被路由盖住）。
>
> 证据等级标记：**[文档]** 官方手册/头文件明说；**[源码]** 读源码得出（给路径/行号）；**[推断]** 基于以上的
> 推理，未实测；**[待测]** 必须真机验证。所有 mpv 源码引用取自 GitHub `master`（2026-10-23 抓取，
> 本机没有 `mpv` 命令行，故没做桌面实验）。

---

## 0. 现状基线（D = 暂停 + 回来重连）

- 守卫计划：隐藏 `pause()`，显示 `play()`；直播隐藏 ≥ 3s 走 `backToLiveEdge()`（见 plan D9 约 L220-249）。
- `backToLiveEdge()`（`lib/src/core/engine.dart:1492`）：`seekEnd` 模式在 `liveSeekable && seekableWindow>0` 时
  只做内核 `seek(window)`，否则 `_reopenLiveSource()` = 整条流重开（DNS/TLS/清单/首片/解码器/首帧全走一遍）。
- 暂停期间 mpv 仍会读网络直到 demuxer 缓冲满：media_kit 把 `demuxer-max-bytes` 设成
  `PlayerConfiguration.bufferSize`，默认 32 MiB（`media_kit-1.2.6/lib/src/player/platform_player.dart:530`；
  `native/player/real.dart:2425-2426`）。**[源码]** 2 Mbps 的流约 2 分钟灌满，之后 demuxer 停读，TCP 反压，
  服务端侧行为取决于协议（见 §3）。
- mpv 手册自己也承认：*"For livestreams, data can build up due to pausing the stream ... If the demuxer cache
  is enabled, these can be skipped manually. The experimental `drop-buffers` command can be used to discard any
  buffered data, though it's very disruptive."* **[文档]** [mpv.rst L1246-1249](https://github.com/mpv-player/mpv/blob/master/DOCS/man/mpv.rst)

## 1. mpv/libmpv 层可用手段

### 1.1 `pause=yes`
- 直播暂停后不会"追"：播放位置停在暂停点，直播边缘继续前移，回来落后暂停时长（上限=缓冲量，满后 demuxer
  停读）。**[文档]**（mpv.rst 同上）
- `core-idle` 也会因缓存不足自动置位，别拿它判断"用户暂停"（[input.rst `core-idle`](https://github.com/mpv-player/mpv/blob/master/DOCS/man/input.rst)）。**[文档]**
- `drop-buffers`：*"Drop audio/video/demuxer buffers, and restart from fresh. Might help with unseekable streams
  that are going out of sync. This command might be changed or removed in the future."* **[文档]**
  [input.rst L1685-1688](https://github.com/mpv-player/mpv/blob/master/DOCS/man/input.rst)。可作为"暂停后回来
  不重开、直接清缓冲追边缘"的候选（组合 F），但**实验性、可能被删**，且若服务端已断连仍要重连。**[待测]**

### 1.2 关视频轨 `vid=no` → 切回 `vid=auto`（本调研的核心）
`vid` 是普通运行期选项（`options.c:640`，`OPT_TRACKCHOICE`）；`set vid no` 走 `mp_switch_track_n`：
**[源码]** [player/loadfile.c L798-889](https://github.com/mpv-player/mpv/blob/master/player/loadfile.c)

1. `uninit_video_chain()`：销毁视频解码器 + 滤镜链（`player/video.c:163`，`vo_chain_uninit` 里
   `talloc_free(track->dec->f)`），发 `VIDEO_RECONFIG`。**视频解码器真的被销毁**，不是"暂停解码"。
2. `handle_force_window(mpctx, true)`：无轨时按 `force-window` 维持窗口；**VO 对象本身不销毁**
   （`uninit_video_out` 才会 `vo_destroy`，这里没调）。
3. `reselect_demux_stream(..., selected=false)` → `demuxer_select_track(.., false)`：demuxer 把该流标记为
   deselected。之后 `demux.c:2185` `bool drop = !ds->selected || ...`——**该流的包到了 demuxer 就被丢掉**，
   不进队列，但**数据照常从网络读进来**（容器是复用的，不能只下音频；mpv 只在 youtube-dl 场景才会改选
   audio-only 格式，见 [options.rst L116-125 `--vid`](https://github.com/mpv-player/mpv/blob/master/DOCS/man/options.rst)）。**[源码]+[文档]**

切回 `vid=auto`（同一个函数，`track != NULL` 分支）：
1. `reselect_demux_stream(.., selected=true)` → `select_track` → `refresh_track`
   （`demux.c:4259-4290`）→ `initiate_refresh_seek`（`demux.c:4171`）。**关键分支** `if (start_ts == MP_NOPTS_VALUE || !seekable) return;`：
   - **demuxer 不可 seek（典型 HTTP-FLV 直播）**：不做 refresh seek，视频流从"现在到达的包"开始；解码器
     新建，**必须等下一个关键帧**才能出第一帧 → 延迟 ≈ 解码器初始化 + (0 ~ 1 个 GOP，均值约半个 GOP)。**[源码]+[推断]**
   - **demuxer 可 seek（点播、带窗口的 HLS）**：会发一次 "refresh seek"，回退到已选流的 `base_ts − 1s` 再把
     缺失的视频包补读回来（注释："seeks back, and then grabs all packets that were missing"）。有缓存时多半
     命中 demuxer 缓存、不重新请求网络；缓存之外则会真发请求。**[源码]**；具体 HLS 直播是否算 seekable、
     会不会回读分片 **[待测]**。
   - `refresh_track` 里有 `avoid_refresh`：只要**已有别的视频流被选中**就避免 refresh seek；我们 vid=no 时没有
     视频被选中，所以**不会**被避免。**[源码]**
2. `reinit_video_chain()`：新建 vo_chain、新解码器（硬解会重新创建 MediaCodec/VT 实例）。
3. 整个过程**不会 reopen 流、不会重新请求**（没有 `loadfile`/`stream_open`）。**[源码]**

> 结论：`vid` 切换 = "拆/建解码器 + 重选 demux 轨"，**不重新打开流**，但**要等关键帧**（不可 seek 直播）
> 或多一次缓存内 refresh seek（可 seek）。

### 1.3 `aid=no` / `mute=yes` / `volume=0` / `ao=null`
- `mute` 与 `volume` 是 `UPDATE_VOL` 选项（`options.c:778/784`），只改软音量，**音频解码与 AO 都还在跑**。**[源码]**
  好处：音频链还在，仍是 A/V 主时钟，demuxer 继续被消费。
- `aid=no` 同理走 `mp_switch_track_n`，拆音频解码器与 AO（`uninit_audio_out`）。**[源码]**
- **`aid=no` 与 `vid=no` 同时关**：mpv 明确考虑了这种情况——`handle_eof` 注释 *"It's possible for the user to
  simultaneously switch both audio and video streams to 'disabled' at runtime. Handle this by waiting rather than
  immediately stopping playback due to EOF."*（`playloop.c:1259-1265`）。**[源码]** 即**不会结束**，但此时没有
  任何消费者：所有流都 deselected，demuxer 不再有"想读的流"。**[推断]**：等价于暂停且不读网络，`time-pos`
  不推进——**不能当待机用**。同理，**音频缺失的流做 `vid=no` 也是这个状态**。
- `ao` 选项在 `options.c` 里没能确认带 `UPDATE_AUDIO` 运行期更新标志（`audio-*` 系列有，`ao` 本身没搜到），
  运行期切 `ao=null` **[待测]**；`mute=yes` 已足够，不必依赖它。

### 1.4 解码降载：`vd-lavc-skipframe` / `skiploopfilter` / `framedrop` / `hwdec`
- `vd-lavc-skipframe`：*"Skips decoding of frames completely. Big speedup, but jerky motion and sometimes bad
  artifacts"*；取值 `none/default/nonref/bidir/nonkey/all`。`vd-lavc-skiploopfilter`（仅 H.264/HEVC）：跳过环路
  滤波，*"big speedup with little visible quality loss"*。**[文档]** [options.rst L1998-2024](https://github.com/mpv-player/mpv/blob/master/DOCS/man/options.rst)
- 语义推断：`nonkey` 之后的 P 帧缺参考帧，**回来必有花屏直到下一个关键帧**——和 B 的"等关键帧"一个代价，却
  不拆解码器，意义不大。`nonref`/`bidir` 只在流里有 B/非参考帧时才省；**直播常见 baseline/无 B 帧，可能
  零收益**。`skiploopfilter=all` 会让误差累积、回来要等关键帧才干净。**[推断]**
- 这些是 **libavcodec 软解选项**。mova 在 Android 用 `mediacodec-copy`（CLAUDE.md），MediaCodec 没有对应
  旋钮，**大概率无效** **[推断]**；它们能否运行期热更新（还是下次解码器初始化才读）**[待测]**，若需要重建
  解码器就又退化成 B 的代价。
- `framedrop`（默认 `vo`）：*"This still decodes and filters all frames, but doesn't render them"*。**[文档]**
  它是为"慢机追同步"设计的，**不降解码量**，不是待机手段。
- 结论：**解码降载类选项不值得做成默认策略**，只作为"桌面软解时想再省点"的可选项。

### 1.5 渲染侧"不上屏"
- **`vo=null`**：mpv-android 的官方做法——surface 销毁时 `setPropertyString("vo","null")`，重建时再设回
  （[BaseMPVView.kt L83-106](https://github.com/mpv-android/mpv-android/blob/master/app/src/main/java/is/xyz/mpv/BaseMPVView.kt)）。**[源码]**
  视频解码器仍在跑，帧被 null VO 丢弃；回来 VO 重建后只要等**下一帧**（不用等关键帧）。VO 重建（GL 上下文
  创建）有成本 **[待测]**，mpv-android 自己也注释了竞态（"setting a property will wait for VO deinit"存疑）。
- **libmpv render API**：`MPV_RENDER_PARAM_SKIP_RENDERING`（[render.h L321-335](https://github.com/mpv-player/mpv/blob/master/include/mpv/render.h)）
  明确"跳过渲染但仍当作已渲染、时序照旧"——这是**官方支持的"不上屏但保持管线"**。但 media_kit_video 原生层
  自己持有 render context，**没有用也没有暴露这个参数**（`media_kit_video-2.0.1/windows/video_output.cc:173,190`
  只传 `OPENGL_FBO`；linux 同）。想用得 fork/改原生，不在本次范围。**[源码]**
- **桌面端 `VideoController.setSize(width, height)`**：media_kit 文档称小尺寸"may yield substantial performance
  improvements"（`native_video_controller/real.dart:197-224`）。是个不销毁纹理的降载手段，可缩到极小（如 2x2）
  再 `setSize()` 还原。**Android 不支持**：`AndroidVideoController.setSize` 直接 `throw UnsupportedError`
  （`android_video_controller/real.dart:221-228`）。**[源码]**
- **media_kit 在 Android 的 surface 回收路径本身就是 C 态**：`VideoOutput.onSurfaceCleanup` 把 `wid` 置 0
  （`VideoOutput.java:104-112`），Dart 侧 `widListener` 随即设 `vo=null`、`wid=0`，**`vid` 仅在
  `vo==mediacodec_embed` 时才改**（`android_video_controller/real.dart:48-77`，注释 *"When --wid is 0, vo=null
  is required to avoid SIGSEGV"*）——也就是默认 `vo=gpu` 时 surface 被回收后，**视频解码仍在，VO 是 null**。
  并且无论 wid 变 0 还是恢复，`widListener` 末尾都会 `player.seek(player.state.position)`（L73-76）。**[源码]**
  这个无条件 seek 对不可 seek 的直播意味着什么（是否失败/卡一下/触发"自动暂停"的观感）**[待测]**，很可能就是
  CLAUDE.md 里"Android 切后台 libmpv 自动暂停"现象的来源之一 **[推断]**。

### 1.6 缓存/读取
- `demuxer-max-bytes`：*"The demuxer will stop reading additional packets as soon as one of the limits is
  reached."* `demuxer-readahead-secs`（默认 1，启用 cache 时基本被忽略，取 max(cache-secs, readahead)）。
  `cache-pause`：缓存见底自动 pause/unpause。`cache-secs`：缓存启用时的预读秒数。**[文档]**
  [options.rst L4335 / L4425 / L5582-5640](https://github.com/mpv-player/mpv/blob/master/DOCS/man/options.rst)
- **这些都不是"待机"开关**：压低 `demuxer-max-bytes`/`cache-secs` 能让"暂停态"更早停读（省流量，但回来更落后）；
  待机态则要**保持足够预读**以免触发 `cache-pause` 缓冲。要不要在待机时调小（比如 cache-secs 压到 5~10s 降内存）
  属二阶优化 **[待测]**。
- 没有找到 mpv 专为"后台/低功耗"设计的内置选项；社区做法（mpv-android 后台播放）是**音频继续、
  surface 销毁时 `vo=null`**，而不是 `vid=no`（mpv-android 源码 `MPVActivity.kt onPauseImpl`/`BaseMPVView.kt`）。
  **[源码]**；mpv-android 用 `vo=null` 的理由我没找到文字说明，推测是避开 `vid` 重选的关键帧代价 **[推断]**。

## 2. 组合方案对比

约定：开销"量级"是**相对值**，均为 **[推断]**，未实测；绝对数据见 §5 测量方案。
假设 1080p H.264 直播、GOP 2s、2 Mbps、Android `mediacodec-copy`。

| | A 纯暂停 | B `vid=no`+`mute` | C 保持解码+不上屏 | D 现状（暂停+回来重连） |
|---|---|---|---|---|
| 做法 | `pause=yes` | 视频轨关，音频静音继续 | `vo=null`（Android/通用）或桌面 `setSize(2,2)` | 暂停；回来 ≥3s `backToLiveEdge()` |
| CPU/GPU | ≈0（解码停） | 低：仅 demux + 音频解码 | 中高：整条视频解码仍跑（`mediacodec-copy` 还有拷贝），仅省 GPU 渲染 | ≈0 |
| 网络 | 约 2 分钟（缓冲满）后停读，之后 0 | **满码率持续** | **满码率持续** | 同 A |
| 电量 | 最省 | 省（省的主要是解码+渲染） | 省得少 | 最省 |
| 直播能否保持在边缘 | 否，每秒落后 1s | **能** | **能** | 否，靠回来重连补 |
| 点播进度 | 停 | 继续走（别忘了会"看完"） | 继续走 | 停 |
| 恢复到出画面 | 0 + 但位置落后，直播还得重连 | 新建解码器 + 等关键帧（FLV 不可 seek）≈ 数百 ms ~ 1 个 GOP；可 seek 的 HLS 多一次缓存内 refresh seek | **等下一帧** + VO 重建（`vo=null` 路径）；setSize 路径近即时 | 重连：DNS/TLS/清单/首片/解码器/首帧，**秒级**（桌面 VOD 首帧 219ms 见 CLAUDE.md，直播未量） |
| HLS vs FLV | HLS：停读超过窗口，分片可能已被服务端滚走，回来要跳段 **[推断]**；FLV：长连接 TCP 反压，服务端可能踢慢客户端 **[推断]** | FLV 不可 seek→等关键帧；HLS 取决于 seekable | 两者同；HLS 更容易（帧级无需关键帧） | 重连对两者都稳，但最慢 |
| Android 后台(surface 回收) | 本就如此 | **前台内成立；真正进后台不成立**（系统限网/限 CPU，无前台服务保不住）[推断] | surface 回收路径 media_kit 已替你切到 `vo=null`，但有无条件 `seek()`（§1.5） | 成立，最稳妥 |
| 无音频流 | 可用 | **不可用**（§1.3，等价暂停且停读）| 可用 | 可用 |

其它变体：
- **E = B 与 C 组合**：有音频走 B；无音频走 C；决策依据 `audio-params`/音轨列表。
- **F = A + `drop-buffers`**：暂停，回来用 `drop-buffers` 清缓冲追边缘，省掉重开。实验性命令，仅在 TCP 连接
  还活着时有意义，且是否真"追到"边缘要实测 **[待测]**。
- **G = B/C 限时 + 回退**：待机最多 N 秒，超时升级为 A（pause）或 D，用 "网络持续满速"这一代价做上限。

## 3. HLS / HTTP-FLV 的差异（均为推断，未实测）

- **HTTP-FLV**：单条长连接，不可 seek。暂停/不消费到缓冲满后 TCP 窗口为 0，服务端（nginx-flv/SRS 等）通常设
  写超时会踢人 → 回来必须重连。待机（B/C）持续消费，连接保持；回来的关键帧等待取决于推流 GOP。
- **HLS（直播）**：按分片拉取；mpv 通过 ffmpeg `hls` demuxer，只在被读时才拉新分片/刷新清单。长时间不读
  → 回来时清单窗口已前移，ffmpeg 会跳段（位置变成"新边缘"附近），所以 A 的 HLS 实际上"自带半个追边缘"；
  B/C 持续拉，不丢段。HLS 通常 `seekable`，故 B 切回可能走 refresh seek（缓存内为主）。

## 4. media_kit 1.2.6 / media_kit_video 2.0.1 的限制

本机 pub cache：`media_kit-1.2.6`、`media_kit_video-2.0.1`（mova 的 `pubspec.yaml:23` 用的是 `^2.0.1`；
cache 里还有 1.3.0 / 2.0.1 两个版本，以 2.0.1 为准）。

1. **运行期 `setProperty` 可行**：`NativePlayer.setProperty(property, value, {waitForInitialization = true})`
   （`native/player/real.dart:1223`），mova 已在用（`mpv_kernel.dart:185-186` 设 `tls-verify`，且判断
   `player.platform is NativePlayer`）。要点：默认 `waitForInitialization=true` 会先等
   `waitForPlayerInitialization` 与 `waitForVideoControllerInitializationIfAttached`——**VideoController 挂界面前
   这个 await 可能不返回**，这与 CLAUDE.md 记录的 dispose 卡死同源 **[源码]**。待机逻辑在 `vid`/`mute` 上
   应沿用 mova 现有的"懒创建"前提：已挂界面才会有视频管线。
2. **`Player` 默认 `vid=no`**，`VideoController.create()` 才把它设回 `auto`
   （`native/player/real.dart:2323-2325`；`native_video_controller/real.dart:158-160`，Android 在
   `android_video_controller/real.dart:196-203`）。**含义：** media_kit 把 `vid` 当"受控属性"；运行期自己改 `vid`
   不会被 media_kit 回写，但**不要和 `VideoController` 的 `widListener` 同时改**（Android 的 `widListener` 在
   `vo==mediacodec_embed` 时也会改 `vid`，L63-66）。**[源码]**
3. **`vid=no` 期间 VideoController/纹理**：
   - 桌面：纹理和 render context 由 `VideoOutputManager` 持有，`vid` 变化不销毁它们 **[推断，源码未见 vid 相关
     释放逻辑]**；`vid=no` 期间没有帧，画面保持**最后一帧还是黑**由 Flutter 纹理内容决定，**[待测]**。
   - Android：纹理是 `SurfaceProducer`，`vid=no` 不影响 surface；回来后 mediacodec 解码器重建，**注意
     `mediacodec_embed` 下源码里有注释** *"It is important to re-initialize --vid in-case of --vo=mediacodec_embed.
     Not doing so causes error 'Could not open codec.' & video never gets rendered."*（L63）——说明 **vid 重选 +
     硬解的组合在 media_kit 里被踩过坑**，用 mova 默认的 `gpu`+`mediacodec-copy` 虽不走 embed，也需真机验证
     切回能出画。**[待测]**
4. **没找到** 针对"运行期切 `vid`"的 media_kit 官方 issue/限制说明（搜索 media-kit 仓库未命中相关议题）。
   能确定的只有 CLAUDE.md 里的 **"创建了 VideoController 却不挂界面就 dispose 会卡"**，所以：
   待机**绝不**能通过"销毁/重建 VideoController"实现，只能在**已挂界面**的 Player 上改属性。
5. **Android 无条件 `seek(currentPosition)`**（§1.5）会在 surface 丢失/恢复时触发，对不可 seek 直播的后果
   **[待测]**；这也是 mova 要守卫的 Android 现象的候选根因。
6. **`VideoController.setSize()` 桌面可用、Android 抛 `UnsupportedError`**——Android 上无法用"缩小纹理"
   降载，只能 `vo=null` 或 `vid=no`。

## 5. 对 mova 的落地建议

### 5.1 要不要做
**做，但定位成"守卫的一个可选 `standby` 模式"，默认关；不要替换现有 pause 路径。** 理由：
- 它省的是**重连+等首帧**的体验延迟，代价是**持续满速下载 + 解码器重建后的关键帧等待**，本质是"用流量/少量
  CPU 换回来的速度"，必须由宿主决策（bingo 的直播卡片、可能在蜂窝网络）。
- 不能保证 0 延迟；真实收益必须靠 §6 的实测量化后才好承诺。

### 5.2 做成什么样（草案，不写代码）
- **API：** `MovaAutoPauseConfig` 增加 `hiddenMode`（枚举：`pause`（默认，现状）/ `standby`），而不是新开
  公共方法。需要手动控制的宿主再暴露 `MovaApi.setStandby(bool on)`（同一能力的命令式入口）。
  `standbyMaxDuration`（默认 30s~60s）：超时升级为 `pause`（G 方案），防止长期白耗流量与电量。
- **内核端口：** 新增 `MovaKernel.setStandby(bool)`（`MovaMpvKernel` 内实现）。**必须落在
  `kernel/mpv_kernel.dart`**——`purity_test` 只允许它 import media_kit（见 CLAUDE.md；plan Task 12 的约束
  "`mpv_kernel.dart` 任何 Task 不许改"针对的是守卫那个计划，待机需要另开一个 plan 并解除该约束）。
- **内核策略（按流类型/能力选）：**
  - 流有音频：`vid=no` + `mute=yes`（B）。进入前记下原 `mute`/`volume`，退出时精确还原。
  - 无音频流：`vo=null`（C；Android 平台 media_kit 已在 surface 丢失时自动做，需避免和 `widListener` 打架，
    建议**待机只在"surface 仍在、App 在前台"时用 `vid=no`，不去碰 `vo`/`wid`**）。桌面可选
    `setSize(2,2)`。
  - 点播：**默认还是 pause**（点播暂停没有边缘问题，重连也无需要）；待机只在直播上有意义。
- **与守卫关系：** 守卫 gate 的输出本来是 "hidden→pause / visible→play / ≥3s→backToLiveEdge"，加一个
  `hiddenMode==standby` 分支：hidden→`setStandby(true)`（流量持续）；visible→`setStandby(false)`，**不**再
  `backToLiveEdge()`，因为本来就在边缘。仍保留 App 进后台走 `pause`（§2 表末两行：后台不适用待机）。
- **与 feed 引擎池：** feed 的 `focus()` 已保证"只有一页出声"（plan L249）。非焦点页本就应是 `pause`/低开销；
  **不要给 feed 页套守卫的 standby**。若池里要保留"邻近页热引擎"，待机可用于"邻近页保温"
  （不出声不出画面，只维持连接），收益/风险与上面一致，但属二期。
- **与 swap 引擎（`MovaSwapEngine`）：** 影子引擎预热期间本来就有画面管线；待机作用对象是"当前 active 引擎"，
  swap 时需把待机状态**同步给新引擎**或在 swap 前先退出待机，避免换进来的是个 `vid=no` 的引擎。

### 5.3 默认值建议
| 项 | 建议默认 | 理由 |
|---|---|---|
| `hiddenMode` | `pause` | 不改变现有行为，待机是 opt-in |
| `standbyMaxDuration` | 30s | 超过它的"隐藏"多半是长离开，回到 D 更省 |
| 点播 | 强制 `pause` | 待机无收益 |
| App 进后台 | 强制 `pause` | 系统限制，且不应偷偷消耗流量 |
| 蜂窝网络 | 宿主决定，文档标注"持续满速下载" | 流量代价 |

## 6. 必须真机实测的清单（真机目前不在手，只写方案）

**测量方法（通用）：** 全部用**真实事件的时间戳**，不用墙钟拍脑袋。恢复延迟 = `T(触发退出待机的属性写入完成)` →
`T(PLAYBACK_RESTART 原生事件，或 MovaFirstFrame)`。mova 已有 FFI 弱客户端订阅
`PLAYBACK_RESTART`/`END_FILE`（`core/kernel/mpv_event_backend.dart`、`platform_impl/mpv_event_backend_ffi.dart`，
CLAUDE.md "自建原生事件订阅"）；`MovaFirstFrame` 为 UI 层首帧。另用 mpv `--msg-level=demux=v,vd=v` 取
"refresh track / refresh seek / reinit decoder"日志，判断是否真的回读了网络。

| # | 问题 | 方法 | 判据 |
|---|---|---|---|
| T1 | `vid=no`→`auto` 恢复延迟（FLV，不可 seek） | 直播推 GOP=1s/2s/4s 三档，待机 10s/30s/120s 后退出，各 20 次，量 `写入 vid=auto` → RESTART/首帧 | 延迟随 GOP 变，中位数≈解码器初始化+½ GOP |
| T2 | 同上（HLS 直播） | 同上；开 `demux=v` 看是否出现 `refresh seek` 与新分片请求（抓包/代理日志） | 有无回读网络；延迟是否仍随 GOP |
| T3 | C 方案（`vo=null`→`gpu`）恢复延迟 | Android 真机，量 `vo` 设回 → 首帧 | 应小于 T1；看 VO 重建成本 |
| T4 | 网络/电量/CPU | 同一直播流分别跑 A/B/C 5 分钟：`dumpsys batterystats`/`netstats`、CPU（`top`/`dumpsys cpuinfo`）、`dumpsys meminfo` | A 约 0 流量（缓冲满后）；B/C 流量≈满速；量化 B、C 的 CPU 差 |
| T5 | 直播边缘保持 | 待机 60s 后退出，读 `demuxer-cache-time`/`time-pos` 与"边缘"（`seekableWindow` 或服务端时间）差 | 应与待机时长无关 |
| T6 | 无音频流上 B | 无音轨直播做 `vid=no`，读 `time-pos` 是否推进、`demuxer-cache-time` 是否增长 | 验证 §1.3 推断（应停） |
| T7 | `mediacodec-copy` + `vid=no/auto` 切回是否能出画 | Android 真机 20 次来回切 | 无黑屏/"Could not open codec" |
| T8 | Android surface 回收路径 | HOME 键 5s/60s/5min 后回前台，记 `wid` 变化、`vo`、`time-pos` 跳变、是否 `playing` 变 false | 弄清 `widListener` 无条件 `seek` 的后果 |
| T9 | 软解下 `skipframe=nonref`/`skiploopfilter=all` 是否热更新 + 是否有收益 | 桌面软解（`hwdec=no`）量 CPU | 若无收益，从方案里删掉 |
| T10 | `drop-buffers`（F）能否替代重开 | 暂停 30s/120s 后执行，看是否追到边缘及重连发生与否 | 决定要不要保留 F |
| T11 | `volume=0`/`mute` 时 Android 是否仍占音频会话/耗电 | `dumpsys audio`、`batterystats` | 评估 B 的音频侧底噪 |
| T12 | 桌面 `setSize(2,2)` 的 GPU 降载与还原延迟 | Windows，GPU-Z/任务管理器 + 还原到首帧耗时 | 决定桌面是否要单独策略 |

## 7. 来源

mpv 一手来源（均 `master`，2026-10-23 抓取）：
- 选项手册源：[options.rst](https://github.com/mpv-player/mpv/blob/master/DOCS/man/options.rst)（`--vid` L116、`--framedrop` L1258、`--vd-lavc-skiploopfilter/skipframe` L1998/2021、`--demuxer-max-bytes` L4335、`--demuxer-readahead-secs` L4425、`--cache*` L5582-5649）
- 命令/属性：[input.rst](https://github.com/mpv-player/mpv/blob/master/DOCS/man/input.rst)（`drop-buffers` L1685、`core-idle` L2625）
- 直播延迟说明：[mpv.rst L1246-1249](https://github.com/mpv-player/mpv/blob/master/DOCS/man/mpv.rst)
- 源码：[player/loadfile.c `mp_switch_track_n`](https://github.com/mpv-player/mpv/blob/master/player/loadfile.c)、[player/video.c `uninit_video_chain`](https://github.com/mpv-player/mpv/blob/master/player/video.c)、[demux/demux.c `initiate_refresh_seek`/`select_track`](https://github.com/mpv-player/mpv/blob/master/demux/demux.c)、[player/playloop.c `handle_eof`](https://github.com/mpv-player/mpv/blob/master/player/playloop.c)、[options/options.c](https://github.com/mpv-player/mpv/blob/master/options/options.c)
- libmpv render API：[include/mpv/render.h](https://github.com/mpv-player/mpv/blob/master/include/mpv/render.h)（`MPV_RENDER_PARAM_SKIP_RENDERING` L321-335）
- 社区做法：[mpv-android BaseMPVView.kt](https://github.com/mpv-android/mpv-android/blob/master/app/src/main/java/is/xyz/mpv/BaseMPVView.kt)、[MPVActivity.kt](https://github.com/mpv-android/mpv-android/blob/master/app/src/main/java/is/xyz/mpv/MPVActivity.kt)

本地源码：
- `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\media_kit-1.2.6\lib\src\player\native\player\real.dart`（L1223 `setProperty`、L2323-2325 默认 `vid=no`、L2400-2427 初始属性）、`platform_player.dart:530`（`bufferSize`）
- `...\media_kit_video-2.0.1\lib\src\video_controller\native_video_controller\real.dart`（L158-160、L197-224）、`android_video_controller\real.dart`（L48-77 `widListener`、L196-203 `vid=auto`、L221-228 `setSize` 抛异常）、`android\src\main\java\...\VideoOutput.java`（L94-112 surface 回调）、`windows\video_output.cc:173,190`
- mova：`lib/src/core/engine.dart:1492`（`backToLiveEdge`）、`lib/src/core/kernel/mpv_kernel.dart`（构造/`_applyTls`）、`doc/plans/2026-10-23-host-ergonomics.md`（D9 L220-249、Task 12/13）、`CLAUDE.md`（audioOnly、懒创建、dispose 卡死）

**未做/未验证声明：** 本机无 `mpv` 命令行，没做桌面实验；没找到 media_kit 关于运行期切 `vid` 的 issue；
所有"开销量级"与"HLS/FLV 服务端行为"均为推断，需 §6 实测后才能当承诺。
