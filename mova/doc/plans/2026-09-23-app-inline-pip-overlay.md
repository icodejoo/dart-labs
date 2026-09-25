# mova 0.6.0：App 内小窗（MovaMini） — 实现计划

**Goal:** 在**不依赖任何系统 PiP API** 的前提下，让播放画面从页面里"缩"成一个可拖拽的悬浮小窗，
**不重新解码、不黑屏**；点小窗回到原页面、点关闭结束播放。两种悬浮范围都要支持——
**页内悬浮**（不受页面滚动影响，随页面生灭）与**跨路由持久悬浮**（push/pop 任意多层仍在最上），
底层状态/位置/渲染面逻辑共用一份（见 §1.1）。默认**关闭**
（`MovaOpts.mini.enabled` 为 `false` 时全链路零行为变化），四端通用（Android/iOS/桌面/Web）。

**与系统 PiP 的关系：** 三者正交、互斥生效——
① `MovaApi.enterPip()`（Android 系统级，已真机验证 `mWindowingMode=pinned`）把**整个 Activity**
缩成系统悬浮窗，退出 App 后仍在；② iOS 系统 PiP 仍未实现（卡在 `AVSampleBufferDisplayLayer`
门槛 spike，见 `doc/notes/2026-07-31-ios-pip-feasibility.md`）；③ 本计划的 **App 内小窗**只在
自家 App 前台的绘制树里做文章，**不出 App**，但**没有任何平台门槛**，四端一次写完。
本计划是 iOS PiP 缺口的跨平台降级方案（即那份笔记里的"阶段 3：跨平台应用内悬浮窗"），
同时也是 Android 上"不想申请 PiP 权限/不想让用户离开 App"场景的首选。

**Architecture:** 核心洞察——**画面不动，widget 动**。`MovaEngine`/`MovaMpvKernel`/`VideoController`
是纯 Dart 对象，它们的生命周期与 widget 树**完全无关**；只要宿主在路由之外持有同一个
`MovaApi` 实例，把 `MovaPlayer` 从页面里卸载、在小窗里重新挂载，libmpv 侧一个字节都不会重新解码
——重挂的只是 Flutter 的 `Texture` widget，`renderHandle` 指向的 `VideoController` 自始至终没变。
`player.dart` 现有的 `KeyedSubtree(key: ValueKey(widget.api))` 恰好保证了这次重挂是干净的
（所有在 `initState` 里订阅流的后代都会重新订阅到同一个活着的 api 上）。
因此本功能的实现量 = **一个路由外的持有者 + 一个绘制在 Navigator 之上的可拖拽框**，
不需要动 `core/` 里任何一行播放逻辑。

**Tech Stack:** Dart 3.12.2 / Flutter ≥3.3、media_kit ^1.2.6、flutter_test。
**本阶段不新增任何第三方依赖**（第三方调研结论见下节，`floating` 明确不引入）。

**Baseline:** 0.5.0，**709 项测试全绿**、`flutter analyze` 0 issues（仅剩那条既有
`feed_player.dart` 警告）。

---

## 0. 第三方包调研结论（重要：用户给出的前提有误，需先纠正）

用户提到"常见开源实现：floating（纯 Dart，基于 Overlay，不依赖系统 PIP，可用于 iOS/Android 通用）"。
**实测核对 pub.dev 后，这个描述与事实不符**：

| 包 | 实际是什么 | 结论 |
|---|---|---|
| **`floating`** (v6.0.0, wrbl.xyz, 270 likes, 160 pts, 距今约 19 个月未更新) | **不是**纯 Dart Overlay，而是 **Android 系统 PiP 的原生封装**（`PiPSwitcher` / `ImmediatePiP` / `OnLeavePiP` / `sourceRectHint`）。README 明说 **Android only**，且"iOS/Web 在平台自身支持前不计划支持" | **否决**。它解决的是 mova **已经自研并真机验证过**的那件事（`MovaApi.enterPip()` + `MovaPlugin.kt`），引进来只会与既有 `pipSupported`/`MovaPipChg`/`MovaState.pip` 语义打架，而对本需求（App 内小窗）**零贡献** |
| `draggable_panel` (v4.1.0，22 天前发布，27 likes，全平台，零依赖) | 真正的纯 Dart 可拖拽面板；**不碰任何 video controller**，只是一个壳 | **可用但不推荐**。① 它要求挂在 `MaterialApp.builder` 上并**自带一套三段式动效模型**（parked / small / expanded），会把它的交互语言强加给 mova 的宿主；② mova 是发到 pub.dev 的**库**，为约 300 行可写的 UI 外壳给所有下游用户加一个 27 likes 的依赖，性价比不成立；③ 与 mova 的 Skin/Component 契约无从对接 |
| `flutter_overlay_window` / `floating_window_android` / `floating_view` 等 | **系统级悬浮窗**，不是"App 内悬浮"——见下方专门辨析 | **否决**。需要运行时权限、Android 独占，与"App 内、四端通用"的需求正交 |

**⚠️ 必须先分清两个同名不同物的"悬浮窗"**（这是本计划最容易被误读的一处，也是
`flutter_overlay_window` 一类包被否决的**唯一**理由）：

| | **系统级悬浮窗**（`flutter_overlay_window` 等） | **App 内悬浮**（本计划） |
|---|---|---|
| 画在哪 | 系统 WindowManager 的一个独立 window，**在自家 App 之外** | 自家 App 的 Flutter 绘制树内，**永远不出 App** |
| 典型形态 | Messenger 的 chat head：切到桌面、切到别的 App，它还浮着 | 用户一旦切走 App，它跟着 App 一起进后台 |
| 权限 | Android 需 `SYSTEM_ALERT_WINDOW`（用户要去系统设置里手动授予）；iOS 根本没有对应能力 | **零权限**，四端一次写完 |
| 与 mova 的关系 | 是 `enterPip()`（系统 PiP）的同类物，属于"离开 App 仍可见"这一档 | 是本计划要做的事 |

**用户提出 `Overlay`/`OverlayEntry` 时说的是后者**——Flutter framework 里的 `Overlay` 是纯
Dart 的绘制层，与 `SYSTEM_ALERT_WINDOW` 毫无关系，只是名字里也有"overlay"。
本计划**采纳** `OverlayEntry` 作为挂载方式之一（见 §1.1），被否决的只是上表左列那些
真·系统窗包。

**推荐：手撸。** 理由不是"NIH"，而是本功能的**难点根本不在拖拽框**——拖拽框是 `Stack` +
`Positioned` + `GestureDetector` 约 150 行；难点在**播放器实例如何脱离路由生命周期存活**，
而这件事**只有 mova 自己知道怎么做**（`MovaApi` 由谁持有、`renderHandle` 何时可复用、
`ValueKey(api)` 的重挂语义、`MovaSwapEngine` 代理下的稳定引用）。任何第三方包都帮不上这一段，
而这一段正是全部风险所在。

---

## 1. 架构决策

### 1.1 两种挂载方式都要支持，且与核心逻辑解耦（**本节 2026-09-23 修订**）

> **修订说明**：本节此前的结论是"不用 `OverlayEntry`，改用 `MaterialApp.builder` 下的
> `Stack`"。**该结论作废**。它把 `OverlayEntry` 的适用场景想窄了——只评估了"跨路由全局
> 持久悬浮"，而用户真正要的另一半是"**页内悬浮**"，后者恰恰是 `OverlayEntry` 的主场。
> 现在的结论是：**两种挂载方式并存，谁也不取代谁。**

#### 两种需求是两件事

| | **方式 A：页内悬浮** | **方式 B：全局持久悬浮** |
|---|---|---|
| 需求 | 就在**这一个页面内部**浮着：不受页面滚动内容影响、可拖拽移动位置 | 跨路由常驻：push/pop 任意多层，小窗一直在最上 |
| 挂载 | `Overlay.of(context)` 找到的**最近祖先** Overlay，`insert(OverlayEntry)` | `MaterialApp.builder` 下的 `Stack` + `Positioned` |
| 生命周期 | 跟随该页面：页面被 pop，小窗随之消失（本来就该消失） | 独立于路由栈 |
| 谁实现 | **mova 实现**（`MovaMiniCtl.showInPage`，封装 entry 的 insert/remove） | **mova 只给文档 + 示例**（宿主自己在 `builder` 里包一层 `Stack`） |

#### 方式 A：`OverlayEntry` 没有被此前那个问题排除

此前反对 `OverlayEntry` 的论据是："`Navigator` 的每个 route 本身就是根 Overlay 里的一个
entry，手工 insert 的小窗会被下一次 `push` 盖住。"这句话**只在 `rootOverlay: true`（插到根
Navigator 那个 Overlay）且追求跨路由持久化时成立**。而页内悬浮：

- `Overlay.of(context)` 默认取**最近祖先** Overlay（`rootOverlay: false`）。在一个普通页面里，
  这通常就是该 route 自己子树里的 Overlay（`Scaffold` 下若无独立 Overlay，则是 route 所在的
  那个）——宿主也可以在页面里自己包一个 `Overlay`，把范围收得更死。
- 不追求跨路由持久化，"被下一次 push 盖住"**根本不是问题**：新路由 push 上来时，旧页面连同
  它的悬浮层本来就该被盖住/切走；pop 回来又一起回来。**这正是期望行为，不是缺陷。**
- 页内悬浮的真正价值在这里：它**脱离页面自身的布局与滚动**。列表页里塞一个 `Stack` 也能浮，
  但会被 `SingleChildScrollView`/`CustomScrollView` 的裁剪与滚动带走；插到页面级 Overlay 上
  则天然独立于滚动内容，坐标系是整个页面视口。

#### 方式 B：mova 不再造一层

方式 B 的本质是宿主在 `MaterialApp.builder` 里包一层 `Stack`，`child` 就是 `Navigator`，
绘制顺序与路由栈无关。**mova 要保证的底层能力只有一个：controller 与路由生命周期解耦**
（`MovaMiniCtl` 活在 Navigator 之外，见 §1.2/Task 5）——这条保证到位，方式 B 就是水到渠成的
十几行宿主代码，不需要 mova 内部再造一层机制。

