---
title: 从 0.7.2 迁移到洋葱管线
status: active
updated: 2026-11-03
summary: 安装、结果、插件、扩展、测试与旧 API 逐项替代
---

# 从 0.7.2 迁移到洋葱管线

## R2b：发版前收口（C24–C29）

条件导入保留原生 unknown 网络异常的精确分类，web/wasm 使用 Dio 跨平台类型。自动 key 的深模式和快速模式都新增 responseType，Map 键带类型标签，数字 1 和字符串 '1' 不再相撞；原自动缓存键会失效。显式 key 和自定义 builder 保持输出；B8 字节体仍保存哈希与完整 base64。

缓存硬否决 internal/cancel，shouldStore 不能覆盖。expectJson 只约束 json 模式，显式 plain/bytes/stream 放行；可在 Dio BaseOptions 设置 responseType。next() 已取消直接返回，不再调用内层。

cancelAll(reason) 和单个 CancelToken.cancel(reason) 都保留首次取消原因：非空值转为字符串，省略时 failureOf(result)?.reason 为 null。内部离线销毁等专用取消结果仍保留自己的细分原因。debug 对未安装插件的每个选项键每客户端告警一次（含 false/null）；已安装但禁用不告警。

Retry 默认 max: 2，按 300ms、600ms 起指数退避，普通等待默认封顶 10 秒；只作用于幂等方法。要维持旧默认不重试，显式 max: 0。Retry-After 的优先级、60 秒上限、超限不重试和不受 jitter/delayMax 影响均不变。

Dioman<R> 的 R 非基础 DiomanResponse<dynamic> 时，缺 create 在构造期抛 ArgumentError。修法如下：

```dart
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';

/// 业务扩展响应。
class AppResponse extends DiomanResponse<dynamic> {
  /// 从工厂基础结果构造。
  AppResponse(DiomanResponse<dynamic> r)
      : super(ok: r.ok, status: r.status, code: r.code, message: r.message,
          data: r.data, request: r.request, raw: r.raw,
          error: r.error, callSite: r.callSite);
}

/// 注册可构造扩展类型的工厂。
void main() {
  final api = Dioman<AppResponse>(dio: Dio(),
      response: DiomanResponseFactory<AppResponse>(create: AppResponse.new));
  api.dispose();
  api.dio.close();
}
```

## 安装方式

