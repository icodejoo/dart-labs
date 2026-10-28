// ignore_for_file: avoid_relative_lib_imports
// accept/lib 提供中立字段常量。
// accept/lib 是仓库内执行器源码，按目标目录使用相对导入。
/// 本地测试共享夹具，不连接外部测试服务。
library;

import '../../accept/lib/literals.dart';
import 'package:test/test.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'fake_cache_persist.dart';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

/// 封装 TestTokens 测试夹具。
/// 可变 token 夹具，统一原来六处同义实现。
class TestTokens implements DiomanTokenManager {
  /// 构造独立测试实例。
  /// 设置初始访问令牌。
  TestTokens(this._access);
  String? _access;

  /// accessToken 的测试实现。
  /// 读取当前访问令牌。
  @override
  String? get accessToken => _access;

  /// refreshToken 的测试实现。
  /// 返回固定刷新令牌。
  @override
  String? get refreshToken => tkRefresh;

  /// canRefresh 的测试实现。
  /// 允许测试触发刷新。
  @override
  bool get canRefresh => true;

  /// clear 的测试实现。
  /// 清除当前会话。
  @override
  void clear() => _access = null;

  /// set 的测试实现。
  /// 更新访问令牌。
  void set(String? value) => _access = value;

  /// setToken 的测试实现。
  /// 保留原测试的显式更新调用形式。
  void setToken(String? value) => set(value);
}

/// 封装 BucketAdapter 测试夹具。
/// 假适配器：按路径返回状态码；路径在 [gates] 里时挂起，直到对应 Completer 完成。
class BucketAdapter implements HttpClientAdapter {
  final statuses = <String, int>{};
  final gates = <String, Completer<void>>{};

  /// fetch 的测试实现。
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final gate = gates[options.path];
    if (gate != null) await gate.future;
    final code = statuses[options.path] ?? 200;
    return ResponseBody.fromString(tkEmpty11, code, headers: {
      Headers.contentTypeHeader: [tkApplicationJson],
    });
  }

  /// close 的测试实现。
  @override
  void close({bool force = false}) {}
}

/// 假适配器的处理函数：参数是请求与"第几次调用"（从1开始）。
typedef AdapterHandler = Future<ResponseBody> Function(
    RequestOptions options, int n);

/// 封装 RecordingAdapter 测试夹具。
/// 记录调用次数、可由测试用 Completer 卡住响应的假 HttpClientAdapter。
class RecordingAdapter implements HttpClientAdapter {
  /// 构造独立测试实例。
  RecordingAdapter(this.handler);

  final AdapterHandler handler;

  /// 已到达适配器的请求总数。
  int calls = 0;

  /// 每次到达适配器的请求选项。
  final seen = <RequestOptions>[];

  /// fetch 的测试实现。
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final n = ++calls;
    seen.add(options);
    await requestStream?.drain<void>();
    return handler(options, n);
  }

  /// close 的测试实现。
  @override
  void close({bool force = false}) {}
}

/// 封装 CountingTransformer 测试夹具。
/// 统计 transformResponse 调用次数，用来证明重放复用了宿主的 transformer。
class CountingTransformer extends SyncTransformer {
  int responses = 0;

  /// transformResponse 的测试实现。
  @override
  Future<dynamic> transformResponse(
      RequestOptions options, ResponseBody responseBody) {
    responses++;
    return super.transformResponse(options, responseBody);
  }
}

/// jsonBody 的测试辅助入口。
/// 构造 JSON 响应体。
ResponseBody jsonBody(Object body, int status) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });

/// successEnvelope 的测试辅助入口。
/// 成功信封 `{code:0, data:{v:1}}`。
Map<String, dynamic> successEnvelope() => {
      tkCode: 0,
      tkData: {tkV: 1},
      tkMessage: tkEmpty,
    };

/// failureEnvelope 的测试辅助入口。
/// 业务失败信封。
Map<String, dynamic> failureEnvelope() =>
    {tkCode: 1, tkData: null, tkMessage: tkBad};

