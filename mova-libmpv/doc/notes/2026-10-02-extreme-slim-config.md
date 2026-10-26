# libmpv 极致瘦身配置：ffmpeg n9.0.2 + mpv v0.41.0（最小静态 libplacebo、摘 `vo_gpu_next`）

> 2026-10-02 · 调研 + 实测笔记 · 分支 `feat/whep-receiver` · 范围只在 `mova-libmpv/doc/notes/` 新增本文件，不改任何已跟踪文件。
>
> **读法**：每条结论后面括号里注明依据（文件+行号 / 命令输出 / URL）。验证等级 `R` 真机、`C` 仅 CI、`L` 本文 Linux x86_64 实测、`B` 仅编译、`T` 理论；**没核实的明说"未核实"，没测的明说"未测/未跑"**，不编体积数字。
>
> **本文在 Linux x86_64（WSL Ubuntu，gcc 15.2，nasm，meson 1.10.1，ninja 1.13.2）上真实跑过的事**：ffmpeg n9.0.2 `configure` + 编译（20 余次）、mpv v0.41.0（摘 `vo_gpu_next`）+ libplacebo v7.360.1 最小静态 + 全套依赖静态链接，链接（30 余次）、量 stripped `libmpv.so` 字节（与评估基线 9,209,384 同口径，**复跑得到字节一致的 9,209,384**），校验 28 个 `mpv_*` 函数仍导出、未解析符号为 0（`-Wl,--no-undefined`）、软渲染 `loadfile`+出帧、12 类媒体样本播放矩阵、libass 字幕渲染、本地 TLS 服务器的 HTTPS 矩阵、变速不变调实测。**Android / Windows / iOS / macOS 一个都没跑**（没有交叉工具链/没有 Mac/没有真机），这些平台的行一律是"由 Linux 数据外推的方向 + 旧数据"，标为 `T`/`B`。
>
> **关键口径提醒**：WHEP 计划 §4/T0.2 的评估基线（钉死 9,053,064、v0.41.0 摘 gpu_next 9,209,384 等）用的 ffmpeg 是**最小子集且没有 `--enable-small`**（`/root/w/mpvt/eval/ffbuild.sh`），本文实测 `--enable-small` 单项就值 4,415,384 字节（+43%）。所以那组数字只能用来比"同口径内的相对增量"，不能和 n6 线产品体积（README 的 6,050,104 / 14,033,920 / 7,550,784）直接比。

## 0. 摘要：最终推荐配置（一页纸）

### 0.1 结论

| 档位 | 定义 | Linux x86_64 stripped（L，实测） | 备注 |
|---|---|---:|---|
| **S 安全档**（迁移首发） | n6 线现行白名单原样迁到 n9.0.2（删 `--disable-postproc`、`--disable-everything`+显式 bsf/hwaccel）、mpv v0.41.0 + b3、最小 libplacebo、freetype 裁模块、`-Db_lundef=true`、各平台已验证的编译器手段 | **10,274,152** | 比评估基线 9,209,384 大 11.6%，因为装的是**完整产品白名单**（dav1d、字幕、flv/rtmp/rtp…） |
| **X 极致档**（本文推荐的上限，需 5 项拍板） | S + LTO + 全链路去 unwind 表 + RELR + mbedtls L1 裁剪（+ Linux 才有的 RELR） | **8,754,480**（MAXL1B） | **比评估基线小 454,904B（−4.9%）**，同时装着完整白名单；−14.79% vs S |
| X−AV1（不推荐，仅记录下限） | X 再去掉 dav1d | 7,410,960（无 mbedtls 裁剪）/ 7,111,896（再加 L1+关 TLS1.3） | AV1 软解丢失，Android bengal 档真机已证实会播放失败 |

`MAXL1B` 的完整校验（L）：28 个 `mpv_*` 函数全部导出（导出符号共 54）；`nm -D --undefined-only` 除 glibc 外 **0**；链接带 `-Wl,--no-undefined`、**不带** `--allow-shlib-undefined`；`NEEDED` 仅 `libm.so.6 libc.so.6`；软渲染 `loadfile` 出帧；12 类样本（mp4/hevc/webm-vp9+opus/av1/mkv/flv/ts/hls/mp3/flac/ogg/mov_text）全部播到 EOF（reason=0）；`sub-add`+libass 渲染像素校验和 with/without 不同；HTTPS（自签 CA）在「TLS1.2+1.3 / 仅 1.2 / 仅 1.3」三种服务器下 `tls-verify` yes/no 全过。

### 0.2 X 档的 5 个必须由产品/工程拍板的取舍

1. **去 unwind 表（−8.65%，Linux）**：崩溃回溯在这些库内部断帧（Android tombstone / Crashlytics NDK）。Android/iOS 实际收益**未测**。
2. **`-Dauto_features=disabled`**：iconv/uchardet 关了 → **GBK/BIG5 等非 UTF-8 外挂字幕不再转码**（`misc/charset_conv.c:152`）；必须与现产物 feature 清单逐项对账（Android/Windows 现状未知）。
3. **mbedtls L1 裁剪（−114,712B，-Os 对照）**：已在三种 TLS 服务器上实测，但没测 chacha-only 服务器、真公网 CDN。**不要**关 TLS1.3（TLS1.3-only 服务器实测失败）、**不能**关 `SSL_SRV_C`（ffmpeg n9 编译失败）。
4. **dav1d 位深 / 是否保留**：Android 现状 `-Dbitdepths=8` 放弃 10-bit AV1 软解；去掉 dav1d 在无 AV1 硬解的机型上直接播放失败（真机已证）。
5. **RELR（Linux −3.5%）**：Linux 桌面需 glibc ≥ 2.36；Android 等价手段未测。

### 0.3 各平台命令骨架

**共同原则**：`--disable-everything --disable-autodetect` + 显式白名单；**删掉 `--disable-postproc`**（n9 报 Unknown option）；每次 configure 后用 `Enabled …` 摘要对账（§1 顶部警告）；`make` 前 `mkdir -p libswscale/x86`（n9.0.2 out-of-tree 并行竞态，§7 #9）。

**Linux x86_64（本文真实跑过的 S 档；极致档在 `[]` 内追加）**

```bash
# ---- ffmpeg n9.0.2（git archive n9.0.2；out-of-tree）----
export PKG_CONFIG_LIBDIR=$DEPS/lib/pkgconfig
mkdir -p build && cd build && mkdir -p libswscale/x86
../configure --prefix=$FF \
  --disable-everything --disable-autodetect --disable-programs --disable-doc --disable-debug --disable-avdevice \
  --disable-gpl --disable-nonfree --enable-version3 --enable-static --disable-shared --enable-pic --pkg-config-flags=--static \
  --disable-symver --disable-swscale-alpha --disable-iconv --disable-vulkan \
  --enable-small --enable-optimizations --enable-network \
  --enable-avutil --enable-avcodec --enable-avformat --enable-avfilter --enable-swscale --enable-swresample \
  --enable-mbedtls --enable-zlib --enable-libdav1d \
  --enable-decoder=h264,hevc,vp9,png,libdav1d,aac,aac_latm,mp3float,opus,flac,vorbis,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s32le,pcm_f32le,pcm_u8,ass,ssa,subrip,text,webvtt,movtext \
  --enable-encoder=png \
  --enable-parser=h264,hevc,vp9,av1,png,aac,aac_latm,flac,opus,vorbis,mpegaudio \
  --enable-demuxer=mov,matroska,webm_dash_manifest,mpegts,hls,flv,live_flv,data,mp3,flac,ogg,wav,aac,ass,srt,webvtt \
  --enable-protocol=file,fd,pipe,data,http,https,tcp,tls,crypto,rtmp,rtmps,rtmpt,rtmpts,ffrtmpcrypt,ffrtmphttp,udp,rtp \
  --enable-bsf=null,extract_extradata,h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,vp9_superframe,vp9_superframe_split,av1_frame_split,av1_frame_merge,mov2textsub,dump_extradata,setts \
  [--enable-lto] \
  --extra-cflags="-I$DEPS/include -ffunction-sections -fdata-sections -fvisibility=hidden [-fno-asynchronous-unwind-tables -fno-unwind-tables]" \
  --extra-ldflags="-L$DEPS/lib -Wl,--gc-sections"

# ---- libplacebo v7.360.1 最小静态 ----
meson setup plc-build --prefix=$PLC --libdir=lib --default-library=static --buildtype=minsize -Db_ndebug=true -Ddebug=false \
  -Dvulkan=disabled -Dopengl=disabled -Dd3d11=disabled -Dglslang=disabled -Dshaderc=disabled \
  -Dlcms=disabled -Ddovi=disabled -Dlibdovi=disabled -Dxxhash=disabled -Dunwind=disabled \
  -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false \
  -Dc_args="-ffunction-sections -fdata-sections -fPIC" -Dcpp_args="-ffunction-sections -fdata-sections -fPIC"

# ---- mpv v0.41.0 + b3（摘 vo_gpu_next）----
git apply b3-v041.patch          # Android 另 git apply javavm-v041.patch
meson setup build --prefer-static --buildtype=minsize -Db_ndebug=true -Db_lundef=true -Ddebug=false \
  -Dauto_features=disabled -Dgpl=false -Dcplayer=false -Dlibmpv=true -Dbuild-date=false -Dtests=false \
  -Dgl=enabled -Dplain-gl=enabled [-Db_lto=true] \
  -Dc_args="-ffunction-sections -fdata-sections [-fno-asynchronous-unwind-tables -fno-unwind-tables]" \
  -Dc_link_args="-Wl,--gc-sections -Wl,--exclude-libs,ALL -Wl,--version-script=mpv.ver -Wl,--as-needed -static-libstdc++ -static-libgcc [-Wl,-z,pack-relative-relocs]"
#   mpv.ver:  { global: mpv_*; local: *; };
strip -s libmpv.so.2.5.0 -o libmpv.stripped.so
nm -D --defined-only libmpv.stripped.so | grep -c ' mpv_'            # 导出
nm -D --undefined-only libmpv.stripped.so | grep -v GLIBC | grep -v ' w '   # 必须为空
```

依赖库构建（freetype 裁模块、fribidi、harfbuzz、libass、dav1d、zlib、mbedtls）的完整参数见 §2.3、§4.2、§5；脚本在 WSL `/root/w/mpvt/extreme/`（`build-deps.sh`、`build-ff.sh`、`build-mpv.sh`、`run-v*.sh`）。

**Android arm64-v8a（骨架，未跑）**：沿用 `media-kit/libmpv-android-video-build @1ecf510` + `libmpv-android-video-build.patch`（已含 meson cross file 的 `minsize`/`b_lto`/分节/visibility、`--native-file`、fribidi `-Db_lto=false`）。ffmpeg 改为：

```bash
./configure --prefix=$P --target-os=android --enable-cross-compile --cross-prefix=$TC/bin/aarch64-linux-android- \
  --cc=$CC --cxx=$CXX --ar=$AR --nm=$NM --ranlib=$RANLIB --strip=$STRIP --arch=aarch64 --cpu=armv8-a --pkg-config=pkg-config \
  --disable-everything --disable-autodetect --disable-programs --disable-doc --disable-debug --disable-avdevice --disable-stripping \
  --disable-gpl --disable-nonfree --enable-version3 --enable-static --disable-shared --pkg-config-flags=--static \
  --disable-symver --disable-swscale-alpha --enable-small --enable-optimizations --disable-runtime-cpudetect --enable-network \
  --enable-jni --enable-mediacodec --enable-mbedtls --enable-zlib --enable-libdav1d \
  --enable-avutil --enable-avcodec --enable-avformat --enable-avfilter --enable-swscale --enable-swresample \
  --enable-decoder=hevc,libdav1d,png,aac,aac_latm,mp3float,opus,flac,vorbis,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s32le,pcm_f32le,pcm_u8,ass,ssa,subrip,text,webvtt,movtext,h264_mediacodec,hevc_mediacodec,vp9_mediacodec,av1_mediacodec \
  --enable-encoder=png --enable-parser=… --enable-demuxer=… --enable-protocol=… --enable-bsf=…   # 与上同
  --enable-lto --extra-cflags="-I$P/include -ffunction-sections -fdata-sections -fvisibility=hidden -flto" --extra-ldflags="-L$P/lib -Wl,--gc-sections -flto"
# x86/x86_64 ABI：configure 后 mkdir -p libswscale/x86 再 make
```
mpv：`b3` + `javavm-v041.patch`；meson 在 Linux 骨架上改 `-Degl-android=enabled -Dandroid-media-ndk=enabled -Dopensles=enabled -Daudiotrack=enabled -Daaudio=disabled`，`c_link_args` 加 `-landroid -llog -lEGL -lc++_static -lc++abi`，libplacebo 同上最小静态（Android 评估用的是 `-Dopengl=enabled`，改 disabled 未验证）。

**Windows x86_64（骨架，未跑）**：ffmpeg 用 `--disable-everything --disable-autodetect --enable-schannel --enable-zlib --enable-libdav1d --enable-d3d11va --enable-dxva2 --enable-hwaccel=h264_d3d11va,h264_d3d11va2,h264_dxva2,hevc_d3d11va,hevc_d3d11va2,hevc_dxva2,vp9_d3d11va,vp9_d3d11va2,vp9_dxva2,av1_d3d11va,av1_d3d11va2,av1_dxva2`，**不加** `-ffunction-sections`/`-fvisibility`/`--enable-lto`，不加 `--enable-version3`；mpv 用 clang，`-Dbuildtype=minsize -Ddebug=false -Db_ndebug=true -Db_lundef=true`，只给 mpv 本体 `-ffunction-sections -fdata-sections`，`-Wl,-Bstatic -lstdc++ -lwinpthread -Wl,-Bdynamic -ldwrite -lole32 -lrpcrt4 -static-libgcc -Wl,--gc-sections`；`-Dgl=enabled -Dplain-gl=enabled` 必须保留（**不要**照抄旧分支 `-Dgl=disabled`）；其余 Windows 特性项是否 `auto_features=disabled` 见 §2.2（未核实）。生成新 `libmpv.dll.a`（`gendef`+`dlltool`）。

**iOS / macOS（骨架，未跑，无 Mac）**：Darwin 补丁需要改：删 `--enable-protocol=hls`（n9 无此协议）；mpv 升到 v0.41.0 同步升 ffmpeg 到 n9.0.2（v0.41.0 要求 ffmpeg ≥ 6.1）；`-Dlibplacebo*` 之类 v0.41.0 不存在的选项不要写；`-Diconv=disabled -Duchardet=disabled` 现状保持。TLS 仍是 securetransport，**无 DTLS**。

## 1. ffmpeg n9.0.2 configure 全量参数表

**写法约定**

- 「来源」：`n6线` = 当前 main 的 n6 线现行配置（`flavors-mova-slim.sh` / CI `linux`、`windows` job / Darwin `movaslim` 补丁）；`v9旧` = 旧分支 `mova-libmpv-winbuild-zhangfly` 的 v9 线；`新增` = 本文新提或本文实测才有数据。
- 「验证」：`R` 真机验证（README / mova CLAUDE.md 有设备与事件证据）；`C` 仅 CI 构建绿；`L` 本文在 Linux x86_64（WSL，gcc 15.2，ffmpeg n9.0.2 + mpv v0.41.0）实际 configure+编译+链接+播放矩阵；`B` 仅编译过（评估脚本/旧分支）；`T` 理论，没跑过。写 `n6:R / n9:L` 表示旧版本真机过、n9 只在 Linux 过。
- 本文所有 `L` 的工作目录是 WSL `/root/w/mpvt/extreme/`（脚本 `build-deps.sh`、`build-ff.sh`、`build-mpv.sh` 等，副本在本次 session scratchpad）；ffmpeg 源是 `git archive n9.0.2`（commit `946fcce07b6dcd0331c8cc609192aeff5e1924f8`，Changelog 首行 `version 9.0.2`）。
- 所有「名字是否存在」的结论来自 n9.0.2 自己的 `./configure --list-decoders/encoders/demuxers/muxers/parsers/protocols/bsfs/filters/hwaccels`（603/269/367/185/68/55/51/592/79 项，原始输出在 `/root/w/mpvt/extreme/lists/`），不是凭记忆。

> **先看这条（最容易让人以为配置没问题的坑）**：n9.0.2 的 `configure` 对**不存在的组件名静默放行**。实测 `--enable-bsf=foo`、`--enable-protocol=hls`、`--enable-demuxer=whep` 全部「accepted」，没有任何报错也没有警告。README 里 `--enable-decoder=av1`（只是 parser 名，真正的解码器叫 `libdav1d`）被静默丢弃的老坑（README L118 "踩坑记录（2026-08-06）"）在 n9 上同样存在。所以**列表里每个名字必须用 `--list-*` 对一遍，并在 configure 结束后对照 `Enabled decoders/…` 摘要核对**。本文做了这件事：S 档配置请求的 23 个解码器、1 个编码器、11 个 parser、16 个 demuxer、17 个协议、12 个 bsf 全部出现在摘要里，无静默丢弃（脚本 `chkenabled.py`，输出见 §8.3）。

### 1.1 全局禁用 / 构建形态类

