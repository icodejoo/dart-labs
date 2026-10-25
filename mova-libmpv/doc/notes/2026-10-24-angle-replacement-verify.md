# 替换随包 ANGLE 的验证：新版 ANGLE 不出画，计划不成立

日期：2026-10-24。机器：Windows 11 Pro 10.0.26100，RTX 4060 Laptop，2560x1600 真实桌面。证据原件在 `D:\tmp\w16\ev\`（日志、15s 采样 csv、截图 png，不入库）。"实测"为本机跑出，"推断"单独标注。前置背景见 `2026-10-24-angle-source-candidates.md`、`2026-10-24-windows-render-memory-growth.md`。

## 结论先行

1. **三个候选在 WHEP 15 分钟长跑里私有内存都平坦，但它们根本没把画面画出来。** 视频区域是透明的（只露出 Flutter 的底色）。此前"换新 ANGLE 后泄漏消失"的结论（a_emu / a_jbr / whep_emu）同样是在不出画的情况下得到的，**不能当作"泄漏已修复"的证据**。
2. 出画与否的分界线在 **Chromium 116 / 117**（实测，见下表）：Chromium ≤116 的 ANGLE 能出画，但同样泄漏约 10 MiB/min；Chromium ≥117 的 ANGLE 不泄漏也不出画。**没有找到"既出画又不泄漏"的版本。**
3. 因此按"只放 libEGL.dll、libGLESv2.dll、体积最小"择优没有意义：能择的范围里没有合格的东西。**我没有把任何新 DLL 接进 CMake**，仓库里的 ANGLE 仍指向上游 v1.0.1，只是校验改成了 sha256、并加了本地覆盖开关。
4. 需要你拍板：下一步是 fork `media_kit_video`（改它的共享纹理/同步方式）、改用软件渲染、还是走别的路。见"后续选项"。

## 怎么发现的

长跑只看了内存和 pos，没有看画面。到了回归阶段按"全屏/小窗/缩放并截图"去做，发现 CEF 146 的窗口里是黑的。之后的对照（同一个 `w16app`、同一个 libmpv、同一个 WHEP 源，只换两个 DLL）：

- 旧版 v1.0.1：出画。
- 其余新版：不出画。

截图方法：`CopyFromScreen` 会受到屏幕上一个 Windows 防火墙弹窗（见"环境提示"）的遮罩影响，后来改用 `PrintWindow(PW_RENDERFULLCONTENT)` 抓窗口本身。判据：用 media_kit 的 `Video` 控件把底色（fill）设成品红 `#FF00FF`，背景再垫一层青色；不出画时截图是纯品红，出画时是 testsrc2 彩条。截图里数饱和像素占比也能区分，但最可靠的是肉眼看图。

mpv 日志（`MPVLOG=.`）里新旧 ANGLE 的差别只有一条：新版在 `vo/libmpv: reconfig` 之后多了 `mpv_render_context_render() not being called or stuck.`。EGL/GL 初始化、FBO、`Texture for plane 0/1` 两边都正常打印，没有任何 `Failure` 或 shader 报错；media_kit 的 `ANGLESurfaceManager` 也没打出 `Failure`。也就是说 mpv 看起来在渲染，输出的纹理却没到屏幕上。

## 数据

### 1. 三个候选的 WHEP 15 分钟长跑（测的是"内存平不平"，不是"出不出画"）

同一个 release 构建（`w15app`，mova 当前代码 + 本地 WHEP libmpv，`demuxer-max-back-bytes=0`），WHEP `whep+http://127.0.0.1:8889/test/whep`，MediaMTX + ffmpeg testsrc2 640x360@25，930s，15s 采样。为了省时间，这几组是**并发**跑的（el、cef150、cef136 三组同时跑，cef146 单独跑），斜率是 60s 之后的线性回归。

