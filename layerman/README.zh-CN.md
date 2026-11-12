# layerman

[English](README.md) | **简体中文**

**layerman** 是一个 headless（不负责渲染）的浮层队列管理器，统一调度 dialog、
modal、bottom sheet、toast 和 banner。它只决定**什么时候、显示哪一个**浮层，
靠的是带具名 slot、优先级、`replace`、`affix`、`overlap` 的串行队列（一个 slot
同时只显示一个）。它自己从不渲染：每个浮层都由你提供的 `present:` 后端来显示
（`showDialog`、GetX、`bot_toast`、自己管理的 `OverlayEntry` 等）。`open()` 像
`showDialog` 一样返回 `Future<T?>` 结果，关闭分两个阶段，后端可以先播完自己的退场动画。

因为只有 `present:` 这一个适配器，原生 `showDialog`、GetX（`Get.dialog` /
`Get.snackbar`）、`bot_toast`、`fluttertoast` 等不同库渲染的浮层，可以用同一条队列统一管理。

> 设计说明：本包是框架无关的 headless TS 包 `@codejoo/overlaymanager` 的 Flutter
> 版，设计思路也一致：核心不 import `package:flutter/widgets.dart`，也没有自己的
> `Overlay` 层，只保留编排规则。

## 特性

- **不再提示**：按结果调用 `suppress`，永久或限时抑制带 `cooldown` 的提交。
- **跨 slot 阻塞**：`OverlaySlotOptions.blockedBy` 在其他 slot 被占用时，暂不激活新条目。
- **业务资格**：`gate:` 返回 `OverlayVerdict.pass/waitUntil/drop`，用来判断路由、登录之外的激活资格。
- **可见确认**：`PresentedOverlay.visible` 在首帧绘制后完成，`shown` 事件和冷却计数都等它。
- **1.0 类型化选项**：`mode: OverlayMode.queue/replace/overlap`、`RouteMatcher`、`OverlayPhase`，取代含义不清的选项和字符串比较。
- **查询与分组**：`cooldownStatus`（`OverlayCooldownStatus`）、`resetCooldown` / `clearCooldowns`、复制的 `tags` / `clearTag`。
- **帧安全提交**：`build()` 期间调用 `open` 会推迟展示和通知；管理器通知按操作合并；空闲 slot 自动回收。
- **串行队列**：每个 slot 一次只显示一个，当前这个移除后才显示下一个，可以用 `gap` 设间隔。
- **具名 slot**：相互独立、并行运行的多条串行队列（如 `toast` 和 `dialog`）。
- **优先级**：优先级高的先显示，同级先进先出。
- **`replace`**：抢占当前浮层并立即显示（跳过待定的 gap，排在已入队的条目之前）。
  被顶掉的浮层会被**关闭**（结果为 `null`），不会再显示，因为已经被 dismiss 的后端
  无法原样重新呈现。
- **`affix`**：保护当前浮层不被 `replace` 顶掉，被挡住的抢占者在队首等待。
- **`overlap`**：绕过队列，等 `delay` 之后叠加显示（全局告警、阻塞式 loading）。
  条件和冷却只判断一次：此刻不满足就丢弃。
- **条件**：`route`、`auth(ctx)`、`when(ctx)` 三者取 AND，由 `setContext({...})` 驱动。
  已显示的浮层如果条件不再满足，会被自动撤下（`dismissWhenUnmet`，默认 true）；
  排队的条目只是等待。
- **冷却**：`OverlayCooldown(session / total / day / hour / minute / minGap)`。
  设置的上限必须全部满足，浮层确认可见后才计数。通过可插拔的
  `OverlayCooldownStorage` 持久化（默认存在内存，生产环境用 `shared_preferences`）。
  **时间型**上限（`minGap` 和日 / 时 / 分的自然时段滚动）到期后，会自动显示排队的条目。
- **后端驱动 `resolve`**：浮层拿到 slot 后才取数据，返回 `null` 就跳过。取数期间
  slot 保持占用，普通后来者要等，但 `replace` 可以抢占并丢弃取数中的条目。
- **`beforeClose` 守卫**：返回 `false`（同步或异步）可以否决一次 `close()`，比如
  未保存内容的确认。`remove` 和 `clear` 会绕过它。
- **`Future<T?>` 结果**：`open()` 返回的 future 在关闭时以你传入的值完成，被 dismiss 则为 `null`。
- **两阶段关闭**：`close()` 先立即给出结果，再等后端发出 `dismissed` 信号（最长等
  `dismissTimeout`），外加每次 `open()` 可选的 `exitDuration` 宽限，之后队列才继续。
  这样后端能先播完退场动画。
- **`pauseAll` / `resumeAll`**：整体冻结，不再显示新浮层，运行中的 `duration` 倒计时暂停。
  按 id 的 `pause` / `resume` 只冻结一个浮层的倒计时。
- **自动路由感知**：`LayermanNavigatorObserver` 自动把真实导航传给 `route` 条件
  （与 router 无关，原生 Navigator、GetX、go_router 都行）。`pauseOnRoutes` 声明
  “免打扰区”路由：进入时冻结队列，离开时恢复，可以和手动 `pauseAll` / `resumeAll`
  一起用。`currentRoute` 读取当前追踪到的路由。
- **`update(id, patch)`**：向已显示浮层的 `data` 做浅合并并通知监听者，不渲染也不改队列。
  `PresentContext.data` 是 present 时的快照，需要实时值请用 `dataListenable`。
- **`clearWhere(test)`**：按条件批量移除（比如“关闭 X 组的全部浮层”）。
- **每个浮层的 `delay` 和 `duration`**（自动关闭）。
- **外部浮层系统**：一条队列统管 `showDialog`、GetX、`bot_toast`、`fluttertoast`，
  或任何能显示、能关闭的东西。
- **路由 presenter**：可复用的 `DialogManager`、`BottomSheetManager`、`presentRoute`。
- **票据和事件**：类型化的 `submit<T>`、带原因的结果、异步事件流。
- **独立暂停来源**：`hold()` 和自动的 `LayermanLifecycle` 绑定。
- **有界等待**：resolve 和关闭超时、`expireAfter`、每个 slot 的 `gap` / `maxQueued`。
- **实时数据与诊断**：`dataListenable`、`resolvingIds`、`records`、`recordOf`。

## 安装

```yaml
dependencies:
  layerman: ^1.0.0
```

```dart
import 'package:layerman/layerman.dart';
```

主包**没有第三方运行时依赖**，只依赖 Flutter SDK。example 里用到 `get` 和
`bot_toast`，只是为了演示外部适配器。

## 快速开始

`Layerman` 是个普通对象，不挂载任何东西，也不需要在 App 上层包一个 widget。
创建一个，用你项目里已有的共享状态方式持有它（单例、GetX binding、
`Provider`、DI 等都行）：

```dart
final manager = Layerman(gap: const Duration(milliseconds: 300));
```

