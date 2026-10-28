# 在线测试源清单与裁剪版 libmpv 实测（2026-10-28）

给 mova 找一批**真实在线**、公开且明确可用于测试/演示的点播与直播地址，覆盖裁剪版 libmpv 支持的格式与协议，
并用**我们自己的裁剪版 `libmpv-2.dll`** 实际播放验证。机器可读的清单在
[example/tool/online_sources.json](../../example/tool/online_sources.json)，批量复测脚本是
[example/tool/online_sources_probe.py](../../example/tool/online_sources_probe.py)。

## 1. 结论速览

- 入库 **100** 项，全部在 2026-10-28 当天**两轮（不同时刻）**实测都符合预期：点播可播 59、反例被明确拒绝 14、直播可播 27（HLS 直播 14、网络电台 13）。
- 测试对象是仓库里的 `libmpv/windows-x86_64-whep/libmpv-2.dll`（sha256 `09f672b0…bc74`，10,879,488 字节，mpv v0.41 / API 2.5，ffmpeg n9.0.2，Windows Schannel TLS），不是完整版 ffmpeg。
- **Android 版没测**（约束：不碰手机）。两个平台的 flavor 有差异，见第 2 节，Windows 上通过不代表 Android 上通过。
- 缺口（没找到可用公开源）：线上 RTMP/RTMPS 直播、HTTP-FLV 直播、第二个低延迟 HLS 来源、4K 点播、120fps 点播、Ogg Vorbis 电台。原因见第 6 节。
- 几个值得 mova 侧关注的实测发现放在第 5 节（无 Range 服务器上 moov 在尾的 MP4 播不了、不支持的视频编码会静默变成只出声、Schannel 间歇握手失败等）。

## 2. 我们支持什么（目标格式以此为准）

出处：Windows 看 [`mova-libmpv/tools/whep-flavor/build-windows.sh`](../../../mova-libmpv/tools/whep-flavor/build-windows.sh) 的 `step_ffmpeg`（约 205–225 行）；
Android 看 [`mova-libmpv/flavors-mova-slim-n9.sh`](../../../mova-libmpv/flavors-mova-slim-n9.sh)（CI 的 `apply-v041.sh` 会再往 `DEMUXERS`/`PROTOCOLS` 里追加 `whep`/`dtls`）；
协议白名单看 `lib/src/core/kernel/mpv_defaults.dart` 的 `movaProtocolWhitelist()`。
老的 [`configure-ffmpeg-slim.sh`](../../../mova-libmpv/configure-ffmpeg-slim.sh) 是 n6 时代清单（还带 vp8/mjpeg 解码），已不是现行配方，仅作参考。

| 项 | Windows（本次实测对象） | Android（flavor 脚本） |
| --- | --- | --- |
| demuxer | mov、matroska（含 webm）、webm_dash_manifest、mpegts、hls、flv、live_flv、data、mp3、flac、ogg、wav、aac、**ac3、eac3**、ass、srt、webvtt（+whep） | 同左，但**没有 ac3、eac3** |
| 协议 | file、fd、pipe、data、http、https、tcp、tls、crypto、rtmp/rtmps/rtmpt/rtmpts、ffrtmpcrypt、ffrtmphttp、udp、rtp（+dtls） | 同左 |
| TLS | Windows Schannel | mbedtls |
| 视频解码 | **软解** h264、hevc、vp9、AV1（libdav1d）、png；d3d11va/dxva2 hwaccel | 软解只有 hevc、AV1（libdav1d）、png；h264/hevc/vp9/av1 走 **MediaCodec 硬解**（无 h264/vp9 软解） |
| 音频解码 | aac、aac_latm、mp3、mp3float、opus、**ac3、eac3**、flac、vorbis、pcm_* | 同左，但**没有 mp3（定点）、ac3、eac3** |
| 字幕解码 | ass、ssa、subrip、text、webvtt、movtext（libass 保留） | 同左 |
| avfilter | 无（`--disable-filters`，未 enable 任何 filter） | 无（`FILTERS=""`） |

**明确没有**（Windows 与 Android 都一样）：VP8 解码、MJPEG 解码、DASH 的 `dash` demuxer（只有 `webm_dash_manifest`，标准 MPD 播不了）、
rtsp/sdp、MPEG-PS（`.mpg`）、AVI、ASF/WMV、RealMedia、Ogg Theora 视频、WMA 音频、裸 HEVC 码流（`.hevc`）。

两条差异在测试里要留意：

1. **ac3/eac3**：只有 Windows 版有。Android 版遇到 E-AC-3 音轨会缺声（推断：flavor 清单里确实没有，但没在 Android 上跑过）。
2. **MPEG-2 视频**：Windows 清单里没写 `mpeg2video`，但实测 `.ts` 样本里的 MPEG-2 视频能解码出画面，日志里还有 mpeg2video 解码器自己的告警。
   推断原因：ffmpeg 的 `d3d11va`/`dxva2` hwaccel 在 configure 里会隐式选入 `mpeg2video`（对应还有 vc1/wmv3）。Android 没有这套 hwaccel，**推断**那边不会带。

协议白名单（`movaProtocolWhitelist()` = media_kit 默认 + `dtls`）：udp、rtp、tcp、tls、data、file、http、https、crypto、dtls。
实测发现它**不影响 RTMP**（见第 5 节第 3 条）。

## 3. 怎么测的

- 判定脚本：`example/tool/online_sources_probe.py`，每个源先 `ffprobe`（完整版 ffmpeg 8.0，只用来取元数据/对照），再用 Python ctypes 加载 `libmpv-2.dll` 真实播放。
- 配置尽量贴近 mova：`vo=null`、`ao=null`、`audio-display=no`、`network-timeout=15`，
  `demuxer-lavf-o=seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=[udp,rtp,tcp,tls,data,file,http,https,crypto,dtls]`
  （与 media_kit 1.2.6 注入的值一致）。
