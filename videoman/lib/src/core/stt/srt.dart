import 'cue.dart';

/// Parses SubRip (`.srt`) text into an ordered list of [VmSttCue]s.
///
/// Tolerant of the common variations real SRT files have (CRLF line endings,
/// a stray leading BOM, blank lines between blocks) but does not attempt to
/// recover from genuinely malformed blocks — those are skipped rather than
/// thrown, since a single bad cue in a large file shouldn't sink the whole
/// parse.
///
/// 把 SubRip（`.srt`）文本解析为有序的 [VmSttCue] 列表。
///
/// 容忍真实 SRT 文件常见的变体（CRLF 换行、开头多余的 BOM、块间空行），但
/// 不会尝试修复真正畸形的块——那些直接跳过而非抛异常，因为大文件里一条坏字幕
/// 不该拖垮整个解析。
///
/// - [text]: the full SRT file content / 完整的 SRT 文件内容
///
/// Returns the parsed cues, in file order.
///
/// 返回按文件顺序排列的解析结果。
List<VmSttCue> parseSrt(String text) {
  final cues = <VmSttCue>[];
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('﻿', '');
  final blocks = normalized.split(RegExp(r'\n\s*\n'));
  for (final block in blocks) {
    final lines = block.trim().split('\n');
    if (lines.length < 2) continue;
    // Line 0 is the sequence number (ignored — cues are already ordered by
    // file position); line 1 is the timing line; the rest is the cue text,
    // possibly spanning multiple lines.
    //
    // 第 0 行是序号（忽略——字幕本就按文件位置排序）；第 1 行是时间行；
    // 其余是字幕文本，可能跨多行。
    final timing = _parseTiming(lines[1]);
    if (timing == null) continue;
    final text = lines.sublist(2).join('\n').trim();
    if (text.isEmpty) continue;
    cues.add(VmSttCue(text: text, start: timing.$1, end: timing.$2));
  }
  return cues;
}

/// Formats [cues] as SubRip (`.srt`) text, one block per cue, in the order
/// given (callers are responsible for pre-sorting if that matters).
///
/// 把 [cues] 格式化为 SubRip（`.srt`）文本，每条字幕一个块，顺序即传入顺序
/// （若顺序重要，排序由调用方负责）。
///
/// - [cues]: the cues to format / 要格式化的字幕
///
/// Returns the SRT file content.
///
/// 返回 SRT 文件内容。
String formatSrt(List<VmSttCue> cues) {
  final buffer = StringBuffer();
  for (var i = 0; i < cues.length; i++) {
    final cue = cues[i];
    buffer
      ..writeln(i + 1)
      ..writeln('${_formatTimestamp(cue.start)} --> ${_formatTimestamp(cue.end)}')
      ..writeln(cue.text)
      ..writeln();
  }
  return buffer.toString();
}

/// Matches an SRT timing line, e.g. `00:00:01,000 --> 00:00:03,500`.
///
/// 匹配 SRT 时间行，如 `00:00:01,000 --> 00:00:03,500`。
final _timingPattern = RegExp(
  r'^(\d{2}):(\d{2}):(\d{2}),(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2}),(\d{3})',
);

/// Parses one SRT timing [line] into its `(start, end)` durations, or null if
/// it doesn't match the expected shape.
///
/// 把一行 SRT 时间行 [line] 解析为其 `(start, end)` 时长；不匹配预期格式时
/// 返回 null。
(Duration, Duration)? _parseTiming(String line) {
  final m = _timingPattern.firstMatch(line.trim());
  if (m == null) return null;
  final start = Duration(
    hours: int.parse(m[1]!),
    minutes: int.parse(m[2]!),
    seconds: int.parse(m[3]!),
    milliseconds: int.parse(m[4]!),
  );
  final end = Duration(
    hours: int.parse(m[5]!),
    minutes: int.parse(m[6]!),
    seconds: int.parse(m[7]!),
    milliseconds: int.parse(m[8]!),
  );
  return (start, end);
}

/// Formats [d] as an SRT timestamp, e.g. `00:00:01,000`.
///
/// 把 [d] 格式化为 SRT 时间戳，如 `00:00:01,000`。
String _formatTimestamp(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  final millis = d.inMilliseconds.remainder(1000);
  return '${two(hours)}:${two(minutes)}:${two(seconds)},${three(millis)}';
}
