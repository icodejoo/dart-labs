import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/core/state/ui_state.dart';

void main() {
  test('MovaState.copyWith changes only the given field', () {
    const a = MovaState();
    final b = a.copyWith(playing: true);
    expect(b.playing, isTrue);
    expect(b.fit, a.fit);
    expect(b.volume, a.volume);
    expect(b.duration, a.duration);
  });

  test('MovaState equality is by value so the bus can dedupe', () {
    const a = MovaState();
    final b = a.copyWith(fit: MovaFit.contain);
    expect(b, equals(a));
    expect(a.copyWith(fit: MovaFit.cover), isNot(equals(a)));
  });

  test('MovaState defaults match 0.1.0 behaviour', () {
    const s = MovaState();
    expect(s.playing, isFalse);
    expect(s.volume, 100.0);
    expect(s.brightness, 1.0);
    expect(s.rate, 1.0);
    expect(s.zoom, 1.0);
    expect(s.fit, MovaFit.contain);
    expect(s.liveSeekable, isFalse);
    expect(s.timeshiftBehind, isNull);
  });

  test('MovaProg and MovaUiState compare by value', () {
    expect(const MovaProg(), const MovaProg());
    expect(const MovaUiState(), const MovaUiState());
    expect(const MovaUiState(hud: MovaHud.volume), isNot(const MovaUiState()));
  });

  test('MovaUiState.copyWith can clear previewAt', () {
    const s = MovaUiState(previewAt: Duration(seconds: 5));
    expect(s.copyWith(clearPreview: true).previewAt, isNull);
    expect(s.copyWith(dragging: true).previewAt, const Duration(seconds: 5));
  });

  test('MovaState.pipSupported defaults to false and round-trips through copyWith', () {
    const s = MovaState();
    expect(s.pipSupported, isFalse);
    expect(s.copyWith(pipSupported: true).pipSupported, isTrue);
    expect(s.copyWith(pipSupported: true), isNot(equals(s)));
  });
}