| 参数 | 作用 | 来源 | 验证 | 风险 / 备注 |
|---|---|---|---|---|
| `--disable-everything` | 一次清空 decoders/encoders/hwaccels/muxers/demuxers/parsers/bsfs/protocols/devices/filters，之后只靠白名单打开 | v9旧（`build-win-libmpv-v9.sh` 注释 "Base is --disable-everything"）、Darwin 补丁；n6线 Android/Linux/Windows 是逐类 `--disable-decoders --disable-encoders --disable-demuxers --disable-parsers --disable-protocols --disable-devices --disable-filters` + `--enable-bsfs --enable-hwaccels`（`flavors-mova-slim.sh:103-121`，workflow `:831-832`） | L（n9.0.2 configure 通过，本文全部 13+ 个变体都用它） | **bsf 和 hwaccel 也被清零，必须显式列**。n6 线的 `--enable-bsfs`/`--enable-hwaccels` 是「全开」，白名单 `--enable-bsf=...` 在它面前是冗余的（`flavors-mova-slim.sh:119` 与 `:71` 同时存在）。n9 推荐改为只列白名单；全开 bsf 的体积代价见 §3.2（BSFALL 变体：+520,192B） |
| `--disable-autodetect` | 所有 `[autodetect]` 的外部库/平台 API 仅在显式 `--enable-xxx` 时才链入，避免 CI 镜像换了就悄悄多链东西 | v9旧（`build-win-libmpv-v9.sh`，引用 superuser404notfound/FFmpegBuild） | L（n9 configure 通过）；Windows v9 另有真机日志 | **坑**：`--enable-d3d11va --enable-dxva2` 本身就是 `[autodetect]` 开关，被它一并关掉；只写 `--enable-hwaccel=h264_d3d11va,...` 而漏写这两个，ffmpeg 解码器不会声明 D3D11VA，mpv `hwdec=auto` 静默回落软解、无任何报错。v9 用 `mpv -v` 日志 `Using hardware decoding (d3d11va)` 验证了修复（`build-win-libmpv-v9.sh` 头注释，R-v9） |
| `--disable-programs --disable-doc --disable-avdevice` | 不要 ffmpeg/ffprobe/ffplay、文档、libavdevice | n6线（workflow `:830`、`flavors-mova-slim.sh:111-114`） | C / L | 无。`--disable-devices`/`--disable-indevs/outdevs` 在 `--disable-everything` 下冗余 |
| `--disable-postproc` | 不要 libpostproc | n6线（`flavors-mova-slim.sh:113`、`flavors-mova-slim-ios.sh:104`、`configure-ffmpeg-slim.sh:317`、workflow `:830`、`:1096`） | **L：n9.0.2 报 `Unknown option "--disable-postproc"` 直接失败**（`--enable-postproc` 同样 Unknown；`grep -n postproc configure` 无结果，libpostproc 已从 n9 移除） | **必须删掉**，这是 n6→n9 迁移第一个必炸点（5 个文件） |
| `--disable-debug` | 不带 `-g` | n6线 iOS（README L678 起：strip+`--disable-debug` 把 iOS 6.86→5.99→5.96MiB）；Android 没传但最后 `llvm-strip --strip-all` | C / L | 无风险，只影响编译产物大小与速度；最终 strip 后无差别 |
| `--disable-gpl --disable-nonfree` | 保持 LGPL | n6线全平台 | C / L（configure 摘要 `License: LGPL version 3 or later`） | — |
| `--enable-version3` | 升到 LGPLv3 | n6线 Android（mbedtls 强制，README L636 起"LGPL → LGPLv3"） | L（mbedtls 下摘要为 LGPL v3 or later） | **仅 mbedtls 平台需要**。Windows(SChannel)/Linux(openssl)/Darwin(securetransport) 不要加，CI 有 `License: LGPL version 2.1` 的 grep 断言（workflow `:847` 一带） |
| `--enable-static --disable-shared --enable-pic --pkg-config-flags=--static` | 静态链进 libmpv | n6线 | L | `--enable-pic` Linux x86 必须（链进 .so）；Android 目标默认 PIC |
| `--disable-symver` | 去掉 ELF 符号版本化（静态链入，毫无用处） | n6线 Linux（README L866 起，和 visibility 一起 −368,608B） | L（n9 通过）；n6:C | Windows/Mach-O 无意义 |
| `--disable-swscale-alpha` | swscale 不带 alpha 通道代码 | n6线 Android（`flavors-mova-slim.sh:116`）、v9旧 | C（Android）/ L | 体积收益**未单独测**。功能上：带透明通道的封面图（PNG attached picture）经 swscale 转换时 alpha 被忽略——**未验证**对 mova 封面显示的影响 |
| `--disable-iconv` | ffmpeg 内部不用 iconv | n6线 Android（`flavors-mova-slim.sh:99`） | C | 与 mpv 的 iconv 无关（mpv 自己的 `-Diconv` 另算，见 §2）。`--disable-autodetect` 下冗余 |
| `--disable-vulkan` | n6 时代必须（NDK 无 `vulkan_beta.h` 导致 `hwcontext_vulkan.c` 编译失败，README L636 起） | n6线 | C | n9 下 `--disable-autodetect` 已覆盖。但 **n9 公共头 `libavutil/hwcontext_vulkan.h` 仍引用 Vulkan 1.3 类型**，旧分支 Android v9 为此在前缀里放了 Vulkan-Headers v1.3.296（`build-android-libmpv-v9.sh` "Vulkan-Headers" 段，B-v9）。本文 Linux 链路（libplacebo 关 vulkan）未遇到；Android NDK r25c 是否遇到：未核实 |
| `--disable-bzlib --disable-linux-perf --disable-dxva2 --disable-vaapi --disable-vdpau --disable-videotoolbox --disable-audiotoolbox --disable-gray` | 各自关闭 | n6线 Android（`flavors-mova-slim.sh:115,123-129`） | C | 在 `--disable-everything --disable-autodetect` 下全部冗余（`--disable-gray` 的默认本来就是关）。保留无害，删掉也无害。**注意**：它们在 Android 上还负责「不要把平台 A 的 API 误开在平台 B」，改成 `--disable-autodetect` 方案后由 `--enable-xxx` 白名单承担 |
| `--enable-small --enable-optimizations` | `-Os`（clang 下 README 记为 `-Oz`）；开优化 | n6线（README L636 起"-Os 的真实作用范围"） | C / L | `--enable-small` 单项收益见 §3.1：不开它 S 档 +4,415,384B |
| `--disable-runtime-cpudetect` | 编译期固定 CPU 能力、去掉分发代码 | n6线 **仅 arm64**（`flavors-mova-slim.sh:83-84`） | n6:C（README L217 关键单项 4：arm64 上**实测零收益**） | **只可用于 aarch64**（NEON 为基线）；armv7/x86/x86_64 上禁止照抄（有真实崩溃风险）。Windows v9 实测 `--cpu=x86-64-v2 --disable-runtime-cpudetect` 仅 −2KB（README L1137 极限压缩记录），不要用 |
| `--disable-x86asm` | 关掉 nasm 汇编，退回 C | 新增 | **L：S 10,274,152 → 8,742,248（−1,531,904，−14.9%）** | **不推荐**：h264/hevc/vp9/swscale/tx 的 SIMD 全部丢失，软解性能大幅下降；ARM 上对应 `--disable-asm/--disable-neon` 同理不可取。仅作为"asm 占了 1.5MB"的归因数据 |
| `--enable-lto` | ffmpeg 自身 LTO | n6线 Android（`flavors-mova-slim.sh:89`；整链 LTO −521KB，README L86 定稿表） | Android: C/R；**Linux: L（见 §3：ffmpeg+mpv LTO −131,152B）**；Windows: 不用（本地 +12,288B，`2026-09-17-windows-libmpv-slim.md` §12） | n6 线 README L866 起记录 Linux "LTO 试了但失败（NASM 对象与 LTO 混链报 `-fPIC`）"——**在 n9.0.2 + gcc 15 + `--enable-pic` 下不再复现**，ffmpeg+mpv 双 LTO 链接通过；`LTO` 变体软渲染冒烟通过，含 LTO 的 `MAX`/`MAXL1` 变体 12 类媒体样本全部播放通过 |
| `--extra-cflags="-ffunction-sections -fdata-sections -fvisibility=hidden"` + `--extra-ldflags="-Wl,--gc-sections"` | ELF 上逐函数分节 + 隐藏符号 + 链接期回收 | n6线 Android/Linux | n6:R(Android)/C；n9:L | **只对 ELF（Android/Linux）有效**。Windows(COFF)上 ffmpeg 加分节 **+124%**（14.70→32.58MiB，`2026-09-17-windows-libmpv-slim.md` §12 发现 2），visibility 在 PE 上零收益（README L1137）；Mach-O 用 `-Wl,-dead_strip`（Darwin 补丁） |
| `--extra-cflags="-fno-asynchronous-unwind-tables -fno-unwind-tables"` | 去掉 `.eh_frame` 展开表（C 代码不需要） | **新增** | **L：全链路（deps+ffmpeg+mpv）S 10,274,152 → 9,385,320（−888,832，−8.65%）**；Android/iOS：**未测** | 崩溃现场回溯会断在这些库的帧上（Android tombstone / Crashlytics NDK 依赖 `.eh_frame` 展开）；Windows x64 SEH 需要完整 unwind 信息，旧分支实测拒绝（`-fno-asynchronous-unwind-tables` −87,552B 但不采纳，`2026-09-17-windows-libmpv-slim.md` §12）。**属 X 档，必须由产品/崩溃上报策略拍板** |
| `--enable-network` | 开网络栈 | n6线 | C / L | — |
| `--enable-avutil --enable-avcodec --enable-avformat --enable-avfilter --enable-swscale --enable-swresample` | 只留 mpv 需要的 6 个库 | n6线 | C / L | mpv 硬依赖这 6 个（`meson.build:22-27`），avfilter 里 filter 全空也能播（见 §1.5、§6） |
| `--enable-hardcoded-tables` | 用硬编码表代替运行时生成 | 无人用过 | T | 会**增大**体积，不用 |

### 1.2 平台硬解 / TLS / 外部库启用类

| 参数 | 平台 | 作用 | 来源 | 验证 | 风险 / 备注 |
|---|---|---|---|---|---|
| `--target-os=android --enable-cross-compile --cross-prefix=… --arch=… --cpu=…`（`armv8-a`/`armv7-a`/`generic`/`i686 --disable-asm`） | Android | 交叉编译 | n6线（`flavors-mova-slim.sh:20-25,86-88`） | n6:R(arm64)/C(其余) | x86 用 `--disable-asm`（i686 无 nasm 路径）；n9 下 x86_64 开 asm，需 §7 的 out-of-tree 竞态规避 |
| `--enable-jni --enable-mediacodec` | Android | MediaCodec 硬解 + `av_jni_set_java_vm` | n6线（`:118,…`） | n6:R（STG-AL00：H.264/HEVC/VP9 硬解，README L520 起） | **配套 mpv 补丁 `mpv_lavc_set_java_vm`**（见 §2.1），缺了 media_kit 加载就 `UnsatisfiedLinkError`（`build-android-libmpv-v9.sh` 头注释 bug #1） |
| `--enable-d3d11va --enable-dxva2` + `--enable-hwaccel=h264_d3d11va,h264_d3d11va2,h264_dxva2,hevc_d3d11va,hevc_d3d11va2,hevc_dxva2,vp9_d3d11va,vp9_d3d11va2,vp9_dxva2,av1_d3d11va,av1_d3d11va2,av1_dxva2` | Windows | D3D11VA/DXVA2 硬解 | n6线 CI（`:1101`，靠 autodetect 全开 hwaccel）；显式 hwaccel 列表来自 v9旧 | n6:R（Windows 真机 2026-09-24，README Windows 行）；n9 的 12 个 hwaccel 名全部存在（`--list-hwaccels` 核对，L-名字） | 一旦改用 `--disable-everything`，hwaccel 列表和 `--enable-d3d11va/dxva2` 必须同时写（上面 `--disable-autodetect` 的坑） |
| `--enable-videotoolbox`（`--enable-neon` 随 Darwin 补丁） + hwaccel `h264_videotoolbox,hevc_videotoolbox,vp9_videotoolbox` | iOS/macOS | VideoToolbox | Darwin 补丁 `video_common_options` | n6:C（CI 绿，无 Mac 无真机，README iOS 节） | **n9 新增 `av1_videotoolbox` hwaccel**（`--list-hwaccels` 实测有；README 记 n6.0 没有）。仍需 `libdav1d` 兜底：VideoToolbox AV1 只有新款 SoC 才有硬解（该判断是常识性推断，**未核实**设备清单）。Darwin 补丁里的 `--enable-audiotoolbox` 链入 AudioToolbox 框架但 movaslim 白名单里没有任何 `*_at` 解码器，**可删，未测** |
| `--enable-vaapi --enable-vdpau` | Linux | 桌面 Linux 硬解 | n6线 CI（`:837`） | n6:C | 动态加载系统库；本文 Linux 实测未开（没有 dev 库），hwaccel 名 `h264_vaapi,hevc_vaapi,vp9_vaapi,av1_vaapi,h264_vdpau,hevc_vdpau,vp9_vdpau,av1_vdpau` 在 n9 存在 |
| `--enable-mbedtls` (+`--enable-version3`) | Android（Linux 实测亦用） | TLS，WHEP 需 DTLS-SRTP 需宏 `MBEDTLS_SSL_DTLS_SRTP`（见 §4） | n6线 | n6:R(Android HTTPS 在播)；n9:L（Linux x86_64 链接+播放） | n9 的 `tls_mbedtls.c:655` 无条件调用 `mbedtls_ssl_conf_dtls_cookies`，**mbedtls 若关 `MBEDTLS_SSL_SRV_C` 则 ffmpeg 编译失败**（L：变体 MBl2/MBl3 失败，错误 `implicit declaration of function ‘mbedtls_ssl_conf_dtls_cookies’`） |
| `--enable-schannel` | Windows | 系统 TLS，零额外字节，去掉 version3 | n6线（workflow `:1100`；−773,632B，`…windows-libmpv-slim.md` §12 Task 1） | n6:R | WHEP：`configure:7619` 对 schannel 的 DTLS 做 `SECPKG_ATTR_DTLS_MTU` 编译检查，mingw-w64 头是否带该宏**未核实** |
| `--enable-securetransport` | iOS/macOS | 系统 TLS | Darwin 补丁 `tls_movaslim_options` | n6:C | **n9 `dtls_protocol_deps_any="openssl schannel gnutls mbedtls"`（`configure:4115`）不含 securetransport → iOS/macOS 在 n9 上也没有 DTLS** |
| `--enable-openssl` | Linux | 系统 openssl，LGPLv2.1 | n6线（workflow `:836`） | n6:C | — |
| `--enable-zlib` | 全平台 | mov `cmov`、mkv zlib 压缩轨、HLS 等 | n6线 | n6:C；n9:L | `--disable-autodetect` 下必须显式写；系统 `-lz` 在 Linux 会变成动态依赖，本文把 zlib 1.3.1 静态进前缀 |
| `--enable-libdav1d` | 全平台（Android 为兜底） | AV1 软解 | n6线 | n6:R（Android：AV1 硬解失败后软解兜底成功，README L105） | **`--enable-decoder=libdav1d` 不带 `--enable-libdav1d` 会被静默丢弃**（README L118）。关于去掉它见 §6 |
| `--enable-libass` | — | ffmpeg 自己的 libass 只服务 `ass`/`subtitles` 滤镜 | v9旧脚本传了；n6线没传 | — | **不要加**：mpv 直接链 libass；ffmpeg 里 filters 为空时它纯属死重 |
| `--enable-libxml2` | — | `dash` demuxer | n6线明确不要（README L168 "DASH 澄清"、L646 "DASH：需要时…约 740 KB"） | — | 不要加 |

### 1.3 白名单（按 mova 真实用途推导）

**推导依据**：mova 是 HLS 为主的点播/直播播放器（Darwin 补丁注释 `libmpv-darwin-build-mova-slim.patch:370-372`："mova is an HLS-first VOD/live player … RTMP push/pull and raw RTP/UDP live feeds are still real sources it needs to open — keep the full RTMP family and udp/rtp"；README L274 "RTMP 全家（直播）、UDP/RTP（IPTV 组播）"；`configure-ffmpeg-slim.sh:237-262` 对每个协议的理由）。FLV 国内直播、字幕 SRT/ASS/WebVTT/mov_text 都是用户拍板保留项（`doc/notes/2026-07-31-ffmpeg-slimming-options.md` §0；README L520 起字幕四格式真机 PASS）。视频以硬解为主，软解按平台能力取舍。

下表「n6 现状」四列 = Android(A) / Windows(W) / Linux(L) / Darwin(D)；✓ 有，✗ 无，`hw` 仅 mediacodec 硬解。**n9 名称核对一栏全部是对 n9.0.2 `--list-*` 的实测结果**。

**视频解码器**

| 组件 | n6 现状 A/W/L/D | n9 名称 | n9 推荐 | 依据 / 验证 | 风险 |
|---|---|---|---|---|---|
| `h264` | hw/✓/✓/✓ | 存在 | S 档：A 不开，其余开 | A 摘软解 2026-08-11（`flavors-mova-slim.sh:40-46`，"NEEDS REAL-DEVICE REGRESSION TEST"）；其余平台 VideoToolbox/D3D11VA/VAAPI 是叠加在软解码器上的 hwaccel，**摘了硬解一并失效**（README L678 起 iOS 节、Windows 节） | **A 的"仅硬解"至今无真机回归（README L143 的表格仍写"双通道保留"，与脚本不一致，以脚本为准）**；CDD 强制 H.264 硬解不覆盖畸形流/并发会话边界 |
| `hevc` | ✓(+hw)/✓/✓/✓ | 存在 | 全开 | A 保留软解：HEVC 硬解覆盖约 65% 且非 CDD 强制（`flavors-mova-slim.sh:47-51`）；v9旧 Android 摘了（9.29MB 一步 −440KB），README 明确反对在无使用占比数据时摘 | X 档才考虑摘（需机型占比数据） |
| `vp9` | hw/✓/✓/✓ | 存在 | A 不开，其余开 | A 摘软解 −667KB（README L86 定稿表）；其余平台同 h264 的 hwaccel 寄生关系 | A：不支持 VP9 硬解的设备直接播放失败（README L636 起） |
| `libdav1d` | ✓/✓/✓/✓ | 存在（外部库解码器） | S 全开 | A：骁龙 bengal 档 AV1 硬解 "Could not open codec."，软解兜底成功（R，README L105）；+671KB（Android arm64 实测） | 去掉的代价见 §6；Linux x86_64 实测 −1,601,632B（本文 NODAV1D，`-Dbitdepths=8,16` 且 x86 asm） |
| `av1_mediacodec` / `h264_mediacodec` / `hevc_mediacodec` / `vp9_mediacodec` | A 专有 | 全部存在 | A 全开 | R（H.264/HEVC/VP9 真机硬解；AV1 硬解此设备失败走软解） | 需 `--enable-mediacodec --enable-jni` |
| `png` | ✓ | 存在 | 全开 + encoder `png` | 封面图/截图（README L644 "截图功能靠 png 编码器"） | 截图功能依赖 encoder png；`--strict-decode` 类设置会让 screenshot 命令失效 |
| `mjpeg`/`vp8`/其它 | ✗ | 存在 | 不开 | README L177：MJPEG +68KB 不加回；VP8 无硬解封装、被 VP9/AV1 取代 | 已知不支持，不要加 |

