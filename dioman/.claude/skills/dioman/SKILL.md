---
name: dioman
description: >-
  Work on dioman — composable, self-contained Dio interceptor plugins (auth, cache, retry, share/
  dedup, mock, normalize, repath, filter, key, loading, cancel, envs, log) plus the correct install
  order. Pure Dart, dio-only, no Flutter. Read BEFORE modifying anything under lib/src/, adding a
  plugin, or reordering the chain. Covers the forward-order execution model, the install-order
  constraints, per-plugin implementation invariants, the extra[...] key registry, and how to verify.
  Triggers on: dio, interceptor, DiomanPlugin, auth token refresh/401 replay, cache TTL, request dedup/
  share, retry back-off, mock fallback, envelope normalize, DiomanException, ITokenManager, install order.
---

# dioman

Pure-Dart package (`dio: ^5.0.0` only, **no Flutter**, SDK `^3.5.0`). A set of **self-contained
Dio interceptor plugins**, each extending `DiomanPlugin` (a named `Interceptor` with `String get name`
and a `dispose()` hook — `lib/src/dioman_plugin.dart`), PLUS the documented correct install order.
Entry `lib/dioman.dart` re-exports all 16 ordered plugins (envs → … → normalize below). Each plugin lives in its own `lib/src/*.dart`.

Acceptance = **`dart analyze` clean** + `dart test` (`test/dioman_test.dart`, `test/
dioman_combinations_test.dart`, `test/dioman_coverage_test.dart`, `test/
dioman_powerset_test.dart` — all four against a REAL `dart:io HttpServer` via `test/support/
test_server.dart` — `TestServer.start(handler)` + `respondJson(req, data, status)` — never a
fake/mock `HttpClientAdapter` and never a hardcoded address like `127.0.0.1:1` for an
"unreachable" endpoint; this matters because it lets throwaway-Dio re-issues (auth replay,
share/retry re-issues) actually reach the test server instead of the live internet, and keeps
every test exercising the real dio transport instead of a stand-in for it) + the runnable
`example/dioman_example.dart` (needs real network; expect it to fail offline). The two READMEs
(`README.md` EN, `README.zh-CN.md` ZH) are the canonical usage docs — read the relevant section
before changing behavior, and keep both in sync on any public API change. They intentionally do
NOT carry design rationale, trade-off writeups, or "why we chose X" prose — that history lives in
git log / this skill file, not in user-facing docs.

