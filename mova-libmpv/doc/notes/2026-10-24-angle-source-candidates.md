# 新版 ANGLE 候选来源调研（替换随包 2022-08 ANGLE）

日期：2026-10-24。只查不改仓库，没有动 CMake。下载与静态检查在 `D:\tmp\angle-src\<候选>\`，全程没运行任何下载来的可执行文件（只用 Python 读 PE、`Get-AuthenticodeSignature`）。"实测"为本机核对，"推断"单独标注。背景见 `2026-10-24-windows-render-memory-growth.md`、`2026-10-02-windows-angle-shrink.md`。

## 结论先行

1. **现在的主流发行物已经没有独立的 libEGL.dll/libGLESv2.dll 了**（实测）：Chrome 155 本机安装目录没有；Electron 44/45 的 zip 没有；CEF 151 起两个 DLL 只剩 463,872B 的同尺寸壳（ANGLE 并进了 libcef.dll）；Flutter 引擎的 `flutter_windows.dll` 也是静态内置 ANGLE，artifacts 里没有独立 DLL。所以"最新版"不可选，**能拿到真 DLL 的最新线是 Chromium 150 / Electron 43 / CEF 150**。
2. 推荐候选：**A. Electron v43.8.3**（Chromium 150.0.7871.250，GitHub release，zip 有官方 sha256 digest），备选 **B. CEF 150.0.22**（同为 Chromium 150，cef-builds 官方索引只给 sha1）。两者都接口兼容、体积 +0.5~0.6 MiB。
3. **需要你拍板的点**：两个来源的 zip 都是 150~165 MB，只为取 2 个 DLL。CMake 直连下载每次构建拉 150 MB 不现实。建议把这两个 DLL（+许可证）从选定的官方包里提出来，作为我们自己仓库的 GitHub release 资产（不入 git 仓库），CMake 用 URL + sha256 校验下载；备选是 CMake 直拉官方 zip 并解压取两个文件（慢但来源最原始）。见"接入方式"。
4. 许可证：ANGLE 本体 BSD-3-Clause（google/angle LICENSE），能随 LGPL 的 mova 分发；但 libGLESv2 里还静态带了 glslang/SPIRV-Tools/zlib 等第三方代码，需要随包带上聚合的第三方声明。**这一条我没法替你定论**，见"许可证"。

## 候选对比

旧基线（alexmercerind `ANGLE.7z` v1.0.1，md5 `e866f13e8d552348058afaafe869b1ed`）：libEGL 472,904B + libGLESv2 7,414,088B = 7,886,992B；PE 时间戳 2022-07-30；ANGLE git `2693b03eba82`。

| 项 | A. Electron v43.8.3（推荐） | B. CEF 150.0.22 minimal | C. alexmercerind 新 release | D. Electron 44/45、CEF 151+、Chrome 155 | E. NuGet `ANGLE.WindowsStore` | F. JBR/Android 模拟器自带 |
|---|---|---|---|---|---|---|
| 版本 | Electron 43.8.3，Chromium 150.0.7871.250；ANGLE 2.1.28042，git `57fed7f75929`；PE 时间戳 2026-10-20 | CEF 150.0.22+gc1a097e，Chromium 150.0.7871.256；ANGLE 2.1.27974，git `bad2d7da0131`；PE 时间戳 2026-10-02；索引 last_modified 2026-10-09 | 无新版：只有 v1.0.0（2022-12，md5 `e5be38d0e1c5cbe5f70e53701ea8b6c9`）和 v1.0.1；v1.0.1 资产 md5 与 CMake 现用的完全一致，DLL 仍是 2022-07 的（实测），发布时间 2024-09 只是重传 | 没有独立 DLL（见上） | 2.1.13，UWP 版 | JBR 2026-03：本地循环 240s、WHEP 630s 平坦（已测） |
| 下载地址 | `https://github.com/electron/electron/releases/download/v43.8.3/electron-v43.8.3-win32-x64.zip`（151,457,540B） | `https://cef-builds.spotifycdn.com/cef_binary_150.0.22%2Bgc1a097e%2Bchromium-150.0.7871.256_windows64_minimal.tar.bz2`（164,266,201B） | github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases | - | nuget.org | 不可再分发 |
| 校验 | release API 的 `digest` = `sha256:98efbd2d1c7bd44150c0aa800cd9ac5fefcefd2d44fd94958a95d6744d86c6de`，本机下载后 sha256 吻合（实测）；另有 release 内 `SHASUMS256.txt` | index.json 的 sha1 `01011e3f5b05caacb3b724c7965b047ffd33fd18`，本机吻合（实测）；只有 sha1，偏弱 | - | - | - | - |
| libEGL.dll | 467,968B，sha256 `6684bb1655fd78a3fc448cc1c7e9ce2bd4d5a0cf318fe458fbf75340d95e5554` | 496,640B，sha256 `4218b6813492291252138c5b6f8f147595bb324afe47b14638f80fe963c47ee2` | 472,904B | - | - | - |
| libGLESv2.dll | 8,069,632B，sha256 `7d4828964cd058ca6f355f5dd85e4e65a8c673ea342c992586dd285e14bd3094` | 7,884,800B，sha256 `3264949ffffec870e42cdb814d429321f076311aef3df6064c6d9f14cb54d875` | 7,414,088B | - | - | - |
| 两个合计 / 相对旧 | 8,537,600B / +650,608B（+0.62 MiB） | 8,381,440B / +494,448B（+0.47 MiB） | 7,886,992B / 0 | - | - | - |
| 签名 | Authenticode 未签名（实测，PowerShell 状态 NotSigned）；靠来源渠道的 sha256 | 同样未签名；靠 sha1 | - | - | - | - |
| 许可证 | 见下节 | 见下节 | - | - | - | - |
| 兼容性 | 通过（见下） | 通过（见下） | 即现状（泄漏） | - | **不兼容**：导入 `msvcp140_app.dll`/`vcruntime140_app.dll`，桌面进程起不来（上次瘦身笔记 变体 G） | 仅作验证参照 |

