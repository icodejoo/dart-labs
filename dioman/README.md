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

Every plugin extends `DiomanPlugin` (a named `Interceptor` with a `dispose()` hook) and works standalone.

| Plugin | What it does |
|---|---|
| `DiomanEnvs` | Apply per-environment `BaseOptions` (baseUrl/timeouts/headers) once at install time. |
| `DiomanRepath` | Substitute path variables `{id}` / `:id` / `[id]` from query params or body. |
| `DiomanFilter` | Strip `null`/empty fields from query params and body before sending. |
| `DiomanKey` | Compute a stable per-request key (`extra[kRequestKey]`) for cache & dedup. |
| `DiomanNormalize` | Unwrap a `{code,data,message}` envelope; reject non-success as an `ApiException`. |
| `DiomanCache` | TTL response cache with `none`/`shallow`/`deep` clone strategies. |
| `DiomanShare` | Deduplicate concurrent same-key requests (`start`/`end`/`race`/`retry`). |
| `DiomanMock` | Route-based mock (inline handlers or a mock server) with real-API fallback. |
| `DiomanCancel` | Inject a `CancelToken` into every request; `cancelAll()` aborts in-flight. |
| `DiomanLoading` | In-flight request counter → a single `onChanged(bool)` for a global spinner. |
| `DiomanAuth` | Token injection + single-window 401/403 refresh & replay (5 failure actions). |
| `DiomanRetry` | Retry network (and optionally business) failures with back-off. |
| `DiomanLog` | Dependency-free request/response/error logging with a pluggable sink. |

## Install

```yaml
dependencies:
  dioman: ^0.4.0
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
dio.interceptors.addAll(<DiomanPlugin>[
  DiomanEnvs(dio: dio, [
    EnvRule(rule: () => true, config: BaseOptions(baseUrl: 'https://api.example.com')),
  ]),
  DiomanRepath(),                 // /users/{id}  → /users/42
  const DiomanFilter(), // drop empty params
  const DiomanKey(),         // key for cache/share
  const DiomanNormalize(),        // {code,data,message} → data
  DiomanCache(),                  // TTL cache (GET)
  DiomanShare(),                  // dedup concurrent
  DiomanMock(),                   // enabled: false by default — dev only
  DiomanCancel(),
  DiomanLoading(onChanged: (busy) => showSpinner(busy)),
  DiomanAuth(
    tokenManager: myTokenManager,
    onRefresh: (tokenManager, _) async { /* refresh + save */ },
    onAccessExpired: (tokenManager, _) async { /* go to login */ },
  ),
  DiomanRetry(dio: dio, max: 2),
  const DiomanLog(),
]);

final res = await dio.get('/users/{id}', queryParameters: {'id': 42});
```

A complete, runnable wiring (with an in-memory token manager and the full ordering rationale in comments) is in [`example/dioman_example.dart`](./example/dioman_example.dart).

### Every plugin's `extra` option, in one place

Each plugin's `name` **is** its `extra` key (fixed, e.g. `'dioman:loading'` — not
reconfigurable) and doubles as the type discriminator for its override: every per-request
value is a concrete `DiomanXxxOptions` class, not a `dynamic` bool/Map that the plugin has
to sniff apart with `is` checks at runtime.

```dart
await dio.get('/x', options: Options(extra: {
  'dioman:auth':      const DiomanAuthOptions(enabled: false),                       // skip auth for this call
  'dioman:qid':       const DiomanKeyOptions(key: 'my-custom-key'),                  // override the computed key (or `enabled: false` to skip)
  'dioman:cache':     const DiomanCacheOptions(expires: 5000, clone: CacheClone.shallow),
  'dioman:share':     const DiomanShareOptions(policy: SharePolicy.race),            // or `enabled: false` to opt out
  'dioman:mock':      const DiomanMockOptions(mockUrl: 'http://localhost:9999'),     // or `enabled: false` to skip
  'dioman:loading':   const DiomanLoadingOptions(enabled: false),                    // don't count toward the indicator
  'dioman:retry':     DiomanRetryOptions(max: 1, isException: (Response r) => false), // or `enabled: false`
  'dioman:filter':    const DiomanFilterOptions(ignoreKeys: ['page']),               // or `enabled: false` to skip
  'dioman:repath':    const DiomanRepathOptions(enabled: false),                     // skip `{id}` substitution
  'dioman:normalize': const DiomanNormalizeOptions(enabled: false),                  // leave the envelope wrapped
  'dioman:log':       const DiomanLogOptions(enabled: false),                        // don't log this call
}));
```

