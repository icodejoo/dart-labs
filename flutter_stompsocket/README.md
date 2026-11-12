# flutter_stompsocket

[![pub](https://img.shields.io/pub/v/flutter_stompsocket.svg)](https://pub.dev/packages/flutter_stompsocket)

> 中文文档：[README.zh-CN.md](./README.zh-CN.md)

A wrapper around [`stomp_dart_client`](https://pub.dev/packages/stomp_dart_client) that adds what the library leaves out: subscription restore, offline buffering, ack handling and token refresh. The only entry class is `Stompsocket`.

> `stomp_dart_client` **reconnects the transport but does not restore subscriptions**. This wrapper re-subscribes after every (re)connect. It also parses a message once for several callbacks, gives you three ways to unsubscribe, buffers sends while offline, supports auto and manual ack, refreshes tokens, and exposes the connection state.

- [Features](#features)
- [Install](#install)
- [Quick start](#quick-start)
- [API](#api)
  - [Constructor options](#constructor-options)
  - [Lifecycle methods](#lifecycle-methods)
  - [Subscribe & unsubscribe](#subscribe--unsubscribe)
  - [Send](#send)
  - [Connection state](#connection-state)
  - [Acknowledgement (ACK/NACK)](#acknowledgement-acknack)
  - [Types & enums](#types--enums)
- [Behavior notes](#behavior-notes)

## Features

- **Shared-parse callback queue** — callbacks with the same `id` share **one** parsed payload (parsed once, then passed to all of them) and send no duplicate `SUBSCRIBE`.
- **Three ways to unsubscribe** — the handle's `.unsubscribe()` (ref-counted), `unsubscribe(id:/destination:)` and `clear()`.
- **Auto re-subscribe on reconnect** — local subscriptions are replayed after each (re)connect.
- **Offline send buffering** — `send()` while disconnected queues the message and sends it once connected.
- **Ack modes** `AckMode { auto, smart, manual }`.
- **Injectable binary decoder** — large payloads are decoded on a background isolate (`compute`).
- **Token refresh** — the async `beforeConnect` returns fresh CONNECT headers on every (re)connect.
- **Observable connection state** — `state` / `stateListenable` (a `ValueListenable`) / `onStateChanged`.
- **Foreground-resume reconnect** — with `resumeOnForeground`, an `AppLifecycleListener` reconnects when the app returns to the foreground, so a backgrounded app does not stay cut off after a lost heartbeat.
- **`copyWith`**, and all native options are passed through.

## Install

```yaml
dependencies:
  flutter_stompsocket: ^0.1.1
```

## Quick start

```dart
import 'package:flutter_stompsocket/flutter_stompsocket.dart';

final ws = Stompsocket(
  url: 'wss://example.com/ws',
  beforeConnect: () async => {'Authorization': 'Bearer ${await getToken()}'},
  onConnected: (_) => resyncSnapshot(), // fetch a fresh snapshot after any (re)connect
);

ws.activate();

final sub = ws.subscribe('/topic/quote', (json, ack) => render(json));

ws.send('/app/order', body: {'sku': 'A', 'qty': 2}); // a Map is JSON-encoded for you

sub.unsubscribe(); // cancel this callback
ws.dispose();      // reversible stop
```

## API

### Constructor options

`Stompsocket({ required String url, ... })`

#### Connection

| Option | Type | Default | Description |
|---|---|---|---|
| `url` | `String` | **required** | WebSocket URL (`ws://` or `wss://`). |
| `connectHeaders` | `Map<String,String>?` | `null` | Static CONNECT headers (auth, etc.). |
| `beforeConnect` | `Future<Map<String,String>?> Function()?` | `null` | Called before every (re)connect. A non-null return replaces the CONNECT headers, so use it for **async token refresh**. Exceptions are swallowed; a failed connect is retried by the reconnect logic. |
| `webSocketConnectHeaders` | `Map<String,dynamic>?` | `null` | HTTP headers for the WebSocket **handshake** (cookies, origin). This is a different layer from the CONNECT headers. |
| `heartbeatIncoming` | `Duration` | `5s` | Incoming heartbeat. |
| `heartbeatOutgoing` | `Duration` | `5s` | Outgoing heartbeat. |
| `pingInterval` | `Duration?` | `null` | Underlying WebSocket ping interval. |
| `connectionTimeout` | `Duration` | `Duration.zero` | Connect timeout (0 = none; set a value in production). |
| `useSockJS` | `bool` | `false` | Use SockJS transport (Spring SockJS endpoints). |

#### Reconnect

| Option | Type | Default | Description |
|---|---|---|---|
| `reconnectDelay` | `Duration` | `5s` | Fixed delay between reconnect attempts. `>0` retries forever; `Duration.zero` turns auto-reconnect off. |
| `resumeOnForeground` | `bool` | `true` | Reconnect immediately on `AppLifecycleState.resumed` if disconnected. Needs an initialized `WidgetsBinding`; set it to `false` in plain Dart without one. |

#### Parsing

| Option | Type | Default | Description |
|---|---|---|---|
| `binaryDecoder` | `ParsedMessage Function(Uint8List)?` | `null` | Decoder for binary frames. It can return any value (including null) and should throw on failure. Large payloads run through `compute` on a background isolate, so it **must be a top-level or static function**. Without it, binary messages count as parse failures. |

> Text messages go through `jsonDecode`, and any JSON value (including null) is delivered. Invalid JSON is delivered as the original text. A frame with `application/octet-stream` always uses `binaryDecoder`. Other binary bodies are first tried as strict UTF-8, and only then passed to the decoder. Large payloads use `compute` (text threshold: 32K UTF-16 code units; binary: 32KB). On Flutter Web, `compute` runs on the current event loop.

#### Send buffer

| Option | Type | Default | Description |
|---|---|---|---|
| `queueWhileDisconnected` | `bool` | `true` | Buffer outgoing messages while disconnected and flush on connect. |
| `maxQueuedMessages` | `int` | `100` | Outbox size limit. The oldest message is dropped when it is exceeded; a value ≤ 0 turns buffering off. |

#### Logging

| Option | Type | Default | Description |
|---|---|---|---|
| `debug` | `bool` | `false` | Master log switch. Nothing is logged when it is off. |
| `onLog` | `void Function(String, {Object? error, StackTrace? stackTrace})?` | `null` | Custom log sink. If omitted and `debug=true`, logs go to `dart:developer`. |

#### Callbacks

| Option | Type | Description |
|---|---|---|
| `onParseFailure` | `void Function(StompFrame, String)?` | Called when a binary message fails to parse. An exception thrown here does not change the ACK/NACK behavior. |
| `onConnected` | `void Function(StompFrame)?` | Called after each (re)connect, **after subscriptions are replayed**. A good place to re-fetch a snapshot. |
| `onDisconnected` | `void Function(StompFrame)?` | Called after a STOMP DISCONNECT. |
| `onStateChanged` | `void Function(StompConnectionState)?` | Called on every state change. |
| `onStompError` | `void Function(StompFrame)?` | Server ERROR frame (auth failure, bad destination, ...). |
| `onWebSocketError` | `void Function(dynamic)?` | WebSocket-level error. |
| `onWebSocketDone` | `void Function()?` | WebSocket closed. |
| `onDebugMessage` | `void Function(String)?` | Raw frame-level trace from the underlying library. |
| `onUnhandledFrame` / `onUnhandledMessage` / `onUnhandledReceipt` | `StompFrameCallback?` | Frames that match no subscription or receipt. |

### Lifecycle methods

| Method | Description |
|---|---|
| `void activate()` | Starts the connection (or restarts it after `dispose`). |
| `void dispose({bool keepSubscriptions = false})` | Stops the connection; you can call `activate()` again later. With `keepSubscriptions=true`, subscriptions are kept and restored on reconnect (pause/resume). |
| `void forceReconnect()` | Reconnects now, skipping `reconnectDelay`. It only acts when you want to be connected but currently are not. Call it when the network comes back. |
| `Stompsocket copyWith({ ... })` | Creates a new instance: arguments you pass override the current ones, the rest are inherited (all constructor arguments). The new instance is **fresh and not connected**, so call `activate()` yourself. |
| `bool get connected` | Whether connected. |

### Subscribe & unsubscribe

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

| Option | Description |
|---|---|
| `id` | Same id: the callback joins that subscription's queue, callbacks share one parsed payload, and no duplicate SUBSCRIBE is sent. Omitted: subscriptions with the same `(destination, ack, onParseError, ordered)` are merged. For an explicit id, the first registration fixes the destination and these options. |
| `ordered` | `true` (default) delivers strictly in arrival order, even when a large message is parsed asynchronously. `false` delivers as soon as a message is parsed: higher throughput, but messages may be reordered. Only the first subscribe of an id applies it. |
| `ack` | See [Acknowledgement](#acknowledgement-acknack). |
| `onParseError` | What to do when parsing fails: `nack` (default, the server redelivers) or `ack` (drop the message). |

Returns `StompSubscription { String id; void unsubscribe(); }`. `unsubscribe()` is ref-counted (UNSUBSCRIBE is sent only when the last callback for that id is cancelled) and safe to call twice.

```dart
int unsubscribe({String? id, String? destination}); // by id / by topic; returns how many were cancelled
void clear();                                        // cancel all
```

### Send

```dart
void send(String destination, {Object? body, Map<String,String>? headers});
```

`body` can be a `String` (sent as is), a `Map`/`List` (JSON-encoded, with `content-type: application/json`), a `Uint8List` (binary) or `null`. While disconnected, messages are buffered according to `queueWhileDisconnected`.

### Connection state

```dart
StompConnectionState get state;                             // current value
ValueListenable<StompConnectionState> get stateListenable;  // reactive
```

```dart
ValueListenableBuilder<StompConnectionState>(
  valueListenable: ws.stateListenable,
  builder: (_, state, _) => Text('$state'),
);
```

### Acknowledgement (ACK/NACK)

`AckMode` (the `ack` argument of `subscribe`):

| Value | STOMP | Behavior |
|---|---|---|
| `auto` (default) | `ack:auto` | The server acks for you; the wrapper sends **no** ACK/NACK. |
| `smart` | `ack:client-individual` | ACK is sent automatically when all callbacks succeed, NACK when any of them throws. A parse failure follows `onParseError`. |
| `manual` | `ack:client-individual` | **Delivered messages are not acked automatically.** The callback's 2nd argument is an `AckControl` for calling ack/nack yourself. |

Callback signature: `typedef JsonCallback = void Function(ParsedMessage json, AckControl ack);`. Outside `manual`, the 2nd argument does nothing; write `(json, _) {}`.

**Manual ack (can be called outside the callback)**: keep the `AckControl` and ack after the async work finishes:

```dart
final pending = <String, AckControl>{};

ws.subscribe('/queue/tasks', (json, ack) {
  pending[json['taskId']] = ack; // keep it for later
}, ack: AckMode.manual);

// elsewhere, once the async work is done:
void onTaskDone(String taskId) {
  pending.remove(taskId)?.ack();  // ack from outside
}
```

Callbacks are synchronous (`void`), so smart mode does not wait for async work; use manual mode when you need that. A message that has no body at all is skipped, and in smart/manual mode it is acked for you. A JSON null body is delivered normally. Shared manual callbacks get the same idempotent control, and the first ack/nack wins.

`dispose` keeps the buffered outgoing messages, and a later `activate` sends them. For an independent session, create a new instance. Parse results still pending when a session stops or disconnects are discarded. `copyWith` treats null as "inherit", so you cannot clear a nullable option by passing null.

An `AckControl` belongs to one session ("session generation"). **After a reconnect it is stale and does nothing.** Calling it more than once is safe.

### Types & enums

- `enum StompConnectionState { idle, connecting, connected, reconnecting, disconnected }`
- `enum AckMode { auto, smart, manual }`
- `enum ParseFailureAck { nack, ack }`
- `abstract interface class AckControl { void ack(); void nack(); }`
- `class StompSubscription { String id; void unsubscribe(); }`
- `typedef ParsedMessage = dynamic;`
- `typedef Dictional<T> = Map<String, T>;` (default `T = dynamic`)
- `typedef JsonCallback = void Function(ParsedMessage json, AckControl ack);`

## Behavior notes

- **No memory growth across reconnects**: `_subscriptions` is keyed by id and is only replayed on reconnect, not added to. The outbox has a size limit. In `manual` mode the `AckControl`s are held by your code, not by the wrapper.
- **Ordered dispatch**: `ordered:true` uses one serial chain per subscription to keep order. The cost is that a large async parse briefly blocks the messages behind it. Use `ordered:false` when order does not matter and you want the lowest latency.
- **Reconnect vs re-subscribe**: `stomp_dart_client` reconnects the transport, driven by `reconnectDelay`. The wrapper re-subscribes before `onConnected` fires. Re-fetch a snapshot in `onConnected` to fill in messages missed while the app was in the background.

## License

MIT
