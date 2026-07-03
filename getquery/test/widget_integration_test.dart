import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:getquery/getquery.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

// gcDuration=0 so GC timers fire at pump(Duration.zero).
QueryClient freshClient() => QueryClient(
      defaultQueryOptions: DefaultQueryOptions(
        staleDuration: StaleDuration.zero,
        gcDuration: const GcDuration(seconds: 0),
        retry: (_, __) => null,
      ),
    );

// Drain flutter_query GC timers before FakeAsync ends.
// freshClient GC = Duration.zero; QueryService default GC = 10 min.
// pump(30 min) covers both.
void drainTimers(WidgetTester tester) {
  addTearDown(() async {
    await tester.pump(const Duration(minutes: 30));
  });
}

// ── ViewModels ────────────────────────────────────────────────────────────────

class _SlowCounterVM extends GetBaseViewModel {
  _SlowCounterVM(QueryClient c, this._future) : super(client: c);
  final Future<int> _future;
  late QueryResult<int> counter;

  @override
  void onInit() {
    super.onInit();
    counter = this.useQuery(['slow-counter'], (_) => _future);
  }
}

class _DynamicVM extends GetBaseViewModel {
  _DynamicVM(QueryClient c, this._fn) : super(client: c);
  final Future<int> Function() _fn;
  late QueryResult<int> result;

  @override
  void onInit() {
    super.onInit();
    result = this.useQuery(['dynamic'], (_) => _fn());
  }
}

class _CacheVM extends GetBaseViewModel {
  _CacheVM(QueryClient c) : super(client: c);
  late QueryResult<String> items;

  @override
  void onInit() {
    super.onInit();
    items = this.useQuery(['cache-items'], (_) async => 'original');
  }

  void overrideCache() =>
      setQueryData<String>(['cache-items'], (_) => 'overridden');
}

class _RxKeyVM extends GetBaseViewModel {
  _RxKeyVM(QueryClient c) : super(client: c);
  final tab = 'A'.obs;
  late QueryResult<String> content;

  @override
  void onInit() {
    super.onInit();
    content = this.useQuery(
      ['content', tab],
      (ctx) async => 'data-${ctx.queryKey.last}',
    );
  }
}

class _MutateVM extends GetBaseViewModel {
  _MutateVM(QueryClient c) : super(client: c);
  var serverValue = 0;
  late QueryResult<int> items;

  @override
  void onInit() {
    super.onInit();
    items = this.useQuery(['mut-items'], (_) async => serverValue);
  }

  Future<void> increment() => mutate(
        () async => ++serverValue,
        invalidates: [
          ['mut-items']
        ],
      );
}

class _Page2VM extends GetBaseViewModel {
  _Page2VM(QueryClient c) : super(client: c);
  late QueryResult<String> data;
  static int disposeCount = 0;

  @override
  void onInit() {
    super.onInit();
    data = this.useQuery(['page2-data'], (_) async => 'hello');
  }

  @override
  void onClose() {
    disposeCount++;
    super.onClose();
  }
}

class _MutationWidgetVM extends GetBaseViewModel {
  _MutationWidgetVM(QueryClient c) : super(client: c);
  late MutationResult<String, String> create;

  @override
  void onInit() {
    super.onInit();
    create = this.useMutation<String, String>((v, _) async => 'created-$v');
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);
  tearDown(Get.reset);

