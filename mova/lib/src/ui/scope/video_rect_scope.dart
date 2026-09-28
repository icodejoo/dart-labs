import 'package:flutter/widgets.dart';

/// Publishes the video content's actual display rect (letterboxing already
/// applied, relative to the player container) down the widget tree, so
/// overlay components can align themselves to the picture rather than to the
/// whole player box.
///
/// Follows the same lookup shape as [MovaScope]/[MovaSelect] (see
/// `scope/scope.dart`, `scope/selector.dart`) but is intentionally its own
/// lightweight [InheritedWidget] rather than folded into [MovaScope]: the
/// rect is derived from layout constraints (via `LayoutBuilder` in
/// `player.dart`), not from `MovaApi`'s streams.
///
/// 向后代发布视频内容的实际显示矩形（已应用 letterbox 计算，相对播放器容器），
/// 使叠加层组件能对齐画面本身，而非整个播放器容器。
///
/// 查找方式与 [MovaScope]/[MovaSelect]（见 `scope/scope.dart`、
/// `scope/selector.dart`）保持一致，但刻意做成独立的轻量 [InheritedWidget]而非
/// 并入 [MovaScope]——该矩形由布局约束推导而来（`player.dart` 里的
/// `LayoutBuilder`），并非来自 `MovaApi` 的流。
class MovaVideoRectScope extends InheritedWidget {
  /// Wraps [child] with a scope that exposes [rect] to descendants.
  ///
  /// 用一个向后代暴露 [rect] 的作用域包裹 [child]。
  const MovaVideoRectScope({required this.rect, required super.child, super.key});

  /// The video content's rect, relative to the player container's origin.
  ///
  /// 视频内容矩形，坐标相对播放器容器的原点。
  final Rect rect;

  /// Looks up the nearest enclosing [MovaVideoRectScope]'s rect, or
  /// [fallback] when none is found (e.g. outside a [MovaPlayer]).
  ///
  /// 查找最近的 [MovaVideoRectScope] 的矩形；找不到时（例如在 [MovaPlayer] 之外）
  /// 返回 [fallback]。
  ///
  /// - [context]: build context to search from / 用于向上查找的构建上下文
  /// - [fallback]: rect returned when no scope is found / 找不到作用域时的兜底矩形
  static Rect of(BuildContext context, {required Rect fallback}) {
    final scope = context.dependOnInheritedWidgetOfExactType<MovaVideoRectScope>();
    return scope?.rect ?? fallback;
  }

  @override
  bool updateShouldNotify(MovaVideoRectScope oldWidget) => rect != oldWidget.rect;
}
