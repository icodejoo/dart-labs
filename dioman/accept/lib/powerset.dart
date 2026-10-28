import 'literals.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'client.dart';
import 'common.dart';

/// 封装 BorrowedAdapter 测试夹具。
/// 借用唯一的 io 连接池，插件拆卸不会关闭宿主传输层。
class BorrowedAdapter implements HttpClientAdapter {
  /// 构造独立测试实例。
  /// 传输层由外部统一释放。
  BorrowedAdapter(this.transport);

  /// 真实 io 适配器。
  final HttpClientAdapter transport;

  /// fetch 的测试实现。
  /// 每个请求仍经真实 netem 和服务器，不做内存响应。
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
          Future<void>? cancelFuture) =>
      transport.fetch(options, stream, cancelFuture);

  /// close 的测试实现。
  /// 插件客户端不拥有共享连接池。
  @override
  void close({bool force = false}) {}
}

/// runRealPowerset 的测试辅助入口。
/// 确定性单开、双开及全部同开，每个组合使用独立轮次验证真实请求。
Future<void> runRealPowerset() async {
  final run = 'dioman-powerset-${DateTime.now().microsecondsSinceEpoch}-$pid';
  final control = ioClient(netemUrl);
  final raw = ioClient(serverUrl);
  final proxy = await createProbeProxy(control, run);
  final transport = ioClient('http://127.0.0.1:${proxy[tkPort]}');
  final adapter = BorrowedAdapter(transport.httpClientAdapter);
  final names = capabilities.toList()..sort();
  final count = (1 << names.length) - 1;
  final masks = <int>{
    for (var i = 0; i < names.length; i++) 1 << i,
    for (var i = 0; i < names.length; i++)
      for (var j = i + 1; j < names.length; j++) (1 << i) | (1 << j),
    count,
  }.toList()
    ..sort();
  final observations = <Map<String, dynamic>>[];
  final watch = Stopwatch()..start();
  final proof = File('coverage/accept/powerset.ndjson');
  await proof.parent.create(recursive: true);
  final sink = proof.openWrite();
  try {
    for (final mask in masks) {
      final subsetRun = '$run-$mask';
      final plugins = <String, dynamic>{
        for (var bit = 0; bit < names.length; bit++)
          if (mask & (1 << bit) != 0) names[bit]: <String, dynamic>{},
      };
      final client = ScenarioClient({
        tkClient: {tkPlugins: plugins}
      }, subsetRun, transport.options.baseUrl, tkHttp);
      client.dio.httpClientAdapter = adapter;
      try {
        final response = await client.dio.get<dynamic>(tkTEcho,
            queryParameters: {
              tkKey: tkPowerset,
              tkData: jsonEncode({tkMask: mask})
            },
            options: Options(
                headers: client.headers,
                extra: client.extras(
                    {tkMock: false, tkKey: true, tkCache: true}, '$mask')));
        final body = obj(response.data);
        final data = body.containsKey(tkCode) ? obj(body[tkData]) : body;
        final meta = obj(data[tkMeta]);
        if (meta[tkRun] != subsetRun ||
            meta[tkHit] != 1 ||
            obj(data[tkPayload])[tkMask] != mask) {
          throw StateError('子集 $mask 的真实响应不符');
        }
        if (client.loadingEvents.where((v) => v).length !=
            client.loadingEvents.where((v) => !v).length) {
          throw StateError('子集 $mask 的 loading 未释放');
        }
        sink.writeln(jsonEncode({
          tkRunId: subsetRun,
          tkMask: mask,
          tkHit: meta[tkHit],
          tkPlugins: plugins.keys.toList(),
          tkStatus: tkPassed
        }));
      } finally {
        await client.dispose();
      }
      final stats = obj(obj((await raw.get<dynamic>('/t/runs/$subsetRun',
              options: Options(headers: {runHeader: subsetRun})))
          .data)[tkData]);
      if (obj(stats[tkByKey])[tkPowerset] != 1 || stats[tkInflight] != 0) {
        throw StateError('子集 $mask 服务端计数或资源释放不符: $stats');
      }
      observations.add({tkMask: mask, tkRunId: subsetRun, tkServer: stats});
      if (serviceBlocked) throw StateError('服务要求停止验收');
    }
    await File(tkAcceptResultsPowersetSummaryJson)
        .writeAsString(const JsonEncoder.withIndent(tkJsonIndent).convert({
      tkRunId: run,
      'strategy': 'deterministic: all singletons + all exact pairs + full set',
      'total_nonempty_subsets': count,
      tkExecuted: masks.length,
      'pair_coverage': 136,
      'singleton_coverage': names.length,
      'full_set_executed': true,
      'exhaustive': false,
      'passed': masks.length,
      'failed': 0,
      tkPlugins: names,
      tkDurationMs: watch.elapsedMilliseconds,
      tkServer: observations
    }));
  } finally {
    await sink.close();
    transport.close(force: true);
    raw.close(force: true);
    await deleteProbeProxy(control, proxy, run);
    control.close(force: true);
  }
}