- 点播通过标准：`file-loaded` 之后，`time-pos` 在 10 秒内至少推进 3 秒；若 ffprobe 显示有视频流（不含封面图），还要求 `video-params/w` 存在（视频真的被解出来，不是只出声）。
- 直播通过标准：同上，再隔 20 秒还要再推进 ≥10 秒且没收到 `END_FILE`。
- 反例通过标准：限时内收到 `END_FILE(error)` 且推进不足 3 秒；不报错也不推进（挂起）算失败。
- 每个源在**两个不同时刻**各测一次（第一轮约 12:31–12:38，第二轮约 12:40–12:47，本机时间），只收两轮都符合预期的。
- 每个源在独立子进程里跑，带硬超时（连同子孙进程一起杀），libmpv 卡死不会拖垮批处理。

复测用法：

```bash
# 注意加 -I，避免当前目录的同名模块被误导入
python -I example/tool/online_sources_probe.py                       # 全部（约 7 分钟，--jobs 默认 3）
python -I example/tool/online_sources_probe.py --kind live           # 只测直播
python -I example/tool/online_sources_probe.py --only hls-aes128-oceans,live-hls-dw
python -I example/tool/online_sources_probe.py --alternatives        # 主地址失败时依次试 alternatives
python -I example/tool/online_sources_probe.py --ffprobe-only        # 没有 dll 时只用 ffprobe，结果标 N/A（未经裁剪版验证）
python -I example/tool/online_sources_probe.py --out result.json --label r2
```

仓库里的 `libmpv-2.dll` 是 **Git LFS 指针**，没拉过的话脚本会提示并降级为只用 ffprobe。想用真实 dll：
`git lfs fetch --include="mova/libmpv/windows-x86_64-whep/libmpv-2.dll"`，再把 `.git/lfs/objects/09/f6/09f672…` 复制成 `libmpv-2.dll`，用 `--dll` 指过去（不要覆盖工作区里的指针文件）。

## 4. 源清单

表里的“实测”是两轮的 `ttfp（从 loadfile 到首个 time-pos 的耗时）/ adv（播放推进秒数）`（直播还有 20 秒后的再推进量）。
`ttfp` 取自轮询循环每轮开头的时刻，会偏小，最多约 0.25 秒（跑得快的源会显示成 0ms），只能当量级参考，别拿它当首帧耗时指标。完整地址、备选地址、出处页都在 JSON 里。
大多数点播样本只有 10–50 秒，只够验证“能播”，不适合做长时间稳定性。

### 4.1 点播：封装与编码

