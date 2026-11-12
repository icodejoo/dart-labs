import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../core/foundation/constants.dart';
import '../../core/motion/phase.dart';
import '../../core/render/cached_picture.dart';
import '../../core/render/layer.dart';
import '../../core/render/paint_helpers.dart';
import '../../core/render/perf_trace.dart';
import '../../core/render/picture_cache.dart';
import '../../core/render/renderer.dart';
import '../../core/render/stir_arms.dart';
import '../layout/lotto_layout.dart';
import '../model/lotto_config.dart';
import '../motion/lotto_motion.dart';

/// 静态背板段。
const int _backId = 0;

/// 静态高光段。
const int _frontId = 1;

/// 静态按钮段。
const int _buttonId = 2;

/// 号码球缓存起点；逐池分配连续下标以兼容用户自定义的任意号码范围。
const int _ballStart = 3;

/// 号码字号占球半径的比例。
const double _numberScale = 0.95;

/// 号码标签最小位数。
const int _numberDigits = 2;

/// 号码左侧补位字符。
const String _numberPadding = '0';

/// 号码与按钮使用的既有字体。
const String _fontFamily = 'Roboto';

/// 高光线宽。
const double _rimWidth = 1.5;

/// 高光白色。
const Color _highlight = Color(0x88FFFFFF);

/// 预录制摇奖机显示列表，每帧只回放与变换。
final class LottoPainter extends CustomPainter {
  /// 创建画笔；[cache] 归渲染表面所有，配置或布局变更前应失效。
  LottoPainter({required this.data, required this.cache})
      : super(
            repaint: Listenable.merge(
                [data.frameListenable, data.imagesListenable])) {
    luckyTraceStart('luckdraw.lotto.record');
    try {
      _context
        ..layout = data.layout
        ..frame = data.frame
        ..size = data.layout.size
        ..devicePixelRatio = data.devicePixelRatio;
      _back = cache.picture(_backId, _recordBack);
      _front = cache.picture(_frontId, _recordFront);
      _button = cache.picture(_buttonId, _recordButton);
      var id = _ballStart;
      _balls = List.generate(
          data.layout.drums.length,
          (p) => List.generate(
              data.layout.drums[p].rest.length,
              (b) => LuckyCachedPicture(
                  cache,
                  id++,
                  _ballBounds(p, b),
                  data.devicePixelRatio,
                  (canvas) => _recordBall(canvas, p, b),
                  data.performance)));
      final physics = data.config.options.physics;
      _arms = List.generate(
          data.layout.drums.length,
          (p) => physics != null && physics.stirArms > 0
              ? LuckyStirArms(
                  containerRadius: data.layout.drums[p].radius,
                  bodyRadius: data.layout.drums[p].ballRadius)
              : null);
      _layerPictures = List.generate(
          data.layers.length,
          (i) => data.layers[i].isStatic
              ? cache.picture(
                  id++, (canvas) => data.layers[i].paint(canvas, _context))
              : null);
    } finally {
      for (final painter in _labels.values) {
        painter.dispose();
      }
      _labels.clear();
      luckyTraceEnd();
    }
  }

  /// 本次布局、配置及复用帧。
  final LuckySurfaceData<LottoConfig, LottoLayout, LottoFrame> data;

  /// 录制期间的已排版文字缓存，构造结束即释放。
  final Map<(String, double, Color), TextPainter> _labels = {};

  /// 表面拥有的缓存。
  final LuckyPictureCache cache;

  /// 背板与结果槽。
  late final ui.Picture _back;

  /// 容器前缘。
  late final ui.Picture _front;

  /// 开始按钮。
  late final ui.Picture _button;

  /// 以池和球下标索引的号码球显示列表。
  late final List<List<LuckyCachedPicture>> _balls;

  /// 各池的拨杆绘制器；未开启物理模式或没有拨杆时为空。
  late final List<LuckyStirArms?> _arms;

  /// 用户静态层缓存，动态层对应空值。
  late final List<ui.Picture?> _layerPictures;

  /// 复用用户层上下文。
  final LuckyLayerContext<LottoLayout, LottoFrame> _context =
      LuckyLayerContext();

  /// 录制容器后板、出口及结果槽。
  void _recordBack(Canvas canvas) {
    final layout = data.layout;
    final paint = luckyScratchPaint(color: data.config.style.drumColor);
    for (final drum in layout.drums) {
      canvas.drawCircle(drum.center, drum.radius, paint);
    }
    paint.color = data.config.style.slotColor;
    for (final drum in layout.drums) {
      for (final slot in drum.slots) {
        canvas.drawCircle(slot, layout.slotRadius * _rimWidth, paint);
      }
      paint.color = data.config.style.rimColor;
      canvas.drawCircle(drum.exit, drum.ballRadius, paint);
      paint.color = data.config.style.slotColor;
    }
  }

  /// 录制圆周及前景高光。
  void _recordFront(Canvas canvas) {
    final paint = luckyScratchPaint(
        color: data.config.style.rimColor,
        style: PaintingStyle.stroke,
        strokeWidth: _rimWidth);
    for (final drum in data.layout.drums) {
      canvas.drawCircle(drum.center, drum.radius, paint);
      final rect =
          Rect.fromCircle(center: drum.center, radius: drum.radius * 0.92);
      paint.color = _highlight;
      canvas.drawArc(rect, -2.6, 1.2, false, paint);
      paint.color = data.config.style.rimColor;
    }
  }

