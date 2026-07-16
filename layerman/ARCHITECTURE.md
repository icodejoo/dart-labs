# Layerman 架构文档

## 项目概述

**layerman** 是一个 Flutter 原生的弹层队列管理器，提供串行一个接一个的队列管理，支持优先级、替换、重叠、冷却和两阶段关闭。可编排 showDialog、GetX、bot_toast 等多种框架的弹层。

## 核心架构

```
应用代码 (show/queue)
    ↓
[Layerman 队列管理器]
    ├─ 队列管理 (FIFO/Replace/Overlap)
    ├─ 优先级处理
    ├─ 条件验证
    └─ 冷却管理
    ↓
[条件检查]
    ├─ 自定义谓词
    ├─ 路由条件
    └─ 认证条件
    ↓
[冷却检查]
    ├─ 会话级冷却
    ├─ 天级冷却
    └─ 时间间隔
    ↓
[弹层渲染]
    ├─ Dialog (showDialog)
    ├─ Toast (bot_toast)
    ├─ GetX Overlay
    └─ 自定义 Widget
    ↓
[用户交互]
    ├─ 点击确定/取消
    ├─ 用户输入
    └─ 异步 resolve
    ↓
[两阶段关闭]
    ├─ Before Close (可选：验证)
    └─ After Close (清理)
    ↓
[下一项处理]
    └─ 继续队列中的下一项
```

## 主要特性

### 1. **队列管理**
```dart
// FIFO - 按顺序
await layerman.show('dialog1');  // 立即显示
await layerman.show('dialog2');  // 等 dialog1 关闭后显示

// Replace - 替换
await layerman.show('old', priority: 1);
await layerman.show('new', mode: LayerMode.replace);  // 关闭 old，显示 new

// Overlap - 重叠
await layerman.show('dialog1');
await layerman.show('dialog2', mode: LayerMode.overlap);  // 同时显示两个
```

### 2. **优先级管理**
```dart
final layerman = Layerman();

// 普通优先级
await layerman.show('low', priority: 10);

// 高优先级：插队到前面
await layerman.show('urgent', priority: 100);

// 最高优先级
await layerman.show('critical', priority: 1000);
```

### 3. **条件控制**
```dart
final layerman = Layerman(
  context: context,
  routeProvider: () => currentRoute,
  authProvider: () => isAuthenticated
);

await layerman.show(
  'promotion',
  conditions: [
    // 只在首页显示
    RouteCondition(pattern: '/home'),
    // 需要认证
    AuthCondition(),
    // 自定义条件
    PredicateCondition((ctx) => user.isPremium)
  ]
);
```

### 4. **冷却系统**
```dart
await layerman.show(
  'newsletter',
  cooldown: CooldownConfig(
    session: 1,           // 本会话只显示 1 次
    daily: 1,             // 每天最多 1 次
    minGap: Duration(hours: 6)  // 最少间隔 6 小时
  )
);
```

### 5. **多框架支持**
```dart
// 使用 showDialog
final result = await layerman.show(
  'confirm',
  builder: (context) => AlertDialog(
    title: Text('Confirm'),
    content: Text('Are you sure?'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), ...),
      TextButton(onPressed: () => Navigator.pop(context, true), ...)
    ]
  )
);

// 使用 bot_toast
final result = await layerman.show(
  'toast',
  builder: (context) => BotToastWidget(message: 'Success!')
);

// 使用 GetX Dialog
final result = await layerman.show(
  'getx-dialog',
  builder: (context) => GetDialog(...)
);
```

### 6. **两阶段关闭**
```dart
await layerman.show(
  'form',
  builder: (context) => FormDialog(),
  beforeClose: (value) async {
    // 验证是否可以关闭
    if (value != null && formNeedsValidation()) {
      return false;  // 不允许关闭
    }
    return true;     // 允许关闭
  },
  afterClose: (value) async {
    // 关闭后清理资源
    await saveData(value);
  }
);
```

### 7. **异步 Resolve**
```dart
// 弹层可异步 resolve
final result = await layerman.show(
  'payment',
  builder: (context) => PaymentDialog(
    onSubmit: (data) async {
      // 后端验证
      final isValid = await api.validatePayment(data);
      // 返回结果
      return isValid ? data : null;
    }
  )
);
```

## 文件结构

