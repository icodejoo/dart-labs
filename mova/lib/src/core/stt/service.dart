import 'dart:async';

import '../model/source.dart';
import '../options/stt_opts.dart';
import 'api.dart';
import 'cue.dart';
import 'stt.dart';

/// The production [IMovaSttApi]: forwards cues from the configured
/// [MovaSttOpts.recognizer], tracks which cue covers the current playback
/// position, and refuses [start] with a [MovaSttBlockReason] when the feature
/// is disabled, unconfigured, or no source is open.
///
/// 生产环境的 [IMovaSttApi]：转发已配置 [MovaSttOpts.recognizer] 产出的字幕，跟踪
/// 哪一条覆盖当前播放位置，并在功能关闭、未配置识别器或尚未打开媒体源时拒绝
/// [start] 并给出 [MovaSttBlockReason]。
class MovaSttService implements IMovaSttApi {
  /// Creates an STT service.
  ///
  /// 创建一个 STT 服务。
  ///
  /// - [opts]: the resolved STT options / 已解析的 STT 配置
  /// - [onBlocked]: refusal callback / 被拒回调
  MovaSttService({
    required this.opts,
    this.onBlocked,
    this.audioOnly = false,
  }) {
    final recognizer = opts.recognizer;
    if (recognizer != null && !audioOnly) {
      _cueSub = recognizer.cues.listen((cue) {
        if (_disposed || _source == null) return;
        if (cue.sessionEpoch != null) {
          if (cue.sessionEpoch != _sessionEpoch) return;
        } else if (_sessionEpoch > 1) {
          // 换源后的无标记结果无法证明归属，宁可丢弃也不污染新内容。
          return;
        }
        _recent.add(cue);
        if (_recent.length > _maxRecent) _recent.removeAt(0);
        if (!_cues.isClosed) _cues.add(cue);
      });
    }
  }

  /// 仅音频播放器禁止启动识别；示例：`MovaSttService(opts: opts, audioOnly: true)`。
  final bool audioOnly;

  /// 每次 attach 递增，识别结果必须归属当前代际。
  int _sessionEpoch = 0;

  /// 资源释放后拒绝迟到结果。
  bool _disposed = false;

  /// The resolved STT options.
  ///
  /// 已解析的 STT 配置。
  final MovaSttOpts opts;

  /// Called whenever [start] is refused; null means stay silent.
  ///
  /// [start] 被拒绝时的回调；为 null 表示静默。
  final void Function(MovaSttBlockReason reason)? onBlocked;

  /// How many recognized cues to retain for [current] lookups.
  ///
  /// 为支持 [current] 查询而保留的最近字幕条数。
  static const _maxRecent = 50;

  /// Recently recognized cues, oldest first, capped at [_maxRecent].
  ///
  /// 最近识别出的字幕，从旧到新，上限为 [_maxRecent]。
  final List<MovaSttCue> _recent = [];

  /// Broadcast sink for [cues].
  ///
  /// [cues] 的广播出口。
  final StreamController<MovaSttCue> _cues =
      StreamController<MovaSttCue>.broadcast();

  /// 当前识别器的字幕订阅。
  StreamSubscription<MovaSttCue>? _cueSub;

  /// The media currently open, or null before [attach].
  ///
  /// 当前打开的媒体；[attach] 之前为 null。
  MovaSource? _source;

  /// The last playback position reported via [updatePosition].
  ///
  /// 通过 [updatePosition] 报告的最近播放位置。
  Duration _position = Duration.zero;

  /// 宿主的识别启用状态；换源不重置。
  bool _started = false;

  /// Identifies the latest start/stop intent for asynchronous rollback.
  ///
  /// 标识最新启停意图，防止异步失败回滚覆盖新状态。
  int _runEpoch = 0;

  @override
  bool get isRunning => _started;

  @override
  List<String> get languages => opts.recognizer?.languages ?? const [];

  @override
  Stream<MovaSttCue> get cues => _cues.stream;

  @override
  MovaSttCue? get current {
    for (var i = _recent.length - 1; i >= 0; i--) {
      if (_recent[i].covers(_position)) return _recent[i];
    }
    return null;
  }

  bool _warnedNoRecognizer = false;

  @override
  Future<void> start() async {
    if (_disposed) return;
    if (audioOnly || !opts.enabled) {
      return _blocked(MovaSttBlockReason.disabled);
    }
    final recognizer = opts.recognizer;
    if (recognizer == null) {
      assert(() {
        if (!_warnedNoRecognizer) {
          _warnedNoRecognizer = true;
          // ignore: avoid_print
          print('STT 未配置 stt.recognizer；可读取 options.stt.hasRecognizer。');
        }
        return true;
      }());
      return _blocked(MovaSttBlockReason.noRecognizer);
    }
    if (_source == null) return _blocked(MovaSttBlockReason.noSource);
    if (_started) return;
    _started = true;
    final epoch = ++_runEpoch;
    try {
      await recognizer.start(_position);
    } catch (_) {
      // Roll back so a failed start can be retried without a stop() first.
      //
      // 回滚，使失败的 start 可直接重试，不必先 stop()。
      if (!_disposed && epoch == _runEpoch) _started = false;
      // 失败只回滚状态，宿主可以再次 start；不把识别异常泄漏到播放调用链。
    }
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    _runEpoch++;
    _started = false;
    await opts.recognizer?.stop();
  }

  /// Records the media now open; called from `Mova.open`.
  ///
  /// 记录当前打开的媒体；由 `Mova.open` 调用。
  ///
  /// - [source]: the media now open / 当前打开的媒体
  /// 换源后识别保持开启，不改变 isRunning、不调用 stop。
  /// 新识别器应实现 IMovaSttSession 并给 cue 带 sessionEpoch；
  /// 旧识别器的无标记 cue 仅兼容首源，后续换源时过滤以免串字幕。
  /// 无返回值；示例：`service.attach(MovaSource('https://host/b.mp4'))`。
  void attach(MovaSource source) {
    if (_disposed) return;
    _sessionEpoch++;
    _source = source;
    _recent.clear();
    _position = Duration.zero;
    final recognizer = opts.recognizer;
    if (!audioOnly && recognizer is IMovaSttSession) {
      (recognizer as IMovaSttSession).bindSession(_sessionEpoch);
    }
  }

  /// Updates the tracked playback position so [current] stays accurate;
  /// called from `Mova`'s progress feed.
  ///
  /// 更新跟踪的播放位置以保持 [current] 准确；由 `Mova` 的进度流调用。
  ///
  /// - [position]: the current playback position / 当前播放位置
  void updatePosition(Duration position) {
    _position = position;
  }

  /// 通知宿主当前启动请求被拒绝。
  void _blocked(MovaSttBlockReason reason) {
    onBlocked?.call(reason);
  }

  /// Releases resources; safe to call once during player disposal.
  ///
  /// 释放本服务的订阅与字幕流，不销毁宿主注入的识别器；重复调用安全。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _started = false;
    await _cueSub?.cancel();
    await _cues.close();
    // 识别器由宿主注入并持有，服务只释放自己的订阅。
  }
}
