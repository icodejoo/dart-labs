# videoman 0.2.0 阶段 B：拖动预览（缩略图） — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 拖动进度条（滑块拖动 / 手势横滑）时，在进度条上方浮出目标时刻的缩略图气泡。
来源优先服务端 WebVTT 雪碧图，缺元数据时用 libmpv 隐藏 `Player` 抽帧兜底；两级缓存（内存计数
LRU + 磁盘字节 LRU），退出清理，默认仅 WiFi 下工作。**每个替用户做的决策都必须齐"默认值 +
配置项 + 可注入策略"三样**（DESIGN §6 硬约束）。

**Architecture:** 新增 `lib/src/core/preview/`（纯 Dart：模型、VTT 解析、哈希、缓存、抽象端口、
服务编排）与 `lib/src/platform_impl/`（Flutter/插件侧具体实现：`connectivity_plus` 网络探针、
`path_provider` 目录解析、media_kit 隐藏 `Player` 抽帧器）。core 只持抽象端口，**第二个
`Player` 绝不出现在 `lib/src/core/**`**——`test/core/purity_test.dart` 的 media_kit 例外集合
永远只有 `{'kernel/mpv_kernel.dart'}` 一项，本阶段不得往里加。`VmPreviewService` 挂在
`VmApi.preview` 上，UI 侧新增 `PreviewComponent`（`VmSlot.bottomAbove`，阶段 A 特意留空的槽位），
由已存在的 `VmUiState.previewAt` 驱动。

**Tech Stack:** Dart 3.12.2 / Flutter ≥3.3、media_kit ^1.2.6、media_kit_video ^2.0.1、
flutter_test。**阶段 B 新增且仅新增两个依赖**：`path_provider`、`connectivity_plus`。
cacheKey 用自写 FNV-1a 64 位哈希（`core/preview/hash.dart`），**不引 `crypto`**（DESIGN §12 自注）。

设计依据：[../DESIGN-0.2.0.md](../DESIGN-0.2.0.md)（§6.1、§7、§10、§11、§12）。
上一阶段：[2026-07-30-phase-a-refactor.md](2026-07-30-phase-a-refactor.md)。

**Baseline（阶段 A 结束、且 `fix(videoman): wire real platform adapters, restoring
brightness/PiP/orientation`〔commit `9c2d4f0`〕落地之后的既成事实，本计划全部以此为准）：**
94 项测试全绿、`flutter analyze` 0 issues、版本 0.2.0。该 commit 已经创建了
`lib/src/platform_impl/wiring.dart` 与 `createVmEngine()`，接好了 brightness/PiP/orientation
三个真实端口；阶段 B 的 Task 12 是在它之上**新增**预览相关的端口参数，不是从零创建。

## 与 DESIGN-0.2.0.md 的偏差（以代码为准）

阶段 A 落地时与设计文档产生了分歧，文档未回写。**本计划一律按当前代码写，遇到冲突不要回退到
文档：**

| DESIGN 说法 | 当前代码事实 | 本计划采用 |
|---|---|---|
| §4.2 `Stream<({int width,int height})> get size` | `Stream<VmSize> get size`（`VmSize` 类在 `core/kernel/kernel.dart`） | `VmSize` |
| §4.2 `Stream<String> get error` | `Stream<Object> get error` | `Object` |
| §4.2 `Object get renderHandle` | `VmKernel.renderHandle` 是 `Object`（非空），但 `VmApi.renderHandle` 是 `Object?` | 各按各的 |
| §4.4 `VmState` 无 `sourceTitle` | `VmState` 有 `sourceTitle` 与 `clearSourceTitle` | 有 |
| §3.1 `model/abr.dart` 里是 `VmBufferingAbr` | 确实存在，且抽象策略 `VmAbrPolicy` 在 `options/abr_config.dart` | 以代码为准 |
| §7.4 `key = sha1(...)` | §12 自己推翻为 FNV-1a | FNV-1a |
| §3.1 `preview/cache.dart` 一个文件装 `VmThumbCache` + `VmTwoLevelCache` | 磁盘目录解析需要 `path_provider`（Flutter 插件），不能放 core | 拆成 `cache.dart`（抽象 + 内存）、`disk_cache.dart`（纯 `dart:io`）、`two_level_cache.dart`，目录端口 `dir_provider.dart` + `platform_impl/thumb_dir_impl.dart` |
| §3.1 `preview/mpv_extractor.dart` 在 `core/preview/` 下 | 会引入第二处 media_kit import，破坏 `purity_test.dart` | 抽象放 `core/preview/extractor.dart`，实现放 `lib/src/platform_impl/mpv_extractor_impl.dart` |
| §3.1 `preview/net_probe.dart` 的 `ConnectivityNetProbe` | 同上，`connectivity_plus` 是 Flutter 插件 | 抽象放 `core/preview/net_probe.dart`，实现放 `lib/src/platform_impl/net_probe_impl.dart` |
| §6.1「缩略图来源 `sources` 有序表」 | — | `List<VmThumbSource>? sources`：`null` = 内置链 `[vtt, extractor]`，非空 = 整链替换 |

## Global Constraints

- 包名 `videoman`，公开类前缀 `Vm`；`src/` 内文件名不带前缀。
- **`lib/src/core/**` 下任何文件禁止 `import 'package:flutter/...'`；只有
  `lib/src/core/kernel/mpv_kernel.dart` 允许 `import 'package:media_kit/...'`。**
  守卫测试 `test/core/purity_test.dart` 的 `_mediaKitExceptions` 集合必须恒等于
  `{'kernel/mpv_kernel.dart'}`——本阶段**任何任务都不许改动这个集合**。
  core 可以用 `dart:io`（`engine.dart` 已在用）。
- 注释规则（全局 `CLAUDE.md`）：每个类/方法/函数/getter/字段都要注释，**先英文一句、空行、后中文**；
  公开 API 用 `///` 文档注释，带参数与返回说明。本计划代码块里给出的注释按原样抄；未给出注释的
  私有小成员也要补一行双语。
- 校验用 `flutter analyze`（必须 0 issues），**不用 `flutter build`**。
- 每个 Task 结束必须 `flutter test` 全绿再 commit。
- 提交信息 `type(scope): message`，scope 用 `videoman`。
- 新依赖只许 `path_provider` 与 `connectivity_plus` 两个（Task 7、Task 5 各引一个）。
  **不许引 `crypto`、`http`、`image`、`ffmpeg_kit`。** HTTP 用 `dart:io` 的 `HttpClient`。
- 基线的 94 项测试（含 `9c2d4f0` 新增的 `wiring_test.dart` 3 项）一项都不许删、不许改断言；
  只允许因新增可选参数而做纯增量修改。
- 预览默认必须"不打扰"：被网络策略拦截时静默不显示、不请求，只发 `VmPreviewBlocked` 事件并调
  `onBlocked`（若配置）。

## 文件结构

**core/preview（新建，纯 Dart，零 Flutter 依赖）**

| 文件 | 职责 | 任务 |
|---|---|---|
| `lib/src/core/preview/models.dart` | `VmThumb` / `VmThumbCrop` / `VmThumbCue` / `VmThumbIndex` | Task 2 |
| `lib/src/core/preview/hash.dart` | `fnv1a64()` / `defaultCacheKey()` / `VmCacheKeyBuilder` | Task 2 |
| `lib/src/core/preview/vtt.dart` | `parseVttThumbs()`（纯函数） | Task 3 |
| `lib/src/core/preview/cache.dart` | `VmThumbCache` 抽象 + `VmMemoryThumbCache`（计数 LRU） | Task 4 |
| `lib/src/core/preview/dir_provider.dart` | `VmThumbDirProvider` 抽象 + `FixedThumbDirProvider` | Task 5 |
| `lib/src/core/preview/disk_cache.dart` | `VmDiskThumbCache`（`dart:io` 字节 LRU） | Task 5 |
| `lib/src/core/preview/two_level_cache.dart` | `VmTwoLevelCache` | Task 6 |
| `lib/src/core/preview/net_probe.dart` | `VmNetProbe` 抽象 + `AlwaysAllowNetProbe` | Task 7 |
| `lib/src/core/preview/fetcher.dart` | `VmHttpFetcher` 抽象 + `IoHttpFetcher`（`dart:io`） | Task 8 |
| `lib/src/core/preview/source.dart` | `VmThumbSource` 抽象 | Task 8 |
| `lib/src/core/preview/vtt_source.dart` | `VmVttThumbSource` | Task 8 |
| `lib/src/core/preview/extractor.dart` | `VmFrameExtractor` 抽象 + `VmExtractorThumbSource` | Task 9 |
| `lib/src/core/preview/platform_kind.dart` | `VmPlatformKind` + `currentPlatformKind()` | Task 9 |
| `lib/src/core/options/preview_config.dart` | `VmPreviewConfig` / `VmPreviewNetwork` / `VmPreviewBlockReason` / 各 typedef | Task 10 |
| `lib/src/core/preview/api.dart` | `VmPreviewApi` 抽象 | Task 11 |
| `lib/src/core/preview/service.dart` | `VmPreviewService implements VmPreviewApi` | Task 11 |

**platform_impl（新建，可引 Flutter/插件）**

| 文件 | 职责 | 任务 |
|---|---|---|
| `lib/src/platform_impl/net_probe_impl.dart` | `ConnectivityNetProbe`（`connectivity_plus`） | Task 7 |
| `lib/src/platform_impl/thumb_dir_impl.dart` | `TempThumbDirProvider`（`path_provider`） | Task 5 |
| `lib/src/platform_impl/mpv_extractor_impl.dart` | `MpvFrameExtractor`（隐藏 media_kit `Player`） | Task 9 |
| `lib/src/platform_impl/wiring.dart` | **已存在**（`9c2d4f0`）：`createVmEngine()` 接好 brightness/PiP/orientation；Task 12 只追加预览三端口的可选参数 | Task 12（扩展） |

**修改**

| 文件 | 改动 | 任务 |
|---|---|---|
| `lib/src/core/options/options.dart` | 加 `preview` 节 + `copyWith`/`==`/`hashCode` | Task 10 |
| `lib/src/core/events/events.dart` | 加 `VmPreviewBlocked` | Task 10 |
| `lib/src/core/api.dart` | 加 `VmPreviewApi get preview` | Task 12 |
| `lib/src/core/engine.dart` | 装配并持有 `VmPreviewService`，`dispose()` 级联 | Task 12 |
| `lib/src/ui/components/preview.dart` | 新建 `PreviewComponent` | Task 13 |
| `lib/src/ui/skins/default_skin.dart` | 组件树加 `PreviewComponent()` | Task 13 |
| `lib/videoman.dart` | barrel 增补导出 | Task 2/10/12/13 |
| `pubspec.yaml` | 加两个依赖 | Task 5/7 |
| `test/support/fake_api.dart` | 加 `preview` 成员与 `FakePreviewApi` | Task 12 |
| `example/lib/main.dart` | 预览 demo 开关 | Task 14 |
| `README.md` / `CHANGELOG.md` / `doc/SPEC.md` | 文档 | Task 15 |

**测试**

`test/core/preview/{models,hash,vtt,cache,disk_cache,two_level_cache,net_probe,vtt_source,extractor,service}_test.dart`、
`test/core/options_test.dart`（增补）、`test/core/engine_test.dart`（增补）、
`test/platform_impl/net_probe_impl_test.dart`（新目录，Task 7）、`test/ui/preview_test.dart`、
`test/ui/skin_test.dart`（增补，Task 13）、`test/core/openness_preview_test.dart`（Task 15）。

**测试数量推进**（基线 94，已含 `9c2d4f0` 的 `wiring_test.dart` 3 项）：Task 2 → 105、
3 → 114、4 → 122、5 → 131、6 → 138、7 → 147、8 → 157、9 → 163、10 → 168、11 → 185、
12 → 190、13 → 199、15 → 212。

**一次性丢弃产物**

`example/lib/spike_screenshot.dart`（Task 1，跑完即删，结论回写本文档附录 A）。

**barrel 最终形态（权威清单）**

各 Task 的「barrel 增补导出」步骤只描述当次增量；阶段 B 全部做完后，`lib/videoman.dart` 里与
预览相关的导出必须恰好是下面这些，且整个文件按字母序排列（`flutter analyze` 不校验顺序，
但 review 按此对账）：

```dart
export 'src/core/preview/api.dart';
export 'src/core/preview/cache.dart';
export 'src/core/preview/dir_provider.dart';
export 'src/core/preview/disk_cache.dart';
export 'src/core/preview/extractor.dart';
export 'src/core/preview/fetcher.dart';
export 'src/core/preview/hash.dart';
export 'src/core/preview/models.dart';
export 'src/core/preview/net_probe.dart';
export 'src/core/preview/platform_kind.dart';
export 'src/core/preview/service.dart';
export 'src/core/preview/source.dart';
export 'src/core/preview/two_level_cache.dart';
export 'src/core/preview/vtt.dart';
export 'src/core/preview/vtt_source.dart';
export 'src/platform_impl/mpv_extractor_impl.dart';
export 'src/platform_impl/net_probe_impl.dart';
export 'src/platform_impl/thumb_dir_impl.dart';
export 'src/platform_impl/wiring.dart';
export 'src/ui/components/preview.dart';
```

`options/preview_config.dart` 不单独导出——它已由既有的
`export 'src/core/options/options.dart';` 传递导出。`export 'src/platform_impl/wiring.dart';`
这一行本身也已经存在（`9c2d4f0` 加的，不是本阶段哪个 Task 新增的导出）；列在这里只是因为
它导出的文件内容会被 Task 12 继续修改（加预览三端口参数），导出行本身不变。

---

## Task 1: 抽帧分辨率实测（DESIGN §11 头号风险）

DESIGN §7.3 假定给隐藏 `Player` 设 `vf=scale=<w>:-2` 就能让 `screenshot()` 吐出缩小后的帧。
但 libmpv 的 `screenshot-raw` 取的到底是**视频分辨率**还是**窗口/vo 分辨率**是未知的——如果是后者，
`vf=scale` 不会影响截图尺寸，必须改走 `VideoControllerConfiguration(width/height)` 路线。
**Task 2 及之后全部假定 `vf=scale` 路线成立**；若本任务证伪，必须先按 Step 4 修订本文档再继续。

这是个**非交互、自报告**的验证程序：它自己抽帧、自己解 JPEG/PNG 文件头读出真实像素宽高、
`print()` 出来、然后 `exit(0)`。执行者（AI agent）只需 `flutter run -d windows -t ...` 并读 stdout，
**不需要人肉观察窗口**。

**Files:**
- Create: `example/lib/spike_screenshot.dart`（临时，Step 5 删除）
- Modify: `doc/plans/2026-07-31-phase-b-preview.md`（写附录 A 结论）
- Test: 无（这是实跑验证，不是单测）

**Interfaces:**
- Consumes: media_kit `Player` / `VideoController` / `VideoControllerConfiguration` / `NativePlayer`
- Produces: 附录 A 的结论文本，与后续任务共享的两个常量决策：`kExtractorRoute`（`vfScale` 或
  `videoControllerSize`）、隐藏 `Player` 的属性列表

- [x] **Step 1: 写 spike 程序 `example/lib/spike_screenshot.dart`**

```dart
// Throwaway verification harness for DESIGN-0.2.0 §11's top risk: does
// libmpv's screenshot return the *video* resolution (so `vf=scale=W:-2`
// shrinks it) or the window/vo resolution (so it does not)? Runs headless,
// prints its findings, and exits — delete after recording the answer in
// doc/plans/2026-07-31-phase-b-preview.md appendix A.
//
// DESIGN-0.2.0 §11 头号风险的一次性验证程序：libmpv 的 screenshot 返回的是
// *视频* 分辨率（那么 `vf=scale=W:-2` 能缩小它）还是窗口/vo 分辨率（那么不能）？
// 无需交互，自行打印结论后退出——把答案记入
// doc/plans/2026-07-31-phase-b-preview.md 附录 A 后即可删除本文件。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// The clip used for the probe; same mp4 the example app already plays.
///
/// 探测所用的片源；与 example 应用已在播放的 mp4 相同。
const String _kUri =
    'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4';

/// Target width requested from both routes under test.
///
/// 两条待测路线都请求的目标宽度。
const int _kTargetWidth = 160;

/// Decoded pixel size of an encoded image, or nulls when the header could
/// not be parsed.
///
/// 编码图像解析出的像素尺寸；无法解析文件头时两项均为 null。
class _Dims {
  /// Pixel width, or null when unknown.
  ///
  /// 像素宽度；未知时为 null。
  final int? width;

  /// Pixel height, or null when unknown.
  ///
  /// 像素高度；未知时为 null。
  final int? height;

  /// Detected container format label, e.g. `jpeg` / `png` / `unknown`.
  ///
  /// 识别出的容器格式标签，如 `jpeg` / `png` / `unknown`。
  final String format;

  /// Creates a dimension record.
  ///
  /// 创建一条尺寸记录。
  const _Dims(this.width, this.height, this.format);

  @override
  String toString() => '$format ${width ?? '?'}x${height ?? '?'}';
}

/// Reads pixel dimensions straight out of a PNG or JPEG header without
/// decoding the image.
///
/// 直接从 PNG 或 JPEG 文件头读出像素尺寸，不解码图像本身。
///
/// - [bytes]: encoded image bytes / 编码后的图像字节
///
/// Returns the parsed [_Dims]; `format` is `unknown` when unrecognised.
///
/// 返回解析出的 [_Dims]；无法识别时 `format` 为 `unknown`。
_Dims _probeDims(Uint8List bytes) {
  if (bytes.length >= 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    return _Dims(w, h, 'png');
  }
  if (bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    var i = 2;
    while (i + 9 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = bytes[i + 1];
      final isSof = marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof) {
        final h = (bytes[i + 5] << 8) | bytes[i + 6];
        final w = (bytes[i + 7] << 8) | bytes[i + 8];
        return _Dims(w, h, 'jpeg');
      }
      final segLen = (bytes[i + 2] << 8) | bytes[i + 3];
      if (segLen < 2) break;
      i += 2 + segLen;
    }
    return const _Dims(null, null, 'jpeg');
  }
  return const _Dims(null, null, 'unknown');
}

/// Opens a hidden player, seeks, screenshots once, and reports the result.
///
/// 打开一个隐藏播放器，跳转、截图一次并报告结果。
///
/// - [label]: route name printed with the result / 打印结果时使用的路线名
/// - [useVfScale]: whether to set `vf=scale=<w>:-2` on the player /
///   是否给播放器设置 `vf=scale=<w>:-2`
/// - [controllerSize]: whether to pin `VideoControllerConfiguration`
///   width/height / 是否固定 `VideoControllerConfiguration` 的宽高
///
/// Returns the screenshot's parsed dimensions, or null when no bytes came
/// back.
///
/// 返回截图解析出的尺寸；未取到字节时返回 null。
Future<_Dims?> _probeRoute(
  String label, {
  required bool useVfScale,
  required bool controllerSize,
}) async {
  final player = Player();
  final controller = VideoController(
    player,
    configuration: controllerSize
        ? const VideoControllerConfiguration(width: _kTargetWidth, height: 90)
        : const VideoControllerConfiguration(),
  );
  try {
    final native = player.platform;
    if (native is NativePlayer) {
      await native.setProperty('ao', 'null');
      await native.setProperty('hwdec', 'no');
      await native.setProperty('hr-seek', 'yes');
      if (useVfScale) {
        await native.setProperty('vf', 'scale=$_kTargetWidth:-2');
      }
    } else {
      // ignore: avoid_print
      print('[$label] player.platform is not NativePlayer — cannot set mpv properties');
    }
    await player.open(Media(_kUri), play: false);
    await player.stream.duration.firstWhere((d) => d > Duration.zero).timeout(
          const Duration(seconds: 30),
          onTimeout: () => Duration.zero,
        );
    await player.seek(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(seconds: 2));
    final nativeW = player.state.width;
    final nativeH = player.state.height;
    final shot = await player.screenshot(format: 'image/jpeg');
    if (shot == null) {
      // ignore: avoid_print
      print('[$label] screenshot() returned null (native ${nativeW}x$nativeH)');
      return null;
    }
    final dims = _probeDims(shot);
    // ignore: avoid_print
    print('[$label] native=${nativeW}x$nativeH requested=${_kTargetWidth}px '
        'shot=$dims bytes=${shot.length} controller=${controller.id.value}');
    return dims;
  } finally {
    await player.dispose();
  }
}

/// Runs both routes and prints a one-line verdict the caller can grep.
///
/// 跑完两条路线并打印一行可被 grep 的结论。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // ignore: avoid_print
  print('=== VIDEOMAN SPIKE: screenshot resolution semantics ===');
  final baseline = await _probeRoute('baseline', useVfScale: false, controllerSize: false);
  final vfScale = await _probeRoute('vf=scale', useVfScale: true, controllerSize: false);
  final ctrlSize =
      await _probeRoute('controllerSize', useVfScale: false, controllerSize: true);
  final vfWorks = vfScale?.width == _kTargetWidth;
  final ctrlWorks = ctrlSize?.width == _kTargetWidth;
  // ignore: avoid_print
  print('=== VERDICT: baseline=$baseline vfScale=$vfScale controllerSize=$ctrlSize '
      'VF_SCALE_WORKS=$vfWorks CONTROLLER_SIZE_WORKS=$ctrlWorks ===');
  exit(0);
}
```

- [x] **Step 2: 跑 spike 并捕获 stdout**

Run: `cd example && flutter run -d windows -t lib/spike_screenshot.dart`
Expected: 控制台出现三行 `[baseline] …` / `[vf=scale] …` / `[controllerSize] …`，最后一行
`=== VERDICT: … VF_SCALE_WORKS=<bool> CONTROLLER_SIZE_WORKS=<bool> ===`，进程自行退出。

若 30s 内 `duration` 一直为 0（网络不可达），换成本地文件：把 `_kUri` 改成
`example/assets` 下任意 mp4 的绝对路径再跑一次；仍失败则在附录 A 记 `INCONCLUSIVE` 并按 Step 6
处理。

- [x] **Step 3: 把结论写进附录 A**

在本文档末尾的「附录 A：抽帧分辨率实测结论」下，把三行 `[...]` 输出与 `VERDICT` 行原样粘贴，
并写明最终选路：

- `VF_SCALE_WORKS=true` → 采用 **vfScale 路线**（Task 9 的 `MpvFrameExtractor` 设 `vf`，
  `VideoController` 用默认 configuration）。
- `VF_SCALE_WORKS=false` 且 `CONTROLLER_SIZE_WORKS=true` → 采用 **videoControllerSize 路线**
  （Task 9 改为在 `VideoControllerConfiguration(width: frameWidth, height: …)` 上下文章，
  不设 `vf`）。
- 两者皆 false → 采用 **原尺寸 + 不缩放** 兜底：抽出的就是原分辨率 JPEG，`frameWidth` 退化为
  仅用于 UI 显示宽度与 cacheKey，并在附录 A 明确记下"磁盘占用会显著高于预算，`diskMaxBytes`
  默认值需要复核"。

- [x] **Step 4: 若结论证伪 vfScale 路线，先修订本文档再往下走**

只需改一处：**Task 9 Step 5** 的 `MpvFrameExtractor` 实现代码——删掉 `_ensurePlayer()` 里的
`await native.setProperty('vf', 'scale=$width:-2');`，改为在 `VideoController(player)` 处传
`configuration: VideoControllerConfiguration(width: width, height: (width * 9 / 16).round())`，
并把 `_ensurePlayer` 的复用条件从"已存在即复用"改为"已存在**且宽度未变**才复用，否则先
`release()` 再重建"（`VideoControllerConfiguration` 只能在构造时给定）。同时把 Task 9 Step 5
开头那段引用本步骤的引用块改写为已确认的路线说明。

其余任务一律不受影响，因为它们只依赖 `VmFrameExtractor` 抽象，`extractor_test.dart` 用的是
`_FakeExtractor`、不碰 media_kit。**改完再进 Task 2。**

- [x] **Step 5: 删除 spike 文件**

```bash
git rm -f example/lib/spike_screenshot.dart
```

- [x] **Step 6: 校验并提交**

Run: `flutter analyze && flutter test`
Expected: 0 issues；94 项全绿（本任务未动 `lib/`）

```bash
git add -A
git commit -m "docs(videoman): record libmpv screenshot resolution spike result for preview extraction"
```

---

## Task 2: 缩略图模型与 FNV-1a cacheKey

纯数据 + 纯函数，零依赖，先把后续所有任务都要用的词汇表钉死。

**Files:**
- Create: `lib/src/core/preview/models.dart`, `lib/src/core/preview/hash.dart`
- Modify: `lib/videoman.dart`
- Test: `test/core/preview/models_test.dart`, `test/core/preview/hash_test.dart`

**Interfaces:**
- Consumes: 无（Phase B 首个代码任务）
- Produces:
  - `class VmThumbCrop { final int x, y, w, h; const VmThumbCrop({required this.x, required this.y, required this.w, required this.h}); }` 带 `==`/`hashCode`/`toString`
  - `class VmThumb { final Duration at; final Uint8List bytes; final VmThumbCrop? crop; const VmThumb({required this.at, required this.bytes, this.crop}); }`
  - `class VmThumbCue { final Duration start, end; final Uri image; final VmThumbCrop? crop; const VmThumbCue({required this.start, required this.end, required this.image, this.crop}); }` 带 `==`/`hashCode`
  - `class VmThumbIndex { final List<VmThumbCue> cues; const VmThumbIndex(this.cues); VmThumbCue? cueAt(Duration t); bool get isEmpty; }`
  - `int fnv1a64(String input)`（掩码为非负 63 位）
  - `String defaultCacheKey(String sourceKey, int bucketSec, int width)`
  - `typedef VmCacheKeyBuilder = String Function(String sourceKey, int bucketSec, int width);`

- [x] **Step 1: 写失败测试 `test/core/preview/models_test.dart`**

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/preview/models.dart';

/// Builds a cue spanning `[from, to)` seconds pointing at `sprite.jpg`.
///
/// 构造一条覆盖 `[from, to)` 秒、指向 `sprite.jpg` 的 cue。
VmThumbCue _cue(int from, int to, {VmThumbCrop? crop}) => VmThumbCue(
      start: Duration(seconds: from),
      end: Duration(seconds: to),
      image: Uri.parse('https://host/sprite.jpg'),
      crop: crop,
    );

void main() {
  test('VmThumbCrop compares by value', () {
    expect(
      const VmThumbCrop(x: 0, y: 0, w: 160, h: 90),
      const VmThumbCrop(x: 0, y: 0, w: 160, h: 90),
    );
    expect(
      const VmThumbCrop(x: 1, y: 0, w: 160, h: 90),
      isNot(const VmThumbCrop(x: 0, y: 0, w: 160, h: 90)),
    );
  });

  test('VmThumb carries its bucket position, bytes and optional crop', () {
    final t = VmThumb(
      at: const Duration(seconds: 10),
      bytes: Uint8List.fromList([1, 2, 3]),
      crop: const VmThumbCrop(x: 160, y: 0, w: 160, h: 90),
    );
    expect(t.at, const Duration(seconds: 10));
    expect(t.bytes, [1, 2, 3]);
    expect(t.crop!.x, 160);
  });

  test('VmThumbIndex.cueAt finds the covering cue', () {
    final idx = VmThumbIndex([_cue(0, 10), _cue(10, 20), _cue(20, 30)]);
    expect(idx.cueAt(const Duration(seconds: 0)), idx.cues[0]);
    expect(idx.cueAt(const Duration(seconds: 9)), idx.cues[0]);
    expect(idx.cueAt(const Duration(seconds: 10)), idx.cues[1]);
    expect(idx.cueAt(const Duration(seconds: 29, milliseconds: 999)), idx.cues[2]);
  });

  test('VmThumbIndex.cueAt clamps below the first and above the last cue', () {
    final idx = VmThumbIndex([_cue(5, 10), _cue(10, 20)]);
    expect(idx.cueAt(const Duration(seconds: 1)), idx.cues[0]);
    expect(idx.cueAt(const Duration(seconds: 999)), idx.cues[1]);
  });

  test('VmThumbIndex.cueAt on an empty index returns null', () {
    const idx = VmThumbIndex(<VmThumbCue>[]);
    expect(idx.isEmpty, isTrue);
    expect(idx.cueAt(const Duration(seconds: 3)), isNull);
  });

  test('VmThumbIndex.cueAt is a binary search over a large index', () {
    final cues = [for (var i = 0; i < 5000; i++) _cue(i * 10, i * 10 + 10)];
    final idx = VmThumbIndex(cues);
    expect(idx.cueAt(const Duration(seconds: 49995)), cues[4999]);
    expect(idx.cueAt(const Duration(seconds: 25000)), cues[2500]);
  });
}
```

- [x] **Step 2: 写失败测试 `test/core/preview/hash_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/preview/hash.dart';

void main() {
  test('fnv1a64 matches the reference vectors for the empty and short inputs', () {
    // Reference FNV-1a 64 vectors, masked to a non-negative Dart int.
    //
    // FNV-1a 64 的参考向量，掩码为非负 Dart int。
    expect(fnv1a64(''), 0xcbf29ce484222325 & 0x7FFFFFFFFFFFFFFF);
    expect(fnv1a64('a'), 0xaf63dc4c8601ec8c & 0x7FFFFFFFFFFFFFFF);
    expect(fnv1a64('foobar'), 0x85944171f73967e8 & 0x7FFFFFFFFFFFFFFF);
  });

  test('fnv1a64 is always non-negative', () {
    for (final s in ['', 'a', 'foobar', 'https://host/very/long/path.m3u8', '中文']) {
      expect(fnv1a64(s), greaterThanOrEqualTo(0), reason: s);
    }
  });

  test('defaultCacheKey is stable and filename-safe', () {
    final k = defaultCacheKey('https://host/a.mp4', 30, 160);
    expect(k, defaultCacheKey('https://host/a.mp4', 30, 160));
    expect(RegExp(r'^[0-9a-z_]+$').hasMatch(k), isTrue, reason: k);
  });

  test('defaultCacheKey separates buckets, widths and sources', () {
    expect(defaultCacheKey('a', 30, 160), isNot(defaultCacheKey('a', 40, 160)));
    expect(defaultCacheKey('a', 30, 160), isNot(defaultCacheKey('a', 30, 320)));
    expect(defaultCacheKey('a', 30, 160), isNot(defaultCacheKey('b', 30, 160)));
  });

  test('defaultCacheKey keeps bucket and width in clear text for debuggability', () {
    expect(defaultCacheKey('https://host/a.mp4', 30, 160), endsWith('_30_160'));
  });
}
```

- [x] **Step 3: 跑测试确认失败**

Run: `flutter test test/core/preview/`
Expected: FAIL — `Error when reading 'lib/src/core/preview/models.dart': No such file or directory` / `fnv1a64 isn't defined`

