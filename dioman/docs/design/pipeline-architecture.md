---
title: dioman 核心架构（洋葱管线 + 归一化响应）
status: active
updated: 2026-10-29
summary: 新内核的模块划分、一次请求的数据流、阶段排序、上下文与取消原语、归一化响应与落定、插件接口、客户端 API 和性能设计
---
## TL;DR

- `Dioman(dio: …, plugins: […])` 产出客户端。一次调用就是一个逻辑请求，穿过 5 个阶段的中间件，最内层调用一次 `dio.fetch`。
- 传输边界把 Dio 的响应或异常判定成 `DiomanResponse`；链路里只流转它，`next()` 不抛错。最外层落定：`get` 成功返回数据、失败抛出；`send` 返回结果对象；程序 bug 原样抛出原始异常。
- 插件 = `DiomanPlugin`（名字、阶段、`setup` 或 `handle`）。内置插件位置固定，自定义插件只选阶段。
- 请求不可变，内层改请求用 `next(patch)`；重试、重放就是再调一次 `next()`。
- 决策依据见 [0001](../decisions/0001-pipeline-redesign.md)，插件细则见 [插件规格](pipeline-plugin-spec.md)。

## 1. 结构

```
api.get<Pet>('/pet/{id}', query: {'id': 1})
  │
  ▼
┌─────────────── 落定（内核）：R → data | R | throw R；bug → 原样抛出 ───────────────┐
│ outer       loading → notify                        每个逻辑请求一次           │
│ prepare     repath → filter → timeout               请求整形，一次             │
│ attempt     retry → breaker                         重试边界：往里每次尝试重跑   │
│ credential  auth                                    每次尝试注入 token          │
│ source      mock → share → cache → offline          结果来源，可短路            │
│ ┌──────── 传输（内核）：dio.fetch（使用者的 Dio 拦截器在这里运行）+ 判定 → R ────┐│
└──────────────────────────────────────────────────────────────────────────────┘
```

模块划分（`lib/src/`，旧文件在 B5 删除）：

| 文件 | 职责 |
|---|---|
| `client.dart` | `Dioman`：动词方法、`request/send`、建逻辑请求上下文、登记在途、落定、`use/eject/inspect/cancelAll/pending/extend/dispose` |
| `pipeline.dart` | 插件排序（阶段 + 内置位置表）、链编译、`next(patch)`、每层的异常边界 |
| `stages.dart` | `DiomanStage` 枚举与内置插件位置表 |
| `context.dart` | `DiomanContext`：请求视图、取消、状态键、`key()`、`fail()`、`markReplayable()`、`canReplay()`、`wait()`、`cancelled()` |
| `request.dart` | 不可变的 `DiomanRequest`、`RequestPatch`、与 `RequestOptions` 互转 |
| `transport.dart` | 按需克隆请求体、调用 `dio.fetch`（`validateStatus` 全部放行）、交给工厂判定 |
| `response.dart` | `DiomanKind`、`DiomanResponse`、`DiomanResponseFactory`、`Envelope` |
| `options.dart` | 请求级插件选项的统一解析（`resolveOption`） |
| `key.dart` | key 服务（由旧 `key_plugin.dart` 的算法迁来，行为不变） |
| `clock.dart` | `DiomanClock`：当前时间与计时器工厂，可注入 |
| `plugins/*.dart` | 12 个内置插件 |
| `token_manager.dart` | `DiomanTokenManager` 接口（去掉 `canRefresh`，见插件规格 auth） |

删除：`dioman.dart` 里的 `install/installPlugins/DiomanHandle`、`plugin_order.dart`、`replay_support.dart`、`request_claims.dart`、`extra_keys.dart`、`mock_adapter.dart`，以及 `key/cancel/normalize/log` 四个插件。

## 2. 一次请求的数据流

1. 动词方法把 path、query、data、调用级配置交给内核。内核用 `Options.compose(dio.options, path, …)` **合并一次**，得到有效的 `RequestOptions`，再包成不可变的 `DiomanRequest`（保留有效配置的全部字段）。`dio.fetch` 不会再合并 BaseOptions（dio 5.11.1 已核对）。
2. 内核建逻辑请求级上下文：分配 `id`；建内核 `CancelToken`，并与使用者传入的 token 联动；登记到在途集合（供 `cancelAll`、`pending` 使用）。
3. 按编译好的链从外到内执行。每层拿到的 `ctx.request` 是外层交给它的版本。
4. 到达传输层：如果有层调用过 `markReplayable()`，就按类型克隆请求体（见 §8 P4）；把 `DiomanRequest` 转成 `RequestOptions`，设置 `validateStatus: (_) => true` 和内核 `cancelToken`，调用 `dio.fetch`。
5. 工厂把响应或异常判定成 `R`，原路返回。每层可以读它、替换它，或者再次调用 `next()`。
6. 最外层落定：从在途集合注销、解除取消联动，然后按 §6 返回数据、返回 `R`、抛出 `R`，或抛出原始异常。

