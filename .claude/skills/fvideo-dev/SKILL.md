---
name: fvideo-dev
description: 在 dart-labs/fvideo 子工程继续开发 media_kit 视频播放库时使用——了解现状、架构、约定、剩余任务（二期 ffmpeg 瘦身、iOS PiP、真机验证）与验证/发布命令。当用户提到 fvideo、视频播放器、media_kit、清晰度/ABR、画中画、手势播放器，或要接着做 fvideo 的剩余任务时触发。
---

# fvideo 继续开发

`dart-labs/fvideo` 是基于 media_kit（libmpv/ffmpeg）的 Flutter 视频播放库，
自研手势与控制层。一期 0.1.0 已完成。开工前先读工程内的三份文档：

- `fvideo/doc/PRD.md` — 需求与决策记录（ADR）
- `fvideo/doc/SPEC.md` — 架构、关键 API、手势数学、清晰度/ABR/PiP 实现、**验证缺口**
- `fvideo/doc/ROADMAP.md` — 里程碑勾选
- `fvideo/CLAUDE.md` — 速览与约定

## 已完成（0.1.0）

内核封装、手势（左音量/右亮度/横滑进度/双击/双指缩放 + HUD）、点播/直播控制条、
观看模式 contain/cover/fill、锁定/沉浸、全屏按宽高比定向、HLS 清晰度提取/手动切换/
缓冲 ABR 降档、Android 系统级 PiP、发布准备。19 单测全过，`pub publish --dry-run` 0 warnings。

## 剩余任务（优先级从高到低）

1. **真机验证**（成本最低、收益高）：起 Android 模拟器（`flutter emulators --launch <id>`）跑 example，
   验手势手感、HLS 联网切档与 ABR、Android PiP 实际进入/退出；再验 iOS 整体。
2. **二期 ffmpeg 瘦身（LGPL）**：自建 libmpv/ffmpeg（借鉴 media_kit 仓库构建脚本，裁剪
   demuxer/decoder，只留主流点播/录播格式），打成替换 `media_kit_libs_video` 的自有 libs 包；
   构建**卡 LGPL**，避开 GPL-only 组件。
3. **iOS PiP**：当前返回不支持；评估 AVSampleBufferDisplayLayer 方案或应用内悬浮窗降级。
4. 打磨：倍速切换、清晰度"自动"回升、控制条细节。

## 约定

- 分层：`lib/src/core/`（无 UI）与 `lib/src/controls/`（自研 UI/手势）；纯逻辑抽出可测。
- 注释先英后中、空行分隔、简短；公开 API 带参/返回/示例。
- 校验用 `flutter analyze`（非 build）；长机械改动批量改、末尾一次性校验。
- 手势左音量/右亮度是刻意设计（与 media_kit 内置相反），勿改回。

## 命令

```bash
cd fvideo
flutter analyze
flutter test
cd example && flutter run -d windows              # 最快实跑
cd example && flutter run -d <android-emulator>   # 移动端手势
cd example && flutter build apk --debug           # 验原生 PiP 编译
flutter pub publish --dry-run
```

## Git

monorepo 子目录；`origin` 同推 codeup 与 github(icodejoo/dart-labs)。
提交 `feat(fvideo): ...`。构建产物勿提交（根 `.gitignore` 有未锚定 `build/`）。
