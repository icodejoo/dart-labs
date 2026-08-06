# mova 0.2.0 架构设计（core/ui 分层 + 拖动预览 + 直播时移）

状态：已评审通过（2026-07-30），待实现。
上游文档：[PRD.md](PRD.md)（需求/决策）、[SPEC.md](SPEC.md)（0.1.0 实现现状）、[ROADMAP.md](ROADMAP.md)。

---

## 1. 背景与目标

0.1.0 的结构是 `core/`（薄封装 media_kit）+ `controls/`（UI 与手势）两层，但 UI 直接持有
`MovaCtrl` 并各自订阅 media_kit 的属性流，控制条是三个大 Widget，外部无法替换局部、
无法插入自有组件（弹幕、水印、广告），文案与配色硬编码。要继续加功能（拖动预览、直播时移、
后续弹幕/字幕/投屏），这个结构会越改越贵。

0.2.0 做三件事：

1. **重构**为 `core/`（行为）+ `ui/`（表现），Stream 做通信层，UI 拆成可寻址的组件树 + 皮肤。
2. **新功能 B**：拖动进度条时显示缩略图预览（服务端雪碧图 / WebVTT，缺元数据时 libmpv 抽帧兜底，
   两级缓存，退出清理，默认仅 WiFi）。
3. **新功能 C**：斗鱼式直播 ↔ 点播（时移）切换，拖动进度条即可回看，可回到直播边缘。

