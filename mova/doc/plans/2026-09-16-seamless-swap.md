# mova 0.4.0：无缝引擎切换（MovaSwapEngine） — 实现计划

**Goal:** 把"广告播完回正片"的黑屏/loading 消除为逐帧无缝：在一个**稳定的渲染面**背后持有"当前生效引擎 + 预热中的影子引擎"，就绪后原子换指。默认**关闭**，`MovaOpts.swap.enabled` 开启；关闭时行为与今天逐字节相同。

**Architecture:** 新增 `lib/src/core/swap/`（纯 Dart）。核心类 `MovaSwapEngine implements MovaApi, MovaSwapCtl`——它**本身就是一个 `MovaApi`**，宿主把它交给 `MovaPlayer`，UI 只认这一份；内部用 `MovaEngineFact`（复用 `core/feed/engine_pool.dart` 已有的 typedef）创建/销毁真实 `MovaEngine`。它拥有**自己的** `MovaBus<MovaState>` 与广播 controller，在 swap 时把订阅从旧引擎重新接到新引擎上——**绝不能直接返回 `active.states`**，否则组件在 `initState` 里订阅的流会在换引擎后死掉（`player.dart` 的 `ValueKey(widget.api)` 只在 api 引用本身变化时才重挂载，而代理的引用是稳定的，正是我们要的）。

**为什么不改 `MovaEngine` 让它持有可变 kernel：** `MovaKernel.renderHandle` 是构造期绑死的 `late final`（`mpv_kernel.dart:152` → `_controller`），`MovaEngine` 的 8 条 `late final StreamSubscription` 也是构造期一次性接线。要让它中途换 kernel，等于重写 `engine.dart` 的整个接线段，且会把风险铺到 289 项既有测试上。改为在 `MovaApi` 层做代理，`engine.dart` **一行不动**，风险面收敛到新文件里。

**命名结论：** 笔记暂拟名 `MovaSeamlessSwap` 改为 **`MovaSwapEngine`**。理由：① 它是 `MovaApi` 的实现，与 `MovaEngine` 同族，`MovaEngineFact` 在本仓库里返回的就是 `MovaApi`，"engine = 一个 MovaApi"已是既有词汇；② `SeamlessSwap` 是动作短语，读不出"这是宿主要持有的那个对象"；③ "seamless" 概念保留在配置侧 `MovaOpts.swap`（`MovaSwapConfig`）与文档里。

**Tech Stack:** Dart 3.12.2 / Flutter ≥3.3、media_kit ^1.2.6、flutter_test。**本阶段不新增任何依赖。**

**Baseline:** 0.3.0，289 项测试全绿、`flutter analyze` 0 issues。

**范围排除：** `core/feed/engine_pool.dart` **保持现状不动**——feed 拖拽过程要求两页画面同时在渲染树上连续插值，是双画面并存需求，结构性不适用本计划的单渲染面离散替换模型（结论见 `doc/notes/2026-08-05-seamless-quality-switch-feasibility.md` 末节）；两者仅共享 `MovaEngineFact` 这一条底层原语，不为 feed 拆任何 Task。

## Global Constraints

- 包名 `mova`，公开类前缀 `Mova`；`src/` 内文件名不带前缀。
- **`lib/src/core/**` 禁止 `import 'package:flutter/...'`；`test/core/purity_test.dart` 的 `_mediaKitExceptions` 必须恒等于 `{'kernel/mpv_kernel.dart'}`，本阶段任何 Task 都不许改它。** `core/swap/**` 只依赖 `MovaApi` 抽象，天然满足。
- 注释规则（`CLAUDE.md`）：每个类/方法/getter/字段都要注释，**先英文一句、空行、后中文**；公开 API 用 `///`，带参数/返回/示例。本计划代码块里的注释按原样抄。
- 校验用 `flutter analyze`（0 issues），不用 `flutter build`。每个 Task 结束 `flutter test` 全绿再 commit，信息用 `type(mova): message`。
- **既有 289 项测试一项都不许删、不许改断言。** 只允许因新增可选参数/新增字段而做纯增量修改（Task 1/2 各一处）。
- **默认关闭是硬约束**：`MovaSwapConfig.enabled` 默认 `false`；关闭时 `MovaSwapEngine` 必须退化为纯直通代理，`MovaAdCtrl` 必须走今天的 `_api.open()` 路径。每个 Task 都要有一条"关闭时行为不变"的测试。
- 开放性契约：每个替用户做的决策必须齐**默认值 + 配置项 + 可注入策略**三样（Task 9 做成可执行对账测试）。

## 文件结构

**core/swap（新建，纯 Dart）**

| 文件 | 职责 | 任务 |
|---|---|---|
| `lib/src/core/swap/warm.dart` | `MovaWarmSignal` / `MovaWarmVerdict` / `MovaWarmPolicy` 抽象 + `MovaBufferWarm` | Task 3 |
| `lib/src/core/swap/trigger.dart` | `MovaWarmCue` / `MovaWarmTrigger` 抽象 + `MovaLeadWarm` / `MovaEagerWarm` | Task 4 |
| `lib/src/core/swap/ctl.dart` | `MovaSwapCtl` 窄接口 + `MovaSwapPhase` | Task 5 |
| `lib/src/core/swap/swap_engine.dart` | `MovaSwapEngine implements MovaApi, MovaSwapCtl` | Task 5/6 |
| `lib/src/core/options/swap_config.dart` | `MovaSwapConfig` | Task 1 |

**修改**

| 文件 | 改动 | 任务 |
|---|---|---|
| `lib/src/core/options/options.dart` | 加 `swap` 节 + `copyWith`/`==`/`hashCode` + export | Task 1 |
| `lib/src/core/state/state.dart` | 加 `int renderEpoch`（默认 0） | Task 2 |
| `lib/src/ui/player.dart` | `_RenderSurface` 的 selector 纳入 `renderEpoch` | Task 2 |
| `lib/src/core/events/events.dart` | 加 `MovaSwapChg` | Task 6 |
| `lib/src/core/ad/ad_controller.dart` | 可选 `swap` 参数 + 无缝回切路径 | Task 7 |
| `lib/src/core/engine.dart` | 仅在 `switchQuality()` 上方加"未来落点"注释 | Task 8 |
| `lib/mova.dart` | barrel 增补导出 | Task 1/3/4/5 |
| `test/support/fake_api.dart` | 加 `FakeSwapCtl`；`FakeMovaApi` 补 `renderEpoch` 推送辅助 | Task 2/7 |
| `example/lib/main.dart` | 广告 demo 加 seamless 开关 | Task 10 |
| `README.md` / `CHANGELOG.md` / `doc/SPEC.md` / `CLAUDE.md` | 文档 | Task 10 |

**测试**

`test/core/swap/{warm,trigger,swap_engine,swap_swap}_test.dart`、`test/core/openness_swap_test.dart`、`test/core/options_test.dart`（增补）、`test/core/state_test.dart`（增补）、`test/core/ad_controller_test.dart`（增补）、`test/ui/player_test.dart`（增补）。

**测试数量推进**（基线 289）：Task 1 → 295、2 → 301、3 → 313、4 → 322、5 → 336、6 → 352、7 → 362、8 → 366、9 → 372、10 → 374。

---

## Task 1: `MovaSwapConfig` 与 `MovaOpts.swap`

先把配置面钉死：默认关闭，且**每个决策都给出默认值 + 配置项 + 可注入策略**。

**Files:**
- Create: `lib/src/core/options/swap_config.dart`
- Modify: `lib/src/core/options/options.dart`, `lib/mova.dart`
- Test: `test/core/options_test.dart`（追加 6 项，不动既有项）

**Interfaces / Produces:**