**音频解码器**

| 组件 | n6 现状 A/W/L/D | n9 | n9 推荐 | 依据 | 风险 |
|---|---|---|---|---|---|
| `aac`、`aac_latm` | ✓ 全部 | 存在 | 开 | HLS/MP4 标配，LATM 见于 MPEG-TS | — |
| `mp3float` | ✓ 全部 | 存在 | 开 | 与定点 `mp3` 二选一（`flavors-mova-slim.sh:56-58`） | — |
| `mp3`（定点） | ✗/✓/✓/✗ | 存在 | 不开 | 冗余实现 | 摘除后 W/L 无功能损失 |
| `opus`、`flac`、`vorbis`、`pcm_s16le/s16be/s24le/s32le/f32le/u8` | ✓ 全部 | 存在 | 开 | WebM/DASH 常见；wav 用 PCM | — |
| `ac3`、`eac3` | ✗/✓/✓/✗ | 存在 | **S 档：A/D 不开（现状）；W/L 是否也摘：产品拍板** | A 2026-08-11 摘除，理由 "mova's actual content is AAC/Opus, never Dolby"（`flavors-mova-slim.sh:54-58`）；**n9 的 hls demuxer 自带 select `ac3_parser`、`ac3_demuxer`、`eac3_demuxer`（`configure:3943`），所以 parser/demuxer 摘不掉，只有解码器可摘**（L 实测：S 配置未要 ac3，摘要里 ac3 parser 与 ac3/eac3 demuxer 仍被自动选入） | 影视点播偶有 Dolby 音轨；摘后该音轨静音。AC3 变体体积增量见 §3.2（+40,960B） |

**字幕解码器**（全平台一致）

| 组件 | n9 | 推荐 | 依据 / 验证 |
|---|---|---|---|
| `ass`、`ssa`、`subrip`、`text`、`webvtt`、`movtext` | 全部存在（注意 n9 里叫 `movtext`，不是 `mov_text`） | 全开 | R：SRT/ASS/WebVTT 外挂 + mov_text 内封四格式真机 PASS（STG-AL00，2026-09-28，README L520 起）；n9：**L 软渲染 + libass 实测**（`sub-add` s.srt，`sub-visibility` yes/no 两次渲染像素校验和不同；mov_text 轨 `movtext.mp4` 播到 EOF） |
| `srt` | 存在（Darwin 补丁多开了它，Android 没有） | 不必开 | `subrip` 已覆盖外挂 SRT（Android 真机 PASS 用的就是无 `srt` 解码器的配置） |

**Parser**

| 组件 | n6 现状 | n9 | 推荐 | 依据 |
|---|---|---|---|---|
| `h264`、`hevc`、`vp9`、`av1` | A/W/L/D 全有 | 存在 | 开 | 即使无软解码器也要靠 parser 找帧边界喂 mediacodec（`flavors-mova-slim.sh:65-67`） |
| `aac`、`aac_latm`、`flac`、`opus`、`vorbis`、`mpegaudio`、`png` | 全有 | 存在 | 开 | — |
| `ac3` | 仅 W/L | 存在 | 不必写 | n9 `hls_demuxer_select` 自动带入 |

**Demuxer**

| 组件 | n6 现状 | n9 | 推荐 | 依据 | 风险 |
|---|---|---|---|---|---|
| `mov` | 全有 | 存在 | 开 | MP4/MOV/M4A | — |
| `matroska` | 全有 | 存在 | 开 | MKV+WebM | — |
| `mpegts`、`hls`、`flv`、`live_flv` | 全有 | 存在 | 开 | HLS 与国内 FLV 直播（用户拍板）。**n9 的 `hls` 只剩 demuxer**，`hls` 协议已在 8.1 移除（`Changelog` "Remove the old HLS protocol handler"） | **Darwin 补丁里 `--enable-protocol=hls` 在 n9 上是无声空操作**（不会报错，见顶部警告） |
| `data`、`mp3`、`flac`、`ogg`、`wav`、`aac` | 全有 | 存在 | 开 | 裸音频文件/audioOnly 模式（Darwin 补丁注释 `libmpv-darwin-build-mova-slim.patch:326-330`） | — |
| `ass`、`srt`、`webvtt` | 全有 | 存在 | 开 | 外挂字幕 | — |
| `webm_dash_manifest` | A/W/L 有，D 2026-09-18 已摘 | 存在 | S 保留 A（已出货）；X 档摘 | README L163/L168："只是 WebM 内嵌 DASH 清单这一窄组合，不代表通用 DASH，不建议依赖"；Darwin 补丁注释 `libmpv-darwin-build-mova-slim.patch:279` 起记录 mova 确认不需要 | 摘后 WebM-DASH 清单播放失败；**收益未单独测** |
| `dash`（需 libxml2）/`rtsp` | 无 | 存在 | 不开 | DASH：+740KB libxml2（README L168、L646）；RTSP：见 §3.2（RTSP 变体 +155,648B） | 若产品要加：`rtsp` 经 `rtpdec_select` 拖入 `asf`、`rm` demuxer（`configure:3991`，L 实测 `Enabled demuxers` 出现 `asf rm`） |
| `ac3`、`eac3` | W/L | 存在 | 不必写 | `hls_demuxer_select` 自动带入（`configure:3943`） | — |

**Protocol**

| 组件 | n6 现状 | n9 | 推荐 | 依据 |
|---|---|---|---|---|
| `file`、`fd`、`pipe`、`data` | 全有 | 存在 | 开 | 本地/Android content fd/管道（`configure-ffmpeg-slim.sh:246-251`） |
| `http`、`https`、`tcp`、`tls`、`crypto` | 全有 | 存在 | 开 | HLS 全部；`crypto` = HLS AES-128 |
| `rtmp`、`rtmps`、`rtmpt`、`rtmpts`、`ffrtmpcrypt`、`ffrtmphttp` | 全有 | 存在 | 开（产品侧明确有 RTMP 直播源） | `rtmpe/rtmpte` 需外部 crypto 后端，不要（`configure-ffmpeg-slim.sh:252,261`） |
| `udp`、`rtp` | 全有 | 存在 | 开 | IPTV 组播（udp 喂 mpegts）、RTP 直播源 |
| `hls`（协议） | Darwin 写了 | **n9 已移除** | 删掉这行 | 见上 |
| `async`、`cache`、`httpproxy`、`ftp`、`rtsp`（不是协议名）… | 无 | `async cache ftp httpproxy` 存在 | 不开 | 笔记 `…ffmpeg-slimming-options.md` §4 "async/cache 建议保留"，但 n6 线实际一直没开且 Android 真机能播，mpv 自带 cache；**未再验证** |

**Bitstream filter**（n9 共 51 个，n6 线 12 个）

| 组件 | 推荐 | 依据 |
|---|---|---|
| `null`、`extract_extradata`、`h264_mp4toannexb`、`hevc_mp4toannexb`、`aac_adtstoasc`、`vp9_superframe`、`vp9_superframe_split`、`av1_frame_split`、`av1_frame_merge`、`mov2textsub`、`dump_extradata`、`setts` | 开（12 个，n9 全部存在，L 摘要核对无丢失） | `configure-ffmpeg-slim.sh:264-272`：mp4toannexb 是 MediaCodec 播 mp4 必需；aac_adtstoasc 供 HLS/TS 里的 AAC；extract_extradata 与 vp9/av1 拆帧器是对应解码器要求；mov2textsub 供 mp4 内封字幕 |
| `--enable-bsfs`（全开 51 个） | **不要**（n6 线 Android 现状，`flavors-mova-slim.sh:119`） | 白名单已够；全开代价见 §3.2 BSFALL 变体（+520,192B） |

**Filter**：n6 线 Android/Linux 全空（`FILTERS=""`，`flavors-mova-slim.sh:76`），Darwin 保留 `overlay,equalizer`（`libmpv-darwin-build-mova-slim.patch` audio_movaslim_options）。**Android 真机验证过零 filter 时字幕合成/OSD 无回归**（2026-09-28，README L520 起；音量均衡为代码审查排除）。**n9 推荐全空**；本文 Linux 链路零 filter 下 12 类样本 + libass 渲染通过（L）。Darwin 现保留的两个 filter 与 Android 结论不一致，**未验证 Darwin 可否同样摘除**。

**编码器**：只留 `png`（截图/封面）。**Muxer**：全空。

### 1.4 WHEP flavor 额外项（只在 `*-whep` flavor 加，默认 flavor 不含）

数据来自本文对 n9.0.2 的核对 + 本地 `whepchk` configure（摘要 `Enabled muxers: rtp whip`、`Enabled protocols: … dtls … srtp …`、`Enabled demuxers: asf mov mpegts rm rtp sdp`，`License: LGPL version 3 or later`）。

| 参数 | 作用 | 来源 | 验证 | 风险 / 备注 |
|---|---|---|---|---|
| `--enable-protocol=dtls,srtp`（`udp`、`rtp`、`http`、`https`、`tls`、`tcp`、`crypto` 已在基线） | DTLS 握手 + SRTP；`dtls_protocol_select="udp_protocol"`（`configure:4116`），`srtp_protocol_select="rtp_protocol srtp"`（`configure:4110`） | 新增（`whip.c` 同款依赖，计划 `2026-10-01-whep-receiver.md` D3） | L（configure 通过；本文 WHEPSET 变体已编译链接，见 §3.2 与 §8.2.1） | `dtls` 需要 TLS 后端满足 `dtls_protocol_deps_any="openssl schannel gnutls mbedtls"`（`configure:4115`），否则 `--enable-protocol=dtls` **静默无效** |
| `--enable-demuxer=rtp,sdp` | RTP 解包（含 `rtpdec_h264`/`rtpdec_opus`）+ SDP 解析 | 新增（计划 A5/A6） | L（同上） | **`rtpdec_select="asf_demuxer mov_demuxer mpegts_demuxer rm_demuxer rtp_protocol srtp"`（`configure:3991`）会把 `asf`、`rm` 两个遗留 demuxer 一起拖进来**；计划里 +297KB 的上界估计包含它们 |
| `--enable-muxer=whip`（可选） | 现成的 WHIP 发送端，代码是新写 `whep.c` 的模板 | 新增 | L | `whip_muxer_select="dtls_protocol rtp_muxer http_protocol"`（`configure:4014`）；接收端不需要，计划里 +106,928B（最小子集口径）。`rtp` muxer 随之入选 |
| `--enable-demuxer=whep` | 将来 `whep.c` 的注册名 | 新增（尚不存在） | **n9.0.2 没有**：`--list-demuxers` 无 whep，configure 对该名字静默放行 | 补丁落地后需同时补 `allformats.c` 注册与 configure 的 `whep_demuxer_select`/`deps` 行 |
| 平台 TLS 后端 | Windows=`--enable-schannel`（`SECPKG_ATTR_DTLS_MTU` 检查，`configure:7619`）；Android=`--enable-mbedtls` + mbedtls 开 `MBEDTLS_SSL_DTLS_SRTP`（`tls_mbedtls.c:281,306,515,657` 四处 `#if`）；Linux=openssl/mbedtls 均可；**iOS/macOS 无** | 计划 D3 | Linux/mbedtls：configure L；其余 T | Android 自建 mbedtls 必须开 SRTP 宏：本机 `mbed-inst` 的头文件第 2055 行已 `#define MBEDTLS_SSL_DTLS_SRTP`；未开时 ffmpeg 运行期报 "DTLS-SRTP is not supported in this mbedtls build"（计划 §1.2 引用 `tls_mbedtls.c:515-518`） |
| TLS 校验默认值 | n9 `tls_verify` 默认 **1**（`libavformat/tls.h:93-94`），n6.0.1 默认 0（`tls.h:49`） | 新增（迁移坑） | L（读源码） | **mpv 的 `stream_lavf.c:201` 总是显式写 `tls_verify`=0/1**，所以走 mpv 的 http(s) 行为不变；**WHEP 信令（`whep.c` 内部直接用 ffmpeg 的 http/tls）不经 mpv，会吃到 n9 的默认 1**，Android 自建 mbedtls 若没有 CA 证书源则全部信令握手失败，需要显式传 `tls_verify`/`ca_file` 或补默认 CA |

### 1.5 n6 线各平台 ffmpeg 现状 → n9 推荐的"差异一览"

| 项 | Android（`flavors-mova-slim.sh`） | Windows（CI） | Linux（CI） | Darwin（movaslim 补丁） | n9 推荐 |
|---|---|---|---|---|---|
| 基线禁用方式 | 逐类 `--disable-*` | 同左 | 同左 | `--disable-all` 风格（meson 拼接） | 统一 `--disable-everything --disable-autodetect` |
| bsf / hwaccel | `--enable-bsfs --enable-hwaccels`（全开） | 同左（autodetect） | 同左 | 显式 bsf，hwaccel 显式 | 全部显式白名单 |
| TLS | mbedtls(+v3) | schannel | openssl | securetransport | 不变 |
| `--disable-postproc` | 有 | 有 | 有 | 无 | **删除** |
| `--enable-lto` | 有（真机验证） | 无（实测负收益） | 无（n6 时失败） | cross-file `-flto`（CI） | Android 保留；**Linux 可开（L：−131,152B）**；Windows 不开 |
| h264/vp9 软解 | 无 | 有 | 有 | 有 | 不变 |
| ac3/eac3、`mp3`（定点） | 无 | 有 | 有 | 无 | 产品拍板，建议统一 |
| `webm_dash_manifest` | 有 | 有 | 有 | 无 | S 保持各自现状；X 统一摘 |
| filters | 空 | 空 | 空 | `overlay,equalizer` | 空（Darwin 需先验证） |

## 2. mpv v0.41.0 meson 参数表（含 libplacebo）

### 2.1 源码与补丁

| 项 | 内容 | 依据 / 验证 |
|---|---|---|
| mpv 版本 | **v0.41.0**（commit `41f6a645068483470267271e1d09966ca3b9f413`，`git -C /root/w/mpvt/src-v041 describe` = `v0.41.0`）。`RELEASE_NOTES:18`："This release requires FFmpeg 6.1 or newer and libplacebo 6.338.2 or newer"；`meson.build:22-29` 要求 libavcodec ≥ 60.31.102、libplacebo ≥ 6.338.2 | L：与 ffmpeg n9.0.2（libavcodec 63.1.102、libavformat 63.1.102、libavutil 61.1.102、libavfilter 12.1.102、libswscale 10.1.102、libswresample 7.1.102，取自 mpv configure 日志）配对，**无需任何兼容补丁**即可编译、链接、播放 |
| 钉死旧 mpv（n6 线用的 `78d43740f5`） | 与 n9.0.2 不兼容：26 条错误 / 9 个文件（`AVCodec.sample_fmts` 等字段、`FF_PROFILE_*`、`avcodec_close`、`AVStream.side_data`、`AV_OPT_TYPE_CHANNEL_LAYOUT` 被移除） | 计划 `2026-10-01-whep-receiver.md` T0.2 spike（该次为 Linux 最小配置，非本文复跑）。需要 342 行兼容补丁 `pin-n9-compat.patch`，**已被"用 v0.41.0"决定取代，作废** |
| **b3 补丁：摘掉 `vo_gpu_next`** | 3 个文件共 8 行删除：`meson.build` 删 `video/out/placebo/ra_pl.c`、`video/out/placebo/utils.c`、`video/out/vo_gpu_next.c`、`video/out/gpu_next/context.c` 四行；`options/options.c` 删 `extern … gl_next_conf` 与 `OPT_SUBSTRUCT(gl_next_opts, gl_next_conf)`；`video/out/vo.c` 删 `video_out_gpu_next` 的 extern 与驱动表项 | **L**：`git apply --check` 对干净的 `git archive v0.41.0` 通过并成功应用；之后完整编译链接；`vo=libmpv` 软渲染冒烟通过。依据：libmpv render API 只有 `gpu`、`sw` 两个后端（`video/out/vo_libmpv.c:114-118`，`include/mpv/render.h:468-470` 只定义 `opengl`、`sw` 两个 API type），`vo_gpu_next` 不在其中但在 VO 驱动表里被引用所以链接器丢不掉 |
| javavm 补丁（Android 专用） | `include/mpv/client.h` 在 `mpv_wakeup` 后加 `MPV_EXPORT int mpv_lavc_set_java_vm(void *vm);`；`player/client.c` 加 `#include <libavcodec/jni.h>`，文件末尾加 `int mpv_lavc_set_java_vm(void *vm){ return av_jni_set_java_vm(vm, NULL); }` | **L：在 b3 之后 `git apply --check` 通过**（本文复核）；Android 编译：B（评估期编过，计划 T0.2 记录 `client.h` 带 23 行偏移、旧补丁 `client.c` hunk 打不上，现在的 `javavm-v041.patch` 是手工移植版）。缺它 media_kit 的 `MediaKitLibsAndroidVideoPlugin` 报 `UnsatisfiedLinkError: cannot locate symbol "mpv_lavc_set_java_vm"`（`build-android-libmpv-v9.sh` bug #1，B-v9→真机复现） |
| libplacebo | **v7.360.1**（`git ls-remote --tags https://github.com/haasn/libplacebo.git` 当前最新 tag；本机树 `describe` = `v7.360.1`，commit `cee9b076f2c63104ccfd497fa79c39a867293ec4`，2026-03-14）。mpv 的 `dependency('libplacebo', version: '>=6.338.2', default_options: ['default_library=static','demos=false'])`（`meson.build:29-30`），**v0.41.0 tag 里没有 `subprojects/`**（`git ls-tree v0.41.0` 核对），所以必须预先装好 libplacebo 并让 pkg-config 找到，不能指望 meson 自动取 | L：最小静态版本，见 §2.3 |
| 版本补充 | master（比 v0.41.0 多约 128–130KB，对 libplacebo 要求 ≥ 7.360.1）不选；原因见计划 | 计划 T0.2 修订表（不复跑） |

**b3 补丁全文**（`git diff` 口径，已在 v0.41.0 上验证）：

