import 'dart:collection';

/// Two-priority-queue scheduler for [SttChunk] decoding order — high
/// priority for the first chunk and whatever chunk playback just jumped to
/// (seek/fast-forward/fast-rewind), low priority for the rest, filled in
/// sequentially in the background.
///
/// Pure Dart, no audio/engine dependency — a worker pool pulls indices via
/// [nextTask] and is responsible for actually extracting/decoding them.
///
/// [SttChunk] 解码顺序的双优先级队列调度器——首个分片和播放刚跳转到的分片
/// （快进/快退/拖动）走高优先级，其余分片走低优先级，后台按顺序背景填充。
///
/// 纯 Dart，不依赖音频/引擎——worker 池通过 [nextTask] 取序号，自己负责
/// 真正的抽取/解码。
///
/// Example / 示例:
/// ```dart
/// final scheduler = ChunkScheduler()..seedLowPriority(List.generate(10, (i) => i));
/// scheduler.enqueueHigh(0);        // 首段
/// scheduler.nextTask(); // 0
/// scheduler.enqueueHigh(7);        // 用户快进跳到了第 7 段
/// scheduler.nextTask(); // 7 —— 插队到最前面
/// scheduler.nextTask(); // 1 —— 高优先级队列空了，回落到低优先级顺序
/// ```
class ChunkScheduler {
  final Queue<int> _high = Queue<int>();
  final Queue<int> _low = Queue<int>();

  /// Seeds the low-priority queue with [allIndices], in the given order —
  /// call once when a manifest is first built.
  ///
  /// 用 [allIndices] 填充低优先级队列，按给定顺序——清单首次构建时调用一次。
  void seedLowPriority(Iterable<int> allIndices) {
    _low.addAll(allIndices);
  }

  /// Moves [chunkIndex] to the front of the high-priority queue, removing it
  /// from the low-priority queue first if present there — a chunk is never
  /// duplicated across both queues.
  ///
  /// 把 [chunkIndex] 移到高优先级队列最前面——如果它已经在低优先级队列里，
  /// 先移除再插入，保证一个分片不会同时出现在两条队列里。
  ///
  /// - [chunkIndex]: index of the chunk to prioritize / 要优先处理的分片序号
  void enqueueHigh(int chunkIndex) {
    _low.remove(chunkIndex);
    _high.remove(chunkIndex);
    _high.addFirst(chunkIndex);
  }

  /// Returns the next chunk index a worker should process — high-priority
  /// queue drains first, low-priority queue only once high is empty. Returns
  /// null when both queues are empty (nothing left to do right now).
  ///
  /// 返回下一个 worker 该处理的分片序号——高优先级队列先出，空了才轮到低
  /// 优先级队列。两条队列都空时返回 null（当前没有待办任务）。
  int? nextTask() {
    if (_high.isNotEmpty) return _high.removeFirst();
    if (_low.isNotEmpty) return _low.removeFirst();
    return null;
  }

  /// Whether either queue still has pending work.
  ///
  /// 是否还有任一队列存在待办任务。
  bool get hasPendingWork => _high.isNotEmpty || _low.isNotEmpty;
}