**Every test, no exceptions, goes through `test_server.dart`'s real `HttpServer`.** Never a fake/
mock `HttpClientAdapter`, never a hand-picked "probably nothing's listening" address (`127.0.0.1:1`,
`example.invalid`). Need a genuinely unreachable endpoint? Start a `TestServer`, grab its
`baseUrl`, then `await server.close()` — the connection-refused you get back is real, not
simulated. This is a hard rule, not a style preference: it's what lets a throwaway-Dio re-issue
(auth replay, retry/share's own re-dispatch) actually land somewhere instead of silently no-op'ing
against a fake adapter that doesn't model per-instance `HttpClient` behavior — a bug in exactly
that interaction (cache/share's `resolve()` missing `callFollowingResponseInterceptor: true`) was
only caught because the coverage sweep used a real server end-to-end.

## The one idea everything follows from

**Dio is forward-order, NOT an onion.** `onRequest`, `onResponse`, and `onError` each iterate
interceptors in `dio.interceptors` **add order** (not reversed for the response phase). So a single
ordered list must satisfy request, response, AND error phases at once. Two rules make ordering
load-bearing:

1. A short-circuit — `handler.resolve()` from `onRequest` (cache hit / share follower / mock hit) —
   **skips every following interceptor's `onRequest`, but still runs `onResponse` of interceptors
   placed AFTER the resolver.** Interceptors placed *before* the resolver never see the response.
2. The `onError` chain runs forward through every interceptor; the first to `resolve()` (auth-401
   replay, retry re-issue) **halts the rest**.

### Recommended order (and the hard constraints)

`envs → timeout → repath → filter → key → cache → offline → share → mock → cancel →
loading → auth → retry → breaker → log → normalize`

`normalize` is LAST — optional, business-specific, not a transport concern (see its own bullet
below and its class doc). Every OTHER plugin therefore sees the response exactly as it came off
the wire, whether or not `normalize` is even installed.

- **timeout right after envs** — pure per-request config (rewrites connect/receive/send timeouts by
  network tier), no request/response coupling, so it sits at the very front alongside `envs`.
- **key before cache & share** — they key off `extra[kRequestKey]`; no key ⇒ they no-op (treat
  request as independent). This is a hard dependency.
- **cache before offline** — an offline read that hits the cache short-circuits before `offline`
  can queue it (stale-cache-over-queue for reads).
- **offline before share/cancel/loading** — a parked (queued) request must NOT have created a share
  entry or opened a cancel/loading bracket, or those leak while it waits; parking happens by NOT
  calling `next` (see its bullet), so anything after it never ran its onRequest.
- **cache/share/mock before cancel & loading** — a short-circuit skips following `onRequest`s, so a
  bracket (increment/inject) placed *before* the resolver would fire on request and never clean up.
- **cancel & loading before auth & retry** — on a 401 (auth) or network retry, those `resolve()` the
  error and halt the forward `onError` chain; the brackets must already have run (counter
  decremented, token released) by then.
- **breaker after retry** — so it counts only each request's FINAL outcome (a retry-recovered
  request reaches its onResponse as a success; only a retry-exhausted one reaches onError as a
  failure), not transient blips retry already absorbed. See its bullet.
- **normalize dead last** — so `cache`'s stored payload, `retry`'s `shouldRetry`, and
  `log`'s dump all see the RAW response regardless of whether `normalize` is installed. Also means
  `normalize` catches a business failure via its own `reject(...)` (see its bullet below) only for
  envelopes `retry`'s own `shouldRetry` didn't already claim — the two mechanisms are
  independent, not stacked, since `retry` runs first.

## Per-plugin implementation invariants (do NOT break)

- **DiomanAuth** (`auth_plugin.dart`, `name: 'dioman:auth'`). Single refresh window = a shared
  `Future<bool>? _refreshing` installed via `_refreshing ??= (() async {…})()` (the `??=` is the
  atomicity trick; `finally { _refreshing = null }` reopens it). Concurrent 401s join the one
  future, then replay. **Replay re-issues via a throwaway `Dio().fetch(opts)`** (lazily created
  `_replayDio`, closed in `dispose()`) — NOT the app dio — so replays deliberately bypass the whole
  interceptor chain (no re-entry into auth); this also means a replayed response bypasses
  `DiomanNormalize` — a known, accepted trade-off of that design (immaterial in practice now that
  `normalize` is recommended LAST anyway — see the order note above). Optional `cancel`/`share`
  setters (NOT constructor params — mirroring `DiomanRetry`'s, see its bullet; `Dioman.install`
  sets them for you automatically when both a `cancel:`/`share:` and an `auth:` are passed to it)
  restore `cancelAll()` trackability (via `DiomanCancel.track()`/`untrack()` around the replay) and
  correct `DiomanShare` settlement (via `registerDownstreamSettler()`/`settle()`) for a request
  currently being replayed — without them, the replay is invisible to both, same shape as the
  bare-Dio trade-off `DiomanRetry` has. Before every replay (refresh or bare replay),
  `_injectToken` re-applies the CURRENT token (via `ready` or `buildHeader`) so a replay after a
  successful refresh doesn't carry the stale pre-refresh header. The `dioman:auth:refreshed`
  one-shot flag is the ONLY thing preventing an infinite refresh→401→refresh loop — never remove it.
  `defaultAuthFailure` distinguishes "I must refresh" from "someone already did" by comparing the
  request's carried token against the current store token — compared via the RAW token stashed in
  `extra['dioman:auth:tokenUsed']` at injection time, not the formatted header (`buildHeader` may
  wrap it, e.g. `'Bearer $t'`, which would never equal the raw store token); falls back to parsing
  the header only when a custom `ready` callback bypassed the stash. Both onRequest `reject()` calls
  (refresh-in-progress-failed, no-token-denied) pass `callFollowingErrorInterceptor: true` so
  brackets installed before auth (cancel/loading/share) still get their `onError` to release state —
  the default `false` would skip the entire error chain and leak them. 5 `AuthFailureAction`s:
  `refresh/replay/deny/expired/others`. `ITokenManager` interface: `accessToken`, `refreshToken`,
  `canRefresh`, `clear()` (note: only `accessToken`/`clear` are read; refresh is delegated to the
  `onRefresh` callback). Default: **every request protected** unless `extra['dioman:auth']` holds a
  `DiomanAuthOptions(enabled: false)` / `isProtected` says otherwise. Also has a constructor-level
  `enabled` flag (default `true`) that disables the whole plugin. Auth's internal `dioman:auth:*`
  extra constants (built off `_name = 'dioman:auth'` as `'$_name:decision'` etc.) are plain strings
  on purpose so they survive Dio's `mergeConfig` on replay.
- **DiomanShare** (`share_plugin.dart`, `name: 'dioman:share'`). Completer-per-key in `_active`, referenced
  directly off each request via `extra['dioman:share:entry']` (not re-looked-up from `_active` in
  onResponse/onError — the shared entry may already be removed by a sibling by the time a
  superseded/losing caller's response lands). No key ⇒ pass through independent. Followers attach to
  `entry.completer.future` and never hit the network. `start`/`retry`: one leader, rest wait. `end`:
  every caller proceeds to network, but only the highest-`seq` response settles the shared promise —
  every other caller (older or superseded) is redirected to that settlement instead of returning its
  own stale result. `race`: all run, first success settles; a losing/failing caller is likewise
  redirected to the eventual winner's result instead of its own. `retry`: onError loops up to
  `retries` times re-issuing via a throwaway `Dio().fetch` (callers never see individual retries);
  the loop's success/exhaustion path is what settles the completer and removes the entry — do NOT
  `handler.resolve()`/`next()` without also doing both. **Remove-from-`_active` BEFORE
  `completer.complete`**, guarded by `identical()` so a new burst that already installed a fresher
  entry isn't clobbered. Each `_Entry`'s completer future carries a defensive `.ignore()` so a
  lone leader (no follower ever attached) or an already-settled end/race completer erroring doesn't
  raise an unhandled zone error. Gotcha: `dispose()` clears `_active` WITHOUT completing pending
  completers → waiters hang.
  **Deferred settlement for DiomanRetry/DiomanAuth** (`_pendingSettlers` int field,
  `registerDownstreamSettler()`, `settle(key, {response, error})`, `hasMultipleDownstreamSettlers`):
  because this plugin sits BEFORE retry/auth in the chain, its own onResponse/onError would
  otherwise settle a shared entry with the FIRST attempt's outcome — before retry/auth ever get a
  chance to recover it — stranding any follower with a stale pre-retry/pre-refresh result even
  though the leader itself goes on to succeed. Fix: `DiomanRetry`/`DiomanAuth` expose a `share`
  SETTER (not a constructor param) whose body calls `share.registerDownstreamSettler()` — set by
  hand, or automatically by `Dioman.install` when both a `share:` and a `retry:`/`auth:` are passed
  to it; while `_pendingSettlers > 0`, this plugin's onResponse/onError skip their own `_settle`+`complete` and
  just `handler.next()`, leaving the entry ALIVE for whoever registered to settle explicitly via
  `settle()`. `DiomanAuth` calls `settle()` unconditionally on a successful resolve (retry, even if
  also registered, is bypassed — see its own bullet on resolve-skips-later-stages) and, on
  hand-off, only if `!hasMultipleDownstreamSettlers` (else defers to `DiomanRetry`, which is always
  structurally last and always settles unconditionally). A companion marker, checked at the top of
  `onRequest`
  (`if (_pendingSettlers > 0 && options.extra['dioman:retry:reentry'] == true) return
  handler.next(options);`), lets `DiomanRetry`'s OWN re-dispatch (see its bullet — it reuses the SAME
  `RequestOptions`) skip the leader/follower decision entirely — without it, deferring removal means
  the still-active entry would make the re-dispatch treat itself as a follower of its own leader,
  deadlocking (this marker is a no-op, and the OLD immediate-remove behavior applies, whenever
  nothing is registered — i.e. it's genuinely dead code unless the `share` setter was wired
  somewhere).
  **Known separate issue (not fixed, pre-existing, unrelated to the above)**: a concurrent follower
  attached via `_handleStart`'s onRequest-side `RequestInterceptorHandler.reject()` (or, same shape,
  `_awaitEntry`'s `resolve`/`reject` from a `.then()` callback) crashes with an unhandled zone error
  instead of cleanly resolving/rejecting the waiting caller, whenever the entry it's bound to
  settles with an ERROR — reproduced against a real server too (not a FakeAdapter artifact), so it's
  a genuine dio/zone interaction, not something this design can route around. A follower that ends
  up bound to a SUCCESSFUL settlement (including via the deferred-settlement mechanism above) is
  unaffected — only the error path crashes. Avoid relying on `start`/`retry`/`end`/`race` followers
  observing an error until this is investigated.
- **DiomanCache** (`cache_plugin.dart`, `name: 'dioman:cache'`). TTL store keyed by `extra[kRequestKey]`, TTL in
  **milliseconds** (default 60000). Hit ⇒ `handler.resolve(Response(...,'OK (cached)'), true)` — the
  trailing `true` (`callFollowingResponseInterceptor`) is required so a cache hit still runs
  `onResponse` of everything installed after cache (share, mock, cancel, loading, auth, retry, log,
  normalize), same as a real response; dropping it would make a cache hit skip `DiomanNormalize`
  entirely (a real, previously-shipped bug — a cache hit returned the raw envelope even with
  `normalize` installed, while a live response correctly got unwrapped). One side effect: it also
  means a cached entry now gets a chance at `DiomanRetry` recovery too (see the Gotcha below).
  Stores only **2xx** `response.data`, RAW (not normalize-unwrapped — `normalize` runs LAST, after
  this plugin; see the order note above). `CacheClone` (`none`/`shallow`/`deep`) is applied **on
  read**, not write — the store holds the live `response.data` reference, so a `none` reader mutating
  the result corrupts the cache. Default `shouldCache` = GET only. Bounded by `maxEntries` (default
  500, `0` disables the cap) — LRU-evicted via remove-then-reinsert on write (Dart's default `Map` is
  insertion-ordered, so `_store.keys.first` is always the least-recently-written entry); without this,
  deep `DiomanKey` keys that vary per query/body (paginated/search endpoints) would accumulate
  forever since an entry is otherwise only removed when its *exact* key is re-requested after expiry.
  Gotcha this plugin does NOT fully solve: it has no concept of "business failure" — a 200 that
  `DiomanRetry.shouldRetry` considers a failure still gets cached here (this plugin runs
  first), so a LATER, unrelated caller for the same key still hits the poisoned entry — but since the
  cache-hit resolve now runs the full following chain, if that later caller's `DiomanRetry` has a
  `shouldRetry` configured, it sees the poisoned data on the cache hit too and recovers it via
  its own re-issue, same as it would for a live response — so the caller gets the CORRECT data, just
  not a fast cache hit. The poisoned entry itself is still never evicted/overwritten (the recovery
  re-issue doesn't write back to cache), so every future caller repeats the recovery dance rather than
  getting a cheap hit, until the entry expires. `DiomanRetry`'s own re-issue (the bare Dio from ITS
  OWN prior attempt) never reads this plugin back either way (bare Dio, doesn't touch this plugin at
  all).
- **DiomanOffline** (`offline_plugin.dart`, `name: 'dioman:offline'`). Offline queue-and-replay.
  Constructor subscribes to the injected `Stream<bool> onConnectivityChanged` (`_sub`, cancelled in
  `dispose()`); a `true` event calls `flush()`. `bool Function() isOnline` is checked in `onRequest`.
  **Parks a request by NOT calling `next`** — it stashes `{handler, options}` in the FIFO `_queue`
  and returns, leaving the request suspended at this plugin (this is WHY it must sit before
  share/cancel/loading — nothing after it ran its onRequest, so no share entry / bracket exists to
  leak). `flush()` drains the queue by calling `handler.next(options)` on each — resuming it down
  the REST of the chain (NOT a throwaway Dio, and it never re-enters this onRequest since `next`
  goes forward). Each entry is settled EXACTLY once at whichever exit fires first: flush →
  `next`; queue full (`maxQueueSize`, default 50, `0`=uncapped) → oldest evicted with
  `reject(queueFull)`; `maxWait` timer (default `null`=unbounded) → `reject(timeout)`; `dispose()` →
  `reject(disposed)` for all. Rejections are `DioException(error:
  DiomanOfflineException(reason), type: unknown)`, no response → retry won't retry them. `maxWait`/
  eviction/dispose all remove-from-queue before rejecting, and the timer callback guards on
  `_queue.remove(entry)` returning true, so no double-settle. `shouldQueue` (default `null` = queue
  everything) gates what's parked; reads normally shouldn't queue (let cache serve them).
  `pending` getter exposes queue length for tests. **dispose MUST reject all** or waiters hang.
- **DiomanNormalize** (`normalize_plugin.dart`, `name: 'dioman:normalize'`, `const` ctor, `onResponse`
  only). **Optional, business-specific, install LAST** — after `log`, at the very end (also where
  `Dioman.install` places it regardless of argument order) — see its class doc and the order note
  above; NOT part of the hard-constraint order, and deliberately excluded from quickstart examples.
  Default detects an envelope by `data is Map && containsKey(codeKey)`; success (`code==0`)
  ⇒ mutates `response.data = envelope[dataKey]` in place; failure ⇒
  `handler.reject(DioException(error: DiomanException(code,message,data)), true)` — **the trailing
  `true` ("call following error interceptors") is required** so anything installed after it (nothing,
  normally, since it's last) would still see the converted business error; dropping it stops error
  propagation. `DiomanException implements Exception` with `code`/`message`/`data`.
- **DiomanRetry** (`retry_plugin.dart`, `name: 'dioman:retry'`). Ported/aligned with the same
  rewrite in `@codejoo/axp`'s `retry.ts` (this monorepo's TS/axios counterpart) — see its class doc
  and `CHANGELOG.md`'s `0.5.0` entry for the full field list. Flat 3000ms default `delay` (was
  exponential `1000*(1<<attempt)` = 1s/2s/4s) — `delay` is now `Duration Function(int current, int
  max, Response? response, DioException? err)` (was `Duration Function(int attempt)`), with
  `jitter`/`delayMax` layered on top (never applied to a `Retry-After`-derived wait). `methods` (a
  `List<String>` whitelist, default idempotent verbs excluding post/patch) is checked FIRST and is
  a hard veto `shouldRetry` cannot override. `shouldRetry(DioException? err, Response? response)`
  now returns `bool?` (was `bool`) and has NO built-in default — an exact `true`/`false` wins
  outright, `null` (including when `shouldRetry` isn't set) falls through to `statusCodes` (default
  `[408,429,500,502,503,504]`), and only when there's no HTTP status at all does it fall further to
  a timeout/connectionError `DioException` type check (pure network failures still retry by
  default). Respects a response's `Retry-After` header (numeric seconds or RFC 1123 HTTP-date) over
  the computed `delay`, gated by `respectRetryAfter`/`afterStatusCodes` (default `[413,429,503]`)
  and capped by `retryAfterMax`. The wait races `RequestOptions.cancelToken`'s `whenCancel`, so a
  cancel mid-wait stops it immediately instead of idling out the full delay. `extra['dioman:retry']`
  now accepts `int` (max override) / `false` (hard-disable veto) / `DiomanRetryOptions` (full
  per-field override), not just the options object. **Re-issues via a throwaway,
  interceptor-less `Dio()`** (lazily created `_retryDio`, closed in `dispose()`) —
  same pattern as auth/share-retry, NOT the injected app dio (that was the OLD design; changing this
  back reintroduces the cache-poisoning and share-reentry-deadlock bugs it was specifically changed to
  avoid — see git history / conversation for the full trade-off analysis). Because the re-issue never
  re-enters this chain, the WHOLE retry loop (up to `max` attempts) has to live inside ONE
  onResponse/onError invocation — an explicit `for` loop, re-checking `shouldRetry`
  against EVERY subsequent attempt's own outcome (do not "simplify" this back to a single-shot
  `_reissue` + rely on recursion; there is no recursion anymore, the loop IS the retry mechanism).
  No more `extra['dioman:retry:count']` — state doesn't need to persist across separate onError
  invocations now that there's only ever one per top-level failure. `shouldRetry` always sees
  the RAW response body (`normalize`, if used, is LAST — see order note above — so it never runs
  before this plugin). Optional `share`/`cancel` SETTERS (not constructor params — both call the
  OTHER plugin's public cross-plugin API — `DiomanShare.registerDownstreamSettler()`/`settle()`,
  `DiomanCancel.track()`/`untrack()` — see their own bullets; `Dioman.install` sets them
  automatically when both a `share:`/`cancel:` and a `retry:` are passed to it) restore what the
  bare-Dio re-issue would otherwise lose for those two specifically; `DiomanAuth`'s token injection and
  `DiomanNormalize`'s unwrapping are NOT recoverable this way (no equivalent param) — a retried
  response carries whatever auth header the ORIGINAL attempt had, and is never normalized, by
  design (see the class doc's full trade-off list). Optional `onRetry: (attempt) {}` callback is a
  lightweight substitute for the logging the re-issue no longer passes through `DiomanLog` for.
- **DiomanBreaker** (`breaker_plugin.dart`, `name: 'dioman:breaker'`). Circuit breaker, one `_Bucket`
  per `METHOD:path` key (override via `keyBuilder`; default reuses `DiomanKey`'s fast-key scheme,
  computed independently — does NOT read `extra[kRequestKey]`). State machine `closed → open →
  halfOpen`: `failureThreshold` (default 10) CONSECUTIVE failures trip closed→open (any success
  resets the count); open rejects fast in `onRequest` (no network) until `resetDuration` (default
  30s) elapses, then admits up to `halfOpenMaxCalls` (default 3) probes — ONE probe success →
  closed, ONE probe failure → open (cooldown restarts). **Installed AFTER retry**, so it only ever
  records each top-level request's FINAL outcome (retry re-issues via its own bare Dio never reach
  it → each request counted exactly once). `onRequest` marks the admitted request via
  `extra['dioman:breaker:key']`; `onResponse`/`onError` only record an outcome when that mark is
  present — a cache/mock short-circuit runs `onResponse` WITHOUT having run this plugin's
  `onRequest`, and must not be recorded. `onError` also skips its OWN `DiomanBreakerOpenException`
  rejections (never counts them). The open-rejection is `DioException(error:
  DiomanBreakerOpenException(bucketKey, retryableAt), type: unknown)` with NO response — so retry's
  default `shouldRetry` won't retry a fail-fast (same non-retryable-shape trick as auth's denial).
  Reject uses `callFollowingErrorInterceptor: true` so brackets before it (cancel/loading/share)
  still release — identical to auth's onRequest rejections. `_isFailure` default: HTTP 5xx / 429, or
  a timeout/connection-error `DioExceptionType` when there's no status; unknown-type errors (auth
  denial, its own open-reject) deliberately don't count. `onError` also skips `DioExceptionType.cancel`
  ENTIRELY — a user cancellation is recorded as neither success nor failure (recording it as
  "success", the default for anything `_isFailure` returns false on, would reset the
  consecutive-failure count and let a burst of cancels mask a genuinely failing dependency). Custom
  `shouldTrip(response?, err?) →
  bool?` overrides (exact bool wins, null → default). `DiomanRetry.breaker` SETTER (wired by
  `Dioman.install` when both passed) lets retry call `breaker.isOpen(config)` — a PURE read, no
  mutation — before each re-issue to stop an in-progress retry loop the instant the breaker trips.
  `dispose()`/`reset()` clear all buckets; no timers, no parked handlers.
