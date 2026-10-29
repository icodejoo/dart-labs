import 'package:dioman/src/diagnostics.dart';
import 'dart:async';
import 'dart:io';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/b4_helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';

/// 选项和判定回调的公开边界。
void main() {
  test(
      '[DiomanCache.enabled][DiomanCache.name][DiomanCache.pluginName][DiomanCache.stage][DiomanCacheOptions.enabled][DiomanMock.enabled][DiomanMock.name][DiomanMock.pluginName][DiomanMock.stage][DiomanMockOptions.enabled][DiomanOffline.enabled][DiomanOffline.name][DiomanOffline.option][DiomanOffline.pluginName][DiomanOffline.stage][DiomanOfflineOptions.enabled][DiomanShare.enabled][DiomanShare.name][DiomanShare.pluginName][DiomanShare.stage][DiomanShareOptions.enabled]'
      '[DiomanCache.setup]'
      '[DiomanMock.setup]'
      '[DiomanOffline.setup]'
      '[DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项', () async {
    final stream = StreamController<bool>.broadcast(sync: true);
    addTearDown(stream.close);
    final plugins = <DiomanPlugin<Result>>[
      const DiomanMock<Result>(enabled: false),
      const DiomanShare<Result>(enabled: false),
      const DiomanCache<Result>(enabled: false),
      DiomanOffline<Result>(
          enabled: false,
          isOnline: () => true,
          onConnectivityChanged: stream.stream)
    ];
    final api = testClient(plugins: plugins);
    expect(plugins.map((p) => p.stage), everyElement(DiomanStage.source));
    expect(api.inspect(), isEmpty);
    final installed = testClient(plugins: [
      DiomanOffline<Result>(
          isOnline: () => true, onConnectivityChanged: stream.stream),
      const DiomanCache<Result>(),
      const DiomanShare<Result>(),
      const DiomanMock<Result>()
    ]);
    expect(installed.inspect().map((e) => e.$2), [
      DiomanMock.pluginName,
      DiomanShare.pluginName,
      DiomanCache.pluginName,
      DiomanOffline.pluginName
    ]);
    final keys = [
      DiomanMock.option,
      DiomanShare.option,
      DiomanCache.option,
      DiomanOffline.option
    ];
    for (final key in keys) {
      await expectLater(
          installed.send<Object?>(b4Get, b4Path,
              call: DiomanCall(options: {key: 1234})),
          throwsArgumentError);
    }
    for (final values in [
      <Object>[
        const DiomanMockOptions(enabled: false),
        const DiomanShareOptions(enabled: false),
        const DiomanCacheOptions(enabled: false),
        const DiomanOfflineOptions(enabled: false)
      ],
      <Object>[false, false, false, false]
    ]) {
      expect(
          (await installed.send<Object?>(b4Get, b4Path,
                  call: DiomanCall(options: Map.fromIterables(keys, values))))
              .ok,
          isTrue);
    }
    installed.dispose();
  });
  test(
      '[DiomanMockOptions.fallbackWhen][DiomanMockOptions.mockUrl][DiomanMockOptions.routes]'
      '[DiomanMock.option] 请求级路由地址覆盖，network 默认回落，判定抛错原样', () async {
    final net = FakeNetwork()
      ..routes['GET:https://mock.test$b4Path'] = [
        FakeReply(
            error: DioException(
                requestOptions: RequestOptions(path: b4Path),
                type: DioExceptionType.connectionError,
                error: const SocketException('offline')))
      ];
    final api = testClient(network: net, plugins: [const DiomanMock<Result>()]);
    expect(
        (await api.send<Object?>(b4Get, b4Path,
                call: b4Call(
                    mock: const DiomanMockOptions(
                        mockUrl: b4LiteralHttpsMockTest))))
            .ok,
        isTrue);
    expect(net.sends.length, 2);
    expect(
        (await api.send<Object?>(b4Get, b4Path,
                call: b4Call(
                    mock: DiomanMockOptions(routes: {b4Route: (_) => 42}))))
            .data,
        42);
    await expectLater(
        api.send<Object?>(b4Get, b4Path,
            call: b4Call(
                mock: DiomanMockOptions(
                    mockUrl: b4LiteralHttpsMockTest,
                    fallbackWhen: (_) => throw StateError(b4LiteralEmpty)))),
        throwsStateError);
    final token = CancelToken()..cancel();
    expect(
        (await api.send<Object?>(b4Get, b4Path,
                call: DiomanCall(cancelToken: token)))
            .kind,
        DiomanKind.cancel);
  });
  test(
      '[DiomanCacheOptions.cachePolicy]'
      '[DiomanCache.option × DiomanShare.option] key false 方法否决与自定义方法和 shouldStore',
      () async {
    final net = FakeNetwork();
    final api = testClient(
        network: net,
        plugins: [const DiomanShare<Result>(), const DiomanCache<Result>()]);
    for (var i = 0; i < 2; i++) {
      await api.send<Object?>(b4Get, b4Path,
          call: b4Call(cache: true, share: true, key: false));
      await api.send<Object?>(b4LiteralPOST, b4Path,
          call: b4Call(cache: true, share: true));
    }
    expect(net.sends.length, 4);
    await api.send<Object?>(b4LiteralPOST, b4Path,
        call: b4Call(
            cache: DiomanCacheOptions(
                shouldCache: (_) => true, shouldStore: (_) => false),
            share: const DiomanShareOptions(
                methods: {b4LiteralPOST},
                retries: 0,
                interval: Duration.zero)));
    expect(api.plugin<DiomanCacheApi>()!.entryCount, 0);
    for (var i = 0; i < 2; i++) {
      await api.send<Object?>(b4LiteralPOST, b4Path,
          call: b4Call(cache: DiomanCacheOptions(shouldCache: (_) => true)));
    }
    expect(net.sends.length, 6, reason: '请求判定明确允许 POST 后真正缓存');
    await api.plugin<DiomanCacheApi>()!.clear();
    await expectLater(
        api.send<Object?>(b4Get, b4Path,
            call: b4Call(
                cache: DiomanCacheOptions(
                    shouldCache: (_) => throw StateError(b4LiteralEmpty)))),
        throwsStateError);
    await expectLater(
        api.send<Object?>(b4Get, b4Path,
            call: b4Call(
                cache: DiomanCacheOptions(
                    shouldStore: (_) => throw StateError(b4LiteralEmpty)))),
        throwsStateError);
    await expectLater(
        api.send<Object?>(b4Get, b4Path,
            call: b4Call(
                cache: const DiomanCacheOptions(
                    cachePolicy: DiomanCachePolicy.persist))),
        throwsStateError);
  });
  test(
      '[DiomanClonePolicy.shallow]'
      '[DiomanCache.clone] deep 保留非字符串键隔离嵌套，shallow List 标量及非法策略', () async {
    for (final body in <Object>[
      {
        1: [2]
      },
      [
        1,
        {b4LiteralN: 0}
      ],
      7
    ]) {
      final source = TestPlugin(b4LiteralSource,
          stage: DiomanStage.source,
          handler: (ctx, next) async =>
              ctx.fail(DiomanFailure(kind: DiomanKind.ok, data: body)));
      for (final clone in [DiomanClonePolicy.deep, DiomanClonePolicy.shallow]) {
        final api =
            testClient(plugins: [DiomanCache<Result>(clone: clone), source]);
        final a =
            await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
        final b =
            await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
        expect(b.data, body);
        if (body is! int) {
          expect(identical(a.data, b.data), isFalse);
        }
        if (body is Map && clone == DiomanClonePolicy.deep) {
          (a.data as Map)[1][0] = 9;
          expect((b.data as Map)[1], [2]);
        }
      }
    }
    final api =
        testClient(plugins: [const DiomanCache<Result>(clone: 'invalid')]);
    await expectLater(
        api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true)),
        throwsArgumentError);
  });
  test('[DiomanOffline.shouldQueue] 判定抛错原样、流错误隔离与订阅前取消', () async {
    final stream = StreamController<bool>.broadcast(sync: true);
    addTearDown(stream.close);
    final logs = <String>[];
    final api = testClient(debug: logs.add, plugins: [
      DiomanOffline<Result>(
          isOnline: () => false, onConnectivityChanged: stream.stream)
    ]);
    stream.addError(StateError('通知'));
    await b4Turn();
    expect(logs, isNotEmpty);
    await expectLater(
        api.send<Object?>(b4Get, b4Path,
            call: b4Call(
                offline: DiomanOfflineOptions(
                    shouldQueue: (_) => throw StateError(b4LiteralEmpty)))),
        throwsStateError);
    final token = CancelToken();
    final cancelled = testClient(plugins: [
      TestPlugin(b4LiteralCancel, handler: (ctx, next) async {
        ctx.state.cancel();
        return next();
      }),
      DiomanOffline<Result>(
          isOnline: () => false, onConnectivityChanged: stream.stream)
    ]);
    expect(
        (await cancelled.send<Object?>(b4Get, b4Path,
                call: DiomanCall(cancelToken: token)))
            .kind,
        DiomanKind.cancel);
    expect(cancelled.plugin<DiomanOfflineApi>()!.pending, 0);
    api.dispose();
    cancelled.dispose();
  });
  test(
      '[DiomanShareOptions.interval]'
      '[DiomanShare.retries] retry 间隔取消与耗尽释放条目，dispose 所有策略清表', () async {
    for (final p in DiomanSharePolicy.values) {
      final gate = Completer<void>();
      final clock = FakeClock();
      final net = FakeNetwork()
        ..routes[b4Route] = [FakeReply(status: 500, gate: gate.future)];
      final api = testClient(
          network: net,
          clock: clock,
          plugins: [const DiomanShare<Result>(retries: 1, interval: b4Tick)]);
      final a = api.send<Object?>(b4Get, b4Path, call: b4Call(share: p));
      await b4Turn();
      api.eject(DiomanShare.pluginName);
      expect((await a).kind, DiomanKind.cancel);
      gate.complete();
      await b4Turn();
      expect(clock.pendingTimers, 0);
    }
    final clock = FakeClock();
    final net = FakeNetwork()..routes[b4Route] = [const FakeReply(status: 500)];
    final api = testClient(
        clock: clock,
        network: net,
        plugins: [const DiomanShare<Result>(interval: b4Tick)]);
    final a = api.send<Object?>(b4Get, b4Path,
        call: b4Call(share: DiomanSharePolicy.retry));
    await b4Turn();
    api.cancelAll();
    expect((await a).kind, DiomanKind.cancel);
    await b4Turn();
    expect(clock.pendingTimers, 0);
    final b = api.send<Object?>(b4Get, b4Path,
        call: b4Call(
            share: const DiomanShareOptions(
                policy: DiomanSharePolicy.retry,
                interval: Duration.zero,
                retries: 1)));
    expect((await b).httpStatus, 500);
    expect(api.plugin<DiomanShareApi>()!.activeEntries, 0);
  });
}
