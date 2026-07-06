---
name: dioman
description: >-
  Work on dioman — composable, self-contained Dio interceptor plugins (auth, cache, retry, share/
  dedup, mock, normalize, repath, reqclean, reqkey, loading, cancel, envs, log) plus the correct install
  order. Pure Dart, dio-only, no Flutter. Read BEFORE modifying anything under lib/src/, adding a
  plugin, or reordering the chain. Covers the forward-order execution model, the install-order
  constraints, per-plugin implementation invariants, the extra[...] key registry, and how to verify.
  Triggers on: dio, interceptor, DioPlugin, auth token refresh/401 replay, cache TTL, request dedup/
  share, retry back-off, mock fallback, envelope normalize, ApiException, ITokenManager, install order.
---

# dioman

Pure-Dart package (`dio: ^5.0.0` only, **no Flutter**, SDK `^3.5.0`). A set of **self-contained
Dio interceptor plugins**, each extending `DioPlugin` (a named `Interceptor` with `String get name`
and a `dispose()` hook — `lib/src/dio_plugin.dart`), PLUS the documented correct install order.
Entry `lib/dioman.dart` re-exports all 13 plugins. Each plugin lives in its own `lib/src/*.dart`.

Acceptance = **`dart analyze` clean** + `dart test` (a `test/dioman_test.dart` suite exists, using a
fake `HttpClientAdapter` — no real network needed) + the runnable `example/dioman_example.dart`
(needs real network; expect it to fail offline). The two READMEs (`README.md` EN, `README.zh-CN.md`
ZH) are the canonical spec and are extremely detailed — read the relevant section before changing
behavior, and keep both in sync on any public API change.

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

`envs → repath → reqclean → reqkey → normalize → cache → share → mock → cancel →
loading → auth → retry → log`

- **reqkey before cache & share** — they key off `extra['_key']`; no key ⇒ they no-op (treat
  request as independent). This is a hard dependency.
- **normalize before cache** — cache must store/return the *unwrapped* payload; `normalize` mutates
  `response.data` in place on success, so anything after it sees the payload not the envelope.
- **normalize before auth** — auth assumes a business error already arrived as a `DioException`.
- **cache/share/mock before cancel & loading** — a short-circuit skips following `onRequest`s, so a
  bracket (increment/inject) placed *before* the resolver would fire on request and never clean up.
- **cancel & loading before auth & retry** — on a 401 (auth) or network retry, those `resolve()` the
  error and halt the forward `onError` chain; the brackets must already have run (counter
  decremented, token released) by then.

## Per-plugin implementation invariants (do NOT break)

- **AuthPlugin** (`auth_plugin.dart`, `name: 'auth'`). Single refresh window = a shared
  `Future<bool>? _refreshing` installed via `_refreshing ??= (() async {…})()` (the `??=` is the
  atomicity trick; `finally { _refreshing = null }` reopens it). Concurrent 401s join the one
  future, then replay. **Replay re-issues via a throwaway `Dio().fetch(opts)`** — NOT the app dio —
  so replays deliberately bypass the whole interceptor chain (no re-entry into auth); this also means
  a replayed response bypasses normalize (envelope stays wrapped) — a known, accepted trade-off of
  that design, not something replay tries to fix. Before every replay (refresh or bare replay),
  `_injectToken` re-applies the CURRENT token (via `ready` or `buildHeader`) so a replay after a
  successful refresh doesn't carry the stale pre-refresh header. The `__auth_refreshed` one-shot flag
  is the ONLY thing preventing an infinite refresh→401→refresh loop — never remove it.
  `defaultAuthFailure` distinguishes "I must refresh" from "someone already did" by comparing the
  request's carried token against the current store token — compared via the RAW token stashed in
  `extra['__auth_token_used']` at injection time, not the formatted header (`buildHeader` may wrap it,
  e.g. `'Bearer $t'`, which would never equal the raw store token); falls back to parsing the header
  only when a custom `ready` callback bypassed the stash. Both onRequest `reject()` calls
  (refresh-in-progress-failed, no-token-denied) pass `callFollowingErrorInterceptor: true` so
  brackets installed before auth (cancel/loading/share) still get their `onError` to release state —
  the default `false` would skip the entire error chain and leak them. 5 `AuthFailureAction`s:
  `refresh/replay/deny/expired/others`. `ITokenManager` interface: `accessToken`, `refreshToken`,
  `canRefresh`, `clear()` (note: only `accessToken`/`clear` are read; refresh is delegated to the
  `onRefresh` callback). Default: **every request protected** unless `extra['protected']==false` /
  `isProtected` says otherwise. Auth's `__`-prefixed extra constants are plain strings on purpose so
  they survive Dio's `mergeConfig` on replay.
