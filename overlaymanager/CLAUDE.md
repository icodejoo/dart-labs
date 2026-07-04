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

## 验收基线(2026-07-04)

- 单测 `flutter test`:**70 全绿**;`flutter analyze` 干净;`flutter pub publish --dry-run` 0 warnings。
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
- 真机 `example/` + `flutter test integration_test -d windows`:**16 全绿**(弹窗内按钮驱动的
  replace/affix/overlap 多弹窗互斥·叠加、蒙层关闭、pause 冻结、程序渐进入队、两组 2×2 clearWhere、
  conditions 走**真实 /promo 页面导航**、cooldown、resolve、beforeClose 每次开卡重置锁、update、
  **应用内重启**(新 manager,session 计数复活)、GetX/bot_toast 混排)。
- demo:`cd example && flutter run -d windows`(~24 按钮 + 路由/活跃/队列状态行)。

## 工作约定

- 与 codejoo 仓库同套习惯:提交落当前分支不新建分支;测试全绿才算完成,展示真实执行输出。
- example 依赖 get/bot_toast 仅为演示编排;**主包保持零第三方运行时依赖**(cooldown 存储走
  抽象接口,shared_preferences 适配放 README 示例,不进依赖)。
- 环境:Flutter 3.44.4 / Dart 3.12.2,Windows desktop 可用(集成测试跑真窗口)。
