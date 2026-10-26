# Dioman 架构文档

## 项目概述

**dioman** 是一个纯 Dart、仅依赖 dio 的拦截器插件库，提供组合式、自包含的 Dio 拦截器插件系统。包括认证、缓存、重试、去重、Mock、规范化等插件，并提供正确的安装顺序指导，使开发者可以灵活组合使用。

## 核心架构

```
应用代码 (Dio 请求)
    ↓
[Dioman 拦截器管理器]
    ├─ 插件链式管理
    └─ 自动排序
    ↓
[拦截器插件]
    ├─ Auth Plugin (认证)
    ├─ Cache Plugin (缓存)
    ├─ Retry Plugin (重试)
    ├─ Dedup Plugin (去重)
    ├─ Mock Plugin (Mock)
    └─ Normalize Plugin (规范化)
    ↓
[请求拦截]
    ├─ 修改请求头/体
    ├─ 检查缓存
    └─ 拦截 Mock 请求
    ↓
[Dio HTTP 客户端]
    └─ 发送网络请求
    ↓
[响应处理]
    ├─ 缓存响应
    ├─ 重试逻辑
    └─ 数据规范化
    ↓
返回应用数据
```

## 主要特性

### 1. **认证插件 (Auth)**
```dart
final dio = Dio();
dio.interceptors.add(
  AuthInterceptor(
    getToken: () => tokenManager.getToken(),
    refreshToken: () => tokenManager.refreshToken(),
    tokenHeader: 'Authorization'
  )
);
```
- 自动注入 Token
- Token 过期自动刷新
- 无缝重试

### 2. **缓存插件 (Cache)**
```dart
dio.interceptors
  ..add(const DiomanKey())
  ..add(DiomanCache(
    persist: appCachePersist, // 实现 DiomanCachePersist
    cachePolicy: DiomanCachePolicy.both,
    expires: 60000,
    clone: DiomanClonePolicy.deep,
  ));
```
- `DiomanKey` 写入 `extra[kKey]`；默认键包含方法、origin、路径和规范化后的 query/body。
- URL query 与 queryParameters 合并；query/body 分字段编码，非结构化 body 使用对象身份。
- 内存插入与持久化回填统一执行 LRU 容量淘汰；deep 策略在入库边界隔离首次响应。
- 持久化变更串行等待，读写错误经 DioException 返回；`await cache.clear()` 和 `await cache.remove(key)` 可等待落盘完成。
- 清理代次阻止旧读取及旧响应回填；单请求 maxEntries 已弃用，容量在插件构造时设置。

### 3. **重试插件 (Retry)**
```dart
dio.interceptors.add(
  RetryInterceptor(
    maxRetries: 3,
    backoffDelay: (retryCount) => 
      Duration(milliseconds: 100 * pow(2, retryCount))
  )
);
```
- 失败自动重试
- 指数退避策略
- 可配置重试次数

### 4. **去重插件 (Dedup)**
```dart
dio.interceptors.add(
  DedupInterceptor()
);
```
- 相同请求自动去重
- 共享响应结果
- 减少网络开销

### 5. **Mock 插件**
```dart
final mock = DiomanMock(enabled: true);
mock.add('GET:/api/users', (options) async => ResponseBody.fromString(
  '[]', 200,
  headers: {Headers.contentTypeHeader: ['application/json']},
));
dio.interceptors.add(mock);
```
- 按 METHOD:path 匹配内联处理器，或转发至 mockUrl。
- 处理器和解码阶段的普通异常转换为 DioException，保证请求完成。

### 6. **规范化插件 (Normalize)**
```dart
dio.interceptors.add(const DiomanNormalize());
```
- 按配置提取响应数据，统一业务错误。
- `DiomanRepath` 默认按路径段编码占位值；重复占位符使用同一快照。
- `DiomanFilter` 和 `DiomanRepath` 修改 Map body 前复制，支持不可变 Map。
- `DiomanOffline` 使用 FIFO Queue；取消立即出队并释放定时器，flush 再检查取消。
- `DiomanBreaker` 通过窗口凭据归还取消的半开槽位，并隔离旧窗口探测结果。
- `DiomanLoading` 按显示周期固定回调，开启和关闭成对通知。

## 文件结构

