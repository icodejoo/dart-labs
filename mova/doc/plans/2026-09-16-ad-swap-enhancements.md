# mova 0.5.0：广告编排增强（delay / duration / 就绪等待 / 失败兜底 / 延迟源解析） — 实现计划

**Goal:** 把 `MovaAdCtrl` 从"能按排期播广告"推进到"能按广告业务的真实时序播广告"：正片源可延迟解析、广告可在真正加载好之后才切入（不浪费曝光在黑屏上）、广告位时长与素材时长解耦、广告前有倒计时提示窗口、广告加载失败有明确兜底。**除"广告位时长 `duration`"外全部默认关闭/默认不改变行为**，0.4.0 的每一条既有路径逐字节保留。

**Architecture（一句话结论先行）：** **不新建任何预热机制。** `MovaWarmTrigger`/`MovaWarmPolicy`/`MovaSwapEngine` 三个抽象**直接复用、类型不改**，"content→ad 预热"只是把同一套 `prepare` → 就绪判据 → `commit` 用在另一个方向上；`MovaSwapCtl` 的 `prepare`/`commit`/`abandon`/`swapTo` 四个动词语义**已经够用，不新增任何方法**，只给 `prepare` 加**一个可选具名参数** `MovaWarmPlan plan`，把"本次预热用哪个触发策略、哪个就绪判据、就绪后是否停在起点"这三件**每次预热各不相同**的事从全局配置里解耦出来。详见下一节。

**Tech Stack:** Dart 3.12.2 / Flutter ≥3.3、media_kit ^1.2.6、flutter_test。**本阶段不新增任何依赖。**

**Baseline:** 0.4.0，**536 项测试全绿**（本次实测 `flutter test` 得到 `+536 All tests passed!`；CLAUDE.md 里写的 535 已过时，以 536 为准）、`flutter analyze` 0 issues（1 条与本批无关的既有 `feed_player.dart` 警告）。

---

## 0. 架构决策：三个抽象怎么被"content→ad"方向复用

### 0.1 结论表（先给结论，理由在后）

| 抽象 | content→ad 方向怎么用 | 是否需要改 |
|---|---|---|
| `MovaWarmTrigger` | 复用。ad→content 用 `MovaLeadWarm`（"广告剩 2 秒了，开始暖正片"）；content→ad 用 **`MovaEagerWarm`**（"delay 倒计时刚开始，立刻开始暖广告"——delay 窗口的全部意义就是拿来预热，没有再等的道理） | **零改动**。两个内置实现都已存在，直接组合 |
| `MovaWarmPolicy` | 复用 `MovaBufferWarm`，`target: Duration.zero`。判据退化为"未在缓冲 + 已缓冲 ≥ lookahead + 连续 2 tick"——这恰好就是"这条广告真的能播了"的定义 | **零改动**（`warm_test.dart` 第 11 项已覆盖 `target == 0`） |
| `MovaSwapEngine` | 复用。`prepare(adSource, at: Duration.zero, …)` → `commit(waitForReady: true)`。它不关心自己暖的是广告还是正片，只认 `MovaSource` | **三处小改 + 一个新参数**，见 0.2 |
| `MovaSwapCtl` | `prepare`/`commit`/`abandon`/`swapTo` 四个动词**语义已足够**，不新增方法 | 只给 `prepare` 加一个可选具名参数 `plan` |

### 0.2 为什么需要 `MovaWarmPlan`，而不是新方法

`_startWarm()` 今天从 `_config`（= `MovaOpts.swap`）取三件事：触发策略、就绪判据、是否静音。这在只有一个预热方向时成立；现在**同一个 `MovaSwapEngine` 实例在同一次播放里要跑两个方向的预热，两个方向的这三件事取值不同**：

| | ad→content（0.4.0 已有） | content→ad（本次新增） |
|---|---|---|
| 触发策略 | `MovaLeadWarm(lead: 2s)`——广告快完了才暖，压缩双活窗口 | `MovaEagerWarm()`——delay 一开始就暖，窗口越长越好 |
| 就绪判据超时 | `MovaSwapConfig.readyTimeout`（8s） | `MovaAdConfig.adReadyTimeout`（5s）——超过这个数广告位就该放弃了，让用户干等 8 秒看不到广告更糟 |
| 就绪后是否停住 | 否（今天是一路播着等 commit） | **是**——广告必须从第 0 帧开始给用户看，不能在影子引擎里悄悄播掉前两秒 |

把这三件事塞进 `MovaSwapConfig` 再加一套 `adTrigger`/`adReadyPolicy` 字段，等于让**通用的切换模块知道"广告"这个概念**——这正是 `doc/notes/2026-08-05` 那节要抽独立模块时明确反对的耦合方向。把它们收进一个**每次调用传入的值对象**，切换模块继续对业务一无所知：

```dart
/// Per-warm-up overrides for one [MovaSwapCtl.prepare] call.
///
/// The three knobs that legitimately differ *between two warm-ups on the same
/// engine*, and therefore cannot live in [MovaSwapConfig]: the same
/// [MovaSwapEngine] now warms content up behind an ad (lead-timed, keeps
/// rolling) and warms an ad up behind content (eager, must hold at frame
/// zero). Every field is nullable/defaulted, so
/// `prepare(src)` with no plan behaves exactly as it did in 0.4.0.
///
/// 单次 [MovaSwapCtl.prepare] 调用的预热参数覆盖。
///
/// 这三个旋钮会在*同一个引擎的两次预热之间*合理地取不同值，因此不能放进
/// [MovaSwapConfig]：同一个 [MovaSwapEngine] 现在既要在广告背后预热正片
/// （按提前量触发、一路播着），又要在正片背后预热广告（立即触发、必须停在
/// 第 0 帧）。每个字段都可空/有默认值，因此不带 plan 的 `prepare(src)` 与
/// 0.4.0 行为完全一致。
class MovaWarmPlan {
  /// Overrides [MovaSwapConfig.effectiveTrigger] for this warm-up; null keeps
  /// the configured one.
  ///
  /// 本次预热对 [MovaSwapConfig.effectiveTrigger] 的覆盖；null 表示沿用已配置的。
  final MovaWarmTrigger? trigger;

  /// Overrides [MovaSwapConfig.newReadyPolicy] for this warm-up; null keeps
  /// the configured one. The engine calls [MovaWarmPolicy.reset] on it before
  /// use, so one instance may safely drive successive warm-ups.
  ///
  /// 本次预热对 [MovaSwapConfig.newReadyPolicy] 的覆盖；null 表示沿用已配置的。
  /// 引擎在使用前会调用其 [MovaWarmPolicy.reset]，因此同一实例可安全驱动多次预热。
  final MovaWarmPolicy? policy;

  /// Whether the shadow pauses and rewinds to the warm-up target the moment it
  /// reports ready, so the swap starts playback from that exact frame.
  ///
  /// Required for ads: an ad warmed with `autoPlay: true` would otherwise burn
  /// its first seconds invisibly in the shadow engine, and the viewer would be
  /// shown an ad that is already two seconds in — an impression the advertiser
  /// paid for and nobody saw.
  ///
  /// 影子引擎一报告就绪，是否立即暂停并回到预热目标点，使切换后从那一帧开始播。
  ///
  /// 广告必须开：否则以 `autoPlay: true` 预热的广告会在影子引擎里把开头几秒
  /// 白白播掉，用户看到的是一条已经播了两秒的广告——广告主付了钱、没人看见。
  final bool pauseWhenReady;

  /// Creates a warm-up plan; all-defaults reproduces 0.4.0 behaviour.
  ///
  /// 创建一份预热计划；全默认即 0.4.0 行为。
  ///
  /// - [trigger]: per-call trigger override / 单次触发策略覆盖
  /// - [policy]: per-call readiness override / 单次就绪判据覆盖
  /// - [pauseWhenReady]: hold at the target frame once ready / 就绪后停在目标帧
  ///
  /// Example / 示例:
  /// ```dart
  /// await swap.prepare(ad.source, plan: const MovaWarmPlan(
  ///   trigger: MovaEagerWarm(), pauseWhenReady: true));
  /// ```
  const MovaWarmPlan({this.trigger, this.policy, this.pauseWhenReady = false});
}
```

### 0.3 顺带修掉的两处 0.4.0 潜伏缺陷

评估复用可行性时在 `swap_engine.dart` 里发现两条，本批一并修（都在 Task 1）：

1. **注入的 `readyPolicy` 从不被 `reset()`**：`MovaSwapConfig.newReadyPolicy()` 在注入时**每次返回同一个实例**（`readyPolicy ?? MovaBufferWarm(...)`），而 `_startWarm` 直接拿来用。第二次预热时该实例还带着上一次的 `_stable` 计数，`stableTicks` 语义失效——一次侥幸 tick 就可能提交切换。修法：`_startWarm` 里 `policy.reset()` 后再用。
2. **`at == Duration.zero` 仍然下发一次 `seek(0)`**：`_startWarm` 的 `if (!_warmLive) await shadow.seek(at)` 对前贴片→正片（`at` 恒为 0）与本次的广告预热（`at` 恒为 0）都会下发一次无意义的 seek。结合本仓库既有实测经验（"真机上临近边界的 seek 会可靠卡死播放器"），刚 `open()` 完就 `seek(0)` 是纯粹的风险敞口。修法：`if (!_warmLive && at > Duration.zero)`。

两条都**不改变任何既有断言**，但都要各补一条回归测试。

### 0.4 复用的代价必须说清楚

开启"等广告就绪"后，**一次中插的双引擎重叠窗口从 1 个变成 2 个**（正片背后暖广告、广告背后暖正片），且正片引擎会在广告开始时被 `dispose()`、广告结束时重建。峰值仍是 2 路解码 session（不变），但时间积分翻倍。这是 Task 12 真机 checklist 必须量的第一个数。

### 0.5 "等广告就绪"不是一个全局开关，而是一个按广告位类型取默认值的决策

**判据一句话：等待的价值，等于等待期间屏幕上那张画面的价值。**

| 广告位类型 | 等待期间屏幕上是什么 | 默认是否等待就绪 | 理由 |
|---|---|---|---|
| `pre` 前贴片 | **什么都没有**——用户刚进播放页，广告的加载态就是他预期看到的第一屏 | **否** | 不存在"正在看的内容被打断"这个损失；也没有更好的替代画面可显示，等待只是把第一屏推后，纯亏 |
| `mid` 中插 | **用户正在看的流畅正片** | **是** | 不等的话就是把一张好画面硬换成黑屏/loading，曝光机会被呈现成黑矩形而浪费掉；宁可稍晚一点点插播 |
| `post` 后贴片 | 已经结束的正片末帧 / 空白 | **否** | 与前贴片同理，没有正在进行的观看体验需要保护 |

这条**必须落成可覆写的默认值，不能写成 `if (kind == mid)` 的硬编码分支**：宿主完全可能想让 post-roll 也等待（比如后贴片接的是"下一集预告"性质的高价值素材），或者让 mid-roll 也不等（比如已经确认自己的广告 CDN 首帧恒在 200ms 内）。因此分三层解析，**逐层覆盖，越具体优先级越高**：

```
break.waitForReady            // 第一优先：单条广告位显式指定（bool?，默认 null）
  ?? config.waitForAdReady.waitFor(break)   // 第二优先：可注入策略；默认 MovaAdWaitByKind()
