import 'dart:async';
import 'dart:typed_data';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/invariant_harness.dart';

const _field = 'a';
const _path = '/b8';

void main() {
  for (final invariant in [8, 9]) {
    test('[INV-pipeline-internals] B8 I$invariant 夹具拒绝错误证据', () {
      final api = testClient();
      final h = InvariantHarness(FakeNetwork(), FakeClock());
      h.entries[1] = h.exits[1] = h.settlements[1] = 1;
      if (invariant == 8) {
        h.ownership[1] = (false, DiomanKind.timeout);
      } else {
        h.expectedEcho[1] = [1];
        h.actualEcho[1] = [2];
      }
      expect(() => h.assertAll(api), throwsA(isA<TestFailure>()));
      api.dispose();
    });
  }
  test('[DiomanKeyService.maxBodyBytes][DiomanKeyService.build] B8 安全内容键', () {
    const service = DiomanKeyService(DiomanKeyOptions());
    String? key(Object? body) =>
        service.build(RequestOptions(path: _path, data: body));
    expect(
        key(<Object?>[
          {_field: 1},
          true
        ]),
        key(<Object?>[
          {_field: 1},
          true
        ]));
    expect(key(<Object?>[1, 2]), isNot(key(<Object?>[2, 1])));
    expect(key(<int>[1, 2]), key(Uint8List.fromList([1, 2])));
    expect(key(<int>[1, 2]), isNot(key(<int>[2, 1])));
    expect(key(Uint8List.fromList([126, 162, 133, 180, 156, 60, 76, 159])),
        isNot(key(Uint8List.fromList([233, 247, 55, 250, 228, 8, 210, 57]))));
    expect(key(Uint8List(DiomanKeyService.maxBodyBytes)), isNotNull);
    expect(key(Uint8List(DiomanKeyService.maxBodyBytes + 1)), isNull);
    for (final body in [
      FormData(),
      const Stream<int>.empty(),
      Object(),
      {_field: Object()},
      <Object?>[Object()]
    ]) {
      expect(key(body), isNull);
    }
  });

  test('[DiomanContext.canReplay] B8 递归判断重放能力', () {
    for (final body in [
      null,
      1,
      true,
      's',
      FormData(),
      {
        _field: [1, null]
      },
      <int>[1]
    ]) {
      expect(
          testContext(request: DiomanRequest(RequestOptions(data: body)))
              .canReplay(),
          isTrue);
    }
    for (final body in [
      const Stream<int>.empty(),
      Object(),
      {_field: Object()},
      [Object()]
    ]) {
      expect(
          testContext(request: DiomanRequest(RequestOptions(data: body)))
              .canReplay(),
          isFalse);
    }
  });

  test('[DiomanResponseFactory.normalize] B8 Dio 解码 FormatException 保留 HTTP 状态',
      () {
    final request = RequestOptions(path: _path);
    final r = DiomanResponseFactory<Result>().normalize(DiomanRequest(request),
        error: DioException(
            requestOptions: request,
            error: const FormatException(),
            response:
                Response<dynamic>(requestOptions: request, statusCode: 502)));
    expect([r.kind, r.status, r.httpStatus], [DiomanKind.parse, 502, 502]);
  });

  test('[DiomanNotify.defaultStringify] B8 internal 默认不通知', () {
    final ctx = testContext();
    final r = ctx.fail(const DiomanFailure(kind: DiomanKind.internal));
    expect(DiomanNotify.defaultStringify(r, ctx), isEmpty);
  });
}
