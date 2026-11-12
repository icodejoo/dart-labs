import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

/// 验证零宽与负宽在上游拆行规则中有可观测区别。
void main() {
  test('zero available width preserves the upstream oversized character rule',
      () {
    const text = 'a';
    const characterWidth = 10.0;

    /// 按码点给出确定性的测量宽度。
    double measure(String value) => value.runes.length * characterWidth;
    final requestedRows = <int>[];
    final lines = splitLuckyText(text, measure, (finishedLines) {
      requestedRows.add(finishedLines);
      return 0;
    });
    expect(lines, ['', text]);
    expect(requestedRows, [0]);
    expect(splitLuckyText(text, measure, (_) => -1), isEmpty);
  });
}
