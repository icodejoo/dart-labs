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

### CardCountdown 每卡一个 AnimationController：被 fps 的真窗口数据推翻
- **原结论的前提**：不限帧时翻牌期间需要逐 vsync 绘制；并入共享 ticker 省不下这些帧。
  原模拟 3 秒内 TextCountdown 出帧 1 次、calendar 175 次、slide 88 次，因而曾决定保留。
- **什么变了**：现在有 fps，需要让调度器在动画采样之间真正休眠；共享 ticker 已自行
  支持 TickerMode，原先依靠 Flutter Ticker 静音的理由也不再成立。
- **真窗口证据**：卡片 fps:30 前后 FPS 为 54.7→54.5，CPU 130%→118% 在噪声内；
  只节流 painter 通知仍由每卡 Ticker 在每个 vsync 请求帧。Counter / precise Countdown
  用共享 ticker 则从 60→30.1 FPS，CPU 降低 50% 以上。
- **新设计**：内部 CardProgress 实现 Animation<double>，所有卡片共用私有惰性 Counter
  任务组；每段为线性 from→to，曲线仍在常驻 painter 应用。calendar 完成前程后反程，
  各用完整 duration；slide/flip 单程，提交时机不变。任务从启动时刻锚定单调钟，避免
  休眠首帧 dt==0 丢时间；热路径复用更新 tear-off，状态回调处于逐任务边界内。
- fps 沿用实例 > 所用 Countdown 插件 > 全局；插件/实例变化同步活动 handle，
  全局仍由引擎动态读取。隐藏/恢复取消动画并直接落定；只订阅一次 HiddenTaskState。
  FlipCardPainter.controller 放宽为 Animation<double>，仍接受 AnimationController。


### 不可见休眠与 muted ≠ paused
- 默认跟随 `TickerMode` 静音，`Countman.muteWhenHidden = false` 可在挂载前关闭。
  原生 `Offstage` 不提供静音信号，调用方需配套 `TickerMode(enabled: !offstage)`。
- 静音不改变 runState/isPaused，不重新锚定，不触发 onPause/onResume；onUpdate/onTick
  不投递，阈值和完成仍按真实时刻唤醒并处于逐任务异常边界内。首帧静音仍初始化
  started 并发一次 onStart，跳过显示回调；终态可同步最终显示，不补发静音期间更新。
- **Counter 选方案 A：可见时跳到真实推进位置**。静音用系统单调钟补算 elapsed，
  只为终点安排休眠；用户暂停时间排除在外。理由：路由返回时展示与当前时间一致，
  避免用户等待不可见期间早应结束的装饰动画，不从暂停处续播。
- ClockPlugin 取消静音使 lastBucket 失效并 requestFrame，保留休眠后 dt == 0；
  插件迁移与新建任务保留静音。CardCountdown 使用共享 Counter 进度任务，
  隐藏与恢复均直接落定当前模型并清零翻牌进度，避免卡在动画半程。


### fps：只限显示，实例覆盖插件与全局
- `Countman.fps` 默认 null；插件、Options 与组件的同名配置按实例 > 插件 > 全局
  逐级回退。运行时全局修改打断休眠，下一帧生效；非法值 debug 断言、release 当 null。
- 完成/阈值属于时间事件，不应因省绘制开销而推迟；显示限帧与桶边界取较晚者，
  再与完成/阈值取最早唤醒。终点强制显示精确终值，静音优先沿用不可见休眠逻辑。
- Counter 限帧后会走休眠 Timer，而唤醒首帧 dt == 0，因此仅限帧路径改按系统
  单调钟差值推进；未限帧保持原 dt 路径。显示节拍跳过错失时隙，避免 vsync 量化
  导致累计降速；暂停排除流逝，迁移与重定向保留真实进度。
- CardCountdown 的进度并入共享 Counter，fps 同样真正降低出帧；端点精确投递，
  时长、曲线及 calendar 两段提交语义保持不变。旧重绘节流方案已由真窗口证据推翻。
- Counter / ClockPlugin 的显示节拍按固定网格推进，以 `display.refreshRate`
  提供的 vsync 周期作对齐，容差为半个 vsync；显示请求点为 `allowed - tol`，
  正数限帧等待均走全局 Timer。目标显示率不超过屏幕刷新率，
  `period <= vsyncPeriod * 1.05` 视为不限；桶边界、完成与阈值不减容差。


### 限帧漂移 bug：实际渲染锚点改为固定网格 + 对齐唤醒
- **根因**：ClockPlugin 用实际渲染时刻 `lastEmitMicros + period` 当下一次锚点。
  60Hz 下 30fps 的 Timer 在约 33.3ms 到期后才请求帧，再等一个 vsync，周期变成
  50ms，形成 30→20fps 漂移。Counter 虽已有固定网格，但两种引擎都在 ≤20ms
  等待窗口逐 vsync 轮询，抖动下出现没有显示更新的空帧。