| id | 类别 | 地址 | 容器 | 编码 | 分辨率 | 码率 | 实测 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `mp4-h264-tv360` | vod-mp4-h264-faststart | `https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_1…` | mov | h264 | 640x360 | 792 kbps | r1 ttfp=0ms adv=3.0s / r2 ttfp=0ms adv=3.0s |
| `mp4-h264-tv1080` | vod-mp4-h264-faststart | `https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080…` | mov | h264 | 1920x1080 | 8387 kbps | r1 ttfp=0ms adv=3.03s / r2 ttfp=0ms adv=3.03s |
| `mp4-h264-mdn` | vod-mp4-h264-faststart | `https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4` | mov | h264/aac | 960x540 | 1785 kbps | r1 ttfp=194ms adv=3.0s / r2 ttfp=218ms adv=3.0s |
| `mp4-h264-faststart-vjs` | vod-mp4-h264-faststart | `https://vjs.zencdn.net/v/oceans.mp4` | mov | h264/aac | 960x400 | 3949 kbps | r1 ttfp=83ms adv=3.0s / r2 ttfp=77ms adv=3.0s |
| `mp4-h264-faststart-mejs` | vod-mp4-h264-faststart | `https://raw.githubusercontent.com/mediaelement/mediaelement-files/master/big_…` | mov | h264/aac | 640x360 | 733 kbps | r1 ttfp=113ms adv=3.0s / r2 ttfp=65ms adv=3.0s |
| `mp4-h264-moovend-blender` | vod-mp4-h264-moov-at-end | `https://download.blender.org/durian/trailer/sintel_trailer-480p.mp4` | mov | h264/aac | 854x480 | 669 kbps | r1 ttfp=791ms adv=3.04s / r2 ttfp=571ms adv=3.04s |
| `mp4-h264-moovend-w3c` | vod-mp4-h264-moov-at-end | `https://media.w3.org/2010/05/sintel/trailer.mp4` | mov | h264/aac | 854x480 | 669 kbps | r1 ttfp=174ms adv=3.04s / r2 ttfp=108ms adv=3.04s |
| `mp4-h264-moovend-w3s` | vod-mp4-h264-moov-at-end | `https://www.w3schools.com/html/mov_bbb.mp4` | mov | h264/aac | 320x176 | 629 kbps | r1 ttfp=408ms adv=3.08s / r2 ttfp=246ms adv=3.04s |
| `mp4-h264-moovend-samplelib` | vod-mp4-h264-moov-at-end | `https://download.samplelib.com/mp4/sample-10s.mp4` | mov | h264/aac | 1920x1080 | 4295 kbps | r1 ttfp=2762ms adv=3.0s / r2 ttfp=2775ms adv=3.0s |
| `mp4-h264-jf1080` | vod-mp4-h264-moov-at-end | `https://repo.jellyfin.org/test-videos/SDR/AVC/Test Jellyfin 1080p AVC 3M.mp4` | mov | h264 | 1920x1080 | 3018 kbps | r1 ttfp=2329ms adv=3.02s / r2 ttfp=2347ms adv=3.18s |
| `mp4-hevc-tv1080` | vod-mp4-hevc | `https://test-videos.co.uk/vids/bigbuckbunny/mp4/h265/1080/Big_Buck_Bunny_1080…` | mov | hevc | 1920x1080 | 8438 kbps | r1 ttfp=0ms adv=3.1s / r2 ttfp=0ms adv=3.0s |
| `mp4-hevc-jf1080` | vod-mp4-hevc | `https://repo.jellyfin.org/test-videos/SDR/HEVC 8bit/Test Jellyfin 1080p HEVC …` | mov | hevc | 1920x1080 | 3021 kbps | r1 ttfp=2073ms adv=3.13s / r2 ttfp=2070ms adv=3.03s |
| `mp4-hevc10-jf1080` | vod-mp4-hevc-10bit | `https://repo.jellyfin.org/test-videos/SDR/HEVC 10bit/Test Jellyfin 1080p HEVC…` | mov | hevc | 1920x1080 | 3020 kbps | r1 ttfp=2363ms adv=3.02s / r2 ttfp=2076ms adv=3.03s |
| `mp4-hevc-hdr10-jf` | vod-mp4-hevc-hdr10 | `https://repo.jellyfin.org/test-videos/HDR/HDR10/HEVC/Test Jellyfin 1080p HEVC…` | mov | hevc | 1920x1080 | 3018 kbps | r1 ttfp=2079ms adv=3.22s / r2 ttfp=2330ms adv=3.23s |
| `mkv-tv-jelly` | vod-mkv-h264 | `https://test-videos.co.uk/vids/jellyfish/mkv/1080/Jellyfish_1080_10s_10MB.mkv` | mkv | h264 | 1920x1080 | 8368 kbps | r1 ttfp=0ms adv=3.07s / r2 ttfp=0ms adv=3.03s |
| `mkv-fs720` | vod-mkv-h264 | `https://filesamples.com/samples/video/mkv/sample_1280x720.mkv` | mkv | h264 | 1280x720 | - | r1 ttfp=103ms adv=3.04s / r2 ttfp=57ms adv=3.0s |
| `mkv-h264-eac3-ffs` | vod-mkv-h264-eac3 | `https://samples.ffmpeg.org/Matroska/H264+EAC3.mkv` | mkv | h264/eac3 | 1280x528 | 4951 kbps | r1 ttfp=3485ms adv=3.09s / r2 ttfp=3561ms adv=3.09s |
| `webm-vp9-tv1080` | vod-webm-vp9 | `https://test-videos.co.uk/vids/bigbuckbunny/webm/vp9/1080/Big_Buck_Bunny_1080…` | mkv | vp9 | 1920x1080 | 8432 kbps | r1 ttfp=0ms adv=3.03s / r2 ttfp=0ms adv=3.0s |
| `webm-vp9-fs720` | vod-webm-vp9 | `https://filesamples.com/samples/video/webm/sample_1280x720.webm` | mkv | vp9 | 1280x720 | - | r1 ttfp=83ms adv=3.0s / r2 ttfp=62ms adv=3.04s |
| `vod-wm-vp9-1080` | vod-webm-vp9 | `https://upload.wikimedia.org/wikipedia/commons/transcoded/c/c0/Big_Buck_Bunny…` | mkv | vp9/opus | 1920x1080 | 3787 kbps | r1 ttfp=279ms adv=3.07s / r2 ttfp=266ms adv=3.05s |
| `av1-mp4-tv1080` | vod-av1-mp4 | `https://test-videos.co.uk/vids/bigbuckbunny/mp4/av1/1080/Big_Buck_Bunny_1080_…` | mov | av1 | 1920x1080 | 8389 kbps | r1 ttfp=0ms adv=3.03s / r2 ttfp=0ms adv=3.03s |
| `av1-mp4-jf1080` | vod-av1-mp4-10bit | `https://repo.jellyfin.org/test-videos/SDR/AV1/Test Jellyfin 1080p AV1 10bit 3…` | mov | av1 | 1920x1080 | 2995 kbps | r1 ttfp=2087ms adv=3.02s / r2 ttfp=2087ms adv=3.08s |
| `av1-webm-tv1080` | vod-av1-webm | `https://test-videos.co.uk/vids/bigbuckbunny/webm/av1/1080/Big_Buck_Bunny_1080…` | mkv | av1 | 1920x1080 | 8389 kbps | r1 ttfp=1ms adv=3.07s / r2 ttfp=0ms adv=3.03s |
| `ts-fs720` | vod-mpegts | `https://filesamples.com/samples/video/ts/sample_1280x720.ts` | mpegts | mpeg2video | 1280x720 | - | r1 ttfp=0ms adv=3.0s / r2 ttfp=0ms adv=3.0s |
| `ts-fs-surf` | vod-mpegts | `https://filesamples.com/samples/video/ts/sample_1280x720_surfing_with_audio.ts` | mpegts | mpeg2video | 1280x720 | 384 kbps | r1 ttfp=202ms adv=3.01s / r2 ttfp=157ms adv=3.22s |
| `m2ts-fs720` | vod-mpegts-m2ts | `https://filesamples.com/samples/video/m2ts/sample_1280x720.m2ts` | mpegts | mpeg2video | 1280x720 | - | r1 ttfp=0ms adv=3.04s / r2 ttfp=0ms adv=3.04s |
| `flv-h264-ffsamples` | vod-flv-h264 | `https://samples.ffmpeg.org/FLV/Enigma_Principles_of_Lust-part.flv` | flv | h264/aac | 426x240 | 19 kbps | r1 ttfp=1163ms adv=3.17s / r2 ttfp=1090ms adv=3.17s |
| `mov-aac-ffsamples` | vod-mov-audio | `https://samples.ffmpeg.org/mov/aacaudio.mov` | mov | aac | - | 40 kbps | r1 ttfp=1769ms adv=3.25s / r2 ttfp=1527ms adv=3.02s |
| `vod-hb-tv1080-30mb` | vod-highbitrate-h264 | `https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080…` | mov | h264 | 1920x1080 | 24563 kbps | r1 ttfp=0ms adv=3.03s / r2 ttfp=0ms adv=3.03s |
| `vod-hb-tv-hevc-30mb` | vod-highbitrate-hevc | `https://test-videos.co.uk/vids/bigbuckbunny/mp4/h265/1080/Big_Buck_Bunny_1080…` | mov | hevc | 1920x1080 | 25169 kbps | r1 ttfp=0ms adv=3.0s / r2 ttfp=0ms adv=3.0s |
| `vod-hb-tv-av1-30mb` | vod-highbitrate-av1 | `https://test-videos.co.uk/vids/bigbuckbunny/mp4/av1/1080/Big_Buck_Bunny_1080_…` | mov | av1 | 1920x1080 | 25215 kbps | r1 ttfp=0ms adv=3.03s / r2 ttfp=0ms adv=3.0s |
| `vod-hb-tv-vp9-30mb` | vod-highbitrate-vp9 | `https://test-videos.co.uk/vids/bigbuckbunny/webm/vp9/1080/Big_Buck_Bunny_1080…` | mkv | vp9 | 1920x1080 | 25206 kbps | r1 ttfp=0ms adv=3.03s / r2 ttfp=0ms adv=3.07s |

