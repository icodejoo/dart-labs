# videoman 产品需求（PRD）

## 定位

基于 [media_kit](https://pub.dev/packages/media_kit)（libmpv/ffmpeg 内核）的
Flutter 视频播放库，自研手势与控制层，最终发布到 pub.dev。面向
android / ios / windows。作为 `dart-labs` monorepo 的子工程存在。

## 内核选型（已定）

- **播放内核**：直接依赖封装 media_kit + media_kit_video（不 fork）。它就是 libmpv/ffmpeg，跨全平台、自带控制条。
- **不用 chewie**：chewie 绑死 video_player，接 media_kit 要套 `video_player_media_kit` 转接层且能力受限；仅借鉴其 API 形态。
- **UI 自研**：内置控制条侧别写死、无缩放、不分直播点播，满足不了需求，故控制条/手势自研（借鉴 universal_video_controls 结构、media_kit 内置手势数学）。

## 功能需求

1. **手势**：左半竖滑=亮度、右半竖滑=音量、横滑=进度、双击左右=快退/快进、双指=缩放；直播禁用进度类；HUD 反馈。
   - media_kit 内置侧别写死不可配，是自研主因。（0.3.0 起我方侧别→动作可配，默认
     左亮度/右音量对齐主流；此前 0.1.0/0.2.0 为左音量/右亮度，已翻转。）
2. **观看模式**：contain / cover / fill 循环切换。
3. **锁定/解锁**：锁定屏蔽全部手势与控制条，防误触；沉浸式观看。
4. **方向**：自动读取视频宽高；全屏按宽高比自动横/竖屏；跟随设备自动旋转。
5. **清晰度**：从流（HLS master）提取多档；手动指定；网络波动自动升/降（ABR）。
6. **画中画（PiP）**：Android 系统级；iOS 见风险。
7. **点播/直播**：两套控制条，直播无进度条、有 LIVE 标记与"回到边缘"。

## 平台

android / ios / windows。（web/macos/linux media_kit 都支持，未纳入本期脚手架。）

## 非功能需求 / 决策记录（ADR）

- **发布**：对外发布到 pub.dev，MIT 许可。
- **二期 ffmpeg 瘦身**：一期用官方 `media_kit_libs_video`（完整包）；二期自建 libmpv/ffmpeg，仅保留主流点播/录播格式并瘦身，替换官方 libs。
- **许可**：二期构建**卡 LGPL**（避开 GPL-only 组件，否则传染下游、违背"对外发布不作限制"的意图）。
- **iOS PiP 降级**：media_kit 用 libmpv 纹理渲染，系统级 PiP 依赖 AVPlayer 路径，暂不实现；`isPipSupported()` 返回 false。后续如需，评估 AVSampleBufferDisplayLayer 方案或应用内悬浮窗降级。
- **手动清晰度**：libmpv 对 HLS 自适应内置；手动锁档采用"解析 master playlist + 打开指定变体 URL"方案，未走 libmpv 属性。
- **实时语音转文字字幕（条件性未来项，非当前承诺）**：若 media_kit/libmpv/ffmpeg 侧具备可行的
  音频抽取或 STT 接入路径（候选：端侧模型经 FFI、云端 STT API、未来的
  ffmpeg/whisper.cpp 集成点），videoman 应支持对音轨做实时转写并以字幕/字幕叠层形式
  展示。**这不是排入某个阶段的开发计划**，仅记录产品意图，是否做、怎么做取决于后续对
  后端可行性的评估结论；评估结论应回写本条并转化为具体阶段任务。
- **AI MCP（Model Context Protocol）集成钩子（预留，非当前承诺）**：架构上为未来能力预留
  空间——播放器可能需要向 MCP 连接的 AI agent 暴露上下文（如当前字幕文本、播放状态），
  或接收其下发的指令。同样是前瞻性预留，不代表已排期实现；目前只要求架构不把这条路堵死。

## 范围与优先级

- **一期（已完成）**：内核封装 + 手势 + 控制条 + 观看模式 + 锁定/沉浸 + 方向/全屏 + 清晰度/ABR + Android PiP + 发布准备（0.1.0）。
- **二期（未开始）**：ffmpeg 瘦身（LGPL）。
- **待补**：iOS PiP、真机验证（见 SPEC 的验证缺口）。
