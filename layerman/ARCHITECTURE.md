# Layerman 架构文档

本文按 `lib/` 当前代码、`.claude/skills/layerman/SKILL.md` 校准，行为口径为 1.0.0。
第 15 节如实列出未做项、功能缺口与有意的决定，不代表现有 API。

## 1. 定位

headless 弹层队列编排器：只决定「何时、哪个」弹层显示，自己不拥有 `Overlay`，
不碰 widget 树。渲染完全交给调用方传入的 `present:` 后端（`showDialog`、GetX、
`bot_toast`、自管 `OverlayEntry` 都行），调度权归本包，渲染权归后端。
`open<T>()` 返回 `Future<T?>`，用法对齐 `showDialog`。

依赖面：核心只用 `dart:async`、`dart:convert` 、`package:flutter/foundation.dart` 和 `package:flutter/scheduler.dart`
（`ChangeNotifier`、`FlutterError`、`SchedulerBinding`）。路由观察者与生命周期绑定依赖 `package:flutter/widgets.dart`，路由 presenter 依赖 Material。
主包零第三方运行时依赖。

## 2. 文件结构与导出

```text
lib/layerman.dart                        公开入口，只导出下列符号
lib/src/overlay_manager.dart             引擎：Layerman、OverlayTicket、OverlayHold 及内部状态
lib/src/overlay_types.dart               模式、路由匹配、阶段、冷却快照、原因、结果、事件、槽位配置
lib/src/fake_clock.dart                  FakeOverlayClock（lib/testing.dart 导出）
lib/src/route_managers.dart              DialogManager / BottomSheetManager / presentRoute
lib/src/lifecycle_binding.dart           LayermanLifecycle
lib/src/overlay_navigator_observer.dart  LayermanNavigatorObserver
test/layerman_test.dart                  单测主体
test/robustness_test.dart                0.2.2 加固回归（类型校验、hydrate 门控、守卫去重等）
test/readme_recipe_test.dart             历史手写 Route 配方回归
test/engine_v030_test.dart               冷却耗尽、超时、接管、数据、观测回归
test/engine_v030b_test.dart              票据、事件、holds、过期、槽位配置
test/engine_v030c_test.dart              build 推迟、批量通知、slot 回收、冷却重置、标签
test/api_v1_test.dart                   1.0 类型契约
test/fuzz_invariants_test.dart          随机序列不变量与 dismiss 去重回归
test/observer_filter_test.dart          PageRoute 过滤与 contextKey
test/route_managers_test.dart           Route presenter 定向关闭与配置
test/lifecycle_binding_test.dart        生命周期暂停绑定
example/                                Android / Windows 示例与手机集成测试
ARCHITECTURE.md / ARCHITECTURE.svg       本文与架构图
```

导出符号：`Layerman`、`OverlayPredicate`、`OverlayCooldown`、`OverlayCooldownStorage`、
`MemoryCooldownStorage`、`OverlayRecord`、`PresentContext`、`PresentedOverlay`、
`Present`、`LayermanNavigatorObserver`、`OverlayTicket`、`OverlayHold`、
`OverlayEndReason`、`OverlayOutcome`、`OverlayEvent`、`OverlayEventType`、`OverlaySlotOptions`、
`DialogManager`、`BottomSheetManager`、`presentRoute`、`LayermanLifecycle`、
`OverlayClock`、`OverlayMode`、`RouteMatcher`、`OverlayPhase`、`OverlayCooldownStatus`。
测试入口 `package:layerman/testing.dart` 单独导出 `FakeOverlayClock`。

`_Entry`、`_Slot`、`_CooldownStore`、`_CooldownRecord` 均为库私有。

## 3. 核心状态

全部在 `Layerman` 实例内：

- `_slots`：`Map<String, _Slot>`，默认槽位名 `''`。每个 `_Slot` 含 `active`（0 或 1 个占位者）、
  `queue`、`gapTimer` / `delayTimer` / `cooldownTimer` 三个计时器、`gapPending`、同 id 优先接管 `takeover`、确实等待跨槽解除的 `waitingUnblock`。
- `_overlaps`：`mode: OverlayMode.overlap` 的并发栈，不占串行 active，但计入 blockedBy 占用。
- `_pendingOverlaps`：暂停期间、等待冷却存储 hydrate 或被 blockedBy 阻塞时被挂起的 overlap。
- `_delayedOverlaps`：等待独立 `overlapDelayTimer` 的 overlap，不占串行槽位。
- `_byId`：id 到条目的映射，**唯一事实来源**。异步回调一律用 `_isCurrent(e)`
  （`_byId[e.id] == e`）判断条目是否仍有效。
- `_context`：`setContext` 合并出的条件上下文。
- 三个暂停来源：`_manualPaused`（`pauseAll` / `resumeAll`）与 `_routeZonePaused`
  （`pauseOnRoutes`），以及 `_holds` 中未释放的独立暂停凭证，有效状态 `_paused` 是三者的 OR。