因此 `MovaMiniHost` **降级为一个可选的便利壳**（约 30 行：监听 `ctl` + `Stack` 两件事），
README 同时给出等价的手写 `Stack` 代码，宿主用哪种都行、不用也行。

#### 解耦点：`MovaMiniWindow` 不关心自己被谁挂载

这是本次修订的**核心设计约束**。小窗的全部逻辑——位置状态、拖拽、钳制、吸边、渲染面订阅、
点击回页面/关闭——收在 `MovaMiniWindow` 这一个 widget 里，它**不知道**自己是被 `OverlayEntry`
插入的还是被宿主的 `Stack` 摆放的：

```
        MovaMiniCtl（路由外真值源：api / rect / skin / mount）
                 │  ChangeNotifier
                 ▼
        MovaMiniWindow（全屏尺寸的 Stack，内部一个 Positioned 装小窗）
                 ▲                        ▲
   OverlayEntry(builder: …)      Stack(children:[child, Positioned.fill(…)])
        ↑ 方式 A（mova 实现）          ↑ 方式 B（宿主代码 / MovaMiniHost 便利壳）
```

- **`MovaMiniWindow` 自身是全屏的 `Stack`，内部才是 `Positioned`**（此前的设计是"它自己就是
  `Positioned`、必须当 `Stack` 的直接子节点"，那样就焊死在方式 B 上了）。这样：
  - 方式 A：`OverlayEntry(builder: (_) => MovaMiniWindow(...))` 直接成立——`RenderTheatre`
    给未定位 child 的是 tight 约束（= Overlay 尺寸），小窗拿到的就是整个页面视口。
  - 方式 B：`Positioned.fill(child: MovaMiniWindow(...))` 塞进宿主的 `Stack`。
  两种外壳下 `MovaMiniWindow` 的 build 输出**逐字节相同**，Task 6 有一条断言钉死这件事。
- 小窗的坐标基准 `bounds` 一律取自 **`MediaQuery.size` / 自身 `LayoutBuilder` 约束**，
  不假设"就是整块屏幕"——页内 Overlay 的尺寸可能小于屏幕（例如宿主把 Overlay 包在半屏区域里）。
  优先用 `LayoutBuilder` 拿到的实际约束当 `bounds`，`MediaQuery.padding` 只用来算 `MovaMiniInsets`。

#### 互斥：同一个 ctl 不许同时被两种方式渲染

双挂同一个 `VideoController` 是 §1.2 明令禁止的事。`MovaMiniCtl` 记一个 `MovaMiniMount`
（`page` / `persistent`），`show*` 时写入：

- `showInPage(context, api)` → `mount = page`，ctl 自己 insert entry；
- `show(api)`（纯状态，给方式 B）→ `mount = persistent`，`MovaMiniHost` 只在 `mount == persistent`
  时渲染，`page` 时渲染 `nothing`（避免宿主同时接了 host 又调 `showInPage` 时出现两个渲染面）。

`MovaMiniMount` 是纯 UI 层枚举，**不进 core**（core 只关心 `MovaState.mini` 这一个 bool，
它不该知道小窗挂在哪）。

### 1.2 画面为什么不会重新解码（本计划的技术基石）

```
宿主持有 ──▶ MovaApi (MovaEngine / MovaSwapEngine)   ← 生命周期与路由无关
                  │  renderHandle: VideoController    ← 构造期绑死，全程不变
                  ▼
   页面里的 MovaPlayer  ──卸载──▶  小窗里的 MovaPlayer  ──重新挂载
                  └─ _RenderSurface 读 api.renderHandle → Video(controller: 同一个)
```

- `MovaMpvKernel` 的 `_controller` 是构造期建立的，`dispose()` 才销毁。widget 卸载**不触发** dispose。
- `_RenderSurface` 每次 build 都重读 `api.renderHandle` 并按 `_RenderHandleKey(handle)` 做 key
  —— 句柄没变，Flutter 复用同一个 `Texture`，**不重建纹理**。
- `player.dart` 的 `ValueKey(widget.api)`：小窗与页面用的是**同一个 api 引用**，
  但它们处在树的不同位置，本来就是两次独立挂载，`initState` 各订阅一次、`dispose` 各取消一次，
  不存在订阅指向死引擎的问题。
- **唯一的可见代价：交接那一帧可能有 1 帧黑**（旧 `Texture` 已卸、新 `Texture` 未绘）。
  缓解：先挂小窗、下一帧再让页面侧的 surface 换成占位（Task 6 的 `handoff` 顺序），
  真机验证里单列一条逐帧核对（Task 10 B 组）。
- **硬约束：同一时刻只允许一个 `MovaPlayer` 持有该 api 的渲染面。** 双挂同一个
  `VideoController` 在部分平台（Android SurfaceTexture）行为未定义。`MovaMiniCtl` 用
  `MovaState.mini` 这一个真值源保证互斥：页面侧用 `_MiniHidden` 把自己整体收起来
  （与既有 `_PipHidden` 同构）。

### 1.3 落在哪一层

| 层 | 改什么 | 为什么 |
|---|---|---|
| `core/state/state.dart` | **加一个 `bool mini`**（默认 `false`） | 与 `fullscreen`/`locked`/`pip` 完全同构的纯 UI 状态位。放进 `MovaState` 的唯一理由是：组件靠 `MovaSelect` 免费拿到响应式（`_MiniHidden` 一行搞定），换成独立的 InheritedWidget 就得给每个组件再铺一套订阅 |
| `core/api.dart` | **加一个 `Future<void> setMini(bool v)`** | 与既有的 `setFullscreen`/`setLocked` 同类：纯状态 setter，不碰任何平台端口。`MovaEngine` 里 3 行实现（emit + 事件），`MovaSwapEngine` 里 1 行转发 |
| `core/events/events.dart` | 加 `MovaMiniChg` | 与 `MovaPipChg`/`MovaFullScreenChg` 同构，宿主要靠它做埋点与路由联动 |
| `core/options/mini_config.dart` | 新增 `MovaMiniConfig` | 默认值 + 配置项 + **可注入策略**三件套（项目开放性硬约束） |
| `core/mini/placement.dart` | **纯函数** `resolveMiniRect` / `snapCorner` / `MovaMiniRect` | 吸边、边界钳制、安全区避让全是纯算术，抽出来单测（项目约定："纯逻辑务必抽出来测"）。**用自定义 `MovaMiniRect`（4 个 double）而非 `Rect`**，以免给 core 引入 `dart:ui` |
| `ui/mini/**` | `MovaMiniCtl`（含 `MovaMiniMount` 与两种挂载入口）/ `MovaMiniWindow`（挂载无关的本体）/ `MovaMiniHost`（方式 B 便利壳）/ `MovaMiniSkin` | 全部 Flutter 侧；挂载方式只是外壳差异，核心逻辑只在 `MovaMiniCtl` + `MovaMiniWindow` 两处 |
| `ui/skins/default_skin.dart` | 加 `_MiniHidden`（与 `_PipHidden` 同构） | 页面侧在小窗态收起 chrome |

**core 的改动总量：一个 bool 字段 + 一个方法 + 一个事件 + 一个 config + 一个纯函数文件。**
`engine.dart` 的播放链路**一行不动**，`purity_test.dart` 的 `_mediaKitExceptions` 不变。

### 1.4 为什么**不**做成一种 `MovaComp`

考虑过"把小窗做成 `MovaComp` 体系里的一种特殊挂载方式"（问题 3 的第三条路线），**否决**：
`MovaComp` 的契约是"渲染进 `MovaSlot` 指定的**播放器叠加层区域**"，它天生活在
`MovaPlayer` 的 `Stack` **内部**；而小窗必须活在 `MovaPlayer` **外部、Navigator 之上**——
两者的坐标系与生命周期都不在一个量级。强行做成 `MovaComp` 会让组件树契约里多出一个
"这个组件不在本 Stack 里渲染"的例外，污染 0.3.0 刚立住的三层契约。
**但小窗内部的 chrome 仍然完全复用该契约**：`MovaMiniSkin implements MovaSkin`，
只 `components()` 出三个既有叶子组件，`assemble()` 简单堆叠——这是 Skin 抽象的正确用法，
也是"新皮肤零成本"这一设计意图的一次实证。

### 1.5 `MovaSwapEngine` 的经验能直接搬吗

**能搬的是结论，不是代码。** 0.4.0 已经证明过一次"引用稳定的 `MovaApi` 代理 + 组件按 api 身份重挂"
这套模型是成立的；本计划复用的正是它的**下半段**（`ValueKey(api)` 的重挂语义 + `renderHandle`
重读 + `renderEpoch` 触发面重建）。但小窗**不需要**代理层：它自始至终就是**同一个** api，
没有换引擎、没有影子引擎、没有原子换指。**不要为小窗引入第二个代理**。
唯一要做的对接是：`MovaSwapEngine` 补一行 `setMini` 转发（Task 3），
以及确认 swap 发生在小窗态时 `renderEpoch` 递增能把小窗里的 `_RenderSurface` 也刷新
（Task 9 的契约测试，二者天然同一份 `MovaSelect` 逻辑，只需断言不回归）。

### 1.6 engine 归谁 dispose（最容易踩的坑，必须写进 README）

mova 现有约定是"**宿主持有 engine**"（`MovaPlayer(api: ...)` 从不 dispose 传进来的 api）。
小窗把这条约定的后果放大了：**页面 `dispose()` 里顺手 `api.dispose()` 是最常见的错误用法**，
会在交接瞬间把正在小窗里播的引擎干掉。
对策三件：① `MovaMiniCtl.show(api)` 的文档注释明写"借用不持有，宿主负责 dispose"；
② `MovaMiniCtl` 提供 `isShowing(api)` 让页面在 `dispose` 前自检；
③ `MovaEngine.dispose()` 在 `state.mini == true` 时打一条 `assert`（debug-only，零 release 成本，
符合项目"构造期/误用不变量用 assert"的约定）。

