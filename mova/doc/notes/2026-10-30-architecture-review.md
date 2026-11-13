# mova 全项目架构评审（2026-10-30）

> 范围：`lib/` 全部（约 3.2 万行、164 个文件）、README/CHANGELOG、Android/iOS/Windows 原生插件壳、`testing.dart`。
> 方法：按模块分 5 组只读评审（播放核心 / 编排层 / 公开 API·DX / UI 层 / 外围与平台），子代理用 opus（effort 按 CLAUDE.md 评审上限 high），主会话逐条对照代码终审。
> 口径：P0 = 会播错内容、崩溃，或默认配置下核心体验坏掉；P1 = 特定配置下的错误行为，或高频、静默的坑；P2 = 有绕法的设计缺陷、低频竞态；P3 = 打磨。
> 每条标注：**已核** = 主会话亲自读过代码确认；**轻核** = 只做了抽查；**待验证** = 静态分析定不了，需要真机或外部确认。
> 只读评审，没有改任何代码；未跑 `flutter test`。

## 0. 统计

- 5 组共报 81 条（核心 13、编排 18、UI 18、外围 18、DX 14），合并去重后剩 **65 条**：P0 2 条、P1 24 条、P2 33 条、P3 6 条。
- 终审调整了 13 条严重度（11 降、1 升、1 部分不采纳），细节见第 10 节。
- 外围组有 6 处行号超出文件实际长度，结论本身在实际位置核实成立，本文用的是实际行号。

## 1. 总体判断

单个模块的质量其实不错：决策逻辑大多抽成了纯函数（`keep_alive/plan.dart`、`recovery/fail.dart`、`live/timeshift.dart`），注释和单测都很密。问题集中在结构上，有五个根子：

1. **没有"会话"的唯一所有者。** recovery、ABR、keepAlive、ads、cutover、playlist、feed、mini 各自作为外挂对象（`MovaAds`、`MovaFeed`、`MovaPlaylist`、`MovaMini` 等）或播放器里的一组标志位存在，彼此靠共享可变字段和代际计数器协作。`Mova` 一个类 2954 行、约 75 个可变字段、6 条各自维护重置清单的重载路径。这次挖出来的功能 bug 几乎都长在功能交界处：换集播成上一集、恢复后丢清晰度、影子没人回收、广告计时无视暂停。
2. **错误没有建模。** 一条 `Stream<Object>` 错误流同时驱动 `state.error`、错误遮罩、广告判失败、cutover 放弃预热，只能靠黑名单打地鼠（已经补了 3 类良性日志）。
3. **状态和配置放错了层。** 每个视图自己的 UI 交互态（控制条显隐、HUD、拖动、锁、缩放）放在播放器里；纯 UI 配置（theme/strings/gesture/danmaku）和"每条内容一份"的数据（广告排期、播放列表条目、弹幕列表）放在播放器构造期的 `MovaOpts` 里。由此带出 `MovaView` 重建陷阱、多视图串扰、没法按集配广告。
4. **公开面过大且不一致。** barrel 有 117 条 export，300 多个 `Mova` 前缀类型；有构造陷阱；能力发现有四种方式；还有一串双重开关。
5. **默认体验有硬伤。** 控制条一隐藏，缓冲转圈和错误层跟着消失；亮度手势第一下就跳变；退出全屏后宿主的竖屏锁定没了；命令式用法下清晰度列表是空的，auto 档根本没有 ABR；桌面端没有键盘和鼠标交互。

**最大收益的方向**不是推倒重写，而是分四步走（第 8 节）：先修 P0 和两个高发根因（错误分级、统一重载），API 不变；再在内部拆 `Mova`；然后把"播放器 / 视图 / 内容"三层分开（这一步同时解掉重建陷阱、多视图串扰、按集广告、主题切换重建播放器）；最后在 1.0 前用一个 `MovaSession` 时间线统一编排。

## 2. P0

### P0-1 默认 UI 套件：控制条自动隐藏或锁定时，缓冲转圈和错误层一起消失（已核）
- 证据：`ui/components/overlays.dart:35,83`，`MovaBufferingComponent` 和 `MovaErrorComponent` 都在 `MovaSlot.center`；`ui/ui_kits/default_ui_kit.dart:110-160` 中 center 槽位在 `_BarVisibility`（按 `controlsVisible` 做 `AnimatedOpacity` + `IgnorePointer`）里面，整个操作层又在 `_HideWhen(locked)` 里面。播放层（`buildPlaybackLayer`）只有画面本身。
- 影响：所有用默认 UI 套件的人都会碰到。播放 3 秒栏自动隐藏后，网络一卡，画面冻住但没有任何加载提示；出错时错误文案和重试按钮透明度为 0、也点不到；锁定状态下同样看不见。
- 修法：加一个不受 `_BarVisibility` 和 locked 控制的状态层（例如 `MovaSlot.status`，仍受 pip/mini 控制），缓冲和错误组件移过去。成本 S。

### P0-2 广告 + 无缝切换：影子不和源绑定，换集后会播成上一集（已核）
- 根因：`MovaCutover.commit()` 没有源参数，不校验影子是谁（`core/cutover/cutover.dart:611`）；`MovaAds._beginLoad` 不放弃在途影子（`core/ad/ads.dart:452-471`）；`_playContent` 直接 `commit(waitForReady: true)`（`ads.dart:1048-1067`）。
- 触发一（只配中插、没有前贴片）：中插最后约 2s，`_warmContentBehindAd` 开始预热正片 A → 用户换集 `ads.load(B)` → `_playContent` 把 A 的影子提交上去 → A 从续播点开播，B 根本没被打开。如果是在中插倒计时（pending）期间 `load(B)`，被当成正片提交的是 A 的那条**广告影子**。
- 触发二（有后贴片）：`_warmContentBehindAd`（`ads.dart:1258-1267` 及其实现）不区分广告位类型，后贴片期间也去预热正片；后贴片结束走 `_goIdleAfterContent`（`ads.dart:1136-1143`），不回收影子。结果是一个静音、暂停的完整播放器（解码器 + 网络缓冲）一直挂到下一次 prepare 或 dispose。下一次 `load(B)` 又会命中触发一，播放列表"下一集"直接重播上一集。
- 触发三：代理的 `open()` 也不放弃在途影子（`cutover.dart:278-279`）。宿主、`MovaPlaylist.jumpTo` 或 `MovaView` 调 `open(Y)` 之后，任意一次 commit 都会用旧影子 X 覆盖 Y。
- 范围：需要 ads 和 cutover 同时开启（两者默认都关），但这正是 README 给广告推荐的组合。
- 修法：`_beginLoad` 和代理 `open()` 开头先 abandon；`commit` 加 `expect:` 参数，源不匹配就拒绝；后贴片不预热正片，`_goIdleAfterContent` 里 abandon；`_beginAd/_playAd/_resumeAfterAd` 都加 `_gen` 守卫。成本 S。

