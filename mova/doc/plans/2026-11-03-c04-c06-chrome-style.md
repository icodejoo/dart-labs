# mova：C04 `MovaChrome` 与 C06 `MovaPlayerStyle` — 逐 Task 子计划

> 2026-11-03 · 子计划（总计划 [2026-10-31-unified-orchestration-master-plan.md](2026-10-31-unified-orchestration-master-plan.md) 的 C04、C06 两行）
> 上游拍板：总计划 §8 十八项全部按推荐默认；本子计划直接用到的是 **待拍板 14**（C04/C05/C06 留在本分支，检查点失败可整体移出）、**待拍板 18**（不加成员级 `@Deprecated`，只在 CHANGELOG 与 dartdoc 公告）、"新功能默认关"、"公开 API 不做破坏性变更（旧接口一个版本内仍可用）"。
> 范围：C04（每视图交互态 + 旧引擎接口桥接）、C06（样式挪出 `MovaOpts`）；C05（全屏路由）只写它依赖 C04 的接口约定，不拆 Task。
> 行号基准：`jelon/mova-orchestration` 的 HEAD `7275bd5c`（A01、A02 已提交，A03 在途）。A 块后续提交会移动 `engine.dart`/`cutover_engine.dart` 行号，开工时按符号重新定位，不要照抄行号。

**Goal：** 控制条显隐、HUD、拖动/预览这些"每个画面自己的交互态"从引擎搬到视图（每个 `MovaPlayer` 一份 `MovaChrome`），同一引擎挂两个视图不再串扰，cutover 换指时控制条不再跳变，拖动和按钮操作会续期自动隐藏（P1-12、P1-13）；主题、文案、手势、控制条行为、弹幕样式从引擎构造期的 `MovaOpts` 挪到视图层的 `MovaPlayerStyle`，接上 Flutter 的 `ThemeExtension`，切主题不再重建引擎，界面不再依赖写死的中文（P1-8 样式部分、P2-17）。

**主干原则：**
- `MovaApi` 零新增成员；新增能力走**包内**接口 `MovaUiBridge`（不导出），不破坏任何 `implements MovaApi` 的宿主。
- 旧 `MovaApi.showControls/hideControls/showHud/setDragging/uiState/uiStates` 与 `MovaOpts.theme/strings/gesture/controls/danmaku` 一个版本内照常可用：**没有视图挂载时行为逐字不变**，单视图时对旧读者可见的状态一致。
- 不加成员级 `@Deprecated`（待拍板 18）；只写 dartdoc 段落和 CHANGELOG「Deprecated（公告）」。
- core 不 import Flutter（`ui_bridge.dart` 是纯 Dart），`purity_test` 规则不改；不引入新依赖。
- 现有断言零改写为目标；唯一例外见第 6 节（`view_test.dart:105`，且取决于 C03 的做法）。

**Baseline：** 以 C04a 开工当天本机实跑为 N0（`flutter test` 全绿 N0 项、`flutter analyze lib test` 0 issues）。写本子计划时最近一次回写是 1865（`a2d021d0`，B 块结束），A 块正在并行增加测试，所以下文一律按增量写（N0+Δ）。

**执行约束：**
- 开工时机按阶梯：C 块在 CP2 之后。届时 A14b（`overlays.dart` 错误层与 `MovaStrs` 错误文案）、A21（`ui/player.dart` 生命周期监听与 `Video` 参数）、A28（`cutover_engine.dart` 的 `_attach` 转发）、A30（`next_up.dart`/广告覆盖层）、C03（`ui/view.dart`）都已落地，C04/C06 在它们之上改，冲突最少。若要提前在 worktree 并行，冲突热点见 9.1 RC-1。
- 落地派 sonnet（low）子代理，按 Task 顺序、每 Task 一个提交；子代理不得自行提交（总计划 3.1 第 6 条），由主会话复核后提交。
- 每个提交：`flutter analyze lib test` 0 issues、`flutter test` 全绿、提交说明写实测总数；C04 全部提交后、C06 全部提交后各回写一次 CLAUDE.md 测试基线与本子计划（总计划 3.1 第 2 条）。

---

> C04 落地更新（2026-11-04）：实测 N0=2269；C04a/b/c/d 分别为 2277/2285/2296/2301，新增 8/8/11/5，既有断言零改写。主会话逐 Task 亲自执行并立即提交；按会话要求不修改 CLAUDE.md。A28 Ready 重放、旧焦点唤出与完整清单分批验证等差异见总计划文末「C04 落地记录（2026-11-04）」。C06 尚未执行。

## 0. 现状核实（HEAD `7275bd5c`，均已读源码确认）

| # | 事实 | 源码证据 | 落点 |
|---|---|---|---|
| 1 | 每视图交互态放在引擎上 | `core/api.dart:43-46`（`uiStates`）、`:54-57`（`uiState`）、`:302-345`（四个动词）；`engine.dart:339`（`_ui` 总线）、`:611-612`（`_hudTimer`/`_autoHideTimer`）、`:2784-2835`（四个动词实现，HUD 800ms 写死在 `:2819`） | C04a/C04b |
| 2 | 就绪时由引擎决定显隐 | `engine.dart:1465-1469`：`_announceReady` 里按 `options.controls.showOnStart` 同步调 `showControls()/hideControls()`，然后才发 `MovaSourceChange`/`MovaReady` | C04b |
| 3 | cutover 逐个转发，换指时控制条跳变 | `cutover_engine.dart:136`（用生效引擎的 `uiState` 播种）、`:234`（`_attach` 里 `engine.uiStates.listen(_uiState.emit)`）、`:422-440`（四个动词直通 `_active`）、`:723`（换指后 `_attach(shadow)`；`MovaBus` 订阅即重放，代理的 UI 态立刻变成影子自己的值——影子预热时已跑过自己的 `_announceReady` 和 3s 计时） | C04b |
| 4 | UI 层直接调旧接口 17 处、5 个文件 | 写：`gesture_layer.dart:226,234,236,350,351,357,363,379`；`bottom_bar.dart:375,400`；`player.dart:217,223`。读：`gesture_layer.dart:233`、`selector.dart:127-128`（`MovaUiSelect`）、`preview.dart:115,121`。经 `MovaUiSelect` 间接消费：`default_skin.dart:289-290`（`_BarVisibility`）、`hud_layer.dart:157,213` | C04c |
| 5 | 自动隐藏不感知交互（P1-13） | `engine.dart:2825-2835` 的 `setDragging` 不碰计时器；`_BarVisibility` 只看 `controlsVisible`（`default_skin.dart:289-290`），预览气泡在 `MovaSlot.bottomAbove`（`preview.dart:42`）随栏淡出 | C04d |
| 6 | 同一引擎第二个视图已经存在 | `mini_window.dart:145` `MovaPlayer(api: widget.api, skin: skin, autoLoadQualities: false)`；`feed_player.dart:317,354` 每页一个 `MovaPlayer` | C04c 用例 |
| 7 | 样式全从引擎 `options` 读 | 见第 1 节计数：lib 59 处、test 25 处 | C06b |
| 8 | `MovaView` 只要 options 不等就重建引擎 | `view.dart:188`；而 `test/ui/view_test.dart:101-110` 恰好是用 **theme** 变化来断言"重建" | C06d |
| 9 | 界面依赖写死的中文 | core：`model/quality.dart:55`（`'自动'`）、`:102`（`'未知'`），且 `MovaStrs.auto` 在 UI 里零引用，清晰度按钮/弹层直接显示 `q.label`（`top_bar.dart:214,244`）。B16 新增：`common.dart:141-157`（按 `IconData` 反查 12 个中文动作名，`'：'` 拼接）、`center_play.dart:75,80`（播放/暂停）、`mini_skin.dart:99,104`（关闭小窗） | C06c |
| 10 | 进度条颜色取宿主 Material 主题 | `bottom_bar.dart:349-352` 的 `SliderTheme` 只写 `trackHeight` | C06e |
| 11 | 图标写死 | `lib/src/ui` 下 28 种 `Icons.*`、12 个文件；`_iconLabel` 按图标反查标签，图标一旦可配，自定义图标会失去标签 | C06c（标签显式化）+ C06e（图标可配） |
| 12 | 现有 UI 测试几乎全用非桥接替身 | `FakeMovaApi` 的四个 UI 动词只记账不改状态（`fake_api.dart:508-528`），测试用 `pushUi(...)` 驱动渲染（24 处）并断言 `calls`/`lastHud`（14 处）；挂 `MovaPlayer` 又用真实引擎的 8 个测试文件里 UI 交互态读写为 0 | 决定 D2 |

P2-17 的第五个子项"错误层直接 `toString`"（`overlays.dart:97`）归 A14b，C06 不重复处理。

---

## 1. 读取点实测计数与迁移策略

### 1.1 `MovaOpts.theme/strings/gesture/controls/danmaku`

统计口径：`\boptions\.(theme|strings|gesture|controls|danmaku)\b`；另用 `options\b(?!\.(五节))` 复查，**没有**"先取 `api.options` 再读字段"的别名路径。

**lib：grep 命中 61 行，其中 2 行是 `common.dart:10,15` 的文档注释，真实代码读取 59 处。**

| 节 | 处数 | 位置 |
|---|---:|---|
| theme | 33 | `top_bar.dart` 7（61,107,156,203,276,329,366）、`bottom_bar.dart` 7（61,136,174,343,435,490,541）、`feed_social.dart` 5（152,216,262,303,342）、`subtitle.dart` 2（120,259）、`preview.dart` 2（201,286）、`overlays.dart` 2（39,87）、`default_skin.dart:391`、`speed_button.dart:44`、`next_up.dart:135`、`hud_layer.dart:258`、`douyin_gesture_layer.dart:140`、`danmaku.dart:213`、`center_play.dart:69`、`ad_overlay.dart:125` |
| strings | 8 | `bottom_bar.dart:436,542`、`top_bar.dart:283`、`subtitle.dart:275`、`speed_button.dart:45`、`next_up.dart:136`、`hud_layer.dart:199`、`ad_overlay.dart:126` |
| gesture | 8 | 全在 `gesture_layer.dart`（191,220,259,279,291,339,355,361） |
| controls | 9 | `player.dart` 5（186,282,297,298,301，都是 `shortcuts`）、`engine.dart` 3（1465 `showOnStart`、2793-2794 `autoHide/autoHideDelay`）、`default_skin.dart:288`（`fadeDuration`） |
| danmaku | 1 | `danmaku.dart:45`（整节读出，`enabled/items` 是数据，其余 5 个字段是样式） |

按层：core 3 处（全在 `engine.dart`，旧路径用）、ui 56 处（16 个文件）。全部位于 `build` 或事件回调里，没有在 `initState` 里读的，所以改成经 `Theme.of` 查找是安全的。

**test：读取 25 处 + 构造 50 处。**
- 经 `api/engine.options` 读 7 处：`core/audio_only_scenarios_test.dart:403,404`、`ui/hud_test.dart:87,107`、`ui/gesture_test.dart:219`、`ui/subtitle_test.dart:54,55`。
- 经 `MovaOpts` 局部变量读 18 处：`core/options_test.dart:31,32,33,34,35,37,58,59,96,97,192,198,199,250,345`、`core/openness_live_test.dart:83,84`、`core/openness_preview_test.dart:218`。
- 以具名参数构造（`MovaOpts(controls: MovaCtrlsConfig(...))` 之类）50 处——不是读取，字段保留就不受影响。

