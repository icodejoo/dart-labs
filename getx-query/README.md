# getx_query

[![pub](https://img.shields.io/pub/v/getx_query.svg)](https://pub.dev/packages/getx_query)

> 中文文档：[README.zh-CN.md](./README.zh-CN.md)

**TanStack-Query-style data fetching for GetX.** A thin, `Rx`-backed bridge over [`flutter_query`](https://pub.dev/packages/flutter_query): call `useQuery` / `useMutation` from **any** function — no `HookWidget`, no `BuildContext` — and render with `Obx`.

> Key insight: `flutter_query` is built around Flutter Hooks (`useQuery` only works inside a `HookWidget`'s `build`). getx_query keeps flutter_query's caching/dedup/retry engine but swaps the Hook surface for GetX `Rx`, so a query is just a value you hold and observe with `Obx` — from a controller, a service, or a plain function.

- [Features](#features)
- [Install](#install)
- [Setup](#setup)
- [Quick start](#quick-start)
- [API](#api)
  - [useQuery](#usequery)
  - [Reactive parameters](#reactive-parameters)
  - [useMutation](#usemutation)
  - [QueryResult](#queryresult)
  - [MutationResult](#mutationresult)
  - [useInfiniteQuery](#useinfinitequery)
  - [InfiniteQueryResult](#infinitequeryresult)
  - [useQueries](#usequeries)
  - [useIsFetching / useIsMutating](#useisfetching--useismutating)
  - [QueryScope](#queryscope)
  - [BaseViewModel & GetBaseViewModel](#baseviewmodel--getbaseviewmodel)
  - [QueryService](#queryservice)
- [Publishing caveat](#publishing-caveat)
- [License](#license)

## Features

- **Hook-free `useQuery` / `useMutation`** — call from any function; the result is an `Rx`-backed object you render with `Obx`.
- **`useInfiniteQuery`** — paginated data with page accumulation: `fetchNextPage`/`fetchPreviousPage`, `hasNextPage`/`hasPreviousPage`, same Hook-free/reactive-parameter model as `useQuery`.
- **`useQueries` with `combine`** — run a dynamic list of queries in parallel and derive a single value from all of them; read `combined()` inside `Obx` for fine-grained rebuilds without React-style memoization.
- **Reactive parameters** — put reactive values (`RxBool`, `RxString`, `RxList`, `RxMap`, `RxSet`, `Rx<T>`, ...) in `queryKey` or `enabled`; the query re-fetches automatically when they change.
- **Auto-disposing view models** — `GetBaseViewModel` (a `GetxController`) and `BaseViewModel` track every subscription and dispose them on close.
- **Grouped lifecycle** — `QueryScope` collects several queries and disposes them together, for contexts that don't want a full ViewModel (a plain `StatefulWidget`, a dialog, a test).
- **Full `QueryClient` surface** — `invalidate/refetch/cancel/reset/removeQueries`, `fetch/prefetch/ensureQueryData`, `get/setQueryData`, `isFetching/isMutating`.
- **`QueryService`** — a `GetxService` `QueryClient` pre-wired to `connectivity_plus` so `refetchOnReconnect` works out of the box; every default is individually overridable.
- **Dispose-safe actions** — calling `refetch()` / `mutate()` / `mutateAsync()` / `reset()` after `dispose()` never throws into the void: fire-and-forget actions become no-ops, `mutateAsync()` rejects with a clear `StateError`.
- **Single import** — the barrel re-exports flutter_query's public types (`QueryClient`, `StaleDuration`, `RetryResolver`, ...).

## Install

```yaml
dependencies:
  getx_query: ^0.1.0
```

```dart
import 'package:getx_query/getx_query.dart';
```

## Setup

Register the shared client once (it wires up connectivity for you):

```dart
GetMaterialApp(
  initialBinding: BindingsBuilder(() {
    Get.put<QueryService>(QueryService(), permanent: true);
  }),
  home: const HomePage(),
);
```

## Quick start

```dart
class TodoViewModel extends GetBaseViewModel {
  final filter = 'all'.obs;

  late final todos = useQuery(
    queryKey: ['todos', filter],          // Rx in key → auto-refetch on change
    queryFn: (_) => api.getTodos(filter.value),
    staleDuration: StaleDuration(minutes: 5),
    placeholder: const [],
  );

  late final addTodo = useMutation<Todo, TodoInput>(
    (input, _) => api.addTodo(input),
    onSuccess: (_, __, ___, ____) => invalidateQueries(queryKey: ['todos']),
  );
}

// UI — no controller boilerplate, just Obx:
final vm = Get.put(TodoViewModel());

Obx(() => vm.todos.isLoading
    ? const CircularProgressIndicator()
    : TodoList(items: vm.todos.data ?? []));
```

A complete runnable app is in [`example/getx_query_example.dart`](./example/getx_query_example.dart).

## API

### useQuery

Subscribe to a cached query from any function — no ViewModel, no Widget required. Without `client` it resolves the global one from `QueryService`. **Remember to `dispose()`** the result (or use a view model / `QueryScope` that does it for you).

```dart
QueryResult<T> useQuery<T>({
  required List<Object?> queryKey,
  required QueryFn<T> queryFn,
  QueryClient? client,
  Object? enabled,
  T? placeholder,
  T? seed,
  DateTime? seedUpdatedAt,
  StaleDuration? staleDuration,
  GcDuration? gcDuration,
  RetryResolver? retry,
  Duration? refetchInterval,
  RefetchOnMount? refetchOnMount,
  RefetchOnResume? refetchOnResume,
  RefetchOnReconnect? refetchOnReconnect,
  NetworkMode? networkMode,
  Map<String, dynamic>? meta,
});
```

| Param | Meaning |
|---|---|
| `queryKey` *(required)* | Cache key. Reactive items (see below) trigger a refetch when they change. |
| `queryFn` *(required)* | Fetcher; receives a `QueryFunctionContext` (`queryKey`, `client`, `signal`, `meta`). |
| `client` | `QueryClient` to use. Defaults to `QueryService`'s global client. |
| `enabled` | `bool?` \| `RxBool` \| `Rx<bool>` — gates fetching; reactive values re-trigger on change. |
| `placeholder` | Shown while pending and uncached. Not persisted to cache. |
| `seed` | Initial data persisted to cache before the first real fetch. |
| `seedUpdatedAt` | Timestamp for `seed`, used for staleness calculation. |
| `staleDuration` | How long data stays fresh before becoming stale. |
| `gcDuration` | How long unused cache entries live before eviction. |
| `retry` | `(failureCount, error) => Duration?` — retry delay, or `null` to stop. |
| `refetchInterval` | Polling interval while mounted. `null` disables polling. |
| `refetchOnMount` | Refetch policy when this hook (re)mounts: `stale` / `always` / `never`. |
| `refetchOnResume` | Same, for app foreground resume. |
| `refetchOnReconnect` | Same, for network reconnect (needs `connectivityChanges` on the client). |
| `networkMode` | `online` (pause offline) / `always` / `offlineFirst`. |
| `meta` | Arbitrary metadata, readable from `queryFn`'s context. |

`useQueries(List<QueryOptions>, {combine})` subscribes to many at once — see [useQueries](#usequeries).

### Reactive parameters

Pass a reactive value directly — the query rewires when it changes, mirroring how flutter_query re-runs on every `HookWidget` build. Both scalar Rx types (`RxBool`, `RxString`, `RxInt`, `Rx<T>`, ...) and GetX's reactive collections (`RxList`, `RxMap`, `RxSet`) are recognized:

```dart
final userId  = 'u1'.obs;
final loggedIn = false.obs;
final tags    = <String>['news'].obs;   // RxList

final profile = useQuery(
  queryKey: ['user', userId, tags],   // RxString + RxList in key
  queryFn: (_) => api.getUser(userId.value, tags),
  enabled: loggedIn,                  // RxBool gates the fetch
);

userId.value = 'u2';         // → refetch
tags.add('sports');          // → refetch (RxList mutations count as a change)
loggedIn.value = true;       // → starts fetching
```

### useMutation

Perform create/update/delete with reactive `isPending`/`isSuccess`/`isError` state. Triggered imperatively via `mutate(vars)` (fire-and-forget) or `await mutateAsync(vars)` (throws on failure); `reset()` returns to idle.

```dart
MutationResult<TData, TVariables> useMutation<TData, TVariables>(
  MutateFn<TData, TVariables> mutationFn, {
  QueryClient? client,
  MutationOnMutate<TVariables, dynamic>? onMutate,
  MutationOnSuccess<TData, TVariables, dynamic>? onSuccess,
  MutationOnError<dynamic, TVariables, dynamic>? onError,
  MutationOnSettled<TData, dynamic, TVariables, dynamic>? onSettled,
  List<Object?>? mutationKey,
  GcDuration? gcDuration,
  RetryResolver? retry,
  NetworkMode? networkMode,
  Map<String, dynamic>? meta,
});
```

| Param | Meaning |
|---|---|
| `mutationFn` *(required)* | `(variables, context) => Future<TData>` — performs the mutation. |
| `client` | Defaults to `QueryService`'s global client. |
| `onMutate` | Runs before the mutation fires; return a value used as `context` in the other callbacks (e.g. for optimistic updates). |
| `onSuccess` | Runs after `mutationFn` resolves. |
| `onError` | Runs after `mutationFn` throws. |
| `onSettled` | Runs after either success or error. |
| `mutationKey` | Groups this mutation for `isMutating`/`useIsMutating` filtering. |
| `gcDuration` | How long the mutation's result stays cached after settling. |
| `retry` | Same shape as `useQuery`'s `retry`. |
| `networkMode` | Same as `useQuery`'s `networkMode`. |
| `meta` | Arbitrary metadata. |

### QueryResult

`Rx`-backed wrapper you observe with `Obx`. Returned by `useQuery` and `QueryScope.watch`.

| Member | Meaning |
|---|---|
| `data` | `T?` — cached/fetched value, falls back to `placeholder`. |
| `isIdle` | No snapshot yet (before first `onMount`). |
| `isLoading` | Pending with no data yet. |
| `isFetching` | A fetch is in flight (including background refetch). |
| `isSuccess` / `isError` | Last fetch outcome. |
| `isStale` | Whether cached data has passed `staleDuration`. |
| `isFetchedAfterMount` | Whether at least one fetch completed since this observer mounted. |
| `error` | Error from the last failed fetch, if any. |
| `updatedAt` | Timestamp of the last successful data update. |
| `refetch()` | Manually refetch. No-op after `dispose()`. |
| `dispose()` | Unsubscribe and release the observer. Idempotent. |

### MutationResult

`Rx`-backed wrapper for a mutation's state. Returned by `useMutation`.

| Member | Meaning |
|---|---|
| `data` | Result of the last successful `mutationFn` call. |
| `error` | Error from the last failed call. |
| `variables` | The `vars` passed to the most recent `mutate`/`mutateAsync`. |
| `failureCount` | Consecutive failures for the current attempt. |
| `isIdle` / `isPending` / `isSuccess` / `isError` | Status flags. |
| `isPaused` | Retry is waiting (e.g. offline under `NetworkMode.online`). |
| `mutate(vars)` | Fire-and-forget. Errors land in `error`, not thrown. No-op after `dispose()`. |
| `mutateAsync(vars)` | Awaitable, throws on failure. Rejects with `StateError` after `dispose()`. |
| `reset()` | Back to idle. No-op after `dispose()`. |
| `dispose()` | Idempotent. |

### useInfiniteQuery

Paginated data with automatic page accumulation — same Hook-free, reactive-parameter model as `useQuery`, plus pagination. Also available as `this.useInfiniteQuery(...)` inside `BaseViewModel`/`GetBaseViewModel`, tracked and auto-disposed exactly like `useQuery`.

```dart
InfiniteQueryResult<TData, TPageParam> useInfiniteQuery<TData, TPageParam>({
  required List<Object?> queryKey,
  required InfiniteQueryFn<TData, TPageParam> queryFn,
  required TPageParam initialPageParam,
  required NextPageParamBuilder<TData, TPageParam> nextPageParamBuilder,
  PrevPageParamBuilder<TData, TPageParam>? prevPageParamBuilder,
  QueryClient? client,
  Object? enabled,
  int? maxPages,
  NetworkMode? networkMode,
  StaleDuration? staleDuration,
  GcDuration? gcDuration,
  InfiniteData<TData, TPageParam>? placeholder,
  RefetchOnMount? refetchOnMount,
  RefetchOnResume? refetchOnResume,
  RefetchOnReconnect? refetchOnReconnect,
  Duration? refetchInterval,
  RetryResolver? retry,
  bool? retryOnMount,
  InfiniteData<TData, TPageParam>? seed,
  DateTime? seedUpdatedAt,
  Map<String, dynamic>? meta,
});
```

`queryKey`, `client`, `enabled`, `networkMode`, `staleDuration`, `gcDuration`, `placeholder`, `refetchOnMount`, `refetchOnResume`, `refetchOnReconnect`, `refetchInterval`, `retry`, `seed`, `seedUpdatedAt`, `meta` mean the same as on `useQuery`. Pagination-specific params:

| Param | Meaning |
|---|---|
| `queryFn` *(required)* | `(InfiniteQueryFunctionContext) => Future<TData>` — fetches **one page**; `context.pageParam` is the param for that page. |
| `initialPageParam` *(required)* | Param used for the first page fetch. |
| `nextPageParamBuilder` *(required)* | `(InfiniteData data) => TPageParam?` — next page's param from pages fetched so far, or `null` if there are no more. |
| `prevPageParamBuilder` | Same, for backward pagination. Omit to disable `fetchPreviousPage`. |
| `maxPages` | Cap on pages kept in memory; oldest pages (from the opposite fetch direction) are dropped past this. |
| `retryOnMount` | Whether to retry a failed query when a new observer mounts. |

```dart
final feed = useInfiniteQuery(
  queryKey: ['feed'],
  queryFn: (ctx) => api.getFeed(page: ctx.pageParam),
  initialPageParam: 0,
  nextPageParamBuilder: (data) => data.pages.last.isEmpty ? null : data.pages.length,
);

Obx(() => ListView(
  children: [
    for (final page in feed.pages) ...page.map((e) => Text(e)),
    if (feed.hasNextPage)
      TextButton(onPressed: feed.fetchNextPage, child: const Text('Load more')),
  ],
));
feed.dispose();
```

### InfiniteQueryResult

Same status flags as `QueryResult`, plus pagination state. Returned by `useInfiniteQuery`.

| Member | Meaning |
|---|---|
| `data` | `InfiniteData<TData, TPageParam>?` — all fetched pages + their params. |
| `pages` | Shorthand for `data.pages` (`const []` before the first snapshot). |
| `pageParams` | Shorthand for `data.pageParams`. |
| `isIdle` / `isLoading` / `isFetching` / `isSuccess` / `isError` / `isStale` / `isFetchedAfterMount` | Same meaning as on `QueryResult`. |
| `hasNextPage` / `hasPreviousPage` | Whether `nextPageParamBuilder`/`prevPageParamBuilder` returned non-null for the last page. |
| `isFetchingNextPage` / `isFetchingPreviousPage` | Whether a `fetchNextPage()`/`fetchPreviousPage()` call is in flight. |
| `isFetchNextPageError` / `isFetchPreviousPageError` | Whether the last fetch in that direction failed. |
| `error` / `updatedAt` | Same meaning as on `QueryResult`. |
| `refetch()` | Refetch all pages from scratch. No-op after `dispose()`. |
| `fetchNextPage()` | Fetch the next page. No-op if `hasNextPage` is false, or after `dispose()`. |
| `fetchPreviousPage()` | Fetch the previous page. No-op if `hasPreviousPage` is false, or after `dispose()`. |
| `dispose()` | Idempotent. |

### useQueries

Runs an arbitrary (and arbitrarily-sized — unlike React, there's no Hook-order rule to work around) list of queries in parallel. Pass `combine` to derive one value from all of them, à la [TanStack Query's `useQueries({ combine })`](https://tanstack.com/query/v5/docs/framework/react/reference/useQueries) — but there's no need for `combine` to memoize away re-renders here: call the returned `combined()` getter *inside* `Obx`, and GetX's fine-grained dependency tracking rebuilds only on the specific fields `combine` actually reads.

```dart
(List<QueryResult>, TCombined Function(), VoidCallback) useQueries<TCombined>(
  List<QueryOptions> options, {
  QueryClient? client,
  TCombined Function(List<QueryResult> results)? combine,
});
```

| Param | Meaning |
|---|---|
| `options` *(required)* | One flutter_query `QueryOptions(queryKey, queryFn, ...)` per query. |
| `client` | Shared client for every query in the list. |
| `combine` | `(results) => TCombined` — derives one value. Calling the returned `combined()` without passing this throws `StateError`. |

Returns `(results, combined, disposeAll)`:

```dart
final (results, combined, disposeAll) = useQueries(
  [
    QueryOptions(['users'],    (_) => api.getUsers()),
    QueryOptions(['products'], (_) => api.getProducts()),
  ],
  combine: (rs) => rs.every((r) => r.isSuccess),
);
Obx(() => Text('all loaded: ${combined()}'));
disposeAll();
```

### useIsFetching / useIsMutating

Live counts of in-flight queries/mutations — the `RxInt` updates on every cache event, not just once at creation.

```dart
(RxInt, VoidCallback) useIsFetching({QueryClient? client, List<Object?>? queryKey, bool exact = false});
(RxInt, VoidCallback) useIsMutating({QueryClient? client, List<Object?>? mutationKey, bool exact = false});
```

| Param | Meaning |
|---|---|
| `client` | Defaults to `QueryService`'s global client. |
| `queryKey` / `mutationKey` | Filter to a specific key; `null` counts everything. |
| `exact` | `true` matches the key exactly; `false` (default) matches by prefix. |

Returns `(count, dispose)` — own the callback and call it to stop observing:

```dart
final (fetchingCount, dispose) = useIsFetching();
Obx(() => fetchingCount.value > 0
    ? const LinearProgressIndicator()
    : const SizedBox());
dispose();
```

### QueryScope

Groups several `useQuery` results so they dispose together — for contexts that want grouped query lifecycle **without** a full `BaseViewModel`/`GetBaseViewModel`: a plain `StatefulWidget`, a dialog/bottom sheet's local state, a test, or any place you don't want the ceremony of a GetX controller (`Get.put`/`Get.delete`, route bindings) just to manage two or three queries.

Constructor takes an optional `client` — omit it to resolve the global one from `QueryService`, same as `useQuery`.

| Member | Meaning |
|---|---|
| `watch({queryKey, queryFn, ...})` | Same options as `useQuery`; the returned `QueryResult` is tracked by this scope. |
| `prefetchQuery({queryKey, queryFn})` | Warms the cache without holding a result. |
| `invalidateQueries({queryKey, exact, refetchType})` | Same as `QueryClient.invalidateQueries`, using this scope's client. |
| `getQueryData<T>(queryKey)` | Read the cache directly. |
| `setQueryData<T>(queryKey, updater)` | Write the cache directly. |
| `mutate(fn, {invalidates})` | Runs `fn`, then invalidates each key in `invalidates`. |
| `dispose()` | Disposes every `watch()` result tracked by this scope, then clears the tracking list. |

**Plain `StatefulWidget`, no ViewModel at all** — the scope lives on the `State` and is disposed alongside it:

```dart
class ShopPage extends StatefulWidget {
  const ShopPage({super.key});
  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  late final _scope = QueryScope();
  late final items = _scope.watch(queryKey: ['shop', 'items'], queryFn: (_) => api.items());

  @override
  void dispose() {
    _scope.dispose(); // disposes `items` too
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Obx(() => ItemList(items: items.data ?? []));
}
```

**Grouping several related queries + a shared explicit client:**

```dart
final scope = QueryScope(client: myClient);
final deposits = scope.watch(queryKey: ['deposit', 'list'], queryFn: (_) => api.getList());
final balance  = scope.watch(queryKey: ['wallet', 'balance'], queryFn: (_) => api.getBalance());

Obx(() => Text('${balance.data}'));
await scope.mutate(() => api.withdraw(10), invalidates: [['wallet', 'balance']]);
scope.dispose(); // disposes both deposits and balance
```

**In a test** — no GetX registration needed at all:

```dart
final scope = QueryScope(client: freshTestClient());
final result = scope.watch(queryKey: ['x'], queryFn: (_) async => 'value');
await pump();
expect(result.data, 'value');
scope.dispose();
```

### BaseViewModel & GetBaseViewModel

Both mix in the full `QueryClient` API and track every subscription (`useQuery`, `useMutation`, `useInfiniteQuery`) for automatic cleanup.

- **`GetBaseViewModel`** — extends `GetxController`; wires `onInit`/`onClose` automatically. Resolves the client from `QueryService` unless you pass one.
- **`BaseViewModel`** — framework-agnostic; constructor-inject a `QueryClient`, call `init()` / `dispose()` yourself (both `@mustCallSuper`).

Each `useQuery`/`useInfiniteQuery` — whether called standalone, via `QueryScope`, or on a ViewModel — honors its own `refetchOnResume` policy individually on app foreground resume (`stale` / `always` / `never`), same as calling flutter_query's hooks directly. There is no blanket, client-wide invalidation on resume.

| Member | Meaning |
|---|---|
| `useQuery({queryKey, queryFn, ...})` | Same options/return as top-level `useQuery`. |
| `useMutation(mutationFn, {...})` | Same options/return as top-level `useMutation`. |
| `useInfiniteQuery({queryKey, queryFn, ...})` | Same options/return as top-level `useInfiniteQuery`. |
| `fetchQuery({queryKey, queryFn, ...})` | Fetch once, `await` the raw result, and populate the cache. |
| `prefetchQuery({queryKey, queryFn, ...})` | Same, but discards the result — just warms the cache. |
| `ensureQueryData({queryKey, queryFn, ...})` | Return cached data if fresh, otherwise fetch. |
| `getQueryData<T>(queryKey)` | Read the cache directly. |
| `getQueryState<T>(queryKey)` | Read the full `QueryState` (status, timestamps, ...) for a key. |
| `setQueryData<T>(queryKey, updater, {updatedAt})` | Write the cache directly. |
| `invalidateQueries({queryKey, exact, predicate, refetchType})` | Mark matching queries stale and (by default) refetch active ones. |
| `refetchQueries({queryKey, exact, predicate})` | Force a refetch without touching staleness. |
| `cancelQueries({queryKey, exact, predicate, revert, silent})` | Cancel in-flight fetches for matching queries. |
| `resetQueries({queryKey, exact, predicate})` | Reset matching queries to their initial state. |
| `removeQueries({queryKey, exact, predicate})` | Remove matching entries from the cache entirely. |
| `isFetching({queryKey, exact, predicate})` | Count of matching queries currently fetching. |
| `isMutating({mutationKey, exact, predicate})` | Count of matching mutations currently pending. |
| `mutate(fn, {invalidates})` | Imperative fire-and-invalidate helper — for reactive loading/error state use `useMutation` instead. |
| `clear()` | Clears the whole `QueryClient` cache. |

### QueryService

A `GetxService` holding a `QueryClient` and subscribed to `connectivity_plus` for reconnect-driven refetch. `useQueryClient()` returns it. There's only ever one registered `QueryService` — `useQueryClient()` / `GetBaseViewModel`'s default resolution always return *that* instance's `client`, whatever options it was constructed with; there's no separate hidden "default" client to fall back to.

Every default is an individually-overridable named constructor param, merged field-by-field with getx_query's own defaults — override just what you need, everything else keeps getx_query's defaults:

| Param | getx_query default | Meaning |
|---|---|---|
| `enabled` | `true` | Whether queries auto-fetch by default. |
| `networkMode` | `NetworkMode.online` | Default offline behavior. |
| `staleDuration` | 5 minutes | Default freshness window. |
| `gcDuration` | 10 minutes | Default cache-eviction delay. |
| `refetchInterval` | `null` (off) | Default polling interval. |
| `refetchOnMount` / `refetchOnResume` / `refetchOnReconnect` | `stale` | Default refetch policy for each trigger. |
| `retry` | 3 attempts, exponential backoff (1s/2s/4s) | Default retry policy. |
| `retryOnMount` | `true` | Retry a failed query when a new observer mounts. |
| `meta` | `null` | Default metadata attached to every query. |
| `connectivityChanges` | `connectivity_plus` wiring | Connectivity source for `refetchOnReconnect`; must emit current state on first listen. |

```dart
Get.put<QueryService>(
  QueryService(gcDuration: GcDuration(minutes: 30)), // staleDuration/retry stay at getx_query's defaults
  permanent: true,
);
```

## Publishing caveat

> **Important.** getx_query reaches into flutter_query's **private internals** — it imports `package:flutter_query/src/core/query_observer.dart` and `.../mutation_observer.dart` and uses `@internal` members. That's what lets it drive queries outside a `HookWidget`.
>
> Consequences:
> - It is pinned to a compatible `flutter_query` version (`^0.10.0`); a minor bump that reshuffles those `src/` files can break it.
> - `dart pub publish` will emit an `implementation_imports` warning. Publishing privately (a git dependency or a private pub server) is the smoother path unless/until flutter_query exposes `QueryObserver`/`MutationObserver` publicly.
>
> Use it as a git/path dependency if pub.dev's warning is a blocker:
> ```yaml
> dependencies:
>   getx_query:
>     git:
>       url: https://github.com/icodejoo/dart-labs.git
>       path: getx-query
> ```

## License

MIT
