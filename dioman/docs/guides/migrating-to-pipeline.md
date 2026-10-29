---
title: 从 0.7.2 迁移到洋葱管线
status: active
updated: 2026-10-29
summary: 安装、结果、插件、扩展、测试与旧 API 逐项替代
---

# 从 0.7.2 迁移到洋葱管线

## 安装方式

将安装到 Dio 的拦截器改为持有 Dioman 客户端。裸调 Dio 不经过管线。动态安装用 use，移除用 eject，查看顺序用 inspect；extend 重新 setup，不共享插件状态。dispose 不关闭调用方持有的 Dio。

旧写法（仅供识别，不参与编译）：

<!-- docs:old -->
```dart
final handle = Dioman.install(dio, plugins: plugins);
final response = await dio.get("/users");
```

新写法：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [const DiomanRepath(), const DiomanFilter(), const DiomanCache()]);
  try {
    final data = await api.get<Map<String, dynamic>>('/users/{id}',
        query: {'id': 42},
        call: DiomanCall(options: {DiomanCache.option: const Duration(minutes: 1)}));
    print(data);
    final result = await api.send<dynamic>('GET', '/health');
    print('${result.kind.name}: ${result.status} / ${result.httpStatus}');
  } on DiomanResponse catch (failure) {
    print('${failure.kind.name}: ${failure.message}');
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- 通过 api 发起逻辑请求；底层 Dio 的拦截器仍负责实际传输。
- 固定阶段决定执行顺序，重复插件名在构造或 use 时拒绝；不再手工 sort/validate。
- use/eject/inspect 管理当前客户端，extend 重新 setup 独立状态；dispose 不关闭调用方的 Dio。

## 请求与结果

动词方法返回 data；send 返回完整结果。query 替代 Dio 调用的 queryParameters；请求配置使用 DiomanCall。key/cancel/normalize/log 无需安装：分别使用 DiomanKeyOptions、cancelAll/pending、DiomanResponseFactory、debug 或 Dio LogInterceptor。显式 key 字符串覆盖自动键，false 同时禁用 cache/share。envelope=false 保留原数据；silent=true 抑制默认通知。

旧写法：

<!-- docs:old -->
```dart
final response = await dio.get('/items', queryParameters: {'page': 1},
    options: Options(extra: {'dioman:retry': 2}));
print(response.data);
```

新写法：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio());
  try {
    final data = await api.get<List<dynamic>>('/items', query: {'page': 1},
        call: DiomanCall(options: {DiomanRetry.option: 2}));
    print(data);
    final result = await api.send<dynamic>('GET', '/items');
    print(result.status);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- 动词方法直接返回 data；需要状态、原因和原始响应时使用 send。
- extra 不再承载插件配置；key、silent、envelope 和 options 都放在 DiomanCall。

## 错误处理

捕获 DiomanResponse，按 kind 与 reason 分流；不要再捕获旧异常子类。status 是逻辑状态，httpStatus 是 HTTP 状态。send 对可预期失败返回结果，但程序错误仍原样抛出。判定回调的错误不吞掉；通知回调错误隔离，onRefresh 抛错算刷新失败。

旧写法：

<!-- docs:old -->
```dart
try {
  await dio.get('/items');
} on DioException catch (error) {
  if (error.error is DiomanException) print(error.error);
}
```

新写法：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')));
  try {
    final r = await api.send<dynamic>('GET', '/items',
        call: const DiomanCall(key: false, envelope: false, silent: true));
    if (!r.ok && r.kind == DiomanKind.offline) print(r.reason);
  } finally { api.dispose(); api.dio.close(force: true); }
}
```

行为差异：

- 动词方法失败时抛 DiomanResponse；send 返回失败结果，程序错误仍抛出。
- 业务状态与 HTTP 状态分别查看 status/httpStatus，失败类别与具体原因分别查看 kind/reason。

## 每个插件

### Loading

旧写法：

<!-- docs:old -->
```dart
Dioman.install(dio, loading: DiomanLoading(onChanged: (busy) => print(busy)));
await dio.get('/items');
```

新写法（独立编译单元）：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [DiomanLoading(onChanged: (visible) => print(visible))]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanLoading.option: false}));
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- `onChanged(bool visible)` 签名沿用；计数改为覆盖整个逻辑请求，刷新、重试、缓存命中和离线等待都在同一显示周期内。
- 按回调身份计数并成对关闭；用 `api.plugin<DiomanLoadingApi>()` 读取 activeCount，回调异常不会改变结果。

### Notify

旧写法：

<!-- docs:old -->
```dart
Dioman.install(dio, plugins: [DiomanNotify(
  notify: (message) => print(message),
  stringify: (data, message, status, options) => message,
)]);
```

新写法（独立编译单元）：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [DiomanNotify(notify: (message, result) => print(message))]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanNotify.option: false}));
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- `notify(message)` 改为 `notify(message, result)`；`stringify(data, message, status, options)` 改为 `stringify(result, ctx)`。
- 默认只提示最终失败，取消和 silent 请求不提示；通知异常隔离。需要业务定制时直接读取 result 的归一化字段。

### Repath

旧写法：

<!-- docs:old -->
```dart
Dioman.install(dio, repath: DiomanRepath());
await dio.get('/users/{id}', queryParameters: {'id': 42});
```

新写法（独立编译单元）：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [const DiomanRepath()]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanRepath.option: const DiomanRepathOptions(removeKey: false)}));
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- 仍支持 `{id}`、`:id`、`[id]`，先查 query 再查 Map data，并按路径段编码。
- 请求使用 query；单次覆盖放入 `DiomanRepath.option`，不再写字符串 extra。

### Filter

旧写法：

<!-- docs:old -->
```dart
Dioman.install(dio, filter: DiomanFilter());
await dio.get('/items', queryParameters: {'q': '', 'limit': 0});
```

新写法（独立编译单元）：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [const DiomanFilter()]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanFilter.option: false}));
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- 默认过滤顶层 null、NaN 和空白字符串；新增 NaN 过滤，0 和 false 仍保留。
- 请求级 false 可关闭过滤；ignoreKeys/ignoreValues 和 predicate 通过选项对象覆盖。

### Timeout

旧写法：

<!-- docs:old -->
```dart
Dioman.install(dio, timeout: DiomanTimeout(probe: () => NetworkQuality.good));
await dio.get('/items', options: Options(extra: {
  'dioman:timeout': DiomanTimeoutOptions(enabled: false),
}));
```

新写法（独立编译单元）：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [DiomanTimeout(probe: () => NetworkQuality.good)]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanTimeout.option: const DiomanTimeoutOptions(timeouts: {NetworkQuality.good: DiomanTimeouts(receive: Duration(seconds: 5))})}));
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- 网络档位由 probe 提供，插件不自行探测；默认只覆盖连接超时，未指定字段保留 Dio 配置。
- 请求级配置迁入 `DiomanTimeout.option`；共享订阅者的等待上限另见来源层说明。

### Retry

旧写法：

<!-- docs:old -->
```dart
Dioman.install(dio, retry: DiomanRetry(max: 2));
await dio.get('/items', options: Options(extra: {'dioman:retry': 2}));
```

新写法（独立编译单元）：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [const DiomanRetry(max: 2)]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanRetry.option: 2}));
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- 默认 max 为 0，需要重试时显式配置；方法白名单始终优先于 shouldRetry。
- 按归一化逻辑状态判断；每次重试重新穿过 breaker、auth 和来源层，不再接 share/cancel/breaker setter。

### Breaker

旧写法：

<!-- docs:old -->
```dart
final breaker = DiomanBreaker(failureThreshold: 5);
Dioman.install(dio, retry: DiomanRetry(max: 2), breaker: breaker);
print(breaker.bucketCount);
```

新写法（独立编译单元）：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [const DiomanBreaker()]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanBreaker.option: false}));
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- 位于 retry 内侧，每次尝试分别计数；熔断返回 kind=breaker，阻止继续重试。
- 管理能力从配置对象迁至 `api.plugin<DiomanBreakerApi>()`，不能再手工 admit/record。

### Auth

旧写法：

<!-- docs:old -->
```dart
DiomanAuth(tokenManager: tokens, onRefresh: refresh, onAccessExpired: expired,
  onFailure: (store, response) => response.statusCode == 401
      ? DiomanAuthFailureAction.refresh : DiomanAuthFailureAction.others);
