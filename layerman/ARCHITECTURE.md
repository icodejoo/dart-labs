# Layerman 架构文档

本文按 `lib/` 当前代码、`.claude/skills/layerman/SKILL.md` 校准，行为口径为 0.2.2。
第 15 节是规划，尚未实现，其中的名字不要当成现有 API。

## 1. 定位

headless 弹层队列编排器：只决定「何时、哪个」弹层显示，自己不拥有 `Overlay`，
不碰 widget 树。渲染完全交给调用方传入的 `present:` 后端（`showDialog`、GetX、
`bot_toast`、自管 `OverlayEntry` 都行），调度权归本包，渲染权归后端。
`open<T>()` 返回 `Future<T?>`，用法对齐 `showDialog`。

依赖面：核心只用 `dart:async`、`dart:convert` 和 `package:flutter/foundation.dart`
（`ChangeNotifier`、`FlutterError`）。只有路由观察者依赖 `package:flutter/widgets.dart`。
主包零第三方运行时依赖。

## 2. 文件结构与导出

```text
lib/layerman.dart                        公开入口，只导出下列符号
lib/src/overlay_manager.dart             引擎：Layerman 及全部内部类型
lib/src/overlay_navigator_observer.dart  LayermanNavigatorObserver
test/layerman_test.dart                  单测主体
test/robustness_test.dart                0.2.2 加固回归（类型校验、hydrate 门控、守卫去重等）
test/readme_recipe_test.dart             README 路由配方回归
example/                                 示例与 Windows 真机集成测试
ARCHITECTURE.md / ARCHITECTURE.svg       本文与架构图
```

导出符号：`Layerman`、`OverlayPredicate`、`OverlayCooldown`、`OverlayCooldownStorage`、
`MemoryCooldownStorage`、`OverlayRecord`、`PresentContext`、`PresentedOverlay`、
`Present`、`LayermanNavigatorObserver`。

`_Entry`、`_Slot`、`_CooldownStore`、`_CooldownRecord`、`_EntryPhase` 均为库私有。

## 3. 核心状态

全部在 `Layerman` 实例内：

- `_slots`：`Map<String, _Slot>`，默认槽位名 `''`。每个 `_Slot` 含 `active`（0 或 1 个占位者）、
  `queue`、`gapTimer` / `delayTimer` / `cooldownTimer` 三个计时器、`gapPending`。
- `_overlaps`：`overlap: true` 的并发栈，不占槽位。
- `_pendingOverlaps`：暂停期间、或等待冷却存储 hydrate 时被挂起的 overlap。
- `_byId`：id 到条目的映射，**唯一事实来源**。异步回调一律用 `_isCurrent(e)`
  （`_byId[e.id] == e`）判断条目是否仍有效。
- `_context`：`setContext` 合并出的条件上下文。
- 两个暂停来源：`_manualPaused`（`pauseAll` / `resumeAll`）与 `_routeZonePaused`
  （`pauseOnRoutes`），有效状态 `_paused` 是两者的 OR。
- `_CooldownStore`：冷却计数；`ready()` 返回的 hydrate Future。

只读观测：`activeIds`（open 或 closing）、`queuedIds`（含挂起的 overlap）、`isShowing(id)`、
`isPaused`、`currentRoute`、`isDisposed`。`Layerman` 继承 `ChangeNotifier`，
状态变化后通知监听者。

## 4. 条目生命周期

`_EntryPhase`：`pending → resolving → open → closing → 移除`。

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

结果只交付一次：`_settle` 用 `settled` 标记保证 `open()` 的 Future 只完成一次，
`close` 的结果或后端 dismissed 的值先到者生效，之后的移除只补 `null`（无效）。

`OverlayRecord.phase` 暴露的是 `pending` / `resolving` / `open` / `closing` 的名字。

## 5. 调度

### 5.1 排序

