# Windows 随包 ANGLE DLL 裁剪调研与实测

日期：2026-10-02。结论先行：**`zlib.dll`、`vk_swiftshader.dll`、`vulkan-1.dll` 可以放心删（5.88 MB）；`d3dcompiler_47.dll` 在 Windows 10+ 上也可删（再省 4.89 MB），合计 10.78 MB（10.28 MiB）；`libEGL.dll`/`libGLESv2.dll` 不能删。** 下文标"实测"的是本机真跑的结果，标"推断"的是读源码或逻辑得出、没验证的。

环境：Windows 10 Pro 19045（本机通过远程会话使用，截图里能看到"正在进行远程会话"条），有 D3D11 硬件适配器；Flutter 3.44+ release 构建，media_kit_video 2.0.1（pub cache 里 1.3.0 的 windows 目录与它的 ANGLE 部分逐行相同，已 diff 确认）。

## 1. 各 DLL 用途与依赖

| DLL | 字节 | 谁用它 | 依据 |
|---|---|---|---|
| libEGL.dll | 472,904 | `media_kit_video_plugin.dll` 静态导入（链接 `libEGL.dll.lib`） | 实测：PE 导入表 |
| libGLESv2.dll | 7,414,088 | 同上；libEGL 静态导入它；libmpv 的 GL 渲染经它走 D3D11 | 实测：PE 导入表 |
| d3dcompiler_47.dll | 4,891,080 | libGLESv2 **运行时按名字 LoadLibrary**（串里有 d3dcompiler_43/46/47/old），不在导入表里；用来把 GLSL 翻成 HLSL 后编译 | 实测：导入表无、字符串有；运行时模块列表见 §3 |
| vulkan-1.dll | 872,776 | 只有 ANGLE 选 Vulkan 后端才会被 libGLESv2 按名加载 | 实测：字符串；media_kit 从不请求 Vulkan（见下） |
| vk_swiftshader.dll | 4,808,008 | Vulkan 的软件 ICD，靠 `vk_swiftshader_icd.json` 被 vulkan-1 发现；**包里没有这个 json** | 实测：libGLESv2 字符串含 `vk_swiftshader_icd.json`，ANGLE 目录无此文件 |
| zlib.dll | 203,264 | **没有任何人用**：libGLESv2/libEGL/libmpv/media_kit 各插件的导入表和字符串里都没有它 | 实测。顺带：它导入 `ucrtbased.dll`、`vcruntime140d.dll`，是 **Debug CRT 构建**，在没装 VS 的机器上本来就加载不起来 |
| libc++.dll（1,275,904） | — | ANGLE.7z 里有但**从未被打包**（不在 bundled_libraries 里），所以不算 | 实测：列表 |

PE 导入表用自写的 Python 解析（本机没有 dumpbin/objdump，脚本在 `C:\Users\jelon\whep-win\angle-test\imports.py`）。

- libGLESv2：静态导入 dxgi/gdi32/kernel32/user32，延迟导入 d3d9。**不静态依赖 d3dcompiler、vulkan、zlib。**
- libEGL：只导入 kernel32 和 libGLESv2。
- **libmpv-2.dll（14,075,392）不导入 zlib.dll**（实测，符合预期；ffmpeg 的 zlib 是静态进去的）。

### media_kit_video 怎么用 ANGLE（读 `angle_surface_manager.cc/.h`，实测=源码）

1. `CreateD3DTexture`：自己 `D3D11CreateDevice`，Win10 RTM+ 用 `D3D_DRIVER_TYPE_HARDWARE`，feature level 11_0 → 9_3。失败直接 `return false`，上层 `throw "Unable to create Windows Direct3D device."`。
2. `CreateEGLDisplay`：依次尝试 4 组属性，**全是 D3D11 或 D3D9**：D3D11 → D3D11 9_3 → D3D9（device type HARDWARE）→ "Wrap"。其中 `kWrapDisplayAttributes` 名字像 WARP，但内容和第一组 D3D11 一模一样，**没有 `EGL_PLATFORM_ANGLE_DEVICE_TYPE_WARP_ANGLE`**。
3. 全程没有请求 Vulkan/SwiftShader/GL 后端。所以 `vulkan-1.dll`、`vk_swiftshader.dll` 在 media_kit 的路径上不可达。

## 2. d3dcompiler_47.dll 在系统里的情况

