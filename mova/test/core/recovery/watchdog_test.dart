import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/recovery/fail.dart';
import 'package:mova/src/core/recovery/watchdog.dart';

/// Records every timeout a watchdog reports.
///
/// 记录看门狗上报的每次超时。
class _Rec {
  final List<(MovaPlayFailKind, Duration)> hits = [];

  MovaPlayWatchdog make({Duration start = const Duration(seconds: 10), Duration? stall = const Duration(seconds: 5)}) =>
      MovaPlayWatchdog(startTimeout: start, stallTimeout: stall, onTimeout: (k, w) => hits.add((k, w)));
}

void main() {
  const s = Duration(seconds: 1);

  test('armStart(playing) fires startTimeout after the deadline with waited == startTimeout', () {
    fakeAsync((async) {
      final r = _Rec();
      final wd = r.make()..armStart(playing: true);
      async.elapse(const Duration(milliseconds: 9999));
      expect(r.hits, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(r.hits, [(MovaPlayFailKind.startTimeout, const Duration(seconds: 10))]);
      wd.dispose();
    });
  });

  test('onLanded before the deadline: no start failure ever', () {
    fakeAsync((async) {
      final r = _Rec();
      final wd = r.make()..armStart(playing: true);
      async.elapse(s * 3);
      wd.onLanded();
      async.elapse(s * 60);
      expect(r.hits, isEmpty);
      wd.dispose();
    });
  });

  test('armStart(playing: false) never fires; onPlaying(true) starts the clock from zero', () {
    fakeAsync((async) {
      final r = _Rec();
      final wd = r.make()..armStart(playing: false);
      async.elapse(s * 60);
      expect(r.hits, isEmpty);
      wd.onPlaying(true);
      async.elapse(const Duration(seconds: 9));
      expect(r.hits, isEmpty);
      async.elapse(s);
      expect(r.hits.single.$1, MovaPlayFailKind.startTimeout);
      wd.dispose();
    });
  });

  test('pausing while the start deadline runs cancels it', () {
    fakeAsync((async) {
      final r = _Rec();
      final wd = r.make()..armStart(playing: true);
      async.elapse(s * 5);
      wd.onPlaying(false);
      async.elapse(s * 60);
      expect(r.hits, isEmpty);
      wd.dispose();
    });
  });

  test('after landing, continuous buffering for stallTimeout fires stallTimeout', () {
    fakeAsync((async) {
      final r = _Rec();
      final wd = r.make()
        ..armStart(playing: true)
        ..onLanded()
        ..onBuffering(true);
      async.elapse(const Duration(milliseconds: 4999));
      expect(r.hits, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(r.hits, [(MovaPlayFailKind.stallTimeout, const Duration(seconds: 5))]);
      wd.dispose();
    });
  });

  test('buffering that ends before the deadline does not fire', () {
    fakeAsync((async) {
      final r = _Rec();
      final wd = r.make()
        ..armStart(playing: true)
        ..onLanded()
        ..onBuffering(true);
      async.elapse(s * 4);
      wd.onBuffering(false);
      async.elapse(s * 60);
      expect(r.hits, isEmpty);
      wd.dispose();
    });
  });

  test('stallTimeout null never reports stalls', () {
    fakeAsync((async) {
      final r = _Rec();
      final wd = r.make(stall: null)
        ..armStart(playing: true)
        ..onLanded()
        ..onBuffering(true);
      async.elapse(s * 600);
      expect(r.hits, isEmpty);
      wd.dispose();
    });
  });

  test('disarm() and dispose() stop every deadline', () {
    fakeAsync((async) {
      final r = _Rec();
      final a = r.make()..armStart(playing: true);
      a.disarm();
      final b = r.make()
        ..armStart(playing: true)
        ..onLanded()
        ..onBuffering(true);
      b.dispose();
      async.elapse(s * 600);
      expect(r.hits, isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });
}
