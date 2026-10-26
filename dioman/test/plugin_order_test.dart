// 声明式插件顺序测试：默认 install 顺序不变、稳定拓扑排序、
// 重复名/环/缺失依赖报错、动态插入后的校验。
// Declarative plugin ordering: default install order unchanged, stable
// topological sort, duplicate/cycle/missing-dependency errors, validation on
// dynamic insertion.
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

import 'support/fake_cache_persist.dart';

/// 改动前 [Dioman.install] 的固定顺序（逐字照抄，作为回归基线）。
const _canonical = <String>[
  'dioman:envs',
  'dioman:timeout',
  'dioman:repath',
  'dioman:filter',
  'dioman:qid',
  'dioman:cache',
  'dioman:offline',
  'dioman:share',
  'dioman:mock',
  'dioman:cancel',
  'dioman:loading',
  'dioman:auth',
  'dioman:retry',
  'dioman:breaker',
  'dioman:log',
  'dioman:normalize',
];

class _TokenManager implements DiomanTokenManager {
  @override
  String? get accessToken => 't';
  @override
  String? get refreshToken => 'r';
  @override
  bool get canRefresh => true;
  @override
  void clear() {}
}

/// 按 [_canonical] 顺序构造全部 16 个内置插件。
List<DiomanPlugin> _allBuiltins() => [
      DiomanEnvs(const []),
      DiomanTimeout(probe: () => NetworkQuality.excellent),
      DiomanRepath(),
      const DiomanFilter(),
      const DiomanKey(),
      DiomanCache(persist: FakeCachePersist()),
      DiomanOffline(
        isOnline: () => true,
        onConnectivityChanged: const Stream<bool>.empty(),
      ),
      DiomanShare(),
      DiomanMock(enabled: false),
      DiomanCancel(),
      DiomanLoading(onChanged: (_) {}),
      DiomanAuth(
        tokenManager: _TokenManager(),
        onRefresh: (_, __) async {},
        onAccessExpired: (_, __) async {},
      ),
      DiomanRetry(),
      DiomanBreaker(),
      DiomanLog(writer: (m, {error}) {}),
      const DiomanNormalize(),
    ];

/// 可声明顺序约束的测试插件。
class _P extends DiomanPlugin {
  _P(
    this._name, {
    this.before = const {},
    this.after = const {},
    this.requires = const {},
  });
  final String _name;
  final Set<String> before;
  final Set<String> after;
  final Set<String> requires;

  @override
  String get name => _name;

  @override
  DiomanPluginOrder get ordering =>
      DiomanPluginOrder(before: before, after: after, requires: requires);
}

List<String> _names(Iterable<DiomanPlugin> ps) => [for (final p in ps) p.name];