| 候选 | DLL 合计字节 | 私有 MiB 60s → 300s → 600s → 930s | 私有斜率 | WS 斜率 | 句柄 60s → 930s | 掉帧 | 出画 |
|---|---|---|---|---|---|---|---|
| Electron v43.8.3（Chromium 150） | 8,537,600 | 299.1 → 302.0 → 303.2 → 302.6 | 0.287 MiB/min | 0.317 | 1733 → 1725 | 0/0 | **否** |
| CEF 150.0.22 | 8,381,440 | 300.1 → 302.5 → 303.3 → 303.7 | 0.242 | 0.273 | 1833 → 1815 | 0/0 | **否** |
| CEF 136.1.6（顺带发现，比 150 小） | 8,332,800 | 300.1 → 302.4 → 303.2 → 303.3 | 0.222 | 0.248 | 1745 → 1736 | 0/0 | **否** |
| CEF 146.0.12（扫描后体积最小的一个） | 8,331,264 | 300.4 → 302.1 → 303.6 → 303.9 | 0.237 | 0.257 | 1735 → 1728 | 0/0 | **否** |
| 对照：旧 v1.0.1（H 的同一套 harness，660s） | 7,886,992 | 295 → 405（658s） | **9.65** | - | 1306 → 1737 | - | 是 |

斜率全部远低于 1 MiB/min 的判据，但这是"没画"的数字。

"体积最小"的扫描（实测，从 CEF 官方索引流式读取 tar 里的两个 DLL 大小，sha1 与官方索引一致）：在扫描过的 CEF 128、132~150 各大版本（没扫 129~131、125~127）里，libEGL+libGLESv2 合计最小的是 **146.0.12，8,331,264B**（比 136.1.6 小 1,536B，比 150.0.22 小 50,176B）。更早的 114.2.13 只有 7,815,680B（比旧版还小 71,312B），但见下表。

### 2. 出画与泄漏的二分（实测）

同一个 `w16app`，`MODE=raw`（media_kit `Video` 控件，品红底色），PrintWindow 截图；泄漏用 WHEP 300~330s、60s 之后的私有内存斜率。

| 来源 | 构建时间 | DLL 合计字节 | 出画 | 私有斜率 |
|---|---|---|---|---|
| 旧 v1.0.1（ANGLE 2.1.18844） | 2022-07 | 7,886,992 | 是 | 9.65（H 的对照） |
| Motrix（Electron，2.1.19728） | 2023-05 | - | 是 | 约 12（G/H 已测） |
| CEF 114.2.13 | 2023-07 | 7,815,680 | 是 | 10.42 |
| CEF 115.3.15 | 2023-08 | 7,942,656 | 是 | 10.25 |
| CEF 116.0.27 | 2023-09 | 7,896,064 | 是 | 9.98 |
| CEF 117.2.5 | 2023-10 | 8,056,320 | **否** | 未测 |
| CEF 118.7.1 / 119.4.7 / 120.2.7 / 126.2.18 | 2023-11 ~ 2024-07 | 8.0~8.5 MB | **否** | 未测 |
| 安卓模拟器 ANGLE | 2025-08 | 12,959,024 | **否** | 平（不出画） |
| CEF 136.1.6 / 146.0.12 / 150.0.22、Electron 43.8.3、JBR（2026-03） | 2025-05 ~ 2026-10 | 见上 | **否** | 平（不出画） |

读法：出画的版本都泄漏；不出画的版本不泄漏。**推断**泄漏与不出画是同一条路径（D3D11 共享句柄 pbuffer）里的两面：这条路径在 Chromium 117 前后被改过，新实现里 media_kit 画进去的内容读不出来。这个推断没有验证，只是数据吻合。

### 3. 新版 ANGLE 的运行时事实（实测，CEF 146，用 FFI 起一个和 media_kit 同样的 D3D11 display）

- `ANGLE 2.1.27045 git hash: 1c0f91aaa60a`，`EGL 1.5`，`OpenGL ES 3.0`，渲染器是 RTX 4060 的 D3D11。
- 显示扩展里 `EGL_ANGLE_surface_d3d_texture_2d_share_handle`、`EGL_ANGLE_d3d_share_handle_client_buffer` 都为 true，pbuffer 与 context 创建成功，`eglMakeCurrent` 成功。也就是说"扩展还在"这件事成立，**但扩展在不代表内容能读出来**。`EGL_ANGLE_device_d3d` 在显示扩展里为 false（它属于 device 扩展，media_kit 不用）。
- 模块表：加载的是包目录里的 `libEGL.dll`/`libGLESv2.dll`，`d3dcompiler_47.dll` 来自 `C:\WINDOWS\SYSTEM32`。带上随包的 `d3dcompiler_47.dll` 也不出画，所以与它无关。
- `flutter_windows.dll` 自己静态内置了一份 ANGLE（不 import libEGL/libGLESv2），所以随包这两个 DLL 只有 media_kit_video 插件和 libmpv 在用，换它们不影响 Flutter 自己的界面（界面始终正常）。
- 排除项：mpv 属性 `hwdec=no`（软解）、`background=color` 都不改变不出画；`vo=libmpv`、`d3d11va-copy` 两边一致。

