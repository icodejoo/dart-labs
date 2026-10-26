# mpv 补丁 0007：ANGLE 上不启用 GL_EXT_disjoint_timer_query（修 Windows 渲染私有内存线性增长）

日期：2026-10-25。机器：Windows 11 Pro，RTX 4060 Laptop，真实桌面。前因见 `2026-10-25-angle-leak-heap-trace-and-plugin-v1.md`（定位到 `glBeginQueryEXT` -> ANGLE `CreateQuery` -> NVIDIA 驱动堆增长）。证据原件在 `D:\tmp\ev14\`（不入库）。

## 结论

1. 新增 `patches/mpv-v041/0007-opengl-common-no-timer-query-on-angle.patch`，真补丁重编的 DLL 实测：旧 ANGLE v1.0.1 + 硬件渲染 + WHEP 720p30，948s 私有内存 337.7 -> 343.0 MiB，斜率 **0.26 MiB/min**（此前 10.07；改字符串的 A/B 是 0.52），达到 <1 MiB/min 目标。
2. 画面正常：WHEP 与 HTTP mp4 都出画（见下）。

## 补丁

`video/out/opengl/common.c` 的 `mpgl_load_functions2`：读 `GL_RENDERER`，含 `ANGLE` 时，在函数段循环里跳过 `GL_EXT_disjoint_timer_query` 那一段。该段不加载，`gl->GenQueries` 为空，`ra_gl.c: gl_timer_create` 返回 NULL，mpv 不建 GPU 计时器（`timer_pool_create` 对 NULL 已有处理）。非 ANGLE 的 GL 后端、其他平台（含 Android 自带 GLES）不受影响。8 行，对 v0.41.0 `git apply --check` 通过。

连带改动：`patches/mpv-v041/README.md`（总表与顺序说明）、`patches/android-v041/apply-v041.sh`、`local-build-arm64.sh`（显式列表加 0007，Android 上因不是 ANGLE 不生效，只为与 0006 同样处理）、`tools/whep-flavor/build-windows.sh`（头部注释；补丁通配自动打）。

## 构建

方法同 0006：MSYS2（`D:\msys64`，MINGW64）、LF 副本 `D:\tmp\lf\mova-libmpv`、`GIT_CONFIG_GLOBAL=/dev/null`，`WORK=D:\whep-win\libmpv14`（源码缓存拷自 libmpv13）。日志确认 ffmpeg 0001-0012 + mpv 0001/0003/0004/0005/0006/0007 按序全部打上。产物 `D:\whep-win\libmpv14\whep\out\libmpv-2.dll`，10,875,904 字节，副本 `D:\tmp\mpv0007\libmpv-2.dll`。未覆盖仓库内任何 DLL，DLL 不入库。

## 斜率（实测）

条件：旧 ANGLE v1.0.1（libGLESv2 7,414,088 B）+ 原版 media_kit_video 插件，硬件渲染，WHEP `whep+http://127.0.0.1:38889/test/whep`（MediaMTX + ffmpeg testsrc2 1280x720@30 1.5Mbps + opus），`demuxer-max-back-bytes=0;demuxer-seekable-cache=no`，15s 采样，t>=60s 最小二乘（`D:\tmp\heap\slope.py`）。

| 组合 | 时长 | 私有 MiB（起 -> 末） | 斜率 MiB/min |
|---|---|---|---|
| 无补丁（ctl1） | 660s | 349.5 -> 445.5 | 10.07 |
| 改字符串 A/B（nq1） | 660s | 335.5 -> 341.6 | 0.52 |
| **真补丁 0007（t0007）** | 948s（n=56） | 337.7 -> 343.0 | **0.26** |

句柄 1728 -> 1721、线程 331 -> 327，稳定。

## 出画

`PrintWindow`（client 1898x1024），判据为 testsrc2 五色条像素数：

