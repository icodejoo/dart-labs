# dioplus

[![pub](https://img.shields.io/pub/v/dioplus.svg)](https://pub.dev/packages/dioplus)

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
| `NormalizeRequestPlugin` | Strip `null`/empty fields from query params and body before sending. |
| `BuildKeyPlugin` | Compute a stable per-request key (`extra['_key']`) for cache & dedup. |
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
  dioplus: ^0.1.0
```

```dart
import 'package:dioplus/dioplus.dart';
```

## Quick start

```dart
final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));

dio.interceptors.addAll(<DioPlugin>[
  RepathPlugin(),                 // /users/{id}  → /users/42
  const NormalizeRequestPlugin(), // drop empty params
  const BuildKeyPlugin(),         // key for cache/share
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

A complete, runnable wiring (with an in-memory token manager and the full ordering rationale in comments) is in [`example/dioplus_example.dart`](./example/dioplus_example.dart).

## Recommended order

Because Dio is forward-order for **all** phases, one list must satisfy request, response, and error at once. Two facts drive it:

1. A short-circuit — `handler.resolve()` from `onRequest` (cache hit / share wait / mock hit) — **skips every following response interceptor**.
2. The `onError` chain runs forward through **every** interceptor, and the first one to `resolve()` (auth-401-replay, retry) **stops the rest**.

| # | plugin | request role | response / error role |
|---|---|---|---|
| 1 | `envs` | (install-time apply) | — |
| 2 | `repath` | rewrite `{id}`/`:id` path | — |
| 3 | `normalize-request` | strip empty params/data | — |
| 4 | `build-key` | compute request key | — |
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

- **`build-key` before `cache` & `share`** — they read `extra['_key']`.
- **`normalize` before `cache`** — the cache must store, and a hit must return, the *unwrapped* payload; otherwise a cached response differs in shape from a live one (a hit resolves with `resolve(false)`, skipping `normalize`).
- **`normalize` before `auth`** — `auth` assumes a business error is already an exception.
- **`cache`/`share`/`mock` before `cancel` & `loading`** — a short-circuit skips following response interceptors, so a bracket placed *before* it would increment/inject on `onRequest` and never clean up.
- **`cancel` & `loading` before `auth` & `retry`** — on a 401 (auth) or a network retry, those plugins `resolve()` the error and halt the forward `onError` chain; the brackets must have already run so the counter is decremented and the token released.

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

### NormalizeRequestPlugin

`NormalizeRequestPlugin({predicate, ignoreKeys, ignoreValues})` — drops "empty" fields (default: `null` and blank strings) from `queryParameters` and a `Map` body. Keep specific keys/values via `ignoreKeys`/`ignoreValues`.

### BuildKeyPlugin

`BuildKeyPlugin({bool fastMode = false, ignoreParams, ignoreDataKeys, builder})` — writes `extra['_key']`. `fastMode` → `METHOD:path`; default (deep) also folds sorted query params and body. Override per request with `extra['key']`.

### NormalizePlugin

`NormalizePlugin({dataKey='data', codeKey='code', messageKey='message', isSuccess, shouldNormalize})` — on a success envelope replaces `response.data` with the inner payload; on a non-success `code` it rejects with an `ApiException` so all error handling is unified at the interceptor layer. By default only kicks in when the body is a `Map` containing `codeKey`, and `isSuccess` is `code == 0`.

### CachePlugin

`CachePlugin({int expires = 60000, CacheClone clone = none, shouldCache})` — TTL cache in **milliseconds**, keyed by `extra['_key']` (needs `BuildKeyPlugin`). Defaults to caching `GET` only. `CacheClone` controls mutation safety of a hit (`none`/`shallow`/`deep`). Management: `remove(key)`, `removeWhere(test)`, `clear()`, `size`.

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

`AuthPlugin({required tokenManager, required onRefresh, required onAccessExpired, onAccessDenied, onFailure, ready, isProtected, headerKey = 'Authorization', buildHeader, enable = true})` — injects the token, and on 401/403 routes to one of five `AuthFailureAction`s (`refresh` / `replay` / `deny` / `expired` / `others`) with a **single shared refresh window** (concurrent requests wait for one refresh). Implement `ITokenManager` (`accessToken`, `refreshToken`, `canRefresh`, `clear()`) to back it. By default every request is protected; exclude public endpoints via `isProtected` or `extra['protected'] = false`.

### RetryPlugin

`RetryPlugin({required Dio dio, int max = 0, delay, retryIf, isExceptionRequest})` — retries on the `onError` path (network timeouts, 5xx by default) with exponential back-off (`1s, 2s, 4s`). Optionally treats a 2xx whose body fails `isExceptionRequest` as a failure (business-level retry — see [Behavior notes](#behavior-notes)).

### LogPlugin

`LogPlugin({logRequest, logResponse, logError, logHeaders, logBody, maxBodyLength = 1000, writer})` — logs to `print` by default; inject `writer` to route to any framework.

## Per-request overrides

Pass `options.extra` on a single call to opt out of / reconfigure a plugin:

| Key | Plugin | Effect |
|---|---|---|
| `protected` | auth | `false` → no token required for this call. |
| `key` | build-key | a `String` overrides the key; `false` skips key generation. |
| `cache` | cache | `false` skip; `true` default; `{expires, clone}` per-call. |
| `share` | share | `false`/`SharePolicy.none` opt out; a `SharePolicy` overrides. |
| `mock` | mock | `false` skip; `{mockUrl: ...}` override target. |
| `loading` | loading | `false` → don't count toward the indicator. |
| `log` | log | `false` → don't log this call. |
| `retry` | retry | an `int` max; `{max, isException}`; `false` skip. |
| `filter` | normalize-request | `false` skip; `{ignoreKeys, ignoreValues}`. |
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