在调用 `open()` / `close()` 的地方拿到它，并在每次调用时传入 `present:` 后端。
这里不需要挂 scope，也不需要 attach，原因见下一节。另见 [基础用法](#基础用法)。

### 为什么没有 `builder:`

`layerman` 是**队列编排器，不是渲染器**。它只决定*什么时候*、*显示哪一个*浮层，从不持有 widget 或 `Overlay` 层。每个浮层都通过你提供的 `present:` 后端来显示。

早先版本有个 `builder:`，返回一个 `Widget`，由 manager 挂进它自己的 `Overlay`。这样 manager 自己就成了 UI 的一部分：要持有 `OverlayState`，要一直挂在 widget 树上，还得配一个 `OverlayManagerScope`。这和这个包存在的目的相违背。

`present:` 能做 `builder:` 做的所有事。你在里面构造任意 UI（`showDialog`、`Get.dialog`、`BotToast.show`、`Navigator.push`，或者自己插一个 `OverlayEntry`），再返回一个 `PresentedOverlay(visible: ..., dismissed: ..., dismiss: ...)` 句柄。`builder:` 能渲染的内容，自己持有 `OverlayEntry` 的 `present:` 后端同样能渲染，所以没有损失。核心现在是 headless 的（不 import `flutter/widgets`），和 headless 的 TS 兄弟包一致。

```dart
manager.open(present: (ctx) {
  final visible = Completer<void>();
  final done = Completer<String?>();
  final cancel = BotToast.showWidget(
    toastBuilder: (_) => OverlayVisibility(
      visible: visible,
      child: MyCard(onOk: () => done.complete('ok')),
    ),
  );
  done.future.whenComplete(cancel);
  return PresentedOverlay<String>(
    visible: visible.future,
    dismissed: done.future,
    dismiss: ([r]) async {
      cancel();
      if (!done.isCompleted) done.complete(r);
    },
  );
});
```

路由弹窗优先用 `DialogManager`，也可以自己保存 Route 对象：`dismissed` 用 `route.completed`，
关闭时通过该路由自己的 navigator 精确关闭这一条。见下方配方。

## 基础用法

### 共享路由 presenter

在 `manager` 旁边建一次，把同一个 `navigatorKey` 传给应用，等 Navigator 挂载后再调用
`open`。下面的例子都用 `dialogs((ctx, close) => widget)`。

```dart
final navigatorKey = GlobalKey<NavigatorState>();
final dialogs = DialogManager(navigatorKey);
final sheets = BottomSheetManager(navigatorKey);

// Mount this once in your app:
final app = MaterialApp(navigatorKey: navigatorKey, home: const Scaffold());
```

### 打开并等待结果

```dart
final ok = await manager.open<bool>(
  id: 'confirm-delete',
  present: dialogs((ctx, close) => Center(
    child: TextButton(
      onPressed: () => Navigator.pop(navigatorKey.currentContext!, true), // 结果 = true
      child: const Text('删除'),
    ),
  )),
);
if (ok == true) doDelete(); // 点遮罩 dismiss -> ok == null
```

`open()` 立即返回一个 `Future<T?>`。浮层可能马上显示，也可能在队列里等，
future 在浮层最终关闭时完成。

### 从 0.x 迁移

完整清单见 [CHANGELOG 的 1.0.0 迁移表](CHANGELOG.md#100)。最常碰到的几项：

| 0.x | 1.0.0 |
| --- | --- |
| `replace: true` / `overlap: true` | `mode: OverlayMode.replace` / `mode: OverlayMode.overlap`（只能选一个，默认 `queue`） |
| `route: '/home'`、`['/a', '/b']`、`RegExp(...)` | `RouteMatcher.exact` / `anyOf` / `regex`；`pauseOnRoutes` 同理 |
| `requiresAuth: true` | `auth: (ctx) => ctx['auth'] == true`；键名与策略由业务决定 |
| `record.phase == 'open'` | `record.phase == OverlayPhase.open` |
| `Layerman(now: ...)` | `Layerman(clock: ...)`，传 `OverlayClock`（`now()` + `createTimer`）；测试用 `FakeOverlayClock` |
| `PresentedOverlay(dismissed:, dismiss:)` | `visible:` 现在**必填**：首帧真正绘制后再完成。`shown` 事件与冷却计数都只在它成功后发生（见 [`Present` 适配器](#接入其它浮层库present-适配器)）；`presentRoute` 与 `OverlayVisibility` 已替你处理 |
| `DialogManager(key, manager: manager)` | 去掉 `manager:`；builder 的 `close` 统一走 `ctx.close` 与 `beforeClose` |
| overlap 忽略 `delay` | overlap 现在先等 `delay` 再做「现在或永不」的资格判断 |

```dart
// 0.x
manager.open(id: 'expired', replace: true, requiresAuth: true, present: present);
// 1.0.0
manager.open(
  id: 'expired',
  mode: OverlayMode.replace,
  auth: (ctx) => ctx['auth'] == true,
  present: present,
);
```

### 在 `build()` 期间打开浮层（Building overlays during `build()`）

在 `build()` 期间调用 `open`，会自动把 `present` 和管理器通知推迟到这一帧之后，但仍然立即返回 Future。
排队顺序不变，展示前会重新检查暂停、条件和 hydrate。要避免重复 build 造成重复提交：

```dart
class PromoTrigger extends StatefulWidget {
  const PromoTrigger({super.key, required this.manager, required this.present});
  final Layerman manager;
  final Present<void> present;

  @override
  State<PromoTrigger> createState() => _PromoTriggerState();
}

class _PromoTriggerState extends State<PromoTrigger> {
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    if (!_submitted) {
      _submitted = true;
      widget.manager.open<void>(id: 'build-promo', present: widget.present);
    }
    return const SizedBox.shrink();
  }
}
```

### 通知按操作合并（Notifications are batched per operation）

一次公开操作在同步变更完成后，最多通知一次管理器监听者。异步续体算独立的批次。
build 期间的通知合并到帧后发出。`dataListenable` 和异步 `events` 是独立通道。

### 标签（Tags）

`tags` 默认是空集合，提交时复制为只读的 `OverlayRecord.tags`。
`clearTag(tag)` 会移除带该标签的 pending、resolving、open、closing 条目，
绕过 `beforeClose`，结束原因为 `removed`。

```dart
manager.open<void>(id: 'campaign', tags: {'promo', 'home'},
  present: dialogs<void>((ctx, close) => const Text('Campaign')));
final record = manager.recordOf('campaign');
if (record?.phase == OverlayPhase.open) {
  manager.clearTag('promo');
}
```

### 队列 / 优先级 / replace / affix / overlap

`mode` 只能选一种 `OverlayMode`：`queue`（默认）、`replace` 或 `overlap`。
`affix` 单独设置，replace 和 overlap 不能同时用。

```dart
manager.open(id: 'welcome', present: dialogs((ctx, close) => const WelcomeSheet()));
manager.open(id: 'promo', priority: 10, present: dialogs((ctx, close) => const PromoCard())); // 插队靠前

// 抢占当前浮层(它会被关闭,结果 null——已被 dismiss 的后端没法如实重新呈现):
manager.open(id: 'session-expired', mode: OverlayMode.replace, present: dialogs((ctx, close) => const ExpiredDialog()));

// 固定当前浮层,replace 顶不掉它:
manager.open(id: 'critical', affix: true, present: dialogs((ctx, close) => const CriticalDialog()));

// 绕过队列，延迟结束后判资格并叠加：
manager.open(id: 'net-error', mode: OverlayMode.overlap, delay: const Duration(seconds: 1), present: dialogs((ctx, close) => const Text('Network error')));

// 并行的独立串行队列:
manager.open(id: 't1', slot: 'toast', present: dialogs((ctx, close) => const Toast('已保存')));
```

`RouteMatcher.exact('/promo')` 匹配单个路径。
`const RouteMatcher.anyOf(['/promo', '/home'])` 匹配列表中的任一路径。
`RouteMatcher.regex(RegExp(r'^/promo/'))` 用 `hasMatch` 匹配。上下文路由为 null 或不是字符串时，一律不匹配。

overlap 的 `delay` 有效：先等待，再按“现在或永不”判断资格。
remove、clear、同 id 重开、dispose 都会取消等待。暂停和 hydrate 可以让它继续等，它也不占串行 slot。

### 条件(`when` / `route` / `auth` / `setContext`)

排队的条目如果条件不满足，只是**等待**。已显示的条目如果条件不再满足，会被自动撤下（除非
设了 `dismissWhenUnmet: false`）。

```dart
manager.setContext({'route': '/promo', 'auth': true}); // 把真实导航/登录态喂进来

manager.open(id: 'promo', route: const RouteMatcher.exact('/promo'), present: dialogs((ctx, close) => const PromoCard()));
manager.open(id: 'inbox', auth: (ctx) => ctx['auth'] == true, present: dialogs((ctx, close) => const InboxHint()));
manager.open(
  id: 'vip',
  when: (ctx) => ctx['tier'] == 'gold', // 与 route / auth 按 AND 组合
  present: dialogs((ctx, close) => const VipCard()),
);
```

`route`、`auth`、`when` 按 **AND** 组合，没设的条件视为通过。
只有 `route` 读取保留键 `route`；`auth` 和 `when` 读取你用 `setContext` 推进来的任意键，
引擎自己不会读 `auth` 键。判断函数抛错时，每个条目只上报一次，并视为不满足。
条件是推模式：外部状态变了，要调用 `setContext`（可以传 `setContext({})`）或靠其他调度触发才会重新判断，
不会只因为时间过去而自动重判。

判断回调（`when`、`auth`、`clearWhere` 的 test）只能读状态。回调里调用管理器的写操作、
票据或 context 操作、hold.release 或 dispose，都会在状态改变前抛出 `StateError`，消息包含“判断函数内不能修改 Layerman”。
条件异常每个条目只上报一次，并视为不满足；`clearWhere` 的 test 抛出的异常会向外传播；只读 getter 不受限制。

### 登录与角色（`auth:` 判断函数）

```dart
manager.setContext({'signedIn': true, 'role': 'admin', 'route': '/admin'});
manager.open<void>(
  id: 'admin-hint',
  route: const RouteMatcher.exact('/admin'),
  auth: (ctx) => ctx['signedIn'] == true && ctx['role'] == 'admin',
  when: (ctx) => ctx['maintenance'] != true,
  present: dialogs<void>((ctx, close) => const Text('Admin')),
);
```

旧的 `requiresAuth: true` 改为 `auth: (ctx) => ctx['auth'] == true`；
旧的仅游客 `requiresAuth: false` 改为 `auth: (ctx) => ctx['auth'] != true`。
键名以及角色、权限策略由业务自己决定。

### 业务资格（`gate:`）

`gate` 用于既不是路由、也不是登录、又没法用简单布尔判断描述的激活资格，
返回 `OverlayVerdict`。它在 `route`、`auth`、`when` 都通过（AND）之后、激活之前求值，
**只拦截激活**：不会重新判断已经在 resolve 或已展示的条目，也不会触发 `dismissWhenUnmet`。

- `OverlayVerdict.pass()`：允许激活（其余约束仍然生效）。
- `OverlayVerdict.waitUntil(retryAt)`：等到 `retryAt` 自动重新判断，`setContext` 也能让它提前重判。
  串行条目和 overlap 都能等；已经过去的时刻视为通过。`retryAt` 要用
  `manager.clock.now()` 算，别用 `DateTime.now()`，否则 `FakeOverlayClock` 下截止时间会算错。
- `OverlayVerdict.drop()`：永久拒绝，条目以 `OverlayEndReason.gated` 结束。

gate 抛异常时，每个条目只上报一次（和 `when` / `auth` 共用）：串行条目继续等待，overlap 以
`dropped` 结束。它和其他判断函数一样只读，在回调里修改管理器会抛 `StateError`。

```dart
manager.open<void>(
  id: 'promo',
  present: dialogs<void>((ctx, close) => const Text('Promo')),
  gate: (ctx) {
    if (ctx['declined'] == true) return const OverlayVerdict.drop();
    if (ctx['ready'] == true) return const OverlayVerdict.pass();
    return OverlayVerdict.waitUntil(
      manager.clock.now().add(const Duration(minutes: 5)),
    );
  },
);
```

### 自动路由感知(`LayermanNavigatorObserver` + `pauseOnRoutes`)

手动在每个页面的生命周期里写 `setContext({'route': ...})` 是样板代码。
`LayermanNavigatorObserver` 帮你自动做这件事：加进 `navigatorObservers` 就行，GetX、
go_router、原生 Navigator 都能用（三者底层都是同一个 Flutter Navigator，而它是标准的
`NavigatorObserver`）。它只观察，不 push、不 pop，也不碰导航本身。

```dart
MaterialApp(
  navigatorKey: navigatorKey,
  navigatorObservers: [LayermanNavigatorObserver(manager)],
  home: const Scaffold(),
);
```

装上之后，把它当作 `route` 这个上下文键的**唯一写入方**：手动调用 `setContext({'route': ...})`
会在下一次导航时被覆盖。要读当前追踪到的路由，用 `manager.currentRoute`，不用自己再维护一份。
path 默认取 `route.settings.name`；你的路由库把 path 放在别处时，传 `pathOf` 覆盖。
匿名路由（没设 `settings.name`）会上报 `null`，条件匹配不到 `null`。这是因为 Flutter
对匿名路由没有“path”这个概念，不是本包的缺陷。

容易踩的几个 Flutter 行为：

- **`MaterialApp.home` 的隐式路由名是 `'/'`**，不是 `null`，也不是 `'/home'`。这是
  Flutter 自己的 `Navigator.defaultRouteName`。想让首页按某个特定字符串匹配条件，要用
  `initialRoute` / `routes`（或带名字的 `RouteSettings`）显式命名，不能靠 `home:`。
- **0.3.0 起默认只跟踪 `PageRoute`。** 对话框、底部弹层和菜单不会改变最近记录的页面路径，
  所以带路由条件的弹窗不会自己关掉，无关的弹窗也不会解除免打扰区。
  要恢复 0.2.x 的行为，传 `routeFilter: (r) => true`。
- 嵌套 Navigator 可以用 `contextKey: 'tabRoute'`，在 `when` 里读取。
  `route:` 和 `pauseOnRoutes` 仍然只读默认的 `route` 键。

`pauseOnRoutes` 在这个基础上做出“免打扰区”：进入匹配的路由会冻结整条队列（和
`pauseAll()` 一样，不激活新的浮层），离开时恢复（和 `resumeAll()` 一样）。它和手动
`pauseAll` / `resumeAll` 是**组合**关系，不是互斥：离开免打扰区不会取消一次无关的手动
暂停，手动 `resumeAll()` 也不会取消仍然生效的免打扰区。

```dart
final manager = Layerman(pauseOnRoutes: const [RouteMatcher.exact('/checkout')]);
// 追踪到的路由是 '/checkout' 期间,不会有新浮层显示——排队的等着,
// 路由一变就立刻激活。
```

进入免打扰区时，“已经在显示的浮层”要不要自动关闭，**刻意不做统一规则**。可以用上面那套
`route` / `when` + `dismissWhenUnmet`（不管哪个 `present:` 后端在渲染，规则都一样），
也可以用某个后端自带的路由感知关闭功能。

### `DialogManager` / `BottomSheetManager`

用应用的 `navigatorKey` 建一次即可。实例只保存配置，每次展示都独立持有自己的 Route。
builder 的 `close([result])` 一律交给 `ctx.close`，会经过 `beforeClose`；实例可以在多个管理器之间复用。
返回键、遮罩和拖动关闭属于后端自己的关闭路径，会绕过守卫。单次调用传入的非 null 选项会覆盖构造时的默认值：

```dart
manager.open<bool>(
  present: sheets<bool>(
    (ctx, close) => TextButton(onPressed: () => close(true), child: const Text('Done')),
    isScrollControlled: true,
    barrierDismissible: false,
  ),
);
```

两者默认 `barrierDismissible: true`、`useSafeArea: true`、`routeNamePrefix: 'layerman://'`。
颜色先取主题，对话框最后兜底用 `Colors.black54`。底部弹层还默认
`isScrollControlled: false`、`enableDrag: true`、`showDragHandle: null`、`backgroundColor: null`。
页面或自定义 Route 用 `presentRoute`，见下方手写配方。

### 结果 / 票据 / 事件（Outcome / tickets / events）

`submit<T>` 的参数和 `open<T>` 完全相同，返回 `OverlayTicket<T>`。`result` 是 `Future<T?>`，
`outcome` 是 `Future<OverlayOutcome<T>>`，包含 `value` 和第一次结束的 `reason`。
两者都在退场动画结束之前完成。类型化的 `ticket.close([T? result])` 会遵守守卫，`remove()` 绕过守卫，
`update(patch)` 更新数据，`data` 是 `ValueListenable<Object?>`。旧票据不能操作同 id 的新提交。
`isActive` 把仍受管的 pending、resolving、closing 也算在内。
`events` 是异步广播流，`OverlayEventType` 有 `queued`、`shown`、`ended`，事件带
`id`、`slot`、`type` 和可空的 `reason`。要在提交前订阅，不会重放历史事件。`ended` 表示第一次完成，不是动画结束。

```dart
final subscription = manager.events.listen((event) {
  debugPrint('${event.id}: ${event.type} ${event.reason}');
});
final ticket = manager.submit<bool>(
  id: 'decision',
  present: dialogs<bool>((ctx, close) => AlertDialog(
    actions: [TextButton(onPressed: () => close(true), child: const Text('OK'))],
  )),
);
ticket.update({'count': 1});
final outcome = await ticket.outcome;
debugPrint('${outcome.value}: ${outcome.reason}');
await subscription.cancel();
```

同一次提交的事件按 queued → shown → ended 的顺序发出，present 里同步关闭也一样。
present 抛错时没有 shown，只有 ended（`failed`）。

### 暂停来源：`hold` 与 `LayermanLifecycle`

手动暂停、`pauseOnRoutes`、未释放的 hold 之间按 OR 组合。`hold(reason)` 返回 `OverlayHold`，
`release()` 可重复调用，`holdCount` 只统计 hold。释放一个来源不会影响其他来源。
`LayermanLifecycle` 默认在 `AppLifecycleState.paused`、`hidden` 时获取 hold，其他状态时释放，
`pauseOn` 可以改这个集合。`attach()` 会立即同步当前状态，`detach()` 解除监听并释放，两者都可重复调用。
更换所有者时要先 detach。

```dart
final lifecycle = LayermanLifecycle(manager)..attach();
final hold = manager.hold('payment');
try {
  await Future<void>.delayed(const Duration(milliseconds: 100));
} finally {
  hold.release();
}
// When the app owner is disposed or the manager is replaced:
lifecycle.detach();
```

### 超时、`expireAfter` 与 slot 选项

`dismissTimeout` 默认 10 秒，从请求后端关闭时算起；`resolveTimeout` 默认 30 秒。
构造时两者都可以传 `null` 表示不限时。单个条目的 `resolveTimeout: null` 表示沿用默认值，
`Duration.zero` 关闭该条目的 resolve 超时。构造时传零是立即超时，不是禁用。
超时会通过 `FlutterError.reportError` 上报 `TimeoutException` 并释放 slot。
resolve 超时的结束原因是 `skipped`，关闭超时保留已经给出的结果和原因。
超时不会取消底层异步工作，也不保证后端 UI 已移除。
`expireAfter` 只计算激活前的串行等待时间（含暂停），不适用于 overlap 和已激活的条目，
到期原因为 `queueExpired`。slot 的 `gap` 覆盖全局 `gap`。正数 `maxQueued` 不含活跃条目，
超出时淘汰排好序的队尾（`queueFull`），可能就是刚提交的这个。
这些截止计时在暂停时照常走，只有 `duration` 会冻结。

```dart
final bounded = Layerman(
  dismissTimeout: const Duration(seconds: 10),
  resolveTimeout: const Duration(seconds: 30),
  slots: const {
    'notice': OverlaySlotOptions(gap: Duration(milliseconds: 200), maxQueued: 3),
  },
);
final boundedDialogs = DialogManager(navigatorKey);
bounded.open<String>(
  slot: 'notice',
  expireAfter: const Duration(minutes: 1),
  resolveTimeout: Duration.zero,
  resolve: () async => 'Ready',
  present: boundedDialogs<String>((ctx, close) => Text(ctx.data as String)),
);
// The owner eventually calls bounded.dispose().
```

串行 `delay` 在 slot 的 gap 之后再等，replace 和同 id 的活跃接管会跳过它；overlap 先等待，再判断资格。
delay 属于正在等待的那个条目：移除或覆盖该条目会取消旧的等待，并重新调度 slot。
`maxQueued` 在激活判定之后才限制仍在等待的条目，build 期间连同容量检查一起推迟到帧后调度。
等待 gap、delay、条件、冷却或 `blockedBy` 的条目仍然计数，本次提交也可能被淘汰。

#### 跨 slot 阻塞（`blockedBy`）

```dart
final manager = Layerman(slots: {
  'toast': OverlaySlotOptions(blockedBy: {'modal'}),
  'banner': OverlaySlotOptions(blockedBy: {'modal'}),
});
```

`OverlaySlotOptions.blockedBy` 类型为 `Set<String>`，默认为空。列出的 slot 被占用期间，本 slot
不激活新条目。“占用”指串行 active 的条目（resolving / open / closing，含 `exitDuration` 宽限），
或该 slot 里已激活的 overlap。gap、appear delay、冷却等待、排队中的条目和等待中的 overlap
**都不算占用**，所以被阻塞的条目可能在 blocker 的两个条目之间出现。**已激活的条目继续显示，
`duration` 照常计时**：modal 出现之前已经显示的 toast 不会被关闭或暂停。

被阻塞的串行条目继续排队，`expireAfter` 和 `maxQueued` 照常生效。replace 在被阻塞时不抢占，
解除后保持原来的最前排序。合格的同 id 串行重开会排队，并保留接管优先权。初次资格检查通过的
overlap 会被持有，解除后再做一次“现在或永不”的判断。
解除统一在最外层操作批次结束时处理，避免 replace 移走旧条目、激活新条目的间隙让其他 slot 插队。
只重新判断确实在等解除的 slot 和被持有的 overlap，不会给其他 slot 增加条件重判的触发点。
循环阻塞按先激活者占用，不保证公平；不存在的 slot 名没有效果；自己阻塞自己会触发 debug 断言。

### 实时数据（`dataListenable`）

`PresentContext.data` 是快照，`dataListenable` 会在 `update` 和 resolve 出新值时通知。
`ticket.data` 是同一个通道，结束后保留最后一个值。manager 刻意不 dispose 这个通道，
方便退场动画结束后再解除监听；后端销毁时，记得移除自己注册的监听者。

```dart
manager.open<void>(
  id: 'cart',
  data: {'count': 1},
  present: dialogs<void>((ctx, close) => ValueListenableBuilder<Object?>(
    valueListenable: ctx.dataListenable,
    builder: (_, value, __) => Text('${(value as Map)['count']}'),
  )),
);
manager.update('cart', {'count': 2});
```

当前数据和 patch 都是字符串键的 Map（`Map<String, Object?>` / `Map<String, dynamic>`）时，浅合并的结果保持
`Map<String, Object?>`，所以后端里 `value as Map<String, dynamic>` 之类的转换继续可用。其他 Map 组合会合并成通用 Map。

### 冷却(频次上限 + 持久化)

```dart
manager.open(
  id: 'rate-us',
  cooldown: const OverlayCooldown(total: 3, day: 1, minGap: Duration(hours: 6)),
  present: dialogs((ctx, close) => const RateUsCard()),
);
```

所有上限都必须通过（AND）才显示，`PresentedOverlay.visible` 确认首帧后才计数。计数按 `id` 记录，所以用冷却必须传显式的 `id`
（debug 下会断言，因为自动生成的 id 每次都不同）。`session` 存内存，其余持久化。生产环境接真实存储：

```dart
final manager = Layerman(cooldownStorage: SharedPrefsCooldownStorage());
await manager.ready(); // 可选:计数已加载、队列已重新调度
```

存储 hydrate 完成前，**所有带 `cooldown` 的提交**都要等，包括只设 session 的和空配置，
因为抑制状态是持久化的。串行条目排队，overlap 被挂起而不是丢弃；不带 `cooldown` 的提交不受影响。
迁移：以前依赖 session-only 条目在 `ready()` 前出现的代码，现在会晚一次存储读取的时间。
在 `ready()` 之前调用 `open` 仍然安全。读或写失败都会通过 `FlutterError.reportError` 上报，不会卡住调度。

`shared_preferences` 适配器的最小实现：

```dart
class SharedPrefsCooldownStorage implements OverlayCooldownStorage {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}
```

**1.0.0 补全 0.3.0 的行为：** `session` / `total` 用完的串行条目，在提交时就立即以
`null`（`capped`）结束；hydrate 完成时会再检查一次队列，不受 slot 占用或暂停影响。
需要可重试的等待，请用时间型冷却；新活动请用新的 id。

`cooldownStatus(id, cooldown)` 返回 `OverlayCooldownStatus`。`canShow` 表示所有上限和抑制检查都通过，
`permanentlyBlocked` 表示 session / total 已用完或被永久抑制。`wait` 在可以显示时是 `Duration.zero`，
受时间型冷却限制时是最长的剩余等待时间，永久受阻或在等冷却存储 hydrate 时是 `null`。
`suppressed` 表示当前有限时或永久抑制。hydrate 之前 `canShow: false, wait: null`，
但 `permanentlyBlocked` 和 `suppressed` 仍然反映内存里已知的状态（包括 session 用完、本次运行中设置的永久抑制）。
`resetCooldown(id)` 清除该 id 的 session 计数、持久化计数和抑制，`clearCooldowns()` 清除全部计数和抑制。
两者都会重新判断等待中的条目并持久化重置，但救不回已经以 `capped` 或 `suppressed` 结束的条目。

```dart
const cap = OverlayCooldown(session: 2, minGap: Duration(minutes: 5));
final status = manager.cooldownStatus('promo', cap);
if (status.canShow) {
  manager.open<void>(id: 'promo', cooldown: cap,
    present: dialogs<void>((ctx, close) => const Text('Promo')));
}
manager.resetCooldown('promo');
manager.clearCooldowns();
```

日 / 小时 / 分钟上限按本地日历计算，时钟返回 UTC（例如服务器时间）时也一样。存储里某条记录损坏时，
会上报并跳过，原值原样写回，直到同 id 写入新的有效记录，或者 `resetCooldown` / `clearCooldowns` 删掉它。
其他 id 的计数和抑制不受影响。

#### 不再提示（`suppress`）

卡片关闭时返回 `'never'`、`'later'` 或 `null`，按结果决定怎么抑制。
`const OverlayCooldown()` 不设次数上限，只遵守 suppress：

```dart
Future<void> showPromo(Layerman manager, Present<String> present) async {
  final r = await manager.open<String>(
    id: 'promo',
    cooldown: const OverlayCooldown(),
    present: present,
  );
  if (r == 'never') manager.suppress('promo');
  if (r == 'later') {
    manager.suppress('promo', duration: const Duration(days: 3));
  }
}

// 例如设置页的开关：被抑制时显示，调用 resetCooldown('promo') 恢复提示。
bool promoSuppressed(Layerman manager) =>
    manager.cooldownStatus('promo', const OverlayCooldown()).suppressed;
```

`Layerman.suppress(String id, {Duration? duration})` 在 `duration` 为正数时，从现在起抑制这么长时间，
null 表示永久。它**只约束带 `cooldown:` 的提交**；不带 cooldown 的手动打开不受影响，
比如用户在设置页主动点“查看活动”。已激活的条目也不受影响。抑制和计数共用同一条持久化记录
（JSON 键 `su`），`resetCooldown(id)` / `clearCooldowns()` 会一起清除它。
多次调用时取更晚的到期时间，永久优先，只会延长不会缩短。所以“任何关闭都抑制三天，选不再提示就永久抑制”
这两个调用的先后顺序不影响结果。要缩短只能 reset，而 reset 会同时清掉计数。

永久抑制会立即以 `OverlayEndReason.suppressed` 结束排队的串行条目，即使正在暂停、slot 被占用或
hydrate 还没完成也一样。限时抑制让串行条目继续等，到期后自己唤醒（如果有更晚才到期的时间型上限，则等到那时）；
可以用 `expireAfter` 限制等待时间。overlap 在 delay 到点或被释放时判断，抑制阻止冷却通过就以 suppressed 丢弃。
冷却丢弃原因的优先级是 `suppressed > capped > dropped`；route / auth / when 条件失败仍然是 `dropped`。
永久抑制时 `permanentlyBlocked: true, wait: null`；限时抑制时，`wait` 取剩余抑制时间和其他时间型
等待中较大的那个（永久受阻或等 hydrate 时仍为 null）。

### 后端驱动 `resolve`

拿到 slot 后才取数据。`resolve` 的类型是 `Future<T?> Function()?`，和结果共用同一个 `T`。
返回 `null` 就跳过，且不计入冷却。resolve 期间，普通条目要等；`replace` 可以抢占并丢弃它。
`ctx.data` 是取到的值。

```dart
manager.open<String>(
  id: 'offer',
  resolve: () async => 'Today’s offer',
  present: dialogs<String>((ctx, close) => AlertDialog(
    content: Text(ctx.data as String),
    actions: [TextButton(onPressed: () => close('accepted'), child: const Text('OK'))],
  )),
);
```

### 在后端内部关闭（`ctx.close`）

`PresentContext<T>.close([T? result])` 经过 `beforeClose` 关闭本次提交，并绑定条目身份：
同 id 重开后，旧回调关不掉新条目。条目不是 open 状态，或守卫还没出结果时，调用无效。
后端自己触发的遮罩、返回键关闭仍然绕过守卫。

```dart
manager.open<bool>(
  beforeClose: () => true,
  present: (ctx) => presentRoute<bool>(
    navigatorKey.currentState!,
    DialogRoute<bool>(
      context: navigatorKey.currentContext!,
      builder: (_) => TextButton(
        onPressed: () => ctx.close(true),
        child: const Text('Done'),
      ),
    ),
  ),
);
```

### `beforeClose` 守卫

```dart
manager.open(
  id: 'editor',
  beforeClose: () async => await confirmDiscard(), // 返回 false 否决关闭
  present: dialogs((ctx, close) => const EditorSheet()),
);
```

`beforeClose` 只拦 `close()` / `dismiss()`，`remove` / `clear` / 自动撤下会绕过它。异步守卫
还没出结果时，同一浮层后续的 `close()` / `dismiss()` 会被忽略，所以连点两下不会问两次。

### pause / resume / update / clearWhere

```dart
manager.pauseAll();  manager.resumeAll();   // 整体冻结 / 释放并重排
manager.pause('sheet'); manager.resume('sheet'); // 冻结/恢复单个 duration 倒计时

manager.update('cart', {'count': 3});       // 浅合并进 data,通知监听者,不重排队列
manager.clearWhere((r) => (r.data as Map?)?['group'] == 'promo'); // 按条件批量清
```

`update` 对 Map 做浅合并，其他值直接替换，会通知 `dataListenable` 和 manager 的监听者，不改变队列。
要读实时值，用 `PresentContext.dataListenable`；`PresentContext.data` 仍是展示时的快照。

### 两阶段关闭 / 退场动画

`close()` 先给出结果，再请求你的后端关闭。队列要等后端的 `dismissed` future
完成，并经过可选的 `exitDuration` 宽限才继续；`dismissTimeout` 到期也会释放条目。
退场动画完全是你后端自己的事。路由后端用 `route.completed`，它在退场动画结束后带着
pop 结果完成；`showDialog` / `Navigator.push` 返回的 future 在 pop 开始时就完成。
`exitDuration` 只留给没有“动画结束”信号的后端。自定义后端也可以自己完成 `dismissed`：

```dart
manager.open<void>(
  id: 'sheet',
  present: (ctx) {
    final visible = Completer<void>();
    final done = Completer<void>();
    var closing = false;
    late OverlayEntry entry;
    void requestClose() {
      if (closing) return;
      closing = true;
      entry.markNeedsBuild(); // 用你自己的"关闭中"视觉状态重建
      Future.delayed(const Duration(milliseconds: 250), () {
        entry.remove();
        done.complete();
      });
    }

    entry = OverlayEntry(
      builder: (_) => AnimatedOpacity(
        opacity: closing ? 0 : 1,
        duration: const Duration(milliseconds: 250),
        child: OverlayVisibility(visible: visible, child: const MySheet()),
      ),
    );
    navigatorKey.currentState!.overlay!.insert(entry);
    return PresentedOverlay<void>(
      visible: visible.future,
      dismissed: done.future,
      dismiss: ([_]) async => requestClose(),
    );
  },
);

manager.close('sheet'); // 立即兑现；dismiss() 播完淡出后推进槽位
```

`resolvingIds` 包含正在 resolve 的条目（也含 overlap）。`records` 覆盖所有受管阶段，
`recordOf(id)` 返回单条快照或 `null`。`queuedIds` 在每个 slot 内按 replace / 优先级 / FIFO
的真实顺序排列，后面接挂起的 overlap；独立的 slot 之间没有全局出场顺序。

### 命令式控制与内省

```dart
manager.close('sheet', someResult); // 带结果的两阶段关闭
manager.dismiss('sheet');           // 以 null 关闭
manager.remove('sheet');            // 立即移除,无退场宽限
manager.clear();                    // 移除全部(排队 + 活跃)

manager.isShowing('sheet'); // 仅 open/closing 为 true
manager.activeIds;          // open/closing 的 id（串行 + overlap）
manager.queuedIds;          // 槽位内按出场顺序的 pending id
manager.resolvingIds;
manager.records;
manager.recordOf('sheet');
manager.isPaused;
```

resolving 条目在 `resolvingIds` 和 `records` 里，不在 `activeIds` / `queuedIds` 里，
打开之前 `isShowing` 为 false。

`Layerman` 是 `ChangeNotifier`，可以用 `addListener` / `AnimatedBuilder` 在每次
状态变化时刷新 UI。

## 接入其它浮层库(`Present` 适配器)

项目里往往不止一套浮层系统。`open(present: ...)` 让管理器去**调度**由**其它库渲染**的
浮层：`present` 回调只在队列许可时被调用一次，并返回一个双向句柄：

```dart
PresentedOverlay<T>(
  visible: firstPaintVisible,       // Future<void>: successful first visible frame
  // Waiting visible uses phase=open and occupies its slot; duration already runs.
  // visible error => failed; an earlier end keeps its reason and has no shown.
  // Only visible success while still open records cooldown and emits shown.
  dismissed: someFuture,            // 后端「已完全关闭」的信号(任意关闭路径)
  dismiss: ([T? result]) async {},  // 由编排器发起的定向关闭
)
```

- `await open(...)` 的结果：由管理器通过 `close(id, result)` 关闭时，就是那个 `result`，
  否则是 **`dismissed`** 完成时带的值。所以 `dismissed` 必须在**每一条**关闭路径上完成
  （用户点击、遮罩、返回键、超时、你的 `dismiss`）。
- `close` / `replace` / `clear` / `remove` 会调用 **`dismiss`**，代表管理器关闭后端。
- 路由后端的 `dismissed` 用 **`route.completed`**：退场动画结束后，带着 pop 结果
  完成。`showDialog` / `Navigator.push` 的 future 在 pop 开始时就完成。
  `exitDuration` 是 `dismissed` 之后的宽限，只留给没有“动画结束”信号的后端。

一条串行队列（加上优先级、replace、冷却、条件）统一管理来自不同库的
dialog、snackbar、toast。

### 原生 `showDialog`

对话框优先用 `DialogManager`。想自己控制时，可以手写 Route：`presentRoute` 推入路由，
用 `route.completed` 等退场结束，并只关闭这一条路由，不需要估算 `exitDuration`。
路由在栈顶且没有内部历史时，pop 会带上结果；被覆盖时用不带结果的 `removeRoute(route)`，以兼容 Flutter 3.27。
`manager.close` 仍然交付指定的结果；直接用返回的句柄关闭被覆盖或带内部历史的路由时，结果为 `null`。

带内部历史的页面（如打开的 Drawer、持久底部面板）也用 `removeRoute`，结果规则和被覆盖时相同。

```dart
manager.open<bool>(
  id: 'confirm',
  present: (ctx) {
    final navigator = navigatorKey.currentState!;
    final route = DialogRoute<bool>(
      context: navigator.context,
      settings: RouteSettings(name: 'layerman://${ctx.id}'),
      builder: (_) => const AlertDialog(content: Text('Confirm?')),
    );
    return presentRoute(navigator, route);
  },
);
```

### GetX dialog / bottom sheet

`Get.dialog` / `Get.bottomSheet` 不暴露 Route 对象。改为在同一个
Navigator（`Get.key.currentState!`）上直接 push `DialogRoute`：

```dart
manager.open<bool>(
  id: 'confirm',
  present: (ctx) {
    final navigator = Get.key.currentState!;
    final route = DialogRoute<bool>(
      context: navigator.context,
      settings: RouteSettings(name: 'om://${ctx.id}'),
      builder: (_) => const ConfirmDialog(),
    );
    // 成功构建、挂载且位于栈顶的首帧才确认可见。
    return presentRoute(navigator, route);
  },
);
```

底部弹层只需把上面的 `route` 构造换成下面的代码，push、
`route.completed` 和定向关闭的逻辑不变。`isScrollControlled` 是必填参数：

```dart
final route = ModalBottomSheetRoute<bool>(
  settings: RouteSettings(name: 'om://${ctx.id}'),
  builder: (_) => const ConfirmDialog(),
  isScrollControlled: false,
);
```

### GetX snackbar

`SnackbarController.future` 在退场动画结束后完成，是最干净的信号。管理器已经把队列
串行化，GetX 自带的 snackbar 队列就被绕开了。

```dart
manager.open<void>(
  id: 'saved',
  slot: 'snack', // 单独车道:让 toast 能与主 dialog 并存
  present: (ctx) {
    final visible = Completer<void>();
    final c = Get.snackbar('已保存', '你的修改已安全保存',
      messageText: OverlayVisibility(visible: visible, child: const Text('你的修改已安全保存')),
    );
    return PresentedOverlay<void>(visible: visible.future, dismissed: c.future, dismiss: ([_]) => c.close());
  },
);
```

> 提示：放在**独立 slot** 的 toast / snackbar 会**故意**和主 dialog 队列并行（这是常见
> 的交互）。若要严格排在 dialog 之后，把它放到**默认 slot**。

### 把导航到的页面也塞进队列

页面用 `presentRoute` 适配 `TransitionRoute<T>`。拿到 slot 才 push，直到退场结束才释放 slot。

```dart
manager.open<bool>(
  id: 'checkout',
  present: (_) => presentRoute(
    navigatorKey.currentState!,
    MaterialPageRoute<bool>(
      settings: const RouteSettings(name: '/checkout'),
      builder: (_) => const Scaffold(body: Text('Checkout')),
    ),
  ),
);
```

### bot_toast

关掉它自带的竞争逻辑：`onlyOne: false` 加专属的 `groupKey`；`onClose` 是唯一的“已完全
关闭”信号；`CancelFunc` 会播放退场动画。

```dart
manager.open<void>(
  id: 'tip',
  slot: 'toast',
  present: (ctx) {
    final visible = Completer<void>();
    final done = Completer<void>();
    final cancel = BotToast.showCustomText(
      toastBuilder: (_) => OverlayVisibility(visible: visible, child: Card(child: Text('已复制'))),
      onlyOne: false,               // replace 决策归管理器
      onClose: () => done.complete(),
    );
    return PresentedOverlay<void>(visible: visible.future, dismissed: done.future, dismiss: ([_]) async => cancel());
  },
);
```

### fluttertoast

`Fluttertoast.showToast` 是“发出去就不管”：**没有单条 toast 的关闭回调**，只有全局的
`Fluttertoast.cancel()`。所以要用一个和时长相同的定时器来**合成** `dismissed`。

```dart
manager.open<void>(
  id: 'copied',
  slot: 'toast',
  present: (ctx) {
    // 原生 showToast 没有可见回报；使用可确认首帧的 FToast widget。
    final visible = Completer<void>();
    final done = Completer<void>();
    final toast = FToast()..init(navigatorKey.currentContext!); // 已挂载页面中、Overlay 下的 context。
    toast.showToast(
      child: OverlayVisibility(visible: visible, child: const Card(child: Text('Copied'))),
      toastDuration: const Duration(seconds: 2),
    );
    final timer = Timer(const Duration(seconds: 2), () {
      if (!done.isCompleted) done.complete();
    });
    return PresentedOverlay<void>(
      visible: visible.future,
      dismissed: done.future,
      dismiss: ([_]) async {
        timer.cancel();
        toast.removeCustomToast();
        if (!done.isCompleted) done.complete();
      },
    );
  },
);
```

> 若需要带单条句柄的自定义 toast，用 `FToast`（`showToast` + `removeCustomToast`），
> 在你自己移除 toast 时去完成 `dismissed`。写法和 bot_toast 相同。

### 编写你自己的适配器 —— 清单

对任何“能显示、能关闭”的库：

1. 在 `present` 里调用该库的显示 API。
2. 返回 `PresentedOverlay(visible:, dismissed:, dismiss:)`。
3. **`dismissed`** 必须在**每一条**关闭路径上完成。路由用退场动画结束后的
   `route.completed`，其它后端用 `onClose`，都没有时再自己合成信号。
4. **`dismiss`** 必须通过**那一条**浮层自己的句柄关闭它，绝不“关掉栈顶那个”。
5. 需要单独一条队列就给 `slot`。`exitDuration` 只留给没有“动画结束”信号的后端，
   路由用 `route.completed`。

### 编排纪律(源自 GetX / bot_toast 的 issue 史)

1. 管理器自己掌握状态，**不要**去读 `Get.isDialogOpen` / `Get.isSnackbarOpen`。
2. 只用各浮层自己的句柄关闭（保存的 Route 对象、`SnackbarController`、
   `CancelFunc`），不要“关掉栈顶”。
3. 关掉后端自带的编排（`onlyOne`、`crossPage`、GetX 的 snackbar 队列），replace /
   dismiss 的决策归管理器。**不要**调用 `Get.closeAllSnackbars()`（会让已入队的 future 一直挂着）。
4. 管理器统一的是**先后顺序**，不是 **z 序**：`bot_toast` 永远画在路由之上（它在
   `Navigator` 之上的 `Stack` 里），返回键归各后端管。z 序完全由你的 `present:` 后端
   决定，想要明确控制，就在自己的 `OverlayEntry` 里插到需要的深度。

## 完整 API 参考

| 1.0 成员 / 类型 | 契约 |
| --- | --- |
| `OverlayPredicate? auth` | 默认 null，与 route / when 按 AND；读取任意业务键。 |
| `OverlayClock clock` | 默认 `OverlayClock.system`；`now()` 与 `createTimer(Duration, callback)` 同源。 |
| `OverlayClock` / `FakeOverlayClock([DateTime? start])` | 测试时钟从 `package:layerman/testing.dart` 导入，默认 DateTime(2000)；`advance(Duration d)`、`pendingTimers`。 |
| `PresentContext<T>.close([T? result])` | 绑定本次提交并经过 beforeClose；仅作用于 open 条目。 |
| `void close(String id, [Object? result])` / `void dismiss(String id)` | 仅关闭已展示的 open 条目，排队中和解析中的条目不受影响，取消请用 remove；close 可携带结果，dismiss 使用 null。 |
| `void dispose()` / `bool get isDisposed` | dispose 一开始 isDisposed 即为 true；销毁中后端回调重入 open / submit 立即以 disposed 结束，其余修改无操作。 |
| `debugCheckInvariants()` | 显式检查不变量；debug 最外层批次结束自动执行。 |
| `OverlayMode mode` | 默认 `OverlayMode.queue`；可选 `replace` / `overlap`，不能同时选择。 |
| `RouteMatcher? route` / `List<RouteMatcher> pauseOnRoutes` | 默认 null / 空列表；使用 `exact` / `anyOf` / `regex`；null 或非字符串路由不匹配，`anyOf` 的输入列表不可修改。 |
| `OverlayPhase` / `OverlayRecord.phase` | `pending` / `resolving` / `open` / `closing`，使用枚举比较。 |
| `void suppress(String id, {Duration? duration})` | 只抑制带 cooldown 的提交；null 永久，正时长从现在起计，只延长。 |
| `OverlayCooldownStatus cooldownStatus(String id, OverlayCooldown cooldown)` | 查询 `canShow`、`permanentlyBlocked`、`wait`、`suppressed`（构造默认 false），不增加计数。 |
| `OverlayCooldownStatus.suppressed` | `final bool`，当前是否处于抑制中；构造参数默认 false。 |
| `void resetCooldown(String id)` / `void clearCooldowns()` | 重置单 id / 全部 session、持久化计数及抑制并重调度。 |
| `Set<String>? tags` / `OverlayRecord.tags` | 参数默认 null（空集合）；提交时复制为只读集合。 |
| `void clearTag(String tag)` | 批量移除带标签条目，绕过守卫，原因 `removed`。 |

完整的签名和默认值见英文版的 [Full API reference](README.md#full-api-reference)，
那里列出了所有导出的符号：`Layerman`（构造函数和全部方法 / getter，含
`pauseOnRoutes` / `currentRoute`）、`open<T>` 的每个参数、`LayermanNavigatorObserver`、
`OverlayCooldown`、`OverlayCooldownStorage` / `MemoryCooldownStorage`、`OverlayRecord`、
`Present` / `PresentContext` / `PresentedOverlay`、`OverlayPredicate` / `OverlayGate` / `OverlayVerdict`。
中英文共用同一份签名表，下面只摘要新增的类型。

| 成员 / 类型 | 契约 |
| --- | --- |
| `submit<T>` / `OverlayTicket<T>` | 参数与 `open<T>` 相同；`id`、`slot`、`result`、`outcome`、`isActive`、`data`；`close([T? result])`、`remove()`、`update(Object? patch)`。 |
| `OverlayOutcome<T>` / `OverlayEndReason` | `value` 与首次 `reason`；新增 `OverlayEndReason.suppressed`（抑制丢弃）与 `gated`（被 gate 永久拒绝）；全部原因及含义见 [架构生命周期表](ARCHITECTURE.md#4-条目生命周期)。 |
| `events` / `OverlayEvent` / `OverlayEventType` | 异步广播；事件有 `type`、`id`、`slot`、`reason`；类型为 `queued` / `shown` / `ended`。 |
| `hold([Object? reason])` / `OverlayHold` | 独立暂停；`reason`、`isReleased`、`release()`，`holdCount` 统计未释放数量。 |
| `OverlaySlotOptions` | `Duration? gap`、`int? maxQueued`、`Set<String> blockedBy`（默认空）；未提供前两项则继承全局间隔 / 不限队列长度；blockedBy 按其他 slot 的占用门控激活。 |
| `dismissTimeout` / `resolveTimeout` / `expireAfter` | 默认关闭 10 秒、解析 30 秒、排队不限时；单条解析零时长禁用，构造参数 null 禁用。 |
| `resolvingIds` / `records` / `recordOf(String id)` | 解析中 id / 全部条目快照 / 单条快照或 null。 |
| `PresentContext.dataListenable` | `ValueListenable<Object?>`，实时数据；`data` 为快照。 |
| `OverlayGate? gate` / `OverlayVerdict` | `pass()` / `waitUntil(DateTime retryAt)` / `drop()`；业务激活资格，在 route/auth/when 之后求值；drop 以 `OverlayEndReason.gated` 结束；`retryAt` 用 `manager.clock.now()` 计算。 |
| `DialogManager` / `BottomSheetManager` / `presentRoute` | Route 型 presenter；构造配置、单次覆盖、签名见英文完整表。 |
| `LayermanLifecycle` | `manager`、`isAttached`、`attach()`、`detach()`、`didChangeAppLifecycleState`；`pauseOn` 默认 paused / hidden。 |
| `LayermanNavigatorObserver` | `pathOf`、`routeFilter`、`contextKey`；默认 PageRoute 过滤与 route 键。 |

## 与 TS 版的刻意差异

- **不做 `stackIndex` / `isTopmost`**：层级和 z 序完全交给渲染浮层的 `present:` 后端
  （它自己的 `Overlay` 或路由栈），队列不追踪也不提供。
- **不内建跨标签页 / 跨 isolate 的冷却同步**：需要的话，共享同一个 `OverlayCooldownStorage`
  后端即可。
- **时间型冷却会自己唤醒**：headless TS 内核只在下一次调度触发时才重新评估，这里不一样：
  被 `minGap` 或自然时段滚动挡住的 Flutter 条目会设一个定时器，时间一到就自动显示。
  `session` / `total` 用完后条目被丢弃，结果为 null。

### 脱离 Flutter 绑定测试（`FakeOverlayClock`）

应用的 dev_dependencies 加入 `test`，就能用普通的 `test()` 测引擎，不需要 flutter_test 绑定；
解析依赖仍需要 Flutter SDK。`OverlayClock` 的 `now()` 和 `createTimer` 必须同源，
不能再单独注入日期回调。`advance` 会触发虚拟计时器，Future 续体要另外排空。

```dart
import 'dart:async';
import 'package:layerman/layerman.dart';
import 'package:layerman/testing.dart';
import 'package:test/test.dart';

void main() {
  test('注入时钟控制展示时长', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    final dismissed = Completer<bool?>();
    final result = manager.open<bool>(
      duration: const Duration(seconds: 1),
      present: (_) => PresentedOverlay<bool>(
        visible: Future<void>.value(), // headless test: immediate visibility
        dismissed: dismissed.future,
        dismiss: ([value]) async { dismissed.complete(value); },
      ),
    );
    clock.advance(const Duration(seconds: 1));
    expect(await result, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(manager.activeIds, isEmpty);
    expect(clock.pendingTimers, 0);
  });
}
```

### debug 不变量检查

debug 下，每个最外层操作批次结束都会自动运行 `debugCheckInvariants()`，检查容器身份、阶段、
排序、计时器和销毁状态。测试可以显式调用（release 也可以），违反约束会抛 `StateError`。
不变量断言和随机序列测试能降低重构风险，但不能替代显式状态机。

## 测试

```bash
flutter test                                            # 单元(widget)测试
cd example && flutter test integration_test/orchestration_test.dart -d <serial> # 真机编排测试
```

单元测试用 `WidgetTester`，覆盖串行队列、关闭后推进、优先级、`Future` 结果、
`replace` / `affix` / `overlap`、条件、冷却（含自唤醒）、`resolve`、`beforeClose`、
pause / resume、`update` / `clearWhere`、`present:` 适配器、阶段切换。`example/` 是一个
完整的真机 demo，通过管理器编排 GetX、bot_toast 和原生 `showDialog`。
手机验证设备为华为 STG-AL00 / Android 12。Windows 桌面运行会抢焦点，不要无人值守地跑。

## 许可

MIT。见 [LICENSE](LICENSE)。