- WHEP（起播约 25s）：红/绿/黄/蓝/青 = 17498/17946/17884/17706/17715，出画。品红 0%，因为 16:9 视频基本铺满窗口，上下只有约 4% 黑边（原版插件下 fill 颜色未体现为品红，出画以色条为准）。
- HTTP mp4（本地 `http.server` 提供 clip.mp4，loop，起播 15s）：色条 16268/16164/17533/17380/17412，出画，品红 11.7% 为信箱区底色。

## 局限

- 关掉计时器后，`vo-passes`/stats 没有逐 pass 耗时（GPU 计时拿不到）。
- 只在一台 RTX 4060 笔记本、一个 NVIDIA 驱动版本上测；AMD/Intel 驱动下泄漏是否存在、补丁是否有副作用未测。
- Android 未测：补丁按 `GL_RENDERER` 含 `ANGLE` 判断，Android 走驱动自带 GLES 不会命中，理论上无影响（推断）。
- 判断依赖 `GL_RENDERER` 字符串含 `ANGLE`；本机旧 ANGLE 命中（斜率下降为证），换成其他 ANGLE 构建时字符串格式未逐一核对。
- 只跑了新 ANGLE 之外的旧 ANGLE v1.0.1 组合；v8078 + 0007 未重测（此前改字符串版是约 1.4 MiB/min）。
- 补丁插件 + 旧 ANGLE 的长跑、5 轮起播停止、缩放/最大化回归没有对 0007 重跑。
- 最大化时私有内存跳到约 1 GiB 的问题与本补丁无关，仍未处理。

## 回归

日期：2026-10-25。组合：0007 的 libmpv-2.dll（10,875,904 B，MD5 b0828c63...，仓库内 DLL 未动）+ 旧 ANGLE v1.0.1（libEGL 472,904 / libGLESv2 7,414,088）+ **原版** media_kit_video 2.0.1 插件（无补丁副本），硬件渲染。测试 app：`D:\tmp\sw_app`（拷自 `D:\tmp\w14\app`，加了按环境变量 `SW_SEQ` 脚本化起播/停止/换源的 `main.dart`），产物目录 `D:\tmp\var_sw`。脚本 `D:\tmp\ev14\sw.ps1`（起播/换源驱动 + 句柄/线程采样 + `PrintWindow`）、`D:\tmp\ev14\rs2.ps1`（缩放/最大化）。截图与日志在 `D:\tmp\ev14\sw_*`（不入库）。WHEP 源：MediaMTX + ffmpeg testsrc2 1280x720@30，`demuxer-max-back-bytes=0;demuxer-seekable-cache=no`。出画判据：五色条（红/绿/黄/蓝/青）像素数均明显大于 0（`PrintWindow`，全窗口）。

### 1. 起播/停止 5 轮：通过

- 同进程内 open/stop 5 轮（每轮起播 22s，停 4s）：每轮出画（色条各 1.7 万～1.8 万，client 1898x1024），无崩溃、无黑屏（黑色占比 0.6%）。起播后句柄/线程 1728/332、1735/333、1734/330、1734/330、1734/330；停止后 1540/292、1538/291、1534/287、1534/287、1536/287。句柄与线程不涨（停止后线程 292 -> 287 略降）。停止后私有内存 319 -> 325 -> 324 MiB（5 轮 +5 MiB，未做更长观察）。
- 另外 5 次独立进程冷启动（起播 18s 后截图）：5 次都出画，进程正常退出。起播后句柄 1731/1840/1731/1728/1743（第 2 次 1840 是瞬时偏高，其他稳定），线程 332～337。

### 2. 缩放 20 次 + 最大化/还原 5 次：通过

- 20 次变尺寸（800x600/1200x700/640x400/1000x800 轮换）和 5 次最大化/还原，每步之后都出画（每步均五色条齐全，无一次 FAIL）。
- 最大化（client 2560x1521）私有内存：采样峰值约 1022～1118 MiB，最大化后 3s 读数 1141～1177 MiB；还原后 3s 读数 559～604 MiB，之后在缩放过程中回落到 340～345 MiB（起始 337 MiB）。还原窗口内的瞬时峰值最高 1326 MiB。
- 句柄 1731 -> 1733～1744，线程 333 -> 328，缩放 20 次与 5 次最大化还原后稳定、不涨。
- 最大化时私有内存跳到约 1 GiB 的现象与 0007 无关（旧 ANGLE、无补丁时同样），仍未处理，仅还原后会回落。

