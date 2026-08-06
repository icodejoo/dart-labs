import 'package:mova/mova.dart';

/// Appends punctuation to each cue in [cues] based on the silence gap to the
/// next one — a zero-dependency fallback for Zipformer's raw output, which
/// carries no punctuation at all (the model was never trained to produce
/// any). Not grammatically aware; it only distinguishes "the speaker kept
/// going" from "the speaker paused" and "the speaker paused for a while",
/// which is already a large readability improvement over one run-on string.
///
/// A cue whose text already ends with terminal punctuation ('。', '！', '？',
/// '，', '.', '!', '?', ',') is left untouched, so re-running this on
/// already-punctuated text (e.g. from a real punctuation-restoration model
/// added later) is a no-op rather than double-punctuating.
///
/// - [cues]: cues in chronological order, as produced by a [MovaSttEngine] /
///   按时间顺序排列的字幕，来自某个 [MovaSttEngine] 的产出
/// - [longPause]: a gap at or above this to the next cue gets a full stop
///   appended / 到下一条字幕的间隔达到这个值就补句号
/// - [shortPause]: a gap at or above this (but below [longPause]) gets a
///   comma appended; shorter gaps get nothing / 达到这个值（但不到
///   [longPause]）就补逗号；更短的间隔不补任何符号
///
/// Returns a new list — [cues] is not mutated.
///
/// 依据到下一条的静音间隔时长，给 [cues] 里每一条字幕补标点——这是给
/// Zipformer 裸输出（模型从没训练过要产出标点）的零依赖兜底方案。不懂语法，
/// 只能分辨"接着说"、"停顿了一下"、"停顿了较久"这三档，但比通篇一句话已经是
/// 很大的可读性提升。
///
/// 已经以终止标点（'。'、'！'、'？'、'，'、'.'、'!'、'?'、','）结尾的字幕不会
/// 被改动，所以对已经带标点的文本（比如以后接入真正的标点恢复模型）重复调用
/// 是空操作，不会叠加标点。
///
/// 返回一个新列表——不会修改 [cues] 本身。
List<MovaSttCue> insertPauseBasedPunctuation(
  List<MovaSttCue> cues, {
  Duration longPause = const Duration(milliseconds: 600),
  Duration shortPause = const Duration(milliseconds: 200),
}) {
  final result = <MovaSttCue>[];
  for (var i = 0; i < cues.length; i++) {
    final cue = cues[i];
    if (cue.text.isEmpty || _endsWithPunctuation(cue.text)) {
      result.add(cue);
      continue;
    }
    final gap = i + 1 < cues.length ? cues[i + 1].start - cue.end : longPause;
    final String mark;
    if (gap >= longPause) {
      mark = '。';
    } else if (gap >= shortPause) {
      mark = '，';
    } else {
      result.add(cue);
      continue;
    }
    result.add(MovaSttCue(text: '${cue.text}$mark', start: cue.start, end: cue.end));
  }
  return result;
}

const _terminalPunctuation = {'。', '！', '？', '，', '.', '!', '?', ','};

bool _endsWithPunctuation(String text) => _terminalPunctuation.contains(text[text.length - 1]);
