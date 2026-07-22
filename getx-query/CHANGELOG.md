## 0.1.1

- Fix: `refetchOnResume` now actually takes effect — every `useQuery`/`useInfiniteQuery`
  (standalone, via `QueryScope`, or on a `BaseViewModel`/`GetBaseViewModel`) subscribes its own
  observer to app-foreground-resume via `AppLifecycleListener(onResume: observer.onResume)`,
  matching flutter_query's own hooks. Each query's individual `stale`/`always`/`never` policy is
  now respected.
  - Previously, standalone `useQuery`/`useInfiniteQuery` and `QueryScope` had no resume handling
    at all, so `refetchOnResume` was silently a no-op.
  - Previously, `BaseViewModel`/`GetBaseViewModel` instead ran a blanket, client-wide
    `invalidateQueries()` on every resume — refetching *all* queries on the shared `QueryClient`
    regardless of their `refetchOnResume` setting (including ones explicitly set to `never`), and
    regardless of whether they were actually stale.

## 0.1.0

- First release. An [Rx]-backed bridge that brings
  [`flutter_query`](https://pub.dev/packages/flutter_query) to GetX:
  - `useQuery` / `useQueryClient` — call from any function, render with `Obx`.
    `queryKey`/`queryFn` are named and required on `useQuery`, `fetchQuery`, `prefetchQuery`,
    `ensureQueryData`, and `QueryScope.watch`/`prefetchQuery`.
  - `useInfiniteQuery` — paginated data with page accumulation: `fetchNextPage`/`fetchPreviousPage`,
    `hasNextPage`/`hasPreviousPage`, `isFetchingNextPage`/`isFetchingPreviousPage`; also available as
    `this.useInfiniteQuery(...)` inside `BaseViewModel`/`GetBaseViewModel` with the same auto-dispose
    tracking as `useQuery`
  - `useQueries` — run a dynamic list of queries in parallel; pass `combine` to derive a single value
    from all results (read via the returned `combined()` inside `Obx` for fine-grained rebuilds)
  - `useMutation` — imperative create/update/delete with reactive `isPending`/`isSuccess`/`isError`
  - Reactive params: pass `RxBool`/`RxString`/`RxInt`/`Rx<T>` **or GetX's reactive collections**
    (`RxList`/`RxMap`/`RxSet`) in `queryKey` or `enabled` for auto re-fetch
  - `useIsFetching` / `useIsMutating` — live `(RxInt, dispose)` counts of in-flight
    queries/mutations, updated on every cache event
  - `QueryResult` / `MutationResult` — `Rx`-backed result wrappers. `dispose()` is idempotent;
    calling `refetch()`/`mutate()`/`reset()` after dispose is a no-op, and `mutateAsync()` rejects
    with a `StateError` instead of touching an unmounted observer
  - `QueryScope` — groups queries for shared disposal without a full ViewModel (a plain
    `StatefulWidget`, a dialog, a test, ...)
  - `BaseViewModel` (constructor-injected client) and `GetBaseViewModel`
    (GetxController) that auto-track and dispose subscriptions. Their shared
    invalidate-all-on-resume behavior is coalesced across ViewModels that share a `QueryClient` —
    one `invalidateQueries()` call per client per resume, not one per ViewModel
  - `QueryService` — a `GetxService` `QueryClient` wired to `connectivity_plus`
    for `refetchOnReconnect`. Every default option is an individually-overridable named
    constructor param, merged field-by-field with getx_query's own defaults
  - Barrel re-exports `flutter_query`'s public types (single import).
