import 'literals.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// 真实服务地址。
final serverUrl =
    Platform.environment['TESTKIT_SERVER'] ?? 'http://127.0.0.1:47080';

/// 代理控制地址。
final netemUrl =
    Platform.environment['TESTKIT_NETEM'] ?? 'http://127.0.0.1:47090';

/// 代理上游，固定使用已启动的业务服务。
final upstream = Uri.parse(serverUrl).authority;

/// 完整矩阵的网络维度。
const matrixNetworks = [
  tkNormal,
  tkWeak,
  'lossy',
  tkOffline,
  'blackhole',
  tkFlap,
  tkDns
];

/// createProbeProxy 的测试辅助入口。
/// 为独立探针创建代理并立即持久化归属，便于中断后安全清理。
Future<Map<String, dynamic>> createProbeProxy(Dio control, String run) async {
  File(tkAcceptResultsProxiesNdjson).parent.createSync(recursive: true);
  final proxy = obj((await control.post<dynamic>(tkProxies,
          data: {tkUpstream: upstream, tkProfile: tkNormal}))
      .data);
  File(tkAcceptResultsProxiesNdjson).writeAsStringSync(
      '${jsonEncode({
            tkRunId: run,
            tkCreated: proxy,
            tkControl: netemUrl,
            tkUpstream: upstream
          })}\n',
      mode: FileMode.append);
  return proxy;
}

/// deleteProbeProxy 的测试辅助入口。
/// 只删除调用方本次创建的代理，并登记删除成功。
Future<void> deleteProbeProxy(
    Dio control, Map<String, dynamic> proxy, String run) async {
  await control.delete<dynamic>('/proxies/${proxy[tkId]}');
  File(tkAcceptResultsProxiesNdjson).writeAsStringSync(
      '${jsonEncode({tkRunId: run, tkDeleted: proxy[tkId]})}\n',
      mode: FileMode.append);
}

/// 服务器限流或熔断时立即中断，禁止领取后续请求。
bool serviceBlocked = false;

/// 服务端用来要求停止的状态码：限流与熔断。
const guardedStatuses = {429, 503};

/// 响应体是否带 testkit 的注入标记（`"reason":"injected"` / `"injected failure"`）。
///
/// testkit 对场景脚本主动注入的失败会在 data 里写 `reason: injected`，真实的
/// 限流/CPU 熔断不会带这个标记。[body] 为原始响应字节；返回是否为注入响应。
///
/// ```dart
/// isInjectedResponse(utf8.encode('{"data":{"reason":"injected"}}')); // true
/// ```
bool isInjectedResponse(List<int> body) =>
    RegExp(r'"reason"\s*:\s*"injected(?: failure)?"')
        .hasMatch(utf8.decode(body, allowMalformed: true));

/// 已解析的响应数据是否带 testkit 的注入标记（`data.reason` 以 `injected` 开头）。
///
/// business 风格下注入的 429/503 以 HTTP 200 加业务码返回，到不了传输层的字节
/// 检查；拦截器和转换器拿到的是解析后的 [data]，用它判定。
bool isInjectedData(dynamic data) {
  final reason = obj(data)[tkReason] ?? obj(obj(data)[tkData])[tkReason];
  return reason is String && reason.startsWith('injected');
}

/// checkServiceStatus 的测试辅助入口。
/// 标记服务端要求停止的响应，不把它交给自动重试。
///
/// [data] 为已解析的响应数据；带注入标记的 429/503 是 testkit 主动注入的，直接放行。
void checkServiceStatus(int? status, {dynamic data}) {
  if (guardedStatuses.contains(status) && !isInjectedData(data)) {
    serviceBlocked = true;
    throw StateError('服务返回 $status，按用户要求停止验收，未重启服务');
  }
}

/// 封装 ServiceGuardAdapter 测试夹具。
/// 在插件重放共用的传输层阻断限流及熔断响应。
class ServiceGuardAdapter implements HttpClientAdapter {
  /// 构造独立测试实例。
  /// 包装真实 io 传输，不合成成功响应。
  ServiceGuardAdapter(this.inner);

  /// 被包装的真实传输层。
  final HttpClientAdapter inner;

  /// fetch 的测试实现。
  /// 在进入重试链之前检测服务状态。
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    final response = await inner.fetch(options, stream, cancelFuture);
    if (!guardedStatuses.contains(response.statusCode)) return response;
    // 429/503 才读响应体：场景脚本主动注入的放行，真实限流/熔断照旧整轮停止。
    final body = await response.stream
        .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
    if (!isInjectedResponse(body)) {
      try {
        checkServiceStatus(response.statusCode);
      } catch (error) {
        throw DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            error: error);
      }
    }
    return ResponseBody(
        Stream.value(Uint8List.fromList(body)), response.statusCode,
        headers: response.headers,
        statusMessage: response.statusMessage,
        isRedirect: response.isRedirect,
        redirects: response.redirects);
  }

  /// close 的测试实现。
  /// 释放自己拥有的传输层。
  @override
  void close({bool force = false}) => inner.close(force: force);
}

