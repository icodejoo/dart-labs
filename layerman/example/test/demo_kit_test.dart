import 'package:layerman_example/demo_kit/demo_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试用代码，保留换行和符号验证原样复制。
const _code = 'Widget example() => const Text("hello");\n';

/// 测试外链，避免连接外部服务。
const _url = 'https://example.com';

/// 生成包含两页与两个分组的测试骨架。
Widget _app(DemoLocale locale, {String? fragment}) => DemoApp(
  title: 'kit',
  seedColor: Colors.blue,
  locale: locale,
  home: DemoShell(
    project: 'kit',
    version: '1.0',
    pubUrl: _url,
    githubUrl: _url,
    readmeUrl: _url,
    initialFragment: fragment,
    destinations: [
      DemoDestination(
        id: 'one',
        en: 'First',
        zh: '第一页',
        icon: Icons.looks_one,
        builder: (context) => DemoPage(
          title: tr(context, 'Hello', '你好'),
          description: tr(context, 'Description', '说明'),
          sections: [
            DemoSection(
              title: tr(context, 'Section', '分区'),
              code: _code,
              child: const DemoGrid(
                children: [
                  DemoGridItem(
                    child: DemoCard(
                      title: 'A',
                      description: 'A',
                      child: Text('demo'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      DemoDestination(
        id: 'two',
        en: 'Second',
        zh: '第二页',
        icon: Icons.looks_two,
        sectionEn: 'More',
        sectionZh: '更多',
        builder: (_) => const Text('second body'),
      ),
    ],
  ),
);

/// 覆盖语言、导航、主题、网格与系统剪贴板契约。

/// 记录挂载次数的探针，用于确认重播会重建主体。
class _MountProbe extends StatefulWidget {
  /// 创建探针，每次挂载调用一次 [onMount]。
  const _MountProbe({required this.onMount});

  /// 挂载回调。
  final VoidCallback onMount;

  /// 创建探针状态。
  @override
  State<_MountProbe> createState() => _MountProbeState();
}

/// 探针状态：initState 时上报一次挂载。
class _MountProbeState extends State<_MountProbe> {
  /// 上报挂载。
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  /// 构建占位文字。
  @override
  Widget build(BuildContext context) => const Text('probe');
}

/// 验证统一组件的语言、导航、主题和重放契约。
void main() {
  test('URL language wins; Chinese locales and fallback resolve', () {
    final chinese = DemoLocale(
      uri: Uri.parse('https://test/?lang=zh'),
      browserLocale: const Locale('en'),
    );
    final english = DemoLocale(
      uri: Uri.parse('https://test/?lang=en'),
      browserLocale: const Locale('zh', 'TW'),
    );
    final inferred = DemoLocale(
      uri: Uri.parse('https://test/?lang=invalid'),
      browserLocale: const Locale('zh', 'HK'),
    );
    final fallback = DemoLocale(
      uri: Uri.parse('https://test/'),
      browserLocale: const Locale('fr'),
    );
    expect(chinese.language, 'zh');
    expect(english.language, 'en');
    expect(inferred.language, 'zh');
    expect(fallback.language, 'en');
    var changes = 0;
    chinese.addListener(() => changes++);
    chinese.select('zh');
    chinese.select('invalid');
    chinese.select('en');
    expect(changes, 1);
    for (final locale in [chinese, english, inferred, fallback]) {
      locale.dispose();
    }
  });

  testWidgets('language and theme rebuild the full page', (tester) async {
    final locale = DemoLocale(uri: Uri.parse(_url));
    await tester.pumpWidget(_app(locale));
    await tester.tap(find.text('中文'));
    await tester.pumpAndSettle();
    expect(find.text('你好'), findsOneWidget);
    expect(find.text('显示代码'), findsOneWidget);
    final before = Theme.of(tester.element(find.byType(DemoPage))).brightness;
    await tester.tap(find.byTooltip('切换亮暗'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(DemoPage))).brightness,
      isNot(before),
    );
    await tester.pumpWidget(const SizedBox());
    locale.dispose();
  });

  for (final width in <double>[375, 1440]) {
    testWidgets('navigation and layout at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final locale = DemoLocale(uri: Uri.parse('$_url?lang=en'));
      final routes = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        (call) async {
          routes.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.navigation,
          null,
        ),
      );
      await tester.pumpWidget(_app(locale));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('demo-sidebar')),
        width >= 900 ? findsOneWidget : findsNothing,
      );
      if (width < 900) {
        await tester.tap(find.byTooltip('Open navigation'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Second'));
      await tester.pumpAndSettle();
      expect(find.text('second body'), findsOneWidget);
      locale.select('zh');
      await tester.pumpAndSettle();
      expect(find.text('second body'), findsOneWidget);
      locale.select('en');
      await tester.pumpAndSettle();
      expect(
        routes
            .where((call) => call.method == 'routeInformationUpdated')
            .last
            .arguments['uri'],
        '/pages/two',
      );
      expect(
        routes.any((call) => call.method == 'selectMultiEntryHistory'),
        isTrue,
      );
      await tester.binding.handlePushRoute('/pages/one');
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      locale.dispose();
    });
  }

  testWidgets('initial hash restores page; invalid id falls back', (
    tester,
  ) async {
    final locale = DemoLocale(uri: Uri.parse(_url));
    await tester.pumpWidget(_app(locale, fragment: '/pages/two'));
    await tester.pumpAndSettle();
    expect(find.text('second body'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(locale, fragment: '/pages/unknown'));
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    locale.dispose();
  });

  testWidgets('CodeBlock is collapsed and copies exact code', (tester) async {
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add(call.arguments['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final locale = DemoLocale(uri: Uri.parse('$_url?lang=en'));
    await tester.pumpWidget(_app(locale));
    await tester.pumpAndSettle();
    expect(find.text('Copy code'), findsNothing);
    await tester.tap(find.text('Show code'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Copy code'));
    await tester.tap(find.text('Copy code'));
    await tester.pump();
    expect(clipboard, [_code]);
    expect(find.text('Code copied'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    locale.dispose();
  });

  testWidgets('grid supports equal rows and full-span panels across widths', (
    tester,
  ) async {
    const sizes = <double>[
      360,
      375,
      599,
      600,
      900,
      999,
      1000,
      1200,
      1500,
      1600,
    ];
    for (final width in sizes) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DemoGrid(
                children: [
                  const DemoGridItem(
                    child: DemoCard(
                      title: 'short',
                      description: 'short',
                      child: Text('body'),
                    ),
                  ),
                  const DemoGridItem(
                    child: DemoCard(
                      title: 'tall',
                      description: 'tall',
                      child: SizedBox(height: 120),
                    ),
                  ),
                  DemoGridItem(
                    span: 0,
                    child: Container(key: const ValueKey('full'), height: 30),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey('full'))).width, width);
      if (DemoGrid.columnsFor(width) > 1) {
        final cards = find.byType(DemoCard);
        expect(
          tester.getSize(cards.at(0)).height,
          tester.getSize(cards.at(1)).height,
        );
      }
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('card detail and info note variants remain readable', (
    tester,
  ) async {
    final locale = DemoLocale(uri: Uri.parse(_url));
    await tester.pumpWidget(
      DemoApp(
        title: 'notes',
        seedColor: Colors.blue,
        locale: locale,
        home: const Scaffold(
          body: Column(
            children: [
              DemoCard(
                title: 'Details',
                description: 'Full description',
                child: Text('body'),
              ),
              InfoNote(text: 'tip'),
              InfoNote(text: 'warning', kind: InfoNoteKind.warning),
              InfoNote(text: 'deprecated', kind: InfoNoteKind.deprecated),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Full description'), findsNWidgets(2));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    locale.dispose();
  });

  testWidgets('native external links copy without dependencies', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = call.arguments['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final locale = DemoLocale(uri: Uri.parse('$_url?lang=en'));
    await tester.pumpWidget(_app(locale));
    await tester.tap(find.byTooltip('pub.dev'));
    await tester.pump();
    expect(copied, _url);
    expect(find.text('Link copied'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    locale.dispose();
  });

  testWidgets('grid remeasures cards after asynchronous body growth', (
    tester,
  ) async {
    final height = ValueNotifier<double>(40);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DemoGrid(
            children: [
              DemoGridItem(
                child: DemoCard(
                  title: 'growing',
                  description: 'description',
                  child: ValueListenableBuilder<double>(
                    valueListenable: height,
                    builder: (_, value, _) => SizedBox(height: value),
                  ),
                ),
              ),
              const DemoGridItem(
                child: DemoCard(
                  title: 'peer',
                  description: 'description',
                  child: Text('body'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    height.value = 180;
    await tester.pump();
    final cards = find.byType(DemoCard);
    expect(
      tester.getSize(cards.at(0)).height,
      tester.getSize(cards.at(1)).height,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    height.dispose();
  });

  testWidgets('DemoCard replay rebuilds only its own body', (tester) async {
    var first = 0;
    var second = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              DemoCard(
                title: 'one',
                description: 'd',
                child: _MountProbe(onMount: () => first++),
              ),
              DemoCard(
                title: 'two',
                description: 'd',
                child: _MountProbe(onMount: () => second++),
              ),
            ],
          ),
        ),
      ),
    );
    expect([first, second], [1, 1]);
    await tester.tap(find.byIcon(Icons.replay_rounded).first);
    await tester.pump();
    expect([first, second], [2, 1]);
  });

  testWidgets('DemoCard hides replay when replayable is false', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DemoCard(
            title: 'still',
            description: 'd',
            replayable: false,
            child: Text('body'),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.replay_rounded), findsNothing);
  });

  testWidgets('card replay remounts its local demo state', (tester) async {
    final locale = DemoLocale(uri: Uri.parse('$_url?lang=en'));
    await tester.pumpWidget(
      DemoApp(
        title: 'replay',
        seedColor: Colors.blue,
        locale: locale,
        home: const Scaffold(
          body: DemoCard(
            title: 'Local state',
            description: 'Reset child state',
            child: TextField(),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'changed');
    await tester.tap(find.byTooltip('Replay'));
    await tester.pump();
    expect(find.text('changed'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    locale.dispose();
  });
  testWidgets(
    'external replay callback resets controller without remounting body',
    (tester) async {
      var resets = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DemoCard(
              title: 'External',
              description: 'Controller',
              onReplay: () => resets++,
              child: const TextField(),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'retained');
      await tester.tap(find.byTooltip('Replay'));
      await tester.pump();
      expect(resets, 1);
      expect(find.text('retained'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
