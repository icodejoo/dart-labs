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
| `ReqcleanPlugin` | Strip `null`/empty fields from query params and body before sending. |
| `ReqkeyPlugin` | Compute a stable per-request key (`extra['_key']`) for cache & dedup. |
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
  dioman: ^0.2.0
```

```dart
import 'package:dioman/dioman.dart';
```

## Quick start

```dart
final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));

dio.interceptors.addAll(<DioPlugin>[
  RepathPlugin(),                 // /users/{id}  → /users/42
  const ReqcleanPlugin(), // drop empty params
  const ReqkeyPlugin(),         // key for cache/share
  const NormalizePlugin(),        // {code,data,message} → data
  CachePlugin(),                  // TTL cache (GET)
  SharePlugin(),                  // dedup concurrent
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

## Recommended order

Because Dio is forward-order for **all** phases, one list must satisfy request, response, and error at once. Two facts drive it:

1. A short-circuit — `handler.resolve()` from `onRequest` (cache hit / share wait / mock hit) — **skips every following response interceptor**.
2. The `onError` chain runs forward through **every** interceptor, and the first one to `resolve()` (auth-401-replay, retry) **stops the rest**.

| # | plugin | request role | response / error role |
|---|---|---|---|
| 1 | `envs` | (install-time apply) | — |
| 2 | `repath` | rewrite `{id}`/`:id` path | — |
| 3 | `reqclean` | strip empty params/data | — |
| 4 | `reqkey` | compute request key | — |
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

- **`reqkey` before `cache` & `share`** — they read `extra['_key']`.
- **`normalize` before `cache`** — the cache must store, and a hit must return, the *unwrapped* payload; otherwise a cached response differs in shape from a live one (a hit resolves with `resolve(false)`, skipping `normalize`).
- **`normalize` before `auth`** — `auth` assumes a business error is already an exception.
- **`cache`/`share`/`mock` before `cancel` & `loading`** — a short-circuit skips following response interceptors, so a bracket placed *before* it would increment/inject on `onRequest` and never clean up.
- **`cancel` & `loading` before `auth` & `retry`** — on a 401 (auth) or a network retry, those plugins `resolve()` the error and halt the forward `onError` chain; the brackets must have already run so the counter is decremented and the token released.

## Wiring: `Dioman.install`

The install order above is a hard constraint. Rather than ordering plugins by hand, pass the ones you want to `Dioman.install` and they're slotted into the canonical sequence (omitted plugins are skipped). It returns a `DiomanHandle` for lookup (`handle.plugin<AuthPlugin>()`) and coordinated teardown (`handle.dispose()` ejects every plugin **and** calls each one's `dispose()` — nothing else does that automatically).

```dart
final handle = Dioman.install(
  dio,
  reqkey: const ReqkeyPlugin(),
  normalize: const NormalizePlugin(),
  cache: CachePlugin(),
  auth: AuthPlugin(tokenManager: tm, onRefresh: ..., onAccessExpired: ...),
  log: const LogPlugin(),
);
// ...later:
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

`RepathPlugin({bool removeKey = true, RegExp? pattern})` — replaces `{id}`, `:id`, `[id]` in the path with values from `queryParameters` (then `data`). By default the consumed key is removed so it isn't also sent as a param.

### ReqcleanPlugin

`ReqcleanPlugin({predicate, ignoreKeys, ignoreValues})` — drops "empty" fields (default: `null` and blank strings) from `queryParameters` and a `Map` body. Keep specific keys/values via `ignoreKeys`/`ignoreValues`.

### ReqkeyPlugin

`ReqkeyPlugin({bool fastMode = false, ignoreParams, ignoreDataKeys, builder})` — writes `extra['_key']`. `fastMode` → `METHOD:path`; default (deep) also folds sorted query params and body. A non-serialisable body (FormData / bytes / stream) folds in object identity so two distinct bodies never key identically (never falsely deduped/cached). Override per request with `extra['key']`.

### NormalizePlugin

`NormalizePlugin({dataKey='data', codeKey='code', messageKey='message', isSuccess, shouldNormalize})` — on a success envelope replaces `response.data` with the inner payload; on a non-success `code` it rejects with an `ApiException` so all error handling is unified at the interceptor layer. By default only kicks in when the body is a `Map` containing `codeKey` **and** either `dataKey` or `messageKey` (so a plain payload that merely carries a `code` field isn't mistaken for an envelope), and `isSuccess` is `code == 0`.

### CachePlugin

`CachePlugin({int expires = 60000, CacheClone clone = shallow, maxEntries = 500, shouldCache, now})` — TTL cache in **milliseconds**, keyed by `extra['_key']` (needs `ReqkeyPlugin`). Defaults to caching `GET` only. A cache **hit is promoted to most-recently-used**, so eviction (past `maxEntries`, `0` disables) is true LRU. `CacheClone` controls mutation safety of a hit and defaults to `shallow` (a hit reader can't corrupt the store by reassigning top-level fields; use `deep` for nested mutation, `none` for zero-copy read-only). `now` injects a clock for deterministic TTL tests. Management: `remove(key)`, `removeWhere(test)`, `clear()`, `size`.

### SharePlugin

`SharePlugin({SharePolicy policy = start, int retries = 3, Duration interval})` — collapses concurrent requests with the same key.

| Policy | Behavior |
|---|---|
| `start` | First request runs; others await its result (HTTP once). |
| `end` | Every new request supersedes the previous; all callers get the **last** result. |
| `race` | Everyone runs; **first success** wins for all. |
| `retry` | Shared promise with internal retry; callers never see the retries. |
| `none` | Opt out. |

### MockPlugin

`MockPlugin({bool enabled = false, mockUrl, fallbackWhen, routes})` — matches `METHOD:path` against inline handlers, else redirects to `mockUrl`; on a 404/network error it **falls back to the real API**. Register handlers with `add('GET:/pet', ...)`, `remove`, `reset`.

### CancelPlugin

`CancelPlugin()` — injects a `CancelToken` into any request that lacks one and tracks it. `cancelAll([reason])` aborts all in-flight; the top-level `cancelAll(dio, [reason])` finds the plugin on a `Dio` and calls it.

### LoadingPlugin

`LoadingPlugin({required void Function(bool) onChanged})` — calls `onChanged(true)` when the first request starts and `onChanged(false)` when the last finishes. `activeCount` exposes the current in-flight count.

### AuthPlugin

`AuthPlugin({required tokenManager, required onRefresh, required onAccessExpired, onAccessDenied, onFailure, ready, isProtected, expiresAt, refreshLeeway = Duration.zero, headerKey = 'Authorization', buildHeader, enable = true})` — injects the token, and on 401/403 routes to one of five `AuthFailureAction`s (`refresh` / `replay` / `deny` / `expired` / `others`) with a **single shared refresh window** (concurrent requests wait for one refresh). Implement `ITokenManager` (`accessToken`, `refreshToken`, `canRefresh`, `clear()`) to back it. By default every request is protected; exclude public endpoints via `isProtected` or `extra['protected'] = false`.

**Proactive refresh (opt-in).** Supply `expiresAt: (token) => DateTime?` (e.g. decode a JWT `exp`) and the plugin refreshes a token that is already expired — within `refreshLeeway` — *before* sending, so the request goes out once with a fresh token instead of eating a 401 round-trip. Concurrent expiring requests collapse onto the same shared refresh window (one refresh, the rest wait, all inject the new token), so no `QueuedInterceptor`/serialization is needed. With no `expiresAt` the behaviour is purely reactive (unchanged) — the 401 path still covers server-side revocation the client can't predict. Return `null` from `expiresAt` for tokens whose expiry you can't determine.

> **`expiresAt` is a plain runtime flag, not a mode switch.** `AuthPlugin` is always an ordinary (parallel) `Interceptor`; passing `expiresAt` only adds a pre-send expiry check to `onRequest`, and the single-refresh guarantee comes from the shared `_refreshing` future either way — never from serializing the interceptor.
>
> **When to turn it on.** This is a *targeted* optimization, not a general win — leave it off unless it pays for itself:
> - **Enable** only when the token carries a **trustworthy** expiry (JWT `exp`, sane clocks) **and** you hit one of: bursty concurrency at the token boundary (e.g. app resume after idle fires many parallel requests), latency-sensitive first-request-after-idle (saves ~1 RTT), or infra that penalizes 401 noise (WAF/rate-limit/alerting).
> - **Leave off** for opaque/no-`exp` tokens, low-concurrency apps, or tokens the server may revoke early — the reactive 401 path is simpler and sufficient, and it always runs anyway.
> - **Failure mode to weigh:** if `expiresAt` says "expired" but the server would still accept it (client clock ahead, or a server grace window), you pay one wasted refresh + added latency on a request that reactive would have served directly. Keep `refreshLeeway` small.

### RetryPlugin

`RetryPlugin({required Dio dio, int max = 0, delay, retryIf, isExceptionRequest})` — retries on the `onError` path (network timeouts, 5xx by default) with exponential back-off (`1s, 2s, 4s`). Optionally treats a 2xx whose body fails `isExceptionRequest` as a failure (business-level retry — see [Behavior notes](#behavior-notes)).

### LogPlugin

`LogPlugin({logRequest, logResponse, logError, logHeaders, logBody, maxBodyLength = 1000, writer})` — logs to `print` by default; inject `writer` to route to any framework.

## Per-request overrides

Pass `options.extra` on a single call to opt out of / reconfigure a plugin:

| Key | Plugin | Effect |
|---|---|---|
| `protected` | auth | `false` → no token required for this call. |
| `key` | reqkey | a `String` overrides the key; `false` skips key generation. |
| `cache` | cache | `false` skip; `true` default; `{expires, clone}` per-call. |
| `share` | share | `false`/`SharePolicy.none` opt out; a `SharePolicy` overrides. |
| `mock` | mock | `false` skip; `{mockUrl: ...}` override target. |
| `loading` | loading | `false` → don't count toward the indicator. |
| `log` | log | `false` → don't log this call. |
| `retry` | retry | an `int` max; `{max, isException}`; `false` skip. |
| `filter` | reqclean | `false` skip; `{ignoreKeys, ignoreValues}`. |
| `repath` | repath | `false` skip substitution. |
| `normalize` | normalize | `false` skip envelope unwrapping. |

```dart
dio.get('/public/config', options: Options(extra: {
  'protected': false, 'cache': false, 'loading': false,
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
- **Business-level retry vs normalize.** In the recommended order, `RetryPlugin.isExceptionRequest` (which inspects the envelope `code`) can't fire, because `normalize` (#5) unwraps the body before `retry` (#12) sees it. Network-level retry is unaffected. If you need envelope-based retry, move `RetryPlugin` ahead of `NormalizePlugin` — but that reintroduces a loading/cancel leak on a retried request, so pair it with `extra['loading'] = false` on those calls.
- **Short-circuits skip response interceptors.** A cache/share/mock `resolve()` (with the default `false`) returns straight to the caller without running any following `onResponse`. That's why brackets (`cancel`/`loading`) sit *after* them — so they never increment on a hit.
- **Single refresh window.** Concurrent 401s trigger exactly one `onRefresh`; the others await it, then replay.

## License

MIT
