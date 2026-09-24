# CLAUDE.md — mova

在 mova 子工程内工作时的指引。详见 [doc/PRD.md](doc/PRD.md)（需求/决策）、
[doc/SPEC.md](doc/SPEC.md)（架构/实现/命令/验证缺口）、[doc/ROADMAP.md](doc/ROADMAP.md)（里程碑）。

> **换机器接手先读这三条**
>
> 1. **构造 engine 一律用 `createMovaEngine()`**（`lib/src/platform_impl/wiring.dart`，已从
>    barrel 导出），**不要直接 `MovaEngine()`**——后者的平台端口默认是 noop，会导致亮度手势
>    不生效、`enterPip()` 恒 false、全屏不转屏。`MovaEngine()` 保留裸构造只为单测注入假端口。
> 2. **[doc/DESIGN-0.2.0.md](doc/DESIGN-0.2.0.md) 有约 10 处已过期**（阶段 A 落地后未回写：
>    kernel 签名、`MovaState.sourceTitle`、`MovaApi.renderHandle`、`MovaAbrPolicy` 落点、
>    sha1→FNV-1a，以及 4 处为守住 core 纯净性而必须挪到 `platform_impl/` 的结构调整）。
>    **设计意图看 DESIGN，签名与落点一律以代码和 [doc/SPEC.md](doc/SPEC.md) 末节为准。**
> 3. **阶段 B/C/D 的逐 Task 实现计划已就绪**，见 [doc/plans/](doc/plans/)。计划已按上述
>    两点对齐过，可直接按 Task 顺序执行。

## 是什么

基于 media_kit（libmpv/ffmpeg）的 Flutter 视频播放插件，自研手势与控制层，
支持点播/直播，发布到 pub.dev。属于 `dart-labs` monorepo 的子工程。

## 当前状态（0.6.0）

**0.6.0 App 内小窗（`MovaMini`）已完成代码落地（真机验证未做）**：不依赖任何系统 PiP
API，让画面从页面里"缩"成一个可拖拽的悬浮小窗——不重新解码、不黑屏。默认
**关闭**（`MovaMiniConfig.enabled` 为 `false`）。两种挂载方式并存：方式 A 页内悬浮
（`MovaMiniCtl.showInPage`，mova 实现 `OverlayEntry` 插入）、方式 B 跨路由持久
（`MovaMiniCtl.show` + `MovaMiniHost` 便利壳）。核心逻辑收在挂载无关的 `MovaMiniWindow`
一处（自身是撑满外部约束的 `Stack`，两种外壳只是"放到哪里"的差异）。core 层仅加
`MovaState.mini`/`MovaApi.setMini`/`MovaMiniChg`/`MovaMiniConfig`/
`core/mini/placement.dart` 五处，播放链路一行不动。测试 **803 项全绿**（基线 709，
本批新增 94）、`flutter analyze` 0 issues（1 条既有 `feed_player.dart` 警告，与本次
改动无关）。详见 [doc/plans/2026-09-23-app-inline-pip-overlay.md](doc/plans/2026-09-23-app-inline-pip-overlay.md)、
[doc/SPEC.md](doc/SPEC.md)「App 内小窗（MovaMini）」一节。**真机验证未做**（计划 Task 12，
见「剩余任务」）。

以下为 0.5.0 阶段成果（仍有效）：

## 当前状态（0.5.0）

> **合并后的当前测试基线：709 项全绿**（2026-09-17，`audioOnly` 与 0.5.0 广告编排增强
> 两条分支各自独立开发后合并进 main：536 → 560（audioOnly +24）与 536 → 656（广告增强
> +120）分别是各自分支单独的基线，**不能相加**——两者共享的既有测试没有重复计数，
> 合并后跑出来的真实总数是 709）、`flutter analyze` 0 issues（仅剩那条既有
> `feed_player.dart` 警告）。以下两节各自的测试数字是它们在合并前的历史快照，保留供
> 追溯，别拿来加总。

**0.5.0 广告编排增强已完成**：把 `MovaAdCtrl` 从"能按排期播广告"推进到"能按广告业务的
真实时序播广告"——正片源延迟解析（`loadDeferred`/`contentError`）、广告位 `duration`/
`delay` 与素材时间轴解耦（一律 `Timer` 驱动，绝不碰 `state.duration`/尾部 seek）、
按广告位类型决定是否等待就绪（`MovaAdWaitByKind` 默认 pre 否 / **mid 是** / post 否，
三层覆盖收在 `MovaAdConfig.waitsFor()` 一处）、加载失败兜底（`MovaAdFailPolicy`）、
以及 `MovaWarmPlan`（给 `prepare` 加可选具名参数，让同一个 `MovaSwapEngine` 服务两个
预热方向）。**不新建任何预热机制**，三个既有抽象零类型改动直接复用。控制器新增第四态
`_Phase.pending`。顺带修掉 0.4.0 三处潜伏缺陷（注入判据从不 `reset()`、`at==0` 仍下发
无谓 `seek(0)`、影子 `MovaErrorEvent` 无人监听）与"中插 pod 根本没串联、会闪回正片"。
**除广告位时长外全部默认关闭/默认不改变行为**；等待要生效还需宿主接了 `swap` 且
`MovaSwapConfig.enabled` 为 true，两者 0.4.0 默认都是关的。测试 **656 项全绿**
（基线 536，本批新增 120 项）、`flutter analyze` 0 issues（1 条与本次改动无关的既有
`feed_player.dart` 警告）。**真机验证部分完成**（2026-09-23，STG AL00 arm64 Android 12；
前贴片不等待路径、中插坏 URL 失败降级、失败事件只触发一次三项已拿到客观证据，其余
仍未测，详见「剩余任务」第 0 条）。
详见 [doc/plans/2026-09-16-ad-swap-enhancements.md](doc/plans/2026-09-16-ad-swap-enhancements.md)、
[doc/SPEC.md](doc/SPEC.md)「广告编排增强」一节。

