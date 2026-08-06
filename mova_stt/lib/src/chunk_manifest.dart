/// State of one [SttChunk] in the streaming-chunked transcription pipeline.
///
/// 流式分片转写流水线中一个 [SttChunk] 的状态。
enum SttChunkState {
  /// Not yet queued for decoding.
  ///
  /// 尚未入队等待解码。
  pending,

  /// Sitting in [ChunkScheduler]'s high or low priority queue.
  ///
  /// 正排在 `ChunkScheduler` 的高或低优先级队列里。
  queued,

  /// A worker is currently extracting/decoding this chunk.
  ///
  /// 有 worker 正在抽取/解码本分片。
  decoding,

  /// Decoding finished; cues are available.
  ///
  /// 解码完成，字幕已可用。
  done,

  /// Extraction or decoding failed.
  ///
  /// 抽取或解码失败。
  failed,
}

/// One time-sliced segment of a source's audio track, with a small overlap
/// on each side so speech spanning a slice boundary still gets decoded in
/// full by at least one neighboring chunk — see [ownStart]/[ownEnd] for how
/// cue ownership across that overlap is resolved.
///
/// 源音轨的一个按时间切出的分片，前后各带一小段重叠，使跨越分片边界的语音
/// 至少能被某一侧的分片完整解码——重叠区的字幕归属判定见 [ownStart]/[ownEnd]。
class SttChunk {
  /// Creates a chunk descriptor.
  ///
  /// 创建一个分片描述。
  SttChunk({
    required this.index,
    required this.start,
    required this.end,
    required this.ownStart,
    required this.ownEnd,
    this.state = SttChunkState.pending,
  });

  /// Zero-based position of this chunk within the manifest.
  ///
  /// 本分片在清单中的从零开始的序号。
  final int index;

  /// Start of the extracted range, including the leading overlap.
  ///
  /// 抽取范围的起点，含前置重叠。
  final Duration start;

  /// End of the extracted range, including the trailing overlap.
  ///
  /// 抽取范围的终点，含后置重叠。
  final Duration end;

  /// Start of this chunk's exclusive ownership range (excludes overlap).
  ///
  /// 本分片独占归属范围的起点（不含重叠）。
  final Duration ownStart;

  /// End of this chunk's exclusive ownership range (excludes overlap).
  ///
  /// 本分片独占归属范围的终点（不含重叠）。
  final Duration ownEnd;

  /// Current lifecycle state; mutated in place by the scheduler/pipeline.
  ///
  /// 当前生命周期状态；由调度器/流水线原地修改。
  SttChunkState state;
}

/// Splits a source's total duration into a sequence of overlapping
/// [SttChunk]s, ready to be handed to [ChunkScheduler].
///
/// Pure computation — no audio is touched here, only the time-range plan.
///
/// 把源的总时长切成一串带重叠的 [SttChunk]，供 [ChunkScheduler] 调度。
///
/// 纯计算——这里不涉及任何音频操作，只产出时间区间计划。
///
/// Example / 示例:
/// ```dart
/// final manifest = ChunkManifest.build(
///   totalDuration: const Duration(minutes: 12, seconds: 30),
///   chunkDuration: const Duration(minutes: 4),
///   overlap: const Duration(seconds: 4),
/// );
/// manifest.chunks.length; // 4 (三个整 4 分钟 + 一个 30 秒尾片)
/// manifest.chunkIndexAt(const Duration(minutes: 5)); // 1
/// ```
class ChunkManifest {
  ChunkManifest._(this.chunks, this._chunkDuration);

  /// Builds a manifest covering `[Duration.zero, totalDuration)`.
  ///
  /// 构建覆盖 `[Duration.zero, totalDuration)` 的清单。
  ///
  /// - [totalDuration]: total length of the source / 源的总时长
  /// - [chunkDuration]: nominal length of each chunk's exclusive-ownership
  ///   range (the last chunk may be shorter) / 每个分片独占归属范围的标称
  ///   时长（最后一片可能更短）
  /// - [overlap]: extra audio pulled in on each side of a chunk purely to
  ///   help VAD/decoding catch speech near the boundary — does not affect
  ///   [SttChunk.ownStart]/[SttChunk.ownEnd] / 每个分片前后额外多抽的一段，
  ///   只是为了帮助 VAD/解码接住边界附近的语音——不影响归属范围
  factory ChunkManifest.build({
    required Duration totalDuration,
    Duration chunkDuration = const Duration(minutes: 4),
    Duration overlap = const Duration(seconds: 4),
  }) {
    if (totalDuration <= Duration.zero) {
      return ChunkManifest._(const [], chunkDuration);
    }
    final chunks = <SttChunk>[];
    var ownStart = Duration.zero;
    var index = 0;
    while (ownStart < totalDuration) {
      final ownEnd = ownStart + chunkDuration > totalDuration
          ? totalDuration
          : ownStart + chunkDuration;
      final start = ownStart - overlap < Duration.zero ? Duration.zero : ownStart - overlap;
      final end = ownEnd + overlap > totalDuration ? totalDuration : ownEnd + overlap;
      chunks.add(SttChunk(index: index, start: start, end: end, ownStart: ownStart, ownEnd: ownEnd));
      ownStart = ownEnd;
      index++;
    }
    return ChunkManifest._(chunks, chunkDuration);
  }

  /// All chunks, in time order.
  ///
  /// 全部分片，按时间顺序排列。
  final List<SttChunk> chunks;

  final Duration _chunkDuration;

  /// Returns the index of the chunk whose exclusive-ownership range covers
  /// [position], clamped to the manifest's bounds.
  ///
  /// 返回独占归属范围覆盖 [position] 的分片序号，越界时夹到清单边界内。
  ///
  /// - [position]: a playback position within the source / 源内的一个播放位置
  int chunkIndexAt(Duration position) {
    if (chunks.isEmpty) return 0;
    if (position <= chunks.first.ownStart) return 0;
    if (position >= chunks.last.ownEnd) return chunks.length - 1;
    // Nominal chunk length gives an O(1) estimate; only the last chunk can
    // be shorter, so this is exact except possibly at the very end, which
    // the clamp above already handles.
    //
    // 用标称分片时长做 O(1) 估算；只有最后一片可能更短，除了已被上面
    // clamp 处理的末尾情况外，估算结果是精确的。
    final estimate = position.inMicroseconds ~/ _chunkDuration.inMicroseconds;
    return estimate.clamp(0, chunks.length - 1);
  }
}