- **修复**：两者共用固定网格（`next += k * period`），跳过错失时隙、不补历史帧；
  读取首个 view 的 `display.refreshRate`，有效有限正数才采用，否则回退 60Hz。
  添加任务时刷新缓存，热路径不分配。容差 `tol = vsyncPeriod / 2`，
  `now >= allowed - tol` 可显示；`nextWake` 的限帧分量返回
  `allowed - tol - now`，通过 Timer 提前请求目标 vsync，跳过 20ms 轮询窗口。
  最早等待逐任务、逐插件携带窗口提示，较晚的普通桶等待不应让限帧重新轮询。
- **保持**：只调整限帧分量；显示唤醒仍取桶边界与限帧请求时刻较晚者，再与
  完成/阈值取最早。桶与事件都不提前，终点强制精确；静音优先且不读取 fps，
  Counter 限帧仍用单调钟推进。目标显示率不超过屏幕刷新率，
  `period <= vsyncPeriod * 1.05` 等同不限，避免屏幕已到上限时额外节流。
- **之前为何漏测**：固定步长 pump 直接交付每一帧，没有 vsync 量化，也没有模拟
  Timer 到期后必须等待下一个 vsync 的行为，只数 onUpdate 还会漏掉空轮询帧。
- **防回归**：`test/core/vsync_throttle_test.dart` 每 1ms 推进 Timer，仅在有请求且
  达到 vsync 边界时 pump；模拟 Hz 同步设置 `debugRefreshRateHz` 并在结束复位。
  Counter 与 precise Countdown 覆盖 60/120Hz、30/20fps（120Hz 加 60fps）、
  0/±1.5ms 抖动、1/50 任务；断言更新率目标 ±1/s、出帧不超过更新率 +1.5/s。
  另测 50fps@60Hz（47–53/s）和 60fps@60Hz 等同不限，并验证桶/阈值/终点不提前。

### Dial 刻度环拆层 + 脏检查：no-go
- **结论**：删除独立刻度 `CustomPaint` / `RepaintBoundary`、输入快照与脏检查，
  保留默认 image 位图缓存及既有 `debugUseTickImages` 矢量回退，不增加公开配置。
- **真窗口证据**：i5-13500 / UHD770 / Impeller，Windows profile，900×600，50 个表盘，
  `interval: 0` 基准插件；预跑一次后，三模式交错各 3 轮，每轮测量 15 秒。
  仅桌面，手机未测。下表为各轮 Build / Raster 均值的三轮算术平均，单位 ms。

  | 模式 | Build 均值 | Raster 均值 |
  | --- | ---: | ---: |
  | image（保留） | 0.98 | 3.43 |
  | layer + 脏检查（删除） | 1.05 | 13.53 |
  | vector（回退） | 1.95 | 12.83 |

- **原因**：本次 Impeller 测量中，RepaintBoundary 省下刻度指令重录，却未省去逐帧光栅化；
  layer 的 Raster 与 vector 接近，明显高于共享位图，额外拆层与脏检查不值得保留。
  这是本机桌面实验结论，不外推到手机或其它渲染后端。
- **原始数据**：`build/perf/desktop-20261105-223927.json`，报告同名 `.md`。
  旧报告以三轮中位数汇总各轮均值：image / layer / vector 的 Raster 为
  3.34 / 13.56 / 12.71 ms，与本表算术平均口径不同。

### AnimatedCounter 低 FPS 诊断：桌面 no-go（2026-11-06）

- **决定**：不改生产实现。20.5 FPS 主要是每秒一次、默认 300ms 的滚动结束后休眠，
  没有活动期持续低帧率证据；仍有少量真实 Raster 超预算，不能说绝对无卡顿。
  本次没有证据支持视觉等价且收益 ≥10% 的优化，不做推测性缓存或裁剪改写。
- **条件**：i5-13500 / UHD770，Windows profile，Flutter 3.47.0，Impeller
  （OpenGLESSDF），900×600 真窗口，不激活缩小并保持可见。50 个单元每秒各变值一次；
  预跑 animatedCounter 一次，随后与持续动画 counterFree 交错各 5 轮，每轮预热 3 秒、
  测量 15 秒。**仅桌面，手机未测**；两组刷新负载不同，不直接比较组件成本。