- [x] **Step 4: 实现 `lib/src/core/preview/models.dart`**

```dart
import 'dart:typed_data';

/// A rectangular sub-region of a sprite sheet, in image pixels.
///
/// 雪碧图中的一块矩形子区域，单位为图像像素。
class VmThumbCrop {
  /// Left edge in image pixels.
  ///
  /// 左边界（图像像素）。
  final int x;

  /// Top edge in image pixels.
  ///
  /// 上边界（图像像素）。
  final int y;

  /// Region width in image pixels.
  ///
  /// 区域宽度（图像像素）。
  final int w;

  /// Region height in image pixels.
  ///
  /// 区域高度（图像像素）。
  final int h;

  /// Creates a crop rectangle.
  ///
  /// 创建一个裁剪矩形。
  ///
  /// - [x], [y]: top-left corner in image pixels / 左上角（图像像素）
  /// - [w], [h]: size in image pixels / 尺寸（图像像素）
  const VmThumbCrop({required this.x, required this.y, required this.w, required this.h});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VmThumbCrop && other.x == x && other.y == y && other.w == w && other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() => 'VmThumbCrop($x,$y,$w,$h)';
}

/// One resolved preview frame: encoded image bytes, the sub-rectangle to
/// display, and the bucket-aligned position it represents.
///
/// 一帧已就绪的预览图：编码后的图像字节、要显示的子矩形，以及它所代表的
/// 桶对齐位置。
class VmThumb {
  /// The bucket-aligned media position this thumbnail represents.
  ///
  /// 该缩略图代表的桶对齐媒体位置。
  final Duration at;

  /// Encoded image bytes (JPEG or PNG); may be a whole sprite sheet when
  /// [crop] is non-null.
  ///
  /// 编码后的图像字节（JPEG 或 PNG）；[crop] 非空时可能是整张雪碧图。
  final Uint8List bytes;

  /// Sub-rectangle of [bytes] to display, or null to display the whole image.
  ///
  /// [bytes] 中要显示的子矩形；为空表示显示整张图。
  final VmThumbCrop? crop;

  /// Creates a preview frame.
  ///
  /// 创建一帧预览图。
  ///
  /// - [at]: bucket-aligned position / 桶对齐位置
  /// - [bytes]: encoded image bytes / 编码后的图像字节
  /// - [crop]: optional sub-rectangle / 可选的子矩形
  const VmThumb({required this.at, required this.bytes, this.crop});
}

/// One WebVTT thumbnail cue: a time range plus the image (and optional
/// sub-rectangle) covering it.
///
/// 一条 WebVTT 缩略图 cue：一个时间区间，以及覆盖该区间的图像（及可选子矩形）。
class VmThumbCue {
  /// Inclusive start of the covered range.
  ///
  /// 覆盖区间的起点（含）。
  final Duration start;

  /// Exclusive end of the covered range.
  ///
  /// 覆盖区间的终点（不含）。
  final Duration end;

  /// Absolute URL of the sprite sheet or standalone image.
  ///
  /// 雪碧图或独立图片的绝对 URL。
  final Uri image;

  /// Sub-rectangle within [image], or null when the whole image is the frame.
  ///
  /// [image] 内的子矩形；为空表示整张图就是该帧。
  final VmThumbCrop? crop;

  /// Creates a cue.
  ///
  /// 创建一条 cue。
  ///
  /// - [start], [end]: covered time range / 覆盖的时间区间
  /// - [image]: absolute image URL / 图片的绝对 URL
  /// - [crop]: optional sub-rectangle / 可选的子矩形
  const VmThumbCue({
    required this.start,
    required this.end,
    required this.image,
    this.crop,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VmThumbCue &&
          other.start == start &&
          other.end == end &&
          other.image == image &&
          other.crop == crop;

  @override
  int get hashCode => Object.hash(start, end, image, crop);

  @override
  String toString() =>
      'VmThumbCue(${start.inMilliseconds}-${end.inMilliseconds}, $image, $crop)';
}

/// A time-ordered set of [VmThumbCue]s with O(log n) lookup.
///
/// 按时间排序的 [VmThumbCue] 集合，查找复杂度 O(log n)。
class VmThumbIndex {
  /// The cues, sorted ascending by [VmThumbCue.start].
  ///
  /// 按 [VmThumbCue.start] 升序排列的 cue 列表。
  final List<VmThumbCue> cues;

  /// Creates an index over already-sorted [cues].
  ///
  /// 用已排序的 [cues] 创建索引。
  ///
  /// - [cues]: cues sorted ascending by start / 按起点升序排列的 cue 列表
  const VmThumbIndex(this.cues);

  /// Whether this index holds no cues.
  ///
  /// 该索引是否不含任何 cue。
  bool get isEmpty => cues.isEmpty;

  /// Finds the cue covering [t], clamping to the first/last cue when [t]
  /// falls outside the indexed range.
  ///
  /// 查找覆盖 [t] 的 cue；[t] 落在索引范围之外时，钳到首/末条 cue。
  ///
  /// - [t]: the media position to look up / 要查找的媒体位置
  ///
  /// Returns the matching cue, or null when the index is empty.
  ///
  /// 返回匹配的 cue；索引为空时返回 null。
  VmThumbCue? cueAt(Duration t) {
    if (cues.isEmpty) return null;
    if (t < cues.first.start) return cues.first;
    var lo = 0;
    var hi = cues.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (cues[mid].start <= t) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return cues[lo];
  }
}
```

- [x] **Step 5: 实现 `lib/src/core/preview/hash.dart`**

```dart
/// 64-bit FNV-1a offset basis.
///
/// FNV-1a 64 位算法的初始偏移量。
const int _kOffsetBasis = 0xcbf29ce484222325;

/// 64-bit FNV-1a prime.
///
/// FNV-1a 64 位算法的质数因子。
const int _kPrime = 0x100000001b3;

/// Computes a 64-bit FNV-1a hash of [input], masked to a non-negative Dart int.
///
/// Self-written on purpose: cache keys need no cryptographic strength, and this
/// keeps `package:crypto` out of the dependency list (DESIGN §12).
///
/// 计算 [input] 的 64 位 FNV-1a 哈希，并掩码为非负 Dart int。
///
/// 刻意自写：缓存 key 不需要密码学强度，这样可以不引入 `package:crypto`
/// （DESIGN §12）。
///
/// - [input]: the string to hash / 要哈希的字符串
///
/// Returns a non-negative 63-bit hash value.
///
/// 返回一个非负的 63 位哈希值。
int fnv1a64(String input) {
  var hash = _kOffsetBasis;
  for (var i = 0; i < input.length; i++) {
    final unit = input.codeUnitAt(i);
    hash ^= unit & 0xFF;
    hash = (hash * _kPrime) & 0xFFFFFFFFFFFFFFFF;
    if (unit > 0xFF) {
      hash ^= (unit >> 8) & 0xFF;
      hash = (hash * _kPrime) & 0xFFFFFFFFFFFFFFFF;
    }
  }
  return hash & 0x7FFFFFFFFFFFFFFF;
}

/// Builds the default cache key for one thumbnail.
///
/// Shape is `<fnv1a64(sourceKey) in base36>_<bucketSec>_<width>` — the hash
/// keeps the key filename-safe and bounded, while bucket and width stay in
/// clear text so a cache directory can be eyeballed while debugging.
///
/// 生成一张缩略图的默认缓存 key。
///
/// 形如 `<fnv1a64(sourceKey) 的 36 进制>_<bucketSec>_<width>`——哈希保证 key
/// 可作文件名且长度有界，桶秒数与宽度保留明文，便于调试时肉眼查看缓存目录。
///
/// - [sourceKey]: stable identifier of the media source, usually its URI /
///   媒体源的稳定标识，通常是其 URI
/// - [bucketSec]: bucket-aligned position in whole seconds / 桶对齐位置（整秒）
/// - [width]: requested frame width in pixels / 请求的帧宽度（像素）
///
/// Returns the cache key.
///
/// 返回缓存 key。
String defaultCacheKey(String sourceKey, int bucketSec, int width) =>
    '${fnv1a64(sourceKey).toRadixString(36)}_${bucketSec}_$width';

/// Strategy for building thumbnail cache keys; see [defaultCacheKey].
///
/// 缩略图缓存 key 的构建策略；参见 [defaultCacheKey]。
///
/// - [sourceKey]: stable identifier of the media source / 媒体源的稳定标识
/// - [bucketSec]: bucket-aligned position in whole seconds / 桶对齐位置（整秒）
/// - [width]: requested frame width in pixels / 请求的帧宽度（像素）
///
/// Returns the cache key.
///
/// 返回缓存 key。
typedef VmCacheKeyBuilder = String Function(String sourceKey, int bucketSec, int width);
```

- [x] **Step 6: barrel 增补导出**

`lib/videoman.dart` 在 `export 'src/core/platform/ports.dart';` 之后按字母序插入两行：

```dart
export 'src/core/preview/hash.dart';
export 'src/core/preview/models.dart';
```

- [x] **Step 7: 跑测试确认通过**

Run: `flutter test test/core/preview/ && flutter analyze`
Expected: 11 项 PASS（models 6 + hash 5），analyze 0 issues

- [x] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(videoman): add thumbnail models and FNV-1a cache-key hashing"
```

---

## Task 3: WebVTT 缩略图解析

纯函数：`#xywh` 片段、相对路径、畸形行、空文件全覆盖。

**Files:**
- Create: `lib/src/core/preview/vtt.dart`
- Modify: `lib/videoman.dart`
- Test: `test/core/preview/vtt_test.dart`

**Interfaces:**
- Consumes: `VmThumbCue`, `VmThumbCrop`, `VmThumbIndex`（Task 2）
- Produces: `VmThumbIndex parseVttThumbs(String content, {required Uri base})`

- [x] **Step 1: 写失败测试 `test/core/preview/vtt_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/preview/models.dart';
import 'package:videoman/src/core/preview/vtt.dart';

/// Base URL every relative sprite path in these fixtures resolves against.
///
/// 这些用例中相对雪碧图路径解析所依据的基准 URL。
final Uri _base = Uri.parse('https://host/media/video.mp4.vtt');

void main() {
  test('parses cues with #xywh crops and resolves relative sprite paths', () {
    const vtt = 'WEBVTT\n'
        '\n'
        '00:00:00.000 --> 00:00:10.000\n'
        'sprite-0.jpg#xywh=0,0,160,90\n'
        '\n'
        '00:00:10.000 --> 00:00:20.000\n'
        'sprite-0.jpg#xywh=160,0,160,90\n';
    final idx = parseVttThumbs(vtt, base: _base);
    expect(idx.cues.length, 2);
    expect(idx.cues[0].start, Duration.zero);
    expect(idx.cues[0].end, const Duration(seconds: 10));
    expect(idx.cues[0].image, Uri.parse('https://host/media/sprite-0.jpg'));
    expect(idx.cues[0].crop, const VmThumbCrop(x: 0, y: 0, w: 160, h: 90));
    expect(idx.cues[1].crop, const VmThumbCrop(x: 160, y: 0, w: 160, h: 90));
  });

  test('a cue without #xywh means the whole image', () {
    const vtt = 'WEBVTT\n\n00:00:00.000 --> 00:00:05.000\nframe-0.jpg\n';
    final idx = parseVttThumbs(vtt, base: _base);
    expect(idx.cues.single.crop, isNull);
    expect(idx.cues.single.image, Uri.parse('https://host/media/frame-0.jpg'));
  });

  test('absolute sprite URLs are kept as-is', () {
    const vtt = 'WEBVTT\n'
        '\n'
        '00:00:00.000 --> 00:00:05.000\n'
        'https://cdn.example.com/s.jpg#xywh=0,0,10,10\n';
    final idx = parseVttThumbs(vtt, base: _base);
    expect(idx.cues.single.image, Uri.parse('https://cdn.example.com/s.jpg'));
  });

  test('supports hours, cue identifiers, comments and CRLF line endings', () {
    const vtt = 'WEBVTT\r\n'
        '\r\n'
        'NOTE this is a comment\r\n'
        '\r\n'
        '1\r\n'
        '01:02:03.500 --> 01:02:13.500\r\n'
        'sprite-1.jpg#xywh=0,90,160,90\r\n';
    final idx = parseVttThumbs(vtt, base: _base);
    expect(
      idx.cues.single.start,
      const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500),
    );
    expect(
      idx.cues.single.end,
      const Duration(hours: 1, minutes: 2, seconds: 13, milliseconds: 500),
    );
    expect(idx.cues.single.crop, const VmThumbCrop(x: 0, y: 90, w: 160, h: 90));
  });

  test('supports the MM:SS.mmm short timestamp form', () {
    const vtt = 'WEBVTT\n\n02:03.000 --> 02:13.000\ns.jpg\n';
    final idx = parseVttThumbs(vtt, base: _base);
    expect(idx.cues.single.start, const Duration(minutes: 2, seconds: 3));
    expect(idx.cues.single.end, const Duration(minutes: 2, seconds: 13));
  });

  test('malformed timing lines, empty payloads and junk are skipped', () {
    const vtt = 'WEBVTT\n'
        '\n'
        'nonsense line\n'
        '\n'
        '00:00:00.000 -> 00:00:10.000\n'
        'bad-arrow.jpg\n'
        '\n'
        '00:00:10.000 --> 00:00:20.000\n'
        '\n'
        '00:00:20.000 --> 00:00:30.000\n'
        'good.jpg#xywh=0,0,160,90\n'
        '\n'
        'xx:yy:zz.qqq --> 00:00:40.000\n'
        'bad-time.jpg\n';
    final idx = parseVttThumbs(vtt, base: _base);
    expect(idx.cues.length, 1);
    expect(idx.cues.single.image, Uri.parse('https://host/media/good.jpg'));
  });

  test('an empty or non-WEBVTT document yields an empty index', () {
    expect(parseVttThumbs('', base: _base).isEmpty, isTrue);
    expect(parseVttThumbs('   \n\n', base: _base).isEmpty, isTrue);
    expect(parseVttThumbs('not a vtt file at all', base: _base).isEmpty, isTrue);
  });

  test('cues come back sorted ascending by start even if the file is not', () {
    const vtt = 'WEBVTT\n'
        '\n'
        '00:00:20.000 --> 00:00:30.000\n'
        'c.jpg\n'
        '\n'
        '00:00:00.000 --> 00:00:10.000\n'
        'a.jpg\n';
    final idx = parseVttThumbs(vtt, base: _base);
    expect(idx.cues.first.image.pathSegments.last, 'a.jpg');
    expect(idx.cueAt(const Duration(seconds: 25))!.image.pathSegments.last, 'c.jpg');
  });

  test('a malformed #xywh fragment degrades to no crop rather than dropping the cue', () {
    const vtt = 'WEBVTT\n\n00:00:00.000 --> 00:00:10.000\ns.jpg#xywh=0,0,abc\n';
    final idx = parseVttThumbs(vtt, base: _base);
    expect(idx.cues.single.crop, isNull);
    expect(idx.cues.single.image, Uri.parse('https://host/media/s.jpg'));
  });
}
```

- [x] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/preview/vtt_test.dart`
Expected: FAIL — `Error when reading 'lib/src/core/preview/vtt.dart': No such file or directory`

- [x] **Step 3: 实现 `lib/src/core/preview/vtt.dart`**

```dart
import 'models.dart';

/// Matches a WebVTT timing line such as `00:00:10.000 --> 00:00:20.000`,
/// tolerating the `MM:SS.mmm` short form and trailing cue settings.
///
/// 匹配 WebVTT 时间轴行，如 `00:00:10.000 --> 00:00:20.000`；兼容 `MM:SS.mmm`
/// 短格式与行尾的 cue 设置。
final RegExp _kTimingLine = RegExp(
  r'^\s*(\d{1,3}:)?(\d{1,2}):(\d{1,2})[.,](\d{1,3})\s*-->\s*'
  r'(\d{1,3}:)?(\d{1,2}):(\d{1,2})[.,](\d{1,3})',
);

/// Matches an `xywh=x,y,w,h` media fragment (the leading `#` already removed).
///
/// 匹配 `xywh=x,y,w,h` 媒体片段（前导 `#` 已被去掉）。
final RegExp _kXywh = RegExp(r'^xywh=(-?\d+),(-?\d+),(-?\d+),(-?\d+)$');

/// Converts one side of a timing line's captured groups into a [Duration].
///
/// 把时间轴行一侧捕获到的分组转换为 [Duration]。
///
/// - [hours]: the `HH:` group including its colon, or null / 含冒号的 `HH:`
///   分组，可为 null
/// - [minutes]: the minutes group / 分钟分组
/// - [seconds]: the seconds group / 秒分组
/// - [millis]: the fractional group, right-padded to milliseconds /
///   小数分组，右补零到毫秒
///
/// Returns the parsed duration.
///
/// 返回解析出的时长。
Duration _toDuration(String? hours, String minutes, String seconds, String millis) {
  final h = hours == null ? 0 : int.parse(hours.substring(0, hours.length - 1));
  return Duration(
    hours: h,
    minutes: int.parse(minutes),
    seconds: int.parse(seconds),
    milliseconds: int.parse(millis.padRight(3, '0')),
  );
}

/// Parses a WebVTT thumbnail track into a time-ordered [VmThumbIndex].
///
/// Only cues whose payload is a single image reference are kept. A payload may
/// carry an `#xywh=x,y,w,h` media fragment selecting a sub-rectangle of a
/// sprite sheet; without one, the whole image is the frame. Relative payload
/// paths resolve against [base]. Malformed timing lines, empty payloads and
/// unparsable fragments never throw — the offending cue is skipped, or, for a
/// bad fragment only, kept without a crop.
///
/// 把 WebVTT 缩略图轨解析为按时间排序的 [VmThumbIndex]。
///
/// 只保留 payload 为单个图片引用的 cue。payload 可带 `#xywh=x,y,w,h` 媒体片段
/// 以选取雪碧图的子矩形；不带时整张图即为该帧。相对路径按 [base] 解析。
/// 畸形时间轴行、空 payload、无法解析的片段都不会抛异常——对应 cue 会被跳过；
/// 仅片段畸形时则保留 cue 但不带裁剪。
///
/// - [content]: raw `.vtt` file content / 原始 `.vtt` 文件内容
/// - [base]: URL the `.vtt` itself was fetched from, used to resolve relative
///   sprite paths / 该 `.vtt` 自身的 URL，用于解析相对雪碧图路径
///
/// Returns the parsed index; empty when [content] is empty or is not a WebVTT
/// document.
///
/// 返回解析出的索引；[content] 为空或不是 WebVTT 文档时返回空索引。
VmThumbIndex parseVttThumbs(String content, {required Uri base}) {
  if (!content.trimLeft().startsWith('WEBVTT')) {
    return const VmThumbIndex(<VmThumbCue>[]);
  }

  final lines = content.split(RegExp(r'\r\n|\n|\r'));
  final cues = <VmThumbCue>[];

  for (var i = 0; i < lines.length; i++) {
    final m = _kTimingLine.firstMatch(lines[i]);
    if (m == null) continue;
    final start = _toDuration(m.group(1), m.group(2)!, m.group(3)!, m.group(4)!);
    final end = _toDuration(m.group(5), m.group(6)!, m.group(7)!, m.group(8)!);

    // Payload is the line right after the timing line; a blank line there
    // means this cue has no image and is skipped.
    //
    // payload 取时间轴行的下一行；该行为空说明本 cue 没有图片，直接跳过。
    final payload = i + 1 < lines.length ? lines[i + 1].trim() : '';
    if (payload.isEmpty) continue;

    final hashAt = payload.indexOf('#');
    final path = hashAt < 0 ? payload : payload.substring(0, hashAt);
    final fragment = hashAt < 0 ? '' : payload.substring(hashAt + 1);
    if (path.isEmpty) continue;

    final f = _kXywh.firstMatch(fragment);
    final crop = f == null
        ? null
        : VmThumbCrop(
            x: int.parse(f.group(1)!),
            y: int.parse(f.group(2)!),
            w: int.parse(f.group(3)!),
            h: int.parse(f.group(4)!),
          );

    final Uri image;
    try {
      image = base.resolve(path);
    } on FormatException {
      continue;
    }
    cues.add(VmThumbCue(start: start, end: end, image: image, crop: crop));
  }

  cues.sort((a, b) => a.start.compareTo(b.start));
  return VmThumbIndex(cues);
}
```

- [x] **Step 4: barrel 增补导出**

`lib/videoman.dart` 在 `export 'src/core/preview/models.dart';` 之后插入：

```dart
export 'src/core/preview/vtt.dart';
```

- [x] **Step 5: 跑测试确认通过**

Run: `flutter test test/core/preview/vtt_test.dart && flutter analyze`
Expected: 9 项 PASS，analyze 0 issues

- [x] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(videoman): parse WebVTT thumbnail tracks into a searchable cue index"
```

---

## Task 4: 缓存抽象与内存计数 LRU

DESIGN §7.4「内存：计数 LRU，默认 40 项」+ §6.1「内存上限 / `memMaxEntries` / 自定义
`VmThumbCache`」。`peek` 是同步方法，专供 §7.1 的「内存命中 → 同帧同步返回，无闪烁」。

**Files:**
- Create: `lib/src/core/preview/cache.dart`
- Modify: `lib/videoman.dart`
- Test: `test/core/preview/cache_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `abstract class VmThumbCache { Uint8List? peek(String key); Future<Uint8List?> read(String key); Future<void> write(String key, Uint8List bytes); Future<void> clear(); Future<void> dispose(); }`
  - `class VmMemoryThumbCache implements VmThumbCache { VmMemoryThumbCache({int maxEntries = 40}); final int maxEntries; int get length; }`

- [ ] **Step 1: 写失败测试 `test/core/preview/cache_test.dart`**

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/preview/cache.dart';

/// Builds [n] filler bytes so tests can tell payloads apart by length.
///
/// 造 [n] 个填充字节，让测试可以按长度区分不同负载。
Uint8List _bytes(int n) => Uint8List.fromList(List<int>.filled(n, n & 0xFF));

void main() {
  test('peek and read miss on an unknown key', () async {
    final c = VmMemoryThumbCache();
    expect(c.peek('nope'), isNull);
    expect(await c.read('nope'), isNull);
    await c.dispose();
  });

  test('write makes the entry available synchronously via peek', () async {
    final c = VmMemoryThumbCache();
    await c.write('k', _bytes(3));
    expect(c.peek('k'), _bytes(3));
    expect(await c.read('k'), _bytes(3));
    expect(c.length, 1);
    await c.dispose();
  });

  test('writing the same key twice replaces rather than duplicates', () async {
    final c = VmMemoryThumbCache();
    await c.write('k', _bytes(3));
    await c.write('k', _bytes(5));
    expect(c.length, 1);
    expect(c.peek('k'), _bytes(5));
    await c.dispose();
  });

  test('count LRU evicts the least recently used entry past maxEntries', () async {
    final c = VmMemoryThumbCache(maxEntries: 2);
    await c.write('a', _bytes(1));
    await c.write('b', _bytes(2));
    await c.write('c', _bytes(3));
    expect(c.length, 2);
    expect(c.peek('a'), isNull);
    expect(c.peek('b'), _bytes(2));
    expect(c.peek('c'), _bytes(3));
    await c.dispose();
  });

  test('peek refreshes recency so the touched entry survives eviction', () async {
    final c = VmMemoryThumbCache(maxEntries: 2);
    await c.write('a', _bytes(1));
    await c.write('b', _bytes(2));
    c.peek('a');
    await c.write('c', _bytes(3));
    expect(c.peek('a'), _bytes(1));
    expect(c.peek('b'), isNull);
    await c.dispose();
  });

  test('read refreshes recency the same way peek does', () async {
    final c = VmMemoryThumbCache(maxEntries: 2);
    await c.write('a', _bytes(1));
    await c.write('b', _bytes(2));
    await c.read('a');
    await c.write('c', _bytes(3));
    expect(c.peek('a'), _bytes(1));
    expect(c.peek('b'), isNull);
    await c.dispose();
  });

  test('maxEntries of zero disables caching entirely', () async {
    final c = VmMemoryThumbCache(maxEntries: 0);
    await c.write('a', _bytes(1));
    expect(c.length, 0);
    expect(c.peek('a'), isNull);
    await c.dispose();
  });

  test('clear empties the cache', () async {
    final c = VmMemoryThumbCache();
    await c.write('a', _bytes(1));
    await c.write('b', _bytes(2));
    await c.clear();
    expect(c.length, 0);
    expect(c.peek('a'), isNull);
    await c.dispose();
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/preview/cache_test.dart`
Expected: FAIL — `Error when reading 'lib/src/core/preview/cache.dart': No such file or directory`

- [ ] **Step 3: 实现 `lib/src/core/preview/cache.dart`**

```dart
import 'dart:collection';
import 'dart:typed_data';

/// Storage for encoded thumbnail bytes, keyed by a cache key.
///
/// [peek] is deliberately synchronous: a memory hit must be renderable in the
/// same frame the scrub position changes, otherwise the preview bubble
/// flickers. Anything that may touch disk or the network belongs in [read].
///
/// 按缓存 key 存取缩略图编码字节的存储。
///
/// [peek] 刻意设计为同步：内存命中必须在拖动位置变化的同一帧内就能渲染，
/// 否则预览气泡会闪烁。任何可能触达磁盘或网络的读取都应放在 [read]。
abstract class VmThumbCache {
  /// Returns the bytes for [key] if they are resident and cheap to fetch,
  /// otherwise null. Must never do I/O.
  ///
  /// 若 [key] 对应的字节已驻留且获取代价极低则返回之，否则返回 null。
  /// 该方法绝不能做 I/O。
  ///
  /// - [key]: the cache key / 缓存 key
  ///
  /// Returns the cached bytes or null.
  ///
  /// 返回缓存的字节或 null。
  Uint8List? peek(String key);

  /// Returns the bytes for [key], possibly hitting slower storage.
  ///
  /// 返回 [key] 对应的字节，允许访问较慢的存储层。
  ///
  /// - [key]: the cache key / 缓存 key
  ///
  /// Returns the cached bytes or null when absent.
  ///
  /// 返回缓存的字节；不存在时返回 null。
  Future<Uint8List?> read(String key);

  /// Stores [bytes] under [key], evicting as needed to stay within limits.
  ///
  /// 以 [key] 存入 [bytes]，必要时淘汰旧条目以维持容量上限。
  ///
  /// - [key]: the cache key / 缓存 key
  /// - [bytes]: encoded image bytes / 编码后的图像字节
  Future<void> write(String key, Uint8List bytes);

  /// Removes every entry.
  ///
  /// 清空全部条目。
  Future<void> clear();

  /// Releases any resources held by this cache; does not imply [clear].
  ///
  /// 释放该缓存持有的资源；不隐含调用 [clear]。
  Future<void> dispose();
}

/// An in-memory [VmThumbCache] with count-based LRU eviction.
///
/// Stores encoded bytes (not decoded `ui.Image`s) so the core layer stays free
/// of Flutter types and memory usage stays predictable.
///
/// 基于条目数做 LRU 淘汰的内存 [VmThumbCache]。
///
/// 存的是编码后的字节（而非已解码的 `ui.Image`），从而让 core 层不依赖
/// Flutter 类型，内存占用也更可预测。
class VmMemoryThumbCache implements VmThumbCache {
  /// Creates an in-memory cache holding at most [maxEntries] thumbnails.
  ///
  /// 创建一个最多保存 [maxEntries] 张缩略图的内存缓存。
  ///
  /// - [maxEntries]: entry ceiling; `0` or negative disables caching entirely /
  ///   条目上限；为 `0` 或负数时完全禁用缓存
  VmMemoryThumbCache({this.maxEntries = 40});

  /// Maximum number of resident entries; `0` or negative disables caching.
  ///
  /// 可驻留的最大条目数；为 `0` 或负数时禁用缓存。
  final int maxEntries;

  /// Entries in least-recently-used-first iteration order.
  ///
  /// 按"最久未使用在前"的迭代顺序存放的条目。
  final LinkedHashMap<String, Uint8List> _entries = LinkedHashMap<String, Uint8List>();

  /// Number of resident entries.
  ///
  /// 当前驻留的条目数。
  int get length => _entries.length;

  /// Moves [key] to the most-recently-used end of the ordering.
  ///
  /// 把 [key] 移到"最近使用"一端。
  ///
  /// - [key]: the key to touch / 要刷新的 key
  ///
  /// Returns the bytes for [key], or null when absent.
  ///
  /// 返回 [key] 对应的字节；不存在时返回 null。
  Uint8List? _touch(String key) {
    final v = _entries.remove(key);
    if (v == null) return null;
    _entries[key] = v;
    return v;
  }

  @override
  Uint8List? peek(String key) => _touch(key);

  @override
  Future<Uint8List?> read(String key) async => _touch(key);

  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (maxEntries <= 0) return;
    _entries.remove(key);
    _entries[key] = bytes;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  @override
  Future<void> clear() async => _entries.clear();

  @override
  Future<void> dispose() async {}
}
```

