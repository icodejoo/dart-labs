# mova ffmpeg 瘦身构建配置（**✅ 二期任务完成（Android），目标扩展到 Flutter 全平台**）

「现代主流点播+直播格式 + 体积优先」的 ffmpeg 瘦身构建配置。对应遗留任务 #4（二期
ffmpeg 瘦身，见 mova 根 [CLAUDE.md](../mova/CLAUDE.md)，已在 [ROADMAP.md](../mova/doc/ROADMAP.md)
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
| Android arm64-v8a | ✅ 已定稿并接入 mova 工程 | 6.52MiB（AV1 硬解+软解双通道，2026-08-06 真机复测后改判，CI 复现构建），见下方"定稿结果"，真机播放验证进行中 |
| Android armeabi-v7a / x86 / x86_64 | ✅ CI 构建通过，未接入真机验证 | 同一套 flavor 脚本直接复用（`--disable-runtime-cpudetect` 已按架构条件判断，不用改），2026-08-06 CI 矩阵三个 ABI 全绿并核验 `dav1d_open` 符号；已接入 `example` 的 jniLibs，还没上真机测过 |
| iOS | 🟢 CI 跑通完整 libmpv，未接入/未真机 | `ios` job（`flavors-mova-slim-ios.sh` + 8 个依赖库 meson 交叉构建 + mpv + strip），v6 线（跟 Android 同版本线：ffmpeg 6.0 + mpv 0.36）。**2026-08-12 定稿数字：6,247,184 字节（≈5.96 MiB）**，`otool -L` 验证纯静态链接、零外部依赖泄漏，比 Android 6.52MiB 还小（VP9/AV1 无 VideoToolbox hwaccel 只能软解，反而省了硬解胶水代码；TLS 用系统 securetransport 不用 vendor mbedtls）。h264/hevc **无法**收窄成纯硬解、libass 字体栈**不建议**砍（架构性限制/投入产出比不划算，见下方"iOS 瘦身配置"一节和"字幕栈瘦身评估"一节的详细论证）。尚未接入 mova 工程、尚未做任何真机/模拟器播放验证。**曾有 `mova-libmpv-winbuild-zhangfly` 分支走 ffmpeg n9.0+mpv 0.41（v9 线）做过 CI 验证（10.15MiB），该分支已作废不用**，不可比、不要复用 |
| macOS | 🟡 CI 首次尝试中（v1，走另一套仓库） | `media-kit/libmpv-darwin-build`，Nix + 固定版本 Xcode，`macos-15` runner。v1 直接用上游自带的"video/default" flavor，未照搬瘦身清单 |
| Windows | ✅ 本地 MSYS2 构建链跑通，未接入/未真机 | 构建链改用 `media-kit/libmpv-win32-video-cmake`（`libmpv-win32-video-build` 已归档/不可用，切到其活跃后继仓库），MSYS2 ucrt64 原生 gcc 工具链（`SKIP_TOOLCHAIN=ON` 跳过从零构建交叉编译器）+ Ninja，x86_64。**2026-08-13 定稿数字：28,274,176 字节（≈26.97 MiB）**，strip 后，含 D3D11VA 硬解，`mpv`/`libmpv-2.dll`/头文件全部产出。**比 media-kit 官方发行版（35.99 MiB，同架构 x86_64）还小 −25%**，且官方版没有针对"现代主流点播+直播"做任何裁剪（完整 openssl+libssh+libsrt+完整 libplacebo/vulkan/shaderc）——这是比 Android(6.52MiB)/iOS(5.96MiB) 更合理的参照系，那两个平台架构完全不同（MediaCodec 独立硬解/VideoToolbox 系统 API），不背 GPU-next 渲染管线这种包袱，直接比"差 4-5 倍"没有意义。详见下方"Windows 瘦身构建"一节 |
| Linux | 🟢 CI 曾跑绿（run 31092096967，但产物**未带** `-Dgpl=false`，见下），2026-08-13 本地 WSL2 复现验证通过 | **media-kit 没有对应仓库**（早前假设的 `libmpv-linux-build` 不存在）——在 runner 本机原生构建 ffmpeg+mpv，不需要交叉编译；依赖走 apt 装现成的 `libass-dev`/`libfreetype6-dev` 等，不用像 Android 那样从源码build |

**关键差异提醒**：Android 这份 flavor 脚本里 `--enable-mediacodec`/`--enable-jni` 是
Android 专属硬解路径，其他平台各自有自己的硬解 API（iOS/macOS 是 VideoToolbox，Windows
是 D3D11VA/DXVA2，Linux 是 VDPAU/VAAPI），**不能直接照搬 flavor 脚本，只有 DECODERS/
DEMUXERS/PROTOCOLS/BSFS 这些格式支持范围的清单是可以跨平台复用的部分**，硬解相关的
`--enable-*`/`--disable-*` 每个平台要重新对着该平台的 ffmpeg configure 选项表过一遍。

**本终稿的数据来自 Android arm64-v8a 真机构建链实测**，不是 Windows 推算。历史 Windows
spike 过程与数据见 [doc/plans/2026-07-31-ffmpeg-slim-build-windows.md](doc/plans/2026-07-31-ffmpeg-slim-build-windows.md)，
组件取舍依据见 [doc/notes/2026-07-31-ffmpeg-slimming-options.md](doc/notes/2026-07-31-ffmpeg-slimming-options.md)。

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
| + 加回 `libdav1d`（AV1 软解，见下方"改判"）**（定稿，CI 复现）** | **6.52 MiB (6,835,296 B)** | **−44.7%** | +671 KB（本地 WSL2 dry-run 测得，CI 正式产物略小 27KB，工具链/编译参数顺序的正常误差） |

**最终决策（2026-08-06 真机复测后改判）：AV1 硬解 + 软解都留**（`av1_mediacodec` 优先，
`libdav1d` 兜底）。原判断是"仅留硬解，跟不上硬解的老机型/冷门 profile 接受播放失败"，
参照 VP9 的取舍逻辑；但拿到真机（STG-AL00，骁龙 bengal 档，Android 12，**现在仍在售的
入门/中低端档位，不是老旧淘汰机型**）实测后翻车："Could not open codec."——AV1 硬解
电路目前只在中高端以上 SoC 才配，入门芯片覆盖不到的比例比预期高，不是"少数冷门老机型"
这么窄。软解实测 CPU 87%~180%（多核）、内存多涨 70~90MB，8 秒低码率 720p 短片没有明显
卡顿，但高码率/长视频场景没测，大概率更吃力、更耗电——**接受这个代价，因为播放失败比
卡顿/耗电更糟**。VP9 保留仅硬解不变：VP9 硬解在 Android 7.0+ 覆盖率明显好于 AV1，
目前没有类似真机翻车证据推翻原判断。

**最终产物**：[`dist/arm64-v8a/libmpv.so`](../mova/tools/ffmpeg-slim/dist/arm64-v8a/libmpv.so)（**6.52MiB，
6,835,296 字节，CI 构建产物，见下方"CI：GitHub Actions 自动构建"**）。

