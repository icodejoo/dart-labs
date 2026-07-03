# flutter_stompsocket

> English: [README.md](./README.md)

[![pub](https://img.shields.io/pub/v/flutter_stompsocket.svg)](https://pub.dev/packages/flutter_stompsocket)

对 [`stomp_dart_client`](https://pub.dev/packages/stomp_dart_client) 的**生产级二次封装**，补齐它不提供的“产品层”能力。核心是一个类 `Stompsocket`。

> 关键认知：底层库**只重连传输、不恢复订阅**。本封装在连接建立后自动重放本地订阅，并在此之上提供函数队列共享解析、三种取消、离线发送缓冲、自动/手动确认、token 刷新、连接状态可观测等能力。

- [特性](#特性)
- [安装](#安装)
- [快速上手](#快速上手)
- [API 详解](#api-详解)
  - [构造函数参数](#构造函数参数)
  - [生命周期方法](#生命周期方法)
  - [订阅与取消](#订阅与取消)
  - [发送](#发送)
  - [连接状态观测](#连接状态观测)
  - [确认（ACK/NACK）](#确认acknack)
  - [枚举与类型](#枚举与类型)
- [行为与语义说明](#行为与语义说明)

## 特性

- **函数队列共享解析**：相同 `id` 的多个回调共用**一份**解析后的数据（只解析一次再分发），不重复向服务端 SUBSCRIBE。
- **三种取消**：句柄 `.unsubscribe()`（引用计数）、`unsubscribe(id:/destination:)`、`clear()`。
- **断线后自动重新订阅**：连接建立/重连后自动重放本地订阅。
- **离线发送缓冲**：未连接时 `send()` 入缓冲，连上后按序补发。
- **确认模式** `AckMode { auto, smart, manual }`。
- **可注入二进制解码器**：大包自动走后台 isolate（`compute`）。
- **token 刷新**：`beforeConnect` 每次（重）连前返回新的 CONNECT 头。
- **连接状态可观测**：`state` / `stateListenable`（`ValueListenable`）/ `onStateChanged`。
- **回前台强制重连**：`resumeOnForeground` 借 `AppLifecycleListener` 规避 App 后台挂起导致的心跳失联。
- **`copyWith`** 与底层原生参数透传。

## 安装

```yaml
dependencies:
  flutter_stompsocket: ^0.1.0
```

## 快速上手

```dart
import 'package:flutter_stompsocket/flutter_stompsocket.dart';

final ws = Stompsocket(
  url: 'wss://example.com/ws',
  beforeConnect: () async => {'Authorization': 'Bearer ${await getToken()}'},
  onConnected: (_) => resyncSnapshot(), // 每次（重）连成功后重拉快照
);

ws.activate();

final sub = ws.subscribe('/topic/quote', (json, ack) => render(json));

ws.send('/app/order', body: {'sku': 'A', 'qty': 2}); // Map 自动 JSON 编码

sub.unsubscribe(); // 取消这一次回调
ws.dispose();      // 可逆停止
```

## API 详解

### 构造函数参数

`Stompsocket({ required String url, ... })`

#### 连接

| 参数 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `url` | `String` | **必填** | WebSocket 地址（`ws://` 或 `wss://`）。 |
| `connectHeaders` | `Map<String,String>?` | `null` | 静态 CONNECT 头（鉴权等）。 |
| `beforeConnect` | `Future<Map<String,String>?> Function()?` | `null` | 每次（重）连前调用；返回非空则覆盖 CONNECT 头，用于**异步 token 刷新**。内部吞异常，失败由重连兜底。 |
| `webSocketConnectHeaders` | `Map<String,dynamic>?` | `null` | WebSocket **握手**阶段的 HTTP 头（Cookie/Origin 等，与 CONNECT 头是两层）。 |
| `heartbeatIncoming` | `Duration` | `5s` | 入向心跳。 |
| `heartbeatOutgoing` | `Duration` | `5s` | 出向心跳。 |
| `pingInterval` | `Duration?` | `null` | 底层 WebSocket ping 间隔。 |
| `connectionTimeout` | `Duration` | `Duration.zero` | 连接超时（0=不超时；生产建议设值）。 |
| `useSockJS` | `bool` | `false` | 使用 SockJS 传输（Spring SockJS 端点）。 |

#### 重连

| 参数 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `reconnectDelay` | `Duration` | `5s` | 固定间隔自动重连；`>0` 无限重试，`Duration.zero` 关闭自动重连。 |
| `resumeOnForeground` | `bool` | `false` | 为 true 时，App 回前台（`AppLifecycleState.resumed`）若未连接则立即重连（需已初始化 `WidgetsBinding`）。 |

#### 消息解析

| 参数 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `binaryDecoder` | `Dictional? Function(Uint8List)?` | `null` | 二进制帧解码器；返回 Map，失败请抛异常。大包经 `compute` 到后台 isolate，故**必须是顶层/静态函数**。未提供时二进制消息按解析失败处理。 |

> 文本消息默认 `jsonDecode`；负载 > 32KB 自动走后台 isolate 解析。

#### 发送缓冲

| 参数 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `queueWhileDisconnected` | `bool` | `true` | 未连接时是否缓冲出站消息，连上后按序补发。 |
| `maxQueuedMessages` | `int` | `100` | 出站缓冲上限，超出丢最旧。 |

#### 日志

| 参数 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `debug` | `bool` | `false` | 日志主开关；关闭时完全静默。 |
| `onLog` | `void Function(String, {Object? error, StackTrace? stackTrace})?` | `null` | 自定义日志输出；未提供且 `debug=true` 时回退 `dart:developer`。 |

#### 回调

| 参数 | 类型 | 说明 |
|---|---|---|
| `onConnected` | `void Function(StompFrame)?` | 每次（重）连成功、**重放订阅之后**触发（重拉快照的好时机）。 |
| `onDisconnected` | `void Function(StompFrame)?` | STOMP DISCONNECT 后触发。 |
| `onStateChanged` | `void Function(StompConnectionState)?` | 连接状态每次变化触发。 |
| `onStompError` | `void Function(StompFrame)?` | 服务端 ERROR 帧（鉴权失败、目的地非法等）。 |
| `onWebSocketError` | `void Function(dynamic)?` | WebSocket 层错误。 |
| `onWebSocketDone` | `void Function()?` | WebSocket 关闭。 |
| `onDebugMessage` | `void Function(String)?` | 原样透传底层帧级流水。 |
| `onUnhandledFrame` / `onUnhandledMessage` / `onUnhandledReceipt` | `StompFrameCallback?` | 未匹配任何订阅/回执的帧。 |

### 生命周期方法

| 方法 | 说明 |
|---|---|
| `void activate()` | 启动（或 dispose 后重启）连接。 |
| `void dispose({bool keepSubscriptions = false})` | 可逆停止；dispose 后仍可再次 `activate`。`keepSubscriptions=true` 保留订阅，重连后自动恢复（pause/resume）。 |
| `void forceReconnect()` | 立即重连（跳过 `reconnectDelay`），仅在“期望连接但当前未连接”时生效。可在网络恢复时手动调。 |
| `Stompsocket copyWith({ ... })` | 复制新实例：提供的参数覆盖、未提供的继承（全部构造参数）。返回**全新未连接**实例，需自行 `activate`。 |
| `bool get connected` | 是否已连接。 |

### 订阅与取消

```dart
StompSubscription subscribe(
  String destination,
  JsonCallback callback, {
  String? id,
  bool ordered = true,
  AckMode ack = AckMode.auto,
  ParseFailureAck onParseError = ParseFailureAck.nack,
});
```

| 参数 | 说明 |
|---|---|
| `id` | 传相同 id → 回调加入同一订阅队列，多回调共用一份解析数据、不重复 SUBSCRIBE；不传 → 自动生成独立订阅。 |
| `ordered` | `true`（默认）严格按到达顺序分发（即使大包异步解析也不乱序）；`false` 解析完即分发，吞吐更高但可能乱序。仅首次订阅该 id 时生效。 |
| `ack` | 见[确认](#确认acknack)。 |
| `onParseError` | 解析失败时 `nack`（默认，重投）或 `ack`（丢弃）。 |

返回 `StompSubscription { String id; void unsubscribe(); }`——`unsubscribe()` 引用计数取消（该 id 最后一个回调取消时才 UNSUBSCRIBE），幂等。

```dart
int unsubscribe({String? id, String? destination}); // 按 id 单个 / 按 topic 批量，返回取消数
void clear();                                        // 取消全部
```

### 发送

```dart
void send(String destination, {Object? body, Map<String,String>? headers});
```

`body` 支持 `String`（原样）、`Map`/`List`（自动 JSON 编码 + `content-type: application/json`）、`Uint8List`（二进制）、`null`（无 body）。未连接时按 `queueWhileDisconnected` 缓冲。

### 连接状态观测

```dart
StompConnectionState get state;                             // 当前值
ValueListenable<StompConnectionState> get stateListenable;  // 响应式
```

```dart
ValueListenableBuilder<StompConnectionState>(
  valueListenable: ws.stateListenable,
  builder: (_, state, _) => Text('$state'),
);
```

### 确认（ACK/NACK）

`AckMode`（`subscribe` 的 `ack` 参数）：

| 值 | STOMP | 行为 |
|---|---|---|
| `auto`（默认） | `ack:auto` | 服务端自动确认，本封装**不发**任何 ACK/NACK。 |
| `smart` | `ack:client-individual` | 按处理结果**自动** ACK（回调全成功）/ NACK（任一抛异常）。解析失败按 `onParseError`。 |
| `manual` | `ack:client-individual` | **不自动应答**，回调第二参给 `AckControl` 手动 ack/nack。 |

回调签名：`typedef JsonCallback = void Function(Dictional json, AckControl ack);`（第二参在非 manual 下为 no-op，可写 `(json, _) {}`）。

**手动确认（可在回调外调用）**：`AckControl` 可存起来，异步完成后再 ack：

```dart
final pending = <String, AckControl>{};

ws.subscribe('/queue/tasks', (json, ack) {
  pending[json['taskId']] = ack; // 存起来
}, ack: AckMode.manual);

// 别处、异步完成后：
void onTaskDone(String taskId) {
  pending.remove(taskId)?.ack();  // 外部 ack
}
```

`AckControl` 绑定“会话代次”，**重连后旧句柄自动失效（no-op）**，重复调用幂等。

### 枚举与类型

- `enum StompConnectionState { idle, connecting, connected, reconnecting, disconnected }`
- `enum AckMode { auto, smart, manual }`
- `enum ParseFailureAck { nack, ack }`
- `abstract interface class AckControl { void ack(); void nack(); }`
- `class StompSubscription { String id; void unsubscribe(); }`
- `typedef Dictional<T> = Map<String, T>;`（默认 `T = dynamic`）
- `typedef JsonCallback = void Function(Dictional json, AckControl ack);`

## 行为与语义说明

- **重连不会内存膨胀**：`_subscriptions` 以 id 为键，重连只重放不新增；出站缓冲有上限；manual 的 `AckControl` 由调用方持有、本封装不留存。
- **有序分发**：`ordered:true` 用每订阅一条串行链保证顺序，代价是大包异步解析会短暂阻塞其后消息；顺序无关且要低延迟时用 `ordered:false`。
- **重连 vs 重订阅**：传输重连由 `reconnectDelay` 交给底层库；重连后重新订阅由本封装完成，并在 `onConnected` 前就绪。业务可在 `onConnected` 里重拉快照补齐后台期间遗漏。

## License

MIT
