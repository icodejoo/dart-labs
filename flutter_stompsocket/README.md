# flutter_stompsocket

[![pub](https://img.shields.io/pub/v/flutter_stompsocket.svg)](https://pub.dev/packages/flutter_stompsocket)

> 中文文档：[README.zh-CN.md](./README.zh-CN.md)

A **production-ready** wrapper over [`stomp_dart_client`](https://pub.dev/packages/stomp_dart_client) that adds the "product" layer it doesn't provide. The single entry class is `Stompsocket`.

> Key insight: the underlying library **reconnects the transport but does not restore subscriptions**. This wrapper re-subscribes automatically after each (re)connect, and adds shared-parse callback queues, three ways to unsubscribe, offline send buffering, auto/manual ack, token refresh, and observable connection state.

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

- **Shared-parse callback queue** — multiple callbacks under the same `id` share **one** parsed payload (parsed once, dispatched to all); no duplicate `SUBSCRIBE`.
- **Three ways to unsubscribe** — the handle's `.unsubscribe()` (ref-counted), `unsubscribe(id:/destination:)`, and `clear()`.
- **Auto re-subscribe on reconnect** — replays local subscriptions once (re)connected.
- **Offline send buffering** — `send()` while disconnected buffers and flushes on connect.
- **Ack modes** `AckMode { auto, smart, manual }`.
- **Injectable binary decoder** — large payloads run on a background isolate (`compute`).
- **Token refresh** — async `beforeConnect` returns fresh CONNECT headers on every (re)connect.
- **Observable connection state** — `state` / `stateListenable` (a `ValueListenable`) / `onStateChanged`.
- **Foreground-resume reconnect** — `resumeOnForeground` uses `AppLifecycleListener` to sidestep heartbeat loss after the app is backgrounded.
- **`copyWith`** and full passthrough of native options.

## Install

```yaml
dependencies:
  flutter_stompsocket: ^0.1.0
```

## Quick start

```dart
import 'package:flutter_stompsocket/flutter_stompsocket.dart';

final ws = Stompsocket(
  url: 'wss://example.com/ws',
  beforeConnect: () async => {'Authorization': 'Bearer ${await getToken()}'},
  onConnected: (_) => resyncSnapshot(), // re-fetch a snapshot after any (re)connect
);

ws.activate();

final sub = ws.subscribe('/topic/quote', (json, ack) => render(json));

ws.send('/app/order', body: {'sku': 'A', 'qty': 2}); // Map is auto JSON-encoded

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
| `beforeConnect` | `Future<Map<String,String>?> Function()?` | `null` | Called before every (re)connect; a non-null return overrides CONNECT headers — use for **async token refresh**. Exceptions are swallowed (a failed connect is covered by reconnect). |
| `webSocketConnectHeaders` | `Map<String,dynamic>?` | `null` | HTTP headers for the WebSocket **handshake** (cookies/origin — a different layer than CONNECT headers). |
| `heartbeatIncoming` | `Duration` | `5s` | Incoming heartbeat. |
| `heartbeatOutgoing` | `Duration` | `5s` | Outgoing heartbeat. |
| `pingInterval` | `Duration?` | `null` | Underlying WebSocket ping interval. |
| `connectionTimeout` | `Duration` | `Duration.zero` | Connect timeout (0 = none; set a value in production). |
| `useSockJS` | `bool` | `false` | Use SockJS transport (Spring SockJS endpoints). |

#### Reconnect

| Option | Type | Default | Description |
|---|---|---|---|
| `reconnectDelay` | `Duration` | `5s` | Fixed-interval auto-reconnect; `>0` retries forever, `Duration.zero` disables it. |
| `resumeOnForeground` | `bool` | `true` | When true, reconnect immediately on `AppLifecycleState.resumed` if disconnected (requires an initialized `WidgetsBinding`; set to `false` for plain-Dart contexts without one). |

#### Parsing

| Option | Type | Default | Description |
|---|---|---|---|
| `binaryDecoder` | `Dictional? Function(Uint8List)?` | `null` | Decoder for binary frames; return a Map, throw on failure. Large payloads run via `compute` on a background isolate, so it **must be a top-level/static function**. If omitted, binary messages are treated as parse failures. |

> Text messages use `jsonDecode`; payloads > 32KB are parsed on a background isolate.

#### Send buffer

| Option | Type | Default | Description |
|---|---|---|---|
| `queueWhileDisconnected` | `bool` | `true` | Buffer outgoing messages while disconnected and flush on connect. |
| `maxQueuedMessages` | `int` | `100` | Outbox cap; oldest dropped when exceeded. |

#### Logging

| Option | Type | Default | Description |
|---|---|---|---|
| `debug` | `bool` | `false` | Master log switch; fully silent when off. |
| `onLog` | `void Function(String, {Object? error, StackTrace? stackTrace})?` | `null` | Custom log sink; falls back to `dart:developer` when omitted and `debug=true`. |

#### Callbacks

| Option | Type | Description |
|---|---|---|
| `onConnected` | `void Function(StompFrame)?` | Fired after each (re)connect, **after subscriptions are replayed** (good place to re-fetch a snapshot). |
| `onDisconnected` | `void Function(StompFrame)?` | Fired after STOMP DISCONNECT. |
| `onStateChanged` | `void Function(StompConnectionState)?` | Fired on every state change. |
| `onStompError` | `void Function(StompFrame)?` | Server ERROR frame (auth failure, bad destination, ...). |
| `onWebSocketError` | `void Function(dynamic)?` | WebSocket-level error. |
| `onWebSocketDone` | `void Function()?` | WebSocket closed. |
| `onDebugMessage` | `void Function(String)?` | Raw frame-level trace passthrough. |
| `onUnhandledFrame` / `onUnhandledMessage` / `onUnhandledReceipt` | `StompFrameCallback?` | Frames matching no subscription/receipt. |

### Lifecycle methods

| Method | Description |
|---|---|
| `void activate()` | Start (or restart after `dispose`) the connection. |
| `void dispose({bool keepSubscriptions = false})` | Reversible stop; you can `activate()` again afterwards. `keepSubscriptions=true` keeps subscriptions and auto-restores them on reconnect (pause/resume). |
| `void forceReconnect()` | Reconnect now (skip `reconnectDelay`); only acts when "want-connected but currently disconnected". Call it on network recovery. |
| `Stompsocket copyWith({ ... })` | Copy into a new instance: provided args override, others are inherited (all constructor args). Returns a **fresh, unconnected** instance — call `activate()` yourself. |
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
| `id` | Same id → callback joins that subscription's queue, callbacks share one parsed payload, no duplicate SUBSCRIBE; omit → an auto-id independent subscription. |
| `ordered` | `true` (default) dispatches strictly in arrival order (even when a large message is parsed asynchronously); `false` dispatches as soon as parsed — higher throughput, possible reordering. Only applied on the first subscribe of that id. |
| `ack` | See [Acknowledgement](#acknowledgement-acknack). |
| `onParseError` | On parse failure: `nack` (default, redeliver) or `ack` (drop). |

Returns `StompSubscription { String id; void unsubscribe(); }` — `unsubscribe()` is ref-counted (UNSUBSCRIBE only when the last callback for that id is cancelled) and idempotent.

```dart
int unsubscribe({String? id, String? destination}); // by id / by topic; returns count cancelled
void clear();                                        // cancel all
```

### Send

```dart
void send(String destination, {Object? body, Map<String,String>? headers});
```

`body` accepts `String` (as-is), `Map`/`List` (auto JSON-encoded + `content-type: application/json`), `Uint8List` (binary), or `null`. Buffered while disconnected per `queueWhileDisconnected`.

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
| `auto` (default) | `ack:auto` | Server auto-acks; the wrapper sends **no** ACK/NACK. |
| `smart` | `ack:client-individual` | **Auto** ACK (all callbacks succeed) / NACK (any throws). Parse failure follows `onParseError`. |
| `manual` | `ack:client-individual` | **No auto ack**; the callback's 2nd arg is an `AckControl` for manual ack/nack. |

Callback signature: `typedef JsonCallback = void Function(Dictional json, AckControl ack);` (the 2nd arg is a no-op outside `manual`; write `(json, _) {}`).

**Manual ack (callable outside the callback)** — store the `AckControl` and ack later:

```dart
final pending = <String, AckControl>{};

ws.subscribe('/queue/tasks', (json, ack) {
  pending[json['taskId']] = ack; // stash it
}, ack: AckMode.manual);

// elsewhere, after async work:
void onTaskDone(String taskId) {
  pending.remove(taskId)?.ack();  // ack from outside
}
```

`AckControl` is bound to a "session generation": **stale after reconnect (no-op)**, idempotent.

### Types & enums

- `enum StompConnectionState { idle, connecting, connected, reconnecting, disconnected }`
- `enum AckMode { auto, smart, manual }`
- `enum ParseFailureAck { nack, ack }`
- `abstract interface class AckControl { void ack(); void nack(); }`
- `class StompSubscription { String id; void unsubscribe(); }`
- `typedef Dictional<T> = Map<String, T>;` (default `T = dynamic`)
- `typedef JsonCallback = void Function(Dictional json, AckControl ack);`

## Behavior notes

- **No memory growth across reconnects**: `_subscriptions` is keyed by id and only replayed (not re-added) on reconnect; the outbox is capped; `manual` `AckControl`s are held by the caller, not the wrapper.
- **Ordered dispatch**: `ordered:true` uses a per-subscription serial chain to preserve order — the cost is that a large async parse briefly blocks the messages behind it; use `ordered:false` when order doesn't matter and you want lowest latency.
- **Reconnect vs re-subscribe**: transport reconnect is delegated to the library via `reconnectDelay`; re-subscribing is done by the wrapper before `onConnected`. Re-fetch a snapshot in `onConnected` to fill gaps missed while backgrounded.

## License

MIT
