# videoman 0.2.0 阶段 A：core/ui 分层重构 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 videoman 从「controls 直连 controller」重构为「core 行为层 + ui 表现层，Stream 通信，UI 是可寻址可打补丁的组件树」，且**对外功能零变化**。

**Architecture:** core 层零 Flutter 依赖，`VmEngine` 包一个抽象 `VmKernel`（唯一 media_kit 实现是 `MpvKernel`），把内核属性流归约成 `VmState`/`VmProgress`/`VmUiState` 三条广播流 + 一条 `VmEvent` 事件流。UI 通过 `VmScope` 拿 `VmApi`，用 `VmSelector` 做字段级重建，界面由 `VmComponent` 组件树 + `VmSkin` 装配，外部用 `VmPatch` 按路径增删换组件。UI → core 只走方法调用，core → UI 只走流。

**Tech Stack:** Dart 3.12 / Flutter ≥3.3、media_kit ^1.2.6、media_kit_video ^2.0.1、screen_brightness ^2.1.11、flutter_test。阶段 A **不加任何新依赖**。

设计依据：[../DESIGN-0.2.0.md](../DESIGN-0.2.0.md)（§3–§6、§9、§10）。

## Global Constraints

- 包名 `videoman`，公开类前缀 `Vm`；`src/` 内文件名不带前缀。
- **core/ 下任何文件禁止 import `package:flutter/*` 与 `package:media_kit/*`**，唯一例外：`core/kernel/mpv_kernel.dart`（可 import media_kit，仍禁 flutter）。
- 注释规则（`CLAUDE.md` 全局）：每个类/方法/函数都要注释，**先英文、空行、后中文**；公开 API 用 `///` 文档注释，带参数与返回说明。本计划代码块里已给出的注释按原样抄；未给出注释的私有小函数也要补一行双语。
- 校验用 `flutter analyze`（必须 0 issues），不用 `flutter build`。
- 每个 Task 结束必须 `flutter test` 全绿再 commit。
- 提交信息 `type(scope): message`，scope 用 `videoman`。
- **功能零变化**：阶段 A 结束时 example 的行为与 0.1.0 完全一致（手势侧别、控制条布局、全屏定向、PiP、清晰度/ABR）。
- 手势侧别刻意与 media_kit 相反（左音量 / 右亮度），**不许"修正"**。
- 硬编码文案与颜色一律走 `VmStrings` / `VmTheme`，组件里不许再出现字面量中文或 `Colors.white`。
- 版本号在 Task 19 统一改为 `0.2.0`，中途不改。

## 文件结构

**core（新建，纯 Dart）**

| 文件 | 职责 |
|---|---|
| `lib/src/core/model/source.dart` | `VmSource` / `VmStreamType`（自 `core/source.dart` 迁移） |
| `lib/src/core/model/fit.dart` | `VmFit` / `vmBoxFit`（`vmBoxFit` 需要 flutter，故留在 ui，见 Task 1） |
| `lib/src/core/model/quality.dart` | `VmQuality` / `parseHlsMasterPlaylist`（迁移） |
| `lib/src/core/model/abr.dart` | `VmBufferingAbr`（自 `BufferingAbr` 改名迁移） |
| `lib/src/core/events/events.dart` | sealed `VmEvent` + 25 个子类 |
| `lib/src/core/bus/bus.dart` | `VmBus<T>`：广播 + `distinct` + `throttle` |
| `lib/src/core/state/state.dart` | `VmState` + `copyWith` |
| `lib/src/core/state/progress.dart` | `VmProgress` |
| `lib/src/core/state/ui_state.dart` | `VmUiState` / `VmHud` |
| `lib/src/core/kernel/kernel.dart` | `VmKernel` 抽象 |
| `lib/src/core/kernel/mpv_kernel.dart` | media_kit 实现 |
| `lib/src/core/options/*.dart` | `VmOptions` / `VmGestureConfig` / `VmAbrConfig` / `VmControlsConfig` / `VmLiveConfig` / `VmStrings` / `VmTheme` |
| `lib/src/core/interceptor/interceptor.dart` | `VmInterceptor` |
| `lib/src/core/platform/ports.dart` | `VmBrightnessPort` / `VmPipPort` / `VmOrientationPort` |
| `lib/src/core/api.dart` | `VmApi` 抽象能力面 |
| `lib/src/core/engine.dart` | `VmEngine implements VmApi` |
| `lib/src/core/compat.dart` | `VmController`（`@Deprecated` 门面） |

**platform_impl（新建，Flutter 侧实现）**

`brightness_impl.dart`、`pip_impl.dart`、`orientation_impl.dart`。

**ui（新建）**

`scope/scope.dart`、`scope/selector.dart`、`slots/slot.dart`、`slots/component.dart`、`slots/patch.dart`、`slots/tree.dart`、`skins/skin.dart`、`skins/default_skin.dart`、`components/`（14 个文件，见 Task 12–15）、`fit_ext.dart`（`vmBoxFit`）、`format.dart`（`formatDuration`）、`player.dart`。

**删除**（Task 18 起）

`lib/src/core/controller.dart`、`lib/src/core/config.dart`、`lib/src/core/source.dart`、`lib/src/core/quality.dart`、`lib/src/core/abr.dart`、`lib/src/controls/*`（5 个文件）。

**测试**

`test/support/fake_kernel.dart`、`test/support/fake_api.dart`、`test/core/*_test.dart`、`test/ui/*_test.dart`；现有 `test/fit_and_format_test.dart`、`test/gesture_layer_test.dart`、`test/quality_abr_test.dart` 内容迁入新路径，`test/method_channel_test.dart` 原样保留。

---

## Task 1: model 层归位

把纯数据模型搬进 `core/model/`，`vmBoxFit`（依赖 flutter 的 `BoxFit`）和 `formatDuration` 搬进 `ui/`，让 core 保持零 Flutter 依赖。

**Files:**
- Create: `lib/src/core/model/source.dart`, `lib/src/core/model/fit.dart`, `lib/src/core/model/quality.dart`, `lib/src/core/model/abr.dart`, `lib/src/ui/fit_ext.dart`, `lib/src/ui/format.dart`
- Modify: `lib/videoman.dart`
- Test: `test/core/model_test.dart`（自 `test/quality_abr_test.dart` + `test/fit_and_format_test.dart` 迁入）

**Interfaces:**
- Consumes: 无（首个任务）
- Produces: `VmSource(String uri, {VmStreamType type, String? title})`、`VmStreamType{vod,live}`、`VmFit{contain,cover,fill}` 带 `next`/`labelKey`、`VmQuality`、`List<VmQuality> parseHlsMasterPlaylist(String content, {required Uri base})`、`VmBufferingAbr({int threshold})` 带 `bool add(bool buffering)`/`void reset()`、`BoxFit vmBoxFit(VmFit)`、`String formatDuration(Duration)`

- [ ] **Step 1: 迁移四个 model 文件**

`git mv lib/src/core/source.dart lib/src/core/model/source.dart`（内容不变）。

`git mv lib/src/core/quality.dart lib/src/core/model/quality.dart`：把 `VmQuality`→已是 `VmQuality`，无需改名，只需确认无 flutter import。

`git mv lib/src/core/abr.dart lib/src/core/model/abr.dart`，类名 `BufferingAbr` → `VmBufferingAbr`（全仓替换）。

新建 `lib/src/core/model/fit.dart`，从 `lib/src/core/config.dart` 抽出 `VmFit`，并把 `label`（硬编码中文）换成 `labelKey`：

```dart
/// Video surface fill mode.
///
/// 画面填充模式。
enum VmFit {
  /// Fit entirely inside the box, letterboxed (default).
  ///
  /// 完整放入画框，可能留黑边（默认）。
  contain,

  /// Fill the box, cropping overflow.
  ///
  /// 铺满画框，裁掉溢出部分。
  cover,

  /// Stretch to fill, ignoring aspect ratio.
  ///
  /// 拉伸铺满，忽略宽高比。
  fill;

  /// The next mode in the contain → cover → fill cycle.
  ///
  /// contain → cover → fill 循环中的下一个模式。
  VmFit get next => switch (this) {
        VmFit.contain => VmFit.cover,
        VmFit.cover => VmFit.fill,
        VmFit.fill => VmFit.contain,
      };
}
```

- [ ] **Step 2: 写 ui 侧两个纯函数文件**

`lib/src/ui/fit_ext.dart`：

```dart
import 'package:flutter/widgets.dart';

import '../core/model/fit.dart';

/// Maps a [VmFit] to the Flutter [BoxFit] used by the video surface.
///
/// 把 [VmFit] 映射为视频画面使用的 Flutter [BoxFit]。
///
/// - [fit]: fill mode / 填充模式
///
/// Returns the matching [BoxFit].
///
/// 返回对应的 [BoxFit]。
BoxFit vmBoxFit(VmFit fit) => switch (fit) {
      VmFit.contain => BoxFit.contain,
      VmFit.cover => BoxFit.cover,
      VmFit.fill => BoxFit.fill,
    };
```

`lib/src/ui/format.dart`：把 `lib/src/controls/controls_common.dart` 里的 `formatDuration` 原样搬过来（含注释）。

- [ ] **Step 3: 迁移测试到 `test/core/model_test.dart`**

把 `test/quality_abr_test.dart` 的 6 项（4 个 parse + 2 个 ABR）与 `test/fit_and_format_test.dart` 的 `VmFit` 3 项合并进 `test/core/model_test.dart`，`BufferingAbr` 改 `VmBufferingAbr`，import 改新路径。`vmBoxFit` 与 `formatDuration` 的 6 项测试迁入 `test/ui/format_test.dart`。`preferredOrientationsFor` 的 3 项暂留原文件（Task 8 迁移）。

- [ ] **Step 4: 更新 barrel 与 import**

`lib/videoman.dart`：

```dart
export 'src/core/model/source.dart';
export 'src/core/model/fit.dart';
export 'src/core/model/quality.dart';
export 'src/core/model/abr.dart';
export 'src/core/controller.dart';
export 'src/core/config.dart';
export 'src/controls/player.dart';
```

