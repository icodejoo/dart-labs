// A single recognized speech-to-text subtitle cue.
//
// 单条语音识别生成的字幕。

/// One recognized text span, with the media-position range it covers.
///
/// Produced by a [MovaSttEngine] as it transcribes; the UI overlay renders
/// whichever cue's `[start, end)` range contains the current playback
/// position.
///
/// 一条识别出的文本区间，附带其覆盖的媒体位置范围。
///
/// 由 [MovaSttEngine] 边转写边产出；UI 叠层渲染当前播放位置落在
/// `[start, end)` 区间内的那一条。
///
/// Example / 示例:
/// ```dart
/// const cue = MovaSttCue(
///   text: '大家好',
///   start: Duration(seconds: 10),
///   end: Duration(seconds: 12),
/// );
/// ```
class MovaSttCue {
  /// Creates a subtitle cue.
  ///
  /// 创建一条字幕。
  const MovaSttCue({required this.text, required this.start, required this.end});

  /// The recognized text.
  ///
  /// 识别出的文本。
  final String text;

  /// Start of the media-position range this cue covers (inclusive).
  ///
  /// 该字幕覆盖区间的起点（含）。
  final Duration start;

  /// End of the media-position range this cue covers (exclusive).
  ///
  /// 该字幕覆盖区间的终点（不含）。
  final Duration end;

  /// Whether [position] falls within `[start, end)`.
  ///
  /// 判断 [position] 是否落在 `[start, end)` 区间内。
  ///
  /// - [position]: the playback position to test / 待检验的播放位置
  bool covers(Duration position) => position >= start && position < end;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaSttCue && text == other.text && start == other.start && end == other.end;

  @override
  int get hashCode => Object.hash(text, start, end);
}
