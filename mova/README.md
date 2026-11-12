# mova

A Flutter video player built on [media_kit](https://pub.dev/packages/media_kit)
(libmpv/ffmpeg) with a self-built gesture + control layer for VOD and live
playback.

基于 [media_kit](https://pub.dev/packages/media_kit)（libmpv/ffmpeg 内核）的
Flutter 视频播放库，自研手势与控制层，支持点播与直播。

> **Repository version / 仓库版本：0.4.1**（以 pubspec.yaml 为准）。
> CHANGELOG 的 `Unreleased`（若有）是当前发布版本之后的仓库能力，使用 path/git 依赖才能拿到；
> 安装某个 pub.dev 版本前请核对对应 CHANGELOG，不能把仓库功能视为已发布功能。
> Android/Windows 有部分真机验证；iOS 未验证，CP2/CP3 仍待真机，
> CP1 为 13 PASS / 3 BLOCKED，尚未整体通过。目标设备验收范围见
> [SPEC](doc/SPEC.md) 与[验收矩阵](doc/ACCEPTANCE-MATRIX.md)。

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
- **Ad orchestration / 广告编排（可选）**：`MovaAds` 按排期播前/中/后贴片，
  支持延迟解析正片源、广告位时长与素材时长解耦、就绪等待、失败兜底。
- **Seamless engine swapping / 无缝引擎切换（可选）**：`MovaCutoverEngine` 在一个稳定渲染面
  背后持有当前引擎与预热中的影子引擎，就绪后原子换指，消除"广告播完回正片"等场景的
  黑屏/loading。默认关闭。
- **In-app mini window / App 内小窗（可选）**：不依赖系统 PiP，把画面缩成可拖拽悬浮小窗，
  不重新解码、不黑屏。默认关闭。
- **Audio-only mode / 仅音频模式（可选）**：跳过视频管线，只解音频，省内存/CPU。默认关闭。

## Platform support / 平台支持

| | Android | iOS | Windows |
|---|:---:|:---:|:---:|
| 播放 / 手势 / 控制条 | ✅ | 未验证 | ✅ |
| 画中画 PiP | ✅ | ❌ | ❌ |

> iOS/桌面 PiP：media_kit 用 libmpv 纹理渲染，系统级 PiP 依赖 AVPlayer 路径，暂未实现，`isPipSupported()` 返回 `false`。详见 [doc/SPEC.md](doc/SPEC.md)「PiP（原生）」一节。

## Known limitations / 已知限制

- iOS/桌面（Windows/macOS/Linux）暂不支持系统级画中画。
- 桌面平台（Windows/macOS/Linux）没有"真全屏"（撑满 OS 窗口、去标题栏）能力，`setFullscreen()` 本身只更新状态/方向，应用内铺满可用 `MovaPlayer(fullscreenRoute: true)`；OS 窗口全屏需宿主自己接 `window_manager` 一类的包（见下方「平台端口」一节）。
- TLS 严格校验（`createMovaEngine(tlsVerify: true, tlsCaFile: ...)`，默认关闭，此时 Android libmpv 不校验证书）：**Android 上开启必须同时传 `tlsCaFile`（PEM 格式 CA 包，例如拼接 `/system/etc/security/cacerts/` 下的证书），否则所有 HTTPS 都会失败**（瘦身 libmpv 用 mbedtls、无系统信任库）；IP 直连不校验证书主机名，仅域名生效；iOS/macOS 未验证。
- 仅音频模式（`audioOnly`）不提供后台常驻播放、锁屏/通知栏控制、耳机线控、音频焦点、gapless、歌单——这些需要 `just_audio` + `audio_service` 一类的专用方案。
- **带画面内核的 `VideoController` 必须真正挂到界面上才能正常销毁**（这是 media_kit 的行为，不是 mova 引入的）：`VideoController` 创建后若一直没有挂到视频组件上，`Player.dispose()` 会一直等它，真机实测 Windows 上 3/6 次、Android 上 4/5 次 dispose 撞上 8 秒超时。默认实现（`createMovaEngine()` / `MovaEngine()`）已做成**懒创建**——第一次渲染（`MovaPlayer` 挂上树，读取 `renderHandle`）时才创建，所以"创建了 engine 却没展示就销毁"是安全的。**如果你自己创建并注入 `VideoController`（传入自己构造的 `MovaMpvKernel`/`Player`，或用 `lazyVideo: false` 的内核），要自己保证它最终挂到了 UI 上再销毁**；纯逻辑、后台预热、单测等不展示画面的场景请用 `audioOnly: true`，或保持默认懒创建、不要读取 `renderHandle`。无缝切换的影子引擎例外：预热阶段就需要解码画面，会提前创建控制器。
- **Windows 上 Flutter 3.47.0/3.47.1（Impeller）：push/pop 不透明路由会让进程原生崩溃**——引擎 bug（flutter/flutter#190774，3.47.2 已修），与 mova 无关，纯 media_kit 也崩。mova 已在 Windows 上让播放器渲染面退出页面转场快照来规避；仍建议宿主升级到 Flutter ≥ 3.47.2。自己直接用 media_kit `Video` 的页面不受这层规避保护，需自行升级或对转场关快照（`ZoomPageTransitionsBuilder(allowSnapshotting: false)`）。
- 自动暂停守卫（`MovaAutoPause`）的视口检测只沿祖先 `Scrollable` 计算，**不覆盖**任意 `ClipRect`/`Transform`/`Overlay` 造成的遮挡；外层 navigator 上的半透明路由要传 `routeObservers`（每个 navigator 一个观察者，不能共用）；懒加载列表如果在守卫来得及暂停之前就销毁了卡片，此后引擎归持有者管。
- 待机已有 Windows release 数据（FLV 唤醒 18/18 走 grace，耗时读数为 5s 兜底，不能当首帧实测耗时），Android CP1 S1/S7/S13/S14 为 20/20；HLS、耗电、iOS/macOS 仍未充分验证。见[待机验证记录](doc/plans/2026-10-23-standby-mode.md)及 [CP1](doc/plans/2026-11-03-cp1-results.md)。
- recovery、广告和 cutover 现由会话仲裁：非终结诊断交给引擎；恢复中等 giveUp，广告终结失败按广告策略裁决一次；正片失败进入 `contentError`，不自动换集。宿主新 open 优先，旧会话和旧影子让位。
- Feed 的池外网络预取只做约 **64KB** 的 Range 请求（默认 `bytes=0-65536`，含两端为 65537 字节）；代码会 drain 响应，服务器忽略 Range 时可能拉完整资源；HLS 只拿 **m3u8**，不预取媒体分片。每次预取 `force close`，连接不能复用；池外直播条目的引擎仍可能满速拉流，预取不能代替限流或离线缓存。
- STT 模型下载是**实验实现，无校验和校验**，本包不内置识别引擎。
- **不支持 DRM、投屏、离线下载**。
- 部分可选能力（广告编排、无缝引擎切换、App 内小窗、仅音频模式）代码已落地但真机验证程度不一，详见各自小节链接的 [doc/SPEC.md](doc/SPEC.md) 章节。

## Install / 安装

```yaml
dependencies:
  mova: ^0.4.1
```

Android 要用画中画，需在 `AndroidManifest.xml` 的 Activity 上声明：

```xml
<activity
    android:name=".MainActivity"
    android:supportsPictureInPicture="true"
    android:configChanges="orientation|screenSize|screenLayout|smallestScreenSize|...">
```

## 能力入口（仓库 Unreleased）

`package:mova/mova.dart` 本版继续兼容导出原有符号。按能力可选用：

| 入口 | 用途 |
|---|---|
| `package:mova/skin.dart` | 组件、插槽、作用域、MovaChrome、样式 |
| `package:mova/ads.dart` | 广告及配置 |
| `package:mova/feed.dart` | Feed 数据、组件、控制器及预取 |
| `package:mova/mini.dart` | 小窗及配置 |
| `package:mova/extend.dart` | 会话、cutover、预览、平台端口、上报 |
| `package:mova/stt.dart` | STT 端口、字幕与实验模型下载 |

STT 从主入口转导出只保留一个版本，建议改导入 `stt.dart`；`MovaApi.stt` 保留。
导出上的内部 helper 隐藏公告见 [SPEC](doc/SPEC.md)，本版尚未加成员级弃用注解。

## 应用内全屏与视图样式（仓库 Unreleased）

```dart
MovaPlayer(
  api: engine,
  fullscreenRoute: true, // 默认 false；根 Navigator 推送 mova/fullscreen
  style: const MovaPlayerStyle(strings: MovaStrs(retry: '再试一次')),
)
```

返回键先退出全屏，锁定时提示解锁；路由借用同一 API、自建 chrome，退出唤出内联控制条。
方向与 PiP/mini 仍由引擎管理；Windows 自定义 surface 同样受快照守卫保护。
`MovaPlayerStyle` 按节查找：视图参数 > ThemeExtension > 旧 options > 默认，切主题不重建引擎。
组件可用 `MovaChrome.of(context)` 控制自己视图的 HUD/控制条/拖动；锁定、fit、zoom 仍共享。

## 源请求头与起播点（仓库 Unreleased）

```dart
const source = MovaSource(
  'https://cdn.example/video.mp4',
  headers: {'Authorization': 'Bearer token'},
  userAgent: 'MyApp/1.0',
  start: Duration(seconds: 30),
);
```

显式 userAgent 覆盖同名头。播放、清晰度探测、VTT/雪碧图、抽帧及 Feed 预取共用头，
`start` 只用于点播，经 seek 寄存链等就绪。自定义旁路 HTTP 应实现
`MovaHeaderedHttpFetch.getWithHeaders(Uri url, Map<String, String> headers)`；
旧 `MovaHttpFetch.get(Uri)` 仍可用，但头会丢失，每实例只在 debug 提示一次。
默认 IO 实现逐请求设置、不泄漏到下一请求；自定义抽帧可实现 `MovaHeaderedFramePuller`。

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
    engine = createMovaEngine();
    _open();
  }

  Future<void> _open() async {
    try {
      await engine.open(const MovaSource(
      'https://example.com/master.m3u8',
      type: MovaStreamType.live, // 或 MovaStreamType.vod
      title: '示例',
      ));
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
    }
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

> **提示**：应用使用 `package:mova/mova.dart` 导出的 `createMovaEngine()`，默认接好
> 亮度/PiP/方向端口。`MovaEngine()` 裸构造默认使用空平台端口，适合测试或自行注入端口，
> debug 下会一次性提示。

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

## 声明式用法（MovaView）

只想"挂一个卡片、给个地址就播"，不用自己管引擎生命周期：

```dart
MovaView(
  source: url == null ? null : MovaSource(url, type: MovaStreamType.live),
  fit: MovaFit.cover,
  poster: Image.network(cover, fit: BoxFit.cover),
  skin: const MovaMinimalSkin(),
)
```

- 第一次拿到非空 `source` 才创建引擎；`source` 真正变了（`MovaSource.sameAs`：比较 uri、type、备选地址、源选项、headers/userAgent/start，**不比 title**）才重开，同源重建不会重开流。
- `source` 变 `null`：引擎暂停，只剩封面（没封面就是黑底）。
- 仅引擎实际读取的配置节变化会**销毁并重建**引擎；等值内联配置、ads/playlist/mini 变化不会重建。UI 样式变化只更新视图；引擎的 options 保留构造快照。
- 打开失败走 `onOpenError`，不传就交给 `FlutterError.reportError`，不会变成未捕获的异步异常。
- 需要把引擎传来传去（跨路由小窗等）时，继续用命令式的 `createMovaEngine()` + `MovaPlayer`；**别把 `MovaView` 持有的引擎交给 `MovaMini`**，`MovaView` 卸载时会把它销毁。

## 封面与出画面信号

`MovaState.playing` 在**发起加载之前**就会变 true，不能用来判断"有没有出画面"。用 `MovaState.rendered`：当前源的首帧已上屏（无视频的源是首段音频已出声）。每次 `open()` 重置为 false；换档、回直播边缘、重试这类内部重载**不**重置，免得封面白闪一下。

```dart
api.events.listen((e) {
  if (e is MovaFirstFrame) log('首帧 ${e.sinceOpen} 经 ${e.signal}');
});
```

- 判据：原生 `PLAYBACK_RESTART` 最准；没订阅时退到 buffering 下降沿、连续递增位置、暂停态首个画面尺寸。原生订阅在工作却迟迟不来 RESTART，最多等 1.5s 宽限就落地。
- **默认首次 open 懒订阅 END_FILE，RESTART 默认不开**（每个引擎一个 mpv 弱客户端，debug 下还有 100ms 轮询；END_FILE 与 recovery 开关无关）：`createMovaEngine(preciseFirstFrame: true)` 打开，首帧更准（真机上 buffering 兜底比真实 RESTART 早约 200ms，偏乐观）；`MovaView` 有 `poster` 时默认开。
- `MovaPlayer(poster:)` / `MovaView(poster:)`：封面叠在传给皮肤的"画面层"里，缓冲转圈、错误层、控制条都画在它上面；`rendered` 且画面尺寸已知后淡出（`posterFade`），换源瞬间重新盖上；纯音频源封面常驻。`MovaFeedPlayer(posterUntilFirstFrame: true)` 同理，默认关闭。
- 填充模式声明式：`MovaEngine(fit:)` / `createMovaEngine(fit:)` 给初值，`MovaPlayer(fit:)` / `MovaView(fit:)` 在挂载与**该参数变化**时应用一次；用户点 fit 按钮选的值不会被无关重建覆盖。
- 想要没有手势、没有任何栏的纯画面：`MovaMinimalSkin(showBuffering:, showError:)`；转圈尺寸/线宽/颜色用 `MovaTheme.bufferingSize/bufferingStrokeWidth/bufferingColor`（默认 `null` 即旧外观）。

## 播放错误

`state.error` 只保存终结错误，供重试遮罩和失败状态使用；包括 `END_FILE(error)`、恢复放弃、已知终结文本以及 open 抛出。默认配置也检测 END_FILE，弱客户端在首次 open 时才启动；每次加载前排空旧事件，并按加载尝试丢弃迟到通知。同次尝试仅一次终结上报，重复日志保留为诊断；待机失败静默记录，唤醒时重开。recovery 关闭时 open 失败本版本仍抛出，同时写终结状态；下一版本将不再抛出。

无 END_FILE 事件泵或注册失败时，补回主文件打开失败的兜底：在错误到达时检查泵可用性，仅 stream/cplayer/ffmpeg 错误文本包含当前主文件有效地址时，进入同一恢复或终结入口。外挂字幕、外部音轨和 HLS 分片的独立地址不会触发此兜底；泵已激活时仍由 END_FILE 判定终结。

非终结内核日志继续发送 `MovaErrorEvent(fatal: false)` 并通知 `MovaHook.onError`，不会写 `state.error` 或弹出错误遮罩。迁移原有“监听 state.error 收集所有错误”的代码时，改监听事件：

```dart
engine.events.listen((event) {
  if (event is MovaErrorEvent) {
    recordDiagnostic(event.error);
    if (event.fatal) showPlaybackFailure();
  }
  if (event is MovaPlayFailure) recordRecoveryDecision(event.action);
});
```

启用 recovery 时可用 `MovaPlayFailure` 跟踪每次重试/切源/放弃决策。错误遮罩文案由 `MovaStrs(playbackError: '播放失败，请重试', retry: '重试')` 配置，原始错误文本仅在 debug 模式显示。有封面的 `MovaPlayer`/`MovaView` 会开启 RESTART 精确首帧。

## 超时与多地址（可选，默认关闭）

默认已通过 `END_FILE(error)` 检测终结失败并结束转圈；`MovaOpts.recovery` 额外提供超时兜底、重试与多地址切换：

```dart
createMovaEngine(
  options: const MovaOpts(recovery: MovaRecoveryConfig(enabled: true)),
);
// 地址按你的优先级排好，mova 只保证按给定顺序尝试
final src = MovaSource.pick([hd, sd, backup], type: MovaStreamType.live);
```

- 触发源：**起播超时**（没出首帧，由 `timeouts` 派生的兜底期限，默认非 WHEP 65s / WHEP 85s；`autoPlay: false` 的暂停态打开不计时，`play()` 后从头计）、**卡顿超时**（出首帧后连续缓冲，兜底期限默认非 WHEP 65s / WHEP 10s，`stallWatchdog: false` 关闭；暂停即停表）、`open()` 抛异常、原生 `END_FILE(error)`（坏地址秒判，不等超时；默认即订阅，与 `recovery` 无关，不必再加 `preciseFirstFrame`）、直播走到结尾（`liveEndIsFailure`，默认算失败）。
- 默认策略 `MovaDefaultRecovery`：**点播**走 `MovaRetryThenFailover`（每个地址等 1s 重试 1 次，再切下一个备选，全部用完放弃，行为与以往一致）；**直播**走 `MovaLiveReconnect`（指数退避 1s、2s、4s…封顶 15s（`maxDelay` 可调）持续重连，推流端重启/掉线后自动接上；有备选时前面的地址各重试 1 次再切，最后一个地址一直重连，`maxAttempts` 可设上限）。不想让直播一直重连：`MovaRecoveryConfig(liveReconnect: false)`，直播回到和点播一样的"重试 1 次就放弃"。`MovaFailoverOnly` 不重试同一地址；也可以实现 `MovaRecoveryPolicy` 整体替换（策略抛异常按放弃处理；`MovaPlayFail.isLive` 可用来区分直播）。
- **重连分工**：超时由 libmpv/ffmpeg 负责，Dart 只处理重连。直播**不开** libmpv 的 `reconnect_streamed`，断流重连全部交给 `MovaLiveReconnect`（指数退避、多地址切换、事件）；点播**保留** mpv 默认的 ffmpeg 重连（Range 续传，窗口约 11s）。触发重连的**主路径是 mpv 的 `END_FILE(error)`**；Dart 的 `startTimeout`/`stallTimeout` 只是**兜底看门狗**，覆盖 mpv 不报错的卡死（缓冲一直转圈、WHEP 因服务端 STUN 保活让 `media_timeout` 不触发等）。
- **统一超时配置 `MovaRecoveryConfig.timeouts`（`MovaTimeouts`）**：`network`→mpv `network-timeout`（整秒），`whepHandshake`/`whepFirstFrame`/`whepMedia`→WHEP 的 `handshake_timeout`/`first_frame_timeout`/`media_timeout`（微秒，仅 `whep…` 地址），每次 open 前下发给 mpv；不设就不动 mpv 默认值。`MovaSource.mpvOptions`/`demuxerOptions`/`whepMediaTimeout` 对同一选项的显式设置优先。
- **看门狗期限默认从 mpv 窗口派生**：`startTimeout`/`stallTimeout` 不设时 = mpv 侧最长窗口 + 5s 余量，保证 mpv 重连/握手窗口内看门狗不会先断开；显式设置则以你的值为准（设得比 mpv 窗口短会打断 mpv 的重连）。mpv 窗口：非 WHEP 为 `max(network, 11s)`（未设 `network` 按 mpv 默认 60s；11s 是 ffmpeg 重连窗口），WHEP 起播为 `network+handshake+firstFrame`（默认 60+10+10）、卡顿为 `media_timeout`（默认 5s）。关掉卡顿看门狗用 `stallWatchdog: false`（取代旧的 `stallTimeout: null`）。
  ```dart
  // 10s 网络超时：非 WHEP 起播/卡顿兜底 16s；WHEP（握手5/首帧8/media5）起播 28s、卡顿 10s
  const MovaRecoveryConfig(
    enabled: true,
    timeouts: MovaTimeouts(
      network: Duration(seconds: 10),
      whepHandshake: Duration(seconds: 5),
      whepFirstFrame: Duration(seconds: 8),
      whepMedia: Duration(seconds: 5),
    ),
  );
  ```
- 确定性失败（404、拒连、`open()` 抛异常、加载在途时到达的 `END_FILE(error)`）一经发现就按策略的退避进入下一次尝试，不必等满 `startTimeout`。
- 事件：每次失败发 `MovaPlayFailure(fail, action)`（`fail.kind` 区分起播/卡顿/…，此时**不**写 `state.error`，还在重试）；失败后重新出画面发 `MovaRecovered`，同时清掉失败期间遗留的 `state.error`；切备选发 `MovaFailover(from, to, uri)`，`MovaState.sourceIndex` 同步；全部失败后写 `state.error = MovaGiveUpError`、发 `MovaErrorEvent`，把残留的 `state.buffering` 置回 false，并暂停内核（离线的直播源不会在后台一直重连）。错误层的"重试"走 `reload()`，从主地址开一个全新会话。
- 重试/切换是内核重载，**不是新会话**：不过 `beforeOpen` 拦截器、不发 `MovaSourceChange`、不动 QoE 会话；`MovaSourceChange`/`MovaReady` 每次 `open()` 只发一次。点播源失败前出过画面的，重载后续播到失败位置。
- **没开 `recovery` 时 `alternatives` 会被忽略**（失败检测是 recovery 提供的），`open()` 失败仍然照旧抛给调用方；开启后 `open()` 失败改为发 `MovaPlayFailure(openThrew)` 并重试，不再抛。
- **按源传 libmpv / ffmpeg 选项**：`MovaSource(mpvOptions:, demuxerOptions:, whepMediaTimeout:)`。`mpvOptions` 是 mpv 选项名到值（如 `{'cache': 'no'}`），`demuxerOptions` 合成进 `demuxer-lavf-o`；都在该源加载前下发、下一个源加载时还原，不会泄漏到别的源，mpv 不接受的选项静默跳过。`demuxer-lavf-o` 是按键并入现有列表（mpv 的 `change-list add`），还原时只删本源加的键、被顶掉的同名键补回原值，media_kit 默认的 `protocol_whitelist`、`allowed_extensions` 等始终保留。WHEP 直播源可以直接写 `whepMediaTimeout: Duration(seconds: 3)`（换算成微秒的 `media_timeout`，只对 `whep…` 地址生效，显式的 `demuxerOptions['media_timeout']` 优先），推流端掉线后更快判失败、更快重连：
  ```dart
  const MovaSource(
    'whep+http://host:8889/x/whep',
    type: MovaStreamType.live,
    whepMediaTimeout: Duration(seconds: 3),
  );
  ```
- 直播的时长一直在涨，`MovaDurationChange`（及 `state.duration`）对直播源按 `MovaLiveConfig.durationStep`（默认 2s）节流：变化不足一个步长不上报；`Duration.zero` 恢复每次都报。点播不受影响。
- mova 不提供备选地址的排序/过滤钩子：排序依据（比如档位名）和协议能否播放（取决于你用的 libmpv 构建）都是宿主才知道的，排好序传进来即可。`MovaSource.pick` 只做清洗：去空白、去空串、去重、保序。

## 自动暂停（可选）

滚出视口、切到别的 Tab、被别的页面盖住、应用进后台时自动暂停，回来再续播：

```dart
MovaView(source: src, autoPause: const MovaAutoPauseConfig())
// 或手动包：MovaAutoPause(api: engine, child: MovaPlayer(api: engine))
```

- 只用 Flutter SDK，不依赖可见性三方包：滚动视口（沿祖先 `Scrollable` 算可见比例，`minVisibleFraction` 可调）、`TickerMode`（`go_router` 的 `indexedStack` 给非活跃分支套了 `Offstage + TickerMode(enabled:false)`）、`ModalRoute.isCurrentOf`、`AppLifecycleListener`。
- Dialog / BottomSheet 算"盖住"（对话框是半透明路由，盖在同一个 navigator 上时 `isCurrentOf` 为 false）。
- **全屏 / 画中画 / App 内小窗豁免页面遮挡与可见性暂停**（后台仍按守卫配置）。`inactive`（下拉通知栏、Android 系统画中画）不暂停，但会先记下"是否在播"——Android 切后台可能先收到播放暂停观测，不先记就会误判成"本来就没在播"，回前台也不续。
- 直播恢复：暂停点可能已滑出 HLS 窗口、HTTP-FLV 连接也可能已断，所以隐藏 ≥ `liveResumeGrace`（默认 3s）后默认 `backToLiveEdge()` 再播，不足 3s 就普通 `play()`；`liveResume: MovaLiveResume.resume` 则一律普通续播。
- **外层 navigator 上推的半透明路由**（典型：`go_router` 的 shell 分支里放卡片，根 navigator 弹对话框/透明页）`ModalRoute.isCurrentOf` 看不到，要传 `routeObservers`：**每个 navigator 一个** `RouteObserver<ModalRoute<dynamic>>`（Flutter 不允许一个 `NavigatorObserver` 挂到两个 navigator 上，会在 debug 下断言失败），把它们都传给守卫。不透明的外层路由（普通整页）转场结束后已经能经 `TickerMode` 察觉，不需要。
- `MovaFeedPlayer` 内置整条 feed 的守卫（`autoPause: null` 可禁用），不要给每一页另套守卫；翻页互斥由池管理。
- 有视频渲染面的 `MovaPlayer` 默认经 `api.pause()` 处理后台暂停，回前台不自行续播；祖先同 API 的 `MovaAutoPause` 可接管（如 `background: false`）。旧后台暂停来自 media_kit `Video.pauseUponEnteringBackgroundMode` 默认值；已关闭该默认路径，不把 surface 回收当成已证实的唯一原因。audioOnly 无视频面，不受此兜底影响。

## 隐藏时待机（keepAlive，可选）

直播卡片被隐藏（切 Tab、滚出屏、被路由盖住）时，除了暂停，还可以让它"待机"：不出画面、不出声，但**保持流连接和直播进度**。重新显示时只需恢复视频解码，不用再走"重新请求 → 首片 → 解码器 → 首帧"整条链路。

```dart
// 守卫自动处理（推荐，默认仍是 pause）
MovaView(
  source: live,
  autoPause: const MovaAutoPauseConfig(hiddenMode: MovaHiddenMode.keepAlive),
)

// 或命令式：引擎实现了 MovaKeepAlive，MovaApi 本身没有新增成员
final api = createMovaEngine();
if (api is MovaKeepAlive) {
  await api.setKeepAlive(true);   // 卡片滑走
  await api.setKeepAlive(false);  // 回到屏幕
}
```

- **机制**：流里有音频 → 关视频解码并静音（音频链当时钟，demuxer 继续追边缘）；流里没有音频 → 继续解码、只静音；点播、进后台、媒体信息未知、HLS（默认）→ 退回普通暂停。待机最长 `MovaKeepAliveConfig.maxDuration`（默认 30s），到点自动退回暂停。
- **网络一点不省**：待机期间照常满速下载，省的是解码/渲染/电。蜂窝网络下建议由宿主自己改回 `hiddenMode: MovaHiddenMode.pause`；**列表里有多张直播卡片时只给主卡片开待机**——每张待机卡片都在满速下载。
- **默认只对 FLV 这类直播生效**：HLS/DASH 默认暂停（`MovaKeepAliveConfig.allowHls: false`），可切回 `vid` 后 demuxer 是否回读网络、是否在直播窗口滑走后出问题都还没真机测过。
- **恢复要等关键帧**：典型等 0~1 个 GOP，不重连。`MovaKeepAliveResume.elapsed` 记录从唤醒调用到第一帧新画面的耗时，`signal` 说明由什么落地。
- **进后台一律暂停**：守卫在应用进后台时会把待机降级为暂停（系统会限网限 CPU）。命令式使用者要自己在进后台时 `pause()`。
- **只有 `setKeepAlive(false)` 能唤醒**：待机期间程序性的 `play()`（广告、播放列表）不会让看不见的卡片出声。待机请求存在期间 `open()` 换源，新源以暂停态加载，首帧落地后若仍应播放再尝试一次进入待机。
- 调参在 `MovaOpts.keepAlive`（`MovaKeepAliveConfig`：`maxDuration`/`silentStreams`/`allowHls`/`resumeTimeout`/`liveResumeGrace`），只有调参没有开关——不调用 `setKeepAlive` 就一行待机代码都不会走到。
- 状态与事件：`MovaState.keepAlivePhase`（`off`/`holding`/`fallback`/`resuming`）、`MovaKeepAliveChange`、`MovaKeepAliveResume`。有封面（`poster`）时，待机与恢复期间封面会瞬间盖上、恢复落地后淡出。
- 待机期间 QoE 照计观看时长与卡顿（本期没有让 collector 识别待机）。
- 宿主 widget 测试里，`MovaTestKernel` 的 `hasAudio`（默认 `null` = 媒体信息未知，此时会退回暂停）与 `fileFormat` 可编排待机场景。
- 验证页：`example/lib/main_keep_alive_verify.dart`；Windows 已部分实测，Android CP1 见上方记录，不能据此视为 CP2/CP3 已通过。

## widget 测试

宿主的 widget 测试里，`createMovaEngine()` 默认会构造真实的 media_kit `Player`，报 `MediaKit.ensureInitialized must be called`。用测试入口换成可编程内核：

```dart
import 'package:mova/testing.dart';

setUp(MovaTesting.useTestKernels);
tearDown(MovaTesting.reset);

testWidgets('封面在首帧后淡出', (t) async {
  await t.pumpWidget(MaterialApp(home: MovaView(source: src, poster: cover)));
  final k = MovaTesting.lastKernel!;
  k.emitSize(1280, 720);
  k.emitRestart();            // MovaState.rendered → true
  await t.pump();
});
```

- `MovaTestKernel` 记录调用并可推送任意内核信号（`emitPlaying/Buffering/Position/Size/Restart/EndFile/...`）；`nativeRestartAvailable` 默认 `false`，buffering/位置兜底会立即落地，不会留下挂起的宽限计时器。
- 安装期间平台端口都是空实现、缩略图只用内存缓存，不会撞上 `path_provider`/`screen_brightness` 的平台通道；显式传入的 `kernel:`/端口仍然优先。
- 测试入口**不在**主 barrel 里，只通过 `package:mova/testing.dart` 引入，不会出现在 app 代码的补全列表中。

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
final engine = createMovaEngine(
  options: const MovaOpts(
    live: MovaLiveConfig(seekMode: MovaLiveSeekMode.dvr),
  ),
);

// 时移：拖动时用你自己的 URL 方案重开源
final engine = createMovaEngine(
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

`MovaPlaylist` 在 `MovaApi` 之上驱动顺序播放：跟踪当前下标、按
`MovaApi.open` 在项间导航、可选自动连播。纯 Dart（无 Flutter 依赖），由宿主构造并
注入，engine 从不持有它：

```dart
final playlist = MovaPlaylist(engine);
await playlist.jumpTo(0); // 打开第一条
```

初值（条目列表/初始下标/是否自动连播）取自 `MovaOpts.playlist`
（`MovaPlaylistConfig`）。与广告组合时共享会话，换集会加载对应排期，
自动连播等待正片及全部后贴片结束（需配置 `playlist.enabled: true`）：

```dart
final ads = MovaAds(engine, cutover: engine); // engine 为同一个 MovaCutoverEngine
final playlist = MovaPlaylist(engine, ads: ads);
await playlist.jumpTo(0);
```

新代码也可直接使用 `MovaSession`（借用播放器，`autoAdvance` 默认关闭）：

```dart
final api = createMovaEngine();
final session = MovaSession(api, items: episodes, autoAdvance: true);
final outcome = await session.jumpTo(0);
// episodes 中每项的 adBreaks 覆盖该集广告；null 回落到 api.options.ads.breaks。
// outcome == MovaLoadOutcome.accepted 表示首段已被接受，不保证首帧。
```

## 沉浸式 Feed 流播放（可选）

`MovaFeedPlayer` 是 bilibili/抖音式"上滑下一个视频"的纵向 feed 组件，背后是
`MovaFeed` + `MovaFeedEnginePool`：每个热页各自独立的引擎，而不是所有页
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

宿主可持有 `MovaFeedPlayerController()`，传入 `MovaFeedPlayer(controller: controller, ...)`，
通过 `feed`、`activeIndex`、`activeApi` 查询，调用 `jumpToPage(index)`、`pause()`、`play()`。
未绑定时查询为 null、命令无操作；打开在途也可控制当前 API；控制器由宿主释放，池和引擎由组件释放。
`autoPause`/`routeObservers` 控制整条 feed 守卫，`errorBuilder(context, index, error, retry)`
可定制单页加载、open 拒绝/异常及运行中失败界面，显式 retry 不影响相邻页。

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

模型下载为实验实现，**没有校验和校验**。启用须通过
`createMovaEngine(options: MovaOpts(stt: MovaSttConfig(enabled: true, engine: recognizer)))`
注入宿主持有的识别器；mova 不内置识别引擎，选型见 [08-04 定案](doc/notes/2026-08-04-stt-engine-decision.md)。

## 广告编排（可选）

`MovaAds` 按排期播前/中/后贴片，并能表达广告业务的真实时序。**除广告位时长外，
所有新能力默认关闭或默认不改变行为。**

```dart
// 正片源延迟解析：前贴片播完之后才真正解析正片地址（短期签名 URL 场景）。
await ads.loadDeferred(() async {
  final play = await playbackService.requestPlayback(videoId); // 宿主业务服务，非 MovaApi
  return MovaSource(play.url, title: play.title);
});
ads.contentError.listen((error) {
  // 宿主展示重试入口；也包含正片 open 失败和运行中终结错误。
});

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

- 广告位时长、跳过与中插 delay 使用可暂停时钟：暂停期间不计费、不消耗倒计时；加载首帧超时仍用独立墙钟，不依赖媒体时间轴。
- `contentError` 汇入解析失败、正片 open/切换异常及运行中终结错误（开启 recovery 时等 giveUp）；宿主拒绝和过期加载不报错。失败回 idle、不发 `contentEnded`、不自动换集；`contentEnded` 只在正片及全部后贴片结束后发出。
- `duration` 必须长于 `skippableAfter`，否则 `assertValid()` 会在 debug 下失败。
- 就绪等待仅在宿主接了 `MovaCutover` 且 `MovaCutoverConfig.enabled` 为 `true` 时才可能生效——两者默认都是关的。
- 失败兜底策略 `MovaAdFailPolicy` 返回 `retry` / `skipBreak` / `abandonPod`，内置 `MovaAdAbandonPod`（首次失败即放弃整个 pod）。

详细行为规则、状态机与真机验证进展见 [doc/SPEC.md](doc/SPEC.md)「广告编排增强」一节、
[doc/plans/2026-09-16-ad-swap-enhancements.md](doc/plans/2026-09-16-ad-swap-enhancements.md)。

## 无缝引擎切换（可选）

`MovaCutoverEngine` 本身就是一个 `MovaApi`：在一个稳定的渲染面背后持有当前生效引擎，以及
一个可选的、正在预热的影子引擎；影子就绪后原子换指，UI 完全无感（不重挂、不黑屏）。
默认 **关闭**（`MovaCutoverConfig.enabled` 为 `false`），关闭时是纯直通代理，行为与直接用
`MovaEngine` 完全一致。

```dart
final api = MovaCutoverEngine(
  engineFactory: () => createMovaEngine(
    options: const MovaOpts(cutover: MovaCutoverConfig(enabled: true)),
  ),
);
final ads = MovaAds(api, cutover: api); // cutover 传同一个实例
runApp(MovaPlayer(api: api));
```

`MovaAds` 接了 `cutover:` 参数后，会在广告播放期间按 `MovaCutoverConfig` 配置的触发策略
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
final mini = MovaMini();
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
final miniCtl = MovaMini(); // 建在 app 根，路由之外

MaterialApp(
  builder: (context, child) => MovaMiniHost(mini: miniCtl, child: child!),
  home: const HomePage(),
)

// 播放页里点"缩小"：
await miniCtl.show(api);
Navigator.of(context).pop();   // 引擎不受影响，画面在小窗里继续
```

**谁 dispose engine**：mova 的约定是"宿主持有 engine"——`MovaPlayer`/`MovaMini`
从不 dispose 传进来的 `api`。页面 `dispose()` 里顺手 `api.dispose()` 会在交接瞬间把正在
小窗里播的引擎干掉；用 `MovaMini.isShowing(api)` 在 `dispose` 前自检。

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
不开启时事件流与不传 `report` 逐字节相同。点播会话以 EOF 结束但完播率低于
`MovaReportConfig.truncatedBelow`（默认 `0.9`，`<=0` 关闭）时，按截断处理：先发 fatal 的
`MovaErrorEvent`（`code: truncated`），`sessionEnd.reason` 记 `failed`，而不是 `ended`。

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
丢帧计数、mpv 日志 prefix 错误分类），必要时（TTFF 精确落地、会话结束原因）经自建
`dart:ffi` 弱客户端订阅原生 mpv 事件（`media_kit` 依赖保持 pub.dev 版本，无需 git 提交）。详见
[doc/SPEC.md](doc/SPEC.md)「埋点与 QoE」一节、
[doc/plans/2026-09-29-telemetry-enhancement.md](doc/plans/2026-09-29-telemetry-enhancement.md)。
**Android 真机与 Windows 桌面已验证 TTFF、卡顿、四分终止态、`qoe: false` 关闭态；iOS/macOS 未验证（原生事件订阅失败时静默退化到 `buffering` 边沿与时序推断）。**

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
`MovaQualityChange`/`MovaPipChange`/`MovaCutoverChange`/`MovaErrorEvent` 等三十余种，
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
pip/锁定时整层隐藏）+**常驻层**（状态层、锁定遮罩与可 patch 的 `lockToggle`；未锁定时按钮随控制条隐藏，锁定时保留解锁入口，PiP/mini 时隐藏按钮）。
组件树是静态的（`components()` 不吃状态），显隐由组件各自的 `MovaSelect` 响应式决定。
插槽词表：`top`/`center`/`bottom`/`bottomAbove`/`overlay`/`left`/`right`/`gesture`/`hud`。

按钮默认支持 Tab 聚焦、Enter/空格激活、无障碍语义和悬停提示。鼠标在播放器上移动会唤出控制条。
播放器快捷键默认关闭；通过 `MovaOpts(controls: MovaCtrlsConfig(shortcuts: true))` 启用后，
点击画面或 Tab 聚焦播放器，可用空格播放/暂停、左右键跳转十秒、上下键调整音量、F 切换全屏、Esc 退出全屏。
快捷键仅作用于当前聚焦视图，不接管文本输入、锁定或 PiP/mini 状态。

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
  patches: [MovaPatch.insertAfter(
    '${MovaTopBarComponent.componentName}/${MovaFullscreenButtonComponent.componentName}',
    MyExtraButtonComponent(),
  )],
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

final engine = createMovaEngine(interceptors: [AuthGate()]);
```

## 项目结构（面向想深入了解或贡献代码的开发者）

`lib/src/core/`（无 UI 依赖的能力面/内核封装）与 `lib/src/ui/`（组件树 + 皮肤 + 手势，
纯 Flutter widget）两层。`MovaApi` 是 `ui/` 唯一允许依赖的抽象——不直接触达
`MovaKernel` 或 media_kit。完整分层说明、各模块职责见 [doc/SPEC.md](doc/SPEC.md)「架构分层」一节。

## 自研瘦身版 libmpv

消费侧接入与各平台配置见 [libmpv/README.md](libmpv/README.md#接入指南从项目-readme-迁入)；
构建配方和 CI 见独立 [mova-libmpv 文档](../mova-libmpv/README.md)。

## Roadmap / 路线图

见 [doc/ROADMAP.md](doc/ROADMAP.md)。

## License

MIT
