# GetX Query 架构文档

## 项目概述

**getx_query** 是一个 TanStack Query（React Query）风格的数据获取库，针对 GetX 框架优化。提供 useQuery/useMutation Hook 风格的 API，基于 flutter_query，与 GetX 的 Rx 响应式系统深度集成，无需 HookWidget，用 Obx 渲染。

## 核心架构

```
Flutter Widget
    ↓
[GetX Query Hook]
    ├─ useQuery (GET 请求)
    └─ useMutation (POST/PUT/DEL)
    ↓
[Query 缓存管理]
    └─ flutter_query 缓存层
    ↓
[Rx 响应式系统]
    ├─ Query State 转 RxValue
    ├─ Mutation State 转 RxValue
    └─ 自动状态更新
    ↓
[网络请求]
    ├─ 获取数据 (Fetch)
    ├─ 修改数据 (Mutate)
    └─ 错误处理
    ↓
[缓存策略]
    ├─ 缓存击中
    ├─ 缓存失效
    └─ 后台重验证
    ↓
[Widget 重建]
    ├─ Obx 监听 RxValue
    ├─ 状态变化触发重建
    └─ 自动 GetBuilder
    ↓
UI 显示
```

## 主要特性

### 1. **useQuery - 数据获取**
```dart
// 基础用法
final userQuery = useQuery(
  key: 'user-1',
  queryFn: () => api.getUser(1)
);

// 在 Widget 中使用
Obx(() => Text(userQuery.state.value?.name ?? 'Loading...'));
```

### 2. **useMutation - 数据修改**
```dart
final updateUserMutation = useMutation(
  mutationFn: (User user) => api.updateUser(user)
);

// 执行修改
await updateUserMutation.mutate(newUser);

// 监听状态
Obx(() {
  if (updateUserMutation.isPending.value) {
    return CircularProgressIndicator();
  }
  return Text('Updated!');
});
```

### 3. **自动缓存管理**
```dart
final query = useQuery(
  key: 'posts',
  queryFn: () => api.getPosts(),
  // 1 小时内缓存有效
  staleTime: Duration(hours: 1),
  // 5 分钟后触发后台重验证
  gcTime: Duration(minutes: 5)
);

// 缓存击中时立即返回，后台自动更新
```

### 4. **Query Invalidation**
```dart
// 在修改成功后，自动失效相关查询
final updateMutation = useMutation(
  mutationFn: (user) => api.updateUser(user),
  onSuccess: (data) {
    // 失效 'user' key 的所有查询
    QueryClient.instance.invalidateQueries(['user']);
  }
);
```

### 5. **状态管理**
```dart
final query = useQuery(
  key: 'data',
  queryFn: () => api.getData()
);

// 状态访问
query.isLoading     // RxBool 初始加载中
query.isFetching    // RxBool 后台获取中
query.isError       // RxBool 出错
query.isSuccess     // RxBool 成功
query.data          // RxValue<T?> 数据
query.error         // RxValue<Object?> 错误
```

### 6. **页面状态**
```dart
final query = useQuery(
  key: 'posts',
  queryFn: () => api.getPosts()
);

Obx(() {
  if (query.isLoading.value && query.data.value == null) {
    return LoadingWidget();
  }
  if (query.isError.value) {
    return ErrorWidget(error: query.error.value);
  }
  return ListView(children: query.data.value!);
});
```

### 7. **后台重验证**
```dart
final query = useQuery(
  key: 'user',
  queryFn: () => api.getUser(),
  staleTime: Duration(minutes: 5)
);

// 5 分钟内：直接返回缓存
// 5 分钟后：返回缓存，后台自动获取更新
// Widget 自动更新（通过 Rx）
```

## 文件结构

```
lib/
├── src/
│   ├── getx_query.dart         # 主入口
│   ├── hooks/
│   │   ├─ use_query.dart       # useQuery Hook
│   │   ├─ use_mutation.dart    # useMutation Hook
│   │   ├─ use_infinite_query.dart
│   │   └─ use_queries.dart
│   ├── cache/
│   │   ├─ query_cache.dart     # Query 缓存
│   │   ├─ cache_manager.dart   # 缓存管理器
│   │   └─ invalidation.dart    # 失效管理
│   ├── state/
│   │   ├─ query_state.dart     # Query 状态
│   │   ├─ mutation_state.dart  # Mutation 状态
│   │   └─ rx_wrapper.dart      # Rx 包装器
│   ├── network/
│   │   ├─ query_client.dart    # Query 客户端
│   │   └─ http_provider.dart   # HTTP 提供器
│   ├── connectivity/
│   │   └─ connectivity_manager.dart # 网络检测
│   ├── types.dart              # 类型定义
│   └─ constants.dart           # 常量
└── getx_query.dart             # 库导出
```

## 核心流程

### 初始化

```dart
// 在 main.dart 或初始化处
void main() {
  GetXQuery.init();
  runApp(MyApp());
}

// 或显式创建 QueryClient
final queryClient = QueryClient();
```

