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

/// checkServiceStatus 的测试辅助入口。
/// 标记服务端要求停止的响应，不把它交给自动重试。
void checkServiceStatus(int? status) {
  if (guardedStatuses.contains(status)) {
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

/// 支持的能力。
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

/// 中立插件允许字段，未知字段必须报错。
const pluginFields = <String, Set<String>>{
  tkAuth: {tkUrlPattern, tkRefresh, tkRefreshQuery},
  tkCache: {tkTtlMs, tkMax, tkMethods},
  tkRetry: {tkMax, tkDelayMs, tkStatuses, tkMethods, tkRespectRetryAfter},
  tkShare: {tkPolicy},
  tkLoading: {tkDelayMs, tkDelayCloseMs},
  tkKey: {tkScope},
  tkTimeout: {tkConnectMs, tkReceiveMs, tkTotalMs},
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
  d.interceptors.add(InterceptorsWrapper(onResponse: (response, handler) {
    try {
      checkServiceStatus(logical(response));
      handler.next(response);
    } catch (error) {
      handler.reject(DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.cancel,
          error: error));
    }
  }, onError: (error, handler) {
    try {
      checkServiceStatus(logical(error.response));
      handler.next(error);
    } catch (cause) {
      handler.next(DioException(
          requestOptions: error.requestOptions,
          response: error.response,
          type: DioExceptionType.cancel,
          error: cause));
    }
  }));
  return d;
}

/// logical 的测试辅助入口。
/// 确定逻辑状态，HTTP 失败优先。
int logical(Response<dynamic>? r) {
  final status = r?.statusCode ?? 0;
  final code = obj(r?.data)[tkCode];
  return status >= 400
      ? status
      : code is int && code != 0
          ? code
          : status;
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
