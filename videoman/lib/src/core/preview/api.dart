import 'models.dart';

/// The scrub-preview capability surface exposed on `VmApi.preview`.
///
/// UI components only ever call [requestAt]/[peekAt] and listen to [thumbs];
/// all policy (debounce, bucketing, network, caching, source order) lives
/// behind this abstraction in the core layer.
///
/// 挂在 `VmApi.preview` 上的拖动预览能力面。
///
/// UI 组件只会调用 [requestAt]/[peekAt] 并监听 [thumbs]；所有策略（防抖、
/// 桶对齐、网络、缓存、来源顺序）都藏在该抽象之后的 core 层里。
abstract class VmPreviewApi {
  /// Emits the thumbnail to display, or null when nothing should be shown.
  ///
  /// 推送应展示的缩略图；无内容可展示时推送 null。
  Stream<VmThumb?> get thumbs;

  /// The thumbnail currently resolved for the active scrub position, if any.
  ///
  /// 当前拖动位置已解析出的缩略图（若有）。
  VmThumb? get current;

  /// Returns the already-resident thumbnail covering [position] without any
  /// I/O, so a bucket that is already cached renders in the same frame.
  ///
  /// 不做任何 I/O，返回已驻留的、覆盖 [position] 的缩略图，使已缓存的桶能在
  /// 同一帧渲染出来。
  ///
  /// - [position]: the scrub position / 拖动位置
  ///
  /// Returns the resident thumbnail, or null when not cached.
  ///
  /// 返回已驻留的缩略图；未缓存时返回 null。
  VmThumb? peekAt(Duration position);

  /// Requests the thumbnail covering [position]; debounced and bucket-aligned.
  ///
  /// 请求覆盖 [position] 的缩略图；带防抖并按桶对齐。
  ///
  /// - [position]: the scrub position / 拖动位置
  void requestAt(Duration position);

  /// Drops the pending request and hides the current thumbnail; called when
  /// the drag ends.
  ///
  /// 丢弃待处理的请求并隐藏当前缩略图；拖动结束时调用。
  void cancel();

  /// Empties the thumbnail cache.
  ///
  /// 清空缩略图缓存。
  Future<void> clear();
}