### 4.2 点播：纯音频

| id | 类别 | 地址 | 容器 | 编码 | 分辨率 | 码率 | 实测 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `mp3-fs1` | vod-audio-mp3 | `https://filesamples.com/samples/audio/mp3/sample1.mp3` | mp3 | mp3 | - | 128 kbps | r1 ttfp=127ms adv=3.23s / r2 ttfp=71ms adv=3.22s |
| `mp3-soundhelix` | vod-audio-mp3 | `https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3` | mp3 | mp3 | - | 192 kbps | r1 ttfp=864ms adv=3.25s / r2 ttfp=862ms adv=3.01s |
| `aac-fs1` | vod-audio-aac-adts | `https://filesamples.com/samples/audio/aac/sample1.aac` | aac | aac | - | 127 kbps | r1 ttfp=93ms adv=3.22s / r2 ttfp=87ms adv=3.21s |
| `m4a-ffsamples` | vod-audio-m4a | `https://samples.ffmpeg.org/mov/audio_with_still.m4a` | mov | aac | - | 130 kbps | r1 ttfp=6650ms adv=3.14s / r2 ttfp=6614ms adv=3.13s |
| `flac-fs1` | vod-audio-flac | `https://filesamples.com/samples/audio/flac/sample1.flac` | flac | flac | - | - | r1 ttfp=69ms adv=3.21s / r2 ttfp=55ms adv=3.16s |
| `ogg-fs1` | vod-audio-ogg-vorbis | `https://filesamples.com/samples/audio/ogg/sample1.ogg` | ogg | vorbis | - | 112 kbps | r1 ttfp=87ms adv=3.21s / r2 ttfp=55ms adv=3.21s |
| `ogg-vorbis-ffs-coyote` | vod-audio-ogg-vorbis | `https://samples.ffmpeg.org/ogg/Vorbis/coyote.ogg` | ogg | vorbis | - | 160 kbps | r1 ttfp=4104ms adv=3.23s / r2 ttfp=4236ms adv=3.23s |
| `opus-fs1` | vod-audio-opus | `https://filesamples.com/samples/audio/opus/sample1.opus` | ogg | opus | - | - | r1 ttfp=65ms adv=3.21s / r2 ttfp=68ms adv=3.26s |
| `wav-fs1` | vod-audio-wav | `https://filesamples.com/samples/audio/wav/sample1.wav` | wav | pcm_s16le | - | 1411 kbps | r1 ttfp=126ms adv=3.17s / r2 ttfp=130ms adv=3.16s |
| `ac3-fs1` | vod-audio-ac3 | `https://filesamples.com/samples/audio/ac3/sample1.ac3` | ac3 | ac3 | - | 192 kbps | r1 ttfp=91ms adv=3.21s / r2 ttfp=59ms adv=3.21s |

### 4.3 点播：HLS（TS / fMP4 / 多码率 / AES-128 / 多音轨与字幕 / 纯音频）

| id | 类别 | 地址 | 容器 | 编码 | 分辨率 | 码率 | 实测 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `hls-ts-apple-16x9` | vod-hls-ts-master | `https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipb…` | hls | h264/aac | 1920x1080 | - | r1 ttfp=15197ms adv=3.17s / r2 ttfp=2634ms adv=3.0s |
| `hls-ts-mux-arte` | vod-hls-ts-master | `https://test-streams.mux.dev/test_001/stream.m3u8` | hls | h264/aac | 640x360 | - | r1 ttfp=1004ms adv=3.0s / r2 ttfp=904ms adv=3.04s |
| `hls-ts-jw-fdr` | vod-hls-ts-master | `https://cdn.jwplayer.com/manifests/pZxWPRg4.m3u8` | hls | h264/aac | 1920x1080 | - | r1 ttfp=696ms adv=3.05s / r2 ttfp=1134ms adv=3.05s |
| `hls-ts-mux-bbb` | vod-hls-ts-60fps | `https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8` | hls | h264/aac | 1920x1080 | - | r1 ttfp=520ms adv=3.05s / r2 ttfp=513ms adv=3.07s |
| `hls-fmp4-apple-adv` | vod-hls-fmp4 | `https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_e…` | hls | h264/aac | 1920x1080 | - | r1 ttfp=5374ms adv=3.14s / r2 ttfp=5245ms adv=3.14s |
| `hls-fmp4-shaka-angelone` | vod-hls-fmp4 | `https://storage.googleapis.com/shaka-demo-assets/angel-one-hls/hls.m3u8` | hls | h264/aac | 768x576 | - | r1 ttfp=16371ms adv=3.02s / r2 ttfp=14623ms adv=3.02s |
| `hls-fmp4-muxed-jw` | vod-hls-fmp4 | `https://s3.amazonaws.com/qa.jwplayer.com/hlsjs/muxed-fmp4/hls.m3u8` | hls | h264/aac | 1280x720 | - | r1 ttfp=6504ms adv=3.05s / r2 ttfp=6592ms adv=3.02s |
| `hls-fmp4-apple-hevc` | vod-hls-hevc | `https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_examp…` | hls | h264/aac | 1920x1080 | - | r1 ttfp=19307ms adv=3.21s / r2 ttfp=9782ms adv=3.21s |
| `hls-ts-hevc-devoldemar` | vod-hls-hevc | `https://devoldemar.github.io/streams/hls/bipbop/hevc.m3u8` | hls | hevc | 1920x1080 | - | r1 ttfp=5728ms adv=3.05s / r2 ttfp=6691ms adv=3.05s |
| `hls-aes128-oceans` | vod-hls-aes128 | `https://playertest.longtailvideo.com/adaptive/oceans_aes/oceans_aes.m3u8` | hls | h264/aac | 1264x528 | - | r1 ttfp=770ms adv=3.17s / r2 ttfp=707ms adv=3.09s |
| `hls-aes128-tracks` | vod-hls-aes128 | `https://playertest.longtailvideo.com/adaptive/aes-with-tracks/master.m3u8` | hls | h264/aac | 1280x720 | - | r1 ttfp=379ms adv=3.11s / r2 ttfp=281ms adv=3.11s |
| `hls-ts-apple-adv` | vod-hls-multi-audio-sub | `https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_e…` | hls | h264/aac | 1920x1080 | - | r1 ttfp=6795ms adv=3.11s / r2 ttfp=3786ms adv=3.21s |
| `hls-multi-sub-elephants` | vod-hls-multi-audio-sub | `https://playertest.longtailvideo.com/adaptive/elephants_dream_v4/index.m3u8` | hls | h264/aac | 1280x720 | - | r1 ttfp=648ms adv=3.08s / r2 ttfp=773ms adv=3.08s |
| `hls-audio-mp3` | vod-hls-audio-only | `https://playertest.longtailvideo.com/adaptive/vod-with-mp3/manifest.m3u8` | hls | h264/mp3 | 1280x720 | - | r1 ttfp=267ms adv=3.07s / r2 ttfp=199ms adv=3.07s |
| `hls-audio-alt-sintel` | vod-hls-audio-only | `https://playertest.longtailvideo.com/adaptive/alt-audio-no-video/sintel/playl…` | hls | aac | - | - | r1 ttfp=353ms adv=3.22s / r2 ttfp=214ms adv=3.21s |