- **DiomanKey** (`key_plugin.dart`, `name: 'dioman:qid'`, `const` ctor). Exports
  `const kRequestKey = 'dioman:key'` — fixed, cross-plugin protocol key (key writes, cache/share
  read), a DIFFERENT string from the plugin's own `name` (`'dioman:qid'`) on purpose, so the
  caller-facing override and the internal wire-protocol slot can never collide. A
  `DiomanKeyOptions(enabled: false)` at `extra['dioman:qid']` ⇒ no key written (request treated
  independent by cache/share); `DiomanKeyOptions(key: '...')` overrides the computed key outright.
  fast = `METHOD:uri.path`; deep also folds **sorted** query params + body. `_encode` sorts map
  keys for determinism — breaking the sort breaks cache/share hit correctness.
- **DiomanMock** (`mock_plugin.dart`, `name: 'dioman:mock'`). `enabled=false` ⇒ passthrough. Route key
  `'METHOD:${options.uri.path}'` — matches `DiomanKey`'s fast-key scheme (resolved path, not the
  raw `options.path`, so absolute-URL and baseUrl-relative requests key consistently). Inline handler
  → decodes the returned `ResponseBody` via a shared `FusedTransformer` (mirroring what dio's own
  dispatch path does) before resolving — constructing the `Response` straight from the raw
  `ResponseBody` would leave `.data` holding the undecoded stream wrapper instead of parsed JSON.
  Both inline-handler and mock-server-redirect resolves pass `callFollowingResponseInterceptor: true`
  so a mock hit still runs `onResponse` of normalize/cache/share (installed earlier in the chain) —
  without it, a mock hit would skip normalize's envelope unwrap and leave a `DiomanShare` entry
  permanently unsettled. Mock-server redirect clears `queryParameters` on the rewritten
  `RequestOptions` — `_rewriteUrl` already folds the original query string into the path, so leaving
  the map populated would make dio append it a second time. Else redirect to `mockUrl` via a fresh
  `Dio`; on 404/network (per `defaultFallback`) → `handler.next(options)` falling back to the REAL API
  with original options. Never falls back on user `cancel`.