```diff
--- a/meson.build
+++ b/meson.build
@@ -251,10 +251,6 @@ sources = files(
     ## libplacebo
-    'video/out/placebo/ra_pl.c',
-    'video/out/placebo/utils.c',
-    'video/out/vo_gpu_next.c',
-    'video/out/gpu_next/context.c',
--- a/options/options.c
+++ b/options/options.c
-extern const struct m_sub_options gl_next_conf;
-    {"", OPT_SUBSTRUCT(gl_next_opts, gl_next_conf)},
--- a/video/out/vo.c
+++ b/video/out/vo.c
-extern const struct vo_driver video_out_gpu_next;
-    &video_out_gpu_next,
```

**摘掉后 libplacebo 还有没有消费者**：有，但只是纯数据/色彩空间助手。`grep -rl "libplacebo/"` 在打过 b3 的树里仍命中 `video/csputils.h`、`video/mp_image.c`、`video/sws_utils.c`、`demux/demux_mkv.c`、`video/filter/vf_format.c`、`video/image_writer.c`、`video/out/gpu/video_shaders.c`、`filters/f_lavfi.c`、`player/main.c` 等，所以 **libplacebo 依赖摘不掉**（`meson.build:51` `'libplacebo': true` 写死，没有 `-Dlibplacebo` 选项——本文用 `meson.options` 逐条核对：**v0.41.0 里不存在 `libplacebo`、`libplacebo-next`、`libcurl`、`subrandr`、`amf` 这五个选项名**，`doc/notes/2026-07-31-libmpv-slimming-options.md` 里提到的这几项来自 master 且已过期，旧分支 Darwin 补丁用过的 `-Dlibplacebo=enabled -Dlibplacebo-next=enabled` 在 v0.41.0 上会直接 "Unknown option"）。链接后 libplacebo 只保留 **7,000 字节**（text 5,056 + rodata 1,072 + eh_frame 872，S 档链接图实测），而不摘 gpu_next 时多出约 0.78MB（Linux：9,986,608 vs 9,209,384，计划修订表；本文复跑了摘除后的基线 9,209,384，字节完全一致）。

### 2.2 mpv meson 参数表

「验证」同 §1 约定。**`-Dauto_features=disabled` 是本文推荐的总开关**：把所有 `auto` 特性全关，之后只显式打开需要的，构建结果就不再受构建机装了什么库影响。代价见下表风险列。

| 参数 | 作用 | 来源 | 验证 | 风险 / 备注 |
|---|---|---|---|---|
| `--default-library=shared`（得到 `libmpv.so` / `libmpv-2.dll`） | 产物形态 | n6线 CI（`:875`） | L | — |
| `--prefer-static` | 依赖优先静态；Windows 必须（mingw DLL 不能带未定义符号） | n6线 Windows/Android/iOS；L 也用 | L | Darwin 下会让 `dependency('iconv')` 探测失效（meson#12455，README L32 ⑥） |
| `--buildtype=minsize -Ddebug=false -Db_ndebug=true` | `-Os`、去 `-g`、去 assert | n6线（Linux 实测 −286,624B，README L900 一节） | n6:C；n9:L | `minsize` 会把 `debug` 悄悄改回 true，必须显式 `-Ddebug=false`（README L900 一节、iOS 节同款坑） |
| **`-Db_lundef=true`** | 链接时对 libmpv 自己的未解析符号报错 | **新增** | **L**：链接通过，`nm -D --undefined-only` 除 glibc 外 0 个 | **mpv 自己的 `meson.build:9` 在 `default_options` 里写了 `b_lundef=false`**，实际链接行里没有 `--no-undefined`，缺符号会被悄悄放过（计划 T0.2 提示过）。实测：默认 `b_lundef=false` 时链接行里是 `-Wl,--allow-shlib-undefined`（本文早期若干变体的 `build.ninja` 可见），加 `-Db_lundef=true` 后换成 `-Wl,--no-undefined`（S、MAXL1B 实测）；无论哪种，最终判据都用 `nm -D --undefined-only` |
| `-Dauto_features=disabled` | 关闭所有 `auto` 特性 | v9旧评估脚本 / WHEP 评估（`mk.sh`），n6线没有 | **L**（全部变体）；Android：B（评估脚本 `and-mpv.sh`，编过未跑）；Windows/iOS：T | **必须与现产物逐项对账**：n6 线是"auto 找到什么算什么"，不知道现 Android/Windows 产物里 `iconv`/`zlib`/`jpeg`/`rubberband`/`lcms2`/`uchardet`/`libarchive` 本来是 yes 还是 no。尤其 `iconv`+`uchardet`：关了以后**非 UTF-8 外挂字幕（GBK/BIG5 等）不再转码**——`misc/charset_conv.c:152` 的 `mp_iconv_to_utf8` 在 `!HAVE_ICONV` 时整段不编译，原样返回；iOS/macOS 的 Darwin 补丁已经这样关了（README L32–33 ⑥⑦，CI 绿但无人验证字幕编码），Android 上是否开：**产品拍板** |
| `-Dgpl=false` | 保持 LGPL | n6线 | n6:C；L | 不是体积手段（README L806 一节：只小 4,288B）；`-Dgpl=false` 对 libplacebo 无影响 |
| `-Dcplayer=false -Dlibmpv=true -Dtests=false -Dbuild-date=false` | 只出 libmpv；可复现构建 | n6线（前三项）；`build-date` 新增 | L | — |
| `-Dmanpage-build=disabled -Dhtml-build=disabled -Dpdf-build=disabled` | 不生成文档 | n6线（Windows `libmpv-win32-video-cmake` 需要 `pdf-build=disabled`，README L1098） | n6:C | `auto_features=disabled` 下 `manpage-build` 也被关，冗余但无害 |
| **`-Dgl=enabled -Dplain-gl=enabled`** | OpenGL render API 的唯一实现（`libmpv_gl.c`、`ra_gl.c`） | n6线（默认即开）；Android v9旧明确写入 | L（编出 `libmpv_gl.c.o`/`ra_gl.c.o`，`used-syms.txt` 含 `mpv_opengl_init_params`/`mpv_opengl_fbo`，**media_kit/mova 的 FFI 用到 OpenGL render API**） | **绝对不能关**：`render.h:468-470` 只有 `opengl`/`sw` 两种 API type；`meson.build:1266-1272` 里 `plain-gl` 就是把 `features['gl']` 置真、从而把 `libmpv_gl.c` 等加入 sources 的开关，`auto_features=disabled` 时必须显式 `enabled`。**旧分支 Windows v9 的 `-Dgl=disabled -Dd3d11=enabled -Dshaderc=enabled`（`build-win-libmpv-v9.sh`）把 OpenGL render API 整个关了，只剩软渲染，与 libmpv 的 OpenGL render API 不兼容（media_kit 使用该 API 的依据：`used-syms.txt` 含 `mpv_opengl_init_params`）——该脚本的 Windows 体积数字（13.60→11.91MB）不能直接当本线参考**（该脚本验证的是 mpv 自己的 `vo=gpu` d3d11 上下文，与 libmpv render API 是两条路径；media_kit Windows 实际走哪条：未核实源码，以 `used-syms` 含 OpenGL 类型为据） |
| Android：`-Degl-android=enabled -Dandroid-media-ndk=enabled -Dopensles=enabled -Daudiotrack=enabled` | MediaCodec 硬解桥（`hwdec_aimagereader.c`）+ 音频输出 | v9旧（bug #3）+ 评估 `and-mpv.sh` | B（编过）；真机：v9旧在 Huawei 上起播正常（`build-android-libmpv-v9.sh` 头注释） | `hwdec_aimagereader.c` 无条件调用 `ra_is_gl()`，缺 GL 则链接期缺符号（v9旧 bug #3）。`audiotrack`/`opensles` 的取舍：mova 实际用哪个音频后端**未核实** |
| Android：`-Daaudio=disabled` | 关 AAudio | v9旧：NDK r25c 的 `aaudio/AAudio.h` 缺 `AAUDIO_FORMAT_IEC61937`，`ao_aaudio.c` 编译失败 | B-v9 | v0.41.0 新增的 AAudio 后端（`RELEASE_NOTES` "ao/aaudio: implement native AAudio backend"）对延迟的帮助**未验证**；换更新的 NDK 后可重新评估 |
| Android 链接：`-Dc_link_args="-landroid -llog -lEGL -lc++_static -lc++abi …"` | 系统库 + 静态 C++ 运行时 | v9旧（bug #2：`__gxx_personality_v0` 找不到）+ 评估 `and-mpv-lto.sh` | B / v9旧真机 | NDK 的 clang 驱动不会自动带静态 C++ 运行时；libass 栈里的 harfbuzz 是 C++（本文构建用 `-fno-exceptions -fno-rtti`，仍需 `operator new/delete`），若再叠加 libplacebo 的 glslang/shaderc 才真需要异常运行时 |
| Windows：`-Dd3d-hwaccel`、`-Dgl-win32`、`-Degl-angle*`、`-Dwasapi`、`-Dd3d11` 等 | 取决于 media_kit 的 GL/ANGLE 路径 | — | T | **本文没有核实 Windows 的 hwdec 路径**（零拷贝的 `hwdec_d3d11egl.c` 需要 `egl-angle`，n6 线 CI 只传了 `buildtype` 等通用项，其余 auto）；任何对这几项的改动都要对账现有产物，并用 `mpv -v` 日志确认 `Using hardware decoding (d3d11va…)` |
| Darwin：`-Dios-gl -Dvideotoolbox-gl -Davfoundation -Daudiounit -Dcoreaudio …` | iOS/macOS | Darwin 补丁 `mk-pkg-mpv`（`MACOS_VIDEO_OPTIONS`/`IOS_VIDEO_OPTIONS`） | C | **未核实**这些在 v0.41.0 的名字：本文只核对到 `meson.options` 里它们全部存在（`ios-gl videotoolbox-gl videotoolbox-pl avfoundation audiounit coreaudio macos-*` 逐个 `grep` 通过），没有跑 |
| `-Diconv=disabled -Duchardet=disabled` | 见上 | Darwin 补丁（README L32–33 ⑥⑦） | C | `meson.build:750-754`：`uchardet` 硬依赖 iconv，关 iconv 必须一并关它 |
| `-Dlua=disabled -Djavascript=disabled -Dcplugins=disabled -Dvapoursynth=disabled -Dlibarchive=disabled -Dlcms2=disabled -Dzimg=disabled -Drubberband=disabled -Djpeg=disabled -Dcdda=disabled -Ddvbin=disabled -Ddvdnav=disabled -Dlibbluray=disabled -Dx11-clipboard=disabled -Dlibavdevice=disabled -Dvector=disabled` | 去脚本引擎/光盘/专业滤镜等 | `doc/notes/2026-07-31-libmpv-slimming-options.md` §1 | `auto_features=disabled` 一并生效；L | `rubberband`：笔记要求关前实测变速不变调——**本文已测（§8.3）：rubberband 关闭时，默认 `audio-pitch-correction=yes`（mpv 自带 scaletempo）下 1.5x/2.0x 的 440Hz 正弦仍输出 440.0/440.2Hz，关掉 pitch-correction 才变成 659.7/879.6Hz**，所以可放心关；`lcms2`：ICC 色彩管理，关了无影响消费级播放 |
| 音频/视频输出后端（`alsa pulse pipewire jack sndio oss-audio wayland x11 xv drm gbm vaapi* vdpau* cuda-* caca sixel sdl2-*`…） | 桌面 Linux 窗口系统/音频 | 笔记 §2 | `auto_features=disabled` 下全关；L | **Linux 桌面若要真出声/硬解**，需要按目标发行版重新打开 `alsa`/`pulse`/`pipewire`/`vaapi`；本文 Linux 链路用 `ao=null` + 软渲染，**没有验证真实音频输出** |
| `-Dc_args="-ffunction-sections -fdata-sections"` | mpv 本体分节，供 `--gc-sections` | n6线 | n6:C；L | **只对 mpv 本体有效**；Windows 上给 ffmpeg/dav1d 分节是净负收益（§3），给 mpv 本体有 −424,448B |
| `-Dc_link_args="-Wl,--gc-sections -Wl,--exclude-libs,ALL -Wl,--version-script=mpv.ver"`，`mpv.ver` = `{ global: mpv_*; local: *; };` | 链接期回收；只导出 `mpv_*` | 评估（`mk.sh`，本文复跑） | L：导出符号 54 个，`used-syms.txt` 的 28 个函数全部在，14 个类型名只是 `used-syms` 里的类型条目（不是符号） | n6 线用 `-fvisibility=hidden`（README L866 起，导出 4,003→443）；version script 方案更彻底（导出 54）。两者可以共存。Windows 不适用（PE 默认不导出，README L1137） |
| Linux：`-Wl,-z,pack-relative-relocs` | RELR 相对重定位压缩 | **新增** | **L：S 10,274,152 → 9,909,688（−364,464，−3.5%）**；LTO 之上再叠 −499,712 | **加载需要 glibc ≥ 2.36**（`GLIBC_ABI_DT_RELR`）；本机 glibc 2.43 通过。Android 等价手段是 lld 的 `--pack-dyn-relocs=relr`，是否需要 `--use-android-relr-tags`、最低 API：**未测未核实**。仅 Linux 桌面 X 档 |
| `-static-libstdc++ -static-libgcc`（Linux） | libharfbuzz 是 C++，避免引入 `libstdc++.so` 依赖 | 评估 `mk.sh` | L（`NEEDED` 只剩 `libm.so.6 libc.so.6`） | — |

### 2.3 libplacebo（v7.360.1）`meson_options.txt` 全部 19 个选项

读自 `/root/w/mpvt/libplacebo-361/meson_options.txt`。**本文 Linux 构建用的最小静态配置**（也是 `plc.sh`/`build-plc.sh` 的参数）：

```
meson setup plc-build --prefix=… --libdir=lib --default-library=static --buildtype=minsize \
  -Db_ndebug=true -Ddebug=false \
  -Dvulkan=disabled -Dopengl=disabled -Dd3d11=disabled -Dglslang=disabled -Dshaderc=disabled \
  -Dlcms=disabled -Ddovi=disabled -Dlibdovi=disabled -Dxxhash=disabled -Dunwind=disabled \
  -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false \
  -Dc_args="-ffunction-sections -fdata-sections -fPIC" -Dcpp_args="-ffunction-sections -fdata-sections -fPIC"
```
结果 `libplacebo.a` 4,026,642 字节，链接后保留 7,000 字节（L）。

| 选项 | 默认 | 推荐 | 说明 / 依据 |
|---|---|---|---|
| `vulkan` | auto | **disabled** | 旧分支 Android 实测 Vulkan 要同时开两个 GPU 上下文（MediaCodec 桥必须有 GLES），CPU +27%、PSS +70MB（`build-android-libmpv-v9.sh` 头注释，R-v9 Huawei）；且 mpv 摘 gpu_next 后无 libplacebo GPU 消费者 |
| `vk-proc-addr` / `vulkan-registry` / `vulkan-sdk` | auto / '' / '' | 不设 | 只在 vulkan 或 glslang 路径有意义；旧分支用 `-Dvulkan-sdk` 借道给 `find_library` 指前缀（`build-android-libmpv-v9.sh` libplacebo 段）——本线不需要 |
| `opengl` | auto | **disabled（B3 下）** | gpu_next 摘掉后 libplacebo 的 GL 后端无调用者（mpv 用自己的 `ra_gl`）。**Android 评估（6,768,032）用的是 `-Dopengl=enabled`**（`runlto.sh`），所以 Android 数字里多了这一块；改成 disabled 的收益在 Android 上**未测** |
| `gl-proc-addr` | auto | 不设 | opengl 关闭后无意义 |
| `d3d11` | auto | **disabled** | 需要 glslang+spirv-cross；mpv 摘 gpu_next 后无消费者。旧分支 Windows v9 开了它（还带 shaderc），该路径不是 media_kit 的渲染路径（见 §2.2 `gl` 行） |
| `glslang` / `shaderc` | auto / auto | **disabled** | 需要 SPIR-V 编译器；去掉后 libplacebo 不再有 C++ 源，省掉 glslang（旧分支 Android 为它编过 `-DENABLE_OPT=OFF` 的 glslang 14.3.0）、shaderc（Windows v9 有一份自带 glslang+SPIRV-Tools 的重复拷贝，一直没去重，README/脚本头注释）。**没有 libplacebo 的 C++ 就不再需要 `-lc++_static` 来满足 libplacebo**（harfbuzz 仍是 C++） |
| `lcms` / `dovi` / `libdovi` | auto | **disabled** | ICC / 杜比视界 reshaping，mova 不用 |
| `xxhash` / `unwind` | auto | **disabled** | 可选库，纯为避免被构建机探测到 |
| `demos` / `tests` / `bench` / `fuzz` | true / false / false / false | **false 全部** | `demos` 默认 true，必须关；mpv 的 `default_options` 也传了 `demos=false` |
| `debug-abort` | false | false | 调试用 |

**未验证项**：libplacebo 在 Android 上 `-Dopengl=disabled` 能否链接（B3 摘除后理论无依赖，只在 Linux 验证）；在 Windows/iOS 上的最小静态构建（`d3d11=disabled` 在 MinGW 下）：未跑。

### 2.4 105 个 `meson.options` 选项的分类（v0.41.0，逐个核对过名字）

**必须开（嵌入场景）**：`gl`（默认 `enabled`）、`plain-gl`、`libmpv`；Android 另需 `egl-android`、`android-media-ndk`、（音频）`opensles`/`audiotrack`；Darwin 另需 `ios-gl`/`videotoolbox-gl`、音频后端（`avfoundation`/`audiounit`/`coreaudio`）；Windows：未核实（见上）。

**可关且已默认被 `auto_features=disabled` 覆盖**（本文 Linux 实测全关后 28 个导出函数、软渲染、12 类样本、libass 渲染都正常）：`cdda cplugins dvbin dvdnav iconv javascript jpeg lcms2 libarchive libavdevice libbluray lua rubberband uchardet vapoursynth vector zimg zlib x11-clipboard alsa jack pipewire pulse sndio oss-audio caca sixel drm gbm wayland x11 xv vaapi* vdpau* vulkan shaderc spirv-cross egl-x11 egl-wayland egl-drm gl-x11 cuda-* d3d-hwaccel d3d9-hwaccel gl-dxinterop* win32-smtc …`。其中带"功能后果"的只有 `iconv`+`uchardet`（字幕编码）、`rubberband`（变速不变调：已实测，关闭无影响，§8.3）、`zlib`（mpv 自己用 zlib 的地方未梳理，**未核实**）、`jpeg`（截图 jpg；mova 只用 png）。

