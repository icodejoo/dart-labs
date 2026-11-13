import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/mini/placement.dart';
import '../../core/options/mini_opts.dart';
import '../player.dart';
import '../ui_kits/ui_kit.dart';
import 'mini.dart';
import 'mini_ui_kit.dart';

/// The draggable mini window itself, holding a `MovaPlayer` on the borrowed
/// api.
///
/// **Mount-agnostic by design**: it fills whatever box it is given and does
/// its own positioning inside, so the very same widget works as an
/// [OverlayEntry]'s child (in-page floating, via [MovaMini.showInPage])
/// and as a `Positioned.fill` child of a host-level [Stack] (persistent
/// floating, via `MovaMiniHost`). It must never assume which one it is in,
/// and must never be a [Positioned] itself.
///
/// Drag moves it (clamped every frame); release hands the rect to
/// [MovaMiniOpts.effectivePlacement] and animates to the result. Tapping
/// the picture invokes [MovaMini.onTapContent] (a no-op unless the host
/// sets it); tapping the close affordance always calls [MovaMini.close].
///
/// 可拖拽的小窗本体，内部用借来的 api 挂一个 `MovaPlayer`。
///
/// **设计上与挂载方式无关**：它撑满外部给它的盒子，在盒子内部自行定位，因此同
/// 一个 widget 既能当 [OverlayEntry] 的 child（页内悬浮，经
/// [MovaMini.showInPage]），也能当宿主级 [Stack] 的 `Positioned.fill` child
/// （持久悬浮，经 `MovaMiniHost`）。它绝不许假设自己在哪一种里，也绝不许自己就
/// 是 [Positioned]。
///
/// 拖动即移动（每帧钳制）；松手把矩形交给 [MovaMiniOpts.effectivePlacement]
/// 并动画到结果。点画面触发 [MovaMini.onTapContent]（宿主未设置时是空操作）；
/// 点关闭按钮总是调 [MovaMini.close]。
class MovaMiniWindow extends StatefulWidget {
  /// Creates the mini window.
  ///
  /// 创建小窗。
  const MovaMiniWindow({
    super.key,
    required this.mini,
    required this.api,
    required this.opts,
  });

  /// The route-independent holder this window reads/writes its rect through.
  ///
  /// 本窗口读写矩形所经的、独立于路由的持有者。
  final MovaMini mini;

  /// The borrowed player this window plays.
  ///
  /// 本窗口播放的、借来的播放器。
  final IMovaApi api;

  /// Sizing/placement/dismiss options.
  ///
  /// 尺寸/落点/关闭行为配置。
  final MovaMiniOpts opts;

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

