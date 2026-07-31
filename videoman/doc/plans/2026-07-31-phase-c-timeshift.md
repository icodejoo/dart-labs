# videoman 0.2.0 阶段 C：直播时移（含阶段 D 收尾发布） — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 斗鱼式「直播 ↔ 点播」切换：直播流在 DVR 窗口内可拖动回看，控制条出进度条与时移指示，
一键回到直播边缘。外加**阶段 D 收尾**——podspec 元数据、example 三个 demo、README/CHANGELOG、
`pub publish --dry-run`、真机一轮验证，直到 0.2.0 可发布。

**Architecture:** 窗口/落后量/是否在边缘三件事抽成 `lib/src/core/live/timeshift.dart` 的纯函数
（可单测、可注入覆盖）；`VmEngine` 只做归约与门控，不含时移算术。`dvr` 模式复用内核原生 seek，
`timeshift` 模式在 `seek()` 里用宿主提供的 `urlBuilder` 生成带起播时间的 URL 重开源。UI 侧
`LiveBarComponent` 复用点播的 `SeekBarComponent`（DESIGN §5.4「一个组件同时服务 VOD 与可拖直播」），
新增时移标签，`liveBadge` 按是否在边缘换配色与文案。

**Tech Stack:** Dart 3.12.2 / Flutter ≥3.3、media_kit ^1.2.6、media_kit_video ^2.0.1、flutter_test。
**阶段 C 不新增任何依赖。**

设计依据：[../DESIGN-0.2.0.md](../DESIGN-0.2.0.md)（§6.2、§8、§10、§11、§12）。
现状依据：[../SPEC.md](../SPEC.md)。上一阶段：[2026-07-30-phase-a-refactor.md](2026-07-30-phase-a-refactor.md)。

**与阶段 B 的关系：** 两个阶段**互不依赖**，可任意先后或并行。本计划不引用任何阶段 B 产物；
Task 12/13/14（阶段 D）里凡涉及阶段 B 的地方都写了「若阶段 B 已落地则……否则跳过」。

**Baseline：** 阶段 A 结束、且 `fix(videoman): wire real platform adapters, restoring
brightness/PiP/orientation`（commit `9c2d4f0`）落地之后为 94 项测试全绿、`flutter analyze`
0 issues、版本 0.2.0。该 commit 已经创建了 `lib/src/platform_impl/wiring.dart` 与
`createVmEngine()`，接好了 brightness/PiP/orientation 三个真实端口——这与阶段 B/C 谁先落地
无关，本计划的任何一步都不需要再自己去接这三个端口。**若阶段 B 先落地**，起始基线还要再加上
阶段 B 新增的测试项数（阶段 B 计划文档里有自己的推进表）。

## 已经做完的部分（阶段 A 已落地，本计划不重复造）

读代码确认，下面这些 DESIGN §8 提到的东西**已经存在**，本计划只在其上增量：

| 已有 | 位置 | 状态 |
|---|---|---|
| `VmLiveSeekMode{off,dvr,timeshift}` | `core/options/live_config.dart` | 完整 |
| `VmLiveConfig.dvrWindow` / `edgeThreshold`（默认 10s） | 同上 | 完整 |
| `VmState.liveSeekable` / `seekableWindow` / `timeshiftBehind` | `core/state/state.dart` | 字段与 `copyWith(clearTimeshift:)` 齐备；**`timeshiftBehind` 至今无人写入** |
| `liveSeekable`/`seekableWindow` 的重算 | `core/engine.dart` 的 `_recomputeLiveSeekable()`，在 `open()` 与 `duration` 变化时触发 | 已接线，但窗口解析 `_resolveWindow()` 只有 `dvrWindow ?? duration`，没有注入点 |
| `seek()` 的直播门控 `type == vod \|\| liveSeekable` | `core/engine.dart` 的 `seek()` | 已实现 |
| 手势横滑的直播门控 | `ui/components/gesture_layer.dart` 的 `_seekAllowed`：`!live \|\| (allowWhenLive && liveSeekable)` | **已实现且刻意为阶段 C 预留**，本计划只补测试（Task 7），不改代码 |
| `VmTimeshiftChanged(behind)` / `VmLiveEdgeReached` 事件类 | `core/events/events.dart` | 类已定义；`VmLiveEdgeReached` 仅被占位实现发过，`VmTimeshiftChanged` 从未被发过 |
| `VmStrings.live` / `backToLive` / `timeshift` | `core/options/strings.dart` | 字段已在，`timeshift`/`backToLive` 尚无人使用 |
| `LiveBarComponent{liveBadge, backToEdge}` | `ui/components/live_bar.dart` | 存在；`backToEdge` 现在调的是 `api.reload()` |

**唯一的占位实现**：`VmEngine.backToLiveEdge()` 目前是 `reload()` + 发 `VmLiveEdgeReached`
（`engine.dart:418-422`），阶段 C 要按 `backToLive` 策略做实。

## 与 DESIGN-0.2.0.md 的偏差（以代码为准）

| DESIGN 说法 | 当前代码事实 | 本计划采用 |
|---|---|---|
| §8「`seek()` 门控改为：`type == vod \|\| liveSeekable`」 | 阶段 A 已经这么写了 | 无需改动 |
| §8 UI 树 `bottomBar/{liveBadge, seekBar, timeshift, backToLive}` | 现为 `{liveBadge, backToEdge}`，且 `backToEdge` 调 `reload()` | 改名 `backToEdge` → `backToLive`，补 `timeshift` 与 `seekBar` |
| §6.2「回直播方式 \| dvr→seek 末端；timeshift→重开 \| `backToLive: seekEnd/reopen`」 | 无该字段 | 加**可空** `backToLive`，为空时按 `seekMode` 推导，兼顾"有默认"与"可配" |
| §6.2「DVR 窗口 \| 取内核 duration \| `dvrWindow` 覆盖 \| `windowResolver(state)`」 | 只有 `dvrWindow`，无 `windowResolver` | 加 `windowResolver` |
| §4.4 `VmState` 无 `sourceTitle` | 有 | 有 |
| §12 阶段 D 单列 | — | 并入本计划 Task 10–14 |

## Global Constraints

- 包名 `videoman`，公开类前缀 `Vm`；`src/` 内文件名不带前缀。
- **`lib/src/core/**` 下任何文件禁止 `import 'package:flutter/...'`；只有
  `lib/src/core/kernel/mpv_kernel.dart` 允许 `import 'package:media_kit/...'`。**
  守卫测试 `test/core/purity_test.dart` 的 `_mediaKitExceptions` 集合必须恒等于
  `{'kernel/mpv_kernel.dart'}`——本阶段**任何任务都不许改动这个集合**。
- 注释规则（全局 `CLAUDE.md`）：每个类/方法/函数/getter/字段都要注释，**先英文一句、空行、后中文**；
  公开 API 用 `///` 文档注释，带参数与返回说明。本计划代码块里给出的注释按原样抄；未给出注释的
  私有小成员也要补一行双语。
- 校验用 `flutter analyze`（必须 0 issues），**不用 `flutter build`**。
- 每个 Task 结束必须 `flutter test` 全绿再 commit。
- 提交信息 `type(scope): message`，scope 用 `videoman`。
- **不新增任何依赖。**
- 手势侧别（左音量 / 右亮度）与 media_kit 内置相反且刻意为之，**不许"修正"**。
- 硬编码文案走 `VmStrings`、颜色/尺寸走 `VmTheme`，组件里不许出现字面量中文或
  `Colors.*`/`Color(0x...)`。
- 开放性契约（DESIGN §6）：每个替用户做的决策必须齐**默认值 + 配置项 + 可注入策略**三样。
  Task 9 逐条对账 §6.2 表格，并把对账做成可执行测试。
- 基线的 94 项测试（若阶段 B 已先落地，连同其新增项）只允许因**语义变更**而改（Task 6 会改
  `live_bar_test.dart` 的 1 项，因为按钮语义从"重开流"变成"回到边缘"），其余一项都不许动。

## 文件结构

**core（新建）**

| 文件 | 职责 | 任务 |
|---|---|---|
| `lib/src/core/live/timeshift.dart` | `resolveWindow()` / `behindOf()` / `atLiveEdge()` 纯函数 | Task 2 |

**core（修改）**

| 文件 | 改动 | 任务 |
|---|---|---|
| `lib/src/core/options/live_config.dart` | 加 `urlBuilder` / `backToLive` / `autoBackToLiveOnStall` / `windowResolver` + `effectiveBackToLive` | Task 1 |
| `lib/src/core/options/strings.dart` | 删 `backToEdge`（被 `backToLive` 取代） | Task 6 |
| `lib/src/core/engine.dart` | 窗口解析改走纯函数、归约 `timeshiftBehind`、timeshift 换源 seek、`backToLiveEdge()` 策略化、卡顿自动回边缘 | Task 3/4/5 |
| `lib/src/core/state/state.dart` | 加 `pipSupported` 字段 | Task 8 |
| `lib/src/core/api.dart` | 加 `bool get pipSupported` | Task 8 |

**ui（修改）**

| 文件 | 改动 | 任务 |
|---|---|---|
| `lib/src/ui/components/bottom_bar.dart` | `SeekBarComponent` 的量程按直播窗口取值 | Task 6 |
| `lib/src/ui/components/live_bar.dart` | 加 `seekBar` 与 `timeshift`，`liveBadge` 按边缘态变样，`backToEdge` → `backToLive` | Task 6 |
| `lib/src/ui/skins/default_skin.dart` | 直播分支传 `seekable` | Task 6 |
| `lib/src/ui/components/top_bar.dart` | `PipButtonComponent` 按能力位隐藏 | Task 8 |

**发布收尾（阶段 D）**

`ios/videoman.podspec`、`example/lib/main.dart`、`README.md`、`CHANGELOG.md`、`doc/SPEC.md`、`CLAUDE.md`。

**测试**

`test/core/live/timeshift_test.dart`（新）、`test/core/openness_live_test.dart`（新，Task 9）、
`test/core/options_test.dart`（增补）、`test/core/engine_test.dart`（增补）、
`test/core/state_test.dart`（增补）、`test/ui/live_bar_test.dart`（改 1 项 + 增补）、
`test/ui/gesture_test.dart`（增补）、`test/ui/top_bar_test.dart`（改 1 项 + 增补）。

---

## Task 1: `VmLiveConfig` 扩展（DESIGN §6.2 的四个开放点）

先把配置面钉死，后面的纯函数与 engine 才有东西可读。四个新字段全部来自 §6.2 表格里
**当前代码缺失**的行。

**Files:**
- Modify: `lib/src/core/options/live_config.dart`
- Test: `test/core/options_test.dart`（追加 5 项，不动既有 4 项）

**Interfaces:**
- Consumes: `VmState`（`core/state/state.dart`，已存在）
- Produces:
  - `typedef VmTimeshiftBuilder = String Function(String uri, Duration behind, DateTime wallClock);`
  - `typedef VmLiveWindowResolver = Duration Function(VmState state);`
  - `enum VmBackToLive { seekEnd, reopen }`
  - `VmLiveConfig` 新增字段 `VmTimeshiftBuilder? urlBuilder`、`VmBackToLive? backToLive`、
    `bool autoBackToLiveOnStall = false`、`VmLiveWindowResolver? windowResolver`
  - `VmBackToLive get effectiveBackToLive`
  - `VmLiveConfig copyWith({...})`

> **依赖方向自查**：`options/live_config.dart` 将 import `state/state.dart`；而 `state/state.dart`
> 只 import `model/*`，**不** import `options/*`，因此不成环。落地后跑一次
> `flutter analyze` 确认无 `import_cycle` 类告警。

- [x] **Step 1: 追加失败测试到 `test/core/options_test.dart`**

顶部 import 区补：

```dart
import 'package:videoman/src/core/state/state.dart';
```

`main()` 末尾追加：

```dart
  test('VmLiveConfig defaults keep 0.1.0 behaviour and add the new knobs off', () {
    const c = VmLiveConfig();
    expect(c.seekMode, VmLiveSeekMode.off);
    expect(c.dvrWindow, isNull);
    expect(c.edgeThreshold, const Duration(seconds: 10));
    expect(c.urlBuilder, isNull);
    expect(c.backToLive, isNull);
    expect(c.autoBackToLiveOnStall, isFalse);
    expect(c.windowResolver, isNull);
  });

  test('effectiveBackToLive derives from seekMode when not configured', () {
    expect(const VmLiveConfig(seekMode: VmLiveSeekMode.dvr).effectiveBackToLive,
        VmBackToLive.seekEnd);
    expect(const VmLiveConfig(seekMode: VmLiveSeekMode.timeshift).effectiveBackToLive,
        VmBackToLive.reopen);
    expect(const VmLiveConfig().effectiveBackToLive, VmBackToLive.seekEnd);
  });

  test('an explicit backToLive overrides the derived default', () {
    const c = VmLiveConfig(
      seekMode: VmLiveSeekMode.timeshift,
      backToLive: VmBackToLive.seekEnd,
    );
    expect(c.effectiveBackToLive, VmBackToLive.seekEnd);
  });

  test('urlBuilder and windowResolver are injectable strategies', () {
    final c = VmLiveConfig(
      seekMode: VmLiveSeekMode.timeshift,
      urlBuilder: (uri, behind, at) => '$uri?behind=${behind.inSeconds}',
      windowResolver: (s) => const Duration(minutes: 30),
    );
    expect(
      c.urlBuilder!('https://h/l.m3u8', const Duration(seconds: 60), DateTime(2026)),
      'https://h/l.m3u8?behind=60',
    );
    expect(c.windowResolver!(const VmState()), const Duration(minutes: 30));
  });

  test('VmLiveConfig.copyWith replaces one field only', () {
    const c = VmLiveConfig(seekMode: VmLiveSeekMode.dvr);
    final n = c.copyWith(autoBackToLiveOnStall: true);
    expect(n.autoBackToLiveOnStall, isTrue);
    expect(n.seekMode, VmLiveSeekMode.dvr);
    expect(n.edgeThreshold, c.edgeThreshold);
  });
```

