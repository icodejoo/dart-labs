/// A single scrolling bullet-comment ("danmaku") entry.
///
/// Purely a data value — [DanmakuTrackComponent] (in `ui/components/`) is the
/// only thing that interprets [time]/[text]/[color]; core never renders.
///
/// 单条滚动弹幕。
///
/// 纯数据值——只有 `ui/components/` 里的 `DanmakuTrackComponent` 解释
/// [time]/[text]/[color]；core 层从不渲染。
class MovaDanmakuItem {
  /// The comment text.
  ///
  /// 弹幕文案。
  final String text;

  /// Playback position this comment fires at.
  ///
  /// 该弹幕触发时对应的播放位置。
  final Duration time;

  /// ARGB color override; `null` uses the track's default text color.
  ///
  /// ARGB 颜色覆盖；`null` 时使用轨道默认文字颜色。
  final int? color;

  /// Creates a danmaku entry.
  ///
  /// 创建一条弹幕。
  ///
  /// - [text]: comment text / 弹幕文案
  /// - [time]: fire position / 触发位置
  /// - [color]: optional ARGB color override / 可选 ARGB 颜色覆盖
  const MovaDanmakuItem({required this.text, required this.time, this.color});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaDanmakuItem &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          time == other.time &&
          color == other.color;

  @override
  int get hashCode => Object.hash(text, time, color);
}
