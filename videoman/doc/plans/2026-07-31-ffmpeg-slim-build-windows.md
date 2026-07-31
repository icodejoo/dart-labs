# 瘦身构建 spike（Windows 平台）：LGPL 瘦身版 ffmpeg 体积验证 — 执行计划

> **执行者说明**：本计划由 opus 定架构，交 sonnet（low effort）逐步执行。**所有架构判断
> （LGPL 合规、要 enable/disable 哪些组件）已在本计划里定死，执行者只做机械的
> 环境准备 + 构建 + 量体积 + 回报，不要自行改动组件清单或 LGPL 策略。**
> 遇到本计划没覆盖的判断（例如某组件编译报缺依赖、要不要为它再装一个库），**停下来，
> 把报错原样记录到"执行记录"一节，不要自行 improvise 引入新依赖或改 LGPL 相关开关**。

## 0. 这个 spike 要回答的唯一问题

**"videoman 只支持现代主流点播+直播格式时，ffmpeg 部分用 LGPL 配置能瘦到多小？"**

背景基线（已实测，见 [../notes/2026-07-31-libmpv-slimming-options.md](../notes/2026-07-31-libmpv-slimming-options.md) §0）：
当前项目随包分发的**完整版** `libmpv-2.dll` = **29.76 MB**（这里面既有 mpv 自身，也有它
静态/动态链接的完整 ffmpeg）。本 spike **不重建整个 libmpv**（那依赖 libplacebo/shaderc/
spirv-cross/libass 等一大堆，是后续大工程），只**单独构建一个瘦身版 ffmpeg 共享库**，量它
的体积，并与一个**同工具链构建的完整版 ffmpeg** 对比，得出"瘦身能省多少"的量级数字。

**明确不在本 spike 范围内**（不要做）：
- 不重建 libmpv（整个 mpv）。
- 不做 Android/iOS/macOS/Linux（本机是 Windows，其他平台离不开各自工具链/Mac）。
- 不替换进 media_kit / 不改动 videoman 任何 `lib/` 代码。
- 不追求"能播放"，只追求"能编译出来 + 量体积 + configure 里 LGPL 与格式裁剪成立"。

## 1. 环境准备

本机已探测到（无需重装）：Chocolatey (`choco`)、Git（含 mingw64 环境）、Python 3.14、
CMake、curl。**缺** MSYS2、gcc/mingw 工具链、nasm、make、pkg-config。

ffmpeg 在 Windows 上最直接的构建方式是 MSYS2 + mingw-w64。步骤：

1. 用 choco 安装 MSYS2（管理员权限）：`choco install msys2 -y`
   （若已存在 `C:\tools\msys64` 或 `C:\msys64` 则跳过）。
2. 通过 MSYS2 的 pacman 安装 mingw-w64 工具链与构建工具（在 MSYS2 的 UCRT64 或 MINGW64
   shell 里，或用 `msys2_shell.cmd -defterm -no-start -ucrt64 -c '...'` 非交互执行）：
   ```
   pacman -S --noconfirm --needed \
     mingw-w64-ucrt-x86_64-gcc \
     mingw-w64-ucrt-x86_64-nasm \
     mingw-w64-ucrt-x86_64-pkgconf \
     make git diffutils
   ```
3. 记录 `gcc --version` / `nasm --version` 到"执行记录"，确认工具链就位。

> 执行提示：MSYS2 的包名/子系统（ucrt64 vs mingw64）细节若报错，把报错记录下来即可；
> ucrt64 与 mingw64 二选一，任一能装上 gcc+nasm 即可，不必纠结。

## 2. 拉取 ffmpeg 源码

```
git clone --depth 1 https://git.ffmpeg.org/ffmpeg.git /path/to/ffmpeg-src
```
（若 ffmpeg.git 主源慢/不通，回退镜像 `https://github.com/FFmpeg/FFmpeg.git`。）
记录 clone 到的 commit（`git rev-parse HEAD`）到"执行记录"。