随包文件集：上次瘦身后只带 `libEGL.dll`、`libGLESv2.dll`，**不**带 d3dcompiler_47/zlib/vk_swiftshader/vulkan-1。新 DLL 也只需要这两个：A/B 的 libGLESv2 导入表只有 USER32/KERNEL32/dxgi/GDI32，延迟导入 d3d9；libEGL 只导入 KERNEL32（实测），没有 CRT 依赖，所以也不用补 vcruntime。d3dcompiler_47 仍然是 libGLESv2 按名字运行时加载（字符串里有 d3dcompiler_43/46/47，实测），与上次结论同：Win10+ 走系统目录；不随包。

## 与 media_kit_video 的兼容性（实测，静态核对）

- media_kit_video 2.0.1 的 `angle_surface_manager.cc` 用到的 EGL 符号：`eglGetPlatformDisplayEXT`、`eglInitialize/Terminate`、`eglChooseConfig`、`eglCreateContext/DestroyContext`、`eglCreatePbufferFromClientBuffer`、`eglBindTexImage/ReleaseTexImage`、`eglMakeCurrent`、`eglGetProcAddress` 与 `EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE`、`EGL_PLATFORM_ANGLE_ANGLE`。
- 用已构建的 `media_kit_video_plugin.dll`（`D:\tmp\w13\...`）的导入表按名字对照：它从 libEGL 导入 11 个、从 libGLESv2 导入 4 个符号，**在 Electron 43 和 CEF 150 的两个 DLL 导出表里全部存在**（缺失 0）。
- libGLESv2 字符串里仍有 `EGL_ANGLE_d3d_share_handle_client_buffer`、`EGL_ANGLE_surface_d3d_texture_2d_share_handle`、`EGL_ANGLE_device_d3d`（A、B 都有，实测）；OpenGL ES 3.0/3.1/3.2 字符串仍在。**这只是字符串存在，运行时是否仍对 D3D11 后端广告该扩展我没有跑，属于待验证项。**
- 旧版有而新版没有的导出：`eglSwapBuffersWithFrameTokenANGLE`、`ANGLEGetDisplayPlatform`、`PlatformMethods` 等内部/过时符号，不在 media_kit 使用范围内。新版导出更多（libEGL 115 vs 108）。
- Electron 43 与 CEF 150 的 libGLESv2 字节不同（git 不同），属于同一 Chromium 150 线上的两次构建。