### 4.4 点播：外挂字幕

脚本在播放通过后执行 `sub-add <url> select`，再等字幕轨出现。两种格式都被裁剪版正确识别。

| id | 类别 | 地址 | 字幕轨 | 实测 |
| --- | --- | --- | --- | --- |
| `sub-vtt-mdn` | vod-external-sub-webvtt | `https://interactive-examples.mdn.mozilla.net/media/cc0-videos/friday.mp4` | webvtt | r1 ttfp=202ms adv=3.03s / r2 ttfp=184ms adv=3.0s |
| `sub-srt-sintel` | vod-external-sub-srt | `https://media.w3.org/2010/05/sintel/trailer.mp4` | subrip | r1 ttfp=148ms adv=3.04s / r2 ttfp=125ms adv=3.04s |

### 4.5 反例（应被明确拒绝）

| id | 类别 | 地址 | 结果（两轮） |
| --- | --- | --- | --- |
| `rej-avi-fs720` | reject-avi | `https://filesamples.com/samples/video/avi/sample_1280x720.avi` | 拒绝(unrecognized file format, 261ms) ; 拒绝(unrecognized file format, 65ms) |
| `rej-wmv-fs720` | reject-wmv-asf | `https://filesamples.com/samples/video/wmv/sample_1280x720.wmv` | 拒绝(unrecognized file format, 259ms) ; 拒绝(unrecognized file format, 260ms) |
| `rej-mpg-fs720` | reject-mpeg-ps | `https://filesamples.com/samples/video/mpg/sample_1280x720.mpg` | 拒绝(unrecognized file format, 520ms) ; 拒绝(unrecognized file format, 59ms) |
| `rej-rm-fs` | reject-realmedia | `https://filesamples.com/samples/video/rm/sample_640x360.rm` | 拒绝(loading failed, 102ms) ; 拒绝(loading failed, 45ms) |
| `rej-ogv-fs720` | reject-ogv-theora | `https://filesamples.com/samples/video/ogv/sample_1280x720.ogv` | 拒绝(no audio or video data played, 111ms) ; 拒绝(no audio or video data played, 61ms) |
| `rej-wma-fs1` | reject-audio-wma | `https://filesamples.com/samples/audio/wma/sample1.wma` | 拒绝(unrecognized file format, 252ms) ; 拒绝(unrecognized file format, 259ms) |
| `webm-vp8-tv1080` | reject-webm-vp8 | `https://test-videos.co.uk/vids/bigbuckbunny/webm/vp8/1080/Big_Buck_Bunny_1080…` | 拒绝(no audio or video data played, 99ms) ; 拒绝(no audio or video data played, 71ms) |
| `hevc-raw-fs720` | reject-raw-hevc-es | `https://filesamples.com/samples/video/hevc/sample_1280x720.hevc` | 拒绝(unrecognized file format, 778ms) ; 拒绝(unrecognized file format, 776ms) |
| `rej-dash-akamai` | reject-dash-mpd | `https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd` | 拒绝(unrecognized file format, 0ms) ; 拒绝(unrecognized file format, 0ms) |
| `rej-dash-shaka` | reject-dash-mpd | `https://storage.googleapis.com/shaka-demo-assets/angel-one/dash.mpd` | 拒绝(unrecognized file format, 263ms) ; 拒绝(unrecognized file format, 256ms) |
| `rej-dash-livesim-vod` | reject-dash-mpd | `https://livesim2.dashif.org/vod/testpic_2s/Manifest.mpd` | 拒绝(unrecognized file format, 780ms) ; 拒绝(unrecognized file format, 772ms) |
| `rej-rtsp-wowza` | reject-rtsp | `rtsp://wowzaec2demo.streamlock.net/vod/mp4:BigBuckBunny_115k.mp4` | 拒绝(loading failed, 1ms) ; 拒绝(loading failed, 1ms) |
| `rej-flv1-zelda` | reject-flv-flv1 | `https://samples.ffmpeg.org/FLV/zelda.flv` | 拒绝(no audio or video data played, 6397ms) ; 拒绝(no audio or video data played, 7068ms) |
| `rej-svq1-mov` | reject-mov-svq1 | `https://samples.ffmpeg.org/mov/NNM3022_LiquidArmor_ISDN.mov` | 拒绝(no audio or video data played, 1202ms) ; 拒绝(no audio or video data played, 1859ms) |

### 4.6 直播：HLS

