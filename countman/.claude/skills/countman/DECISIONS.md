# Countman 设计决策记录

> 这是按时间累积的决策日志。**历史条目保留原貌**：被后来版本推翻的决策不删除，而是就地标注
> “已被 0.3.0 推翻”（或“已演进”）并写出新决策与理由；0.2.5 / 0.3.0 的新决策集中在文末两节。
> 早期条目里的旧命名已按当前公开名称修正：`Countup` / `CountupPlugin` → `Counter`，
> `CountupHandle` → `CounterHandle`，`countup()` → `counter()`，`CountupText` → `TextCounter`，
> `CountupBuilder` → `CounterBuilder`，`AnimatedCountup` → `AnimatedCounter`，
> `CountupOdometer` → `OdometerCounter`，`CountdownPlugin` → `Countdown`，
> `CountdownWidget` → `TextCountdown` / `CountdownBuilder` 等倒计时组件。

## Phase 1 — 核心引擎

### Ticker：纯单例
- `Countman` 静态类，不支持多实例
- Flutter 只有一个 vsync，多实例无收益
- 驱动：`SchedulerBinding.scheduleFrameCallback`（等价 rAF）
- 0.3.0 仍然成立；只是“每帧都 tick”变成了“按唤醒时间调度”，见文末 0.3.0 一节

### 分组：插件多实例
- 每个 `CountmanPlugin` 实例 = 一个独立任务队列 = 一个"分组"
- 取代 `@codejoo/counter` 的 label 字符串分组，心智更简单
- 所有实例挂在同一个 ticker 上，开销不变
- 注册表的身份：早期按插件 `name` 去重（同名静默忽略）。
  > **已被 0.3.0 推翻**：改为按实例注册，同名的另一个实例在 debug 下 `assert`（release 照常注册）。
  > 理由：同名静默忽略会让后建的实例从未 `onAttach`，首次 `add()` 才抛 `LateInitializationError`，
  > 且常出在“页面重建又建了一个同名分组”的场景，错误离原因很远。按实例判断能让“同一实例重复注册”
  > 无害，“同名不同实例”在开发期立刻暴露。

### CountmanContext：单例注入
- `Countman._ctx` 是 `static final`，进程生命周期只创建一次
- `use(plugin)` 时通过 `plugin.onAttach(ctx)` 注入，不在每次调用时 new
- 好处：插件不依赖 `Countman` 类，依赖方向单向（Countman → Plugin）

### 空闲自停
- `tick()` 返回 `false` = 本插件无活跃任务
- 所有插件均返回 `false` → ticker 自动停止，无任务时零开销
- 插件 `add()` 任务时调 `ctx.requestFrame()` 唤醒 ticker
> **已被 0.3.0 推翻（返回值部分）**：`tick()` 返回 `int`——距下次处理的微秒数
> （`CountmanPlugin.idle = -1` / `nextFrame = 0` / 正数）。“全部 idle 则停表、`add()` 时
> `requestFrame()` 唤醒”的思路保留。理由见 0.3.0 一节“休眠调度”。

### Lazy 任务（方案 A）
- 非活跃任务（待进入视口）：`tick()` 跳过，不计 busy
- ticker 可停止；任务激活时再调 `requestFrame()` 重启

---

## Phase 2 — Counter 引擎

### 数值类型：`double`
- 插值天然是浮点，引擎内部统一 `double`
- 显示层由用户或 formatter 决定是否取整

### Easing：使用 Flutter `Curve`
- 与 Flutter 生态统一，`Curves.easeOut` 等开箱即用
- 签名一致：`transform(t: double) → double`，无需自定义 easing 函数

### Retarget：`CounterHandle` 对象
- `plugin.add()` 返回 `CounterHandle`，封装 id + plugin 引用
- `handle.update(to: newTo)` 从当前值续接，不跳变
- `handle.cancel()` 移除任务

### 回调：`onUpdate` 为主，Widget 层用 `ValueNotifier`
- 引擎层：`onUpdate(double value)` 回调，零分配，无 Stream 开销
- Widget 层：`ValueNotifier<double>` + `ValueListenableBuilder`，符合 Flutter 习惯

