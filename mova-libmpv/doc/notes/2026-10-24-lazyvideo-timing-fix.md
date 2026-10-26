# lazyVideo 时序：Windows 黑屏修复与 Android VP9 起播慢的再定位

日期 2026-10-24。范围：`mova/lib/src/core/kernel/mpv_kernel.dart`（`MovaMpvKernel`）。

## 结论先行

| 症状 | 原假设 | 实测结论 | 处理 |
|---|---|---|---|
| B Windows 黑屏（lazyVideo + 立即 open 只出声） | 控制器创建时才设 vid=auto，视频轨没被重选 | **机制不同**：`vid=auto` 比渲染上下文先到，文件恰在此窗口打开，mpv 初始化 VO 失败后**永久丢掉视频轨** | 已修复 |
| A Android 解码器多重建一次 / VP9 起播慢 | lazyVideo 先 vo=null 再 vo=gpu | **不成立**：lazy 与非 lazy（eager）日志完全相同；null->gpu 是 media_kit Android 控制器自身流程；v0.41 与 n6 基线在同一测法下无系统性差异；VP9 尖刺新旧版都有 | **mova 侧无抓手，未修，原样记录**（见"未解决"） |

## 1 症状 B：根因证据（Windows，release，ANGLE，本机 mp4 / HTTP / HLS）

harness：`mova/example/lib/main_lazyvideo_verify.dart`（`DUMP=true` 打印 mpv 日志）。修复前，HTTP mp4 的 mpv 日志（毫秒为相对 open）：

```
 14ms  Set property: vo="libmpv" / vid="auto"      <- media_kit 控制器此刻才写（渲染上下文还没建）
 39ms  Opening done ... ● Video --vid=1 (h264 640x360)
 39ms  vo/libmpv: No render context set.
 39ms  Error opening/initializing the selected video_out (--vo) device.
 39ms  lavf: deselect track 0
 39ms  Video: no video                              <- 视频轨被永久丢弃，只剩音频
 86ms  libmpv_render: GL_VERSION=... (渲染上下文此时才建好，晚了 47ms)
```

结果：`vid=no`、无视频解码器、`MovaSizeChange` 不触发。因此"没被重新选中"只对了一半：不是没选，而是选了但 VO 初始化失败被 mpv 撤销。

两条旁证：
- 只补一次 `vid=auto` 无效：运行期读到的 `vid=no` 对应的选项值其实仍是 `auto`，再设 `auto` 是空操作（日志只多一行 `Set property: vid="auto"`，仍无视频解码器）。先写 `no` 再写 `auto` 才会重选（日志出现 `Opening decoder h264`、`vid=1`、`vo=libmpv`）。
- 补选对不可 seek 且已读到 EOF 的小流无效（测试用 `python -m http.server` 无 Range，文件极小，在失败前已读完，重选时视频包已丢）：画面为空。HLS 和可 seek 的源可补回。所以光靠补选不够，还需要避免撞上窗口。

## 2 改动

文件：`mova/lib/src/core/kernel/mpv_kernel.dart`、`mova/lib/src/platform_impl/frame_yield.dart`（新）、`mova/lib/src/platform_impl/wiring.dart`、`mova/test/core/kernel/mpv_kernel_video_test.dart`（新）、`mova/test/core/audio_only_test.dart`（结构守卫由"数 `VideoController(` 行"改为"数 `_attachController()` 调用行"，守卫语义不变）、`mova/example/lib/main_lazyvideo_verify.dart`（新，验证入口）。

内核行为：
1. 所有创建控制器处收口到 `_attachController()`，创建后立即启动 `_prepareVideo`：等控制器渲染面就绪（`controller.platform.future`，Windows 上含纹理/渲染上下文），若 mpv 报 `vid=no` 则先写 `no` 再写 `auto` 重选。失败静默，退化为旧行为。
2. `open()`：已有控制器则先等其就绪（上限 `kVideoReadyTimeout`=3s）再开文件，避开窗口。
3. `open()`：lazy 且控制器尚未创建时，先通过注入钩子 `mountYield` 让出一帧（上限 `kMountGrace`=250ms），让同帧挂载的 `MovaPlayer` 先创建控制器。**只让出、绝不自己创建**，所以 lazyVideo 的初衷（从不展示的引擎不创建视频管线、`Player.dispose()` 不再等渲染面；audioOnly 完全不碰）保持不变。`core/` 不能依赖 flutter（`purity_test`），所以钩子由 `platform_impl/frame_yield.dart` 的 `movaFrameYield`（`SchedulerBinding.endOfFrame`）经 `createMovaEngine` 注入；直接 `MovaMpvKernel(lazyVideo: true)` 不传钩子则不让出（仍有第 1 条的补选兜底）。

与用户决策的差异（需知悉）：用户拍板的"open 前定好 vo、不再先 null 后 gpu"，在 Windows 上对应成"open 前先让渲染面就绪"，已实现；在 Android 上这一前提不成立（见 §4），没有可改项。

## 3 验证

单元：新增 9 项（`mpv_kernel_video_test.dart`：补选、不重复补选、open 等就绪、lazy 不创建控制器、同帧挂载让出一帧、就绪失败不阻塞、audioOnly 不碰、非 lazy 同样补选）。先红（编译失败 / 让出一帧用例断言失败）再绿。`flutter test` 全量 1023 项全绿（基线 1014 + 9），`flutter analyze lib test` 0 issues。

Windows（`D:\tmp\w13` 副本构建，WHEP DLL 用 `D:\tmp\win2\slim_pkg`，release）。同一 harness、挂界面后**立即** open，每源 2–3 轮：