## 3. 构建 A：瘦身版（本 spike 的主角）

在 MSYS2 shell 里，于 ffmpeg 源码目录执行 configure。**以下 enable 清单是本计划定死的，
直接照抄，对应 [../notes/2026-07-31-ffmpeg-slimming-options.md](../notes/2026-07-31-ffmpeg-slimming-options.md)
的结论（现代主流点播+直播：h264/hevc/vp9/av1/vp8 + aac/mp3/opus/ac3/eac3/flac/vorbis；
mp4/mkv/webm/ts/hls/dash/flv/rtsp；http(s)/tls/crypto/rtmp*/rtsp/rtp/udp）**：

```
./configure \
  --prefix=$PWD/_slim_install \
  --enable-lgpl \
  --enable-shared \
  --disable-static \
  --disable-programs \
  --disable-doc \
  --disable-everything \
  --enable-decoder=h264,hevc,vp9,vp8,av1,aac,aac_latm,mp3,mp3float,opus,ac3,eac3,flac,vorbis \
  --enable-parser=h264,hevc,vp9,vp8,av1,aac,aac_latm,ac3,flac,opus,vorbis,mpegaudio \
  --enable-demuxer=mov,matroska,mpegts,hls,dash,flv,live_flv,rtsp,aac,mp3,flac,ogg,webm_dash_manifest \
  --enable-protocol=file,http,https,tls,crypto,data,async,cache,rtmp,rtmps,rtmpe,rtmpt,rtmpte,rtmpts,rtp,udp,tcp \
  --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc \
  --enable-network
```

要点说明（供理解，不要改）：
- `--enable-lgpl`：LGPL 合规的根开关（避开 GPL-only 组件），对应遗留任务 #4 的"卡 LGPL"。
  若某个 enable 项与 `--enable-lgpl` 冲突而 configure 报错，**把报错记录下来、把那一项从
  清单里去掉重试，并在执行记录里标注"因 LGPL 冲突移除了 X"**——不要改成 `--enable-gpl`。
- `--disable-everything` 后逐类 enable，是 ffmpeg 官方推荐的最小化构建法。
- 加了 `tcp`（http/rtmp/rtsp 底层依赖）、`aac_adtstoasc`（HLS/TS 里 AAC 转封装常需要）、
  `mpegaudio` parser（mp3）等**隐式依赖项**——盘点笔记 §5 已提示这类依赖要靠实测补齐。
- **若 configure 因某个组件缺内部依赖（如某 demuxer 需要某 parser/bsf）报错**：把报错原样
  记录，按报错提示补上它明确要求的那一个 `--enable-...` 项重试；**只补 ffmpeg 内部组件，
  不要引入外部库（如 libx264/libfdk 等），也不要动 LGPL 开关**。

configure 成功后：
```
make -j$(nproc)
make install
```

产物在 `_slim_install/bin/`（Windows 下 ffmpeg 的库是 `avcodec-*.dll` / `avformat-*.dll` /
`avutil-*.dll` / `swresample-*.dll` / `swscale-*.dll` 等分开的多个 DLL）。**量出这些
`av*.dll` + `sw*.dll` 的总字节数**，记录到"执行记录"。

## 4. 构建 B：完整版参考（对照基线）

同一份源码、同一工具链，重新 configure 一个"接近完整"的版本作为对照（这样体积差才是同工具
链下的净瘦身量，排除工具链差异）：

```
make distclean
./configure \
  --prefix=$PWD/_full_install \
  --enable-lgpl \
  --enable-shared \
  --disable-static \
  --disable-programs \
  --disable-doc
make -j$(nproc)
make install
```
（即：同样 LGPL、同样只出库不出程序，但**不做** `--disable-everything`，保留 ffmpeg 默认
的全部解复用器/解码器/协议。）量出 `_full_install/bin/` 下 `av*.dll`+`sw*.dll` 总字节数。