修掉 `controller.dart`/`config.dart`/`controls/*` 里指向旧路径的 import。`config.dart` 里删掉 `VmFit`（已迁出），保留 `VmGestureConfig`。`controls_common.dart` 删掉 `vmBoxFit`/`formatDuration`，改为 import ui 侧新文件。

- [ ] **Step 5: 跑测试与分析**

Run: `flutter analyze && flutter test`
Expected: analyze 0 issues；测试 19 项全绿（数量不变，只是位置变了）

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(videoman): move data models into core/model, split flutter-dependent helpers into ui"
```

---

## Task 2: 事件表与事件总线

**Files:**
- Create: `lib/src/core/events/events.dart`, `lib/src/core/bus/bus.dart`
- Test: `test/core/bus_test.dart`

**Interfaces:**
- Consumes: `VmSource`, `VmQuality`, `VmFit`（Task 1）
- Produces: sealed `VmEvent` 及子类 `VmReady`/`VmSourceChanged(source)`/`VmPlay`/`VmPause`/`VmCompleted`/`VmSeeking(target)`/`VmSeeked(position)`/`VmBufferingChanged(buffering)`/`VmDurationChanged(duration)`/`VmSizeChanged(width,height)`/`VmVolumeChanged(value)`/`VmBrightnessChanged(value)`/`VmRateChanged(value)`/`VmQualityListChanged(qualities)`/`VmQualityChanged(quality)`/`VmAbrDownshift(from,to)`/`VmFitChanged(fit)`/`VmZoomChanged(zoom)`/`VmLockChanged(value)`/`VmFullscreenChanged(value)`/`VmPipChanged(value)`/`VmTimeshiftChanged(behind)`/`VmLiveEdgeReached`/`VmErrorEvent(error,stack)`；`VmBus<T>(T initial)` 带 `stream`/`value`/`emit(T)`/`Stream<R> select<R>(R Function(T))`/`close()`；`Stream<T> throttleStream<T>(Stream<T>, Duration)`

- [ ] **Step 1: 写失败测试 `test/core/bus_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/bus/bus.dart';

void main() {
  test('VmBus emits current value to new listeners', () async {
    final bus = VmBus<int>(1);
    final seen = <int>[];
    final sub = bus.stream.listen(seen.add);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [1]);
    bus.emit(2);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [1, 2]);
    await sub.cancel();
    await bus.close();
  });

  test('VmBus skips duplicate values', () async {
    final bus = VmBus<int>(1);
    final seen = <int>[];
    final sub = bus.stream.listen(seen.add);
    bus.emit(1);
    bus.emit(1);
    bus.emit(2);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [1, 2]);
    await sub.cancel();
    await bus.close();
  });

  test('VmBus.select only emits when the picked field changes', () async {
    final bus = VmBus<({int a, int b})>((a: 0, b: 0));
    final seen = <int>[];
    final sub = bus.select((v) => v.a).listen(seen.add);
    bus.emit((a: 0, b: 9));
    bus.emit((a: 1, b: 9));
    await Future<void>.delayed(Duration.zero);
    expect(seen, [0, 1]);
    await sub.cancel();
    await bus.close();
  });

  test('throttleStream keeps the first and the last value in a window', () async {
    final src = StreamController<int>();
    final seen = <int>[];
    final sub = throttleStream(src.stream, const Duration(milliseconds: 50)).listen(seen.add);
    src.add(1);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    src.add(2);
    src.add(3);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(seen, [1, 3]);
    await sub.cancel();
    await src.close();
  });
}
```

顶部补 `import 'dart:async';`。**不要**用 `fake_async`：它只是 `flutter_test` 的传递依赖，直接 import 会
触发 `depend_on_referenced_packages` lint 而让 analyze 非 0。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/bus_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'videoman' ... bus.dart` / `VmBus isn't defined`

- [ ] **Step 3: 实现 `lib/src/core/bus/bus.dart`**

```dart
import 'dart:async';

/// A value-holding broadcast bus: replays the current value to new listeners
/// and drops consecutive duplicates.
///
/// 持值的广播总线：新订阅者立即收到当前值，并自动丢弃连续重复值。
class VmBus<T> {
  final StreamController<T> _controller = StreamController<T>.broadcast();
  T _value;

  /// Creates a bus seeded with [initial].
  ///
  /// 用 [initial] 作为初始值创建总线。
  VmBus(T initial) : _value = initial;

  /// The current value.
  ///
  /// 当前值。
  T get value => _value;

  /// Broadcast stream that starts with the current value.
  ///
  /// 以当前值开头的广播流。
  Stream<T> get stream async* {
    yield _value;
    yield* _controller.stream;
  }

  /// Publishes [next]; no-op when equal to the current value.
  ///
  /// 发布 [next]；与当前值相等时不发。
  void emit(T next) {
    if (next == _value) return;
    _value = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  /// Stream of [pick] results, emitting only when the picked value changes.
  ///
  /// [pick] 结果的流，仅在被选中的值变化时才发。
  Stream<R> select<R>(R Function(T value) pick) =>
      stream.map(pick).distinct();

  /// Closes the underlying controller.
  ///
  /// 关闭底层控制器。
  Future<void> close() => _controller.close();
}

/// Rate-limits [source] to at most one value per [window], always emitting the
/// first value immediately and the last value of a window at its end.
///
/// 把 [source] 限流为每 [window] 最多一个值：首值立即发，窗口内的末值在窗口结束时发。
Stream<T> throttleStream<T>(Stream<T> source, Duration window) {
  StreamController<T>? out;
  StreamSubscription<T>? sub;
  Timer? timer;
  T? pending;
  var hasPending = false;

  void flush() {
    timer = null;
    if (!hasPending) return;
    hasPending = false;
    out!.add(pending as T);
    timer = Timer(window, flush);
  }

  out = StreamController<T>(
    onListen: () {
      sub = source.listen(
        (v) {
          if (timer == null) {
            out!.add(v);
            timer = Timer(window, flush);
          } else {
            pending = v;
            hasPending = true;
          }
        },
        onError: (Object e, StackTrace s) => out!.addError(e, s),
        onDone: () => out!.close(),
      );
    },
    onCancel: () async {
      timer?.cancel();
      await sub?.cancel();
    },
  );
  return out.stream;
}
```

- [ ] **Step 4: 实现 `lib/src/core/events/events.dart`**

按 Interfaces 列出的 25 个子类写完。模板（其余同构，`final` 字段 + `const` 构造 + 双语注释）：

```dart
import '../model/fit.dart';
import '../model/quality.dart';
import '../model/source.dart';

/// Base type of everything broadcast on [VmApi.events].
///
/// [VmApi.events] 上广播的所有事件的基类。
sealed class VmEvent {
  /// Base constructor.
  ///
  /// 基类构造。
  const VmEvent();
}

/// The player finished opening a source and is ready to play.
///
/// 播放器已打开源、可以播放。
class VmReady extends VmEvent {
  /// Creates the event.
  ///
  /// 创建事件。
  const VmReady();
}

/// A new source was opened.
///
/// 打开了新的媒体源。
class VmSourceChanged extends VmEvent {
  /// The source that was opened.
  ///
  /// 被打开的源。
  final VmSource source;

  /// Creates the event with [source].
  ///
  /// 用 [source] 创建事件。
  const VmSourceChanged(this.source);
}

/// A seek was requested and is in flight.
///
/// 已发起跳转、尚未完成。
class VmSeeking extends VmEvent {
  /// Requested target position.
  ///
  /// 请求的目标位置。
  final Duration target;

  /// Creates the event with [target].
  ///
  /// 用 [target] 创建事件。
  const VmSeeking(this.target);
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/core/bus_test.dart && flutter analyze`
Expected: 4 项 PASS，analyze 0 issues

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(videoman): add sealed VmEvent table and VmBus broadcast/throttle primitives"
```

---

## Task 3: 三个状态快照

**Files:**
- Create: `lib/src/core/state/state.dart`, `lib/src/core/state/progress.dart`, `lib/src/core/state/ui_state.dart`
- Test: `test/core/state_test.dart`

**Interfaces:**
- Consumes: `VmFit`, `VmQuality`, `VmStreamType`（Task 1）
- Produces: `VmState`（字段见下，含 `const VmState({...})` 与 `copyWith`，实现 `==`/`hashCode`）、`VmProgress({position, buffer})`、`VmHud{none,volume,brightness,seek,fit,quality,zoom}`、`VmUiState({controlsVisible, dragging, hud, hudText, previewAt})`

- [ ] **Step 1: 写失败测试 `test/core/state_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/fit.dart';
import 'package:videoman/src/core/state/progress.dart';
import 'package:videoman/src/core/state/state.dart';
import 'package:videoman/src/core/state/ui_state.dart';

