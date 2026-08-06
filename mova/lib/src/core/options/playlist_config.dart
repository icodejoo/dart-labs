import '../model/playlist.dart';

/// Configuration for sequential playlist playback (episodes / tracks) plus the
/// "next up" card that appears near the end of an item.
///
/// Data-only by design: the running index and navigation live on
/// `MovaPlistCtrl` (host-constructed), keeping this bundle immutable and
/// comparable. Disabled and empty by default so enabling it is an explicit
/// host decision.
///
/// 顺序播放列表（剧集/曲目）与临近结束显示的"下一集"卡片的配置。
///
/// 刻意只做数据：运行时下标与导航在 `MovaPlistCtrl`（宿主构造）上，
/// 使本配置保持不可变、可比较。默认关闭且列表为空，是否启用由宿主显式决定。
class MovaPlistConfig {
  /// Master switch; the playlist controller/card do nothing when `false`.
  ///
  /// 总开关；为 `false` 时播放列表控制器/卡片均不动作。
  final bool enabled;

  /// The ordered list of items to play through.
  ///
  /// 要顺序播放的项列表。
  final List<MovaPlistItem> items;

  /// Index the controller starts on (clamped into range).
  ///
  /// 控制器起始下标（会钳入有效范围）。
  final int initialIndex;

  /// Whether reaching the end of an item auto-advances to the next one.
  ///
  /// 播完一项后是否自动前进到下一项。
  final bool autoPlayNext;

  /// How long before an item's end the "next up" card appears.
  ///
  /// "下一集"卡片在一项结束前多久出现。
  final Duration nextUpLeadTime;

  /// Creates a playlist configuration; disabled and empty by default.
  ///
  /// 创建播放列表配置；默认关闭且列表为空。
  ///
  /// - [enabled]: master switch / 总开关
  /// - [items]: ordered item list / 顺序项列表
  /// - [initialIndex]: starting index / 起始下标
  /// - [autoPlayNext]: auto-advance at end / 结束自动续播
  /// - [nextUpLeadTime]: card lead time before end / 卡片提前量
  const MovaPlistConfig({
    this.enabled = false,
    this.items = const <MovaPlistItem>[],
    this.initialIndex = 0,
    this.autoPlayNext = true,
    this.nextUpLeadTime = const Duration(seconds: 10),
  });

  /// Returns a copy with the given fields replaced; omitted fields keep their
  /// current value.
  ///
  /// 返回一份替换了指定字段的拷贝；未指定的字段保持当前值。
  MovaPlistConfig copyWith({
    bool? enabled,
    List<MovaPlistItem>? items,
    int? initialIndex,
    bool? autoPlayNext,
    Duration? nextUpLeadTime,
  }) {
    return MovaPlistConfig(
      enabled: enabled ?? this.enabled,
      items: items ?? this.items,
      initialIndex: initialIndex ?? this.initialIndex,
      autoPlayNext: autoPlayNext ?? this.autoPlayNext,
      nextUpLeadTime: nextUpLeadTime ?? this.nextUpLeadTime,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaPlistConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          identical(items, other.items) &&
          initialIndex == other.initialIndex &&
          autoPlayNext == other.autoPlayNext &&
          nextUpLeadTime == other.nextUpLeadTime;

  @override
  int get hashCode => Object.hash(
        enabled,
        items,
        initialIndex,
        autoPlayNext,
        nextUpLeadTime,
      );
}