### 1.7 方式 A 独有的坑：`OverlayEntry` 的生命周期归 ctl 管

页内悬浮多出一条方式 B 没有的风险线——**entry 的宿主 Overlay 可能先于 ctl 消失**
（页面被 pop，该 route 子树连同它的 Overlay 一起销毁），此时 ctl 若还握着那个已 remove/
已失效的 entry，下次 `hide()` 会对一个死 entry 调 `remove()`（重复 remove 抛
`'Tried to remove an OverlayEntry that is not in the Overlay'`）。三条对策：

1. `MovaMiniCtl` 内部 remove 前一律判 `entry.mounted`，并在 remove 后立刻置 `null`
   （`hide()`/`close()`/换 api 三条路径共用同一个私有 `_detachEntry()`）。
2. `showInPage` 的文档注释明写：**页面 `dispose()` 里必须调一次 `ctl.hide()` 或 `ctl.close()`**，
   否则 `MovaState.mini` 会停在 `true`（画面没人渲染，但页面侧 chrome 仍以为在小窗态）。
   demo 里正确演示一次（Task 10）。
3. `showInPage` 用的是 `Overlay.of(context)`（`rootOverlay: false`，最近祖先）。
   宿主若确实想插到根 Overlay，传 `rootOverlay: true` —— 但文档要写明：
   **那种用法会被下一次 `push` 的路由盖住**，想要跨路由持久请改用方式 B，
   别在根 Overlay 上跟路由栈较劲。

---

## 2. 文件结构

**新建（core，纯 Dart）**

| 文件 | 职责 | 任务 |
|---|---|---|
| `lib/src/core/options/mini_config.dart` | `MovaMiniConfig` + `MovaMiniCorner` | Task 1 |
| `lib/src/core/mini/placement.dart` | `MovaMiniRect` / `MovaMiniPlacement` 抽象 + `MovaCornerSnap` 默认实现 + 纯函数 `clampToBounds` | Task 4 |

**新建（ui）**

| 文件 | 职责 | 任务 |
|---|---|---|
| `lib/src/ui/mini/mini_ctl.dart` | `MovaMiniCtl extends ChangeNotifier` + `MovaMiniMount` — 路由外的真值源，含方式 A 的 `OverlayEntry` 挂载封装 | Task 5 |
| `lib/src/ui/mini/mini_host.dart` | `MovaMiniHost` — 方式 B 的便利壳（约 30 行 `Stack`，可不用） | Task 6 |
| `lib/src/ui/mini/mini_window.dart` | `MovaMiniWindow` — 挂载无关的小窗本体（全屏 `Stack` + 内部 `Positioned`）：拖拽/吸边/关闭与回页面 | Task 7 |
| `lib/src/ui/mini/mini_skin.dart` | `MovaMiniSkin implements MovaSkin` — 小窗内的极简 chrome | Task 8 |

**修改**

| 文件 | 改动 | 任务 |
|---|---|---|
| `lib/src/core/state/state.dart` | 加 `bool mini`（默认 false）+ `copyWith`/`==`/`hashCode` | Task 2 |
| `lib/src/core/api.dart` | 加 `Future<void> setMini(bool v)` | Task 3 |
| `lib/src/core/engine.dart` | 实现 `setMini`；`dispose()` 加 mini-态 assert | Task 3 |
| `lib/src/core/events/events.dart` | 加 `MovaMiniChg` | Task 3 |
| `lib/src/core/swap/swap_engine.dart` | 转发 `setMini` | Task 3 |
| `lib/src/core/compat.dart` | `MovaCtrl` 兼容层补 `setMini`（若其转发全量 API） | Task 3 |
| `lib/src/core/options/options.dart` | 加 `mini` 节 + `copyWith`/`==`/`hashCode` + export | Task 1 |
| `lib/src/ui/skins/default_skin.dart` | 加 `_MiniHidden`，套在操作层外（与 `_PipHidden` 并列） | Task 8 |
| `lib/mova.dart` | barrel 增补 6 处导出 | Task 1/4/5/6/7/8 |
| `test/support/fake_api.dart` | `FakeMovaApi` 补 `setMini` + `mini` 推送辅助 | Task 3 |
| `example/lib/mini_window_demo.dart` | **独立** demo 页（项目约定：验收 demo 不与其他 spike 混用） | Task 10 |
| `example/lib/main.dart` | `MaterialApp.builder` 接 `MovaMiniHost` + 入口 | Task 10 |
| `README.md` / `CHANGELOG.md` / `doc/SPEC.md` / `CLAUDE.md` | 文档 | Task 11 |

**测试**

`test/core/mini/placement_test.dart`、`test/core/options_test.dart`（增补）、
`test/core/state_test.dart`（增补）、`test/core/engine_test.dart`（增补）、
`test/core/swap/swap_engine_test.dart`（增补）、`test/core/openness_mini_test.dart`、
`test/ui/mini/mini_ctl_test.dart`、`test/ui/mini/mini_mount_test.dart`（**新增**：两种挂载方式
各自的行为 + 二者等价性）、`test/ui/mini/mini_window_test.dart`、`test/ui/mini/mini_skin_test.dart`、
`test/ui/player_test.dart`（增补：跨位置重挂同一 api 后渲染句柄不变）。
（原 `mini_host_test.dart` 并入 `mini_mount_test.dart`——`MovaMiniHost` 降级成便利壳后，
真正要测的是"两种外壳下同一个 `MovaMiniWindow` 行为一致"，分两个文件反而割裂。）

**测试数量推进**（基线 **709**）：
Task 1 → 717、2 → 723、3 → 735、4 → 751、5 → 765（+14，含方式 A 的 entry 生命周期）、
6 → 781（+16，两种挂载方式各 6 + 等价性 4）、7 → 795（+14，含"bounds 取外部约束"）、
8 → 803、9 → 807、10 → 807（demo 无单测）、11 → 807。

（修订前为 795；挂载层改成"两种方式并存"后净增 12 项，全部落在 Task 5/6/7。）

---

## Global Constraints

- 包名 `mova`，公开类前缀 `Mova`；`src/` 内文件名不带前缀。
- **`lib/src/core/**` 禁止 `import 'package:flutter/...'` 与 `dart:ui`**；
  `test/core/purity_test.dart` 的 `_mediaKitExceptions` 必须恒等于 `{'kernel/mpv_kernel.dart'}`，
  本阶段任何 Task 都不许改它。`core/mini/placement.dart` 因此用自定义 `MovaMiniRect`，不用 `Rect`。
- 注释规则（`CLAUDE.md`）：每个类/方法/getter/字段都要注释，**先英文一句、空行、后中文**；
  公开 API 带参数/返回/示例。本计划代码块里的注释按原样抄。
- 校验用 `flutter analyze`（0 issues），不用 `flutter build`。每个 Task 结束 `flutter test`
  全绿再 commit，信息用 `type(mova): message`。
- **既有 709 项测试一项都不许删、不许改断言**，只允许因新增字段/可选参数做纯增量修改。
- **默认关闭是硬约束**：`MovaMiniConfig.enabled` 默认 `false`；未接 `MovaMiniHost` 的宿主
  行为与今天逐字节相同。每个 Task 都要有一条"关闭时行为不变"的测试。
- 开放性契约：每个替用户做的决策必须齐**默认值 + 配置项 + 可注入策略**三样
  （Task 9 做成可执行对账测试，照抄 `openness_swap_test.dart` 的写法）。

---

## Task 1: `MovaMiniConfig` 与 `MovaOpts.mini`

先钉死配置面：默认关闭，每个决策三件套齐全。

**Files:**
- Create: `lib/src/core/options/mini_config.dart`
- Modify: `lib/src/core/options/options.dart`, `lib/mova.dart`
- Test: `test/core/options_test.dart`（追加 8 项，不动既有项）

**Interfaces / Produces:**