`_cmp`：`replace` 条目排在最前（replace 前排带），其次 `priority` 降序，最后 `seq` 先进先出。
`replace` 是条目的不可变字段，保证被 `affix` 挡住而排队的抢占者，仍排在先到的普通项前面。

### 5.2 资格

资格 = 条件 + 冷却（再加 hydrate 门控）。

- 条件：给了 `when` 则它是**唯一权威**，`route` / `requiresAuth` 被忽略；否则 `route`
  （`String` / `List<String>` / `RegExp`）匹配 `_context['route']`，且 `requiresAuth` 与
  `_context['auth'] == true` 一致。`requiresAuth: false` 表示「仅游客」。
- 冷却：`_CooldownStore` 逐项检查，见第 9 节。
- hydrate 门控：存储读取完成前，带持久化上限（`total` / `day` / `hour` / `minute` /
  `minGap`）的条目视为「暂不满足」；只有 `session` 上限的条目不受影响。hydrate 完成后统一重调度。
  串行条目排队等待；overlap 条目被挂起，而不是丢弃。

### 5.3 不满足怎么办

- 串行条目：**等待**，留在队列里，下次调度触发再判断。
- overlap 条目：**丢弃**（结果 `null`），即「现在或永不」。暂停期间或等 hydrate 时改为挂起。
- 时间型冷却（`minGap`、day/hour/minute 桶滚动）会自唤醒：`_schedule` 找不到合格项时，
  对最近到期者起 `cooldownTimer`，到点（多留 16ms）重新调度。`session` / `total` 不会自己到期，
  不唤醒，只在 `open` / 关闭 / `setContext` 等调度触发时重判。

### 5.4 调度流程 `_schedule(slot)`

暂停则返回；取消旧 `cooldownTimer`；槽位被占、`gapPending`、`delayTimer` 在走、队列为空则返回；
按 `_cmp` 排序取第一个合格项；它有 `delay` 且未跳过则起 `delayTimer` 并返回；否则 `_activate`。

间隔：关闭一个串行条目后 `_advanceSlot`，若构造参数 `gap > 0` 则置 `gapPending` 并起
`gapTimer`，到期再调度。条目自己的 `delay` 在它出场前再等一次，且 overlap 忽略 `delay`。

### 5.5 replace 抢占

`open(replace: true)` 仅当自身满足资格、管理器未暂停时才抢占；当前项 `affix` 则不抢占，
抢占者留在队列前排带，等当前项走后显示。抢占时：

- 被抢占者直接关闭（`_discardActive`：结果 `null`、尽力 dismiss 后端），**不回队列**，
  因为已被 dismiss 的后端无法如实重新 present；
- 取消 `gapTimer`、`delayTimer`，跳过间隔和延迟，立即显示。

### 5.6 同 id 重开

`open` 复用一个活跃 id：旧项被丢弃（结果 `null`）并释放槽位，新项 `skipGap`。
复用一个仍排队的 id：覆盖旧排队项。`affix` 不拦同 id 重开。

## 6. 两阶段关闭

