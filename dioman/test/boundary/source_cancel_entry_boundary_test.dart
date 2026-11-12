import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';

/// 独立插件实例仍防御已经取消的上下文。
void main() {
  test('[DiomanShare.setup][DiomanOffline.setup] 独立 handle 不发送已取消请求', () async {
    final token = CancelToken()..cancel();
    final ctx = testContext(
        token: token,
        request: DiomanRequest(RequestOptions(),
            call: DiomanCall(options: {DiomanShare.option: true})));
    final events = StreamController<bool>();
    final instances = <DiomanPluginInstance<DiomanResponse<dynamic>>>[
      const DiomanShare().setup(ctx.client),
      DiomanOffline(isOnline: () => false, onConnectivityChanged: events.stream)
          .setup(ctx.client)
    ];
    for (final instance in instances) {
      final result =
          await instance.handle(ctx, ([patch]) async => fail('取消不能进入内层'));
      expect(failureOf(result)?.kind, DiomanFailureKind.cancel);
      expect(failureOf(result)?.reason, isNull);
      instance.dispose();
    }
    await events.close();
  });
}