## 3. P1（24 条，按主题）

### 播放核心

**P1-1 错误模型没分级（已核）**
- `mova.dart:766-770`：内核每条非良性错误都写进 `state.error` 并发 `MovaErrorEvent`；`overlays.dart:89-104` 只要非空就弹遮罩，显示 `error.toString()`（mpv 原始英文）。
- 良性错误靠黑名单（`kernel/mpv_defaults.dart` 的 `isBenignMpvError`，已经补了 3 类）。现成的 `report/error_policy.dart` 能分致命和非致命，播放器却没用。
- recovery 关（默认）时：首帧之后一条非良性日志就会把遮罩盖在仍在播放的画面上，直到下一次 `open()` 才清掉。recovery 开时：重试期间同样写 `state.error`（README:216 说"此时不写 state.error"，与实现不符），用户点遮罩上的"重试"走 `reload()`，会打断 failover。
- 编排层也被拖累：`ads.dart:1095-1099` 收到任何 `MovaErrorEvent` 就判广告失败；`cutover.dart:539-543` 影子收到任何错误就放弃预热。
- recovery 关时 `open()` 会把异常抛出来（`mova.dart:898`），和约束"运行时可恢复错误不 throw"冲突；README 首例里 `mova.open(...)` 既不 await 也不 catch，坏地址会变成未捕获的异步异常。
- 修法：结构化 `MovaPlaybackError{kind, fatal, code, uri, raw}`，播放器复用 error_policy 判定；`state.error` 只放终结错误，非终结的走 warning 事件；编排层只认 fatal 或 `MovaPlayFailure(giveUp)`；`open()` 不再因加载失败而抛（给一个版本过渡）；错误文案进 `MovaStrs`。成本 M。

**P1-2 内部重载不记得"当前加载的是什么"（已核）**
- `_activeUri` 只由源和地址下标推出来（`mova.dart:311-315`）；`_recover`（`:1520`）和 `_reopenLiveSource`（`:2619`）都重载它，而 `switchQuality` 加载的是 `q.uri`（`:2438`）。
- 后果：开着 recovery 时手选 720p，一卡顿就重载回 master（实际变成 auto），UI 还显示 720p。直播时移中触发恢复，时移位置丢失。换档地址立即失败时，失败被延到 open 返回后才处理，此时 `_lastPosition` 已被 `_forgetMediaProgress` 清零，`_recoveryPosition=0`（`:1424`），结果是用主地址从头播。
- 6 条重载路径（open、`_recover`、`switchQuality`、`_reopenLiveSource`、`_seekTimeshift`、keepAlive reloadEdge）各有一份不同的重置清单，这是这类 bug 的温床。
- 修法：`LoadSpec{uri, kind, resumeAt}` + 唯一入口 `_reload(spec)`，恢复时重放 spec，不再重新推 uri。成本 S-M。

**P1-3 清晰度/ABR 的默认链路是断的（已核；mpv 行为待一次真机确认）**
- 只有 `MovaPlayer.initState` 调一次 `loadQualities()`（`ui/player.dart:136-138`），`MovaView` 在 open 之后另调一次（`ui/view.dart:240`），播放器自己从不调。
- 命令式写法（initState 里 `mova.open(src)`、build 里放 `MovaPlayer`）下，`open()` 要先 `await beforeOpen` 才给 `_source` 赋值（`mova.dart:1263,1289`），`loadQualities` 执行时 `_source==null`，列表为空。之后换源会清空列表（`:1307`），也不会再加载。
- 即使列表加载成功，第一项永远是 auto（`model/quality.dart:111`），`loadQualities` 把它设为当前档（`mova.dart:2403`），`downshiftQuality` 遇到 auto 直接返回（`:2517`）。所以 `MovaAbrOpts.enabled` 只有在用户手选过具体档之后才生效。
- README 说"自动档委托 libmpv 原生 ABR"，但 mpv 的 HLS 选档是启动时按 `hls-bitrate`（默认 max）**静态**选，不会自适应。也就是说 auto 档等于"最高码率、无 ABR"，弱网下最容易卡的恰恰是默认档。
- 修法：播放器在 ready 后自己探测（`MovaAbrOpts.probeVariants`，默认开）；auto 档下由 mova 的 ABR 接管（加灰度开关）。成本 S-M。

**P1-4 进度没有同步快照，流也不重放（已核）**
- `IMovaApi` 只有 `Stream<MovaProg> progress`（`core/api.dart:41`），是不重放的广播流（`mova.dart:671`）；`MovaProgSelect` 没有 initialData（`ui/scope/selector.dart:79-84`）；组件各自缓存的初值都是 0（`bottom_bar.dart` 的 `_position`、`gesture_layer.dart` 的 `_lastPosition`）。
- 后果：暂停时 mpv 不发 position。这时重新挂载的组件（锁定后解锁、全屏新路由、小窗或 PiP 返回）进度显示 0:00，双击从 0 起算。
- 修法：`IMovaApi` 加 `MovaProg get progressValue`，`progress` 改成订阅即重放。纯增量。成本 S。

### 编排层

**P1-5 广告计时完全不感知暂停和前后台（已核）**
- 广告位和倒计时都是墙钟 Timer（`ads.dart:907-918`），ads.dart 里没有任何对 `playing`/`playbackIntent` 的引用；续播的 `open` 都用默认 `autoPlay: true`（`:840`、`:1065`）。
- 后果：广告带 `duration` 时用户切后台，守卫把它暂停，Timer 照样到期，上报 `completed`（计费口径出错），然后正片在后台出声播放。中插倒计时期间用户暂停正片，到期后广告照样自动开播。
- 修法：Timer 换成跟随播放状态的可暂停时钟；续播继承 `playbackIntent`；`_commitNow` 用 `wasPlaying` 决定是否开播。成本 M。

