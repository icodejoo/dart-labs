# videoman ffmpeg 瘦身构建配置

「主流点播+直播格式 + `-Os`」的可复用 ffmpeg 瘦身构建配置。对应遗留任务 #4（二期
ffmpeg 瘦身，见根 [CLAUDE.md](../../CLAUDE.md)）。所有组件清单与优化标志经 2026-07-31
Windows spike 实测验证，完整过程与数据见
[../../doc/plans/2026-07-31-ffmpeg-slim-build-windows.md](../../doc/plans/2026-07-31-ffmpeg-slim-build-windows.md)，
组件取舍依据见 [../../doc/notes/2026-07-31-ffmpeg-slimming-options.md](../../doc/notes/2026-07-31-ffmpeg-slimming-options.md)。

## 是什么

一个 `configure` 封装脚本 `configure-ffmpeg-slim.sh`，为 videoman 构建**只保留现代主流
点播+直播格式、`-Os` 优化体积、LGPL、纯解码（无编码/封装）**的 ffmpeg 共享库。

**支持的格式**（现代主流点播+直播，范围经产品拍板）：
- 视频：H.264 / H.265(HEVC) / VP9 / AV1 / VP8
- 音频：AAC(+LATM) / MP3 / Opus / AC-3 / E-AC-3 / FLAC / Vorbis
- 容器：MP4(全家桶) / MKV / WebM / MPEG-TS / **HLS** / **FLV(含直播)** / RTSP / 裸音频流
- 协议：http(s)/tls / **HLS AES 加密分片** / **RTMP 全家(直播)** / RTSP+RTP+UDP
- **不含**：DASH（需外部 libxml2，见下）、rtmpe/rtmpte（需外部 crypto 后端）、Android
  `content://`、一切老旧格式（AVI/ASF/RM/WMV/DVD/蓝光…）、**一切编码器/封装器**。

## 实测结果（Windows/x86，同工具链，install strip 后，仅 ffmpeg 7 库）

| 版本 | 体积 | 相对 |
|---|---|---|
| 完整版 ffmpeg(-O3，全格式) | 29.8 MB | — |
| 主流瘦身(-O3) | 11.0 MB | 省 63% |
| **本方案：主流瘦身 + `-Os`** | **6.26 MB** | **省 79%（相对完整版）** |

解码性能代价（480p H.264）：真实多线程播放约慢 **2%**（单线程约 7%）。

> ⚠️ **以上均为 Windows/x86 数字。真机 ARM+NEON 的体积/性能百分比会有出入，
> 必须在目标平台复测**。HEVC/AV1/更高分辨率的 `-Os` 代价也与 H.264 不同。

## 源码母版

### 上游（要瘦身的对象，权威来源）

| 组件 | 官方仓库 | 说明 |
|---|---|---|
| **ffmpeg** | `https://git.ffmpeg.org/ffmpeg.git`（镜像 `https://github.com/FFmpeg/FFmpeg.git`） | spike 实测用 commit `ad53728984531cebdb027e70e78d7165a6bdfe20`（master，约 8.0 线） |
| **mpv / libmpv** | `https://github.com/mpv-player/mpv.git` | 本脚本只构建 ffmpeg；完整 libmpv 瘦身见下「与 libmpv 的关系」 |

拉取 ffmpeg：
```bash
git clone --depth 1 https://github.com/FFmpeg/FFmpeg.git ffmpeg
```

### 我们当前随包的基线（media_kit 预编译，即本次瘦身要替换的对象）

videoman 经 media_kit 使用**预编译** libmpv（内含完整 ffmpeg），当前基线为
`libmpv-2.dll` ≈ 29.76 MB（Windows）。其来源链：

| 平台 | media_kit 预编译来源 | 上游 |
|---|---|---|
| Windows/桌面 | media_kit 构建（`mpv-player/mpv` 某 commit + `google/angle` GLES） | 见 `media_kit_libs_windows_video` 的 CHANGELOG（逐版本标注 mpv commit，如 `140ec21`/`652a1dd`） |
| Android | `https://github.com/media-kit/libmpv-android-video-build` releases（v1.1.7，ffmpeg 静态链入 libmpv） | 同 mpv-player/mpv 上游 |
| iOS/macOS | media_kit 对应的 `libmpv-*-video-build` 构建仓库 | 同上 |

