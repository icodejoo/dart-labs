// ignore_for_file: avoid_relative_lib_imports
// 集成层：install
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
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

  group('动态插拔后的 retry ↔ breaker 重新接线', () {
    /// 记录 isOpen 被咨询次数的熔断器；阈值调高，保证不会真的熔断。
    final spyFactory = _SpyBreaker.new;

    /// 装 retry（不装 breaker），适配器恒回 500，返回装配结果。
    ({Dio dio, DiomanHandle handle}) build() {
      final adapter =
          RecordingAdapter((o, n) async => jsonBody({tkCode: 500}, 500));
      final dio = fakeDio(adapter);
      final handle = Dioman.install(dio,
          retry:
              DiomanRetry(max: 2, delay: (_, __, ___, ____) => Duration.zero));
      return (dio: dio, handle: handle);
    }

    /// 发一个注定失败的请求（重试耗尽后抛错，吞掉）。
    Future<void> fail(Dio dio) async {
      try {
        await dio.get<dynamic>(tkX);
      } on DioException {
        // 500 重试耗尽，属预期。
      }
    }

    test(
        '[DiomanHandle.insertAfter][DiomanRetry.breaker] install 后再 insert breaker：retry 会咨询它',
        () async {
      final b = build();
      final spy = spyFactory();
      b.handle.insertAfter(b.handle.plugin<DiomanRetry>()!, spy);
      await fail(b.dio);
      expect(spy.isOpenCalls, greaterThan(0));
    });

    test(
        '[DiomanHandle.remove][DiomanRetry.breaker] remove breaker：retry 不再咨询已移除的实例',
        () async {
      final adapter =
          RecordingAdapter((o, n) async => jsonBody({tkCode: 500}, 500));
      final dio = fakeDio(adapter);
      final spy = spyFactory();
      final handle = Dioman.install(dio,
          retry:
              DiomanRetry(max: 2, delay: (_, __, ___, ____) => Duration.zero),
          breaker: spy);
      await fail(dio);
      final before = spy.isOpenCalls;
      expect(before, greaterThan(0), reason: '安装时已接线');

      expect(handle.remove<DiomanBreaker>(), same(spy));
      await fail(dio);
      expect(spy.isOpenCalls, before, reason: '移除后 retry 不应再申请凭据');
    });

    test(
        '[DiomanHandle.prepend][DiomanHandle.append][DiomanRetry.breaker] 移除后再 append 新 breaker：接到新实例而不是旧的',
        () async {
      final b = build();
      final first = spyFactory();
      b.handle.insertAfter(b.handle.plugin<DiomanRetry>()!, first);
      b.handle.remove<DiomanBreaker>();
      final second = spyFactory();
      b.handle.append(second);
      await fail(b.dio);
      expect(second.isOpenCalls, greaterThan(0));
      expect(first.isOpenCalls, 0);
    });

    test(
        '[DiomanHandle.remove][DiomanRetry.breaker] 被移除的 retry 也被解除接线（不再持有 breaker）',
        () async {
      final adapter =
          RecordingAdapter((o, n) async => jsonBody({tkCode: 500}, 500));
      final dio = fakeDio(adapter);
      final spy = spyFactory();
      final retry =
          DiomanRetry(max: 2, delay: (_, __, ___, ____) => Duration.zero);
      final handle = Dioman.install(dio, retry: retry, breaker: spy);
      handle.remove<DiomanRetry>();
      // 摘下的 retry 原样放回一个没有 breaker 的链上，不应还咨询旧 breaker。
      dio.interceptors.add(retry);
      await fail(dio);
      expect(spy.isOpenCalls, 0);
    });

    test(
        '[DiomanHandle.dispose][DiomanRetry.breaker] dispose 解除 retry 对 breaker 的引用',
        () async {
      final adapter =
          RecordingAdapter((o, n) async => jsonBody({tkCode: 500}, 500));
      final dio = fakeDio(adapter);
      final spy = spyFactory();
      final retry =
          DiomanRetry(max: 2, delay: (_, __, ___, ____) => Duration.zero);
      Dioman.install(dio, retry: retry, breaker: spy).dispose();
      dio.interceptors.add(retry);
      await fail(dio);
      expect(spy.isOpenCalls, 0);
    });

    test(
        '[DiomanRetry.breaker][Dioman.install][DiomanHandle.remove] 手动接的外部 breaker：install、插拔无关插件都不清掉它',
        () async {
      final adapter =
          RecordingAdapter((o, n) async => jsonBody({tkCode: 500}, 500));
      final dio = fakeDio(adapter);
      final external = spyFactory();
      final retry =
          DiomanRetry(max: 2, delay: (_, __, ___, ____) => Duration.zero)
            ..breaker = external;
      final handle = Dioman.install(dio, retry: retry);
      expect(retry.breaker, same(external), reason: '链上没有 breaker 时不应置空');
      handle.append(DiomanLog(enabled: false));
      handle.remove<DiomanLog>();
      expect(retry.breaker, same(external), reason: '插拔无关插件不影响外部 breaker');
      await fail(dio);
      expect(external.isOpenCalls, greaterThan(0));
    });

    test('[DiomanRetry.share] 兼容 setter 是无效果的空操作：insert/remove 不需要也不依赖它',
        () async {
      final b = build();
      final retry = b.handle.plugin<DiomanRetry>()!;
      // ignore: deprecated_member_use_from_same_package
      retry.share = DiomanShare();
      b.handle.insertAfter(retry, _SpyBreaker());
      expect(() => b.handle.remove<DiomanBreaker>(), returnsNormally);
      await fail(b.dio);
    });
  });
}

/// 统计 [isOpen] 被咨询次数的熔断器。
class _SpyBreaker extends DiomanBreaker {
  /// 创建间谍熔断器，阈值足够高以免真的熔断。
  _SpyBreaker() : super(failureThreshold: 1000);

  /// [isOpen] 被调用的次数。
  int isOpenCalls = 0;

  /// 记录调用后沿用原判定。
  @override
  bool isOpen(RequestOptions config) {
    isOpenCalls++;
    return super.isOpen(config);
  }
}
