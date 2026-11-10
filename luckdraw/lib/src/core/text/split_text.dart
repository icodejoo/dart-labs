import '../foundation/constants.dart';
import '../render/perf_trace.dart';

/// 测量 [text] 的单行宽度，返回逻辑像素数。
typedef LuckyTextWidth = double Function(String text);

/// 按码点和 [measure] 宽度分行；[maxWidthOf] 接收已完成行数。
///
/// [lineClamp] 非正或 null 表示无限；末行预留省略号宽度。空文本返回一个空行。
/// 例如 `splitLuckyText('abc', measure, (_) => 100)`。
List<String> splitLuckyText(String text, LuckyTextWidth measure,
    double Function(int finishedLines) maxWidthOf,
    {int? lineClamp}) {
  luckyTraceStart('luckdraw.text.split');
  try {
    // 上游 index.ts:155-188；IMP-06 仅把 UTF-16 码元迭代改为码点。
    final clamp = lineClamp == null || lineClamp <= 0 ? -1 : lineClamp;
    var str = '';
    final lines = <String>[];
    final endWidth = measure(kLuckyEllipsis);
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      str += ch;
      var currWidth = measure(str);
      final maxWidth = maxWidthOf(lines.length);
      if (clamp == lines.length + 1) currWidth += endWidth;
      if (maxWidth < 0) return lines;
      if (currWidth > maxWidth) {
        lines.add(str.substring(0, str.length - ch.length));
        str = ch;
      }
      if (clamp == lines.length) {
        lines[lines.length - 1] += kLuckyEllipsis;
        return lines;
      }
    }
    if (str.isNotEmpty) lines.add(str);
    if (lines.isEmpty) lines.add(text);
    return lines;
  } finally {
    luckyTraceEnd();
  }
}

/// 删除 [text] 中的换行符 `\n`，保留回车；例如 `'a\nb'` 返回 `'ab'`。
String removeLineBreaks(String text) => text.replaceAll('\n', '');
