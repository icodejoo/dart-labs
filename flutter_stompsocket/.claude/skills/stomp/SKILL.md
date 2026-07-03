---
name: stomp
description: >-
  Work on flutter_stompsocket — the Flutter/Dart STOMP-over-WebSocket client (class Stompsocket)
  wrapping stomp_dart_client. Read BEFORE modifying lib/flutter_stompsocket.dart, its tests, or
  the READMEs. Covers architecture, the isolate/ordered parsing model, Dart-specific invariants,
  and the verify workflow. Triggers on: STOMP, Stompsocket, stomp_dart_client, subscribe/
  unsubscribe, ack/nack, reconnect re-subscribe, offline send buffer, beforeConnect token refresh,
  binaryDecoder, isolate/compute parsing, ordered dispatch, ValueListenable connection state.
---

# flutter_stompsocket

A **Flutter/Dart** production wrapper over
[`stomp_dart_client`](https://pub.dev/packages/stomp_dart_client) (`^3.0.0`, a normal dependency,
not a peer dep). Package `flutter_stompsocket`, top-level class **`Stompsocket`**. This is the
**original**; `@codejoo/stomp` (a separate repo at `D:\workspaces\codejoo\apps\stomp`) is the TS
port of it. The two share behavior and even test structure — keep them conceptually in sync when
changing shared semantics, but note the platform differences below.

Whole implementation is **one file**: `lib/flutter_stompsocket.dart` (~860 lines). Tests:
`test/flutter_stompsocket_test.dart` driven by an in-package `dart:io` broker
`test/stomp_test_broker.dart`. Example: `example/flutter_stompsocket_example.dart`.

## The core problem it solves

`stomp_dart_client` reconnects the **transport** but does **not** restore subscriptions.
`Stompsocket` keeps a local `Map<String, _Subscription>` registry and **replays it in `_onConnect`**.
Everything else layers on that: shared-parse callback queues, ref-counted unsubscribe, offline
send buffer, ack modes, token-refresh beforeConnect, connection-state observation, foreground
resume.

## Architecture map (all in `lib/flutter_stompsocket.dart`)

- **Subscription registry** — `_subscriptions: Map<String, _Subscription>`. Same `id` → callbacks
  appended to one `_Subscription.callbacks` queue, sharing ONE parsed payload; only one wire
  SUBSCRIBE. STOMP `id` header is set to our id in `_openOnWire` so the library can't auto-assign
  ids that break id-based dedup/unsubscribe. `ack` header set per `AckMode.header` (auto → omitted).
- **Ref-counted unsubscribe** — handle `StompSubscription.unsubscribe()` → `_cancelReg` removes
  one `_CallbackReg`; wire UNSUBSCRIBE fires only when the id's last callback goes. Plus
  `unsubscribe({id | destination})` and `clear()`.
- **Ordered + async parsing** — THE distinctive Dart feature. `subscribe(..., ordered = true)`
  (default) serializes dispatch through `_Subscription.tail` (a `Future` chain) so arrival order is
  preserved even when a large payload parses on a background isolate while a small one parses
  synchronously. `ordered: false` dispatches as soon as parse completes (higher throughput, may
  reorder). See `_onIncoming`.
- **Isolate parsing by size** — `_parse` returns `FutureOr<_ParseResult>`. Payloads
  `<= _isolateThreshold` (32 KB) parse synchronously; larger ones go to a background isolate via
  `compute()` to avoid jank. `_ParseResult` is a record `(Dictional? data, String? error)` — the
  record exists to carry the error string OUT of the isolate (logs in `compute` don't reach the
  main console). `_decodeStringBody` is a top-level function so it can be sent to an isolate.
- **Ack modes** (`AckMode` enum): `auto` (STOMP `ack:auto`, wrapper sends nothing), `smart`
  (`client-individual`, auto-ACK on all-callbacks-ok / NACK on any throw or parse failure per
  `onParseError`), `manual` (`client-individual`, wrapper sends nothing; callback's 2nd arg
  `AckControl` acks/nacks — storable, callable OUTSIDE the callback). Logic is the `switch` in
  `_dispatch`. ack id = `frame.headers['ack'] ?? frame.headers['message-id']` (`_ackIdOf`).
- **Session generation** — `_generation` increments each `_onConnect`. `_MessageAck` captures the
  gen and no-ops after reconnect (`_generation` changed or `!client.connected`); idempotent via
  `_used`.
