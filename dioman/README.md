# dioman

[![pub](https://img.shields.io/pub/v/dioman.svg)](https://pub.dev/packages/dioman)
[![Demo](https://img.shields.io/badge/demo-live-brightgreen)](https://icodejoo.github.io/dart-labs/dioman/)

> 中文文档：[README.zh-CN.md](./README.zh-CN.md)

**[▶ Live Demo](https://icodejoo.github.io/dart-labs/dioman/)** — interactive request playground, no server needed.

A set of **composable, self-contained** [`dio`](https://pub.dev/packages/dio) interceptor *plugins* — auth, cache, retry, request dedup, mock, envelope-normalize, path-rewrite, loading, cancel, logging — that each do one thing, plus the **correct install order** to wire them together.

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
| `DiomanRepath` | Substitute path variables `{id}` / `:id` / `[id]` from query params or body. |
| `DiomanFilter` | Strip `null`/empty fields from query params and body before sending. |
| `DiomanKey` | Compute a stable per-request key (`extra[kRequestKey]`) for cache & dedup. |
| `DiomanCache` | TTL response cache with `none`/`shallow`/`deep` clone strategies. |
| `DiomanShare` | Deduplicate concurrent same-key requests (`start`/`end`/`race`/`retry`). |
| `DiomanMock` | Route-based mock (inline handlers or a mock server) with real-API fallback. |
| `DiomanCancel` | Inject a `CancelToken` into every request; `cancelAll()` aborts in-flight. |
| `DiomanLoading` | In-flight request counter → a single `onChanged(bool)` for a global spinner. |
| `DiomanAuth` | Token injection + single-window 401/403 refresh & replay (5 failure actions). |
| `DiomanRetry` | Retry network (and optionally business) failures with back-off. |
| `DiomanLog` | Dependency-free request/response/error logging with a pluggable sink. |
| `DiomanNormalize` | *(optional, install last)* Unwrap a `{code,data,message}` envelope; reject non-success as an `ApiException`. |

## Install

```yaml
dependencies:
  dioman: ^0.4.1
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
  cache: DiomanCache(),                   // TTL cache (GET)
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
  'dioman:share':     const DiomanShareOptions(policy: SharePolicy.race),            // or `enabled: false` to opt out
  'dioman:mock':      const DiomanMockOptions(mockUrl: 'http://localhost:9999'),     // or `enabled: false` to skip
  'dioman:loading':   const DiomanLoadingOptions(enabled: false),                    // don't count toward the indicator
  'dioman:retry':     DiomanRetryOptions(max: 1, shouldRetry: (err, r) => false),     // or `enabled: false`
  'dioman:filter':    const DiomanFilterOptions(ignoreKeys: ['page']),               // or `enabled: false` to skip
  'dioman:repath':    const DiomanRepathOptions(enabled: false),                     // skip `{id}` substitution
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
envs → repath → filter → key → cache → share → mock → cancel → loading → auth → retry → log → normalize
```

| # | plugin | request role | response / error role |
|---|---|---|---|
| 1 | `envs` | (install-time apply) | — |
| 2 | `repath` | rewrite `{id}`/`:id` path | — |
| 3 | `filter` | strip empty params/data | — |
| 4 | `key` | compute request key | — |
| 5 | `cache` | serve from cache | store raw payload |
| 6 | `share` | dedup concurrent | settle waiters |
| 7 | `mock` | dev override / fallback | — |
| 8 | `cancel` | inject `CancelToken` | release token |
| 9 | `loading` | count++ | count-- (bracket) |
| 10 | `auth` | inject token / wait for refresh | 401 → refresh + replay |
| 11 | `retry` | — | retry network/business failures |
| 12 | `log` | log request | log response / error |
| 13 | `normalize` *(optional)* | — | unwrap envelope / reject biz-error |

Constraints if you're wiring plugins onto `dio.interceptors` by hand instead of through
`Dioman.install` (which already gets this right for you):

- `key` before `cache` & `share` — they read `extra[kRequestKey]`.
- `cache`/`share`/`mock` before `cancel` & `loading` — so a cache/share/mock hit doesn't leave
  a loading spinner or cancel-token bracket stuck open.
- `cancel` & `loading` before `auth` & `retry` — so their cleanup has already run by the time a
  401 or a retry resolves the error.
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

`install` also wires `DiomanRetry.share`/`.cancel` and `DiomanAuth.share`/`.cancel` for you when
you pass the same `share:`/`cancel:` instance to `retry:`/`auth:` (see
[DiomanRetry](#diomanretry)/[DiomanShare](#diomanshare)). Hand-wiring those setters is only
needed if you add plugins to `dio.interceptors` yourself instead of going through `install`.

```dart
final handle = Dioman.install(
  dio,
  key: const DiomanKey(),
  cache: DiomanCache(),
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

### DiomanRepath

`DiomanRepath({bool removeKey = true, bool enabled = true, RegExp? pattern})` — `pattern` defaults to matching `{id}` / `:id` / `[id]` in the path; replaces matches with values from `queryParameters` (then `data`). By default the consumed key is removed so it isn't also sent as a param.

### DiomanFilter

`DiomanFilter({bool Function(String, dynamic)? predicate, List<String> ignoreKeys = const [], List<dynamic> ignoreValues = const [], bool enabled = true})` — drops "empty" fields (`predicate` default: `null` and blank strings) from `queryParameters` and a `Map` body. Keep specific keys/values via `ignoreKeys`/`ignoreValues`.

### DiomanKey

`DiomanKey({bool fastMode = false, List<String> ignoreKeys = const [], bool enabled = true, String Function(RequestOptions)? builder})` — writes `extra[kRequestKey]` (fixed, cross-plugin protocol key — `'dioman:key'`). `fastMode` → `METHOD:path`; default (`fastMode: false`, deep) also folds sorted query params and body — `ignoreKeys` excludes names from both. Override per request with `extra['dioman:qid'] = const DiomanKeyOptions(key: '...')` (or `enabled: false` to skip).

### DiomanNormalize — optional, business-specific, install LAST

Not a transport concern — a convenience for **one specific** envelope convention (`{code, data, message}`). Use it if your API matches; skip it entirely otherwise. Left out of [Quick start](#quick-start) and the hard-constraint order table for this reason — **if you use it, install it last**, after `log` (also where `Dioman.install` places it regardless of argument order).

`DiomanNormalize({String dataKey = 'data', String codeKey = 'code', String messageKey = 'message', bool enabled = true, bool Function(dynamic)? isSuccess, bool Function(RequestOptions, Response)? shouldNormalize})` — on a success envelope replaces `response.data` with the inner payload; on a non-success `code` it rejects with an `ApiException`. By default only kicks in when the body is a `Map` containing `codeKey` **and** either `dataKey` or `messageKey`, and `isSuccess` is `code == 0`.

### DiomanCache

`DiomanCache({int expires = 60000, CacheClone clone = CacheClone.shallow, int maxEntries = 500, bool enabled = true, bool Function(RequestOptions)? shouldCache, DateTime Function() now = DateTime.now})` — TTL cache in **milliseconds**, keyed by `extra[kRequestKey]` (needs `DiomanKey`). Defaults to caching `GET` only. Bounded by `maxEntries` (`0` disables the cap), LRU-evicted. `CacheClone` controls mutation safety of a hit: `shallow` (default, a hit reader can't corrupt the store by reassigning top-level fields), `deep` (safe for nested mutation), `none` (zero-copy read-only). `now` injects a clock for deterministic TTL tests. Management: `remove(key)`, `removeWhere(test)`, `clear()`, `size`.

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

`share`/`cancel` are settable properties (not constructor params) — set them to the same instances installed elsewhere on the chain so `DiomanShare` dedup and `cancelAll()` stay correctly aware of an in-flight retry; `Dioman.install` does this for you automatically. `onRetry` is a lightweight `(attempt) {}` hook for your own logging.

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
| `dioman:retry` | retry | `int` \| `false` \| `DiomanRetryOptions` | `int` overrides `max` only; `false` disables (highest-priority veto); the options object overrides any field (`max`/`methods`/`shouldRetry`/`statusCodes`/`delay`/`jitter`/`delayMax`/`respectRetryAfter`/`afterStatusCodes`/`retryAfterMax`/`enabled`). |
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

Slot it into the list at the position its request/response roles imply (see [Recommended order](#recommended-order)).

## License

MIT
