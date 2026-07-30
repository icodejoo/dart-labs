import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvideo/fvideo.dart';
import 'package:fvideo/src/controls/controls_common.dart';

void main() {
  group('FvideoFit', () {
    test('cycles contain → cover → fill → contain', () {
      expect(FvideoFit.contain.next, FvideoFit.cover);
      expect(FvideoFit.cover.next, FvideoFit.fill);
      expect(FvideoFit.fill.next, FvideoFit.contain);
    });

    test('maps to the matching BoxFit', () {
      expect(fvideoBoxFit(FvideoFit.contain), BoxFit.contain);
      expect(fvideoBoxFit(FvideoFit.cover), BoxFit.cover);
      expect(fvideoBoxFit(FvideoFit.fill), BoxFit.fill);
    });

    test('every mode has a non-empty label', () {
      for (final f in FvideoFit.values) {
        expect(f.label, isNotEmpty);
      }
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