/// 隔离请求头。
const runHeader = 'X-Test-Run';

/// 风格请求头。
const styleHeader = 'X-Test-Style';

/// 缺省请求预算。
const defaultBudget = 8000;

/// flap 的连通性采样必须在 1500ms 离线窗口内结束。
const flapProbeBudget = 500;

/// 受保护路径。
const privatePath = '/t/private';

/// 刷新接口。
const refreshPath = '/t/auth/refresh';

/// 登录接口。
const loginPath = '/t/auth/login';

/// 契约默认重试状态。
const retryStatuses = [500, 502, 503, 504];

/// 契约默认幂等方法。
const retryMethods = [tkGET, 'PUT', 'HEAD', tkDELETE, 'OPTIONS'];

/// 插件级能力：与插件一一对应，插件矩阵与幂集按它们生成组合。
const capabilities = {
  tkAuth,
  tkCache,
  tkRetry,
  tkShare,
  tkCancel,
  tkLoading,
  tkMock,
  tkNormalize,
  tkNotify,
  tkRepath,
  tkKey,
  tkFilter,
  tkEnvs,
  tkBreaker,
  tkOffline,
  tkTimeout,
  tkLog
};

/// 细分能力：声明某个具体行为，不对应独立插件，不参与插件矩阵与幂集。
///
/// mock 已在 source 管线中；业务信封始终归一化，不声明 raw-business-code。
const subCapabilities = {
  tkMultipart,
  'keep-alive',
  'share-retry',
  'timeout-send',
  'mock-in-chain',
};

/// 执行器声明的全部能力；场景 requires 里不在其中的按"缺能力"跳过。
const supportedCapabilities = {...capabilities, ...subCapabilities};

/// 缺能力只按场景声明识别；raw-business-code 等未声明能力一律不执行。
List<String> missingCapabilities(Map<String, dynamic> scenario) =>
    (scenario[tkRequires] as List? ?? const [])
        .cast<String>()
        .where((capability) => !supportedCapabilities.contains(capability))
        .toList();

/// 中立插件允许字段，未知字段必须报错。
const pluginFields = <String, Set<String>>{
  tkAuth: {tkUrlPattern, tkRefresh, tkRefreshQuery},
  tkCache: {tkTtlMs, tkMax, tkMethods},
  tkRetry: {tkMax, tkDelayMs, tkStatuses, tkMethods, tkRespectRetryAfter},
  tkShare: {tkPolicy},
  tkLoading: {tkDelayMs, tkDelayCloseMs},
  tkKey: {tkScope},
  tkTimeout: {tkConnectMs, tkSendMs, tkReceiveMs},
  tkBreaker: {tkThreshold, tkOpenMs},
  tkOffline: {tkProbe},
  tkMock: {tkFallbackOn404},
  tkNormalize: {},
  tkNotify: {},
  tkCancel: {},
  tkRepath: {},
  tkFilter: {},
  tkEnvs: {},
  tkLog: {},
};

/// 按 CONTRACT §7 的 32 位线性同余算法生成 [size] 个字节。
///
/// `state = state * 1664525 + 1013904223 mod 2^32`，每步输出高 8 位；
/// 与其他语言逐字节一致，不依赖任何库。
///
/// - [seed] 起始状态，无符号 32 位（0..4294967295）。
/// - [size] 字节数，非负。
///
/// 返回长度为 [size] 的字节数组。
///
/// ```dart
/// seedBytes(1, 4); // 3c 5e 81 b4
/// ```
Uint8List seedBytes(int seed, int size) {
  if (seed < 0 || seed > 0xFFFFFFFF) {
    throw RangeError.range(seed, 0, 0xFFFFFFFF);
  }
  final out = Uint8List(size);
  var state = seed;
  for (var i = 0; i < size; i++) {
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;
    out[i] = state >> 24;
  }
  return out;
}

/// 场景请求体是否为 multipart（只含单个键 `multipart` 的对象）。
bool isMultipartBody(dynamic body) =>
    body is Map && body.length == 1 && body.containsKey(tkMultipart);

/// 把场景里的 multipart 描述构造成 dio 的 [FormData]。
///
/// 先按对象顺序写 `fields`，再按数组顺序写 `files`；文件内容由 `seed`/`size`
/// 经 [seedBytes] 生成，`Content-Type` 固定 `application/octet-stream`。
/// 文件用 [MultipartFile.fromBytes]，可被 FormData 克隆，供重放与内部重试重建。
///
/// - [spec] 即 `request.body.multipart`：`{fields?, files?}`。
///
/// 返回新的 [FormData]。
FormData buildMultipart(Map<String, dynamic> spec) {
  final form = FormData();
  for (final e in obj(spec['fields']).entries) {
    form.fields.add(MapEntry(e.key, '${e.value}'));
  }
  for (final raw in spec['files'] as List? ?? const []) {
    final f = obj(raw);
    form.files.add(MapEntry(
        f['name'] as String,
        MultipartFile.fromBytes(seedBytes(f['seed'] as int, f['size'] as int),
            filename: f['filename'] as String,
            contentType: DioMediaType('application', 'octet-stream'))));
  }
  return form;
}

