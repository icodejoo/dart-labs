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
- 可选 `DiomanKey(namespace: () => currentAccountId)` 每次启用的请求生成键时取一次账号作用域；非空结果以独立 JSON 字段加入 deep/fast/自定义键，防止跨账号命中缓存或加入旧在途 share 请求。使用非敏感账号标识，不要返回明文 token。
- namespace 未配置、返回 null/空串时保留原键；回调异常转 DioException 并完成一次请求出口。账号作用域由插件统一提供，不增加 DiomanKeyOptions 单请求覆盖；旧缓存及在途请求仍持有原键，不自动清空或取消。
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

## 插件顺序声明

安装顺序原本靠 `Dioman.install` 的固定顺序加 README 文档手工保证。现在每个插件可以**声明**自己的
顺序约束，由 `Dioman` 做稳定拓扑排序并校验；固定顺序的 `install` 入口及其结果不变。

### 设计结论

- **元数据放哪**：`DiomanPlugin.ordering`（默认 `DiomanPluginOrder.none` 的非抽象 getter），含
  `before` / `after` / `requires` 三个名字集合。非抽象默认值，现有自定义插件无需改动。
- **约束语义**：`before`/`after` 只在对方也被安装时生效，指向未安装插件的名字被忽略（即"可选依赖"）；
  `requires` 只要求对方存在，不隐含顺序。一对插件的约束在任意一侧声明一次即可。
- **内置插件只声明 README 里的硬约束**（key 在 cache/share 之前、repath/filter 在 key 之前、cache 在
  offline 之前、offline 在 share/cancel/loading 之前、cache/share/mock 在 cancel/loading 之前、
  cancel/loading 在 auth/retry 之前、breaker 在 retry 之后、normalize 在其余内置插件之后）。声明分散在
  key/cache/offline/cancel/loading/breaker/normalize 里，`share`/`auth`/`retry` 不需要任何改动。
  软性的"规范位置"仍由 `Dioman.install` 的输入顺序表达。
- **排序**：深度优先、按输入顺序处理，放置一个插件前先放好它尚未放置的前驱。无约束的插件保持输入
  顺序，被需要的前驱提前到刚好满足约束的位置，结果确定。`install` 的输入就是规范顺序，且内置约束与之
  一致，所以结果恒等于旧顺序（`test/unit/plugin_order_test.dart` 对 2^16 个子集断言）。
- **校验**（`DiomanPluginOrderException`，带 `issue` 和涉及的插件名）：重复名、缺失必需依赖、环
  （列出环上的名字）、`misordered`（给定顺序违反约束）。`install`/`installPlugins` 在修改 `dio` 之前
  抛出；`insertBefore/insertAfter/prepend/append` 在修改前校验，失败时 handle 与 dio 保持原状；
  `remove` 会拒绝移除被其它插件 `requires` 的插件。
- **新增入口**：`Dioman.sort`、`Dioman.validate`、`Dioman.installPlugins`，`Dioman.install` 增加可选
  `plugins:` 以混入自定义插件。直接操作 `dio.interceptors` 的手写顺序完全不受影响。

### 被放弃的方案

- **只靠一张中心化顺序表**：集中但看不到自定义插件的约束，且 `plugin.ordering` 无法自描述。放弃。
- **给每个内置插件一个全序下标**（rank）：自定义插件无法表达"在 key 之后、cache 之前"，每加一个插件
  都要重排。放弃。
- **每个内置插件都声明"在全部前驱之后"**：约束量 O(n^2)，且把"建议顺序"误当成"硬约束"。放弃。
- **Kahn（取最小下标）**：被需要的前驱要等到别的无约束插件都放完才出现，自定义插件会被挤到意外位置；
  改用深度优先、前驱提前。
- **让 `cache`/`share` `requires` `key`**：README 里"无 key 则 no-op"是合法用法，强制依赖会让
  `install(cache: ...)` 抛错，改变现有行为。放弃。

## extra 键注册表

