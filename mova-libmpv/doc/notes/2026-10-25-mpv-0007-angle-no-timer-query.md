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