- [x] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/options_test.dart`
Expected: FAIL — `The getter 'urlBuilder' isn't defined for the class 'VmLiveConfig'`

- [x] **Step 3: 实现 `lib/src/core/options/live_config.dart`**

文件顶部补 import 与两个 typedef、一个枚举（放在 `VmLiveSeekMode` 之后、`VmLiveConfig` 之前）：

```dart
import '../state/state.dart';
```

```dart
/// Builds the playback URL for a time-shifted live stream.
///
/// Servers differ wildly here (`?begin=`, `?starttime=`, path-embedded epochs,
/// signed tokens), so videoman never guesses: `timeshift` mode is inert until
/// the host supplies one of these. This is DESIGN section 6.2's "时移 URL"
/// injection point.
///
/// 为时移直播流构造播放 URL。
///
/// 各家服务端差异极大（`?begin=`、`?starttime=`、把时间戳嵌进路径、带签名的
/// token 等），videoman 绝不猜测：宿主不提供本回调时 `timeshift` 模式不生效。
/// 这是 DESIGN §6.2「时移 URL」的注入点。
///
/// - [uri]: the original live URI / 原始直播地址
/// - [behind]: how far behind the live edge to start / 相对直播边缘回退的时长
/// - [wallClock]: "now" as seen by the client / 客户端视角的当前时刻
///
/// Returns the URL to open / 返回要打开的地址。
typedef VmTimeshiftBuilder = String Function(
  String uri,
  Duration behind,
  DateTime wallClock,
);

/// Resolves the seekable DVR/time-shift window for the current state.
///
/// The bundled default infers the window from the kernel-reported duration,
/// which is right for HLS sliding windows but wrong for servers that advertise
/// it out-of-band. This is DESIGN section 6.2's `windowResolver` injection
/// point.
///
/// 解析当前状态下可拖动的 DVR/时移窗口。
///
/// 内置默认实现由内核报告的时长推断窗口，这对 HLS 滑动窗口是对的，但对通过
/// 带外方式声明窗口的服务端就不对。这是 DESIGN §6.2 的 `windowResolver` 注入点。
///
/// - [state]: the current player state / 当前播放器状态
///
/// Returns the seekable window length / 返回可拖动窗口长度。
typedef VmLiveWindowResolver = Duration Function(VmState state);

/// How "back to live" is performed.
///
/// 「回到直播」的执行方式。
enum VmBackToLive {
  /// Seek to the end of the seekable window without reopening the source.
  ///
  /// Right for DVR streams, where the same URL already spans the window.
  ///
  /// 不重开源，直接跳到可拖动窗口末端。
  ///
  /// 适用于 DVR 流——同一个地址本身就覆盖整个窗口。
  seekEnd,

  /// Reopen the original live URL from scratch.
  ///
  /// Right for time-shift streams, whose current URL points at a past instant
  /// and can never catch up to the edge by seeking.
  ///
  /// 从头重新打开原始直播地址。
  ///
  /// 适用于时移流——其当前地址指向过去的某一时刻，靠 seek 永远追不上边缘。
  reopen,
}
```

`VmLiveConfig` 类内，在 `edgeThreshold` 字段之后追加四个字段：

```dart
  /// Builds the time-shifted playback URL; `null` leaves
  /// [VmLiveSeekMode.timeshift] inert (seeks are ignored).
  ///
  /// 构造时移播放地址；为 `null` 时 [VmLiveSeekMode.timeshift] 不生效
  /// （拖动被忽略）。
  final VmTimeshiftBuilder? urlBuilder;

  /// How to return to the live edge; `null` derives it from [seekMode]
  /// (see [effectiveBackToLive]).
  ///
  /// 回到直播边缘的方式；为 `null` 时按 [seekMode] 推导（见
  /// [effectiveBackToLive]）。
  final VmBackToLive? backToLive;

  /// Whether a buffering stall while time-shifted automatically jumps back to
  /// the live edge. Off by default — silently losing the user's chosen replay
  /// position is a surprising default, so it is opt-in.
  ///
  /// 时移状态下发生卡顿是否自动跳回直播边缘。默认关闭——悄悄丢掉用户选定的
  /// 回看位置是个意外的默认行为，因此需显式开启。
  final bool autoBackToLiveOnStall;

  /// Overrides how the seekable window is computed; `null` uses
  /// [dvrWindow] when set, otherwise the kernel-reported duration.
  ///
  /// 覆盖可拖动窗口的计算方式；为 `null` 时优先用 [dvrWindow]，否则用内核报告
  /// 的时长。
  final VmLiveWindowResolver? windowResolver;
```

构造追加四个参数（保持既有三个不变）：

```dart
    this.urlBuilder,
    this.backToLive,
    this.autoBackToLiveOnStall = false,
    this.windowResolver,
```

加派生 getter 与 `copyWith`：

```dart
  /// The back-to-live strategy actually in effect.
  ///
  /// Returns [backToLive] when configured; otherwise derives it from
  /// [seekMode] per DESIGN section 6.2 — `timeshift` reopens, everything else
  /// seeks to the window end.
  ///
  /// 实际生效的回到直播策略。
  ///
  /// 配置了 [backToLive] 就用它；否则按 DESIGN §6.2 由 [seekMode] 推导——
  /// `timeshift` 重开源，其余一律跳到窗口末端。
  VmBackToLive get effectiveBackToLive =>
      backToLive ??
      (seekMode == VmLiveSeekMode.timeshift
          ? VmBackToLive.reopen
          : VmBackToLive.seekEnd);

  /// Returns a copy with the given fields replaced.
  ///
  /// Nullable strategy fields ([dvrWindow], [urlBuilder], [backToLive],
  /// [windowResolver]) can only be set, not cleared — clearing an injected
  /// strategy has no use case and would need a flag per field.
  ///
  /// 返回一份替换了指定字段的拷贝。
  ///
  /// 可空的策略字段（[dvrWindow]、[urlBuilder]、[backToLive]、
  /// [windowResolver]）只能设置、不能清空——清空已注入的策略没有使用场景，
  /// 且会需要给每个字段配一个标志位。
  ///
  /// - [seekMode]: replacement seek mode / 替换用的拖动模式
  /// - [dvrWindow]: replacement DVR window / 替换用的 DVR 窗口
  /// - [edgeThreshold]: replacement edge threshold / 替换用的边缘阈值
  /// - [urlBuilder]: replacement time-shift URL builder / 替换用的时移地址构造器
  /// - [backToLive]: replacement back-to-live strategy / 替换用的回直播策略
  /// - [autoBackToLiveOnStall]: replacement stall behaviour / 替换用的卡顿行为
  /// - [windowResolver]: replacement window resolver / 替换用的窗口解析器
  ///
  /// Returns the new [VmLiveConfig] / 返回新的 [VmLiveConfig]。
  VmLiveConfig copyWith({
    VmLiveSeekMode? seekMode,
    Duration? dvrWindow,
    Duration? edgeThreshold,
    VmTimeshiftBuilder? urlBuilder,
    VmBackToLive? backToLive,
    bool? autoBackToLiveOnStall,
    VmLiveWindowResolver? windowResolver,
  }) {
    return VmLiveConfig(
      seekMode: seekMode ?? this.seekMode,
      dvrWindow: dvrWindow ?? this.dvrWindow,
      edgeThreshold: edgeThreshold ?? this.edgeThreshold,
      urlBuilder: urlBuilder ?? this.urlBuilder,
      backToLive: backToLive ?? this.backToLive,
      autoBackToLiveOnStall:
          autoBackToLiveOnStall ?? this.autoBackToLiveOnStall,
      windowResolver: windowResolver ?? this.windowResolver,
    );
  }
```

`==` 整体替换为下面这段（注意既有的最后一行 `edgeThreshold == other.edgeThreshold;` 的分号要变成
`&&`）。函数字段按引用相等，这是有意的——两个不同闭包本就应视为不同配置：

```dart
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VmLiveConfig &&
          runtimeType == other.runtimeType &&
          seekMode == other.seekMode &&
          dvrWindow == other.dvrWindow &&
          edgeThreshold == other.edgeThreshold &&
          urlBuilder == other.urlBuilder &&
          backToLive == other.backToLive &&
          autoBackToLiveOnStall == other.autoBackToLiveOnStall &&
          windowResolver == other.windowResolver;
```

`hashCode` 改为：

```dart
  @override
  int get hashCode => Object.hash(
        seekMode,
        dvrWindow,
        edgeThreshold,
        urlBuilder,
        backToLive,
        autoBackToLiveOnStall,
        windowResolver,
      );
```

- [x] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/options_test.dart && flutter analyze`
Expected: 9 项 PASS（既有 4 + 新增 5），analyze 0 issues

- [x] **Step 5: 跑纯净性守卫**

Run: `flutter test test/core/purity_test.dart`
Expected: PASS（`live_config.dart` 新增的 import 是 core 内部文件）

- [x] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(videoman): add timeshift url builder, back-to-live strategy and window resolver knobs"
```

---

## Task 2: 时移纯函数 `core/live/timeshift.dart`

DESIGN §8 点名要求的三个可单测纯函数。engine 里**不许**再出现时移算术。

**Files:**
- Create: `lib/src/core/live/timeshift.dart`
- Modify: `lib/videoman.dart`
- Test: `test/core/live/timeshift_test.dart`

**Interfaces:**
- Consumes: `VmState`（已存在）、`VmLiveConfig` / `VmLiveWindowResolver`（Task 1）
- Produces:
  - `Duration resolveWindow(VmState s, VmLiveConfig cfg)`
  - `Duration? behindOf(Duration position, Duration window, Duration edgeThreshold)`
  - `bool atLiveEdge(Duration position, Duration window, Duration edgeThreshold)`

- [ ] **Step 1: 写失败测试 `test/core/live/timeshift_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/live/timeshift.dart';
import 'package:videoman/src/core/options/live_config.dart';
import 'package:videoman/src/core/state/state.dart';

/// Ten seconds — the product's default "close enough to the edge" threshold.
///
/// 十秒——产品默认的"已足够接近边缘"阈值。
const _edge = Duration(seconds: 10);

void main() {
  group('resolveWindow', () {
    test('falls back to the kernel-reported duration', () {
      const s = VmState(duration: Duration(minutes: 5));
      expect(resolveWindow(s, const VmLiveConfig()), const Duration(minutes: 5));
    });

    test('an explicit dvrWindow wins over the duration', () {
      const s = VmState(duration: Duration(minutes: 5));
      const cfg = VmLiveConfig(dvrWindow: Duration(minutes: 2));
      expect(resolveWindow(s, cfg), const Duration(minutes: 2));
    });

    test('an injected windowResolver wins over everything', () {
      const s = VmState(duration: Duration(minutes: 5));
      final cfg = VmLiveConfig(
        dvrWindow: const Duration(minutes: 2),
        windowResolver: (_) => const Duration(hours: 1),
      );
      expect(resolveWindow(s, cfg), const Duration(hours: 1));
    });

    test('an unknown duration resolves to zero, not to a negative window', () {
      expect(resolveWindow(const VmState(), const VmLiveConfig()), Duration.zero);
    });
  });

  group('behindOf', () {
    test('inside the edge threshold counts as at the edge (null)', () {
      expect(behindOf(const Duration(seconds: 55), const Duration(seconds: 60), _edge),
          isNull);
      expect(behindOf(const Duration(seconds: 50), const Duration(seconds: 60), _edge),
          isNull, reason: 'exactly at the threshold is still the edge');
    });

    test('beyond the threshold reports how far behind', () {
      expect(behindOf(const Duration(seconds: 20), const Duration(seconds: 60), _edge),
          const Duration(seconds: 40));
    });

    test('a zero or unknown window is never behind', () {
      expect(behindOf(const Duration(seconds: 20), Duration.zero, _edge), isNull);
    });

    test('a position past the window end is not reported as negative', () {
      expect(behindOf(const Duration(seconds: 90), const Duration(seconds: 60), _edge),
          isNull);
    });
  });

  group('atLiveEdge', () {
    test('is the exact inverse of behindOf being null', () {
      expect(atLiveEdge(const Duration(seconds: 55), const Duration(seconds: 60), _edge),
          isTrue);
      expect(atLiveEdge(const Duration(seconds: 20), const Duration(seconds: 60), _edge),
          isFalse);
      expect(atLiveEdge(Duration.zero, Duration.zero, _edge), isTrue);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/live/timeshift_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package ... live/timeshift.dart` / `resolveWindow isn't defined`

- [ ] **Step 3: 实现 `lib/src/core/live/timeshift.dart`**