> 即：**要瘦身就是把 media_kit 这套「完整预编译 libmpv+ffmpeg」换成我们自建的瘦身版**。
> media_kit 的各 `libmpv-*-video-build` 仓库的构建脚本，是我们自建时的直接参照。

## 环境准备

核心依赖：C 编译器 + `nasm`（或 yasm）+ `make` + `pkg-config`。

- **Windows（MSYS2 / mingw）**：
  ```bash
  choco install msys2 -y     # 需管理员
  # 在 MSYS2 ucrt64 shell：
  pacman -S --noconfirm --needed mingw-w64-ucrt-x86_64-gcc \
    mingw-w64-ucrt-x86_64-nasm mingw-w64-ucrt-x86_64-pkgconf make git diffutils
  ```
  ⚠️ **企业 TLS 拦截网络**（如证书链 `CN=sangfor CA`）下 MSYS2 的 HTTPS 官方镜像会
  报 `unable to get local issuer certificate`——在 `etc/pacman.d/mirrorlist.*` 顶部
  加明文 HTTP 镜像（如 `http://mirrors.tuna.tsinghua.edu.cn/...`）即可绕过。
- **Linux（Debian/Ubuntu）**：`sudo apt install build-essential nasm pkg-config git`
- **macOS**：`brew install nasm pkg-config`（Xcode CLT 提供编译器）

## 用法

```bash
# 只 configure（检查配置是否成立）：
./configure-ffmpeg-slim.sh /path/to/ffmpeg-src

# configure 并构建安装（-Os 默认）：
./configure-ffmpeg-slim.sh /path/to/ffmpeg-src /path/to/out '-Os' --build

# 想对比 -O3：
./configure-ffmpeg-slim.sh /path/to/ffmpeg-src /path/to/out-o3 '-O3' --build
```

组件清单在脚本顶部的 `DECODERS`/`PARSERS`/`DEMUXERS`/`PROTOCOLS`/`BSFS` 变量里，按需增删。

## 已知取舍与扩展点

- **LGPL**：当前 ffmpeg 里 LGPL 已是默认（`--enable-lgpl` flag 已移除），脚本不传任何
  `--enable-gpl`/`--enable-nonfree`，即为 LGPL。构建摘要会打印 `License: LGPL ...`。
- **DASH**：`dash` demuxer 依赖外部 `libxml2`，默认未启用。需要时：系统装 libxml2，脚本
  configure 补 `--enable-libxml2`，并往 `DEMUXERS` 加 `,dash`（libxml2 LGPL 兼容）。
- **rtmpe/rtmpte**（RTMP 私有加密，冷门）：需外部 crypto 后端（openssl/gnutls/mbedtls）。
  构建环境装了其一并 `--enable-openssl` 之类即自动可用；否则被禁，不影响主流 rtmp。
- **进一步压体积**（详见 spike 文档）：`-Os` 已是甜点。再叠 `--enable-small`（源码级缩表）
  仅再省约 0.13MB（2%）却增加解码变慢风险，**不推荐**；去 vp8/ac3/eac3/flac/vorbis 仅省
  约 0.36MB，性价比低。`swscale`(约 2MB) 是大头但 libmpv 需要它，不可轻去。

## 与 libmpv 的关系（重要）

**本脚本只构建 ffmpeg，不是最终产物。** videoman 用的是 **libmpv**，ffmpeg 是 libmpv 的
底层依赖。最终要的是「瘦身版 libmpv（内含此瘦身 ffmpeg）」替换 media_kit 的预编译库。
完整 libmpv 瘦身（还要处理 mpv 自身的脚本引擎/字幕渲染/显示后端等，见
[../../doc/notes/2026-07-31-libmpv-slimming-options.md](../../doc/notes/2026-07-31-libmpv-slimming-options.md)）
是更大的工程，本配置是其中「ffmpeg 那一半」的实测就绪部分。构建完整 libmpv 时，把 mpv 的
构建指向这个瘦身 ffmpeg（`--enable-lgpl` mpv 侧、`PKG_CONFIG_PATH` 指向本脚本的安装前缀）
即可。