**P1-6 一次性 `cutoverTo` 路径 open 抛异常时，广告编排对象（`MovaAds`）会卡死（已核）**
- `ads.dart:832-836` 只有 try/finally 没有 catch；`cutoverTo` 回落到 `_active.open`（`cutover.dart:854,876`），recovery 关时会抛。
- 后果：状态卡在 `_phase=ad`，没有任何 Timer，画面停在上一条广告的末帧，同时产生一个未捕获异常。`_playContent` 的 `open`（`ads.dart:1065`）同样没 catch，也不会走 `contentError`。
- 修法：所有 open 都汇到 `_onAdFailure` 或 `contentError`。成本 S。

**P1-7 README 推荐的 ads + playlist 组合是坏的（已核）**
- README:381-384 让宿主用 `MovaAds.contentEnded` 驱动 `playlist.next()`；而 `next()` → `jumpTo()` → `_api.open()`（`playlist.dart:120,144-147`），绕过了 `ads.load`。
- 后果：ads 停在 idle，中插只在 `_phase==content` 时触发（`ads.dart:1307`），idle 下的 `MovaDone` 被忽略（`:1106-1112`）。第二集起完全没有广告，`contentEnded` 也不再触发，自动连播在第二集之后就断了。
- 修法：`MovaPlaylist(api, ads:)`（或可选的 `opener`）统一走 `ads.load`。成本 S。

**P1-8 "每条内容一份"的数据放进了播放器级 `MovaOpts`，`MovaView` 还有重建陷阱（已核）**
- `MovaAds` 在构造时就从 `_api.options.ads` 快照了 breaks、onAdEvent、enabled（`ads.dart:143-147`），`load(MovaSource)` 不接受排期参数，所以没法按集配置广告，除非重建播放器。播放列表条目、弹幕列表同理。
- `MovaView.didUpdateWidget` 只要 `options != oldWidget.options` 就销毁播放器并重开（`ui/view.dart:188-193`）。配置的 `==` 对闭包、列表、策略对象都按引用比较（例如 `live_opts.dart:226-235` 的 `urlBuilder`/`windowResolver`，以及 `ads.breaks`、`danmaku.items`、`strings.adStartingIn`）。宿主在 build 里内联写 `MovaOpts(...)`，父组件每次重建都会关流、从 0 重开。切主题、切语言也会重建播放器。
- 修法：短期，`MovaView` 只比较播放器真正读取的那几节，debug 下提示"options 每帧都在变"；中期，见第 8 节第 3 阶段。成本 S/M。

**P1-9 双重开关、静默不生效（已核）**
- README:478 的示例 `MovaCutover(movaFactory: createMova)` 得到的是**关闭的直通代理**：代理读的是工厂造出的播放器的 `options.cutover`（`cutover.dart:199`）。
- `MovaAds(api, cutover: api)` 要把同一个实例传两次。
- `MovaMini.showInPage` 检查 `enabled`（`ui/mini/mini.dart:174`），`show()` 不检查（`:121`），所以 `show()` 会把 `state.mini` 置成 true，`MovaMiniHost` 却什么都不画。`playlist.enabled` 只挡 NextUp 组件。
- 修法：构造了 `MovaAds`、调了方法就视为开启，配置里的 `enabled` 只留作灰度；`MovaAds` 自己判断 `api is IMovaCutover`。这不改变"默认关闭"：不构造就什么都不会发生。成本 S。

**P1-10 `MovaFeedPlayer` 是个黑盒（已核）**
- `MovaFeed` 是私有的（`ui/feed_player.dart:175`），宿主拿不到当前播放器，push 详情页时没法暂停 feed；没接 `MovaAutoPause`。
- `activate(0)` 和 `onPageChanged: _feed.activate`（`:221,348`）都丢弃了返回的 Future，`open` 抛异常（recovery 关时）就变成未捕获错误，那一页永远停在占位图。
- 修法：暴露 `MovaFeed`；内置 autoPause；每一项单独 catch，提供 `errorBuilder`。成本 M。

### UI 层

**P1-11 "全屏"只是转屏加沉浸，退出时还会解除宿主的方向锁（已核）**
- `setFullscreen` 只写 state 和 `_applyOrient`（`mova.dart:2325-2334`）；UI 层除了按钮之外没有任何全屏处理，不改布局，不拦返回键，桌面上没有效果（README:55 自己也承认了）。
- 非全屏的 auto 方向解析成 `DeviceOrientation.values`（`platform_impl/orient_impl.dart:64-65`），`reset()` 同样设成全方向加 edgeToEdge（`:91-94`）。一个只允许竖屏的 App，进出一次全屏之后就能自由旋转了，宿主自己的系统栏模式也被覆盖。
- 修法：内置应用窗口内的全屏路由，加 PopScope（先退全屏再返回，锁定时按返回键先提示解锁）；进入全屏前记下宿主的方向和系统栏偏好，退出时还原（Flutter 读不到当前方向偏好，需要宿主声明一次）；OS 级窗口全屏走可选端口。成本 M。

**P1-12 视图自己的 UI 交互态放在了播放器上（已核）**
- `IMovaApi.showControls/hideControls/showHud/setDragging/uiStates`（`core/api.dart:302-345`）、自动隐藏计时器（`mova.dart:2650-2700`），cutover 还得一个个转发（`cutover.dart:368-378`）。
- 后果：同一个播放器同时挂在页面和全屏路由（或小窗、预览窗）上时，点一下两边的控制条一起切换，锁、缩放、fit 一起变，第二个视图挂载时又调一次 `loadQualities()`。
- 修法：见第 8 节第 3 阶段的 `MovaChrome`。成本 L（可增量进行）。

**P1-13 自动隐藏不感知用户交互（已核）**
- 计时器只在 `showControls` 时启动；`setDragging` 不碰计时器（`mova.dart:2681-2690`）。
- 后果：拖进度条超过 3 秒，整条栏连同预览缩略图在手指下淡出；连点倍速或 fit 按钮时栏照样消失。
- 修法：可见条件改为 `controlsVisible || dragging`；按钮点击时续期。成本 S。

