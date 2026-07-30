# CLAUDE.md — videoman

在 videoman 子工程内工作时的指引。详见 [doc/PRD.md](doc/PRD.md)（需求/决策）、
[doc/SPEC.md](doc/SPEC.md)（架构/实现/命令/验证缺口）、[doc/ROADMAP.md](doc/ROADMAP.md)（里程碑）。

## 是什么

基于 media_kit（libmpv/ffmpeg）的 Flutter 视频播放插件，自研手势与控制层，
支持点播/直播，发布到 pub.dev。属于 `dart-labs` monorepo 的子工程。

## 当前状态（0.1.0）

一期 **P0–P7 全部完成**：内核封装、手势（左音量/右亮度/横滑进度/双击/双指缩放）、
点播/直播控制条、观看模式 contain/cover/fill、锁定/沉浸、全屏按宽高比定向、
HLS 清晰度提取/手动切换/缓冲 ABR 降档、Android 系统级 PiP、发布准备。
19 项单测全过，`flutter pub publish --dry-run` 0 warnings。

## 剩余任务（在此机器继续时先看 doc/SPEC.md 末节）

1. **二期 ffmpeg 瘦身（LGPL）——未开始**，唯一剩余大块。
2. **iOS PiP 未实现**（libmpv 纹理限制，当前返回不支持）。
3. **真机未验证**：迄今只有 Windows 桌面实跑 + Android APK 编译；手势手感、HLS 联网切档、Android PiP 实际行为、iOS 整体都需真机/模拟器验证。

## 约定

- 结构分层：`lib/src/core/`（薄封装 media_kit，无 UI）与 `lib/src/controls/`（自研 UI/手势）；新逻辑按层归位，别塞回 barrel。
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
