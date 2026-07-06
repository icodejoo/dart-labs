## 0.3.0

- Feature: `DiomanHandle.remove<T>()` ejects a single installed plugin from `dio.interceptors`
  and calls its own `dispose()`, leaving the rest of the chain untouched — the single-plugin
  counterpart to `dispose()`'s teardown-everything. Returns the removed plugin, or `null` (a
  no-op) if that type was never installed.

Breaking changes to every plugin's `extra` key:

- Every plugin with a per-request `extra` option now exposes it as a mutable
  `static String configProperty` (e.g. `LoadingPlugin.configProperty`) instead of a hardcoded
  string literal — read/write `options.extra[XxxPlugin.configProperty]`, and reassign the static
  field to remap the key if it collides with another package's `extra` usage. Defaults:
  `AuthPlugin` → `dioman:auth`, `KeyPlugin` → `dioman:qid`, `CachePlugin` → `dioman:cache`,
  `SharePlugin` → `dioman:share`, `MockPlugin` → `dioman:mock`, `LoadingPlugin` → `dioman:loading`,
  `LogPlugin` → `dioman:log`, `RetryPlugin` → `dioman:retry`, `FilterPlugin` → `dioman:filter`,
  `RepathPlugin` → `dioman:repath`, `NormalizePlugin` → `dioman:normalize`.
- All internal (plugin-private / cross-plugin coordination) `extra` keys dropped their
  underscore-prefixed form (`_key`, `_cache_ttl`, `__auth_decision`, ...) in favor of a namespaced
  `dioman:<plugin>:<detail>` form (`dioman:cache:ttl`, `dioman:auth:decision`, ...); the cross-plugin
  request key (`kRequestKey`) is now `'dioman:key'`.
- `ReqkeyPlugin` renamed to `KeyPlugin` (`reqkey_plugin.dart` → `key_plugin.dart`, `name: 'reqkey'`
  → `'key'`, `Dioman.install(reqkey: ...)` → `Dioman.install(key: ...)`).
- `ReqcleanPlugin` renamed to `FilterPlugin` (`reqclean_plugin.dart` → `filter_plugin.dart`,
  `name: 'reqclean'` → `'filter'`, `Dioman.install(reqclean: ...)` → `Dioman.install(filter: ...)`).

See the [Quick start](./README.md#every-plugins-extra-option-in-one-place) for full per-plugin
usage.

## 0.2.0

First release of `dioman` — a set of composable, self-contained [Dio] interceptor plugins, all
extending a common `DioPlugin` base (a named `Interceptor` with `dispose`), plus the documented
correct install order (Dio runs `onRequest`/`onResponse`/`onError` in forward add-order for all
phases). Plugins: `EnvsPlugin`, `RepathPlugin`, `FilterPlugin`, `KeyPlugin`,
`NormalizePlugin`, `CachePlugin`, `SharePlugin`, `MockPlugin`, `CancelPlugin`, `LoadingPlugin`,
`AuthPlugin`, `RetryPlugin`, `LogPlugin`. Wire them with `Dioman.install` or by hand.

Notable capabilities and behaviors:

- Feature: `AuthPlugin` proactive refresh (opt-in) — pass `expiresAt` (+ optional `refreshLeeway`)
  to refresh an already-expired token *before* sending, so requests avoid a doomed 401 round-trip.
  Concurrent expiring requests collapse onto the existing single shared refresh window; the plugin
  stays an ordinary parallel `Interceptor` (no `QueuedInterceptor`). Off by default → purely reactive.
- Feature: `Dioman.install(dio, {...})` wires the given plugins in the canonical order and returns a
  `DiomanHandle` for lookup (`plugin<T>()`) and coordinated teardown (`dispose()` ejects every plugin
  and calls each one's `dispose()`).
- `CachePlugin`: a cache **hit now promotes the entry to most-recently-used** (true LRU eviction, not
  merely oldest-write); the default clone is now `CacheClone.shallow` and is **type-preserving**
  (a `Map<String, dynamic>` stays one, so typed `get<...>()` doesn't break); added an injectable
  `now` clock for deterministic TTL tests.
- `NormalizePlugin`: default envelope detection now requires `codeKey` **and** (`dataKey` or
  `messageKey`), so a plain payload that merely carries a `code` field isn't mistaken for an envelope.
- `KeyPlugin`: a non-serialisable body (FormData/bytes/stream) now folds in object identity, so
  two distinct bodies never key identically (no false dedup/cache).
- `AuthPlugin`/`SharePlugin`/`MockPlugin` now reuse a single bare `Dio` for replays/retries/redirects
  (instead of allocating one per call) and close it on `dispose`.
- Fix: `SharePlugin.dispose` now completes pending shared completers with an error before clearing
  `_active` (was leaving them dangling); `MockPlugin` gained a `dispose` that closes its redirect Dio.
- Fix: `AuthPlugin` compared the formatted `Authorization` header against the raw store token,
  so the default Bearer builder made the refresh action unreachable (always fell through to
  replay/expire); token refresh is now correctly triggered, and a post-refresh replay carries the
  freshly refreshed token instead of the stale one.
- Fix: `AuthPlugin`'s `onRequest` rejects now propagate to earlier brackets
  (`callFollowingErrorInterceptor: true`), so `CancelPlugin`/`LoadingPlugin`/`SharePlugin` release
  their state on a denied request instead of leaking a token / stuck spinner / dead completer.
- Fix: `SharePlugin.retry` now actually retries up to `retries` times (previously gave up after one
  internal attempt) and properly settles the shared completer and removes the entry from `_active`
  on both success and exhaustion — previously a successful internal retry left every waiter (and
  every future request with the same key) permanently hung.
- Fix: `SharePlugin.end`/`race` now deliver the correct cross-caller result (the last request for
  `end`, the winning sibling's result for `race`) to every caller, including superseded/losing ones
  — previously each caller only ever saw its own response.
- Fix: `MockPlugin` inline handlers now decode the `ResponseBody` before resolving (previously
  `.data` held the raw undecoded stream wrapper); mock hits now propagate through
  normalize/cache/share (`callFollowingResponseInterceptor: true`) so envelopes are unwrapped and
  shared-request followers don't hang; the mock-server redirect no longer duplicates query
  parameters; the route key now matches `KeyPlugin`'s resolved-path scheme.
- Fix: `RetryPlugin` now honors `extra['retry'] == false` on the business-retry (`onResponse`) path
  too, and gives up immediately after the back-off delay if the request was cancelled.
- Fix: `CancelPlugin` re-registers a token it previously injected when `RetryPlugin` re-dispatches
  the same `RequestOptions` — previously `cancelAll()` silently stopped covering a request once it
  entered its first retry.
- Fix: `EnvsPlugin` no longer resets a user-configured `responseType` back to the `json` default
  when an applied rule didn't explicitly set one.
- `CachePlugin` gained `maxEntries` (default 500) to LRU-bound the store, which previously grew
  without limit under deep `KeyPlugin` keys.
- Added `test/dioman_test.dart`, a fake-adapter regression suite covering all of the above.