## 3. 阶段与排序

| 阶段 | 语义 | 自定义插件的典型用途 |
|---|---|---|
| `outer` | 每个逻辑请求进出一次，看到最终的 `R` | 埋点、整体耗时 |
| `prepare` | 请求整形，只跑一次 | 公共参数、签名前的规整 |
| `attempt` | 重试边界；retry 以内的层每次尝试都重跑 | 每次尝试的日志、请求签名（**自定义插件的默认阶段**） |
| `credential` | 凭证注入与鉴权失败处理 | 自定义 header 鉴权 |
| `source` | 结果来源，可以不触网直接返回 | 本地兜底、离线数据 |

规则：
1. 阶段顺序固定为上表。
2. 同一阶段内：`enforce: pre` 的自定义插件 → 内置插件（固定次序）→ `enforce: post`（默认）的自定义插件；自定义插件之间按 `plugins` 列表顺序。
3. 插件名重复直接抛 `ArgumentError`。内置插件名以 `dioman:` 开头，这个前缀保留给内置插件。
4. 链在构造、`use`、`eject` 时编译一次；在途请求沿用发起时的链快照。
5. `api.inspect()` 返回 `[(stage, name)]`，排查顺序问题只看它。

## 4. 上下文与请求

```dart
/// 中间件拿到的上下文；逻辑请求级字段在各层共享，request 是本层视图。
abstract class DiomanContext<R extends DiomanResponse> {
  int get id;                                   // 逻辑请求序号
  Dioman<R> get client;
  DiomanRequest get request;                    // 本层看到的请求，不可变
  CancelToken get cancelToken;                  // 逻辑请求级：使用者 token ∪ cancelAll
  bool get isCancelled;
  DiomanLogger get log;                         // 受 debug 开关控制
  String? key();                                // 惰性计算，按 request 缓存；不可哈希或 key:false 时为 null
  T? get<T>(StateKey<T> key);                   // 逻辑请求级状态
  void set<T>(StateKey<T> key, T value);
  R fail(DiomanFailure init);                   // 凭空造结果，必须经工厂
  bool canReplay();                             // 最近实际发送的请求体能否安全重放
  void markReplayable();                        // 声明本请求可能被重发，传输层据此克隆请求体
  Future<T?> wait<T>(Future<T> pending, {Duration? timeout});  // 取消原语一，见下
  R? cancelled();                               // 取消原语二：已取消则返回 cancel 结果
}
typedef DiomanNext<R> = Future<R> Function([RequestPatch? patch]);
final class StateKey<T> { const StateKey(this.description); final String description; }
```

**请求不可变**：`DiomanRequest` 的字段都是 final，集合是不可修改的视图。`RequestPatch` 是"要改的字段"加"要删的键"：`headers`、`query`、`extra` 按键合并，`removeHeaders`、`removeQuery` 显式删除；headers 合并不区分大小写；`data`、`path`、`method`、超时、`cancelToken` 整体替换。同一层两次调用 `next()` 拿到同一个基准请求。

**取消原语**（每个 await 之后都要重查）：
- `ctx.wait(pending, timeout:)`：等 `pending` 完成、等取消、等超时三者之一。无论哪种结局，都要取消计时器、摘掉对 token 的监听，并忽略迟到的结果。调用时如果已经取消，立即返回 `null`，不挂任何监听。返回 `null` 表示被取消或超时，调用方用 `ctx.cancelled()` 区分。
- `ctx.cancelled()`：已取消就返回 `kind: cancel` 的结果，否则返回 `null`。
- Dio 的 `CancelToken` 没有"摘掉监听"的接口，内核用自己的订阅登记实现 `wait`，保证测试里能断言"没有残留的监听和计时器"（不变量 I3）。

## 5. 归一化响应

