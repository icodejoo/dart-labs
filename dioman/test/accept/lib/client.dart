import 'literals.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'common.dart';

/// 封装 MemoryPersist 测试夹具。
/// 内存持久化端口，实际缓存行为由插件控制。
class MemoryPersist implements DiomanCachePersist {
  /// 持久化内容。
  final values = <String, dynamic>{};

  /// read 的测试实现。
  /// 读取条目。
  @override
  dynamic read(String key) => values[key];

  /// write 的测试实现。
  /// 写入条目。
  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    values[key] = value;
  }

  /// remove 的测试实现。
  /// 删除条目。
  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  /// erase 的测试实现。
  /// 清空条目。
  @override
  Future<void> erase() async {
    values.clear();
  }
}

/// 封装 Tokens 测试夹具。
/// 令牌存储保留最近一次变化前的值。
class Tokens implements DiomanTokenManager {
  /// 完整鉴权头。
  String? access;

  /// 刷新令牌。
  String? refresh;

  /// 旧鉴权头。
  String? previousAccess;

  /// 旧刷新令牌。
  String? previousRefresh;

  /// 当前用户。
  String user = tkDioman;

  /// accessToken 的测试实现。
  /// 当前令牌。
  @override
  String? get accessToken => access;

  /// refreshToken 的测试实现。
  /// 当前刷新令牌。
  @override
  String? get refreshToken => refresh;

  /// canRefresh 的测试实现。
  /// 是否允许刷新。
  @override
  bool get canRefresh => refresh != null && refresh!.isNotEmpty;

  /// replace 的测试实现。
  /// 更换令牌并记录变化。
  void replace(String? a, String? r) {
    if (a != access) previousAccess = access;
    if (r != refresh) previousRefresh = refresh;
    access = a;
    refresh = r;
  }

  /// accept 的测试实现。
  /// 接收登录或刷新信封数据。
  void accept(Map<String, dynamic> data) => replace(
      data[tkAccessToken] == null ? null : 'Bearer ${data[tkAccessToken]}',
      data[tkRefreshToken] as String?);

  /// clear 的测试实现。
  /// 清空当前令牌。
  @override
  void clear() => replace(null, null);

  /// mutate 的测试实现。
  /// 按契约篡改令牌。
  void mutate(Map<String, dynamic> spec) {
    final parts = (access ?? tkEmpty).split(tkSpace).last.split(tkDot);
    String? a = access;
    switch (spec[tkAccess]) {
      case tkNone:
        a = null;
      case tkEmpty6:
        a = tkEmpty;
      case tkGarbage:
        a = 'Bearer garbage-not-jwt';
      case tkPrevious:
        a = previousAccess;
      case 'wrong_scheme':
        a = 'Token ${(access ?? tkEmpty).split(tkSpace).last}';
      case 'bad_signature':
        if (parts.length == 3) {
          parts[2] =
              '${parts[2].startsWith(tkA) ? 'B' : tkA}${parts[2].substring(1)}';
        }
        a = 'Bearer ${parts.join(tkDot)}';
      case 'tampered_payload':
        if (parts.length == 3) {
          final payload = obj(jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))));
          payload[tkSub] = '${payload[tkSub]}-tampered';
          parts[1] = base64Url
              .encode(utf8.encode(jsonEncode(payload)))
              .replaceAll(tkEquals, tkEmpty);
        }
        a = 'Bearer ${parts.join(tkDot)}';
    }
    final r = switch (spec[tkRefresh]) {
      tkNone => null,
      tkGarbage => 'garbage-refresh',
      tkPrevious => previousRefresh,
      _ => refresh,
    };
    replace(a, r);
  }
}

/// 封装 EnvelopeTransformer 测试夹具。
/// 业务信封在传输边界转成错误，使 auth/retry/cache 看到同一种失败。
class EnvelopeTransformer extends FusedTransformer {
  /// 构造独立测试实例。
  /// 只有安装 normalize 且请求未关闭时启用业务判定。
  EnvelopeTransformer(this.enabled);

  /// 全局业务判定开关。
  final bool enabled;