**P1-14 media_kit `Video` 默认进后台就暂停，绕过了播放器（已核；真机影响待验证）**
- media_kit_video 2.0.1 `video_texture.dart:132-133`：`pauseUponEnteringBackgroundMode = true`、`resumeUponEnteringForegroundMode = false`；`:280-296` 进入 `paused` 状态时直接 `player.pause()`。mova 的 `Video(...)`（`ui/player.dart:302-305`）没有传这两个参数。
- 后果：只要挂着 `MovaPlayer`，就做不到后台继续出声；这次暂停绕过了 `MovaHook` 和 `playbackIntent`，播放器以为自己还在播。
- **CLAUDE.md 小窗一节把"切后台暂停、回来要手动点"归因于"GPU Surface 被回收、libmpv 自动暂停"，代码证据指向的其实是 media_kit `Video` 的这个默认行为。** 是否还叠加了 surface 回收需要真机确认。
- 修法：传 `pauseUponEnteringBackgroundMode: false`，后台策略统一交给播放器或守卫。成本 S，加一轮真机回归。

**P1-15 桌面、TV、无障碍完全缺位（已核）**
- `lib/src/ui` 下 `Shortcuts`、`Focus`、`MouseRegion`、`Semantics`、`PointerScroll` 都是零命中；`MovaIconButton` 用的是 GestureDetector，点击区约 38dp，没有标签，也不能获得焦点。
- 后果：Windows 是主平台之一，却没有空格暂停、方向键 seek、鼠标悬停唤出控制条、滚轮音量；Android TV 方向键到达不了任何控件；TalkBack 读不出按钮。
- 修法：按钮改成可聚焦，加 tooltip 和语义（属于修缺陷，默认开）；`MovaPlayer` 内置 Shortcuts/Actions（默认关、给开关）；`MouseRegion.onHover` 唤出控制条。成本 M。

**P1-16 底栏按下标取子节点，按文档 patch 底栏会错位甚至越界（已核）**
- `ui/components/bottom_bar.dart:68-80` 用 `children[0..5]` 取子节点；`ui/slots/tree.dart` 的 remove/insertAfter 会让下标整体平移。
- 后果：`MovaPatch.remove('bottomBar/durationLabel')` 之后，点播布局把"回到直播"按钮当成时长标签，直播布局 `children[5]` 抛 RangeError。`insertAfter('bottomBar/positionLabel', X)` 之后进度条消失。
- 修法：`_buildRecursive` 给每个子节点套 `KeyedSubtree(ValueKey(name))`，组合组件按名字取，认不出的子节点统一追加到末尾。成本 S。

**P1-17 弹幕：向前跳一次就生成全部弹幕（已核）**
- `ui/components/danmaku.dart:165-185`：位置前跳时，把游标到当前位置之间的弹幕全部 `_spawn`，每条一个 widget 加一个 Ticker（墙钟 Tween），整层套 `Opacity`。
- 后果：开了弹幕后，从 30:00 续播或向前拖动，一下生成几千个 widget，界面必卡；暂停和改倍速时已经飞出去的弹幕照样滚。
- 修法：前跳超过 `crossDuration` 时只移动游标、不补发；横向位置由"播放位置减弹幕时间"推导；轨道做碰撞检测并限制同屏数量；改成单个 CustomPainter。成本 M。

### 外围与平台

**P1-18 亮度既不读初值，也不还原（已核）**
- 播放器只调 `_brightness.set`（`mova.dart:2271`），从没调过 `get()`；`state.brightness` 默认 1.0（`state/state.dart:248`）。音量是有播种的（`mova.dart:832-845`）。实现用的是 `setApplicationScreenBrightness`（`platform_impl/brightness_impl.dart`），端口也没有 reset。
- 后果：系统亮度 30% 时第一次下拉，亮度从约 100% 开始往下调，表现为屏幕突然变亮；离开播放页后，整个 App 保持播放器设的亮度。
- 修法：构造时像音量一样播种；dispose 和退出全屏时还原（新增可选能力接口，实现里调 `resetApplicationScreenBrightness`）。成本 S。

**P1-19 鉴权请求头没有一等支持，旁路请求全部不带头（已核）**
- `MovaSource` 只有 uri/type/title/alternatives/mpvOptions/demuxerOptions/whepMediaTimeout，没有 headers/userAgent/起播位置。Referer/Cookie 只能手写 `mpvOptions: {'http-header-fields': …}`。
- 而这些旁路请求都不带头：清晰度探测（`mova.dart:2395` 的 `_fetcher.get`）、VTT 和雪碧图（`preview/fetcher.dart:56-60`）、抽帧器（`IMovaFramePuller.extract` 只收 uri）、feed 预取。在防盗链 CDN 下，正片能播，清晰度列表、缩略图、预取全都静默失败。
- 修法：`MovaSource(headers:, userAgent:)` 经现有 `mpvOptionsFor` 下发，fetcher 和抽帧器统一使用；`open(source, start:)` 复用现有的 seek 寄存。成本 M。

**P1-20 QoE 数据失真（已核）**
- 心跳直接读 `_tally.watchedMs`，发出前不结算（`report/collector.dart:208-215`）；`onPosition` 也不 tick（`:361-371`）。不暂停一直看时，每次心跳里的 watchedMs 和 stallMs 都停在旧值。
- `_fatalSeen` 一旦置位就要到下一个会话才重置（`collector.dart:160,599-602,670`），collector 不认 `MovaRecovered`；翻译白名单里也没有 `MovaPlayFailure`/`MovaRecovered`/`MovaFailover`（`report/translator.dart`）。开启 recovery 后，一次 404 被备选地址救回来、用户看完整片，sessionEnd 仍是 `failed`，而且没有任何重试记录。
- 修法：心跳前先 `tick(now)`；collector 订阅 `MovaRecovered` 清掉 fatal；新增 recoveryAttempt/failover 上报。成本 S。

**P1-21 预览默认的"仅 WiFi"名不副实，tree-shaking 的理由也已不成立（已核）**
- 探针默认是 `MovaAlwaysAllowNetProbe`（`mova.dart:1148`），所以不显式传 probe 时 `wifiOnly` 就等于 always。
- `wiring.dart:113-134` 不默认接 probe 和 extractor 的理由是 tree-shaking，但：`connectivity_plus` 本来就是 pubspec 硬依赖（`pubspec.yaml:20`），原生插件照样注册进每个宿主；`media_kit_video` 早已被 `core/kernel/mpv_kernel.dart` 和 `ui/player.dart:2` 静态引用；`MovaFrameExtractor` 只 import `media_kit`。
- 修法：`createMova` 默认接 `MovaConnectivityNetProbe()`。**这会推翻已定的"网络探针默认不接线"，但原决策依据已不成立。** 抽帧器是否默认接，另行权衡（每个播放器首次拖动会多起一个 mpv 实例，feed 池里要限流）；不管怎么定，过期注释都要改。成本 S。

