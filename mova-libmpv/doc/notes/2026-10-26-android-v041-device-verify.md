# Android v041 包真机起播验证

日期：2026-10-26。设备 STG-AL00（`7NQBB23606003715`，同 Wi-Fi，真实 UDP），分支 main（HEAD e76a1126）。证据（不入库）在 `D:\tmp\v041log\`。

## 结论

1. 仓库 APK（`mova/example/build/app/outputs/flutter-apk/app-release.apk`）里 `lib/arm64-v8a/libmpv.so` = 6,354,048 B、sha256 `b54e16a0...1c43`，与 v041 包一致；`armeabi-v7a/libmpv.so` = 5,702,540 B、sha256 `08604e78...4d01`，也一致。无需重建。
2. 真机（arm64）上 WHEP H264 720p30、HTTP mp4、HTTP webm（VP9+opus）、HTTP mpegts 各起播一次，全部出画（screencap 实看到色条+计数），logcat 里 FATAL / SIGSEGV / SIGILL / SIGABRT / ANR / UnsatisfiedLinkError 均为 0。
3. WHEP 连续 13 分钟：Native Heap 平台期无增长，Graphics 不变；TOTAL PSS 有小幅波动（见下），未见与 libmpv 相关的持续增长。

## 做法

- 仓库 APK 入口是 `main_whep_verify.dart`（观察固定 40s、默认开 UDP 中继、mpv 日志 verbose），不适合长跑。所以把 `mova`、`mova_stt` 复制到 `D:\tmp\v041w`（仓库未改），换上 `main_amem.dart`（观察秒数读 `/data/local/tmp/whep_observe.txt`）和带 showWhenLocked 的 manifest，用 fvm flutter 3.47.1 构建：`flutter build apk --release -t lib/main_amem.dart --target-platform android-arm64 --dart-define=WHEP_RELAY_ON=false`。该副本用的就是 v041 包，APK 内 arm64 so sha 仍是 `b54e16a0...`；安装后设备上 base.apk sha 与本地一致。
  - 注意：不加 `WHEP_RELAY_ON=false` 时 app 会先去连本机不存在的 TCP 中继，抛异常，界面停在 "whep verify"，无任何输出。
- 源：MediaMTX v1.21.1（端口 18889/18189/18554，未碰 8889/8189）+ Windows ffmpeg testsrc 1280x720@30 H264 baseline 2.5M + opus；HTTP 用 `python -m http.server 18900` 提供 `D:\tmp\amem\www` 的 t.mp4 / v.webm / t.ts。
- 采样：每 20s `dumpsys meminfo`；logcat 改为后台落盘（设备 logcat 环形缓冲在 mpv 日志下会丢掉 `t+` 行）；用 `adb svc power stayon usb` 防熄屏。

## 起播结果（各观察 40s）

| 项 | 结果 |
|---|---|
| WHEP H264 720p30 | FIRSTFRAME 2.2s，size 1280x720，hwdec=mediacodec-copy，acodec=opus，fps 28.6-30，drop 15/0，pos 与墙钟一致，出画 |
| HTTP mp4（h264+aac） | 首帧 238ms，fps 30，drop 0/0，出画 |
| HTTP webm（VP9+opus） | 首帧 210ms，acodec=opus，fps 30，drop 0/0，出画（screencap 看到色条与计数） |
| HTTP mpegts（h264+aac） | 首帧 370ms，acodec=aac，fps 30，drop 0/0，出画 |

mp4/ts 的出画靠 screencap 文件大小（45 KB，纯黑约 17 KB）和与 webm/WHEP 同形判断，没逐张用眼看；WHEP 与 webm 两张已实看。

## WHEP 长跑（观察 780s，采样 40 个，窗口 770s 内）

| 窗口 | Native Heap | Graphics | TOTAL PSS |
|---|---|---|---|
| t>=120s（10.8 分钟） | +0.046 MiB/min（26.2->27.7） | -0.004（72.0 不变） | +0.42 |
| t>=300s（7.6 分钟） | +0.013 | +0.08（量化噪声，值恒为 72.0/73.7） | +0.67 |

- 对比 10-25 基线（Native +0.03、TOTAL +0.15）：Native 与 Graphics 一致；**TOTAL 斜率偏大（0.4-0.67 vs 0.15）**。TOTAL 在 155.7->163.6 MiB 间波动，Native/Graphics/Java 都平，增量来自其他类别（System/Unknown/Private Other），没在长跑里分类采样。
- 补测一次 7 分钟（`d1.txt`/`d2.txt`，t=90s 与 t=380s 两次完整 meminfo）：TOTAL 166,006 -> 166,046 KB（+40 KB，约 4.8 分钟），Native +1.9 MiB（预热尾巴）、Unknown +0.7、Private Other +0.6，其余不变。所以更像长跑里 System 类（跨进程图形缓冲等）的波动，而非 libmpv 泄漏；但样本只有这两次，不能完全排除缓慢增长。
- 本次 Native 稳态约 27 MiB，比 10-25 基线（96-98 MiB）低很多：本次 `main_amem` 与基线同源，差异原因没查（可能是 demuxer 缓冲预热行为随 so 版本/补丁变化，或本轮 mpv 日志级别/观察配置不同），仅记录事实。
- 长跑结尾 screencap 在观察结束后，已是黑屏（app 已 stop），没有长跑中途的画面截图；中途出画见补测 `long_mid.png`（约 3.5 分钟，色条+计数，实看）。
- drop：780s 内 238 帧（约 0.3/s），pos 781866ms 与墙钟一致。

## 未验证 / 注意

- armeabi-v7a 仍未运行验证（本机无 32 位 ARM 设备）。
- 声音没有实听，只确认 acodec 解出、pos 与墙钟同速。
- 手机有 PIN 锁屏；测试期间屏幕保持常亮（`stayon usb`，已还原），长跑前几次因熄屏拿到黑屏截图，已重测。
- 没有对仓库 `app-release.apk`（`main_whep_verify.dart` 入口）本身再跑一遍，用的是同 so 的 `main_amem` 副本构建；两者 so 的 sha 已核对一致。
- 收尾：MediaMTX、ffmpeg 推流、http.server 已按 PID 结束，测试 app 保留在手机（`main_amem` 版）。未改仓库文件，未提交；`auto.crt/auto.key` 不存在。

## 补充：TOTAL 斜率与 Native 稳态归因（20 分钟分类采样 + 对照）

日期同日。证据在 `D:\tmp\attr\`（`v041\`、`base\` 各 21 份 `dumpsys meminfo -a` 与 `/proc/<pid>/status`，`ana.py` 出表）。方法：同一台 STG-AL00、同一路 WHEP H264 720p30（MediaMTX 18889 + ffmpeg testsrc 2.5M，源全程不重启）、同一入口 `main_amem`、观察 1230s、每 60s 一次完整采样（t=0..1212s，21 点），斜率为最小二乘。

### 结论

1. **之前的 TOTAL +0.42 / +0.67 MiB/min 没有复现，不是持续增长。** 干净重跑 v041：t>=300s（15.1 分钟）TOTAL **+0.027 MiB/min**（155.0 -> 155.5），同窗口 Native +0.007、Graphics 0、Private Other +0.001、System +0.011、Unknown 0.000。旧数字来自 40 个 20s 采样里 TOTAL 在 161-165 间的台阶式跳变（见下"旧数据为什么偏大"），不是斜坡。
2. **Native 稳态 27 vs 97 MiB 的差异不是 .so，也不是测量口径，而是应用层 mova 代码不同。** 见下"对照"。
3. 没有发现 libmpv 相关的持续增长，结论可信度见"不确定性"。

### v041（新 mova + v041 so，sha b54e16a0...）斜率，MiB/min

| 类别 | t=0 -> 1212s 首/末 | 全程斜率 | t>=300s 斜率 |
|---|---|---|---|
| Native Heap | 26.8 -> 28.2 | +0.030 | +0.007 |
| Java Heap | 3.4 -> 8.5 | +0.075 | +0.003 |
| Code | 15.8 -> 16.1 | +0.005 | 0.000 |
| Graphics | 72.0 恒定 | 0.000 | 0.000 |
| Private Other | 11.8 -> 12.9 | +0.034 | +0.001 |
| System | 14.5 -> 16.7 | +0.057 | +0.011 |
| **TOTAL PSS** | 145.4 -> 155.5 | +0.206 | **+0.027** |
| RSS（meminfo） | 242.5 -> 255.6 | +0.299 | +0.134 |

全程的 +10 MiB 几乎全部发生在前 2 分钟（TOTAL 145.4 -> 154.4：Java Heap +5、Native +1.2、System +2、Unknown +0.8 等一次性预热），之后平。`/proc/<pid>/status` 的 RssAnon 反而在降（-0.69/min，57 -> 48，被换出/回收，VmSwap 25 -> 23），RssFile +0.11/min（108 MiB 左右，文件映射页缓存，不计入 Native/Private）。

### 对照：旧 mova + 同一个 so（apk_base.apk）

- **关键事实：`D:\tmp\amem\apk_base.apk` 里 arm64 `libmpv.so` sha256 就是 `b54e16a0...1c43`，与 v041 包完全一致。** 10-25 的"基线"并不是旧 .so，只是旧版 mova 代码。仓库里旧包 `media_kit_libs_android_video_slim` 的 jniLibs 是 132 字节的 LFS 指针（未拉取），所以拿不到真正的 n6 旧 so，本次没有做"旧 so"对照。
- 入口 `main_amem.dart` 在 `D:\tmp\w12`（10-25 基线构建）与 `D:\tmp\v041w`（本次）逐字相同（diff 无差异）。差异在 `mova/lib` 本身：新版多了 `mpv_kernel.dart` / `mpv_defaults.dart` 里的实时源缓冲限制——WHEP 流打开后 `file-format=whep`，把 `demuxer-max-back-bytes` 设为 0、`demuxer-seekable-cache` 设为 no（`kRealtimeFileFormats = {'whep'}`、`kLiveMaxBackBytes = '0'`）。旧版没有。两边其余差异（standby/guard/first_frame 等 UI 与生命周期代码、pubspec 指向 v041 包）与内存无直接关系。
- 同方法同流 20 分钟，旧 mova：

| 类别 | 首 -> 末 | 全程斜率 | t>=300s 斜率 |
|---|---|---|---|
| Native Heap | 27.4 -> 93.7 | +2.124 | +0.028 |
| Graphics | 68.5 -> 72.0 | +0.046 | 0.000 |
| Private Other | 12.6 -> 14.3 | +0.048 | +0.029 |
| System | 14.1 -> 14.7 | +0.017 | +0.010 |
| TOTAL PSS | 142.4 -> 219.4 | +2.310 | **+0.073** |

  Native 前 5 分钟从 27 涨到 93 MiB 后封顶（与 10-25 的结果一致），所以 97 MiB 是后向缓冲吃满；新 mova 把后向缓冲限为 0，Native 就稳在 28 MiB。**同一个 so，同一个入口，只差 mova 代码，Native 稳态差 65 MiB**，这就把"测量口径/so 版本"两种猜测排除了；剩下"是 `demuxer-max-back-bytes=0` 造成的"我是由代码+现象推断，没有在设备上回读 mpv 属性验证。
- 稳态 t>=300s：旧 mova TOTAL +0.073，新 mova +0.027，同量级，都 <0.1 MiB/min。

### 旧数据（13 分钟，+0.42 / +0.67）为什么偏大

那次是 20s 间隔 40 个点，TOTAL 在 161.6 / 163.4 / 164.2 / 165.1 / 168.8 之间跳变，其中最大的几次跳变同时对应 Graphics 在 72.0 / 73.7 之间量化翻转（`EGL mtrack` 值只取几个离散档），Dalvik Heap 在 2.6 / 7.8 间翻转（GC 后/前），System 有 -1.7 台阶。窗口很短时，一两个台阶落在窗口端点就能拉出 0.4-0.7 的斜率；15-20 分钟窗口里这些台阶不再单调累积。本次干净重跑没有再出现。

### 不确定性 / 做不到的

- **无法取 `smaps` / `smaps_rollup`**：设备是 user 版、无 root，shell uid 读 `/proc/<pid>/smaps_rollup` 与 `smaps` 返回 `Permission denied`，所以没有 Pss_Anon/Pss_File/Pss_Shmem，更无法按映射区间对比起末快照。替代：`dumpsys meminfo -a` 的分映射类别（Native/Dalvik/.so/.apk/EGL/Unknown 等）与 `/proc/<pid>/status` 的 RssAnon/RssFile/RssShmem（是 Rss 不是 Pss）。由于 TOTAL 在稳态没有可测增长，没有可追的"增长最多映射"。
- 每种配置只跑了 1 次 20 分钟，没有重复；稳态斜率 +0.027 与 +0.073 的差异在噪声内，不能据此说新版更省。
- 第一次尝试 v041 跑时，我误留了一个没杀掉的采样脚本并发写同一目录（采样互相交错、还重启了一次 app），该批数据（`D:\tmp\attr\v041_dirty`）作废，上面表格全部来自后续干净重跑；那批数据里 Graphics 是 85.5 而非 72.0，原因没查，推测与并发重启 app 有关，不作结论。
- 只测了 arm64、WHEP H264；armeabi-v7a 仍未运行验证；Graphics 没有长期变化只说明此设备此路径。
- 收尾：MediaMTX（PID 33052）、ffmpeg（PID 35760）已按 PID 结束；手机侧 `whep_url.txt` / `whep_observe.txt` 已删，`stayon` 已还原，测试 app（v041 版 main_amem）留在手机上；未改仓库其他文件，未提交；`auto.crt/auto.key` 不存在。

## 补充：armeabi-v7a 32 位真机运行验证

日期同日。证据在 `D:\tmp\v7\`（`logs\`、`v7a.apk`）。STG-AL00 的 abilist 含 armeabi-v7a，可以 32 位进程跑 app，所以这次是真机运行 v041 的 armeabi-v7a so，不再只是符号级。

### 结论

1. **armeabi-v7a 的 libmpv.so（sha 08604e78...4d01）在真机上 32 位进程里跑通：WHEP H264 720p30、HTTP mp4、webm(VP9+opus)、mpegts 都起播并出画（四张 screencap 都实看到色条+计数），logcat 里 SIGILL / SIGSEGV / SIGABRT / FATAL / ANR / UnsatisfiedLinkError 全为 0（5 轮，含 650s 长跑）。**
2. 音频：四种源起播时 `dumpsys audio` 都有该 app 的 OpenSL ES AudioPlayer（state:started），`media.audio_flinger` 里有 Active=yes 的 track（48000 Hz，Server 计数持续前进，FrmRdy 满）。**声音未实听**，只是系统层确认在出流。
3. WHEP 长跑 650s：t>=300s 窗口 TOTAL 斜率 -0.12 MiB/min、Native +0.009 MiB/min（6 个点，约 5 分钟），arm64 参考是 TOTAL +0.027、Native +0.007，同量级、无持续增长。

### 做法

- 在 `D:\tmp\v041w`（仓库副本，仓库未改）里把 `example/android/app/build.gradle.kts` 的 abiFilters 改成只含 armeabi-v7a，用 fvm flutter 3.47.1：`flutter build apk --release -t lib/main_amem.dart --target-platform android-arm --dart-define=WHEP_RELAY_ON=false`。
- **坑：这样出来的 APK 仍带 arm64-v8a（含 libmpv.so）和 x86_64 的 so**（onnxruntime/sherpa 等插件的 jniLibs 不受 abiFilters 限制），安装后 `primaryCpuAbi=arm64-v8a`，会按 64 位跑，等于没测。处理：用脚本删掉 APK 里 `lib/` 下 armeabi-v7a 以外的条目，zipalign + 用 debug keystore 重新 apksigner 签名（`D:\tmp\v7\v7a.apk`），重新安装后 `pm dump` 显示 `primaryCpuAbi=armeabi-v7a`、`secondaryCpuAbi=null`。APK 内 `lib/armeabi-v7a/libmpv.so` sha 08604e78...（核对一致）。
- 32 位进程确认：user 版无 root，`/proc/<pid>/maps`、`exe` 读不了（Permission denied），所以没看到 linker 与 so 映射。替代证据：app 进程 PPID=808，`ps` 显示 808 是 `zygote`（32 位），`zygote64` 是 807；加上 primaryCpuAbi 与 APK 里只有 v7a 的 so，足以认定是 32 位进程。`dumpsys meminfo -a` 的 `.so mmap` 也有数据，没单独列出 libmpv 路径。
- 源：MediaMTX v1.21.1（`D:\tmp\mtx\amem.yml`，18889/18189/18554）+ WinGet Packages 下真实路径的 ffmpeg 9.0.2 testsrc 1280x720@30 H264 baseline 2.5M + opus（RTSP 推到 MediaMTX，手机走局域网 WHEP，UDP 真实）；HTTP 用 `python -m http.server 18900` 提供 `D:\tmp\amem\www` 的 t.mp4 / v.webm / t.ts。入口 `main_amem`，logcat 后台落盘。

### 起播结果（各观察 40s，WHEP 650s）

| 项 | 结果 |
|---|---|
| WHEP H264 720p30 | FIRSTFRAME 1.7s，1280x720，hwdec=mediacodec-copy，acodec=opus，fps 29.1-29.7，drop 15/0（40s），出画 |
| HTTP mp4（h264+aac） | 首帧 367ms，fps 30，drop 0/0，出画 |
| HTTP webm（VP9+opus） | 首帧 158ms，fps 30，drop 0/0，出画 |
| HTTP mpegts（h264+aac） | 首帧 238ms，fps 30，drop 0/0，出画 |

### WHEP 长跑（观察 650.9s，posDelta 651.9s，每 60s 一次 `dumpsys meminfo`，11 点）

| 窗口 | TOTAL PSS | Native Heap | Graphics | Java |
|---|---|---|---|---|
| t>=300s（6 点，约 5 分钟） | -0.12 MiB/min（197.6->196.8 起末波动） | +0.009 | 0（恒 75.6，见下） | +0.017 |
| 全程 | +0.86（含前 5 分钟预热，190.9->202.3 后回落到 196.8） | +0.106 | +0.44 | +0.22 |

- TOTAL 绝对值（约 190-202 MiB）比 arm64 的 155 MiB 高：32 位 Code 段 49 MiB（arm64 约 16 MiB），Native 稳态 25 MiB，和 arm64 的 27 MiB 接近。Code 高的原因没细查。
- Graphics 在 t≈244s 由 72.0 跳到 75.6 MiB 后恒定（EGL mtrack 离散档，之前 arm64 也见过量化翻转），之后不变，不是持续增长。
- drop 209/0（650s）。样本只有 1 次、窗口 5 分钟（t>=300s 仅 6 点），斜率只能说"无明显增长"，不是 arm64 那次 20 分钟级别的精度。
- **长跑结尾 screencap 是黑屏+锁屏图标**：这次脚本没开 `stayon`，手机中途熄屏锁屏，所以没有长跑中途的画面；pos 与墙钟同步、fps 正常、音频 track 在 k=1/k=3 采样时 active（k=2 那次瞬间 `state:stopped`，k=3 又 started，原因没查，可能是熄屏/standby 逻辑）。出画证据来自前面 4 轮 40s 的截图。
- mpv 的 audio 属性：验证入口没打印，没取。

### 收尾

- 手机当前装的是 **32 位测试包 `D:\tmp\v7\v7a.apk`**（`main_amem` 入口，仅 armeabi-v7a，debug 签名，包名 com.icodejoo.mova.mova_example），app 已 force-stop，`/data/local/tmp/whep_url.txt`、`whep_observe.txt` 已删。要回到 arm64 测试包需重装（`D:\tmp\v041w` 构建出的 arm64 APK 要先把 abiFilters 改回，该副本现在是 v7a-only）。
- MediaMTX（PID 35172）、http.server（PID 8496）已按 PID 结束；ffmpeg 推流（PID 35284）收尾时已不存在（taskkill 报找不到，推流在测试期间一直在，原因没查），没动别的会话的进程。仓库只新增本节笔记，未提交，`auto.crt/auto.key` 不存在，没碰 `mova/libmpv/README.md` 与 mpv-0007 笔记。