- `slots`：不可变的 `Map<String, OverlaySlotOptions>`，按槽覆盖全局 `gap`，可限制 `maxQueued`，并用 `blockedBy` 指定激活阻塞来源。
- `submit<T>` 返回绑定单次 `_Entry` 身份的 `OverlayTicket<T>`，含结果与 outcome 两个 Future；
  `open<T>` 委托 `submit<T>(...).result`。`_events` 异步广播 queued/shown/ended。
- `_CooldownStore`：冷却计数及 `_CooldownRecord.suppressedUntilMs`（JSON `su`）；`ready()` 返回 hydrate Future。
- `_blockedByOf` 保存阻塞来源的不可变副本，`_blockerSlots` / `_blockableSlots` 分别索引来源 / 被阻塞槽；
  `_unblockPending` 标记本批次释放过来源，批次末尾统一处理。
- `_hydrationApplied` 表示 manager 的 hydrate 续体已应用，区别于 store 刚读完、清理还未执行的微任务窗口。

只读观测：`activeIds`（open 或 closing）、`queuedIds`（含挂起的 overlap）、`isShowing(id)`、
`isPaused`、`currentRoute`、`isDisposed`、`holdCount`；`resolvingIds` 补充解析中条目，
`records` 覆盖全部阶段，`recordOf(id)` 返回快照或 null。`queuedIds` 按槽内真实出场顺序返回，
后接挂起的 overlap，不承诺槽位间的全局顺序。`Layerman` 继承 `ChangeNotifier`，
状态变化后通知监听者。

## 4. 条目生命周期

`OverlayPhase`：`pending → resolving → open → closing → 移除`。

| 迁移 | 触发 |
| --- | --- |
| 入队，`pending` | `open()`；串行条目进槽位 `queue`，overlap 条目直接走 overlap 流程 |
| `pending` 等 delay | 队首合格且有 `delay`：起 `delayTimer`，到期再调度（每个条目只消费一次） |
| `pending → resolving` | 被调度占住槽位且带 `resolve`：槽位已承诺，普通后来者只能等；`replace` 仍可抢占并丢弃它 |
| `pending/resolving → open` | 无 `resolve` 直接开；有则 `resolve` 返回非 null。进入 `open` 时调用 `present`、记冷却、起 `duration` 计时 |
| `resolving → 移除` | `resolve` 返回 null 或抛异常：跳过，结果 `null`，**不记冷却** |
| `open → closing` | `close()` 通过守卫、`duration` 到期、后端自己报告 dismissed |
| `closing → 移除` | 后端 dismissed（加 `exitDuration` 宽限）、无法由我们关闭、或 dismiss 同步抛异常 |
| 任意阶段 `→ 移除` | `remove` / `clear` / `clearWhere`、被 `replace` 抢占、同 id 重开、`dismissWhenUnmet`：立即移除，未交付的结果补 `null`，仍在显示的后端被尽力 dismiss，不等 `dismissed` |

结束原因（`OverlayEndReason`）：

| 原因 | 触发 |
| --- | --- |
| `closed` | 显式 close / dismiss |
| `dismissedByBackend` | 后端先报告关闭 |
| `expired` | duration 到期 |
| `replaced` | replace 抢占 |
| `superseded` | 同 id 新提交覆盖 |
| `removed` | remove / clear / clearWhere |
| `unmet` | dismissWhenUnmet 条件失效 |
| `skipped` | resolve 空值、异常或超时 |
| `dropped` | overlap 不满足条件或可恢复冷却 |
| `capped` | session / total 永久上限耗尽 |
| `suppressed` | 带 cooldown 的条目因抑制结束 |
| `queueFull` | maxQueued 超限淘汰有序队尾 |
| `queueExpired` | expireAfter 到期 |
| `failed` | present 同步抛异常 |
| `disposed` | manager 销毁 |

结果只交付一次：`_settle` 用 `settled` 标记保证 `open()` 的 Future 只完成一次，
`close` 的结果或后端 dismissed 的值先到者生效，之后的移除不会覆盖首次值与原因。`_settle(e, result, reason)` 必须带原因，
首次兑现同时完成 `result` / `outcome` 并发 `ended`；不代表退场动画已经结束。关闭超时也不改写首次原因。

`OverlayRecord.phase` 是 `OverlayPhase` 枚举：`pending` / `resolving` / `open` / `closing`，不再暴露字符串。
`mode` 默认 `OverlayMode.queue`，可选 `replace` / `overlap`；二者不能组合，`affix` 独立。
内部仍以不可变的 `replace` 字段参与排序，以 overlap 集合表示并发条目。

## 5. 调度

### 5.1 排序

`_cmp`：`replace` 条目排在最前（replace 前排带），其次 `priority` 降序，最后 `seq` 先进先出。`_enqueue` 二分定位有序插入，调度不再反复排序。
`replace` 是条目的不可变字段，保证被 `affix` 挡住而排队的抢占者，仍排在先到的普通项前面。

### 5.2 资格

资格 = 条件 + 冷却（再加 hydrate 门控）。

- 条件：`route` / `auth` / `when` 按 AND 短路组合，未提供则通过。
  `route`（`RouteMatcher?`）读取 `_context['route']`；`auth` 与 `when` 都是
  `OverlayPredicate?`，读取 `setContext` 提供的任意键，引擎不读取保留键 auth。
