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

本 spike **成功** = 拿到下面这张对照表并填进本文件"执行记录 → 结论"：

| 版本 | av*.dll+sw*.dll 总体积 | 说明 |
|---|---|---|
| 完整版（构建 B） | ____ MB | 同工具链的对照基线 |
| 瘦身版（构建 A） | ____ MB | 只留主流点播+直播格式 |
| 省下 | ____ % | |

并回答：
1. `--enable-lgpl` + 上面的格式裁剪，configure 是否顺利成立（有没有哪一项因 LGPL 被迫移除）？
2. 瘦身版实际多大，量级是否接近"个位数 MB"？
3. 过程中补了哪些隐式依赖项（记录下来，供正式瘦身时直接采用）。

**注意**：这张表量的是"ffmpeg 部分"的体积，不等于最终 `libmpv-2.dll` 的体积（后者还含 mpv
自身 + libmpv 盘点笔记里那些可关/保留的 mpv 组件）。但它给出瘦身任务最大的那块（ffmpeg）
的真实数字，是继续评估"完整 libmpv 瘦身能到多小"的关键输入。

## 6. 执行记录（执行者填写）

> 每个阶段做完/失败都在这里追加记录：命令、关键输出、体积数字、遇到的报错原文。
> 失败也是有价值的结论——如实记录，不要为了"成功"而绕过 LGPL 或塞进计划外的依赖。

- 环境准备：_待填_
- ffmpeg 源码 commit：_待填_
- 构建 A（瘦身）configure 结果 / 补的依赖 / 产物体积：_待填_
- 构建 B（完整）产物体积：_待填_
- 结论对照表：_待填_

## 7. 收尾

- 构建产物（`ffmpeg-src`、`_slim_install`、`_full_install`）放在项目**外**的临时目录，
  **不要**提交进仓库（`videoman/` 根 `.gitignore` 未必挡得住，务必放到 repo 之外）。
- 本计划文件（含填好的"执行记录"）会提交，作为遗留任务 #4 的实测输入。
- 完成后回报：把结论对照表贴出来，并说明构建 A 是否遇到 LGPL 冲突、补了哪些依赖。