  /// transformResponse 的测试实现。
  /// 保留原始状态、响应头及响应体。
  @override
  Future<dynamic> transformResponse(
      RequestOptions options, ResponseBody body) async {
    final data = await super.transformResponse(options, body);
    try {
      checkServiceStatus(body.statusCode);
      if (obj(data)[tkCode] is int) {
        checkServiceStatus(obj(data)[tkCode] as int);
      }
    } catch (error) {
      throw DioException(
          requestOptions: options, type: DioExceptionType.cancel, error: error);
    }
    if (body.statusCode < 400 &&
        data is String &&
        data.trim().isNotEmpty &&
        (body.headers[Headers.contentTypeHeader]?.join().contains('html') ??
            false)) {
      throw DioException(
          requestOptions: options, error: const FormatException('网关返回 HTML'));
    }
    final override = options.extra[DiomanNormalize.pluginName];
    if (enabled &&
        !(override is DiomanNormalizeOptions && override.enabled == false) &&
        body.statusCode < 400 &&
        obj(data)[tkCode] is int &&
        obj(data)[tkCode] != 0) {
      throw DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
              requestOptions: options,
              statusCode: body.statusCode,
              data: data,
              headers: Headers.fromMap(body.headers)),
          error: DiomanException(
              code: obj(data)[tkCode],
              message: '${obj(data)[tkMessage]}',
              data: data));
    }
    return data;
  }
}

/// classify 的测试辅助入口。
/// 把 dioman 错误归入契约类别。
String classify(Object error, {String? authTag, bool budgetExpired = false}) {
  if (budgetExpired) return tkTimeout;
  if (error is! DioException) return 'unknown:$error';
  if (error.type == DioExceptionType.cancel) return tkCanceled;
  if (authTag != null) return authTag;
  if ((error.message ?? tkEmpty).contains('[auth] session expired')) {
    return tkExpired;
  }
  if (error.error is DiomanBreakerOpenException) return 'breaker_open';
  if (error.error is DiomanOfflineException) return tkOffline;
  if (error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.sendTimeout) {
    return tkTimeout;
  }
  if (error.response != null) {
    final r = error.response!;
    if ((r.statusCode ?? 0) >= 400) return 'http:${r.statusCode}';
    final code = obj(r.data)[tkCode];
    if (code != null) return 'business:$code';
    if (error.error is DiomanException) {
      return 'business:${(error.error as DiomanException).code}';
    }
  }
  if (error.error is FormatException) return 'parse';
  if (error.error is SocketException ||
      error.error is HttpException ||
      error.type == DioExceptionType.connectionError) {
    return tkNetwork;
  }
  if ((error.message ?? tkEmpty).contains(tkRefreshFailed)) return tkExpired;
  if ((error.message ?? tkEmpty).contains('no token')) return tkUnauthenticated;
  return 'unknown:$error';
}