```dart
/// Which corner the mini window snaps to when first shown.
///
/// 小窗首次出现时吸附到哪个角。
enum MovaMiniCorner {
  /// Top-left / 左上
  topLeft,

  /// Top-right / 右上
  topRight,

  /// Bottom-left / 左下
  bottomLeft,

  /// Bottom-right / 右下（默认，最不挡内容）
  bottomRight,
}

/// Configuration for the in-app mini window (app-inline picture-in-picture).
///
/// Off by default. This feature never touches a platform PiP API — it is pure
/// Flutter compositing above the [Navigator], so it behaves identically on
/// every platform and needs no permission.
///
/// App 内小窗（应用内画中画）的配置。
///
/// 默认关闭。该特性完全不碰任何平台 PiP API——它只是在 [Navigator] 之上做纯
/// Flutter 合成，因此四端行为一致，也不需要任何权限。
class MovaMiniConfig {
  /// Master switch; [MovaMiniHost] renders nothing when `false`.
  ///
  /// 总开关；为 `false` 时 [MovaMiniHost] 不渲染任何东西。
  final bool enabled;

  /// The mini window's width in logical pixels; height follows [aspectRatio].
  ///
  /// 小窗宽度（逻辑像素）；高度由 [aspectRatio] 推出。
  final double width;

  /// Width / height of the mini window.
  ///
  /// 小窗的宽高比。
  final double aspectRatio;

  /// Inset kept between the window and every screen edge / safe-area edge.
  ///
  /// 小窗与屏幕边缘/安全区之间保留的间距。
  final double margin;

  /// Whether a drag release snaps the window to the nearest horizontal edge.
  ///
  /// 拖动松手后是否吸附到最近的水平边缘。
  final bool snapToEdge;

  /// Where the window first appears.
  ///
  /// 小窗首次出现的位置。
  final MovaMiniCorner initialCorner;

  /// Whether flinging the window off-screen dismisses it (and stops playback).
  ///
  /// 是否允许把小窗甩出屏幕以关闭它（并停止播放）。
  final bool dismissible;

  /// Snap/clamp animation duration; [Duration.zero] disables the animation.
  ///
  /// 吸边/钳制动画时长；[Duration.zero] 表示不做动画。
  final Duration settleDuration;

  /// Decides *where the window lands*; `null` uses [MovaCornerSnap] seeded
  /// from [snapToEdge]/[margin].
  ///
  /// 决定*小窗最终落点*；为 `null` 时使用由 [snapToEdge]/[margin] 构造的
  /// [MovaCornerSnap]。
  final MovaMiniPlacement? placement;

  /// Creates a mini-window configuration; disabled by default.
  ///
  /// 创建一份小窗配置；默认关闭。
  ///
  /// - [enabled]: master switch / 总开关
  /// - [width]: window width in logical px / 小窗宽度
  /// - [aspectRatio]: width over height / 宽高比
  /// - [margin]: edge inset / 边距
  /// - [snapToEdge]: snap on release / 松手吸边
  /// - [initialCorner]: first-show corner / 首次出现的角
  /// - [dismissible]: fling-away to close / 甩出关闭
  /// - [settleDuration]: settle animation / 落位动画时长
  /// - [placement]: injectable landing policy / 可注入的落点策略
  ///
  /// Example / 示例:
  /// ```dart
  /// const opts = MovaOpts(mini: MovaMiniConfig(enabled: true, width: 180));
  /// ```
  const MovaMiniConfig({
    this.enabled = false,
    this.width = 180,
    this.aspectRatio = 16 / 9,
    this.margin = 12,
    this.snapToEdge = true,
    this.initialCorner = MovaMiniCorner.bottomRight,
    this.dismissible = true,
    this.settleDuration = const Duration(milliseconds: 220),
    this.placement,
  })  : assert(width > 0, 'width must be positive'),
        assert(aspectRatio > 0, 'aspectRatio must be positive'),
        assert(margin >= 0, 'margin must not be negative');

  /// The placement policy actually in effect.
  ///
  /// 实际生效的落点策略。
  MovaMiniPlacement get effectivePlacement =>
      placement ?? MovaCornerSnap(snap: snapToEdge, margin: margin);

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回一份替换了指定字段的拷贝。
  MovaMiniConfig copyWith({ /* 每个字段一个可空参数 */ });

  // == / hashCode 覆盖全部字段，写法照抄 MovaSwapConfig。
}
```

`MovaOpts` 加一节：`final MovaMiniConfig mini;`，构造器 `this.mini = const MovaMiniConfig()`，
`copyWith`/`==`/`hashCode` 同步，`options.dart` 顶部 `export 'mini_config.dart';`。

**Test assertions:**
- 默认构造 `enabled` 为 `false`、`width == 180`、`aspectRatio == 16/9`、
  `initialCorner == MovaMiniCorner.bottomRight`。
- `MovaOpts().mini == const MovaMiniConfig()`；`MovaOpts()` 的 `==`/`hashCode` 纳入 `mini`。
- `copyWith(enabled: true)` 只改那一个字段。
- `effectivePlacement` 在 `placement == null` 时返回 `MovaCornerSnap`，非空时原样返回。
- `assert`：`width: 0` / `aspectRatio: -1` / `margin: -1` 各抛 `AssertionError`。
- **关闭态**：`const MovaOpts()` 与 0.5.0 的默认值逐字段相等（回归保护）。

---

## Task 2: `MovaState.mini`

**Files:** Modify `lib/src/core/state/state.dart`; Test `test/core/state_test.dart`（追加 6 项）

```dart
  /// Whether the picture is currently rendered in the in-app mini window.
  ///
  /// Orthogonal to [pip] (system-level) and mutually exclusive with it and
  /// with [fullscreen]: the engine clears the other two when this turns on.
  ///
  /// 画面当前是否渲染在 App 内小窗里。
  ///
  /// 与 [pip]（系统级）正交，且与它和 [fullscreen] 互斥：该位置真时 engine 会
  /// 清掉另外两个。
  final bool mini;
```

`copyWith`/`==`/`hashCode` 同步（`mini` 是非空 bool，照抄 `fullscreen` 的写法，
**不要**用 `clearXxx` 那一套）。

**Test assertions:**
- `const MovaState().mini` 为 `false`。
- `copyWith(mini: true).mini` 为 `true`，其余字段不变。
- `copyWith()`（空调用）不改 `mini`。
- `==`/`hashCode` 纳入 `mini`（两个只差 `mini` 的实例不相等、hash 不同）。
- 既有 709 项里任何构造 `MovaState` 的断言都不受影响（新增字段有默认值）。

---

## Task 3: `MovaApi.setMini` + `MovaMiniChg` + 互斥语义

**Files:**
- Modify: `lib/src/core/api.dart`, `lib/src/core/engine.dart`,
  `lib/src/core/events/events.dart`, `lib/src/core/swap/swap_engine.dart`,
  `lib/src/core/compat.dart`, `test/support/fake_api.dart`
- Test: `test/core/engine_test.dart`（+8）、`test/core/swap/swap_engine_test.dart`（+2）、
  `test/core/api_test.dart`（+2）

```dart
// api.dart
  /// Enters or leaves the in-app mini window.
  ///
  /// Pure UI state: no platform channel, no PiP API. The host's
  /// [MovaMiniHost] is what actually renders the window; this method is the
  /// single source of truth both it and the page-side chrome read from.
  /// Entering implicitly leaves fullscreen (they cannot both be meaningful).
  ///
  /// 进入或退出 App 内小窗。
  ///
  /// 纯 UI 状态：不走任何平台通道，不碰 PiP API。真正渲染小窗的是宿主侧的
  /// [MovaMiniHost]；本方法只是它与页面侧 chrome 共同读取的唯一真值源。
  /// 进入小窗会隐式退出全屏（二者不可能同时有意义）。
  ///
  /// - [v]: `true` 进入小窗，`false` 退出 / enter when `true`
  ///
  /// Example / 示例:
  /// ```dart
  /// await api.setMini(true);   // 页面 chrome 自动收起，宿主的 MovaMiniHost 弹出小窗
  /// ```
  Future<void> setMini(bool v);
```

```dart
// engine.dart
  @override
  Future<void> setMini(bool v) async {
    if (state.mini == v) return;               // 幂等，避免无谓事件
    if (v && state.fullscreen) await setFullscreen(false);
    _state.emit(state.copyWith(mini: v));
    _events.add(MovaMiniChg(v));
  }
```

`dispose()` 首行加：

```dart
    // Disposing while the mini window still renders this engine leaves the
    // host painting a dead texture — almost always a page that disposed the
    // engine it had just handed off. Debug-only, zero release cost.
    //
    // 小窗仍在渲染本引擎时 dispose，会让宿主继续绘制一个已死的纹理——几乎总是
    // 某个页面把刚交接出去的引擎顺手销毁了。仅 debug 生效，release 零成本。
    assert(!state.mini, 'dispose() while MovaState.mini is true — see MovaMiniCtl docs');
```

`MovaMiniChg extends MovaEvent`（带 `final bool mini;`，照抄 `MovaPipChg`）。
`swap_engine.dart` 加一行 `Future<void> setMini(bool v) => _active.setMini(v);`。
`fake_api.dart` 的 `FakeMovaApi` 记录调用并暴露 `emitMini(bool)`。

**Test assertions:**
- `setMini(true)` → `state.mini` 为真、发出一次 `MovaMiniChg(true)`。
- 重复 `setMini(true)` **不再发事件**（幂等）。
- 全屏态下 `setMini(true)` → `fullscreen` 变 false 且先发 `MovaFullScreenChg(false)` 再发
  `MovaMiniChg(true)`（事件顺序断言）。
- `setMini(false)` 不会把 `fullscreen` 改回去。
- `setMini` 不触碰任何 Port（用假 Port 断言零调用：`pip`/`orientation`/`brightness`/`volume`）。
- `MovaSwapEngine.setMini` 转发到当前生效引擎；swap 后转发到新引擎。
- mini 态下 `dispose()` 在 debug 触发 `AssertionError`；`setMini(false)` 后正常 dispose。

---

## Task 4: 落点纯逻辑 `core/mini/placement.dart`

全部是算术，**零 Flutter 依赖**，是本计划单测密度最高的一块。

```dart
/// An axis-aligned rectangle in logical pixels, in the host window's
/// coordinate space. A tiny stand-in for `Rect`: `core/` must not import
/// `dart:ui`.
///
/// 宿主窗口坐标系下的轴对齐矩形（逻辑像素）。`Rect` 的极简替身：`core/`
/// 不许 import `dart:ui`。
class MovaMiniRect {
  /// Creates the rectangle from its left/top corner and size.
  ///
  /// 由左上角与尺寸创建矩形。
  const MovaMiniRect({required this.left, required this.top,
                      required this.width, required this.height});

  final double left, top, width, height;

  /// Right edge / 右边界
  double get right => left + width;

  /// Bottom edge / 下边界
  double get bottom => top + height;

  /// Returns a copy translated by ([dx], [dy]).
  ///
  /// 返回平移 ([dx], [dy]) 后的拷贝。
  MovaMiniRect shift(double dx, double dy);

  // == / hashCode / toString 全覆盖（测试里要直接比较矩形）。
}

/// The edge insets kept clear of system chrome (status bar, home indicator).
///
/// 需要避开系统 chrome（状态栏、Home 指示条）的内边距。
class MovaMiniInsets { const MovaMiniInsets({this.left = 0, this.top = 0,
                                             this.right = 0, this.bottom = 0}); /* ... */ }

/// Decides where the mini window lands after a drag ends.
///
/// Pure logic, injected via [MovaMiniConfig.placement] so a host can replace
/// the built-in corner snapping with its own (free positioning, magnetic
/// grid, single-edge dock, …) without forking the widget.
///
/// 决定小窗在一次拖动结束后落在哪里。
///
/// 纯逻辑，经 [MovaMiniConfig.placement] 注入，宿主可以在不 fork widget 的
/// 前提下把内置的吸角换成自己的（自由摆放、磁吸网格、单边停靠……）。
abstract class MovaMiniPlacement {
  /// Returns the resting rectangle for [current] inside [bounds].
  ///
  /// - [current]: where the finger released it / 手指松开时的位置
  /// - [bounds]: the host window rect / 宿主窗口矩形
  /// - [insets]: system-chrome insets to avoid / 要避开的系统内边距
  /// - [velocityX]/[velocityY]: release velocity in px/s / 松手速度
  ///
  /// 返回 [current] 在 [bounds] 内的最终停靠矩形。
  MovaMiniRect settle(MovaMiniRect current, {required MovaMiniRect bounds,
    required MovaMiniInsets insets, double velocityX = 0, double velocityY = 0});
}