/// fakeDio 的测试辅助入口。
/// 用假适配器和同步 transformer 建一个 Dio。
Dio fakeDio(RecordingAdapter adapter, {Transformer? transformer}) =>
    Dio(BaseOptions(baseUrl: tkHttpFake))
      ..httpClientAdapter = adapter
      ..transformer = transformer ?? SyncTransformer();

/// settleAsync 的测试辅助入口。
/// 让出事件循环，等其它异步任务推进。
Future<void> settleAsync([int ms = 30]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// testAuth 的测试辅助入口。
/// 构造一个鉴权插件，onRefresh 默认换成 t1。
DiomanAuth testAuth(
  TestTokens tm, {
  Future<void> Function(DiomanTokenManager, Response<dynamic>)? onRefresh,
  void Function()? onExpired,
}) =>
    DiomanAuth(
      tokenManager: tm,
      onRefresh: onRefresh ?? (_, __) async => tm.set(tkT1),
      onAccessExpired: (_, __) async => onExpired?.call(),
    );

/// testRetry 的测试辅助入口。
/// 零延迟的重试插件。
DiomanRetry testRetry({
  int max = 1,
  DiomanShouldRetry? shouldRetry,
  List<String>? methods,
  void Function(int)? onRetry,
}) =>
    DiomanRetry(
      max: max,
      delay: (_, __, ___, ____) => Duration.zero,
      shouldRetry: shouldRetry,
      methods: methods,
      onRetry: onRetry,
    );

/// retryBusinessFailure 的测试辅助入口。
/// 业务失败（code != 0）视为可重试。
bool? retryBusinessFailure(DioException? err, Response<dynamic>? r) {
  final d = r?.data;
  return d is Map && d[tkCode] != null && d[tkCode] != 0 ? true : null;
}

/// installStateful 的测试辅助入口。
/// Installs a subset of the 6 stateful plugins on [dio], in their canonical
/// relative order, auto-adding [DiomanKey] whenever [cache] or [share] is
/// present (both depend on it).
void installStateful(
  Dio dio, {
  DiomanCache? cache,
  DiomanShare? share,
  DiomanCancel? cancel,
  DiomanLoading? loading,
  DiomanAuth? auth,
  DiomanRetry? retry,
}) {
  if (cache != null || share != null) dio.interceptors.add(const DiomanKey());
  for (final p in [cache, share, cancel, loading, auth, retry]) {
    if (p != null) dio.interceptors.add(p);
  }
}

/// 封装 Unencodable 测试夹具。
class Unencodable {
  /// toString 的测试实现。
  @override
  String toString() => 'unencodable';
}

/// 封装 AsyncOnlyCachePersist 测试夹具。
/// A [DiomanCachePersist] whose [read] is genuinely async (never returns
/// synchronously), to prove [DiomanCache] awaits it rather than assuming sync.
class AsyncOnlyCachePersist implements DiomanCachePersist {
  final _store = <String, dynamic>{};

  /// read 的测试实现。
  @override
  Future<dynamic> read(String key) async {
    await Future<void>.delayed(Duration.zero);
    return _store[key];
  }

  /// write 的测试实现。
  @override
  Future<void> write(String key, Map<String, dynamic> value) async =>
      _store[key] = value;

  /// remove 的测试实现。
  @override
  Future<void> remove(String key) async => _store.remove(key);

  /// erase 的测试实现。
  @override
  Future<void> erase() async => _store.clear();
}

const pluginNames = [
  tkEnvs, tkRepath, tkFilter, tkKey, tkCache, tkShare, tkMock, //
  tkCancel, tkLoading, tkAuth, tkRetry, tkLog, tkNormalize, //
  tkTimeout, tkOffline, tkBreaker,
];

/// Number of core plugins (bits 0-12) — the paced exception sweep's universe.
const coreCount = 13;

/// Highest mask value for the baseline sweep (all 16 plugins).
final allMax = (1 << pluginNames.length) - 1;

/// Highest mask value for the paced sweep (core 13 only; bits 13-15 stay 0).
final coreMax = (1 << coreCount) - 1;

/// hasBit 的测试辅助入口。
bool hasBit(int mask, int bit) => (mask & (1 << bit)) != 0;

/// hasKey 的测试辅助入口。
bool hasKey(int mask) => hasBit(mask, 3);

/// hasCache 的测试辅助入口。
bool hasCache(int mask) => hasBit(mask, 4);

/// hasAuth 的测试辅助入口。
bool hasAuth(int mask) => hasBit(mask, 9);

/// hasRetry 的测试辅助入口。
bool hasRetry(int mask) => hasBit(mask, 10);

/// hasNormalize 的测试辅助入口。
bool hasNormalize(int mask) => hasBit(mask, 12);

/// installSubset 的测试辅助入口。
/// Installs the subset of the plugins selected by [mask]'s bits (bit i
/// ↔ [_names][i]) — [Dioman.install] slots them into the canonical order
/// regardless of which bits are set. `retry`/`auth` are configured to
/// recover in exactly 1 extra attempt so the exception-path phases below
/// stay deterministic and fast. The three appended plugins (bits 13-15) are
/// configured as pure pass-throughs on the plain-success path: `timeout`
/// only rewrites config, `offline` reports `isOnline: true` so nothing is
/// queued, and `breaker` never trips because every request in the baseline
/// sweep succeeds (its consecutive-failure count stays 0).
DiomanHandle installSubset(Dio dio, int mask, TestTokens tm) {
  /// has 的测试辅助入口。
  bool has(int bit) => hasBit(mask, bit);
  return Dioman.install(
    dio,
    envs: has(0) ? DiomanEnvs(const []) : null,
    timeout:
        has(13) ? DiomanTimeout(probe: () => NetworkQuality.excellent) : null,
    repath: has(1) ? DiomanRepath() : null,
    filter: has(2) ? const DiomanFilter() : null,
    key: has(3) ? const DiomanKey() : null,
    cache: has(4)
        ? DiomanCache(
            persist: FakeCachePersist(),
            cachePolicy: DiomanCachePolicy.memo,
          )
        : null,
    offline: has(14)
        ? DiomanOffline(
            isOnline: () => true,
            onConnectivityChanged: const Stream<bool>.empty(),
          )
        : null,
    share: has(5) ? DiomanShare(policy: DiomanSharePolicy.start) : null,
    mock: has(6) ? DiomanMock(enabled: false) : null,
    cancel: has(7) ? DiomanCancel() : null,
    loading: has(8) ? DiomanLoading(onChanged: (_) {}) : null,
    auth: has(9)
        ? DiomanAuth(
            tokenManager: tm,
            onRefresh: (_, __) async => tm.set(tkT1),
            onAccessExpired: (_, __) async {},
          )
        : null,
    retry: has(10)
        ? DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero)
        : null,
    breaker: has(15) ? DiomanBreaker() : null,
    log: has(11) ? DiomanLog(writer: (m, {error}) {}) : null,
    normalize: has(12) ? const DiomanNormalize() : null,
  );
}

