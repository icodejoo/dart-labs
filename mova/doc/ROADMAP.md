# mova 功能清单与里程碑

基于 media_kit（libmpv/ffmpeg 内核）的 Flutter 视频播放库，自研手势与控制层。
面向 android / ios / windows，最终发布到 pub.dev。

## 功能清单

### 播放内核
- media_kit + media_kit_video（libmpv/ffmpeg），点播 / 直播。
- 二期：自建**瘦身** libmpv/ffmpeg（仅主流点播/录播格式），构建卡 **LGPL**。

### 手势交互
- 左半竖滑=音量、右半竖滑=亮度、横滑=进度、双击左右=快退/快进、双指=缩放。
- 直播态自动禁用进度类手势。
- HUD 反馈（音量/亮度/进度）。

### 观看模式（#5）
- `contain` / `cover` / `fill` 三种画面填充模式，可切换。

### 锁定与沉浸（#4）
- 锁定/解锁：锁定后屏蔽全部手势与控制条，防误触。
- 沉浸式观看（隐藏系统栏）。

### 方向与全屏（#3）
- 自动读取视频宽高（`player.state.width/height`）。
- 按宽高比在初始化时自动选择横屏/竖屏播放。
- 自动旋转跟随设备。
- 全屏切换。

### 清晰度与自适应（#2）
- 从视频流（HLS master playlist 等）提取多档清晰度。
- 手动指定清晰度。
- 检测网络波动，自动升/降清晰度（ABR）。

### 画中画（#1）
- Android 系统级 PiP（PictureInPictureParams）。
- iOS PiP（见技术风险）。

### 控制条
- 点播控制条：进度条、播放/暂停、倍速、全屏、清晰度、观看模式、锁定入口。
- 直播控制条：LIVE 标记、回到直播边缘、无可拖动进度。
- 单击切换控制条显隐。

## 里程碑

- [x] **P0** 工程结构（core / controls 分层）
- [x] **P1** 内核封装（MovaCtrl / MovaSource）
- [x] **P2** 手势层 + HUD（MovaGestDetect / MovaPlayer）
- [x] **P3** 观看模式（#5）+ 锁定/沉浸（#4）+ 点播/直播控制条
- [x] **P4** 方向与全屏（#3）：全屏切换 + 按宽高比定向 + 尺寸流自动重定向 + autoOrientation 开关
- [x] **P5** 清晰度提取 / 手动切换 / ABR 自适应（#2）：HLS master 解析、手动切档（保位续播）、缓冲卡顿降档；"自动"档委托 libmpv 原生 ABR
- [x] **P6** 画中画 PiP（#1）：Android 系统级 PiP（ActivityAware + PictureInPictureParams，宽高比钳制）；iOS/桌面返回不支持（见风险），按钮仅在支持平台显示
- [x] **P7** 发布准备：README、CHANGELOG、LICENSE(MIT)、pubspec 元数据/topics、example 源切换、`pub publish --dry-run` 通过
- [x] **二期** ffmpeg 瘦身（LGPL）：Android arm64-v8a 定稿并接入（6.55MiB，AV1 硬解+
      软解双通道，2026-08-06 真机验证 H.264/HEVC/VP9/AV1 通过），详见
      [tools/ffmpeg-slim/README.md](../tools/ffmpeg-slim/README.md)。armeabi-v7a/
      x86/x86_64 及 iOS/macOS/Windows/Linux 仍是 TODO（同一份 README 的"多平台进度"
      表跟踪）；字幕渲染/截图/HLS-FLV直播/avfilter回归/后台中断/AV1高码率场景这 6 项
      真机功能检查也还没测完（同 README"真机测试"一节），不阻塞标记本阶段完成。
