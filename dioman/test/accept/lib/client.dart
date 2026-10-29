import 'literals.dart';
import 'dart:async';
import 'dart:convert';
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

  /// 写入刷新后的原始凭证。
  @override
  void setTokens({required String accessToken, String? refreshToken}) =>
      replace(accessToken, refreshToken);

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

/// 只读库返回的类别、原因和逻辑状态，不重复判定业务信封。
String classify(Object error) {
  if (error is! DiomanResponse) return 'unknown:$error';
  return switch (error.kind) {
    DiomanKind.ok => tkOk,
    DiomanKind.http => 'http:${error.status}',
    DiomanKind.biz => 'business:${error.status}',
    DiomanKind.network => tkNetwork,
    DiomanKind.timeout => tkTimeout,
    DiomanKind.cancel => tkCanceled,
    DiomanKind.parse => 'parse',
    DiomanKind.auth => error.reason ?? tkExpired,
    DiomanKind.breaker => 'breaker_open',
    DiomanKind.offline => tkOffline,
    DiomanKind.internal => 'internal',
  };
}

/// 中立场景到公开配置的映射；库独立承担归一化、取消和插件决策。
class ScenarioClient {
  /// 构造被测客户端，真实传输可由连接池场景共享。
  ScenarioClient(this.config, this.run, String base, this.style,
      {HttpClientAdapter? transport})
      : dio = ioClient(base,
            budget: obj(config[tkClient])['base_timeout_ms'] as int? ??
                defaultBudget) {
    plugins = obj(obj(config[tkClient])[tkPlugins]);
    for (final entry in plugins.entries) {
      final allowed = pluginFields[entry.key];
      if (allowed == null) throw StateError('插件 ${entry.key} 未映射');
      for (final key in obj(entry.value).keys) {
        if (!allowed.contains(key)) {
          throw StateError('插件 ${entry.key}.$key 未映射');
        }
      }
    }
    if (transport != null) dio.httpClientAdapter = transport;
    final auth = obj(plugins[tkAuth]);
    final cache = obj(plugins[tkCache]);
    final retry = obj(plugins[tkRetry]);
    final timeout = obj(plugins[tkTimeout]);
    final breaker = obj(plugins[tkBreaker]);
    final loading = obj(plugins[tkLoading]);
    final key = obj(plugins[tkKey]);
    if (auth[tkRefresh] != null && auth[tkRefresh] != 'endpoint') {
      throw StateError('auth.refresh 只支持 endpoint');
    }
    if (key[tkScope] != null && key[tkScope] != tkUser) {
      throw StateError('key.scope 只支持 user');
    }
    api = Dioman<DiomanResponse<dynamic>>(
      dio: dio,
      // 只读库已分类的逻辑状态；服务停止守卫不重分类、不改结果。
      response: DiomanResponseFactory(create: (result) {
        checkServiceStatus(result.status, data: result.data);
        return result;
      }),
      key: DiomanKeyOptions(
          namespace: key[tkScope] == tkUser ? () => tokens.user : null),
      debug: plugins.containsKey(tkLog) ? logs.add : false,
      plugins: [
        if (plugins.containsKey(tkEnvs)) const DiomanEnvs([]),
        if (plugins.containsKey(tkTimeout))
          DiomanTimeout(probe: () => NetworkQuality.excellent, timeouts: {
            NetworkQuality.excellent: DiomanTimeouts(
                connect: timeout[tkConnectMs] == null
                    ? null
                    : ms(timeout[tkConnectMs] as num),
                send: timeout[tkSendMs] == null
                    ? null
                    : ms(timeout[tkSendMs] as num),
                receive: timeout[tkReceiveMs] == null
                    ? null
                    : ms(timeout[tkReceiveMs] as num)),
          }),
        if (plugins.containsKey(tkRepath)) const DiomanRepath(),
        if (plugins.containsKey(tkFilter)) const DiomanFilter(),
        if (plugins.containsKey(tkCache))
          DiomanCache(
              persist: MemoryPersist(),
              expires: ms(cache[tkTtlMs] as num? ?? 60000),
              maxEntries: cache[tkMax] as int? ?? 500,
              shouldCache: (request) => (cache[tkMethods] as List? ?? [tkGET])
                  .contains(request.method)),
        if (plugins.containsKey(tkOffline))
          DiomanOffline(
              // 中立 probe 契约是探测失败即返回 offline，使用原生零等待预算。
              maxWait: Duration.zero,
              isOnline: () => online,
              onConnectivityChanged: connectivity.stream),
        if (plugins.containsKey(tkShare))
          DiomanShare(policy: policy(obj(plugins[tkShare])[tkPolicy])),
        if (plugins.containsKey(tkMock))
          DiomanMock(
              mockUrl: '$base/t/mock',
              fallbackWhen: obj(plugins[tkMock])[tkFallbackOn404] == false
                  ? (_) => false
                  : null),
        if (plugins.containsKey(tkLoading))
          DiomanLoading(
              onChanged: loadingEvents.add,
              delay: ms(loading[tkDelayMs] as num? ?? 0),
              delayClose: ms(loading[tkDelayCloseMs] as num? ?? 0)),
        if (plugins.containsKey(tkAuth))
          DiomanAuth(
              tokenManager: tokens,
              buildHeader: (token) => token,
              isProtected: (request) => request.uri.path
                  .startsWith(auth[tkUrlPattern] as String? ?? privatePath),
              onRefresh: (_, result) async {
                // 刷新凭证由使用者回调管理；缺凭证时直接报告刷新失败，不发空请求。
                if (tokens.refresh == null || tokens.refresh!.isEmpty) {
                  throw StateError('没有刷新凭证');
                }
                refreshCount++;
                final refreshApi = Dioman(dio: ioClient(dio.options.baseUrl));
                try {
                  final data = await refreshApi.post<Map<String, dynamic>>(
                      refreshPath,
                      data: {tkRefreshToken: tokens.refresh},
                      query: obj(auth[tkRefreshQuery]),
                      call: DiomanCall(headers: headers));
                  tokens.accept(data);
                } finally {
                  refreshApi.dispose();
                  refreshApi.dio.close(force: true);
                }
              },
              onAccessExpired: (_, __) => expiredCount++,
              onAccessDenied: (_, __) => deniedCount++),
        if (plugins.containsKey(tkRetry))
          DiomanRetry(
              max: retry[tkMax] as int? ?? 0,
              methods:
                  List<String>.from(retry[tkMethods] as List? ?? retryMethods),
              delay: (_, __, ___) => ms(retry[tkDelayMs] as num? ?? 0),
              statusCodes:
                  List<int>.from(retry[tkStatuses] as List? ?? retryStatuses),
              respectRetryAfter: retry[tkRespectRetryAfter] as bool? ?? true),
        if (plugins.containsKey(tkBreaker))
          DiomanBreaker(
              failureThreshold: breaker[tkThreshold] as int? ?? 3,
              resetDuration: ms(breaker[tkOpenMs] as num? ?? 1000)),
        if (plugins.containsKey(tkNotify))
          DiomanNotify(notify: (message, _) => notices.add(message)),
      ],
    );
  }

