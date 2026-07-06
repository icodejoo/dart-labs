---
name: getx_query
description: >-
  Work on getx_query — TanStack-Query-style data fetching for GetX: an Rx-backed useQuery/useMutation
  bridge over flutter_query (no HookWidget, render with Obx), plus auto-disposing view models
  (BaseViewModel/GetBaseViewModel), QueryScope, and a connectivity-wired QueryService.
  Read BEFORE modifying anything under lib/src/, bumping flutter_query, or adding a client method.
  Covers the private-internals fragility, the observer-driving mechanism, disposal/leak invariants,
  and how to verify. Triggers on: getx_query, flutter_query, useQuery, useMutation, QueryObserver,
  MutationObserver, GetX Rx, Obx, QueryResult, GetBaseViewModel, QueryService, refetchOnReconnect.
---

# getx_query

Flutter package (`sdk ^3.5.0`, `flutter >=3.24.0`). An **`Rx`-backed bridge that brings
`flutter_query` (^0.10.0) to GetX**: call `useQuery`/`useMutation` from any function — no
`HookWidget`, no `BuildContext` — and render with `Obx`. Deps: `flutter_query`, `get`,
`connectivity_plus`, `meta`. Barrel `lib/getx_query.dart` re-exports flutter_query's public types and
`hide`s the Hook symbols getx_query replaces (single import).

Files under `lib/src/`: `use_query.dart`, `use_mutation.dart`, `use_infinite_query.dart`,
`query_result.dart`, `mutation_result.dart`, `infinite_query_result.dart`, `query_scope.dart`
(just `QueryScope` — `watchQuery` was removed, see below), `base_view_model.dart` (the core),
`query_service.dart`, `reactive.dart` (shared, non-exported Rx helpers — see below).
Real test suite: `test/use_query_test.dart` + `test/widget_integration_test.dart` (**78 tests, verified
green**).