`DiomanCancel` and `DiomanEnvs` have no per-request `extra` option (cancel is driven by `cancelAll`; envs applies once at install time) — each instead takes a constructor-level `enabled` flag that gates the whole plugin. Every other plugin takes the **same** `enabled` flag at construction too (permanently on/off for the whole plugin), on top of the per-request `enabled` in its `DiomanXxxOptions`.

Every `DiomanXxxOptions` field mirrors a constructor parameter 1:1 (excluding constructor-only dependencies like `tokenManager`/`onRefresh`/`dio` that can't sensibly vary per call), and every field is `null` by default — `null` means "inherit whatever the constructor set", not "use `true`/some other implicit default". So `const DiomanCacheOptions(expires: 5000)` leaves `enabled` and `clone` exactly as the plugin was constructed with; it does **not** silently re-enable a plugin built with `enabled: false`. **`List`/`Map` fields merge (union) with the plugin's own defaults instead of replacing them** — e.g. `DiomanFilter(ignoreKeys: ['a'])` plus a per-request `DiomanFilterOptions(ignoreKeys: ['b'])` keeps **both** `'a'` and `'b'`; `DiomanKeyOptions.ignoreKeys` and `DiomanMockOptions.routes` behave the same way.

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

The install order above is a hard constraint. Rather than ordering plugins by hand, pass the ones you want to `Dioman.install` and they're slotted into the canonical sequence (omitted plugins are skipped). It returns a `DiomanHandle` for lookup (`handle.plugin<DiomanAuth>()`), removing a single plugin (`handle.remove<DiomanAuth>()` ejects it from `dio.interceptors` and calls its own `dispose()`, leaving the rest of the chain untouched — a no-op, returning `null`, if that type isn't installed), and coordinated teardown (`handle.dispose()` ejects **every** plugin and calls each one's `dispose()` — nothing else does that automatically).

```dart
final handle = Dioman.install(
  dio,
  key: const DiomanKey(),
  normalize: const DiomanNormalize(),
  cache: DiomanCache(),
  auth: DiomanAuth(tokenManager: tm, onRefresh: ..., onAccessExpired: ...),
  log: const DiomanLog(),
);

// Remove a single plugin later (e.g. logging out — drop DiomanAuth only):
handle.remove<DiomanAuth>();

// ...or eject everything at once:
handle.dispose();
```

## Plugins

Every plugin exposes a `String get name` (for lookup/dedup) and a `dispose()` hook. Most read a per-request flag from `options.extra` (see [Per-request overrides](#per-request-overrides)).

### DiomanEnvs

`DiomanEnvs(List<EnvRule> rules, {Dio? dio, bool enabled = true})` — applies the **first matching** rule's `BaseOptions` to `dio.options`. Install-time only (`onRequest` is a no-op). Pass `dio:` to apply immediately in the constructor, or call `apply(dio)` yourself later. `enabled: false` makes `apply` a permanent no-op.

```dart
DiomanEnvs(dio: dio, [
  EnvRule(rule: () => kDebug, config: BaseOptions(baseUrl: 'https://dev.api')),
  EnvRule(rule: () => true,   config: BaseOptions(baseUrl: 'https://api')), // fallback
]);
```

### DiomanRepath

`DiomanRepath({bool removeKey = true, bool enabled = true, RegExp? pattern})` — `pattern` defaults to matching `{id}` / `:id` / `[id]` in the path; replaces matches with values from `queryParameters` (then `data`). By default the consumed key is removed so it isn't also sent as a param.

### DiomanFilter

`DiomanFilter({bool Function(String, dynamic)? predicate, List<String> ignoreKeys = const [], List<dynamic> ignoreValues = const [], bool enabled = true})` — drops "empty" fields (`predicate` default: `null` and blank strings) from `queryParameters` and a `Map` body. Keep specific keys/values via `ignoreKeys`/`ignoreValues`.

### DiomanKey

`DiomanKey({bool fastMode = false, List<String> ignoreKeys = const [], bool enabled = true, String Function(RequestOptions)? builder})` — writes `extra[kRequestKey]` (fixed, cross-plugin protocol key — `'dioman:key'`). `fastMode` → `METHOD:path`; default (`fastMode: false`, deep) also folds sorted query params and body — `ignoreKeys` excludes names from both. A non-serialisable body (FormData / bytes / stream) folds in object identity so two distinct bodies never key identically (never falsely deduped/cached). Override per request with `extra['dioman:qid'] = const DiomanKeyOptions(key: '...')` (or `enabled: false` to skip).

### DiomanNormalize

`DiomanNormalize({String dataKey = 'data', String codeKey = 'code', String messageKey = 'message', bool enabled = true, bool Function(dynamic)? isSuccess, bool Function(RequestOptions, Response)? shouldNormalize})` — on a success envelope replaces `response.data` with the inner payload; on a non-success `code` it rejects with an `ApiException` so all error handling is unified at the interceptor layer. By default only kicks in when the body is a `Map` containing `codeKey` **and** either `dataKey` or `messageKey` (so a plain payload that merely carries a `code` field isn't mistaken for an envelope), and `isSuccess` is `code == 0`.

### DiomanCache

`DiomanCache({int expires = 60000, CacheClone clone = CacheClone.shallow, int maxEntries = 500, bool enabled = true, bool Function(RequestOptions)? shouldCache, DateTime Function() now = DateTime.now})` — TTL cache in **milliseconds**, keyed by `extra[kRequestKey]` (needs `DiomanKey`). Defaults to caching `GET` only. A cache **hit is promoted to most-recently-used**, so eviction (past `maxEntries`, `0` disables) is true LRU. `CacheClone` controls mutation safety of a hit and defaults to `shallow` (a hit reader can't corrupt the store by reassigning top-level fields; use `deep` for nested mutation, `none` for zero-copy read-only). `now` injects a clock for deterministic TTL tests. Management: `remove(key)`, `removeWhere(test)`, `clear()`, `size`.

### DiomanShare

`DiomanShare({SharePolicy policy = SharePolicy.start, int retries = 3, Duration interval = Duration.zero, bool enabled = true})` — collapses concurrent requests with the same key.

| Policy | Behavior |
|---|---|
| `start` | First request runs; others await its result (HTTP once). |
| `end` | Every new request supersedes the previous; all callers get the **last** result. |
| `race` | Everyone runs; **first success** wins for all. |
| `retry` | Shared promise with internal retry; callers never see the retries. |
| `none` | Opt out. |

### DiomanMock

`DiomanMock({bool enabled = false, String? mockUrl, MockFallbackDecider? fallbackWhen, Map<String, MockHandler>? routes})` — `fallbackWhen` defaults to `defaultFallback` (404 or network error, excluding user cancel); `routes` defaults to empty. Matches `METHOD:path` against inline handlers, else redirects to `mockUrl`; on a 404/network error it **falls back to the real API**. Register handlers with `add('GET:/pet', ...)`, `remove`, `reset`.

### DiomanCancel

`DiomanCancel({bool enabled = true})` — injects a `CancelToken` into any request that lacks one and tracks it. `cancelAll([reason])` aborts all in-flight; the top-level `cancelAll(dio, [reason])` finds the plugin on a `Dio` and calls it. `enabled: false` disables injection/tracking entirely.

### DiomanLoading

`DiomanLoading({required void Function(bool) onChanged, bool enabled = true})` — `onChanged` is required, no default. Calls `onChanged(true)` when the first request starts and `onChanged(false)` when the last finishes. `activeCount` exposes the current in-flight count. (`DiomanLoadingOptions` also carries an `onChanged` field mirroring this constructor param, for structural symmetry — it is not consulted per-request, since overriding the shared counter's callback for a single call would desync the increment/decrement pair.)

### DiomanAuth

`DiomanAuth({required tokenManager, required onRefresh, required onAccessExpired, onAccessDenied, onFailure, ready, isProtected, expiresAt, Duration refreshLeeway = Duration.zero, DateTime Function() now = DateTime.now, String headerKey = 'Authorization', String Function(String)? buildHeader, bool enabled = true})` — `buildHeader` defaults to `'Bearer $token'`. Injects the token, and on 401/403 routes to one of five `AuthFailureAction`s (`refresh` / `replay` / `deny` / `expired` / `others`) with a **single shared refresh window** (concurrent requests wait for one refresh). Implement `ITokenManager` (`accessToken`, `refreshToken`, `canRefresh`, `clear()`) to back it. By default every request is protected; exclude public endpoints via `isProtected` or `extra['dioman:auth'] = const DiomanAuthOptions(enabled: false)`.

**Proactive refresh (opt-in).** Supply `expiresAt: (token) => DateTime?` (e.g. decode a JWT `exp`) and the plugin refreshes a token that is already expired — within `refreshLeeway` — *before* sending, so the request goes out once with a fresh token instead of eating a 401 round-trip. Concurrent expiring requests collapse onto the same shared refresh window (one refresh, the rest wait, all inject the new token), so no `QueuedInterceptor`/serialization is needed. With no `expiresAt` the behaviour is purely reactive (unchanged) — the 401 path still covers server-side revocation the client can't predict. Return `null` from `expiresAt` for tokens whose expiry you can't determine.

> **`expiresAt` is a plain runtime flag, not a mode switch.** `DiomanAuth` is always an ordinary (parallel) `Interceptor`; passing `expiresAt` only adds a pre-send expiry check to `onRequest`, and the single-refresh guarantee comes from the shared `_refreshing` future either way — never from serializing the interceptor.
>
> **When to turn it on.** This is a *targeted* optimization, not a general win — leave it off unless it pays for itself:
> - **Enable** only when the token carries a **trustworthy** expiry (JWT `exp`, sane clocks) **and** you hit one of: bursty concurrency at the token boundary (e.g. app resume after idle fires many parallel requests), latency-sensitive first-request-after-idle (saves ~1 RTT), or infra that penalizes 401 noise (WAF/rate-limit/alerting).
> - **Leave off** for opaque/no-`exp` tokens, low-concurrency apps, or tokens the server may revoke early — the reactive 401 path is simpler and sufficient, and it always runs anyway.
> - **Failure mode to weigh:** if `expiresAt` says "expired" but the server would still accept it (client clock ahead, or a server grace window), you pay one wasted refresh + added latency on a request that reactive would have served directly. Keep `refreshLeeway` small.

### DiomanRetry

`DiomanRetry({required Dio dio, int max = 0, Duration Function(int attempt)? delay, bool enabled = true, bool Function(DioException)? retryIf, bool Function(Response)? isExceptionRequest})` — `delay` defaults to exponential back-off (`1s, 2s, 4s`); `retryIf` defaults to timeouts + connection errors + `statusCode >= 500 && != 501`. Retries on the `onError` path. Optionally treats a 2xx whose body fails `isExceptionRequest` as a failure (business-level retry — see [Behavior notes](#behavior-notes)).

### DiomanLog

`DiomanLog({bool logRequest = true, bool logResponse = true, bool logError = true, bool logHeaders = false, bool logBody = true, int maxBodyLength = 1000, bool enabled = true, LogWriter? writer})` — logs to `print` by default; inject `writer` to route to any framework.

## Per-request overrides

Pass `options.extra` on a single call to opt out of / reconfigure a plugin. Each plugin's
`name` **is** its fixed `extra` key, and the value is always its own `DiomanXxxOptions` type
— see [Every plugin's `extra` option](#every-plugins-extra-option-in-one-place) for a full
usage example:

| `extra` key (`= name`) | Plugin | Options type | Effect |
|---|---|---|---|
| `dioman:auth` | auth | `DiomanAuthOptions` | `enabled: false` → no token required for this call. |
| `dioman:qid` | key | `DiomanKeyOptions` | `key: '...'` overrides the key; `enabled: false` skips key generation. |
| `dioman:cache` | cache | `DiomanCacheOptions` | `enabled: false` skip; `expires`/`clone` per-call. |
| `dioman:share` | share | `DiomanShareOptions` | `enabled: false` opt out; `policy` overrides. |
| `dioman:mock` | mock | `DiomanMockOptions` | `enabled: false` skip; `mockUrl` overrides target. |
| `dioman:loading` | loading | `DiomanLoadingOptions` | `enabled: false` → don't count toward the indicator. |
| `dioman:log` | log | `DiomanLogOptions` | `enabled: false` → don't log this call. |
| `dioman:retry` | retry | `DiomanRetryOptions` | `max`/`isException` per-call; `enabled: false` skip. |
| `dioman:filter` | filter | `DiomanFilterOptions` | `enabled: false` skip; `ignoreKeys`/`ignoreValues` per-call. |
| `dioman:repath` | repath | `DiomanRepathOptions` | `enabled: false` skip substitution. |
| `dioman:normalize` | normalize | `DiomanNormalizeOptions` | `enabled: false` skip envelope unwrapping. |

```dart
dio.get('/public/config', options: Options(extra: {
  'dioman:auth': const DiomanAuthOptions(enabled: false),
  'dioman:cache': const DiomanCacheOptions(enabled: false),
  'dioman:loading': const DiomanLoadingOptions(enabled: false),
}));
```

## Write your own plugin

```dart
class TimingPlugin extends DiomanPlugin {
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
- **Business-level retry vs normalize.** In the recommended order, `DiomanRetry.isExceptionRequest` (which inspects the envelope `code`) can't fire, because `normalize` (#5) unwraps the body before `retry` (#12) sees it. Network-level retry is unaffected. If you need envelope-based retry, move `DiomanRetry` ahead of `DiomanNormalize` — but that reintroduces a loading/cancel leak on a retried request, so pair it with `extra['dioman:loading'] = const DiomanLoadingOptions(enabled: false)` on those calls.
- **Short-circuits skip response interceptors.** A cache/share/mock `resolve()` (with the default `false`) returns straight to the caller without running any following `onResponse`. That's why brackets (`cancel`/`loading`) sit *after* them — so they never increment on a hit.
- **Single refresh window.** Concurrent 401s trigger exactly one `onRefresh`; the others await it, then replay.

## License

MIT
