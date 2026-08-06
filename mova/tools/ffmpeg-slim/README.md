# mova ffmpeg 瘦身构建配置（**✅ 二期任务完成（Android），目标扩展到 Flutter 全平台**）

「现代主流点播+直播格式 + 体积优先」的 ffmpeg 瘦身构建配置。对应遗留任务 #4（二期
ffmpeg 瘦身，见根 [CLAUDE.md](../../CLAUDE.md)，已在 [ROADMAP.md](../../doc/ROADMAP.md)
标记完成）。**"完成"指 Android arm64-v8a 定稿+接入+核心解码路径真机验证**——其余
ABI/平台、字幕/截图/HLS-FLV/avfilter回归/后台中断/AV1高码率场景这几项仍是本文件下方
明确跟踪的 TODO，不是"全平台全功能都验证完毕"。

**目标已从"移动端优先"扩展为 Flutter 全平台**（Android/iOS/macOS/Windows/Linux）——
`media_kit_libs_video` 聚合包本来就依赖全平台的 `media_kit_libs_*_video` 子包，是否
瘦身、瘦几个平台是分平台独立决策，不影响 `mova/pubspec.yaml` 继续用聚合包（详见下方
"多平台进度"一节的结论）。**当前只有 Android arm64-v8a 真正跑通并有实测数据**，其余
平台是设计中的 TODO，见下表。

## 多平台进度

| 平台 | 状态 | 说明 |
|---|---|---|
| Android arm64-v8a | ✅ 已定稿并接入 mova 工程 | 6.55MiB（AV1 硬解+软解双通道，2026-08-06 真机复测后改判），见下方"定稿结果"，真机播放验证进行中 |
| Android armeabi-v7a / x86 / x86_64 | ⬜ 未开始 | 同一套 flavor 脚本理论上可复用，`--disable-runtime-cpudetect` 那条 arm64 专属优化不能照搬（见"关键单项发现"第 4 条），需要各自重新实测体积 |
| iOS | ⬜ 未开始 | 构建链是 `media-kit/libmpv-ios-video-build`（不是 Android 那个仓库），需要 macOS 运行器；MediaCodec 硬解概念不适用，iOS 走 VideoToolbox，取舍逻辑要重新过一遍 |
| macOS | ⬜ 未开始 | 构建链是 `media-kit/libmpv-macos-video-build`，同样需要 macOS 运行器 |
| Windows | ⬜ 未开始 | 构建链是 `media-kit/libmpv-win32-build`，历史 Windows spike（见文首链接）只做了推算，没有真实构建 |
| Linux | ⬜ 未开始 | 构建链是 `media-kit/libmpv-linux-build` |

**关键差异提醒**：Android 这份 flavor 脚本里 `--enable-mediacodec`/`--enable-jni` 是
Android 专属硬解路径，其他平台各自有自己的硬解 API（iOS/macOS 是 VideoToolbox，Windows
是 D3D11VA/DXVA2，Linux 是 VDPAU/VAAPI），**不能直接照搬 flavor 脚本，只有 DECODERS/
DEMUXERS/PROTOCOLS/BSFS 这些格式支持范围的清单是可以跨平台复用的部分**，硬解相关的
`--enable-*`/`--disable-*` 每个平台要重新对着该平台的 ffmpeg configure 选项表过一遍。

**本终稿的数据来自 Android arm64-v8a 真机构建链实测**，不是 Windows 推算。历史 Windows
spike 过程与数据见 [../../doc/plans/2026-07-31-ffmpeg-slim-build-windows.md](../../doc/plans/2026-07-31-ffmpeg-slim-build-windows.md)，
组件取舍依据见 [../../doc/notes/2026-07-31-ffmpeg-slimming-options.md](../../doc/notes/2026-07-31-ffmpeg-slimming-options.md)。

## ⭐ 2026-08-06 定稿结果（在下面"实测结果"一节基础上继续深挖）

在 WSL2 Ubuntu 上把完整链路（NDK 下载→源码 clone→patch→构建→strip→符号核验）走了一遍
真实的 `media-kit/libmpv-android-video-build` 构建，并在此基础上叠加了 6 项进一步瘦身
手段，逐项实测（不是理论估算）：

| 阶段 | 体积 | 相对 media_kit 现状（11.80MiB）| 相对上一阶段 |
|---|---:|---:|---:|
| 完整格式终稿（下节的 7.97MiB 版本） | 8.90 MiB | −25% | — |
| 去掉 VP8 软解 + VP9 软解（只留 `vp9_mediacodec` 硬解） | 8.23 MiB | −30% | −667 KB |
| + `-Wl,--gc-sections` / `-ffunction-sections -fdata-sections` | 8.18 MiB | −31% | −54 KB（收益很小，符合"ffmpeg 已经拆得很细"的预期） |
| + `-Os`（meson `buildtype=minsize`，作用于 dav1d/freetype/fribidi/harfbuzz/mpv） | 7.84 MiB | −34% | −348 KB |
| + `-fvisibility=hidden`（**单项收益最大**，导出符号从 4692 个砍到 610 个） | 7.19 MiB | −39% | **−669 KB** |
| + 全链路 LTO（ffmpeg+dav1d+freetype+harfbuzz+libass+mpv 一起做，**fribidi 除外**） | 6.68 MiB | −43% | −521 KB |
| + 去掉 `overlay`/`equalizer` 两个 avfilter（**未过真机播放验证**） | 6.61 MiB (6,931,744 B) | −44% | −70 KB |
| + 去掉 VP8/MJPEG/AV1 全部软解 + `webm_dash_manifest` 之外的多余项清理 | 5.87 MiB (6,157,264 B) | −50% | −774 KB |
| + 加回 `av1_mediacodec`（AV1 硬解） | 5.87 MiB (6,158,976 B) | −50.3% | +1.7 KB |
| + 加回 `libdav1d`（AV1 软解，见下方"改判"）**（定稿）** | **6.55 MiB (6,862,416 B)** | **−44.5%** | +671 KB |