```

新写法（独立编译单元）：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

class Tokens implements DiomanTokenManager {
  @override
  String? accessToken = 'demo';
  @override
  String? refreshToken;
  @override
  void setTokens({required String accessToken, String? refreshToken}) {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }
  @override
  void clear() { accessToken = null; refreshToken = null; }
}

Future<void> main() async {
  final tokens = Tokens();
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [DiomanAuth(tokenManager: tokens, onRefresh: (store, result) async { store.setTokens(accessToken: 'renewed'); }, onAccessExpired: (store, result) { store.clear(); },
        onFailure: (result, store) async => result.status == 401
            ? DiomanAuthFailureAction.refresh : DiomanAuthFailureAction.others)]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanAuth.option: false}));
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- `onFailure(store, Response)` 改为可异步的 `onFailure(result, store)`，读取逻辑 status；HTTP 200 的业务 401 也能触发刷新。
- ready 返回 RequestPatch，不再直接改 RequestOptions；tokenManager 不再要求 canRefresh。
- 刷新通过独立客户端获取并保存 token；单客户端单飞，缓存命中也先经过认证。示例 renewed 只是存储演示。

### Mock

旧写法：

<!-- docs:old -->
```dart
Dioman.install(dio, mock: DiomanMock(enabled: true, routes: {
  'GET:/items': (options) async => ResponseBody.fromString(
    '{"code":0,"data":[]}', 200,
    headers: {Headers.contentTypeHeader: ['application/json']}),
}));
```

新写法（独立编译单元）：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [DiomanMock(routes: {'GET:/items': (request) => {'code': 0, 'data': <String>[]}})]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanMock.option: true}));
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- 已发布的拦截器式 mock 改为 source 插件，内联处理器接收 DiomanRequest，可返回原始 data 或 Dio Response。
- 内联命中不进入 share/cache/offline；默认仅 HTTP 404 或 network 触发真实回落，回落重新经过内层。
- 缺少地址和路由时跳过并记录 debug 提示；不会安装传输 adapter。

### Share

旧写法：

<!-- docs:old -->
```dart
Dioman.install(dio, share: DiomanShare());
await dio.get('/items', options: Options(extra: {
  'dioman:share': DiomanShareOptions(policy: DiomanSharePolicy.start),
}));
```

新写法（独立编译单元）：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [const DiomanShare()]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanShare.option: DiomanSharePolicy.start}));
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- 默认不参与请求，必须用 `DiomanShare.option` 开启；false 替代 none。
- start/end/race/retry 各自隔离；同次尝试共享只读结果，每个逻辑调用保有自己的外层重试预算。
- 首发取消仍保留其他订阅者的传输，最后一个订阅者离开才取消；超时计算见来源层说明。

### Cache

旧写法：

<!-- docs:old -->
```dart
Dioman.install(dio, cache: DiomanCache(persist: store));
await dio.get('/items', options: Options(extra: {
  'dioman:cache': DiomanCacheOptions(cachePolicy: DiomanCachePolicy.memo),
}));
```

新写法（独立编译单元）：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [const DiomanCache()]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanCache.option: const Duration(minutes: 1)}));
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- 默认按请求关闭，开启后的策略默认为 memo，只有持久化策略需要 persist；默认只缓存 GET/HEAD 的 ok 结果。
- TTL 使用 Duration；命中复用归一化结果，不再次拆包，读写各自保留快照。
- clear 作废所有在途旧写入，remove 只作废目标 key；管理入口改为 `api.plugin<DiomanCacheApi>()`。

### Offline

旧写法：

<!-- docs:old -->
```dart
final offline = DiomanOffline(isOnline: () => online,
  onConnectivityChanged: connectivity);
Dioman.install(dio, offline: offline);
print(offline.pending);
offline.flush();
```

新写法（独立编译单元）：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [DiomanOffline(isOnline: () => true, onConnectivityChanged: const Stream<bool>.empty())]);
  try {
    final result = await api.send<dynamic>('GET', '/items',
        call: DiomanCall(options: {DiomanOffline.option: const DiomanOfflineOptions(maxWait: Duration(seconds: 10))}));
    print(result.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- 仍按 FIFO 等待，默认容量 50；满时淘汰最早请求，非正容量不设上限。
- 结果使用 kind=offline 与 reason=queueFull/timeout/disposed；不再捕获专用异常。
- 通过 `api.plugin<DiomanOfflineApi>()` 查询 pending 或 flush；dispose 后迟到请求不能再次入队。

### Envs

旧写法：

<!-- docs:old -->
```dart
Dioman.install(dio, envs: DiomanEnvs([
  EnvRule(rule: () => true, config: BaseOptions(baseUrl: 'https://api.example.com')),
]));
```

新写法（独立编译单元）：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(), plugins: [
    DiomanEnvs([EnvRule(rule: () => true, config: BaseOptions(baseUrl: 'https://api.example.com'))]),
  ]);
  print(api.inspect());
  api.dispose();
  api.dio.close(force: true);
}
```

行为差异：

- 只在 setup 时将首个匹配规则合并到 BaseOptions，不进入请求链，也没有请求级 option。
- 不再传宿主 dio 或手工 apply；eject 不恢复旧配置，extend 会重新 setup。

### 来源层与旧版差异

mock 缺地址且无路由时跳过并 debug 告警；内联处理器可返回 data 或 Dio Response，后者保留 HTTP 状态。探测每请求独立，真实回落重新参与 cache/share。

