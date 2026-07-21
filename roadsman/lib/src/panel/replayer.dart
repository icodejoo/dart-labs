/// Replay: a `Timer` drives round-by-round playback through the `store.append`
/// path, so insert animations and viewport follow all kick in naturally
/// (this isn't a separate rendering path — it's just "auto-append at the
/// right time for you").
///
/// Ported from `src/panel/replayer.ts`.
library;

import 'dart:async';

import '../core/store.dart';
import '../core/types.dart';

/// Replay state.
enum ReplayState { idle, playing, paused }

/// Replay options.
class ReplayOptions {
  /// Interval between rounds (ms), defaults to 800ms.
  final int intervalMs;

  const ReplayOptions({this.intervalMs = 800});
}

/// Replay progress.
class ReplayProgress {
  /// Number of rounds played so far (0-based).
  final int current;

  /// Total number of rounds.
  final int total;

  const ReplayProgress({required this.current, required this.total});
}

/// Drives the replay.
class Replayer {
  final List<RawResult> _fullResults;
  final RoadmapStore _store;
  final int _intervalMs;

  Timer? _timer;
  int _cursor = 0;
  ReplayState _state = ReplayState.idle;

  Replayer(this._fullResults, this._store, {ReplayOptions opts = const ReplayOptions()})
    : _intervalMs = opts.intervalMs;

  /// Current replay state.
  ReplayState get state => _state;

  /// Current progress.
  ReplayProgress get progress => ReplayProgress(current: _cursor, total: _fullResults.length);

  /// Resumes playback from the current position, calling `store.append` round by round.
  void play() {
    if (_state == ReplayState.playing) return;
    _state = ReplayState.playing;
    _timer = Timer.periodic(Duration(milliseconds: _intervalMs), (_) {
      if (_cursor >= _fullResults.length) {
        pause();
        return;
      }
      _store.append(_fullResults[_cursor]);
      _cursor++;
    });
  }

  /// Pauses playback (keeps the current progress; resume with [play]).
  void pause() {
    _timer?.cancel();
    _timer = null;
    if (_state == ReplayState.playing) _state = ReplayState.paused;
  }

  /// Jumps to round [no] (no animation played, goes straight through `setResults`).
  void seek(int no) {
    final idx = _fullResults.indexWhere((r) => r.no == no);
    if (idx == -1) return;
    _cursor = idx + 1;
    _store.setResults(_fullResults.sublist(0, _cursor));
  }

  /// Stops the replay and restores the full shoe data.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _state = ReplayState.idle;
    _cursor = 0;
    _store.setResults(_fullResults);
  }
}

/// Creates a replayer that calls `store.append` round by round at
/// [opts.intervalMs] intervals.
///
/// ```dart
/// final replayer = createReplayer(shoe.results, store, opts: const ReplayOptions(intervalMs: 500));
/// replayer.play();
/// ```
Replayer createReplayer(List<RawResult> fullResults, RoadmapStore store, {ReplayOptions opts = const ReplayOptions()}) =>
    Replayer(fullResults, store, opts: opts);