### API 入口：顶层函数自举 + plugin.add 两层
- `counter(opts)` — 默认插件自动注册，99% 场景
- `plugin.add(opts)` — 自定义分组；首次 `add()` 时插件会自注册，也可显式 `Countman.use(plugin)`

### 计时方式：dt 累积
- 不用 `elapsed` 绝对时间（Flutter 测试里第一帧 elapsed 经 epoch 调整为 0）
- 用 `dt` 增量累积（frame 1 dt=0 锚定，frame 2+ 累积），测试和生产行为一致
- 只适用于逐帧动画的 `Counter`。会休眠的时钟引擎不能累加 `dt`（休眠后首帧 `dt` 为 0），
  改为每帧读时钟，见 0.3.0 一节。

---

## Phase 2 — TextCounter / CounterBuilder Widget

### `CounterBuilder`
- `StatefulWidget`，内部持有 `ValueNotifier<double>`
- `onUpdate` 更新 notifier，`ValueListenableBuilder` 驱动重建
- `didUpdateWidget` 检测 `to` 变化时调 `handle.update()` retarget

### `TextCounter`
- `StatelessWidget` 包装 `CounterBuilder`
- 保留：`prefix`/`suffix`（String）、`prefixWidget`/`suffixWidget`（Widget）
- 去掉：`prefixBuilder`/`suffixBuilder`（感知数值的前后缀直接用 `CounterBuilder`）
- `prefix` 和 `prefixWidget` 同时传时 Widget 优先

### `plugin` 参数：暂不暴露
- 当时 Widget 统一走 `counter()` 默认实例
- 分组需求出现时再添加（加参数比去参数容易）
> **已演进**：现在所有 Builder / 展示组件都有 `plugin` 参数，解析顺序为
> 显式 `plugin` > 最近 Provider 的 `plugin` > 默认组（见 0.3.0 一节“配置解析”）。

---

## OdometerCounter — odometer vs flip_counter_plus

### 选择 odometer 作为依赖
- `odometer` 的核心是 `OdometerNumber` + `Odometer` widget（per-digit Stack）
- `flip_counter_plus` 功能更丰富（小数、50 个参数、7 种过渡）但不可作为依赖（无共享 ticker，单文件 2455 行）
- 参考 flip_counter_plus 的思路按需实现特性
> **已被后续版本取代**：`OdometerCounter` 不再依赖 `odometer` 包，它是 `AnimatedCounter`
> painter 路径的薄封装（固定宽度前导零）。依赖越少、与 `AnimatedCounter` 共用同一套滚动内核越好维护。

### OdometerNumber 构造方式：Option A（float 直接构造）
- 放弃 `OdometerNumber.lerp`，改用 `_fromFloat(v)` 直接从 float 值构造
- 个位携带小数进度（平滑滑动），高位在整数进位时跳变
- 彻底解决递减时补零问题
- 回退点：commit `462fd0f`（lerp 方案）
- “个位携带小数进度、高位整数进位时跳变”的语义保留在 `DigitRollEngine` 的普通（累计）模式里。

### prefix/suffix 与 TextCounter 保持一致
- prefix/suffix (String) + prefixWidget/suffixWidget (Widget)，Widget 优先
- 有前后缀时套 Row，否则直接返回 digits widget

### RepaintBoundary 可选参数
- `CounterBuilder` 和 `AnimatedCounter` 均增加 `repaintBoundary: bool = true`
- 默认启用；大量实例（如 demo 宫格）应设为 false 避免 GPU 合成层爆炸
- README 需说明：>10 个并发建议 `repaintBoundary: false`

### 性能瓶颈实测（0→999,999,999，94 并发）
- build=75-85ms（主因）：94 个 ValueListenableBuilder × 9 DigitColumn = 846 widget 重建/帧
- raster=8-11ms（正常）：RepaintBoundary 生效
- 启动 spike=400-800ms：94 个 widget 同时 didUpdateWidget

### StartScheduler — 启动分批
- `lib/src/core/start_scheduler.dart`，Counter 和 Countdown 共用
- `batch: int`（默认 0 = 不分批）加在 AnimatedCounter 构造器上
- `batch: 5` 表示每帧最多启动 5 个 widget，约 5×3ms = 15ms，不超帧预算
- 只对「动画首次启动」分批；resume/reverse/restart 是用户主动操作，立即执行
- 副作用：视觉上 widget 以 batch 大小依次出现，非完全同帧（可接受）
> **已演进**：批大小改为全局 `StartScheduler.instance.defaultBatchSize` 与按分组覆盖的
> `groupBatchSize`，不再是构造器参数。