将安装到 Dio 的拦截器改为持有 Dioman 客户端。裸调 Dio 不经过管线。动态安装用 use，移除用 eject，查看顺序用 inspect；extend 重新 setup，auth 会话和 loading 显示按资源共享。dispose 不关闭调用方持有的 Dio。

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
    print('${failureOf(result)?.kind.name}: ${result.status}, code ${result.code}');
  } on DiomanResponse catch (failure) {
    print('${failureOf(failure)?.kind.name}: ${failure.message}');
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- 通过 api 发起逻辑请求；底层 Dio 的拦截器仍负责实际传输。
- 固定阶段决定执行顺序，重复插件名在构造或 use 时拒绝；不再手工 sort/validate。
- use/eject/inspect 管理当前客户端，extend 重新 setup；auth 会话按 TokenManager、loading 按相等回调共享；dispose 不关闭调用方的 Dio。

## R2a 响应契约 Breaking

顶层 kind 改为 failureOf(r)?.kind，DiomanKind 改为 DiomanFailureKind；ok/http/biz 不属于失败标记。顶层 reason 移入 failureOf(r)?.reason。删除 httpStatus，status 仅表示 HTTP（无响应为 0）。业务码缺省为 0；默认 HTTP 2xx 且 code 为 0 或 '0' 成功。客户端 statusOf 与 ctx.statusOf 单独提供有效状态，extend 继承配置；映射抛错按 bug 原栈抛出。

Envelope、envelope/isEnvelope/logicalStatus 与 call.envelope 删除。协议转换改为 parse(body, raw)，返回 DiomanParsed；create 保留扩展构造职责，不能抹掉内核失败事实。需要逐请求跳过信封时，用 DiomanCall(extra: …) 标记，在自定义 parse 读取 raw.requestOptions.extra：

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(dio: Dio(), response: DiomanResponseFactory(
      parse: (body, raw) {
        if (raw.requestOptions.extra['plain'] == true || body is! Map ||
            !body.containsKey('code') ||
            !(body.containsKey('data') || body.containsKey('message'))) {
          return DiomanParsed(data: body);
        }
        return DiomanParsed(code: body['code'] ?? 0, data: body['data'],
            message: '${body['message'] ?? ''}');
      }));
  try {
    await api.send<Object?>('GET', 'https://api.example.com/items',
        call: const DiomanCall(extra: {'plain': true}));
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

## 生命周期与作用域（C19–C21）

Auth 按 TokenManager 共享单飞刷新、过期和无 token 通知状态；无 token 每轮只通知一次，观察到登录 token 后复位。最后一个持有者卸载时解除关联，迟到失败不清 token、不通知；还有持有者时共享失败仍只处理一次。

Loading 按回调 `==` 跨客户端共享，实例方法 tear-off 也归入同一项。`activeCount` 只统计自身占用。卸载只释放自身占用；新请求接管延迟隐藏窗口，旧客户端卸载不关闭已交接的 spinner。窗口归属方卸载取消计时并补发 false，窗口使用安排它的客户端时钟。

`extend(dio: engine)` 直接使用传入引擎，保留拦截器、adapter、transformer。默认 extend 只克隆 BaseOptions，新建 Dio，不复制这些扩展。options 在 setup 后按非空、非默认字段覆盖，Map 按顶层键合并；不能用默认值重置继承的非默认值。显式传父引擎时会共享可变配置，覆盖同时影响父客户端。

插件配置列表默认继承，显式 plugins 则替换；实例、在途请求和链重新建立。工厂、key、reject、debug、clock 继承引用；auth/loading 按资源共享。两份 README 的扩展章节提供完整边界表。

## 请求与结果

动词方法返回 data；send 返回完整结果。query 替代 Dio 调用的 queryParameters；请求配置使用 DiomanCall。key/cancel/normalize/log 无需安装：分别使用 DiomanKeyOptions、cancelAll/pending、DiomanResponseFactory、debug 或 Dio LogInterceptor。显式 key 字符串覆盖自动键，false 同时禁用 cache/share。协议转换使用 parse；silent=true 抑制默认通知。

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
- extra 不再承载插件配置；key、silent、extra 和 options 都放在 DiomanCall。

## 错误处理

Dio unknown 的解码 `FormatException` 现归 `kind: parse`，保留 Dio 提供的 HTTP 状态。HTML 默认按文本；`expectJson: true` 在 json 模式下将 2xx 非空文本判为 parse，不依赖 MIME 声明；显式 plain/bytes/stream 不受严格 JSON 判定约束。

捕获 DiomanResponse，通过 failureOf 读取 kind 与 reason；不要再捕获旧异常子类。status 仅表示 HTTP，删除 httpStatus。send 对可预期失败返回结果，但程序错误仍原样抛出。判定回调的错误不吞掉；通知回调错误隔离，onRefresh 抛错算刷新失败。

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
        call: const DiomanCall(key: false, silent: true));
    if (!r.ok && failureOf(r)?.kind == DiomanFailureKind.offline) print(failureOf(r)?.reason);
  } finally { api.dispose(); api.dio.close(force: true); }
}
```

行为差异：

- 动词方法失败时抛 DiomanResponse；send 返回失败结果，程序错误仍抛出。
- HTTP 状态查看 status，业务码查看 code；有效状态配置 statusOf，失败类别与原因通过 failureOf 读取。

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
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- `onChanged(bool visible)` 签名沿用；计数改为覆盖整个逻辑请求，刷新、重试、缓存命中和离线等待都在同一显示周期内。
- 按回调相等（`==`）共享显示并成对关闭；用 `api.plugin<DiomanLoadingApi>()` 读取 activeCount，回调异常不会改变结果。

### Notify

默认 `stringify` 对 `kind == internal` 返回空串；需要通知时可自行提供 stringify。

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
    print(failureOf(result)?.kind);
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
    print(failureOf(result)?.kind);
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
    print(failureOf(result)?.kind);
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
    print(failureOf(result)?.kind);
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

行为变化：`retryAfterMax` 默认 60 秒。Retry-After 秒数或 HTTP 日期要求的等待超过上限时，不再重试，直接返回本次结果。需要近似无限遵守时显式传很大的 Duration，例如 `retryAfterMax: Duration(days: 36500)`。服务端等待仍不叠 jitter、不受 `delayMax` 限制。一次性流及不透明体最多发送一次。

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
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- 默认 max 为 2，从 300ms 起指数退避，普通等待封顶 10 秒；max: 0 关闭重试，方法白名单始终优先于 shouldRetry。
- 按 ctx.statusOf 的有效状态判断；每次重试重新穿过 breaker、auth 和来源层，不再接 share/cancel/breaker setter。

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
    print(failureOf(result)?.kind);
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

插件与 `DiomanAuthOptions` 新增 `refreshTimeout`，默认 30 秒，使用 `DiomanClock` 计时；超时走刷新失败路径，同一失败会话只通知一次。刷新期间重新登录替换了 token 时，失败等待者按当前 token 继续。`onRefresh` 经同一客户端请求时必须本次关闭 auth：`call: DiomanCall(options: {DiomanAuth.option: false})`。一次性流及不透明体不能重放，返回本次结果。

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
    print(failureOf(result)?.kind);
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
```

