import 'package:flutter_test/flutter_test.dart';
import 'package:mova_example/main_coverage_api.dart' as c;
import 'package:mova_example/verify_auto/s00d_contract.dart' as s00d;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('QoE observations retain inputs and four terminal reasons', () async {
    c.records.clear();
    await s00d.run();
    final checks = c.records.where((r) => r['kind'] == 'CHECK').toList();
    expect(checks.length, greaterThan(100));
    expect(checks.where((r) => r['pass'] != true).toList(), isEmpty);
    expect(
      checks.every(
        (r) =>
            (r.containsKey('actual') && r.containsKey('expected')) ||
            r['numbers'] is Map,
      ),
      isTrue,
    );
  });
}