- 冷却：`_CooldownStore` 逐项检查，见第 9 节。
- hydrate 门控：存储读取完成前，**任何带 `cooldown` 的提交**都视为「暂不满足」，包括只有
  session 或空 `const OverlayCooldown()`；抑制持久化且对它们均生效。不带 cooldown 的不受影响。
  hydrate 完成后统一重调度。
  串行条目排队等待；overlap 条目被挂起，而不是丢弃。

### 5.3 不满足怎么办

- 串行条目：可恢复的不满足**等待**；提交时检查 `permanentlyBlocked`（session / total 耗尽或永久抑制），
  立即结束为 null / capped 或 suppressed；hydrate 完成后扫描所有串行队列清理永久受阻项，不受暂停或 slot 占用阻挡。
  调度扫描也保留检查。hydrate 前不据尚未读到的 total 判定永久受阻。
- overlap 条目：**丢弃**（结果 `null`），即「现在或永不」。初次资格通过后，暂停、等 hydrate 或 blockedBy 阻塞时改为挂起，释放时重判。
- 时间型冷却（限时抑制、`minGap`、day/hour/minute 桶滚动）会自唤醒：`_schedule` 找不到合格项时，
  对最近到期者起 `cooldownTimer`，到点（多留 16ms）重新调度。`session` / `total` 不会自己到期，
  不唤醒，提交 / hydrate / 调度检查时丢弃。

### 5.4 调度流程 `_schedule(slot)`

暂停则返回；取消旧 `cooldownTimer`；槽位被占、`gapPending`、`delayTimer` 在走、队列为空则返回；
随后检查 `_slotBlocked(slot)`，若阻塞则置 `waitingUnblock = true` 并返回；
通过后先消费合格 `takeover`，否则从有序队列扫描并丢弃永久受阻项，取第一个合格项；它有 `delay` 且未跳过则起 `delayTimer` 并返回；否则 `_activate`。

间隔：关闭一个串行条目后 `_advanceSlot`，若 `slots[slot]?.gap ?? gap` 大于零 则置 `gapPending` 并起
`gapTimer`，到期再调度。条目自己的 `delay` 在它出场前再等一次，overlap 也遵守 `delay`：先进入 `_delayedOverlaps` 等待，
到点移出后执行一次性资格判定；remove / clear / 同 id 重开 / dispose 均取消等待。

### 5.5 replace 抢占

`open(mode: OverlayMode.replace)` 仅当自身满足资格、管理器未暂停且本 slot 未被 blockedBy 阻塞时才抢占；当前项 `affix` 则不抢占，
抢占者留在队列前排带，等当前项走后显示。抢占时：

- 被抢占者直接关闭（`_discardActive`：结果 `null`、尽力 dismiss 后端），**不回队列**，
  因为已被 dismiss 的后端无法如实重新 present；
- 取消 `gapTimer`、`delayTimer`，跳过间隔和延迟，立即显示。

### 5.6 同 id 重开

`open` 复用一个活跃 id：旧项被丢弃（结果 `null` / superseded），新项 `skipGap`。
若仍在同一串行槽、未暂停且合格，新项直接 `_activate` 接管，不让更高优先级排队项抢走。
若被阻塞或在 build 期间，合格且未暂停的同槽新项由 `takeover` 保留接管权，解除后先于其他排队项。
跨槽或转 overlap 时原槽重调度；不满足接管条件时正常排队。
复用一个仍排队的 id：覆盖旧排队项。`affix` 不拦同 id 重开。

### 5.7 排队期限与容量

`expireAfter` 提交时起 `queueTimer`，只适用于激活前串行等待（含暂停），激活取消；
到期移除并给出 queueExpired。`maxQueued` 必须正数，只计算等待项，入队后超限淘汰
有序队尾（queueFull），可能淘汰本次提交。`OverlaySlotOptions.gap` 覆盖全局间隔。

### 5.8 跨 slot 阻塞

`OverlaySlotOptions.blockedBy` 为 `Set<String>`，默认空。`_slotBlocked` 仅看来源 slot 的
`active != null`（resolving / open / closing，含 exitDuration 宽限），或 `_overlaps` 中该 slot 的条目。
gap、appear delay、cooldown 等待、排队、等待中的 overlap 都不算占用；不存在的 slot 名无效果。
构造时复制阻塞集合，自阻塞触发 debug 断言；环按先激活者占用，不保证公平。

阻塞只拦新激活，不关闭或暂停已激活条目，duration 继续走。串行排队仍受 expireAfter / maxQueued
约束；replace 阻塞时不抢占，解除后按最前排带出场；同 id 重开按 5.6 保留合格接管权。
`_admitOverlap` 先检查条件与冷却，再将合格但被阻塞的项放入 `_pendingOverlaps`；
`_releaseOverlap` 在仍暂停、等 hydrate 或受阻时继续持有，否则再做 now-or-never 判定。
解除由最外层批次末尾的 `_releaseUnblocked` 处理，见 13.1。

## 6. 两阶段关闭