  /// 原始场景配置。
  final Map<String, dynamic> config;

  /// 本轮隔离标识。
  final String run;

  /// 当前响应风格。
  String style;

  /// 真实传输宿主。
  final Dio dio;

  /// 被测洋葱客户端。
  late final Dioman<DiomanResponse<dynamic>> api;

  /// 原始插件配置。
  late final Map<String, dynamic> plugins;

  /// 凭证存储。
  final tokens = Tokens();

  /// 连通事件端口。
  final connectivity = StreamController<bool>.broadcast();

  /// 宿主观测的连通状态。
  bool online = true;

  /// loading 原始事件。
  final loadingEvents = <bool>[];

  /// 通知原文。
  final notices = <String>[];

  /// debug 原文。
  final logs = <String>[];

  /// 刷新次数。
  int refreshCount = 0;

  /// 会话过期通知次数。
  int expiredCount = 0;

  /// 拒绝通知次数。
  int deniedCount = 0;

  /// 隔离请求头。
  Map<String, dynamic> get headers => {runHeader: run, styleHeader: style};

  /// 解析策略，拒绝未知值。
  static DiomanSharePolicy policy(dynamic value) =>
      DiomanSharePolicy.values.firstWhere((p) => p.name == (value ?? 'start'),
          orElse: () => throw StateError('share.policy 未映射: $value'));