### 路径 B（CustomPainter）决策
- `AnimatedCounter` 改为 CustomPainter 渲染，消除 build 开销（~80ms → ~2ms）
- **混合方案**：默认走 CustomPainter；用户传 `digitBuilder`/`digitTransitionBuilder` 时 fallback 到 Widget 路径
- 用户选择 builder 时知晓性能代价，不是意外降级
- 路径 A（每位独立 ValueNotifier）被 B 完全覆盖，不需要实施
- 预估工期：最小可用版（roll/fade/scale + 混合）4-5 天
- 0.3.0 仍然成立：`AnimatedCounterBuilder` 走组件树路径，`AnimatedCounter` 走 painter 路径，
  两条路径共用 `DigitRollEngine` 与 `resolveDigitMotion`。

### 小数支持（已实现）
- 参考 flip_counter_plus：`v * 10^fractionDigits` 转整数后构造数位
- 小数点作为分隔符插在相应位之前；现由 `CounterFormat.fractionDigits` / `decimalSeparator` 配置

---

## Phase 3 — Countdown

### 命名约定
- 引擎类：`Counter`（原 `CountupPlugin`）、`Countdown`（原 `CountdownPlugin`）
- Widget：倒计时侧为 `TextCountdown`、`CountdownBuilder` 等（原 `CountdownWidget`）；
  计数侧为 `TextCounter`、`CounterBuilder`、`AnimatedCounter`

### 时间模型：Deadline（真实时钟）
- 每个任务存储 `endTime = DateTime.now().add(duration)`
- `remaining = endTime.difference(DateTime.now())`（clamp ≥ 0）
- 好处：app 切后台、ticker 挂起、恢复时自动修正，无累积漂移
- 与 counter 的 dt 累积模式形成对比：倒计时语义绑定真实时间，counter 绑定动画进度
> **已被 0.3.0 推翻**：时间模型按语义分两种。**相对时长**（`duration`、组件 `to: Duration`）
> 与正计时锚定**单调钟**，系统时间改动不影响；**绝对截止**（`deadline`、组件 `to` 为
> `DateTime` / `int` / `String`）锚定**墙钟**。暂停恢复、`reset()` 之后一律改按单调钟继续。
> 理由：全按墙钟时，用户把手机时间拨快 / 拨慢 / 自动校时会让“再来 5 分钟”的验证码、
> 答题倒计时凭空跳变，这类场景需要的是“经过了多久”；而“20:00 开售”这类与真实时刻绑定的
> 场景才需要墙钟。两者都靠 `CountmanClock` 的双时间轴实现，SystemClock 还补上设备深睡期间
> 单调钟停走的时长（见文末 0.3.0 一节）。

### 节流：默认每秒通知一次
- tick() 每帧运行（维持 ticker 活跃）
- 默认：`remaining.inSeconds < lastNotifiedSeconds` 才调 `onUpdate`
- `showMilliseconds: true`：每帧调 `onUpdate`，用于毫秒级精度展示
- `lastNotifiedSeconds` 初始为 `total.inSeconds + 1`，保证第 1 帧必通知
- 值修正：回调时传入实时计算的 `remaining`（非近似值），widget 层用 formatter 决定精度
> **已被 0.3.0 推翻**：`tick()` 不再“每帧运行以维持 ticker 活跃”。每个任务按自己的值跨过
> `interval` 整数倍（显示桶）才更新，`tick` 返回最早的唤醒微秒数，调度器两次更新之间挂一个
> 全局 `Timer` 休眠。`showMilliseconds` 早已由 `interval: 0` / `precise: true` 取代。
> 理由：一秒一次的显示却每个 vsync（60/120 Hz）都出帧，纯属浪费；50 个文本倒计时的
> 实测里 CPU 主要耗在这些空转帧上（README 的对比数据即在旧调度器下测得）。

