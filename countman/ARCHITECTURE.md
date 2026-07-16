# Countman 架构文档

## 项目概述

**countman** 是一个高性能的 Flutter 计数动画库，支持计数 (Counter)、倒计时 (CountDown)、秒表 (StopWatch) 功能。核心设计是使用一个共享的 Vsync 定时器驱动所有实例，避免每个 Widget 创建独立定时器，实现高并发场景下的性能优化。

## 核心架构

```
Flutter Widget
    ↓
[Countman 控制器]
    ├─ Counter (计数)
    ├─ CountDown (倒计时)
    └─ StopWatch (秒表)
    ↓
[共享 Vsync 定时器]
    └─ 单一全局定时器驱动所有实例
    ↓
[动画回调 (onTick)]
    ├─ 每帧调用
    └─ 状态更新
    ↓
[状态管理]
    ├─ 当前值
    ├─ 目标值
    └─ 动画进度
    ↓
[渲染]
    ├─ GetBuilder 重建
    ├─ Obx 响应式
    └─ 自定义渲染
    ↓
用户看到的动画
```

## 主要特性

### 1. **共享 Vsync 定时器**
- 所有 Counter/CountDown/StopWatch 实例共享一个 Vsync 定时器
- 减少 Timer 对象创建
- 高并发场景性能优秀

### 2. **三种计数模式**

#### Counter (计数)
```dart
final counter = Counter(
  initial: 0,
  target: 100,
  duration: Duration(seconds: 1)
);
await counter.start();  // 从 0 数到 100
```

#### CountDown (倒计时)
```dart
final countdown = CountDown(
  duration: Duration(minutes: 5)
);
countdown.start();  // 从 5 分钟倒数到 0
```

#### StopWatch (秒表)
```dart
final stopwatch = StopWatch();
stopwatch.start();   // 开始计时
stopwatch.pause();   // 暂停
stopwatch.resume();  // 继续
```

### 3. **缓动动画**
- 内置多种缓动函数 (Linear, EaseIn, EaseOut, etc.)
- 支持自定义缓动函数
- 平滑的数值变化

### 4. **GetX 集成**
- 使用 GetX 的 Rx 响应式系统
- Obx 自动重建 Widget
- 无需手动订阅

### 5. **高精度**
- 毫秒级精度
- 适合精确计时需求

## 文件结构

```
lib/
├── src/
│   ├── core/
│   │   ├─ ticker_manager.dart  # Vsync 定时器管理
│   │   ├─ counter.dart         # Counter 实现
│   │   ├─ countdown.dart       # CountDown 实现
│   │   └─ stopwatch.dart       # StopWatch 实现
│   ├── animations/
│   │   ├─ easing.dart          # 缓动函数
│   │   └─ animation_mixin.dart # 动画 Mixin
│   ├── widgets/
│   │   ├─ counter_widget.dart  # Counter Widget
│   │   ├─ countdown_widget.dart# CountDown Widget
│   │   └─ stopwatch_widget.dart# StopWatch Widget
│   ├── types.dart              # 类型定义
│   └─ constants.dart           # 常量
└── countman.dart               # 主入口
```

## 核心流程

### 初始化

```dart
// 创建 Counter
final counter = Counter(
  initial: 0,
  target: 999,
  duration: Duration(seconds: 3),
  easing: Easing.easeOut
);
```

### 执行流程

```
用户调用 counter.start()
    ↓
[初始化]
    ├─ 记录起始值
    ├─ 计算总帧数
    └─ 注册到共享 Ticker
    ↓
[Ticker 开始]
    ├─ 每帧调用 onTick 回调
    └─ 触发 Rx 更新
    ↓
[计算当前值]
    ├─ 计算缓动进度 (0 → 1)
    ├─ 根据缓动函数计算数值
    └─ 更新 Rx 变量
    ↓
[Widget 重建]
    ├─ Obx 监听 Rx 变化
    ├─ 自动重建 Widget
    └─ 显示新的数值
    ↓
[重复]
    └─ 直到达到目标值
    ↓
[完成]
    ├─ 触发 onComplete 回调
    ├─ 从 Ticker 注销
    └─ 清理资源
```

### 共享 Ticker 机制

```dart
// TickerManager 内部

class TickerManager {
  late Ticker _ticker;
  final List<TickerCallback> _callbacks = [];
  
  void register(TickerCallback callback) {
    _callbacks.add(callback);
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }
  
  void unregister(TickerCallback callback) {
    _callbacks.remove(callback);
    if (_callbacks.isEmpty) {
      _ticker.stop();
    }
  }
  
  void _onTick(Duration elapsed) {
    for (var callback in _callbacks) {
      callback(elapsed);
    }
  }
}

// 所有 Counter 实例共享一个 Ticker
final counter1 = Counter(...);  // 注册到 TickerManager
final counter2 = Counter(...);  // 注册到同一 TickerManager
final counter3 = Counter(...);  // 注册到同一 TickerManager

// 三个 Counter 共用一个 Ticker，性能最优
```

## 性能优化

### 1. **共享 Ticker**
减少 Timer 对象创建，高并发场景下 CPU 占用更低

### 2. **Rx 响应式**
GetX 的 Rx 系统高效处理状态变化，自动重建只涉及改变的 Widget

### 3. **内存管理**
及时清理过期的回调，防止内存泄漏

## 与其他项目的关系

- **@codejoo/counter** (TypeScript/JavaScript 版本): 类似的功能设计
- **GetX 库**: 依赖 GetX 的 Rx 和 Widget 系统

## 参考

- [README.md](./README.md)
- [源代码](./lib)
- GetX: https://pub.dev/packages/get