“窗口”是第一个变体的播放列表里所有分片时长之和，可以当作 DVR/时移窗口的粗略参考；`LL` 表示播放列表里有 `EXT-X-PART`（低延迟 HLS）。
窗口较大的有 DW（约 30 分钟，适合验证时移）、Unified Streaming（约 10 分钟）。

| id | 类别 | 地址 | 编码 | 分辨率 | 窗口 | 实测 |
| --- | --- | --- | --- | --- | --- | --- |
| `live-hls-mux-ll` | live-hls-low-latency | `https://stream.mux.com/v69RSHhFelSm4701snP22dYz2jICy4E4FUyk02rW4gxRM.m3u8` | h264/aac | 1920x1080 | 窗口 20s LL | r1 ttfp=6265ms adv=23.22s live+20.17s / r2 ttfp=6005ms adv=23.09s live+20.08s |
| `live-hls-dw` | live-hls-multi | `https://dwamdstream102.akamaized.net/hls/live/2015525/dwstream102/index.m3u8` | h264/aac | 1920x1080 | 窗口 1800s | r1 ttfp=6294ms adv=23.24s live+20.2s / r2 ttfp=2376ms adv=23.28s live+20.22s |
| `live-hls-dw-es` | live-hls-multi | `https://dwamdstream104.akamaized.net/hls/live/2015530/dwstream104/master.m3u8` | h264/aac | 1920x1080 | 窗口 1800s | r1 ttfp=20532ms adv=23.3s live+20.24s / r2 ttfp=20660ms adv=23.28s live+20.22s |
| `live-hls-france24-en` | live-hls-multi | `https://live.france24.com/hls/live/2037218-b/F24_EN_HI_HLS/master_5000.m3u8` | h264/aac | 1920x1080 | 窗口 100s | r1 ttfp=738ms adv=23.28s live+20.24s / r2 ttfp=393ms adv=23.28s live+20.24s |
| `live-hls-nhk-japan` | live-hls-multi | `https://masterpl.hls.nhkworld.jp/hls/w/live/smarttv.m3u8` | h264/aac | 1920x1080 | 窗口 36s | r1 ttfp=1708ms adv=23.26s live+20.19s / r2 ttfp=1816ms adv=23.19s live+20.15s |
| `live-hls-nhk-premium` | live-hls-multi | `https://media-tyo.hls.nhkworld.jp/hls/wp/live/master.m3u8` | h264/aac | 1280x720 | 窗口 36s | r1 ttfp=2723ms adv=23.35s live+20.15s / r2 ttfp=3162ms adv=23.16s live+20.05s |
| `live-hls-aje-apps` | live-hls-multi | `https://live-hls-apps-aje-fa.getaj.net/AJE/index.m3u8` | h264/aac | 1920x1080 | 窗口 36s | r1 ttfp=12531ms adv=23.24s live+20.2s / r2 ttfp=11650ms adv=23.28s live+20.24s |
| `live-hls-arirang` | live-hls-multi | `https://amdlive-ch01-ctnd-com.akamaized.net/arirang_1ch/smil:arirang_1ch.smil…` | h264/aac | 1920x1080 | 窗口 6s | r1 ttfp=5777ms adv=27.44s live+24.26s / r2 ttfp=5259ms adv=23.22s live+20.19s |
| `live-hls-redbull` | live-hls-multi | `https://rbmn-live.akamaized.net/hls/live/590964/BoRB-AT/master.m3u8` | h264/aac | 1920x1080 | 窗口 180s | r1 ttfp=4102ms adv=23.27s live+20.23s / r2 ttfp=3651ms adv=23.23s live+20.2s |
| `live-hls-bloomberg-us` | live-hls-multi | `https://bloomberg.com/media-manifest/streams/us.m3u8` | h264/aac | 1280x720 | 窗口 50s | r1 ttfp=4259ms adv=23.22s live+20.22s / r2 ttfp=3207ms adv=23.41s live+20.22s |
| `live-hls-unified-scte35` | live-hls-fmp4 | `https://demo.unified-streaming.com/k8s/live/stable/scte35.isml/.m3u8` | h264/aac | 1280x720 | 窗口 599s | r1 ttfp=7063ms adv=23.24s live+20.2s / r2 ttfp=6953ms adv=23.24s live+20.2s |
| `live-hls-amagi-dw-en` | live-hls-single | `https://amg01644-amg01644c1-amgplt0343.playout.now3.amagi.tv/ts-eu-w1-n2/play…` | h264/aac | 1920x1080 | 窗口 60s | r1 ttfp=13057ms adv=23.28s live+20.24s / r2 ttfp=12898ms adv=23.28s live+20.2s |
| `live-hls-skynews-ar` | live-hls-single | `https://live-stream.skynewsarabia.com/c-horizontal-channel/horizontal-stream/…` | h264/aac | 1920x1080 | 窗口 60s | r1 ttfp=5518ms adv=23.12s live+19.96s / r2 ttfp=4242ms adv=23.4s live+20.24s |
| `live-hls-arirang-http` | live-hls-http-plain | `http://amdlive-ch01.ctnd.com.edgesuite.net/arirang_1ch/smil:arirang_1ch.smil/…` | h264/aac | 1920x1080 | 窗口 6s | r1 ttfp=1898ms adv=23.24s live+20.22s / r2 ttfp=3300ms adv=25.13s live+22.12s |

### 4.7 直播：网络电台（Icecast/SHOUTcast 与 HLS 音频）