**最终决策（2026-08-06 真机复测后改判）：AV1 硬解 + 软解都留**（`av1_mediacodec` 优先，
`libdav1d` 兜底）。原判断是"仅留硬解，跟不上硬解的老机型/冷门 profile 接受播放失败"，
参照 VP9 的取舍逻辑；但拿到真机（STG-AL00，骁龙 bengal 档，Android 12，**现在仍在售的
入门/中低端档位，不是老旧淘汰机型**）实测后翻车："Could not open codec."——AV1 硬解
电路目前只在中高端以上 SoC 才配，入门芯片覆盖不到的比例比预期高，不是"少数冷门老机型"
这么窄。软解实测 CPU 87%~180%（多核）、内存多涨 70~90MB，8 秒低码率 720p 短片没有明显
卡顿，但高码率/长视频场景没测，大概率更吃力、更耗电——**接受这个代价，因为播放失败比
卡顿/耗电更糟**。VP9 保留仅硬解不变：VP9 硬解在 Android 7.0+ 覆盖率明显好于 AV1，
目前没有类似真机翻车证据推翻原判断。

**最终产物**：[`dist/arm64-v8a/libmpv.so`](dist/arm64-v8a/libmpv.so)（**6.55MiB，
6,862,416 字节**）。
**最终 flavor 脚本**：[`flavors-mova-slim.sh`](flavors-mova-slim.sh)（cp 到
`buildscripts/scripts/ffmpeg.sh` 使用，见下文"出真正的 Android 产物"）。
**buildscripts 本身需要的补丁**：[`libmpv-android-video-build.patch`](libmpv-android-video-build.patch)
（`build.sh` + 7 个 `scripts/*.sh`，见下文"进一步瘦身需要的 buildscripts 补丁"一节）。

**验证过关的**：`mpv_lavc_set_java_vm` 符号在（硬解 JavaVM 绑定正常）、
`h264_mediacodec_decoder`/`hevc_mediacodec_decoder`/`vp9_mediacodec_decoder`/
`av1_mediacodec_decoder` 四个硬解符号均在、`dav1d` 符号回归（AV1 软解）、
VP8/MJPEG 相关符号确认消失。**真机验证进展**：H.264/HEVC/VP9 硬解、AV1 硬解失败
后软解兜底成功，均已在 STG-AL00 上过；字幕渲染/截图/HLS-FLV 直播/avfilter 回归
（`FILTERS=""` 去掉 `overlay`/`equalizer` 后 OSD/字幕合成有没有受影响）/后台中断
恢复这五项仍未测，详见下方"真机测试"一节。

### 支持的视频编码格式（解码）

| 编码 | 硬解 | 软解 | 说明 |
|---|---|---|---|
| H.264/AVC | ✅ `h264_mediacodec` | ✅ `h264` | 双通道保留——CDD 强制硬解，但 profile/level/并发会话/畸形流等边缘场景仍需软解兜底 |
| HEVC/H.265 | ✅ `hevc_mediacodec` | ✅ `hevc` | 双通道保留——硬解覆盖率约 65%，非 CDD 强制，软解兜底面更大 |
| VP9 | ✅ `vp9_mediacodec` | ❌ | 仅硬解——2016+/Android 7.0+ SoC 基本覆盖，取舍：不支持硬解的设备/内容直接播放失败 |
| AV1 | ✅ `av1_mediacodec` | ✅ `libdav1d` | 双通道保留——硬解优先，入门/中低端 SoC（如骁龙 bengal 档）常年缺 AV1 硬解，真机实测直接播放失败，故加回软解兜底（2026-08-06 改判，见上方决策说明） |
| PNG | ✅（编解码器层，非 mediacodec） | ✅ `png` | 封面图/截图用途保留 |
| VP8 | ❌ | ❌ | 完全砍掉——遗留格式，无 mediacodec 硬解封装，已被 VP9/AV1 取代 |
| MJPEG | ❌ | ❌ | 完全砍掉——PNG 已覆盖封面图/截图场景 |
| 其它（MPEG-2/4 Part2、WMV、RealVideo 等） | ❌ | ❌ | 未在"现代主流点播+直播"范围内，未启用 |

### 支持的容器/封装格式（demuxer）

| 格式 | 支持 | 说明 |
|---|---|---|
| MP4/MOV | ✅ `mov` | 点播主流容器 |
| Matroska/WebM | ✅ `matroska` | 含 WebM |
| MPEG-TS | ✅ `mpegts` | 直播/广电常见 |
| HLS (m3u8) | ✅ `hls` | 直播/点播分片协议 |
| FLV（含 `live_flv`） | ✅ `flv`,`live_flv` | 国内直播平台常用，用户明确要求保留 |
| 纯音频容器（MP3/FLAC/OGG/WAV/AAC/AC3/EAC3） | ✅ | 配合对应音频解码器 |
| 字幕容器（ASS/SRT/WebVTT） | ✅ `ass`,`srt`,`webvtt` | 外挂字幕 |
| `webm_dash_manifest` | ✅（demuxer 保留，见下方说明） | 见下方"DASH 澄清" |
| DASH（MPD 清单/自适应码流调度） | ⚠️ 见下方澄清 | 不是独立编解码器/muxer，见说明 |
| RTSP | ❌ | 早期规划保留、当前 flavor 未启用协议/demuxer，如需摄像头场景要单独加回 |
| AVI/WMV/RM 等传统容器 | ❌ | 不在"现代主流"范围 |

