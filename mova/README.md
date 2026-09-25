# mova

A Flutter video player built on [media_kit](https://pub.dev/packages/media_kit)
(libmpv/ffmpeg) with a self-built gesture + control layer for VOD and live
playback.

基于 [media_kit](https://pub.dev/packages/media_kit)（libmpv/ffmpeg 内核）的
Flutter 视频播放库，自研手势与控制层，支持点播与直播。

## Features / 功能

- **Gestures / 手势**：左半竖滑=亮度、右半竖滑=音量、横滑=进度、双击=快进退、双指=缩放，带 HUD 反馈；侧别→动作可配。
- **Fill modes / 观看模式**：`contain` / `cover` / `fill` 循环切换。
- **Lock / 锁定**：一键锁定屏蔽全部交互（防误触），沉浸式观看。
- **Orientation / 方向**：全屏按视频宽高比自动横/竖屏；顶栏横竖屏按钮（仅移动端）可
  `setOrientation` 强制横/竖屏，独立于全屏。
- **Quality / 清晰度**：解析 HLS master 提取档位、手动切换、网络卡顿自动降档；"自动"档委托 libmpv 原生 ABR。
- **PiP / 画中画**：Android 系统级画中画（iOS/桌面暂不支持，见下）。
- **VOD & Live / 点播与直播**：两套控制条；直播默认禁止拖动，可开启 DVR（服务端窗口内拖动）
  或时移（拖动即换源），带"回到直播"按钮与时移角标。
- **Scrub preview / 拖动预览缩略图**：拖动进度条或横滑手势时，进度条上方浮出目标时刻的
  缩略图气泡（WebVTT 雪碧图 / libmpv 抽帧兜底，两级缓存，默认仅 WiFi）。
- **Ad orchestration / 广告编排（可选）**：`MovaAdController` 按排期播前/中/后贴片，
  支持延迟解析正片源、广告位时长与素材时长解耦、就绪等待、失败兜底。
- **Seamless engine swapping / 无缝引擎切换（可选）**：`MovaSwapEngine` 在一个稳定渲染面
  背后持有当前引擎与预热中的影子引擎，就绪后原子换指，消除"广告播完回正片"等场景的
  黑屏/loading。默认关闭。
- **In-app mini window / App 内小窗（可选）**：不依赖系统 PiP，把画面缩成可拖拽悬浮小窗，
  不重新解码、不黑屏。默认关闭。
- **Audio-only mode / 仅音频模式（可选）**：跳过视频管线，只解音频，省内存/CPU。默认关闭。

## Platform support / 平台支持

| | Android | iOS | Windows |
|---|:---:|:---:|:---:|
| 播放 / 手势 / 控制条 | ✅ | ✅ | ✅ |
| 画中画 PiP | ✅ | ❌ | ❌ |

> iOS/桌面 PiP：media_kit 用 libmpv 纹理渲染，系统级 PiP 依赖 AVPlayer 路径，暂未实现，`isPipSupported()` 返回 `false`。详见 [doc/SPEC.md](doc/SPEC.md)「PiP（原生）」一节。

## Known limitations / 已知限制

- iOS/桌面（Windows/macOS/Linux）暂不支持系统级画中画。
- 桌面平台（Windows/macOS/Linux）没有"真全屏"（撑满 OS 窗口、去标题栏）能力，`setFullscreen()` 不会有可见效果，需宿主自己接 `window_manager` 一类的包（见下方「平台端口」一节）。
- 仅音频模式（`audioOnly`）不提供后台常驻播放、锁屏/通知栏控制、耳机线控、音频焦点、gapless、歌单——这些需要 `just_audio` + `audio_service` 一类的专用方案。
- 部分可选能力（广告编排、无缝引擎切换、App 内小窗、仅音频模式）代码已落地但真机验证程度不一，详见各自小节链接的 [doc/SPEC.md](doc/SPEC.md) 章节。

## Install / 安装

```yaml
dependencies:
  mova: ^0.1.0
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
import 'package:mova/mova.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized(); // 全局一次性初始化
  runApp(const MyApp());
}

class Page extends StatefulWidget {
  const Page({super.key});
  @override
  State<Page> createState() => _PageState();
}

class _PageState extends State<Page> {
  late final MovaEngine engine;

  @override
  void initState() {
    super.initState();
    engine = MovaEngine();
    engine.open(const MovaSource(
      'https://example.com/master.m3u8',
      type: MovaStreamType.live, // 或 MovaStreamType.vod
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
    return MovaPlayer(api: engine); // 默认皮肤 MovaDefaultSkin
  }
}
```

> **提示**：`MovaEngine()` 裸构造默认走 noop 平台端口（亮度手势不生效、`enterPip()` 恒
> `false`、全屏不转屏，仅供纯 Dart 单测使用）。应用代码应改用
> `lib/src/platform_impl/wiring.dart` 导出的 `createMovaEngine()`，它默认接好真实的
> 亮度/PiP/方向端口。上面示例为了突出最小用法用了 `MovaEngine()`，实际项目里请换成
> `createMovaEngine()`。

自定义手势侧别→动作/开关，通过 `MovaOpts` 传入 `MovaEngine`。侧别与动作解耦，可自由
重映射（把亮度放右侧、或用 `MovaGestureAction.none` 禁用某一侧）：

```dart
final engine = createMovaEngine(
  options: const MovaOpts(
    gesture: MovaGestureConfig(
      // 默认即主流约定：左亮度、右音量、横滑进度。下面演示换回旧的左音量/右亮度。
      leftVertical: MovaGestureAction.volume,      // 左侧竖滑=音量
      rightVertical: MovaGestureAction.brightness, // 右侧竖滑=亮度
      horizontal: MovaGestureAction.seek,          // 横滑=进度
      doubleTapSeek: true,
      doubleTapStep: Duration(seconds: 10),
      pinchZoom: true,
    ),
  ),
);
```

## 拖动预览

```dart
final engine = createMovaEngine(
  options: const MovaOpts(
    preview: MovaPreviewConfig(
      network: MovaPreviewNet.wifiOnly, // 默认；always / never 可选
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
MovaPlayer(
  api: engine,
  skin: MovaDefaultSkin(patches: [MovaPatch.replace('preview', MyBubble())]),
)
```

## 直播时移

```dart
// DVR：不换源，在服务端滑动窗口内拖动
final engine = MovaEngine(
  options: const MovaOpts(
    live: MovaLiveConfig(seekMode: MovaLiveSeekMode.dvr),
  ),
);

// 时移：拖动时用你自己的 URL 方案重开源
final engine = MovaEngine(
  options: MovaOpts(
    live: MovaLiveConfig(
      seekMode: MovaLiveSeekMode.timeshift,
      dvrWindow: const Duration(hours: 2),
      urlBuilder: (uri, behind, now) =>
          '$uri?begin=${now.subtract(behind).millisecondsSinceEpoch}',
    ),
  ),
);
```

默认 `off`（禁止拖动）；`timeshift` 模式没有 `urlBuilder` 就不生效；
`windowResolver` 用于服务端带外声明窗口的场景。

## 广告编排（可选）

`MovaAdController` 按排期播前/中/后贴片，并能表达广告业务的真实时序。**除广告位时长外，
所有新能力默认关闭或默认不改变行为。**

```dart
// 正片源延迟解析：前贴片播完之后才真正解析正片地址（DRM/签名 URL 场景）。
await ads.loadDeferred(() async {
  final play = await api.requestPlayback(videoId);
  return MovaSource(play.url, title: play.title);
});
ads.contentError.listen((e) => /* 解析失败，由宿主决定是否重试 */);

// 广告位时长与倒计时：duration 与素材时长解耦，delay 只对中插生效。
MovaAdBreak(
  kind: MovaAdBreakKind.mid,
  source: MovaSource('https://cdn/ad.mp4'),
  offset: const Duration(seconds: 600),
  delay: const Duration(seconds: 3),     // "3 秒后播放广告"，期间正片继续播
  duration: const Duration(seconds: 15), // 买下的广告位是 15 秒，与素材长度无关
  skippableAfter: const Duration(seconds: 5),
);

// 等广告真的就绪再切入：默认 pre 不等 / mid 等 / post 不等。
MovaAdConfig(
  waitForAdReady: const MovaAdWaitByKind(post: true), // 后贴片也等
  adReadyTimeout: const Duration(seconds: 5),
  notReadyAction: MovaAdNotReady.hardCut,             // 等不到就硬切
);

// 加载失败兜底。
MovaAdConfig(
  failPolicy: const MovaAdRetrySkip(maxRetries: 0), // 默认：不重试，跳过这一条
  loadTimeout: const Duration(seconds: 8),          // 多久没有首帧算失败
);
```

要点：

- `duration` 必须长于 `skippableAfter`，否则 `assertValid()` 会在 debug 下失败。
- 就绪等待仅在宿主接了 `MovaSwapController` 且 `MovaSwapConfig.enabled` 为 `true` 时才可能生效——两者默认都是关的。
- 失败兜底策略 `MovaAdFailPolicy` 返回 `retry` / `skipBreak` / `abandonPod`，内置 `MovaAdAbandonPod`（首次失败即放弃整个 pod）。

详细行为规则、状态机与真机验证进展见 [doc/SPEC.md](doc/SPEC.md)「广告编排增强」一节、
[doc/plans/2026-09-16-ad-swap-enhancements.md](doc/plans/2026-09-16-ad-swap-enhancements.md)。

## 无缝引擎切换（可选）

`MovaSwapEngine` 本身就是一个 `MovaApi`：在一个稳定的渲染面背后持有当前生效引擎，以及
一个可选的、正在预热的影子引擎；影子就绪后原子换指，UI 完全无感（不重挂、不黑屏）。
默认 **关闭**（`MovaSwapConfig.enabled` 为 `false`），关闭时是纯直通代理，行为与直接用
`MovaEngine` 完全一致。

```dart
final api = MovaSwapEngine(engineFactory: createMovaEngine);
// 或带上配置：createMovaEngine(options: MovaOpts(swap: MovaSwapConfig(enabled: true)))
final ads = MovaAdController(api, swap: api); // swap 传同一个实例
runApp(MovaPlayer(api: api));
```

`MovaAdController` 接了 `swap:` 参数后，会在广告播放期间按 `MovaSwapConfig` 配置的触发策略
（默认 `MovaLeadWarm`：结束前 2 秒开始预热，短于 5 秒的广告不预热）后台预热正片，广告一
结束就原子切换回正片。详见 [doc/SPEC.md](doc/SPEC.md)「无缝引擎切换」一节、
[doc/plans/2026-09-16-seamless-swap.md](doc/plans/2026-09-16-seamless-swap.md)。

## App 内小窗（`MovaMini`，可选）

在不依赖任何系统 PiP API 的前提下，让画面从页面里缩成一个可拖拽的悬浮小窗——不重新
解码、不黑屏。与系统级 PiP（`MovaApi.enterPip()`）和需要 `SYSTEM_ALERT_WINDOW` 权限的
系统悬浮窗都不是一回事：本功能是 Flutter 自己绘制树里的合成，不出 App，四端零权限。
默认 **关闭**（`MovaMiniConfig.enabled` 为 `false`）。

两种挂载方式并存，按需选用：

```dart
// 方式 A · 页内悬浮：当前页面内浮着，页面 pop 时小窗随之消失。
final mini = MovaMiniController();
await mini.showInPage(context, api);

// 页面 dispose() 里必须调一次 hide() 或 close()：
@override
void dispose() {
  if (mini.isShowing(api)) mini.hide();
  super.dispose();
}
```

```dart
// 方式 B · 跨路由持久：push/pop 任意多层，小窗一直在最上。
final miniCtl = MovaMiniController(); // 建在 app 根，路由之外

MaterialApp(
  builder: (context, child) => MovaMiniHost(ctl: miniCtl, child: child!),
  home: const HomePage(),
)

// 播放页里点"缩小"：
await miniCtl.show(api);
Navigator.of(context).pop();   // 引擎不受影响，画面在小窗里继续
```

**谁 dispose engine**：mova 的约定是"宿主持有 engine"——`MovaPlayer`/`MovaMiniController`
从不 dispose 传进来的 `api`。页面 `dispose()` 里顺手 `api.dispose()` 会在交接瞬间把正在
小窗里播的引擎干掉；用 `MovaMiniController.isShowing(api)` 在 `dispose` 前自检。

demo 见 [example/lib/mini_window_demo.dart](example/lib/mini_window_demo.dart)（
`flutter run -t lib/mini_window_demo.dart`）。详见 [doc/SPEC.md](doc/SPEC.md)「App 内小窗（MovaMini）」一节。

## 仅音频模式（`audioOnly`，可选）

同一个项目里既要放视频也要放纯音频时，音频那条路不该背视频的资源开销。
`audioOnly: true` 构造出的引擎不建立任何视频管线：默认内核跳过 `VideoController`，
抽帧兜底也不接线。此时 `renderHandle` 为 `null`，`MovaPlayer` 渲染黑色占位——或者你
传给它的任意 `surface`（封面、波形、歌词面）。默认 **关闭**，关闭时行为与不加这个
参数时逐字节相同。

```dart
final engine = createMovaEngine(
  audioOnly: true,
  options: const MovaOpts(preview: MovaPreviewConfig(enabled: false)), // 没有帧可预览
);
runApp(MovaPlayer(api: engine, surface: CoverArt(url: coverUrl)));
```

需要熄屏后台常驻播放 + 系统媒体控制（锁屏/通知栏、耳机线控、音频焦点、gapless、歌单）
请用 `just_audio` + `audio_service`；只是前台界面里放一段音频，用这个模式即可，无需
多引一个插件。实测内存/CPU 收益数据见 [doc/SPEC.md](doc/SPEC.md)「仅音频模式」一节、
[doc/notes/2026-09-16-audio-only-feasibility.md](doc/notes/2026-09-16-audio-only-feasibility.md)。

## 平台端口

`MovaEngine()` 裸构造默认走 noop 端口（供纯 Dart 单测使用），应用代码应改用
`lib/src/platform_impl/wiring.dart` 的 `createMovaEngine()`——它默认接好
`MovaScreenBrightnessPort()` / `MovaChannelPipPort()` / `MovaSystemChromeOrientationPort()`，
并额外接好预览相关的端口（缩略图目录/抽帧器/网络探针的真实实现）。

### 音量端口 / Volume

右侧竖滑调音量走 `MovaVolumePort`。`createMovaEngine()` 默认在 **Android** 上接
`MovaSystemVolumePort()`（原生 `AudioManager`，调**系统媒体音量**、与硬件音量键联动，
不引第三方依赖）；**iOS**（系统限制代码改音量）与**桌面**回退到播放器自身音量。

任意平台都能自己接管——传入 `MovaCallbackVolumePort`，回调收到目标百分比（0–100），
由你决定怎么落地（例如用自己的系统音量方案）：

```dart
final engine = createMovaEngine(
  options: options,
  volume: MovaCallbackVolumePort((percent) => myAudio.setSystemVolume(percent)),
);
```

不传回调时，Android 走内置系统音量、其它平台走播放器音量——都无需额外代码。

### 桌面真全屏

`MovaSystemChromeOrientationPort` 只处理移动端的方向锁定/沉浸式系统 UI；桌面平台
（Windows/macOS/Linux）没有对应的"真全屏"概念（把 OS 窗口撑满屏幕、去掉标题栏），
调用 `setFullscreen(true)` 在桌面端不会有可见效果。mova 不内置窗口管理依赖，桌面端
真全屏留给宿主自己接：

```dart
engine.events.listen((e) {
  if (e is MovaFullScreenChange) {
    // 例如用 window_manager 包切换真实的 OS 窗口全屏。
    windowManager.setFullScreen(e.value);
  }
});
```

`MovaFullScreenChange` 事件在 `setFullscreen()` 每次调用时都会发出，与
`MovaOrientationPort` 无关——不需要实现整套 `MovaOrientationPort` 接口，监听事件流即可。

## 自定义皮肤 / Custom skins

三档定制，由浅入深：

1. **补丁档**：`MovaDefaultSkin(patches: [...])`——增/删/替换/重写组件、在已有插槽间挪位置。
2. **半覆写档**：`extends MovaDefaultSkin` 只覆写某一层的受保护方法
   （`buildPlaybackLayer`/`buildOperableLayer`/`buildPersistentLayer`），重排版而复用其余各层。
3. **全实现档**：`implements MovaSkin` 重写 `components()`/`assemble()`，布局与组件全自定义。

内置皮肤是三层骨架：**播放层**（画面）+**操作层**（手势/顶中底/左右栏，随闲置一起淡隐、
pip/锁定时整层隐藏）+**常驻层**（锁定遮罩与锁定/解锁按钮，恒挂载、默认穿透、不受门控）。
组件树是静态的（`components()` 不吃状态），显隐由组件各自的 `MovaSelect` 响应式决定。
插槽词表：`top`/`center`/`bottom`/`bottomAbove`/`overlay`/`left`/`right`/`gesture`/`hud`。

打补丁或整体实现 `MovaSkin`：

```dart
// 去掉顶栏里的画中画按钮。
const noPipSkin = MovaDefaultSkin(
  patches: [MovaPatch.remove('topBar/pipButton')],
);

MovaPlayer(api: engine, skin: noPipSkin);
```

```dart
// 在顶栏追加一个自定义组件。
final withExtra = MovaDefaultSkin(
  patches: [MovaPatch.add(MovaSlot.top, MyExtraButtonComponent(), order: 10)],
);
```

需要完全不同的排版时，直接实现 `MovaSkin`：

```dart
class MySkin implements MovaSkin {
  @override
  List<MovaComponent> components() => [/* 自定义组件树（静态） */];

  @override
  Widget assemble(BuildContext context, MovaSlotBundle slots, Widget video) {
    return Stack(children: [video, ...slots[MovaSlot.top]]);
  }
}
```

## 注入拦截器 / Interceptors

`MovaHook` 让宿主 App 否决或改写核心动作（例如播放前鉴权、跳转边界限制、
统一错误上报），无需改动 `MovaEngine`/组件代码：

```dart
class AuthGate extends MovaHook {
  @override
  Future<bool> beforeOpen(MovaSource source) async {
    return await checkEntitlement(source.uri); // false 则取消打开
  }

  @override
  Future<Duration?> beforeSeek(Duration target) async {
    return target < Duration.zero ? Duration.zero : target; // 改写目标位置
  }

  @override
  void onError(Object error, StackTrace stack) => reportToSentry(error, stack);
}

final engine = MovaEngine(interceptors: [AuthGate()]);
```

## 项目结构（面向想深入了解或贡献代码的开发者）

`lib/src/core/`（无 UI 依赖的能力面/内核封装）与 `lib/src/ui/`（组件树 + 皮肤 + 手势，
纯 Flutter widget）两层。`MovaApi` 是 `ui/` 唯一允许依赖的抽象——不直接触达
`MovaKernel` 或 media_kit。完整分层说明、各模块职责见 [doc/SPEC.md](doc/SPEC.md)「架构分层」一节。

## 进阶：接入自研瘦身版 libmpv（可选，仅进阶用户）

默认情况下（不做任何配置）安装 mova 会走官方 `media_kit_libs_video` 依赖，能正常播放，
只是体积比自研瘦身版大一些。项目自己维护了一套体积更小的瘦身版 libmpv 构建
（独立仓库 `mova-libmpv`，产物在本仓库 `libmpv/` 目录，按平台分子目录，未随包发布，
需要自己从源码仓库获取）。这是**可选的进阶操作，普通用户完全不需要做**。

**现状**：Android/Windows 已在本仓库 `example` app 里验证真机可用；iOS/macOS/Linux
二进制已产出，但尚未经过下游项目验证接入。

### Android

参考 [example/android/app/build.gradle.kts](example/android/app/build.gradle.kts) 里的
`syncMovaLibmpv` Gradle task：在你自己的 `android/app/build.gradle.kts` 里加一个类似的
`Copy` task，把 mova 仓库里 `libmpv/<abi>/libmpv.so`（`arm64-v8a`/`armeabi-v7a`/`x86`/
`x86_64`）拷进你项目的 `src/main/jniLibs/<abi>/`，挂在 `preBuild` 之前；再配合
`packaging { jniLibs { pickFirsts += "**/libmpv.so" } }` 让它赢过官方包版本。

二进制目前**唯一的获取渠道**是 clone `mova` 仓库源码、直接使用其中的
`libmpv/<abi>/libmpv.so` 文件——尚未提供 GitHub Release 一类更方便的分发渠道。

### Windows

参考本仓库 [packages/media_kit_libs_windows_video_slim](packages/media_kit_libs_windows_video_slim)
这个 fork 包的完整做法，其 `windows/CMakeLists.txt` 跳过官方 7z 下载，直接指向
`libmpv/windows-x86_64/libmpv-2.dll`。可选做法：

- 如果你的项目与 mova 源码在同一台机器上、能访问相对路径，直接在自己的
  `pubspec.yaml` 里用 `dependency_overrides` 的 `path` 依赖指向这个 fork 包（参考
  [example/pubspec.yaml](example/pubspec.yaml) 里的写法）；
- 否则复制这个 fork 包到自己项目里，再改 `CMakeLists.txt` 里的二进制来源路径。

### iOS / macOS / Linux

二进制已产出，但暂无现成的下游接入方案，需要自己参照 Android/Windows 的思路
（Podspec `prepare_command` / CMake 自定义步骤）自行接入，欢迎贡献。

### 免责声明

这是社区/进阶用法，mova 官方不对接入后的行为提供支持保证；瘦身版二进制版本与 mova
包版本没有强绑定关系，升级前建议自己验证。

## Roadmap / 路线图

见 [doc/ROADMAP.md](doc/ROADMAP.md)。

## License

MIT
