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
`feed_player.dart` 警告）。**真机验证未做**（计划 Task 12，见「剩余任务」第 0 条）。
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
[doc/SPEC.md](doc/SPEC.md)"无缝引擎切换"一节。**真机验证未做**（Task 11：黑屏是否真的
消除、中插续播点误差、内存/解码 session 三阶段采样、短广告降级路径，均需真机逐项验证）。

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
计划见
[doc/plans/2026-09-16-audio-only.md](doc/plans/2026-09-16-audio-only.md)、
[doc/SPEC.md](doc/SPEC.md)"仅音频模式"一节。**真机验证未做**（Task 5）。

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

**libmpv 瘦身产物的 CI/git 集成——进行中，2026-09-17 中途暂停，恢复时先读这条**：
目标是照抄 `media_kit_libs_android_video` 的思路（包本身不含二进制，构建时下载+校验），
但用户拍板改成**随包发布**（不做构建时下载，直接把编译产物随仓库/包分发，理由是内网
构建环境不应该依赖运行时联网下载）。为了让"随包发布"不至于把 `.git` 历史撑爆（实测
`mova/tools/ffmpeg-slim/dist/` 这条路径已经在历史里累积了 990 MiB，262 个 blob，且
`git clone` 会把这些历史版本全部下载下来），拍板方案是 **Git LFS**（本机已装
`git-lfs 3.7.1`，但 codeup/GitHub 是否都支持还没验证；用户已明确"不用管 codeup，它只是
备用仓"，可以只保证 GitHub 那份干净）。

**待恢复时按顺序做**：
1. 用 `git filter-repo`（已装，`pip install git-filter-repo`，不在 PATH，装在
   `C:\Users\jelon\AppData\Roaming\Python\Python314\Scripts\git-filter-repo.exe`）在一个
   **独立临时 clone**里（不要在主工作区/带 worktree 的仓库里直接跑，filter-repo 对多
   worktree 场景不友好）把 `mova/tools/ffmpeg-slim/dist/` 这条路径**从 GitHub main 的全部
   历史里剥离**，force push 回 GitHub（不动 codeup）。
2. 在同一次操作里，把**当前**的 `dist/` 内容重新加回去，这次用 `.gitattributes` +
   `git lfs track` 接管，之后的每次重建不再让 `.git` 历史线性增长。
3. 主工作区（`C:\workspace\dart-labs`）事后要 `fetch` + 对齐本地 `main`——**注意本地当时
   还有两个 worktree 分支**（若已合并进 main 则无影响；若还没合并，务必先合并/处理掉，
   否则它们的公共祖先提交哈希会因历史改写而"消失"，需要 `git rebase --onto` 才能续接）。
4. **CI 的"提交产物回 dist/"重试逻辑有 bug**（android-arm64/android-other-abi×3/darwin/
   linux/windows 五个 job 共用同一段脚本）：2026-09-17 windows job 实测复现——`git push`
   被拒后 `git fetch + git rebase origin/main`，但工作区不干净导致 `rebase` 直接报错退出
   （`cannot rebase: You have unstaged changes`）。根源和修法记在
   `mova-libmpv/README.md`「多平台进度」表 Windows 那一行。**这个 bug 要在改造成 LFS 之前
   或同时一起修**，不然 LFS 化之后这五个 job 还是会用同一套有 bug 的重试逻辑。
5. darwin(macOS) job 上次被我们主动 `gh run cancel` 打断（不是构建失败，只是编译到一半，
   这个 job 天然要 45-90 分钟+），下次重跑要给够时间，别提前取消。
6. LFS 化 + 历史清理都做完后，**重新触发一次全平台 CI**，确认全部 6 个 job（4 Android
   ABI + linux + windows；darwin 视时间预算决定是否一起跑）能在新的 LFS 流程下跑绿并正确
   提交。
7. **接线到 mova 实际构建**：现状 `example/android/app/build.gradle.kts` 已有
   `pickFirsts += "**/libmpv.so"` 的合并逻辑，但 `jniLibs/` 下的 `.so` 是手动拷贝的旧文件，
   跟 `dist/` 当前产物 MD5 对不上（已实测确认），说明这条集成从没被自动化同步过。LFS 化后
   要么写个脚本/Gradle task 把 `dist/<abi>/libmpv.so` 同步进 `jniLibs/`，要么直接让
   `jniLibs/` 本身也纳入 LFS 管理、CI 直接写到那个路径。iOS 侧同理（podspec 尚未接线）。