- **SharePlugin** (`share_plugin.dart`, `name: 'share'`). Completer-per-`_key` in `_active`, referenced
  directly off each request via `extra['_share_entry']` (not re-looked-up from `_active` in
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
  completers → waiters hang. **Known separate issue (not fixed, pre-existing)**: a concurrent
  follower attached via `_handleStart`'s onRequest-side `RequestInterceptorHandler.reject()` hangs
  forever when the shared request ultimately errors, even though the leader and the shared completer
  both settle correctly — reproduced with the original unmodified code too, so it predates any of
  this file's fixes. Root cause not yet isolated; avoid relying on `start`/`retry` followers
  observing an error until this is investigated.
- **CachePlugin** (`cache_plugin.dart`, `name: 'cache'`). TTL store keyed by `extra['_key']`, TTL in
  **milliseconds** (default 60000). Hit ⇒ `handler.resolve(Response(...,'OK (cached)'))`. Stores only
  **2xx** `response.data` (post-normalize). `CacheClone` (`none`/`shallow`/`deep`) is applied **on
  read**, not write — the store holds the live `response.data` reference, so a `none` reader mutating
  the result corrupts the cache. Default `shouldCache` = GET only. Bounded by `maxEntries` (default
  500, `0` disables the cap) — LRU-evicted via remove-then-reinsert on write (Dart's default `Map` is
  insertion-ordered, so `_store.keys.first` is always the least-recently-written entry); without this,
  deep `ReqkeyPlugin` keys that vary per query/body (paginated/search endpoints) would accumulate
  forever since an entry is otherwise only removed when its *exact* key is re-requested after expiry.
- **NormalizePlugin** (`normalize_plugin.dart`, `name: 'normalize'`, `const` ctor, `onResponse`
  only). Default detects an envelope by `data is Map && containsKey(codeKey)`; success (`code==0`)
  ⇒ mutates `response.data = envelope[dataKey]` in place; failure ⇒
  `handler.reject(DioException(error: ApiException(code,message,data)), true)` — **the trailing
  `true` ("call following error interceptors") is required** so retry/auth see the converted business
  error; dropping it stops error propagation. `ApiException implements Exception` with
  `code`/`message`/`data`.
- **RetryPlugin** (`retry_plugin.dart`, `name: 'retry'`). Back-off `1000*(1<<attempt)` ms = 1s/2s/4s.
  Default `retryIf` = timeouts + connectionError + `statusCode>=500 && !=501`. **Re-issues via the
  INJECTED app `_dio.fetch` (re-runs the full chain)** — unlike auth/share which use a throwaway Dio.
  On reaching `max` it resets `extra['_retry_count']` to 0 (so reusing the same `RequestOptions`
  starts fresh). `extra['retry']==false` is honored on BOTH the onResponse (business-retry) and
  onError (network-retry) paths. After the back-off delay and before re-fetching, checks
  `config.cancelToken?.isCancelled` and gives up immediately rather than issuing a doomed network
  call. Business-retry (`isExceptionRequest` on a 2xx) can't fire in the recommended order because
  `normalize` unwraps before retry sees the body — move retry ahead of normalize to enable it (and
  pair with `extra['loading']=false` to avoid the bracket leak).
- **ReqkeyPlugin** (`reqkey_plugin.dart`, `name: 'reqkey'`, `const` ctor). Exports
  `const kRequestKey = '_key'`. `extra['key']==false` ⇒ no key written (request treated independent
  by cache/share). fast = `METHOD:uri.path`; deep also folds **sorted** query params + body.
  `_encode` sorts map keys for determinism — breaking the sort breaks cache/share hit correctness.
- **MockPlugin** (`mock_plugin.dart`, `name: 'mock'`). `enabled=false` ⇒ passthrough. Route key
  `'METHOD:${options.uri.path}'` — matches `ReqkeyPlugin`'s fast-key scheme (resolved path, not the
  raw `options.path`, so absolute-URL and baseUrl-relative requests key consistently). Inline handler
  → decodes the returned `ResponseBody` via a shared `FusedTransformer` (mirroring what dio's own
  dispatch path does) before resolving — constructing the `Response` straight from the raw
  `ResponseBody` would leave `.data` holding the undecoded stream wrapper instead of parsed JSON.
  Both inline-handler and mock-server-redirect resolves pass `callFollowingResponseInterceptor: true`
  so a mock hit still runs `onResponse` of normalize/cache/share (installed earlier in the chain) —
  without it, a mock hit would skip normalize's envelope unwrap and leave a `SharePlugin` entry
  permanently unsettled. Mock-server redirect clears `queryParameters` on the rewritten
  `RequestOptions` — `_rewriteUrl` already folds the original query string into the path, so leaving
  the map populated would make dio append it a second time. Else redirect to `mockUrl` via a fresh
  `Dio`; on 404/network (per `defaultFallback`) → `handler.next(options)` falling back to the REAL API
  with original options. Never falls back on user `cancel`.