行为差异：

- `onFailure(store, Response)` 改为可异步的 `onFailure(result, store)`，读取 HTTP status 或业务 code；默认路由经显式配置的 statusOf 识别 HTTP 200 内的业务 401。
- ready 返回 RequestPatch，不再直接改 RequestOptions；tokenManager 不再要求 canRefresh。
- 刷新通过独立客户端获取并保存 token；同 TokenManager 跨客户端单飞，缓存命中也先经过认证。示例 renewed 只是存储演示。

### Mock

探测后回落前检查请求体是否可重放；一次性流及不透明体返回探测结果，不再次发送。

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
    print(failureOf(result)?.kind);
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

调用方自身取消或订阅超时撤回 end/race 的结果资格，调用方仍保留自己的取消或超时结果；无法安全构键的请求体不参与共享，详见 Cache。

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
    print(failureOf(result)?.kind);
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

自动 key 包含 responseType，Map 键带类型标签；JSON 数组按内容编码，64 KiB 内字节列表保留内容哈希与完整 base64；超大字节体、FormData、Stream、其他对象或编码失败返回 null，不再参与 cache/share。命中返回前重查调用方取消。

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
    print(failureOf(result)?.kind);
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
    print(failureOf(result)?.kind);
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
- retry/breaker/auth 共用 ctx.statusOf 有效状态，cache 读取 ok；breaker 每次尝试计数。
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
| `DiomanBreakerOpenException` | 使用 failureOf(result) 读取 breaker/open；构造失败用 ctx.fail(DiomanFailureKind.breaker, reason: 'open')。 |
| `DiomanBreakerOpenException.bucketKey` | 使用 failureOf(result) 读取 breaker/open；构造失败用 ctx.fail(DiomanFailureKind.breaker, reason: 'open')。 |
| `DiomanBreakerOpenException.new` | 使用 failureOf(result) 读取 breaker/open；构造失败用 ctx.fail(DiomanFailureKind.breaker, reason: 'open')。 |
| `DiomanBreakerOpenException.new(bucketKey)` | 使用 failureOf(result) 读取 breaker/open；构造失败用 ctx.fail(DiomanFailureKind.breaker, reason: 'open')。 |
| `DiomanBreakerOpenException.new(retryableAt)` | 使用 failureOf(result) 读取 breaker/open；构造失败用 ctx.fail(DiomanFailureKind.breaker, reason: 'open')。 |
| `DiomanBreakerOpenException.retryableAt` | 使用 failureOf(result) 读取 breaker/open；构造失败用 ctx.fail(DiomanFailureKind.breaker, reason: 'open')。 |
| `DiomanBreakerOpenException.toString` | 使用 failureOf(result) 读取 breaker/open；构造失败用 ctx.fail(DiomanFailureKind.breaker, reason: 'open')。 |
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
| `DiomanException.new` | `DiomanResponse.new`。 新结果构造需要 ok/status/request；插件优先用 ctx.fail，不可只改构造器名字。 |
| `DiomanException.new(code)` | `DiomanResponse.new(code)`。 新结果构造需要 ok/status/request；插件优先用 ctx.fail，不可只改构造器名字。 |
| `DiomanException.new(data)` | `DiomanResponse.new(data)`。 新结果构造需要 ok/status/request；插件优先用 ctx.fail，不可只改构造器名字。 |
| `DiomanException.new(message)` | `DiomanResponse.new(message)`。 新结果构造需要 ok/status/request；插件优先用 ctx.fail，不可只改构造器名字。 |
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
| `DiomanNormalize` | 协议转换由 DiomanResponseFactory.parse 配置；请求级差异用 DiomanCall.extra 标记并在 parse 读取，不再安装归一化插件。 |
| `DiomanNormalize.codeKey` | 协议转换由 DiomanResponseFactory.parse 配置；请求级差异用 DiomanCall.extra 标记并在 parse 读取，不再安装归一化插件。 |
| `DiomanNormalize.dataKey` | 协议转换由 DiomanResponseFactory.parse 配置；请求级差异用 DiomanCall.extra 标记并在 parse 读取，不再安装归一化插件。 |
| `DiomanNormalize.enabled` | 协议转换由 DiomanResponseFactory.parse 配置；请求级差异用 DiomanCall.extra 标记并在 parse 读取，不再安装归一化插件。 |
| `DiomanNormalize.isSuccess` | 协议转换由 DiomanResponseFactory.parse 配置；请求级差异用 DiomanCall.extra 标记并在 parse 读取，不再安装归一化插件。 |
| `DiomanNormalize.messageKey` | 协议转换由 DiomanResponseFactory.parse 配置；请求级差异用 DiomanCall.extra 标记并在 parse 读取，不再安装归一化插件。 |
| `DiomanNormalize.name` | 协议转换由 DiomanResponseFactory.parse 配置；请求级差异用 DiomanCall.extra 标记并在 parse 读取，不再安装归一化插件。 |
| `DiomanNormalize.new` | 协议转换由 DiomanResponseFactory.parse 配置；请求级差异用 DiomanCall.extra 标记并在 parse 读取，不再安装归一化插件。 |
| `DiomanNormalize.new(codeKey)` | 协议转换由 DiomanResponseFactory.parse 配置；请求级差异用 DiomanCall.extra 标记并在 parse 读取，不再安装归一化插件。 |
| `DiomanNormalize.new(dataKey)` | 协议转换由 DiomanResponseFactory.parse 配置；请求级差异用 DiomanCall.extra 标记并在 parse 读取，不再安装归一化插件。 |
| `DiomanNormalize.new(enabled)` | 协议转换由 DiomanResponseFactory.parse 配置；请求级差异用 DiomanCall.extra 标记并在 parse 读取，不再安装归一化插件。 |
| `DiomanNormalize.new(isSuccess)` | 协议转换由 DiomanResponseFactory.parse 配置；请求级差异用 DiomanCall.extra 标记并在 parse 读取，不再安装归一化插件。 |
| `DiomanNormalize.new(messageKey)` | 协议转换由 DiomanResponseFactory.parse 配置；请求级差异用 DiomanCall.extra 标记并在 parse 读取，不再安装归一化插件。 |
| `DiomanNormalize.new(shouldNormalize)` | 协议转换由 DiomanResponseFactory.parse 配置；请求级差异用 DiomanCall.extra 标记并在 parse 读取，不再安装归一化插件。 |
| `DiomanNormalize.onResponse` | 改为 setup 返回的实例 handle(ctx, next)；调用 next(patch) 执行内层并读取归一化结果，不再使用 Dio handler。 |
| `DiomanNormalize.ordering` | 协议转换由 DiomanResponseFactory.parse 配置；请求级差异用 DiomanCall.extra 标记并在 parse 读取，不再安装归一化插件。 |
| `DiomanNormalize.pluginName` | 协议转换由 DiomanResponseFactory.parse 配置；请求级差异用 DiomanCall.extra 标记并在 parse 读取，不再安装归一化插件。 |
| `DiomanNormalize.shouldNormalize` | 协议转换由 DiomanResponseFactory.parse 配置；请求级差异用 DiomanCall.extra 标记并在 parse 读取，不再安装归一化插件。 |
| `DiomanNormalizeOptions` | 信封字段与判定改为 DiomanResponseFactory.parse；请求级差异用 DiomanCall.extra 与 parse。 |
| `DiomanNormalizeOptions.codeKey` | 信封字段与判定改为 DiomanResponseFactory.parse；请求级差异用 DiomanCall.extra 与 parse。 |
| `DiomanNormalizeOptions.dataKey` | 信封字段与判定改为 DiomanResponseFactory.parse；请求级差异用 DiomanCall.extra 与 parse。 |
| `DiomanNormalizeOptions.enabled` | 信封字段与判定改为 DiomanResponseFactory.parse；请求级差异用 DiomanCall.extra 与 parse。 |
| `DiomanNormalizeOptions.isSuccess` | 信封字段与判定改为 DiomanResponseFactory.parse；请求级差异用 DiomanCall.extra 与 parse。 |
| `DiomanNormalizeOptions.messageKey` | 信封字段与判定改为 DiomanResponseFactory.parse；请求级差异用 DiomanCall.extra 与 parse。 |
| `DiomanNormalizeOptions.new` | 信封字段与判定改为 DiomanResponseFactory.parse；请求级差异用 DiomanCall.extra 与 parse。 |
| `DiomanNormalizeOptions.new(codeKey)` | 信封字段与判定改为 DiomanResponseFactory.parse；请求级差异用 DiomanCall.extra 与 parse。 |
| `DiomanNormalizeOptions.new(dataKey)` | 信封字段与判定改为 DiomanResponseFactory.parse；请求级差异用 DiomanCall.extra 与 parse。 |
| `DiomanNormalizeOptions.new(enabled)` | 信封字段与判定改为 DiomanResponseFactory.parse；请求级差异用 DiomanCall.extra 与 parse。 |
| `DiomanNormalizeOptions.new(isSuccess)` | 信封字段与判定改为 DiomanResponseFactory.parse；请求级差异用 DiomanCall.extra 与 parse。 |
| `DiomanNormalizeOptions.new(messageKey)` | 信封字段与判定改为 DiomanResponseFactory.parse；请求级差异用 DiomanCall.extra 与 parse。 |
| `DiomanNormalizeOptions.new(shouldNormalize)` | 信封字段与判定改为 DiomanResponseFactory.parse；请求级差异用 DiomanCall.extra 与 parse。 |
| `DiomanNormalizeOptions.shouldNormalize` | 信封字段与判定改为 DiomanResponseFactory.parse；请求级差异用 DiomanCall.extra 与 parse。 |
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
| `DiomanOfflineException` | 通过 failureOf(result) 读取 offline 与 reason（queueFull、timeout、disposed）；不再有独立异常类型。 |
| `DiomanOfflineException.new` | 通过 failureOf(result) 读取 offline 与 reason（queueFull、timeout、disposed）；不再有独立异常类型。 |
| `DiomanOfflineException.new(reason)` | 通过 failureOf(result) 读取 offline 与 reason（queueFull、timeout、disposed）；不再有独立异常类型。 |
| `DiomanOfflineException.reason` | 通过 failureOf(result) 读取 offline 与 reason（queueFull、timeout、disposed）；不再有独立异常类型。 |
| `DiomanOfflineException.toString` | 通过 failureOf(result) 读取 offline 与 reason（queueFull、timeout、disposed）；不再有独立异常类型。 |
| `DiomanOfflineReason` | 原因改为 failureOf(result)?.reason 字符串：queueFull、timeout、disposed。 |
| `DiomanOfflineReason.disposed` | 原因改为 failureOf(result)?.reason 字符串：queueFull、timeout、disposed。 |
| `DiomanOfflineReason.queueFull` | 原因改为 failureOf(result)?.reason 字符串：queueFull、timeout、disposed。 |
| `DiomanOfflineReason.timeout` | 原因改为 failureOf(result)?.reason 字符串：queueFull、timeout、disposed。 |
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
| `DiomanTokenManager.canRefresh` | canRefresh 删除；onRefresh 决定能否刷新，失效状态由 TokenManager 对应的共享会话保存。 |
| `LogWriter` | `DiomanLogger`。 |
| `MockFallbackDecider` | 使用 DiomanMock.fallbackWhen，接收归一化结果；默认仅 HTTP 404 或 network 回落。 |
| `MockHandler` | `DiomanMockRoute`。 |
| `cancelAll` | `Dioman.cancelAll`。 |
| `defaultFallback` | 使用 DiomanMock 默认回落规则，或自行配置 fallbackWhen；不再对任意非取消错误回落。 |
| `kKey` | 使用 ctx.key() 或 DiomanCall.key；自动构键由内核负责。 |