```text
close(id, result)
  → 校验 result 类型（不符抛 ArgumentError，条目状态不变）
  → beforeClose 守卫（false/抛异常取消；异步未决期间同条目的重复 close 被忽略）
  → _doClose：停 duration 计时 → settle 结果 → phase = OverlayPhase.closing → _notify（批次结束合并通知）
  → 后端 dismiss(result)
  → 后端 dismissed 触发 _onExternalDismissed
  → exitDuration 宽限（可选）
  → _remove → 按 gap 推进槽位
```

请求后端关闭后启动 `dismissTimeout`（默认 10 秒，构造参数 null 不限时）；
未收到 dismissed 时上报 `TimeoutException` 并 `_remove` 释放槽位，保留已兑现结果和原因。
这不保证后端 UI 消失。正常 dismissed、移除、接管、clear、dispose 都取消相关计时器。

异步守卫返回时会重新检查条目是否仍在、是否仍是 `open`，因为它在等待期间可能已被移除。

绕过 `beforeClose` 的路径：`remove`、`clear` / `clearWhere`、`duration` 到期（`_autoClose`）、
`dismissWhenUnmet` 触发的移除、被 replace 或同 id 重开顶掉。
守卫只管显式 `close()`（`dismiss(id)` 即 `close(id)`）。

`exitDuration` 的含义是「后端 dismissed 之后的宽限」。路由类后端推荐用 `TransitionRoute.completed`
作 `dismissed`：它在退场动画**结束**后才带着 pop 结果完成，不需要 `exitDuration`；`showDialog` /
`Navigator.push` 返回的 Future 在退场动画**开始**时就完成。`exitDuration` 留给没有「动画结束」信号的后端。

## 7. present 协议

```dart
final f = layerman.open<bool>(
  id: 'promo',
  present: (PresentContext<bool> ctx) {
    final c = Completer<bool?>();
    // 展示 UI，用户操作或 dismiss 时 c.complete(...)
    return PresentedOverlay<bool>(
      dismissed: c.future,
      dismiss: ([r]) async { /* 只关掉这一个 */ },
    );
  },
);
```

- `PresentContext<T>`：`id`、`slot`、`data`、`dataListenable`。后者为实时 `ValueListenable<Object?>`，
  `update` Map 浅合并或替换后通知；`OverlayTicket.data` 为同一通道。条目结束不 dispose 通道，
  以便后端退场时仍可解除监听；后端自行移除其注册的监听者。`data` 是 present 那一刻的**快照**（`resolve` 之后的值）。
- `PresentedOverlay.dismissed`：必须覆盖**所有**关闭路径（点击、蒙层、返回键、超时、程序关闭）；
  它的值成为 `open()` 的结果。出错按 `null` 处理。
- `PresentedOverlay.dismiss`：编排器驱动的关闭，必须**定点**关这一个（保存的 Route 对象：在栈顶就 `pop`，
  被盖住就 `removeRoute`；`SnackbarController.close()`；`bot_toast` 的 `CancelFunc`），不能「弹栈顶」。
  按路由名 `popUntil` 在目标不在栈顶时什么也不做，会导致关闭失效；0.3.0 看门狗能释放槽位，但不能保证该后端 UI 已移除。
  传 `null` 则编排器无法抢占它，`close` 只把它从队列摘掉，后端自管生命周期。
- 后端异常隔离：`present` 同步抛异常则上报、丢弃条目（结果 `null`、不记冷却）、队列继续；
  `dismiss` 同步抛或异步失败只上报，不外抛。
- `externalDone` 防止已移除条目的晚到 dismissed 信号再次驱动移除。
- `dismissRequested` 在请求后端 dismiss **之前**置位，所有关闭路径共用该标记，
  每个条目最多请求一次，包括同步抛错、异步失败以及 close 后的 remove / clear / dismiss 超时。
  随机序列测试发现原实现会重复请求，令 `popUntil` / `Get.back()` 等非幂等后端误关其他弹层；
  该修复不替代后端定点关闭的契约。

`route_managers.dart` 提供可全局复用的 `DialogManager` / `BottomSheetManager`，只保存配置。
`presentRoute<T>(NavigatorState navigator, TransitionRoute<T> route)` 推入并保留 Route，
`dismissed` 使用 completed，栈顶 pop(result)，被覆盖则 removeRoute(route)。后者不传 result，
兼容 Flutter 3.27；直接关闭句柄的被覆盖路由结果 null，manager.close 已先交付指定结果。
builder close 总是经 ctx.close 走守卫；返回键、遮罩等始终走后端路径。

`PresentContext<T>.close([T? result])` 绑定本次提交的 `_Entry` 身份，先确认仍是当前且
处于 open，再经 `beforeClose`；旧上下文不能关闭同 id 的新条目。DialogManager /
BottomSheetManager 的 builder close 直接使用 ctx.close，不再接受 manager 参数。
present 内同步 close 时，返回后的后端句柄仍须清理，且不能启动 duration。
后端自行 dismissed 进入 exitDuration 宽限时立即取消 duration。

## 8. 条件与上下文

`setContext(partial)` 的顺序：

