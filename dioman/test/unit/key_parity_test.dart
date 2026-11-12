import '../support/constants.dart';
import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// 固定旧提交导出的基准，避免入口切换后丢失算法兼容证据。
void main() {
  test(
      '[DiomanKeyOptions.fastMode][DiomanKeyOptions.ignores]'
      '[DiomanKeyService.build] 固定种子 2400 个入口中 有意变化逐项断言，其余入口逐字节兼容旧基准',
      () async {
    final random = Random(20261028);
    Object? value(int depth) {
      if (depth > 2) return random.nextInt(9);
      switch (random.nextInt(6)) {
        case 0:
          return null;
        case 1:
          return random.nextBool();
        case 2:
          return 'v${random.nextInt(30)}';
        case 3:
          return random.nextInt(100);
        case 4:
          return [value(depth + 1), value(depth + 1)];
        default:
          return {
            pipelineTestZ: value(depth + 1),
            pipelineTestA: value(depth + 1)
          };
      }
    }

    final baseline =
        jsonDecode(File('test/support/key_baseline.json').readAsStringSync())
            as List;
    expect(baseline, hasLength(2400));
    final counts = <String, int>{};
    for (var i = 0; i < 2400; i++) {
      final fast = random.nextBool();
      final requestFast = random.nextBool() ? random.nextBool() : null;
      final ignores = random.nextBool() ? [pipelineTestIgnore] : <String>[];
      final requestIgnores = random.nextBool() ? [pipelineTestA] : null;
      final String? scope = [null, pipelineTestEmpty, 'account:$i'][i % 3];
      final String? explicit =
          i % 7 == 0 ? 'explicit:$i' : (i % 7 == 1 ? pipelineTestEmpty : null);
      String builder(RequestOptions o) => 'builder:${o.path}';
      String localBuilder(RequestOptions o) => 'request:${o.path}';
      final global = i % 11 == 0 ? builder : null;
      final local = i % 13 == 0 ? localBuilder : null;
      final request = RequestOptions(
          path: '/p${i % 15}?inline=$i',
          baseUrl: pipelineTestHttpsExampleTest,
          method: i.isEven ? pipelineTestGetMethod : pipelineTestPOST,
          queryParameters: {
            pipelineTestZ: i,
            pipelineTestA: '$i',
            pipelineTestIgnore: 1
          },
          data: value(0));
      final next = DiomanKeyService(DiomanKeyOptions(
              fastMode: fast,
              ignores: ignores,
              builder: global,
              namespace: () => scope))
          .build(
              request,
              DiomanKeyOptions(
                  fastMode: requestFast,
                  ignores: requestIgnores,
                  key: explicit,
                  builder: local));
      // 固定基准不改，只转换已明确变更的自动键字段。
      final expected = (baseline[i] as String?)?.replaceAll(
          '"<identityHashCode(data)>"', '${identityHashCode(request.data)}');
      if (expected?.contains('identity') != true) {
        final automatic = local == null &&
            (explicit == null || explicit.isEmpty) &&
            global == null;
        final category =
            automatic ? ((requestFast ?? fast) ? 'fast' : 'deep') : 'unchanged';
        counts.update(category, (n) => n + 1, ifAbsent: () => 1);
        var wanted = expected;
        if (automatic && expected != null) {
          final scoped = scope != null && scope.isNotEmpty;
          if (requestFast ?? fast) {
            final old =
                scoped ? (jsonDecode(expected) as List).first : expected;
            final fastKey = jsonEncode([old, ResponseType.json.name]);
            wanted = scoped ? jsonEncode([fastKey, scope]) : fastKey;
          } else {
            final fields = jsonDecode(expected) as List;
            fields[1] = jsonEncode(_tagKeys(jsonDecode(fields[1] as String)));
            final body = fields[2];
            if (body is Map && body.containsKey('map')) {
              body['map'] =
                  jsonEncode(_tagKeys(jsonDecode(body['map'] as String)));
            }
            fields.insert(3, ResponseType.json.name);
            wanted = jsonEncode(fields);
          }
        }
        expect(next, wanted, reason: 'seed=20261028 case=$i');
      } else if (request.data is List) {
        counts.update('b8-list', (n) => n + 1, ifAbsent: () => 1);
        expect(next, isNotNull, reason: 'B8 JSON 数组按内容构键 case=$i');
      } else {
        counts.update('b8-scalar', (n) => n + 1, ifAbsent: () => 1);
        expect(next, isNull, reason: 'B8 不再生成标量身份键 case=$i');
      }
    }
    final evidence = File('coverage/r2b-key-parity.json');
    evidence.parent.createSync(recursive: true);
    evidence.writeAsStringSync(jsonEncode(counts));
    expect(counts.values.reduce((a, b) => a + b), 2400);
  });

  test('[DiomanKeyService.build] 开关、显式键、异常及不可序列化回退', () {
    final r = RequestOptions(
        path: pipelineTestR, data: {pipelineTestBad: double.nan});
    const service = DiomanKeyService(DiomanKeyOptions());
    expect(service.build(r, false), isNull);
    expect(service.build(r, pipelineTestExplicit), pipelineTestExplicit);
    expect(() => service.build(r, 3), throwsArgumentError);
    expect(service.build(r), isNull);
    expect(service.build(RequestOptions(data: pipelineTestEmpty)), isNotNull);
    expect(service.build(RequestOptions(data: {})), isNotNull);
    final sorted = RequestOptions(data: {
      pipelineTestZ: {
        pipelineTestB: 1,
        pipelineTestA: [2, 1]
      },
      pipelineTestA: 1
    });
    final reversed = RequestOptions(data: {
      pipelineTestA: 1,
      pipelineTestZ: {
        pipelineTestA: [2, 1],
        pipelineTestB: 1
      }
    });
    expect(service.build(sorted), service.build(reversed));
    expect(
        () => DiomanKeyService(
                DiomanKeyOptions(builder: (_) => throw StateError('builder')))
            .build(r),
        throwsStateError);
    expect(
        () => DiomanKeyService(DiomanKeyOptions(
            namespace: () => throw StateError('namespace'))).build(r),
        throwsStateError);
  });
}

/// 将历史字符串键基准转换为本批明确引入的类型标签。
Object? _tagKeys(Object? value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry('string:$key', _tagKeys(item)));
  }
  if (value is List) return value.map(_tagKeys).toList();
  return value;
}