## R3：原生响应按需读取

所有成功、失败和缓存结果默认 `raw == null`、`error == null`。将原先直接读取 `result.raw` 的调用改为显式传入 `DiomanCall(raw: true)`；成功时读取响应头也需要开启。可预期失败抛出的结果同样携带自身原生数据。插件在 `await next()` 后通过 `ctx.native` 读取匹配结果的只读视图，逻辑请求落定后槽会清空并永久封闭。

```dart
import 'package:dioman/dioman.dart';
Future<String?> responseHeader(Dioman api) async {
  final result = await api.send<Object?>('GET', '/pets',
      call: const DiomanCall(raw: true));
  return result.raw?.headers.value('etag');
}
```

顶层 `errorStack` 已删除；internal 原始异常与栈改为 `failureOf(result)?.error` 和 `failureOf(result)?.errorStack`，即使没开 raw 仍会原栈重抛。其余失败默认不保留异常。缓存只保存快照，命中经同一工厂重建并绑定当前请求；缓存命中和 share 跟随者没有自身原生数据，即使开 raw 也不借用首发调用方的对象。share 的 request 仍代表实际传输，Retry-After 仍生效。完整 request 的瘦身留待后续批次。

## R5：解码与异步清理

原先 get<User> 只是运行时转型，现在可传 decode: User.fromJson 显式转换。
get/post/put/patch/delete/head/request 返回解码数据，send 返回 data 已解码的结果副本。
只在成功落定后解码；失败按原规则返回或 reject，decode 抛错原对象原栈抛出，不经过插件或改为 parse。
share 每个调用方独立解码，不修改共享响应；解码器应只读输入数据。