/// 封装 ScenarioClient 测试夹具。
/// 场景客户端及其原始回调记录。
class ScenarioClient {
  /// 构造独立测试实例。
  /// 按中立配置创建 io 客户端。
  ScenarioClient(this.config, this.run, String base, this.style)
      : dio = ioClient(base,
            budget: obj(config[tkClient])['base_timeout_ms'] as int? ??
                defaultBudget) {
    final p = obj(obj(config[tkClient])[tkPlugins]);
    plugins = p;
    for (final entry in p.entries) {
      final allowed = pluginFields[entry.key];
      if (allowed == null) throw StateError('插件 ${entry.key} 未映射');
      for (final k in obj(entry.value).keys) {
        if (!allowed.contains(k)) throw StateError('插件 ${entry.key}.$k 未映射');
      }
    }
    final auth = obj(p[tkAuth]);
    if (auth[tkRefresh] != null && auth[tkRefresh] != 'endpoint') {
      throw StateError('auth.refresh 只支持 endpoint');
    }
    final key = obj(p[tkKey]);
    if (key[tkScope] != null && key[tkScope] != tkUser) {
      throw StateError('key.scope 只支持 user');
    }
    final retry = obj(p[tkRetry]);
    final timeout = obj(p[tkTimeout]);
    final cache = obj(p[tkCache]);
    final loading = obj(p[tkLoading]);
    final breaker = obj(p[tkBreaker]);
    dio.transformer = EnvelopeTransformer(
        p.containsKey(tkNormalize) || p.containsKey(tkAuth));
    // 总预算取消在进入插件错误链前还原为超时，避免熔断器把它当用户取消。
    dio.interceptors.add(InterceptorsWrapper(onError: (error, handler) {
      if (error.requestOptions.extra[tkAcceptBudgetExpired] == true) {
        handler.next(error.copyWith(type: DioExceptionType.receiveTimeout));
      } else {
        handler.next(error);
      }
    }));
    handle = Dioman.install(
      dio,
      envs: p.containsKey(tkEnvs) ? DiomanEnvs([]) : null,
      timeout: p.containsKey(tkTimeout)
          ? DiomanTimeout(probe: () => NetworkQuality.excellent, timeouts: {
              NetworkQuality.excellent: DiomanTimeouts(
                  connect: timeout[tkConnectMs] == null
                      ? null
                      : ms(timeout[tkConnectMs] as num),
                  receive: timeout[tkReceiveMs] == null
                      ? null
                      : ms(timeout[tkReceiveMs] as num))
            })
          : null,
      repath: p.containsKey(tkRepath) ? DiomanRepath() : null,
      filter: p.containsKey(tkFilter) ? const DiomanFilter() : null,
      key: p.containsKey(tkKey)
          ? DiomanKey(
              enabled: false,
              namespace: key[tkScope] == tkUser ? () => tokens.user : null)
          : null,
      cache: p.containsKey(tkCache)
          ? DiomanCache(
              persist: MemoryPersist(),
              cachePolicy: DiomanCachePolicy.memo,
              expires: cache[tkTtlMs] as int? ?? 60000,
              maxEntries: cache[tkMax] as int? ?? 500,
              shouldCache: (o) =>
                  (cache[tkMethods] as List? ?? [tkGET]).contains(o.method))
          : null,
      offline: p.containsKey(tkOffline)
          ? DiomanOffline(
              isOnline: () => online,
              onConnectivityChanged: connectivity.stream,
              maxQueueSize: 50,
              maxWait: Duration.zero)
          : null,
      share: p.containsKey(tkShare)
          ? DiomanShare(policy: policy(obj(p[tkShare])[tkPolicy]))
          : null,
      mock: p.containsKey(tkMock)
          ? DiomanMock(
              enabled: true,
              mockUrl: '$base/t/mock',
              fallbackWhen: ({response, error}) =>
                  obj(p[tkMock])[tkFallbackOn404] != false &&
                  (response ?? error?.response)?.statusCode == 404)
          : null,
      cancel: p.containsKey(tkCancel) ? DiomanCancel() : null,
      loading: p.containsKey(tkLoading)
          ? DiomanLoading(
              onChanged: loadingEvents.add,
              delay: ms(loading[tkDelayMs] as num? ?? 0),
              delayClose: ms(loading[tkDelayCloseMs] as num? ?? 0))
          : null,
      auth: p.containsKey(tkAuth)
          ? DiomanAuth(
              tokenManager: tokens,
              buildHeader: (t) => t,
              isProtected: (o) => o.uri.path
                  .startsWith(auth[tkUrlPattern] as String? ?? privatePath),
              onRefresh: (_, r) async {
                refreshCount++;
                final d = ioClient(dio.options.baseUrl);
                try {
                  final response = await d.post<dynamic>(refreshPath,
                      data: {tkRefreshToken: tokens.refresh},
                      queryParameters: obj(auth[tkRefreshQuery]),
                      options: Options(headers: headers));
                  if (logical(response) >= 400) {
                    throw StateError(tkRefreshFailed);
                  }
                  tokens.accept(obj(obj(response.data)[tkData]));
                } finally {
                  d.close(force: true);
                }
              },
              onAccessExpired: (_, r) async {
                expiredCount++;
                tags['${r.requestOptions.extra[tkAcceptId]}'] = tkExpired;
              },
              onAccessDenied: (_, r) async {
                final synthetic = r.statusCode == 0;
                if (!synthetic) deniedCount++;
                tags['${r.requestOptions.extra[tkAcceptId]}'] =
                    synthetic ? tkUnauthenticated : tkDenied;
              },
              onFailure: (_, r) {
                final status = logical(r);
                if (status == 403) return DiomanAuthFailureAction.deny;
                if (status != 401) return DiomanAuthFailureAction.others;
                if (!tokens.canRefresh) return DiomanAuthFailureAction.expired;
                return defaultAuthFailure(
                    tokens,
                    Response<dynamic>(
                        requestOptions: r.requestOptions,
                        statusCode: 401,
                        data: r.data),
                    tkAuthorization);
              })
          : null,
      retry: p.containsKey(tkRetry)
          ? DiomanRetry(
              max: retry[tkMax] as int? ?? 0,
              methods:
                  List<String>.from(retry[tkMethods] as List? ?? retryMethods),
              delay: (_, __, ___, ____) => ms(retry[tkDelayMs] as num? ?? 0),
              shouldRetry: (e, r) => shouldRetry(e, r, retry),
              respectRetryAfter: retry[tkRespectRetryAfter] as bool? ?? true,
              afterStatusCodes: [200, 413, 429, 503])
          : null,
      breaker: p.containsKey(tkBreaker)
          ? DiomanBreaker(
              failureThreshold: breaker[tkThreshold] as int? ?? 3,
              resetDuration: ms(breaker[tkOpenMs] as num? ?? 1000),
              shouldTrip: (r, e) =>
                  logical(r ?? e?.response) >= 500 ||
                  (r == null && e?.response == null))
          : null,
      log: p.containsKey(tkLog)
          ? DiomanLog(writer: (message, {error}) => logs.add(message))
          : null,
      normalize: p.containsKey(tkNormalize) ? const DiomanNormalize() : null,
      plugins: [
        if (p.containsKey(tkNotify))
          DiomanNotify<dynamic>(
              notify: notices.add,
              stringify: (data, message, status, o) =>
                  o.extra[tkAcceptSilent] == true ||
                          o.cancelToken?.isCancelled == true
                      ? tkEmpty
                      : status >= 400 ||
                              (obj(data)[tkCode] is int &&
                                  obj(data)[tkCode] != 0) ||
                              status == 0
                          ? (message.isEmpty ? 'request failed' : message)
                          : tkEmpty)
      ],
    );
  }

