# Flutter Stompsocket 架构文档

## 项目概述

**flutter_stompsocket** 是一个生产级别的 Flutter STOMP-over-WebSocket 客户端库，基于 stomp_dart_client 封装。提供共享解析回调队列、自动重新订阅、离线发送缓冲、自动/手动确认等功能。

## 核心架构

```
应用代码
    ↓
[Stompsocket 核心]
    ├─ 连接管理器
    ├─ 协议处理器
    ├─ 状态管理器
    └─ 事件系统
    ↓
[WebSocket 连接]
    ├─ 建立 WS 连接
    ├─ STOMP 握手
    └─ 心跳管理
    ↓
[消息处理]
    ├─ 共享解析队列
    ├─ Ref-counted 订阅
    ├─ 消息确认 (ACK/NACK)
    └─ 消息过滤
    ↓
[离线支持]
    ├─ 离线缓冲队列
    └─ 重连时重发
    ↓
[重连管理]
    ├─ 自动重连
    ├─ 指数退避
    ├─ 重新订阅
    └─ 前台恢复
    ↓
应用回调处理
```

## 主要特性

### 1. **STOMP 协议支持**
```dart
final stomp = Stompsocket(
  brokerURL: 'ws://localhost:15674/ws',
  login: 'guest',
  passcode: 'guest',
  heartbeatOut: 10000,
  heartbeatIn: 10000
);

await stomp.connect();
```

### 2. **连接管理**
```dart
// 监听连接状态
stomp.onConnect?.listen((_) {
  print('Connected');
});

stomp.onDisconnect?.listen((_) {
  print('Disconnected');
});

// 手动连接/断开
await stomp.connect();
await stomp.disconnect();
```

### 3. **订阅管理**
```dart
// 简单订阅
final subscription = await stomp.subscribe(
  '/topic/chat',
  onMessage: (message) {
    print('Message: ${message.body}');
  }
);

// 取消订阅
await subscription.unsubscribe();
```

### 4. **发送消息**
```dart
// 发送消息到队列
await stomp.send(
  '/queue/notifications',
  body: 'Hello',
  headers: {'custom-header': 'value'}
);

// 连接断开时自动缓冲，重连后自动发送
```

### 5. **消息确认**
```dart
// 自动确认
final subscription = await stomp.subscribe(
  '/queue/tasks',
  ack: 'auto',
  onMessage: (message) {
    // 消息自动 ACK
  }
);

// 手动确认
final subscription = await stomp.subscribe(
  '/queue/important',
  ack: 'client',
  onMessage: (message) {
    try {
      // 处理消息
      message.ack();
    } catch (e) {
      message.nack();
    }
  }
);
```

### 6. **自动重连**
```dart
final stomp = Stompsocket(
  brokerURL: 'ws://localhost:15674/ws',
  reconnectDelay: Duration(seconds: 1),
  maxReconnectAttempts: 10
);

// 连接断开时自动重连
// 重新订阅所有之前的主题
// 重发离线期间的待发送消息
```

### 7. **离线支持**
```dart
// 连接离线时消息自动缓冲
await stomp.send('/queue/email', body: 'Offline message');

// 重连后自动发送缓冲消息
// 支持配置最大缓冲大小
```

## 文件结构

```
lib/
├── src/
│   ├── stompsocket.dart        # Stompsocket 核心类
│   ├── connection/
│   │   ├─ connection_manager.dart
│   │   ├─ websocket_handler.dart
│   │   └─ heartbeat_manager.dart
│   ├── subscription/
│   │   ├─ subscription.dart    # 订阅对象
│   │   ├─ subscription_manager.dart
│   │   └─ ref_counter.dart     # Ref-counted 计数
│   ├── message/
│   │   ├─ message.dart         # STOMP 消息
│   │   └─ message_queue.dart   # 消息队列
│   ├── offline/
│   │   └─ offline_buffer.dart  # 离线缓冲
│   ├── protocol/
│   │   ├─ frame_parser.dart    # 帧解析器
│   │   ├─ frame_builder.dart   # 帧构建器
│   │   └─ protocol.dart        # STOMP 协议常量
│   ├── state/
│   │   ├─ connection_state.dart# 连接状态
│   │   └─ event_emitter.dart   # 事件发射
│   ├── types.dart              # 类型定义
│   └─ constants.dart           # 常量
└── stompsocket.dart            # 主入口
```

## 核心流程

### 初始化和连接

```dart
final stomp = Stompsocket(
  brokerURL: 'ws://localhost:15674/ws',
  login: 'guest',
  passcode: 'guest',
  heartbeatOut: 10000,
  heartbeatIn: 10000,
  onConnect: () => print('Connected'),
  onDisconnect: () => print('Disconnected'),
  onError: (error) => print('Error: $error')
);

await stomp.connect();
```