### useQuery 流程

```
用户调用 useQuery(key: 'data', queryFn: fetch)
    ↓
[Hook 创建]
    ├─ 生成唯一查询键
    ├─ 创建 RxValue<T> 状态
    └─ 注册到 QueryClient
    ↓
[首次加载]
    ├─ 检查缓存中是否存在
    ├─ 缓存未命中 → isLoading = true
    └─ 调用 queryFn 获取数据
    ↓
[数据获取]
    ├─ 执行异步 queryFn
    ├─ 网络请求获取数据
    └─ 等待结果返回
    ↓
[成功]
    ├─ data.value = 获取的数据
    ├─ isSuccess = true
    ├─ isLoading = false
    ├─ 存储到缓存
    └─ 触发 Rx 更新
    ↓
[失败]
    ├─ error.value = 异常对象
    ├─ isError = true
    ├─ isLoading = false
    └─ 触发 Rx 更新
    ↓
[缓存管理]
    ├─ 记录加载时间
    ├─ 计算 stale 时间
    └─ 启动 gc 定时器
    ↓
[返回给应用]
    └─ 返回 useQuery 对象 (包含所有 RxValue)
    ↓
[Obx 监听]
    ├─ 用户用 Obx 包装 Widget
    ├─ 读取 RxValue (如 data.value)
    └─ 变化时自动重建 Widget
```

### useMutation 流程

```
用户调用 mutation.mutate(payload)
    ↓
[Mutation 初始化]
    ├─ isPending = true
    ├─ isError = false
    └─ isSuccess = false
    ↓
[执行 mutationFn]
    ├─ 调用用户提供的修改函数
    ├─ mutationFn(payload) 执行
    └─ 等待结果
    ↓
[成功]
    ├─ data.value = 返回值
    ├─ isSuccess = true
    ├─ isPending = false
    ├─ 调用 onSuccess 回调
    └─ 触发 Rx 更新
    ↓
[失败]
    ├─ error.value = 异常
    ├─ isError = true
    ├─ isPending = false
    ├─ 调用 onError 回调
    └─ 触发 Rx 更新
    ↓
[Query 失效]
    ├─ 在 onSuccess 中失效相关查询
    ├─ QueryClient.invalidateQueries(['key'])
    └─ 相关查询后台重新获取
    ↓
[Widget 重建]
    ├─ Obx 监听状态变化
    ├─ 显示加载/成功/失败 UI
    └─ 用户看到反馈
```

### 缓存策略

```dart
// 场景：用户列表缓存

final usersQuery = useQuery(
  key: 'users',
  queryFn: () => api.getUsers(),
  staleTime: Duration(minutes: 5),    // 5 分钟内认为新鲜
  gcTime: Duration(hours: 1)           // 1 小时后从缓存删除
);

// 时间轴：
// 0:00 - 获取用户列表 → 缓存
// 0:01 - 再次 useQuery → 返回缓存 (isStale=false)
// 0:06 - 再次 useQuery → 返回缓存 (isStale=true) + 后台更新
// 1:00 - 缓存过期，删除
```

### 离线支持

```dart
// ConnectivityManager 检测网络状态
final isOnline = connectivityManager.isOnline.value;

final query = useQuery(
  key: 'data',
  queryFn: () => api.getData(),
  enabled: isOnline  // 有网才执行
);

// 网络恢复时自动重新执行查询
connectivityManager.onConnectivityChanged.listen((isOnline) {
  if (isOnline) {
    query.refetch();
  }
});
```

## 与其他项目的关系

- **flutter_query**: 底层缓存库
- **GetX**: 状态管理和响应式基础
- **其他 Dart-Labs 子包**: 可作为数据获取层

## 使用示例

```dart
class UserPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // 创建 Query Hook
    final userQuery = useQuery(
      key: 'user-profile',
      queryFn: () => api.getUser()
    );

    final updateMutation = useMutation(
      mutationFn: (User u) => api.updateUser(u),
      onSuccess: (_) {
        // 更新成功后失效查询，自动重新加载
        QueryClient.instance.invalidateQueries(['user-profile']);
      }
    );

    return Scaffold(
      body: Obx(() {
        // 加载中
        if (userQuery.isLoading.value) {
          return Center(child: CircularProgressIndicator());
        }
        
        // 出错
        if (userQuery.isError.value) {
          return Center(
            child: Text('Error: ${userQuery.error.value}')
          );
        }

        // 成功
        final user = userQuery.data.value!;
        return Column(
          children: [
            Text(user.name),
            ElevatedButton(
              onPressed: () => updateMutation.mutate(
                user.copyWith(name: 'Updated')
              ),
              child: Text(
                updateMutation.isPending.value 
                  ? 'Saving...' 
                  : 'Update'
              )
            )
          ]
        );
      })
    );
  }
}
```

## 参考

- [README.md](./README.md)
- [源代码](./lib)
- flutter_query: https://pub.dev/packages/flutter_query
- GetX: https://pub.dev/packages/get
