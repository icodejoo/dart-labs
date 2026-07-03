// ignore_for_file: invalid_use_of_internal_member, library_private_types_in_public_api

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:getquery/getquery.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<void> pump([int n = 5]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

QueryClient freshClient() => QueryClient(
      defaultQueryOptions: DefaultQueryOptions(
        staleDuration: StaleDuration.zero,
        gcDuration: GcDuration(seconds: 1),
        retry: (_, __) => null,
      ),
    );

// ── Test ViewModels ───────────────────────────────────────────────────────────

class _SimpleGetVM extends GetBaseViewModel {
  _SimpleGetVM(QueryClient client, this._fn) : super(client: client);
  final QueryFn<String> _fn;
  late QueryResult<String> items;

  @override
  void onInit() {
    super.onInit();
    items = this.useQuery(['items'], _fn);
  }
}

class _MultiGetVM extends GetBaseViewModel {
  _MultiGetVM(QueryClient c, this._fnA, this._fnB) : super(client: c);
  final QueryFn<String> _fnA;
  final QueryFn<String> _fnB;
  late QueryResult<String> a;
  late QueryResult<String> b;

  @override
  void onInit() {
    super.onInit();
    a = this.useQuery(['a'], _fnA);
    b = this.useQuery(['b'], _fnB);
  }
}

class _InvalidateGetVM extends GetBaseViewModel {
  _InvalidateGetVM(QueryClient c, this._fn) : super(client: c);
  final QueryFn<String> _fn;
  late QueryResult<String> items;
  @override
  Future<void> refresh() => invalidateQueries(queryKey: ['inv-items']);

  @override
  void onInit() {
    super.onInit();
    items = this.useQuery(['inv-items'], _fn);
  }
}

class _MutateGetVM extends GetBaseViewModel {
  _MutateGetVM(QueryClient c, this._queryFn, this._mutateFn) : super(client: c);
  final QueryFn<String> _queryFn;
  final Future<String> Function() _mutateFn;
  late QueryResult<String> items;

  Future<String> submit() => mutate(
        _mutateFn,
        invalidates: [
          ['mut-items']
        ],
      );

  @override
  void onInit() {
    super.onInit();
    items = this.useQuery(['mut-items'], _queryFn);
  }
}

class _StandaloneVM extends BaseViewModel {
  _StandaloneVM(super.client, this._fn);
  final QueryFn<String> _fn;
  late QueryResult<String> items;

  @override
  void init() {
    super.init();
    items = this.useQuery(['sa-items'], _fn);
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);
  tearDown(Get.reset);

  // ── 1. QueryResult state ────────────────────────────────────────────────

  group('QueryResult', () {
    test('initial: isIdle=true isLoading=true data=placeholder', () {
      final r = QueryResult<String>(placeholder: 'loading...');
      expect(r.isIdle, true);
      expect(r.isLoading, true);
      expect(r.isSuccess, false);
      expect(r.isError, false);
      expect(r.isFetching, false);
      expect(r.data, 'loading...');
      expect(r.error, null);
    });

    test('success: isSuccess=true data correct', () async {
      final client = freshClient();
      final r = useQuery(['qr-ok'], (_) async => 'hello', client: client);
      await pump();
      expect(r.isSuccess, true);
      expect(r.isLoading, false);
      expect(r.data, 'hello');
      r.dispose();
    });

    test('error: isError=true error contains exception', () async {
      final client = freshClient();
      final r = useQuery<String>(
        ['qr-err'],
        (_) async => throw Exception('boom'),
        client: client,
      );
      await pump();
      expect(r.isError, true);
      expect(r.error.toString(), contains('boom'));
      r.dispose();
    });

    test('dispose calls disposeCallback once', () {
      var called = 0;
      final r = QueryResult<int>();
      r.disposeCallback = () => called++;
      r.dispose();
      expect(called, 1);
    });

    test('calling dispose twice does not throw', () {
      final r = QueryResult<int>();
      r.disposeCallback = () {};
      r.dispose();
      expect(() => r.dispose(), returnsNormally);
    });

    test('isFetching=true while request is in flight', () async {
      final client = freshClient();
      final completer = Completer<String>();
      final r = useQuery(['qr-fetch'], (_) => completer.future, client: client);
      await pump(1);
      expect(r.isFetching, true);
      completer.complete('done');
      await pump();
      expect(r.isFetching, false);
      r.dispose();
    });
  });

  // ── 2. useQuery basic ───────────────────────────────────────────────────

  group('useQuery - basic', () {
    test('fetches data successfully', () async {
      final client = freshClient();
      final r = useQuery(['basic-ok'], (_) async => 'result', client: client);
      await pump();
      expect(r.isSuccess, true);
      expect(r.data, 'result');
      r.dispose();
    });

    test('shows error on failure', () async {
      final client = freshClient();
      final r = useQuery<String>(
        ['basic-fail'],
        (_) => Future.error(Exception('err')),
        client: client,
      );
      await pump();
      expect(r.isError, true);
      expect(r.error.toString(), contains('err'));
      r.dispose();
    });

    test('placeholder shown before data arrives', () async {
      final client = freshClient();
      final completer = Completer<String>();
      final r = useQuery(['basic-ph'], (_) => completer.future,
          client: client, placeholder: 'pending...');
      expect(r.data, 'pending...');
      completer.complete('real');
      await pump();
      expect(r.data, 'real');
      r.dispose();
    });

    test('seed provides initial cached data', () async {
      final client = freshClient();
      final completer = Completer<String>();
      final r = useQuery(['basic-seed'], (_) => completer.future,
          client: client, seed: 'seed-value');
      await pump(1);
      expect(r.data, 'seed-value');
      completer.complete('fresh');
      await pump();
      expect(r.data, 'fresh');
      r.dispose();
    });

    test('multiple dispose does not throw', () async {
      final client = freshClient();
      final r = useQuery(['multi-dispose'], (_) async => 'x', client: client);
      await pump();
      r.dispose();
      expect(() => r.dispose(), returnsNormally);
    });
  });

  // ── 3. useQuery enabled ─────────────────────────────────────────────────

  group('useQuery - enabled', () {
    test('enabled:false skips request', () async {
      final client = freshClient();
      var count = 0;
      final r = useQuery(['en-false'], (_) async { count++; return 'data'; },
          client: client, enabled: false);
      await pump();
      expect(count, 0);
      r.dispose();
    });

    test('enabled:true triggers request', () async {
      final client = freshClient();
      var count = 0;
      final r = useQuery(['en-true'], (_) async { count++; return 'data'; },
          client: client, enabled: true);
      await pump();
      expect(count, 1);
      expect(r.isSuccess, true);
      r.dispose();
    });

    test('RxBool enabled=false then true triggers fetch', () async {
      final client = freshClient();
      var count = 0;
      final enabled = false.obs;
      final r = useQuery(['en-rx'], (_) async { count++; return 'rx-data'; },
          client: client, enabled: enabled);
      await pump();
      expect(count, 0);

      enabled.value = true;
      await pump(10);
      expect(count, 1);
      expect(r.isSuccess, true);
      r.dispose();
    });

    test('RxBool true->false stops refetch after invalidate', () async {
      final client = freshClient();
      var count = 0;
      final enabled = true.obs;
      final r = useQuery(['en-rx-off'], (_) async { count++; return 'v$count'; },
          client: client, enabled: enabled);
      await pump();
      expect(count, 1);

      enabled.value = false;
      await pump(3);
      await client.invalidateQueries(queryKey: ['en-rx-off']);
      await pump();
      expect(count, 1);
      r.dispose();
    });
  });

  // ── 4. useQuery reactive queryKey ───────────────────────────────────────

  group('useQuery - reactive queryKey', () {
    test('Rx item in key triggers refetch on change', () async {
      final client = freshClient();
      final userId = 'u1'.obs;
      final fetched = <String>[];
      final r = useQuery(
        ['user', userId],
        (ctx) async { final key = ctx.queryKey.last as String; fetched.add(key); return 'profile-$key'; },
        client: client,
      );
      await pump();
      expect(fetched, ['u1']);
      expect(r.data, 'profile-u1');

      userId.value = 'u2';
      await pump(10);
      expect(fetched, contains('u2'));
      expect(r.data, 'profile-u2');
      r.dispose();
    });
  });

  // ── 5. staleDuration ────────────────────────────────────────────────────

  group('useQuery - staleDuration', () {
    test('fresh data: second mount does not refetch', () async {
      final client = freshClient();
      var count = 0;
      final r1 = useQuery(['stale-key'], (_) async { count++; return 'data'; },
          client: client, staleDuration: StaleDuration(minutes: 5));
      await pump();
      expect(count, 1);
      r1.dispose();

      final r2 = useQuery(['stale-key'], (_) async { count++; return 'data'; },
          client: client, staleDuration: StaleDuration(minutes: 5));
      await pump();
      expect(count, 1);
      expect(r2.data, 'data');
      r2.dispose();
    });

    test('staleDuration=zero: remount always refetches', () async {
      final client = freshClient();
      var count = 0;
      final r1 = useQuery(['stale-zero'], (_) async { count++; return 'v$count'; },
          client: client, staleDuration: StaleDuration.zero);
      await pump();
      expect(count, 1);
      r1.dispose();

      final r2 = useQuery(['stale-zero'], (_) async { count++; return 'v$count'; },
          client: client, staleDuration: StaleDuration.zero);
      await pump();
      expect(count, 2);
      r2.dispose();
    });
  });

  // ── 6. retry ────────────────────────────────────────────────────────────

  group('useQuery - retry', () {
    test('retry succeeds after initial failure', () async {
      final client = freshClient();
      var attempts = 0;
      final completer = Completer<String>();
      final r = useQuery<String>(
        ['retry-ok'],
        (_) async {
          attempts++;
          if (attempts < 2) throw Exception('tmp fail');
          return completer.future;
        },
        client: client,
        retry: (count, _) => count < 1 ? Duration.zero : null,
      );
      await pump(10);
      completer.complete('ok');
      await pump();
      expect(r.isSuccess, true);
      expect(attempts, 2);
      r.dispose();
    });

    test('error shown after max retries exceeded', () async {
      final client = freshClient();
      var attempts = 0;
      final r = useQuery<String>(
        ['retry-fail'],
        (_) async { attempts++; throw Exception('always fail'); },
        client: client,
        retry: (count, _) => count < 2 ? Duration.zero : null,
      );
      await pump(20);
      expect(r.isError, true);
      expect(attempts, 3);
      r.dispose();
    });
  });

  // ── 7. deduplication ────────────────────────────────────────────────────

  group('useQuery - deduplication', () {
    test('same key shares single request', () async {
      final client = freshClient();
      var count = 0;
      final r1 = useQuery(['dedup'], (_) async { count++; return 'shared'; }, client: client);
      final r2 = useQuery(['dedup'], (_) async { count++; return 'shared'; }, client: client);
      await pump();
      expect(count, 1);
      expect(r1.data, 'shared');
      expect(r2.data, 'shared');
      r1.dispose();
      r2.dispose();
    });

    test('second subscriber still receives data after first disposes', () async {
      final client = freshClient();
      final completer = Completer<String>();
      final r1 = useQuery(['dedup2'], (_) => completer.future, client: client);
      final r2 = useQuery(['dedup2'], (_) => completer.future, client: client);
      await pump(1);
      r1.dispose();
      completer.complete('late');
      await pump();
      expect(r2.isSuccess, true);
      expect(r2.data, 'late');
      r2.dispose();
    });
  });

  // ── 8. lifecycle ────────────────────────────────────────────────────────

  group('useQuery - lifecycle', () {
    test('no updates received after dispose', () async {
      final client = freshClient();
      final completer = Completer<String>();
      final r = useQuery(['lc-disp'], (_) => completer.future, client: client);
      await pump(1);
      expect(r.data, null);
      r.dispose();
      completer.complete('after-dispose');
      await pump();
      expect(r.isSuccess, false);
      expect(r.data, null);
    });

    test('invalidateQueries triggers refetch', () async {
      final client = freshClient();
      var count = 0;
      final r = useQuery(['lc-inv'], (_) async { count++; return 'v$count'; }, client: client);
      await pump();
      expect(count, 1);
      await client.invalidateQueries(queryKey: ['lc-inv']);
      await pump();
      expect(count, 2);
      expect(r.data, 'v2');
      r.dispose();
    });
  });

  // ── 9. useQueryClient ───────────────────────────────────────────────────

  group('useQueryClient', () {
    test('returns QueryClient from QueryService', () async {
      final svc = Get.put<QueryService>(QueryService(), permanent: true);
      final client = useQueryClient();
      expect(client, same(svc.client));
    });
  });

  // ── 10. useMutation ─────────────────────────────────────────────────────

  group('useMutation', () {
    test('mutate updates isPending then isSuccess', () async {
      final client = freshClient();
      final completer = Completer<String>();
      final m = useMutation<String, String>(
        (v, _) => completer.future,
        client: client,
      );

      expect(m.isIdle, true);
      m.mutate('input');
      await pump(1);
      expect(m.isPending, true);

      completer.complete('result');
      await pump();
      expect(m.isSuccess, true);
      expect(m.data, 'result');
      m.dispose();
    });

    test('mutateAsync returns data', () async {
      final client = freshClient();
      final m = useMutation<int, int>(
        (v, _) async => v * 2,
        client: client,
      );
      final result = await m.mutateAsync(5);
      expect(result, 10);
      m.dispose();
    });

    test('error captured in isError', () async {
      final client = freshClient();
      final m = useMutation<String, String>(
        (_, __) async => throw Exception('mut-err'),
        client: client,
      );
      m.mutate('x');
      await pump();
      expect(m.isError, true);
      expect(m.error.toString(), contains('mut-err'));
      m.dispose();
    });

    test('reset returns to idle', () async {
      final client = freshClient();
      final m = useMutation<String, String>(
        (v, _) async => v,
        client: client,
      );
      await m.mutateAsync('hello');
      expect(m.isSuccess, true);
      m.reset();
      await pump(1);
      expect(m.isIdle, true);
      expect(m.data, null);
      m.dispose();
    });

    test('onSuccess callback called with data', () async {
      final client = freshClient();
      String? received;
      final m = useMutation<String, String>(
        (v, _) async => 'got-$v',
        client: client,
        onSuccess: (data, _, __, ___) { received = data; },
      );
      await m.mutateAsync('foo');
      expect(received, 'got-foo');
      m.dispose();
    });

    test('useMutation in GetBaseViewModel auto-disposes on onClose', () async {
      final client = freshClient();
      var called = false;
      final vm = Get.put(_MutationVM(client, () async { called = true; return 'ok'; }));
      await pump();
      await vm.doMutate();
      expect(called, true);
      expect(vm.createItem.isSuccess, true);
      Get.delete<_MutationVM>();
    });
  });

  // ── 11. GetBaseViewModel ────────────────────────────────────────────────

  group('GetBaseViewModel', () {
    test('useQuery auto-disposes on onClose', () async {
      final client = freshClient();
      var count = 0;
      Get.put(_SimpleGetVM(client, (_) async { count++; return 'data'; }));
      await pump();
      expect(count, 1);
      Get.delete<_SimpleGetVM>();
      await client.invalidateQueries(queryKey: ['items']);
      await pump();
      expect(count, 1);
    });

    test('multiple useQuery all tracked and cleaned up', () async {
      final client = freshClient();
      final vm = Get.put(_MultiGetVM(client, (_) async => 'a', (_) async => 'b'));
      await pump();
      expect(vm.a.isSuccess, true);
      expect(vm.b.isSuccess, true);
      expect(() => Get.delete<_MultiGetVM>(), returnsNormally);
    });

    test('invalidateQueries triggers refetch', () async {
      final client = freshClient();
      var count = 0;
      final vm = Get.put(_InvalidateGetVM(client, (_) async { count++; return 'v$count'; }));
      await pump();
      expect(count, 1);
      await vm.refresh();
      await pump();
      expect(count, 2);
      expect(vm.items.data, 'v2');
    });

    test('mutate helper calls fn and invalidates', () async {
      final client = freshClient();
      var queryCount = 0;
      var mutateExecuted = false;
      final vm = Get.put(_MutateGetVM(
        client,
        (_) async { queryCount++; return 'q$queryCount'; },
        () async { mutateExecuted = true; return 'mutated'; },
      ));
      await pump();
      expect(queryCount, 1);
      final result = await vm.submit();
      await pump();
      expect(mutateExecuted, true);
      expect(result, 'mutated');
      expect(queryCount, 2);
    });

    test('prefetchQuery warms cache', () async {
      final client = freshClient();
      var count = 0;
      final vm = Get.put(_SimpleGetVM(client, (_) async { count++; return 'pf'; }));
      vm.prefetchQuery(['prefetch-key'], (_) async { count++; return 'pf'; });
      await pump();
      expect(count, greaterThanOrEqualTo(1));
    });

    test('getQueryData returns cached data', () async {
      final client = freshClient();
      final vm = Get.put(_SimpleGetVM(client, (_) async => 'cached-val'));
      await pump();
      final cached = vm.getQueryData<String>(['items']);
      expect(cached, 'cached-val');
    });

    test('setQueryData updates cache immediately', () async {
      final client = freshClient();
      final vm = Get.put(_SimpleGetVM(client, (_) async => 'original'));
      await pump();
      expect(vm.items.data, 'original');
      vm.setQueryData<String>(['items'], (_) => 'overridden');
      await pump();
      expect(vm.items.data, 'overridden');
    });

    test('isFetching returns active fetch count', () async {
      final client = freshClient();
      final completer = Completer<String>();
      final vm = Get.put(_SimpleGetVM(client, (_) => completer.future));
      await pump(1);
      expect(vm.isFetching(queryKey: ['items']), greaterThan(0));
      completer.complete('done');
      await pump();
      expect(vm.isFetching(queryKey: ['items']), 0);
    });

    test('cancelQueries stops in-flight request (isFetching becomes false)', () async {
      final client = freshClient();
      final completer = Completer<String>();
      final vm = Get.put(_SimpleGetVM(client, (_) => completer.future));
      await pump(1);
      expect(vm.isFetching(queryKey: ['items']), greaterThan(0));
      await vm.cancelQueries(queryKey: ['items']);
      await pump();
      // After cancel with revert=true, state reverts to pre-fetch (no data, not fetching)
      expect(vm.isFetching(queryKey: ['items']), 0);
    });

    test('resetQueries triggers a fresh refetch', () async {
      // After reset, the active observer immediately re-fetches.
      // Verify by counting fetches: reset should cause a second fetch.
      final client = freshClient();
      var count = 0;
      final vm = Get.put(_SimpleGetVM(client, (_) async { count++; return 'v$count'; }));
      await pump();
      expect(count, 1);
      expect(vm.items.data, 'v1');

      await vm.resetQueries(queryKey: ['items']);
      await pump();
      // Active observer re-fetched after reset
      expect(count, 2);
      expect(vm.items.data, 'v2');
    });

    test('removeQueries removes entry from cache', () async {
      final client = freshClient();
      final vm = Get.put(_SimpleGetVM(client, (_) async => 'data'));
      await pump();
      expect(vm.getQueryData<String>(['items']), 'data');
      vm.removeQueries(queryKey: ['items']);
      expect(vm.getQueryData<String>(['items']), null);
    });
  });

  // ── 12. BaseViewModel standalone ────────────────────────────────────────

  group('BaseViewModel', () {
    test('constructor injection, manual init/dispose', () async {
      final client = freshClient();
      final vm = _StandaloneVM(client, (_) async => 'standalone');
      vm.init();
      await pump();
      expect(vm.items.isSuccess, true);
      expect(vm.items.data, 'standalone');
      expect(() => vm.dispose(), returnsNormally);
    });

    test('no updates after dispose', () async {
      final client = freshClient();
      final completer = Completer<String>();
      final vm = _StandaloneVM(client, (_) => completer.future);
      vm.init();
      vm.dispose();
      completer.complete('after-dispose');
      await pump();
      expect(vm.items.data, null);
    });

    test('invalidateQueries / setQueryData / getQueryData / mutate work', () async {
      final client = freshClient();
      var count = 0;
      final vm = _StandaloneVM(client, (_) async { count++; return 'v$count'; });
      vm.init();
      await pump();
      expect(count, 1);

      await vm.invalidateQueries(queryKey: ['sa-items']);
      await pump();
      expect(count, 2);

      vm.setQueryData<String>(['sa-items'], (_) => 'manual');
      await pump();
      expect(vm.items.data, 'manual');

      final cached = vm.getQueryData<String>(['sa-items']);
      expect(cached, 'manual');

      vm.dispose();
    });

    test('mutate helper calls fn and invalidates', () async {
      final client = freshClient();
      var queryCount = 0;
      final vm = _StandaloneVM(client, (_) async { queryCount++; return 'q$queryCount'; });
      vm.init();
      await pump();
      expect(queryCount, 1);

      await vm.mutate(() async => 'ok', invalidates: [['sa-items']]);
      await pump();
      expect(queryCount, 2);
      vm.dispose();
    });
  });

  // ── 13. QueryScope ──────────────────────────────────────────────────────

  group('QueryScope', () {
    test('watch collects results, dispose clears all', () async {
      final client = freshClient();
      var countA = 0, countB = 0;
      final scope = QueryScope(client: client);
      final a = scope.watch(['sc-a'], (_) async { countA++; return 'a$countA'; });
      final b = scope.watch(['sc-b'], (_) async { countB++; return 'b$countB'; });
      await pump();
      expect(a.isSuccess, true);
      expect(b.isSuccess, true);
      scope.dispose();
      await client.invalidateQueries();
      await pump();
      expect(countA, 1);
      expect(countB, 1);
    });

    test('QueryScope.invalidateQueries works', () async {
      final client = freshClient();
      var count = 0;
      final scope = QueryScope(client: client);
      final r = scope.watch(['sc-inv'], (_) async { count++; return 'v$count'; });
      await pump();
      expect(count, 1);
      await scope.invalidateQueries(queryKey: ['sc-inv']);
      await pump();
      expect(count, 2);
      expect(r.data, 'v2');
      scope.dispose();
    });

    test('QueryScope.mutate helper invalidates on success', () async {
      final client = freshClient();
      var count = 0;
      final scope = QueryScope(client: client);
      final r = scope.watch(['sc-mut'], (_) async { count++; return 'v$count'; });
      await pump();
      expect(count, 1);
      await scope.mutate(() async => 'done', invalidates: [['sc-mut']]);
      await pump();
      expect(count, 2);
      expect(r.data, 'v2');
      scope.dispose();
    });

    test('QueryScope uses useQueryClient when no client passed', () async {
      Get.put<QueryService>(QueryService(), permanent: true);
      final scope = QueryScope();
      var called = false;
      final r = scope.watch(['sc-global'], (_) async { called = true; return 'global'; });
      await pump();
      expect(called, true);
      expect(r.isSuccess, true);
      scope.dispose();
    });
  });

  // ── 14. watchQuery ──────────────────────────────────────────────────────

  group('watchQuery', () {
    test('returns (QueryResult, dispose) record', () async {
      final client = freshClient();
      final (result, dispose) = watchQuery(client, ['wq-key'], (_) async => 'wq-data');
      await pump();
      expect(result.isSuccess, true);
      expect(result.data, 'wq-data');
      dispose();
    });

    test('dispose callback equals result.dispose', () async {
      final client = freshClient();
      var disposeCount = 0;
      final (result, dispose) = watchQuery(client, ['wq-disp'], (_) async => 'x');
      final original = result.disposeCallback;
      result.disposeCallback = () { disposeCount++; original?.call(); };
      dispose();
      expect(disposeCount, 1);
    });

    test('explicit client bypasses QueryService', () async {
      final client = freshClient();
      final (r, d) = watchQuery(client, ['wq-explicit'], (_) async => 'explicit');
      await pump();
      expect(r.isSuccess, true);
      d();
    });
  });
}

// ── Additional test ViewModels ────────────────────────────────────────────────

class _MutationVM extends GetBaseViewModel {
  _MutationVM(QueryClient client, this._fn) : super(client: client);
  final Future<String> Function() _fn;
  late MutationResult<String, void> createItem;

  @override
  void onInit() {
    super.onInit();
    createItem = this.useMutation<String, void>((_, __) => _fn());
  }

  Future<void> doMutate() => createItem.mutateAsync(null);
}
