# Windows ANGLE 渲染内存泄漏：网络调研

日期：2026-10-25。只读调研，未改仓库、未安装依赖、未跑桌面程序。用 gh/curl 查 GitHub 与 pub.dev。"事实"为链接可核对的内容，"推断/假设"为我的推理，未验证。背景见 `2026-10-24-windows-render-memory-growth.md`、`2026-10-24-angle-replacement-verify.md`、`2026-10-24-angle-source-candidates.md`。

## 结论先行

1. **没找到任何 media-kit 或 ANGLE 上游对"ANGLE 渲染路径每分钟约 10 MiB 原生泄漏"的官方确认或修复**。media-kit 仓库里 Windows 内存类 issue（#1278、#549、#776、#857）都是"反映内存涨、没定位"，结论多是 mpv 缓冲或 ffmpeg 问题。不是已知并已修的 bug，我们的 15 分钟对照实验比上游已有信息细得多。
2. **最有价值的发现：media-kit 开着一个 PR #1436（2026-08-02 创建，仍 OPEN，作者 Carapacik）**，把 Windows ANGLE 换成 `chromium/8078` 并同步改了 media_kit_video 的 C++。改动里**删掉了 `glGenTextures + eglBindTexImage` 和 `eglReleaseTexImage`**（"生产端未使用的 GL 纹理"，libmpv 直接渲染进 pbuffer）。这与我们的"117+ 不出画"现象高度相关（假设，见下）。
3. **mpv 上游 2026-10-15 合并了 D3D11 render API（PR #17764）**，可让嵌入方直接渲染进应用自己的 `ID3D11Texture2D`，彻底绕开 ANGLE。刚合并，没有发布版，media-kit 尚未接入。这是长期正解。
4. mpv 2026-10-14 提交 `40c998a1ca` 修了 `hwdec_d3d11egl` 里 FFmpeg 硬件设备引用不释放（"设备在 render-context 销毁后仍存活"）。这是 ANGLE 路径里的真实泄漏，但泄漏的是**设备对象，且只在 render context 销毁时才体现**，不太可能解释持续线性增长（推断）。

## 线索表

