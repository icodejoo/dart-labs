import 'package:flutter_test/flutter_test.dart';

import 'parity_support.dart';

/// 真实上游九宫格数值及 PNG 对照。
void main() {
  group('grid parity', () {
    for (final id in ['g01', 'g02', 'g03', 'g04']) {
      test('case $id currIndex sequence matches upstream', () {
        final input = ParityCase(id);
        final session = gridParitySession(input);
        addTearDown(session.dispose);
        expectParitySequence(input, session);
      });
    }
    test('case g05 currIndex sequence matches upstream', () {
      final input = ParityCase('g05');
      final session = gridParitySession(input);
      addTearDown(session.dispose);
      expectParitySequence(input, session);
    });
    for (final imageId in ['g01', 'g02', 'g03', 'g04', 'g05']) {
      testWidgets('case $imageId keyframes match upstream within tolerance',
          (tester) async {
        final input = ParityCase(imageId);
        final session = gridParitySession(input);
        addTearDown(session.dispose);
        await expectParityKeyframes(tester, input, session);
      }, tags: 'golden');
    }
  });
}
