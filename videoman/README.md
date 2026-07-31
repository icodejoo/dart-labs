# videoman

A Flutter video player built on [media_kit](https://pub.dev/packages/media_kit)
(libmpv/ffmpeg) with a self-built gesture + control layer for VOD and live
playback.

基于 [media_kit](https://pub.dev/packages/media_kit)（libmpv/ffmpeg 内核）的
Flutter 视频播放库，自研手势与控制层，支持点播与直播。

## Features / 功能

- **Gestures / 手势**：左半竖滑=亮度、右半竖滑=音量、横滑=进度、双击=快进退、双指=缩放，带 HUD 反馈；侧别→动作可配。
- **Fill modes / 观看模式**：`contain` / `cover` / `fill` 循环切换。
- **Lock / 锁定**：一键锁定屏蔽全部交互（防误触），沉浸式观看。
- **Orientation / 方向**：全屏按视频宽高比自动横/竖屏。
- **Quality / 清晰度**：解析 HLS master 提取档位、手动切换、网络卡顿自动降档；"自动"档委托 libmpv 原生 ABR。
- **PiP / 画中画**：Android 系统级画中画（iOS/桌面暂不支持，见下）。
- **VOD & Live / 点播与直播**：两套控制条；直播默认禁止拖动，可开启 DVR（服务端窗口内拖动）
  或时移（拖动即换源），带"回到直播"按钮与时移角标。
- **Scrub preview / 拖动预览缩略图**：拖动进度条或横滑手势时，进度条上方浮出目标时刻的
  缩略图气泡（WebVTT 雪碧图 / libmpv 抽帧兜底，两级缓存，默认仅 WiFi）。

## Platform support / 平台支持

| | Android | iOS | Windows |
|---|:---:|:---:|:---:|
| 播放 / 手势 / 控制条 | ✅ | ✅ | ✅ |
| 画中画 PiP | ✅ | ❌ | ❌ |

> iOS/桌面 PiP：media_kit 用 libmpv 纹理渲染，系统级 PiP 依赖 AVPlayer 路径，暂未实现，`isPipSupported()` 返回 `false`。

## Install / 安装

```yaml
dependencies:
  videoman: ^0.3.0
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

自定义手势侧别→动作/开关，通过 `VmOptions` 传入 `VmEngine`。侧别与动作解耦，可自由
重映射（把亮度放右侧、或用 `VmGestureAction.none` 禁用某一侧）：

```dart
final engine = createVmEngine(
  options: const VmOptions(
    gesture: VmGestureConfig(
      // 默认即主流约定：左亮度、右音量、横滑进度。下面演示换回旧的左音量/右亮度。
      leftVertical: VmGestureAction.volume,      // 左侧竖滑=音量
      rightVertical: VmGestureAction.brightness, // 右侧竖滑=亮度
      horizontal: VmGestureAction.seek,          // 横滑=进度
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
  scope/                 VmScope / VmSelector / VmPlugin —— 能力面下发、按字段订阅、副作用能力 mixin
  skins/                 VmSkin / VmDefaultSkin —— 静态组件树 + 可覆写的三层骨架
  components/                         —— 叶子/组合组件（top_bar/bottom_bar/gesture_layer/hud_layer/...）
```

`VmApi` 是 `ui/` 唯一允许依赖的抽象——它不直接触达 `VmKernel` 或 media_kit。
测试用 `FakeVmApi`（见 `test/support/fake_api.dart`），因此绝大多数组件/皮肤测试
无需启动真实播放内核。

## 拖动预览

```dart
final engine = createVmEngine(
  options: const VmOptions(
    preview: VmPreviewConfig(
      network: VmPreviewNetwork.wifiOnly, // 默认；always / never 可选
      frameWidth: 160,                    // 缩略图宽度
      bucket: Duration(seconds: 10),      // 桶大小，同桶复用同一张图
      memMaxEntries: 40,                  // 内存 LRU 条目上限
      diskMaxBytes: 64 * 1024 * 1024,     // 磁盘 LRU 字节上限
    ),
  ),
);
```

约定的缩略图轨地址是 `<视频地址>.vtt`；要换地址用 `vttUrl` 或 `vttUrlResolver`。
要整块换掉气泡外观：

```dart
VmPlayer(
  api: engine,
  skin: VmDefaultSkin(patches: [VmPatch.replace('preview', MyBubble())]),
)
```

## 直播时移

```dart
// DVR：不换源，在服务端滑动窗口内拖动
final engine = VmEngine(
  options: const VmOptions(
    live: VmLiveConfig(seekMode: VmLiveSeekMode.dvr),
  ),
);

// 时移：拖动时用你自己的 URL 方案重开源
final engine = VmEngine(
  options: VmOptions(
    live: VmLiveConfig(
      seekMode: VmLiveSeekMode.timeshift,
      dvrWindow: const Duration(hours: 2),
      urlBuilder: (uri, behind, now) =>
          '$uri?begin=${now.subtract(behind).millisecondsSinceEpoch}',
    ),
  ),
);
```

默认 `off`（保持 0.1.0 禁拖行为）；`timeshift` 模式没有 `urlBuilder` 就不生效；
`windowResolver` 用于服务端带外声明窗口的场景。

## 平台端口

`VmEngine()` 裸构造默认走 noop 端口（供纯 Dart 单测使用），应用代码应改用
`lib/src/platform_impl/wiring.dart` 的 `createVmEngine()`——它默认接好
`ScreenBrightnessPort()` / `ChannelPipPort()` / `SystemChromeOrientationPort()`，
并额外接好预览相关的端口（缩略图目录/抽帧器/网络探针的真实实现）。

### 音量端口 / Volume

右侧竖滑调音量走 `VmVolumePort`。`createVmEngine()` 默认在 **Android** 上接
`SystemVolumePort()`（原生 `AudioManager`，调**系统媒体音量**、与硬件音量键联动，
不引第三方依赖）；**iOS**（系统限制代码改音量）与**桌面**回退到播放器自身音量。

任意平台都能自己接管——传入 `CallbackVolumePort`，回调收到目标百分比（0–100），
由你决定怎么落地（例如用自己的系统音量方案）：

```dart
final engine = createVmEngine(
  options: options,
  volume: CallbackVolumePort((percent) => myAudio.setSystemVolume(percent)),
);
```

不传回调时，Android 走内置系统音量、其它平台走播放器音量——都无需额外代码。

`SystemChromeOrientationPort` 只处理移动端的方向锁定/沉浸式系统 UI；在
Windows/macOS/Linux 上没有对应的"真全屏"概念（把 OS 窗口撑满屏幕、去掉标题栏），
调用 `setFullscreen(true)` 在桌面端不会有可见效果。videoman 不内置窗口管理
依赖，桌面端真全屏留给宿主自己接：

```dart
engine.events.listen((e) {
  if (e is VmFullscreenChanged) {
    // 例如用 window_manager 包切换真实的 OS 窗口全屏。
    windowManager.setFullScreen(e.value);
  }
});
```

`VmFullscreenChanged` 事件在 `setFullscreen()` 每次调用时都会发出，与
`VmOrientationPort` 无关——不需要实现整套 `VmOrientationPort` 接口（那是给移动端
方向/沉浸式 UI 设计的），监听事件流即可。

## 自定义皮肤 / Custom skins

三档定制，由浅入深：

1. **补丁档**：`VmDefaultSkin(patches: [...])`——增/删/替换/重写组件、在已有插槽间挪位置。
2. **半覆写档**：`extends VmDefaultSkin` 只覆写某一层的受保护方法
   （`buildPlaybackLayer`/`buildOperableLayer`/`buildPersistentLayer`），重排版而复用其余各层。
3. **全实现档**：`implements VmSkin` 重写 `components()`/`assemble()`，布局与组件全自定义。

内置皮肤是三层骨架：**播放层**（画面）+**操作层**（手势/顶中底/左右栏，随闲置一起淡隐、
pip/锁定时整层隐藏）+**常驻层**（锁定遮罩与锁定/解锁按钮，恒挂载、默认穿透、不受门控）。
组件树是静态的（`components()` 不吃状态），显隐由组件各自的 `VmSelector` 响应式决定。
插槽词表：`top`/`center`/`bottom`/`bottomAbove`/`overlay`/`left`/`right`/`gesture`/`hud`。

打补丁或整体实现 `VmSkin`：

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
  List<VmComponent> components() => [/* 自定义组件树（静态） */];

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
