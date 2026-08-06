# ffmpeg 瘦身：解码器/容器/协议完整盘点（现代主流点播 + 直播范围）

> 2026-07-31 · 调研笔记 · 对应遗留任务 #4「二期 ffmpeg 瘦身」（[CLAUDE.md](../../CLAUDE.md)
> 未开始项），与 [2026-07-31-libmpv-slimming-options.md](2026-07-31-libmpv-slimming-options.md)
> 是同一件事的两个层面——那份盘点 libmpv 自己的构建选项（脚本引擎、字幕渲染、显示/音频
> 输出后端），本文档盘点**libmpv 底下包的 ffmpeg**：解码器、容器格式（demuxer/muxer）、
> 网络协议。范围锁定为"现代主流点播 + 直播"，边界经用户拍板（见 §0）。选项名称来源：
> ffmpeg 官方仓库 `master` 分支源码（2026-07-31 拉取核对）：
> - `libavcodec/allcodecs.c`（解码器/编码器注册表）
> - `libavformat/allformats.c`（demuxer/muxer 注册表）
> - `libavformat/protocols.c`（协议注册表）
>
> 本文档只做**盘点与分类**，不是可执行的瘦身脚本——真正动手瘦身时以此为起点，仍需实际
> `./configure --disable-everything --enable-...` 编译验证，某些组件之间有隐式依赖
> （例如某解复用器可能在内部需要某个 bitstream filter），静态盘点无法完全替代实测。

## 0. 范围边界（用户已拍板，2026-07-31）

**这次瘦身"现代主流"的定义，不是纯技术判断，是产品范围决策**，已问过用户拍板：

| 场景 | 是否支持 | 说明 |
|---|---|---|
| FLV-over-HTTP / RTMP 直播 | **需要，保留** | 国内直播平台（抖音/虎牙/斗鱼类）常用，与 HLS 并列，不能按纯西方"现代streaming"标准（YouTube/Netflix 早已转向 HLS/DASH）想当然砍掉。 |
| MPEG-DASH | **需要，保留** | 与 HLS 并列的另一套自适应流标准，虽然 mova 现有文档（`MovaLiveConfig`/DVR/时移）都是围绕 HLS 设计的，但用户明确要保留 DASH 源的可能性。 |
| RTSP（IP 摄像头类实时流） | **需要，保留** | 监控摄像头/实时推流场景。 |
| Android `content://` 本地相册 URI | **不需要** | mova 定位是 CDN 点播/直播播放器，不是本地相册播放器，用户明确不需要。 |

## 1. 视频解码器（`libavcodec/allcodecs.c`）

| 解码器 | 去留 | 说明 |
|---|---|---|
| `h264` | **保留** | H.264/AVC，点播/直播最基础、最普及的视频编码，任何"主流"范围都必须有。 |
| `hevc` | **保留** | H.265/HEVC，4K/高码率场景的主流编码，现代点播（尤其国内视频平台）广泛使用。 |
| `vp9` | **保留** | VP9，YouTube 等平台 WebM 系的主流编码。 |
| `av1` | **保留** | AV1，新一代开放编码，Netflix/YouTube/Twitch 等正逐步转向，"现代主流"范围理应包含。 |
| `vp8` | 待定，倾向保留 | 老一代 WebM 编码，多数新内容已转向 VP9/AV1，但存量 WebM 内容与部分直播场景仍可能用到；体积代价小，建议保留，除非日后实测发现完全用不上。 |
| `mpeg2video` / `mpeg1video` | **可关** | 老式广电/DVD 时代编码，点播/直播源不会用这个。 |
| `mpeg4`（DivX/Xvid 系） | **可关** | 老式编码，"现代主流"范围不含。 |
| `h263` | **可关** | 更老的视频会议时代编码，不适用。 |
| `wmv1`/`wmv2`/`wmv3`/`vc1` | **可关** | Windows Media 系视频编码，国内外主流点播/直播都已不用。 |
| `theora` | **可关** | Ogg 生态的老式开放编码，早已被 VP8/VP9 取代，不适用。 |
| `rv10`/`rv20`/`rv30`/`rv40` | **可关** | RealVideo，早已淘汰。 |
| `indeo2`/`indeo3`/`indeo4`/`indeo5` | **可关** | 老式专有编码，不适用。 |
| `cinepak` | **可关** | 上世纪 90 年代的老编码，不适用。 |
| `flv1`（Sorenson Spark） | **可关** | 早期 FLV 常用的老编码；**注意与"是否支持 FLV 容器"是两回事**——保留 FLV/RTMP **容器/协议**支持（见 §3/§4）不代表要保留这个老编码，现代 FLV 直播流通常已经是 H.264/AAC 编码、只是外层封装用 FLV，`flv1` 这个具体老编码本身可以关。 |
| `prores` | **可关** | 专业剪辑用编码（苹果 Final Cut 生态），不是消费级点播/直播场景。 |
| `msmpeg4v1`/`v2`/`v3` | **可关** | 微软早期私有 MPEG-4 变种，不适用。 |