  /// Recomputes geometry when the borrowed player or its sizing changes.
  ///
  /// 借用的播放器或尺寸配置变化时重新计算窗口几何。
  @override
  void didUpdateWidget(covariant MovaMiniWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.api, oldWidget.api) ||
        widget.opts.width != oldWidget.opts.width ||
        widget.opts.aspectRatio != oldWidget.opts.aspectRatio) {
      _rect = null;
      _lastBounds = null;
      _lastInsets = null;
      _dragging = false;
    }
  }

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

        final height = widget.opts.width / widget.opts.aspectRatio;
        var rect =
            _rect ??
            rectForCorner(
              widget.opts.initialCorner,
              width: widget.opts.width,
              height: height,
              bounds: bounds,
              insets: insets,
              margin: widget.opts.margin,
            );
        // Re-anchor only when the surrounding constraints/insets actually
        // changed since the last build (rotation, host resize) — not on
        // every rebuild, which would fight a placement policy that
        // deliberately returns a rect outside the default margin/snap rules.
        // Proportional remap first (keeps "near this corner" across a bounds
        // shape change like rotation), clamp second (safety net for validity)
        // — real-device verification (2026-09-24) found bare clamping alone
        // lets the window drift toward an edge across repeated rotations.
        //
        // 只在外部约束/内边距相较上次 build 确实变化时才重新锚定（转屏、宿主
        // resize）——而非每次 rebuild 都钳，否则会跟"故意返回默认边距/吸边
        // 规则之外矩形"的落点策略打架。先按比例重新映射（转屏这类 bounds
        // 形状变化后仍"贴在原来那个角落附近"），再钳制兜底合法性——真机验证
        // （2026-09-24）发现只钳制会导致连续转屏后小窗往一侧走位。
        if (_lastBounds != null &&
            (_lastBounds != bounds || _lastInsets != insets)) {
          rect = remapProportionally(
            rect,
            oldBounds: _lastBounds!,
            newBounds: bounds,
          );
          rect = clampToBounds(
            rect,
            bounds: bounds,
            insets: insets,
            margin: widget.opts.margin,
          );
        }
        _lastBounds = bounds;
        _lastInsets = insets;
        _rect = rect;

        final uiKit = _effectiveUiKit();

        return Stack(
          fit: StackFit.expand,
          children: [
            AnimatedPositioned(
              duration: _dragging
                  ? Duration.zero
                  : widget.opts.settleDuration,
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
                onTap: () => widget.mini.onTapContent?.call(widget.api),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Material(
                    elevation: 8,
                    child: MovaPlayer(
                      api: widget.api,
                      uiKit: uiKit,
                      autoLoadQualities: false,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Wires `MovaMini.close` into the UI kit's close button when the caller
  /// left [MovaMiniUiKit.onClose] unset — sparing callers from having to
  /// thread `mini.close` through every custom UI kit injection.
  ///
  /// 调用方未设置 [MovaMiniUiKit.onClose] 时，把 `MovaMini.close` 接进 UI 套件
  /// 的关闭按钮——省得调用方每次注入自定义 UI 套件都要手动串一遍 `mini.close`。
  IMovaUiKit _effectiveUiKit() {
    final uiKit = widget.mini.uiKit;
    if (uiKit is MovaMiniUiKit && uiKit.onClose == null) {
      return MovaMiniUiKit(onClose: widget.mini.close);
    }
    return uiKit;
  }

  void _onDrag(
    DragUpdateDetails details,
    MovaMiniRect bounds,
    MovaMiniInsets insets,
  ) {
    final current = _rect;
    if (current == null) return;
    final moved = current.shift(details.delta.dx, details.delta.dy);
    final clamped = clampToBounds(
      moved,
      bounds: bounds,
      insets: insets,
      margin: widget.opts.margin,
    );
    setState(() {
      _dragging = true;
      _rect = clamped;
    });
    widget.mini.setRect(clamped);
  }

  /// Closes an outward fling or settles within the effective bounds.
  ///
  /// 关闭向外甩动的小窗，或在有效边界内落位。
  void _onDragEnd(
    DragEndDetails details,
    MovaMiniRect bounds,
    MovaMiniInsets insets,
  ) {
    final current = _rect;
    if (current == null) return;
    final velocity = details.velocity.pixelsPerSecond;

    if (widget.opts.dismissible &&
        _isFlungOffscreen(current, bounds, insets, velocity)) {
      setState(() => _dragging = false);
      widget.mini.close();
      return;
    }

    final settled = widget.opts.effectivePlacement.settle(
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
    widget.mini.setRect(settled);
  }

  /// Detects an outward release at the same safe-area/margin drag boundary.
  ///
  /// 使用与拖动一致的安全区和边距边界识别向外甩动。
  bool _isFlungOffscreen(
    MovaMiniRect rect,
    MovaMiniRect bounds,
    MovaMiniInsets insets,
    Offset velocity,
  ) {
    const threshold = 1200.0;
    final margin = widget.opts.margin;
    final movingLeftOut =
        velocity.dx <= -threshold &&
        rect.left <= bounds.left + insets.left + margin;
    final movingRightOut =
        velocity.dx >= threshold &&
        rect.right >= bounds.right - insets.right - margin;
    final movingUpOut =
        velocity.dy <= -threshold &&
        rect.top <= bounds.top + insets.top + margin;
    final movingDownOut =
        velocity.dy >= threshold &&
        rect.bottom >= bounds.bottom - insets.bottom - margin;
    return movingLeftOut || movingRightOut || movingUpOut || movingDownOut;
  }
}
