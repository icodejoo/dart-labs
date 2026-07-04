# overlaymanager — 项目记忆

**先读 `/overlaymanager` 技能**(`.claude/skills/overlaymanager/SKILL.md`)再改代码——架构图、
不变量、外部后端纪律、验收流程都在那里,此处只记背景与决策史。

## 是什么

Flutter 原生 overlay **队列管理器**(dialog/modal/bottomsheet/toast 编排),TS 姊妹包为
`@codejoo/overlaymanager`(`D:/workspaces/codejoo/apps/overlay-manager`,headless)。本包**拥抱
Flutter**:真实 `OverlayEntry` 插入 `OverlayManagerScope` 自有 Overlay 层,`open<T>() → Future<T?>`。
另有 TS 没有的**外部 presenter**(`Present`/`PresentedOverlay`):统一编排 showDialog / GetX
(dialog·snackbar) / bot_toast——调度权归本包、渲染权归各家。

## 决策史(为什么是现在这样)

- **0.1.0**:参考 pub 的 `overlay_manager`(handle 模型)+`flutter_overlay_manager`(独立于
  Navigator 的层),叠加 TS 的编排语义(串行/gap/slot/priority/replace/overlap/两阶段关闭)。
- **0.2.0 外部 presenter**:源码级调研 GetX 4.7 / bot_toast 4.1 / 编排模式后选 **Handle 模式**
  (present 返回 `{dismissed, dismiss}` 双向句柄);生态无先例。四条纪律见技能。
- **0.3.0 TS-parity**:conditions(`when`/`route`/`requiresAuth`/`setContext`/`dismissWhenUnmet`)、
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
  名与 `.claude/skills/overlaymanager/` 技能目录名保持不变**(只是本地路径,不是 pub.dev 包标识)。

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
- 环境:Flutter 3.44.4 / Dart 3.12.2,Windows desktop 可用(集成测试跑真窗口)。