插件 dispose 从 void 改为 FutureOr<void>，同步实现仍可保持 void；客户端 dispose 从 void 改为 Future<void>。
客户端同步 cancelAll 并拒绝新请求，因此旧的不 await 写法仍立即生效。
需要等待异步资源清理、捕获清理异常或关闭宿主引擎时，改为 await api.dispose()。
清理按注册逆序串行等待，尽力全部执行，最后原栈抛出首个异常；重复调用返回同一个 Future。
不 await 时，清理失败的异常不再同步抛出，而是随返回的 Future 变成未处理的异步异常；需要捕获就 await，或自行给返回值挂 catchError。

eject(name) 仍返回 bool，异步清理由客户端跟踪；await api.dispose() 会一并等待已移除实例并原栈报告首个观测错误。同步 eject 清理错误仍直接抛出，销毁开始后禁止移除实例。

开启 debug 时新增 retry.jitter 和 cache.clone 字段类型检查；请求级选项仍不做编译期类型化。
两份 README 的 failureOf(r)?.kind 穷举 switch 保留 null 分支，可直接编译。

```dart
import 'package:dioman/dioman.dart';

/// 用户请求路径。
const _userPath = '/user';

/// 调用方的数据模型。
class User {
  /// 保存用户编号。
  User(this.id);

  /// 从成功响应的数据构造用户。
  factory User.fromJson(Object? data) => User((data as Map)['id'] as int);

  /// 用户编号。
  final int id;
}

/// 解码仅在成功落定后执行。
Future<User> loadUser(Dioman api) =>
    api.get<User>(_userPath, decode: User.fromJson);

/// send 保留结果字段并转换 data。
Future<DiomanResponse<User>> sendUser(Dioman api) =>
    api.send<User>('GET', _userPath, decode: User.fromJson);

/// 等待插件完成清理。
Future<void> closeClient(Dioman api) async {
  await api.dispose();
}
```

