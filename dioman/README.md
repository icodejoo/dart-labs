# dioman

[![pub](https://img.shields.io/pub/v/dioman.svg)](https://pub.dev/packages/dioman)
[![Demo](https://img.shields.io/badge/demo-live-brightgreen)](https://icodejoo.github.io/dart-labs/dioman/)

> 中文文档：[README.zh-CN.md](./README.zh-CN.md)

**[▶ Live Demo](https://icodejoo.github.io/dart-labs/dioman/)** — interactive request playground, no server needed.

A set of **composable, self-contained** [`dio`](https://pub.dev/packages/dio) interceptor *plugins* — auth, cache, retry, circuit-break, dynamic timeouts, offline queue, request dedup, mock, envelope-normalize, path-rewrite, loading, cancel, logging — that each do one thing, plus the **correct install order** to wire them together.

Pure Dart, `dio` only — **no Flutter dependency**.

- [Features](#features)
- [Install](#install)
- [Quick start](#quick-start)
- [Recommended order](#recommended-order)
- [Wiring: `Dioman.install`](#wiring-dionaminstall)
- [Plugins](#plugins)
- [Per-request overrides](#per-request-overrides)
- [Write your own plugin](#write-your-own-plugin)

## Features

Every plugin extends `DiomanPlugin` (a named `Interceptor` with a `dispose()` hook) and works standalone.

| Plugin | What it does |
|---|---|
| `DiomanEnvs` | Apply per-environment `BaseOptions` (baseUrl/timeouts/headers) once at install time. |
| `DiomanTimeout` | Set connect/receive/send timeouts per request from an injected network-quality tier. |
| `DiomanRepath` | Substitute path variables `{id}` / `:id` / `[id]` from query params or body. |
| `DiomanFilter` | Strip `null`/empty fields from query params and body before sending. |
| `DiomanKey` | Compute a stable per-request key (`extra[kRequestKey]`) for cache & dedup. |
| `DiomanCache` | TTL response cache with `none`/`shallow`/`deep` clone strategies. |
| `DiomanOffline` | Queue requests while offline; replay them when connectivity returns. |
| `DiomanShare` | Deduplicate concurrent same-key requests (`start`/`end`/`race`/`retry`). |
| `DiomanMock` | Route-based mock (inline handlers or a mock server) with real-API fallback. |
| `DiomanCancel` | Inject a `CancelToken` into every request; `cancelAll()` aborts in-flight. |
| `DiomanLoading` | In-flight request counter → a single `onChanged(bool)` for a global spinner. |
| `DiomanAuth` | Token injection + single-window 401/403 refresh & replay (5 failure actions). |
| `DiomanRetry` | Retry network (and optionally business) failures with back-off. |
| `DiomanBreaker` | Circuit breaker: trip per `METHOD:path` after consecutive failures, fail fast, probe to recover. |
| `DiomanLog` | Dependency-free request/response/error logging with a pluggable sink. |
| `DiomanNormalize` | *(optional, install last)* Unwrap a `{code,data,message}` envelope; reject non-success as an `DiomanException`. |

## Install

```yaml
dependencies:
  dioman: ^0.6.0
```

```dart
import 'package:dioman/dioman.dart';
```

## Quick start

Pass the plugins you want to `Dioman.install` — it slots each one into the **canonical
order** (see [Recommended order](#recommended-order)) for you, and auto-wires
`DiomanRetry`/`DiomanAuth` to a `share:`/`cancel:` you also pass.

```dart
final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));

final handle = Dioman.install(
  dio,
  envs: DiomanEnvs(dio: dio, [
    EnvRule(rule: () => true, config: BaseOptions(baseUrl: 'https://api.example.com')),
  ]),
  repath: DiomanRepath(),                 // /users/{id}  → /users/42
  filter: const DiomanFilter(),           // drop empty params
  key: const DiomanKey(),                 // key for cache/share
  cache: DiomanCache(persist: yourCachePersist),                   // TTL cache (GET)
  share: DiomanShare(),                   // dedup concurrent
  mock: DiomanMock(),                     // enabled: false by default — dev only
  cancel: DiomanCancel(),
  loading: DiomanLoading(onChanged: (busy) => showSpinner(busy)),
  auth: DiomanAuth(
    tokenManager: myTokenManager,
    onRefresh: (tokenManager, _) async { /* refresh + save */ },
    onAccessExpired: (tokenManager, _) async { /* go to login */ },
  ),
  retry: DiomanRetry(max: 2),
  log: const DiomanLog(),
  // normalize: const DiomanNormalize(), // optional, business-specific —
  // see its own section below. install() places it last regardless of
  // where you pass it among these named arguments.
);

final res = await dio.get('/users/{id}', queryParameters: {'id': 42});

// Later — eject every installed plugin and release its resources:
// handle.dispose();
```

A complete, runnable wiring (with an in-memory token manager) is in [`example/dioman_example.dart`](./example/dioman_example.dart).

### Every plugin's `extra` option, in one place

Each plugin's `name` **is** its `extra` key (fixed, e.g. `'dioman:loading'`) and doubles as the
type discriminator for its override: every per-request value is a concrete `DiomanXxxOptions`
class.

```dart
await dio.get('/x', options: Options(extra: {
  'dioman:auth':      const DiomanAuthOptions(enabled: false),                       // skip auth for this call
  'dioman:qid':       const DiomanKeyOptions(key: 'my-custom-key'),                  // override the computed key (or `enabled: false` to skip)
  'dioman:cache':     const DiomanCacheOptions(expires: 5000, clone: CacheClone.shallow),
  'dioman:offline':   const DiomanOfflineOptions(enabled: false),                      // don't queue this call when offline
  'dioman:share':     const DiomanShareOptions(policy: SharePolicy.race),            // or `enabled: false` to opt out
  'dioman:mock':      const DiomanMockOptions(mockUrl: 'http://localhost:9999'),     // or `enabled: false` to skip
  'dioman:loading':   const DiomanLoadingOptions(enabled: false),                    // don't count toward the indicator
  'dioman:retry':     DiomanRetryOptions(max: 1, shouldRetry: (err, r) => false),     // or `enabled: false`
  'dioman:breaker':   const DiomanBreakerOptions(enabled: false),                     // skip the circuit breaker for this call
  'dioman:filter':    const DiomanFilterOptions(ignoreKeys: ['page']),               // or `enabled: false` to skip
  'dioman:repath':    const DiomanRepathOptions(enabled: false),                     // skip `{id}` substitution
  'dioman:timeout':   const DiomanTimeoutOptions(enabled: false),                    // keep carried timeouts for this call
  'dioman:normalize': const DiomanNormalizeOptions(enabled: false),                  // leave the envelope wrapped
  'dioman:log':       const DiomanLogOptions(enabled: false),                        // don't log this call
}));
```

`DiomanCancel` and `DiomanEnvs` have no per-request `extra` option — each takes a
constructor-level `enabled` flag that gates the whole plugin instead. Every other plugin takes
the **same** `enabled` flag at construction too, on top of the per-request `enabled` in its
`DiomanXxxOptions`.

Every `DiomanXxxOptions` field mirrors a constructor parameter 1:1, and every field is `null`
by default — `null` means "inherit whatever the constructor set". So `const
DiomanCacheOptions(expires: 5000)` leaves `enabled` and `clone` exactly as constructed; it does
**not** silently re-enable a plugin built with `enabled: false`. `List`/`Map` fields
(`DiomanFilterOptions.ignoreKeys`, `DiomanKeyOptions.ignoreKeys`, `DiomanMockOptions.routes`)
**merge** with the plugin's own defaults instead of replacing them.

## Recommended order

```
envs → timeout → repath → filter → key → cache → offline → share → mock → cancel → loading → auth → retry → breaker → log → normalize
```

| # | plugin | request role | response / error role |
|---|---|---|---|
| 1 | `envs` | (install-time apply) | — |
| 2 | `timeout` | set timeouts by network tier | — |
| 3 | `repath` | rewrite `{id}`/`:id` path | — |
| 4 | `filter` | strip empty params/data | — |
| 5 | `key` | compute request key | — |
| 6 | `cache` | serve from cache | store raw payload |
| 7 | `offline` | queue while offline | (replay on reconnect) |
| 8 | `share` | dedup concurrent | settle waiters |
| 9 | `mock` | dev override / fallback | — |
| 10 | `cancel` | inject `CancelToken` | release token |
| 11 | `loading` | count++ | count-- (bracket) |
| 12 | `auth` | inject token / wait for refresh | 401 → refresh + replay |
| 13 | `retry` | — | retry network/business failures |
| 14 | `breaker` | fail fast when circuit open | count outcome, trip / recover |
| 15 | `log` | log request | log response / error |
| 16 | `normalize` *(optional)* | — | unwrap envelope / reject biz-error |

Constraints if you're wiring plugins onto `dio.interceptors` by hand instead of through
`Dioman.install` (which already gets this right for you):

- `key` before `cache` & `share` — they read `extra[kRequestKey]`.
- `cache` before `offline` — an offline read that hits the cache short-circuits before it can be
  queued (stale-cache-over-queue for reads).
- `offline` before `share`/`cancel`/`loading` — a parked (queued) request must not have created a
  share entry or opened a cancel/loading bracket, or those would leak while it waits.
- `cache`/`share`/`mock` before `cancel` & `loading` — so a cache/share/mock hit doesn't leave
  a loading spinner or cancel-token bracket stuck open.
- `cancel` & `loading` before `auth` & `retry` — so their cleanup has already run by the time a
  401 or a retry resolves the error.
- `breaker` after `retry` — so it counts only each request's *final* outcome (a retry-recovered
  request is a success, only a retry-exhausted one is a failure), not transient blips retry absorbs.
- `normalize` last, after everything (including `log`) — it's optional and business-specific;
  every other plugin should see the response exactly as it came off the wire.

## Wiring: `Dioman.install`

Pass the plugins you want; they're slotted into the canonical order above (omitted plugins are
skipped). Returns a `DiomanHandle` for lookup (`handle.plugin<DiomanAuth>()`), removing a single
plugin (`handle.remove<DiomanAuth>()`), and coordinated teardown (`handle.dispose()` ejects
every plugin and calls each one's `dispose()`).

Need a plugin `install` doesn't know about (a custom one, or reordering relative to the canonical
chain)? `handle.insertBefore(anchor, p)` / `handle.insertAfter(anchor, p)` slot `p` next to an
already-installed `anchor` plugin; `handle.prepend(p)` / `handle.append(p)` slot it at the very
front/back of the chain. All four manage `p` on both `dio.interceptors` and the handle itself, so
it's visible to `plugin<T>()`/`remove<T>()`/`dispose()` afterwards. `insertBefore`/`insertAfter`
throw `ArgumentError` if `anchor` isn't installed on this handle.

`install` also wires `DiomanRetry.share`/`.cancel`, `DiomanAuth.share`/`.cancel`, and
`DiomanRetry.breaker` for you when you pass the same `share:`/`cancel:`/`breaker:` instance
alongside `retry:`/`auth:` (see [DiomanRetry](#diomanretry)/[DiomanShare](#diomanshare)/
[DiomanBreaker](#diomanbreaker)). Hand-wiring those setters is only needed if you add plugins to
`dio.interceptors` yourself instead of going through `install`.

```dart
final handle = Dioman.install(
  dio,
  key: const DiomanKey(),
  cache: DiomanCache(persist: yourCachePersist),
  auth: DiomanAuth(tokenManager: tm, onRefresh: ..., onAccessExpired: ...),
  log: const DiomanLog(),
  normalize: const DiomanNormalize(), // optional — install places it last regardless of argument order
);

// Remove a single plugin later (e.g. logging out — drop DiomanAuth only):
handle.remove<DiomanAuth>();

// ...or eject everything at once:
handle.dispose();
```

## Plugins

Every plugin exposes a `String get name` (for lookup/dedup) and a `dispose()` hook. Each plugin's name is also available as a `static const pluginName` on the class itself (e.g. `DiomanCache.pluginName`), so callers can reference a plugin's `extra` key without constructing an instance. Most read a per-request flag from `options.extra` (see [Per-request overrides](#per-request-overrides)).

### DiomanEnvs

`DiomanEnvs(List<EnvRule> rules, {Dio? dio, bool enabled = true})` — applies the **first matching** rule's `BaseOptions` to `dio.options`. Install-time only (`onRequest` is a no-op). Pass `dio:` to apply immediately in the constructor, or call `apply(dio)` yourself later. `enabled: false` makes `apply` a permanent no-op.

```dart
DiomanEnvs(dio: dio, [
  EnvRule(rule: () => kDebug, config: BaseOptions(baseUrl: 'https://dev.api')),
  EnvRule(rule: () => true,   config: BaseOptions(baseUrl: 'https://api')), // fallback
]);
```

### DiomanTimeout

`DiomanTimeout({required NetworkQuality Function() probe, Map<NetworkQuality, DiomanTimeouts> timeouts = <defaults>, bool enabled = true})` — sets each request's `connect`/`receive`/`send` timeouts from the current network tier. Pure Dart: it never detects connectivity itself — the host classifies the connection into a `NetworkQuality` (`excellent`/`good`/`poor`/`none`) and returns it from `probe`, called once per request. Each tier maps to a `DiomanTimeouts(connect?, receive?, send?)`; **only the non-null fields of the matched tier are written**, so a partially-configured tier leaves the other timeouts as `BaseOptions` set them, and a tier absent from the map is a no-op for that request. Default map stretches the connect timeout as quality drops (`10s`/`15s`/`30s`/`10s`), leaving receive/send untouched. Install first (right after `DiomanEnvs`) — it's pure per-request config. `none` is just another tier here; fail-fast / offline queueing is out of scope.

```dart
final timeout = DiomanTimeout(
  probe: () => myConnectivity.quality, // your NetworkQuality source
  timeouts: {
    NetworkQuality.poor: const DiomanTimeouts(
      connect: Duration(seconds: 30), receive: Duration(seconds: 30)),
  },
);
```

### DiomanRepath

`DiomanRepath({bool removeKey = true, bool enabled = true, RegExp? pattern})` — `pattern` defaults to matching `{id}` / `:id` / `[id]` in the path; replaces matches with values from `queryParameters` (then `data`). By default the consumed key is removed so it isn't also sent as a param.

### DiomanFilter

`DiomanFilter({bool Function(String, dynamic)? predicate, List<String> ignoreKeys = const [], List<dynamic> ignoreValues = const [], bool enabled = true})` — drops "empty" fields (`predicate` default: `null` and blank strings) from `queryParameters` and a `Map` body. Keep specific keys/values via `ignoreKeys`/`ignoreValues`.

### DiomanKey

`DiomanKey({bool fastMode = false, List<String> ignoreKeys = const [], bool enabled = true, String Function(RequestOptions)? builder})` — writes `extra[kRequestKey]` (fixed, cross-plugin protocol key — `'dioman:key'`). `fastMode` → `METHOD:path`; default (`fastMode: false`, deep) also folds sorted query params and body — `ignoreKeys` excludes names from both. Override per request with `extra['dioman:qid'] = const DiomanKeyOptions(key: '...')` (or `enabled: false` to skip).

### DiomanNormalize — optional, business-specific, install LAST

Not a transport concern — a convenience for **one specific** envelope convention (`{code, data, message}`). Use it if your API matches; skip it entirely otherwise. Left out of [Quick start](#quick-start) and the hard-constraint order table for this reason — **if you use it, install it last**, after `log` (also where `Dioman.install` places it regardless of argument order).

`DiomanNormalize({String dataKey = 'data', String codeKey = 'code', String messageKey = 'message', bool enabled = true, bool Function(dynamic)? isSuccess, bool Function(RequestOptions, Response)? shouldNormalize})` — on a success envelope replaces `response.data` with the inner payload; on a non-success `code` it rejects with an `DiomanException`. By default only kicks in when the body is a `Map` containing `codeKey` **and** either `dataKey` or `messageKey`, and `isSuccess` is `code == 0`.

### DiomanCache

`DiomanCache({required DiomanCachePersist persist, DiomanCachePolicy cachePolicy = DiomanCachePolicy.none, int expires = 60000, CacheClone clone = CacheClone.shallow, int maxEntries = 500, bool enabled = true, bool Function(RequestOptions)? shouldCache, DateTime Function() now = DateTime.now})` — TTL cache in **milliseconds**, keyed by `extra[kRequestKey]` (needs `DiomanKey`). Defaults to caching `GET` only. Bounded by `maxEntries` (`0` disables the cap), LRU-evicted (memory layer only). `CacheClone` controls mutation safety of a hit: `shallow` (default, a hit reader can't corrupt the store by reassigning top-level fields), `deep` (safe for nested mutation), `none` (zero-copy read-only). `now` injects a clock for deterministic TTL tests. Management: `remove(key)`, `clear()` (both always touch the memory store and `persist`, regardless of `cachePolicy`). There's no `removeWhere`/`size` — `DiomanCachePersist` has no key-enumeration capability, so a bulk/pattern-based operation could never be correct against a `persist`-only entry; keep your own key list in the caller if you need bulk eviction.

`persist` is **required** — there is no built-in no-op implementation, so you must implement `DiomanCachePersist` yourself (`read`/`write`/`remove`/`erase`, shaped after the `get_storage` package's container API — `read` may be sync or async (`FutureOr`), `write`/`remove`/`erase` are always async), backed by a file, sqlite, Hive, `get_storage`, or anything else, even if you only ever use `DiomanCachePolicy.memo`.

`cachePolicy` (also overridable per request via `DiomanCacheOptions.cachePolicy`) picks *where* a cached entry lives, independently of whether it's cached at all (still gated by `enabled`/`shouldCache`):
- `none` (default) — don't cache this request at all; always passes through. Caching is opt-in, not a silent default.
- `memo` — in-memory `_store` only, same as the old behavior. Not durable — wiped on restart or `dispose()`. `persist` is never touched.
- `persist` — `persist` only; the in-memory store is never read or written for that request.
- `both` — synced: a write goes to `_store` **and** `persist`; a memory miss falls back to `persist.read` and backfills `_store` so the next hit is served from memory again.

### DiomanOffline

`DiomanOffline({required bool Function() isOnline, required Stream<bool> onConnectivityChanged, bool Function(RequestOptions)? shouldQueue, int maxQueueSize = 50, Duration? maxWait, bool enabled = true})` — parks requests while offline and replays them on reconnect. Pure Dart: it never detects connectivity — the host reports it via `isOnline` (checked per request to decide whether to queue) and `onConnectivityChanged` (a `true` event auto-flushes; you can also call `flush()`). A parked request has its handler captured and simply isn't advanced; on flush it resumes with `handler.next(options)` down the rest of the chain (no throwaway `Dio`). `shouldQueue` decides what gets queued (`null` = everything); reads usually shouldn't queue — let them fail and serve `DiomanCache` instead. `maxQueueSize` (default 50, `0` = uncapped) evicts the **oldest** when full. `maxWait` (default `null` = unbounded) caps how long a request waits before it's rejected.

A rejected queued request throws a `DioException` whose `.error` is a **`DiomanOfflineException`** (`reason`: `queueFull` / `timeout` / `disposed`) — carrying no `response` and `DioExceptionType.unknown`, so a paired `DiomanRetry` doesn't retry it. Install it **after `DiomanCache`, before `DiomanShare`** (see [Recommended order](#recommended-order)): a cache hit short-circuits before queueing, and a parked request never opens a share/cancel/loading bracket. `dispose()` rejects every pending request (`disposed`) and cancels the stream subscription — nothing is left hanging.

> `maxWait` is off by default, so a queued request can wait indefinitely (until reconnect, eviction, or dispose). Set it if you need a hard upper bound on a spinner.

```dart
final offline = DiomanOffline(
  isOnline: () => connectivity.isOnline,
  onConnectivityChanged: connectivity.onlineStream, // Stream<bool>
  shouldQueue: (o) => o.method != 'GET',            // e.g. only queue writes
);
dio.interceptors.add(offline); // after DiomanCache, before DiomanShare
```

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

`DiomanLoading({required void Function(bool) onChanged, bool enabled = true})` — calls `onChanged(true)` when the first request starts and `onChanged(false)` when the last finishes. `activeCount` exposes the current in-flight count.

### DiomanAuth

`DiomanAuth({required tokenManager, required onRefresh, required onAccessExpired, onAccessDenied, onFailure, ready, isProtected, expiresAt, Duration refreshLeeway = Duration.zero, DateTime Function() now = DateTime.now, String headerKey = 'Authorization', String Function(String)? buildHeader, bool enabled = true})` — `buildHeader` defaults to `'Bearer $token'`. Injects the token, and on 401/403 routes to one of five `AuthFailureAction`s (`refresh` / `replay` / `deny` / `expired` / `others`) with a **single shared refresh window** (concurrent requests wait for one refresh). Implement `ITokenManager` (`accessToken`, `refreshToken`, `canRefresh`, `clear()`) to back it. By default every request is protected; exclude public endpoints via `isProtected` or `extra['dioman:auth'] = const DiomanAuthOptions(enabled: false)`.

**Proactive refresh (opt-in).** Supply `expiresAt: (token) => DateTime?` (e.g. decode a JWT `exp`) and the plugin refreshes an already-expired token — within `refreshLeeway` — *before* sending, avoiding a doomed 401 round-trip. Concurrent expiring requests share one refresh window. With no `expiresAt`, behavior is purely reactive (401 path only). Worth enabling when tokens carry a trustworthy expiry and you see bursty concurrency at the token boundary, latency-sensitive first-requests, or 401-noise-sensitive infra; otherwise the reactive path alone is simpler and sufficient.

### DiomanRetry

`DiomanRetry({int max = 0, List<String>? methods, DiomanShouldRetry? shouldRetry, List<int>? statusCodes, DiomanRetryDelay? delay, Object? jitter, Duration? delayMax, bool enabled = true, bool respectRetryAfter = true, List<int>? afterStatusCodes, Duration? retryAfterMax, void Function(int attempt)? onRetry})` — `methods` (default `[GET,PUT,HEAD,DELETE,OPTIONS,TRACE]`) is checked first and is a hard veto `shouldRetry` can't override. `delay` defaults to a flat `3000ms`; `jitter` (`true` or a `Duration Function(Duration)`) and `delayMax` layer on top. `shouldRetry` has no built-in default — an exact `true`/`false` wins, `null` falls through to `statusCodes` (default `[408,429,500,502,503,504]`), and only with no HTTP status at all (a pure network failure) further falls back to a timeout/connection-error check. Called as `shouldRetry(err, err.response)` on the `onError` path (network-level retry) and as `shouldRetry(null, response)` on the `onResponse` path (business-level retry — a 2xx whose body it flags as a failure, checked against the raw response body). A response's `Retry-After` header (seconds or an RFC 1123 HTTP-date) wins over `delay` when its status is in `afterStatusCodes` (default `[413,429,503]`) and `respectRetryAfter` is true (default), capped by `retryAfterMax`.

`share`/`cancel`/`breaker` are settable properties (not constructor params) — set them to the same instances installed elsewhere on the chain so `DiomanShare` dedup and `cancelAll()` stay correctly aware of an in-flight retry, and so retrying stops the instant a paired `DiomanBreaker` trips; `Dioman.install` does this for you automatically. `onRetry` is a lightweight `(attempt) {}` hook for your own logging.

### DiomanBreaker

`DiomanBreaker({int failureThreshold = 10, Duration resetDuration = const Duration(seconds: 30), int halfOpenMaxCalls = 3, DiomanShouldTrip? shouldTrip, String Function(RequestOptions)? keyBuilder, void Function(String key, DiomanBreakerState from, DiomanBreakerState to)? onStateChange, bool enabled = true})` — a circuit breaker bucketed per `METHOD:path` (override with `keyBuilder`). Each bucket is `closed` → `open` after `failureThreshold` **consecutive** failures (any success resets the count); `open` rejects every request **without touching the network** (fail fast) until `resetDuration` elapses, then admits up to `halfOpenMaxCalls` probe requests — one probe success closes it, one probe failure re-opens it. `shouldTrip(response?, err?) → bool?` decides what counts as a failure (an exact `true`/`false` wins, `null` falls through to the default: network/timeout errors and HTTP 5xx / 429). `onStateChange` is an observational `(key, from, to)` hook for metrics.

An open bucket rejects with a `DioException` whose `.error` is a **`DiomanBreakerOpenException`** (`bucketKey`, `retryableAt`) — carrying no `response` and `DioExceptionType.unknown`, so a paired `DiomanRetry` never retries a fail-fast rejection. Install it **after** `DiomanRetry` (see [Recommended order](#recommended-order)); pair the two via `Dioman.install(dio, retry: ..., breaker: ...)` and `DiomanRetry` also consults the breaker before every re-issue, so an in-progress retry loop halts the moment the circuit trips.

**Why alongside `DiomanRetry`?** Retry spaces out a *single* request's own attempts; it does nothing across independent requests — 20 requests each retrying 3× still land 60 hits on a downed server. The breaker adds the cross-request state retry lacks: once a dependency is genuinely down, new requests are rejected in microseconds (no waiting out a weak-network timeout) and the server gets a cooldown instead of being hammered.

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
| `dioman:offline` | offline | `DiomanOfflineOptions` | `enabled: false` skip (pass through even offline); `shouldQueue`/`maxQueueSize`/`maxWait` per-call. |
| `dioman:share` | share | `DiomanShareOptions` | `enabled: false` opt out; `policy` overrides. |
| `dioman:mock` | mock | `DiomanMockOptions` | `enabled: false` skip; `mockUrl` overrides target. |
| `dioman:loading` | loading | `DiomanLoadingOptions` | `enabled: false` → don't count toward the indicator. |
| `dioman:log` | log | `DiomanLogOptions` | `enabled: false` → don't log this call. |
| `dioman:retry` | retry | `int` \| `false` \| `DiomanRetryOptions` | `int` overrides `max` only; `false` disables (highest-priority veto); the options object overrides any field (`max`/`methods`/`shouldRetry`/`statusCodes`/`delay`/`jitter`/`delayMax`/`respectRetryAfter`/`afterStatusCodes`/`retryAfterMax`/`enabled`). |
| `dioman:breaker` | breaker | `DiomanBreakerOptions` | `enabled: false` skip (neither rejected when open nor counted); `failureThreshold`/`resetDuration`/`halfOpenMaxCalls`/`shouldTrip`/`keyBuilder` per-call. |
| `dioman:filter` | filter | `DiomanFilterOptions` | `enabled: false` skip; `ignoreKeys`/`ignoreValues` per-call. |
| `dioman:repath` | repath | `DiomanRepathOptions` | `enabled: false` skip substitution. |
| `dioman:timeout` | timeout | `DiomanTimeoutOptions` | `enabled: false` skip (keep carried timeouts); `timeouts` merges/overrides tiers per-call. |
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

Slot it into the list at the position its request/response roles imply (see [Recommended order](#recommended-order)).

## License

MIT