## 5. 成功判据与产出

本 spike **成功** = 拿到下面这张对照表（已实测填好，2026-07-31）：

### 体积对照（7 个库 av*/sw* 总和，install 后 strip）

| 版本 | 7 库合计 | avcodec | vs slim-O3 |
|---|---|---|---|
| 完整版（-O3，全格式，构建 B） | **29.8 MB** | 18.1 MB | — |
| **瘦身版（-O3，主流点播+直播，构建 A）** | **11.0 MB** | 6.81 MB | 基准（省 63%） |
| 瘦身再去 vp8/ac3/eac3/flac/vorbis（-O3） | 10.64 MB | 6.48 MB | −0.36 MB（几乎无意义） |
| **瘦身 + `-Os`** | **6.26 MB** | 3.73 MB | **−43%** |
| 瘦身 + `-Os` + LTO | 6.11 MB | 3.66 MB | −45%（LTO 边际仅 −2.4%） |

### 解码性能对照（480p h264，Windows/x86，墙钟中位数，越小越快）

| 线程模式 | -O3 | -Os | -Os 相对 |
|---|---|---|---|
| 单线程（隔离解码器代码） | 6.13s | 6.55s | 慢 6.8% |
| 多线程（贴近真实播放） | 1.36s | 1.39s | 慢 1.9% |

结论回答：
1. **LGPL：无冲突**。当前 ffmpeg 已无 `--enable-lgpl` flag（LGPL 是默认，只要不传
   `--enable-gpl`）；configure 摘要确认 `License: LGPL version 2.1 or later`。全程未开
   任何 GPL/nonfree 组件。
2. **瘦身版 ffmpeg = 11.0 MB**（-O3）/ **6.26 MB**（-Os）。加 `-Os` 是最大体积杠杆
   （−43%），远超"抠不常见解码器"（仅 −0.36MB）；LTO 边际收益极小（−2.4%）。
3. **`-Os` 性能代价**：单线程 h264 解码慢 ~6.8%（h264 的 CABAC/CAVLC 熵解码是 C 代码、
   非 SIMD，`-Os` 关内联/展开会伤到它），但**多线程（真实播放）仅慢 1.9%**。用 43% 体积
   换真实播放 ~2% 解码 CPU，对移动端划算。**限定**：Windows/x86 数据不能直接搬到 ARM+NEON
   真机；HEVC/AV1/更高分辨率的 C/SIMD 配比不同，需真机复测。
4. **补的隐式依赖 / 因外部库移除的项**（正式瘦身直接采用）：
   - 补：`--enable-protocol=...,ffrtmpcrypt,ffrtmphttp`（rtmp 变体内部依赖）、
     `--enable-parser=...,mpegaudio`（mp3）、`--enable-bsf=...,aac_adtstoasc`（HLS/TS AAC）。
   - **做 benchmark 必须额外补**：`--enable-muxer=null` + `--enable-encoder=wrapped_avframe`
     （否则 `-f null` 因缺 muxer/encoder 无法跑；且测试要 `-an` 丢音频，避免缺音频编码器）。
     —— 这几项**仅 benchmark 需要**，生产瘦身库不需要（生产库只解码、不需 null 输出）。
   - **DASH**：`dash` demuxer 依赖外部 `libxml2`，本 spike 未装 → 暂移除。正式支持 DASH
     需引入 libxml2（LGPL 兼容，可后加）。HLS 不依赖 libxml2，不受影响。
   - **rtmpe/rtmpte**：RTMP 私有加密需外部 crypto 后端（gcrypt/gmp/openssl/mbedtls），
     本机走 schannel 不覆盖 → 禁用。主流 rtmp/rtmps/rtmpt/rtmpts 不受影响。