```

`MovaAdWaitByKind()` 的默认值就是上表的 `pre: false, mid: true, post: false`。

**同时，这条澄清把"等待"与"`delay` 倒计时"彻底解耦成两件独立的事**——两者绑死是错的：

| | `delay` 倒计时 | 等待广告就绪 |
|---|---|---|
| 是什么 | 宿主指定的、**用户可见**的"N 秒后播放广告"窗口 | **用户不可见**的后台预热窗口 |
| 时长由谁定 | `MovaAdBreak.delay`，固定 | 广告自己什么时候加载好，上界是 `MovaAdConfig.adReadyTimeout` |
| 可否单独存在 | 可以（`delay > 0` + 不等待 = 单纯的倒计时提示） | **可以**（`delay == 0` + 等待 = 正片不间断地继续播，广告一就绪就原子切入，**没有任何角标**） |

`delay == 0` 且等待开启，正是中插的**默认形态**：用户看不到任何倒计时，只会觉得"广告是无缝接上的"。两者同时开启时，退出 pending 阶段的条件是**两个条件都满足**：倒计时已走完 **且** 广告已就绪（后者受 `adReadyTimeout` 兜底）。

**这条不破坏"默认行为不变"的硬约束**，因为等待要真正发生需要同时满足三件事：宿主传了 `swap`、`MovaSwapConfig.enabled` 为 true、且解析结果为等待。前两件在 0.4.0 默认下都是关的，所以不接 `MovaSwapEngine` 的宿主一行行为都不会变。

---

## Global Constraints

- 包名 `mova`，公开类前缀 `Mova`；`src/` 内文件名不带前缀。
- **`lib/src/core/**` 禁止 `import 'package:flutter/...'`；`test/core/purity_test.dart` 的 `_mediaKitExceptions` 必须恒等于 `{'kernel/mpv_kernel.dart'}`，本阶段任何 Task 都不许改它。** 本批新增的 `core/ad/fail.dart`、`core/swap/plan.dart` 均为零依赖纯 Dart。
- 注释规则（`CLAUDE.md`）：每个类/方法/getter/字段都要注释，**先英文一句、空行、后中文**；公开 API 用 `///`，带参数/返回/示例。本计划代码块里的注释按原样抄。
- 校验用 `flutter analyze`（0 issues），不用 `flutter build`。每个 Task 结束 `flutter test` 全绿再 commit，信息用 `type(mova): message`。
- **既有 536 项测试一项都不许删、不许改断言。** 只允许因新增可选参数而做纯增量修改（Task 1 一处：`FakeSwapCtl.prepare` 签名）。
- **默认行为不变是硬约束**：`MovaAdBreak.delay` 默认 `Duration.zero`、`duration` 默认 `null`、`MovaWarmPlan()` 全默认等价 0.4.0。**"是否等广告就绪"默认按 kind 取值（`pre`/`post` 否、`mid` 是），但它只在宿主传了 `swap` 且 `MovaSwapConfig.enabled` 为 true 时才可能生效**——两者在 0.4.0 默认下都是关的，所以不接 `MovaSwapEngine` 的宿主行为逐字节不变。每个 Task 都要有一条"新特性未配置时行为逐字不变"的测试。
- **广告位相关的每一个替用户做的决策必须齐"默认值 + 配置项 + 可注入策略"三样**（Task 10 做成可执行对账测试）。唯一例外见 Task 3 对 `pauseWhenReady` 的说明（那是正确性不变量，不是口味选择，理由写在那里）。
- **不依赖媒体时间轴的硬约束**：`delay` 与 `duration` 的到期一律用 `Timer` 判定、到期后走与 `skip()` 完全相同的同步续播路径。**任何一处都不许用 `MovaDone`、`state.duration` 或 `seek` 到素材尾部来实现这两个语义**（实测结论：真机上临近真实 EOF 的 seek 会可靠卡死 mpv/media_kit；大文件时长在真机网络下可能长时间解析不出来）。

## 文件结构

**新建（纯 Dart）**

| 文件 | 职责 | 任务 |
|---|---|---|
| `lib/src/core/swap/plan.dart` | `MovaWarmPlan` | Task 1 |
| `lib/src/core/ad/fail.dart` | `MovaAdFailKind` / `MovaAdFail` / `MovaAdFailAction` / `MovaAdFailPolicy` 抽象 + `MovaAdRetrySkip` / `MovaAdAbandonPod` | Task 3 |

**修改**

| 文件 | 改动 | 任务 |
|---|---|---|
| `lib/src/core/swap/ctl.dart` | `prepare` 加可选 `MovaWarmPlan plan` | Task 1 |
| `lib/src/core/swap/swap_engine.dart` | 接 `plan`；`policy.reset()`；`at>0` 才 seek；影子 `MovaErrorEvent` → 放弃；`pauseWhenReady` 落地 | Task 1 |
| `lib/src/core/model/source.dart` | `typedef MovaSourceResolver` | Task 4 |
| `lib/src/core/model/ad.dart` | `MovaAdBreak.delay`/`duration`/`waitForReady` + 两条 assert；`MovaAdEventType.pending`/`.failed`；`MovaAdEvent.error` | Task 2 |
| `lib/src/core/options/ad_config.dart` | `MovaAdWaitPolicy`/`MovaAdWaitByKind` + 7 个新旋钮 + `effectiveWarmPlan`/`effectiveFailPolicy`/`waitsFor(break)` | Task 3 |
| `lib/src/core/options/strings.dart` | `adStartingIn` | Task 9 |
| `lib/src/core/ad/ad_controller.dart` | 主战场：`_Phase.pending`、`duration` 定时器、延迟源解析、就绪等待编排、失败策略 | Task 4–8 |
| `lib/src/ui/components/ad_overlay.dart` | delay 倒计时角标 | Task 9 |
| `lib/mova.dart` | barrel 增补导出 | Task 1/3/11 |
| `test/support/fake_api.dart` | `FakeSwapCtl.prepare` 加 `plan` + `lastPlan`；`FakeMovaApi` 加 `openThrows` | Task 1/8 |
| `example/lib/main.dart` | 广告 demo 加 delay/duration/等待就绪三个开关 | Task 11 |
| `README.md` / `CHANGELOG.md` / `doc/SPEC.md` / `CLAUDE.md` | 文档 | Task 11 |

**测试**

`test/core/swap/plan_test.dart`（新）、`test/core/ad/fail_test.dart`（新）、`test/core/openness_ad_test.dart`（新）、`test/core/swap/swap_engine_test.dart`（增补）、`test/core/model_test.dart`（增补）、`test/core/options_test.dart`（增补）、`test/core/ad_controller_test.dart`（大幅增补，既有 31 项一条不动）、`test/ui/ad_overlay_test.dart`（增补）。

**测试数量推进**（基线 **536**）：Task 1 → 550、2 → 560、3 → 572、4 → 580、5 → 589、6 → 605、7 → 621、8 → 635、9 → 642、10 → 651、11 → 654。

**需求覆盖对账**（七点一个不漏）：

| 需求 | 落在 |
|---|---|
| 1 正片源延迟解析 | Task 4 |
| 2 广告切入是否等就绪（两层语义 + **按 kind 取默认** + 兜底） | Task 1（`pauseWhenReady`）、Task 3（`MovaAdWaitByKind` 三层解析）、Task 7（编排与兜底） |
| 3a `duration` 定长广告位（不依赖素材时间轴） | Task 2（模型）、Task 5（定时器） |
| 3b `delay` 倒计时阶段（正片继续播） | Task 2（模型）、Task 6（状态机）、Task 9（UI） |
| 4 广告加载失败兜底 | Task 3（策略类型）、Task 8（接线） |
| 5 delay 窗口 = 广告预热窗口（同一套编排） | Task 7 |
| 6 pod 内 delay 只一次 / duration 各自计时 | Task 6（结构性保证 + 中插 pod 串联修正）、Task 5 |
| 7 `duration` < `skippableAfter` 构造期校验 | Task 2 |

---

## Task 1: `MovaWarmPlan` 与 `MovaSwapCtl.prepare(plan:)`

先把复用接缝钉死。**本 Task 不碰 `MovaAdCtrl` 一行**，把切换模块的改动单独验干净。

**Files:**
- Create: `lib/src/core/swap/plan.dart`
- Modify: `lib/src/core/swap/ctl.dart`, `lib/src/core/swap/swap_engine.dart`, `lib/mova.dart`, `test/support/fake_api.dart`
- Test: `test/core/swap/plan_test.dart`（新，4 项）、`test/core/swap/swap_engine_test.dart`（追加 10 项，既有项一条不改）

**Produces:** 0.2 节的 `MovaWarmPlan` 全文，外加：

```dart
  /// Asks the configured trigger whether to start warming [source] at [at],
  /// and starts a shadow engine if it says yes.
  ///
  /// [plan] overrides the trigger / readiness policy / hold-at-target
  /// behaviour for this one warm-up. It exists because a single engine now
  /// warms in two directions — content behind an ad, and an ad behind
  /// content — and those two want different answers. Omit it for 0.4.0
  /// behaviour.
  ///
  /// （中文同上，略——实现时按 0.2 节注释规范补全）
  ///
  /// - [plan]: per-warm-up overrides / 单次预热的参数覆盖
  Future<void> prepare(
    MovaSource source, {
    Duration at = Duration.zero,
    MovaWarmCue cue = const MovaWarmCue(),
    MovaWarmPlan plan = const MovaWarmPlan(),
  });
```

**Steps:**
1. 建 `plan.dart`，只有 `MovaWarmPlan` 一个类，零 import。
2. `ctl.dart` 的 `prepare` 加 `plan` 参数（有默认值 → 既有调用点零改动）。
3. `swap_engine.dart`：
   - `prepare` 改为 `_startWarm(source, at: at, cue: cue, plan: plan)`；`_startWarm` 的 `trigger` 形参由 `MovaWarmPlan` 取代（`swapTo` 改为传 `const MovaWarmPlan(trigger: MovaEagerWarm())`）。
   - 触发策略取 `plan.trigger ?? _config.effectiveTrigger`。
   - 判据取 `plan.policy ?? _config.newReadyPolicy()`，**取到后立刻 `..reset()`**（0.3 节缺陷①）。
   - `seek` 条件改为 `if (!_warmLive && at > Duration.zero)`（0.3 节缺陷②）。
   - 新增 `_shadowEventSub`：订阅影子的 `events`，见到 `MovaErrorEvent` 立刻走与 `MovaWarmVerdict.giveUp` **完全相同**的分支（`abandon()` + 唤醒 `_readyCompleter(false)`）。`abandon()`/`_commitNow()`/`dispose()` 三处都要取消它。
   - `pauseWhenReady`：在 `_evaluate` 判定 `ready` 的那一刻（仅第一次），若 `plan.pauseWhenReady` 为真，`await shadow.pause()` 后 `if (at > Duration.zero) await shadow.seek(at)`——回绕落在已缓冲区间内，是廉价的后向 seek，且**绝不靠近素材尾部**。`_commitNow` 里已有的 `shadow.play()` 负责起播，无需改动。
   - 把 `plan` 存进 `_warmPlan` 字段供 `_evaluate`/`_commitNow` 读取；`abandon()` 里清空。
4. `fake_api.dart` 的 `FakeSwapCtl.prepare` 同步加 `plan` 参数 + `MovaWarmPlan? lastPlan` 记录字段（**纯增量**，既有断言不受影响）。
5. `lib/mova.dart` 增 `export 'src/core/swap/plan.dart';`。

**单测要求：**

`plan_test.dart`（4 项）：
1. `const MovaWarmPlan()` 三字段为 `null`/`null`/`false`。
2. 三个字段分别可赋值并读回。
3. `MovaWarmPlan` 可 `const` 构造（编译期即证明，写一个 `const` 字面量断言）。
4. 注入 trigger + policy 同时给出时两者各自独立生效（构造断言，不涉引擎）。

`swap_engine_test.dart` 追加（10 项）：
5. 不传 `plan` 时，触发策略与判据仍取自 `MovaSwapConfig`（回归护栏）。
6. `plan.trigger` 注入后，`MovaSwapConfig.trigger` **不被调用**，注入的被调用。
7. `plan.policy` 注入后，`MovaSwapConfig.readyPolicy` 不被调用。
8. `plan.policy` 在被喂第一个信号**之前**收到过一次 `reset()`（缺陷①回归；用记录调用序的假判据断言 `['reset', 'onSignal']`）。
9. 连续两次 `prepare`（中间 `abandon`）复用同一注入判据实例时，第二次的连续计数从零起算（缺陷①的行为级断言）。
10. `at == Duration.zero` 时影子**不**收到 `seek`（缺陷②回归）；`at > 0` 时收到（既有行为不变）。
11. `pauseWhenReady: false`（默认）时影子在 ready 后**不**收到 `pause`（0.4.0 行为逐字保留）。
12. `pauseWhenReady: true` 时影子在首次 ready 后收到 `pause`，且 `at == 0` 时**不**追加 `seek`；`at > 0` 时追加 `seek(at)`。
13. `pauseWhenReady: true` 且判据连续多次报 `ready` 时，`pause` 只发生一次（幂等）。
14. 影子 `events` 上推 `MovaErrorEvent` → 影子被 `dispose`、`swapPhase` 回 `idle`、在途 `commit(waitForReady: true)` 解析为 `false`（不挂起、不抛）。

**验收标准：** 550 项全绿；`swap_engine_test.dart`/`openness_swap_test.dart` 既有断言一条未改；`flutter analyze` 0 issues；`purity_test` 通过。

---

## Task 2: `MovaAdBreak` 的 `delay`/`duration`/`waitForReady` 与构造期校验

纯模型层，无行为。先把数据形状与**需求 7 的校验**钉死，后面所有 Task 都依赖它。

**Files:**
- Modify: `lib/src/core/model/ad.dart`
- Test: `test/core/model_test.dart`（追加 10 项）

**Produces:**

```dart
  /// How long the content keeps playing after this break becomes due, before
  /// the ad actually takes over — the window a "your video resumes after this
  /// ad" countdown badge is shown in.
  ///
  /// Deliberately *not* a blank-screen wait: the content plays on for the whole
  /// countdown, which is both a better experience and (when
  /// [MovaAdConfig.waitForAdReady] is on) exactly the window the ad is warmed
  /// up in. Only meaningful for [MovaAdBreakKind.mid] — a pre-roll has no
  /// content to play during the countdown and a post-roll has none left.
  /// Within an ad pod only the *first* break's delay is honoured; see
  /// `MovaAdCtrl`.
  ///
  /// 该广告位到期后、广告真正接管画面之前，正片继续播放的时长——也就是
  /// "N 秒后播放广告"角标显示的那段窗口。
  ///
  /// 刻意*不是*黑屏等待：整个倒计时期间正片照常播放，这既是更好的体验，也
  /// （在 [MovaAdConfig.waitForAdReady] 开启时）正好就是预热广告的那个窗口。
  /// 仅对 [MovaAdBreakKind.mid] 有意义——前贴片倒计时期间没有正片可播，后贴片
  /// 则已经播完了。一个广告 pod 里只有*第一条*的 delay 生效，见 `MovaAdCtrl`。
  final Duration delay;

  /// How long this ad slot runs before the content resumes, regardless of the
  /// ad media's own length; null means "play the media to its end".
  ///
  /// Decoupled from the media on purpose. The slot that was bought is 15
  /// seconds; the creative handed over may be longer, shorter, or a generic
  /// loop. Enforcement is a plain [Timer] started at the ad's first rendered
  /// frame and never touches the media timeline — the engine is not asked for
  /// a duration (which can take a long time to resolve over a real mobile
  /// network on a large file) and is never seeked near its real EOF (which
  /// reliably wedges the player on device). Expiry takes the exact same
  /// synchronous resume path `skip()` takes, which is the one path already
  /// proven on hardware.
  ///
  /// 该广告位运行多久后续播正片，与广告素材自身长度无关；null 表示"把素材播到
  /// 结束"。
  ///
  /// 刻意与素材解耦。买的广告位是 15 秒，交付的素材可能更长、更短、或是一段
  /// 通用循环片。到期判定是一个从广告首帧起算的普通 [Timer]，完全不碰媒体
  /// 时间轴——不向引擎要时长（大文件在真机移动网络下可能很久解析不出来），
  /// 也绝不 seek 到素材真实 EOF 附近（真机上会可靠地把播放器卡死）。到期后
  /// 走的是与 `skip()` 完全相同的同步续播路径，那是唯一已在真机上验证过的路径。
  final Duration? duration;

  /// Whether the player waits for this ad to actually be ready before cutting
  /// to it, overriding [MovaAdConfig.waitForAdReady] for this one break; null
  /// defers to the config.
  ///
  /// The per-break escape hatch on top of the per-kind default. Set it when
  /// one particular creative deserves different treatment from the rest of its
  /// kind — a mid-roll from a CDN known to be slow that you would rather cut
  /// to immediately than delay, or a post-roll carrying a high-value
  /// next-episode teaser that is worth waiting for.
  ///
  /// Only has any effect when the host wired a `MovaSwapCtl` and
  /// [MovaSwapConfig.enabled] is true; with no swap engine there is nothing to
  /// warm up in and the field is ignored.
  ///
  /// 播放器是否等这条广告真的就绪后才切过去；为该条广告位覆盖
  /// [MovaAdConfig.waitForAdReady]，null 表示沿用配置。
  ///
  /// 这是架在"按 kind 取默认值"之上的单条逃生口。当某一条素材值得与同类其他
  /// 广告位区别对待时使用——比如一条来自已知较慢 CDN 的中插，你宁可立刻硬切
  /// 也不愿推迟；又比如一条承载高价值"下集预告"的后贴片，值得为它等一等。
  ///
  /// 仅在宿主接了 `MovaSwapCtl` 且 [MovaSwapConfig.enabled] 为 true 时才有
  /// 效果；没有切换引擎就没有可预热之处，该字段被忽略。
  final bool? waitForReady;
```

构造函数（加 `waitForReady` 参数，默认 `null`）追加两条 `assert`：

```dart
  const MovaAdBreak({
    required this.kind,
    required this.source,
    this.offset = Duration.zero,
    this.delay = Duration.zero,
    this.duration,
    this.waitForReady,
    this.skippableAfter,
    this.clickThroughUrl,
  })  : assert(
          duration == null || skippableAfter == null || duration > skippableAfter,
          'duration must outlast skippableAfter, otherwise the slot is force-'
          'resumed before the skip control ever appears and the ad is, in '
          'practice, unskippable. / duration 必须长于 skippableAfter，否则广告位'
          '会在跳过控件出现之前就被强制续播，这条广告实际上不可跳过。',
        ),
        assert(
          kind == MovaAdBreakKind.mid || delay == Duration.zero,
          'delay is only meaningful for mid-roll breaks: a pre-roll has no '
          'content to play during the countdown, a post-roll has none left. / '
          'delay 只对中插有意义：前贴片倒计时期间没有正片可播，后贴片已经播完了。',
        );
```

**取舍判断（需求 7：assert 还是注释警告？）— 结论是 `assert`，理由三条：**
1. `MovaAdBreak` 的构造器是 `const`，且实践中排期就是写在配置里的字面量。**`assert` 在 `const` 构造里是编译期求值的**——`const MovaAdBreak(duration: 5s, skippableAfter: 10s)` 会直接编译失败，这是最强、最早、零运行时成本的一道关，注释做不到。
2. `assert` 在 release 下被完全移除，**终端观众不会因为宿主的配置错误而崩溃**，风险面只在开发者机器上。
3. 这个错误的表现（"跳过按钮永远等不到就被切走"）在真机上**极难归因**——用户只会觉得"这个播放器的跳过按钮是坏的"。这正是值得大声失败的那一类配置错误。

> **注意：`lib/src/core/**` 目前一条 `assert` 都没有**（本次实测 `grep` 确认）。这是本仓库第一次引入该约定，因此要在 `CLAUDE.md`「约定」一节补一句："值对象的构造期不变量用 `assert`（const 构造器里是编译期校验、release 下零成本）；运行时的可恢复错误一律走策略对象 + 事件回调，不许 `throw`。" 由 Task 11 回写。

**单测要求（`model_test.dart` 追加 10 项）：**
1. `delay` 默认 `Duration.zero`、`duration` 默认 `null`、**`waitForReady` 默认 `null`**（默认值护栏）。
2. 三个字段都能正常赋值读回。
3. `duration > skippableAfter` 可正常构造。
4. `duration == skippableAfter` 抛 `AssertionError`（边界不含——相等同样跳不到）。
5. `duration < skippableAfter` 抛 `AssertionError`。
6. `duration` 为 null、`skippableAfter` 非 null 时不抛（不可跳过与定长互不牵连）。
7. `kind: pre` + `delay > 0` 抛 `AssertionError`；`kind: post` 同理。
8. `kind: mid` + `delay > 0` 不抛。
9. **`waitForReady` 对任何 `kind` 都可显式设为 `true`/`false`，不抛**——包括 `pre`/`post`（宿主有权让后贴片也等待，模型层不得越俎代庖地挡住）。
10. `waitForReady: true` 与 `delay: Duration.zero` 可共存（这正是中插的默认形态：不可见的预热等待，没有倒计时角标）。

**验收标准：** 560 项全绿；`ad_controller_test.dart` 一条未改（模型层加字段不影响既有用例）。

---

## Task 3: `MovaAdConfig` 旋钮面与 `MovaAdFailPolicy`

把本批所有"替用户做的决策"一次性钉在配置层，**每一条都齐默认值 + 配置项 + 可注入策略**。

**Files:**
- Create: `lib/src/core/ad/fail.dart`
- Modify: `lib/src/core/options/ad_config.dart`, `lib/mova.dart`
- Test: `test/core/ad/fail_test.dart`（新，6 项）、`test/core/options_test.dart`（追加 6 项）

**Produces（`fail.dart`）:**

```dart
/// Why an ad break failed to play.
///
/// 一个广告位播放失败的原因。
enum MovaAdFailKind {
  /// `open()` on the ad source threw.
  ///
  /// 对广告源的 `open()` 抛出了异常。
  openThrew,

  /// The player reported a [MovaErrorEvent] while the ad was loading or
  /// playing.
  ///
  /// 广告加载或播放期间播放器报告了 [MovaErrorEvent]。
  playerError,

  /// The ad was opened but never produced a first frame within
  /// [MovaAdConfig.loadTimeout].
  ///
  /// 广告已打开，但在 [MovaAdConfig.loadTimeout] 内始终没有产出首帧。
  loadTimeout,

  /// Warming the ad up in a shadow engine timed out or was given up on, and
  /// [MovaAdConfig.notReadyAction] chose to drop the break.
  ///
  /// 在影子引擎里预热广告超时或被放弃，且 [MovaAdConfig.notReadyAction]
  /// 选择了丢弃该广告位。
  warmFailed,
}

/// One ad failure, fed to a [MovaAdFailPolicy].
///
/// A plain value object so the recovery rule is unit-testable with no player,
/// no engine and no Flutter binding.
///
/// 一次广告失败，喂给 [MovaAdFailPolicy]。
///
/// 纯值对象，使兜底规则无需播放器、引擎或 Flutter 绑定即可被测试。
class MovaAdFail {
  /// The break that failed.
  ///
  /// 失败的广告位。
  final MovaAdBreak adBreak;

  /// What went wrong.
  ///
  /// 出了什么问题。
  final MovaAdFailKind kind;

  /// How many times this break has already been attempted, starting at 1 for
  /// the first failure.
  ///
  /// 该广告位已经尝试过的次数，首次失败时为 1。
  final int attempt;

  /// The underlying error object, when there was one.
  ///
  /// 底层错误对象（若有）。
  final Object? error;

  /// Creates a failure record.
  ///
  /// 创建一条失败记录。
  ///
  /// - [adBreak]: the break that failed / 失败的广告位
  /// - [kind]: failure category / 失败类别
  /// - [attempt]: 1-based attempt counter / 从 1 起算的尝试次数
  /// - [error]: underlying error / 底层错误
  const MovaAdFail({
    required this.adBreak,
    required this.kind,
    required this.attempt,
    this.error,
  });
}

/// What the controller should do about a failed ad break.
///
/// 控制器该拿一条失败的广告位怎么办。
enum MovaAdFailAction {
  /// Re-open the same break and try again.
  ///
  /// 重新打开同一条广告位再试一次。
  retry,

  /// Give up on this break, mark it played, and carry on with the pod (or the
  /// content if it was the last one).
  ///
  /// 放弃这一条，标记为已播，继续 pod 的下一条（若已是最后一条则回正片）。
  skipBreak,

  /// Give up on the whole pod: mark every remaining break of the same kind as
  /// played and go straight to the content.
  ///
  /// 放弃整个 pod：把同类型的所有剩余广告位都标记为已播，直接进正片。
  abandonPod,
}

/// Decides how to recover from an ad that would not play.
///
/// The counterpart of [MovaWarmPolicy] on the failure side: a pure, injectable
/// rule so hosts with a real ad stack (fill-rate targets, make-good
/// obligations, per-campaign retry budgets) can replace it wholesale instead
/// of living with mova's opinion.
///
/// 判定一条播不出来的广告该如何兜底。
///
/// 失败侧与 [MovaWarmPolicy] 对应的那一半：纯粹、可注入的规则，使有真实广告
/// 体系的宿主（填充率指标、补播义务、每个 campaign 各自的重试预算）能整体
/// 替换掉它，而不必忍受 mova 的一家之言。
abstract class MovaAdFailPolicy {
  /// Returns the action to take for [failure].
  ///
  /// 返回针对 [failure] 应采取的动作。
  ///
  /// - [failure]: the failure being recovered from / 待兜底的失败
  ///
  /// Returns the recovery action / 返回兜底动作。
  MovaAdFailAction onFailure(MovaAdFail failure);
}

/// Retries up to [maxRetries] times, then skips the break and carries on.
///
/// The default, with [maxRetries] zero. Retrying a broken ad URL costs the
/// viewer a second stall for something they did not ask to watch, so the
/// out-of-the-box answer is "the viewer's time wins": drop that one creative,
/// keep the rest of the pod. Hosts who own make-good obligations raise
/// [maxRetries] deliberately.
///
/// 最多重试 [maxRetries] 次，之后跳过该广告位继续。
///
/// 默认策略，[maxRetries] 为 0。对一个坏掉的广告地址重试，代价是让观众为一个
/// 他本来就没想看的东西再卡一次，因此开箱默认是"观众的时间优先"：丢掉这一条
/// 素材，保留 pod 的其余部分。有补播义务的宿主可以自行调高 [maxRetries]。
class MovaAdRetrySkip implements MovaAdFailPolicy { … }

/// Abandons the entire pod on the first failure and goes straight to content.
///
/// 首次失败即放弃整个 pod，直接进正片。
class MovaAdAbandonPod implements MovaAdFailPolicy { … }
```

**Produces（`ad_config.dart` 新增类型）:**

```dart
/// Decides whether a given ad break should be warmed up and cut to only once
/// it is actually ready to play.
///
/// Injectable so hosts can base the answer on anything they know and mova does
/// not — current network class, whether the creative is a high-value takeover,
/// a server-side flag, an A/B bucket. The built-in [MovaAdWaitByKind] answers
/// it from the break's [MovaAdBreakKind] alone.
///
/// 判定某一条广告位是否应当先预热、待其真正可播后才切入。
///
/// 可注入，使宿主能依据任何 mova 不知道的信息作答——当前网络等级、这条素材
/// 是不是高价值大包段、服务端下发的开关、A/B 分桶。内置的
/// [MovaAdWaitByKind] 仅依据广告位的 [MovaAdBreakKind] 作答。
abstract class MovaAdWaitPolicy {
  /// Returns whether [adBreak] should wait for readiness before cutting in.
  ///
  /// 返回 [adBreak] 是否应等待就绪后再切入。
  ///
  /// - [adBreak]: the break about to play / 即将播放的广告位
  ///
  /// Returns whether to wait / 返回是否等待。
  bool waitFor(MovaAdBreak adBreak);
}

/// Answers "wait for readiness?" per [MovaAdBreakKind], defaulting to the one
/// rule that follows from what is on screen during the wait.
///
/// The value of waiting equals the value of the picture the viewer is looking
/// at while you wait. During a **mid-roll** that picture is the content they
/// are actively watching, and cutting it to a loading spinner both ruins the
/// moment and spends an impression on a black rectangle — so [mid] defaults to
/// true. During a **pre-roll** there is no picture at all: the ad's own
/// loading state *is* the first screen the viewer expects, nothing is being
/// interrupted, and waiting would only push that first screen further out — so
/// [pre] defaults to false. A **post-roll** follows the same logic as a
/// pre-roll: the content is over, there is no ongoing experience to protect —
/// so [post] defaults to false.
///
/// 依 [MovaAdBreakKind] 回答"是否等待就绪"，默认值由"等待期间屏幕上是什么"
/// 这一条判据推出。
///
/// 等待的价值，等于等待期间用户正看着的那张画面的价值。**中插**期间那张画面
/// 是用户正在观看的正片，把它切成一个转圈既毁掉了当下的观看体验，又把一次
/// 曝光花在了黑矩形上——所以 [mid] 默认 true。**前贴片**期间压根没有画面：
/// 广告自身的加载态*就是*用户预期看到的第一屏，没有任何东西被打断，等待只会
/// 把这第一屏更加推后——所以 [pre] 默认 false。**后贴片**与前贴片同理：
/// 正片已经结束，没有正在进行的体验需要保护——所以 [post] 默认 false。
class MovaAdWaitByKind implements MovaAdWaitPolicy {
  /// Whether pre-rolls wait; false by default.
  ///
  /// 前贴片是否等待；默认 false。
  final bool pre;

  /// Whether mid-rolls wait; true by default.
  ///
  /// 中插是否等待；默认 true。
  final bool mid;

  /// Whether post-rolls wait; false by default.
  ///
  /// 后贴片是否等待；默认 false。
  final bool post;

  /// Creates a per-kind wait rule.
  ///
  /// 创建一份按类型区分的等待规则。
  ///
  /// - [pre]: wait before pre-rolls / 前贴片前是否等待
  /// - [mid]: wait before mid-rolls / 中插前是否等待
  /// - [post]: wait before post-rolls / 后贴片前是否等待
  ///
  /// Example / 示例:
  /// ```dart
  /// // Also wait for post-rolls (a high-value next-episode teaser).
  /// // 后贴片也等待（一条高价值的下集预告）。
  /// const MovaAdConfig(waitForAdReady: MovaAdWaitByKind(post: true));
  ///
  /// // Never wait, anywhere — back to 0.4.0 behaviour.
  /// // 任何位置都不等待——回到 0.4.0 行为。
  /// const MovaAdConfig(waitForAdReady: MovaAdWaitByKind(mid: false));
  /// ```
  const MovaAdWaitByKind({this.pre = false, this.mid = true, this.post = false});

  @override
  bool waitFor(MovaAdBreak adBreak) => switch (adBreak.kind) {
        MovaAdBreakKind.pre => pre,
        MovaAdBreakKind.mid => mid,
        MovaAdBreakKind.post => post,
      };
}
```

`MovaAdConfig` 上的解析入口（**这是控制器唯一该调的口子，三层覆盖只在这里发生一次**）：

```dart
  /// Resolves whether [adBreak] waits for readiness: the break's own
  /// [MovaAdBreak.waitForReady] wins when set, otherwise [waitForAdReady]
  /// decides.
  ///
  /// 解析 [adBreak] 是否等待就绪：广告位自身的 [MovaAdBreak.waitForReady]
  /// 设了就以它为准，否则交由 [waitForAdReady] 裁决。
  ///
  /// - [adBreak]: the break about to play / 即将播放的广告位
  ///
  /// Returns whether to wait / 返回是否等待。
  bool waitsFor(MovaAdBreak adBreak) =>
      adBreak.waitForReady ?? waitForAdReady.waitFor(adBreak);
```

**旋钮表：**

| 字段 | 默认 | 含义 |
|---|---|---|
| `MovaAdWaitPolicy waitForAdReady` | `const MovaAdWaitByKind()`（pre 否 / **mid 是** / post 否） | 是否等广告真正就绪才切入；可整体替换为任意 `MovaAdWaitPolicy`；单条广告位可用 `MovaAdBreak.waitForReady` 再覆盖 |
| `Duration adReadyTimeout` | `5s` | 等待广告就绪的上限 |
| `MovaAdNotReady notReadyAction` | `MovaAdNotReady.hardCut` | 等不到时怎么办：`hardCut`（立刻硬切，可能黑屏）/ `dropBreak`（放弃这条插播，正片不被打断） |
| `MovaAdFailPolicy? failPolicy` | `null` → `const MovaAdRetrySkip()` | 加载失败兜底策略（可注入） |
| `Duration loadTimeout` | `8s` | 广告 `open()` 后多久没有首帧算失败 |
| `bool durationFromFirstFrame` | `true` | `duration` 从首帧起算（而非从 `open()` 起算） |
| `MovaWarmPlan? adWarmPlan` | `null` → 见下 | 广告方向的预热计划（可注入） |

> **`notReadyAction` 为什么仍默认 `hardCut`（在 mid 默认等待之后，这条更要讲清楚）：** 中插现在默认会尝试等待，但**等不到时的降级必须回到今天的行为**——`hardCut` 就是今天的 `open()`。若默认 `dropBreak`，一个只是网络稍差的宿主会发现自己的中插悄悄少了一批，这是库替他吃掉了收入。所以默认是"尽力等，等不到就照今天的样子切"；真正在乎曝光质量的宿主显式选 `dropBreak`——**渲染成一块黑矩形的曝光就是被浪费掉的曝光**，这正是需求 2 的原话动机。两个选项都给足，不替用户拍板。

```dart
/// What to do when an ad was supposed to be warmed up before cutting in, but
/// was not ready in time.
///
/// 当广告本该预热就绪后再切入、却没能及时就绪时该怎么办。
enum MovaAdNotReady {
  /// Cut to the ad anyway, accepting whatever blank/loading the player shows.
  /// Preserves ad inventory at the cost of the viewer's experience.
  ///
  /// 照切不误，接受播放器呈现的黑屏/loading。以观众体验为代价保住广告库存。
  hardCut,

  /// Drop this break entirely; the content is never interrupted. Protects the
  /// viewer — and arguably the advertiser too, since an impression rendered as
  /// a black rectangle is an impression wasted.
  ///
  /// 完全丢弃这条广告位，正片不被打断。保护观众——某种意义上也保护了广告主，
  /// 因为呈现为一块黑矩形的曝光就是被浪费掉的曝光。
  dropBreak,
}

  /// The warm-up plan used for the content→ad direction.
  ///
  /// Defaults to eager (the whole point of [MovaAdBreak.delay] is to spend
  /// that window warming up, so there is nothing to wait for), buffer-based
  /// readiness bounded by [adReadyTimeout], and `pauseWhenReady: true` so the
  /// ad is shown from its first frame.
  ///
  /// 用于 content→ad 方向的预热计划。
  ///
  /// 默认立即触发（[MovaAdBreak.delay] 窗口存在的全部意义就是拿来预热，没有
  /// 再等的道理）、以 [adReadyTimeout] 为界的缓冲判据、以及 `pauseWhenReady:
  /// true` 使广告从第一帧开始展示。
  MovaWarmPlan get effectiveWarmPlan =>
      adWarmPlan ??
      MovaWarmPlan(
        trigger: const MovaEagerWarm(),
        policy: MovaBufferWarm(timeout: adReadyTimeout),
        pauseWhenReady: true,
      );

  /// The failure policy actually in effect.
  ///
  /// 实际生效的失败兜底策略。
  MovaAdFailPolicy get effectiveFailPolicy => failPolicy ?? const MovaAdRetrySkip();
```

> **`pauseWhenReady` 为什么不是一个旋钮：** 它不是口味选择，是广告曝光的正确性不变量——一条在影子引擎里已经悄悄播了两秒的广告，切出来给用户看时就已经缺了开头，且这两秒计不进任何合理的曝光口径。开放性对账表（Task 10）里这一行明确标注"不提供旋钮"并写明这条理由，不是遗漏。

**Steps:** 建 `fail.dart` → 扩 `MovaAdConfig`（字段 + 构造参数 + `copyWith` + `==` + `hashCode` + 两个 `effective*` getter）→ barrel 导出 `src/core/ad/fail.dart`。

**单测要求：**

`fail_test.dart`（6 项，脱离播放器，只构造 `MovaAdFail`）：
1. `MovaAdRetrySkip()`（默认 `maxRetries: 0`）首次失败即返回 `skipBreak`。
2. `MovaAdRetrySkip(maxRetries: 2)`：`attempt` 1、2 返回 `retry`，3 返回 `skipBreak`。
3. `MovaAdRetrySkip` 对 `MovaAdFailKind` 的四个值一视同仁（重试预算与失败原因解耦）。
4. `MovaAdAbandonPod()` 对任何 `attempt`/`kind` 都返回 `abandonPod`。
5. 两个内置实现都无状态：同一实例连续调用互不影响。
6. `MovaAdFail` 值对象四个字段可读回，`error` 可为 null。

`options_test.dart`（追加 6 项）：
7. 七个新字段的默认值全覆盖；`waitForAdReady` 默认是 `MovaAdWaitByKind` 实例。
8. **`MovaAdWaitByKind()` 的三个默认值：`pre` false、`mid` true、`post` false**（本次澄清的核心断言）。
9. `MovaAdWaitByKind.waitFor` 对三种 kind 各返回对应值；`MovaAdWaitByKind(mid: false, post: true)` 能整体改写默认。
10. `MovaAdConfig.waitsFor`：`MovaAdBreak.waitForReady` 为 `true`/`false` 时**压过**按 kind 的默认（两条断言，分别用一条 `pre` 强制 true、一条 `mid` 强制 false）。
11. `MovaAdConfig.waitsFor`：`waitForReady` 为 null 时落到注入的 `MovaAdWaitPolicy`，且该策略确实被调用一次（记录型假策略）。
12. `effectiveWarmPlan`/`effectiveFailPolicy` 的默认与注入；`MovaAdConfig.copyWith` 逐个新字段只替换一个；`MovaOpts.copyWith(ads: …)` 不影响其他节。

**验收标准：** 572 项全绿；`MovaAdConfig` 既有三字段的测试一项未改。

---

## Task 4: 正片源延迟解析（需求 1）

**问题：** `load(MovaSource)` 要求正片地址在**构造 `MovaSource` 的那一刻**就已知。真实场景里正片地址要等广告播完、按用户画像/DRM 授权/签名 URL 时效动态决定。

**方案：** 新增 `loadDeferred(MovaSourceResolver)`。`_content` 从"构造期给定的值"变成"首次真正需要时才求值、之后记忆化的惰性槽"。**只加入口，不动 `load(MovaSource)` 的任何语义**——它内部走同一条惰性槽，用一个立即返回的 resolver 播种。

**Files:**
- Modify: `lib/src/core/model/source.dart`, `lib/src/core/ad/ad_controller.dart`, `lib/mova.dart`
- Test: `test/core/ad_controller_test.dart`（追加 8 项）

**Produces:**

```dart
/// Resolves the content source on demand, called only when the player is
/// actually about to open it.
///
/// Exists so a host can hand `MovaAdCtrl` a promise of a source rather than a
/// source: the real content URL is commonly decided *after* the pre-roll has
/// played — by entitlement/DRM checks, by the viewer profile, or simply
/// because a signed URL minted at page load would already have expired by the
/// time the ads finish.
///
/// 按需解析正片源，仅在播放器真的要打开它时才被调用。
///
/// 它的存在是为了让宿主能把"一个源的承诺"而非"一个源"交给 `MovaAdCtrl`：
/// 真实的正片地址常常是在前贴片播完*之后*才定下来的——取决于权益/DRM 校验、
/// 用户画像，或者仅仅因为页面加载时签发的签名 URL 到广告播完早就过期了。
typedef MovaSourceResolver = Future<MovaSource> Function();
```

```dart
  /// Loads content whose source is resolved lazily, with its scheduled ads.
  ///
  /// Behaves exactly like [load] except that [resolve] is not called until the
  /// content is actually about to be opened — after every pre-roll has
  /// finished, or (when seamless swapping is on) a couple of seconds before
  /// the last pre-roll ends, when the content starts warming up. The result is
  /// memoised: [resolve] is called at most once per [loadDeferred].
  ///
  /// If [resolve] throws or rejects, the controller goes idle and the error is
  /// reported on [contentError]; the host decides whether to call
  /// [loadDeferred] again.
  ///
  /// 带排期广告地加载一段"源需要惰性解析"的正片。
  ///
  /// 与 [load] 完全相同，区别只在于 [resolve] 直到正片真的要被打开时才调用——
  /// 即所有前贴片播完之后，或（开启无缝切换时）最后一条前贴片结束前一两秒、
  /// 正片开始预热之时。结果会被记忆化：每次 [loadDeferred] 最多调用一次
  /// [resolve]。
  ///
  /// [resolve] 抛出或 reject 时，控制器转入空闲，错误经 [contentError] 上报；
  /// 是否重新调用 [loadDeferred] 由宿主决定。
  ///
  /// - [resolve]: resolves the content source on demand / 按需解析正片源
  ///
  /// Example / 示例:
  /// ```dart
  /// await ads.loadDeferred(() async {
  ///   final play = await api.requestPlayback(videoId);  // DRM / signed URL
  ///   return MovaSource(play.url, title: play.title);
  /// });
  /// ```
  Future<void> loadDeferred(MovaSourceResolver resolve) async { … }

  /// Fires when the content source resolver passed to [loadDeferred] failed;
  /// carries the thrown object.
  ///
  /// 当传给 [loadDeferred] 的正片源解析器失败时触发；携带抛出的对象。
  Stream<Object> get contentError => _contentError.stream;
```

**Steps:**
1. `typedef MovaSourceResolver` 落在 `model/source.dart`（与 `MovaSource` 同处，barrel 已传递导出）。
2. 控制器内部：`MovaSource? _content` 保留为**已解析结果的缓存**，新增 `MovaSourceResolver? _resolve`。新增私有 `Future<MovaSource?> _contentSource()`：`_content` 非空直接返回；否则 `_resolve` 为空返回 null；否则 `await _resolve!()`，成功则写入 `_content` 并返回，失败则 `_contentError.add(e)` 并返回 null。
3. `load(MovaSource c)` 改为 `_content = c; _resolve = null;` 后与今天完全一致的流程（**不经过 resolver，零 await 增量**）。
4. `loadDeferred(r)` 设 `_content = null; _resolve = r;` 后走同一流程。
5. 三个消费点改为 `await _contentSource()`：`_playContent()`、`_onProgress` 里 ad 阶段的 `swap.prepare(content, …)`、以及 Task 7 的 delay 阶段。**`_playContent()` 拿到 null 时只做 `_changes.add(null)` 后返回**（今天 `_content == null` 就是这么处理的，语义一致）。
6. 新增 `_contentError` broadcast controller，`dispose()` 里关闭。

**取舍判断：** 为什么是新方法 `loadDeferred` 而不是把 `load` 的参数改成 `FutureOr<MovaSource> Function()`？① `load(MovaSource)` 是本库最常被调用的广告入口，example 与两处测试都在用，改签名收益为零；② 两个入口各自的 dartdoc 能把"什么时候调用 resolver"讲清楚，一个联合类型参数讲不清；③ `contentError` 只对 deferred 路径有意义，分开更诚实。

**单测要求（追加 8 项）：**
1. `loadDeferred` 在有前贴片时，**广告开始播放之后 resolver 仍未被调用**（`resolverCalls == 0`）——这是需求 1 的核心断言。
2. 前贴片 `MovaDone` 后 resolver 被调用**恰好一次**，且 `api.source?.uri` 等于 resolver 返回的地址。
3. 无前贴片时 `loadDeferred` 立刻调用 resolver 并起播（不引入额外阶段）。
4. 中插广告结束回正片时 resolver **不再**被第二次调用（记忆化）。
5. 开启 swap 时，广告播放中的 `prepare` 用的是 resolver 解析出的源（且 resolver 仍只被调一次）。
6. resolver 抛出 → `contentError` 收到该对象，`isShowingAd` 为 false，`_api.calls` 上不出现 `open`。
7. resolver 抛出后再次 `loadDeferred` 能正常重试（惰性槽被重置）。
8. **`load(MovaSource)` 路径逐字不变**：既有前贴片→正片用例的 `api.calls` 序列与 0.4.0 相同（回归护栏）。

**验收标准：** 580 项全绿；既有 31 项广告用例一条未改。

---

## Task 5: `MovaAdBreak.duration` 定长广告位（需求 3a、6 的 duration 半边）

**核心约束（重申）：不碰媒体时间轴。** 到期用 `Timer`，到期后走与 `skip()` **完全相同**的同步续播路径。

**Files:**
- Modify: `lib/src/core/ad/ad_controller.dart`
- Test: `test/core/ad_controller_test.dart`（追加 9 项）

**Produces / 实现要点:**

1. 新增字段 `Timer? _slotTimer;`、`bool _resuming = false;`。
2. `_playAd(b)` 末尾**不**直接起表。起表点由 `MovaAdConfig.durationFromFirstFrame` 决定：
   - `true`（默认）：在 `_onProgress` 的 ad 分支里，见到该广告位的**第一个** progress tick 时 `_armSlotTimer(b)`（用 `_slotTimer == null && b.duration != null` 守卫，保证只起一次）。
   - `false`：`_playAd` 里 `await _api.open(...)` 之后立刻 `_armSlotTimer(b)`。
3. `_armSlotTimer(b)`：`_slotTimer = Timer(b.duration!, () { if (_phase != _Phase.ad || _current != b) return; _fire(MovaAdEventType.completed, b); unawaited(_resumeAfterAd(b)); });`
   —— 到期视为 `completed`：广告位买定的时长已经履约。
4. **续播去重守卫 `_resuming`**：`_resumeAfterAd` 开头 `if (_resuming) return; _resuming = true;`，在它内部真正切到下一状态（`_playAd` / `_playContent` / `_goIdleAfterContent`）之前复位。这是必须的——`duration` 到期、素材自身 `MovaDone`、用户 `skip()` 三条路现在可能在同一 tick 内撞车，0.4.0 没有这道守卫（当时只有两条路且互斥性靠 `_phase` 侥幸成立）。
5. `_cancelSlotTimer()` 在四处调用：`_playAd` 开头（切到下一条广告时）、`_playContent` 开头、`_goIdleAfterContent`、`dispose()`。
6. **需求 6 的 duration 半边**：`_slotTimer` 是 `_playAd` 级别的，pod 里每条广告各自 `_armSlotTimer`，**天然各自独立计时**——这是结构性保证，不需要额外代码，但需要一条 pod 用例把它钉住。

**单测要求（追加 9 项，全部用 `fakeAsync` 或 `FakeTimer` 推进时钟，不用真实 `await Future.delayed`）：**
1. `duration` 为 null 时行为逐字不变（无 timer、仍靠 `MovaDone` 结束）——回归护栏。
2. `duration: 15s` 的中插：推进 15s 后自动回正片（`api.source?.uri == content.uri`），**且过程中从未收到 `MovaDone`**。
3. 同上场景下 `onAdEvent` 收到 `completed`（不是 `skipped`）。
4. `duration` 到期的续播路径与 `skip()` 逐字相同：中插回到 `_contentResumeAt`（断言 `api.lastSeek`）。
5. 素材自身 `MovaDone` 早于 `duration` 到期 → 立刻续播，且**后续 timer 到期不再触发第二次续播**（`_resuming` + `_current` 守卫；断言 `open` 只出现一次）。
6. 用户 `skip()` 早于 `duration` 到期 → 同上，timer 到期不二次触发。
7. `durationFromFirstFrame: true`（默认）下：`open()` 后不推 progress，推进超过 `duration` 的时长，**不**续播；推第一个 tick 后再推进 `duration`，才续播（首帧起算的行为级断言）。
8. `durationFromFirstFrame: false` 下：不推 progress、直接推进 `duration` 即续播。
9. **pod 内 duration 各自独立**：两条前贴片各 `duration: 5s`，推进 5s 播第二条、再推进 5s 进正片；断言两条都完整计了自己的 5 秒（需求 6）。

**验收标准：** 589 项全绿；`skip()` 的既有三项断言一条未改。

---

## Task 6: `_Phase.pending` 与 `delay` 倒计时（需求 3b、6 的 delay 半边）

**新增一个阶段。** 今天是 idle/ad/content 三态，`delay` 需要第四态：**广告已到期、但正片仍在播、倒计时进行中**。

**Files:**
- Modify: `lib/src/core/ad/ad_controller.dart`
- Test: `test/core/ad_controller_test.dart`（追加 16 项）

**Produces:**

```dart
enum _Phase {
  idle,

  /// A mid-roll is due but has not taken over yet, while the content
  /// deliberately keeps playing — either because its [MovaAdBreak.delay]
  /// countdown is running, or because the ad is being warmed up in the
  /// background and is not ready to be shown, or both. Distinct from [content]
  /// because no *further* mid-roll may be triggered here, and distinct from
  /// [ad] because nothing has interrupted the viewer yet.
  ///
  /// 一条中插已到期但尚未接管，而正片刻意继续播放——可能是其
  /// [MovaAdBreak.delay] 倒计时正在走，可能是广告正在后台预热、还不能见人，
  /// 也可能两者同时。与 [content] 不同之处在于此阶段不得再触发*别的*中插；
  /// 与 [ad] 不同之处在于观众此刻还没有被打断。
  pending,

  ad,
  content,
}
```

公开面新增：

```dart
  /// Whether an ad is counting down to take over while the content still
  /// plays.
  ///
  /// 是否有一条广告正在倒计时、即将接管，而正片仍在播放。
  bool get isAdPending => _phase == _Phase.pending;

  /// The break that is counting down, or null when none is.
  ///
  /// 正在倒计时的广告位；没有则为 null。
  MovaAdBreak? get pendingBreak => _pending;

  /// Time left before the pending ad takes over, or null when none is pending.
  ///
  /// 距待播广告接管还剩的时长；没有待播广告时为 null。
  Duration? get delayRemaining { … }
```

**实现要点：**
1. **进入 `pending` 的条件从"有 delay"放宽为"有 delay 或要等待就绪"**：`_onProgress` 的 `content` 分支里 `dueMidRoll` 命中后
   ```dart
   final wantsDelay = due.delay > Duration.zero;
   final wantsWait  = _wantsWait(due);   // Task 7 提供
   if (wantsDelay || wantsWait) { _beginDelay(due); } else { unawaited(_playAd(due)); }
   ```
   `_wantsWait(b)` = `_swap != null && _swap.swapEnabled && _cfg.waitsFor(b)`。**默认路径（不接 swap engine）恒为 false，零变化。**
2. `_beginDelay(b)` 里的定时器只在 `b.delay > 0` 时才起；`delay == 0` 且仅因等待而进入 pending 时，**没有倒计时、没有角标**，退出完全由就绪信号（或 `adReadyTimeout`）驱动。`delayRemaining` 在这种情况下返回 `null`——UI 据此不渲染任何东西（Task 9）。

3. `_beginDelay(b)`（完整实现）：`_phase = _Phase.pending; _pending = b; _played.add(b);`（**立刻标记已播**，避免倒计时期间被 `dueMidRoll` 反复命中）、`_delayDeadline = Duration/DateTime 基准`、`_delayTimer = Timer(b.delay, () => unawaited(_beginAd(b)))`、`_fire(MovaAdEventType.pending, b)`、`_changes.add(null)`。
4. **`pending` 阶段正片继续播放**：`_onProgress` 的 `pending` 分支持续更新 `_lastContentPosition` 与 `_contentResumeAt = p.position`——续播点是**广告真正接管那一刻**的位置，不是倒计时开始那一刻。**此分支不再调用 `dueMidRoll`**（避免倒计时期间又弹一条）。
5. `_beginAd(b)`：Task 7 接管其内部；本 Task 先实现为直接 `_playAd(b)`。
6. **需求 6：pod 内 delay 只出现一次。** 这是**结构性保证**而非条件判断：`delay` 只在 `_onProgress`/`playAdNow`/`load` 这三个**入口**被查询；`_resumeAfterAd` 串到 pod 下一条时一律直接 `_playAd(next)`，永不经过 `_beginDelay`。文档与测试都要把这条钉死。
7. **顺带修正：中插 pod 今天根本没有串联。** `_resumeAfterAd` 的 `mid` 分支直接 `_playContent(at:)`，pod 里的第二条中插要靠"回到正片 → 下一个 tick 再被 `dueMidRoll` 命中"才播——这会让画面在两条广告之间闪一下正片，**并且在本 Task 之后会让第二条中插再弹一次 delay 倒计时**，正是需求 6 要杜绝的。改为：`mid` 分支先找"下一条未播、且 `offset <= _contentResumeAt`"的中插，有则 `_playAd(next)` 直接串联，无则 `_playContent(at: _contentResumeAt)`。
   > **已核对既有断言不受影响**：`ad_controller_test.dart` 的 `'multiple mid-rolls at arbitrary offsets each play once, in order'` 用的是 30s 与 60s 两个不同 offset，mid1 播完时 `_contentResumeAt == 31s < 60s`，不满足串联条件，仍走 `_playContent`，该用例的每一条断言（含"resumed content"那两条）逐字成立。实现前仍须先跑一遍该用例确认。
8. `playAdNow(ad)`：若 `ad.delay > 0` 或 `_wantsWait(ad)` 则走 `_beginDelay`（此时 `_phase` 必须是 `content`）；否则维持今天的 `_playAd`。`_phase == _Phase.pending` 时 `playAdNow` 为空操作（已经有一条在排队了）。
9. 生命周期：正片在 `pending` 期间播完（`MovaDone`）→ 取消 `_delayTimer`、丢弃 `_pending`（它是排在正片里的中插，正片没了它也没意义）、走今天的正片结束逻辑（后贴片 / idle）。`skip()` 在 `pending` 阶段是**空操作**（屏幕上还没有广告可跳，"取消即将播放的广告"是宿主的产品决策，不是播放器的）。`dispose()` 取消 `_delayTimer`。

**单测要求（追加 16 项，时钟用 fakeAsync）：**
1. `delay` 为 `Duration.zero`（默认）时，中插触发路径逐字不变——回归护栏。
2. `delay: 5s` 的中插到期：`isAdPending` 为 true、`isShowingAd` 为 false、`api.source?.uri` 仍是正片（**正片没被打断**）。
3. 同上：`onAdEvent` 收到 `pending`，且**尚未**收到 `started`。
4. 同上：`changes` 在进入 pending 时发出一次。
5. `delayRemaining` 随 progress tick 递减，倒计时结束前 > 0。
6. 推进 5s 后广告接管：`isShowingAd` 为 true、`isAdPending` 为 false、`api.source?.uri` 是广告地址、`onAdEvent` 收到 `started`。
7. **倒计时期间正片继续推进**：pending 阶段连续推 progress，`_api.calls` 上**不出现** `pause`/`open`/`seek`（正片没有被任何形式地打断）。
8. **续播点取接管那一刻**：pending 开始于 30s、推进到 35s 才接管，广告结束后 `api.lastSeek == 35s`（不是 30s）。
9. **需求 6：pod 内 delay 只弹一次**。两条前贴片、第一条 `delay` 非零（用 mid 构造 pod：两条同 offset 的中插，第一条 `delay: 3s`，第二条 `delay: 3s`）→ `pending` 事件只出现**一次**，第二条广告紧接第一条播出、中间**不**再进入 pending、`api.source` **不**回到正片一次。
10. 倒计时期间不会触发第二条中插：pending 阶段推一个越过另一条中插 offset 的 progress，该条**不**被触发（`played` 不含它）。
11. `playAdNow` 带 `delay` 的广告：进入 pending，倒计时结束后接管，续播点是接管那一刻的位置。
12. `playAdNow` 在 pending 阶段是空操作。
13. 正片在 pending 期间 `MovaDone` → `_delayTimer` 被取消、`isAdPending` 为 false、走后贴片/idle 逻辑（断言 `contentEnded` 或后贴片起播）。
14. `skip()` 在 pending 阶段是空操作（`isAdPending` 仍为 true、无任何 api 调用）。
15. **`delay == 0` + `waitsFor` 为 true + swap 开启 → 仍然进入 `pending`**，正片继续播、`delayRemaining` 为 `null`、`changes` 发出一次。
16. `delay == 0` + `waitsFor` 为 false（或未接 swap）→ **不**进入 pending，行为与 0.4.0 逐字相同（默认路径护栏）。

**验收标准：** 605 项全绿；`'multiple mid-rolls at arbitrary offsets each play once, in order'` 与 `'an ad pod plays every pre-roll in order before the content'` 两项既有用例断言一条未改。

---

## Task 7: 按广告位类型决定是否等待就绪、就绪后原子切入（需求 2、5）

**这是三个抽象反向复用的落点。** delay 窗口（若有）与"是否等待"是两件独立的事，但共用同一套预热/切换编排。

**Files:**
- Modify: `lib/src/core/ad/ad_controller.dart`
- Test: `test/core/ad_controller_test.dart`（追加 16 项）

**实现要点：**

1. `_wantsWait(MovaAdBreak b)`：
   ```dart
   bool _wantsWait(MovaAdBreak b) {
     final swap = _swap;
     // Waiting needs somewhere to warm up in; with no swap engine the whole
     // question is moot and the per-kind default never even gets consulted.
     //
     // 等待需要一个可供预热之处；没有切换引擎时这个问题根本不成立，
     // 按类型的默认值压根不会被查询。
     return swap != null && swap.swapEnabled && _cfg.waitsFor(b);
   }
   ```
   **三层覆盖（break → config policy → 按 kind 默认）全部封在 `_cfg.waitsFor` 里，控制器不做任何 kind 判断**——不许在 `ad_controller.dart` 里出现 `kind == MovaAdBreakKind.mid` 这种分支，否则宿主的覆盖就绕不过去了。这条写进注释。

2. **前贴片与后贴片天然走不到 `pending` 状态机，但仍须能等待。** `load()` 里的前贴片在 `_Phase.idle` 下起播，根本没有 progress tick 来驱动 `prepare`；`_resumeAfterAd` 串到后贴片时正片已结束、同样没有 tick。因此即使宿主把 `MovaAdWaitByKind(pre: true)` 打开，也**不能**靠 Task 6 的 `pending` 循环兑现。处理方式：`_playAd` 在 `_wantsWait(b)` 为 true **且当前阶段不是 `pending`**（即没有 Task 6 的预热窗口跑过）时，走一次**一次性**的 `swap.swapTo(b.source)`——`swapTo` 正是"不可预测切换点"的单次调用形式，内部就是 eager 预热 + `commit(waitForReady: true)` + 失败回落 `open()`，语义严丝合缝，**一行新逻辑都不用写**。返回 false 时它已经自己做了 `open()` 兜底，控制器只需照常做阶段簿记。
   > 这也是 `MovaSwapCtl` 的四个动词"已经够用"的第三处印证：两段式（`prepare`+`commit`）服务可预测切换点（中插有 delay/预热窗口），一次式（`swapTo`）服务不可预测切换点（前/后贴片"就是现在"）。

3. `_onProgress` 的 `pending` 分支：`_wantsWait(b)` 为真时每 tick 调 `prepare`（`at: Duration.zero`、`plan: _cfg.effectiveWarmPlan`），`cue` 为
   `MovaWarmCue(remaining: delayRemaining, total: b.delay)`；**`delay == 0` 时两者均为 `null`**，此时 `MovaEagerWarm` 仍返回 true（它无视 cue），预热照常启动——这正是把 `MovaEagerWarm` 选作广告方向默认触发策略的原因。

4. **退出 pending 的条件是"倒计时走完"与"广告就绪"的合取**，由两个独立信号汇合：
   - `delay > 0`：delay 定时器到期时调 `_beginAd(b)`。
   - `_wantsWait` 为真：额外起一个 `adReadyTimeout` 的兜底定时器；`swap.commit(waitForReady: true)` 自身受判据超时约束。
   - 两者都有 → `_beginAd` 在 delay 到期时才被调，其内部再 `commit(waitForReady: true)` 等就绪（即"至少 delay，最多 delay + adReadyTimeout"）。
   - 只有等待（`delay == 0`）→ `_beginAd` 立刻被调，`commit(waitForReady: true)` 负责全部等待。

5. `_beginAd(b)`（Task 6 留的钩子）完整实现：
   ```dart
   Future<void> _beginAd(MovaAdBreak b) async {
     if (!_wantsWait(b)) { await _playAd(b); return; }          // 今天的路径
     if (await _swap!.commit(waitForReady: true)) {
       await _playAd(b, alreadyOnScreen: true);                 // 已原子切到广告
       return;
     }
     switch (_cfg.notReadyAction) {
       case MovaAdNotReady.hardCut:  await _playAd(b);
       case MovaAdNotReady.dropBreak:
         _fire(MovaAdEventType.failed, b, error: …);
         _abandonPending();
     }
   }
   ```
6. `_playAd` 加一个**私有**具名参数 `bool alreadyOnScreen = false`：为 true 时跳过 `await _api.open(b.source)` 与那一句 `unawaited(_swap?.abandon())`（影子刚刚才转正，不能拆），其余（`_phase`/`_current`/`_adPosition`/`_played`/`_changes`/`_fire(started)`/STT 抑制）**一律照常执行**。这是必须的——阶段簿记绝不能因为走了无缝路径而漏掉，这条正是 0.4.0 Task 7 第 7 项测试守住的东西。
7. `_abandonPending()`：取消 delay timer、`_pending = null`、`_phase = _Phase.content`、`unawaited(_swap?.abandon())`、`_changes.add(null)`。

**取舍判断（`dropBreak` vs `hardCut` 谁当默认）：** 默认 `hardCut`，理由是**默认必须等于今天的行为**——中插现在默认会尝试等待，但**等不到时的降级必须回到今天的行为**（`hardCut` 就是今天的 `open()`）。若默认 `dropBreak`，一个只是网络稍差的宿主会发现自己的中插悄悄少了一批，这是库替他吃掉了收入。真正在乎曝光质量的宿主显式选 `dropBreak`——**渲染成一块黑矩形的曝光就是被浪费掉的曝光**，这正是需求 2 的原话动机。两个选项都给足，不替用户拍板。

**单测要求（追加 16 项，用 `FakeSwapCtl`）：**
1. 未接 swap（`_swap == null`）时：`prepare`/`swapTo` 从不被调用，全部走 `open()`——回归护栏。
2. `swapEnabled` 为 false 时同上（哪怕 `waitsFor` 返回 true）。
3. **中插默认等待**：接了 swap、配置全默认、一条 `delay: 0` 的中插到期 → 进入 pending、`prepare` 被调用、正片未被打断。
4. **前贴片默认不等待**：同一份默认配置下，前贴片走 `open()`，`prepare`/`swapTo` **都不被调用**（本次澄清的核心断言）。
5. **后贴片默认不等待**：同上。
6. `MovaAdWaitByKind(mid: false)` → 中插退回立刻硬切，`prepare` 不被调用（宿主能关掉默认）。
7. `MovaAdWaitByKind(pre: true)` → 前贴片走 `swapTo`（而非 `prepare`+`commit`），返回 true 时 `_api.calls` 上不出现 `open`。
8. `MovaAdBreak.waitForReady: false` 压过 `mid` 的默认 true。
9. `MovaAdBreak.waitForReady: true` 压过 `pre` 的默认 false。
10. 注入自定义 `MovaAdWaitPolicy` 时它确实被 `MovaAdCtrl` 咨询（记录型假策略），且按其返回值决定路径。
11. 等待路径下每个 tick 都调 `prepare`，`plan` 等于 `_cfg.effectiveWarmPlan`（断言 `pauseWhenReady == true`、`trigger is MovaEagerWarm`）、`at` 恒为 `Duration.zero`。
12. `delay > 0` 时 `cue.remaining` 随倒计时递减、`cue.total == b.delay`；**`delay == 0` 时两者均为 `null`**。
13. `commit` 返回 true → `_api.calls` 上不出现 `open`，但 `isShowingAd` 为 true、`onAdEvent` 收到 `started`、`changes` 发出（阶段簿记不漏）；且 `abandon()` **不**被调用。
14. `commit` 返回 false + `hardCut` → 出现 `open`，广告照常开始。
15. `commit` 返回 false + `dropBreak` → 不出现 `open`、`isShowingAd`/`isAdPending` 均为 false、阶段回 content、`onAdEvent` 收到 `failed`、该广告位已标记已播、`abandon()` 被调用一次。
16. **ad→content 方向不受影响**：0.4.0 的"广告播放期间 tick 调 `prepare(content, …)`"仍成立，且此时 `plan` 为默认 `const MovaWarmPlan()`（两个方向各用各的计划，互不串味）。

**验收标准：** 621 项全绿；0.4.0 Task 7 的既有 10 项无缝回切用例断言一条未改；**`ad_controller.dart` 全文 `grep` 不到 `MovaAdBreakKind.mid ==` 形式的等待判断**（kind 判断只许存在于 `MovaAdWaitByKind` 里）。

---

## Task 8: 广告加载失败兜底（需求 4）

今天完全没有这条路径：`_api.open(ad.source)` 抛了没人管、`MovaErrorEvent` 没人听、广告卡在加载中没有超时。

**Files:**
- Modify: `lib/src/core/ad/ad_controller.dart`, `test/support/fake_api.dart`
- Test: `test/core/ad_controller_test.dart`（追加 14 项）

**实现要点：**

1. `fake_api.dart`：`FakeMovaApi` 加 `Object? openThrows`（非空时 `open()` 抛它）+ `int openCalls`。纯增量。
2. 四个失败入口，全部汇流到一个 `_onAdFailure(MovaAdBreak b, MovaAdFailKind kind, [Object? error])`：
   - `_playAd` 里 `await _api.open(b.source)` 包 try/catch → `openThrew`。
   - `_onEvent` 加分支：`if (e is MovaErrorEvent && (_phase == _Phase.ad))` → `playerError`。（**只在 ad 阶段拦截**；正片的播放错误不归广告控制器管，继续原样流给宿主。）
   - `_playAd` 后起 `_loadTimer = Timer(_cfg.loadTimeout, …)`，在该广告位的**第一个** progress tick 上取消；到期未取消 → `loadTimeout`。
   - Task 7 的 `dropBreak` 分支 → `warmFailed`（复用同一汇流口，但它不走重试——`notReadyAction` 已经是那一层的裁决；实现上 `dropBreak` 直接 `_fire(failed)` + `_abandonPending()`，**不**进 `_onAdFailure`。这条要在注释里写明，避免两层策略叠加导致行为难以推理）。
3. `_onAdFailure`：
   ```dart
   _attempts[b] = (_attempts[b] ?? 0) + 1;
   _fire(MovaAdEventType.failed, b, error: error);
   final action = _cfg.effectiveFailPolicy.onFailure(
       MovaAdFail(adBreak: b, kind: kind, attempt: _attempts[b]!, error: error));
   switch (action) {
     case MovaAdFailAction.retry:     await _playAd(b, isRetry: true);
     case MovaAdFailAction.skipBreak: await _resumeAfterAd(b);   // 同 skip() 的路径
     case MovaAdFailAction.abandonPod:
       _markPodPlayed(b.kind);                                   // 同类型剩余全标已播
       await _resumeAfterAd(b);
   }
   ```
   `_attempts` 是 `Map<MovaAdBreak, int>`，在 `load`/`loadDeferred` 时清空。`_playAd(b, isRetry: true)` 不重复 `_fire(started)`、不重复 `_played.add`（幂等，`_played` 是 Set 本就幂等，但不要重复发事件）。
4. `abandonPod` 的 `_markPodPlayed(kind)`：把 `_breaks` 里所有该 `kind` 且未播的都塞进 `_played`。对 `mid` 只标记 `offset <= _contentResumeAt` 的那些（同一 pod 的定义就是同一插入点）——否则会把后面几十分钟的中插全吃掉，那不是"放弃 pod"，是"关掉广告"。**这条边界必须有测试。**
5. `_cancelLoadTimer()` 与 `_slotTimer` 一样在 `_playAd` 开头 / `_playContent` / `_goIdleAfterContent` / `dispose()` 四处调用。
6. **重试与 `duration` 的交互**：重试时 `_slotTimer` 已在 `_playAd` 开头被取消并会重新起表——重试的那条广告重新获得完整的 `duration`。这是正确的（广告主买的是 15 秒可见时长），写进注释。

**单测要求（追加 14 项）：**
1. 没有失败时行为逐字不变（`failPolicy` 从不被调用）——回归护栏。
2. `open()` 抛出 → `onAdEvent` 收到 `failed`，且 `MovaAdFail.kind == openThrew`、`error` 是抛出的那个对象（用记录型假策略断言）。
3. 默认策略（`MovaAdRetrySkip()`）下，前贴片 `open` 失败 → 直接进正片（`api.source?.uri == content.uri`），`openCalls` 为 1（没有重试）。
4. `MovaAdRetrySkip(maxRetries: 2)` 下，`open` 持续失败 → `openCalls` 为 3（首次 + 两次重试）后进正片。
5. 重试成功（第二次 `open` 不抛）→ 广告正常播放，`onAdEvent` 序列是 `started, failed, started`。
6. `MovaAdAbandonPod()` 下，三条前贴片的第一条失败 → 后两条**都不播**、直接进正片。
7. `abandonPod` 对中插的边界：同 offset 的 pod 被吃掉，**更晚 offset 的中插仍然会在后面正常播出**（第 4 点的边界护栏）。
8. 广告播放中收到 `MovaErrorEvent` → 走失败策略，`kind == playerError`。
9. **正片播放中收到 `MovaErrorEvent` → 失败策略不被调用**（不越界）。
10. `loadTimeout`：`open` 成功但从不推 progress，推进 8s → 走失败策略，`kind == loadTimeout`。
11. 第一个 progress tick 到达后，再推进超过 `loadTimeout` 的时长**不**触发失败（timer 已取消）。
12. `skipBreak` 走的是与 `skip()` 完全相同的续播路径：中插失败后 `api.lastSeek == _contentResumeAt`。
13. pod 中间一条失败 → pod 的下一条照常播（`skipBreak` 不牵连兄弟）。
14. 失败 + 重试的广告位，`duration` 定时器从重试后的首帧重新起算（与 Task 5 交互护栏）。

**验收标准：** 635 项全绿；`fake_api.dart` 的改动是纯增量（既有字段/方法签名一个未改）。

---

## Task 9: delay 倒计时角标（UI）

**Files:**
- Modify: `lib/src/core/options/strings.dart`, `lib/src/ui/components/ad_overlay.dart`
- Test: `test/ui/ad_overlay_test.dart`（追加 7 项）

**Produces:**

```dart
/// Default copy for the "ad starts in N seconds" countdown.
///
/// A top-level function so it can be a `const` default for
/// [MovaStrs.adStartingIn].
///
/// "N 秒后播放广告"倒计时的默认文案。
///
/// 写成顶层函数，以便作为 [MovaStrs.adStartingIn] 的 `const` 默认值。
String movaDefaultAdStartingIn(int seconds) => '$seconds 秒后播放广告';
```

```dart
  /// Builds the countdown copy shown while the content plays on and an ad is
  /// about to take over.
  ///
  /// A function rather than a plain string because the number is embedded in
  /// the sentence and every language puts it somewhere else; a `'$n' + suffix`
  /// concatenation would not survive translation.
  ///
  /// 构造"正片继续播、广告即将接管"期间显示的倒计时文案。
  ///
  /// 用函数而非纯字符串，因为数字嵌在句子中间、各语言的位置都不一样；
  /// `'$n' + 后缀` 式拼接经不起翻译。
  ///
  /// - [seconds]: whole seconds left / 剩余整秒数
  ///
  /// Returns the rendered copy / 返回渲染后的文案。
  final String Function(int seconds) adStartingIn;
```

`ad_overlay.dart` 的 `_AdOverlayViewState.build`：在 `if (!controller.isShowingAd || b == null) return const SizedBox.shrink();` **之前**插入 pending 分支——渲染条件收紧为 **`controller.isAdPending && controller.delayRemaining != null`**：只有宿主显式配了 `delay` 的可见倒计时才画角标（复用现有 `_Countdown` 样式，改为接 `String text`，位置 `bottom: 24, right: 16`，**不**渲染全屏点击层、**不**渲染广告角标）。中插默认形态（`delay == 0`、仅后台等待就绪）**刻意不渲染任何东西**：那段等待对用户就该是不存在的，画一个"正在加载广告"的提示只会把本来无感的事变成有感的事。这条写进组件 dartdoc。倒计时秒数取 `controller.delayRemaining`，同样向上取整（与既有 `skipIn` 的取整规则一致，4.9s 读作 "5"）。progress 回调里 pending 阶段也要 `setState`（今天只在 `isShowingAd` 时更新）。

**单测要求（追加 7 项，WidgetTester）：**
1. 无 pending、无 ad 时不渲染任何东西（回归护栏）。
2. `delay > 0` 的 pending 阶段渲染倒计时文案，内容等于 `adStartingIn(n)` 的输出。
3. pending 阶段**不**渲染广告角标（`strings.adBadge` 找不到）。
4. pending 阶段**不**渲染全屏点击层：点击画面中央**不**触发 `notifyClicked`（正片手势不被吞）。
5. 倒计时数字随 progress tick 递减并重建。
6. 从 pending 切到 ad 后，倒计时消失、广告角标出现（阶段切换的 UI 护栏）。
7. **`delay == 0` 的 pending 阶段（仅等待就绪）不渲染任何东西**——`find.byType(Text)` 为空，屏幕上没有任何广告相关提示。

**验收标准：** 642 项全绿；`ad_overlay_test.dart` 既有用例断言一条未改；`MovaStrs` 的 `==`/`hashCode` 纳入新字段且 `options_test` 既有断言不变。

---

## Task 10: 开放性对账 `test/core/openness_ad_test.dart`

照 `openness_swap_test.dart` 的形式，把本批每个"替用户做的决策"做成可执行测试（9 项）：

| 决策 | 默认值 | 配置项 | 可注入策略 |
|---|---|---|---|
| **广告是否等就绪才切入** | **按 kind：`pre` 否 / `mid` 是 / `post` 否** | `MovaAdConfig.waitForAdReady`（`MovaAdWaitByKind` 的三个字段）+ `MovaAdBreak.waitForReady` 单条覆盖 | `MovaAdWaitPolicy` |
| 等多久算等不到 | 5s | `adReadyTimeout` | `adWarmPlan.policy`（`MovaWarmPolicy`） |
| 何时开始预热广告 | delay 一开始（`MovaEagerWarm`） | —（由 `MovaAdBreak.delay` 决定窗口长度） | `adWarmPlan.trigger`（`MovaWarmTrigger`） |
| 等不到时怎么办 | `hardCut` | `notReadyAction` | —（二选一枚举，语义穷尽） |
| 广告加载失败怎么办 | 跳过该条（`MovaAdRetrySkip()`，0 次重试） | `failPolicy` | `MovaAdFailPolicy` |
| 多久没首帧算加载失败 | 8s | `loadTimeout` | 同上（策略据 `kind` 自行裁决） |
| `duration` 从哪一刻起算 | 首帧 | `durationFromFirstFrame` | — |
| 广告预热就绪后是否停在第 0 帧 | **恒为 true，不提供旋钮** | — | — |

**最后一行必须写成一条显式测试**，断言 `MovaAdConfig().effectiveWarmPlan.pauseWhenReady` 恒为 `true`，且测试名与 `reason` 里写明理由：*这不是口味选择，是广告曝光的正确性不变量——把广告开头几秒在影子引擎里播掉，等于交付一个缺头的曝光。开放性契约在这里让位于正确性，并在此留痕。* 这条是有意识地违反"每个决策都要有旋钮"的唯一一处，必须在对账表里显性存在，而不是悄悄没有。

每行一条测试：断言默认值、断言配置项能改、断言注入的策略确实被 `MovaAdCtrl` 采用（用记录调用的假策略/假 `MovaSwapCtl` 断言它被调过）。首行拆成两条：一条断言三个 kind 的默认值（`pre` 否 / `mid` 是 / `post` 否），一条断言三层覆盖顺序（`MovaAdBreak.waitForReady` > 注入的 `MovaAdWaitPolicy` > 按 kind 默认）各自都能生效。

**验收标准：** 651 项全绿。

---

## Task 11: barrel、example demo 与文档

- `lib/mova.dart` 增补（按字母序）：
  ```dart
  export 'src/core/ad/fail.dart';
  export 'src/core/swap/plan.dart';
  ```
  （`MovaAdNotReady` 由 `options/ad_config.dart` 经 `options.dart` 传递导出；`MovaSourceResolver` 由 `model/source.dart` 传递导出。）
- `example/lib/main.dart` 的广告 demo 页加三个开关，**且三条路径都要能跑**（真机验证要来回切）：
  1. `delay`：中插广告位带 3s 倒计时。
  2. `duration`：中插广告位强制 8s（素材更长，用来肉眼确认"没播完就被收回"且**没有卡死**）。
  3. `waitForAdReady`（`MovaAdWaitByKind` 的 `mid` 字段）：开（默认）时中插在 delay 窗口/后台里预热、就绪后原子切入；关时立刻硬切——demo 应同时演示前贴片默认不等待（`swapTo` 一次式路径）与中插默认等待（`prepare`+`commit` 两段式路径）两种效果。
  再加一个"故意插一条坏 URL 广告"的按钮，用来真机走失败降级路径（Task 12 的 B 组）。
- `README.md` 加"广告编排（delay / duration / 就绪等待 / 失败兜底）"小节；`CHANGELOG.md` 记 0.5.0；`doc/SPEC.md` 加一节（含本文 0.1 节的三抽象复用结论表与"两个预热方向共用同一套 `MovaSwapEngine`"的一句话结论 + 链接）；`CLAUDE.md` 的"当前状态"/"剩余任务"回写（含把测试基线数字从 535 改为本批完成后的真实数字），并把真机验证列为未完成；`CLAUDE.md`「约定」一节补上 Task 2 决定的 assert 约定。
- 追加 3 项 barrel 可见性测试（`MovaWarmPlan`/`MovaAdFailPolicy`/`MovaAdNotReady` 能从 `package:mova/mova.dart` 直接引用）。

**验收标准：** 654 项全绿；`flutter analyze` 0 issues；`cd example && flutter run -d windows` 三条开关的组合都能起。

---

## 本次范围排除（以及为什么）

1. **VAST / VMAP 解析。** mova 的输入是 `MovaAdBreak` 值对象，把 XML 解析塞进核心层要引入 XML 依赖 + 一整套与播放毫不相关的协议状态机。宿主（或一个独立的 `mova_vast` 适配包）把 VAST 翻译成 `MovaAdBreak` 列表，是更干净的边界。本批的 `duration`/`delay` 字段恰恰就是为了让这层翻译能无损落地而加的。
2. **`MovaAdBreak.source` 的延迟解析。** 需求 1 只要求正片。给广告素材也加一层 resolver 会把失败矩阵翻倍（解析失败 × 加载失败 × 预热失败），而宿主已经有一条现成的路：用 `playAdNow` 传一个刚构造好的 `MovaAdBreak`。预配置中插确实覆盖不到——留作 VAST 支持落地时一并评估。
3. **曝光上报 / 可见性测量（quartile beacons、viewability）。** `onAdEvent` + `adPosition` + 本批新增的 `pending`/`failed` 已经把宿主自己算四分位所需的全部信息给足了；在纯 Dart 核心层内置一个 HTTP 打点客户端会引入网络依赖，且各家计量口径互不兼容，库不该替谁拍板。
4. **广告期间禁用 seek / 倍速 / 手势。** 这是皮肤层的事，`MovaPatch` 今天就能表达（0.3.0 的插件化契约就是为这个设计的），塞进 `MovaAdCtrl` 等于让核心层管 UI 策略。
5. **把 `MovaWarmPlan.pauseWhenReady` 的默认值改为 `true`，顺带修正 ad→content 的续播点漂移。** 0.4.0 的正片预热是一路播着等 commit 的，因此切回正片时实际位置会比 `_contentResumeAt` 超前约一个预热窗口（1–2s）。本批的 `pauseWhenReady` 已经把修法造好了，但**默认值不动**——这是 0.4.0 从未在真机上量过的偏差（Task 11 checklist 里"中插回切续播点准确"至今是未测项），在拿到实测数字之前改默认值是拿既有行为去赌。Task 12 的 A-3 就是去量这个数，量完再单独决定。
6. **清晰度切换真正接入 `swapTo`。** 与 0.4.0 Task 8 的结论一致，仍只有契约测试 + 落点注释，不做深实现。
7. **feed 引擎池。** 结构性不适用单渲染面离散替换模型，结论见 `doc/notes/2026-08-05-seamless-quality-switch-feasibility.md` 末节，不改。

---

## Task 12: 真机验证（Android 优先，iOS 次之）

**这是本计划唯一无法靠单测收敛的部分。** 本批的核心命题——"等广告真正就绪再切，比黑屏硬切更划算"——**完全建立在真实网络下的加载时序上**，单测里每一个 `Timer` 都是假的。阈值（`adReadyTimeout` 5s、`loadTimeout` 8s、默认 `delay` 该建议多长）必须真机调。

> **先修工具链再测。** 0.4.0 Task 11 的教训已经写在那份文档里：目标机型没有 `screenrecord`、release 包的 `debugPrint` 在 logcat 里看不到，导致 A/B/C 三组大半子项"未能按原定精度验证"。**本轮开测前必须先解决这两件事**，否则会原样复现一份无结论的记录：
> - **逐帧证据**：换一台带 `screenrecord` 的机型，或用 scrcpy / 外接采集卡录屏，目标是能分辨单帧黑屏。1 秒级截图**不构成**本组任何一条的证据。
> - **事件时序**：用 `--profile` 包（保留 `debugPrint`）而非 `--release`，或在 example 里挂一个把 `MovaSwapChg`/`MovaAdEvent`/`MovaAdFail` 写进屏上滚动日志区的面板（改 example，不改 lib）。**Task 11 的 example 面板应该直接把这个日志区做进去**，本条前置到 Task 11 完成。

### 真机验证 checklist

**A. 等待广告就绪：pre-roll 与 mid-roll 默认行为不同，必须分开验**

*A-1 前贴片（默认不等待）*
- [ ] 全默认配置 + 接 `MovaSwapEngine`：前贴片**没有**任何等待，进播放页后立刻开始加载广告。逐帧确认首屏即广告加载态，**不是**先看到一段空白/正片首帧再切。
- [ ] 逐帧测量"进入播放页 → 广告首帧"的墙钟时长，作为基线。
- [ ] 显式打开 `MovaAdWaitByKind(pre: true)`（走 `swapTo` 那条路）：确认广告能正常播出、**且这个时长明显变长**——用实测数字证明"前贴片不该等"这条默认值是对的。若两者相差无几，说明 `swapTo` 的兜底回落太快，等待压根没发生，要回去查。
- [ ] 弱网下重跑 `pre: true`：确认超时后仍能回落到 `open()`，没有出现"既没等到也没切成"的第三种状态。

*A-2 中插（默认等待）*
- [ ] 全默认配置、`delay: 0`、良好 Wi-Fi：中插到期后**正片继续播到广告就绪那一刻才切**。逐帧录屏数出切入瞬间的黑屏/loading 帧数，目标是 **0**。
- [ ] 记录从"中插到期"到 `MovaSwapChg(ready)` 的墙钟毫秒数，跑 10 次取分布——**这是 `adReadyTimeout` 默认 5s 是否合理的唯一真实依据**。
- [ ] 同上在 4G / 弱网下重跑 10 次，记录分布与超时次数。
- [ ] 对比组：`MovaAdWaitByKind(mid: false)`（退回硬切），同一条中插逐帧数黑屏帧数。**A-2 的结论必须是一个两位数字的对比**（等待路径 N 帧 vs 硬切路径 M 帧），不接受"未见明显差异"。
- [ ] 延迟总账：等待路径下"中插到期 → 广告首帧"总时长 vs 硬切路径，确认没有为了消黑屏反而让广告晚了一大截。
- [ ] `delay: 3s` + 默认等待：确认实际接管时刻是 **max(倒计时走完, 广告就绪)**，两个条件都满足才切。
- [ ] 逐帧确认 `pauseWhenReady` 生效：广告是从**素材第 0 帧**开始的，不是已经播了一两秒的中段。

*A-3 三层覆盖在真机上确实生效*
- [ ] 单条中插设 `waitForReady: false`，其余中插保持默认：**只有那一条**硬切，其余仍等待。
- [ ] 注入一个自定义 `MovaAdWaitPolicy`（例如"仅 Wi-Fi 下等待"），切换网络类型确认行为随之改变。

**B. 广告加载失败降级路径**
- [ ] 坏 URL（404）+ 默认 `MovaAdRetrySkip()`：广告位被跳过、正片正常续播、`failed` 事件里 `kind == openThrew` 或 `playerError`（看 media_kit 在真机上到底以哪种形式报出来——**这一条很可能与单测里的假设不一致，是本组最值得看的发现点**）。
- [ ] 坏 URL + `MovaAdRetrySkip(maxRetries: 2)`：确认真的重试了两次，且每次重试的用户可感知停顿有多长（决定默认 0 次是否站得住）。
- [ ] 黑洞 URL（连得上但永不返回数据，例如指向一个 sleep 的端点或超大文件的极慢镜像）：确认 `loadTimeout` 真的能救场，而不是卡死在 `open()` 里——**`open()` 在真机上到底会不会永远不返回，决定 `loadTimeout` 这个 Timer 是否够用、还是需要一条更硬的兜底。**
- [ ] 中途断网（广告播到一半拔网）：确认 `MovaErrorEvent` 被收到并走失败策略，而不是静默卡住。
- [ ] `MovaAdAbandonPod()` + 三条前贴片的第一条坏掉：确认后两条**没播**、直接进正片。
- [ ] 弱网下 `waitForAdReady` 超时 + `notReadyAction: dropBreak`：确认正片**完全没有被打断**（逐帧看，不能有一帧卡顿或黑屏）。
- [ ] 同上 + `hardCut`：确认降级为硬切后广告仍能播出（不能出现"既没等到也没切成"的第三种状态）。

**C. delay 倒计时期间正片是否流畅播放**
- [ ] `delay: 5s`、`waitForAdReady` 开启：逐帧录屏确认倒计时全程正片**无掉帧、无卡顿、无音频断续**——这是本批最容易翻车的地方，因为此时正片引擎与广告影子引擎正在同时解码。
- [ ] 同上在中低端机型上重跑（目标：命中硬解并发 session 上限时会发生什么）。若正片在预热期间明显卡顿，结论应是**回写一条"低端机建议关闭 `waitForAdReady`"的文档警告**，或给 `MovaAdConfig` 补一个设备能力门槛旋钮（视实测决定，不预先设计）。
- [ ] 倒计时角标：数字每秒递减、不跳秒、不出现负数、广告接管时立刻消失。
- [ ] 倒计时期间正片手势仍然可用（音量/亮度/进度拖动），确认 pending 阶段没有渲染全屏点击层（Task 9 第 4 项的真机复核）。
- [ ] 三阶段 `dumpsys meminfo`（倒计时开始前 / 倒计时中 / 广告接管后 3 秒）：确认接管后**回落到接近阶段①**。**本条必须在一次完全不发生页面导航的采样里完成**——0.4.0 Task 11 的 B 项就是被一次意外导航污染的，那个"阶段③不回落"的疑点至今未定性，本轮顺带一并查清。

**D. pod 内 delay 只弹一次 / 等待只等一次**
- [ ] 两条同 offset 的中插、两条都配 `delay: 3s`：倒计时角标**只出现一次**，两条广告连续播出，中间**没有**闪回正片、**没有**第二次倒计时。
- [ ] 同上、两条都走默认等待（`delay: 0`）：**只有第一条**经历等待窗口，第二条紧接着播（pod 内部串联走 `_playAd`，不重新进 pending）。逐帧确认两条之间没有正片闪回、没有第二段停顿。
- [ ] 同上确认两条广告各自的 `duration` 独立生效（第一条 8s 被收回、第二条也得到完整 8s）。
- [ ] 三条前贴片 pod：确认连播正常、每条各自计 `duration`、**全程没有任何等待**（默认 `pre: false`）。

**E. `duration` 的真机可靠性（本批最重要的反向验证）**
- [ ] `duration: 8s` + 一条**真实时长 60s 的大文件**广告素材：确认 8 秒准时收回、**播放器没有卡死**、正片正常续播。这一条是在真机上直接检验"不依赖媒体时间轴"这条设计约束是否真的兑现了——如果这里卡死，说明实现里还残留着对 `MovaDone`/`state.duration`/尾部 `seek` 的隐性依赖。
- [ ] `duration: 8s` + 一条**真实时长只有 3s** 的素材：素材先播完（`MovaDone`），确认立刻续播、且 8s 的 timer 到期时**不会**触发第二次续播（`_resuming` 守卫的真机复核）。
- [ ] 真机网络下，`durationFromFirstFrame: true` 的起算点确实是首帧而非 `open()`：在弱网下让广告加载 3 秒才出首帧，确认用户实际看到广告的时长仍是完整的 `duration`。

**F. 回归（全部新特性关闭态）**
- [ ] 全部新旋钮保持默认（`delay: 0`、`duration: null`、`waitForAdReady: const MovaAdWaitByKind()`、`waitForReady: null`）走一遍完整广告 demo：前贴片、中插、pod、跳过、点击上报、无缝回切，逐项确认与 0.4.0 表现一致。**注意默认下中插会等待就绪**，这条不是"关闭态"，是"默认态"——真正的关闭态回归需要显式传 `MovaAdWaitByKind(mid: false)` 单独走一遍。
- [ ] `load(MovaSource)`（非 deferred）路径确认无任何额外延迟。

**G. 结论回写**
- [ ] A 组的延迟分布 → 回写 `adReadyTimeout` 默认值与 `MovaAdBreak.delay` 的文档建议值。
- [ ] B 组的 `open()` 失败形态 → 回写 `MovaAdFailKind` 各值在真机上的实际触发条件到 dartdoc。
- [ ] C 组的双引擎并发表现 → 决定是否需要给 `waitForAdReady` 补一条设备能力警告或门槛。
- [ ] E 组若发现 `duration` 仍受素材影响 → 回到 Task 5 重新定位隐性依赖。
- [ ] **以上任一组未达精度即不得回写默认值**，照 0.4.0 Task 11 的写法如实记录"未能按原定精度验证"，不编造数字。

---

**决策与结论摘要：** 本次**不新建任何预热机制**——`MovaWarmTrigger`/`MovaWarmPolicy` **零改动**直接复用（ad→content 用 `MovaLeadWarm`，content→ad 用 `MovaEagerWarm` + `target: 0` 的 `MovaBufferWarm`），`MovaSwapCtl` 的 `prepare`/`commit`/`abandon`/`swapTo` 四个动词**语义已足够、不新增方法**，唯一的接口增量是给 `prepare` 加一个可选具名参数 `MovaWarmPlan plan`。**"是否等广告就绪才切入"落成 `MovaAdWaitPolicy` + 内置 `MovaAdWaitByKind`**——判据是"等待的价值等于等待期间屏幕上那张画面的价值"：默认 `pre` 否 / `mid` 是 / `post` 否，三层覆盖（`MovaAdBreak.waitForReady` > 注入策略 > 按 kind 默认）全部收在 `MovaAdConfig.waitsFor()` 一处，控制器里不许出现任何 `kind` 判断分支。前/后贴片走 `swapTo` 一次式路径，中插走 `prepare`+`commit` 两段式路径——这进一步印证了 `MovaSwapCtl` 四个动词各自的适用场景，不需要新方法。"等待"与"`delay` 倒计时"被拆成两件独立的事：中插的默认形态是 `delay == 0` 的**无角标**后台等待。顺带修掉 0.4.0 两处潜伏缺陷（注入的判据从不 `reset()`、`at == 0` 仍下发无谓 `seek(0)`）与"中插 pod 今天根本没串联、会闪回正片"的既有缺陷。`delay`/`duration` 一律 `Timer` 驱动、走 `skip()` 那条已在真机验证过的同步续播路径，绝不碰媒体时间轴；`duration < skippableAfter` 用 `const` 构造器里的 `assert`（编译期失败、release 零成本）挡住。**共拆 12 个 Task**，测试从 **536** 推进到 **654**，外加真机 checklist 七组（A 组按 pre/mid 拆成 A-1/A-2/A-3 分别验证，因为两者默认行为不同）。

**风险最大**：中插默认等待意味着双活解码窗口在默认配置下就会出现，中低端机能否扛住只能真机定（Task 12-C）。**工作量最大**：Task 6–8，`MovaAdCtrl` 从三态变四态、叠加三条独立定时器与重入守卫，外加本次追加的三层等待策略解析。