```dart
enum DiomanKind { ok, http, biz, network, timeout, cancel, parse, auth, breaker, offline, internal }

/// 归一化响应：成功、失败、被抛出的都是它。字段在构造时由工厂算好。
class DiomanResponse<D> implements Exception {
  final bool ok;
  final DiomanKind kind;
  final int status;            // 逻辑状态：插件判断 401/403/5xx 一律读它
  final int httpStatus;        // 原始 HTTP 状态，没收到响应时为 0
  final Object? code;          // 业务码，非信封响应为 null
  final String message;
  final D data;
  final String? reason;        // 细分原因，如 auth 的 expired / denied / unauthenticated
  final DiomanRequest request; // 实际发出的请求；share/cache 时是发出那一次的
  final Response<dynamic>? raw;
  final Object? error;         // 原始异常
  final StackTrace? errorStack;
  final StackTrace? callSite;  // 仅 debug：发起请求那一刻的调用点
}
```

**工厂 `DiomanResponseFactory`**（每个客户端一份）：

| 选项 | 默认 | 说明 |
|---|---|---|
| `envelope` | `Envelope(code: 'code', data: 'data', message: 'message')` | 信封字段名；`null` 关闭信封识别。`code` 和 `data` 两个键都在才算信封 |
| `isSuccess(code)` | `code == null \|\| code == 0 \|\| code == '0'` | 业务码判定，只在收到 2xx 响应且是信封时调用 |
| `logicalStatus(response)` | 失败、2xx、业务码是 400–599 的整数 → 业务码；否则 httpStatus | 使用者可以把 `'TOKEN_EXPIRED'` 映射成 401 |
| `expectJson` | `false` | 声明 JSON 却解析失败时判为 `parse` |
| `create(init)` | `DiomanResponse.new` | 扩展点：返回带额外字段的子类 |

**分类规则**（按优先级）：

| 输入 | kind | status |
|---|---|---|
| 内核 token 已取消，或 `DioExceptionType.cancel` | cancel | 0 |
| `connectionTimeout` / `sendTimeout` / `receiveTimeout` | timeout | 0 |
| `unknown` 且 cause 为解码 `FormatException` | parse | HTTP 状态（传输解码闭包保留元信息） |
| `connectionError`、`badCertificate`，或 `unknown` 且 `error` 是 `SocketException`/`HttpException`/`TlsException` | network | 0 |
| `badResponse`（只会来自使用者的 Dio 拦截器主动 reject） | http | 取响应状态 |
| 其余 `DioException.unknown`、非 Dio 异常（使用者拦截器或 Transformer 里的 bug） | internal | 0 |
| 2xx、`expectJson`、数据是非空字符串（不依赖 MIME） | parse | httpStatus |
| 收到响应 | ok / biz / http，按 `isSuccess` 与 2xx 判定 | 按 `logicalStatus` |

内核负责：工厂自己抛错时，改用内置工厂造 `internal` 结果，并保留第一次的异常，保证外层照常收尾。

## 6. 落定

| 情况 | `get/post/…`（返回数据） | `send`（返回结果） |
|---|---|---|
| 成功 | `r.data` | `r` |
| 可预期的失败 | `throw r` | `r`（`ok == false`） |
| 程序 bug（`kind: internal`） | `Error.throwWithStackTrace(r.error, r.errorStack)` | 同左 |

- **bug 不伪装成请求失败**：中间件、判定类回调、使用者 Dio 拦截器或 Transformer 抛出的异常，链内包成 internal 交给外层，保证 `next()` 不出错、外层的计数和注销照常完成；落定时抛出原始异常。
- **调用点**：debug 开启时，内核在发起请求那一刻记下 `StackTrace.current`；失败落定时派生一个带 `callSite` 的副本再抛，不修改被 share/cache 共享的原对象。生产环境不记录，零开销。
- **`reject`**：`Dioman(reject: (r) => …)` 在抛出前转换可预期的失败，用来适配需要特定异常类型的生态。默认原样抛出 `r`。

## 7. 插件接口

```dart
abstract class DiomanPlugin<R extends DiomanResponse> {
  String get name;                              // 内置插件以 dioman: 开头
  DiomanStage get stage => DiomanStage.attempt; // 自定义插件的默认阶段
  DiomanEnforce get enforce => DiomanEnforce.post;
  /// 每个客户端调用一次；状态建在返回的实例里。只有 setup、没有 handle 的插件不进链。
  DiomanPluginInstance<R> setup(Dioman<R> client);
}
abstract class DiomanPluginInstance<R extends DiomanResponse> {
  Future<R> handle(DiomanContext<R> ctx, DiomanNext<R> next);
  void dispose() {}
}
```