## 逻辑请求截止时间

`Dioman(deadline: ...)` 设置默认整体预算，请求级 `DiomanCall(deadline: ...)` 非空值优先；均为 null 时不设截止，零或负值立即到期。预算从逻辑请求入口开始，覆盖重试等待、token 刷新排队、离线队列、share 等待和完整传输（含响应体）。到期取消自身内核令牌，结果为 `timeout`、`reason: 'deadline'`，取消判别返回 false。计时使用 `DiomanClock`，所有落定出口均清理计时器。`extend` 继承默认预算。

该能力与 timeout 插件和 Dio connect/send/receive 阶段超时独立。share 订阅者到期只退出自身，最后一人离开才中止共享传输；end/race 按 B8 自身条件撤回，不污染其他调用方。

```dart
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

/// 默认五秒，本次两秒，覆盖排队、重试和传输。
Future<void> deadlineExample() async {
  final api = Dioman(dio: Dio(), deadline: const Duration(seconds: 5));
  try {
    final result = await api.send<Object?>('GET', 'https://example.com/pets',
        call: const DiomanCall(deadline: Duration(seconds: 2)));
    if (failureOf(result)?.reason == 'deadline') {
      assert(failureOf(result)?.kind == DiomanFailureKind.timeout);
    }
  } finally {
    await api.dispose();
  }
}
```
