/// Immutable snapshot of playback position and buffer progress.
///
/// Kept separate from [VmState] because it changes at a much higher
/// frequency (every tick during playback), so consumers that only care
/// about state changes can avoid rebuilding on every progress tick.
///
/// 播放位置与缓冲进度的不可变快照。
///
/// 与 `VmState` 分离，因为它的变化频率远高于状态（播放期间每 tick 都变），
/// 只关心状态变化的消费者可以避免因进度 tick 而频繁重建。
class VmProgress {
  /// Current playback position.
  ///
  /// 当前播放位置。
  final Duration position;

  /// How far playback has buffered ahead.
  ///
  /// 已缓冲到的位置。
  final Duration buffer;

  /// Creates a progress snapshot; defaults to zero/zero.
  ///
  /// 创建一个进度快照；默认零/零。
  const VmProgress({this.position = Duration.zero, this.buffer = Duration.zero});

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回一个替换了指定字段的副本。
  VmProgress copyWith({Duration? position, Duration? buffer}) {
    return VmProgress(
      position: position ?? this.position,
      buffer: buffer ?? this.buffer,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VmProgress && other.position == position && other.buffer == buffer;
  }

  @override
  int get hashCode => Object.hash(position, buffer);
}