```dart
/// Configuration for seamless engine swapping.
///
/// Off by default: a swap costs a second decode session for the overlap
/// window, and many low-end Android SoCs only support one or two. With
/// [enabled] false every consumer falls back to today's plain `open()`
/// rebuild, so this whole feature is a pure opt-in increment.
///
/// 无缝引擎切换的配置。
///
/// 默认关闭：一次切换会在重叠窗口内多占一路解码 session，而很多中低端
/// Android SoC 只支持 1–2 路。[enabled] 为 false 时所有调用方都回落到今天
/// 的 `open()` 重建路径，因此整个特性是纯粹的可选增量。
class MovaSwapConfig {
  /// Master switch; no shadow engine is ever created when `false`.
  ///
  /// 总开关；为 `false` 时永不创建影子引擎。
  final bool enabled;

  /// How long before a predictable end the shadow engine starts warming up.
  ///
  /// 在可预测的结束时刻前多久开始预热影子引擎。
  final Duration leadTime;

  /// Clips shorter than this never warm up — the overlap window would be
  /// most of their length, so the double cost is not worth the saved blank.
  ///
  /// 短于此值的片段一律不预热——重叠窗口会占掉它大半时长，双份开销换不回
  /// 那一下黑屏。
  final Duration minWarmDuration;

  /// Gives up warming after this long and falls back to a plain `open()`.
  ///
  /// 超过此时长仍未就绪则放弃预热，回落到普通 `open()`。
  final Duration readyTimeout;

  /// Whether the shadow engine is muted while warming, so only one audio
  /// decode path is live until the swap commits.
  ///
  /// 预热期间是否静音影子引擎，使切换落定前只有一路音频解码在跑。
  final bool muteWhileWarm;

  /// Decides *when* warming starts; `null` uses [MovaLeadWarm] seeded from
  /// [leadTime]/[minWarmDuration].
  ///
  /// 决定*何时*开始预热；为 `null` 时使用由 [leadTime]/[minWarmDuration]
  /// 构造的 [MovaLeadWarm]。
  final MovaWarmTrigger? trigger;

  /// Decides *whether the shadow is ready*; `null` uses [MovaBufferWarm]
  /// seeded from [readyTimeout].
  ///
  /// 决定*影子引擎是否已就绪*；为 `null` 时使用由 [readyTimeout] 构造的
  /// [MovaBufferWarm]。
  final MovaWarmPolicy? readyPolicy;

  /// Creates a swap configuration; disabled by default.
  ///
  /// 创建一份切换配置；默认关闭。
  ///
  /// - [enabled]: master switch / 总开关
  /// - [leadTime]: warm-up lead before a predictable end / 结束前的预热提前量
  /// - [minWarmDuration]: shortest clip worth warming for / 值得预热的最短片长
  /// - [readyTimeout]: give-up deadline / 放弃预热的期限
  /// - [muteWhileWarm]: mute the shadow while warming / 预热期间静音影子引擎
  /// - [trigger]: injectable warm-up trigger / 可注入的预热触发策略
  /// - [readyPolicy]: injectable readiness verdict / 可注入的就绪判据
  ///
  /// Example / 示例:
  /// ```dart
  /// const opts = MovaOpts(swap: MovaSwapConfig(enabled: true));
  /// ```
  const MovaSwapConfig({
    this.enabled = false,
    this.leadTime = const Duration(seconds: 2),
    this.minWarmDuration = const Duration(seconds: 5),
    this.readyTimeout = const Duration(seconds: 8),
    this.muteWhileWarm = true,
    this.trigger,
    this.readyPolicy,
  });

  /// The trigger actually in effect.
  ///
  /// 实际生效的预热触发策略。
  MovaWarmTrigger get effectiveTrigger =>
      trigger ?? MovaLeadWarm(lead: leadTime, minDuration: minWarmDuration);

  /// A fresh readiness policy instance; policies carry per-warm-up state, so
  /// each warm-up gets its own rather than sharing one across swaps.
  ///
  /// 新建一个就绪判据实例；判据带有每次预热的累积状态，因此每次预热各用一个，
  /// 不跨切换共享。
  MovaWarmPolicy newReadyPolicy() =>
      readyPolicy ?? MovaBufferWarm(timeout: readyTimeout);

  MovaSwapConfig copyWith({...});
}
```

`MovaOpts` 追加 `final MovaSwapConfig swap;`（默认 `const MovaSwapConfig()`）、构造参数、`copyWith`、`==`、`hashCode`；`options.dart` 顶部加 `export 'swap_config.dart';` 与 import。

**Steps:**
1. 先写失败测试：默认值全覆盖（`enabled` 为 false、`leadTime` 2s、`minWarmDuration` 5s、`readyTimeout` 8s、`muteWhileWarm` true、两个策略字段为 null）。
2. `effectiveTrigger` 在未注入时返回由 `leadTime`/`minWarmDuration` 播种的 `MovaLeadWarm`；注入后原样返回注入值。
3. `newReadyPolicy()` 每次返回**不同实例**（`expect(identical(a, b), isFalse)`）；注入时返回注入值。
4. `MovaSwapConfig.copyWith` 只替换一个字段。
5. `MovaOpts().swap` 等于 `const MovaSwapConfig()`；`MovaOpts.copyWith(swap: ...)` 不影响其他节。
6. 实现 → `flutter test test/core/options_test.dart && flutter analyze`。

> Task 1 依赖 Task 3/4 的类型。**执行顺序上先做 Task 3 与 Task 4，再回头做 Task 1**；本文按"配置面优先"的阅读顺序编号，执行时按 3 → 4 → 1 → 2 → 5 → 6 → …。

**验收标准：** 295 项全绿；`MovaOpts` 既有 11 节的测试一项未改；analyze 0 issues。

---

## Task 2: `MovaState.renderEpoch` 与渲染面重建触发

**问题：** `_RenderSurface`（`lib/src/ui/player.dart:157-182`）虽然每次 build 都重读 `api.renderHandle`，但它包在 `MovaSelect<({MovaFit fit, double zoom})>` 里——**只有 fit/zoom 变化才会重建**。换引擎后 handle 变了却没人触发重建，画面会停在旧纹理上。这是整个方案能不能成立的关键接缝，必须先解决。

**方案：** `MovaState` 加一个 `int renderEpoch`（默认 0），`_RenderSurface` 的 selector 扩成 `(fit, zoom, epoch)`。`MovaEngine` 永远不写它（恒为 0，既有行为零变化）；`MovaSwapEngine` 每次 commit 后递增一次。

**Files:**
- Modify: `lib/src/core/state/state.dart`, `lib/src/ui/player.dart`, `test/support/fake_api.dart`
- Test: `test/core/state_test.dart`（追加 3 项）、`test/ui/player_test.dart`（追加 3 项）

**Produces:**

```dart
  /// Monotonic counter bumped whenever the render handle behind this state
  /// changes identity. Always 0 for a plain [MovaEngine]; only
  /// [MovaSwapEngine] advances it, and only to force the render surface to
  /// re-read [MovaApi.renderHandle] — the surface selector watches fit/zoom
  /// and would otherwise never rebuild on a swap.
  ///
  /// 单调递增计数器，在该状态背后的渲染句柄身份变化时加一。对普通
  /// [MovaEngine] 恒为 0；只有 [MovaSwapEngine] 会推进它，其唯一用途是强制
  /// 渲染面重新读取 [MovaApi.renderHandle]——渲染面的 selector 观察的是
  /// fit/zoom，否则切换时永远不会重建。
  final int renderEpoch;
