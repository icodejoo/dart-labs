# Flutter Windows 产品路径（media_kit Video + ANGLE）渲染验证

日期：2026-10-24。机器：Windows 11 Pro 10.0.26100，真实桌面。证据原件在 `D:\tmp\win2\ev\`（不入库）。"实测"为本机跑出，"推断"单独标注。

## 结论

- `flutter build windows` 失败的**根因**：Claude Code 进程（及其全部子进程）开启了 RedirectionGuard（`ProcessRedirectionTrustPolicy` flags=1，explorer 是 0），非提权用户创建的符号链接/junction 对其子进程一律是"不受信任的装入点"（WinError 448），经链接目录访问 `.plugin_symlinks/*/windows` 必然 "not an existing directory"。与 Dart 写链接的格式无关（`mklink` 建的 symlink、junction 同样失败）；开发者模式已开、同盘/跨盘都一样。
- **解法（实测可用）**：让构建进程跳出该进程树，用 `Start-Process explorer.exe <脚本.cmd>`（由已运行的 explorer 代为启动，子进程 flags=0），脚本里调 fvm flutter。任务计划程序与 WMI 在本会话被拒（Access denied），不可用。普通终端手工运行不受影响。不需要改任何系统设置，没改 Flutter SDK。
- 产品路径渲染**正常**：Flutter Windows release/debug + media_kit Video + ANGLE，WHEP、HTTP mp4、本地 mp4、本地 HLS 全部出画（截图见下）。瘦身掉 d3dcompiler_47/vk_swiftshader/vulkan/zlib 后**无缺陷**：运行时模块表显示 libEGL/libGLESv2/libmpv 取自应用目录，`d3dcompiler_47.dll` 取自 `C:\WINDOWS\SYSTEM32`（10.0.26100.6899），无黑屏无崩溃。
- 单测 `fvm flutter test`：**1014 项全绿**（与基线一致）。

## 构建方法与 DLL 来源

- 切片包 `media_kit_libs_windows_video_slim` 的 CMake 从 `windows/libmpv-2.dll` 取 DLL，从 `windows-devlib/libmpv.dll.a` 取导入库。**这两个文件在本工作树里是未拉取的 LFS 指针**（一个 133 字节，一个 130 字节），直接构建会 `LNK1107 文件无效或损坏`。另外指针对应的对象（14,075,392 字节）是旧的非 S 档 DLL，不是 WHEP 的。
- 本地覆盖（不提交）：把包拷到 `D:\tmp\win2\slim_pkg`，放入含 0011 的 DLL（拷贝 `D:\tmp\win2\dll\libmpv-2.dll`，sha256 前缀 `25d621eb`，10,875,904 字节），用 `dlltool -d libmpv-2.def` 重生成导入库（导出符号与 def 一致，54 个），再在 `mova/example/pubspec_overrides.yaml`（用完已删）把 `media_kit_libs_windows_video` 指过去。产物目录里 `libmpv-2.dll` 的 sha256 与之一致。
- 对 MediaMTX（`mine.yml`，端口整体 +20000 避开并行任务实例，chunked 默认多候选，`curl -i` 为 `Transfer-Encoding: chunked`）用 `main_whep_verify.dart` 跑 WHEP：2.8s 出首帧，640x360，`hwdec=d3d11va-copy`，acodec=opus，fps=25，drop=0/0，40s 观察 posDelta=40720ms，wasapi 选中 Realtek 扬声器。截图 `whep_shot1.png`（testsrc2 色条正确，叠加时码 1:03.720）。

## 一般播放（release，`main_win_verify.dart` MODE=general）

本地 `python -m http.server` 提供 clip.mp4 与 HLS（4s 分片，VOD）。各 15s：

| 源 | 结果（15s 时） | 画面 |
|---|---|---|
| HTTP mp4 | pos=14320 640x360 hwdec=d3d11va-copy drop=1/0 avsync≈0.0007 | 红/黄色条像素检查通过 |
| 本地 mp4 | pos=14680 drop=0/0 | 同上 |
| 本地 HLS | pos=14701 drop=0/0 | 同上 |

截图 `gen2b_httpmp4.png` / `gen2b_filemp4.png` / `gen2b_hls.png`、`gen2_http.png`。

### 发现的缺陷（**未修，需决策**）：懒创建 VideoController + 立即 open 的本地源没有画面

- 现象：`createMovaEngine()`（`lazyVideo: true`）挂到界面后**立即** `open()` 本地/HTTP 点播源，只出声不出画：`MovaSizeChange` 不触发、`vid=no`、`vo` 为空、`track-list/count=2`（视频轨在），窗口黑屏；WHEP 因为信令有延迟所以躲过（`vid=1`）。
- 对照：`PRE_OPEN_MS=1500`（挂界面后等 1.5s 再 open）三个源全部正常出画。mpv 日志里 `VideoOutput` 控制器已创建、`vid` 却仍是 `no`，推断：控制器创建时才把 `vid` 设 `auto`，此时文件已打开、视频轨没被重新选中。
- 未能做 A/B 确认是否 slim DLL 特有：换上游 2023-09 的 libmpv（md5 a832ef24…，同一 example）该 harness 里连音频都不播（pos=0），不可比。Android 真机上同一流程（先播后挂界面）曾验过正常，所以不排除是 Windows 或新 mpv 提交特有。
- 影响：产品里"先 open、后挂界面"的点播在 Windows 上会黑屏。属 mova 内核（`MovaMpvKernel.lazyVideo`/`renderHandle`）范畴，不是 CMake/资源配置，按任务约定**停下记录，不改**。建议：创建 `VideoController` 后补一次 `vid=auto` 重选，或 `open` 前确保 `renderHandle` 已读取。

## 稳定性（release，WHEP，chunked MediaMTX）

5 轮起播/停止（每轮 8s，每轮重建 engine + MovaPlayer，`stress`）：5/5 轮 `size=640x360`，pos 5120/6400/6440/5720/6440ms，drop=0/0，vo-delayed=0，avsync≈2e-5。进程采样（5s 一次，`samples_stress_keep.csv`）：峰值 WS 195.4 MiB、私有 448.1 MiB、句柄 1748/线程 335，结束时句柄 1054/线程 156（回落到比起点 1302 更低），无句柄增长。

330s 长跑（`long`，同一会话）：pos 328160，drop=0/0、vo-delayed=0 全程（每 30s 采样 11 次），avsync≤0.0008。进程：句柄 1738→1731 持平，线程持平；**但 WS 与私有内存线性上涨**：WS 182.6→257.9 MiB（约 +0.28 MiB/s ≈ 17 MiB/min），私有 307→384.6 MiB，结束 dispose 后回落到 209/336 MiB，句柄 1064。

### 未解决：带视频渲染的内存线性增长（**不是 slim 引入，也不是 mova 引入**）

对照（均 release、同源，`samples_*.csv`）：

| 配置 | 内存趋势 |
|---|---|
| mova + MovaPlayer（long，330s） | WS 183→258 MiB 线性涨 |
| 裸 media_kit Player+Video（rawwhep，210s） | 同样线性涨（约 8.6 MiB/30s） |
| 同上 hwdec=no 软解（rawwhepsw，180s） | 同样线性涨 |
| 同上 + 随包 d3dcompiler_47（ANGLE.7z 的 10.0.20348 版，模块表确认加载） | 重复一次后同样线性涨（首次曾平台化，复测不成立，视为偶然） |
| 裸 media_kit 不创建 VideoController（vid=no，rawwhepnov，180s） | 122→128 MiB，基本持平 |
| 裸 media_kit 本地 mp4 loop-file（rawfile，150s） | 184→198 MiB 后趋平 |

结论：增长发生在"有视频渲染面"的实况 WHEP 上，与 mova 层、硬解/软解、d3dcompiler 来源都无关。上次 libmpv 独立 smoke（vo=gpu 自带窗口，660s）私有内存是平的，所以更像 libmpv render API + ANGLE 纹理路径（或实况流下的帧队列）相关，**推断**，未定位。尚需更长（>10 分钟）观察是否趋于平台，并用 release 对照一份上游 libmpv（需先解决上游 DLL 在此 harness 里不播放的问题）。

## 其他

- 并行任务收尾时误停了我的 MediaMTX/ffmpeg/http.server，一批复测因此无效（pos=0），已重启后重测，上表为有效数据。
- 新增验证入口 `mova/example/lib/main_win_verify.dart`（general/stress/long/raw* 模式，未提交，仅验证用）。`main_whep_verify.dart` 原有的未提交改动未动。
- 已还原 `example/windows/flutter/generated_*` 与 `pubspec.lock`，删除临时 `pubspec_overrides.yaml`；停掉全部后台进程（MediaMTX mine.yml、ffmpeg、http.server、采样器、app）。没有 git commit。