**P1-22 半成品 STT 全量暴露在公开面（已核）**
- barrel 导出 12 个 stt 文件加 3 个 impl（`mova.dart:59-70,77,80-81`），`IMovaApi.stt` 恒存在，但 `IMovaStt.feed()` 全库零调用点（ROADMAP 也承认端到端不可用）。
- 附带缺陷：`stt/service.dart:105` 会 rethrow，`:147` 会 dispose 宿主传进来的播放器；`MovaAudioExtractor._player` 从未赋值（`mpv_audio_extractor_impl.dart:60,105`），超时或异常时局部 Player 不会释放，原生实例泄漏；模型下载复用 `MovaIoHttpFetcher`，10s 超时套在整个响应体上（`preview/fetcher.dart:64-70`），几十 MB 的模型必定超时，而且写盘不是原子的（`stt/model_provider.dart:161-163`）。
- 修法：先从主 barrel 撤下（保留 `@Deprecated` 导出一个版本）；方向见第 9 节待拍板。成本 M。

### 公开 API / DX

**P1-23 构造陷阱：`Mova()` 会静默降级（已核）**
- 裸构造（`mova.dart:645-651`）的端口是 noop，内核没有 `backendFactory`。结果不止亮度、PiP、转屏不生效，recovery 的 END_FILE 秒判、`preciseFirstFrame`、TLS 也都悄悄没了。
- README 首例（:105）和时移、拦截器示例用的都是裸构造，还要手动调 `Mova.ensureInitialized()`。
- 修法（不破坏 core 纯净）：core 加一个纯 Dart 注册表（端口工厂 + 内核构建器）；platform_impl 通过 `dartPluginClass` 的 `registerWith()` 或 `Mova.ensureInitialized()` 安装默认实现；`flutter_test` 下不注册，仍是 noop。`createMova` 退化为等价别名。签名不变，裸构造的用户会从 noop 变成真端口，这正是他们原本想要的。成本 M。

**P1-24 recovery 关闭时，坏地址长时间转圈没有事件，备选地址被静默忽略（已核）**
- README:188 自己写了"缓冲转圈转很久，什么事件都没有"；`alternatives` 在 recovery 关闭时被忽略（README:218）。
- 修法（不推翻"recovery 默认关"）："判失败"不依赖 recovery。关着时也订阅 `END_FILE(error)`，转成终结的 `state.error`（代价是每个播放器一个弱客户端，可以只在需要时懒启动）。源里带了 alternatives 但 recovery 关着时，debug 下 assert 提醒。成本 S。

## 4. P2（33 条）