- **Cancel/Loading brackets** (`cancel_plugin.dart` `name: 'dioman:cancel'`, `loading_plugin.dart`
  `name: 'dioman:loading'`). Both hook all three of onRequest/onResponse/onError to survive short-circuits.
  Cancel injects a `CancelToken` only if the request lacks one, and sets `token.requestOptions =
  options` right after (see next paragraph for why) — the `existing != null` branch (re-registering
  a token this plugin itself injected, checked via `extra['dioman:cancel:token'] == existing`)
  exists for a `RequestOptions` object that re-enters this SAME onRequest a second time (e.g. a
  caller manually re-dispatching it through this same Dio); none of `DiomanRetry`/`DiomanAuth`/
  `DiomanShare`'s own internal re-issues hit it anymore (all three use a throwaway,
  interceptor-less Dio that never reaches this onRequest) — they stay trackable instead via the
  public `track(token)`/`untrack(token)` methods, called by `DiomanRetry`/`DiomanAuth` around their
  own re-issue when their `cancel` setter is set (see their bullets). `cancelAll([reason])` + top-level
  `cancelAll(dio,[reason])`; `dispose()` cancels all. Cancel has a constructor-level `enabled` flag
  (wrapped in `DiomanCancelOptions`, checked at the top of `onRequest`) but no per-request `extra`
  opt-out — it always injects unless the caller already supplied a token.
  **`token.requestOptions = options` is load-bearing, not cosmetic.** dio's own `Options.compose`
  only wires `cancelToken.requestOptions` for a token the CALLER already attached before compose
  runs (`options.dart`); a token this plugin attaches afterwards, here in `onRequest`, never gets
  that backfilled on its own. Without the explicit assignment, `CancelToken.cancel()`
  (`cancel_token.dart`) falls back to `requestOptions ?? RequestOptions()` — a BRAND NEW, empty
  `RequestOptions` — for the resulting `DioException`, wiping out every OTHER plugin's per-request
  `extra` state on cancellation (share's entry key, loading's bracket flag, ...). This was a real,
  previously-shipped bug: cancelling a `DiomanShare` leader permanently deadlocked that key (its
  onError could never find `extra['dioman:share:entry']` to settle/remove it), and cancelling any
  request left `DiomanLoading`'s counter stuck forever (same reason). Do not remove this line.
  Loading is a 0↔1
  edge-triggered counter calling `onChanged(bool)`; increment marks the request as bracketed via
  `extra['dioman:loading:bracketed']` and decrement only fires if that request was actually the one
  that incremented — needed because a mock hit resolving with
  `callFollowingResponseInterceptor: true` runs loading's `onResponse` even though loading's own
  `onRequest` (later in the chain) never got to run for that short-circuited request; a plain
  `DiomanLoadingOptions(enabled: false)` recheck (or a disabled constructor-level `enabled`) would
  otherwise decrement an unrelated in-flight request's counter if not gated correctly. `dispose()`
  force-resets to 0 and fires `onChanged(false)`. `DiomanLoadingOptions` also carries an `onChanged`
  field mirroring the constructor param, for structural symmetry only — never read per-request
  (overriding the shared counter's callback for one call would desync increment/decrement).
- **DiomanEnvs** (`envs_plugin.dart`, `name: 'dioman:envs'`). Install-time only (`onRequest` no-op). First
  matching `EnvRule` wins. `apply` only overwrites `responseType` when the rule's `BaseOptions`
  explicitly sets something other than the `ResponseType.json` default — since `responseType` is
  non-nullable, `json` is treated as "not intentionally set" (same convention as every other guarded
  field), so a rule that only configures e.g. `baseUrl` no longer silently resets a user-configured
  `bytes`/`stream` responseType back to json. Known limitation: a rule that genuinely WANTS to reset
  responseType to json is indistinguishable from "didn't set it" — there's no sentinel for that.
  Constructor-level `enabled` flag (wrapped in `DiomanEnvsOptions`) makes `apply` a permanent no-op.
- **DiomanTimeout** (`timeout_plugin.dart`, `name: 'dioman:timeout'`). Dynamic per-request timeouts
  by network tier. `NetworkQuality Function() probe` (constructor-only, called once per `onRequest`)
  returns one of `NetworkQuality{excellent,good,poor,none}`; `Map<NetworkQuality, DiomanTimeouts>
  timeouts` maps each tier to a `DiomanTimeouts(connect?, receive?, send?)`. **Only non-null fields
  are written** onto `options.connectTimeout`/`receiveTimeout`/`sendTimeout` — a null field leaves
  the request's existing value (from `BaseOptions`/caller) untouched, and a tier ABSENT from the map
  is a complete no-op for that request. Default map sets connect 10s/15s/30s/10s (weak-net stretch),
  receive/send untouched. `none` is just another tier — NO fail-fast (that's offline's job). Per-
  request `DiomanTimeoutOptions.timeouts` MERGES by tier (`{...own, ...override}`). No instance
  state, `dispose()` no-op. Pure config → installed right after envs.
- **DiomanLog** (`log_plugin.dart`, `name: 'dioman:log'`). Dependency-free; `print` by default, `writer` to
  route elsewhere.

## The `extra[...]` key registry (single source of coordination)

**`name` is the key — fixed, not reconfigurable.** Every plugin's `String get name` (e.g.
`'dioman:cache'`) doubles as its `extra` slot: `options.extra[name]`. There is no
static/mutable "remap the key" mechanism (that existed briefly in 0.3.0 as `configProperty` and
was removed) — `name` is a plain literal getter, full stop.