`RequestOptions.extra` 里的键分三类，集中登记在 `DiomanExtraKeys`（`lib/src/extra_keys.dart`）：

- **公开配置键**：`extra[插件名] = DiomanXxxOptions`，调用方可写。
- **跨插件协议键**：`dioman:key`、`dioman:claims`、`dioman:share:joined`，插件之间的约定，调用方不应写。
- **内部状态键**：`<插件名>:<字段>`，插件自己记账，调用方不应读写。

同名的插件实例读写同一批状态键，会互相覆盖。`DiomanExtraKeys.findSharedState(dio.interceptors)`、
`DiomanHandle.diagnoseSharedStateKeys()` 返回冲突列表，`DiomanExtraKeys.assertNoSharedState` 在
debug 下直接断言。自定义插件可用 `DiomanExtraKeys.register` 登记自己的键（重复登记抛 `StateError`）。

**取舍**：不改任何现有键名与读写代码（私有常量留在各插件里，运行时行为零改动），注册表是一份 const
清单；"源码里的键常量与注册表一致"由 `test/integration/extra_keys_integration_test.dart` 扫描 `lib/src` 守护，新增键忘记登记
会失败；下表由 `DiomanExtraKeys.toMarkdown()` 生成，测试保证它与注册表同步。没有做"插件改读注册表
常量"的大重构（收益小、动到 share/auth/retry 内部）。目前没有键被改名，因此暂不提供旧键别名。

