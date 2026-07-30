# fvideo

A Flutter video player built on [media_kit](https://pub.dev/packages/media_kit)
(libmpv/ffmpeg) with a self-built gesture + control layer for VOD and live
playback.

基于 [media_kit](https://pub.dev/packages/media_kit)（libmpv/ffmpeg 内核）的
Flutter 视频播放库，自研手势与控制层，支持点播与直播。

## Features / 功能

- **Gestures / 手势**：左半竖滑=音量、右半竖滑=亮度、横滑=进度、双击=快进退、双指=缩放，带 HUD 反馈。
- **Fill modes / 观看模式**：`contain` / `cover` / `fill` 循环切换。
- **Lock / 锁定**：一键锁定屏蔽全部交互（防误触），沉浸式观看。
- **Orientation / 方向**：全屏按视频宽高比自动横/竖屏。
- **Quality / 清晰度**：解析 HLS master 提取档位、手动切换、网络卡顿自动降档；"自动"档委托 libmpv 原生 ABR。
- **PiP / 画中画**：Android 系统级画中画（iOS/桌面暂不支持，见下）。
- **VOD & Live / 点播与直播**：两套控制条，直播禁用进度、支持"回到边缘"。

## Platform support / 平台支持

| | Android | iOS | Windows |
|---|:---:|:---:|:---:|
| 播放 / 手势 / 控制条 | ✅ | ✅ | ✅ |
| 画中画 PiP | ✅ | ❌ | ❌ |

> iOS/桌面 PiP：media_kit 用 libmpv 纹理渲染，系统级 PiP 依赖 AVPlayer 路径，暂未实现，`isPipSupported()` 返回 `false`。

## Install / 安装

```yaml
dependencies:
  fvideo: ^0.1.0
```

Android 要用画中画，需在 `AndroidManifest.xml` 的 Activity 上声明：

```xml
<activity
    android:name=".MainActivity"
    android:supportsPictureInPicture="true"
    android:configChanges="orientation|screenSize|screenLayout|smallestScreenSize|...">
```

## Usage / 用法

```dart
import 'package:flutter/material.dart';
import 'package:fvideo/fvideo.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FvideoController.ensureInitialized(); // 全局一次性初始化
  runApp(const MyApp());
}

class Page extends StatefulWidget {
  const Page({super.key});
  @override
  State<Page> createState() => _PageState();
}

class _PageState extends State<Page> {
  late final FvideoController controller;

  @override
  void initState() {
    super.initState();
    controller = FvideoController();
    controller.open(const FvideoSource(
      'https://example.com/master.m3u8',
      type: FvideoStreamType.live, // 或 FvideoStreamType.vod
      title: '示例',
    ));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FvideoPlayer(
      controller: controller,
      fit: FvideoFit.contain,
      gestureConfig: const FvideoGestureConfig(),
    );
  }
}
```

自定义手势侧别/开关：

```dart
const FvideoGestureConfig(
  leftVerticalVolume: true,      // 左侧竖滑=音量
  rightVerticalBrightness: true, // 右侧竖滑=亮度
  horizontalSeek: true,          // 横滑=进度
  doubleTapSeek: true,
  doubleTapStep: Duration(seconds: 10),
  pinchZoom: true,
);
```

## Roadmap / 路线图

见 [doc/ROADMAP.md](doc/ROADMAP.md)。二期计划自建**瘦身** libmpv/ffmpeg（仅主流点播/录播格式，构建卡 LGPL）替换官方 `media_kit_libs_video`。

## License

MIT
