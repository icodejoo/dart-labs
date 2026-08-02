# videoman ffmpeg 瘦身构建配置（终稿，移动端优先）

「现代主流点播+直播格式 + 体积优先」的 ffmpeg 瘦身构建配置。对应遗留任务 #4（二期
ffmpeg 瘦身，见根 [CLAUDE.md](../../CLAUDE.md)）。

**本终稿的数据来自 Android arm64-v8a 真机构建链实测**，不是 Windows 推算。历史 Windows
spike 过程与数据见 [../../doc/plans/2026-07-31-ffmpeg-slim-build-windows.md](../../doc/plans/2026-07-31-ffmpeg-slim-build-windows.md)，
组件取舍依据见 [../../doc/notes/2026-07-31-ffmpeg-slimming-options.md](../../doc/notes/2026-07-31-ffmpeg-slimming-options.md)。

## 是什么

`configure-ffmpeg-slim.sh`：一个 ffmpeg `configure` 封装，产出**只保留现代主流点播+直播
格式、纯解码（除一个 png 编码器）、体积优先、LGPL** 的 ffmpeg。目标是移动端
（Android/iOS）；**桌面端明确不在考虑范围内**。

**支持的格式**：

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

本脚本只 configure ffmpeg。videoman 出货的是 **libmpv（ffmpeg 静态链在里面）**，
必须走 `libmpv-android-video-build`：

```bash
git clone https://github.com/media-kit/libmpv-android-video-build
cd libmpv-android-video-build/buildscripts
# 1. NDK 25.2.9519653 放到 sdk/android-sdk-linux/ndk/25.2.9519653
# 2. ./include/download-deps.sh          拉源码
# 3. ./patch.sh                          ← 千万别漏，见上文
# 4. 把本脚本的组件清单写成 flavors/<name>.sh，cp 到 scripts/ffmpeg.sh
# 5. ./build.sh --arch arm64 mpv
# 6. llvm-strip --strip-all prefix/arm64-v8a/usr/local/lib/libmpv.so
```

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
- **AV1**：只用 libdav1d。ffmpeg 自带 av1 解码器体积更大且在 arm64 上慢一个量级，永不启用
- **再往下压体积就是放弃功能**（不建议在无明确需求时动）：
  - 字体栈 libass+freetype+harfbuzz+fribidi 约 2 MB —— 放弃 ASS 特效字幕才能省
  - libdav1d 约 1.4 MB —— 赌 AV1 硬解才能省，老设备直接不能播
  - mbedtls+mbedcrypto 约 1.6 MB —— 把 https 交给 Dart/Kotlin 侧下载后喂 fd 才能省
- **`-Os` 的真实作用范围**：ffmpeg 侧 media_kit 上游本来就带 `--enable-small`（clang 下
  映射为 `-Oz`），所以 `-Os` 在 ffmpeg 上**没有增量收益**；增量来自 dav1d/freetype/
  fribidi/harfbuzz/mpv 从 `-O3` 降到 `-Os`，以及上面那三个上游压根没开优化的库
