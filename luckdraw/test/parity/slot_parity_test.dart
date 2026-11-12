import 'package:flutter_test/flutter_test.dart';

import 'parity_support.dart';

/// 真实上游老虎机数值及 PNG 对照。
void main() {
  group('slot parity', () {
    for (final id in ['s01', 's02', 's03', 's04', 's05']) {
      test('case $id scroll sequence matches upstream', () {
        final input = ParityCase(id);
        final session = slotParitySession(input);
        addTearDown(session.dispose);
        expectParitySequence(input, session);
      });
    }
    // s03 与 s05 的残余差异经 DIAG2 判定为文字光栅化加 reel 列边界的 1 像素
    // 抗锯齿差异，逐帧登记在 parityImageTolerance 的 edge-aa 层，详见 FINDINGS。
    for (final imageId in ['s01', 's02', 's03', 's04', 's05']) {
      testWidgets('case $imageId keyframes match upstream within tolerance',
          (tester) async {
        final input = ParityCase(imageId);
        final session = slotParitySession(input);
        addTearDown(session.dispose);
        await expectParityKeyframes(tester, input, session);
      }, tags: 'golden');
    }
  });
}