  /// 场景原始配置。
  final Map<String, dynamic> config;

  /// 本轮唯一隔离标识。
  final String run;

  /// 当前风格。
  String style;

  /// 被测 Dio。
  final Dio dio;

  /// 插件句柄。
  late final DiomanHandle handle;

  /// 插件配置。
  late final Map<String, dynamic> plugins;

  /// 令牌端口。
  final tokens = Tokens();

  /// 连通性事件源。
  final connectivity = StreamController<bool>.broadcast();

  /// 最近探测状态。
  bool online = true;

  /// loading 原始事件。
  final loadingEvents = <bool>[];

  /// 通知原始文本。
  final notices = <String>[];

  /// 日志原文。
  final logs = <String>[];

  /// 按请求记录鉴权类别。
  final tags = <String, String>{};

  /// 实际刷新次数。
  int refreshCount = 0;

  /// 过期回调次数。
  int expiredCount = 0;

  /// 越权回调次数。
  int deniedCount = 0;

  /// headers 的测试实现。
  /// 场景隔离与风格请求头。
  Map<String, dynamic> get headers => {runHeader: run, styleHeader: style};

  /// policy 的测试实现。
  /// 解析去重策略，拒绝未知值。
  static DiomanSharePolicy policy(dynamic value) =>
      DiomanSharePolicy.values.firstWhere((p) => p.name == (value ?? 'start'),
          orElse: () => throw StateError('share.policy 未映射: $value'));