| # | 问题 | 证据 | 状态 |
|---|---|---|---|
| 1 | 连点两次换档：第二次读到被清零的位置，从头播；前一次醒来释放了后一次的 ABR 屏蔽 | `mova.dart:2440,2458,2481-2483` | 已核（原 P1） |
| 2 | `open(autoPlay:false)` 加载期间调 `play()` 被吞：内核 open 在 `_player.open(play:false)` 前有多段 await，`_loadKernel` 只纠偏一个方向 | `mova.dart:1273,915-918`，`mpv_kernel.dart` 的 `open` | 已核，时间窗待验证 |
| 3 | 恢复重载期间用户 seek，被首帧落地后的续播 seek 覆盖 | `mova.dart:1027-1040,1998-2021` | 已核 |
| 4 | ABR 判据粗：seek 引起的缓冲也计数、不衰减、只降不升；宿主传的 `abr.policy` 实例会被 cutover/feed 的多个播放器共享 | `mova.dart:663-665,2934-2938` | 已核 |
| 5 | 时移模式下 `timeshiftBehind` 被新流位置重算，"回到直播"可能常亮 | `mova.dart:2203-2208,2910-2923` | 待验证（取决于服务端时间基） |
| 6 | pod 串播时，旧广告播放器的 Done/错误被记到下一条头上；一次性预热没带 `pauseWhenReady`，就绪超时用的是 8s | `ads.dart:791-836,1107-1111` | 已核；"第二条回落成 open"的根因待验证（原 P1） |
| 7 | 预热时机用的是素材剩余时长，不看广告位时长和可跳过点（30s 素材配 15s 广告位永远不预热） | `ads.dart:1260-1264` | 已核（原 P1） |
| 8 | 换指窗口内转发旧播放器的 `playing=false`；影子期间新源的 SourceChange/Ready/FirstFrame 在代理流上收不到 | `cutover.dart:675-713` | 已核 |
| 9 | 向前 seek 越过 N 个中插会全部补播（没有 snapback 策略） | `ads.dart:26-38,602-610` | 已核 |
| 10 | cutover 失败原因不可观测，只返回 bool | `cutover.dart:611,851` | 已核 |
| 11 | feed 预取只拉前 64KB（HLS 只拿到 m3u8）、不带头、force close 断开复用；池外播放器只 pause，直播照样满速拉流 | `feed_prefetcher.dart`、`feed_pool.dart` | 轻核 |
| 12 | NextUp 卡片按 `state.duration` 判断，会在广告里弹出来 | `next_up.dart:119-128` | 轻核 |
| 13 | 自动暂停守卫只豁免 pip/mini，不豁免 fullscreen（宿主自建全屏路由时会误暂停） | `ui/guard/auto_pause.dart:192,207,246,281` | 已核（原 P1） |
| 14 | patch 路径拼错时静默无效；README"在顶栏追加"示例的实际渲染位置不对；锁定按钮不在组件树里，去不掉 | `ui/slots/tree.dart:61-112`、README:711 | 已核 |
| 15 | `vSensitivity` 是死配置（全库没人读）；`allowWhenLive` 的文档与实现不符 | `gesture_opts.dart:95` | 已核 |
| 16 | 与外层 PageView/TabBarView 的手势竞技：外层拖动识别器先赢，音量/亮度或横滑 seek 失效 | `gesture_layer.dart:377-385` | 待验证 |
| 17 | 主题和文案脱离 Flutter 体系：进度条颜色取宿主 Theme、图标写死、`MovaStrs` 默认中文、core 里写死 '自动'/'未知'、错误层直接 toString | `model/quality.dart:55,102`、`overlays.dart:97` | 已核 |
| 18 | 锁定按钮在内联卡片上常驻，不跟随控制条隐藏 | `default_ui_kit.dart:233-244` | 轻核 |
| 19 | 选项弹层是 Column 不能滚动，横屏全屏时选项一多可能溢出 | `common.dart:181-206` | 代码已核，溢出阈值待验证 |
| 20 | 抽帧缩略图是原分辨率 JPEG，内存缓存按条数（40）限额，`Image.memory` 没设 cacheWidth，1080p 一张解码约 8MB | `mpv_extractor_impl.dart:101-108,177`、`cache.dart:74`、`ui/components/preview.dart:300,319` | 已核（原 P1；抽帧兜底默认不接，接了就是 P1） |
| 21 | 磁盘缓存每写一次就全目录扫描，还在 sort 比较器里同步 stat，跑在 UI isolate 上 | `disk_cache.dart:91-99,128,171-180` | 已核（原 P1） |
| 22 | 所有播放器共用 `<tmp>/mova_thumbs`，`clearOnDispose` 默认 true，cutover 换指或 feed 回收时会清掉别人的缓存 | `thumb_dir_impl.dart`、`preview/service.dart:375`、`preview_opts.dart:230` | 已核（原 P1） |
| 23 | 预览队列不丢弃过时请求，慢拖时队头阻塞，停住的那一桶要等前面的抽完 | `preview/service.dart:246-252,276-322` | 已核 |
| 24 | 宿主注入的有状态对象所有权不清：播放器 dispose 会销毁共享的 extractor/cache/probe，stallPolicy 实例被复用 | `preview/service.dart:372-377`、`report_opts.dart:85` | 轻核 |
| 25 | sessionStart 的媒体信息在内核 open 之前异步采样，拿到的是空值或上一条的值 | `mova.dart:1282-1288`、`collector.dart:250` | 时序已核，取值待验证 |
| 26 | seek 引起的缓冲被算成 rebuffer，也没有 seek 时延指标 | `collector.dart:485-531` | 轻核 |
| 27 | 测试内核完全被动，宿主要懂首帧判据和 seek 校验链才能写测试 | `testing/test_kernel.dart:137-156` | 轻核 |
| 28 | Android PiP 只有进出（没有 actions、autoEnter、sourceRectHint）；`pipChanged` 回流广播给所有播放器，feed 池里会同时变成 pip=true | `MovaPlugin.kt:121-138`、`mova.dart:823-829` | 广播部分已核 |
| 29 | 音频焦点、耳机拔出、iOS AVAudioSession 都没处理 | 原生插件 | 待验证（需先确认 media_kit 自身是否处理） |
| 30 | barrel 导出了大量内部实现（preview 的 hash/two_level_cache/disk_cache/vtt、report 的 stall/session/session_id、placement/timeshift 纯函数、format、fit_ext 等），18 个无前缀顶层函数会污染宿主命名空间 | `mova.dart:18-54,100,102` | 已核 |
| 31 | 能力发现有四种方式：恒在的子 API（preview/stt）、`is` 探测（keepAlive/mute/PiP 观察）、外部包装对象（ads/playlist/feed/mini）、实现 IMovaApi 的代理（cutover） | 多处 | 已核 |
| 32 | `createMova` 参数分层不清：传了 kernel 后 audioOnly/tlsVerify/tlsCaFile/preciseFirstFrame 被静默忽略；Android 上 `tlsVerify` 不配 `tlsCaFile` 会让所有 HTTPS 失败，却没有 assert；网络配置散在三层；fit 能在三处设 | `platform_impl/wiring.dart:161-236` | 已核 |
| 33 | 文档过期：README 首屏还写"首次发布 0.1.0"；平台表里 iOS 标 ✅（从未验证）；keepAlive"无真机数据"（Windows 已测）；`api.dart:368-371` 写"必须且只能调用一次"（dispose 已经幂等）；`stt_opts.dart:36,45` 引用了不存在的 `createMova(stt:)`；README 里夹着 120 行 libmpv 构建内容，CHANGELOG 混着测试计数 | 见左 | 已核 |

## 5. P3（6 条）

- core 只在形式上纯净：`mova.dart:11` → `kernel/mpv_kernel.dart` → `media_kit_video`（依赖 Flutter），purity_test 只查直接 import。mpv 概念也渗进了公共模型（`MovaSource.mpvOptions/demuxerOptions/whepMediaTimeout`、keepAlive 比较 file-format 字符串、首帧事件挂在"上报"接口下）。**如果要做 HarmonyOS 之类的第二内核，这条升为 P2。**（原 P2）
- 约 18 个事件只是状态字段的镜像，而且不去重（`setFit` 传同一个值也发 `MovaFitChange`，`mova.dart:2298-2299`）；`dispose` 里 `_hudTimer`/`_autoHideTimer` 放在若干 await 之后才取消（`:2865-2866`），和"同步前缀取消"的注释不一致。
- `MovaAdBreak` 按身份相等，pod 里两条参数完全相同的 const 素材会被 const 规范化成同一个实例，只播一次。（轻核）
- 位置标签每秒重建 5 次；父组件每次重建，`MovaPlayer` 都会重跑 `components()` 和 `applyPatches`，约 30 个 `MovaSelect` 重新订阅。（轻核）
- VTT 一次瞬时失败就永久标记不可用；可拖动的 DVR 直播也会触发抽帧；debug 下轮询让 TTFF 最多偏晚 100ms。（轻核）
- 改名遗留（已清理为 `MovaMiniHost(mini:)`、`MovaAdOverlayComponent.ads`）；`MovaFactory`（无参）和 `MovaViewFactory`（带 options）是两套工厂类型；抽象、实现、参数名对不齐（`IMovaFramePuller`/`MovaFrameExtractor`/`extractor:`、`MovaHook`/`interceptors:`）。

## 6. 可以收进库内部、不需要宿主指定的逻辑