- [ ] **三期** 语音转字幕（STT）：`ZipformerSttEngine` 本身已验证（2026-08-05，Windows
      桌面用真实模型+官方测试 wav 跑通，识别效果正确；Android 真机上验证时踩过两个坑，
      未复测确认稳定，见下方笔记）。**但"打开视频、实时出字幕"这个端到端场景做不出来
      ——`MovaSttEngine.feed()` 从没有任何调用点，从播放中的视频抽音频喂给引擎这条链路
      完全没实现**，是比"验证引擎"更大的一块独立工作。**外挂字幕文件（视频自带字幕）
      功能也完全没有**——`MovaSttApi` 只有实时识别一条路，没有"加载已有字幕文件"的接口，
      需要新设计 API 形状。批量预转写（点播一次性转写缓存字幕文件）依赖二期 ffmpeg 瘦身
      产出的自建 ffmpeg + FFI 绑定——mpv `ao=pcm` 音频抽取方案真机实测失败且被证实是已知
      不可靠的老驱动，绕开 media_kit 直接 FFI 调 ffmpeg 也没有现成可用的库。详见
      [doc/notes/2026-08-04-stt-engine-decision.md](notes/2026-08-04-stt-engine-decision.md)。

## 技术风险（需评估/决策）

- **iOS PiP**：media_kit 用 libmpv 纹理渲染，系统级 PiP（`AVPictureInPictureController`）依赖 AVPlayer/`AVSampleBufferDisplayLayer`，libmpv 纹理路径接系统 PiP 很困难。iOS 端可能只能降级为“应用内悬浮窗”。Android 系统 PiP 相对可行。
- **手动清晰度切换**：libmpv 对 HLS/DASH 的自适应是内置的；手动锁定某一档需解析 master playlist 或操作 libmpv 属性（如 track/bitrate 选择），可行性待验证。
- **自动旋转**：依赖设备传感器与原生方向监听。
- **清晰度切换非真正无缝（bilibili 式秒切）——独立方向，未评估工程量**（2026-08-05
  记录）：真机实测确认 `setVideoTrack` 切档比重开变体 URL 快，但点击瞬间会暂停、约 1
  秒后 loading 才恢复，不是无感切换（见
  [doc/plans/2026-08-04-quality-native-tracks-spike.md](plans/2026-08-04-quality-native-tracks-spike.md)
  附录）。查过 playora 源码（`lib/src/core/controller.dart`）：其原生平台的
  `selectQuality` 对嵌入 HLS 轨道调用的也是同一个 `player.setVideoTrack(track)`，**没有
  任何预缓冲/延迟切换处理**——playora 唯一做到真正无缝的是 Web 平台，走浏览器 hls.js
  的 level 切换（MSE 原生支持分段级多码率无缝切换，与 mpv 无关）。也查过
  bilibili 官方开源播放器 ijkplayer（`bilibili/ijkplayer`）：它是 FFmpeg/ffplay 分支，
  与 mpv 同属直接封装 `libavformat`/`libavcodec` 的架构，用的是**同一套** FFmpeg HLS
  demuxer——demuxer 对码率切换是懒加载模型（切换时才按当前位置现抓新码率分段+重建
  解码器），不会像 ExoPlayer/hls.js 那样并行预取候选码率分段，因此**架构上与 mpv
  面临同一个限制**，不是能直接复用来解决问题的现成代码。真正实现了分段级无缝切换的是
  Google 官方开源的 **ExoPlayer/Media3**（Android，Apache 2.0）和 iOS 系统自带的
  `AVPlayer`（HLS 自适应是 OS 原生能力）。**用户澄清：不是要换内核，是要借鉴这类
  播放器"预取好了再切"的思路，在现有 media_kit 架构上实现类似效果**——复杂度预研见
  [doc/notes/2026-08-05-seamless-quality-switch-feasibility.md](notes/2026-08-05-seamless-quality-switch-feasibility.md)：
  可行，思路是复用项目里已验证过的"影子引擎预热+热切换"模式（同构于 feed 引擎池的
  `spike_dual_engine.dart` 内存实测），量级接近阶段 B/C（15/9 Task），核心风险是
  真机预热阈值调参而非能不能做。**尚未拍板是否投入，未拆 Task。**