  /// 录制按钮背景和文案。
  void _recordButton(Canvas canvas) {
    final rect = data.layout.button;
    canvas.drawOval(
        rect, luckyScratchPaint(color: data.config.style.buttonColor));
    _text(canvas, data.config.style.buttonText, rect.center,
        rect.height / _ballStart, data.config.style.buttonTextColor);
  }

  /// 录制一颗号码球；只在缓存缺失时创建画笔和文字对象。
  void _recordBall(Canvas canvas, int pool, int ball) {
    final drum = data.layout.drums[pool];
    final config = data.config.pools[pool];
    final rect = Rect.fromCircle(center: Offset.zero, radius: drum.ballRadius);
    final paint = luckyScratchPaint();
    config.ballFill.applyTo(paint, rect);
    canvas.drawCircle(Offset.zero, drum.ballRadius, paint);
    _text(canvas, _ballLabel(pool, ball), Offset.zero,
        drum.ballRadius * _numberScale, config.textColor);
  }

  /// 与录制文字相同的号码标签。
  String _ballLabel(int pool, int ball) => (data.config.pools[pool].min + ball)
      .toString()
      .padLeft(_numberDigits, _numberPadding);

  /// 包含号码文字和抗锯齿边缘的缓存区域，长号码和系统缩放不裁剪。
  Rect _ballBounds(int pool, int ball) {
    final radius = data.layout.drums[pool].ballRadius;
    final circle = Rect.fromCircle(center: Offset.zero, radius: radius);
    final padding = 1 / data.devicePixelRatio;
    final label = _ballLabel(pool, ball);
    if (data.textScale == TextScaler.noScaling &&
        label.length <= _numberDigits) {
      return circle.inflate(padding);
    }
    final painter =
        _label(label, radius * _numberScale, data.config.pools[pool].textColor);
    return circle
        .expandToInclude(Rect.fromCenter(
            center: Offset.zero, width: painter.width, height: painter.height))
        .inflate(padding);
  }

  /// 本次录制内复用的已排版文字；同一号码的测量与绘制只排版一次。
  TextPainter _label(String text, double fontSize, Color color) =>
      _labels.putIfAbsent((text, fontSize, color), () {
        final painter = TextPainter(
            text: TextSpan(
                text: text,
                style: TextStyle(
                    color: color, fontSize: fontSize, fontFamily: _fontFamily)),
            textDirection: data.textDirection,
            textScaler: data.textScale);
        luckyTraceStart(kLuckyTextPainterLayoutTrace, layouts: 1);
        try {
          painter.layout();
        } finally {
          luckyTraceEnd();
        }
        return painter;
      });

  /// 录制期绘制居中文字；文字对象由 [_label] 缓存，录制结束统一释放。
  void _text(
      Canvas canvas, String text, Offset center, double fontSize, Color color) {
    final painter = _label(text, fontSize, color);
    painter.paint(
        canvas,
        center -
            Offset(painter.width / kLuckyHalfDivisor,
                painter.height / kLuckyHalfDivisor));
  }

  /// 回放指定位置的用户层。
  void _layers(Canvas canvas, LuckyLayerPosition position) => luckyReplayLayers(
      canvas, data.layers, _layerPictures, position, _context);

  /// 回放一颗球的缓存；坐标计算只读复用缓冲。
  void _ball(Canvas canvas, int p, int b) {
    final drum = data.layout.drums[p];
    canvas.save();
    canvas.translate(drum.center.dx + data.frame.x[p][b],
        drum.center.dy + data.frame.y[p][b]);
    canvas.rotate(data.frame.slotOf[p][b] < 0 ? data.frame.angle[p][b] : 0);
    _balls[p][b].paint(canvas, isMoving: data.frame.phase.isMoving);
    canvas.restore();
  }

  /// 按背板、球、前景、按钮、用户层顺序绘制，不使用 saveLayer。
  @override
  void paint(Canvas canvas, Size size) {
    luckyTraceStart('luckdraw.lotto.paint');
    try {
      if (data.layout.isEmpty) return;
      data.hooks.beforeDraw?.call(canvas, size);
      _layers(canvas, LuckyLayerPosition.background);
      canvas.drawPicture(_back);
      _layers(canvas, LuckyLayerPosition.belowItems);
      final frame = data.frame;
      for (var p = 0; p < _arms.length; p++) {
        final arms = _arms[p];
        if (arms != null &&
            p < frame.physical.length &&
            frame.physical[p] != 0) {
          arms.paint(canvas, data.layout.drums[p].center, frame.stirDeg[p],
              data.config.options.physics!.stirArms, frame.mix);
        }
      }
      for (var p = 0; p < _balls.length; p++) {
        for (var b = 0; b < _balls[p].length; b++) {
          if (data.frame.slotOf[p][b] < 0) _ball(canvas, p, b);
        }
      }
      for (var p = 0; p < _balls.length; p++) {
        for (var b = 0; b < _balls[p].length; b++) {
          if (data.frame.slotOf[p][b] >= 0) _ball(canvas, p, b);
        }
      }
      canvas.drawPicture(_front);
      _layers(canvas, LuckyLayerPosition.aboveItems);
      canvas.drawPicture(_button);
      _layers(canvas, LuckyLayerPosition.foreground);
      data.hooks.afterDraw?.call(canvas, size);
    } finally {
      luckyTraceEnd();
    }
  }

  /// 布局、图片、配置或绘制层发生低频变更时重绘。
  @override
  bool shouldRepaint(covariant LottoPainter oldDelegate) =>
      oldDelegate.data != data;
}