**Public API shape:** `queryKey` and `queryFn` are always named + required (`useQuery({required
queryKey, required queryFn, ...})`, same for `fetchQuery`/`prefetchQuery`/`ensureQueryData`/
`QueryScope.watch`/`QueryScope.prefetchQuery`). This is deliberate — don't revert to positional for
these two params even though flutter_query itself takes them positionally underneath (that internal
`QueryOptions(...)` call is a different, external API — leave it positional, it isn't ours to change).

**`watchQuery` was removed (pre-1.0, never published, so no deprecation cycle needed).** It was
`useQuery(client: ..., ...)` with `client` forced positional-required and the result pre-bundled as
`(result, result.dispose)` — zero capability over calling `useQuery` directly with an explicit
`client:`. If a future feature needs a genuinely different capability (not just a different
call-site shape), give it a real reason to exist; don't resurrect this exact shim.

## THE headline fragility — private flutter_query internals

getx_query drives queries outside a `HookWidget` by importing flutter_query's **private `src/`
observers** and using `@internal` members. This is the #1 thing to understand before any
`flutter_query` version bump:

- `use_query.dart:7` and `base_view_model.dart:20` → `import 'package:flutter_query/src/core/query_observer.dart';`
- `use_mutation.dart:7` and `base_view_model.dart:19` → `import 'package:flutter_query/src/core/mutation_observer.dart';`
- `use_infinite_query.dart` reuses the **same** `query_observer.dart` import — `InfiniteQueryObserver`
  is defined via `part of 'query_observer.dart';` in flutter_query's own source
  (`infinite_query_observer.dart`), so it's already reachable with zero new import surface. Its shape
  mirrors `QueryObserver` exactly: `onMount`/`onUnmount`/`subscribe`/`options=`/`result`, plus
  `fetchNextPage()`/`fetchPreviousPage()`.
- `use_query.dart`'s `useIsFetching`/`useIsMutating` also reach into `client.cache`/`client.mutationCache`
  (both `@internal` getters on `QueryClient`) and subscribe to their `QueryCacheEvent`/
  `MutationCacheEvent` streams to drive live counts — see below.
- Every consumer file leads with `// ignore_for_file: implementation_imports, invalid_use_of_internal_member`.
- Uses flutter_query `@internal` observer members: `onMount`/`onUnmount`/`subscribe`/`options=`/`result`
  (query), `mutate`/`mutateAsync`/`reset` (mutation).

Consequences a maintainer must respect:
- **Pinned to `flutter_query ^0.10.0`.** A minor bump that reshuffles those `src/` files or renames
  observer members, or the `cache`/`mutationCache` getters / their event types, breaks getx_query at
  compile time — re-verify all of these on any bump.
- `dart pub publish` emits an `implementation_imports` warning — the README documents git/private
  publishing as the workaround. Don't "fix" the warning by removing the imports; they're load-bearing.
- The `hide` lists (in `getx_query.dart` and per-file) shadow flutter_query's public `QueryResult`/
  `MutationResult`/`useQuery`/… with the local Rx versions. If you add a new local shadow, add it to
  the `hide`; if flutter_query renames a hidden symbol, the hide silently becomes a no-op.

## How it drives a query (the manual HookWidget-build loop)

`useQuery` (`use_query.dart`) reimplements what a HookWidget build does, by hand. **Ordering is
load-bearing** — don't reorder:

1. Resolve client: `client ?? useQueryClient()`; `useQueryClient()` = `Get.find<QueryService>().client`
   (global client via GetX service locator, not context).
2. Build a private `QueryObserver` from `QueryOptions` (reactive values unwrapped via `_plain`, key via
   `_resolveKey`).
3. `observer.onMount()` → **`result.update(observer.result)` seed** → `observer.subscribe(result.update)`.
   Seeding before subscribe is required so the first snapshot isn't lost.
4. **Reactive params:** `bindReactive([...queryKey, enabled], update)` subscribes an updater closure to
   the `.stream` of every reactive item in the key + `enabled`. On tick it rebuilds
   `observer.options = QueryOptions(...)`.
   **Infinite-rewire avoidance depends ENTIRELY on flutter_query's `QueryObserver.options=` internally
   diffing the key and only refetching on real change** — getx_query does no local dedup. If you swap to
   an observer that refetches unconditionally on `options=`, you create a loop.
5. Disposal: `disposeCallback` runs `unsubscribe()` → `observer.onUnmount()` → cancels every reactive
   stream sub.

`useMutation` mirrors this with `MutationObserver`; `mutate`/`mutateAsync`/`reset` on `MutationResult`
are thin public wrappers (guarded by `_disposed`) over `mutateImpl`/`mutateAsyncImpl`/`resetImpl`,
which are the raw fields wired directly to observer methods — see disposal invariants below for why
they're split.

### `reactive.dart` — `plainValue`/`resolveReactiveKey`/`bindReactive`, recognize `RxObjectMixin` not `Rx`

Shared (not duplicated — `use_query.dart`, `base_view_model.dart`, and `use_infinite_query.dart` all
import it) helper file, not exported from the barrel. Checks `v is RxObjectMixin` rather than `v is Rx`
so GetX's reactive collections (`RxList`/`RxMap`/`RxSet`) are recognized — they mix in `RxObjectMixin`
for `.value`/`.stream` but do NOT extend `Rx<T>` (only `RxBool`/`RxInt`/`RxString`/`RxDouble`/`Rx<T>`
do). Checking `is Rx` (or `is RxInterface`, which has no `.value`/`.stream` at all) silently drops
collection support. This file used to be duplicated per-consumer; it was extracted specifically so a
third `useInfiniteQuery` copy wouldn't triple the bug surface below — if you're tempted to inline a new
copy for a future hook, don't, import this instead.

**`plainValue` must return a snapshot copy for `RxList`/`RxMap`/`RxSet`, not `.value` directly** —
`List.of(v)` / `Set.of(v)` / `Map.of(v)`. These types mutate their backing collection **in place**
(`RxList.add()` calls `refresh()` on the *same* `_value` list), so returning the live reference would
hand flutter_query the exact same object on every rebuild: the "old" cached key and the "new" resolved
key would alias the same mutating list, so key-diffing sees no change even after a real mutation. This
was caught by a regression test (`useQuery - reactive queryKey (RxList)`) that failed silently (fetch
count stuck at 1) until the copy was added — if you touch `plainValue`, rerun that test specifically.

## Disposal & leak invariants (do NOT break)

- **Standalone `useQuery`/`useMutation`/`useInfiniteQuery` are NOT tracked — the caller MUST `dispose()`**,
  or the observer + reactive stream subscriptions leak. Only `_Core` (behind the view models) and
  `QueryScope` auto-track and auto-dispose.
- **`dispose()` is idempotent** on both `QueryResult` and `MutationResult` (`_disposed` flag guards
  `disposeCallback`) — safe to call more than once.
- **Actions are dispose-guarded too**, not just `dispose()` itself: `QueryResult.refetch()`,
  `MutationResult.mutate()`/`reset()` silently no-op after dispose; `MutationResult.mutateAsync()`
  rejects with `StateError` instead of calling into an unmounted observer. This matters for the real
  race where a mutation is still in flight when its owning ViewModel closes.
- `enabled` is cast `as bool?` — passing a non-bool reactive value throws at runtime. Only
  `bool?`/`RxBool`/`Rx<bool>`.
- `Rx`-backing: each result holds one `Rx<fq.QueryResult?>`; every getter reads `_rx.value?…` so
  touching any getter inside `Obx` registers the dependency. `data` falls back to the ctor-stored
  `placeholder` while `_rx.value == null`. `isStale` defaults **true** before the first snapshot.
- **`useIsFetching`/`useIsMutating` are live** — they return `(RxInt, VoidCallback)`, subscribing to
  `client.cache`/`client.mutationCache` (see above) and recomputing the count on every cache event.
  The caller owns the returned `VoidCallback` and must call it to unsubscribe (same "you must dispose
  this" contract as a standalone `useQuery`) — there's no `_Core` tracking for these two.
- **`useQueries`' `combine`** is a plain closure, not a live `Rx`. `combined()` just calls `combine(results)`
  on demand — it only becomes "reactive" because the caller invokes it *inside* `Obx`, at which point
  every `QueryResult` getter it touches (`.data`, `.isLoading`, ...) registers as a GetX dependency at
  that call site. There is no separate Rx wrapper for the combined value; don't add one, it'd be
  redundant with `Obx`'s own tracking and would need its own dispose story for no benefit.

## base_view_model.dart architecture (the core)

- All logic is in the private `_Core`; the public surface is the `_QueryDelegate` mixin forwarding to
  `_core`; `BaseViewModel` and `GetBaseViewModel` supply the `_core`. **Adding a client method means
  editing `_Core` AND `_QueryDelegate`.** Note `_Core` re-implements `useQuery`/`useMutation`/
  `useInfiniteQuery` *independently* of the top-level `use_query.dart`/`use_mutation.dart`/
  `use_infinite_query.dart` (duplicated wiring logic — keep in sync; the reactive-type handling itself
  is shared via `reactive.dart`, not duplicated).
- `_Core` tracks `_results`/`_mutations`/`_infiniteResults` (one list per result type); `dispose()`
  disposes all three + `removeObserver(this)`. This is the auto-cleanup standalone hooks lack.
- `_Core` mixes in `WidgetsBindingObserver`; **`didChangeAppLifecycleState` on `resumed` calls
  `_client.invalidateQueries()` with no key → invalidates ALL queries.** A non-obvious global side
  effect; active only in view-model flows, not standalone hooks.
  **Coalesced across ViewModels sharing a client:** every live `_Core` gets this callback on resume,
  which fire synchronously in the same event loop turn. `_Core._pendingResumeInvalidate` (a static
  `Set<QueryClient>`) + `scheduleMicrotask` collapse N simultaneous callbacks for the same client into
  one `invalidateQueries()` call. If you touch this, preserve the "first _Core to see this resume wins,
  the rest see `add()` return false" shape — don't key it per-`_Core` instance, that defeats the point.
- `GetBaseViewModel extends GetxController`: `onInit`→`super.onInit(); _core.init()`;
  `onClose`→`_core.dispose(); super.onClose()`. Ordering (dispose before super.onClose) is deliberate;
  GetX calls these automatically → subscriptions auto-dispose on controller close (the main reason to
  prefer it over standalone hooks). `BaseViewModel` is framework-agnostic: constructor-inject a
  `QueryClient`, call `init()`/`dispose()` yourself (both `@mustCallSuper`).
- Global client resolution has **three call sites** to keep aligned: `useQueryClient()` (use_query),
  and inline `Get.find<QueryService>().client` (use_mutation, GetBaseViewModel). All resolve the same service.

## QueryService (query_service.dart)

`QueryService extends GetxService`, `late final client` built in `onInit()` (touching `client` before
GetX inits throws; register `permanent: true`). Constructor takes **one nullable named param per
`DefaultQueryOptions` field** (`enabled`, `networkMode`, `staleDuration`, `gcDuration`,
`refetchInterval`, `refetchOnMount`, `refetchOnResume`, `refetchOnReconnect`, `retry`, `retryOnMount`,
`meta`) plus `connectivityChanges`. `onInit()` merges each `_field ?? <getx_query's own default for that
field>` and builds one `DefaultQueryOptions` from the merged values — this is deliberately field-level,
NOT "pass a whole `DefaultQueryOptions` object and swap it in wholesale". The whole-object approach was
tried first and rejected: a `DefaultQueryOptions` you're handed has already collapsed "caller didn't
touch this field" into "flutter_query's own default for this field" by construction time — there's no
way to tell those two apart on the received object, so a field you didn't mean to touch silently reverts
to flutter_query's raw default instead of getx_query's. Field-level params sidestep that entirely: `null`
unambiguously means "not overridden".

**If you add a field to this constructor because flutter_query added one to `DefaultQueryOptions`,
update the `??` merge line in `onInit()` in the same change** — this list is duplicated by design (see
field-level rationale above) so it doesn't auto-track upstream.

getx_query's own defaults (used when a field is left `null`): 5-min stale, 10-min GC, retry
exponential `1<<count` s capped at 3 attempts; every other field matches flutter_query's own
`DefaultQueryOptions` default already, so the merge target is the same value either way for those.
**`connectivity_plus` wiring for `refetchOnReconnect`:**
`connectivityChanges` maps `Connectivity().onConnectivityChanged → !results.contains(none)`. Invariant:
flutter_query requires this stream to **emit current state on first listen** — `connectivity_plus` does;
a stream that doesn't emit initially breaks reconnect refetch. `onClose()` calls `client.clear()`.

There is only ever **one** registered `QueryService` instance (`Get.put<QueryService>(..., permanent:
true)`) — `useQueryClient()` and `GetBaseViewModel`'s default resolution both do `Get.find<QueryService>().client`,
which is whichever instance was registered, custom options or not. There's no separate "default
singleton" hiding behind a custom one; the registered instance *is* the global one.

## Verify workflow

```bash
cd D:/workspaces/dart-labs/getx-query
flutter test        # acceptance gate — 78 tests (use_query + widget_integration), must be green
flutter analyze     # flutter_lints (analysis_options includes package:flutter_lints/flutter.yaml)
```

The integration tests pump real widgets with `Obx` and assert rebuilds; the unit tests cover reactive
params (including `RxList`), disposal/dispose-guards, `useIsFetching`/`useIsMutating` live reactivity,
`useInfiniteQuery` pagination (page fetch/append/exhaustion/dispose, standalone + `GetBaseViewModel`),
`useQueries`' `combine`, and QueryScope cleanup. When changing behavior add/adjust a test, keep the
top-level hooks and `_Core`'s duplicated wiring in sync, and update BOTH READMEs (`README.md` EN,
`README.zh-CN.md` ZH) on any public API change. Re-check the `flutter_query/src/` import paths and the
`cache`/`mutationCache` internal surface whenever bumping `flutter_query`.