⚠️ **踩坑记录（2026-08-06）**：flavor 脚本里加 `libdav1d` 到 `DECODERS_VIDEO` **不够**——
ffmpeg 的 `--enable-decoder=libdav1d` 只声明"要这个解码器"，没有 `--enable-libdav1d`
（声明"要链接这个外部库"）时会被静默丢弃，**不报错**，编译/strip/符号校验全部通过，
只有产物体积明显偏小、`dav1d_*` 动态符号缺失才能发现。第一次 CI 跑就踩了这个坑
（产物 6,131,808 字节，比硬解单独版还小，`llvm-nm` 一查发现零 dav1d 符号）——本地
WSL2 dry-run 当时是用临时命令行手动加的 `--enable-libdav1d`，没同步进这份脚本文件，
两边跑的实际不是同一套配置。修复后 CI 重跑确认 19 个 `dav1d_*` 符号存在，产物体积符合
预期，这才是这份文档里"定稿"数字的来源。
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
| + AV1 软解（`libdav1d`，硬解 `av1_mediacodec` 继续保留） | 6.52 MiB (6,835,296 B，CI 复现构建) | **+671 KB（约 +11%，本地 WSL2 dry-run 测得）** |
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
git apply /path/to/mova-libmpv/libmpv-android-video-build.patch
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
这么做（见 [`../.github/workflows/build-mova-libmpv.yml`](../.github/workflows/build-mova-libmpv.yml)
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
git apply /path/to/mova-libmpv/libmpv-android-video-build.patch   # ← gc-sections/-Os/LTO/visibility，见上文
cd buildscripts
# 1. ./include/download-sdk.sh           拉 NDK（sdkmanager 走这个很慢，见下方"环境准备"里的
#    直连下载技巧）；或手动把 NDK 25.2.9519653 放到 sdk/android-sdk-linux/ndk/25.2.9519653
# 2. ./include/download-deps.sh          拉源码
# 3. ./patch.sh                          ← 千万别漏，见上文
# 4. cp ../../mova-libmpv/flavors-mova-slim.sh scripts/ffmpeg.sh
# 5. ./build.sh --arch arm64 mpv
# 6. llvm-strip --strip-all prefix/arm64-v8a/usr/local/lib/libmpv.so
```

⚠️ `sdkmanager` 走官方源下载 NDK 实测极慢（约 0.12MB/s，531MB 的 NDK 要 1 小时+）。
更快的办法：直接 `wget https://dl.google.com/android/repository/android-ndk-r25c-linux.zip`
（同一版本，2-3MB/s），解压后把 `android-ndk-r25c/` 整个目录改名放到
`sdk/android-sdk-linux/ndk/25.2.9519653/`，跳过 `sdkmanager` 这一步（`platforms`/
`build-tools` 这两个 Android SDK 组件我们的 `.so`-only 产物流程用不到，可以不装）。

## CI：GitHub Actions 自动构建

[`.github/workflows/build-mova-libmpv.yml`](../.github/workflows/build-mova-libmpv.yml)
（monorepo 根）复刻了上面"出真正的 Android 产物"这一整套手动步骤，触发条件只有两类
文件变化（+ `workflow_dispatch` 手动触发），**不含真机播放验证**（CI 里没有设备）：

- `mova-libmpv/flavors-mova-slim.sh`（瘦身 flavor 配置）
- `mova-libmpv/libmpv-android-video-build.patch`（buildscripts 补丁）

构建产物落地到 `mova/tools/ffmpeg-slim/dist/arm64-v8a/libmpv.so`（CI 自动 commit push
回 main，`[skip ci]` 避免自触发），同时也作为 workflow artifact 保留 30 天。`libmpv-
android-video-build` 仓库本身固定 checkout 到本文档"实测结果"一节记录的 commit
（`1ecf510`），版本升级需要显式改 workflow 里的 `LIBMPV_BUILD_REF`，不会被上游新提交
静默带跑偏。

## 接入 mova 工程（Android，已完成）

`media_kit_libs_android_video` 会自带一份未瘦身的 `libmpv.so`（~11.8MiB），走 Gradle
jniLibs 合并时如果两份 `libmpv.so` 都在会直接报 merge 冲突。接入方式：

1. 把 `mova/tools/ffmpeg-slim/dist/arm64-v8a/libmpv.so`（CI 构建产物落地位置，见上方
   "CI：GitHub Actions 自动构建"）放到目标 App 模块的
   `android/app/src/main/jniLibs/arm64-v8a/libmpv.so`（当前落地在
   [`example/android/app/src/main/jniLibs/arm64-v8a/libmpv.so`](../mova/example/android/app/src/main/jniLibs/arm64-v8a/libmpv.so)）。
2. App 模块 `build.gradle.kts` 加 `packaging { jniLibs { pickFirsts += "**/libmpv.so" } }`
   （见 [`example/android/app/build.gradle.kts`](../mova/example/android/app/build.gradle.kts)），
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

## iOS 瘦身配置（2026-08-12 更新：CI 已跑通完整 libmpv）

[`flavors-mova-slim-ios.sh`](flavors-mova-slim-ios.sh)（ffmpeg 层配置）+
`.github/workflows/build-mova-libmpv.yml` 的 `ios` job（依赖库交叉构建 + mpv
构建 + strip + 静态链接校验，v6 线，跟 main 分支的 ffmpeg 6.x/mpv 0.36 一致）：
decoder/demuxer/protocol/bsf 清单照搬 Android 那份定稿
（[`flavors-mova-slim.sh`](flavors-mova-slim.sh)），硬解从 MediaCodec 换成
VideoToolbox，TLS 用 iOS 系统自带的 securetransport（不像 Android 要额外
vendor mbedtls）。**CI 已跑通、有真实产物体积**，但**尚未接入 mova 工程、
未做任何真机/模拟器播放验证**——跟 Android 那份还差最后一步。

**产物**：`libmpv.dylib` 6,247,184 字节（≈5.96 MiB），`strip -S -x` 后（`-S`
清 DWARF 调试符号、`-x` 清不需要的全局符号；ffmpeg 侧配套加了
`--disable-debug`，meson cross file 加了 `debug = false`——ffmpeg 默认
`enable debug`、meson `minsize` buildtype 默认 `debug=true`，两处都会悄悄把
`-g` 编译进每个目标文件，之前只做 `strip -x` 没清干净，补上后从 6.86MiB→
5.99MiB→5.96MiB，最后这步只省了 32.5KB，收益不大但零风险，顺手做了），
`otool -L` 验证除系统框架（CoreText/CoreFoundation/VideoToolbox/CoreMedia/
CoreVideo/AudioToolbox）和系统自带 libiconv/libbz2/libz 外零外部依赖——
ffmpeg/dav1d/libass/freetype/harfbuzz/fribidi 全部静态链入这一个动态库，跟
Android"ffmpeg 静态链进 libmpv.so"是同一个形状。比 Android 定稿的 6.52MiB
还小（原因见下方"与 Android 的关键差异"）。

**依赖库交叉构建方法**：dav1d/freetype/fribidi/harfbuzz/libass/mpv 全部自带
meson 构建系统，**一份 meson cross file**（`c`/`cpp`/`objc` 都指向 `xcrun
--sdk iphoneos --find clang`，`-isysroot` 指向 iOS SDK，`b_lto=true` +
`buildtype=minsize` + `-fvisibility=hidden`/`-ffunction-sections`/
`-fdata-sections` 镜像 Android 的编译器/链接器手段）就能全部搞定——不需要
像 Android 那样依赖专门的 buildscripts 项目，比预想的容易。

**与 Android 的关键差异**：

- ffmpeg 的 VideoToolbox 支持是**hwaccel**，不是像 `h264_mediacodec` 那样的
  独立 decoder 名字——`--enable-videotoolbox --enable-hwaccels` 只是让已经
  启用的 h264/hevc **软解码器**在运行时有机会把帧交给 `VTDecompressionSession`。
  ffmpeg n6.0（v6 线锁定版本）对 VP9/AV1 完全没有 VideoToolbox hwaccel，所以
  vp9/av1 只能走软解——这是能力缺口，不是漏写；这也是 iOS 产物比 Android
  （VP9/AV1 都有硬解）更小的原因之一。