### 4. 在"不出画"的新版上做的回归（不作数，只记录）

CEF 146 DLL 的构建里跑了：5 轮起播/停止、HTTP mp4 + 本地 HLS + WHEP 交替、点播 mp4/HLS，全部 `pos` 前进、无崩溃；窗口缩放/最大化/无边框全屏/快速来回缩放无崩溃。**但画面全程是透明的**，所以这些"通过"没有意义，不能算回归通过。

对仓库里当前 CMake（旧版 ANGLE）构建出来的 `w16app`：raw 截图 90.3% 饱和像素，彩条正常出画，模块表加载的是包目录的 DLL、`d3dcompiler_47` 来自 System32。

## 仓库内改动（可提交的最小改动，未 commit）

### 1. `mova/packages/media_kit_libs_windows_video_slim/windows/CMakeLists.txt`

- `download_and_verify` 改为 **sha256**（`file(SHA256 …)`），不引入新依赖；下载失败（`file(DOWNLOAD … STATUS)`）和校验失败都直接 `FATAL_ERROR`，并删掉坏文件，不会静默回退旧 DLL。
- ANGLE 解压改到配置阶段，解压目录 `build/ANGLE`（**名字不能改**：`media_kit_video` 的 CMake 硬编码读取 `${CMAKE_BINARY_DIR}/ANGLE/include` 与 `ANGLE/lib/libEGL.dll.lib`、`libGLESv2.dll.lib`，所以资产里必须带 `include/` 和 `lib/`，不能只放两个 DLL；它们只用于编译链接，不进应用产物）。目录里写一个 `.mova-angle-stamp`，内容为归档 sha256（本地覆盖时为 `local`），不一致就清掉重解压，避免换版本后误用旧 DLL。原来的 `check_directory_exists_and_not_empty` 和 `*_ANGLE_EXTRACT` 自定义目标不再使用，已删除。
- 本地覆盖开关：CMake 变量或环境变量 `MOVA_ANGLE_LOCAL_DIR` 指向"资产解压后的目录"（需含两个 DLL、`lib/*.dll.lib`、`include/EGL/egl.h`），默认关闭；开启时发 `WARNING`，跳过下载与校验。
- **当前取值**：`ANGLE_URL` 仍是 `alexmercerind/flutter-windows-ANGLE-OpenGL-ES` v1.0.1 的 `ANGLE.7z`，`ANGLE_SHA256 = cc5911bb15d596fd5a2b362613ad35b7093b427117269a7359054a65746a5f9a`（该文件 md5 `e866f13e8d552348058afaafe869b1ed` 与原来固定的一致）。`bundled_libraries` 仍是 libmpv + libEGL + libGLESv2，不带 d3dcompiler_47。将来换资产只需改这两行。
- 验证（实测）：
  - 用 `cmake -S . -B b` 的独立脚本验证：`file://` 下载 + sha256 通过 + 解压；二次配置不重复解压；切到本地覆盖后戳变 `local`；切回下载会重新解压；**故意写错 sha256 会报 `Integrity check failed (expected …, got …)` 并删掉文件**。
  - 真实 `flutter build windows --release`（`w16app`）：先用本地覆盖指向 CEF 146 的资产目录，产物里是新 DLL（sha256 `0e278701…`、`5eecfffc…`）；再不带覆盖重新构建，从 GitHub 实际下载、sha256 通过、从 `local` 戳切回并重新解压，产物里是旧 DLL（`b2590bd0…`、`620bb6e3…`），产物目录里只有这两个 ANGLE DLL，没有 d3dcompiler/zlib/vk_swiftshader/vulkan-1。
- 文件在工作区是 LF（索引也是 LF，`core.autocrlf=true` 会在提交时处理）。

