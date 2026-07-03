---
name: dioplus
description: >-
  Work on dioplus — composable, self-contained Dio interceptor plugins (auth, cache, retry, share/
  dedup, mock, normalize, repath, build-key, loading, cancel, envs, log) plus the correct install
  order. Pure Dart, dio-only, no Flutter. Read BEFORE modifying anything under lib/src/, adding a
  plugin, or reordering the chain. Covers the forward-order execution model, the install-order
  constraints, per-plugin implementation invariants, the extra[...] key registry, and how to verify.
  Triggers on: dio, interceptor, DioPlugin, auth token refresh/401 replay, cache TTL, request dedup/
  share, retry back-off, mock fallback, envelope normalize, ApiException, ITokenManager, install order.
---

# dioplus

Pure-Dart package (`dio: ^5.0.0` only, **no Flutter**, SDK `^3.5.0`). A set of **self-contained
Dio interceptor plugins**, each extending `DioPlugin` (a named `Interceptor` with `String get name`
and a `dispose()` hook — `lib/src/dio_plugin.dart`), PLUS the documented correct install order.
Entry `lib/dioplus.dart` re-exports all 13 plugins. Each plugin lives in its own `lib/src/*.dart`.

**No test suite exists** (no `test/` dir). Acceptance = **`dart analyze` clean** + the runnable
`example/dioplus_example.dart`. The two READMEs (`README.md` EN, `README.zh-CN.md` ZH) are the
canonical spec and are extremely detailed — read the relevant section before changing behavior, and
keep both in sync on any public API change.

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

`envs → repath → normalize-request → build-key → normalize → cache → share → mock → cancel →
loading → auth → retry → log`

- **build-key before cache & share** — they key off `extra['_key']`; no key ⇒ they no-op (treat
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
  so replays deliberately bypass the whole interceptor chain (no re-entry into auth). The
  `__auth_refreshed` one-shot flag is the ONLY thing preventing an infinite refresh→401→refresh
  loop — never remove it. `defaultAuthFailure` distinguishes "I must refresh" from "someone already
  did" by comparing the request's carried token against the current store token. 5
  `AuthFailureAction`s: `refresh/replay/deny/expired/others`. `ITokenManager` interface:
  `accessToken`, `refreshToken`, `canRefresh`, `clear()` (note: only `accessToken`/`clear` are read;
  refresh is delegated to the `onRefresh` callback). Default: **every request protected** unless
  `extra['protected']==false` / `isProtected` says otherwise. Auth's `__`-prefixed extra constants
  are plain strings on purpose so they survive Dio's `mergeConfig` on replay.
- **SharePlugin** (`share_plugin.dart`, `name: 'share'`). Completer-per-`_key` in `_active`. No key
  ⇒ pass through independent. Followers attach to `entry.completer.future` and never hit the
  network. `start`/`retry`: one leader, rest wait. `end`: all run, only the highest `seq` settles the
  shared promise. `race`: all run, first success settles, `inFlight` counts down for the
  last-error-settles case. `retry`: re-issues via throwaway `Dio().fetch` (callers never see
  retries). **Remove-from-`_active` BEFORE `completer.complete`** so a new burst during completion
  callbacks starts a fresh entry. Gotcha: `dispose()` clears `_active` WITHOUT completing pending
  completers → waiters hang.
- **CachePlugin** (`cache_plugin.dart`, `name: 'cache'`). TTL store keyed by `extra['_key']`, TTL in
  **milliseconds** (default 60000). Hit ⇒ `handler.resolve(Response(...,'OK (cached)'))`. Stores only
  **2xx** `response.data` (post-normalize). `CacheClone` (`none`/`shallow`/`deep`) is applied **on
  read**, not write — the store holds the live `response.data` reference, so a `none` reader mutating
  the result corrupts the cache. Default `shouldCache` = GET only.
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
  starts fresh). Business-retry (`isExceptionRequest` on a 2xx) can't fire in the recommended order
  because `normalize` unwraps before retry sees the body — move retry ahead of normalize to enable
  it (and pair with `extra['loading']=false` to avoid the bracket leak).
- **BuildKeyPlugin** (`build_key_plugin.dart`, `name: 'build-key'`, `const` ctor). Exports
  `const kRequestKey = '_key'`. `extra['key']==false` ⇒ no key written (request treated independent
  by cache/share). fast = `METHOD:uri.path`; deep also folds **sorted** query params + body.
  `_encode` sorts map keys for determinism — breaking the sort breaks cache/share hit correctness.
- **MockPlugin** (`mock_plugin.dart`, `name: 'mock'`). `enabled=false` ⇒ passthrough. Route key
  `'METHOD:${options.path}'` (uses `options.path`, not `uri.path` — asymmetric with build-key).
  Inline handler → resolve; else redirect to `mockUrl` via a fresh `Dio`; on 404/network (per
  `defaultFallback`) → `handler.next(options)` falling back to the REAL API with original options.
  Never falls back on user `cancel`.
- **Cancel/Loading brackets** (`cancel_plugin.dart` `name: 'cancel'`, `loading_plugin.dart`
  `name: 'loading'`). Both hook all three of onRequest/onResponse/onError to survive short-circuits.
  Cancel injects a `CancelToken` only if the request lacks one; `_release` on response/error;
  `cancelAll([reason])` + top-level `cancelAll(dio,[reason])`; `dispose()` cancels all. Loading is a
  0↔1 edge-triggered counter calling `onChanged(bool)`; increment AND decrement both gate on
  `extra['loading']!=false` — if a caller mutates that mid-flight the counter desyncs. `dispose()`
  force-resets to 0 and fires `onChanged(false)`.
- **EnvsPlugin** (`envs_plugin.dart`, `name: 'envs'`). Install-time only (`onRequest` no-op). First
  matching `EnvRule` wins. Gotcha: `apply` unconditionally sets `responseType` from the rule's
  `BaseOptions`, so a rule with a default `BaseOptions` overwrites `responseType` to json.
- **LogPlugin** (`log_plugin.dart`, `name: 'log'`). Dependency-free; `print` by default, `writer` to
  route elsewhere.

## The `extra[...]` key registry (single source of coordination)

User-facing (per-request overrides): `protected` (auth), `key` (build-key), `cache`, `share`,
`mock`, `loading`, `log`, `retry`, `filter` (normalize-request), `repath`, `normalize`.
Internal (do not collide): `_key`, `_cache_key`/`_cache_ttl`/`_cache_clone`,
`_share_leader`/`_share_seq`/`_share_policy`/`_share_retries_left`, `_retry_count`, `_cancel_token`,
`__auth_decision`/`__auth_protected`/`__auth_refreshed`/`__auth_denied`. There are no collisions —
preserve that when adding a plugin.

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
cd D:/workspaces/dioplus
dart analyze          # acceptance gate — must be "No issues found!"
dart run example/dioplus_example.dart   # exercise the wired chain (uses an in-memory token manager)
```

No unit tests exist yet. If you add behavior, prefer adding a `test/` suite with a fake Dio adapter
(mirror the STOMP siblings' in-repo test-broker approach). Always re-run `dart analyze` and update
BOTH READMEs for any public API or ordering change.