### 暂停/恢复
- pause：`pausedRemaining = remaining`（快照）
- resume：`endTime = DateTime.now().add(pausedRemaining!)`（重设 deadline）
- 暂停期间 tick() 跳过该任务，ticker 若全部暂停则自停
- resume 后调 `ctx.requestFrame()` 重启 ticker
- 0.3.0：快照与跳过暂停任务的做法不变；resume 时改为在**单调钟**上重新锚定
  （`endMicros = 单调钟当前 + pausedRemaining`），`absolute` 置为 false。

### 分组：同 counter，plugin 多实例
- `Countdown(name: 'auction')` 创建独立队列
- 传入 `TextCountdown(plugin: myGroup, ...)` / `CountdownBuilder(plugin: myGroup, ...)` 指定分组
- 不接入 `StartScheduler`（`add()` 开销极低，无需批量延迟启动）

### CountdownController
- 用户侧创建，传入 widget，widget 在 initState 注入内部 handle
- API：`pause()` / `resume()` / `reset({Duration?})` / `cancel()`
- Getter：`remaining` / `isPaused` / `isDone`
- 纯命令式，不继承 ChangeNotifier（展示更新由 widget 内部 ValueNotifier 驱动）
> **已被 0.3.0 推翻（“纯命令式”部分）**：三个 controller（`CounterValueController` /
> `CountdownController` / `ElapsedController`，以及 `AnimatedCounterController`）统一混入
> `CountmanRunStateNotifier`，暴露 `runState`（`CountmanRunState`：idle / running / paused /
> completed）与 `runStateListenable`，另有 `restart()` 与 `dispose()`；业务侧用
> `ValueListenableBuilder` 监听即可。理由：业务上“播放/暂停按钮跟随真实状态”“完成后显示
> 重试”几乎是必需，每个业务自己包一层状态既重复又容易和真实任务状态不同步；放进控制器
> 能由组件在状态机里统一维护。构建期写入的状态推迟到帧末通知，避免监听者构建期 `setState`。

### CountdownFormat 内置格式化
- `hms` / `ms` / `msTenths` / `auto`（`DurationFormatter = String Function(Duration)`）
- 格式化在 widget 层；引擎层只传 Duration，不做字符串处理
> **已演进**：`DurationFormatter = String Function(TimeParts)`（引擎每任务复用一个预拆分的
> `TimeParts`，格式化函数直接读 `days/hours/minutes/…`，免去 `%` 运算与分配）；内置格式化器
> 扩充为 `hms` / `ms` / `msTenths` / `msMillis` / `dhms` / `dhm` / `auto`，0.3.0 新增
> `CountdownFormat.template(pattern)`。引擎层依旧不做字符串处理。

---

## 0.2.5 — 稳定性与 SDK 下限

### SDK 下限：Flutter 3.35 / Dart 3.9
- 包本来就需要它：`@internal` 从 `package:flutter/foundation.dart` 导入，Flutter 3.35 才导出。
- 把 `pubspec.yaml` 的下限写成事实，而不是继续声明一个实际跑不通的更低版本。
- 验证方式：用最低版本 SDK 在 `git archive` 副本上跑，不在开发副本上跑。

### 控制器绑定“认主”
- 组件 `controller.attach(handle, relaunch: …)`，销毁时 `controller.detach(handle)`（不用无参 `detach()`）；
  `AnimatedCounterController` 用 `$owner` 做同样的归属检查。
- 理由：组件被重新 key、或控制器同一帧从旧组件转交新组件时，旧组件的 dispose 会误拆新绑定。
  只换 `controller` 属于重新绑定，不重启任务。

### 任务回调逐任务隔离
- `TaskQueuePlugin.tick` 对每个任务单独 try/catch/finally，异常经 `FlutterError.reportError` 上报，
  终态任务一定被清理。
- 理由：一个业务回调抛异常不应饿死同组其它任务，更不能让共享 ticker 停摆。

### 完成与阈值每帧检查
- 完成与阈值不再受 `interval` 节流，只有普通显示更新按间隔。`onComplete` 恰在截止帧触发，
  `Duration.zero` / 已过期截止在首帧完成；每个时钟组每帧只读一次时钟。
