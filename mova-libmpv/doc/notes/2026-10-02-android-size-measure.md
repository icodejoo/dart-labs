# Android arm64 体积复核：ffmpeg n6.0.1 vs n9.0.2（WSL 交叉编译）

日期：2026-10-02。承接 [t02 真实 flavor spike](2026-10-02-t02-real-flavor-spike.md)。只记结论与证据；
构建目录 WSL `/root/w/andm/`（脚本 `build.sh`，`$1`=0/1 控制 LTO），换机器即失。

## 1. 结论

**Android arm64 上 n6.0.1 -> n9.0.2 的 ffmpeg 升级约 +0.80MB（+13.4%~13.8%），比 Linux spike 的 +500KB 大。**
加 mpv v0.41.0（摘 vo_gpu_next + javavm 补丁）后合计约 +0.95MB（+16%）。

stripped `libmpv.so` 字节（llvm-strip -s，arm64 API24，NDK r25c）：

| 组合 | 非 LTO | 整链 LTO |
|---|---|---|
| n6.0.1 + 钉死 mpv `78d43740f5`（无 libplacebo） | 6,147,712 | 5,815,040 |
| n9.0.2 + 钉死 mpv + 兼容补丁 | 6,969,304 | 6,615,960 |
| n9.0.2 + v0.41.0 + libplacebo + 摘 vo_gpu_next + javavm-v041 | 7,127,064 | 6,768,032 |
| n9 钉死 相对 n6 | +821,592 (+13.4%) | +800,920 (+13.8%) |
| n9 + v0.41.0 摘补丁 相对 n6 | +979,352 (+15.9%) | +952,992 (+16.4%) |

- n6 两行本次实测（`/root/w/andm/n6-0.stripped.so`、`n6-1.stripped.so`，ffversion.h 确认 `n6.0.1`）。
- n9 的三行**不是本次重编**，取自上一轮留在 `/root/w/mpvt/eval/` 的 `andout-pin`、`andout-v041-B3`、`andoutlto-pin`、`andoutlto-v041-B3`
  （同一套 `and-deps*.sh` 依赖前缀、同一 cross 文件）。n6 这边是复用同一份依赖前缀，只重编 ffmpeg 与 mpv，口径一致。
- 增量主要在 `.text`：LTO 下 n6 3,576,544 vs n9 4,144,836（+568,292）；`.rodata` +89,568，`.rela.dyn` +38,040，`.eh_frame` +49,912，`.data.rel.ro` +33,912。
  （llvm-size -A 实测。静态库对比：libavcodec.a 15.6MB vs 20.0MB，libavformat.a 6.4MB vs 7.3MB，libavutil.a 2.8MB vs 3.2MB。）
  **具体是 n9 哪些代码/表导致的没拆**。

## 2. 口径限制（必读）

- 这是**近似 flavor**，不是 CI 真实 flavor：没有 libdav1d（真实 flavor 含，约 +671KB，两边都不含，不影响差值但影响绝对值）；
  mbedtls 3.6.7（真实 3.4.0）、freetype/harfbuzz/fribidi/libass 版本也不同；ffmpeg 是 n6.0.1（真实 `v_ffmpeg=6.0`）；
  mpv 无 `mpv_lavc_set_java_vm` 补丁（钉死那行）。绝对值不能和仓库里 6,050,104 比，**只看同口径差值**。
- n9 钉死那行带 `pin-n9-compat.patch`（让旧 mpv 编 n9），对体积的影响未单独量。
- 没做真机/冒烟，只量体积。没拆增量来源。

## 3. 本机能否构建（实测）