- **h264/hevc 无法像 Android 那样收窄成"纯硬解"，这是架构性的、不是保守
  策略，2026-08-12 已确认排查清楚，之后不要再花时间尝试**：
  - Android 的 MediaCodec 硬解在 ffmpeg 里是**完全独立的一份解码器实现**
    （`h264_mediacodec`）——整段码流直接丢给 Android 系统黑盒，NAL 解析和
    像素解码全部在黑盒内部完成，跟软解 `h264` decoder 毫无共享代码，所以
    能二选一、砍掉软解不影响硬解。
  - iOS 的 VideoToolbox 硬解**寄生在软解 decoder 内部**：ffmpeg 自己的
    `h264`/`hevc` decoder 负责解析 NAL/slice header、维护参考帧关系（这一步
    必须软件完成），只有"把压缩数据变成像素"这最后一步通过 hwaccel 回调
    转发给 `VTDecompressionSession`。软解代码和硬解调度是**同一份代码**，
    砍掉软解 decoder 会把硬解一并砍掉，没有"只留硬解"这个选项。
  - 更激进的做法（直接改 ffmpeg 源码，把 `libavcodec/h264*.c`/`hevc*.c`
    里纯像素解码的函数体〈IDCT/运动补偿/去块滤波/NEON 汇编〉物理删掉，只留
    解析+hwaccel 胶水代码）**技术上可能可行，但 2026-08-12 评估后决定不做**：
    没有 configure 开关能做到，得手动patch 源码、长期维护一份跟 ffmpeg 版本
    绑定的私有 fork；而且失败模式比 Android 更差——VideoToolbox 只要遇到
    解码会话超限/系统限流/冷门 SPS 组合等任何问题就会**完全无法播放**（没有
    软解退路），不像现在这样至少能优雅降级。投入产出比不划算，明确不做。

**已知未测项，真机上出问题时来这里查决策记录**：

- h264/hevc 双通道（硬解+软解都编进去了）——**从未真机验证**，如果发现某
  个机型/内容下硬解和软解都有问题，先看是不是 ffmpeg n6.0 的 VideoToolbox
  hwaccel 本身对某些 profile/level 支持不全，而不是当作"要不要收窄"的信号
  （上面已经论证过收窄在架构上做不到）。
- AV1/VP9 纯软解——ffmpeg n6.0 没有对应 hwaccel，如果真机测出功耗/发热问题，
  这是已知代价（跟 Android 加回 AV1 软解时的实测结论一致，见上方"AV1 软解
  / MJPEG 的实测取舍数据"一节），解法是升级 ffmpeg/mpv 版本线（等上游给
  VideoToolbox 加 VP9/AV1 hwaccel）或产品层面砍掉这两个格式，不是这份配置
  能单独解决的。
- securetransport 替换 mbedtls 后能否正常握手 HTTPS/HLS AES-128/RTMPS——
  CI 只验证了编译链接成功，实际网络握手行为未测。

**下一步**：接入 mova 工程（打包 xcframework 或直接 embed dylib）→ 真机/
模拟器播放验证（参照 Android 当初的验证清单逐项过：H.264/HEVC 硬解+软解、
AV1/VP9 软解、字幕、HLS/FLV 直播、HTTPS 握手、后台中断恢复）。**旧的
zhangfly 分支（ffmpeg n9.0+mpv 0.41 v9 线，CI 验证到 10.15MiB）已作废，
不要复用其代码或数据**——那条线版本号、依赖形态（libplacebo 强制依赖）都
跟这份 v6 线配置不同，不可比也不可直接抄。

## 字幕栈瘦身评估（2026-08-12，结论：不砍，libass 保留）

libass+freetype+harfbuzz+fribidi 这套字体栈占 iOS/Android 产物体积的一大块
（Android 估算约 2MB，接近 iOS 现在整个 libmpv 的三分之一）。用户提出"只要
基础字幕能力（纯文本+前景色/背景色/字号/位置，不要卡拉OK/动画特效），能不能
把这块砍掉换体积"，逐层论证下来，**结论是不砍**，记录完整推理链，避免以后
重新纠结同一个问题：

1. **"只删特效、留基础"在技术上不存在这个选项**。libass 没有编译开关能单独
   关闭 `\t`（动画过渡）/`\move`/`\p`（矢量绘图/卡拉OK）/`\blur`/`\clip` 这些
   标签的解释逻辑——它们是 `ass_render.c` 里的普通代码分支，不是可选
   feature。而且这些"特效代码"本身占的体积很小，**真正的大头是
   freetype+harfbuzz+fribidi 这套"渲染任何文字都要用到"的基础设施**（字体
   光栅化+文字整形+双向文字算法），画一行纯白字加背景色和画卡拉OK特效字幕
   走的是同一条流水线，前者省不掉后者的成本。手动 patch 源码物理删动画
   相关函数体，即使做成了也大概率只省几十 KB（相对整个 ~2MB 是九牛一毛），
   还要背负"长期维护一份手术过的 ffmpeg/libass 私有 fork"的代价，评估后
   明确不做。
2. **libass/fribidi/harfbuzz 这三者在 libass 0.17.3 源码里是硬依赖**
   （`meson.build` 里 `dependency('fribidi', ...)`/`dependency('harfbuzz', ...)`
   都没有 `required: get_option(...)`，没有开关能单独关掉其中一个），所以
   "留 libass 但去掉 harfbuzz/fribidi 换轻量文字整形"这条路也不存在。
3. **ffmpeg 的字幕 decoder 本身不做任何渲染**——它只是把不同字幕容器格式
   （SRT/WebVTT/ASS/mov_text）解析成统一的带标签文本（内部走 ASS 事件
   格式），颜色/背景/字号/位置的**解释和栅格化**全部是 libass 的工作。SRT
   格式本身没有这些概念（非标准的 `<font color>` 内联标签是唯一例外）；
   WebVTT 规范里确实有位置/基础颜色，但 ffmpeg 的 webvtt decoder 支持
   比较基础；ASS 的完整样式模型（`{\c\fs\pos...}` 覆写标签）由 libass 独家
   解释。这意味着如果真要砍掉 libass 改 Flutter 渲染，Dart 侧至少要写一个
   "极简 ASS 标签解释器"（认 `\c`/`\fs`/`\pos`/`\an`，忽略其余）才能达到跟
   现在同等的基础效果，工作量比"直接不砍"高出一截。
4. **`libmpv` 已经原生支持"统一基础样式覆盖"，不需要自己写解释器**：
   `sub-color`/`sub-back-color`/`sub-font`/`sub-font-size`/`sub-margin-x`/
   `sub-margin-y`/`sub-pos`/`sub-align-x`/`sub-align-y` 这些 mpv 属性，配合
   **`sub-ass-override=force`**，可以强制用这套配置覆盖字幕文件自带的样式
   （不管来源是外挂 SRT/WebVTT/ASS 还是内嵌 mov_text 轨道，统一生效）——
   用户想要的"基础纯文本+统一前景色背景色"效果，`MovaApi`/`MovaOpts` 透传
   这几个选项给 libmpv 就有了，不用碰 libass 内部也不用自己解析标签。