- 本机实测：`C:\Windows\System32\d3dcompiler_47.dll` 存在，4,517,376 字节，版本 10.0.19041.3636。随包那份是 4,891,080 字节、10.0.20348.1（比系统的新，体积不同）。
- 微软文档说法：**这一条我没查到微软页面的原文**。找到的是：微软为 Windows 7 SP1 / Server 2008 R2 SP1 / Server 2012 单独发了 KB4019990（"Update for the D3DCompiler_47.dll component"，搜索结果确认存在，support.microsoft.com 页面我没能抓到原文）；"Windows 8.1 及以后自带"来自社区/二手来源，属于**推断**。
- 本机运行时证据（实测）：把 app 目录里的 d3dcompiler_47.dll 删掉后（变体 C/E），进程模块列表里它从 `C:\Windows\SYSTEM32\` 加载，播放正常。说明 ANGLE 的 LoadLibrary 是"先 app 目录后系统目录"，Win10 有系统版就够。
- Flutter 桌面官方只支持 Windows 10+（推断，未在本次查文档）。若产品只面向 Win10+，d3dcompiler_47 不需要随包。

## 3. 变体实测

方法：以 `example/lib/main_angle_shrink_verify.dart`（临时文件，已删，不入库）release 构建（`flutter build windows --release`，没有加 `--no-enable-impeller`，release 命令不支持该开关，用默认后端），`cmake --install` 到 `C:\Program Files\mova_example`，再复制成 A–G 七份隔离目录手工删文件。每个变体由脚本启动，`MOVA_LOG` 落盘，播放 `example/assets/test_video.mp4`（640x360、约 12 秒，播完重开一次）约 25 秒：内嵌 → `setFullscreen(true)` → 退出 → `setMini(true)`+`showInPage`（App 内小窗）→ 退出，在各阶段由日志标记触发脚本对**窗口截屏**，用 PIL 数饱和色像素占比（有彩条画面 ≈0.76，黑屏/纯底色 ≈0）。判据都是真实事件：`MovaSizeChange`（640x360）、position 每秒推进、`fs`/`mini` 状态位。

| 变体 | 删除 | 删除字节 | 出画（内嵌/全屏/小窗/退出后，饱和占比） | 崩溃 | 备注 |
|---|---|---|---|---|---|
| A 基线 | 无 | 0 | 0.76 / 0.76 / 0.76 / 0.76 | 无 | 运行中模块：libGLESv2、libEGL、dxgi、d3d11、d3d9、app 目录的 d3dcompiler_47；**没加载** zlib/vulkan-1/vk_swiftshader |
| B | zlib | 203,264 | 同上 全 0.76 | 无 | 与 A 无差异 |
| C | zlib + d3dcompiler_47 | 5,094,344 | 全 0.76 | 无 | d3dcompiler_47 改从 System32 加载（实测模块路径） |
| D | zlib + vk_swiftshader + vulkan-1 | 5,884,048 | 全 0.76 | 无 | 与 A 无差异 |
| E | 以上四个全删 | 10,775,128 | 全 0.76 | 无 | 同 C 的加载路径；SizeChange 共 7 次、position 单调推进、含一次 Done 重开 |
| F（反例） | libEGL + libGLESv2 + 其余 | — | — | 进程没起来，日志文件都没生成 | 脚本 60 秒超时后强杀；推断是加载器报缺 DLL 的对话框，**没有抓到对话框**。符合 media_kit_video_plugin 静态导入这两个 DLL |
| G（反例） | E + 换成 NuGet ANGLE.WindowsStore 2.1.13 的 x64 libEGL/libGLESv2（1.97MB） | — | — | 进程没起来 | 该包导入 `msvcp140_app.dll`/`vcruntime140_app.dll`（UWP 专用 CRT），桌面应用没有，**不是 drop-in** |

注意：
- 第一轮每个变体的"全屏"截屏 A/B 是黑的，原因是 12 秒视频恰好在截屏瞬间播完重开（日志里 `Done`→`SizeChange 0x360→0x0` 对得上），是测试时序问题，**不是 ANGLE**。改成早点进全屏后重跑一轮，全部变体 4 张图都是 0.76。上表是第二轮。第一轮数据保存在 `C:\Users\jelon\whep-win\angle-test\run1\`。
- 每个变体只跑了一次完整流程（第一轮 + 第二轮共两次，结论一致）。样本量小，不是压力测试。
- 本机有 D3D11 硬件适配器，**没有测"无 GPU 机器"**。

## 4. 兜底风险评估

- **无 D3D11 能力（旧显卡、部分 VM）**：首先在 media_kit 自己的 `D3D11CreateDevice(HARDWARE)` 失败，直接抛"Unable to create Windows Direct3D device"，**根本到不了 ANGLE**，所以有没有 SwiftShader 无关（源码推断，未实测）。ANGLE 内部四次尝试都是 D3D11/D3D9，没有 Vulkan。再说 Flutter 引擎自己也需要 D3D11。结论：SwiftShader 是死重，删它不改变任何降级行为。
- **失败后果**：是 libmpv 回退软件路径还是黑屏，我没有读 Dart 层 `VideoController` 对这个异常的处理，**未验证**。从 C++ 看是抛 `std::runtime_error`，不会回退到 libmpv 软件渲染（推断）。
- **vulkan-1.dll**：没有 ICD json 的情况下 SwiftShader 本来就找不到，只可能找系统里真实显卡驱动的 Vulkan ICD；media_kit 不选 Vulkan，不可达。
- **d3dcompiler_47**：风险只在 Windows 7/8（无 KB 的机器）或残缺系统（精简版/某些 Server Core 变体，推断）。ANGLE 内部还会尝试 d3dcompiler_46/43，也都是系统组件。如果产品要支持 Win7，保留；只支持 Win10+ 可删。
- **Impeller**：本轮没有测 `--no-enable-impeller`（CLAUDE.md 里那个 libmpv 崩溃规避）与 ANGLE 裁剪的交互，两者互不相关，但**没测**。

## 5. 精简 ANGLE（只留 D3D11）调研（不动手构建，全部是资料/推断）

- 我实测到的唯一硬数据：NuGet `ANGLE.WindowsStore` 2.1.13 的 x64 libGLESv2.dll = **1,972,880** 字节（Win32 1,460,368，ARM 1,392,784），libEGL 32,912。但它是 **UWP 构建，依赖 `_app` CRT，不能直接给桌面 App 用**（变体 G 实测起不来），版本也老（2.1.13，对比我们现在的 2.1.18844）。能说明的只是"D3D11-only 的 ANGLE 可以到 2MB 级"。
- 网上没找到"Chromium 新版 + `angle_enable_d3d9/gl/vulkan/swiftshader=false`"的精确体积数字。一条资料（NucleusFramework/angle）说 Electron 里取出的 libGLESv2 约 8.5MB，包含 Vulkan、桌面 GL、D3D9、SwiftShader、OpenCL 前端、GLES1，GN 层全关能显著缩小，但没有给最终字节数。
- 推断预估：新版 ANGLE D3D11-only、`is_component_build=false`、`symbol_level=0`、`angle_enable_vulkan=false`、`angle_enable_gl=false`、`angle_enable_d3d9=false`、`angle_enable_swiftshader=false`、关 GLES1/CL，**x64 约 2–3.5MB**（信息不足，区间很宽）。多出的是 D3D11 渲染器 + 翻译器（SPIR-V/HLSL 输出）本身。再收益约 **4–5.4MB**（7.41MB → 2–3.4MB）。
- 工作量（推断）：拉 Chromium depot_tools + ANGLE 源码（几 GB），Windows 上 clang-cl 构建约 1–2 小时首编；需要对齐 media_kit 用到的 EGL 扩展（`EGL_ANGLE_d3d_share_handle_client_buffer`、`eglCreatePbufferFromClientBuffer`、`EGL_ANGLE_platform_angle_d3d` 等）；还要在 CI 里长期维护（和 mova-libmpv 的 CI 类似），并走 LICENSE 合规。对 Flutter 3.x 兼容性：media_kit 只用 ANGLE 的 EGL/GLES 接口，不依赖 Flutter 引擎里那份，所以不涉及 Flutter 版本（推断）。
- 判断：**先做 §6 的删文件（零成本，10.78MB），精简 ANGLE 再省 4–5MB 的性价比低，暂不建议。**

## 6. 推荐删除清单与总收益

推荐（实测通过，Windows 10+ 为前提）：

| DLL | 字节 | 建议 |
|---|---|---|
| zlib.dll | 203,264 | 删（无人使用，且是 Debug CRT 构建） |
| vk_swiftshader.dll | 4,808,008 | 删（不可达；无 ICD json） |
| vulkan-1.dll | 872,776 | 删（不可达） |
| d3dcompiler_47.dll | 4,891,080 | 删（Win10+ 系统自带，实测从 System32 加载）；若要支持 Win7/8 则保留 |
| libEGL.dll / libGLESv2.dll | 472,904 / 7,414,088 | **保留**（静态导入，删了起不来） |

收益：前三项 **5,884,048 字节（≈5.61 MiB）**，全删 **10,775,128 字节（≈10.28 MiB）**，打包的 ANGLE 部分从 18.7MB 降到 7.89MB（libEGL+libGLESv2）。

顺带一个更大的头：这个 example 目录里还有 `onnxruntime.dll` 17.8MB + `sherpa-onnx-c-api.dll` 4.6MB（来自 mova_stt，不是 mova 本体），整包 DLL 合计 77.1MB，其中 ANGLE 相关 18.7MB，libmpv 14.1MB，flutter_windows.dll 21.3MB。如果评估的是"mova 自己引入的体积"，stt 那两个比 ANGLE 还大，但那不在本任务范围。

### 落地改动片段（只写在笔记，未改仓库）

文件 `C:\workspace\dart-labs\mova\packages\media_kit_libs_windows_video_slim\windows\CMakeLists.txt`，末尾的 `media_kit_libs_windows_video_bundled_libraries`：

```diff
 set(
   media_kit_libs_windows_video_bundled_libraries
   "${CUSTOM_LIBMPV_DLL}"
-  "${ANGLE_SRC}/d3dcompiler_47.dll"
   "${ANGLE_SRC}/libEGL.dll"
   "${ANGLE_SRC}/libGLESv2.dll"
-  "${ANGLE_SRC}/vk_swiftshader.dll"
-  "${ANGLE_SRC}/vulkan-1.dll"
-  "${ANGLE_SRC}/zlib.dll"
   PARENT_SCOPE
 )