### 1.2 旧 UI 交互接口

lib：UI 层直接调用/读取 17 处（5 个文件，见第 0 节第 4 行），间接 3 处；core 内部 2 处（`engine.dart:1466,1468`）。test：约 147 行（16 个文件，含替身 14 行），集中在 `engine_verbs_test`(37)、`engine_test`(22)、`engine_streams_test`(13)、`hud_test`(11)、`gesture_test`(10)、`preview_test`(9)。

### 1.3 迁移策略与 analyze 0 怎么保持

1. **不加成员级注解**（待拍板 18）。`analysis_options` 继承 flutter_lints，`deprecated_member_use_from_same_package` 对包内 lib 与 test 都报；不加注解就没有警告，analyze 0 由构造保证。
2. **公告**：`MovaOpts` 五个字段、`MovaApi` 六个 UI 成员各加一段 dartdoc"计划在下个版本弃用，改用 `MovaPlayerStyle` / `MovaChrome`"；CHANGELOG `Unreleased` 加「Deprecated（公告，下个版本加注解）」小节。core 文件里用反引号写类名，不用 `[MovaChrome]` 方括号引用（core 不能 import UI）。
3. **包内读取收口**：C04c 之后 UI 层的旧 UI 接口调用只留在 `ui/chrome/chrome.dart` 的回落口（`MovaUiPort` 的 api 分支）；C06b 之后样式节读取只留在 `ui/style/style.dart` 的查找链（5 处）与 `engine.dart` 的旧路径（3 处）。两条都由守卫测试锁住（C04c、C06b 各 1 条，扫描源码，仿 `purity_test`）。
4. **下个版本**真加注解时：lib 只需处理上述约 8 + 6 处（加 `// ignore: deprecated_member_use_from_same_package` 并注明"旧路径兜底"或直接删除）；test 的 25 处读取与约 147 行旧 UI 用例再决定迁移或 ignore。构造调用点（50 处）只在给**参数**也加注解时才会报。

---

## 2. 架构决策

### D1 — `MovaChrome` 归属：每个 `MovaPlayer` 视图一份，谁创建谁销毁

- `MovaPlayer` 不传 `chrome:` 时自己建一份，`State.dispose` 里同步销毁；宿主经 `MovaPlayer(chrome: c)` 传入的，`MovaPlayer` 只绑定/解绑，不销毁（与"借用不 dispose"一致，总计划 2.6 #5）。
- 一个 `MovaChrome` 同一时刻只能绑一个视图（debug 断言）。
- 换 `api` 时同一份 chrome 解绑再绑到新 api，状态按新 api 重新播种；`KeyedSubtree` 的 key 由 `ValueKey(api)` 改为 `ValueKey((api, chrome))`，换 chrome 也强制组件重挂（只在 `initState` 订阅一次的组件不会挂在旧 chrome 上）。

否决：
- **每引擎一份**（现状）：同一引擎的页面与小窗/全屏路由互相串扰，正是 P1-12。
- **完全交给宿主创建**：破坏零配置用法。
- **放进 `MovaScope`**：`InheritedWidget` 不能持有需要销毁的对象。
- **一份 chrome 共享给多个视图**（让全屏进出"状态连续"）：要引用计数，而且两个视图又会互相影响，与"互不串扰"矛盾。

### D2 — 只为支持视图桥的引擎自动建 chrome，其他 `MovaApi` 实现保持旧路径

`MovaPlayer` 在 `api is MovaUiBridge`（`MovaEngine`、`MovaCutoverEngine`、测试替身 `FakeBridgeApi`）时才自动建 chrome；宿主自写的 `implements MovaApi`（包装器、自制替身）不建，组件经回落口直接调旧接口，**行为逐字不变**。宿主显式传 `chrome:` 时一律启用（chrome 独立工作，没有镜像与旧动词转发）。

否决：
- **对所有 api 都建 chrome**：宿主自写实现上的 `api.showControls()` 不再驱动视图（行为破坏）；现有 24 处 `pushUi` 与 14 处 `calls/lastHud` 断言都得改。
- **不加桥，chrome 观察 `api.uiStates` 并"采纳外部变化"**：分不清"宿主调了旧动词"和"另一个视图回写的镜像"，两个视图会互相带着变，等于没修。

### D3 — 桥接：包内能力 `MovaUiBridge`，有视图时旧动词转发、视图状态回写镜像

新文件 `core/state/ui_bridge.dart`（纯 Dart、不导出、下个版本随旧接口删除）：

```dart
/// 支持"每视图交互态"的引擎能力（包内，过渡用）。
abstract interface class MovaUiBridge {
  /// 当前源是否已宣布就绪；新视图据此决定是否立刻开始自动隐藏计时。
  bool get uiReady;

  /// 挂接一个视图，返回连接；引擎已销毁时返回已关闭的连接。
  MovaUiLink linkUi(MovaUiSink sink);
}

/// 接收旧 UI 动词的视图端。
abstract interface class MovaUiSink {
  void legacyShow({required bool sticky});
  void legacyHide();
  void legacyHud(MovaHud hud, String? text);
  void legacyDragging(bool dragging, Duration? previewAt);
}

/// 视图与引擎之间的一条连接。
abstract interface class MovaUiLink {
  /// 把视图状态写给旧的 uiState/uiStates 读者；多视图时后写者胜出。
  void mirror(MovaUiState state);

  /// 断开；最后一个视图断开后，旧动词恢复由引擎自管。
  void unlink();
}
```

语义：
- **无连接**：引擎一切照旧（四个动词自管计时、`_announceReady` 按 `showOnStart` 显隐）。现有 core 测试零改动就是证据。
- **有连接**：四个旧动词转发给所有连接的视图，引擎不再自己起计时器、不改 `_ui`；`_announceReady` 不碰 UI（视图各自监听 `MovaReady`）；视图每次变化 `mirror` 回 `_ui`，旧读者照常读 `uiState/uiStates`。
- **首个视图挂接时**取消引擎旧路径的两个计时器；新视图只用旧状态的 `controlsVisible` 播种（HUD、拖动、预览是瞬时态，不继承），可见且 `uiReady` 为真时立刻开始自动隐藏计时，否则等 `MovaReady`。

否决：
- **给 `MovaApi` 加 attach 成员**：破坏所有 `implements MovaApi`。
- **写穿**（chrome 调旧动词来保持镜像）：引擎和视图两套计时器各跑各的；两个视图的写穿互相覆盖。
- **导出桥接口**让宿主包装器也能接入：多 3 个公开类型，下个版本就删；包装器本版本保持旧路径已经是"行为不变"。

### D4 — cutover：视图连在代理上，换指不跳变，不碰 `_commitNow`

- `MovaCutoverEngine` 自己实现 `MovaUiBridge`，连接存在代理上（不连内部引擎），所以换指不需要迁移连接。
- 有连接时 `_attach` 不再把生效引擎的 `uiStates` 转发到代理（只改 `:234` 这一行），换指瞬间代理的 UI 态保持视图镜像的值；四个旧动词有连接时转发给视图，否则照旧直通 `_active`。
- `uiReady` 委托给 `_active`（`_active is MovaUiBridge` 时）；最后一个视图断开时把代理 UI 态重新对齐 `_active.uiState`。
- 影子仍会跑自己的 `_announceReady` 和旧路径计时器，只是没人看；引擎 dispose 时同步取消（B15 已保证），代价是后台多一个空转 Timer。

否决：代理再向内部引擎建一条"中继连接"、换指时迁过去——要改 `_commitNow`，正是 A02/A20/A28 的热区。

### D5 — 组件读写口：包内 `MovaUiPort` + `movaUiOf(context)`，`MovaUiSelect` 签名不变

- `movaUiOf(context)`：最近的 `MovaChromeScope` 里有 chrome 就包它，否则包 `MovaScope` 的 api（回落到旧接口）。`pumpComponent` 这类不经 `MovaPlayer` 的树、宿主自建的 `MovaScope` 树都照常工作。
- 公开 `MovaUiSelect` 改为 chrome 感知：同一个组件在 `MovaPlayer` 里读本视图，在裸 `MovaScope` 里读 `api.uiStates`。
- `MovaChrome` 不实现任何包内接口（避免公开类的父类型里出现不可导入的类型）；`MovaUiPort` 是包内具体类。

### D6 — 自动隐藏续期（P1-13，C04d 单独提交）

- `setDragging(true)`：强制可见并暂停计时；`setDragging(false)`：未常显时重新计时。控制条隐藏时横滑 seek 也会唤出控制条（预览气泡在栏里，原来根本看不到）。
- 控制条区域内任意按下（`_BarVisibility` 里包一层 `Listener(behavior: deferToChild)`，不参与手势竞技）和按钮的键盘激活（`MovaIconButton` 的 `ActivateIntent`）调 `touch()` 续期。
- `sticky` 下都不计时；回落口（自定义 api）的 `touch()` 是空操作，旧行为不变。

否决：评审原文"可见条件改为 `controlsVisible || dragging`"——松手瞬间控制条会闪隐，而且旧读者看到的 `controlsVisible` 与画面不一致。

### D7 — 与 C05（全屏路由）的接口约定

全屏路由里的第二个 `MovaPlayer` 自建 chrome，不共享内联视图的；进入时以旧读者可见态播种、`uiReady` 为真即开始计时；退出时由 C05 调内联视图的 `chrome.show()`；路由视图传 `autoLoadQualities: false`（与 `mini_window.dart:145` 一致，避免第二次探测；A12 的同会话去重是兜底）。完整行为表见第 7 节。

### D8 — `MovaPlayerStyle` 形态：一个 `ThemeExtension`，五节可空，复用现有类型

```dart
@immutable
class MovaPlayerStyle extends ThemeExtension<MovaPlayerStyle> {
  const MovaPlayerStyle({this.theme, this.strings, this.gesture, this.controls, this.danmaku});
  final MovaTheme? theme;
  final MovaStrs? strings;
  final MovaGestureConfig? gesture;
  final MovaCtrlsConfig? controls;
  final MovaDanmakuStyle? danmaku;
}
```

`MovaTheme/MovaStrs/MovaGestureConfig/MovaCtrlsConfig` 原样复用，**不改名、不搬出 core**（"这是挪位置，不是改名"）；新增 `MovaDanmakuStyle`（只含 trackCount/trackHeight/fontSize/opacity/crossDuration）。

否决：
- **把这些类型搬出 core**：会改 `MovaOpts` 字段类型与 import 路径，属于破坏；留到下个版本删 `MovaOpts` 字段时一起做。
- **每节一个 `ThemeExtension`**（5 个）：宿主配置分散。
- **字段级合并**：语义复杂，也与 `MovaOpts.copyWith` 的节级替换不一致。各节整体替换。

### D9 — 查找顺序：widget 参数 > `ThemeExtension` > 旧路径 options > 默认，各节独立回落

- `MovaPlayer(style:)` 经包内 `MovaStyleScope` 下发；`ThemeExtension` 取 `Theme.of(context).extension<MovaPlayerStyle>()`；旧路径取 `MovaView` 下发的 options（C06d 起），否则取 `api.options`；都没有用默认。
- 组件改调 `MovaPlayerStyle.themeOf/stringsOf/gestureOf/controlsOf/danmakuOf(context)`。依赖 `Theme`，所以换主题只重建依赖它的组件，**不碰引擎**；B15 缓存的 `_skinTree` 不受影响（`b15_test.dart:126` 已锚定"主题变化仍能更新缓存子树"）。
- `lerp` 做离散切换（t<0.5 用旧值）：主题动画默认 200ms，期间依赖方每帧重建一次，可接受。