/// Built-in placement: clamps into bounds, then (when [snap]) slides
/// horizontally to whichever side the window's center is nearer, honouring
/// [margin] and the safe-area [MovaMiniInsets].
///
/// 内置落点策略：先钳进边界，再（[snap] 为真时）沿水平方向滑到窗口中心更靠近
/// 的那一侧，并遵守 [margin] 与安全区 [MovaMiniInsets]。
class MovaCornerSnap implements MovaMiniPlacement { /* ... */ }

/// Clamps [r] so it lies fully inside [bounds] minus [insets] and [margin].
/// Exposed separately because the drag itself needs it every frame, while
/// snapping only happens on release.
///
/// 钳制 [r] 使其完全落在 [bounds] 去掉 [insets] 与 [margin] 后的区域内。
/// 单独暴露是因为拖动过程每帧都要用它，而吸边只在松手时发生。
MovaMiniRect clampToBounds(MovaMiniRect r, {required MovaMiniRect bounds,
  required MovaMiniInsets insets, double margin = 0});

/// Returns the rect for [corner] — the window's first appearance.
///
/// 返回 [corner] 对应的矩形——小窗首次出现的位置。
MovaMiniRect rectForCorner(MovaMiniCorner corner, {required double width,
  required double height, required MovaMiniRect bounds,
  required MovaMiniInsets insets, double margin = 0});
```

**Test assertions**（`test/core/mini/placement_test.dart`，16 项）：
- `clampToBounds`：完全在内 → 原样返回（同一实例语义可不保，值相等即可）；
  左/上/右/下各越界一次 → 各自被推回 margin+inset 处；
  窗口比可用区还大 → 取左上对齐而非负宽（退化情形不得产生负坐标）。
- `rectForCorner` 四个角各一条，断言精确坐标（含 inset + margin 叠加）。
- `MovaCornerSnap.settle`：中心在左半 → 贴左；中心在右半 → 贴右；
  `snap: false` → 只钳制不吸边；**垂直方向永远只钳制不吸**（明确的产品决策，需断言）。
- 松手速度：`velocityX` 大幅指向左但中心在右半 → **以速度为准贴左**（惯性优先，一条断言钉死）。
- 安全区：`insets.bottom = 34`（iPhone home 条）时贴底不压 home 条。
- `MovaMiniRect.shift` / `==` / `hashCode`。

---

## Task 5: `MovaMiniCtl` — 路由外的真值源（两种挂载方式的共同底座）

**本 Task 是"挂载方式解耦"的落点**：ctl 持有全部与挂载无关的状态（api / skin / rect /
onClosed），只多一个 `mount` 字段区分当前走的是哪条路；方式 A 的 `OverlayEntry` 生命周期
也收在这里（§1.7），方式 B 则完全不经过 ctl 的挂载代码——它只读 ctl 的状态。

```dart
/// How the mini window is mounted into the widget tree.
///
/// 小窗以何种方式挂进 widget 树。
enum MovaMiniMount {
  /// Not mounted. / 未挂载。
  none,

  /// Inserted as an [OverlayEntry] into the nearest ancestor [Overlay]
  /// (in-page floating; disappears with its page).
  ///
  /// 作为 [OverlayEntry] 插入最近祖先 [Overlay]（页内悬浮，随页面消失）。
  page,

  /// Rendered by a host-level [Stack] under `MaterialApp.builder`
  /// (survives route changes).
  ///
  /// 由 `MaterialApp.builder` 下的宿主级 [Stack] 渲染（跨路由存活）。
  persistent,
}
```

```dart
/// The route-independent holder of whatever is currently playing in the mini
/// window.
///
/// Lives outside the [Navigator] (a host-level singleton, or provided however
/// the host prefers) so that popping the page that started playback does not
/// take the engine down with it. It **borrows** the [MovaApi] — it never
/// creates and never disposes one; disposing stays the host's job, exactly as
/// with [MovaPlayer].
///
/// 当前在小窗里播放的内容的持有者，独立于路由。
///
/// 它活在 [Navigator] 之外（宿主级单例，或宿主偏好的任何注入方式），使得弹出
/// 发起播放的那个页面不会把引擎一起带走。它**借用** [MovaApi]——既不创建也不
/// 销毁；销毁仍然是宿主的职责，与 [MovaPlayer] 的约定完全一致。
///
/// Example / 示例:
/// ```dart
/// final mini = MovaMiniCtl();
///
/// // 方式 A：页内悬浮（mova 负责插 OverlayEntry）
/// await mini.showInPage(context, api);
///
/// // 方式 B：跨路由持久（宿主自己在 MaterialApp.builder 里放 Stack）
/// // MaterialApp(builder: (c, child) => MovaMiniHost(ctl: mini, child: child!))
/// await mini.show(api, skin: const MovaMiniSkin());
/// Navigator.of(context).pop();   // 引擎不受影响，画面在小窗里继续
/// ```
class MovaMiniCtl extends ChangeNotifier {
  /// The api currently rendered in the mini window; `null` when hidden.
  ///
  /// 当前渲染在小窗里的 api；隐藏时为 `null`。
  MovaApi? get api => _api;

  /// The skin used inside the mini window.
  ///
  /// 小窗内使用的皮肤。
  MovaSkin get skin => _skin;

  /// The window's current rectangle; `null` before the first layout.
  ///
  /// 小窗当前矩形；首次布局前为 `null`。
  MovaMiniRect? get rect => _rect;

  /// How the window is currently mounted; [MovaMiniMount.none] when hidden.
  ///
  /// 当前挂载方式；隐藏时为 [MovaMiniMount.none]。
  MovaMiniMount get mount => _mount;

  /// Hands [api] to the mini window and flips `MovaState.mini` on, **without
  /// mounting anything itself** — a host-level [Stack] (e.g. [MovaMiniHost]
  /// under `MaterialApp.builder`) is what renders it. Mount B / 方式 B。
  ///
  /// Idempotent for the same [api]. Showing a different [api] while one is
  /// already up first flips the previous one's `mini` back off (it is never
  /// disposed here).
  ///
  /// 把 [api] 交给小窗并置起 `MovaState.mini`，但**自己不挂载任何东西**——
  /// 真正渲染它的是宿主级 [Stack]（例如 `MaterialApp.builder` 下的
  /// [MovaMiniHost]）。即方式 B。
  ///
  /// 同一个 [api] 重复调用是幂等的。已有小窗时 show 另一个 [api]，会先把前一个
  /// 的 `mini` 置回 false（此处永不 dispose 它）。
  Future<void> show(MovaApi api, {MovaSkin skin = const MovaMiniSkin()});

  /// Same as [show], but also inserts an [OverlayEntry] into the [Overlay]
  /// nearest to [context], so the window floats inside that page — free of the
  /// page's own scrolling and layout. Mount A / 方式 A。
  ///
  /// The entry lives and dies with that page's [Overlay]: popping the page
  /// takes the window with it, which is exactly what in-page floating means.
  /// For a window that must survive route changes use [show] + a host-level
  /// [Stack] instead (see README); passing [rootOverlay] `true` is **not** the
  /// way to get that — an entry in the root overlay is buried by the next
  /// `push`.
  ///
  /// The page **must** call [hide] or [close] in its `dispose()`, otherwise
  /// `MovaState.mini` stays `true` with nothing rendering it.
  ///
  /// 与 [show] 相同，但额外向离 [context] 最近的 [Overlay] 插入一个
  /// [OverlayEntry]，使小窗悬浮在那个页面内部——不受该页面自身滚动与布局影响。
  /// 即方式 A。
  ///
  /// entry 与该页面的 [Overlay] 同生共死：页面被 pop，小窗随之消失——这正是
  /// "页内悬浮"的语义。需要跨路由存活请改用 [show] + 宿主级 [Stack]（见
  /// README）；把 [rootOverlay] 传 `true` **不是**实现它的办法——插在根 overlay
  /// 里的 entry 会被下一次 `push` 埋掉。
  ///
  /// 页面**必须**在 `dispose()` 里调一次 [hide] 或 [close]，否则
  /// `MovaState.mini` 会停在 `true` 而无人渲染。
  ///
  /// - [context]: locates the target [Overlay] / 用于定位目标 [Overlay]
  /// - [api]: the borrowed engine / 借用的引擎
  /// - [skin]: chrome inside the window / 小窗内的皮肤
  /// - [rootOverlay]: insert into the root overlay instead / 改插根 overlay
  ///
  /// Example / 示例:
  /// ```dart
  /// // 列表页里点"小窗播放"：
  /// await mini.showInPage(context, api);
  /// // 页面 dispose 里：
  /// if (mini.isShowing(api)) await mini.hide();
  /// ```
  Future<void> showInPage(BuildContext context, MovaApi api,
      {MovaSkin skin = const MovaMiniSkin(), bool rootOverlay = false});

  /// Takes the picture back out of the mini window, leaving playback running.
  ///
  /// Use this when the user taps the window to return to the full page: the
  /// page remounts a [MovaPlayer] on the same api and playback never stops.
  ///
  /// 把画面从小窗里收回，播放继续。
  ///
  /// 用户点小窗回到整页时用它：页面用同一个 api 重新挂载 [MovaPlayer]，
  /// 播放全程不中断。
  Future<void> hide();

  /// Closes the mini window and pauses playback, then notifies [onClosed].
  ///
  /// Still does not dispose the api — the host decides that in [onClosed].
  ///
  /// 关闭小窗并暂停播放，随后回调 [onClosed]。
  ///
  /// 仍然不 dispose api——由宿主在 [onClosed] 里决定。
  Future<void> close();

