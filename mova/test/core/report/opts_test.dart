import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/report/error_policy.dart';
import 'package:mova/src/core/report/session_id.dart';
import 'package:mova/src/core/report/stall.dart';

void main() {
  group('MovaReportOpts defaults', () {
    test('qoe defaults to false, minStall to 200ms, heartbeat to null', () {
      const opts = MovaReportOpts();
      expect(opts.qoe, isFalse);
      expect(opts.minStall, const Duration(milliseconds: 200));
      expect(opts.heartbeat, isNull);
      expect(opts.stallPolicy, isNull);
      expect(opts.errorPolicy, isNull);
      expect(opts.sessionId, isNull);
    });

    test('MovaOpts().report is the default opts', () {
      expect(const MovaOpts().report, const MovaReportOpts());
    });
  });

  group('MovaReportOpts.newStallPolicy', () {
    test('returns a fresh instance every call', () {
      const opts = MovaReportOpts();
      final a = opts.newStallPolicy();
      final b = opts.newStallPolicy();
      expect(identical(a, b), isFalse);
      expect(a, isA<MovaEdgeStall>());
    });

    test('an injected stallPolicy is returned verbatim', () {
      final injected = MovaEdgeStall();
      final opts = MovaReportOpts(stallPolicy: injected);
      expect(identical(opts.newStallPolicy(), injected), isTrue);
    });
  });

  group('MovaReportOpts.effectiveErrorPolicy', () {
    test('defaults to MovaPrefixError', () {
      const opts = MovaReportOpts();
      expect(opts.effectiveErrorPolicy, isA<MovaPrefixError>());
    });

    test('an injected errorPolicy is returned verbatim', () {
      const injected = _FixedError();
      const opts = MovaReportOpts(errorPolicy: injected);
      expect(identical(opts.effectiveErrorPolicy, injected), isTrue);
    });
  });

  group('MovaReportOpts.effectiveSessionIdFactory', () {
    test('defaults to newMovaSessionId', () {
      const opts = MovaReportOpts();
      expect(opts.effectiveSessionIdFactory, same(newMovaSessionId));
    });

    test('an injected sessionId factory is actually used', () {
      var calls = 0;
      String factory() {
        calls++;
        return 'fixed-id';
      }

      final opts = MovaReportOpts(sessionId: factory);
      expect(opts.effectiveSessionIdFactory(), 'fixed-id');
      expect(calls, 1);
    });
  });

  test('copyWith replaces one field without disturbing the others', () {
    const base = MovaReportOpts();
    final copy = base.copyWith(qoe: true);
    expect(copy.qoe, isTrue);
    expect(copy.minStall, base.minStall);
    expect(copy.heartbeat, base.heartbeat);
  });

  test("MovaOpts.copyWith(report: ...) doesn't affect other sections", () {
    const opts = MovaOpts();
    final updated = opts.copyWith(report: const MovaReportOpts(qoe: true));
    expect(updated.report.qoe, isTrue);
    expect(updated.abr, opts.abr);
    expect(updated.live, opts.live);
  });

  test('newMovaSessionId() produces 1000 distinct ids', () {
    final ids = {for (var i = 0; i < 1000; i++) newMovaSessionId()};
    expect(ids.length, 1000);
  });
}

class _FixedError implements IMovaErrorPolicy {
  const _FixedError();
  @override
  MovaErrorVerdict classify(Object error, {String? subsystem, required bool afterFirstFrame}) =>
      const MovaErrorVerdict(fatal: false, code: 'fixed');
}
