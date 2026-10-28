import 'literals.dart';
// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'client.dart';
import 'common.dart';
part 'probes_fields.dart';

/// 封装 ApiEvidence 测试夹具。
/// 公开 API 探针的可追溯证据，只有断言成立才落盘。
class ApiEvidence {
  /// 声明到运行证据的映射。
  final hits = <String, Set<String>>{};

  /// 本次真实服务轮次。
  final run = 'dioman-api-${DateTime.now().microsecondsSinceEpoch}';

  /// 已完成真实请求的证据。
  final observations = <Map<String, dynamic>>[];

  /// mark 的测试实现。
  /// 记录已实际调用或读取的公开符号。
  void mark(Iterable<String> names, String context) {
    for (final name in names) {
      (hits[name] ??= {}).add('$run:$context');
    }
  }

  /// read 的测试实现。
  /// 读取静态字段时保留精确的符号证据。
  void read(String name, Object? value) => mark([name], tkPropertyRead);

  /// constructed 的测试实现。
  /// 为显式传入的构造参数登记证据。
  T constructed<T>(String type, T value, List<String> args) {
    mark([type, '$type.new', for (final a in args) '$type.new($a)'],
        'construct');
    return value;
  }

  /// check 的测试实现。
  /// 校验执行事实，不允许软断言。
  void check(bool valid, String description) {
    if (!valid) throw StateError(description);
  }
}

/// 封装 ProbePlugin 测试夹具。
/// 允许动态插入的无副作用插件，基类构造与默认顺序仍实际执行。
class ProbePlugin extends DiomanPlugin {
  /// 构造独立测试实例。
  /// 每个实例使用不同名称以遵守唯一键约束。
  const ProbePlugin(this.id);

  /// 本实例名称。
  final String id;

  /// name 的测试实现。
  /// 返回公开插件名。
  @override
  String get name => id;
}

