---
name: dioman
description: >-
  Work on dioman — composable, self-contained Dio interceptor plugins (auth, cache, retry, share/
  dedup, normalize, repath, filter, key, loading, cancel, envs, log), the transport-level
  DiomanMockAdapter, plus the correct install order. Pure Dart, dio-only, no Flutter. Read BEFORE modifying anything under lib/src/, adding a
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

Acceptance = **`dart analyze` clean** + `dart test` (layered under `test/unit|rule|boundary|combo|
integration/`, see `docs/guides/test-layers.md`; anything that sends requests runs against a REAL `dart:io HttpServer` via `test/support/
test_server.dart` — `TestServer.start(handler)` + `respondJson(req, data, status)` — never a
fake/mock `HttpClientAdapter` and never a hardcoded address like `127.0.0.1:1` for an
"unreachable" endpoint; this matters because it lets the interceptor-less `ReplayClient` re-issues
(auth replay, share/retry re-issues) actually reach the test server instead of the live internet, and keeps
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
simulated. This is a hard rule, not a style preference: it's what lets a `ReplayClient` re-issue
(auth replay, retry/share's own re-dispatch) actually land somewhere instead of silently no-op'ing
against a fake adapter that doesn't model per-instance `HttpClient` behavior — a bug in exactly
that interaction (cache/share's `resolve()` missing `callFollowingResponseInterceptor: true`) was
only caught because the coverage sweep used a real server end-to-end.

## The one idea everything follows from

**Dio is forward-order, NOT an onion.** `onRequest`, `onResponse`, and `onError` each iterate
interceptors in `dio.interceptors` **add order** (not reversed for the response phase). So a single
ordered list must satisfy request, response, AND error phases at once. Two rules make ordering
load-bearing:

1. A short-circuit — `handler.resolve()` from `onRequest` (cache hit / share follower) —
   **skips every following interceptor's `onRequest`, but still runs `onResponse` of interceptors
   placed AFTER the resolver.** Interceptors placed *before* the resolver never see the response.
2. The `onError` chain runs forward through every interceptor; the first to `resolve()` (auth-401
   replay, retry re-issue) **halts the rest**.

### Recommended order (and the hard constraints)

`envs → timeout → repath → filter → key → cache → offline → share → cancel →
loading → auth → retry → breaker → log → normalize`

`normalize` is LAST — optional, business-specific, not a transport concern (see its own bullet
below and its class doc). Every OTHER plugin therefore sees the response exactly as it came off
the wire, whether or not `normalize` is even installed.

- **timeout right after envs** — pure per-request config (rewrites connect/receive/send timeouts by
  network tier), no request/response coupling, so it sits at the very front alongside `envs`.
- **key before cache & share** — they key off `extra[kRequestKey]`; no key ⇒ they no-op (treat
  request as independent). This is a hard dependency.
- **retry only recovers requests its own onRequest admitted** (not an ordering constraint, but it
  decides what retry may touch). A result an upstream plugin short-circuited (a cache hit, a share
  follower, ...) still reaches `DiomanRetry.onResponse`/`onError` (resolve/reject with `true`), but
  retry never claimed that request (`claimRequest` runs in its onRequest, which the short-circuit
  skipped), so `_notAdmitted` passes it on as-is — no re-issue, no `onRetry`, no rewrite. A cached
  business failure is therefore never "recovered" by retry. Mocking is NOT part of this chain:
  `DiomanMockAdapter` sits at the transport, below every plugin (see its bullet), so retry replays a
  mocked 500 through the adapter again.
- **cache before offline** — an offline read that hits the cache short-circuits before `offline`
  can queue it (stale-cache-over-queue for reads).
- **offline before share/cancel/loading** — a parked (queued) request must NOT have created a share
  entry or opened a cancel/loading bracket, or those leak while it waits; parking happens by NOT
  calling `next` (see its bullet), so anything after it never ran its onRequest.
- **cache/share before cancel & loading** — a short-circuit skips following `onRequest`s, so a
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
  future, then replay. **Replay goes through the shared `ReplayClient`** (`lib/src/replay_support.dart`,
  also used by `DiomanRetry` and `DiomanShare`'s `policy=retry`; held as `_replay`, released in
  `dispose()`), which never re-enters the app dio's interceptor chain (no re-entry into auth):
  `ReplayClient.fetch` builds a fresh interceptor-less `Dio` that BORROWS the host dio's
  `httpClientAdapter`/`transformer` (custom proxy/cert/serialization stay consistent) — it is not
  closed, since the adapter belongs to the host — and only falls back to one lazily-created bare
  `Dio()` (closed in `dispose()`) when no host is bound. The host is bound through the plugin's `dio`
  setter, which `Dioman.install`/`DiomanHandle` call for you (`_bindHost` in `dioman.dart`; set it by
  hand only when wiring a chain yourself). Because the replay skips the chain, the recovered response
  is handed over MANUALLY: `ReplayClient.runDownstream` calls `onResponse` of every interceptor
  installed AFTER auth (normalize, breaker, log, ...; plus any `DiomanCache` installed before it), and
  `finishRecovered` then ends the chain with `handler.resolve`. A downstream `reject` is mapped back to
  dio's terminate (`reject(e)`) vs continue (`reject(e, true)`) semantics via `DownstreamReject`. So a
  replayed response is NOT cut off from later response handling — it is normalized like a first-time
  success. Cancel/share cooperation is claim-based, not setter-based: auth registers itself on each
  protected request in onRequest (`claimRequest` → `RequestClaims`, `extra['dioman:claims']`,
  `request_claims.dart`) and releases the claim only when it hands the final result off, so
  `DiomanShare` settles its entry (and `DiomanCancel` stops tracking the token) only after every
  claimant is done; `cancelAll()` therefore covers the refresh wait and the replay. The old `cancel`/
  `share` setters still exist but are `@Deprecated` no-ops. Before every replay (refresh or bare
  replay), `_injectToken` re-applies the CURRENT token (via `ready` or `buildHeader`) so a replay
  after a successful refresh doesn't carry the stale pre-refresh header. The `dioman:auth:refreshed`
  one-shot flag is the ONLY thing preventing an infinite refresh→401→refresh loop — never remove it.
  `defaultAuthFailure` distinguishes "I must refresh" from "someone already did" by comparing the
  request's carried token against the current store token — compared via the RAW token stashed in
  `extra['dioman:auth:tokenUsed']` at injection time (`_injectToken` stashes it UNCONDITIONALLY, whether
  the token went in via `ready` or `buildHeader`), not the formatted header (`buildHeader` may
  wrap it, e.g. `'Bearer $t'`, which would never equal the raw store token); it falls back to parsing
  the header only when no stash is present (the stash is cleared by `_clearFlags` on the auth exit
  paths). Both onRequest `reject()` calls
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
  `retries` times re-issuing via `ReplayClient.fetch` (interceptor-less `Dio` borrowing the host's
  adapter/transformer — see the auth bullet; callers never see individual retries); on success the
  result goes through `finishRecovered`, which hands it to the interceptors installed after share
  before ending the chain. The loop's success/exhaustion path is what settles the completer and removes
  the entry — do NOT `handler.resolve()`/`next()` without also doing both. **Remove-from-`_active` BEFORE
  `completer.complete`**, guarded by `identical()` so a new burst that already installed a fresher
  entry isn't clobbered. Each `_Entry`'s completer future carries a defensive `.ignore()` so a
  lone leader (no follower ever attached) or an already-settled end/race completer erroring doesn't
  raise an unhandled zone error. Gotcha: `dispose()` clears `_active` WITHOUT completing pending
  completers → waiters hang.
  **Leader-cancel takeover (`start` policy)**: each follower registers `{options, handler}` on the
  entry. When the leader is canceled and a follower with a non-cancelled token is alive, `_offer`
  calls `_promoteFollower`: it clears that follower's `dioman:share:joined` mark, `_adopt`s it onto
  the entry and `handler.next(options)`s it, so it re-enters the WHOLE downstream chain with its own
  options (cancel injects its token, auth/retry recover 401/500, its own FormData is unconsumed).
  Its final result settles the entry through the claims registry; if it is canceled too, the next
  live follower is promoted, and with none left the entry settles as canceled and is detached. The
  promoted follower's `completer.future.then` callback must skip (`promoted` flag) — a handler can
  complete once. There is NO bare-transport takeover any more; don't reintroduce one.
  **Deferred settlement for DiomanRetry/DiomanAuth** (per-request claims, `request_claims.dart`):
  because this plugin sits BEFORE retry/auth in the chain, its own onResponse/onError would
  otherwise settle a shared entry with the FIRST attempt's outcome — before retry/auth ever get a
  chance to recover it — stranding any follower with a stale pre-retry/pre-refresh result even
  though the leader itself goes on to succeed. Fix: `_adopt` creates a `RequestClaims` on the request
  (`extra['dioman:claims']`, `onFinal` → `_offer`), and `DiomanAuth`/`DiomanRetry` register themselves
  on it in their own onRequest (`claimRequest`). `_finishOrDefer` settles on the spot only when no
  claimant remains; otherwise it waits, and the entry settles when the last claimant hands its final
  result off (`releaseClaim`/`handOff*`) or ends the chain (`claims.finish`). Responsibility travels
  WITH the request, not with a plugin-level counter, so removing/rebinding a plugin leaves nothing
  dangling and there is no `share` wiring to do — the `share` setters on retry/auth and share's
  `registerDownstreamSettler()`/`hasMultipleDownstreamSettlers` are `@Deprecated` no-ops kept for
  compatibility (a bare counter that influences nothing). A request that `kJoinedKey`-marks itself
  (follower/loser) never recovers on its own — the leader's settlement is delivered instead.
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
  `onResponse` of everything installed after cache (offline, share, cancel, loading, auth, retry, log,
  normalize), same as a real response; dropping it would make a cache hit skip `DiomanNormalize`
  entirely (a real, previously-shipped bug — a cache hit returned the raw envelope even with
  `normalize` installed, while a live response correctly got unwrapped). `DiomanRetry.onResponse`
  runs for it too but passes it on untouched: retry never admitted a cache hit (see the Gotcha below).
  Never stores responses carrying `x-dioman-mock` (unconditional veto before user shouldStore).
  Stores only **2xx** `response.data` that also passes `shouldStore` (per-request > plugin > the
  normalize judge wired at install > none), RAW (not normalize-unwrapped — `normalize` runs LAST, after
  this plugin; see the order note above). `CacheClone` (`none`/`shallow`/`deep`) is applied **on
  read**, not write — the store holds the live `response.data` reference, so a `none` reader mutating
  the result corrupts the cache. Default `shouldCache` = GET only. Bounded by `maxEntries` (default
  500, `0` disables the cap) — LRU-evicted via remove-then-reinsert on write (Dart's default `Map` is
  insertion-ordered, so `_store.keys.first` is always the least-recently-written entry); without this,
  deep `DiomanKey` keys that vary per query/body (paginated/search endpoints) would accumulate
  forever since an entry is otherwise only removed when its *exact* key is re-requested after expiry.
  Gotcha this plugin does NOT fully solve: it has no concept of "business failure" — a 200 that
  `DiomanRetry.shouldRetry` considers a failure still gets cached here (this plugin runs
  first), so a LATER, unrelated caller for the same key still hits the poisoned entry and gets it
  back AS-IS: the cache hit short-circuits before `DiomanRetry.onRequest`, retry never admitted that
  request, so it does not recover or rewrite it (it used to, via the cache hit's following-chain
  `onResponse`; that was a side effect of the unguarded retry bug, not a feature). Keeping business
  failures out of the cache is the cache layer's job: `shouldStore`, or the normalize judge
  `Dioman.install` wires into it. The recovery re-issue of a request retry DID admit runs on an
  interceptor-less `Dio` (`ReplayClient.fetch`), so it never READS this plugin; but
  `ReplayClient.runDownstream` also calls `onResponse` of any `DiomanCache` installed BEFORE the
  replayer, so the recovered result goes through this plugin's normal store rules (2xx +
  `shouldStore`) like any other response.
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
  per-field override), not just the options object. **Re-issues via the shared `ReplayClient`**
  (`replay_support.dart`, held as `_replay`, released in `dispose()`; `_reissue` calls
  `_replay.fetch`): an interceptor-less `Dio` that borrows the host dio's `httpClientAdapter`/
  `transformer` (bound via the `dio` setter by `Dioman.install`/`DiomanHandle`; one lazily-created bare
  `Dio()` when unbound) — same pattern as auth/share-retry, and it never re-enters the app dio's
  chain (re-entering is what previously caused the cache-poisoning and share-reentry-deadlock bugs —
  see git history for the trade-off analysis; don't change it back). Because the re-issue never
  re-enters this chain, the WHOLE retry loop (up to `max` attempts) has to live inside ONE
  onResponse/onError invocation — an explicit `for` loop, re-checking `shouldRetry`
  against EVERY subsequent attempt's own outcome (do not "simplify" this back to a single-shot
  `_reissue` + rely on recursion; there is no recursion anymore, the loop IS the retry mechanism).
  No more `extra['dioman:retry:count']` — state doesn't need to persist across separate onError
  invocations now that there's only ever one per top-level failure. `shouldRetry` always sees
  the RAW response body (`normalize`, if used, is LAST — see order note above — so it never runs
  before this plugin). Share/cancel cooperation is claim-based: when `_mayRetry` says the request can be
  retried, onRequest registers this plugin on the request (`claimRequest` → `RequestClaims`) and it
  hands off only once the request's true final outcome is known, so `DiomanShare` never settles with a
  pre-retry result and `DiomanCancel` keeps tracking the token through back-off waits. The old `share`/
  `cancel` SETTERS are `@Deprecated` no-ops (nothing to wire). **That claim doubles as the
  "I admitted this request" proof**: `_notAdmitted(config)` (= `claimsOf(config)?.has(this) != true`)
  gates both `_handleResponse` and `_handleError` — a request without this plugin's claim (upstream
  short-circuit by a cache hit/..., or one `_mayRetry` rejected) is handed on untouched. It replaced
  the old `_unclaimedUnderShare` guard, which only fired when a share registry existed and so missed
  every no-share chain; do NOT test "is there a registry" instead of "is retry in it", and do not add
  a separate extra key for this. A retried response carries whatever auth
  header the ORIGINAL attempt had (retry re-issues the same `RequestOptions`; auth's own recovery is
  reached through `claims.recoverAuth` on a 401), and a recovered result IS handed to the interceptors
  installed after retry (breaker, log, normalize...) by `ReplayClient.runDownstream`, so it is
  normalized like a first-time success; interceptors installed BEFORE retry (other than a `DiomanCache`)
  are not re-run for it (see the class doc's trade-off list). If the request is canceled while auth recovery (`claims.recoverAuth`) is waiting on a refresh,
  `_reissue` throws the token's cancel error rather than rethrowing the original 401 (and the
  response path routes it to `_failCanceled`), so share sees a cancel and can promote a follower.
  Optional `onRetry: (attempt) {}` callback is a
  lightweight substitute for the logging the re-issue no longer passes through `DiomanLog` for.
