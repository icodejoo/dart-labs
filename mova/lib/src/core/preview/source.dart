import '../model/source.dart';
import 'models.dart';

/// One strategy for obtaining a preview thumbnail at a given position.
///
/// The preview service walks an ordered list of sources and takes the first
/// non-null answer, so a source signals "I cannot serve this media" simply by
/// returning null. Sources must never throw: a broken thumbnail track degrades
/// the bubble, never playback.
///
/// 在给定位置取得预览缩略图的一种策略。
///
/// 预览服务按顺序遍历来源列表，取第一个非 null 的结果；因此来源只要返回 null
/// 即表示"我无法服务该媒体"。来源不得抛异常：坏掉的缩略图轨只能让气泡降级，
/// 绝不能影响播放。
abstract class MovaThumbSource {
  /// Stable identifier used in diagnostics and tests, e.g. `vtt`.
  ///
  /// 用于诊断与测试的稳定标识，例如 `vtt`。
  String get name;

  /// Produces the thumbnail covering [bucket] of [source].
  ///
  /// 产出 [source] 中覆盖 [bucket] 的缩略图。
  ///
  /// - [source]: the media being previewed / 正在预览的媒体
  /// - [bucket]: bucket-aligned position / 桶对齐位置
  ///
  /// Returns the thumbnail, or null when this source cannot serve it.
  ///
  /// 返回缩略图；本来源无法服务时返回 null。
  Future<MovaThumb?> thumbAt(MovaSource source, Duration bucket);

  /// Drops per-media state so the next [thumbAt] starts fresh; called when the
  /// player opens a different source.
  ///
  /// 丢弃与当前媒体相关的状态，让下次 [thumbAt] 从头开始；播放器打开新源时调用。
  Future<void> reset();

  /// Releases all resources held by this source.
  ///
  /// 释放该来源持有的全部资源。
  Future<void> dispose();
}