- [ ] **Step 4: barrel 增补导出**

`lib/videoman.dart` 在 `export 'src/core/preview/hash.dart';` 之前插入：

```dart
export 'src/core/preview/cache.dart';
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/core/preview/cache_test.dart && flutter analyze`
Expected: 8 项 PASS，analyze 0 issues

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(videoman): add thumbnail cache port with in-memory count LRU"
```

---

## Task 5: 磁盘字节 LRU 与目录端口（引入 `path_provider`）

DESIGN §7.4「磁盘：`getTemporaryDirectory()/videoman_thumbs/`，字节 LRU 默认 64MB」+
§6.1「磁盘上限 / 目录 | 64MB / 临时目录 | `diskMaxBytes`、`diskDir`」。
`path_provider` 是 Flutter 插件，所以**目录解析拆成端口**：抽象在 core，`getTemporaryDirectory()`
实现在 `platform_impl/`。磁盘读写本身只用 `dart:io`，留在 core。

**Files:**
- Create: `lib/src/core/preview/dir_provider.dart`, `lib/src/core/preview/disk_cache.dart`, `lib/src/platform_impl/thumb_dir_impl.dart`
- Modify: `pubspec.yaml`, `lib/videoman.dart`
- Test: `test/core/preview/disk_cache_test.dart`

**Interfaces:**
- Consumes: `VmThumbCache`（Task 4）
- Produces:
  - `abstract class VmThumbDirProvider { Future<String> resolve(); }`
  - `class FixedThumbDirProvider implements VmThumbDirProvider { const FixedThumbDirProvider(this.path); final String path; }`
  - `class VmDiskThumbCache implements VmThumbCache { VmDiskThumbCache({required VmThumbDirProvider dir, int maxBytes = 64 * 1024 * 1024}); final int maxBytes; Future<void> evict(); Future<int> totalBytes(); }`
  - `class TempThumbDirProvider implements VmThumbDirProvider { const TempThumbDirProvider({String folderName = 'videoman_thumbs'}); final String folderName; }`（`platform_impl`）

- [ ] **Step 1: 加依赖**

`pubspec.yaml` 的 `dependencies:` 段内，`plugin_platform_interface` 与 `screen_brightness` 之间
按字母序插入：

```yaml
  path_provider: ^2.1.5
```

Run: `flutter pub get`
Expected: 解析成功，`pubspec.lock` 出现 `path_provider`

- [ ] **Step 2: 写失败测试 `test/core/preview/disk_cache_test.dart`**

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/preview/dir_provider.dart';
import 'package:videoman/src/core/preview/disk_cache.dart';

/// Builds [n] filler bytes so tests can tell payloads apart by length.
///
/// 造 [n] 个填充字节，让测试可以按长度区分不同负载。
Uint8List _bytes(int n) => Uint8List.fromList(List<int>.filled(n, n & 0xFF));

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('vm_thumbs_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Builds a disk cache rooted at the per-test temp directory.
  ///
  /// 构造一个以本用例临时目录为根的磁盘缓存。
  VmDiskThumbCache cache({int maxBytes = 1 << 20}) => VmDiskThumbCache(
        dir: FixedThumbDirProvider(tmp.path),
        maxBytes: maxBytes,
      );

  test('write then read round-trips the bytes', () async {
    final c = cache();
    await c.write('k', _bytes(64));
    expect(await c.read('k'), _bytes(64));
    await c.dispose();
  });

  test('read misses return null and never throw', () async {
    final c = cache();
    expect(await c.read('missing'), isNull);
    await c.dispose();
  });

  test('peek is always null because disk reads cannot be synchronous', () async {
    final c = cache();
    await c.write('k', _bytes(8));
    expect(c.peek('k'), isNull);
    await c.dispose();
  });

  test('totalBytes reports the sum of stored entries', () async {
    final c = cache();
    await c.write('a', _bytes(100));
    await c.write('b', _bytes(50));
    expect(await c.totalBytes(), 150);
    await c.dispose();
  });

  test('evict deletes oldest-touched files until the byte budget is met', () async {
    final big = cache();
    await big.write('a', _bytes(100));
    await big.write('b', _bytes(100));
    await big.write('c', _bytes(100));
    await big.dispose();

    final now = DateTime.now();
    File('${tmp.path}/a.thumb').setLastModifiedSync(now.subtract(const Duration(hours: 3)));
    File('${tmp.path}/b.thumb').setLastModifiedSync(now.subtract(const Duration(hours: 2)));
    File('${tmp.path}/c.thumb').setLastModifiedSync(now.subtract(const Duration(hours: 1)));

    final small = cache(maxBytes: 250);
    await small.evict();
    expect(await small.read('a'), isNull);
    expect(await small.read('b'), _bytes(100));
    expect(await small.read('c'), _bytes(100));
    await small.dispose();
  });

  test('read touches the file so a re-read entry survives the next eviction', () async {
    final big = cache();
    await big.write('a', _bytes(100));
    await big.write('b', _bytes(100));
    await big.write('c', _bytes(100));
    await big.dispose();

    final now = DateTime.now();
    File('${tmp.path}/a.thumb').setLastModifiedSync(now.subtract(const Duration(hours: 3)));
    File('${tmp.path}/b.thumb').setLastModifiedSync(now.subtract(const Duration(hours: 2)));
    File('${tmp.path}/c.thumb').setLastModifiedSync(now.subtract(const Duration(hours: 1)));

    final small = cache(maxBytes: 250);
    await small.read('a');
    await small.evict();
    expect(await small.read('a'), _bytes(100));
    expect(await small.read('b'), isNull);
    await small.dispose();
  });

  test('write evicts inline so the budget is never exceeded after a write', () async {
    final c = cache(maxBytes: 150);
    await c.write('a', _bytes(100));
    await c.write('b', _bytes(100));
    expect(await c.totalBytes(), lessThanOrEqualTo(150));
    await c.dispose();
  });

  test('clear removes every stored entry but keeps the directory usable', () async {
    final c = cache();
    await c.write('a', _bytes(10));
    await c.clear();
    expect(await c.totalBytes(), 0);
    await c.write('b', _bytes(10));
    expect(await c.read('b'), _bytes(10));
    await c.dispose();
  });

  test('an unusable directory degrades to a silent no-op cache', () async {
    final blocker = File('${tmp.path}/blocker')..writeAsStringSync('x');
    final c = VmDiskThumbCache(
      dir: FixedThumbDirProvider('${blocker.path}/nested'),
      maxBytes: 1 << 20,
    );
    await c.write('k', _bytes(4));
    expect(await c.read('k'), isNull);
    expect(await c.totalBytes(), 0);
    await c.clear();
    await c.dispose();
  });
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/core/preview/disk_cache_test.dart`
Expected: FAIL — `Error when reading 'lib/src/core/preview/dir_provider.dart': No such file or directory`

- [ ] **Step 4: 实现 `lib/src/core/preview/dir_provider.dart`**