```

`copyWith` 追加 `int? renderEpoch`，`==`/`hashCode` 纳入。

`player.dart` 的 selector 改为：

```dart
      child: MovaSelect<({MovaFit fit, double zoom, int epoch})>(
        selector: (s) => (fit: s.fit, zoom: s.zoom, epoch: s.renderEpoch),
```

**测试要求：**
- `state_test.dart`：默认 `renderEpoch == 0`；`copyWith(renderEpoch: 1)` 生效且不动其他字段；`renderEpoch` 不同的两个 state 不相等（保证 `MovaBus` 的去重不会吃掉它）。
- `player_test.dart`（WidgetTester + `FakeMovaApi`）：① 只改 `renderHandle` 而不推 state，渲染面**不**重建（记录当前行为）；② 改 `renderHandle` 并推 `renderEpoch+1` 的 state，渲染面重建且读到新 handle（用一个计数 builder 或自定义 `surface` 断言）；③ `MovaEngine` 路径下 `renderEpoch` 恒为 0（`engine_test.dart` 也可加一条）。

**验收标准：** 301 项全绿；既有 `player_test.dart`/`skin_test.dart` 断言一条未改。

---

## Task 3: 预热就绪判据 `core/swap/warm.dart`（纯逻辑）

这是本计划里**唯一全新的判定逻辑**，与 `MovaBufferAbr`（`options/abr_config.dart:46`）同形但目的相反——后者数缓冲**上升沿**判"该降档"，前者数**连续平稳 tick** 判"已经够顺，可以切"。纯 Dart、零 I/O、脱离 Flutter 与真实内核可单测。

**Files:**
- Create: `lib/src/core/swap/warm.dart`
- Modify: `lib/mova.dart`
- Test: `test/core/swap/warm_test.dart`（12 项）

**Produces:**

```dart
/// One observation of a warming shadow engine, fed to a [MovaWarmPolicy].
///
/// A plain value object so the readiness rule can be exercised without any
/// engine, kernel or Flutter binding.
///
/// 对预热中影子引擎的一次观测，喂给 [MovaWarmPolicy]。
///
/// 纯值对象，使就绪规则无需任何引擎、内核或 Flutter 绑定即可被测试。
class MovaWarmSignal {
  /// The shadow engine's current playhead.
  ///
  /// 影子引擎的当前播放位置。
  final Duration position;

  /// How far the shadow engine has buffered ahead.
  ///
  /// 影子引擎已缓冲到的位置。
  final Duration buffer;

  /// The position the swap should land on.
  ///
  /// 切换应当落在的位置。
  final Duration target;

  /// Whether the shadow engine is currently stalled.
  ///
  /// 影子引擎当前是否正在缓冲。
  final bool buffering;

  /// How long this warm-up has been running.
  ///
  /// 本次预热已进行的时长。
  final Duration elapsed;

  /// Creates an observation.
  ///
  /// 创建一次观测。
  ///
  /// - [position], [buffer], [target]: positions in media time / 媒体时间轴上的位置
  /// - [buffering]: current stall flag / 当前是否卡顿
  /// - [elapsed]: time since warm-up started / 自预热开始的耗时
  const MovaWarmSignal({
    required this.position,
    required this.buffer,
    required this.target,
    required this.buffering,
    required this.elapsed,
  });
}

/// The verdict a [MovaWarmPolicy] returns for one [MovaWarmSignal].
///
/// [MovaWarmPolicy] 针对一次 [MovaWarmSignal] 给出的裁决。
enum MovaWarmVerdict {
  /// Not ready yet; keep warming.
  ///
  /// 尚未就绪，继续预热。
  waiting,

  /// Ready — the swap may commit now.
  ///
  /// 已就绪——现在可以提交切换。
  ready,

  /// Give up; the caller must tear the shadow down and fall back to a plain
  /// `open()` rather than stall the user waiting for a swap that isn't coming.
  ///
  /// 放弃；调用方须拆掉影子引擎并回落到普通 `open()`，而不是让用户干等一个
  /// 永远不会到来的切换。
  giveUp,
}

/// Decides when a warming shadow engine is ready to become the live one.
///
/// The exact counterpart of [MovaAbrPolicy]: that one watches for "too
/// rough, step down", this one watches for "smooth enough, swap now".
///
/// 判定预热中的影子引擎何时可以转正为生效引擎。
///
/// 与 [MovaAbrPolicy] 恰好互为镜像：后者盯"太卡了，降档"，本者盯"够顺了，
/// 现在切"。
abstract class MovaWarmPolicy {
  /// Feeds one observation and returns the verdict.
  ///
  /// 输入一次观测并返回裁决。
  ///
  /// - [signal]: the latest shadow-engine observation / 最新一次影子引擎观测
  ///
  /// Returns the verdict for this tick / 返回本 tick 的裁决。
  MovaWarmVerdict onSignal(MovaWarmSignal signal);

  /// Resets accumulated state so the instance can drive another warm-up.
  ///
  /// 重置累积状态，使该实例可驱动下一次预热。
  void reset();
}

/// Buffer-based readiness: ready once the shadow has reached the target
/// position, is not stalled, and holds [lookahead] of buffered data — for
/// [stableTicks] consecutive observations.
///
/// The consecutive-tick requirement is what keeps a single lucky tick from
/// committing a swap that immediately re-buffers on screen; the lookahead is
/// what makes the first frames after the swap play through instead of
/// stalling at the moment the user is watching.
///
/// 基于缓冲的就绪判据：影子引擎已到达目标位置、未在卡顿、且已缓冲
/// [lookahead] 的数据——并连续满足 [stableTicks] 次观测。
///
/// 要求连续多 tick，是为了避免某一次侥幸的观测把切换提交出去、切完立刻在
/// 用户眼前重新缓冲；要求提前量，是为了让切换后的头几帧能连贯播下去，而不是
/// 恰好卡在用户注视的那一刻。
class MovaBufferWarm implements MovaWarmPolicy {
  /// How much buffered-ahead data counts as enough.
  ///
  /// 多少提前缓冲量算够。
  final Duration lookahead;

  /// How close to [MovaWarmSignal.target] counts as arrived.
  ///
  /// 距 [MovaWarmSignal.target] 多近算已到达。
  final Duration tolerance;

  /// Consecutive satisfying observations required.
  ///
  /// 需要连续满足的观测次数。
  final int stableTicks;

  /// Deadline after which [MovaWarmVerdict.giveUp] is returned.
  ///
  /// 超过该期限即返回 [MovaWarmVerdict.giveUp]。
  final Duration timeout;

  /// Creates a buffer-based readiness policy.
  ///
  /// 创建一个基于缓冲的就绪判据。
  ///
  /// - [lookahead]: buffered-ahead requirement, default 1s / 提前缓冲量要求，默认 1 秒
  /// - [tolerance]: arrival tolerance, default 800ms / 到达容差，默认 800 毫秒
  /// - [stableTicks]: consecutive satisfying ticks, default 2 / 连续满足次数，默认 2
  /// - [timeout]: give-up deadline, default 8s / 放弃期限，默认 8 秒
  ///
  /// Example / 示例:
  /// ```dart
  /// final policy = MovaBufferWarm(lookahead: const Duration(seconds: 2));
  /// ```
  MovaBufferWarm({
    this.lookahead = const Duration(seconds: 1),
    this.tolerance = const Duration(milliseconds: 800),
    this.stableTicks = 2,
    this.timeout = const Duration(seconds: 8),
  });

  /// Consecutive satisfying observations seen so far; for tests and
  /// diagnostics.
  ///
  /// 至今连续满足的观测次数；供测试与诊断使用。
  int get stable => _stable;

  @override
  MovaWarmVerdict onSignal(MovaWarmSignal signal) { /* … */ }

  @override
  void reset() { /* … */ }
}
```

**单测要求（`test/core/swap/warm_test.dart`，脱离 Flutter/真实内核，只构造 `MovaWarmSignal`）：**
1. 单次满足条件仍返回 `waiting`（`stableTicks` 默认 2）。
2. 连续两次满足返回 `ready`。
3. 中途出现 `buffering: true` 会把连续计数清零。
4. `position` 未到 `target - tolerance` 一律 `waiting`。
5. `position` 恰好落在容差边界算已到达（边界含）。
6. `buffer - position < lookahead` 一律 `waiting`。
7. `elapsed >= timeout` 返回 `giveUp`，且 `giveUp` 优先于 `ready`。
8. 已返回 `ready` 后再喂信号仍返回 `ready`（幂等，避免调用方重复提交时抖动）。
9. `reset()` 后连续计数归零，实例可复用。
10. `stableTicks: 1` 时首次满足即 `ready`。
11. `target` 为零（从头起播）时逻辑同样成立。
12. `position` 跑过 `target` 很多（影子引擎已播过头）仍算已到达。

**验收标准：** 313 项全绿；`purity_test` 通过；`warm.dart` 不含任何 `import 'dart:async'` 以外的依赖（实际应零 import）。

---

## Task 4: 预热触发策略 `core/swap/trigger.dart`（纯逻辑）

"何时开始预热"是**场景相关**的：广告用"剩余时长倒推"，清晰度切换用"选中即触发"。抽成可插拔策略，两种内置实现。

**Files:**
- Create: `lib/src/core/swap/trigger.dart`
- Modify: `lib/mova.dart`
- Test: `test/core/swap/trigger_test.dart`（9 项）

**Produces:**

```dart
/// What the caller knows about the upcoming switch point.
///
/// 调用方对即将到来的切换点的已知信息。
class MovaWarmCue {
  /// Time left until the switch point, or null when it is not predictable
  /// (e.g. a user-initiated quality change happens "now").
  ///
  /// 距切换点剩余的时长；不可预测时为 null（例如用户发起的清晰度切换就是
  /// "现在"）。
  final Duration? remaining;

  /// Total length of the clip being played out, or null when unknown.
  ///
  /// 正在播出的片段总时长；未知时为 null。
  final Duration? total;

  /// Creates a cue.
  ///
  /// 创建一条切换线索。
  ///
  /// - [remaining]: time left until the switch / 距切换点剩余时长
  /// - [total]: total clip length / 片段总时长
  const MovaWarmCue({this.remaining, this.total});
}

/// Decides whether warming should start now for a given [MovaWarmCue].
///
/// 依据给定的 [MovaWarmCue] 判定此刻是否应开始预热。
abstract class MovaWarmTrigger {
  /// Returns whether to start warming now.
  ///
  /// 返回此刻是否应开始预热。
  ///
  /// - [cue]: what is known about the switch point / 关于切换点的已知信息
  ///
  /// Returns whether to warm now / 返回是否立即预热。
  bool shouldWarm(MovaWarmCue cue);
}

/// Warms up [lead] before a predictable switch point, and never at all for
/// clips shorter than [minDuration].
///
/// The ad case: an ad's length is known, so the two engines only overlap for
/// the last second or two instead of the whole break — same peak cost, far
/// smaller time-integral of that cost, and a far smaller chance of actually
/// hitting the SoC's concurrent hardware-decode session limit.
///
/// 在可预测的切换点前 [lead] 开始预热；片长短于 [minDuration] 则完全不预热。
///
/// 广告场景：广告时长基本已知，因此两个引擎只在最后一两秒重叠，而非整个广告
/// 全程——峰值开销不变，但开销的时间积分小得多，真撞上 SoC 硬解并发 session
/// 上限的概率也小得多。
class MovaLeadWarm implements MovaWarmTrigger { … }

/// Warms up immediately, for switch points that are not predictable.
///
/// The quality-switch case: the user tapped a variant, "now" is the cue.
///
/// 立即预热，用于不可预测的切换点。
///
/// 清晰度切换场景：用户点了某一档，线索就是"现在"。
class MovaEagerWarm implements MovaWarmTrigger { … }
```

**单测要求：**
- `MovaLeadWarm`：`remaining > lead` → false；`remaining == lead` → true（边界含）；`remaining < lead` → true；`remaining <= 0` → false（已经结束，来不及了）；`total < minDuration` → 恒 false（**短广告降级路径**）；`total == null` → 按 `remaining` 判定（不因未知时长而拒绝）；`remaining == null` → false。
- `MovaEagerWarm`：任何 cue 都返回 true，包括空 cue。
- 两者都不持有状态：同一实例连续调用互不影响。

**验收标准：** 322 项全绿。

---

## Task 5: `MovaSwapCtl` 与 `MovaSwapEngine` 代理骨架（关闭态直通）

先只做**代理转发**与**关闭态直通**，不碰预热逻辑——把最容易出错的流生命周期单独立一个 Task 验干净。

**Files:**
- Create: `lib/src/core/swap/ctl.dart`, `lib/src/core/swap/swap_engine.dart`
- Modify: `lib/mova.dart`
- Test: `test/core/swap/swap_engine_test.dart`（14 项）

**Produces:**

```dart
/// Which stage of a swap the engine is in.
///
/// 引擎当前处于切换的哪个阶段。
enum MovaSwapPhase {
  /// One engine live, no shadow.
  ///
  /// 单引擎生效，无影子引擎。
  idle,

  /// A shadow engine exists and is warming up.
  ///
  /// 影子引擎已存在，正在预热。
  warming,

  /// The shadow engine is ready; a commit will be instant.
  ///
  /// 影子引擎已就绪；此时提交切换是瞬时的。
  ready,
}

/// The swap capability surface consumers drive, kept separate from [MovaApi]
/// so callers like `MovaAdCtrl` depend on the swap verbs alone and can be
/// tested against a tiny fake.
///
/// 调用方驱动的切换能力面，与 [MovaApi] 分开，使 `MovaAdCtrl` 这类调用方
/// 只依赖切换动词，并能对着一个极小的假对象做测试。
abstract class MovaSwapCtl {
  /// Whether seamless swapping is configured on.
  ///
  /// 是否已配置开启无缝切换。
  bool get swapEnabled;

  /// The current swap phase.
  ///
  /// 当前切换阶段。
  MovaSwapPhase get swapPhase;

  /// Emits every swap phase transition.
  ///
  /// 每次切换阶段迁移时推送。
  Stream<MovaSwapPhase> get swapPhases;

  /// Asks the configured trigger whether to start warming [source] at [at],
  /// and starts a shadow engine if it says yes.
  ///
  /// Safe to call on every progress tick: it is a no-op when swapping is
  /// disabled, when the trigger declines, or when a shadow for the same
  /// source is already warming.
  ///
  /// 询问已配置的触发策略是否应开始在 [at] 预热 [source]，若是则启动影子引擎。
  ///
  /// 可安全地在每个进度 tick 上调用：切换被禁用、触发策略拒绝、或同一源的
  /// 影子引擎已在预热时，均为空操作。
  ///
  /// - [source]: the media to warm up / 要预热的媒体
  /// - [at]: the position the swap should land on / 切换应落在的位置
  /// - [cue]: what is known about the switch point / 关于切换点的已知信息
  ///
  /// Example / 示例:
  /// ```dart
  /// await swap.prepare(content, at: resumeAt,
  ///     cue: MovaWarmCue(remaining: adLeft, total: adLength));
  /// ```
  Future<void> prepare(MovaSource source, {Duration at, MovaWarmCue cue});

  /// Promotes a ready shadow engine to be the live one and disposes the old.
  ///
  /// 把已就绪的影子引擎转正为生效引擎，并释放旧引擎。
  ///
  /// - [waitForReady]: when true, waits out the readiness policy (bounded by
  ///   its own timeout) instead of refusing immediately /
  ///   为 true 时等待就绪判据出结果（受其自身超时约束），而不是立即拒绝
  ///
  /// Returns whether the swap happened; `false` means the caller must fall
  /// back to a plain `open()`.
  ///
  /// 返回切换是否发生；`false` 表示调用方须回落到普通 `open()`。
  Future<bool> commit({bool waitForReady = false});

  /// Tears down any shadow engine without swapping.
  ///
  /// 拆除影子引擎（若有），不执行切换。
  Future<void> abandon();

  /// Warms [source] and commits as soon as it is ready, falling back to a
  /// plain `open()` on the live engine when warming is declined or times out.
  ///
  /// The one-call form for unpredictable switch points (quality switching,
  /// playlist next-episode). [prepare] + [commit] is the two-phase form for
  /// predictable ones (ads).
  ///
  /// 预热 [source] 并在就绪后立即提交；预热被拒或超时时回落到在生效引擎上做
  /// 普通 `open()`。
  ///
  /// 这是面向不可预测切换点（清晰度切换、播放列表下一集）的一次性调用形式；
  /// 面向可预测切换点（广告）的两段式形式是 [prepare] + [commit]。
  ///
  /// - [source]: the media to switch to / 要切换到的媒体
  /// - [at]: the position to land on / 要落到的位置
  ///
  /// Returns whether the switch was seamless / 返回本次切换是否为无缝切换。
  Future<bool> swapTo(MovaSource source, {Duration at});
}

/// A [MovaApi] that owns a live engine plus, briefly, a warming shadow one,
/// and presents a single stable surface in front of both.
///
/// The UI holds *this* object, never the engines behind it: its streams,
/// state snapshot and render handle stay addressable across a swap, so
/// components that subscribe once in `initState` keep working and
/// `MovaPlayer`'s `ValueKey(api)` never remounts the tree mid-swap.
///
/// With [MovaSwapConfig.enabled] false this is a pure pass-through: no shadow
/// engine is ever created and every method forwards verbatim to the single
/// engine the factory produced.
///
/// 一个持有生效引擎、并在短暂窗口内同时持有预热中影子引擎的 [MovaApi]，
/// 在两者之前呈现唯一一份稳定的对外面。
///
/// UI 持有的是*本对象*，而非它背后的引擎：它的流、状态快照与渲染句柄在切换
/// 前后始终可寻址，因此在 `initState` 里订阅一次的组件继续有效，
/// `MovaPlayer` 的 `ValueKey(api)` 也不会在切换途中重挂整棵树。
///
/// [MovaSwapConfig.enabled] 为 false 时它是纯直通代理：永不创建影子引擎，
/// 每个方法都原样转发给工厂产出的那唯一一个引擎。
class MovaSwapEngine implements MovaApi, MovaSwapCtl {
  /// Creates a swap engine over [engineFactory].
  ///
  /// 基于 [engineFactory] 创建一个切换引擎。
  ///
  /// - [engineFactory]: creates each underlying engine; hosts pass
  ///   `createMovaEngine` / 创建每个底层引擎；宿主传 `createMovaEngine`
  ///
  /// Example / 示例:
  /// ```dart
  /// final api = MovaSwapEngine(engineFactory: createMovaEngine);
  /// runApp(MovaPlayer(api: api));
  /// ```
  MovaSwapEngine({required MovaEngineFact engineFactory});

  /// The engine currently driving the render surface.
  ///
  /// 当前驱动渲染面的引擎。
  MovaApi get active;
}
```

**本 Task 的实现要点（写进 Steps）：**
1. 构造时调一次 `engineFactory()` 得到 `active`；`_attach(active)` 建立所有转发订阅。
2. **自持 `MovaBus<MovaState>` + 三个 broadcast `StreamController`**（events/progress/uiStates），`states`/`progress`/`events`/`uiStates` 返回自己的流，**不返回 `active.states`**。`state`/`uiState` 返回 bus 的当前值（构造时用 `active.state` 播种）。
3. `renderHandle` → `active.renderHandle`；`options` → `active.options`；`preview`/`stt` → `active.preview`/`active.stt`（文档里写明：切换后指向新引擎的服务，旧引擎的预览缓存随旧引擎释放）。
4. 所有能力方法（`open`/`play`/`seek`/`setVolume`/…/`backToLiveEdge`/`showControls`/`setDragging`）原样转发到 `active`。
5. `dispose()` 级联释放 active 与 shadow（若有）并关闭自有 controller。
6. 关闭态：`prepare`/`commit`/`swapTo` 分别为空操作 / 返回 false / 在 `active` 上做 `open()`+`seek()` 并返回 false。

**单测要求（`test/core/swap/swap_engine_test.dart`，工厂返回 `FakeMovaApi`，不碰真实内核）：**
1. 构造只调用工厂一次。
2. `states` 转发底层引擎推的 state，且新订阅者能收到当前快照。
3. `progress`/`events`/`uiStates` 三条流均可转发。
4. 每个能力方法都转发到 `active`（用 `FakeMovaApi.calls` 逐一断言，至少覆盖 `open`/`play`/`pause`/`seek`/`setVolume`/`setRate`/`setFit`/`setFullscreen`/`switchQuality`/`reload`/`backToLiveEdge`）。
5. `renderHandle`/`options`/`state`/`preview`/`stt` 转发正确。
6. `dispose()` 释放底层引擎并关闭自有流（再订阅不抛）。
7. **关闭态**：`swapEnabled` 为 false；`prepare` 后 `swapPhase` 仍为 `idle` 且工厂仍只被调用一次；`commit()` 返回 false 且不 `open`；`swapTo()` 在 active 上产生 `open` + `seek` 并返回 false。
8. `swapPhases` 初始不推送、`swapPhase` 初始为 `idle`。

**验收标准：** 336 项全绿；`MovaSwapEngine` 对 `MovaApi` 的实现完整（analyze 0 issues 即证明）。

---

## Task 6: 预热、就绪、原子切换（开启态）

在 Task 5 的骨架上接上真正的双引擎编排。

**Files:**
- Modify: `lib/src/core/swap/swap_engine.dart`, `lib/src/core/events/events.dart`
- Test: `test/core/swap/swap_swap_test.dart`（16 项）

**Produces:** `class MovaSwapChg extends MovaEvent { final MovaSwapPhase phase; … }`

**实现要点：**
1. `prepare`：`enabled` 为 false → 返回；`config.effectiveTrigger.shouldWarm(cue)` 为 false → 返回（**这条就是短广告降级路径**）；已有同 uri 影子 → 返回；否则 `engineFactory()` 造影子，`muteWhileWarm` 时 `setVolume(0)`，`open(source, autoPlay: true)` + `seek(at)`，起一个 `Stopwatch`，订阅影子的 `states`/`progress` 构造 `MovaWarmSignal` 喂 `config.newReadyPolicy()`，phase → `warming` 并发 `MovaSwapChg`。
2. 判据回 `ready` → phase → `ready`；回 `giveUp` → `abandon()` 并回 `idle`（同时发事件），**不抛异常**。
3. `commit`：无影子 → false；phase 非 `ready` 且 `waitForReady` 为 false → false；`waitForReady` 为 true → 等一个由判据超时兜底的 `Completer`。
4. **原子切换顺序**（写死在文档里，真机调参时才允许动）：`active.pause()` → 影子 `setVolume(active.state.volume)` → 影子 `play()` → 把转发订阅从 active 重接到影子（`_detach` + `_attach`）→ `active` 与影子互换 → `renderEpoch + 1` 并 emit 新 state → 发 `MovaSwapChg(idle)` → `unawaited(old.dispose())`（**先换指再释放**，释放是慢的原生调用，不能挡在换指前面）。
5. `abandon`：取消影子订阅、`dispose()` 影子、判据 `reset()`、phase 回 `idle`。
6. `swapTo` = `prepare(cue: const MovaWarmCue())` 走 `MovaEagerWarm` 语义 + `commit(waitForReady: true)`；返回 false 时在 active 上 `open()`+`seek()` 兜底。
7. `dispose()` 期间的迟到回调必须全部空转（`_disposed` 守卫，照抄 `engine_pool.dart` 的 `_disposed` 模式）。

**单测要求（工厂按调用次数返回不同 `FakeMovaApi`）：**
1. 开启 + 触发策略放行 → 工厂被调用第二次，影子被 `open` 且 `lastAutoPlay == true`，随后 `seek` 到 `at`。
2. `muteWhileWarm` 为 true 时影子被 `setVolume(0)`；为 false 时不被调用。
3. 触发策略拒绝（短广告）→ 工厂仍只调用一次，phase 保持 `idle`。
4. 判据未就绪时 `commit()` 返回 false 且不换指。
5. 判据就绪后 `swapPhase == ready`，`swapPhases` 收到 `warming` 与 `ready` 两次。
6. `commit()` 成功后：`active` 变为影子实例；旧引擎收到 `pause` 与 `dispose`；新引擎收到 `play`。
7. `commit()` 成功后 `renderEpoch` 递增 1，且从 `states` 上能观察到这一次 emit。
8. `commit()` 后 `renderHandle` 指向新引擎的 handle。
9. `commit()` 后旧引擎推 state **不再**出现在代理的 `states` 上；新引擎推 state 出现（订阅确实重接了）。
10. **切换前就订阅了 `progress` 的订阅者，切换后仍能收到新引擎的 tick**（这是"UI 组件 initState 订阅一次"的回归护栏，必须有）。
11. 判据返回 `giveUp` → 影子被 `dispose`，phase 回 `idle`，`commit()` 返回 false。
12. `commit(waitForReady: true)` 在判据超时后返回 false 且已 `abandon`。
13. `swapTo` 在开启且就绪时返回 true，且 active 换了实例。
14. `swapTo` 在关闭时回落为 active 上的 `open`+`seek` 并返回 false。
15. 重复 `prepare` 同一 uri 不会造出第二个影子。
16. `dispose()` 在预热中调用会连影子一起释放，且之后的迟到就绪回调不抛。

**验收标准：** 352 项全绿；`MovaSwapChg` 已从 barrel 可见。

---

## Task 7: `MovaAdCtrl` 接入无缝回切

**Files:**
- Modify: `lib/src/core/ad/ad_controller.dart`, `test/support/fake_api.dart`（加 `FakeSwapCtl`）
- Test: `test/core/ad_controller_test.dart`（追加 10 项，既有项一条不改）

**改动点：**
1. 构造签名改为 `MovaAdCtrl(this._api, {MovaSwapCtl? swap}) : _swap = swap, …`——**位置参数不变**，既有 `MovaAdCtrl(api)` 调用点（`example/lib/main.dart:655`、两处测试）零改动。文档注明：`swap` 应当就是同时作为 `api` 传入的那个 `MovaSwapEngine`。
2. `_onProgress` 的 `_Phase.ad` 分支：记录 `_adPosition` 后，若 `_swap != null && _swap.swapEnabled` 且当前广告有已知时长（`_current.source` 的时长从 `_api.state.duration` 取），调
   `unawaited(_swap.prepare(_content!, at: _contentResumeAt, cue: MovaWarmCue(remaining: adDuration - _adPosition, total: adDuration)))`。
   触发策略自己决定放不放行，控制器不做算术——`MovaLeadWarm` 就是那条算术。
3. `_playContent({at})`：开头改为
   ```dart
   if (_swap != null && await _swap.commit()) { /* 已无缝切到正片，跳过 open/seek */ }
   else { await _api.open(c); if (at > Duration.zero) await _api.seek(at); }
   ```
   其余（phase/`_changes`/STT 恢复）不变。
4. `_playAd()` 开头 `unawaited(_swap?.abandon())`——切去广告时丢掉任何为正片预热的影子（例如一个 pod 里连播多条广告）。
5. `dispose()` 追加 `await _swap?.abandon()`。

**单测要求（复用 `fake_api.dart` 的 `FakeMovaApi` + 新增 `FakeSwapCtl`，脱离 Flutter 与真实内核）：**
1. **不传 `swap` 时行为逐字不变**：前贴片→正片仍是 `open`；中插→正片仍是 `open` + `seek`（这条直接复用既有断言的形状，作为回归护栏）。
2. `swapEnabled` 为 false 时：`prepare` 从不被调用，`_playContent` 仍走 `open`。
3. 开启时，广告播放期间的每个 progress tick 都调 `prepare`，且 `cue.remaining` 随 `adPosition` 递减、`cue.total` 等于广告时长。
4. `prepare` 的 `at` 等于中插保存的 `_contentResumeAt`；前贴片场景等于 `Duration.zero`。
5. `commit()` 返回 true 时，`_api` 上**不出现** `open`、不出现 `seek`。
6. `commit()` 返回 false 时回落：`_api` 上出现 `open`（中插场景还要出现 `seek`）。
7. 切回正片后 `isShowingAd` 为 false、`changes` 发出一次（阶段簿记不因无缝路径而漏）。
8. STT 恢复逻辑在无缝路径上同样生效（`_sttWasRunning` 为 true 时 `stt.start` 被调用）。
9. `_playAd` 时 `abandon()` 被调用一次（广告 pod 连播场景）。
10. `dispose()` 调用 `abandon()`。

**验收标准：** 362 项全绿；`ad_controller_test.dart` 与 `ad_overlay_test.dart` 既有断言一条未改。

---

## Task 8: 清晰度切换的接口形状兼容（只定型，不做深实现）

**本 Task 不改 `switchQuality()` 的实现。** 目的只有一个：证明 `MovaSwapCtl` 的形状**现在**就能表达清晰度热切换，避免以后为它返工重构模块接口。

`MovaEngine.switchQuality()`（`lib/src/core/engine.dart:803-813`）当前语义是：取 `q.uri`（auto 取 `_source.uri`）→ `_kernel.open(playUri, play: wasPlaying)` → 非直播则 `seek(pos)` → 写 `currentQuality` + 发 `MovaQualChg`。这正是 `swapTo(MovaSource(playUri), at: pos)` 的语义，**只差"切完要把 `currentQuality` 写回新引擎的 state"**这一件事。

**Files:**
- Modify: `lib/src/core/engine.dart`（**只加注释**，标出未来落点与那一件差事）
- Test: `test/core/swap/swap_engine_test.dart`（追加 4 项契约测试）

**契约测试要求：**
1. `swapTo(MovaSource(variantUri), at: pos)` 在开启且就绪时确实换指，且新引擎被 `open` 的是 `variantUri`、被 `seek` 到 `pos`。
2. `swapTo` 用的是**即时触发**语义：`cue` 为空（`remaining == null`）时默认 `MovaLeadWarm` 会拒绝，因此 `swapTo` 必须显式走 `MovaEagerWarm`——断言"空 cue 的 `swapTo` 仍然创建了影子引擎"。
3. 直播源（`MovaStreamType.live`）下 `swapTo` 不下发 `seek`（与 `switchQuality` 的既有直播分支一致）。
4. `swapTo` 返回 false 时的兜底路径与今天的 `switchQuality` 完全等价（active 上 `open` + `seek`）。

`engine.dart` 里加的注释（放在 `switchQuality` 上方）：

```dart
  /// Seamless variant switching is *not* wired here on purpose: swapping
  /// engines mid-stream is [MovaSwapEngine]'s job, and this method's
  /// semantics already map onto `swapTo(MovaSource(uri), at: position)`
  /// one-to-one. The only piece still missing when that day comes is
  /// carrying [MovaState.currentQuality] across the swap — the shadow engine
  /// starts with an empty quality list, so the promoted engine must be
  /// re-seeded with it. See doc/plans/2026-09-16-seamless-swap.md Task 8.
  ///
  /// 此处刻意*不*接无缝换档：流中途换引擎是 [MovaSwapEngine] 的职责，且本方法
  /// 的语义已与 `swapTo(MovaSource(uri), at: position)` 一一对应。真要做那天
  /// 唯一还缺的一块，是把 [MovaState.currentQuality] 带过切换——影子引擎起步时
  /// 清晰度列表为空，转正后必须重新播种。见
  /// doc/plans/2026-09-16-seamless-swap.md Task 8。
```

**验收标准：** 366 项全绿；`switchQuality()` 的**可执行代码一行未改**（`git diff` 只有注释）。

---

## Task 9: 开放性对账 `test/core/openness_swap_test.dart`

照 `openness_live_test.dart`/`openness_preview_test.dart` 的形式，把"每个替用户做的决策都齐默认值 + 配置项 + 可注入策略"做成可执行测试（6 项）：

| 决策 | 默认值 | 配置项 | 可注入策略 |
|---|---|---|---|
| 是否启用无缝切换 | `false` | `MovaSwapConfig.enabled` | —（开关本身） |
| 何时开始预热 | 提前 2s | `leadTime` | `trigger`（`MovaWarmTrigger`） |
| 多短的片段不预热 | 5s | `minWarmDuration` | 同上（策略自己决定） |
| 何时算预热就绪 | 缓冲 1s + 连续 2 tick | `readyTimeout` | `readyPolicy`（`MovaWarmPolicy`） |
| 等多久放弃 | 8s | `readyTimeout` | 同上 |
| 预热时是否静音 | `true` | `muteWhileWarm` | — |

每行一条测试：断言默认值、断言配置项能改、断言注入的策略确实被 `MovaSwapEngine` 采用（用一个记录调用的假策略断言它被调过）。

**验收标准：** 372 项全绿。

---

## Task 10: barrel、example demo 与文档

- `lib/mova.dart` 增补（按字母序）：
  ```dart
  export 'src/core/swap/ctl.dart';
  export 'src/core/swap/swap_engine.dart';
  export 'src/core/swap/trigger.dart';
  export 'src/core/swap/warm.dart';
  ```
  （`options/swap_config.dart` 由既有的 `options.dart` 传递导出，不单列。）
- `example/lib/main.dart` 的广告 demo：加一个 `seamless` 开关，开时用
  `MovaSwapEngine(engineFactory: createMovaEngine)` 作为 api，并把它同时传给 `MovaAdCtrl(api, swap: api)`；关时沿用今天的 `createMovaEngine()`。**两条路径都要能跑**，这是真机验证要来回切的那个开关。
- `README.md` 加"无缝引擎切换（可选）"小节；`CHANGELOG.md` 记 0.4.0；`doc/SPEC.md` 加一节（含"feed 引擎池不适用本模型"的一句话结论与链接）；`CLAUDE.md` 的"当前状态"与"剩余任务"回写，并把真机验证列为未完成。
- 追加 2 项 barrel 可见性测试（`MovaSwapEngine`/`MovaSwapConfig` 能从 `package:mova/mova.dart` 直接引用）。

**验收标准：** 374 项全绿；`flutter analyze` 0 issues；`cd example && flutter run -d windows` 两条路径都能起。

---

## Task 11: 真机验证（Android 优先，iOS 次之）

**这是本计划唯一无法靠单测收敛的部分，预热阈值必须真机调。** 用 Task 10 的 example 开关来回对比。

### 真机验证 checklist

**2026-09-16 真机验证记录**（设备：华为 STG-AL00 / Android 12 / arm64-v8a，adb id
`7NQBB23606003715`；example `--release` 包直接装机跑）。**方法论限制先说明**：该机型
`/system/bin/` 下没有 `screenrecord`（`ls`/`which` 均确认不存在，非路径问题），因此无法
按计划录屏逐帧核验；改用 `adb exec-out screencap` 连续截图（单帧往返约 1.0–1.4s，达不到
逐帧精度），且 release 包下 `debugPrint`（`MovaSwapChg`/`MovaAdEvent` 等事件日志）在
`adb logcat` 里也看不到（已尝试，无输出）。以下条目凡是需要"逐帧"或"事件时序"精度的，
标注为**未能按原定精度验证**，只给出这套方法能看到的定性结果；没有编造任何数字。

**A. 广告黑屏是否消除**
- [x] 关闭 seamless（前贴片 flower.mp4，总长 00:05）：约 1.0–1.4s 间隔连续截图，从
  广告播放中一路截到切回正片，两张相邻截图之间未见黑屏/loading 帧，画面直接从广告末帧
  过渡到正片首帧。**未能按"逐帧"精度验证**（screenrecord 不可用，1s 级截图间隔可能漏掉
  更短的黑屏闪烁），只能说这套方法在自然操作节奏下没捕捉到黑屏。
- [x] 开启 seamless（同一条 flower.mp4 前贴片）：同样连续截图，广告→正片过渡同样未见
  黑屏/旧画面残留。**与关闭态相比，在这套 1s 级截图精度下未观察到肉眼可辨的差异**——
  这既可能是两条路径在此机型/此素材下都足够快，也可能是采样粒度不够细，无法区分。
  **结论：本轮未能证实"黑屏帧数从有到 0"的对比结论，需要真正的逐帧录屏工具复测。**
- [ ] 中插广告（mid-roll）回切续播点准确：未测量（没有做时间戳级别的位置比对）。
- [ ] 后贴片→空闲不应触发任何预热：未验证（demo 没有单独的后贴片位，且拿不到
  `swapPhase` 事件日志）。
- [ ] 广告 pod 连播（两条前贴片）：未验证——example 的 `_adBreaks` 只配了一个前贴片 +
  一个 10s 处中插，没有连续两条前贴片的 pod 场景，无法在不改代码的前提下测。
- [ ] 切换瞬间的音频（咔哒声/双声）：未验证——没有可用的音频采集手段，截图看不出声音。
- [ ] 切换瞬间的画面（跳变/尺寸抖动）：连续截图中未见明显跳变，但 1s 级间隔不足以捕捉
  单帧抖动，**未能按原定精度验证**。

**B. 内存 / 解码 session 是否符合预期**
- [x] 三阶段 `dumpsys meminfo` 采样（seamless 开启，用"此刻插入广告"插播一条 6 秒时长的
  friday.mp4 中插）：
  - 阶段①（广告播放早期 ~0s）：TOTAL PSS **125382 KB**，Native Heap PSS 24464 KB。
  - 阶段②（广告播放到 ~3s，处于预热窗口内）：TOTAL PSS **151105 KB**，Native Heap PSS
    34756 KB（较阶段① 涨约 26MB，与"影子引擎在预热"的预期方向一致）。
  - 阶段③（切换完成 3 秒后）：TOTAL PSS **159479 KB**，Native Heap PSS 44528 KB——
    **没有回落到接近阶段①，反而比阶段②还高**；再等 5 秒后又继续涨到 TOTAL PSS
    183829 KB。**这与文档预期的"阶段③必须回落到接近阶段①，否则是旧引擎泄漏"矛盾**，
    是本轮最值得注意的信号。但采样过程中出现了非预期的界面变化（截图显示应用在阶段③
    附近自动跳回了首页且转为横屏，不确定是否是手势/生命周期问题导致引擎重建，而非
    swap 泄漏本身），**采样被这次意外导航污染，不能直接断定是 `MovaSwapEngine` 的内存
    泄漏**。**建议**：用一次不受干扰的复测（固定停留在广告演示页、不触发任何导航）
    重新采三阶段数据，如果阶段③依然不回落，再定位是否为泄漏。
- [ ] 连续播 10 条带广告的内容看阶段③是否累积爬升：未测试（时间/条件不允许，且上面
  已经在单轮内观察到疑似不回落的现象，优先级上应先查清单轮问题）。
- [ ] 双活窗口时长（`warming`→`idle` 墙钟时间）：未测量——拿不到 `MovaSwapChg` 事件
  时间戳（release 下 logcat 无输出）。
- [ ] 中低端机硬解并发上限下的降级路径：未测试（本机型是否命中硬解 session 上限未知，
  且拿不到 error 流事件日志）。

**C. 短广告阈值降级路径是否生效**
- [ ] 3 秒短广告（低于 `minWarmDuration` 默认 5s）全程不建影子引擎：未测试——example
  内没有一条短于 5s 的现成素材，没有改代码新增测试素材（按硬约束不改 lib/test，也没有
  再新增 example 素材）。
- [~] 恰好 5 秒边界（`minWarmDuration` 默认 5s）：example 的前贴片 flower.mp4 总长正好
  00:05，天然覆盖了这个边界。开启 seamless 后该广告能正常播放并平滑切回正片（见 A 项
  截图），**行为上看是放行并尝试预热的**，但因为拿不到 `swapPhase`/工厂调用次数的日志，
  **无法确认是"含边界放行"还是恰好没触发预热也表现正常**——现象和判据都不够精确，只能
  算部分验证。
- [ ] 断网/弱网预热超时 `giveUp`：未测试（没有可控的弱网/断网模拟手段）。
- [ ] `duration` 恒为 0 的畸形源：未测试（没有构造这类源）。

**D. 回归（开关关闭态）**
- [x] 关闭 seamless 走一遍广告 demo：前贴片正常播放、可跳过、播完正常回正片，未见异常；
  与描述中"0.3.0 今天的行为"（有黑屏但截图粒度下未捕捉到）一致，**未见退化**。
- [ ] `renderEpoch` 恒为 0 的临时日志验证：未测试（不允许改代码加临时日志，且 release
  下 logcat 本身也拿不到输出）。

**E. 结论回写**
- [ ] 由于 A/B/C 大部分子项因工具限制（无 screenrecord、release 日志不可见、缺少弱网/
  短广告/连续 pod 等测试条件）未能达到原定精度，**暂不满足"回写默认参数"的前提**。
  已确认需要跟进的唯一实质性疑点是 B 项阶段③内存未回落，建议下一轮：① 用一台装了
  `screenrecord` 或用外接录屏的设备/工具复测 A 项；② 在不发生任何页面导航的前提下干净
  复测 B 项三阶段采样，确认阶段③是否真的不回落；③ 视 ②的结果决定是否需要回写
  `MovaBufferWarm`/`MovaSwapConfig` 的默认值。

**2026-09-23 补充记录**（同一设备 STG AL00，用专门构造的 `main_seamless_test.dart`
读取真实事件戳，解决了上一轮"拿不到 `MovaSwapChg`/事件时间戳"的限制）：
- [x] 切换机制真实生效的直接证据：skip 触发后 `MovaState.renderEpoch` 从 1 跳到 2，
  确认原子切指路径确实执行了（不是表面上"看起来没黑屏"的巧合）。
- [x] 切换耗时（基于真实事件戳，非墙钟估算）：从 skip 调用到 `renderEpoch` 落地 =
  **806ms**。
- 本轮**只测了这两项**，A 组黑屏/跳变的视觉判断、B 组内存三阶段采样（含上一轮未解决
  的阶段③不回落疑点）、C 组短广告降级、断网预热兜底均**未在本轮复测**，上一轮记录的
  开放问题（阶段③内存不回落）依然待查。

**2026-09-24 补充记录**（同一设备 STG AL00，新建独立文件
`example/lib/main_seamless_swap_verify.dart`，未提交）：
- [x] **B 组"中插回切续播点准确"——初测方向搞反，已定位真实根因并修复**：
  首次探针报"提前 2210ms"，实为探针自身 bug（一次插播里两次 `renderEpoch`
  跳变，Completer 在第一次——正片→广告——就完成，误把广告引擎的 position
  当成了正片续播位置）。**真实根因**：`MovaAdCtrl._warmContentBehindAd`
  用默认 `MovaWarmPlan`（`pauseWhenReady: false`），广告背后预热正片的影子
  引擎 `autoPlay: true` 按真实时间一路播，commit 时已经漂过整个广告剩余
  时长——真机实测续播目标 6006ms、实际落点 **8842ms（+2836ms 偏晚**，用户
  无声丢掉这段正片，不是偏早）。同一机制在 content→ad 方向也在漏：
  `_holdAtTarget`（`lib/src/core/swap/swap_engine.dart`）对目标为 0 的情形
  跳过回绕，导致广告缺头约 300ms。**已修复**：`_warmContentBehindAd` 显式
  传 `MovaWarmPlan(pauseWhenReady: true)`；`_holdAtTarget` 回绕守卫从
  `_warmAt > 0` 改成 `!_warmLive`（直播源仍不 seek）。`ad_controller_test.dart`
  /`swap_engine_test.dart` 各补 1 项回归，测试从 803 推进到 **809**，
  `flutter analyze` 0 issues。真机复测（新探针 `example/lib/
  main_resume_accuracy_verify.dart`，基于两次 `renderEpoch` 跳变，修正了
  初版探针的测量 bug）：修复前 6006ms→8842ms（+2836ms）；修复后两次采样
  5964ms→6006ms（+42ms）、5630ms→5672ms（+42ms）——42ms 是 progress 流
  200ms 节流下的一个采样格，已接近测量下限。**第二个疑点已排查，确认不是
  代码 bug**：`_startWarm` 里紧跟 `open()` 下发的 `seek(at)` 曾观察到 3 次
  运行 1 次快（20ms）、2 次慢（2.4s）。真机对照实验（裸 media_kit 三变体）
  证实：无寄存机制时过早 seek 会被 mpv 丢弃且**卡死播放器**；mova 的寄存
  机制 12/12 轮全部正确走到、全部真实落地，0 轮丢弃——那 2.4 秒就是 mpv
  报出 duration 本身的网络加载耗时（实测 3068–5327ms），与寄存机制无关。
  顺手做了一次加固：`MovaEngine.open()` 同步重置
  `duration`/`_lastPosition`/`_lastBuffer` 为 0，把"寄存还是直发"的判据从
  隐性竞态变成确定性的；顺带修掉复用引擎播放新源时上一条素材 position
  漏进新源首个 `MovaProg` 的真 bug。测试从 809 推进到 **811**，
  `flutter analyze` 0 issues，真机复测 6 轮无回归（3068–3782ms）。**排查中
  发现新的未修真 bug（另案）**：`MovaEngine.switchQuality` 清晰度切换/ABR
  自动降档路径无条件直接打内核、完全绕开寄存机制，是同一种会被 mpv 丢弃并
  卡死的模式，且从未真机验过。
- [x] **C 组短广告降级路径——PASS**：预热窗口压到 300ms、广告仅持有 250ms 即
  `skip()`，未见卡死/异常，`renderEpoch` 仍成功递增——即便预热窗口压缩到这个
  程度，无缝路径依然走成功，没有出现"预热来不及、界面卡住"。
- [x] **C 组断网/弱网预热超时兜底——PASS**：用真实 `adb shell svc wifi/data
  disable` 断网（测完已用 `svc wifi/data enable` 恢复），广告播放中断网，等过
  `readyTimeout=5s` 窗口后在断网状态下调用 `skip()`，未卡死，同步正常返回
  （走的是非无缝路径完成续播）。
- [x] **B 组三阶段内存采样——重新采样但数据仍不可信，需第三次单独重跑**：
  baseline=160.15MiB → 正片播放=130.90MiB(-29.25) → 双引擎并存=149.48MiB(-10.67)
  → 切回正片=150.31MiB(-9.84)，出现负增量。**原因已查清且与上一轮不同**：这次
  不是页面导航污染，而是四组测试在同一个进程内顺序执行，前面组（尤其短广告/断网
  两组）留下的引擎/GC 残留污染了本组自己的 baseline，不满足"三阶段对账"应有的
  干净起点。**结论：要拿到可信数字，B 组的内存采样必须单独拆成独立一次进程启动**
  （不与其他组共享进程），本轮未做。
- A 组黑屏/跳变的视觉判断（需要逐帧录屏/人眼工具，本轮仍无可用工具，明确跳过而
  非编造）**仍未测**。

---

**决策与结论摘要：** 模块定名 **`MovaSwapEngine`**（笔记暂拟的 `MovaSeamlessSwap` 改掉——它是一个 `MovaApi` 实现，与 `MovaEngine` 同族更好读；"seamless"概念保留在 `MovaOpts.swap`/`MovaSwapConfig`）。关键取舍：**不改 `MovaEngine`/`MovaKernel` 的 `late final renderHandle`**，改为在 `MovaApi` 层做稳定代理，`engine.dart` 可执行代码零改动；代理必须自持流而非转发底层流，否则组件 `initState` 的订阅会在换引擎后死掉。为触发渲染面重建新增 `MovaState.renderEpoch`（普通引擎恒 0）。预热拆成两个可插拔纯逻辑：触发策略（`MovaLeadWarm`/`MovaEagerWarm`）与就绪判据（`MovaBufferWarm`，`MovaBufferAbr` 的镜像）。清晰度切换只做接口形状契约测试 + 注释标落点，不做深实现；feed 引擎池明确排除。**共拆 11 个 Task**，测试从 289 推进到 374，外加真机 checklist 五组。
