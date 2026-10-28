import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

import 'scenarios.dart';

/// 基线请求的绝对地址，不产生真实网络访问。
const _baseUrl = 'https://benchmark.invalid';

/// 所有场景共用的路径。
const _path = '/value';

/// 立即返回的成功信封；每次 fetch 新建响应，Dio 每次解码出新 Map。
const _envelope = '{"code":0,"data":{"value":1},"message":"ok"}';

/// 薄假传输，只计数并返回新信封，没有路由表或定时器。
class _ImmediateAdapter implements HttpClientAdapter {
  /// 记录实际传输调用数。
  int sends = 0;

  /// 立即创建独立响应体，交给真实 Dio Transformer 解码。
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sends++;
    return ResponseBody.fromString(_envelope, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  /// 假传输没有需要释放的连接。
  @override
  void close({bool force = false}) {}
}

/// memo 场景仍需提供旧 API 要求的持久化契约，但不会访问它。
class _UnusedPersist implements DiomanCachePersist {
  /// 持久化不参与本基线。
  @override
  dynamic read(String key) => null;

  /// 持久化不参与本基线。
  @override
  Future<void> write(String key, Map<String, dynamic> value) async {}

  /// 持久化不参与本基线。
  @override
  Future<void> remove(String key) async {}

  /// 持久化不参与本基线。
  @override
  Future<void> erase() async {}
}

/// 预置有效凭证，auth 参与链路但不触发刷新。
class _Tokens implements DiomanTokenManager {
  /// 返回固定的有效凭证。
  @override
  String get accessToken => 'benchmark-token';

  /// 固定刷新凭证，仅满足旧接口契约。
  @override
  String get refreshToken => 'benchmark-refresh';

  /// 基线不需要刷新。
  @override
  bool get canRefresh => false;

  /// 成功路径不会清除凭证。
  @override
  void clear() {}
}

/// 旧安装式客户端，所有旧 API 依赖集中在本文件。
class _LegacyClient implements DiomanBenchClient {
  /// 构造单一场景并安装对应旧插件。
  _LegacyClient(this.scenario) {
    dio.httpClientAdapter = adapter;
    if (scenario == DiomanBenchScenario.s1) return;
    final full = scenario == DiomanBenchScenario.s3 ||
        scenario == DiomanBenchScenario.s4;
    final shared = scenario == DiomanBenchScenario.s5;
    if (full) {
      dio.httpClientAdapter = DiomanMockAdapter(inner: adapter);
    }
    handle = Dioman.install(
      dio,
      envs: full ? DiomanEnvs([]) : null,
      timeout:
          full ? DiomanTimeout(probe: () => NetworkQuality.excellent) : null,
      repath: full ? DiomanRepath() : null,
      filter: full ? const DiomanFilter() : null,
      key: full || shared ? const DiomanKey() : null,
      cache: full
          ? DiomanCache(
              persist: _UnusedPersist(),
              cachePolicy: DiomanCachePolicy.memo,
              // 每轮远短于 TTL，S4 不允许因过期触网。
              expires: const Duration(hours: 1).inMilliseconds)
          : null,
      offline: full
          ? DiomanOffline(
              isOnline: () => true, onConnectivityChanged: connectivity.stream)
          : null,
      share:
          full || shared ? DiomanShare(policy: DiomanSharePolicy.start) : null,
      cancel: full ? DiomanCancel() : null,
      loading: full ? DiomanLoading(onChanged: (_) {}) : null,
      auth: full
          ? DiomanAuth(
              tokenManager: _Tokens(),
              onRefresh: (_, __) async {},
              onAccessExpired: (_, __) async {})
          : null,
      retry: full || scenario == DiomanBenchScenario.s6
          ? DiomanRetry(max: 2)
          : null,
      breaker: full ? DiomanBreaker() : null,
      log: full ? DiomanLog(writer: (_, {error}) {}) : null,
      normalize: full ? const DiomanNormalize() : null,
      plugins: [
        if (full)
          DiomanNotify<dynamic>(
              notify: (_) {}, stringify: (_, __, ___, ____) => '')
      ],
    );
  }

  final DiomanBenchScenario scenario;
  final Dio dio = Dio(BaseOptions(baseUrl: _baseUrl));
  final _ImmediateAdapter adapter = _ImmediateAdapter();
  final StreamController<bool> connectivity =
      StreamController<bool>.broadcast();
  DiomanHandle? handle;
  int sequence = 0;

  /// 读取底层发送次数，包括 mock 包装下的真实回落。
  @override
  int get sends => adapter.sends;

  /// 执行同一场景的稳定操作，S3 递增 query 保证真实缓存未命中。
  @override
  Future<void> operation() async {
    if (scenario == DiomanBenchScenario.s5) {
      await Future.wait(List.generate(
          diomanBenchConcurrency,
          (_) => dio.get<dynamic>(_path,
              options: Options(extra: {
                DiomanShare.pluginName: true,
              }))));
    } else if (scenario == DiomanBenchScenario.s6) {
      await dio.post<dynamic>(_path, data: {
        'items': [
          {'value': 1}
        ]
      });
    } else {
      await dio.get<dynamic>(_path,
          queryParameters: scenario == DiomanBenchScenario.s3
              ? {'sequence': sequence++}
              : null,
          options: Options(extra: {
            DiomanCache.pluginName: true,
            DiomanShare.pluginName: true,
          }));
    }
  }

  /// 回收整个场景，避免影响后续场景。
  @override
  Future<void> dispose() async {
    handle?.dispose();
    dio.close(force: true);
    await connectivity.close();
  }
}

/// B0 的旧客户端构造器；新实现可另建同签名函数交错运行。
Future<DiomanBenchClient> createLegacyBenchClient(
        DiomanBenchScenario scenario) async =>
    _LegacyClient(scenario);
