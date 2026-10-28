import '../support/pipeline/constants.dart';
import 'dart:math';
import 'package:dioman/pipeline.dart';
import 'package:dioman/dioman.dart' as legacy;
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// 唯一允许同时导入新旧库的差分测试。
void main() {
  test('[DiomanKeyService.build] 固定种子 2400 组与旧 key 逐字节一致', () async {
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
      final old = legacy.DiomanKey(
          fastMode: fast,
          ignores: ignores,
          builder: global,
          namespace: () => scope);
      final options = request.copyWith();
      options.extra[legacy.DiomanKey.pluginName] = legacy.DiomanKeyOptions(
          fastMode: requestFast,
          ignores: requestIgnores,
          key: explicit,
          builder: local);
      final handler = RequestInterceptorHandler();
      old.onRequest(options, handler);
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
      expect(next, options.extra[legacy.kKey], reason: 'seed=20261028 case=$i');
    }
  });

  test('[DiomanKeyService.build] 开关、显式键、异常及不可序列化回退', () {
    final r = RequestOptions(
        path: pipelineTestR, data: {pipelineTestBad: double.nan});
    const service = DiomanKeyService(DiomanKeyOptions());
    expect(service.build(r, false), isNull);
    expect(service.build(r, pipelineTestExplicit), pipelineTestExplicit);
    expect(() => service.build(r, 3), throwsArgumentError);
    expect(service.build(r), contains('NaN'));
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
