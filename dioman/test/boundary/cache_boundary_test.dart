// ignore_for_file: avoid_relative_lib_imports
// 边界层：cache
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/fake_cache_persist.dart';
import '../support/fixtures.dart';

/// 注册本文件的边界层用例。
void main() {
  test(
      '[DiomanCache.clear][DiomanCache.remove] remove invalidates pending reads and clear invalidates old responses',
      () async {
    final persist = ControlledPersist()..readGate = Completer<dynamic>();
    final cache =
        DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.both);
    final pending = RecordingRequestHandler();
    cache.onRequest(cacheOptions(), pending);
    await pumpEvents();
    await cache.remove(cacheKey);
    persist.readGate!.complete({
      dataField: 'stale',
      expiryField: DateTime.now().millisecondsSinceEpoch + 60000
    });
    await pumpEvents();
    expect(pending.response, isNull);
    expect(pending.calls, 1);
    persist.readGate = null;
    final options = cacheOptions();
    cache.onRequest(options, RecordingRequestHandler());
    await pumpEvents();
    await cache.clear();
    cache.onResponse(
        Response(requestOptions: options, statusCode: 200, data: 1),
        RecordingResponseHandler());
    await pumpEvents();
    expect(persist.store, isEmpty);
    final next = RecordingRequestHandler();
    cache.onRequest(cacheOptions(), next);
    await pumpEvents();
    expect(next.response, isNull);
  });

  test(
      '[DiomanCachePersist.write][DiomanCache.cachePolicy] cache write failure rejects response once and management failures await',
      () async {
    final persist = ControlledPersist();
    final cache =
        DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.persist);
    final options = cacheOptions();
    cache.onRequest(options, RecordingRequestHandler());
    await pumpEvents();
    persist.fails = true;
    final handler = RecordingResponseHandler();
    cache.onResponse(
        Response(requestOptions: options, data: 1, statusCode: 200), handler);
    await pumpEvents();
    expect(handler.calls, 1);
    expect(handler.error?.error, isA<StateError>());
    await expectLater(Future<void>.sync(cache.clear), throwsStateError);
    await expectLater(
        Future<void>.sync(() => cache.remove(cacheKey)), throwsStateError);
  });

  test(
      '[DiomanCache.clear][DiomanCachePersist.write] clear waits for pending write and erases afterwards',
      () async {
    final persist = ControlledPersist()..writeGate = Completer<void>();
    final cache =
        DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.persist);
    final options = cacheOptions();
    cache.onRequest(options, RecordingRequestHandler());
    await pumpEvents();
    final handler = RecordingResponseHandler();
    cache.onResponse(
        Response(requestOptions: options, data: 1, statusCode: 200), handler);
    await pumpEvents();
    var cleared = false;
    final clear = Future<void>.sync(cache.clear).then((_) => cleared = true);
    await pumpEvents();
    expect(cleared, isFalse);
    expect(handler.calls, 0);
    persist.writeGate!.complete();
    await clear;
    await pumpEvents();
    expect(persist.operations, [writeOperation, eraseOperation]);
    expect(persist.store, isEmpty);
    expect(handler.calls, 1);
  });

  test(
      '[DiomanCachePersist.read][DiomanCache.cachePolicy] cache read failure rejects once',
      () async {
    final cache = DiomanCache(
        persist: ControlledPersist()..fails = true,
        cachePolicy: DiomanCachePolicy.both);
    final handler = RecordingRequestHandler();
    cache.onRequest(cacheOptions(), handler);
    await pumpEvents();
    expect(handler.calls, 1);
    expect(handler.error?.error, isA<StateError>());
  });

  test(
      '[DiomanCache.cachePolicy][DiomanCache.maxEntries] cache persistent hydration respects memory capacity',
      () async {
    final persist = ControlledPersist();
    final expiry = DateTime.now().millisecondsSinceEpoch + 60000;
    for (final key in [firstField, secondField]) {
      persist.store[key] = {dataField: key, expiryField: expiry};
    }
    final cache = DiomanCache(
        persist: persist, cachePolicy: DiomanCachePolicy.both, maxEntries: 1);
    for (final key in [firstField, secondField, firstField]) {
      cache.onRequest(cacheOptions(key), RecordingRequestHandler());
      await pumpEvents();
    }
    expect(persist.reads, 3);
  });

  test(
      '[DiomanCache.clear][DiomanCachePersist.read] clear prevents old read from repopulating memory',
      () async {
    final persist = ControlledPersist()..readGate = Completer<dynamic>();
    final cache =
        DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.both);
    final first = RecordingRequestHandler();
    cache.onRequest(cacheOptions(), first);
    cache.clear();
    persist.readGate!.complete({
      dataField: tkOld,
      expiryField: DateTime.now().millisecondsSinceEpoch + 60000
    });
    await pumpEvents();
    persist.readGate = null;
    final second = RecordingRequestHandler();
    cache.onRequest(cacheOptions(), second);
    await pumpEvents();
    expect(second.response, isNull);
    expect(persist.reads, 2);
  });

  test(
      '[DiomanCachePersist.read][DiomanCache.cachePolicy] slow read of an expired entry cannot delete a fresher same-key entry',
      () async {
    final persist = GatedPersist()..gates[1] = Completer<dynamic>();
    final now = DateTime.now().millisecondsSinceEpoch;
    final expired = {dataField: tkOld, expiryField: now - 1000};
    persist.store[cacheKey] = expired;
    final cache =
        DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.both);

    // A：持久化读取被卡住。
    final optionsA = cacheOptions();
    final handlerA = RecordingRequestHandler();
    cache.onRequest(optionsA, handlerA);
    await pumpEvents();
    // B：读到同一个过期条目，清理后走网络并写入新缓存。
    final optionsB = cacheOptions();
    final handlerB = RecordingRequestHandler();
    cache.onRequest(optionsB, handlerB);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(handlerB.calls, 1, reason: 'B 未命中，放行到网络');
    cache.onResponse(
        Response(requestOptions: optionsB, statusCode: 200, data: tkNew),
        RecordingResponseHandler());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect((persist.store[cacheKey] as Map)[dataField], tkNew);

    // A 的慢读取此刻才带着旧的过期条目返回。
    persist.gates[1]!.complete(expired);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(handlerA.calls, 1);

    expect((persist.store[cacheKey] as Map)[dataField], tkNew,
        reason: '持久化里的新条目不能被 A 的过期清理删掉');
    final hit = RecordingRequestHandler();
    cache.onRequest(cacheOptions(), hit);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(hit.response?.data, tkNew, reason: '内存里的新条目也还在');
  });

  test(
      '[DiomanCache.cachePolicy][DiomanCache.clone] cache 深拷贝保留非字符串 Map 键且隔离嵌套修改',
      () async {
    final cache = DiomanCache(
        persist: FakeCachePersist(),
        cachePolicy: DiomanCachePolicy.memo,
        clone: DiomanClonePolicy.deep);
    final options = RequestOptions(path: replayPath, extra: {kKey: replayPath});
    final initial = RequestInterceptorHandler();
    cache.onRequest(options, initial);
    await handlerCompletion(initial);
    final payload = <int, dynamic>{
      1: <int>[2]
    };
    final stored = ResponseInterceptorHandler();
    cache.onResponse(
        Response(requestOptions: options, statusCode: 200, data: payload),
        stored);
    await handlerCompletion(stored);
    (payload[1] as List)[0] = 9;
    final handler = RequestInterceptorHandler();
    cache.onRequest(
        RequestOptions(path: replayPath, extra: {kKey: replayPath}), handler);
    final response = (await handlerCompletion(handler)).data as Response;
    expect(response.data, {
      1: [2]
    });
    cache.dispose();
  });
}
