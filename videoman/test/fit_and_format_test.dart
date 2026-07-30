import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/videoman.dart';
import 'package:videoman/src/controls/controls_common.dart';

void main() {
  group('VmFit', () {
    test('cycles contain → cover → fill → contain', () {
      expect(VmFit.contain.next, VmFit.cover);
      expect(VmFit.cover.next, VmFit.fill);
      expect(VmFit.fill.next, VmFit.contain);
    });

    test('maps to the matching BoxFit', () {
      expect(vmBoxFit(VmFit.contain), BoxFit.contain);
      expect(vmBoxFit(VmFit.cover), BoxFit.cover);
      expect(vmBoxFit(VmFit.fill), BoxFit.fill);
    });

    test('every mode has a non-empty label', () {
      for (final f in VmFit.values) {
        expect(f.label, isNotEmpty);
      }
    });
  });

  group('preferredOrientationsFor', () {
    test('landscape video ⇒ landscape orientations', () {
      final o = preferredOrientationsFor(1920, 1080);
      expect(o, contains(DeviceOrientation.landscapeLeft));
      expect(o, isNot(contains(DeviceOrientation.portraitUp)));
    });

    test('portrait video ⇒ portrait orientations', () {
      final o = preferredOrientationsFor(1080, 1920);
      expect(o, contains(DeviceOrientation.portraitUp));
      expect(o, isNot(contains(DeviceOrientation.landscapeLeft)));
    });

    test('square video ⇒ landscape (width ≥ height)', () {
      expect(preferredOrientationsFor(500, 500), contains(DeviceOrientation.landscapeLeft));
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