约定：
- **状态必须建在 `setup` 返回的实例里**，不能放在插件对象上。插件对象只是配置（可以是 const），同一个插件对象可以装进多个客户端，各自一份状态。
- 插件暴露给使用者的操作（例如 cache 的 `clear`），通过 `api.plugin<DiomanCacheApi>()` 取得。
- 用户回调分两类：**通知类**（loading、notify、onAccessExpired、onAccessDenied、onStateChange、onConnectivityChanged）抛错会被隔离，并输出到 `debugPrint` 级别的错误日志；**判定类**（shouldRetry、delay、onFailure、isProtected、fallbackWhen、shouldCache、shouldTrip、keyBuilder）抛错按 bug 处理。`onRefresh` 例外：它抛错算刷新失败。

## 8. 客户端 API

```dart
class Dioman<R extends DiomanResponse<dynamic>> {
  Dioman({required Dio dio, List<DiomanPlugin<R>> plugins = const [],
          DiomanResponseFactory<R>? response, DiomanKeyOptions key = const DiomanKeyOptions(),
          Object Function(R r)? reject, Object? debug /* bool | DiomanLogger */,
          DiomanClock clock = const DiomanClock.system()});
  Dio get dio;
  Future<T> get<T>(String path, {Map<String, dynamic>? query, Object? data, DiomanCall? call});
  // post / put / patch / delete / head 同形；request<T>(method, path, …)
  Future<DiomanResponse<T>> send<T>(String method, String path, {…});
  void use(DiomanPlugin<R> plugin);
  bool eject(String name);
  A? plugin<A>();                       // 取插件暴露的操作
  List<(DiomanStage, String)> inspect();
  int cancelAll([Object? reason]);
  int get pending;
  Dioman<R> extend({BaseOptions? options, List<DiomanPlugin<R>>? plugins});
  void dispose();
}
```

- `DiomanCall`：调用级配置，包含 headers、超时、使用者的 `cancelToken`、`key`、`silent`、以及各插件的请求级选项（以插件导出的选项键为键）。
- `extend()` 克隆 Dio 的 BaseOptions，默认继承插件列表并各自重新 `setup`，状态不共享。
- `dispose()`：先 `cancelAll()`，再按注册的逆序调用各插件实例的 `dispose`（尽力执行完，最后抛出第一个异常）；之后拒绝新的请求和 `use`。

## 8.1 B1 终审裁决（2026-10-29）

- **链内返回类型为 `DiomanResponse<dynamic>`**，不是使用者的子类 `R`：使用者工厂自身抛错时，内核只能用内置工厂造基础的 internal 结果；如果强转成 `R`，会在运行时抛 TypeError，打破"`next()` 不出错"。`R` 约束的是客户端正常工厂 `create` 的产出；插件要用扩展字段时用 `is` 判断。
- **`ctx.wait` 的错误传递**：被等待的 future 自身出错时，`wait` 把错误交给调用方，不转成 internal；取消与超时返回 `null`，用 `ctx.cancelled()` 区分。
- **请求体保留引用**：`data` 是 Dio 的不透明载荷，只有 `markReplayable()` 时才复制（Map/List/FormData）；headers、query、extra 是不可修改的顶层集合。
- **`send<T>` 的数据可空**：失败时 `data` 为 `null`，原始值在 `raw` 里；结果本身已是 `DiomanResponse<T>` 时保留原实例及扩展字段。
- **待修（B2 落地）**：插件经 `ctx.fail` 造 internal 却不带 `error`/`errorStack` 时，落定处的 `!` 会抛 TypeError 盖掉问题。落定改为：没有 error 抛 `StateError`，没有 stack 用 `StackTrace.current`。

## 9. 性能设计

| # | 做法 |
|---|---|
| P1 | 链只在增删插件时编译，请求时不排序、不查表 |
| P2 | 上下文固定形状；没有 patch 时复用外层实例，有 patch 才派生；状态容器惰性创建 |
| P3 | `key()` 惰性计算并按请求缓存；不用 cache/share 的请求不算 key |
| P4 | 重发前先检查 canReplay，不能重放则返回本次结果，重复传输保护触发 internal；请求体按需克隆：只有 `markReplayable()` 时才克隆。Map/List 递归拷贝，`FormData` 用 `clone()`，`Stream` 等无法克隆的回退原引用并在 debug 下告警，不让请求失败 |
| P5 | 传输层 `validateStatus` 全部放行，HTTP 错误不构造 `DioException` |
| P6 | 失败直接抛 `R`，不另建异常对象；调用点只在 debug 下记录 |
| P7 | 入口只合并一次配置，传输层直接 `fetch`，没有二次合并 |
| P8 | 缓存过期惰性删除，写入时按容量节流清扫（按清扫后的条目数，不按固定间隔，避免 axp B6 发现的平方级插入） |
| P9 | 插件级配置在 `setup` 时预合并；请求级 `true` 或省略时直接复用这份配置 |
