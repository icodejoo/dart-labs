# Android 内存基线、0006/0007 重编对比、--disable-bsfs 核对

日期：2026-10-25。设备 STG-AL00（`7NQBB23606003715`，手机 192.168.254.136，PC 192.168.254.110，同 Wi-Fi，真实 UDP）。分支 `feat/whep-receiver`，HEAD 7828bc83。证据（不入库）在 `D:\tmp\amem\`（`logs\*.csv` 采样、`so\` 三个临时 so、`tools\`）。

## 结论

1. **Android 没有 Windows 那种持续增长**。720p30 WHEP H264 播 16.9 分钟：稳定后（t>=300s，11.7 分钟）Native Heap 斜率 +0.03 MiB/min，Graphics 约 +0.05（锯齿抖动 70/74 MiB，非趋势），TOTAL PSS +0.15 MiB/min，均 <1 MiB/min。
2. 前 4 分钟 Native Heap 从 29 MiB 涨到约 98 MiB 后封顶（疑为 demuxer/解码缓冲填满，之后平台期不动）。所以"全程拟合"斜率会被预热段拉高到 2.5 MiB/min，不能当泄漏。
3. 含 0006+0007 重编的 so 在 Android 上行为不变（预期内，0007 只在 GL_RENDERER 含 ANGLE 时生效），出画正常，斜率同量级。
4. `--disable-bsfs`：**Android n9 flavor 早已包含**（见下），没有可省的 340 KB；真机回归按 A 版（已含 disable-bsfs）做了，H264 WHEP/mp4/webm(VP9)/ts 全部能播。
5. **WHEP 没有 VP9**：offer 只带 opus + H264（`0003` 的 SDP 只写 H264/rtx），MediaMTX 报 `codecs not supported by client`。所以"WHEP VP9"在当前实现下不是回归项，不是 bsfs 的问题。这是计划有意的范围：`doc/plans/2026-10-01-whep-receiver.md` 第 83 行（H.264 + Opus 起步）、第 164 行（决策 A9）、第 638 行（"不做"）。要支持需新增 SDP、answer 选 codec 和 VP9 RTP 解包，属于新任务。

## 1. 内存基线（仓库 so，sha `b54e16a0...`，6,354,048 B，无 0006/0007）

方法：示例验证 app 的副本（`main_amem.dart`，从 `main_whep_verify.dart` 派生：mpv 日志降到 warn，观察秒数读 `/data/local/tmp/whep_observe.txt`；manifest 加了 showWhenLocked/turnScreenOn，只在 `D:\tmp\w12\mova` 副本里）。MediaMTX v1.21.1（端口 18889/18189/18554，未碰 8889/8189），Windows ffmpeg testsrc 1280x720@30 H264 baseline 2.5M + opus。每 20s `dumpsys meminfo`，50 个样本。`hwdec=mediacodec-copy`，fps 29.4-30，pos 与墙钟一致（1105s 内 pos 1107.8s），全程 `vo drop` 212 帧。

| 窗口 | Native Heap | Graphics | TOTAL PSS | Java |
|---|---|---|---|---|
| 全程 0-16.9min | +2.45 MiB/min（28.7->96.2） | +0.02（72.0->72.0） | +2.57（143->214） | +0.01 |
| t>=120s（14.9min） | +0.83（预热尾巴） | +0.05 | +0.94 | -0.00 |
| t>=300s（11.8min） | **+0.03** | +0.05 | **+0.15** | +0.00 |
| t>=600s（6.9min） | +0.01 | 0.00 | +0.02 | +0.00 |

Native 稳定在 96-98 MiB，Graphics 70-74 MiB 抖动，TOTAL 212-219 MiB。

## 2. 0006+0007 重编（A 版）

- WSL 用 `e2e-arm64.sh`（WHEP=1，JOBS=16，NDK 参数用 `/root/w/ndk/android-ndk-r25c`，第二个参数是 NDK r25c 目录本身）。工作目录 `/root/w/amem/A`，约 10 分钟。第一次因 github 瞬断（mpv/media-kit-android-helper clone 超时）失败，重跑成功。脚本里 `apply-v041.sh` 已含 0006/0007，所以"含 0006+0007"就是当前仓库补丁集。
- 注意：`git archive` 出来的 sh、`libmpv-android-video-build.patch`、`android-v041/*.patch`、flavor 是 CRLF，在 WSL 直接跑会 `patch does not apply`，副本里要先 `sed -i 's/\r$//'`（仓库内未改）。
- 产物：strip 后 **6,354,160 B**（+112 B vs 仓库 so），sha `3d92bae9...b5bd`，`strings` 含 `ANGLE`（仓库 so 里没有）。仓库 so 是 10-24 构建的，早于 0006/0007，所以本次确实是"有 vs 无"对比。
- 同条件（同 app、同流、1140s 观察、50 样本）：

| 窗口 | Native | Graphics | TOTAL |
|---|---|---|---|
| 全程 16.9min | +2.40 | +0.16 | +2.68 |
| t>=120s | +0.80 | +0.03 | +0.95 |
| t>=300s | **+0.02** | -0.03 | **+0.11** |

  与基线同形：预热后平台。起播出画正常（hwdec=mediacodec-copy，fps 29.4-30，drop 311/0，logcat 无 FATAL/SIGSEGV/UnsatisfiedLinkError）。结论：0006/0007 在 Android 上无副作用、无可见收益（因为本来就没有增长）。
- 注意：缓冲预热增长（约 70 MiB/4 分钟）是否应限制（`demuxer-max-bytes` 等）不在本次范围，见 2026-10-24-realtime-demuxer-cache-limit.md。

## 3. --disable-bsfs

- **实际情况**：`flavors-mova-slim-n9.sh` 第 156-157 行已经是 `--disable-bsfs` + `--enable-bsf="$BSFS"`（BSFS 12 个，第 75 行）；A 版 `config.mak` 里 `CONFIG_*_BSF=yes` 正好 12 个。仓库里 10-24 的 so 同样是这个配置。所以 Android 无需再加，也没有需要改的位置。
- 对照：临时副本去掉这两行（全 bsf，D 版，`/root/w/amem/D`，仅构建不上机）config 里 50 个 bsf，strip 后 **6,839,960 B**，比 A 版大 **485,800 B**。即 `--disable-bsfs` 在 Android 上已经省了约 474 KiB。"预计省约 340 KB"对应的应是别的构建（10-02 的调研：n6 -295 KB；CI linux/windows 的 workflow 只写了 `--enable-bsf=` 没写 `--disable-bsfs`）。如要落实，需检查的位置是 `.github/workflows` 里 linux/windows 的 ffmpeg configure（以及 `tools/whep-flavor/build-linux.sh`、`build-windows.sh` 的 configure）是否带 `--disable-bsfs`；我没改也没测。
- 真机回归（A 版 so，已含 disable-bsfs；各约 40-45s，不是 2-3 分钟，加上 H264 WHEP 的 17 分钟）：

| 项 | 结果 |
|---|---|
| WHEP H264 720p30（MediaMTX） | 能播 17 分钟，pos 与墙钟一致，无 FATAL |
| WHEP VP9 | **不适用**：offer 无 VP9，服务端拒绝（`codecs not supported by client`），播放器 size 0x0 |
| HTTP mp4（h264+aac，faststart） | 45s 内 pos=44800，1280x720，acodec=aac，fps 30，drop 0/0 |
| HTTP webm（VP9+opus，mediacodec-copy） | 40s，pos=39373，acodec=opus，drop 0/0 |
| HTTP mpegts（h264+aac） | 40s，pos=39788，acodec=aac，drop 0/0 |

  各路 logcat 的 FATAL/SIGSEGV/SIGABRT/ANR/UnsatisfiedLinkError 计数均为 0。播中截屏（`mid_mp4/webm/ts.png`，44-69 KB，纯黑屏约 17 KB）与基线（色条+计数）一致，有画面。

## 未验证 / 注意

- **声音没有实听**：只确认了 acodec 解出、pos 与墙钟同速、无 underrun 类报错；没有验证扬声器输出。
- 手机有 PIN 锁屏，我没有也没猜密码：用 manifest 的 showWhenLocked 让测试 app 在锁屏上方显示（只在 `D:\tmp\w12` 副本）。`dumpsys meminfo` 与锁屏无关，但锁屏下 SurfaceView 行为与解锁后是否有差别未单独对比。
- WHEP 之外未做 HEVC、AV1、HLS 的 bsf 回归；`hevc_mp4toannexb`、`aac_adtstoasc` 路径只被 mp4/ts 间接覆盖。
- 没做 0006 单独的验证（0006 只修 GLsync 释放，Android 无增长，无法区分）。
- 样本总时长 16.9 分钟（要求 >=15）；基线与 A 版没有交替重复，差异（Graphics 全程斜率 0.02 vs 0.16）在噪声范围内（锯齿幅度约 3.6 MiB）。
- 收尾：MediaMTX、H264 推流、http.server 已按 PID 停；WSL 的 VP9 推流 `timeout 700` 自行结束；手机侧 `whep_url.txt` / `whep_observe.txt` 已删，测试 app 仍装在手机上（含 A 版 so，非仓库 so）。没有改仓库脚本、没有提交、没有写入任何 .so 到仓库。
