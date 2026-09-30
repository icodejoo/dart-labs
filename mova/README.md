# mova

A Flutter video player built on [media_kit](https://pub.dev/packages/media_kit)
(libmpv/ffmpeg) with a self-built gesture + control layer for VOD and live
playback.

基于 [media_kit](https://pub.dev/packages/media_kit)（libmpv/ffmpeg 内核）的
Flutter 视频播放库，自研手势与控制层，支持点播与直播。

> ⚠️ **Not production-ready yet / 尚未生产就绪**：this is a first pub.dev release
> (`0.1.0`) of a hobby/small-team-maintained plugin. Several features have only
> been unit-tested and have **not** been verified on real devices yet (see
> [Known limitations](#known-limitations--已知限制) below). Use at your own risk
> in production apps — review the limitations and test thoroughly on your
> target devices first.
>
> 这是一个个人/小团队维护插件的**首次** pub.dev 发布（`0.1.0`）。部分功能只过了单元
> 测试、**尚未经过真机验证**（详见下方「已知限制」）。生产环境使用请自行评估风险，
> 在你的目标设备上充分测试后再上线。

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
- **带画面内核的 `VideoController` 必须真正挂到界面上才能正常销毁**（这是 media_kit 的行为，不是 mova 引入的）：`VideoController` 创建后若一直没有挂到视频组件上，`Player.dispose()` 会一直等它，真机实测 Windows 上 3/6 次、Android 上 4/5 次 dispose 撞上 8 秒超时。默认实现（`createMovaEngine()` / `MovaEngine()`）已做成**懒创建**——第一次渲染（`MovaPlayer` 挂上树，读取 `renderHandle`）时才创建，所以"创建了 engine 却没展示就销毁"是安全的。**如果你自己创建并注入 `VideoController`（传入自己构造的 `MovaMpvKernel`/`Player`，或用 `lazyVideo: false` 的内核），要自己保证它最终挂到了 UI 上再销毁**；纯逻辑、后台预热、单测等不展示画面的场景请用 `audioOnly: true`，或保持默认懒创建、不要读取 `renderHandle`。无缝切换的影子引擎例外：预热阶段就需要解码画面，会提前创建控制器。
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
  skin: MovaDefaultSkin(
    patches: [MovaPatch.replace(MovaPreviewComponent.componentName, MyBubble())],
  ),
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

## 弹幕（可选）

`MovaDanmakuItem` 是纯数据值（文案/触发位置/可选颜色），配合
`MovaDanmakuTrackComponent` 渲染滚动弹幕轨道，core 层从不渲染，只负责数据形状：

```dart
final items = [
  MovaDanmakuItem(text: '前方高能', time: const Duration(seconds: 30)),
  MovaDanmakuItem(text: '好家伙', time: const Duration(seconds: 45), color: 0xFFFF5555),
];
```

具体接入方式（把弹幕流喂给 `MovaDanmakuTrackComponent`）随皮肤/组件树自定义而定，
参见「自定义皮肤」一节。

## 播放列表（可选）

`MovaPlaylistController` 在 `MovaApi` 之上驱动顺序播放：跟踪当前下标、按
`MovaApi.open` 在项间导航、可选自动连播。纯 Dart（无 Flutter 依赖），由宿主构造并
注入，engine 从不持有它：

```dart
final playlist = MovaPlaylistController(engine);
await playlist.jumpTo(0); // 打开第一条
```

初值（条目列表/初始下标/是否自动连播）取自 `MovaOpts.playlist`
（`MovaPlaylistConfig`）。**与广告组合时注意**：`MovaPlaylistController` 与
`MovaAdController` 都响应 `MovaDone`，不要在同一播放器上同时启用两者的自动行为——
应把 `MovaPlaylistConfig.autoPlayNext` 设为 `false`，改由
`MovaAdController.contentEnded` 驱动 `playlist.next()`。

## 沉浸式 Feed 流播放（可选）

`MovaFeedPlayer` 是 bilibili/抖音式"上滑下一个视频"的纵向 feed 组件，背后是
`MovaFeedController` + `MovaFeedEnginePool`：每个热页各自独立的引擎，而不是所有页
共用一个，一次上滑是在两个已经活着的画面之间交换（无黑屏一闪、无残留旧帧）。

```dart
MovaFeedPlayer(
  engineFactory: createMovaEngine,             // MovaEngineFactory：池中每个引擎怎么造
  loader: (index) async {                      // MovaFeedLoader：按下标解析条目，到底返回 null
    if (index >= myFeedUrls.length) return null;
    return MovaFeedItem(source: MovaSource(myFeedUrls[index]));
  },
)
```

`MovaFeedItem` 是单条 feed 条目的数据值（源 + 点赞/评论/分享等社交字段）；
`MovaFeedPrefetcher`（默认 `MovaNetworkWarmFeedPrefetcher`）负责提前预热邻近条目的
网络链路，预热深度经 `prefetchDepth` host 可配。社交交互 UI 组件见
`ui/components/feed_social.dart`（点赞/评论/分享按钮、头像、信息栏，均可通过皮肤
补丁体系增删）。详见 [doc/SPEC.md](doc/SPEC.md)「Feed」相关章节。

## 语音转字幕 / STT（可选）

`MovaApi.stt`（`MovaSttApi`）暴露识别出的字幕流：组件只监听 `cues`/`current`、调用
`start()`/`stop()`，音频抽取与识别引擎调用都藏在 core 层背后。识别引擎本身通过
`MovaSttEngine` 端口注入（默认 `MovaNoopSttEngine`，不接引擎则该能力静默不生效）：

```dart
engine.stt.cues.listen((cue) => print('${cue.start}: ${cue.text}'));
await engine.stt.start();
```

内置 `MovaSubtitleOverlayComponent`/`MovaSubtitleButtonComponent` 渲染字幕轨与开关
按钮；`formatSrt()` 可将识别出的 `MovaSttCue` 列表导出为标准 `.srt` 文件。模型/
字幕文件的存放目录通过 `MovaSttModelDirProvider`/`MovaSttSubtitleDirProvider` 注入，
默认走系统临时目录（`platform_impl/stt_model_dir_impl.dart` 等）。

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

## 埋点上报 QoE 增强（可选）

`createMovaEngine(reporter: ...)` 接一个 `MovaReporter`（回调即可，见下方「状态、
事件与自定义组件」），默认只转发 UI 动作流水；把 `MovaOpts.report` 设为
`MovaReportConfig(qoe: true)` 后额外产出业界必测四件套：起播耗时（`firstFrame`/
`startupFail`）、卡顿次数与时长（`rebuffer`）、播放失败 fatal/非 fatal 区分
（`MovaErrorEvent` 补 `fatal`/`code`）、会话开始/结束（`sessionStart`/`sessionEnd`，
`reason` 为 `ended`/`stopped`/`failed`/`abandoned` 四分之一）。默认 **关闭**，
不开启时事件流与不传 `report` 逐字节相同。

```dart
final engine = createMovaEngine(
  options: const MovaOpts(report: MovaReportConfig(qoe: true)),
  reporter: (e) {
    // 转成任意分析 SDK 的调用——mova 只标准化，从不自己发送/攒批/调度。
    myAnalytics.track(e.name.value, {...e.params, 'sessionId': e.sessionId});
  },
);
```

`MovaReportName` 从 0.2.x 起是 const 值类而非枚举（内置项 + `MovaReportName.custom`
自定义名双轨，`==`/`hashCode`/`Map`/`Set` 键用法不变），破坏面见 CHANGELOG。信号优先
取 libmpv 原生能力（`paused-for-cache` 真卡顿信号、`video-bitrate`/`cache-speed`/
丢帧计数、mpv 日志 prefix 错误分类），必要时（TTFF 精确落地、会话结束原因）经
`media_kit` 的 `observeEvent` 新 API 订阅原生 mpv 事件——这也是本仓库依赖
`media_kit` git 提交而非 pub.dev 版本的原因。详见
[doc/SPEC.md](doc/SPEC.md)「埋点与 QoE」一节、
[doc/plans/2026-09-29-telemetry-enhancement.md](doc/plans/2026-09-29-telemetry-enhancement.md)。
**仅 Windows 桌面验证过 `observeEvent` 能驱动 TTFF/会话结束落地，未做任何真机验证。**

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

### 亮度与方向端口

左侧竖滑调亮度走 `MovaBrightPort`（`createMovaEngine()` 默认接
`MovaScreenBrightnessPort()`）；强制横竖屏走 `MovaOrientationPort`（默认接
`MovaSystemChromeOrientationPort()`）。两者与 `MovaVolumePort` 同构，都可以自行
实现该抽象类并通过 `createMovaEngine(brightness: ..., orientation: ...)` 换掉。
方向端口不需要的场景可传内置的 `MovaNoopOrientationPort()` 显式关闭；亮度端口目前
没有对应的内置空实现，不需要该能力时自行实现一个空的 `MovaBrightPort` 即可。

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

## 状态、事件与自定义组件

`MovaState`（累计快照，如 `playing`/`duration`/`quality`）与 `MovaProg`（高频进度
字段：`position`/`buffer`）、`MovaUiState`（HUD/锁定等纯 UI 态）是三类只读状态；
`MovaApi.events` 则是离散事件流（`MovaEvent` 密封类族，`MovaPlay`/`MovaSeeked`/
`MovaQualityChange`/`MovaPipChange`/`MovaSwapChange`/`MovaErrorEvent` 等三十余种，
完整列表见 `lib/src/core/events/events.dart`）。

写自定义组件（`extends MovaComponent`）时，两种读取方式对应两种场景：

```dart
// 无状态重建：只读一个字段、随其变化自动 rebuild，不需要自己管订阅。
MovaSelect<bool>(
  selector: (state) => state.playing,
  builder: (context, playing) => Icon(playing ? Icons.pause : Icons.play_arrow),
)

// 有状态副作用：需要在事件发生时做点什么（弹 Toast、打点），而不只是重建。
class _MyState extends State<MyWidget> with MovaPlugin<MyWidget> {
  @override
  void initState() {
    super.initState();
    bind(api.events, (e) { if (e is MovaErrorEvent) showToast(e.error); }); // 自动在 dispose 时取消订阅
  }
}
```

`MovaPlugin` 只提供 `api`（稳定句柄）与 `bind`（生命周期安全订阅）两个与业务无关的
能力，写在哪个组件里都不会有成员名冲突。

## 内置皮肤集 / Built-in skins

除 `MovaDefaultSkin` 外还内置了两套现成皮肤，直接传给 `MovaPlayer.skin` 即可切换：

```dart
MovaPlayer(api: engine, skin: MovaBilibiliSkin()); // 类 B 站风格（非 const：内置补丁经 static final 拼接）
MovaPlayer(api: engine, skin: const MovaDouyinSkin());   // 类抖音风格，含双击点赞爱心特效手势层
```

`MovaBilibiliSkin` 是 `MovaDefaultSkin` 的补丁化变体；`MovaDouyinSkin` 独立实现
`MovaSkin`，替换了手势层（`MovaDouyinGestureLayerComponent`，双击点赞 + 单击暂停）。
两者都可以再叠加自己的 `patches` 做进一步定制。

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
// 组件路径用 <ComponentClass>.componentName 拼，避免手写字符串拼错。
const noPipSkin = MovaDefaultSkin(
  patches: [
    MovaPatch.remove(
      '${MovaTopBarComponent.componentName}/${MovaPipButtonComponent.componentName}',
    ),
  ],
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
只是体积比自研瘦身版大一些（Android 约 11.8MB → 6.05MB；Windows 约 14.66MB →
13.41MB。二进制越裁越小，具体数字见各平台产物目录）。项目自己维护了一套体积更小的
瘦身版 libmpv 构建（独立子工程 `mova-libmpv`，产物通过 CI 自动同步推送到本仓库
`packages/` 各对应平台包内）。**这是可选的进阶操作，普通用户完全不需要做，装了 mova 也不会自动生效。**

**能力面被裁过，接入前请知悉**：瘦身版去掉了 VP8/VP9 软解、收窄了音频
decoder/demuxer 白名单、砍掉了部分协议（ftp/async/cache/subfile/httpproxy），且
avfilter（`overlay`/`equalizer`，用于 OSD/字幕合成/音频均衡）移除后的真机播放影响
**尚未做过系统性验证**。如果你的场景依赖这些能力，先别接入。

### 机制：同名整包替换（同一套思路适用所有已落地平台）

不管哪个平台，接入方式都是**同一个模式**：本仓库提供一个与官方包**同名**的 fork 包
（`publish_to: 'none'`，只能通过 path/git 依赖引用，不会被误装），装了它并在你项目的
`pubspec.yaml` 里用 `dependency_overrides` 指过去之后，官方包**完全退出依赖图**——
不是"两份二进制打架、谁赢的问题"，而是从一开始就只有一个提供方，天然没有冲突，
也不需要额外的合并规则。删掉 `dependency_overrides` 那几行，就干净回退到官方版本，
零残留、零副作用。

### Android

```yaml
# 你项目自己的 pubspec.yaml —— 复制粘贴即可用，把 ref 换成你想锁定的 commit/tag
dependency_overrides:
  media_kit_libs_android_video:
    git:
      url: https://github.com/icodejoo/dart-labs.git
      path: mova/packages/media_kit_libs_android_video_slim
      ref: main
```

如果你是把 `dart-labs` 仓库 clone 到自己项目旁边本地开发（而不是走 git 依赖），
把上面 `git:` 那三行换成一行相对路径即可（假设两个仓库是兄弟目录）：

```yaml
    path: ../dart-labs/mova/packages/media_kit_libs_android_video_slim
```

不需要改任何 Gradle 文件、不需要 `pickFirsts`——加这一行依赖覆盖就是全部操作。
这个 fork 包内含两个原生库：mova-libmpv 自建的瘦身版 `libmpv.so`，以及
**原样提取自官方 release 的** `libmediakitandroidhelper.so`（负责 `content://`
URI 打开等，mova-libmpv 不构建这个，必须保留，否则会丢功能）。

验证方式（不用信我们说的，自己核对，`<mova-repo>` 换成你本地 clone 的路径）：

```bash
unzip -p build/app/outputs/flutter-apk/app-release.apk lib/arm64-v8a/libmpv.so | sha256sum
sha256sum <mova-repo>/mova/packages/media_kit_libs_android_video_slim/android/src/main/jniLibs/arm64-v8a/libmpv.so
# 两个 sha256 应完全一致
```

### Windows

```yaml
dependency_overrides:
  media_kit_libs_windows_video:
    git:
      url: https://github.com/icodejoo/dart-labs.git
      path: mova/packages/media_kit_libs_windows_video_slim
      ref: main
```

同样只需要这一行（本地 clone 用法同上，把 `git:` 换成 `path: ../dart-labs/mova/...`）；
这个 fork 包自带自研瘦身版 `windows/libmpv-2.dll` 以及对应的导入库与公共头文件，完全自包含，
跳过官方 7z 下载。参考本仓库 [example/pubspec.yaml](example/pubspec.yaml) 的实际写法（长期用于真机验证）。

### iOS / macOS

**⚠️ 结构已落地，但完全未经验证（没有 Mac，无法构建/签名/真机测试）**：

```yaml
dependency_overrides:
  media_kit_libs_ios_video:
    git:
      url: https://github.com/icodejoo/dart-labs.git
      path: mova/packages/media_kit_libs_ios_video_slim
      ref: main
  media_kit_libs_macos_video:
    git:
      url: https://github.com/icodejoo/dart-labs.git
      path: mova/packages/media_kit_libs_macos_video_slim
      ref: main
```

`packages/media_kit_libs_ios_video_slim` 与 `_macos_video_slim` 两个 fork 包已经
提交了 `Frameworks/Mpv.xcframework`（用 mova-libmpv 的 `libmpv.dylib` 手工拼出
`Mpv.framework` 的目录结构——`Info.plist`/`Modules/module.modulemap`/`Headers/`），
podspec 用 `prepare_command` 在 `pod install` 时跑官方同款
`create_framework_symlinks.sh`（MIT，未改动）生成符号链接，不再走官方那套
下载 xcframework 归档的 `make` 流程。

**这些文件是在没有 Xcode 工具链（`otool`/`install_name_tool`/`xcodebuild`/`lipo`）
的 Windows 机器上手工拼装的**，从未跑过 `pod install`，也从未真机验证过——dylib
的 `LC_ID_DYLIB`/依赖路径是否符合 framework 内部约定（`@rpath/Mpv.framework/Mpv`）
完全未经确认，`macos-universal/libmpv.dylib` 是否真的是 arm64+x86_64 fat binary
也未用 `lipo` 核实过。**接入前请先在 Mac 上完整走一遍 `pod install` +
`flutter build ios`/`flutter build macos` + 真机播放，不要直接用于生产。**
详见 [doc/plans/2026-09-25-libmpv-pub-package.md](doc/plans/2026-09-25-libmpv-pub-package.md)
「Darwin（iOS/macOS）同名替换设计」一节；欢迎有 Mac 环境的贡献者验证并回填结论。

### Linux

libmpv 在 Linux 上来自系统（`media_kit_video` 走 pkg-config 找 mpv/epoxy），
不存在"包提供二进制"这个位置可占，本方案模型不适用，接入需要走系统包管理或
自建 RPATH，不在本方案范围内。

### 免责声明

这是社区/进阶用法，mova 官方不对接入后的行为提供支持保证；瘦身版二进制版本与 mova
包版本没有强绑定关系，升级前建议自己按上面的 sha256 核对方式重新验证一次。

## Roadmap / 路线图

见 [doc/ROADMAP.md](doc/ROADMAP.md)。

## License

MIT
