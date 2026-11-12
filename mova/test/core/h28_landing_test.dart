import 'package:flutter_test/flutter_test.dart';
// The device harness belongs to the separate example package.
// ignore: avoid_relative_lib_imports
import '../../example/lib/verify_auto/seek_landing.dart';

void main() {
  test(
    'playing landing keeps the initial error while verifying continued motion',
    () {
      final landing = SeekLanding(12000, playing: true);
      expect(
        landing.sample(
          elapsedMs: 0,
          positionMs: 12450,
          seeking: false,
          buffering: false,
          pathMatches: true,
        ),
        isFalse,
      );
      expect(
        landing.sample(
          elapsedMs: 450,
          positionMs: 12900,
          seeking: false,
          buffering: false,
          pathMatches: true,
        ),
        isTrue,
      );
      expect(landing.landedMs, 12450);
    },
  );
  for (final paused in [false, true]) {
    test(
      'H28 ${paused ? "paused" : "cutover"}: 12s echo then zero is not landing',
      () {
        final landing = SeekLanding(12000);
        bool at(int ms, int position, {bool seeking = false}) => landing.sample(
          elapsedMs: ms,
          positionMs: position,
          seeking: seeking,
          buffering: false,
          pathMatches: true,
        );
        expect(at(0, 12000), isFalse);
        expect(at(90, 0), isFalse);
        expect(at(500, paused ? 0 : 343), isFalse);
        // Product retry at 1500ms; only the stable native landing counts.
        expect(at(1500, 12000, seeking: true), isFalse);
        expect(at(1600, 12000), isFalse);
        expect(at(2000, paused ? 12000 : 12400), isTrue);
      },
    );
  }
  test('native landing survives delayed UI buffering; wrong path resets it', () {
    final landing = SeekLanding(12000);
    bool at(int ms, {bool buffering = false, bool pathMatches = true}) =>
        landing.sample(
          elapsedMs: ms,
          positionMs: 12000,
          seeking: false,
          buffering: buffering,
          pathMatches: pathMatches,
        );
    expect(at(0), isFalse);
    expect(at(400, buffering: true), isFalse);
    expect(at(500), isTrue);
    expect(at(900, pathMatches: false), isFalse);
    expect(at(1000), isFalse);
    expect(at(1400), isTrue);
  });
}
