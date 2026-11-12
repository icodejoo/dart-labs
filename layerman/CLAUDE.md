# layerman — 项目记忆

## 分支

- 本项目在与目录同名的分支 `layerman` 上开发、提交、推送，新分支也从它拉；该分支不存在时先从 `main` 拉出。
- 不用一次性分支；确需临时分支，用完合回 `layerman` 后删除。
- 仓库总则见根目录 `CLAUDE.md`。

**先读 `/layerman` 技能**(`.claude/skills/layerman/SKILL.md`)再改代码——架构图、
不变量、外部后端纪律、验收流程都在那里,此处只记背景与决策史。

## 是什么

**headless** overlay **队列编排器**(dialog/modal/bottomsheet/toast 编排),TS 姊妹包为
`@codejoo/overlaymanager`(`D:/workspaces/codejoo/apps/overlay-manager`,同为 headless)。公开类叫
`Layerman`(0.2.0 前叫 `OverlayManager`,见决策史)——只管**排队/优先级/条件/冷却/两阶段关闭**这些编排逻辑,
自己不拥有任何 `Overlay`/`OverlayEntry`,不碰 widget 树。渲染完全交给调用方通过 `present:`(`Present`/
`PresentedOverlay`)接入——showDialog / GetX(dialog·snackbar) / bot_toast / 自建 `OverlayEntry`
都行,调度权归本包、渲染权归各家。`open<T>() → Future<T?>`。

## 决策史(为什么是现在这样)

- **0.1.0**:参考 pub 的 `overlay_manager`(handle 模型)+`flutter_overlay_manager`(独立于
  Navigator 的层),叠加 TS 的编排语义(串行/gap/slot/priority/replace/overlap/两阶段关闭)。
- **0.2.0 外部 presenter**:源码级调研 GetX 4.7 / bot_toast 4.1 / 编排模式后选 **Handle 模式**
  (present 返回 `{dismissed, dismiss}` 双向句柄);生态无先例。四条纪律见技能。
- **0.3.0 TS-parity**:conditions(`when`/`route`/`auth`/`setContext`/`dismissWhenUnmet`)、
  cooldown(可插拔存储+注入 now)、`affix`、`beforeClose`、`pauseAll` 全冻结、`resolve`、
  `update`、`clearWhere`。**刻意不做**:stackIndex/isTopmost(自渲染 z 序=插入序)、跨 isolate
  冷却同步(共享 storage 即可)。
- **真机抓过两个真 bug**(单测组合漏掉):replace 未排 front band(错弹了先排队的普通项)、
  replace 未跳 pending gap。教训:**行为改动要配真机集成用例**。
- **第二轮真机抓到 3 个语义 bug + 1 个 demo bug**(2026-07-04):①replace 顶掉的旧弹窗被
  `_discardActive` 丢弃、没退回队列(TS 是 `_displace` 退队;已加 `_displace`+`exemptNextCooldown`);
  ②`minGap`/桶滚动这类**时间型**冷却过期后队列项永不弹(已加 `slot.cooldownTimer` 自唤醒,
  `timeUntilEligible` 算最近到期;session/total 不会到期故不唤醒);③resolve 首弹无数据其实是
  **陈旧 `flutter run`**(引擎/单测/集成都证明首弹即注入数据);④重启按钮无反应=用 `runApp` 重建
  第二个 GetMaterialApp/BotToastInit(init-once 静默失败),改 `_AppRootState.restart()` setState
  换 manager + generation key 重挂 HomePage。

- **发布准备(0.0.1,2026-07-04)**:公开 API `show<T>()` **改名为 `open<T>()`**(`show` 已不存在;
  注意 barrel 的 `export ... show` 组合子是 Dart 关键字,勿动)。pubspec 版本从 **0.0.1** 起、补
  homepage/repository/issue_tracker/topics、LICENSE 用 MIT、CHANGELOG 收拢为单条 0.0.1。README
  重写为**中英双语 + 100% API 覆盖 + 接入 showDialog/GetX/bot_toast/fluttertoast 的 recipe**。
  `flutter pub publish --dry-run` = **0 warnings / 75KB**(勿加根级 `.pubignore`——它会覆盖根
  `.gitignore` 反而把 root `build/` 卷进去,archive 暴涨到 14MB)。
- **包名改 `layerman`**(2026-07-04):真发布时 pub.dev 拒绝 `overlaymanager`(与已有包
  `overlay_manager` 太相似)。pubspec `name`、barrel 文件 `lib/overlaymanager.dart→lib/layerman.dart`、
  `test`/`example` 里的 `package:overlaymanager/...` import、`example/pubspec.yaml` 的依赖 key 与
  `example` 自身包名(`overlaymanager_example→layerman_example`)、`main.dart` 里硬编码的 UI 文案
  (标题/toast 文本)、README 安装片段与 `storageKey` 默认值示例、SKILL.md 的发布名一并同步。**仓库文件夹
  名与 `.claude/skills/overlaymanager/` 技能目录名当时保持不变**(只是本地路径,不是 pub.dev 包标识)。