/// describeSubset 的测试辅助入口。
String describeSubset(int mask) => [
      for (var i = 0; i < pluginNames.length; i++)
        if ((mask & (1 << i)) != 0) pluginNames[i],
    ].join('+');

/// isUnwrapped 的测试辅助入口。
/// True if [data] is the envelope's inner payload (`{'v': 1}`) — the shape
/// DiomanNormalize unwraps a success envelope to.
bool isUnwrapped(dynamic data) =>
    data is Map && data.length == 1 && data[tkV] == 1;

/// isRawEnvelope 的测试辅助入口。
/// True if [data] is the raw, un-normalized success envelope.
bool isRawEnvelope(dynamic data) =>
    data is Map &&
    data[tkCode] == 0 &&
    data[tkMessage] == tkEmpty &&
    data[tkData] is Map &&
    (data[tkData] as Map)[tkV] == 1;

/// matchesSuccessShape 的测试辅助入口。
/// The shape a successful response's `.data` must have for [mask] — raw
/// envelope, or unwrapped if DiomanNormalize is in the combination. Used for
/// the baseline, cache-hit, and recovered (retry / auth replay) assertions:
/// a recovered success flows through normalize (if installed) exactly like a
/// first-time success does.
bool matchesSuccessShape(int mask, dynamic data) =>
    hasNormalize(mask) ? isUnwrapped(data) : isRawEnvelope(data);

