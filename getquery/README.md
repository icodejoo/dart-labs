# getquery

[![pub](https://img.shields.io/pub/v/getquery.svg)](https://pub.dev/packages/getquery)

> 中文文档：[README.zh-CN.md](./README.zh-CN.md)

**TanStack-Query-style data fetching for GetX.** A thin, `Rx`-backed bridge over [`flutter_query`](https://pub.dev/packages/flutter_query): call `useQuery` / `useMutation` from **any** function — no `HookWidget`, no `BuildContext` — and render with `Obx`.

> Key insight: `flutter_query` is built around Flutter Hooks (`useQuery` only works inside a `HookWidget`'s `build`). getquery keeps flutter_query's caching/dedup/retry engine but swaps the Hook surface for GetX `Rx`, so a query is just a value you hold and observe with `Obx` — from a controller, a service, or a plain function.

- [Features](#features)
- [Install](#install)
- [Setup](#setup)
- [Quick start](#quick-start)
- [API](#api)
  - [useQuery](#usequery)
  - [Reactive parameters](#reactive-parameters)
  - [useMutation](#usemutation)
  - [QueryResult / MutationResult](#queryresult--mutationresult)
  - [watchQuery & QueryScope](#watchquery--queryscope)
  - [BaseViewModel & GetBaseViewModel](#baseviewmodel--getbaseviewmodel)
  - [QueryService](#queryservice)
- [Publishing caveat](#publishing-caveat)
- [License](#license)

## Features

- **Hook-free `useQuery` / `useMutation`** — call from any function; the result is an `Rx`-backed object you render with `Obx`.
- **Reactive parameters** — put `Rx` values in `queryKey` or `enabled`; the query re-fetches automatically when they change.
- **Auto-disposing view models** — `GetBaseViewModel` (a `GetxController`) and `BaseViewModel` track every subscription and dispose them on close.
- **Grouped lifecycle** — `QueryScope` collects several queries and disposes them together (great for a `StatefulWidget`); `watchQuery` returns a `(result, dispose)` record.
- **Full `QueryClient` surface** — `invalidate/refetch/cancel/reset/removeQueries`, `fetch/prefetch/ensureQueryData`, `get/setQueryData`, `isFetching/isMutating`.
- **`QueryService`** — a `GetxService` `QueryClient` pre-wired to `connectivity_plus` so `refetchOnReconnect` works out of the box.
- **Single import** — the barrel re-exports flutter_query's public types (`QueryClient`, `StaleDuration`, `RetryResolver`, ...).

## Install

```yaml
dependencies:
  getquery: ^0.1.0
```

```dart
import 'package:getquery/getquery.dart';
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
    ['todos', filter],                    // Rx in key → auto-refetch on change
    (_) => api.getTodos(filter.value),
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

A complete runnable app is in [`example/getquery_example.dart`](./example/getquery_example.dart).

## API

### useQuery

```dart
QueryResult<T> useQuery<T>(
  List<Object?> queryKey,
  QueryFn<T> queryFn, {
  QueryClient? client,
  Object? enabled,            // bool? | RxBool | Rx<bool>
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

Same options as flutter_query's `useQuery`. Without `client` it resolves the global one from `QueryService`. **Remember to `dispose()`** the result (or use a view model / `QueryScope` that does it for you).

`useQueries(List<QueryOptions>)` subscribes to many at once and returns `(results, disposeAll)`.

### Reactive parameters

Pass `Rx` values directly — the query rewires when they change, mirroring how flutter_query re-runs on every `HookWidget` build:

```dart
final userId  = 'u1'.obs;
final loggedIn = false.obs;

final profile = useQuery(
  ['user', userId],          // RxString in key
  (_) => api.getUser(userId.value),
  enabled: loggedIn,         // RxBool gates the fetch
);

userId.value = 'u2';         // → refetch
loggedIn.value = true;       // → starts fetching
```

### useMutation

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

Triggered imperatively via `mutate(vars)` (fire-and-forget) or `await mutateAsync(vars)` (throws on failure); `reset()` returns to idle.

### QueryResult / MutationResult

`Rx`-backed wrappers you observe with `Obx`.

| `QueryResult<T>` | |
|---|---|
| `data` | `T?` (falls back to `placeholder`) |
| `isIdle` / `isLoading` / `isFetching` | status flags |
| `isSuccess` / `isError` / `isStale` | status flags |
| `error` / `updatedAt` | error + last-updated |
| `refetch()` / `dispose()` | actions |

| `MutationResult<TData, TVariables>` | |
|---|---|
| `data` / `error` / `variables` / `failureCount` | |
| `isIdle` / `isPending` / `isSuccess` / `isError` / `isPaused` | |
| `mutate(vars)` / `mutateAsync(vars)` / `reset()` / `dispose()` | |

### watchQuery & QueryScope

```dart
// record form — explicit client:
final (items, cancel) = watchQuery(client, ['shop', 'items'], (_) => api.items());
Obx(() => ItemList(items: items.data ?? []));
cancel();

// grouped lifecycle — dispose all at once (e.g. in State.dispose):
final scope = QueryScope();
final a = scope.watch(['a'], (_) => api.a());
final b = scope.watch(['b'], (_) => api.b());
scope.dispose();
```

`QueryScope` also exposes `invalidateQueries` / `prefetchQuery` / `get/setQueryData` and a `mutate(fn, invalidates: [...])` helper.

### BaseViewModel & GetBaseViewModel

Both mix in the full `QueryClient` API (`useQuery`, `useMutation`, `invalidateQueries`, `fetchQuery`, `setQueryData`, `isFetching`, `mutate`, ...) and track every subscription for automatic cleanup.

- **`GetBaseViewModel`** — extends `GetxController`; wires `onInit`/`onClose` automatically. Resolves the client from `QueryService` unless you pass one.
- **`BaseViewModel`** — framework-agnostic; constructor-inject a `QueryClient`, call `init()` / `dispose()` yourself.

Both also invalidate all queries on `AppLifecycleState.resumed`.

### QueryService

A `GetxService` holding a `QueryClient` configured with sensible defaults (5-min stale, 10-min GC, 3 retries with back-off) and subscribed to `connectivity_plus` for reconnect-driven refetch. `useQueryClient()` returns it.

## Publishing caveat

> **Important.** getquery reaches into flutter_query's **private internals** — it imports `package:flutter_query/src/core/query_observer.dart` and `.../mutation_observer.dart` and uses `@internal` members. That's what lets it drive queries outside a `HookWidget`.
>
> Consequences:
> - It is pinned to a compatible `flutter_query` version (`^0.10.0`); a minor bump that reshuffles those `src/` files can break it.
> - `dart pub publish` will emit an `implementation_imports` warning. Publishing privately (a git dependency or a private pub server) is the smoother path unless/until flutter_query exposes `QueryObserver`/`MutationObserver` publicly.
>
> Use it as a git/path dependency if pub.dev's warning is a blocker:
> ```yaml
> dependencies:
>   getquery:
>     git: https://github.com/icodejoo/getquery
> ```

## License

MIT
