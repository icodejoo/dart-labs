// ignore_for_file: avoid_relative_lib_imports
// 集成层：install
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/fake_cache_persist.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的集成层用例。
void main() {
  group(tkDiomanInstall, () {
    test(
        '[Dioman.install][DiomanHandle.dispose] adds plugins in canonical order and the handle disposes them all',
        () async {
      final server = await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));

      final loadingStates = <bool>[];
      final handle = Dioman.install(
        dio,
        key: const DiomanKey(),
        share: DiomanShare(), // exercises DiomanShare.dispose() teardown too
        cancel: DiomanCancel(),
        loading: DiomanLoading(onChanged: loadingStates.add),
        log: const DiomanLog(
            logRequest: false, logResponse: false, logError: false),
      );

      // Canonical order: key → share → cancel → loading → log
      // (envs..auth/retry omitted).
      final names = dio.interceptors
          .whereType<DiomanPlugin>()
          .map((p) => p.name)
          .toList();
      expect(names, [
        tkDiomanQid,
        tkDiomanShare2,
        tkDiomanCancel2,
        tkDiomanLoading2,
        tkDiomanLog2
      ]);
      expect(handle.plugin<DiomanCancel>(), isNotNull);
      expect(handle.plugin<DiomanAuth>(), isNull);

      await dio.get<void>(tkX);
      expect(loadingStates, [true, false]);

      // dispose() must eject every plugin AND run each plugin's own dispose()
      // (DiomanShare's teardown, DiomanLoading's onChanged(false), etc.)
      // without throwing.
      expect(handle.dispose, returnsNormally);
      expect(dio.interceptors.whereType<DiomanPlugin>(), isEmpty,
          reason: 'dispose must eject every installed plugin');
      expect(loadingStates, [true, false], reason: '已关闭周期在 dispose 时不重复通知');
    });
    test(
        '[DiomanHandle.plugin][DiomanHandle.remove] remove<T>() ejects only the targeted plugin, runs its dispose, '
        'and is a no-op for a type that was never installed', () async {
      final server = await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));

      final loadingStates = <bool>[];
      final handle = Dioman.install(
        dio,
        key: const DiomanKey(),
        cancel: DiomanCancel(),
        loading: DiomanLoading(onChanged: loadingStates.add),
        log: const DiomanLog(
            logRequest: false, logResponse: false, logError: false),
      );

      expect(handle.remove<DiomanAuth>(), isNull,
          reason: 'DiomanAuth was never installed — nothing to remove');

      final removed = handle.remove<DiomanLoading>();
      expect(removed, isNotNull);
      expect(loadingStates, isEmpty, reason: '没有开启显示周期时不发出关闭通知');
      expect(handle.plugin<DiomanLoading>(), isNull);
      expect(dio.interceptors.contains(removed), isFalse,
          reason: 'remove() must eject the plugin from dio.interceptors');

      // The rest of the chain is untouched.
      final names = dio.interceptors
          .whereType<DiomanPlugin>()
          .map((p) => p.name)
          .toList();
      expect(names, [tkDiomanQid, tkDiomanCancel2, tkDiomanLog2]);
      expect(handle.plugins.map((p) => p.name),
          [tkDiomanQid, tkDiomanCancel2, tkDiomanLog2]);

      await dio.get<void>(tkX); // still works without the removed plugin
    });
    test(
        '[DiomanHandle.append][DiomanHandle.insertAfter] insertBefore/insertAfter/prepend/append slot a custom plugin into '
        'both the handle and dio.interceptors, in the right position and '
        'execution order', () async {
      final server = await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));

      final order = <String>[];

      /// custom 的测试辅助入口。
      RecordingPlugin custom(String name) => RecordingPlugin(name, order.add);

      final handle = Dioman.install(
        dio,
        key: const DiomanKey(),
        cancel: DiomanCancel(),
        loading: DiomanLoading(onChanged: (_) {}),
      );
      final cancelPlugin = handle.plugin<DiomanCancel>()!;

      final before = custom(tkBefore);
      final after = custom(tkAfter);
      final first = custom(tkFirst);
      final last = custom(tkLast);
      handle.insertBefore(cancelPlugin, before);
      handle.insertAfter(cancelPlugin, after);
      handle.prepend(first);
      handle.append(last);

      final expectedNames = [
        tkFirst,
        tkDiomanQid,
        tkBefore,
        tkDiomanCancel2,
        tkAfter,
        tkDiomanLoading2,
        tkLast,
      ];
      expect(handle.plugins.map((p) => p.name), expectedNames);
      expect(dio.interceptors.whereType<DiomanPlugin>().map((p) => p.name),
          expectedNames);

      await dio.get<void>(tkX);
      expect(order, [tkFirst, tkBefore, tkAfter, tkLast],
          reason: 'inserted plugins must actually run in chain position');

      expect(
        () => handle.insertBefore(
            RecordingPlugin(tkOrphan, order.add), custom(tkX2)),
        throwsArgumentError,
        reason: 'anchor not installed on this handle',
      );
      expect(
        () => handle.insertAfter(
            RecordingPlugin(tkOrphan, order.add), custom(tkY)),
        throwsArgumentError,
      );

      // dispose() must also eject/dispose the manually-inserted plugins.
      handle.dispose();
      expect(dio.interceptors.whereType<DiomanPlugin>(), isEmpty);
    });
  });

  group('默认 install 顺序不变', () {
    test('[Dioman.install][DiomanHandle.plugins] 全部 16 个插件的安装顺序与改动前逐一相同', () {
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
          tokenManager: OrderTokens(),
          onRefresh: (_, __) async {},
          onAccessExpired: (_, __) async {},
        ),
        retry: DiomanRetry(),
        breaker: DiomanBreaker(),
        log: DiomanLog(writer: (m, {error}) {}),
        normalize: const DiomanNormalize(),
      );
      expect(orderedNames(handle.plugins), canonicalOrder);
      expect(orderedNames(dio.interceptors.whereType<DiomanPlugin>()),
          canonicalOrder);
      handle.dispose();
    });
    test(
        '[Dioman.install][DiomanPlugin.ordering] install 的 plugins 参数：自定义插件按约束插入内置链',
        () {
      final dio = Dio();
      final handle = Dioman.install(
        dio,
        key: const DiomanKey(),
        cache: DiomanCache(persist: FakeCachePersist()),
        log: DiomanLog(writer: (m, {error}) {}),
        plugins: [
          OrderedPlugin(tkCustomAfterKey,
              after: {tkDiomanQid}, before: {tkDiomanCache2}),
          OrderedPlugin(tkFree),
        ],
      );
      expect(orderedNames(handle.plugins), [
        tkDiomanQid,
        tkCustomAfterKey,
        tkDiomanCache2,
        tkDiomanLog2,
        tkFree,
      ]);
      handle.dispose();
    });
  });

  group('报错', () {
    test(
        '[Dioman.install][DiomanPluginOrderIssue.cycle][DiomanPluginOrderIssue.duplicateName] install 遇到环/重复名同样抛错，且不修改 dio',
        () {
      final dio = Dio();
      final before = dio.interceptors.length;
      expect(
        () => Dioman.install(dio, plugins: [
          OrderedPlugin(tkA2, before: {tkB2}),
          OrderedPlugin(tkB2, before: {tkA2}),
        ]),
        throwsA(isA<DiomanPluginOrderException>()),
      );
      expect(
        () => Dioman.install(dio, key: const DiomanKey(), plugins: [
          OrderedPlugin(tkDiomanQid),
        ]),
        throwsA(isA<DiomanPluginOrderException>().having(
            (e) => e.issue, tkIssue, DiomanPluginOrderIssue.duplicateName)),
      );
      expect(dio.interceptors.length, before);
    });
  });

  group('动态插入后的校验', () {
    /// build 的测试辅助入口。
    DiomanHandle build(Dio dio) => Dioman.install(
          dio,
          key: const DiomanKey(),
          cache: DiomanCache(persist: FakeCachePersist()),
          cancel: DiomanCancel(),
          log: DiomanLog(writer: (m, {error}) {}),
        );
    test('[DiomanHandle.insertBefore][DiomanHandle.insertAfter] 合法插入成功并按位置生效',
        () {
      final dio = Dio();
      final handle = build(dio);
      handle.insertAfter(handle.plugin<DiomanKey>()!,
          OrderedPlugin(tkOk, after: {tkDiomanQid}));
      expect(orderedNames(handle.plugins),
          [tkDiomanQid, tkOk, tkDiomanCache2, tkDiomanCancel2, tkDiomanLog2]);
    });
    test(
        '[DiomanHandle.insertBefore][DiomanHandle.insertAfter][DiomanHandle.prepend][DiomanHandle.append][DiomanPluginOrderIssue.duplicateName] 重复名：四个插入方法都抛错且保持原状',
        () {
      final dio = Dio();
      final handle = build(dio);
      final anchor = handle.plugin<DiomanCache>()!;
      final snapshot = orderedNames(handle.plugins);
      final calls = <void Function()>[
        () => handle.insertBefore(anchor, OrderedPlugin(tkDiomanLog2)),
        () => handle.insertAfter(anchor, OrderedPlugin(tkDiomanLog2)),
        () => handle.prepend(OrderedPlugin(tkDiomanLog2)),
        () => handle.append(OrderedPlugin(tkDiomanLog2)),
      ];
      for (final c in calls) {
        expect(
          c,
          throwsA(isA<DiomanPluginOrderException>().having(
              (e) => e.issue, tkIssue, DiomanPluginOrderIssue.duplicateName)),
        );
      }
      expect(orderedNames(handle.plugins), snapshot);
      expect(
          orderedNames(dio.interceptors.whereType<DiomanPlugin>()), snapshot);
    });
    test(
        '[DiomanHandle.insertBefore][DiomanPluginOrderIssue.misordered] 位置违反约束：抛 misordered，handle 与 dio 均不变',
        () {
      final dio = Dio();
      final handle = build(dio);
      final snapshot = orderedNames(handle.plugins);
      // 自定义插件声明必须在 key 之前，却被放到 cache 之后。
      expect(
        () => handle.insertAfter(handle.plugin<DiomanCache>()!,
            OrderedPlugin(tkBad, before: {tkDiomanQid})),
        throwsA(isA<DiomanPluginOrderException>().having(
            (e) => e.issue, tkIssue, DiomanPluginOrderIssue.misordered)),
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
            (e) => e.issue, tkIssue, DiomanPluginOrderIssue.misordered)),
      );
      expect(orderedNames(handle.plugins),
          snapshot.where((n) => n != tkDiomanCancel2).toList());
      expect(orderedNames(dio.interceptors.whereType<DiomanPlugin>()),
          snapshot.where((n) => n != tkDiomanCancel2).toList());
    });
    test(
        '[DiomanHandle.insertBefore][DiomanPluginOrderIssue.missingDependency] 缺失必需依赖：插入被拒',
        () {
      final dio = Dio();
      final handle = build(dio);
      expect(
        () => handle.append(OrderedPlugin(tkNeedy, requires: {tkDiomanAuth2})),
        throwsA(isA<DiomanPluginOrderException>().having(
            (e) => e.issue, tkIssue, DiomanPluginOrderIssue.missingDependency)),
      );
      expect(handle.plugin<DiomanAuth>(), isNull);
      handle.append(OrderedPlugin(tkFine, requires: {tkDiomanLog2}));
      expect(handle.plugins.last.name, tkFine);
    });
    test(
        '[DiomanHandle.insertBefore][DiomanHandle.insertAfter] anchor 不在 handle 上仍抛 ArgumentError（既有行为）',
        () {
      final handle = build(Dio());
      expect(
          () =>
              handle.insertBefore(OrderedPlugin(tkOrphan), OrderedPlugin(tkX2)),
          throwsArgumentError);
    });
    test(
        '[DiomanHandle.remove][DiomanPluginOrder.requires] remove：被其它插件 requires 的插件不能移除',
        () {
      final dio = Dio();
      final handle = build(dio);
      handle.append(OrderedPlugin(tkNeedy, requires: {tkDiomanLog2}));
      expect(
        () => handle.remove<DiomanLog>(),
        throwsA(isA<DiomanPluginOrderException>().having(
            (e) => e.issue, tkIssue, DiomanPluginOrderIssue.missingDependency)),
      );
      expect(handle.plugin<DiomanLog>(), isNotNull);
    });
  });
}