- **仓库文件夹/技能目录也改 `layerman`**(2026-07-05):补上第二步——`overlaymanager/` 文件夹 →
  `layerman/`、`.claude/skills/overlaymanager/` → `.claude/skills/layerman/`(含 SKILL.md `name`)、
  `test/overlaymanager_test.dart` → `test/layerman_test.dart`、pubspec `homepage` 的 `tree/main/overlaymanager`
  → `tree/main/layerman`、example/README 标题、本记忆头部与 `/layerman` 技能引用一并同步。**仍保留不动**:
  公开类 `OverlayManager` 与 `lib/src/overlay_manager.dart`(是描述性 API,不是 `overlaymanager` 单词包名),
  以及 README 里指向 TS 姊妹包的 `@codejoo/overlaymanager`(那是另一个包)。

- **0.1.0 深度链接/自动路由感知**(2026-07-04,brainstorm 多轮收敛):最初提议"捕获即将跳转的 path、
  拦截/阻断导航"——经讨论排除:①Flutter 无"push 前拦截"钩子,只有事后 `NavigatorObserver`;②真拦截
  (阻止跳转)必须拥有 push 调用点(改调用点=侵入性太强,被否);③"用 present: 把 Navigator.push 包起来
  排队"这个方向本身没问题、且**零新引擎代码**已经可用(README 补了这个 recipe),但**不是**本轮要交付的
  主功能。最终收敛到用户提的更简方案:**只做自动路由感知 + 免打扰区**,完全不碰导航本身——
  `OverlayNavigatorObserver`(新文件 `overlay_navigator_observer.dart`)监听 `didPush`/`didPop`/
  `didReplace`/`didRemove`,自动帮 host 调 `setContext({'route':...})`(GetX/go_router/vanilla
  Navigator 通吃,因为三者底层都是同一个 Flutter Navigator);`pauseOnRoutes` 构造参数声明"免打扰区"
  route pattern,进入自动 `pauseAll` 语义、离开自动 `resumeAll` 语义,与手动 pauseAll/resumeAll 通过
  `_manualPaused || _routeZonePaused` 的 OR 组合(互不覆盖);已显示弹窗要不要在进免打扰区时自动关—
  **刻意不做统一规则**,交给已有的 `route`/`when`+`dismissWhenUnmet`(后端无关,builder/present 一视同仁)。
  新增 `OverlayManager.currentRoute` getter 让 host 不用自己维护路由镜像(demo 借此彻底删掉了
  `routeLabel`/`setRoute()`,`PromoPage` 从 StatefulWidget 简化成 StatelessWidget——手动样板代码归零)。
  **过程中抓到一个真实的生产级 bug,不只是测试假象**:`OverlayNavigatorObserver` 一开始只调用
  `WidgetsBinding.instance.addPostFrameCallback` 就返回,单测(`flutter test`,`AutomatedTestWidgetsFlutterBinding`)
  发现回调**永不触发**——根因是若当前没有任何 widget 处于 dirty/待重绘状态,`pump()`/`pumpAndSettle()`
  不会强制产生一帧,注册的 postFrameCallback 就永久悬挂;真机集成测试(`IntegrationTestWidgetsFlutterBinding`)
  掩盖了这个问题(导航过渡动画自己会排帧)。修法:在 `addPostFrameCallback` 之后显式补一句
  `WidgetsBinding.instance.scheduleFrame()`——这不是测试变通,是真实生产环境也需要的健壮性修复
  (若导航发生时应用恰好完全静止、没有其它东西要重绘,同样的悬挂会在真机上发生)。
- **评估过 `WidgetsBindingObserver` 能否拦截导航,结论:能,但跟 `OverlayNavigatorObserver` 是两件事**
  (细节见 SKILL.md「Considered and deferred」)。`didPushRouteInformation` 能拦**系统/平台发起**的路由
  请求(真 OS 深链冷启动/热启动、Web 地址栏变化)——这是真前置否决,但 app 内代码调 `Navigator.push`/
  `Get.to`/`context.go` 完全不走这条路径。`didPopRoute` 能拦**系统触发**的返回(硬件/手势返回键)。两者
  都不能解决"拦截任意 app 内导航、不改调用点"这个组合——本轮**没做**,留给以后真要接系统级深链再捡。
