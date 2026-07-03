---
name: getquery
description: >-
  Work on getquery — TanStack-Query-style data fetching for GetX: an Rx-backed useQuery/useMutation
  bridge over flutter_query (no HookWidget, render with Obx), plus auto-disposing view models
  (BaseViewModel/GetBaseViewModel), QueryScope/watchQuery, and a connectivity-wired QueryService.
  Read BEFORE modifying anything under lib/src/, bumping flutter_query, or adding a client method.
  Covers the private-internals fragility, the observer-driving mechanism, disposal/leak invariants,
  and how to verify. Triggers on: getquery, flutter_query, useQuery, useMutation, QueryObserver,
  MutationObserver, GetX Rx, Obx, QueryResult, GetBaseViewModel, QueryService, refetchOnReconnect.
---

# getquery

Flutter package (`sdk ^3.5.0`, `flutter >=3.24.0`). An **`Rx`-backed bridge that brings
`flutter_query` (^0.10.0) to GetX**: call `useQuery`/`useMutation` from any function — no
`HookWidget`, no `BuildContext` — and render with `Obx`. Deps: `flutter_query`, `get`,
`connectivity_plus`, `meta`. Barrel `lib/getquery.dart` re-exports flutter_query's public types and
`hide`s the Hook symbols getquery replaces (single import).

Files under `lib/src/`: `use_query.dart`, `use_mutation.dart`, `query_result.dart`,
`mutation_result.dart`, `watch.dart`, `base_view_model.dart` (713 lines, the core), `query_service.dart`.
Real test suite: `test/use_query_test.dart` + `test/widget_integration_test.dart` (**64 tests, verified green**).

## THE headline fragility — private flutter_query internals

getquery drives queries outside a `HookWidget` by importing flutter_query's **private `src/`
observers** and using `@internal` members. This is the #1 thing to understand before any
`flutter_query` version bump:

- `use_query.dart:7` and `base_view_model.dart:20` → `import 'package:flutter_query/src/core/query_observer.dart';`
- `use_mutation.dart:7` and `base_view_model.dart:19` → `import 'package:flutter_query/src/core/mutation_observer.dart';`
- Every consumer file leads with `// ignore_for_file: implementation_imports, invalid_use_of_internal_member`.
- Uses flutter_query `@internal` observer members: `onMount`/`onUnmount`/`subscribe`/`options=`/`result`
  (query), `mutate`/`mutateAsync`/`reset` (mutation).

Consequences a maintainer must respect:
- **Pinned to `flutter_query ^0.10.0`.** A minor bump that reshuffles those `src/` files or renames
  observer members breaks getquery at compile time — re-verify the two import paths and the member
  names on any bump.
- `dart pub publish` emits an `implementation_imports` warning — the README documents git/private
  publishing as the workaround. Don't "fix" the warning by removing the imports; they're load-bearing.
- The `hide` lists (in `getquery.dart` and per-file) shadow flutter_query's public `QueryResult`/
  `MutationResult`/`useQuery`/… with the local Rx versions. If you add a new local shadow, add it to
  the `hide`; if flutter_query renames a hidden symbol, the hide silently becomes a no-op.

## How it drives a query (the manual HookWidget-build loop)

`useQuery` (`use_query.dart`) reimplements what a HookWidget build does, by hand. **Ordering is
load-bearing** — don't reorder:

1. Resolve client: `client ?? useQueryClient()`; `useQueryClient()` = `Get.find<QueryService>().client`
   (global client via GetX service locator, not context).
2. Build a private `QueryObserver` from `QueryOptions` (Rx values unwrapped via `_plain`, key via `_resolveKey`).
3. `observer.onMount()` → **`result.update(observer.result)` seed** → `observer.subscribe(result.update)`.
   Seeding before subscribe is required so the first snapshot isn't lost.
4. **Reactive Rx params:** `_bindRx([...queryKey, enabled], update)` subscribes an updater closure to
   the `.stream` of every `Rx` in the key + `enabled`. On tick it rebuilds `observer.options = QueryOptions(...)`.
   **Infinite-rewire avoidance depends ENTIRELY on flutter_query's `QueryObserver.options=` internally
   diffing the key and only refetching on real change** — getquery does no local dedup. If you swap to
   an observer that refetches unconditionally on `options=`, you create a loop.
5. Disposal: `disposeCallback` runs `unsubscribe()` → `observer.onUnmount()` → cancels every Rx stream sub.