- 理由：原先最多晚一个 interval 才完成，对“整点开抢”类场景不可接受。0.3.0 的休眠调度在此之上
  保持“完成时刻必有唤醒”（`completionWake`）。

### `BarStyle.width` / `height` 取字面值
- 垂直条未显式给尺寸时默认 8×200（原来是 200×8）。

---

## 0.3.0 — 休眠调度、时钟抽象、统一配置

### 休眠调度（推翻“tick 每帧运行，维持 ticker 活跃”）
- **旧决策**：Phase 3 “tick() 每帧运行（维持 ticker 活跃）”。
- **新决策**：`CountmanPlugin.tick` 返回 `int` 微秒数（`idle` / `nextFrame` / 正数）。`Countman` 汇总各插件
  返回值：有人要下一帧、或最小值不超过 20 ms 就继续排帧；最小值更大就挂**一个**全局 `Timer`，到点
  只请求一帧，仍由 vsync 帧执行处理；全部 idle 则停表。休眠后的首帧 `dt` 为 0。
- **插件契约随之变化**：`onDetach()` 成为必须实现（`unuse` / `destroy` 时调用，之后可重新挂载）；
  `TaskQueuePlugin.beginFrame` / `step` 改为 `void`，任务的唤醒时间由 `nextWake(task)` 给出。
- **理由**：秒级显示不需要 60/120 Hz 的帧；休眠把“一秒一次更新”的帧数从每秒 60 降到约 1。
  20 ms 窗口避免短定时器抖动。取舍：休眠插件不能累加 `dt`，必须读时钟——这正是下一条的动机。

### 时钟任务：按各自值的桶边界更新
- **旧决策**：插件级 `_accumMs` 累积到 `interval` 才处理（所有任务同相位）。
- **新决策**：显示桶 = `显示值微秒 ~/ interval 微秒`，每个任务**跨过自己的整数倍边界**那一帧更新，
  与加入时刻无关；`nextWake` = `boundaryWake` / `completionWake` / `thresholdWake` 的最小值；
  `ClockPlugin` 钩子全部改为整数微秒（`valueMicrosOf` 取代 `valueOf`，`thresholdWake` 取代
  `thresholdCrossed`）。
- **理由**：同相位累积会让后加入的任务显示晚到最多一个 interval，且无法给出准确的睡眠时长；
  逐任务桶边界既准确又能休眠。整数微秒避免热路径里 `Duration` 分配与浮点累计误差。

### 时钟抽象 `CountmanClock`（推翻“倒计时时间模型：墙钟 deadline”）
- **旧决策**：所有倒计时锚定墙钟 `DateTime.now()`。
- **新决策**：相对时长与正计时走单调钟，绝对截止（`deadline`、`to` 为 `DateTime`/`int`/`String`）与
  `ElapsedOptions.since` 走墙钟；暂停恢复 / `reset()` 之后转为相对（单调钟）。`CountdownOptions` 的
  `duration` 与 `deadline` 二选一。
- **时钟实现**：`SystemClock`（默认；懒注册 `AppLifecycleListener`，回到前台时把单调钟在深睡期间停走的
  时长补回——Dart VM 在 Android 上用 `CLOCK_MONOTONIC`，深睡时不走）、`OffsetClock`（服务器校时，只偏移
  墙钟）、`ManualCountmanClock`（测试，`advance` / `jumpWall` / `suspend`）；`CountmanClock.system`
  可整体替换，`Countdown` / `Elapsed` 可注入 `clock`。
- **理由**：见 Phase 3“时间模型”条目的批注。同时让测试不再依赖全局函数 `countdownClock` 的替换。
  `countdownClock` / `elapsedClock` 保留，作为 `SystemClock` 的底层时间源。

### 插件注册表按实例（推翻“按 name 去重，同名静默忽略”）
- 见 Phase 1“分组”条目的批注。`Countman.unuse(plugin, {dispose = true})` 按实例注销；示例页退出时按实例注销。

### 样式：`CountmanTheme`（推翻“样式经 Provider 下发”）
- **旧决策**：各组件默认样式由 `CounterProvider` / `CountdownProvider` 等的 `*Style` 参数下发。
- **新决策**：`CountmanTheme`（`ThemeExtension`）承载所有展示组件的默认样式；解析顺序为
  组件 `style` > Provider `*Style`（已 `@Deprecated`）> `CountmanTheme` > 内置默认，字段级合并；
  各 `*Style` 新增静态 `lerp`；`CountmanTheme.maybeOf` / `of` 供第三方读取。