**No `dynamic` + `is` sniffing.** Every plugin with a caller-facing per-request option defines a
matching `DiomanXxxOptions` class (**every field nullable, including `enabled`** — see below) and
reads/writes `options.extra[name]` as that single concrete type. **Type-check once, reuse the
result**: `final o = override is DiomanXxxOptions ? override : null;` at the top of the method,
then `o?.field ?? ownField` for every field after — never repeat the `is` check per field
(`onResponse`/`onError` get their own `o` since they're separate calls; that's the only
unavoidable repetition). Do this for any new plugin that takes a per-request option.

**Fields are `null` by default, meaning "inherit the constructor's value" — not a hardcoded
default.** `DiomanXxxOptions({this.enabled, this.expires, ...})` — no field has `= true` /
`= const []` / etc. This matters because a per-request override that only sets *one* field must
not silently reset every other field (especially `enabled`) to some implicit default; the
resolution is always `o?.field ?? constructorField`, so an omitted field is invisible to the
merge. Every field mirrors a constructor parameter 1:1, **except** constructor-only dependencies
that can't sensibly vary per call (`tokenManager`/`onRefresh`/`onAccessExpired` on `DiomanAuth`,
`onRetry` on `DiomanRetry`, `onChanged` on `DiomanLoading` — the last one IS mirrored onto
`DiomanLoadingOptions` for structural symmetry but documented as never read per-request, since
swapping the shared counter's callback for one call would desync the increment/decrement pair).
`share`/`cancel` on `DiomanAuth`/`DiomanRetry` aren't constructor params at all — they're plain
SETTERS (see their bullets above), so they don't appear in `DiomanXxxOptions` either.