| # | 线索 | 时间 | 结论 | 可信度 | 适用于我们吗 | 下一步验证 |
|---|---|---|---|---|---|---|
| 1 | [media-kit PR #1436](https://github.com/media-kit/media-kit/pull/1436) 更新 ANGLE 到 chromium/8078（x64+ARM64）、libmpv 到 0.41.0 构建（release 20261023）；删除 `GLuint t; glGenTextures; eglBindTexImage; glTexParameteri` 以及 `CleanUp` 里的 `eglReleaseTexImage`；删 D3D9 与 9_x 回退；`SwapBuffers` 改名 `FinishRendering`（仍是 `glFinish`） | 创建 2026-08-02，OPEN，无评论 | PR 作者自述"Validated with local rendering tests"，**未提及内存泄漏**。diff 我读过（`gh pr diff 1436`），与描述一致 | 单人 PR 自述，未合并，非官方确认 | **高度相关**。我们的 117+ 失败现象（EGL 扩展广告、pbuffer/context 创建成功，但 `mpv_render_context_render() not being called or stuck`、Video 区透明）与"新 ANGLE + 旧 plugin 的 eglBindTexImage 路径"吻合。**假设**：旧版 plugin 的 `eglBindTexImage` 在新 ANGLE 上失败/改变状态导致渲染线程卡住，PR 去掉它后就能出画。这是推断，未验证 | 见"验证清单 V1"：本地 fork 一份 media_kit_video 2.0.1 的 windows/，仅删 `angle_surface_manager.cc` 里 bind 那几行 + `eglReleaseTexImage`，换 117+（先用已测过的 Electron 43 DLL）看是否出画、是否还涨 |
| 2 | [Carapacik/flutter-windows-ANGLE-OpenGL-ES release v8078](https://github.com/Carapacik/flutter-windows-ANGLE-OpenGL-ES/releases/tag/v8078)（x64 5.0 MiB / arm64 8.7 MiB 的 7z，有 SHA256SUMS）；对应上游 PR [alexmercerind/flutter-windows-ANGLE-OpenGL-ES#9](https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/pull/9) | v8078 发布 2026-10-22；PR OPEN | PR 描述："Fix EGL resource cleanup, resize synchronization, and texture lifetime during asynchronous Flutter unregistration"，ANGLE 版本 chromium/8078 rev 9fe55a5。**直接给出了我们一直找的"可拿到的新版 ANGLE 小包"**（比从 Electron 抠 DLL 干净，且是 media-kit 生态原生格式，含 7z 包与校验和） | 单人 fork，未合并，非官方。但体积小、有 CI 与校验 | 适用（候选替换物）。注意它是第三方 fork，供应链需自己审 | V2：下载 x64 7z（用 aria2），核对 SHA256，只读检查 PE（时间戳、导出），在隔离目录中展开，**配合 V1 的 plugin 改动**一起测。v1.1.0（2026-09-26）也是同一 fork 的 release，版本较旧，可作为二分对照 |
| 3 | [alexmercerind/flutter-windows-ANGLE-OpenGL-ES](https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES) 官方仓库 | 最新 release v1.0.1（2024-09-28）；issue 1~4 全部 closed，无任何内存/泄漏 issue | 官方仓库没有更新 ANGLE 版本，也没有关于 117+ 的任何记录 | 事实（核对 releases/issues 列表） | 官方路径没有现成修复，只能走 PR #9 或我们自建 | 无需验证 |
| 4 | media-kit issue [#1278](https://github.com/media-kit/media-kit/issues/1278)（Windows 内存/CPU 异常高），维护者回复链 | 2025-09 ~ 2026-05 | alexmercerind 2025-10-06 确认：Windows 回落 `-copy` hwdec，因为 ANGLE 的 GL 实现不支持全部特性，"最好的解法是让 mpv 接收 D3D11 纹理"；srix55："有个很讨厌的 bug 在逐步泄漏内存，花了几周没找到"；Predidit：2026-05-03 说他的分支有 Windows 零拷贝实现，但依赖 out-of-tree mpv 补丁，等 mpv PR #17764 | 维护者官方陈述（回落 copy、方案是 D3D11 直出）+ 一条他人"也遇到泄漏"评论（仅一条评论） | 部分适用：srix55 的现象与我们相同但没有任何数据；维护者**没有承认 ANGLE 泄漏**，把它当作性能问题 | 无 |
| 5 | media-kit issue [#296](https://github.com/media-kit/media-kit/issues/296)（Windows 直接 D3D11 渲染的增强请求） | 2023-07 创建，OPEN | 计划方向就是绕开 ANGLE。2025-06 有人用 `vo:'gpu'+hwdec:'d3d11va'` 能降 CPU，但视频出在独立窗口，不能嵌入 | 官方（维护者开的 issue） | 说明"换 vo"这条 workaround 不可行：独立窗口，与 Flutter 纹理无关 | 不建议验证 |
| 6 | [mpv PR #17764 "libmpv: add D3D11 render API backend"](https://github.com/mpv-player/mpv/pull/17764)（kasper93，已合并） | 合并 2026-10-15 | 新增 `MPV_RENDER_API_TYPE_D3D11`、`render_d3d11.h`，嵌入方提供 `ID3D11Device` 与每帧目标 `ID3D11Texture2D`，交换链与呈现完全在调用方。`MPV_CLIENT_API_VERSION` 升至 2.6 | 官方（上游 mpv 已合并） | **完全绕开 ANGLE，也就绕开泄漏**。但需要：(a) 含此提交的 libmpv 构建（最新 release v0.41.0 为 2025-12-21，**不含**，需用 master 构建）；(b) media-kit 的 C++ 插件改成 D3D11 直出（Flutter 侧 `FlutterDesktopGpuSurfaceDescriptor` 已用 D3D11 shared handle，较易接） | V4（评估项，非立即验证）：确认我们的 mova-libmpv CI 能否用 master 构建并含 `render_d3d11.h`；Dart 侧 FFI 绑定需新增该 API 参数结构 |
| 7 | mpv commit [40c998a1ca "hwdec_d3d11egl: release the FFmpeg hardware device reference"](https://github.com/mpv-player/mpv/commit/40c998a1ca) | 2026-10-14 | `init()` 把 ANGLE 的 D3D11 device 包进 `AVBufferRef`，移除 hwdec 条目时没释放引用，设备在 render-context 销毁后仍存活 | 官方（上游提交信息） | **弱适用**：我们是持续线性增长而非"销毁时才漏"，且 `d3d11va-copy` 路径不一定走 d3d11egl 互操作。不作主因 | V5（低优先）：看我们 libmpv 构建是否已含此提交；如含则无需操作 |
| 8 | mpv commit [1d15686142 "hwdec_d3d11egl: fix EGL_EXT_device_query availability check"](https://github.com/mpv-player/mpv/commit/1d15686142) | 2026-07-31 | 新 ANGLE（commit 56663dbfa780 之后）把 `EGL_EXT_device_query` 从 display 扩展串挪到 client 扩展串，旧检查永远失败，导致原生 d3d11va 互操作被静默关闭 | 官方（提交信息） | **对"新 ANGLE 换进旧 libmpv"有影响**：能出画，但 hwdec 互操作静默失效（回落 copy）。若我们升级 ANGLE，libmpv 也要含此提交，否则性能下降（非功能故障）。与我们"117+ 不出画"无关（是 hwdec，不是渲染） | 升级 ANGLE 后看 mpv 日志是否仍选 `d3d11va-copy` |
| 9 | [libmpv-win32-video-cmake PR #14](https://github.com/media-kit/libmpv-win32-video-cmake/pull/14)（同作者）与 [Carapacik/libmpv-win32-video-cmake release 20261023](https://github.com/Carapacik/libmpv-win32-video-cmake/releases/tag/20261023) | 2026-10-23 | 同步 shinchiro 构建，mpv 0.41.0 + FFmpeg 9.0.2，带上述两个 ANGLE 修复；x86/x64/x64-v3/arm64 | 单人 PR，OPEN | 只作对照参考：我们自有 mova-libmpv 流水线，不直接用它的 libmpv | 可对比其 mpv 提交点是否包含 #7、#8 |
| 10 | media-kit `main` 最近提交：`fix: memory leaks (#1446)`（2026-08-30，改 `media_native.dart`/`real.dart`/`android_content_uri_provider.dart`）；Windows 目录最后一次实质改动是 2025-10-04 `fix[windows]: run method call on main thread (#1274)` | 2026-08-30 | #1446 只改 Dart 侧 media/player，**不涉及 Windows 渲染**。pub.dev 最新仍是 media_kit_video 2.0.1、media_kit_libs_windows_video 1.0.11。**main 上没有渲染路径变化，也没有 Windows 泄漏修复** | 事实（`gh api` 提交列表） | 不适用：升级到 main 不会修我们的问题。我们用 2.0.1 已是最新发布 | 无 |
| 11 | media-kit [#1383](https://github.com/media-kit/media-kit/issues/1383)、[#1449](https://github.com/media-kit/media-kit/issues/1449)（Windows 多引擎卡死、dispose 后 COM 未初始化） | 2026-02、2026-09 | 都是 Windows 稳定性 bug，与持续泄漏无关 | 复现（issue 中带最小复现） | 不适用 | 无 |
| 12 | media-kit [#776](https://github.com/media-kit/media-kit/issues/776)（"memory leaks?"）里 sherlockvn/bdlukaa 指出 `VideoTexture` 部分对象未 dispose，已由 PR #823 修（Dart 侧 widget 泄漏） | 2024-05~06 | 是 Dart 侧开关视频时的泄漏，**不是我们这种稳态播放中线性增长**。我们已排除 Dart 堆 | 官方修复已合入 | 不适用 | 无 |
| 13 | media-kit [#549](https://github.com/media-kit/media-kit/issues/549) 等：直播流内存涨、`bufferSize` 文档单位错误 | 2023-11 | mpv 解复用缓冲导致，设小 `demuxer-max-*` 可压住 | 多人复现 | 对应我们已识别的"6~7 MiB/min 后向缓冲"那一半，已有结论 | 无 |
| 14 | fvp（libmdk，作者 wang-bin）：[pub.dev/packages/fvp](https://pub.dev/packages/fvp) 最新 0.39.1，文档称 Windows 默认 D3D11 渲染器，支持 x64/arm64 | 2026 | 不经 ANGLE。issue #549 里有用户从 media_kit 迁到 fvp 解决 RTSP 内存涨。**mdk SDK 是闭源二进制**（fvp 本身 BSD-3，mdk-sdk 许可需另核，我没查到确切条款） | fvp 许可证为事实；mdk 许可/体积/功能未核 | 作为"换播放内核"的备选：成本大（我们依赖 mpv 的 WHEP 补丁、`loadfile` 选项、音轨等，换内核等于重写 kernel 层），**不推荐** | 无，除非用户决定放弃 libmpv |
| 15 | 关于"Chromium 117 起 ANGLE 对 D3D11 share handle/keyed mutex 行为变化"的上游记录 | - | **没搜到任何公开记录证明 117 改了 share handle 行为**。WebSearch 只返回旧版 ANGLE 扩展文档。**不能当事实** | 无证据 | 我们对 117+ 失败的原因目前只有假设（见线索 1） | V1 的 A/B 即可验证，不必再翻上游 |

## 117+ 不出画的假设（未验证）

旧 plugin 在 `CreateAndBindEGLSurface` 里：`eglCreatePbufferFromClientBuffer(... EGL_TEXTURE_TARGET=2D, EGL_TEXTURE_FORMAT=RGBA)` 之后，`glGenTextures` + `glBindTexture` + `eglBindTexImage(surface_)`，`Draw()` 里 MakeCurrent、mpv 渲染到默认帧缓冲、`glFinish`。也就是**同一个 pbuffer 既是当前绘制表面，又被 bind 成纹理**。较新的 ANGLE 对这种用法校验更严或行为不同，是合理猜测；PR #1436 作者把这段删掉并在 8078 上跑通，间接支持，但他没说明这是出画修复的原因。源码位置：`media_kit_video-2.0.1/windows/angle_surface_manager.cc`（pub cache：`C:\Users\Administrator\AppData\Local\Pub\Cache\hosted\pub.dev\media_kit_video-2.0.1`）。

另一个可能是 `mpv_render_context_render() not being called or stuck` 来自渲染线程在 `Draw` 里卡住（`WaitForSingleObject` / EGL 调用失败后未返回）。需要日志确认，见 V1 的观察点。

## 方案排序

| 排名 | 方案 | 工作量 | 风险 | 新增依赖 | 说明 |
|---|---|---|---|---|---|
| 1 | **A. 本地覆盖 media_kit_video 的 windows/ C++（仅按 PR #1436 删 bind/release 几行），再换新 ANGLE（PR #9 的 v8078 包，或 Electron 43 的 DLL）** | 小到中：先做 A/B 验证约半天；定型要 vendoring plugin（可用 `dependency_overrides` 指本地路径，或 git fork）+ 改 CMake 取新 ANGLE | 中：新 ANGLE 需实机覆盖多种 GPU；`hwdec` 互操作可能静默失效（线索 8）；plugin 要自己维护。第三方 ANGLE fork 需审查（Electron 官方 zip 来源更正统） | 不新增 pub 依赖；新增"自维护 plugin fork"与一个 ANGLE 二进制来源（**需要你同意**） | 最小改动、最可能一次解决泄漏（前提：新 ANGLE 确实不泄漏，我们 2026-10-24 笔记已实测 2025-08/2026-03 构建 15 分钟平坦）。关键未验证点是线索 1 的假设 |
| 2 | **B. 等 media-kit 合并 #1436 或直接引用 Carapacik 的 PR 分支** | 小（改 pubspec 指向 git 分支 + 验证） | 中高：未合并、单人维护、变更面巨大（diff 55 万字符，混有格式化与大量无关文件），与我们 libmpv/Flutter 3.47.1 的兼容未知 | 引入 git 依赖（**需你同意**） | 比 A 省 vendoring，但无法只取 C++ 小改动，风险偏大。建议只把它当参考实现，不直接依赖 |
| 3 | **C. 长期：接入 mpv D3D11 render API（#17764）** | 大：mova-libmpv 要用 master 构建；media-kit 的 C++ plugin 要新写 D3D11 渲染后端；Dart FFI 新增参数 | 中高：API 刚合并未发布；同时要自己维护 plugin；但彻底去掉 ANGLE，还能让 `d3d11va` 零拷贝，并且 ANGLE 的 7.9 MiB（我们已瘦身后的更少）也能删掉 | 不新增外部依赖，但把 plugin 维护权全部收到我们手里 | 方向最正，Predidit 分支（[Predidit/media-kit](https://github.com/Predidit/media-kit)，有"零拷贝"实现，依赖 out-of-tree 补丁）可参考。适合列入下一阶段，不是止血方案 |
| 4 | D. 软件渲染（`enableHardwareAcceleration:false`）作为兜底 | 极小（我们已实测约 0 MiB/min） | CPU 占用高、分辨率受 `SW_RENDERING_MAX_*` 限制 | 无 | 已知可用的**即时止血**，可按机型/场景作为开关 |
| 5 | E. 降低增速的小手段：关后向缓冲（`demuxer-max-back-bytes=0`，已定位那 6~7 MiB/min） | 极小 | 实时流无回看需求时无副作用 | 无 | 和 A/C 无关，建议无论如何都做 |
| 6 | F. 换 fvp/mdk 等其他内核 | 很大（重写 kernel 层，WHEP 补丁失效） | 高；mdk 闭源 | 新增依赖 | 不推荐 |

## 推荐的下一步验证清单（均不需要新依赖；V1/V2 需要在你同意后做，且要在无 CPU 采样的时段跑）

- **V1（最关键，约半天）**：复制 `media_kit_video-2.0.1/windows/` 到临时目录，只改 `angle_surface_manager.cc`：删掉 `CreateAndBindEGLSurface` 里 `GLuint t; glGenTextures...glTexParameteri` 五行与 `CleanUp` 里的 `eglReleaseTexImage`。用 `dependency_overrides` 指向该副本。
  - 观察 1：搭配已知会"不出画"的 Electron 43 DLL，看是否出画。
  - 观察 2：出画后跑 15 分钟，看私有内存斜率。
  - 观察 3：搭配旧 ANGLE（随包 2022-08）只改 plugin，看泄漏是否变化（用来判断泄漏在 bind 用法里，还是在旧 ANGLE 本体）。
- **V2**：用 aria2 取 [v8078 x64 7z](https://github.com/Carapacik/flutter-windows-ANGLE-OpenGL-ES/releases/tag/v8078)，核对 `SHA256SUMS`，在隔离目录展开，只读检查后与 V1 的 plugin 组合测。同时在 mpv 日志里看 `hwdec` 是否仍为 `d3d11va-copy`（线索 8）。
- **V3**：对 V1 的 plugin 副本再加最小日志（`eglGetError`、`Draw` 进出），定位 117+ 不出画是哪个 EGL 调用失败或线程卡在何处，然后可以反馈给 PR #1436 或 media-kit。
- **V4（评估，不动手）**：确认 mova-libmpv CI 能否出含 `render_d3d11.h` 的 libmpv（mpv master，2026-10-15 之后），评估方案 C 的 Dart FFI 与 C++ plugin 工作量。
- **V5**：核对我们现用 libmpv 的 mpv 提交点是否包含 `1d15686142` 与 `40c998a1ca`。

## 需要用户决定的点

1. 是否同意引入"自维护的 media_kit_video windows 插件副本（dependency_overrides 或 fork）"来做 V1 与方案 A。
2. 新 ANGLE 的来源：Carapacik fork 的 v8078（小、带校验，但第三方单人 fork）还是 Electron 43 官方 zip 抠 DLL（来源正统，但需自己托管，见 2026-10-24 笔记）。
3. 近期止血与长期路线的取舍：先上"软件渲染开关 + 关后向缓冲"，同时推进方案 A；方案 C（mpv D3D11 直出）是否立项。

## 局限

- WebSearch 对 chromium/angle 的 bug 库（issues.chromium.org）没有检索到相关条目，故"ANGLE 上游已知泄漏与修复版本区间"这一问**没有结论**，不能当作"上游不存在"。
- 没有读 Predidit 分支代码细节，只确认其分支名与 issue 里的描述。
- fvp 的 D3D11 纹理直出细节与 mdk-sdk 许可条款未核对。
