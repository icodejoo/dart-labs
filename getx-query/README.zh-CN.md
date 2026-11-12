# getx_query

> English: [README.md](./README.md)

[![pub](https://img.shields.io/pub/v/getx_query.svg)](https://pub.dev/packages/getx_query)

**给 GetX 用的 TanStack-Query 风格数据请求。** 在 [`flutter_query`](https://pub.dev/packages/flutter_query) 上包了很薄的一层，把查询变成 `Rx` 值。在**任意**函数里都能调用 `useQuery` / `useMutation`（不需要 `HookWidget`，也不需要 `BuildContext`），用 `Obx` 渲染就行。

> 原理：`flutter_query` 基于 Flutter Hooks，它的 `useQuery` 只能在 `HookWidget` 的 `build` 里用。getx_query 保留了 flutter_query 的缓存、请求去重和重试逻辑，只是把 Hook 的接口换成了 GetX 的 `Rx`。这样一个查询就是一个你自己持有、用 `Obx` 观察的值，不管你在 controller、service 还是普通函数里。

- [特性](#特性)
- [安装](#安装)
- [初始化](#初始化)
- [快速上手](#快速上手)
- [API](#api)
  - [useQuery](#usequery)
  - [响应式参数](#响应式参数)
  - [useMutation](#usemutation)
  - [QueryResult](#queryresult)
  - [MutationResult](#mutationresult)
  - [useInfiniteQuery](#useinfinitequery)
  - [InfiniteQueryResult](#infinitequeryresult)
  - [useQueries](#usequeries)
  - [useIsFetching / useIsMutating](#useisfetching--useismutating)
  - [QueryScope](#queryscope)
  - [BaseViewModel 与 GetBaseViewModel](#baseviewmodel-与-getbaseviewmodel)
  - [QueryService](#queryservice)
- [发布注意事项](#发布注意事项)
- [License](#license)

## 特性

- **不用 Hook 的 `useQuery` / `useMutation`**：在任意函数里调用，返回一个基于 `Rx` 的对象，用 `Obx` 渲染。
- **`useInfiniteQuery`**：分页数据，自动把各页累积起来，提供 `fetchNextPage`/`fetchPreviousPage` 和 `hasNextPage`/`hasPreviousPage`。用法和 `useQuery` 一样：不用 Hook，支持响应式参数。
- **带 `combine` 的 `useQueries`**：并行跑一组查询（数量可以变），再从所有结果算出一个值。在 `Obx` 里读 `combined()`，只有它读到的字段变化才会重建，不需要 React 那套 memoization。
- **响应式参数**：把响应式值（`RxBool`、`RxString`、`RxList`、`RxMap`、`RxSet`、`Rx<T>`……）放进 `queryKey` 或 `enabled`，值一变就自动重新请求。
- **自动释放订阅的 ViewModel**：`GetBaseViewModel`（一个 `GetxController`）和 `BaseViewModel` 会记录每个订阅，关闭时统一释放。
- **成组管理生命周期**：`QueryScope` 把多个查询放在一起，一起释放。适合用不着完整 ViewModel 的场景（普通 `StatefulWidget`、弹窗、测试）。
- **`QueryClient` 的方法都有**：`invalidate/refetch/cancel/reset/removeQueries`、`fetch/prefetch/ensureQueryData`、`get/setQueryData`、`isFetching/isMutating`。
- **`QueryService`**：一个持有 `QueryClient` 的 `GetxService`，已经接好 `connectivity_plus`，`refetchOnReconnect` 不用额外配置就能用；每个默认值都可以单独覆盖。
- **`dispose()` 之后调用也安全**：`refetch()`、`mutate()`、`reset()` 变成空操作，`mutateAsync()` 会以 `StateError` reject。
- **只需一个 import**：`getx_query.dart` 会转出 flutter_query 的公开类型（`QueryClient`、`StaleDuration`、`RetryResolver`……）。

## 安装

```yaml
dependencies:
  getx_query: ^0.1.0
```

```dart
import 'package:getx_query/getx_query.dart';
```

## 初始化

全局注册一次共享的 client（网络连通性也会一并接好）：

```dart
GetMaterialApp(
  initialBinding: BindingsBuilder(() {
    Get.put<QueryService>(QueryService(), permanent: true);
  }),
  home: const HomePage(),
);
```

## 快速上手

```dart
class TodoViewModel extends GetBaseViewModel {
  final filter = 'all'.obs;

  late final todos = useQuery(
    queryKey: ['todos', filter],          // key 里放 Rx，值变了就自动重新请求
    queryFn: (_) => api.getTodos(filter.value),
    staleDuration: StaleDuration(minutes: 5),
    placeholder: const [],
  );

  late final addTodo = useMutation<Todo, TodoInput>(
    (input, _) => api.addTodo(input),
    onSuccess: (_, __, ___, ____) => invalidateQueries(queryKey: ['todos']),
  );
}

// UI：直接用 Obx，不用写 controller 样板代码
final vm = Get.put(TodoViewModel());

Obx(() => vm.todos.isLoading
    ? const CircularProgressIndicator()
    : TodoList(items: vm.todos.data ?? []));
```

完整可运行示例见 [`example/getx_query_example.dart`](./example/getx_query_example.dart)。

## API

### useQuery

在任意函数里订阅一个缓存查询，不需要 ViewModel，也不需要 Widget。不传 `client` 时，用 `QueryService` 里的全局实例。**用完要 `dispose()`** 结果，也可以交给会自动释放的 ViewModel 或 `QueryScope`。

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

| 参数 | 含义 |
|---|---|
| `queryKey`（必填） | 缓存 key。里面的响应式项变化时会重新请求（见下）。 |
| `queryFn`（必填） | 取数函数；接收 `QueryFunctionContext`（`queryKey`/`client`/`signal`/`meta`）。 |
| `client` | 使用哪个 `QueryClient`，不传则用 `QueryService` 的全局实例。 |
| `enabled` | `bool?` \| `RxBool` \| `Rx<bool>`。控制是否请求；响应式值变化时会重新触发。 |
| `placeholder` | 请求中且无缓存时展示，不写入缓存。 |
| `seed` | 首次真实请求前的初始数据，会写入缓存。 |
| `seedUpdatedAt` | `seed` 的时间戳，用于计算是否过期。 |
| `staleDuration` | 数据保持新鲜（不过期）多久。 |
| `gcDuration` | 无人订阅的缓存条目多久后被回收。 |
| `retry` | `(失败次数, 错误) => Duration?`。返回重试前的等待时长，返回 `null` 就不再重试。 |
| `refetchInterval` | 挂载期间的轮询间隔，`null` 关闭轮询。 |
| `refetchOnMount` | 挂载时的重新请求策略：`stale`/`always`/`never`。 |
| `refetchOnResume` | 同上，针对 App 回前台。 |
| `refetchOnReconnect` | 同上，针对网络重连（需要 client 配了 `connectivityChanges`）。 |
| `networkMode` | `online`（离线暂停）/ `always` / `offlineFirst`。 |
| `meta` | 任意元数据，`queryFn` 的 context 里能读到。 |

`useQueries(List<QueryOptions>, {combine})` 可以一次订阅多个，见 [useQueries](#usequeries)。

### 响应式参数

直接传响应式值就行，值变了，查询会自动换成新值重新请求。这和 flutter_query 在每次 `HookWidget` build 时重新执行的效果一样。单个值的 Rx 类型（`RxBool`、`RxString`、`RxInt`、`Rx<T>`……）和 GetX 的响应式集合（`RxList`、`RxMap`、`RxSet`）都支持：

```dart
final userId  = 'u1'.obs;
final loggedIn = false.obs;
final tags    = <String>['news'].obs;   // RxList

final profile = useQuery(
  queryKey: ['user', userId, tags],   // RxString + RxList 都在 key 里
  queryFn: (_) => api.getUser(userId.value, tags),
  enabled: loggedIn,                  // RxBool 控制是否请求
);

userId.value = 'u2';         // → 重取
tags.add('sports');          // → 重取（RxList 的变更也算变化）
loggedIn.value = true;       // → 开始请求
```

### useMutation

用来新增、修改或删除数据，带响应式的 `isPending`/`isSuccess`/`isError` 状态。用 `mutate(vars)`（触发后不管结果）或 `await mutateAsync(vars)`（失败时抛异常）来触发；`reset()` 回到 idle。

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

| 参数 | 含义 |
|---|---|
| `mutationFn`（必填） | `(变量, context) => Future<TData>`。执行 mutation。 |
| `client` | 不传则用 `QueryService` 全局实例。 |
| `onMutate` | 在 mutation 开始前执行；它的返回值会作为 `context` 传给其他回调（可用来做乐观更新）。 |
| `onSuccess` | `mutationFn` 成功后执行。 |
| `onError` | `mutationFn` 失败后执行。 |
| `onSettled` | 成功或失败后都会执行。 |
| `mutationKey` | 给这个 mutation 分组，供 `isMutating`/`useIsMutating` 按 key 过滤。 |
| `gcDuration` | mutation 结束后，结果在缓存里保留多久。 |
| `retry` | 跟 `useQuery` 的 `retry` 一样。 |
| `networkMode` | 跟 `useQuery` 的 `networkMode` 一样。 |
| `meta` | 任意元数据。 |

### QueryResult

基于 `Rx` 的对象，用 `Obx` 观察。`useQuery` 和 `QueryScope.watch` 返回它。

| 成员 | 含义 |
|---|---|
| `data` | `T?`。缓存或取回的值，没有值时用 `placeholder`。 |
| `isIdle` | 还没有过任何快照（首次 `onMount` 之前）。 |
| `isLoading` | 请求中且还没有数据。 |
| `isFetching` | 正在请求（包括后台重新请求）。 |
| `isSuccess` / `isError` | 上次请求结果。 |
| `isStale` | 缓存数据是否已超过 `staleDuration`。 |
| `isFetchedAfterMount` | 本次挂载后是否已完成过至少一次请求。 |
| `error` | 上次失败请求的错误，无则为 `null`。 |
| `updatedAt` | 上次成功更新数据的时间戳。 |
| `refetch()` | 手动重新请求。`dispose` 之后什么也不做。 |
| `dispose()` | 取消订阅，释放 observer。可重复调用。 |

### MutationResult

基于 `Rx` 的 mutation 状态对象，由 `useMutation` 返回。

| 成员 | 含义 |
|---|---|
| `data` | 上次成功调用 `mutationFn` 的结果。 |
| `error` | 上次失败调用的错误。 |
| `variables` | 最近一次 `mutate`/`mutateAsync` 传的 `vars`。 |
| `failureCount` | 当前这次尝试连续失败的次数。 |
| `isIdle` / `isPending` / `isSuccess` / `isError` | 状态标志。 |
| `isPaused` | 重试正在等待（比如 `NetworkMode.online` 下离线）。 |
| `mutate(vars)` | 触发后不管结果，错误放进 `error`，不抛出。`dispose` 之后什么也不做。 |
| `mutateAsync(vars)` | 可以 await，失败时抛异常。`dispose` 之后以 `StateError` reject。 |
| `reset()` | 回到 idle。`dispose` 之后什么也不做。 |
| `dispose()` | 可重复调用。 |

### useInfiniteQuery

分页数据，自动把各页累积起来。用法和 `useQuery` 一样（不用 Hook，支持响应式参数），再加上分页。在 `BaseViewModel`/`GetBaseViewModel` 里也能用 `this.useInfiniteQuery(...)`，和 `useQuery` 一样会被记录并自动释放。

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

`queryKey`、`client`、`enabled`、`networkMode`、`staleDuration`、`gcDuration`、`placeholder`、`refetchOnMount`、`refetchOnResume`、`refetchOnReconnect`、`refetchInterval`、`retry`、`seed`、`seedUpdatedAt`、`meta` 这些参数的含义和 `useQuery` 里的同名参数一样。分页专用的参数：

| 参数 | 含义 |
|---|---|
| `queryFn`（必填） | `(InfiniteQueryFunctionContext) => Future<TData>`。只取**一页**；`context.pageParam` 是这一页的参数。 |
| `initialPageParam`（必填） | 第一页请求用的参数。 |
| `nextPageParamBuilder`（必填） | `(InfiniteData data) => TPageParam?`。根据已取到的页面算出下一页的参数，返回 `null` 表示没有更多了。 |
| `prevPageParamBuilder` | 同上，用于向前分页。不传则禁用 `fetchPreviousPage`。 |
| `maxPages` | 内存里最多保留几页；超过后，丢弃与请求方向相反那一端最旧的页。 |
| `retryOnMount` | 新 observer 挂载时是否重试失败的查询。 |

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
      TextButton(onPressed: feed.fetchNextPage, child: const Text('加载更多')),
  ],
));
feed.dispose();
```

### InfiniteQueryResult

状态标志和 `QueryResult` 一样，另外多了分页状态。由 `useInfiniteQuery` 返回。

| 成员 | 含义 |
|---|---|
| `data` | `InfiniteData<TData, TPageParam>?`。所有已取到的页面和各页的参数。 |
| `pages` | `data.pages` 的简写（首次快照前为 `const []`）。 |
| `pageParams` | `data.pageParams` 的简写。 |
| `isIdle` / `isLoading` / `isFetching` / `isSuccess` / `isError` / `isStale` / `isFetchedAfterMount` | 跟 `QueryResult` 同名成员含义一致。 |
| `hasNextPage` / `hasPreviousPage` | 对最后一页，`nextPageParamBuilder`/`prevPageParamBuilder` 返回的值是否不为 null。 |
| `isFetchingNextPage` / `isFetchingPreviousPage` | 对应方向的 `fetchNextPage()`/`fetchPreviousPage()` 是否正在进行。 |
| `isFetchNextPageError` / `isFetchPreviousPageError` | 对应方向的最近一次请求是否失败。 |
| `error` / `updatedAt` | 跟 `QueryResult` 同名成员含义一致。 |
| `refetch()` | 从头重新取所有页。`dispose` 之后什么也不做。 |
| `fetchNextPage()` | 取下一页。`hasNextPage` 为 false 或已 `dispose` 时什么也不做。 |
| `fetchPreviousPage()` | 取上一页。`hasPreviousPage` 为 false 或已 `dispose` 时什么也不做。 |
| `dispose()` | 可重复调用。 |

### useQueries

并行跑一组查询，数量不限，也可以变（和 React 不同，这里没有 Hook 调用顺序的限制）。传 `combine` 可以从所有结果里算出一个值，跟 [TanStack Query 的 `useQueries({ combine })`](https://tanstack.com/query/v5/docs/framework/react/reference/useQueries) 一样。不过这里不用靠 `combine` 来避免重复渲染：在 `Obx` **里面**调用返回的 `combined()`，GetX 的依赖追踪只会在 `combine` 实际读到的字段变化时才重建。

```dart
(List<QueryResult>, TCombined Function(), VoidCallback) useQueries<TCombined>(
  List<QueryOptions> options, {
  QueryClient? client,
  TCombined Function(List<QueryResult> results)? combine,
});
```

| 参数 | 含义 |
|---|---|
| `options`（必填） | 每个查询一个 flutter_query 的 `QueryOptions(queryKey, queryFn, ...)`。 |
| `client` | 列表里所有查询共用的 client。 |
| `combine` | `(results) => TCombined`。算出一个值。没传 `combine` 却调用返回的 `combined()`，会抛 `StateError`。 |

返回 `(results, combined, disposeAll)`：

```dart
final (results, combined, disposeAll) = useQueries(
  [
    QueryOptions(['users'],    (_) => api.getUsers()),
    QueryOptions(['products'], (_) => api.getProducts()),
  ],
  combine: (rs) => rs.every((r) => r.isSuccess),
);
Obx(() => Text('全部加载完成：${combined()}'));
disposeAll();
```

### useIsFetching / useIsMutating

实时统计正在进行的查询/mutation 数量。`RxInt` 会随每个缓存事件更新，不是创建时读一次就完了。

```dart
(RxInt, VoidCallback) useIsFetching({QueryClient? client, List<Object?>? queryKey, bool exact = false});
(RxInt, VoidCallback) useIsMutating({QueryClient? client, List<Object?>? mutationKey, bool exact = false});
```

| 参数 | 含义 |
|---|---|
| `client` | 不传则用 `QueryService` 全局实例。 |
| `queryKey` / `mutationKey` | 只统计匹配这个 key 的；`null` 统计全部。 |
| `exact` | `true` 精确匹配 key；`false`（默认）按前缀匹配。 |

返回 `(count, dispose)`。不再观察时，记得调用返回的 `dispose`：

```dart
final (fetchingCount, dispose) = useIsFetching();
Obx(() => fetchingCount.value > 0
    ? const LinearProgressIndicator()
    : const SizedBox());
dispose();
```

### QueryScope

把多个 `useQuery` 的结果放成一组，一起释放。想成组管理查询的生命周期、又**不想**用完整的 `BaseViewModel`/`GetBaseViewModel` 时用它：普通 `StatefulWidget`、弹窗或 bottom sheet 的局部状态、测试，或者其他只有两三个查询、不值得搭一整套 GetX controller（`Get.put`/`Get.delete`、路由绑定）的地方。

构造函数可以传 `client`；不传就用 `QueryService` 里的全局实例，和 `useQuery` 一样。

| 成员 | 含义 |
|---|---|
| `watch({queryKey, queryFn, ...})` | 选项和 `useQuery` 一样；返回的 `QueryResult` 由这个 scope 管理。 |
| `prefetchQuery({queryKey, queryFn})` | 提前加载数据放进缓存，不持有结果。 |
| `invalidateQueries({queryKey, exact, refetchType})` | 和 `QueryClient.invalidateQueries` 一样，用这个 scope 的 client。 |
| `getQueryData<T>(queryKey)` | 直接读缓存。 |
| `setQueryData<T>(queryKey, updater)` | 直接写缓存。 |
| `mutate(fn, {invalidates})` | 执行 `fn`，然后让 `invalidates` 里的每个 key 失效。 |
| `dispose()` | 释放这个 scope 管理的所有 `watch()` 结果，并清空列表。 |

**普通 `StatefulWidget`，完全不用 ViewModel**：scope 放在 `State` 上，随 `State` 一起释放：

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
    _scope.dispose(); // 连 items 一起释放
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Obx(() => ItemList(items: items.data ?? []));
}
```

**把几个相关查询放成一组，并共用一个指定的 client：**

```dart
final scope = QueryScope(client: myClient);
final deposits = scope.watch(queryKey: ['deposit', 'list'], queryFn: (_) => api.getList());
final balance  = scope.watch(queryKey: ['wallet', 'balance'], queryFn: (_) => api.getBalance());

Obx(() => Text('${balance.data}'));
await scope.mutate(() => api.withdraw(10), invalidates: [['wallet', 'balance']]);
scope.dispose(); // deposits 和 balance 一起释放
```

**在测试里用**（完全不用注册 GetX）：

```dart
final scope = QueryScope(client: freshTestClient());
final result = scope.watch(queryKey: ['x'], queryFn: (_) async => 'value');
await pump();
expect(result.data, 'value');
scope.dispose();
```

### BaseViewModel 与 GetBaseViewModel

两者都混入了完整的 `QueryClient` API，并记录每个订阅（`useQuery`、`useMutation`、`useInfiniteQuery`），以便自动清理。

- **`GetBaseViewModel`**：继承 `GetxController`，自动在 `onInit`/`onClose` 里处理；不传 client 时用 `QueryService` 里的。
- **`BaseViewModel`**：不依赖任何框架；构造时传入 `QueryClient`，`init()` / `dispose()` 要自己调用（都标了 `@mustCallSuper`）。

App 回到前台时，每个 `useQuery`/`useInfiniteQuery` 都按自己的 `refetchOnResume` 策略（`stale`/`always`/`never`）处理，不管它是单独调用的、通过 `QueryScope` 还是在 ViewModel 上调用的，这和直接调用 flutter_query 的 hook 一致。回到前台时不会对整个 client 做批量失效。

| 成员 | 含义 |
|---|---|
| `useQuery({queryKey, queryFn, ...})` | 选项/返回值跟顶层 `useQuery` 一样。 |
| `useMutation(mutationFn, {...})` | 选项/返回值跟顶层 `useMutation` 一样。 |
| `useInfiniteQuery({queryKey, queryFn, ...})` | 选项/返回值跟顶层 `useInfiniteQuery` 一样。 |
| `fetchQuery({queryKey, queryFn, ...})` | 请求一次，`await` 得到原始结果，同时写入缓存。 |
| `prefetchQuery({queryKey, queryFn, ...})` | 同上，但丢掉结果，只是提前把数据放进缓存。 |
| `ensureQueryData({queryKey, queryFn, ...})` | 缓存还新鲜就直接返回，否则去请求。 |
| `getQueryData<T>(queryKey)` | 直接读缓存。 |
| `getQueryState<T>(queryKey)` | 读某个 key 完整的 `QueryState`（状态、时间戳等）。 |
| `setQueryData<T>(queryKey, updater, {updatedAt})` | 直接写缓存。 |
| `invalidateQueries({queryKey, exact, predicate, refetchType})` | 把匹配的查询标记为过期，默认会顺带重新请求正在使用的。 |
| `refetchQueries({queryKey, exact, predicate})` | 强制重新请求，不改过期状态。 |
| `cancelQueries({queryKey, exact, predicate, revert, silent})` | 取消匹配查询正在进行的请求。 |
| `resetQueries({queryKey, exact, predicate})` | 把匹配的查询重置回初始状态。 |
| `removeQueries({queryKey, exact, predicate})` | 把匹配的条目从缓存里彻底删掉。 |
| `isFetching({queryKey, exact, predicate})` | 匹配的查询里正在请求的数量。 |
| `isMutating({mutationKey, exact, predicate})` | 匹配的 mutation 里正在进行的数量。 |
| `mutate(fn, {invalidates})` | 执行 `fn`，再让 `invalidates` 里的 key 失效。需要响应式的 loading/error 状态时，用 `useMutation`。 |
| `clear()` | 清空整个 `QueryClient` 缓存。 |

### QueryService

一个 `GetxService`，持有 `QueryClient`，并监听 `connectivity_plus`，网络重连时自动重新请求。`useQueryClient()` 返回它。全局只会注册一个 `QueryService`：`useQueryClient()` 和 `GetBaseViewModel` 默认取到的，永远是**这一个**已注册实例的 `client`，不管它是用什么参数创建的；背后没有另一个隐藏的“默认” client。

每个默认值都是一个具名构造参数，可以单独覆盖，你传的值会逐字段和 getx_query 的默认值合并，所以只用设你想改的那几项：

| 参数 | getx_query 默认值 | 含义 |
|---|---|---|
| `enabled` | `true` | 查询默认是否自动请求。 |
| `networkMode` | `NetworkMode.online` | 默认离线行为。 |
| `staleDuration` | 5 分钟 | 默认新鲜期。 |
| `gcDuration` | 10 分钟 | 默认缓存回收延迟。 |
| `refetchInterval` | `null`（关闭） | 默认轮询间隔。 |
| `refetchOnMount` / `refetchOnResume` / `refetchOnReconnect` | `stale` | 各触发点的默认重取策略。 |
| `retry` | 3 次，指数退避（1s/2s/4s） | 默认重试策略。 |
| `retryOnMount` | `true` | 新 observer 挂载时是否重试失败的查询。 |
| `meta` | `null` | 附加到每个查询上的默认元数据。 |
| `connectivityChanges` | 接到 `connectivity_plus` | `refetchOnReconnect` 用的网络状态来源；第一次监听时必须发出当前状态。 |

```dart
Get.put<QueryService>(
  QueryService(gcDuration: GcDuration(minutes: 30)), // staleDuration/retry 仍是 getx_query 的默认值
  permanent: true,
);
```

## 发布注意事项

> **重要。** getx_query 用到了 flutter_query 的**私有内部实现**：它 import 了 `package:flutter_query/src/core/query_observer.dart` 和 `.../mutation_observer.dart`，还用了 `@internal` 成员。正因为这样，它才能在 `HookWidget` 之外驱动查询。
>
> 这意味着：
> - 它依赖 `flutter_query` `^0.10.0`；如果某个小版本调整了这些 `src/` 文件的位置，它可能就不能用了。
> - `dart pub publish` 会给出 `implementation_imports` 警告。在 flutter_query 公开 `QueryObserver`/`MutationObserver` 之前，**私有发布**（git 依赖或私有 pub 服务器）更省事。
>
> 如果 pub.dev 的警告挡了你的路，用 git 或 path 依赖就行：
> ```yaml
> dependencies:
>   getx_query:
>     git:
>       url: https://github.com/icodejoo/dart-labs.git
>       path: getx-query
> ```

## License

MIT
