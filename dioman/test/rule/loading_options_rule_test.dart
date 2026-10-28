import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/fixtures.dart';

/// 短延迟，用于验证显示与关闭的延迟边缘。
const _wait = Duration(milliseconds: 40);

/// 足够长的延迟，保证测试期间不会触发。
const _long = Duration(hours: 1);

/// 加载提示用例的请求路径。
const _path = '/loading';

/// 验证计数、错误出口及两个延迟边缘。
void main() {
  test(
      '[DiomanLoading.name][DiomanLoading.pluginName][DiomanLoading.ordering] 名称、配置键及安装约束',
      () {
    final plugin = DiomanLoading(onChanged: (_) {});
    addTearDown(plugin.dispose);
    expect(DiomanLoading.pluginName, 'dioman:loading');
    expect(plugin.name, DiomanLoading.pluginName);
    expect(
        plugin.ordering.after,
        containsAll([
          DiomanCache.pluginName,
          DiomanShare.pluginName,
          DiomanMock.pluginName
        ]));
    expect(plugin.ordering.before,
        containsAll([DiomanAuth.pluginName, DiomanRetry.pluginName]));
    final options = RequestOptions(path: _path, extra: {
      DiomanLoading.pluginName: const DiomanLoadingOptions(enabled: false),
    });
    plugin.onRequest(options, RecordingRequestHandler());
    expect(plugin.activeCount, 0);
  });

  test('[DiomanLoading.onError][DiomanLoading.onResponse] 成功和失败仅释放自己开启的计数', () {
    for (final type in [
      null,
      DioExceptionType.badResponse,
      DioExceptionType.cancel,
      DioExceptionType.receiveTimeout
    ]) {
      final states = <bool>[];
      final plugin = DiomanLoading(onChanged: states.add);
      addTearDown(plugin.dispose);
      final options = RequestOptions(path: _path);
      plugin.onRequest(options, RecordingRequestHandler());
      expect(plugin.activeCount, 1);
      plugin.onResponse(Response(requestOptions: RequestOptions(path: _path)),
          RecordingResponseHandler());
      expect(plugin.activeCount, 1, reason: '没有加过计数的请求不能抢走在途名额');
      if (type == null) {
        plugin.onResponse(
            Response(requestOptions: options), RecordingResponseHandler());
      } else {
        plugin.onError(DioException(requestOptions: options, type: type),
            IgnoringErrorHandler());
      }
      expect(plugin.activeCount, 0);
      expect(states, [true, false]);
      plugin.onResponse(
          Response(requestOptions: options), RecordingResponseHandler());
      expect(plugin.activeCount, 0);
      expect(states, [true, false]);
    }
  });

  test('[DiomanLoadingOptions.delay] 默认继承且仅零到一的请求决定显示延迟', () async {
    expect(const DiomanLoadingOptions().delay, isNull);
    for (final inherited in [false, true]) {
      final states = <bool>[];
      final plugin = DiomanLoading(
          onChanged: states.add, delay: inherited ? _wait : _long);
      addTearDown(plugin.dispose);
      final firstOverride =
          DiomanLoadingOptions(delay: inherited ? null : _wait);
      expect(firstOverride.delay, inherited ? isNull : _wait);
      final first = RequestOptions(
          path: _path, extra: {DiomanLoading.pluginName: firstOverride});
      final second = RequestOptions(path: _path, extra: {
        DiomanLoading.pluginName: const DiomanLoadingOptions(delay: _long),
      });
      plugin.onRequest(first, RecordingRequestHandler());
      plugin.onRequest(second, RecordingRequestHandler());
      expect(states, isEmpty);
      await Future<void>.delayed(_wait * 2);
      expect(states, [true]);
      plugin.onResponse(
          Response(requestOptions: first), RecordingResponseHandler());
      plugin.onResponse(
          Response(requestOptions: second), RecordingResponseHandler());
      expect(states, [true, false]);
    }
  });

  test('[DiomanLoadingOptions.delayClose] 默认继承且仅一到零的请求决定关闭延迟', () async {
    expect(const DiomanLoadingOptions().delayClose, isNull);
    for (final inherited in [false, true]) {
      final states = <bool>[];
      final plugin = DiomanLoading(
          onChanged: states.add, delayClose: inherited ? _wait : Duration.zero);
      addTearDown(plugin.dispose);
      final lastOverride =
          DiomanLoadingOptions(delayClose: inherited ? null : _wait);
      expect(lastOverride.delayClose, inherited ? isNull : _wait);
      final first = RequestOptions(path: _path, extra: {
        DiomanLoading.pluginName: const DiomanLoadingOptions(delayClose: _long),
      });
      final last = RequestOptions(
          path: _path, extra: {DiomanLoading.pluginName: lastOverride});
      plugin.onRequest(first, RecordingRequestHandler());
      plugin.onRequest(last, RecordingRequestHandler());
      plugin.onResponse(
          Response(requestOptions: first), RecordingResponseHandler());
      expect(plugin.activeCount, 1);
      plugin.onResponse(
          Response(requestOptions: last), RecordingResponseHandler());
      expect(plugin.activeCount, 0);
      expect(states, [true]);
      await Future<void>.delayed(_wait * 2);
      expect(states, [true, false]);
    }
  });
}
