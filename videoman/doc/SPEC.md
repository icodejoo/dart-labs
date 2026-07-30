# videoman 技术规格（SPEC）

配套阅读：[PRD.md](PRD.md)（需求/决策）、[ROADMAP.md](ROADMAP.md)（里程碑）。

## 架构分层

```
lib/
├─ videoman.dart                      # 对外唯一入口 barrel
├─ videoman_platform_interface.dart   # 平台通道接口（getPlatformVersion / isPipSupported / enterPip）
├─ videoman_method_channel.dart       # MethodChannel 实现（PlatformException/MissingPlugin → false）
└─ src/
   ├─ core/                         # 内核层：薄封装 media_kit，无 UI
   │  ├─ controller.dart     # VmController：open/play/pause/seek/volume/rate/reload/dispose
   │  │                             #   + 清晰度 loadQualities/switchQuality/downshiftQuality（dart:io 拉 master）
   │  │                             #   + PiP isPipSupported/enterPip（委托 platform interface）
   │  ├─ source.dart         # VmSource + VmStreamType(vod/live)
   │  ├─ config.dart         # VmGestureConfig（手势侧别/开关）+ VmFit(contain/cover/fill, .next/.label)
   │  ├─ quality.dart               # VmQuality + parseHlsMasterPlaylist（纯函数，可测）
   │  └─ abr.dart                   # BufferingAbr：缓冲上升沿计数降档（纯逻辑，可测）
   └─ controls/                     # UI 层：自研控制条/手势
      ├─ player.dart         # VmPlayer 主组件；vmBoxFit()/preferredOrientationsFor() 公开纯函数
      ├─ gesture_layer.dart         # VmGestureDetector：原始手势→意图，不碰播放状态
      ├─ controls_common.dart       # formatDuration / ControlIconButton / ControlGradientBar
      ├─ vod_controls.dart          # VodControls：进度条+播放暂停+清晰度/填充/全屏/锁定/PiP
      └─ live_controls.dart         # LiveControls：LIVE 标记 + 回到边缘 + 同上操作
android/src/main/kotlin/.../VideomanPlugin.kt  # 原生 PiP：ActivityAware + enterPictureInPictureMode
```

Slint 无关；纯 Flutter/Dart + 少量 Kotlin。

## 关键 API 与不变式

- `VmController.ensureInitialized()`：`MediaKit.ensureInitialized()`，进程内一次。
- `VmController.seek()` 在 `isLive` 时**忽略**（直播不可拖）；直播"回到边缘"用 `reload()`（重开源）。
- `VmPlayer` 组合 `Video(controls: NoVideoControls, fit: vmBoxFit(_fit))` + `Transform.scale`（缩放）+ 手势层 + 控制条 + 锁定遮罩；控制条**仅顶/底两条**可点击，中间透传给手势层。

## 手势数学（gesture_layer.dart）

- 轴向锁定阈值 `_kAxisLockThreshold = 8px`；判定后本次拖动锁定模式。
- 横滑进度：`seconds = dx / width * 90`（满屏宽=90s）；直播禁用。
- 竖滑：`frac = -dy / height`；左侧 → 音量 `start + frac*100`（0–100），右侧 → 亮度 `start + frac`（0–1）。
- 双指：`onScaleUpdate.pointerCount>=2` 进入 zoom，emit `scale`；父层 `_zoom=(_baseZoom*scale).clamp(1,maxZoom)`，end 固化。
- 双击：`onDoubleTapDown` 记录 x 判左右，`± doubleTapStep`。
- 亮度用 `screen_brightness`（`application` 读、`setApplicationScreenBrightness` 写）；平台不支持时兜底 1.0。

## 清晰度 / ABR

- `parseHlsMasterPlaylist(content, base)`：扫 `#EXT-X-STREAM-INF`，取下一非注释行为变体 URI，解析 BANDWIDTH/RESOLUTION，相对路径按 base 解析；"自动"档在首位，其余按分辨率从高到低。非 master 返回 `[]`。
- `switchQuality(q)`：`q.isAuto` 打开源 URL（libmpv 自适应），否则打开变体 URL；保留播放态，点播下保位续播。
- `BufferingAbr.add(buffering)`：仅计 false→true 上升沿；达 `threshold`（默认 3）返回一次 true 触发 `downshiftQuality()` 并重置。**自动档不降档**（交给 libmpv）。

## PiP（原生）

- Dart：`isPipSupported()` / `enterPip({width,height})`，异常→false。
- Android `VideomanPlugin.kt`：`ActivityAware` 拿 Activity；`isPipSupported` = SDK≥26 且设备有 `FEATURE_PICTURE_IN_PICTURE`；`enterPip` 用 `PictureInPictureParams`，宽高比 `clamp(0.42,2.39)`。
- **宿主 App 要求**：Activity 声明 `android:supportsPictureInPicture="true"` 且 `configChanges` 含 orientation|screenSize|screenLayout|smallestScreenSize（example 已配）。
- iOS/桌面：未处理 → notImplemented → Dart 侧 false。

## 方向

- `preferredOrientationsFor(w,h)`：宽≥高横屏（双向），否则竖屏。
- 订阅 `player.stream.width/height`，全屏且 `autoOrientation` 时按最新尺寸重定向；退出全屏恢复 `DeviceOrientation.values`。
- 锁定或全屏 → `SystemUiMode.immersiveSticky`；否则 `edgeToEdge`。

## 测试（19 项）

- `test/gesture_layer_test.dart`：音量/亮度/进度提交/直播禁用（WidgetTester dragFrom，注意需铺满视窗 + `pumpAndSettle` 排空双击计时器）。
- `test/fit_and_format_test.dart`：VmFit.next/label、vmBoxFit、preferredOrientationsFor、formatDuration。
- `test/quality_abr_test.dart`：parseHlsMasterPlaylist、BufferingAbr 上升沿/阈值。
- `test/method_channel_test.dart`：getPlatformVersion 桩。

## 命令

```bash
flutter analyze                                   # 校验（用 analyze，不用 build）
flutter test                                      # 单测
cd example && flutter run -d windows              # 桌面实跑（快）
cd example && flutter run -d <android-emulator>   # 移动端手势验证
cd example && flutter build apk --debug           # 验 Android 原生 PiP 编译
flutter pub publish --dry-run                     # 发布校验（当前 0 warnings）
```

## 剩余任务与验证缺口（在另一台电脑继续时优先看这里）

1. **二期 ffmpeg 瘦身（LGPL）——未开始**：自建 libmpv/ffmpeg（借鉴 media_kit 仓库构建脚本，裁剪 demuxer/decoder），打成替换 `media_kit_libs_video` 的自有 libs 包；构建卡 LGPL。
2. **iOS PiP——未实现**：当前返回 false。评估 AVSampleBufferDisplayLayer 或应用内悬浮窗降级。
3. **真机验证缺口**：迄今仅 Windows 桌面实跑 + Android APK 编译。**未验证**：真机手势手感（尤其双指缩放、灵敏度）、HLS 联网切档与 ABR 实际行为、Android PiP 实际进入/退出、iOS 端整体播放与手势。建议先起 Pixel 模拟器跑一轮。
4. **清晰度局限**：手动切档依赖 HLS master；纯 mp4/单码率源无档位（预期）。
5. **HUD/控制条细节**：倍速切换、清晰度"自动"回升未做；控制条为基础版，可继续打磨。