  /// 将请求配置映射到类型化键，不用 extra 携带运行状态。
  DiomanCall call(Map<String, dynamic> options,
      {CancelToken? token, Map<String, dynamic>? headers}) {
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
    for (final key in options.keys) {
      if (!allowed.contains(key)) throw StateError('请求选项 $key 未映射');
    }
    if (options.containsKey(tkFilter) && options[tkFilter] is! bool) {
      throw StateError('请求选项 filter 必须是布尔值');
    }
    final cache = obj(options[tkCache]);
    final retry = obj(options[tkRetry]);
    for (final key in cache.keys) {
      if (!{tkTtlMs, tkKey}.contains(key)) throw StateError('cache.$key 未映射');
    }
    for (final key in retry.keys) {
      if (!pluginFields[tkRetry]!.contains(key)) {
        throw StateError('retry.$key 未映射');
      }
    }
    final key = cache[tkKey] ??
        options[tkKey] ??
        (plugins.containsKey(tkKey) ? false : null);
    return DiomanCall(
        headers: {...this.headers, ...?headers},
        cancelToken: token,
        key: key == tkSimple
            ? const DiomanKeyOptions(fastMode: true)
            : key == 'deep' || key == true
                ? null
                : key,
        envelope: options[tkNormalize] as bool?,
        silent: options[tkSilent] == true,
        receiveTimeout: options[tkTimeoutMs] == null
            ? null
            : ms(options[tkTimeoutMs] as num),
        options: {
          DiomanAuth.option: options[tkAuth] == true
              ? const DiomanAuthOptions(enabled: true)
              : options[tkAuth],
          DiomanCache.option: options[tkCache] == false
              ? false
              : options[tkCache] == null
                  ? true
                  : DiomanCacheOptions(
                      expires: cache[tkTtlMs] == null
                          ? null
                          : ms(cache[tkTtlMs] as num)),
          DiomanShare.option: options[tkShare] == tkNone
              ? false
              : options[tkShare] is String
                  ? DiomanShareOptions(policy: policy(options[tkShare]))
                  : options[tkShare] ?? true,
          DiomanLoading.option: options[tkLoading],
          DiomanRetry.option: options[tkRetry] == false
              ? false
              : DiomanRetryOptions(
                  max: options[tkRetry] is num
                      ? (options[tkRetry] as num).toInt()
                      : retry[tkMax] as int?,
                  methods: retry[tkMethods] == null
                      ? null
                      : List<String>.from(retry[tkMethods] as List),
                  delay: retry[tkDelayMs] == null
                      ? null
                      : (_, __, ___) => ms(retry[tkDelayMs] as num),
                  statusCodes: retry[tkStatuses] == null
                      ? null
                      : List<int>.from(retry[tkStatuses] as List),
                  respectRetryAfter: retry[tkRespectRetryAfter] as bool?),
          DiomanMock.option: options[tkMock],
          DiomanBreaker.option: options[tkBreaker],
          DiomanFilter.option: options[tkFilter] == true,
        });
  }

  /// 释放客户端和宿主端口。
  Future<void> dispose() async {
    api.dispose();
    dio.close(force: true);
    await connectivity.close();
  }
}
