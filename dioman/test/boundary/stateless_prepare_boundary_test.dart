import '../support/pipeline/b2_constants.dart';
import 'dart:async';
import 'package:dioman/pipeline.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/pipeline/helpers.dart';
import '../support/pipeline/fake_network.dart';
import '../rule/stateless_prepare_rule_test.dart' show preparePlain;

/// 验证准备阶段的边界、输入不变与错误身份。
void main() {
  test('[DiomanTimeouts.connect] 档位补丁送达 adapter，连接超时按 timeout 归类', () async {
    final net = FakeNetwork();
    net.failOn[1] = DioException(
        requestOptions: RequestOptions(path: preparePlain),
        type: DioExceptionType.connectionTimeout);
    final api = testClient(
        network: net,
        plugins: [DiomanTimeout(probe: () => NetworkQuality.poor)]);
    final result = await api.send<Object?>(b2Get, preparePlain);
    expect(
        net.sends.single.options.connectTimeout, const Duration(seconds: 30));
    expect(result.kind, DiomanKind.timeout);
  });
  test('[DiomanRepath.pattern] URL 只处理路径，缺键、无捕获和空捕获保持原样', () async {
    final net = FakeNetwork();
    final api = testClient(network: net, plugins: [const DiomanRepath()]);
    const url = 'https://example.test:8888/{id}?literal={id}#:{id}';
    await api.send<Object?>(b2Get, url, query: {b2Id: 1});
    expect(net.sends.last.options.path,
        'https://example.test:8888/1?literal={id}#:{id}');
    for (final path in ['/missing/{id}', '/plain']) {
      await api.send<Object?>(b2Get, path);
      expect(net.sends.last.options.path, path);
    }
    for (final pattern in [
      RegExp('plain'),
      RegExp(r'(a)?(b)?plain'),
      RegExp(r'()plain')
    ]) {
      await api.send<Object?>(b2Get, preparePlain,
          call: DiomanCall(options: {
            DiomanRepath.option: DiomanRepathOptions(pattern: pattern)
          }));
      expect(net.sends.last.options.path, preparePlain);
    }
    await api
        .send<Object?>(b2Get, b2IdPath, query: {b2Id: null}, data: {b2Id: 2});
    expect(net.sends.last.options.path, '/null');
    expect(net.sends.last.options.data, {b2Id: 2});
  });

  test('[DiomanRepath.pattern] 无路径绝对 URL 的 query 与 fragment 不参与替换', () async {
    final net = FakeNetwork();
    final api = testClient(network: net, plugins: [const DiomanRepath()]);
    for (final url in [
      'https://example.test?next=/{id}',
      'https://example.test#next=/{id}',
    ]) {
      await api.send<Object?>(b2Get, url, query: {b2Id: 1});
      expect(net.sends.last.options.path, url);
      expect(net.sends.last.options.queryParameters, {b2Id: 1});
    }
  });

  test('[DiomanFilter] FormData、Stream 和非 Map 原样；无剔除不打补丁', () async {
    final net = FakeNetwork();
    DiomanRequest? before;
    DiomanRequest? after;
    final api = testClient(network: net, plugins: [
      TestPlugin('before',
          stage: DiomanStage.prepare,
          enforce: DiomanEnforce.pre, handler: (ctx, next) {
        before = ctx.request;
        return next();
      }),
      const DiomanFilter(),
      TestPlugin('after', stage: DiomanStage.prepare, handler: (ctx, next) {
        after = ctx.request;
        return next();
      })
    ]);
    for (final data in [
      null,
      'text',
      const {b2Zero: 0},
      FormData.fromMap({b2X: b2Empty}),
      Stream<List<int>>.value([1, 2])
    ]) {
      await api.send<Object?>(b2Post, preparePlain, data: data);
      expect(after, same(before));
      expect(after!.data, same(data));
    }
    await api.send<Object?>(b2Get, preparePlain, query: {b2X: null});
    expect(after, isNot(same(before)));
    expect(before!.query, {b2X: null});
  });

  test('[DiomanFilter.predicate] 判定错误按原对象抛出，谓词每字段只执行一次', () async {
    final error = StateError('predicate sentinel');
    final api =
        testClient(plugins: [DiomanFilter(predicate: (_, v) => throw error)]);
    await expectLater(api.send<Object?>(b2Get, preparePlain, query: {b2X: 1}),
        throwsA(same(error)));
    expect(api.pending, 0);
    final visits = <String>[];
    final counted = testClient(plugins: [
      DiomanFilter(predicate: (k, v) {
        visits.add(k);
        return false;
      })
    ]);
    await counted
        .send<Object?>(b2Post, preparePlain, query: {b2Q: 1}, data: {b2B: 2});
    expect(visits, [b2Q, b2B]);
  });

  test('[DiomanTimeout.probe] 缺档无补丁，空档保留请求超时，probe 错误原样抛出', () async {
    final net = FakeNetwork();
    final api = testClient(network: net, plugins: [
      DiomanTimeout(probe: () => NetworkQuality.none, timeouts: const {})
    ]);
    await api.send<Object?>(b2Get, preparePlain);
    expect(net.sends.single.options.connectTimeout, isNull);
    api.eject(DiomanTimeout.pluginName);
    api.use(DiomanTimeout(
        probe: () => NetworkQuality.none,
        timeouts: const {NetworkQuality.none: DiomanTimeouts()}));
    await api.send<Object?>(b2Get, preparePlain);
    expect(net.sends.last.options.connectTimeout, isNull);
    final error = StateError('probe sentinel');
    final broken =
        testClient(plugins: [DiomanTimeout(probe: () => throw error)]);
    await expectLater(
        broken.send<Object?>(b2Get, preparePlain), throwsA(same(error)));
  });

  test('[resolveOption] 每个插件拒绝未知请求选项类型', () async {
    final keys = [
      DiomanLoading.option,
      DiomanNotify.option,
      DiomanRepath.option,
      DiomanFilter.option,
      DiomanTimeout.option
    ];
    final api = testClient(plugins: [
      DiomanLoading(onChanged: (_) {}),
      DiomanNotify(notify: (_, r) {}),
      const DiomanRepath(),
      const DiomanFilter(),
      DiomanTimeout(probe: () => NetworkQuality.good)
    ]);
    for (final key in keys) {
      await expectLater(
          api.send<Object?>(b2Get, preparePlain,
              call: DiomanCall(options: {key: 123})),
          throwsArgumentError);
    }
  });
}