- **逐轮耗时**：单位 ms，avg/p90/p99 为各轮帧统计，不是合并分位数。

  | 轮次 | FPS | Build avg/p90/p99 | Raster avg/p90/p99 | 超预算帧 |
  | --- | ---: | --- | --- | ---: |
  | 1 | 20.7 | 2.41 / 4.75 / 9.43 | 6.87 / 10.30 / 17.51 | 4 |
  | 2 | 20.9 | 2.12 / 3.64 / 6.66 | 6.70 / 9.31 / 12.08 | 0 |
  | 3 | 20.8 | 1.96 / 3.46 / 9.48 | 5.71 / 7.84 / 16.71 | 4 |
  | 4 | 20.4 | 2.02 / 3.65 / 5.95 | 6.08 / 8.65 / 11.43 | 0 |
  | 5 | 20.5 | 1.59 / 2.54 / 4.06 | 5.40 / 6.83 / 9.32 | 0 |

- **空闲与漏帧分开**：临时记录现有帧回调的系统 vsync 时间，以 onAnimationStart/End
  跟踪活动数（0–50）；上一帧结束仍有动画才计活动间隔，不主动请求帧。五轮活动间隔
  avg 均 16.680ms、p90/p99 均 16.681ms，共 1468 个活动间隔，>16.7ms 与 >25ms
  均为 0；活动跨度占约 32.65%，空闲间隔 p99 均 683.897ms。全体间隔 p99 为
  667.217 / 667.217 / 667.217 / 683.897 / 683.897ms，不能把这些休眠算作掉帧。
  对照 FPS 为 60.0 / 59.7 / 59.3 / 60.0 / 59.7，也测到跨 vsync 间隔。
- **边界**：1550 帧中 8 帧（0.516%）max(Build, Raster) >16.67ms，均为 Raster
  超预算；调度间隔不是屏幕呈现时间，不据此保证显示链路零漏帧，也未定位偶发尖峰根因。
  首轮 7.80ms 未重现；本次预跑 6.58ms、正式 5.40–6.87ms，也未重现旧后两轮
  约 4.4ms 的环境水平，故只能说旧首轮异常未稳定复现，不能确认就是预热离群。
- **代码解释**：进度任务加入共享 defaultCounter / 唯一 ticker，全部 idle 后停止。
  每帧原地更新常驻 painter，不重建 widget；Paragraph 按数字/透明度/方向色缓存，
  layout 发生于缓存未命中；默认淡化用文字颜色，无 Opacity。每列有 clipRect，
  saveLayer 是前导位揭示或显式 blur 等条件路径，没有每数位独立 ticker。
- **产物**：`build/perf/desktop-20261106-083722.json`（含逐帧原始耗时和诊断时间戳），
  同名 `.md`；完整诊断含口径、对照与限制：
  `build/perf/animated-diagnosis-20261106/report.md`，精简数据同目录 `summary.json`。
  临时采样代码已逐字节还原，既有 15 个未提交文件的还原前哈希核验全部一致；
  不新增生产代码、测试或依赖，不改 API、CHANGELOG，不提交 git。
- **验证**：还原后全量 `flutter test` 通过（915 项通过、6 项沿用既有跳过配置）；
  `flutter analyze lib test` 无问题。未实施优化，新增代码覆盖率与像素差分不适用。


### AnimatedCounter 消融定位：视觉门槛 no-go（2026-11-06，仅桌面）

- **决定**：不保留生产优化。硬矩形裁剪的性能信号可重复，但真位图差异超过容差；
  不用性能收益抵消视觉要求。临时开关、位图缓存、裁剪改动和诊断测试全部还原，
  API、依赖、CHANGELOG 保持本次任务开始时原样，不提交 git。
- **条件**：i5-13500 / UHD770，Flutter 3.47.0 / Dart 3.13.0，Windows profile，
  Impeller / OpenGLESSDF，900×600 真窗口，50 个组件每秒各改值一次、默认 300ms。
  强制出帧：同一临时二进制，预跑空载一次；正式 7 轮，每轮先 emptyBaseline，
  再测 7 版，各版顺序每轮轮换，恰好遍历全部顺序位置；每进程预热 3s、测量 15s。
  共 56 个有效进程，空载与显示器校验全部通过。仅桌面，手机和其他后端未测。