  // 1. Obx renders loading -> data
  testWidgets('Obx renders query: loading -> data', (tester) async {
    drainTimers(tester);

    final client = freshClient();
    final completer = Completer<int>();
    final vm = Get.put(_SlowCounterVM(client, completer.future));

    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Center(
          child: Obx(() {
            if (vm.counter.isLoading) {
              return const CircularProgressIndicator(key: Key('loading'));
            }
            return Text('${vm.counter.data}', key: const Key('value'));
          }),
        ),
      ),
    ));

    await tester.pump();
    expect(find.byKey(const Key('loading')), findsOneWidget);

    completer.complete(42);
    await tester.pumpAndSettle();
    expect(find.text('42'), findsOneWidget);
    expect(find.byKey(const Key('loading')), findsNothing);
  });

  // 2. invalidateQueries triggers Obx rebuild
  testWidgets('invalidateQueries triggers Obx rebuild with new data', (tester) async {
    drainTimers(tester);

    final client = freshClient();
    var callCount = 0;
    final vm = Get.put(_DynamicVM(client, () async {
      callCount++;
      return callCount * 10;
    }));

    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Center(
          child: Obx(() {
            if (vm.result.isLoading) {
              return const CircularProgressIndicator(key: Key('loading'));
            }
            return Text('${vm.result.data}', key: const Key('value'));
          }),
        ),
        floatingActionButton: FloatingActionButton(
          key: const Key('refresh'),
          onPressed: () => vm.invalidateQueries(queryKey: ['dynamic']),
          child: const Icon(Icons.refresh),
        ),
      ),
    ));

    await tester.pumpAndSettle();
    expect(find.text('10'), findsOneWidget);
    expect(callCount, 1);

    await tester.tap(find.byKey(const Key('refresh')));
    await tester.pumpAndSettle();
    expect(find.text('20'), findsOneWidget);
    expect(callCount, 2);
  });

  // 3. onClose called on Get.delete
  testWidgets('Get.delete triggers onClose, query subscription cleaned up', (tester) async {
    drainTimers(tester);

    final client = freshClient();
    _Page2VM.disposeCount = 0;
    final vm = Get.put(_Page2VM(client));

    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Center(
          child: Obx(() => Text(
                vm.data.data ?? 'loading',
                key: const Key('page2text'),
              )),
        ),
      ),
    ));

    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);

    Get.delete<_Page2VM>();
    for (var i = 0; i < 5; i++) {
      await tester.pump(Duration.zero);
    }
    expect(_Page2VM.disposeCount, 1);
  });

  // 4. setQueryData -> Obx updates immediately
  testWidgets('setQueryData writes to cache, Obx reflects immediately', (tester) async {
    drainTimers(tester);

    final client = freshClient();
    final vm = Get.put(_CacheVM(client));

    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Center(
          child: Obx(() => Text(
                vm.items.data ?? 'null',
                key: const Key('cacheValue'),
              )),
        ),
        floatingActionButton: FloatingActionButton(
          key: const Key('override'),
          onPressed: vm.overrideCache,
          child: const Icon(Icons.edit),
        ),
      ),
    ));

    await tester.pumpAndSettle();
    expect(find.text('original'), findsOneWidget);

    await tester.tap(find.byKey(const Key('override')));
    await tester.pumpAndSettle();
    expect(find.text('overridden'), findsOneWidget);
  });

  // 5. Rx queryKey triggers new request on change
  testWidgets('Rx queryKey change triggers refetch, Obx updates', (tester) async {
    drainTimers(tester);

    final client = freshClient();
    final vm = Get.put(_RxKeyVM(client));

    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Center(
          child: Obx(() => Text(
                vm.content.data ?? 'loading',
                key: const Key('rxContent'),
              )),
        ),
        floatingActionButton: FloatingActionButton(
          key: const Key('switchTab'),
          onPressed: () => vm.tab.value = 'B',
          child: const Icon(Icons.swap_horiz),
        ),
      ),
    ));

    await tester.pumpAndSettle();
    expect(find.text('data-A'), findsOneWidget);

    await tester.tap(find.byKey(const Key('switchTab')));
    await tester.pumpAndSettle();
    expect(find.text('data-B'), findsOneWidget);
  });

  // 6. mutate helper + invalidateQueries -> Obx increments
  testWidgets('mutate + invalidateQueries: Obx increments correctly', (tester) async {
    drainTimers(tester);

    final client = freshClient();
    final vm = Get.put(_MutateVM(client));

    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Center(
          child: Obx(() => Text(
                '${vm.items.data ?? 0}',
                key: const Key('mutateValue'),
              )),
        ),
        floatingActionButton: FloatingActionButton(
          key: const Key('increment'),
          onPressed: vm.increment,
          child: const Icon(Icons.add),
        ),
      ),
    ));

    await tester.pumpAndSettle();
    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('increment')));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('increment')));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
  });

  // 7. QueryScope disposes on StatefulWidget.dispose
  testWidgets('QueryScope cleans up on State.dispose, invalidate no longer fires', (tester) async {
    drainTimers(tester);

    final client = freshClient();
    var fetchCount = 0;

    await tester.pumpWidget(GetMaterialApp(
      home: _ScopedPage(client: client, onFetch: () => fetchCount++),
    ));

    await tester.pumpAndSettle();
    expect(fetchCount, 1);
    expect(find.text('scoped-data'), findsOneWidget);

    await tester.pumpWidget(const GetMaterialApp(
      home: Scaffold(body: Text('replaced')),
    ));
    await tester.pumpAndSettle();

    await client.invalidateQueries();
    await tester.pumpAndSettle();
    expect(fetchCount, 1);
  });

  // 8. Global useQuery + Obx
  testWidgets('Global useQuery (no ViewModel) drives Obx correctly', (tester) async {
    drainTimers(tester);

    final client = freshClient();
    final result = useQuery(
      ['global-widget'],
      (_) async => 'global-value',
      client: client,
    );

    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Center(
          child: Obx(() => Text(
                result.data ?? 'waiting',
                key: const Key('globalVal'),
              )),
        ),
      ),
    ));

    await tester.pumpAndSettle();
    expect(find.text('global-value'), findsOneWidget);

    result.dispose();
    await tester.pump(Duration.zero);
  });

  // 9. watchQuery record API
  testWidgets('watchQuery (result, dispose) record drives Obx', (tester) async {
    drainTimers(tester);

    final client = freshClient();
    final (result, dispose) = watchQuery(
      client,
      ['wq-widget'],
      (_) async => 99,
    );

    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Center(
          child: Obx(() => Text(
                '${result.data ?? 0}',
                key: const Key('wqVal'),
              )),
        ),
      ),
    ));

    await tester.pumpAndSettle();
    expect(find.text('99'), findsOneWidget);

    dispose();
    await tester.pump(Duration.zero);
  });

  // 10. QueryService resolves via useQueryClient
  testWidgets('QueryService registered: useQuery resolves without explicit client', (tester) async {
    drainTimers(tester);

    final client = freshClient();
    Get.put<QueryService>(QueryService(), permanent: true);
    final result = useQuery(
      ['service-widget'],
      (_) async => 'from-service',
      client: client, // use freshClient to avoid 10-min GC timer
    );

    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Center(
          child: Obx(() => Text(
                result.data ?? 'waiting',
                key: const Key('serviceVal'),
              )),
        ),
      ),
    ));

    await tester.pumpAndSettle();
    expect(find.text('from-service'), findsOneWidget);

    result.dispose();
    await tester.pump(Duration.zero);
  });

  // 11. useMutation in widget: isPending -> isSuccess -> Obx updates
  testWidgets('useMutation reactive state drives Obx', (tester) async {
    drainTimers(tester);

    final client = freshClient();
    final vm = Get.put(_MutationWidgetVM(client));

    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Center(
          child: Obx(() {
            if (vm.create.isPending) {
              return const CircularProgressIndicator(key: Key('pending'));
            }
            if (vm.create.isSuccess) {
              return Text(vm.create.data!, key: const Key('result'));
            }
            return const Text('idle', key: Key('idle'));
          }),
        ),
        floatingActionButton: FloatingActionButton(
          key: const Key('submit'),
          onPressed: () => vm.create.mutate('test'),
          child: const Icon(Icons.send),
        ),
      ),
    ));

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('idle')), findsOneWidget);

    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(find.text('created-test'), findsOneWidget);
  });
}

// ── _ScopedPage ───────────────────────────────────────────────────────────────

class _ScopedPage extends StatefulWidget {
  const _ScopedPage({required this.client, required this.onFetch});
  final QueryClient client;
  final VoidCallback onFetch;

  @override
  State<_ScopedPage> createState() => _ScopedPageState();
}

class _ScopedPageState extends State<_ScopedPage> {
  late final QueryScope _scope;
  late final QueryResult<String> _data;

  @override
  void initState() {
    super.initState();
    _scope = QueryScope(client: widget.client);
    _data = _scope.watch(['scoped'], (_) async {
      widget.onFetch();
      return 'scoped-data';
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Obx(() => Text(
              _data.data ?? 'loading',
              key: const Key('scopedVal'),
            )),
      ),
    );
  }
}