否决：
- **`api.options` 优先**：它永远非空（默认 `const MovaTheme()`），宿主没法用主题覆盖。
- **在 `ThemeExtension` 之后插一步 `Localizations.of<MovaStrs>`**（评审建议，总计划顺序没有）：本子计划按总计划不加；以后要加只是查找链里插一行，不影响 API。

### D10 — 弹幕：样式字段走样式，`enabled/items` 仍取旧路径 options

`danmakuOf(context).applyTo(movaLegacyOptionsOf(context).danmaku)` 合成一个 `MovaDanmakuConfig` 交给 `_DanmakuTrack`，轨道组件一行不改（B06 的改动不受影响）；`items` 保持同一引用，`didUpdateWidget` 里的 `identical(items)` 判断照旧。"弹幕条目随内容走"仍暂缓（总计划 1.4）。

### D11 — 写死中文：界面不再显示 core 的中文标签，core 原值保留一个版本

- 清晰度：auto 档显示 `MovaStrs.auto`，未知档显示新字段 `MovaStrs.unknownQuality`；宿主自定义的标签（如"超清"）原样显示。
- core：两个字面量提成常量 `kMovaAutoQualityLabel`、`kMovaUnknownQualityLabel`，值不变；dartdoc 与 CHANGELOG 预告下个版本改成中性值。
- B16 的语义标签全部进 `MovaStrs`，内置组件显式传 `label:`，`_iconLabel` 只给第三方按钮兜底并改读当前样式的文案。

否决：本版本就把 `MovaQuality.auto().label` 改成 `'auto'`——自己渲染 `label` 的宿主界面会变样，还要改写 4 处断言（`engine_verbs_test.dart:382`、`model_test.dart:28`、`engine_test.dart:1705-1709`）。

### D12 — 弃用策略（待拍板 18 的落地方式）

见 1.3：不加注解、dartdoc + CHANGELOG 公告、包内读取收口到两个文件并用守卫测试锁住。

### D13 — `MovaView`：样式节变化走视图层，不重建引擎（C06d）

`MovaView` 把自己的 `options` 作为旧路径层传给内部 `MovaPlayer`，比较 options 时排除五个样式节。**前提是 C03 对样式节保守**：C03 只放宽它确认是引擎读取的节，五个样式节仍"按值比较、变了就重建"（`view_test.dart:101-110` 在 C03 里保持原样）；到 C06d 才放宽。这样 C04/C06 被整体移出时，C03 的行为自然正确。若 C03 已经把样式节排除在重建之外，C06d 只补旧路径层传递，不再改写断言。

---

## 3. 文件结构

| 文件 | 动作 | Task |
|---|---|---|
| `lib/src/core/state/ui_state.dart` | 加常量 `kMovaHudDuration`（800ms） | C04a |
| `lib/src/ui/chrome/chrome.dart` | 新建：`MovaChrome`（公开）、`MovaChromeScope`、`MovaUiPort`、`movaUiOf`、绑定函数（包内） | C04a、C04c、C04d |
| `lib/src/core/state/ui_bridge.dart` | 新建：`MovaUiBridge/MovaUiSink/MovaUiLink`（包内） | C04b |
| `lib/src/core/engine.dart` | 实现 `MovaUiBridge`；四个动词与 `_announceReady` 分支；`:2819` 改用常量 | C04a、C04b |
| `lib/src/core/cutover/cutover_engine.dart` | 实现 `MovaUiBridge`；四个动词分支；`_attach` 一行 | C04b |
| `lib/src/core/api.dart` | 六个 UI 成员的弃用公告（dartdoc） | C04c |
| `lib/src/ui/player.dart` | `chrome:`、`style:` 参数；chrome 归属；`MovaChromeScope`、`MovaStyleScope` | C04c、C06b |
| `lib/src/ui/scope/selector.dart` | `MovaUiSelect` 改读 `movaUiOf` | C04c |
| `lib/src/ui/components/gesture_layer.dart`、`bottom_bar.dart`、`preview.dart` | 改用 `movaUiOf` | C04c |
| `lib/src/ui/skins/default_skin.dart` | `_BarVisibility` 续期 `Listener` | C04d |
| `lib/src/ui/components/common.dart` | `MovaIconButton` 键盘激活续期；`_iconLabel` 读样式文案 | C04d、C06c |
| `lib/src/ui/style/style.dart` | 新建：`MovaPlayerStyle`、`MovaDanmakuStyle`（公开）、`MovaStyleScope`、查找函数（包内） | C06a |
| 16 个组件文件（第 1.1 节） | 样式读取改走 `MovaPlayerStyle.xxxOf` | C06b |
| `lib/src/core/options/options.dart` | 五个字段的弃用公告（dartdoc） | C06b |
| `lib/src/core/options/strings.dart` | 新增 15 个文案字段 | C06c |
| `lib/src/core/model/quality.dart` | 两个字面量提常量（值不变） | C06c |
| `lib/src/ui/view.dart` | `style:` 透传（C06b）；旧路径层与样式节比较（C06d） | C06b、C06d |
| `lib/src/ui/style/icons.dart`、`core/options/theme.dart` | `MovaIcons`；`MovaTheme.progressColor` | C06e |
| `lib/mova.dart` | `export 'src/ui/chrome/chrome.dart' show MovaChrome;`、`export 'src/ui/style/style.dart' show MovaPlayerStyle, MovaDanmakuStyle;`（C06e 加 `MovaIcons`） | C04c、C06b、C06e |
| `test/support/fake_bridge_api.dart` | 新建：`FakeBridgeApi extends FakeMovaApi implements MovaUiBridge`（新文件，不和 A 块改 `fake_api.dart` 撞车） | C04b |

用 `export ... show` 只导出公开类，包内辅助函数留在同一库里访问私有成员，不用 `@internal`（避免 analyzer 对已导出库里 `@internal` 成员的诊断）。

---

## 4. Global Constraints

- core 不 import Flutter；`purity_test` 的 `_mediaKitExceptions` 不改。
- `MovaApi` 零新增成员；`FakeMovaApi` 不改（新替身放新文件）。
- 现有断言不改；若意外需要改，提交说明逐条写"旧断言为什么错"（总计划 3.1 第 4 条），并回写本子计划第 6 节。
- 注释中文、简短；公开 API 带参数、返回、示例；本计划不新增组件类（`componentName` 规则不涉及）。
- 同一字面量出现 2 次以上提常量（`kMovaHudDuration`、两个清晰度标签常量）。
- 时间相关断言用 `fakeAsync` / `tester.pump(Duration)`，不 sleep、不用 `DateTime.now()`。
- C07、C10–C16 的提交**不得引用** `MovaChrome`、`MovaPlayerStyle`、`movaUiOf`、`MovaStyleScope`、`MovaUiBridge`（C05、C08、C17 例外）——这是第 9.2 节能干净移出的前提，CP3 前 grep 一次。

---

## Task C04a：`feat(mova): MovaChrome 每视图交互态状态机（未接线）`

**Files：** Create `lib/src/ui/chrome/chrome.dart`；Modify `lib/src/core/state/ui_state.dart`（加 `kMovaHudDuration`）、`lib/src/core/engine.dart:2819`（改用常量，行为不变）；Test `test/ui/chrome/chrome_test.dart`。本提交不导出、不接线，语义与引擎旧实现一一对应（P1-13 留到 C04d）。

**Produces：**

```dart
/// HUD 浮层自动收起前的停留时长。
const Duration kMovaHudDuration = Duration(milliseconds: 800);

/// 一个播放器视图自己的交互态：控制条显隐、HUD、拖动与预览位置，含自动隐藏计时。
///
/// [MovaPlayer] 默认为每个视图建一份并负责销毁；经 `MovaPlayer(chrome:)` 传入的由宿主销毁。
/// 同一时刻只能挂在一个视图上。
///
/// 示例：
/// ```dart
/// final chrome = MovaChrome();
/// MovaPlayer(api: engine, chrome: chrome);
/// chrome.show(sticky: true); // 打开自定义面板时让控制条常显
/// ```
class MovaChrome extends ChangeNotifier implements ValueListenable<MovaUiState> {
  /// 创建交互态，初值为控制条可见、无 HUD、无拖动。
  MovaChrome();

  final MovaBus<MovaUiState> _bus = MovaBus<MovaUiState>(const MovaUiState());
  MovaCtrlsConfig _controls = const MovaCtrlsConfig();
  Timer? _autoHideTimer;
  Timer? _hudTimer;
  bool _sticky = false;
  bool _disposed = false;

  /// 当前交互态。
  @override
  MovaUiState get value => _bus.value;

  /// 同 [value]，与旧 `MovaApi.uiState` 同名，便于迁移。
  MovaUiState get uiState => _bus.value;

  /// 交互态变化流；新订阅者立即收到当前值，连续相同值不重复发。
  Stream<MovaUiState> get uiStates => _bus.stream;

  /// 显示控制条；[sticky] 为 true 时不自动隐藏，直到下一次 [show] 或 [hide]。
  void show({bool sticky = false}) {
    if (_disposed) return;
    _cancelAutoHide();
    _sticky = sticky;
    _emit(value.copyWith(controlsVisible: true));
    if (!sticky) _armAutoHide();
  }

  /// 隐藏控制条并取消自动隐藏计时。
  void hide() {
    if (_disposed) return;
    _cancelAutoHide();
    _sticky = false;
    _emit(value.copyWith(controlsVisible: false));
  }

  /// 在显示与隐藏之间切换（单击画面用）。
  void toggle() => value.controlsVisible ? hide() : show();

  /// 显示临时提示 [hud]，[kMovaHudDuration] 后收起；不传 [text] 会清掉旧文本。
  void showHud(MovaHud hud, {String? text}) { /* 同 engine.dart:2810-2822 */ }

  /// 标记拖动开始/结束；[previewAt] 为拖动预览位置，结束时清空。
  void setDragging(bool v, {Duration? previewAt}) { /* 同 engine.dart:2825-2835 */ }

  /// 同步取消计时器；之后各动词静默无效，[uiStates] 结束。
  @override
  void dispose() { /* _disposed = true; 取消两个计时器; _bus.close(); super.dispose(); */ }

  void _armAutoHide() {
    if (_controls.autoHide) _autoHideTimer = Timer(_controls.autoHideDelay, hide);
  }

  void _emit(MovaUiState next) {
    if (next == value) return;
    _bus.emit(next);
    notifyListeners();
  }
}