- Windows 侧：`E:\sdk\android\ndk\` 存在（含哪些版本没列，**未核实**）；`C:\Users\jelon\AppData\Local\Android` 不存在。
- WSL（Ubuntu，18 核、11.9GB 内存、939GB 空闲）：meson、ninja、cmake、nasm、pkg-config、python3 齐全；
  **NDK r25c 已在 `/root/w/mpvt/eval/ndk/android-ndk-r25c`**（与 CI 同版本）；ffmpeg 源 `/root/w/ffmpeg`（有 n6.0.1 tag）、`/root/w/ff902`（有 n9.0.2 tag）；
  依赖源码 `/root/w/mpvt/eval/dl/`、mbedtls `/root/w/mbedtls`；已编好的 arm64 依赖前缀 `and-prefix`（非 LTO）、`and-prefix-lto`。
- 缺：没有 dav1d、libxml2 的交叉编译（真实 flavor 要）；没有 `libmpv-android-video-build@1ecf510` 的真实脚本链在 WSL 里跑过（本次也没跑）。
- 耗时（实测）：n6 ffmpeg+mpv 非 LTO 47 秒，整链 LTO 2 分 27 秒（make -j8）。**单 ABI 本地很快。**

## 4. CI 能否传参（读 workflow，未改）

`.github/workflows/build-mova-libmpv.yml`：`workflow_dispatch:` **没有 inputs**，也**没有 FFMPEG_REF/MPV_REF 变量**。
ffmpeg 版本写死在两处：`libmpv-android-video-build@1ecf510` 的 `buildscripts/include/depinfo.sh`（`v_ffmpeg=6.0`、`v_mpv=78d43740...`）
和 `download-deps.sh`（`git clone --branch n$v_ffmpeg`、mpv `git reset --hard 78d43740...`）；`ANDROID_LIBMPV_BUILD_REF`、`NDK_VERSION` 在顶层 env。
Linux job 里 `git clone --depth 1 --branch n6.0.1` 也写死（约 789 行）。

参数化方案（只给方案）：
1. `workflow_dispatch.inputs` 加 `ffmpeg_ref`（默认 `6.0`）、`mpv_ref`（默认钉死 hash）、`commit_artifact`（默认 false）。
2. 在 "Clone libmpv-android-video-build" 之后加一步 `sed -i "s/^v_ffmpeg=.*/v_ffmpeg=${{ inputs.ffmpeg_ref }}/" buildscripts/include/depinfo.sh`，mpv 同理（`download-deps.sh` 里 hash 重复写了一遍，要连它一起 sed）。
   注意 `git clone --branch n$v_ffmpeg` 要求传 `9.0.2`。
3. **deps 缓存 key 只含 `ANDROID_LIBMPV_BUILD_REF`**，换 ref 必须把 ffmpeg/mpv ref 拼进 key，否则复用旧源码（同类问题 x86 job 已踩过）。
4. "Commit built artifact to packages/" 步骤必须加 `if: inputs.commit_artifact != true` 的反面保护（实验构建不能回写 `packages/`，会覆盖发布产物）。
5. 还要处理 ffmpeg 补丁（见 5）。

## 5. 新发现：真实 Android 链的两个 ffmpeg 补丁在 n9.0.2 上都打不上（实测）

`buildscripts/patches/ffmpeg/` 下 `dash_base_url_escape.patch`、`hls_mp4_seek.patch` 对 n6.0.1 `git apply --check` 通过，
对 n9.0.2 都失败（`libavformat/dashdec.c:768`、`libavformat/hls.c:2506` hunk 不匹配）。
是否已被上游吸收、是否需 rebase 重做**未核实**。T0.6 要把这两个补丁的去留作为前置项。

## 6. 本地 WSL 与 CI 对比（评估，推断成分较多）

- 本地：单 ABI 1~3 分钟出数，能随手加减选项做 A/B，适合**拆增量来源**和选项取舍；缺点是不是真实脚本链（缺 dav1d 等），数字只看差值。
- CI：权威（真实 flavor、真实 NDK 缓存），但目前不能传参、改 workflow 才能跑、每次要拉源码并编全依赖（耗时本次未量，**不知道**），
  且有回写 `packages/` 的副作用。
- 建议：先在本地补 dav1d 并拆增量来源、决定选项；再做 CI 参数化跑一次真实 flavor 做最终确认。
