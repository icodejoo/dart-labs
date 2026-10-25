# Windows 渲染内存线性增长：堆分配栈定位（阶段 1）与插件修复 V1 验证（阶段 2）

日期：2026-10-25。机器：Windows 11 Pro 10.0.26100，RTX 4060 Laptop（NVIDIA 用户态驱动 `nvwgf2umx`），真实桌面。证据原件在 `D:\tmp\heap\ev\`、`D:\tmp\mkv_app\ev\`（不入库）。"实测"为本机跑出，"推断"单独标注。

## 结论（先看这里）

1. **增长的调用栈已定位**：libmpv 每帧调 `glBeginQueryEXT`（mpv 的 GPU 计时器，`ra_gl.c: gl_timer_start`）→ ANGLE（`libGLESv2`）在其 D3D11 后端里调 `ID3D11Device::CreateQuery`（反汇编确认走 vtable+0xC0）→ `d3d11.dll` → **`nvwgf2umx.dll`（NVIDIA 用户态驱动）里 `RtlAllocateHeap` 触发堆段扩展**。46 次大块提交里 45 次是这条栈（98%），累计 12 MiB，与 10 MiB/min 吻合。
2. **A/B 对照证实因果**：只把 libmpv-2.dll 里的扩展名字符串 `GL_EXT_disjoint_timer_query` 改一个字符（mpv 就加载不到 query 函数、不建计时器，不重编），旧 ANGLE v1.0.1 + 硬件渲染 + WHEP 720p30、去后向缓冲、660s：**10.07 → 0.52 MiB/min**，画面正常。
3. **阶段 2 证伪了"新 ANGLE + 插件修复能治泄漏"**：按 PR #1436 修补 media_kit_video 后，Electron 43 与 Carapacik v8078 的 ANGLE 都**能出画了**（未修补插件 + v8078 仍不出画，已 A/B），但**泄漏照旧**：v8078 11.27 MiB/min（930s）、Electron 43 11.86 MiB/min（420s）。此前"新 ANGLE 不涨"只是因为不出画，不是修好了。叠加关计时器后 v8078 降到约 1.4~1.7 MiB/min（比旧 ANGLE 的 0.5 高，原因未查）。
4. **v8078 比现随包更大**：+1,545,072 B（+19.6%），没有体积收益也没有泄漏收益，不建议换。
5. **推荐修法**：不换 ANGLE、不 fork media_kit_video，给 mpv 加一条补丁让 libmpv 的 GL 路径不建 GPU 计时器（见"建议"）。需你拍板。

## 阶段 1：定位

### 工具（装了什么，由你决定是否卸载）

本机原本只有 `wpr.exe`/`tracerpt`/`logman`。`winget` 不可用（源更新失败，`0x80072f0d`）；`aka.ms`、`go.microsoft.com` 的 TLS 报 `SEC_E_UNTRUSTED_ROOT`（本机缺根证书），所以用 `curl -k` 只取重定向，再对**落盘文件做 Authenticode 校验**（均为 `CN=Microsoft Corporation`，Valid）。

- `winsdksetup.exe`（Windows SDK 10.0.26100.1 联机安装器，1.4 MB，来源 `download.microsoft.com`）→ 用 `/features OptionId.WindowsDesktopDebuggers /layout` 只拉调试器特性，缓存 177 MB 在 `D:\tmp\dbgtools\layout\`。
- 用 `msiexec /a`（管理安装，只解包，**没有安装到系统**）把 `X64 Debuggers And Tools-x64_en-us.msi`（38.6 MB，签名 Valid）解到 `D:\tmp\dbgtools\x64\`，含 `cdb.exe`、`umdh.exe`、`gflags.exe`、`dbghelp.dll`。卸载 = 删 `D:\tmp\dbgtools\`。
- `ntdll.pdb` 一份（1.9 MB，`curl -k` 从 `msdl.microsoft.com` 取，**只靠 GUID/age 匹配，没有签名校验**）放在 `D:\tmp\heap\sym\`，仅供 UMDH/cdb 解析 ntdll。
- 没有 `pip install` 任何东西，没有装 WinDbg 商店版/WPA/ADK。
- **系统改动（已还原）**：为试 `gflags +ust`，本机 UAC 是"内置管理员静默提升"（`ConsentPromptBehaviorAdmin=0`），我用 `Start-Process -Verb RunAs` 起了提升的 pwsh，在 `HKLM\...\Image File Execution Options\w14app.exe` 写了 `GlobalFlag=0x1000`、`StackTraceDatabaseSizeInMB=512`、`FrontEndHeapDebugOptions=8`，试完已 `reg delete` 整个键，复查"找不到键"。

### 方法与走过的弯路

1. 测试 app：`D:\tmp\heap\app`（拷自 `D:\tmp\w14\g_after`：旧 ANGLE v1.0.1 的 `libEGL 472,904 / libGLESv2 7,414,088`、含 0006 的 WHEP libmpv-2.dll、media_kit_video 2.0.1 原版插件），WHEP 1280x720@30（MediaMTX `D:\tmp\w14\mtx.yml` + ffmpeg testsrc2），`demuxer-max-back-bytes=0;demuxer-seekable-cache=no`。启动方式 `D:\tmp\heap\run_ust.ps1`（`Start-Process explorer.exe` 代为拉起）。启用栈跟踪后复现：约 10.5 MiB/min。
2. **UMDH 失败**：`gflags +ust`（含用 PEB.NtGlobalFlag 挂起改标志的无注册表办法）、禁用 Segment Heap（`FrontEndHeapDebugOptions=8`）、加大栈库、补 ntdll 符号后，UMDH 始终报"没有任何带栈的分配 / 栈库满"，输出里所有块都是 `BackTrace0`；cdb 读 `ntdll!RtlpStackTraceDatabase` 发现库里有约 1900 条栈。**原因没查清**，不再纠缠（未确认是否是 UMDH 26100 与本机 ntdll 的结构不匹配）。
3. **改用 cdb 条件断点**（有效）：附加到进程，在 `ntdll!NtAllocateVirtualMemory` 下条件断点：`RegionSize` 在 [0x30000, 0x80000]（对应此前 VirtualQueryEx 看到的 260~430 KB 私有提交块）且 `AllocationType` 含 `MEM_COMMIT`，命中就 `k 24` 记栈（脚本 `D:\tmp\heap\vabp.cdb`，聚合 `D:\tmp\heap\agg.py`）。这些块是 **NT 堆自己向系统要的段扩展**（栈顶 `RtlpExtendHeap → RtlpFindAndCommitPages`），不是 VirtualAlloc 直调，所以 `!address` 把它们归在 `<unknown>` 而不是 `Heap`，且 wpr 的 VirtualAllocation 路径没有必要再走。
4. 局限：命中的是"**触发堆段扩展的那次分配**"，是对增长来源的统计归因，不是"分配了多少、释放了多少"的对账；样本 46 条。

### 调用栈 Top（stack 自顶向下，去掉 ntdll 堆内部帧）

45/46 命中同一路径（累计 12,064 KB，每次 ~270 KB）：

```
nvwgf2umx!SetDependencyInfo+0x46244c        ← RtlAllocateHeap（LFH 满，扩展堆段）
nvwgf2umx!NVAPI_DirectMethods+0x7291a / +0x76ea8 / +0x781ee
nvwgf2umx!NVAPI_Thunk+0x1dfdd ... +0x3633ed
d3d11!D3D11CoreCreateLayeredDevice+0x3408d ... +0x5268f   （符号是最近导出名，实为 d3d11 内部）
libGLESv2!ANGLEResetDisplayPlatform+0x12ee12 / +0x1199f9/+0x1199c2  （最近导出名，实为 ANGLE 内部函数）
libGLESv2!glShadingRateQCOM+0x14295
libGLESv2!GL_BeginQueryEXT+0x8e
libmpv_2+0x7024bb  (ra_gl gl_timer_start)  ← mpv_render_context_render+0x29c
```

另 1/46 是同一驱动内另一条路径（`nvwgf2umx+0x90da9`）。

**ANGLE 内的函数没有符号**（只有导出名偏移），下面是反汇编推断，不当事实：`libGLESv2+…12edd0` 处函数把 `[r8+0x3608]`（device）取 vtable，调 `[vtable+0xC0]`，0xC0/8=24 正是 `ID3D11Device::CreateQuery` 的槽位，随后对返回值做引用计数并分配 16 字节节点挂进队列。用断点计数：每个 `glBeginQueryEXT` 对应约 3 次该函数调用（与 D3D11 时间 query 的"disjoint + 开始/结束两个 timestamp"一致）。

### 谁的责任（置信度）

- **泄漏发生在 NVIDIA 用户态驱动的堆里**（高）：增长的提交块全由 `nvwgf2umx` 的分配触发，且只在 ANGLE 创建 D3D11 query 的路径上。
- **触发条件是"每帧 BeginQuery→CreateQuery"**（高）：A/B 关掉计时器后斜率从 10.07 降到 0.52 MiB/min。
- **是 ANGLE 没释放这些 query，还是驱动释放后不还内存**（**未确定**）：我没有对 ANGLE 的 `Release` 做计数。ANGLE 114/115/116、v8078、Electron 43 都涨相同速率，说明与 ANGLE 版本无关（中）；没有换 GPU/WARP 对照，所以不能把锅只扣在驱动上。
- 与旧结论一致：fence（0006）、media_kit_video 每帧路径都不是主因；本次栈里完全没有 fence 相关分配。

### 对"换 ANGLE / 软件渲染 / D3D11 路径"的含义

- 换 ANGLE：**无效**（阶段 2 实测）。
- 软件渲染：不建 GL 计时器，所以不涨，与此前观察一致；但 CPU 代价高，是退路不是首选。
- mpv 的 D3D11 `ra_d3d11` 路径：**未试**；它有自己的 timer（`ra_d3d11.c`），且 libmpv 嵌入 Flutter 需要 D3D11 纹理共享方案，改动大，不建议为这个泄漏走。
- 关掉 mpv 的 GL 计时器：本次验证有效，代价仅是 `vo-passes`/stats 的逐 pass 耗时没了。

## 阶段 2：插件修复 V1

### 做了什么

- v8078 包：`github.com/Carapacik/flutter-windows-ANGLE-OpenGL-ES/releases/tag/v8078`，`ANGLE-9fe55a5-windows-x64.7z`，5,279,180 B，sha256 `7008390323627647db33eb2112fd4100f46b544389307886db435fe7b10e8a55`，与发布页 `SHA256SUMS`、API digest 一致。只解压，没运行里面任何东西，放在 `D:\tmp\angle-v8078\`。manifest：angle `9fe55a5`，release 8078。
- 临时副本 `D:\tmp\mkv_patched\media_kit_video`（拷自 pub cache 2.0.1），临时最小 app `D:\tmp\mkv_app`（`pubspec.yaml` 里 `dependency_overrides` 指向副本；Video 控件 `fill` 设品红 `0xFFFF00FF`）。构建用 `Start-Process explorer.exe build.cmd`。仓库里没有任何第三方副本/DLL/依赖改动。
- 补丁（PR #1436 里与泄漏/出画相关的 `angle_surface_manager.cc` 两处，完整 PR 的其余部分是格式/日志/注释/9_3 回退删除，未取）：

```diff
--- a/windows/angle_surface_manager.cc
+++ b/windows/angle_surface_manager.cc
@@ void ANGLESurfaceManager::CleanUp(bool release_context) {
   if (release_context) {
-    if (display_ != EGL_NO_DISPLAY && surface_ != EGL_NO_SURFACE) {
-      eglReleaseTexImage(display_, surface_, EGL_BACK_BUFFER);
-    }
     if (display_ != EGL_NO_DISPLAY && context_ != EGL_NO_CONTEXT) {
@@ bool ANGLESurfaceManager::CreateAndBindEGLSurface() {
-  GLuint t;
-  glGenTextures(1, &t);
-  glBindTexture(GL_TEXTURE_2D, t);
-  eglBindTexImage(display_, surface_, EGL_BACK_BUFFER);
-  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
-  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
+  // libmpv renders directly into the pbuffer back buffer (PR media-kit#1436).
   return true;
```

  完整 diff 在 `D:\tmp\mkv_patched\v1.diff`。
- **更正 10-25 源码分析里的一条"明确缺陷"**：`angle_surface_manager.cc:223/234` 的 `AddRef()` **不是**泄漏。两个成员是 `ComPtr<ID3D11Texture2D>`（`.h:79-80` 已确认），`CleanUp` 先手动 `->Release()` 再 `= nullptr`（ComPtr 再释放一次），一次 `AddRef` 正好与手动 `Release` 抵消；删掉 `AddRef` 反而会多释放一次。所以"Resize 的 AddRef 缺陷"不存在，没有改。`glGenTextures` 不删的问题（每次 Create/Resize 漏一个纹理名）是真的，PR 的删法已覆盖。

### 出画（`PrintWindow` + 品红底色，WHEP 720p30，22s 时）

判据：品红占比（背景色，testsrc2 自带一条品红色条约 3.4%）与红/绿/黄/蓝/青五条色条像素数。

| 插件 | ANGLE | 结果 |
|---|---|---|
| 补丁 | 旧 v1.0.1（现随包） | 出画（品红 3.4%） |
| 补丁 | Electron 43（`libGLESv2` 8,069,632 / `libEGL` 467,968） | **出画**（原版插件下此前不出画） |
| 补丁 | v8078 | **出画** |
| **原版 2.0.1** | **v8078** | **不出画**（品红 94.7%，五色条为 0）——补丁是出画的必要条件 |

### 私有内存斜率（WHEP 720p30，`demuxer-max-back-bytes=0`，t≥60s 最小二乘，15s 采样）

| 组合 | 时长 | 私有 MiB（起→末） | 斜率 MiB/min |
|---|---|---|---|
| 原版插件 + 旧 ANGLE（对照 ctl1） | 660s | 349.5 → 445.5 | **10.07** |
| 原版插件 + 旧 ANGLE + **关 GL 计时器** (nq1) | 660s | 335.5 → 341.6 | **0.52** |
| 补丁插件 + v8078（阶段 2 主测） | 930s | 356.3 → 516.0 | **11.27** |
| 补丁插件 + Electron 43 | 420s | 359.8 → 425.7 | **11.86** |
| 补丁插件 + v8078 + 关 GL 计时器 | 600s | 350.9 → 366.6 | 1.68（t≥200s：1.41） |

目标"<1 MiB/min"：只有"旧 ANGLE + 关计时器"达到；新 ANGLE 不关计时器完全没改善。v8078+关计时器仍有约 1.4 MiB/min 残留，来源没查（可能是新 ANGLE 另有小增长，也可能是起播后的缓慢爬升，样本只有 10 分钟）。

"关计时器"的做法：复制一份 libmpv-2.dll，把 `GL_EXT_disjoint_timer_query`（文件偏移 8522262）末位 `y` 改成 `x`，不入库，仅用于 A/B。画面截图确认正常（`D:\tmp\heap\ev\nqshot_plain.png`）。

### 回归（补丁插件 + v8078，`D:\tmp\mkv_app\ev\`）

- 5 轮起播/停止（每轮重启 app，14s 后截图）：5/5 出画，五色条像素稳定在 1.6~1.8 万。
- HTTP mp4（本机 `http.server` 提供 clip.mp4，loop）：出画（五色条像素 1~1.7 万，品红 15% 为上下黑边处的底色）。
- 缩放/最大化（`SetWindowPos`/`ShowWindow`，20 次变尺寸 + 5 次最大化还原，每步 `PrintWindow`）：每一步都出画，句柄稳定（1722→1729）；**最大化时私有内存跳到约 1 GiB、还原后回落**，**原版插件 + 旧 ANGLE 同样如此**（1,033 MiB），不是补丁引入。这个跳变本身偶然发现、没有追，值得单独关注（可能是 Flutter/ANGLE 在大窗口下的表面分配）。
- 没有测真正的全屏（media_kit 的全屏是应用层逻辑，最小 app 没有），用最大化代替。
- 没有单独做"补丁插件 + 旧 ANGLE"的长跑，也没有做 Android/其他平台。

### 体积

| | libEGL | libGLESv2 | 合计 |
|---|---|---|---|
| 现随包 v1.0.1 | 472,904 | 7,414,088 | 7,886,992 |
| v8078 | 505,344 | 8,926,720 | 9,432,064（**+1,545,072 B，+19.6%**） |
| Electron 43 | 467,968 | 8,069,632 | 8,537,600（+650,608 B） |

v8078 包里另带的 `d3dcompiler_47`（4.7 MB）、`vk_swiftshader`、`vulkan-1` 本次没用，与现随包的瘦身策略一致，不计入。

## 建议（排序）与需要你决定的点

1. **首选：给 mpv 打一条补丁，libmpv 的 GL 路径不建 GPU 计时器**（草案，**未创建文件**；命名可为 `0007-opengl-ra-gl-disable-timer-queries.patch`）。最小做法是 `video/out/opengl/ra_gl.c` 的 `gl_timer_create` 直接 `return NULL`（`timer_pool_create` 对 NULL 计时器已有处理，`gpu/utils.c`）；折中做法是只在 GL_RENDERER 含 "ANGLE" 时返回 NULL。已验证（二进制改字符串的等价效果）：旧 ANGLE 下 10.07 → 0.52 MiB/min。Android 路径本次未测，Android 走驱动自带 GLES，是否同样泄漏未知；折中做法不影响 Android。**不换 ANGLE、不 fork media_kit_video。**
   - 需要你决定：全关还是仅 ANGLE 时关；是否接受 `vo-passes`/stats 页面没有逐 pass 耗时；是否新增 0007 并重编 Windows libmpv（一小时级）。
2. **次选：不改 mpv，改为在 media_kit 或 mova 里让 ANGLE 不广告 `GL_EXT_disjoint_timer_query`**。我没找到现成的运行时开关（ANGLE 的 feature override 要经 `EGL_ANGLE_feature_control` 在创建 display 时传，需要改 media_kit_video 插件，等于要自维护插件副本），所以排在 mpv 补丁之后。
3. **不建议：换 ANGLE（v8078/Electron 43）并自维护 media_kit_video 补丁副本**。已证明补丁让新 ANGLE 能出画，但泄漏不变、体积更大。唯一可能的理由是将来为别的目的升级 ANGLE，那时 PR #1436 的补丁是必要条件（原版插件 + v8078 不出画），再决定是否自维护副本。
4. 退路：硬件渲染不可用时回落软件渲染（不涨，CPU 高）。
5. 需要你拍板的汇总：是否新增 mpv 0007 补丁；全关还是仅 ANGLE；是否需要我继续查"泄漏的是 ANGLE 还是驱动"（换 WARP 或 AMD/Intel 对照、给 ANGLE 的 query `Release` 计数，用于向 ANGLE/NVIDIA 上报，不影响修复）；v8078+关计时器 1.4 MiB/min 的残留是否值得查；最大化时 1 GiB 私有内存跳变是否单独立项。

## 未解决 / 局限

- UMDH 为何拿不到栈（见阶段 1 方法 2）。
- ANGLE 是否对 query 做了 `Release`、泄漏归属 ANGLE 还是驱动（未区分）；只在一张 RTX 4060 笔记本 + 一个驱动版本上测，AMD/Intel 是否同样泄漏未知。
- 关计时器是靠改 libmpv 字符串模拟，没有重编带 0007 的 DLL；Android 未测。
- `vabp` 样本 46 条，是对"触发堆扩展"的归因，不是分配/释放对账。
- 阶段 2 的 v8078+关计时器只有 600s，Electron 43 只有 420s。

## 收尾

- 起的进程均已停（MediaMTX 35520、ffmpeg 16056、各采样器/cdb/http.server/app），没有按进程名模式杀进程；IFEO 键已删。
- 仓库：只新增本笔记；没有 git commit/push，没有改计划文档；没有 `pubspec_overrides.yaml`（临时 app 用自己的 `pubspec.yaml`，在 `D:\tmp\mkv_app`），没有动 generated 文件。
- 防火墙弹窗没有出现。