**默认 disabled、不用管**：`pthread-debug sdl2-gamepad uwp openal sdl2-audio gl-x11 sdl2-video html-build pdf-build`。

**关不掉**：`libass`（`meson.build:32` `dependency('libass', version: '>= 0.12.2')` 无 feature 选项，`:50` `'libass': true` 写死；`sub/osd_libass.c:205` 等恒编译）；`libplacebo`（`:29`、`:51`）；ffmpeg 六个库；`video/out/gpu/*` 渲染抽象（`gpu/spirv.c` 等恒编译）。旧分支曾把 libass 从 mpv 里整个摘掉并真机验证"可行"（改 `sub/osd_libass.c`/`sd_ass.c`/`ass_mp.c` 为桩，`build-win-libmpv-v9.sh` 头注释，B-v9），**但"外挂 SRT/ASS 随播放时间自动同步"依赖 libass，且 README 字幕栈评估（L756–805）已决定保留**，见 §6。

**v0.41.0 里不存在的选项名**（别再写）：`libplacebo`、`libplacebo-next`、`libcurl`、`subrandr`、`amf`、`cuda`。

## 3. 编译器 / 链接器级手段

### 3.1 逐项表（只列实际可用且有依据的；收益是"该项单独/按所述口径"的字节差）

| 手段 | 平台 | 来源 | 验证 | 实测收益（口径） | 风险 / 备注 |
|---|---|---|---|---|---|
| **`--enable-small`**（`-Os`，且切到 `CONFIG_SMALL` 的小表实现） | 全平台 | n6线（Android 上游本来就带；README L662） | n6:C；**n9:L：去掉它 S 档 10,274,152 → 14,689,536（+4,415,384，+43%）** | 全文**最大的单项**（本文 NOSMALL 变体） | **WHEP 计划 §4 评估基线（9,209,384 等）用的 ffmpeg 没带 `--enable-small`**（`ffbuild.sh`：`--optflags=-Os` 而无 `--enable-small`），所以那些绝对数字和 n6 线产品不可直接比，只能比同口径内的相对增量 |
| `-Os`（`buildtype=minsize` 作用于 mpv/dav1d/freetype/…） | 全平台 | n6线 | Android：−348KB（README L86 定稿表，从 `-O3` 降到 `-Os`）；Linux mpv：**−286,624B（−3.7%）**（README L900 一节）；本文 mbedtls：`MinSizeRel`(-Os) 相对预编译 `-O2`：**−102,432B** | 见左 | 不要和 `-O3` 混用；mbedtls CMake `Release` 自己写 `-O2`（§4.2） |
| `-ffunction-sections -fdata-sections` + `-Wl,--gc-sections` | **ELF（Android/Linux）**：全组件；**COFF（Windows）：只给 mpv 本体** | n6线 | Android：−54KB（README L86 表）；Windows：mpv 本体 −424,448B | Windows 给 ffmpeg 加：**+124%**（14.70→32.58MiB）；给 dav1d 加：+62,976B（`…windows-libmpv-slim.md` §12 发现 2） | 同一手段在 ELF/COFF 上方向相反，**不能把 Linux/Android 的 flags 照抄到 Windows** |
| `-fvisibility=hidden` | ELF、Mach-O | n6线 | Android：**−669KB（单项最大，导出符号 4692→610）**（README L86 表）；Linux：与分节、`--disable-symver` 合计 −368,608B，导出 4,003→443（README L866 一节） | 见左 | **Windows 零收益**（PE 默认不导出，byte-for-byte 相同，README L1137）；mpv 自己用 `MPV_EXPORT` 标公开 API，不会被误伤 |
| `-Wl,--exclude-libs,ALL -Wl,--version-script=mpv.ver`（`{ global: mpv_*; local: *; };`） | ELF | 评估 `mk.sh`（本文复跑） | **L：全部变体导出恰好 54 个符号**，`used-syms.txt` 的 28 个 `mpv_*` 函数全在 | 与 visibility 同向，不再单列 | Windows/Mach-O 不适用 |
| **LTO**：ffmpeg `--enable-lto` + mpv `-Db_lto=true`（+ 依赖库各自 `-flto`） | Android（CI+真机）；**Linux（本文新测）**；iOS（旧分支 CI）；**Windows 不上** | n6线 Android；旧分支 iOS | Android：**−521KB**（README L86，整链：ffmpeg+dav1d+freetype+harfbuzz+libass+mpv，fribidi 除外）；**Linux x86_64 L：10,274,152 → 10,143,000（−131,152，−1.3%）**（仅 ffmpeg+mpv，依赖库未 LTO）；iOS 旧分支：10,967,592→10,666,384（−301,208，−2.7%，CI run 31456135129，B-v9）；**Windows：+12,288B（负收益）**，且已用 `gcc-ar/gcc-ranlib` 排除假阴性（`…windows-libmpv-slim.md` §12 Task 7 记录） | **meson 交叉编译坑**：`b_lto=true` 写进 cross file 会泄漏到宿主机原生工具（fribidi 的 `gen-unicode-version` 报 `undefined symbol: main`），要 `--native-file`（`b_lto=false`），fribidi 还得命令行 `-Db_lto=false`（README L202 关键单项 3；`libmpv-android-video-build.patch` 已处理）。n6 README 记的"Linux LTO 失败（NASM 对象与 LTO 混链报 `-fPIC`）"在 n9.0.2 + gcc 15 + `--enable-pic` **不复现**（本文 LTO、MAX、MAXL1 变体链接通过） |
| `-Wl,--icf=safe` | Android（lld） | 上游 `libmpv-android-video-build` 的 `LDFLAGS` 已带 `-Wl,-O1,--icf=safe`（补丁 build.sh hunk 上下文可见） | Android：随上游，未单独测 | — | Linux 实测相反：gold + `--icf=all` **+8,544B**，bfd 默认最优（README L923）；Windows：lld 的 MinGW/COFF 端口不接受 gcc 驱动自动注入的 `--allow-shlib-undefined`，不可用（`…windows-libmpv-slim.md` §12）。**本文 WSL 没有 lld/gold，Linux 上未复测**（未测） |
| `-Wl,-z,max-page-size=16384` | Android | 上游已带 | — | 16KB 页兼容所需，**不要为省几 KB 去掉** | — |
| **`-fno-asynchronous-unwind-tables -fno-unwind-tables`**（全链路：ffmpeg + 各依赖 + mpv） | Linux/Android/Mach-O 理论可；**Windows x64 不可** | **新增** | **Linux L：S 10,274,152 → 9,385,320（−888,832，−8.65%）**；`.eh_frame`+`.eh_frame_hdr` 957,380B → 57,972B（MAXL1B 实测节大小）。拆分：只给依赖库+mpv、ffmpeg 不加：9,897,320（−376,832）；ffmpeg 部分另得 −512,000 | Android/iOS：**未测**（arm64 的 `.eh_frame` 占比未知） | 崩溃现场回溯会断：Android tombstone/Crashlytics NDK 靠 `.eh_frame` 展开；这些库内部的帧无法展开（崩溃栈里 libmpv 帧之下丢失）。C++ 异常无影响（harfbuzz 本就 `-fno-exceptions`，libplacebo 无 glslang 后无 C++）。Windows x64 SEH 需要完整 unwind 信息，旧分支实测 −87,552B 仍**不采纳**（`…windows-libmpv-slim.md` §12）。**X 档，需要崩溃上报策略拍板** |
| **`-Wl,-z,pack-relative-relocs`**（RELR） | Linux（glibc ≥ 2.36）；Android 等价是 lld `--pack-dyn-relocs=relr` | **新增** | **Linux L：S → 9,909,688（−364,464，−3.5%）**；叠 LTO 后 9,774,440（−499,712 vs S）；`.rela.dyn` 374,352B → 480B + `.relr.dyn` 8,072B | Android：**未测未核实**（是否要 `--use-android-relr-tags`、最低 API、minSdk 影响） | glibc < 2.36 的发行版无法加载（`GLIBC_ABI_DT_RELR`）；本机 glibc 2.43 通过。Linux 桌面 X 档 |
| `-fcf-protection=none -fno-stack-protector` | **仅 x86 Linux gcc（Ubuntu 默认开）** | **新增** | **Linux L：−208,976B（−2.0%）**（全链路 `HARDEN2`） | NDK clang 默认不开，Android 无此收益 | 去掉 CET/栈保护是安全加固退化，**不推荐**，仅记录"Ubuntu 默认 flags 占 2%" |
| `-Oz`（只给 mpv 本体） | gcc/clang | n6线 Windows 实验（`2026-09-17-windows-libmpv-slim.md`） | **Linux L：−20,480B（−0.2%）**；Windows CI：−11,776B；Windows 本地曾测 −1,575,424B 但 CI 复现失败，差异**未查明**（README Windows 行；`…windows-libmpv-slim.md` §12 发现 3） | — | 收益在真实 CI 上不稳，不采纳 |
| `-fno-tree-vectorize`（n9 起 gcc ≥ 13 默认开自动向量化，`configure:8116-8128`） | gcc | 新增 | **Linux L：与 S 字节完全一致（10,274,152）** | 无 | `--enable-small` 下无差别，不需要处理 |
| `--disable-x86asm` | x86 | 新增 | Linux L：−1,531,904B（−14.9%） | — | **不推荐**：丢全部 SIMD；ARM 上 `--disable-asm` 同理，arm64 的 `--disable-runtime-cpudetect` 实测零收益（README L217） |
| `-fomit-frame-pointer` | Android | 旧试验 | Android A/B：**加了反而大**，移除后 6,190,732→6,050,104（−2.27%，README L23 Android arm64 行）；Windows clang 也已去掉 | — | 不要加 |
| strip | 全平台 | n6线 | — | Android `llvm-strip --strip-all`；Linux `strip --strip-all`/`-s`；Windows mingw `strip -s`；Darwin `strip -S -x`（README L678 起：6.86→5.99→5.96MiB） | strip 前先做符号核验（Windows 的 `nm --defined-only` 检查必须在 strip 之前，workflow `:1232-1248`，`strip -s` 在 `:1248`） |
| UPX（Windows DLL） | Windows | 网上通用方案 | **未测** | 号称压到 ~26% | 稳定性/杀软误报/`LoadLibrary` 与 Dart FFI 加载未验证，不建议（README Windows"下一步"） |
| `-Wl,-z,norelro` / `-Wl,--build-id=none` / `-Wl,-z,noseparate-code` | ELF | — | **未测** | 预期各 ≤ 数十 KB（页对齐/元数据） | 去 RELRO 是安全退化，不推荐 |

### 3.2 本文 Linux x86_64 实测汇总（同一工具链、同一 `strip -s`、同一 28 函数导出集）

基线与口径：

- **评估基线（复跑）**：WHEP 计划 T0.2 修订表里的"v0.41.0 摘 `vo_gpu_next`" **9,209,384**。本文用同一 `mk.sh`（输出路径改到 `extreme/`）、同一 `src-v041-B3`、同一 `eval/ffos-inst`（**最小 ffmpeg 子集**：6 个解码器、9 个 demuxer、无字幕/`flv`/`rtmp`/`dav1d`、无 `--enable-small`）、同一 `eval/plc-v360-min` 重跑，得到 **9,209,384，字节一致**——证明工具链未漂移。
- **S 档 = 本文推荐的安全档（Linux 版）**：ffmpeg n9.0.2 白名单（§1.3，含 `libdav1d`，23 解码器 + 1 编码器 + 11 parser + 16 demuxer + 17 协议 + 12 bsf，零 filter）+ 静态 mbedtls 3.6.7（预编译 `-O2`+分节）+ zlib 1.3.1 + dav1d 1.5.1（`bitdepths=8,16`）+ freetype 2.13.3（裁模块）+ fribidi 1.0.16 + harfbuzz 10.4.0 + libass 0.17.4 + libplacebo 7.360.1 最小静态 + mpv v0.41.0 + b3。**S 档 = 10,274,152B**，比评估基线大 1,064,768B（+11.6%），因为装了一整套真实产品白名单（含 dav1d 软解 1.58MB、字幕解码器、flv/rtmp/rtp、`--enable-small` 抵消了一部分）。

| 变体（只改一个变量，除非注明） | stripped 字节 | Δ vs S | % |
|---|---:|---:|---:|
| 评估基线（最小 ffmpeg，复跑） | 9,209,384 | （不同口径） | — |
| **S** | **10,274,152** | 0 | 0 |
| LTO（ffmpeg `--enable-lto` + mpv `b_lto`） | 10,143,000 | −131,152 | −1.28% |
| RELR（`-z pack-relative-relocs`） | 9,909,688 | −364,464 | −3.55% |
| LTO + RELR | 9,774,440 | −499,712 | −4.86% |
| unwind 表全链路去除（UNWIND2） | 9,385,320 | −888,832 | −8.65% |
| 　└ 仅依赖库+mpv，ffmpeg 未加（首次误跑，留作拆分） | 9,897,320 | −376,832 | −3.67% |
| freetype 全模块（仅去 bzip2）= 对照"裁模块" | 10,409,320 | **+135,168** | +1.32%（即裁模块 −135,168） |
| `-fcf-protection=none -fno-stack-protector`（HARDEN2） | 10,065,176 | −208,976 | −2.03% |
| `-fno-tree-vectorize`（NOVEC） | 10,274,152 | 0 | 0 |
| mpv 本体 `-Oz` | 10,253,672 | −20,480 | −0.20% |
| **去掉 `--enable-small`**（NOSMALL） | 14,689,536 | **+4,415,384** | **+42.97%** |
| `--disable-x86asm`（NOASM） | 8,742,248 | −1,531,904 | −14.91% |
| **去掉 dav1d**（NODAV1D，`av1.mp4` 播放失败 err=-16） | 8,672,520 | −1,601,632 | −15.59% |
| `--enable-bsfs`（全开 51 个 bsf，n6 线 Android 现状） | 10,794,344 | **+520,192** | +5.06% |
| 加 `ac3,eac3` 解码器 | 10,315,112 | +40,960 | +0.40% |
| 加 `rtsp,sdp,rtp` demuxer（带出 `asf`、`rm`） | 10,429,800 | +155,648 | +1.51% |
| WHEP 件：`whip` muxer + `rtp,sdp` demuxer + `dtls,srtp` 协议（无 `whep.c`） | 10,454,376 | +180,224 | +1.75% |
| mbedtls `-Os`（默认配置，MBsbase） | 10,171,720 | −102,432 | −1.00% |
| mbedtls `-Os` + L1 裁剪（MBsl1） | 10,057,008 | −217,144 | −2.11% |
| mbedtls `-Os` + L1 + 关 TLS1.3（MBsl1t，**TLS1.3-only 服务器失败**） | 9,958,704 | −315,448 | −3.07% |
| **MAX = LTO + unwind 全去 + RELR** | 8,951,144 | −1,323,008 | −12.88% |
| MAX + mbedtls L1（**MAXL1，推荐的 Linux 极致档**；加 `-Wl,--no-undefined` 重链接的 MAXL1B 字节数相同） | **8,754,480** | −1,519,672 | **−14.79%** |
| MAX + mbedtls L1 + 关 TLS1.3（MAXMB，不推荐） | 8,656,176 | −1,617,976 | −15.75% |
| MAX 去 dav1d（MAXND，**AV1 不可播**） | 7,410,960 | −2,863,192 | −27.87% |
| MAX 去 dav1d + mbedtls L1 + 关 TLS1.3（MAXNDMB，极限下限） | 7,111,896 | −3,162,256 | −30.78% |

> 不可相加：LTO 会吃掉一部分 unwind/visibility 带来的死代码，RELR 与分节也有交叠；所有"组合"行都是**整体重编译链接后单独量的**，不是加减得出的。**MAXL1 对 S 的总差 −1,519,672 不等于单项之和**（−131,152 − 364,464 − 888,832 − 217,144 ≠ −1,519,672，因为 mbedtls 对照基线是 `-O2` 预编译库，MAXL1 里的是 `-Os` 重编库）。

### 3.3 S 档体积构成（`-Wl,-Map` 按输入归档 × 节类型归因，stripped 10,274,152B 对应的非 .bss 部分合计 10,215,827B）

| 归档 | text | rodata | 合并字符串 | data.rel.ro | .eh_frame | 非 bss 合计 | 备注 |
|---|---:|---:|---:|---:|---:|---:|---|
| libavcodec | 2,622,892 | 211,738 | 16 | 66,096 | 302,256 | **3,202,998** | 另有 .bss 1,223,242（运行期内存，不占文件） |
| mpv 本体 | 717,233 | 41,479 | 332,578 | 242,288 | 270,788 | **1,612,080** | 合并字符串（`.rodata.*.str1.1`）整个程序的字符串表 332,578 归在第一个对象上，**逐 .o 归因不可信** |
| libdav1d | 1,413,522 | 119,159 | 0 | 512 | 45,256 | **1,578,469** | `bitdepths=8,16` + x86 asm |
| libharfbuzz | 392,042 | 108,312 | 0 | 816 | 79,824 | 582,786 | |
| libswscale | 454,777 | 8,738 | 0 | 5,272 | 43,328 | 512,115 | n9 新 ops 后端 |
| libavformat | 377,029 | 20,761 | 68 | 46,080 | 50,432 | 494,434 | |
| libavutil | 350,703 | 13,881 | 0 | 73,768 | 37,792 | 476,180 | `tx_*` 变换表；另有 .bss 1,063,372 |
| libfreetype（裁模块） | 233,443 | 82,891 | 0 | 11,848 | 34,224 | 362,406 | |
| mbedtls 三库（预编译 `-O2`） | 397,343 | 40,275 | 28,518 | 26,096 | 59,472 | 551,736 | |
| libass | 143,109 | 1,884 | 0 | 336 | 15,224 | 160,729 | |
| libfribidi | 6,787 | 85,632 | 0 | 0 | 1,104 | 93,579 | |
| libswresample / libavfilter / libz / libplacebo | — | — | — | — | — | 78,091 / 58,683 / 42,805 / **7,000** | |
| **合计** | **7,247,784** | 752,741 + cst 4,996 | 361,180 | 485,840 | **957,380** | **10,215,827** | .bss 2,536,146 不占文件 |