/// 封装 RecordingPlugin 测试夹具。
/// Minimal DiomanPlugin that records its own [name] into [onRun] whenever
/// [onRequest] fires — used to prove a manually-inserted plugin actually
/// runs at its inserted chain position, not just that it appears in the
/// plugin/interceptor lists.
class RecordingPlugin extends DiomanPlugin {
  /// 构造独立测试实例。
  RecordingPlugin(this._name, this.onRun);
  final String _name;
  final void Function(String) onRun;

  /// name 的测试实现。
  @override
  String get name => _name;

  /// onRequest 的测试实现。
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    onRun(_name);
    handler.next(options);
  }
}

/// sourceFiles 的测试辅助入口。
/// 读取 lib/src 下全部源码，返回 {文件名: 内容}。
Map<String, String> sourceFiles() => {
      for (final f in Directory('lib/src').listSync().whereType<File>())
        if (f.path.endsWith('.dart')) f.path: f.readAsStringSync(),
    };

/// assertsEnabled 的测试辅助入口。
/// 断言是否已开启（dart test 默认开启）。
bool get assertsEnabled {
  var on = false;
  assert(on = true);
  return on;
}

/// 封装 CustomPlugin 测试夹具。
class CustomPlugin extends DiomanPlugin {
  /// name 的测试实现。
  @override
  String get name => tkMyPlugin;
}

/// 测试请求路径。
const fixturePath = '/leaf';

/// 测试缓存键。
const cacheKey = 'leaf-key';

/// 持久化失败信息。
const persistFailure = 'persist failure';

/// 测试路由键。
const mockRoute = 'GET:$fixturePath';

/// 第二个字段名。
const secondField = tkB2;

/// 第一个字段名。
const firstField = tkA2;

/// 保留字段名。
const keepField = tkKeep;

/// 测试查询值。
const queryValue = tk1;

/// 嵌套字段名。
const nestedField = tkNested;

/// 数值字段名。
const valueField = tkValue;

/// 写入操作标记。
const writeOperation = 'write';

/// 清空操作标记。
const eraseOperation = 'erase';

/// 查询字段名。
const queryField = 'q';

/// 持久化负载字段。
const dataField = tkData;

/// 持久化过期字段。
const expiryField = tkExpiresAt;

/// 账号 A 的非敏感缓存作用域。
const accountA = 'account-a';

/// 账号 B 的非敏感缓存作用域。
const accountB = 'account-b';

/// 异步隔离用例的最大等待时间。
const namespaceTimeout = Duration(seconds: 2);

/// 旧深度键中的空查询编码。
const emptyQueryKey = tkEmpty11;

/// namespacedKey 的测试辅助入口。
/// 生成指定插件和单请求配置对应的键。
String namespacedKey(DiomanKey plugin, {DiomanKeyOptions? override}) {
  final options = RequestOptions(
      path: fixturePath,
      extra: {if (override != null) DiomanKey.pluginName: override});
  final handler = RecordingRequestHandler();
  plugin.onRequest(options, handler);
  expect(handler.calls, 1);
  return options.extra[kKey] as String;
}

/// pumpEvents 的测试辅助入口。
/// 等待异步入口完成。
Future<void> pumpEvents() => Future<void>.delayed(Duration.zero);

/// 封装 RecordingRequestHandler 测试夹具。
/// 记录出口并检测重复完成。
class RecordingRequestHandler extends RequestInterceptorHandler {
  /// 完成次数。
  int calls = 0;

  /// 缓存响应。
  Response<dynamic>? response;

  /// 拒绝异常。
  DioException? error;

  /// next 的测试实现。
  /// 记录请求放行。
  @override
  void next(RequestOptions options) {
    calls++;
  }

  /// resolve 的测试实现。
  /// 记录短路响应。
  @override
  void resolve(Response response,
      [bool callFollowingResponseInterceptor = false]) {
    calls++;
    this.response = response;
  }

  /// reject 的测试实现。
  /// 记录错误出口。
  @override
  void reject(DioException error,
      [bool callFollowingErrorInterceptor = false]) {
    calls++;
    this.error = error;
  }
}