**DASH 澄清**：DASH（Dynamic Adaptive Streaming over HTTP）本身是一套"清单+分片调度"
协议，不是编解码器也不是单一 muxer 格式，因此"硬解/软解"这个维度对它不适用——它调度的
分片通常是 fMP4（走 `mov` demuxer）。当前 flavor 里的 `webm_dash_manifest` 只是
"WebM 容器内嵌 DASH 清单"这一种特定组合的 demuxer，不代表通用 DASH（比如 MPD+fMP4）
支持——如果要完整支持主流 DASH 点播源，还需要额外的 MPD 清单解析逻辑（ffmpeg 侧一般靠
`--enable-libxml2` 完整 DASH demuxer，当前未启用）。**结论：当前构建对"完整 DASH"
不算支持，只是保留了 WebM+DASH 这一窄组合的 demuxer，作为已知取舍点记录，不建议
依赖它。**

### AV1 软解 / MJPEG 的实测取舍数据（2026-08-06 补测，AV1 结论已改判）

定稿后又实测了两个被砍掉能力"如果加回来要多花多少体积"，作为取舍依据存档：

| 加回项 | 体积 | 相对定稿版（5.87MiB / 6,158,976 B） |
|---|---:|---:|
| + AV1 软解（`libdav1d`，硬解 `av1_mediacodec` 继续保留） | 6.55 MiB (6,862,416 B) | **+671 KB（约 +11%）** |
| + MJPEG 解码 | 5.94 MiB (6,228,272 B) | **+68 KB** |

**结论：AV1 软解加回，MJPEG 维持不加**。

- **AV1 软解改判为加回**：最初判断"触发场景窄（老旧模拟器/冷门 profile/2023 年前老
  机型）"被真机数据打破——STG-AL00（骁龙 bengal 档，Android 12，当前仍在售的入门/
  中低端档位）实测直接 "Could not open codec."，说明覆盖不到 AV1 硬解的不是"少数冷门
  老机型"，而是整个入门芯片档位，比例比预期高得多。软解实测 CPU 87%~180%、内存多涨
  70~90MB（8 秒低码率 720p 短片，未测高码率/长视频场景），代价接受：播放失败比软解
  卡顿/耗电更糟。
- **MJPEG 不加回**：+68KB 代价虽然小，但 PNG 编解码器已经覆盖封面图/截图场景，MJPEG
  在当前"现代主流点播+直播"场景里没有增量必要性——单纯因为便宜而加回属于"没有需求
  driven"的功能蔓延，不做。

踩坑记录：第一次测 AV1 软解时用 `--enable-decoder=av1` 完全没效果（体积只涨 1.7KB），
因为 `av1` 在 ffmpeg 里只是 parser 名字，真正的软解码器要写 `--enable-decoder=libdav1d`
才会被链接进去——ffmpeg 的 decoder/parser 命名不总是一一对应，改配置时不能想当然。

### 关键单项发现

1. **LTO 对"ffmpeg 单独"收益有限（网上通用结论），但对"ffmpeg+dav1d+freetype+
   harfbuzz+libass+mpv 一起做全链路 LTO"收益不小**（−521KB）——跨库死代码消除/内联
   的机会比单一大型 C 项目内部更多。**不要直接信通用结论，自己测**。
2. **`-fvisibility=hidden` 是所有单项里收益最大的**（−669KB）——各依赖库内部符号默认
   都是"外部可见"的动态符号，白占 `.dynsym`/`.dynstr`，还挡了链接器的死代码消除。
   mpv 自己的公开 API 靠 `MPV_EXPORT` 宏显式标记 `visibility("default")`，全局转
   `hidden` 不会误伤。
3. **LTO 在 meson 交叉编译下有个坑**：`b_lto=true` 写在 cross file 的
   `[built-in options]` 里会泄漏到"宿主机原生工具"（比如 fribidi 自己在构建期跑的
   `gen-unicode-version` 码表生成器），导致普通系统链接器处理不了 LTO 位码报
   `undefined symbol: main`。修法是显式提供 `--native-file` 把 `b_lto` 在宿主机侧
   关掉；fribidi 即使这样还是不行，只能在它自己的 `meson setup` 命令行单独加
   `-Db_lto=false` 覆盖。dav1d/freetype/harfbuzz/mpv 都不受影响。
4. **`--disable-runtime-cpudetect` 在 arm64 上实测零效果**——NEON 在 AArch64 基线
   架构里是强制项，`--cpu=armv8-a` 已经让 ffmpeg 编译期就认定 NEON 存在，运行时
   探测开关本身没有可消除的分发代码。**不建议在其他架构（armv7l/x86/x86_64）
   上照抄这个开关**，那些架构上 NEON/AVX2 不是强制项，关掉有真实崩溃风险。
5. **APK 打包不会帮你省这块体积**——现代 Android（AGP 3.6+/App Bundle 默认）要求
   原生库 `extractNativeLibs=false`，也就是 APK 里必须"不压缩存储"直接 mmap，
   6.61MiB 是要全额算进安装包体积的实际数字，压缩红利基本拿不到。
6. **ijkplayer（业界最常参考的移动端 ffmpeg 瘦身样本）没有做到这么细**——它的
   `module-lite.sh` 只做了 `--disable-everything` + 精选 decoder/demuxer，没有
   `gc-sections`/`-fvisibility=hidden`/`-Os`/跨库 LTO 这些编译器/链接器级别手段。

### 进一步瘦身需要的 buildscripts 补丁

上面 6 项手段里，第 3 项之后都不是 `flavors-mova-slim.sh` 这一个文件能控制的
（改的是 `libmpv-android-video-build` 仓库自己的 `build.sh` 和各依赖的
`scripts/*.sh`）。这些改动打包在 [`libmpv-android-video-build.patch`](libmpv-android-video-build.patch)
里，克隆好 `libmpv-android-video-build` 之后 `git apply` 一下即可：