5. **libmpv 同时能承接"AI 实时翻译字幕"这个未来场景**：mpv 支持
   `osd-overlay` 命令或 `sub-add` 配合可动态更新的字幕源，把外部实时生成的
   文本（翻译/STT 转写）持续喂给同一条 libass 渲染管线，不需要另起一套
   Flutter 渲染逻辑。也就是说 libass 现在同时覆盖"静态字幕文件"和"动态
   实时字幕"两个场景，砍掉它意味着这两个场景都要在 Dart 侧重新实现（含
   "内嵌字幕轨道怎么从容器里抠出来喂给 Dart"这个完全没验证过的难题），
   只为换 2MB，投入产出比不划算。

**结论**：字幕相关瘦身到此为止，libass 全套保留。真要在这个方向上再拿到
显著收益，唯一现实的路径是等 ffmpeg/mpv 版本升级或第三方轻量字幕渲染库
出现，不是现在这份配置能解决的。

## Linux 瘦身构建（2026-08-13，WSL2 本地复现验证通过）

CI 的 `linux` job（`ubuntu-22.04` runner，原生构建，无交叉编译）此前有过一次绿构建
（run 31092096967），但那次的 mpv `meson setup` **没有** `-Dgpl=false`——workflow
里那一步的注释早就标了"产物必须重新构建才能出货"，`dist/linux-x86_64/libmpv.so`
里存的正是这份旧产物，**目前还不能直接出货**。

2026-08-13 在本机 WSL2（Ubuntu 24.04）用 workflow `linux` job 里完全相同的
configure/meson 参数**本地复现了一遍**，目的是先确认配方本身没问题，不急着推 CI：

**踩到一个环境相关的坑，跟 Windows job 同源**：ffmpeg `n6.0` 编译在这台 WSL2
（binutils 2.42）上失败——`libavcodec/x86/mathops.h` 内联汇编的 `shr`/`sar` 用了
非立即数操作数，binutils ≥ 2.41 直接拒绝（`operand type mismatch for 'shr'`）。
这正是 Windows job 早先遇到过、换成 `n6.0.1` 解决的同一个 bug（见下方"Windows 瘦身
构建"一节）。CI 的 `linux` job 之所以此前能跑绿，是因为 `ubuntu-22.04` runner 的
binutils 是 2.38（低于 2.41 门槛），**不代表配方本身没问题，只是运气好踩在了安全区**——
换到更新的发行版（Ubuntu 24.04+、或未来 GitHub Actions 升级 runner 镜像）随时可能
炸。本地换成 `n6.0.1` 后配置/编译均一次通过，跟 Windows job 的解法完全一致。
**建议**：`linux` job 的 ffmpeg 版本也提前改成 `n6.0.1`，不要等 `ubuntu-22.04`
真的升级 binutils 才被动踩坑。

**验证结果**（WSL2 Ubuntu 24.04，ffmpeg n6.0.1 + mpv `78d43740f5`，`-Dgpl=false`）：

| 项 | 结果 |
|---|---|
| configure/make/meson/ninja | 全部一次通过 |
| strip 后体积 | 8,185,280 字节（≈7.81 MiB） |
| 对比旧产物（无 `-Dgpl=false`，8,189,568 字节） | 只小 4,288 字节——`-Dgpl=false` 主要是**许可证合规**意义（mpv 默认 GPL，必须关掉才能维持 LGPL 出货），不是体积手段，体积几乎不受影响 |
| AV1（dav1d） | 走 apt 系统共享库 `libdav1d.so.7`（`ldd` 确认 `NEEDED`），非静态符号——符合 workflow 校验逻辑"`nm` 找到 defined `dav1d_open` 或 `ldd` 命中 `libdav1d` 二选一即可"的口径 |

**本地构建产物没有回填 `dist/linux-x86_64/`**：WSL2 Ubuntu 24.04 的 glibc 比 CI
`ubuntu-22.04` runner 新，直接拿本地产物出货会让消费端 glibc 兼容范围变窄（新 glibc
编译的 `.so` 在更老的发行版上可能因为符号版本对不上而加载失败）。**出货产物必须
让真正的 CI（`ubuntu-22.04`）产出**，本地这次只是验证配方——下次接手：把 `linux`
job 的 `if: false` 打开、ffmpeg 换成 `n6.0.1`、mpv 保留 `-Dgpl=false`，push 触发一次
真实 CI 构建，让它自动回写 `dist/linux-x86_64/libmpv.so`。

### Linux 继续挖掘：TLS 后端换成系统 openssl（2026-08-13）

**关键前提**：Linux 这条线跟 Android/iOS 形状不同——ffmpeg 是 `--enable-static
--disable-shared` **静态链进 libmpv.so**（跟 Android/iOS 一样），但 libass/
freetype/harfbuzz/fribidi/dav1d/mbedtls 等第三方依赖走的是 **apt 装的系统共享库**
（`ldd` 能看到一长串 `.so.N`），不是像 Android/iOS 那样全部静态打包进单个二进制。
这意味着"换 TLS 库"这类第三方依赖的选择，本身对 `libmpv.so` **自身文件体积**基本
没有影响（因为它们的代码字节根本不在这个文件里）——但 ffmpeg 本身既然是静态链入，
`-fvisibility=hidden`/`--gc-sections`/`-flto` 这类"对自己代码生效"的编译器手段
**跟 Android/iOS 是同一个作用域，应该同样有效**（见下一节实测）。

把 `--enable-mbedtls`（apt `libmbedtls-dev`）换成 `--enable-openssl`（apt
`libssl-dev`，Linux 几乎所有发行版都预装 `libssl.so`/`libcrypto.so`，`curl`/
`apt`/`openssh` 等系统组件本身就依赖它，不用像 mbedtls 那样额外要求装小众包）：

| 项 | mbedtls 版 | openssl 版 |
|---|---|---|
| libmpv.so 体积（strip 后） | 8,185,280 B | 8,185,344 B（**几乎相等，+64 字节噪声**——证实了上面"第三方依赖是动态链接，体积跟选哪个库无关"的判断） |
| License | LGPLv3（mbedtls 双授权 Apache-2.0/GPL-2.0 强制 `--enable-version3`） | **LGPLv2.1**（不再需要 `--enable-version3`，跟 iOS 把 mbedtls 换成系统 securetransport 拿到的收益是同一个道理） |
| 运行期依赖 | `libmbedtls.so.14`/`libmbedx509.so.1`/`libmbedcrypto.so.7` | `libssl.so.3`/`libcrypto.so.3` |

**结论：换成 openssl，体积不变但 License 更宽松、依赖更通用，无副作用，直接采纳。**

### Linux 继续挖掘：`-fvisibility=hidden` + `--gc-sections` + `--disable-symver`（2026-08-13）

上网查了一圈，社区对"动态链接第三方依赖的 `.so` 还能不能瘦身"没有直接的实测数据
（Alpine/Arch/Gentoo 的构建脚本、ffmpeg wiki 都没有覆盖这个具体场景），干脆直接
本地实测，不猜。在上面 openssl 版基础上加三样东西：

- ffmpeg `--extra-cflags="-fvisibility=hidden -ffunction-sections -fdata-sections"`
  + `--extra-ldflags="-Wl,--gc-sections"`
- ffmpeg `configure` 加 `--disable-symver`（ffmpeg 是静态链入，符号版本化
  `@@LIBAVCODEC_60` 这套机制对我们毫无意义，纯免费收益）
- mpv meson 加 `-Dc_args="-fvisibility=hidden -ffunction-sections -fdata-sections"`
  `-Dc_link_args="-Wl,--gc-sections"`