/// 封装 IgnoringErrorHandler 测试夹具。
/// 不创建带错误的未观察 Future 的错误出口。
class IgnoringErrorHandler extends ErrorInterceptorHandler {
  /// next 的测试实现。
  /// 消费错误出口。
  @override
  void next(DioException error) {}
}

/// 封装 RecordingResponseHandler 测试夹具。
/// 记录响应阶段的唯一出口。
class RecordingResponseHandler extends ResponseInterceptorHandler {
  /// 完成次数。
  int calls = 0;

  /// 持久化错误。
  DioException? error;

  /// next 的测试实现。
  /// 记录响应放行。
  @override
  void next(Response response) {
    calls++;
  }

  /// reject 的测试实现。
  /// 记录错误出口。
  @override
  void reject(DioException error,
      [bool callFollowingErrorInterceptor = false]) {
    calls++;
    this.error = error;
  }
}

/// 封装 ControlledPersist 测试夹具。
/// 可控持久化读取及失败。
class ControlledPersist implements DiomanCachePersist {
  /// 可观察的持久化条目。
  final store = <String, dynamic>{};

  /// 待完成的读取。
  Completer<dynamic>? readGate;

  /// 读取次数。
  int reads = 0;

  /// 操作失败开关。
  bool fails = false;

  /// 写入闸门。
  Completer<void>? writeGate;

  /// 持久化调用顺序。
  final operations = <String>[];

  /// read 的测试实现。
  /// 返回受控读取结果。
  @override
  Future<dynamic> read(String key) async {
    reads++;
    if (fails) throw StateError(persistFailure);
    return readGate == null ? store[key] : readGate!.future;
  }

  /// write 的测试实现。
  /// 等待写入闸门后持久化。
  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    operations.add(writeOperation);
    await writeGate?.future;
    if (fails) throw StateError(persistFailure);
    store[key] = value;
  }

  /// remove 的测试实现。
  /// 记录删除并报告失败。
  @override
  Future<void> remove(String key) async {
    operations.add('remove');
    if (fails) throw StateError(persistFailure);
    store.remove(key);
  }

  /// erase 的测试实现。
  /// 记录清空并报告失败。
  @override
  Future<void> erase() async {
    operations.add(eraseOperation);
    if (fails) throw StateError(persistFailure);
    store.clear();
  }
}

/// 封装 GatedPersist 测试夹具。
/// 按调用序号卡住读取的持久化：第 n 次读取可由 [gates] 里对应的闸门控制。
class GatedPersist extends ControlledPersist {
  /// 读取序号（从 1 起）到闸门的映射，没有闸门的读取直接返回。
  final gates = <int, Completer<dynamic>>{};

  /// read 的测试实现。
  /// 返回受控读取结果。
  @override
  Future<dynamic> read(String key) {
    final n = ++reads;
    if (fails) return Future<dynamic>.error(StateError(persistFailure));
    return gates[n]?.future ?? Future<dynamic>.value(store[key]);
  }
}

/// cacheOptions 的测试辅助入口。
/// 创建带缓存协议键的请求。
RequestOptions cacheOptions([String key = cacheKey]) =>
    RequestOptions(path: fixturePath, extra: {kKey: key});

/// requestKey 的测试辅助入口。
/// 生成请求键。
String requestKey(RequestOptions options) {
  const DiomanKey().onRequest(options, RecordingRequestHandler());
  return options.extra[kKey] as String;
}

/// 改动前 [Dioman.install] 的固定顺序（逐字照抄，作为回归基线）。
const canonicalOrder = <String>[
  tkDiomanEnvs2,
  'dioman:timeout',
  tkDiomanRepath2,
  tkDiomanFilter2,
  tkDiomanQid,
  tkDiomanCache2,
  tkDiomanOffline2,
  tkDiomanShare2,
  tkDiomanMock2,
  tkDiomanCancel2,
  tkDiomanLoading2,
  tkDiomanAuth2,
  tkDiomanRetry2,
  tkDiomanBreaker2,
  tkDiomanLog2,
  tkDiomanNormalize2,
];