- **DiomanBreaker** (`breaker_plugin.dart`, `name: 'dioman:breaker'`). Circuit breaker, one `_Bucket`
  per `METHOD:path` key (override via `keyBuilder`; default reuses `DiomanKey`'s fast-key scheme,
  computed independently — does NOT read `extra[kRequestKey]`). State machine `closed → open →
  halfOpen`: `failureThreshold` (default 10) CONSECUTIVE failures trip closed→open (any success
  resets the count); open rejects fast in `onRequest` (no network) until `resetDuration` (default
  30s) elapses, then admits up to `halfOpenMaxCalls` (default 3) probes — ONE probe success →
  closed, ONE probe failure → open (cooldown restarts). **Installed AFTER retry** (with `DiomanRetry.breaker` wired by `install`, retry records each real
  attempt and takes a fresh admission only AFTER `prepareForReplay` succeeds — taking it first would
  let a non-replayable body (Stream) break out holding an unused admission that the final error
  then records a second time), so it only ever
  records each top-level request's FINAL outcome (retry re-issues via the interceptor-less
  `ReplayClient` Dio, which never re-enters this chain's onRequest; the recovered result reaches this
  plugin's onResponse once as the request's final outcome → each request counted exactly once). `onRequest` marks the admitted request via
  `extra['dioman:breaker:key']`; `onResponse`/`onError` only record an outcome when that mark is
  present — a cache short-circuit runs `onResponse` WITHOUT having run this plugin's
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
  Per-attempt accounting goes through the public handler-free API: `admit(options)` takes a fresh
  admission ticket before a re-issue, `recordResponse`/`recordError` consume it (no ticket ⇒ no-op,
  so the final outcome reaching the chain's `onResponse`/`onError` is never counted twice). The
  interceptor methods are thin wrappers over these; never fake a handler to call them.
  `dispose()`/`reset()` clear all buckets; no timers, no parked handlers.
- **DiomanKey** (`key_plugin.dart`, `name: 'dioman:qid'`, `const` ctor). Exports
  `const kRequestKey = 'dioman:key'` — fixed, cross-plugin protocol key (key writes, cache/share
  read), a DIFFERENT string from the plugin's own `name` (`'dioman:qid'`) on purpose, so the
  caller-facing override and the internal wire-protocol slot can never collide. A
  `DiomanKeyOptions(enabled: false)` at `extra['dioman:qid']` ⇒ no key written (request treated
  independent by cache/share); `DiomanKeyOptions(key: '...')` overrides the computed key outright.
  fast = `METHOD:uri.path`; deep also folds **sorted** query params + body. `_encode` sorts map
  keys for determinism — breaking the sort breaks cache/share hit correctness.
- **DiomanMockAdapter** (`mock_adapter.dart`, not a DiomanPlugin). Wrap `dio.httpClientAdapter`
  with `inner: dio.httpClientAdapter`; never pass to Dioman.install. No chain ordering constraints.
  Install ONLY in development/test flavors (pure Dart cannot detect release mode). `enabled=true`
  by default. Owns MockHandler/MockFallbackDecider/defaultFallback/DiomanMockOptions (all defined
  in `mock_adapter.dart`). Per-request override key is the public const `DiomanMockAdapter.extraKey`
  (`'dioman:mock'`): a `DiomanMockOptions` merges routes and overrides scalars; bare `false` also
  disables the adapter. It is not a plugin, so the key registry lists it with owner
  `DiomanExtraKeys.mockAdapterOwner` (the class name) instead of a plugin name.
  Inline routes use METHOD:uri.path. Otherwise forward rewritten path/query to mockUrl using inner;
  fallback reuses original options and inner. Buffer request streams in memory for two sends.
  Raw HTTP responses go through Dio decoding/validateStatus; fallbackWhen receives response with
  raw ResponseBody data (default fallback only for 404), or error for transport failures. HTTP 500
  is not an adapter transport exception: retry handles it and replays through this adapter again.
  Auth replays also traverse it; share can merge mock requests. Upstream cache/offline may stop or
  park requests before the adapter. Being below `share`, concurrent identical requests merge before
  reaching it (one mock probe, not N); being below `cache`, a real fallback response is cached like
  any real response, and a mock response is never cached (marker veto).
  Inline handlers race cancelFuture; inner receives cancelFuture; close forwards force to inner.
  Inline/non-fallback forwarding adds public markerHeader = x-dioman-mock with value 1. Real
  passthrough/fallback adds no marker. Cache MUST veto any marked response BEFORE shouldStore,
  even a user callback cannot allow it. Existing real cache reads are unchanged.
- **Cancel/Loading brackets** (`cancel_plugin.dart` `name: 'dioman:cancel'`, `loading_plugin.dart`
  `name: 'dioman:loading'`). Both hook all three of onRequest/onResponse/onError to survive short-circuits.
  Cancel injects a `CancelToken` only if the request lacks one, and sets `token.requestOptions =
  options` right after (see next paragraph for why) — the `existing != null` branch (re-registering
  a token this plugin itself injected, checked via `extra['dioman:cancel:token'] == existing`)
  exists for a `RequestOptions` object that re-enters this SAME onRequest a second time (e.g. a
  caller manually re-dispatching it through this same Dio); none of `DiomanRetry`/`DiomanAuth`/
  `DiomanShare`'s own internal re-issues hit it anymore (all three go through `ReplayClient`'s
  interceptor-less Dio that never reaches this onRequest) — they stay trackable instead because they
  HOLD the request via its `RequestClaims`: `_release` doesn't untrack the token while claimants remain
  (`claims.hasOwners`), it registers `claims.whenDrained(...)` and untracks only when the logical
  request's final result is out (and, for a share loser still waiting on the winner, after that
  delivery). The public `track(token)`/`untrack(token)` remain for CUSTOM plugins that re-dispatch
  through an interceptor-less client; `DiomanRetry`/`DiomanAuth`'s `cancel` setters are deprecated
  no-ops. `cancelAll([reason])` + top-level
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
  that incremented — needed because a cache/share hit resolving with
  `callFollowingResponseInterceptor: true` runs loading's `onResponse` even though loading's own
  `onRequest` (later in the chain) never got to run for that short-circuited request; a plain
  `DiomanLoadingOptions(enabled: false)` recheck (or a disabled constructor-level `enabled`) would
  otherwise decrement an unrelated in-flight request's counter if not gated correctly. `dispose()`
  force-resets to 0 and fires `onChanged(false)`. `DiomanLoadingOptions` also carries an `onChanged`
  field mirroring the constructor param, for structural symmetry only — never read per-request
  (overriding the shared counter's callback for one call would desync increment/decrement).
- **DiomanEnvs** (`envs_plugin.dart`, `name: 'dioman:envs'`). Install-time only (`onRequest` no-op). `apply(dio)` runs
  ONLY from the constructor when `dio:` is passed, or when the caller invokes it — `Dioman.install`/
  `DiomanHandle` never call it (a `DiomanEnvs(rules)` without `dio:` and without a manual `apply` does
  nothing). First matching `EnvRule` wins. `apply` only overwrites `responseType` when the rule's `BaseOptions`
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
`dioman:qid`, `DiomanCache` → `dioman:cache`, `DiomanShare` → `dioman:share`, `DiomanLoading` → `dioman:loading`, `DiomanLog` → `dioman:log`, `DiomanRetry` →
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
separate calls. The old `dioman:retry:reentry` marker no longer exists. The cross-plugin settlement
keys live in `request_claims.dart` (internal, not exported): `kClaimsKey` = `'dioman:claims'` (the
per-request `RequestClaims` registry — share creates it in `_adopt`, auth/retry claim on it, cancel
reads it) and `kJoinedKey` = `'dioman:share:joined'` (marks a share follower/loser that must not
recover on its own).
Each is built as `'$_name:detail'` off that plugin's own `static const _name = 'dioman:<plugin>'`
(e.g. `cache_plugin.dart`: `static const _name = 'dioman:cache'; static const _kCacheKey =
'$_name:key';` and `String get name => _name;`) — never hand-typed as a second copy of the
literal. This also means an internal key can never collide with any plugin's `name` (a bare,
single-segment string like `dioman:cache`), since internal keys always carry a `:detail` suffix.
Internal keys stay `static const` local to their own plugin file — **do not** hoist them into a
shared cross-plugin constants file; that would recreate the coupling the self-contained-plugin
design avoids. There are no collisions — preserve that when adding a plugin.