- **Connection state** — `StompConnectionState` enum, exposed via `state` getter,
  `stateListenable` (a `ValueListenable<StompConnectionState>` backed by `ValueNotifier` — feed a
  `ValueListenableBuilder`), and the imperative `onStateChanged` callback (one-line GetX bridge).
- **beforeConnect** — `_beforeConnect` runs the user hook before every (re)connect, swallows
  errors, and rewrites the mutable `_connectHeaders` map (passed by reference to `StompConfig`) →
  async token refresh on every reconnect.
- **Foreground-resume reconnect** — `resumeOnForeground` (default **false**) installs an
  `AppLifecycleListener(onResume: forceReconnect)`; `forceReconnect()` does deactivate+activate to
  skip `reconnectDelay`. Requires an initialized `WidgetsBinding`.
- **copyWith / dispose** — `copyWith` returns a fresh un-connected instance (private ctor-arg
  fields `_url`, `_heartbeatIncoming`, … exist solely to reproduce construction). `dispose(
  keepSubscriptions=false)` is reversible; `keepSubscriptions=true` retains the registry for
  auto-replay on next `activate` (pause/resume).

## Non-obvious invariants — do NOT break these

1. **Dart `enum`s are fine here** — this repo uses real `enum` for `AckMode`/`ParseFailureAck`/
   `StompConnectionState` (unlike the TS port, which is under `erasableSyntaxOnly` and must use
   `as const` objects). `AckMode.header` maps enum → the SUBSCRIBE `ack` header value.
2. **Binary is detected by `frame.binaryBody != null`** (in `_parse`) — stomp_dart_client routes
   octet-stream frames into `binaryBody`. (This DIFFERS from the TS port, where `isBinaryBody` is
   unreliable and detection goes by `content-type`.)
3. **`binaryDecoder` must be a top-level/static function** — large binary payloads are sent to an
   isolate via `compute(decoder, bytes)`, so it cannot capture instance state / be a closure.
4. **JSON top level must be an object** (`Dictional = Map<String, dynamic>`). `_decodeStringBody`
   returns an error for non-object → drives `onParseError`.
5. **`ordered` dispatch preserves arrival order** — don't "optimize" away the `sub.tail` chain;
   a test sends a >32 KB payload immediately followed by a small one and asserts order `[big, small]`.
6. **Same-id callbacks share the exact same parsed object** (test asserts `identical(a, b)`).
   Independent subscriptions (auto id) do NOT share (`identical` is false).
7. **`_dispatch` re-checks `identical(_subscriptions[sub.id], sub)`** after async parse — the sub
   may have been cancelled or re-created under the same id mid-flight. Keep that guard.
8. **`_runCallbacks` iterates `List.of(sub.callbacks)`** (a copy) so a callback can (un)subscribe
   during dispatch.
9. **State transitions**: `activate`→connecting; `_onConnect`→connected; `_onWebSocketDone`→
   reconnecting (if `reconnectDelay > Duration.zero` and still `_wantConnection`) else disconnected;
   `dispose`→disconnected. `dispose` sets `_wantConnection=false` first so the done handler won't
   override.

## Build & config

- Dart/Flutter package. `pubspec.yaml`: SDK `^3.7.0`, Flutter `>=3.29.0`, dep
  `stomp_dart_client: ^3.0.0`. Lints via `flutter_lints` (`analysis_options.yaml` includes
  `package:flutter_lints/flutter.yaml`).
- It's a library package (has `example/`), versioned in `CHANGELOG.md` (currently 0.1.0).

## Verify workflow

Acceptance = **`flutter test` green** (or `dart test`). Tests spin up a real `dart:io`
`HttpServer`/WebSocket broker (`StompTestBroker`) on an ephemeral loopback port and assert on
captured frames (`broker.framesOf('ACK'|'NACK'|'SUBSCRIBE'|'SEND'|'CONNECT'|...)`,
`broker.subscriptionCount`, `broker.subscribeCountFor(id)`). Reconnect tests use
`broker.dropConnections()`. There's a dedicated test for >32 KB payloads parsing correctly through
`compute`, and one asserting `ordered` keeps big-then-small order. Prefer extending the broker
over mocking stomp_dart_client.

```bash
cd D:/workspaces/flutter_stompsocket
flutter test        # the acceptance gate (dart test also works)
flutter analyze     # flutter_lints
```

When changing behavior, add/adjust a test and, if the public API changes, update BOTH `README.md`
(EN) and `README.zh-CN.md` (ZH) — and consider whether the TS port `@codejoo/stomp` needs the same
change to stay in sync.
