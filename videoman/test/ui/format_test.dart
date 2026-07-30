import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/videoman.dart';
import 'package:videoman/src/ui/fit_ext.dart';
import 'package:videoman/src/ui/format.dart';

void main() {
  group('vmBoxFit', () {
    test('maps to the matching BoxFit', () {
      expect(vmBoxFit(VmFit.contain), BoxFit.contain);
      expect(vmBoxFit(VmFit.cover), BoxFit.cover);
      expect(vmBoxFit(VmFit.fill), BoxFit.fill);
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