## 2. 音频解码器

| 解码器 | 去留 | 说明 |
|---|---|---|
| `aac` / `aac_latm` | **保留** | AAC，点播/直播最主流音频编码（MP4/HLS/DASH 标配）；`aac_latm` 覆盖某些 MPEG-TS/HLS 流里 LATM 封装的 AAC，HLS/直播场景可能用到，一并保留。 |
| `mp3` / `mp3float` | **保留** | MP3，虽老但仍极为普及，很多点播源音轨仍是 MP3。 |
| `opus` | **保留** | 现代 Web 音频编码，WebM/DASH 生态常用，"现代主流"范围应包含。 |
| `ac3` / `eac3` | **保留** | Dolby Digital / Dolby Digital Plus，很多广播源/影视点播内容的环绕声音轨仍用这个，直播/点播都可能遇到。 |
| `flac` | **保留** | 无损音频，部分高品质点播源会用。 |
| `vorbis` | 待定，倾向保留 | 老一代 WebM 音频编码，多数新内容已转向 Opus，但存量 WebM 点播内容可能仍用 Vorbis 音轨；体积代价小，建议保留。 |
| `mp2` | **可关** | MPEG-1 Layer II，老式广播音频编码，现代点播/直播基本不用。 |
| `wmav1`/`wmav2` | **可关** | Windows Media 音频，不适用。 |
| `ra_144`/`ra_288` | **可关** | RealAudio，早已淘汰。 |
| `dts` | **可关** | 蓝光/影院环绕声编码，且有专利/授权顾虑，消费级点播/直播不适用。 |
| `truehd` | **可关** | 蓝光无损音频，同上不适用。 |
| `alac` | **可关** | Apple 无损音频，除非专门要放苹果生态本地文件，点播/直播源不适用。 |
| `speex` | **可关** | 老式 VoIP 语音编码，不适用。 |
| `amr_nb`/`amr_wb` | **可关** | 手机通话录音编码，不适用于视频点播/直播场景。 |
| 各类 `adpcm_*`（几十种变体） | **可关** | 老游戏/老容器格式专用的一大批 ADPCM 变体，点播/直播源完全用不到。 |
| `gsm`/`gsm_ms` | **可关** | 电话语音编码，不适用。 |

## 3. 容器格式（demuxer，`libavformat/allformats.c`）

