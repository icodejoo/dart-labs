import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/foundation/angles.dart';
import '../../core/foundation/fill.dart';
import '../../core/foundation/image.dart';
import '../../core/foundation/text.dart';
import '../../core/geometry/image_box.dart';
import '../../core/render/layer.dart';
import '../../core/render/paint_helpers.dart';
import '../../core/render/perf_trace.dart';
import '../../core/render/picture_cache.dart';
import '../../core/render/renderer.dart';
import '../../core/text/text_line.dart';
import '../../core/text/text_measurer.dart';
import '../layout/lots_layout.dart';
import '../model/lots_config.dart';
import '../motion/lots_motion.dart';

/// 背景段编号。
const int _backgroundId = 0;

/// 后壁段编号。
const int _backId = 1;

/// 无字签段编号。
const int _bareId = 2;

/// 前壁段编号。
const int _frontId = 3;

/// 有字签段编号起点（T5.8）。
const int _namedBase = 4000;

/// 签文卡段编号起点，负编号避免与签段冲突。
const int _cardBase = -1;

/// 用户层段编号起点。
const int _layerBase = 100;

/// 录制签文卡图片的分组名。
const String _imageGroup = 'sticks';

/// 单位无字签矩形。
const Rect _unitStick = Rect.fromLTWH(0, 0, 1, 1);

/// 签上标签的纵向留白比例。
const double _labelInset = 0.08;

/// 抽签画笔；所有显示列表在构造时准备，帧内只变换回放。
final class LotsPainter extends CustomPainter {
  /// 使用 surface 所有的 [cache] 准备静态段。
  LotsPainter(this.data, this.cache)
      : super(
            repaint: Listenable.merge(
                [data.frameListenable, data.imagesListenable])) {
    luckyTraceStart('luckdraw.lots.record');
    try {
      _cardCenter = data.layout.card.center;
      _background = cache.picture(
          _backgroundId,
          (canvas) => _fill(canvas, Offset.zero & data.layout.size,
              data.config.style.background));
      _back = cache.picture(
          _backId,
          (canvas) =>
              _fill(canvas, data.layout.cylinder, data.config.style.backFill));
      _bare = cache.picture(_bareId,
          (canvas) => _fill(canvas, _unitStick, data.config.style.stickFill));
      _front = cache.picture(
          _frontId,
          (canvas) => _fill(
              canvas, data.layout.cylinder, data.config.style.cylinderFill));
      for (var i = 0; i < data.config.sticks.length; i++) {
        final index = i;
        _named.add(cache.picture(
            _namedBase + i, (canvas) => _recordNamed(canvas, index)));
        _cards.add(cache.picture(
            _cardBase - i, (canvas) => _recordCard(canvas, index)));
      }
      _context = LuckyLayerContext<LotsLayout, LotsFrame>()
        ..size = data.layout.size
        ..layout = data.layout
        ..frame = data.frame
        ..devicePixelRatio = data.devicePixelRatio;
      for (var i = 0; i < data.layers.length; i++) {
        final layer = data.layers[i];
        _layerPictures.add(layer.isStatic
            ? cache.picture(
                _layerBase + i, (canvas) => layer.paint(canvas, _context))
            : null);
      }
    } finally {
      luckyTraceEnd();
    }
  }

  /// 当前宿主输入。
  final LuckySurfaceData<LotsConfig, LotsLayout, LotsFrame> data;

  /// surface 持有的缓存。
  final LuckyPictureCache cache;

  /// 低频阶段预算的卡片中心，避免绘制时由 Rect.center 创建 Offset。
  late final Offset _cardCenter;

  /// 背景段。
  late final ui.Picture _background;

  /// 签筒后壁。
  late final ui.Picture _back;

  /// 共用无字签。
  late final ui.Picture _bare;

  /// 签筒前壁。
  late final ui.Picture _front;

  /// 各目标签段。
  final List<ui.Picture> _named = [];

  /// 各签文卡段。
  final List<ui.Picture> _cards = [];

  /// 复用层上下文。
  late final LuckyLayerContext<LotsLayout, LotsFrame> _context;

  /// 静态用户层，动态层为空。
  final List<ui.Picture?> _layerPictures = [];

  /// 录制矩形填充。
  void _fill(Canvas canvas, Rect rect, LuckyFill fill) =>
      paintLuckyFill(canvas, Path()..addRect(rect), fill, rect);

  /// 录制目标签和签名。
  void _recordNamed(Canvas canvas, int index) {
    final rect = data.layout.sticks[index % data.layout.sticks.length];
    final stick = data.config.sticks[index];
    _fill(canvas, rect, stick.fill ?? data.config.style.stickFill);
    final painter = TextPainter(
        text: TextSpan(
            text: stick.label,
            style: TextStyle(
                color: data.config.style.textColor,
                fontSize: data.config.style.fontSize,
                fontFamily: data.config.style.fontFamily)),
        textDirection: data.textDirection,
        textScaler: data.textScale);
    try {
      luckyTraceStart(kLuckyTextPainterLayoutTrace, layouts: 1);
      try {
        painter.layout(maxWidth: rect.width);
      } finally {
        luckyTraceEnd();
      }
      painter.paint(
          canvas, Offset(rect.left, rect.top + rect.height * _labelInset));
    } finally {
      painter.dispose();
    }
  }

