import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

void main() {
  group('movaBoxFit', () {
    test('maps to the matching BoxFit', () {
      expect(movaBoxFit(MovaFit.contain), BoxFit.contain);
      expect(movaBoxFit(MovaFit.cover), BoxFit.cover);
      expect(movaBoxFit(MovaFit.fill), BoxFit.fill);
    });
  });

  group('formatDuration', () {
    test('mm:ss under an hour', () {
      expect(formatDuration(const Duration(seconds: 75)), '01:15');
      expect(formatDuration(Duration.zero), '00:00');
    });

    test('h:mm:ss at or over an hour', () {
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    });

    test('keeps a leading minus for negatives', () {
      expect(formatDuration(const Duration(seconds: -30)), '-00:30');
    });
  });
}