```dart
import '../options/live_config.dart';
import '../state/state.dart';

/// Resolves the seekable DVR/time-shift window for [s] under [cfg].
///
/// Precedence: an injected [VmLiveConfig.windowResolver] wins, then an
/// explicit [VmLiveConfig.dvrWindow], then the kernel-reported
/// [VmState.duration] (a live HLS stream's "duration" is its sliding-window
/// length). A negative result is clamped to zero so callers never see a
/// nonsensical window.
///
/// 在配置 [cfg] 下解析状态 [s] 的可拖动 DVR/时移窗口。
///
/// 优先级：注入的 [VmLiveConfig.windowResolver] 最高，其次是显式的
/// [VmLiveConfig.dvrWindow]，最后回落到内核报告的 [VmState.duration]
/// （直播 HLS 流的"时长"即其滑动窗口长度）。结果为负时被 clamp 到零，
/// 使调用方绝不会拿到荒谬的窗口值。
///
/// - [s]: the current player state / 当前播放器状态
/// - [cfg]: the live configuration in effect / 生效的直播配置
///
/// Returns the window length, never negative / 返回窗口长度，绝不为负。
Duration resolveWindow(VmState s, VmLiveConfig cfg) {
  final resolver = cfg.windowResolver;
  final raw = resolver != null ? resolver(s) : (cfg.dvrWindow ?? s.duration);
  return raw.isNegative ? Duration.zero : raw;
}

/// How far [position] is behind the live edge of a [window], or `null` when it
/// is close enough to the edge to count as live.
///
/// Returns `null` (i.e. "at the edge") when the window is unknown/zero, when
/// the gap is within [edgeThreshold], or when [position] sits at or past the
/// window end — a playhead ahead of the window is a clock-skew artefact, not a
/// negative time-shift.
///
/// 返回 [position] 落后 [window] 直播边缘的时长；足够接近边缘时返回 `null`。
///
/// 以下三种情况都返回 `null`（即"在边缘"）：窗口未知/为零；差距在
/// [edgeThreshold] 以内；[position] 位于窗口末端或之后——播放头跑到窗口前面
/// 是时钟偏差造成的假象，不是负的时移量。
///
/// - [position]: current playhead within the window / 窗口内的当前播放位置
/// - [window]: seekable window length / 可拖动窗口长度
/// - [edgeThreshold]: gap still counted as live / 仍算作直播的差距阈值
///
/// Returns the lag, or `null` when at the edge / 返回落后时长；在边缘时返回 `null`。
Duration? behindOf(Duration position, Duration window, Duration edgeThreshold) {
  if (window <= Duration.zero) return null;
  final behind = window - position;
  if (behind <= edgeThreshold) return null;
  return behind;
}

/// Whether [position] counts as sitting at the live edge of [window].
///
/// Exactly the inverse of [behindOf] returning a value; kept as its own
/// function so UI code reads as intent rather than as a null check.
///
/// 判断 [position] 是否算作处于 [window] 的直播边缘。
///
/// 与 [behindOf] 返回非空恰好互为反面；单独成函数是为了让 UI 代码读起来是
/// 意图表达，而不是一次 null 判断。
///
/// - [position]: current playhead within the window / 窗口内的当前播放位置
/// - [window]: seekable window length / 可拖动窗口长度
/// - [edgeThreshold]: gap still counted as live / 仍算作直播的差距阈值
///
/// Returns whether playback is at the live edge / 返回是否处于直播边缘。
bool atLiveEdge(Duration position, Duration window, Duration edgeThreshold) =>
    behindOf(position, window, edgeThreshold) == null;
```

- [ ] **Step 4: barrel 增补导出**

`lib/videoman.dart` 在 `export 'src/core/interceptor/interceptor.dart';` 之后按字母序插入：

