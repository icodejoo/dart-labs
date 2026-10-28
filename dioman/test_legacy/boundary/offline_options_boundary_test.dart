import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/support/fixtures.dart';

/// 离线队列用例的请求路径。
const _path = '/offline';

/// 验证离线队列配置及释放出口。
void main() {
  test(
      '[DiomanOffline.name][DiomanOffline.pluginName][DiomanOffline.ordering] 名称、配置键及挂起顺序',
      () {
    final plugin = DiomanOffline(
        isOnline: () => false,
        onConnectivityChanged: const Stream<bool>.empty());
    addTearDown(plugin.dispose);
    expect(DiomanOffline.pluginName, 'dioman:offline');
    expect(plugin.name, DiomanOffline.pluginName);
    expect(
        plugin.ordering.before,
        containsAll([
          DiomanShare.pluginName,
          DiomanCancel.pluginName,
          DiomanLoading.pluginName
        ]));
    const override = DiomanOfflineOptions(enabled: false);
    expect(const DiomanOfflineOptions().enabled, isNull);
    expect(override.enabled, isFalse);
    final handler = RecordingRequestHandler();
    plugin.onRequest(
        RequestOptions(
            path: _path, extra: {DiomanOffline.pluginName: override}),
        handler);
    expect(handler.calls, 1);
    expect(plugin.pending, 0);
  });

  test('[DiomanOfflineOptions.maxQueueSize] 空值继承而单请求上限在入队时生效', () {
    expect(const DiomanOfflineOptions().maxQueueSize, isNull);
    const override = DiomanOfflineOptions(maxQueueSize: 1);
    expect(override.maxQueueSize, 1);
    for (final option in [const DiomanOfflineOptions(), override]) {
      final plugin = DiomanOffline(
          isOnline: () => false,
          onConnectivityChanged: const Stream<bool>.empty(),
          maxQueueSize: 2);
      addTearDown(plugin.dispose);
      final first = RecordingRequestHandler();
      final second = RecordingRequestHandler();
      plugin.onRequest(RequestOptions(path: _path), first);
      plugin.onRequest(
          RequestOptions(
              path: _path, extra: {DiomanOffline.pluginName: option}),
          second);
      final limited = option.maxQueueSize != null;
      expect(plugin.pending, limited ? 1 : 2);
      expect(first.calls, limited ? 1 : 0);
      if (limited) {
        expect((first.error!.error as DiomanOfflineException).reason,
            DiomanOfflineReason.queueFull);
      }
      plugin.flush();
      expect(first.calls, 1);
      expect(second.calls, 1);
    }
  });

  test('[DiomanOffline.dispose] 释放拒绝排队请求并退订连通性流', () async {
    var cancelled = 0;
    final stream = StreamController<bool>(onCancel: () {
      cancelled++;
    });
    addTearDown(stream.close);
    final plugin = DiomanOffline(
        isOnline: () => false, onConnectivityChanged: stream.stream);
    final handler = RecordingRequestHandler();
    plugin.onRequest(RequestOptions(path: _path), handler);
    expect(plugin.pending, 1);
    plugin.dispose();
    await pumpEvents();
    expect(cancelled, 1);
    expect(stream.hasListener, isFalse);
    expect(plugin.pending, 0);
    expect((handler.error!.error as DiomanOfflineException).reason,
        DiomanOfflineReason.disposed);
    stream.add(true);
    plugin.flush();
    plugin.dispose();
    expect(handler.calls, 1);
  });
}
