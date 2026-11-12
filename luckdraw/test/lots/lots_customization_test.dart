import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/lots.dart';
import 'package:luckdraw/src/lots/motion/lots_motion.dart';
import 'package:luckdraw/src/lots/render/lots_painter.dart';

import '../support/lots_fixtures.dart';
import '../support/recording_canvas.dart';

/// 自定义布局的画布尺寸。
const Size _size = Size(320, 480);

/// 自定义签筒边界。
const Rect _cylinder = Rect.fromLTWH(80, 220, 160, 180);

/// 两个不同尺寸的自定义槽位。
const List<Rect> _slots = [
  Rect.fromLTWH(100, 140, 18, 150),
  Rect.fromLTWH(180, 100, 24, 200)
];

/// 自定义扇形角度，单位为弧度。
const List<double> _angles = [-0.1, 0.3];

/// 自定义升签距离。
const double _rise = 90;

/// 自定义卡片边界。
const Rect _card = Rect.fromLTWH(30, 20, 260, 110);

/// 浮点比较误差。
const double _epsilon = 1e-10;

/// 替换全部几何参数以验证调整器使用最终布局。
LotsLayout _adjust(LotsLayout base) => base.copyWith(
    size: _size,
    cylinder: _cylinder,
    pivot: _cylinder.bottomCenter,
    sticks: _slots,
    angles: _angles,
    riseDistance: _rise,
    card: _card);

/// 创建空布局，保留其余默认几何。
LotsLayout _empty(LotsLayout base) => base.copyWith(sticks: [], angles: []);

/// 记录缓动调用参数并使用线性进度。
final class _RecordingEasing implements LuckyEasing {
  /// 减速调用的时间、起点、变化量和时长。
  final List<List<double>> calls = [];

  /// 此测试不使用加速入口。
  @override
  double easeIn(double t, double b, double c, double d) =>
      throw StateError('升签与翻卡必须调用 easeOut');

  /// 返回线性减速进度并保存调用参数。
  @override
  double easeOut(double t, double b, double c, double d) {
    calls.add([t, b, c, d]);
    return b + c * (t / d).clamp(0, 1);
  }
}