### 2. 精简版 NOTICE（草稿）

- 新增 `mova/packages/media_kit_libs_windows_video_slim/NOTICE.md`：ANGLE 本体（BSD-3-Clause）+ Abseil（Apache-2.0）、zlib（zlib License）两项**有二进制证据**（libGLESv2 里有 `third_party\abseil-cpp` 路径字符串、`Cr_z_*` 符号），另有 Vulkan-Headers、SPIRV-Tools、SPIRV-Headers、xxHash、VulkanMemoryAllocator、Volk 六项按 ANGLE third_party 依赖**推断**列入（二进制里没找到直接证据，为保守起见列出）。许可全文取自 Electron v43.8.3 发行包里的 `LICENSES.chromium.html` 中对应条目（Apache-2.0 全文只列一次）。glslang 不在 Chromium 的许可汇总里，没列。
- 追加 `mova-libmpv/third_party/NOTICE.md` 第 6 节指向它（原第 6 节"免责声明"顺延为第 7 节）。
- **这不是法律意见，完整性需要人工核对。** 文中也写明：清单对应 Chromium 150 线，对当前随包的 2022 版只能作参考，最终分发哪个版本要按那个版本重新核对。文件顶部标注了"草稿"状态。

## 待上传资产（已打包，**不建议上传**）

`D:\tmp\angle-release\`（未上传、未创建任何 release）：

- `mova-angle-win-x64.7z`：CEF 146.0.12 的两个 DLL + `include/`（EGL、GLES2、KHR 共 9 个头文件）+ `lib/`（旧版的两个 `.dll.lib`，导入的符号在新 DLL 导出表里都存在）。2,282,262B，sha256 `606a6067b8cd55c1a12e8a940c08305f98996a75e19bb0d081b456668427a35b`。
- `dll-only-cef146.7z`：仅两个 DLL，2,205,033B。对照：Electron 43.8.3 两个 DLL 的 7z 是 2,224,298B，CEF 150 是 2,226,197B，CEF 136 是 2,195,472B（同样用 `7z -mx=9 -m0=lzma2 -ms=on`）。
- `stage/`：打包前的目录。
- 来源与校验：CEF 146.0.12 tar.bz2 官方索引 sha1 `aacab1305cc69316958ce042aec6a2ed2a69e43c`，本机下载后吻合；`libEGL.dll` 506,368B sha256 `0e2787016b87c03609d32a2402e69a7b0c9d4c9b55bc192546d68a13536f04d4`；`libGLESv2.dll` 7,824,896B sha256 `5eecfffc990b0742eb8f65173e42f6c57118a8c391dccd9f267935fc77f1f26a`。DLL 为 Authenticode 未签名。

**由于新 DLL 不出画，这个资产不能用，不要上传。** 如果以后找到可用的构建，上传命令的草稿如下（**只记录，没有执行**；tag 与资产名是占位，需你确认；`gh release create` 会对外发布，需要你点头）：

```bash
# 草稿：不要在确认可用的构建之前执行
gh release create mova-angle-chromium-<版本> \
  --repo icodejoo/dart-labs \
  --title "mova ANGLE <版本>（Windows x64）" \
  --notes "只含 libEGL.dll、libGLESv2.dll 与编译用 include/、lib/；来源与 sha256 见 PROVENANCE。" \
  D:/tmp/angle-release/mova-angle-win-x64.7z