最终 ELF 节（S）：`.text` 7,258,738、`.rodata` 1,137,152、`.eh_frame`+`.eh_frame_hdr` 957,380、`.data.rel.ro` 502,128、`.rela.dyn` 374,352。MAXL1B：`.text` 7,064,386、`.rodata` 1,098,048、`.eh_frame`+hdr 57,972、`.data.rel.ro` 487,104、`.relr.dyn` 8,072。

**与用户给的"已知大项分布"对照**（口径不同，不要直接比）：libavcodec 4.33MB / mpv 2.13MB / libavutil 1.6MB / libswscale 1.1MB / libass 栈 1.55MB / mbedtls 0.55MB / freetype 全模块 487KB 可裁，来自评估基线（最小 ffmpeg，**无 `--enable-small`**，含 `.bss`/链接前口径，具体归因脚本是 `mapsum.py`）。本文的数字是链接后保留（含 eh_frame、不含 .bss）：mbedtls 0.55MB 与之吻合；freetype "可裁"本文端到端实测为 135,168B（裁后链接保留 362,406B；全模块版的保留量 497,574B 是 362,406+135,168 推算，未单独出链接图），与 487KB 的差别在于那份数字是"全模块 .a/链接前"。

### 3.4 各平台差异

| 平台 | 工具链 | 要点（均为 n6 线现状，n9 迁移同样适用） |
|---|---|---|
| Android | NDK r25c（clang 14.0.7），`media-kit/libmpv-android-video-build @1ecf510` + `libmpv-android-video-build.patch` | meson cross file `buildtype=minsize`、`b_lto=true`、`-ffunction-sections -fdata-sections -fvisibility=hidden`、`--gc-sections`；`--native-file` 关掉宿主机 LTO；fribidi `-Db_lto=false`；libass/libxml2/mbedtls 走 make 的 `CFLAGS="-fPIC -Os … -flto -fomit-frame-pointer"`（含 `-fomit-frame-pointer`，与 README L23 的 A/B 结论是否矛盾见本节末说明）；dav1d `-Dbitdepths=8` |
| Windows | MSYS2 MINGW64；ffmpeg/dav1d 用 gcc，**mpv 单独用 clang**（gcc 16.2.0 miscompile） | ffmpeg 不分节、不 LTO、不 visibility；mpv 本体分节 + gc-sections；`-Wl,-Bstatic -lstdc++ -lwinpthread -Wl,-Bdynamic` 保自包含；`-Wl,-Map` 路径必须 `cygpath -m`；strip 前做符号核验 |
| iOS / macOS | Nix + 固定 Xcode（`media-kit/libmpv-darwin-build` + `libmpv-darwin-build-mova-slim.patch`） | `-Dbuildtype=minsize -Ddebug=false -Db_ndebug=true`；ffmpeg `-Os -fvisibility=hidden -ffunction-sections -fdata-sections`、`-Wl,-dead_strip`；**meson 命令行的 `-Dc_args=` 是替换而不是追加 cross file 里的 `-arch/-isysroot/-miphoneos-version-min`**（libpng 因此 `cc.get_define('ZLIB_VERSION')` 失败，README L36 记录），所以 visibility/分节/dead_strip 要写进 Nix 生成的 cross file 而不是命令行 |
| Linux | gcc 15（本文）/ ubuntu-22.04 runner（CI） | ffmpeg 静态、系统库动态（CI 现状）；本文为同口径把 libass 栈/mbedtls/dav1d/zlib 都做成静态；`-static-libstdc++ -static-libgcc`；n6 线 CI 上 `-fvisibility=hidden` 配 `--gc-sections` |

> **关于 Android 补丁里的 `-fomit-frame-pointer`**：上面这条我在对账时发现 README（L23）说 `-fomit-frame-pointer` A/B 后"移除（回归）"，而 `libmpv-android-video-build.patch` 里 libass/libxml2/mbedtls 的 `CFLAGS` 仍带 `-fomit-frame-pointer`、`flavors-mova-slim.sh` 的 ffmpeg `--extra-cflags` 里已没有。这是否是有意区别：**未核实**，列入待验证。

## 4. TLS / 加密后端选择

| 平台 | 后端 | 体积（libmpv 内） | 许可 | 对 HTTPS/HLS | 对 WHEP（DTLS-SRTP） | 依据 / 验证 |
|---|---|---|---|---|---|---|
| Android | **mbedtls 3.6.x 自建静态** | 约 0.55MB（本文 L：默认配置、`-O2`+分节的预编译库，S 档链接图 `libmbedcrypto` 299,737 + `libmbedtls` 219,765 + `libmbedx509` 32,234 = **551,736B**；`-Os` 重编同配置 **434,106B**） | LGPLv3（`--enable-version3` 强制，README L638） | n6:R（Android HTTPS 在播）；**n9:L**（本地 TLS 服务器实测，见下） | **需要 `MBEDTLS_SSL_DTLS_SRTP`**（`tls_mbedtls.c:281,306,515,657` 四处 `#if`；本机 `mbed-inst` 头第 2055 行已开），且 ffmpeg 只配 `MBEDTLS_TLS_SRTP_AES128_CM_HMAC_SHA1_80`（`tls_mbedtls.c:515-518`） | media-kit buildscripts 的 `mbedtls.sh` 走 `make CFLAGS="-fPIC -Os -ffunction-sections -fdata-sections -fvisibility=hidden -flto -fomit-frame-pointer"`（`libmpv-android-video-build.patch` 的 mbedtls.sh 一段；mbedtls Makefile 对 `CFLAGS` 的处理方式按惯例理解为替换默认 `-O2`，**未核实**） |
| Windows | **SChannel**（系统） | 0 额外字节；相对 mbedtls −773,632B（`2026-09-17-windows-libmpv-slim.md` §12 Task 1）；旧分支 13.60→12.04MB（−1.56MB，含去掉 mbedtls 全部） | 去掉 version3 → LGPLv2.1 | n6:R | `configure:7619` 对 schannel 做 `SECPKG_ATTR_DTLS_MTU` 检查，**mingw-w64 头是否带该宏：未核实**；没有则 `dtls` 协议静默不启用 | workflow `:1100` |
| iOS / macOS | **securetransport**（系统） | 0 | LGPLv2.1 | n6:C（只验证过编译链接，**握手行为未测**，README L678 起"已知未测项"） | **没有**：`dtls_protocol_deps_any="openssl schannel gnutls mbedtls"`（`configure:4115`）不含 securetransport，L 实测 n9.0.2 如此 | Darwin 补丁 `tls_movaslim_options` |
| Linux | **openssl**（系统动态库；本文实测用静态 mbedtls 以和基线同口径） | 对 `libmpv.so` 自身体积≈0（README L843："+64 字节噪声"） | LGPLv2.1 | n6:C | 可用 | workflow `:836` |

### 4.1 本文新做的功能性实测（HTTPS，基于 mpv 真实 END_FILE 事件，不是墙钟）

方法：本机 `python3` 起 TLS 服务器（自签 `CN=localhost` 证书，`subjectAltName=DNS:localhost`），分别限定「TLS1.2+1.3 都行 / 仅 TLS1.2 / 仅 TLS1.3」，用 `smoke5`（`smoke3` + 环境变量传 `tls-verify`/`tls-ca-file`）经 `libmpv` 软渲染播放 `https://localhost:PORT/h264_aac.ts`，读 `MPV_EVENT_END_FILE` 的 `reason/error`。每个变体各 6 个组合（verify=no，verify=yes+ca-file）。

| libmpv 变体 | 服务器两者皆可 | 仅 TLS1.2 | 仅 TLS1.3 |
|---|---|---|---|
| S（mbedtls 默认配置，`-O2`） | 播放到 EOF，reason=0（verify no / yes+ca 均过） | 同左 | 同左 |
| MBsbase（mbedtls 默认配置，`-Os`） | 同左 | 同左 | 同左 |
| MBsl1（裁剪 L1，见下） | 同左 | 同左 | 同左 |
| **MBsl1t（L1 + 关 TLS 1.3）** | 过（协商到 1.2） | 过 | **失败：reason=4，err=-13（loading failed）** |

这同时验证了 mova 的 `tlsVerify`/`tlsCaFile`（mpv 的 `tls-verify`/`tls-ca-file`）在 n9.0.2 + mbedtls 上仍有效（`stream_lavf.c:201-203` 总是显式把 `tls_verify` 写成 0/1，所以 n9 把 ffmpeg 自己的 `tls_verify` 默认值从 0 改成 1 不影响经 mpv 的 http(s)，见 §1.4）。**范围限制**：只在 Linux x86_64 上跑；没有测 Android 的 CA 来源、没有测 chacha-only 服务器、没有测真公网站点。

### 4.2 mbedtls 裁剪（本文新做，Linux x86_64，全部 `-Os` 同口径对比）

配置裁剪用 mbedtls 自带 `scripts/config.py unset …`，编译 `-DCMAKE_BUILD_TYPE=MinSizeRel`（**坑**：mbedtls 的 CMake 在 `Release` 下自己把优化级别写成 `-O2`，传 `CMAKE_C_FLAGS_RELEASE` 无效；本机预编译库是靠 `CMAKE_C_FLAGS` 给了分节才没丢；本文第一次变体没分节、没 `-Os`，结果比预编译库还大，作废重做）。

| 变体 | 关掉什么 | libmpv stripped | 相对 MBsbase | 功能实测 |
|---|---|---:|---:|---|
| MBsbase | 无（默认配置，仅 `MBEDTLS_SSL_DTLS_SRTP` 打开） | 10,171,720 | — | HTTPS ✓ |
| **MBsl1（L1）** | ARIA、CAMELLIA、DES、CHACHA20/CHACHAPOLY/POLY1305、CCM、RIPEMD160、NIST_KW、DHM；密钥交换 DHE-RSA/DHE-PSK/PSK/RSA-PSK/ECDHE-PSK/ECDH-ECDSA/ECDH-RSA；曲线 secp192r1/224r1/192k1/224k1/256k1、bp256r1/384r1/512r1 | 10,057,008 | **−114,712（−1.1%）** | HTTPS ✓（三种服务器） |
| MBsl1t（L1 + `SSL_PROTO_TLS1_3`） | 再关 TLS 1.3 | 9,958,704 | −213,016（−2.1%） | **TLS1.3-only 服务器失败** ✗ |
| L2/L3（再关 `MBEDTLS_SSL_SRV_C`） | 服务端 | — | — | **ffmpeg 编译失败**：`tls_mbedtls.c:655: implicit declaration of function ‘mbedtls_ssl_conf_dtls_cookies’` |

结论：L1 是 X 档里最安全的 mbedtls 裁剪（−114,712B，三类服务器实测过）；关 TLS1.3 省 ~98KB 但会被只支持 1.3 的服务器拒绝，**不建议**；关 `SSL_SRV_C` 不可行（除非给 ffmpeg 打补丁，**不建议**）。**未测**：chacha-only 服务器、证书链用到 ECDSA-P521 之外的曲线、WHEP 的 DTLS 握手（DTLS 密码套件需 ECDHE + AES-GCM，L1 没动）。Android 上的收益（arm64）：**未测**。

### 4.3 对 WHEP 的含义

1. **iOS/macOS 在 n9.0.2 上依然没有 DTLS 后端**（`configure:4115`），WHEP 本期不含 Darwin，与计划 D3 一致。
2. Windows 的 `dtls` 取决于 `SECPKG_ATTR_DTLS_MTU` 在 mingw-w64 头里是否存在（未核实）；不存在时 `--enable-protocol=dtls` 会**静默无效**（见 §1 顶部警告），验证方式：configure 摘要里必须看到 `Enabled protocols: … dtls …`。
3. Android 自建 mbedtls 必须打开 `MBEDTLS_SSL_DTLS_SRTP`；**不要**对 WHEP flavor 应用 §4.2 的 L2/L3（关服务端）——DTLS 握手角色取决于 SDP `a=setup`，ffmpeg 的 DTLS 路径在 `tls_mbedtls.c` 里同时包含服务端代码。
4. WHEP 信令走 ffmpeg 自己的 http/tls，吃 n9 的 `tls_verify=1` 默认值，需要显式处理证书来源（§1.4）。

## 5. 依赖库裁剪

「实测」栏里的 Linux 数据都是本文在 x86_64 + gcc 15 的 S 档配置上做的对照；Android arm64/Windows 的数据来自 README/旧分支，口径不同，不可相加。

| 依赖 | 现状（n6 线） | 推荐裁法 | 收益 | 验证 | 风险 / 依据 |
|---|---|---|---|---|---|
| **freetype 2.13.3**（libass 栈） | Android：buildscripts 默认（`libmpv-android-video-build.patch` 里没有任何裁模块动作），**没有裁模块**；Windows CI：pacman 版，没裁；旧分支 v9 Windows/Android 脚本裁过 | `modules.cfg` 去掉 `type1 cid pfr type42 winfonts pcf bdf`（字体驱动）、`RASTER_MODULES += raster/svg/sdf`、`AUX_MODULES += lzw/bzip2`；**保留 `truetype cff sfnt autofit pshinter smooth cache gzip psaux psnames`** | **L：−135,168B（10,409,320 → 10,274,152，−1.3%）**；旧分支 Windows 12.04→11.91MB（−130KB）一致 | **L**（`sub-add` 外挂 SRT，DejaVu Sans TTF，`sub-visibility` yes/no 两次渲染像素校验和不同）；Windows 旧分支真机 `sub-add` 随 seek 同步（R-v9） | **OTF-CFF 字体未测**（本机无 .otf；本文保留 cff 驱动）。**旧分支 Android v9 脚本的 `sed` 是对 `include/freetype/config/ftmodule.h` 动手，且连 `cff_driver_class`、`psaux`、`psnames`、`pshinter` 一起删**——① freetype 的 meson/autotools 构建会从 `modules.cfg` 重新生成 `ftmodule.h`（本文 L：meson 下 `bld/ftmodule.h` 由 `builds/meson/parse_modules_cfg.py` 从 `modules.cfg` 生成，改 `modules.cfg` 才生效），那处 `sed` 很可能没起作用；② 即使生效，删 cff 会让 OpenType-CFF 字体（常见于 CJK `.otf`、MKV 内嵌字体）无法加载。**不要照抄 Android v9 的删法**。**坑**：freetype meson 的 `-Dbzip2=disabled` 只关"必须找到"，`dependency('bzip2', required:false)` 仍会探测系统 `bzip2.pc` 并写进 `freetype2.pc` 的 `Requires`（`meson.build:322-331`），导致下游 `Package 'bzip2' not found`；构建时必须隔离 `PKG_CONFIG_LIBDIR` |
| **harfbuzz 10.4.0** | 旧分支 v9：显式关 graphite/cairo/glib/icu/gobject/introspection/benchmark/docs（旧分支实测**字节零变化**，只防漂移） | `-Dfreetype=disabled -Dglib=disabled -Dgobject=disabled -Dicu=disabled -Dcairo=disabled -Dgraphite=disabled -Dtests=disabled -Ddocs=disabled -Dbenchmark=disabled -Dutilities=disabled`（10.4.0 无 `-Dsubset` 选项，传了报 Unknown option） | 0（防漂移） | L（链接+字幕渲染） | libass 不用 `hb-ft`（`grep` 无命中），所以关 freetype 集成可行；链接后 harfbuzz 仍保留 **582,786B**（text 392KB + rodata 108KB + eh_frame 80KB，S 档图），C++ 无异常无 RTTI |
| **libass 0.17.4**（README 用 0.17.3） | v9：`--disable-require-system-font-provider --disable-fontconfig`（零字节变化） | 同左，再加 `--disable-libunibreak` | 零（防漂移） | L | **无字体提供者**：libass 只能用 mpv 的 `sub-fonts-dir`/容器内嵌字体；本机测试靠 `sub-fonts-dir` 才渲染出文字 → **Android/iOS 的默认字体来源要在产品侧配置**（v9 Android 脚本注释 "mova ships its own fonts, never relies on system font discovery on Android"）；libass 在 S 档图里 160,729B |
| **fribidi 1.0.16** | `-Db_lto=false` 硬覆盖（native-file 对它无效，README L202 关键单项 3） | `-Ddocs=false -Dtests=false -Dbin=false` | — | L | 保留 93,579B（85KB 是 Unicode 表），无裁法 |
| **libxml2** | Android buildscripts 会编；Darwin 补丁已去；Windows/Linux 不涉及 | **不启用 `dash` demuxer 就不会链进** | 避免 +740KB（README L168、L646） | n6:C | 若产品要 DASH 才需要 |
| **dav1d** | Android：`-Dbitdepths=8`（`libmpv-android-video-build.patch` 的 `dav1d.sh` hunk）；Windows CI：`-Dbitdepths=8,16`；Linux CI：系统库 | 保留；位深取舍见右 | Android arm64 +671KB（README L177）；**Linux x86_64：−1,601,632B（本文 NODAV1D：10,274,152→8,672,520，`bitdepths=8,16` + x86 asm）** | n6:R（Android 软解兜底成功）；n9:L（`av1.mp4` 播放；去掉后 `av1.mp4` 报 `err=-16 no audio or video data played`，反证测试有效） | **Android 的 `-Dbitdepths=8` 意味着 10-bit AV1（HDR 常见）不能走 dav1d 软解**，该决定在 patch 里没有注释依据（Windows 版 workflow 注释明确选 8,16 并指向"Android 的相反选择"，见 `2026-09-17-windows-libmpv-slim.md` §6.1）；Windows CI：不分节（分节反而 +62,976B，`…windows-libmpv-slim.md` §12 发现 2） |
| **mbedtls** | 见 §4 | L1 裁剪 | −114,712B（Linux） | L | 见 §4.2 |
| **zlib 1.3.1** | 全平台 | 静态，`-Os` 分节 | 链接后 42,805B | L | `--disable-autodetect` 下必须 `--enable-zlib`，否则 mov `cmov`/mkv zlib 压缩轨读不了 |
| **libplacebo** | 见 §2.3 | 最小静态 | 链接后 7,000B | L | — |
| **glslang / shaderc / spirv-cross** | v9旧：Android 为 libplacebo Vulkan/GL 后端编 glslang 14.3.0；Windows 编 glslang+spirv-cross+shaderc | **一律不要**（B3 摘 gpu_next 后无消费者） | Windows 旧分支：glslang `ENABLE_OPT=OFF` 省 SPIRV-Tools-opt 9.4MB 静态库（链接前）、shaderc 自带第二份 glslang 未去重——整条链不再需要 | L（Linux 全程未编它们） | **mpv 自己的 d3d11 上下文需要 shaderc**，但 media_kit 的 libmpv render API 不走它（§2.2 `gl` 行） |
| **harfbuzz/freetype 之外的 libstdc++** | — | Linux：`-static-libstdc++ -static-libgcc`；Windows：`-Wl,-Bstatic -lstdc++ -lwinpthread -Wl,-Bdynamic`（+107,008B 换自包含）；Android：`-lc++_static -lc++abi` | — | L / n6:C | 否则 DLL 会动态依赖 `libstdc++-6.dll`/`libgcc_s_seh-1.dll`/`libwinpthread-1.dll`（`…windows-libmpv-slim.md` §12 发现 1） |

