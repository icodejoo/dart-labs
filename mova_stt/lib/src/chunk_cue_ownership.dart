import 'package:mova/mova.dart';

import 'chunk_manifest.dart';

/// Whether [cue] belongs to [chunk], resolving the overlap between
/// neighboring chunks by the cue's midpoint — a cue whose midpoint falls
/// inside `[chunk.ownStart, chunk.ownEnd)` belongs here; one whose midpoint
/// falls in the leading/trailing overlap belongs to the neighboring chunk
/// that owns that range instead, so a chunk must drop its own overlap-region
/// cues that fail this check to avoid duplicate/conflicting subtitles at
/// slice boundaries.
///
/// Pure function — no audio or engine dependency, only [MovaSttCue] and
/// [SttChunk] time ranges.
///
/// 判断 [cue] 是否归属于 [chunk]，用 cue 的中点解决相邻分片的重叠区
/// 归属——中点落在 `[chunk.ownStart, chunk.ownEnd)` 内就归本片；落在前后
/// 重叠区的中点归属于拥有那段范围的相邻分片，因此一个分片必须丢弃自己
/// 重叠区里没通过这个判定的 cue，避免分片边界处出现重复/冲突的字幕。
///
/// 纯函数——不依赖音频或引擎，只用到 [MovaSttCue] 和 [SttChunk] 的时间区间。
///
/// Example / 示例:
/// ```dart
/// final chunk = ChunkManifest.build(totalDuration: const Duration(minutes: 8)).chunks[0];
/// cueBelongsToChunk(
///   const MovaSttCue(text: 'x', start: Duration(seconds: 1), end: Duration(seconds: 3)),
///   chunk,
/// ); // true —— 中点 2s 落在本片独占范围内
/// ```
bool cueBelongsToChunk(MovaSttCue cue, SttChunk chunk) {
  final midMicros = (cue.start.inMicroseconds + cue.end.inMicroseconds) ~/ 2;
  final mid = Duration(microseconds: midMicros);
  return mid >= chunk.ownStart && mid < chunk.ownEnd;
}