  /// Whether [candidate] is the api the mini window currently renders.
  ///
  /// Page `dispose()` should consult this before disposing its engine.
  ///
  /// [candidate] 是否就是小窗当前渲染的那个 api。
  /// 页面 `dispose()` 在销毁引擎前应先问这一句。
  bool isShowing(MovaApi candidate) => identical(_api, candidate);

  /// Called after [close]; the host's hook for disposing the engine.
  ///
  /// [close] 之后触发；宿主销毁引擎的挂钩。
  void Function(MovaApi api)? onClosed;

  /// Updates the window rectangle (called by [MovaMiniWindow] while dragging).
  ///
  /// 更新小窗矩形（拖动时由 [MovaMiniWindow] 调用）。
  void setRect(MovaMiniRect r);
}
```

私有实现要点：`_detachEntry()` 一处集中处理 entry 的摘除——`_entry?.mounted == true` 才
`remove()`，随后无条件置 `null`；`hide()` / `close()` / 换 api 三条路径都只走它，
绝不在别处 `remove()`（§1.7 的重复 remove 崩溃点）。
`_mount` 在 `show` 时置 `persistent`、`showInPage` 时置 `page`、`hide`/`close` 时置 `none`。

**Test assertions**（`test/ui/mini/mini_ctl_test.dart`，14 项）：
- `show(api)` → `api` 非空、`mount == persistent`、`ctl` 通知一次、
  `FakeMovaApi.setMini(true)` 被调一次、**没有**插入任何 `OverlayEntry`。
- `showInPage(context, api)` → `mount == page`、目标 Overlay 里多出恰好一个 entry、
  `setMini(true)` 被调一次。
- `showInPage` 后 `hide()` → entry 被摘、`mount == none`；**再调一次 `hide()` 不抛**
  （重复 remove 防护，§1.7 的核心断言）。
- 页面被 pop 导致宿主 Overlay 销毁后再调 `hide()` **不抛**（`entry.mounted` 判据生效）。
- 同 api 重复 `show` → 只通知一次、`setMini` 不重复调。
- 换 api `show` → 旧 api 收到 `setMini(false)`、新 api 收到 `setMini(true)`、
  **旧 api 未被 dispose**（断言 `FakeMovaApi.disposed == false`）。
- `hide()` → `api` 归 null、旧 api `setMini(false)`、**未调 `pause()`**。
- `close()` → 调了 `pause()`、`setMini(false)`、`onClosed` 收到那个 api、**未 dispose**。
- `isShowing` 用 `identical` 而非 `==`（两个 equal-but-not-identical 的假 api 断言为 false）。
- 隐藏态调 `hide()`/`close()` 是安全空操作。
- `setRect` 通知监听者。
- `dispose()` 后再 `show` 不抛（或按 ChangeNotifier 契约抛 —— 选定其一并断言）。

---

## Task 6: 两种挂载方式（方式 A 由 mova 实现，方式 B 只给便利壳 + 文档）

**本 Task 的验收核心不是"host 能不能渲染"，而是"同一个 `MovaMiniWindow` 在两种外壳下
行为一致"**——这是 §1.1 解耦约束的可执行证明。

### 6a. 方式 A：`OverlayEntry`（mova 实现，落在 Task 5 的 `showInPage` 里）

Task 5 已给出 API 形状，本 Task 补它的渲染契约：

```dart
  _entry = OverlayEntry(
    // 不用 Positioned/maintainState：MovaMiniWindow 自己是全屏 Stack，
    // RenderTheatre 给未定位 child 的是 tight 约束（= Overlay 尺寸）。
    builder: (_) => MovaMiniWindow(ctl: this, api: api, config: cfg),
  );
  Overlay.of(context, rootOverlay: rootOverlay).insert(_entry!);
```

### 6b. 方式 B：`MovaMiniHost` —— 三十行便利壳，**可以不用**

```dart
/// A convenience wrapper that composites the mini window above the whole app.
///
/// Optional: it is exactly a [Stack] of your app content plus the window, and
/// hosts that prefer to own that [Stack] can skip this class entirely — see the
/// README for the equivalent hand-written snippet. Use it in
/// [MaterialApp.builder], where [child] is the [Navigator] itself, so the
/// window is composited above every pushed route.
///
/// Renders nothing while [MovaMiniCtl.api] is `null`, while
/// [MovaMiniConfig.enabled] is `false`, or while the window is mounted the
/// other way ([MovaMiniMount.page]) — the same api must never have two
/// rendering surfaces.
///
/// 把小窗合成到整个 App 之上的便利壳。
///
/// 可选：它就是"App 内容 + 小窗"两层 [Stack]，想自己掌控那个 [Stack] 的宿主
/// 完全可以不用它——README 里给了等价的手写代码。用在 [MaterialApp.builder]
/// 里，[child] 就是 [Navigator] 本身，因此小窗合成在所有已压入路由之上。
///
/// [MovaMiniCtl.api] 为 `null`、[MovaMiniConfig.enabled] 为 `false`、或小窗正以
/// 另一种方式挂载（[MovaMiniMount.page]）时，它什么都不渲染——同一个 api 绝不
/// 允许有两个渲染面。
///
/// Example / 示例:
/// ```dart
/// MaterialApp(
///   builder: (context, child) => MovaMiniHost(ctl: miniCtl, child: child!),
///   home: const HomePage(),
/// )
/// ```
class MovaMiniHost extends StatefulWidget {
  const MovaMiniHost({super.key, required this.ctl, required this.child});

  /// The route-independent mini-window state. / 独立于路由的小窗状态。
  final MovaMiniCtl ctl;

