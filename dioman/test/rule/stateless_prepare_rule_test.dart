import '../support/b2_constants.dart';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';
import '../support/fake_network.dart';

/// 共用带三种占位符的路径。
const preparePath = '/{id}/:name/[id]';

/// 共用请求路径。
const preparePlain = '/plain';

/// 基础超时。
const prepareBase = Duration(seconds: 4);

/// 覆盖超时。
const prepareOverride = Duration(seconds: 7);

/// 验证三个 prepare 插件的规则与请求覆盖。
void main() {
  test('[DiomanRepath] 三语法、query 优先、重复替换、编码和默认 query 消费', () async {
    final net = FakeNetwork();
    final api = testClient(network: net, plugins: [const DiomanRepath()]);
    api.dio.options.queryParameters = {b2Id: b2EncodedInput};
    final body = {b2Id: b2Body, b2Name: b2ChineseInput, b2Keep: 0};
    await api.send<Object?>(b2Post, preparePath, data: body);
    final sent = net.sends.single.options;
    final id = Uri.encodeComponent(b2EncodedInput);
    expect(sent.path, '/$id/${Uri.encodeComponent('中文 空格')}/$id');
    expect(sent.queryParameters, isEmpty);
    expect(sent.data, {b2Id: b2Body, b2Keep: 0});
    expect(body, containsPair(b2Name, b2ChineseInput));
    expect(api.dio.options.queryParameters, contains(b2Id));
  });

  test(
      '[DiomanRepath.defaultPattern][DiomanRepath.enabled][DiomanRepath.removeKey][DiomanRepathOptions.enabled][DiomanRepathOptions.removeKey]'
      '[DiomanRepath.option] 开关、字段继承、自定义模式与保留来源', () async {
    final net = FakeNetwork();
    final plugin = DiomanRepath(pattern: RegExp(r'\$(\w+)'), removeKey: false);
    final api = testClient(network: net, plugins: [plugin]);
    for (final option in [null, true, const DiomanRepathOptions()]) {
      await api.send<Object?>(b2Get, r'/$id',
          query: {b2Id: 2},
          call: DiomanCall(options: {DiomanRepath.option: option}));
      expect(net.sends.last.options.path, '/2');
      expect(net.sends.last.options.queryParameters, {b2Id: 2});
    }
    for (final option in [false, const DiomanRepathOptions(enabled: false)]) {
      await api.send<Object?>(b2Get, r'/$id',
          query: {b2Id: 2},
          call: DiomanCall(options: {DiomanRepath.option: option}));
      expect(net.sends.last.options.path, r'/$id');
    }
    await api.send<Object?>(b2Get, b2IdPath,
        query: {b2Id: 3},
        call: DiomanCall(options: {
          DiomanRepath.option: DiomanRepathOptions(
              pattern: DiomanRepath.defaultPattern, removeKey: true)
        }));
    expect(net.sends.last.options.path, '/3');
    expect(net.sends.last.options.queryParameters, isEmpty);
  });

  test('[DiomanFilter.defaultPredicate] C9 剔除空值与 NaN，保留零 false 和嵌套字段',
      () async {
    final net = FakeNetwork();
    final api = testClient(network: net, plugins: [const DiomanFilter()]);
    final fields = {
      b2Nil: null,
      b2Nan: double.nan,
      'blank': ' \t',
      'empty': b2Empty,
      b2Zero: 0,
      b2False: false,
      b2Nested: {b2Nil: null},
      b2List: <int>[]
    };
    api.dio.options.queryParameters = Map.of(fields);
    await api.send<Object?>(b2Post, preparePlain,
        data: Map.unmodifiable(fields));
    final expected = {
      b2Zero: 0,
      b2False: false,
      b2Nested: {b2Nil: null},
      b2List: <int>[]
    };
    expect(net.sends.single.options.queryParameters, expected);
    expect(net.sends.single.body, expected);
    expect(fields.keys, containsAll([b2Nan, b2Nil]));
    expect(api.dio.options.queryParameters, contains(b2Nil));
  });

  test(
      '[DiomanFilter.enabled][DiomanFilter.ignoreKeys][DiomanFilter.ignoreValues][DiomanFilterOptions.enabled][DiomanFilterOptions.ignoreKeys][DiomanFilterOptions.ignoreValues][DiomanFilterOptions.predicate]'
      '[DiomanFilter.option] 豁免并集、谓词覆盖与空字段继承', () async {
    final net = FakeNetwork();
    final api = testClient(network: net, plugins: [
      const DiomanFilter(ignoreKeys: ['a'], ignoreValues: [b2Empty])
    ]);
    final query = {'a': null, b2B: null, 'c': b2Empty, 'd': b2Blank, b2Drop: 9};
    await api.send<Object?>(b2Post, preparePlain,
        query: query,
        data: query,
        call: DiomanCall(options: {
          DiomanFilter.option: DiomanFilterOptions(
              ignoreKeys: [b2B],
              ignoreValues: [b2Blank],
              predicate: (k, v) => k == b2Drop)
        }));
    final kept = Map.of(query)..remove(b2Drop);
    expect(net.sends.last.options.queryParameters, kept);
    expect(net.sends.last.body, kept);
    for (final option in [null, true, const DiomanFilterOptions()]) {
      await api.send<Object?>(b2Get, preparePlain,
          query: {b2X: null},
          call: DiomanCall(options: {DiomanFilter.option: option}));
      expect(net.sends.last.options.queryParameters, isEmpty);
    }
    for (final option in [false, const DiomanFilterOptions(enabled: false)]) {
      await api.send<Object?>(b2Get, preparePlain,
          query: {b2X: null},
          call: DiomanCall(options: {DiomanFilter.option: option}));
      expect(net.sends.last.options.queryParameters, {b2X: null});
    }
  });

  test(
      '[NetworkQuality.excellent]'
      '[DiomanTimeout.defaultConnect]'
      '[DiomanTimeout.defaultTimeouts]'
      '[DiomanTimeout.timeouts] 默认四档和 probe 每请求一次', () async {
    final net = FakeNetwork();
    var tier = NetworkQuality.excellent;
    var probes = 0;
    final api = testClient(network: net, plugins: [
      DiomanTimeout(probe: () {
        probes++;
        return tier;
      })
    ]);
    api.dio.options.receiveTimeout = prepareBase;
    api.dio.options.sendTimeout = prepareBase;
    for (final quality in NetworkQuality.values) {
      tier = quality;
      await api.send<Object?>(b2Get, preparePlain);
      expect(net.sends.last.options.connectTimeout,
          Duration(seconds: [10, 15, 30, 10][quality.index]));
      expect(net.sends.last.options.receiveTimeout, prepareBase);
      expect(net.sends.last.options.sendTimeout, prepareBase);
    }
    expect(probes, 4);
  });

  test(
      '[DiomanTimeout.enabled][DiomanTimeoutOptions.enabled]'
      '[DiomanTimeout.option] 按档并集、单档替换、非空覆盖和请求关闭', () async {
    final net = FakeNetwork();
    var tier = NetworkQuality.good;
    final api = testClient(network: net, plugins: [
      DiomanTimeout(probe: () => tier, timeouts: const {
        NetworkQuality.good: DiomanTimeouts(connect: prepareBase),
        NetworkQuality.poor: DiomanTimeouts(connect: prepareBase)
      })
    ]);
    api.dio.options.connectTimeout = prepareBase;
    final override = const DiomanTimeoutOptions(timeouts: {
      NetworkQuality.poor:
          DiomanTimeouts(receive: prepareOverride, send: prepareOverride)
    });
    await api.send<Object?>(b2Get, preparePlain,
        call: DiomanCall(options: {DiomanTimeout.option: override}));
    expect(net.sends.last.options.connectTimeout, prepareBase);
    tier = NetworkQuality.poor;
    await api.send<Object?>(b2Get, preparePlain,
        call: DiomanCall(options: {DiomanTimeout.option: override}));
    expect(net.sends.last.options.connectTimeout, prepareBase);
    expect(net.sends.last.options.receiveTimeout, prepareOverride);
    expect(net.sends.last.options.sendTimeout, prepareOverride);
    for (final option in [false, const DiomanTimeoutOptions(enabled: false)]) {
      await api.send<Object?>(b2Get, preparePlain,
          call: DiomanCall(options: {DiomanTimeout.option: option}));
      expect(net.sends.last.options.receiveTimeout, isNull);
    }
    for (final option in [true, const DiomanTimeoutOptions()]) {
      await api.send<Object?>(b2Get, preparePlain,
          call: DiomanCall(options: {DiomanTimeout.option: option}));
      expect(net.sends.last.options.connectTimeout, prepareBase);
    }
  });

  test(
      '[DiomanEnvs.name][DiomanFilter.name][DiomanLoading.name][DiomanNotify.enabled][DiomanNotify.name][DiomanNotify.stage][DiomanPlugin.name][DiomanRepath.name][DiomanRepath.stage][DiomanTimeout.name][DiomanTimeout.stage]'
      '[DiomanFilter.pluginName]'
      '[DiomanRepath.pluginName]'
      '[DiomanLoading.setup]'
      '[DiomanNotify.setup]'
      '[DiomanRepath.setup]'
      '[DiomanFilter.setup]'
      '[DiomanTimeout.setup]'
      '[DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键', () async {
    final plugins = <DiomanPlugin<Result>>[
      DiomanLoading(onChanged: (_) {}),
      DiomanNotify(notify: (_, r) {}),
      const DiomanRepath(),
      const DiomanFilter(),
      DiomanTimeout(probe: () => NetworkQuality.none),
      const DiomanEnvs([])
    ];
    final names = [
      'loading',
      b2NotifyLabel,
      'repath',
      'filter',
      'timeout',
      'envs'
    ];
    for (var i = 0; i < plugins.length; i++) {
      expect(plugins[i].name, 'dioman:${names[i]}');
      expect(plugins[i].enabled, isTrue);
    }
    expect(plugins.take(2).every((p) => p.stage == DiomanStage.outer), isTrue);
    expect(plugins.skip(2).take(3).every((p) => p.stage == DiomanStage.prepare),
        isTrue);
    final api = testClient(plugins: plugins.reversed.toList());
    expect(api.inspect().map((e) => e.$2), plugins.take(5).map((p) => p.name));
    final off = testClient(plugins: [
      DiomanLoading(onChanged: (_) => fail(b2Off), enabled: false),
      DiomanNotify(notify: (_, r) => fail(b2Off), enabled: false),
      const DiomanRepath(enabled: false),
      const DiomanFilter(enabled: false),
      DiomanTimeout(probe: () => throw StateError(b2Off), enabled: false),
      DiomanEnvs(
          [EnvRule(rule: () => throw StateError(b2Off), config: BaseOptions())],
          enabled: false)
    ]);
    expect(off.inspect(), isEmpty);
    expect(off.plugin<DiomanLoadingApi>(), isNull);
    await off.send<Object?>(b2Get, preparePath, query: {b2Id: null});
    await off.send<Object?>(b2Get, preparePath,
        query: {b2Id: null},
        call: DiomanCall(options: {
          DiomanLoading.option: true,
          DiomanNotify.option: true,
          DiomanRepath.option: const DiomanRepathOptions(enabled: true),
          DiomanFilter.option: const DiomanFilterOptions(enabled: true),
          DiomanTimeout.option: const DiomanTimeoutOptions(enabled: true)
        }));
  });
}
