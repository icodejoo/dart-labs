# Flutter Stompsocket 架构文档

本包封装 `stomp_dart_client`，入口为 `lib/flutter_stompsocket.dart`。
本文按当前代码、README 和测试校准；旧稿中的 `brokerURL`、`connect()`、
指数退避、重试次数上限和 `lib/src/` 拆分目录均非现有 API，不据此新增功能。

## 已定约束

- 保持单文件核心和现有命名风格，公开方法保持同步。
- 传输、握手、心跳及固定间隔自动重连交给 `stomp_dart_client`。
  `reconnectDelay > Duration.zero` 无限重试，零值关闭自动重连。
- 本封装负责连接成功后恢复本地订阅，再补发离线消息，最后通知 `onConnected`。
- 同一订阅只解析一次，回调共享同一份结果；取消句柄按注册对象身份引用计数。
- 不传 id 时，按 `(destination, ack, onParseError, ordered)` 生成确定性归并键。
  自动键使用 `\x1f`，不能使用 STOMP 帧终止符 NUL。
  显式 id 直接用作键，首次注册确定目的地和选项；调用方不要复用自动键作为显式 id。
- 默认按单个订阅的到达顺序分发；可用 `ordered:false` 选择解析完成即分发。
- `dispose` 是可逆停止，允许再次 `activate`，因此状态通知器不能在停止时销毁。

## 文件结构

```text
lib/flutter_stompsocket.dart       核心、类型、句柄、解析和确认
test/flutter_stompsocket_test.dart 原有行为集成测试
test/review_regression_test.dart   边界与竞态回归测试
test/stomp_test_broker.dart        本地 WebSocket/STOMP 测试服务
example/                          Flutter 示例
README.md / README.zh-CN.md        双语 API 契约
```

## 生命周期与状态

```dart
final ws = Stompsocket(
  url: 'ws://localhost:15674/ws',
  connectHeaders: {'login': 'guest', 'passcode': 'guest'},
  beforeConnect: () async => {'Authorization': 'Bearer token'},
  onConnected: (_) { /* 重拉业务快照 */ },
);
ws.activate();
```

`state` 为同步快照，`stateListenable` 为 Flutter 原生 `ValueListenable`，
`onStateChanged` 便于命令式桥接。同值不重复通知。监听者可同步停止实例，
停止后不得继续启动传输或报告过期的连接成功事件。重复启动活动连接为无操作。

状态流：首次启动 `idle → connecting → connected`；传输关闭后，启用重连时
进入 `reconnecting`，否则进入 `disconnected`。停止进入 `disconnected`，
再次启动进入 `connecting`。关闭自动重连时，首次连接失败也进入 `disconnected`。

`beforeConnect` 每次连接前异步刷新 CONNECT 头；返回非 null 替换全部头，
返回 null 或抛异常则保留已有头，异常记日志。它不是取消连接的钩子。
停止期间未完成的准备结果不得覆盖新尝试的头；再次启动先等待旧准备退出底层流程，
避免旧流程在底层重新 active 后建立第二条连接。

`resumeOnForeground` 默认 true，通过 `AppLifecycleListener` 在回前台时调用
`forceReconnect()`。只有期望连接且当前未连接时生效，跳过重连等待；需要已初始化
WidgetsBinding，纯 Dart 场景应设为 false。

`dispose(keepSubscriptions:false)` 默认清空订阅和回调；true 保留登记供重启恢复。
两者均保留出站缓冲。实例中会话代次使停止、断线前的解析结果和旧 ACK 句柄失效。
重新连接会重置订阅解析链，避免新会话被旧大包阻塞。

## 订阅与解析

```dart
final subscription = ws.subscribe('/topic/chat', (value, ack) {
  // value 可以是任意 JSON 值，也可以是非 JSON 的原始文本。
});
subscription.unsubscribe(); // 仅移除本次注册；最后一个取消才发 UNSUBSCRIBE
ws.unsubscribe(destination: '/topic/chat'); // 按目的地批量取消
ws.clear(); // 取消全部
```

相同自动归并键或显式 id 的回调共用一条 wire 订阅。重复取消安全，旧句柄不能
取消同 id 重建后的新订阅。离线取消只修改本地登记，不向失效连接发帧。

文本 JSON 解码成功就交付实际值（含 null、数组、标量）；解码异常则交付原始文本。
显式 `application/octet-stream` 走注入的 `binaryDecoder`，其余二进制 body
先严格探测 UTF-8：成功按文本处理，失败走二进制解码器。缺少解码器或解码异常才是
解析失败。真正没有 body 的消息不调用订阅回调。

小包同步解析，大包使用 `compute`。文本阈值为 32K UTF-16 代码单元，二进制阈值为
32KB。原生平台每次 compute 新建 isolate，只适合偶发大包；Web 在当前事件循环运行。
大包二进制解码器需为可发送到 isolate 的顶层或静态函数。

`ordered:true` 将解析追加到每个订阅的 Future 链，异常不应破坏后续链。
`ordered:false` 允许小包先于大包交付。停止或会话变化后均丢弃旧解析结果，
不再触发业务回调、解析失败监控或 ACK/NACK。

## ACK/NACK

| 模式 | 订阅头 | 应答责任 |
|---|---|---|
| auto | 不带 ack（服务端默认 auto） | 本封装不发送 ACK/NACK |
| smart | client-individual | 同步回调全成功 ACK，任一抛异常 NACK |
| manual | client-individual | 回调通过 AckControl 应答，可在回调外调用 |

smart/manual 解析失败按 `ParseFailureAck` 自动应答，默认 NACK；
真正无 body 时自动 ACK。合法 JSON null 必须交给回调，manual 不擅自确认。
`onParseFailure` 用于监控，监控异常不改变确认策略。

确认 id 优先取 MESSAGE 的 `ack`，回退 `message-id`（沿用底层兼容策略）。
句柄绑定会话代次，只在当前连接有效且幂等。共享 manual 回调拿到同一个句柄，
首次 ack/nack 生效。非 manual 回调得到 no-op 句柄。

`JsonCallback` 是同步 void 回调，smart 不等待异步业务；异步任务须选择 manual，
完成后再确认。NACK 的重投和死信上限由 broker 决定。

## 离线发送

```dart
ws.send('/queue/notification', body: {'text': 'Hello'});
```

字符串原样发送，Map/List 等对象 JSON 编码并补默认 `application/json`（允许头覆盖），
Uint8List 发送二进制，null 不带 body。离线时按 `queueWhileDisconnected` 缓冲，
容量默认 100，超限丢最旧；容量 ≤0 不缓冲。连接后按序补发，发送异常时将未发送部分
退回缓冲并遵守容量上限，下次连接再尝试。缓冲不提供服务端送达保证。

## 配置复制与观测

`copyWith` 继承未提供的构造参数，返回未连接的新实例，不复制订阅、缓冲或状态。
null 表示继承，因此不能用 null 清空可空配置。
`debug` 控制库日志，`onLog` 可接管输出；`onDebugMessage` 独立透传底层流水。
业务应在 `onConnected` 重拉快照，补齐断线期间未收到的消息。

## 验证

运行 `flutter analyze` 和 `flutter test`。测试服务只覆盖本封装用到的 STOMP 子集，
不替代真实 broker 的心跳、重投、鉴权及 SockJS 兼容验证。
