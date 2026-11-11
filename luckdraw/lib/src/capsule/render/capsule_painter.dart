import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/foundation/angles.dart';
import '../../core/foundation/fill.dart';
import '../../core/foundation/image.dart';
import '../../core/geometry/image_box.dart';
import '../../core/motion/phase.dart';
import '../../core/render/cached_picture.dart';
import '../../core/render/layer.dart';
import '../../core/render/paint_helpers.dart';
import '../../core/render/perf_trace.dart';
import '../../core/render/picture_cache.dart';
import '../../core/render/renderer.dart';
import '../../core/render/stir_arms.dart';
import '../layout/capsule_layout.dart';
import '../model/capsule_config.dart';
import '../motion/capsule_motion.dart';

/// 胶囊配色 Picture 段基址，来自 T5.4。
const int _capsuleBase = 3000;

/// 奖品卡段基址，与胶囊段分离。
const int _cardBase = 1000000;

/// 球体背面默认填充。
const LuckyFill _globeFill = LuckyFill.color(Color(0x223BA5C7));

/// 机身默认填充。
const LuckyFill _bodyFill = LuckyFill.color(Color(0xFFE95567));

/// 旋钮默认填充。
const LuckyFill _knobFill = LuckyFill.color(Color(0xFFF9F5E9));

/// 高光与旋钮标记颜色。
const Color _highlight = Color(0x99FFFFFF);

/// 托盘与滑道颜色。
const Color _trayColor = Color(0xFF35485A);

/// 统一二分系数。
const double _half = 0.5;

/// 胶囊描边宽度。
const double _seamWidth = 1;

/// 静态背面段。
const int _back = 0;

/// 静态前面段。
const int _front = 1;

/// 旋钮段。
const int _knob = 2;

/// 静态层段基址。
const int _layerBase = 2000000;

/// 预录制扭蛋机显示列表；帧绘制仅回放，缓存所有权归表面。
final class CapsulePictures {
  /// 创建缓存，调用 prepare 后才可绘制。
  CapsulePictures();

  /// 原生显示列表缓存。
  final LuckyPictureCache cache = LuckyPictureCache();

  /// 每种奖品的胶囊显示列表，相同配色复用同一对象。
  final List<ui.Picture> capsules = [];

  /// 每种配色的运动位图与停下后的矢量回放。
  final List<LuckyCachedPicture> capsulePlayback = [];

  /// 每种奖品的卡片显示列表。
  final List<ui.Picture> cards = [];

  /// 已录制的背面。
  late ui.Picture back;

  /// 已录制的前面高光。
  late ui.Picture front;

  /// 已录制的旋钮。
  late ui.Picture knob;

  /// 物理模式的拨杆绘制器；未开启物理模式或没有拨杆时为空。
  LuckyStirArms? stirArms;

  /// 各静态层显示列表。
  final Map<int, ui.Picture> layers = {};