```bash
git clone https://github.com/media-kit/libmpv-android-video-build
cd libmpv-android-video-build
git apply /path/to/mova/tools/ffmpeg-slim/libmpv-android-video-build.patch
```

补丁内容一览：
- `build.sh`：`loadarch()` 的 `LDFLAGS` 加 `--gc-sections`；`setup_prefix()` 的
  meson crossfile 加 `buildtype=minsize`/`b_lto=true`/`c_args`/`c_link_args`；
  新增 `native.txt`（`b_lto=false`，给宿主机原生工具用）
- `scripts/{dav1d,freetype,harfbuzz,mpv}.sh`：`meson setup` 加
  `--native-file native.txt`
- `scripts/fribidi.sh`：额外加 `-Db_lto=false` 命令行覆盖（native-file 对它不够）
- `scripts/{libass,libxml2,mbedtls}.sh`：CFLAGS 从裸 `-fPIC` 换成完整的
  `-fPIC -Os -ffunction-sections -fdata-sections -fvisibility=hidden -flto
  -fomit-frame-pointer`（这仨走的是 autotools/make，不吃 meson crossfile）

## 是什么

`configure-ffmpeg-slim.sh`：一个 ffmpeg `configure` 封装，产出**只保留现代主流点播+直播
格式、纯解码（除一个 png 编码器）、体积优先、LGPL** 的 ffmpeg。目标是移动端
（Android/iOS）；**桌面端明确不在考虑范围内**。

⚠️ **这是独立的宿主机验证脚本，不是实际出货配置**——下面这份格式列表是它自己的默认值，
用来在宿主机上快速验证"这套解码器/demuxer/协议组合能不能编译成立"（见下文"出真正的
Android 产物"一节的用法）。**mova 实际接入的产物走的是 [`flavors-mova-slim.sh`](flavors-mova-slim.sh)**，
格式范围不完全一样——VP8/MJPEG 在那份里被砍掉了，AV1 是硬解+软解双通道（不是这里写的
纯 `libdav1d`）。真实产物的格式表见上方"支持的视频编码格式（解码）"一节，不要看这份就
以为是最终产物的格式范围。

**`configure-ffmpeg-slim.sh` 自己默认支持的格式**：

- 视频：H.264 / H.265(HEVC) / VP9 / AV1（走 libdav1d）/ VP8；Android 上另有
  MediaCodec 硬解（h264/hevc/vp8/vp9/av1）
- 音频：AAC(+LATM) / MP3 / Opus / AC-3 / E-AC-3 / FLAC / Vorbis / PCM
- 字幕：ASS/SSA / SubRip / WebVTT / mov_text（内封）+ 外挂 .ass/.srt/.vtt
- 封面图：MJPEG / PNG（attached picture）
- 容器：MP4 全家桶 / MKV / WebM / MPEG-TS / **HLS** / **FLV（含直播）** / 裸音频流
- 协议：file/fd/pipe/data、http(s)/tls、**HLS AES-128 加密分片**、
  **RTMP 全家（直播）**、UDP/RTP（IPTV 组播）
- **不含**：DASH、RTSP、rtmpe/rtmpte、一切封装器（muxer）、除 png 外的一切编码器、
  一切老旧格式（AVI/ASF/RM/WMV/MPEG-1/2/4/Xvid/Theora/VP6/H.263/DVD/蓝光/
  Real/ATRAC/APE/TAK/DSD/DTS…）

## 实测结果（Android arm64-v8a，真机构建链）

构建链：`media-kit/libmpv-android-video-build @1ecf510` + ffmpeg 6.0 + NDK r25c
（clang 14.0.7）+ mpv `78d4374`。ffmpeg **静态链入 libmpv.so**，体积为
`llvm-strip --strip-all` 之后的单个 `libmpv.so`。

| 配置 | 体积 | 相对 media_kit 现状 |
|---|---:|---:|
| `full`（全 decoder/demuxer/parser，-O3） | 16,111,168 B（15.37 MiB） | +30.2% |
| `default`（**media_kit 现在实际发布的**） | 12,369,664 B（11.80 MiB） | 基线 |
| **终稿（本配置）** | **8,356,744 B（7.97 MiB）** | **−4,012,920 B / −32.4%** |

组件数（`llvm-nm` 数据符号实测，非估算）：

| 配置 | decoder | encoder | muxer | demuxer | parser | protocol | bsf |
|---|---:|---:|---:|---:|---:|---:|---:|
| `full` | 507 | 7 | 0 | 346 | 58 | 22 | 41 |
| `default` | 147 | 6 | 0 | 74 | 18 | 22 | 41 |
| **终稿** | **33** | **2** | **0** | **20** | **14** | **18** | **13** |

> 历史参考（Windows/x86，仅 ffmpeg 7 个共享库，与上表不可直接比）：完整版 -O3 = 29.8 MB，
> 主流瘦身 -O3 = 11.0 MB，主流瘦身 -Os = 6.26 MB。解码性能代价：480p H.264 多线程约慢 2%
> （单线程约 7%）。ARM+NEON 上汇编路径不受 `-Os` 影响，纯 C 路径仍需真机复测。

## 关键发现：瘦身收益不来自「去掉编码器」

media_kit 现在发布的 libmpv **本来就基本是纯解码**：

- **muxer = 0**：它的 flavor 传了 `--disable-muxers` 且从未再启用任何一个
  （`config.mak` 里连 `CONFIG_MOV_MUXER` 都没有，二进制里搜不到 `ff_*_muxer`）