### 3. 本地 mp4 / HTTP mp4 / 换源：通过

同一进程内连续换源（每步 22s，起播 18s 后截图），7 步全部出画：

| 步骤 | 源 | 色条（红/绿/黄/蓝/青） | 私有 MiB |
|---|---|---|---|
| 1 | 本地 mp4 | 16476/17060/17265/17212/17402 | 295 |
| 2 | HTTP mp4 | 16142/16750/17474/17370/17412 | 300 |
| 3 | WHEP | 17530/18004/18005/17696/17700 | 352 |
| 4 | HTTP mp4 | 16156/16316/17476/17293/17395 | 312 |
| 5 | WHEP | 17607/17896/18049/17688/17663 | 359 |
| 6 | 本地 mp4 | 16142/16750/17474/17370/17412 | 321 |
| 7 | WHEP | 17519/18063/17882/17680/17623 | 363 |

覆盖 WHEP -> mp4 -> WHEP 两次。无崩溃、无黑屏；句柄 1666～1735、线程 329～331，稳定。换源后私有内存阶梯上升（WHEP 段 352 -> 359 -> 363 MiB），是 7 步共 150s 的短观察，未判断是否为泄漏，斜率结论仍以前面 948s 的 0.26 MiB/min 为准。

### 4. 真全屏：通过（Win32 无边框全屏，非 app 内全屏）

对窗口去掉标题栏样式并 `SetWindowPos` 到 2560x1600 置顶：出画（client 2560x1600，色条 31692/19706/32510/36204/36658，黑色 0%）。私有内存峰值 1147 MiB、全屏稳定后 707 MiB，句柄 1736。退出全屏后出画（978x644），私有内存 555 MiB。没有测 Flutter app 内的全屏（media_kit 的 `enterFullscreen`），因为测试 app 没有该 UI。

### 局限

- 一台机器（RTX 4060 Laptop、单个驱动版本）、单显示器，没有多屏测试。
- 5 轮起播/停止只测了 WHEP；mp4 起播/停止循环没单独做（换源已覆盖 mp4 的 open）。
- 起播/停止后的内存与换源后的内存观察时间短，只能说明没有明显增长，不能代替长跑。
- 测试 app 的 `Video` 控件设了品红 `fill`，原版插件下品红底色是否生效取决于信箱区，色条判据不受影响。
- 本节的"局限"里此前写的"5 轮/缩放/最大化没对 0007 重跑"，以本节为准已补跑。

## CI 产物验证