```text
close(id, result)
  → 校验 result 类型（不符抛 ArgumentError，条目状态不变）
  → beforeClose 守卫（false/抛异常取消；异步未决期间同条目的重复 close 被忽略）
  → _doClose：停 duration 计时 → settle 结果 → phase = closing → notifyListeners
  → 后端 dismiss(result)
  → 后端 dismissed 触发 _onExternalDismissed
  → exitDuration 宽限（可选）
  → _remove → 按 gap 推进槽位
```

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
  present: (PresentContext ctx) {
    final c = Completer<bool?>();
    // 展示 UI，用户操作或 dismiss 时 c.complete(...)
    return PresentedOverlay<bool>(
      dismissed: c.future,
      dismiss: ([r]) async { /* 只关掉这一个 */ },
    );
  },
);
```

- `PresentContext`：`id`、`slot`、`data`。`data` 是 present 那一刻的**快照**（`resolve` 之后的值）。
- `PresentedOverlay.dismissed`：必须覆盖**所有**关闭路径（点击、蒙层、返回键、超时、程序关闭）；
  它的值成为 `open()` 的结果。出错按 `null` 处理。
- `PresentedOverlay.dismiss`：编排器驱动的关闭，必须**定点**关这一个（保存的 Route 对象：在栈顶就 `pop`，
  被盖住就 `removeRoute`；`SnackbarController.close()`；`bot_toast` 的 `CancelFunc`），不能「弹栈顶」。
  按路由名 `popUntil` 在目标不在栈顶时什么也不做，会让条目永远停在 closing。
  传 `null` 则编排器无法抢占它，`close` 只把它从队列摘掉，后端自管生命周期。
- 后端异常隔离：`present` 同步抛异常则上报、丢弃条目（结果 `null`、不记冷却）、队列继续；
  `dismiss` 同步抛或异步失败只上报，不外抛。
- `externalDone`：后端已报告关闭（或已被通知关闭）后置位，晚到的 dismissed 信号不会重复驱动移除。
  对 replace / clear / remove 掉的仍在显示的条目，先置位再尽力 dismiss（fire-and-forget）。

## 8. 条件与上下文

`setContext(partial)` 的顺序：

1. 合并进 `_context`；
2. 更新免打扰区（`_updateRouteZone`，见第 10 节）；
3. 对已显示且 `dismissWhenUnmet`（默认 true）而条件不再满足的条目执行 `_remove`；
4. 对每个槽位重调度；
5. `notifyListeners()`。

保留键：`route`（`String`）和 `auth`（`bool`），其余键给 `when` 谓词自由使用。
`when` 收到的是上下文的不可变副本。`currentRoute` 读回 `_context['route']`。

`when` 抛异常视为不满足，并上报（每个条目只报一次）。

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
- hydrate：构造时触发读取；完成前带持久化上限的条目自动等待（见 5.2），完成后统一重调度，
  `ready()` 在重调度之后完成，所以 open 前不必先 await。存储损坏或不可用时上报并退化为空计数。
  hydrate 与已有计数**合并**而非覆盖；写入串行化（同一时刻最多一次在途写入，结束后补写最新快照），
  失败会上报，不影响调度。
- 构造参数 `now` 可注入时钟，便于测试。

## 10. 暂停

两个来源，按 OR 组合，互不覆盖：

- 手动：`pauseAll()` / `resumeAll()`。
- 免打扰区：构造参数 `pauseOnRoutes`（`String` / `List<String>` / `RegExp`），每次 `setContext`
  后比对 `route`。

只有**有效**暂停状态发生边沿变化时才执行冻结或释放（`_applyPauseTransition`），所以在区内手动
`resumeAll` 不会提前放行，离开区也不会撤销手动暂停。

- 冻结（`_applyFreeze`）：取消各槽位冷却唤醒计时，冻住所有 `duration` 并记下剩余时间。此后不新激活
  任何条目（串行、overlap、replace 都不行）；显式 `close` / `remove` / `clear` 仍可用。
- 释放（`_applyRelease`）：挂起的 overlap 重判资格后打开或丢弃（仍在等 hydrate 的继续挂起）；暂停期间返回的 `resolve` 数据
  （`hasHeldData`）直接打开，不重跑 resolver；解冻 `duration`；重调度所有槽位。

按 id：`pause(id)` / `resume(id)` 只冻结 / 恢复单个条目的 `duration` 倒计时，条目保持显示。

## 11. 路由感知

`LayermanNavigatorObserver(manager, {pathOf})` 只重写 `didChangeTop`，不碰旧的
`didPush` / `didPop` / `didRemove` / `didReplace`：后两者报告的是「变动位置」的路由，
不一定是真正的栈顶。`didChangeTop` 还覆盖冷启动和声明式 `Navigator(pages:)`（go_router 的模型）。

流程：`isDisposed` 检查 → `pathOf(topRoute)`（默认 `route.settings.name`；抛异常则
`FlutterError.reportError` 并按 `null` 处理）→ 注册 post-frame 回调 → 立刻 `scheduleFrame()`
（否则静止帧下回调可能一直挂着）→ 回调内再查一次 `isDisposed`，然后
`manager.setContext({'route': path})`。延后到帧后是因为某些路由器会在 build 期间触发，
同步 `setContext` 会引发 `markNeedsBuild during build`。

接入后把它当作 `route` 键的唯一写者。两个易踩点：

- `MaterialApp.home` 的隐式路由名是 `'/'`，不是 `null`，也不是你想的 `'/home'`；要用别的名字就走
  `initialRoute` / `routes` 或带名字的 `RouteSettings`。
- 同一个 `Navigator` 上的路由型弹窗（`showDialog`、`Get.dialog`）在显示期间确实是栈顶路由，
  `route` 会变成弹窗的路由名。见第 14 节。

## 12. 错误隔离一览

| 用户回调 | 抛异常时 |
| --- | --- |
| `present` | 上报（`FlutterError.reportError`，library `layerman`）；丢弃条目，结果 `null`，不记冷却，队列继续 |
| `PresentedOverlay.dismiss` | 同步抛或异步失败：上报；同步失败后不再重复请求该后端 |
| `PresentedOverlay.dismissed` | 报错按 `null` 结果处理 |
| `resolve` | 视为返回 `null`，跳过该条目，不记冷却 |
| `beforeClose` | 抛异常或返回的 Future 出错：取消本次关闭 |
| `when` | 视为不满足，上报（每个条目一次） |
| `OverlayCooldownStorage` | 读失败上报并退化为空计数；写失败上报，不影响调度 |
| `pathOf` | 上报，该路由按 `null` 处理 |

`close(id, result)` 的 `result` 类型不符是调用方错误，直接抛 `ArgumentError`，条目状态不变。

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

## 14. 已知限制（截至 0.2.2，均经评审实测）

- `session` / `total` 上限耗尽后，条目永远排队，`open` 的 Future 不完成。
- `dismiss` 之后 `dismissed` 不完成，或 `resolve` 不返回，槽位被永久占住，没有超时。
- 弹窗 / 底部弹层路由会改写 `route` 上下文：带 `route` 条件的弹窗可能把自己关掉，
  免打扰区可能被无关弹窗解除。
- 同 id 重开会让位给更高优先级的排队项（重开的条目重新按优先级排）。
- `update()` 的新数据后端读不到：`PresentContext.data` 是 present 时刻的快照，也没有按 id
  读数据的公开 API；后端要显示实时数据，只能自己维护可监听状态并和 `update` 同步更新。
- `resolving` 中的条目不出现在 `activeIds` / `queuedIds`。
- overlap 忽略 `delay`；`requiresAuth: false` 表示「仅游客」，不是「不要求登录」。
- `open` 在 build 期间被调用时会同步 present，可能触发 `markNeedsBuild during build`。

## 15. 演进方向（规划中，尚未实现）

以下**均不是现有 API**，名字可能调整：

- **类型化句柄 `OverlayTicket<T>`**：`close(T?)`、`update`、状态可监听；`open()` 仍返回 `Future<T?>`。
- **统一资格判断 `Gate`**：结果为通过 / 等待到某时刻 / 丢弃并给出原因，取代散落的资格分支。
- **显式状态机 + 公开操作串行派发**：避免监听者重入造成的中间态。
- **自带基于 `Route` 对象的 presenter `DialogManager`**：全局建一次、持有 `navigatorKey`，
  `dismissed` 用 `route.completed`，`dismiss` 用 `removeRoute`，同类的按 `XxxManager`
  命名（如 `BottomSheetManager`）。
- **观察者的 `routeFilter`（默认只看 `PageRoute`）与 `contextKey`**：缓解弹窗路由改写 `route`。
- **进后台自动暂停**。
- **结果原因与事件流**，以及 **dismiss 看门狗与 resolve 超时**（对应第 14 节的永久占槽问题）。
