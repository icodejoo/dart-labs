// ignore_for_file: avoid_relative_lib_imports
// 单元层：plugin_order
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';

/// 注册本文件的单元层用例。
void main() {
  group('默认 install 顺序不变', () {
    test('[Dioman.sort] 内置插件任意子集按规范顺序排序都是恒等（2^16 个子集）', () {
      final all = allBuiltins();
      for (var mask = 0; mask < (1 << all.length); mask++) {
        final subset = [
          for (var i = 0; i < all.length; i++)
            if ((mask & (1 << i)) != 0) all[i],
        ];
        final sorted = Dioman.sort(subset);
        expect(orderedNames(sorted), orderedNames(subset),
            reason: 'mask=$mask');
      }
    });
    test('[Dioman.sort] 内置插件乱序输入，排序后满足 README 的全部硬约束', () {
      final all = allBuiltins().reversed.toList();
      final names = orderedNames(Dioman.sort(all));

      /// at 的测试辅助入口。
      int at(String n) => names.indexOf(n);
      expect(at(tkDiomanQid), lessThan(at(tkDiomanCache2)));
      expect(at(tkDiomanQid), lessThan(at(tkDiomanShare2)));
      expect(at(tkDiomanRepath2), lessThan(at(tkDiomanQid)));
      expect(at(tkDiomanFilter2), lessThan(at(tkDiomanQid)));
      expect(at(tkDiomanCache2), lessThan(at(tkDiomanOffline2)));
      for (final n in [tkDiomanShare2, tkDiomanCancel2, tkDiomanLoading2]) {
        expect(at(tkDiomanOffline2), lessThan(at(n)));
      }
      for (final n in [tkDiomanCache2, tkDiomanShare2, tkDiomanMock2]) {
        expect(at(n), lessThan(at(tkDiomanCancel2)));
        expect(at(n), lessThan(at(tkDiomanLoading2)));
      }
      for (final a in [tkDiomanCancel2, tkDiomanLoading2]) {
        expect(at(a), lessThan(at(tkDiomanAuth2)));
        expect(at(a), lessThan(at(tkDiomanRetry2)));
      }
      expect(at(tkDiomanRetry2), lessThan(at(tkDiomanBreaker2)));
      expect(at(tkDiomanNormalize2), names.length - 1);
    });
  });

  group('稳定拓扑排序', () {
    test('[Dioman.sort] 无约束时保持输入顺序', () {
      final ps = [OrderedPlugin(tkC), OrderedPlugin(tkA2), OrderedPlugin(tkB2)];
      expect(orderedNames(Dioman.sort(ps)), [tkC, tkA2, tkB2]);
    });
    test(
        '[Dioman.sort][DiomanPluginOrder.before][DiomanPluginOrder.after] 只调整被约束的插件，其余保持输入顺序（同输入多次结果一致）',
        () {
      /// build 的测试辅助入口。
      List<DiomanPlugin> build() => [
            OrderedPlugin(tkA2),
            OrderedPlugin(tkB2, before: {tkA2}),
            OrderedPlugin(tkC),
            OrderedPlugin(tkD, after: {tkC}, before: {tkB2}),
          ];
      // d 需在 c 之后、b 之前；b 需在 a 之前 => c d b a
      expect(orderedNames(Dioman.sort(build())), [tkC, tkD, tkB2, tkA2]);
      expect(orderedNames(Dioman.sort(build())), [tkC, tkD, tkB2, tkA2]);
    });
    test(
        '[Dioman.sort][DiomanPluginOrder.before][DiomanPluginOrder.after] before/after 指向未安装的插件被忽略（可选依赖）',
        () {
      final ps = [
        OrderedPlugin(tkX2, before: {'ghost'}, after: {'ghost2'}),
        OrderedPlugin(tkY)
      ];
      expect(orderedNames(Dioman.sort(ps)), [tkX2, tkY]);
    });
    test('[Dioman.sort] sort 不修改入参、返回新列表', () {
      final ps = [
        OrderedPlugin(tkA2, after: {tkB2}),
        OrderedPlugin(tkB2)
      ];
      final sorted = Dioman.sort(ps);
      expect(orderedNames(ps), [tkA2, tkB2]);
      expect(orderedNames(sorted), [tkB2, tkA2]);
    });
  });

  group('报错', () {
    test(
        '[DiomanPluginOrderException.issue][DiomanPluginOrderException.plugins][Dioman.sort][DiomanPluginOrderIssue.duplicateName] 重复名：异常包含重复的插件名',
        () {
      expect(
        () => Dioman.sort(
            [OrderedPlugin(tkDup), OrderedPlugin(tkOk), OrderedPlugin(tkDup)]),
        throwsA(isA<DiomanPluginOrderException>()
            .having(
                (e) => e.issue, tkIssue, DiomanPluginOrderIssue.duplicateName)
            .having((e) => e.plugins, tkPlugins, [tkDup]).having(
                (e) => e.toString(), tkMessage, contains(tkDup))),
      );
    });
    test(
        '[DiomanPluginOrderException.toString][Dioman.sort][DiomanPluginOrderIssue.cycle] 环：异常列出环上的插件名，不含环外插件',
        () {
      final ps = [
        OrderedPlugin(tkA2, before: {tkB2}),
        OrderedPlugin(tkB2, before: {tkC}),
        OrderedPlugin(tkC, before: {tkA2}),
        OrderedPlugin('outside'),
      ];
      expect(
        () => Dioman.sort(ps),
        throwsA(isA<DiomanPluginOrderException>()
            .having((e) => e.issue, tkIssue, DiomanPluginOrderIssue.cycle)
            .having((e) => e.plugins.toSet(), tkPlugins, {
          tkA2,
          tkB2,
          tkC
        }).having((e) => e.toString(), tkMessage,
                allOf(contains(tkA2), contains(tkB2), contains(tkC)))),
      );
    });
    test('[Dioman.sort][DiomanPluginOrderIssue.cycle] 自指约束算环', () {
      expect(
        () => Dioman.sort([
          OrderedPlugin(tkSelf, before: {tkSelf})
        ]),
        throwsA(isA<DiomanPluginOrderException>()
            .having((e) => e.issue, tkIssue, DiomanPluginOrderIssue.cycle)),
      );
    });
    test(
        '[Dioman.sort][DiomanPluginOrderIssue.missingDependency][DiomanPluginOrder.requires] 缺失必需依赖：异常含依赖方与缺失名',
        () {
      expect(
        () => Dioman.sort([
          OrderedPlugin(tkNeedy, requires: {tkMissing})
        ]),
        throwsA(isA<DiomanPluginOrderException>()
            .having((e) => e.issue, tkIssue,
                DiomanPluginOrderIssue.missingDependency)
            .having((e) => e.plugins, tkPlugins, [tkNeedy, tkMissing])),
      );
    });
    test(
        '[Dioman.sort][DiomanPluginOrder.requires] 必需依赖存在时不报错（requires 只要求存在，不隐含顺序）',
        () {
      final ps = [
        OrderedPlugin(tkNeedy, requires: {tkDep}),
        OrderedPlugin(tkDep)
      ];
      expect(orderedNames(Dioman.sort(ps)), [tkNeedy, tkDep]);
    });
    test(
        '[Dioman.validate][DiomanPluginOrderIssue.misordered] validate：顺序违反约束时抛 misordered 并带两个插件名',
        () {
      expect(
        () => Dioman.validate([
          OrderedPlugin(tkLate),
          OrderedPlugin(tkEarly, before: {tkLate})
        ]),
        throwsA(isA<DiomanPluginOrderException>()
            .having((e) => e.issue, tkIssue, DiomanPluginOrderIssue.misordered)
            .having((e) => e.plugins, tkPlugins, [tkEarly, tkLate])),
      );
      Dioman.validate([
        OrderedPlugin(tkEarly, before: {tkLate}),
        OrderedPlugin(tkLate)
      ]);
    });
  });
}