1. 合并进 `_context`；
2. 更新免打扰区（`_updateRouteZone`，见第 10 节）；
3. 对已显示且 `dismissWhenUnmet`（默认 true）而条件不再满足的条目执行 `_remove`；
4. 对每个槽位重调度；
5. `_notify()` 登记批次结束后的通知。

保留键只有 `route`；`auth` / `when` 可读取任意业务键。
`auth` / `when` 收到缓存的不可变上下文视图，每次 `setContext` 后失效重建。`currentRoute` 读回 `_context['route']`。

`auth` / `when` 抛异常视为不满足，并上报（每个条目只报一次）。

### 8.1 类型化路由匹配

`route` 接受 `RouteMatcher?`（默认 null），`pauseOnRoutes` 接受 `List<RouteMatcher>`（默认空列表）。
`const RouteMatcher.exact(path)` 精确比较，`const RouteMatcher.anyOf(paths)` 匹配任一路径，
`RouteMatcher.regex(pattern)` 调用 RegExp.hasMatch；`matches(Object? route)` 对 null 或非字符串返回 false。
`anyOf` 不复制传入列表，调用方不得修改列表。`route`、`auth`、`when` 始终按 AND 组合。

## 9. 冷却

`OverlayCooldown` 的各字段按 AND 组合，**真实打开时**才计数：

| 字段 | 语义 | 持久化 |
| --- | --- | --- |
| `session` | 本管理器实例内最多 N 次 | 否，只在内存 |
| `total` | 历史累计最多 N 次 | 是 |
| `day` / `hour` / `minute` | 每个**本地日历**日 / 小时 / 分钟最多 N 次 | 是 |
| `minGap` | 距上次打开的滚动最小间隔 | 是 |

- 必须配合显式 `id`（debug 下断言），因为计数按 id 记，自动 id 每次都变。
- 存储协议：`OverlayCooldownStorage.read(key)` / `write(key, value)`，在构造参数
  `storageKey`（默认 `layerman:cooldown`）下存**一个** JSON 字符串，按 id 分记录。
  默认 `MemoryCooldownStorage`，真实应用接 `shared_preferences` 一类的实现（主包不依赖）。
- hydrate：构造时触发读取；完成前所有带 cooldown 的条目自动等待（含 session-only / 空配置）（见 5.2），完成后统一重调度，
  `ready()` 在重调度之后完成，所以 open 前不必先 await。存储损坏或不可用时上报并退化为空计数。
  hydrate 与已有计数**合并**而非覆盖；写入串行化（同一时刻最多一次在途写入，结束后补写最新快照），
  失败会上报，不影响调度。
- 构造参数 `clock` 注入同源时间与计时器，便于测试。

### 9.1 查询与重置

`cooldownStatus(String id, OverlayCooldown cooldown)` 不增加计数，返回 `OverlayCooldownStatus`：
`canShow` 为全部上限通过，`permanentlyBlocked` 为 session / total 耗尽或永久抑制；`wait` 在通过时为
Duration.zero，时间冷却时取最长剩余等待，永久受阻或等待持久化 hydrate 时为 null。
`suppressed` 表示当前存在有效抑制。hydrate 前 `canShow: false, wait: null`，但
permanentlyBlocked / suppressed 按内存已知状态给出（session 耗尽、本会话永久抑制仍可识别）。
`resetCooldown(String id)` / `clearCooldowns()` 同时清除 session、持久化计数及抑制，复用串行写入；
hydrate 未结束的重置也保留，旧存储不能将清掉的计数带回。重置后未暂停则重新调度，
暂停期间仍保持冻结；已结束的 capped / suppressed 条目不会复活。

### 9.2 按结果抑制

`Layerman.suppress(String id, {Duration? duration})`：null 永久，非 null 必须为正，从 clock.now()
起计算到期时间。只门控带 cooldown 的提交，手动不带 cooldown 的打开与已激活条目不受影响。
空 `const OverlayCooldown()` 不限次数，只接受抑制。调用方可按结果在关闭后调用 suppress。

抑制复用 `_CooldownRecord.suppressedUntilMs` / JSON `su`，永久用 `_suppressForeverMs` 哨兵；
重复调用与 hydrate 合并都取更晚时间，永久优先，只延长不缩短。原因是“任何关闭抑制三天，
不再提示抑制永久”的先后顺序不应影响结果。reset 会连同计数一起清除，hydrate 前的重置也保留。
永久抑制立即清理该 id 的排队串行项，即使暂停、slot 占用、hydrate 未完成也以 suppressed 结束。
限时抑制保留串行等待并自唤醒；wait 取抑制剩余与其他时间型限制的最大值。
永久抑制时 permanentlyBlocked 为 true，wait 为 null；永久上限或 hydrate 门控也使 wait 为 null。

overlap 在 delay 到点或释放时判断，抑制中丢弃。`_dropReason` 的冷却拒绝优先级是
suppressed > capped > dropped；`_admitOverlap` 的条件失败路径直接给 dropped，不调用该优先级判断。

### 9.3 时间与计时器

