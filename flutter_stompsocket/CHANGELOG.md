## 0.1.3

- Metadata and docs only, no code changes: `repository` / `issue_tracker` now
  point to the monorepo (`https://github.com/icodejoo/dart-labs`), added a
  library-level doc comment, and the changelog is now in English (the Chinese
  original is kept in `CHANGELOG.zh-CN.md` in the repository, excluded from the
  published package).

## 0.1.2

- **Fix:** messages from a stale session no longer leak into the new session;
  restarting after `stop` no longer connects twice; JSON `null` is no longer
  dropped; fixed re-entrant state changes, send-buffer overflow, and a monitor
  callback whose parse failure blocked the ACK.
- Merged duplicated logic, added 23 regression tests, and aligned README /
  ARCHITECTURE with the code.

## 0.1.1

- **Fix: binary misdetection made text messages fail to parse.** The
  `stomp_dart_client` parser puts the body into `binaryBody` when `content-type`
  is `application/octet-stream` **or missing**. Servers such as ActiveMQ often
  omit `content-type`, so plain JSON text was treated as binary and routed to
  `binaryDecoder` (parsing failed outright if none was configured). Now only an
  explicit `octet-stream` takes the binary fast path; everything else first goes
  through a strict UTF-8 decoding probe and, if it succeeds, is parsed as text.
  Only data that structurally violates UTF-8 (compressed / truly binary) falls
  back to `binaryDecoder`.
- **Fix: reconnecting during async parsing of a large frame could send ACK/NACK
  for the old session.** Smart-mode auto-ack had no session-generation check
  (manual mode already did): if the connection dropped and reconnected while a
  large frame was being parsed in a background isolate, `_onConnect` reused the
  same `_Subscription` objects, so the `identical()` check passed and
  `client.connected` was true again, and an ACK/NACK carrying the **old session's**
  ack id was sent, which the server could not recognize. The session generation
  is now captured when the message arrives and threaded through
  `_dispatch` / `_sendAck`; if it changed, the ack is skipped.
- **Change: `resumeOnForeground` now defaults to `true`** (aligned with
  `@codejoo/stomp`). Reconnecting on return to the foreground matters most on
  mobile (the OS suspends background timers), so defaulting to off was
  counter-intuitive. It still requires a Flutter app with an initialized
  `WidgetsBinding`; pure Dart usage can set it to `false` explicitly.
- **Fix: the separator in the auto dedup key could truncate STOMP frames.** When
  no `id` is given, the deterministic key used to merge subscriptions is sent on
  the wire as the STOMP `id` header. It used to be joined with `\x00`, but NUL is
  the STOMP frame terminator, and a NUL inside a header cuts the frame in half
  (the server reports "malformed frame"). It now uses `\x1f` (unit separator),
  the same fix as in `@codejoo/stomp`.

## 0.1.0

- Initial release. A wrapper around `stomp_dart_client` providing:
  - Shared parsing via a function queue (callbacks with the same id share one
    parsed result)
  - Three ways to cancel: handle `unsubscribe()` / by id / by destination /
    `clear()`
  - Automatic reconnect (from the library) and automatic re-subscribe after
    reconnect (from this wrapper)
  - `send()` with an offline buffer while disconnected
  - `AckMode { auto, smart, manual }`: no ack / automatic ack / manual ack
    (`AckControl`)
  - Injectable binary decoder `binaryDecoder`
  - `beforeConnect` to refresh the token before connecting
  - Connection state as `ValueListenable` plus `onStateChanged`
  - `resumeOnForeground`: force a reconnect on return to the foreground
  - `copyWith` and pass-through of native `stomp_dart_client` options
