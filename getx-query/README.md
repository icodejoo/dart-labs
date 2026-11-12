# getx_query

[![pub](https://img.shields.io/pub/v/getx_query.svg)](https://pub.dev/packages/getx_query)

> 中文文档：[README.zh-CN.md](./README.zh-CN.md)

**TanStack-Query-style data fetching for GetX.** A thin layer over [`flutter_query`](https://pub.dev/packages/flutter_query) that exposes queries as `Rx` values. Call `useQuery` / `useMutation` from **any** function (no `HookWidget`, no `BuildContext`) and render with `Obx`.

> How it works: `flutter_query` is built on Flutter Hooks, so its `useQuery` only works inside a `HookWidget`'s `build`. getx_query keeps flutter_query's caching, deduplication and retry engine and replaces the Hook interface with GetX `Rx`. A query becomes a value you hold and watch with `Obx`, whether you are in a controller, a service or a plain function.

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

- **`useQuery` / `useMutation` without Hooks.** Call them from any function. The result is an `Rx`-backed object that you render with `Obx`.
- **`useInfiniteQuery`.** Paginated data that accumulates pages: `fetchNextPage`/`fetchPreviousPage`, `hasNextPage`/`hasPreviousPage`. It works like `useQuery`: no Hooks, reactive parameters.
- **`useQueries` with `combine`.** Run a list of queries in parallel (the list can change size) and derive one value from all of them. Read `combined()` inside `Obx` and only the fields it reads trigger a rebuild; no React-style memoization needed.
- **Reactive parameters.** Put reactive values (`RxBool`, `RxString`, `RxList`, `RxMap`, `RxSet`, `Rx<T>`, ...) in `queryKey` or `enabled`, and the query refetches when they change.
- **View models that clean up after themselves.** `GetBaseViewModel` (a `GetxController`) and `BaseViewModel` track every subscription and dispose of it when closed.
- **Grouped lifecycle.** `QueryScope` holds several queries and disposes them together. Use it where a full ViewModel is more than you need (a plain `StatefulWidget`, a dialog, a test).
- **All of `QueryClient`.** `invalidate/refetch/cancel/reset/removeQueries`, `fetch/prefetch/ensureQueryData`, `get/setQueryData`, `isFetching/isMutating`.
- **`QueryService`.** A `GetxService` that holds a `QueryClient` already connected to `connectivity_plus`, so `refetchOnReconnect` works without extra setup. Every default can be overridden on its own.
- **Safe to call after `dispose()`.** `refetch()`, `mutate()` and `reset()` become no-ops, and `mutateAsync()` rejects with a `StateError`.
- **One import.** `getx_query.dart` re-exports flutter_query's public types (`QueryClient`, `StaleDuration`, `RetryResolver`, ...).

## Install

```yaml
dependencies:
  getx_query: ^0.1.0
```

```dart
import 'package:getx_query/getx_query.dart';
```

## Setup

Register the shared client once. It also sets up connectivity for you:

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

// UI: just Obx, no controller boilerplate
final vm = Get.put(TodoViewModel());

Obx(() => vm.todos.isLoading
    ? const CircularProgressIndicator()
    : TodoList(items: vm.todos.data ?? []));
```

A complete runnable app is in [`example/getx_query_example.dart`](./example/getx_query_example.dart).

## API

### useQuery

Subscribe to a cached query from any function. No ViewModel or Widget is needed. Without `client`, it uses the global one from `QueryService`. **Call `dispose()`** on the result when you are done, or use a view model or `QueryScope`, which does it for you.

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
| `enabled` | `bool?` \| `RxBool` \| `Rx<bool>`. Controls whether it fetches; a change in a reactive value triggers it again. |
| `placeholder` | Shown while pending and uncached. Not persisted to cache. |
| `seed` | Initial data persisted to cache before the first real fetch. |
| `seedUpdatedAt` | Timestamp for `seed`, used for staleness calculation. |
| `staleDuration` | How long data stays fresh before becoming stale. |
| `gcDuration` | How long unused cache entries live before eviction. |
| `retry` | `(failureCount, error) => Duration?`. Returns the retry delay, or `null` to stop. |
| `refetchInterval` | Polling interval while mounted. `null` disables polling. |
| `refetchOnMount` | Refetch policy when this hook (re)mounts: `stale` / `always` / `never`. |
| `refetchOnResume` | Same, for app foreground resume. |
| `refetchOnReconnect` | Same, for network reconnect (needs `connectivityChanges` on the client). |
| `networkMode` | `online` (pause offline) / `always` / `offlineFirst`. |
| `meta` | Arbitrary metadata, readable from `queryFn`'s context. |

`useQueries(List<QueryOptions>, {combine})` subscribes to many at once. See [useQueries](#usequeries).

### Reactive parameters

Pass a reactive value directly and the query switches to the new value when it changes. This matches how flutter_query re-runs on every `HookWidget` build. Both scalar Rx types (`RxBool`, `RxString`, `RxInt`, `Rx<T>`, ...) and GetX's reactive collections (`RxList`, `RxMap`, `RxSet`) are supported:

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

Create, update or delete data, with reactive `isPending`/`isSuccess`/`isError` state. Trigger it with `mutate(vars)` (fire-and-forget) or `await mutateAsync(vars)` (throws on failure); `reset()` returns it to idle.

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
| `mutationFn` *(required)* | `(variables, context) => Future<TData>`. Runs the mutation. |
| `client` | Defaults to `QueryService`'s global client. |
| `onMutate` | Runs before the mutation starts. Its return value is passed as `context` to the other callbacks (useful for optimistic updates). |
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
| `data` | `T?`. The cached or fetched value; falls back to `placeholder`. |
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

Paginated data that accumulates pages automatically. It works like `useQuery` (no Hooks, reactive parameters) and adds pagination. Inside `BaseViewModel`/`GetBaseViewModel` you can also call `this.useInfiniteQuery(...)`; it is tracked and disposed just like `useQuery`.

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

`queryKey`, `client`, `enabled`, `networkMode`, `staleDuration`, `gcDuration`, `placeholder`, `refetchOnMount`, `refetchOnResume`, `refetchOnReconnect`, `refetchInterval`, `retry`, `seed`, `seedUpdatedAt`, `meta` mean the same as in `useQuery`. The pagination parameters:

| Param | Meaning |
|---|---|
| `queryFn` *(required)* | `(InfiniteQueryFunctionContext) => Future<TData>`. Fetches **one page**; `context.pageParam` is the param for that page. |
| `initialPageParam` *(required)* | Param used for the first page fetch. |
| `nextPageParamBuilder` *(required)* | `(InfiniteData data) => TPageParam?`. Returns the next page's param from the pages fetched so far, or `null` if there are no more. |
| `prevPageParamBuilder` | Same, for backward pagination. Omit to disable `fetchPreviousPage`. |
| `maxPages` | Maximum number of pages kept in memory. Beyond it, the oldest pages (at the end opposite to the fetch direction) are dropped. |
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
| `data` | `InfiniteData<TData, TPageParam>?`. All fetched pages and their params. |
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

Runs a list of queries in parallel. The list can be any size and can change, because unlike React there is no Hook-order rule here. Pass `combine` to derive one value from all of them, as in [TanStack Query's `useQueries({ combine })`](https://tanstack.com/query/v5/docs/framework/react/reference/useQueries). You don't need `combine` to avoid re-renders, though: call the returned `combined()` getter *inside* `Obx`, and GetX's dependency tracking rebuilds only when a field that `combine` actually reads changes.

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
| `combine` | `(results) => TCombined`. Derives one value. Calling the returned `combined()` without passing `combine` throws `StateError`. |

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

Live counts of queries/mutations in flight. The `RxInt` updates on every cache event, not just once when it is created.

```dart
(RxInt, VoidCallback) useIsFetching({QueryClient? client, List<Object?>? queryKey, bool exact = false});
(RxInt, VoidCallback) useIsMutating({QueryClient? client, List<Object?>? mutationKey, bool exact = false});
```

| Param | Meaning |
|---|---|
| `client` | Defaults to `QueryService`'s global client. |
| `queryKey` / `mutationKey` | Filter to a specific key; `null` counts everything. |
| `exact` | `true` matches the key exactly; `false` (default) matches by prefix. |

Returns `(count, dispose)`. Keep the callback and call it when you want to stop observing:

```dart
final (fetchingCount, dispose) = useIsFetching();
Obx(() => fetchingCount.value > 0
    ? const LinearProgressIndicator()
    : const SizedBox());
dispose();
```

### QueryScope

Groups several `useQuery` results so they are disposed together. Use it when you want that grouping **without** a full `BaseViewModel`/`GetBaseViewModel`: a plain `StatefulWidget`, the local state of a dialog or bottom sheet, a test, or anywhere a GetX controller (`Get.put`/`Get.delete`, route bindings) is too much for two or three queries.

The constructor takes an optional `client`. Without it, the global one from `QueryService` is used, same as in `useQuery`.

| Member | Meaning |
|---|---|
| `watch({queryKey, queryFn, ...})` | Same options as `useQuery`; the returned `QueryResult` is tracked by this scope. |
| `prefetchQuery({queryKey, queryFn})` | Warms the cache without holding a result. |
| `invalidateQueries({queryKey, exact, refetchType})` | Same as `QueryClient.invalidateQueries`, using this scope's client. |
| `getQueryData<T>(queryKey)` | Read the cache directly. |
| `setQueryData<T>(queryKey, updater)` | Write the cache directly. |
| `mutate(fn, {invalidates})` | Runs `fn`, then invalidates each key in `invalidates`. |
| `dispose()` | Disposes every `watch()` result tracked by this scope, then clears the tracking list. |

**Plain `StatefulWidget`, no ViewModel.** The scope lives on the `State` and is disposed with it:

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

**In a test** (no GetX registration needed):

```dart
final scope = QueryScope(client: freshTestClient());
final result = scope.watch(queryKey: ['x'], queryFn: (_) async => 'value');
await pump();
expect(result.data, 'value');
scope.dispose();
```

### BaseViewModel & GetBaseViewModel

Both mix in the full `QueryClient` API and track every subscription (`useQuery`, `useMutation`, `useInfiniteQuery`) for automatic cleanup.

- **`GetBaseViewModel`**: extends `GetxController` and hooks into `onInit`/`onClose` for you. It uses the client from `QueryService` unless you pass one.
- **`BaseViewModel`**: not tied to any framework. Pass a `QueryClient` to the constructor and call `init()` / `dispose()` yourself (both are `@mustCallSuper`).

When the app returns to the foreground, every `useQuery`/`useInfiniteQuery` follows its own `refetchOnResume` policy (`stale` / `always` / `never`), whether it was called standalone, through `QueryScope` or on a ViewModel. This is the same as calling flutter_query's hooks directly. Nothing is invalidated client-wide on resume.

| Member | Meaning |
|---|---|
| `useQuery({queryKey, queryFn, ...})` | Same options/return as top-level `useQuery`. |
| `useMutation(mutationFn, {...})` | Same options/return as top-level `useMutation`. |
| `useInfiniteQuery({queryKey, queryFn, ...})` | Same options/return as top-level `useInfiniteQuery`. |
| `fetchQuery({queryKey, queryFn, ...})` | Fetch once, `await` the raw result, and populate the cache. |
| `prefetchQuery({queryKey, queryFn, ...})` | Same, but discards the result; it only warms the cache. |
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
| `mutate(fn, {invalidates})` | Runs `fn`, then invalidates the keys in `invalidates`. For reactive loading/error state, use `useMutation` instead. |
| `clear()` | Clears the whole `QueryClient` cache. |

### QueryService

A `GetxService` that holds a `QueryClient` and listens to `connectivity_plus` to refetch on reconnect. `useQueryClient()` returns it. Only one `QueryService` is ever registered: `useQueryClient()` and `GetBaseViewModel`'s default lookup always return *that* instance's `client`, whatever options it was created with. There is no hidden "default" client behind it.

Every default is a named constructor parameter that you can override on its own. Your values are merged field by field with getx_query's defaults, so you only set what you want to change:

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

> **Important.** getx_query uses flutter_query's **private internals**. It imports `package:flutter_query/src/core/query_observer.dart` and `.../mutation_observer.dart` and uses `@internal` members. That is how it can drive queries outside a `HookWidget`.
>
> Consequences:
> - It depends on `flutter_query` `^0.10.0`; a minor release that moves those `src/` files can break it.
> - `dart pub publish` gives an `implementation_imports` warning. Unless flutter_query makes `QueryObserver`/`MutationObserver` public, it is easier to publish privately (a git dependency or a private pub server).
>
> If the pub.dev warning blocks you, use it as a git or path dependency:
> ```yaml
> dependencies:
>   getx_query:
>     git:
>       url: https://github.com/icodejoo/dart-labs.git
>       path: getx-query
> ```

## License

MIT