- **理由**：Flutter 里“全局默认样式”的标准位置就是 `ThemeData.extensions`，能和 `Theme` 覆盖、主题动画
  （`lerp`）、暗色模式自然配合，也不要求在树上摆 Provider。Provider 保留标量默认（`duration` / `color` …）、
  共享 `plugin` 与分组回调这些真正“分组”的职责。

### Builder 为统一入口，配置解析集中
- `CounterBuilder` / `CountdownBuilder` / `ElapsedBuilder` 统一解析插件与减弱动画（`scope_resolution.dart`），
  展示组件做成薄封装；`CardCountdown` 自己持有任务但调用同一组解析函数。倒计时家族现在读取
  `CountdownProvider.plugin`，`onAllComplete` 对卡片生效；`AnimatedCounter` 读取 `CounterProvider.plugin`。
- 插件（或 `precise`）变化时**迁移任务并保留状态**（剩余 / 已经过、圈速、暂停态、显示值），不再重启，
  旧任务静默取消。理由：重启会让倒计时凭空回到满值，这几乎从来不是调用方想要的。

### 常驻 painter + `.listenable`
- Ring / Bar 四个组件的 painter 常驻，进度经 `Listenable` 原地重绘（`CounterBuilder.listenable` /
  `CountdownBuilder.listenable`，`RingPainter` / `BarPainter` 可选 `progressListenable`）；语义只在整数
  百分比变化时更新。`CounterBuilder.builder` 因此变成可空字段（构造参数仍必填）——唯一的小破坏。
- 理由：逐 tick 重建 widget 子树只为改一个进度值，没有必要。

### AnimatedCounter 配置对象与渲染内核拆分
- 平铺参数中与 `format` / `timeline` / `style` 重复的 38 个标记 `@Deprecated`，行为与优先级不变
  （对象非空字段覆盖同名平铺参数，空字段回退）。理由：公开面过大且重复，对象化后更易主题化、
  复用与 `lerp`。
- 内部抽出纯 Dart `DigitRollEngine`（可脱离 Flutter 单测）与单一来源的 `resolveDigitMotion`
  （painter 与组件树只“应用”结果），`_base_counter.dart` 按职责拆成 part 文件。理由：两条渲染路径
  原来各写一份运动 `switch`，改一处漏一处。
- `AnimatedCounter` 新增 `plugin` / `animateOnce`，尊重 `MediaQuery.disableAnimations`；方向变色由共享
  ticker 驱动，渐变期间不重建。

### 引擎增强
- `CountdownOptions.total`（进度分母）、`CountdownRounding { floor, ceil }`（只影响显示，完成与阈值
  仍按真实剩余）；`ElapsedOptions.since` / `initial` / `limit`、圈速 `lap()` / `laps`；
  `CountdownFormat.template`（创建时解析一次）；`CounterFormat.format`（与静止显示一致的字符串）。

### animate-once 失败不再断言
- 无稳定 id 或无 Provider 时：debug 警告一次，退化为每次都动画。理由：这是“优化没生效”，不是
  “程序错误”，不该让页面崩。

### CardCountdown 每卡一个 AnimationController：评估后保留
- **评估**：用 0.3.0 调度器 + `ManualCountmanClock`，统计 3 秒（188 个 16 ms 时隙）内有排帧的时隙数：
  `TextCountdown` = 1；`CardCountdown` 默认 calendar 过渡 = 175（往返两段，450 ms × 2，每秒约 900 ms
  在动）；slide 过渡 = 88（单程 450 ms）。
- **结论**：保留。`Countdown` 插件本身每秒只贡献约 1 帧，卡片的帧几乎全来自翻牌动画本身；
  动画期间无论由哪个 ticker 驱动都必须逐帧绘制，所以把每卡的 `AnimationController` 并入共享 ticker
  省不下帧，只换来写法统一。
- **后果**：卡片开销由过渡类型与时长决定（README 的性能建议已写明：缩短 `duration` 可成比例降低）。
