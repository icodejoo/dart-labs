import 'package:dioman/dioman.dart';
import 'package:dioman/src/context.dart' show DiomanContextInternal;
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';
import '../support/invariant_harness.dart';

/// 原生槽的共享状态和结果身份契约。
void main() {
  test(
      '[DiomanNative][DiomanNative.response][DiomanNative.raw][DiomanNative.error][DiomanContext.native] 派生共享单槽且严格匹配结果',
      () async {
    final ctx = testContext();
    final child = ctx.derive(const RequestPatch(headers: {'x-native': 'yes'}));
    final first = ctx.factory.fail(ctx.request, DiomanFailureKind.network);
    final raw =
        Response<dynamic>(requestOptions: ctx.request.toRequestOptions());
    final error = StateError('first');
    expect(ctx.native, isNull);
    child.writeNative(first, raw, error);
    expect(ctx.native!.response, same(first));
    expect(ctx.native!.error, same(error));
    final derived = ctx.factory.derive(first, 1);
    ctx.observeNative(derived);
    expect(child.native!.response, same(derived));
    expect(child.native!.raw, same(raw));
    ctx.observeNative(ctx.fail(DiomanFailureKind.offline));
    expect(ctx.native, isNull);
    child.writeNative(derived, raw, null);
    expect(ctx.native!.error, isNull);
    ctx.state.closeNative();
    NativeSlotProbe.assertClosed(child);
  });
}
