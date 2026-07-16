/// 回放：`Timer` 驱动逐局回放，走 `store.append` 路径，插入动画/视口跟随全部
/// 自然生效（不是另起一套渲染逻辑，只是"自动帮你按时间点 append"）。
///
/// 移植自 `src/panel/replayer.ts`。
library;

import 'dart:async';

import '../core/store.dart';
import '../core/types.dart';

/// 回放状态。
enum ReplayState { idle, playing, paused }

/// 回放选项。
class ReplayOptions {
  /// 每局播放间隔（ms），默认 800ms。
  final int intervalMs;

  const ReplayOptions({this.intervalMs = 800});
}

/// 回放进度。
class ReplayProgress {
  /// 当前已播放到第几局（0-based）。
  final int current;

  /// 总局数。
  final int total;

  const ReplayProgress({required this.current, required this.total});
}

/// 回放驱动。
class Replayer {
  final List<RawResult> _fullResults;
  final RoadmapStore _store;
  final int _intervalMs;

  Timer? _timer;
  int _cursor = 0;
  ReplayState _state = ReplayState.idle;

  Replayer(this._fullResults, this._store, {ReplayOptions opts = const ReplayOptions()})
    : _intervalMs = opts.intervalMs;

  /// 当前回放状态。
  ReplayState get state => _state;

  /// 当前进度。
  ReplayProgress get progress => ReplayProgress(current: _cursor, total: _fullResults.length);

  /// 从当前位置继续播放，逐局调用 `store.append`。
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

  /// 暂停播放（保留当前进度，可用 [play] 续播）。
  void pause() {
    _timer?.cancel();
    _timer = null;
    if (_state == ReplayState.playing) _state = ReplayState.paused;
  }

  /// 跳转到第 [no] 局（不播动画，直接走 `setResults`）。
  void seek(int no) {
    final idx = _fullResults.indexWhere((r) => r.no == no);
    if (idx == -1) return;
    _cursor = idx + 1;
    _store.setResults(_fullResults.sublist(0, _cursor));
  }

  /// 停止回放，恢复完整靴数据。
  void stop() {
    _timer?.cancel();
    _timer = null;
    _state = ReplayState.idle;
    _cursor = 0;
    _store.setResults(_fullResults);
  }
}

/// 创建一个回放驱动，逐局按 [opts.intervalMs] 间隔调用 `store.append`。
///
/// ```dart
/// final replayer = createReplayer(shoe.results, store, opts: const ReplayOptions(intervalMs: 500));
/// replayer.play();
/// ```
Replayer createReplayer(List<RawResult> fullResults, RoadmapStore store, {ReplayOptions opts = const ReplayOptions()}) =>
    Replayer(fullResults, store, opts: opts);
