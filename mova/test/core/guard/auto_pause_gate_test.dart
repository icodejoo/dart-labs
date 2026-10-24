import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/guard/auto_pause.dart';

final _t0 = DateTime(2026, 10, 23, 12);

/// Drives one reason on/off with sensible defaults.
///
/// 用合理的默认值驱动某个原因的开/关。
MovaGuardAction _set(
  MovaAutoPauseGate g,
  MovaHideReason r,
  bool active, {
  bool playing = true,
  bool live = false,
  bool exempt = false,
  Duration at = Duration.zero,
}) =>
    g.update(r, active, playing: playing, live: live, exempt: exempt, now: _t0.add(at));

void main() {
  const off = MovaHideReason.offscreen;

  test('1. hiding while playing pauses; hiding while not playing does nothing', () {
    expect(_set(MovaAutoPauseGate(const MovaAutoPauseConfig()), off, true), MovaGuardAction.pause);
    expect(_set(MovaAutoPauseGate(const MovaAutoPauseConfig()), off, true, playing: false), MovaGuardAction.none);
  });

  test('2. showing again resumes only if it was playing before hiding', () {
    final g = MovaAutoPauseGate(const MovaAutoPauseConfig());
    _set(g, off, true);
    expect(_set(g, off, false, playing: false), MovaGuardAction.resume);

    final idle = MovaAutoPauseGate(const MovaAutoPauseConfig());
    _set(idle, off, true, playing: false);
    expect(_set(idle, off, false, playing: false), MovaGuardAction.none);
  });

  test('3. stacked reasons: dropping one stays hidden, dropping the last resumes', () {
    final g = MovaAutoPauseGate(const MovaAutoPauseConfig());
    expect(_set(g, off, true), MovaGuardAction.pause);
    expect(_set(g, MovaHideReason.routeCovered, true, playing: false), MovaGuardAction.none);
    expect(g.reasons, {off, MovaHideReason.routeCovered});
    expect(_set(g, off, false, playing: false), MovaGuardAction.none);
    expect(g.hidden, isTrue);
    expect(_set(g, MovaHideReason.routeCovered, false, playing: false), MovaGuardAction.resume);
    expect(g.hidden, isFalse);
  });

  test('4. exempt (pip / mini): neither pauses on hide nor resumes on show', () {
    final g = MovaAutoPauseGate(const MovaAutoPauseConfig());
    expect(_set(g, MovaHideReason.background, true, exempt: true), MovaGuardAction.none);
    expect(_set(g, MovaHideReason.background, false, exempt: true), MovaGuardAction.none);
  });

  test('5. resumeOnShow:false pauses but never resumes', () {
    final g = MovaAutoPauseGate(const MovaAutoPauseConfig(resumeOnShow: false));
    expect(_set(g, off, true), MovaGuardAction.pause);
    expect(_set(g, off, false, playing: false), MovaGuardAction.none);
  });

  test('6. live + reloadEdge + hidden at least the grace period reloads the edge', () {
    final g = MovaAutoPauseGate(const MovaAutoPauseConfig());
    _set(g, off, true, live: true);
    expect(_set(g, off, false, live: true, playing: false, at: const Duration(seconds: 3)), MovaGuardAction.reloadEdge);
  });

  test('7. live hidden for less than the grace period just resumes', () {
    final g = MovaAutoPauseGate(const MovaAutoPauseConfig());
    _set(g, off, true, live: true);
    expect(_set(g, off, false, live: true, playing: false, at: const Duration(milliseconds: 2999)), MovaGuardAction.resume);
  });

  test('8. MovaLiveResume.resume and VOD always resume plainly', () {
    final live = MovaAutoPauseGate(const MovaAutoPauseConfig(liveResume: MovaLiveResume.resume));
    _set(live, off, true, live: true);
    expect(_set(live, off, false, live: true, playing: false, at: const Duration(minutes: 5)), MovaGuardAction.resume);

    final vod = MovaAutoPauseGate(const MovaAutoPauseConfig());
    _set(vod, off, true);
    expect(_set(vod, off, false, playing: false, at: const Duration(minutes: 5)), MovaGuardAction.resume);
  });

  test('9. the inactive snapshot survives the system pausing the player before hidden arrives', () {
    final g = MovaAutoPauseGate(const MovaAutoPauseConfig());
    g.onInactive(playing: true);
    // By the time `hidden` lands, Android has already paused libmpv.
    _set(g, MovaHideReason.background, true, playing: false);
    expect(_set(g, MovaHideReason.background, false, playing: false), MovaGuardAction.resume);
  });

  test('10. inactive then resumed without hiding clears the snapshot', () {
    final g = MovaAutoPauseGate(const MovaAutoPauseConfig());
    g.onInactive(playing: true);
    g.onResumed();
    // A later hide (the user had since paused) must not borrow the stale snapshot.
    expect(_set(g, MovaHideReason.background, true, playing: false), MovaGuardAction.none);
    expect(_set(g, MovaHideReason.background, false, playing: false), MovaGuardAction.none);
  });

  test('11. a disabled kind is ignored entirely: offscreen with viewport:false never hides', () {
    final g = MovaAutoPauseGate(const MovaAutoPauseConfig(viewport: false));
    expect(_set(g, off, true), MovaGuardAction.none);
    expect(g.hidden, isFalse);
    expect(g.reasons, isEmpty);
  });

  test('12. setting or clearing the same reason twice is idempotent', () {
    final g = MovaAutoPauseGate(const MovaAutoPauseConfig());
    expect(_set(g, off, false), MovaGuardAction.none);
    expect(_set(g, off, true), MovaGuardAction.pause);
    expect(_set(g, off, true), MovaGuardAction.none);
    expect(_set(g, off, false, playing: false), MovaGuardAction.resume);
    expect(_set(g, off, false, playing: false), MovaGuardAction.none);
  });
}
