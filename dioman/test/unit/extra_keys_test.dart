// ignore_for_file: avoid_relative_lib_imports
// 单元层：extra_keys
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/request_claims.dart' show kClaimsKey, kJoinedKey;
import 'package:dioman/src/request_claims.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/fixtures.dart';

/// 注册本文件的单元层用例。
void main() {
  group(tkEmpty10, () {
    test('[DiomanExtraKeys.lookup][DiomanExtraKeys.ofOwner] lookup / ofOwner',
        () {
      expect(DiomanExtraKeys.lookup('dioman:nope'), isNull);
      expect(DiomanExtraKeys.lookup('dioman:share:entry')!.owner,
          DiomanShare.pluginName);
      final cache = DiomanExtraKeys.ofOwner(DiomanCache.pluginName)
          .map((k) => k.key)
          .toSet();
      expect(cache, containsAll([tkDiomanCache2, tkDiomanCacheKey]));
    });
  });

  group('自定义插件登记', () {
    const custom = DiomanExtraKey(
      key: tkMyPluginState,
      owner: tkMyPlugin,
      kind: DiomanExtraKeyKind.state,
      valueType: 'int',
      description: '测试用状态键',
    );
    tearDown(() => DiomanExtraKeys.unregister(custom.key));
    test(
        '[DiomanExtraKeys.register][DiomanExtraKeys.lookup] register 后可 lookup；重复登记或覆盖内置键抛 StateError',
        () {
      DiomanExtraKeys.register(custom);
      expect(DiomanExtraKeys.lookup(tkMyPluginState), same(custom));
      expect(() => DiomanExtraKeys.register(custom), throwsStateError);
      expect(
        () => DiomanExtraKeys.register(const DiomanExtraKey(
          key: tkDiomanCacheKey,
          owner: tkX2,
          kind: DiomanExtraKeyKind.state,
          valueType: 'String',
          description: tkDup,
        )),
        throwsStateError,
      );
    });
    test('[DiomanExtraKeys.unregister] unregister 只能移除自定义键，内置键返回 false 且保留',
        () {
      DiomanExtraKeys.register(custom);
      expect(DiomanExtraKeys.unregister(custom.key), isTrue);
      expect(DiomanExtraKeys.lookup(custom.key), isNull);
      expect(DiomanExtraKeys.unregister(tkDiomanCacheKey), isFalse);
      expect(DiomanExtraKeys.lookup(tkDiomanCacheKey), isNotNull);
    });
    test(
        '[DiomanExtraKeys.register][DiomanExtraKeys.findSharedState] 自定义状态键也参与重复实例诊断',
        () {
      DiomanExtraKeys.register(custom);
      final dio = Dio();
      dio.interceptors
        ..add(CustomPlugin())
        ..add(CustomPlugin());
      expect(DiomanExtraKeys.findSharedState(dio.interceptors).single.key,
          same(custom));
    });
  });

  group(tkEmpty10, () {
    test('[DiomanExtraKeys.all][DiomanExtraKey.key] 键全局唯一，且分类字段完整', () {
      final keys = DiomanExtraKeys.all.map((k) => k.key).toList();
      expect(keys.toSet().length, keys.length, reason: '注册表出现重复键');
      for (final k in DiomanExtraKeys.all) {
        expect(k.key, startsWith(tkDioman2));
        expect(k.owner, startsWith(tkDioman2));
        expect(k.valueType, isNotEmpty, reason: k.key);
        expect(k.description, isNotEmpty, reason: k.key);
      }
    });
    test(
        '[DiomanExtraKeys.ofKind][DiomanExtraKeyKind.config] 公开配置键 = 插件名，值类型是对应的 DiomanXxxOptions',
        () {
      final config = DiomanExtraKeys.ofKind(DiomanExtraKeyKind.config);
      expect(config, isNotEmpty);
      for (final k in config) {
        expect(k.key, k.owner, reason: '配置键就是插件名');
        expect(k.valueType, endsWith('Options'));
      }
      expect(DiomanExtraKeys.lookup(DiomanCache.pluginName)!.valueType,
          tkDiomanCacheOptions);
    });
    test('[DiomanExtraKeys.ofKind][DiomanExtraKeyKind.protocol] 跨插件协议键与既有常量一致',
        () {
      final protocol = DiomanExtraKeys.ofKind(DiomanExtraKeyKind.protocol)
          .map((k) => k.key)
          .toSet();
      expect(protocol, {kKey, kClaimsKey, kJoinedKey});
    });
    test('[DiomanExtraKeys.ofKind][DiomanExtraKeyKind.state] 内部状态键都以所属插件名为前缀',
        () {
      for (final k in DiomanExtraKeys.ofKind(DiomanExtraKeyKind.state)) {
        expect(k.key, startsWith('${k.owner}:'), reason: k.key);
      }
    });
  });
}