```
lib/
├── dioman.dart                 # 公共导出
└── src/
    ├── dioman.dart             # 插件管理及安装
    ├── dioman_plugin.dart      # 插件基类
    ├── key_plugin.dart         # 请求键
    ├── cache_plugin.dart       # 缓存及持久化接口
    ├── offline_plugin.dart     # 离线排队
    ├── mock_plugin.dart        # Mock
    ├── breaker_plugin.dart     # 熔断
    ├── loading_plugin.dart     # 显示周期计数
    ├── repath_plugin.dart      # 路径替换
    ├── filter_plugin.dart      # 参数过滤
    ├── normalize_plugin.dart   # 响应规范化
    └── ...                    # 其余独立插件
```

## 核心流程

### 初始化

```dart
final dio = Dio(BaseOptions(
  baseUrl: 'https://api.example.com',
  connectTimeout: Duration(seconds: 10),
  receiveTimeout: Duration(seconds: 10)
));

// 正确安装顺序很重要！
// 1. Auth (最先，为其他插件提供 Token)
dio.interceptors.add(AuthInterceptor(...));

// 2. Cache (缓存检查)
dio.interceptors.add(DiomanCache(...));

// 3. Dedup (去重检查)
dio.interceptors.add(DedupInterceptor(...));

// 4. Mock (开发测试)
dio.interceptors.add(MockInterceptor(...));

// 5. Retry (最后，重试整个请求链)
dio.interceptors.add(RetryInterceptor(...));

// 6. Normalize (响应处理)
dio.interceptors.add(DiomanNormalize(...));
```

### 请求流程

```
应用调用 dio.get('/api/users')
    ↓
[Auth 拦截]
    ├─ 检查 Token 有效期
    ├─ 如需刷新则刷新
    └─ 注入 Authorization 头
    ↓
[Cache 拦截]
    ├─ 检查缓存是否存在
    ├─ 缓存未过期则返回缓存
    └─ Cache Hit → 返回给应用
    ↓
[Dedup 拦截]
    ├─ 标准化请求 Key
    ├─ 检查是否有相同请求在处理
    └─ 相同请求等待首个完成，共享结果
    ↓
[Mock 拦截]
    ├─ 检查是否在 Mock 列表
    ├─ 匹配则返回 Mock 数据
    └─ Mock Hit → 返回给应用
    ↓
[Dio 网络请求]
    ├─ 发送真实网络请求
    └─ 等待响应
    ↓
[Retry 重试]
    ├─ 请求成功 → 继续
    ├─ 请求失败 → 计算延迟
    ├─ 延迟后重试
    └─ 达到最大重试次数则放弃
    ↓
[Cache 缓存]
    ├─ 缓存成功响应
    └─ 记录时间戳
    ↓
[Normalize 规范化]
    ├─ 提取有用数据
    ├─ 转换格式
    └─ 返回给应用
    ↓
应用接收数据
```

### Auth Token 刷新流程

```
请求发送时 Token 已过期
    ↓
[Auth 拦截器检测]
    ├─ 读取当前 Token
    ├─ 检查过期时间
    └─ 发现已过期
    ↓
[刷新 Token]
    ├─ 调用 refreshToken() 方法
    ├─ 请求新 Token
    └─ 等待结果
    ↓
[更新 Token]
    ├─ 保存新 Token
    └─ 返回到 Token 管理器
    ↓
[重试原请求]
    ├─ 使用新 Token 重新发送
    └─ 继续请求链
```

### 去重机制

```dart
// 用户同时发起三个相同请求
final future1 = dio.get('/api/users');  // 第一个请求
final future2 = dio.get('/api/users');  // 第二个请求
final future3 = dio.get('/api/users');  // 第三个请求

// Dedup 插件处理：
// 1. future1 生成 Key="GET:/api/users"
//    → 没有相同 Key 在处理，发送网络请求
// 2. future2 生成 Key="GET:/api/users"
//    → 检测到已有相同 Key 在处理，等待 future1 结果
// 3. future3 生成 Key="GET:/api/users"
//    → 检测到已有相同 Key 在处理，等待 future1 结果
// 4. 网络请求完成
//    → future1 返回结果
//    → future2 返回相同结果（无网络开销）
//    → future3 返回相同结果（无网络开销）
```

## 插件安装顺序