- **encoder = 6**：`apng jpeg2000 jpegls ljpeg mjpeg png`，全是图像编码器，
  给 mpv 的 `screenshot` 用
- **decoder = 147** ← 体积全在这里

所以 32.4% 的收益来自**砍掉 115 个遗留解码器 + 54 个遗留 demuxer**，与编码器几乎无关。
「已经是纯解码所以没必要瘦身」这个推论不成立。

另一个反直觉点：终稿**加了** png 编码器和整套直播协议，却比同配置带 DASH 的版本**更小**
—— 因为去掉 `dash` demuxer 连带去掉了 `--enable-libxml2`，把 libxml2 约 740 KB 的静态库
整个甩出了产物。

## ⚠️ 自建时最容易踩的坑：必须先跑 `./patch.sh`

`media-kit/libmpv-android-video-build` 自带三个补丁，**官方 release 是带着它们构建的**：

```
patches/mpv/mpv_lavc_set_java_vm.patch      ← 关键
patches/ffmpeg/hls_mp4_seek.patch           ← HLS fMP4 seek 修复
patches/ffmpeg/dash_base_url_escape.patch
```

`download.sh` **不会**应用它们，`bundle_*.sh` 才会调 `./patch.sh`。漏掉的后果是一个
「看起来完全正常、视频也能播」的 `libmpv.so`，但 **MediaCodec 硬解永久静默关闭**：

1. ffmpeg 静态链入后没有独立 `libavcodec.so` 可 `dlopen`
2. media_kit 的 `AndroidHelper`（`android_helper.dart:29-95`）因此只能从 libmpv 找
   `mpv_lavc_set_java_vm`（正是该补丁新增的导出）
3. 符号缺失 → 抛 `UnsupportedError` → 被它自己的 `catch (_) {}` 吞掉 → JavaVM 永远
   设不进 libavcodec → 全程软解，且没有任何报错

核验：

```bash
llvm-nm -D --defined-only libmpv.so | grep mpv_lavc_set_java_vm
# 必须有输出；只有 av_jni_set_java_vm 是不够的
```

## 顺带修掉的三个上游 bug

`libmpv-android-video-build` 的三个依赖脚本在命令行硬写 `CFLAGS=-fPIC`，把环境里的
`CFLAGS` 整个顶掉：

| 脚本 | 上游实际优化级别 | 修复后 |
|---|---|---|
| `scripts/libass.sh` | **无 `-O`**（只有 `-fPIC`） | `-fPIC -Os …` |
| `scripts/libxml2.sh` | **无 `-O`**（只有 `-fPIC`） | `-fPIC -Os …` |
| `scripts/mbedtls.sh` | `-fPIC`（mbedtls Makefile 用 `?=` 设 `CFLAGS`，被命令行覆盖后连默认优化都没了） | `-fPIC -Os …` |

改成 `CFLAGS="-fPIC $CFLAGS"` 即可（对不设 `CFLAGS` 的原有 flavor 行为不变）。这一处
修复单独贡献了约 663 KB。

## 源码母版

| 组件 | 官方仓库 | 镜像（国内更快） | 版本 |
|---|---|---|---|
| ffmpeg | `https://git.ffmpeg.org/ffmpeg.git` | `https://github.com/FFmpeg/FFmpeg.git` | `n6.0`（media_kit 构建链锁定） |
| dav1d | `https://code.videolan.org/videolan/dav1d.git` | `https://github.com/videolan/dav1d.git` | `1.2.0` |
| mpv | `https://github.com/mpv-player/mpv.git` | — | `78d43740f52db817d98bcf24fb30a76ab6fa13ff` |
| 构建脚本 | `https://github.com/media-kit/libmpv-android-video-build` | — | `1ecf510` |

> `freetype` / `libxml2` 的官方仓库在 `gitlab.freedesktop.org` / `gitlab.gnome.org`，
> 国内拉取极慢；改用 GitHub 镜像 `github.com/freetype/freetype`、`github.com/GNOME/libxml2`
> （同 tag）可大幅提速。

## 与 media_kit 集成

### 替换预编译库的入口

`media_kit_libs_android_video` 在构建期下载写死版本的 jar 并校验 MD5
（`libs/android/media_kit_libs_android_video/android/build.gradle:61-64`）：

```gradle
["url": "https://github.com/media-kit/libmpv-android-video-build/releases/download/v1.1.7/default-arm64-v8a.jar",
 "md5": "83df25b61193af8fa815e373143ac9af", ...]
```

要换成自建瘦身版，就是 fork 这个 libs 包（或用 path override）把 url/md5 指向自己的 jar。
jar 结构是 `lib/<abi>/*.so`。

### 指定任意路径的 libmpv（动态加载）

media_kit 一等公民支持（`media_kit/lib/src/player/native/core/native_library.dart:32-46`）：

```dart
MediaKit.ensureInitialized(libmpv: '/data/user/0/<pkg>/files/libmpv.so');
// 也支持 LIBMPV_LIBRARY_PATH 环境变量
```

Android 上有三个约束：

1. **加载顺序**：`AndroidHelper.ensureInitialized()` 是按**裸 soname** 打开的
   （`DynamicLibrary.open('libmpv.so')`）。必须**先**用绝对路径加载一次
   （`System.load("/abs/.../libmpv.so")`），linker 按 SONAME 记入命名空间后，
   裸名 `dlopen` 才会命中同一个 handle
2. **`libmediakitandroidhelper.so` 仍须在 APK 内**，它提供
   `MediaKitAndroidHelperGetJavaVM` / `GetFilesDir` / `IsEmulator` / `GetAPILevel`
3. **Play 政策**：从自有服务器下载可执行原生代码违反 Google Play 的
   Device and Network Abuse 政策。合规路径是 **Play Feature Delivery**
   （dynamic feature module，原生库在 feature module 内是允许的）

