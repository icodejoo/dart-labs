# dioman

[![pub](https://img.shields.io/pub/v/dioman.svg)](https://pub.dev/packages/dioman)

> 中文文档：[README.zh-CN.md](./README.zh-CN.md)

A set of **composable, self-contained** [`dio`](https://pub.dev/packages/dio) interceptor *plugins* — auth, cache, retry, request dedup, mock, envelope-normalize, path-rewrite, loading, cancel, logging — that each do one thing, plus the **correct install order** to wire them together.

> Key insight: **Dio runs `onRequest` / `onResponse` / `onError` of every interceptor in the same forward (add) order** — it is *not* an onion model. So the order you add plugins is the whole game: get it wrong and a cache hit leaks a loading spinner, or `auth` sees a business error it can't recognize. This package gives you the plugins **and** a documented, defensible order (see [Recommended order](#recommended-order)).

Pure Dart, `dio` only — **no Flutter dependency**.

- [Features](#features)
- [Install](#install)
- [Quick start](#quick-start)
- [Recommended order](#recommended-order)
- [Plugins](#plugins)
- [Per-request overrides](#per-request-overrides)
- [Write your own plugin](#write-your-own-plugin)
- [Behavior notes](#behavior-notes)

## Features

Every plugin extends `DioPlugin` (a named `Interceptor` with a `dispose()` hook) and works standalone.

| Plugin | What it does |
|---|---|
| `EnvsPlugin` | Apply per-environment `BaseOptions` (baseUrl/timeouts/headers) once at install time. |
| `RepathPlugin` | Substitute path variables `{id}` / `:id` / `[id]` from query params or body. |
| `FilterPlugin` | Strip `null`/empty fields from query params and body before sending. |
| `KeyPlugin` | Compute a stable per-request key (`extra[kRequestKey]`) for cache & dedup. |
| `NormalizePlugin` | Unwrap a `{code,data,message}` envelope; reject non-success as an `ApiException`. |
| `CachePlugin` | TTL response cache with `none`/`shallow`/`deep` clone strategies. |
| `SharePlugin` | Deduplicate concurrent same-key requests (`start`/`end`/`race`/`retry`). |
| `MockPlugin` | Route-based mock (inline handlers or a mock server) with real-API fallback. |
| `CancelPlugin` | Inject a `CancelToken` into every request; `cancelAll()` aborts in-flight. |
| `LoadingPlugin` | In-flight request counter → a single `onChanged(bool)` for a global spinner. |
| `AuthPlugin` | Token injection + single-window 401/403 refresh & replay (5 failure actions). |
| `RetryPlugin` | Retry network (and optionally business) failures with back-off. |
| `LogPlugin` | Dependency-free request/response/error logging with a pluggable sink. |

## Install

```yaml
dependencies:
  dioman: ^0.3.0
```

```dart
import 'package:dioman/dioman.dart';
```

## Quick start

Plugins are listed below in the **canonical order** (see [Recommended order](#recommended-order)) —
copy this as-is and it's already correctly sequenced; add/remove plugins in place without
reordering the rest.

```dart
final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));

// envs → repath → filter → key → normalize → cache →
// share → mock → cancel → loading → auth → retry → log
dio.interceptors.addAll(<DioPlugin>[
  EnvsPlugin(dio: dio, [
    EnvRule(rule: () => true, config: BaseOptions(baseUrl: 'https://api.example.com')),
  ]),
  RepathPlugin(),                 // /users/{id}  → /users/42
  const FilterPlugin(), // drop empty params
  const KeyPlugin(),         // key for cache/share
  const NormalizePlugin(),        // {code,data,message} → data
  CachePlugin(),                  // TTL cache (GET)
  SharePlugin(),                  // dedup concurrent
  MockPlugin(),                   // enabled: false by default — dev only
  CancelPlugin(),
  LoadingPlugin(onChanged: (busy) => showSpinner(busy)),
  AuthPlugin(
    tokenManager: myTokenManager,
    onRefresh: (tm, _) async { /* refresh + save */ },
    onAccessExpired: (tm, _) async { /* go to login */ },
  ),
  RetryPlugin(dio: dio, max: 2),
  const LogPlugin(),
]);

final res = await dio.get('/users/{id}', queryParameters: {'id': 42});
```

A complete, runnable wiring (with an in-memory token manager and the full ordering rationale in comments) is in [`example/dioman_example.dart`](./example/dioman_example.dart).

### Every plugin's `extra` option, in one place

Each plugin reads its per-request option from a **static, overridable** `configProperty`
field — not a hardcoded string — so the key never collides with another package's
`extra` usage and can be renamed without touching plugin internals. The `extra` **value**
is read the same way either way (`dynamic`, pattern-matched at runtime); only the **key**
is configurable.

```dart
await dio.get('/x', options: Options(extra: {
  AuthPlugin.configProperty:      false,                              // dioman:auth  — skip auth for this call
  KeyPlugin.configProperty:    'my-custom-key',                    // dioman:qid        — override the computed key ('false' skips it)
  CachePlugin.configProperty:     {'expires': 5000, 'clone': CacheClone.shallow}, // dioman:cache
  SharePlugin.configProperty:     SharePolicy.race,                   // dioman:share      — or `false` to opt out
  MockPlugin.configProperty:      {'mockUrl': 'http://localhost:9999'}, // dioman:mock      — or `false` to skip
  LoadingPlugin.configProperty:   false,                               // dioman:loading    — don't count toward the indicator
  RetryPlugin.configProperty:     {'max': 1, 'isException': (Response r) => false}, // dioman:retry — or an `int` max, or `false`
  FilterPlugin.configProperty:  {'ignoreKeys': ['page']},            // dioman:filter     — or `false` to skip
  RepathPlugin.configProperty:    false,                               // dioman:repath     — skip `{id}` substitution
  NormalizePlugin.configProperty: false,                               // dioman:normalize  — leave the envelope wrapped
  LogPlugin.configProperty:       false,                               // dioman:log        — don't log this call
}));
```

`CancelPlugin` and `EnvsPlugin` have no per-request `extra` option (cancel is driven by `cancelAll`; envs applies once at install time).

### Remapping a key

Set the static field **before** any request runs (e.g. at app start) — every plugin
reads it dynamically on each call:

```dart
LoadingPlugin.configProperty = 'my_app:loading'; // now `extra['my_app:loading'] = false` opts out
```

## Recommended order

Because Dio is forward-order for **all** phases, one list must satisfy request, response, and error at once. Two facts drive it:

1. A short-circuit — `handler.resolve()` from `onRequest` (cache hit / share wait / mock hit) — **skips every following response interceptor**.
2. The `onError` chain runs forward through **every** interceptor, and the first one to `resolve()` (auth-401-replay, retry) **stops the rest**.

| # | plugin | request role | response / error role |
|---|---|---|---|
| 1 | `envs` | (install-time apply) | — |
| 2 | `repath` | rewrite `{id}`/`:id` path | — |
| 3 | `filter` | strip empty params/data | — |
| 4 | `key` | compute request key | — |
| 5 | `normalize` | — | unwrap envelope / reject biz-error |
| 6 | `cache` | serve from cache | store **unwrapped** payload |
| 7 | `share` | dedup concurrent | settle waiters |
| 8 | `mock` | dev override / fallback | — |
| 9 | `cancel` | inject `CancelToken` | release token |
| 10 | `loading` | count++ | count-- (bracket) |
| 11 | `auth` | inject token / wait for refresh | 401 → refresh + replay |
| 12 | `retry` | — | retry network failures |
| 13 | `log` | log request | log response / error |

**Why these positions (the hard constraints):**

- **`key` before `cache` & `share`** — they read `extra[kRequestKey]`.
- **`normalize` before `cache`** — the cache must store, and a hit must return, the *unwrapped* payload; otherwise a cached response differs in shape from a live one (a hit resolves with `resolve(false)`, skipping `normalize`).
- **`normalize` before `auth`** — `auth` assumes a business error is already an exception.
- **`cache`/`share`/`mock` before `cancel` & `loading`** — a short-circuit skips following response interceptors, so a bracket placed *before* it would increment/inject on `onRequest` and never clean up.
- **`cancel` & `loading` before `auth` & `retry`** — on a 401 (auth) or a network retry, those plugins `resolve()` the error and halt the forward `onError` chain; the brackets must have already run so the counter is decremented and the token released.

## Wiring: `Dioman.install`

The install order above is a hard constraint. Rather than ordering plugins by hand, pass the ones you want to `Dioman.install` and they're slotted into the canonical sequence (omitted plugins are skipped). It returns a `DiomanHandle` for lookup (`handle.plugin<AuthPlugin>()`), removing a single plugin (`handle.remove<AuthPlugin>()` ejects it from `dio.interceptors` and calls its own `dispose()`, leaving the rest of the chain untouched — a no-op, returning `null`, if that type isn't installed), and coordinated teardown (`handle.dispose()` ejects **every** plugin and calls each one's `dispose()` — nothing else does that automatically).

```dart
final handle = Dioman.install(
  dio,
  key: const KeyPlugin(),
  normalize: const NormalizePlugin(),
  cache: CachePlugin(),
  auth: AuthPlugin(tokenManager: tm, onRefresh: ..., onAccessExpired: ...),
  log: const LogPlugin(),
);

// Remove a single plugin later (e.g. logging out — drop AuthPlugin only):
handle.remove<AuthPlugin>();

// ...or eject everything at once:
handle.dispose();
```

## Plugins

Every plugin exposes a `String get name` (for lookup/dedup) and a `dispose()` hook. Most read a per-request flag from `options.extra` (see [Per-request overrides](#per-request-overrides)).

### EnvsPlugin

`EnvsPlugin(List<EnvRule> rules, {Dio? dio})` — applies the **first matching** rule's `BaseOptions` to `dio.options`. Install-time only (`onRequest` is a no-op). Pass `dio:` to apply immediately in the constructor, or call `apply(dio)` yourself later.

```dart
EnvsPlugin(dio: dio, [
  EnvRule(rule: () => kDebug, config: BaseOptions(baseUrl: 'https://dev.api')),
  EnvRule(rule: () => true,   config: BaseOptions(baseUrl: 'https://api')), // fallback
]);
```

### RepathPlugin

`RepathPlugin({bool removeKey = true, RegExp? pattern})` — `pattern` defaults to matching `{id}` / `:id` / `[id]` in the path; replaces matches with values from `queryParameters` (then `data`). By default the consumed key is removed so it isn't also sent as a param.

### FilterPlugin

`FilterPlugin({bool Function(String, dynamic)? predicate, List<String> ignoreKeys = const [], List<dynamic> ignoreValues = const []})` — drops "empty" fields (`predicate` default: `null` and blank strings) from `queryParameters` and a `Map` body. Keep specific keys/values via `ignoreKeys`/`ignoreValues`.

### KeyPlugin

`KeyPlugin({bool fastMode = false, List<String> ignoreParams = const [], List<String> ignoreDataKeys = const [], String Function(RequestOptions)? builder})` — writes `extra[kRequestKey]` (fixed, cross-plugin protocol key — `'dioman:key'`). `fastMode` → `METHOD:path`; default (`fastMode: false`, deep) also folds sorted query params and body. A non-serialisable body (FormData / bytes / stream) folds in object identity so two distinct bodies never key identically (never falsely deduped/cached). Override per request with `extra[KeyPlugin.configProperty]` (default `'dioman:qid'`).

### NormalizePlugin

`NormalizePlugin({String dataKey = 'data', String codeKey = 'code', String messageKey = 'message', bool Function(dynamic)? isSuccess, bool Function(RequestOptions, Response)? shouldNormalize})` — on a success envelope replaces `response.data` with the inner payload; on a non-success `code` it rejects with an `ApiException` so all error handling is unified at the interceptor layer. By default only kicks in when the body is a `Map` containing `codeKey` **and** either `dataKey` or `messageKey` (so a plain payload that merely carries a `code` field isn't mistaken for an envelope), and `isSuccess` is `code == 0`.

### CachePlugin

`CachePlugin({int expires = 60000, CacheClone clone = CacheClone.shallow, int maxEntries = 500, bool Function(RequestOptions)? shouldCache, DateTime Function() now = DateTime.now})` — TTL cache in **milliseconds**, keyed by `extra[kRequestKey]` (needs `KeyPlugin`). Defaults to caching `GET` only. A cache **hit is promoted to most-recently-used**, so eviction (past `maxEntries`, `0` disables) is true LRU. `CacheClone` controls mutation safety of a hit and defaults to `shallow` (a hit reader can't corrupt the store by reassigning top-level fields; use `deep` for nested mutation, `none` for zero-copy read-only). `now` injects a clock for deterministic TTL tests. Management: `remove(key)`, `removeWhere(test)`, `clear()`, `size`.

### SharePlugin

`SharePlugin({SharePolicy policy = SharePolicy.start, int retries = 3, Duration interval = Duration.zero})` — collapses concurrent requests with the same key.

| Policy | Behavior |
|---|---|
| `start` | First request runs; others await its result (HTTP once). |
| `end` | Every new request supersedes the previous; all callers get the **last** result. |
| `race` | Everyone runs; **first success** wins for all. |
| `retry` | Shared promise with internal retry; callers never see the retries. |
| `none` | Opt out. |

### MockPlugin

`MockPlugin({bool enabled = false, String? mockUrl, MockFallbackDecider? fallbackWhen, Map<String, MockHandler>? routes})` — `fallbackWhen` defaults to `defaultFallback` (404 or network error, excluding user cancel); `routes` defaults to empty. Matches `METHOD:path` against inline handlers, else redirects to `mockUrl`; on a 404/network error it **falls back to the real API**. Register handlers with `add('GET:/pet', ...)`, `remove`, `reset`.

### CancelPlugin

`CancelPlugin()` — injects a `CancelToken` into any request that lacks one and tracks it. `cancelAll([reason])` aborts all in-flight; the top-level `cancelAll(dio, [reason])` finds the plugin on a `Dio` and calls it.

### LoadingPlugin

`LoadingPlugin({required void Function(bool) onChanged})` — `onChanged` is required, no default. Calls `onChanged(true)` when the first request starts and `onChanged(false)` when the last finishes. `activeCount` exposes the current in-flight count.

### AuthPlugin

`AuthPlugin({required tokenManager, required onRefresh, required onAccessExpired, onAccessDenied, onFailure, ready, isProtected, expiresAt, Duration refreshLeeway = Duration.zero, DateTime Function() now = DateTime.now, String headerKey = 'Authorization', String Function(String)? buildHeader, bool enable = true})` — `buildHeader` defaults to `'Bearer $token'`. Injects the token, and on 401/403 routes to one of five `AuthFailureAction`s (`refresh` / `replay` / `deny` / `expired` / `others`) with a **single shared refresh window** (concurrent requests wait for one refresh). Implement `ITokenManager` (`accessToken`, `refreshToken`, `canRefresh`, `clear()`) to back it. By default every request is protected; exclude public endpoints via `isProtected` or `extra[AuthPlugin.configProperty] = false`.

**Proactive refresh (opt-in).** Supply `expiresAt: (token) => DateTime?` (e.g. decode a JWT `exp`) and the plugin refreshes a token that is already expired — within `refreshLeeway` — *before* sending, so the request goes out once with a fresh token instead of eating a 401 round-trip. Concurrent expiring requests collapse onto the same shared refresh window (one refresh, the rest wait, all inject the new token), so no `QueuedInterceptor`/serialization is needed. With no `expiresAt` the behaviour is purely reactive (unchanged) — the 401 path still covers server-side revocation the client can't predict. Return `null` from `expiresAt` for tokens whose expiry you can't determine.

> **`expiresAt` is a plain runtime flag, not a mode switch.** `AuthPlugin` is always an ordinary (parallel) `Interceptor`; passing `expiresAt` only adds a pre-send expiry check to `onRequest`, and the single-refresh guarantee comes from the shared `_refreshing` future either way — never from serializing the interceptor.
>
> **When to turn it on.** This is a *targeted* optimization, not a general win — leave it off unless it pays for itself:
> - **Enable** only when the token carries a **trustworthy** expiry (JWT `exp`, sane clocks) **and** you hit one of: bursty concurrency at the token boundary (e.g. app resume after idle fires many parallel requests), latency-sensitive first-request-after-idle (saves ~1 RTT), or infra that penalizes 401 noise (WAF/rate-limit/alerting).
> - **Leave off** for opaque/no-`exp` tokens, low-concurrency apps, or tokens the server may revoke early — the reactive 401 path is simpler and sufficient, and it always runs anyway.
> - **Failure mode to weigh:** if `expiresAt` says "expired" but the server would still accept it (client clock ahead, or a server grace window), you pay one wasted refresh + added latency on a request that reactive would have served directly. Keep `refreshLeeway` small.

### RetryPlugin

`RetryPlugin({required Dio dio, int max = 0, Duration Function(int attempt)? delay, bool Function(DioException)? retryIf, bool Function(Response)? isExceptionRequest})` — `delay` defaults to exponential back-off (`1s, 2s, 4s`); `retryIf` defaults to timeouts + connection errors + `statusCode >= 500 && != 501`. Retries on the `onError` path. Optionally treats a 2xx whose body fails `isExceptionRequest` as a failure (business-level retry — see [Behavior notes](#behavior-notes)).

### LogPlugin

`LogPlugin({bool logRequest = true, bool logResponse = true, bool logError = true, bool logHeaders = false, bool logBody = true, int maxBodyLength = 1000, LogWriter? writer})` — logs to `print` by default; inject `writer` to route to any framework.

## Per-request overrides

Pass `options.extra` on a single call to opt out of / reconfigure a plugin. Each key is a
**static, overridable** field (`XxxPlugin.configProperty`) — see [Every plugin's `extra`
option](#every-plugins-extra-option-in-one-place) for defaults and a full usage example:

| Static field | Plugin | Default key | Effect |
|---|---|---|---|
| `AuthPlugin.configProperty` | auth | `dioman:auth` | `false` → no token required for this call. |
| `KeyPlugin.configProperty` | key | `dioman:qid` | a `String` overrides the key; `false` skips key generation. |
| `CachePlugin.configProperty` | cache | `dioman:cache` | `false` skip; `true` default; `{expires, clone}` per-call. |
| `SharePlugin.configProperty` | share | `dioman:share` | `false`/`SharePolicy.none` opt out; a `SharePolicy` overrides. |
| `MockPlugin.configProperty` | mock | `dioman:mock` | `false` skip; `{mockUrl: ...}` override target. |
| `LoadingPlugin.configProperty` | loading | `dioman:loading` | `false` → don't count toward the indicator. |
| `LogPlugin.configProperty` | log | `dioman:log` | `false` → don't log this call. |
| `RetryPlugin.configProperty` | retry | `dioman:retry` | an `int` max; `{max, isException}`; `false` skip. |
| `FilterPlugin.configProperty` | filter | `dioman:filter` | `false` skip; `{ignoreKeys, ignoreValues}`. |
| `RepathPlugin.configProperty` | repath | `dioman:repath` | `false` skip substitution. |
| `NormalizePlugin.configProperty` | normalize | `dioman:normalize` | `false` skip envelope unwrapping. |

```dart
dio.get('/public/config', options: Options(extra: {
  AuthPlugin.configProperty: false,
  CachePlugin.configProperty: false,
  LoadingPlugin.configProperty: false,
}));
```

## Write your own plugin

```dart
class TimingPlugin extends DioPlugin {
  @override
  String get name => 'timing';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['_t0'] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final t0 = response.requestOptions.extra['_t0'] as int?;
    if (t0 != null) print('${response.requestOptions.uri} took '
        '${DateTime.now().millisecondsSinceEpoch - t0}ms');
    handler.next(response);
  }
}
```

Then slot it into the list at the position its request/response roles imply (see [Recommended order](#recommended-order)).

## Behavior notes

- **Dio is forward-order, not onion.** `onRequest`, `onResponse`, and `onError` all iterate interceptors in add order. The whole [Recommended order](#recommended-order) follows from this plus the short-circuit / error-resolve rules above.
- **Business-level retry vs normalize.** In the recommended order, `RetryPlugin.isExceptionRequest` (which inspects the envelope `code`) can't fire, because `normalize` (#5) unwraps the body before `retry` (#12) sees it. Network-level retry is unaffected. If you need envelope-based retry, move `RetryPlugin` ahead of `NormalizePlugin` — but that reintroduces a loading/cancel leak on a retried request, so pair it with `extra[LoadingPlugin.configProperty] = false` on those calls.
- **Short-circuits skip response interceptors.** A cache/share/mock `resolve()` (with the default `false`) returns straight to the caller without running any following `onResponse`. That's why brackets (`cancel`/`loading`) sit *after* them — so they never increment on a hit.
- **Single refresh window.** Concurrent 401s trigger exactly one `onRefresh`; the others await it, then replay.

## License

MIT