**`List`/`Map` fields merge (union), they do not replace.** `DiomanFilterOptions.ignoreKeys`/
`ignoreValues`, `DiomanKeyOptions.ignoreParams`/`ignoreDataKeys`, and `DiomanMockOptions.routes`
all resolve as `{...ownDefault, ...override}` (or `own[k] ?? override[k]` lookup for maps) — a
per-request addition supplements the plugin's defaults instead of shadowing them. Every other
field (scalars, enums, single callbacks) resolves as plain `override ?? own` (last-write-wins,
no merge concept applies).

**Every plugin also takes a constructor-level `enabled` flag** (default `true`) that disables the
plugin permanently, independent of (and resolved together with, via the same `o?.enabled ??
enabled` expression) any per-request `DiomanXxxOptions.enabled`.
`DiomanCancel`/`DiomanEnvs` have *only* this constructor-level flag (wrapped in
`DiomanCancelOptions`/`DiomanEnvsOptions`) since they have no per-request behavior at all — no
`extra[name]` is ever read for those two, so no merge logic exists there.

Fixed `name` values (also the `extra` key): `DiomanAuth` → `dioman:auth`, `DiomanKey` →
`dioman:qid`, `DiomanCache` → `dioman:cache`, `DiomanShare` → `dioman:share`, `DiomanMock` →
`dioman:mock`, `DiomanLoading` → `dioman:loading`, `DiomanLog` → `dioman:log`, `DiomanRetry` →
`dioman:retry`, `DiomanFilter` → `dioman:filter`, `DiomanRepath` → `dioman:repath`,
`DiomanNormalize` → `dioman:normalize`, `DiomanCancel` → `dioman:cancel`, `DiomanEnvs` →
`dioman:envs`, `DiomanTimeout` → `dioman:timeout`, `DiomanBreaker` → `dioman:breaker`,
`DiomanOffline` → `dioman:offline`.