/// 把场景 `request.body` 转成发给 dio 的请求体：multipart 构造 [FormData]，其余原样。
dynamic requestBody(dynamic body) => isMultipartBody(body)
    ? buildMultipart(obj((body as Map)[tkMultipart]))
    : body;

/// 服务端 `read_delay_ms` 控制参数的字段名。
const readDelayKey = 'read_delay_ms';

/// 递归找出场景里最大的 `read_delay_ms`（毫秒），没有则返回 0。
///
/// 服务端在读请求体前停顿期间不轮询 body，客户端提前超时关闭连接后，处理器仍会
/// 在途到停顿结束；收尾等待 inflight 归零时要把这段时间算进去。
///
/// - [node] 场景 JSON 的任意节点（Map / List / 标量）。
int maxReadDelayMs(dynamic node) {
  var best = 0;
  if (node is Map) {
    for (final e in node.entries) {
      final v = e.value;
      final here = e.key == readDelayKey && v is num ? v.toInt() : 0;
      final deeper = maxReadDelayMs(v);
      best = [best, here, deeper].reduce((a, b) => a > b ? a : b);
    }
  } else if (node is List) {
    for (final x in node) {
      final deeper = maxReadDelayMs(x);
      if (deeper > best) best = deeper;
    }
  }
  return best;
}

/// 按点分路径（如 `meta.conn`）从 [data] 取值，路径不存在返回 null。
dynamic dottedField(dynamic data, String path) {
  dynamic cur = data;
  for (final part in path.split('.')) {
    if (cur is! Map || !cur.containsKey(part)) return null;
    cur = cur[part];
  }
  return cur;
}

/// 判定结果项的 `same_as` 断言：两个请求都成功，且 data 的同一字段相等。
///
/// - [id] 当前结果项 id。
/// - [records] 全部请求事实，按 id 索引。
/// - [spec] 即 `same_as: {id, field}`。
///
/// 通过返回 null，否则返回失败原因。
String? checkSameAs(
    String id, Map<String, dynamic> records, Map<String, dynamic> spec) {
  final otherId = '${spec[tkId]}';
  final field = '${spec['field']}';
  final mine = obj(records[id]);
  final other = obj(records[otherId]);
  if (other.isEmpty) return '$id: same_as 引用的 $otherId 缺少请求结果';
  if (mine[tkOk] != true || other[tkOk] != true) {
    return '$id: same_as 要求双方都成功（ok=true），实际 $id=${mine[tkOk]}、$otherId=${other[tkOk]}';
  }
  final a = dottedField(mine[tkData], field);
  final b = dottedField(other[tkData], field);
  if (a == null || b == null) return '$id: same_as 字段 $field 缺失（$a / $b）';
  if (a != b) return '$id: same_as $field 不等，$id=$a、$otherId=$b';
  return null;
}

/// obj 的测试辅助入口。
/// 统一 JSON 对象转换。
Map<String, dynamic> obj(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : {};

/// ms 的测试辅助入口。
/// 毫秒转换。
Duration ms(num n) => Duration(milliseconds: n.toInt());

/// pause 的测试辅助入口。
/// 等待短时间。
Future<void> pause(num n) => Future<void>.delayed(ms(n));

/// ioClient 的测试辅助入口。
/// 显式使用 io adapter，不读取系统代理。
Dio ioClient(String base, {int budget = defaultBudget}) {
  final d = Dio(BaseOptions(
      baseUrl: base,
      connectTimeout: ms(budget),
      receiveTimeout: ms(budget),
      sendTimeout: ms(budget)));
  d.httpClientAdapter =
      ServiceGuardAdapter(IOHttpClientAdapter(createHttpClient: () {
    return HttpClient()..findProxy = (_) => 'DIRECT';
  }));
  return d;
}

/// subset 的测试辅助入口。
/// 递归子集匹配，数组要求相同长度。
bool subset(dynamic actual, dynamic expected) {
  if (expected is Map) {
    return actual is Map &&
        expected.entries.every(
            (e) => actual.containsKey(e.key) && subset(actual[e.key], e.value));
  }
  if (expected is List) {
    return actual is List &&
        actual.length == expected.length &&
        List.generate(expected.length, (i) => subset(actual[i], expected[i]))
            .every((x) => x);
  }
  return actual == expected;
}

/// range 的测试辅助入口。
/// 统一检查数值区间。
void range(List<String> failures, String label, num value, dynamic spec) {
  final r = obj(spec);
  if ((r[tkEq] != null && value != r[tkEq]) ||
      (r[tkMin] != null && value < r[tkMin]) ||
      (r[tkMax] != null && value > r[tkMax])) {
    failures.add('$label=$value，预期 ${jsonEncode(r)}');
  }
}
