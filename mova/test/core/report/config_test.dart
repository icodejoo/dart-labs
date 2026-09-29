import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/report/error_policy.dart';
import 'package:mova/src/core/report/session_id.dart';
import 'package:mova/src/core/report/stall.dart';

void main() {
  group('MovaReportConfig defaults', () {
    test('qoe defaults to false, minStall to 200ms, heartbeat to null', () {
      const config = MovaReportConfig();
      expect(config.qoe, isFalse);
      expect(config.minStall, const Duration(milliseconds: 200));
      expect(config.heartbeat, isNull);
      expect(config.stallPolicy, isNull);
      expect(config.errorPolicy, isNull);
      expect(config.sessionId, isNull);
    });

    test('MovaOpts().report is the default config', () {
      expect(const MovaOpts().report, const MovaReportConfig());
    });
  });

  group('MovaReportConfig.newStallPolicy', () {
    test('returns a fresh instance every call', () {
      const config = MovaReportConfig();
      final a = config.newStallPolicy();
      final b = config.newStallPolicy();
      expect(identical(a, b), isFalse);
      expect(a, isA<MovaEdgeStall>());
    });

    test('an injected stallPolicy is returned verbatim', () {
      final injected = MovaEdgeStall();
      final config = MovaReportConfig(stallPolicy: injected);
      expect(identical(config.newStallPolicy(), injected), isTrue);
    });
  });

  group('MovaReportConfig.effectiveErrorPolicy', () {
    test('defaults to MovaPrefixError', () {
      const config = MovaReportConfig();
      expect(config.effectiveErrorPolicy, isA<MovaPrefixError>());
    });

    test('an injected errorPolicy is returned verbatim', () {
      const injected = _FixedError();
      const config = MovaReportConfig(errorPolicy: injected);
      expect(identical(config.effectiveErrorPolicy, injected), isTrue);
    });
  });

  group('MovaReportConfig.effectiveSessionIdFactory', () {
    test('defaults to newMovaSessionId', () {
      const config = MovaReportConfig();
      expect(config.effectiveSessionIdFactory, same(newMovaSessionId));
    });

    test('an injected sessionId factory is actually used', () {
      var calls = 0;
      String factory() {
        calls++;
        return 'fixed-id';
      }

      final config = MovaReportConfig(sessionId: factory);
      expect(config.effectiveSessionIdFactory(), 'fixed-id');
      expect(calls, 1);
    });
  });

  test('copyWith replaces one field without disturbing the others', () {
    const base = MovaReportConfig();
    final copy = base.copyWith(qoe: true);
    expect(copy.qoe, isTrue);
    expect(copy.minStall, base.minStall);
    expect(copy.heartbeat, base.heartbeat);
  });

  test("MovaOpts.copyWith(report: ...) doesn't affect other sections", () {
    const opts = MovaOpts();
    final updated = opts.copyWith(report: const MovaReportConfig(qoe: true));
    expect(updated.report.qoe, isTrue);
    expect(updated.abr, opts.abr);
    expect(updated.live, opts.live);
  });

  test('newMovaSessionId() produces 1000 distinct ids', () {
    final ids = {for (var i = 0; i < 1000; i++) newMovaSessionId()};
    expect(ids.length, 1000);
  });
}

class _FixedError implements MovaErrorPolicy {
  const _FixedError();
  @override
  MovaErrorVerdict classify(Object error, {String? subsystem, required bool afterFirstFrame}) =>
      const MovaErrorVerdict(fatal: false, code: 'fixed');
}
