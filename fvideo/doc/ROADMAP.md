# fvideo 功能清单与里程碑

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
- [x] **P1** 内核封装（FvideoController / FvideoSource）
- [x] **P2** 手势层 + HUD（FvideoGestureDetector / FvideoPlayer）
- [x] **P3** 观看模式（#5）+ 锁定/沉浸（#4）+ 点播/直播控制条
- [x] **P4** 方向与全屏（#3）：全屏切换 + 按宽高比定向 + 尺寸流自动重定向 + autoOrientation 开关
- [x] **P5** 清晰度提取 / 手动切换 / ABR 自适应（#2）：HLS master 解析、手动切档（保位续播）、缓冲卡顿降档；"自动"档委托 libmpv 原生 ABR
- [x] **P6** 画中画 PiP（#1）：Android 系统级 PiP（ActivityAware + PictureInPictureParams，宽高比钳制）；iOS/桌面返回不支持（见风险），按钮仅在支持平台显示
- [x] **P7** 发布准备：README、CHANGELOG、LICENSE(MIT)、pubspec 元数据/topics、example 源切换、`pub publish --dry-run` 通过
- [ ] **二期** ffmpeg 瘦身（LGPL）

## 技术风险（需评估/决策）

- **iOS PiP**：media_kit 用 libmpv 纹理渲染，系统级 PiP（`AVPictureInPictureController`）依赖 AVPlayer/`AVSampleBufferDisplayLayer`，libmpv 纹理路径接系统 PiP 很困难。iOS 端可能只能降级为“应用内悬浮窗”。Android 系统 PiP 相对可行。
- **手动清晰度切换**：libmpv 对 HLS/DASH 的自适应是内置的；手动锁定某一档需解析 master playlist 或操作 libmpv 属性（如 track/bitrate 选择），可行性待验证。
- **自动旋转**：依赖设备传感器与原生方向监听。