/// 封装 OrderTokens 测试夹具。
class OrderTokens implements DiomanTokenManager {
  /// accessToken 的测试实现。
  @override
  String? get accessToken => 't';

  /// refreshToken 的测试实现。
  @override
  String? get refreshToken => 'r';

  /// canRefresh 的测试实现。
  @override
  bool get canRefresh => true;

  /// clear 的测试实现。
  @override
  void clear() {}
}

/// allBuiltins 的测试辅助入口。
/// 按 [canonicalOrder] 顺序构造全部 16 个内置插件。
List<DiomanPlugin> allBuiltins() => [
      DiomanEnvs(const []),
      DiomanTimeout(probe: () => NetworkQuality.excellent),
      DiomanRepath(),
      const DiomanFilter(),
      const DiomanKey(),
      DiomanCache(persist: FakeCachePersist()),
      DiomanOffline(
        isOnline: () => true,
        onConnectivityChanged: const Stream<bool>.empty(),
      ),
      DiomanShare(),
      DiomanMock(enabled: false),
      DiomanCancel(),
      DiomanLoading(onChanged: (_) {}),
      DiomanAuth(
        tokenManager: OrderTokens(),
        onRefresh: (_, __) async {},
        onAccessExpired: (_, __) async {},
      ),
      DiomanRetry(),
      DiomanBreaker(),
      DiomanLog(writer: (m, {error}) {}),
      const DiomanNormalize(),
    ];

/// 封装 OrderedPlugin 测试夹具。
/// 可声明顺序约束的测试插件。
class OrderedPlugin extends DiomanPlugin {
  /// 构造独立测试实例。
  OrderedPlugin(
    this._name, {
    this.before = const {},
    this.after = const {},
    this.requires = const {},
  });
  final String _name;
  final Set<String> before;
  final Set<String> after;
  final Set<String> requires;

  /// name 的测试实现。
  @override
  String get name => _name;

  /// ordering 的测试实现。
  @override
  DiomanPluginOrder get ordering =>
      DiomanPluginOrder(before: before, after: after, requires: requires);
}

/// orderedNames 的测试辅助入口。
List<String> orderedNames(Iterable<DiomanPlugin> ps) =>
    [for (final p in ps) p.name];

/// 独立测试路径，避免与其它测试的缓存或桶混用。
const replayPath = '/review';

/// 测试字段名。
const replayField = tkField;

/// 测试错误说明。
const replayFailure = 'review failure';

/// 测试时间片，足够等待本地计时器。
const replayTick = Duration(milliseconds: 30);

/// handlerCompletion 的测试辅助入口。
/// 获取 Dio handler 的受保护完成结果，仅在测试中使用。
Future<dynamic> handlerCompletion(dynamic handler) =>
    handler.future as Future<dynamic>;

/// 封装 ThrowingStage 测试夹具。
/// 按确定行为测试下游同步抛出和异步抛出的区别。
class ThrowingStage extends Interceptor {
  /// 构造独立测试实例。
  /// 选择异步抛出路径。
  ThrowingStage(this.asynchronous);

  /// 是否通过 Future 抛出。
  final bool asynchronous;

  /// onResponse 的测试实现。
  /// 不完成 handler，错误必须由 ReplayClient 转成下游错误。
  @override
  dynamic onResponse(Response response, ResponseInterceptorHandler handler) {
    if (asynchronous) return Future<void>.error(StateError(replayFailure));
    throw StateError(replayFailure);
  }
}

/// 封装 UnclonableForm 测试夹具。
/// 自定义 FormData 可能拒绝克隆，执行器必须放弃重放。
class UnclonableForm extends FormData {
  /// clone 的测试实现。
  /// 显式拒绝克隆，模拟外部一次性附件实现。
  @override
  FormData clone() => throw StateError(replayFailure);
}

/// 封装 BrokenCloneForm 测试夹具。
/// 外部 multipart 实现的非状态类克隆失败，验证共享异常出口。
class BrokenCloneForm extends FormData {
  /// clone 的测试实现。
  /// 模拟附件克隆时发现格式错误。
  @override
  FormData clone() => throw const FormatException(replayFailure);
}