share 首发离开保留同一次传输，最后订阅者离开才取消；四种策略互相隔离，每个逻辑调用持有自己的外层重试预算。start/retry 底层三超时为零；订阅者上限为连接加接收，有 data 再加发送，任一参与值 null/非正则不限时。这是整体上限，不模拟 Dio 阶段进度。共享结果只读，request 属于真正发送的请求。

cache 默认 memo，memo 不必传 persist；GET/HEAD 默认允许。只保存归一化结果，命中不再拆包。持久化 Map 新增 result 元信息，必须完整保留；旧 data/expiresAt 格式仍能读，但只能重建 HTTP 200。写入与返回各有快照；接受存储的未命中可能调用 clone 两次。clear 作废全部在途写入；remove 仅作废目标键。auth 在 cache 外层，清空 token 不能通过缓存绕过认证。

loading 包括缓存命中、共享跟随者、离线与刷新等待。offline 的 reason 包括 queueFull、timeout、disposed；销毁后旧链迟到请求不能再入队。

## 自定义拦截器 → 自定义插件

Dio Interceptor 仍可负责每次传输的底层处理；逻辑请求策略应改为 setup/handle。删除宿主 Dio setter、认领、手工 settle 和下游登记；用固定阶段、next(patch)、StateKey 与实例生命周期组合。

旧写法：

<!-- docs:old -->
```dart
class Trace extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-Trace'] = 'demo';
    handler.next(options);
  }
}
dio.interceptors.add(Trace());
```

新写法：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
class Trace extends DiomanPlugin<DiomanResponse<dynamic>> {
  const Trace();
  @override
  String get name => 'app:trace';
  @override
  DiomanStage get stage => DiomanStage.prepare;
  @override
  DiomanEnforce get enforce => DiomanEnforce.pre;
  @override
  DiomanPluginInstance<DiomanResponse<dynamic>> setup(
      Dioman<DiomanResponse<dynamic>> client) => _Trace();
}
class _Trace extends DiomanPluginInstance<DiomanResponse<dynamic>> {
  final visits = StateKey<int>('visits');
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext<DiomanResponse<dynamic>> ctx,
      DiomanNext<DiomanResponse<dynamic>> next) async {
    ctx.set(visits, (ctx.get(visits) ?? 0) + 1);
    await ctx.wait(Future<bool>.value(true));
    final cancelled = ctx.cancelled();
    if (cancelled != null) return cancelled;
    return next(const RequestPatch(headers: {'X-Trace': 'demo'}));
  }
}