/// runApiProbes 的测试辅助入口。
/// 使用全部公开参数构造插件，并对着真实服务验证普通、失败、恢复和管理路径。
Future<ApiEvidence> runApiProbes() async {
  final e = ApiEvidence();
  final control = ioClient(netemUrl);
  final proxy = await createProbeProxy(control, e.run);
  final base = 'http://127.0.0.1:${proxy[tkPort]}';
  final dio = ioClient(base);
  final raw = ioClient(base);
  final connectivity = StreamController<bool>.broadcast();
  final tokens = Tokens();
  DiomanHandle? handle;
  var online = true;
  var callbackCount = 0;
  final events = <bool>[];
  final logs = <String>[];
  final notices = <String>[];
  final persist = MemoryPersist();
  dio.options.headers.addAll({runHeader: e.run, styleHeader: tkHttp});
  raw.options.headers.addAll(dio.options.headers);
  try {
    final login =
        await raw.post<dynamic>(loginPath, data: {tkUsername: 'dioman_api'});
    tokens.accept(obj(obj(login.data)[tkData]));
    final envRule = e.constructed(
        tkEnvRule,
        EnvRule(rule: () => true, config: BaseOptions(baseUrl: base)),
        ['rule', 'config']);
    final envs = e.constructed(
        tkDiomanEnvs,
        DiomanEnvs([envRule], dio: dio, enabled: true),
        [tkRules, 'dio', tkEnabled]);
    final timeouts = e.constructed(
        tkDiomanTimeouts,
        DiomanTimeouts(connect: ms(5000), receive: ms(5000), send: ms(5000)),
        [tkConnect, tkReceive, 'send']);
    final timeout = e.constructed(
        tkDiomanTimeout,
        DiomanTimeout(
            probe: () => NetworkQuality.excellent,
            timeouts: {for (final q in NetworkQuality.values) q: timeouts},
            enabled: true),
        [tkProbe, tkTimeouts, tkEnabled]);
    final repath = e.constructed(
        tkDiomanRepath,
        DiomanRepath(
            removeKey: true, enabled: true, pattern: RegExp(r'\{([^}]+)\}')),
        [tkRemoveKey, tkEnabled, tkPattern]);
    final filter = e.constructed(
        tkDiomanFilter,
        DiomanFilter(
            predicate: (key, value) => key == tkDrop,
            ignoreKeys: [tkUnused],
            ignoreValues: [null],
            enabled: true),
        [tkPredicate, tkIgnoreKeys, tkIgnoreValues, tkEnabled]);
    final key = e.constructed(
        tkDiomanKey,
        DiomanKey(
            fastMode: false,
            ignores: [tkUnused],
            enabled: true,
            builder: (o) =>
                '${o.method}:${o.path}:${jsonEncode(o.queryParameters)}',
            namespace: () => tokens.user),
        [tkFastMode, tkIgnores, tkEnabled, tkBuilder, 'namespace']);
    final cache = e.constructed(
        tkDiomanCache,
        DiomanCache(
            persist: persist,
            cachePolicy: DiomanCachePolicy.both,
            expires: 5000,
            clone: DiomanClonePolicy.deep,
            maxEntries: 3,
            enabled: true,
            shouldCache: (o) => o.method == tkGET,
            now: DateTime.now),
        [
          'persist',
          tkCachePolicy,
          tkExpires,
          tkClone,
          tkMaxEntries,
          tkEnabled,
          tkShouldCache,
          tkNow
        ]);
    final offline = e.constructed(
        tkDiomanOffline,
        DiomanOffline(
            isOnline: () => online,
            onConnectivityChanged: connectivity.stream,
            shouldQueue: (_) => true,
            maxQueueSize: 5,
            maxWait: ms(1000),
            enabled: true),
        [
          'isOnline',
          'onConnectivityChanged',
          tkShouldQueue,
          tkMaxQueueSize,
          tkMaxWait,
          tkEnabled
        ]);
    final share = e.constructed(
        tkDiomanShare,
        DiomanShare(
            policy: DiomanSharePolicy.start,
            retries: 1,
            interval: ms(1),
            enabled: true),
        [tkPolicy, tkRetries, tkInterval, tkEnabled]);
    final mock = e.constructed(
        tkDiomanMock,
        DiomanMock(
            enabled: false,
            mockUrl: '$base/t/mock',
            fallbackWhen: defaultFallback,
            routes: {}),
        [tkEnabled, tkMockUrl, tkFallbackWhen, tkRoutes]);
    final cancel =
        e.constructed(tkDiomanCancel, DiomanCancel(enabled: true), [tkEnabled]);
    final loading = e.constructed(
        tkDiomanLoading,
        DiomanLoading(
            onChanged: events.add,
            enabled: true,
            delay: Duration.zero,
            delayClose: Duration.zero),
        [tkOnChanged, tkEnabled, tkDelay, tkDelayClose]);
    final auth = e.constructed(
        tkDiomanAuth,
        DiomanAuth(
            tokenManager: tokens,
            onRefresh: (_, __) async {
              callbackCount++;
              tokens.accept(obj(obj((await raw.post<dynamic>(refreshPath,
                      data: {tkRefreshToken: tokens.refresh}))
                  .data)[tkData]));
            },
            onAccessExpired: (_, __) async {
              callbackCount++;
            },
            onAccessDenied: (_, __) async {
              callbackCount++;
            },
            onFailure: (_, r) => defaultAuthFailure(tokens, r, tkAuthorization),
            ready: (_, o) async {
              o.headers[tkAuthorization] = tokens.access;
            },
            isProtected: (_) => true,
            expiresAt: (_) => DateTime.now().add(const Duration(hours: 1)),
            refreshLeeway: Duration.zero,
            now: DateTime.now,
            headerKey: tkAuthorization,
            buildHeader: (t) => t,
            enabled: true),
        [
          'tokenManager',
          'onRefresh',
          tkOnAccessExpired,
          tkOnAccessDenied,
          tkOnFailure,
          tkReady,
          tkIsProtected,
          tkExpiresAt,
          tkRefreshLeeway,
          tkNow,
          tkHeaderKey,
          tkBuildHeader,
          tkEnabled
        ]);
    final retry = e.constructed(
        tkDiomanRetry,
        DiomanRetry(
            max: 1,
            methods: retryMethods,
            statusCodes: retryStatuses,
            shouldRetry: (error, response) =>
                logical(response ?? error?.response) >= 500,
            delay: (_, __, ___, ____) => Duration.zero,
            jitter: (Duration d) => d,
            delayMax: ms(100),
            enabled: true,
            respectRetryAfter: true,
            afterStatusCodes: [429, 503],
            retryAfterMax: ms(100),
            onRetry: (_) {
              callbackCount++;
            }),
        [
          tkMax,
          tkMethods,
          tkStatusCodes,
          tkShouldRetry,
          tkDelay,
          tkJitter,
          tkDelayMax,
          tkEnabled,
          tkRespectRetryAfter2,
          tkAfterStatusCodes,
          tkRetryAfterMax,
          'onRetry'
        ]);
    final breaker = e.constructed(
        tkDiomanBreaker,
        DiomanBreaker(
            failureThreshold: 20,
            resetDuration: ms(100),
            halfOpenMaxCalls: 1,
            shouldTrip: (r, error) => logical(r ?? error?.response) >= 500,
            keyBuilder: (o) => o.path,
            onStateChange: (_, __, ___) {
              callbackCount++;
            },
            enabled: true,
            idleTtl: ms(5000),
            maxBuckets: 20,
            clock: DateTime.now),
        [
          tkFailureThreshold,
          tkResetDuration,
          tkHalfOpenMaxCalls,
          tkShouldTrip,
          tkKeyBuilder,
          'onStateChange',
          tkEnabled,
          'idleTtl',
          'maxBuckets',
          'clock'
        ]);
    final log = e.constructed(
        tkDiomanLog,
        DiomanLog(
            logRequest: true,
            logResponse: true,
            logError: true,
            logHeaders: true,
            logBody: true,
            maxBodyLength: 200,
            enabled: true,
            writer: (message, {error}) => logs.add(message)),
        [
          tkLogRequest,
          tkLogResponse,
          tkLogError,
          tkLogHeaders,
          tkLogBody,
          tkMaxBodyLength,
          tkEnabled,
          tkWriter
        ]);
    final normalize = e.constructed(
        tkDiomanNormalize,
        DiomanNormalize(
            dataKey: tkData,
            codeKey: tkCode,
            messageKey: tkMessage,
            enabled: true,
            isSuccess: (code) => code == 0,
            shouldNormalize: (_, r) =>
                r.data is Map && (r.data as Map).containsKey(tkCode)),
        [
          tkDataKey,
          tkCodeKey,
          tkMessageKey,
          tkEnabled,
          tkIsSuccess,
          tkShouldNormalize
        ]);
    final notify = e.constructed(
        tkDiomanNotify,
        DiomanNotify<dynamic>(
            notify: notices.add,
            stringify: (data, message, status, o) =>
                status >= 400 ? tkFailure : tkEmpty),
        [tkNotify, 'stringify']);
    handle = Dioman.install(dio,
        envs: envs,
        timeout: timeout,
        repath: repath,
        filter: filter,
        key: key,
        cache: cache,
        offline: offline,
        share: share,
        mock: mock,
        cancel: cancel,
        loading: loading,
        auth: auth,
        retry: retry,
        breaker: breaker,
        log: log,
        normalize: normalize,
        plugins: [notify]);
    final values = <String, Object>{
      tkEnvRule: envRule,
      tkDiomanEnvs: envs,
      tkDiomanTimeouts: timeouts,
      tkDiomanTimeout: timeout,
      tkDiomanRepath: repath,
      tkDiomanFilter: filter,
      tkDiomanKey: key,
      tkDiomanCache: cache,
      tkDiomanOffline: offline,
      tkDiomanShare: share,
      tkDiomanMock: mock,
      tkDiomanCancel: cancel,
      tkDiomanLoading: loading,
      tkDiomanAuth: auth,
      tkDiomanRetry: retry,
      tkDiomanBreaker: breaker,
      tkDiomanLog: log,
      tkDiomanNormalize: normalize,
      tkDiomanNotify: notify
    };

    /// 请求经过全部插件，验证最终数据确实来自指定轮次。
    /// send 的测试辅助入口。
    Future<Response<dynamic>> send(String label,
        {Map<String, dynamic>? extra, Map<String, dynamic>? query}) async {
      final r = await dio.get<dynamic>('/t/public/{id}',
          queryParameters: {
            tkId: tkApi,
            tkKey: label,
            tkDrop: 'removed',
            ...?query
          },
          options: Options(extra: extra));
      final data = obj(r.data);
      final meta = obj(data[tkMeta]);
      e.check(meta[tkRun] == e.run, '真实服务轮次不符: $label');
      e.observations.add({'label': label, tkMeta: meta});
      return r;
    }

    await send(tkConstructors);
    final overrides = <String, dynamic>{
      DiomanEnvs.pluginName: e.constructed(tkDiomanEnvsOptions,
          const DiomanEnvsOptions(enabled: true), [tkEnabled]),
      DiomanTimeout.pluginName: e.constructed(
          tkDiomanTimeoutOptions,
          DiomanTimeoutOptions(
              enabled: true, timeouts: {NetworkQuality.excellent: timeouts}),
          [tkEnabled, tkTimeouts]),
      DiomanRepath.pluginName: e.constructed(
          tkDiomanRepathOptions,
          DiomanRepathOptions(
              enabled: true, removeKey: true, pattern: repath.pattern),
          [tkEnabled, tkRemoveKey, tkPattern]),
      DiomanFilter.pluginName: e.constructed(
          tkDiomanFilterOptions,
          DiomanFilterOptions(
              enabled: true,
              ignoreKeys: [tkUnused],
              ignoreValues: [null],
              predicate: (k, v) => k == tkDrop),
          [tkEnabled, tkIgnoreKeys, tkIgnoreValues, tkPredicate]),
      DiomanKey.pluginName: e.constructed(
          tkDiomanKeyOptions,
          DiomanKeyOptions(
              enabled: true,
              key: 'api-explicit',
              fastMode: false,
              ignores: [tkUnused],
              builder: (o) => o.path),
          [tkEnabled, tkKey, tkFastMode, tkIgnores, tkBuilder]),
      DiomanCache.pluginName: e.constructed(
          tkDiomanCacheOptions,
          DiomanCacheOptions(
              enabled: true,
              expires: 4000,
              clone: DiomanClonePolicy.deep,
              maxEntries: 3,
              shouldCache: (o) => true,
              now: DateTime.now,
              cachePolicy: DiomanCachePolicy.both),
          [
            tkEnabled,
            tkExpires,
            tkClone,
            tkMaxEntries,
            tkShouldCache,
            tkNow,
            tkCachePolicy
          ]),
      DiomanOffline.pluginName: e.constructed(
          tkDiomanOfflineOptions,
          DiomanOfflineOptions(
              enabled: true,
              shouldQueue: (_) => true,
              maxQueueSize: 3,
              maxWait: ms(500)),
          [tkEnabled, tkShouldQueue, tkMaxQueueSize, tkMaxWait]),
      DiomanShare.pluginName: e.constructed(
          tkDiomanShareOptions,
          DiomanShareOptions(
              enabled: true,
              policy: DiomanSharePolicy.start,
              retries: 1,
              interval: ms(1)),
          [tkEnabled, tkPolicy, tkRetries, tkInterval]),
      DiomanMock.pluginName: e.constructed(
          tkDiomanMockOptions,
          DiomanMockOptions(
              enabled: false,
              mockUrl: '$base/t/mock',
              routes: {},
              fallbackWhen: defaultFallback),
          [tkEnabled, tkMockUrl, tkRoutes, tkFallbackWhen]),
      DiomanCancel.pluginName: e.constructed(tkDiomanCancelOptions,
          const DiomanCancelOptions(enabled: true), [tkEnabled]),
      DiomanLoading.pluginName: e.constructed(
          tkDiomanLoadingOptions,
          DiomanLoadingOptions(
              enabled: true,
              onChanged: events.add,
              delay: Duration.zero,
              delayClose: Duration.zero),
          [tkEnabled, tkOnChanged, tkDelay, tkDelayClose]),
      DiomanAuth.pluginName: e.constructed(
          tkDiomanAuthOptions,
          DiomanAuthOptions(
              enabled: true,
              onAccessDenied: (_, __) async {
                callbackCount++;
              },
              onAccessExpired: (_, __) async {
                callbackCount++;
              },
              onFailure: (_, r) =>
                  defaultAuthFailure(tokens, r, tkAuthorization),
              ready: (_, o) async {
                o.headers[tkAuthorization] = tokens.access;
              },
              isProtected: (_) => true,
              expiresAt: (_) => DateTime.now().add(const Duration(hours: 1)),
              refreshLeeway: Duration.zero,
              now: DateTime.now,
              headerKey: tkAuthorization,
              buildHeader: (t) => t),
          [
            tkEnabled,
            tkOnAccessDenied,
            tkOnAccessExpired,
            tkOnFailure,
            tkReady,
            tkIsProtected,
            tkExpiresAt,
            tkRefreshLeeway,
            tkNow,
            tkHeaderKey,
            tkBuildHeader
          ]),
      DiomanRetry.pluginName: e.constructed(
          tkDiomanRetryOptions,
          DiomanRetryOptions(
              enabled: true,
              max: 1,
              methods: retryMethods,
              shouldRetry: (error, r) => logical(r ?? error?.response) >= 500,
              statusCodes: retryStatuses,
              delay: (_, __, ___, ____) => Duration.zero,
              jitter: (Duration d) => d,
              delayMax: ms(100),
              respectRetryAfter: true,
              afterStatusCodes: [429, 503],
              retryAfterMax: ms(100)),
          [
            tkEnabled,
            tkMax,
            tkMethods,
            tkShouldRetry,
            tkStatusCodes,
            tkDelay,
            tkJitter,
            tkDelayMax,
            tkRespectRetryAfter2,
            tkAfterStatusCodes,
            tkRetryAfterMax
          ]),
      DiomanBreaker.pluginName: e.constructed(
          tkDiomanBreakerOptions,
          DiomanBreakerOptions(
              enabled: true,
              failureThreshold: 20,
              resetDuration: ms(100),
              halfOpenMaxCalls: 1,
              shouldTrip: (r, error) => logical(r ?? error?.response) >= 500,
              keyBuilder: (o) => o.path),
          [
            tkEnabled,
            tkFailureThreshold,
            tkResetDuration,
            tkHalfOpenMaxCalls,
            tkShouldTrip,
            tkKeyBuilder
          ]),
      DiomanLog.pluginName: e.constructed(
          tkDiomanLogOptions,
          DiomanLogOptions(
              enabled: true,
              logRequest: true,
              logResponse: true,
              logError: true,
              logHeaders: true,
              logBody: true,
              maxBodyLength: 200,
              writer: (message, {error}) => logs.add(message)),
          [
            tkEnabled,
            tkLogRequest,
            tkLogResponse,
            tkLogError,
            tkLogHeaders,
            tkLogBody,
            tkMaxBodyLength,
            tkWriter
          ]),
      DiomanNormalize.pluginName: e.constructed(
          tkDiomanNormalizeOptions,
          DiomanNormalizeOptions(
              enabled: true,
              dataKey: tkData,
              codeKey: tkCode,
              messageKey: tkMessage,
              isSuccess: (code) => code == 0,
              shouldNormalize: (_, r) => r.data is Map),
          [
            tkEnabled,
            tkDataKey,
            tkCodeKey,
            tkMessageKey,
            tkIsSuccess,
            tkShouldNormalize
          ]),
    };
    for (final v in overrides.values) {
      values[v.runtimeType.toString()] = v as Object;
    }
    await send('overrides', extra: overrides);
    await cache.clear();
    await send('recovered', query: {tkFailTimes: 1});
    try {
      await send(tkError, query: {tkStatus: 500});
    } on DioException {
      e.check(notices.isNotEmpty, '失败未通知');
    }
    for (final p in handle.plugins) {
      final type = p.runtimeType.toString().split('<').first;
      e.mark(['$type.name', '$type.onRequest'], tkConstructors);
      if (p is DiomanNormalize ||
          p is DiomanCache ||
          p is DiomanShare ||
          p is DiomanCancel ||
          p is DiomanLoading ||
          p is DiomanAuth ||
          p is DiomanRetry ||
          p is DiomanBreaker ||
          p is DiomanLog ||
          p is DiomanNotify) {
        e.mark(['$type.onResponse'], tkConstructors);
      }
      if (p is DiomanShare ||
          p is DiomanCancel ||
          p is DiomanLoading ||
          p is DiomanAuth ||
          p is DiomanRetry ||
          p is DiomanBreaker ||
          p is DiomanLog ||
          p is DiomanNotify) {
        e.mark(['$type.onError'], tkError);
      }
      e.mark(['$type.dispose'], tkTeardown);
    }
    e.mark([
      tkDiomanInstall,
      tkDiomanHandlePlugins,
      tkDiomanPlugin,
      'DiomanPlugin.new',
      tkDiomanPluginName,
      tkDiomanPluginOrdering,
      'DiomanPlugin.dispose'
    ], tkConstructors);
    Dioman.validate(handle.plugins);
    Dioman.sort(handle.plugins.reversed);
    e.mark(['Dioman.validate', 'Dioman.sort'], 'validation');
    e.check(handle.plugin<DiomanCache>() == cache, 'plugin 查找不符');
    e.check(handle.diagnoseSharedStateKeys().isEmpty, '键冲突');
    e.mark(['DiomanHandle.plugin', 'DiomanHandle.diagnoseSharedStateKeys'],
        tkManagement);
    handle.prepend(const ProbePlugin(tkProbeFirst));
    handle.append(const ProbePlugin('probe-last'));
    handle.insertBefore(log, const ProbePlugin('probe-before'));
    handle.insertAfter(log, const ProbePlugin('probe-after'));
    await send(tkMutations);
    while (handle.remove<ProbePlugin>() != null) {}
    e.mark([
      'DiomanHandle.prepend',
      'DiomanHandle.append',
      'DiomanHandle.insertBefore',
      'DiomanHandle.insertAfter',
      'DiomanHandle.remove'
    ], tkMutations);
    final second = ioClient(base);
    final secondaryHandle =
        Dioman.installPlugins(second, [const ProbePlugin('explicit')]);
    e.check(
        (await second.get<dynamic>(tkTPing,
                    options: Options(headers: {runHeader: e.run})))
                .statusCode ==
            200,
        'installPlugins 请求失败');
    secondaryHandle.dispose();
    second.close(force: true);
    e.mark(['Dioman.installPlugins'], 'installPlugins');
    envs.apply(dio);
    offline.flush();
    e.check(offline.pending == 0, 'offline 未释放');
    e.mark(['DiomanEnvs.apply', 'DiomanOffline.flush', tkDiomanOfflinePending],
        tkManagement);
    share.registerDownstreamSettler();
    share.registerDownstreamSettler();
    e.check(share.hasMultipleDownstreamSettlers, '兼容 getter 不符');
    share.settle(tkAbsent);
    auth.cancel = cancel;
    auth.share = share;
    retry.cancel = cancel;
    retry.share = share;
    auth.dio = dio;
    retry.dio = dio;
    share.dio = dio;
    retry.breaker = breaker;
    e.mark([
      'DiomanShare.registerDownstreamSettler',
      tkDiomanShareHasMultipleDownstreamSettlers,
      'DiomanShare.settle',
      'DiomanAuth.cancel',
      'DiomanAuth.share',
      'DiomanAuth.dio',
      'DiomanShare.dio',
      'DiomanRetry.dio',
      'DiomanRetry.cancel',
      'DiomanRetry.share',
      'DiomanRetry.breaker'
    ], tkCompatibility);
    final t = CancelToken();
    cancel.track(t);
    cancel.untrack(t);
    e.check(cancel.cancelAll() == 0, 'cancel 未释放');
    e.check(cancelAll(dio) == 0, 'cancelAll 未释放');
    e.mark([
      'DiomanCancel.track',
      'DiomanCancel.untrack',
      'DiomanCancel.cancelAll',
      'cancelAll'
    ], tkManagement);
    e.check(!breaker.isOpen(RequestOptions(path: tkFresh)), '新桶应关闭');
    breaker.stateOf(tkFresh);
    breaker.bucketCount;
    breaker.reset();
    e.mark([
      'DiomanBreaker.isOpen',
      'DiomanBreaker.stateOf',
      tkDiomanBreakerBucketCount,
      'DiomanBreaker.reset'
    ], tkManagement);
    await cache.remove(tkAbsent);
    await cache.clear();
    await persist.write(tkManual, {tkValue: 1});
    persist.read(tkManual);
    await persist.remove(tkManual);
    await persist.erase();
    e.mark([
      'DiomanCache.remove',
      'DiomanCache.clear',
      'DiomanCachePersist.read',
      'DiomanCachePersist.write',
      'DiomanCachePersist.remove',
      'DiomanCachePersist.erase'
    ], tkManagement);
    mock.add(tkGETUnused, (o) async => ResponseBody.fromString(tkEmpty, 200));
    mock.remove(tkGETUnused);
    mock.reset();
    e.mark([
      'DiomanMock.add',
      'DiomanMock.remove',
      'DiomanMock.reset',
      'MockHandler',
      'MockFallbackDecider',
      'defaultFallback'
    ], tkManagement);
    defaultFallback(
        response: Response<dynamic>(
            requestOptions: RequestOptions(), statusCode: 404));
    e.check(loading.activeCount == 0, 'loading 未归零');
    e.mark([
      tkDiomanLoadingActiveCount,
      tkDiomanTokenManagerAccessToken,
      tkDiomanTokenManagerRefreshToken,
      tkDiomanTokenManagerCanRefresh,
      'defaultAuthFailure'
    ], tkConstructors);
    tokens.clear();
    e.mark(['DiomanTokenManager.clear'], tkManagement);
    final constants = <String, Object>{
      'DiomanClonePolicy': DiomanClonePolicy.values,
      'DiomanCachePolicy': DiomanCachePolicy.values,
      'DiomanSharePolicy': DiomanSharePolicy.values,
      'NetworkQuality': NetworkQuality.values,
      'DiomanAuthFailureAction': DiomanAuthFailureAction.values,
      'DiomanBreakerState': DiomanBreakerState.values,
      'DiomanOfflineReason': DiomanOfflineReason.values,
      'DiomanExtraKeyKind': DiomanExtraKeyKind.values,
      tkDiomanPluginOrderIssue: DiomanPluginOrderIssue.values,
    };
    for (final entry in constants.entries) {
      e.mark([
        entry.key,
        ...(entry.value as List<Enum>).map((v) => '${entry.key}.${v.name}')
      ], 'enum metadata');
    }
    final metadata = e.constructed(
        tkDiomanExtraKey,
        const DiomanExtraKey(
            key: 'probe:state',
            owner: tkProbeFirst,
            kind: DiomanExtraKeyKind.state,
            valueType: tkBool,
            description: tkProbeState),
        [tkKey, 'owner', tkKind, 'valueType', 'description']);
    const configKey = DiomanExtraKey.config('probe:config', tkBool, '探针配置');
    const stateKey = DiomanExtraKey.state(
        'probe:second', tkProbeFirst, tkBool, tkProbeState);
    values[tkDiomanExtraKey] = metadata;
    final sharedKey = e.constructed(tkDiomanSharedStateKey,
        DiomanSharedStateKey(metadata, 2), [tkKey, 'count']);
    values[tkDiomanSharedStateKey] = sharedKey;
    metadata.toString();
    sharedKey.toString();
    DiomanExtraKeys.register(metadata);
    DiomanExtraKeys.lookup(metadata.key);
    DiomanExtraKeys.ofKind(metadata.kind);
    DiomanExtraKeys.ofOwner(metadata.owner);
    DiomanExtraKeys.all;
    DiomanExtraKeys.builtIn;
    DiomanExtraKeys.findSharedState([cache, cache]);
    DiomanExtraKeys.assertNoSharedState(handle.plugins);
    DiomanExtraKeys.toMarkdown();
    DiomanExtraKeys.unregister(metadata.key);
    e.mark([
      'DiomanExtraKey.config',
      'DiomanExtraKey.config(name)',
      'DiomanExtraKey.config(valueType)',
      'DiomanExtraKey.config(description)',
      'DiomanExtraKey.state',
      'DiomanExtraKey.state(key)',
      'DiomanExtraKey.state(owner)',
      'DiomanExtraKey.state(valueType)',
      'DiomanExtraKey.state(description)',
      'DiomanExtraKey.toString',
      'DiomanSharedStateKey.toString',
      'DiomanExtraKeys',
      'DiomanExtraKeys.register',
      'DiomanExtraKeys.lookup',
      'DiomanExtraKeys.ofKind',
      'DiomanExtraKeys.ofOwner',
      tkDiomanExtraKeysAll,
      tkDiomanExtraKeysBuiltIn,
      'DiomanExtraKeys.findSharedState',
      'DiomanExtraKeys.assertNoSharedState',
      'DiomanExtraKeys.toMarkdown',
      'DiomanExtraKeys.unregister'
    ], tkMetadata);
    e.check(
        configKey.kind == DiomanExtraKeyKind.config &&
            stateKey.kind == DiomanExtraKeyKind.state,
        '快捷键构造不符');
    values[tkDiomanPluginOrder] = e.constructed(
        tkDiomanPluginOrder,
        const DiomanPluginOrder(
            before: {tkAfter}, after: {tkBefore}, requires: {'dependency'}),
        [tkBefore, tkAfter, tkRequires]);
    final orderError = e.constructed(
        tkDiomanPluginOrderException,
        const DiomanPluginOrderException(
            DiomanPluginOrderIssue.cycle, [tkA2], '探针异常'),
        [tkIssue, tkPlugins, tkMessage]);
    values[tkDiomanPluginOrderException] = orderError;
    orderError.toString();
    final businessError = e.constructed(
        tkDiomanException,
        const DiomanException(code: 1001, message: '业务失败', data: {}),
        [tkCode, tkMessage, tkData]);
    values[tkDiomanException] = businessError;
    businessError.toString();
    final offlineError = e.constructed(tkDiomanOfflineException,
        const DiomanOfflineException(DiomanOfflineReason.timeout), [tkReason]);
    values[tkDiomanOfflineException] = offlineError;
    offlineError.toString();
    final breakerError = e.constructed(
        tkDiomanBreakerOpenException,
        DiomanBreakerOpenException(
            bucketKey: tkBucket, retryableAt: DateTime.now()),
        ['bucketKey', 'retryableAt']);
    values[tkDiomanBreakerOpenException] = breakerError;
    breakerError.toString();
    e.mark([
      'DiomanPluginOrderException.toString',
      'DiomanException.toString',
      'DiomanOfflineException.toString',
      'DiomanBreakerOpenException.toString',
      tkDiomanCachePersist,
      tkDiomanTokenManager,
      tkDiomanHandle,
      'Dioman',
      'DiomanRetryDelay',
      'DiomanShouldRetry',
      'DiomanJitter',
      'DiomanShouldTrip',
      'LogWriter',
      'kKey'
    ], tkMetadata);
    values[tkDiomanTokenManager] = tokens;
    values[tkDiomanCachePersist] = persist;
    values[tkDiomanHandle] = handle;
    values[tkDiomanPlugin] = const ProbePlugin('base');
    DiomanNotifyOptions();
    e.mark([tkDiomanNotifyOptions, 'DiomanNotifyOptions.new'], tkCompatibility);
    // 每个字段的实际读取由生成的检查器完成，避免靠类覆盖代替字段覆盖。
    await writeApiEvidence(e, values);
    e.check(events.where((v) => v).length == events.where((v) => !v).length,
        'loading 不成对');
    e.check(logs.isNotEmpty && callbackCount > 0, '回调未执行');
    final serverProof = ioClient(serverUrl);
    try {
      final response = await serverProof.get<dynamic>('/t/runs/${e.run}',
          options: Options(headers: {runHeader: e.run}));
      final stats = obj(obj(response.data)[tkData]);
      e.check(stats[tkInflight] == 0, 'API 探针在途请求未释放');
      e.observations.add({tkServer: stats, tkRunId: e.run});
    } finally {
      serverProof.close(force: true);
    }
    online = false;
  } finally {
    handle?.dispose();
    dio.close(force: true);
    raw.close(force: true);
    await connectivity.close();
    await deleteProbeProxy(control, proxy, e.run);
    control.close(force: true);
  }
  e.mark(['DiomanHandle.dispose'], tkTeardown);
  await File(tkAcceptResultsApiEvidenceJson)
      .writeAsString(const JsonEncoder.withIndent(tkJsonIndent).convert({
    tkRunId: e.run,
    'service': serverUrl,
    'netem_control': netemUrl,
    tkAdapter: tkIo,
    tkHits: {
      for (final entry in e.hits.entries) entry.key: entry.value.toList()
    },
    tkObservations: e.observations
  }));
  return e;
}

/// writeApiEvidence 的测试辅助入口。
/// 由 inventory 生成的字段检查器在独立文件实现。
Future<void> writeApiEvidence(ApiEvidence e, Map<String, Object> values) async {
  inspectApiFields(e, values);
}

/// inspectApiFields 的测试辅助入口。
/// 逐项读取字段的生成器入口，生成内容见 probes_fields.dart。
void inspectApiFields(ApiEvidence e, Map<String, Object> values) {
  generatedInspect(e, values);
}
