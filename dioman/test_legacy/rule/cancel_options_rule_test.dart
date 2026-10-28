import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/request_claims.dart';
import 'package:test/test.dart';
import '../../test/support/fixtures.dart';
import '../../test/support/test_server.dart';

/// 取消配置用例的请求路径。
const _path = '/cancel-options';

/// 注册取消选项、声明与响应注销规则测试。
void main() {
  test(
      '[DiomanCancel.name][DiomanCancel.pluginName][DiomanCancel.ordering] 固定名称用于查找，声明前后顺序',
      () {
    final cancel = DiomanCancel();
    expect(cancel.name, 'dioman:cancel');
    expect(cancel.name, DiomanCancel.pluginName);
    expect(cancel.ordering.after, {
      DiomanCache.pluginName,
      DiomanShare.pluginName,
    });
    expect(cancel.ordering.before,
        {DiomanAuth.pluginName, DiomanRetry.pluginName});
    expect(cancel.ordering.requires, isEmpty);
    final dio = Dio();
    final handle = Dioman.install(dio, cancel: cancel);
    expect(handle.plugins.singleWhere((p) => p.name == DiomanCancel.pluginName),
        same(cancel));
    handle.dispose();
    dio.close(force: true);
  });

  for (final enabled in [true, false]) {
    test(
        '[DiomanCancel.config][DiomanCancel.new(enabled)][DiomanCancelOptions.enabled] enabled=$enabled 控制构造期注入与登记，忽略请求覆盖',
        () async {
      const defaults = DiomanCancelOptions();
      final config = DiomanCancelOptions(enabled: enabled);
      expect(defaults.enabled, isTrue);
      expect(config.enabled, enabled);
      final cancel = enabled ? DiomanCancel() : DiomanCancel(enabled: false);
      expect(cancel.config.enabled, enabled);
      final server = await TestServer.start((r) => respondJson(r, {}, 200));
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final handle = Dioman.install(dio, cancel: cancel);
      addTearDown(() async {
        handle.dispose();
        dio.close(force: true);
        await server.close();
      });
      final result = await dio.get<void>(_path,
          options: Options(
              extra: {cancel.name: DiomanCancelOptions(enabled: !enabled)}));
      expect(result.requestOptions.cancelToken, enabled ? isNotNull : isNull);
      final manual = CancelToken();
      cancel.track(manual);
      expect(cancel.cancelAll(), enabled ? 1 : 0);
      expect(manual.isCancelled, enabled);
    });
  }

  test('[cancelAll] 无插件返回零，多个取消插件只调用首个', () {
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    expect(cancelAll(dio), 0);
    final first = DiomanCancel();
    final second = DiomanCancel();
    final token = CancelToken();
    final other = CancelToken();
    first.track(token);
    second.track(other);
    dio.interceptors.addAll([first, second]);
    expect(cancelAll(dio, _path), 1);
    expect(token.cancelError!.error, _path);
    expect(other.isCancelled, isFalse);
    expect(cancelAll(dio), 0);
    second.dispose();
  });

  test('[DiomanCancel.onResponse] 无认领立即注销，有认领和落败等待则延迟至最终结果', () async {
    for (final stage in [0, 1, 2]) {
      final cancel = DiomanCancel();
      final options = RequestOptions(path: _path);
      cancel.onRequest(options, RecordingRequestHandler());
      final token = options.cancelToken!;
      final owner = Object();
      final winner = Completer<Response<dynamic>>();
      if (stage > 0) claimRequest(options, owner);
      if (stage == 2) claimsOf(options)!.onFinal = (_, __) => winner.future;
      cancel.onResponse(Response<dynamic>(requestOptions: options),
          RecordingResponseHandler());
      // 分别验证无认领、仍有认领、认领已交出但等待胜者三种状态。
      if (stage == 0) {
        expect(cancel.cancelAll(), 0);
      } else {
        if (stage == 2) {
          releaseClaim(options, owner,
              response: Response<dynamic>(requestOptions: options));
          expect(claimsOf(options)!.loser, same(winner.future));
        }
        expect(cancel.cancelAll(), 1, reason: '有认领或等待胜者期间仍追踪');
        expect(token.isCancelled, isTrue);
      }
      cancel.dispose();
    }
    // 独立验证正常交付后自动注销，而非上面的 cancelAll 主动清空。
    final cancel = DiomanCancel();
    final options = RequestOptions(path: _path);
    cancel.onRequest(options, RecordingRequestHandler());
    final owner = Object();
    final winner = Completer<Response<dynamic>>();
    claimRequest(options, owner);
    claimsOf(options)!.onFinal = (_, __) => winner.future;
    cancel.onResponse(
        Response<dynamic>(requestOptions: options), RecordingResponseHandler());
    releaseClaim(options, owner,
        response: Response<dynamic>(requestOptions: options));
    winner.complete(Response<dynamic>(requestOptions: options));
    await winner.future;
    expect(cancel.cancelAll(), 0);
    expect(options.cancelToken!.isCancelled, isFalse);
  });
}
