import 'package:dioman/src/diagnostics.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/b4_helpers.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';

/// 持久化 I/O 竞态，所有用户等待可取消。
void main() {
  test(
      '[DiomanCachePolicy.both]'
      '[DiomanCachePersist.erase]'
      '[DiomanCachePersist.remove]'
      '[DiomanCachePersist.read] 慢读取被 clear remove dispose 作废，旧读取不回填',
      () async {
    for (final action in [b4LiteralClear, b4LiteralRemove, b4LiteralDispose]) {
      final store = B4Persist()
        ..snapshot = true
        ..readGate = Completer<void>()
        ..values[b4Key] = {
          b4LiteralData: b4LiteralOld,
          b4LiteralExpiresAt: 60000
        };
      final net = FakeNetwork();
      final api = testClient(network: net, plugins: [
        DiomanCache<Result>(persist: store, cachePolicy: DiomanCachePolicy.both)
      ]);
      final cache = api.plugin<DiomanCacheApi>()!;
      final pending =
          api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
      await b4Turn();
      if (action == b4LiteralClear) {
        await cache.clear();
      } else if (action == b4LiteralRemove) {
        await cache.remove(b4Key);
      } else {
        api.eject(DiomanCache.pluginName);
      }
      store.readGate!.complete();
      expect((await pending).data, isNot(b4LiteralOld));
      expect(cache.entryCount, 0);
      expect(cache.pendingWrites, 0);
    }
  });
  test('[DiomanCachePersist.write] clear 等待在途持久化写入后 erase，错误原样且尾链可恢复',
      () async {
    final store = B4Persist()..writeGate = Completer<void>();
    final api = testClient(plugins: [
      DiomanCache<Result>(persist: store, cachePolicy: DiomanCachePolicy.both)
    ]);
    final cache = api.plugin<DiomanCacheApi>()!;
    final pending = api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
    await store.writeStarted.future;
    var cleared = false;
    final clear = cache.clear().then((_) => cleared = true);
    await b4Turn();
    expect(cleared, isFalse);
    store.writeGate!.complete();
    await pending;
    await clear;
    expect(store.values, isEmpty);
    expect(cache.entryCount, 0);
    expect(cache.pendingWrites, 0);
    for (final action in [
      b4LiteralRead,
      b4LiteralWrite,
      b4LiteralRemove,
      'erase'
    ]) {
      final p = B4Persist()..error = StateError('persist');
      final c = testClient(plugins: [
        DiomanCache<Result>(persist: p, cachePolicy: DiomanCachePolicy.persist)
      ]);
      if (action == b4LiteralWrite) {
        p.error = null;
        p.writeGate = Completer<void>();
        final future =
            c.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
        await b4Turn();
        p.error = StateError(b4LiteralWrite);
        final check = expectLater(future, throwsStateError);
        p.writeGate!.complete();
        await check;
      } else if (action == b4LiteralRead) {
        await expectLater(
            c.send<Object?>(b4Get, b4Path, call: b4Call(cache: true)),
            throwsStateError);
      } else if (action == b4LiteralRemove) {
        await expectLater(
            c.plugin<DiomanCacheApi>()!.remove(b4Key), throwsStateError);
      } else {
        await expectLater(
            c.plugin<DiomanCacheApi>()!.clear(), throwsStateError);
      }
      p.error = null;
      await c.plugin<DiomanCacheApi>()!.clear();
      expect(c.plugin<DiomanCacheApi>()!.pendingWrites, 0);
    }
  });
  test('[DiomanCachePersist.read] 旧过期慢读取不得删除较新写入，持久命中按容量提升', () async {
    final store = B4Persist()
      ..snapshot = true
      ..readGate = Completer<void>()
      ..values[b4Key] = {b4LiteralData: b4LiteralOld, b4LiteralExpiresAt: -1};
    final net = FakeNetwork();
    final api = testClient(network: net, plugins: [
      DiomanCache<Result>(
          persist: store, cachePolicy: DiomanCachePolicy.both, maxEntries: 1)
    ]);
    final old = api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
    await b4Turn();
    final gate = store.readGate!;
    store.readGate = null;
    await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
    final saved = store.values[b4Key];
    gate.complete();
    await old;
    expect(store.values[b4Key], saved);
    expect(api.plugin<DiomanCacheApi>()!.pendingWrites, 0);
    for (final key in [b4LiteralA, b4LiteralB]) {
      store.values[key] = {b4LiteralData: key, b4LiteralExpiresAt: 60000};
    }
    for (final key in [b4LiteralA, b4LiteralB, b4LiteralA]) {
      expect(
          (await api.send<Object?>(b4Get, b4Path,
                  call: b4Call(cache: true, key: key)))
              .data,
          key);
      expect(api.plugin<DiomanCacheApi>()!.entryCount, 1);
    }
  });
  test('[DiomanCachePersist.read × DiomanContext.wait] 取消读取、过期清理、尾链、写入均清理订阅',
      () async {
    for (final phase in [
      b4LiteralRead,
      b4LiteralTail,
      b4LiteralRemove,
      b4LiteralWrite
    ]) {
      final store = B4Persist();
      final api = testClient(plugins: [
        DiomanCache<Result>(
            persist: store, cachePolicy: DiomanCachePolicy.persist)
      ]);
      final cache = api.plugin<DiomanCacheApi>()!;
      if (phase == b4LiteralRemove) {
        store.values[b4Key] = {
          b4LiteralData: b4LiteralOld,
          b4LiteralExpiresAt: -1
        };
        store.removeGate = Completer<void>();
      }
      if (phase == b4LiteralRead) {
        store.readGate = Completer<void>();
      }
      if (phase == b4LiteralWrite || phase == b4LiteralTail) {
        store.writeGate = Completer<void>();
      }
      Future<DiomanResponse<Object?>>? first;
      if (phase == b4LiteralTail) {
        first = api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
        await store.writeStarted.future;
      }
      final pending =
          api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
      await b4Turn();
      api.cancelAll();
      expect((await pending).kind, DiomanKind.cancel);
      store.readGate?.complete();
      store.removeGate?.complete();
      store.writeGate?.complete();
      if (first != null) {
        expect((await first).kind, DiomanKind.cancel);
      }
      await b4Turn();
      expect(cache.pendingWrites, 0);
      expect(api.cancellationSubscriptions, 0);
    }
  });
  test(
      '[DiomanClonePolicy.deep][DiomanFailure.data]'
      '[DiomanCache.clone] 写入快照隔离来源和返回值，扩展工厂保留标记', () async {
    final body = <int, dynamic>{
      1: <int>[2]
    };
    final source = TestPlugin(b4LiteralSource,
        stage: DiomanStage.source,
        handler: (ctx, next) async =>
            ctx.fail(DiomanFailure(kind: DiomanKind.ok, data: body)));
    final api = testClient(plugins: [
      const DiomanCache<Result>(clone: DiomanClonePolicy.deep),
      source
    ]);
    final first =
        await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
    (body[1] as List)[0] = 9;
    (first.data as Map)[1][0] = 7;
    expect(
        (await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true)))
            .data,
        {
          1: [2]
        });
  });
}