`Layerman(clock: OverlayClock.system)` 是默认时间源。所有时间读取经 `clock.now()`，
所有计时器经 `clock.createTimer(...)`，包括 slot 的 gap / delay / cooldown，以及条目的
排队过期、overlap delay、解析超时、关闭超时、duration、退场宽限。
`package:layerman/testing.dart` 导出 `FakeOverlayClock([DateTime? start])`，默认 DateTime(2000)，
`advance(Duration d)` 推进时间并触发窗口内计时器；`pendingTimers` 检查未取消计时器。
可用普通 Dart test() 测引擎而无需 Flutter 绑定，Future 续体需另行排空。

## 10. 暂停

三个来源，按 OR 组合，互不覆盖：

- 手动：`pauseAll()` / `resumeAll()`。
- 免打扰区：构造参数 `pauseOnRoutes`（`List<RouteMatcher>`，默认空列表），每次 `setContext`
  后比对 `route`。

- holds：`hold([Object? reason])` 返回 `OverlayHold`，`release()` 幂等，`holdCount` 只统计 holds。
  所有 holds 释放且手动/路由来源也都放开才恢复。销毁后 token 标为已释放。
- `LayermanLifecycle(manager, pauseOn: ...)` 通过 hold 接入生命周期，不是第四种暂停位；
  默认 paused / hidden 获取，其他状态释放。attach 立即同步且幂等，detach 解除监听并释放；
  更换 manager 前 detach。只冻结 duration，不冻结 queue/resolve/dismiss 截止计时。

只有**有效**暂停状态发生边沿变化时才执行冻结或释放（`_applyPauseTransition`），所以在区内手动
`resumeAll` 不会提前放行，离开区也不会撤销手动暂停。

- 冻结（`_applyFreeze`）：取消各槽位冷却唤醒计时，冻住所有 `duration` 并记下剩余时间。此后不新激活
  任何条目（串行、overlap、replace 都不行）；显式 `close` / `remove` / `clear` 仍可用。
- 释放（`_applyRelease`）：挂起的 overlap 重判资格后打开或丢弃（仍在等 hydrate 的继续挂起）；暂停期间返回的 `resolve` 数据
  （`hasHeldData`）直接打开，不重跑 resolver；解冻 `duration`；重调度所有槽位。

按 id：`pause(id)` / `resume(id)` 只冻结 / 恢复单个条目的 `duration` 倒计时，条目保持显示。

## 11. 路由感知

`LayermanNavigatorObserver(manager, {pathOf, routeFilter, contextKey})` 只重写 `didChangeTop`，不碰旧的
`didPush` / `didPop` / `didRemove` / `didReplace`：后两者报告的是「变动位置」的路由，
不一定是真正的栈顶。`didChangeTop` 还覆盖冷启动和声明式 `Navigator(pages:)`（go_router 的模型）。

默认 `routeFilter` 只接受 PageRoute；拒绝时不取路径、不安排回调，保留最近页面上下文。
`routeFilter: (r) => true` 恢复 0.2.x 所有路由行为。`contextKey` 默认 route；嵌套导航可改为
其他键并用 when 读取；route 条件和 pauseOnRoutes 仍只识别默认 route 键。

流程：`isDisposed` 检查 → `routeFilter(topRoute)` → `pathOf(topRoute)`（默认 `route.settings.name`；抛异常则
`FlutterError.reportError` 并按 `null` 处理）→ 注册 post-frame 回调 → 立刻 `scheduleFrame()`
（否则静止帧下回调可能一直挂着）→ 回调内再查一次 `isDisposed`，然后
`manager.setContext({contextKey: path})`。延后到帧后是因为某些路由器会在 build 期间触发，
同步 `setContext` 会引发 `markNeedsBuild during build`。

接入后把它当作 `route` 键的唯一写者。两个易踩点：

- `MaterialApp.home` 的隐式路由名是 `'/'`，不是 `null`，也不是你想的 `'/home'`；要用别的名字就走
  `initialRoute` / `routes` 或带名字的 `RouteSettings`。
- 对话框、底部弹层、菜单默认被过滤，不再改写页面 route；放开过滤后自行承担弹窗路径参与条件的影响。

## 12. 错误隔离一览

| 用户回调 | 抛异常时 |
| --- | --- |
| `present` | 上报（`FlutterError.reportError`，library `layerman`）；丢弃条目，结果 `null`，不记冷却，队列继续 |
| `PresentedOverlay.dismiss` | 同步抛或异步失败：上报；同步失败后不再重复请求该后端 |
| `PresentedOverlay.dismissed` | 报错按 `null` 结果处理 |
| `resolve` | 视为返回 `null`，跳过该条目，不记冷却 |
| `beforeClose` | 抛异常或返回的 Future 出错：取消本次关闭 |
| `auth` / `when` | 视为不满足，上报（每个条目一次） |
| `OverlayCooldownStorage` | 读失败上报并退化为空计数；写失败上报，不影响调度 |
| resolve 超时 | 默认 30 秒，上报 TimeoutException；按 skipped 跳过且不计冷却，晚到结果忽略 |
| dismiss 超时 | 默认 10 秒，上报 TimeoutException 并释放槽位；首次结果/原因保留 |
| `pathOf` | 上报，该路由按 `null` 处理 |