## 是否含泄漏修复（线索）

- **没有查到**与"D3D11 后端按帧泄漏 260~430KB 私有区块"直接对应的 ANGLE commit 或发行说明。我没有二分，也没有找到 ANGLE 的 issue 对应项。
- 间接证据（已测）：2023-05（Motrix）仍涨；2025-08（模拟器）、2026-03（JBR）平坦。A/B 的 ANGLE 为 2026-10 构建，在已验证平坦的区间之后，**推断**不会回退，但这是必须实测的，不能当结论。
- Electron 43.8.3 release 说明里有一条 "Backported fixes from upstream ANGLE, Chromium, PDFium, Skia and V8"，不具体。

## 许可证

- ANGLE：BSD-3-Clause（google/angle 仓库 LICENSE，首行 `Copyright 2018 The ANGLE Project Authors`，实测读取）。条款要求二进制再分发带版权声明与免责声明；不禁止 LGPL 产品分发。
- 第三方：libGLESv2 静态链了 ANGLE 的 third_party（glslang、SPIRV-Tools、SPIRV-Cross、zlib 等；**推断**，没逐个核对导出/字符串）。Electron zip 里的 `LICENSES.chromium.html`（5.7 MB，含 348 处 BSD 式条款块）是 Chromium 整体的聚合声明，范围远大于 ANGLE；我没能在其中按标题定位到只属于 ANGLE 的条目。CEF minimal 包只带 CEF 自己的 BSD LICENSE.txt，README 说其他软件另有协议，没有聚合声明文件（实测没有 LICENSES 文件）。
- **停在这里，需要你定**：随包时应带哪份声明——只带 ANGLE 的 BSD LICENSE，还是带 Electron 的 `LICENSES.chromium.html`（5.7 MB，会吃掉瘦身成果）？建议按 ANGLE 仓库的 `third_party` 实际链入项补一份精简 NOTICE。是否可接受由你/法务判断，我没有下结论。
- Electron zip 本身还含 Electron 的 MIT LICENSE，但我们只取两个 DLL，不分发 Electron 其余部分。
- 另：旧的 alexmercerind 包同样是 ANGLE 构建，现有随包是否已有 NOTICE 我没有核对。

## 推荐

**首选 A（Electron v43.8.3）**
- 理由：GitHub release 稳定地址 + 官方 sha256（release digest 与本机下载一致）；Chromium 150.0.7871.250 带 Electron 的安全补丁线，更新持续；体积 +0.62 MiB，与现随包接近；两个 DLL 实测与 media_kit 插件符号完全兼容。
- 风险：zip 151 MB 只取 2 文件；构建 ANGLE 是 Chromium 的配置（可能删减部分 EGL 扩展，见"待验证"）；DLL 未签名；Electron 44 起这条线终止，之后升级要换来源或自编；泄漏修复未经 WHEP 15 分钟实测。

**备选 B（CEF 150.0.22）**
- 理由：体积略小（+0.47 MiB），官方只做 CEF，tar.bz2 里与 JBR 同源血统（JBR 2026-03 的版本已证明平坦）。
- 风险：只有 sha1；CEF 151 起不再有独立 DLL，到此为止；无聚合声明文件。

**不推荐**：C（无更新，仍泄漏）；E（UWP 版不兼容）；F（JBR 为 GPL+CE 的运行时、模拟器为 Android SDK 许可，来源不可复现）；自己从 google/angle 源码编译（一次性成本高，且 Windows 下需 depot_tools/MSVC，除非前几者都不可接受）。