参考架构：[bytedance/xgplayer](https://github.com/bytedance/xgplayer)（EventEmitter 核心 +
Plugin 挂载点 + hooks + presets 皮肤）。移植到 Flutter 时两处变形：DOM → Widget，
CSS 皮肤 → 组合装配。

### 非目标

- 不做 iOS PiP（libmpv 纹理限制，仍返回 false）。
- 不做二期 ffmpeg 瘦身（LGPL，独立里程碑）。
- 不引入 provider/riverpod/bloc 等状态管理依赖。

---

## 2. 命名与版本

- 包名 `mova`，公开类前缀 `Vm`（短，且不与 Flutter 的 `VideoPlayer` 相撞）。
- `src/` 内文件名不带前缀（`core/controller.dart`、`ui/components/seek_bar.dart`）。
- 原生侧用 `MovaPlugin` / `MovaPluginCApi`，channel 名 `mova`，Android 包
  `com.icodejoo.mova`。
- 版本 **0.2.0**（破坏性变更）。

---

## 3. 架构总览

```
                 ┌──────────────── ui/ （表现）────────────────┐
                 │  MovaPlayer（门面）                            │
                 │    └ MovaScope(InheritedWidget: MovaApi)         │
                 │        └ MovaSkin.assemble(slots, video)       │
                 │            └ 组件树（MovaComp，可寻址）    │
                 └──────────┬──────────────────▲───────────────┘
        api.play()/seek()   │                  │  events / states / progress / uiStates
                            ▼                  │
                 ┌──────────────── core/ （行为）───────────────┐
                 │  MovaApi（抽象能力面）                          │
                 │  MovaEngine implements MovaApi                   │
                 │    ├ MovaKernel（抽象内核）→ MpvKernel          │
                 │    ├ MovaBus（broadcast + 节流/去重）           │
                 │    ├ 状态归约 → MovaState / MovaProg / MovaUiState │
                 │    ├ MovaHook 链（4 个拦截点）           │
                 │    ├ preview/（缩略图服务）                   │
                 │    ├ live/（时移窗口计算）                    │
                 │    └ platform/（亮度/PiP/方向 抽象端口）      │
                 └──────────────────────────────────────────────┘
                            ▲
                 platform_impl/（Flutter 侧实现，注入 engine）
```

**通信是单向的**：UI → core 走**直接方法调用**（类型安全、可 await、能拿错误）；
core → UI 走**广播流**（只播"已发生的事"）。不做双向 emit。

### 3.1 目录

```
lib/mova.dart                      barrel，只导公开面
lib/src/
  core/
    api.dart                           MovaApi 抽象能力面
    engine.dart                        MovaEngine 实现
    kernel/kernel.dart                 MovaKernel 抽象（可 fake）
    kernel/mpv_kernel.dart             唯一 import media_kit 的文件
    bus/bus.dart                       MovaBus：broadcast + throttle/distinct
    events/events.dart                 sealed MovaEvent 事件表
    state/state.dart                   MovaState + copyWith
    state/progress.dart                MovaProg（高频）
    state/ui_state.dart                MovaUiState（控制条可见/HUD/预览位置）
    interceptor/interceptor.dart       MovaHook
    options/options.dart               MovaOpts 聚合
    options/preview_config.dart        MovaPrevConfig
    options/live_config.dart           MovaLiveConfig
    options/gesture_config.dart        MovaGestConfig（自 0.1.0 迁入）
    options/abr_config.dart            MovaAbrConfig
    options/controls_config.dart       MovaCtrlsConfig
    options/strings.dart               MovaStrs（文案外置）
    options/theme.dart                 MovaTheme（配色/尺寸外置）
    model/source.dart                  MovaSource / MovaStreamType
    model/quality.dart                 MovaQual + parseHlsMasterPlaylist
    model/fit.dart                     MovaFit + movaBoxFit
    model/abr.dart                     BufferingAbr → MovaBufferAbr
    preview/
      models.dart                      MovaThumb / MovaThumbCue / MovaThumbIndex
      source.dart                      MovaThumbSource 抽象
      vtt.dart                         parseVttThumbs()（纯函数）
      vtt_source.dart                  MovaVttThumbSource
      extractor.dart                   MovaFramePuller 抽象
      mpv_extractor.dart               MpvFrameExtractor（隐藏 Player）
      cache.dart                       MovaThumbCache 抽象 + MovaTwoLevelCache
      service.dart                     MovaPrevSvc implements MovaPrevApi
      net_probe.dart                   MovaNetProbe 抽象
    live/timeshift.dart                窗口/behind 纯函数
    platform/ports.dart                MovaBrightPort / MovaPipPort / MovaOrientPort
  platform_impl/
    brightness_impl.dart               screen_brightness
    pip_impl.dart                      MethodChannel（现有 platform_interface 收纳于此）
    orientation_impl.dart              SystemChrome
    net_probe_impl.dart                connectivity_plus
  ui/
    player.dart                        MovaPlayer 门面
    scope/scope.dart                   MovaScope
    scope/selector.dart                MovaSelect<T>
    slots/slot.dart                    MovaSlot 枚举 + MovaSlotBundle
    slots/component.dart               MovaComp
    slots/patch.dart                   MovaPatch（路径寻址增删换）
    slots/tree.dart                    组件树解析与构建
    skins/skin.dart                    MovaSkin 抽象
    skins/default_skin.dart            MovaDefSkin（VOD/Live 共用，按 state 出树）
    components/…                       见 5.4
```

---

## 4. core 设计

### 4.1 MovaApi（能力面）

UI 只依赖这个抽象类；测试用 `FakeMovaApi`。

```dart
abstract class MovaApi {
  // ── 订阅（四条流，按频率拆开）
  Stream<MovaEvent> get events;        // 离散事件，低频
  Stream<MovaState> get states;        // 快照，去重
  Stream<MovaProg> get progress;   // position/buffer，节流
  Stream<MovaUiState> get uiStates;    // 控制条可见/HUD/预览位置
  MovaState get state;                 // 同步快照，首帧不闪
  MovaUiState get uiState;
  MovaOpts get options;

  // ── 能力
  Future<void> open(MovaSource source, {bool autoPlay = true});
  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration to);
  Future<void> seekBy(Duration delta);
  Future<void> setVolume(double v);        // 0–100
  Future<void> setBrightness(double v);    // 0–1
  Future<void> setRate(double r);
  Future<void> setFit(MovaFit f);
  Future<void> setZoom(double z);
  Future<void> setLocked(bool v);
  Future<void> setFullscreen(bool v);
  Future<void> loadQualities();
  Future<void> switchQuality(MovaQual q);
  Future<bool> enterPip();
  Future<void> reload();
  Future<void> backToLiveEdge();

  // ── UI 编排（由组件调用，状态仍归 core）
  void showControls({bool sticky = false});
  void hideControls();
  void showHud(MovaHud hud);
  void setDragging(bool v, {Duration? previewAt});

  MovaPrevApi get preview;
  Future<void> dispose();
}
```

### 4.2 MovaKernel（内核抽象）

隔离 media_kit，使 core 可在纯 Dart 下测试。

```dart
abstract class MovaKernel {
  Future<void> open(String uri, {bool play = true});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);
  Future<void> setVolume(double v);
  Future<void> setRate(double r);
  Future<Uint8List?> screenshot();

  Stream<bool> get playing;
  Stream<bool> get buffering;
  Stream<bool> get completed;
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<Duration> get buffer;
  Stream<({int width, int height})> get size;
  Stream<String> get error;

  Object get renderHandle;   // media_kit VideoController；ui 侧向下转型使用
  Future<void> dispose();
}
```

`MpvKernel` 是唯一 `import 'package:media_kit/media_kit.dart'` 的文件。

### 4.3 事件表（sealed）

```dart
sealed class MovaEvent { const MovaEvent(); }
```

| 事件 | 载荷 |
|---|---|
| `MovaReady` | — |
| `MovaSourceChg` | `MovaSource source` |
| `MovaPlay` / `MovaPause` / `MovaDone` | — |
| `MovaSeek` / `MovaSeeked` | `Duration target` / `Duration position` |
| `MovaBufferChg` | `bool buffering` |
| `MovaDurChg` | `Duration duration` |
| `MovaSizeChg` | `int width, height` |
| `MovaVolumeChg` / `MovaBrightChg` / `MovaRateChg` | `double value` |
| `MovaQualListChg` | `List<MovaQual> qualities` |
| `MovaQualChg` | `MovaQual quality` |
| `MovaAbrDownShift` | `MovaQual from, to` |
| `MovaFitChg` / `MovaZoomChg` | 新值 |
| `MovaLockChg` / `MovaFullScreenChg` / `MovaPipChg` | `bool value` |
| `MovaTimeShiftChg` | `Duration behind` |
| `MovaLiveEdgeReach` | — |
| `MovaPrevBlock` | `MovaPrevBlockReason reason` |
| `MovaErrorEvent` | `Object error, StackTrace? stack` |

### 4.4 状态

```dart
class MovaState {                       // 不可变 + copyWith
  final bool playing, buffering, completed, locked, fullscreen, pip;
  final Duration duration;            // VOD 时长；DVR 直播为窗口长度
  final int width, height;
  final double volume, brightness, rate, zoom;
  final MovaFit fit;
  final List<MovaQual> qualities;
  final MovaQual? currentQuality;
  final MovaStreamType type;
  final bool liveSeekable;            // 直播是否可拖
  final Duration seekableWindow;      // 可拖窗口
  final Duration? timeshiftBehind;    // null = 在直播边缘
  final Object? error;
}

class MovaProg { final Duration position, buffer; }     // 节流 200ms

enum MovaHud { none, volume, brightness, seek, fit, quality, zoom }

class MovaUiState {
  final bool controlsVisible, dragging;
  final MovaHud hud;
  final String? hudText;
  final Duration? previewAt;          // 拖动中的预览位置；null = 不显示气泡
}
```

**取舍**：单个大快照 + `MovaSelect` 字段级 distinct。新增字段不改流；代价是每次变更一次
`copyWith` 对象分配（对 200ms 节流量级无影响）。不做 per-field stream。

### 4.5 拦截点（对应 xgplayer hooks，收窄为 4 个）

```dart
abstract class MovaHook {
  Future<bool> beforeOpen(MovaSource s) async => true;          // false 取消
  Future<Duration?> beforeSeek(Duration target) async => target; // null 取消，可改写
  Future<bool> beforePlay() async => true;                    // 前贴广告/鉴权
  void onError(Object e, StackTrace st) {}
}
```

按注册顺序串行执行；任一 `false`/`null` 短路。**不提供**任意方法 hook——Flutter 下会让
状态无法追踪。

---

## 5. ui 设计

### 5.1 MovaScope + MovaSelect

```dart
class MovaScope extends InheritedWidget {
  final MovaApi api;
  static MovaApi of(BuildContext c);
}

/// 只在 selector 结果变化时 rebuild
class MovaSelect<T> extends StatelessWidget {
  final T Function(MovaState s) selector;
  final Widget Function(BuildContext c, T value) builder;
}
// 同类：MovaProgSelect<T>、MovaUiSelect<T>
```

### 5.2 组件模型（树）

```dart
enum MovaSlot { gesture, hud, top, center, bottomAbove, bottom, overlay }
// 视频画面本身不是组件：它由 MovaPlayer 构建后作为 assemble(video) 参数传入，永远在最底层。

abstract class MovaComp {
  String get name;                                 // 唯一名，路径寻址用
  MovaSlot get slot;                                 // 顶层挂载点；作为子组件时被父级忽略
  int get order => 0;                              // 同槽排序
  List<MovaComp> get children => const [];      // 空 = 细粒度原子组件
  /// children 已由框架构建完毕传入；父级只排布（Row/Column/Stack）
  Widget build(BuildContext c, MovaApi api, List<Widget> children);
}
```

**细/中两种粒度统一**：中粒度（`topBar`、`bottomBar`、`hudLayer`）就是持有 children 的组合组件。

### 5.3 皮肤与补丁

```dart
abstract class MovaSkin {
  List<MovaComp> components(MovaState s);   // 可按 vod/live/时移 动态出树
  Widget assemble(BuildContext c, MovaSlotBundle slots, Widget video);
}

sealed class MovaPatch {
  factory MovaPatch.replace(String path, MovaComp c);
  factory MovaPatch.remove(String path);
  factory MovaPatch.insertAfter(String path, MovaComp c);
  factory MovaPatch.add(MovaSlot slot, MovaComp c, {int order});
}

class MovaDefSkin implements MovaSkin {
  const MovaDefSkin({List<MovaPatch> patches = const []});
}
```

路径 = 组件 name 以 `/` 连接。示例：

```dart
MovaPlayer(
  api: api,
  skin: MovaDefSkin(patches: [
    MovaPatch.replace('bottomBar/seekBar', MySeekBar()),   // 换细组件
    MovaPatch.remove('topBar/pip'),                        // 删按钮
    MovaPatch.replace('bottomBar', MyBottomBar()),         // 换整块中粒度
    MovaPatch.add(MovaSlot.top, DanmakuToggle(), order: 5),  // 插自有组件
  ]),
)
```

### 5.4 默认组件树

```
(底层)     视频画面（assemble 参数，非组件）
gesture    gestureLayer
hud        hudLayer/{volumeHud, brightnessHud, seekHud, zoomHud}
top        topBar/{title, pip, quality, fit, fullscreen, lock}
center     centerPlay/{playPause}
bottomAbove preview                            # 缩略图气泡（浮在进度条上方）
bottom     bottomBar/{position, seekBar, duration}                      # VOD
           bottomBar/{liveBadge, seekBar, timeshift, backToLive}        # Live
overlay    buffering, error, lockMask
```

`seekBar` 一个组件同时服务 VOD 与可拖直播；直播不可拖时默认皮肤不出该组件。

组件内部只做两件事：`MovaSelect` 订字段渲染 + 调 `api.xxx()`。**无组件持有另一组件引用**；
跨组件协同（控制条自动隐藏、HUD、预览位置）全部经 `MovaUiState`。

---

## 6. 开放性契约（硬约束）

**每个替用户做的决策必须齐三样：默认值 + 配置项 + 可注入策略。** 缺任一条算设计缺陷，
review 时逐条对账。

### 6.1 预览

| 决策 | 默认 | 配置项 | 可注入 |
|---|---|---|---|
| 网络限制 | `wifiOnly` | `network` | `probe`（`MovaNetProbe`） |
| 被拦提示 | 静默 | — | `onBlocked(reason)` |
| 缩略图来源 | `[vtt, mpvExtract]` | `sources` 有序表 | 自定义 `MovaThumbSource` |
| VTT 地址 | 约定 `<video>.vtt` | `vttUrl` | `vttUrlResolver` |
| 抽帧兜底 | 开 | `extractFallback`、`platforms` | 自定义 `MovaFramePuller` |
| 帧宽 / 桶间隔 / 硬解 | 160px / 10s / off | 均可配 | — |
| 内存上限 | 40 张 | `memMaxEntries` | 自定义 `MovaThumbCache` |
| 磁盘上限 / 目录 | 64MB / 临时目录 | `diskMaxBytes`、`diskDir` | 同上 |
| 缓存 key | `sha1(src|bucket|w)` | — | `cacheKeyBuilder` |
| 退出清理 | 开 | `clearOnDispose` | 同上 |
| 请求防抖 | 120ms | `debounce` | — |
| 气泡外观 | 默认组件 | — | patch `preview` |

### 6.2 直播时移

| 决策 | 默认 | 配置项 | 可注入 |
|---|---|---|---|
| 时移模式 | `off` | `seekMode: off/dvr/timeshift` | — |
| 时移 URL | 无 | — | `urlBuilder(uri, behind, wallClock)` |
| DVR 窗口 | 取内核 duration | `dvrWindow` 覆盖 | `windowResolver(state)` |
| "在边缘"阈值 | 10s | `edgeThreshold` | — |
| 回直播方式 | dvr→seek 末端；timeshift→重开 | `backToLive: seekEnd/reopen`（可空，空则按 `seekMode` 推导） | — |
| 卡顿自动回边缘 | 关 | `autoBackToLiveOnStall` | — |

### 6.3 全局

| 项 | 说明 |
|---|---|
| `MovaStrs` | `'适应'/'裁剪'/'拉伸'/'回到直播'/'LIVE'/'时移'` 等全部外置，整表可换，宿主自接 l10n |
| `MovaTheme` | 颜色/图标/字号/进度条高度/渐变，替代散落的 `Colors.white`、`Color(0xFFE53935)` |
| `MovaGestConfig` | 补 `hSeekSpanPerScreen`（原硬编码满屏 90s）、`vSensitivity`、`allowWhenLive` |
| `MovaAbrConfig` | `policy` 可注入，替换 `MovaBufferAbr` |
| `MovaCtrlsConfig` | `autoHide`、`autoHideDelay`（3s）、`showOnStart` |
| `kernel` | 可注入自研内核 / 测试 fake |
| `platform` | 亮度/PiP/方向三端口均可注入 |
| `interceptors` | 4 个拦截点 |
| `skin` + `patches` | 组件树任意增删换 |

聚合入口：

```dart
class MovaOpts {
  const MovaOpts({
    this.preview = const MovaPrevConfig(),
    this.live = const MovaLiveConfig(),
    this.gesture = const MovaGestConfig(),
    this.abr = const MovaAbrConfig(),
    this.controls = const MovaCtrlsConfig(),
    this.strings = const MovaStrs(),
    this.theme = const MovaTheme(),
  });
  MovaOpts copyWith({...});
}
```

---

## 7. 功能 B：拖动预览

### 7.1 数据流

```
拖动位置 t（按 interval 取桶 → bucket）
 ├ 网络策略检查（wifiOnly 且当前蜂窝 → emit MovaPrevBlock，不请求）
 ├ 内存命中？ → 同帧同步返回，无闪烁
 ├ 磁盘命中？ → 异步读 → 显示 + 回填内存
 ├ sources 依次尝试：
 │   ├ MovaVttThumbSource：Index.cueAt(t) → 取 sprite 图（磁盘/网络）→ 按 #xywh 裁剪
 │   └ MpvFrameExtractor：hidden Player.seek(bucket) → screenshot() → JPEG
 └ 抽帧结果：
     ├ bucket 仍等于当前拖动桶 → 进内存 + 显示，用完落盘
     └ 已过期（拖到别处）→ 只落盘，等下次读
```

- 防抖 120ms；抽帧**串行单队列**，新请求取消旧的（旧结果仍落盘，不浪费）。
- 桶对齐保证同区间复用同一张图。

### 7.2 WebVTT 缩略图格式

```
WEBVTT

00:00:00.000 --> 00:00:10.000
sprite-0.jpg#xywh=0,0,160,90

00:00:10.000 --> 00:00:20.000
sprite-0.jpg#xywh=160,0,160,90
```

`parseVttThumbs(String content, {required Uri base})` → `List<MovaThumbCue>`，纯函数。
无 `#xywh` 视为整图；相对路径按 base 解析。默认按约定探测 `<video-url>.vtt`。

### 7.3 抽帧（复用内置 libmpv/ffmpeg，零新依赖）

隐藏一个无 UI 的 media_kit `Player` + 小尺寸 `VideoController`：
`hwdec=no`、`ao=null`、`vf=scale=<w>:-2`、`hr-seek=yes`、`cache=no`；
`seek(t)` 后 `player.screenshot(format:'image/jpeg')`。解码与缩放由 ffmpeg
（libavcodec + swscale）完成，HTTP range 由 libmpv 自己发。**不引 ffmpeg_kit**，
不影响二期瘦身。

> **实测风险（必须先验）**：`screenshot-raw` 取的是 video 分辨率还是窗口分辨率，
> 决定 `vf=scale` 是否生效。Windows 桌面先验；若无效改用
> `VideoControllerConfiguration(width/height)` 路线。见 §11。

### 7.4 缓存与清理

- **内存**：计数 LRU，默认 40 项，存 `bytes + crop`（不缓存已解码 `ui.Image`）。
- **磁盘**：`getTemporaryDirectory()/mova_thumbs/`（新增 `path_provider`），
  字节 LRU 默认 64MB，key = `sha1(sourceKey|bucketSec|width)`。
- **清理**：`dispose()` 清目录（`clearOnDispose`，默认开）；进程内首次 init 也全清一次，
  兜住"上次被系统杀掉留残留"。

### 7.5 网络策略

```dart
enum MovaPrevNet { wifiOnly, always, never }   // 默认 wifiOnly
abstract class MovaNetProbe { Future<bool> allowHeavy(); Stream<bool> get changes; }
```

默认实现 `ConnectivityNetProbe`（新增 `connectivity_plus`）：wifi/ethernet/vpn → 允许，
mobile → 拦，unknown/桌面 → 允许（不误伤桌面）。用户可注入自己的 probe 接省流开关。

---

## 8. 功能 C：直播 ↔ 点播（时移）

```dart
enum MovaLiveSeekMode { off, dvr, timeshift }
typedef MovaTimeShiftBldr = String Function(String uri, Duration behind, DateTime wallClock);
enum MovaBackToLive { seekEnd, reopen }
```

- **dvr**：不换源，放开内核原生 seek。窗口 = 内核 `duration`（HLS 滑动窗口，随流更新），
  `position` 即窗口内偏移。
- **timeshift**：`onChangeEnd` 时用 `urlBuilder` 生成带起播时间的 URL 重开源；
  `behind = window - value`。
- **off**：保持 0.1.0 行为（直播禁拖）。

状态与能力：`state.liveSeekable`、`state.seekableWindow`、`state.timeshiftBehind`、
`api.backToLiveEdge()`。`seek()` 门控改为：`type == vod || liveSeekable`。

UI：`bottomBar` 在 `liveSeekable` 时出 `seekBar`；`liveBadge` 在边缘为红 `LIVE`，
回看时为灰 `时移 -MM:SS`，右侧出 `backToLive` 按钮。手势横滑门控同步放开
（`!isLive || liveSeekable`，且受 `gesture.allowWhenLive` 约束）。

纯函数（`live/timeshift.dart`，可单测）：

```dart
Duration resolveWindow(MovaState s, MovaLiveConfig cfg);
Duration? behindOf(Duration position, Duration window, Duration edgeThreshold);
bool atLiveEdge(Duration position, Duration window, Duration edgeThreshold);
```

**落地偏差**（阶段 C 落地，2026-07-31，详见 `doc/SPEC.md`「直播时移」一节与
`doc/plans/2026-07-31-phase-c-timeshift.md`）：`backToLive` 是**可空**字段，
为空时按 `seekMode` 推导（`timeshift` → `reopen`，其余 → `seekEnd`），而非
本节原文暗示的必填枚举；UI 树里的 `backToEdge` 组件已更名为 `backToLive`
（patch 路径 `bottomBar/backToEdge` → `bottomBar/backToLive`，破坏性变更）；
`behind` 在写入 `MovaState` 前按整秒量化，避免 position 高频回调击穿去重后的
`states` 流。

---

## 9. 兼容与迁移

- `MovaPlayer` 对外签名保持兼容，新增可选 `skin` / `options` 参数。
- `MovaCtrl` 保留为 `MovaEngine` 的 `@Deprecated` 门面（转发全部方法）。
- `VodControls` / `LiveControls` / `MovaGestDetect` 标 `@Deprecated`，0.3.0 删除。
- `CHANGELOG` 写明破坏性变更与替换表。

---

## 10. 测试策略

**core（纯 Dart，`FakeKernel` 推状态）**

- 事件序列：open → `MovaSourceChg`/`MovaReady`/`MovaPlay`；seek → `MovaSeek`→`MovaSeeked`。
- 状态归约：各字段跟随内核流；`copyWith` 不丢字段。
- `progress` 节流：高频 position 输入 → 输出条数受限。
- `states` 去重：相同快照不重复发。
- 拦截器：`beforeSeek` 返回 null 取消、返回改写值生效；`beforePlay` false 阻止播放。
- seek 门控三模式：off 忽略、dvr 允许并 clamp、timeshift 触发 urlBuilder。
- 时移纯函数：`resolveWindow` / `behindOf` / `atLiveEdge` 边界。
- ABR：上升沿计数、阈值、自动档不降档。
- 清晰度：`parseHlsMasterPlaylist`（沿用现有 4 项）。
- 预览：`parseVttThumbs`（`#xywh`/无 xywh/相对路径/畸形行/空文件）、`MovaThumbIndex.cueAt`
  二分边界、内存 LRU 淘汰序、磁盘 LRU 字节上限淘汰、cacheKey 稳定性、桶对齐、
  网络策略拦截（fake probe）、抽帧串行与过期结果仍落盘（fake extractor）。

**ui（`FakeMovaApi` + WidgetTester）**

- 手势四类平移现有 4 项（音量/亮度/进度提交/直播禁滑）+ 新增可拖直播放开。
- slot 装配：组件按 slot/order 落位。
- patch：`replace`/`remove`/`insertAfter`/`add` 四种生效，路径寻中/细两级。
- `MovaSelect`：无关字段变化不触发 rebuild（rebuild 计数断言）。
- 直播控制条：`liveSeekable` 才出 `seekBar`；`backToLiveEdge` 后 badge 回红。
- 预览气泡：`uiState.previewAt` 非空才显示；网络被拦时不显示。

保留 `test/method_channel_test.dart`。

---

## 11. 风险与验证缺口

| 风险 | 应对 |
|---|---|
| `screenshot-raw` 分辨率语义（§7.3） | **阶段 B 第一件事**：Windows 桌面写最小验证脚本实测；不通则改 `VideoControllerConfiguration(width/height)` |
| 隐藏 Player 内存/耗电（移动端） | `platforms` 可配；移动端可只走雪碧图；抽帧串行 + 空闲即释放隐藏 Player |
| 阶段 A 无可见收益、纯风险 | 强制"功能零变化 + 19 项测试改造后全绿"作为出口条件 |
| 真机仍未验证（承自 0.1.0） | 阶段 C 后统一起 Android 模拟器/真机跑一轮：手势手感、HLS 联网切档、PiP、时移 |
| `connectivity_plus` 平台差异 | 未知一律放行；桌面视为允许 |
| DVR 窗口靠内核 duration 推断 | 提供 `dvrWindow` / `windowResolver` 覆盖 |

---

## 12. 阶段与交付

| 阶段 | 内容 | 出口条件 |
|---|---|---|
| **A：重构** | core 骨架（api/engine/kernel/bus/events/state/interceptor/options）+ 现有 5 个控件平移成组件树 + 皮肤/补丁 + 文案与主题外置 + 兼容门面 | **功能零变化**；`flutter analyze` 0；现有 19 项测试改造后全绿 + 新增 core/ui 骨架测试全绿 |
| **B：拖动预览** | `preview/` 全套 + `preview` 组件 + 网络策略 + 两级缓存 + 清理 | 抽帧分辨率实测通过；预览单测全绿；Windows 实跑可见气泡 |
| **C：直播时移** | `live/` + seekBar 复用 + liveBadge/timeshift/backToLive 组件 + 手势门控 | 时移单测全绿；模拟 DVR m3u8 实跑可拖可回边缘 |
| **D：收尾** | README/CHANGELOG/example 三个 demo（VOD/直播/时移）、`pub publish --dry-run` 0 warnings、真机一轮 | 发布 0.2.0 |

规模估计：core ~1300 行、ui ~2000 行、测试 ~1200 行。阶段 A 对用户零可见收益，但后续每个
功能都吃它的红利。

新增依赖：仅 `path_provider`、`connectivity_plus` 两个。cacheKey 用自写 FNV-1a 64 位哈希
（`preview/hash.dart`，纯函数可测），**不引 `crypto`**。§7.4 的 `sha1(...)` 记法按此实现替换。