| 源 | 修复前 | 修复后 |
|---|---|---|
| 本地 mp4 | （harness 带 `?t=` 导致失败，改后见下行） | vid=1、vo=libmpv、hwdec=d3d11va-copy，首帧 sizeMs 157–772ms，截图 ~100KB 视频帧 |
| HTTP mp4（无 Range） | `vid=no`、无视频解码器、sizeMs=null（2/2 轮） | 出画（3/3 + 2/2 轮），vidSets=1（无需补选） |
| HTTP mp4（Range） | 未测 | 出画 |
| 本地 HLS | `vid=no`（2/2 轮） | 出画（5/5 轮） |
| WHEP（MediaMTX，端口 +20000） | 未单测（旧笔记：先 open 的本地/HTTP 黑屏，WHEP 因信令延迟躲过） | 出画 5/5（含 3 轮 + 2 轮），sizeMs 2.5–3.8s |

最终代码再跑一遍：5 源 x 2 轮共 10/10 出画，`vidSets=1`、解码器打开 1 次、`seeks=0`。`main_win_verify` stress 5 轮 WHEP 起播/停止（每轮重建 engine）：5/5 `size=640x360`、`err=none`、dispose 正常（pos 5880–6440ms，drop=0/0）。真实窗口截屏（`shot.ps1`）可见画面（testsrc2 色条）。mpv 截图取自视频帧，非窗口。

Android（STG-AL00，v0.41 `libmpv.so`，release，`adb reverse` + Range 服务，3 轮 x h264/hevc/vp9，harness 同上，首个 position>0 的 ms；三次独立运行共 9 个样本）：

| 构建 | h264 中位 | hevc 中位 | vp9 中位 / ≥2s 尖刺 | 视频解码器打开次数（中位） |
|---|---|---|---|---|
| n6 基线 so（3 样本） | 773 | 899 | 1008 / 1 次 | 3 |
| v0.41 修复前 | 837 | 814 | 1008 / 4 次（9 个里） | 3 |
| v0.41 修复后（中间版，9 样本） | 761 | 793 | 2201 / 5 次 | 3（尖刺时 9） |
| v0.41 最终代码（1 次 3 轮） | 737 | 880 | 914 / 0 次 | 3 |

（"解码器打开次数"是 harness 里 `Opening decoder` 中匹配 `h264|hevc|vp9|av1|mediacodec` 的行数，含重建；与旧笔记按 `vp9_mediacodec` 单口径的"3 次/2 次"口径不完全一致，只作相对比较。）

Android WHEP 不退化：`main_whep_verify`（真实局域网 UDP，手机 192.168.254.136 -> 电脑 192.168.254.110:28889，MediaMTX +20000 配置）40s `posDelta=40080ms`、`size=640x360`、首帧 1.8s，无错误事件。

## 4 症状 A：为什么 mova 侧改不动（证据）

1. lazy 与 eager（`lazyVideo:false`，控制器在构造期创建）在同一 harness 下的 mpv 时间线逐项相同：`vo=null / vid=auto` -> 视频解码器 #1（此时无 surface）-> 约 +360ms `vo=null` -> 解码器重建（#2、#3）+ `seek` -> `vo=gpu`。三次解码器打开、三次 vo 设置，两种模式一样。
2. 原因在 media_kit_video 2.0.1 Android 控制器（`android_video_controller/real.dart`）：`wid`（surface）要等 `videoParams`（需先解出视频尺寸）才由原生创建，`widListener` 再执行 `vo=null -> android-surface-size -> wid -> vo=gpu` 并 `seek(currentPosition)`，每次都让 mpv 重建 mediacodec。这是"先用 vo=null 解一次拿尺寸、再换 gpu"的固有流程，与 mova 何时创建控制器无关。
3. v0.41 与基线对比在本 harness 下不呈现旧笔记里的"系统性慢 100–350ms"（h264/hevc 差在 ±100ms 噪声内）；VP9 的 2–4s 尖刺（解码器打开 9/15 次、vo 设置 7/11 次，每循环 +4）**基线 so 也出现**（1/3），v0.41 修复前后都有，是间歇性的连环 seek 重建。尖刺不由 lazyVideo 决定。
4. 旧笔记 §4 的"不可 seek 源上连环 seek"在本次用的是带 Range 的服务，不覆盖该情形。

可能的后续（均超出本期决策）：mpv 侧让 `mediacodec-copy` 在 vo 重配时不重建解码器（旧笔记建议 b）；或给 media_kit 的 Android 控制器提前给出 surface 尺寸（不依赖首个解码结果）。两者都动第三方/mpv，需用户定。

## 未解决 / 注意

- 症状 A 未修（见 §4）；VP9 间歇尖刺在基线也有，来源未查清（推断为 `widListener` 的 `seek` 与 `videoParams` 的 `SetSurfaceSize` 互相触发的重建循环，未证实）。
- 不可 seek 的 HTTP 流若在渲染面就绪**之后才**挂载（`open` 后很久才挂界面）仍可能丢视频轨：补选只对可 seek / HLS 有效。需要时可考虑 open 前强制创建控制器，代价是失去 lazyVideo 的"从不展示就不建管线"收益。
- `kMountGrace` 250ms、`kVideoReadyTimeout` 3s 为经验值，帧停摆（后台）时 open 最多多等 250ms。
- Windows 的"HTTP mp4 无 Range"用例用 `python -m http.server`，不具代表性（无 Range 且文件极小）。
- 附带发现（非本次）：MovaSizeChange 的首个事件常为 `640x0`（宽先于高），既有行为未动。
