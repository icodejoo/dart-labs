import 'engine.dart';
import 'model/quality.dart';
import 'model/source.dart';

/// Deprecated 0.1.0-compatible facade wrapping a [VmEngine].
///
/// This is a compatibility shim only: it forwards every call to the
/// [engine] it wraps and carries no state of its own. Use [VmEngine] (or the
/// higher-level `VmPlayer` widget) directly instead; this class is removed
/// in 0.3.0.
///
/// 兼容 0.1.0 的已弃用门面，包装一个 [VmEngine]。
///
/// 这只是一个兼容层：把每次调用转发给它包装的 [engine]，自身不持有任何状态。
/// 请直接使用 [VmEngine]（或更高层的 `VmPlayer` 组件）；该类将在 0.3.0 移除。
@Deprecated('Use VmEngine instead. 0.3.0 移除。')
class VmController {
  /// The engine this controller forwards every call to.
  ///
  /// 该控制器转发所有调用的目标 engine。
  final VmEngine engine;

  /// Creates a controller wrapping [engine] (defaults to a new [VmEngine]).
  ///
  /// 创建一个包装 [engine] 的控制器（省略时默认新建一个 [VmEngine]）。
  VmController({VmEngine? engine}) : engine = engine ?? VmEngine();

  /// Forwards to [VmEngine.open].
  ///
  /// 转发到 [VmEngine.open]。
  Future<void> open(VmSource source, {bool autoPlay = true}) =>
      engine.open(source, autoPlay: autoPlay);

  /// Forwards to [VmEngine.play].
  ///
  /// 转发到 [VmEngine.play]。
  Future<void> play() => engine.play();

  /// Forwards to [VmEngine.pause].
  ///
  /// 转发到 [VmEngine.pause]。
  Future<void> pause() => engine.pause();

  /// Forwards to [VmEngine.playOrPause].
  ///
  /// 转发到 [VmEngine.playOrPause]。
  Future<void> playOrPause() => engine.playOrPause();

  /// Forwards to [VmEngine.seek].
  ///
  /// 转发到 [VmEngine.seek]。
  Future<void> seek(Duration to) => engine.seek(to);

  /// Forwards to [VmEngine.setVolume].
  ///
  /// 转发到 [VmEngine.setVolume]。
  Future<void> setVolume(double v) => engine.setVolume(v);

  /// Forwards to [VmEngine.setRate].
  ///
  /// 转发到 [VmEngine.setRate]。
  Future<void> setRate(double r) => engine.setRate(r);

  /// Forwards to [VmEngine.loadQualities].
  ///
  /// 转发到 [VmEngine.loadQualities]。
  Future<void> loadQualities() => engine.loadQualities();

  /// Forwards to [VmEngine.switchQuality].
  ///
  /// 转发到 [VmEngine.switchQuality]。
  Future<void> switchQuality(VmQuality q) => engine.switchQuality(q);

  /// Forwards to [VmEngine.reload].
  ///
  /// 转发到 [VmEngine.reload]。
  Future<void> reload() => engine.reload();

  /// Forwards to [VmEngine.enterPip].
  ///
  /// The old 0.1.0 `isPipSupported()` probe has no equivalent on [VmApi] —
  /// callers should call [enterPip] directly and check its returned
  /// success flag instead of probing support beforehand.
  ///
  /// 转发到 [VmEngine.enterPip]。
  ///
  /// 旧版 0.1.0 的 `isPipSupported()` 探测方法在 [VmApi] 上没有对应实现——
  /// 调用方应直接调用 [enterPip] 并检查其返回的成功标志，而不是事先探测是否支持。
  Future<bool> enterPip() => engine.enterPip();

  /// Forwards to [VmEngine.dispose].
  ///
  /// 转发到 [VmEngine.dispose]。
  Future<void> dispose() => engine.dispose();
}