以下为 0.4.0 阶段成果（仍有效）：

## 当前状态（0.4.0）

**0.4.0 无缝引擎切换已完成（默认关闭）**：新增 `MovaSwapEngine`（`lib/src/core/swap/`）——
一个本身实现 `MovaApi` 的代理，持有生效引擎 + 短暂预热中的影子引擎，就绪后原子换指，
把"广告播完回正片"从黑屏/loading 变成逐帧无缝。`MovaOpts.swap`（`MovaSwapConfig`）默认
`enabled: false`，关闭时是纯直通代理，行为与 0.3.0 逐字节一致。预热拆成两层可插拔纯逻辑：
触发策略 `MovaWarmTrigger`（`MovaLeadWarm`/`MovaEagerWarm`）与就绪判据 `MovaWarmPolicy`
（`MovaBufferWarm`，`MovaBufferAbr` 的镜像）。新增 `MovaState.renderEpoch`（普通引擎恒
0，仅切换后递增，触发渲染面重读 `renderHandle`）。`MovaAdCtrl` 接了可选 `swap` 参数即可
接入；清晰度切换（`switchQuality`）只做了接口形状契约测试 + 落点注释，未真正接入；
feed 引擎池结构性不适用本模型，明确排除。详见
[doc/plans/2026-09-16-seamless-swap.md](doc/plans/2026-09-16-seamless-swap.md)、
[doc/SPEC.md](doc/SPEC.md)"无缝引擎切换"一节。**真机验证部分完成**（2026-09-23：用
`main_seamless_test.dart` 实测 skip 触发后 `renderEpoch` 1→2 确认切换机制真实生效，
广告→正片切换间隔（skip 调用到 renderEpoch 落地，基于真实事件戳）= 806ms；黑屏是否真的
消除、切换瞬间音画是否跳变、内存/解码 session 三阶段采样、短广告降级路径、断网预热
超时兜底仍未测，见「剩余任务」第 0 条）。

**0.4.x 仅音频模式（`audioOnly`）已完成（默认关闭）**：`MpvKernel` / `MovaEngine` /
`createMovaEngine()` 新增 `bool audioOnly = false` 构造参数。为 `true` 时完全跳过
`VideoController` 的创建——media_kit 的 `Player` 默认就是 mpv 的 `--vid=no`，只有
`VideoController.create()` 会把它改回 `vid=auto`，因此不挂接它就等于让 libmpv 只解
音频：解码帧缓冲/GPU 纹理/Flutter `Texture` 注册三项是 0 而非变小。`createMovaEngine()`
在此模式下也不再默认注入 `MpvFrameExtractor`（它首次抽帧会新开第二个 `Player` 并为其建
`VideoController`）。`MovaKernel.renderHandle` 由 `Object` 放宽为 `Object?`。
**不新增任何公开类、barrel 一行未改、UI 层零改动**（`null` 句柄天然走占位分支，音频的
封面/波形/歌词面用已有的 `MovaPlayer.surface` 传入，故不做 `MovaAudioSkin`）。
`audioOnly` 刻意不进 `MovaOpts`（构造期资源决策，`copyWith` 无法生效），也不加
`MovaStreamType.audio`（与流类型正交）。**Windows 桌面端已实测**（`ProcessInfo.currentRss`，
同一条素材各两轮）：播放期内存增量视频 197 MiB vs 音频 96 MiB，省约 101 MiB、约 2.05×——
**是约 2 倍而非推算的两个数量级**（RSS 含 Flutter engine/libmpv 自身常驻开销），
同时直接确认 `audioOnly` 下 `MovaState.size` 为 `0x0`（视频轨未解码）、`renderHandle`
为 `null`；数据见 [doc/notes/2026-09-16-audio-only-feasibility.md](doc/notes/2026-09-16-audio-only-feasibility.md) §1.5。
**真机三阶段内存对账已实测**（2026-09-23，STG AL00，`ProcessInfo.currentRss`，两次独立
运行）：video 模式 baseline 108.89→playing 156.73（+47.84）→disposed 155.63 MiB，audio
模式 baseline 99.45→playing 117.18（+17.73）→disposed 121.73 MiB，真机播放期增量比约
2.7×（桌面此前是约 2.05×，量级一致、真机差距更大）；`renderHandle`/`size` 在 audio
模式下分别确认为 `null`/`0x0`。计划见
[doc/plans/2026-09-16-audio-only.md](doc/plans/2026-09-16-audio-only.md)、
[doc/SPEC.md](doc/SPEC.md)"仅音频模式"一节。**真机验证部分完成**（Task 5，剩余项见
「剩余任务」）。

**当前测试基线：560 项全绿**（0.4.0 落地时为 536，仅音频模式新增 24 项）、
`flutter analyze` 0 issues（1 条与上述改动均无关的既有 `feed_player.dart` 警告，
早于这些改动已存在）。

以下为 0.3.0 阶段成果（仍有效）：

**0.3.0 UI 插件化已完成**（承 0.2.0 阶段 A–D）：把组件树/皮肤/补丁沉淀为
**Plugin / Component / Skin** 三层契约——`MovaPlugin` 能力 mixin（`api` + `bind()`，
`ui/scope/plugin.dart`）、组件树静态化（`MovaSkin.components()` 无参，VOD/直播底栏合并为
自适应 `BottomBarComponent`，`live_bar.dart` 已删）、`MovaDefSkin.assemble` 拆为可覆写
三层（`buildPlaybackLayer`/`buildOperableLayer`/`buildPersistentLayer`）、`MovaSlot` 加
`left`/`right`。**手势侧别→动作改配**：`MovaGestConfig` 用 `MovaGestAction` 映射，默认
翻转为左亮度/右音量（对齐主流）。设计见 [doc/DESIGN-0.3.0-plugin-skin.md](doc/DESIGN-0.3.0-plugin-skin.md)。
后续增量：系统音量端口 `MovaVolumePort`、强制横竖屏 `MovaApi.setOrientation`
（`MovaOrient{auto,portrait,landscape}` + 顶栏仅移动端的 `orientationButton`，
独立于全屏；`auto` 保持按宽高比定向）。
289 项测试全绿，`flutter analyze` 0 issues。**横竖屏按钮真机仍未验证**（手势/音量/亮度
线已在 Android 真机过；方向按钮与 PiP/直播/时移 UI 等仍未系统走真机，承自 0.2.0）。

