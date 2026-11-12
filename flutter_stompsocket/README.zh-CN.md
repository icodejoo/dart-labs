# flutter_stompsocket

> English: [README.md](./README.md)

[![pub](https://img.shields.io/pub/v/flutter_stompsocket.svg)](https://pub.dev/packages/flutter_stompsocket)

在 [`stomp_dart_client`](https://pub.dev/packages/stomp_dart_client) 外面包了一层，补上它缺的几块：恢复订阅、离线缓冲、消息确认和 token 刷新。入口只有一个类 `Stompsocket`。

> `stomp_dart_client` **只负责重连传输，不会恢复订阅**。这个封装会在每次（重）连之后自动重新订阅。另外，同一条消息只解析一次就能分给多个回调，有三种取消订阅的方式，离线时发送的消息会先缓存，确认可以自动也可以手动，支持刷新 token，还能观察连接状态。

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

- **函数队列共享解析**：相同 `id` 的多个回调共用**一份**解析结果（只解析一次，再分给每个回调），也不会重复发 `SUBSCRIBE`。
- **三种取消**：句柄的 `.unsubscribe()`（引用计数）、`unsubscribe(id:/destination:)`、`clear()`。
- **断线后自动重新订阅**：每次（重）连成功后，重放本地订阅。
- **离线发送缓冲**：未连接时 `send()` 先把消息存起来，连上后按顺序发出。
- **确认模式**：`AckMode { auto, smart, manual }`。
- **可注入二进制解码器**：大包放到后台 isolate（`compute`）里解码。
- **token 刷新**：每次（重）连前，`beforeConnect` 返回新的 CONNECT 头。
- **连接状态可观测**：`state` / `stateListenable`（`ValueListenable`）/ `onStateChanged`。
- **回前台强制重连**：开启 `resumeOnForeground` 后，用 `AppLifecycleListener` 在 App 回到前台时重连，避免 App 在后台被挂起、心跳断了就一直连不上。
- **`copyWith`**，底层库的原生参数也都能传。

## 安装

```yaml
dependencies:
  flutter_stompsocket: ^0.1.1
```

## 快速上手

```dart
import 'package:flutter_stompsocket/flutter_stompsocket.dart';

final ws = Stompsocket(
  url: 'wss://example.com/ws',
  beforeConnect: () async => {'Authorization': 'Bearer ${await getToken()}'},
  onConnected: (_) => resyncSnapshot(), // 每次（重）连成功后重新拉一份快照
);

ws.activate();

final sub = ws.subscribe('/topic/quote', (json, ack) => render(json));

ws.send('/app/order', body: {'sku': 'A', 'qty': 2}); // Map 会自动编码成 JSON

sub.unsubscribe(); // 取消这个回调
ws.dispose();      // 停止连接，之后还能再 activate
```

## API 详解

### 构造函数参数

`Stompsocket({ required String url, ... })`

#### 连接

| 参数 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `url` | `String` | **必填** | WebSocket 地址（`ws://` 或 `wss://`）。 |
| `connectHeaders` | `Map<String,String>?` | `null` | 静态 CONNECT 头（鉴权等）。 |
| `beforeConnect` | `Future<Map<String,String>?> Function()?` | `null` | 每次（重）连前调用。返回非空就替换 CONNECT 头，用来**异步刷新 token**。异常会被吞掉；这次连接失败了，由重连逻辑重试。 |
| `webSocketConnectHeaders` | `Map<String,dynamic>?` | `null` | WebSocket **握手**时带的 HTTP 头（Cookie、Origin 等），和 CONNECT 头不是一层。 |
| `heartbeatIncoming` | `Duration` | `5s` | 接收心跳间隔。 |
| `heartbeatOutgoing` | `Duration` | `5s` | 发送心跳间隔。 |
| `pingInterval` | `Duration?` | `null` | 底层 WebSocket ping 间隔。 |
| `connectionTimeout` | `Duration` | `Duration.zero` | 连接超时（0 表示不超时；生产环境建议设一个值）。 |
| `useSockJS` | `bool` | `false` | 使用 SockJS 传输（Spring SockJS 端点）。 |

#### 重连

| 参数 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `reconnectDelay` | `Duration` | `5s` | 两次重连之间的固定间隔。`>0` 会一直重试，`Duration.zero` 关闭自动重连。 |
| `resumeOnForeground` | `bool` | `true` | App 回到前台（`AppLifecycleState.resumed`）时，如果没连上就立即重连。需要已初始化 `WidgetsBinding`；在没有它的纯 Dart 环境里请设为 `false`。 |

#### 消息解析

| 参数 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `binaryDecoder` | `ParsedMessage Function(Uint8List)?` | `null` | 二进制帧的解码器。可以返回任意值（包括 null），解码失败就抛异常。大包会经 `compute` 放到后台 isolate，所以它**必须是顶层函数或静态方法**。不传的话，二进制消息一律算解析失败。 |

> 文本消息用 `jsonDecode` 解析，任何 JSON 值（包括 null）都会交给回调；不是合法 JSON 的，原样把文本交给回调。显式标了 `application/octet-stream` 的帧，直接用 `binaryDecoder`；其他二进制 body 先按严格 UTF-8 试一遍，不行才交给解码器。大包用 `compute`（文本超过 32K 个 UTF-16 代码单元、二进制超过 32KB 时）。Flutter Web 上 `compute` 仍然在当前事件循环里执行。

#### 发送缓冲

| 参数 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `queueWhileDisconnected` | `bool` | `true` | 未连接时是否缓存要发的消息，连上后按顺序发出。 |
| `maxQueuedMessages` | `int` | `100` | 发送缓冲的上限，超出就丢掉最旧的；≤0 表示不缓冲。 |

#### 日志

| 参数 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `debug` | `bool` | `false` | 日志总开关；关掉后什么都不输出。 |
| `onLog` | `void Function(String, {Object? error, StackTrace? stackTrace})?` | `null` | 自定义日志输出。没传且 `debug=true` 时，日志走 `dart:developer`。 |

#### 回调

| 参数 | 类型 | 说明 |
|---|---|---|
| `onParseFailure` | `void Function(StompFrame, String)?` | 二进制消息解析失败时调用。这里抛异常不影响 ACK/NACK 的处理。 |
| `onConnected` | `void Function(StompFrame)?` | 每次（重）连成功后调用，**此时订阅已经重放完**。适合在这里重新拉快照。 |
| `onDisconnected` | `void Function(StompFrame)?` | STOMP DISCONNECT 之后调用。 |
| `onStateChanged` | `void Function(StompConnectionState)?` | 连接状态每次变化都会调用。 |
| `onStompError` | `void Function(StompFrame)?` | 服务端 ERROR 帧（鉴权失败、目的地非法等）。 |
| `onWebSocketError` | `void Function(dynamic)?` | WebSocket 层错误。 |
| `onWebSocketDone` | `void Function()?` | WebSocket 关闭。 |
| `onDebugMessage` | `void Function(String)?` | 底层库的原始帧级日志。 |
| `onUnhandledFrame` / `onUnhandledMessage` / `onUnhandledReceipt` | `StompFrameCallback?` | 没有匹配到任何订阅或回执的帧。 |

### 生命周期方法

| 方法 | 说明 |
|---|---|
| `void activate()` | 启动连接（或在 `dispose` 之后重新启动）。 |
| `void dispose({bool keepSubscriptions = false})` | 停止连接，之后还能再 `activate`。`keepSubscriptions=true` 会保留订阅，重连后自动恢复（用于暂停/恢复）。 |
| `void forceReconnect()` | 立即重连，不等 `reconnectDelay`。只在“想连着、但现在没连上”时才起作用。网络恢复时可以手动调用。 |
| `Stompsocket copyWith({ ... })` | 复制出一个新实例：传了的参数覆盖原值，没传的沿用（所有构造参数都适用）。新实例是**全新的、未连接**的，需要自己调用 `activate()`。 |
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
| `id` | 传相同的 id：回调加入同一个订阅队列，共用一份解析结果，不重复发 SUBSCRIBE。不传：`(destination, ack, onParseError, ordered)` 都相同的订阅会合并。显式 id 的目的地和这些选项，以第一次注册为准。 |
| `ordered` | `true`（默认）严格按到达顺序分发，大包异步解析时也不会乱序。`false` 解析完就分发：吞吐更高，但可能乱序。只在这个 id 第一次订阅时生效。 |
| `ack` | 见[确认](#确认acknack)。 |
| `onParseError` | 解析失败时怎么处理：`nack`（默认，服务端会重发）或 `ack`（丢掉这条消息）。 |

返回 `StompSubscription { String id; void unsubscribe(); }`。`unsubscribe()` 按引用计数取消（这个 id 的最后一个回调取消时，才发 UNSUBSCRIBE），重复调用也没问题。

```dart
int unsubscribe({String? id, String? destination}); // 按 id 取消一个 / 按 topic 批量取消，返回取消的数量
void clear();                                        // 取消全部
```

### 发送

```dart
void send(String destination, {Object? body, Map<String,String>? headers});
```

`body` 可以是 `String`（原样发送）、`Map`/`List`（自动编码成 JSON，并加上 `content-type: application/json`）、`Uint8List`（二进制）或 `null`（没有 body）。未连接时，按 `queueWhileDisconnected` 决定是否缓存。

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
| `auto`（默认） | `ack:auto` | 服务端自动确认，封装**不会**发任何 ACK/NACK。 |
| `smart` | `ack:client-individual` | 所有回调都成功就自动发 ACK，任何一个抛异常就发 NACK。解析失败按 `onParseError` 处理。 |
| `manual` | `ack:client-individual` | **成功投递的消息不会自动确认**，回调的第二个参数是 `AckControl`，由你自己调用 ack/nack。 |

回调签名：`typedef JsonCallback = void Function(ParsedMessage json, AckControl ack);`。不是 `manual` 时，第二个参数什么都不做，可以写 `(json, _) {}`。

**手动确认（可以在回调外调用）**：把 `AckControl` 存起来，等异步处理完再 ack：

```dart
final pending = <String, AckControl>{};

ws.subscribe('/queue/tasks', (json, ack) {
  pending[json['taskId']] = ack; // 先存起来
}, ack: AckMode.manual);

// 在别处，异步处理完成后：
void onTaskDone(String taskId) {
  pending.remove(taskId)?.ack();  // 外部 ack
}
```

回调是同步的 `void`，smart 模式不会等异步任务；需要异步处理就用 manual。完全没有 body 的消息会跳过回调，并在 smart/manual 模式下自动确认；body 是 JSON null 的消息会正常投递给回调。共享订阅里的 manual 回调拿到的是同一个句柄，重复调用没有副作用，以第一次 ack/nack 为准。

`dispose` 会保留还没发出的离线消息，下次 `activate` 时补发。想要一个独立的会话，就新建实例。会话停止或断开时还没解析完的消息，结果会被丢弃。`copyWith` 里 null 表示沿用原值，所以不能用 null 把可空参数清掉。

`AckControl` 属于某一次会话（“会话代次”）。**重连之后，旧的句柄失效，调用不会有任何效果**；重复调用也没问题。

### 枚举与类型

- `enum StompConnectionState { idle, connecting, connected, reconnecting, disconnected }`
- `enum AckMode { auto, smart, manual }`
- `enum ParseFailureAck { nack, ack }`
- `abstract interface class AckControl { void ack(); void nack(); }`
- `class StompSubscription { String id; void unsubscribe(); }`
- `typedef ParsedMessage = dynamic;`
- `typedef Dictional<T> = Map<String, T>;`（默认 `T = dynamic`）
- `typedef JsonCallback = void Function(ParsedMessage json, AckControl ack);`

## 行为与语义说明

- **重连不会让内存越涨越多**：`_subscriptions` 以 id 为键，重连时只重放，不新增；发送缓冲有上限；`manual` 的 `AckControl` 由调用方持有，封装自己不保留。
- **有序分发**：`ordered:true` 给每个订阅用一条串行链来保证顺序。代价是大包异步解析时，会让排在后面的消息稍微等一会儿。顺序无所谓、又要低延迟时，用 `ordered:false`。
- **重连和重新订阅**：传输层重连由底层库按 `reconnectDelay` 负责；重新订阅由本封装完成，并且在 `onConnected` 触发之前就绪。可以在 `onConnected` 里重新拉快照，补上 App 在后台时漏掉的消息。

## License

MIT