```
请求方向 (应用 → 网络)

应用
  ↓
[1] Auth 拦截器 - 注入 Token
  ↓
[2] Cache 拦截器 - 缓存检查
  ↓
[3] Dedup 拦截器 - 去重检查
  ↓
[4] Mock 拦截器 - Mock 检查
  ↓
[5] Dio 核心 - 发送网络
  ↓
[6] Retry 拦截器 - 重试处理（响应侧）
  ↓
[7] Normalize 拦截器 - 响应规范化
  ↓
应用

关键点：
- Auth 最先：其他插件可能需要 Token
- Cache/Dedup/Mock 中间：在网络请求前检查
- Retry 靠后：包装整个请求链
- Normalize 最后：最后处理响应格式
```

## 结算与恢复协作（share / auth / retry / cancel）

这四个插件按"一次逻辑请求"协作，责任跟着请求走，不依赖插件级计数或手动接线：

- **认领登记簿**（`lib/src/request_claims.dart`，内部文件）：`DiomanAuth`（受保护请求）和
  `DiomanRetry`（可能重试的请求）在 `onRequest` 里把自己登记到 `extra['dioman:claims']`，
  交出最终结果时注销；全部注销才算"结果最终确定"。`DiomanShare` 据此推迟结算——没有认领者当场
  结算，有则等登记簿清空；`DiomanCancel` 据此在整个逻辑请求（退避、刷新等待、重放）期间持续追踪
  token。公开请求、mock 短路的请求不会被认领，share 当场结算，不会悬挂。
- **独立结果**：共享结算时存一份快照（`data` 引用不深拷贝）；follower / 落败者各拿一份绑定自己
  `RequestOptions` 的 `Response`/`DioException`，并被标记为 joined，不会再自行重试/刷新重放。
- **重放传输层**（`lib/src/replay_support.dart`）：`share`/`auth`/`retry` 通过 `dio` 属性
  （`Dioman.install`/`DiomanHandle` 自动绑定与解绑）借用宿主的 `httpClientAdapter`/`transformer`；
  未绑定时退回无拦截器的裸 `Dio`。`FormData` 每次重放前克隆，`Stream` 请求体不自动重放。
- **恢复结果的后续处理**：错误阶段恢复成功（auth 重放、retry 重试、share `policy: retry`）后，
  结果会依次交给宿主链上排在恢复者之后的拦截器的 `onResponse`（normalize、breaker、log……），再
  终结链路，与首次成功语义一致；响应阶段的业务失败恢复直接 `handler.next`。

- **下游 reject 的两种语义**：恢复结果交给下游拦截器时，保留 dio 的 InterceptorState 类型。
  `handler.reject(e)`（reject）终止链路，后续错误拦截器不再执行；`handler.reject(e, true)`
  （rejectCallFollowing）或拦截器抛异常，则把错误交给后续错误拦截器。两种都会释放认领。
- **共享结算用下游处理前的快照**：恢复成功后先注销恢复者的认领，没有其它认领者就立刻以
  "下游处理之前"的结果结算 share，再让下游（normalize 等）处理并终结。各调用者（leader、
  follower）因此各自只处理一次，不会把已解包的结果再解一层。
- **end / race 的最终仲裁**：请求交出最终结果（成功或失败）时，若 share 判定它已落败
  （race 已有胜者或仍有在途请求、end 已被更新的请求取代），auth/retry 不直接把自己的结果
  交给调用者，而是等 entry 的胜出结果并经下游处理后交付；错误阶段的落败者也走同一收尾，
  loading、cancel 登记和认领都会正常释放。
- **取消优先于等待**：auth 的刷新等待（请求入口与 401 重放两处）与请求的 `CancelToken`
  竞争，取消时立刻完成 handler、注销认领，共享的刷新本身继续运行。请求入口的任何回调异常
  （`isProtected`/`expiresAt`/`now`/`buildHeader`）都转成 `DioException` 走错误链。
- **已知限制**：恢复结果是直接调用下游拦截器的 `onResponse`，若下游装有
  `QueuedInterceptor`，会绕过它自己的串行队列；复用同一个 `CancelToken` 发起大量请求时，
  每次退避/刷新等待都会挂一个取消监听，直到 token 被取消或回收才释放。

## 与其他项目的关系

- **@codejoo/axp** (TypeScript 版本): 类似的插件化设计
- **其他 Dart-Labs 子包**: 可作为 HTTP 客户端

## 参考

- [README.md](./README.md)
- [源代码](./lib)
- Dio: https://pub.dev/packages/dio