### 连接流程

```
用户调用 stomp.connect()
    ↓
[连接初始化]
    ├─ 建立 WebSocket 连接
    ├─ 连接 ws://broker/ws
    └─ 状态变为 CONNECTING
    ↓
[STOMP CONNECT 帧]
    ├─ 构建 CONNECT 帧
    ├─ 包含 login, passcode, accept-version
    └─ 发送到 Broker
    ↓
[等待 CONNECTED 响应]
    ├─ Broker 响应 CONNECTED 帧
    ├─ 解析协议版本、服务器信息
    └─ 状态变为 CONNECTED
    ↓
[恢复之前的订阅]
    ├─ 遍历订阅列表
    ├─ 为每个订阅发送 SUBSCRIBE 帧
    └─ 重新激活订阅
    ↓
[发送离线消息]
    ├─ 检查离线缓冲
    ├─ 为每条缓冲消息发送 SEND 帧
    └─ 清空缓冲区
    ↓
[触发回调]
    ├─ 调用 onConnect 回调
    └─ 通知应用连接完成
    ↓
连接就绪，可以发送/接收消息
```

### 订阅流程

```
用户调用 stomp.subscribe('/topic/chat')
    ↓
[创建订阅对象]
    ├─ 生成唯一订阅 ID
    ├─ 创建 Subscription 对象
    └─ 保存回调函数
    ↓
[检查 Ref-Count]
    ├─ 检查是否已订阅该主题
    ├─ 已订阅 → ref-count++，不发送 SUBSCRIBE 帧
    └─ 未订阅 → 发送 SUBSCRIBE 帧
    ↓
[发送 SUBSCRIBE 帧]
    ├─ 构建 SUBSCRIBE 帧
    ├─ 指定 id 和 destination
    └─ 发送到 Broker
    ↓
[接收消息]
    ├─ Broker 发送 MESSAGE 帧
    ├─ 解析帧内容
    └─ 调用订阅者回调
    ↓
[消息确认]
    ├─ 如果 ack='auto' → 自动 ACK
    ├─ 如果 ack='client' → 等待手动 ACK/NACK
    └─ 发送 ACK/NACK 帧到 Broker
```

### 去重和共享解析

```dart
// 场景：多个组件订阅同一主题

final sub1 = await stomp.subscribe('/topic/news', 
  onMessage: (msg) => widget1.update(msg)
);

final sub2 = await stomp.subscribe('/topic/news',
  onMessage: (msg) => widget2.update(msg)
);

final sub3 = await stomp.subscribe('/topic/news',
  onMessage: (msg) => widget3.update(msg)
);

// Ref-Count 管理：
// 1. sub1: ref-count = 1, 发送 SUBSCRIBE 帧
// 2. sub2: ref-count = 2, 不发送 SUBSCRIBE 帧（已订阅）
// 3. sub3: ref-count = 3, 不发送 SUBSCRIBE 帧（已订阅）

// Broker 发来消息时，一次解析，三个回调都触发
// Parser 共享，减少重复工作
```

### 重连流程

```
WebSocket 连接断开
    ↓
[检测断开]
    ├─ WebSocket onClose 事件
    ├─ 状态变为 DISCONNECTED
    └─ 清理资源
    ↓
[计算重连延迟]
    ├─ delay = min(initialDelay * 2^attempt, maxDelay)
    ├─ 例：1s, 2s, 4s, 8s, ... (指数退避)
    └─ 启动定时器
    ↓
[前台恢复检测]
    ├─ 如果应用在前台恢复
    ├─ 立即触发重连（不等待延迟）
    └─ WidgetsBindingObserver.didChangeAppLifecycleState
    ↓
[尝试重连]
    ├─ 重复连接流程
    ├─ 恢复订阅和离线消息
    └─ 失败后继续重试
    ↓
[重连成功]
    ├─ 重置延迟计数器
    ├─ 触发 onConnect 回调
    └─ 用户无感知
```

### 离线消息缓冲

```dart
// 场景：连接断开时发送消息

// 连接在线
await stomp.send('/queue/notification', body: 'Online message');

// 连接断开（网络问题）
// 消息自动进入缓冲队列
await stomp.send('/queue/notification', body: 'Offline message 1');
await stomp.send('/queue/notification', body: 'Offline message 2');

// 消息在缓冲中，等待重连

// 重连成功后
// 缓冲消息自动发送
// 应用无需干预

// 可配置最大缓冲大小，防止内存溢出
```

## 与其他项目的关系

- **@codejoo/stomp** (TypeScript 版本): 类似的功能设计
- **其他 Dart-Labs 子包**: 可作为实时通信基础

## 参考

- [README.md](./README.md)
- [源代码](./lib)
- stomp_dart_client: https://pub.dev/packages/stomp_dart_client