| Demuxer | 覆盖范围 | 去留 | 说明 |
|---|---|---|---|
| `mov` | MP4/MOV/M4A/3GP/3G2/MJ2（ISO-BMFF 全家桶，ffmpeg 用同一个 demuxer 处理） | **保留** | 点播最主流容器，必须有。 |
| `matroska` | MKV **和** WebM（ffmpeg 用同一个 demuxer，按扩展名/内容区分） | **保留** | 点播常见容器。 |
| `mpegts` | HLS 的 `.ts` 分片、传统广电流 | **保留** | HLS 播放必需（HLS 的 TS 分片本身要靠这个解复用）。 |
| `hls` | HLS 播放列表（master/media playlist）本身 | **保留** | HLS 播放的入口，必须有（mova 手动清晰度切换是应用层解析 master playlist，但底层 ffmpeg 仍需要这个来处理 media playlist/分片调度）。 |
| `dash` | MPEG-DASH 播放列表（MPD） | **保留（用户已拍板）** | 见 §0。 |
| `flv` / `live_flv` | FLV 容器（含直播场景的 live-flv 变体） | **保留（用户已拍板）** | 见 §0，国内直播常用。 |
| `rtsp`（作为 demuxer 端） | RTSP 流的媒体描述/会话 | **保留（用户已拍板）** | 见 §0，需与 §4 的 `rtsp`/`rtp` 协议配套保留。 |
| `avi` | 老式 Windows 容器 | **可关** | 点播/直播源不会用 AVI。 |
| `asf` | Windows Media 容器（wmv 的外层） | **可关** | 同上，不适用。 |
| `rm` | RealMedia 容器 | **可关** | 早已淘汰。 |
| `ogg` | Ogg 容器（配 Vorbis/Theora/Opus） | 待定，倾向保留 | 若保留 `vorbis` 音频解码器（见 §2），配套的 Ogg 容器也建议一并保留；若最终决定 Vorbis 可关，Ogg 容器也可一并关闭。 |
| `mpegps`（VOB/DVD 风格） | 老式 DVD 风格容器 | **可关** | 不适用于点播/直播源。 |
| `webm_dash_manifest` | WebM 专属的 DASH 清单变体（不同于标准 `dash`） | **可关**，除非明确要支持 WebM-DASH 混合场景 | 是一个相对小众的变体，标准 `dash` demuxer 已覆盖主流 DASH 需求。 |

## 4. 网络协议（`libavformat/protocols.c`）

| 协议 | 去留 | 说明 |
|---|---|---|
| `file` | **保留** | 本地文件访问，测试/缓存场景仍需要。 |
| `http` / `https` / `tls` | **保留** | 网络流播放的绝对核心，任何 HLS/DASH/点播源都依赖。 |
| `crypto` | **保留** | HLS AES-128 加密分片解密用，很多正式商用 HLS 流是加密的，必须保留。 |
| `data` | **保留** | `data:` URI，体积成本极小，保留无妨（部分场景用于内嵌小段元数据）。 |
| `async` / `cache` | **保留** | ffmpeg 内部缓冲/异步读取的辅助协议，其他协议链路常隐式依赖，建议保留。 |
| `rtmp` / `rtmps` / `rtmpe` / `rtmpt` / `rtmpte` / `rtmpts` | **保留（用户已拍板）** | 见 §0，国内直播常用；几个变体分别对应明文/加密/走 HTTP 隧道等变种，直播源具体用哪个不确定时建议全部保留。 |
| `rtsp`（配 `rtsp_demuxer`）+ `rtp` | **保留（用户已拍板）** | 见 §0，IP 摄像头/实时流场景；RTSP 协商后通常走 RTP 传输媒体数据，两者需配套保留。 |
| `udp` | 待定，倾向保留 | RTSP/RTP 场景常见的底层传输协议，若保留 RTSP/RTP 支持，`udp` 大概率也要保留（否则 RTP-over-UDP 传输走不通）。 |
| `ftp` | **可关** | 老式文件传输协议，点播/直播源不会用 FTP 地址。 |
| `libssh`（SFTP） | **可关** | 同上，不适用。 |
| `libsmbclient`（SMB/CIFS 局域网共享） | **可关** | 不适用于 CDN 点播/直播场景。 |
| `gopher` / `gophers` | **可关** | 上世纪的老协议，不适用。 |
| `mms` / `mmsh` / `mmst` | **可关** | Windows Media 流媒体协议，早已被淘汰，不适用。 |
| `icecast` | **可关** | 主要用于音频网络电台，不是视频点播/直播场景。 |
| `sctp` / `srtp` / `prompeg` | **可关** | 专业广播贡献链路（contribution feed）场景用的协议，不是消费级 CDN 点播/直播播放器需要的。 |
| `librist` | **可关** | 专业低延迟广播贡献协议（Reliable Internet Stream Transport），同上，niche 场景。 |
| `libsrt`（Secure Reliable Transport） | **可关**，除非未来要接专业推流贡献源 | SRT 主要用于专业直播/广播的"贡献链路"（推流到 CDN 那一段），不是消费者观看 CDN 分发内容需要的协议；mova 是播放器不是推流器，一般用不到。 |
| `librtmp`/`librtmpe`/`librtmps`/`librtmpt`/`librtmpte` | **可关** | ffmpeg 自带的 `rtmp*` 协议实现已经原生支持 RTMP（见上），这些是依赖外部 `librtmp` 库的替代实现，通常不需要重复保留。 |
| `libamqp` / `libzmq` | **可关** | 消息队列协议桥接，与视频播放场景无关。 |
| `ipfs_gateway` / `ipns_gateway` | **可关** | IPFS 分布式存储网关协议，不是点播/直播场景常见来源。 |
| `bluray` | **可关** | 蓝光光盘协议，与 §1（libmpv 盘点）里蓝光相关项一致，不适用。 |
| `subfile` / `concat` / `concatf` / `tee` | **可关** | ffmpeg 命令行工具常用的流拼接/多路输出工具协议，播放器场景不需要。 |
| `md5` | **可关** | 调试用的校验协议，不适用于生产播放场景。 |
| `unix` | **可关** | Unix 域套接字，不适用。 |
| `pipe` / `fd` | **可关**，除非内部工具链依赖 | 进程管道协议，mova 播放网络/文件源不需要，除非未来构建工具链内部另有用途。 |
| `android_content` | **可关（用户已拍板不需要本地相册场景）** | 见 §0。 |