## 接入方式（待你选定后再做，当前未改任何文件）

1. 推荐：在我们自己的仓库发一个 release（例如 `mova-angle-<chromium版本>`），资产只放 `libEGL.dll`、`libGLESv2.dll`、`NOTICE`/`LICENSE` 与一个记录**来源 URL、官方 sha256、DLL 各自 sha256**的 `PROVENANCE.txt`（不入 git）。`CMakeLists.txt` 里把 `ANGLE_URL` 指向该资产，`ANGLE_MD5` 改成 sha256 校验（`download_and_verify` 目前是 md5，需要看是否支持 sha256；这涉及改函数，实施时再确认）。
2. 或：CMake 直拉官方 Electron zip，校验官方 sha256 后只解出两个 DLL。来源最原始、无需再托管，代价是每次干净构建多下 151 MB（CI 缓存可缓解）。
3. 无论哪种，`bundled_libraries` 列表保持现在的三项（libmpv + libEGL + libGLESv2），其余瘦身结论不变；`d3dcompiler_47.dll` 仍不随包。

## 选定后的验证计划

1. 先在 `D:\tmp\w14\app`（最小工程）只替换两个 DLL：WHEP，`demuxer-max-back-bytes=0;demuxer-seekable-cache=no`，**≥15 分钟**，15s 采样私有内存/WS/句柄；判据同 `whep_emu`（15 分钟总增 ≤ 约 5 MiB）。再跑一次默认 mpv 参数，确认只剩后向缓冲斜率（约 7 MiB/min）。
2. 本地 mp4 `loop-file=inf` 240s（对照 `a_emu`/`a_jbr`）。
3. 场景回归（同 2026-10-02 瘦身笔记的方法，截图数饱和色占比）：内嵌、全屏、App 内小窗、退出后；窗口缩放（`VideoOutput.Resize` 重建纹理，多做几次来回缩放，观察是否崩溃/黑屏/内存阶梯）。
4. 源类型：HLS（点播与直播）、本地 mp4、WHEP；高分辨率（1080p/4K）一次，确认没有退化。
5. 运行时验证扩展：启动日志里取 `eglQueryString` 的 `EGL_EXTENSIONS`/`GL_VERSION`，确认 D3D11 后端下 `EGL_ANGLE_surface_d3d_texture_2d_share_handle` 仍被广告（本次只核对了字符串）。
6. 瘦身文件集：确认模块列表只多了这两个新 DLL，`d3dcompiler_47.dll` 仍从 `System32` 加载；对比安装包体积 +约 0.6 MiB。
7. 多 GPU/无独显：至少在一台集显机器与本机独显上各跑一遍，因为 Chromium 构建对驱动 bug 的 workaround 有变化。
8. CI：CMake 校验失败时必须明确报错，不允许静默回退旧 DLL。

## 未解决 / 需要拍板

1. 选 A 还是 B；是否自托管这两个 DLL 的 release（引入一个新的二进制分发点）。
2. 随包 NOTICE 的范围（见"许可证"）。
3. 泄漏修复版本区间未二分；若要确证，可再取 Chromium 130~140 段的 CEF（上面探测显示 CEF 128/132/136/140/144/150 都带独立 DLL，体积 7.8~8.2 MB）。
4. `download_and_verify` 目前是否支持 sha256，实施时再看。
5. NuGet 上 CEF 相关包（如 CefSharp 的 `cef.redist.x64`）里的 libEGL/libGLESv2：**没有核对**，本次略过；它们本质是 CEF 同源，不会比 B 多出新信息，只多一个 nuget 校验渠道。

## 本机留存（不入库）

`D:\tmp\angle-src\`：`alex100`/`alex101`（旧包）、`electron45`（无 DLL 的证据）、`electron43`、`cef150`、`cef156`（无 DLL 的证据）、`probe\`（CEF 各大版本是否带 DLL 的流式探测结果）、`pe.py`/`imp.py`/`exp.py`（静态读取脚本）。