日期：2026-10-25。被测：仓库内 CI 注入的 `mova/libmpv/windows-x86_64-whep/libmpv-2.dll`（HEAD 7828bc83，10,876,416 B，MD5 53a88f41...）。只读使用：把它拷进 `D:\tmp\var_ci`（`var_sw` 的副本，DLL 替换为 CI 版），仓库文件未改。其余条件同前：旧 ANGLE v1.0.1 + 原版 media_kit_video 2.0.1 + 硬件渲染；MediaMTX + ffmpeg testsrc2 1280x720@30 1.5Mbps + opus；`demuxer-max-back-bytes=0;demuxer-seekable-cache=no`；15s 采样，t>=60s 最小二乘（`D:\tmp\heap\slope.py`）。脚本与原始数据在 `D:\tmp\ci\`（不入库）。

### 1. sha256 与 LFS 指针

`git cat-file -p HEAD:mova/libmpv/windows-x86_64-whep/libmpv-2.dll` 的 oid 为 `313f45d8f017f659b74866bfe990d5fe34b43e623c2445fc230b7a0413e3c38e`，size 10876416；工作区文件 sha256 完全一致，大小一致。

### 2. WHEP 长跑斜率

| 组合 | 时长 | 私有 MiB（t=60s -> 末） | 斜率 MiB/min |
|---|---|---|---|
| 无补丁 | 660s | 349.5 -> 445.5 | 10.07 |
| 本地重编 0007 | 948s（n=56） | 337.7 -> 343.0 | 0.26 |
| **CI 产物** | 991s（n=63） | 336.9 -> 344.2 | **0.42** |

CI 版达到 <1 MiB/min 目标。线程 328 -> 330（稳定），句柄 1725 -> 1817：句柄在 t=796s 到 811s 之间一次性 +110（1721 -> 1831）后保持平台，之前约 800s 内在 1714~1727 间波动，不是线性增长；本地重编版同类长跑是 1728 -> 1721，没有这一跳。跳变原因未查（只有一次，未重现）。0.42 与 0.26 的差别在单次运行的波动范围内，没做重复运行，不下结论。

### 3. 出画与精简回归

- 长跑起播约 45s：`PrintWindow`（client 1898x1024）色条 红/绿/黄/蓝/青 = 17552/15539/17967/17532/17699，出画。
- 起播/停止 5 轮（每轮起播 22s、停 4s）：每轮出画（第 2 轮绿 10026 偏低但远大于 0，其余 1.5 万～1.8 万），黑色 0.6%，无崩溃。起播后句柄/线程 1728/332、1735/333、1732/330、1732/330、1734/330；停止后 1540/292、1538/291、1535/288、1532/287、1534/287。停止后私有内存 320 -> 320 -> 322 -> 321 -> 324 MiB。
- 缩放 20 次（800x600/1200x700/640x400/1000x800 轮换）+ 最大化/还原 5 次：每步都出画，`FAILS=0`，无崩溃。最大化私有内存 990～1163 MiB，还原后 3s 读数 352～601 MiB，缩放过程中回落到 357～389 MiB；句柄 1731 -> 1736、线程 333 -> 329。最大化时约 1 GiB 的现象与 0007 无关，同上文，仍未处理。

### 4. 与本地重编版对比、strings 核对

斜率 0.42 对 0.26，均 <1 MiB/min，不触发"明显更高"的条件。仍做了核对：两份 DLL 的 `strings -a` 里 `GL_EXT_disjoint_timer_query` 各 1 处、含 `ANGLE` 的字符串各 21 处，数量一致。两份 DLL 字节不同（MD5 b0828c63... 对 53a88f41...，大小差 512 B），是不同时间、不同环境构建的产物，差异未逐项分析。

### 5. 未验证项

- 只做了一次 991s 长跑，没有重复运行，0.42 与 0.26 的差距是否为噪声未确认。
- 句柄 t≈800s 处 +110 的一次性跳变未复现、未定位。
- `strings` 只能证明字符串在，不能证明补丁逻辑生效；生效的依据是斜率（0.42 对无补丁 10.07）。
- 未做 mp4/换源/真全屏回归，也未测其他 ANGLE 构建、其他显卡驱动，范围同前文"局限"。

## 其他 GPU 与句柄复测

日期：2026-10-25。被测同上：仓库内 CI 注入的 `libmpv-2.dll`（sha256 前缀 313f45d8，只读使用，未改仓库文件），旧 ANGLE v1.0.1 + 原版 media_kit_video 2.0.1。脚本与数据在 `D:\tmp\ci2\`（`hsnap.ps1` 为 NtQuerySystemInformation 句柄类型采样器；`b.csv`、`bdump_*.txt`、`a.log`），不入库。

### A. 其他 GPU 路径：本机没有可用的第二块 GPU

- `Get-CimInstance Win32_VideoController` 只有 NVIDIA GeForce RTX 4060 Laptop GPU。
- `Get-PnpDevice -Class Display` 另有一条 **AMD Radeon(TM) 610M**（`PCI\VEN_1002&DEV_164E`），但 `IsPresent=False`、`CM_PROB_PHANTOM`，是历史残留的幽灵设备（集显在 BIOS/MUX 里关着或当前不枚举），不可用。
- dxdiag 只列一个显示设备（RTX 4060），`Hybrid Graphics GPU: Discrete`，`Microsoft Graphics Hybrid: Not Supported`。
- DXGI 适配器（`HKLM\SOFTWARE\Microsoft\DirectX`）：NVIDIA（LUID 0x10B22）与 Microsoft Basic Render Driver（LUID 0x173D6，即 WARP）；GPU Adapter Memory 性能计数器同样只有这两个 LUID。
- 结论：没有 Intel/AMD 集显可测。每应用 GPU 偏好（UserGpuPreferences）无处可指，**没有改注册表**；该键下现有项只有 Lenovo 两个 env_detect.exe 的 `GpuPreference=2` 和 `VRROptimizeEnable=0`，均为系统自带，未动。

WARP 对照尝试：

- 做法：复制 media_kit_video 2.0.1 到 `D:\tmp\mkv_warp`，把 `angle_surface_manager.cc` 里 D3D11 设备的 `D3D_DRIVER_TYPE_HARDWARE` 改成 `D3D_DRIVER_TYPE_WARP`，用 fvm flutter 3.47.1 重编测试 app（`D:\tmp\warp_app`），产物 `D:\tmp\var_warp`，换入 CI 版 libmpv-2.dll 与旧 ANGLE（sha256 与 `var_ci` 一致）。
- 结果：起播日志为 `ANGLESurfaceManager: Failure: eglCreatePbufferFromClientBuffer` 后 `VideoOutput: Using S/W rendering.`。WARP 设备的共享纹理无法被 ANGLE 建成 pbuffer，media_kit 自动退回**软件渲染**，没有进入硬件渲染路径，所以没有走 mpv 的 GPU 计时器代码，这一轮对 0007 没有验证价值。GPU 引擎计数器佐证：进程的 3D 引擎占用全在 NVIDIA LUID（Flutter 自己的 ANGLE 仍在 4060 上），WARP LUID 为 0。
- 已因此中止该进程（按 PID 杀），没有跑满 15 分钟，没有斜率数据。软件渲染路径的 CPU 评估见 2026-10-24-software-render-cpu-eval 笔记，与 0007 无关。
- 要让整条链真走 WARP，需要 Flutter 引擎自己的 ANGLE 也跑在 WARP 上并改共享方式，改动超出本次范围，未做。且 WARP 本来就不等于 AMD/Intel 驱动。

### B. 句柄跳变复测：未复现

- 条件同"CI 产物验证"：独立进程，WHEP 720p30 1.5 Mbps，`demuxer-max-back-bytes=0;demuxer-seekable-cache=no`，起播后 15s 采样（`b.csv`，n=63 个 t>=60s 样本），共 993s，MediaMTX 与 ffmpeg 为本次自起（按 PID 管理，结束后已停）。
- 私有内存 339.3 -> 344.7 MiB，斜率 **0.33 MiB/min**（上次 0.42，本地重编 0.26，无补丁 10.07），三次都在 0.26~0.42，可视为同一量级的波动。
- 句柄：t=15s 1839，之后缓慢回落到 1801~1832，末 1808；线程 337 -> 328。**t≈800s 前后（783/798/813s）为 1805/1805/1808，没有 +110 跳变**，全程没有任何一次 >+15 的上升。
- 类型分布（每 15s 一次）：Event 987 -> 967，Thread 335 左右，WaitCompletionPacket 122 -> 117，Section 73~74，Key 53，File 26，IRTimer 11~12，其余恒定；约 216 个句柄类型无法解析（DuplicateHandle 失败，数量恒定，不随时间变化）。没有哪一类随时间增长。
- 因没有复现，无需句柄定位；每个采样点的句柄值+类型清单已存 `D:\tmp\ci2\bdump_*.txt` 备查。上次那次 +110 仍原因不明，只能说 2 次 CI DLL 长跑里 1 次出现、1 次未出现，是低概率偶发或与外部因素（如系统/驱动）有关，未证实也未排除。

### 未验证项

- 没有 Intel/AMD 集显可测；WARP 路径因 media_kit 退回软件渲染，未验证 0007 在其他驱动上的行为。
- 句柄跳变只做了一次复测（未复现），不能断言根治或必现。
- WARP 与 B 轮都没有重做缩放/最大化回归（B 轮在 4060 上已于前文做过）；B 轮长跑没有截图验证出画（前文 CI 产物验证已验证）。

## main 上 CI 产物（b8225d01）复测

日期：2026-10-25。被测：main（HEAD e76a1126）上 CI 重编并注入的 `mova/libmpv/windows-x86_64-whep/libmpv-2.dll`（10,876,416 B，sha256 前缀 b8225d01c348bb08），只读使用：拷进 `D:\tmp\var_main`（`var_ci` 副本换入新 DLL），仓库文件未改。条件同前（旧 ANGLE v1.0.1 + 原版 media_kit_video 2.0.1 + 硬件渲染，RTX 4060；MediaMTX + ffmpeg testsrc2 1280x720@30 1.5Mbps CBR + opus；`demuxer-max-back-bytes=0;demuxer-seekable-cache=no`；15s 采样，t>=60s 最小二乘）。脚本与数据在 `D:\tmp\ci3\`（不入库）。

### 1. 仓库文件核对

- `git cat-file -p HEAD:...libmpv-2.dll` 的 LFS oid 为 `b8225d01c348bb0876debba7cc0dc230145495c6dd8b70b8717969ed393ba719`，size 10876416；工作区 DLL 的 sha256 与之完全一致。
- 同目录 `libmpv-2.def` 导出名 54 个（去掉 LIBRARY/EXPORTS 行）；`libmpv.dll.a` 43,674 B，LFS 指针 size 与之相同；`libmpv-2.def` 1,123 B。

### 2. WHEP 长跑斜率

| 组合 | 时长 | 私有 MiB（t=60s -> 末） | 斜率 MiB/min |
|---|---|---|---|
| 无补丁 | 660s | 349.5 -> 445.5 | 10.07 |
| CI 版 313f45d8（第 1 次） | 991s | 336.9 -> 344.2 | 0.42 |
| CI 版 313f45d8（第 2 次） | 993s | 339.3 -> 344.7 | 0.33 |
| **main CI 版 b8225d01** | 961s（n=61） | 341.7 -> 346.4 | **0.35** |

达到 <1 MiB/min 目标，与 313f45d8 的两次结果（0.42、0.33）同一量级。句柄全程 1718~1730（t>=15s 后），没有 >+15 的上升，未出现 313f45d8 第 1 次长跑里的 +110 跳变；线程 t>=60s 为 325~331，末 326。出画：起播约 45s 与跑完 961s 后各做一次 `PrintWindow`（client 1898x1024），色条 红/绿/黄/蓝/青 = 17375/17921/17831/17597/17690 与 17679/18329/17983/17633/17613，黑色 0.6%。

### 3. 精简回归

- 起播/停止 5 轮（起播 22s、停 4s）：每轮出画（色条 1.5 万~1.8 万，其中第 4 轮红 15161、绿 9769 偏低但远大于 0），无崩溃。起播后私有/句柄/线程 335.6/1731/333、339.0/1737/333、341.3/1734/330、339.7/1734/330、340.4/1734/330；停止后 318.6~322.9 MiB、句柄 1534~1540、线程 287~292。
- 最大化/还原 5 次 + 缩放 20 次（800x600/1200x700/640x400/1000x800 轮换）+ 起始/结束共 32 次出画检查，全部 OK，`FAILS=0`，无崩溃。最大化私有内存峰值 1018~1102 MiB（与 0007 无关的既有现象，同前文，仍未处理），还原后 3s 读数 555~577 MiB；缩放阶段 339~432 MiB；句柄 1731~1742、线程 328~333，不增长。

### 4. 与 313f45d8 的差异：事实线索

两份 DLL 大小相同（10,876,416 B），`cmp -l` 只有 **12 个字节**不同，其余字节完全相同：

| 偏移 | 位置 | 含义 |
|---|---|---|
| 0x88~0x89（2 B） | PE 头 | COFF TimeDateStamp：16:16:08 对 21:06:44（本地时间） |
| 0xd8~0xd9（2 B） | PE 头 | CheckSum：00a6e63a 对 00a66974 |
| 0x9cee0c~0x9cee13（6 B，分布在 8 字节内） | `.rdata` | mpv 内嵌的 `__DATE__ __TIME__` 字符串：`Oct 25 2026 08:14:55` 对 `Oct 25 2026 13:05:36`（UTC，与上面本地时间差 8h 吻合） |
| 0xa4ec04~0xa4ec05（2 B） | `.edata` | 导出目录 TimeDateStamp |

另核对：`objdump -h` 节区名/大小完全一致（`.text` 0x7f7960 等），导出表名单一致，`strings -a` 仅有上述 `__TIME__` 一处不同。结论：两份 DLL 的代码与数据字节一致，哈希不同只因构建时间戳（PE 头、导出目录、mpv 编译时间字符串）和由此改变的 PE 校验和，没有代码或补丁差异。这是对已有字节的核对结果，不是推测。

### 5. 未验证项

- b8225d01 只做了一次 961s 长跑（313f45d8 做过两次），不单独断言噪声范围。
- 字节比较能证明两份 DLL 代码段一致，因此 0007 的有效性沿用前文斜率结论，没有对补丁逻辑另做反汇编核对。
- 仍未做 mp4/换源/真全屏回归，也未测其他 ANGLE 构建、其他显卡驱动（本机只有 RTX 4060），范围同前文"局限"。

## main 上 CI 产物（b8225d01）60 分钟长跑

日期：2026-10-26。被测与条件同上一节（`D:\tmp\var_main`，DLL sha256 与仓库 `mova/libmpv/windows-x86_64-whep/libmpv-2.dll` 一致，均为 b8225d01c348bb08...）；MediaMTX + ffmpeg testsrc2 1280x720@30 1.5Mbps CBR + opus，WHEP 起播后不换源，跑满约 3600s。每 30s 采样（n=120，末采样 t=3586s），每 5 分钟一次 `PrintWindow` 出画检查（共 13 次，含起播后 61s 与结束时）。脚本与数据在 `D:\tmp\ci4\`（不入库）。

### 结果

| 区间 | 私有 MiB（首 -> 末） | 斜率 MiB/min（最小二乘） |
|---|---|---|
| 前 10 分钟（t=60~600s，n=18） | 338.8 -> 342.7 | 0.53 |
| 10 分钟后（t>=600s，n=100） | 342.8 -> 346.1 | 0.04 |
| 全程（t>=60s，n=118） | 338.8 -> 346.1 | 0.08 |

- 私有内存 t>=30s 范围 336.5~346.1 MiB，末 346.1；增长集中在前 10 分钟（预热/缓存填充），之后基本持平。
- 句柄 t>=30s 范围 1714~1734，末 1721，无上升趋势。
- 线程 t>=30s 范围 325~332，末 327，无上升趋势。
- 出画：13 次检查全部 `ok=True`，客户区 1898x1024，色条 红/绿/黄/蓝/青 均在 1 万~1.8 万量级，黑色 0.6%，无黑屏、无冻结。有 4 次（t=604、1508、2412、3316，间隔约 15 分钟）绿色像素偏低（9756~11058，红/黄也略低到 15162~16668），推测与 testsrc2 画面内容周期变化落在采样点上有关，未做验证；其余时刻稳定在 1.7 万以上，且远大于 0。

### 结论与未验证项

- 60 分钟内私有内存、句柄、线程无持续增长，画面持续正常，与上一节 16 分钟结果（0.35 MiB/min）一致；上一节斜率偏高主要来自前 10 分钟的预热段。
- 只做了一次 60 分钟长跑，不单独断言噪声范围；仍只覆盖 RTX 4060 + 旧 ANGLE v1.0.1 + 硬件渲染，范围同前文"局限"。
- 前述绿色像素偏低的周期性原因为推测，没有逐帧核对。
