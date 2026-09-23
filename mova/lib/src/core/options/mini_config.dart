import '../mini/placement.dart';

/// Which corner the mini window snaps to when first shown.
///
/// 小窗首次出现时吸附到哪个角。
enum MovaMiniCorner {
  /// Top-left / 左上
  topLeft,

  /// Top-right / 右上
  topRight,

  /// Bottom-left / 左下
  bottomLeft,

  /// Bottom-right / 右下（默认，最不挡内容）
  bottomRight,
}

/// Configuration for the in-app mini window (app-inline picture-in-picture).
///
/// Off by default. This feature never touches a platform PiP API — it is pure
/// Flutter compositing above the [Navigator], so it behaves identically on
/// every platform and needs no permission.
///
/// App 内小窗（应用内画中画）的配置。
///
/// 默认关闭。该特性完全不碰任何平台 PiP API——它只是在 [Navigator] 之上做纯
/// Flutter 合成，因此四端行为一致，也不需要任何权限。
class MovaMiniConfig {
  /// Master switch; [MovaMiniHost] renders nothing when `false`.
  ///
  /// 总开关；为 `false` 时 [MovaMiniHost] 不渲染任何东西。
  final bool enabled;

  /// The mini window's width in logical pixels; height follows [aspectRatio].
  ///
  /// 小窗宽度（逻辑像素）；高度由 [aspectRatio] 推出。
  final double width;

  /// Width / height of the mini window.
  ///
  /// 小窗的宽高比。
  final double aspectRatio;

  /// Inset kept between the window and every screen edge / safe-area edge.
  ///
  /// 小窗与屏幕边缘/安全区之间保留的间距。
  final double margin;

  /// Whether a drag release snaps the window to the nearest horizontal edge.
  ///
  /// 拖动松手后是否吸附到最近的水平边缘。
  final bool snapToEdge;

  /// Where the window first appears.
  ///
  /// 小窗首次出现的位置。
  final MovaMiniCorner initialCorner;

  /// Whether flinging the window off-screen dismisses it (and stops playback).
  ///
  /// 是否允许把小窗甩出屏幕以关闭它（并停止播放）。
  final bool dismissible;

  /// Snap/clamp animation duration; [Duration.zero] disables the animation.
  ///
  /// 吸边/钳制动画时长；[Duration.zero] 表示不做动画。
  final Duration settleDuration;

  /// Decides *where the window lands*; `null` uses [MovaCornerSnap] seeded
  /// from [snapToEdge]/[margin].
  ///
  /// 决定*小窗最终落点*；为 `null` 时使用由 [snapToEdge]/[margin] 构造的
  /// [MovaCornerSnap]。
  final MovaMiniPlacement? placement;

  /// Creates a mini-window configuration; disabled by default.
  ///
  /// 创建一份小窗配置；默认关闭。
  ///
  /// - [enabled]: master switch / 总开关
  /// - [width]: window width in logical px / 小窗宽度
  /// - [aspectRatio]: width over height / 宽高比
  /// - [margin]: edge inset / 边距
  /// - [snapToEdge]: snap on release / 松手吸边
  /// - [initialCorner]: first-show corner / 首次出现的角
  /// - [dismissible]: fling-away to close / 甩出关闭
  /// - [settleDuration]: settle animation / 落位动画时长
  /// - [placement]: injectable landing policy / 可注入的落点策略
  ///
  /// Example / 示例:
  /// ```dart
  /// const opts = MovaOpts(mini: MovaMiniConfig(enabled: true, width: 180));
  /// ```
  const MovaMiniConfig({
    this.enabled = false,
    this.width = 180,
    this.aspectRatio = 16 / 9,
    this.margin = 12,
    this.snapToEdge = true,
    this.initialCorner = MovaMiniCorner.bottomRight,
    this.dismissible = true,
    this.settleDuration = const Duration(milliseconds: 220),
    this.placement,
  })  : assert(width > 0, 'width must be positive'),
        assert(aspectRatio > 0, 'aspectRatio must be positive'),
        assert(margin >= 0, 'margin must not be negative');

  /// The placement policy actually in effect.
  ///
  /// 实际生效的落点策略。
  MovaMiniPlacement get effectivePlacement =>
      placement ?? MovaCornerSnap(snap: snapToEdge, margin: margin);

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回一份替换了指定字段的拷贝。
  MovaMiniConfig copyWith({
    bool? enabled,
    double? width,
    double? aspectRatio,
    double? margin,
    bool? snapToEdge,
    MovaMiniCorner? initialCorner,
    bool? dismissible,
    Duration? settleDuration,
    MovaMiniPlacement? placement,
  }) {
    return MovaMiniConfig(
      enabled: enabled ?? this.enabled,
      width: width ?? this.width,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      margin: margin ?? this.margin,
      snapToEdge: snapToEdge ?? this.snapToEdge,
      initialCorner: initialCorner ?? this.initialCorner,
      dismissible: dismissible ?? this.dismissible,
      settleDuration: settleDuration ?? this.settleDuration,
      placement: placement ?? this.placement,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaMiniConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          width == other.width &&
          aspectRatio == other.aspectRatio &&
          margin == other.margin &&
          snapToEdge == other.snapToEdge &&
          initialCorner == other.initialCorner &&
          dismissible == other.dismissible &&
          settleDuration == other.settleDuration &&
          placement == other.placement;

  @override
  int get hashCode => Object.hash(
      enabled, width, aspectRatio, margin, snapToEdge, initialCorner, dismissible, settleDuration, placement);
}
