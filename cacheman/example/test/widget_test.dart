import 'dart:async';
import 'dart:io';
import 'package:cacheman/cacheman.dart';
import 'package:cacheman_example/demo_backends.dart';
import 'package:cacheman_example/demo_kit/demo_kit.dart';
import 'package:cacheman_example/demo_support.dart';
import 'package:cacheman_example/get_storage_cache.dart';
import 'package:cacheman_example/main.dart';
import 'package:cacheman_example/pages/ttl_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 所有真实存储操作的临时目录。
late Directory _storageDirectory;

/// 包声明中的版本，用于约束页头版本 chip。
final _packageVersion = RegExp(
  r'^version: (.+)$',
  multiLine: true,
).firstMatch(File('../pubspec.yaml').readAsStringSync())!.group(1)!.trim();

/// 线上页面的稳定地址。
const _pageIds = [
  'basic',
  'ttl',
  'batch',
  'namespace',
  'advanced',
  'async',
  'hub',
  'types',
];

/// 挂载实际页面，并在测试结束时释放计时器与语言状态。
Future<void> _show(
  WidgetTester tester,
  String id, {
  String language = 'en',
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final locale = DemoLocale(uri: Uri.parse('https://test/?lang=$language'));
  await tester.pumpWidget(
    CachemanDemoApp(locale: locale, initialFragment: '/pages/$id'),
  );
  await _settle(tester);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 250));
    locale.dispose();
    tester.view.reset();
  });
}

/// 先构建异步主体，再让真实存储 Future 离开测试的虚拟时钟队列。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

/// 点击可见按钮并等待交互结束。
Future<void> _tap(WidgetTester tester, String text) async {
  final target = find.text(text).first;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await _settle(tester);
}

