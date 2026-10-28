// ignore_for_file: avoid_relative_lib_imports
// 边界层：loading
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/loading_plugin.dart';
import 'package:test/test.dart';
import '../../test/support/fixtures.dart';

/// 注册本文件的边界层用例。
void main() {
  test(
      '[DiomanLoading.dispose][DiomanLoading.delayClose][DiomanLoading.new(onChanged)] loading callback stays paired across delayed hide and disposal',
      () async {
    final states = <bool>[];
    final own = <bool>[];
    final loading = DiomanLoading(
        onChanged: states.add, delayClose: const Duration(hours: 1));
    final first = cacheOptions();
    loading.onRequest(first, RecordingRequestHandler());
    loading.onResponse(
        Response(requestOptions: first), RecordingResponseHandler());
    final second = cacheOptions()
      ..extra[DiomanLoading.pluginName] =
          DiomanLoadingOptions(onChanged: own.add);
    loading.onRequest(second, RecordingRequestHandler());
    expect(loading.activeCount, 1);
    loading.dispose();
    expect(loading.activeCount, 0);
    loading.dispose();
    expect(states, [true, false]);
    expect(own, isEmpty);
  });

  test('[DiomanLoading.dispose] 释放取消尚未触发的显示定时器', () async {
    final states = <bool>[];
    const delay = Duration(milliseconds: 20);
    final loading = DiomanLoading(onChanged: states.add, delay: delay);
    loading.onRequest(cacheOptions(), RecordingRequestHandler());
    expect(loading.activeCount, 1);
    loading.dispose();
    expect(loading.activeCount, 0);
    await Future<void>.delayed(delay * 2);
    expect(states, isEmpty);
  });

  test(
      '[DiomanLoading.new(onChanged)][DiomanLoadingOptions.onChanged] loading closes using callback that opened display cycle',
      () {
    final states = <bool>[];
    final own = <bool>[];
    final loading = DiomanLoading(onChanged: states.add);
    final first = cacheOptions();
    final second = cacheOptions()
      ..extra[DiomanLoading.pluginName] =
          DiomanLoadingOptions(onChanged: own.add);
    loading.onRequest(first, RecordingRequestHandler());
    loading.onRequest(second, RecordingRequestHandler());
    for (final options in [first, second]) {
      loading.onResponse(
          Response(requestOptions: options), ResponseInterceptorHandler());
    }
    expect(states, [true, false]);
    expect(own, isEmpty);
  });

  test('[DiomanLoading.delay][DiomanLoading.new(onChanged)] loading 在显示前结束时不通知',
      () async {
    final events = <bool>[];
    final plugin = DiomanLoading(onChanged: events.add, delay: replayTick);
    final options = RequestOptions(path: replayPath);
    plugin.onRequest(options, RequestInterceptorHandler());
    plugin.onResponse(
        Response(requestOptions: options), ResponseInterceptorHandler());
    await Future<void>.delayed(replayTick);
    expect(events, isEmpty);
    plugin.dispose();
  });
}
