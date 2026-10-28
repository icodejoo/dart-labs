// ignore_for_file: avoid_relative_lib_imports
// 集成层：extra_keys
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/accept/lib/literals.dart';
import '../../test/support/fake_cache_persist.dart';
import '../../test/support/fixtures.dart';

/// 注册本文件的集成层用例。
void main() {
  group('与源码一致（防止新增键忘记登记）', () {
    test(
        '[DiomanExtraKeys.all][DiomanExtraKeys.builtIn] 源码里每个 dioman: 键常量都在注册表中，注册表的非配置键都能在源码找到',
        () {
      final found = <String>{};
      // 形如 `const _kX = '$pluginName:x'` 或 `const kX = 'dioman:x'`。
      final decl = RegExp(r"const\s+_?k\w+\s*=\s*'([^']+)'");
      final pluginNameDecl = RegExp(tkStaticConstPluginName);
      for (final entry in sourceFiles().entries) {
        final src = entry.value;
        final pn = pluginNameDecl.firstMatch(src)?.group(1);
        for (final m in decl.allMatches(src)) {
          var v = m.group(1)!;
          if (pn != null) v = v.replaceAll(r'$pluginName', pn);
          if (v.startsWith(tkDioman2)) found.add(v);
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
    test(
        '[DiomanExtraKeys.ofKind][DiomanExtraKeyKind.config] 配置键对应真实存在的插件名；非插件 owner 只有 DiomanMockAdapter',
        () {
      final names = <String>{};
      final pluginNameDecl = RegExp(tkStaticConstPluginName);
      for (final src in sourceFiles().values) {
        final m = pluginNameDecl.firstMatch(src);
        if (m != null) names.add(m.group(1)!);
      }
      for (final k in DiomanExtraKeys.ofKind(DiomanExtraKeyKind.config)) {
        if (k.owner == DiomanExtraKeys.mockAdapterOwner) {
          // 传输层 adapter 不是插件，键由它自己的常量提供。
          expect(k.key, DiomanMockAdapter.extraKey);
          expect(names, isNot(contains(k.key)),
              reason: 'mock 不再是插件：源码里不该再有同名 pluginName');
        } else {
          expect(names, contains(k.key));
          expect(k.owner, k.key);
        }
      }
    });
  });

  group('重复实例共享状态键的诊断', () {
    test(
        '[DiomanSharedStateKey.key][DiomanExtraKeys.findSharedState][DiomanSharedStateKey.count] 同一 Dio 上装两个 DiomanCache：报告它的状态键，数量为 2',
        () {
      final dio = Dio();
      dio.interceptors
        ..add(DiomanCache(persist: FakeCachePersist()))
        ..add(DiomanCache(persist: FakeCachePersist()));
      final conflicts = DiomanExtraKeys.findSharedState(dio.interceptors);
      expect(conflicts, isNotEmpty);
      expect(conflicts.every((c) => c.count == 2), isTrue);
      expect(conflicts.map((c) => c.key.key),
          containsAll([tkDiomanCacheKey, 'dioman:cache:generation']));
      expect(conflicts.every((c) => c.key.owner == DiomanCache.pluginName),
          isTrue);
    });
    test(
        '[DiomanExtraKeys.findSharedState][Dioman.install] 正常 install 没有冲突；无状态键的重复插件（log）不算冲突',
        () {
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
    test(
        '[DiomanHandle.diagnoseSharedStateKeys] handle.diagnoseSharedStateKeys 能发现绕过 handle 手动重复添加的实例',
        () {
      final dio = Dio();
      final handle = Dioman.install(dio, cancel: DiomanCancel());
      dio.interceptors.add(DiomanCancel());
      final conflicts = handle.diagnoseSharedStateKeys();
      expect(conflicts.map((c) => c.key.key), [tkDiomanCancelToken]);
    });
    test(
        '[DiomanExtraKeys.assertNoSharedState] assertNoSharedState：debug 下重复实例抛 AssertionError，无冲突不抛',
        () {
      final dio = Dio();
      dio.interceptors.add(DiomanCancel());
      expect(() => DiomanExtraKeys.assertNoSharedState(dio.interceptors),
          returnsNormally);
      dio.interceptors.add(DiomanCancel());
      expect(
        () => DiomanExtraKeys.assertNoSharedState(dio.interceptors),
        assertsEnabled
            ? throwsA(isA<AssertionError>().having(
                (e) => e.toString(), tkMessage, contains(tkDiomanCancelToken)))
            : returnsNormally,
      );
    });
  });

  test(
      '[DiomanExtraKeys.toMarkdown] docs/design/architecture.md 中的键表与 DiomanExtraKeys.toMarkdown() 同步',
      () {
    // Windows 下 autocrlf 会把文档检出成 CRLF，统一成 LF 再比对。
    final doc = File('docs/design/architecture.md')
        .readAsStringSync()
        .replaceAll('\r\n', tkEmpty9);
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