`useMutation` mirrors this with `MutationObserver`; `mutate`/`mutateAsync`/`reset` are wired directly
to observer methods (they're `late` fields on `MutationResult`). Mutations have no reactive key → no Rx subs.

## Disposal & leak invariants (do NOT break)

- **Standalone `useQuery`/`useMutation`/`watchQuery` are NOT tracked — the caller MUST `dispose()`**,
  or the observer + Rx stream subscriptions leak. Only `_Core` (behind the view models) and
  `QueryScope` auto-track and auto-dispose.
- **No double-dispose guard** in `QueryResult`/`MutationResult.dispose()` — `disposeCallback` is never
  nulled, so calling `dispose()` twice calls `unsubscribe`/`onUnmount` twice. The one exception is
  `QueryScope.dispose()`, which `_results.clear()`s after disposing (idempotent-ish).
- `enabled` is cast `as bool?` — passing a non-bool `Rx` throws at runtime. Only `bool?`/`RxBool`/`Rx<bool>`.
- `Rx`-backing: each result holds one `Rx<fq.QueryResult?>`; every getter reads `_rx.value?…` so
  touching any getter inside `Obx` registers the dependency. `data` falls back to the ctor-stored
  `placeholder` while `_rx.value == null`. `isStale` defaults **true** before the first snapshot.
- **`useIsFetching`/`useIsMutating` are non-reactive stubs** — seeded once, never update. Do not build
  UI assuming they're live.

## base_view_model.dart architecture (the core)

- All logic is in the private `_Core`; the public surface is the `_QueryDelegate` mixin forwarding to
  `_core`; `BaseViewModel` and `GetBaseViewModel` supply the `_core`. **Adding a client method means
  editing `_Core` AND `_QueryDelegate`.** Note `_Core` re-implements `useQuery`/`useMutation`
  *independently* of the top-level `use_query.dart`/`use_mutation.dart` (duplicated logic — keep in sync).
- `_Core` tracks `_results`/`_mutations`; `dispose()` disposes all + `removeObserver(this)`. This is the
  auto-cleanup standalone hooks lack.
- `_Core` mixes in `WidgetsBindingObserver`; **`didChangeAppLifecycleState` on `resumed` calls
  `_client.invalidateQueries()` with no key → invalidates ALL queries.** A non-obvious global side
  effect; active only in view-model flows, not standalone hooks.
- `GetBaseViewModel extends GetxController`: `onInit`→`super.onInit(); _core.init()`;
  `onClose`→`_core.dispose(); super.onClose()`. Ordering (dispose before super.onClose) is deliberate;
  GetX calls these automatically → subscriptions auto-dispose on controller close (the main reason to
  prefer it over standalone hooks). `BaseViewModel` is framework-agnostic: constructor-inject a
  `QueryClient`, call `init()`/`dispose()` yourself (both `@mustCallSuper`).
- Global client resolution has **three call sites** to keep aligned: `useQueryClient()` (use_query),
  and inline `Get.find<QueryService>().client` (use_mutation, GetBaseViewModel). All resolve the same service.

## QueryService (query_service.dart)

`QueryService extends GetxService`, `late final client` built in `onInit()` (touching `client` before
GetX inits throws; register `permanent: true`). Defaults: 5-min stale, 10-min GC, retry exponential
`1<<count` s capped at 3 attempts. **`connectivity_plus` wiring for `refetchOnReconnect`:**
`connectivityChanges` maps `Connectivity().onConnectivityChanged → !results.contains(none)`. Invariant:
flutter_query requires this stream to **emit current state on first listen** — `connectivity_plus` does;
a stream that doesn't emit initially breaks reconnect refetch. `onClose()` calls `client.clear()`.

## Verify workflow

```bash
cd D:/workspaces/dart-flutter/getquery
flutter test        # acceptance gate — 64 tests (use_query + widget_integration), must be green
flutter analyze     # flutter_lints (analysis_options includes package:flutter_lints/flutter.yaml)
```

The integration tests pump real widgets with `Obx` and assert rebuilds; the unit tests cover reactive
params, disposal, and QueryScope cleanup. When changing behavior add/adjust a test, keep the
top-level hooks and `_Core`'s duplicated implementations in sync, and update BOTH READMEs (`README.md`
EN, `README.zh-CN.md` ZH) on any public API change. Re-check the two `flutter_query/src/` import paths
whenever bumping `flutter_query`.
