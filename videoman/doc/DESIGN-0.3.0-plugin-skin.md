# videoman 0.3.0 架构设计（插件化 UI：Plugin / Component / Skin 三层契约）

状态：**草案（2026-07-31），待评审**。
上游文档：[PRD.md](PRD.md)、[SPEC.md](SPEC.md)、[DESIGN-0.2.0.md](DESIGN-0.2.0.md)（0.2.0 分层与组件树的地基）。
参考：[bytedance/xgplayer](https://github.com/bytedance/xgplayer)（EventEmitter + Plugin 挂载点 + presets 皮肤）——**借形不照搬**，见 §8。

---

## 1. 为什么写这份

0.2.0 已经把 UI 拆成"可寻址组件树 + 皮肤 + 补丁"，但几个概念**有实无名、职责有重叠**：

- 组件已经持有 `api`（经 `build(context, api, children)` 传入）、已经用 `VmSelector` 自渲染，
  但没有一个**统一的能力契约**说清"一个组件能拿到哪两种能力、边界在哪"。
- "谁决定显隐"目前散在三处：`components(VmState)` 按 source 类型换 VOD/直播底栏、
  `assemble()` 里的 `_PipHidden`/`_LockedHidden`/`_BarVisibility` 包整个操作层、
  组件内部各自 `VmSelector` 切图标。三者其实是**三种不同粒度**的职责，但没写清边界，
  容易越权（比如某个组件自己判断 pip 该不该显示，和皮肤的整层门控打架）。
- 布局位置被 `assemble()` 焊死，定制方想"把控制条挪到顶部"却又不想重写整套，没有中间档。
- 手势侧别和主流（bilibili 等）相反，是 0.1.0 的历史选择，这次一并对齐。

这份文档把这些**正名、划界、补齐**，并记录两处明确的行为变更（手势侧别、新增 left/right 槽）。
**它不是推倒重来**——落地时现有 9 个顶层组件绝大多数只需微调，见 §7 迁移影响。

### 非目标

- 不改 core↔ui 的通信模型（ui→core 直接调 `VmApi`，core→ui 走事件流，维持非对称，理由见 §2）。
- 不引入运行时 `install/uninstall` 的动态插件生命周期（xgplayer 有，我们暂不需要，见 §8）。
- 不引入 provider/riverpod/bloc。

---

## 2. 通信模型（维持现状，仅登记结论）

复盘确认 **core↔ui 非对称**是当前最优，不改：

- **core → ui**：走 emitter（`events`/`states`/`progress`/`uiStates` 四条流），ui 只订阅，不摸 core 内部。
- **ui → core**：ui 持 `VmApi` 抽象接口**直接调方法**（`play()`/`seek()`/`setLocked()`…），
  不经 emitter 转发命令。

**为什么不做"双向都走 emitter"的命令总线**：ui→core 方向本就不需要解耦——ui 依赖的是
`VmApi` 抽象（测试用 `FakeVmApi` 替身即证），已经"依赖抽象不依赖实现"。把方法调用改成
command 事件只是把耦合从接口签名挪到事件类型表，还丢了类型安全、直接返回值、可跳转，
可维护性/可扩展性都更差。真正需要解耦的只有 core→ui（core 不该知道有哪些组件在听），
那正是 emitter 单向广播在做的。**对称是形式，不是目标。**

> 插件的写操作**必须**经 `VmApi` 这一层（`play`/`seek`/…），不得绕到 `VmEngine`/`VmKernel`
> 内部，否则会绕过 `VmInterceptor`（鉴权/边界改写/错误上报）。这条写进 `VmPlugin` 契约文档。

---

## 3. 三层契约总览

```
┌─────────────────────────────────────────────────────────────┐
│ Skin        组装者：注册表 + 布局骨架 + 补丁靶子               │
│   VmDefaultSkin（三层骨架，assemble 可覆写） / 自定义 VmSkin   │
├─────────────────────────────────────────────────────────────┤
│ Component   功能单元：一个能力=一个组件（start/pause/全屏/字幕）│
│   with VmPlugin，自渲染、插槽无关                              │
├─────────────────────────────────────────────────────────────┤
│ VmPlugin    纯能力 mixin，与业务无关，只给两样东西：           │
│   ① 持有 VmApi（能发指令）  ② 订阅 emitter（能听事件）         │
└─────────────────────────────────────────────────────────────┘
```

一句话职责：**Plugin 给能力，Component 用能力做一个功能，Skin 把功能拼成整体。**

术语正名（复盘时纠过一次）：**"start/pause/全屏/字幕"是一个个 Component，不是 Plugin。**
Plugin 是唯一的、与业务无关的能力载体；Component 才是"每个功能一个"的单元。

---

## 4. VmPlugin —— 纯能力 mixin

### 4.1 它只负责两件事

1. **持有 `VmApi`**：让组件能发指令（读 `api.state`、调 `api.play()`…）。
2. **订阅 emitter**：让组件能听事件流，且订阅的生命周期被安全托管（建得下、也一定退得掉）。

**它不负责任何业务**——听什么、听到后干什么、渲染什么，都是组件自己的行为。Plugin 只提供
"能听/能发"这两种能力本身。这条纯粹性是关键：正因为 Plugin 不掺业务，就不存在"多个业务
mixin 叠加导致成员命名冲突"的问题——全局只有**一个**能力 mixin。

### 4.2 两种载体，两副面孔（对应第 6 节的 stateless/stateful 分野）

同样的两种能力，落在不同载体上：

- **Stateless 组件（默认，纯渲染型）**：
  - 「持有 api」→ 经 `VmScope.of(context)` 或 `build(context, api, …)` 参数拿到，已有。
  - 「订阅」→ 经 `VmSelector`/`VmProgressSelector`/`VmUiSelector` 声明式订阅（内部 `StreamBuilder`
    + `.distinct()`，广播流上重订阅安全）。**这类组件不需要 `with VmPlugin`**——两种能力
    已由 scope + selector 结构性地提供。
- **Stateful 组件（少数，事件副作用型）**：需要在 `initState` 建订阅、`dispose` 退订阅，
  这才是 `VmPlugin` mixin 真正落地的地方：

```dart
/// Capability mixin for stateful components that react to events with
/// side effects (not mere rebuilds). Grants two things: [api] to issue
/// commands, and [bind] to subscribe with lifecycle-safe teardown.
///
/// 为「事件副作用型」有状态组件提供能力的 mixin（副作用，非单纯重建）。
/// 只给两样：[api] 发指令、[bind] 带生命周期安全回收的订阅。
mixin VmPlugin<T extends StatefulWidget> on State<T> {
  /// The capability surface. 能力面。
  VmApi get api => VmScope.of(context);

  final List<StreamSubscription<dynamic>> _subs = [];

  /// Subscribes to [stream], auto-cancelled on [dispose]. Call from
  /// [initState], never from [build].
  ///
  /// 订阅 [stream]，[dispose] 时自动取消。只在 [initState] 调用，禁在 [build]。
  void bind<E>(Stream<E> stream, void Function(E) onEvent) {
    _subs.add(stream.listen(onEvent));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
```

> **契约铁律**：订阅只能挂在有稳定生命周期的载体（`State`）上，且必须在 `initState` 建、
> `dispose` 退。禁止在 `build`/`components()` 里建订阅——那会随重建反复建/丢，正是本次
> 已修复的 `throttleStream` 抖动坑（监听数 0→1→0→1 把广播流打死）。`bind()` 把"正确的
> 用法"做成唯一顺手的用法，让人想写错都难。

---

## 5. Component —— 功能单元

保持现有 `VmComponent`（`name`/`slot`/`order`/`children`/`build`），**补两条新规矩**：

### 5.1 插槽无关（新规矩，为"挪位置"铺路）

组件的 `build` **不得写死自己在顶/中/底**（比如不能 `Align(bottom)` 硬钉底部）。位置由皮肤的
`assemble()` 通过插槽决定。只有插槽无关，"把控制条从底部挪到顶部"才能靠 `remove` + `add`
到另一个插槽（或覆写 `assemble`）实现，而不必改组件本身。

### 5.2 三种"变化"的职责划界（本次最重要的澄清）

组件树里的"变化"有三种粒度，**各归各家，不许越权**：

| 变化粒度 | 例子 | 归属 | 机制 |
|---|---|---|---|
| **粗粒度成员**：这个 source 下有没有这个组件 | 直播用直播条、点播用点播条 | **Component 自己** | 组件恒挂载，按 `state.type` 自己收成 `SizedBox.shrink()` |
| **层级门控**：整个操作层一起显隐 | 闲置自动隐藏、pip/锁定时整层藏 | **Skin 骨架（`assemble`）** | 一个 `_BarVisibility`/`_PipHidden`/`_LockedHidden` 包整层，**整体一次**，非逐元素 |
| **组件内渲染**：单个组件跟状态变外观 | 播放键切图标、进度条走位、角标闪现 | **Component 自己** | `VmSelector` 选字段重建 |

**边界只剩两家**：整层显隐归骨架（做一次，对应你"整体隐藏、不要每个元素各自隐藏"的要求），
其余一切——粗粒度成员 + 组件内渲染——都归组件自己（`VmSelector`）。层级门控（pip/锁定/闲置）
和组件自渲染打的是不同的字段、不同的层，不会打架。

> **决策（2026-07-31，推翻本文档初稿）**：`components(state)` **塌缩掉**。皮肤不再按 state
> 出不同的树——组件树变成**静态**的，"直播/点播用哪套底栏"下沉为组件自身按 `state.type`
> 自我显隐。代价是两套底栏都 mount、都订阅 `type`（略费，已接受）；收益是接口更简单
> （皮肤的 `components()` 不再吃 state、每次状态变不重算树）、职责更统一（所有响应式都在组件里）。
>
> **连带的接口变化**：`VmSkin.components(VmState s)` → `VmSkin.components()`（去掉 state 参数，
> 返回固定组件集）。补丁只需应用一次。
>
> **连带的命名问题**：现在 `LiveBarComponent` 与 `BottomBarComponent` 共用顶层 `name='bottomBar'`
> 作为 VOD/直播的替换点——静态树里同名会让补丁定位歧义。落地时**合并为一个自适应
> `BottomBarComponent`**（内部 `VmSelector((s)=>s.type)` 决定出直播条还是点播条内容），
> 保留单一 `bottomBar` 名给补丁；这也顺带消掉"两套都 mount"里更重的那半。

---

## 6. Stateless vs Stateful 分野（复盘已定，登记）

组件默认 **Stateless + `VmSelector`**，仅"事件副作用型"用 **Stateful + `VmPlugin`**：

| 监听类型 | 例子 | 载体 | 能力来源 |
|---|---|---|---|
| **渲染响应**：状态变→重画 | 播放键切图标、进度条走位、锁定切显隐 | Stateless | `VmScope` + `VmSelector` |
| **副作用响应**：事件到→干件事（非重画） | 收到 `VmError` 弹提示、`VmLiveEdgeReached` 闪角标、进 pip 触发系统调用 | Stateful | `with VmPlugin` |

**不用裸 `StreamBuilder`**（除非像 `VmSelector` 那样封装并配 `.distinct()`）：它无选择性重建
（一有事件重建整棵子树，position 200ms 一跳会引发重建风暴），且 build 里现算 stream 会踩
重订阅陷阱。现有 `VmSelector` 已经把这层封好（广播流 + `.distinct()`），组件复用它即可。

---

## 7. Skin —— 变薄的组装者

`VmSkin` 接口**保留但变薄**，`VmDefaultSkin` 从"焊死实现"改为"**可分档覆写**"，给出三档灵活度：

### 7.1 三档定制

| 档 | 做法 | 能改什么 | 不用碰什么 |
|---|---|---|---|
| **① 补丁档** | `VmDefaultSkin(patches: [...])` | 增/删/替换/重写组件、在**已有插槽间**挪位置、改颜色尺寸（`VmTheme`） | 不写布局代码 |
| **② 半覆写档** | `extends VmDefaultSkin` 只 override 某一层的受保护方法（`buildOperableLayer` 等） | 重排版（把控制条挪顶部、侧栏、画面内浮层） | 复用默认组件集、主题、补丁能力、其余各层 |
| **③ 全实现档** | `implements VmSkin` | 布局、交互、组件全自定义 | —— |

**关键改动**：把 `VmDefaultSkin.assemble()` 内部的三层拆成**可单独覆写的受保护方法**
（如 `buildPlaybackLayer` / `buildOperableLayer` / `buildPersistentLayer`），让"半覆写档"
只重写想改的那层，而不是把整个 `assemble` 抄一遍。这是"把 controller 挪到顶部"从
"重写整套"降级为"覆写一个方法"的技术前提。

### 7.2 三层骨架（沿用 0.2.0，登记为正式契约）

`VmDefaultSkin` 的骨架就是你定的三层，写死为内置皮肤的"统一整体"：

1. **播放层**：原始 video 画面。
2. **操作层**：手势 + 顶/中/底 chrome。整层作为**一个** `_BarVisibility` 随 `controlsVisible`
   渐隐并变穿透；pip/锁定时整层 `_PipHidden`/`_LockedHidden` 隐藏。
3. **常驻层**：锁定遮罩 + 锁定/解锁切换按钮。恒挂载、默认对点击穿透，只有需要吸收事件的
   部分（锁定时的不透明遮罩）才拦截；**不受任何门控**（它本身是改变那些状态的入口）。

> 对应你的原话"交互层分上层(常驻层)/下层(操作层)，上层默认穿透给下层，某元素需吸收才不穿透，
> 加解锁在常驻层"。这套已在 0.2.0 落地，本次只是把它写成**受保护、可覆写**的方法，供②档复用。

---

## 8. 与 xgplayer 的取舍（借形不照搬）

| xgplayer | videoman 取舍 |
|---|---|
| EventEmitter 核心 | ✅ 已有（`VmBus` 四条流），core→ui 走它 |
| Plugin 有生命周期、可运行时 `install/uninstall` | ❌ 不做动态增删。定制在**构造皮肤时**静态组装（`patches`/覆写），够用且简单 |
| 内置控件与第三方用同一套注册机制 | ✅ 认同并对齐——内置组件也走 `VmComponent`+插槽，无"皮肤特权通道" |
| 插件间不互相引用、都过 player 事件 | ✅ 已是（组件只认 `VmApi`+事件流，互不引用） |
| CSS 皮肤 | → 组合装配（`assemble` + `VmTheme`） |

**结论**：我们要的是 xgplayer 的**可扩展性契约**（能独立增/替/删任意功能点、内置与第三方同机制），
不要它的**运行时动态生命周期**（Flutter 侧静态组装 + 声明式重建已覆盖需求，动态 install
只会引入订阅生命周期的复杂度）。

---

## 9. 行为变更（本次两处明确改动）

### 9.1 手势侧别翻转 → 左亮度 / 右音量，且配置改为「侧别→动作」映射

对齐 bilibili 等主流。**这推翻了 0.1.0 起"刻意与 media_kit 内置相反"的历史选择**。

**决策（2026-07-31）**：`VmGestureConfig` 不再用 `leftVerticalVolume: bool` 这种把侧别与动作
写死绑定的布尔开关，而是**抽象成「侧别 → 动作」映射**，侧别与动作彻底解耦——定制方能任意
组合（甚至左右都调音量、或某侧禁用）：

```dart
/// Which action a directional gesture performs. Decoupling side from action
/// lets hosts remap freely (e.g. brightness on the right, or disable a side).
///
/// 某方向手势执行哪个动作。侧别与动作解耦，宿主可自由重映射
///（如把亮度放右侧、或禁用某一侧）。
enum VmGestureAction { volume, brightness, seek, none }

VmGestureConfig(
  leftVertical: VmGestureAction.brightness,  // 默认：左亮度
  rightVertical: VmGestureAction.volume,     // 默认：右音量
  horizontal: VmGestureAction.seek,
  doubleTapSeek: true,
  pinchZoom: true,
)
```

默认值即"左亮度/右音量"，等价于翻转后的主流约定；旧的 `leftVerticalVolume` 等布尔字段移除
（破坏性变更，计 0.3.0）。

连带要清理所有反向表述，否则下一个接手者看到"勿改回"的注释会又改回去：`CLAUDE.md`、本 `doc/`、
组件注释、`README.md`、`.claude` 下 `videoman-dev` skill 里的"左音量/右亮度…刻意为之…勿修正"。

**HUD 反馈维持居中**（overlay/center），不分左右——同样对齐主流（bilibili 音量/亮度弹居中胶囊）。

### 9.2 VmSlot 新增 left / right

新增两个**垂直边带**插槽，定位为侧边内容（侧栏、剧集列表、弹幕设置等），**不承载音量/亮度 HUD**
（HUD 居中）。枚举一旦公开不便再删，故本次一次性把位置词表补全：

```
gesture, hud, top, center, bottomAbove, bottom, overlay, left, right
```

---

## 10. 迁移影响（落地不重来，量化一下）

- **VmPlugin**：新增一个 mixin 文件（`ui/scope/plugin.dart` 量级），~30 行。现有 stateless
  组件**零改动**（它们本就靠 scope+selector）。只有真正做副作用的组件改成 `with VmPlugin`。
- **VmComponent**：契约文档补"插槽无关"一条；现有组件抽查是否有写死方位的（`center_play` 用
  `Center`、`_LockToggleButton` 用 `Align(centerRight)`——后者在常驻层，属骨架不属组件，OK）。
- **VmSkin/VmDefaultSkin**：`assemble` 拆成三个受保护方法；`components(state)` → 无参
  `components()`（组件树静态化）；`LiveBarComponent`/`BottomBarComponent` 合并为一个自适应
  底栏组件（内部按 `type` 自渲染）。补丁系统的应用时机从"每次状态变"降为"一次"。这是本次
  代码量主要来源，但集中在皮肤 + 底栏两个文件。
- **VmSlot**：加两枚举值 + `buildSlots` 处理；`assemble` 骨架决定 left/right 渲染到哪。
- **手势**：`gesture_layer` 侧别判断翻转 + 全仓反向文案清理（机械改动，批量）。
- **测试**：新增 `VmPlugin` 单测（订阅 dispose 回收）；手势翻转的现有测试断言要跟着改。

**没有"15+ 组件全重写"**——那是我复盘早期的误判。真实是"加一个 mixin + 拆一个 assemble +
补两个枚举 + 翻手势文案"。

---

## 11. 决策与待定项

**已定（2026-07-31）**：

- ✅ **`VmGestureConfig` → 侧别→动作映射**（`leftVertical: VmGestureAction.brightness`），
  侧别与动作解耦。见 §9.1。
- ✅ **`components(state)` 塌缩**为无参 `components()`，组件树静态化、组件自我显隐。见 §5.2。
- ✅ **版本号 0.3.0**（破坏性：手势配置改形 + 手势侧别翻转）。

**仍待你拍板**：

1. **`assemble` 拆分粒度**：拆成 3 个受保护方法（播放/操作/常驻）够不够？操作层内部的顶/中/底
   要不要也各自可覆写？倾向先拆 3 个，不够再细。
2. **left/right 是否本期就落地内容**：插槽本期加，但是否本期就往里放一个示例组件（如剧集侧栏 demo）？
   还是只留空插槽、内容留给定制方？

---

## 12. 落地顺序（评审通过后再拆细 Task）

1. 加 `VmSlot.left/right` + `buildSlots`/`assemble` 支持（不改行为，先铺位置）。
2. 加 `VmPlugin` mixin + 单测；挑一个副作用组件（如 error toast）做 pilot 迁移验证。
3. `VmDefaultSkin.assemble` 拆成三个受保护方法 + ②档覆写的 widget 测试。
4. 手势侧别翻转 + 全仓反向文案清理 + 测试断言更新。
5. 文档回写（README/SPEC/CLAUDE/skill）、`pub publish --dry-run`。

> 每步 TDD + `flutter analyze` 0 issues + 提交，沿用既有节奏。真机验证（承自 0.2.0 Task 14）
> 一并覆盖手势新侧别的手感。
