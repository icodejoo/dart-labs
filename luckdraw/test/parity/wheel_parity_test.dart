import 'package:flutter_test/flutter_test.dart';

import 'parity_support.dart';

/// 真实上游转盘数值及 PNG 对照。
void main() {
  group('wheel parity', () {
    for (final id in ['w01', 'w02', 'w03', 'w04', 'w05', 'w06']) {
      test('case $id rotateDeg sequence matches upstream', () {
        final input = ParityCase(id);
        final session = wheelParitySession(input);
        addTearDown(session.dispose);
        expectParitySequence(input, session);
      });
    }
    for (final imageId in ['w01', 'w02', 'w03', 'w05', 'w06']) {
      testWidgets('case $imageId keyframes match upstream within tolerance',
          (tester) async {
        final input = ParityCase(imageId);
        final session = wheelParitySession(input);
        addTearDown(session.dispose);
        await expectParityKeyframes(tester, input, session);
      }, tags: 'golden');
    }
    testWidgets('case w04 keyframes match upstream within tolerance',
        (tester) async {
      final input = ParityCase('w04');
      final session = wheelParitySession(input);
      addTearDown(session.dispose);
      await expectParityKeyframes(tester, input, session);
    }, tags: 'golden');
  });
  group('parity diagnostic', () {
    const ids = [
      'w01',
      'w02',
      'w03',
      'w04',
      'w05',
      'w06',
      'g01',
      'g02',
      'g03',
      'g04',
      'g05',
      's01',
      's02',
      's03',
      's04',
      's05'
    ];
    const labels = ['0', '60', '170', '240', 'settled'];
    const edgeFrames = {
      ('s03', '60'),
      ('s03', '240'),
      ('s05', 'settled'),
      ('s05', '240')
    };
    test('text-heavy tolerance is limited to diagnosed w04 frame 60', () {
      var textFrames = 0;
      for (final id in ids) {
        for (final label in labels) {
          final tolerance = parityImageTolerance(id, label);
          if (id == 'w04' && label == '60') {
            expect(tolerance.layer, 'text-heavy');
            textFrames++;
          } else if (edgeFrames.contains((id, label))) {
            expect(tolerance.layer, 'edge-aa', reason: '$id/$label');
          } else {
            expect(tolerance.layer, 'standard', reason: '$id/$label');
            expect(tolerance.maxDiffRatio, 0.018);
            expect(tolerance.maxMeanError, 1.8);
          }
        }
      }
      expect(textFrames, 1);
      expect(parityImageTolerance('w04', '61').layer, 'standard');
      expect(parityImageTolerance('unknown', '60').layer, 'standard');
    });
    test('edge-aa tolerance is limited to four diagnosed slot frames', () {
      var edgeCount = 0;
      for (final id in ids) {
        for (final label in labels) {
          if (parityImageTolerance(id, label).layer == 'edge-aa') {
            expect(edgeFrames, contains((id, label)));
            edgeCount++;
          }
        }
      }
      expect(edgeCount, 4);
      expect(parityImageTolerance('s03', '0').layer, 'standard');
      expect(parityImageTolerance('s03', '170').layer, 'standard');
    });
    test('text-heavy tolerance keeps ten percent measured headroom below caps',
        () {
      final tolerance = parityImageTolerance('w04', '60');
      expect(tolerance.maxDiffRatio, closeTo(0.022746913580246916, 1e-12));
      expect(tolerance.maxMeanError, closeTo(1.505047839506173, 1e-12));
      expect(tolerance.maxDiffRatio, lessThanOrEqualTo(0.04));
      expect(tolerance.maxMeanError, lessThanOrEqualTo(2.5));
    });
    test('edge-aa tolerance keeps ten percent measured headroom below caps',
        () {
      const measured = {
        ('s03', '60'): (775, 1.386404),
        ('s03', '240'): (733, 1.930154),
        ('s05', 'settled'): (638, 1.510694),
        ('s05', '240'): (638, 1.510694)
      };
      for (final entry in measured.entries) {
        final tolerance = parityImageTolerance(entry.key.$1, entry.key.$2);
        expect(tolerance.maxDiffRatio,
            closeTo(entry.value.$1 / 32400 * 1.1, 1e-12));
        expect(tolerance.maxMeanError, closeTo(entry.value.$2 * 1.1, 1e-12));
        expect(tolerance.maxDiffRatio, lessThanOrEqualTo(0.04));
        expect(tolerance.maxMeanError, lessThanOrEqualTo(2.5));
      }
    });
  });
}