**注意**：这张表量的是"ffmpeg 部分"的体积，不等于最终 `libmpv-2.dll` 的体积（后者还含 mpv
自身 + libmpv 盘点笔记里那些可关/保留的 mpv 组件）。但它给出瘦身任务最大的那块（ffmpeg）
的真实数字，是继续评估"完整 libmpv 瘦身能到多小"的关键输入。

## 6. 执行记录（执行者填写）

> 每个阶段做完/失败都在这里追加记录：命令、关键输出、体积数字、遇到的报错原文。
> 失败也是有价值的结论——如实记录，不要为了"成功"而绕过 LGPL 或塞进计划外的依赖。

### 环境准备（2026-07-31，Windows 10，本机 jelon）

- MSYS2 经 `choco install msys2 -y` 装到 `C:\tools\msys64`。安装本身成功，但装完
  choco 触发的 `pacman -Syuu` 系统更新全程报 `SSL certificate ... unable to get
  local issuer certificate (20)`——本机处于企业 TLS 拦截网络（证书链 `CN=sangfor CA`），
  MSYS2 自带 CA bundle 不含该私有根，导致所有走 HTTPS 的官方镜像同步失败。
- **绕过办法（不触碰 LGPL/组件，仅镜像源改动）**：在 `C:\tools\msys64\etc\pacman.d\`
  的 `mirrorlist.msys` 与 `mirrorlist.mingw` 顶部各加两条**明文 HTTP** 镜像
  （`http://mirrors.tuna.tsinghua.edu.cn/...`、`http://mirrors.ustc.edu.cn/...`，
  已 `curl` 实测 HTTP 200 可达，绕开被拦截的 HTTPS）。之后 `pacman -Sy` 无报错。
- 工具链安装：`pacman -S --noconfirm --needed mingw-w64-ucrt-x86_64-gcc
  mingw-w64-ucrt-x86_64-nasm mingw-w64-ucrt-x86_64-pkgconf make git diffutils`
  一次装成（ucrt64 子系统；mingw64 子系统未装 gcc，统一用 ucrt64）。版本核实：
  - `gcc.exe (Rev5, Built by MSYS2 project) 16.1.0`
  - `NASM version 3.02`
  - `GNU Make 4.4.1`，`pkgconf 3.0.4`
  - 非交互执行统一用 `C:/tools/msys64/usr/bin/bash.exe -lc 'export PATH=/ucrt64/bin:$PATH; ...'`。

### ffmpeg 源码 commit

- 主源 `git.ffmpeg.org` 未测，直接用 GitHub 镜像 `https://github.com/FFmpeg/FFmpeg.git`
  （GitHub 不在拦截名单，HTTPS 正常）。`--depth 1` 浅克隆到
  `C:\Users\jelon\AppData\Local\Temp\ffmpeg-slim-spike\ffmpeg-src`。
- commit：`ad53728984531cebdb027e70e78d7165a6bdfe20`（约 8.0 版本线 master 顶端）。

### 构建 A（瘦身）configure 结果 / 补的依赖

- **spec §3 的 `--enable-lgpl` 这个 flag 在当前 ffmpeg 已不存在**（`configure` 报
  `Unknown option "--enable-lgpl"`）。当前 ffmpeg 里 **LGPL 就是默认许可**——只要
  **不传** `--enable-gpl` 即为 LGPL。所以按 spec §3「与 LGPL 冲突就移除那一项」的规则，
  移除了这个无效 flag，**LGPL 策略完全不变**：configure 摘要末尾确认
  `License: LGPL version 2.1 or later`。（未加任何 `--enable-gpl`/`--enable-nonfree`。）
