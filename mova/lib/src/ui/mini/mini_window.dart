import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/mini/placement.dart';
import '../../core/options/mini_config.dart';
import '../player.dart';
import '../skins/skin.dart';
import 'mini_ctl.dart';
import 'mini_skin.dart';

/// The draggable mini window itself, holding a `MovaPlayer` on the borrowed
/// api.
///
/// **Mount-agnostic by design**: it fills whatever box it is given and does
/// its own positioning inside, so the very same widget works as an
/// [OverlayEntry]'s child (in-page floating, via [MovaMiniCtl.showInPage])
/// and as a `Positioned.fill` child of a host-level [Stack] (persistent
/// floating, via `MovaMiniHost`). It must never assume which one it is in,
/// and must never be a [Positioned] itself.
///
/// Drag moves it (clamped every frame); release hands the rect to
/// [MovaMiniConfig.effectivePlacement] and animates to the result. Tapping
/// the picture calls [MovaMiniCtl.hide]; tapping the close affordance calls
/// [MovaMiniCtl.close].
///
/// 可拖拽的小窗本体，内部用借来的 api 挂一个 `MovaPlayer`。
///
/// **设计上与挂载方式无关**：它撑满外部给它的盒子，在盒子内部自行定位，因此同
/// 一个 widget 既能当 [OverlayEntry] 的 child（页内悬浮，经
/// [MovaMiniCtl.showInPage]），也能当宿主级 [Stack] 的 `Positioned.fill` child
/// （持久悬浮，经 `MovaMiniHost`）。它绝不许假设自己在哪一种里，也绝不许自己就
/// 是 [Positioned]。
///
/// 拖动即移动（每帧钳制）；松手把矩形交给 [MovaMiniConfig.effectivePlacement]
/// 并动画到结果。点画面调 [MovaMiniCtl.hide]；点关闭按钮调 [MovaMiniCtl.close]。
class MovaMiniWindow extends StatefulWidget {
  /// Creates the mini window.
  ///
  /// 创建小窗。
  const MovaMiniWindow({super.key, required this.ctl, required this.api, required this.config});

  /// The route-independent holder this window reads/writes its rect through.
  ///
  /// 本窗口读写矩形所经的、独立于路由的持有者。
  final MovaMiniCtl ctl;

  /// The borrowed engine this window plays.
  ///
  /// 本窗口播放的、借来的引擎。
  final MovaApi api;

  /// Sizing/placement/dismiss configuration.
  ///
  /// 尺寸/落点/关闭行为配置。
  final MovaMiniConfig config;

  @override
  State<MovaMiniWindow> createState() => _MovaMiniWindowState();
}

class _MovaMiniWindowState extends State<MovaMiniWindow> {
  MovaMiniRect? _rect;
  MovaMiniRect? _lastBounds;
  MovaMiniInsets? _lastInsets;
  // While actively panning the window must jump instantly to the finger —
  // the settle animation is only for the post-release snap.
  //
  // 主动拖动期间小窗须瞬时跟手——落位动画只在松手后的吸边阶段生效。
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = MovaMiniRect(
          left: 0,
          top: 0,
          width: constraints.biggest.width,
          height: constraints.biggest.height,
        );
        final mq = MediaQuery.maybeOf(context);
        final insets = MovaMiniInsets(
          left: mq?.padding.left ?? 0,
          top: mq?.padding.top ?? 0,
          right: mq?.padding.right ?? 0,
          bottom: mq?.padding.bottom ?? 0,
        );