void main() {
  test('VmState.copyWith changes only the given field', () {
    const a = VmState();
    final b = a.copyWith(playing: true);
    expect(b.playing, isTrue);
    expect(b.fit, a.fit);
    expect(b.volume, a.volume);
    expect(b.duration, a.duration);
  });

  test('VmState equality is by value so the bus can dedupe', () {
    const a = VmState();
    final b = a.copyWith(fit: VmFit.contain);
    expect(b, equals(a));
    expect(a.copyWith(fit: VmFit.cover), isNot(equals(a)));
  });

  test('VmState defaults match 0.1.0 behaviour', () {
    const s = VmState();
    expect(s.playing, isFalse);
    expect(s.volume, 100.0);
    expect(s.brightness, 1.0);
    expect(s.rate, 1.0);
    expect(s.zoom, 1.0);
    expect(s.fit, VmFit.contain);
    expect(s.liveSeekable, isFalse);
    expect(s.timeshiftBehind, isNull);
  });

  test('VmProgress and VmUiState compare by value', () {
    expect(const VmProgress(), const VmProgress());
    expect(const VmUiState(), const VmUiState());
    expect(const VmUiState(hud: VmHud.volume), isNot(const VmUiState()));
  });

  test('VmUiState.copyWith can clear previewAt', () {
    const s = VmUiState(previewAt: Duration(seconds: 5));
    expect(s.copyWith(clearPreview: true).previewAt, isNull);
    expect(s.copyWith(dragging: true).previewAt, const Duration(seconds: 5));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/state_test.dart`
Expected: FAIL — `VmState isn't defined`

- [ ] **Step 3: 实现三个状态类**

`state.dart` 字段（全部 `final`，构造全部命名可选带默认）：
`playing=false`、`buffering=false`、`completed=false`、`locked=false`、`fullscreen=false`、`pip=false`、
`duration=Duration.zero`、`width=0`、`height=0`、
`volume=100.0`、`brightness=1.0`、`rate=1.0`、`zoom=1.0`、
`fit=VmFit.contain`、`qualities=const <VmQuality>[]`、`currentQuality`（可空）、
`type=VmStreamType.vod`、`liveSeekable=false`、`seekableWindow=Duration.zero`、`timeshiftBehind`（可空）、`error`（可空 `Object?`）。

`copyWith` 每个字段一个可空参数，另加 `bool clearQuality=false`、`bool clearTimeshift=false`、`bool clearError=false` 用于显式置空。`==` 用全字段比较（`qualities` 用 `listEquals` 的手写等价实现，core 不能 import flutter/foundation，自己写一个私有 `_listEq`）。

`ui_state.dart` 的 `copyWith` 额外带 `bool clearPreview=false`、`bool clearHudText=false`。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/state_test.dart && flutter analyze`
Expected: 5 项 PASS，0 issues

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(videoman): add immutable VmState/VmProgress/VmUiState snapshots"
```

---

## Task 4: 内核抽象 + FakeKernel + MpvKernel

**Files:**
- Create: `lib/src/core/kernel/kernel.dart`, `lib/src/core/kernel/mpv_kernel.dart`, `test/support/fake_kernel.dart`
- Test: `test/core/kernel_contract_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `abstract class VmKernel`（方法：`Future<void> open(String uri,{bool play})`、`play()`、`pause()`、`seek(Duration)`、`setVolume(double)`、`setRate(double)`、`Future<Uint8List?> screenshot()`、`Future<void> dispose()`；流：`Stream<bool> playing/buffering/completed`、`Stream<Duration> position/duration/buffer`、`Stream<VmSize> size`、`Stream<Object> error`；`Object get renderHandle`）、`class VmSize({int width,int height})`、`class MpvKernel implements VmKernel`、`class FakeKernel implements VmKernel`（带 `emitPlaying(bool)`/`emitBuffering(bool)`/`emitPosition(Duration)`/`emitDuration(Duration)`/`emitBuffer(Duration)`/`emitSize(int,int)`/`emitCompleted(bool)`/`emitError(Object)` 与调用记录 `List<String> calls`、`Duration? lastSeek`、`String? lastUri`）

- [ ] **Step 1: 写失败测试 `test/core/kernel_contract_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/kernel/kernel.dart';

import '../support/fake_kernel.dart';

void main() {
  test('FakeKernel records calls and replays pushed state', () async {
    final k = FakeKernel();
    final seen = <bool>[];
    final sub = k.playing.listen(seen.add);
    await k.open('https://host/a.mp4');
    await k.play();
    await k.seek(const Duration(seconds: 7));
    k.emitPlaying(true);
    await Future<void>.delayed(Duration.zero);
    expect(k.lastUri, 'https://host/a.mp4');
    expect(k.calls, ['open', 'play', 'seek']);
    expect(k.lastSeek, const Duration(seconds: 7));
    expect(seen.last, isTrue);
    await sub.cancel();
    await k.dispose();
  });

  test('VmSize compares by value', () {
    expect(const VmSize(width: 16, height: 9), const VmSize(width: 16, height: 9));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/kernel_contract_test.dart`
Expected: FAIL — `VmKernel isn't defined`

- [ ] **Step 3: 写 `kernel.dart` 抽象与 `VmSize`**

`VmKernel` 用 `abstract class`，全部成员按 Interfaces 声明，每个成员带双语文档注释。`VmSize` 带 `const` 构造、`==`、`hashCode`。

- [ ] **Step 4: 写 `test/support/fake_kernel.dart`**

内部用 `StreamController<T>.broadcast()` 逐个属性；`open/play/pause/seek/setVolume/setRate` 往 `calls` 追加方法名并记录参数；`screenshot()` 返回 `fakeShot`（可在测试里赋值的 `Uint8List?`，默认 null）；`renderHandle` 返回 `Object()`。

- [ ] **Step 5: 写 `mpv_kernel.dart`**

包 `Player` + `VideoController`，把 `player.stream.*` 转成 `VmKernel` 的流，`size` 由 `player.stream.width`/`height` 合并（各自缓存最新值后 emit `VmSize`），`error` 取 `player.stream.error`。`screenshot()` 转发 `player.screenshot(format: 'image/jpeg')`。`renderHandle` 返回 `VideoController`。构造签名：

```dart
/// Creates the media_kit-backed kernel.
///
/// 创建基于 media_kit 的内核。
MpvKernel({Player? player});
```

- [ ] **Step 6: 跑测试与分析**

Run: `flutter test && flutter analyze`
Expected: 全绿，0 issues

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(videoman): add VmKernel abstraction with mpv implementation and test fake"
```

---

## Task 5: 配置族（含文案与主题外置）

**Files:**
- Create: `lib/src/core/options/options.dart`, `gesture_config.dart`, `abr_config.dart`, `controls_config.dart`, `live_config.dart`, `strings.dart`, `theme.dart`
- Delete: `lib/src/core/config.dart`（内容拆入上面）
- Test: `test/core/options_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `VmGestureConfig({horizontalSeek=true, leftVerticalVolume=true, rightVerticalBrightness=true, doubleTapSeek=true, doubleTapStep=Duration(seconds:10), pinchZoom=true, maxZoom=3.0, hSeekSpanPerScreen=Duration(seconds:90), vSensitivity=1.0, allowWhenLive=true})`
  - `abstract class VmAbrPolicy { bool onBuffering(bool buffering); void reset(); }`（`VmBufferingAbr` 实现它）
  - `VmAbrConfig({stallThreshold=3, enabled=true, VmAbrPolicy? policy})`——`policy` 为空时 engine 用
    `VmBufferingAbr(threshold: stallThreshold)`，非空时直接用注入的实现（DESIGN §6.3 的 ABR 注入口）
  - `VmControlsConfig({autoHide=true, autoHideDelay=Duration(seconds:3), showOnStart=true})`
  - `VmLiveSeekMode{off,dvr,timeshift}`、`VmLiveConfig({seekMode=VmLiveSeekMode.off, dvrWindow, edgeThreshold=Duration(seconds:10)})`
  - `VmStrings`（键：`fitContain`='适应'、`fitCover`='裁剪'、`fitFill`='拉伸'、`live`='LIVE'、`backToLive`='回到直播'、`timeshift`='时移'、`backToEdge`='回到边缘'、`auto`='自动'、`quality`='清晰度'，附 `String fitLabel(VmFit)`）
  - `VmTheme`（`iconColor=0xFFFFFFFF`、`textColor=0xFFFFFFFF`、`accentColor=0xFFE53935`、`barGradientColor=0x99000000`、`titleFontSize=14.0`、`timeFontSize=12.0`、`captionFontSize=10.0`、`centerIconSize=64.0`、`progressHeight=2.0`；颜色用 `int` 存，core 不 import flutter，ui 侧转 `Color`）
  - `VmOptions({preview 暂缺, live, gesture, abr, controls, strings, theme})` 带 `copyWith`

- [ ] **Step 1: 写失败测试 `test/core/options_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/fit.dart';
import 'package:videoman/src/core/options/options.dart';

void main() {
  test('VmOptions defaults are const-constructible and preserve 0.1.0 gesture behaviour', () {
    const o = VmOptions();
    expect(o.gesture.leftVerticalVolume, isTrue);
    expect(o.gesture.rightVerticalBrightness, isTrue);
    expect(o.gesture.hSeekSpanPerScreen, const Duration(seconds: 90));
    expect(o.gesture.doubleTapStep, const Duration(seconds: 10));
    expect(o.abr.stallThreshold, 3);
    expect(o.controls.autoHideDelay, const Duration(seconds: 3));
    expect(o.live.seekMode, VmLiveSeekMode.off);
  });

  test('VmStrings.fitLabel covers every VmFit value', () {
    const s = VmStrings();
    for (final f in VmFit.values) {
      expect(s.fitLabel(f), isNotEmpty);
    }
    expect(s.fitLabel(VmFit.contain), '适应');
  });

  test('VmStrings can be replaced wholesale for localisation', () {
    const s = VmStrings(fitContain: 'Fit', live: 'ON AIR');
    expect(s.fitLabel(VmFit.contain), 'Fit');
    expect(s.live, 'ON AIR');
  });

  test('VmOptions.copyWith replaces one section only', () {
    const o = VmOptions();
    final n = o.copyWith(controls: const VmControlsConfig(autoHide: false));
    expect(n.controls.autoHide, isFalse);
    expect(n.gesture, o.gesture);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/options_test.dart`
Expected: FAIL — `VmOptions isn't defined`

- [ ] **Step 3: 实现七个配置文件**

`options.dart` 汇总导出并定义 `VmOptions`；其余各文件一个类。`VmGestureConfig` 从旧 `config.dart` 迁入并补 4 个新字段。全部 `const` 构造 + `==`/`hashCode`。

- [ ] **Step 4: 删旧 config.dart，改引用**

`lib/videoman.dart` 改导出 `src/core/options/options.dart`；`controls/*` 与 `controller.dart` 的 `VmGestureConfig`/`VmFit` import 改新路径。

- [ ] **Step 5: 跑测试与分析**

Run: `flutter analyze && flutter test`
Expected: 全绿，0 issues

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(videoman): externalise strings/theme and add VmOptions config family"
```

---

## Task 6: 拦截器

**Files:**
- Create: `lib/src/core/interceptor/interceptor.dart`
- Test: `test/core/interceptor_test.dart`

**Interfaces:**
- Consumes: `VmSource`
- Produces: `abstract class VmInterceptor`（`beforeOpen(VmSource)→Future<bool>`、`beforeSeek(Duration)→Future<Duration?>`、`beforePlay()→Future<bool>`、`onError(Object,StackTrace)→void`，均有默认实现）、`class VmInterceptorChain(List<VmInterceptor>)` 带同名四方法（串行短路）

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/interceptor/interceptor.dart';
import 'package:videoman/src/core/model/source.dart';

class _DenyOpen extends VmInterceptor {
  @override
  Future<bool> beforeOpen(VmSource s) async => false;
}

class _ClampSeek extends VmInterceptor {
  @override
  Future<Duration?> beforeSeek(Duration t) async =>
      t > const Duration(seconds: 10) ? const Duration(seconds: 10) : t;
}

class _CancelSeek extends VmInterceptor {
  @override
  Future<Duration?> beforeSeek(Duration t) async => null;
}

void main() {
  test('empty chain allows everything', () async {
    final c = VmInterceptorChain(const []);
    expect(await c.beforeOpen(const VmSource('u')), isTrue);
    expect(await c.beforePlay(), isTrue);
    expect(await c.beforeSeek(const Duration(seconds: 3)), const Duration(seconds: 3));
  });

  test('a denying interceptor short-circuits beforeOpen', () async {
    final c = VmInterceptorChain([_DenyOpen()]);
    expect(await c.beforeOpen(const VmSource('u')), isFalse);
  });

  test('beforeSeek rewrites are threaded through the chain', () async {
    final c = VmInterceptorChain([_ClampSeek()]);
    expect(await c.beforeSeek(const Duration(seconds: 30)), const Duration(seconds: 10));
  });

  test('a null from beforeSeek cancels and stops the chain', () async {
    var reached = false;
    final c = VmInterceptorChain([_CancelSeek(), _ClampSeek()]);
    expect(await c.beforeSeek(const Duration(seconds: 30)), isNull);
    expect(reached, isFalse);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/interceptor_test.dart`
Expected: FAIL — `VmInterceptor isn't defined`

- [ ] **Step 3: 实现**

```dart
/// Hook points that let hosts veto or rewrite core actions.
///
/// 供宿主否决或改写内核行为的拦截点。
abstract class VmInterceptor {
  /// Base constructor.
  ///
  /// 基类构造。
  const VmInterceptor();

  /// Returns false to cancel opening [source].
  ///
  /// 返回 false 可取消打开 [source]。
  Future<bool> beforeOpen(VmSource source) async => true;

  /// Returns the (possibly rewritten) target, or null to cancel the seek.
  ///
  /// 返回（可能被改写的）目标位置；返回 null 取消本次跳转。
  Future<Duration?> beforeSeek(Duration target) async => target;

  /// Returns false to cancel starting playback.
  ///
  /// 返回 false 可取消开始播放。
  Future<bool> beforePlay() async => true;

  /// Called for every kernel or pipeline error.
  ///
  /// 内核或管线出错时回调。
  void onError(Object error, StackTrace stack) {}
}
```

`VmInterceptorChain` 按顺序遍历：`beforeOpen`/`beforePlay` 任一 false 立即返回 false；`beforeSeek` 用上一个的返回值喂下一个，遇 null 立即返回 null；`onError` 全部调用（每个 try/catch 包住，避免一个抛异常打断其他）。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/interceptor_test.dart`
Expected: 4 项 PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(videoman): add VmInterceptor hook points and serial chain"
```

---

## Task 7: 平台端口与实现

**Files:**
- Create: `lib/src/core/platform/ports.dart`, `lib/src/platform_impl/brightness_impl.dart`, `lib/src/platform_impl/pip_impl.dart`, `lib/src/platform_impl/orientation_impl.dart`
- Modify: `lib/videoman_platform_interface.dart`, `lib/videoman_method_channel.dart`（保持原位，被 `pip_impl.dart` 使用）
- Test: `test/core/ports_test.dart`, `test/ui/orientation_test.dart`（自 `fit_and_format_test.dart` 迁入 `preferredOrientationsFor` 3 项）

**Interfaces:**
- Consumes: 无
- Produces: `abstract class VmBrightnessPort { Future<double> get(); Future<void> set(double); }`、`abstract class VmPipPort { Future<bool> isSupported(); Future<bool> enter({int? width,int? height}); }`、`abstract class VmOrientationPort { Future<void> apply({required bool fullscreen, required bool immersive, required int width, required int height}); Future<void> reset(); }`、`FallbackBrightnessPort`（永远返回 1.0，core 默认值）、`NoopPipPort`（永远 false）、`NoopOrientationPort`；实现类 `ScreenBrightnessPort`、`ChannelPipPort`、`SystemChromeOrientationPort`（带 `List<DeviceOrientation> preferredOrientationsFor(int width,int height)` 顶层函数）

- [ ] **Step 1: 写失败测试 `test/core/ports_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/platform/ports.dart';

void main() {
  test('fallback brightness port reports full brightness and ignores writes', () async {
    final p = FallbackBrightnessPort();
    expect(await p.get(), 1.0);
    await p.set(0.2);
    expect(await p.get(), 1.0);
  });

  test('noop pip port is unsupported', () async {
    final p = NoopPipPort();
    expect(await p.isSupported(), isFalse);
    expect(await p.enter(width: 16, height: 9), isFalse);
  });
}
```

`test/ui/orientation_test.dart` 迁入原 3 项 `preferredOrientationsFor` 测试，import 改
`package:videoman/src/platform_impl/orientation_impl.dart`。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/ports_test.dart`
Expected: FAIL — `FallbackBrightnessPort isn't defined`

- [ ] **Step 3: 实现端口与三个实现**

`ports.dart` 只有抽象与 noop 兜底（零 flutter import）。`brightness_impl.dart` 包 `screen_brightness`（读 `application`、写 `setApplicationScreenBrightness`，异常兜底 1.0）。`pip_impl.dart` 转发 `VmPlatform.instance`。`orientation_impl.dart` 从旧 `controls/player.dart` 搬 `preferredOrientationsFor` 与 `SystemChrome` 调用。

- [ ] **Step 4: 跑测试与分析**

Run: `flutter test && flutter analyze`
Expected: 全绿，0 issues

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(videoman): add platform ports with brightness/pip/orientation implementations"
```

---

## Task 8: VmApi 抽象面

**Files:**
- Create: `lib/src/core/api.dart`, `test/support/fake_api.dart`
- Test: `test/core/api_test.dart`

**Interfaces:**
- Consumes: Task 2–7 全部类型
- Produces: `abstract class VmApi`（成员完全按 DESIGN §4.1）、`class FakeVmApi implements VmApi`。
  `FakeVmApi` 的完整测试面（后续 Task 全部依赖它，这里一次性定死，不许后补字段）：
  - 构造：`FakeVmApi({VmOptions options = const VmOptions()})`
  - 推数据：`push(VmState)`、`pushUi(VmUiState)`、`pushProgress(VmProgress)`、`pushEvent(VmEvent)`
  - 调用记录：`List<String> calls`（方法名，按调用序）
  - 参数记录：`Duration? lastSeek`、`double? lastVolume`、`double? lastBrightness`、`double? lastRate`、
    `double? lastZoom`、`VmFit? lastFit`、`bool? lastLocked`、`bool? lastFullscreen`、
    `VmQuality? lastQuality`、`bool? lastDragging`、`Duration? lastPreviewAt`、`VmHud? lastHud`
  - 可控返回：`bool pipSupported = true`（`enterPip()` 按它返回）、`Object? renderHandle`（默认 null，
    `VmPlayer` 遇 null 时渲染占位）

- [ ] **Step 1: 写失败测试 `test/core/api_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/state/state.dart';

import '../support/fake_api.dart';

void main() {
  test('FakeVmApi replays the current state to late subscribers', () async {
    final api = FakeVmApi();
    api.push(const VmState(playing: true));
    final seen = <bool>[];
    final sub = api.states.listen((s) => seen.add(s.playing));
    await Future<void>.delayed(Duration.zero);
    expect(seen, [true]);
    await sub.cancel();
    await api.dispose();
  });

  test('FakeVmApi records capability calls', () async {
    final api = FakeVmApi();
    await api.play();
    await api.seek(const Duration(seconds: 3));
    expect(api.calls, ['play', 'seek']);
    expect(api.lastSeek, const Duration(seconds: 3));
    await api.dispose();
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/api_test.dart`
Expected: FAIL — `FakeVmApi isn't defined`

- [ ] **Step 3: 实现 `api.dart` 与 `fake_api.dart`**

`VmApi` 只声明，不带实现（`abstract class`，成员带完整双语文档注释，含参数与返回）。阶段 A 的 `VmApi` 暂**不含** `preview` getter（阶段 B 加），其余按 DESIGN §4.1 一字不差。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/api_test.dart && flutter analyze`
Expected: 2 项 PASS，0 issues

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(videoman): add VmApi capability surface and FakeVmApi test double"
```

---

## Task 9: VmEngine（状态归约与能力实现）

**Files:**
- Create: `lib/src/core/engine.dart`
- Test: `test/core/engine_test.dart`

**Interfaces:**
- Consumes: `VmKernel`, `VmBus`, `VmEvent`, `VmState`, `VmProgress`, `VmUiState`, `VmOptions`, `VmInterceptorChain`, 三个 Port
- Produces: `class VmEngine implements VmApi`，构造：

```dart
VmEngine({
  VmKernel? kernel,
  VmOptions options = const VmOptions(),
  List<VmInterceptor> interceptors = const [],
  VmBrightnessPort? brightness,
  VmPipPort? pip,
  VmOrientationPort? orientation,
});
```

`kernel` 为空时用 `MpvKernel()`；三个 port 为空时用 noop/fallback。另有 `static void ensureInitialized()`（转发 `MediaKit.ensureInitialized()`，放在 `mpv_kernel.dart` 里由 engine 转发，保持 core 不直连 media_kit：engine 调 `MpvKernel.ensureInitialized()`）。

- [ ] **Step 1: 写失败测试 `test/core/engine_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/engine.dart';
import 'package:videoman/src/core/events/events.dart';
import 'package:videoman/src/core/interceptor/interceptor.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/options/options.dart';

import '../support/fake_kernel.dart';

void main() {
  late FakeKernel k;
  late VmEngine e;

  setUp(() {
    k = FakeKernel();
    e = VmEngine(kernel: k);
  });

  tearDown(() => e.dispose());

  test('open emits VmSourceChanged then forwards to the kernel', () async {
    final events = <VmEvent>[];
    final sub = e.events.listen(events.add);
    await e.open(const VmSource('https://host/a.mp4'));
    await Future<void>.delayed(Duration.zero);
    expect(k.lastUri, 'https://host/a.mp4');
    expect(events.whereType<VmSourceChanged>(), isNotEmpty);
    expect(e.state.type, VmStreamType.vod);
    await sub.cancel();
  });

  test('kernel state is reduced into VmState', () async {
    k.emitPlaying(true);
    k.emitDuration(const Duration(minutes: 2));
    k.emitSize(1920, 1080);
    await Future<void>.delayed(Duration.zero);
    expect(e.state.playing, isTrue);
    expect(e.state.duration, const Duration(minutes: 2));
    expect(e.state.width, 1920);
  });

  test('position is exposed on the throttled progress stream, not states', () async {
    final states = <int>[];
    final sub = e.states.listen((_) => states.add(1));
    k.emitPosition(const Duration(seconds: 1));
    k.emitPosition(const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);
    expect(states.length, 1); // 只有初始快照，position 不进 states
    await sub.cancel();
  });

  test('seek is ignored for live sources when seekMode is off', () async {
    await e.open(const VmSource('https://host/l.m3u8', type: VmStreamType.live));
    k.calls.clear();
    await e.seek(const Duration(seconds: 5));
    expect(k.calls, isEmpty);
  });

  test('seek is allowed for live sources in dvr mode and clamped to the window', () async {
    final e2 = VmEngine(
      kernel: k,
      options: const VmOptions(live: VmLiveConfig(seekMode: VmLiveSeekMode.dvr)),
    );
    await e2.open(const VmSource('https://host/l.m3u8', type: VmStreamType.live));
    k.emitDuration(const Duration(seconds: 60));
    await Future<void>.delayed(Duration.zero);
    k.calls.clear();
    await e2.seek(const Duration(seconds: 90));
    expect(k.lastSeek, const Duration(seconds: 60));
    await e2.dispose();
  });

  test('beforeSeek can cancel a seek', () async {
    final e2 = VmEngine(kernel: k, interceptors: [_CancelSeek()]);
    await e2.open(const VmSource('https://host/a.mp4'));
    k.calls.clear();
    await e2.seek(const Duration(seconds: 5));
    expect(k.calls, isEmpty);
    await e2.dispose();
  });

  test('beforePlay can veto playback', () async {
    final e2 = VmEngine(kernel: k, interceptors: [_DenyPlay()]);
    k.calls.clear();
    await e2.play();
    expect(k.calls, isEmpty);
    await e2.dispose();
  });

  test('kernel errors surface on state and events', () async {
    final events = <VmEvent>[];
    final sub = e.events.listen(events.add);
    k.emitError('boom');
    await Future<void>.delayed(Duration.zero);
    expect(e.state.error, 'boom');
    expect(events.whereType<VmErrorEvent>(), isNotEmpty);
    await sub.cancel();
  });

  test('showHud/hideControls drive VmUiState', () async {
    e.showHud(VmHud.volume);
    expect(e.uiState.hud, VmHud.volume);
    e.hideControls();
    expect(e.uiState.controlsVisible, isFalse);
  });

  test('setDragging carries the preview position and clears it on release', () {
    e.setDragging(true, previewAt: const Duration(seconds: 12));
    expect(e.uiState.dragging, isTrue);
    expect(e.uiState.previewAt, const Duration(seconds: 12));
    e.setDragging(false);
    expect(e.uiState.previewAt, isNull);
  });

  test('ABR downshifts after the configured number of stalls', () async {
    // 见 Step 3 的 _abrFixture 说明：先注入两档清晰度再连续三次 buffering 上升沿
  });
}

class _CancelSeek extends VmInterceptor {
  @override
  Future<Duration?> beforeSeek(Duration t) async => null;
}

class _DenyPlay extends VmInterceptor {
  @override
  Future<bool> beforePlay() async => false;
}
```

最后一项 ABR 测试补全：用 `e.debugSetQualities(list)`（engine 上加一个 `@visibleForTesting` 方法注入档位），
然后 `k.emitBuffering(true); k.emitBuffering(false);` 重复 3 次，断言 `k.lastUri` 变成次高档的 URL。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/engine_test.dart`
Expected: FAIL — `VmEngine isn't defined`

- [ ] **Step 3: 实现 `engine.dart`**

要点：

1. 三个 `VmBus`：`_state`、`_ui`，以及 `_progress`（用普通 `StreamController.broadcast` + `throttleStream`）。`events` 用独立 `StreamController<VmEvent>.broadcast()`。
2. 构造时订阅 kernel 全部流；每个回调走 `_reduce`：更新对应字段 → `_state.emit(next)` → 发对应事件。
3. `position`/`buffer` 只进 `_progress`（经 `throttleStream(..., Duration(milliseconds: 200))`），**不进** `_state`。
4. `seek()` 门控：
   ```dart
   final gate = state.type == VmStreamType.vod || state.liveSeekable;
   if (!gate) return;
   final t = await _chain.beforeSeek(to);
   if (t == null) return;
   final clamped = state.duration > Duration.zero
       ? Duration(milliseconds: t.inMilliseconds.clamp(0, state.duration.inMilliseconds))
       : t;
   await _kernel.seek(clamped);
   ```
5. `liveSeekable` 在 `open()` 与 `duration` 变化时重算：`type == live && options.live.seekMode != off && window > Duration.zero`（`timeshift` 模式下 window 取 `options.live.dvrWindow ?? duration`）。
6. `loadQualities()`/`switchQuality()`/`downshift` 逻辑从旧 `controller.dart` 搬来，`switchQuality` 后发 `VmQualityChanged`；ABR 用 `VmBufferingAbr(threshold: options.abr.stallThreshold)`，在 buffering 回调里 `add()`，返回 true 且 `options.abr.enabled` 时降档并发 `VmAbrDownshift`。
7. `setVolume`/`setRate` 转发 kernel 并更新 state；`setBrightness` 走 `VmBrightnessPort`；`setFullscreen` 走 `VmOrientationPort`；`enterPip` 走 `VmPipPort` 并发 `VmPipChanged`。
8. `setFit`/`setZoom`/`setLocked` 只改 state 发事件（渲染由 ui 侧读 state）。
9. `showControls/hideControls`：`autoHide` 开启时 `showControls()` 起一个 `Timer(options.controls.autoHideDelay)` 自动 `hideControls()`；`sticky: true` 不起定时器。
10. `showHud(VmHud)`：设置 `hud` 并起 800ms 定时器复位为 `VmHud.none`。
11. `dispose()`：取消全部订阅、关全部 controller/bus、`_kernel.dispose()`。
12. `@visibleForTesting void debugSetQualities(List<VmQuality> qs, {VmQuality? current})`。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/engine_test.dart && flutter analyze`
Expected: 12 项 PASS，0 issues

- [ ] **Step 5: 加一条 core 纯净性守卫测试**

`test/core/purity_test.dart`：

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('core never imports flutter, and only mpv_kernel imports media_kit', () {
    final files = Directory('lib/src/core')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      final src = f.readAsStringSync();
      expect(src.contains("package:flutter/"), isFalse, reason: '${f.path} imports flutter');
      if (!f.path.replaceAll(r'\', '/').endsWith('kernel/mpv_kernel.dart')) {
        expect(src.contains("package:media_kit"), isFalse, reason: '${f.path} imports media_kit');
      }
    }
  });
}
```

Run: `flutter test test/core/purity_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(videoman): add VmEngine reducing kernel streams into state/events"
```

---

## Task 10: VmScope 与 VmSelector

**Files:**
- Create: `lib/src/ui/scope/scope.dart`, `lib/src/ui/scope/selector.dart`
- Test: `test/ui/selector_test.dart`

**Interfaces:**
- Consumes: `VmApi`, `VmState`, `VmProgress`, `VmUiState`
- Produces: `class VmScope extends InheritedWidget({required VmApi api, required Widget child})` 带 `static VmApi of(BuildContext)`；`class VmSelector<T> extends StatelessWidget({required T Function(VmState) selector, required Widget Function(BuildContext,T) builder})`；同构的 `VmProgressSelector<T>`、`VmUiSelector<T>`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/state/state.dart';
import 'package:videoman/src/ui/scope/scope.dart';
import 'package:videoman/src/ui/scope/selector.dart';

import '../support/fake_api.dart';

void main() {
  testWidgets('VmSelector rebuilds only when the picked field changes', (t) async {
    final api = FakeVmApi();
    var builds = 0;
    await t.pumpWidget(MaterialApp(
      home: VmScope(
        api: api,
        child: VmSelector<bool>(
          selector: (s) => s.playing,
          builder: (c, playing) {
            builds++;
            return Text('$playing');
          },
        ),
      ),
    ));
    await t.pump();
    final base = builds;

    api.push(const VmState(volume: 50));   // 无关字段
    await t.pump();
    expect(builds, base);

    api.push(const VmState(volume: 50, playing: true));
    await t.pump();
    expect(builds, base + 1);
    expect(find.text('true'), findsOneWidget);
    await api.dispose();
  });

  testWidgets('VmScope.of throws a readable error outside a scope', (t) async {
    await t.pumpWidget(Builder(builder: (c) {
      expect(() => VmScope.of(c), throwsA(isA<FlutterError>()));
      return const SizedBox();
    }));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/selector_test.dart`
Expected: FAIL — `VmScope isn't defined`

- [ ] **Step 3: 实现**

`VmScope`：`updateShouldNotify => api != oldWidget.api`；`of` 用 `dependOnInheritedWidgetOfExactType`，为空时 `throw FlutterError('VmScope.of() called outside a VmScope. Wrap your widget in VmPlayer or VmScope.')`。

`VmSelector`：内部 `StreamBuilder<T>(stream: api.states.map(selector).distinct(), initialData: selector(api.state), builder: ...)`。三个 Selector 除数据源不同外同构。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/ui/selector_test.dart && flutter analyze`
Expected: 2 项 PASS，0 issues

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(videoman): add VmScope and field-level VmSelector widgets"
```

---

## Task 11: 组件树、槽位与补丁

**Files:**
- Create: `lib/src/ui/slots/slot.dart`, `lib/src/ui/slots/component.dart`, `lib/src/ui/slots/patch.dart`, `lib/src/ui/slots/tree.dart`
- Test: `test/ui/tree_test.dart`

**Interfaces:**
- Consumes: `VmApi`
- Produces:
  - `enum VmSlot { gesture, hud, top, center, bottomAbove, bottom, overlay }`
  - `abstract class VmComponent { String get name; VmSlot get slot; int get order; List<VmComponent> get children; Widget build(BuildContext, VmApi, List<Widget>); }`
  - `sealed class VmPatch` + 四个工厂 `VmPatch.replace(String path, VmComponent c)`、`VmPatch.remove(String path)`、`VmPatch.insertAfter(String path, VmComponent c)`、`VmPatch.add(VmSlot slot, VmComponent c, {int order = 0})`
  - `List<VmComponent> applyPatches(List<VmComponent> tree, List<VmPatch> patches)`（纯函数）
  - `class VmSlotBundle { List<Widget> operator [](VmSlot slot); }`
  - `VmSlotBundle buildSlots(BuildContext c, VmApi api, List<VmComponent> tree)`

- [ ] **Step 1: 写失败测试 `test/ui/tree_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/api.dart';
import 'package:videoman/src/ui/slots/component.dart';
import 'package:videoman/src/ui/slots/patch.dart';
import 'package:videoman/src/ui/slots/slot.dart';
import 'package:videoman/src/ui/slots/tree.dart';

/// Minimal leaf used to assert tree shape.
///
/// 用于断言组件树形状的最小叶子组件。
class _Leaf extends VmComponent {
  @override
  final String name;
  @override
  final VmSlot slot;
  @override
  final int order;
  _Leaf(this.name, {this.slot = VmSlot.top, this.order = 0});
  @override
  Widget build(BuildContext c, VmApi api, List<Widget> children) => Text(name);
}

/// Minimal composite that lays its children out in a row.
///
/// 把子组件横向排布的最小组合组件。
class _Group extends VmComponent {
  @override
  final String name;
  @override
  final VmSlot slot;
  @override
  final List<VmComponent> children;
  _Group(this.name, this.children, {this.slot = VmSlot.top});
  @override
  Widget build(BuildContext c, VmApi api, List<Widget> children) => Row(children: children);
}

List<String> _names(List<VmComponent> t) =>
    t.expand((c) => [c.name, ...c.children.map((k) => '${c.name}/${k.name}')]).toList();

void main() {
  List<VmComponent> tree() => [
        _Group('topBar', [_Leaf('title'), _Leaf('pip'), _Leaf('lock')]),
      ];

  test('replace swaps a nested component by path', () {
    final out = applyPatches(tree(), [VmPatch.replace('topBar/pip', _Leaf('cast'))]);
    expect(_names(out), ['topBar', 'topBar/title', 'topBar/cast', 'topBar/lock']);
  });

  test('replace swaps a whole composite by path', () {
    final out = applyPatches(tree(), [VmPatch.replace('topBar', _Leaf('bare'))]);
    expect(_names(out), ['bare']);
  });

  test('remove drops a nested component', () {
    final out = applyPatches(tree(), [VmPatch.remove('topBar/pip')]);
    expect(_names(out), ['topBar', 'topBar/title', 'topBar/lock']);
  });

  test('insertAfter puts the new component right after the anchor', () {
    final out = applyPatches(tree(), [VmPatch.insertAfter('topBar/title', _Leaf('x'))]);
    expect(_names(out), ['topBar', 'topBar/title', 'topBar/x', 'topBar/pip', 'topBar/lock']);
  });

  test('add appends a new top-level component to a slot', () {
    final out = applyPatches(tree(), [VmPatch.add(VmSlot.overlay, _Leaf('ad', slot: VmSlot.overlay))]);
    expect(out.last.name, 'ad');
    expect(out.last.slot, VmSlot.overlay);
  });

  test('an unmatched path is a no-op, not a crash', () {
    final out = applyPatches(tree(), [VmPatch.remove('nope/nope')]);
    expect(_names(out), _names(tree()));
  });

  testWidgets('buildSlots groups widgets by slot and sorts by order', (t) async {
    final api = FakeVmApiStub();
    final treeIn = <VmComponent>[
      _Leaf('b', slot: VmSlot.top, order: 2),
      _Leaf('a', slot: VmSlot.top, order: 1),
      _Leaf('o', slot: VmSlot.overlay),
    ];
    late VmSlotBundle bundle;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      bundle = buildSlots(c, api, treeIn);
      return Column(children: bundle[VmSlot.top]);
    })));
    expect(bundle[VmSlot.top].length, 2);
    expect(bundle[VmSlot.overlay].length, 1);
    expect(find.text('a'), findsOneWidget);
  });
}
```

`FakeVmApiStub` 直接用 `test/support/fake_api.dart` 的 `FakeVmApi`（import 后改名使用即可，本测试无需推流）。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/tree_test.dart`
Expected: FAIL — `VmSlot isn't defined`

- [ ] **Step 3: 实现四个文件**

`applyPatches` 递归遍历，路径用 `name` 以 `/` 拼接匹配；`add` 直接 append 到顶层列表。
`buildSlots`：递归先构建 children widget 列表再调父级 `build`，顶层按 `slot` 分组、组内按 `order` 再按插入序稳定排序。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/ui/tree_test.dart && flutter analyze`
Expected: 7 项 PASS，0 issues

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(videoman): add addressable component tree with slots and patches"
```

---

## Task 12: 组件平移 1 —— 手势层与 HUD

把 `lib/src/controls/gesture_layer.dart` 的手势数学原样搬进组件，事件出口从回调改为 `api` 调用 + `VmUiState`。**侧别与数值不许改**。

**Files:**
- Create: `lib/src/ui/components/gesture_layer.dart`, `lib/src/ui/components/hud_layer.dart`, `test/support/pump.dart`
- Test: `test/ui/gesture_test.dart`（自 `test/gesture_layer_test.dart` 迁入 4 项 + 新增 1 项）

**Interfaces:**
- Consumes: `VmApi`, `VmComponent`, `VmSlot`, `VmGestureConfig`, `VmHud`
- Produces: `class GestureLayerComponent extends VmComponent`（`name='gestureLayer'`, `slot=VmSlot.gesture`）、`class HudLayerComponent extends VmComponent`（`name='hudLayer'`, `slot=VmSlot.hud`, children: `VolumeHudComponent`/`BrightnessHudComponent`/`SeekHudComponent`/`ZoomHudComponent`，四个都在同文件内定义）

- [ ] **Step 1: 先写共享 pump 辅助 `test/support/pump.dart`**

后续 Task 13–16 的组件测试全部复用它，不要各自再写私有 `_pumpXxx`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/api.dart';
import 'package:videoman/src/ui/scope/scope.dart';
import 'package:videoman/src/ui/slots/component.dart';
import 'package:videoman/src/ui/slots/tree.dart';

/// Pumps [component] (with its children built) inside a full-viewport [VmScope].
///
/// 把 [component]（含其子组件）铺满视窗地挂在 [VmScope] 里 pump 出来。
///
/// - [tester]: the widget tester / WidgetTester 实例
/// - [api]: capability surface injected into the scope / 注入 scope 的能力面
/// - [component]: component under test / 被测组件
Future<void> pumpComponent(
  WidgetTester tester,
  VmApi api,
  VmComponent component,
) async {
  await tester.pumpWidget(MaterialApp(
    home: VmScope(
      api: api,
      child: Builder(builder: (c) {
        final bundle = buildSlots(c, api, [component]);
        return SizedBox.expand(
          child: Stack(children: bundle[component.slot]),
        );
      }),
    ),
  ));
  await tester.pump();
}
```

- [ ] **Step 2: 迁移测试到 `test/ui/gesture_test.dart`**

四项原测试改为 `await pumpComponent(t, api, GestureLayerComponent())`，用 `t.dragFrom` 驱动，
断言 `api.calls` 与 `api.lastVolume`/`lastBrightness`/`lastSeek`。第五项新增：

```dart
testWidgets('horizontal drag seeks a live source when liveSeekable is true', (t) async {
  final api = FakeVmApi();
  api.push(const VmState(
    type: VmStreamType.live,
    liveSeekable: true,
    seekableWindow: Duration(minutes: 5),
    duration: Duration(minutes: 5),
  ));
  await pumpComponent(t, api, GestureLayerComponent());
  await t.dragFrom(t.getCenter(find.byType(GestureDetector)), const Offset(100, 0));
  await t.pumpAndSettle();
  expect(api.calls, contains('seek'));
  await api.dispose();
});
```

原第 4 项（直播禁滑）保留，改为默认 `liveSeekable: false` 的直播 state。

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/ui/gesture_test.dart`
Expected: FAIL — `GestureLayerComponent isn't defined`

- [ ] **Step 4: 实现两个组件**

`GestureLayerComponent.build` 返回原 `VmGestureDetector` 的等价实现：轴向锁定阈值 8px、横滑
`seconds = dx / width * options.gesture.hSeekSpanPerScreen.inSeconds`、左竖滑音量
`start + frac*100`、右竖滑亮度 `start + frac`、双击 `±doubleTapStep`、双指 `scale` clamp 到
`options.gesture.maxZoom`。拖动过程中 `api.setDragging(true, previewAt: target)` + `api.showHud(VmHud.seek)`，
释放时 `api.seek(target)` 并 `api.setDragging(false)`。所有门控读 `api.options.gesture` 与 `api.state`。

`HudLayerComponent` 用 `VmUiSelector<VmHud>` 决定显示哪个 HUD，文案取 `api.options.strings`，
配色取 `api.options.theme`。

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/ui/gesture_test.dart && flutter analyze`
Expected: 5 项 PASS，0 issues

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(videoman): port gesture layer and HUDs to components"
```

---

## Task 13: 组件平移 2 —— 顶栏

**Files:**
- Create: `lib/src/ui/components/top_bar.dart`（含 `TopBarComponent` + `TitleComponent`/`PipButtonComponent`/`QualityButtonComponent`/`FitButtonComponent`/`FullscreenButtonComponent`/`LockButtonComponent`）, `lib/src/ui/components/common.dart`（`VmIconButton`/`VmGradientBar`，自 `controls_common.dart` 迁入并改吃 `VmTheme`）
- Test: `test/ui/top_bar_test.dart`

**Interfaces:**
- Consumes: `VmApi`, `VmComponent`, `VmTheme`, `VmStrings`
- Produces: 上列 6 个组件类 + `VmIconButton({required IconData icon, String? caption, VoidCallback? onPressed, required VmTheme theme})` + `VmGradientBar({required bool top, required Widget child, required VmTheme theme})`

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('fit button cycles the fill mode and shows the configured label', (t) async {
  final api = FakeVmApi();
  await pumpComponent(t, api, TopBarComponent());
  expect(find.text('适应'), findsOneWidget);
  await t.tap(find.byIcon(Icons.aspect_ratio_rounded));
  await t.pump();
  expect(api.calls, contains('setFit'));
  expect(api.lastFit, VmFit.cover);
  await api.dispose();
});

testWidgets('pip button is hidden when pip is unsupported', (t) async {
  final api = FakeVmApi()..pipSupported = false;
  await pumpComponent(t, api, TopBarComponent());
  expect(find.byIcon(Icons.picture_in_picture_alt_rounded), findsNothing);
  await api.dispose();
});

testWidgets('quality button is hidden when there are no variants', (t) async {
  final api = FakeVmApi();
  api.push(const VmState());
  await pumpComponent(t, api, TopBarComponent());
  expect(find.byIcon(Icons.high_quality_rounded), findsNothing);
  await api.dispose();
});

testWidgets('replacing VmStrings changes the fit label without touching components', (t) async {
  final api = FakeVmApi(options: const VmOptions(strings: VmStrings(fitContain: 'Fit')));
  await pumpComponent(t, api, TopBarComponent());
  expect(find.text('Fit'), findsOneWidget);
  await api.dispose();
});
```

`FakeVmApi` 需补 `pipSupported` 字段、`lastFit` 记录，以及可选 `options` 构造参数。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/top_bar_test.dart`
Expected: FAIL — `TopBarComponent isn't defined`

- [ ] **Step 3: 实现顶栏组件**

布局与 0.1.0 的 `_topBar()` 一致：`title` 撑开，右侧依次 pip / quality / fit / fullscreen / lock。
每个按钮组件独立成类，条件显示逻辑放在各自 `build` 里（返回 `SizedBox.shrink()` 表示不显示），
不再由父级 `if` 控制——这样 patch 掉某个按钮不影响其他。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/ui/top_bar_test.dart && flutter analyze`
Expected: 4 项 PASS，0 issues

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(videoman): port top bar into per-button components"
```

---

## Task 14: 组件平移 3 —— 中心播放键、VOD 底栏、覆盖层

**Files:**
- Create: `lib/src/ui/components/center_play.dart`, `lib/src/ui/components/bottom_bar.dart`（`BottomBarComponent` + `PositionLabelComponent`/`SeekBarComponent`/`DurationLabelComponent`）, `lib/src/ui/components/overlays.dart`（`BufferingComponent`/`ErrorComponent`/`LockMaskComponent`）
- Test: `test/ui/bottom_bar_test.dart`, `test/ui/overlays_test.dart`

**Interfaces:**
- Consumes: `VmApi`, `VmProgressSelector`, `VmSelector`, `VmUiSelector`
- Produces: `CenterPlayComponent`（children: `PlayPauseComponent`）、`BottomBarComponent` 及 3 个子组件、3 个 overlay 组件

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('seek bar commits the dragged position on release', (t) async {
  final api = FakeVmApi();
  api.push(const VmState(duration: Duration(minutes: 2)));
  await pumpComponent(t, api, BottomBarComponent());
  await t.drag(find.byType(Slider), const Offset(200, 0));
  await t.pumpAndSettle();
  expect(api.calls, contains('seek'));
  await api.dispose();
});

testWidgets('seek bar is disabled when duration is zero', (t) async {
  final api = FakeVmApi();
  await pumpComponent(t, api, BottomBarComponent());
  expect(t.widget<Slider>(find.byType(Slider)).onChanged, isNull);
  await api.dispose();
});

testWidgets('position label follows the throttled progress stream', (t) async {
  final api = FakeVmApi();
  api.push(const VmState(duration: Duration(minutes: 2)));
  await pumpComponent(t, api, BottomBarComponent());
  api.pushProgress(const VmProgress(position: Duration(seconds: 65)));
  await t.pump();
  expect(find.text('01:05'), findsOneWidget);
  await api.dispose();
});

testWidgets('buffering overlay shows only while buffering', (t) async {
  final api = FakeVmApi();
  await pumpComponent(t, api, LockMaskComponent());
  expect(find.byType(CircularProgressIndicator), findsNothing);
  api.push(const VmState(buffering: true));
  await t.pump();
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
  await api.dispose();
});

testWidgets('lock mask swallows taps when locked', (t) async {
  final api = FakeVmApi();
  api.push(const VmState(locked: true));
  await pumpComponent(t, api, LockMaskComponent());
  await t.tapAt(const Offset(200, 200));
  await t.pump();
  expect(api.calls.where((c) => c == 'playOrPause'), isEmpty);
  await api.dispose();
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/bottom_bar_test.dart test/ui/overlays_test.dart`
Expected: FAIL — `BottomBarComponent isn't defined`

- [ ] **Step 3: 实现**

`SeekBarComponent` 内部保留 `_dragValue` 本地状态（拖动中不回读 progress，避免抖动），
`onChanged` 时 `api.setDragging(true, previewAt: v)`，`onChangeEnd` 时 `api.seek(v)` + `api.setDragging(false)`。
`ErrorComponent` 读 `state.error`，非空时显示文案 + 重试按钮（调 `api.reload()`）。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test && flutter analyze`
Expected: 全绿，0 issues

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(videoman): port center play, VOD bottom bar and overlay components"
```

---

## Task 15: 组件平移 4 —— 直播底栏

阶段 A 只做 0.1.0 等价功能：LIVE 标 + 回到边缘。时移相关组件在阶段 C 加。

**Files:**
- Create: `lib/src/ui/components/live_bar.dart`（`LiveBarComponent` + `LiveBadgeComponent` + `BackToEdgeComponent`）
- Test: `test/ui/live_bar_test.dart`

**Interfaces:**
- Consumes: `VmApi`, `VmStrings`, `VmTheme`
- Produces: `LiveBarComponent`（`name='bottomBar'`, `slot=VmSlot.bottom`）、`LiveBadgeComponent`（`name='liveBadge'`）、`BackToEdgeComponent`（`name='backToEdge'`）

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('live bar shows the LIVE badge and no seek bar by default', (t) async {
  final api = FakeVmApi();
  api.push(const VmState(type: VmStreamType.live));
  await pumpComponent(t, api, LiveBarComponent());
  expect(find.text('LIVE'), findsOneWidget);
  expect(find.byType(Slider), findsNothing);
  await api.dispose();
});

testWidgets('back-to-edge button reloads the stream', (t) async {
  final api = FakeVmApi();
  api.push(const VmState(type: VmStreamType.live));
  await pumpComponent(t, api, LiveBarComponent());
  await t.tap(find.byIcon(Icons.sync_rounded));
  await t.pump();
  expect(api.calls, contains('reload'));
  await api.dispose();
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/live_bar_test.dart`
Expected: FAIL — `LiveBarComponent isn't defined`

- [ ] **Step 3: 实现**

布局与 0.1.0 `LiveControls._bottomBar()` 一致，文案取 `strings.live` / `strings.backToEdge`，
badge 底色取 `theme.accentColor`。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/ui/live_bar_test.dart && flutter analyze`
Expected: 2 项 PASS，0 issues

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(videoman): port live bottom bar into components"
```

---

## Task 16: 皮肤与装配

**Files:**
- Create: `lib/src/ui/skins/skin.dart`, `lib/src/ui/skins/default_skin.dart`
- Test: `test/ui/skin_test.dart`

**Interfaces:**
- Consumes: 全部组件类、`applyPatches`、`buildSlots`
- Produces: `abstract class VmSkin { List<VmComponent> components(VmState s); Widget assemble(BuildContext c, VmSlotBundle slots, Widget video); }`、`class VmDefaultSkin implements VmSkin { const VmDefaultSkin({List<VmPatch> patches = const []}); }`

- [ ] **Step 1: 写失败测试**

```dart
test('default skin emits the VOD tree for a vod source', () {
  const skin = VmDefaultSkin();
  final names = skin.components(const VmState()).map((c) => c.name).toList();
  expect(names, containsAll(['gestureLayer', 'hudLayer', 'topBar', 'centerPlay', 'bottomBar']));
  final bottom = skin.components(const VmState()).firstWhere((c) => c.name == 'bottomBar');
  expect(bottom.children.map((c) => c.name), ['position', 'seekBar', 'duration']);
});

test('default skin emits the live tree for a live source', () {
  const skin = VmDefaultSkin();
  final bottom = skin
      .components(const VmState(type: VmStreamType.live))
      .firstWhere((c) => c.name == 'bottomBar');
  expect(bottom.children.map((c) => c.name), ['liveBadge', 'backToEdge']);
});

test('patches passed to the default skin are applied to its tree', () {
  final skin = VmDefaultSkin(patches: [VmPatch.remove('topBar/pip')]);
  final top = skin.components(const VmState()).firstWhere((c) => c.name == 'topBar');
  expect(top.children.map((c) => c.name), isNot(contains('pip')));
});

testWidgets('assemble stacks video at the bottom and overlays on top', (t) async {
  final api = FakeVmApi();
  const skin = VmDefaultSkin();
  await t.pumpWidget(MaterialApp(
    home: VmScope(
      api: api,
      child: Builder(builder: (c) {
        final bundle = buildSlots(c, api, skin.components(api.state));
        return skin.assemble(c, bundle, const ColoredBox(color: Color(0xFF000000)));
      }),
    ),
  ));
  expect(find.byType(Stack), findsWidgets);
  await api.dispose();
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/skin_test.dart`
Expected: FAIL — `VmDefaultSkin isn't defined`

- [ ] **Step 3: 实现**

`components(state)`：按 `state.type` 选 VOD/直播底栏，其余相同；最后 `applyPatches(tree, patches)`。
`assemble`：`Stack` 自底向上 = video → gesture → 三段栏 `Column(top, Expanded(center), bottomAbove+bottom)` →
hud → overlay。栏区可见性由 `VmUiSelector<bool>(controlsVisible)` 包 `AnimatedOpacity` + `IgnorePointer`，
沿用 0.1.0 的"仅顶/底可点击、中间透传"规则。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/ui/skin_test.dart && flutter analyze`
Expected: 4 项 PASS，0 issues

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(videoman): add VmSkin abstraction and default VOD/live skins"
```

---

## Task 17: VmPlayer 门面重写

**Files:**
- Create: `lib/src/ui/player.dart`
- Delete: `lib/src/controls/player.dart`
- Modify: `lib/videoman.dart`, `example/lib/main.dart`
- Test: `test/ui/player_test.dart`

**Interfaces:**
- Consumes: `VmApi`, `VmSkin`, `VmDefaultSkin`, `buildSlots`, `vmBoxFit`, `MpvKernel.renderHandle`
- Produces:

```dart
class VmPlayer extends StatefulWidget {
  /// Creates the player widget.
  ///
  /// 创建播放器组件。
  const VmPlayer({
    super.key,
    required this.api,
    this.skin = const VmDefaultSkin(),
    this.autoLoadQualities = true,
  });

  /// Playback facade driving this widget.
  ///
  /// 驱动本组件的播放能力面。
  final VmApi api;

  /// Component tree provider.
  ///
  /// 组件树提供者。
  final VmSkin skin;

  /// Whether to probe HLS quality variants after opening a source.
  ///
  /// 打开源后是否自动探测 HLS 清晰度档位。
  final bool autoLoadQualities;
}
```

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('VmPlayer provides its api down the tree and renders the skin', (t) async {
  final api = FakeVmApi();
  await t.pumpWidget(MaterialApp(home: VmPlayer(api: api, skin: const VmDefaultSkin())));
  await t.pump();
  expect(find.byType(VmScope), findsOneWidget);
  await api.dispose();
});

testWidgets('VmPlayer applies zoom from state via Transform.scale', (t) async {
  final api = FakeVmApi();
  api.push(const VmState(zoom: 2.0));
  await t.pumpWidget(MaterialApp(home: VmPlayer(api: api)));
  await t.pump();
  final ts = t.widget<Transform>(find.byType(Transform).first);
  expect(ts.transform.getMaxScaleOnAxis(), closeTo(2.0, 0.001));
  await api.dispose();
});
```

`FakeVmApi` 的 `renderHandle` 返回 null 时，`VmPlayer` 用 `ColoredBox` 占位（测试可跑，不需要真内核）。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/player_test.dart`
Expected: FAIL — `VmPlayer isn't defined`（旧 player 已删）

- [ ] **Step 3: 实现**

`build`：`VmScope(api) → Stack`；画面部分 `VmSelector<({VmFit fit, double zoom})>` → `Transform.scale` 包
`Video(controller: handle, controls: NoVideoControls, fit: vmBoxFit(fit))`（`handle` 为 `VideoController` 时；
否则占位 `ColoredBox`）。`initState` 里若 `autoLoadQualities` 则 `api.loadQualities()`。
0.1.0 的全屏/方向/沉浸/锁定编排已在 Task 9 移入 engine，这里只订阅 state 渲染，**不再自己持有这些状态**。

- [ ] **Step 4: 更新 example**

`example/lib/main.dart` 改为构造 `VmEngine`（`VmEngine.ensureInitialized()` → `VmEngine(...)` → `open`），
传给 `VmPlayer(api: engine)`；三个 demo 入口（点播 / 直播 / 自定义皮肤）保留原有两个 + 新增一个
`VmDefaultSkin(patches: [VmPatch.remove('topBar/pip')])` 的皮肤定制示例。

- [ ] **Step 5: 跑测试与分析**

Run: `flutter analyze && flutter test`
Expected: 全绿，0 issues

- [ ] **Step 6: 桌面实跑核对功能零变化**

Run: `cd example && flutter run -d windows`
逐项核对：左竖滑音量、右竖滑亮度、横滑进度、双击快进退、双指缩放、contain/cover/fill 循环、
锁定遮罩、全屏定向、控制条 3s 自动隐藏、清晰度菜单、直播条无进度条 + 回到边缘。
**任一不一致就停下修，不进下一 Task。**

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(videoman): rewrite VmPlayer as a scope+skin facade"
```

---

## Task 18: 兼容门面与旧 API 弃用

**Files:**
- Create: `lib/src/core/compat.dart`
- Delete: `lib/src/core/controller.dart`, `lib/src/controls/controls_common.dart`, `lib/src/controls/gesture_layer.dart`, `lib/src/controls/live_controls.dart`, `lib/src/controls/vod_controls.dart`
- Modify: `lib/videoman.dart`
- Test: `test/core/compat_test.dart`

**Interfaces:**
- Consumes: `VmEngine`
- Produces: `@Deprecated('Use VmEngine instead. 0.3.0 移除。') class VmController`（转发 `open`/`play`/`pause`/`playOrPause`/`seek`/`setVolume`/`setRate`/`loadQualities`/`switchQuality`/`reload`/`enterPip`/`isPipSupported`/`dispose`，暴露 `VmEngine get engine`）

- [ ] **Step 1: 写失败测试**

```dart
test('VmController forwards to the engine it wraps', () async {
  final k = FakeKernel();
  // ignore: deprecated_member_use_from_same_package
  final c = VmController(engine: VmEngine(kernel: k));
  await c.open(const VmSource('https://host/a.mp4'));
  await c.play();
  expect(k.calls, ['open', 'play']);
  await c.dispose();
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/compat_test.dart`
Expected: FAIL — `VmController isn't defined`（旧文件已删）

- [ ] **Step 3: 实现门面并清理 barrel**

`lib/videoman.dart` 最终导出：

```dart
export 'src/core/api.dart';
export 'src/core/compat.dart';
export 'src/core/engine.dart';
export 'src/core/events/events.dart';
export 'src/core/interceptor/interceptor.dart';
export 'src/core/model/abr.dart';
export 'src/core/model/fit.dart';
export 'src/core/model/quality.dart';
export 'src/core/model/source.dart';
export 'src/core/options/options.dart';
export 'src/core/platform/ports.dart';
export 'src/core/state/progress.dart';
export 'src/core/state/state.dart';
export 'src/core/state/ui_state.dart';
export 'src/ui/components/common.dart';
export 'src/ui/fit_ext.dart';
export 'src/ui/format.dart';
export 'src/ui/player.dart';
export 'src/ui/scope/scope.dart';
export 'src/ui/scope/selector.dart';
export 'src/ui/skins/default_skin.dart';
export 'src/ui/skins/skin.dart';
export 'src/ui/slots/component.dart';
export 'src/ui/slots/patch.dart';
export 'src/ui/slots/slot.dart';
export 'src/ui/slots/tree.dart';
```

- [ ] **Step 4: 跑测试与分析**

Run: `flutter analyze && flutter test`
Expected: 全绿，0 issues（`compat.dart` 内部自用 deprecated 成员处加 `// ignore: deprecated_member_use_from_same_package`）

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(videoman): drop legacy controls, add deprecated VmController facade"
```

---

## Task 19: 阶段 A 收口（对账 + 文档 + 版本）

**Files:**
- Modify: `pubspec.yaml`, `CHANGELOG.md`, `README.md`, `CLAUDE.md`, `doc/SPEC.md`
- Test: 全量

- [ ] **Step 1: 开放性对账**

按 DESIGN §6.3 逐条 grep 核对，全部要有出口：

```bash
grep -rn "Colors\.\|Color(0x" lib/src/ui/components lib/src/ui/skins | grep -v "theme\." ; echo "--- 上面应为空 ---"
grep -rnP "['\"][\x{4e00}-\x{9fff}]" lib/src/ui ; echo "--- 上面应为空（中文只许出现在 strings.dart 与注释）---"
grep -rn "Duration(seconds: 3)\|Duration(seconds: 90)\|Duration(seconds: 10)" lib/src/ui lib/src/core --include=*.dart | grep -v options/ ; echo "--- 上面应为空 ---"
```

任一非空就把字面量搬进 `VmStrings`/`VmTheme`/对应 config。

- [ ] **Step 2: 版本与文档**

`pubspec.yaml` → `version: 0.2.0`。
`CHANGELOG.md` 加 `## 0.2.0` 段：core/ui 分层、组件树+皮肤+补丁、文案与主题外置、`VmController` 弃用、
破坏性变更替换表（`VodControls`/`LiveControls`/`VmGestureDetector` → `VmDefaultSkin` + patches）。
`README.md` 加「架构」「自定义皮肤」「注入拦截器」三节示例代码。
`CLAUDE.md` 的「结构分层」「当前状态」改成新结构。
`doc/SPEC.md` 的架构与测试小节按新结构重写，末节「剩余任务」更新为阶段 B/C/D。

- [ ] **Step 3: 全量校验**

Run: `flutter analyze && flutter test && flutter pub publish --dry-run`
Expected: analyze 0 issues；测试全绿；dry-run 0 warnings

- [ ] **Step 4: 记录出口条件达成**

在 `doc/SPEC.md` 写下实际测试数量与通过截图/输出摘要（不许只写"通过"）。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "docs(videoman): close phase A — 0.2.0 architecture docs and openness audit"
```

---

## 阶段 B / C / D 的计划生成时点

阶段 B（拖动预览）与 C（直播时移）的详细计划在**阶段 A 的 Task 19 出口条件达成后**生成，
理由：两者的每个 Task 都要写 `VmApi`/`VmState`/`VmComponent` 的确切签名，而这些签名在阶段 A
落地过程中可能微调（例如 `VmUiState.previewAt` 的类型、`buildSlots` 的参数）。提前写死会让计划
与代码漂移，返工成本高于重新生成的成本。

阶段 A 完成后按 DESIGN §7（预览）与 §8（时移）各生成一份同粒度计划，文件名：
`doc/plans/<date>-phase-b-preview.md`、`doc/plans/<date>-phase-c-timeshift.md`。

DESIGN §11 的第一条风险（`screenshot-raw` 分辨率语义）在阶段 B 的 Task 1 就要实测掉，
不通就改走 `VideoControllerConfiguration(width/height)`，并回写 DESIGN。