/// 验证抽签的缓动、波形、布局和部件录制扩展契约。
void main() {
  test('默认扩展参数保留原来的缓动、正弦波与布局', () {
    const options = LotsOptions();
    expect(options.riseEasing, same(LuckyEasings.quad));
    expect(options.revealEasing, same(LuckyEasings.cubic));
    expect(options.shakeWaveform, same(lotsSineWaveform));
    expect(options.layoutAdjuster, isNull);
    for (final phase in [-450.0, -90.0, 0.0, 45.0, 90.0, 180.0, 720.0]) {
      expect(options.shakeWaveform(phase),
          closeTo(math.sin(phase * math.pi / 180), _epsilon));
    }
    final motion = lotsMotion();
    cruiseLots(motion);
    motion.tick(120, 20);
    expect(
        motion.frame.shakeDeg,
        lotsFixture.options.maxShakeDeg *
            math.sin(motion.frame.shakePhaseDeg * math.pi / 180));
    motion.stop(1);
    motion.tick(370, 250);
    expect(motion.frame.riseProgress, LuckyEasings.quad.easeOut(50, 0, 1, 100));
    motion.tick(470, 100);
    expect(
        motion.frame.revealProgress, LuckyEasings.cubic.easeOut(50, 0, 1, 100));
    final base = lotsLayout();
    final adjusted = lotsLayout(lotsFixture.copyWith(
        options: lotsFixture.options.copyWith(layoutAdjuster: (base) => base)));
    expect(adjusted.size, base.size);
    expect(adjusted.cylinder, base.cylinder);
    expect(adjusted.pivot, base.pivot);
    expect(adjusted.sticks, base.sticks);
    expect(adjusted.angles, base.angles);
    expect(adjusted.riseDistance, base.riseDistance);
    expect(adjusted.card, base.card);
  });

  test('自定义升签与翻卡缓动收到 easeOut 时间参数并控制帧进度', () {
    final rise = _RecordingEasing(), reveal = _RecordingEasing();
    final motion = lotsMotion(lotsFixture.copyWith(
        options: lotsFixture.options
            .copyWith(riseEasing: rise, revealEasing: reveal)));
    cruiseLots(motion);
    motion.stop(1);
    motion.tick(350, 250);
    expect(rise.calls.single, [50, 0, 1, 100]);
    expect(motion.frame.riseProgress, 0.5);
    expect(reveal.calls, isEmpty);
    motion.tick(450, 100);
    expect(reveal.calls.single, [50, 0, 1, 100]);
    expect(motion.frame.revealProgress, 0.5);
    expect(motion.frame.riseProgress, 1);
    settleLots(motion);
    expect(motion.frame.revealProgress, 1);
  });

  test('自定义波形收到累计角度且乘以加速、匀速、阻尼和待机振幅', () {
    final phases = <double>[];
    final config = lotsFixture.copyWith(
        options: lotsFixture.options.copyWith(shakeWaveform: (phaseDeg) {
      phases.add(phaseDeg);
      return -0.5;
    }));
    final motion = lotsMotion(config)..start();
    motion.tick(50, 50);
    expect(phases.last, motion.frame.shakePhaseDeg);
    expect(motion.frame.shakeDeg,
        -6 * config.options.motion.accelerationEasing.easeIn(50, 0, 1, 100));
    motion.tick(100, 50);
    motion.tick(120, 20);
    expect(motion.frame.shakeDeg, -6);
    motion.stop(1);
    motion.tick(220, 100);
    expect(
        motion.frame.shakeDeg,
        -6 *
            (1 -
                config.options.motion.decelerationEasing
                    .easeOut(100, 0, 1, 200)));
    motion.reset();
    motion.idleSpin();
    motion.tick(240, 20);
    expect(motion.frame.shakeDeg, -6);
    expect(phases.last, motion.frame.shakePhaseDeg);
    expect(phases, hasLength(5));
  });

  test('布局副本与调整器可覆盖所有几何并改变目标槽位数量', () {
    final base = lotsLayout(), copy = lotsLayout().copyWith();
    expect(copy.size, base.size);
    expect(copy.cylinder, base.cylinder);
    expect(copy.pivot, base.pivot);
    expect(copy.sticks, base.sticks);
    expect(copy.angles, base.angles);
    expect(copy.riseDistance, base.riseDistance);
    expect(copy.card, base.card);
    var calls = 0;
    final config = lotsFixture.copyWith(
        options: lotsFixture.options.copyWith(layoutAdjuster: (layout) {
      calls++;
      expect(layout.sticks, base.sticks);
      return _adjust(layout);
    }));
    final layout = lotsLayout(config);
    expect(calls, 1);
    expect(layout.size, _size);
    expect(layout.cylinder, _cylinder);
    expect(layout.pivot, _cylinder.bottomCenter);
    expect(layout.sticks, _slots);
    expect(layout.angles, _angles);
    expect(layout.riseDistance, _rise);
    expect(layout.card, _card);
    expect(layout.raisedStick(0), _slots.first.shift(const Offset(0, -_rise)));
    final motion = LotsMotion()..configure(config, layout);
    cruiseLots(motion);
    motion.stop(2);
    settleLots(motion);
    expect(motion.frame.targetSlot, 0);
  });

  test('调整器返回空布局时运动、命中和直接绘制均安全', () {
    final notifier = LuckyFrameNotifier(), cache = LuckyPictureCache();
    addTearDown(notifier.dispose);
    addTearDown(cache.dispose);
    for (final LotsLayoutAdjuster adjust in [
      _empty,
      (base) => base.copyWith(size: Size.zero)
    ]) {
      final config = lotsFixture.copyWith(
          options: lotsFixture.options.copyWith(layoutAdjuster: adjust));
      final data = lotsSurface(notifier, config: config);
      expect(data.layout.isEmpty, isTrue);
      final motion = LotsMotion()..configure(config, data.layout);
      expect(motion.start(), isFalse);
      expect(motion.idleSpin(), isFalse);
      expect(motion.tick(100, 100), 0);
      expect(
          const LotsGame()
              .hitTestAll(config, data.layout, motion.frame, Offset.zero),
          isEmpty);
      final canvas = TestRecordingCanvas();
      LotsPainter(data, cache).paint(canvas, data.layout.size);
      expect(canvas.invocations, isEmpty);
      expect(cache.debugRecordCount, 0);
    }
  });

  testWidgets('空布局调整器经过 LuckyLots 宿主时不抛异常', (tester) async {
    final controller = LotsController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: LuckyLots(
            controller: controller,
            config: lotsFixture.copyWith(
                options:
                    lotsFixture.options.copyWith(layoutAdjuster: _empty)))));
    controller.play();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('非空自定义布局的槽位和角度数量必须一致', () {
    final config = lotsFixture.copyWith(
        options: lotsFixture.options
            .copyWith(layoutAdjuster: (base) => base.copyWith(angles: [])));
    expect(() => lotsLayout(config), throwsAssertionError);
  });

  test('新选项的副本、相等性和哈希包含全部扩展字段', () {
    /// 固定幅度，使用同一函数引用验证值语义。
    double waveform(double phaseDeg) => 0;
    final options = LotsOptions(
        riseEasing: LuckyEasings.sine,
        revealEasing: LuckyEasings.quart,
        shakeWaveform: waveform,
        layoutAdjuster: _adjust);
    expect(options.copyWith(), options);
    expect(options.copyWith().hashCode, options.hashCode);
    expect(
        options.copyWith(
            riseEasing: options.riseEasing,
            revealEasing: options.revealEasing,
            shakeWaveform: waveform,
            layoutAdjuster: _adjust),
        options);
    final variants = [
      options.copyWith(riseEasing: LuckyEasings.quad),
      options.copyWith(revealEasing: LuckyEasings.cubic),
      options.copyWith(shakeWaveform: (_) => 0),
      options.copyWith(layoutAdjuster: (base) => _adjust(base)),
    ];
    for (final variant in variants) {
      expect(variant, isNot(options));
      expect(variant.hashCode, isNot(options.hashCode));
      expect(variant.copyWith(), variant);
      expect(variant.copyWith().hashCode, variant.hashCode);
    }
    expect(const LotsOptions().layoutAdjuster, isNull);
  });

  test('新样式的副本、相等性和哈希按绘制闭包引用比较', () {
    /// 共用的部件绘制函数。
    void part(Canvas canvas, LotsLayout layout) {}

    /// 共用的签身绘制函数。
    void stick(Canvas canvas, Size size, LotsStick? stick) {}
    final style = LotsStyle(
        backgroundPainter: part,
        cylinderBackPainter: part,
        cylinderFrontPainter: part,
        stickPainter: stick);
    expect(style.copyWith(), style);
    expect(style.copyWith().hashCode, style.hashCode);
    expect(
        style.copyWith(
            backgroundPainter: part,
            cylinderBackPainter: part,
            cylinderFrontPainter: part,
            stickPainter: stick),
        style);
    final variants = [
      style.copyWith(backgroundPainter: (_, __) {}),
      style.copyWith(cylinderBackPainter: (_, __) {}),
      style.copyWith(cylinderFrontPainter: (_, __) {}),
      style.copyWith(stickPainter: (_, __, ___) {}),
    ];
    for (final variant in variants) {
      expect(variant, isNot(style));
      expect(variant.hashCode, isNot(style.hashCode));
      expect(variant.copyWith(), variant);
      expect(variant.copyWith().hashCode, variant.hashCode);
    }
    const defaults = LotsStyle();
    expect(defaults.backgroundPainter, isNull);
    expect(defaults.cylinderBackPainter, isNull);
    expect(defaults.cylinderFrontPainter, isNull);
    expect(defaults.stickPainter, isNull);
  });

  test('部件和签身在最终布局坐标中分别录制一次且动画只回放缓存', () {
    final notifier = LuckyFrameNotifier(), cache = LuckyPictureCache();
    addTearDown(notifier.dispose);
    addTearDown(cache.dispose);
    final parts = <String>[];
    final bodies = <(Size, LotsStick?, Offset)>[];
    final cards = <Rect>[];
    final config = lotsFixture.copyWith(
        options: lotsFixture.options.copyWith(layoutAdjuster: _adjust),
        sticks: [
          ...lotsFixture.sticks,
          LotsStick(label: 'extra', painter: (_, rect) => cards.add(rect))
        ],
        style: lotsFixture.style.copyWith(backgroundPainter: (canvas, layout) {
          expect(canvas.getTransform()[12], 0);
          expect(layout.card, _card);
          parts.add('background');
        }, cylinderBackPainter: (canvas, layout) {
          expect(canvas.getTransform()[13], 0);
          expect(layout.cylinder, _cylinder);
          parts.add('back');
        }, cylinderFrontPainter: (canvas, layout) {
          expect(layout.pivot, _cylinder.bottomCenter);
          parts.add('front');
        }, stickPainter: (canvas, size, stick) {
          final transform = canvas.getTransform();
          bodies.add((size, stick, Offset(transform[12], transform[13])));
          canvas.drawRect(Offset.zero & size, Paint());
        }));
    final frame = LotsFrame()
      ..targetIndex = 3
      ..targetSlot = 1
      ..riseProgress = 0.5
      ..revealProgress = 0.5;
    final data = lotsSurface(notifier, config: config, frame: frame);
    final painter = LotsPainter(data, cache);
    expect(parts, ['background', 'back', 'front']);
    expect(bodies, [
      for (final slot in _slots) (slot.size, null, slot.topLeft),
      for (var i = 0; i < config.sticks.length; i++)
        (
          _slots[i % _slots.length].size,
          config.sticks[i],
          _slots[i % _slots.length].topLeft
        )
    ]);
    expect(cards, [_card]);
    final count = 3 + _slots.length + config.sticks.length * 2;
    expect(cache.debugRecordCount, count);
    for (var i = 0; i < 3; i++) {
      final canvas = TestRecordingCanvas();
      painter.paint(canvas, data.layout.size);
      canvas.expectBalancedWithoutSaveLayer();
      expect(canvas.countCalls(#drawPicture), 3 + _slots.length + 1);
      expect(
          canvas.invocations.any((record) =>
              record.invocation.memberName == #translate &&
              record.invocation.positionalArguments[1] ==
                  -_rise * frame.riseProgress),
          isTrue);
    }
    LotsPainter(data, cache).paint(TestRecordingCanvas(), data.layout.size);
    expect(cache.debugRecordCount, count);
    expect(parts, hasLength(3));
    expect(bodies, hasLength(_slots.length + config.sticks.length));
    expect(cards, hasLength(1));
  });

  testWidgets('每个绘制闭包变化均使宿主图片缓存失效且重复构建复用', (tester) async {
    final notifier = LuckyFrameNotifier();
    addTearDown(notifier.dispose);
    final calls = <String, int>{};

    /// 创建可区分版本的部件绘制器。
    LotsPartPainter part(String id) => (_, __) {
          calls.update(id, (count) => count + 1, ifAbsent: () => 1);
        };

    /// 创建可区分版本的签身绘制器。
    LotsStickBodyPainter body(String id) => (_, __, ___) {
          calls.update(id, (count) => count + 1, ifAbsent: () => 1);
        };

    /// 保持布局代数不变，仅借助配置相等性触发缓存失效。
    Future<LotsPainter> pump(LotsStyle style) async {
      final data =
          lotsSurface(notifier, config: lotsFixture.copyWith(style: style));
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
              builder: (context) =>
                  const LotsCanvasRenderer().buildSurface(context, data))));
      return tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!
          as LotsPainter;
    }

    var style = lotsFixture.style;
    final initial = await pump(style);
    var records = initial.cache.debugRecordCount;
    final styles = [
      style = style.copyWith(backgroundPainter: part('background')),
      style = style.copyWith(cylinderBackPainter: part('back')),
      style = style.copyWith(cylinderFrontPainter: part('front')),
      style = style.copyWith(stickPainter: body('body')),
      style = style.copyWith(stickPainter: body('replacement')),
    ];
    for (final style in styles) {
      final painter = await pump(style);
      expect(painter.cache.debugRecordCount, greaterThan(records));
      records = painter.cache.debugRecordCount;
      final previous = Map<String, int>.of(calls);
      await pump(style.copyWith());
      expect(painter.cache.debugRecordCount, records);
      expect(calls, previous);
    }
    expect(calls['background'], 5);
    expect(calls['back'], 4);
    expect(calls['front'], 3);
    expect(calls['body'], 12 + lotsFixture.sticks.length);
    expect(calls['replacement'], 12 + lotsFixture.sticks.length);
    final defaults = await pump(lotsFixture.style);
    expect(defaults.cache.debugRecordCount, greaterThan(records));
    await tester.pumpWidget(const SizedBox());
  });
}
