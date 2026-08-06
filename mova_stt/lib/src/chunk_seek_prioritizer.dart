import 'dart:async';

import 'chunk_manifest.dart';
import 'chunk_scheduler.dart';

/// Returns the chunk indices that should be moved to the high-priority queue
/// when playback lands on [target] — the chunk covering [target] itself,
/// plus the next chunk so playback doesn't immediately outrun decoded
/// subtitles again.
///
/// Pure function, no timers involved — the debounce that decides *when* to
/// call this after a burst of scrub events lives in [ChunkSeekPrioritizer].
///
/// 播放落到 [target] 时该被挪到高优先级队列的分片序号——覆盖 [target] 本身
/// 的分片，加上下一片（防止播放马上又追上已解码字幕的进度）。
///
/// 纯函数，不涉及计时器——决定"一串拖动事件后什么时候才真正调用它"的防抖
/// 逻辑在 [ChunkSeekPrioritizer] 里。
///
/// Example / 示例:
/// ```dart
/// final manifest = ChunkManifest.build(totalDuration: const Duration(minutes: 20));
/// chunksToPrioritize(manifest, const Duration(minutes: 9)); // [2, 3]
/// ```
List<int> chunksToPrioritize(ChunkManifest manifest, Duration target) {
  if (manifest.chunks.isEmpty) return const [];
  final index = manifest.chunkIndexAt(target);
  final result = [index];
  if (index + 1 < manifest.chunks.length) result.add(index + 1);
  return result;
}

/// Debounces a burst of seek events (e.g. dragging the scrub bar) down to a
/// single [ChunkScheduler.enqueueHigh] call for the settled target position
/// — without this, every intermediate scrub position would enqueue its own
/// high-priority decode request and the priority queue would lose its
/// purpose.
///
/// 把一串拖动产生的连续 seek 事件（比如拖进度条）防抖成"落点稳定后只调一次"
/// [ChunkScheduler.enqueueHigh]——没有这层防抖，拖动过程中的每个中间位置都会
/// 各自触发一次高优先级解码请求，优先级队列就失去了意义。
///
/// Example / 示例:
/// ```dart
/// final prioritizer = ChunkSeekPrioritizer(manifest: manifest, scheduler: scheduler);
/// prioritizer.onSeek(const Duration(minutes: 3));  // 拖动中，尚未生效
/// prioritizer.onSeek(const Duration(minutes: 9));  // 手指仍在动，覆盖前一次
/// // 300ms 后手指停在 9 分钟处 → 只有 9 分钟对应的分片被 enqueueHigh
/// ```
class ChunkSeekPrioritizer {
  /// Creates a seek-driven prioritizer over [manifest]/[scheduler].
  ///
  /// 基于 [manifest]/[scheduler] 创建一个 seek 驱动的优先级调整器。
  ///
  /// - [manifest]: the chunk time-range plan / 分片时间区间计划
  /// - [scheduler]: receives the resulting [ChunkScheduler.enqueueHigh] calls
  ///   / 接收最终触发的 [ChunkScheduler.enqueueHigh] 调用
  /// - [settleDelay]: how long the target must stay unchanged before it's
  ///   actually prioritized / 落点保持不变多久后才真正生效
  ChunkSeekPrioritizer({
    required this.manifest,
    required this.scheduler,
    this.settleDelay = const Duration(milliseconds: 300),
  });

  /// The chunk time-range plan.
  ///
  /// 分片时间区间计划。
  final ChunkManifest manifest;

  /// Receives the resulting high-priority enqueue calls.
  ///
  /// 接收最终触发的高优先级入队调用。
  final ChunkScheduler scheduler;

  /// How long a seek target must stay unchanged before it's prioritized.
  ///
  /// seek 落点保持不变多久后才真正被优先处理。
  final Duration settleDelay;

  Timer? _debounce;

  /// Call on every seek/scrub event; only the last call within [settleDelay]
  /// actually results in a priority change.
  ///
  /// 每次 seek/拖动事件都调用；[settleDelay] 内只有最后一次调用真正生效。
  ///
  /// - [target]: the playback position being sought to / 正在跳转到的播放位置
  void onSeek(Duration target) {
    _debounce?.cancel();
    _debounce = Timer(settleDelay, () {
      // Reversed: enqueueHigh pushes to the front, so enqueueing in reverse
      // order leaves the first (most important) index at the very front.
      //
      // 倒序：enqueueHigh 是插到队首，倒序入队才能让第一个（最重要的）
      // 序号留在最前面。
      for (final index in chunksToPrioritize(manifest, target).reversed) {
        scheduler.enqueueHigh(index);
      }
    });
  }

  /// Cancels any pending debounced seek — call when the player/page is
  /// disposed to avoid a stray [Timer] firing after teardown.
  ///
  /// 取消任何待生效的防抖 seek——播放器/页面销毁时调用，避免销毁后
  /// [Timer] 还触发一次。
  void dispose() => _debounce?.cancel();
}