void main() {
  final api = Dioman(dio: Dio(), plugins: [const Trace()]);
  api.dispose();
  api.dio.close(force: true);
}
```

行为差异：

- setup 返回每客户端独立的实例，状态不放在共享配置对象中。
- next(patch) 派生内层请求，StateKey 使用身份隔离；不再认领请求或手工 settle。
- 多次发送前声明 markReplayable；等待后检查取消，单订阅 Stream 不能保证重放。

## 测试替身

旧写法：

<!-- docs:old -->
```dart
Dioman.install(dio, mock: DiomanMock(enabled: true, routes: {
  'GET:/items': (options) async => ResponseBody.fromString(
    '{"code":0,"data":[42]}', 200,
    headers: {Headers.contentTypeHeader: ['application/json']}),
}));
final response = await dio.get('/items');
assert((response.data as List).single == 42);
```

新写法（无需网络）：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(), plugins: [
    DiomanMock(routes: {'GET:/items': (_) => {'code': 0, 'data': [42]}}),
  ]);
  try {
    final items = await api.get<List<dynamic>>('/items');
    assert(items.single == 42);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- 业务测试从统一客户端入口调用，内联路由返回的信封也经过结果归一化。
- 内核和计时测试可注入脚本化传输与 DiomanClock；真实 Dio 超时、Transformer 和重放仍需本地 HttpServer 验证。
- dispose 释放客户端状态，调用方另外关闭自己持有的 Dio。

## 常见坑

- cache/share 必须逐请求开启；省略不启用。false 替代 none 策略。
- 请求级 now/clock 删除；使用客户端 clock。缓存 TTL 的插件级 clock 仍保留。请求级容量占位删除，实际 LRU 容量在插件上配置。
- filter 新增剔除 NaN；0 与 false 保留。
- token 存储删除 canRefresh；刷新是否失效由 auth 实例管理。
- retry/breaker/auth/cache 共用逻辑状态；breaker 每次尝试计数。
- 自定义判定抛错是程序错误；通知类回调异常不改变请求结果。

## 旧 API 逐项替代

以下逐项来自 B5b 的 api-renames/api-removals；构造参数和成员分别计数。证据中从未发布的中间态不属于 0.7.2 迁移范围，排除计数记录在 B6 审计。对没有一对一替代的条目保留具体裁决原因，不能机械改名。

| 旧 API | 新写法或删除理由 |
|---|---|
| `Dioman.install` | 使用 Dioman 构造客户端；use/eject 管理插件，inspect 查看固定阶段；不再支持锚点插入或手工排序。 |
| `Dioman.installPlugins` | 使用 Dioman 构造客户端；use/eject 管理插件，inspect 查看固定阶段；不再支持锚点插入或手工排序。 |
| `Dioman.sort` | 使用 Dioman 构造客户端；use/eject 管理插件，inspect 查看固定阶段；不再支持锚点插入或手工排序。 |
| `Dioman.validate` | 使用 Dioman 构造客户端；use/eject 管理插件，inspect 查看固定阶段；不再支持锚点插入或手工排序。 |
| `DiomanAuth.cancel` | 由客户端维护生命周期；凭证通过 ready 返回 RequestPatch 注入，移除 Dio 宿主和取消/共享接线。 |
| `DiomanAuth.dio` | 由客户端维护生命周期；凭证通过 ready 返回 RequestPatch 注入，移除 Dio 宿主和取消/共享接线。 |
| `DiomanAuth.dispose` | 由客户端维护生命周期；凭证通过 ready 返回 RequestPatch 注入，移除 Dio 宿主和取消/共享接线。 |
| `DiomanAuth.new(now)` | 由客户端维护生命周期；凭证通过 ready 返回 RequestPatch 注入，移除 Dio 宿主和取消/共享接线。 |
| `DiomanAuth.onError` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanAuth.onRequest` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanAuth.onResponse` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanAuth.share` | 由客户端维护生命周期；凭证通过 ready 返回 RequestPatch 注入，移除 Dio 宿主和取消/共享接线。 |
| `DiomanAuthOptions.new(now)` | 请求级时钟已删除，使用 Dioman(clock: …)；其它字段继续通过 DiomanAuth.option 配置。 |
| `DiomanAuthOptions.now` | 请求级时钟已删除，使用 Dioman(clock: …)；其它字段继续通过 DiomanAuth.option 配置。 |
| `DiomanBreaker.admit` | 通过 api.plugin<DiomanBreakerApi>() 查询或重置状态；每次尝试由管线自动申请放行和记账，不能手工 admit/record。 |
| `DiomanBreaker.bucketCount` | `DiomanBreakerApi.bucketCount`。 |
| `DiomanBreaker.dispose` | 通过 api.plugin<DiomanBreakerApi>() 查询或重置状态；每次尝试由管线自动申请放行和记账，不能手工 admit/record。 |
| `DiomanBreaker.isOpen` | `DiomanBreakerApi.isOpen`。 |
| `DiomanBreaker.onError` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanBreaker.onRequest` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanBreaker.onResponse` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanBreaker.ordering` | 通过 api.plugin<DiomanBreakerApi>() 查询或重置状态；每次尝试由管线自动申请放行和记账，不能手工 admit/record。 |
| `DiomanBreaker.recordError` | 通过 api.plugin<DiomanBreakerApi>() 查询或重置状态；每次尝试由管线自动申请放行和记账，不能手工 admit/record。 |
| `DiomanBreaker.recordResponse` | 通过 api.plugin<DiomanBreakerApi>() 查询或重置状态；每次尝试由管线自动申请放行和记账，不能手工 admit/record。 |
| `DiomanBreaker.reset` | `DiomanBreakerApi.reset`。 |
| `DiomanBreaker.stateOf` | `DiomanBreakerApi.stateOf`。 |
| `DiomanBreakerOpenException` | 使用 DiomanResponse(kind: breaker) 与 reason=open；构造失败用 ctx.fail(DiomanFailure(...))。 |
| `DiomanBreakerOpenException.bucketKey` | 使用 DiomanResponse(kind: breaker) 与 reason=open；构造失败用 ctx.fail(DiomanFailure(...))。 |
| `DiomanBreakerOpenException.new` | 使用 DiomanResponse(kind: breaker) 与 reason=open；构造失败用 ctx.fail(DiomanFailure(...))。 |
| `DiomanBreakerOpenException.new(bucketKey)` | 使用 DiomanResponse(kind: breaker) 与 reason=open；构造失败用 ctx.fail(DiomanFailure(...))。 |
| `DiomanBreakerOpenException.new(retryableAt)` | 使用 DiomanResponse(kind: breaker) 与 reason=open；构造失败用 ctx.fail(DiomanFailure(...))。 |
| `DiomanBreakerOpenException.retryableAt` | 使用 DiomanResponse(kind: breaker) 与 reason=open；构造失败用 ctx.fail(DiomanFailure(...))。 |
| `DiomanBreakerOpenException.toString` | 使用 DiomanResponse(kind: breaker) 与 reason=open；构造失败用 ctx.fail(DiomanFailure(...))。 |
| `DiomanCache.clear` | `DiomanCacheApi.clear`。 |
| `DiomanCache.dispose` | 缓存由 source 阶段管理；清理使用 api.plugin<DiomanCacheApi>()，不再手工运行响应钩子。 |
| `DiomanCache.new(now)` | 缓存由 source 阶段管理；清理使用 api.plugin<DiomanCacheApi>()，不再手工运行响应钩子。 |
| `DiomanCache.onRequest` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanCache.onResponse` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanCache.ordering` | 缓存由 source 阶段管理；清理使用 api.plugin<DiomanCacheApi>()，不再手工运行响应钩子。 |
| `DiomanCache.remove` | `DiomanCacheApi.remove`。 |
| `DiomanCacheOptions.maxEntries` | 请求级时钟与容量占位已删除；使用客户端 clock 和插件 maxEntries。TTL 使用 Duration。 |
| `DiomanCacheOptions.new(maxEntries)` | 请求级时钟与容量占位已删除；使用客户端 clock 和插件 maxEntries。TTL 使用 Duration。 |
| `DiomanCacheOptions.new(now)` | 请求级时钟与容量占位已删除；使用客户端 clock 和插件 maxEntries。TTL 使用 Duration。 |
| `DiomanCacheOptions.now` | 请求级时钟与容量占位已删除；使用客户端 clock 和插件 maxEntries。TTL 使用 Duration。 |
| `DiomanCachePolicy.none` | none 已删除；请求级 DiomanCache.option: false 关闭。默认策略 memo。 |
| `DiomanCancel` | 无需安装取消插件；Dioman.cancelAll/pending 与 DiomanCall.cancelToken 覆盖逻辑请求；不再暴露 track/untrack。 |
| `DiomanCancel.cancelAll` | 无需安装取消插件；Dioman.cancelAll/pending 与 DiomanCall.cancelToken 覆盖逻辑请求；不再暴露 track/untrack。 |
| `DiomanCancel.config` | 无需安装取消插件；Dioman.cancelAll/pending 与 DiomanCall.cancelToken 覆盖逻辑请求；不再暴露 track/untrack。 |
| `DiomanCancel.dispose` | 无需安装取消插件；Dioman.cancelAll/pending 与 DiomanCall.cancelToken 覆盖逻辑请求；不再暴露 track/untrack。 |
| `DiomanCancel.name` | 无需安装取消插件；Dioman.cancelAll/pending 与 DiomanCall.cancelToken 覆盖逻辑请求；不再暴露 track/untrack。 |
| `DiomanCancel.new` | 无需安装取消插件；Dioman.cancelAll/pending 与 DiomanCall.cancelToken 覆盖逻辑请求；不再暴露 track/untrack。 |
| `DiomanCancel.new(enabled)` | 无需安装取消插件；Dioman.cancelAll/pending 与 DiomanCall.cancelToken 覆盖逻辑请求；不再暴露 track/untrack。 |
| `DiomanCancel.onError` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanCancel.onRequest` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanCancel.onResponse` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanCancel.ordering` | 无需安装取消插件；Dioman.cancelAll/pending 与 DiomanCall.cancelToken 覆盖逻辑请求；不再暴露 track/untrack。 |
| `DiomanCancel.pluginName` | 无需安装取消插件；Dioman.cancelAll/pending 与 DiomanCall.cancelToken 覆盖逻辑请求；不再暴露 track/untrack。 |
| `DiomanCancel.track` | 无需安装取消插件；Dioman.cancelAll/pending 与 DiomanCall.cancelToken 覆盖逻辑请求；不再暴露 track/untrack。 |
| `DiomanCancel.untrack` | 无需安装取消插件；Dioman.cancelAll/pending 与 DiomanCall.cancelToken 覆盖逻辑请求；不再暴露 track/untrack。 |
| `DiomanCancelOptions` | 取消是内核能力，不能用请求级开关移除登记；使用 DiomanCall.cancelToken。 |
| `DiomanCancelOptions.enabled` | 取消是内核能力，不能用请求级开关移除登记；使用 DiomanCall.cancelToken。 |
| `DiomanCancelOptions.new` | 取消是内核能力，不能用请求级开关移除登记；使用 DiomanCall.cancelToken。 |
| `DiomanCancelOptions.new(enabled)` | 取消是内核能力，不能用请求级开关移除登记；使用 DiomanCall.cancelToken。 |
| `DiomanEnvs.apply` | DiomanEnvs 只在 setup 应用首个命中的 EnvRule；配置克隆后合并，不提供请求拦截入口。 |
| `DiomanEnvs.new(dio)` | DiomanEnvs 只在 setup 应用首个命中的 EnvRule；配置克隆后合并，不提供请求拦截入口。 |
| `DiomanEnvs.onRequest` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanException` | `DiomanResponse`。 |
| `DiomanException.code` | `DiomanResponse.code`。 |
| `DiomanException.data` | `DiomanResponse.data`。 |
| `DiomanException.message` | `DiomanResponse.message`。 |
| `DiomanException.new` | `DiomanResponse.new`。 新结果构造需要 ok/kind/status/httpStatus/request/data；插件优先用 ctx.fail，不可只改构造器名字。 |
| `DiomanException.new(code)` | `DiomanResponse.new(code)`。 新结果构造需要 ok/kind/status/httpStatus/request/data；插件优先用 ctx.fail，不可只改构造器名字。 |
| `DiomanException.new(data)` | `DiomanResponse.new(data)`。 新结果构造需要 ok/kind/status/httpStatus/request/data；插件优先用 ctx.fail，不可只改构造器名字。 |
| `DiomanException.new(message)` | `DiomanResponse.new(message)`。 新结果构造需要 ok/kind/status/httpStatus/request/data；插件优先用 ctx.fail，不可只改构造器名字。 |
| `DiomanException.toString` | `DiomanResponse.toString`。 |
| `DiomanExtraKey` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.config` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.config(description)` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.config(name)` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.config(valueType)` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.description` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.key` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.kind` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.new` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.new(description)` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.new(key)` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.new(kind)` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.new(owner)` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.new(valueType)` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.owner` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.state` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.state(description)` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.state(key)` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.state(owner)` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.state(valueType)` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.toString` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKey.valueType` | 字符串 extra 注册协议已删除；请求配置用 DiomanOptionKey 与 DiomanCall.options，链内状态用 StateKey。 |
| `DiomanExtraKeyKind` | 字符串键的描述类型已删除；用类型化选项键或 StateKey 表达用途。 |
| `DiomanExtraKeyKind.config` | 字符串键的描述类型已删除；用类型化选项键或 StateKey 表达用途。 |
| `DiomanExtraKeyKind.protocol` | 字符串键的描述类型已删除；用类型化选项键或 StateKey 表达用途。 |
| `DiomanExtraKeyKind.state` | 字符串键的描述类型已删除；用类型化选项键或 StateKey 表达用途。 |
| `DiomanExtraKeys` | 无需注册或枚举 extra 协议；使用静态插件 option 键，链内状态用独立 StateKey。 |
| `DiomanExtraKeys.all` | 无需注册或枚举 extra 协议；使用静态插件 option 键，链内状态用独立 StateKey。 |
| `DiomanExtraKeys.assertNoSharedState` | 无需注册或枚举 extra 协议；使用静态插件 option 键，链内状态用独立 StateKey。 |
| `DiomanExtraKeys.builtIn` | 无需注册或枚举 extra 协议；使用静态插件 option 键，链内状态用独立 StateKey。 |
| `DiomanExtraKeys.findSharedState` | 无需注册或枚举 extra 协议；使用静态插件 option 键，链内状态用独立 StateKey。 |
| `DiomanExtraKeys.lookup` | 无需注册或枚举 extra 协议；使用静态插件 option 键，链内状态用独立 StateKey。 |
| `DiomanExtraKeys.mockAdapterOwner` | 无需注册或枚举 extra 协议；使用静态插件 option 键，链内状态用独立 StateKey。 |
| `DiomanExtraKeys.ofKind` | 无需注册或枚举 extra 协议；使用静态插件 option 键，链内状态用独立 StateKey。 |
| `DiomanExtraKeys.ofOwner` | 无需注册或枚举 extra 协议；使用静态插件 option 键，链内状态用独立 StateKey。 |
| `DiomanExtraKeys.register` | 无需注册或枚举 extra 协议；使用静态插件 option 键，链内状态用独立 StateKey。 |
| `DiomanExtraKeys.toMarkdown` | 无需注册或枚举 extra 协议；使用静态插件 option 键，链内状态用独立 StateKey。 |
| `DiomanExtraKeys.unregister` | 无需注册或枚举 extra 协议；使用静态插件 option 键，链内状态用独立 StateKey。 |
| `DiomanFilter.onRequest` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanHandle` | 直接持有 Dioman 客户端；use/eject/inspect/plugin/dispose 替代安装句柄。 |
| `DiomanHandle.append` | 直接持有 Dioman 客户端；use/eject/inspect/plugin/dispose 替代安装句柄。 |
| `DiomanHandle.diagnoseSharedStateKeys` | 直接持有 Dioman 客户端；use/eject/inspect/plugin/dispose 替代安装句柄。 |
| `DiomanHandle.dispose` | `Dioman.dispose`。 |
| `DiomanHandle.insertAfter` | 直接持有 Dioman 客户端；use/eject/inspect/plugin/dispose 替代安装句柄。 |
| `DiomanHandle.insertBefore` | 直接持有 Dioman 客户端；use/eject/inspect/plugin/dispose 替代安装句柄。 |
| `DiomanHandle.plugin` | `Dioman.plugin`。 |
| `DiomanHandle.plugins` | 直接持有 Dioman 客户端；use/eject/inspect/plugin/dispose 替代安装句柄。 |
| `DiomanHandle.prepend` | 直接持有 Dioman 客户端；use/eject/inspect/plugin/dispose 替代安装句柄。 |
| `DiomanHandle.remove` | 直接持有 Dioman 客户端；use/eject/inspect/plugin/dispose 替代安装句柄。 |
| `DiomanKey` | `DiomanKeyService`。 这是独立构键服务；普通客户端无需安装它，使用 DiomanKeyOptions 与 DiomanCall.key。 |
| `DiomanKey.builder` | 无需安装构键插件；DiomanKeyOptions 配置算法，DiomanCall.key 覆盖单次值，ctx.key() 惰性读取。 |
| `DiomanKey.enabled` | 无需安装构键插件；DiomanKeyOptions 配置算法，DiomanCall.key 覆盖单次值，ctx.key() 惰性读取。 |
| `DiomanKey.fastMode` | 无需安装构键插件；DiomanKeyOptions 配置算法，DiomanCall.key 覆盖单次值，ctx.key() 惰性读取。 |
| `DiomanKey.ignores` | 无需安装构键插件；DiomanKeyOptions 配置算法，DiomanCall.key 覆盖单次值，ctx.key() 惰性读取。 |
| `DiomanKey.name` | 无需安装构键插件；DiomanKeyOptions 配置算法，DiomanCall.key 覆盖单次值，ctx.key() 惰性读取。 |
| `DiomanKey.namespace` | 无需安装构键插件；DiomanKeyOptions 配置算法，DiomanCall.key 覆盖单次值，ctx.key() 惰性读取。 |
| `DiomanKey.new` | `DiomanKeyService.new`。 这是独立构键服务；普通客户端无需安装它，使用 DiomanKeyOptions 与 DiomanCall.key。 |
| `DiomanKey.new(builder)` | 无需安装构键插件；DiomanKeyOptions 配置算法，DiomanCall.key 覆盖单次值，ctx.key() 惰性读取。 |
| `DiomanKey.new(enabled)` | 无需安装构键插件；DiomanKeyOptions 配置算法，DiomanCall.key 覆盖单次值，ctx.key() 惰性读取。 |
| `DiomanKey.new(fastMode)` | 无需安装构键插件；DiomanKeyOptions 配置算法，DiomanCall.key 覆盖单次值，ctx.key() 惰性读取。 |
| `DiomanKey.new(ignores)` | 无需安装构键插件；DiomanKeyOptions 配置算法，DiomanCall.key 覆盖单次值，ctx.key() 惰性读取。 |
| `DiomanKey.new(namespace)` | 无需安装构键插件；DiomanKeyOptions 配置算法，DiomanCall.key 覆盖单次值，ctx.key() 惰性读取。 |
| `DiomanKey.onRequest` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanKey.ordering` | 无需安装构键插件；DiomanKeyOptions 配置算法，DiomanCall.key 覆盖单次值，ctx.key() 惰性读取。 |
| `DiomanKey.pluginName` | 无需安装构键插件；DiomanKeyOptions 配置算法，DiomanCall.key 覆盖单次值，ctx.key() 惰性读取。 |
| `DiomanKeyOptions.enabled` | 显式键改为 DiomanCall.key；单次构键配置也可放入该字段；禁用用 false。 |
| `DiomanKeyOptions.new(enabled)` | 显式键改为 DiomanCall.key；单次构键配置也可放入该字段；禁用用 false。 |
| `DiomanLoading.activeCount` | `DiomanLoadingApi.activeCount`。 |
| `DiomanLoading.dispose` | 通过 api.plugin<DiomanLoadingApi>() 读取计数；显示与收尾由 outer 阶段自动配对，状态不在工厂上。 |
| `DiomanLoading.onError` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanLoading.onRequest` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanLoading.onResponse` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanLoading.ordering` | 通过 api.plugin<DiomanLoadingApi>() 读取计数；显示与收尾由 outer 阶段自动配对，状态不在工厂上。 |
| `DiomanLog` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.enabled` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.logBody` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.logError` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.logHeaders` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.logRequest` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.logResponse` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.maxBodyLength` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.name` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.new` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.new(enabled)` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.new(logBody)` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.new(logError)` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.new(logHeaders)` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.new(logRequest)` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.new(logResponse)` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.new(maxBodyLength)` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.new(writer)` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.onError` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanLog.onRequest` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanLog.onResponse` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanLog.pluginName` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLog.writer` | 使用客户端 debug/DiomanLogger；需要传输正文与头日志时使用 Dio LogInterceptor。没有同名插件或请求级日志开关。 |
| `DiomanLogOptions` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanLogOptions.enabled` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanLogOptions.logBody` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanLogOptions.logError` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanLogOptions.logHeaders` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanLogOptions.logRequest` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanLogOptions.logResponse` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanLogOptions.maxBodyLength` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanLogOptions.new` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanLogOptions.new(enabled)` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanLogOptions.new(logBody)` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanLogOptions.new(logError)` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanLogOptions.new(logHeaders)` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanLogOptions.new(logRequest)` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanLogOptions.new(logResponse)` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanLogOptions.new(maxBodyLength)` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanLogOptions.new(writer)` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanLogOptions.writer` | 日志配置改为客户端 debug 或 Dio LogInterceptor；旧请求级格式化和正文开关没有一对一替代。 |
| `DiomanNormalize` | 归一化由 DiomanResponseFactory 与 Envelope 配置；请求级 DiomanCall.envelope=false 禁止识别，不再安装归一化插件。 |
| `DiomanNormalize.codeKey` | 归一化由 DiomanResponseFactory 与 Envelope 配置；请求级 DiomanCall.envelope=false 禁止识别，不再安装归一化插件。 |
| `DiomanNormalize.dataKey` | 归一化由 DiomanResponseFactory 与 Envelope 配置；请求级 DiomanCall.envelope=false 禁止识别，不再安装归一化插件。 |
| `DiomanNormalize.enabled` | 归一化由 DiomanResponseFactory 与 Envelope 配置；请求级 DiomanCall.envelope=false 禁止识别，不再安装归一化插件。 |
| `DiomanNormalize.isSuccess` | 归一化由 DiomanResponseFactory 与 Envelope 配置；请求级 DiomanCall.envelope=false 禁止识别，不再安装归一化插件。 |
| `DiomanNormalize.messageKey` | 归一化由 DiomanResponseFactory 与 Envelope 配置；请求级 DiomanCall.envelope=false 禁止识别，不再安装归一化插件。 |
| `DiomanNormalize.name` | 归一化由 DiomanResponseFactory 与 Envelope 配置；请求级 DiomanCall.envelope=false 禁止识别，不再安装归一化插件。 |
| `DiomanNormalize.new` | 归一化由 DiomanResponseFactory 与 Envelope 配置；请求级 DiomanCall.envelope=false 禁止识别，不再安装归一化插件。 |
| `DiomanNormalize.new(codeKey)` | 归一化由 DiomanResponseFactory 与 Envelope 配置；请求级 DiomanCall.envelope=false 禁止识别，不再安装归一化插件。 |
| `DiomanNormalize.new(dataKey)` | 归一化由 DiomanResponseFactory 与 Envelope 配置；请求级 DiomanCall.envelope=false 禁止识别，不再安装归一化插件。 |
| `DiomanNormalize.new(enabled)` | 归一化由 DiomanResponseFactory 与 Envelope 配置；请求级 DiomanCall.envelope=false 禁止识别，不再安装归一化插件。 |
| `DiomanNormalize.new(isSuccess)` | 归一化由 DiomanResponseFactory 与 Envelope 配置；请求级 DiomanCall.envelope=false 禁止识别，不再安装归一化插件。 |
| `DiomanNormalize.new(messageKey)` | 归一化由 DiomanResponseFactory 与 Envelope 配置；请求级 DiomanCall.envelope=false 禁止识别，不再安装归一化插件。 |
| `DiomanNormalize.new(shouldNormalize)` | 归一化由 DiomanResponseFactory 与 Envelope 配置；请求级 DiomanCall.envelope=false 禁止识别，不再安装归一化插件。 |
| `DiomanNormalize.onResponse` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanNormalize.ordering` | 归一化由 DiomanResponseFactory 与 Envelope 配置；请求级 DiomanCall.envelope=false 禁止识别，不再安装归一化插件。 |
| `DiomanNormalize.pluginName` | 归一化由 DiomanResponseFactory 与 Envelope 配置；请求级 DiomanCall.envelope=false 禁止识别，不再安装归一化插件。 |
| `DiomanNormalize.shouldNormalize` | 归一化由 DiomanResponseFactory 与 Envelope 配置；请求级 DiomanCall.envelope=false 禁止识别，不再安装归一化插件。 |
| `DiomanNormalizeOptions` | 信封字段与判定改为 DiomanResponseFactory/Envelope；请求级关闭使用 DiomanCall.envelope=false。 |
| `DiomanNormalizeOptions.codeKey` | 信封字段与判定改为 DiomanResponseFactory/Envelope；请求级关闭使用 DiomanCall.envelope=false。 |
| `DiomanNormalizeOptions.dataKey` | 信封字段与判定改为 DiomanResponseFactory/Envelope；请求级关闭使用 DiomanCall.envelope=false。 |
| `DiomanNormalizeOptions.enabled` | 信封字段与判定改为 DiomanResponseFactory/Envelope；请求级关闭使用 DiomanCall.envelope=false。 |
| `DiomanNormalizeOptions.isSuccess` | 信封字段与判定改为 DiomanResponseFactory/Envelope；请求级关闭使用 DiomanCall.envelope=false。 |
| `DiomanNormalizeOptions.messageKey` | 信封字段与判定改为 DiomanResponseFactory/Envelope；请求级关闭使用 DiomanCall.envelope=false。 |
| `DiomanNormalizeOptions.new` | 信封字段与判定改为 DiomanResponseFactory/Envelope；请求级关闭使用 DiomanCall.envelope=false。 |
| `DiomanNormalizeOptions.new(codeKey)` | 信封字段与判定改为 DiomanResponseFactory/Envelope；请求级关闭使用 DiomanCall.envelope=false。 |
| `DiomanNormalizeOptions.new(dataKey)` | 信封字段与判定改为 DiomanResponseFactory/Envelope；请求级关闭使用 DiomanCall.envelope=false。 |
| `DiomanNormalizeOptions.new(enabled)` | 信封字段与判定改为 DiomanResponseFactory/Envelope；请求级关闭使用 DiomanCall.envelope=false。 |
| `DiomanNormalizeOptions.new(isSuccess)` | 信封字段与判定改为 DiomanResponseFactory/Envelope；请求级关闭使用 DiomanCall.envelope=false。 |
| `DiomanNormalizeOptions.new(messageKey)` | 信封字段与判定改为 DiomanResponseFactory/Envelope；请求级关闭使用 DiomanCall.envelope=false。 |
| `DiomanNormalizeOptions.new(shouldNormalize)` | 信封字段与判定改为 DiomanResponseFactory/Envelope；请求级关闭使用 DiomanCall.envelope=false。 |
| `DiomanNormalizeOptions.shouldNormalize` | 信封字段与判定改为 DiomanResponseFactory/Envelope；请求级关闭使用 DiomanCall.envelope=false。 |
| `DiomanNotify.onError` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanNotify.onRequest` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanNotify.onResponse` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanNotify.ordering` | 回调在 outer 阶段消费最终 DiomanResponse；通知异常隔离，取消与 silent 默认不通知。 |
| `DiomanNotifyOptions` | 请求级仅保留 DiomanNotify.option 的布尔开关；静默使用 DiomanCall.silent，回调在插件上配置。 |
| `DiomanNotifyOptions.new` | 请求级仅保留 DiomanNotify.option 的布尔开关；静默使用 DiomanCall.silent，回调在插件上配置。 |
| `DiomanOffline.dispose` | 通过 api.plugin<DiomanOfflineApi>() 查看 pending 或 flush；队列由 source 实例管理，销毁后禁止迟到入队。 |
| `DiomanOffline.flush` | `DiomanOfflineApi.flush`。 |
| `DiomanOffline.onRequest` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanOffline.ordering` | 通过 api.plugin<DiomanOfflineApi>() 查看 pending 或 flush；队列由 source 实例管理，销毁后禁止迟到入队。 |
| `DiomanOffline.pending` | `DiomanOfflineApi.pending`。 |
| `DiomanOfflineException` | 使用 DiomanResponse(kind: offline) 与 reason（queueFull、timeout、disposed）；不再有独立异常类型。 |
| `DiomanOfflineException.new` | 使用 DiomanResponse(kind: offline) 与 reason（queueFull、timeout、disposed）；不再有独立异常类型。 |
| `DiomanOfflineException.new(reason)` | 使用 DiomanResponse(kind: offline) 与 reason（queueFull、timeout、disposed）；不再有独立异常类型。 |
| `DiomanOfflineException.reason` | 使用 DiomanResponse(kind: offline) 与 reason（queueFull、timeout、disposed）；不再有独立异常类型。 |
| `DiomanOfflineException.toString` | 使用 DiomanResponse(kind: offline) 与 reason（queueFull、timeout、disposed）；不再有独立异常类型。 |
| `DiomanOfflineReason` | 原因改为 DiomanResponse.reason 字符串：queueFull、timeout、disposed。 |
| `DiomanOfflineReason.disposed` | 原因改为 DiomanResponse.reason 字符串：queueFull、timeout、disposed。 |
| `DiomanOfflineReason.queueFull` | 原因改为 DiomanResponse.reason 字符串：queueFull、timeout、disposed。 |
| `DiomanOfflineReason.timeout` | 原因改为 DiomanResponse.reason 字符串：queueFull、timeout、disposed。 |
| `DiomanPlugin.dispose` | 配置保留在 DiomanPlugin；handle/dispose 放在 setup 返回的 DiomanPluginInstance，不绑定宿主 Dio setter。 |
| `DiomanPlugin.ordering` | 配置保留在 DiomanPlugin；handle/dispose 放在 setup 返回的 DiomanPluginInstance，不绑定宿主 Dio setter。 |
| `DiomanPluginOrder` | 改为 DiomanStage 和 DiomanEnforce；固定阶段自动排序，重复名称抛 ArgumentError，不再检查 before/after/requires。 |
| `DiomanPluginOrder.after` | 改为 DiomanStage 和 DiomanEnforce；固定阶段自动排序，重复名称抛 ArgumentError，不再检查 before/after/requires。 |
| `DiomanPluginOrder.before` | 改为 DiomanStage 和 DiomanEnforce；固定阶段自动排序，重复名称抛 ArgumentError，不再检查 before/after/requires。 |
| `DiomanPluginOrder.new` | 改为 DiomanStage 和 DiomanEnforce；固定阶段自动排序，重复名称抛 ArgumentError，不再检查 before/after/requires。 |
| `DiomanPluginOrder.new(after)` | 改为 DiomanStage 和 DiomanEnforce；固定阶段自动排序，重复名称抛 ArgumentError，不再检查 before/after/requires。 |
| `DiomanPluginOrder.new(before)` | 改为 DiomanStage 和 DiomanEnforce；固定阶段自动排序，重复名称抛 ArgumentError，不再检查 before/after/requires。 |
| `DiomanPluginOrder.new(requires)` | 改为 DiomanStage 和 DiomanEnforce；固定阶段自动排序，重复名称抛 ArgumentError，不再检查 before/after/requires。 |
| `DiomanPluginOrder.none` | 改为 DiomanStage 和 DiomanEnforce；固定阶段自动排序，重复名称抛 ArgumentError，不再检查 before/after/requires。 |
| `DiomanPluginOrder.requires` | 改为 DiomanStage 和 DiomanEnforce；固定阶段自动排序，重复名称抛 ArgumentError，不再检查 before/after/requires。 |
| `DiomanPluginOrderException` | 排序诊断类型已删除；重复名称在构造或 use 时抛 ArgumentError，其它旧依赖约束改为固定阶段。 |
| `DiomanPluginOrderException.issue` | 排序诊断类型已删除；重复名称在构造或 use 时抛 ArgumentError，其它旧依赖约束改为固定阶段。 |
| `DiomanPluginOrderException.message` | 排序诊断类型已删除；重复名称在构造或 use 时抛 ArgumentError，其它旧依赖约束改为固定阶段。 |
| `DiomanPluginOrderException.new` | 排序诊断类型已删除；重复名称在构造或 use 时抛 ArgumentError，其它旧依赖约束改为固定阶段。 |
| `DiomanPluginOrderException.new(issue)` | 排序诊断类型已删除；重复名称在构造或 use 时抛 ArgumentError，其它旧依赖约束改为固定阶段。 |
| `DiomanPluginOrderException.new(message)` | 排序诊断类型已删除；重复名称在构造或 use 时抛 ArgumentError，其它旧依赖约束改为固定阶段。 |
| `DiomanPluginOrderException.new(plugins)` | 排序诊断类型已删除；重复名称在构造或 use 时抛 ArgumentError，其它旧依赖约束改为固定阶段。 |
| `DiomanPluginOrderException.plugins` | 排序诊断类型已删除；重复名称在构造或 use 时抛 ArgumentError，其它旧依赖约束改为固定阶段。 |
| `DiomanPluginOrderException.toString` | 排序诊断类型已删除；重复名称在构造或 use 时抛 ArgumentError，其它旧依赖约束改为固定阶段。 |
| `DiomanPluginOrderIssue` | 旧顺序问题枚举已删除；inspect 查看阶段，重复名称以 ArgumentError 拒绝。 |
| `DiomanPluginOrderIssue.cycle` | 旧顺序问题枚举已删除；inspect 查看阶段，重复名称以 ArgumentError 拒绝。 |
| `DiomanPluginOrderIssue.duplicateName` | 旧顺序问题枚举已删除；inspect 查看阶段，重复名称以 ArgumentError 拒绝。 |
| `DiomanPluginOrderIssue.misordered` | 旧顺序问题枚举已删除；inspect 查看阶段，重复名称以 ArgumentError 拒绝。 |
| `DiomanPluginOrderIssue.missingDependency` | 旧顺序问题枚举已删除；inspect 查看阶段，重复名称以 ArgumentError 拒绝。 |
| `DiomanRepath.onRequest` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanRetry.breaker` | 重试通过 next 重新进入内层，配置位于工厂，生命周期由客户端管理；删除宿主/取消/共享/熔断接线。 |
| `DiomanRetry.cancel` | 重试通过 next 重新进入内层，配置位于工厂，生命周期由客户端管理；删除宿主/取消/共享/熔断接线。 |
| `DiomanRetry.dio` | 重试通过 next 重新进入内层，配置位于工厂，生命周期由客户端管理；删除宿主/取消/共享/熔断接线。 |
| `DiomanRetry.dispose` | 重试通过 next 重新进入内层，配置位于工厂，生命周期由客户端管理；删除宿主/取消/共享/熔断接线。 |
| `DiomanRetry.onError` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanRetry.onRequest` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanRetry.onResponse` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanRetry.share` | 重试通过 next 重新进入内层，配置位于工厂，生命周期由客户端管理；删除宿主/取消/共享/熔断接线。 |
| `DiomanShare.dio` | source 实例自动仲裁每次尝试，删除手工 settle、下游登记与宿主 Dio；结果只读，最后订阅者离开才取消传输。 |
| `DiomanShare.dispose` | source 实例自动仲裁每次尝试，删除手工 settle、下游登记与宿主 Dio；结果只读，最后订阅者离开才取消传输。 |
| `DiomanShare.hasMultipleDownstreamSettlers` | source 实例自动仲裁每次尝试，删除手工 settle、下游登记与宿主 Dio；结果只读，最后订阅者离开才取消传输。 |
| `DiomanShare.onError` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanShare.onRequest` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanShare.onResponse` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanShare.registerDownstreamSettler` | source 实例自动仲裁每次尝试，删除手工 settle、下游登记与宿主 Dio；结果只读，最后订阅者离开才取消传输。 |
| `DiomanShare.settle` | source 实例自动仲裁每次尝试，删除手工 settle、下游登记与宿主 Dio；结果只读，最后订阅者离开才取消传输。 |
| `DiomanSharePolicy.none` | none 已删除；使用 DiomanShare.option: false。 |
| `DiomanSharedStateKey` | 删除字符串共享状态描述表；逻辑状态用非 const 的 StateKey，客户端状态用 setup 实例。 |
| `DiomanSharedStateKey.count` | 删除字符串共享状态描述表；逻辑状态用非 const 的 StateKey，客户端状态用 setup 实例。 |
| `DiomanSharedStateKey.key` | 删除字符串共享状态描述表；逻辑状态用非 const 的 StateKey，客户端状态用 setup 实例。 |
| `DiomanSharedStateKey.new` | 删除字符串共享状态描述表；逻辑状态用非 const 的 StateKey，客户端状态用 setup 实例。 |
| `DiomanSharedStateKey.new(count)` | 删除字符串共享状态描述表；逻辑状态用非 const 的 StateKey，客户端状态用 setup 实例。 |
| `DiomanSharedStateKey.new(key)` | 删除字符串共享状态描述表；逻辑状态用非 const 的 StateKey，客户端状态用 setup 实例。 |
| `DiomanSharedStateKey.toString` | 删除字符串共享状态描述表；逻辑状态用非 const 的 StateKey，客户端状态用 setup 实例。 |
| `DiomanTimeout.onRequest` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanTokenManager.canRefresh` | canRefresh 删除；onRefresh 决定能否刷新，失效状态由 auth 实例保存。 |
| `LogWriter` | `DiomanLogger`。 |
| `MockFallbackDecider` | 使用 DiomanMock.fallbackWhen，接收归一化结果；默认仅 HTTP 404 或 network 回落。 |
| `MockHandler` | `DiomanMockRoute`。 |
| `cancelAll` | `Dioman.cancelAll`。 |
| `defaultFallback` | 使用 DiomanMock 默认回落规则，或自行配置 fallbackWhen；不再对任意非取消错误回落。 |
| `kKey` | 使用 ctx.key() 或 DiomanCall.key；自动构键由内核负责。 |