## 6. 已知不可裁 / 不要裁的项与原因

| 项 | 为什么不能（或不该）裁 | 证据 |
|---|---|---|
| **libass + freetype + harfbuzz + fribidi**（合计 S 档约 1.20MB，不含 libstdc++） | libass 无编译开关可只删特效；harfbuzz/fribidi 是其硬依赖（`meson.build` 无 `required: get_option`）；mpv 自己 `libass` 硬依赖；同一条 libass 管线还承接 STT/翻译等动态字幕（`osd-overlay`/`sub-add`）。旧分支曾**真的把 libass 从 mpv 里摘掉并真机验证能跑**，但同时验证了 `sub-add` 外挂 SRT/ASS 的时间同步只在有 libass 时成立 | README L756–L805（字幕栈评估，结论保留）；`mpv meson.build:32,50`；`build-win-libmpv-v9.sh` 头注释（B-v9） |
| **`libdav1d`（AV1 软解）** | Snapdragon bengal 档 SoC 无 AV1 硬解，真机 "Could not open codec."，软解兜底成功；"播放失败比卡顿更糟" | README L105–L116、L520 起 AV1 条目；Windows 桌面高码率 1080p AV1 软解 36.8% 单核、无卡顿（README 同节） |
| **`av1`/`h264`/`hevc`/`vp9` parser** | 即使没有对应软解码器也要靠 parser 找帧边界喂 `*_mediacodec` | `flavors-mova-slim.sh:65-67` |
| **Windows/iOS/Linux 的 h264/hevc/vp9 软解码器** | D3D11VA/VideoToolbox/VAAPI 是叠加在软解码器内部的 hwaccel，解析 NAL/参考帧必须软件完成；摘了硬解一并失效。做成"只留硬解"要改 ffmpeg 源码，评估后明确不做，且失败模式（会话超限就彻底不能播）比 Android 更差 | README L678 起 iOS 节"架构性的、不是保守策略"、L1004 Windows 节 |
| **`gl` / `plain-gl`** | libmpv render API 的 OpenGL 后端 | `render.h:468-470`；`meson.build:1266-1272`（§2.2） |
| **ffmpeg 的 `png` encoder + `png` decoder** | 截图与封面 | README L644 |
| **`hls` demuxer 自带的 `aac`/`ac3`/`eac3` demuxer 与 `ac3` parser** | n9 的 `hls_demuxer_select` 强制带入 | `configure:3943`；L（S 摘要里自动出现） |
| **bsf：`h264_mp4toannexb`/`hevc_mp4toannexb`/`aac_adtstoasc`/`extract_extradata`/`vp9_superframe(_split)`/`av1_frame_split/merge`/`mov2textsub`** | MediaCodec 播 mp4、HLS/TS 里的 AAC、对应解码器要求 | `configure-ffmpeg-slim.sh:264-272` |
| **`--enable-jni` + mpv 的 `mpv_lavc_set_java_vm` 补丁（Android）** | 缺了 media_kit 的 Android 插件加载时 `UnsatisfiedLinkError` | `build-android-libmpv-v9.sh` 头注释 bug #1（真机复现） |
| **`-Dgl=enabled -Dplain-gl=enabled -Degl-android=enabled`（Android）** | `hwdec_aimagereader.c` 无条件用 `ra_is_gl()`，缺则链接失败 | v9 旧 bug #3 |
| **`-lc++_static -lc++abi`（Android）** | NDK clang 驱动不自动带静态 C++ 运行时 | v9 旧 bug #2 |
| **`--enable-d3d11va --enable-dxva2` + 显式 hwaccel 列表（Windows，用 `--disable-autodetect`/`--disable-everything` 时）** | 否则 mpv `hwdec=auto` 静默回落软解 | `build-win-libmpv-v9.sh` 头注释；真机 `Using hardware decoding (d3d11va)` |
| **Windows 上不要给 ffmpeg/dav1d 加 `-ffunction-sections`、不要上 LTO、`-fvisibility=hidden` 无效** | 数据：+124% / +62,976B；LTO +12,288B；PE 默认不导出 | `…windows-libmpv-slim.md` §12；README L1137 |
| **Windows 上 mpv 必须用 clang 编** | gcc 16.2.0 对 `options/m_config_frontend.c` miscompile，`mpv_create()` 段错误；6 种 gcc 变体全复现 | README Windows 行（2026-09-24），workflow `:1127-1135` |
| **Android 的 `-Wl,-z,max-page-size=16384`** | 16KB 页兼容（上游 buildscripts 已带，我们的补丁保留了它：`libmpv-android-video-build.patch` build.sh hunk 上下文） | 补丁文件头部 |
| **mbedtls 的 `SSL_SRV_C`** | n9 `tls_mbedtls.c:655` 无条件引用 DTLS cookie API | L（编译失败） |
| **`--disable-x86asm`/`--disable-asm`** | 软解性能 | L：−1.53MB 的代价是丢全部 SIMD |
| **`-Dbitdepths=8`（dav1d，Android 现状）是否要保留** | 它在省体积的同时放弃 10-bit AV1 软解 | 见 §5；这是"需要产品确认"的项，不是技术不可裁 |

## 7. n6 → n9.0.2（及 mpv 0.36 钉死版 → v0.41.0）迁移差异清单

**组件名核对结论（n6 线所有白名单名字逐个对 n9.0.2 `--list-*`）**：n6 线 Android/Windows/Linux/Darwin 四份清单里的解码器、编码器、parser、demuxer、协议、bsf 名字，在 n9.0.2 里**全部仍然存在，没有改名、没有被移除**（`chk()` 脚本逐名比对，唯一的"缺失"是本文自己传错的两个：`hls` 不是协议、`whip/whep` 不是 demuxer；硬解 `*_mediacodec` 是解码器而不是 hwaccel，n6 也一样）。真正的差异在**选项、行为、链接、构建系统**：

| # | 差异 | 影响面 | 证据 | 处理 |
|---|---|---|---|---|
| 1 | **`--disable-postproc` / `--enable-postproc` 已不存在** | **5 处会让 configure 直接失败**：`flavors-mova-slim.sh:113`、`flavors-mova-slim-ios.sh:104`、`configure-ffmpeg-slim.sh:317`、workflow `build-mova-libmpv.yml:830`、`:1096` | n9.0.2 实跑：`Unknown option "--disable-postproc"`；`grep -n postproc configure` 空 | 删掉 |
| 2 | **configure 对未知组件名静默放行** | 任何拼错/已移除的名字（`--enable-bsf=foo`、`--enable-protocol=hls`、`--enable-demuxer=whep`）都"通过" | n9.0.2 实跑，三个都 accepted | 每次 configure 后用 `Enabled …` 摘要对账（本文 `chkenabled.py`，§8.3） |
| 3 | **`hls` 协议已移除**（8.1：`Changelog` "Remove the old HLS protocol handler"），只剩 `hls` demuxer | Darwin 补丁 `protocol_movaslim_options` 里的 `--enable-protocol=hls` 变空操作 | `--list-protocols` 55 项无 hls | 删这一行；HLS 行为由 demuxer + http 承担，Android/Linux/Windows 的 n6 清单本来就没写 |
| 4 | **`tls_verify` 默认值 0 → 1** | 经 mpv 的 http(s) 不受影响（`stream_lavf.c:201` 总是显式写）；WHEP 内部直接用 ffmpeg 的 http/tls 会吃到 1 | `libavformat/tls.h:49`（n6.0.1）vs `:93-94`（n9.0.2）；`Changelog` 8.0 "Enable TLS peer certificate verification by default (on next major version bump)" | WHEP 信令显式传 `tls_verify`/`ca_file` |
| 5 | **libpostproc 已删；libavcodec 63 / libavformat 63 / libavutil 61 / libavfilter 12 / libswscale 10 / libswresample 7** | mpv 版本必须配套：v0.41.0 要求 ffmpeg ≥ 6.1（libavcodec ≥ 60.31.102）；钉死的 `78d43740f5` 与 n9.0.2 不兼容（26 条错误） | mpv configure 日志；计划 T0.2 | 用 v0.41.0；`pin-n9-compat.patch` 作废 |
| 6 | **mpv `libplacebo` 成为硬依赖，且没有 `-Dlibplacebo` 选项；`libplacebo-next`、`libcurl`、`subrandr`、`amf` 选项名都不存在** | 旧分支（v9 线）Darwin 补丁用过这些名字；n6 线钉死 mpv `78d43740f5` 的选项集：未核实 | `meson.options` 逐条核对（105 项） | b3 补丁 + 最小 libplacebo（§2） |
| 7 | **mpv 默认 VO 改为 `gpu-next`**（`RELEASE_NOTES` "vo: prefer vo_gpu_next over vo_gpu by default"），`vo_mediacodec_embed` 不再是 Android 默认 | libmpv render API 不受影响（只有 `gpu`/`sw` 后端） | `vo_libmpv.c:114-118` | 摘掉 `vo_gpu_next`（b3） |
| 8 | **mpv 的 `b_lundef=false` 写在 `meson.build:9`** | 链接期不报未解析符号 | `meson.build:9`；L：`-Db_lundef=true` 通过 | 加 `-Db_lundef=true`，并用 `nm -D --undefined-only` 复核 |
| 9 | **libswscale 重写出的新 ops 后端**：x86 需要 `HOSTCC libswscale/x86/uops_macros.gen.asm` | **out-of-tree 构建 + 并行 make 有竞态**：首次 `make -j18` 报 `cc1: fatal error: opening output file libswscale/x86/uops_macros.gen.asm: No such file or directory`，再跑一次就过 | 本文 S 档首次构建日志（`ffmake-S.log`）；之后所有在 `make` 前 `mkdir -p libswscale/x86` 的构建（十余次）都一次通过 | **Android x86/x86_64 ABI 的 `flavors-mova-slim.sh` 就是 out-of-tree（`mkdir -p _build$ndk_suffix; cd …; ../configure`）会撞上**；arm64/armv7 没有 x86 asm，推断不受影响（未验证）。configure 之后 `mkdir -p libswscale/x86` |
| 10 | **`rtpdec_select` 拖入 `asf`、`rm` demuxer**；**`hls_demuxer_select` 拖入 `aac`/`ac3`/`eac3` demuxer 与 `ac3` parser** | 启用 rtp/sdp/rtsp 必然多出两个遗留容器；摘不掉的 ac3 | `configure:3991`、`:3943`；L 的 `Enabled demuxers` 摘要 | 体积见 §3.2、§8.2.1（RTSP +155,648B；WHEPSET +180,224B） |
| 11 | **`--enable-lto` 在 Linux/gcc 15 上可用了** | n6 线 README 记的"NASM 目标文件与 LTO 混链失败"不再复现 | L：ffmpeg+mpv 双 LTO 链接通过；`LTO` 变体软渲染冒烟通过，含 LTO 的 MAX/MAXL1 变体 12 类样本播放通过（§3） | Linux 可开；Windows 仍不开 |
| 12 | **GCC 自动向量化默认开（8.0）** | `configure:8116-8128` 只对 gcc < 13 保留 `-fno-tree-vectorize` | L：`-fno-tree-vectorize` 对 `--enable-small` 构建产物**字节完全一致**（10,274,152） | 无需处理 |
| 13 | **yasm 不再支持，必须 nasm** | x86 构建机 | `Changelog` 8.0 "yasm support dropped, users need to use nasm" | 已满足：main workflow 的 android 两个 job（`:77`、`:241`）、linux job（`:773`）apt 列表有 `nasm`，windows job 有 `mingw-w64-x86_64-nasm`（`:964`）；本机 nasm 3.01 通过 |
| 14 | **`av1_videotoolbox` hwaccel 新增**（n6.0 没有） | iOS/macOS 在新款 SoC 上可走硬解 AV1；仍需 `libdav1d` 兜底 | `--list-hwaccels` 79 项含 `av1_videotoolbox` | 未测；不要因此删 dav1d |
| 15 | **`whip` muxer、`dtls`/`srtp` 协议存在，`whep` 不存在** | WHEP flavor 起点 | `--list-muxers/protocols/demuxers` | §1.4 |
| 16 | **`tls_mbedtls.c` 在 n9 里引用 `mbedtls_ssl_conf_dtls_cookies`（无条件）** | mbedtls 不能关 `MBEDTLS_SSL_SRV_C` | `tls_mbedtls.c:655`；L 编译失败 | §4.2 |
| 17 | **n9 `hwcontext_vulkan.h` 公共头仍要 Vulkan 1.3 类型** | Android NDK r25c 自带 vulkan.h 旧，旧分支 v9 Android 为此往前缀里补了 Vulkan-Headers v1.3.296 | `build-android-libmpv-v9.sh` "Vulkan-Headers" 段（B-v9） | 本线 libplacebo 关 vulkan 后 Linux 未遇到，Android：未核实 |
| 18 | **mbedtls CMake 的 `Release` 自己写 `-O2`，忽略 `CMAKE_C_FLAGS_RELEASE`** | 自建 mbedtls 若按习惯传 release flags，既丢 `-Os` 也丢分节 | 本文第一次 mbedtls 变体：ninja flags 里只有 `-O2 -std=c99`，无 `-Os`/`-fPIC`/`-ffunction-sections`；`MinSizeRel` + `CMAKE_C_FLAGS` 才对 | §4.2 |
| 19 | **freetype meson 的 `-Dbzip2=disabled` 挡不住对系统 `bzip2.pc` 的探测** | 下游链接报 `Package 'bzip2' not found` | `freetype meson.build:322-331`；本文构建失败两次 | 构建时隔离 `PKG_CONFIG_LIBDIR` |
| 20 | **mpv 的 `javavm` 补丁要手工移植**（`client.h` 带偏移、旧 `client.c` hunk 打不上） | Android | 计划 T0.2；本文 `git apply --check` 对 v0.41.0 + b3 通过 | 用 `javavm-v041.patch` |
| 21 | **`hls_mp4_seek`、`dash_base_url_escape` 两个 ffmpeg 补丁在 n9.0.2 上已被上游修复** | `media-kit/libmpv-android-video-build` 的 `patches/ffmpeg/*.patch` 对 n9.0.2 `git apply` 失败是因为已修，不是冲突 | 计划 T0.2 记录（本文未复核） | 删除这两个补丁 |
| 22 | **旧分支 Windows v9 的 `-Dgl=disabled -Dd3d11=enabled -Dshaderc=enabled`** 与 libmpv 的 OpenGL render API 不兼容（media_kit 使用该 API 的依据：`used-syms.txt` 含 `mpv_opengl_init_params`） | 该脚本的 Windows 体积数字不可直接沿用 | `render.h:468-470`；`meson.build:1266-1272` | §2.2 |

## 8. 极致配置的预期总体积区间（只引用实测，并写清口径）

### 8.1 口径与可信度

- **Linux x86_64 stripped `libmpv.so`**：本文实测（§3.2）。工具链同评估基线：gcc 15.2.0（Ubuntu 15.2.0-16ubuntu1）、GNU ld 2.46、`strip -s`、meson 1.10.1、nasm；ffmpeg n9.0.2（`946fcce0…`）、mpv v0.41.0（`41f6a645…`）+ b3、libplacebo v7.360.1（`cee9b076…`）、freetype VER-2-13-3、fribidi 1.0.16、harfbuzz 10.4.0、libass 0.17.4、dav1d 1.5.1（`42b2b24f…`）、zlib 1.3.1、mbedtls 3.6.7（`068ff08`，仅 `MBEDTLS_SSL_DTLS_SRTP` 打开）。
- **与评估基线同口径对比**：评估基线 **9,209,384**（最小 ffmpeg，无 `--enable-small`），本文用同一脚本复跑得 **9,209,384（字节一致）**；本文 S 档 = 10,274,152（完整产品白名单），极致档 MAXL1 = **8,754,480**（比评估基线小 454,904B，−4.9%）。**它们不是"同一份 ffmpeg 配置"**：评估基线是 6 个解码器、9 个 demuxer 的最小子集，S/X 是 23 个解码器 + 16 个 demuxer + 17 个协议 + 12 个 bsf + 字幕 + dav1d。
- **平台口径差异**：Linux 数字的拆分（`--enable-small` 4.4MB、dav1d 1.6MB、asm 1.5MB、unwind 0.89MB、RELR 0.36MB、bsfs 0.52MB、LTO 0.13MB、freetype 0.135MB、mbedtls L1 0.115MB）是 **x86_64 + gcc** 的；arm64/clang/COFF/Mach-O 上每一项的字节数会不同，方向性可参考表中"验证"列，**数字不能搬运**。例如 dav1d 在 Android arm64（`bitdepths=8`）实测 +671KB（README L177），在本文 x86_64（`bitdepths=8,16`+asm）是 1.6MB。

### 8.2 各平台已有实测 / 本文实测一览