`close(id, result)` 的 `result` 类型不符是调用方错误，直接抛 `ArgumentError`，条目状态不变。

构造 `resolveTimeout: null` 不限时；单条 `open` / `submit` 的 resolveTimeout 为 null 则继承，
Duration.zero 则关闭该条超时。构造时零时长表示立即超时。超时不取消底层 Future。

`dispose` 之后：`open` 在 debug 下断言，release 下返回 `null` 且不 present；
其余写操作为无操作。

## 13. 扩展点

- **Present 适配器**：`present:` 回调本身，按 `showDialog` / GetX / `bot_toast` / 自管
  `OverlayEntry` 各写一个适配（README 有配方）。
- **`OverlayCooldownStorage`**：接任意持久层。
- **`when` 谓词**（`OverlayPredicate`）：读 `setContext` 的任意键做条件。
- **`pathOf`**：观察者从非 `settings.name` 的地方取路径。
- **`ChangeNotifier` 监听**：状态变化后读 `activeIds` / `queuedIds` / `isPaused` 刷新 UI；
  `update(id, patch)` 也走这个通知。

### 13.1 批量通知与 build 期间推迟

公开操作、票据关闭/移除及异步状态续体进入 `_batch`，嵌套调用增加 `_batchDepth`；
内部状态变更统一调用 `_notify`，批次内只设置 `_notifyPending`。最外层结束先调用
`_releaseUnblocked`，再回收空槽，再在 assert 中调用 `debugCheckInvariants()`，最后统一通知。
所以一次公开操作最多触发一次管理器通知，监听者不会看到该操作中途的状态。
异步续体各自是独立批次；`dataListenable` 的同步值通知和 `events` 的异步广播不受此合并限制。

`_detachFromActive` 只在移走 blocker 时置 `_unblockPending`，不能在此立即调度：replace 在
同一次提交中先摘掉旧项、再激活抢占者，立即释放会让其他 slot 趁暂时空位插队。
`_releaseUnblocked` 等占用稳定后循环处理释放，暂停则等待恢复，build 则推迟帧后。
它只重排 `waitingUnblock` 为真的 slot，以及可释放的受阻 overlap；不能改成对所有 slot 调
`_applyRelease`，也不能重排所有配置了 blockedBy 的 slot。条件是推模式，全量重排会给与本次
解除无关的 slot 增加条件重判触发点，并改变出场时机。

`_inBuildPhase` 检查 `SchedulerBinding` 的 `SchedulerPhase.persistentCallbacks`。
build 期间 `_schedule` 用 `_deferredSlots` 对每个 slot 去重登记 post-frame 调度，
挂起 overlap / 暂停释放通过 `_deferRelease` 与 `_releasePending` 合并帧后处理；
`_notify` 用 `_frameNotifyPending` 推迟管理器通知。帧后再次检查销毁、暂停、条件与 hydrate，
沿用正常调度；同 id 接管由 `_Slot.takeover` 保留优先权。帧后展示的通知可以覆盖同帧待发通知。
`open` 仍立即返回 Future；调用方仍需防止重复 build 反复提交，不要把 build 当一次性事件。
这里针对展示和管理器通知，不承诺所有用户回调或后端 dismiss 都自动推迟。

`debugCheckInvariants()` 核对容器身份、阶段、排序、计时器及销毁状态；失败抛 StateError。
自动检查只在 debug 最外层批次结束执行，也可显式在 release 调用。所有改变状态的路径
必须处于 `_batch` 内，包括计时器、Future 续体、帧后回调和 dispose。

新增 debug 不变量（均在 `debugCheckInvariants` 中）：

- (i) `_hydrationApplied` 为真后，串行队列中带 cooldown 的项不得 permanentlyBlocked
  （session / total 耗尽或永久抑制）。使用 manager 续体标记，避免 store 已 hydrated、
  manager 尚未清理队列的微任务窗口误报。
- (j) 若 `waitingUnblock` 为真且 slot 已不受阻、未暂停、不在 build、无 `_releasePending`，
  且该槽不在 `_deferredSlots` 中，则视为解除后漏调度。
- (k) `_pendingOverlaps` 中，若未暂停、不在 build、无 `_releasePending`、slot 不受阻，
  且 `_hydrationApplied` 为真或条目不带 cooldown，则视为可释放却漏释放。

### 13.2 slot 回收与标签

最外层 `_batch` 退出时，从 `_slots` 删除 active 为空、queue 为空、gapPending 为 false，
且 gapTimer / delayTimer / cooldownTimer 全部为 null 的运行时 slot。有计时器的空 slot
必须保留；回收不修改公开 `slots` 配置，后续可按需重建。`debugSlotCount` 仅供测试观察运行时数量。

`open` / `submit` 的 `Set<String>? tags` 默认 null，提交时复制成只读集合，
经 `OverlayRecord.tags` 查询。`clearTag(String tag)` 复用 `clearWhere`，先移除全部匹配项再推进槽位，
涵盖 pending / resolving / open / closing，绕过 beforeClose，首次结束原因为 removed。

## 14. 已知限制（截至 1.0.0）

