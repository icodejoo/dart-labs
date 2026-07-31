# CLAUDE.md — videoman

在 videoman 子工程内工作时的指引。详见 [doc/PRD.md](doc/PRD.md)（需求/决策）、
[doc/SPEC.md](doc/SPEC.md)（架构/实现/命令/验证缺口）、[doc/ROADMAP.md](doc/ROADMAP.md)（里程碑）。

> **换机器接手先读这三条**
>
> 1. **构造 engine 一律用 `createVmEngine()`**（`lib/src/platform_impl/wiring.dart`，已从
>    barrel 导出），**不要直接 `VmEngine()`**——后者的平台端口默认是 noop，会导致亮度手势
>    不生效、`enterPip()` 恒 false、全屏不转屏。`VmEngine()` 保留裸构造只为单测注入假端口。
> 2. **[doc/DESIGN-0.2.0.md](doc/DESIGN-0.2.0.md) 有约 10 处已过期**（阶段 A 落地后未回写：
>    kernel 签名、`VmState.sourceTitle`、`VmApi.renderHandle`、`VmAbrPolicy` 落点、
>    sha1→FNV-1a，以及 4 处为守住 core 纯净性而必须挪到 `platform_impl/` 的结构调整）。
>    **设计意图看 DESIGN，签名与落点一律以代码和 [doc/SPEC.md](doc/SPEC.md) 末节为准。**
> 3. **阶段 B/C/D 的逐 Task 实现计划已就绪**，见 [doc/plans/](doc/plans/)。计划已按上述
>    两点对齐过，可直接按 Task 顺序执行。

## 是什么

基于 media_kit（libmpv/ffmpeg）的 Flutter 视频播放插件，自研手势与控制层，
支持点播/直播，发布到 pub.dev。属于 `dart-labs` monorepo 的子工程。

## 当前状态（0.2.0）

**阶段 A（core/ui 分层重构）已完成**：功能与 0.1.0 保持一致（零可见变化），架构
重写为 `VmApi`/`VmEngine`（取代 `VmController`，后者已 `@Deprecated`）+
`VmKernel` 内核抽象 + 组件树/皮肤/补丁（`VmComponent`/`VmSkin`/`VmDefaultSkin`/
`VmPatch`）+ 文案与主题外置（`VmStrings`/`VmTheme`，经 `VmOptions` 注入）+
拦截点（`VmInterceptor`）。

**阶段 B（拖动预览缩略图）已完成**：`VmApi.preview`/`VmOptions.preview`/
`VmPreviewBlocked` 三个新公开面，WebVTT 雪碧图 + libmpv 抽帧兜底的有序来源链，
内存+磁盘两级缓存，`connectivity_plus` 网络策略，`PreviewComponent` 气泡
（水平位置随拖动比例跟随）。

**阶段 C（直播时移）已完成**：`VmLiveConfig` 新增 `urlBuilder`/`backToLive`/
`autoBackToLiveOnStall`/`windowResolver`；`lib/src/core/live/timeshift.dart`
纯函数 `resolveWindow`/`behindOf`/`atLiveEdge`；`VmState.timeshiftBehind` 真正
写入并伴随 `VmTimeshiftChanged`/`VmLiveEdgeReached` 事件；`backToLiveEdge()`
从占位（`reload()`）变为按策略执行；新增 `VmApi.pipSupported`/
`VmState.pipSupported`，PiP 按钮在不支持的平台自动隐藏；直播底栏加
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

**承自 fvideo（改名前）、排在 0.2.0 之后**——videoman 就是 fvideo，遗留任务全部承接：

4. **二期 ffmpeg 瘦身（LGPL）——未开始**：自建 libmpv/ffmpeg 裁剪 demuxer/decoder，
   替换 `media_kit_libs_video`；构建卡 LGPL，避开 GPL-only 组件。**顺带待办**：自建时
   可直接导出一个轻量 FFI 抽帧函数（如 `vm_extract_thumbnail(uri, atMs, width) -> jpegBytes`，
   内部走 `libavformat`+`libswscale`），替换阶段 B 现在"开一个完整隐藏 `Player` 抽帧"的
   重量级方案（阶段 B 受限于 mpv `screenshot()` 不支持缩放，见
   [doc/plans/2026-07-31-phase-b-preview.md](doc/plans/2026-07-31-phase-b-preview.md) 附录 A）。
5. **iOS PiP 未实现**：当前返回不支持（libmpv 纹理限制）；评估
   AVSampleBufferDisplayLayer 或应用内悬浮窗降级。
6. **实时语音转文字字幕 + AI MCP 接入预留——排在阶段 B/C/D 之后、视 STT 后端可行性而定**：
   见 [doc/PRD.md](doc/PRD.md) ADR 与 [doc/SPEC.md](doc/SPEC.md) 未来项小节。字幕为条件性
   未来项（是否做取决于 media_kit/libmpv/ffmpeg 侧能否提供可行的 STT 接入路径），MCP 为
   架构预留钩子；均未排入具体阶段，不是当前开发计划。

## 约定

- 结构分层：`lib/src/core/`（薄封装 media_kit/内核抽象，无 UI 依赖）与
  `lib/src/ui/`（组件树 `slots/`、皮肤 `skins/`、叶子组件 `components/`、
  手势层、`VmPlayer` 门面）；新逻辑按层归位，别塞回 barrel。UI 层只准依赖
  `VmApi` 抽象，不得直接触达 `VmKernel`/media_kit。
- 注释：每个类/方法/函数都要注释，先英文后中文、空行分隔、简短；公开 API 带参数/返回/示例。
- 校验用 `flutter analyze`（不用 build），除非要真跑 app。长机械改动先批量改、最后一次性校验。
- 手势侧别（0.3.0 起：左亮度/右音量，对齐 bilibili 等主流）经 `VmGestureConfig` 的
  侧别→动作映射（`leftVertical`/`rightVertical`/`horizontal` 取 `VmGestureAction`）配置，
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

`dart-labs` 是 monorepo，videoman 是子目录。`origin` 同时推 codeup 与 github(icodejoo/dart-labs)。
提交信息用 `type(scope): message`，scope 用 `videoman`。装了 lefthook 钩子（本机若无 lefthook 会跳过）。
