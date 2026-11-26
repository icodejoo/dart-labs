import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/cold_mount_budget.dart';
import 'package:xvg/src/rust_static_svg.dart';
import 'package:xvg/xvg.dart' show RustLib;

/// 正方形测试图的边长。
const _svgSide = 24;

/// 等待原生解析结果的最长时间。
const _replyTimeout = Duration(seconds: 5);

/// 小图源，绘制一块全红的 24 × 24 矩形。
const _svg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="$_svgSide" height="$_svgSide">'
    '<rect width="$_svgSide" height="$_svgSide" fill="red"/></svg>';

/// 用空白扩充合法源，精确覆盖长度边界。
String _svgOfLength(int length) => _svg.padRight(length);

/// 生成指定长度的坏 XML，验证实际 Rust 错误传回 widget。
String _invalidSvgOfLength(int length) => '<svg><'.padRight(length);

/// FRB 计数探针，所有调用仍交给真实原生库。
class _ParseHandler extends BaseHandler {
  /// 同步解析次数。
  int syncCalls = 0;

  /// 异步解析次数。
  int asyncCalls = 0;

  /// 最近一次异步解析结果，用于在测试的真实异步区等待。
  Future<Object?>? lastAsync;

  /// 转发同步调用并计数。
  @override
  S executeSync<S, E extends Object, W>(SyncTask<S, E, W> task) {
    if (task.constMeta.debugName == 'parse_svg') syncCalls++;
    return super.executeSync(task);
  }

  /// 转发异步调用并记录它的完成信号。
  @override
  Future<S> executeNormal<S, E extends Object>(NormalTask<S, E> task) {
    final future = super.executeNormal(task);
    if (task.constMeta.debugName == 'parse_svg_async') {
      asyncCalls++;
      lastAsync = future;
    }
    return future;
  }

  /// 清理本用例的计数。
  void reset() {
    syncCalls = 0;
    asyncCalls = 0;
    lastAsync = null;
  }
}

/// 将待测组件置于固定约束和文字方向下。
Widget _mount(Widget svg) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: svg),
);

/// 在真实异步区等待 FRB 回包，再让 FutureBuilder 重建。
Future<void> _awaitPaint(WidgetTester tester, _ParseHandler handler) async {
  await tester.runAsync(() async {
    await handler.lastAsync!.timeout(_replyTimeout);
  });
  await tester.pump();
}

/// 验证原生静态渲染的长度分发、首帧和同键生命周期。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final handler = _ParseHandler();
  final cache = RustXvgPictureCache.instance;
  final painter = find.descendant(
    of: find.byType(StaticXvg),
    matching: find.byType(CustomPaint),
  );
  final futureBuilder = find.byType(FutureBuilder<RustSvgPictureInfo>);
  final svgSize = Size.square(_svgSide.toDouble());

  // 原生库缺失或 ABI 过期应让本组失败，避免静默空跑。
  setUpAll(() => RustLib.init(handler: handler));
  setUp(() {
    handler.reset();
    ColdMountFrameBudget.instance.debugReset();
    cache.clear();
  });
  tearDown(() {
    cache
      ..onParseMiss = null
      ..clear();
  });

  testWidgets('cold large SVG paints after a placeholder frame', (
    tester,
  ) async {
    final source = _svgOfLength(staticSvgAsyncParseThreshold + 1);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        _mount(StaticXvg(source, width: svgSize.width, height: svgSize.height)),
      );
      expect(painter, findsNothing);
      expect(futureBuilder, findsOneWidget);
      expect(cache.peek(source), isNull);
      expect(handler.asyncCalls, 1);
      expect(handler.syncCalls, 0);
    });

    await _awaitPaint(tester, handler);
    expect(painter, findsOneWidget);
    await tester.runAsync(() async {
      final info = cache.peek(source)!;
      final image = await info.picture.toImage(1, 1);
      try {
        final pixels = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(pixels!.buffer.asUint8List(), [255, 0, 0, 255]);
      } finally {
        image.dispose();
      }
    });
  });

  testWidgets('small SVG paints synchronously in its first frame', (
    tester,
  ) async {
    await tester.pumpWidget(_mount(const StaticXvg(_svg)));
    expect(painter, findsOneWidget);
    expect(cache.peek(_svg)!.size, svgSize);
    expect(handler.syncCalls, 1);
    expect(handler.asyncCalls, 0);
  });

  testWidgets('large SVG forwards the async parse error to errorBuilder', (
    tester,
  ) async {
    final source = _invalidSvgOfLength(staticSvgAsyncParseThreshold);
    final rustError = predicate<Object>(
      (error) => error.toString().contains('XML'),
    );
    var errors = 0;
    const errorKey = ValueKey('parse-error');
    await tester.runAsync(() async {
      await tester.pumpWidget(
        _mount(
          StaticXvg(
            source,
            errorBuilder: (_, error, stackTrace) {
              errors++;
              expect(error, rustError);
              expect(stackTrace.toString(), isNotEmpty);
              return const SizedBox(key: errorKey);
            },
          ),
        ),
      );
      expect(find.byKey(errorKey), findsNothing);
      expect(handler.asyncCalls, 1);
      expect(handler.syncCalls, 0);
      await expectLater(
        handler.lastAsync!.timeout(_replyTimeout),
        throwsA(rustError),
      );
    });
    await tester.pump();
    expect(find.byKey(errorKey), findsOneWidget);
    expect(errors, 1);
    expect(cache.peek(source), isNull);
    await tester.runAsync(() async {
      await expectLater(
        cache.getOrRenderAsync(source).timeout(_replyTimeout),
        throwsA(rustError),
      );
    });
    expect(handler.asyncCalls, 2);
  });

  test(
    'concurrent large cache misses share one native parse and recording',
    () async {
      final source = _svgOfLength(staticSvgAsyncParseThreshold);
      var reports = 0;
      cache.onParseMiss = (_) => reports++;
      final first = cache.getOrRenderAsync(source);
      final second = cache.getOrRenderAsync(source);
      expect(second, same(first));
      final [a, b] = await Future.wait([first, second]);
      expect(b, same(a));
      expect(cache.peek(source), same(a));
      expect(handler.asyncCalls, 1);
      expect(handler.syncCalls, 0);
      expect(reports, 1);
      cache.clear();
      final next = await cache.getOrRenderAsync(source);
      expect(next, isNot(same(a)));
      expect(handler.asyncCalls, 2);
      expect(reports, 2);
    },
  );

  testWidgets(
    'threshold is inclusive and a cached large SVG paints immediately',
    (tester) async {
      final below = _svgOfLength(staticSvgAsyncParseThreshold - 1);
      final boundary = _svgOfLength(staticSvgAsyncParseThreshold);
      await tester.pumpWidget(_mount(StaticXvg(below)));
      expect(painter, findsOneWidget);
      expect(handler.syncCalls, 1);
      expect(handler.asyncCalls, 0);
      await tester.runAsync(() async {
        await tester.pumpWidget(_mount(StaticXvg(boundary)));
        expect(painter, findsNothing);
        expect(handler.asyncCalls, 1);
      });
      await _awaitPaint(tester, handler);
      expect(painter, findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_mount(StaticXvg(boundary)));
      expect(painter, findsOneWidget);
      expect(futureBuilder, findsNothing);
      expect(handler.syncCalls, 1);
      expect(handler.asyncCalls, 1);
    },
  );
}