| id | 类别 | 地址 | 容器 | 编码 | 实测 |
| --- | --- | --- | --- | --- | --- |
| `radio-mp3-rp` | live-radio-mp3 | `https://stream.radioparadise.com/mp3-192` | mp3 | mp3 | r1 ttfp=306ms adv=23.02s live+20.0s / r2 ttfp=293ms adv=23.51s live+20.26s |
| `radio-mp3-somafm` | live-radio-mp3 | `https://ice1.somafm.com/groovesalad-128-mp3` | mp3 | mp3 | r1 ttfp=902ms adv=23.05s live+20.05s / r2 ttfp=848ms adv=23.1s live+20.09s |
| `radio-mp3-kexp` | live-radio-mp3 | `https://kexp-mp3-128.streamguys1.com/kexp128.mp3` | mp3 | mp3 | r1 ttfp=2401ms adv=23.05s live+20.04s / r2 ttfp=2483ms adv=23.02s live+20.02s |
| `radio-mp3-npr` | live-radio-mp3 | `https://npr-ice.streamguys1.com/live.mp3` | mp3 | mp3 | r1 ttfp=1052ms adv=23.02s live+20.02s / r2 ttfp=1106ms adv=23.04s live+20.04s |
| `radio-mp3-bbcws` | live-radio-mp3 | `https://stream.live.vc.bbcmedia.co.uk/bbc_world_service` | mp3 | mp3 | r1 ttfp=3680ms adv=21.67s live+18.67s / r2 ttfp=1783ms adv=23.11s live+20.11s |
| `radio-mp3-rfr` | live-radio-mp3 | `https://icecast.radiofrance.fr/franceinter-midfi.mp3` | mp3 | mp3 | r1 ttfp=1278ms adv=23.26s live+20.24s / r2 ttfp=1220ms adv=23.05s live+20.05s |
| `radio-mp3-dlf` | live-radio-mp3 | `https://st01.sslstream.dlf.de/dlf/01/128/mp3/stream.mp3` | mp3 | mp3 | r1 ttfp=2234ms adv=23.28s live+20.03s / r2 ttfp=2192ms adv=23.04s live+20.03s |
| `radio-aac-rp` | live-radio-aac | `https://stream.radioparadise.com/aac-320` | aac | aac | r1 ttfp=313ms adv=23.0s live+19.99s / r2 ttfp=317ms adv=23.01s live+20.01s |
| `radio-aac-somafm` | live-radio-aac | `https://ice1.somafm.com/groovesalad-128-aac` | aac | aac | r1 ttfp=918ms adv=23.08s live+20.07s / r2 ttfp=933ms adv=23.01s live+20.01s |
| `radio-aac-rfr` | live-radio-aac | `https://icecast.radiofrance.fr/franceinter-hifi.aac` | aac | aac | r1 ttfp=1442ms adv=23.32s live+20.07s / r2 ttfp=1253ms adv=23.01s live+20.01s |
| `radio-flac-rp` | live-radio-flac | `https://stream.radioparadise.com/flac` | ogg | flac | r1 ttfp=333ms adv=3396274.57s live+20.23s / r2 ttfp=365ms adv=3396686.01s live+20.18s |
| `radio-opus-listenmoe` | live-radio-ogg-opus | `https://listen.moe/opus` | ogg | opus | r1 ttfp=395ms adv=23.22s live+20.19s / r2 ttfp=561ms adv=23.23s live+20.23s |
| `radio-hls-rfr` | live-radio-hls-audio | `https://stream.radiofrance.fr/franceinter/franceinter.m3u8?id=radiofrance` | hls | aac | r1 ttfp=2536ms adv=23.01s live+19.99s / r2 ttfp=2617ms adv=23.5s live+20.24s |

## 5. 实测发现（对 mova 有用的部分）

1. **moov 在文件尾的 MP4/MOV，在不支持 Range 的服务器上播不了。** `filesamples.com`（Cloudflare/Ezoic，回 200 分块、无 `Content-Length`、无 `Accept-Ranges`）上的
   `sample_*.mp4/.mov/.m4a/.3gp` 全部报 `Cannot seek backward in linear streams! … partial file`，而同样 moov 在尾、但服务器支持 Range 的源
   （Blender、W3C、w3schools、samplelib、Jellyfin）都能播。完整版 `ffprobe` 对这些文件反而能读出元数据，所以别拿 ffprobe 结果当可播依据。
   结论：线上要是遇到“MP4 偶尔播不了”，先查源站是否支持 Range 和 moov 位置，别急着怀疑解码。
2. **不支持的视频编码 + 支持的音频 = 静默只出声，不报错。** `FLV/asian-commercials-are-weird.flv`（VP6 + MP3）与 Wikimedia 的 `Big_Buck_Bunny_4K.webm`
   （VP8 + Vorbis）都会正常推进 `time-pos`、只有日志里一句 `Failed to initialize a decoder for codec 'vp8'`，`state.error` 不会有。
   所以脚本的通过判据里加了“有视频流就必须解出画面”，这种源不能只看 `time-pos`。
3. **RTMP 不受协议白名单约束。** 用 ffmpeg 在本机回环起一个 RTMP 服务（`-f flv -listen 1 rtmp://127.0.0.1:19350/live/t`），裁剪版 libmpv 在 mova 默认白名单
   （不含 `rtmp`）和加上 `rtmp` 两种配置下都能播（H.264+AAC，推进 23 秒）。原因：顶层 URL 由 mpv 自己的 stream 层打开，`demuxer-lavf-o` 的白名单只约束
   demuxer 内部再打开的嵌套协议（比如 HLS 分片）。这条是本机回环结果，不是线上源。
4. **Windows Schannel 有间歇性握手/解密失败。**
   - `tls: Unable to decrypt message (error 0x80090330)`：下载 `filesamples.com` 的大文件时偶发，同一个 `.ts` 样本一次能播一次失败。
   - `tls: Failed to read handshake response`：`pl.streamingvideoprovider.com` 的 HLS（播放列表本身用 curl 的 Schannel 能取到、完整版 ffprobe 也能读），裁剪版稳定复现失败，已从清单里剔除。
   - `0x80090326`（TLS 致命告警）：`tv-trtworld.live.trt.com.tr`，curl 也连不上，更像目标服务器的问题。
   - 这些都是 Windows 版 n9 自带 Schannel 的表现；Android 用 mbedtls，**没验证**是否同样受影响。
5. **CDN 速度决定“能不能测”。** Apple `devstreaming-cdn` 到本机很慢，首个 `time-pos` 要 5–21 秒（仍在 25 秒上限内）；Jellyfin 的测试仓库只有约 200KB/s，所以它的 4K（40–100 Mbps）一个也播不动，这是带宽问题不是解码问题。
   `test-videos.co.uk` 的 CDN 约 7.8MB/s，高码率（1080p 30MB/10s ≈ 24 Mbps）的 H.264/HEVC/AV1/VP9 都能轻松通过。