/// 包内：更新自动隐藏等控制条配置（MovaPlayer 调用）。
void movaSetChromeControls(MovaChrome chrome, MovaCtrlsConfig controls) => chrome._controls = controls;
```

**断言（8）：**
1. 初值 `chrome.value == const MovaUiState()`，`uiStates` 首个事件就是它。
2. `show()` 后推进 2.9s 仍可见，推进到 3s 变为不可见（默认 `autoHideDelay`）。
3. `show(sticky: true)` 后推进 10s 仍可见；随后 `show()` 重新计时，3s 后隐藏。
4. 2s 时再 `show()` 以第二次为准：4.9s 仍可见、5s 隐藏（对应 `engine_verbs_test.dart:479` 的语义）；`hide()` 取消挂起的计时器，之后推进 5s 监听器计数不再增加；相同值不重复通知。
5. `movaSetChromeControls(c, MovaCtrlsConfig(autoHide: false))` 后 `show()` 不武装计时器（`async.nonPeriodicTimerCount == 0`）。
6. `showHud(MovaHud.seek, text: '00:20')` → `hud == seek`、`hudText == '00:20'`；800ms 后 `hud == none`、`hudText == null`；再 `showHud(MovaHud.volume)` 不传文本会清掉旧文本。
7. `setDragging(true, previewAt: 12s)` → `dragging` 为 true、`previewAt == 12s`；`setDragging(false)` → 两者复位为 false/null。
8. `show()` + `showHud(volume)` 后 `nonPeriodicTimerCount == 2`，`dispose()` 返回前降为 0；dispose 后各动词不抛、不通知；`uiStates` 以 done 结束。

**验收：** analyze 0；测试 **N0+8**；现有测试零改动。

---

## Task C04b：`feat(mova): 旧 UI 接口与视图的过渡桥，无视图时行为不变`

**Files：** Create `lib/src/core/state/ui_bridge.dart`（D3 骨架）、`test/support/fake_bridge_api.dart`；Modify `lib/src/core/engine.dart`、`lib/src/core/cutover/cutover_engine.dart`；Test `test/core/ui_bridge_test.dart`。本提交没人去连接视图，对用户无可见变化。

**engine.dart（只动 UI 段落与类声明行）：**

```dart
class MovaEngine implements MovaApi, MovaProgressSource, MovaKeepAlive, MovaPlayerMute,
    MovaHandoffRetirable, MovaUiBridge {
  // 已连接的视图。
  final Set<_EngineUiLink> _uiLinks = {};

  @override
  bool get uiReady => _readyAnnounced && !_disposed;

  @override
  MovaUiLink linkUi(MovaUiSink sink) {
    final link = _EngineUiLink(this, sink);
    if (_disposed) return link..closed = true;
    if (_uiLinks.isEmpty) {
      // 视图接管：旧路径的计时器不再有人负责。
      _autoHideTimer?.cancel();
      _autoHideTimer = null;
      _hudTimer?.cancel();
      _hudTimer = null;
    }
    _uiLinks.add(link);
    return link;
  }

  @override
  void showControls({bool sticky = false}) {
    if (_disposed) return;
    if (_uiLinks.isNotEmpty) {
      for (final l in [..._uiLinks]) l.sink.legacyShow(sticky: sticky);
      return;
    }
    // ……原逻辑不变……
  }
  // hideControls / showHud / setDragging 同样分支。

  void _announceReady() {
    // ……
    if (_uiLinks.isEmpty) {
      if (options.controls.showOnStart) { showControls(); } else { hideControls(); }
    }
    // ……其余不变……
  }
  // dispose 同步前缀：把所有连接标为关闭并清空（不回调）。
}

/// 引擎侧的一条视图连接。
class _EngineUiLink implements MovaUiLink {
  _EngineUiLink(this._engine, this.sink);
  final MovaEngine _engine;
  final MovaUiSink sink;
  bool closed = false;

  @override
  void mirror(MovaUiState state) {
    if (!closed && !_engine._disposed) _engine._ui.emit(state);
  }

  @override
  void unlink() {
    if (closed) return;
    closed = true;
    _engine._uiLinks.remove(this);
  }
}
```

**cutover_engine.dart（只动类声明行、`_attach` 一行、四个动词）：**

```dart
// 连在代理上的视图；换指不迁移。
final Set<_ProxyUiLink> _uiLinks = {};

@override
bool get uiReady {
  final a = _active;
  return a is MovaUiBridge && (a as MovaUiBridge).uiReady;
}

// _attach 内（原 :234）：
_activeUiSub = engine.uiStates.listen((s) {
  if (_uiLinks.isEmpty) _uiState.emit(s);
});

@override
void showControls({bool sticky = false}) {
  if (_disposed) return;
  if (_uiLinks.isNotEmpty) {
    for (final l in [..._uiLinks]) l.sink.legacyShow(sticky: sticky);
    return;
  }
  _active.showControls(sticky: sticky);
}
// 其余三个动词同理；_ProxyUiLink.mirror → _uiState.emit；
// unlink 后若已无连接：_uiState.emit(_active.uiState) 重新对齐。
```

**`FakeBridgeApi`：** 继承 `FakeMovaApi`；`bool ready` 可设；`sinks` 列表；四个旧动词先照旧记账（`super`），有连接时再转发；`mirror` 走 `pushUi`。

**断言（8）：**
1. 连接后断开，引擎回到旧路径：`linkUi(s).unlink()` 后 `showControls()`，3s 后 `uiState.controlsVisible` 为 false，sink 日志为空。
2. 有连接时四个旧动词只转发：日志依次为 `show(sticky:true)`、`hide`、`hud(volume,x)`、`drag(true,3s)`；`engine.uiState` 仍等于连接前的值；再推进 4s 日志与 `uiState` 都不变。
3. `link.mirror(MovaUiState(controlsVisible: false, hud: MovaHud.volume))` 后 `engine.uiState` 等于该值，`uiStates` 订阅者恰好收到一次；同值再 mirror 不重复发。
4. 有连接时 `open()` 到就绪：`MovaReady` 照发，sink 日志为空，推进 4s `uiState` 仍为初值（引擎没有自己显隐或计时）；`uiReady` 由 false 变 true。
5. 先 `showControls()`（旧路径已武装 3s）再 `linkUi`：推进 5s，sink 没收到 `hide`、`uiState.controlsVisible` 仍为 true（挂接时取消了旧计时器）。
6. `dispose()` 后 sink 不再收到任何回调；`link.mirror(...)` 与 `link.unlink()` 不抛；dispose 后 `linkUi` 返回已关闭的连接。
7. 代理有连接时：`made.first.pushUi(MovaUiState(controlsVisible: false))` 不改变代理 `uiState`；`proxy.hideControls()` 转给 sink，`made.first.calls` 不含 `hideControls`。
8. 代理换指不跳变：连接 + `mirror(controlsVisible: false)` → `prepare` + `warmToReady(made[1])` + `commit()`，影子 `pushUi(controlsVisible: true)` 后代理 `uiState.controlsVisible` 仍为 false；`unlink()` 后代理 `uiState` 等于新生效引擎的 `uiState`；`proxy.uiReady` 跟随 `_active`。

**验收：** analyze 0；测试 **N0+16**；`test/core/` 下 `engine_verbs_test`、`engine_test`、`engine_streams_test`、`engine_fuzz_test`、`state_test`、`cutover_engine_test`（含 `:66-76` 的 uiStates 转发用例）零改动全绿。

---

## Task C04c：`feat(mova): 每个 MovaPlayer 视图持有 MovaChrome，组件改读视图交互态`

**Files：** Modify `lib/src/ui/chrome/chrome.dart`（绑定、`MovaChromeScope`、`maybeOf/of`、`MovaUiPort`、`movaUiOf`）、`lib/src/ui/player.dart`、`lib/src/ui/scope/selector.dart`、`lib/src/ui/components/gesture_layer.dart`、`bottom_bar.dart`、`preview.dart`、`lib/src/core/api.dart`（公告）、`lib/mova.dart`、`CHANGELOG.md`；Test `test/ui/chrome/chrome_player_test.dart`、`test/ui/chrome/ui_access_test.dart`。

**chrome.dart 增量：**

```dart
// MovaChrome 内：
MovaApi? _api;
MovaUiLink? _link;
StreamSubscription<MovaEvent>? _eventSub;
late final _ChromeSink _sink = _ChromeSink(this);

void _bind(MovaApi api) {
  assert(_api == null, '一个 MovaChrome 同一时刻只能挂一个视图');
  _api = api;
  _cancelTimers();
  _sticky = false;
  // 只继承显隐；HUD、拖动、预览是瞬时态。
  _bus.emit(MovaUiState(controlsVisible: api.uiState.controlsVisible));
  // 不在 build 期间同步通知；微任务里再通知，期间若已销毁就跳过。
  scheduleMicrotask(() {
    if (!_disposed) notifyListeners();
  });
  final bridge = api is MovaUiBridge ? api as MovaUiBridge : null;
  final ready = bridge?.uiReady ?? false;
  _link = bridge?.linkUi(_sink);
  if (value.controlsVisible && ready) _armAutoHide();
  _eventSub = api.events.listen((e) {
    if (e is MovaReady) _controls.showOnStart ? show() : hide();
  });
}

void _unbind() { /* 取消计时器与事件订阅；_link?.unlink(); _api = null; */ }

// _emit 末尾加：_link?.mirror(next);