Internal (fixed, cross-plugin protocol or single-plugin bookkeeping, never exposed via a per-call
`DiomanXxxOptions`): `kRequestKey` = `'dioman:key'` (key writes, cache/share read — the one
genuinely cross-plugin key, kept as a public top-level const for that reason, and deliberately a
DIFFERENT string from `DiomanKey`'s own `name` = `'dioman:qid'` so the wire-protocol slot and the
caller-facing override can never collide), `dioman:cache:key`/`ttl`/`clone`,
`dioman:share:entry`/`seq`/`policy`/`retriesLeft`, `dioman:cancel:token`,
`dioman:loading:bracketed`, `dioman:auth:decision`/`protected`/`refreshed`/`denied`/`tokenUsed`,
`dioman:breaker:key` (marks a request `DiomanBreaker`'s onRequest admitted, so onResponse/onError
only record outcomes for requests that actually ran its onRequest — same guard shape as
`dioman:loading:bracketed`). `DiomanTimeout` and `DiomanOffline` have NO internal `extra` keys —
timeout is stateless (writes directly to the request's timeout fields), offline keeps its queue as
instance state (the `_queue` list), not in `extra`.
`DiomanRetry` has no internal `extra` key of its own anymore — its whole retry loop lives inside
one onResponse/onError invocation now (see its bullet above), nothing needs to persist across
separate calls. `dioman:retry:reentry` is `DiomanShare`'s own internal marker (see its bullet), not
`DiomanRetry`'s — `DiomanRetry` writes it, but it's `DiomanShare`'s onRequest that reads and owns
the invariant.
Each is built as `'$_name:detail'` off that plugin's own `static const _name = 'dioman:<plugin>'`
(e.g. `cache_plugin.dart`: `static const _name = 'dioman:cache'; static const _kCacheKey =
'$_name:key';` and `String get name => _name;`) — never hand-typed as a second copy of the
literal. This also means an internal key can never collide with any plugin's `name` (a bare,
single-segment string like `dioman:cache`), since internal keys always carry a `:detail` suffix.
Internal keys stay `static const` local to their own plugin file — **do not** hoist them into a
shared cross-plugin constants file; that would recreate the coupling the self-contained-plugin
design avoids. There are no collisions — preserve that when adding a plugin.