  /// 录制当前布局与图片版本的所有静态段。
  void prepare(
      LuckySurfaceData<CapsuleConfig, CapsuleLayout, CapsuleFrame> data,
      {bool imagesOnly = false}) {
    luckyTraceStart('luckdraw.capsule.record');
    try {
      if (imagesOnly) {
        for (var i = 0; i < data.config.prizes.length; i++) {
          if (data.config.prizes[i].images.isNotEmpty) {
            cache.invalidate(_cardBase + i);
          }
        }
      } else {
        cache.invalidateAll();
      }
      capsules.clear();
      capsulePlayback.clear();
      cards.clear();
      layers.clear();
      final l = data.layout, c = data.config;
      final physics = c.options.physics;
      stirArms = physics != null && physics.stirArms > 0
          ? LuckyStirArms(
              containerRadius: l.globeRadius, bodyRadius: l.capsuleRadius)
          : null;
      back = cache.picture(_back, (canvas) {
        paintLuckyFill(
            canvas,
            Path()
              ..addOval(Rect.fromCircle(
                  center: l.globeCenter, radius: l.globeRadius)),
            c.style.globeFill ?? _globeFill,
            Rect.fromCircle(center: l.globeCenter, radius: l.globeRadius));
        paintLuckyFill(
            canvas,
            Path()
              ..addRRect(RRect.fromRectAndRadius(
                  l.body, Radius.circular(l.knobRadius))),
            c.style.bodyFill ?? _bodyFill,
            l.body);
        canvas.drawRRect(
            RRect.fromRectAndRadius(l.tray.deflate(l.capsuleRadius * _half),
                Radius.circular(l.capsuleRadius)),
            Paint()..color = _trayColor);
        canvas.drawPath(
            Path()
              ..moveTo(l.dropPath[0].dx, l.dropPath[0].dy)
              ..lineTo(l.dropPath[1].dx, l.dropPath[1].dy)
              ..lineTo(l.dropPath[2].dx, l.dropPath[2].dy)
              ..lineTo(l.dropPath[3].dx, l.dropPath[3].dy),
            Paint()
              ..color = _trayColor
              ..strokeWidth = l.capsuleRadius
              ..style = PaintingStyle.stroke);
      });
      front = cache.picture(_front, (canvas) {
        canvas.drawArc(
            Rect.fromCircle(center: l.globeCenter, radius: l.globeRadius),
            math.pi,
            math.pi * _half,
            false,
            Paint()
              ..color = _highlight
              ..style = PaintingStyle.stroke
              ..strokeWidth = l.capsuleRadius * _half);
      });
      knob = cache.picture(_knob, (canvas) {
        final bounds =
            Rect.fromCircle(center: Offset.zero, radius: l.knobRadius);
        paintLuckyFill(canvas, Path()..addOval(bounds),
            c.style.knobFill ?? _knobFill, bounds);
        canvas.drawLine(
            Offset(-l.knobRadius * _half, 0),
            Offset(l.knobRadius * _half, 0),
            Paint()
              ..color = _trayColor
              ..strokeWidth = l.capsuleRadius * _half);
      });
      final colors = <(LuckyFill, LuckyFill), LuckyCachedPicture>{};
      for (var i = 0; i < c.prizes.length; i++) {
        final prize = c.prizes[i],
            key = (c.prizes[i].topFill, c.prizes[i].bottomFill);
        final picture = colors.putIfAbsent(
            key,
            () => LuckyCachedPicture(
                    cache,
                    _capsuleBase + i,
                    Rect.fromCircle(
                        center: Offset.zero,
                        radius: l.capsuleRadius + _seamWidth),
                    data.devicePixelRatio, (canvas) {
                  final bounds = Rect.fromCircle(
                      center: Offset.zero, radius: l.capsuleRadius);
                  final top = Path()
                    ..moveTo(-l.capsuleRadius, 0)
                    ..arcTo(bounds, math.pi, math.pi, false)
                    ..close();
                  final bottom = Path()
                    ..moveTo(l.capsuleRadius, 0)
                    ..arcTo(bounds, 0, math.pi, false)
                    ..close();
                  paintLuckyFill(canvas, top, prize.topFill, bounds);
                  paintLuckyFill(canvas, bottom, prize.bottomFill, bounds);
                  canvas.drawCircle(
                      Offset.zero,
                      l.capsuleRadius,
                      Paint()
                        ..color = c.style.seamColor
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = _seamWidth);
                  canvas.drawLine(
                      Offset(-l.capsuleRadius, 0),
                      Offset(l.capsuleRadius, 0),
                      Paint()
                        ..color = c.style.seamColor
                        ..strokeWidth = _seamWidth);
                }, data.performance));
        capsules.add(picture.picture);
        capsulePlayback.add(picture);
        cards.add(cache.picture(_cardBase + i, (canvas) {
          final style = c.style.card,
              path = Path()
                ..addRRect(RRect.fromRectAndRadius(
                    l.card, Radius.circular(c.style.card.borderRadius ?? 0)));
          if (style.background != null) {
            paintLuckyFill(canvas, path, style.background!, l.card,
                shadow: style.shadow, dpr: data.devicePixelRatio);
          }
          for (var j = 0; j < prize.images.length; j++) {
            final image = prize.images[j],
                resolved = data.images[LuckyImageSlot('prizes', i, j)];
            if (resolved != null) {
              final rect = LuckyImagePlacement(
                      slot: LuckyImageSlot('prizes', i, j),
                      image: image,
                      box: l.card,
                      maxWidth: l.card.width,
                      maxHeight: l.card.height,
                      leftBase: l.card.width,
                      topBase: l.card.height)
                  .place(resolved.naturalSize);
              drawLuckyImage(canvas, resolved.image, rect,
                  borderRadius: image.borderRadius, opacity: image.opacity);
            }
          }
          paintLuckyTextLines(canvas, l.cardTexts[i], null,
              textDirection: data.textDirection, textScale: data.textScale);
          prize.painter?.call(canvas, l.card);
          if (style.foreground != null) {
            paintLuckyFill(canvas, path, style.foreground!, l.card);
          }
          if (style.border != null) {
            strokeLuckyBorder(
                canvas, l.card, style.borderRadius ?? 0, style.border!);
          }
        }));
      }
      final context = LuckyLayerContext<CapsuleLayout, CapsuleFrame>()
        ..size = l.size
        ..layout = l
        ..frame = data.frame
        ..devicePixelRatio = data.devicePixelRatio;
      for (var i = 0; i < data.layers.length; i++) {
        final layer = data.layers[i];
        if (layer.isStatic) {
          layers[i] = cache.picture(
              _layerBase + i, (canvas) => layer.paint(canvas, context));
        }
      }
    } finally {
      luckyTraceEnd();
    }
  }