        final height = widget.config.width / widget.config.aspectRatio;
        var rect = _rect ??
            rectForCorner(
              widget.config.initialCorner,
              width: widget.config.width,
              height: height,
              bounds: bounds,
              insets: insets,
              margin: widget.config.margin,
            );
        // Re-clamp only when the surrounding constraints/insets actually
        // changed since the last build (rotation, host resize) — not on
        // every rebuild, which would fight a placement policy that
        // deliberately returns a rect outside the default margin/snap rules.
        //
        // 只在外部约束/内边距相较上次 build 确实变化时才重新钳制（转屏、宿主
        // resize）——而非每次 rebuild 都钳，否则会跟"故意返回默认边距/吸边
        // 规则之外矩形"的落点策略打架。
        if (_lastBounds != null && (_lastBounds != bounds || _lastInsets != insets)) {
          rect = clampToBounds(rect, bounds: bounds, insets: insets, margin: widget.config.margin);
        }
        _lastBounds = bounds;
        _lastInsets = insets;
        _rect = rect;

        final skin = _effectiveSkin();

        return Stack(
          fit: StackFit.expand,
          children: [
            AnimatedPositioned(
              duration: _dragging ? Duration.zero : widget.config.settleDuration,
              curve: Curves.easeOut,
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: GestureDetector(
                key: const ValueKey('movaMiniWindowGesture'),
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => setState(() => _dragging = true),
                onPanUpdate: (details) => _onDrag(details, bounds, insets),
                onPanEnd: (details) => _onDragEnd(details, bounds, insets),
                onTap: () => widget.ctl.hide(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Material(
                    elevation: 8,
                    child: MovaPlayer(api: widget.api, skin: skin, autoLoadQualities: false),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Wires `MovaMiniCtl.close` into the skin's close button when the caller
  /// left [MovaMiniSkin.onClose] unset — sparing callers from having to
  /// thread `ctl.close` through every custom skin injection.
  ///
  /// 调用方未设置 [MovaMiniSkin.onClose] 时，把 `MovaMiniCtl.close` 接进皮肤
  /// 的关闭按钮——省得调用方每次注入自定义皮肤都要手动串一遍 `ctl.close`。
  MovaSkin _effectiveSkin() {
    final skin = widget.ctl.skin;
    if (skin is MovaMiniSkin && skin.onClose == null) {
      return MovaMiniSkin(onClose: widget.ctl.close);
    }
    return skin;
  }

  void _onDrag(DragUpdateDetails details, MovaMiniRect bounds, MovaMiniInsets insets) {
    final current = _rect;
    if (current == null) return;
    final moved = current.shift(details.delta.dx, details.delta.dy);
    final clamped = clampToBounds(moved, bounds: bounds, insets: insets, margin: widget.config.margin);
    setState(() {
      _dragging = true;
      _rect = clamped;
    });
    widget.ctl.setRect(clamped);
  }

  void _onDragEnd(DragEndDetails details, MovaMiniRect bounds, MovaMiniInsets insets) {
    final current = _rect;
    if (current == null) return;
    final velocity = details.velocity.pixelsPerSecond;

    if (widget.config.dismissible && _isFlungOffscreen(current, bounds, velocity)) {
      setState(() => _dragging = false);
      widget.ctl.close();
      return;
    }

    final settled = widget.config.effectivePlacement.settle(
      current,
      bounds: bounds,
      insets: insets,
      velocityX: velocity.dx,
      velocityY: velocity.dy,
    );
    setState(() {
      _dragging = false;
      _rect = settled;
    });
    widget.ctl.setRect(settled);
  }

  /// Whether the release velocity is fast enough, and points far enough
  /// outside [bounds], to count as "flung away".
  ///
  /// 松手速度是否足够快、且指向 [bounds] 之外足够远，构成"甩出关闭"。
  bool _isFlungOffscreen(MovaMiniRect rect, MovaMiniRect bounds, Offset velocity) {
    const threshold = 1200.0;
    if (velocity.distance < threshold) return false;
    final movingLeftOut = velocity.dx < 0 && rect.left <= bounds.left;
    final movingRightOut = velocity.dx > 0 && rect.right >= bounds.right;
    final movingUpOut = velocity.dy < 0 && rect.top <= bounds.top;
    final movingDownOut = velocity.dy > 0 && rect.bottom >= bounds.bottom;
    return movingLeftOut || movingRightOut || movingUpOut || movingDownOut;
  }
}