# 之后把 CMakeLists.txt 里的 ANGLE_URL 改成
#   https://github.com/icodejoo/dart-labs/releases/download/<tag>/mova-angle-win-x64.7z
# ANGLE_SHA256 改成上面记录的 sha256。
```

## 后续选项（需你拍板，我没动）

1. **fork `media_kit_video`**（它在 pub 缓存里，是外部依赖）：定位新 ANGLE 下共享句柄 pbuffer 读不出内容的原因，改成 `EGL_ANGLE_d3d_texture_client_buffer`（直接传 `ID3D11Texture2D*`）或加 keyed mutex / 显式同步。这是新增一个 fork 的依赖，需要你同意。我的推断（未验证）是新版 ANGLE 在共享句柄上换了同步语义，`glFinish()` 之后另一个 D3D 设备的 `CopyResource` 读到的是空内容；也可能是 alpha 恒为 0。两者都没有证据，下一步用 `MPV_RENDER_PARAM` 读回像素或用 PIX/RenderDoc 看共享纹理内容可以区分。
2. **软件渲染兜底**：`enableHardwareAcceleration:false`，实测不泄漏（`r_swrender`，见内存增长笔记），代价是 CPU 读回；之前没测 CPU 占用。
3. **不经 ANGLE**：libmpv 用原生 d3d11 渲染到共享纹理（需要改 libmpv 构建与 media_kit 之间的接口，工作量大）。
4. **自编 ANGLE 打补丁**：泄漏出现在 Chromium ≤116；若能定位具体泄漏点，在旧版上打补丁并自编，体积可控。需要 depot_tools/MSVC，成本高，并且要先确认泄漏点在 ANGLE 里。
5. 若只想先压住 mpv 侧的增长：`demuxer-max-back-bytes=0` + `demuxer-seekable-cache=no`（已在内核里对 live 生效），只剩 ANGLE 的 ~10 MiB/min。

## 未解决

- 新 ANGLE 不出画的根因没有定位（见选项 1），只缩小到 Chromium 116→117。116 和 117 之间的小版本、以及 120~136 之间是否有个别构建恢复出画，没有逐个测（测过 117、118、119、120、126、136、146、150、Electron 43、模拟器、JBR，均不出画）。
- 泄漏是否真的在"出画"那条路径里，只有相关性，没有因果验证。
- 用户要求的"体积最小增量"没有可交付的结果：在出画的版本里，114 比旧版小 71 KB 但泄漏；不出画的版本里 CEF 146 最小（+444,272B）。
- 回归项里全屏/小窗/缩放、HTTP mp4、HLS、5 轮起播在新 DLL 上跑过但画面透明，不作数；未在旧 DLL 上重跑全套（旧 DLL 是现状，之前已验证）。

## 环境提示

- 屏幕上出现了一个 Windows 防火墙弹窗："Windows 防火墙已阻止…ffmpeg.exe 的某些功能"，不是我的流程点出来的（我的 ffmpeg 推流只走回环；机器上同时有其它任务在起 ffmpeg/python/mediamtx），我**没有点**它（"取消"会写入阻止规则，"允许"会改防火墙），留给你处理。它会遮挡 `CopyFromScreen` 截图，所以改用了 `PrintWindow`。
- 我的 MediaMTX（端口 8889/18554，配置 `D:\tmp\mtx\win_chunked.yml`）曾被另一个任务借用（日志里出现过路径 `w18`，21:39~21:40）。收尾时我只停了自己起的 mediamtx(15636)、ffmpeg(37512)、http.server(33040)；采样器随被测进程退出而结束；`w16app`/`w15app` 进程已全部退出。
- 我没有改仓库里的 `mova/lib`、没有改计划文档、没有 `git commit`、没有 `pubspec_overrides.yaml`；测试工程与构建副本在 `D:\tmp\w16\`（`app\` 是 `w16app`，含 `raw`/`layout`/`egl` 等模式和 FFI 的 EGL 探测）。

## 方法

- 构建：`D:\tmp\w16\app`（`w15app` 的副本，改名 `w16app`，`media_kit_libs_windows_video` 指到 `D:\tmp\w16\pkg`，即带 WHEP libmpv 的 `slim_pkg` 副本 + 仓库当前 `CMakeLists.txt`）；`flutter build windows` 用 `Start-Process explorer.exe <脚本.cmd>` 代启动（RedirectionGuard），fvm Flutter 3.47.1。
- 长跑：每个候选目录复制 `D:\tmp\w15\rel_b`（旧 DLL 的 release 目录）后只覆盖两个 DLL；`MODE=long SEC=930 LIVE=1`；采样器按 PID 取 WS/私有/句柄/线程，15s 一点；掉帧来自应用每 30s 打印的 `frame-drop-count`/`decoder-frame-drop-count`。
- 二分：`extract_dlls.py` 从 `cef-builds.spotifycdn.com` 的 tar.bz2（aria2 16 连接下载，核对官方 sha1）里取两个 DLL；`raw` 模式截图判断出画。
- 下载只用于获取公开发行物；没有上传任何文件到任何外部服务，没有创建 GitHub release。