```dart
export 'src/core/live/timeshift.dart';
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/core/live/timeshift_test.dart && flutter analyze`
Expected: 9 项 PASS，analyze 0 issues

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(videoman): add pure timeshift window/behind/edge helpers"
```

---

## Task 3: engine 归约窗口与 `timeshiftBehind`

把 `_resolveWindow()` 换成 Task 2 的纯函数，并让 `timeshiftBehind` 真正跟着播放位置走、
发 `VmTimeshiftChanged` / `VmLiveEdgeReached`。

**取舍（必须照做）**：`behind` 按**整秒量化**后再比较入库。position 每秒来若干次，不量化会让
`states` 流退化成高频流——阶段 A 特意把 position 排除在 `states` 之外，不能在这里破功。
UI 只显示 `-MM:SS`，秒级精度足够。

**Files:**
- Modify: `lib/src/core/engine.dart`
- Test: `test/core/engine_test.dart`（追加 5 项）

**Interfaces:**
- Consumes: `resolveWindow` / `behindOf`（Task 2）、`VmTimeshiftChanged` / `VmLiveEdgeReached`（已存在）
- Produces: 无新公开类型；`VmState.timeshiftBehind` 首次被写入

- [ ] **Step 1: 追加失败测试到 `test/core/engine_test.dart`**

`main()` 末尾追加：

```dart
  test('timeshiftBehind stays null for a VOD source', () async {
    await e.open(const VmSource('https://host/a.mp4'));
    k.emitDuration(const Duration(seconds: 600));
    k.emitPosition(const Duration(seconds: 10));
    await Future<void>.delayed(Duration.zero);
    expect(e.state.timeshiftBehind, isNull);
  });

  test('a dvr live stream reports how far behind the edge it is', () async {
    final k2 = FakeKernel();
    final e2 = VmEngine(
      kernel: k2,
      options: const VmOptions(live: VmLiveConfig(seekMode: VmLiveSeekMode.dvr)),
    );
    await e2.open(const VmSource('https://host/l.m3u8', type: VmStreamType.live));
    k2.emitDuration(const Duration(seconds: 300));
    k2.emitPosition(const Duration(seconds: 100));
    await Future<void>.delayed(Duration.zero);
    expect(e2.state.liveSeekable, isTrue);
    expect(e2.state.seekableWindow, const Duration(seconds: 300));
    expect(e2.state.timeshiftBehind, const Duration(seconds: 200));
    await e2.dispose();
  });

  test('inside the edge threshold clears timeshiftBehind and announces the edge', () async {
    final k2 = FakeKernel();
    final e2 = VmEngine(
      kernel: k2,
      options: const VmOptions(live: VmLiveConfig(seekMode: VmLiveSeekMode.dvr)),
    );
    await e2.open(const VmSource('https://host/l.m3u8', type: VmStreamType.live));
    k2.emitDuration(const Duration(seconds: 300));
    k2.emitPosition(const Duration(seconds: 100));
    await Future<void>.delayed(Duration.zero);
    final events = <VmEvent>[];
    final sub = e2.events.listen(events.add);
    k2.emitPosition(const Duration(seconds: 295));
    await Future<void>.delayed(Duration.zero);
    expect(e2.state.timeshiftBehind, isNull);
    expect(events.whereType<VmLiveEdgeReached>(), isNotEmpty);
    await sub.cancel();
    await e2.dispose();
  });

  test('VmTimeshiftChanged fires only when the whole-second lag changes', () async {
    final k2 = FakeKernel();
    final e2 = VmEngine(
      kernel: k2,
      options: const VmOptions(live: VmLiveConfig(seekMode: VmLiveSeekMode.dvr)),
    );
    await e2.open(const VmSource('https://host/l.m3u8', type: VmStreamType.live));
    k2.emitDuration(const Duration(seconds: 300));
    await Future<void>.delayed(Duration.zero);
    final events = <VmEvent>[];
    final sub = e2.events.listen(events.add);
    // All three ticks quantise to the same whole-second lag (199s): the raw
    // lags are 199.8s / 199.4s / 199.1s, which truncate to 199 every time.
    //
    // 三次 tick 量化后落后量相同（均为 199 秒）：原始落后量分别是 199.8 /
    // 199.4 / 199.1 秒，截断后都是 199。
    k2.emitPosition(const Duration(milliseconds: 100200));
    k2.emitPosition(const Duration(milliseconds: 100600));
    k2.emitPosition(const Duration(milliseconds: 100900));
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<VmTimeshiftChanged>().length, 1,
        reason: 'sub-second jitter must not spam the event stream');
    await sub.cancel();
    await e2.dispose();
  });

  test('an injected windowResolver overrides the kernel duration', () async {
    final k2 = FakeKernel();
    final e2 = VmEngine(
      kernel: k2,
      options: VmOptions(
        live: VmLiveConfig(
          seekMode: VmLiveSeekMode.dvr,
          windowResolver: (_) => const Duration(seconds: 120),
        ),
      ),
    );
    await e2.open(const VmSource('https://host/l.m3u8', type: VmStreamType.live));
    k2.emitDuration(const Duration(seconds: 300));
    await Future<void>.delayed(Duration.zero);
    expect(e2.state.seekableWindow, const Duration(seconds: 120));
    await e2.dispose();
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/engine_test.dart`
Expected: FAIL — 「a dvr live stream reports how far behind the edge it is」等项失败，
`expected: Duration:0:03:20.000000  actual: <null>`（`timeshiftBehind` 从未被写入）

- [ ] **Step 3: engine 改造**

`lib/src/core/engine.dart`：

1. 顶部补 import：

```dart
import 'live/timeshift.dart';
```

2. `_resolveWindow()` 整个方法**删除**，`_recomputeLiveSeekable()` 里改为调纯函数：

```dart
  void _recomputeLiveSeekable() {
    final window = resolveWindow(state, options.live);
    final seekable = state.type == VmStreamType.live &&
        options.live.seekMode != VmLiveSeekMode.off &&
        window > Duration.zero;
    _state.emit(state.copyWith(liveSeekable: seekable, seekableWindow: window));
    _updateTimeshift(_lastPosition);
  }
```

3. `_positionSub` 的回调体内，`_lastPosition = v;` 之后插入：

```dart
      _updateTimeshift(v);
```

4. 新增归约方法（放在 `_recomputeLiveSeekable()` 之后）：

```dart
  /// Recomputes [VmState.timeshiftBehind] from [position] and announces the
  /// transition on the event stream.
  ///
  /// The lag is quantised to whole seconds before comparison: position ticks
  /// arrive several times a second, and emitting a new [VmState] for every
  /// sub-second change would turn the deduplicated [states] stream into a
  /// high-frequency one — exactly what phase A avoided by keeping position out
  /// of [VmState]. Second-level precision is all the `-MM:SS` indicator needs.
  ///
  /// 依据 [position] 重算 [VmState.timeshiftBehind]，并在事件流上广播其变化。
  ///
  /// 落后量在比较前先量化到整秒：position 每秒到达数次，若每次亚秒级变化都发一个
  /// 新的 [VmState]，去重后的 [states] 流就会退化成高频流——这正是阶段 A 把
  /// position 排除在 [VmState] 之外所要避免的。`-MM:SS` 指示器也只需要秒级精度。
  ///
  /// - [position]: latest known playhead position / 最近已知的播放位置
  void _updateTimeshift(Duration position) {
    final live = state.type == VmStreamType.live && state.liveSeekable;
    final raw = live
        ? behindOf(position, state.seekableWindow, options.live.edgeThreshold)
        : null;
    final behind = raw == null ? null : Duration(seconds: raw.inSeconds);
    if (behind == state.timeshiftBehind) return;
    if (behind == null) {
      _state.emit(state.copyWith(clearTimeshift: true));
      if (live) _events.add(const VmLiveEdgeReached());
    } else {
      _state.emit(state.copyWith(timeshiftBehind: behind));
      _events.add(VmTimeshiftChanged(behind));
    }
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/engine_test.dart && flutter analyze`
Expected: 全绿（既有项一项不变 + 新增 5 项），analyze 0 issues

> 若既有的「seek is allowed for live sources in dvr mode and clamped to the window」失败，
> 说明 `_recomputeLiveSeekable()` 里新增的 `_updateTimeshift` 调用改变了 `seekableWindow`
> 的时序——检查 `_updateTimeshift` 是否在 `_state.emit` **之后**调用（必须是之后，它要读
> 刚写入的 `seekableWindow`）。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(videoman): reduce live timeshift lag into VmState and announce edge transitions"
```

---

## Task 4: `timeshift` 模式的换源 seek

DESIGN §8：「**timeshift**：`onChangeEnd` 时用 `urlBuilder` 生成带起播时间的 URL 重开源；
`behind = window - value`」。同时修一个既有小问题：`seek()` 的 clamp 上界用的是
`state.duration`，但 `timeshift` 模式下窗口可能来自 `dvrWindow`/`windowResolver` 而 duration 为 0，
此时 clamp 形同虚设。改成按直播窗口 clamp。

**Files:**
- Modify: `lib/src/core/engine.dart`
- Test: `test/core/engine_test.dart`（追加 5 项）

**Interfaces:**
- Consumes: `VmTimeshiftBuilder`（Task 1）、`VmTimeshiftChanged` / `VmLiveEdgeReached`（已存在）
- Produces: 无新公开类型；`seek()` 在 `timeshift` 模式下的换源语义

- [ ] **Step 1: 追加失败测试到 `test/core/engine_test.dart`**

`main()` 末尾追加：

```dart
  test('timeshift seek reopens the stream at the url the builder returns', () async {
    final k2 = FakeKernel();
    final e2 = VmEngine(
      kernel: k2,
      options: VmOptions(
        live: VmLiveConfig(
          seekMode: VmLiveSeekMode.timeshift,
          dvrWindow: const Duration(seconds: 600),
          urlBuilder: (uri, behind, at) => '$uri?behind=${behind.inSeconds}',
        ),
      ),
    );
    await e2.open(const VmSource('https://host/l.m3u8', type: VmStreamType.live));
    await Future<void>.delayed(Duration.zero);
    k2.calls.clear();
    await e2.seek(const Duration(seconds: 100));
    expect(k2.lastUri, 'https://host/l.m3u8?behind=500');
    expect(k2.calls, contains('open'));
    expect(k2.calls, isNot(contains('seek')));
    expect(e2.state.timeshiftBehind, const Duration(seconds: 500));
    await e2.dispose();
  });

  test('timeshift seek is a no-op when no urlBuilder is supplied', () async {
    final k2 = FakeKernel();
    final e2 = VmEngine(
      kernel: k2,
      options: const VmOptions(
        live: VmLiveConfig(
          seekMode: VmLiveSeekMode.timeshift,
          dvrWindow: Duration(seconds: 600),
        ),
      ),
    );
    await e2.open(const VmSource('https://host/l.m3u8', type: VmStreamType.live));
    k2.calls.clear();
    await e2.seek(const Duration(seconds: 100));
    expect(k2.calls, isEmpty);
    await e2.dispose();
  });

  test('a timeshift seek landing inside the edge threshold reports the edge', () async {
    final k2 = FakeKernel();
    final e2 = VmEngine(
      kernel: k2,
      options: VmOptions(
        live: VmLiveConfig(
          seekMode: VmLiveSeekMode.timeshift,
          dvrWindow: const Duration(seconds: 600),
          urlBuilder: (uri, behind, at) => '$uri?behind=${behind.inSeconds}',
        ),
      ),
    );
    await e2.open(const VmSource('https://host/l.m3u8', type: VmStreamType.live));
    final events = <VmEvent>[];
    final sub = e2.events.listen(events.add);
    await e2.seek(const Duration(seconds: 595));
    await Future<void>.delayed(Duration.zero);
    expect(e2.state.timeshiftBehind, isNull);
    expect(events.whereType<VmLiveEdgeReached>(), isNotEmpty);
    await sub.cancel();
    await e2.dispose();
  });

  test('a live seek is clamped to the window even when duration is unknown', () async {
    final k2 = FakeKernel();
    final e2 = VmEngine(
      kernel: k2,
      options: const VmOptions(
        live: VmLiveConfig(
          seekMode: VmLiveSeekMode.dvr,
          dvrWindow: Duration(seconds: 120),
        ),
      ),
    );
    await e2.open(const VmSource('https://host/l.m3u8', type: VmStreamType.live));
    await Future<void>.delayed(Duration.zero);
    await e2.seek(const Duration(seconds: 999));
    expect(k2.lastSeek, const Duration(seconds: 120));
    await e2.dispose();
  });

  test('beforeSeek still gates a timeshift seek', () async {
    final k2 = FakeKernel();
    final e2 = VmEngine(
      kernel: k2,
      interceptors: [_CancelSeek()],
      options: VmOptions(
        live: VmLiveConfig(
          seekMode: VmLiveSeekMode.timeshift,
          dvrWindow: const Duration(seconds: 600),
          urlBuilder: (uri, behind, at) => '$uri?behind=${behind.inSeconds}',
        ),
      ),
    );
    await e2.open(const VmSource('https://host/l.m3u8', type: VmStreamType.live));
    k2.calls.clear();
    await e2.seek(const Duration(seconds: 100));
    expect(k2.calls, isEmpty);
    await e2.dispose();
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/engine_test.dart`
Expected: FAIL — 「timeshift seek reopens the stream at the url the builder returns」失败，
`expected: 'https://host/l.m3u8?behind=500'  actual: 'https://host/l.m3u8'`（当前实现直接 `_kernel.seek`）

- [ ] **Step 3: 改造 `seek()` 并加 `_seekTimeshift()`**

`lib/src/core/engine.dart` 的 `seek()` 整体替换为：

```dart
  @override
  Future<void> seek(Duration to) async {
    final gate = state.type == VmStreamType.vod || state.liveSeekable;
    if (!gate) return;
    final t = await _chain.beforeSeek(to);
    if (t == null) return;
    // For a seekable live stream the meaningful upper bound is the DVR
    // window, not `duration` — with an explicit dvrWindow/windowResolver the
    // kernel may report no duration at all.
    //
    // 对可拖动的直播流，有意义的上界是 DVR 窗口而非 `duration`——配置了显式
    // dvrWindow/windowResolver 时，内核可能根本不报告时长。
    final limit = state.type == VmStreamType.live && state.liveSeekable
        ? state.seekableWindow
        : state.duration;
    final clamped = limit > Duration.zero
        ? Duration(milliseconds: t.inMilliseconds.clamp(0, limit.inMilliseconds))
        : t;
    if (state.type == VmStreamType.live &&
        options.live.seekMode == VmLiveSeekMode.timeshift) {
      await _seekTimeshift(clamped);
      return;
    }
    _events.add(VmSeeking(clamped));
    await _kernel.seek(clamped);
    _events.add(VmSeeked(clamped));
  }
```

在 `_updateTimeshift()` 之后新增：

```dart
  /// Performs a time-shift seek by reopening the stream at a host-built URL.
  ///
  /// Unlike DVR mode there is nothing to seek within: the live URL only ever
  /// serves the edge, so the only way to replay is to open a different URL
  /// carrying the desired start time. [VmLiveConfig.urlBuilder] is the sole
  /// source of that URL — without it the mode is inert and this is a no-op,
  /// because guessing a server's time-shift parameter would silently open a
  /// wrong (or 404) stream.
  ///
  /// 通过用宿主构造的 URL 重开流来完成一次时移拖动。
  ///
  /// 与 DVR 模式不同，这里没有可供 seek 的内容：直播地址永远只提供边缘内容，
  /// 想回看就只能打开另一个携带目标起播时间的地址。[VmLiveConfig.urlBuilder]
  /// 是该地址的唯一来源——没有它本模式不生效、本方法为空操作，因为猜测服务端
  /// 的时移参数只会静默打开一个错误（或 404）的流。
  ///
  /// - [target]: the clamped in-window target position / 已 clamp 的窗口内目标位置
  Future<void> _seekTimeshift(Duration target) async {
    final src = _source;
    final builder = options.live.urlBuilder;
    if (src == null || builder == null) return;
    final window = state.seekableWindow;
    final raw = window > target ? window - target : Duration.zero;
    final behind = Duration(seconds: raw.inSeconds);
    _events.add(VmSeeking(target));
    await _kernel.open(builder(src.uri, behind, DateTime.now()), play: true);
    if (behind <= options.live.edgeThreshold) {
      _state.emit(state.copyWith(clearTimeshift: true));
      _events.add(const VmLiveEdgeReached());
    } else {
      _state.emit(state.copyWith(timeshiftBehind: behind));
      _events.add(VmTimeshiftChanged(behind));
    }
    _events.add(VmSeeked(target));
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/engine_test.dart && flutter analyze`
Expected: 全绿（新增 5 项），analyze 0 issues

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(videoman): implement timeshift seeking by reopening at a host-built url"
```

---

## Task 5: `backToLiveEdge()` 策略化与卡顿自动回边缘

`backToLiveEdge()` 当前是阶段 A 的占位（`reload()` + 发事件，`engine.dart:418-422`）。
按 DESIGN §6.2「回直播方式 | dvr→seek 末端；timeshift→重开」做实，并补
`autoBackToLiveOnStall`（默认关）。

**为什么不复用 `reload()`**：`reload()` 走的是完整的 `open()`——会清空清晰度列表、发
`VmSourceChanged`/`VmReady`、重跑拦截链。回边缘只是换个播放位置，不该让 UI 以为换了源。
所以直接调 `_kernel.open(_source!.uri)`。这一点对 `timeshift` 模式尤其关键：`_source.uri`
始终是**原始**直播地址，而内核当前打开的是带时间参数的时移地址。

**Files:**
- Modify: `lib/src/core/engine.dart`
- Test: `test/core/engine_test.dart`（追加 5 项）

**Interfaces:**
- Consumes: `VmBackToLive` / `VmLiveConfig.effectiveBackToLive` / `autoBackToLiveOnStall`（Task 1）
- Produces: 无新公开类型；`backToLiveEdge()` 的真实语义

- [ ] **Step 1: 追加失败测试到 `test/core/engine_test.dart`**

`main()` 末尾追加：

```dart
  test('backToLiveEdge in dvr mode seeks to the window end without reopening', () async {
    final k2 = FakeKernel();
    final e2 = VmEngine(
      kernel: k2,
      options: const VmOptions(live: VmLiveConfig(seekMode: VmLiveSeekMode.dvr)),
    );
    await e2.open(const VmSource('https://host/l.m3u8', type: VmStreamType.live));
    k2.emitDuration(const Duration(seconds: 300));
    k2.emitPosition(const Duration(seconds: 100));
    await Future<void>.delayed(Duration.zero);
    k2.calls.clear();
    await e2.backToLiveEdge();
    expect(k2.calls, ['seek']);
    expect(k2.lastSeek, const Duration(seconds: 300));
    expect(e2.state.timeshiftBehind, isNull);
    await e2.dispose();
  });

  test('backToLiveEdge in timeshift mode reopens the original live url', () async {
    final k2 = FakeKernel();
    final e2 = VmEngine(
      kernel: k2,
      options: VmOptions(
        live: VmLiveConfig(
          seekMode: VmLiveSeekMode.timeshift,
          dvrWindow: const Duration(seconds: 600),
          urlBuilder: (uri, behind, at) => '$uri?behind=${behind.inSeconds}',
        ),
      ),
    );
    await e2.open(const VmSource('https://host/l.m3u8', type: VmStreamType.live));
    await e2.seek(const Duration(seconds: 100));
    expect(k2.lastUri, 'https://host/l.m3u8?behind=500');
    k2.calls.clear();
    await e2.backToLiveEdge();
    expect(k2.calls, ['open']);
    expect(k2.lastUri, 'https://host/l.m3u8',
        reason: 'must reopen the original url, not the time-shifted one');
    expect(e2.state.timeshiftBehind, isNull);
    await e2.dispose();
  });

  test('an explicit backToLive strategy overrides the mode-derived one', () async {
    final k2 = FakeKernel();
    final e2 = VmEngine(
      kernel: k2,
      options: const VmOptions(
        live: VmLiveConfig(
          seekMode: VmLiveSeekMode.dvr,
          backToLive: VmBackToLive.reopen,
        ),
      ),
    );
    await e2.open(const VmSource('https://host/l.m3u8', type: VmStreamType.live));
    k2.emitDuration(const Duration(seconds: 300));
    await Future<void>.delayed(Duration.zero);
    k2.calls.clear();
    await e2.backToLiveEdge();
    expect(k2.calls, ['open']);
    await e2.dispose();
  });

  test('backToLiveEdge is a no-op for a VOD source', () async {
    await e.open(const VmSource('https://host/a.mp4'));
    k.calls.clear();
    await e.backToLiveEdge();
    expect(k.calls, isEmpty);
  });

  test('autoBackToLiveOnStall jumps back only while time-shifted and only when on', () async {
    final k2 = FakeKernel();
    final e2 = VmEngine(
      kernel: k2,
      options: const VmOptions(
        live: VmLiveConfig(
          seekMode: VmLiveSeekMode.dvr,
          autoBackToLiveOnStall: true,
        ),
      ),
    );
    await e2.open(const VmSource('https://host/l.m3u8', type: VmStreamType.live));
    k2.emitDuration(const Duration(seconds: 300));
    await Future<void>.delayed(Duration.zero);

    // At the edge: a stall must not move the playhead.
    // 在边缘：卡顿不应移动播放头。
    k2.emitPosition(const Duration(seconds: 298));
    await Future<void>.delayed(Duration.zero);
    k2.calls.clear();
    k2.emitBuffering(true);
    await Future<void>.delayed(Duration.zero);
    expect(k2.calls, isEmpty);

    // Time-shifted: a stall jumps back to the edge.
    // 时移中：卡顿会跳回边缘。
    k2.emitBuffering(false);
    k2.emitPosition(const Duration(seconds: 50));
    await Future<void>.delayed(Duration.zero);
    k2.calls.clear();
    k2.emitBuffering(true);
    await Future<void>.delayed(Duration.zero);
    expect(k2.calls, contains('seek'));
    await e2.dispose();
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/engine_test.dart`
Expected: FAIL — 「backToLiveEdge in dvr mode seeks to the window end without reopening」失败，
`expected: ['seek']  actual: ['open']`（当前占位实现走的是 `reload()`）

- [ ] **Step 3: 实现**

`lib/src/core/engine.dart`：

1. 加重入保护字段（放在 `_abrDownshiftInFlight` 之后）：

```dart
  /// Reentrancy guard for [_maybeAutoBackToLive]: true while an automatic
  /// back-to-edge jump is still in flight. Buffering can flap several times
  /// per second, and each overlapping jump would issue another kernel
  /// `seek()`/`open()` on top of the previous one.
  ///
  /// [_maybeAutoBackToLive] 的重入保护：为真表示一次自动回边缘仍在进行中。
  /// 缓冲状态每秒可能翻转数次，若不加保护，每次翻转都会在上一次未完成时再向
  /// 内核发一次 `seek()`/`open()`。
  bool _autoBackToLiveInFlight = false;
```

2. `_bufferingSub` 的回调体内，`_handleAbrBuffering(v);` 之后插入：

```dart
      _maybeAutoBackToLive(v);
```

3. `backToLiveEdge()` 整体替换：

```dart
  @override
  Future<void> backToLiveEdge() async {
    if (state.type != VmStreamType.live) return;
    switch (options.live.effectiveBackToLive) {
      case VmBackToLive.seekEnd:
        final window = state.seekableWindow;
        if (state.liveSeekable && window > Duration.zero) {
          await _kernel.seek(window);
        } else {
          await _reopenLiveSource();
        }
      case VmBackToLive.reopen:
        await _reopenLiveSource();
    }
    _state.emit(state.copyWith(clearTimeshift: true));
    _events.add(const VmLiveEdgeReached());
  }
```

4. 新增两个私有方法（放在 `_seekTimeshift()` 之后）：

```dart
  /// Reopens the original live URL on the kernel, bypassing [open].
  ///
  /// [open] would clear the quality list and emit
  /// [VmSourceChanged]/[VmReady], telling the UI the source changed — but
  /// returning to the edge is a position change, not a source change. It also
  /// matters in [VmLiveSeekMode.timeshift]: [_source] still holds the
  /// *original* live URL while the kernel currently has a time-shifted one
  /// open, so this is what actually catches back up.
  ///
  /// 绕过 [open]，直接让内核重新打开原始直播地址。
  ///
  /// 走 [open] 会清空清晰度列表并发出 [VmSourceChanged]/[VmReady]，告诉 UI
  /// 源变了——但回到边缘只是位置变化，不是换源。这一点在
  /// [VmLiveSeekMode.timeshift] 下尤其关键：[_source] 里存的仍是**原始**直播
  /// 地址，而内核当前打开的是带时间参数的时移地址，重开原始地址才能真正追上。
  Future<void> _reopenLiveSource() async {
    final s = _source;
    if (s == null) return;
    await _kernel.open(s.uri, play: true);
  }

  /// Jumps back to the live edge on a stall, when configured to.
  ///
  /// Only fires on a rising stall while actually time-shifted: a stall at the
  /// edge has nowhere to jump to, and jumping while the user is deliberately
  /// replaying would silently discard their chosen position — which is why
  /// [VmLiveConfig.autoBackToLiveOnStall] defaults to off.
  ///
  /// 在配置开启时，卡顿则跳回直播边缘。
  ///
  /// 仅在**确实处于时移状态**且卡顿发生时触发：在边缘卡顿无处可跳；而用户正在
  /// 主动回看时跳走会悄悄丢掉他选定的位置——这正是
  /// [VmLiveConfig.autoBackToLiveOnStall] 默认关闭的原因。
  ///
  /// - [buffering]: the latest buffering flag / 最新的缓冲标志
  void _maybeAutoBackToLive(bool buffering) {
    if (!buffering) return;
    if (!options.live.autoBackToLiveOnStall) return;
    if (state.type != VmStreamType.live) return;
    if (state.timeshiftBehind == null) return;
    if (_autoBackToLiveInFlight) return;
    _autoBackToLiveInFlight = true;
    unawaited(
      backToLiveEdge().whenComplete(() => _autoBackToLiveInFlight = false),
    );
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test && flutter analyze`
Expected: 全绿（新增 5 项），analyze 0 issues

> 既有的 `test/ui/live_bar_test.dart` 的「back-to-edge button reloads the stream」此刻**仍应通过**
> ——它断言的是 `api.reload()` 被调用，而 UI 还没改（Task 6 才改）。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(videoman): make backToLiveEdge strategy-driven and add stall auto-recovery"
```

---

## Task 6: 直播控制条（seekBar / 时移标签 / 边缘态角标 / 回直播按钮）

DESIGN §8 的 UI 部分 + §5.4 的直播树 `bottomBar/{liveBadge, seekBar, timeshift, backToLive}`。

三处语义变更，都是**刻意的破坏性变更**（0.2.0 尚未发布，可接受，Task 12 写进 CHANGELOG）：

1. `BackToEdgeComponent`（name `backToEdge`，调 `api.reload()`）→ `BackToLiveComponent`
   （name `backToLive`，调 `api.backToLiveEdge()`）。patch 路径 `bottomBar/backToEdge`
   随之变为 `bottomBar/backToLive`。
2. `VmStrings.backToEdge` 删除——它的唯一使用点被 `VmStrings.backToLive` 取代，留着就是死配置。
3. `SeekBarComponent` 的量程：直播可拖时取 `seekableWindow`，其余取 `duration`。

**Files:**
- Modify: `lib/src/ui/components/live_bar.dart`, `lib/src/ui/components/bottom_bar.dart`,
  `lib/src/ui/skins/default_skin.dart`, `lib/src/core/options/strings.dart`,
  `lib/src/core/options/theme.dart`
- Test: `test/ui/live_bar_test.dart`（改 1 项 + 追加 6 项）

**Interfaces:**
- Consumes: `VmState.liveSeekable` / `seekableWindow` / `timeshiftBehind`、`VmStrings.live` /
  `timeshift` / `backToLive`、`formatDuration`（`lib/src/ui/format.dart`）
- Produces:
  - `VmTheme.timeshiftBadgeColor`（默认 `0xFF616161`）
  - `class LiveBarComponent extends VmComponent { LiveBarComponent({bool seekable = false}); final bool seekable; }`
  - `class TimeshiftLabelComponent extends VmComponent`（name `'timeshift'`）
  - `class BackToLiveComponent extends VmComponent`（name `'backToLive'`）
  - `LiveBadgeComponent` 按 `timeshiftBehind` 切换配色/文案（类名与 name 不变）

- [ ] **Step 1: 改写并追加 `test/ui/live_bar_test.dart`**

整个文件替换为：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/state/state.dart';
import 'package:videoman/src/ui/components/live_bar.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// A live state at the edge of a 300-second DVR window.
///
/// 处于 300 秒 DVR 窗口边缘的直播状态。
const _atEdge = VmState(
  type: VmStreamType.live,
  liveSeekable: true,
  seekableWindow: Duration(seconds: 300),
);

/// The same window, but replaying 65 seconds behind the edge.
///
/// 同一窗口，但正在回看落后边缘 65 秒的内容。
const _behind = VmState(
  type: VmStreamType.live,
  liveSeekable: true,
  seekableWindow: Duration(seconds: 300),
  timeshiftBehind: Duration(seconds: 65),
);

void main() {
  testWidgets('a non-seekable live bar shows the LIVE badge and no seek bar', (t) async {
    final api = FakeVmApi();
    api.push(const VmState(type: VmStreamType.live));
    await pumpComponent(t, api, LiveBarComponent());
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    await api.dispose();
  });

  testWidgets('a seekable live bar shows the seek bar', (t) async {
    final api = FakeVmApi();
    api.push(_atEdge);
    await pumpComponent(t, api, LiveBarComponent(seekable: true));
    expect(find.byType(Slider), findsOneWidget);
    await api.dispose();
  });

  testWidgets('the badge reads LIVE at the edge and 时移 while replaying', (t) async {
    final api = FakeVmApi();
    api.push(_atEdge);
    await pumpComponent(t, api, LiveBarComponent(seekable: true));
    expect(find.text('LIVE'), findsOneWidget);
    api.push(_behind);
    await t.pump();
    expect(find.text('LIVE'), findsNothing);
    expect(find.text('时移'), findsOneWidget);
    await api.dispose();
  });

  testWidgets('the timeshift label shows the lag and hides at the edge', (t) async {
    final api = FakeVmApi();
    api.push(_behind);
    await pumpComponent(t, api, LiveBarComponent(seekable: true));
    expect(find.text('-01:05'), findsOneWidget);
    api.push(_atEdge);
    await t.pump();
    expect(find.text('-01:05'), findsNothing);
    await api.dispose();
  });

  testWidgets('the back-to-live button calls backToLiveEdge, not reload', (t) async {
    final api = FakeVmApi();
    api.push(_behind);
    await pumpComponent(t, api, LiveBarComponent(seekable: true));
    await t.tap(find.byIcon(Icons.sync_rounded));
    await t.pump();
    expect(api.calls, contains('backToLiveEdge'));
    expect(api.calls, isNot(contains('reload')));
    await api.dispose();
  });

  testWidgets('replacing VmStrings relabels the badge without touching components', (t) async {
    final api = FakeVmApi(
      options: const VmOptions(strings: VmStrings(live: 'ON AIR')),
    );
    api.push(_atEdge);
    await pumpComponent(t, api, LiveBarComponent(seekable: true));
    expect(find.text('ON AIR'), findsOneWidget);
    await api.dispose();
  });

  testWidgets('the live seek bar spans the DVR window, not the duration', (t) async {
    final api = FakeVmApi();
    api.push(_atEdge);
    await pumpComponent(t, api, LiveBarComponent(seekable: true));
    final slider = t.widget<Slider>(find.byType(Slider));
    expect(slider.max, 300000.0);
    await api.dispose();
  });
}
```

顶部还要 `import 'package:videoman/src/core/options/options.dart';`（`VmOptions`/`VmStrings`）。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ui/live_bar_test.dart`
Expected: FAIL — `The named parameter 'seekable' isn't defined`（`LiveBarComponent`）

- [ ] **Step 3: 加主题色并删掉死文案**

`lib/src/core/options/theme.dart`：在 `accentColor` 字段之后插入

```dart
  /// ARGB color for the badge while the live stream is time-shifted (i.e. not
  /// at the live edge).
  ///
  /// 直播处于时移状态（即不在直播边缘）时角标的 ARGB 颜色。
  final int timeshiftBadgeColor;
```

构造加 `this.timeshiftBadgeColor = 0xFF616161,`（放在 `accentColor` 之后）；
`==` 加 `timeshiftBadgeColor == other.timeshiftBadgeColor &&`；`hashCode` 的
`Object.hash(...)` 参数表里 `accentColor` 之后插入 `timeshiftBadgeColor`。

`lib/src/core/options/strings.dart`：删除 `backToEdge` 字段、其构造参数
`this.backToEdge = '回到边缘',`、`==` 里的 `backToEdge == other.backToEdge &&`、
`hashCode` 参数表里的 `backToEdge`。

- [ ] **Step 4: 重写 `lib/src/ui/components/live_bar.dart`**

整个文件替换为：

```dart
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../format.dart';
import '../scope/selector.dart';
import '../slots/component.dart';
import '../slots/slot.dart';
import 'bottom_bar.dart';
import 'common.dart';

/// Composite component for the live-stream bottom control bar.
///
/// Layout mirrors DESIGN section 5.4's live tree
/// `bottomBar/{liveBadge, seekBar, timeshift, backToLive}`. The seek bar is
/// only *placed* when [seekable]; the skin decides that from
/// `VmState.liveSeekable`, so a non-DVR stream keeps 0.1.0's badge-only bar.
///
/// 直播底部控制条组合组件。
///
/// 布局对应 DESIGN §5.4 的直播树
/// `bottomBar/{liveBadge, seekBar, timeshift, backToLive}`。进度条仅在
/// [seekable] 为真时才被**放置**；皮肤依据 `VmState.liveSeekable` 决定该值，
/// 因此非 DVR 流保持 0.1.0 那种只有角标的底栏。
class LiveBarComponent extends VmComponent {
  /// Creates the live-bar composite.
  ///
  /// [seekable] decides whether the seek bar is laid out; defaults to `false`
  /// so a bare `LiveBarComponent()` reproduces the non-seekable live bar.
  ///
  /// 创建直播底栏组合组件。
  ///
  /// [seekable] 决定是否布置进度条；默认 `false`，因此裸的
  /// `LiveBarComponent()` 复现不可拖动的直播底栏。
  LiveBarComponent({this.seekable = false});

  /// Whether this stream can be scrubbed within its DVR window.
  ///
  /// 该流是否可在其 DVR 窗口内拖动。
  final bool seekable;

  @override
  String get name => 'bottomBar';

  @override
  VmSlot get slot => VmSlot.bottom;

  // The child list is fixed-length regardless of [seekable] so child indices
  // (and therefore patch paths) never shift; only placement varies.
  //
  // 无论 [seekable] 取值，子组件列表长度恒定，使子节点下标（以及 patch 路径）
  // 永不错位；变化的只是是否布置。
  @override
  List<VmComponent> get children => [
        LiveBadgeComponent(),
        SeekBarComponent(),
        TimeshiftLabelComponent(),
        BackToLiveComponent(),
      ];

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmGradientBar(
      top: false,
      theme: theme,
      child: Row(
        children: [
          const SizedBox(width: 8),
          children[0],
          if (seekable) Expanded(child: children[1]) else const Spacer(),
          children[2],
          children[3],
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// The live/time-shift badge: a red `LIVE` pill at the edge, a muted
/// `时移` pill while replaying.
///
/// Colour and copy both come from options ([VmTheme.accentColor] /
/// [VmTheme.timeshiftBadgeColor], [VmStrings.live] / [VmStrings.timeshift]).
///
/// 直播/时移角标：在边缘时是红色 `LIVE` 胶囊，回看时是灰色 `时移` 胶囊。
///
/// 配色与文案都取自配置（[VmTheme.accentColor] / [VmTheme.timeshiftBadgeColor]、
/// [VmStrings.live] / [VmStrings.timeshift]）。
class LiveBadgeComponent extends VmComponent {
  /// Creates the live-badge leaf component.
  ///
  /// 创建直播角标叶子组件。
  LiveBadgeComponent();

  @override
  String get name => 'liveBadge';

  // Inert: this component is only ever nested under [LiveBarComponent],
  // which lays out its children directly rather than via slot placement.
  //
  // 无效：该组件始终嵌套在 [LiveBarComponent] 之下，父组件直接通过 children
  // 布局，而非按槽位放置。
  @override
  VmSlot get slot => VmSlot.bottom;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    final strings = api.options.strings;
    return VmSelector<bool>(
      selector: (s) => s.timeshiftBehind == null,
      builder: (context, atEdge) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Color(atEdge ? theme.accentColor : theme.timeshiftBadgeColor),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            atEdge ? strings.live : strings.timeshift,
            style: TextStyle(
              color: Color(theme.textColor),
              fontWeight: FontWeight.bold,
              fontSize: theme.badgeFontSize,
            ),
          ),
        );
      },
    );
  }
}

/// Shows how far behind the live edge playback currently is, as `-MM:SS`.
///
/// Renders nothing at the live edge, so the bar is visually identical to a
/// plain live stream until the user actually scrubs back.
///
/// 以 `-MM:SS` 展示当前落后直播边缘的时长。
///
/// 处于直播边缘时不渲染任何内容，因此在用户真正回看之前，底栏与普通直播流
/// 在视觉上完全一致。
class TimeshiftLabelComponent extends VmComponent {
  /// Creates the timeshift-label leaf component.
  ///
  /// 创建时移标签叶子组件。
  TimeshiftLabelComponent();

  @override
  String get name => 'timeshift';

  // Inert: nested under [LiveBarComponent], which positions it directly.
  //
  // 无效：嵌套在 [LiveBarComponent] 之下，由父组件直接定位。
  @override
  VmSlot get slot => VmSlot.bottom;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmSelector<Duration?>(
      selector: (s) => s.timeshiftBehind,
      builder: (context, behind) {
        if (behind == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '-${formatDuration(behind)}',
            style: TextStyle(
              color: Color(theme.textColor),
              fontSize: theme.timeFontSize,
            ),
          ),
        );
      },
    );
  }
}

/// Button returning playback to the live edge.
///
/// Delegates the *how* entirely to [VmApi.backToLiveEdge], which follows
/// `VmLiveConfig.effectiveBackToLive` (seek to the window end for DVR, reopen
/// the original URL for time-shift). Replaces 0.1.0's `backToEdge` button,
/// which called `reload()` unconditionally.
///
/// 让播放回到直播边缘的按钮。
///
/// **具体怎么回**完全交给 [VmApi.backToLiveEdge]，由
/// `VmLiveConfig.effectiveBackToLive` 决定（DVR 跳到窗口末端，时移则重开原始
/// 地址）。它取代了 0.1.0 里无条件调用 `reload()` 的 `backToEdge` 按钮。
class BackToLiveComponent extends VmComponent {
  /// Creates the back-to-live leaf component.
  ///
  /// 创建回到直播叶子组件。
  BackToLiveComponent();

  @override
  String get name => 'backToLive';

  // Inert: nested under [LiveBarComponent], which positions it directly.
  //
  // 无效：嵌套在 [LiveBarComponent] 之下，由父组件直接定位。
  @override
  VmSlot get slot => VmSlot.bottom;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    final strings = api.options.strings;
    return VmIconButton(
      icon: Icons.sync_rounded,
      caption: strings.backToLive,
      theme: theme,
      onPressed: api.backToLiveEdge,
    );
  }
}
```

- [ ] **Step 5: `SeekBarComponent` 量程改为按流类型取值**

`lib/src/ui/components/bottom_bar.dart` 的 `SeekBarComponent.build` 替换为：

```dart
  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    return VmSelector<Duration>(
      selector: (s) => s.type == VmStreamType.live && s.liveSeekable
          ? s.seekableWindow
          : s.duration,
      builder: (context, span) => _SeekBar(api: api, duration: span),
    );
  }
```

顶部补 `import '../../core/model/source.dart';`。

类文档注释里补一句（中英各一行）：

```dart
/// For a seekable live stream the span is the DVR window rather than
/// `duration`, so one component serves both VOD and DVR live (DESIGN §5.4).
///
/// 对可拖动的直播流，量程取 DVR 窗口而非 `duration`，因此同一个组件同时服务
/// 点播与可拖直播（DESIGN §5.4）。
```

- [ ] **Step 6: 皮肤传 `seekable`**

`lib/src/ui/skins/default_skin.dart` 的 `components(VmState s)` 里，把

```dart
        s.type == VmStreamType.live ? LiveBarComponent() : BottomBarComponent(),
```

改为

```dart
        s.type == VmStreamType.live
            ? LiveBarComponent(seekable: s.liveSeekable)
            : BottomBarComponent(),
```

- [ ] **Step 7: 跑测试与分析**

Run: `flutter test && flutter analyze`
Expected: 全绿（live_bar 7 项），analyze 0 issues

`test/ui/skin_test.dart:26`（测试 `'default skin emits the live tree for a live source'`）断言的是

```dart
    expect(bottom.children.map((c) => c.name), ['liveBadge', 'backToEdge']);
```

改成

```dart
    expect(bottom.children.map((c) => c.name),
        ['liveBadge', 'seekBar', 'timeshift', 'backToLive']);
```

这是本阶段**唯一**允许改动的阶段 A 既有断言，因为组件树的直播分支语义确实变了。

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(videoman): add seek bar, timeshift indicator and back-to-live button to the live bar"
```

---

## Task 7: 直播手势门控回归测试

**本任务不改任何生产代码。** 阶段 A 已经把 `gesture_layer.dart` 的 `_seekAllowed` 写成
`!live || (allowWhenLive && liveSeekable)`（`gesture_layer.dart:177-183`），刻意为阶段 C 预留。
但当时没有直播可拖的场景，这条分支从未被测过。本任务把它钉住，防止以后被"简化"掉。

**Files:**
- Test: `test/ui/gesture_test.dart`（追加 4 项，不动既有 4 项）

**Interfaces:**
- Consumes: `GestureLayerComponent`、`VmState.liveSeekable`、`VmGestureConfig.allowWhenLive`
- Produces: 无

- [ ] **Step 1: 追加失败测试到 `test/ui/gesture_test.dart`**

先读一遍文件顶部，沿用它既有的 import 与拖动辅助写法（阶段 A 已有 4 项手势测试，
其中一项就是"直播禁滑"，本任务的新用例应与它同构）。在 `main()` 末尾追加：

```dart
  testWidgets('horizontal drag seeks a seekable live stream', (t) async {
    final api = FakeVmApi();
    api.push(const VmState(
      type: VmStreamType.live,
      liveSeekable: true,
      seekableWindow: Duration(seconds: 300),
    ));
    await pumpComponent(t, api, GestureLayerComponent());
    await t.drag(find.byType(GestureDetector).last, const Offset(120, 0));
    await t.pump();
    expect(api.calls, contains('seek'));
    await api.dispose();
  });

  testWidgets('horizontal drag stays blocked on a non-seekable live stream', (t) async {
    final api = FakeVmApi();
    api.push(const VmState(type: VmStreamType.live));
    await pumpComponent(t, api, GestureLayerComponent());
    await t.drag(find.byType(GestureDetector).last, const Offset(120, 0));
    await t.pump();
    expect(api.calls, isNot(contains('seek')));
    await api.dispose();
  });

  testWidgets('allowWhenLive=false blocks seeking even when liveSeekable', (t) async {
    final api = FakeVmApi(
      options: const VmOptions(gesture: VmGestureConfig(allowWhenLive: false)),
    );
    api.push(const VmState(
      type: VmStreamType.live,
      liveSeekable: true,
      seekableWindow: Duration(seconds: 300),
    ));
    await pumpComponent(t, api, GestureLayerComponent());
    await t.drag(find.byType(GestureDetector).last, const Offset(120, 0));
    await t.pump();
    expect(api.calls, isNot(contains('seek')));
    await api.dispose();
  });

  testWidgets('double tap seeks a seekable live stream and is blocked otherwise', (t) async {
    final seekable = FakeVmApi();
    seekable.push(const VmState(
      type: VmStreamType.live,
      liveSeekable: true,
      seekableWindow: Duration(seconds: 300),
    ));
    await pumpComponent(t, seekable, GestureLayerComponent());
    await t.tap(find.byType(GestureDetector).last);
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.byType(GestureDetector).last);
    await t.pump(const Duration(milliseconds: 400));
    expect(seekable.calls, contains('seek'));
    await seekable.dispose();

    final locked = FakeVmApi();
    locked.push(const VmState(type: VmStreamType.live));
    await pumpComponent(t, locked, GestureLayerComponent());
    await t.tap(find.byType(GestureDetector).last);
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.byType(GestureDetector).last);
    await t.pump(const Duration(milliseconds: 400));
    expect(locked.calls, isNot(contains('seek')));
    await locked.dispose();
  });
```

若顶部缺 import，补 `package:videoman/src/core/model/source.dart`、
`package:videoman/src/core/options/options.dart`、`package:videoman/src/core/state/state.dart`。

- [ ] **Step 2: 跑测试**

Run: `flutter test test/ui/gesture_test.dart`
Expected: **4 项新用例应当直接 PASS**——这是回归测试，不是 TDD。

若「horizontal drag seeks a seekable live stream」失败，说明 `_seekAllowed` 的实现与
`gesture_layer.dart:177-183` 读到的不一致，或拖动距离/阈值不足（`_kAxisLockThreshold` 是 8px，
120px 足够）；先核对代码再决定是改测试写法还是修实现——**不要**直接放宽断言。

- [ ] **Step 3: 跑全量**

Run: `flutter test && flutter analyze`
Expected: 全绿，analyze 0 issues

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test(videoman): pin live-seek gesture gating for dvr streams"
```

---

## Task 8: `VmApi.pipSupported` 同步能力位（阶段 A 遗留 backlog）

阶段 A 收口 review 记下的缺口，源码注释里也写死了：`lib/src/ui/components/top_bar.dart:108-127`
的 `PipButtonComponent` 类文档里有一整段 `GAP:` / `缺口：`，说明 `VmApi` 没有同步的
「是否支持 PiP」getter，所以按钮在桌面上**永远渲染且点了没反应**。`test/ui/top_bar_test.dart:24-45`
也把这个兜底行为写成了测试。本任务补上能力位。

**与阶段 B 的关系**：`VmEngine` 自身构造函数默认的 pip 端口仍是 `NoopPipPort`（恒 false，
纯 Dart 单测要用），但真实的 `ChannelPipPort` 早就有人构造了——`fix(videoman): wire real
platform adapters, restoring brightness/PiP/orientation`（commit `9c2d4f0`）已经补上
`lib/src/platform_impl/wiring.dart` 的 `createVmEngine()`，`example/lib/main.dart` 也已经
改用它，这与阶段 B 是否落地无关。本任务只补 `VmApi`/`VmState` 上缺的同步能力位，不涉及
端口装配，也不需要碰 `example/lib/main.dart`。

**Files:**
- Modify: `lib/src/core/state/state.dart`, `lib/src/core/api.dart`, `lib/src/core/engine.dart`,
  `lib/src/ui/components/top_bar.dart`, `lib/videoman.dart`, `test/support/fake_api.dart`
- Test: `test/core/state_test.dart`（追加 1 项）、`test/core/engine_test.dart`（追加 2 项）、
  `test/ui/top_bar_test.dart`（**删 1 项、加 2 项**）

**Interfaces:**
- Consumes: `VmPipPort`（`core/platform/ports.dart`，已存在）、`ChannelPipPort` /
  `ScreenBrightnessPort` / `SystemChromeOrientationPort`（`lib/src/platform_impl/*`，已存在）
- Produces:
  - `VmState.pipSupported`（`bool`，默认 `false`，进 `copyWith`/`==`/`hashCode`）
  - `abstract class VmApi { bool get pipSupported; }`
  - barrel 导出 `src/platform_impl/{brightness_impl,orientation_impl,pip_impl}.dart`

- [ ] **Step 1: 写失败测试 — state 与 engine**

`test/core/state_test.dart` 的 `main()` 末尾追加：

```dart
  test('VmState.pipSupported defaults to false and round-trips through copyWith', () {
    const s = VmState();
    expect(s.pipSupported, isFalse);
    expect(s.copyWith(pipSupported: true).pipSupported, isTrue);
    expect(s.copyWith(pipSupported: true), isNot(equals(s)));
  });
```

`test/core/engine_test.dart` 的 `main()` 末尾追加：

```dart
  test('pipSupported starts false and flips once the port answers', () async {
    final k2 = FakeKernel();
    final e2 = VmEngine(kernel: k2, pip: _YesPip());
    expect(e2.pipSupported, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(e2.pipSupported, isTrue);
    expect(e2.state.pipSupported, isTrue);
    await e2.dispose();
  });

  test('pipSupported stays false when the port throws', () async {
    final k2 = FakeKernel();
    final e2 = VmEngine(kernel: k2, pip: _ThrowingPip());
    await Future<void>.delayed(Duration.zero);
    expect(e2.pipSupported, isFalse);
    await e2.dispose();
  });
```

同文件底部（与既有的 `_CancelSeek` / `_DenyPlay` 并列）追加：

```dart
/// A pip port that reports support and always succeeds.
///
/// 报告支持画中画且总是成功的 pip 端口。
class _YesPip implements VmPipPort {
  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> enter({int? width, int? height}) async => true;
}

/// A pip port whose capability probe fails, standing in for a platform whose
/// channel is missing.
///
/// 能力探测会失败的 pip 端口，用于模拟缺少平台通道的平台。
class _ThrowingPip implements VmPipPort {
  @override
  Future<bool> isSupported() async => throw MissingPluginException('no pip');

  @override
  Future<bool> enter({int? width, int? height}) async => false;
}
```

顶部补 `import 'package:flutter/services.dart';`（`MissingPluginException`）与
`import 'package:videoman/src/core/platform/ports.dart';`。

> 测试文件可以 import flutter——`purity_test.dart` 只扫 `lib/src/core/`。

- [ ] **Step 2: 写失败测试 — UI**

`test/ui/top_bar_test.dart`：**删掉**第 24–45 行那一整块（`// NOTE: VmApi exposes no
synchronous …` 注释 + `testWidgets('pip button always shows (no sync capability check on
VmApi)', …)` 整项），换成：

```dart
  testWidgets('pip button is hidden when the platform reports no pip support', (t) async {
    final api = FakeVmApi()..pipSupported = false;
    await pumpComponent(t, api, TopBarComponent());
    expect(find.byIcon(Icons.picture_in_picture_alt_rounded), findsNothing);
    await api.dispose();
  });

  testWidgets('pip button shows and enters pip when supported', (t) async {
    final api = FakeVmApi()..pipSupported = true;
    await pumpComponent(t, api, TopBarComponent());
    await t.tap(find.byIcon(Icons.picture_in_picture_alt_rounded));
    await t.pump();
    expect(api.calls, contains('enterPip'));
    await api.dispose();
  });
```

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/core/state_test.dart test/core/engine_test.dart test/ui/top_bar_test.dart`
Expected: FAIL — `The named parameter 'pipSupported' isn't defined`（`VmState.copyWith`）、
`The getter 'pipSupported' isn't defined for the class 'VmEngine'`

- [ ] **Step 4: 加 `VmState.pipSupported`**

`lib/src/core/state/state.dart`：在 `pip` 字段之后插入

```dart
  /// Whether the current platform supports system picture-in-picture at all.
  ///
  /// Distinct from [pip], which says whether PiP is *active*. Resolved once
  /// per engine from `VmPipPort.isSupported()`; `false` until that probe
  /// answers, so UI that hides itself on `false` merely appears a frame or two
  /// late instead of flashing a button that does nothing.
  ///
  /// 当前平台是否支持系统画中画。
  ///
  /// 与 [pip] 不同——后者表示画中画是否**正在生效**。每个 engine 用
  /// `VmPipPort.isSupported()` 探测一次；探测返回前为 `false`，因此依赖它隐藏
  /// 自身的 UI 只是晚一两帧出现，而不会先闪一个点了没反应的按钮。
  final bool pipSupported;
```

构造里在 `this.pip = false,` 之后加 `this.pipSupported = false,`；
`copyWith` 参数表在 `bool? pip,` 之后加 `bool? pipSupported,`，返回体在 `pip: pip ?? this.pip,`
之后加 `pipSupported: pipSupported ?? this.pipSupported,`；
`==` 在 `other.pip == pip &&` 之后加 `other.pipSupported == pipSupported &&`；
`hashCode` 的第一个 `Object.hash(playing, buffering, completed, locked, fullscreen, pip)`
改为 `Object.hash(playing, buffering, completed, locked, fullscreen, pip, pipSupported)`。

- [ ] **Step 5: 加 `VmApi.pipSupported` 并在 engine 探测**

`lib/src/core/api.dart`：在 `Object? get renderHandle;` 之后插入

```dart
  /// Whether the current platform supports system picture-in-picture.
  ///
  /// A synchronous mirror of [VmState.pipSupported] so components can branch
  /// without a selector. Components that must *rebuild* when it flips should
  /// still watch `VmState.pipSupported` through a `VmSelector`, since the
  /// value is resolved asynchronously shortly after construction.
  ///
  /// 当前平台是否支持系统画中画。
  ///
  /// [VmState.pipSupported] 的同步镜像，便于组件不用 selector 也能分支。需要在
  /// 它翻转时**重建**的组件仍应通过 `VmSelector` 观察 `VmState.pipSupported`，
  /// 因为该值是在构造后不久异步解析出来的。
  bool get pipSupported;
```

`lib/src/core/engine.dart`：

1. `renderHandle` getter 之后加：

```dart
  @override
  bool get pipSupported => state.pipSupported;
```

2. 构造体末尾（`_errorSub = ...` 那段之后）加探测：

```dart
    // Probe pip support once. The UI hides the pip button until this answers,
    // which is why a failed probe must resolve to false rather than throw.
    //
    // 探测一次画中画支持情况。UI 在它返回前隐藏画中画按钮，因此探测失败必须
    // 归约为 false，而不能抛出。
    unawaited(
      _pip.isSupported().then((ok) {
        if (_events.isClosed) return;
        _state.emit(state.copyWith(pipSupported: ok));
      }).catchError((Object _) {}),
    );
```

- [ ] **Step 6: `PipButtonComponent` 按能力位隐藏，`FakeVmApi` 补镜像**

`lib/src/ui/components/top_bar.dart`：把 `PipButtonComponent` 类文档里从 `/// GAP:` 到
`/// 报告。` 的整段缺口说明**删掉**，换成：

```dart
/// Picture-in-picture entry button; renders nothing where PiP is unsupported.
///
/// Visibility follows [VmState.pipSupported], which the engine resolves once
/// from `VmPipPort.isSupported()` shortly after construction — so on desktop
/// the button never appears at all, rather than appearing and doing nothing.
///
/// 画中画入口按钮；平台不支持画中画时不渲染任何内容。
///
/// 可见性跟随 [VmState.pipSupported]——engine 在构造后不久用
/// `VmPipPort.isSupported()` 解析一次。因此桌面端该按钮根本不会出现，而不是
/// 出现了点了没反应。
```

`build` 替换为：

```dart
  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmSelector<bool>(
      selector: (s) => s.pipSupported,
      builder: (context, supported) {
        if (!supported) return const SizedBox.shrink();
        return VmIconButton(
          icon: Icons.picture_in_picture_alt_rounded,
          theme: theme,
          onPressed: () => api.enterPip(),
        );
      },
    );
  }
```

`test/support/fake_api.dart`：

1. `_state` 初值改为 `VmBus<VmState>(const VmState(pipSupported: true))`（保持既有"默认支持"语义）。
2. 把字段 `bool pipSupported = true;` 及其上方注释替换为一对 getter/setter，使能力 getter 与
   状态上的 `VmSelector` 永远一致：

```dart
  /// Whether this fake reports pip support; mirrored into
  /// [VmState.pipSupported] so `..pipSupported = false` also flips what any
  /// `VmSelector` on state sees.
  ///
  /// 该假对象是否报告支持画中画；会镜像进 [VmState.pipSupported]，因此
  /// `..pipSupported = false` 同时也会翻转状态上任何 `VmSelector` 看到的值。
  @override
  bool get pipSupported => state.pipSupported;

  /// Sets [pipSupported] by pushing a new state snapshot.
  ///
  /// 通过推送新状态快照来设置 [pipSupported]。
  ///
  /// - [value]: whether pip is supported / 是否支持画中画
  set pipSupported(bool value) => push(state.copyWith(pipSupported: value));
```

3. `enterPip()` 里的 `return pipSupported;` 原样保留（现在读的是 state）。

- [ ] **Step 7: 补 `brightness_impl`/`orientation_impl`/`pip_impl` 的 barrel 导出**

`lib/videoman.dart` 末尾（`export 'src/ui/slots/tree.dart';` 之后）追加：

```dart
export 'src/platform_impl/brightness_impl.dart';
export 'src/platform_impl/orientation_impl.dart';
export 'src/platform_impl/pip_impl.dart';
```

`export 'src/platform_impl/wiring.dart';` 已经存在（`9c2d4f0` 加的），不用再动；这里补的
只是这三个具体适配器类自身的导出，方便宿主想绕开 `createVmEngine()` 自己拼装时能直接
`import 'package:videoman/videoman.dart'` 拿到它们。`example/lib/main.dart` 已经在用
`createVmEngine()`（真实的 brightness/PiP/orientation 三个端口已经装好），本任务不需要
再碰它。

- [ ] **Step 8: 跑全量测试与分析**

Run: `flutter test && flutter analyze`
Expected: 全绿（state +1、engine +2、top_bar 由 1 项变 2 项），analyze 0 issues

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat(videoman): add a synchronous pip capability flag and hide the pip button without it"
```

---

## Task 9: 阶段 C 开放性对账（DESIGN §6.2）

DESIGN §6 是硬约束：**每个替用户做的决策必须齐默认值 + 配置项 + 可注入策略**。把 §6.2 的
六行表格逐行变成可执行断言，防止以后悄悄退化。

**Files:**
- Create: `test/core/openness_live_test.dart`
- Test: 全量

**Interfaces:**
- Consumes: Task 1–6 全部产物
- Produces: 一份可执行的 §6.2 对账测试

- [ ] **Step 1: 写对账测试 `test/core/openness_live_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/live/timeshift.dart';
import 'package:videoman/src/core/options/options.dart';
import 'package:videoman/src/core/state/state.dart';

void main() {
  group('DESIGN section 6.2 openness contract — every row needs default + knob + injection', () {
    test('timeshift mode: off by default, seekMode knob', () {
      expect(const VmLiveConfig().seekMode, VmLiveSeekMode.off);
      expect(const VmLiveConfig(seekMode: VmLiveSeekMode.dvr).seekMode,
          VmLiveSeekMode.dvr);
      expect(const VmLiveConfig(seekMode: VmLiveSeekMode.timeshift).seekMode,
          VmLiveSeekMode.timeshift);
    });

    test('timeshift url: no default, urlBuilder injection', () {
      expect(const VmLiveConfig().urlBuilder, isNull,
          reason: 'videoman must never guess a server timeshift parameter');
      final c = VmLiveConfig(urlBuilder: (u, b, t) => '$u!${b.inSeconds}');
      expect(c.urlBuilder!('x', const Duration(seconds: 3), DateTime(2026)), 'x!3');
    });

    test('dvr window: duration default, dvrWindow knob, windowResolver injection', () {
      const withDuration = VmState(duration: Duration(minutes: 4));
      expect(resolveWindow(withDuration, const VmLiveConfig()),
          const Duration(minutes: 4));
      expect(
        resolveWindow(withDuration,
            const VmLiveConfig(dvrWindow: Duration(minutes: 1))),
        const Duration(minutes: 1),
      );
      expect(
        resolveWindow(
          withDuration,
          VmLiveConfig(windowResolver: (_) => const Duration(minutes: 9)),
        ),
        const Duration(minutes: 9),
      );
    });

    test('edge threshold: 10s default, edgeThreshold knob', () {
      expect(const VmLiveConfig().edgeThreshold, const Duration(seconds: 10));
      expect(
        const VmLiveConfig(edgeThreshold: Duration(seconds: 30)).edgeThreshold,
        const Duration(seconds: 30),
      );
      expect(
        behindOf(const Duration(seconds: 40), const Duration(seconds: 60),
            const Duration(seconds: 30)),
        isNull,
        reason: 'a wider threshold must widen what counts as the edge',
      );
    });

    test('back-to-live: derived default, backToLive knob', () {
      expect(const VmLiveConfig(seekMode: VmLiveSeekMode.dvr).effectiveBackToLive,
          VmBackToLive.seekEnd);
      expect(
          const VmLiveConfig(seekMode: VmLiveSeekMode.timeshift).effectiveBackToLive,
          VmBackToLive.reopen);
      expect(
        const VmLiveConfig(
          seekMode: VmLiveSeekMode.timeshift,
          backToLive: VmBackToLive.seekEnd,
        ).effectiveBackToLive,
        VmBackToLive.seekEnd,
      );
    });

    test('auto back-to-live on stall: off by default, autoBackToLiveOnStall knob', () {
      expect(const VmLiveConfig().autoBackToLiveOnStall, isFalse);
      expect(
        const VmLiveConfig(autoBackToLiveOnStall: true).autoBackToLiveOnStall,
        isTrue,
      );
    });

    test('the whole section is replaceable through VmOptions.copyWith', () {
      const o = VmOptions();
      final n = o.copyWith(
          live: const VmLiveConfig(seekMode: VmLiveSeekMode.dvr));
      expect(n.live.seekMode, VmLiveSeekMode.dvr);
      expect(n.gesture, o.gesture);
      expect(n.theme, o.theme);
    });

    test('live copy and colours stay externalised (VmStrings / VmTheme)', () {
      const s = VmStrings(live: 'ON AIR', timeshift: 'REPLAY', backToLive: 'GO LIVE');
      expect(s.live, 'ON AIR');
      expect(s.timeshift, 'REPLAY');
      expect(s.backToLive, 'GO LIVE');
      expect(const VmTheme().timeshiftBadgeColor,
          isNot(const VmTheme().accentColor),
          reason: 'the timeshifted badge must be visually distinct from LIVE');
    });
  });
}
```

- [ ] **Step 2: 跑对账测试**

Run: `flutter test test/core/openness_live_test.dart`
Expected: 8 项全 PASS。**任何一项失败都说明 §6.2 有一行没落实，回对应 Task 补，不要改断言。**

- [ ] **Step 3: 硬编码扫描**

```bash
grep -rn "Colors\.\|Color(0x" lib/src/ui/components/live_bar.dart | grep -v "theme\." ; echo "--- 上面应为空 ---"
grep -rnP "['\"][\x{4e00}-\x{9fff}]" lib/src/ui/components/live_bar.dart ; echo "--- 上面应为空（中文只许在注释里）---"
grep -rn "Duration(seconds: 10)" lib/src/core/live lib/src/core/engine.dart ; echo "--- 上面应为空：边缘阈值必须来自 VmLiveConfig ---"
grep -rn "timeshift\|behind\|window" lib/src/core/engine.dart | grep -v "resolveWindow\|behindOf\|atLiveEdge\|///\|//" ; echo "--- 上面若出现算术表达式，说明时移算术漏在了 engine 里，应搬进 live/timeshift.dart ---"
```

- [ ] **Step 4: 跑全量**

Run: `flutter test && flutter analyze`
Expected: 全绿，analyze 0 issues

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "test(videoman): audit the live timeshift openness contract"
```

---

## Task 10（阶段 D）: iOS podspec 与包元数据收口

`ios/videoman.podspec` 至今还是 Flutter 模板占位内容：`s.version = '0.0.1'`、
`s.summary = 'A new Flutter plugin project.'`、`s.homepage = 'http://example.com'`、
`s.author = { 'Your Company' => 'email@example.com' }`。发布前必须对齐。

**Files:**
- Modify: `ios/videoman.podspec`
- Test: 无（靠 Task 13 的 `pub publish --dry-run` 兜底）

**Interfaces:**
- Consumes: `pubspec.yaml` 的 `version` / `description` / `homepage`
- Produces: 与 pubspec 一致的 podspec 元数据

- [ ] **Step 1: 核对 pubspec 现值**

Run: `grep -n "^version:\|^description:\|^homepage:\|^repository:" pubspec.yaml`
Expected: `version: 0.2.0`、`homepage: https://github.com/icodejoo/dart-labs/tree/main/videoman`

- [ ] **Step 2: 改写 podspec 元数据**

`ios/videoman.podspec` 前段替换为（保留后面的 `source_files` / `dependency` / `platform` /
`pod_target_xcconfig` / `swift_version` / 隐私清单注释块**原样不动**）：

```ruby
Pod::Spec.new do |s|
  s.name             = 'videoman'
  s.version          = '0.2.0'
  s.summary          = 'media_kit (libmpv/ffmpeg) video player plugin with a self-built gesture and controls layer.'
  s.description      = <<-DESC
A Flutter video player plugin built on media_kit (libmpv/ffmpeg): custom gesture
layer, VOD and live control bars, HLS quality switching with buffering-based ABR,
scrub-preview thumbnails, live timeshift, and Android picture-in-picture.
                       DESC
  s.homepage         = 'https://github.com/icodejoo/dart-labs/tree/main/videoman'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'jelon' => 'jelon@tbu.net' }
  s.source           = { :path => '.' }
```

> `s.version` 必须与 `pubspec.yaml` 的 `version` 保持一致；以后每次改版本都要同时改这里。
> 在 `doc/SPEC.md` 的「命令」小节旁边记一句这个约束（Task 12 一并写）。

- [ ] **Step 3: 校验**

Run: `flutter analyze`
Expected: 0 issues（podspec 不参与 analyze，此步只是确认没顺手改坏 Dart 代码）

若本机有 CocoaPods：`cd ios && pod lib lint videoman.podspec --allow-warnings`；
没有就跳过，交给 Task 14 的 iOS 真机/模拟器验证兜底。

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore(videoman): replace ios podspec template placeholders with real metadata"
```

---

## Task 11（阶段 D）: example 三个 demo（点播 / 直播 / 时移）

DESIGN §12 阶段 D：「example 三个 demo（VOD/直播/时移）」。现在 example 的三个入口是
「VOD mp4 / HLS 多清晰度 / 自定义皮肤」——缺直播与时移。

**Files:**
- Modify: `example/lib/main.dart`
- Test: 无（实跑验证在 Task 14）

**Interfaces:**
- Consumes: `VmSource(type: VmStreamType.live)`、`VmOptions(live: VmLiveConfig(...))`、
  `VmLiveSeekMode`、`VmTimeshiftBuilder`
- Produces: example 里五个入口（原三个 + 直播 + 时移），每个 demo 带自己的 `VmOptions`

- [ ] **Step 1: 让每个 demo 能带自己的 options**

`example/lib/main.dart` 的 `_Demo` 类加一个字段：

```dart
/// A demo source with a display name and the options it needs.
///
/// 带显示名与所需配置的演示源。
class _Demo {
  /// Label shown in the app bar.
  ///
  /// 应用栏上显示的名称。
  final String name;

  /// The media source this entry plays.
  ///
  /// 该入口播放的媒体源。
  final VmSource source;

  /// Player options this entry needs (live mode, timeshift builder, …).
  ///
  /// 该入口所需的播放器配置（直播模式、时移地址构造器等）。
  final VmOptions options;

  /// Creates a demo entry.
  ///
  /// 创建一个演示入口。
  const _Demo(this.name, this.source, {this.options = const VmOptions()});
}
```

- [ ] **Step 2: 加直播与时移两个入口**

`_demos` 列表末尾追加两项（前三项保持原样，只是现在都用默认 `options`）：

```dart
  _Demo(
    '直播 · DVR 可拖',
    VmSource(
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      type: VmStreamType.live,
      title: '直播（DVR 窗口内可回看）',
    ),
    options: const VmOptions(
      live: VmLiveConfig(seekMode: VmLiveSeekMode.dvr),
    ),
  ),
  _Demo(
    '直播 · 时移换源',
    VmSource(
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      type: VmStreamType.live,
      title: '直播（时移：拖动即换源）',
    ),
    options: VmOptions(
      live: VmLiveConfig(
        seekMode: VmLiveSeekMode.timeshift,
        dvrWindow: const Duration(minutes: 10),
        // Demo-only: this public test stream has no timeshift endpoint, so the
        // builder just appends a query the server ignores. It exists to show
        // *where* a real deployment plugs its own URL scheme in.
        //
        // 仅用于演示：这个公开测试流没有时移接口，构造器只是拼一个服务端会忽略
        // 的查询参数。它的意义是展示真实部署应当在**哪里**接入自己的地址方案。
        urlBuilder: (uri, behind, wallClock) =>
            '$uri?begin=${wallClock.subtract(behind).millisecondsSinceEpoch}',
      ),
    ),
  ),
```

> 时移 demo 的 `urlBuilder` **不会**真的换出可播的流——这是预期行为，Task 14 的核对项写明
> 「时移入口只验证 UI 与事件流，不验证画面」。

- [ ] **Step 3: 切换 demo 时重建 engine**

`options` 是构造期参数，切 demo 必须重建 engine。example 已经在用
`createVmEngine()`（`_engine = createVmEngine();`，装好了真实的 brightness/PiP/orientation
三个端口），本步骤只是把这个既有调用改为接收每个 demo 自己的 `options`，不需要另写一个
重复装配端口的 `_createEngine` 辅助函数。`_PlayerPageState` 改为：

```dart
  @override
  void initState() {
    super.initState();
    _engine = createVmEngine(options: _demos[_index].options);
    _engine.open(_demos[_index].source);
  }

  /// Switches to demo source [i], rebuilding the engine because options are
  /// construction-time.
  ///
  /// 切换到第 [i] 个演示源；因为配置是构造期参数，需要重建 engine。
  ///
  /// - [i]: index into the demo list / 演示列表下标
  Future<void> _switch(int i) async {
    final old = _engine;
    setState(() {
      _index = i;
      _engine = createVmEngine(options: _demos[i].options);
    });
    await old.dispose();
    await _engine.open(_demos[i].source);
    await _engine.loadQualities();
    if (mounted) setState(() {});
  }
```

`late final VmEngine _engine;` 改为 `late VmEngine _engine;`（现在会被重新赋值）。

> 若阶段 B 已落地，`createVmEngine()` 还会多接好预览相关的端口（缩略图目录/抽帧器），
> 与这里的直播 `options` 互不冲突，不需要额外处理。

- [ ] **Step 4: 校验**

Run: `flutter analyze`
Expected: 0 issues

- [ ] **Step 5: 桌面实跑冒烟**

Run: `cd example && flutter run -d windows`

核对：五个入口都能切换、切换不崩、直播入口底栏出现进度条与 `LIVE` 角标、
拖动直播进度条后角标变灰显示`时移`并出现 `-MM:SS`、点回直播按钮角标变回红色。

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(videoman): add live and timeshift demos to the example app"
```

---

## Task 12（阶段 D）: README / CHANGELOG / SPEC / CLAUDE.md

**Files:**
- Modify: `README.md`, `CHANGELOG.md`, `doc/SPEC.md`, `CLAUDE.md`, `doc/DESIGN-0.2.0.md`
- Test: 无

**Interfaces:**
- Consumes: Task 1–11 全部产物
- Produces: 与代码一致的文档

- [ ] **Step 1: CHANGELOG**

`CHANGELOG.md` 的 `## 0.2.0` 段追加「直播时移」小节：

- 新增 `VmLiveSeekMode.dvr` / `.timeshift` 两种可拖直播模式；
- 新增 `VmLiveConfig.urlBuilder` / `backToLive` / `autoBackToLiveOnStall` / `windowResolver`；
- 新增 `lib/src/core/live/timeshift.dart` 纯函数 `resolveWindow` / `behindOf` / `atLiveEdge`；
- `VmState.timeshiftBehind` 现在真正被写入，并伴随 `VmTimeshiftChanged` / `VmLiveEdgeReached` 事件；
- `VmApi.backToLiveEdge()` 由占位（`reload()`）变为按策略执行；
- 新增 `VmApi.pipSupported` / `VmState.pipSupported`，PiP 按钮在不支持的平台自动隐藏；
- **破坏性变更表**（0.2.0 内部，相对阶段 A/B 中间态）：

| 旧 | 新 | 说明 |
|---|---|---|
| `BackToEdgeComponent`（name `backToEdge`） | `BackToLiveComponent`（name `backToLive`） | patch 路径 `bottomBar/backToEdge` → `bottomBar/backToLive`；行为由 `reload()` 改为 `backToLiveEdge()` |
| `VmStrings.backToEdge` | `VmStrings.backToLive` | 前者删除 |
| `LiveBarComponent()` | `LiveBarComponent({bool seekable = false})` | 新增可选参数，旧写法仍可编译 |

- [ ] **Step 2: README**

新增「直播时移」一节：

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

并说明三点：默认 `off`（保持 0.1.0 禁拖行为）；`timeshift` 模式没有 `urlBuilder` 就不生效；
`windowResolver` 用于服务端带外声明窗口的场景。

再补一节「平台端口」，说明 `VmEngine()` 裸构造默认走 noop 端口（供纯 Dart 单测使用），
应用代码应改用 `lib/src/platform_impl/wiring.dart` 的 `createVmEngine()`——它默认接好
`ScreenBrightnessPort()` / `ChannelPipPort()` / `SystemChromeOrientationPort()`，且与
阶段 B/C 谁先落地无关；若阶段 B 已落地，`createVmEngine()` 还会多接好预览相关的端口。

- [ ] **Step 3: SPEC**

`doc/SPEC.md`：
- 「架构分层」目录树补 `core/live/timeshift.dart`；
- 新增「直播时移」一节：三种模式的语义、窗口解析优先级（`windowResolver` > `dvrWindow` >
  `duration`）、`behind` 按整秒量化的取舍与理由、`backToLiveEdge` 为何绕过 `open()`；
- 「关键 API 与不变式」里把「`VmApi.seek()` 在直播时被引擎忽略」改成
  「直播下 `seek()` 受 `liveSeekable` 门控；`dvr` 走内核 seek，`timeshift` 走 `urlBuilder` 换源」；
- 「测试」一节补新增测试文件与新的总数；
- 记一句 podspec 版本必须与 pubspec 同步；
- 末节「剩余任务」按实际情况更新（阶段 C 完成；阶段 B 视其是否已落地）。

- [ ] **Step 4: CLAUDE.md 与 DESIGN 回写**

`CLAUDE.md` 的「当前状态」改为阶段 C 已完成。

`doc/DESIGN-0.2.0.md` §8 末尾追加一段「落地偏差」：`backToLive` 是**可空**字段（为空时按
`seekMode` 推导）；UI 树里 `backToEdge` 已更名 `backToLive`；`behind` 按整秒量化。
§6.2 表格「回直播方式」一行的「配置项」列补上「（可空，空则按 `seekMode` 推导）」。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "docs(videoman): document live timeshift and reconcile design doc with the implementation"
```

---

## Task 13（阶段 D）: 全量校验与发布预检

**Files:**
- Modify: `doc/SPEC.md`（贴实测输出）
- Test: 全量

- [ ] **Step 1: analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 全量测试并留档**

Run: `flutter test`
Expected: 全绿。**把最后一行原始输出**（形如 `00:0X +NNN: All tests passed!`）**原样抄进
`doc/SPEC.md` 的测试小节**，连同日期与机器。不许只写"通过"。

- [ ] **Step 3: 纯净性最终确认**

Run: `flutter test test/core/purity_test.dart`
并 `grep -n "_mediaKitExceptions" -A 3 test/core/purity_test.dart`
Expected: PASS，且集合内容仍恰好是 `{'kernel/mpv_kernel.dart'}`

- [ ] **Step 4: 依赖清单确认**

Run: `grep -n -A 12 "^dependencies:" pubspec.yaml`
Expected: 阶段 C **没有**新增任何依赖。若阶段 B 已落地，只应多 `path_provider` 与
`connectivity_plus`；其余与阶段 A 相同。

- [ ] **Step 5: 发布预检**

Run: `flutter pub publish --dry-run`
Expected: **0 warnings**。常见问题与处理：
- `example/lib/spikes/` 或阶段 B 的一次性 spike 文件仍在 → 删掉或加进 `.pubignore`；
- podspec 版本与 pubspec 不一致 → 回 Task 10；
- `description` 过短/过长 → 调 `pubspec.yaml`；
- 缺 `example/README.md` 之类的可选建议 → 按提示补。

把 dry-run 的完整输出摘要也记进 `doc/SPEC.md`。

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore(videoman): record 0.2.0 release pre-flight results"
```

---

## Task 14（阶段 D）: 真机 / 模拟器验证一轮

**这是 0.2.0 的最后一道关，也是从 0.1.0 一路欠到现在的债。** `doc/SPEC.md` 末节明确记着：
阶段 A 的重构**从未在真机上验证过**，「手势手感、HLS 联网切档、Android PiP 实际行为、
iOS 整体播放，均承自 0.1.0 尚未在真机验证」。本任务把整个 0.2.0 面在真机上过一遍。

> **本任务需要人参与**（接设备、看画面、判断手感）。自动化 agent 跑到这里应当停下来，
> 把下面的核对清单交给人执行，并把结果填回 `doc/SPEC.md`。

**Files:**
- Modify: `doc/SPEC.md`（新增「真机验证结果」一节）
- Test: 无自动化测试

- [ ] **Step 1: Android 真机 / 模拟器**

Run: `cd example && flutter run -d <android-device-id>`

逐项核对并记录**通过 / 失败 / 未测**：

1. 点播 mp4 能播、能暂停、进度条走。
2. **左半屏竖滑改音量**、**右半屏竖滑改亮度**（侧别与 media_kit 内置相反，这是刻意的，
   不要"修正"）。亮度必须真的改屏幕亮度——若无反应，说明 `ScreenBrightnessPort` 没接上
   （见 Task 8 Step 7）。
3. 横滑改进度、双击左右快退快进 10s、双指缩放。
4. 控制条 3 秒自动隐藏；点一下重新出现。
5. contain / cover / fill 三态循环，画面表现正确。
6. 锁定后手势与按钮全部失效；解锁恢复。
7. 全屏按视频宽高比定向（横视频转横屏），退出全屏恢复。
8. HLS 多清晰度入口：清晰度菜单能列出档位、切换后画面继续播且位置不跳。
9. **PiP 按钮出现**（Android 支持），点击进入系统画中画，返回后播放继续。
10. 直播 DVR 入口：底栏出进度条与红色 `LIVE`；拖动后角标变灰 `时移` 且出现 `-MM:SS`；
    点回直播按钮回到边缘、角标变红。
11. 时移入口：**只验证 UI 与事件**——拖动后地址确实变了（可加临时日志或看 `VmTimeshiftChanged`），
    画面加载失败是预期的（公开测试流没有时移接口）。
12. 若阶段 B 已落地：拖动进度条出现缩略图气泡；切到蜂窝网络后气泡只剩时间文字、不出图
    （默认 `wifiOnly` 生效）。

- [ ] **Step 2: iOS 真机 / 模拟器**

Run: `cd example && flutter run -d <ios-device-id>`

逐项核对：

1. 上面 Android 清单的 1–8、10、11 同样核对一遍。
2. **PiP 按钮应当不出现**——iOS 未实现 PiP（libmpv 纹理限制，`isPipSupported()` 返回 `false`），
   Task 8 的能力位应当把按钮藏掉。**若按钮出现了，说明能力位没生效，回 Task 8。**
3. 亮度手势在 iOS 上的实际行为（`screen_brightness` 在 iOS 上改的是系统亮度）。

若本机没有 macOS/Xcode，如实记「未测（无 iOS 构建环境）」，**不要**假装通过。

- [ ] **Step 3: 记录结果**

`doc/SPEC.md` 新增「真机验证结果（0.2.0）」一节，用表格逐项记录：
设备型号 / 系统版本 / 每一项的通过与否 / 发现的问题。

**不许只写"通过"**——每一项都要有明确结论，未测的写「未测」并说明原因。

- [ ] **Step 4: 发现的问题分流**

- 阻断发布的（崩溃、核心功能不可用）→ 立刻修，修完回 Task 13 重跑全量校验。
- 不阻断的（手感、样式细节）→ 记进 `doc/ROADMAP.md` 作为 0.2.1/0.3.0 的待办，
  在 SPEC 里注明「已知问题，不阻断 0.2.0」。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "docs(videoman): record 0.2.0 real-device verification results"
```

---

## 阶段 C / D 出口条件

1. `flutter analyze` 0 issues；`flutter test` 全绿，原始输出已抄进 `doc/SPEC.md`。
2. `test/core/openness_live_test.dart` 8 项全过（DESIGN §6.2 逐行落实）。
3. `test/core/live/timeshift_test.dart` 9 项全过；engine 里**没有**残留的时移算术。
4. `test/core/purity_test.dart` 的 media_kit 例外集合仍恰为 `{'kernel/mpv_kernel.dart'}`。
5. 阶段 C **未新增任何依赖**。
6. `ios/videoman.podspec` 的 `version` 与 `pubspec.yaml` 一致，无模板占位字段。
7. `flutter pub publish --dry-run` 0 warnings。
8. Task 14 的真机核对清单逐项有明确结论并已写入 `doc/SPEC.md`；无阻断发布的问题遗留。
