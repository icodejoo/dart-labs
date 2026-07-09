# Countman 设计决策记录

## Phase 1 — 核心引擎

### Ticker：纯单例
- `Countman` 静态类，不支持多实例
- Flutter 只有一个 vsync，多实例无收益
- 驱动：`SchedulerBinding.scheduleFrameCallback`（等价 rAF）

### 分组：插件多实例
- 每个 `CountmanPlugin` 实例 = 一个独立任务队列 = 一个"分组"
- 取代 `@codejoo/counter` 的 label 字符串分组，心智更简单
- 所有实例挂在同一个 ticker 上，开销不变

### CountmanContext：单例注入
- `Countman._ctx` 是 `static final`，进程生命周期只创建一次
- `use(plugin)` 时通过 `plugin.onAttach(ctx)` 注入，不在每次调用时 new
- 好处：插件不依赖 `Countman` 类，依赖方向单向（Countman → Plugin）

### 空闲自停
- `tick()` 返回 `false` = 本插件无活跃任务
- 所有插件均返回 `false` → ticker 自动停止，无任务时零开销
- 插件 `add()` 任务时调 `ctx.requestFrame()` 唤醒 ticker

### Lazy 任务（方案 A）
- 非活跃任务（待进入视口）：`tick()` 跳过，不计 busy
- ticker 可停止；任务激活时再调 `requestFrame()` 重启

---

## Phase 2 — CountupPlugin

### 数值类型：`double`
- 插值天然是浮点，引擎内部统一 `double`
- 显示层由用户或 formatter 决定是否取整

### Easing：使用 Flutter `Curve`
- 与 Flutter 生态统一，`Curves.easeOut` 等开箱即用
- 签名一致：`transform(t: double) → double`，无需自定义 easing 函数

### Retarget：`CountupHandle` 对象
- `plugin.add()` 返回 `CountupHandle`，封装 id + plugin 引用
- `handle.update(to: newTo)` 从当前值续接，不跳变
- `handle.cancel()` 移除任务

### 回调：`onUpdate` 为主，Widget 层用 `ValueNotifier`
- 引擎层：`onUpdate(double value)` 回调，零分配，无 Stream 开销
- Widget 层：`ValueNotifier<double>` + `ValueListenableBuilder`，符合 Flutter 习惯

### API 入口：顶层函数自举 + plugin.add 两层
- `countup(opts)` — 默认插件自动注册，99% 场景
- `plugin.add(opts)` — 自定义分组，需显式 `Countman.use(plugin)`

### 计时方式：dt 累积
- 不用 `elapsed` 绝对时间（Flutter 测试里第一帧 elapsed 经 epoch 调整为 0）
- 用 `dt` 增量累积（frame 1 dt=0 锚定，frame 2+ 累积），测试和生产行为一致

---

## Phase 2 — CountupText / CountupBuilder Widget

### `CountupBuilder`
- `StatefulWidget`，内部持有 `ValueNotifier<double>`
- `onUpdate` 更新 notifier，`ValueListenableBuilder` 驱动重建
- `didUpdateWidget` 检测 `to` 变化时调 `handle.update()` retarget

### `CountupText`
- `StatelessWidget` 包装 `CountupBuilder`
- 保留：`prefix`/`suffix`（String）、`prefixWidget`/`suffixWidget`（Widget）
- 去掉：`prefixBuilder`/`suffixBuilder`（感知数值的前后缀直接用 `CountupBuilder`）
- `prefix` 和 `prefixWidget` 同时传时 Widget 优先

### `plugin` 参数：暂不暴露
- 目前 Widget 统一走 `countup()` 默认实例
- 分组需求出现时再添加（加参数比去参数容易）

---

## CountupOdometer — odometer vs flip_counter_plus

### 选择 odometer 作为依赖
- `odometer` 的核心是 `OdometerNumber` + `Odometer` widget（per-digit Stack）
- `flip_counter_plus` 功能更丰富（小数、50 个参数、7 种过渡）但不可作为依赖（无共享 ticker，单文件 2455 行）
- 参考 flip_counter_plus 的思路按需实现特性

### OdometerNumber 构造方式：Option A（float 直接构造）
- 放弃 `OdometerNumber.lerp`，改用 `_fromFloat(v)` 直接从 float 值构造
- 个位携带小数进度（平滑滑动），高位在整数进位时跳变
- 彻底解决递减时补零问题
- 回退点：commit `462fd0f`（lerp 方案）

### prefix/suffix 与 CountupText 保持一致
- prefix/suffix (String) + prefixWidget/suffixWidget (Widget)，Widget 优先
- 有前后缀时套 Row，否则直接返回 digits widget

### RepaintBoundary 可选参数
- `CountupBuilder` 和 `CountupPlus` 均增加 `repaintBoundary: bool = true`
- 默认启用；大量实例（如 demo 宫格）应设为 false 避免 GPU 合成层爆炸
- README 需说明：>10 个并发建议 `repaintBoundary: false`

### 性能瓶颈实测（0→999,999,999，94 并发）
- build=75-85ms（主因）：94 个 ValueListenableBuilder × 9 DigitColumn = 846 widget 重建/帧
- raster=8-11ms（正常）：RepaintBoundary 生效
- 启动 spike=400-800ms：94 个 widget 同时 didUpdateWidget

### StartScheduler — 启动分批
- `lib/src/core/start_scheduler.dart`，CountupPlugin 和 CountdownPlugin 共用
- `batch: int`（默认 0 = 不分批）加在 CountupPlus 构造器上
- `batch: 5` 表示每帧最多启动 5 个 widget，约 5×3ms = 15ms，不超帧预算
- 只对「动画首次启动」分批；resume/reverse/restart 是用户主动操作，立即执行
- 副作用：视觉上 widget 以 batch 大小依次出现，非完全同帧（可接受）

### 路径 B（CustomPainter）决策
- `CountupPlus` 改为 CustomPainter 渲染，消除 build 开销（~80ms → ~2ms）
- **混合方案**：默认走 CustomPainter；用户传 `digitBuilder`/`digitTransitionBuilder` 时 fallback 到 Widget 路径
- 用户选择 builder 时知晓性能代价，不是意外降级
- 路径 A（每位独立 ValueNotifier）被 B 完全覆盖，不需要实施
- 预估工期：最小可用版（roll/fade/scale + 混合）4-5 天

### 小数支持（待实现）
- 参考 flip_counter_plus：`v * 10^fractionDigits` 转整数后构造 OdometerNumber
- 渲染层从 SlideOdometerTransition 换成直接用 Odometer，在第 N 位前插 decimalSeparator

---

## Phase 3 — CountdownPlugin（待脑暴）
