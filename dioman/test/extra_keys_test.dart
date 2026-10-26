// extra 键注册表测试：集中登记、与源码一致、重复实例共享状态键的诊断、
// 文档表格与注册表同步。
// extra key registry: central registration, consistency with the sources,
// diagnosis of duplicate instances sharing state keys, docs in sync.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/request_claims.dart' show kClaimsKey, kJoinedKey;
import 'package:test/test.dart';

import 'support/fake_cache_persist.dart';

/// 读取 lib/src 下全部源码，返回 {文件名: 内容}。
Map<String, String> _sources() => {
      for (final f in Directory('lib/src').listSync().whereType<File>())
        if (f.path.endsWith('.dart')) f.path: f.readAsStringSync(),
    };

/// 断言是否已开启（dart test 默认开启）。
bool get _assertsEnabled {
  var on = false;
  assert(on = true);
  return on;
}

void main() {
  group('注册表内容', () {
    test('键全局唯一，且分类字段完整', () {
      final keys = DiomanExtraKeys.all.map((k) => k.key).toList();
      expect(keys.toSet().length, keys.length, reason: '注册表出现重复键');
      for (final k in DiomanExtraKeys.all) {
        expect(k.key, startsWith('dioman:'));
        expect(k.owner, startsWith('dioman:'));
        expect(k.valueType, isNotEmpty, reason: k.key);
        expect(k.description, isNotEmpty, reason: k.key);
      }
    });

    test('公开配置键 = 插件名，值类型是对应的 DiomanXxxOptions', () {
      final config = DiomanExtraKeys.ofKind(DiomanExtraKeyKind.config);
      expect(config, isNotEmpty);
      for (final k in config) {
        expect(k.key, k.owner, reason: '配置键就是插件名');
        expect(k.valueType, endsWith('Options'));
      }
      expect(DiomanExtraKeys.lookup(DiomanCache.pluginName)!.valueType,
          'DiomanCacheOptions');
    });

    test('跨插件协议键与既有常量一致', () {
      final protocol = DiomanExtraKeys.ofKind(DiomanExtraKeyKind.protocol)
          .map((k) => k.key)
          .toSet();
      expect(protocol, {kKey, kClaimsKey, kJoinedKey});
    });

    test('内部状态键都以所属插件名为前缀', () {
      for (final k in DiomanExtraKeys.ofKind(DiomanExtraKeyKind.state)) {
        expect(k.key, startsWith('${k.owner}:'), reason: k.key);
      }
    });

    test('lookup / ofOwner', () {
      expect(DiomanExtraKeys.lookup('dioman:nope'), isNull);
      expect(DiomanExtraKeys.lookup('dioman:share:entry')!.owner,
          DiomanShare.pluginName);
      final cache = DiomanExtraKeys.ofOwner(DiomanCache.pluginName)
          .map((k) => k.key)
          .toSet();
      expect(cache, containsAll(['dioman:cache', 'dioman:cache:key']));
    });
  });

  group('与源码一致（防止新增键忘记登记）', () {
    test('源码里每个 dioman: 键常量都在注册表中，注册表的非配置键都能在源码找到', () {
      final found = <String>{};
      // 形如 `const _kX = '$pluginName:x'` 或 `const kX = 'dioman:x'`。
      final decl = RegExp(r"const\s+_?k\w+\s*=\s*'([^']+)'");
      final pluginNameDecl = RegExp(r"static const pluginName = '([^']+)'");
      for (final entry in _sources().entries) {
        final src = entry.value;
        final pn = pluginNameDecl.firstMatch(src)?.group(1);
        for (final m in decl.allMatches(src)) {
          var v = m.group(1)!;
          if (pn != null) v = v.replaceAll(r'$pluginName', pn);
          if (v.startsWith('dioman:')) found.add(v);
        }
      }
      expect(found, isNotEmpty);
      final registered = DiomanExtraKeys.all
          .where((k) => k.kind != DiomanExtraKeyKind.config)
          .map((k) => k.key)
          .toSet();
      expect(found.difference(registered), isEmpty,
          reason: '源码中有键没登记到 DiomanExtraKeys');
      expect(registered.difference(found), isEmpty, reason: '注册表里有键在源码中已不存在');
    });

    test('配置键对应真实存在的插件名', () {
      final names = <String>{};
      final pluginNameDecl = RegExp(r"static const pluginName = '([^']+)'");
      for (final src in _sources().values) {
        final m = pluginNameDecl.firstMatch(src);
        if (m != null) names.add(m.group(1)!);
      }
      for (final k in DiomanExtraKeys.ofKind(DiomanExtraKeyKind.config)) {
        expect(names, contains(k.key));
      }
    });
  });

  group('重复实例共享状态键的诊断', () {
    test('同一 Dio 上装两个 DiomanCache：报告它的状态键，数量为 2', () {
      final dio = Dio();
      dio.interceptors
        ..add(DiomanCache(persist: FakeCachePersist()))
        ..add(DiomanCache(persist: FakeCachePersist()));
      final conflicts = DiomanExtraKeys.findSharedState(dio.interceptors);
      expect(conflicts, isNotEmpty);
      expect(conflicts.every((c) => c.count == 2), isTrue);
      expect(conflicts.map((c) => c.key.key),
          containsAll(['dioman:cache:key', 'dioman:cache:generation']));
      expect(conflicts.every((c) => c.key.owner == DiomanCache.pluginName),
          isTrue);
    });

    test('正常 install 没有冲突；无状态键的重复插件（log）不算冲突', () {
      final dio = Dio();
      final handle = Dioman.install(
        dio,
        key: const DiomanKey(),
        cache: DiomanCache(persist: FakeCachePersist()),
        share: DiomanShare(),
      );
      expect(handle.diagnoseSharedStateKeys(), isEmpty);
      dio.interceptors
        ..add(DiomanLog(writer: (m, {error}) {}))
        ..add(DiomanLog(writer: (m, {error}) {}));
      expect(handle.diagnoseSharedStateKeys(), isEmpty);
    });

    test('handle.diagnoseSharedStateKeys 能发现绕过 handle 手动重复添加的实例', () {
      final dio = Dio();
      final handle = Dioman.install(dio, cancel: DiomanCancel());
      dio.interceptors.add(DiomanCancel());
      final conflicts = handle.diagnoseSharedStateKeys();
      expect(conflicts.map((c) => c.key.key), ['dioman:cancel:token']);
    });

    test('assertNoSharedState：debug 下重复实例抛 AssertionError，无冲突不抛', () {
      final dio = Dio();
      dio.interceptors.add(DiomanCancel());
      expect(() => DiomanExtraKeys.assertNoSharedState(dio.interceptors),
          returnsNormally);
      dio.interceptors.add(DiomanCancel());
      expect(
        () => DiomanExtraKeys.assertNoSharedState(dio.interceptors),
        _assertsEnabled
            ? throwsA(isA<AssertionError>().having((e) => e.toString(),
                'message', contains('dioman:cancel:token')))
            : returnsNormally,
      );
    });
  });

  group('自定义插件登记', () {
    const custom = DiomanExtraKey(
      key: 'my:plugin:state',
      owner: 'my:plugin',
      kind: DiomanExtraKeyKind.state,
      valueType: 'int',
      description: '测试用状态键',
    );
    tearDown(() => DiomanExtraKeys.unregister(custom.key));

    test('register 后可 lookup；重复登记或覆盖内置键抛 StateError', () {
      DiomanExtraKeys.register(custom);
      expect(DiomanExtraKeys.lookup('my:plugin:state'), same(custom));
      expect(() => DiomanExtraKeys.register(custom), throwsStateError);
      expect(
        () => DiomanExtraKeys.register(const DiomanExtraKey(
          key: 'dioman:cache:key',
          owner: 'x',
          kind: DiomanExtraKeyKind.state,
          valueType: 'String',
          description: 'dup',
        )),
        throwsStateError,
      );
    });

    test('unregister 只能移除自定义键，内置键返回 false 且保留', () {
      DiomanExtraKeys.register(custom);
      expect(DiomanExtraKeys.unregister(custom.key), isTrue);
      expect(DiomanExtraKeys.lookup(custom.key), isNull);
      expect(DiomanExtraKeys.unregister('dioman:cache:key'), isFalse);
      expect(DiomanExtraKeys.lookup('dioman:cache:key'), isNotNull);
    });

    test('自定义状态键也参与重复实例诊断', () {
      DiomanExtraKeys.register(custom);
      final dio = Dio();
      dio.interceptors
        ..add(_Custom())
        ..add(_Custom());
      expect(DiomanExtraKeys.findSharedState(dio.interceptors).single.key,
          same(custom));
    });
  });

  test('ARCHITECTURE.md 中的键表与 DiomanExtraKeys.toMarkdown() 同步', () {
    final doc = File('ARCHITECTURE.md').readAsStringSync();
    const start = '<!-- dioman:extra-keys:start -->';
    const end = '<!-- dioman:extra-keys:end -->';
    final s = doc.indexOf(start);
    final e = doc.indexOf(end);
    expect(s, greaterThanOrEqualTo(0), reason: '缺少起始标记');
    expect(e, greaterThan(s), reason: '缺少结束标记');
    final body = doc.substring(s + start.length, e).trim();
    expect(body, DiomanExtraKeys.toMarkdown().trim(),
        reason: '键表过期：把 toMarkdown() 的输出贴回两个标记之间');
  });
}

class _Custom extends DiomanPlugin {
  @override
  String get name => 'my:plugin';
}