## Cross-cutting rules when editing

- **All three re-issue mechanisms (retry, auth replay, share's own `policy=retry`) go through the
  shared `ReplayClient` (`lib/src/replay_support.dart`)** — an interceptor-less `Dio` that borrows the
  host dio's `httpClientAdapter`/`transformer` (bare `Dio()` fallback when unbound), so none re-enter
  this chain's `onRequest`. The recovered result is then handed MANUALLY to the `onResponse` of the
  interceptors installed after the replayer (`runDownstream`, plus any earlier `DiomanCache`) and the
  chain is ended by `finishRecovered`, so a replayed response is NOT cut off from later response
  handling. Don't reintroduce app-dio re-entry for any of them without re-reading the
  `DiomanRetry`/`DiomanShare` bullets above (it previously caused real bugs: cache poisoning, a
  share-reentry deadlock, a loading-counter flicker — each specifically traced to that choice).
- **handler.resolve vs next vs reject** is deliberate everywhere — cache/share hits `resolve`
  (short-circuit); normalize failure `reject(...,true)`; retry/auth `resolve` on re-issue success and
  `next(original)` on failure.
- Adding a plugin: extend `DiomanPlugin`, give a unique `name`, read/write only your own `extra` keys,
  implement `dispose()` if you hold instance state, and slot it into the order by its request/
  response/error roles (document why in the README order table).
- **Cross-plugin wiring lives in one place: `_wireChain` / `_unwire` in `lib/src/dioman.dart`.**
  `installPlugins` and every `DiomanHandle` insert/prepend/append/remove/dispose call them, so the
  wiring always matches the current chain:
  - retry ↔ breaker: a breaker on the chain is assigned to `retry.breaker`; when there is none,
    `retry.breaker` is left alone (a hand-wired external breaker survives). `_unwire` clears only
    references to the plugin being removed.
  - cache ↔ normalize: with a normalize on the chain, cache gets normalize's own "would reject"
    judge (shared code, `_resolveEnvelope`) so HTTP 200 business failures are not stored; removed
    when normalize leaves. A user `shouldStore` (plugin or per request) always wins.
  - host binding: `_bindHost` assigns the host dio to `share`/`auth`/`retry` via their `dio` setter so
    their `ReplayClient` borrows its adapter/transformer.
  - `share`/`cancel` setters on retry/auth, and share's `registerDownstreamSettler()` /
    `hasMultipleDownstreamSettlers`, are `@Deprecated` no-ops — settlement and cancel tracking are
    claim-based (`RequestClaims`), so there is nothing to wire.
  Adding a new cross-plugin link: put it in `_wireChain`, undo it in `_unwire`, never in a constructor.

## Verify workflow

```bash
cd D:/workspaces/dart-labs/dioman
dart analyze          # acceptance gate — must be "No issues found!"
# Fast loop while iterating — every layer except combo (which holds the paced power-set sweep):
dart test test/unit test/rule test/boundary test/integration
# Full acceptance gate before calling something done — includes combo/powerset_combo_test.dart's
# paced exception-path sweep, which is deliberately slow (~8 min) to stay under the local
# ephemeral-port budget (see that file's own doc). Must be "All tests passed!".
dart test
dart run example/dioman_example.dart   # exercise the wired chain (needs real network)
```

Always re-run `dart analyze` + `dart test` and update BOTH READMEs for any public API or ordering
change. New tests always go in one of the four files above, always against `test_server.dart`'s
real server — see the hard rule above.
