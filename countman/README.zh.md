# countman

**面向 Flutter 的高性能计数器、倒计时与计时动画 —— 由一个共享的 vsync ticker 驱动，而非逐组件的定时器。专为高并发计时场景设计。**

[English](README.md) · **简体中文**

[![pub.dev](https://img.shields.io/pub/v/countman.svg)](https://pub.dev/packages/countman)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Demo](https://img.shields.io/badge/demo-live-brightgreen)](https://icodejoo.github.io/dart-labs/)

**[▶ 在线演示](https://icodejoo.github.io/dart-labs/)** —— 计数器 · 倒计时 · 计时，涵盖全部组件、全部 API。

- ⚡ **无 `Timer.periodic`，无逐组件 `AnimationController`** —— 一切都由单个 `SchedulerBinding.scheduleFrameCallback` 驱动。
- 🚀 **专为高并发设计** —— 第 100 个活动计数器/计时器与第 1 个开销相同；当没有任何动画时，ticker 会自动进入空闲。
- 🎨 计数器 · 倒计时 · 计时，每类都提供 文本 / 环形 / 进度条 / 里程表 / 表盘 / 翻牌 渲染器，支持逐组件样式、控制器与 provider。

---

## 截图

| 计数器 | 倒计时 | 计时 |
| :---: | :---: | :---: |
| ![计数器演示](example/screenshots/counter.jpg) | ![倒计时演示](example/screenshots/countdown.jpg) | ![计时演示](example/screenshots/elapsed.jpg) |
| 文本 / 环形 / 条形 / 里程表 / 动画 | 文本 / 环形 / 条形 / 表盘 / 卡片 | 秒表、高精度、Provider |

> 截取自[示例应用](example/) —— 可在[在线演示](https://icodejoo.github.io/dart-labs/)中实际体验。

---

## 为什么选择 countman？

大多数计数器包会给每个组件配一个自己的 `AnimationController`（或一个
`Timer.periodic`）。屏幕上有 N 个计数器，你就要付出 N 次帧回调
注册、N 个定时器和 N 套彼此独立、互不感知的动画生命周期。

**countman** 反其道而行：由一个 `SchedulerBinding.scheduleFrameCallback` 驱动
每一个实例。ticker 在动画间隙处于空闲（当所有任务
完成时自动停止），并按需唤醒。新增第一百个计数器与
新增第一个开销相同。

```
Countman (1 scheduleFrameCallback)
  ├── Counter    — interpolates numbers from → to (every frame)
  ├── Countdown  — wall-clock deadline timers (interval-gated)
  └── Elapsed    — wall-clock elapsed timers (interval-gated)
```

每个引擎都是一个 `CountmanPlugin`；你可以为每类注册多个实例，
以隔离互相独立的「分组」。

---

## 安装

```yaml
dependencies:
  countman: ^0.1.0
```

```dart
import 'package:countman/countman.dart';
```

---

## 性能

| 方案 | 帧回调 | 定时器分配 |
|---|---|---|
| N 个 `AnimationController` | N | N 个 vsync 监听器 |
| N 个 `Timer.periodic` | — | N 个定时器 |
| **countman** | **1** | **0** |

在 94 个并发 `AnimatedCounter` 实例（0 → 999,999,999）下测量：

- **Raster：8–11 ms** —— RepaintBoundary 让每个计数器处于自己的图层。
- **Build：~2 ms** —— CustomPainter 路径完全跳过组件实例化。
- **启动尖峰** 通过 `StartScheduler` 批处理分摊到多帧。

### 与其他包的正面对比

**50 个并发倒计时**，Windows 桌面 **profile** 模式，每库测量 15 s，
同一会话中依次连续运行（显示器 120 Hz）。FPS =
实际渲染帧数 ÷ 耗时；UI/raster = 每帧线程时间；
CPU = 占**一个**核心的比例，从操作系统进程外部采样；RSS =
常驻内存集大小。除 FPS/jank 外均越低越好。

*（50 个并发倒计时，Windows 桌面 profile 模式，每库测量 15 s，同一会话依次运行，
显示器 120 Hz。CPU 为单核占用率，从操作系统进程外部采样。除 FPS/jank 外均越低越好。）*

**卡片 / 滑动模式** —— countman `CardCountdown(slide)` 对比 [`slide_countdown`](https://pub.dev/packages/slide_countdown) `^2.0.2`：

| 指标 | countman `CardCountdown` slide | `slide_countdown` |
|---|---|---|
| FPS（帧数 / 15 s） | **121.7** (1826) | 32.5 (488) |
| UI ms  avg / p99 | **0.80 / 2.12** | 1.32 / 4.39 |
| raster ms  avg / p99 | **0.83 / 1.47** | 1.05 / 1.76 |
| jank 帧 | 0 | 0 |
| RSS  avg / peak (MB) | 130.2 / 137.3 | 130.3 / 135.4 |
| CPU（1 核） | 26.1 % | **10.0 %** |

countman **每一帧 vsync** 都驱动滑动+缩放+透明度过渡（完全
顺滑、单帧更便宜），因此渲染的帧数多得多、总
CPU 更高；`slide_countdown` 仅在其每秒一次的滑动突发期间重绘 ——
CPU 更低，但节奏更突发、单帧更贵。两者均无卡顿，且使用
相同的内存。

*（countman 每帧驱动滑动+缩放+透明动画，完全顺滑、单帧更便宜，因此帧数更多、总 CPU
更高；`slide_countdown` 仅在每秒滑动瞬间重绘——CPU 更低，但帧节奏更突发、单帧更贵。
两者均无卡顿，内存相同。）*

**文本模式** —— countman `TextCountdown` 对比 [`stop_watch_timer`](https://pub.dev/packages/stop_watch_timer) `^3.2.2`（通过 `StreamBuilder` 驱动一个 `Text`）：

| 指标 | countman `TextCountdown` | `stop_watch_timer` |
|---|---|---|
| FPS（帧数 / 15 s） | 120.9 (1813) | 120.1 (1801) |
| UI ms  avg / p99 | **0.10 / 0.16** | 0.16 / 0.66 |
| raster ms  avg / p99 | 0.37 / 0.59 | **0.31 / 0.58** |
| jank 帧 | 0 | 0 |
| RSS  avg / peak (MB) | 113.8 / 116.0 | 113.9 / 116.4 |
| CPU（1 核） | **12.1 %** | 18.8 % |

对于纯文本倒计时，单一共享 ticker + `markNeedsPaint` 比
50 个独立的 `stop_watch_timer` 流**少用约 35% 的 CPU**
（单核 12.1 % vs 18.8 %），且单帧 UI 耗时更稳定；内存
完全相同。

*（纯文本倒计时下，单一共享 ticker + `markNeedsPaint` 比 50 个独立
`stop_watch_timer` 流省约 35% CPU（单核 12.1% vs 18.8%），单帧 UI 耗时更稳；
内存相同。）*

> 使用 `example/lib/benchmark_page.dart` 复现：
> `flutter run --profile -d windows --dart-define=BENCH_LIB=countmanCard`
>（也可用 `slide` / `countmanText` / `stopWatch`）。

---

## Counter（计数器）

数值插值组件。它们在共享 ticker 上执行 `from → to` 的动画。
所有组件都接受 `from` / `to` / `duration`（默认 1000 ms）/ `curve`
（默认 `Curves.easeOut`）/ `allowNegative`（默认 `false`，钳制到 ≥ 0）/
`plugin` / `controller`（[`CounterValueController`](#counters-controller)），外加
生命周期回调 `onUpdate` / `onComplete` / `onReady` / `onStart` /
`onCancel`，以及 `animateOnce`（参见 [进阶](#animate-once-list-friendly)）。

### `TextCounter`

即插即用的文本计数器，可选前缀/后缀。

```dart
TextCounter(to: 9999)                                        // "9999"
TextCounter(to: 9999, prefix: '¥', style: const TextCounterStyle(
  textStyle: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)))
TextCounter(to: 9999, prefixWidget: const Icon(Icons.star), suffix: ' pts')
TextCounter(to: 1234.56, fractionDigits: 2)                  // "1234.56"
TextCounter(to: 1234.56, formatter: (v) => v.toStringAsFixed(2))
```

| 参数 | 默认值 | 说明 |
|---|---|---|
| `to` | 必填 | 目标值 |
| `from` | `0` | 起始值 |
| `formatter` | 整数 | `String Function(double)` —— 优先于 `fractionDigits` |
| `fractionDigits` | — | 无 `formatter` 时的小数位数 |
| `style` | — | `TextCounterStyle`（`CountmanTextStyle` 的别名） |
| `prefix`/`suffix` | — | 纯文本；`prefixWidget`/`suffixWidget` 优先 |
| `semanticsLabel` | — | 固定的屏幕阅读器标签 |
| `repaintBoundary` | `false` | 隔离重绘图层 |

### `RingCounter`

朝目标填充的圆弧：progress = `(value − from) / (to − from)`。

```dart
RingCounter(
  to: 100,
  style: const RingCounterStyle(size: 80, strokeWidth: 10),
  center: const TextCounter(to: 100, suffix: '%'),
)
```

视觉样式位于 [`RingCounterStyle`](#ring-style)（`RingStyle` 的别名）。也
支持 `painterBuilder: (context, progress) => CustomPainter` 以完全
自定义圆弧。

### `BarCounter`

朝目标填充的线性进度条。

```dart
BarCounter(to: 100, style: const BarCounterStyle(
  width: 240, height: 12, gradient: LinearGradient(colors: [Colors.blue, Colors.green])))
```

视觉样式位于 [`BarCounterStyle`](#bar-style)（`BarStyle` 的别名）；也支持
`painterBuilder`。

### `OdometerCounter`

机械里程表式的滑动数字，由一个自包含的 `CustomPainter` 绘制
（不依赖第三方包）。个位数字连续滚动，更高位的
数字在整数进位时跳动。

```dart
OdometerCounter(
  to: 9999,
  style: const OdometerCounterStyle(
    numberTextStyle: TextStyle(fontSize: 40),
    letterWidth: 24,
  ),
  groupSeparator: ',',       // text drawn every 3 digits
)

OdometerCounter(from: 9999, to: 100)               // decreasing, no leading zeros
OdometerCounter(to: 500, bounceOvershoot: 0.35)    // spring overshoot per digit
```

| 参数 | 默认值 | 说明 |
|---|---|---|
| `style` | — | `OdometerCounterStyle`（`numberTextStyle`、`letterWidth` 20、`verticalOffset` 20、`fadeEnabled`、`digitAlignment`、`crossAxisAlignment`、`prefixStyle`、`suffixStyle`、`padding`、`decoration`） |
| `groupSeparator` | — | 每 3 位绘制的 `String` |
| `slideCurve` | — | 逐位滑动的缓动曲线 |
| `bounceOvershoot` | `0.0` | 个位数字每次过渡的过冲幅度 |
| `prefix`/`suffix`/`prefixWidget`/`suffixWidget` | — | 前后缀 |

### `AnimatedCounter`

功能齐全的滚动数字计数器：可组合过渡、错峰、紧凑
记数法、小数、数字分组、颜色着色以及编程式控制。
由一个持久化的 `CustomPainter` 支撑 —— 每帧零组件构建
（`AnimatedCounterBuilder` 变体改走组件树路径）。

```dart
AnimatedCounter(value: 9999)

AnimatedCounter(
  value: 1000000,
  duration: const Duration(seconds: 2),
  transition: CounterTransition.slide,   // .slide·.slideScale·.slideBlur·.rotate·.flip·.flipFade
  staggerDelay: const Duration(milliseconds: 30),
  staggerDirection: StaggerDirection.rightToLeft,
  thousandSeparator: ',',
  style: const AnimatedCounterStyle(
    textStyle: TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
    increasingColor: Colors.green, decreasingColor: Colors.red,
  ),
)

// 货币：前缀 + 分组模式（grouping [3]=USD、[4]=CNY、[3,2]=INR）
AnimatedCounter(value: 1234.56, prefix: r'$', fractionDigits: 2,
    thousandSeparator: ',', groupingPattern: const [3])   // $1,234.56

// Compact notation
AnimatedCounter(value: 1200000, compactNotation: true)  // "1.2M"

// International numerals
AnimatedCounter(value: 2025, numeralSystem: NumeralSystem.devanagari)
```

关键参数：

| 参数 | 默认值 | 说明 |
|---|---|---|
| `value` | — | 目标值（或通过 `controller` 驱动） |
| `controller` | — | [`AnimatedCounterController`](#animatedcounter-controller) |
| `duration` | `300 ms` | 动画时长 |
| `curve` | `Curves.linear` | 缓动曲线 |
| `transition` | `CounterTransition.slide` | 可组合外观：预设 `.slide`·`.slideScale`·`.slideBlur`·`.rotate`·`.flip`·`.flipFade`，或由 `CounterMotion`（`none`/`slide`/`rotate`/`flip`）叠加 `scale`/`fade`/`blur` 修饰自建，如 `CounterTransition(motion: CounterMotion.none, scale: true)` |
| `fast` | `false` | 每位单步：每列只移动一个身位（旧→新，如 1000→9999 千位 1→9 一次），而非完整级联滚动。对所有 `transition` 生效；painter 与 widget 两条路径都支持。 |
| `fractionDigits` | `0` | 小数位数 |
| `wholeDigits` | `1` | 最少整数位槽 |
| `hideLeadingZeroes` | `true` | 隐藏前导零 |
| `thousandSeparator` | — | 例如 `','` |
| `groupingPattern` | `[3]` | 数字分组（INR 用 `[3, 2]`，CNY 用 `[4]`） |
| `decimalSeparator` | `'.'` | 小数点字符 |
| `staggerDelay` | — | 逐位错峰偏移 |
| `staggerDirection` | `rightToLeft` | `leftToRight` 或 `rightToLeft` |
| `compactNotation` | `false` | 将 `1200000` 显示为 `1.2M` |
| `compactAbbreviations` | K/M/B/T | 自定义紧凑标签（`Map<num,String>`） |
| `numeralSystem` | `latin` | `easternArabic`·`persian`·`devanagari`·`bengali` |
| `showPositiveSign` | `false` | 为正值显示带动画的 `+` |
| `flipDirection` | `AxisDirection.up` | 数字滚动方向 |
| `reverseDuration` / `reverseCurve` | — | 反向动画时的时序 |
| `startDelay` | — | 开始前的延迟 |
| `speedMultiplier` | `1.0` | 缩放所有时长 |
| `triggerHaptics` | `false` | 数字变化时的选择点击反馈 |
| `autoEaseThreshold` | `100000` | 对大范围线性动画自动 `easeInOut` |
| `repaintBoundary` | `true` | 隔离重绘图层 |
| `style` | — | `AnimatedCounterStyle`（文本/前后缀/分隔符样式、对齐、`padding`、`increasingColor`/`decreasingColor`/`colorFadeDuration`、`decoration`） |
| `painterBuilder` | — | 自定义 `CounterPainter` 子类工厂 |

### `AnimatedCounterBuilder`

与 `AnimatedCounter` 同一引擎，但暴露 `digitBuilder` /
`digitTransitionBuilder`，让你用自己的组件渲染每一位数字
（始终走组件树路径 —— 请仅用于少量计数器）。

```dart
AnimatedCounterBuilder(
  value: 1234,
  digitBuilder: (context, digit, style) => Text('$digit', style: style),
)
```

### `CounterBuilder`

底层驱动。通过 `builder` 暴露原始的动画 `double` —— 你可以
基于它构建任何东西。缓存的 `child` 每帧原样透传。

```dart
CounterBuilder(
  to: 9999,
  duration: const Duration(seconds: 2),
  curve: Curves.easeOut,
  builder: (context, value, child) => Text(value.toInt().toString(),
      style: const TextStyle(fontSize: 48)),
)
```

`valueTransform` 在值到达 `builder` 之前对其进行映射；`onUpdate` 仍然
看到原始值。

### <a name="counters-controller"></a>`CounterValueController`

针对计数器家族（`TextCounter`、`RingCounter`、
`BarCounter`、`OdometerCounter`、`CounterBuilder`）的命令式控制。

```dart
final ctrl = CounterValueController();
TextCounter(to: 0, controller: ctrl);

ctrl.update(to: 9999, duration: const Duration(seconds: 1)); // retarget from current
ctrl.pause();
ctrl.resume();
ctrl.cancel();
ctrl.value;        // current animated value
ctrl.isAnimating;  // running (not paused, not done)
ctrl.isPaused;
ctrl.isDone;
```

### <a name="animatedcounter-controller"></a>`AnimatedCounterController`

面向 `AnimatedCounter` / `AnimatedCounterBuilder` 的更丰富控制器。

```dart
final ctrl = AnimatedCounterController(initialValue: 0);
AnimatedCounter(controller: ctrl, value: 0);

ctrl.animateTo(9999);   // animate to a value
ctrl.jumpTo(9999);      // instant, no animation
ctrl.pause();
ctrl.resume();
ctrl.stop();
ctrl.restart();
ctrl.repeat(reverse: true);
ctrl.reverse();
ctrl.status;            // AnimationStatus
ctrl.addStatusListener(listener);
```

---

## Countdown（倒计时）

墙钟截止计时器。每个倒计时组件都接受 `to` —— 可为
`DateTime`、`Duration`、`int`（自纪元起的毫秒数）**或** ISO-8601 `String` ——
它们都会被解析为一个绝对截止时间，因此后台暂停与丢帧
永远不会造成漂移。共享参数：`plugin`、`precise`、`controller`
（[`CountdownController`](#countdown-controller)）、`onComplete`、`onTick`、
`threshold` + `onThreshold`，以及生命周期 `onReady`/`onStart`/`onCancel`/
`onPause`/`onResume`。

### `TextCountdown`

即插即用的倒计时文本。当 `to` 为 `Duration` 时可用 `const` 构造。

```dart
TextCountdown(
  to: const Duration(minutes: 5),
  formatter: CountdownFormat.ms,
  style: const TextCountdownStyle(
    textStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
)

TextCountdown(to: DateTime(2026, 1, 1), formatter: CountdownFormat.dhms)
```

### `RingCountdown`

从满到空逐渐排空的弧形环（progress = 剩余 / 总量）。默认
开启一个领先的圆点，让慢速倒计时每一跳都可见地移动。

```dart
RingCountdown(
  to: const Duration(minutes: 2),
  style: const RingCountdownStyle(size: 100, strokeWidth: 10),
  center: const TextCountdown(to: Duration(minutes: 2), formatter: CountdownFormat.ms),
)
```

### `BarCountdown`

随时间流逝而收缩的线性进度条。

```dart
BarCountdown(
  to: const Duration(minutes: 1),
  style: const BarCountdownStyle(
    width: 250, height: 10,
    gradient: LinearGradient(colors: [Colors.green, Colors.yellow, Colors.red]),
    borderRadius: Radius.circular(5),
  ),
)
```

### `DialCountdown`

带四个同心环（刻度、两条装饰弧、内部进度环）的模拟
表盘。在最后一分钟，点亮的元素会由 绿 → 黄 → 红 渐变。

```dart
DialCountdown(
  to: const Duration(minutes: 5),
  style: const DialCountdownStyle(size: 200, glow: true),
  builder: (context, parts) => Text(
    '${parts.minutes.toString().padLeft(2, '0')}:'
    '${parts.seconds.toString().padLeft(2, '0')}',
    style: const TextStyle(color: Colors.white, fontSize: 28),
  ),
)
```

`DialCountdownStyle` 字段：`size`（200）、`clockwise`、`redAt`（3）、`yellowAt`
（10）、`colors`（`DialColors`）、`ticks`（`DialTicksConfig`）、`arcA`/`arcB`
（`DialArcConfig`）、`inner`（`DialInnerConfig`）、`glow`，以及显式的
`showTicks`/`showArcA`/`showArcB`/`showInner` 开关，外加 `centerAlignment` /
`padding` / `decoration`。`builder` 填充中心；`painterBuilder:
(context, parts) => CustomPainter` 替换整个表盘。

### `CardCountdown`

翻牌显示；每个时间单位（H/M/S）都是一张卡片，在数字
变化时执行动画。每张卡片由一个 `AnimationController` 驱动单个 `CustomPainter` ——
数字变化从不重建组件树。

```dart
CardCountdown(to: const Duration(hours: 1, minutes: 30))

CardCountdown(
  to: DateTime(2026, 12, 31),
  labels: const ['H', 'M', 'S'],       // pass null to hide labels
  separator: ':',
  showHours: true,                     // null = auto (shown when ≥ 1 h)
  style: const CardCountdownStyle(
    splitDigits: true,
    transitionType: CountdownType.slide,   // calendar · slide · flip
    scaleEffect: SlideEffect.both,
    opacityEffect: SlideEffect.enter,
    cardColor: Color(0xFF212121),
  ),
)
```

`CardCountdownStyle` 字段：`splitDigits`、`cardWidth`（56）/ `cardHeight`
（76）、`digitGap` / `unitGap`、`cardColor`、`transitionType`
（`CountdownType.calendar`/`slide`/`flip`）、`scaleEffect` / `opacityEffect`
（`SlideEffect.none`/`enter`/`exit`/`both`）、`scaleFactor`（1.5）、`perspective`
（0.006，仅 flip）、`textStyle` / `labelStyle` / `separatorStyle`、`padding` /
`decoration`。组件级：`duration`（450 ms）、`curve`（linear）、
`repaintBoundary`。另见 [`CardCountdownProvider`](#providers)。

### `CountdownBuilder`

底层驱动，将剩余时间以 [`TimeParts`](#timeparts) 形式暴露。

```dart
CountdownBuilder(
  duration: const Duration(minutes: 5),   // or use `to:` for a deadline
  builder: (context, parts, child) => Text(CountdownFormat.ms(parts)),
)
```

### <a name="countdown-controller"></a>`CountdownController`

```dart
final ctrl = CountdownController();
CountdownBuilder(duration: const Duration(minutes: 2), controller: ctrl,
  builder: (_, parts, __) => Text(CountdownFormat.ms(parts)));

ctrl.pause();
ctrl.resume();
ctrl.reset();                                     // back to original duration
ctrl.reset(duration: const Duration(seconds: 30)); // override duration
ctrl.cancel();
ctrl.remaining;  // Duration
ctrl.isPaused;
ctrl.isDone;
```

---

## Elapsed（计时）

开放式的秒表计时器 —— 从零无限向上计数，直到被移除或
取消。与 Countdown 拥有相同的 `plugin` / `precise` / `controller`
（[`ElapsedController`](#elapsed-controller)）/ `onTick` / `threshold` +
`onThreshold` / 生命周期回调。

### `TextElapsed`

```dart
TextElapsed()                                  // 00:00, 00:01, 00:02, …
TextElapsed(formatter: CountdownFormat.hms)
TextElapsed(prefix: '⏱ ', style: const TextElapsedStyle(
  textStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)))
```

### `ElapsedBuilder`

```dart
ElapsedBuilder(
  builder: (context, parts, child) => Text(CountdownFormat.hms(parts)),
)
```

### <a name="elapsed-controller"></a>`ElapsedController`

```dart
final ctrl = ElapsedController();
TextElapsed(controller: ctrl);

ctrl.pause();
ctrl.resume();
ctrl.reset();     // back to zero, then resume
ctrl.cancel();
ctrl.elapsed;     // Duration
ctrl.isPaused;
```

---

## 格式化器（Formatters）

`CountdownFormat` 提供了 `String Function(TimeParts)` 格式化器，供
每个倒计时/计时文本组件使用（通过 `formatter:`）。

| 格式化器 | 示例 | 说明 |
|---|---|---|
| `CountdownFormat.hms` | `01:23:45` | 始终显示小时 |
| `CountdownFormat.ms` | `03:07` | 分钟可超过 59 |
| `CountdownFormat.msTenths` | `00:09.7` | 十分之一秒 —— 与 `precise: true` 搭配 |
| `CountdownFormat.msMillis` | `00:09.327` | 完整毫秒精度 —— 与 `precise: true` 搭配 |
| `CountdownFormat.dhms` | `2d 03:04:05` | ≥ 1 天时显示整天数，否则用 `hms` |
| `CountdownFormat.dhm` | `2d 03:04` | 天 + 时 + 分（无秒） |
| `CountdownFormat.auto` | 自适应 | ≥1d → `dhms` · ≥1h → `hms` · <10s → `msTenths` · 否则 `ms` |

你也可以自己编写：`formatter: (t) => '${t.totalMinutes}m ${t.seconds}s'`。

---

## 样式（Styling）

每个视觉组件都接受一个 `style:` 对象；旧的零散视觉参数
（`size`、`strokeWidth`、`color`、`width`、`height`、`gradient`、`borderRadius`、
`textStyle`……）都已并入其中。**每个** 样式还携带
`decoration` + `padding`，用于容器背景 / 边框 / 圆角。

- **`CountmanTextStyle`** —— 用于文本组件。别名：`TextCounterStyle`、
  `TextCountdownStyle`、`TextElapsedStyle`。（`textStyle`、前后缀样式、`decoration`、`padding`。）

### <a name="ring-style"></a>`RingStyle`（别名 `RingCounterStyle` / `RingCountdownStyle`）

`size`、`strokeWidth`、`trackStrokeWidth`、`color`、`trackColor`、`gradient`、
`trackGradient`、`startAngle`、`strokeCap`、`clockwise`、**`sweepAngle`**（< 2π
时形成一个局部弧形仪表）、**`showTrack`**、`backgroundColor`、
`centerAlignment`，以及一个圆点：**`showThumb`**（`RingCountdown` 默认开、
`RingCounter` 默认关）、**`thumbColor`**、**`thumbRadius`**，
外加 `padding` / `decoration`。

```dart
const RingCounterStyle(
  size: 120, strokeWidth: 12,
  sweepAngle: 4.71,                     // ~270° gauge
  startAngle: 2.36,
  gradient: SweepGradient(colors: [Colors.blue, Colors.cyan]),
  showThumb: true,
)
```

### <a name="bar-style"></a>`BarStyle`（别名 `BarCounterStyle` / `BarCountdownStyle`）

`width`、`height`、`trackHeight`、`color`、`trackColor`、`gradient`、
`trackGradient`、`borderRadius`、`borderRadiusGeometry`、**`fillFromStart`**、
**`showTrack`**、**`vertical`**（沿垂直轴填充），外加 `padding` /
`decoration`。

其他样式对象：`OdometerCounterStyle`、`DialCountdownStyle`、
`CardCountdownStyle`、`AnimatedCounterStyle`（已在上文各组件处
文档说明）。所有样式均为不可变，并提供 `copyWith` 与 `merge`。

---

## Providers

Provider 将默认配置（以及一个可选的共享分组）向下传递给
后代组件。组件按 **自身属性 >
provider > 内置默认值** 的顺序解析每个值。

| Provider | 配置项 |
|---|---|
| `CounterProvider` | 计数器家族 —— `duration`、`curve`、`allowNegative`、`textStyle`、`color`、`trackColor`、`repaintBoundary`、`animateOnce`、各组件 `*Style`、`plugin`、`onGroupReady`/`onAllComplete` |
| `CountdownProvider` | 倒计时家族 —— `formatter`、`textStyle`、`color`、`trackColor`、`repaintBoundary`、`animateOnce`、各组件 `*Style`（含 `cardCountdownStyle` / `dialCountdownStyle`）、`plugin`、分组回调 |
| `ElapsedProvider` | 计时家族 —— `formatter`、`textStyle`、`textElapsedStyle`、`plugin`、分组回调 |
| `CountmanProvider` | 一次性配置全部三个家族（嵌套上述 provider） |
| `CardCountdownProvider` | `CardCountdown` 默认值 + 在一棵卡片子树间共享的字形（`TextPainter`）缓存 |

```dart
CountmanProvider(
  textStyle: const TextStyle(fontSize: 24),
  color: Colors.teal,
  formatter: CountdownFormat.hms,
  child: MyPage(),   // TextCounter / RingCountdown / TextElapsed inside inherit these
)
```

`onGroupReady` 在分组从 空闲 → 活动 时触发（首个任务入队）；
`onAllComplete` 在其从 活动 → 空闲 时触发（最后一个任务离开）。

---

## 进阶（Advanced）

### `Counter` / `Countdown` / `Elapsed` 引擎

组件只是便捷封装；你也可以直接驱动引擎。每个引擎都是一个
`CountmanPlugin`，带有一个 `name`，并（对 Countdown/Elapsed 而言）带有一个以毫秒计的 `interval`
（`1000` = 每秒一次，`0` = 每帧）。

```dart
// Top-level helpers on the auto-registered default instances:
final h  = counter(CounterOptions(to: 100, onUpdate: (v) => print(v)));
final cd = countdown(CountdownOptions(duration: const Duration(minutes: 1),
    onUpdate: (parts) => print(CountdownFormat.ms(parts))));
final el = elapsed(ElapsedOptions(onUpdate: (parts) => print(parts.inSeconds)));

// Default instances (auto-registered on first access):
defaultCounter; defaultCountdown; defaultElapsed;
defaultCountdownMs; defaultElapsedMs;   // interval: 0, used by precise widgets

// A custom group for isolation:
final auction = Countdown(name: 'auction', interval: 1000);
Countman.use(auction);                  // register (duplicate names ignored)
CountdownBuilder(duration: ..., plugin: auction, builder: ...);

Countman.start();   // usually implicit — plugins request frames when they add tasks
Countman.stop();    // pause the frame loop (tasks preserved)
Countman.destroy(); // stop + dispose every plugin
```

> 请在模块级或长生命周期状态级别注册分组。`Countman.use` 会忽略
> 重名，因此在重置时于 `initState` 内重新创建的分组将
> 永远不会收到 `onAttach`，并会在首次 `add()` 时抛出异常。

### 毫秒精度（`precise: true`）

对于亚秒级格式化器（`msTenths` / `msMillis`），设置 `precise: true` ——
组件会在共享的每帧分组（`defaultCountdownMs` /
`defaultElapsedMs`，`interval: 0`）上自我驱动，无需你手工接线 plugin。

```dart
TextCountdown(
  to: const Duration(seconds: 10),
  precise: true,
  formatter: CountdownFormat.msMillis,   // 00:09.327
)

ElapsedBuilder(
  precise: true,
  builder: (_, parts, __) => Text(CountdownFormat.msTenths(parts)),
)
```

当你传入了显式的 `plugin` 时，`precise` 会被忽略。

### <a name="animate-once-list-friendly"></a>只播放一次（适合列表）

在惰性列表中，计数器每次滚回视图都会重新播放其入场
动画。设置 `animateOnce: true` **并** 提供一个稳定的 `ValueKey`：入场动画
只会在该 key 于某个 provider 下首次出现时播放；之后的
重建会直接跳到目标值。

```dart
CounterProvider(
  animateOnce: true,
  child: ListView(children: [
    for (final row in rows)
      TextCounter(key: ValueKey(row.id), to: row.amount),
  ]),
)
```

该注册表存活于 provider 上，因此能挺过滚出/滚入。组件
自身的 `animateOnce` 会覆盖 provider 的默认值。

### 批量启动（`StartScheduler`）

当一个密集的 `AnimatedCounter` 网格在同一帧内启动时，冷启动开销
可能撑爆帧预算。`StartScheduler` 将启动分摊到多帧。

```dart
StartScheduler.instance.defaultBatchSize = 5;   // ≤ 5 starts per frame
setState(() => _target = 999);

// Per-group override:
StartScheduler.instance.groupBatchSize[myCounter] = 10;
```

对于会入队的组件，请务必在 `dispose()` 中调用
`StartScheduler.instance.cancel(this)`，以释放闭包。

### 可注入时钟（`countdownClock`）

Countdown/Elapsed 通过一个可替换的 `() → DateTime` 读取时间。在测试中
覆盖它，即可在没有真实延迟的情况下推进时间：

```dart
var fakeNow = DateTime(2024);
countdownClock = () => fakeNow;
fakeNow = fakeNow.add(const Duration(seconds: 3));   // "3 seconds pass"
```

### <a name="timeparts"></a>`TimeParts`

每个倒计时/计时 builder 收到的值对象。它每一跳都会被
**原地修改**（每个任务一份，每帧零分配）—— 请同步读取
你需要的整数值；不要跨帧持有它。

- 分量：`days`、`hours`（0–23）、`minutes`（0–59）、`seconds`（0–59）、`millis`（0–999）
- 合计：`totalHours`、`totalMinutes`、`totalSeconds`，以及 `Duration` 风格的 `inDays`/`inHours`/…/`inMicroseconds`
- `value`（原始 `Duration`）、`total`（倒计时分母，计时时为 null）、`progress`（0–1）
- `parts` —— 实时只读的 `[d, h, m, s, ms]` 视图

### 自定义画笔（`painterBuilder`）

`RingCounter`/`RingCountdown`/`BarCounter`/`BarCountdown` 接受
`painterBuilder: (context, progress) => CustomPainter`；`DialCountdown` 接受
`(context, parts) => CustomPainter`；`AnimatedCounter` 接受一个
`CounterPainterBuilder`。每个内置画笔（从
`painter/painter.dart` 导出）都拥有公开、可逐个覆盖的绘制方法，
因此你可以子类化其中之一，而无需从零开始。

---

## 性能建议

- **`repaintBoundary`** —— 开启（大多数组件默认）会让每个组件拥有自己的
  合成图层。少量时很好；对密集网格（>~10）请将其设为 `false`，
  让一个祖先图层覆盖一切。
- **用 `StartScheduler` 批量启动网格**（见上文）。
- **规模化时避免 `digitBuilder` / `digitTransitionBuilder`** —— 它们会强制走
  组件路径（~0.85 ms/位/帧），而非 CustomPainter 路径。
- **`blur` 与 `flip`** 过渡类型始终走组件路径 —— 大网格中请避免。
- **HH:mm:ss 显示用 `interval: 1000`**（默认）；只有当你确实显示
  亚秒级数字时，才去用 `precise:`/`interval: 0`。

---

## 致谢 / 归属（Credits / Attributions）

### flip_counter_plus

- 仓库：[github.com/Itsxhadi/flip_counter_plus](https://github.com/Itsxhadi/flip_counter_plus)
- 许可证：MIT
- 作用：`AnimatedCounter` 的 `DigitColumn`（以及整体结构）改编
  自 `AnimatedFlipCounter`。主要改动：
  - `AnimationController`（逐实例 vsync）被替换为共享 `Countman` ticker 上的
    `Counter` 引擎。
  - 每帧 `setState` 被替换为由 `ValueNotifier` 重绘触发器驱动的
    持久化 `CounterPainter` —— 每帧无组件构建开销。
  - Roll 过渡从 `Positioned`（布局阶段）改为
    `Transform.translate + ClipRect`（仅合成阶段）。
  - 新增了全九目标值调整，以避免退化的数字模式。

> `OdometerCounter` 不再依赖外部的 `odometer` 包 —— 它
> 由随 countman 一起打包的自包含 `CustomPainter` 绘制。

---

## 贡献（Contributing）

非常欢迎 issue 与 PR —— bug 报告、功能点子、性能
发现、文档，以及为 [示例应用](example/)（它驱动着
[在线演示](https://icodejoo.github.io/dart-labs/)）贡献的 **新 demo**，全都很有帮助。

- 🐛 [提交 issue](https://github.com/icodejoo/dart-labs/issues)
- 🔧 [发起 PR](https://github.com/icodejoo/dart-labs/pulls) —— 提交前请（在 `countman/` 下）运行
  `dart analyze` 与 `flutter test`。
- 🎨 想加个 demo？在 `example/lib/` 下放一个页面，并将其接入
  `example/lib/main.dart` 中的首页导航中枢。

## 许可证（License）

MIT —— 参见 [LICENSE](LICENSE)。