```

保守方案（只删 5.88MB、仍随包 d3dcompiler_47）：只去掉 `vk_swiftshader.dll`、`vulkan-1.dll`、`zlib.dll` 三行。`media_kit_video` 的链接只用 `ANGLE/lib/libEGL.dll.lib`、`libGLESv2.dll.lib`，不依赖这几个 DLL，所以不影响编译（推断，未在改过的 CMake 上重新 configure；本次实验是直接删构建产物里的文件）。

## 7. agy（Antigravity）说法核对

| agy 的说法 | 核对结果 |
|---|---|
| 微软 FXC 文档里有原文 "The d3dcompiler_47.dll is included inbox with Windows 8.1 and Windows 10." | **证伪**：我抓取了该页，正文只有"FXC 是离线 HLSL 编译工具，位于 SDK 目录"一句，**没有这句话**。引用是编的。"8.1+ 自带"这个事实本身多半对，但没拿到微软原文 |
| KB4019990 是 Win7 SP1 补丁 | 证实存在（搜索结果多处确认），微软页面原文没抓到 |
| ANGLE.WindowsStore x64 libGLESv2.dll = 1,972,880 字节 | **证实**（我独立下载解压得到同一数字） |
| 它"高度裁剪优化、可作为最小预编译包" | **证伪（对我们的用途）**：UWP 构建，导入 `msvcp140_app`/`vcruntime140_app`，桌面 App 起不来（变体 G 实测） |
| 自定义 D3D11-only 构建 "1.5–2MB" | **未证实**：没有来源，只是把 UWP 包的数字外推；我估 2–3.5MB，同样是推断 |
| 官方 Flutter Windows 引擎静态链接 ANGLE，flutter_windows.dll 10–12MB | ANGLE 静态链接大体合理（本机 app 目录里确实没有 Flutter 自己的 libEGL，推断未逐符号验证）；**大小说错**：本机 release 的 flutter_windows.dll 是 21,273,088 字节 |
| "官方引擎没公开 EGL 符号所以 media_kit 必须自带" | 没有来源，未验证 |
| ANGLE D3D11 无 GPU 时**默认自动回退 WARP**，保持默认即可 | **与本场景不符**：就算 ANGLE 内部会回退，media_kit 在进 ANGLE 之前已经用 `D3D_DRIVER_TYPE_HARDWARE` 自己建 D3D11 设备，失败即抛异常；且 media_kit 的属性里没有 WARP device type（"Wrap" 属性集是 D3D11 默认的重复项）。agy 对 ANGLE 内部的说法我没有核实 |

## 8. 未验证项

- 没有 D3D11 能力的机器（真 VM、无 GPU 的 RDP、旧显卡）上的实际表现；Windows 7/8、Win10 早期版本、Server Core 上 d3dcompiler_47 是否一定在系统目录。
- `--no-enable-impeller` 组合、第二台机器、其他显卡厂商（本机只有一块）。
- 修改过的 CMakeLists 真正重新 configure + build 一次（本次是手工删产物目录里的文件）。
- 微软 d3dcompiler_47 随系统分发的官方原文。

## 附：实验文件

`C:\Users\jelon\whep-win\angle-test\`：`base`/`A`–`G` 隔离 app 副本、`run.ps1`（启动+截屏）、`imports.py`（PE 导入表）、`logs/`、`shots/`（第二轮）、`run1/`（第一轮）。仓库里的临时文件 `mova/example/lib/main_angle_shrink_verify.dart` 已删除；`C:\Program Files\mova_example` 被我的验证构建覆盖（原来部署的是别的 demo 的构建）。