  /// 录制签文卡背景、图片、文字与自绘内容。
  void _recordCard(Canvas canvas, int index) {
    final stick = data.config.sticks[index], rect = data.layout.card;
    _fill(canvas, rect, data.config.style.cardFill);
    for (var i = 0; i < stick.images.length; i++) {
      final slot = LuckyImageSlot(_imageGroup, index, i);
      final resolved = data.images[slot];
      if (resolved == null) continue;
      final image = stick.images[i];
      final placement = LuckyImagePlacement(
          slot: slot,
          image: image,
          box: rect,
          maxWidth: rect.width,
          maxHeight: rect.height,
          leftBase: rect.width,
          topBase: rect.height);
      drawLuckyImage(
          canvas, resolved.image, placement.place(resolved.naturalSize),
          opacity: image.opacity, borderRadius: image.borderRadius);
    }
    final measurer = TextPainterMeasurer(
        textScaler: data.textScale, textDirection: data.textDirection);
    try {
      final defaults = LuckyTextDefaults(
          color: data.config.style.textColor,
          fontSize: data.config.style.fontSize,
          fontFamily: data.config.style.fontFamily);
      for (final text in stick.texts) {
        final lines = layoutLuckyTextLines(
            text: text,
            defaults: defaults,
            measurer: measurer,
            box: rect,
            leftBase: rect.width,
            topBase: rect.height,
            maxWidthOf: (_, __) => rect.width);
        paintLuckyTextLines(canvas, lines, measurer,
            textDirection: data.textDirection, textScale: data.textScale);
      }
    } finally {
      measurer.dispose();
    }
    stick.painter?.call(canvas, rect);
  }

  /// 绕签筒底部中点摇动整组内容。
  void _shake(Canvas canvas) {
    final pivot = data.layout.pivot;
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(luckyDegToRad(data.frame.shakeDeg));
    canvas.translate(-pivot.dx, -pivot.dy);
  }

  /// 回放指定位置的静态层或调用动态层。
  void _layers(Canvas canvas, LuckyLayerPosition position) {
    for (var i = 0; i < data.layers.length; i++) {
      final layer = data.layers[i];
      if (layer.position != position) continue;
      canvas.save();
      final picture = _layerPictures[i];
      if (picture == null) {
        layer.paint(canvas, _context);
      } else {
        canvas.drawPicture(picture);
      }
      canvas.restore();
    }
  }

  /// 回放缓存段，不使用 saveLayer，也不在帧内创建 Paint 或 Rect。
  @override
  void paint(Canvas canvas, Size size) {
    luckyTraceStart('luckdraw.lots.paint');
    try {
      final l = data.layout, f = data.frame;
      data.hooks.beforeDraw?.call(canvas, size);
      _layers(canvas, LuckyLayerPosition.background);
      canvas.drawPicture(_background);
      canvas.save();
      _shake(canvas);
      canvas.drawPicture(_back);
      _layers(canvas, LuckyLayerPosition.belowItems);
      for (var slot = 0; slot < l.sticks.length; slot++) {
        final rect = l.sticks[slot];
        final target =
            slot == f.targetSlot && f.targetIndex >= 0 && f.riseProgress > 0;
        canvas.save();
        canvas.translate(l.pivot.dx, l.cylinder.top);
        canvas.rotate(l.angles[slot]);
        canvas.translate(-l.pivot.dx, -l.cylinder.top);
        if (target) {
          canvas.translate(0, -l.riseDistance * f.riseProgress);
          canvas.drawPicture(_named[f.targetIndex]);
        } else {
          canvas.translate(rect.left, rect.top);
          canvas.scale(rect.width, rect.height);
          canvas.drawPicture(_bare);
        }
        canvas.restore();
      }
      canvas.drawPicture(_front);
      canvas.restore();
      _layers(canvas, LuckyLayerPosition.aboveItems);
      if (f.targetIndex >= 0 && f.revealProgress > 0) {
        canvas.save();
        canvas.translate(_cardCenter.dx, _cardCenter.dy);
        canvas.scale(f.revealProgress);
        canvas.translate(-_cardCenter.dx, -_cardCenter.dy);
        canvas.drawPicture(_cards[f.targetIndex]);
        canvas.restore();
      }
      _layers(canvas, LuckyLayerPosition.foreground);
      data.hooks.afterDraw?.call(canvas, size);
    } finally {
      luckyTraceEnd();
    }
  }

  /// 低频输入变化时重绘。
  @override
  bool shouldRepaint(covariant LotsPainter oldDelegate) =>
      data != oldDelegate.data;
}