```dart
/// Resolves the on-disk directory thumbnails are cached in.
///
/// Kept as a port because the default answer needs `path_provider`
/// (`getTemporaryDirectory()`), a Flutter plugin that must not be imported
/// from `lib/src/core/**`. The concrete implementation lives in
/// `lib/src/platform_impl/thumb_dir_impl.dart`.
///
/// 解析缩略图磁盘缓存所在目录。
///
/// 之所以做成端口，是因为默认答案需要 `path_provider`
/// （`getTemporaryDirectory()`）——它是 Flutter 插件，`lib/src/core/**`
/// 下不允许引入。具体实现放在 `lib/src/platform_impl/thumb_dir_impl.dart`。
abstract class VmThumbDirProvider {
  /// Returns the absolute path of the cache directory; the caller creates it
  /// if it does not exist yet.
  ///
  /// 返回缓存目录的绝对路径；目录不存在时由调用方负责创建。
  ///
  /// Returns the directory path.
  ///
  /// 返回目录路径。
  Future<String> resolve();
}

/// A [VmThumbDirProvider] that always returns one fixed path.
///
/// Backs the `diskDir` config knob and keeps disk-cache tests free of
/// plugin channels.
///
/// 恒定返回同一路径的 [VmThumbDirProvider]。
///
/// 既支撑 `diskDir` 配置项，也让磁盘缓存测试无需依赖插件通道。
class FixedThumbDirProvider implements VmThumbDirProvider {
  /// Creates a provider pinned to [path].
  ///
  /// 创建一个固定指向 [path] 的 provider。
  ///
  /// - [path]: absolute cache directory path / 缓存目录的绝对路径
  const FixedThumbDirProvider(this.path);

  /// The fixed cache directory path.
  ///
  /// 固定的缓存目录路径。
  final String path;

  @override
  Future<String> resolve() async => path;
}
```

- [ ] **Step 5: 实现 `lib/src/core/preview/disk_cache.dart`**

```dart
import 'dart:io';
import 'dart:typed_data';

import 'cache.dart';
import 'dir_provider.dart';

/// File-name suffix used for every cached thumbnail.
///
/// 每个缓存缩略图文件使用的扩展名后缀。
const String _kSuffix = '.thumb';

/// A [VmThumbCache] backed by a directory of files, evicting by total bytes
/// with least-recently-touched-first ordering.
///
/// Recency is the file's last-modified stamp: [write] sets it implicitly and
/// [read] refreshes it, so a thumbnail that keeps getting re-read survives.
/// Every filesystem error is swallowed — a broken cache directory must degrade
/// the preview feature, never crash playback.
///
/// 以文件目录为后端的 [VmThumbCache]，按总字节数淘汰，最久未触碰者先删。
///
/// "最近使用"以文件的 last-modified 时间戳为准：[write] 会隐式更新它，
/// [read] 会主动刷新它，因此反复被读取的缩略图不会被淘汰。所有文件系统错误
/// 都被吞掉——缓存目录坏掉只能让预览功能降级，绝不能让播放崩溃。
class VmDiskThumbCache implements VmThumbCache {
  /// Creates a disk cache rooted at [dir]'s resolved path.
  ///
  /// 创建一个以 [dir] 解析出的路径为根的磁盘缓存。
  ///
  /// - [dir]: directory resolver / 目录解析器
  /// - [maxBytes]: total byte budget; `0` or negative disables caching /
  ///   总字节预算；为 `0` 或负数时禁用缓存
  VmDiskThumbCache({required this.dir, this.maxBytes = 64 * 1024 * 1024});

  /// Resolver for the cache directory.
  ///
  /// 缓存目录的解析器。
  final VmThumbDirProvider dir;

  /// Total byte budget across all cached files.
  ///
  /// 所有缓存文件加起来的字节预算。
  final int maxBytes;

  /// Memoised, already-created cache directory, or null before first use or
  /// when the directory could not be created.
  ///
  /// 已创建并缓存下来的目录对象；首次使用前或目录创建失败时为 null。
  Directory? _resolved;

  /// Resolves and creates the cache directory once, returning null when the
  /// filesystem refuses.
  ///
  /// 一次性解析并创建缓存目录；文件系统拒绝时返回 null。
  ///
  /// Returns the directory, or null when unusable.
  ///
  /// 返回目录对象；不可用时返回 null。
  Future<Directory?> _dir() async {
    final cached = _resolved;
    if (cached != null) return cached;
    try {
      final d = Directory(await dir.resolve());
      if (!await d.exists()) await d.create(recursive: true);
      _resolved = d;
      return d;
    } on FileSystemException {
      return null;
    }
  }

  /// Maps [key] to its backing file inside [d].
  ///
  /// 把 [key] 映射为 [d] 目录下对应的文件。
  ///
  /// - [d]: the cache directory / 缓存目录
  /// - [key]: the cache key / 缓存 key
  ///
  /// Returns the backing file handle.
  ///
  /// 返回对应的文件句柄。
  File _file(Directory d, String key) => File('${d.path}${Platform.pathSeparator}$key$_kSuffix');

  /// Lists every cached file, newest-touched last; empty when unusable.
  ///
  /// 列出全部缓存文件，最近被触碰的排在最后；不可用时返回空列表。
  ///
  /// Returns the sorted file list.
  ///
  /// 返回排序后的文件列表。
  Future<List<File>> _entries() async {
    final d = await _dir();
    if (d == null) return const <File>[];
    try {
      final files = (await d.list().toList())
          .whereType<File>()
          .where((f) => f.path.endsWith(_kSuffix))
          .toList();
      files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      return files;
    } on FileSystemException {
      return const <File>[];
    }
  }

  /// Sums the byte size of every cached file.
  ///
  /// 统计全部缓存文件的字节总和。
  ///
  /// Returns the total size in bytes; `0` when the cache is unusable.
  ///
  /// 返回总字节数；缓存不可用时返回 `0`。
  Future<int> totalBytes() async {
    var total = 0;
    for (final f in await _entries()) {
      try {
        total += await f.length();
      } on FileSystemException {
        continue;
      }
    }
    return total;
  }

  /// Deletes least-recently-touched files until the total fits [maxBytes].
  ///
  /// 从最久未触碰的文件开始删，直到总量落回 [maxBytes] 以内。
  Future<void> evict() async {
    final files = await _entries();
    var total = 0;
    final sizes = <File, int>{};
    for (final f in files) {
      try {
        final len = await f.length();
        sizes[f] = len;
        total += len;
      } on FileSystemException {
        continue;
      }
    }
    for (final f in files) {
      if (total <= maxBytes) break;
      try {
        await f.delete();
        total -= sizes[f] ?? 0;
      } on FileSystemException {
        continue;
      }
    }
  }

  @override
  Uint8List? peek(String key) => null;

  @override
  Future<Uint8List?> read(String key) async {
    final d = await _dir();
    if (d == null) return null;
    final f = _file(d, key);
    try {
      if (!await f.exists()) return null;
      final bytes = await f.readAsBytes();
      await f.setLastModified(DateTime.now());
      return bytes;
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (maxBytes <= 0) return;
    final d = await _dir();
    if (d == null) return;
    try {
      await _file(d, key).writeAsBytes(bytes, flush: true);
    } on FileSystemException {
      return;
    }
    await evict();
  }

  @override
  Future<void> clear() async {
    for (final f in await _entries()) {
      try {
        await f.delete();
      } on FileSystemException {
        continue;
      }
    }
  }

  @override
  Future<void> dispose() async {}
}
```

- [ ] **Step 6: 实现 `lib/src/platform_impl/thumb_dir_impl.dart`**

```dart
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/preview/dir_provider.dart';

/// The default [VmThumbDirProvider]: a named folder under the platform
/// temporary directory, e.g. `<tmp>/videoman_thumbs`.
///
/// Lives outside `lib/src/core/**` because `path_provider` is a Flutter
/// plugin and the core layer must stay plugin-free.
///
/// 默认的 [VmThumbDirProvider]：平台临时目录下的一个命名文件夹，
/// 例如 `<tmp>/videoman_thumbs`。
///
/// 放在 `lib/src/core/**` 之外，因为 `path_provider` 是 Flutter 插件，
/// core 层必须与插件解耦。
class TempThumbDirProvider implements VmThumbDirProvider {
  /// Creates a provider rooted at the temporary directory.
  ///
  /// 创建一个以临时目录为根的 provider。
  ///
  /// - [folderName]: sub-folder name under the temp directory /
  ///   临时目录下的子文件夹名
  const TempThumbDirProvider({this.folderName = 'videoman_thumbs'});

  /// Sub-folder name under the platform temporary directory.
  ///
  /// 平台临时目录下的子文件夹名。
  final String folderName;

  @override
  Future<String> resolve() async {
    final tmp = await getTemporaryDirectory();
    return '${tmp.path}${Platform.pathSeparator}$folderName';
  }
}
```

- [ ] **Step 7: barrel 增补导出**

`lib/videoman.dart` 在 `export 'src/core/preview/cache.dart';` 之后按字母序插入：

```dart
export 'src/core/preview/dir_provider.dart';
export 'src/core/preview/disk_cache.dart';
```

并在文件末尾（`export 'src/ui/slots/tree.dart';` 之后）追加：

```dart
export 'src/platform_impl/thumb_dir_impl.dart';
```

- [ ] **Step 8: 跑测试与分析**

Run: `flutter test test/core/preview/ && flutter analyze`
Expected: disk_cache 9 项 + 前序 28 项全 PASS，analyze 0 issues。
`test/core/purity_test.dart` 仍 PASS（`disk_cache.dart` 只用 `dart:io`，没引 flutter）。

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat(videoman): add byte-LRU disk thumbnail cache with pluggable directory port"
```

---

## Task 6: 两级缓存

DESIGN §7.1「内存命中 → 同帧同步返回；磁盘命中 → 异步读 → 显示 + 回填内存」。

**Files:**
- Create: `lib/src/core/preview/two_level_cache.dart`
- Modify: `lib/videoman.dart`
- Test: `test/core/preview/two_level_cache_test.dart`

**Interfaces:**
- Consumes: `VmThumbCache`, `VmMemoryThumbCache`（Task 4）、`VmDiskThumbCache`（Task 5）
- Produces: `class VmTwoLevelCache implements VmThumbCache { VmTwoLevelCache({required VmThumbCache memory, required VmThumbCache disk}); final VmThumbCache memory; final VmThumbCache disk; }`

- [ ] **Step 1: 写失败测试 `test/core/preview/two_level_cache_test.dart`**

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/preview/cache.dart';
import 'package:videoman/src/core/preview/two_level_cache.dart';

/// Builds [n] filler bytes so tests can tell payloads apart by length.
///
/// 造 [n] 个填充字节，让测试可以按长度区分不同负载。
Uint8List _bytes(int n) => Uint8List.fromList(List<int>.filled(n, n & 0xFF));

/// A recording [VmThumbCache] standing in for the slow (disk) level.
///
/// 记录调用的 [VmThumbCache]，用于替身"慢速（磁盘）"层。
class _RecordingCache implements VmThumbCache {
  /// Stored entries.
  ///
  /// 已存储的条目。
  final Map<String, Uint8List> store = <String, Uint8List>{};

  /// Ordered method names invoked on this fake.
  ///
  /// 在该替身上被调用的方法名有序列表。
  final List<String> calls = <String>[];

  @override
  Uint8List? peek(String key) {
    calls.add('peek:$key');
    return null;
  }

  @override
  Future<Uint8List?> read(String key) async {
    calls.add('read:$key');
    return store[key];
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    calls.add('write:$key');
    store[key] = bytes;
  }

  @override
  Future<void> clear() async {
    calls.add('clear');
    store.clear();
  }

  @override
  Future<void> dispose() async => calls.add('dispose');
}

void main() {
  late VmMemoryThumbCache memory;
  late _RecordingCache disk;
  late VmTwoLevelCache cache;

  setUp(() {
    memory = VmMemoryThumbCache(maxEntries: 2);
    disk = _RecordingCache();
    cache = VmTwoLevelCache(memory: memory, disk: disk);
  });

  test('write goes into both levels', () async {
    await cache.write('k', _bytes(4));
    expect(memory.peek('k'), _bytes(4));
    expect(disk.store['k'], _bytes(4));
  });

  test('peek answers from memory without touching disk', () async {
    await cache.write('k', _bytes(4));
    disk.calls.clear();
    expect(cache.peek('k'), _bytes(4));
    expect(disk.calls, isEmpty);
  });

  test('peek misses when only disk holds the entry', () async {
    await disk.write('k', _bytes(4));
    disk.calls.clear();
    expect(cache.peek('k'), isNull);
    expect(disk.calls, isEmpty);
  });

  test('read falls through to disk and back-fills memory', () async {
    await disk.write('k', _bytes(4));
    expect(await cache.read('k'), _bytes(4));
    expect(memory.peek('k'), _bytes(4));
  });

  test('read does not hit disk again once memory holds the entry', () async {
    await disk.write('k', _bytes(4));
    await cache.read('k');
    disk.calls.clear();
    expect(await cache.read('k'), _bytes(4));
    expect(disk.calls, isEmpty);
  });

  test('read returns null when neither level has the key', () async {
    expect(await cache.read('nope'), isNull);
    expect(disk.calls, contains('read:nope'));
  });

  test('clear and dispose cascade to both levels', () async {
    await cache.write('k', _bytes(4));
    await cache.clear();
    expect(memory.peek('k'), isNull);
    expect(disk.store, isEmpty);
    await cache.dispose();
    expect(disk.calls, contains('dispose'));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/preview/two_level_cache_test.dart`
Expected: FAIL — `Error when reading 'lib/src/core/preview/two_level_cache.dart': No such file or directory`

- [ ] **Step 3: 实现 `lib/src/core/preview/two_level_cache.dart`**

```dart
import 'dart:typed_data';

import 'cache.dart';

/// Composes a fast synchronous level (memory) over a slow persistent one
/// (disk).
///
/// [peek] only ever consults [memory], so a scrub that lands on an already
/// resident bucket renders in the same frame. [read] falls through to [disk]
/// and back-fills [memory] so the next scrub over the same bucket is
/// instantaneous. [write] fans out to both levels.
///
/// 把一个同步的快速层（内存）叠加在慢速持久层（磁盘）之上。
///
/// [peek] 只查 [memory]，因此拖到已驻留的桶时可在同一帧渲染出来。[read] 会
/// 下探到 [disk] 并回填 [memory]，让下次拖到同一个桶时瞬时命中。[write] 同时
/// 写入两层。
class VmTwoLevelCache implements VmThumbCache {
  /// Creates a two-level cache over [memory] and [disk].
  ///
  /// 用 [memory] 与 [disk] 组成两级缓存。
  ///
  /// - [memory]: the fast, synchronously peekable level / 可同步 peek 的快速层
  /// - [disk]: the slow, persistent level / 慢速持久层
  VmTwoLevelCache({required this.memory, required this.disk});

  /// The fast level; must answer [VmThumbCache.peek] without I/O.
  ///
  /// 快速层；其 [VmThumbCache.peek] 必须不做 I/O。
  final VmThumbCache memory;

  /// The slow, persistent level.
  ///
  /// 慢速持久层。
  final VmThumbCache disk;

  @override
  Uint8List? peek(String key) => memory.peek(key);

  @override
  Future<Uint8List?> read(String key) async {
    final hit = memory.peek(key);
    if (hit != null) return hit;
    final fromDisk = await disk.read(key);
    if (fromDisk != null) await memory.write(key, fromDisk);
    return fromDisk;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    await memory.write(key, bytes);
    await disk.write(key, bytes);
  }

  @override
  Future<void> clear() async {
    await memory.clear();
    await disk.clear();
  }

  @override
  Future<void> dispose() async {
    await memory.dispose();
    await disk.dispose();
  }
}
```

- [ ] **Step 4: barrel 增补导出**

`lib/videoman.dart` 在 `export 'src/core/preview/models.dart';` 之后插入：

```dart
export 'src/core/preview/two_level_cache.dart';
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/core/preview/two_level_cache_test.dart && flutter analyze`
Expected: 7 项 PASS，analyze 0 issues

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(videoman): compose memory and disk thumbnail caches into a two-level cache"
```

---

## Task 7: 网络策略端口与 `connectivity_plus` 实现

DESIGN §7.5 + §6.1「网络限制 | `wifiOnly` | `network` | `probe`（`VmNetProbe`）」。
`VmPreviewNetwork` 枚举与端口一起放在 `net_probe.dart`（DESIGN §7.5 就是这么排的），Task 10 的
`VmPreviewConfig` 直接引用，避免配置与端口互相依赖。

**Files:**
- Create: `lib/src/core/preview/net_probe.dart`, `lib/src/platform_impl/net_probe_impl.dart`
- Modify: `pubspec.yaml`, `lib/videoman.dart`
- Test: `test/core/preview/net_probe_test.dart`, `test/platform_impl/net_probe_impl_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum VmPreviewNetwork { wifiOnly, always, never }`
  - `abstract class VmNetProbe { Future<bool> allowHeavy(); Stream<bool> get changes; Future<void> dispose(); }`
  - `class AlwaysAllowNetProbe implements VmNetProbe`
  - `Future<bool> previewAllowedOn(VmPreviewNetwork policy, VmNetProbe probe)`
  - `class ConnectivityNetProbe implements VmNetProbe { ConnectivityNetProbe({Connectivity? connectivity}); static bool allowsHeavy(List<ConnectivityResult> results); }`（`platform_impl`）

- [ ] **Step 1: 加依赖**

`pubspec.yaml` 的 `dependencies:` 段内，`flutter:` 之后、`media_kit:` 之前按字母序插入：

```yaml
  connectivity_plus: ^6.1.5
```

Run: `flutter pub get`
Expected: 解析成功，`pubspec.lock` 出现 `connectivity_plus`

- [ ] **Step 2: 写失败测试 `test/core/preview/net_probe_test.dart`**

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/preview/net_probe.dart';

/// A probe returning a fixed verdict, recording how often it was consulted.
///
/// 返回固定判定结果的探针，并记录被咨询了多少次。
class _FixedProbe implements VmNetProbe {
  /// Creates a probe that always answers [verdict].
  ///
  /// 创建一个恒定回答 [verdict] 的探针。
  _FixedProbe(this.verdict);

  /// The verdict returned by [allowHeavy].
  ///
  /// [allowHeavy] 返回的判定结果。
  final bool verdict;

  /// How many times [allowHeavy] was called.
  ///
  /// [allowHeavy] 被调用的次数。
  int calls = 0;

  /// Backing controller for [changes].
  ///
  /// [changes] 的底层控制器。
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  @override
  Future<bool> allowHeavy() async {
    calls++;
    return verdict;
  }

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  Future<void> dispose() => _changes.close();
}

void main() {
  test('AlwaysAllowNetProbe permits heavy traffic and never errors', () async {
    final p = AlwaysAllowNetProbe();
    expect(await p.allowHeavy(), isTrue);
    expect(await p.changes.first, isTrue);
    await p.dispose();
  });

  test('the never policy blocks without consulting the probe', () async {
    final p = _FixedProbe(true);
    expect(await previewAllowedOn(VmPreviewNetwork.never, p), isFalse);
    expect(p.calls, 0);
    await p.dispose();
  });

  test('the always policy permits without consulting the probe', () async {
    final p = _FixedProbe(false);
    expect(await previewAllowedOn(VmPreviewNetwork.always, p), isTrue);
    expect(p.calls, 0);
    await p.dispose();
  });

  test('the wifiOnly policy defers to the probe', () async {
    final allow = _FixedProbe(true);
    final deny = _FixedProbe(false);
    expect(await previewAllowedOn(VmPreviewNetwork.wifiOnly, allow), isTrue);
    expect(await previewAllowedOn(VmPreviewNetwork.wifiOnly, deny), isFalse);
    expect(allow.calls, 1);
    expect(deny.calls, 1);
    await allow.dispose();
    await deny.dispose();
  });

  test('a throwing probe degrades to allowed rather than breaking playback', () async {
    expect(await previewAllowedOn(VmPreviewNetwork.wifiOnly, _ThrowingProbe()), isTrue);
  });
}

/// A probe whose [allowHeavy] always throws, standing in for a broken
/// connectivity plugin.
///
/// [allowHeavy] 恒抛异常的探针，用于模拟坏掉的连通性插件。
class _ThrowingProbe implements VmNetProbe {
  @override
  Future<bool> allowHeavy() async => throw StateError('plugin missing');

  @override
  Stream<bool> get changes => const Stream<bool>.empty();

  @override
  Future<void> dispose() async {}
}
```

- [ ] **Step 3: 写失败测试 `test/platform_impl/net_probe_impl_test.dart`**

```dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/platform_impl/net_probe_impl.dart';

void main() {
  test('wifi, ethernet and vpn allow heavy traffic', () {
    expect(ConnectivityNetProbe.allowsHeavy([ConnectivityResult.wifi]), isTrue);
    expect(ConnectivityNetProbe.allowsHeavy([ConnectivityResult.ethernet]), isTrue);
    expect(ConnectivityNetProbe.allowsHeavy([ConnectivityResult.vpn]), isTrue);
  });

  test('a mobile-only connection blocks heavy traffic', () {
    expect(ConnectivityNetProbe.allowsHeavy([ConnectivityResult.mobile]), isFalse);
  });

  test('mobile alongside wifi still allows heavy traffic', () {
    expect(
      ConnectivityNetProbe.allowsHeavy([ConnectivityResult.mobile, ConnectivityResult.wifi]),
      isTrue,
    );
  });

  test('unknown, none and empty results allow rather than false-block desktop', () {
    expect(ConnectivityNetProbe.allowsHeavy([ConnectivityResult.other]), isTrue);
    expect(ConnectivityNetProbe.allowsHeavy([ConnectivityResult.none]), isTrue);
    expect(ConnectivityNetProbe.allowsHeavy(const <ConnectivityResult>[]), isTrue);
  });
}
```

- [ ] **Step 4: 跑测试确认失败**

Run: `flutter test test/core/preview/net_probe_test.dart test/platform_impl/net_probe_impl_test.dart`
Expected: FAIL — `Error when reading 'lib/src/core/preview/net_probe.dart': No such file or directory`

- [ ] **Step 5: 实现 `lib/src/core/preview/net_probe.dart`**

```dart
/// When scrub-preview thumbnails are allowed to use the network.
///
/// 何时允许拖动预览缩略图走网络。
enum VmPreviewNetwork {
  /// Only on connections considered unmetered; the default.
  ///
  /// 仅在被视为不计流量的连接上启用；默认值。
  wifiOnly,

  /// On any connection.
  ///
  /// 任意连接下都启用。
  always,

  /// Never — disables networked thumbnail sources entirely.
  ///
  /// 永不启用——完全关闭需要联网的缩略图来源。
  never,
}

/// Reports whether the current connection is suitable for bandwidth-heavy,
/// non-essential traffic such as sprite sheets and frame extraction.
///
/// 判断当前连接是否适合承载雪碧图、抽帧这类"非必要且吃带宽"的流量。
abstract class VmNetProbe {
  /// Whether heavy, optional traffic is currently acceptable.
  ///
  /// 当前是否可以接受重量级的可选流量。
  ///
  /// Returns true when heavy traffic is allowed.
  ///
  /// 允许重量级流量时返回 true。
  Future<bool> allowHeavy();

  /// Emits a new verdict whenever connectivity changes.
  ///
  /// 连通性变化时推送新的判定结果。
  Stream<bool> get changes;

  /// Releases any listeners this probe holds.
  ///
  /// 释放该探针持有的监听。
  Future<void> dispose();
}

/// A [VmNetProbe] that always permits heavy traffic.
///
/// The core-layer default so a host that never wires a real probe still gets
/// working previews; the plugin-backed probe lives in
/// `lib/src/platform_impl/net_probe_impl.dart`.
///
/// 恒定允许重量级流量的 [VmNetProbe]。
///
/// 作为 core 层默认值，让未接入真实探针的宿主也能用上预览；基于插件的探针放在
/// `lib/src/platform_impl/net_probe_impl.dart`。
class AlwaysAllowNetProbe implements VmNetProbe {
  @override
  Future<bool> allowHeavy() async => true;

  @override
  Stream<bool> get changes => Stream<bool>.value(true);

  @override
  Future<void> dispose() async {}
}

/// Resolves [policy] against [probe] into a single allow/deny answer.
///
/// A probe that throws is treated as "allowed": a broken connectivity plugin
/// must degrade to a working preview, not silently disable the feature.
///
/// 把 [policy] 与 [probe] 归结为一个允许/拒绝的答案。
///
/// 探针抛异常时按"允许"处理：连通性插件坏掉只能导致预览照常工作，而不能悄悄
/// 把功能关掉。
///
/// - [policy]: the configured network policy / 配置的网络策略
/// - [probe]: the connectivity probe to consult under [VmPreviewNetwork.wifiOnly] /
///   在 [VmPreviewNetwork.wifiOnly] 下要咨询的连通性探针
///
/// Returns whether networked preview sources may run.
///
/// 返回是否允许运行需要联网的预览来源。
Future<bool> previewAllowedOn(VmPreviewNetwork policy, VmNetProbe probe) async {
  switch (policy) {
    case VmPreviewNetwork.never:
      return false;
    case VmPreviewNetwork.always:
      return true;
    case VmPreviewNetwork.wifiOnly:
      try {
        return await probe.allowHeavy();
      } on Object {
        return true;
      }
  }
}
```

- [ ] **Step 6: 实现 `lib/src/platform_impl/net_probe_impl.dart`**

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

import '../core/preview/net_probe.dart';

/// The default [VmNetProbe]: treats wifi/ethernet/vpn as unmetered and a
/// mobile-only connection as metered.
///
/// Anything else — `none`, `other`, an empty result list, or a platform the
/// plugin cannot classify — is allowed, so desktops are never false-blocked
/// (DESIGN §11: "未知一律放行；桌面视为允许").
///
/// 默认的 [VmNetProbe]：把 wifi/以太网/VPN 视为不计流量，把仅蜂窝的连接视为
/// 计流量。
///
/// 其余情况——`none`、`other`、空结果列表，或插件无法分类的平台——一律放行，
/// 避免误伤桌面端（DESIGN §11：「未知一律放行；桌面视为允许」）。
class ConnectivityNetProbe implements VmNetProbe {
  /// Creates a probe over [connectivity], defaulting to a new `Connectivity()`.
  ///
  /// 基于 [connectivity] 创建探针；省略时新建一个 `Connectivity()`。
  ///
  /// - [connectivity]: injectable connectivity_plus facade / 可注入的
  ///   connectivity_plus 门面
  ConnectivityNetProbe({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  /// The connectivity_plus facade this probe reads from.
  ///
  /// 该探针读取的 connectivity_plus 门面。
  final Connectivity _connectivity;

  /// Classifies a connectivity_plus result list as unmetered (true) or
  /// metered (false).
  ///
  /// 把 connectivity_plus 的结果列表分类为不计流量（true）或计流量（false）。
  ///
  /// - [results]: the reported active connection types / 上报的当前连接类型
  ///
  /// Returns whether heavy traffic is acceptable.
  ///
  /// 返回是否可以接受重量级流量。
  static bool allowsHeavy(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet) ||
        results.contains(ConnectivityResult.vpn)) {
      return true;
    }
    if (results.contains(ConnectivityResult.mobile)) return false;
    return true;
  }

  @override
  Future<bool> allowHeavy() async => allowsHeavy(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get changes => _connectivity.onConnectivityChanged.map(allowsHeavy);

  @override
  Future<void> dispose() async {}
}
```

- [ ] **Step 7: barrel 增补导出**

`lib/videoman.dart` 在 `export 'src/core/preview/models.dart';` 之后插入：

```dart
export 'src/core/preview/net_probe.dart';
```

并在 `export 'src/platform_impl/thumb_dir_impl.dart';` 之前插入：

```dart
export 'src/platform_impl/net_probe_impl.dart';
```

- [ ] **Step 8: 跑测试与分析**

Run: `flutter test && flutter analyze`
Expected: net_probe 5 项 + net_probe_impl 4 项全 PASS，累计 147 项全绿，analyze 0 issues。
`purity_test.dart` 仍 PASS（`connectivity_plus` 只出现在 `platform_impl/`）。

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat(videoman): add preview network policy port with connectivity_plus probe"
```

---

## Task 8: HTTP 取数端口、缩略图来源抽象与 VTT 来源

DESIGN §7.1 的第一条来源 + §6.1「缩略图来源 | `[vtt, mpvExtract]` | `sources` 有序表 | 自定义
`VmThumbSource`」「VTT 地址 | 约定 `<video>.vtt` | `vttUrl` | `vttUrlResolver`」。
HTTP 用 `dart:io` 的 `HttpClient`（不引 `package:http`），并藏在 `VmHttpFetcher` 端口后面以便单测。

**Files:**
- Create: `lib/src/core/preview/fetcher.dart`, `lib/src/core/preview/source.dart`, `lib/src/core/preview/vtt_source.dart`
- Modify: `lib/videoman.dart`
- Test: `test/core/preview/vtt_source_test.dart`

**Interfaces:**
- Consumes: `VmSource`（既有）、`VmThumb`/`VmThumbIndex`（Task 2）、`parseVttThumbs`（Task 3）
- Produces:
  - `abstract class VmHttpFetcher { Future<Uint8List?> get(Uri url); Future<void> close(); }`
  - `class IoHttpFetcher implements VmHttpFetcher { IoHttpFetcher({Duration timeout = const Duration(seconds: 10)}); }`
  - `abstract class VmThumbSource { String get name; Future<VmThumb?> thumbAt(VmSource source, Duration bucket); Future<void> reset(); Future<void> dispose(); }`
  - `typedef VmVttUrlResolver = Uri? Function(VmSource source);`
  - `Uri? defaultVttUrl(VmSource source)`
  - `class VmVttThumbSource implements VmThumbSource { VmVttThumbSource({required VmHttpFetcher fetcher, VmVttUrlResolver resolveUrl = defaultVttUrl, int maxSprites = 4}); }`

- [ ] **Step 1: 写失败测试 `test/core/preview/vtt_source_test.dart`**

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/preview/fetcher.dart';
import 'package:videoman/src/core/preview/models.dart';
import 'package:videoman/src/core/preview/vtt_source.dart';

/// A [VmHttpFetcher] serving canned responses and recording every URL asked.
///
/// 返回预置响应并记录每次请求 URL 的 [VmHttpFetcher]。
class _FakeFetcher implements VmHttpFetcher {
  /// Canned responses, keyed by URL.
  ///
  /// 按 URL 存放的预置响应。
  final Map<String, Uint8List> responses = <String, Uint8List>{};

  /// Every URL requested, in order.
  ///
  /// 按顺序记录的每个被请求 URL。
  final List<String> requested = <String>[];

  /// Registers [body] as the response for [url].
  ///
  /// 把 [body] 注册为 [url] 的响应。
  ///
  /// - [url]: the URL to serve / 要服务的 URL
  /// - [body]: response body as text / 文本形式的响应体
  void serveText(String url, String body) =>
      responses[url] = Uint8List.fromList(utf8.encode(body));

  /// Registers [bytes] as the response for [url].
  ///
  /// 把 [bytes] 注册为 [url] 的响应。
  ///
  /// - [url]: the URL to serve / 要服务的 URL
  /// - [bytes]: raw response body / 原始响应体
  void serveBytes(String url, List<int> bytes) =>
      responses[url] = Uint8List.fromList(bytes);

  @override
  Future<Uint8List?> get(Uri url) async {
    requested.add(url.toString());
    return responses[url.toString()];
  }

  @override
  Future<void> close() async {}
}

/// The VTT fixture used across these tests.
///
/// 本组测试共用的 VTT 样例。
const String _vtt = 'WEBVTT\n'
    '\n'
    '00:00:00.000 --> 00:00:10.000\n'
    'sprite-0.jpg#xywh=0,0,160,90\n'
    '\n'
    '00:00:10.000 --> 00:00:20.000\n'
    'sprite-0.jpg#xywh=160,0,160,90\n';

void main() {
  const src = VmSource('https://host/media/a.mp4');

  test('defaultVttUrl appends .vtt to the media path', () {
    expect(defaultVttUrl(src), Uri.parse('https://host/media/a.mp4.vtt'));
    expect(
      defaultVttUrl(const VmSource('https://host/l.m3u8?token=1')),
      Uri.parse('https://host/l.m3u8.vtt?token=1'),
    );
    expect(defaultVttUrl(const VmSource('')), isNull);
  });

  test('fetches the vtt once, then serves thumbs with the right crop', () async {
    final f = _FakeFetcher()
      ..serveText('https://host/media/a.mp4.vtt', _vtt)
      ..serveBytes('https://host/media/sprite-0.jpg', [1, 2, 3]);
    final s = VmVttThumbSource(fetcher: f);

    final t0 = await s.thumbAt(src, const Duration(seconds: 0));
    final t1 = await s.thumbAt(src, const Duration(seconds: 10));

    expect(t0!.crop, const VmThumbCrop(x: 0, y: 0, w: 160, h: 90));
    expect(t0.at, Duration.zero);
    expect(t0.bytes, [1, 2, 3]);
    expect(t1!.crop, const VmThumbCrop(x: 160, y: 0, w: 160, h: 90));
    expect(
      f.requested.where((u) => u.endsWith('.vtt')).length,
      1,
      reason: 'vtt should be fetched exactly once',
    );
    expect(
      f.requested.where((u) => u.endsWith('sprite-0.jpg')).length,
      1,
      reason: 'the sprite sheet should be fetched exactly once',
    );
    await s.dispose();
  });

  test('a missing vtt makes the source permanently unavailable for that media', () async {
    final f = _FakeFetcher();
    final s = VmVttThumbSource(fetcher: f);
    expect(await s.thumbAt(src, Duration.zero), isNull);
    expect(await s.thumbAt(src, const Duration(seconds: 10)), isNull);
    expect(f.requested.length, 1, reason: 'a failed vtt fetch must not be retried per scrub');
    await s.dispose();
  });

  test('an empty vtt is treated as unavailable', () async {
    final f = _FakeFetcher()..serveText('https://host/media/a.mp4.vtt', 'WEBVTT\n');
    final s = VmVttThumbSource(fetcher: f);
    expect(await s.thumbAt(src, Duration.zero), isNull);
    await s.dispose();
  });

  test('a missing sprite yields null without poisoning the index', () async {
    final f = _FakeFetcher()..serveText('https://host/media/a.mp4.vtt', _vtt);
    final s = VmVttThumbSource(fetcher: f);
    expect(await s.thumbAt(src, Duration.zero), isNull);
    f.serveBytes('https://host/media/sprite-0.jpg', [9]);
    expect((await s.thumbAt(src, Duration.zero))!.bytes, [9]);
    await s.dispose();
  });

  test('a custom resolver overrides the .vtt convention', () async {
    final f = _FakeFetcher()
      ..serveText('https://cdn/thumbs.vtt', _vtt)
      ..serveBytes('https://cdn/sprite-0.jpg', [7]);
    final s = VmVttThumbSource(
      fetcher: f,
      resolveUrl: (_) => Uri.parse('https://cdn/thumbs.vtt'),
    );
    expect((await s.thumbAt(src, Duration.zero))!.bytes, [7]);
    await s.dispose();
  });

  test('a resolver returning null disables the source', () async {
    final f = _FakeFetcher();
    final s = VmVttThumbSource(fetcher: f, resolveUrl: (_) => null);
    expect(await s.thumbAt(src, Duration.zero), isNull);
    expect(f.requested, isEmpty);
    await s.dispose();
  });

  test('reset drops the cached index so a new media re-fetches', () async {
    final f = _FakeFetcher()
      ..serveText('https://host/media/a.mp4.vtt', _vtt)
      ..serveBytes('https://host/media/sprite-0.jpg', [1]);
    final s = VmVttThumbSource(fetcher: f);
    await s.thumbAt(src, Duration.zero);
    await s.reset();
    await s.thumbAt(src, Duration.zero);
    expect(f.requested.where((u) => u.endsWith('.vtt')).length, 2);
    await s.dispose();
  });

  test('sprite memoisation is bounded by maxSprites', () async {
    const many = 'WEBVTT\n'
        '\n'
        '00:00:00.000 --> 00:00:10.000\n'
        's0.jpg\n'
        '\n'
        '00:00:10.000 --> 00:00:20.000\n'
        's1.jpg\n';
    final f = _FakeFetcher()
      ..serveText('https://host/media/a.mp4.vtt', many)
      ..serveBytes('https://host/media/s0.jpg', [0])
      ..serveBytes('https://host/media/s1.jpg', [1]);
    final s = VmVttThumbSource(fetcher: f, maxSprites: 1);
    await s.thumbAt(src, Duration.zero);
    await s.thumbAt(src, const Duration(seconds: 10));
    await s.thumbAt(src, Duration.zero);
    expect(f.requested.where((u) => u.endsWith('s0.jpg')).length, 2);
    await s.dispose();
  });

  test('the source reports a stable name for diagnostics', () {
    expect(VmVttThumbSource(fetcher: _FakeFetcher()).name, 'vtt');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/preview/vtt_source_test.dart`
Expected: FAIL — `Error when reading 'lib/src/core/preview/fetcher.dart': No such file or directory`

- [ ] **Step 3: 实现 `lib/src/core/preview/fetcher.dart`**

```dart
import 'dart:io';
import 'dart:typed_data';

/// Fetches small auxiliary assets (WebVTT tracks, sprite sheets) over HTTP.
///
/// A port rather than a direct `HttpClient` call so tests can serve canned
/// bytes and hosts can inject their own auth headers, CDN rewriting or caching
/// HTTP stack.
///
/// 通过 HTTP 拉取小型辅助资源（WebVTT 轨、雪碧图）。
///
/// 之所以做成端口而不是直接调 `HttpClient`：测试可以喂预置字节，宿主也可以
/// 注入自己的鉴权头、CDN 改写或带缓存的 HTTP 栈。
abstract class VmHttpFetcher {
  /// Fetches [url]; returns null on any non-200 response or transport error.
  ///
  /// 拉取 [url]；任何非 200 响应或传输错误都返回 null。
  ///
  /// - [url]: the absolute URL to fetch / 要拉取的绝对 URL
  ///
  /// Returns the response body, or null on failure.
  ///
  /// 返回响应体；失败时返回 null。
  Future<Uint8List?> get(Uri url);

  /// Releases any connections this fetcher holds.
  ///
  /// 释放该 fetcher 持有的连接。
  Future<void> close();
}

/// The default [VmHttpFetcher], built on `dart:io`'s [HttpClient].
///
/// Chosen over `package:http` so preview support adds no new dependency; every
/// failure mode collapses to null so a broken thumbnail track never surfaces
/// as a playback error.
///
/// 默认的 [VmHttpFetcher]，基于 `dart:io` 的 [HttpClient]。
///
/// 相比 `package:http` 选它是为了让预览功能不引入任何新依赖；所有失败路径都
/// 收敛为 null，坏掉的缩略图轨绝不会冒充成播放错误。
class IoHttpFetcher implements VmHttpFetcher {
  /// Creates a fetcher with a per-request [timeout].
  ///
  /// 创建一个每请求超时为 [timeout] 的 fetcher。
  ///
  /// - [timeout]: total per-request deadline / 单次请求的总超时
  IoHttpFetcher({this.timeout = const Duration(seconds: 10)});

  /// Total per-request deadline.
  ///
  /// 单次请求的总超时。
  final Duration timeout;

  /// The lazily created client; null until the first request.
  ///
  /// 惰性创建的客户端；首次请求前为 null。
  HttpClient? _client;

  @override
  Future<Uint8List?> get(Uri url) async {
    final client = _client ??= (HttpClient()..connectionTimeout = timeout);
    try {
      final request = await client.getUrl(url).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final chunks = await response.toList().timeout(timeout);
      final out = <int>[];
      for (final c in chunks) {
        out.addAll(c);
      }
      return Uint8List.fromList(out);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> close() async {
    _client?.close(force: true);
    _client = null;
  }
}
```

- [ ] **Step 4: 实现 `lib/src/core/preview/source.dart`**

```dart
import '../model/source.dart';
import 'models.dart';

/// One strategy for obtaining a preview thumbnail at a given position.
///
/// The preview service walks an ordered list of sources and takes the first
/// non-null answer, so a source signals "I cannot serve this media" simply by
/// returning null. Sources must never throw: a broken thumbnail track degrades
/// the bubble, never playback.
///
/// 在给定位置取得预览缩略图的一种策略。
///
/// 预览服务按顺序遍历来源列表，取第一个非 null 的结果；因此来源只要返回 null
/// 即表示"我无法服务该媒体"。来源不得抛异常：坏掉的缩略图轨只能让气泡降级，
/// 绝不能影响播放。
abstract class VmThumbSource {
  /// Stable identifier used in diagnostics and tests, e.g. `vtt`.
  ///
  /// 用于诊断与测试的稳定标识，例如 `vtt`。
  String get name;

  /// Produces the thumbnail covering [bucket] of [source].
  ///
  /// 产出 [source] 中覆盖 [bucket] 的缩略图。
  ///
  /// - [source]: the media being previewed / 正在预览的媒体
  /// - [bucket]: bucket-aligned position / 桶对齐位置
  ///
  /// Returns the thumbnail, or null when this source cannot serve it.
  ///
  /// 返回缩略图；本来源无法服务时返回 null。
  Future<VmThumb?> thumbAt(VmSource source, Duration bucket);

  /// Drops per-media state so the next [thumbAt] starts fresh; called when the
  /// player opens a different source.
  ///
  /// 丢弃与当前媒体相关的状态，让下次 [thumbAt] 从头开始；播放器打开新源时调用。
  Future<void> reset();

  /// Releases all resources held by this source.
  ///
  /// 释放该来源持有的全部资源。
  Future<void> dispose();
}
```

- [ ] **Step 5: 实现 `lib/src/core/preview/vtt_source.dart`**

```dart
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../model/source.dart';
import 'fetcher.dart';
import 'models.dart';
import 'source.dart';
import 'vtt.dart';

/// Strategy for locating a media's WebVTT thumbnail track.
///
/// 定位某个媒体的 WebVTT 缩略图轨的策略。
///
/// - [source]: the media being previewed / 正在预览的媒体
///
/// Returns the track URL, or null to disable the VTT source for this media.
///
/// 返回该轨的 URL；返回 null 表示对该媒体禁用 VTT 来源。
typedef VmVttUrlResolver = Uri? Function(VmSource source);

/// The conventional thumbnail track location: the media URL with `.vtt`
/// appended to its path, query and fragment preserved.
///
/// 约定的缩略图轨位置：在媒体 URL 的路径后追加 `.vtt`，保留 query 与 fragment。
///
/// - [source]: the media being previewed / 正在预览的媒体
///
/// Returns the derived URL, or null when the media URI has no usable path.
///
/// 返回推导出的 URL；媒体 URI 没有可用路径时返回 null。
Uri? defaultVttUrl(VmSource source) {
  final u = Uri.tryParse(source.uri);
  if (u == null || u.path.isEmpty) return null;
  return u.replace(path: '${u.path}.vtt');
}

/// A [VmThumbSource] backed by a server-provided WebVTT thumbnail track and
/// its sprite sheets.
///
/// The track is fetched once per media and memoised, including the negative
/// result: a 404 must not trigger a fetch on every scrub tick. Sprite sheets
/// are memoised too, bounded by `maxSprites` in least-recently-used order.
///
/// 基于服务端提供的 WebVTT 缩略图轨及其雪碧图的 [VmThumbSource]。
///
/// 每个媒体只拉取一次轨并记忆结果——包括失败结果：404 不能让每次拖动 tick 都
/// 重新发请求。雪碧图同样被记忆，按最近最少使用顺序、以 `maxSprites` 为上限。
class VmVttThumbSource implements VmThumbSource {
  /// Creates a VTT-backed thumbnail source.
  ///
  /// 创建基于 VTT 的缩略图来源。
  ///
  /// - [fetcher]: HTTP port used for the track and sprites / 拉取轨与雪碧图的
  ///   HTTP 端口
  /// - [resolveUrl]: strategy locating the track, defaults to [defaultVttUrl] /
  ///   定位轨的策略，默认为 [defaultVttUrl]
  /// - [maxSprites]: how many sprite sheets stay memoised / 最多记忆多少张雪碧图
  VmVttThumbSource({
    required this.fetcher,
    this.resolveUrl = defaultVttUrl,
    this.maxSprites = 4,
  });

  /// HTTP port used for the track and its sprite sheets.
  ///
  /// 拉取轨及其雪碧图所用的 HTTP 端口。
  final VmHttpFetcher fetcher;

  /// Strategy locating the WebVTT track for a media.
  ///
  /// 为某个媒体定位 WebVTT 轨的策略。
  final VmVttUrlResolver resolveUrl;

  /// Ceiling on memoised sprite sheets.
  ///
  /// 记忆雪碧图的数量上限。
  final int maxSprites;

  /// The parsed track for the current media, or null before the first fetch.
  ///
  /// 当前媒体已解析的轨；首次拉取前为 null。
  VmThumbIndex? _index;

  /// Whether resolving/fetching/parsing the track already failed for the
  /// current media, so it must not be retried on every scrub.
  ///
  /// 当前媒体的轨是否已在解析/拉取/定位环节失败过，避免每次拖动都重试。
  bool _unavailable = false;

  /// Memoised sprite sheets in least-recently-used-first order.
  ///
  /// 按"最久未使用在前"顺序记忆的雪碧图。
  final LinkedHashMap<String, Uint8List> _sprites = LinkedHashMap<String, Uint8List>();

  @override
  String get name => 'vtt';

  /// Fetches and parses the track once per media.
  ///
  /// 每个媒体只拉取并解析一次轨。
  ///
  /// - [source]: the media being previewed / 正在预览的媒体
  ///
  /// Returns the parsed index, or null when unavailable.
  ///
  /// 返回解析出的索引；不可用时返回 null。
  Future<VmThumbIndex?> _ensureIndex(VmSource source) async {
    if (_unavailable) return null;
    final cached = _index;
    if (cached != null) return cached;

    final url = resolveUrl(source);
    if (url == null) {
      _unavailable = true;
      return null;
    }
    final bytes = await fetcher.get(url);
    if (bytes == null) {
      _unavailable = true;
      return null;
    }
    late final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: true);
    } on FormatException {
      _unavailable = true;
      return null;
    }
    final index = parseVttThumbs(text, base: url);
    if (index.isEmpty) {
      _unavailable = true;
      return null;
    }
    _index = index;
    return index;
  }

  /// Fetches [url]'s sprite sheet, memoising it under an LRU bound.
  ///
  /// 拉取 [url] 对应的雪碧图，并在 LRU 上限内记忆之。
  ///
  /// - [url]: the sprite sheet URL / 雪碧图 URL
  ///
  /// Returns the sheet bytes, or null when the fetch failed.
  ///
  /// 返回雪碧图字节；拉取失败时返回 null。
  Future<Uint8List?> _sprite(Uri url) async {
    final key = url.toString();
    final hit = _sprites.remove(key);
    if (hit != null) {
      _sprites[key] = hit;
      return hit;
    }
    final bytes = await fetcher.get(url);
    if (bytes == null) return null;
    if (maxSprites > 0) {
      _sprites[key] = bytes;
      while (_sprites.length > maxSprites) {
        _sprites.remove(_sprites.keys.first);
      }
    }
    return bytes;
  }

  @override
  Future<VmThumb?> thumbAt(VmSource source, Duration bucket) async {
    final index = await _ensureIndex(source);
    if (index == null) return null;
    final cue = index.cueAt(bucket);
    if (cue == null) return null;
    final bytes = await _sprite(cue.image);
    if (bytes == null) return null;
    return VmThumb(at: bucket, bytes: bytes, crop: cue.crop);
  }

  @override
  Future<void> reset() async {
    _index = null;
    _unavailable = false;
    _sprites.clear();
  }

  @override
  Future<void> dispose() async {
    await reset();
    await fetcher.close();
  }
}
```

- [ ] **Step 6: barrel 增补导出**

`lib/videoman.dart` 在 `export 'src/core/preview/disk_cache.dart';` 之后按字母序插入：

```dart
export 'src/core/preview/fetcher.dart';
```

并在 `export 'src/core/preview/net_probe.dart';` 之后插入：

```dart
export 'src/core/preview/source.dart';
export 'src/core/preview/vtt_source.dart';
```

- [ ] **Step 7: 跑测试确认通过**

Run: `flutter test test/core/preview/vtt_source_test.dart && flutter analyze`
Expected: 10 项 PASS，analyze 0 issues

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(videoman): add http fetcher port, thumb source contract and WebVTT source"
```

---

## Task 9: 抽帧端口、平台判定与 media_kit 隐藏 Player 实现

DESIGN §7.3 + §6.1「抽帧兜底 | 开 | `extractFallback`、`platforms` | 自定义 `VmFrameExtractor`」。
**隐藏 `Player` 是本阶段唯一一处 media_kit 新用法，必须落在 `lib/src/platform_impl/`**，
core 只见抽象端口。具体的 mpv 属性组合取决于 Task 1 的实测结论。

**Files:**
- Create: `lib/src/core/preview/extractor.dart`, `lib/src/core/preview/platform_kind.dart`, `lib/src/platform_impl/mpv_extractor_impl.dart`
- Modify: `lib/videoman.dart`
- Test: `test/core/preview/extractor_test.dart`

**Interfaces:**
- Consumes: `VmSource`（既有）、`VmThumb`（Task 2）、`VmThumbSource`（Task 8）
- Produces:
  - `abstract class VmFrameExtractor { Future<Uint8List?> extract(String uri, Duration at, {required int width, required bool hwdec}); Future<void> release(); Future<void> dispose(); }`
  - `class VmExtractorThumbSource implements VmThumbSource { VmExtractorThumbSource({required VmFrameExtractor extractor, int width = 160, bool hwdec = false}); }`
  - `enum VmPlatformKind { android, ios, windows, macos, linux, other }`
  - `VmPlatformKind currentPlatformKind()`
  - `class MpvFrameExtractor implements VmFrameExtractor`（`platform_impl`，无单测，靠 Task 14 实跑验证）

- [ ] **Step 1: 写失败测试 `test/core/preview/extractor_test.dart`**

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/preview/extractor.dart';
import 'package:videoman/src/core/preview/platform_kind.dart';

/// A [VmFrameExtractor] returning canned bytes and recording its arguments.
///
/// 返回预置字节并记录调用参数的 [VmFrameExtractor]。
class _FakeExtractor implements VmFrameExtractor {
  /// Bytes returned by [extract]; null makes extraction "fail".
  ///
  /// [extract] 返回的字节；为 null 表示抽帧"失败"。
  Uint8List? result = Uint8List.fromList([42]);

  /// Ordered method names invoked on this fake.
  ///
  /// 在该替身上被调用的方法名有序列表。
  final List<String> calls = <String>[];

  /// The `uri` of the most recent [extract] call.
  ///
  /// 最近一次 [extract] 调用的 `uri`。
  String? lastUri;

  /// The `at` of the most recent [extract] call.
  ///
  /// 最近一次 [extract] 调用的 `at`。
  Duration? lastAt;

  /// The `width` of the most recent [extract] call.
  ///
  /// 最近一次 [extract] 调用的 `width`。
  int? lastWidth;

  /// The `hwdec` of the most recent [extract] call.
  ///
  /// 最近一次 [extract] 调用的 `hwdec`。
  bool? lastHwdec;

  @override
  Future<Uint8List?> extract(
    String uri,
    Duration at, {
    required int width,
    required bool hwdec,
  }) async {
    calls.add('extract');
    lastUri = uri;
    lastAt = at;
    lastWidth = width;
    lastHwdec = hwdec;
    return result;
  }

  @override
  Future<void> release() async => calls.add('release');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

void main() {
  const src = VmSource('https://host/a.mp4');

  test('the source reports a stable name for diagnostics', () {
    expect(VmExtractorThumbSource(extractor: _FakeExtractor()).name, 'extract');
  });

  test('thumbAt forwards uri, bucket, width and hwdec to the extractor', () async {
    final e = _FakeExtractor();
    final s = VmExtractorThumbSource(extractor: e, width: 320, hwdec: true);
    final t = await s.thumbAt(src, const Duration(seconds: 30));
    expect(e.lastUri, 'https://host/a.mp4');
    expect(e.lastAt, const Duration(seconds: 30));
    expect(e.lastWidth, 320);
    expect(e.lastHwdec, isTrue);
    expect(t!.at, const Duration(seconds: 30));
    expect(t.bytes, [42]);
    expect(t.crop, isNull, reason: 'an extracted frame is always the whole image');
    await s.dispose();
  });

  test('defaults are 160px and software decoding', () async {
    final e = _FakeExtractor();
    final s = VmExtractorThumbSource(extractor: e);
    await s.thumbAt(src, Duration.zero);
    expect(e.lastWidth, 160);
    expect(e.lastHwdec, isFalse);
    await s.dispose();
  });

  test('a failed extraction yields null and is retried on the next scrub', () async {
    final e = _FakeExtractor()..result = null;
    final s = VmExtractorThumbSource(extractor: e);
    expect(await s.thumbAt(src, Duration.zero), isNull);
    e.result = Uint8List.fromList([7]);
    expect((await s.thumbAt(src, Duration.zero))!.bytes, [7]);
    await s.dispose();
  });

  test('reset releases the extractor without disposing it', () async {
    final e = _FakeExtractor();
    final s = VmExtractorThumbSource(extractor: e);
    await s.reset();
    expect(e.calls, ['release']);
    await s.dispose();
    expect(e.calls, ['release', 'dispose']);
  });

  test('currentPlatformKind reports one of the known kinds', () {
    expect(VmPlatformKind.values, contains(currentPlatformKind()));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/preview/extractor_test.dart`
Expected: FAIL — `Error when reading 'lib/src/core/preview/extractor.dart': No such file or directory`

- [ ] **Step 3: 实现 `lib/src/core/preview/platform_kind.dart`**

```dart
import 'dart:io';

/// The host platform, as far as the preview feature needs to distinguish it.
///
/// 预览功能所需区分的宿主平台粒度。
enum VmPlatformKind {
  /// Android.
  ///
  /// 安卓。
  android,

  /// iOS.
  ///
  /// iOS。
  ios,

  /// Windows desktop.
  ///
  /// Windows 桌面。
  windows,

  /// macOS desktop.
  ///
  /// macOS 桌面。
  macos,

  /// Linux desktop.
  ///
  /// Linux 桌面。
  linux,

  /// Anything else / unclassifiable.
  ///
  /// 其他/无法分类的平台。
  other,
}

/// Detects the current [VmPlatformKind] from `dart:io`.
///
/// Uses `dart:io` rather than `defaultTargetPlatform` so the core layer stays
/// free of Flutter imports; videoman is a libmpv-backed plugin and never
/// targets web, so the `dart:io` restriction costs nothing.
///
/// 通过 `dart:io` 判定当前的 [VmPlatformKind]。
///
/// 用 `dart:io` 而非 `defaultTargetPlatform`，是为了让 core 层不引入 Flutter；
/// videoman 是基于 libmpv 的插件、本就不支持 web，因此这个限制没有代价。
///
/// Returns the detected platform kind.
///
/// 返回检测到的平台类型。
VmPlatformKind currentPlatformKind() {
  if (Platform.isAndroid) return VmPlatformKind.android;
  if (Platform.isIOS) return VmPlatformKind.ios;
  if (Platform.isWindows) return VmPlatformKind.windows;
  if (Platform.isMacOS) return VmPlatformKind.macos;
  if (Platform.isLinux) return VmPlatformKind.linux;
  return VmPlatformKind.other;
}
```

- [ ] **Step 4: 实现 `lib/src/core/preview/extractor.dart`**

```dart
import 'dart:typed_data';

import '../model/source.dart';
import 'models.dart';
import 'source.dart';

/// Decodes one frame of a media at a given position, downscaled for preview.
///
/// A port rather than a concrete class because the only implementation spins a
/// second, hidden media_kit `Player`, and `lib/src/core/**` must stay
/// media_kit-free — the implementation lives in
/// `lib/src/platform_impl/mpv_extractor_impl.dart`.
///
/// 在给定位置解出媒体的一帧，并按预览需要缩小。
///
/// 之所以做成端口而非具体类：唯一的实现会另起一个隐藏的 media_kit `Player`，
/// 而 `lib/src/core/**` 必须与 media_kit 解耦——实现放在
/// `lib/src/platform_impl/mpv_extractor_impl.dart`。
abstract class VmFrameExtractor {
  /// Extracts the frame of [uri] at [at], encoded as JPEG.
  ///
  /// 抽取 [uri] 在 [at] 处的一帧，编码为 JPEG。
  ///
  /// - [uri]: the media address / 媒体地址
  /// - [at]: the position to extract / 要抽取的位置
  /// - [width]: target width in pixels; height follows the aspect ratio /
  ///   目标宽度（像素），高度按宽高比推导
  /// - [hwdec]: whether hardware decoding may be used / 是否允许硬件解码
  ///
  /// Returns the encoded frame, or null when extraction failed.
  ///
  /// 返回编码后的帧；抽取失败时返回 null。
  Future<Uint8List?> extract(
    String uri,
    Duration at, {
    required int width,
    required bool hwdec,
  });

  /// Frees the underlying decoder while staying reusable — called when the
  /// player goes idle or opens a different media.
  ///
  /// 释放底层解码器但保持可复用——播放器空闲或换源时调用。
  Future<void> release();

  /// Releases everything permanently.
  ///
  /// 永久释放全部资源。
  Future<void> dispose();
}

/// Adapts a [VmFrameExtractor] to the [VmThumbSource] contract so the preview
/// service can treat extraction as just another entry in its ordered source
/// list.
///
/// An extracted frame is always the whole image, so [VmThumb.crop] is null.
///
/// 把 [VmFrameExtractor] 适配为 [VmThumbSource] 契约，让预览服务可以把抽帧
/// 当作有序来源表里的普通一项对待。
///
/// 抽出来的帧总是整张图，因此 [VmThumb.crop] 恒为 null。
class VmExtractorThumbSource implements VmThumbSource {
  /// Creates an extractor-backed thumbnail source.
  ///
  /// 创建基于抽帧器的缩略图来源。
  ///
  /// - [extractor]: the frame extractor port / 抽帧端口
  /// - [width]: target frame width in pixels / 目标帧宽度（像素）
  /// - [hwdec]: whether hardware decoding may be used / 是否允许硬件解码
  VmExtractorThumbSource({
    required this.extractor,
    this.width = 160,
    this.hwdec = false,
  });

  /// The frame extractor this source drives.
  ///
  /// 该来源驱动的抽帧端口。
  final VmFrameExtractor extractor;

  /// Target frame width in pixels.
  ///
  /// 目标帧宽度（像素）。
  final int width;

  /// Whether hardware decoding may be used.
  ///
  /// 是否允许硬件解码。
  final bool hwdec;

  @override
  String get name => 'extract';

  @override
  Future<VmThumb?> thumbAt(VmSource source, Duration bucket) async {
    final bytes = await extractor.extract(
      source.uri,
      bucket,
      width: width,
      hwdec: hwdec,
    );
    if (bytes == null) return null;
    return VmThumb(at: bucket, bytes: bytes);
  }

  @override
  Future<void> reset() => extractor.release();

  @override
  Future<void> dispose() => extractor.dispose();
}
```

- [ ] **Step 5: 实现 `lib/src/platform_impl/mpv_extractor_impl.dart`**

> **Task 1 实测结论（附录 A）：`vfScale` 与 `controllerSize` 两条路线均
> `WORKS=false`——`screenshot()` 拿到的始终是原生分辨率。** 因此下面的实现**不设
> `vf` 属性、也不给 `VideoControllerConfiguration` 传宽高**，直接把 `screenshot()`
> 的原图整张返回；`width` 参数不参与实际抽帧，只用于 cache key（Task 2）与 UI 侧显示
> 目标宽度。磁盘缓存的 `diskMaxBytes` 默认值因此需要按原分辨率 JPEG 复核，见附录 A。

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/preview/extractor.dart';

/// The default [VmFrameExtractor]: a second, hidden media_kit `Player` used
/// only to decode single frames.
///
/// Reuses the libmpv/ffmpeg already bundled for playback, so preview
/// extraction adds no dependency and does not affect the planned ffmpeg
/// slimming milestone. Playback quality settings are deliberately minimal —
/// audio off, no cache, exact seeks — because these frames are only ever
/// shown as small preview thumbnails. Output is NOT downscaled at the mpv
/// layer: Task 1's spike found that neither `vf=scale` nor
/// `VideoControllerConfiguration` sizing actually shrinks what
/// `screenshot()` returns on Windows (see plan appendix A), so [extract]
/// hands back whatever resolution the source has and `width` is purely
/// advisory (cache key, UI-side target size).
///
/// Calls are serialised internally: libmpv cannot service two seek+screenshot
/// round trips on one player concurrently.
///
/// 默认的 [VmFrameExtractor]：第二个隐藏的 media_kit `Player`，只用于解单帧。
///
/// 复用播放时已经打包进来的 libmpv/ffmpeg，因此预览抽帧不引入任何依赖，也不
/// 影响后续 ffmpeg 瘦身里程碑。播放相关设置刻意压到最低——关音频、不做缓存、
/// 精确 seek——因为这些帧只是拿来当小预览图用，不会被真的观看。输出**不**在
/// mpv 层缩放：Task 1 的 spike 发现 Windows 上 `vf=scale` 与
/// `VideoControllerConfiguration` 都不能真正缩小 `screenshot()` 的结果
/// （见计划附录 A），因此 [extract] 原样返回源分辨率的图，`width` 只是
/// 建议值（用于 cache key 与 UI 侧目标尺寸）。
///
/// 内部对调用做了串行化：libmpv 无法在同一个 player 上并发处理两次
/// seek + screenshot 往返。
class MpvFrameExtractor implements VmFrameExtractor {
  /// Creates an extractor; the hidden player is created lazily on first use.
  ///
  /// 创建抽帧器；隐藏播放器在首次使用时才惰性创建。
  ///
  /// - [settleDelay]: how long to wait after a seek before screenshotting /
  ///   seek 之后、截图之前的等待时长
  MpvFrameExtractor({this.settleDelay = const Duration(milliseconds: 250)});

  /// How long to wait after a seek before screenshotting.
  ///
  /// seek 之后、截图之前的等待时长。
  final Duration settleDelay;

  /// The hidden player, or null when released.
  ///
  /// 隐藏播放器；已释放时为 null。
  Player? _player;

  /// The hidden player's video controller; kept alive alongside [_player].
  ///
  /// 隐藏播放器的视频控制器；与 [_player] 同生共死。
  VideoController? _controller;

  /// The media currently open on the hidden player, or null when none.
  ///
  /// 隐藏播放器当前已打开的媒体；无则为 null。
  String? _openUri;

  /// Serialises concurrent [extract] calls onto one hidden player.
  ///
  /// 把并发的 [extract] 调用串行化到同一个隐藏播放器上。
  Future<void> _queue = Future<void>.value();

  /// Whether [dispose] has already run; further calls are no-ops.
  ///
  /// [dispose] 是否已执行过；执行过后所有调用都变为空操作。
  bool _disposed = false;

  /// Creates the hidden player if needed and applies the extraction-tuned mpv
  /// properties.
  ///
  /// 按需创建隐藏播放器，并应用为抽帧调优过的 mpv 属性。
  ///
  /// - [width]: target frame width in pixels / 目标帧宽度（像素）
  /// - [hwdec]: whether hardware decoding may be used / 是否允许硬件解码
  ///
  /// Returns the ready player.
  ///
  /// 返回就绪的播放器。
  Future<Player> _ensurePlayer(int width, bool hwdec) async {
    final existing = _player;
    if (existing != null) return existing;
    final player = Player();
    _controller = VideoController(player);
    final native = player.platform;
    if (native is NativePlayer) {
      await native.setProperty('ao', 'null');
      await native.setProperty('hwdec', hwdec ? 'auto' : 'no');
      await native.setProperty('hr-seek', 'yes');
      await native.setProperty('cache', 'no');
      // `width` is intentionally unused here: neither `vf=scale` nor
      // VideoControllerConfiguration sizing shrinks screenshot() output on
      // Windows (Task 1 spike, plan appendix A), so no mpv-side scaling is
      // attempted.
      //
      // `width` 在此故意不使用：Task 1 的 spike（见计划附录 A）证实
      // Windows 上 `vf=scale` 与 VideoControllerConfiguration 都不能真正
      // 缩小 screenshot() 的输出，因此不在 mpv 层做任何缩放尝试。
    }
    _player = player;
    return player;
  }

  /// Performs one extraction on the hidden player, without queueing.
  ///
  /// 在隐藏播放器上执行一次抽帧，不做排队。
  ///
  /// - [uri]: the media address / 媒体地址
  /// - [at]: the position to extract / 要抽取的位置
  /// - [width]: target width in pixels / 目标宽度（像素）
  /// - [hwdec]: whether hardware decoding may be used / 是否允许硬件解码
  ///
  /// Returns the encoded frame, or null on any failure.
  ///
  /// 返回编码后的帧；任何失败都返回 null。
  Future<Uint8List?> _extractNow(
    String uri,
    Duration at, {
    required int width,
    required bool hwdec,
  }) async {
    if (_disposed) return null;
    try {
      final player = await _ensurePlayer(width, hwdec);
      if (_openUri != uri) {
        await player.open(Media(uri), play: false);
        _openUri = uri;
      }
      await player.seek(at);
      await Future<void>.delayed(settleDelay);
      return await player.screenshot(format: 'image/jpeg');
    } on Object {
      return null;
    }
  }

  @override
  Future<Uint8List?> extract(
    String uri,
    Duration at, {
    required int width,
    required bool hwdec,
  }) {
    final completer = Completer<Uint8List?>();
    _queue = _queue.then((_) async {
      completer.complete(await _extractNow(uri, at, width: width, hwdec: hwdec));
    });
    return completer.future;
  }

  @override
  Future<void> release() async {
    final player = _player;
    _player = null;
    _controller = null;
    _openUri = null;
    if (player != null) {
      try {
        await player.dispose();
      } on Object {
        // Disposing a hidden helper must never surface as a playback error.
        //
        // 释放隐藏辅助播放器时的异常绝不能冒充成播放错误。
      }
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await release();
  }
}
```

- [ ] **Step 6: barrel 增补导出**

`lib/videoman.dart` 在 `export 'src/core/preview/disk_cache.dart';` 之后按字母序插入：

```dart
export 'src/core/preview/extractor.dart';
```

在 `export 'src/core/preview/net_probe.dart';` 之前插入：

```dart
export 'src/core/preview/platform_kind.dart';
```

在 `export 'src/platform_impl/net_probe_impl.dart';` 之前插入：

```dart
export 'src/platform_impl/mpv_extractor_impl.dart';
```

- [ ] **Step 7: 跑测试与分析**

Run: `flutter test && flutter analyze`
Expected: extractor 6 项 PASS，累计 163 项全绿，analyze 0 issues。
**特别确认 `flutter test test/core/purity_test.dart` PASS**——`extractor.dart` 只依赖
`dart:typed_data`，media_kit 只出现在 `platform_impl/mpv_extractor_impl.dart`。

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(videoman): add frame extractor port with hidden media_kit player implementation"
```

---

## Task 10: `VmPreviewConfig` 与 `VmOptions.preview`

DESIGN §6.1 全表落成配置类，外加 `VmPreviewBlocked` 事件。阶段 A 在 `options.dart` 的类注释里
写了「目前暂不包含 `preview`（预览图）一节，留待后续任务」——本任务把那句话删掉。

**Files:**
- Create: `lib/src/core/options/preview_config.dart`
- Modify: `lib/src/core/options/options.dart`, `lib/src/core/events/events.dart`, `lib/videoman.dart`
- Test: `test/core/options_test.dart`（追加 5 项，不动既有 4 项）

**Interfaces:**
- Consumes: `VmPreviewNetwork`/`VmNetProbe`（Task 7）、`VmThumbSource`（Task 8）、`VmFrameExtractor`（Task 9）、`VmPlatformKind`（Task 9）、`VmThumbCache`（Task 4）、`VmThumbDirProvider`（Task 5）、`VmCacheKeyBuilder`（Task 2）、`VmVttUrlResolver`（Task 8）
- Produces:
  - `enum VmPreviewBlockReason { network, disabled, noSource, platform }`
  - `typedef VmPreviewBlockedCallback = void Function(VmPreviewBlockReason reason);`
  - `class VmPreviewConfig`（字段见 Step 3），带 `const` 构造、`copyWith`、`==`、`hashCode`
  - `VmOptions.preview`（默认 `const VmPreviewConfig()`）+ `copyWith(preview:)` + 参与 `==`/`hashCode`
  - `class VmPreviewBlocked extends VmEvent { final VmPreviewBlockReason reason; const VmPreviewBlocked(this.reason); }`

- [ ] **Step 1: 追加失败测试到 `test/core/options_test.dart`**

在文件顶部 import 区补（**只补这三行**，多补会触发 `unused_import` 让 analyze 非 0）：

```dart
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/preview/net_probe.dart';
import 'package:videoman/src/core/preview/platform_kind.dart';
```

`VmVttUrlResolver` 无需 import：测试里传的是闭包字面量，类型由参数位置推断。

在 `main()` 末尾追加：

```dart
  test('VmPreviewConfig defaults match DESIGN section 6.1', () {
    const p = VmPreviewConfig();
    expect(p.enabled, isTrue);
    expect(p.network, VmPreviewNetwork.wifiOnly);
    expect(p.onBlocked, isNull);
    expect(p.sources, isNull, reason: 'null means the built-in [vtt, extract] chain');
    expect(p.vttEnabled, isTrue);
    expect(p.vttUrl, isNull);
    expect(p.vttUrlResolver, isNull);
    expect(p.extractFallback, isTrue);
    expect(p.extractPlatforms, VmPlatformKind.values.toSet());
    expect(p.frameWidth, 160);
    expect(p.bucket, const Duration(seconds: 10));
    expect(p.hwdec, isFalse);
    expect(p.memMaxEntries, 40);
    expect(p.diskMaxBytes, 64 * 1024 * 1024);
    expect(p.diskDir, isNull);
    expect(p.cacheKeyBuilder, isNull);
    expect(p.clearOnDispose, isTrue);
    expect(p.debounce, const Duration(milliseconds: 120));
    expect(p.probe, isNull);
    expect(p.cache, isNull);
    expect(p.extractor, isNull);
  });

  test('VmOptions exposes a preview section that defaults to VmPreviewConfig', () {
    const o = VmOptions();
    expect(o.preview, const VmPreviewConfig());
  });

  test('VmOptions.copyWith replaces only the preview section', () {
    const o = VmOptions();
    final n = o.copyWith(preview: const VmPreviewConfig(frameWidth: 320));
    expect(n.preview.frameWidth, 320);
    expect(n.gesture, o.gesture);
    expect(n.controls, o.controls);
    expect(n, isNot(o));
  });

  test('VmPreviewConfig.copyWith replaces one knob and compares by value', () {
    const p = VmPreviewConfig();
    final n = p.copyWith(network: VmPreviewNetwork.never);
    expect(n.network, VmPreviewNetwork.never);
    expect(n.frameWidth, p.frameWidth);
    expect(n, isNot(p));
    expect(p.copyWith(), p);
  });

  test('every VmPreviewConfig injection point accepts a custom strategy', () {
    final p = VmPreviewConfig(
      probe: AlwaysAllowNetProbe(),
      cacheKeyBuilder: (s, b, w) => 'custom',
      vttUrlResolver: (s) => Uri.parse('https://cdn/t.vtt'),
      onBlocked: (_) {},
      extractPlatforms: const {VmPlatformKind.windows},
    );
    expect(p.probe, isA<VmNetProbe>());
    expect(p.cacheKeyBuilder!('a', 1, 2), 'custom');
    expect(p.vttUrlResolver!(const VmSource('x')), Uri.parse('https://cdn/t.vtt'));
    expect(p.onBlocked, isNotNull);
    expect(p.extractPlatforms, {VmPlatformKind.windows});
  });
```

（上面三个 import 已覆盖本组用到的全部类型。）

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/options_test.dart`
Expected: FAIL — `VmPreviewConfig isn't defined`；既有 4 项仍 PASS

- [ ] **Step 3: 实现 `lib/src/core/options/preview_config.dart`**

```dart
import '../preview/cache.dart';
import '../preview/dir_provider.dart';
import '../preview/extractor.dart';
import '../preview/hash.dart';
import '../preview/net_probe.dart';
import '../preview/platform_kind.dart';
import '../preview/source.dart';
import '../preview/vtt_source.dart';

/// Why a scrub-preview request was refused before any work happened.
///
/// 一次拖动预览请求在真正开工前被拒绝的原因。
enum VmPreviewBlockReason {
  /// The network policy refused this connection.
  ///
  /// 网络策略拒绝了当前连接。
  network,

  /// Preview is switched off via [VmPreviewConfig.enabled].
  ///
  /// 预览已通过 [VmPreviewConfig.enabled] 关闭。
  disabled,

  /// No media has been opened yet.
  ///
  /// 尚未打开任何媒体。
  noSource,

  /// No configured source can serve this platform.
  ///
  /// 当前平台上没有任何已配置的来源可用。
  platform,
}

/// Notified when a preview request is refused; the default is silence.
///
/// 预览请求被拒绝时的回调；默认行为是静默。
///
/// - [reason]: why the request was refused / 被拒绝的原因
typedef VmPreviewBlockedCallback = void Function(VmPreviewBlockReason reason);

/// Configuration for the scrub-preview (thumbnail) feature.
///
/// Every decision videoman makes on the host's behalf appears here as a
/// default plus a knob, and — where a decision is a strategy rather than a
/// value — an injection point ([probe], [cache], [extractor], [sources],
/// [vttUrlResolver], [cacheKeyBuilder]). See DESIGN §6.1.
///
/// 拖动预览（缩略图）功能的配置。
///
/// videoman 替宿主做的每一个决策，在这里都以"默认值 + 配置项"的形式出现；
/// 若该决策本质是策略而非取值，还额外提供注入点（[probe]、[cache]、
/// [extractor]、[sources]、[vttUrlResolver]、[cacheKeyBuilder]）。见 DESIGN §6.1。
class VmPreviewConfig {
  /// Whether the preview feature runs at all.
  ///
  /// 是否启用预览功能。
  final bool enabled;

  /// When networked thumbnail sources may run.
  ///
  /// 何时允许运行需要联网的缩略图来源。
  final VmPreviewNetwork network;

  /// Injected connectivity probe; null uses [AlwaysAllowNetProbe] in core and
  /// the connectivity_plus probe when the host wires one in.
  ///
  /// 注入的连通性探针；为 null 时 core 内部使用 [AlwaysAllowNetProbe]，宿主
  /// 接入时可换成基于 connectivity_plus 的探针。
  final VmNetProbe? probe;

  /// Called when a request is refused; null means stay silent.
  ///
  /// 请求被拒绝时的回调；为 null 表示静默。
  final VmPreviewBlockedCallback? onBlocked;

  /// Ordered thumbnail source chain; null builds the default
  /// `[vtt, extract]` chain from [vttEnabled]/[extractFallback].
  ///
  /// 有序的缩略图来源链；为 null 时按 [vttEnabled]/[extractFallback] 构建默认
  /// 的 `[vtt, extract]` 链。
  final List<VmThumbSource>? sources;

  /// Whether the WebVTT source participates in the default chain.
  ///
  /// WebVTT 来源是否参与默认链。
  final bool vttEnabled;

  /// Fixed WebVTT track URL; overrides the `<video>.vtt` convention.
  ///
  /// 固定的 WebVTT 轨地址；覆盖 `<video>.vtt` 约定。
  final String? vttUrl;

  /// Strategy locating the WebVTT track; wins over [vttUrl] when both are set.
  ///
  /// 定位 WebVTT 轨的策略；与 [vttUrl] 同时设置时以本项为准。
  final VmVttUrlResolver? vttUrlResolver;

  /// Whether frame extraction backs up a missing/failing WebVTT track.
  ///
  /// WebVTT 轨缺失/失败时是否用抽帧兜底。
  final bool extractFallback;

  /// Platforms frame extraction is allowed to run on.
  ///
  /// 允许运行抽帧的平台集合。
  final Set<VmPlatformKind> extractPlatforms;

  /// Injected frame extractor; null uses the media_kit-backed default wired in
  /// by the host layer.
  ///
  /// 注入的抽帧器；为 null 时使用由宿主层接入的、基于 media_kit 的默认实现。
  final VmFrameExtractor? extractor;

  /// Target thumbnail width in pixels.
  ///
  /// 缩略图目标宽度（像素）。
  final int frameWidth;

  /// Bucket size positions are aligned to, so scrubbing within one bucket
  /// reuses one image.
  ///
  /// 位置对齐所用的桶大小，使同一桶内的拖动复用同一张图。
  final Duration bucket;

  /// Whether extraction may use hardware decoding.
  ///
  /// 抽帧是否允许使用硬件解码。
  final bool hwdec;

  /// Memory cache entry ceiling.
  ///
  /// 内存缓存条目上限。
  final int memMaxEntries;

  /// Disk cache byte budget.
  ///
  /// 磁盘缓存字节预算。
  final int diskMaxBytes;

  /// Fixed disk cache directory; null uses the platform temporary directory.
  ///
  /// 固定的磁盘缓存目录；为 null 时使用平台临时目录。
  final String? diskDir;

  /// Injected cache implementation; null builds the default two-level cache
  /// from [memMaxEntries]/[diskMaxBytes]/[diskDir].
  ///
  /// 注入的缓存实现；为 null 时按 [memMaxEntries]/[diskMaxBytes]/[diskDir]
  /// 构建默认的两级缓存。
  final VmThumbCache? cache;

  /// Injected disk directory resolver; null uses [diskDir] when set, otherwise
  /// the host-wired temporary-directory provider.
  ///
  /// 注入的磁盘目录解析器；为 null 时优先用 [diskDir]，否则使用宿主接入的
  /// 临时目录 provider。
  final VmThumbDirProvider? dirProvider;

  /// Strategy building cache keys; null uses [defaultCacheKey].
  ///
  /// 构建缓存 key 的策略；为 null 时使用 [defaultCacheKey]。
  final VmCacheKeyBuilder? cacheKeyBuilder;

  /// Whether the disk cache directory is wiped on dispose.
  ///
  /// 销毁时是否清空磁盘缓存目录。
  final bool clearOnDispose;

  /// How long scrub movement must settle before a request is issued.
  ///
  /// 拖动静止多久之后才发出请求。
  final Duration debounce;

  /// Creates a preview configuration; every field defaults to the value
  /// documented in DESIGN §6.1.
  ///
  /// 创建预览配置；每个字段的默认值均与 DESIGN §6.1 一致。
  ///
  /// - [enabled]: master switch / 总开关
  /// - [network]: network policy / 网络策略
  /// - [probe]: injected connectivity probe / 注入的连通性探针
  /// - [onBlocked]: refusal callback / 被拒回调
  /// - [sources]: full source-chain override / 整条来源链的覆盖
  /// - [vttEnabled]: include the WebVTT source / 是否启用 WebVTT 来源
  /// - [vttUrl]: fixed WebVTT URL / 固定 WebVTT 地址
  /// - [vttUrlResolver]: WebVTT URL strategy / WebVTT 地址策略
  /// - [extractFallback]: include the extraction source / 是否启用抽帧兜底
  /// - [extractPlatforms]: platforms extraction runs on / 允许抽帧的平台
  /// - [extractor]: injected extractor / 注入的抽帧器
  /// - [frameWidth]: target width in px / 目标宽度（像素）
  /// - [bucket]: bucket size / 桶大小
  /// - [hwdec]: allow hardware decoding / 是否允许硬解
  /// - [memMaxEntries]: memory entry ceiling / 内存条目上限
  /// - [diskMaxBytes]: disk byte budget / 磁盘字节预算
  /// - [diskDir]: fixed disk directory / 固定磁盘目录
  /// - [cache]: injected cache / 注入的缓存
  /// - [dirProvider]: injected directory resolver / 注入的目录解析器
  /// - [cacheKeyBuilder]: cache-key strategy / 缓存 key 策略
  /// - [clearOnDispose]: wipe disk cache on dispose / 销毁时清盘
  /// - [debounce]: scrub settle delay / 拖动防抖时长
  const VmPreviewConfig({
    this.enabled = true,
    this.network = VmPreviewNetwork.wifiOnly,
    this.probe,
    this.onBlocked,
    this.sources,
    this.vttEnabled = true,
    this.vttUrl,
    this.vttUrlResolver,
    this.extractFallback = true,
    this.extractPlatforms = const {
      VmPlatformKind.android,
      VmPlatformKind.ios,
      VmPlatformKind.windows,
      VmPlatformKind.macos,
      VmPlatformKind.linux,
      VmPlatformKind.other,
    },
    this.extractor,
    this.frameWidth = 160,
    this.bucket = const Duration(seconds: 10),
    this.hwdec = false,
    this.memMaxEntries = 40,
    this.diskMaxBytes = 64 * 1024 * 1024,
    this.diskDir,
    this.cache,
    this.dirProvider,
    this.cacheKeyBuilder,
    this.clearOnDispose = true,
    this.debounce = const Duration(milliseconds: 120),
  });

  /// Returns a copy with the given knobs replaced; omitted knobs keep their
  /// current value.
  ///
  /// 返回一份替换了指定配置项的拷贝；未指定的项保持当前值。
  ///
  /// Every parameter mirrors the same-named field.
  ///
  /// 每个参数对应同名字段。
  ///
  /// Returns the new [VmPreviewConfig].
  ///
  /// 返回新的 [VmPreviewConfig]。
  VmPreviewConfig copyWith({
    bool? enabled,
    VmPreviewNetwork? network,
    VmNetProbe? probe,
    VmPreviewBlockedCallback? onBlocked,
    List<VmThumbSource>? sources,
    bool? vttEnabled,
    String? vttUrl,
    VmVttUrlResolver? vttUrlResolver,
    bool? extractFallback,
    Set<VmPlatformKind>? extractPlatforms,
    VmFrameExtractor? extractor,
    int? frameWidth,
    Duration? bucket,
    bool? hwdec,
    int? memMaxEntries,
    int? diskMaxBytes,
    String? diskDir,
    VmThumbCache? cache,
    VmThumbDirProvider? dirProvider,
    VmCacheKeyBuilder? cacheKeyBuilder,
    bool? clearOnDispose,
    Duration? debounce,
  }) {
    return VmPreviewConfig(
      enabled: enabled ?? this.enabled,
      network: network ?? this.network,
      probe: probe ?? this.probe,
      onBlocked: onBlocked ?? this.onBlocked,
      sources: sources ?? this.sources,
      vttEnabled: vttEnabled ?? this.vttEnabled,
      vttUrl: vttUrl ?? this.vttUrl,
      vttUrlResolver: vttUrlResolver ?? this.vttUrlResolver,
      extractFallback: extractFallback ?? this.extractFallback,
      extractPlatforms: extractPlatforms ?? this.extractPlatforms,
      extractor: extractor ?? this.extractor,
      frameWidth: frameWidth ?? this.frameWidth,
      bucket: bucket ?? this.bucket,
      hwdec: hwdec ?? this.hwdec,
      memMaxEntries: memMaxEntries ?? this.memMaxEntries,
      diskMaxBytes: diskMaxBytes ?? this.diskMaxBytes,
      diskDir: diskDir ?? this.diskDir,
      cache: cache ?? this.cache,
      dirProvider: dirProvider ?? this.dirProvider,
      cacheKeyBuilder: cacheKeyBuilder ?? this.cacheKeyBuilder,
      clearOnDispose: clearOnDispose ?? this.clearOnDispose,
      debounce: debounce ?? this.debounce,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VmPreviewConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          network == other.network &&
          identical(probe, other.probe) &&
          identical(onBlocked, other.onBlocked) &&
          identical(sources, other.sources) &&
          vttEnabled == other.vttEnabled &&
          vttUrl == other.vttUrl &&
          identical(vttUrlResolver, other.vttUrlResolver) &&
          extractFallback == other.extractFallback &&
          _setEq(extractPlatforms, other.extractPlatforms) &&
          identical(extractor, other.extractor) &&
          frameWidth == other.frameWidth &&
          bucket == other.bucket &&
          hwdec == other.hwdec &&
          memMaxEntries == other.memMaxEntries &&
          diskMaxBytes == other.diskMaxBytes &&
          diskDir == other.diskDir &&
          identical(cache, other.cache) &&
          identical(dirProvider, other.dirProvider) &&
          identical(cacheKeyBuilder, other.cacheKeyBuilder) &&
          clearOnDispose == other.clearOnDispose &&
          debounce == other.debounce;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        enabled,
        network,
        probe,
        onBlocked,
        sources,
        vttEnabled,
        vttUrl,
        vttUrlResolver,
        extractFallback,
        Object.hashAllUnordered(extractPlatforms),
        extractor,
        frameWidth,
        bucket,
        hwdec,
        memMaxEntries,
        diskMaxBytes,
        diskDir,
        cache,
        dirProvider,
        cacheKeyBuilder,
        clearOnDispose,
        debounce,
      ]);
}

/// Order-insensitive set equality; core cannot import `setEquals` from
/// `package:flutter/foundation.dart`.
///
/// 与顺序无关的集合相等判断；core 不能从 `package:flutter/foundation.dart`
/// 引入 `setEquals`。
///
/// - [a], [b]: the sets to compare / 要比较的两个集合
///
/// Returns whether the sets hold the same elements.
///
/// 返回两个集合元素是否相同。
bool _setEq(Set<VmPlatformKind> a, Set<VmPlatformKind> b) =>
    a.length == b.length && a.containsAll(b);
```

- [ ] **Step 4: 把 `preview` 接进 `VmOptions`**

`lib/src/core/options/options.dart`：

1. 顶部 export 区加 `export 'preview_config.dart';`，import 区加 `import 'preview_config.dart';`（都按字母序，`live_config` 与 `strings` 之间）。
2. 类文档注释里删掉 `A \`preview\` section is intentionally absent for now (deferred to a later task).` 与对应中文句「目前暂不包含 `preview`（预览图）一节，留待后续任务。」，改写为：

```dart
/// Groups every configurable aspect (preview, gestures, ABR, control bar,
/// live behaviour, copy, theme) into one object so apps can construct and
/// pass a single [VmOptions] instance, and so [copyWith] can replace one
/// section without disturbing the others.
///
/// 把所有可配置项（预览、手势、ABR、控制条、直播行为、文案、主题）归入一个
/// 对象，应用只需构造并传入一个 [VmOptions] 实例；[copyWith] 可只替换其中
/// 一节而不影响其他节。
```

3. 新字段（放在 `live` 之前，保持"预览在前"与构造参数顺序一致）：

```dart
  /// Scrub-preview (thumbnail) configuration.
  ///
  /// 拖动预览（缩略图）配置。
  final VmPreviewConfig preview;
```

4. 构造参数加 `this.preview = const VmPreviewConfig(),`（第一个参数）。
5. `copyWith` 加 `VmPreviewConfig? preview,` 参数、`preview: preview ?? this.preview,` 赋值、
   文档注释加 `/// - [preview]: replacement preview config / 替换用的预览配置`。
6. `==` 加 `preview == other.preview &&`；`hashCode` 改为
   `Object.hash(preview, live, gesture, abr, controls, strings, theme)`。

- [ ] **Step 5: 加 `VmPreviewBlocked` 事件**

`lib/src/core/events/events.dart` 顶部 import 区加：

```dart
import '../options/preview_config.dart';
```

在 `VmErrorEvent` 之前插入：

```dart
/// A scrub-preview request was refused before any work happened.
///
/// 一次拖动预览请求在真正开工前被拒绝。
class VmPreviewBlocked extends VmEvent {
  /// Why the request was refused.
  ///
  /// 被拒绝的原因。
  final VmPreviewBlockReason reason;

  /// Creates the event with [reason].
  ///
  /// 用 [reason] 创建事件。
  const VmPreviewBlocked(this.reason);
}
```

- [ ] **Step 6: barrel 增补导出**

`lib/videoman.dart` 已导出 `src/core/options/options.dart`，`preview_config.dart` 随之传递导出，
无需新增行。确认 `flutter analyze` 无 `unused_import`。

- [ ] **Step 7: 跑测试与分析**

Run: `flutter test && flutter analyze`
Expected: options 9 项（原 4 + 新 5）PASS，累计 168 项全绿，analyze 0 issues。
`purity_test.dart` PASS（`preview_config.dart` 只 import core 内部文件）。

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(videoman): add VmPreviewConfig section and VmPreviewBlocked event"
```

---

## Task 11: `VmPreviewApi` 与 `VmPreviewService`

DESIGN §7.1 的整条数据流：防抖 → 桶对齐 → 网络策略 → 内存同步命中 → 磁盘异步命中 →
按顺序试来源 → 过期结果仍落盘。这是阶段 B 的核心逻辑，全部可在纯 Dart 下测。

**Files:**
- Create: `lib/src/core/preview/api.dart`, `lib/src/core/preview/service.dart`
- Modify: `lib/videoman.dart`
- Test: `test/core/preview/service_test.dart`

**Interfaces:**
- Consumes: Task 2/4/6/7/8/9/10 全部类型
- Produces:
  - `abstract class VmPreviewApi { Stream<VmThumb?> get thumbs; VmThumb? get current; VmThumb? peekAt(Duration position); void requestAt(Duration position); void cancel(); Future<void> clear(); }`
  - `class VmPreviewService implements VmPreviewApi`，构造：

```dart
VmPreviewService({
  required VmPreviewConfig config,
  required VmThumbCache cache,
  required VmNetProbe probe,
  required List<VmThumbSource> sources,
  void Function(VmPreviewBlockReason reason)? onBlocked,
});
```

  外加 `void attach(VmSource? source)`、`Future<void> dispose()`、`@visibleForTesting Future<void> drain()`

- [ ] **Step 1: 写失败测试 `test/core/preview/service_test.dart`**

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/options/preview_config.dart';
import 'package:videoman/src/core/preview/cache.dart';
import 'package:videoman/src/core/preview/models.dart';
import 'package:videoman/src/core/preview/net_probe.dart';
import 'package:videoman/src/core/preview/service.dart';
import 'package:videoman/src/core/preview/source.dart';

/// A [VmThumbSource] returning canned bytes after an optional delay, recording
/// every bucket it was asked for.
///
/// 可选延迟后返回预置字节的 [VmThumbSource]，并记录被请求过的每个桶。
class _FakeSource implements VmThumbSource {
  /// Creates a fake source.
  ///
  /// 创建一个假来源。
  ///
  /// - [name]: diagnostic identifier / 诊断标识
  /// - [answer]: whether this source produces a thumbnail / 该来源是否产出缩略图
  /// - [delay]: artificial latency per request / 每次请求的人造延迟
  _FakeSource({this.name = 'fake', this.answer = true, this.delay = Duration.zero});

  @override
  final String name;

  /// Whether [thumbAt] produces a thumbnail or null.
  ///
  /// [thumbAt] 产出缩略图还是 null。
  bool answer;

  /// Artificial latency applied to every request.
  ///
  /// 每次请求施加的人造延迟。
  Duration delay;

  /// Buckets this source was asked for, in order.
  ///
  /// 按顺序记录该来源被请求过的桶。
  final List<Duration> asked = <Duration>[];

  /// Ordered lifecycle method names invoked on this fake.
  ///
  /// 在该替身上被调用的生命周期方法名有序列表。
  final List<String> calls = <String>[];

  @override
  Future<VmThumb?> thumbAt(VmSource source, Duration bucket) async {
    asked.add(bucket);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (!answer) return null;
    return VmThumb(at: bucket, bytes: Uint8List.fromList([bucket.inSeconds & 0xFF]));
  }

  @override
  Future<void> reset() async => calls.add('reset');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

/// A [VmNetProbe] with a flippable verdict.
///
/// 判定结果可切换的 [VmNetProbe]。
class _SwitchProbe implements VmNetProbe {
  /// Creates a probe answering [verdict].
  ///
  /// 创建一个回答 [verdict] 的探针。
  _SwitchProbe(this.verdict);

  /// The verdict returned by [allowHeavy].
  ///
  /// [allowHeavy] 返回的判定结果。
  bool verdict;

  @override
  Future<bool> allowHeavy() async => verdict;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();

  @override
  Future<void> dispose() async {}
}

void main() {
  const src = VmSource('https://host/a.mp4');
  const noDebounce = VmPreviewConfig(
    debounce: Duration.zero,
    network: VmPreviewNetwork.always,
  );

  late VmMemoryThumbCache cache;
  late _FakeSource source;
  late VmPreviewService service;

  /// Builds a service over the shared fakes with [config].
  ///
  /// 用共享替身与 [config] 构造一个服务。
  VmPreviewService build(VmPreviewConfig config, {VmNetProbe? probe}) {
    return VmPreviewService(
      config: config,
      cache: cache,
      probe: probe ?? AlwaysAllowNetProbe(),
      sources: [source],
      onBlocked: config.onBlocked,
    )..attach(src);
  }

  setUp(() {
    cache = VmMemoryThumbCache();
    source = _FakeSource();
  });

  tearDown(() => service.dispose());

  test('requestAt aligns the position down to the configured bucket', () async {
    service = build(noDebounce);
    service.requestAt(const Duration(seconds: 17));
    await service.drain();
    expect(source.asked, [const Duration(seconds: 10)]);
    expect(service.current!.at, const Duration(seconds: 10));
  });

  test('scrubbing within one bucket only asks the source once', () async {
    service = build(noDebounce);
    service.requestAt(const Duration(seconds: 11));
    await service.drain();
    service.requestAt(const Duration(seconds: 18));
    await service.drain();
    expect(source.asked, [const Duration(seconds: 10)]);
  });

  test('a memory hit is served synchronously by peekAt without any await', () async {
    service = build(noDebounce);
    service.requestAt(const Duration(seconds: 10));
    await service.drain();
    service.requestAt(const Duration(seconds: 40));
    await service.drain();
    expect(service.peekAt(const Duration(seconds: 12))!.at, const Duration(seconds: 10));
  });

  test('resolved thumbs are published on the thumbs stream', () async {
    service = build(noDebounce);
    final seen = <VmThumb?>[];
    final sub = service.thumbs.listen(seen.add);
    service.requestAt(const Duration(seconds: 20));
    await service.drain();
    await Future<void>.delayed(Duration.zero);
    expect(seen.whereType<VmThumb>().map((t) => t.at), contains(const Duration(seconds: 20)));
    await sub.cancel();
  });

  test('debounce collapses a burst of scrub ticks into one request', () async {
    service = build(const VmPreviewConfig(
      debounce: Duration(milliseconds: 40),
      network: VmPreviewNetwork.always,
    ));
    service.requestAt(const Duration(seconds: 10));
    service.requestAt(const Duration(seconds: 20));
    service.requestAt(const Duration(seconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await service.drain();
    expect(source.asked, [const Duration(seconds: 30)]);
  });

  test('a stale result is cached but never published as current', () async {
    source.delay = const Duration(milliseconds: 60);
    service = build(noDebounce);
    service.requestAt(const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    service.requestAt(const Duration(seconds: 20));
    await service.drain();
    expect(service.current!.at, const Duration(seconds: 20));
    expect(
      cache.peek(service.debugKeyFor(const Duration(seconds: 10))!),
      isNotNull,
      reason: 'the superseded bucket still lands in the cache',
    );
  });

  test('extraction runs serially, one request at a time', () async {
    source.delay = const Duration(milliseconds: 30);
    service = build(noDebounce);
    service.requestAt(const Duration(seconds: 10));
    service.requestAt(const Duration(seconds: 20));
    service.requestAt(const Duration(seconds: 30));
    await service.drain();
    expect(source.asked.length, lessThanOrEqualTo(3));
    expect(service.current!.at, const Duration(seconds: 30));
  });

  test('a blocked network refuses without touching any source', () async {
    final reasons = <VmPreviewBlockReason>[];
    service = build(
      VmPreviewConfig(
        debounce: Duration.zero,
        onBlocked: reasons.add,
      ),
      probe: _SwitchProbe(false),
    );
    service.requestAt(const Duration(seconds: 10));
    await service.drain();
    expect(source.asked, isEmpty);
    expect(service.current, isNull);
    expect(reasons, [VmPreviewBlockReason.network]);
  });

  test('a disabled config refuses with the disabled reason', () async {
    final reasons = <VmPreviewBlockReason>[];
    service = build(VmPreviewConfig(
      enabled: false,
      debounce: Duration.zero,
      network: VmPreviewNetwork.always,
      onBlocked: reasons.add,
    ));
    service.requestAt(const Duration(seconds: 10));
    await service.drain();
    expect(source.asked, isEmpty);
    expect(reasons, [VmPreviewBlockReason.disabled]);
  });

  test('no attached source refuses with the noSource reason', () async {
    final reasons = <VmPreviewBlockReason>[];
    service = VmPreviewService(
      config: const VmPreviewConfig(
        debounce: Duration.zero,
        network: VmPreviewNetwork.always,
      ),
      cache: cache,
      probe: AlwaysAllowNetProbe(),
      sources: [source],
      onBlocked: reasons.add,
    );
    service.requestAt(const Duration(seconds: 10));
    await service.drain();
    expect(source.asked, isEmpty);
    expect(reasons, [VmPreviewBlockReason.noSource]);
  });

  test('an empty source chain refuses with the platform reason', () async {
    final reasons = <VmPreviewBlockReason>[];
    service = VmPreviewService(
      config: const VmPreviewConfig(
        debounce: Duration.zero,
        network: VmPreviewNetwork.always,
      ),
      cache: cache,
      probe: AlwaysAllowNetProbe(),
      sources: const <VmThumbSource>[],
      onBlocked: reasons.add,
    )..attach(src);
    service.requestAt(const Duration(seconds: 10));
    await service.drain();
    expect(reasons, [VmPreviewBlockReason.platform]);
  });

  test('sources are tried in order and the first non-null answer wins', () async {
    final first = _FakeSource(name: 'first', answer: false);
    final second = _FakeSource(name: 'second');
    service = VmPreviewService(
      config: noDebounce,
      cache: cache,
      probe: AlwaysAllowNetProbe(),
      sources: [first, second],
    )..attach(src);
    service.requestAt(const Duration(seconds: 10));
    await service.drain();
    expect(first.asked, [const Duration(seconds: 10)]);
    expect(second.asked, [const Duration(seconds: 10)]);
    expect(service.current, isNotNull);
  });

  test('attach resets every source and clears the current thumb', () async {
    service = build(noDebounce);
    service.requestAt(const Duration(seconds: 10));
    await service.drain();
    expect(service.current, isNotNull);
    service.attach(const VmSource('https://host/b.mp4'));
    expect(service.current, isNull);
    expect(source.calls, contains('reset'));
  });

  test('cancel drops the pending request and hides the current thumb', () async {
    service = build(const VmPreviewConfig(
      debounce: Duration(milliseconds: 40),
      network: VmPreviewNetwork.always,
    ));
    service.requestAt(const Duration(seconds: 10));
    service.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await service.drain();
    expect(source.asked, isEmpty);
    expect(service.current, isNull);
  });

  test('a custom cacheKeyBuilder is used for every entry', () async {
    service = VmPreviewService(
      config: VmPreviewConfig(
        debounce: Duration.zero,
        network: VmPreviewNetwork.always,
        cacheKeyBuilder: (s, b, w) => 'custom_${b}_$w',
      ),
      cache: cache,
      probe: AlwaysAllowNetProbe(),
      sources: [source],
    )..attach(src);
    service.requestAt(const Duration(seconds: 20));
    await service.drain();
    expect(cache.peek('custom_20_160'), isNotNull);
  });

  test('clear empties the cache and drops the current thumb', () async {
    service = build(noDebounce);
    service.requestAt(const Duration(seconds: 10));
    await service.drain();
    await service.clear();
    expect(cache.length, 0);
    expect(service.current, isNull);
  });

  test('dispose releases every source and closes the thumbs stream', () async {
    service = build(noDebounce);
    final done = Completer<void>();
    final sub = service.thumbs.listen(null, onDone: done.complete);
    await service.dispose();
    await done.future.timeout(const Duration(seconds: 1));
    expect(source.calls, contains('dispose'));
    await sub.cancel();
    // A second dispose from tearDown must be a no-op.
    //
    // tearDown 里的第二次 dispose 必须是空操作。
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/preview/service_test.dart`
Expected: FAIL — `Error when reading 'lib/src/core/preview/service.dart': No such file or directory`

- [ ] **Step 3: 实现 `lib/src/core/preview/api.dart`**

```dart
import 'models.dart';

/// The scrub-preview capability surface exposed on `VmApi.preview`.
///
/// UI components only ever call [requestAt]/[peekAt] and listen to [thumbs];
/// all policy (debounce, bucketing, network, caching, source order) lives
/// behind this abstraction in the core layer.
///
/// 挂在 `VmApi.preview` 上的拖动预览能力面。
///
/// UI 组件只会调用 [requestAt]/[peekAt] 并监听 [thumbs]；所有策略（防抖、
/// 桶对齐、网络、缓存、来源顺序）都藏在该抽象之后的 core 层里。
abstract class VmPreviewApi {
  /// Emits the thumbnail to display, or null when nothing should be shown.
  ///
  /// 推送应展示的缩略图；无内容可展示时推送 null。
  Stream<VmThumb?> get thumbs;

  /// The thumbnail currently resolved for the active scrub position, if any.
  ///
  /// 当前拖动位置已解析出的缩略图（若有）。
  VmThumb? get current;

  /// Returns the already-resident thumbnail covering [position] without any
  /// I/O, so a bucket that is already cached renders in the same frame.
  ///
  /// 不做任何 I/O，返回已驻留的、覆盖 [position] 的缩略图，使已缓存的桶能在
  /// 同一帧渲染出来。
  ///
  /// - [position]: the scrub position / 拖动位置
  ///
  /// Returns the resident thumbnail, or null when not cached.
  ///
  /// 返回已驻留的缩略图；未缓存时返回 null。
  VmThumb? peekAt(Duration position);

  /// Requests the thumbnail covering [position]; debounced and bucket-aligned.
  ///
  /// 请求覆盖 [position] 的缩略图；带防抖并按桶对齐。
  ///
  /// - [position]: the scrub position / 拖动位置
  void requestAt(Duration position);

  /// Drops the pending request and hides the current thumbnail; called when
  /// the drag ends.
  ///
  /// 丢弃待处理的请求并隐藏当前缩略图；拖动结束时调用。
  void cancel();

  /// Empties the thumbnail cache.
  ///
  /// 清空缩略图缓存。
  Future<void> clear();
}
```

- [ ] **Step 4: 实现 `lib/src/core/preview/service.dart`**

```dart
import 'dart:async';

import 'package:meta/meta.dart';

import '../model/source.dart';
import '../options/preview_config.dart';
import 'api.dart';
import 'cache.dart';
import 'hash.dart';
import 'models.dart';
import 'net_probe.dart';
import 'source.dart';

/// The production [VmPreviewApi]: debounces scrub ticks, aligns them to
/// buckets, enforces the network policy, serves cache hits, and walks the
/// configured source chain — one request in flight at a time.
///
/// A superseded request's result is still written to the cache rather than
/// discarded: the work is already paid for, and the user is very likely to
/// scrub back over that bucket (DESIGN §7.1).
///
/// 生产环境的 [VmPreviewApi]：对拖动 tick 做防抖、按桶对齐、执行网络策略、
/// 优先吃缓存命中，再按配置的来源链依次尝试——同一时刻只有一个请求在飞。
///
/// 被后来者取代的请求，其结果仍会写入缓存而非丢弃：这份开销已经付过了，而且
/// 用户很可能会拖回那个桶（DESIGN §7.1）。
class VmPreviewService implements VmPreviewApi {
  /// Creates a preview service.
  ///
  /// 创建一个预览服务。
  ///
  /// - [config]: the resolved preview configuration / 已解析的预览配置
  /// - [cache]: thumbnail storage / 缩略图存储
  /// - [probe]: connectivity probe consulted under `wifiOnly` / `wifiOnly` 下
  ///   要咨询的连通性探针
  /// - [sources]: ordered source chain / 有序的来源链
  /// - [onBlocked]: refusal callback / 被拒回调
  VmPreviewService({
    required this.config,
    required this.cache,
    required this.probe,
    required this.sources,
    this.onBlocked,
  });

  /// The resolved preview configuration.
  ///
  /// 已解析的预览配置。
  final VmPreviewConfig config;

  /// Thumbnail storage; usually a two-level memory + disk cache.
  ///
  /// 缩略图存储；通常是内存 + 磁盘的两级缓存。
  final VmThumbCache cache;

  /// Connectivity probe consulted under [VmPreviewNetwork.wifiOnly].
  ///
  /// [VmPreviewNetwork.wifiOnly] 下要咨询的连通性探针。
  final VmNetProbe probe;

  /// Ordered source chain; the first non-null answer wins.
  ///
  /// 有序的来源链；第一个非 null 的结果获胜。
  final List<VmThumbSource> sources;

  /// Called whenever a request is refused; null means stay silent.
  ///
  /// 请求被拒绝时的回调；为 null 表示静默。
  final VmPreviewBlockedCallback? onBlocked;

  /// Broadcast sink for [thumbs].
  ///
  /// [thumbs] 的广播出口。
  final StreamController<VmThumb?> _thumbs = StreamController<VmThumb?>.broadcast();

  /// The media currently being previewed, or null before [attach].
  ///
  /// 当前正在预览的媒体；[attach] 之前为 null。
  VmSource? _source;

  /// The debounce timer for the newest scrub tick.
  ///
  /// 最新一次拖动 tick 的防抖计时器。
  Timer? _debounce;

  /// The bucket the user is currently scrubbing over, or null when idle.
  ///
  /// 用户当前拖到的桶；空闲时为 null。
  Duration? _wanted;

  /// Serialises resolution work so only one source request is in flight.
  ///
  /// 把解析工作串行化，保证同一时刻只有一个来源请求在飞。
  Future<void> _queue = Future<void>.value();

  /// The thumbnail currently resolved for [_wanted], if any.
  ///
  /// [_wanted] 当前已解析出的缩略图（若有）。
  VmThumb? _current;

  /// Whether [dispose] has run; further calls are no-ops.
  ///
  /// [dispose] 是否已执行；执行过后所有调用都变为空操作。
  bool _disposed = false;

  @override
  Stream<VmThumb?> get thumbs => _thumbs.stream;

  @override
  VmThumb? get current => _current;

  /// Points the service at [source], resetting every source's per-media state
  /// and dropping the current thumbnail.
  ///
  /// 把服务指向 [source]，重置每个来源与当前媒体相关的状态，并丢弃当前缩略图。
  ///
  /// - [source]: the newly opened media, or null when the player has none /
  ///   新打开的媒体；播放器无媒体时为 null
  void attach(VmSource? source) {
    _source = source;
    _debounce?.cancel();
    _debounce = null;
    _wanted = null;
    _publish(null);
    for (final s in sources) {
      unawaited(s.reset());
    }
  }

  /// Aligns [position] down to the configured bucket size.
  ///
  /// 把 [position] 向下对齐到配置的桶大小。
  ///
  /// - [position]: the raw scrub position / 原始拖动位置
  ///
  /// Returns the bucket-aligned position.
  ///
  /// 返回桶对齐后的位置。
  Duration _bucketOf(Duration position) {
    final step = config.bucket.inMilliseconds;
    if (step <= 0) return position;
    final ms = position.inMilliseconds;
    return Duration(milliseconds: (ms < 0 ? 0 : ms) ~/ step * step);
  }

  /// Builds the cache key for [bucket] using the configured strategy.
  ///
  /// 用配置的策略为 [bucket] 生成缓存 key。
  ///
  /// - [bucket]: the bucket-aligned position / 桶对齐位置
  ///
  /// Returns the cache key, or null when no media is attached.
  ///
  /// 返回缓存 key；未附着媒体时返回 null。
  String? _keyFor(Duration bucket) {
    final src = _source;
    if (src == null) return null;
    final builder = config.cacheKeyBuilder ?? defaultCacheKey;
    return builder(src.uri, bucket.inSeconds, config.frameWidth);
  }

  /// Exposes [_keyFor] to tests that assert on cache contents.
  ///
  /// 把 [_keyFor] 暴露给需要断言缓存内容的测试。
  ///
  /// - [bucket]: the bucket-aligned position / 桶对齐位置
  ///
  /// Returns the cache key, or null when no media is attached.
  ///
  /// 返回缓存 key；未附着媒体时返回 null。
  @visibleForTesting
  String? debugKeyFor(Duration bucket) => _keyFor(bucket);

  /// Publishes [thumb] as the current preview.
  ///
  /// 把 [thumb] 作为当前预览发布出去。
  ///
  /// - [thumb]: the thumbnail to show, or null to hide / 要展示的缩略图，
  ///   null 表示隐藏
  void _publish(VmThumb? thumb) {
    _current = thumb;
    if (!_thumbs.isClosed) _thumbs.add(thumb);
  }

  /// Reports [reason] to [onBlocked], swallowing host callback errors.
  ///
  /// 把 [reason] 报给 [onBlocked]，并吞掉宿主回调抛出的异常。
  ///
  /// - [reason]: why the request was refused / 被拒原因
  void _block(VmPreviewBlockReason reason) {
    final cb = onBlocked;
    if (cb == null) return;
    try {
      cb(reason);
    } on Object {
      // A host callback must never break the preview pipeline.
      //
      // 宿主回调绝不能打断预览流水线。
    }
  }

  @override
  VmThumb? peekAt(Duration position) {
    final bucket = _bucketOf(position);
    final key = _keyFor(bucket);
    if (key == null) return null;
    final bytes = cache.peek(key);
    if (bytes == null) return null;
    return VmThumb(at: bucket, bytes: bytes);
  }

  @override
  void requestAt(Duration position) {
    if (_disposed) return;
    final bucket = _bucketOf(position);
    _wanted = bucket;

    final hit = peekAt(bucket);
    if (hit != null) {
      _publish(hit);
      return;
    }

    _debounce?.cancel();
    if (config.debounce <= Duration.zero) {
      _enqueue(bucket);
    } else {
      _debounce = Timer(config.debounce, () => _enqueue(bucket));
    }
  }

  /// Appends resolution of [bucket] to the serial queue.
  ///
  /// 把 [bucket] 的解析工作追加到串行队列。
  ///
  /// - [bucket]: the bucket-aligned position / 桶对齐位置
  void _enqueue(Duration bucket) {
    _queue = _queue.then((_) => _resolve(bucket));
  }

  /// Resolves [bucket] through cache then the source chain, publishing it only
  /// while it is still the bucket the user wants.
  ///
  /// 依次通过缓存与来源链解析 [bucket]；仅当它仍是用户想要的桶时才发布。
  ///
  /// - [bucket]: the bucket-aligned position / 桶对齐位置
  Future<void> _resolve(Duration bucket) async {
    if (_disposed) return;
    if (!config.enabled) {
      _block(VmPreviewBlockReason.disabled);
      return;
    }
    final src = _source;
    if (src == null) {
      _block(VmPreviewBlockReason.noSource);
      return;
    }
    if (sources.isEmpty) {
      _block(VmPreviewBlockReason.platform);
      return;
    }
    if (!await previewAllowedOn(config.network, probe)) {
      _block(VmPreviewBlockReason.network);
      return;
    }

    final key = _keyFor(bucket);
    if (key == null) return;

    final cached = await cache.read(key);
    if (cached != null) {
      if (_wanted == bucket) _publish(VmThumb(at: bucket, bytes: cached));
      return;
    }

    for (final source in sources) {
      VmThumb? thumb;
      try {
        thumb = await source.thumbAt(src, bucket);
      } on Object {
        thumb = null;
      }
      if (thumb == null) continue;
      // Cache first, publish second: a superseded bucket still earns its place
      // in the cache, it just never becomes the visible thumbnail.
      //
      // 先缓存再发布：被取代的桶依然值得留在缓存里，只是不会成为可见的缩略图。
      await cache.write(key, thumb.bytes);
      if (_wanted == bucket) _publish(thumb);
      return;
    }
  }

  @override
  void cancel() {
    _debounce?.cancel();
    _debounce = null;
    _wanted = null;
    _publish(null);
  }

  @override
  Future<void> clear() async {
    await cache.clear();
    _publish(null);
  }

  /// Waits for every queued resolution to settle; test-only.
  ///
  /// 等待队列中全部解析工作完成；仅供测试使用。
  @visibleForTesting
  Future<void> drain() => _queue;

  /// Releases the service, its sources and its cache.
  ///
  /// Wipes the cache first when [VmPreviewConfig.clearOnDispose] is set, so a
  /// killed process does not leave a temp directory full of thumbnails.
  ///
  /// 释放服务、其来源与其缓存。
  ///
  /// [VmPreviewConfig.clearOnDispose] 打开时先清空缓存，避免进程被杀后临时
  /// 目录里堆满缩略图。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _debounce?.cancel();
    _debounce = null;
    _wanted = null;
    await _queue;
    for (final s in sources) {
      await s.dispose();
    }
    if (config.clearOnDispose) await cache.clear();
    await cache.dispose();
    await probe.dispose();
    await _thumbs.close();
  }
}
```

- [ ] **Step 5: barrel 增补导出**

`lib/videoman.dart` 在 `export 'src/core/preview/cache.dart';` 之前插入：

```dart
export 'src/core/preview/api.dart';
```

在 `export 'src/core/preview/source.dart';` 之前插入：

```dart
export 'src/core/preview/service.dart';
```

- [ ] **Step 6: 跑测试确认通过**

Run: `flutter test test/core/preview/service_test.dart && flutter analyze`
Expected: 17 项 PASS，analyze 0 issues

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(videoman): add VmPreviewApi and debounced bucket-aligned preview service"
```

---


## Task 12: 接进 `VmApi` / `VmEngine`，并补上 platform_impl 装配

DESIGN §4.1 的 `VmPreviewApi get preview` 在阶段 A 被明确推迟（`api.dart` 注释里写着「阶段 A 的
`VmApi` 暂不含 `preview` getter（阶段 B 加）」），本任务补上。

**`createVmEngine()` 已经存在，本任务只扩展它**：阶段 A 收口后的 `fix(videoman): wire real
platform adapters, restoring brightness/PiP/orientation`（commit `9c2d4f0`）已经建了
`lib/src/platform_impl/wiring.dart` 与 `createVmEngine({kernel, options, interceptors,
brightness, pip, orientation})`，接好了 brightness/PiP/orientation 三个真实端口，并从
`lib/videoman.dart` 导出。阶段 B 要做的只是在同一个函数上**追加**预览用的三个可选端口参数
（`VmThumbDirProvider? thumbDir`、`VmFrameExtractor? extractor`、`VmHttpFetcher? fetcher`），
默认接入 Task 5/9 的真实平台实现，不改、不删已有的 brightness/pip/orientation 参数。

**Files:**
- Modify: `lib/src/platform_impl/wiring.dart`, `lib/src/core/api.dart`, `lib/src/core/engine.dart`,
  `test/support/fake_api.dart`
- Test: `test/core/engine_test.dart`（追加 5 项，不动既有项）

**Interfaces:**
- Consumes: Task 4–11 全部类型
- Produces:
  - `VmApi.preview` → `VmPreviewApi`
  - `VmEngine` 新增可选构造参数 `VmThumbDirProvider? thumbDir`、`VmFrameExtractor? extractor`、`VmHttpFetcher? fetcher`
  - `createVmEngine()`（已存在，`platform_impl/wiring.dart`）新增三个可选参数：
    `VmThumbDirProvider? thumbDir`、`VmFrameExtractor? extractor`、`VmHttpFetcher? fetcher`，
    默认分别接入 `TempThumbDirProvider()`、`MpvFrameExtractor()`、（`fetcher` 留空即走
    `VmEngine` 自己的 `IoHttpFetcher()` 兜底）；原有的 `kernel`/`options`/`interceptors`/
    `brightness`/`pip`/`orientation` 参数与行为不变
  - `class FakePreviewApi implements VmPreviewApi`（测试替身，带 `push(VmThumb?)`、`peekResult`、`lastRequestedAt`、`calls`）
  - `FakeVmApi.preview` → `FakePreviewApi`

- [ ] **Step 1: 追加失败测试到 `test/core/engine_test.dart`**

顶部 import 区补：

```dart
import 'package:videoman/src/core/options/preview_config.dart';
import 'package:videoman/src/core/preview/net_probe.dart';
```

在 `main()` 末尾（`class _CancelSeek` 之前）追加：

```dart
  test('preview is exposed on the api surface', () {
    expect(e.preview, isNotNull);
    expect(e.preview.current, isNull);
  });

  test('opening a source attaches it to the preview service', () async {
    await e.open(const VmSource('https://host/a.mp4'));
    e.preview.requestAt(const Duration(seconds: 5));
    // With no sources able to serve this media the request resolves to
    // nothing, but attaching must not throw and must clear any old thumb.
    //
    // 没有来源能服务该媒体时请求解析为空，但 attach 不得抛异常，且必须清掉
    // 旧缩略图。
    expect(e.preview.current, isNull);
  });

  test('a disabled preview config emits VmPreviewBlocked on the event stream', () async {
    final e2 = VmEngine(
      kernel: FakeKernel(),
      options: const VmOptions(
        preview: VmPreviewConfig(
          enabled: false,
          debounce: Duration.zero,
          network: VmPreviewNetwork.always,
        ),
      ),
    );
    final events = <VmEvent>[];
    final sub = e2.events.listen(events.add);
    await e2.open(const VmSource('https://host/a.mp4'));
    e2.preview.requestAt(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(events.whereType<VmPreviewBlocked>(), isNotEmpty);
    expect(
      events.whereType<VmPreviewBlocked>().first.reason,
      VmPreviewBlockReason.disabled,
    );
    await sub.cancel();
    await e2.dispose();
  });

  test('the configured onBlocked callback also fires', () async {
    final reasons = <VmPreviewBlockReason>[];
    final e2 = VmEngine(
      kernel: FakeKernel(),
      options: VmOptions(
        preview: VmPreviewConfig(
          enabled: false,
          debounce: Duration.zero,
          network: VmPreviewNetwork.always,
          onBlocked: reasons.add,
        ),
      ),
    );
    await e2.open(const VmSource('https://host/a.mp4'));
    e2.preview.requestAt(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(reasons, [VmPreviewBlockReason.disabled]);
    await e2.dispose();
  });

  test('disposing the engine disposes the preview service', () async {
    final e2 = VmEngine(kernel: FakeKernel());
    await e2.dispose();
    // A closed preview stream is the observable proof the service was torn
    // down; requesting after dispose must be a silent no-op.
    //
    // 预览流已关闭即是服务已销毁的可观测证据；dispose 之后再请求必须静默无操作。
    e2.preview.requestAt(const Duration(seconds: 1));
    expect(e2.preview.current, isNull);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/engine_test.dart`
Expected: FAIL — `The getter 'preview' isn't defined for the class 'VmEngine'`；既有项仍 PASS

- [ ] **Step 3: 在 `VmApi` 上声明 `preview`**

`lib/src/core/api.dart`：import 区加 `import 'preview/api.dart';`；在 `Object? get renderHandle;`
之后插入：

```dart
  /// The scrub-preview capability surface: thumbnail requests, the resolved
  /// thumbnail stream, and cache control.
  ///
  /// 拖动预览能力面：缩略图请求、已解析缩略图的流，以及缓存控制。
  VmPreviewApi get preview;
```

- [ ] **Step 4: 在 `VmEngine` 里装配预览服务**

`lib/src/core/engine.dart`：

1. import 区补：

```dart
import 'options/preview_config.dart';
import 'preview/api.dart';
import 'preview/cache.dart';
import 'preview/dir_provider.dart';
import 'preview/disk_cache.dart';
import 'preview/extractor.dart';
import 'preview/fetcher.dart';
import 'preview/net_probe.dart';
import 'preview/platform_kind.dart';
import 'preview/service.dart';
import 'preview/source.dart';
import 'preview/two_level_cache.dart';
import 'preview/vtt_source.dart';
```

2. 字段（放在 `_orientation` 之后）：

```dart
  /// The scrub-preview service assembled from [VmOptions.preview].
  ///
  /// 依据 [VmOptions.preview] 装配出来的拖动预览服务。
  late final VmPreviewService _previewService;
```

3. 构造签名加三个可选参数（放在 `orientation` 之后）：

```dart
    VmThumbDirProvider? thumbDir,
    VmFrameExtractor? extractor,
    VmHttpFetcher? fetcher,
```

并在构造函数文档注释里补一段：

```dart
  /// [thumbDir]/[extractor]/[fetcher] supply the platform-side pieces of the
  /// preview pipeline; each may be omitted, in which case the corresponding
  /// capability degrades (no disk cache / no frame extraction / a `dart:io`
  /// HTTP client) rather than failing.
  ///
  /// [thumbDir]/[extractor]/[fetcher] 提供预览流水线的平台侧零件；三者均可
  /// 省略，省略时对应能力降级（无磁盘缓存 / 无抽帧兜底 / 使用 `dart:io`
  /// 的 HTTP 客户端）而不是报错。
```

4. 构造体末尾（`_errorSub = ...` 之后）加：

```dart
    _previewService = _buildPreview(
      thumbDir: thumbDir,
      extractor: extractor,
      fetcher: fetcher,
    );
```

5. 新增两个私有方法与 getter：

```dart
  @override
  VmPreviewApi get preview => _previewService;

  /// Assembles the preview service from [VmOptions.preview] plus the
  /// platform-side pieces the host injected.
  ///
  /// Every injection point in [VmPreviewConfig] wins over the built-in
  /// default; a missing platform piece degrades that one capability instead of
  /// disabling preview outright.
  ///
  /// 依据 [VmOptions.preview] 与宿主注入的平台侧零件装配预览服务。
  ///
  /// [VmPreviewConfig] 里的每个注入点都优先于内置默认；缺失某个平台零件只会
  /// 让该项能力降级，而不会整体关闭预览。
  ///
  /// - [thumbDir]: disk-cache directory resolver / 磁盘缓存目录解析器
  /// - [extractor]: frame extractor / 抽帧器
  /// - [fetcher]: HTTP fetcher for VTT tracks and sprites / 拉取 VTT 轨与
  ///   雪碧图的 HTTP 客户端
  ///
  /// Returns the assembled service.
  ///
  /// 返回装配好的服务。
  VmPreviewService _buildPreview({
    VmThumbDirProvider? thumbDir,
    VmFrameExtractor? extractor,
    VmHttpFetcher? fetcher,
  }) {
    final cfg = options.preview;
    final dir = cfg.dirProvider ??
        (cfg.diskDir != null ? FixedThumbDirProvider(cfg.diskDir!) : thumbDir);
    final cache = cfg.cache ??
        (dir == null
            ? VmMemoryThumbCache(maxEntries: cfg.memMaxEntries)
            : VmTwoLevelCache(
                memory: VmMemoryThumbCache(maxEntries: cfg.memMaxEntries),
                disk: VmDiskThumbCache(dir: dir, maxBytes: cfg.diskMaxBytes),
              ));
    return VmPreviewService(
      config: cfg,
      cache: cache,
      probe: cfg.probe ?? AlwaysAllowNetProbe(),
      sources: cfg.sources ?? _defaultThumbSources(cfg, extractor, fetcher),
      onBlocked: _onPreviewBlocked,
    );
  }

  /// Builds the built-in `[vtt, extract]` source chain, honouring
  /// [VmPreviewConfig.vttEnabled], [VmPreviewConfig.extractFallback] and
  /// [VmPreviewConfig.extractPlatforms].
  ///
  /// 构建内置的 `[vtt, extract]` 来源链，遵循 [VmPreviewConfig.vttEnabled]、
  /// [VmPreviewConfig.extractFallback] 与 [VmPreviewConfig.extractPlatforms]。
  ///
  /// - [cfg]: the preview configuration / 预览配置
  /// - [extractor]: host-injected frame extractor / 宿主注入的抽帧器
  /// - [fetcher]: host-injected HTTP fetcher / 宿主注入的 HTTP 客户端
  ///
  /// Returns the ordered source chain, possibly empty.
  ///
  /// 返回有序的来源链，可能为空。
  List<VmThumbSource> _defaultThumbSources(
    VmPreviewConfig cfg,
    VmFrameExtractor? extractor,
    VmHttpFetcher? fetcher,
  ) {
    final chain = <VmThumbSource>[];
    if (cfg.vttEnabled) {
      final fixed = cfg.vttUrl;
      chain.add(VmVttThumbSource(
        fetcher: fetcher ?? IoHttpFetcher(),
        resolveUrl: cfg.vttUrlResolver ??
            (fixed == null ? defaultVttUrl : (_) => Uri.tryParse(fixed)),
      ));
    }
    final ex = cfg.extractor ?? extractor;
    if (cfg.extractFallback &&
        ex != null &&
        cfg.extractPlatforms.contains(currentPlatformKind())) {
      chain.add(VmExtractorThumbSource(
        extractor: ex,
        width: cfg.frameWidth,
        hwdec: cfg.hwdec,
      ));
    }
    return chain;
  }

  /// Publishes a preview refusal on [events] and forwards it to the
  /// host callback.
  ///
  /// 把一次预览拒绝发布到 [events] 上，并转发给宿主回调。
  ///
  /// - [reason]: why the request was refused / 被拒原因
  void _onPreviewBlocked(VmPreviewBlockReason reason) {
    if (!_events.isClosed) _events.add(VmPreviewBlocked(reason));
    final cb = options.preview.onBlocked;
    if (cb == null) return;
    try {
      cb(reason);
    } on Object {
      // A host callback must never break the engine.
      //
      // 宿主回调绝不能打断 engine。
    }
  }
```

6. `open()` 里在 `_source = source;` 之后插入 `_previewService.attach(source);`。
7. `dispose()` 里在 `await _kernel.dispose();` **之前**插入 `await _previewService.dispose();`。

- [ ] **Step 5: 扩展 `lib/src/platform_impl/wiring.dart`（现有文件，只加预览三端口）**

这是 `9c2d4f0` 落地后的**当前文件全文**（不要从零重写，下面的 diff 建立在它之上）：

```dart
// Wires a [VmEngine] to the real platform adapters implemented under
// `lib/src/platform_impl/`. This file — not `core/engine.dart` — is the only
// place allowed to reference those adapters, since `lib/src/core/**` must
// never import `package:flutter/*` or any `platform_impl/*` file (enforced
// by `test/core/purity_test.dart`).
//
// 把 [VmEngine] 接到 `lib/src/platform_impl/` 下的真实平台适配器。只有本文件
// （而非 `core/engine.dart`）允许引用这些适配器，因为 `lib/src/core/**` 绝不能
// 引入 `package:flutter/*` 或任何 `platform_impl/*` 文件（由
// `test/core/purity_test.dart` 强制检查）。

import '../core/engine.dart';
import '../core/interceptor/interceptor.dart';
import '../core/kernel/kernel.dart';
import '../core/options/options.dart';
import '../core/platform/ports.dart';
import 'brightness_impl.dart';
import 'orientation_impl.dart';
import 'pip_impl.dart';

/// Creates a [VmEngine] wired to the real platform adapters
/// ([ScreenBrightnessPort], [ChannelPipPort], [SystemChromeOrientationPort])
/// instead of [VmEngine]'s own noop/fallback defaults.
///
/// [VmEngine]'s bare constructor intentionally defaults to zero-dependency
/// noop ports so it stays usable from pure-Dart unit tests that can't touch
/// platform channels; app code should call this factory instead so the
/// brightness-drag gesture, PiP, and fullscreen-orientation features actually
/// work. Any of [brightness], [pip], or [orientation] can still be overridden
/// (e.g. with a fake, in a widget test that exercises the real engine
/// wiring).
///
/// 创建一个接入真实平台适配器（[ScreenBrightnessPort]、[ChannelPipPort]、
/// [SystemChromeOrientationPort]）的 [VmEngine]，而非使用 [VmEngine] 自身的
/// 空/兜底默认实现。
///
/// [VmEngine] 的裸构造函数刻意默认使用零依赖的空端口，以便纯 Dart 单测（无法
/// 触达平台通道）也能直接使用；app 代码应改用本工厂函数，这样亮度拖拽手势、
/// 画中画、全屏方向这些功能才能真正生效。[brightness]、[pip]、[orientation]
/// 三者仍可分别覆盖（例如在验证真实 engine 接线的 widget 测试中传入 fake）。
///
/// - [kernel]: the playback kernel; defaults to a new `MpvKernel` (see
///   [VmEngine.new]) / 播放内核，省略时默认新建 `MpvKernel`（见
///   [VmEngine.new]）
/// - [options]: engine configuration / engine 配置
/// - [interceptors]: interceptor chain consulted before open/seek/play /
///   在 open/seek/play 前咨询的拦截链
/// - [brightness]: overrides the real [ScreenBrightnessPort] default /
///   覆盖默认的真实 [ScreenBrightnessPort]
/// - [pip]: overrides the real [ChannelPipPort] default / 覆盖默认的真实
///   [ChannelPipPort]
/// - [orientation]: overrides the real [SystemChromeOrientationPort] default
///   / 覆盖默认的真实 [SystemChromeOrientationPort]
///
/// Returns a [VmEngine] ready for use by app code.
///
/// 返回一个可供 app 代码直接使用的 [VmEngine]。
VmEngine createVmEngine({
  VmKernel? kernel,
  VmOptions options = const VmOptions(),
  List<VmInterceptor> interceptors = const [],
  VmBrightnessPort? brightness,
  VmPipPort? pip,
  VmOrientationPort? orientation,
}) {
  return VmEngine(
    kernel: kernel,
    options: options,
    interceptors: interceptors,
    brightness: brightness ?? ScreenBrightnessPort(),
    pip: pip ?? ChannelPipPort(),
    orientation: orientation ?? SystemChromeOrientationPort(),
  );
}
```

改动：加三个 import（`mpv_extractor_impl.dart`、`net_probe_impl.dart`、`thumb_dir_impl.dart`），
给 `createVmEngine` 追加 `thumbDir`/`extractor`/`fetcher` 三个可选参数并接入默认实现，
同时把 `options.preview.probe` 缺省接上 `ConnectivityNetProbe()`。**`kernel`/`options`/
`interceptors`/`brightness`/`pip`/`orientation` 六个既有参数与其默认值一字不动**——阶段 B
只做增量。改完后的完整文件：

```dart
import '../core/engine.dart';
import '../core/interceptor/interceptor.dart';
import '../core/kernel/kernel.dart';
import '../core/options/options.dart';
import '../core/platform/ports.dart';
import '../core/preview/dir_provider.dart';
import '../core/preview/extractor.dart';
import '../core/preview/fetcher.dart';
import 'brightness_impl.dart';
import 'mpv_extractor_impl.dart';
import 'net_probe_impl.dart';
import 'orientation_impl.dart';
import 'pip_impl.dart';
import 'thumb_dir_impl.dart';

/// Creates a [VmEngine] wired to the real platform adapters
/// ([ScreenBrightnessPort], [ChannelPipPort], [SystemChromeOrientationPort],
/// and — since phase B — [VmThumbDirProvider]/[VmFrameExtractor] for scrub
/// preview) instead of [VmEngine]'s own noop/fallback defaults.
///
/// [VmEngine]'s bare constructor intentionally defaults to zero-dependency
/// noop ports so it stays usable from pure-Dart unit tests that can't touch
/// platform channels; app code should call this factory instead so the
/// brightness-drag gesture, PiP, fullscreen-orientation, and scrub-preview
/// thumbnails actually work. Any port can still be overridden (e.g. with a
/// fake, in a widget test that exercises the real engine wiring).
///
/// 创建一个接入真实平台适配器（[ScreenBrightnessPort]、[ChannelPipPort]、
/// [SystemChromeOrientationPort]，以及阶段 B 起新增的拖动预览端口
/// [VmThumbDirProvider]/[VmFrameExtractor]）的 [VmEngine]，而非使用 [VmEngine]
/// 自身的空/兜底默认实现。
///
/// [VmEngine] 的裸构造函数刻意默认使用零依赖的空端口，以便纯 Dart 单测（无法
/// 触达平台通道）也能直接使用；app 代码应改用本工厂函数，这样亮度拖拽手势、
/// 画中画、全屏方向、拖动预览缩略图这些功能才能真正生效。每个端口仍可分别
/// 覆盖（例如在验证真实 engine 接线的 widget 测试中传入 fake）。
///
/// - [kernel]: the playback kernel; defaults to a new `MpvKernel` (see
///   [VmEngine.new]) / 播放内核，省略时默认新建 `MpvKernel`（见
///   [VmEngine.new]）
/// - [options]: engine configuration / engine 配置
/// - [interceptors]: interceptor chain consulted before open/seek/play /
///   在 open/seek/play 前咨询的拦截链
/// - [brightness]: overrides the real [ScreenBrightnessPort] default /
///   覆盖默认的真实 [ScreenBrightnessPort]
/// - [pip]: overrides the real [ChannelPipPort] default / 覆盖默认的真实
///   [ChannelPipPort]
/// - [orientation]: overrides the real [SystemChromeOrientationPort] default
///   / 覆盖默认的真实 [SystemChromeOrientationPort]
/// - [thumbDir]: overrides the real [TempThumbDirProvider] default used for
///   the on-disk thumbnail cache / 覆盖默认的真实 [TempThumbDirProvider]（磁盘
///   缩略图缓存目录）
/// - [extractor]: overrides the real [MpvFrameExtractor] default used as the
///   frame-extraction fallback source / 覆盖默认的真实 [MpvFrameExtractor]
///   （抽帧兜底来源）
/// - [fetcher]: overrides the HTTP fetcher used to pull WebVTT tracks and
///   sprites; left null, [VmEngine] falls back to its own `IoHttpFetcher()` /
///   覆盖拉取 WebVTT 轨与雪碧图的 HTTP 客户端；留空则由 [VmEngine] 自己兜底为
///   `IoHttpFetcher()`
///
/// Returns a [VmEngine] ready for use by app code.
///
/// 返回一个可供 app 代码直接使用的 [VmEngine]。
VmEngine createVmEngine({
  VmKernel? kernel,
  VmOptions options = const VmOptions(),
  List<VmInterceptor> interceptors = const [],
  VmBrightnessPort? brightness,
  VmPipPort? pip,
  VmOrientationPort? orientation,
  VmThumbDirProvider? thumbDir,
  VmFrameExtractor? extractor,
  VmHttpFetcher? fetcher,
}) {
  return VmEngine(
    kernel: kernel,
    options: options.preview.probe == null
        ? options.copyWith(preview: options.preview.copyWith(probe: ConnectivityNetProbe()))
        : options,
    interceptors: interceptors,
    brightness: brightness ?? ScreenBrightnessPort(),
    pip: pip ?? ChannelPipPort(),
    orientation: orientation ?? SystemChromeOrientationPort(),
    thumbDir: thumbDir ?? const TempThumbDirProvider(),
    extractor: extractor ?? MpvFrameExtractor(),
    fetcher: fetcher,
  );
}
```

- [ ] **Step 6: 给 `FakeVmApi` 加 `preview`**

`test/support/fake_api.dart`：import 区补

```dart
import 'package:videoman/src/core/preview/api.dart';
import 'package:videoman/src/core/preview/models.dart';
```

在 `FakeVmApi` 类之后追加：

```dart
/// A test double for [VmPreviewApi] that records requests and lets tests push
/// thumbnails into the stream.
///
/// [VmPreviewApi] 的测试替身：记录请求，并允许测试向流中推送缩略图。
class FakePreviewApi implements VmPreviewApi {
  /// Backing controller for [thumbs].
  ///
  /// [thumbs] 的底层控制器。
  final StreamController<VmThumb?> _thumbs = StreamController<VmThumb?>.broadcast();

  /// Ordered method names invoked on this fake.
  ///
  /// 在该替身上被调用的方法名有序列表。
  final List<String> calls = <String>[];

  /// The argument of the most recent [requestAt] call.
  ///
  /// 最近一次 [requestAt] 调用的参数。
  Duration? lastRequestedAt;

  /// The value [peekAt] returns; settable by tests, defaults to null.
  ///
  /// [peekAt] 的返回值；可由测试赋值，默认 null。
  VmThumb? peekResult;

  /// The thumbnail most recently pushed via [push].
  ///
  /// 最近一次通过 [push] 推送的缩略图。
  VmThumb? _current;

  @override
  Stream<VmThumb?> get thumbs => _thumbs.stream;

  @override
  VmThumb? get current => _current;

  @override
  VmThumb? peekAt(Duration position) {
    calls.add('peekAt');
    return peekResult;
  }

  @override
  void requestAt(Duration position) {
    calls.add('requestAt');
    lastRequestedAt = position;
  }

  @override
  void cancel() => calls.add('cancel');

  @override
  Future<void> clear() async => calls.add('clear');

  /// Pushes [thumb] to [thumbs] and makes it the [current] value.
  ///
  /// 把 [thumb] 推送到 [thumbs] 并设为 [current]。
  ///
  /// - [thumb]: the thumbnail to publish, or null to hide / 要发布的缩略图，
  ///   null 表示隐藏
  void push(VmThumb? thumb) {
    _current = thumb;
    _thumbs.add(thumb);
  }

  /// Closes the backing stream.
  ///
  /// 关闭底层流。
  Future<void> dispose() => _thumbs.close();
}
```

并在 `FakeVmApi` 里加字段与 getter：

```dart
  /// The preview test double this fake exposes.
  ///
  /// 该假对象暴露的预览测试替身。
  @override
  final FakePreviewApi preview = FakePreviewApi();
```

`FakeVmApi.dispose()` 里在 `await _uiState.close();` 之后加 `await preview.dispose();`。

- [ ] **Step 7: 跑测试与分析**

`export 'src/platform_impl/wiring.dart';` 已经在 `lib/videoman.dart` 里（`9c2d4f0` 加的），
本任务不新增导出行——先 `grep -n "export 'src/platform_impl/wiring.dart'" lib/videoman.dart`
确认这行还在，再跑：

Run: `flutter test && flutter analyze`
Expected: engine 新增 5 项 PASS，累计 190 项全绿，analyze 0 issues；`test/platform_impl/wiring_test.dart`
原有 3 项（`9c2d4f0` 加的）仍 PASS。`purity_test.dart` PASS（`engine.dart` 只 import core
内部文件；插件全在 `wiring.dart`）。

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(videoman): expose preview on VmApi and wire platform implementations via createVmEngine"
```

---

## Task 13: 预览气泡组件与默认皮肤

DESIGN §5.4 的 `bottomAbove preview` + §6.1「气泡外观 | 默认组件 | — | patch `preview`」。
`VmSlot.bottomAbove` 自阶段 A 起一直是空的，就是给这个组件留的。

**Files:**
- Create: `lib/src/ui/components/preview.dart`
- Modify: `lib/src/ui/skins/default_skin.dart`, `lib/videoman.dart`
- Test: `test/ui/preview_test.dart`, `test/ui/skin_test.dart`（追加 1 项）

**Interfaces:**
- Consumes: `VmApi`（含 Task 12 的 `preview`）、`VmThumb`/`VmThumbCrop`（Task 2）、`VmUiSelector`、`VmComponent`、`VmSlot`、`formatDuration`
- Produces: `class PreviewComponent extends VmComponent`（`name` = `'preview'`，`slot` = `VmSlot.bottomAbove`）

- [ ] **Step 1: 写失败测试 `test/ui/preview_test.dart`**

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/preview/models.dart';
import 'package:videoman/src/core/state/ui_state.dart';
import 'package:videoman/src/ui/components/preview.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// A 1x1 transparent PNG — the smallest payload `Image.memory` will decode.
///
/// 一张 1x1 透明 PNG——`Image.memory` 能解码的最小负载。
final Uint8List _png = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  late FakeVmApi api;

  setUp(() => api = FakeVmApi());
  tearDown(() => api.dispose());

  testWidgets('renders nothing while previewAt is null', (t) async {
    await pumpComponent(t, api, PreviewComponent());
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining(':'), findsNothing);
  });

  testWidgets('shows the formatted scrub timestamp once previewAt is set', (t) async {
    await pumpComponent(t, api, PreviewComponent());
    api.pushUi(const VmUiState(dragging: true, previewAt: Duration(seconds: 65)));
    await t.pump();
    expect(find.text('01:05'), findsOneWidget);
  });

  testWidgets('requests the thumbnail for the scrub position', (t) async {
    await pumpComponent(t, api, PreviewComponent());
    api.pushUi(const VmUiState(dragging: true, previewAt: Duration(seconds: 42)));
    await t.pump();
    expect(api.preview.calls, contains('requestAt'));
    expect(api.preview.lastRequestedAt, const Duration(seconds: 42));
  });

  testWidgets('renders a pushed thumbnail as an image', (t) async {
    await pumpComponent(t, api, PreviewComponent());
    api.pushUi(const VmUiState(dragging: true, previewAt: Duration(seconds: 10)));
    await t.pump();
    expect(find.byType(Image), findsNothing);
    api.preview.push(VmThumb(at: const Duration(seconds: 10), bytes: _png));
    await t.pump();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a synchronous cache hit renders without waiting for the stream', (t) async {
    api.preview.peekResult = VmThumb(at: const Duration(seconds: 10), bytes: _png);
    await pumpComponent(t, api, PreviewComponent());
    api.pushUi(const VmUiState(dragging: true, previewAt: Duration(seconds: 10)));
    await t.pump();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a cropped sprite is clipped to the crop rectangle', (t) async {
    await pumpComponent(t, api, PreviewComponent());
    api.pushUi(const VmUiState(dragging: true, previewAt: Duration(seconds: 10)));
    await t.pump();
    api.preview.push(VmThumb(
      at: const Duration(seconds: 10),
      bytes: _png,
      crop: const VmThumbCrop(x: 160, y: 0, w: 160, h: 90),
    ));
    await t.pump();
    final clip = t.widget<ClipRect>(find.byKey(const ValueKey('vmPreviewClip')));
    expect(clip, isNotNull);
    final box = t.getSize(find.byKey(const ValueKey('vmPreviewClip')));
    expect(box.width / box.height, closeTo(160 / 90, 0.01));
  });

  testWidgets('clearing previewAt hides the bubble again', (t) async {
    await pumpComponent(t, api, PreviewComponent());
    api.pushUi(const VmUiState(dragging: true, previewAt: Duration(seconds: 10)));
    await t.pump();
    api.preview.push(VmThumb(at: const Duration(seconds: 10), bytes: _png));
    await t.pump();
    expect(find.byType(Image), findsOneWidget);
    api.pushUi(const VmUiState());
    await t.pump();
    expect(find.byType(Image), findsNothing);
    expect(api.preview.calls, contains('cancel'));
  });

  testWidgets('the component is addressable at path "preview" in slot bottomAbove', (t) async {
    final c = PreviewComponent();
    expect(c.name, 'preview');
    expect(c.slot.name, 'bottomAbove');
    expect(c.children, isEmpty);
  });
}
```

- [ ] **Step 2: 追加失败测试到 `test/ui/skin_test.dart`**

在 `main()` 末尾追加：

```dart
  test('the default tree mounts the preview bubble in the bottomAbove slot', () {
    final tree = const VmDefaultSkin().components(const VmState());
    final preview = tree.firstWhere((c) => c.name == 'preview');
    expect(preview.slot, VmSlot.bottomAbove);
  });
```

顶部若缺 `import 'package:videoman/src/ui/slots/slot.dart';` 则补上。

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/ui/preview_test.dart test/ui/skin_test.dart`
Expected: FAIL — `Error when reading 'lib/src/ui/components/preview.dart': No such file or directory`

- [ ] **Step 4: 实现 `lib/src/ui/components/preview.dart`**

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/preview/models.dart';
import '../../core/state/ui_state.dart';
import '../format.dart';
import '../slots/component.dart';
import '../slots/slot.dart';

/// The scrub-preview bubble: a thumbnail plus the target timestamp, floating
/// directly above the seek bar while a drag is in progress.
///
/// Driven purely by [VmUiState.previewAt] — both drag sources (the seek bar's
/// `onChanged` and the gesture layer's horizontal drag) already publish it via
/// `VmApi.setDragging`, so this component needs no knowledge of either.
/// Replace it wholesale with `VmPatch.replace('preview', MyBubble())`.
///
/// 拖动预览气泡：一张缩略图加目标时间戳，拖动过程中浮在进度条正上方。
///
/// 完全由 [VmUiState.previewAt] 驱动——两个拖动来源（进度条的 `onChanged`
/// 与手势层的横滑）都已经通过 `VmApi.setDragging` 发布该字段，因此本组件
/// 无需感知它们中的任何一个。可用 `VmPatch.replace('preview', MyBubble())`
/// 整块替换。
class PreviewComponent extends VmComponent {
  /// Creates the preview-bubble component.
  ///
  /// 创建预览气泡组件。
  PreviewComponent();

  @override
  String get name => 'preview';

  @override
  VmSlot get slot => VmSlot.bottomAbove;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) =>
      _PreviewBubble(api: api);
}

/// Stateful body of [PreviewComponent]: tracks the scrub position from
/// [VmApi.uiStates] and the resolved thumbnail from `VmApi.preview.thumbs`.
///
/// [PreviewComponent] 的有状态主体：从 [VmApi.uiStates] 跟踪拖动位置，从
/// `VmApi.preview.thumbs` 跟踪已解析的缩略图。
class _PreviewBubble extends StatefulWidget {
  /// Creates the bubble widget.
  ///
  /// 创建气泡 widget。
  ///
  /// [api] is the capability surface to request thumbnails through.
  ///
  /// [api] 为用于请求缩略图的能力面。
  const _PreviewBubble({required this.api});

  /// The capability surface this bubble reads from.
  ///
  /// 该气泡读取的能力面。
  final VmApi api;

  @override
  State<_PreviewBubble> createState() => _PreviewBubbleState();
}

/// State for [_PreviewBubble].
///
/// [_PreviewBubble] 的状态。
class _PreviewBubbleState extends State<_PreviewBubble> {
  /// The current scrub position, or null when no drag is in progress.
  ///
  /// 当前拖动位置；无拖动时为 null。
  Duration? _at;

  /// The thumbnail to render, or null while none has resolved yet.
  ///
  /// 要渲染的缩略图；尚未解析出来时为 null。
  VmThumb? _thumb;

  /// Subscription feeding [_at]; cancelled on dispose.
  ///
  /// 为 [_at] 供数的订阅；在 dispose 时取消。
  StreamSubscription<VmUiState>? _uiSub;

  /// Subscription feeding [_thumb]; cancelled on dispose.
  ///
  /// 为 [_thumb] 供数的订阅；在 dispose 时取消。
  StreamSubscription<VmThumb?>? _thumbSub;

  @override
  void initState() {
    super.initState();
    // Seed synchronously from the current snapshot without setState — the
    // first build has not run yet, so assigning the fields directly is both
    // correct and flicker-free.
    //
    // 同步从当前快照播种，不走 setState——首帧尚未构建，直接赋值既正确又不闪。
    final at = widget.api.uiState.previewAt;
    if (at != null) {
      _at = at;
      _thumb = widget.api.preview.peekAt(at);
      widget.api.preview.requestAt(at);
    }
    _uiSub = widget.api.uiStates.listen((s) => _apply(s.previewAt));
    _thumbSub = widget.api.preview.thumbs.listen((t) {
      if (!mounted) return;
      setState(() => _thumb = t);
    });
  }

  @override
  void dispose() {
    _uiSub?.cancel();
    _thumbSub?.cancel();
    super.dispose();
  }

  /// Reacts to a new scrub position: hides on null, otherwise takes the
  /// synchronous cache hit (if any) and asks for the real thumbnail.
  ///
  /// 响应新的拖动位置：为 null 时隐藏；否则先取同步缓存命中（若有），再请求
  /// 真正的缩略图。
  ///
  /// - [at]: the new scrub position, or null when the drag ended / 新的拖动
  ///   位置；拖动结束时为 null
  void _apply(Duration? at) {
    if (at == _at) return;
    if (!mounted) return;
    if (at == null) {
      widget.api.preview.cancel();
      setState(() {
        _at = null;
        _thumb = null;
      });
      return;
    }
    // Take the synchronous cache hit first so an already-resident bucket
    // renders in this very frame; keep the previous frame otherwise, so the
    // bubble shows a stale image rather than blinking to an empty box.
    //
    // 先取同步缓存命中，让已驻留的桶就在本帧渲染出来；没命中则保留上一帧，
    // 让气泡显示一张旧图而不是闪成空框。
    final hit = widget.api.preview.peekAt(at);
    widget.api.preview.requestAt(at);
    setState(() {
      _at = at;
      _thumb = hit ?? _thumb;
    });
  }

  @override
  Widget build(BuildContext context) {
    final at = _at;
    if (at == null) return const SizedBox.shrink();
    final theme = widget.api.options.theme;
    final width = widget.api.options.preview.frameWidth.toDouble();
    final crop = _thumb?.crop;
    final height = crop == null ? width * 9 / 16 : width * crop.h / crop.w;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _frame(width, height, crop),
            const SizedBox(height: 2),
            Text(
              formatDuration(at),
              style: TextStyle(
                color: Color(theme.textColor),
                fontSize: theme.captionFontSize,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the image frame: the whole bitmap, the crop window into a sprite
  /// sheet, or an empty placeholder box while nothing has resolved.
  ///
  /// 构建图像框：整张位图、雪碧图上的裁剪窗口，或尚未解析出内容时的空占位框。
  ///
  /// - [width]: bubble width in logical pixels / 气泡宽度（逻辑像素）
  /// - [height]: bubble height in logical pixels / 气泡高度（逻辑像素）
  /// - [crop]: sprite sub-rectangle, or null for the whole image /
  ///   雪碧图子矩形；为 null 表示整张图
  ///
  /// Returns the framed image widget.
  ///
  /// 返回带边框的图像 widget。
  Widget _frame(double width, double height, VmThumbCrop? crop) {
    final theme = widget.api.options.theme;
    final thumb = _thumb;
    final border = Border.all(color: Color(theme.textColor), width: 1);

    if (thumb == null) {
      return Container(
        key: const ValueKey('vmPreviewPlaceholder'),
        width: width,
        height: height,
        decoration: BoxDecoration(color: Color(theme.barGradientColor), border: border),
      );
    }

    final Widget image = crop == null
        ? Image.memory(
            thumb.bytes,
            width: width,
            height: height,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          )
        : FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: crop.w.toDouble(),
              height: crop.h.toDouble(),
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: Transform.translate(
                  offset: Offset(-crop.x.toDouble(), -crop.y.toDouble()),
                  child: Image.memory(
                    thumb.bytes,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                  ),
                ),
              ),
            ),
          );

    return Container(
      decoration: BoxDecoration(border: border),
      child: ClipRect(
        key: const ValueKey('vmPreviewClip'),
        child: SizedBox(width: width, height: height, child: image),
      ),
    );
  }
}
```

- [ ] **Step 5: 挂进默认皮肤**

`lib/src/ui/skins/default_skin.dart`：import 区加 `import '../components/preview.dart';`；
`components()` 的列表里，在 `s.type == VmStreamType.live ? LiveBarComponent() : BottomBarComponent(),`
**之前**插入 `PreviewComponent(),`（`bottomAbove` 在 `assemble` 里已排在 `bottom` 之上）。

- [ ] **Step 6: barrel 增补导出**

`lib/videoman.dart` 在 `export 'src/ui/components/overlays.dart';` 之后按字母序插入：

```dart
export 'src/ui/components/preview.dart';
```

- [ ] **Step 7: 跑测试与分析**

Run: `flutter test && flutter analyze`
Expected: preview 8 项 + skin 追加 1 项 PASS，累计 199 项全绿，analyze 0 issues

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(videoman): add scrub preview bubble component in the bottomAbove slot"
```

---

## Task 14: example 接入与 Windows 实跑验证

DESIGN §12 阶段 B 的出口条件之一：「Windows 实跑可见气泡」。example 已经在用
`createVmEngine()`（`_engine = createVmEngine();`，`9c2d4f0` 切过去的），本任务只是给这个
调用加上 Task 12 新增的预览配置参数，不涉及从裸 `VmEngine()` 切换。

**Files:**
- Modify: `example/lib/main.dart`
- Test: 无新增单测（这是实跑验证）

**Interfaces:**
- Consumes: `createVmEngine`（已存在，Task 12 扩展）、`VmPreviewConfig`（Task 10）、`PreviewComponent`（Task 13）
- Produces: 可实跑的预览 demo

- [ ] **Step 1: 给 example 现有的 `createVmEngine()` 调用加预览网络策略**

`example/lib/main.dart` 的 `initState()`（当前是 `_engine = createVmEngine();`，无参数）：

```dart
  @override
  void initState() {
    super.initState();
    // The demo runs on desktop/emulator over whatever connection is
    // available, so the preview network policy is relaxed to `always`;
    // production defaults to `wifiOnly`.
    //
    // demo 在桌面/模拟器上跑，网络类型不确定，故把预览网络策略放宽为
    // `always`；生产环境默认是 `wifiOnly`。
    _engine = createVmEngine(
      options: const VmOptions(
        preview: VmPreviewConfig(network: VmPreviewNetwork.always),
      ),
    );
    _engine.open(_demos[_index].source);
  }
```

顶部 import 保持 `import 'package:videoman/videoman.dart';` 即可（barrel 已导出
`createVmEngine`、`VmPreviewConfig`、`VmPreviewNetwork`）。

- [ ] **Step 2: 在 AppBar 上加一个"关闭预览"开关，验证配置项真的生效**

`_PlayerPageState` 加字段：

```dart
  /// Whether the scrub-preview bubble is enabled in this demo run.
  ///
  /// 本次 demo 运行中是否启用拖动预览气泡。
  bool _previewOn = true;
```

`_engine` 改为可重建：把 `late final VmEngine _engine;` 改成 `late VmEngine _engine;`，
并加一个重建方法：

```dart
  /// Rebuilds the engine with preview switched to [on], reopening the current
  /// demo source.
  ///
  /// 以预览开关 [on] 重建 engine，并重新打开当前演示源。
  ///
  /// - [on]: whether the preview bubble should be enabled / 是否启用预览气泡
  Future<void> _togglePreview(bool on) async {
    final old = _engine;
    setState(() {
      _previewOn = on;
      _engine = createVmEngine(
        options: VmOptions(
          preview: VmPreviewConfig(
            enabled: on,
            network: VmPreviewNetwork.always,
          ),
        ),
      );
    });
    await old.dispose();
    await _engine.open(_demos[_index].source);
  }
```

AppBar 的 `actions` 列表最前面插入：

```dart
          IconButton(
            tooltip: _previewOn ? '关闭预览' : '开启预览',
            icon: Icon(_previewOn ? Icons.image : Icons.image_not_supported),
            onPressed: () => _togglePreview(!_previewOn),
          ),
```

- [ ] **Step 3: Windows 实跑**

Run: `cd example && flutter run -d windows`
Expected（人工/agent 观察窗口即可，无需 stdout 断言）：

1. 拖动底部进度条 → 进度条正上方出现一个气泡，含时间戳（如 `00:35`）。
2. 起初气泡里是空占位框，抽帧完成后变成画面；来回拖回同一个 10s 桶时**立刻**出画面（内存命中）。
3. 在画面上横滑（手势层进度手势）→ 同样出现气泡。
4. 松手 → 气泡消失。
5. 点 AppBar 的图片图标关闭预览 → 再拖动时只有 HUD，无气泡。

若第 2 点始终停在空占位框：先看控制台是否有 mpv 报错；再确认附录 A 选定的抽帧路线与
`mpv_extractor_impl.dart` 里实际写的一致。**不要**通过延长 `settleDelay` 掩盖问题以外的原因，
先确认 `screenshot()` 是否返回了非 null 字节（临时在 `_extractNow` 里 `print(shot?.length)`，
验证完删掉）。

- [ ] **Step 4: 把实跑结果写进附录 B**

在本文档末尾「附录 B：Windows 实跑结果」下逐条勾选上面 5 点，记录发现的问题。

- [ ] **Step 5: 校验并提交**

Run: `flutter analyze && flutter test`
Expected: 0 issues，199 项全绿

```bash
git add -A
git commit -m "feat(videoman): wire example to createVmEngine with a preview toggle"
```

---

## Task 15: 开放性对账、文档与阶段收口

DESIGN §6 的硬约束要求「review 时逐条对账」。本任务把 §6.1 那张表变成一条**可执行的守卫测试**，
再补文档。

**Files:**
- Create: `test/core/openness_preview_test.dart`
- Modify: `README.md`, `CHANGELOG.md`, `doc/SPEC.md`
- Test: `test/core/openness_preview_test.dart`

**Interfaces:**
- Consumes: Task 2–13 的全部公开类型
- Produces: DESIGN §6.1 的逐行守卫测试

- [ ] **Step 1: 写 `test/core/openness_preview_test.dart`**

```dart
// A row-by-row audit of DESIGN-0.2.0 section 6.1: every decision videoman
// makes for the user must ship a default, a config knob, and — when the
// decision is a strategy — an injection point. This test fails loudly if a
// later change drops any of the three.
//
// 对 DESIGN-0.2.0 §6.1 的逐行对账：videoman 替用户做的每个决策都必须同时提供
// 默认值、配置项，以及（当该决策是策略时）注入点。后续改动若丢掉三者之一，
// 本测试会直接失败。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/options/options.dart';
import 'package:videoman/src/core/options/preview_config.dart';
import 'package:videoman/src/core/preview/cache.dart';
import 'package:videoman/src/core/preview/dir_provider.dart';
import 'package:videoman/src/core/preview/extractor.dart';
import 'package:videoman/src/core/preview/models.dart';
import 'package:videoman/src/core/preview/net_probe.dart';
import 'package:videoman/src/core/preview/platform_kind.dart';
import 'package:videoman/src/core/preview/source.dart';
import 'package:videoman/src/ui/components/preview.dart';
import 'package:videoman/src/ui/skins/default_skin.dart';
import 'package:videoman/src/ui/slots/patch.dart';

/// A minimal [VmThumbSource] used to prove the source chain is replaceable.
///
/// 用于证明来源链可替换的最小 [VmThumbSource]。
class _NullSource implements VmThumbSource {
  @override
  String get name => 'null';

  @override
  Future<VmThumb?> thumbAt(VmSource source, Duration bucket) async => null;

  @override
  Future<void> reset() async {}

  @override
  Future<void> dispose() async {}
}

/// A minimal [VmThumbCache] used to prove the cache is replaceable.
///
/// 用于证明缓存可替换的最小 [VmThumbCache]。
class _NullCache implements VmThumbCache {
  @override
  Uint8List? peek(String key) => null;

  @override
  Future<Uint8List?> read(String key) async => null;

  @override
  Future<void> write(String key, Uint8List bytes) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> dispose() async {}
}

/// A minimal [VmFrameExtractor] used to prove extraction is replaceable.
///
/// 用于证明抽帧可替换的最小 [VmFrameExtractor]。
class _NullExtractor implements VmFrameExtractor {
  @override
  Future<Uint8List?> extract(
    String uri,
    Duration at, {
    required int width,
    required bool hwdec,
  }) async =>
      null;

  @override
  Future<void> release() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  group('DESIGN 6.1 row: network policy', () {
    test('default is wifiOnly, knob is network, strategy is probe', () {
      expect(const VmPreviewConfig().network, VmPreviewNetwork.wifiOnly);
      expect(
        const VmPreviewConfig(network: VmPreviewNetwork.never).network,
        VmPreviewNetwork.never,
      );
      expect(VmPreviewConfig(probe: AlwaysAllowNetProbe()).probe, isA<VmNetProbe>());
    });
  });

  group('DESIGN 6.1 row: blocked notification', () {
    test('default is silence, strategy is onBlocked', () {
      expect(const VmPreviewConfig().onBlocked, isNull);
      var seen = false;
      VmPreviewConfig(onBlocked: (_) => seen = true).onBlocked!(
        VmPreviewBlockReason.network,
      );
      expect(seen, isTrue);
    });
  });

  group('DESIGN 6.1 row: thumbnail sources', () {
    test('default chain is implicit, knob is vttEnabled/extractFallback, strategy is sources', () {
      const d = VmPreviewConfig();
      expect(d.sources, isNull, reason: 'null means the built-in [vtt, extract] chain');
      expect(d.vttEnabled, isTrue);
      expect(d.extractFallback, isTrue);
      expect(const VmPreviewConfig(vttEnabled: false).vttEnabled, isFalse);
      expect(const VmPreviewConfig(extractFallback: false).extractFallback, isFalse);
      expect(VmPreviewConfig(sources: [_NullSource()]).sources, hasLength(1));
    });
  });

  group('DESIGN 6.1 row: vtt url', () {
    test('default is the .vtt convention, knob is vttUrl, strategy is vttUrlResolver', () {
      expect(const VmPreviewConfig().vttUrl, isNull);
      expect(const VmPreviewConfig(vttUrl: 'https://cdn/t.vtt').vttUrl, 'https://cdn/t.vtt');
      final cfg = VmPreviewConfig(vttUrlResolver: (_) => Uri.parse('https://cdn/x.vtt'));
      expect(cfg.vttUrlResolver!(const VmSource('a')), Uri.parse('https://cdn/x.vtt'));
    });
  });

  group('DESIGN 6.1 row: extraction fallback', () {
    test('default on, knobs are extractFallback/extractPlatforms, strategy is extractor', () {
      const d = VmPreviewConfig();
      expect(d.extractFallback, isTrue);
      expect(d.extractPlatforms, VmPlatformKind.values.toSet());
      expect(
        const VmPreviewConfig(extractPlatforms: {VmPlatformKind.windows}).extractPlatforms,
        {VmPlatformKind.windows},
      );
      expect(VmPreviewConfig(extractor: _NullExtractor()).extractor, isA<VmFrameExtractor>());
    });
  });

  group('DESIGN 6.1 row: frame width / bucket / hwdec', () {
    test('defaults are 160px, 10s and software decoding, each configurable', () {
      const d = VmPreviewConfig();
      expect(d.frameWidth, 160);
      expect(d.bucket, const Duration(seconds: 10));
      expect(d.hwdec, isFalse);
      const c = VmPreviewConfig(
        frameWidth: 320,
        bucket: Duration(seconds: 5),
        hwdec: true,
      );
      expect(c.frameWidth, 320);
      expect(c.bucket, const Duration(seconds: 5));
      expect(c.hwdec, isTrue);
    });
  });

  group('DESIGN 6.1 row: memory ceiling', () {
    test('default 40 entries, knob memMaxEntries, strategy cache', () {
      expect(const VmPreviewConfig().memMaxEntries, 40);
      expect(const VmPreviewConfig(memMaxEntries: 5).memMaxEntries, 5);
      expect(VmPreviewConfig(cache: _NullCache()).cache, isA<VmThumbCache>());
    });
  });

  group('DESIGN 6.1 row: disk ceiling and directory', () {
    test('defaults 64MB and temp dir, knobs diskMaxBytes/diskDir, strategies cache/dirProvider', () {
      const d = VmPreviewConfig();
      expect(d.diskMaxBytes, 64 * 1024 * 1024);
      expect(d.diskDir, isNull, reason: 'null means the platform temp directory');
      expect(const VmPreviewConfig(diskMaxBytes: 1024).diskMaxBytes, 1024);
      expect(const VmPreviewConfig(diskDir: '/tmp/x').diskDir, '/tmp/x');
      expect(
        const VmPreviewConfig(dirProvider: FixedThumbDirProvider('/tmp/y')).dirProvider,
        isA<VmThumbDirProvider>(),
      );
    });
  });

  group('DESIGN 6.1 row: cache key', () {
    test('default is the built-in hash, strategy is cacheKeyBuilder', () {
      expect(const VmPreviewConfig().cacheKeyBuilder, isNull);
      final cfg = VmPreviewConfig(cacheKeyBuilder: (s, b, w) => 'k');
      expect(cfg.cacheKeyBuilder!('a', 1, 2), 'k');
    });
  });

  group('DESIGN 6.1 row: clear on dispose', () {
    test('default on, knob clearOnDispose, strategy cache', () {
      expect(const VmPreviewConfig().clearOnDispose, isTrue);
      expect(const VmPreviewConfig(clearOnDispose: false).clearOnDispose, isFalse);
      expect(VmPreviewConfig(cache: _NullCache()).cache, isA<VmThumbCache>());
    });
  });

  group('DESIGN 6.1 row: request debounce', () {
    test('default 120ms and configurable', () {
      expect(const VmPreviewConfig().debounce, const Duration(milliseconds: 120));
      expect(
        const VmPreviewConfig(debounce: Duration.zero).debounce,
        Duration.zero,
      );
    });
  });

  group('DESIGN 6.1 row: bubble appearance', () {
    test('default component is addressable and replaceable by patch', () {
      expect(PreviewComponent().name, 'preview');
      final patched = VmDefaultSkin(
        patches: [VmPatch.remove('preview')],
      ).components(const VmState());
      expect(patched.where((c) => c.name == 'preview'), isEmpty);
    });
  });

  test('VmOptions carries the preview section and copyWith keeps it isolated', () {
    const o = VmOptions();
    expect(o.preview, const VmPreviewConfig());
    expect(o.copyWith(preview: const VmPreviewConfig(frameWidth: 99)).gesture, o.gesture);
  });
}
```

顶部若缺 `import 'package:videoman/src/core/state/state.dart';`（`VmState` 用于
`components(const VmState())`）则补上。

- [ ] **Step 2: 跑测试确认通过**

Run: `flutter test test/core/openness_preview_test.dart && flutter analyze`
Expected: 13 项 PASS，analyze 0 issues。
**任何一项失败都表示 §6.1 的某一行缺了默认值/配置项/注入点，必须补齐而不是改测试。**

- [ ] **Step 3: 更新 `CHANGELOG.md`**

在 `## 0.2.0` 段落（若尚未存在则新建）里追加：

```markdown
### 新增 — 拖动预览（阶段 B）

- 拖动进度条或横滑手势时，在进度条上方显示目标时刻的缩略图气泡（`PreviewComponent`，
  挂在 `VmSlot.bottomAbove`，可用 `VmPatch.replace('preview', …)` 整块替换）。
- 缩略图来源按序：服务端 WebVTT 雪碧图（约定 `<video-url>.vtt`，支持 `#xywh` 裁剪）→
  libmpv 隐藏 `Player` 抽帧兜底。可用 `VmPreviewConfig.sources` 整链替换。
- 两级缓存：内存计数 LRU（默认 40 项）+ 磁盘字节 LRU（默认 64MB，临时目录），
  `dispose()` 默认清盘。
- 网络策略默认 `wifiOnly`，由 `connectivity_plus` 探针判定；未知连接与桌面一律放行。
  被拦时静默不请求，只发 `VmPreviewBlocked` 事件并回调 `onBlocked`。
- `VmApi.preview`（`VmPreviewApi`）、`VmOptions.preview`（`VmPreviewConfig`）、
  `VmPreviewBlocked` 事件为新增公开 API。
- 扩展 `createVmEngine()`（已在阶段 A 收尾的平台适配器接线修复中随 brightness/PiP/orientation
  一起加入）：新增 `thumbDir`/`extractor`/`fetcher` 三个可选参数，缺省接入缩略图目录、抽帧器、
  网络探针的真实实现，用于本阶段的拖动预览功能。

### 依赖

- 新增 `path_provider`、`connectivity_plus`。
```

- [ ] **Step 4: 更新 `README.md`**

在功能列表里加一行「拖动预览缩略图（WebVTT 雪碧图 / libmpv 抽帧兜底，两级缓存，默认仅 WiFi）」，
并新增一节：

````markdown
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
````

- [ ] **Step 5: 更新 `doc/SPEC.md`**

把「阶段 B：拖动预览——未开始」那条改成「已完成」，并补一段实现现状：文件清单、
`VmApi.preview` / `VmOptions.preview` / `VmPreviewBlocked` 三个新公开面、
抽帧路线（引用附录 A 的结论）、以及 `createVmEngine()` 在本阶段新增的 `thumbDir`/
`extractor`/`fetcher` 三个预览端口参数。

- [ ] **Step 6: 最终校验**

Run: `flutter analyze && flutter test && flutter pub publish --dry-run`
Expected: analyze 0 issues；212 项全绿；dry-run 0 warnings

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "docs(videoman): audit preview openness contract and document phase B"
```

---

## 附录 A：抽帧分辨率实测结论

实测于 2026-07-31，Windows 桌面（`flutter run -d windows`），片源为 example 已用的
GitHub 示例 mp4（native 854x480），请求宽度 160px。

```
[baseline]      native=854x480 requested=160px shot=jpeg 854x480 bytes=257685
[vf=scale]      native=854x480 requested=160px shot=jpeg 854x480 bytes=257685
[controllerSize] native=854x480 requested=160px shot=jpeg 854x480 bytes=257685
=== VERDICT route=vfScale       result=jpeg 854x480 WORKS=false ===
=== VERDICT route=controllerSize result=jpeg 854x480 WORKS=false ===
```

`vf=scale=160:-2` 与 `VideoControllerConfiguration(width/height)` 均未能让
`player.screenshot()` 返回缩小后的图像——两条路线拿到的都是原生 854x480，与不设任何
缩放的 baseline 完全一致。

**最终选路：原尺寸 + 不缩放兜底**（DESIGN §11 头号风险证伪，两条候选路线均不成立）。
Task 9 的 `MpvFrameExtractor` 直接对 `player.screenshot()` 返回的原图不做任何缩放/裁剪，
`frameWidth` 配置项退化为仅用于 UI 显示时的目标宽度与 cacheKey 参与量，不影响实际抽帧
分辨率。**`diskMaxBytes` 默认值需要复核**——按原分辨率 JPEG 估算，同样条目数下磁盘占用
会明显高于按 160px 缩略图估算的预算，Task 5/6 实现磁盘缓存时需回头核实默认上限是否仍然
合理（或改为存储前用 Flutter `ui.Image`/`instantiateImageCodec` 在内存中二次缩放后再落盘，
这属于 Task 9 范围内的追加决定，而不是走 mpv 侧的 `vf`/`configuration`）。

**调试过程中的额外发现（与选路结论无关，仅供后续排障参考）**：spike 早期版本在同一进程里
连续创建第 3 个 `Player()` 实例时，会在 `NativePlayer.setProperty()` 上永久挂起，且不受
调用间延时、`dispose()` 时序、或引入 `media_kit_native_event_loop` 包影响；前两个实例
在同一场景下总能正常工作。这与 videoman 的真实用法无关——运行时任何时刻至多同时存在
一个主播放器 + 一个隐藏抽帧 `Player`（两个实例），不会触发该现象——因此本计划不将其当作
待解决问题，只留档供未来若真机上出现类似"第 N 个播放器卡死"症状时参考。

## 附录 B：Windows 实跑结果

> Task 14 Step 4 在此逐条记录。

- [ ] 拖动进度条出现气泡与时间戳
- [ ] 抽帧完成后气泡出画面；回拖同桶立刻出图（内存命中）
- [ ] 画面横滑手势同样出气泡
- [ ] 松手气泡消失
- [ ] 关闭预览开关后不再出气泡

发现的问题：（待填）
