import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

void main() {
  Duration ms(int n) => Duration(milliseconds: n);
  MovaFirstFrameGate armed({bool autoPlay = true}) => MovaFirstFrameGate()..arm(autoPlay: autoPlay);

  test('unarmed gate ignores everything', () {
    final g = MovaFirstFrameGate();
    expect(g.onRestart(), isNull);
    expect(g.onBuffering(true, nativeLive: false), isNull);
    expect(g.onBuffering(false, nativeLive: false), isNull);
    expect(g.onProgress(ms(40), nativeLive: false), isNull);
    expect(g.onProgress(ms(80), nativeLive: false), isNull);
    expect(g.onSize(1280, 720, nativeLive: false), isNull);
    expect(g.onGraceExpired(), isNull);
  });

  test('restart lands immediately and only once', () {
    final g = armed();
    expect(g.onRestart(), MovaFirstFrameSignal.restart);
    expect(g.landed, isTrue);
    expect(g.onRestart(), isNull);
  });

  test('initial false without a prior true does not land', () {
    final g = armed();
    expect(g.onBuffering(false, nativeLive: false), isNull);
    expect(g.landed, isFalse);
  });

  test('true to false edge lands as buffering', () {
    final g = armed();
    g.onBuffering(true, nativeLive: false);
    expect(g.onBuffering(false, nativeLive: false), MovaFirstFrameSignal.buffering);
  });

  test('native live defers to grace, then restart wins', () {
    final g = armed();
    g.onBuffering(true, nativeLive: true);
    expect(g.onBuffering(false, nativeLive: true), isNull);
    expect(g.landed, isFalse);
    expect(g.awaitingGrace, isTrue);
    expect(g.onRestart(), MovaFirstFrameSignal.restart);
    expect(g.awaitingGrace, isFalse);
  });

  test('grace expiry lands only when awaiting', () {
    final g = armed();
    expect(g.onGraceExpired(), isNull);
    g.onBuffering(true, nativeLive: true);
    g.onBuffering(false, nativeLive: true);
    expect(g.onGraceExpired(), MovaFirstFrameSignal.grace);
    expect(g.landed, isTrue);
  });

  test('progress needs two consecutive increases above zero', () {
    final g = armed();
    expect(g.onProgress(Duration.zero, nativeLive: false), isNull);
    expect(g.onProgress(ms(40), nativeLive: false), isNull);
    expect(g.onProgress(ms(80), nativeLive: false), MovaFirstFrameSignal.progress);
  });

  test('non-increasing positions do not land', () {
    final g = armed();
    g.onProgress(ms(80), nativeLive: false);
    expect(g.onProgress(ms(80), nativeLive: false), isNull);
    expect(g.onProgress(ms(40), nativeLive: false), isNull);
    expect(g.landed, isFalse);
  });

  test('size lands for a paused open; zero size does not', () {
    final g = armed(autoPlay: false);
    expect(g.onSize(0, 0, nativeLive: false), isNull);
    expect(g.onSize(1280, 720, nativeLive: false), MovaFirstFrameSignal.size);
  });

  test('size is ignored when autoPlay is true', () {
    final g = armed();
    expect(g.onSize(1280, 720, nativeLive: false), isNull);
  });

  test('size with native live only enters grace', () {
    final g = armed(autoPlay: false);
    expect(g.onSize(1280, 720, nativeLive: true), isNull);
    expect(g.landed, isFalse);
    expect(g.awaitingGrace, isTrue);
  });

  test('re-arm clears edge and position memory', () {
    final g = armed();
    g.onBuffering(true, nativeLive: false);
    g.onProgress(ms(40), nativeLive: false);
    g.arm(autoPlay: true);
    expect(g.onBuffering(false, nativeLive: false), isNull);
    expect(g.onProgress(ms(80), nativeLive: false), isNull);
  });

  test('reset clears all flags', () {
    final g = armed();
    g.onBuffering(true, nativeLive: true);
    g.onBuffering(false, nativeLive: true);
    g.reset();
    expect(g.armed, isFalse);
    expect(g.landed, isFalse);
    expect(g.awaitingGrace, isFalse);
  });

  test('fallbacks after landing never raise awaitingGrace', () {
    final g = armed();
    g.onRestart();
    g.onBuffering(true, nativeLive: true);
    g.onBuffering(false, nativeLive: true);
    expect(g.awaitingGrace, isFalse);
  });

  test('resume arming ignores buffering edges and moving positions', () {
    final g = MovaFirstFrameGate()..arm(autoPlay: true, resume: true);
    expect(g.onBuffering(true, nativeLive: false), isNull);
    expect(g.onBuffering(false, nativeLive: false), isNull);
    expect(g.onProgress(ms(40), nativeLive: false), isNull);
    expect(g.onProgress(ms(80), nativeLive: false), isNull);
    expect(g.onProgress(ms(120), nativeLive: false), isNull);
    expect(g.landed, isFalse);
  });

  test('resume arming lands a non-zero size at once, with no grace wait', () {
    final g = MovaFirstFrameGate()..arm(autoPlay: true, resume: true);
    expect(g.onSize(0, 0, nativeLive: true), isNull);
    expect(g.onSize(1280, 720, nativeLive: true), MovaFirstFrameSignal.size);
    expect(g.landed, isTrue);
    expect(g.awaitingGrace, isFalse);
  });

  test('resume arming lands on a native restart, and a later plain arm restores the default rules', () {
    final g = MovaFirstFrameGate()..arm(autoPlay: true, resume: true);
    expect(g.onRestart(), MovaFirstFrameSignal.restart);
    g.arm(autoPlay: true);
    expect(g.onBuffering(true, nativeLive: false), isNull);
    expect(g.onBuffering(false, nativeLive: false), MovaFirstFrameSignal.buffering);
  });
}