<!-- dioman:extra-keys:start -->
| 键 | 所属插件 | 类别 | 值类型 | 说明 |
|---|---|---|---|---|
| `dioman:auth` | `dioman:auth` | 公开配置 | `DiomanAuthOptions` | 单请求认证覆盖 |
| `dioman:breaker` | `dioman:breaker` | 公开配置 | `DiomanBreakerOptions` | 单请求熔断覆盖 |
| `dioman:cache` | `dioman:cache` | 公开配置 | `DiomanCacheOptions` | 单请求缓存覆盖 |
| `dioman:filter` | `dioman:filter` | 公开配置 | `DiomanFilterOptions` | 单请求参数过滤覆盖 |
| `dioman:qid` | `dioman:qid` | 公开配置 | `DiomanKeyOptions` | 单请求键生成覆盖 |
| `dioman:loading` | `dioman:loading` | 公开配置 | `DiomanLoadingOptions` | 单请求加载态覆盖 |
| `dioman:log` | `dioman:log` | 公开配置 | `DiomanLogOptions` | 单请求日志覆盖 |
| `dioman:mock` | `dioman:mock` | 公开配置 | `DiomanMockOptions` | 单请求 Mock 覆盖 |
| `dioman:normalize` | `dioman:normalize` | 公开配置 | `DiomanNormalizeOptions` | 单请求规范化覆盖 |
| `dioman:offline` | `dioman:offline` | 公开配置 | `DiomanOfflineOptions` | 单请求离线排队覆盖 |
| `dioman:repath` | `dioman:repath` | 公开配置 | `DiomanRepathOptions` | 单请求路径替换覆盖 |
| `dioman:retry` | `dioman:retry` | 公开配置 | `DiomanRetryOptions` | 单请求重试覆盖 |
| `dioman:share` | `dioman:share` | 公开配置 | `DiomanShareOptions` | 单请求去重覆盖 |
| `dioman:timeout` | `dioman:timeout` | 公开配置 | `DiomanTimeoutOptions` | 单请求超时覆盖 |
| `dioman:key` | `dioman:qid` | 跨插件协议 | `String` | key 写入的请求键，cache/share 读取 |
| `dioman:claims` | `dioman:share` | 跨插件协议 | `RequestClaims` | 认领登记簿：auth/retry 认领，share/cancel 据此推迟结算 |
| `dioman:share:joined` | `dioman:share` | 跨插件协议 | `bool` | 标记跟随者/落败者，auth/retry 见到后不再自行恢复 |
| `dioman:notify:sent` | `dioman:notify` | 内部状态 | `bool` | 同一逻辑请求已发送通知 |
| `dioman:auth:decision` | `dioman:auth` | 内部状态 | `bool` | 本次请求是否受保护的缓存判定 |
| `dioman:auth:protected` | `dioman:auth` | 内部状态 | `bool` | 请求已按受保护处理 |
| `dioman:auth:refreshed` | `dioman:auth` | 内部状态 | `bool` | 本次请求已刷新过令牌，防止重复刷新 |
| `dioman:auth:denied` | `dioman:auth` | 内部状态 | `bool` | 请求被认证拒绝（走错误链） |
| `dioman:auth:tokenUsed` | `dioman:auth` | 内部状态 | `String?` | 注入请求的原始令牌 |
| `dioman:breaker:key` | `dioman:breaker` | 内部状态 | `Record` | 熔断放行凭据（桶、窗口、探测标记） |
| `dioman:cache:key` | `dioman:cache` | 内部状态 | `String` | 本次请求的缓存键 |
| `dioman:cache:ttl` | `dioman:cache` | 内部状态 | `int` | 本次请求解析出的 TTL（毫秒） |
| `dioman:cache:generation` | `dioman:cache` | 内部状态 | `int` | 请求发起时的清理代次 |
| `dioman:cache:policy` | `dioman:cache` | 内部状态 | `DiomanCachePolicy` | 本次请求的缓存策略 |
| `dioman:cancel:token` | `dioman:cancel` | 内部状态 | `CancelToken` | cancel 注入的令牌 |
| `dioman:loading:bracketed` | `dioman:loading` | 内部状态 | `bool` | 请求已打开加载括号 |
| `dioman:loading:delayClose` | `dioman:loading` | 内部状态 | `Duration` | 本次请求的延迟关闭时长 |
| `dioman:retry:callbackFailed` | `dioman:retry` | 内部状态 | `bool` | 重试回调抛过异常 |
| `dioman:share:entry` | `dioman:share` | 内部状态 | `Object` | 请求所属的在途条目 |
| `dioman:share:seq` | `dioman:share` | 内部状态 | `int` | 请求在条目中的序号 |
| `dioman:share:policy` | `dioman:share` | 内部状态 | `DiomanSharePolicy` | 本次请求的去重策略 |
| `dioman:share:retriesLeft` | `dioman:share` | 内部状态 | `int` | retry 策略剩余次数 |
| `dioman:share:interval` | `dioman:share` | 内部状态 | `Duration` | retry 策略重试间隔 |
<!-- dioman:extra-keys:end -->

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
- **首发取消后 follower 重新入链接手**（`start` 策略）：follower 登记时保存自己的
  `RequestOptions` 和请求阶段 handler。首发被取消且还有 `cancelToken` 未取消的 follower 时，
  share 选第一个，清掉它的 joined 标记、重新挂上 entry，再 `handler.next` 让它带着自己的
  options 走完下游整条链（cancel 注入 token、auth 刷新/重放、retry 重试都照常生效；`FormData`/
  `Stream` 是它自己未消费的 body）。它的最终结果经认领登记簿回到 share 结算 entry，其余
  follower 仍从 completer 取结果；它也被取消则递归接手下一个，没有存活 follower 时以取消结算
  并摘除 entry。首发自己的调用方仍拿到取消结果。不再用裸传输替 follower 发请求。
- **认证恢复期间取消**：retry 重试遇 401 交给 auth 恢复，等待期间请求被取消、auth 返回 null 时，
  retry 抛取消错误（响应阶段走 `_failCanceled`），不把原 401/业务失败当最终结果，因此 share 才
  能识别取消并触发 follower 接手。
- **retry 与 breaker 记账**：retry 每次重放前先确认 body 可重放（`prepareForReplay`），成功后才
  领熔断凭据；body 不可重放（如 `Stream`）时直接结束，最终错误不会带着新领的凭据再被记一次。
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
