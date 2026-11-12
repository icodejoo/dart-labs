import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:getx_query/getx_query.dart';

/// 使用无重试客户端验证上游迁移，测试结束后统一释放缓存计时器。
QueryClient _client() {
  final client = QueryClient(
    defaultQueryOptions: DefaultQueryOptions(retry: (_, __) => null),
  );
  addTearDown(client.clear);
  return client;
}

/// 排空查询订阅的异步通知。
Future<void> _flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// 提供可直接调用的普通 ViewModel 包装接口。
class _ViewModel extends BaseViewModel {
  /// 注入测试客户端。
  _ViewModel(super.client);
}

/// 提供可直接调用的 GetX ViewModel 包装接口。
class _GetViewModel extends GetBaseViewModel {
  /// 注入测试客户端。
  _GetViewModel(QueryClient client) : super(client: client);
}

/// 验证普通值兼容层、sealed 快照映射和原生惰性选项。
void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  for (final entryPoint in [
    'standalone',
    'scope',
    'viewmodel',
    'getViewmodel'
  ]) {
    test('$entryPoint preserves plain seed, timestamp and reactive options',
        () async {
      final client = _client();
      final enabled = false.obs;
      final key = 1.obs;
      final timestamp = DateTime.utc(2026);
      addTearDown(enabled.close);
      addTearDown(key.close);
      final scope = QueryScope(client: client);
      final vm = _ViewModel(client);
      final getVm = _GetViewModel(client);
      addTearDown(scope.dispose);
      addTearDown(vm.dispose);
      addTearDown(getVm.onClose);
      final watch = switch (entryPoint) {
        'scope' => scope.watch<String>,
        'viewmodel' => vm.useQuery<String>,
        'getViewmodel' => getVm.useQuery<String>,
        _ => (
                {required List<Object?> queryKey,
                required QueryFn<String> queryFn,
                Object? enabled,
                String? seed,
                DateTime? seedUpdatedAt,
                String? placeholder}) =>
            useQuery<String>(
                client: client,
                queryKey: queryKey,
                queryFn: queryFn,
                enabled: enabled,
                seed: seed,
                seedUpdatedAt: seedUpdatedAt,
                placeholder: placeholder),
      };
      final result = watch(
        queryKey: ['plain-seed', key],
        queryFn: (_) async => 'fetched',
        enabled: enabled,
        seed: 'seeded',
        seedUpdatedAt: timestamp,
        placeholder: 'loading',
      );
      addTearDown(result.dispose);
      expect(result.data, 'seeded');
      expect(result.updatedAt, timestamp);
      key.value = 2;
      await _flush();
      expect(result.data, 'seeded');
      expect(result.updatedAt, timestamp);
      expect(client.getQueryData<String>(['plain-seed', 2]), 'seeded');
      enabled.value = true;
      await _flush();
      expect(result.data, 'fetched');
      expect(result.error, isNull);
    });
  }

  test('a newer seed never overwrites fetched cache data', () async {
    final client = _client();
    const key = ['existing'];
    final timestamp = DateTime.utc(2025);
    client.setQueryData<String, dynamic>(key, (_) => 'cached',
        updatedAt: timestamp);
    final result = useQuery<String>(
      client: client,
      queryKey: key,
      queryFn: (_) async => 'network',
      enabled: false,
      seed: 'new seed',
      seedUpdatedAt: DateTime.utc(2026),
    );
    addTearDown(result.dispose);
    expect(result.data, 'cached');
    expect(result.updatedAt, timestamp);
  });

  test(
      'query snapshots retain data on refetch failure and clear recovered error',
      () async {
    final client = _client();
    var fail = false;
    final failure = StateError('refetch');
    final result = useQuery<String>(
      client: client,
      queryKey: ['refetch'],
      queryFn: (_) async {
        if (fail) throw failure;
        return 'cached';
      },
    );
    addTearDown(result.dispose);
    await _flush();
    fail = true;
    await result.refetch();
    expect(result.isError, isTrue);
    expect(result.error, same(failure));
    expect(result.data, 'cached');
    fail = false;
    await result.refetch();
    expect(result.isSuccess, isTrue);
    expect(result.error, isNull);
  });

  for (final useVm in [false, true]) {
    test(
        'infinite query maps plain seed and error snapshots (viewmodel: $useVm)',
        () async {
      final client = _client();
      final vm = _ViewModel(client);
      addTearDown(vm.dispose);
      final enabled = false.obs;
      addTearDown(enabled.close);
      final seed = InfiniteData<List<int>, int>([
        [0]
      ], [
        0
      ]);
      final timestamp = DateTime.utc(2026);
      final failure = StateError('page');
      final watch = useVm
          ? vm.useInfiniteQuery<List<int>, int>
          : (
                  {required List<Object?> queryKey,
                  required InfiniteQueryFn<List<int>, int> queryFn,
                  required int initialPageParam,
                  required NextPageParamBuilder<List<int>, int>
                      nextPageParamBuilder,
                  Object? enabled,
                  InfiniteData<List<int>, int>? seed,
                  InfiniteData<List<int>, int>? placeholder,
                  DateTime? seedUpdatedAt}) =>
              useInfiniteQuery<List<int>, int>(
                  client: client,
                  queryKey: queryKey,
                  queryFn: queryFn,
                  initialPageParam: initialPageParam,
                  nextPageParamBuilder: nextPageParamBuilder,
                  enabled: enabled,
                  seed: seed,
                  placeholder: placeholder,
                  seedUpdatedAt: seedUpdatedAt);
      final result = watch(
        queryKey: ['infinite'],
        queryFn: (_) async => throw failure,
        initialPageParam: 0,
        nextPageParamBuilder: (_) => 1,
        enabled: enabled,
        seed: seed,
        placeholder: InfiniteData.empty(),
        seedUpdatedAt: timestamp,
      );
      addTearDown(result.dispose);
      expect(result.pages, [
        [0]
      ]);
      expect(result.pageParams, [0]);
      expect(result.updatedAt, timestamp);
      enabled.value = true;
      await _flush();
      expect(result.isError, isTrue);
      expect(result.error, same(failure));
      expect(result.data, seed);
    });
  }

  test('viewmodel fetch, prefetch and ensure keep plain seed timestamps',
      () async {
    final client = _client();
    final vm = _ViewModel(client);
    addTearDown(vm.dispose);
    final timestamp = DateTime.utc(2026);
    var requests = 0;
    var index = 0;
    for (final fetch in [
      vm.fetchQuery<String>,
      vm.prefetchQuery<String>,
      vm.ensureQueryData<String>
    ]) {
      final key = ['imperative', index++];
      await fetch(
          queryKey: key,
          queryFn: (_) async {
            requests++;
            return 'network';
          },
          seed: 'seeded',
          seedUpdatedAt: timestamp,
          staleDuration: StaleDuration.infinity);
      expect(client.getQueryData<String>(key), 'seeded');
      expect(
          client.getQueryState<String, dynamic>(key)?.dataUpdatedAt, timestamp);
    }
    expect(requests, 0);
  });

  test('useQueries resolves lazy seed only when no cached data exists',
      () async {
    final client = _client();
    const existing = ['existing'];
    client.setQueryData<dynamic, dynamic>(existing, (_) => 'cached');
    var seedCalls = 0;
    var timestampCalls = 0;
    final timestamp = DateTime.utc(2026);
    final (results, _, dispose) = useQueries<void>([
      for (final key in [
        existing,
        ['empty']
      ])
        QueryOptions<String, dynamic>(key, (_) async => 'network',
            enabled: false, seed: Seed.lazy(() {
          seedCalls++;
          return 'seeded';
        }), seedUpdatedAt: SeedUpdatedAt.lazy(() {
          timestampCalls++;
          return timestamp;
        })),
    ], client: client);
    addTearDown(dispose);
    expect(results.map((r) => r.data), ['cached', 'seeded']);
    expect(results.last.updatedAt, timestamp);
    expect(seedCalls, 1);
    expect(timestampCalls, 1);
  });

  test('useQueries forwards value placeholders without persisting them', () {
    final client = _client();
    const key = ['placeholder'];
    final (results, _, dispose) = useQueries<void>([
      QueryOptions<String, dynamic>(key, (_) async => 'network',
          enabled: false, placeholder: const Placeholder.value('loading')),
    ], client: client);
    addTearDown(dispose);
    expect(results.single.data, 'loading');
    expect(results.single.isSuccess, isTrue);
    expect(client.getQueryData<dynamic>(key), isNull);
  });

  test('useQueries keeps previous data while a reactive key fetches', () async {
    final client = _client();
    final page = 1.obs;
    addTearDown(page.close);
    final next = Completer<String>();
    final (results, _, dispose) = useQueries<void>([
      QueryOptions<String, dynamic>(['pages', page],
          (_) => page.value == 1 ? Future.value('first') : next.future,
          placeholder: Placeholder.keepPrevious),
    ], client: client);
    addTearDown(dispose);
    await _flush();
    expect(results.single.data, 'first');
    page.value = 2;
    await _flush();
    expect(results.single.data, 'first');
    expect(results.single.isFetching, isTrue);
    expect(client.getQueryData<dynamic>(['pages', 2]), isNull);
    next.complete('second');
    await _flush();
    expect(results.single.data, 'second');
  });

  test('a null lazy seed skips its timestamp and still fetches', () async {
    final client = _client();
    final (results, _, dispose) = useQueries<void>([
      QueryOptions<String, dynamic>(['null-seed'], (_) async => 'network',
          seed: const Seed.lazy(_noSeed),
          seedUpdatedAt: SeedUpdatedAt.lazy(() => throw StateError('unused'))),
    ], client: client);
    addTearDown(dispose);
    expect(results.single.isLoading, isTrue);
    await _flush();
    expect(results.single.data, 'network');
  });

  test('mutation snapshots preserve data, variables, errors and reset',
      () async {
    final client = _client();
    final failure = StateError('mutation');
    final mutation = useMutation<String, int>((value, _) async {
      if (value < 0) throw failure;
      return '$value';
    }, client: client);
    addTearDown(mutation.dispose);
    expect(mutation.variables, isNull);
    await mutation.mutateAsync(1);
    expect(mutation.data, '1');
    expect(mutation.variables, 1);
    expect(mutation.error, isNull);
    await expectLater(mutation.mutateAsync(-1), throwsA(same(failure)));
    expect(mutation.isError, isTrue);
    expect(mutation.data, isNull);
    expect(mutation.variables, -1);
    expect(mutation.error, same(failure));
    mutation.reset();
    expect(mutation.isIdle, isTrue);
    expect(mutation.variables, isNull);
    expect(mutation.error, isNull);
  });
}

/// 返回空种子，用于验证上游不会调用无用的时间戳解析器。
String? _noSeed() => null;
