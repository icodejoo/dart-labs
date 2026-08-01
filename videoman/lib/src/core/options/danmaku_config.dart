import '../model/danmaku.dart';

/// Configuration for the bilibili-style scrolling-danmaku overlay.
///
/// Display-only by design (see doc/PRD.md ADR): no send box, no input, no
/// dedup/rate-limit engine — [items] is a fixed, host-supplied list rendered
/// as scrolling bullet comments timed to playback position. Sending/
/// moderation is the host's business.
///
/// bilibili 风格滚动弹幕的配置。
///
/// 刻意只做展示（见 doc/PRD.md ADR）：无发送框、无输入、无去重/限流引擎——
/// [items] 是宿主提供的固定列表，按播放位置触发滚动展示。发送/审核是宿主的
/// 业务。
class VmDanmakuConfig {
  /// Master switch; the track renders nothing at all when `false`.
  ///
  /// 总开关；为 `false` 时轨道完全不渲染。
  final bool enabled;

  /// The fixed list of comments to render, keyed by [VmDanmakuItem.time].
  ///
  /// 要渲染的固定弹幕列表，按 [VmDanmakuItem.time] 触发。
  final List<VmDanmakuItem> items;

  /// Number of horizontal tracks comments are distributed across, to reduce
  /// overlap. Assignment is round-robin, not full anti-collision.
  ///
  /// 弹幕分布的横向轨道数，用于减少重叠。分配方式是轮询，非完整防重叠算法。
  final int trackCount;

  /// Vertical pixel height reserved per track.
  ///
  /// 每条轨道预留的纵向像素高度。
  final double trackHeight;

  /// Font size for comment text.
  ///
  /// 弹幕文字字号。
  final double fontSize;

  /// Opacity applied to the whole track (0–1).
  ///
  /// 整个弹幕轨道的透明度（0–1）。
  final double opacity;

  /// How long a comment takes to cross the screen right-to-left.
  ///
  /// 一条弹幕从右到左划过屏幕所需的时长。
  final Duration crossDuration;

  /// Creates a danmaku configuration; disabled and empty by default so
  /// enabling it is an explicit host decision.
  ///
  /// 创建弹幕配置；默认关闭且列表为空，是否启用由宿主显式决定。
  ///
  /// - [enabled]: master switch / 总开关
  /// - [items]: fixed comment list / 固定弹幕列表
  /// - [trackCount]: horizontal track count / 横向轨道数
  /// - [trackHeight]: per-track height in px / 每条轨道高度（像素）
  /// - [fontSize]: comment font size / 弹幕字号
  /// - [opacity]: track opacity / 轨道透明度
  /// - [crossDuration]: screen-crossing duration / 划过屏幕耗时
  const VmDanmakuConfig({
    this.enabled = false,
    this.items = const <VmDanmakuItem>[],
    this.trackCount = 4,
    this.trackHeight = 28.0,
    this.fontSize = 14.0,
    this.opacity = 0.9,
    this.crossDuration = const Duration(seconds: 8),
  });

  /// Returns a copy with the given fields replaced; omitted fields keep
  /// their current value.
  ///
  /// 返回一份替换了指定字段的拷贝；未指定的字段保持当前值。
  VmDanmakuConfig copyWith({
    bool? enabled,
    List<VmDanmakuItem>? items,
    int? trackCount,
    double? trackHeight,
    double? fontSize,
    double? opacity,
    Duration? crossDuration,
  }) {
    return VmDanmakuConfig(
      enabled: enabled ?? this.enabled,
      items: items ?? this.items,
      trackCount: trackCount ?? this.trackCount,
      trackHeight: trackHeight ?? this.trackHeight,
      fontSize: fontSize ?? this.fontSize,
      opacity: opacity ?? this.opacity,
      crossDuration: crossDuration ?? this.crossDuration,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VmDanmakuConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          identical(items, other.items) &&
          trackCount == other.trackCount &&
          trackHeight == other.trackHeight &&
          fontSize == other.fontSize &&
          opacity == other.opacity &&
          crossDuration == other.crossDuration;

  @override
  int get hashCode => Object.hash(
        enabled,
        items,
        trackCount,
        trackHeight,
        fontSize,
        opacity,
        crossDuration,
      );
}
