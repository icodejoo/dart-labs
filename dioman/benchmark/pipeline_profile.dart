import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

/// 公开插件边界的计时探针；只用于定位线索，不替代无探针的 A/B。
class _Probe extends DiomanPlugin<DiomanResponse<dynamic>> {
  const _Probe(this.stage, this.enforce, this.samples);
  @override
  final DiomanStage stage;
  @override
  final DiomanEnforce enforce;
  final Map<String, List<int>> samples;
  @override
  String get name => 'profile:${stage.name}:${enforce.name}';
  @override
  DiomanPluginInstance<DiomanResponse<dynamic>> setup(
          Dioman<DiomanResponse<dynamic>> client) =>
      _ProbeInstance(name, samples);
}

/// 每客户端独立探针，记录包含内层的耗时。
class _ProbeInstance extends DiomanPluginInstance<DiomanResponse<dynamic>> {
  _ProbeInstance(this.name, this.samples);
  final String name;
  final Map<String, List<int>> samples;
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext<DiomanResponse<dynamic>> ctx,
      DiomanNext<DiomanResponse<dynamic>> next) async {
    final watch = Stopwatch()..start();
    try {
      return await next();
    } finally {
      (samples[name] ??= []).add(watch.elapsedTicks);
    }
  }
}

/// 与性能基准相同的新 JSON 信封薄传输。
class _Immediate implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString('{"code":0,"data":{"value":1}}', 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
  @override
  void close({bool force = false}) {}
}

/// 有效凭证，不触发刷新。
class _Tokens implements DiomanTokenManager {
  @override
  String get accessToken => 'profile-token';
  @override
  String? get refreshToken => null;
  @override
  void setTokens({required String accessToken, String? refreshToken}) {}
  @override
  void clear() {}
}

/// 全插件未命中路径的阶段内时间差；探针自身开销保留，不作性能门槛证据。
Future<void> main() async {
  final samples = <String, List<int>>{};
  final connectivity = StreamController<bool>.broadcast();
  final dio = Dio(BaseOptions(baseUrl: 'https://profile.invalid'))
    ..httpClientAdapter = _Immediate();
  final api = Dioman(dio: dio, plugins: [
    for (final stage in DiomanStage.values)
      for (final enforce in DiomanEnforce.values)
        _Probe(stage, enforce, samples),
    const DiomanEnvs([]),
    DiomanLoading(onChanged: (_) {}),
    DiomanNotify(notify: (_, __) {}),
    const DiomanRepath(),
    const DiomanFilter(),
    DiomanTimeout(probe: () => NetworkQuality.excellent),
    const DiomanRetry(max: 2),
    const DiomanBreaker(),
    DiomanAuth(
        tokenManager: _Tokens(),
        onRefresh: (_, __) {},
        onAccessExpired: (_, __) {}),
    const DiomanMock(),
    const DiomanShare(),
    const DiomanCache(),
    DiomanOffline(
        isOnline: () => true, onConnectivityChanged: connectivity.stream),
  ]);
  try {
    for (var i = 0; i < 6000; i++) {
      if (i == 1000) samples.clear();
      await api.get<dynamic>('/value',
          query: {'sequence': i},
          call: DiomanCall(
              options: {DiomanCache.option: true, DiomanShare.option: true}));
    }
    final micros = 1000000 / Stopwatch().frequency;
    double mean(String key) =>
        samples[key]!.reduce((a, b) => a + b) / samples[key]!.length * micros;
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'method': '5000 calls after 1000 warmup; intrusive stage timers',
      'inclusiveMeanMicros': {for (final key in samples.keys) key: mean(key)},
      'stageBuiltinWindowMicros': {
        for (final stage in DiomanStage.values)
          stage.name: mean('profile:${stage.name}:pre') -
              mean('profile:${stage.name}:post')
      },
      'transportAndNormalizationMicros': mean('profile:source:post')
    }));
  } finally {
    api.dispose();
    dio.close(force: true);
    await connectivity.close();
  }
}