6. **HLS 里夹的字幕轨不影响播放。** Apple 的 adv 示例带 `eia_608` 字幕，裁剪版没有该解码器，只在日志里报 `Could not find subtitle decoder for format 'eia_608'`，音视频照常播。
7. **低延迟 HLS（LL-HLS）可播。** Mux 的 LL-HLS 测试流（`EXT-X-PART`，fMP4 分片）两轮都稳定推进。

## 6. 没找到可用源的格子 / 被剔除的候选

| 格子 | 情况 |
| --- | --- |
| 线上 RTMP / RTMPS 直播 | 试了 iptv-org 里的 6 个 `rtmp://` 地址（台湾公视 CTS、香港卫视等），**全部在握手阶段被重置**（`Error number -10054`，完整版 ffprobe 同样失败）。同一台机器上 HTTPS 都正常，推测是本机网络拦了 1935 端口或这些源已失效，**无法区分**。只做了本机回环验证（见第 5 节第 3 条）。 |
| HTTP-FLV 直播 | 唯一找到的公开源是阿根廷圣胡安国立大学的 `https://srs.unsj.edu.ar/live/xama/xama.flv`（H.264+AAC 720p，能解码），但两次实测 20 秒只推进 7.8 秒和 10.0 秒（源端限速或带宽不够），**不稳定，没收**。SRS 官方 demo（`ossrs.net:8080`、`d.ossrs.net`）连不上/域名不存在。H.264 的 FLV **点播**有（`flv-h264-ffsamples`）。 |
| 第二个低延迟 HLS | 只有 Mux 一个。Apple 的 `ll-hls-test.apple.com`（TS 与 CMAF 两个）已 404，Akamai 的 `cph-p2p-msl` 测试流 404。 |
| 4K 点播 | Jellyfin 4K 带宽不够（见上）；FFmpeg 样本库的 `4khdr/PE2_Leopard_4K.mkv`（HEVC 4K，含 DTS 音轨与 PGS 字幕）加载后 10 秒内 `time-pos` 不推进（原因未深究，可能与 DTS/PGS 轨有关）；Apple 4K HLS 25 秒内没出首个 `time-pos`；Wikimedia 的 VP9 2160p 转码文件第一轮单测通过，但在最终两轮里都被 **429 限流**，剔除。 |
| 120fps 点播 | FFmpeg 样本库那个 120fps MKV 的视频是 mpeg4，不可解。已有的高帧率是 60fps（Mux HLS，`hls-ts-mux-bbb`）。 |
| Ogg Vorbis 电台 | Radio Paradise 的 `ogg-128` 已 404；点播的 Ogg Vorbis 有（`ogg-fs1`、`ogg-vorbis-ffs-coyote`），电台只有 Ogg Opus（listen.moe）。 |
| H.264 的 `.mov` 点播 | 没找到支持 Range 的 H.264 `.mov`（filesamples 的 `.mov` 无 Range 播不了）。MOV 容器只用 `mov-aac-ffsamples`（QuickTime 音频）覆盖；H.264 的 `.mp4` 与 `.mov` 走同一个 `mov` demuxer。 |
| 失效/不可用的候选 | `ll-hls-test.apple.com`（404）、`cph-p2p-msl.akamaized.net`（404）、NASA TV 的 `ntv1/ntv2.akamaized.net`（主列表有，子列表 404）、France24 旧地址（子列表 400，新地址可用）、CBS News/ABC News Live（子列表 404 或无数据）、`nhkwlive-ojp.akamaized.net`（域名不解析，新地址 `masterpl.hls.nhkworld.jp` 可用）、`live-hls-web-aje.getaj.net`（域名不解析，`live-hls-apps-aje-fa.getaj.net` 可用）、`live.cgtn.com`（CGTN 变体域名无解析）、`bitdash-a/bitmovin-a.akamaihd.net`（403）、`sample-videos.com`（返回非媒体内容）。 |

## 7. 本机访问不了的域名

- **没有新增需要写进 `blocked-domains.md` 的域名。** 上面所有“解析失败”的主机，用本机 DNS、`8.8.8.8`、`1.1.1.1` 三处结果一致，是源端真的下线，不是本机被拦。
- `curl` 在这台机器上对几乎所有 HTTPS 站点都先报 `schannel … CRYPT_E_NO_REVOCATION_CHECK (0x80092012)`，需要加 `--ssl-no-revoke`。
  这和 `blocked-domains.md` 里 `shutterstock.com` 的 “curl 直连 exit 35（SSL 握手失败）” 很像：我用 `--ssl-no-revoke` 复测它返回的是 403（服务器拒绝），不是握手失败，
  那条记录可能是同一个吊销检查问题，值得复核（没改那个文件）。
- 限流而不是封锁：`upload.wikimedia.org` 连续请求会 429；`bitmovin` 系列对本机返回 403。

## 8. 使用注意

- **这些源随时可能下线**。跑真机/CI 前先用同一个脚本复测一遍（`--alternatives` 可以自动切备选）。直播类（尤其是新闻台）最容易换地址。
- 电视台与电台地址来自各机构官方的公开网页或播放器，iptv-org 清单只当作“找地址”的索引。**只用于开发测试，别在产品里内置。**
- Jellyfin 测试视频是 CC BY-SA 4.0；Blender 的 Sintel/Big Buck Bunny 是 CC BY；其余来自各厂商/开源项目的示例页，出处见 JSON 的 `source_page`。
- Windows 实测不能代表 Android：软解/硬解路径、TLS 实现、ac3/eac3、MPEG-2 视频都不同（第 2 节）。Android 复测请用同一份 JSON，把 `--dll` 换成设备侧的跑法需要另写脚本，这个脚本只在 Windows 上加载 dll。
- 高码率或 4K 源要看带宽：并发太高会互相挤占，复测 4K 时用 `--jobs 1`。
- 验证脚本只能说明“10 秒内能连续播放”，不能替代手势、PiP、转场、内存这些真机用例。