**结果**：

| 项 | openssl 基线（无编译器手段） | +visibility/gc-sections/disable-symver |
|---|---:|---:|
| strip 后体积 | 8,185,344 B | **7,816,736 B（−368,608 字节，约 −4.5%）** |
| 导出动态符号数（`nm -D`） | 4,003 | **443**（−89%，跟 Android 当年"4692→610"的量级几乎一样） |

`mpv_create`/`mpv_initialize`/`mpv_render_context_create` 等公开 API 符号确认
仍在（mpv 自己用 `MPV_EXPORT` 宏显式标 `visibility("default")`，跟 Android/iOS
同一套机制，全局转 hidden 不会误伤公开 API），`libass`/`libdav1d`/`libssl`/
`libcrypto` 等依赖链接关系不受影响。**这三样对静态链入 ffmpeg 的场景确实有效，
跟 Android/iOS 的经验一致，直接采纳。**

**LTO 试了但失败，不追**：额外加 `-flto` 到 ffmpeg 和 mpv 两端，mpv 最终链接时
报 `relocation R_X86_64_PC32 against undefined symbol 'bF8' can not be used
when making a shared object; recompile with -fPIC`——ffmpeg x86 NASM 汇编产出的
目标文件与 LTO bitcode 混合链接时不满足 `-fPIC` 要求，这是 ffmpeg 自身汇编代码
生成流程的限制，不是我们配置错了。跟 Android/iOS 走 meson 交叉编译的 LTO 路径
不是同一套工具链组合，Android/iOS 上能行不代表这里也能行。**结论：Linux 这条线
LTO 收益不明确、有真实链接失败风险，不值得为了未知的小体积收益继续折腾，放弃。**

### Linux 继续挖掘：mpv 的 meson buildtype 一直是默认 `debugoptimized`（2026-08-13）

前面几轮都只顾着给 ffmpeg 加 `--enable-small`（映射到 `-Os`），但**从没给 mpv 自己
的 meson build 指定 `buildtype`**——meson 不传 `-Dbuildtype` 时默认是
`debugoptimized`（`-O2` + `debug=true` + `b_ndebug=false`，即保留 assert 断言），
根本没吃到 Android/iOS 那份 `buildtype=minsize`（`-Os`）的优化级别。补上：

```
-Dbuildtype=minsize -Db_ndebug=true -Ddebug=false
```

（`-Ddebug=false` 覆盖 `minsize` 默认帮你打开的 `debug=true`，跟 iOS 那份"两处都会
悄悄把 `-g` 编译进目标文件"的坑是同一个道理；`-Db_ndebug=true` 额外去掉运行时
assert 检查的代码体积，`minsize` 本身不会自动开这个）

| 项 | +visibility/gc-sections/disable-symver | +buildtype=minsize/b_ndebug |
|---|---:|---:|
| strip 后体积 | 7,816,736 B | **7,530,112 B（−286,624 字节，约 −3.7%）** |

`mpv_create` 等公开 API 符号、`libass`/`libdav1d`/`libssl`/`libcrypto` 依赖链接
关系确认均无异常。**这是一个纯粹的"漏配置"，跟 Android/iOS 的经验本该同步做却
没做，直接采纳，零风险。**

### 试过没用的：gold 链接器 + `--icf=all`（相同代码折叠）

`-fuse-ld=gold -Wl,--icf=all` 理论上能把字节完全相同的函数体合并成一份，对
ffmpeg 这种"同一份逻辑给不同 codec 复制了很多次"的代码库应该有戏。实测反而
**体积从 7,530,112 涨到 7,538,656（+8,544 字节）**——gold 的默认 section 布局/
对齐开销盖过了 ICF 折叠掉的那点字节，净效果是负的。**结论：不用，GNU `ld`（bfd）
默认链接器就是当前最优选择，没必要为了这个手段换链接器。**

### avfilter 已经是"零启用"状态，跟 Android 最终决策一致，没有额外空间

检查了一下 `Enabled filters:` 输出——当前配方压根没 `--enable-filter=...` 过
任何一个具体 filter（只有 `--disable-filters` 加上 `CONFIG_AVFILTER=yes` 保留
avfilter 框架本身，给 mpv OSD/字幕合成用），跟 Android 最终定稿的 `FILTERS=""`
是同一个状态。**这条路已经在天花板上，不用再挖。**（同 Android 一样，"avfilter
框架保留但零具体 filter 是否影响 OSD/字幕合成/音量均衡"这个功能性风险仍未真机/
真实播放验证，只是配置层面确认了没有更多体积可省。）

### 汇总：Linux 从"旧的不合规产物"到"当前最优配方"总共省了多少

| 阶段 | strip 后体积 | 累计相对旧产物 |
|---|---:|---:|
| 旧产物（`dist/linux-x86_64/libmpv.so`，无 `-Dgpl=false`，mbedtls） | 8,189,568 B | 基线 |
| + `-Dgpl=false`（合规必须） | 8,185,280 B | −0.05% |
| + mbedtls→openssl（体积无影响，License 换成 LGPLv2.1） | 8,185,344 B | ≈同上 |
| + `-fvisibility=hidden`/`--gc-sections`/`--disable-symver` | 7,816,736 B | −4.6% |
| + mpv `buildtype=minsize`/`b_ndebug=true` | **7,530,112 B** | **−8.05%** |

**下次接手**：`linux` job 除了前面"ffmpeg 换 n6.0.1"，把上面四项手段（openssl
替换 mbedtls、visibility/gc-sections/disable-symver、mpv buildtype=minsize+
b_ndebug）一次性都加上，apt 依赖列表 `libmbedtls-dev` 换成 `libssl-dev`，预期
出货体积 **≈7.53MiB**（比最初"v1 native build"阶段的设想更小）。gold+ICF 已验证
无收益，不用加。

## Windows 瘦身构建（2026-08-13，MSYS2 本地构建链跑通）

**构建环境**：Windows 10/11 + MSYS2（`C:\tools\msys64`，`ucrt64` 子系统）+ Ninja，
**不用 WSL2/Docker**——2026 年 8 月的最新尝试改成原生 MSYS2 ucrt64 gcc 工具链直接跑，
比当年 Android 那套 WSL2 方案更贴近"Windows 上直接构建 Windows 产物"。

**仓库选择**：原计划用的 `media-kit/libmpv-win32-video-build` 已经**归档/不可用**
（GitHub `archived`/`pushed_at` 长期无更新），改用它的活跃后继仓库
**`media-kit/libmpv-win32-video-cmake`**（同作者/同组织，CMake 驱动而非纯 shell 脚本）。
**教训**：在深挖某个仓库的"诡异 bug"之前，先用 GitHub API 查一下
`archived`/`pushed_at`/`updated_at` ——本次因为没有先查，多花了不少时间在修一个后来
发现是"仓库已废弃、根本不会再修"的假 bug 上。

**关键配置**：`cmake -DSKIP_TOOLCHAIN=ON -DTARGET_ARCH=x86_64-w64-mingw32
-DSINGLE_SOURCE_LOCATION="X:/src_packages" -G Ninja -B build_x86_64 -S .`，
`SKIP_TOOLCHAIN` 是本次新加的选项（该仓库默认会先从零构建一整套交叉编译器，
耗时且没必要——MSYS2 ucrt64 本身就自带完整原生 mingw-w64 gcc 工具链，跳过重复构建）。

### 最终产物

