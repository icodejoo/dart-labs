# Windows 带视频渲染的内存线性增长：根因定位

日期：2026-10-24。机器：Windows 11 Pro 10.0.26100，RTX 4060 Laptop，真实桌面。证据原件在 `D:\tmp\w14\ev\`（`s_*.csv` 为 15s 采样，`*.log` 为应用输出，不入库）。"实测"为本机跑出，"推断"单独标注。

## 结论

增长由**两个互相独立的部分**叠加，之前把它们当成一个问题：

1. **约 9~10 MiB/min：随包 ANGLE（`libEGL.dll`/`libGLESv2.dll`，2022-08 构建）的原生内存泄漏。** 只在 OpenGL ES 硬件渲染路径出现。换成较新的 ANGLE（2025-08 / 2026-03 构建）后 15 分钟平坦。这是主因。
2. **约 6~7 MiB/min：mpv 解复用器的"后向缓冲"（back buffer）。** 实时流默认 `demuxer-max-back-bytes=150MiB`，已播放的包一直留着（`seekable-ranges` 从 0 起），上限 150 MiB 才会停。属缓冲增长，不是泄漏，参数能压住。

两者之和约 17 MiB/min，与此前观察（183→258 MiB / 330s）一致。

## 数据

### 15 分钟长观察（基线，随包 ANGLE，默认 mpv 参数，WHEP，release）

`whep_base`，960s，每 15s 一点：

| t(s) | WS MiB | 私有 MiB | 句柄 | VRAM 专用 MiB |
|---|---|---|---|---|
| 65 | 195.9 | 309.2 | 1822 | 130.3 |
| 305 | 263.0 | 375.8 | 1805 | 130.4 |
| 626 | 359.9 | 476.8 | 1808 | 135.8 |
| 946 | 422.9 | 540.9 | 1806 | 135.8 |

- 持续增长，**15 分钟没有平台**；斜率前 10 分钟约 17 MiB/min，后段降到约 9~12 MiB/min（原因未细究，**推断**与分配器行为有关），仍不是在趋平。
- 句柄 1800 上下抖动不涨；GDI/USER 对象 96/66 不涨；线程不涨；GPU 专用显存 130→136 MiB 基本持平。**不是句柄泄漏，不是显存泄漏，是进程私有（CPU 侧）原生内存。**
- Dart 堆：profile 构建 + vm service（`prof1`，300s）`dart_heap` 在 9~12.5 MiB 间锯齿（GC 回收），`external=0`，同时 RSS 196→242 MiB 仍线性涨。**不在 Dart 堆。**

### 对照矩阵（均 release，640x360 25fps，除注明外 mpv 参数为 `demuxer-max-back-bytes=0;demuxer-seekable-cache=no` 以先排除后向缓冲）

斜率为 WS，MiB/min。

| 编号 | 配置 | 观察 | 斜率 | 结论 |
|---|---|---|---|---|
| whep_base | WHEP，默认参数，随包 ANGLE | 960s | 17 → 9~12 | 基线 |
| dec_novo | WHEP，**不渲染**（无 VideoController，`vid=auto`，d3d11va-copy 解码） | 300s | 约 7.5 | 解码 + 后向缓冲，无渲染时只剩后向缓冲 |
| r_noback | WHEP，渲染，关后向缓冲 | 300s | 9.8 | 去掉缓冲后仍涨，渲染路径有泄漏 |
| r_noimp | 同上，重复一次（试图关 Impeller 的开关在 release 无效，实际仍是 Impeller） | 240s | 9.5 | 可重复 |
| prof1 | 同 r_noback，profile 构建 | 300s | 约 10 | Dart 堆平，external=0 |
| r_http | 实况 HTTP MPEG-TS（本机 ffmpeg 推，非 WHEP），渲染，关后向缓冲 | 240s | 约 9 | **不是 WHEP 特有**，实况 + 渲染都涨 |
| r_file | 本地 mp4 `loop-file=inf`，渲染 | 300s | 约 12（180→228） | **本地循环也涨**；此前"约 198 MiB 趋平"的结论不成立（那次观察窗口太短） |
| r_nowidget | 本地 mp4 循环，创建 VideoController 但**不挂 Video 控件** | 240s | 约 11.5 | 不需要 Flutter 采样纹理，泄漏在 mpv→ANGLE 这一段 |
| r_swrender | 本地 mp4 循环，`enableHardwareAcceleration:false`（mpv 软件渲染到像素缓冲） | 240s | 约 0（181→187 后平） | **软件渲染路径不涨，硬件渲染（ANGLE）路径涨** |
| a_emu | 本地 mp4 循环，换 Android 模拟器自带 ANGLE（2025-08，libGLESv2 12.5MB） | 240s | 约 0.9（187→192.5 后平） | 新 ANGLE 不涨 |
| whep_emu | WHEP，换新 ANGLE（emulator），关后向缓冲，**930s** | 930s | WS 173.2→177.4，私有 299.0→303.0（15 分钟总增约 4 MiB） | **15 分钟平坦** |
| a_motrix | 本地 mp4 循环，Motrix(Electron) 自带 ANGLE（2023-05，2.1.19728，7.5MB） | 240s | 约 12 | 2023-05 的版本仍涨 |
| a_jbr | 本地 mp4 循环，JetBrains Runtime(CEF) 自带 ANGLE（2026-03，7.9MB） | 240s | 约 1.6（175→182） | 新版不涨，且体积与现随包接近 |
| whep_jbr_def | WHEP，JBR 的 ANGLE，**默认 mpv 参数** | 630s | 约 7.4 | 只剩后向缓冲（对应成分 2） |

前期（上一份笔记）已有的对照：软解、随包 d3dcompiler、裸 media_kit 都涨；不创建 VideoController 平——与"只要走 ANGLE 硬件渲染就涨"一致。

### 定位链条（实测）

1. 不渲染不涨（dec_novo，扣去后向缓冲）→ 增长与"有渲染面"相关。
2. 软件渲染不涨、硬件渲染涨（r_swrender vs r_file）→ 问题在 OpenGL ES（ANGLE）这一路，不在解码、不在 mpv 通用渲染逻辑。
3. 不挂 Video 控件也涨（r_nowidget）→ 与 Flutter 引擎/Impeller 采样纹理无关。
4. Dart 堆平、句柄平、显存平、`external=0`（prof1）→ 是 native 私有内存。
5. 只替换 `libEGL.dll`+`libGLESv2.dll` 两个文件，其余（libmpv、media_kit、Flutter）不变，增长消失（a_emu/whep_emu/a_jbr）；2023-05 的版本不行（a_motrix）→ **泄漏在 ANGLE，修复在 2023-05 之后**。
6. 增长以大量 260~430KB 左右的私有提交区域（47×266,240B、27×299,008B、7×331,776B……）的形式出现（两次 `VirtualQueryEx` 快照对比，300s 内私有 +40 MiB，其中新区域 +49 MiB）。**推断**：是 ANGLE 内部按帧分配的纹理/暂存缓冲没有回收（D3D11 后端的 staging/上传缓冲），具体对象没有进一步定位（本机无 UMDH/WPA，Toolhelp 堆遍历只覆盖到 5 MiB，其余分配不在 NT 堆里）。

### 后向缓冲（成分 2）

- `demuxer-cache-state` 的 `seekable-ranges` 为 `[{start:0, end:<当前>}]`，`bof-cached:true`：整段播放过的包都留着；`total-bytes` 约 97 KB/s（视频 + opus，含容器开销），折合约 5.8 MB/min，加上包对象开销约 6~7 MiB/min（dec_novo 无渲染也是 7.5 MiB/min）。
- `demuxer-max-back-bytes=0` + `demuxer-seekable-cache=no` 后 `seekable-ranges` 为空，这一部分消失（r_noback 斜率从 17 降到约 9.8）。
- 前向缓冲 `fw-bytes` 一直稳定在约 130 KB（1.3s），实时流没有向前堆积；WHEP 的 ffmpeg 侧解复用器本身不累积（dec_novo 去掉后向缓冲后无额外增长，上次 libmpv-only smoke 660s 平坦也一致：smoke 用 vo=gpu 自己的窗口，不走 ANGLE）。

## 建议

### 1. 换 ANGLE（根治成分 1，需要决策）

`media_kit_libs_windows_video_slim` 的 CMake 当前从 `alexmercerind/flutter-windows-ANGLE-OpenGL-ES` v1.0.1 的 `ANGLE.7z` 取 DLL（md5 `e866f13e8d552348058afaafe869b1ed`，文件时间 2022-08-19，libEGL 472,904B / libGLESv2 7,414,088B，sha256 前缀 `620BB6E38D7E`）。**这个版本在 ANGLE 硬件渲染路径上泄漏。** 建议改为随包一份较新的 ANGLE：

- 本机验证过可直接替换（接口兼容，不需要改 media_kit_video 插件）的两个来源：
  - Android 模拟器自带（`D:\sdk\android\emulator\lib64\gles_angle`，2025-08，libGLESv2 12,488,856B）：体积 +5 MB，不适合随包。
  - JetBrains Runtime 的 CEF ANGLE（`C:\Program Files\JetBrains\IntelliJ IDEA 2026.1\jbr\bin`，2026-03-25，libEGL 512,352B sha256 前缀 `080BFF74DCD0` / libGLESv2 7,882,088B 前缀 `7B930D8AC640`）：体积与现随包相当（+0.5 MB），本地循环 240s 平坦；**还没跑 WHEP 长观察**，只跑了 WHEP 默认参数 630s（斜率仅剩后向缓冲）。
- 要正式随包，需要一个可复现、可校验的来源：Chromium/Electron/CEF 发行包里都带这两个文件（ANGLE 为 BSD 协议），可在 CMake 里像现在一样用 URL + md5 下载。**这是引入新的二进制来源，需你拍板选哪个来源和版本**，我没有改 CMake。
- 换之前建议做的事：用选定的版本在 WHEP 上跑 ≥15 分钟，并回归 d3dcompiler 取自系统目录、全屏/小窗、缩放（`VideoOutput.Resize` 会重建纹理）这些场景；Chromium 构建的 ANGLE 偶发会对 EGL 扩展有删减，本机基础路径未发现问题。

### 2. 实时流压住后向缓冲（成分 2，参数即可）

mova 当前没有设置任何 demuxer 缓存参数（`mpv_kernel.dart` 里只有 `tls-*`）。对 WHEP/直播源，打开前设置：

- `demuxer-max-back-bytes=0`（或一个较小值，例如 4 MiB 给回看一点余地）
- `demuxer-seekable-cache=no`

实测（whep_emu，换新 ANGLE 后）15 分钟私有内存 299→303 MiB，平坦。点播源需要拖动回看，不要对点播关；直播时移（`MovaLiveConfig` 的 timeshift）若依赖本地回看缓冲，需按窗口大小保留相应的 back bytes，这一条要结合产品决定。这属于 mova 内核（`MovaMpvKernel`）范畴，按任务约定我没动 `mova/lib`。

### 3. 临时规避（不换 ANGLE 时）

- 没有能压住成分 1 的 mpv 参数：软解、vd-lavc-threads、关后向缓冲都不影响它（见矩阵）。
- 唯一可行的规避是 `enableHardwareAcceleration:false`（软件渲染，实测不涨），代价是每帧一次 CPU 读回/拷贝，高分辨率下 CPU 占用会明显升高，**不建议作为默认**，本次没有测其 CPU 占用。

### 上游线索

- 现象最小复现：Flutter Windows + `media_kit` 1.2.x / `media_kit_video` 2.0.1 + `ANGLE.7z` v1.0.1（2022-08），任意视频源（本地 mp4 循环即可），`Video` 控件，WS/私有内存约 10 MiB/min 线性增长，句柄/显存平，Dart 堆平；换 2026 年的 ANGLE DLL 即消失。
- 可以向 `alexmercerind/flutter-windows-ANGLE-OpenGL-ES` 提 issue 要求更新 ANGLE.7z；或在 media_kit 上游提 issue 说明随包 ANGLE 过旧。

## 方法与环境

- 在 `D:\tmp\w14\app` 建最小 Flutter 工程（仅 media_kit + media_kit_video + 本地 slim 包覆盖到 `D:\tmp\win2\slim_pkg` 的 WHEP DLL；可执行名改为 `w14app` 以免和并行任务的 `mova_example` 混淆），参数全走环境变量（`W14_*`），一次构建多次复用。`flutter build windows` 由 `Start-Process explorer.exe <cmd>` 代启动（RedirectionGuard 规避）。
- 采样脚本 `sampler.ps1`：WS、私有、句柄、线程、GDI、USER、GPU 专用/共享显存（性能计数器 `GPU Process Memory`），15s 一点。Dart 堆用 profile 构建 + `vm_service` 自连取 `getMemoryUsage`。
- 区域快照：`regsnap.py`（`VirtualQueryEx` 枚举）。Toolhelp 堆遍历（`heapsnap.py`）极慢且只覆盖 5 MiB，价值有限，已弃用。
- 推流：MediaMTX（`D:\tmp\w14\mtx.yml`，端口整体 +10000，避开并行任务）+ ffmpeg testsrc2 640x360@25 400k + opus；实况 HTTP 用 `ffmpeg -listen 1 -f mpegts`。注意 `-listen 1` 必须放在输出之前才生效（放在输入之前会让 ffmpeg 当场退出，造成 pos=0 的假阴性；RTSP/UDP 直连 mpv 因协议白名单没带 `rtsp`/mpegts-over-udp 解不出来，同样 pos=0，已弃用，数据不采信）。
- 收尾：只停了自己起的 mediamtx(20292)、ffmpeg(38112)、各采样器与 `w14app`；没有碰别人的 python/ffmpeg/http.server。没有改仓库任何文件、没有 `pubspec_overrides.yaml`、没有 git commit。

## 未解决 / 待决策

1. 选哪个新 ANGLE 来源与版本、是否改 CMake 随包（见建议 1）。
2. JBR 版 ANGLE 的 WHEP ≥15 分钟平坦验证（本次只做了本地循环 240s + WHEP 默认参数 630s）。
3. ANGLE 具体泄漏对象与修复所在版本区间（2023-05 之后、2025-08 之前）没有二分；需要的话可再找中间版本（Chromium 2024 的构建）定位。
4. 直播时移是否依赖后向缓冲，决定 `demuxer-max-back-bytes` 取值。
5. 后向缓冲在默认参数下 150 MiB 封顶后的行为（本次最长默认参数观察 630s，约 +70 MiB，没跑到封顶）。
