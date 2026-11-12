import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

/// 微基准的共同地址。
const _url = 'https://benchmark.invalid';

/// 微基准的共同路径。
const _path = '/value';

/// 重放开关名称。
const _cloneOn = 'clone-on', _cloneOff = 'clone-off';

/// 嵌套体字段。
const _items = 'items', _value = 'value';

/// 与正式基准相同的预热与测量下限。
const _warmupMillis = 500, _measurementMillis = 2000;

/// 微基准结果字段。
const _scenarioField = 'scenario',
    _operationsField = 'operations',
    _elapsedField = 'elapsedSeconds',
    _meanField = 'meanMicros';

/// 防止同步测量结果被消除。
Object? _sink;

/// 立即返回 JSON 的薄适配器。
class _DiomanImmediate implements HttpClientAdapter {
  /// 返回独立响应，保留真实转换开销。
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString('{"code":0,"data":1}', 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });

  /// 无外部资源。
  @override
  void close({bool force = false}) {}
}

/// 只改变重放声明，其他管线完全相同。
class _DiomanReplayProbe extends DiomanPlugin<DiomanResponse<dynamic>> {
  /// 保存本次克隆开关。
  const _DiomanReplayProbe(this.clone);

  /// 是否声明重放。
  final bool clone;

  /// 固定探针名称。
  @override
  String get name => 'r4:replay';

  /// 与 retry 同阶段。
  @override
  DiomanStage get stage => DiomanStage.attempt;

  /// 创建独立探针。
  @override
  DiomanPluginInstance<DiomanResponse<dynamic>> setup(
          Dioman<DiomanResponse<dynamic>> client) =>
      _DiomanReplayInstance(clone);
}

/// 克隆成本探针实例。
class _DiomanReplayInstance
    extends DiomanPluginInstance<DiomanResponse<dynamic>> {
  /// 保存克隆开关。
  _DiomanReplayInstance(this.clone);

  /// 是否声明重放。
  final bool clone;

  /// 相同发送路径，仅切换声明。
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext<DiomanResponse<dynamic>> ctx,
      DiomanNext<DiomanResponse<dynamic>> next) {
    if (clone) ctx.markReplayable();
    return next();
  }
}

/// 同步小操作批量计时，避免计时器成本掩盖复制成本。
Map<String, Object> _sync(String name, Object? Function() operation) {
  const batch = 100;
  final warmup = Stopwatch()..start();
  while (warmup.elapsedMilliseconds < _warmupMillis) {
    _sink = operation();
  }
  final watch = Stopwatch()..start();
  var count = 0;
  while (watch.elapsedMilliseconds < _measurementMillis) {
    for (var i = 0; i < batch; i++) {
      _sink = operation();
    }
    count += batch;
  }
  watch.stop();
  return {
    _scenarioField: name,
    _operationsField: count,
    _elapsedField: watch.elapsedTicks / watch.frequency,
    _meanField: watch.elapsedTicks /
        watch.frequency *
        Duration.microsecondsPerSecond /
        count,
  };
}

/// S6 类嵌套 POST 的克隆开关；不安装 retry，避免同时改变方法白名单等成本。
Future<Map<String, Object>> _clone(bool clone) async {
  final dio = Dio(BaseOptions(baseUrl: _url))
    ..httpClientAdapter = _DiomanImmediate();
  final api = Dioman(dio: dio, plugins: [_DiomanReplayProbe(clone)]);

  /// 每次提供独立嵌套请求体。
  Future<void> operation() async {
    await api.post<dynamic>(_path, data: {
      _items: [
        {_value: 1}
      ]
    });
  }

  try {
    final warmup = Stopwatch()..start();
    while (warmup.elapsedMilliseconds < _warmupMillis) {
      await operation();
    }
    final watch = Stopwatch()..start();
    var count = 0;
    while (watch.elapsedMilliseconds < _measurementMillis) {
      await operation();
      count++;
    }
    watch.stop();
    return {
      _scenarioField: clone ? _cloneOn : _cloneOff,
      _operationsField: count,
      _elapsedField: watch.elapsedTicks / watch.frequency,
      _meanField: watch.elapsedTicks /
          watch.frequency *
          Duration.microsecondsPerSecond /
          count,
    };
  } finally {
    api.dispose();
    dio.close(force: true);
  }
}

/// 请求复制、严格 JSON、构键及克隆的独立诊断入口。
Future<void> main(List<String> args) async {
  final options = RequestOptions(baseUrl: _url, path: _path, headers: {
    'Authorization': 'benchmark-token'
  }, queryParameters: {
    'sequence': 1
  }, data: {
    _items: [
      {_value: 1}
    ]
  });
  final request = DiomanRequest(options);
  final raw = Response<dynamic>(
      requestOptions: options, statusCode: 200, data: {'code': 0, 'data': 1});
  final operations = <String, Object? Function()>{
    'construct': () => DiomanRequest(options),
    'patch': () => request.patch(const RequestPatch(headers: {'x-probe': 1})),
    'export': request.toRequestOptions,
    'uri': () => request.uri,
    'strict-json': () => const DiomanResponseFactory(expectJson: true)
        .normalize(request, raw: raw),
    'key': () => const DiomanKeyService(DiomanKeyOptions()).build(options),
  };
  final selected = args.isEmpty ? operations.keys.toList() : args;
  final rows = <Map<String, Object>>[];
  for (final name in selected) {
    rows.add(name.startsWith('clone-')
        ? await _clone(name == _cloneOn)
        : _sync(name, operations[name]!));
  }
  if (_sink == null && rows.isEmpty) throw StateError('空测量');
  stdout.writeln(jsonEncode({
    'warmupMillis': _warmupMillis,
    'measurementMillis': _measurementMillis,
    'results': rows,
  }));
}