`build_x86_64/mpv-dev-x86_64-<date>-git-<rev>/libmpv-2.dll`：

- **28,274,176 字节 ≈ 26.97 MiB**（`strip` 之后，符号单独在 `mpv-debug-*` 目录），
  含 D3D11VA 硬解
- 同批产出 `mpv-x86_64-*`（`mpv.exe`/`mpv.com`）与 `mpv-dev-*`（`client.h` 等头文件，
  供 media_kit 集成用）
- **比 media-kit 官方发行版还小 −25%**：实测下载了官方 2024-10-21 发布的
  `mpv-dev-x86_64` 版本解压，`libmpv-2.dll` 是 **37,735,936 字节（≈35.99 MiB）**——
  这是更合理的参照系，因为它是同一套构建配方、同架构，只是没针对"现代主流点播+直播"
  做任何裁剪（完整 openssl+libssh+libsrt+完整 libplacebo/vulkan/shaderc）。**不要拿
  Android(6.52MiB)/iOS(5.96MiB) 当基准比"差 4-5 倍"**——那两个平台架构完全不同
  （MediaCodec 独立硬解/VideoToolbox 系统 API，不背 GPU-next 渲染管线），不是同一个
  起跑线，直接比没有意义。

### ⚠️ 修复了一个比体积更重要的功能缺口

这套 cmake 仓库默认的 ffmpeg 配置里 `--disable-decoders` 之后，**从未有任何一行
`--enable-decoder=h264`/`hevc`/`vp9` 之类的语句**——也就是说照抄默认配置出来的
"能编译通过、产物也不小"的 libmpv **实际上放不了 H.264/HEVC/VP9/AV1 里的任何一个**，
这比任何体积问题都严重，而且不会在编译期报错，只有真正尝试播放时才会暴露。同理
D3D11VA/DXVA2 硬解 API 也被 `--disable-d3d11va`/`--disable-dxva2` 显式关闭，
即便加上正确的 decoder 之后也只能纯 CPU 软解。这两处都已修复：

- decoder/demuxer/protocol/parser/bsf 清单改为对齐 Android 定稿清单
  （`flavors-mova-slim.sh`）的"现代主流点播+直播"范围，同时补全 h264/hevc/vp9/
  libdav1d(av1)/png 视频解码器 + 完整字幕解码器（ass/ssa/subrip/text/webvtt/movtext）
- 启用 `--enable-d3d11va`（Windows 现代硬解 API，DXVA2 是被取代的旧 API，维持关闭）——
  h264/hevc 的硬解在 D3D11VA 架构下是**寄生在软解 decoder 内部**的（跟 iOS
  VideoToolbox 同一个模式，见上方"iOS 瘦身配置"一节的详细论证），无法收窄成纯硬解，
  这不是保守策略，是架构限制
- 补上这些真正需要的解码器后体积从"一个没有实际解码能力的 34.62MiB"变成
  "一个真正能播放视频的 26.97MiB"（D3D11VA 硬解本身只增加了约 25KB，代价极小）

### 环境级踩坑（影响面广，其他包也可能中招）

以下问题不是某一个依赖包的 bug，是这套"MSYS2 ucrt64 + `SKIP_TOOLCHAIN` + 长路径
`subst` 别名"组合本身的坑，花的时间比逐包修复加起来还多：

1. **`exec.in` 的 PATH 拼接把自己写死的路径顶掉了**——`exec.in`
   （该仓库统一命令执行入口，所有子构建都通过它）把 `@CMAKE_INSTALL_PREFIX@/bin`
   这个带盘符的 Windows 路径（`C:/...`）直接塞进冒号分隔的 `$PATH`，`C:` 那个冒号
   被当成 PATH 分隔符，把路径从中截断成两截垃圾条目——这个坑从**第一次**构建就存在，
   只是长期没暴露，因为没有任何包真的需要从这个目录找工具，直到后面手动放 `ar`/`ranlib`
   shim 才发现"明明放了文件却死活找不到"。修法：用 `cygpath -u` 转成 POSIX 形式再拼。
2. **`eval` 重新分词吞掉了带空格的编译参数**——`exec.in` 用
   `eval "${args[@]}"` 执行最终命令，这一步会把数组元素**拼接成一个字符串再重新按空格
   分词**，所以像 `-DCMAKE_CXX_FLAGS='${x} -fpermissive'`（CMakeLists.txt 里用单引号，
   但单引号对 CMake 只是字面字符，不是语法层面的引号）这种"一个参数内部带空格"的写法，
   会在 eval 阶段被拆成两个独立参数，导致 `-fpermissive` 被当成裸选项报
   "Unknown argument"。**真正有效的修法不是避免空格，而是让参数内容本身带上转义的
   `\"`**（例如 `[=[-DCMAKE_CXX_FLAGS=\"-D__STDC_FORMAT_MACROS -fpermissive\"]=]`）——
   `\"` 在 CMake 生成的中转 `.cmake` 脚本里能正确转义存活，到 eval 阶段这对引号又会被
   bash 当作真实的 shell 引号，把内部空格保护起来。踩过的弯路：先试过 CMake 语法双引号
   包裹整个参数（编译期就会被 CMake 自己的 `set(command "...")` 语句里的裸引号
   提前截断，产生"Argument not separated from preceding token"的语法错误）——所以
   "空格保护"这件事必须同时扛过两层解析（CMake 生成阶段 + bash eval 阶段），只转义一层
   不够。
3. **MSYS2 ucrt64 没有 `x86_64-w64-mingw32-` 前缀的 `ar`/`ranlib`/`nm`/`objcopy`/
   `strip`**——只有 `gcc-ar`/`gcc-ranlib`/`gcc-nm` 这些 gcc 包装版本（且它们依赖
   `liblto_plugin.dll` 必须和自己在同一目录，复制到别处就找不到插件），plain
   `ar.exe`/`ranlib.exe`/`nm.exe`/`objcopy.exe`/`strip.exe` 倒是有但没有目标三元组
   前缀。openssl/ffmpeg 的 Makefile/configure 都是硬编码 `$(CROSS_COMPILE)ar` 这类
   前缀名。修法：在根 `CMakeLists.txt` 里 `SKIP_TOOLCHAIN` 分支下用 `file(COPY_FILE)`
   把这几个 plain 工具复制一份改名放进 `${CMAKE_INSTALL_PREFIX}/bin`（正好在
   `exec.in` 的 PATH 最前面）。
4. **`subst X:` 长路径别名下，"resolve 回真实盘符"这条隐藏规则会咬到用 realpath
   的第三方脚本**——项目根目录路径太深触发 Windows `MAX_PATH`（260 字符）限制
   （尤其是 shaderc 内嵌 glslang 这类深层 third_party），用 `subst X: <项目根目录>`
   起一个短别名规避。但这只是"逻辑映射"，某些工具调用 Win32 的
   `GetFinalPathNameByHandle`（Python `os.path.realpath`、部分 Perl `Cwd::realpath`
   路径）时会把 `X:\...` 解析回真实的长 `C:\...` 路径——如果某段代码里一部分路径算术
   用短别名、另一部分被这类 API 解析回长路径，两者混用会得到风马牛不相及的相对路径。
   实际踩到两处：harfbuzz 的 `gen-harfbuzzcc.py`/`gen-harfbuzz-world.py`（`os.path.abspath`
   +`os.path.relpath` 混用触发 `ValueError: path is on mount 'X:', start on mount 'C:'`，
   修法是统一在两侧都用 `os.path.realpath`）和 openssl 的 `Configure`（Perl 的
   `absolutedir()` helper 只在 `$^O eq "MSWin32"` 时用不解析盘符的 `rel2abs`，MSYS2
   ucrt64 perl 报的 `$^O` 是 `"cygwin"` 不是 `"MSWin32"`，导致落到会解析的
   `Cwd::realpath` 分支——不过这条最后发现是误诊，真正原因见下条）。