## Cross-cutting rules when editing

- **All three re-issue mechanisms (retry, auth replay, share's own `policy=retry`) now use a
  throwaway, interceptor-less `Dio()`** — none re-enter this chain. This is uniform as of the
  bare-Dio retry redesign; don't reintroduce app-dio re-entry for any of them without re-reading the
  `DiomanRetry`/`DiomanShare` bullets above (it previously caused real bugs: cache poisoning, a
  share-reentry deadlock, a loading-counter flicker — each specifically traced to that choice).
- **handler.resolve vs next vs reject** is deliberate everywhere — cache/share/mock hits `resolve`
  (short-circuit); normalize failure `reject(...,true)`; retry/auth `resolve` on re-issue success and
  `next(original)` on failure.
- Adding a plugin: extend `DiomanPlugin`, give a unique `name`, read/write only your own `extra` keys,
  implement `dispose()` if you hold instance state, and slot it into the order by its request/
  response/error roles (document why in the README order table).
- **`Dioman.install` auto-wires `share`/`cancel`/`breaker` setters.** After `addAll`-ing the ordered
  plugin list, `install` does `if (share != null) { retry?.share = share; auth?.share = share; }`,
  the same for `cancel`, and `if (breaker != null) retry?.breaker = breaker;` — so callers going
  through `install` never need to touch the setters by hand. Hand-wiring (`retry.share = share`,
  `retry.breaker = breaker`) is only needed when adding plugins to `dio.interceptors` directly
  instead of through `install`.

## Verify workflow

```bash
cd D:/workspaces/dart-labs/dioman
dart analyze          # acceptance gate — must be "No issues found!"
# Fast loop while iterating — everything except the paced power-set sweep:
dart test test/dioman_test.dart test/dioman_combinations_test.dart test/dioman_coverage_test.dart
# Full acceptance gate before calling something done — includes dioman_powerset_test.dart's
# paced exception-path sweep, which is deliberately slow (~8 min) to stay under the local
# ephemeral-port budget (see that file's own doc). Must be "All tests passed!".
dart test
dart run example/dioman_example.dart   # exercise the wired chain (needs real network)
```

Always re-run `dart analyze` + `dart test` and update BOTH READMEs for any public API or ordering
change. New tests always go in one of the four files above, always against `test_server.dart`'s
real server — see the hard rule above.
