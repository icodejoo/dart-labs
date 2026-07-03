# getquery

> English: [README.md](./README.md)

[![pub](https://img.shields.io/pub/v/getquery.svg)](https://pub.dev/packages/getquery)

**为 GetX 打造的 TanStack-Query 式数据请求。** 对 [`flutter_query`](https://pub.dev/packages/flutter_query) 的一层薄薄的、`Rx` 驱动的封装：在**任意**函数里调用 `useQuery` / `useMutation`——不需要 `HookWidget`、不需要 `BuildContext`——用 `Obx` 渲染即可。

> 关键认知：`flutter_query` 基于 Flutter Hooks（`useQuery` 只能在 `HookWidget` 的 `build` 里用）。getquery 保留了 flutter_query 的缓存/去重/重试引擎，只把 Hook 外壳换成 GetX 的 `Rx`——于是一个查询就是一个你持有、并用 `Obx` 观察的值，无论在 controller、service 还是普通函数里。

- [特性](#特性)
- [安装](#安装)
- [初始化](#初始化)
- [快速上手](#快速上手)
- [API](#api)
  - [useQuery](#usequery)
  - [响应式参数](#响应式参数)
  - [useMutation](#usemutation)
  - [QueryResult / MutationResult](#queryresult--mutationresult)
  - [watchQuery 与 QueryScope](#watchquery-与-queryscope)
  - [BaseViewModel 与 GetBaseViewModel](#baseviewmodel-与-getbaseviewmodel)
  - [QueryService](#queryservice)
- [发布注意事项](#发布注意事项)
- [License](#license)

## 特性

- **免 Hook 的 `useQuery` / `useMutation`**：任意函数里调用，返回一个 `Rx` 驱动的对象，用 `Obx` 渲染。
- **响应式参数**：把 `Rx` 放进 `queryKey` 或 `enabled`，值变化时自动重新请求。
- **自动释放的 ViewModel**：`GetBaseViewModel`（`GetxController`）与 `BaseViewModel` 会追踪每个订阅并在关闭时释放。
- **成组生命周期**：`QueryScope` 收集多个查询一起释放（适合 `StatefulWidget`）；`watchQuery` 返回 `(result, dispose)` record。
- **完整的 `QueryClient` 能力**：`invalidate/refetch/cancel/reset/removeQueries`、`fetch/prefetch/ensureQueryData`、`get/setQueryData`、`isFetching/isMutating`。
- **`QueryService`**：一个 `GetxService` 版 `QueryClient`，已接好 `connectivity_plus`，开箱即用 `refetchOnReconnect`。
- **单一导入**：barrel 会转发 flutter_query 的公开类型（`QueryClient`、`StaleDuration`、`RetryResolver`……）。

## 安装

```yaml
dependencies:
  getquery: ^0.1.0
```

```dart
import 'package:getquery/getquery.dart';
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
    ['todos', filter],                    // key 里放 Rx → 变化即自动重取
    (_) => api.getTodos(filter.value),
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

完整可运行示例见 [`example/getquery_example.dart`](./example/getquery_example.dart)。

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

参数与 flutter_query 的 `useQuery` 一致。不传 `client` 时从 `QueryService` 解析全局实例。**记得 `dispose()`** 结果（或交给会自动释放的 ViewModel / `QueryScope`）。

`useQueries(List<QueryOptions>)` 一次订阅多个，返回 `(results, disposeAll)`。

### 响应式参数

直接传 `Rx`——值变化时查询自动重连，等价于 flutter_query 在每次 `HookWidget` build 时重跑：

```dart
final userId  = 'u1'.obs;
final loggedIn = false.obs;

final profile = useQuery(
  ['user', userId],          // key 里的 RxString
  (_) => api.getUser(userId.value),
  enabled: loggedIn,         // RxBool 控制是否请求
);

userId.value = 'u2';         // → 重取
loggedIn.value = true;       // → 开始请求
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

命令式触发：`mutate(vars)`（发后不管）或 `await mutateAsync(vars)`（失败抛出）；`reset()` 回到 idle。

### QueryResult / MutationResult

用 `Obx` 观察的 `Rx` 封装对象。

| `QueryResult<T>` | |
|---|---|
| `data` | `T?`（无值时回退 `placeholder`） |
| `isIdle` / `isLoading` / `isFetching` | 状态标志 |
| `isSuccess` / `isError` / `isStale` | 状态标志 |
| `error` / `updatedAt` | 错误 + 最后更新时间 |
| `refetch()` / `dispose()` | 动作 |

| `MutationResult<TData, TVariables>` | |
|---|---|
| `data` / `error` / `variables` / `failureCount` | |
| `isIdle` / `isPending` / `isSuccess` / `isError` / `isPaused` | |
| `mutate(vars)` / `mutateAsync(vars)` / `reset()` / `dispose()` | |

### watchQuery 与 QueryScope

```dart
// record 形式——显式 client：
final (items, cancel) = watchQuery(client, ['shop', 'items'], (_) => api.items());
Obx(() => ItemList(items: items.data ?? []));
cancel();

// 成组生命周期——一次性释放（如在 State.dispose 里）：
final scope = QueryScope();
final a = scope.watch(['a'], (_) => api.a());
final b = scope.watch(['b'], (_) => api.b());
scope.dispose();
```

`QueryScope` 还提供 `invalidateQueries` / `prefetchQuery` / `get/setQueryData` 以及 `mutate(fn, invalidates: [...])` 辅助方法。

### BaseViewModel 与 GetBaseViewModel

两者都混入了完整的 `QueryClient` API（`useQuery`、`useMutation`、`invalidateQueries`、`fetchQuery`、`setQueryData`、`isFetching`、`mutate`……），并追踪每个订阅以自动清理。

- **`GetBaseViewModel`**：继承 `GetxController`，自动接好 `onInit`/`onClose`；不传 client 时从 `QueryService` 解析。
- **`BaseViewModel`**：与框架无关；构造时注入 `QueryClient`，自行调用 `init()` / `dispose()`。

两者都会在 `AppLifecycleState.resumed`（回前台）时失效所有查询。

### QueryService

一个 `GetxService`，持有配置了合理默认值（5 分钟 stale、10 分钟 GC、3 次退避重试）的 `QueryClient`，并订阅 `connectivity_plus` 以实现重连自动重取。`useQueryClient()` 返回它。

## 发布注意事项

> **重要。** getquery 触及了 flutter_query 的**私有内部**——它 import 了 `package:flutter_query/src/core/query_observer.dart` 与 `.../mutation_observer.dart`，并使用了 `@internal` 成员。正是这一点让它能在 `HookWidget` 之外驱动查询。
>
> 带来的后果：
> - 它锁定在兼容的 `flutter_query` 版本（`^0.10.0`）；一次挪动这些 `src/` 文件的小版本升级就可能让它失效。
> - `dart pub publish` 会给出 `implementation_imports` 警告。除非/直到 flutter_query 把 `QueryObserver`/`MutationObserver` 公开，否则用**私有方式发布**（git 依赖或私有 pub 服务器）更顺畅。
>
> 若 pub.dev 的警告成为阻碍，用 git/path 依赖即可：
> ```yaml
> dependencies:
>   getquery:
>     git: https://github.com/icodejoo/getquery
> ```

## License

MIT