5. **openssl 的 `apps/include`/`include/openssl` 输出目录压根没人创建**——上面第4条
   一度以为是 subst 路径解析问题，深挖后发现真相简单得多：`Configure` 里那段写
   `configuration.h` 的代码假设 `apps/include`/`include/openssl` 这两个构建期目录
   已经存在（正常由 Makefile 的其他目标提前 `mkdir` 出来），而我们是直接单独调用
   `Configure` 脚本、没有跑完整的 `make` 依赖链，这两个目录从未被创建，写文件时报
   "No such file or directory"。修法：在 `packages/openssl.cmake` 的
   `CONFIGURE_COMMAND` 前面加两条 `${CMAKE_COMMAND} -E make_directory`。**这是本次
   踩坑里唯一一次"先深挖了错误方向再回头发现更简单真相"的案例，记录下来提醒自己
   下次先看错误信息字面意思，别急着上升到"环境级"猜测**。

### 包级踩坑（一次性，逐个修复）

- **vulkan / spirv-cross 的官方 patch 文件因上游内容漂移，`git am --3way` 报
  `sha1 information is lacking or useless`**——patch 本身没坏，是上游仓库自
  patch 制作以来又有新提交，导致 patch 的上下文行和当前 HEAD 内容对不上。改用
  `git apply`（更容忍上下文漂移）+ 失败时退化成"假定已等效应用"的宽松兜底（写了个
  共享脚本 `apply-patch-idempotent.sh`）。
- **fontconfig 的补丁同理**，改用 `patch -p1 --fuzz=3` 兜底（`git apply` 比
  `patch(1)` 严格得多，fuzz 匹配能扛住行号偏移）。
- **fontconfig 内嵌的 gperf 工具**（`subprojects/gperf`）里 `getopt.c`/`getopt.h`
  用 `#ifdef __GNU_LIBRARY__` 分支出的旧式 K&R 空参数声明
  （`extern int strncmp ();`）在 GCC 16 默认 C23 方言下被当成"零参数原型"，导致
  "too many arguments to function" 编译错误——这是本 session 里第三次遇到同类
  GCC16/C23 K&R 兼容性问题（前两次是 gmp/libiconv，靠全局 `CFLAGS=-std=gnu17`
  绕过；这次因为触发条件是 `__GNU_LIBRARY__` 未定义分支，全局 `-std=gnu17` 没扛住，
  只能手动改这两行声明）。
- **graphengine / zimg 的官方仓库在 bitbucket.org/the-sekrit-twc**——两个都返回
  "You may not have access to this repository or it no longer exists"（Bitbucket
  近年收紧了匿名 git 访问），换成同作者的 GitHub 镜像
  `github.com/sekrit-twc/{graphengine,zimg}` 解决。
- **libjxl / freetype2 clone 偶发空 clone**（只有 `.git` 没有工作树文件）——纯网络
  瞬断（`Failed to connect to github.com:443`），删除后重试即可，不是仓库或配置问题。
- **ffmpeg 默认要求 `cuda_llvm`**（`--enable-cuda-llvm --enable-cuvid --enable-nvdec
  --enable-nvenc --enable-ffnvcodec`，定义在 `cmake/packages_check.cmake`）——这台
  构建机没有 CUDA 工具链，`configure` 报 "cuda_llvm requested but not found"。
  在 `SKIP_TOOLCHAIN` 分支下改成全部 `--disable-*`：mova 只需要 D3D11VA 解码路径，
  NVENC/NVDEC 属于可选加分项，不是本次目标。
- **openal-soft 撞上 GCC16 C++20 modules 与 SSE intrinsics 头文件的编译器级冲突**
  （`common/phase_shifter.cppm`/`alc/context.cppm` 编译时报
  `conflicting language linkage for imported declaration '__m128 ...'`，
  `xmmintrin.h` 里的内联函数在 C++ module 上下文下的语言链接属性和普通翻译单元
  不一致，这是 GCC 该版本 modules 支持的已知不成熟点，不是配置问题）——回头检查发现
  ffmpeg.cmake 里 `DEPENDS` 列了 `openal-soft` 但**从未真正传 `--enable-openal`
  给 ffmpeg configure**，是个挂空依赖，直接从 `DEPENDS` 列表删掉，问题连带消失。
- **mpv 的 `-Dpdf-build=enabled` 需要 `rst2pdf`**（文档生成工具，未安装）——不需要
  文档，改 `-Dpdf-build=disabled`。
- **mpv 配置期报 `Feature egl-angle cannot be enabled`**——`angle-headers` 包只提供
  头文件，不提供实际编译好的 ANGLE（`libEGL`/`libGLESv2`）库，`SKIP_TOOLCHAIN`
  环境下从未真正构建过 ANGLE 本体。`cmake/packages_check.cmake` 里 `mpv_gl` 变量
  在 `SKIP_TOOLCHAIN` 时改成 `-Degl-angle=disabled`，保留普通 `-Dgl=enabled` 即可
  （mpv 有完整的传统 OpenGL/D3D11 输出路径，不依赖 ANGLE）。
- **mpv 自带的"去 libass"补丁不完整**——该仓库有一个
  `mpv-0001-remove-libass.patch`，故意删掉 `sub/osd_libass.c`/`sub/ass_mp.{c,h}`/
  `sub/sd_ass.c` 这几个文件（推测是为了避免某些许可或依赖层面的顾虑，但整个
  依赖链里其实另外单独构建了 `libass` 给 ffmpeg/mpv 用，这个"去 libass"更像是
  只针对 mpv 自身 OSD 渲染入口的一个特化裁剪，而非否定 libass 本身）。但
  `sub/osd.h` 里声明的 `osd_get_function_sym`/`osd_get_text_size`/
  `osd_set_external`/`osd_mangle_ass` 四个函数仍被 `player/command.c` 和
  `player/osd.c` **无条件调用**，补丁没有同步清理这些调用点，导致链接期
  `undefined reference`。`sub/osd.h` 里其实留了行注释"defined in osd_libass.c
  and **osd_dummy.c**"——暗示本该有这么一个空实现兜底文件，但补丁作者忘了真的
  创建它。**这个坑反复踩了 5+ 次**：最初用 patch 文件方式修（新增
  `mpv-0002-osd-dummy-stub.patch`），但共享脚本 `apply-patch-idempotent.sh` 的
  "假定已等效应用"兜底逻辑只检查 patch 能否反向 apply，不检查目标文件是否真的存在——
  每次 mpv 源码因为 `git clone` 重新拉取（网络瞬断重试、或 `force_rebuild_git`
  触发的完整 reclone）而重置时，这个假阳性就会让 `sub/osd_dummy.c` 悄悄消失但 patch
  步骤仍显示"成功"。手写 patch 文件时还额外踩过一次 hunk 头行数写错
  （`@@ -0,0 +1,31 @@` 但实际内容有 35 行），导致 `git apply` 只应用一部分、
  `osd_mangle_ass` 函数体被整个截断丢失——这类 hunk 一律用 `git diff`/`git commit`
  差分生成，不要手写行数。**最终修法**：不再依赖 patch 的幂等检测，在 `mpv.cmake` 的
  `PATCH_COMMAND` 里加一条无条件执行的自愈脚本（`mpv-ensure-osd-dummy.sh`：每次都
  强制 `cp` 模板文件 `mpv-osd_dummy.c` 到 `sub/osd_dummy.c` + 用 `grep`/`sed`
  确保 `meson.build` 引用它），完全不依赖 git 状态判断，自愈而非"假设"。
