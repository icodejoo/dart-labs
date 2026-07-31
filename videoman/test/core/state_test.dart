import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/fit.dart';
import 'package:videoman/src/core/state/progress.dart';
import 'package:videoman/src/core/state/state.dart';
import 'package:videoman/src/core/state/ui_state.dart';

void main() {
  test('VmState.copyWith changes only the given field', () {
    const a = VmState();
    final b = a.copyWith(playing: true);
    expect(b.playing, isTrue);
    expect(b.fit, a.fit);
    expect(b.volume, a.volume);
    expect(b.duration, a.duration);
  });

  test('VmState equality is by value so the bus can dedupe', () {
    const a = VmState();
    final b = a.copyWith(fit: VmFit.contain);
    expect(b, equals(a));
    expect(a.copyWith(fit: VmFit.cover), isNot(equals(a)));
  });

  test('VmState defaults match 0.1.0 behaviour', () {
    const s = VmState();
    expect(s.playing, isFalse);
    expect(s.volume, 100.0);
    expect(s.brightness, 1.0);
    expect(s.rate, 1.0);
    expect(s.zoom, 1.0);
    expect(s.fit, VmFit.contain);
    expect(s.liveSeekable, isFalse);
    expect(s.timeshiftBehind, isNull);
  });

  test('VmProgress and VmUiState compare by value', () {
    expect(const VmProgress(), const VmProgress());
    expect(const VmUiState(), const VmUiState());
    expect(const VmUiState(hud: VmHud.volume), isNot(const VmUiState()));
  });

  test('VmUiState.copyWith can clear previewAt', () {
    const s = VmUiState(previewAt: Duration(seconds: 5));
    expect(s.copyWith(clearPreview: true).previewAt, isNull);
    expect(s.copyWith(dragging: true).previewAt, const Duration(seconds: 5));
  });

  test('VmState.pipSupported defaults to false and round-trips through copyWith', () {
    const s = VmState();
    expect(s.pipSupported, isFalse);
    expect(s.copyWith(pipSupported: true).pipSupported, isTrue);
    expect(s.copyWith(pipSupported: true), isNot(equals(s)));
  });
}
