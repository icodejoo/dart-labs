# getx_query

> English: [README.md](./README.md)

[![pub](https://img.shields.io/pub/v/getx_query.svg)](https://pub.dev/packages/getx_query)

**为 GetX 打造的 TanStack-Query 式数据请求。** 对 [`flutter_query`](https://pub.dev/packages/flutter_query) 的一层薄薄的、`Rx` 驱动的封装：在**任意**函数里调用 `useQuery` / `useMutation`——不需要 `HookWidget`、不需要 `BuildContext`——用 `Obx` 渲染即可。

> 关键认知：`flutter_query` 基于 Flutter Hooks（`useQuery` 只能在 `HookWidget` 的 `build` 里用）。getx_query 保留了 flutter_query 的缓存/去重/重试引擎，只把 Hook 外壳换成 GetX 的 `Rx`——于是一个查询就是一个你持有、并用 `Obx` 观察的值，无论在 controller、service 还是普通函数里。

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

- **免 Hook 的 `useQuery` / `useMutation`**：任意函数里调用，返回一个 `Rx` 驱动的对象，用 `Obx` 渲染。
- **`useInfiniteQuery`**：分页数据，自动累积页面——`fetchNextPage`/`fetchPreviousPage`、`hasNextPage`/`hasPreviousPage`，跟 `useQuery` 同一套免 Hook、响应式参数模型。
- **带 `combine` 的 `useQueries`**：并行跑一组数量可变的查询，聚合成一个派生值；在 `Obx` 里读 `combined()` 即可精确按需重建，不需要 React 那套 memoization。
- **响应式参数**：把响应式值（`RxBool`、`RxString`、`RxList`、`RxMap`、`RxSet`、`Rx<T>`……）放进 `queryKey` 或 `enabled`，值变化时自动重新请求。
- **自动释放的 ViewModel**：`GetBaseViewModel`（`GetxController`）与 `BaseViewModel` 会追踪每个订阅并在关闭时释放。
- **成组生命周期**：`QueryScope` 收集多个查询一起释放，用于不想上完整 ViewModel 的场景（纯 `StatefulWidget`、弹窗、测试）。
- **完整的 `QueryClient` 能力**：`invalidate/refetch/cancel/reset/removeQueries`、`fetch/prefetch/ensureQueryData`、`get/setQueryData`、`isFetching/isMutating`。
- **`QueryService`**：一个 `GetxService` 版 `QueryClient`，已接好 `connectivity_plus`，开箱即用 `refetchOnReconnect`；每个默认值都能单独覆盖。
- **释放后调用安全**：`dispose()` 之后再调用 `refetch()` / `mutate()` / `mutateAsync()` / `reset()` 不会抛向空处——发后不管类动作变成空操作，`mutateAsync()` 会以明确的 `StateError` reject。
- **单一导入**：barrel 会转发 flutter_query 的公开类型（`QueryClient`、`StaleDuration`、`RetryResolver`……）。

## 安装

```yaml
dependencies:
  getx_query: ^0.1.0
```

```dart
import 'package:getx_query/getx_query.dart';
```

## 初始化

全局注册一次共享 client（内部已接好连通性）：

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
    queryKey: ['todos', filter],          // key 里放 Rx → 变化即自动重取
    queryFn: (_) => api.getTodos(filter.value),
    staleDuration: StaleDuration(minutes: 5),
    placeholder: const [],
  );

  late final addTodo = useMutation<Todo, TodoInput>(
    (input, _) => api.addTodo(input),
    onSuccess: (_, __, ___, ____) => invalidateQueries(queryKey: ['todos']),
  );
}

// UI —— 没有 controller 样板，直接 Obx：
final vm = Get.put(TodoViewModel());

Obx(() => vm.todos.isLoading
    ? const CircularProgressIndicator()
    : TodoList(items: vm.todos.data ?? []));
```

完整可运行示例见 [`example/getx_query_example.dart`](./example/getx_query_example.dart)。

## API

### useQuery

从任意函数订阅一个缓存查询——不需要 ViewModel、不需要 Widget。不传 `client` 时从 `QueryService` 解析全局实例。**记得 `dispose()`** 结果（或交给会自动释放的 ViewModel / `QueryScope`）。

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
| `queryKey`（必填） | 缓存 key。里面的响应式项变化时触发重取（见下）。 |
| `queryFn`（必填） | 取数函数；接收 `QueryFunctionContext`（`queryKey`/`client`/`signal`/`meta`）。 |
| `client` | 使用哪个 `QueryClient`，不传则用 `QueryService` 的全局实例。 |
| `enabled` | `bool?` \| `RxBool` \| `Rx<bool>`——控制是否请求；响应式值变化会重新触发。 |
| `placeholder` | 请求中且无缓存时展示，不写入缓存。 |
| `seed` | 首次真实请求前的初始数据，会写入缓存。 |
| `seedUpdatedAt` | `seed` 的时间戳，用于计算是否过期。 |
| `staleDuration` | 数据保持新鲜（不过期）多久。 |
| `gcDuration` | 无人订阅的缓存条目多久后被回收。 |
| `retry` | `(失败次数, 错误) => Duration?`——重试等待时长，`null` 停止重试。 |
| `refetchInterval` | 挂载期间的轮询间隔，`null` 关闭轮询。 |
| `refetchOnMount` | 本次挂载时的重取策略：`stale`/`always`/`never`。 |
| `refetchOnResume` | 同上，针对 App 回前台。 |
| `refetchOnReconnect` | 同上，针对网络重连（需要 client 配了 `connectivityChanges`）。 |
| `networkMode` | `online`（离线暂停）/ `always` / `offlineFirst`。 |
| `meta` | 任意元数据，`queryFn` 的 context 里能读到。 |

`useQueries(List<QueryOptions>, {combine})` 一次订阅多个——见 [useQueries](#usequeries)。

### 响应式参数

直接传响应式值——变化时查询自动重连，等价于 flutter_query 在每次 `HookWidget` build 时重跑。标量 Rx 类型（`RxBool`、`RxString`、`RxInt`、`Rx<T>`……）和 GetX 的响应式集合（`RxList`、`RxMap`、`RxSet`）都能识别：

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

命令式创建/更新/删除，带响应式 `isPending`/`isSuccess`/`isError` 状态。通过 `mutate(vars)`（发后不管）或 `await mutateAsync(vars)`（失败抛出）触发；`reset()` 回到 idle。

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
| `mutationFn`（必填） | `(变量, context) => Future<TData>`——执行 mutation。 |
| `client` | 不传则用 `QueryService` 全局实例。 |
| `onMutate` | mutation 触发前执行；返回值作为其余回调的 `context`（可用于乐观更新）。 |
| `onSuccess` | `mutationFn` 成功后执行。 |
| `onError` | `mutationFn` 失败后执行。 |
| `onSettled` | 成功或失败后都会执行。 |
| `mutationKey` | 给这个 mutation 分组，供 `isMutating`/`useIsMutating` 按 key 过滤。 |
| `gcDuration` | mutation 结果 settle 后缓存保留多久。 |
| `retry` | 跟 `useQuery` 的 `retry` 一样。 |
| `networkMode` | 跟 `useQuery` 的 `networkMode` 一样。 |
| `meta` | 任意元数据。 |

### QueryResult

用 `Obx` 观察的 `Rx` 封装对象。由 `useQuery` 和 `QueryScope.watch` 返回。

| 成员 | 含义 |
|---|---|
| `data` | `T?`——缓存/取回的值，无值时回退 `placeholder`。 |
| `isIdle` | 还没有过任何快照（首次 `onMount` 之前）。 |
| `isLoading` | 请求中且还没有数据。 |
| `isFetching` | 正在请求（含后台重取）。 |
| `isSuccess` / `isError` | 上次请求结果。 |
| `isStale` | 缓存数据是否已超过 `staleDuration`。 |
| `isFetchedAfterMount` | 本次挂载后是否已完成过至少一次请求。 |
| `error` | 上次失败请求的错误，无则为 `null`。 |
| `updatedAt` | 上次成功更新数据的时间戳。 |
| `refetch()` | 手动重取。dispose 后空操作。 |
| `dispose()` | 取消订阅、释放 observer。幂等。 |

### MutationResult

`Rx` 封装的 mutation 状态。由 `useMutation` 返回。

| 成员 | 含义 |
|---|---|
| `data` | 上次成功调用 `mutationFn` 的结果。 |
| `error` | 上次失败调用的错误。 |
| `variables` | 最近一次 `mutate`/`mutateAsync` 传的 `vars`。 |
| `failureCount` | 当前这次尝试连续失败的次数。 |
| `isIdle` / `isPending` / `isSuccess` / `isError` | 状态标志。 |
| `isPaused` | 重试正在等待（比如 `NetworkMode.online` 下离线）。 |
| `mutate(vars)` | 发后不管，错误进 `error` 不抛出。dispose 后空操作。 |
| `mutateAsync(vars)` | 可 await，失败抛出。dispose 后以 `StateError` reject。 |
| `reset()` | 回到 idle。dispose 后空操作。 |
| `dispose()` | 幂等。 |

### useInfiniteQuery

分页数据，自动累积页面——跟 `useQuery` 同一套免 Hook、响应式参数模型，外加分页能力。在 `BaseViewModel`/`GetBaseViewModel` 里也能用 `this.useInfiniteQuery(...)`——跟 `useQuery` 一样被追踪并自动释放。

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

`queryKey`、`client`、`enabled`、`networkMode`、`staleDuration`、`gcDuration`、`placeholder`、`refetchOnMount`、`refetchOnResume`、`refetchOnReconnect`、`refetchInterval`、`retry`、`seed`、`seedUpdatedAt`、`meta` 跟 `useQuery` 同名参数含义一致。分页专属参数：

| 参数 | 含义 |
|---|---|
| `queryFn`（必填） | `(InfiniteQueryFunctionContext) => Future<TData>`——只取**一页**；`context.pageParam` 是这一页的参数。 |
| `initialPageParam`（必填） | 第一页请求用的参数。 |
| `nextPageParamBuilder`（必填） | `(InfiniteData data) => TPageParam?`——根据已取页面算出下一页参数，`null` 表示没有更多了。 |
| `prevPageParamBuilder` | 同上，用于向前分页。不传则禁用 `fetchPreviousPage`。 |
| `maxPages` | 内存里最多保留几页；超过后从对侧方向丢弃最旧页。 |
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

跟 `QueryResult` 一样的状态标志，外加分页状态。由 `useInfiniteQuery` 返回。

| 成员 | 含义 |
|---|---|
| `data` | `InfiniteData<TData, TPageParam>?`——所有已取页面 + 各自的参数。 |
| `pages` | `data.pages` 的简写（首次快照前为 `const []`）。 |
| `pageParams` | `data.pageParams` 的简写。 |
| `isIdle` / `isLoading` / `isFetching` / `isSuccess` / `isError` / `isStale` / `isFetchedAfterMount` | 跟 `QueryResult` 同名成员含义一致。 |
| `hasNextPage` / `hasPreviousPage` | 上一页是否让 `nextPageParamBuilder`/`prevPageParamBuilder` 返回非空。 |
| `isFetchingNextPage` / `isFetchingPreviousPage` | 对应方向的 `fetchNextPage()`/`fetchPreviousPage()` 是否正在进行。 |
| `isFetchNextPageError` / `isFetchPreviousPageError` | 对应方向的最近一次请求是否失败。 |
| `error` / `updatedAt` | 跟 `QueryResult` 同名成员含义一致。 |
| `refetch()` | 重新取所有页。dispose 后空操作。 |
| `fetchNextPage()` | 取下一页。`hasNextPage` 为 false 或已 dispose 时空操作。 |
| `fetchPreviousPage()` | 取上一页。`hasPreviousPage` 为 false 或已 dispose 时空操作。 |
| `dispose()` | 幂等。 |

### useQueries

并行跑一组任意数量的查询（跟 React 不同，Dart 这边没有 Hook 顺序限制，数量可以随便变）。传 `combine` 可以从所有结果里派生出一个值，对齐 [TanStack Query 的 `useQueries({ combine })`](https://tanstack.com/query/v5/docs/framework/react/reference/useQueries)——但这里不需要靠 `combine` 去避免重渲染：在 `Obx` **内部**调用返回的 `combined()`，GetX 的细粒度依赖追踪会只在 `combine` 实际读取的字段变化时才重建。

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
| `combine` | `(results) => TCombined`——派生出一个值。不传却调用返回的 `combined()` 会抛 `StateError`。 |

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

实时统计正在进行的查询/mutation 数量——`RxInt` 会随每个缓存事件更新，而不仅仅是创建时读一次。

```dart
(RxInt, VoidCallback) useIsFetching({QueryClient? client, List<Object?>? queryKey, bool exact = false});
(RxInt, VoidCallback) useIsMutating({QueryClient? client, List<Object?>? mutationKey, bool exact = false});
```

| 参数 | 含义 |
|---|---|
| `client` | 不传则用 `QueryService` 全局实例。 |
| `queryKey` / `mutationKey` | 只统计匹配这个 key 的；`null` 统计全部。 |
| `exact` | `true` 精确匹配 key；`false`（默认）按前缀匹配。 |

返回 `(count, dispose)`——停止观察时记得释放返回的回调：

```dart
final (fetchingCount, dispose) = useIsFetching();
Obx(() => fetchingCount.value > 0
    ? const LinearProgressIndicator()
    : const SizedBox());
dispose();
```

### QueryScope

把多个 `useQuery` 结果分组、一起释放——用于想要成组管理查询生命周期，但**不想**上完整 `BaseViewModel`/`GetBaseViewModel` 的场景：纯 `StatefulWidget`、弹窗/bottom sheet 的局部状态、测试，或者任何不想为了管两三个查询就搭一整套 GetX controller（`Get.put`/`Get.delete`、路由绑定）的地方。

构造函数可选传 `client`——不传则从 `QueryService` 解析全局实例，跟 `useQuery` 一样。

| 成员 | 含义 |
|---|---|
| `watch({queryKey, queryFn, ...})` | 选项跟 `useQuery` 一样；返回的 `QueryResult` 被这个 scope 追踪。 |
| `prefetchQuery({queryKey, queryFn})` | 预热缓存，不持有结果。 |
| `invalidateQueries({queryKey, exact, refetchType})` | 跟 `QueryClient.invalidateQueries` 一样，用这个 scope 的 client。 |
| `getQueryData<T>(queryKey)` | 直接读缓存。 |
| `setQueryData<T>(queryKey, updater)` | 直接写缓存。 |
| `mutate(fn, {invalidates})` | 跑 `fn`，然后失效 `invalidates` 里每个 key。 |
| `dispose()` | 释放这个 scope 追踪的所有 `watch()` 结果，然后清空追踪列表。 |

**纯 `StatefulWidget`，完全不用 ViewModel**——scope 挂在 `State` 上，随 `State` 一起释放：

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

**成组管理几个相关查询 + 共用一个显式 client：**

```dart
final scope = QueryScope(client: myClient);
final deposits = scope.watch(queryKey: ['deposit', 'list'], queryFn: (_) => api.getList());
final balance  = scope.watch(queryKey: ['wallet', 'balance'], queryFn: (_) => api.getBalance());

Obx(() => Text('${balance.data}'));
await scope.mutate(() => api.withdraw(10), invalidates: [['wallet', 'balance']]);
scope.dispose(); // deposits 和 balance 一起释放
```

**测试里用**——完全不用注册 GetX：

```dart
final scope = QueryScope(client: freshTestClient());
final result = scope.watch(queryKey: ['x'], queryFn: (_) async => 'value');
await pump();
expect(result.data, 'value');
scope.dispose();
```

### BaseViewModel 与 GetBaseViewModel

两者都混入了完整的 `QueryClient` API，并追踪每个订阅（`useQuery`、`useMutation`、`useInfiniteQuery`）以自动清理。

- **`GetBaseViewModel`**：继承 `GetxController`，自动接好 `onInit`/`onClose`；不传 client 时从 `QueryService` 解析。
- **`BaseViewModel`**：与框架无关；构造时注入 `QueryClient`，自行调用 `init()` / `dispose()`（都标了 `@mustCallSuper`）。

每个 `useQuery`/`useInfiniteQuery`——无论是独立调用、通过 `QueryScope`，还是挂在 ViewModel 上——在 App 回前台时都会各自遵循自己的 `refetchOnResume` 策略（`stale`/`always`/`never`），与直接调用 flutter_query 的 hook 行为一致。不存在整个 client 级别的批量失效。

| 成员 | 含义 |
|---|---|
| `useQuery({queryKey, queryFn, ...})` | 选项/返回值跟顶层 `useQuery` 一样。 |
| `useMutation(mutationFn, {...})` | 选项/返回值跟顶层 `useMutation` 一样。 |
| `useInfiniteQuery({queryKey, queryFn, ...})` | 选项/返回值跟顶层 `useInfiniteQuery` 一样。 |
| `fetchQuery({queryKey, queryFn, ...})` | 取一次、`await` 拿到原始结果，同时写入缓存。 |
| `prefetchQuery({queryKey, queryFn, ...})` | 同上但丢弃结果——只是预热缓存。 |
| `ensureQueryData({queryKey, queryFn, ...})` | 缓存新鲜就直接返回，否则去取。 |
| `getQueryData<T>(queryKey)` | 直接读缓存。 |
| `getQueryState<T>(queryKey)` | 读某个 key 完整的 `QueryState`（状态、时间戳等）。 |
| `setQueryData<T>(queryKey, updater, {updatedAt})` | 直接写缓存。 |
| `invalidateQueries({queryKey, exact, predicate, refetchType})` | 标记匹配的查询为过期，默认顺带重取活跃的。 |
| `refetchQueries({queryKey, exact, predicate})` | 强制重取，不碰过期状态。 |
| `cancelQueries({queryKey, exact, predicate, revert, silent})` | 取消匹配查询的飞行中请求。 |
| `resetQueries({queryKey, exact, predicate})` | 把匹配的查询重置回初始状态。 |
| `removeQueries({queryKey, exact, predicate})` | 把匹配条目彻底从缓存移除。 |
| `isFetching({queryKey, exact, predicate})` | 匹配的查询里正在请求的数量。 |
| `isMutating({mutationKey, exact, predicate})` | 匹配的 mutation 里正在进行的数量。 |
| `mutate(fn, {invalidates})` | 命令式的"跑完就失效"辅助方法——要响应式的 loading/error 状态用 `useMutation`。 |
| `clear()` | 清空整个 `QueryClient` 缓存。 |

### QueryService

一个 `GetxService`，持有 `QueryClient` 并订阅 `connectivity_plus` 以实现重连自动重取。`useQueryClient()` 返回它。全局只会注册一个 `QueryService`——`useQueryClient()` / `GetBaseViewModel` 默认解析拿到的永远是**那一个**已注册实例的 `client`，不管它是用什么参数构造的；不存在另一个"默认单例"藏在背后当兜底。

每个默认值都是独立可覆盖的具名构造参数，逐字段跟 getx_query 自己的默认值合并——只改你要改的，其余字段保持 getx_query 的默认值：

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
| `meta` | `null` | 每个查询的默认元数据。 |
| `connectivityChanges` | `connectivity_plus` 接线 | `refetchOnReconnect` 用的连通性来源；必须在首次监听时发出当前状态。 |

```dart
Get.put<QueryService>(
  QueryService(gcDuration: GcDuration(minutes: 30)), // staleDuration/retry 仍是 getx_query 的默认值
  permanent: true,
);
```

## 发布注意事项

> **重要。** getx_query 触及了 flutter_query 的**私有内部**——它 import 了 `package:flutter_query/src/core/query_observer.dart` 与 `.../mutation_observer.dart`，并使用了 `@internal` 成员。正是这一点让它能在 `HookWidget` 之外驱动查询。
>
> 带来的后果：
> - 它锁定在兼容的 `flutter_query` 版本（`^0.10.0`）；一次挪动这些 `src/` 文件的小版本升级就可能让它失效。
> - `dart pub publish` 会给出 `implementation_imports` 警告。除非/直到 flutter_query 把 `QueryObserver`/`MutationObserver` 公开，否则用**私有方式发布**（git 依赖或私有 pub 服务器）更顺畅。
>
> 若 pub.dev 的警告成为阻碍，用 git/path 依赖即可：
> ```yaml
> dependencies:
>   getx_query:
>     git:
>       url: https://github.com/icodejoo/dart-labs.git
>       path: getx-query
> ```

## License

MIT
