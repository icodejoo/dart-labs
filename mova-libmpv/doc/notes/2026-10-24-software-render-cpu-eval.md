# Windows 软件渲染 CPU 占用评估（中途暂停，仅有硬件渲染基线）

日期：2026-10-24。**测量中途暂停（用户决定腾出 CPU 重编 libmpv），已完成 10/20 格，且完成的全是硬件渲染格；软件渲染一格都没有完整数据。** 所以本笔记**不能回答"软件渲染 CPU 是否可接受"**，只留基线、方法和复跑办法。证据原件在 `D:\tmp\w19\ev\`（不入库）。

## 环境

- AMD Ryzen 9 7945HX（16 核 / 32 线程），RTX 4060 Laptop，Win11 Pro 10.0.26100，显示 2560x1600，系统缩放 150%（所以"小窗"1280x720 逻辑像素 = 1920x1080 物理像素窗口）。
- 测试工程 `D:\tmp\w19\app`（由内存排查的 w14 最小工程改来：media_kit + media_kit_video，slim 包覆盖到 `D:\tmp\win2\slim_pkg` 的 WHEP libmpv-2.dll，sha256 前缀 25d621eb；ANGLE 保持随包旧版 v1.0.1）。release 构建，`VideoControllerConfiguration(enableHardwareAcceleration: !SWRENDER)`，hwdec 保持默认（实测 d3d11va-copy）。仓库未改动，没有 pubspec_overrides.yaml。
- 推流：MediaMTX（D:\tmp\w14\mtx.yml，端口 38889/38554）+ ffmpeg testsrc2 30fps，libx264 baseline zerolatency，视频码率 360p 1M / 720p 3M / 1080p 6M，附 opus 音轨（无音轨时 MediaMTX 报 "codecs not supported by client"，起播失败）。点播：本地 1080p30 H.264（6Mbps）、HEVC（4Mbps）mp4，`loop-file=inf`。
- 每格 200s（前 20s 预热，稳态取 t>=25s，每 5s 一点，约 35 点）。CPU 为整个进程（含 mpv 线程）的 `TotalProcessorTime` 差分：单核口径 = 占一个核的百分比（可 >100），整机归一 = 除以 32。
- 帧间隔：Flutter `FrameTiming` 的 raster 完成时刻差。**局限**：纹理视频帧不产生 FrameTiming，为了有数据，界面底部放了一条 3px 的无限进度条强制连续出帧，所以该指标是"Flutter 合成帧节奏"（约 60~70 帧/s，均值 14~17ms），不是视频帧送显间隔；视频送显质量看 mpv 的掉帧计数与 estimated-vf-fps。进度条本身给所有格子加了同等的基线开销。

## 已完成的 10 格（均为硬件渲染，ANGLE v1.0.1）

CPU 单核% 为稳态均值（p95 在括号），整机% = 归一值；GPU 为整机 `nvidia-smi` 利用率（含系统其他负载，空闲基线约 20~25%）与解码器利用率；g3d/gvd 为该进程的 GPU Engine 3D / VideoDecode 利用率。内存斜率含 mpv 默认的后向缓冲增长（未关 demuxer 缓存），**不能直接当 ANGLE 泄漏斜率**。

| 窗口 | 源 | CPU 单核% (p95) | 整机% | GPU 总/解码% | 进程 3D/VDec % | WS / 私有 MiB | 内存斜率 MiB/min (WS) | 掉帧 fdrop/dec/delayed | estimated-vf-fps | Flutter 帧 p99 / >50ms 次数 | 出画 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 小窗 | WHEP 640x360 | 24.1 (28.7) | 0.75 | 27/3 | 5.6/3.3 | 207/331 | 23.1 | 0/0/0 | 30.0 | 18.5 / 4 | 是 |
| 小窗 | WHEP 1280x720 | 27.0 (30.8) | 0.85 | 28/5 | 8.6/5.8 | 246/405 | 35.7 | 0/0/0 | 30.0 | 18.4 / 9 | 是 |
| 小窗 | WHEP 1920x1080 | 39.9 (44.2) | 1.25 | 32/10 | 12.4/11.0 | 289/495 | 28.2 | 0/0/0 | 30.0 | 18.5 / 18 | 是 |
| 小窗 | mp4 H.264 1080p | 34.1 (42.3) | 1.06 | 32/12 | 13.0/12.2 | 279/491 | 13.1 | 0/0/0 | 30.0 | 18.5 / 2 | 是 |
| 小窗 | mp4 HEVC 1080p | 36.4 (42.6) | 1.14 | 32/6 | 14.2/5.7 | 266/494 | 17.3 | 0/0/0 | 30.0 | 18.4 / 7 | 是 |
| 全屏 2560x1600 | WHEP 640x360 | 23.9 (30.3) | 0.75 | 30/3 | 10.7/3.3 | 207/426 | 23.3 | 0/0/0 | 30.0 | 18.7 / 2 | 是 |
| 全屏 | WHEP 1280x720 | 22.8 (26.8) | 0.71 | 29/11 | 7.2/3.9 | 236/495 | 35.8 | 0/0/0 | 30.0 | 18.5 / 18 | 是 |
| 全屏 | WHEP 1920x1080 | 30.2 (34.7) | 0.95 | 33/17 | 9.6/7.8 | 270/583 | 26.7 | 0/0/0 | 30.0 | 18.4 / 13 | 是 |
| 全屏 | mp4 H.264 1080p | 22.5 (26.2) | 0.70 | 27/14 | 8.5/8.2 | 266/581 | 13.0 | 0/0/0 | 30.0 | 45.4 / 5 | 是 |
| 全屏 | mp4 HEVC 1080p | 24.6 (29.3) | 0.77 | 30/10 | 8.8/3.1 | 255/584 | 15.3 | 0/0/0 | 30.0 | 45.4 / 3 | 是 |

"出画"依据：窗口截图（`ev\*.png`）亮度标准差 >40（非均匀，视频区域非透明/非黑；小窗 360p 那张已肉眼看过，testsrc2 色条正确，其余只做了像素统计）。

## 数据能支持的结论（仅硬件渲染）

1. 这台机上硬件渲染 + d3d11va-copy 解码，1080p30 单路的进程 CPU 只有约 0.7~1.3% 整机（单核口径 22~40%）；全部 10 格 0 掉帧，estimated-vf-fps 稳定 30。这是后续软件渲染的对照基线。
2. 小窗比全屏 CPU 略高（同源约 +5~10 个单核百分点）的原因没有查，不下结论。WHEP 比同分辨率本地 mp4 略高（实况路径多一层 WebRTC 收包/重组）。
3. 内存斜率偏高（WHEP 23~36、mp4 13~17 MiB/min）是 ANGLE 泄漏（约 9.6）叠加默认后向缓冲（实况约 6~7）的总和，且 35 个点的斜率不精确，**本表不拿来作泄漏结论**；专门的稳定性对比（关后向缓冲）没来得及跑。
4. 全屏 mp4 的 Flutter 帧 p99 为 45ms 而其他格 18ms，意味着该两格合成帧偶有拉长，原因未查（可能是循环文件回绕或系统干扰），单次观测不下结论。

## 未完成项（需复跑）

- 软件渲染 10 格全部未做（队列第 11 格 `sw_small_whep360` 跑到一半被停，残留数据在 `D:\tmp\w19\partial\`，不可用）。
- 稳定性对比（软件渲染 ≥15 分钟 WHEP 720p 斜率 <1 MiB/min、硬件渲染对照约 9.6）未跑，队列文件已写好：`D:\tmp\w19\queue_stab.csv`（关后向缓冲 `demuxer-max-back-bytes=0;demuxer-seekable-cache=no`，每格 1000s）。
- 降分辨率 / `vd-lavc-threads` / `hwdec` 缓解组合的评估、切换条件建议：依赖软件渲染数据，未做。
- mova 层是否暴露软件渲染开关（只读排查）：`MovaMpvKernel` 构造函数有 `videoControllerFactory`（`VideoController Function(Player)`，默认 `VideoController.new`，见 `mova/lib/src/core/kernel/mpv_kernel.dart`），注入工厂即可构造 `VideoControllerConfiguration(enableHardwareAcceleration:false)`，但需确认 `createMovaEngine` / `wiring.dart` 是否把该参数透传出来；没有逐处核对，也没有改代码。最小接入建议：在 `createMovaEngine` 增加一个渲染模式参数并转给该工厂。

## 复跑方法

1. 起 MediaMTX：`D:\tmp\mtx\mediamtx.exe D:\tmp\w14\mtx.yml`（工作目录 `D:\tmp\w14`），记下 PID。
2. 队列文件 `D:\tmp\w19\queue_main.csv`（20 格，硬件格已有 `ev\<tag>.done`，驱动会跳过已完成的）；驱动 `D:\tmp\w19\driver.ps1`，由 `Start-Process explorer.exe D:\tmp\w19\run_main.cmd` 代启动（`run_stab.cmd` 对应稳定性队列）。驱动负责拉起/停止 ffmpeg 与测试 app 并记录 PID（`apppids.txt`、`ffpids.txt`）。
3. 汇总：`python D:\tmp\w19\summ.py`。注意 ffmpeg 要用 WinGet Packages 下的真实路径（`Links` 下是符号链接，在本会话进程树里会被 RedirectionGuard 拦）。
4. 复跑期间尽量不做别的重负载，否则 CPU 数据被污染（本次暂停就是这个原因）。