- **发布前 `/code-review` 抓到 6 个真问题**(2026-07-04,scope 限定在 0.0.1→0.1.0 的新增 diff,均已修+补
  回归,细节见 SKILL.md 不变量 #12-16):①`OverlayNavigatorObserver` 原来监听的是 legacy 四件套
  (`didPush`/`didPop`/`didRemove`/`didReplace`)——`didRemove`/`didReplace` 报告的是"被改动那个位置"的
  route,不一定是真正最顶层(可能被压在别的路由下面);改用 Flutter 自己文档明确的"永远给最新顶层路由"的
  `didChangeTop`,顺带覆盖了 go_router 那类声明式 `Navigator(pages:)` 场景(legacy 四件套接不到)。
  ②`OverlayManager` 加 `isDisposed`,observer 的延迟回调前后都查——防止导航事件已排队、但 app 重启
  disposed 了 manager,回调再跑时调用一个已 dispose 的 ChangeNotifier 崩溃。③`pathOf` 现在包一层
  try/catch,抛出经 `FlutterError.reportError` 上报而不是直接从 NavigatorObserver 回调里冒出去炸导航。
  ④真机验证到:`MaterialApp.home` 的隐式路由名字是 `'/'`(Flutter 自己的 `Navigator.defaultRouteName`),
  不是 `null` 也不是 `'/home'`——demo 之前手动 `setContext({'route':'/home'})` 装上 observer 后第一帧就被
  盖成 `'/'`;修法是 demo 改用 `initialRoute`/`routes` 显式命名首页,不在引擎里"修"这个(这是正确的
  Flutter 行为,不是缺陷)。⑤发现并记录(不修,只写文档):`presentRouteDialog` 那套 recipe 给弹窗路由起的
  `RouteSettings(name:'om://$id')` 会被同一个 observer 观察到,弹窗开着的时候 `route` 会短暂变成那个合成
  名字——这是 Flutter 模型下正确行为(弹窗确实在最顶层),不做特殊过滤(会悄悄破坏想拿弹窗路由做条件的场景)。
  ⑥3 个独立 agent 收敛到同一处重复(`pauseAll`/`resumeAll`/`_updateRouteZone` 里手写的"记前值→翻转→按边沿
  调 freeze/release"逻辑),提炼成共享的 `_applyPauseTransition(before)`;`pauseOnRoutes` 与 `open()` 的
  `route` 参数类型校验也从两份手写 union 收敛成共享的 `_isRoutePattern`。

- **0.2.0 headless 化 + 改名 `Layerman`**(2026-07-20):随 let188_app 的 popup 接入需求,做了两件事。
  ①**headless 重构**:删掉自渲染的 `builder:` 路径(连同 `OverlayHandle`/`OverlayPhase`/
  `OverlayManagerScope`/`attach`/`detach`/`isAttached`/`barrierColor`/`barrierDismissible`,以及连带
  不可达的 `_displace`/`wasDisplaced`/`replaceBand`/`resolved`),`present:` 成为唯一必传渲染入口,核心
  不再 import `flutter/widgets`。`replace` 语义随之变化:被顶掉的项现在**总是关闭**(result null),不再退回
  队列重现(旧的"displace+resume"依赖自渲染 widget 才能安全重现,外部 backend 关了就没法保真重现)。
  ②**反悔上一轮"仓库文件夹/技能目录改 layerman"时的决定**,这次真的把公开类 `OverlayManager` 改名
  `Layerman`、`OverlayNavigatorObserver` 改名 `LayermanNavigatorObserver`,让主入口类名跟包名对齐
  （类似 `dio` 包的 `Dio`、`bot_toast` 包的 `BotToast`）。`OverlayPredicate`/`OverlayCooldown`/
  `OverlayCooldownStorage`/`OverlayRecord`/`PresentedOverlay` **刻意不跟着改**——这些描述的是"被管理的
  浮层"这个领域概念本身,不是包/管理器的身份,机械换成 `Layerman*` 会读不通（`PresentedOverlay` 是"被展示
  的浮层",不是"被展示的编排器"）。**测试(1246→1246行,内容全改)72 全绿、`flutter analyze` 干净、
  example 15 页 + 真机集成测试 17 全绿**(过程中顺带修了 5 个 demo 层面的真问题:重启时路由清理和 widget
  key 切换挤在同一个 setState 里竞态出 FocusManager 崩溃;`presentEntry` 用错了 `Overlay.of` 的查找方式;
  beforeClose/update 两个演示的关闭按钮绕开了 `close()` 直接 pop 路由,守卫形同虚设;两个演示误用模态
  `presentCard` 挡住了同页其它按钮;条件页拿路由条件配模态弹窗,弹窗自己的合成路由名把 `route` 上下文
  改了,当场把自己条件判掉)。
  **CHANGELOG/CLAUDE.md 教训**:全局 sed 替换 `OverlayManager`→`Layerman` 时,不能碰**历史记录**——
  CHANGELOG 的 0.0.1/0.1.0 条目、以及本文件里描述"当时决定保留 OverlayManager 不改"的那句话,都是在
  陈述"那个时间点这个类真的叫这个名字"的事实,机械替换会把历史记录改到自相矛盾(比如把"我们决定保留
  OverlayManager 这个名字"改成"我们决定保留 Layerman 这个名字"——变成废话)。只有**当前**（未发布的
  0.2.0 条目、以及这条新增的决策记录本身）该用新名字,历史条目一律保持发生时的原名。

- **0.2.2 加固 + 全量架构评审（2026-11-04）**：评审时写了 18 条探针测试，实测确认了一批缺陷
  （未修的清单见 `ARCHITECTURE.md` §14）。用户选定**路线 A：0.2.2 补丁 → 0.3.0 只新增 API →
  1.0 收口（破坏性）**。0.2.2 修了 6 项：
  ①`close(id, 类型不对的结果)` 原来抛 TypeError，且 future 永远挂起 → 现在先校验，不符抛 ArgumentError；
  ②冷却 hydrate 竞态（`ready()` 前 open 绕过上限；整表写回抹掉其它 id；hydrate 后又覆盖新计数）
  → 改为门控 + 合并 + 串行写 + 失败上报；
  ③异步 `beforeClose` 未决时重复 close 会去重；
  ④`when` 谓词抛异常会被隔离；
  ⑤`cooldown` 必须传显式 id（debug 断言）；
  ⑥dispose 后 open 在 debug 断言、release 返回 null。
  README 的路由配方原来按名字 `popUntil`/`Get.until` 关闭，目标不在栈顶时静默失效，条目永远卡在
  closing；现在改为保存 Route 对象（栈顶时 pop，被盖住时 `removeRoute`），`dismissed` 用
  `route.completed`，不再需要 exitDuration 估计值。
  版本下限：`didChangeTop` 从 Flutter **3.27.0** 才有（commit 88bee39f542），原来的
  `flutter: ">=1.17.0"` 是错的；`sdk` 从 ^3.12.2 降到 ^3.6.0（分析器已按 3.6 语言版本验证）；
  `removeRoute` 的 result 参数要 **3.32** 才有，所以配方里不传。
  ARCHITECTURE.md/.svg 原稿写的是根本不存在的 API，已照代码重写。新增 `layerman-ci.yml`：
  stable 上跑 analyze + test，3.27.4 上只跑 test，deploy 依赖它。
  **命名决定（用户指定）**：0.3.0 自带的 Route 型 presenter 叫 **`DialogManager`**（不叫
  DialogPresenter），全局建一次、持有 navigatorKey；同类的按 `XxxManager` 命名（如
  `BottomSheetManager`）。0.3.0 待办见 ARCHITECTURE §15。

## 验收基线(2026-11-04,0.2.2)

- `flutter test`：**101 条全绿**（layerman_test 81 + robustness_test 15 + readme_recipe_test 5）；
  `flutter analyze`（含 example）干净；本机 Flutter 3.47.0 / Dart 3.13.0。
- 真机集成 17 条本轮**没有重跑**：example 的 Windows runner 会弹出普通窗口抢焦点，而本轮改动
  不影响 example 的可见流程。要跑先问用户，或者先给 runner 加安静模式。

## 验收基线(2026-07-04)

- 单测 `flutter test`:**80 全绿**(0.1.0 新增 10 条:pauseOnRoutes 组合语义 3 条 + `OverlayNavigatorObserver`
  7 条,含 disposed-manager 与 throwing-pathOf 两条 code-review 回归);`flutter analyze` 干净;
  `flutter pub publish --dry-run` 0 warnings。
- 真机集成 **17 全绿**(`/zone` 自动冻结队列 1 条 + `/promo` 往返真机断言路由标签文本(而不只是
  activeIds/queuedIds)验证 `/home` 命名修复)。
- **第二轮 code-review 又抓到 3 个真 bug**(2026-07-04,均补回归):①displace 一个带 `resolve` 的已开项,
  resume 时会**重跑 resolver**(重复副作用,若第二次返回 null 会把正显示的项静默丢弃)→加 `resolved` 标记,
  `_activate` 对已 resolved 项跳过 resolver 直接复用旧 data;②对 displaced-pending 项调用 `close()` 完全
  **绕过了 `beforeClose` 守卫**(第一轮加的 `wasDisplaced` 快路径漏了守卫检查)→`_close` 重构为
  `_isDisplacedPending`+统一 `proceed()`,守卫对两条路径(open 关闭 / displaced 直接 settle+remove)都生效;
  ③连带修的竞态:async `beforeClose` 批准结果到达时只认 `phase==open`,若批准前该项被 replace 顶掉
  (变 displaced-pending)则批准被丢弃→async 分支改为在结果到达时**重新判定** open 或 displaced-pending
  两态,已批准的关闭不会因为中途被顶替而失效。
- **`/simplify` 清理一轮**(2026-07-04,4 角度 agent 并行,70 测全绿验证零行为变化):`exemptNextCooldown`
  与 `wasDisplaced` 合并为一个字段(两处 set/reset 完全同步,纯重复;顺带清掉合并时残留的重复赋值行);
  `_close` 的 `proceed()` 内联闭包提炼成 `_finishClose`+`_closable` 方法,guard==null/verdict==true 两条
  分支的重复 shape 收敛;`canShow` 改为委托 `timeUntilEligible(...) == Duration.zero`(验证等价,消 24
  行重复桶计算);新增 `_detachOverlayEntry`/`_detachFromActive`/`_isCurrent`/`_cancelCooldownTimer` 四个
  小助手,收敛 `detach`/`_remove`/`_displace`/`_discardActive` 里各自手写的 overlayEntry 拆除+active/
  overlaps 摘除+byId 身份判断+cooldownTimer 取消(原来 4 处各写一份)。**判断性跳过**(过于侵入、紧接
  两轮正确性修复不宜再动):`_discardActive` 合并进 `_remove(advance:false)`——两者已收敛到只差
  `notifyListeners()` 时机,但那个多余 notify 会在 `open()` 执行中途(旧项已删、新项未入队)同步触发监听器
  看到暂态,判定为真实行为变化而非纯清理,保留 `_discardActive` 独立;`_Slot` 的 gap/delay/cooldown 三个
  `Timer?` 统一成一个唤醒时钟、`_EntryPhase` 加 `suspended` 取代三个布尔位——结构性改动,超出本轮清理范围。
- **code-review 修了 7 个 displace/cooldown 缺陷**(2026-07-04,均补回归用例):①单发冷却(session/total)
  被 displace 的项永不再显示+future 悬挂→`exemptNextCooldown` 现同时绕过 `_cooldownPass`;②displace
  resolving 项会双跑 resolver+旧数据→resolving 改 `_discardActive`,只 displace `phase==open`;③持句柄
  close 被 displace 的项被吞+会重现→`wasDisplaced` 让 pending 的 close 生效(settle+remove);④duration
  被 displace 后重置为满时长→`_freezeDuration` 冻结剩余,`_startDuration` 用 `durationRemaining ?? duration`;
  ⑤两个 replace:true 时被顶的旧项按 seq 反超抢占者→`replaceBand`(可变,初值=replace)驱动 `_cmp`,displace
  置 false;⑥`clear()` 未取消 `cooldownTimer`→已补;⑦example 合并 listenable 内联churn/restart 重复 setRoute→已清。
- 真机 `example/` + `flutter test integration_test -d windows`:覆盖弹窗内按钮驱动的
  replace/affix/overlap 多弹窗互斥·叠加、蒙层关闭、pause 冻结、程序渐进入队、两组 2×2 clearWhere、
  conditions 走**真实 /promo 页面导航**、cooldown、resolve、beforeClose 每次开卡重置锁、update、
  **应用内重启**(新 manager,session 计数复活)、GetX/bot_toast 混排、**`/zone` 免打扰区自动冻结/恢复**。
- demo:`cd example && flutter run -d windows`(25 按钮 + 路由/活跃/队列状态行)。

## 工作约定

- 与 codejoo 仓库同套习惯:提交落当前分支不新建分支;测试全绿才算完成,展示真实执行输出。
- example 依赖 get/bot_toast 仅为演示编排;**主包保持零第三方运行时依赖**(cooldown 存储走
  抽象接口,shared_preferences 适配放 README 示例,不进依赖)。
- 环境：本机 Flutter 3.47.0 / Dart 3.13.0（2026-11-04；之前是 3.44.4 / 3.12.2），Windows desktop
  可用（集成测试跑真窗口，会抢焦点）。3.47 的 `pub get` 会自动给两份 analysis_options 加
  `analyzer.exclude`，并改写 example 的 pubspec.lock 和插件注册文件（后者只改换行符）。
  不是有意为之就别提交这些文件。


## 0.3.0 决策与验收记录（2026-11-04）

评审结论采用路线 A：0.2.2 先加固，0.3.0 增量扩展并修复行为，1.0 再收口。
本批完成永久冷却耗尽丢弃、关闭/解析超时、同 id 串行接管、实时数据、完整观测，
以及票据/首次结束原因/异步事件、holds、生命周期自动暂停、排队过期与槽位配置。
观察者默认只接受 PageRoute，可通过 routeFilter 恢复全部路由，contextKey 支持嵌套导航。
有序插入和 when 上下文视图缓存属于内部优化。发布包通过 .pubignore 排除本文件和 .claude/。

Route 型 presenter 命名遵循用户指定的 `DialogManager`（不叫 DialogPresenter）；
同类遵循 `XxxManager`，本批有 `BottomSheetManager`，全局建一次，只存配置、每次独立 Route。
`presentRoute` 留给页面/自定义 Route；builder close 可绑定 manager 经过守卫。
Flutter 3.27 兼容约束继续保留：removeRoute 不传 result。
1.0 的 Gate、显式状态机/串行派发、overlap/replace 枚举、route 类型化、phase 枚举，
等 0.3.0 在真实使用中稳定后再定，不把规划符号写成当前 API。

验收基线（2026-11-04，0.3.0）：

- 单测 `flutter test`：**199 条全绿**（本机 Flutter 3.47.0 / Dart 3.13.0）；`flutter analyze`
  （含 example）干净。**最低版本 Flutter 3.27.4（Dart 3.6）上同样 199 条全绿**，`pub get` 与 `analyze`
  也通过——3.27 的验证方式：`git clone --depth 1 --branch 3.27.4 file:///E:/sdk/flutter C:/f327/flutter`
  （Windows 未开长路径，克隆目录必须很短），把 lib/test/pubspec.yaml 复制到 `C:/f327/pkg`，
  用 `C:/f327/flutter/bin/flutter pub get --no-example` 再 `flutter test`。
- 手机真机：华为 STG-AL00 / Android 12（序列号 `7NQBB23606003715`），
  `cd example && flutter test integration_test/orchestration_test.dart -d 7NQBB23606003715`，
  **26 条全绿**（原有 17 + 0.3.0 新增 9）。example 已补 Android 平台（`flutter create --platforms=android`）。
- 手机测试的坑：①同一个 1400×900 视口在手机上排版更高，按钮会落到视口外，点之前用 `tapVisible`
  （`ensureVisible` 后再点）。②**不要用 `WidgetsBinding.handleAppLifecycleStateChanged(paused)`
  模拟后台**：paused/hidden/detached 会把全局出帧关掉，真机上 `pump()` 等不到帧会一直挂着，手机屏幕
  停在 "Test starting..."；演示页和测试都改为调用 `appLifecycle.didChangeAppLifecycleState(...)`
  （`LayermanLifecycle` 的观察者方法，走同一套 hold 逻辑但不动出帧开关）。普通 `flutter test`
  里这个坑不会暴露，只有真机才会。
- Windows 桌面集成测试会抢焦点，不无人值守跑。
- 并发派 Codex 最多 2 个：3 个并发 + Gradle 守护进程会把本机内存吃光，Codex 被 OOM 杀掉
  （`memory allocation of 536870912 bytes failed`）。Gradle/Kotlin 守护进程跑完手机测试后要结束。


## 1.0.0 决策记录（2026-11-04）

评审路线 A 的三步全部完成：0.2.2 加固、0.3.0 增量扩展、1.0 破坏性类型收口。
`open` / `submit` 以 `mode: OverlayMode.queue/replace/overlap` 取代两个布尔参数；
`route` / `pauseOnRoutes` 使用 `RouteMatcher`，`OverlayRecord.phase` 使用 `OverlayPhase`。
补齐 build 期间推迟 present 与通知、按操作批量通知、空 slot 回收、冷却查询重置与标签。

随机序列不变量测试 `test/fuzz_invariants_test.dart` 作为 1.0 前置安全网，抓到 close 后
remove / clear / dismiss 超时会重复请求后端 dismiss 的缺陷；非幂等后端可能误关其他弹窗。
`dismissRequested` 在第一次请求前置位，保证每条目最多请求一次，即使后端抛错也不重试。

Gate 与显式状态机当时未完成；旧的“风险大于收益”解释已在下方发布前复审中撤回。
未做项、功能缺口与有意决定以 ARCHITECTURE §15 及下方补完记录为准。
本节取代上文 0.3.0 记录中“1.0 方案待定”的历史规划。

验收基线（1.0.0，2026-11-04）：

- 本机 `flutter test`：**600 条全绿**（Flutter 3.47.0 / Dart 3.13.0）；最低 Flutter 3.27.4（Dart 3.6）上同样 **600 条全绿**，`analyze` 干净。
- 手机集成 `flutter test integration_test/orchestration_test.dart -d 7NQBB23606003715`：**29 条全绿**（华为 STG-AL00 / Android 12）。
- 关键 README 示例用 dart analyze 验证，SVG 用 Python XML 解析。
- 验证流程继续使用手机明确 `-d` 序列号；Windows 桌面抢焦点，不无人值守跑。
  不用 handleAppLifecycleStateChanged 模拟后台，改调用 LayermanLifecycle 的观察者方法。


## 1.0.0 发布前补完（2026-11-04）

1.0.0 尚未发布，本次更新现有版本条目，不另增版本。
复审结论：Gate / 显式状态机与操作串行派发的旧理由站不住，真实原因是工作量（引擎 2000+ 行），
属于内部重构，1.x 可随时做。批次 debug 不变量断言和随机序列测试是风险缓解，不是完成重构的替代证明。
当前 _Entry 为 9 个可变布尔 + 6 个计时器（不含配置与 getter）。

此前漏报项：业务自定义资格扩展点；slot 并发数 / 跨 slot 互斥；显式裁剪 API 与全表 JSON 写回成本；
冷却按结果计数及周 / 月可插拔规则；后端真正可见回报计数；票据可监听状态；Inspector；
OverlayRequest<T> 参数对象；同帧导航合并；layerman_getx / layerman_bot_toast 适配包。
上述均未提供，限制及替代手段逐项列于 ARCHITECTURE §14–15。

用户要求 requiresAuth 改为 auth 判断函数：各业务系统的认证判断不同，还要考虑角色 / 权限，无法枚举。
函数读取 setContext 任意键，引擎不再读取保留键 auth。when 改为与 route / auth 按 AND 组合，
避免额外业务条件悄悄绕过路由或权限限制，减少调用方重复写判断。

本批文档同步：迁移对照表、clock / FakeOverlayClock、PresentContext<T>.close、无 manager 参数的
Route presenter、overlap delay 与取消、debug 批次不变量、清理缺陷修复，以及如实的未做项说明。
B2 已核实提交及 hydrate 清理路径调用永久上限判断，不再等待被占 slot 的调度扫描。
保留主入口导出 Material presenter（SDK 内置、不增第三方依赖）；setContext({}) 保留全量重判语义。

验收基线：单测 **782 条全绿**（Flutter 3.47.0；最低 Flutter 3.27.4 上同样 782 条全绿，连续两次干净全量运行），0 个 skip；手机真机 **33 条全绿**（华为 STG-AL00 / Android 12，序列号 7NQBB23606003715）。如实记录一次偶发：3.27.4 有一次全量运行恰好与手机测试的 Gradle 构建并发，fuzz 文件最后一条（overlap 延迟取消）报 did not complete；该用例完全跑在假时间里、无真实时间依赖，单条、整文件、两次干净全量均无法复现，系统也无资源耗尽事件，根因未定。以后做最低版本验证时不要与手机构建并发。
本次只验证系统临时目录中的 README 关键示例 dart analyze 和 ARCHITECTURE.svg XML；不据历史基线宣称新测试通过。


## 1.0.0 发布前新增 suppress / blockedBy（2026-11-04）

用户评估剩余未做项后，选定完成 suppress 与 blockedBy。1.0.0 尚未发布，直接合入现有版本。
本记录更新此前“跨 slot 互斥 / 冷却按结果计数未提供”的历史结论：按结果调用 suppress 已支持
“不再提示”；频次计数仍在 present 成功返回后发生，周 / 月可插拔规则、slot 并发数仍未做。

suppress 只约束带 cooldown 的提交，让设置页主动“查看活动”等无 cooldown 打开仍可用；
因此任何 cooldown（包括 session-only、空配置）都等待 hydrate，因为抑制是持久化状态。
依赖 session-only 在 ready() 前显示的代码会晚一个存储读取的时间。hydrate 前状态查询
canShow false / wait null，但永久受阻及 suppressed 仍反映内存已知状态。
抑制与计数同记录 su，调用及 hydrate 合并只延长不缩短、永久优先，确保“关闭抑制三天，
不再提示永久抑制”不受调用顺序影响。reset 才能缩短，且会一起清除计数。已激活条目不受影响。

blockedBy 的占用是 serial active（resolving / open / closing 含 exitDuration）或 active overlap；
gap、appear delay、冷却等待、队列和等待 overlap 不算占用。阻塞只拦新激活，已展示项与 duration
继续；环不保证公平。解除统一在最外层批次末尾，防止 replace 移走旧项到激活新项的暂态让其他
slot 插队；只调度 waitingUnblock 的槽及受阻 overlap，不扩大推模式条件重判的触发范围。

验收基线（主会话实测）：单测 **841 条全绿**（Flutter 3.47.0；最低 Flutter 3.27.4 上同样 841 条全绿，
`analyze` 干净），0 个 skip；手机真机 **38 条全绿**（原有 33 + 新增 5，华为 STG-AL00 / Android 12，
序列号 7NQBB23606003715）。README 新增示例经临时工程 `dart analyze` 验证，SVG 经 XML 解析。
随机序列测试里"被阻塞后解除并出场""overlap 被阻塞持有后释放"两项实际只发生 2 次和 1 次，
这两条路径主要由 blocked_by_test 的确定性用例与不变量 (j)(k) 守住，不靠随机测试。


## 1.0.0 发布前代码评审修复（2026-11-04）

用户要求评审全部源码：Codex 两路只读初审（引擎；适配器 + example + test），主会话逐条终审并写探针
实测取证。Codex 报 9 条全部成立（两条 P0 降为 P2，三条 demo 问题降为 P3），终审另补 7 条漏报；
用户选择一次全部修完。1.0.0 尚未发布，只更新现有条目。

引擎：判断函数（when / auth / clearWhere 的 test）统一只读，期间所有修改入口（含票据、ctx.close、
hold.release、dispose）在任何状态变化前抛 StateError（“判断函数内不能修改 Layerman”）；条件异常
每条目上报一次并按不满足处理，clearWhere test 异常外传。dispose 一开始就置 `_disposing`（isDisposed
随即为 true），后端回调重入 open / submit 立即以 disposed 结束。串行 delay 绑定属主，属主离队时取消
计时器并在最外层批次末尾重调度（debug 不变量 l）。maxQueued 移到批次末尾、激活判定之后执行，build
期间推迟到帧后。resolve 写 data 后重查身份与阶段；update 两侧都是字符串键 Map 时保留
Map<String, Object?>；日历桶按 now.toLocal()；hydrate 逐条隔离损坏记录并原样写回，同 id 的有效记录
优先；present 同步结束时 ended 延到 shown 之后。适配器：Route 带内部历史（Drawer、持久底部面板）时
改用 removeRoute。close / dismiss 只作用于 open 条目（文档写明）。_Entry 仍为 9 个可变布尔 + 6 个计时器。

终审补修（Codex 修复后复核发现）：① `_flush` 原先把 `_unparsed` 展开在有效记录之后，同 id 的损坏原值
会盖住新写入的计数和永久抑制，重启后“不再提示”失效——已改为有效记录优先并补回归；② A1 的 when / auth
用例在谓词内断言，失败会被引擎当作条件异常吞掉——改为谓词外再断言没有上报；③ C2 的 replace 分支在旧代码
上也能通过——改为不合格的 replace 排队项；④ 翻译注释时丢了 OverlayCooldownStorage 的示例，已补回；
⑤ README 里堆在“编排纪律”末尾的新说明按主题挪回各章节。反向验证：新回归放到修复前的代码上跑，针对原缺陷的
26 条全部失败。

example：Pause 页改用非模态 entry；ShadSheet 复用公开的 RouteCapture，首帧前 dismiss 不留孤立 sheet；
toast 检视保存 CancelFunc；update / affix 演示改读 ctx.dataListenable；presentCard 的关闭按钮走
ctx.close（经过 beforeClose），`_removeRouteDismiss` 在栈顶且无内部历史时 pop、否则 removeRoute，
保留退场动画；清理 Get.until、String/RegExp 路由参数、按 om:// 名字关闭等过时说明；新增 B2 / B3 / B4
三条集成用例，update 用例改为断言管理器数据。B4 首轮真机失败是用例只 pump 一帧就断言，toast 退场后
还需一帧移除，已改为 pumpAndSettle（toast 静止时不排帧，空 dismiss 仍会失败）。

提交前按 git 流程跑了两轮 simplify（先本轮改动，再全部源码，都由 Codex 执行、主会话终审），采纳 8 处
纯质量清理：抽出 `_cancelDelayTimer`、`_thawDuration` 复用 `_startDuration`、删冗余的 `!overlap` 与重复注释、
example 的 `_removeRouteDismiss` 直接传 Route、删无用 Builder 与空列表三元、三个测试文件里完全相同的后端与
flush 提到 `test/support/headless_backend.dart`；用例数不变。没采纳的建议（合并 `_discardActive` 与 `_remove`、
合并 overlap 提交与释放判定、容量只扫变化的槽位等）都可能改变通知或调度时机。

验收基线（主会话实测）：`flutter analyze`（含 example）干净；`flutter test` **869 条全绿**，0 skip
（Flutter 3.47.0 / Dart 3.13.0）；手机真机 **41 条全绿**（原有 38 + 新增 3，华为 STG-AL00 /
Android 12，序列号 7NQBB23606003715）。最低 Flutter 3.27.4 本轮未运行（本地环境已删），新代码只用了
3.27 已有的 API（willHandlePopInternally、DateTime.toLocal），开 PR 时 CI 的 3.27.4 任务会覆盖。


## 合并 layerman-visible（2026-11-06）

“可见确认后才计数”已合入 layerman：冷却计数与 `shown` 事件改在后端 visible 确认后才发生，
可见前结束的条目只有 queued、ended，不计数。这取代上文“后端真正可见回报计数未提供”的历史结论。
同时去掉了 `_presenting` / `_finishPresent`（visible 之前才需要暂存 ended），`dispose` 内不再交付暂存事件。
`PresentedOverlay` 的 `visible` 为必传参数，测试里手写后端要补 `visible: Future<void>.value()`。
验收：`flutter test` 1146 条全绿、`flutter analyze` 干净（本机 Flutter 3.47.0）；
最低 Flutter 3.27.4 与手机真机本轮未重跑。
