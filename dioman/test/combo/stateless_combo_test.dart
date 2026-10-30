import '../support/b2_constants.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/invariant_harness.dart';
import '../rule/envs_rule_test.dart'
    show envUrl, overrideUrl, envNested, envTime;

/// 组合请求路径。
const comboPath = '/combo';

/// 组合规则的网络路由。
const comboRoute = '$b2Get:$comboPath';

/// 核对本批插件之间及内核生命周期的交互。
void main() {
  test('[DiomanLoadingApi.activeCount] 并发成功失败各自落定，任何请求都不能遗留括号', () async {
    for (final statuses in [
      [500, 500],
      [500, 200],
      [200, 500]
    ]) {
      final net = FakeNetwork();
      final clock = FakeClock();
      final h = InvariantHarness(net, clock);
      final gates = [Completer<void>(), Completer<void>()];
      net.routes[comboRoute] = [
        for (var i = 0; i < 2; i++)
          FakeReply(status: statuses[i], gate: gates[i].future)
      ];
      final api = testClient(
          network: net,
          clock: clock,
          plugins: [h.loadingPlugin(), ...h.probes()]);
      final a = h.track(1, api.send<Object?>(b2Get, comboPath));
      final b = h.track(2, api.send<Object?>(b2Get, comboPath));
      await flush();
      gates[0].complete();
      await a;
      expect(api.plugin<DiomanLoadingApi>()!.activeCount, 1);
      expect(h.loading.values.single, [true]);
      gates[1].complete();
      await b;
      expect(api.plugin<DiomanLoadingApi>()!.activeCount, 0);
      h.assertAll(api);
    }
  });
  test(
      '[DiomanLoading.stage]'
      '[DiomanLoadingApi.activeCount] credential 等待期间已计数，失败出口均释放自己的括号',
      () async {
    for (final kind in [
      DiomanKind.http,
      DiomanKind.network,
      DiomanKind.timeout,
      DiomanKind.cancel,
      DiomanKind.internal
    ]) {
      final events = <bool>[];
      final gate = Completer<void>();
      final bug = StateError('source failure');
      final api = testClient(plugins: [
        DiomanLoading(onChanged: events.add),
        TestPlugin('credential-wait', stage: DiomanStage.credential,
            handler: (ctx, next) async {
          await ctx.wait(gate.future);
          return next();
        }),
        TestPlugin('source-result',
            stage: DiomanStage.source,
            handler: (ctx, _) async => ctx.fail(DiomanFailure(
                kind: kind, error: kind == DiomanKind.internal ? bug : null)))
      ]);
      final pending = api.send<Object?>(b2Get, comboPath);
      final checked = kind == DiomanKind.internal
          ? expectLater(pending, throwsA(same(bug)))
          : pending.then((r) => expect(r.kind, kind));
      await flush();
      expect(events, [true]);
      expect(api.plugin<DiomanLoadingApi>()!.activeCount, 1);
      // 未参与 loading 的调用不能抢走另一请求的计数。
      final optedOut = api.send<Object?>(b2Get, comboPath,
          call: DiomanCall(options: {DiomanLoading.option: false}));
      final other = kind == DiomanKind.internal
          ? expectLater(optedOut, throwsA(same(bug)))
          : optedOut.then((r) => expect(r.kind, kind));
      gate.complete();
      await Future.wait([checked, other]);
      expect(events, [true, false]);
      expect(api.pending, 0);
      expect(api.plugin<DiomanLoadingApi>()!.activeCount, 0);
    }
  });
  test('[Dioman.extend] 保留非默认 Dio 字段，显式 overrides 最后应用', () {
    final parent = testClient();
    final options = BaseOptions(
        method: b2Post,
        preserveHeaderCase: true,
        contentType: Headers.textPlainContentType,
        validateStatus: (_) => false,
        receiveDataWhenStatusError: false,
        followRedirects: false,
        maxRedirects: 2,
        persistentConnection: false,
        requestEncoder: (_, request) => [1],
        responseDecoder: (_, request, body) => b2Empty,
        listFormat: ListFormat.csv);
    final child = parent.extend(options: options);
    final inherited = child.extend(options: BaseOptions());
    for (final c in [child, inherited]) {
      expect(c.dio.options.method, options.method);
      expect(c.dio.options.preserveHeaderCase, isTrue);
      expect(c.dio.options.contentType, options.contentType);
      expect(c.dio.options.validateStatus(200), isFalse);
      expect(c.dio.options.receiveDataWhenStatusError, isFalse);
      expect(c.dio.options.followRedirects, isFalse);
      expect(c.dio.options.maxRedirects, 2);
      expect(c.dio.options.persistentConnection, isFalse);
      expect(c.dio.options.requestEncoder, same(options.requestEncoder));
      expect(c.dio.options.responseDecoder, same(options.responseDecoder));
      expect(c.dio.options.listFormat, options.listFormat);
    }
  });
  test('[DiomanLoading × DiomanNotify] 多次 next 仅一个 loading 周期与最终通知，I2/I4',
      () async {
    for (final success in [true, false]) {
      final net = FakeNetwork();
      final clock = FakeClock();
      final h = InvariantHarness(net, clock);
      net.routes[comboRoute] = [
        const FakeReply(status: 500),
        FakeReply(status: success ? 200 : 500)
      ];
      final api = testClient(network: net, clock: clock, plugins: [
        h.notifyPlugin(),
        h.loadingPlugin(),
        ...h.probes(),
        TestPlugin('replay', handler: (ctx, next) async {
          ctx.markReplayable();
          await next();
          return next();
        })
      ]);
      final r = await h.track(1, api.send<Object?>(b2Get, comboPath));
      expect(r.ok, success);
      expect(net.sends.length, 2);
      expect(h.loading.values.single, [true, false]);
      expect(h.notifications, success ? isEmpty : {1: 1});
      h.assertAll(api);
    }
  });

  test('[DiomanLoading × DiomanNotify] 共享同一响应的两个逻辑请求按 ctx.id 分开通知', () async {
    final net = FakeNetwork();
    final clock = FakeClock();
    final h = InvariantHarness(net, clock);
    final gate = Completer<void>();
    net.routes[comboRoute] = [FakeReply(status: 500, gate: gate.future)];
    Future<Result>? shared;
    final api = testClient(network: net, clock: clock, plugins: [
      h.loadingPlugin(),
      h.notifyPlugin(),
      ...h.probes(),
      TestPlugin('shared-result',
          stage: DiomanStage.source, handler: (ctx, next) => shared ??= next())
    ]);
    final a = h.track(1, api.send<Object?>(b2Get, comboPath));
    final b = h.track(2, api.send<Object?>(b2Get, comboPath));
    await flush();
    expect(api.plugin<DiomanLoadingApi>()!.activeCount, 2);
    gate.complete();
    final results = await Future.wait([a, b]);
    expect(results.first, same(results.last));
    expect(h.notifications, {1: 1, 2: 1});
    h.assertAll(api);
  });

  test('[DiomanLoading × DiomanNotify] 取消与 source 短路仍成对、无多余通知', () async {
    for (final cancel in [true, false]) {
      final net = FakeNetwork();
      final clock = FakeClock();
      final h = InvariantHarness(net, clock);
      final api = testClient(network: net, clock: clock, plugins: [
        h.loadingPlugin(),
        h.notifyPlugin(),
        ...h.probes(),
        TestPlugin('short', stage: DiomanStage.source, handler: (ctx, _) async {
          if (cancel) ctx.client.cancelAll();
          return ctx.fail(DiomanFailure(
              kind: cancel ? DiomanKind.cancel : DiomanKind.http));
        })
      ]);
      await h.track(1, api.send<Object?>(b2Get, comboPath));
      expect(net.sends, isEmpty);
      expect(h.loading.values.single, [true, false]);
      expect(h.notifications, cancel ? isEmpty : {1: 1});
      h.assertAll(api);
    }
  });

  for (final pair in [
    (true, true, false),
    (true, false, true),
    (false, true, true)
  ]) {
    test('[DiomanRepath × DiomanFilter × DiomanTimeout] 成对整形 $pair 按固定顺序发送',
        () async {
      final net = FakeNetwork();
      final plugins = <DiomanPlugin<Result>>[
        if (pair.$3) DiomanTimeout(probe: () => NetworkQuality.poor),
        if (pair.$2) const DiomanFilter(),
        if (pair.$1) const DiomanRepath()
      ];
      final api = testClient(network: net, plugins: plugins);
      api.dio.options.queryParameters = {b2Id: b2Empty, b2Nil: null};
      await api.send<Object?>(b2Post, b2IdPath,
          data: const {b2Name: b2Empty, b2Keep: 0});
      expect(net.sends.single.options.path, pair.$1 ? '/' : b2IdPath);
      expect(net.sends.single.options.queryParameters,
          pair.$2 ? isEmpty : {b2Nil: null});
      expect(net.sends.single.options.connectTimeout,
          pair.$3 ? const Duration(seconds: 30) : isNull);
      expect(net.sends.single.body,
          pair.$2 ? {b2Keep: 0} : {b2Name: b2Empty, b2Keep: 0});
    });
  }

  test('[Dioman.extend × DiomanEnvs] 先 setup 再显式覆盖，父子与规则模板容器隔离', () {
    final template =
        BaseOptions(baseUrl: envUrl, connectTimeout: envTime, headers: {
      envNested: {
        b2List: [1]
      },
      b2Env: 1
    }, queryParameters: {
      envNested: [1]
    }, extra: {
      envNested: [1]
    });
    final events = <bool>[];
    final parent = testClient(plugins: [
      DiomanLoading(onChanged: events.add),
      DiomanEnvs([EnvRule(rule: () => true, config: template)])
    ]);
    parent.dio.options.baseUrl = overrideUrl;
    final overrides = BaseOptions(
        baseUrl: overrideUrl,
        connectTimeout: const Duration(seconds: 8),
        headers: {
          envNested: {
            b2List: [9]
          }
        },
        queryParameters: {
          envNested: [9]
        },
        extra: {
          envNested: [9]
        });
    final child = parent.extend(options: overrides);
    final inherited = parent.extend();
    expect(inherited.dio.options.baseUrl, envUrl);
    expect(child.dio.options.baseUrl, overrideUrl);
    expect(child.dio.options.connectTimeout, const Duration(seconds: 8));
    expect(child.dio.options.headers[b2Env], 1);
    expect(child.plugin<DiomanLoadingApi>(),
        isNot(same(parent.plugin<DiomanLoadingApi>())));
    (child.dio.options.headers[envNested][b2List] as List).add(10);
    (child.dio.options.queryParameters[envNested] as List).add(10);
    final childExtras = child.dio.options.extra;
    final overrideExtras = overrides.extra;
    final parentExtras = parent.dio.options.extra;
    (childExtras[envNested] as List).add(10);
    expect(parent.dio.options.headers[envNested], {
      b2List: [1]
    });
    expect(template.headers[envNested], {
      b2List: [1]
    });
    expect(overrides.headers[envNested], {
      b2List: [9]
    });
    expect(overrides.queryParameters[envNested], [9]);
    expect(overrideExtras[envNested], [9]);
    expect(parent.dio.options.queryParameters[envNested], [1]);
    expect(parentExtras[envNested], [1]);
    parent.dispose();
    child.dispose();
    inherited.dispose();
  });
}