| 现在宿主要做什么 | 库内怎么处理 | 代价或风险 |
|---|---|---|
| 必须选 `createMova` 而不是 `Mova()`，还要手动 `ensureInitialized` | 默认实现注册表 + `dartPluginClass`，`Mova()` 就是正确用法；内核构造时自动调幂等的 `MediaKit.ensureInitialized()` | integration_test 会拿到真实端口（这本来就是想要的） |
| 命令式用法下自己想办法让清晰度列表加载出来 | 播放器在 ready 之后自己探测（不依赖 `MovaPlayer.initState`） | 多一次 master 清单请求 |
| auto 档下 ABR 不工作，要先手选一档 | auto 档由 mova 的 ABR 接管（灰度开关） | auto 档行为会变 |
| 维护错误黑名单、在遮罩里自己过滤 | 播放器复用 `error_policy` 判 fatal | 要定一份 kind 枚举 |
| `MovaAds(api, cutover: api)`，外加两三个 enabled 开关 | 构造即启用，自动识别 `api is IMovaCutover` | 一个版本的 `@Deprecated` 过渡 |
| ads 和 playlist 组合要关 `autoPlayNext`、自己接 `contentEnded` | `MovaPlaylist(api, ads:)` 自动走 `ads.load` | 无 |
| 暂停或后台时自己处理广告计时 | 广告时钟跟随 `playing`/`playbackIntent` | 计费口径变化要写进 CHANGELOG |
| audioOnly 时要记得关预览 | audioOnly 自动关预览、STT，也不再去猜 `.vtt` | 无 |
| 想让 wifiOnly 生效，得自己传 probe | 默认接 `MovaConnectivityNetProbe` | 推翻旧决定，但原依据已不成立 |
| 自己恢复亮度、方向、系统栏 | 进入时播种和记录，dispose 或退出全屏时还原 | 宿主若有自己的亮度逻辑，给 opt-out |
| 全屏时自己重排布局、推路由、拦返回键 | 内置全屏路由 + PopScope；守卫豁免 fullscreen | 需要先把 UI 交互态做成每视图一份 |
| 后台是否暂停（实际被 media_kit 偷偷暂停了） | 关掉 `Video` 自带的后台暂停，统一交给守卫或播放器 | 需要真机回归 |
| 拖动时控制条不要消失 | 交互期间自动续期 | 无 |
| 每个工厂闭包里重复注入同一批对象，还要担心被别的播放器销毁 | 注入点改成工厂，播放器只销毁自己创建的对象；缩略图目录按播放器隔离 | 改一下契约文档 |
| 有封面时想要精确首帧，得记得开 `preciseFirstFrame` | 原生事件泵按需懒启动（挂了 poster 或开了 reporter/recovery 才启动） | 每个播放器一个弱客户端 |

## 7. 能力缺口与补强

| 优先级 | 能力 | 现状和抓手 |
|---|---|---|
| P1 | 音轨、字幕轨选择，外挂字幕（SRT/ASS/VTT） | 完全没有。内核已经在监听 `_player.stream.tracks`，`sub-add` 四种格式都在真机上验证过，libass 也特意保留了 |
| P1 | `MovaSource.headers/userAgent`、`open(start:)` | 见 P1-19 |
| P1 | 结构化错误 | 见 P1-1 |
| P1 | 截图 API | 内核已有 `screenshot()`，`IMovaApi` 没暴露 |
| P1 | 诊断快照 `stats()` 和"stats for nerds"浮层 | `MovaStatsSnapshot` 现成，补上分辨率、fps、HDR 参数、缓冲时长即可 |
| P1 | 进度条显示已缓冲量 | `MovaProg.buffer` 现成，`Slider.secondaryTrackValue` 一行 |
| P1 | 桌面快捷键、鼠标悬停唤出控制条；长按临时 2 倍速 | 见 P1-15 |
| P2 | 真 ABR（带宽估计、升档、时间窗） | 现在只有"卡 3 次降一档" |
| P2 | 预加载时间线上的下一个节点（pod 下一条、续播点、播放列表下一项） | cutover 的 prepare 已具备，缺的是编排 |
| P2 | 广告追踪事件（impression、四分位、pause/mute、pod 位置 k/n）；VAST/VMAP 适配接口（解析库需用户同意才能引入） | 无 |
| P2 | Android PiP 的 actions 和 autoEnter；音频焦点、耳机拔出 | 见 P2 第 28、29 条 |
| P2 | `stop()`（释放解码但不销毁）、循环播放、前向缓冲时长和低延迟直播的一等配置 | 无 |
| P3 | 媒体会话、通知栏控制、后台播放（audioOnly 场景刚需；`audio_service` 需用户同意） | 无 |
| — | DRM、投屏、离线下载 | 和 mova 的定位不符，建议在 README 里明说不支持 |

## 8. 重构路线（按投入产出排序）

**第 0 阶段：修 bug，不动公开 API（S/M 级，先做）**
- 两条 P0：状态层、影子和源绑定。
- 两个高发根因：错误分级（`MovaPlaybackError` + 复用 error_policy）、`LoadSpec` + 统一 `_reload()`。
- 一组 S 级修复：进度快照和重放、亮度和方向还原、心跳结算和恢复后的 QoE、`Video` 的后台暂停、自动隐藏续期、底栏按名取子节点、广告计时跟随暂停、ads 的 open 异常汇流、`MovaPlaylist(ads:)`、播放器自动探测清晰度、`MovaView` 只比较播放器节、wifiOnly 探针接线。
- 收益：P0 全清，P1 能清掉一半以上。风险：seek 和续播链要重跑 rerun 矩阵。

**第 1 阶段：在内部拆 `Mova`，公开 API 不变（M）**
- `Mova` 只保留门面、命令串行化和效果执行。子组件：`LoadController`（唯一重载入口，持有 session/attempt/currentLoad）、`SeekController`（寄存、校验、链）、`PresentationGate`（首帧和 resume 闸门）、`RecoveryController`、`QualityController`（列表、ABR、hold，hold 跟 LoadSpec 同生命周期）、`LiveController`、`KeepAliveController`（plan 纯函数原样搬过去）。
- 内核信号统一成内部 sealed `_Signal`，由门面按固定顺序分发；所有命令走一条队列（把 `_keepAliveQueue` 泛化），每条带 token，await 之后统一用 `token.isCurrent` 判断。
- 能删掉的特判：`_variantLanded`、`_holdParkForLanding` + `_parkHoldTimer`、`_abrHold` 的 10s 兜底、`_recoveryAwaitingFrame`、`_readyAnnounced`，以及散在 6 处的 `keepAlivePhase==holding` 判断。

