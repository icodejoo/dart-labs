import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart';
import 'package:svgx/src/svg_source_loader.dart';
import 'package:svgx/src/cold_mount_budget.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';

const spin =
    '<svg width="24" height="24"><rect width="24" height="24"><animate attributeName="opacity" values="0;1" dur="10s" repeatCount="indefinite"/></rect></svg>';

class Bundle extends CachingAssetBundle {
  Bundle(this.value);
  final String value;
  int calls = 0;
  final gate = Completer<String>();
  @override
  Future<String> loadString(String key, {bool cache = true}) {
    calls++;
    return gate.future;
  }

  @override
  Future<ByteData> load(String key) async => ByteData(0);
}

void burn() {
  final sw = Stopwatch()..start();
  while (sw.elapsedMilliseconds < 10) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    SvgSourceLoader.instance.clear();
    ColdMountFrameBudget.instance.debugReset();
    SvgxDocumentCache.instance
      ..clear()
      ..maximumSize = 1000;
  });
  test('network and file load keys use stable values', () {
    final dynamic a = Svgx.network(
      'http://example/a',
      headers: {'a': '1', 'b': '2'},
    );
    final dynamic b = Svgx.network(
      'http://example/a',
      headers: {'b': '2', 'a': '1'},
    );
    expect(a.loadKey, b.loadKey);
    final dynamic x = Svgx.file(File('same.svg'));
    final dynamic y = Svgx.file(File('same.svg'));
    expect(x.loadKey, y.loadKey);
  });
  test('theme compares all values', () {
    final a = SvgxTheme(currentColor: const Color(0xff123456));
    final b = SvgxTheme(currentColor: const Color(0xff123456));
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(StringSvgx(spin, theme: a), StringSvgx(spin, theme: b));
  });
  test('asset cache isolates bundles and merges in-flight requests', () async {
    final a = Bundle('a'), b = Bundle('b');
    final x = SvgSourceLoader.instance.asset('same', bundle: a);
    final y = SvgSourceLoader.instance.asset('same', bundle: a);
    final z = SvgSourceLoader.instance.asset('same', bundle: b);
    a.gate.complete('a');
    b.gate.complete('b');
    expect(await Future.wait([x, y, z]), ['a', 'a', 'b']);
    expect(a.calls, 1);
    expect(await SvgSourceLoader.instance.asset('same', bundle: b), 'b');
  });
  test('throwing work still consumes budget', () {
    expect(
      () => ColdMountFrameBudget.instance.runNow(() {
        burn();
        throw StateError('work');
      }),
      throwsStateError,
    );
    expect(ColdMountFrameBudget.instance.hasRoom, false);
  });
  testWidgets('budget resets even without deferred work', (tester) async {
    ColdMountFrameBudget.instance.runNow(burn);
    expect(ColdMountFrameBudget.instance.hasRoom, false);
    await tester.pumpWidget(const SizedBox());
    expect(ColdMountFrameBudget.instance.hasRoom, true);
  });
  test('document cache converges after reducing maximumSize', () {
    final c = SvgxDocumentCache.instance;
    for (var i = 0; i < 8; i++) {
      c.getOrParse('<svg width="24" height="24"><!--$i--></svg>');
    }
    c.maximumSize = 1;
    c.getOrParse(spin);
    expect(c.length, 1);
  });
  testWidgets('animated dispatch applies filter only when supplied', (
    tester,
  ) async {
    const filter = ColorFilter.mode(Colors.red, BlendMode.srcIn);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Svgx.string(spin, colorFilter: filter),
      ),
    );
    expect(find.byType(ColorFiltered), findsOneWidget);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Svgx.string(spin),
      ),
    );
    expect(find.byType(ColorFiltered), findsNothing);
  });
  testWidgets('rate changes preserve virtual time', (tester) async {
    Widget w(double rate) => Directionality(
      textDirection: TextDirection.ltr,
      child: SvgxAnimated.string(spin, playbackRate: rate),
    );
    Duration time() =>
        (tester.widget<CustomPaint>(find.byType(CustomPaint)).painter
                as AnimatedSvgPainter)
            .clock
            .value;
    await tester.pumpWidget(w(1));
    await tester.pump(const Duration(milliseconds: 100));
    final before = time();
    await tester.pumpWidget(w(2));
    await tester.pump(const Duration(milliseconds: 100));
    expect((time() - before).inMilliseconds, closeTo(200, 2));
  });
  testWidgets('source replacement keeps previous SVG during load', (
    tester,
  ) async {
    final a = Bundle('a'), b = Bundle('b');
    Widget w(Bundle bundle) => Directionality(
      textDirection: TextDirection.ltr,
      child: Svgx.asset('a', bundle: bundle),
    );
    await tester.pumpWidget(w(a));
    a.gate.complete(spin);
    await tester.pump();
    await tester.pump();
    expect(find.byType(SvgxAnimated), findsOneWidget);
    await tester.pumpWidget(w(b));
    expect(find.byType(SvgxAnimated), findsOneWidget);
    b.gate.complete(spin);
    await tester.pump();
  });
  testWidgets('invalid animated provider reports parse errors to listener', (
    tester,
  ) async {
    Object? error;
    final stream = const StringSvgx('<svg><animate>')
        .resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (_, _) {},
      onError: (Object e, StackTrace? s) {
        error = e;
      },
    );
    stream.addListener(listener);
    await tester.pump();
    expect(error, isNotNull);
    stream.removeListener(listener);
  });
}
