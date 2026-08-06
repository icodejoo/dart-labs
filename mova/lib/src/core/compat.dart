import 'engine.dart';
import 'model/quality.dart';
import 'model/source.dart';

/// Deprecated 0.1.0-compatible facade wrapping a [MovaEngine].
///
/// This is a compatibility shim only: it forwards every call to the
/// [engine] it wraps and carries no state of its own. Use [MovaEngine] (or the
/// higher-level `MovaPlayer` widget) directly instead; this class is removed
/// in 0.3.0.
///
/// 兼容 0.1.0 的已弃用门面，包装一个 [MovaEngine]。
///
/// 这只是一个兼容层：把每次调用转发给它包装的 [engine]，自身不持有任何状态。
/// 请直接使用 [MovaEngine]（或更高层的 `MovaPlayer` 组件）；该类将在 0.3.0 移除。
@Deprecated('Use MovaEngine instead. 0.3.0 移除。')
class MovaCtrl {
  /// The engine this controller forwards every call to.
  ///
  /// 该控制器转发所有调用的目标 engine。
  final MovaEngine engine;

  /// Creates a controller wrapping [engine] (defaults to a new [MovaEngine]).
  ///
  /// 创建一个包装 [engine] 的控制器（省略时默认新建一个 [MovaEngine]）。
  MovaCtrl({MovaEngine? engine}) : engine = engine ?? MovaEngine();

  /// Forwards to [MovaEngine.open].
  ///
  /// 转发到 [MovaEngine.open]。
  Future<void> open(MovaSource source, {bool autoPlay = true}) =>
      engine.open(source, autoPlay: autoPlay);

  /// Forwards to [MovaEngine.play].
  ///
  /// 转发到 [MovaEngine.play]。
  Future<void> play() => engine.play();

  /// Forwards to [MovaEngine.pause].
  ///
  /// 转发到 [MovaEngine.pause]。
  Future<void> pause() => engine.pause();

  /// Forwards to [MovaEngine.playOrPause].
  ///
  /// 转发到 [MovaEngine.playOrPause]。
  Future<void> playOrPause() => engine.playOrPause();

  /// Forwards to [MovaEngine.seek].
  ///
  /// 转发到 [MovaEngine.seek]。
  Future<void> seek(Duration to) => engine.seek(to);

  /// Forwards to [MovaEngine.setVolume].
  ///
  /// 转发到 [MovaEngine.setVolume]。
  Future<void> setVolume(double v) => engine.setVolume(v);

  /// Forwards to [MovaEngine.setRate].
  ///
  /// 转发到 [MovaEngine.setRate]。
  Future<void> setRate(double r) => engine.setRate(r);

  /// Forwards to [MovaEngine.loadQualities].
  ///
  /// 转发到 [MovaEngine.loadQualities]。
  Future<void> loadQualities() => engine.loadQualities();

  /// Forwards to [MovaEngine.switchQuality].
  ///
  /// 转发到 [MovaEngine.switchQuality]。
  Future<void> switchQuality(MovaQual q) => engine.switchQuality(q);

  /// Forwards to [MovaEngine.reload].
  ///
  /// 转发到 [MovaEngine.reload]。
  Future<void> reload() => engine.reload();

  /// Forwards to [MovaEngine.enterPip].
  ///
  /// The old 0.1.0 `isPipSupported()` probe has no equivalent on [MovaApi] —
  /// callers should call [enterPip] directly and check its returned
  /// success flag instead of probing support beforehand.
  ///
  /// 转发到 [MovaEngine.enterPip]。
  ///
  /// 旧版 0.1.0 的 `isPipSupported()` 探测方法在 [MovaApi] 上没有对应实现——
  /// 调用方应直接调用 [enterPip] 并检查其返回的成功标志，而不是事先探测是否支持。
  Future<bool> enterPip() => engine.enterPip();

  /// Forwards to [MovaEngine.dispose].
  ///
  /// 转发到 [MovaEngine.dispose]。
  Future<void> dispose() => engine.dispose();
}