---

以下为 0.2.0 阶段成果（仍有效）：

**阶段 A（core/ui 分层重构）已完成**：功能与 0.1.0 保持一致（零可见变化），架构
重写为 `MovaApi`/`MovaEngine`（取代 `MovaCtrl`，后者已 `@Deprecated`）+
`MovaKernel` 内核抽象 + 组件树/皮肤/补丁（`MovaComp`/`MovaSkin`/`MovaDefSkin`/
`MovaPatch`）+ 文案与主题外置（`MovaStrs`/`MovaTheme`，经 `MovaOpts` 注入）+
拦截点（`MovaHook`）。

**阶段 B（拖动预览缩略图）已完成**：`MovaApi.preview`/`MovaOpts.preview`/
`MovaPrevBlock` 三个新公开面，WebVTT 雪碧图 + libmpv 抽帧兜底的有序来源链，
内存+磁盘两级缓存，`connectivity_plus` 网络策略，`PreviewComponent` 气泡
（水平位置随拖动比例跟随）。

**阶段 C（直播时移）已完成**：`MovaLiveConfig` 新增 `urlBuilder`/`backToLive`/
`autoBackToLiveOnStall`/`windowResolver`；`lib/src/core/live/timeshift.dart`
纯函数 `resolveWindow`/`behindOf`/`atLiveEdge`；`MovaState.timeshiftBehind` 真正
写入并伴随 `MovaTimeShiftChg`/`MovaLiveEdgeReach` 事件；`backToLiveEdge()`
从占位（`reload()`）变为按策略执行；新增 `MovaApi.pipSupported`/
`MovaState.pipSupported`，PiP 按钮在不支持的平台自动隐藏；直播底栏加
`seekBar`/`timeshift`/`backToLive`（原 `backToEdge` 已改名删除）。
260 项测试全绿，`flutter analyze` 0 issues。

## 剩余任务

**Windows 真机播放中途 libmpv 原生崩溃——已解决（用户 2026-09-24 拍板标记解决，
规避手段：`--no-enable-impeller` 强制走 Skia 后端）**。注意这是**规避手段而非
调用栈级根因**（未拿到带符号 dll + 崩溃转储做最终确认，样本量也只有 3 次以上
未复现），后续如复现请先怀疑 Impeller 相关改动或 Flutter 升级带来的默认值变化。
`mini_window_demo` 在播放中途（非引擎刚创建时）触发
`0xc0000005` 访问越界，故障模块是自研瘦身版 `libmpv-2.dll`，Windows 事件日志三次复现
故障偏移完全一致（`libmpv-2.dll+0x94d927`）。已排除：不是已用 clang 修复的
`mpv_create()` 崩溃（位置、时机都不同，且已确认 CI 产物确实是 clang 编译）、不是网络
流本身、不是小尺寸渲染面、不是 `createMovaEngine()`/`MovaPlayer` 封装本身、不是
`showInPage()` 挂载动作本身、不是 `MovaMiniCtl.show()`+`Navigator.pop()` 的路由转场
竞态——这几种场景自动化复现均不崩，**崩溃似乎只在真人鼠标/拖拽交互下触发**。故障地址
落在静态链接的 ffmpeg/libav 内部（非 mpv 导出符号区间），dll 无调试符号，反汇编看不出
函数名。**新发现**：Flutter 3.47 起 Windows 桌面端 Impeller 已非纯 opt-in（`--no-
enable-impeller` 是真实变量切换，不是空操作），用该参数强制走 legacy Skia 后端启动
demo 后，同样的"播放中途+真人拖拽"场景连续 3 次以上未复现崩溃（此前是 100% 必现）——
指向 libmpv 的 GPU 纹理/渲染句柄与 Impeller（可能是其 ANGLE/D3D 层）交互时的资源竞争
或生命周期问题，但**尚未确认是否 100% 规避**（样本量仍小，只是从"必现"变成"多次不
现"，未排除低概率复现）、**尚未定位到具体触发机制**（仍需带符号 dll + 崩溃转储配合
cdb/gdb 拿真实调用栈）。已配置
`HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\mova_example.exe`
收集转储到 `_crash_dumps/`（本轮未复现崩溃故未拿到 `.dmp`，配置仍保留）。详见
[doc/SPEC.md](doc/SPEC.md)「App 内小窗（MovaMini）」一节的详细排查记录。
**注意区分**：`_MisuseDemo` 页面故意触发的 debug assert 会导致窗口无声消失但
**没有**崩溃弹窗/事件日志/原生故障——那是另一个已在 demo 里修复的问题
（`_engine.dispose()` 缺 `catchError`），不要和这个原生崩溃混为一谈。

**0.6.0 App 内小窗——真机验证未做（Task 12，每次启动请提醒用户此项未完成）**：
Task 1–11 已完成（core 五处改动、`MovaMiniCtl`/`MovaMiniWindow`/`MovaMiniHost`/
`MovaMiniSkin`、开放性对账、example demo、文档）。剩 Task 12 的真机 checklist（七组，
详见计划文档）：A 组不重新解码（`renderEpoch`/position 连续性、三阶段内存对比）、
B 组交接那一帧（黑帧数、音频不中断）、C 组跨路由/生命周期（方式 A 页内滚动零漂移、
方式 B 跨两层路由、两种方式互斥、转屏钳回、与系统 PiP 互斥）、D 组手感（拖动跟手、
吸边动画、甩出阈值）、E 组误用防护（assert 命中/release 不崩）、F 组关闭态回归、
G 组结论回写。计划见 [doc/plans/2026-09-23-app-inline-pip-overlay.md](doc/plans/2026-09-23-app-inline-pip-overlay.md)。