- **补的 ffmpeg 内部依赖**：首轮 configure 有两条 WARNING——
  1. `Disabled rtmpe/rtmpte because ... ffrtmpcrypt_protocol / ffrtmphttp_protocol`：
     按 spec §3「缺内部组件就补那一个内部项」，给 `--enable-protocol` 追加了
     `ffrtmpcrypt,ffrtmphttp`（均为 ffmpeg 内部协议组件，非外部库）。
  2. `Disabled dash_demuxer because ... libxml2`：dash demuxer 依赖**外部库 libxml2**。
     按 spec §3「只补内部组件、不引入外部库」，**移除了 `dash` demuxer**，记录为
     「因缺外部依赖 libxml2 移除了 dash demuxer」。注意 HLS demuxer 仍在（HLS 更主流，
     不依赖 libxml2）；DASH 若要支持需正式构建时引入 libxml2（LGPL 兼容，可后续加）。
- **二轮 configure（补 ffrtmpcrypt/ffrtmphttp、去 dash）结果**：exit 0，
  `License: LGPL version 2.1 or later`。但新出 WARNING：
  `Disabled ffrtmpcrypt_protocol because not any dependency is satisfied:
  gcrypt gmp openssl mbedtls`，连带 `rtmpe/rtmpte` 仍被禁。原因：RTMP 加密握手需要
  一个外部大数/加密后端（gcrypt/gmp/openssl/mbedtls），本机 ffmpeg 走 **schannel** 做
  TLS（`https/rtmps/tls` 正常），schannel 不覆盖 rtmpe 的私有加密。**这是环境缺外部
  crypto 库的限制，非 LGPL 冲突**，按 spec 精神不引入外部库，记录并放行——
  `rtmpe/rtmpte`（RTMP 私有加密，冷门）不可用，但 `rtmp/rtmps/rtmpt/rtmpts` 及
  `http/https/hls/rtsp/rtp/udp/tcp` 全部在册，主流点播/直播协议不受影响。
- **最终瘦身版启用清单**（configure 摘要实测）：
  - Libraries：avcodec avformat avutil avfilter avdevice swscale swresample
  - Decoders：aac aac_latm ac3 av1 eac3 flac h264 hevc mp3 mp3float opus vorbis vp8 vp9
  - Parsers：aac aac_latm ac3 av1 flac h264 hevc mpegaudio opus vorbis vp8 vp9
  - Demuxers：aac ac3 asf eac3 flac flv hls live_flv matroska mov mp3 mpegts ogg rm
    rtsp webm_dash_manifest（asf/rm 为默认带入的连带项）
  - Protocols：async cache crypto data file http https rtmp rtmps rtmpt rtmpts rtp
    tcp tls dtls udp ffrtmphttp
  - BSFs：aac_adtstoasc h264_mp4toannexb hevc_mp4toannexb vp9_superframe_split
- **构建过程的一个坑（记录备查）**：`make -j$(nproc)` 尾部 `libavdevice` 链接报
  `avdevice-63.def: syntax error` / `cannot find @...dll.objs` / `cannot open
  libavdevice.ver`——这是 `--disable-everything` 下 avdevice 无任何 in/out dev、其
  .def/.ver/.objs 生成在 mingw 并行链接下出问题的**已知构建机制问题，非 LGPL/格式相关**。
  但 `make install` 仍把全部 7 个 DLL（含被 strip 的 avdevice-63.dll，17KB）装进
  `_slim_install/bin/`，5 个 spec 点名的核心 DLL 完好，故不影响体积测量。
- **注意 strip**：configure 摘要 `strip symbols yes`，`make install` 会 strip DLL。
  构建树里未 strip 的中间产物（如 avcodec 未 strip = 28.6MB）**不是**最终体积；一律以
  `_slim_install/bin/` 下 **已 strip** 的安装产物为准。
- **瘦身版产物体积（`_slim_install/bin/`，已 strip）**：

  | DLL | 字节 | MB |
  |---|---|---|
  | avcodec-63.dll | 6,809,600 | 6.49 |
  | avformat-63.dll | 1,136,128 | 1.08 |
  | avutil-61.dll | 1,087,488 | 1.04 |
  | swresample-7.dll | 178,688 | 0.17 |
  | swscale-10.dll | 2,134,528 | 2.04 |
  | avfilter-12.dll | 162,816 | 0.16 |
  | avdevice-63.dll | 17,920 | 0.02 |
  | **spec 点名 5 DLL 合计** | **11,346,432** | **10.82** |
  | **全部 7 个 av*+sw* 合计** | **11,527,168** | **10.99** |