| 平台 | 口径 | 字节 | 来源 | 状态 |
|---|---|---:|---|---|
| **Linux x86_64（本文）** | stripped，n9.0.2 + v0.41.0 + b3，**S 档** | **10,274,152** | 本文 L | 已跑 |
| Linux x86_64（本文） | **X 极致档 MAXL1B**（LTO + unwind 全去 + RELR + mbedtls L1，仍含 dav1d） | **8,754,480** | 本文 L | 已跑，功能矩阵通过 |
| Linux x86_64（本文） | MAX（同上，不裁 mbedtls） | 8,951,144 | 本文 L | 已跑 |
| Linux x86_64（本文） | MAXND（MAX 去 dav1d，AV1 不可播） | 7,410,960 | 本文 L | 已跑，av1.mp4 `err=-16`（反证测试有效） |
| Linux x86_64（评估） | v0.41.0 摘 `vo_gpu_next`，**最小 ffmpeg** | 9,209,384 | WHEP 计划 T0.2 修订表；本文复跑一致 | 不同口径 |
| Linux x86_64（n6 线 CI） | n6.0.1 + 钉死 mpv，系统共享库 libass 栈 | 7,550,784 | README Linux 行（2026-09-17 CI） | **口径不同**（库是动态的，不在文件里）|
| Android arm64（n6 线 CI） | 现产物，n6.0 + 钉死 mpv，dav1d + 全套 | 6,050,104 | README L23（2026-09-18） | 已出货 |
| Android arm64（评估，**未整链 LTO**） | NDK r25c，ffmpeg 按 v6 线清单**去 dav1d**，API24；钉死 / v0.41.0+libplacebo(GL) / **v0.41.0 摘 gpu_next** | 6,969,304 / 7,775,616 / **7,127,064** | WHEP 计划 T0.2 修订（子代理评估，非本文复跑） | 只编过，未在设备上跑 |
| Android arm64（评估，**整链 LTO**） | 同上 | 6,615,960 / 7,392,992 / **6,768,032** | 同上 | 只编过 |
| Android arm64（本文推荐配置） | n9.0.2 + v0.41.0 + b3 + javavm + libplacebo 最小静态（opengl 关）+ 本文 §1/§2 参数 | **未跑** | — | **未测**；方向：评估的 6,768,032 里没有 dav1d、用的是全开 bsf（`--enable-bsfs`，Linux 上单这项 +520,192B）、freetype 未裁（Linux −135,168B）、libplacebo 开了 GL，加回 dav1d 会 +~0.67MB（README L177，arm64 8-bit） |
| Windows x86_64（n6 线 CI） | 现产物，clang 编 mpv | 14,033,920 | README Windows 行（2026-09-24） | 已接入真机 |
| Windows x86_64（旧分支 v9，不可参考） | gl 关、d3d11+shaderc 开、v0.41.0 + libplacebo d3d11 | 13.60→11.91MB | `build-win-libmpv-v9.sh` 头注释 | 关了 `gl`，与 libmpv 的 OpenGL render API 不兼容（§2.2；media_kit Windows 实际路径未核实），数字不作参考 |
| Windows x86_64（本文推荐配置） | — | **未跑** | — | **未测** |
| iOS arm64（n6 线 CI） | 单文件 `libmpv.dylib` | 6,534,448（README iOS 行，v3.4）/ 5,741,680（README macOS 行记 dist/ios-arm64） | README | **README 内两处记录不一致**（WHEP 计划 §4 也指出过） |
| macOS（n6 线 CI） | arm64 / amd64 / universal | 7,398,112 / 7,957,944 / 15,377,120 | README macOS 行 | 无真机 |
| iOS / macOS（本文推荐配置） | — | **未跑** | — | **未测**（无 Mac） |

**本文 §3.2 里的"单项收益"在 Android/Windows/iOS 上哪些预期方向一致**（均 `T`）：`--enable-small`（已在用）、bsf 白名单（Android 现用 `--enable-bsfs`，应有收益，arm64 字节数未测）、freetype 裁模块（libass 栈在 Android 同款）、unwind 表（Android 有 `.eh_frame`，但崩溃回溯代价需拍板）、mbedtls 裁剪（仅 Android）、LTO（Android 已在用，Linux 新增）；**不适用**：RELR（Linux 专有，Android 等价手段未测）、HARDEN（Ubuntu gcc 默认）、Windows 的分节/visibility/LTO/unwind。

#### 8.2.1 WHEP flavor 增量（Linux，实测）

在 S 档上追加 `--enable-muxer=whip --enable-demuxer=rtp,sdp --enable-protocol=dtls,srtp`（mbedtls）：**+180,224B（+1.75%）**，其中带出了 `asf`、`rm` 两个 demuxer 与 `rtp` muxer；configure 摘要见 `/root/w/mpvt/extreme/ffconf-WHEPSET.log`（`Enabled muxers: rtp whip`、`Enabled protocols: … dtls … srtp …`、`Enabled demuxers: … asf … rm … rtp sdp …`）。**不含将来的 `whep.c`**（计划估计 +几十 KB，推算未编）。计划 §4 的预算（+0.3–0.35MB，红线 ≤0.5MB）在这个口径下目前用掉 0.18MB，余量 0.32MB 留给 `whep.c` 与重放保护等代码。RTSP 对照：+155,648B。

### 8.3 校验证据（本文实际执行的命令与结果）

**配置项名字有效性（必做项）**

| 校验对象 | 命令 | 结果 |
|---|---|---|
| ffmpeg 全部 `--enable-*/--disable-*`（S 档用到的 ~40 个选项） | 实际 `configure` 13+ 次 | 全部接受；**`--disable-postproc` 报 `Unknown option`**（这是唯一被拒绝的） |
| 平台专有选项在 n9.0.2 `--help` 中存在 | `grep -E -e "--(enable\|disable)-$o" help.txt` | `mediacodec jni d3d11va dxva2 d3d12va schannel securetransport videotoolbox audiotoolbox neon vaapi vdpau mbedtls openssl libdav1d libass zlib libxml2 lto small optimizations runtime-cpudetect swscale-alpha network symver pic iconv autodetect version3 gpl nonfree hwaccels bsfs` 全部存在 |
| ffmpeg 白名单每个名字存在于 n9 `--list-*` | `chk()`（decoders/encoders/parsers/demuxers/protocols/bsfs/muxers/hwaccels） | n6 线四份清单全部名字存在；`mov_text` 不是解码器名（叫 `movtext`，n6 线也是 `movtext`） |
| ffmpeg 白名单"静默丢弃"检查 | `chkenabled.py ffconf-S.log` | `decoders requested=23 enabled=23 silently-dropped=none`；`encoders 1/1`；`parsers requested=11 enabled=12 dropped=none extra=['ac3']`；`demuxers requested=16 enabled=18 dropped=none extra=['ac3','eac3']`（`hls_demuxer_select` 自动带入）；`protocols 17/17`；`bsfs 12/12` |
| mpv 全部 `-D` 选项名 | 对 `meson.options`（105 项）逐名 `grep` + 一次带 64 个 `-D…=disabled`（含 Android/Windows/Darwin 专有项）的真实 `meson setup` | **所有推荐/涉及的名字均存在；meson `rc=0`，无 `Unknown option`**；确认**不存在**的：`libplacebo`、`libplacebo-next`、`libcurl`、`subrandr`、`amf`、`cuda` |
| libplacebo 选项名 | 真实 `meson setup`（v7.360.1） | 19 个选项里用到的 14 个全部接受 |
| b3 / javavm 补丁 | `git apply --check` 对干净 `git archive v0.41.0` | 通过；b3 之后再 `--check` javavm 通过 |

**功能 / 符号校验（MAXL1B 与 S 同一套）**

| 项 | 命令 | 结果 |
|---|---|---|
| 28 个 `mpv_*` 函数仍导出 | `nm -D --defined-only \| awk '{print $3}'` 与 `used-syms.txt`（42 项=28 函数+14 类型名）`comm -23` | 仅缺 14 个**类型名**（`mpv_event`、`mpv_format`…，不是符号），28 函数全在；导出共 54 |
| 未定义符号为 0 | `nm -D --undefined-only`，滤掉 `GLIBC`/弱符号 | 空；**重链接 `MAXL1B` 带 `-Wl,--no-undefined`**（`-Db_lundef=true`，mpv 自己的 `meson.build:9` 默认 `false`）链接通过；`NEEDED` = `libm.so.6 libc.so.6` |
| 软渲染冒烟 | `smoke2.c`（`vo=libmpv` + SW render API，`loadfile` + 渲染） | `render_ctx=0 sw frames=22 end=1`（S、NODAV1D、LTO、NOASM、MAX…均如此）|
| 12 类样本播放矩阵（`smoke3.c`，读 `END_FILE` reason/error） | h264+aac mp4、hevc+aac mp4、vp9+opus webm、av1 mp4、h264 mkv/flv/ts、本地 HLS m3u8、mp3、flac、ogg、`mov_text` mp4 | S、MAX、MAXL1：**12/12 reason=0**；NODAV1D/MAXND 的 `av1.mp4`：`reason=4 err=-16`（反证） |
| libass 字幕渲染 | `smoke4.c`：`sub-add` SRT，`sub-fonts-dir`+DejaVu Sans，同一帧 `sub-visibility` yes/no 各渲染一次，比像素校验和 | S/MAX/MAXL1：`sub-text='hello sub'`，`differ=1` |
| HTTPS 矩阵 | `tlstest.py` + `smoke5.c`（§4.1） | S/MBsbase/MBsl1/MAXL1 共 4 个变体 × 6 组合 = 24/24 通过；MBsl1t 在 TLS1.3-only 服务器 2/2 失败（其余 4/6 通过） |
| 变速不变调（rubberband 是否必要） | `pitch.c`：`ao=pcm`，440Hz 正弦，`speed=1.0/1.5/2.0` × `audio-pitch-correction=yes/no`，数过零点 | S（**rubberband 关**）：`yes` → 440.0/440.2 Hz，`no` → 659.7/879.6 Hz。**默认变速不变调靠 mpv 自带 scaletempo 就够，不需要 rubberband**——这是 `libmpv-slimming-options.md` §3 里"关前必须实测"的那一项，现已有数据 |

## 9. 待验证清单（每个 `T`/`B` 项用什么真实事件 / 数字验证）

遵循 mova CLAUDE.md "真机验证前先设计基于真实事件的测量方法"：下面不用墙钟、不用临近 EOF 的 seek；每项给出**事件源**与**通过判据**；防缓存（URL 带 timestamp）、多次取平均。

| # | 待验证项 | 当前 | 验证方法（事件源） | 通过判据 |
|---|---|---|---|---|
| 1 | Android arm64 全链（n9.0.2 + v0.41.0 + b3 + javavm）能编、能载入 | T | CI 产物：`llvm-nm -D`；真机 `MediaKitLibsAndroidVideoPlugin` 加载（logcat 无 `UnsatisfiedLinkError`） | `mpv_lavc_set_java_vm`、4 个 `ff_*_mediacodec_decoder`、`dav1d_*`≥19 个符号在；导出符号集 ⊇ `used-syms.txt`；`nm -u` 无多余 |
| 2 | Android H.264 仅硬解（n6 线已摘软解，至今无回归） | T（脚本注释自述 untested） | STG-AL00：畸形流、并发两路、冷门 profile/level；`MovaReady`/`MovaErrorEvent` + mpv `END_FILE.error` | 与 sw+hw 对照构建相比，无新增播放失败 |
| 3 | `auto_features=disabled` 与现产物 feature 对账 | T | 现产物 `mpv -v` 启动日志/`meson introspect --buildoptions` vs 新构建；GBK `.srt` 文件 `sub-text` 轮询（README L520 方法）| feature 差异清单全部被明确接受；GBK 字幕要么转码正常，要么产品明确放弃 |
| 4 | 去 unwind 表在 Android arm64 的收益与崩溃回溯代价 | T | 构建对比 `.eh_frame` 节大小；调试 harness 在 libmpv 线程里 `abort()`，比较 tombstone 栈帧是否仍含 `libmpv.so` 帧 | 体积收益 ≥ 约定阈值 且 崩溃栈可用，或产品拍板放弃 |
| 5 | Android RELR（`--pack-dyn-relocs=relr`）与 minSdk | T | 目标最低 API 设备上 `dlopen` 成功（logcat linker 无报错）；`.rela.dyn` 节大小 | 全部目标 API 加载成功 |
| 6 | mbedtls L1 在 Android 上的 HTTPS 兼容 | T（Linux 本地服务器已过） | 真机访问真实 HTTPS/HLS CDN 若干（列清单），读 `END_FILE.reason`；chacha-only 服务器；WHEP DTLS 握手 | 与默认配置对照零回归 |
| 7 | dav1d `bitdepths`（8 vs 8,16）与 10-bit AV1 | T | 10-bit AV1 样本（`ffmpeg -pix_fmt yuv420p10le`），`END_FILE.error`；体积差 | 产品拍板 |
| 8 | libplacebo `-Dopengl=disabled` 在 Android 链接 | T（Linux 已过） | 交叉编译 + `llvm-nm` 导出/未定义；体积对比评估 6,768,032 | 链接通过；体积不增 |
| 9 | bsf 白名单代替 `--enable-bsfs`（Android 现状） | T（Linux +520,192B） | 同一 ABI 构建对比；回归 HLS/TS（`aac_adtstoasc`）、mp4（`*_mp4toannexb`）、WebM(vp9 superframe)、mov_text | 全部样本 `END_FILE.reason=0`，体积减少 |
| 10 | freetype 裁模块的 OTF-CFF 字体 | T（本机无 .otf） | 含 CFF 字体的 ASS/MKV，`sub-text` + 同一帧 with/without 字幕像素校验和 | `differ=1` 且字形正确（CJK 抽样） |
| 11 | Windows n9 全链：clang 编 mpv、SChannel、D3D11VA | T | CI 产物 `mpv_create` 冒烟 5/5；`flutter run -d windows` 实机：`mpv -v` 日志出现 `Using hardware decoding (d3d11va…)`；configure 摘要含 `dtls`（`SECPKG_ATTR_DTLS_MTU` 检查） | 同 2026-09-24 验证项零回归 |
| 12 | Windows 的 `-Dgl`/`d3d-hwaccel`/`egl-angle*` 取舍 | T | 与现产物 `meson` summary 对账 + media_kit 实际 render 路径（读 `media_kit_video` Windows 源码或 `mpv_render_context_create` 参数日志） | 路径一致、画面持续渲染（`MovaSizeChange`/渲染事件） |
| 13 | iOS/macOS（无 Mac，**未验证**）：n9 + v0.41.0 的 Nix 构建、securetransport 握手、VideoToolbox | T | 需 Mac：`pod install`、真机 `Using hardware decoding (videotoolbox)`、HTTPS/HLS AES-128/RTMPS | 与 README iOS 节"已知未测项"逐条关闭 |
| 14 | Darwin 保留的 `overlay,equalizer` 能否像 Android 一样清零 | T | 同 Android 2026-09-28 方法：`sub-text` 轮询 + 截图 | 无回归 |
| 15 | WHEP：Linux 端到端 | T | 本地 WHEP 服务器（SRS/mediamtx），事件源：`MPV_EVENT_PLAYBACK_RESTART`（首帧）时间戳相对信令完成事件；`tc netem` 丢包下 NACK 触发后帧间隔分布 | 计划 T1.x 判据 |
| 16 | WHEP 信令的 `tls_verify` 默认 1 在 Android 上的 CA 来源 | T | 真机 WHEP 信令 HTTPS 握手事件 | 握手成功且证书校验有效 |
| 17 | Linux `lld`/`gold` + ICF | 未测 | WSL 装 clang/lld，`-fuse-ld=lld -Wl,--icf=all` 重链接 S | 体积对比 S；`used-syms` 全在 |
| 18 | Linux 硬解（`vaapi`/`vdpau`） | T | 有 GPU 的机器 `mpv -v` 日志 `Using hardware decoding (vaapi)` | 出现且画面正常 |
| 19 | Android `libmpv-android-video-build.patch` 里 libass/libxml2/mbedtls 的 `-fomit-frame-pointer` 与 README"移除"结论是否矛盾 | 未核实 | 对 libmpv.so 做 A/B（去掉该 flag） | 体积是否 −2% 量级 |
| 20 | Linux 真实音频输出 | 未测（本文用 `ao=null`/`ao=pcm`） | 开 `alsa/pulse/pipewire` 后 `ao` 事件 | 出声 |
| 21 | zlib 在 mpv 里的实际用途（`auto_features=disabled` 关掉的 `zlib`） | 未核实 | grep `HAVE_ZLIB` 的使用点，对应功能样本 | 无功能项依赖，或明确列出 |

## 附录 A. 复现材料与已知局限

**工作目录与脚本（WSL，`/root/w/mpvt/extreme/`，未入库；副本在本次会话 scratchpad）**：`build-deps.sh`（freetype/fribidi/harfbuzz/libass/dav1d）、`build-ff.sh`/`build-ff6.sh`/`build-ff8.sh`/`build-ff9.sh`（ffmpeg 变体）、`build-plc.sh`（libplacebo）、`build-mpv.sh`（mpv）、`mk-base.sh`（评估基线复跑，输出路径已改，**未覆盖 `/root/w/mpvt/eval/` 任何已有产物**）、`run-v2…v9.sh`（变体编排）、`smoke2.c`/`smoke3.c`/`smoke4.c`/`smoke5.c`/`matrix.sh`/`subtest.sh`/`tlsrun.sh`/`tlstest.py`/`pitch.c`/`pitchrun.sh`（功能校验）、`mapsum3.py`（链接图按归档×节类型归因）、`chkenabled.py`、`optchk.sh`。各变体的 `ffconf-*.log`、`mpvconf-*.log`、`out-*.stripped.so` 都留在该目录。**本文只新增了本文件**；未 `git commit`、未切分支、未改任何已跟踪文件。

**已知局限（务必带着读本文）**

1. 所有 `L` 数据来自 **x86_64 + gcc 15**；arm64/clang/COFF/Mach-O 的字节数没有跑，只有方向。
2. 软渲染冒烟和样本矩阵验证了**解复用/解码/出帧/字幕渲染/HTTPS**，没有验证：真实 GPU 渲染、真实音频输出、硬件解码、公网 CDN、直播推流（RTMP/RTP 只确认了协议被编进来并通过 `Enabled protocols` 对账，没有对接真实服务器）、OTF-CFF 字体、CJK 字形。
3. `-Dauto_features=disabled` 在 Android/Windows/iOS 上与现产物的 feature 差异**没有对账**。
4. 评估基线与 n6 线 README 的数字口径互不相同（§0 顶部、§8.1），本文已逐处标注，但引用时请带口径。
5. `mpv.ver`/`exclude-libs` 只在 ELF 上有意义；Windows 的导出由 `MPV_EXPORT` 与 `.def` 决定，本文未处理。