void main() {
  group('默认 install 顺序不变', () {
    test('全部 16 个插件的安装顺序与改动前逐一相同', () {
      final dio = Dio();
      final handle = Dioman.install(
        dio,
        envs: DiomanEnvs(const []),
        timeout: DiomanTimeout(probe: () => NetworkQuality.excellent),
        repath: DiomanRepath(),
        filter: const DiomanFilter(),
        key: const DiomanKey(),
        cache: DiomanCache(persist: FakeCachePersist()),
        offline: DiomanOffline(
          isOnline: () => true,
          onConnectivityChanged: const Stream<bool>.empty(),
        ),
        share: DiomanShare(),
        mock: DiomanMock(enabled: false),
        cancel: DiomanCancel(),
        loading: DiomanLoading(onChanged: (_) {}),
        auth: DiomanAuth(
          tokenManager: _TokenManager(),
          onRefresh: (_, __) async {},
          onAccessExpired: (_, __) async {},
        ),
        retry: DiomanRetry(),
        breaker: DiomanBreaker(),
        log: DiomanLog(writer: (m, {error}) {}),
        normalize: const DiomanNormalize(),
      );
      expect(_names(handle.plugins), _canonical);
      expect(_names(dio.interceptors.whereType<DiomanPlugin>()), _canonical);
      handle.dispose();
    });

    test('内置插件任意子集按规范顺序排序都是恒等（2^16 个子集）', () {
      final all = _allBuiltins();
      for (var mask = 0; mask < (1 << all.length); mask++) {
        final subset = [
          for (var i = 0; i < all.length; i++)
            if ((mask & (1 << i)) != 0) all[i],
        ];
        final sorted = Dioman.sort(subset);
        expect(_names(sorted), _names(subset), reason: 'mask=$mask');
      }
    });

    test('内置插件乱序输入，排序后满足 README 的全部硬约束', () {
      final all = _allBuiltins().reversed.toList();
      final names = _names(Dioman.sort(all));
      int at(String n) => names.indexOf(n);
      expect(at('dioman:qid'), lessThan(at('dioman:cache')));
      expect(at('dioman:qid'), lessThan(at('dioman:share')));
      expect(at('dioman:repath'), lessThan(at('dioman:qid')));
      expect(at('dioman:filter'), lessThan(at('dioman:qid')));
      expect(at('dioman:cache'), lessThan(at('dioman:offline')));
      for (final n in ['dioman:share', 'dioman:cancel', 'dioman:loading']) {
        expect(at('dioman:offline'), lessThan(at(n)));
      }
      for (final n in ['dioman:cache', 'dioman:share', 'dioman:mock']) {
        expect(at(n), lessThan(at('dioman:cancel')));
        expect(at(n), lessThan(at('dioman:loading')));
      }
      for (final a in ['dioman:cancel', 'dioman:loading']) {
        expect(at(a), lessThan(at('dioman:auth')));
        expect(at(a), lessThan(at('dioman:retry')));
      }
      expect(at('dioman:retry'), lessThan(at('dioman:breaker')));
      expect(at('dioman:normalize'), names.length - 1);
    });

    test('install 的 plugins 参数：自定义插件按约束插入内置链', () {
      final dio = Dio();
      final handle = Dioman.install(
        dio,
        key: const DiomanKey(),
        cache: DiomanCache(persist: FakeCachePersist()),
        log: DiomanLog(writer: (m, {error}) {}),
        plugins: [
          _P('custom-after-key',
              after: {'dioman:qid'}, before: {'dioman:cache'}),
          _P('free'),
        ],
      );
      expect(_names(handle.plugins), [
        'dioman:qid',
        'custom-after-key',
        'dioman:cache',
        'dioman:log',
        'free',
      ]);
      handle.dispose();
    });
  });

  group('稳定拓扑排序', () {
    test('无约束时保持输入顺序', () {
      final ps = [_P('c'), _P('a'), _P('b')];
      expect(_names(Dioman.sort(ps)), ['c', 'a', 'b']);
    });

    test('只调整被约束的插件，其余保持输入顺序（同输入多次结果一致）', () {
      List<DiomanPlugin> build() => [
            _P('a'),
            _P('b', before: {'a'}),
            _P('c'),
            _P('d', after: {'c'}, before: {'b'}),
          ];
      // d 需在 c 之后、b 之前；b 需在 a 之前 => c d b a
      expect(_names(Dioman.sort(build())), ['c', 'd', 'b', 'a']);
      expect(_names(Dioman.sort(build())), ['c', 'd', 'b', 'a']);
    });

    test('before/after 指向未安装的插件被忽略（可选依赖）', () {
      final ps = [
        _P('x', before: {'ghost'}, after: {'ghost2'}),
        _P('y')
      ];
      expect(_names(Dioman.sort(ps)), ['x', 'y']);
    });

    test('sort 不修改入参、返回新列表', () {
      final ps = [
        _P('a', after: {'b'}),
        _P('b')
      ];
      final sorted = Dioman.sort(ps);
      expect(_names(ps), ['a', 'b']);
      expect(_names(sorted), ['b', 'a']);
    });
  });

  group('报错', () {
    test('重复名：异常包含重复的插件名', () {
      expect(
        () => Dioman.sort([_P('dup'), _P('ok'), _P('dup')]),
        throwsA(isA<DiomanPluginOrderException>()
            .having(
                (e) => e.issue, 'issue', DiomanPluginOrderIssue.duplicateName)
            .having((e) => e.plugins, 'plugins', ['dup']).having(
                (e) => e.toString(), 'message', contains('dup'))),
      );
    });

    test('环：异常列出环上的插件名，不含环外插件', () {
      final ps = [
        _P('a', before: {'b'}),
        _P('b', before: {'c'}),
        _P('c', before: {'a'}),
        _P('outside'),
      ];
      expect(
        () => Dioman.sort(ps),
        throwsA(isA<DiomanPluginOrderException>()
            .having((e) => e.issue, 'issue', DiomanPluginOrderIssue.cycle)
            .having((e) => e.plugins.toSet(), 'plugins', {
          'a',
          'b',
          'c'
        }).having((e) => e.toString(), 'message',
                allOf(contains('a'), contains('b'), contains('c')))),
      );
    });

    test('自指约束算环', () {
      expect(
        () => Dioman.sort([
          _P('self', before: {'self'})
        ]),
        throwsA(isA<DiomanPluginOrderException>()
            .having((e) => e.issue, 'issue', DiomanPluginOrderIssue.cycle)),
      );
    });

    test('缺失必需依赖：异常含依赖方与缺失名', () {
      expect(
        () => Dioman.sort([
          _P('needy', requires: {'missing'})
        ]),
        throwsA(isA<DiomanPluginOrderException>()
            .having((e) => e.issue, 'issue',
                DiomanPluginOrderIssue.missingDependency)
            .having((e) => e.plugins, 'plugins', ['needy', 'missing'])),
      );
    });

    test('必需依赖存在时不报错（requires 只要求存在，不隐含顺序）', () {
      final ps = [
        _P('needy', requires: {'dep'}),
        _P('dep')
      ];
      expect(_names(Dioman.sort(ps)), ['needy', 'dep']);
    });

    test('install 遇到环/重复名同样抛错，且不修改 dio', () {
      final dio = Dio();
      final before = dio.interceptors.length;
      expect(
        () => Dioman.install(dio, plugins: [
          _P('a', before: {'b'}),
          _P('b', before: {'a'}),
        ]),
        throwsA(isA<DiomanPluginOrderException>()),
      );
      expect(
        () => Dioman.install(dio, key: const DiomanKey(), plugins: [
          _P('dioman:qid'),
        ]),
        throwsA(isA<DiomanPluginOrderException>().having(
            (e) => e.issue, 'issue', DiomanPluginOrderIssue.duplicateName)),
      );
      expect(dio.interceptors.length, before);
    });

    test('validate：顺序违反约束时抛 misordered 并带两个插件名', () {
      expect(
        () => Dioman.validate([
          _P('late'),
          _P('early', before: {'late'})
        ]),
        throwsA(isA<DiomanPluginOrderException>()
            .having((e) => e.issue, 'issue', DiomanPluginOrderIssue.misordered)
            .having((e) => e.plugins, 'plugins', ['early', 'late'])),
      );
      Dioman.validate([
        _P('early', before: {'late'}),
        _P('late')
      ]);
    });
  });

  group('动态插入后的校验', () {
    DiomanHandle build(Dio dio) => Dioman.install(
          dio,
          key: const DiomanKey(),
          cache: DiomanCache(persist: FakeCachePersist()),
          cancel: DiomanCancel(),
          log: DiomanLog(writer: (m, {error}) {}),
        );

    test('合法插入成功并按位置生效', () {
      final dio = Dio();
      final handle = build(dio);
      handle.insertAfter(
          handle.plugin<DiomanKey>()!, _P('ok', after: {'dioman:qid'}));
      expect(_names(handle.plugins),
          ['dioman:qid', 'ok', 'dioman:cache', 'dioman:cancel', 'dioman:log']);
    });

    test('重复名：四个插入方法都抛错且保持原状', () {
      final dio = Dio();
      final handle = build(dio);
      final anchor = handle.plugin<DiomanCache>()!;
      final snapshot = _names(handle.plugins);
      final calls = <void Function()>[
        () => handle.insertBefore(anchor, _P('dioman:log')),
        () => handle.insertAfter(anchor, _P('dioman:log')),
        () => handle.prepend(_P('dioman:log')),
        () => handle.append(_P('dioman:log')),
      ];
      for (final c in calls) {
        expect(
          c,
          throwsA(isA<DiomanPluginOrderException>().having(
              (e) => e.issue, 'issue', DiomanPluginOrderIssue.duplicateName)),
        );
      }
      expect(_names(handle.plugins), snapshot);
      expect(_names(dio.interceptors.whereType<DiomanPlugin>()), snapshot);
    });

    test('位置违反约束：抛 misordered，handle 与 dio 均不变', () {
      final dio = Dio();
      final handle = build(dio);
      final snapshot = _names(handle.plugins);
      // 自定义插件声明必须在 key 之前，却被放到 cache 之后。
      expect(
        () => handle.insertAfter(
            handle.plugin<DiomanCache>()!, _P('bad', before: {'dioman:qid'})),
        throwsA(isA<DiomanPluginOrderException>().having(
            (e) => e.issue, 'issue', DiomanPluginOrderIssue.misordered)),
      );
      // 内置约束：把一个 cancel 放在 cache 之前是违规的（cache 须先于 cancel）。
      expect(
        () => handle.remove<DiomanCancel>(),
        returnsNormally,
      );
      expect(
        () =>
            handle.insertBefore(handle.plugin<DiomanCache>()!, DiomanCancel()),
        throwsA(isA<DiomanPluginOrderException>().having(
            (e) => e.issue, 'issue', DiomanPluginOrderIssue.misordered)),
      );
      expect(_names(handle.plugins),
          snapshot.where((n) => n != 'dioman:cancel').toList());
      expect(_names(dio.interceptors.whereType<DiomanPlugin>()),
          snapshot.where((n) => n != 'dioman:cancel').toList());
    });

    test('缺失必需依赖：插入被拒', () {
      final dio = Dio();
      final handle = build(dio);
      expect(
        () => handle.append(_P('needy', requires: {'dioman:auth'})),
        throwsA(isA<DiomanPluginOrderException>().having(
            (e) => e.issue, 'issue', DiomanPluginOrderIssue.missingDependency)),
      );
      expect(handle.plugin<DiomanAuth>(), isNull);
      handle.append(_P('fine', requires: {'dioman:log'}));
      expect(handle.plugins.last.name, 'fine');
    });

    test('anchor 不在 handle 上仍抛 ArgumentError（既有行为）', () {
      final handle = build(Dio());
      expect(() => handle.insertBefore(_P('orphan'), _P('x')),
          throwsArgumentError);
    });

    test('remove：被其它插件 requires 的插件不能移除', () {
      final dio = Dio();
      final handle = build(dio);
      handle.append(_P('needy', requires: {'dioman:log'}));
      expect(
        () => handle.remove<DiomanLog>(),
        throwsA(isA<DiomanPluginOrderException>().having(
            (e) => e.issue, 'issue', DiomanPluginOrderIssue.missingDependency)),
      );
      expect(handle.plugin<DiomanLog>(), isNotNull);
    });
  });
}
