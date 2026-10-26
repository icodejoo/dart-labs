# Windows 窗口最大化私有内存瞬间 +700 MiB：归因到 Flutter 引擎自带 ANGLE 的 MSAA 后备缓冲

日期：2026-10-25。机器：Windows 11 Pro 10.0.26100，RTX 4060 Laptop，工作区 2560x1600（最大化 client 2560x1521）。证据与脚本在 `D:\tmp\ev15\`（不入库）。"实测"为本机数据，"推断"单独标注。

## 结论（先看这里）

1. **这 700 MiB 以上不是 libmpv、不是 media_kit 插件、不是 media_kit 自带的 ANGLE（libEGL/libGLESv2），也不是 0007。** 调用栈全部落在 `flutter_windows.dll` 里（Flutter 引擎静态链接的另一份 ANGLE）：
   `Rasterizer::DrawToSurfaceUnsafe → EmbedderExternalViewEmbedder::SubmitFlutterView → CompositorOpenGL::CreateBackingStore → glRenderbufferStorageMultisample → ANGLE RenderbufferD3D::setStorageMultisample → Renderer11::createRenderTarget → ID3D11Device::CreateTexture2D → d3d11 → NVIDIA 驱动 → D3DKMTCreateAllocation`。
   即 Flutter Windows 合成器每建一个"后备缓冲"，就分配一对 4x MSAA 的 RGBA8 + D24S8（各 5120x3042 采样，约 59.4 MiB），最大化时在几秒内**建了 5 套**（实测 10 次大分配，594 MiB），外加 blit 用的 2560x1521 纹理约 130 MiB。
2. **触发条件是"画面里有较大面积的 LinearGradient"（再叠加窗口足够大），不是视频本身。** 同一份 Flutter 引擎，**纯 Flutter、无视频、无任何插件**，只要铺一层全屏渐变，同样涨 +530 MiB，栈相同。media_kit 默认的桌面控件（`MaterialDesktopVideoControls`）里恰好有两层全尺寸渐变 Container，所以"原版插件 + `Video(controller)` 默认控件"必现。
3. **mova 正式的播放器用 `controls: NoVideoControls`，只有顶/底两条小渐变条**，实测不触发（见下表，+167~250 MiB，峰值约 450~580 MiB）。这个现象对 mova 产品形态影响小；它主要影响"直接用 media_kit 默认控件的 demo/测试 app"。
4. 是**系统提交内存（驱动在用户态映射的显存备份/系统内存）**，不是显存：最大化时 `nvidia-smi` 全卡显存只多 85~90 MiB，私有内存却 +700~800 MiB。
5. 我们可控的缓解：**不要在视频上放全屏渐变**（用 `NoVideoControls`、小面积渐变条、纯色半透明、或预渲染 1xN 位图代替渐变）。引擎/ANGLE/驱动内部的"为什么一次建 5 套、为什么延迟约 3 秒才释放"我没查清，列在上报要点里。

## 1. 每次最大化是否都涨、还原是否回落、5 次是否有残留（0007 DLL，默认控件，WHEP 720p30）

`libmpv-2.dll` 与 `D:\tmp\mpv0007\libmpv-2.dll` 的 md5 相同（`b0828c63...`），即 0007 基线。起播 14s 后，`ShowWindow(SW_MAXIMIZE)` / `SW_RESTORE` 各 5 次，100ms 采样 `PrivateMemorySize64`：

| 轮 | 最大化峰值 MiB | 最大化 13s 后稳态 | 还原后 | 相对起始 |
|---|---|---|---|---|
| 起始 | - | - | 339 | - |
| 1 | 1142 | 434 | 352 | +13 |
| 2 | 1144 | 436 | 350 | +11 |
| 3 | 1141 | 437 | 352 | +14 |
| 4 | 1144 | 435 | 354 | +15 |
| 5 | 1145 | 438 | 355 | +16 |

- **每次都涨，幅度稳定**（峰值 1141~1145，+800 MiB）。
- 时间形态（100ms 采样）：最大化后 100ms 内 356 → 1029（+670），保持约 3 秒，再阶梯回落 1029 → 672 → 440（每级约 3 秒），**最大化状态下就已回落到比起始高 ~100 MiB 的稳态**；还原后回到起始附近。
- **还原后基本回落**，5 轮只多 +3 MiB 左右（+13 → +16，每轮 +1~2 MiB 的缓爬，样本太少，不能下结论是泄漏，需要更多轮次或长跑才能判断）。稳态（最大化中）比起始高 ~100 MiB 是 2560x1521 的一套常驻后备缓冲，属正常。
- `mova` 形态（NoVideoControls + ClipRect + Transform.scale）同样 5 轮：峰值 502~505，稳态 422，还原后 339~342（起始 336，+2~+5）。

## 2. 最大化窗口内的大块分配归因

### 方法与弯路

- 先按旧笔记的方法在 `NtAllocateVirtualMemory` / `NtAllocateVirtualMemoryEx` 下条件断点（RegionSize ≥ 1 MiB）：**整个最大化过程只命中 3 次**。说明这些内存**不是用户态 VirtualAlloc 申请的**。
- `VirtualQueryEx` 快照对比（`D:\tmp\ev15\vq.py`）：最大化后 0.7s 内多出 700 MiB 的 `MEM_PRIVATE` 区域，块大小集中为 60.0 MiB x8、20 MiB x4、15.0 MiB x5 等；60 MiB = 2560x1521 的 4x MSAA（5120x3042x4B 的 RGBA8），15 MiB = 2560x1536x4B。这提示是驱动/内核把显存分配对应的系统内存映射进进程。
- 改在 `win32u!NtGdiDdDDICreateAllocation`（D3DKMT 建分配）下断点，读 NVIDIA 的私有驱动数据（宽/高/采样数，实测字段位置，格式按 4B/像素估），并用 `k 70` 取栈；Flutter 引擎的符号用匹配的 `flutter_windows.dll.pdb`（Flutter 3.47.1 release 缓存里自带，GUID 一致，已按符号服务器目录布局放进 `D:\tmp\ev15\sym\`）。

### 最大化窗口内 `CreateAllocation` 汇总（默认控件，估算 895 MiB，实测私有内存峰值 +800 MiB）

| 次数 | 估算 | 尺寸/采样 | 引擎层调用链（符号解析后） |
|---|---|---|---|
| 10 | 594.1 MiB | 5120x3042 / 4x | `CompositorOpenGL::CreateBackingStore → GL_RenderbufferStorageMultisample → RenderbufferD3D::setStorageMultisample` |
| 2 | 59.3 MiB | 3796x2048 / 4x | 同上（窗口动画中间尺寸 1898x1024 的一套） |
| 5+4 | 133.7 MiB | 2560x1521 / 1x | `GL_BlitFramebuffer → blitRenderbufferRect / TextureStorage11_2D::ensureTextureExists` |
| 其余 | ~100 MiB | 交换链、渐变纹理 4096x1024（16 MiB x2）等 | `EGL_CreateWindowSurface → SurfaceD3D::resetSwapChain` 等 |

- 栈里**没有** `libmpv`、`media_kit_video_plugin`、插件的 `libGLESv2.dll`；大块都经 `flutter_windows → d3d11 → nvwgf2umx`。
- 把握程度：归因到"Flutter 引擎 ANGLE 的合成器后备缓冲"，**高**（栈与尺寸对得上，且纯 Flutter 复现）。每次 +700 MiB 的字节数是"估算"（4B/像素假设 + 驱动私有数据里的宽高采样字段，没有拿到驱动对分配大小的官方值），与 VirtualQueryEx 的实测增量（700 MiB 新增）吻合。
- 不含的部分：没有对"释放"计数，所以回落是靠内存曲线看，不是靠 `DestroyAllocation` 对账。

## 3. 对照实验

### 3.1 控件/组件对照（2560x1521 一次变尺寸，起始 1000x700；"增量"= 峰值 - 起始）

| 配置 | 增量 MiB | 稳态增量 |
|---|---|---|
| 原版 `Video(controller)` 默认控件，WHEP | +806 | +146 |
| 同上，本地 mp4（`D:\tmp\win2\media\clip.mp4`） | +806 | +144 |
| 同上，**不播放**（Player 已建，没 open） | +731 | 约 +590（无重绘，不回落） |
| 只建 `Player + VideoController`，**界面不放 Video 控件** | +168 | +134 |
| 完全不初始化 media_kit（纯 Flutter 转圈） | +162 | +130 |
| `Video(controls: NoVideoControls)` | +170 | +138 |
| 仅 `Texture(textureId)` | +172 | +137 |
| mova 形态：ColoredBox + ClipRect + Transform.scale + NoVideoControls | +167 | +135 |
| mova 形态 + 顶/底 64px 渐变条 | +250 | +189 |
| 同上，条改纯色半透明 / 改 1x64 预渲染位图 | +168 / +167 | +134 / +136 |
| 同上，渐变条外包 RepaintBoundary | +245 | +182 |
| **纯 Flutter + 全屏渐变层（无视频无插件）** | **+530** | +428 |
| 纯 Flutter + 全屏渐变层 + `Opacity` / `AnimatedOpacity` / `RepaintBoundary` | +531 / +530 / +530 | 约 +420 |
| 纯 Flutter + 全屏纯色半透明 | +169 | +135 |
| 纯 Flutter + 底部 80px 渐变条 | +229 | +174 |

结论：**触发的是全屏渐变，与是否有视频、本地文件还是 WHEP、libmpv 版本无关**；Opacity 与 RepaintBoundary 都不能挡。没有视频（纯 Flutter）也能复现，直接排除 libmpv、mpv 选项、media_kit 插件的 ANGLE。`mova` 的小渐变条只带来约 +80 MiB 的额外开销。

### 3.2 尺寸线性吗（默认控件、WHEP、每次从 1000x700 起）

- 一直到 2300x1300，增量近似随面积线性增长：1280x720 +45、1920x1080 +94、2048x1152 +100、2200x1240 +119、2300x1300 +131。
- 到一定高度后**突变**到 +530~+810：同一进程内宽 2560，高 1470 以下 +161~+178，高 1490 以上 +802~+810（升序、降序各测一遍，阈值一致）。
- **阈值不稳定**：更早的两次会话里，2400x1360、2560x1440、1920x1440、1000x1400 也触发过，之后同样的尺寸全新进程里不触发。我没有找到阈值漂移的原因（推断：与同时在飞的帧数/驱动延迟释放有关，未证实）。所以"超过某个高度就涨"只当现象，不能当规律；稳定可靠的只有"2560x1521（最大化）必现"。
- 宽度本身不是触发项：2560x720、2564x1360 都没触发。

## 4. 缓解方案（临时环境验证，未入库）

| 方案 | 效果（2560x1521） | 备注 |
|---|---|---|
| `Video(controls: NoVideoControls)` | +806 → +170 | mova 播放器已用 |
| 顶/底小渐变条（mova 现状，64px） | +250，稳态 +189 | 可接受 |
| 渐变条改半透明纯色，或预渲染 1xN 位图再拉伸 | +168 | 最省，视觉略有差别 |
| 保留 media_kit 默认控件 | +806 | 不推荐；该控件两层全尺寸渐变，无参数可关底层渐变（`bottomButtonBar` 非空就会画），没单独验证"清空 topButtonBar 能否部分缓解" |
| 引擎开关（`FLUTTER_ENGINE_SWITCHES=enable-impeller=false`） | 无效 | release 引擎不读环境开关，日志仍是 Impeller OpenGLES |
| 改 mpv 选项 / 换 ANGLE / 0007 | 无关 | 栈里没有这些层 |

不入库、不动 mova 代码。建议 mova 侧保持"不在视频上放全屏渐变"的约束（皮肤里有全屏渐变时先验证内存）。

## 5. 向 Flutter / ANGLE / NVIDIA 上报要点（若要报）

- 现象：Flutter 3.47.1 Windows release，Impeller OpenGLES（经引擎内嵌 ANGLE → D3D11），一帧里有全屏 LinearGradient 时，窗口从 1000x700 变到 2560x1521，私有内存 +530 MiB（纯 Flutter 最小复现，`D:\tmp\pf_app`）；无渐变时 +160。
- 栈：`CompositorOpenGL::CreateBackingStore` 每套后备缓冲 = 4x MSAA RGBA8 + D24S8，各 5120x3042 采样（约 59.4 MiB x2）；最大化窗口内建了 5 套，约 3 秒后阶梯释放，不是单套常驻。
- 数据：私有内存 356 → 1029 MiB（100ms 内），3 秒后 672，再 3 秒后 440；`nvidia-smi` 全卡显存只 +85~90 MiB。
- 问题：为什么渐变会让合成器多建后备缓冲（待查：是 Impeller 对 GLES 渐变路径的帧内同步导致缓存未复用，还是 ANGLE/驱动延迟释放）；这套缓冲是否可以复用或限制数量。
- 我没验证的：是否 NVIDIA 专有（没有 AMD/Intel 对照）；Flutter 其他版本；Skia 后端。

## 未验证项 / 局限

- 阈值漂移原因没查；最大化触发"5 套"的内部机制没查（需要 Flutter 引擎侧日志或带符号的 Impeller 栈，已有引擎 PDB，可继续在 `CompositorOpenGL::CreateBackingStore` 调用点打条件计数）。
- 5 轮重复里的 +1~2 MiB/轮缓增没有长跑验证。
- 默认控件样例里鼠标是否悬停在窗口上（控件是否可见）没有控制；`AnimatedOpacity` 在 opacity 0 时的绘制行为我没有核实，所以"控件隐藏时是否仍触发"未确认。
- 只测了 NVIDIA 4060 Laptop，单显示器工作区 2560x1521；没有测 DPI 缩放变化、真全屏（非最大化）、多显示器。
- 没有测 mova 完整皮肤（只用了等价的小渐变条复刻）。

## 环境与清理

- 起的进程：MediaMTX 与 ffmpeg 已按 PID 结束；测试 app、cdb 均按 PID 结束，没有残留。
- 调试器用的是 `D:\tmp\dbgtools\x64\`（上次已装），新增 `D:\tmp\ev15\sym\`（含 251 MiB 的 Flutter 引擎 PDB，可删），新增 `D:\tmp\pf_app`（纯 Flutter 对照）、`D:\tmp\var_sw2`、`D:\tmp\var_sw3`（不同 UI 模式的构建，含 0007 DLL，不入库）。`D:\tmp\sw_app\lib\main.dart` 加了 `SW_UI` 模式开关（临时，非仓库）。
- 本次**没有改注册表**。顺带发现 `HKLM\...\Image File Execution Options` 根下有一个孤立的值 `USTEnabled = w14app.exe`，不是本次写入的（应是上次 gflags 试验的残留，`w14app.exe` 子键已不存在）；我没有动它，是否删除请你定。
- 仓库没有改动、没有提交、没有推送。
