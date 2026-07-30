import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/fit.dart';
import 'package:videoman/src/core/options/options.dart';

void main() {
  test('VmOptions defaults are const-constructible and preserve 0.1.0 gesture behaviour', () {
    const o = VmOptions();
    expect(o.gesture.leftVerticalVolume, isTrue);
    expect(o.gesture.rightVerticalBrightness, isTrue);
    expect(o.gesture.hSeekSpanPerScreen, const Duration(seconds: 90));
    expect(o.gesture.doubleTapStep, const Duration(seconds: 10));
    expect(o.abr.stallThreshold, 3);
    expect(o.controls.autoHideDelay, const Duration(seconds: 3));
    expect(o.live.seekMode, VmLiveSeekMode.off);
  });

  test('VmStrings.fitLabel covers every VmFit value', () {
    const s = VmStrings();
    for (final f in VmFit.values) {
      expect(s.fitLabel(f), isNotEmpty);
    }
    expect(s.fitLabel(VmFit.contain), '适应');
  });

  test('VmStrings can be replaced wholesale for localisation', () {
    const s = VmStrings(fitContain: 'Fit', live: 'ON AIR');
    expect(s.fitLabel(VmFit.contain), 'Fit');
    expect(s.live, 'ON AIR');
  });

  test('VmOptions.copyWith replaces one section only', () {
    const o = VmOptions();
    final n = o.copyWith(controls: const VmControlsConfig(autoHide: false));
    expect(n.controls.autoHide, isFalse);
    expect(n.gesture, o.gesture);
  });
}
