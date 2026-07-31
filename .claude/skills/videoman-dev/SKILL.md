---
name: videoman-dev
description: 在 dart-labs/videoman 子工程继续开发 media_kit 视频播放库时使用——了解现状、core/ui 分层架构、约定、剩余任务（阶段 B 拖动预览、阶段 C 直播时移、二期 ffmpeg 瘦身、iOS PiP、真机验证）与验证/发布命令。当用户提到 videoman、视频播放器、media_kit、清晰度/ABR、画中画、手势播放器、组件树/皮肤，或要接着做 videoman 的剩余任务时触发。
---

# videoman 继续开发

`dart-labs/videoman` 是基于 media_kit（libmpv/ffmpeg）的 Flutter 视频播放库，
自研手势与控制层。**由 `fvideo` 改名而来 —— 同一个工程，fvideo 的全部遗留任务
都是 videoman 的任务，没有取消，只是排期。**

当前 **0.2.0 阶段 A（core/ui 架构重构）已完成并合入 main**。开工前先读：

- `videoman/doc/SPEC.md` — 当前架构、关键 API、DESIGN 与实现的偏差记录、**验证缺口**（最重要）
- `videoman/doc/DESIGN-0.2.0.md` — 0.2.0 架构设计（§7 拖动预览、§8 直播时移、§6 开放性契约）
- `videoman/doc/plans/` — 分阶段实现计划
- `videoman/doc/PRD.md` — 需求与决策记录（ADR）
- `videoman/doc/ROADMAP.md` — 里程碑勾选
- `videoman/CLAUDE.md` — 速览与约定

⚠️ DESIGN-0.2.0.md 部分内容在落地时发生偏差（见 SPEC.md 末节的偏差清单），
**以代码为准**，不要照着 DESIGN 的签名写。

## 已完成

- **0.1.0**：内核封装、手势（左音量/右亮度/横滑进度/双击/双指缩放 + HUD）、
  点播/直播控制条、contain/cover/fill、锁定/沉浸、全屏按宽高比定向、
  HLS 清晰度提取/手动切换/缓冲 ABR 降档、Android 系统级 PiP。
- **0.2.0 阶段 A**：重构为 `core/`（行为，零 Flutter 依赖）+ `ui/`（表现）；
  `VmApi`/`VmEngine`/`VmKernel`、sealed 事件表、四条流（events/states/progress/uiStates）、
  可寻址组件树 + `VmSkin` + `VmPatch` 补丁、`VmOptions`/`VmStrings`/`VmTheme` 全外置、
  `VmInterceptor` 四拦截点、`VmController` 降级为 `@Deprecated` 兼容门面。
  91 单测全过，`flutter analyze` 0 issues，`pub publish --dry-run` 0 warnings。

## 剩余任务

**0.2.0 内**（按 `doc/DESIGN-0.2.0.md` §12）：

1. **阶段 B — 拖动预览**：服务端雪碧图/WebVTT + libmpv 抽帧兜底 + 内存/磁盘两级缓存 +
   默认仅 WiFi。计划见 `doc/plans/2026-07-31-phase-b-preview.md`。
   ⚠️ 第一个 Task 是实测 spike：libmpv `screenshot-raw` 返回原始分辨率还是窗口分辨率，
   决定 `vf=scale` 抽帧缩放路线是否成立（DESIGN §11 首要风险）。
2. **阶段 C — 直播时移**：斗鱼式直播↔回看切换（HLS DVR 原生 seek + CDN 时移 URL 双模式）。
3. **阶段 D — 收尾**：README/CHANGELOG/example 三个 demo、`pub publish --dry-run`、真机一轮。

**承自 fvideo/0.1.0，排在 0.2.0 之后**：

4. **二期 ffmpeg 瘦身（LGPL）——未开始**：自建 libmpv/ffmpeg（借鉴 media_kit 仓库
   构建脚本，裁剪 demuxer/decoder，只留主流点播/录播格式），打成替换
   `media_kit_libs_video` 的自有 libs 包；构建**卡 LGPL**，避开 GPL-only 组件。
5. **iOS PiP 未实现**：当前返回不支持（libmpv 纹理限制）；评估
   AVSampleBufferDisplayLayer 方案或应用内悬浮窗降级。
6. **真机未验证**：迄今只有 Windows 桌面实跑 + Android APK 编译。手势手感、
   HLS 联网切档、Android PiP 实际行为、iOS 整体都没验过；阶段 A 重构本身也未上真机。

**阶段 A 遗留的小尾巴**：

- `VmApi` 缺同步的 PiP 能力查询 getter，导致 `PipButtonComponent` 在不支持的平台
  （桌面）渲染成死按钮（0.1.0 会隐藏）。临时规避：`VmPatch.remove('topBar/pipButton')`。
- `ios/videoman.podspec` 仍是 Flutter 模板占位元数据（`0.0.1` / `example.com` / `Your Company`）。

## 架构与约定

- 分层：`lib/src/core/`（行为，**禁 import `package:flutter/*`**；只有
  `core/kernel/mpv_kernel.dart` 可 import `package:media_kit/*`，由
  `test/core/purity_test.dart` 强制）+ `lib/src/ui/`（表现）+
  `lib/src/platform_impl/`（亮度/PiP/方向等平台实现，注入 core 的抽象端口）。
- UI → core 只走方法调用；core → UI 只走流。组件用 `VmSelector` 按字段订阅，防重建风暴。
- 新增用户可见决策必须齐**默认值 + 配置项 + 可注入策略**三件套（DESIGN §6 开放性契约）。
- 文案进 `VmStrings`、配色尺寸进 `VmTheme`，组件里不许出现字面量中文或 `Colors.xxx`。
- 注释先英后中、空行分隔；每个类/方法/字段都要有。
- 校验用 `flutter analyze`（非 build）；长机械改动批量改、末尾一次性校验。
- 手势左音量/右亮度是刻意设计（与 media_kit 内置相反），勿改回。

## 命令

```bash
cd videoman
flutter analyze
flutter test
cd example && flutter run -d windows              # 最快实跑
cd example && flutter run -d <android-emulator>   # 移动端手势
cd example && flutter build apk --debug           # 验原生 PiP 编译
flutter pub publish --dry-run
```

## Git

monorepo 子目录；`origin` 同推 codeup 与 github(icodejoo/dart-labs)。
提交 `feat(videoman): ...`。构建产物勿提交（根 `.gitignore` 有未锚定 `build/`）。
提交前有 code-review gate hook 拦截，需先 review 再 `-Action mark`。