```
lib/
├── src/
│   ├── layerman.dart           # Layerman 核心类
│   ├── queue/
│   │   ├─ queue_manager.dart   # 队列管理器
│   │   ├─ layer_item.dart      # 队列项
│   │   └─ priority_queue.dart  # 优先级队列
│   ├── conditions/
│   │   ├─ condition.dart       # 条件基类
│   │   ├─ route_condition.dart # 路由条件
│   │   ├─ auth_condition.dart  # 认证条件
│   │   └─ predicate_condition.dart # 自定义条件
│   ├── cooldown/
│   │   ├─ cooldown_config.dart # 冷却配置
│   │   ├─ cooldown_manager.dart # 冷却管理
│   │   └─ cooldown_storage.dart # 冷却存储
│   ├── rendering/
│   │   ├─ layer_renderer.dart  # 弹层渲染器
│   │   ├─ dialog_renderer.dart # Dialog 渲染
│   │   ├─ toast_renderer.dart  # Toast 渲染
│   │   └─ overlay_renderer.dart # Overlay 渲染
│   ├── lifecycle/
│   │   ├─ layer_lifecycle.dart # 弹层生命周期
│   │   └─ close_handler.dart   # 关闭处理
│   ├── types.dart              # 类型定义
│   └─ constants.dart           # 常量
└── layerman.dart               # 主入口
```

## 核心流程

### 初始化

```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final layerman = Layerman(
      context: context,
      routeProvider: () => currentRoute,
      authProvider: () => currentUser != null
    );

    return MaterialApp(
      home: Home(layerman: layerman)
    );
  }
}
```

### 显示弹层流程

```
用户调用 layerman.show('dialog-1', options)
    ↓
[验证阶段]
    ├─ 检查条件是否满足
    │  ├─ 路由条件 ✓
    │  ├─ 认证条件 ✓
    │  └─ 自定义条件 ✓
    └─ 条件不满足 → reject
    ↓
[冷却检查]
    ├─ 查询冷却存储
    ├─ 是否在冷却期内
    └─ 在冷却期 → 启动计时器，等待
    ↓
[优先级处理]
    ├─ 计算队列位置
    ├─ FIFO: 加入队列末尾
    ├─ Replace: 关闭当前，插队
    └─ Overlap: 保留当前，直接显示
    ↓
[排队等待]
    ├─ 如果当前有弹层显示
    ├─ 加入队列等待
    └─ 当前弹层关闭后唤醒
    ↓
[弹层显示]
    ├─ 调用 builder 创建 Widget
    ├─ 选择渲染器（Dialog/Toast/etc）
    ├─ 显示给用户
    └─ 等待用户交互
    ↓
[用户交互]
    ├─ 用户点击按钮
    ├─ 应用返回值
    └─ 触发 before-close 回调
    ↓
[Before Close]
    ├─ 调用 beforeClose 函数
    ├─ 验证是否可关闭
    ├─ 可关闭 → 继续
    └─ 不可关闭 → 留在屏幕
    ↓
[弹层关闭]
    ├─ 移除 Widget
    ├─ 触发 afterClose 回调
    └─ 清理资源
    ↓
[处理冷却]
    ├─ 记录显示时间
    ├─ 计算冷却截止时间
    └─ 存储冷却状态
    ↓
[下一项处理]
    ├─ 获取队列中的下一项
    ├─ 重复流程
    └─ 队列为空则完成
```

### 优先级队列处理

```dart
// 场景：优先级插队

// 1. 显示优先级 10 的弹层
final layer1 = LayerItem('dialog1', priority: 10);
queue.add(layer1);  // [dialog1(10)]

// 2. 显示优先级 100 的弹层
final layer2 = LayerItem('dialog2', priority: 100);
queue.add(layer2);  // 插队到前面 [dialog2(100), dialog1(10)]

// 3. 显示优先级 50 的弹层
final layer3 = LayerItem('dialog3', priority: 50);
queue.add(layer3);  // 插队到中间 [dialog2(100), dialog3(50), dialog1(10)]

// 队列处理顺序：
// dialog2 → dialog3 → dialog1
```

### 冷却状态管理

```dart
// 持久化冷却状态
// StorageManager (类似 Cacheman) 存储：
// {
//   'promotion': {
//     'sessionCount': 1,
//     'lastShowTime': 1234567890,
//     'dailyShowDates': ['2026-07-16']
//   }
// }

// 检查冷却：
bool isCoolingDown(String key, CooldownConfig config) {
  final state = storage.get(key);
  
  // 检查会话计数
  if (state['sessionCount'] >= config.session) {
    return true;
  }
  
  // 检查每日计数
  if (state['dailyShowDates'].contains(today)) {
    return true;
  }
  
  // 检查最小间隔
  if (now - state['lastShowTime'] < config.minGap) {
    return true;
  }
  
  return false;
}
```

## 与其他项目的关系

- **@codejoo/layerman** (TypeScript 版本): 类似的功能设计
- **@codejoo/storage** (Dart 版本 - cacheman): 用于存储冷却状态
- **GetX**: 可与 GetX 集成
- **bot_toast**: 可作为弹层渲染方案

## 参考

- [README.md](./README.md)
- [源代码](./lib)
- bot_toast: https://pub.dev/packages/bot_toast