**0.5.0 广告编排增强——真机验证未做（Task 12，每次启动请提醒用户此项未完成）**：
Task 1–11 已完成。剩 Task 12 的真机 checklist（七组）：A 组等待就绪（前贴片默认不等
vs 中插默认等，需逐帧数黑屏帧数、跑 10 次取时延分布来验证 `adReadyTimeout` 5s 是否
合理）、B 组失败降级（坏 URL 在真机上到底以 `openThrew` 还是 `playerError` 报出来是
最值得看的发现点；黑洞 URL 下 `open()` 会不会永不返回）、C 组倒计时期间正片是否流畅
（双活解码，中低端机是最大风险）、D 组 pod 内只弹一次、E 组 `duration` 对超长素材是否
真的不卡死（这是"不依赖媒体时间轴"约束的反向验证）、F 组关闭态回归、G 组结论回写。
example 已建独立页 `AdOrchestrationDemoPage`（四个开关 + 真实回调打点的屏上事件日志，
无需 logcat）。计划见
[doc/plans/2026-09-16-ad-swap-enhancements.md](doc/plans/2026-09-16-ad-swap-enhancements.md)。

**0.4.x 仅音频模式——真机验证未做（Task 5，每次启动请提醒用户此项未完成）**：
Task 1–4 已完成（`renderHandle` 契约放宽、`MpvKernel` 不建视频管线、
`MovaEngine`/`createMovaEngine()` 透传、UI/swap 兼容护栏与文档）。剩 Task 5 的真机
checklist：纯音频源与带视频轨源的播放正确性（后者应只出声不出画）、三阶段
`dumpsys meminfo` 内存对账（视频 / 音频 / 释放后）、电量/CPU 量级抽查、
连播多轮看是否逐轮爬升（泄漏判据）、关闭态全 demo 回归。
**其中两项已在 Windows 桌面端提前拿到实测答案**（见笔记 §1.5）：① 内存——桌面 RSS
实测视频 197 MiB vs 音频 96 MiB，约 2.05×，**已如实回写笔记，把"两个数量级"的口径
更正为分项量级**；② `vid=no` 已直接确认（audio 模式 `size` 为 `0x0`）。
**但桌面 RSS 与移动端 `dumpsys meminfo` 不能直接类比**，移动端那笔账（MediaCodec/
纹理分栏）仍需真机重做。
**已就绪的前置**：`example/lib/audio_only_demo.dart`（独立 demo 页，带真实事件打点）
与 `example/lib/perf_probe_audio_only.dart`（RSS 探针，`--dart-define` 选模式）。
计划见 [doc/plans/2026-09-16-audio-only.md](doc/plans/2026-09-16-audio-only.md)。
另：`MovaAudioSkin`（封面/歌词/波形专用皮肤，第二档，约 6–8 Task）**明确不做**，
将来若确有需要再评估——当前用 `MovaPlayer.surface` 已够。

0. **0.4.0 无缝引擎切换——真机验证未做（Task 11，每次启动请提醒用户此项未完成）**：
   Task 1–10 已完成（配置面、`renderEpoch`、预热触发/就绪判据、`MovaSwapEngine` 骨架
   与原子切换、`MovaAdCtrl` 接入、清晰度切换契约测试、开放性对账、barrel/example/文档）。
   剩 Task 11 的真机 checklist：广告黑屏是否真的消除、中插续播点误差、切换瞬间音画是否
   有跳变、内存/解码 session 三阶段采样是否有泄漏、短广告降级路径、断网预热超时兜底。
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
   `pub publish --dry-run` 待最终校验（Task 13）、**真机一轮验证仍未做**（Task 14；
   手势手感、HLS 联网切档、Android PiP 实际行为、iOS 整体、直播/时移 UI；均承自 0.1.0
   仍未验证，且阶段 A 重构、预览、时移三块都从未上过真机）。

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