/// 验证实际操作、独立重放、语言与响应式布局。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    _storageDirectory = await Directory.systemTemp.createTemp(
      'cacheman-demo-widget-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => _storageDirectory.path,
        );
    await GetStorageCache(
      container: demoContainer,
      path: _storageDirectory.path,
    ).ensureInitialized();
  });
  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // 只删除本测试创建且位于系统临时目录内的目录。
    // get_storage 保留文件句柄，Windows 下交给系统临时目录清理。
    if (!Platform.isWindows &&
        _storageDirectory.absolute.path.startsWith(
          Directory.systemTemp.absolute.path,
        )) {
      await _storageDirectory.delete(recursive: true);
    }
  });
  for (final id in _pageIds) {
    for (final language in ['en', 'zh']) {
      for (final size in [const Size(375, 667), const Size(1440, 900)]) {
        testWidgets('$id $language at $size has cards without overflow', (
          tester,
        ) async {
          await _show(tester, id, language: language, size: size);
          expect(find.byType(DemoPage), findsOneWidget);
          expect(find.byType(DemoGrid), findsOneWidget);
          expect(find.text('Initializing…'), findsNothing);
          expect(find.text('正在初始化…'), findsNothing);
          await tester.tap(
            find.byTooltip(language == 'en' ? 'Toggle theme' : '切换亮暗'),
          );
          await _settle(tester);
          expect(find.text(_packageVersion), findsOneWidget);
          final cards = find.byType(DemoCard);
          expect(cards.evaluate().length, greaterThanOrEqualTo(2));
          expect(
            find.byTooltip(language == 'en' ? 'Replay' : '重放'),
            findsNWidgets(cards.evaluate().length),
          );
          for (final element in cards.evaluate()) {
            final rect = tester.getRect(find.byWidget(element.widget));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  testWidgets('basic CRUD and enumeration; replay resets input and data', (
    tester,
  ) async {
    await _show(tester, 'basic');
    await tester.enterText(find.byType(TextField), 'changed');
    await _tap(tester, 'Write');
    await _tap(tester, 'Read');
    expect(find.text('changed'), findsNWidgets(2));
    await _tap(tester, 'Remove');
    expect(find.text('[]'), findsOneWidget);
    await _tap(tester, 'Erase scope');
    await _tap(tester, 'Write pair');
    await _tap(tester, 'Read snapshot');
    expect(find.text('[1, 2]'), findsOneWidget);
    await tester.tap(find.byTooltip('Replay').at(1));
    await _settle(tester);
    expect(find.text('changed'), findsNothing);
    expect(find.text(demoValue), findsOneWidget);
    await _tap(tester, 'Read');
    expect(tester.takeException(), isNull);
  });
  testWidgets('batch and all three accessor forms', (tester) async {
    await _show(tester, 'batch');
    await _tap(tester, 'Write all');
    expect(find.text('[10, 20]'), findsOneWidget);
    for (final text in [
      'Read all',
      'Remove all',
      'fast.set',
      'lazy.get',
      'batchFast',
    ]) {
      await _tap(tester, text);
    }
    expect(find.text('[$demoValue, $demoValue]'), findsOneWidget);
  });
  testWidgets('namespace erase preserves peer and switching escapes colons', (
    tester,
  ) async {
    await _show(tester, 'namespace');
    await _tap(tester, 'Write both');
    expect(find.textContaining('Alice'), findsOneWidget);
    await _tap(tester, 'Erase A');
    expect(find.textContaining('Bob'), findsOneWidget);
    await _tap(tester, 'Storage keys');
    expect(find.textContaining('accounts%3Aa'), findsOneWidget);
    await _tap(tester, 'Switch & write');
    expect(find.textContaining('switch%3Aa%3Ab'), findsOneWidget);
    await _tap(tester, 'Back to A');
    expect(find.text('[]'), findsOneWidget);
  });
  testWidgets('Jsonx types round trip; debug snapshot decodes values', (
    tester,
  ) async {
    await _show(tester, 'advanced');
    for (final text in ['DateTime', 'Duration', 'Set', 'BigInt', 'Uri']) {
      await _tap(tester, text);
      expect(find.textContaining('Jsonx.encode'), findsOneWidget);
      expect(find.textContaining('type: Null'), findsNothing);
    }
    await _tap(tester, 'Seed values');
    await _tap(tester, 'Take snapshot');
    expect(find.textContaining('snapshot:first'), findsOneWidget);
  });
  testWidgets('layered backends and async replay', (tester) async {
    await _show(tester, 'async');
    await _tap(tester, 'Store summary');
    expect(find.text('1000'), findsOneWidget);
    await _tap(tester, 'Store 1,000 rows');
    expect(find.text('{rows: 1000, keys: 1}'), findsOneWidget);
    await _tap(tester, 'Write custom');
    expect(find.text(demoValue), findsNWidgets(2));
    await tester.tap(find.text('Erase').at(0));
    await _settle(tester);
    await tester.tap(find.text('Erase').at(1));
    await _settle(tester);
    await tester.tap(find.byTooltip('Replay').at(1));
    await _settle(tester);
    expect(find.text('{rows: 1000, keys: 1}'), findsNothing);
  });
  testWidgets('Hub own-write filter, flush, erase and subscription reset', (
    tester,
  ) async {
    await _show(tester, 'hub');
    await _tap(tester, 'Write A');
    expect(find.text('No watch events yet.'), findsNWidgets(2));
    await _tap(tester, 'Write B');
    expect(find.text('A.watch events: [2]'), findsOneWidget);
    await _tap(tester, 'Flush now');
    expect(find.text('Pending save requested.'), findsOneWidget);
    await _tap(tester, 'Erase B');
    expect(find.text('A.watch events: [null, 2]'), findsOneWidget);
    await tester.tap(find.byTooltip('Replay').first);
    await _settle(tester);
    expect(find.text('No watch events yet.'), findsNWidgets(2));
    await tester.tap(find.text('Write A').at(1));
    await _settle(tester);
    expect(find.text('A.watch events: [1]'), findsOneWidget);
  });
  testWidgets(
    'adapters, mismatch retention, corruption removal, serialize error',
    (tester) async {
      await _show(tester, 'types');
      await _tap(tester, 'Typed list');
      expect(find.text('[$demoValue]'), findsOneWidget);
      await _tap(tester, 'Profile adapter');
      expect(find.text(demoValue), findsOneWidget);
      await _tap(tester, 'Type mismatch');
      expect(find.textContaining('TypeMismatchError'), findsOneWidget);
      expect(find.textContaining('retained: true'), findsOneWidget);
      await _tap(tester, 'Corrupt entry');
      expect(find.textContaining('CorruptEntryError'), findsOneWidget);
      expect(find.textContaining('retained: false'), findsOneWidget);
      await _tap(tester, 'Serialize error');
      expect(find.text('[SerializeError]'), findsOneWidget);
    },
  );
  testWidgets(
    'clock observation never renews; explicit read renews; expiry and replay',
    (tester) async {
      await _show(tester, 'ttl');
      final cache = GetStorageCache(
        container: demoContainer,
        options: const CachemanOptions(
          namespace: 'expiry-sliding',
          sliding: true,
        ),
      );
      await tester.runAsync(cache.ensureInitialized);
      final key = cache.storageKey(demoKey);
      final initial = cache.box.read<String>(key);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(cache.box.read<String>(key), initial);
      await tester.tap(find.text('Read').at(2));
      await tester.pump();
      expect(cache.box.read<String>(key), isNot(initial));
      await tester.runAsync(
        () => Future<void>.delayed(
          demoLifetime + const Duration(milliseconds: 100),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Expired'), findsNWidgets(3));
      await _tap(tester, 'Read');
      expect(find.text('Read result: null'), findsOneWidget);
      await _tap(tester, 'Purge');
      for (var index = 0; index < 3; index++) {
        await tester.tap(find.byTooltip('Replay').at(index));
        await _settle(tester);
      }
      expect(find.textContaining('Remaining:'), findsNWidgets(3));
    },
  );
  testWidgets('pending actions and late initialization dispose safely', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    var disposed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActionDemo(
            create: () async => DemoSession([
              DemoAction('Wait', '等待', (_) => pending.future),
            ], dispose: () => disposed++),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Wait'));
    await tester.pump();
    expect(find.text('Loading…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    pending.complete(1);
    await tester.pump();
    expect(disposed, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActionDemo(create: () async => throw StateError('expected')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Operation failed'), findsOneWidget);
    final session = Completer<DemoSession>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActionDemo(key: UniqueKey(), create: () => session.future),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    session.complete(DemoSession([], dispose: () => disposed++));
    await tester.pump();
    expect(disposed, 2);
  });
  testWidgets('custom backend primitives support CRUD without get_storage', (
    tester,
  ) async {
    final sync = MemorySync();
    final async = MemoryAsync();
    await sync.ensureInitialized();
    await async.ensureInitialized();
    sync.write(demoKey, demoValue);
    await async.write(demoKey, demoValue);
    expect(sync.read<String>(demoKey), demoValue);
    expect(await async.read<String>(demoKey), demoValue);
    sync.remove(demoKey);
    await async.remove(demoKey);
    expect(sync.keys(), isEmpty);
    expect(await async.keys(), isEmpty);
    sync.write(demoKey, demoValue);
    await async.write(demoKey, demoValue);
    sync.erase();
    await async.erase();
    expect(sync.length, 0);
    expect(await async.length(), 0);
    await tester.pumpWidget(const SizedBox());
  });
}
