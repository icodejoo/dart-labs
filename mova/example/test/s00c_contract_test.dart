import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:mova_example/main_coverage_api.dart' as c;
import 'package:mova_example/verify_auto/s00c_contract.dart' as s00c;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'public API coverage emits measured checks without a native player',
    () async {
      c.records.clear();
      final overrides = HttpOverrides.current;
      // This probe verifies an actual loopback Range request. Flutter's default
      // test HttpClient returns 400 without contacting the loopback server.
      HttpOverrides.global = null;
      try {
        await s00c.run();
      } finally {
        HttpOverrides.global = overrides;
      }
      final errors = c.records.where((r) => r['kind'] == 'S00C_SCRIPT_ERROR');
      expect(errors, isEmpty, reason: '$errors');
      // A2 receipt audits are independent strict product observations and may
      // deliberately fail on the injected asynchronous kernel. This test owns
      // only the S00c contract producers; it must not rewrite their A2 verdicts.
      final checks = c.records
          .where(
            (r) =>
                r['kind'] == 'CHECK' &&
                [
                  'public-testing-kernel',
                  'loopback-http',
                ].contains(r['origin']),
          )
          .toList();
      expect(checks.length, greaterThanOrEqualTo(16));
      expect(checks.where((r) => r['pass'] != true), isEmpty);
      expect(
        checks.every(
          (r) =>
              ['public-testing-kernel', 'loopback-http'].contains(r['origin']),
        ),
        isTrue,
      );
      expect(
        checks.map((r) => r['id']),
        containsAll([
          'A29.rangeWarm',
          'C13.defaultHeartbeat',
          'A30.cancelResult',
          'A30.staleResult',
        ]),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
