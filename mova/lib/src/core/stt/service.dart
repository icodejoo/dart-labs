import 'dart:async';

import '../model/source.dart';
import '../options/stt_config.dart';
import 'api.dart';
import 'cue.dart';

/// The production [MovaSttApi]: forwards cues from the configured
/// [MovaSttConfig.engine], tracks which cue covers the current playback
/// position, and refuses [start] with a [MovaSttBlockReason] when the feature
/// is disabled, unconfigured, or no source is open.
///
/// 生产环境的 [MovaSttApi]：转发已配置 [MovaSttConfig.engine] 产出的字幕，跟踪
/// 哪一条覆盖当前播放位置，并在功能关闭、未配置引擎或尚未打开媒体源时拒绝
/// [start] 并给出 [MovaSttBlockReason]。
class MovaSttSvc implements MovaSttApi {
  /// Creates an STT service.
  ///
  /// 创建一个 STT 服务。
  ///
  /// - [config]: the resolved STT configuration / 已解析的 STT 配置
  /// - [onBlocked]: refusal callback / 被拒回调
  MovaSttSvc({required this.config, this.onBlocked}) {
    final engine = config.engine;
    if (engine != null) {
      _cueSub = engine.cues.listen((cue) {
        _recent.add(cue);
        if (_recent.length > _maxRecent) _recent.removeAt(0);
        if (!_cues.isClosed) _cues.add(cue);
      });
    }
  }

  /// The resolved STT configuration.
  ///
  /// 已解析的 STT 配置。
  final MovaSttConfig config;

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
  final StreamController<MovaSttCue> _cues = StreamController<MovaSttCue>.broadcast();

  StreamSubscription<MovaSttCue>? _cueSub;

  /// The media currently open, or null before [attach].
  ///
  /// 当前打开的媒体；[attach] 之前为 null。
  MovaSource? _source;

  /// The last playback position reported via [updatePosition].
  ///
  /// 通过 [updatePosition] 报告的最近播放位置。
  Duration _position = Duration.zero;

  bool _started = false;

  @override
  bool get isRunning => _started;

  @override
  List<String> get languages => config.engine?.languages ?? const [];

  @override
  Stream<MovaSttCue> get cues => _cues.stream;

  @override
  MovaSttCue? get current {
    for (var i = _recent.length - 1; i >= 0; i--) {
      if (_recent[i].covers(_position)) return _recent[i];
    }
    return null;
  }

  @override
  Future<void> start() async {
    if (!config.enabled) return _blocked(MovaSttBlockReason.disabled);
    final engine = config.engine;
    if (engine == null) return _blocked(MovaSttBlockReason.noEngine);
    if (_source == null) return _blocked(MovaSttBlockReason.noSource);
    if (_started) return;
    _started = true;
    await engine.start(_position);
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await config.engine?.stop();
  }

  /// Records the media now open; called from `MovaEngine.open`.
  ///
  /// 记录当前打开的媒体；由 `MovaEngine.open` 调用。
  ///
  /// - [source]: the media now open / 当前打开的媒体
  void attach(MovaSource source) {
    _source = source;
    _recent.clear();
    _position = Duration.zero;
  }

  /// Updates the tracked playback position so [current] stays accurate;
  /// called from `MovaEngine`'s progress feed.
  ///
  /// 更新跟踪的播放位置以保持 [current] 准确；由 `MovaEngine` 的进度流调用。
  ///
  /// - [position]: the current playback position / 当前播放位置
  void updatePosition(Duration position) {
    _position = position;
  }

  void _blocked(MovaSttBlockReason reason) {
    onBlocked?.call(reason);
  }

  /// Releases resources; safe to call once during engine disposal.
  ///
  /// 释放资源；引擎销毁时调用一次即可。
  Future<void> dispose() async {
    await _cueSub?.cancel();
    await _cues.close();
    await config.engine?.dispose();
  }
}
