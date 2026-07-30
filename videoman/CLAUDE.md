# CLAUDE.md — videoman

在 videoman 子工程内工作时的指引。详见 [doc/PRD.md](doc/PRD.md)（需求/决策）、
[doc/SPEC.md](doc/SPEC.md)（架构/实现/命令/验证缺口）、[doc/ROADMAP.md](doc/ROADMAP.md)（里程碑）。

## 是什么

基于 media_kit（libmpv/ffmpeg）的 Flutter 视频播放插件，自研手势与控制层，
支持点播/直播，发布到 pub.dev。属于 `dart-labs` monorepo 的子工程。

## 当前状态（0.2.0）

**阶段 A（core/ui 分层重构）已完成**：功能与 0.1.0 保持一致（零可见变化），架构
重写为 `VmApi`/`VmEngine`（取代 `VmController`，后者已 `@Deprecated`）+
`VmKernel` 内核抽象 + 组件树/皮肤/补丁（`VmComponent`/`VmSkin`/`VmDefaultSkin`/
`VmPatch`）+ 文案与主题外置（`VmStrings`/`VmTheme`，经 `VmOptions` 注入）+
拦截点（`VmInterceptor`）。`flutter analyze` 0 issues，测试全绿，
`flutter pub publish --dry-run` 0 warnings（详见 doc/SPEC.md）。

## 剩余任务（在此机器继续时先看 doc/SPEC.md 末节）

按 doc/DESIGN-0.2.0.md §12 的阶段划分：

1. **阶段 B：拖动预览缩略图——未开始**。`preview/` 全套（抽帧/缓存/网络策略）+
   `preview` 组件；第一步先实测 `screenshot-raw` 分辨率语义（DESIGN §7.3、§11 风险表）。
2. **阶段 C：直播时移——未开始**。`live/timeshift.dart` 窗口/behind 纯函数 +
   `liveBadge`/`timeshift`/`backToLive` 组件 + 手势门控。
3. **阶段 D：收尾——未开始**。README/CHANGELOG/example 三个 demo（VOD/直播/时移）、
   真机一轮验证（手势手感、HLS 联网切档、Android PiP 实际行为、iOS 整体，均承自
   0.1.0 仍未验证）、发布 0.2.0。

## 约定

- 结构分层：`lib/src/core/`（薄封装 media_kit/内核抽象，无 UI 依赖）与
  `lib/src/ui/`（组件树 `slots/`、皮肤 `skins/`、叶子组件 `components/`、
  手势层、`VmPlayer` 门面）；新逻辑按层归位，别塞回 barrel。UI 层只准依赖
  `VmApi` 抽象，不得直接触达 `VmKernel`/media_kit。
- 注释：每个类/方法/函数都要注释，先英文后中文、空行分隔、简短；公开 API 带参数/返回/示例。
- 校验用 `flutter analyze`（不用 build），除非要真跑 app。长机械改动先批量改、最后一次性校验。
- 手势侧别（左音量/右亮度）与 media_kit 内置相反且刻意为之，勿"修正"。
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
