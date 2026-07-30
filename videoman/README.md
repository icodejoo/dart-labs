# videoman

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
  videoman: ^0.2.0
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
import 'package:videoman/videoman.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  VmEngine.ensureInitialized(); // 全局一次性初始化
  runApp(const MyApp());
}

class Page extends StatefulWidget {
  const Page({super.key});
  @override
  State<Page> createState() => _PageState();
}

class _PageState extends State<Page> {
  late final VmEngine engine;

  @override
  void initState() {
    super.initState();
    engine = VmEngine();
    engine.open(const VmSource(
      'https://example.com/master.m3u8',
      type: VmStreamType.live, // 或 VmStreamType.vod
      title: '示例',
    ));
  }

  @override
  void dispose() {
    engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VmPlayer(api: engine); // 默认皮肤 VmDefaultSkin
  }
}
```

自定义手势侧别/开关，通过 `VmOptions` 传入 `VmEngine`：

```dart
final engine = VmEngine(
  options: const VmOptions(
    gesture: VmGestureConfig(
      leftVerticalVolume: true,      // 左侧竖滑=音量
      rightVerticalBrightness: true, // 右侧竖滑=亮度
      horizontalSeek: true,          // 横滑=进度
      doubleTapSeek: true,
      doubleTapStep: Duration(seconds: 10),
      pinchZoom: true,
    ),
  ),
);
```

## 架构 / Architecture

0.2.0 起分两层：`lib/src/core/`（无 UI 依赖的能力面/内核封装）与
`lib/src/ui/`（组件树 + 皮肤 + 手势，纯 Flutter widget）。

```
core/
  api.dart              VmApi        —— UI 层唯一依赖的抽象能力面
  engine.dart           VmEngine     —— VmApi 的生产实现（取代 0.1.0 的 VmController）
  kernel/                            —— VmKernel 抽象；mpv_kernel.dart 是唯一 import media_kit 的文件
  bus/ events/ state/                —— 事件总线、sealed 事件表、VmState/VmProgress/VmUiState
  interceptor/           VmInterceptor —— beforeOpen/beforeSeek/beforePlay/onError 四个拦截点
  options/               VmOptions    —— gesture/abr/controls/live/strings/theme 六节配置聚合
ui/
  player.dart            VmPlayer     —— 顶层组件：接 VmApi + 渲染画面 + 由 VmSkin 出树
  slots/                 VmComponent / VmSlot / VmPatch —— 组件树模型与结构化补丁
  skins/                 VmSkin / VmDefaultSkin —— 依据 VmState 决定树里有哪些组件
  components/                         —— 叶子/组合组件（top_bar/bottom_bar/live_bar/gesture_layer/hud_layer/...）
```

`VmApi` 是 `ui/` 唯一允许依赖的抽象——它不直接触达 `VmKernel` 或 media_kit。
测试用 `FakeVmApi`（见 `test/support/fake_api.dart`），因此绝大多数组件/皮肤测试
无需启动真实播放内核。

## 自定义皮肤 / Custom skins

不用继承旧版 `VodControls`/`LiveControls`/`VmGestureDetector`，改为对
`VmDefaultSkin` 打补丁，或整体实现 `VmSkin` 接口重写 `components()`/`assemble()`：

```dart
// 去掉顶栏里的画中画按钮（等价于 0.1.0 里派生子类删掉一个按钮）。
const noPipSkin = VmDefaultSkin(
  patches: [VmPatch.remove('topBar/pipButton')],
);

VmPlayer(api: engine, skin: noPipSkin);
```

```dart
// 在顶栏追加一个自定义组件。
final withExtra = VmDefaultSkin(
  patches: [VmPatch.add(VmSlot.top, MyExtraButtonComponent(), order: 10)],
);
```

需要完全不同的排版时，直接实现 `VmSkin`：

```dart
class MySkin implements VmSkin {
  @override
  List<VmComponent> components(VmState s) => [/* 自定义组件树 */];

  @override
  Widget assemble(BuildContext context, VmSlotBundle slots, Widget video) {
    return Stack(children: [video, ...slots[VmSlot.top]]);
  }
}
```

## 注入拦截器 / Interceptors

`VmInterceptor` 让宿主 App 否决或改写核心动作（例如播放前鉴权、跳转边界限制、
统一错误上报），无需改动 `VmEngine`/组件代码：

```dart
class AuthGate extends VmInterceptor {
  @override
  Future<bool> beforeOpen(VmSource source) async {
    return await checkEntitlement(source.uri); // false 则取消打开
  }

  @override
  Future<Duration?> beforeSeek(Duration target) async {
    return target < Duration.zero ? Duration.zero : target; // 改写目标位置
  }

  @override
  void onError(Object error, StackTrace stack) => reportToSentry(error, stack);
}

final engine = VmEngine(interceptors: [AuthGate()]);
```

## Roadmap / 路线图

见 [doc/ROADMAP.md](doc/ROADMAP.md) 与 [doc/DESIGN-0.2.0.md](doc/DESIGN-0.2.0.md)。
阶段 A（本次，core/ui 分层重构）已完成；阶段 B（拖动预览缩略图）、阶段 C（直播
时移）、阶段 D（收尾发布）计划见 DESIGN 文档 §7/§8/§12。

## License

MIT