- **mpv.cmake 复制头文件的源路径写错**——`copy-binary` 步骤里
  `<SOURCE_DIR>/include/mpv/client.h` 这个路径在 mpv 源码里根本不存在，真实路径是
  `<SOURCE_DIR>/libmpv/client.h`（`include/mpv/` 更像是"安装后"的最终布局名字，
  被误当成了源码路径），改一下 `sed` 批量替换即可。
- **打包收尾的 `rename.sh` 脚本执行失败**（"inappropriate file type or format"）——
  该仓库用 `file(WRITE ...)` 在 Windows 上生成的 `#!/bin/bash` 脚本带 CRLF 换行，
  且 `ExternalProject_Add_Step` 直接把这个脚本路径当可执行文件调用（没有 `bash`
  前缀），Windows 的 `CreateProcess` 不认识 shebang，需要显式 `COMMAND bash
  ${RENAME} ...`。

### 极限压缩实验记录（2026-08-13，一个变量一个变量测）

在"修好功能缺口"之后（34.62MiB → 装上真正需要的解码器），继续测了几轮压缩手段，
**一次只改一个变量**（吸取了 batch 测试翻车的教训，见下方"踩过的弯路"）：

| 手段 | 结果 | 结论 |
|---|---:|---|
| **OpenSSL → SChannel**（ffmpeg 自身 TLS，Windows 系统自带 API，同 iOS securetransport 思路）+ 去掉 libssh/libsrt（都依赖 openssl 且都不在实际需要的协议范围内） | **34.62 MiB → 26.94 MiB（−7.68MiB / −22%）** | ✅ **本轮唯一有效的手段**，换掉一整个大依赖库的收益远超任何编译器 flag |
| 去掉 ffmpeg 里 20 个零链接的挂空 DEPENDS（amf-headers/avisynth-headers/bzip2/libmodplug/libpng/libsoxr/libbs2b/libwebp/libzimg/libmysofa/fontconfig/harfbuzz/opus/speex/vorbis/libvpl/libjxl/libxml2/libplacebo 等，逐个用 `libavcodec.pc`/`libavformat.pc` 的 `Libs:`/`Requires:` 字段核实过零链接） | 体积不变（26.94 MiB） | 纯构建时间优化，这些库本来就没被链接进最终产物（ffmpeg 的 `--enable-libXXX` 语义是"只有匹配的 decoder/demuxer/filter 也启用时才真正使用"，光有 DEPENDS 不会让库被链接） |
| 去掉 libplacebo 依赖的 vulkan/shaderc/spirv-cross（`-Dvulkan=disabled -Dshaderc=disabled`，同时精简 vulkan/shaderc/spirv-cross 三个包整个不用构建） | **体积零变化**（byte-for-byte 相同） | LTO + `--gc-sections` 早就把这部分死代码切干净了，砍依赖本身不影响产物 |
| 把 `ar`/`ranlib` 从裸二进制复制改成正确调用 `gcc-ar`/`gcc-ranlib`（带 `--plugin=liblto_plugin.dll`，让静态库归档时真正保留 LTO 字节码，而非退化成非 LTO 的"胖"目标文件）——本身是修复此前一个隐藏 bug，全量重建验证 | **体积零变化**（byte-for-byte 相同） | 说明 LTO 在这套构建里本来就有效（`b_lto=true`/`--enable-lto=thin` 起作用了），这次只是排除了"会不会有更多没兑现的 LTO 收益"的疑虑 |
| 单独测 `-fvisibility=hidden`（只加这一个 flag，不动其他） | **体积零变化**（byte-for-byte 相同） | **根因找到**：Android 该项收益（−669KB）来自 ELF/.so 默认导出所有符号，而 **Windows PE/COFF 默认恰恰相反**——DLL 里的符号默认不导出，必须显式 `__declspec(dllexport)`/`.def` 才会出现在导出表，mpv 自己用 `MPV_EXPORT` 宏做这件事。这个 flag 在 Windows 上是在解决一个根本不存在的问题 |
| 单独测 `--cpu=x86-64-v2 --disable-runtime-cpudetect`（固定 SSE4.2 基线，砍掉 ffmpeg 为不同 SIMD 等级编译的多份 dispatch 变体，代价是放弃 ~2009 年前的老 CPU 兼容性） | 体积几乎不变（−2KB） | `--enable-small` 本身可能已经在 SIMD 变体数量上做过妥协，这条路径的冗余本来就不多 |

**踩过的弯路**：曾经一次性 batch 打包 `-Doptimization=s`（从 `3` 改）+
`-fvisibility=hidden` + `--gc-sections` 三个变量一起测，结果体积从 34.62MiB **涨到**
53.53MiB——回滚后拆开单独测才发现真正拖累的是 `optimization=s` 这一项（具体机制未查，
猜测是跟 `b_lto_mode=thin`——GCC 其实没有 clang 式的"thin LTO"，只有 fat LTO，混用
可能导致某种双重编译或退化路径），而不是 visibility。**教训：多个变量一起改，出问题
后无法定位是哪个变量的锅，必须回滚重测——这次拆开单独测才拿到干净结论**。

**结论**：这套构建的编译器/链接器层面手段已经系统性测完，**26.97MiB（含 D3D11VA 硬解）
是当前不碰 mpv/ffmpeg 源码前提下的现实下限**。唯一还没测的是物理 patch 源码删代码
（比如砍掉 libplacebo 的 `vo_gpu_next` 渲染路径——但 libplacebo 在 mpv 0.39
`meson.build` 里是硬依赖，没有 `required: get_option()` 开关，真要去掉必须手动改 mpv
源码，风险等级等同于 iOS 那边评估过并放弃的"物理砍 ffmpeg h264 解码器像素代码"，
用户已确认**暂不深入这个方向**。

### 下一步（未做）

- **接入 mova 工程**：目前只是产物验证阶段，还没接进 Flutter 侧（fork/path override
  `media_kit_libs_windows_video`，方法同 Android 那节"与 media_kit 集成"）。
- **真机（真实 Windows 机器）播放验证**：还没有跑过 `example` 应用实际播放视频，
  只验证了"编译链接通过、产物存在"——这是目前性价比最高、也是唯一必须做的下一步，
  优先级高于继续抠体积。
- **UPX 后处理压缩**（搜索到的通用方案，未实测）：号称能把体积压到原来的 ~26%，
  但 DLL 用 UPX 压缩的稳定性/兼容性不如 EXE，且可能触发杀毒软件误报，加载时也有
  解压开销——如果要试，必须先验证 `LoadLibrary`/Dart FFI `DynamicLibrary.open`
  加载 UPX 压缩后的 DLL 没有问题，再谈体积收益。
- **libplacebo 硬依赖能否物理砍掉**：已评估，风险等级等同物理砍解码器代码，
  用户已确认暂缓，见上方"极限压缩实验记录"结论。
- **未跑 x86/x86_64（除本次 x86_64 外）其他架构**：`TARGET_ARCH` 目前只验证了
  `x86_64-w64-mingw32`，i686/aarch64 交叉编译目标未测试。

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