### 优先级建议

1. **ABI split（App Bundle）** —— media_kit 默认下发 4 个 ABI。让每台设备只拿 1 份：
   `4 × 11.80 = 47 MB → 11.80 MB`，**6 倍收益，几乎零成本**
2. **换成本终稿** → 再到 7.97 MB（1.4 倍收益，已实测就绪）
3. **dynamic feature module** —— 只在还要再抠首装体积时考虑。它优化的是同一个轴
   （分发体积），代价是首启延迟 + 依赖 Play + 一套下载/校验/回滚逻辑。运行期内存两者
   都不解决也都不恶化：`.so` 是 mmap + 按需分页，用不到的解码器页面根本不会驻留

## 环境准备

核心依赖：C 编译器 + `nasm`（或 yasm）+ `make` + `pkg-config`。完整 Android 构建还需
`meson`/`ninja`/`cmake`/`autoconf`/`libtool`/`ragel` 与 Linux 版 NDK r25c。

- **Linux（Debian/Ubuntu）**：
  ```bash
  sudo apt install build-essential nasm yasm pkg-config git \
    meson ninja-build cmake autoconf automake libtool ragel unzip wget
  ```
- **Windows**：**不要在原生 Windows 上构建 Android 产物**。`buildscripts` 依赖
  `ln -s` 造扁平 sysroot、autotools 全套、meson 交叉 cross file，MSYS2 下逐项踩坑。
  用 WSL2（Ubuntu）—— 它就跑在同一台机器上，产物直接落到 Windows 盘。
  ⚠️ WSL2 默认内存可能被 `%USERPROFILE%\.wslconfig` 限死；`nproc` 却仍报满核数，
  ninja 开满并行会 OOM（`clang++: Killed`）。构建前确认 `free -m` 至少 8 GB。
- **macOS**：`brew install nasm pkg-config meson ninja cmake automake libtool`

⚠️ **`meson` 版本坑**：mpv 的构建脚本传 `--prefer-static`，这个 flag 只在较新的
meson 里才认识。Ubuntu 22.04（GitHub Actions `ubuntu-22.04` runner 的默认 apt 源）
的 `apt install meson` 版本太老，会报 `meson: error: unrecognized arguments:
--prefer-static` 直接失败。本仓库验证过能用的版本是 **1.3.2**（WSL2 Ubuntu 24.04 的
apt 默认版本）——版本不够新时改用 `pip3 install --user "meson==1.3.2"`，CI 里已经
这么做（见 [`../../.github/workflows/build-mova-libmpv.yml`](../../.github/workflows/build-mova-libmpv.yml)
的"Install build dependencies"步骤）。

## 用法

```bash
# 宿主机构建，只为验证组件集合能成立
./configure-ffmpeg-slim.sh /path/to/ffmpeg-src /path/to/out '-Os' --build

# Android arm64（交叉编译参数由调用方给；出真产物请走 buildscripts，见下）
EXTRA_CONFIGURE="--target-os=android --enable-cross-compile \
  --arch=aarch64 --cross-prefix=aarch64-linux-android- \
  --cc=aarch64-linux-android21-clang" \
./configure-ffmpeg-slim.sh /path/to/ffmpeg-src /path/to/out '-Os' \
  --android --with-dav1d --with-tls --build

# 零编码器（放弃截图功能）
./configure-ffmpeg-slim.sh /path/to/ffmpeg-src /path/to/out '-Os' --strict-decode
```

组件清单在脚本顶部的 `DECODERS_*`/`ENCODERS`/`PARSERS`/`DEMUXERS`/`PROTOCOLS`/`BSFS`/
`FILTERS` 变量里，按需增删。

## 出真正的 Android 产物

本脚本只 configure ffmpeg。mova 出货的是 **libmpv（ffmpeg 静态链在里面）**，
必须走 `libmpv-android-video-build`：

```bash
git clone https://github.com/media-kit/libmpv-android-video-build
cd libmpv-android-video-build
git apply /path/to/mova/tools/ffmpeg-slim/libmpv-android-video-build.patch   # ← gc-sections/-Os/LTO/visibility，见上文
cd buildscripts
# 1. ./include/download-sdk.sh           拉 NDK（sdkmanager 走这个很慢，见下方"环境准备"里的
#    直连下载技巧）；或手动把 NDK 25.2.9519653 放到 sdk/android-sdk-linux/ndk/25.2.9519653
# 2. ./include/download-deps.sh          拉源码
# 3. ./patch.sh                          ← 千万别漏，见上文
# 4. cp ../../mova/tools/ffmpeg-slim/flavors-mova-slim.sh scripts/ffmpeg.sh
# 5. ./build.sh --arch arm64 mpv
# 6. llvm-strip --strip-all prefix/arm64-v8a/usr/local/lib/libmpv.so
```

⚠️ `sdkmanager` 走官方源下载 NDK 实测极慢（约 0.12MB/s，531MB 的 NDK 要 1 小时+）。
更快的办法：直接 `wget https://dl.google.com/android/repository/android-ndk-r25c-linux.zip`
（同一版本，2-3MB/s），解压后把 `android-ndk-r25c/` 整个目录改名放到
`sdk/android-sdk-linux/ndk/25.2.9519653/`，跳过 `sdkmanager` 这一步（`platforms`/
`build-tools` 这两个 Android SDK 组件我们的 `.so`-only 产物流程用不到，可以不装）。

## CI：GitHub Actions 自动构建

[`.github/workflows/build-mova-libmpv.yml`](../../../.github/workflows/build-mova-libmpv.yml)
（monorepo 根）复刻了上面"出真正的 Android 产物"这一整套手动步骤，触发条件只有两类
文件变化（+ `workflow_dispatch` 手动触发），**不含真机播放验证**（CI 里没有设备）：