/// 取最近视图的交互态；不在 MovaPlayer 下或引擎不支持时为 null。
static MovaChrome? maybeOf(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<MovaChromeScope>()?.chrome;

/// 同 [maybeOf]，找不到时抛 [FlutterError]。
static MovaChrome of(BuildContext context) { /* … */ }

/// 宿主经旧动词发来的命令，转成本视图的操作。
class _ChromeSink implements MovaUiSink { /* legacyShow→show 等 */ }

/// 包内：向下发布本视图的 chrome。
class MovaChromeScope extends InheritedWidget {
  const MovaChromeScope({super.key, required this.chrome, required super.child});
  final MovaChrome? chrome;
  @override
  bool updateShouldNotify(MovaChromeScope old) => !identical(chrome, old.chrome);
}

/// 包内：组件读写交互态的统一入口，有 chrome 用 chrome，否则回落到 api 旧接口。
class MovaUiPort {
  MovaUiPort._(this._chrome, this._api);
  /// 有 chrome 用 chrome，没有就回落到 [api] 的旧接口。
  factory MovaUiPort.of(MovaChrome? chrome, MovaApi api) => MovaUiPort._(chrome, api);
  /// 只走 [api] 的旧接口。
  factory MovaUiPort.forApi(MovaApi api) => MovaUiPort._(null, api);
  final MovaChrome? _chrome;
  final MovaApi _api;
  MovaUiState get uiState => _chrome?.uiState ?? _api.uiState;
  Stream<MovaUiState> get uiStates => _chrome?.uiStates ?? _api.uiStates;
  void show({bool sticky = false}) => _chrome != null ? _chrome.show(sticky: sticky) : _api.showControls(sticky: sticky);
  void hide() => _chrome != null ? _chrome.hide() : _api.hideControls();
  void toggle() => _chrome != null
      ? _chrome.toggle()
      : (_api.uiState.controlsVisible ? _api.hideControls() : _api.showControls());
  void showHud(MovaHud hud, {String? text}) => /* 同上 */;
  void setDragging(bool v, {Duration? previewAt}) => /* 同上 */;
}

/// 包内：[listen] 为 true 时依赖 chrome 作用域（build 里用），initState 里传 false。
MovaUiPort movaUiOf(BuildContext context, {bool listen = false}) { /* … */ }

void movaBindChrome(MovaChrome chrome, MovaApi api) => chrome._bind(api);
void movaUnbindChrome(MovaChrome chrome) => chrome._unbind();
```

**player.dart：**

```dart
/// 本视图的交互态；不传时，引擎支持视图交互态就自动建一份并负责销毁。
/// 传入的实例由宿主销毁，同一时刻只能给一个 MovaPlayer 用。
///
/// 示例：`MovaPlayer(api: engine, chrome: chrome)`
final MovaChrome? chrome;

// _MovaPlayerState：
MovaChrome? _chrome;
bool _ownsChrome = false;
MovaUiPort get _ui => MovaUiPort.of(_chrome, widget.api);

void _attachChrome() {
  final given = widget.chrome;
  _ownsChrome = given == null && widget.api is MovaUiBridge;
  _chrome = given ?? (_ownsChrome ? MovaChrome() : null);
  final c = _chrome;
  if (c == null) return;
  movaSetChromeControls(c, widget.api.options.controls); // C06b 改为样式查找
  movaBindChrome(c, widget.api);
}

void _detachChrome() {
  final c = _chrome;
  if (c == null) return;
  movaUnbindChrome(c);
  if (_ownsChrome) c.dispose();
  _chrome = null;
}
// initState：_attachChrome()；didUpdateWidget：api 或 chrome 变了就先 detach 再 attach，并 _skinTree = null；
// dispose：_detachChrome()；悬停/快捷键（:217、:223）改调 _ui.show()；
// build：MovaScope(api) > MovaChromeScope(chrome: _chrome) > …… > KeyedSubtree(key: ValueKey((widget.api, _chrome)))
```

**组件改动：** `MovaUiSelect.build` 改为 `final ui = movaUiOf(context, listen: true)`，其余不变；手势层 9 处改为 `movaUiOf(context).xxx`（单击用 `toggle()`）；进度条 `:375,400` 同理；预览气泡 `initState` 用 `movaUiOf(context)`（不建依赖）读初值并订阅 `uiStates`。

**公告：** `api.dart` 六个成员各补一段：

```dart
/// 过渡说明：每个 MovaPlayer 视图现在各有一份 `MovaChrome`。本成员一个版本内照常可用——
/// 有视图挂载时，调用会转给所有视图，读到的是最近一次变化的那个视图；没有视图时行为不变。
/// 计划在下个版本弃用，新代码请用 `MovaChrome.of(context)`。
```

**CHANGELOG（Unreleased）：**
- Feat：每个 `MovaPlayer` 视图各自持有交互态 `MovaChrome`；同一引擎挂多个视图（页面 + 小窗、后续的全屏路由）不再互相串扰；cutover 换指时控制条不再跳成新引擎的状态。没有视图挂载时旧接口行为完全不变；有视图时，显示/隐藏在 `MovaReady` 之后由视图执行（旧读者看到的 `uiState` 晚一个微任务更新）。宿主自写的 `MovaApi` 实现本版本仍走旧接口。
- Deprecated（公告，下个版本加注解）：`MovaApi.showControls/hideControls/showHud/setDragging/uiState/uiStates` → `MovaChrome`（`show/hide/toggle/showHud/setDragging/uiState/uiStates`）。

**断言（11）：** 1–3、9 用宿主传入的 chrome 便于断言；7 验证默认创建路径。
1. 两视图互不串扰：同一 `FakeBridgeApi` 上下挂两个 `MovaPlayer(chrome: a/b)`，点 A 的画面中心 → `a.uiState.controlsVisible` 为 false、`b` 仍为 true；A 子树里 `_BarVisibility` 的 `AnimatedOpacity.opacity == 0`，B 子树里为 1。
2. HUD 与拖动只在本视图：A 上横滑 seek → `a.uiState.dragging` 为 true、A 子树出现 seek HUD 文本；`b.uiState == const MovaUiState()`，B 子树里没有 HUD。
3. 旧动词广播：`api.hideControls()` → a、b 都隐藏；`api.showControls(sticky: true)` → 都显示，推进 10s 仍显示。
4. 镜像后写者胜出：点 A 隐藏后 `api.uiState.controlsVisible == false`；再点 B（B 隐藏）、点 A（A 显示）后 `api.uiState.controlsVisible == true`。
5. `showOnStart`：`api.pushEvent(const MovaReady())` → 两视图都显示、3s 后都隐藏；`MovaCtrlsConfig(showOnStart: false)` 时 `MovaReady` 后都隐藏。
6. 挂载时机：`ready = true` 且旧状态可见时挂载 → 3s 后自动隐藏；`ready = false` 时挂载 → 推进 10s 仍可见，直到 `MovaReady`。
7. 归属：不传 chrome 时，卸载前用 `MovaChrome.maybeOf(t.element(find.byType(AnimatedOpacity).first))` 取到实例，卸载后 `api.sinks` 为空、该实例已销毁（`uiStates` 以 done 结束）；传入的 chrome 卸载后未销毁，能再挂到另一个 `MovaPlayer`。
8. 换 api：同一 `MovaPlayer` 从 api1 换到 api2 → `api1.sinks` 为空、`api2.sinks` 长度 1；之后 `api1.hideControls()` 不影响视图。
9. 真实 cutover 换指（`t.runAsync`）：`MovaCutoverEngine(engineFactory: () => FakeMovaApi(options: 启用 cutover))` 挂 `MovaPlayer(chrome: c)`，点击隐藏 → prepare/commit 完成（`renderEpoch` 1）→ 影子 `pushUi(controlsVisible: true)` 后 `c.uiState.controlsVisible` 仍为 false、`_BarVisibility` 透明度仍为 0。
10. 非桥接 api 走旧路径：`FakeMovaApi` 上的 `MovaPlayer` 里 `MovaChrome.maybeOf` 为 null；点画面记录 `hideControls`（与 `gesture_test.dart:273` 同一条路径，这里只锚定选择逻辑）。
11. 守卫：扫描 `lib/src/ui/**/*.dart`，除 `ui/chrome/chrome.dart` 外不得出现 `\b(?:_?api|widget\.api)\.(showControls|hideControls|showHud|setDragging|uiStates?)\b`。

**验收：** analyze 0；测试 **N0+27**；第 6 节"需复核但预期不改"的文件全绿。

---

## Task C04d：`fix(mova): 拖动与按钮操作续期自动隐藏`

**Files：** Modify `lib/src/ui/chrome/chrome.dart`（`setDragging` 保持、`touch()`；`MovaUiPort.touch`）、`lib/src/ui/skins/default_skin.dart`（`_BarVisibility`）、`lib/src/ui/components/common.dart`（键盘激活续期）、`CHANGELOG.md`；Test `test/ui/chrome/auto_hide_renew_test.dart`。

```dart
// MovaChrome：
void setDragging(bool v, {Duration? previewAt}) {
  if (_disposed) return;
  if (v) {
    _cancelAutoHide(); // 拖动期间不隐藏
    _emit(value.copyWith(controlsVisible: true, dragging: true, previewAt: previewAt));
  } else {
    _emit(value.copyWith(dragging: false, clearPreview: true));
    if (value.controlsVisible && !_sticky) _armAutoHide();
  }
}

/// 有操作发生：控制条可见、未常显、未在拖动时重新开始自动隐藏计时。
void touch() {
  if (_disposed || !value.controlsVisible || _sticky || value.dragging) return;
  _cancelAutoHide();
  _armAutoHide();
}

// MovaUiPort：
void touch() => _chrome?.touch(); // 旧路径不续期，保持原行为

// _BarVisibility：
child: Listener(
  behavior: HitTestBehavior.deferToChild, // 只在命中按钮/栏时触发，不抢手势
  onPointerDown: (_) => movaUiOf(context).touch(),
  child: child,
),
```

**CHANGELOG：** Fix：拖进度条或在画面上横滑时控制条与预览缩略图不再中途淡出，松手后重新计时；点控制条上的按钮（含键盘激活）会续期自动隐藏。只对 `createMovaEngine`/`MovaCutoverEngine` 驱动的视图生效。

**断言（5）：**
1. `show()` 后 1s 开始拖底栏进度条并持续 5s：期间 `uiState.controlsVisible` 恒为 true、预览气泡在；松手后 2.9s 仍可见，3s 隐藏。
2. 控制条隐藏时在画面上横滑 seek：拖动中 `controlsVisible` 与 `dragging` 都为 true；松手 3s 后隐藏。
3. `show()` 后每 2s 点一次顶栏 fit 按钮，共 4 次，期间一直可见；最后一次点击后 3s 隐藏；其中一次改为聚焦按钮后按 Enter，同样续期。
4. `show(sticky: true)` 后拖动结束、点按钮，推进 10s 仍可见，且没有自动隐藏计时器。
5. 非桥接 `FakeMovaApi` 上点按钮不新增 `showControls` 记录（`touch` 为空操作），拖进度条仍只记 `setDragging`。

**验收：** analyze 0；测试 **N0+32**。

---

## Task C06a：`feat(mova): MovaPlayerStyle 与样式查找链（未接线）`

**Files：** Create `lib/src/ui/style/style.dart`；Test `test/ui/style/style_test.dart`。本提交不改组件、不导出。

```dart
/// 播放器视图的外观与交互配置：主题、文案、手势、控制条行为、弹幕样式。
///
/// 优先级：`MovaPlayer(style:)` > `ThemeData.extensions` 里的本类 > 引擎 `MovaOpts` 的同名节
/// （旧路径，计划下个版本弃用）> 默认值。各节独立回落、整体替换；换主题只重建组件，不重建引擎。
///
/// 示例：
/// ```dart
/// MaterialApp(theme: ThemeData(extensions: const [
///   MovaPlayerStyle(theme: MovaTheme(accentColor: 0xFF00B0FF)),
/// ]));
/// MovaPlayer(api: engine, style: const MovaPlayerStyle(strings: MovaStrs(live: 'ON AIR')));
/// ```
@immutable
class MovaPlayerStyle extends ThemeExtension<MovaPlayerStyle> {
  const MovaPlayerStyle({this.theme, this.strings, this.gesture, this.controls, this.danmaku});

  /// 颜色与字号；null 时回落。
  final MovaTheme? theme;
  /// 界面文案；null 时回落。
  final MovaStrs? strings;
  /// 手势映射与灵敏度；null 时回落。
  final MovaGestureConfig? gesture;
  /// 控制条行为（自动隐藏、淡入淡出、快捷键）；null 时回落。
  final MovaCtrlsConfig? controls;
  /// 弹幕样式；null 时回落。
  final MovaDanmakuStyle? danmaku;

  /// 当前视图生效的主题。只在 build 或事件回调里调用。
  static MovaTheme themeOf(BuildContext context) =>
      _pick(context, (s) => s.theme) ?? movaLegacyOptionsOf(context).theme;
  // stringsOf / gestureOf / controlsOf 同理；
  // danmakuOf：_pick(...) ?? MovaDanmakuStyle.fromConfig(movaLegacyOptionsOf(context).danmaku)

  @override
  MovaPlayerStyle copyWith({ /* 五节 */ });

  /// 离散切换，不做插值。
  @override
  MovaPlayerStyle lerp(covariant ThemeExtension<MovaPlayerStyle>? other, double t) =>
      other is MovaPlayerStyle && t >= 0.5 ? other : this;
  // == / hashCode 按五节比较
}

/// 弹幕的展示样式；条目与开关仍在 `MovaOpts.danmaku`。
@immutable
class MovaDanmakuStyle {
  const MovaDanmakuStyle({
    this.trackCount = 4,
    this.trackHeight = 28.0,
    this.fontSize = 14.0,
    this.opacity = 0.9,
    this.crossDuration = const Duration(seconds: 8),
  }) : assert(trackCount > 0, 'trackCount must be positive');
  // 字段注释略
  factory MovaDanmakuStyle.fromConfig(MovaDanmakuConfig c) => /* 取 5 个样式字段 */;
  /// 用本样式覆盖 [data] 的样式字段，保留 enabled 与 items。
  MovaDanmakuConfig applyTo(MovaDanmakuConfig data) => data.copyWith(/* 5 个样式字段 */);
}

/// 包内：MovaPlayer 下发 widget 参数，MovaView 下发旧路径 options。
class MovaStyleScope extends InheritedWidget {
  const MovaStyleScope({super.key, this.local, this.legacy, required super.child});
  final MovaPlayerStyle? local;
  final MovaOpts? legacy;
  static MovaStyleScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MovaStyleScope>();
  @override
  bool updateShouldNotify(MovaStyleScope old) => local != old.local || !identical(legacy, old.legacy);
}

/// 包内：先 widget 参数（可显式传入，供 MovaPlayer 自己解析），再 ThemeExtension。
T? _pick<T>(BuildContext context, T? Function(MovaPlayerStyle s) f, {MovaPlayerStyle? local}) { /* … */ }

/// 包内：旧路径 options——MovaView 下发的优先，其次当前 api 的，都没有用默认。
MovaOpts movaLegacyOptionsOf(BuildContext context) =>
    MovaStyleScope.maybeOf(context)?.legacy ??
    context.dependOnInheritedWidgetOfExactType<MovaScope>()?.api.options ??
    const MovaOpts();

/// 包内：MovaPlayer 在自己的 context 上解析控制条配置（它在自己的作用域之上）。
MovaCtrlsConfig movaResolveControls(BuildContext context, MovaPlayerStyle? local) =>
    _pick(context, (s) => s.controls, local: local) ?? movaLegacyOptionsOf(context).controls;
```

**断言（8）：**
1. 什么都不配：`themeOf == const MovaTheme()`、`stringsOf == const MovaStrs()`，其余三节与 `danmakuOf` 为默认（挂在 `MovaScope(FakeMovaApi())` 下用 `Builder` 取值；不在 `MovaScope` 下也返回默认、不抛）。
2. 旧路径：`FakeMovaApi(options: MovaOpts(theme: MovaTheme(accentColor: 0xFF00FF00)))` → `themeOf(context).accentColor == 0xFF00FF00`。
3. `ThemeExtension` 胜过旧路径：扩展里 `accentColor: 0xFF0000FF` → 取扩展值；扩展没设的 `strings` 仍取旧路径的值。
4. widget 参数胜过扩展：`MovaStyleScope(local: MovaPlayerStyle(theme: 红))` → 红；`local` 只设 `strings` 时 `theme` 回落到扩展（各节独立）。
5. 节整体替换：扩展只改 `accentColor`，`textColor` 为 `MovaTheme` 默认值，而不是旧路径里设的 `textColor`。
6. 切换 `ThemeData` 后 `Builder` 读到新值；`FakeMovaApi.calls` 没有新增（查找不碰 api）。
7. `lerp(other, 0.3)` 返回自身、`0.7` 返回 other、other 为 null 返回自身；`copyWith` 只替换指定节；`==`/`hashCode` 按节比较。
8. `MovaDanmakuStyle.fromConfig` 取样式字段；`applyTo` 覆盖 5 个样式字段且 `identical(result.items, data.items)`、`enabled` 不变；`MovaDanmakuStyle(trackCount: 0)` 抛 `AssertionError`。

**验收：** analyze 0；测试 **N0+40**（若按总计划顺序先做 C05，则再加 C05 的增量，见第 5 节）。

---

## Task C06b：`feat(mova): 组件改读 MovaPlayerStyle，MovaPlayer 与 MovaView 增加 style 参数`

**Files：** Modify 第 1.1 节列出的 16 个 UI 文件（56 处）、`lib/src/ui/player.dart`、`lib/src/ui/view.dart`（`style:` 透传）、`lib/src/core/options/options.dart`（五个字段公告）、`lib/mova.dart`、`CHANGELOG.md`；Test `test/ui/style/style_player_test.dart`、`test/ui/style/style_access_test.dart`。

**机械部分（无参数、无扩展时结果与改前逐字一致，现有测试零改动即验收）：**
- `final theme = api.options.theme;` → `final theme = MovaPlayerStyle.themeOf(context);`（33 处）；strings 8 处同理。
- 手势层 8 处 `_api.options.gesture` → `MovaPlayerStyle.gestureOf(context)`（都在回调里，有 `context`）。
- `default_skin.dart:288` 的 `fadeDuration` → `MovaPlayerStyle.controlsOf(context).fadeDuration`。
- `danmaku.dart:45` → `final data = movaLegacyOptionsOf(context).danmaku; if (!data.enabled || data.items.isEmpty) …; config: MovaPlayerStyle.danmakuOf(context).applyTo(data)`。

**player.dart：**

```dart
/// 本视图的样式；优先级最高，未设的节回落到主题扩展与引擎配置。
///
/// 示例：`MovaPlayer(api: engine, style: const MovaPlayerStyle(strings: MovaStrs(live: 'ON AIR')))`
final MovaPlayerStyle? style;

// _MovaPlayerState：在 didChangeDependencies 与 didUpdateWidget 里
//   _controls = movaResolveControls(context, widget.style);
//   if (_chrome != null) movaSetChromeControls(_chrome!, _controls);
// :186/:282/:297/:298/:301 的 shortcuts 改读 _controls.shortcuts；
// build 里在 MovaChromeScope 之外再包：
//   MovaStyleScope(local: widget.style, legacy: MovaStyleScope.maybeOf(context)?.legacy, child: …)
```

**view.dart：** 增加 `style` 参数，原样传给内部 `MovaPlayer`（旧路径层在 C06d）。

**公告：** `options.dart` 五个字段各补一段"计划在下个版本弃用：改用 `MovaPlayerStyle`（`MovaPlayer(style:)` 或 `ThemeData.extensions`）；本版本仍作为最低优先级的回落值"。

**CHANGELOG：**
- Feat：新增 `MovaPlayerStyle`（`ThemeExtension`），主题、文案、手势、控制条行为、弹幕样式可以按视图设置（`MovaPlayer(style:)`、`MovaView(style:)`）或跟随 `ThemeData`；切主题只重建组件，不重建引擎。
- Deprecated（公告）：`MovaOpts.theme/strings/gesture/controls/danmaku` → `MovaPlayerStyle`；弹幕的 `enabled/items` 仍在 `MovaOpts.danmaku`。

**断言（5）：**
1. 同一直播 `FakeMovaApi` 上两个视图：一个 `style: MovaPlayerStyle(strings: MovaStrs(live: 'ON AIR'))` 显示 `ON AIR`，另一个显示 `LIVE`。
2. 真实引擎（`createMovaEngine(kernel: FakeKernel(), …)`）打开后 `kernel.emitBuffering(true)`；在两个带不同扩展的 `ThemeData` 间切换 10 次，缓冲转圈颜色跟着变；全程 `kernel.openedUris.length == 1`、`MovaSourceChange` 只有 1 次、`engine.state.renderEpoch == 0`。
3. `style: MovaPlayerStyle(gesture: MovaGestureConfig(doubleTapSeek: false))` 时双击不记 `seek`；不设时记 `seek`（对照）。
4. `FakeBridgeApi` + `style: MovaPlayerStyle(controls: MovaCtrlsConfig(autoHideDelay: Duration(seconds: 1)))`：`show()` 后 1s 隐藏（chrome 读的是样式不是 `api.options` 的 3s）；`controls: MovaCtrlsConfig(shortcuts: true)` 经样式开启快捷键，聚焦后空格记 `playOrPause`。
5. 守卫：`lib/src/ui/**` 里 `options\.(theme|strings|gesture|controls|danmaku)\b` 不再出现；`movaLegacyOptionsOf(` 只出现在 `ui/style/style.dart` 与 `ui/components/danmaku.dart`；`lib/src/core/**` 里只允许 `engine.dart` 的 3 处旧路径。

**验收：** analyze 0；测试 **N0+45**；现有 UI 测试零改动（`b15_test.dart:100-130` 的"缓存子树不重建、主题变化仍更新"照旧通过）。

---

## Task C06c：`fix(mova): 界面文案不再依赖写死的中文，清晰度与无障碍标签进 MovaStrs`

**Files：** Modify `lib/src/core/options/strings.dart`、`lib/src/core/model/quality.dart`、`lib/src/ui/components/top_bar.dart`、`common.dart`、`center_play.dart`、`speed_button.dart`、`subtitle.dart`、`bottom_bar.dart`（回到直播按钮）、`lib/src/ui/skins/default_skin.dart`（锁定按钮）、`lib/src/ui/mini/mini_skin.dart`、`CHANGELOG.md`；Test `test/ui/style/strings_test.dart`。若 A14b 已给 `MovaStrs` 加了错误文案字段，这里只追加、不重名。

**`MovaStrs` 新增 15 个字段（默认值就是现在写死的中文，默认界面零变化）：** `play`（播放）、`pause`（暂停）、`pip`（画中画）、`aspectRatio`（画面比例）、`rotate`（旋转屏幕）、`enterFullscreen`（进入全屏）、`exitFullscreen`（退出全屏）、`lock`（锁定控制）、`unlock`（解锁控制）、`subtitles`（字幕选择）、`speed`（播放速度）、`action`（操作）、`closeMini`（关闭小窗）、`unknownQuality`（未知）、`labelWithValue`（`String Function(String action, String value)`，默认顶层函数 `movaDefaultLabelWithValue` → `'$action：$value'`，写成顶层函数才能做 const 默认值）。已有的 `quality`、`backToLive` 复用。`==`/`hashCode` 同步。

```dart
// quality.dart
/// auto 档的兼容标签；界面显示改用 `MovaStrs.auto`，下个版本改为中性值。
const String kMovaAutoQualityLabel = '自动';
/// 无分辨率、无码率时的兼容标签；界面显示改用 `MovaStrs.unknownQuality`。
const String kMovaUnknownQualityLabel = '未知';

// top_bar.dart（包内函数）
/// 清晰度的展示文案：auto 与未知档走文案，宿主自定义标签原样显示。
String movaQualityLabel(MovaQuality q, MovaStrs s) =>
    q.isAuto ? s.auto : (q.label == kMovaUnknownQualityLabel ? s.unknownQuality : q.label);
```

内置按钮全部显式传 `label:`（PiP、清晰度、画面比例、旋转、全屏、锁定、字幕、倍速、回到直播、中央播放、关闭小窗）；`_iconLabel` 只给第三方按钮兜底，改读 `MovaPlayerStyle.stringsOf(context)` 与 `labelWithValue`。

**CHANGELOG：** Fix：清晰度"自动/未知"与按钮的无障碍名称、悬停提示改由 `MovaStrs` 提供，可以本地化；默认文案不变。`MovaQuality.auto().label` 本版本仍是 `'自动'`，界面已不再直接显示它，下个版本改为中性值。

**断言（5）：**
1. 默认文案不变：默认皮肤下 `find.bySemanticsLabel('画中画')`、`'清晰度：自动'`、`'画面比例：适应'`、`'进入全屏'`、`'锁定控制'` 都在；清晰度弹层的 auto 行显示 `自动`。
2. 换语言：`style: MovaPlayerStyle(strings: MovaStrs(pip: 'Picture in picture', auto: 'Auto', lock: 'Lock controls', play: 'Play', pause: 'Pause'))` 下语义标签与 tooltip 变成英文；auto 档的按钮说明与弹层行显示 `Auto`，而 `MovaQuality.label` 仍是 `自动`。
3. `MovaQuality(label: kMovaUnknownQualityLabel, uri: 'u')` 在 `unknownQuality: 'Unknown'` 下显示 `Unknown`；`MovaQuality(label: '超清', uri: 'v')` 原样显示。
4. `labelWithValue: (a, v) => '$a: $v'` + `aspectRatio: 'Aspect ratio'`、`fitContain: 'Fit'` → 画面比例按钮语义为 `Aspect ratio: Fit`。
5. `closeMini`、`play`/`pause` 在小窗关闭按钮与中央播放按钮上生效。

**验收：** analyze 0；测试 **N0+50**；`top_bar_test.dart:155-206`、`b16_test.dart` 的语义断言照旧通过。

---

## Task C06d：`fix(mova): MovaView 改样式节不再重建引擎`

**Files：** Modify `lib/src/ui/view.dart`（若 C03 已提供 `engineSectionsEqual`，则同时改 `lib/src/core/options/options.dart` 让它排除五个样式节）、`CHANGELOG.md`；Test `test/ui/view_style_test.dart`；**改写** `test/ui/view_test.dart:105`。

```dart
// view.dart
/// 把样式节归一成默认值，只留引擎读取的节参与比较。
MovaOpts _engineOnly(MovaOpts o) => o.copyWith(
      theme: const MovaTheme(),
      strings: const MovaStrs(),
      gesture: const MovaGestureConfig(),
      controls: const MovaCtrlsConfig(),
      danmaku: const MovaDanmakuConfig(),
    );

// didUpdateWidget：
if (_engine != null && _engineOnly(widget.options) != _engineOnly(oldWidget.options)) { /* 重建 */ }
// （C03 已有 engineSectionsEqual 时改用它，并保证它排除这五节）