  /// The app content (normally the [Navigator]). / App 内容（通常是 [Navigator]）。
  final Widget child;
}
```

实现要点（`_MovaMiniHostState`）：
- `initState` 里 `widget.ctl.addListener(_onCtl)`，`didUpdateWidget` 里换监听，`dispose` 里摘。
- `build`：
  ```dart
  final api = widget.ctl.api;
  final cfg = api?.options.mini ?? const MovaMiniConfig();   // 配置跟着 api 走
  return Stack(children: [
    widget.child,
    if (api != null && cfg.enabled && widget.ctl.mount == MovaMiniMount.persistent)
      Positioned.fill(
        child: MovaMiniWindow(
          key: const ValueKey('movaMiniWindow'),
          ctl: widget.ctl, api: api, config: cfg),
      ),
  ]);
  ```
- **`Positioned.fill` 在这里，不在 `MovaMiniWindow` 里**——小窗本体必须保持"挂载无关"
  （§1.1），它内部自己有 `Stack`+`Positioned`。
- `Directionality`/`MediaQuery` 在 `MaterialApp.builder` 的位置上**已经可用**，无需自建。
- README 给出等价手写片段（宿主不想用本类时照抄）：
  ```dart
  builder: (context, child) => Stack(children: [
    child!,
    if (miniCtl.api != null)      // 自行加 ListenableBuilder 订阅 miniCtl
      Positioned.fill(child: MovaMiniWindow(ctl: miniCtl, api: miniCtl.api!,
                                            config: miniCtl.api!.options.mini)),
  ]),
  ```

**Test assertions**（`test/ui/mini/mini_mount_test.dart`，16 项）：

*方式 B（6 项）*
- `ctl.api == null` → 树里找不到 `MovaMiniWindow`，且 `child` 正常渲染。
- `cfg.enabled == false` → 同上（**关闭态硬约束**）。
- `show(api)` 后 pump → 找到 exactly one `MovaMiniWindow`。
- **跨路由存活**：带 `MaterialApp.builder` 的两页应用 → `show` → `Navigator.push` 新页 →
  小窗仍在树中且**在新页之上**（`tester.getTopLeft` + hit-test 断言小窗接得到点击）；
  `pop` 回去后仍在。
- `hide()` 后小窗消失、`child` 不受影响。
- `ctl` 实例被替换（`didUpdateWidget`）时监听正确迁移；host 自身 dispose 不 dispose `ctl`。

*方式 A（6 项）*
- `showInPage(context, api)` → 该页面的 Overlay 里出现 exactly one `MovaMiniWindow`。
- **不受页面滚动影响**：页面是 `ListView`，`tester.drag` 滚列表 → 小窗 `getTopLeft` 不变
  （这是页内悬浮相对"页面里塞个 Stack"的核心价值，必须钉死）。
- 在页内小窗态下 `Navigator.push` 新页 → 小窗**被新页盖住**（hit-test 打不到）——
  这是**期望行为**，断言它以防后人当 bug 修。
- `Navigator.pop` 掉承载页 → entry 随 Overlay 消失，且此后调 `hide()` 不抛。
- 页内拖拽正常：`tester.drag` 小窗本体 → 位移生效、被钳在页面视口内。
- `enabled == false` 时 `showInPage` 不插 entry（**关闭态硬约束**）。

*两种方式等价（4 项，§1.1 解耦约束的可执行证明）*
- 同一 `ctl`+`api`+`config`，分别用 `OverlayEntry` 外壳与 `Positioned.fill` 外壳
  `pumpWidget`，**`MovaMiniWindow` 的首帧 `getRect` 相等**。
- 两种外壳下拖拽 100px 的落点相等。
- 两种外壳下点画面都触发 `ctl.hide()`、点关闭都触发 `ctl.close()`。
- **互斥**：宿主同时接了 `MovaMiniHost` 又调 `showInPage` → 树里 `MovaMiniWindow`
  **仍然只有一个**（host 因 `mount == page` 不渲染）；页面侧 `MovaPlayer` 在 `mini` 为真时
  不渲染 `_RenderSurface`（配合 Task 8 的 `_MiniHidden`），断言全树渲染面只有一个。

---

## Task 7: `MovaMiniWindow` — 可拖拽的框（**挂载无关**）

```dart
/// The draggable mini window itself, holding a [MovaPlayer] on the borrowed
/// api.
///
/// **Mount-agnostic by design**: it fills whatever box it is given and does its
/// own positioning inside, so the very same widget works as an [OverlayEntry]'s
/// child (in-page floating, via [MovaMiniCtl.showInPage]) and as a
/// `Positioned.fill` child of a host-level [Stack] (persistent floating, via
/// [MovaMiniHost]). It must never assume which one it is in, and must never be
/// a [Positioned] itself.
///
/// Drag moves it (clamped every frame); release hands the rect to
/// [MovaMiniConfig.effectivePlacement] and animates to the result. Tapping the
/// picture calls [MovaMiniCtl.hide]; tapping the close affordance calls
/// [MovaMiniCtl.close].
///
/// 可拖拽的小窗本体，内部用借来的 api 挂一个 [MovaPlayer]。
///
/// **设计上与挂载方式无关**：它撑满外部给它的盒子，在盒子内部自行定位，因此同一个
/// widget 既能当 [OverlayEntry] 的 child（页内悬浮，经 [MovaMiniCtl.showInPage]），
/// 也能当宿主级 [Stack] 的 `Positioned.fill` child（持久悬浮，经 [MovaMiniHost]）。
/// 它绝不许假设自己在哪一种里，也绝不许自己就是 [Positioned]。
///
/// 拖动即移动（每帧钳制）；松手把矩形交给 [MovaMiniConfig.effectivePlacement]
/// 并动画到结果。点画面调 [MovaMiniCtl.hide]；点关闭按钮调 [MovaMiniCtl.close]。
class MovaMiniWindow extends StatefulWidget { /* ctl / api / config */ }
```

实现要点：
- **根节点是 `LayoutBuilder` → `Stack(fit: StackFit.expand)`，小窗是它内部的
  `AnimatedPositioned`**。`bounds` 取 `LayoutBuilder` 的 `constraints.biggest`
  （**不是** `MediaQuery.size`）——页内 Overlay 的尺寸可能小于整块屏幕。
  `MediaQuery.padding` 只用来算 `MovaMiniInsets`。
- 位置状态 `MovaMiniRect _rect`，首帧由 `rectForCorner(config.initialCorner, ...)` 播种。
- `GestureDetector(onPanUpdate:)` → `_rect = clampToBounds(_rect.shift(dx, dy), ...)` → `setState`。
  **用 `GestureDetector` 而非 `Draggable`**：`Draggable`/`DragTarget` 是为"拖到某个目标区域放下"
  设计的，会创建 feedback widget 的**第二棵子树**——对一个持有 `Texture` 的播放器来说等于
  在拖动期间凭空多挂一个渲染面，正是 §1.2 明令禁止的事。
- `onPanEnd` → `config.effectivePlacement.settle(...)` → `AnimatedPositioned`（
  `duration: config.settleDuration`）动到目标；`settleDuration == Duration.zero` 时直接跳。
- `dismissible` 且松手速度超阈值并指向屏幕外 → `ctl.close()`。
- 内容：`ClipRRect` + `Material(elevation:)` 包 `MovaPlayer(api: api, skin: ctl.skin,
  autoLoadQualities: false)` —— **`autoLoadQualities: false` 是必须的**，否则每次进小窗都会
  重新探测一次 HLS 档位。
- `MediaQuery.of(context).padding` → `MovaMiniInsets`；`LayoutBuilder` 约束 → `bounds`。
  尺寸变化（转屏、窗口 resize、承载 Overlay 变大变小）在 `LayoutBuilder` 重建时重新
  `clampToBounds`（**转屏后小窗不能跑到可用区外**），比 `didChangeDependencies` 更可靠——
  后者拿不到页内 Overlay 自身的尺寸变化。

**Test assertions**（`test/ui/mini/mini_window_test.dart`，14 项）：
- 首帧位置 == `rectForCorner(bottomRight, ...)`（四个角各一条参数化断言 → 4 项）。
- `tester.drag` 100px → `getTopLeft` 相应位移；拖出边界 → 被钳回。
- 松手后落点 == `effectivePlacement.settle` 的返回值（注入一个固定返回的假 placement，
  断言 widget **确实用了注入的策略**而非内置的 —— 开放性的可执行证明）。
- 点画面 → `ctl.hide()` 被调，`close()` 未被调。
- 点关闭按钮 → `ctl.close()` 被调。
- `dismissible: false` 时高速甩出不关闭，只被钳回。
- 外部约束变化（模拟转屏 / 承载 Overlay 缩小）→ 小窗仍完全在可用区内。
- **`bounds` 取自外部约束而非屏幕**：把 `MovaMiniWindow` 放进一个半屏大小的盒子里，
  首帧落点按**那个盒子**算（而不是 `MediaQuery.size`）——页内挂载正确性的关键断言。
- `MovaMiniWindow` 本身**不是** `Positioned`（`expect(find.byType(MovaMiniWindow)` 的
  直接父节点不要求是 `Stack`；用 `tester.widget` 断言其 build 出的根为 `LayoutBuilder`）。
- 内部 `MovaPlayer` 的 `autoLoadQualities` 为 `false`（用 `tester.widget<MovaPlayer>` 断言）。
- 拖动期间树里**只有一个** `MovaPlayer`（证明没用 `Draggable` 的 feedback 复制子树）。

---

## Task 8: `MovaMiniSkin` + 页面侧 `_MiniHidden`

**`MovaMiniSkin`**：`components()` 只给三个——`CenterPlayComponent()`（中央播放/暂停）、
`BufferingComponent()`、加一个新的极简 `MiniCloseComponent()`（`MovaSlot.top`，一个 ✕）。
`assemble()` 就是 `Stack([Positioned.fill(video), ...slots[top], ...slots[center]])`。
**不复用 `MovaDefSkin`**：180px 宽的框里塞进度条/清晰度/全屏按钮毫无意义，且它的
`_BarVisibility` 自动隐藏在小窗里是负担。

**`_MiniHidden`**（`default_skin.dart`，紧挨 `_PipHidden` 放，注释同构）：

```dart
/// Hides [child] outright while [MovaState.mini] is active.
///
/// The picture has been handed to the in-app mini window, which carries its
/// own minimal chrome ([MovaMiniSkin]); the page-side chrome would otherwise
/// keep painting over a surface that is no longer there.
///
/// [MovaState.mini] 生效期间直接隐藏 [child]。
///
/// 画面已交给 App 内小窗，小窗自带极简 chrome（[MovaMiniSkin]）；否则页面侧的
/// chrome 会继续绘制在一个已经不在那里的画面之上。
class _MiniHidden extends StatelessWidget { /* 与 _PipHidden 逐字同构 */ }
```

套在 `buildOperableLayer` 里，与 `_PipHidden` 并列：`_MiniHidden(child: _PipHidden(child: _LockedHidden(...)))`。

**页面侧的画面**：`MovaPlayer.surface` 已经是现成的口子——demo 里页面在 `mini` 为真时传一个
占位（`ColoredBox` + "正在小窗播放" 文案），**不需要给 `MovaPlayer` 加任何新参数**。
这条要写进 README：库不替宿主决定占位长什么样。

**Test assertions**（`test/ui/mini/mini_skin_test.dart` 8 项）：
- `MovaMiniSkin().components()` 恰好三个，`name` 分别为 `centerPlay`/`buffering`/`miniClose`。
- 小窗树里**没有** seek bar / 清晰度按钮 / 全屏按钮（三条 `findsNothing`）。
- 点 `miniClose` 触发注入的回调。
- `mini: true` 时 `MovaDefSkin` 的 top/bottom/gesture 槽位组件全部 `findsNothing`，
  而常驻层的锁定按钮仍在（与 `_PipHidden` 的既有语义一致）。
- `mini: false` 时一切照旧（**关闭态回归**）。

---

## Task 9: 开放性对账 + 契约测试

照抄 `test/core/openness_swap_test.dart` 的写法，做成可执行清单
（`test/core/openness_mini_test.dart`，4 项）：

| 替用户做的决策 | 默认值 | 配置项 | 可注入策略 |
|---|---|---|---|
| **小窗挂在哪** | 不替宿主决定 | `show`（方式 B）/ `showInPage`（方式 A） | 宿主可完全绕开两者，自己把 `MovaMiniWindow` 放进任意容器 |
| 小窗多大 | `width: 180`, `16/9` | `MovaMiniConfig.width/aspectRatio` | —（数值即策略） |
| 落在哪 | 右下角 | `initialCorner`/`snapToEdge`/`margin` | `MovaMiniPlacement` |
| 小窗里放什么 chrome | `MovaMiniSkin` | `MovaMiniCtl.show(skin:)` | 任意 `MovaSkin` |
| 关闭后引擎怎么办 | 不 dispose | `MovaMiniCtl.onClosed` | 宿主回调 |
| 页面侧占位画什么 | 库不决定 | `MovaPlayer.surface` | 任意 `Widget` |

外加两条与 0.4.0/0.5.0 的交叉契约测试（`test/ui/player_test.dart` 增补，2 项）：
- **同一 api 在两个树位置先后挂载，`renderHandle` 不变**：`_RenderHandleKey` 的值在
  卸载→重挂前后相等（这是"不重新解码"的可执行证明，替代无法在单测里做的真机验证）。
- **mini 态下发生 swap**：`renderEpoch` 递增能让小窗里的 `_RenderSurface` 重建
  （与页面内的行为一致，断言不回归）。

---

## Task 10: example demo（独立页，不与既有 spike 混用）

`example/lib/mini_window_demo.dart` —— 项目约定"验收 demo 要为该功能单独建一个页面"。
页面内容：
- 一个全局 `MovaMiniCtl`（`main.dart` 里建，`MaterialApp.builder` 接 `MovaMiniHost`）。
- **两种挂载方式各演示一遍，页面上用一个分段开关切换**：
  - **方式 A（页内悬浮）**：一个长 `ListView` 页面，点"页内小窗" → `mini.showInPage(context, api)`
    → 滚动列表，小窗纹丝不动、可拖拽；`push` 一个新页面，小窗被盖住（**说明这是期望行为**）；
    `pop` 回来又在。页面 `dispose` 里正确调 `mini.hide()`（示范 §1.7 的必做动作）。
  - **方式 B（跨路由持久）**：播放页点"缩小" → `mini.show(api)` → `Navigator.pop` → 回到列表页，
    小窗仍在播；再 `push` 另一个页面，小窗仍在最上。
- 屏上事件日志（`MovaMiniChg`/`MovaPipChg`/`MovaFullScreenChg` 三条真实打点，
  **不依赖 logcat**——0.4.0/0.5.0 的真机验证吃过 release 下拿不到日志的亏）。
- 四个开关：`enabled` / `snapToEdge` / `dismissible` / `initialCorner`。
- 一个"故意错误用法"按钮：页面 dispose 时不检查 `isShowing` 就 dispose engine，
  用来在 debug 下亲眼看到 Task 3 那条 assert 触发（教学 + 回归）。

`main.dart` 加入口。**demo 不计入测试数**。

---

## Task 11: 文档

- `README.md`：新增"App 内小窗"一节，**按两种挂载方式分两小节**：
  - 方式 A（页内悬浮）：一步接入——页面里 `mini.showInPage(context, api)`，
    `dispose` 里 `mini.hide()`。写明它随页面消失、会被新路由盖住，这是语义不是缺陷。
  - 方式 B（跨路由持久）：三步接入（建 `MovaMiniCtl` → `MaterialApp.builder` 接
    `MovaMiniHost` → 页面调 `show`），**并给出不用 `MovaMiniHost` 的等价手写 `Stack` 片段**
    （Task 6b），说明 mova 在这条路上只保证"controller 与路由生命周期解耦"。
  - 一个显眼的"谁 dispose engine"警告框；一句"`MovaMiniWindow` 挂载无关，你也可以把它
    放进任何自己的容器"。
  - 一段辨析：Flutter 的 `Overlay` ≠ Android `SYSTEM_ALERT_WINDOW` 系统悬浮窗（§0 那张表），
    本功能零权限、不出 App。
- `CHANGELOG.md`：0.6.0 条目。
- `doc/SPEC.md`：新增"App 内小窗（MovaMini）"一节，写明与系统 PiP / 系统级悬浮窗的
  三方关系（§0 两张表）、`MovaState.mini`/`pip`/`fullscreen` 的互斥矩阵、
  **两种挂载方式的分工与 `MovaMiniMount` 互斥规则**，以及"核心逻辑与挂载方式解耦"
  这条不可回退的架构约束（`MovaMiniWindow` 永远不许变回 `Positioned`）。
- `CLAUDE.md`：当前状态加 0.6.0 段落；**用当次实测的 `flutter test` 输出更新测试基线数字**
  （项目约定，基线过时会让下一份计划从错误起点推导）。
- `doc/notes/2026-07-31-ios-pip-feasibility.md`：回写一行——"阶段 3（跨平台应用内悬浮窗）
  已由 `doc/plans/2026-09-23-app-inline-pip-overlay.md` 落地"。

---

## 验收标准

1. `flutter analyze` 0 issues（除既有 `feed_player.dart` 那条）。
2. `flutter test` **807 项全绿**，既有 709 项一项未改。
3. **关闭态逐字节等价**：既不接 `MovaMiniHost`、也不调 `showInPage` 的宿主，
   `MovaState`/事件流/渲染树与 0.5.0 完全一致（`enabled: false` 的回归测试覆盖
   host/window/skin/`showInPage` 四处）。
4. `test/core/purity_test.dart` 不变且通过（core 未引入 flutter/`dart:ui`）。
5. **两种挂载方式都能跑通且互斥**：
   - 方式 B：example 里跨两层路由 push/pop 后小窗仍在最上层且仍在播；
   - 方式 A：example 的长列表页滚动时小窗位置不动、可拖拽，pop 页面后 entry 干净摘除；
   - 同时接了 host 又调 `showInPage` 时，全树只有一个 `MovaMiniWindow`、一个渲染面。
6. **解耦不可回退**：`MovaMiniWindow` 的源码里不出现 `Positioned` 作为根节点、
   不出现 `MediaQuery.size` 作 `bounds`、不 import `mini_host.dart`
   （Task 6 的等价性 4 项断言即为其可执行守卫）。

---

## 真机验证 checklist（Task 12，与实现分开一轮）

按项目约定："真机验证前必须先设计基于真实事件的测量方法"——本功能的测量锚点是
**`MovaMiniChg` 事件时间戳 + `renderEpoch`**，不用墙钟。

**A. 不重新解码（本功能的核心命题）**
- [ ] 交接前后 `MovaState.position` 连续：在 `MovaMiniChg(true)` 前后各采一次 position，
  差值应 ≈ 交接耗时（几十 ms 量级），**不得归零、不得回退**。
- [ ] 交接前后 `renderEpoch` **不变**（变了就说明发生了引擎重建，命题不成立）。
- [ ] 三阶段内存（`dumpsys meminfo`）：页面播放中 / 小窗中 / 回页面后——三者应在同一量级，
  小窗态**不得**出现第二份解码 session 的涨幅（对照 0.4.0 swap 预热期约 +26MB 的量级）。

**B. 交接那一帧**
- [ ] 逐帧录屏数黑帧：交接处黑帧数应为 0 或 1。若 >1，调整 Task 6 的挂载顺序
  （先挂小窗、下一帧再收页面 surface）。
- [ ] 音频不中断（交接瞬间无咔哒、无静音间隙）。

**C. 跨路由 / 生命周期**
- [ ] **方式 A**：长列表页内小窗——快速惯性滚动列表 100+ 项，小窗位置零漂移、视频不卡；
  该页 pop 后 entry 干净消失、无 `OverlayEntry not in the Overlay` 崩溃、无内存滞留。
- [ ] **方式 A**：页内小窗态下 push 新路由 → 小窗被盖住；pop 回来 → 小窗仍在且仍在播
  （**播放没中断**是关键：被盖住只是不可见，引擎不受影响）。
- [ ] **方式 B**：push 两层新路由后小窗仍在最上且可点击（验证 §1.1 的判断）。
- [ ] **两种方式的互斥**：先 `showInPage`，再在另一页调 `show` → 任一时刻只有一个小窗、
  一个渲染面（真机上双渲染面的典型症状是花屏或黑屏，单测抓不到）。
- [ ] 应用切后台再回前台，小窗位置与播放状态保持。
- [ ] 转屏后小窗被正确钳回可用区（不出屏、不压刘海/home 条）。
- [ ] Android 上小窗态再调 `enterPip()`（系统 PiP）：应互斥而非叠加，
  **这是最值得看的边界**——预期 `setMini(false)` 后再进系统 PiP。

**D. 手感**
- [ ] 拖动跟手（无一帧延迟感）、吸边动画自然、甩出关闭的阈值不误触。
- [ ] 中低端机上拖动期间视频不掉帧（`Texture` 随 `Positioned` 移动的代价）。

**E. 误用防护**
- [ ] debug 下触发 Task 10 的"故意错误用法"按钮，确认 assert 命中且信息可读。
- [ ] release 下同一路径不崩（assert 被编译掉，行为退化为画面冻结而非 crash）。

**F. 关闭态回归**
- [ ] 不接 `MovaMiniHost` 走一遍全部既有 demo，确认零变化。

**G. 结论回写**：把 A/B 的实测数字写回本文件与 `CLAUDE.md`。

---

**决策与结论摘要：** **手撸，不引 `floating`** —— 该包实际是 Android-only 的**系统 PiP 原生封装**
（与用户理解的"纯 Dart Overlay、四端通用"不符），做的正是 mova 已自研并真机验证过的事，对本需求零贡献；
其余候选要么是需要权限的 Android 系统悬浮窗，要么是会把自己交互语言强加给宿主的通用面板壳，
而本功能的真正难点（播放器实例脱离路由存活）没有任何第三方能代劳。
**挂载层（2026-09-23 修订，撤销"不用 `OverlayEntry`"的旧结论）**：**两种方式并存，不二选一**——
方式 A 页内悬浮（`MovaMiniCtl.showInPage` 往 `Overlay.of(context)` 的最近祖先插 `OverlayEntry`，
不受页面滚动影响、可拖拽，随页面生灭；"会被下一次 push 盖住"在这个场景下是期望行为而非缺陷），
由 mova 实现；方式 B 跨路由持久（`MaterialApp.builder` 下的 `Stack`），mova 只给
`MovaMiniHost` 这个约 30 行的可选便利壳 + README 等价手写片段——因为只要"controller 与路由
生命周期解耦"这条底层能力到位，方式 B 就是宿主十几行代码的事。**核心约束**：小窗本体
`MovaMiniWindow` 挂载无关（自身是撑满外部约束的 `Stack`，`bounds` 取 `LayoutBuilder` 约束而非
`MediaQuery.size`，绝不自己当 `Positioned`），两种外壳只是"把它放到哪里"的差异，Task 6 有 4 条
等价性断言守卫；`MovaMiniMount` 枚举保证同一 api 永不出现两个渲染面。
**分层**：core 只加"一个 bool 字段 + 一个 setter + 一个事件 + 一个 config + 一个纯函数文件"
（与 `fullscreen`/`pip` 完全同构），播放链路一行不动，core 不知道小窗挂在哪；
挂载/拖拽/皮肤全在 `lib/src/ui/mini/`。
**不**把小窗做成 `MovaComp`（坐标系与生命周期都不在一个量级），但小窗内部的 chrome 完全复用
`MovaSkin` 契约（`MovaMiniSkin`）。**共拆 11 个 Task + 1 轮真机**，测试从 **709 推进到 807**。
两个最大的坑：① "页面 dispose 顺手把刚交接出去的引擎销毁了"——文档 + `isShowing` +
debug assert 三重防；② 方式 A 的 `OverlayEntry` 在承载 Overlay 先死时被重复 remove——
`_detachEntry()` 单点收口 + `entry.mounted` 判据（§1.7）。
