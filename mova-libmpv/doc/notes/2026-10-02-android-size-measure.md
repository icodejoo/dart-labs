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

## 7. 瘦身配方复测（n6 / n6 瘦身 / n9 瘦身 / n9+v0.41）

日期：2026-10-02。WSL `/root/w/andm2/`（脚本 `build2.sh VAR LTO`，换机器即失），均为**本次实测重编**，arm64 API24、NDK r25c、llvm-strip -s，
复用 `and-prefix(-lto)` 依赖前缀（无 dav1d，口径同 §2），make -j8。

| 组合 | 非 LTO | 相对 (a) | 整链 LTO | 相对 (a) |
|---|---:|---:|---:|---:|
| (a) n6.0.1 现行（沿用 §1，`andm/n6-{0,1}.stripped.so` 复核字节一致） | 6,147,712 | 0 | 5,815,040 | 0 |
| (b) n6.0.1 + `--disable-bsfs`（置于 `--enable-bsf=` 前，去掉 `--enable-bsfs`） | 5,888,912 | -258,800 (-4.2%) | 5,560,296 | -254,744 (-4.4%) |
| (c) n9.0.2 + `--disable-bsfs --disable-iamf --disable-swscale-alpha`，去 `--enable-bsfs`/`--disable-postproc`，钉死 mpv + 兼容补丁 | 6,445,568 | +297,856 (+4.8%) | 6,108,976 | +293,936 (+5.1%) |
| (d) (c) + mpv v0.41.0 + libplacebo + 摘 vo_gpu_next + javavm-v041 | 6,603,344 | +455,632 (+7.4%) | 6,261,144 | +446,104 (+7.7%) |

派生差值（同口径）：

| 对比 | 非 LTO | 整链 LTO |
|---|---:|---:|
| (c) - (b)：n9 瘦身 vs n6 同样瘦身 | +556,656 (+9.5%) | +548,680 (+9.9%) |
| (d) - (c)：mpv 0.41 + plc 增量 | +157,776 | +152,168 |

注意：(a) 的配方里本来就有 `--disable-swscale-alpha`，所以 (b) 相对 (a) 实际只多了 `--disable-bsfs`；n6 的 `--disable-postproc` 保留。

### 结论

- **n9 瘦身后 vs n6 现行（a）：不是 ≤，仍大 +294KB~+298KB（约 +5%）**。与 Linux x86 调研（§0 of ffmpeg9-slim-research，A 集 -8KB）不一致：
  arm64 上 n6 现行的 bsf 全开代价（-259KB）比 Linux 上小，n9 的结构性增长反而更大。
- **n9 瘦身后 vs n6 同样瘦身（b）：更不是，+549KB~+557KB（约 +9.5%）**。研究文档推测"arm64 真实差距小于 x86 的 +324KB"，**本次实测推翻**：arm64 上差距更大。
- 走完整升级路径（d）相对现行 +446KB~+456KB（+7.4%~+7.7%）；比未瘦身的 n9 路径（§1 表：+953KB/+979KB）省约 500KB。
- 体积第一的立场下：n9 不能靠 configure 开关追平 n6；n6 自己也该先上 `--disable-bsfs`（-255KB，零功能代价待验证 bsf 白名单够用）。

### 口径与未做

- (a)/(b) 用干净 clone 的钉死 mpv `78d43740f5`（无补丁）；(c) 用 `src-pin-and`（含 n9 兼容补丁 + javavm 补丁，与 §1 的 n9 行同源）。mpv 侧补丁差异未单独量化，
  会混入 (c)-(b) 的差值，但补丁只 49 行增/29 行删，预计影响远小于 500KB（**推断**）。
- **dav1d 没补成**：WSL 内源码目录 `dl/` 没有 dav1d，`git clone code.videolan.org` 报 SSL 证书签发者不受信（环境层面的 CA 问题），未绕过校验。
  需要用户给出 dav1d 源码包或修好 WSL CA 才能继续；真实 flavor 含 dav1d（约 +671KB），不影响本表差值。
- 没做 Enabled bsfs 之外的功能冒烟，没做真机。