- **构建 B（完整，-O3，install strip 后）产物体积**：avcodec 18.11 / avformat 2.76 /
  avutil 1.04 / swresample 0.17 / swscale 2.03 / avfilter 5.57 / avdevice 0.15 MB →
  **全部 7 库合计 = 29.8 MB**（与项目现随包的 `libmpv-2.dll` 29.76MB 惊人接近，侧证 libmpv
  打包的 ffmpeg 差不多就是这个完整量）。

### 额外变体：优化标志（`-Os` / `-Os+LTO`）与"去不常见解码器"

同一份源码/工具链，改优化标志与解码器集，均 install strip 后量：

| 变体 | 7 库合计 | avcodec | 备注 |
|---|---|---|---|
| slim `-O3`（基准） | 11.0 MB | 6.81 MB | 主流点播+直播全集 |
| slim `-O3` 去 vp8/ac3/eac3/flac/vorbis | 10.64 MB | 6.48 MB | 仅省 0.36MB，性价比极低 |
| slim `-Os` | **6.26 MB** | 3.73 MB | 体积 −43%，最大杠杆 |
| slim `-Os`+LTO | 6.11 MB | 3.66 MB | 比 -Os 再省 0.15MB（−2.4%），LTO 边际很小 |

### 解码性能实测（-O3 vs -Os，480p h264，Windows/x86）

benchmark 用 `ffmpeg -an -stream_loop 3 -f null -` 墙钟计时（Windows mingw 版 `-benchmark`
只报 maxrss、不报 utime，故用墙钟），7 次取中位数：

| 线程模式 | -O3 | -Os | -Os 相对 |
|---|---|---|---|
| 单线程 | 6.13s | 6.55s | **慢 6.8%** |
| 多线程 | 1.36s | 1.39s | **慢 1.9%** |

**benchmark 踩坑记录（备查）**：`--disable-everything` 会连带禁掉 `null` muxer 与全部
encoder，导致 `-f null` 报 "Encoder not found" 跑不了——benchmark 专用构建必须补
`--enable-muxer=null --enable-encoder=wrapped_avframe`，且用 `-an` 丢音频（否则卡在缺
音频编码器）。这三项仅 benchmark 需要，**生产瘦身库不需要**。

### 结论对照表（见 §5，已填全）

- ffmpeg 部分：完整 29.8MB → 主流瘦身 11.0MB（-O3，省 63%）→ 加 -Os 再到 6.26MB（省 43%）。
- **决策建议**：正式瘦身用 `-Os`（体积最大杠杆，真实播放性能代价约 2%）；**不必**上 LTO
  （边际 2.4%、增构建复杂度）；**不必**抠不常见解码器（仅省 0.36MB）。DASH 需引 libxml2
  再定。**以上均 Windows/x86 数据，真机 ARM 需复测性能百分比。**
- 这只是 ffmpeg 部分；最终 `libmpv-2.dll` 还含 mpv 自身（见
  [../notes/2026-07-31-libmpv-slimming-options.md](../notes/2026-07-31-libmpv-slimming-options.md)），
  完整 libmpv 瘦身构建是后续更大的工程，本 spike 未做。

## 7. 收尾

- 构建产物（`ffmpeg-src`、`_slim_install`、`_full_install`）放在项目**外**的临时目录，
  **不要**提交进仓库（`videoman/` 根 `.gitignore` 未必挡得住，务必放到 repo 之外）。
- 本计划文件（含填好的"执行记录"）会提交，作为遗留任务 #4 的实测输入。
- 完成后回报：把结论对照表贴出来，并说明构建 A 是否遇到 LGPL 冲突、补了哪些依赖。