// build：
MovaStyleScope(legacy: widget.options, child: MovaPlayer(…, style: widget.style))
```

**CHANGELOG：** Fix：`MovaView(options:)` 只改主题、文案、手势、控制条、弹幕这五节时不再销毁重建引擎，播放不中断；改引擎读取的节仍会重建。

**断言（2 新增 + 1 改写）：**
1. `MovaView(options: MovaOpts(theme: A))` 换成 theme B：`engines.made` 仍为 1、未 dispose、未重开；缓冲转圈颜色变成 B 的 `accentColor`。
2. 父组件每次 build 都内联 `MovaOpts(strings: MovaStrs(adStartingIn: (n) => '$n s'), danmaku: MovaDanmakuConfig(enabled: true, items: [...]))`（闭包与列表每次新建），重建 5 次后 `engines.made` 仍为 1，弹幕照常显示。
3. 改写 `view_test.dart:105`：触发项从 `MovaOpts(theme: MovaTheme(accentColor: 0xFF00FF00))` 改为一个引擎读取的节（推荐 `MovaOpts(preview: MovaPreviewConfig(frameWidth: 99))`，以 C03 确认的引擎节为准），`:107-109` 三条断言原样保留。旧断言错在哪：它把"主题变化"当成引擎配置变化，而主题本该只影响视图。

**验收：** analyze 0；测试 **N0+52**。

---

## Task C06e（可裁剪）：`feat(mova): 图标与进度条颜色进样式（默认不变）`

P2-17 的余下两个子项。整个 Task 独立，不做时这两项转入暂缓，其他 Task 不受影响。

**Files：** Create `lib/src/ui/style/icons.dart`（`MovaIcons`，约 20 个 `IconData` 字段，默认值就是现在的 `Icons.*`；只覆盖播放器 chrome，feed 社交按钮不在内）；Modify `lib/src/ui/style/style.dart`（`icons` 节 + `iconsOf`）、`lib/src/core/options/theme.dart`（`int? progressColor`，null 沿用宿主 `SliderTheme`）、使用这些图标的组件、`bottom_bar.dart`（`activeTrackColor/thumbColor`）、`lib/mova.dart`、`CHANGELOG.md`；Test `test/ui/style/icons_test.dart`。

**断言（3）：**
1. 默认图标不变：`find.byIcon(Icons.picture_in_picture_alt_rounded)` 等仍在。
2. `style: MovaPlayerStyle(icons: MovaIcons(pip: Icons.open_in_new))` → 新图标出现，语义标签仍是 `画中画`（C06c 起标签显式传入，不靠图标反查）。
3. `MovaTheme(progressColor: 0xFF00FF00)` → `SliderTheme.of(sliderContext).activeTrackColor == Color(0xFF00FF00)`；为 null 时等于宿主 `SliderTheme` 的值（与改前一致）。

**验收：** analyze 0；测试 **N0+55**。

---

## 5. 测试数量推进

N0 = C04a 开工当天实测。按建议顺序 C04 → C06 → C05（见第 10 节第 8 条）：

| Task | 新增 | 改写 | 累计 |
|---|---:|---:|---|
| C04a | +8 | 0 | N0+8 |
| C04b | +8 | 0 | N0+16 |
| C04c | +11 | 0 | N0+27 |
| C04d | +5 | 0 | N0+32 |
| C06a | +8 | 0 | N0+40 |
| C06b | +5 | 0 | N0+45 |
| C06c | +5 | 0 | N0+50 |
| C06d | +2 | 1（`view_test.dart:105`） | N0+52 |
| C06e（可裁剪） | +3 | 0 | N0+55 |
| C05（总计划估 +8，不在本子计划内） | +8 | — | N0+63 |

若保持总计划原顺序（C05 在 C04 与 C06 之间），C06 各行累计再加 C05 的增量，并且 C06b 要多迁移 C05 新增的样式读取。

C04 合计 +32（总计划估 +25，多出的主要是桥接层单测 +8）；C06 合计 +23（总计划估 +15；不做 C06e 为 +20）。

---

## 6. 会改写的现有断言

**确定改写（1 处）：**

| 文件:行 | 现在 | 改成 | 提交 | 原因 |
|---|---|---|---|---|
| `test/ui/view_test.dart:105` | `options: const MovaOpts(theme: MovaTheme(accentColor: 0xFF00FF00))` 触发重建 | 换成引擎读取的节（推荐 `preview`），`:107-109` 不动 | C06d | 主题变化按设计不再重建引擎 |

前提：C03 按 D13 对样式节保守。若 C03 已经把这条改掉，C06d 改写数为 0。

**需复核、预期不改：**
- 挂 `MovaPlayer`/`MovaView` 又用真实引擎的 8 个文件（C04c 起它们拿到每视图 chrome，计时器从引擎移到视图）：`test/core/progress_snapshot_test.dart`、`test/testing/testing_test.dart`、`test/ui/auto_pause_test.dart`、`b12_test.dart`、`b15_test.dart`、`feed_player_test.dart`、`review_regression_test.dart`、`view_test.dart`。这些文件里 UI 交互态读写为 0；若有用例因挂起计时器或时序变红，按总计划 3.1 第 4 条在提交说明里逐条写原因并回写本节。
- 用 `FakeMovaApi`（非桥接，走回落口）的 UI 测试：`gesture_test`、`hud_test`、`preview_test`、`overlays_test`、`b14_test`、`b16_test`、`audio_only_interaction_test`、mini 系列——24 处 `pushUi`、14 处 `calls/lastHud` 断言保持原样。
- `test/core/` 下直接调引擎旧 UI 动词的用例（约 90 行）：没有视图连接，走旧路径，不改。
- `top_bar_test.dart:155-206`（auto 行显示 `自动`）、`b16_test.dart` 语义标签：默认 `MovaStrs` 值与原写死文案相同。
- `player_test.dart:29`（只有一个 `MovaScope`）、`skin_test.dart:114`（`RepaintBoundary` 后代）：新增的是 `MovaChromeScope`/`MovaStyleScope`/`Listener`，不影响。

---

## 7. 控制条计时搬到视图后，各场景下的行为（含 C05）

| 场景 | C04 之前 | C04 之后 |
|---|---|---|
| 单视图（`MovaPlayer` + `createMovaEngine`） | 引擎持有；就绪时在 `_announceReady` 里同步按 `showOnStart` 显隐 | 视图持有；收到 `MovaReady` 后显隐（晚一个微任务）；旧读者经镜像看到同样的值 |
| 已就绪后才挂载 | 沿用引擎的计时（可能马上就隐藏） | 以旧状态的可见性播种，`uiReady` 为真且可见时从挂载起重新计时（最多比原来晚一个 `autoHideDelay` 隐藏） |
| 页面 + `MovaMini` 小窗（同一引擎两个 `MovaPlayer`） | 点一处两处一起变 | 各自独立；旧 `api.showControls()` 两处都显示；`api.uiState` 取最近变化的那个视图 |
| cutover 换指（广告 → 正片） | 代理的 UI 态跳成影子的值（影子预热时自己跑过就绪与 3s 计时） | 不跳变，视图计时照常；影子的旧路径计时器在后台空转、随引擎销毁同步取消 |
| 全屏路由（C05） | 没有此功能 | 路由里的新视图自建 chrome，进入时继承可见态并开始计时；内联视图在路由下面保留自己的状态；退出时由 C05 调内联视图 `show()`；键盘焦点、悬停各自独立（B16 本来就按视图） |
| feed 翻页（池引擎复用） | 新页沿用引擎的共享态 | 每页视图各一份；翻回已就绪的页按 `uiReady` 开始计时 |
| 没有视图（宿主只用 api 自建 UI） | 引擎自管 | 完全不变 |
| 宿主自写 `implements MovaApi` | — | 不自动建 chrome，组件走旧接口，完全不变（显式传 `chrome:` 才启用） |
| 锁定、缩放、fit、全屏/小窗标志 | 引擎共享 | 仍共享：它们在 `MovaState` 里，换指由 `_inheritViewSettings` 继承。两个可见视图时"锁、缩放一起变"仍是已知限制，暂缓 |

---

## 8. 真机 / Windows 验证点（CP3）

总计划 CP3 已有的行：F3/A17 precise 280 再跑一次（C04 搬了控制条计时）；C05 全屏路由 Windows 进出 20 次 0 崩溃、Android 返回键先退全屏、锁定时提示解锁；C06 切主题与语言 10 次，位置连续、引擎不重建（`renderEpoch`、会话 id 不变）。本子计划补充检查行如下。取证一律用事件：`chrome.uiStates` 事件、`renderEpoch`、`MovaSourceChange` 计数、QoE 会话 id、原生 time-pos；不用墙钟秒表。Android 实验前确认亮屏解锁。

| 编号 | 平台 | 内容 | 次数 | 通过标准 |
|---|---|---|---|---|
| C04-1 | Android | 拖进度条 5s，栏与缩略图不淡出；松手后按时隐藏 | 5 | 5/5；隐藏事件与 PointerUp 事件间隔 3s±0.3s |
| C04-2 | Android | 页面 + `MovaMini` 小窗同时可见，点一处不影响另一处 | 5 | 5/5（两个 chrome 的事件日志互不出现对方的变化） |
| C04-3 | Android | 广告 → 正片 cutover 换指时控制条不闪 | 10 | `renderEpoch` 递增前后 200ms 内本视图 `uiStates` 无事件，10/10 |
| C04-4 | Windows | 两个视图：悬停唤出、快捷键只作用于聚焦的那个 | 5 | 5/5 |
| C04-5 | Android + Windows | 皮肤专项（总计划 R-10）：默认、哔哩、抖音、极简、小窗皮肤各走点击、拖动、HUD、锁定 | 各 3 | 与 CP2 一致 |
| C05-3 | Android | 进全屏时路由视图控制条可见并按时隐藏；退出后内联视图显示控制条 | 5 | 5/5 |
| C06-2 | Android | `MovaView(options:)` 改主题 5 次 | 5 | `onEngine` 只回调 1 次、`MovaSourceChange` 不新增 |
| C06-3 | Android（TalkBack）+ Windows（讲述人） | 英文 `MovaStrs` 下按钮朗读英文 | 抽查 | 读出英文 |
| C06-4 | Windows | 主题切换动画 10 次（`AnimatedTheme` 走 `lerp`） | 10 | 0 崩溃（转场快照路径不受影响） |

需要新建一个验证页 `example/lib/main_chrome_style_verify.dart` + `example/lib/verify_auto/chrome_style_auto.dart`（AUTORUN 模式），约 0.5–1 人天；总计划 4.0 的 15 个新场景只覆盖 CP0–CP2，7.3 没有计入这一项。

---

## 9. 风险与回退

### 9.1 风险

| # | 风险 | 概率 | 影响 | 应对 |
|---|---|---|---|---|
| RC-1 | 与 A 块冲突：`engine.dart` 的 `_announceReady`（A10 改"每会话一次"）与类声明行；`cutover_engine.dart` 的 `_attach`（A28）与类声明行；`ui/player.dart`（A21）；`overlays.dart`、`MovaStrs`（A14b）；`next_up.dart`、广告覆盖层（A30） | 中 | 中 | 按阶梯在 CP2 后开工；C04 只动 UI 段落；rebase 时以 A 块版本为准、只重放 UI 段落 |
| RC-2 | 旧读者时序：`MovaReady` 之后 `uiState` 晚一个微任务才更新 | 低 | 低 | CHANGELOG 写明；C04c 断言 5 锚定 |
| RC-3 | 两个视图时镜像"后写者胜出"，旧读者看到来回变 | 中 | 低 | 只影响旧读者；dartdoc 写明，推荐改读 `MovaChrome` |
| RC-4 | 宿主自写的 `MovaApi` 实现本版本享受不到 P1-12/P1-13 修复 | 确定 | 低 | 设计如此（行为不变）；CHANGELOG 写明可显式传 `chrome:` |
| RC-5 | 主题动画期间依赖样式的组件每帧重建 | 中 | 低 | `lerp` 离散切换；只在切主题时发生 |
| RC-6 | C03 先行把样式节排除在重建之外，C06d 之前经 `MovaView.options` 改主题失效 | 中 | 中 | 要求 C03 按 D13 保守；C06d 再放宽 |
| RC-7 | 宿主自定义组件在 `initState` 里调 `MovaPlayerStyle.xxxOf`（内部是 `Theme.of`）触发断言 | 低 | 低 | dartdoc 写明只在 build 或回调里调用 |
| RC-8（总计划 R-10） | 自定义皮肤失灵 | 中 | 中 | 旧接口桥接、回落口、守卫测试；CP3 皮肤专项 C04-5 |
| RC-9 | 视图连在代理上，影子的旧路径计时器空转 | 确定 | 极低 | 引擎 dispose 同步取消；下个版本删旧接口时一起消失 |

### 9.2 C04/C06 整体移出本分支

**什么时候：** CP3 里 C04/C05/C06 相关检查两轮修复仍不过（总计划 6.3）。C06 依赖 C04，反过来不依赖，所以只有 C06 出问题时可以只移 C06；C04 出问题必须连 C06（和 C05）一起移。

**干净回退的前提（落地期间就要守住）：**
1. C04/C06 的改动集中在新文件（`ui/chrome/`、`ui/style/`、`core/state/ui_bridge.dart`、`test/ui/chrome/`、`test/ui/style/`、`test/support/fake_bridge_api.dart`、`test/ui/view_style_test.dart`）和第 3 节列出的已有文件段落。
2. C07、C10–C16 不引用 `MovaChrome`、`MovaPlayerStyle`、`movaUiOf`、`MovaStyleScope`、`MovaUiBridge`（第 4 节约束）；CP3 前 grep 确认。
3. C03 对样式节保守（D13），C06d 才放宽。

**步骤（不 reset、不 force push）：**
1. 先处理依赖者：C05 整体 `git revert`。C08 若已落地，**不 revert C08**（C09 依赖 C08，会连带），另起一个提交从新入口文件删掉 `MovaChrome`、`MovaPlayerStyle`、`MovaDanmakuStyle`（以及 `MovaIcons`）的 `show` 导出，并更新 C08 的导出面快照测试。
2. `git revert --no-commit` 按逆序撤 C06e…C06a、C04d…C04a；冲突以"恢复到 C04a 之前的引擎与组件代码"为准；`flutter analyze lib test` 0、`flutter test` 全绿后提交一次：`revert(mova): 移出 C04–C06（CP3 未过）`，正文列出被撤销的提交 hash 与原因。
3. 核对：引擎 `_announceReady` 回到无条件显隐；`MovaApi`、`MovaOpts` 的 dartdoc 回到原文；`view_test.dart:105` 回到用 theme 触发重建（C03 保守做法下仍然成立）；CHANGELOG 里 C04/C06 的条目随 revert 删除；测试数回落约 55 条（加上 C05 的 8 条）。
4. 文档：总计划与 ROADMAP 把 P1-12、P1-13、P2-17、P1-8 的样式部分移回"暂缓"，写明触发条件（例如"下个 minor 前做一次只含 C04 的小分支"）；C17 去掉对应段落。

**部分回退：** C04d（P1-13 续期）、C06d（`MovaView` 不重建）、C06e（图标与进度条颜色）互相独立，可以单独 revert。C04c 是枢纽，撤它就要连 C04d 和 C06 全部一起撤。只撤接线、保留 C04a/C04b/C06a 也可以：C04a/C06a 不导出，C04b 在没有视图连接时等于没改，留着是死代码但无害。

---

## 10. 与总计划不一致之处 / 待确认（都不阻塞，附推荐默认）

1. **读取点计数**：总计划写"lib 约 61、test 约 22–24+"。实测 lib grep 命中 61 行，其中 2 行是 `common.dart:10,15` 的注释，真实代码读取 59 处（core 3 + ui 56，16 个文件）；test 读取 25 处，另有 50 处构造。
2. **`@Deprecated` 措辞冲突**：总计划 §2.4 写 C04/C06 的旧成员"`@Deprecated` 桥接/兜底"，与已拍板的待拍板 18（不加成员级注解）字面矛盾；本子计划按待拍板 18。
3. **范围**：评审的 `MovaChrome` 含 `locked/zoom`，总计划 §2.4 只搬五个 UI 成员。本子计划按总计划，`locked/zoom/fit` 留在 `MovaState`，多视图下仍共享，记为已知限制（第 7 节最后一行）。
4. **P2-17 覆盖不全**：总计划把 P2-17 整条归给 C06，但 C06 行只写了"主题文案手势弹幕"；子项"图标写死""进度条颜色取宿主 Theme"没人接。本子计划加 C06e（可裁剪）；"错误层 toString"归 A14b。
5. **B16 新增了写死中文**：`common.dart:143-156` 按图标反查 12 个中文动作名、`center_play.dart:75,80`、`mini_skin.dart:99,104`，总计划没有计入；另外 `MovaStrs.auto` 在 UI 里零引用。归入 C06c。
6. **C03 × C06 的隐藏耦合**：C03 若只比较引擎节，在 C06 之前经 `MovaView.options` 改主题、文案会直接失效（组件仍读旧引擎的 options），而 `view_test.dart:101-110` 恰好用 theme 变化断言重建。要求 C03 对样式节保守、C06d 放宽——这也是 C04/C06 能干净移出的前提。
7. **提交数与测试增量**：C04 由 1 个提交拆成 4 个、C06 拆成 5 个（含可裁剪的 C06e），阶梯总数 66 → 73。测试 C04 +32（估 +25）、C06 +23（估 +15，不做 C06e 为 +20）。
8. **顺序建议（推荐默认：调整）**：总计划是 C04 → C05 → C06；建议改成 C04 → C06 → C05。依赖不变（C05 依赖 C04、B04），好处是 C05 新增的全屏提示文案和样式直接走 `MovaPlayerStyle`/`MovaStrs`，不用在 C06b 里二次迁移。
9. **回退范围**：总计划 6.2 说 C04/C06 失败时回退"这两个及其依赖（C05、C08）"，但 C09 依赖 C08，回退 C08 会连带 C09。本子计划改为保留 C08/C09，只删 C08 里的几处 `show` 导出（9.2 第 1 步）。
10. **真机成本**：总计划 4.0 的 15 个新验证页只到 CP2，CP3 的 C04/C05/C06 需要再建一个验证页（约 0.5–1 人天），7.3 未计。
11. **测试改写预估**：总计划 §5.1 预计"C04/C06：UI 测试改走新接口的一部分"；本设计（非桥接 api 走回落口）让现有断言零改写，只剩 `view_test.dart:105` 一处，且取决于 C03。
12. **行号漂移**：总计划 §2.4 的 `api.dart:302-345` 只覆盖四个动词，`uiStates/uiState` 在 `:43-57`；评审的 `engine.dart:2650-2700`、`cutover_engine.dart:368-378` 在 HEAD `7275bd5c` 已漂到 `2784-2835`、`422-440`。
13. **小的待确认项（推荐默认）**：
    - `MovaChrome` 的动词叫 `show/hide/toggle/touch`，`showHud/setDragging/uiState/uiStates` 与旧名一致（推荐；备选是沿用 `showControls/hideControls`）。
    - 查找链不插 `Localizations` 一步（推荐，严格按总计划顺序；以后插一行即可）。
    - `MovaQuality` 的中文标签本版本保留原值（推荐；见 D11）。
    - C06e 纳入本分支（推荐纳入，标可裁剪）。

---

## 11. 交给 C17 的文档清单

- README：控制条交互一节改为 `MovaChrome`（`MovaPlayer(chrome:)`、`MovaChrome.of(context)`），旧 `api.showControls()` 对照表；主题与文案一节改为 `MovaPlayerStyle`（`ThemeExtension` 示例、`MovaPlayer(style:)`、`MovaView(style:)`）；`MovaOpts(controls: MovaCtrlsConfig(shortcuts: true))`（README:695）改为样式写法；手势配置示例（README:138）同理；写明多视图下锁定/缩放仍共享。
- SPEC：新增「每视图交互态（MovaChrome）」与「播放器样式（MovaPlayerStyle）」两节，含桥接语义、查找顺序、第 7 节行为表的精简版。
- CHANGELOG：把 C04c、C06b 的 Deprecated（公告）合并进 Breaking/Deprecated 汇总小节。
- CLAUDE.md：「当前状态」加两节的一句话说明与测试基线（按 3.1 规则已逐块回写，C17 只复核）。


### C06 第一批落地（2026-11-04）

C06a/b/c 已按会话要求合为一次提交；UI 实际迁移 59 处，core 保留三处旧路径。新增 19 项，回退 19 红、恢复 19 绿；analyze 0 issues。一次全量 2331 通过 + b09 目录缺失 7 项失败，补目录后仅该文件 7/7 通过，合计覆盖 2338 项。基线计数差额、API 与偏差见总计划文末 C06 落地记录；既有断言零改写。清晰度 core 常量留第二批，不修改 CLAUDE.md。