- **Cancel/Loading brackets** (`cancel_plugin.dart` `name: 'cancel'`, `loading_plugin.dart`
  `name: 'loading'`). Both hook all three of onRequest/onResponse/onError to survive short-circuits.
  Cancel injects a `CancelToken` only if the request lacks one **it didn't itself inject before** —
  `RetryPlugin` re-dispatches through the full chain reusing the same `RequestOptions`/`CancelToken`,
  and `_release` deregisters that token after each failed attempt, so onRequest re-registers it
  (checked via `extra['_cancel_token'] == options.cancelToken`) rather than treating it as
  user-supplied and leaving it untracked for the rest of the retries; `cancelAll([reason])` + top-level
  `cancelAll(dio,[reason])`; `dispose()` cancels all. Loading is a 0↔1 edge-triggered counter calling
  `onChanged(bool)`; increment marks the request as bracketed via `extra['_loading_bracketed']` and
  decrement only fires if that request was actually the one that incremented — needed because a mock
  hit resolving with `callFollowingResponseInterceptor: true` runs loading's `onResponse` even though
  loading's own `onRequest` (later in the chain) never got to run for that short-circuited request; a
  plain `extra['loading']!=false` recheck would decrement an unrelated in-flight request's counter.
  `dispose()` force-resets to 0 and fires `onChanged(false)`.
- **EnvsPlugin** (`envs_plugin.dart`, `name: 'envs'`). Install-time only (`onRequest` no-op). First
  matching `EnvRule` wins. `apply` only overwrites `responseType` when the rule's `BaseOptions`
  explicitly sets something other than the `ResponseType.json` default — since `responseType` is
  non-nullable, `json` is treated as "not intentionally set" (same convention as every other guarded
  field), so a rule that only configures e.g. `baseUrl` no longer silently resets a user-configured
  `bytes`/`stream` responseType back to json. Known limitation: a rule that genuinely WANTS to reset
  responseType to json is indistinguishable from "didn't set it" — there's no sentinel for that.
- **LogPlugin** (`log_plugin.dart`, `name: 'log'`). Dependency-free; `print` by default, `writer` to
  route elsewhere.

## The `extra[...]` key registry (single source of coordination)

User-facing (per-request overrides): `protected` (auth), `key` (reqkey), `cache`, `share`,
`mock`, `loading`, `log`, `retry`, `filter` (reqclean), `repath`, `normalize`.
Internal (do not collide): `_key`, `_cache_key`/`_cache_ttl`/`_cache_clone`,
`_share_entry`/`_share_seq`/`_share_policy`/`_share_retries_left`, `_retry_count`, `_cancel_token`,
`_loading_bracketed`,
`__auth_decision`/`__auth_protected`/`__auth_refreshed`/`__auth_denied`/`__auth_token_used`. There
are no collisions — preserve that when adding a plugin.

## Cross-cutting rules when editing

- **Re-issue instance matters**: retry uses the app dio (re-enters chain); auth & share-retry use a
  throwaway `Dio()` (no re-entrancy). Changing either alters semantics.
- **handler.resolve vs next vs reject** is deliberate everywhere — cache/share/mock hits `resolve`
  (short-circuit); normalize failure `reject(...,true)`; retry/auth `resolve` on re-issue success and
  `next(original)` on failure.
- Adding a plugin: extend `DioPlugin`, give a unique `name`, read/write only your own `extra` keys,
  implement `dispose()` if you hold instance state, and slot it into the order by its request/
  response/error roles (document why in the README order table).

## Verify workflow

```bash
cd D:/workspaces/dart-labs/dioman
dart analyze          # acceptance gate — must be "No issues found!"
dart test             # fake-adapter regression suite — must be "All tests passed!"
dart run example/dioman_example.dart   # exercise the wired chain (needs real network)
```

Always re-run `dart analyze` + `dart test` and update BOTH READMEs for any public API or ordering
change.