- **条件是推模式**：`when` / `auth` 只在 setContext、提交、关闭、暂停释放等调度触发时
  重新判定；闭包捕获的外部状态变化不会自动触发。条件不按时间自唤醒，时间型冷却的唤醒另算。
- **beforeClose 仅拦管理器发起的显式关闭**：包括 close、票据 close 和 ctx.close；后端自身
  的遮罩、返回键、拖动关闭无法被它拦截。remove / clear / duration 到期等强制路径也绕过守卫。
- **expireAfter 仅适用于串行激活前的等待**（含暂停），不限制 overlap 或 active；
  resolveTimeout / dismissTimeout 释放编排状态，但不能取消后端 Future 工作。
- **编排器不拥有 UI 层级与取消能力**：后端须提供定向 dismiss；仅超时移除内部条目，不能保证
  错误后端遗留的 UI 已消失。跨后端 z-order、返回键策略由调用方处理。
- **阻塞只拦激活**：已经出场的条目继续显示，duration 继续计时，不被关闭或暂停。
- **gap / appear delay 不算 blocker 占用**：被阻塞的条目可能在 blocker 的两个条目之间出场。
- **阻塞环不保证公平**：先激活者占用，不提供公平轮转。
- **抑制只约束带 cooldown 的提交**：无 cooldown 的手动打开不受影响。
- **抑制只延长**：缩短只能 reset，而 reset 会连同计数一起清除。
- **限时抑制的串行项持续排队到到期**：可用 expireAfter 限定等待。

## 15. 未做项、功能缺口与有意的决定

### Gate（统一资格判断）——未做

真实原因是工作量：引擎已 2000+ 行，不是“风险大于收益”。这是引擎内部重构，不改变公开 API，
1.x 里随时可以做。风险缓解已有每个批次结束的 debug 不变量断言及随机序列测试，覆盖慢 / 失败
hydrate、build 期间 open、冷却查询重置、标签、overlap delay、auth、ctx.close；这些是安全网，
不能据此声称结构重构已经没有必要。

**功能缺口**：没有业务自定义资格扩展点来表达“等到某时刻再判断”或“永久丢弃并给原因”。
when / auth 只能返回 bool，不会按时间自唤醒。替代写法是用 expireAfter 限定串行等待，
或调用方定时 setContext({}) 推动重新判定。

### 显式状态机与操作串行派发——未做

原因同上，是工作量。部分替代是 `_batch`（一次操作一次管理器通知、监听者看不到操作中间态）
及 debug 不变量断言；它们不是显式状态机或操作串行派发框架。
技术债仍在增长：每条目的隐式状态从评审时的 6 个布尔 + 2 个计时器，增长为当前 `_Entry` 的
**9 个可变布尔 + 6 个计时器**。布尔为 externalDone、dismissRequested、skipGap、delayConsumed、
closeGuardPending、conditionErrorReported、settled、paused、hasHeldData；计时器为 queueTimer、
overlapDelayTimer、dismissTimer、resolveTimer、durationTimer、removeTimer。
此计数不含 3 个只读配置布尔 replace / affix / dismissWhenUnmet、派生 getter 或 slot 的计时器。

### slot 并发数——尚未提供（功能缺口）

每个串行 slot 只能有一个占位者。同 slot 多个同时出场仍只能拆成多个 slot 或用 overlap。
跨 slot 激活互斥已由 blockedBy 提供，见 5.8。

### 冷却记录自动裁剪——未提供，理由成立

持久化记录不保存该 id 用过哪些上限，record() 对任何持久化上限都累加 total；按时间自动删除
会悄悄重置 total 上限。抑制也存在同一条记录里，按时间删除还会悄悄解除“不再提示”。
可行替代是调用方显式开启的裁剪 API（未做）。每次写入仍是整张 JSON 表重写，id 很多时有成本。现有手段是 resetCooldown / clearCooldowns，由调用方明确重置计数。

### 其余未做项（逐项状态）

- 可插拔冷却规则（周 / 月桶）：未做，只有现有固定频次字段。
- 按“真正可见”计数（后端回报已展示）：未做，没有后端可见确认协议。
- 票据上的状态可监听：未做；可用 events 按 id 过滤代替，同 id 重开需调用方区分提交。
- 调试面板（Inspector）：未做；现有 records / recordOf / events 提供原始观测。
- 参数对象 OverlayRequest<T>：未做，仍为 open / submit 命名参数；该名称不是当前 API。
- 观察者同一帧多次导航合并：未做，目前每次 didChangeTop 各自排帧后回调。
- 适配包 layerman_getx：未做，README 仅有适配配方。
- 适配包 layerman_bot_toast：未做，README 仅有适配配方。

### 有意的决定（附理由）

- 不拆 package:layerman/flutter.dart：主入口一并导出依赖 Material 的 presenter；Material 属于
  Flutter SDK，不增加第三方依赖。该独立入口目前不存在。
- setContext 值未变也全量重新判定：setContext({}) 就是“推动重新判定”的手段；
  冷却过期本身不是外部条件的调度触发点（串行时间型冷却另有内部唤醒计时器）。
