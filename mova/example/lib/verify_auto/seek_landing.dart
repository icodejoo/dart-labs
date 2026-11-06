/// Reject transient mpv time-pos echoes while a reload/seek is still settling.
class SeekLanding {
  SeekLanding(this.targetMs, {this.stableMs = 400, this.playing = false});

  final int targetMs;
  final int stableMs;
  final bool playing;
  int? _sinceMs;
  int? landedMs;

  bool sample({
    required int elapsedMs,
    required int positionMs,
    required bool seeking,
    required bool buffering,
    required bool pathMatches,
  }) {
    final since = _sinceMs;
    final expected = since == null
        ? targetMs
        : landedMs! + (playing ? elapsedMs - since : 0);
    if (seeking ||
        !pathMatches ||
        (positionMs - expected).abs() > 500) {
      _sinceMs = null;
      landedMs = null;
      return false;
    }
    if (_sinceMs == null) {
      _sinceMs = elapsedMs;
      landedMs = positionMs;
    }
    // UI buffering can lag native seeking=no. Preserve that first native
    // landing, but require buffering to clear before accepting the window.
    return !buffering && elapsedMs - _sinceMs! >= stableMs;
  }
}
