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

## 当前状态（0.3.0）

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
- 校验用 `flutter analyze`（不用 build），除非要真跑 app。长机械改动先批量改、最后一次性校验。
- 手势侧别（0.3.0 起：左亮度/右音量，对齐 bilibili 等主流）经 `MovaGestConfig` 的
  侧别→动作映射（`leftVertical`/`rightVertical`/`horizontal` 取 `MovaGestAction`）配置，
  非写死；默认值即上述主流约定。（0.2.0 及之前是"左音量/右亮度"，已翻转，别按旧注释改回。）
- 新函数/模块配单测；纯逻辑（解析/ABR/映射/格式化）务必抽出来测，UI 用 WidgetTester。

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
