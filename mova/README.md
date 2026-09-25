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
- **Seamless engine swapping / 无缝引擎切换（可选）**：`MovaSwapEngine` 在一个稳定渲染面
  背后持有当前引擎与预热中的影子引擎，就绪后原子换指，消除"广告播完回正片"等场景的
  黑屏/loading。默认关闭（`MovaOpts.swap.enabled`），`MovaAdCtrl` 传入同一个
  `MovaSwapEngine` 作 `swap:` 参数即可接入；详见下方用法。

## Platform support / 平台支持

| | Android | iOS | Windows |
|---|:---:|:---:|:---:|
| 播放 / 手势 / 控制条 | ✅ | ✅ | ✅ |
| 画中画 PiP | ✅ | ❌ | ❌ |

> iOS/桌面 PiP：media_kit 用 libmpv 纹理渲染，系统级 PiP 依赖 AVPlayer 路径，暂未实现，`isPipSupported()` 返回 `false`。

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
    return MovaPlayer(api: engine); // 默认皮肤 MovaDefSkin
  }
}
```

自定义手势侧别→动作/开关，通过 `MovaOpts` 传入 `MovaEngine`。侧别与动作解耦，可自由
重映射（把亮度放右侧、或用 `MovaGestAction.none` 禁用某一侧）：

```dart
final engine = createMovaEngine(
  options: const MovaOpts(
    gesture: MovaGestConfig(
      // 默认即主流约定：左亮度、右音量、横滑进度。下面演示换回旧的左音量/右亮度。
      leftVertical: MovaGestAction.volume,      // 左侧竖滑=音量
      rightVertical: MovaGestAction.brightness, // 右侧竖滑=亮度
      horizontal: MovaGestAction.seek,          // 横滑=进度
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
  api.dart              MovaApi        —— UI 层唯一依赖的抽象能力面
  engine.dart           MovaEngine     —— MovaApi 的生产实现（取代 0.1.0 的 MovaCtrl）
  kernel/                            —— MovaKernel 抽象；mpv_kernel.dart 是唯一 import media_kit 的文件
  bus/ events/ state/                —— 事件总线、sealed 事件表、MovaState/MovaProg/MovaUiState
  interceptor/           MovaHook —— beforeOpen/beforeSeek/beforePlay/onError 四个拦截点
  options/               MovaOpts    —— gesture/abr/controls/live/strings/theme 六节配置聚合
ui/
  player.dart            MovaPlayer     —— 顶层组件：接 MovaApi + 渲染画面 + 由 MovaSkin 出树
  slots/                 MovaComp / MovaSlot / MovaPatch —— 组件树模型与结构化补丁
  scope/                 MovaScope / MovaSelect / MovaPlugin —— 能力面下发、按字段订阅、副作用能力 mixin
  skins/                 MovaSkin / MovaDefSkin —— 静态组件树 + 可覆写的三层骨架
  components/                         —— 叶子/组合组件（top_bar/bottom_bar/gesture_layer/hud_layer/...）
```

`MovaApi` 是 `ui/` 唯一允许依赖的抽象——它不直接触达 `MovaKernel` 或 media_kit。
测试用 `FakeMovaApi`（见 `test/support/fake_api.dart`），因此绝大多数组件/皮肤测试
无需启动真实播放内核。

## 拖动预览

```dart
final engine = createMovaEngine(
  options: const MovaOpts(
    preview: MovaPrevConfig(
      network: MovaPrevNet.wifiOnly, // 默认；always / never 可选
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
  skin: MovaDefSkin(patches: [MovaPatch.replace('preview', MyBubble())]),
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

默认 `off`（保持 0.1.0 禁拖行为）；`timeshift` 模式没有 `urlBuilder` 就不生效；
`windowResolver` 用于服务端带外声明窗口的场景。

## 广告编排（delay / duration / 就绪等待 / 失败兜底）

`MovaAdCtrl` 除了按排期播前/中/后贴片，还能表达广告业务的真实时序。**除广告位时长外，
所有新能力默认关闭或默认不改变行为。**

### 正片源延迟解析

正片地址常常要等前贴片播完之后才定得下来（DRM/权益校验、用户画像，或页面加载时签发的
签名 URL 早已过期）。`loadDeferred` 接一个"源的承诺"而不是源：

```dart
await ads.loadDeferred(() async {
  final play = await api.requestPlayback(videoId); // DRM / 签名 URL
  return MovaSource(play.url, title: play.title);
});
ads.contentError.listen((e) => /* 解析失败，由宿主决定是否重试 */);
```

resolver 直到正片真的要被打开时才调用（所有前贴片播完之后），结果记忆化。
`load(MovaSource)` 的语义一字未改。

### 广告位时长与倒计时

```dart
MovaAdBreak(
  kind: MovaAdBreakKind.mid,
  source: MovaSource('https://cdn/ad.mp4'),
  offset: const Duration(seconds: 600),
  delay: const Duration(seconds: 3),     // "3 秒后播放广告"，期间正片继续播
  duration: const Duration(seconds: 15), // 买下的广告位是 15 秒，与素材长度无关
  skippableAfter: const Duration(seconds: 5),
);
```

* `duration`：素材更长会被准时收回，更短则播完即续播。
* `delay`：只对中插有意义；一个 pod 里只有**第一条**的 delay 生效。

两者的到期判定都是普通 `Timer`，到期后走与 `skip()` 完全相同的同步续播路径——**不**查询
媒体时长、**不** seek 到素材尾部（真机上靠近真实 EOF 的 seek 会可靠地卡死播放器）。
`duration` 必须长于 `skippableAfter`，否则 `assertValid()` 会在 debug 下大声失败。

### 等广告真的就绪再切入

判据一句话：**等待的价值，等于等待期间屏幕上那张画面的价值。** 中插期间那张画面是用户
正在看的正片，把它切成转圈既毁体验又把曝光花在黑矩形上；前/后贴片则没有正在进行的观看
体验需要保护。所以默认是 `pre` 否 / `mid` 是 / `post` 否：

```dart
MovaAdConfig(
  waitForAdReady: const MovaAdWaitByKind(post: true), // 后贴片也等（高价值下集预告）
  adReadyTimeout: const Duration(seconds: 5),
  notReadyAction: MovaAdNotReady.hardCut,             // 等不到就照今天的样子切
);
```

三层覆盖，越具体优先级越高：`MovaAdBreak.waitForReady` > 注入的 `MovaAdWaitPolicy` >
按 kind 的默认值。**仅在宿主接了 `MovaSwapCtl` 且 `MovaSwapConfig.enabled` 为 `true` 时
才可能生效**——两者默认都是关的，所以不接切换引擎的宿主行为逐字节不变。

等待与 `delay` 倒计时是两件独立的事：`delay == 0` + 等待正是中插的默认形态——用户看不到
任何倒计时，只会觉得"广告是无缝接上的"。两者同时开启时，接管时刻是
**max(倒计时走完, 广告就绪)**。

### 加载失败兜底

```dart
MovaAdConfig(
  failPolicy: const MovaAdRetrySkip(maxRetries: 0), // 默认：不重试，跳过这一条
  loadTimeout: const Duration(seconds: 8),          // 多久没有首帧算失败
);
```

四条失败路径——`open()` 抛出、播放期间播放器报错、始终没有首帧、预热未能及时就绪——
统一汇流到 `MovaAdFailPolicy`，返回 `retry` / `skipBreak` / `abandonPod`。内置另一个
`MovaAdAbandonPod`（首次失败即放弃整个 pod）。默认"观众的时间优先"：对一个坏掉的广告
地址重试，代价是让观众为一个他本来就没想看的东西再卡一次。

> **真机验证尚未进行**：等待是否真的消除黑屏、`adReadyTimeout`/`loadTimeout` 的默认值
> 是否合理、双活解码窗口在中低端机上的表现，均需真机逐项验证。checklist 见
> [doc/plans/2026-09-16-ad-swap-enhancements.md](doc/plans/2026-09-16-ad-swap-enhancements.md)
> Task 12。

## 无缝引擎切换（可选）

`MovaSwapEngine` 本身就是一个 `MovaApi`：在一个稳定的渲染面背后持有当前生效引擎，以及
一个可选的、正在预热的影子引擎；影子就绪后原子换指，UI 完全无感（不重挂、不黑屏）。
默认 **关闭**（`MovaSwapConfig.enabled` 为 `false`），关闭时是纯直通代理，行为与直接用
`MovaEngine` 完全一致。

```dart
final api = MovaSwapEngine(engineFactory: createMovaEngine);
// 或带上配置：createMovaEngine(options: MovaOpts(swap: MovaSwapConfig(enabled: true)))
final ads = MovaAdCtrl(api, swap: api); // swap 传同一个实例
runApp(MovaPlayer(api: api));
```

`MovaAdCtrl` 接了 `swap:` 参数后，会在广告播放期间按 `MovaSwapConfig` 配置的触发策略
（默认 `MovaLeadWarm`：结束前 2 秒开始预热，短于 5 秒的广告不预热）后台预热正片，广告一
结束就原子切换回正片，不再经过 `open()` 的黑屏/loading。清晰度切换目前仍走
`switchQuality()` 的传统路径（`engine.dart` 顶部有落点注释，说明如何映射到
`MovaSwapCtl.swapTo`）；`core/feed/engine_pool.dart` 的双画面并存需求不适用本模型，
两者仅共享 `MovaEngineFact` 这条原语。详见
[doc/plans/2026-09-16-seamless-swap.md](doc/plans/2026-09-16-seamless-swap.md)。

## App 内小窗（`MovaMini`，可选）

在不依赖任何系统 PiP API 的前提下，让画面从页面里"缩"成一个可拖拽的悬浮小窗——不重新
解码、不黑屏。与系统级 PiP（`MovaApi.enterPip()`）和 Android 那类需要权限的系统悬浮窗
（`SYSTEM_ALERT_WINDOW`）都不是一回事：本功能完全是 Flutter 自己绘制树里的合成，永远不
出 App，四端零权限、行为一致。默认 **关闭**（`MovaMiniConfig.enabled` 为 `false`）。

核心洞察：`MovaApi`/`MovaEngine` 是纯 Dart 对象，生命周期与 widget 树无关；只要宿主在
路由之外持有同一个 `MovaApi` 实例，把 `MovaPlayer` 从页面里卸载、在小窗里重新挂载，
libmpv 侧一个字节都不会重新解码——重挂的只是 Flutter 的 `Texture` widget。

两种挂载方式并存，按需选用，互不取代：

### 方式 A · 页内悬浮（mova 实现）

就在当前页面内部浮着：不受页面滚动内容影响、可拖拽移动位置；页面被 pop，小窗随之消失
（这正是"页内"该有的语义，不是缺陷）；`push` 新路由会盖住它，`pop` 回来又在。

```dart
final mini = MovaMiniCtl();

// 打开小窗：
await mini.showInPage(context, api);

// 页面 dispose() 里必须调一次 hide() 或 close()，否则 MovaState.mini 会停在
// true 而无人渲染：
@override
void dispose() {
  if (mini.isShowing(api)) mini.hide();
  super.dispose();
}
```

### 方式 B · 跨路由持久（mova 只给便利壳 + 文档）

跨路由常驻：push/pop 任意多层，小窗一直在最上。mova 只保证底层能力
（controller 与路由生命周期解耦）；`MovaMiniHost` 是一个约 30 行的可选便利壳：

```dart
final miniCtl = MovaMiniCtl(); // 建在 app 根，路由之外

MaterialApp(
  builder: (context, child) => MovaMiniHost(ctl: miniCtl, child: child!),
  home: const HomePage(),
)

// 播放页里点"缩小"：
await miniCtl.show(api);
Navigator.of(context).pop();   // 引擎不受影响，画面在小窗里继续
```

不想用 `MovaMiniHost` 也可以，等价的手写 `Stack`：

```dart
builder: (context, child) => Stack(children: [
  child!,
  // 用 ListenableBuilder/AnimatedBuilder 订阅 miniCtl：
  if (miniCtl.api != null)
    Positioned.fill(child: MovaMiniWindow(
      ctl: miniCtl, api: miniCtl.api!, config: miniCtl.api!.options.mini)),
]),
```

### ⚠️ 谁 dispose engine

mova 一贯的约定是"宿主持有 engine"——`MovaPlayer`/`MovaMiniCtl` 从不 dispose 传进来的
`api`。**页面 `dispose()` 里顺手 `api.dispose()` 是最常见的错误用法**，会在交接瞬间把
正在小窗里播的引擎干掉。`MovaMiniCtl.isShowing(api)` 让页面在 `dispose` 前自检；
`MovaEngine.dispose()` 在 `state.mini == true` 时还会打一条 debug-only 的 `assert` 兜底
（release 零成本）。

### 与系统 PiP / 系统悬浮窗的关系

三者正交、互斥生效：① `enterPip()`（Android 系统级）把**整个 Activity**缩成系统悬浮窗，
退出 App 后仍在；② `flutter_overlay_window` 一类**系统悬浮窗**需要 `SYSTEM_ALERT_WINDOW`
权限，画在自家 App **之外**；③ 本功能只在自家 App 前台的绘制树里做文章，**不出 App**，
但没有任何平台门槛。Flutter 的 `Overlay`/`OverlayEntry` 与 Android 的系统悬浮窗只是同名，
毫无关系。

demo 见 [example/lib/mini_window_demo.dart](example/lib/mini_window_demo.dart)（
`flutter run -t lib/mini_window_demo.dart`）。详见
[doc/plans/2026-09-23-app-inline-pip-overlay.md](doc/plans/2026-09-23-app-inline-pip-overlay.md)、
[doc/SPEC.md](doc/SPEC.md)「App 内小窗（MovaMini）」一节。**真机验证未做**（Task 12）。

## 仅音频模式（`audioOnly`）

同一个项目里既要放视频也要放纯音频时，音频那条路不该背视频的资源开销。
`audioOnly: true` 构造出的引擎**不建立任何视频管线**：默认内核跳过 `VideoController`，
抽帧兜底也不接线。此时 `renderHandle` 为 `null`，`MovaPlayer` 渲染黑色占位——
或者你传给它的任意 `surface`（封面、波形、歌词面）。

默认 **关闭**（`audioOnly` 为 `false`），关闭时行为与不加这个参数时逐字节相同。

```dart
final engine = createMovaEngine(
  audioOnly: true,
  options: const MovaOpts(preview: MovaPrevConfig(enabled: false)), // 没有帧可预览
);
runApp(MovaPlayer(api: engine, surface: CoverArt(url: coverUrl)));
```

### 省下多少

media_kit 的 `Player` 一创建就是 mpv 的 `--vid=no`，**只有** `VideoController.create()`
会把它改回 `vid=auto`。因此不挂接它，libmpv 就只解音频：**解码帧缓冲、GPU 纹理、
Flutter `Texture` 注册这三项直接是 0，而不只是变小**——它们正是视频侧内存开销的全部。
量级上：内存约差两个数量级（MB 级 vs 近百 MB 级），CPU 与电量差一个数量级以上。

> ⚠️ 上述"两个数量级"是按编解码参数**推算的分项量级**，只在单独比帧缓冲/GPU 纹理
> 这几项时成立，**不要用它推整机内存**。
>
> **Windows 桌面端已有实测**（同一条 854×480 素材，`ProcessInfo.currentRss`，各两轮）：
> 视频模式播放期内存增量均值 **197 MiB**，audioOnly **96 MiB**，
> **省约 101 MiB，倍率约 2.05×**——是约 2 倍，不是两个数量级，因为 RSS 还包含
> Flutter engine 与 libmpv 自身那份两种模式都要付的常驻开销。同一轮实测还直接确认了
> `audioOnly` 下 `MovaState.size` 为 `0x0`（视频轨压根没解码）、`renderHandle` 为
> `null`。完整数据与口径说明见
> [doc/notes/2026-09-16-audio-only-feasibility.md](doc/notes/2026-09-16-audio-only-feasibility.md) §1.5。
>
> **Android/iOS 真机验证仍未进行**，桌面 RSS 与移动端 `dumpsys meminfo` 不能直接类比。
> 复现方式见 [example/README.md](example/README.md) 的 RSS 探针一节。

反直觉的一点：**包体积不随模式变**。只要还链着 `media_kit_libs_video`，那 ~11.8 MiB/ABI
的 `libmpv.so`（含 ffmpeg）就照样在包里，不管你运行时放不放视频。

### 该用 mova 还是换 just_audio

> 需要熄屏后台常驻 + 系统媒体控制吗？
> 需要 → `just_audio` + `audio_service`。
> 不需要（只是前台界面里放一段音频） → mova 的 `audioOnly` 模式，别多引一个插件。

mova 在音频模式下**没有**这些东西：后台常驻、锁屏/通知栏、耳机线控、音频焦点、
gapless、歌单。补齐它们是一整套四端原生工程，不在 mova 的范围内。反过来，控制条、
手势、时移、ABR、广告、拦截器这些 mova 已有的东西在音频模式下照常工作——换插件反而
要把它们再实现一遍。

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

`MovaSystemChromeOrientationPort` 只处理移动端的方向锁定/沉浸式系统 UI；在
Windows/macOS/Linux 上没有对应的"真全屏"概念（把 OS 窗口撑满屏幕、去掉标题栏），
调用 `setFullscreen(true)` 在桌面端不会有可见效果。mova 不内置窗口管理
依赖，桌面端真全屏留给宿主自己接：

```dart
engine.events.listen((e) {
  if (e is MovaFullScreenChg) {
    // 例如用 window_manager 包切换真实的 OS 窗口全屏。
    windowManager.setFullScreen(e.value);
  }
});
```

`MovaFullScreenChg` 事件在 `setFullscreen()` 每次调用时都会发出，与
`MovaOrientPort` 无关——不需要实现整套 `MovaOrientPort` 接口（那是给移动端
方向/沉浸式 UI 设计的），监听事件流即可。

## 自定义皮肤 / Custom skins

三档定制，由浅入深：

1. **补丁档**：`MovaDefSkin(patches: [...])`——增/删/替换/重写组件、在已有插槽间挪位置。
2. **半覆写档**：`extends MovaDefSkin` 只覆写某一层的受保护方法
   （`buildPlaybackLayer`/`buildOperableLayer`/`buildPersistentLayer`），重排版而复用其余各层。
3. **全实现档**：`implements MovaSkin` 重写 `components()`/`assemble()`，布局与组件全自定义。

内置皮肤是三层骨架：**播放层**（画面）+**操作层**（手势/顶中底/左右栏，随闲置一起淡隐、
pip/锁定时整层隐藏）+**常驻层**（锁定遮罩与锁定/解锁按钮，恒挂载、默认穿透、不受门控）。
组件树是静态的（`components()` 不吃状态），显隐由组件各自的 `MovaSelect` 响应式决定。
插槽词表：`top`/`center`/`bottom`/`bottomAbove`/`overlay`/`left`/`right`/`gesture`/`hud`。

打补丁或整体实现 `MovaSkin`：

```dart
// 去掉顶栏里的画中画按钮（等价于 0.1.0 里派生子类删掉一个按钮）。
const noPipSkin = MovaDefSkin(
  patches: [MovaPatch.remove('topBar/pipButton')],
);

MovaPlayer(api: engine, skin: noPipSkin);
```

```dart
// 在顶栏追加一个自定义组件。
final withExtra = MovaDefSkin(
  patches: [MovaPatch.add(MovaSlot.top, MyExtraButtonComponent(), order: 10)],
);
```

需要完全不同的排版时，直接实现 `MovaSkin`：

```dart
class MySkin implements MovaSkin {
  @override
  List<MovaComp> components() => [/* 自定义组件树（静态） */];

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

## Roadmap / 路线图

见 [doc/ROADMAP.md](doc/ROADMAP.md) 与 [doc/DESIGN-0.2.0.md](doc/DESIGN-0.2.0.md)。
阶段 A（本次，core/ui 分层重构）已完成；阶段 B（拖动预览缩略图）、阶段 C（直播
时移）、阶段 D（收尾发布）计划见 DESIGN 文档 §7/§8/§12。

## License

MIT