**libmpv 瘦身产物的 CI/git 集成——2026-09-17 全平台 CI 首次全绿**（8/8 job，含此前
一直失败的 Android x86——根因是共享 build 缓存跨架构污染导致 meson 复用 stale 配置
构建出静态库，已修复）。**同日追加 Windows/Linux 的编译器级瘦身**（Windows 14.66→
13.41 MiB −8.5%，Linux 8,189,568→7,550,784 字节 −7.8%，均为 `-Os` 级别；`-Oz` 在
Windows 上本地测出 −11.2% 但 CI 复现失败，已回退）。**iOS 已于同日追加完成**（其他四
平台 job 暂时 `if: false`，CI 现在只跑 iOS 做快速迭代）：先复用 `media-kit/libmpv-darwin-build`
的默认 flavor 拿到第一次真实全绿（18.48MiB/18 个独立 dylib），再叠加 mova 自己的
`movaslim` flavor（`mova-libmpv/libmpv-darwin-build-mova-slim.patch`，decoder/demuxer 裁剪
+ securetransport 替 mbedtls）降到 10.76MiB/13 个文件，最后把 ffmpeg/dav1d/freetype/
fribidi/harfbuzz/libpng/libass 全部改成静态链接进单一 `libmpv.dylib`（跟 Android 同一种
"单文件"形态才可比）+ 编译器级瘦身（`buildtype=minsize`/`debug=false`/`b_ndebug=true`），
CI 实测 7,489,408 字节 ≈7.14MiB，仅比 Android 的 6.52MiB 高约 9.5%（两平台硬解
API——MediaCodec vs VideoToolbox——架构本就不同，这个差距已经很合理）。**再叠加 audio/protocol
白名单收窄**（movaslim 音频 decoder/demuxer 只留 mova 实际用得上的一批，协议只砍掉
ftp/async/cache/subfile/httpproxy，RTMP/RTP/UDP 因为是真实直播源保留）后，**当前记录：
CI 实测 6,534,448 字节 ≈6.23MiB，反超 Android 的 6.52MiB 约 4.4%**。静态化过程连环
踩坑（5 层 pkg-config `Requires:` 传递依赖、libtool `ar`/`ranlib` 被替换成 `false`、
meson `-Dc_args=` 会替换而非追加 cross-file 的 `-arch`/`-isysroot` 导致 libpng 头文件检测
失败）详见 `mova-libmpv/README.md`「多平台进度」表 iOS 那一行的完整记录。macOS/其余平台
仍是 upstream 默认 flavor 未裁剪，是独立于本轮的更大工作量。Task 1–6 已完成，Task 7 剩
Android jniLibs 已接线，iOS 侧尚未把 `dist/darwin/` 产物接进 podspec：
目标是照抄 `media_kit_libs_android_video` 的思路（包本身不含二进制，构建时下载+校验），
但用户拍板改成**随包发布**（不做构建时下载，直接把编译产物随仓库/包分发，理由是内网
构建环境不应该依赖运行时联网下载）。为了让"随包发布"不至于把 `.git` 历史撑爆（实测
`mova/tools/ffmpeg-slim/dist/` 这条路径已经在历史里累积了 990 MiB，262 个 blob，且
`git clone` 会把这些历史版本全部下载下来），拍板方案是 **Git LFS**。

**Task 1–3 已完成**：在独立临时 clone 里用 `git filter-repo` 把
`mova/tools/ffmpeg-slim/dist/` 从 main 的全部历史里剥离（`.git` 898M→68M），重新用
`.gitattributes` + `git lfs track` 接管当前 `dist/` 内容并 force push。**范围比最初计划
更大**：用户 2026-09-17 当场改主意，**codeup 也一并做了同样的 filter-repo + force push**
（不是最初"只保证 GitHub 干净、不用管 codeup"的方案）——已验证 codeup 支持 Git LFS
（不支持 locking API，无影响，`lfs.<url>/info/lfs.locksverify` 可选择性关闭静默该提示）。
两个远程现在历史一致、都在 LFS 之下。主工作区 `main` 已 `reset --hard` 对齐到新历史
（`efc8b5a`），本地 5 个已合并的旧分支（`bench/ffi-copy-share`、3 个 `worktree-agent-*`、
`worktree-rust-perf-opt`）未处理但已确认全部完全合并进旧 main，改写后可安全删除（未删，
纯本地悬挂引用，不影响正常工作）；`mova-libmpv-winbuild-zhangfly` 是未合并的独立分支，
未被改写、未受影响。**pre-push 钩子已手动合并**（项目用 lefthook 管 `.git/hooks/pre-push`，
不能用 `git lfs install` 直接覆盖，改为在文件末尾追加 `git lfs pre-push` 调用，
`post-checkout`/`post-commit`/`post-merge` 三个钩子为空白，直接新建）。

