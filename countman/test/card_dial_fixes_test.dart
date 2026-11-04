import 'package:countman/countman.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/manual_clock.dart';

/// 卡片语义与小时列切换用例共用的初始时长。
const _initialDuration = Duration(minutes: 10);

/// 字形缓存与透明度用例共用的倒计时时长。
const _cardDuration = Duration(seconds: 5);

/// 翻牌进行中的细粒度推进间隔。
const _fineStep = Duration(milliseconds: 100);

/// 验证背景与文字透明度叠乘的半透明黑色。
const _halfAlphaBlack = Color(0x80000000);

/// 为卡片和表盘用例提供相同的主题、文字方向及居中布局。
Widget _host(Widget child) => MaterialApp(home: Center(child: child));

/// 记录内环圆弧次数及画笔身份，不依赖实际光栅化结果。
class _ArcCanvas implements Canvas {
  /// 每次绘制圆弧时保存同一个画笔实例。
  final paints = <Paint>[];

  /// 记录弧段绘制。
  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter,
      Paint paint) {
    paints.add(paint);
  }

  /// 本用例不关心其他 Canvas 操作。
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 保存绘制时卡片的 alpha，避免画笔后续原地更新影响断言。
class _AlphaCanvas implements Canvas {
  /// 卡片实际使用的不透明度。
  final alphas = <double>[];

  /// 记录卡片背景色。
  @override
  void drawRRect(RRect rrect, Paint paint) {
    alphas.add(paint.color.a);
  }

