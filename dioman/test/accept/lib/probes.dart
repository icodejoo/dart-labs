import 'literals.dart';
// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:io';
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

/// 使用新客户端执行真实请求，只为实际构造和调用登记证据。
Future<ApiEvidence> runApiProbes() async {
  final evidence = ApiEvidence();
  final client = ScenarioClient({
    'client': {'plugins': {}}
  }, evidence.run, serverUrl, tkHttp);
  try {
    final result = await client.api.send<dynamic>('GET', tkTPing,
        call: DiomanCall(headers: client.headers));
    evidence.check(result.ok, '真实 ping 成功');
    evidence.check(client.api.pending == 0, '逻辑请求释放');
    evidence.mark([
      'Dioman',
      'Dioman.new',
      'Dioman.new(dio)',
      'Dioman.send',
      'Dioman.pending',
      'DiomanResponse',
      'DiomanResponse.kind'
    ], '真实 ping');
    evidence.observations
        .add({'kind': result.kind.name, 'status': result.status});
    inspectApiFields(
        evidence, {'Dioman': client.api, 'DiomanResponse': result});
  } finally {
    await client.dispose();
  }
  evidence.mark(['Dioman.dispose'], tkTeardown);
  final target = File(tkAcceptResultsApiEvidenceJson);
  target.parent.createSync(recursive: true);
  target.writeAsStringSync(const JsonEncoder.withIndent(tkJsonIndent).convert({
    tkRunId: evidence.run,
    tkHits: {
      for (final entry in evidence.hits.entries) entry.key: entry.value.toList()
    },
    tkObservations: evidence.observations,
  }));
  return evidence;
}

/// 读取已经实际构造的实例字段；不虚报未构造类型。
Future<void> writeApiEvidence(
        ApiEvidence evidence, Map<String, Object> values) async =>
    inspectApiFields(evidence, values);

/// 由台账生成的逐字段读取入口。
void inspectApiFields(ApiEvidence evidence, Map<String, Object> values) =>
    generatedInspect(evidence, values);
