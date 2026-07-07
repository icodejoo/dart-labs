## 0.4.0

Breaking: every plugin class renamed `XxxPlugin` → `DiomanXxx` (`DioPlugin` base →
`DiomanPlugin`), and the 0.3.0 `configProperty` mechanism is gone — replaced by a fixed,
non-reconfigurable `name` (which **is** the plugin's `extra` key) plus a typed
`DiomanXxxOptions` class for every per-request override (no more `dynamic` bool/Map read
with `is`/`==` checks inside a plugin):

- `AuthPlugin` → `DiomanAuth`, `CachePlugin` → `DiomanCache`, `CancelPlugin` → `DiomanCancel`,
  `EnvsPlugin` → `DiomanEnvs`, `FilterPlugin` → `DiomanFilter` (already renamed from
  `ReqcleanPlugin` in 0.3.0), `KeyPlugin` → `DiomanKey` (already renamed from `ReqkeyPlugin` in
  0.3.0), `LoadingPlugin` → `DiomanLoading`, `LogPlugin` → `DiomanLog`, `MockPlugin` →
  `DiomanMock`, `NormalizePlugin` → `DiomanNormalize`, `RepathPlugin` → `DiomanRepath`,
  `RetryPlugin` → `DiomanRetry`, `SharePlugin` → `DiomanShare`. `Dioman.install`'s named
  parameters are unaffected (`key:`, `filter:`, etc.).
- `XxxPlugin.configProperty` removed. `name` is now the fixed `extra` key (unchanged values:
  `dioman:auth`, `dioman:qid`, `dioman:cache`, `dioman:share`, `dioman:mock`,
  `dioman:loading`, `dioman:log`, `dioman:retry`, `dioman:filter`, `dioman:repath`,
  `dioman:normalize`) — it can no longer be remapped.
- Every per-request `extra` value is now a `DiomanXxxOptions` instance instead of a raw
  `bool`/`Map`/enum — e.g. `extra['dioman:cache'] = const DiomanCacheOptions(enabled: false)`
  instead of `extra['dioman:cache'] = false`. `DiomanAuthOptions` drops the old function-typed
  per-call override (redundant with the constructor's `isProtected` callback); every other
  plugin's previous dynamic shapes map 1:1 onto named fields.
- Every plugin constructor gained a matching `enabled` flag (default `true`) that disables the
  plugin entirely — on top of the per-request `enabled` in its `DiomanXxxOptions`.
  `DiomanAuth`'s existing `enable` param was renamed `enabled` for consistency.
- Every `DiomanXxxOptions` field now mirrors a constructor parameter 1:1 (excluding
  constructor-only dependencies like `tokenManager`/`onRefresh`/`dio`/`onChanged` that can't
  sensibly vary per call): `DiomanCacheOptions.maxEntries`, `DiomanKeyOptions.fastMode`/
  `ignoreParams`/`ignoreDataKeys`, `DiomanLogOptions.logRequest`/`logResponse`/`logError`/
  `logHeaders`/`logBody`/`maxBodyLength`, `DiomanNormalizeOptions.dataKey`/`codeKey`/
  `messageKey`, `DiomanRepathOptions.removeKey`/`pattern`, `DiomanShareOptions.retries`/
  `interval`, `DiomanMockOptions.routes`, and `DiomanLoadingOptions.onChanged` (documented as
  never consulted per-request — see below) are new.
- Full constructor↔`DiomanXxxOptions` parity, and every new field is actually **wired** (read
  at request/response/error time), not just structurally mirrored: `DiomanCacheOptions.shouldCache`/
  `now`, `DiomanFilterOptions.predicate`, `DiomanKeyOptions.builder`, `DiomanMockOptions.fallbackWhen`,
  `DiomanNormalizeOptions.isSuccess`/`shouldNormalize`, `DiomanRetryOptions.delay`/`retryIf`,
  `DiomanLogOptions.writer`, and on `DiomanAuthOptions`: `onAccessDenied`, `onAccessExpired`,
  `onFailure`, `ready`, `isProtected`, `expiresAt`, `refreshLeeway`, `now`, `headerKey`,
  `buildHeader` (still excluded: `tokenManager`, `onRefresh` — tied to the single shared refresh
  window, can't vary per call without breaking it for every concurrent caller).
- `DiomanAuth`'s internal token-manager parameter/field is now named `tokenManager` throughout
  (was `tm` in callback signatures and the private `_tm` field) for consistency with the
  constructor's own `tokenManager` parameter.
- Every field and constructor parameter across all 13 plugins now has a bilingual (English +
  Chinese) doc comment.
- Fix: every `enabled` (and other) field on `DiomanXxxOptions` is now nullable and defaults to
  `null`, not a hardcoded default like `true`/`const []`. `null` means "inherit whatever the
  constructor set" — a per-request override that only sets one field (e.g. `expires`) no longer
  silently resets `enabled` back to `true` on a plugin constructed with `enabled: false`.
- Fix: `List`/`Map`-typed per-request overrides now **merge (union)** with the plugin's own
  defaults instead of replacing them outright — `DiomanFilterOptions.ignoreKeys`/`ignoreValues`,
  `DiomanKeyOptions.ignoreParams`/`ignoreDataKeys`, and `DiomanMockOptions.routes` all keep the
  plugin's defaults *and* the per-request additions.
- Every `onRequest`/`onResponse`/`onError` now reads `extra[name]` and type-checks it into a
  local variable exactly once, then reuses that variable for every field — no more repeated
  `override is DiomanXxxOptions` checks scattered through a method.
- Internal cross-plugin/bookkeeping `extra` keys are now built as `'$name:detail'` off each
  plugin's own fixed `name` (e.g. `DiomanCache`'s `dioman:cache:key`/`ttl`/`clone`,
  `DiomanAuth`'s `dioman:auth:decision`/`protected`/`refreshed`/`denied`/`tokenUsed`) instead of
  separately-typed-out literals — same values as 0.3.0, just derived rather than duplicated.

See the [Quick start](./README.md#every-plugins-extra-option-in-one-place) for full per-plugin
usage.

## 0.3.0

- Feature: `DiomanHandle.remove<T>()` ejects a single installed plugin from `dio.interceptors`
  and calls its own `dispose()`, leaving the rest of the chain untouched — the single-plugin
  counterpart to `dispose()`'s teardown-everything. Returns the removed plugin, or `null` (a
  no-op) if that type was never installed.

Breaking changes to every plugin's `extra` key:

- Every plugin with a per-request `extra` option now exposes it as a mutable
  `static String configProperty` (e.g. `DiomanLoading.configProperty`) instead of a hardcoded
  string literal — read/write `options.extra[XxxPlugin.configProperty]`, and reassign the static
  field to remap the key if it collides with another package's `extra` usage. Defaults:
  `DiomanAuth` → `dioman:auth`, `DiomanKey` → `dioman:qid`, `DiomanCache` → `dioman:cache`,
  `DiomanShare` → `dioman:share`, `DiomanMock` → `dioman:mock`, `DiomanLoading` → `dioman:loading`,
  `DiomanLog` → `dioman:log`, `DiomanRetry` → `dioman:retry`, `DiomanFilter` → `dioman:filter`,
  `DiomanRepath` → `dioman:repath`, `DiomanNormalize` → `dioman:normalize`.
- All internal (plugin-private / cross-plugin coordination) `extra` keys dropped their
  underscore-prefixed form (`_key`, `_cache_ttl`, `__auth_decision`, ...) in favor of a namespaced
  `dioman:<plugin>:<detail>` form (`dioman:cache:ttl`, `dioman:auth:decision`, ...); the cross-plugin
  request key (`kRequestKey`) is now `'dioman:key'`.
- `ReqkeyPlugin` renamed to `DiomanKey` (`reqkey_plugin.dart` → `key_plugin.dart`, `name: 'reqkey'`
  → `'key'`, `Dioman.install(reqkey: ...)` → `Dioman.install(key: ...)`).
- `ReqcleanPlugin` renamed to `DiomanFilter` (`reqclean_plugin.dart` → `filter_plugin.dart`,
  `name: 'reqclean'` → `'filter'`, `Dioman.install(reqclean: ...)` → `Dioman.install(filter: ...)`).

See the [Quick start](./README.md#every-plugins-extra-option-in-one-place) for full per-plugin
usage.

## 0.2.0

First release of `dioman` — a set of composable, self-contained [Dio] interceptor plugins, all
extending a common `DiomanPlugin` base (a named `Interceptor` with `dispose`), plus the documented
correct install order (Dio runs `onRequest`/`onResponse`/`onError` in forward add-order for all
phases). Plugins: `DiomanEnvs`, `DiomanRepath`, `DiomanFilter`, `DiomanKey`,
`DiomanNormalize`, `DiomanCache`, `DiomanShare`, `DiomanMock`, `DiomanCancel`, `DiomanLoading`,
`DiomanAuth`, `DiomanRetry`, `DiomanLog`. Wire them with `Dioman.install` or by hand.

Notable capabilities and behaviors:

- Feature: `DiomanAuth` proactive refresh (opt-in) — pass `expiresAt` (+ optional `refreshLeeway`)
  to refresh an already-expired token *before* sending, so requests avoid a doomed 401 round-trip.
  Concurrent expiring requests collapse onto the existing single shared refresh window; the plugin
  stays an ordinary parallel `Interceptor` (no `QueuedInterceptor`). Off by default → purely reactive.
- Feature: `Dioman.install(dio, {...})` wires the given plugins in the canonical order and returns a
  `DiomanHandle` for lookup (`plugin<T>()`) and coordinated teardown (`dispose()` ejects every plugin
  and calls each one's `dispose()`).
- `DiomanCache`: a cache **hit now promotes the entry to most-recently-used** (true LRU eviction, not
  merely oldest-write); the default clone is now `CacheClone.shallow` and is **type-preserving**
  (a `Map<String, dynamic>` stays one, so typed `get<...>()` doesn't break); added an injectable
  `now` clock for deterministic TTL tests.
- `DiomanNormalize`: default envelope detection now requires `codeKey` **and** (`dataKey` or
  `messageKey`), so a plain payload that merely carries a `code` field isn't mistaken for an envelope.
- `DiomanKey`: a non-serialisable body (FormData/bytes/stream) now folds in object identity, so
  two distinct bodies never key identically (no false dedup/cache).
- `DiomanAuth`/`DiomanShare`/`DiomanMock` now reuse a single bare `Dio` for replays/retries/redirects
  (instead of allocating one per call) and close it on `dispose`.
- Fix: `DiomanShare.dispose` now completes pending shared completers with an error before clearing
  `_active` (was leaving them dangling); `DiomanMock` gained a `dispose` that closes its redirect Dio.
- Fix: `DiomanAuth` compared the formatted `Authorization` header against the raw store token,
  so the default Bearer builder made the refresh action unreachable (always fell through to
  replay/expire); token refresh is now correctly triggered, and a post-refresh replay carries the
  freshly refreshed token instead of the stale one.
- Fix: `DiomanAuth`'s `onRequest` rejects now propagate to earlier brackets
  (`callFollowingErrorInterceptor: true`), so `DiomanCancel`/`DiomanLoading`/`DiomanShare` release
  their state on a denied request instead of leaking a token / stuck spinner / dead completer.
- Fix: `DiomanShare.retry` now actually retries up to `retries` times (previously gave up after one
  internal attempt) and properly settles the shared completer and removes the entry from `_active`
  on both success and exhaustion — previously a successful internal retry left every waiter (and
  every future request with the same key) permanently hung.
- Fix: `DiomanShare.end`/`race` now deliver the correct cross-caller result (the last request for
  `end`, the winning sibling's result for `race`) to every caller, including superseded/losing ones
  — previously each caller only ever saw its own response.
- Fix: `DiomanMock` inline handlers now decode the `ResponseBody` before resolving (previously
  `.data` held the raw undecoded stream wrapper); mock hits now propagate through
  normalize/cache/share (`callFollowingResponseInterceptor: true`) so envelopes are unwrapped and
  shared-request followers don't hang; the mock-server redirect no longer duplicates query
  parameters; the route key now matches `DiomanKey`'s resolved-path scheme.
- Fix: `DiomanRetry` now honors `extra['retry'] == false` on the business-retry (`onResponse`) path
  too, and gives up immediately after the back-off delay if the request was cancelled.
- Fix: `DiomanCancel` re-registers a token it previously injected when `DiomanRetry` re-dispatches
  the same `RequestOptions` — previously `cancelAll()` silently stopped covering a request once it
  entered its first retry.
- Fix: `DiomanEnvs` no longer resets a user-configured `responseType` back to the `json` default
  when an applied rule didn't explicitly set one.
- `DiomanCache` gained `maxEntries` (default 500) to LRU-bound the store, which previously grew
  without limit under deep `DiomanKey` keys.
- Added `test/dioman_test.dart`, a fake-adapter regression suite covering all of the above.