  /// 其他操作与本用例无关。
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 获取卡片常驻绘制模型。
FlipCardPainter painter(WidgetTester t) => t
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<FlipCardPainter>()
    .single;

/// 验证小时扩位和倒计时语义同步。
void main() {
  late ManualCountmanClock clock;
  setUp(() {
    clock = installManualClock(wallTime: DateTime(2026));
  });
  tearDown(Countman.destroy);
  testWidgets('123 小时拆成三个小时数字', (t) async {
    await t.pumpWidget(_host(const CardCountdown(to: Duration(hours: 123))));
    expect(painter(t).model.committed.take(3), [1, 2, 3]);
    expect(painter(t).geom.cells.length, 7);
  });
  testWidgets('语义从真实剩余时间初始化', (t) async {
    await t.pumpWidget(_host(const CardCountdown(to: _initialDuration)));
    expect(
        find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.value == '00:10:00'),
        findsOneWidget);
  });
  testWidgets('切换 showHours 保留当前剩余时间且语义随 tick 更新', (t) async {
    const elapsed = Duration(minutes: 3);
    await t.pumpWidget(
        _host(const CardCountdown(to: _initialDuration, showHours: false)));
    await t.pump();
    clock.advance(elapsed);
    await t.pump(elapsed);
    await t.pumpWidget(
        _host(const CardCountdown(to: _initialDuration, showHours: true)));
    expect(painter(t).model.committed, [0, 0, 0, 7, 0, 0]);
    expect(
        find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.value == '00:07:00'),
        findsOneWidget);
  });
  testWidgets('细粒度 tick 相同目标不会重新启动翻牌', (t) async {
    final plugin = Countdown(name: 'card-fine', interval: 0);
    Countman.use(plugin);
    await t.pumpWidget(_host(CardCountdown(
        to: const Duration(seconds: 10),
        plugin: plugin,
        duration: const Duration(seconds: 1),
        style: const CardCountdownStyle(transitionType: CountdownType.slide))));
    await t.pump();
    clock.advance(const Duration(milliseconds: 1100));
    await t.pump(const Duration(milliseconds: 16));
    clock.advance(_fineStep);
    await t.pump(_fineStep);
    final before = painter(t).controller.value;
    final currentPainter = painter(t);
    clock.advance(_fineStep);
    await t.pump(_fineStep);
    expect(painter(t).controller.value, greaterThan(before));
    expect(identical(currentPainter, painter(t)), isTrue);
  });
  testWidgets('Odometer 非有限端点不抛出且完成值使用实际钳制值', (t) async {
    double? completed;
    await t.pumpWidget(_host(OdometerCounter(
        from: double.nan,
        to: -10,
        duration: Duration.zero,
        onComplete: (v) => completed = v)));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(completed, 0);
  });
  testWidgets('内环长倒计时绘制次数固定且复用画笔', (t) async {
    for (final days in [1, 30]) {
      await t.pumpWidget(_host(DialCountdown(
          key: ValueKey(days),
          to: Duration(days: days),
          style: const DialCountdownStyle(
              showTicks: false, showArcA: false, showArcB: false))));
      final p = t
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<CustomPainter>()
          .single;
      final canvas = _ArcCanvas();
      p.paint(canvas, const Size.square(200));
      expect(canvas.paints.length, 4);
      expect(canvas.paints.toSet().length, 1);
    }
  });
  testWidgets('天单元按需扩位并将小时限制为 0–23', (t) async {
    await t.pumpWidget(_host(const CardCountdown(
        to: Duration(days: 2, hours: 3), showDays: true, dayLabel: '天')));
    expect(painter(t).model.committed, [2, 0, 3, 0, 0, 0, 0]);
    expect(painter(t).geom.unitLabelText, ['天', 'H', 'M', 'S']);
    await t.pumpWidget(_host(const CardCountdown(
        to: Duration(days: 123, hours: 3), showDays: true)));
    expect(painter(t).model.committed.take(5), [1, 2, 3, 0, 3]);
    expect(painter(t).geom.cells.length, 9);
  });
  testWidgets('翻牌透明度叠乘卡片与文字原 alpha', (t) async {
    await t.pumpWidget(_host(const CardCountdown(
        to: _cardDuration,
        style: CardCountdownStyle(
            cardColor: _halfAlphaBlack,
            textStyle: TextStyle(color: _halfAlphaBlack)))));
    final p = painter(t);
    final canvas = _AlphaCanvas();
    p.drawFaceWithAlpha(
        canvas, const Rect.fromLTWH(0, 0, 30, 50), 2, BorderRadius.zero, .5);
    expect(canvas.alphas.single, closeTo(.25, .01));
    final styles = p.digitCache.keys
        .where((key) => key.$1 == '2')
        .map((key) => key.$2.color!.a);
    expect(styles, everyElement(lessThan(.3)));
  });
  test('共享字形缓存有界且淘汰时释放段落', () {
    final cache = CardGlyphCache();
    final first = TextPainter(
        text: const TextSpan(text: '0'), textDirection: TextDirection.ltr)
      ..layout();
    cache[('0', const TextStyle())] = first;
    for (var i = 1; i <= CardGlyphCache.capacity; i++) {
      cache[('$i', const TextStyle())] = TextPainter(
          text: TextSpan(text: '$i'), textDirection: TextDirection.ltr)
        ..layout();
    }
    expect(cache.length, CardGlyphCache.capacity);
    expect(first.debugDisposed, isTrue);
    cache.clear();
  });
  testWidgets('样式变化释放本地及共享旧字形', (t) async {
    const red = TextStyle(color: Colors.red);
    const blue = TextStyle(color: Colors.blue);
    await t.pumpWidget(_host(const CardCountdownProvider(
        textStyle: red, child: CardCountdown(to: _cardDuration))));
    final old = painter(t).digitCache.values.toList();
    await t.pumpWidget(_host(const CardCountdownProvider(
        textStyle: blue, child: CardCountdown(to: _cardDuration))));
    expect(old.map((p) => p.debugDisposed), everyElement(isTrue));
    await t.pumpWidget(_host(const CardCountdown(
        to: _cardDuration, style: CardCountdownStyle(textStyle: red))));
    final local = painter(t).digitCache.values.toList();
    await t.pumpWidget(_host(const CardCountdown(
        to: _cardDuration, style: CardCountdownStyle(textStyle: blue))));
    expect(local.map((p) => p.debugDisposed), everyElement(isTrue));
  });
  test('Dial 注释无替换字符且 Odometer 构造器标记废弃参数', () {
    expect(File('lib/src/widgets/dial_countdown.dart').readAsStringSync(),
        isNot(contains('\uFFFD')));
    expect(
        File('lib/src/widgets/odometer_counter.dart')
            .readAsStringSync()
            .replaceAll('\r\n', '\n'),
        contains(
            "@Deprecated('No effect; use bounceOvershoot instead')\n    this.bounceElasticity"));
  });
}