**待恢复时按顺序做剩余 Task**：
4. **CI 的"提交产物回 dist/"重试逻辑——三个连环 bug，2026-09-17 当天全部现场发现并修复**：
   a) **rebase-on-dirty-tree**：原先"先本地 commit，push 被拒就 `fetch + rebase`"在工作区
      不纯净时会 `cannot rebase: You have unstaged changes`；改成"每次重试先 `fetch +
      reset --hard origin/main` 拿干净基线，再在其上 mkdir/cp/add/commit"，从根源上避免
      （不用查清楚具体是什么弄脏了工作区）。
   b) **LFS 内容从未真正上传**（比 a 更隐蔽、后果更重）：`actions/checkout` 不装 LFS 的
      pre-push/post-commit 钩子，五个 job 原来的 `git push` 因此只推了合法的 LFS *指针*
      提交，**从未上传过对应的二进制内容**——GitHub main 一度处于"5 个提交存在、但一
      `checkout` 就 404"的坏状态（arm64-v8a/armeabi-v7a/x86_64/linux-x86_64/darwin×2 共
      6 个对象缺失，已用 `gh run download` 从该次 run 的 artifact 里取出比对 SHA256 一致
      后手工塞进 `.git/lfs/objects/` 并 `git lfs push --object-id` 补传，已用干净 clone
      验证可正常下载）。修复：commit 后、push 前显式插入 `git lfs push origin main`。
   c) **windows job 专属**：该 job 全部 step 默认 `shell: msys2 {0}`，其 PATH 不含
      Windows Git 自带的 `git-lfs.exe`，导致 pre-push 钩子直接因"找不到 git-lfs"报错
      退出——现象和 a 长得很像（`error: failed to push`），但根因完全不同，5 次重试
      每次都在同一处失败。修复：把"Commit built artifact to dist/"这一步单独覆盖成
      `shell: bash`（不需要 MSYS2 工具链）。
   三处改动都在 `.github/workflows/build-mova-libmpv.yml`，详情记在
   `mova-libmpv/README.md`「多平台进度」表 Windows 那一行。**已过一轮真实 CI 验证**
   （run 35172861864 起，见 Task 6）。
5. darwin(macOS) job 上次被我们主动 `gh run cancel` 打断（不是构建失败，只是编译到一半，
   这个 job 天然要 45-90 分钟+）——**2026-09-17 已按此要求完整跑完一次，没有提前取消，
   成功**。
6. **LFS 化 + 历史清理 + 上述三个 bug 修复后的全平台重跑——已完成（2026-09-17，
   run 35172861864）**：8 个 job 里 7 个绿（Android arm64-v8a/armeabi-v7a/x86_64、
   iOS、Linux、Windows、macOS/darwin 全部成功，dist/ 提交与 LFS 内容都正确落地）。
   唯一失败的是 **Android x86，且是与本次 LFS/CI 修复完全无关的新发现**：
   "Build libmpv for x86" 那步没有真正报错退出，但压根没产出
   `prefix/x86/usr/local/lib/libmpv.so`，导致下一步 "Strip and verify" 报
   `No such file or directory`——x86 架构的构建本身有问题，需要单独排查（未开始），
   和 arm64-v8a/armeabi-v7a/x86_64 用的是同一套 flavor 脚本、只是架构参数不同，
   具体哪一步吞掉了失败还没查。

   **⚠️ 运维踩坑记录（2026-09-17）——`git lfs push --object-id origin` 在双 push-url
   remote 下不可靠**：本仓库 `origin` 同时配置了 codeup（fetch+push）与 GitHub
   （仅 push）两个 push URL。手工用 `git lfs push --object-id origin <oid...>`
   补传缺失对象时，它只会实际传到其中一个端点（不确定具体解析规则，实测观察到的现象
   是"报告全部成功"但 codeup 端仍然 404），**不会对两个 push URL 都传**。CI 那五个
   job 各自只 push 到 GitHub（`actions/checkout` 的 token 只对 GitHub 有效），所以
   **CI 每次重建产物后，codeup 端总会比 GitHub 缺新对象**——这不是一次性问题，是
   这套双仓架构的常态，每次 CI 重建完都需要手动从 GitHub 拉真实内容、再显式推到
   一个单独指向 codeup 的 remote（不要用 `origin`，用类似
   `git remote add codeup-explicit let188@...:codeup/dart-labs.git` 建一个专用
   remote 再 `git lfs push --object-id codeup-explicit <oid...>`）才能补齐。
   **验证方法**：`git clone --branch main --single-branch <url> <tmpdir>` 全新
   clone 一次，比对 `dist/*/*` 每个文件的字节数，这是唯一可靠的验证手段——
   `git lfs pull` 在本地已有 `.git/lfs/objects/` 缓存时会掩盖远端缺失对象的问题。
7. **接线到 mova 实际构建——Android/Windows 已完成，iOS 未接线**：
   - **Android（2026-09-17）**：`example/android/app/build.gradle.kts` 新增
     `syncMovaLibmpv` Gradle task（`Copy`，从 `tools/ffmpeg-slim/dist/<abi>/libmpv.so`
     拷进 `src/main/jniLibs/<abi>/`，四个 ABI 目录名两边天然一致），挂在 `preBuild`
     之前，每次构建自动同步。已本地验证：同步后 `jniLibs/` 四个 `.so` 的 MD5 与
     `dist/` 逐一比对完全一致。
   - **Windows（2026-09-24 确认，随「真机播放验证」一起落地，此前记录未同步）**：
     `example/pubspec.yaml` 用 `dependency_overrides` 把 `media_kit_libs_windows_video`
     指到本地 fork 包 `packages/media_kit_libs_windows_video_slim`。该 fork 的
     `windows/CMakeLists.txt` 跳过官方 7z 下载，直接指向
     `tools/ffmpeg-slim/dist/windows-x86_64/libmpv-2.dll`（mova-libmpv CI 产出的自研
     瘦身版），并从 `windows-devlib/libmpv.dll.a`（用 `gendef`+`dlltool` 针对该 dll
     导出表手工生成，dll 换版本要重新生成）+ `mpv-headers/*.h`（pin 在
     build-mova-libmpv.yml windows job 用的 mpv commit）拼出 `media_kit_video` 链接期
     需要的目录结构。真机验证（`flutter run -d windows` 画面+声音正常）用的就是这条
     链路，不是临时替换测试——**Windows 是真实生效的接线，不是仅验证未接线**。
   - **iOS 尚未接线**（podspec 还没引用 `dist/darwin/` 产物，留待 iOS PiP/真机验证
     一起处理时再补）。

**0.5.0 广告编排增强——真机验证部分完成（Task 12，每次启动请提醒用户此项仍有剩余项未完成）**：
Task 1–11 已完成。Task 12 真机 checklist 七组，**2026-09-23（STG AL00 arm64 Android 12）
已拿到客观证据的**：前贴片默认不等待路径正常播完、swap ready→ad completed→swap idle
事件全部触发；B 组失败降级——中插换坏地址后 15.94s 触发加载、16.05s 即失败，日志显示
`ad failed (Failed to open https://host.invalid/definitely-missing.mp4.)`，**确认真机上
坏 URL 走 openThrew（`open()` 直接失败），不是 playerError**，正片自动无缝续播、未见
卡死；D 组同一广告位失败事件只触发一次、未见重复弹出，客观验证通过。**仍未测**：A 组
等待就绪的黑屏帧数与时延分布（需视觉判断+多次统计验证 `adReadyTimeout` 5s 是否合理）、
C 组倒计时期间正片流畅度（双活解码，中低端机风险，主观判断）、E 组超长素材 `duration`
场景（本轮未构造超长素材）、F 组关闭态回归、G 组结论回写（尚待补全）。
example 已建独立页 `AdOrchestrationDemoPage`（四个开关 + 真实回调打点的屏上事件日志，
无需 logcat）。计划见
[doc/plans/2026-09-16-ad-swap-enhancements.md](doc/plans/2026-09-16-ad-swap-enhancements.md)。

**0.4.x 仅音频模式——真机验证部分完成（Task 5，每次启动请提醒用户此项仍有剩余项未完成）**：
Task 1–4 已完成（`renderHandle` 契约放宽、`MpvKernel` 不建视频管线、
`MovaEngine`/`createMovaEngine()` 透传、UI/swap 兼容护栏与文档）。Task 5 真机 checklist
中，**2026-09-23（STG AL00 arm64 Android 12）已用 `ProcessInfo.currentRss` 实测完成
三阶段内存对账**（两次独立运行）：video 模式 baseline 108.89→playing 156.73（+47.84）
→disposed 155.63 MiB，audio 模式 baseline 99.45→playing 117.18（+17.73）→disposed
121.73 MiB，真机播放期增量比约 2.7×（桌面此前约 2.05×，量级一致、真机差距更大）；
`renderHandle`（audio 模式为 null）、`size`（audio 模式为 `0x0`）均已在真机确认。
dispose 后内存几乎未回落——不能排除泄漏，但也非直接证据，需多轮连播才能下结论。
**仍未测**：带视频轨源在 audioOnly 下是否真的只出声不出画（本轮只测了纯音频源）、
`dumpsys meminfo` 分栏对账（MediaCodec/纹理，本轮用的是 `ProcessInfo.currentRss` 不是
`dumpsys meminfo`）、电量/CPU 量级抽查、连播多轮内存爬升判据（本轮只做了单轮三阶段）、
关闭态全 demo 回归。
**顺带发现探针缺陷（未修复，仅记录）**：`example/lib/perf_probe_audio_only.dart` 用
`stdout.writeln` 而非 `print()`，release 包在 Android 上不会出现在 logcat；且用
`Platform.environment` 读取模式参数，但 `--dart-define` 不会注入 Android 进程的 OS
环境变量，导致该探针的模式切换实际上从未真正生效过——待修。
**已就绪的前置**：`example/lib/audio_only_demo.dart`（独立 demo 页，带真实事件打点）
与 `example/lib/perf_probe_audio_only.dart`（RSS 探针，`--dart-define` 选模式，见上方
缺陷记录）。
计划见 [doc/plans/2026-09-16-audio-only.md](doc/plans/2026-09-16-audio-only.md)。
另：`MovaAudioSkin`（封面/歌词/波形专用皮肤，第二档，约 6–8 Task）**明确不做**，
将来若确有需要再评估——当前用 `MovaPlayer.surface` 已够。

0. **0.4.0 无缝引擎切换——真机验证部分完成（Task 11，每次启动请提醒用户此项仍有剩余项未完成）**：
   Task 1–10 已完成（配置面、`renderEpoch`、预热触发/就绪判据、`MovaSwapEngine` 骨架
   与原子切换、`MovaAdCtrl` 接入、清晰度切换契约测试、开放性对账、barrel/example/文档）。
   **2026-09-23（STG AL00 arm64 Android 12）已用 `main_seamless_test.dart` 实测**：skip
   触发后 `renderEpoch` 从 1 跳到 2，确认切换机制真实生效；广告→正片切换间隔（skip 调用
   到 renderEpoch 落地，基于真实事件戳，非墙钟估算）= 806ms。**仍未测**：广告黑屏是否
   真的消除（视觉主观判断）、中插续播点误差、切换瞬间音画是否有跳变（主观）、内存/解码
   session 三阶段采样（本轮未做，只测了 renderEpoch 和耗时）、短广告降级路径、断网预热
   超时兜底。
   计划见 [doc/plans/2026-09-16-seamless-swap.md](doc/plans/2026-09-16-seamless-swap.md)。

按 doc/DESIGN-0.2.0.md §12 的阶段划分。**逐 Task 计划已写好，直接照做即可**：

1. **阶段 B：拖动预览缩略图——已完成**（2026-07-31）。计划与实测结论：
   [doc/plans/2026-07-31-phase-b-preview.md](doc/plans/2026-07-31-phase-b-preview.md)
   （15 Task 全部完成，附录 A/B 记录实测结论与真机验证结果）。详见
   [doc/SPEC.md](doc/SPEC.md)"剩余任务"一节的实现现状小结。
2. **阶段 C：直播时移——已完成**（2026-07-31）。计划：
   [doc/plans/2026-07-31-phase-c-timeshift.md](doc/plans/2026-07-31-phase-c-timeshift.md)
   （Task 1–9 全部完成）。详见 [doc/SPEC.md](doc/SPEC.md)"直播时移（阶段 C）"一节。
3. **阶段 D：收尾——进行中**。同上文件的 Task 10–14：iOS podspec 元数据已对齐
   pubspec（Task 10 完成，注意版本号需手动同步）、example 已加直播/时移两个 demo
   （Task 11 完成，仅桌面冒烟，未做交互验证）、README/CHANGELOG/SPEC 已更新（Task 12）、
   `pub publish --dry-run` 待最终校验（Task 13）、**Task 14 真机验证部分完成**
   （2026-09-23，STG AL00 arm64 Android 12）：HLS 联网切档——加载后事件序列出现两次独立
   `MovaSizeChg`（伴随 `MovaBufferChg`/`MovaDurChg`/`MovaReady`），符合分辨率切换的真实
   信号，确认真实发生；Android PiP——`engine.pipSupported = true`、`enterPip() = true`、
   触发后收到 `MovaPipChg` 事件，`adb shell dumpsys activity` 确认
   `mIsInPictureInPictureMode=true`、`mWindowingMode=pinned`，**真机确认真实生效**。
   **仍未测**：手势手感（左亮度/右音量的实际触感，主观）、直播/时移 UI 交互、iOS 整体
   （本轮只有 Android 设备）。

**承自 fvideo（改名前）、排在 0.2.0 之后**——mova 就是 fvideo，遗留任务全部承接：

4. **二期 ffmpeg 瘦身（LGPL）——Android arm64-v8a 已定稿，未接入项目、未过真机播放**：
   自建 libmpv/ffmpeg 裁剪 demuxer/decoder，替换 `media_kit_libs_video`；构建卡 LGPL，
   避开 GPL-only 组件。**2026-08-06 在 WSL2 上跑通完整 `libmpv-android-video-build`
   构建链，产出真实 `libmpv.so` 并逐项实测验证**：从 media_kit 现状 11.80MiB 压到
   **6.61MiB（省 44%）**——依次叠加格式裁剪（去 VP8/VP9 软解）+ 编译器/链接器手段
   （`gc-sections`/`-Os`/`-fvisibility=hidden`/跨库 LTO/去 avfilter），逐项都有实测
   数字，不是理论估算。核验通过 MediaCodec 硬解 JavaVM 绑定符号
   （`mpv_lavc_set_java_vm`）、VP9 硬解符号。**构建配方（flavor 脚本、buildscripts
   补丁、CI）已迁到独立子工程 [../mova-libmpv/README.md](../mova-libmpv/README.md)
   （2026-08-13），完整技术清单与踩坑记录见该文件（"⭐ 2026-08-06 定稿结果"一节）；
   构建产物仍落在本工程 [tools/ffmpeg-slim/](tools/ffmpeg-slim/)（dist/ 下按平台
   分目录）**。mpv 构建选项完整盘点见
   [../mova-libmpv/doc/notes/2026-07-31-libmpv-slimming-options.md](../mova-libmpv/doc/notes/2026-07-31-libmpv-slimming-options.md)，
   ffmpeg 格式范围盘点见
   [../mova-libmpv/doc/notes/2026-07-31-ffmpeg-slimming-options.md](../mova-libmpv/doc/notes/2026-07-31-ffmpeg-slimming-options.md)
   （2026-08-13 起这两份调研笔记也迁到 `mova-libmpv` 了）。
   **尚未做的**：① 去掉 avfilter（`overlay`/`equalizer`）这一步**未过真机播放验证**，
   上线前必须实测 OSD/字幕合成/音频均衡是否受影响；② armv7l/x86/x86_64 三个架构
   还没构建，`--disable-runtime-cpudetect` 这类 arm64 专属优化**不能**照抄过去；
   ③ 还没接入 `media_kit_libs_android_video`（fork 该 libs 包或用 path override
   把预编译 jar 换成自建产物，方法见 README"与 media_kit 集成"一节）；④ 历史 Windows
   spike 数据（ffmpeg 单独 6.26MB，省 79%）已被本次 Android 真机数据取代，仅供参考，
   见 [../mova-libmpv/doc/plans/2026-07-31-ffmpeg-slim-build-windows.md](../mova-libmpv/doc/plans/2026-07-31-ffmpeg-slim-build-windows.md)。
   **字幕相关选项（libass/subrandr/uchardet）明确保留待定，不要关**——用户认为 mpv
   原生字幕渲染可能有用，等瘦身构建实测出体积数字后再权衡（与
   [doc/notes/2026-07-31-stt-subtitle-feasibility.md](doc/notes/2026-07-31-stt-subtitle-feasibility.md)
   的"Flutter 侧字幕组件 vs mpv 原生渲染"架构决策一并拍板）。**顺带待办**：自建时可直接
   导出一个轻量 FFI 抽帧函数（如 `vm_extract_thumbnail(uri, atMs, width) -> jpegBytes`，
   内部走 `libavformat`+`libswscale`），替换阶段 B 现在"开一个完整隐藏 `Player` 抽帧"的
   重量级方案（阶段 B 受限于 mpv `screenshot()` 不支持缩放，见
   [doc/plans/2026-07-31-phase-b-preview.md](doc/plans/2026-07-31-phase-b-preview.md) 附录 A）。
5. **iOS PiP 未实现——待定任务，每次启动请提醒用户此项未完成**：当前返回不支持
   （libmpv 纹理限制）。**可行性已调研,方向定为 `AVSampleBufferDisplayLayer` +
   `CVPixelBuffer`**（Android 是 Activity 级 PiP、无需取帧；iOS 必须自渲染取帧）；
   落地卡在一次**需 Mac + iOS 15+ 真机**的门槛 spike。研究 + 落地计划 + 渲染机制/性能
   澄清见 [doc/notes/2026-07-31-ios-pip-feasibility.md](doc/notes/2026-07-31-ios-pip-feasibility.md)。
   不需 Mac 也能先做的：跨平台"应用内悬浮窗"降级方案（阶段 3）。
6. **实时语音转文字字幕——可行性 + 音频抽取 spike + 动态加载调研均已完成；方向 2026-08-01
   倾向 whisper.cpp，待用户确认依赖后拆 Task**：方向是**各平台原生轻量抽取 API**（Android `MediaExtractor`+
   `MediaCodec`、iOS `AVAssetReader`）+ **平台原生 STT**（Android ML Kit / iOS
   `SFSpeechAudioBufferRecognitionRequest`，均系统自带、走原生插件代码，不算新依赖）+
   字幕叠层组件；PCM 抽取与 STT 调用同一次原生方法内完成，不过 Dart 侧。spike 验证过
   "起第二个 media_kit `Player` 用 `Media(start:,end:)` 分块"技术上可行，但双播放器
   CPU/内存翻倍，**已否决**，改走上述原生 API 路线。曾建议默认依赖 whisper.cpp，已
   推翻；曾评估 MCP 兜底转写，**已否决**（请求/响应协议非实时流式、延迟不可控，且与
   MCP 钩子"被动暴露上下文"的本职冲突）——缺口复用既有 `MovaVolumePort`/
   `CallbackVolumePort` 的注入模式给宿主一个通用 `MovaSttEngine` 口子即可，不专门补 MCP。
   完整调研 + spike 实测数据见
   [doc/notes/2026-07-31-stt-subtitle-feasibility.md](doc/notes/2026-07-31-stt-subtitle-feasibility.md)
   附录 A，回写见 [doc/PRD.md](doc/PRD.md) ADR。**macOS（无原生插件，需从零搭建）与
   Windows（SAPI/COM，无项目内先例）暂缓**，逐 Task 落地计划见 `doc/plans/`。AI MCP
   接入钩子（被动暴露上下文/接受指令，与字幕转写解耦）仍是纯架构预留，未评估、未排期。
   **⚠️ 2026-08-01 方向调整（覆盖上文"平台原生优先"）**：动态加载调研
   [doc/notes/2026-08-01-dynamic-loading.md](doc/notes/2026-08-01-dynamic-loading.md)
   厘清「引擎=代码 / 模型=数据」——whisper.cpp 引擎仅几 MB 随包，模型是数据、运行时下载、
   全平台合规（iOS 有官方 ODR/Background Assets）、天然满足"不内置模型"，**化解了此前对
   whisper.cpp 的两个顾虑**，方向倾向 whisper.cpp（四端统一、避开 Android ML Kit alpha 坑）；
   **引入 whisper.cpp 依赖仍需用户正式确认后才拆落地 Task**。

## 约定

- 结构分层：`lib/src/core/`（薄封装 media_kit/内核抽象，无 UI 依赖）与
  `lib/src/ui/`（组件树 `slots/`、皮肤 `skins/`、叶子组件 `components/`、
  手势层、`MovaPlayer` 门面）；新逻辑按层归位，别塞回 barrel。UI 层只准依赖
  `MovaApi` 抽象，不得直接触达 `MovaKernel`/media_kit。
- 注释：每个类/方法/函数都要注释，先英文后中文、空行分隔、简短；公开 API 带参数/返回/示例。
- 值对象的构造期不变量用 `assert`（release 下零成本，风险面只在开发者机器上）；运行时的
  可恢复错误一律走策略对象 + 事件回调，不许 `throw`。**注意 `const` 构造器的限制**：
  Dart 常量求值器只支持 num/String/bool 上的原生运算，`Duration` 的 `>`/`==`/
  `.inMicroseconds` 都不可用，在 `const` 构造器的初始化列表里写这类 assert 会让**每一处**
  `const` 调用点变成编译错误。这种情况改为公开一个 `assertValid()` 方法、由持有者在入口
  处调用（见 `MovaAdBreak.assertValid()`）。
- 校验用 `flutter analyze`（不用 build），除非要真跑 app。长机械改动先批量改、最后一次性校验。
- 手势侧别（0.3.0 起：左亮度/右音量，对齐 bilibili 等主流）经 `MovaGestConfig` 的
  侧别→动作映射（`leftVertical`/`rightVertical`/`horizontal` 取 `MovaGestAction`）配置，
  非写死；默认值即上述主流约定。（0.2.0 及之前是"左音量/右亮度"，已翻转，别按旧注释改回。）
- 新函数/模块配单测；纯逻辑（解析/ABR/映射/格式化）务必抽出来测，UI 用 WidgetTester。
- **完成一个 Task/里程碑并提交后，立刻用当次实测的 `flutter test` 输出更新 `CLAUDE.md` 与相关 `doc/plans/*.md` 里的测试基线数字。** 这个数字过时会让下一次规划文档（尤其是 Opus 拆的计划）从错误的起点开始推导任务数与验收标准，多次发生过。
- **真机验证前必须先设计基于真实事件的测量方法**（如 `renderEpoch`/`MovaDone` 事件戳），不用墙钟计时、不用临近素材 EOF 的 seek——这两种方法在本项目里已反复导致"测试工具自己的 bug 被误判为产品 bug"的返工。验收 demo 要为该功能单独建一个页面，不与其他 spike 混用；每次测量注意防缓存（URL 加 timestamp）、多次取平均。详见 `feedback_real_device_verification` 记忆。

## 落地工作流：Opus 拆方案 + Sonnet 落地

本项目验证有效的标准流程，新功能默认按此走：

1. **Opus 规划 agent**（只读探索 + 写文档，不动 `lib/`）把需求拆成 `doc/plans/<date>-<feature>.md`：架构决策、逐 Task 的文件改动、代码块、单测断言、验收标准、测试数量推进表。
2. 主 agent 把计划文档落盘到仓库。
3. **Sonnet（或 Opus，视复杂度）落地 agent** 按计划逐 Task 实现，每个 Task 一个 commit，`flutter analyze` 0 issues + `flutter test` 全绿再往下走。
4. 真机验证单独一轮，产出实测数字回写计划文档与 `feedback_real_device_verification`。

## 命令

```bash
flutter analyze
flutter test
cd example && flutter run -d windows        # 最快的实跑
flutter pub publish --dry-run
```

## Git

`dart-labs` 是 monorepo，mova 是子目录。`origin` 同时推 codeup 与 github(icodejoo/dart-labs)。
提交信息用 `type(scope): message`，scope 用 `mova`。装了 lefthook 钩子（本机若无 lefthook 会跳过）。
