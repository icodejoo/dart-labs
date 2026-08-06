import 'source.dart';

/// One entry in a sequential playlist — a single episode or track — wrapping a
/// playable [source] with optional display metadata for the "next up" card.
///
/// 顺序播放列表中的一项——单集/单条——包裹可播放的 [source]，并附带供"下一集"
/// 卡片展示的可选元数据。
class MovaPlistItem {
  /// The playable source for this entry.
  ///
  /// 该项对应的可播放源。
  final MovaSource source;

  /// Card title; falls back to [MovaSource.title] when omitted.
  ///
  /// 卡片标题；省略时回退到 [MovaSource.title]。
  final String? title;

  /// Secondary line under the title (e.g. "第 3 集").
  ///
  /// 标题下的副标题（例如"第 3 集"）。
  final String? subtitle;

  /// Poster/thumbnail URL shown on the next-up card.
  ///
  /// "下一集"卡片上的封面/缩略图地址。
  final String? poster;

  /// Creates a playlist item.
  ///
  /// 创建一个播放列表项。
  ///
  /// - [source]: the playable source / 可播放源
  /// - [title]: card title, overrides the source title / 卡片标题，覆盖源标题
  /// - [subtitle]: secondary line / 副标题
  /// - [poster]: poster/thumbnail URL / 封面地址
  ///
  /// Example / 示例:
  /// ```dart
  /// const MovaPlistItem(
  ///   source: MovaSource('https://host/ep3.m3u8'),
  ///   title: '第三集',
  /// );
  /// ```
  const MovaPlistItem({
    required this.source,
    this.title,
    this.subtitle,
    this.poster,
  });

  /// The best display title: explicit [title] or the source's own title.
  ///
  /// 最合适的展示标题：显式 [title] 或源自带的标题。
  String? get displayTitle => title ?? source.title;
}