- `mova/tools/ffmpeg-slim/flavors-mova-slim.sh`（瘦身 flavor 配置）
- `mova/tools/ffmpeg-slim/libmpv-android-video-build.patch`（buildscripts 补丁）

构建产物落地到 `mova/tools/ffmpeg-slim/dist/arm64-v8a/libmpv.so`（CI 自动 commit push
回 main，`[skip ci]` 避免自触发），同时也作为 workflow artifact 保留 30 天。`libmpv-
android-video-build` 仓库本身固定 checkout 到本文档"实测结果"一节记录的 commit
（`1ecf510`），版本升级需要显式改 workflow 里的 `LIBMPV_BUILD_REF`，不会被上游新提交
静默带跑偏。

## 接入 mova 工程（Android，已完成）

`media_kit_libs_android_video` 会自带一份未瘦身的 `libmpv.so`（~11.8MiB），走 Gradle
jniLibs 合并时如果两份 `libmpv.so` 都在会直接报 merge 冲突。接入方式：

1. 把 `dist/arm64-v8a/libmpv.so` 放到目标 App 模块的
   `android/app/src/main/jniLibs/arm64-v8a/libmpv.so`（当前落地在
   [`example/android/app/src/main/jniLibs/arm64-v8a/libmpv.so`](../../example/android/app/src/main/jniLibs/arm64-v8a/libmpv.so)）。
2. App 模块 `build.gradle.kts` 加 `packaging { jniLibs { pickFirsts += "**/libmpv.so" } }`
   （见 [`example/android/app/build.gradle.kts`](../../example/android/app/build.gradle.kts)），
   让我们的版本赢过 `media_kit_libs_android_video` 合并进来的那份。
3. **只覆盖了 arm64-v8a**——armeabi-v7a/x86/x86_64 目前没有对应瘦身产物，这些 ABI 上
   `pickFirsts` 因为我们没有同名文件冲突，会自然回退用 `media_kit_libs_android_video`
   原版的 `.so`（未瘦身，但能跑，不会崩）。多架构瘦身构建是后续 TODO。
4. **真机播放验证尚未完成**——见下方"真机测试"。

## 真机测试（进行中）

- [x] 安装 `mova/example` 到真机——设备 STG-AL00（Huawei/Honor，Snapdragon "bengal"
      平台，即 SD460/662/680 档，Android 12），`arm64-v8a`。
- [x] 基础点播 H.264/mp4：正常起播，contain 适配正确。
- [x] HEVC 硬解：`Big_Buck_Bunny_720_10s_1MB.mp4`（test-videos.co.uk）正常起播，
      logcat 确认走 `OMX-VDEC-1080P` 硬解路径。
- [x] VP9 硬解：`Big_Buck_Bunny_720_10s_1MB.webm`（test-videos.co.uk）正常起播到片尾，
      logcat 确认走 `OMX.qcom.video.decoder.vp9`。
- [x] AV1 硬解：**此设备报 "Could not open codec."**——`bengal` 平台没有 AV1 硬解单元。
      第一版测试源（test-videos.co.uk 的 AV1 mp4）本身还有独立问题——探测阶段卡死转圈
      近 30 秒不报错、CPU 占满 212% 却没有任何 `OMX`/`ACodec` 日志，怀疑该文件 moov
      atom 不在文件头（非 fast-start），换成 `elysiatools.com` 的 AV1 样例后能在几秒内
      正常走到"打开硬解失败"的正常报错路径，验证了失败原因是硬解不可用而非卡死/网络
      问题。**结果导致改判**：原"仅硬解"决策被推翻，见上方"最终决策"一节。
- [x] AV1 软解兜底：把 `libdav1d` 加回后同一台设备（`libmpv-av1sw.so` / 现已合并为
      定稿 `dist/arm64-v8a/libmpv.so`）能正常软解播放 elysiatools 的 AV1 样例。
      8 秒 720p 低码率短片实测 CPU 87%~180%（多核）、RSS 内存比硬解多涨 70~90MB，
      肉眼无明显卡顿；**未测**高码率/长视频/1080p+ 场景，大概率更吃力，暂无数据。
- [ ] 字幕：ASS/SRT/WebVTT 外挂字幕 + mov_text 内封字幕渲染——未测，demo 里还没有带字幕的源
- [ ] 截图（png 编码器路径）——未测
- [ ] HLS/FLV 直播流起播——未测（demo 已有 HLS 源，FLV 无）
- [ ] **重点**：`FILTERS=""` 去掉 `overlay`/`equalizer` 之后，OSD、字幕合成、音量均衡
      是否有可感知回归——仍未针对性验证，上面测的都是纯视频轨，没有触发这两个 avfilter
      的路径
- [ ] 播放中翻后台/来电中断恢复——未测
- [ ] AV1 软解在高码率/长视频/1080p+ 场景下的 CPU/内存/发热/流畅度——上面只测了低码率
      短片，结论不能直接套用到真实业务内容

**下次接手**：三个新 demo 入口（`ffmpeg瘦身 · HEVC/VP9/AV1`）已加进
`example/lib/main.dart` 的 `_demos` 列表，真机上可直接点开测，不用再改代码找测试源
（AV1 那条标题写的是"硬解验证"，但现在硬解失败会自动落到软解，标题文案没同步改，
下次顺手改一下）。剩下要测的是字幕/截图/HLS-FLV/avfilter回归/后台中断/AV1软解高码率
这六项——建议先测 avfilter 回归（设计决策里唯一标"未验证"的功能性风险点，优先级
高于其余格式覆盖类检查）。

## 已知取舍与扩展点

