import 'package:flutter_test/flutter_test.dart';
import 'package:mova_stt/mova_stt.dart';

void main() {
  group('parallelismForCoreCount', () {
    test('uses half the core count on typical multi-core devices', () {
      expect(parallelismForCoreCount(8), 4);
      expect(parallelismForCoreCount(6), 3);
      expect(parallelismForCoreCount(4), 2);
    });

    test('never goes below 1 even on low-core devices', () {
      expect(parallelismForCoreCount(2), 1);
      expect(parallelismForCoreCount(1), 1);
      expect(parallelismForCoreCount(0), 1);
    });

    test('caps at 4 regardless of how many cores are available (memory budget)', () {
      expect(parallelismForCoreCount(16), 4);
      expect(parallelismForCoreCount(64), 4);
    });
  });
}