  /// 释放所有显示列表，可重复调用。
  void dispose() => cache.dispose();
}

/// 只回放缓存的帧画笔；不创建 Paint、Rect、TextPainter 或离屏图层。
final class CapsulePainter extends CustomPainter {
  /// 使用持久缓存与复用帧绘制。
  CapsulePainter(this.data, this.pictures)
      : super(
            repaint: Listenable.merge(
                [data.frameListenable, data.imagesListenable]));

  /// 当前表面输入。
  final LuckySurfaceData<CapsuleConfig, CapsuleLayout, CapsuleFrame> data;

  /// 表面持有的显示列表。
  final CapsulePictures pictures;

  /// 用户层复用上下文。
  final LuckyLayerContext<CapsuleLayout, CapsuleFrame> _context =
      LuckyLayerContext();

  /// 绘制指定位置的层。
  void _layers(Canvas canvas, LuckyLayerPosition position) {
    for (var i = 0; i < data.layers.length; i++) {
      final layer = data.layers[i];
      if (layer.position != position) continue;
      if (layer.isStatic) {
        canvas.drawPicture(pictures.layers[i]!);
      } else {
        layer.paint(canvas, _context);
      }
    }
  }

  /// 平移并旋转回放胶囊。
  void _capsule(Canvas canvas, int index, int prize) {
    final f = data.frame, l = data.layout;
    canvas.save();
    canvas.translate(
        l.globeCenter.dx + f.x[index], l.globeCenter.dy + f.y[index]);
    canvas.rotate(f.angle[index]);
    pictures.capsulePlayback[prize].paint(canvas, isMoving: f.phase.isMoving);
    canvas.restore();
  }

  /// 按约定段顺序回放；掉落胶囊使用目标奖品配色。
  @override
  void paint(Canvas canvas, Size size) {
    luckyTraceStart('luckdraw.capsule.paint');
    try {
      final l = data.layout, f = data.frame;
      if (l.isEmpty) return;
      _context
        ..size = size
        ..layout = l
        ..frame = f
        ..devicePixelRatio = data.devicePixelRatio;
      data.hooks.beforeDraw?.call(canvas, size);
      _layers(canvas, LuckyLayerPosition.background);
      canvas.drawPicture(pictures.back);
      _layers(canvas, LuckyLayerPosition.belowItems);
      final dropped = f.stage == CapsuleStage.dropping ||
          f.stage == CapsuleStage.revealing ||
          f.stage == CapsuleStage.done;
      final arms = pictures.stirArms;
      if (arms != null && f.physical) {
        arms.paint(canvas, l.globeCenter, f.stirDeg,
            data.config.options.physics!.stirArms, f.mix);
      }
      for (var i = 0; i < l.capsules.length; i++) {
        if ((!dropped || i != f.droppedCapsule) && i != f.guided) {
          _capsule(canvas, i, l.capsules[i]);
        }
      }
      if (f.guided >= 0 && !dropped) {
        _capsule(canvas, f.guided, l.capsules[f.guided]);
      }
      canvas.drawPicture(pictures.front);
      canvas.save();
      canvas.translate(l.knobCenter.dx, l.knobCenter.dy);
      canvas.rotate(luckyDegToRad(f.knobDeg));
      canvas.drawPicture(pictures.knob);
      canvas.restore();
      if (dropped && f.droppedCapsule >= 0) {
        _capsule(canvas, f.droppedCapsule, f.targetPrize);
      }
      if (f.revealProgress > 0 && f.targetPrize >= 0) {
        canvas.save();
        canvas.translate(l.cardCenter.dx, l.cardCenter.dy);
        canvas.scale(f.revealProgress);
        canvas.translate(-l.cardCenter.dx, -l.cardCenter.dy);
        canvas.drawPicture(pictures.cards[f.targetPrize]);
        canvas.restore();
      }
      _layers(canvas, LuckyLayerPosition.aboveItems);
      _layers(canvas, LuckyLayerPosition.foreground);
      data.hooks.afterDraw?.call(canvas, size);
    } finally {
      luckyTraceEnd();
    }
  }

  /// 布局、图片和输入变更由宿主低频重建，帧通过 Listenable 驱动。
  @override
  bool shouldRepaint(CapsulePainter oldDelegate) => data != oldDelegate.data;
}