- **LGPL → LGPLv3**：Android 必须 `--enable-mbedtls`（系统无 TLS 后端），而 mbedtls 3.x
  是 Apache-2.0/GPL-2.0 双授权，ffmpeg 归类为 version3，configure 会强制要求
  `--enable-version3`（不加直接报 `mbedtls is version3 and --enable-version3 is not specified`）。
  结果是 LGPLv3，不是 LGPLv2.1
- **`--disable-vulkan` 必加**：ffmpeg 会从 NDK sysroot 自动探测到 `vulkan.h`，但 NDK 没带
  `vulkan_beta.h`，`hwcontext_vulkan.c` 编译失败
- **截图功能**：靠 png 编码器。传 `--strict-decode` 会去掉它，`screenshot` 命令随之失效
- **DASH**：需要时加 `--enable-libxml2` + `DEMUXERS` 补 `,dash`，代价约 740 KB（libxml2 静态库）
- **RTSP**：需要时 `DEMUXERS` 补 `,rtsp`，但它会 select `rdt`，连带拖进 `rm`/`asf`/`ivr`/`kux`
- **AV1**：`av1_mediacodec` 硬解 + `libdav1d` 软解都留（+671KB，2026-08-06 真机翻车后
  改判加回，实测数据见上方"AV1 软解/MJPEG 的实测取舍数据"一节）。软解只能用
  libdav1d——ffmpeg 自带的 av1 解码器体积更大且在 arm64 上慢一个量级，不要用
- **VP8 已去掉**：老旧格式，早被 VP9/AV1 取代，且没有 mediacodec 硬解包装器，去掉几乎不
  影响现代点播/直播场景
- **VP9 只留硬解**（`vp9_mediacodec`，软解已去掉）：VP9 硬解在 2016 年后的 Android 机型上
  已接近普及（CDD 长期要求项），但**没有软解兜底**——模拟器、极老设备、冷门 profile 会
  直接播放失败而不是降级软解。这跟 H.264/HEVC 不一样：H.264 是 CDD 强制硬解、HEVC 反而
  只有约 65% 机型有硬解（无强制要求），**这两个的软解都不能动**
- **avfilter 的 `overlay`/`equalizer` 已去掉**（`FILTERS=""`）—— **尚未过真机播放验证**，
  上线前必须实测 OSD/字幕合成/音频均衡是否受影响
- **再往下压体积就是放弃功能**（不建议在无明确需求时动）：
  - 字体栈 libass+freetype+harfbuzz+fribidi 约 2 MB —— 放弃 ASS 特效字幕才能省
  - libdav1d 约 1.4 MB —— 赌 AV1 硬解才能省，老设备直接不能播
  - mbedtls+mbedcrypto 约 1.6 MB —— 把 https 交给 Dart/Kotlin 侧下载后喂 fd 才能省
- **`-Os` 的真实作用范围**：ffmpeg 侧 media_kit 上游本来就带 `--enable-small`（clang 下
  映射为 `-Oz`），所以 `-Os` 在 ffmpeg 上**没有增量收益**；增量来自 dav1d/freetype/
  fribidi/harfbuzz/mpv 从 `-O3` 降到 `-Os`，以及上面那三个上游压根没开优化的库
- **mpv 自身已经没有配置层面能再省的空间**：`libmpv.a` 链接前原始体积约 3.39MB（对比
  `libavcodec.a` 单独 23.47MB，ffmpeg 才是真正的大头）。mpv 的可选 meson feature
  （`libarchive`/`libbluray`/`lcms2`/`rubberband`/`zimg`/各桌面 GL 后端等）全部是
  `auto` 档位，而我们的依赖链根本没提供这些库，meson 探测不到就自动跳过——本来就是
  零成本，没有再关的空间。剩下的 mpv 核心代码（命令/属性系统、demux、OSD）是播放器
  基础架构，砍不动
- **LTO 通用结论不可全信**：网上"LTO 对 ffmpeg 收益有限"的结论是针对"ffmpeg 单独"场景；
  我们是 ffmpeg+dav1d+freetype+harfbuzz+libass+mpv 一起做**跨库全链路 LTO**，实测收益
  −521KB，不小。**通用结论要自己实测验证，不能直接套**
- **APK 打包对这块体积没有压缩红利**：现代 Android（AGP 3.6+/App Bundle 默认）强制
  `extractNativeLibs=false`，原生库必须在 APK 里"不压缩存储"直接 mmap，最终体积就是
  这个数字全额算进安装包，指望 deflate 压缩省一截是不现实的

## 已知的进一步优化方向（未做，标注原因）

- **native/cross LTO 分离目前是"绕过"而非"根治"**：`--native-file` 机制在 dav1d/
  freetype/harfbuzz/mpv 上生效，但 fribidi 自己构建期的 `gen-unicode-version` 等码表
  生成工具还是会被 `b_lto=true` 污染，只能在 `scripts/fribidi.sh` 单独传
  `-Db_lto=false` 硬覆盖。这是 meson 某些版本的已知行为不一致（cross file 的
  `[built-in options]` 泄漏到 native 编译），根治需要升级 meson 或等上游修复，
  没有花时间深挖
- **ffmpeg 的 `av_tx` 变换表**（`ff_tx_tab_16384_float` 等一系列，累计约 1MB）：这些是
  FFT 查找表，编译期静态生成、不是运行时按需生成，理论上能通过限制最大变换点数来砍，
  但需要改 ffmpeg 源码本身（不是 configure 开关能关的），风险和收益都需要重新评估，
  本次未做
- **多架构（armv7l/x86/x86_64）尚未构建**：目前只有 arm64-v8a 一个架构的实测数据；
  `--disable-runtime-cpudetect` 这类 arm64 专属优化**不能**照抄到其他架构（见上文）