**第 2 阶段：把"播放器 / 视图 / 内容"三层分开（增量新增 + `@Deprecated` 过渡）**
- `MovaChrome`（UI 层的 ChangeNotifier，每个视图一份）：controlsVisible/hud/dragging/previewAt/locked/zoom 加自动隐藏计时器。`IMovaApi.showControls` 等标 deprecated，保留一个版本。全屏路由以它为基础。
- `MovaPlayerStyle`（theme/strings/icons/gesture/controls/danmaku 样式）挪出 `MovaOpts`，接 `ThemeExtension` 和 `Localizations`。查找顺序：widget 参数 > ThemeExtension > `api.options.*`（deprecated）> 默认值。这是挪位置，不是改名；对 core 纯净性也是加强，core 不再承载颜色和字号。
- 每条内容一份的数据跟内容走：`ads.load(content, breaks:)`、`MovaPlaylistItem.adBreaks`、弹幕改成控制器或流；`MovaOpts` 里的对应字段只当默认值用。
- 公开面：默认实现注册表；`MovaSource.headers/start`；tracks API；barrel 分入口（`mova.dart` / `ui_kit.dart` / `ads.dart` / `feed.dart` / `mini.dart` / `extend.dart` / `testing.dart`），同一个符号先在新旧两处都导出，内部 helper 标 `@Deprecated('internal; will be hidden')`。
- 收益：重建陷阱、多视图串扰、按集广告、切主题重建播放器这几类问题从根上消失；主入口的类型数能从 300 多降到约 60。

**第 3 阶段：1.0 前做统一编排（L，真机回归最多）**
- `MovaSession` 作为唯一的编排所有者：Timeline（`Item{source, adBreaks, meta}`，节点是 pre/content/midPod/post）、Cursor + Intent（计时器跟随 intent）、Transition（cutover 降为内部机制，plan 由前后节点推导 rate/hold/mute）、Preloader（总是预热下一个节点）、FailureArbiter（传输失败归播放器 recovery，节点级失败归会话策略），事件带 nodeId 和 epoch。
- `MovaAds`/`MovaPlaylist` 变成它的薄适配器，保留一个版本；barrel 去掉内部导出；STT 迁出，`IMovaApi.stt` 改为统一的 `subtitles`（原生轨道 + 外挂文件 + cue 源，STT 产出写成 SRT 再 `sub-add` 进 libass 管线）。
- feed 仍按已定约束不进 cutover，只共享 Intent 和 FailureArbiter。
- 对标：Media3 的 `MediaItem` + `AdsConfiguration`（广告作为 Timeline 的 period）、AVQueuePlayer 的预取、IMA 的 `AdsManager` + `ContentProgressProvider`。

## 9. 待拍板

1. **"新功能默认关闭"里的三处例外**（推荐都做）：
   - 网络探针默认接线：推翻原决定，原依据已不成立；
   - "判失败"不依赖 recovery：recovery 本身仍默认关；
   - 原生事件泵按需懒启动：挂了 poster 就有精确首帧。
2. **破坏性改动的节奏**：现在还是 0.x，破坏成本最低。推荐第 0、1 阶段马上做；第 2 阶段走 deprecate；第 3 阶段作为 1.0 的门槛。
3. **STT 去向**：推荐先从主 barrel 撤下。另外发现一处冲突：相邻的 `mova_stt` 用的是 sherpa-onnx（Zipformer），而 CLAUDE.md 写的是"倾向 whisper.cpp"，需要定以哪个为准。
4. **版本号对账**：`pubspec.yaml` 是 0.4.0，CHANGELOG 有 0.3.1/0.3.2/0.4.0 三节，CLAUDE.md 写的是"已发布 0.3.0"。本机访问 pub.dev 不通，没能核实。这会影响 Unreleased 那批改名能不能顺带把第 5 节的改名遗留一起收掉。
5. **CLAUDE.md 有一处归因可能不对**：小窗一节把"切后台暂停"归因于 Surface 回收，代码证据指向 media_kit `Video` 的默认后台暂停（P1-14）。建议真机确认后再改文档。

## 10. 终审记录

- **调整严重度（13 条）**：
  - 降级 11 条：核心 B2 P1→P2；核心 B10 P2→P3（不做第二内核的前提下）；核心 B12 P2→P3；编排 B6、B7 P1→P2；UI B2 P0→P1（崩溃发生在开发期定制时，开发者第一次运行就能看到）；UI B8 P1→P2（只影响自建全屏路由的宿主）；外围 B1、B2、B3 P1→P2（抽帧兜底默认不接，或者后果只是缓存效率）；DX B1、B2 P0→P1（静默失效或特定写法才触发，不是播错内容）。
  - 升级 1 条：UI B12 弹幕 P2→P1（功能开着时，向前拖动这个常规操作必卡）。
- **不采纳**：核心 B12 里"`playOrPause` 在 fallback 或重载期间等于 no-op"——fallback 时卡片本来就不可见，重载期间 `play()` 是无害的。
- **合并去重**：错误模型（核心 B4 + DX B4 + 编排 B15 + 外围部分）、进度重放（核心 B5 + UI B3）、重建陷阱（DX B2/B3 + 编排 B10 + UI B6）、请求头（DX B6 + 外围 B6 + 核心 D + 编排 B16 部分）、影子绑定（编排 B1/B2/B3）、默认探针（外围 B7 + DX B7）、UI 交互态（UI B7 + DX B14）。
- **待验证**：mpv auto 档是否真的静态选最高码率（P1-3）、时移时间基（P2 第 5 条）、`play()` 被吞的时间窗（P2 第 2 条）、pod 第二条回落成 open 的根因（P2 第 6 条）、`Video` 后台暂停的真机影响（P1-14）、手势竞技（P2 第 16 条）、弹层溢出阈值（P2 第 19 条）、sessionStart 实际取值（P2 第 25 条）、音频焦点（P2 第 29 条）、pub.dev 已发布版本。
- **行号纠错**：外围组引用的 `mpv_extractor_impl.dart:301-308/413-417`、`disk_cache.dart:366/437-448`、`cache.dart:147`、`mpv_audio_extractor_impl.dart:245-285`、`stt/service.dart:252-259/301` 都超出了文件实际行数。对应结论已在实际位置（见正文）核实成立。
- **轻核项**：P2 第 11、12、18、24、26、27 条和 P3 里标"轻核"的几条只做了抽查；其余 P0、P1 和大部分 P2 都逐条对过代码。