## 5. Bitstream Filters（简要提示，需实测确认依赖关系）

`h264_mp4toannexb` / `hevc_mp4toannexb` 这类比特流过滤器，在"MP4 封装（NAL 长度前缀格式）
与 MPEG-TS/Annex B 格式互转"的场景下（例如某些 HLS 分片场景内部）可能被隐式需要。**这类
过滤器通常由相关 demuxer/muxer 在编译期自动拉入依赖，不建议手工精确摘除**——`--disable-
everything` 之后优先靠实际编译报错/运行时报错来确认缺了哪个，而不是单靠静态盘点猜测。

## 6. 硬件加速——与 libmpv 盘点保持一致，不要在两份文档间产生分歧

硬解路径应严格对应
[2026-07-31-libmpv-slimming-options.md](2026-07-31-libmpv-slimming-options.md) §2 已定的
"每平台只留实际使用的那条"结论：Android 保 MediaCodec 相关（`h264_mediacodec`/
`hevc_mediacodec`/`aac_mediacodec`/`av1_mediacodec`/`vp8_mediacodec` 等 `_mediacodec_decoder`
变体，与 `--enable-mediacodec`）、iOS/macOS 保 VideoToolbox 硬解路径（ffmpeg 里这条不是
独立的 `_decoder` 条目，而是通过 `--enable-videotoolbox` 这个 hwaccel 开关叠加在标准
`h264`/`hevc` 软解码器之上）、Windows 保 D3D11VA（`--enable-d3d11va`，同样是 hwaccel
开关叠加模式，非独立解码器）。**其余平台专属硬解变体（`_qsv`/`_cuvid`/`_amf`/`_v4l2m2m`/
`_rkmpp` 等）均可关**——这些分别对应 Intel QuickSync、NVIDIA、AMD、Linux V4L2、瑞芯微等
专用硬件平台，均不是 mova 目标平台会用到的路径。

## 7. 待办

- 真正启动瘦身工作时，按本清单配置 `./configure --disable-everything --enable-decoder=
  ... --enable-demuxer=... --enable-protocol=...`，实测编译产物体积，并与
  [2026-07-31-libmpv-slimming-options.md](2026-07-31-libmpv-slimming-options.md) 的
  29.76MB 基线一并对比、回填两份文档。
- 待定项（`vp8`/`vorbis`+`ogg`/`webm_dash_manifest`/`udp`/`pipe`+`fd`）在实测阶段按实际
  编译/播放验证结果决定去留，不要停留在静态判断。
- §5 的 bitstream filter 依赖关系需要通过实际 `--disable-everything` 编译报错来定，不能
  单靠本文档的静态盘点。

## 参考

- ffmpeg 解码器/编码器注册表（`libavcodec/allcodecs.c`，2026-07-31 拉取自 `master` 分支）
  https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/allcodecs.c
- ffmpeg demuxer/muxer 注册表（`libavformat/allformats.c`）
  https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/allformats.c
- ffmpeg 协议注册表（`libavformat/protocols.c`）
  https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/protocols.c
- 相关调研：[2026-07-31-libmpv-slimming-options.md](2026-07-31-libmpv-slimming-options.md)
  （libmpv 自身构建选项盘点，脚本引擎/字幕渲染/显示后端等）