- **消融表**：逐轮中位数（极差 = 最大−最小），时间单位 ms；不合并帧计算分位数。

  | 版本 | Raster avg | Raster p90 | Raster p99 | presentFps | 错过vsync% | 间隔 p99 |
  | --- | ---: | ---: | ---: | ---: | ---: | ---: |
  | emptyBaseline | 1.16（2.85） | 1.92（4.07） | 3.41（6.19） | 60.00（1.27） | 0.000（0.795） | 20.19（4.93） |
  | 原版 | 8.02（10.89） | 13.71（13.78） | 19.22（17.78） | 59.73（2.20） | 1.012（2.647） | 25.30（9.53） |
  | 关闭文字提交 | 1.75（1.63） | 3.00（3.70） | 5.50（5.23） | 60.00（1.73） | 0.222（0.916） | 21.90（4.90） |
  | 关闭数字淡化 | 5.07（3.48） | 7.76（8.22） | 13.45（8.56） | 59.93（0.27） | 0.334（1.451） | 22.88（3.72） |
  | 关闭逐列裁剪 | 3.13（3.73） | 4.93（6.76） | 9.36（11.21） | 59.87（2.53） | 0.224（1.399） | 23.53（7.03） |
  | 预热全部段落 | 5.62（3.78） | 9.20（7.35） | 13.76（18.56） | 59.87（11.60） | 0.223（3.204） | 24.46（15.15） |
  | 关闭组件重绘边界 | 5.75（6.53） | 7.91（11.47） | 13.45（13.45） | 59.33（5.20） | 0.668（1.709） | 23.64（5.94） |
  | 保留裁剪、关闭抗锯齿 | 3.37（4.65） | 5.42（6.90） | 9.70（9.72） | 60.00（0.33） | 0.222（1.230） | 22.91（5.06） |
  | 字形位图缓存原型 | 无有效数据 | — | — | — | — | — |

- **开销归因**：关闭文字提交和硬裁剪的同轮 p99 分别 7/7 轮改善，支持文字与
  逐列抗锯齿矩形裁剪是本机默认路径的主要开销组合；未采引擎 glyph/path trace，
  不能断言文字必然转路径光栅化。默认 slide 用绘制坐标，无透视变换和 Opacity；
  Paragraph 命中时不 layout，TextPainter 测量只随配置失效；常驻 painter 原地更新，
  无逐帧 widget rebuild。动画使用共享 Counter/ticker，边界按 counter 而非 digit；
  saveLayer 只在前导位 reveal、显式 blur 等条件路径，非默认每位每帧。
- **性能与视觉分开裁决**：硬裁剪 p99 从 19.22（极差 17.78）到 9.70（9.72），
  两组中位数之比改善 49.53%；同轮配对改善中位数 43.76%，极差 49.75 个百分点，
  7 轮均超过 10%。但按 `test/support/bitmap.dart` 的平均通道误差口径、容差 2，
  紧截图矩阵共 1120 组，116 组超标、最大 4.534；包含 Ahem 默认纵向 slide
  静止端点，不能仅限制运动类型解决。初步 Segoe UI 的 56 组最大仅 0.33，
  证明小样本通过不足以保证全部支持字形等价，故撤销。
- **其他候选**：关闭文字/淡化/裁剪改变视觉。预热段落同轮配对 p99 改善中位数
  5.03%，未达 10%；保留 48.33 FPS 异常轮。关闭边界配对中位数改善 24.41%，
  但改善比例极差 75.68 个百分点、2/7 轮反向，presentFps 中位数下降且最低
  54.73；不据此宣称稳定收益或取消既有默认边界。字形位图复用 ImageByteCache，
  每 painter 256 KiB、销毁/换色清理，但 profile 首轮发生 Context Lost /
  framebuffer fatal，无 BENCH；不编造指标，也不外推为全部共享位图方案不可行。
- **口径限制**：presentFps 是 rasterFinish 完成速率代理，不能等同 DWM/硬件扫描。
  错过vsync% 是间隔 >1.5×参考周期的比例，非丢失槽位数。原版 p99 为
  7.29–25.07ms，噪声明显；不把配对比值的中位数与两组中位数之比混用。
- **产物**：完整报告 `build/perf/animated-counter-investigation/report.md`，
  聚合 `summary.json`；主批次 `build/perf/desktop-present-20261106-094116.json`
  （按 ablation 分组，含逐帧原始完成时间戳），同前缀 `-preflight.json` 为预跑。
  像素数据 `clip-pixels-all.json`、初步 `pixels.json`、断言失败
  `clip-test-first-failure.log` 和逐字节还原核验 `restoration.json` 均在报告目录。
  首次失败批次单独保存，未混入统计，全部异常轮次保留。
- **验证**：还原后 `flutter test --concurrency 1` 全量 915 项通过、6 项沿用既有跳过；
  `flutter analyze lib test` 无问题。像素预检与全量测试首次均发生编译器 OOM，
  清理仅本次失败命令的遗留进程后重试通过，未终止其他工作区进程。
  example 下的 `flutter analyze lib test` 也无问题。
  无新增生产代码，新增行覆盖率不适用；不运行 pnpm typecheck。