  /// shouldRetry 的测试实现。
  /// 重试只允许中立状态和网络、超时错误。
  bool shouldRetry(DioException? e, Response<dynamic>? response,
      Map<String, dynamic> options) {
    final r = response ?? e?.response;
    if (r != null) {
      return (options[tkStatuses] as List? ?? retryStatuses)
          .contains(logical(r));
    }
    return e != null && [tkNetwork, tkTimeout].contains(classify(e));
  }

  /// extras 的测试实现。
  /// 把请求级配置逐项映射到公开选项对象。
  Map<String, dynamic> extras(Map<String, dynamic> o, String id) {
    const allowed = {
      tkAuth,
      tkCache,
      tkRetry,
      tkShare,
      tkLoading,
      tkSilent,
      tkTimeoutMs,
      tkKey,
      tkMock,
      tkNormalize,
      tkBreaker,
      tkFilter
    };
    for (final k in o.keys) {
      if (!allowed.contains(k)) throw StateError('请求选项 $k 未映射');
    }
    if (o.containsKey(tkFilter) && o[tkFilter] is! bool) {
      throw StateError('请求选项 filter 必须是布尔值: ${o[tkFilter]}');
    }
    final key = o[tkKey];
    final c = obj(o[tkCache]);
    final r = {...obj(plugins[tkRetry]), ...obj(o[tkRetry])};
    for (final k in c.keys) {
      if (!{tkTtlMs, tkKey}.contains(k)) throw StateError('cache.$k 未映射');
    }
    for (final k in r.keys) {
      if (!pluginFields[tkRetry]!.contains(k)) throw StateError('retry.$k 未映射');
    }
    return {
      tkAcceptId: id,
      tkAcceptSilent: o[tkSilent] == true,
      DiomanAuth.pluginName: DiomanAuthOptions(enabled: o[tkAuth] as bool?),
      DiomanKey.pluginName: DiomanKeyOptions(
          enabled: c[tkKey] != null || key != null && key != false,
          key: c[tkKey] as String? ??
              (key is String && !{'deep', tkSimple}.contains(key) ? key : null),
          fastMode: key == tkSimple),
      DiomanCache.pluginName: DiomanCacheOptions(
          enabled: o[tkCache] != false, expires: c[tkTtlMs] as int?),
      DiomanShare.pluginName: DiomanShareOptions(
          enabled: o[tkShare] != false && o[tkShare] != tkNone,
          policy: o[tkShare] is String ? policy(o[tkShare]) : null),
      DiomanLoading.pluginName:
          DiomanLoadingOptions(enabled: o[tkLoading] as bool?),
      DiomanRetry.pluginName: DiomanRetryOptions(
          enabled: o[tkRetry] != false,
          max: o[tkRetry] is num
              ? (o[tkRetry] as num).toInt()
              : r[tkMax] as int?,
          methods: r[tkMethods] == null
              ? null
              : List<String>.from(r[tkMethods] as List),
          delay: r[tkDelayMs] == null
              ? null
              : (_, __, ___, ____) => ms(r[tkDelayMs] as num),
          shouldRetry: (e, response) => shouldRetry(e, response, r),
          respectRetryAfter: r[tkRespectRetryAfter] as bool?),
      DiomanMock.pluginName: DiomanMockOptions(enabled: o[tkMock] as bool?),
      DiomanNormalize.pluginName:
          DiomanNormalizeOptions(enabled: o[tkNormalize] as bool?),
      DiomanBreaker.pluginName:
          DiomanBreakerOptions(enabled: o[tkBreaker] as bool?),
      // testkit D19：只有请求级 filter: true 才过滤；DiomanFilter 装上默认开启，
      // 所以缺省与 false 都要显式关掉，client.plugins.filter 只代表装配。
      DiomanFilter.pluginName:
          DiomanFilterOptions(enabled: o[tkFilter] == true),
    };
  }

  /// dispose 的测试实现。
  /// 释放全部客户端资源。
  Future<void> dispose() async {
    handle.dispose();
    dio.close(force: true);
    await connectivity.close();
  }
}
