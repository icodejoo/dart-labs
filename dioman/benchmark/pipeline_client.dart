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

/// 有效凭证，基准不触发刷新。
class _Tokens implements DiomanTokenManager {
  @override
  String get accessToken => 'benchmark-token';
  @override
  String get refreshToken => 'benchmark-refresh';
  @override
  void setTokens({required String accessToken, String? refreshToken}) {}
  @override
  void clear() {}
}

/// 新客户端六场景，与固定旧提交共享 runner 和发送数自检。
class _PipelineClient implements DiomanBenchClient {
  _PipelineClient(this.scenario) {
    dio.httpClientAdapter = adapter;
    final full = scenario == DiomanBenchScenario.s3 ||
        scenario == DiomanBenchScenario.s4;
    final shared = scenario == DiomanBenchScenario.s5;
    api = Dioman(dio: dio, plugins: [
      if (full) ...[
        const DiomanEnvs([]),
        DiomanTimeout(probe: () => NetworkQuality.excellent),
        const DiomanRepath(),
        const DiomanFilter(),
        const DiomanCache(expires: Duration(hours: 1)),
        DiomanOffline(
            isOnline: () => true, onConnectivityChanged: connectivity.stream),
        DiomanLoading(onChanged: (_) {}),
        DiomanAuth(
            tokenManager: _Tokens(),
            onRefresh: (_, __) {},
            onAccessExpired: (_, __) {}),
        const DiomanBreaker(),
        DiomanNotify(notify: (_, __) {}),
        // 空路由代表不命中；不额外发 mock 探测请求。
        const DiomanMock(),
      ],
      if (full || shared) const DiomanShare(policy: DiomanSharePolicy.start),
      if (full || scenario == DiomanBenchScenario.s6) const DiomanRetry(max: 2),
    ]);
  }
  final DiomanBenchScenario scenario;
  final dio = Dio(BaseOptions(baseUrl: _baseUrl));
  final adapter = _ImmediateAdapter();
  final connectivity = StreamController<bool>.broadcast();
  late final Dioman api;
  int sequence = 0;
  @override
  int get sends => adapter.sends;
  @override
  Future<void> operation() async {
    if (scenario == DiomanBenchScenario.s1) {
      await dio.get<dynamic>(_path);
    } else if (scenario == DiomanBenchScenario.s5) {
      await Future.wait(List.generate(
          diomanBenchConcurrency,
          (_) => api.get<dynamic>(_path,
              call: DiomanCall(options: {DiomanShare.option: true}))));
    } else if (scenario == DiomanBenchScenario.s6) {
      await api.post<dynamic>(_path, data: {
        'items': [
          {'value': 1}
        ]
      });
    } else {
      await api.get<dynamic>(_path,
          query: scenario == DiomanBenchScenario.s3
              ? {'sequence': sequence++}
              : null,
          call: DiomanCall(
              options: {DiomanCache.option: true, DiomanShare.option: true}));
    }
  }

  @override
  Future<void> dispose() async {
    api.dispose();
    dio.close(force: true);
    await connectivity.close();
  }
}

/// 新版六场景构造器。
Future<DiomanBenchClient> createPipelineBenchClient(
        DiomanBenchScenario scenario) async =>
    _PipelineClient(scenario);
