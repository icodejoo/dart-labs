import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'mova_method_channel.dart';

/// Platform contract behind mova's native features (system PiP, system
/// volume). Platform implementations extend this class and register
/// themselves through [instance]; every member has a safe default, so a
/// platform without a native side simply reports "unsupported".
///
/// mova 原生能力（系统画中画、系统音量）背后的平台契约。各平台实现继承本类，
/// 并通过 [instance] 注册；每个成员都有安全默认值，没有原生侧的平台只会回报
/// "不支持"。
abstract class MovaPlatform extends PlatformInterface {
  /// Constructs a MovaPlatform.
  ///
  /// 构造一个 MovaPlatform；子类须经此调用以通过令牌校验。
  MovaPlatform() : super(token: _token);

  /// Token that [PlatformInterface.verifyToken] checks on [instance] changes.
  ///
  /// [instance] 被替换时由 [PlatformInterface.verifyToken] 校验的令牌。
  static final Object _token = Object();

  /// Backing field of [instance].
  ///
  /// [instance] 的底层字段。
  static MovaPlatform _instance = MethodChannelMova();

  /// The default instance of [MovaPlatform] to use.
  ///
  /// Defaults to [MethodChannelMova].
  ///
  /// 当前使用的 [MovaPlatform] 实例；默认为 [MethodChannelMova]。
  static MovaPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [MovaPlatform] when
  /// they register themselves.
  ///
  /// 各平台实现在注册时，应把继承自 [MovaPlatform] 的自有类赋给它。
  static set instance(MovaPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Returns the host platform's version string, e.g. `Android 12`.
  ///
  /// 返回宿主平台的版本字符串，例如 `Android 12`。
  ///
  /// Example / 示例:
  /// ```dart
  /// final v = await MovaPlatform.instance.getPlatformVersion();
  /// ```
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Whether this platform can enter system picture-in-picture.
  ///
  /// 本平台是否支持进入系统画中画。
  ///
  /// Returns `true` when supported, `false` otherwise (the default).
  ///
  /// 支持时返回 `true`，否则返回 `false`（默认）。
  ///
  /// Example / 示例:
  /// ```dart
  /// if (await MovaPlatform.instance.isPipSupported()) { /* show the button */ }
  /// ```
  Future<bool> isPipSupported() => Future.value(false);

  /// Requests system PiP with an optional [width]/[height] aspect hint.
  /// Returns whether PiP was entered.
  ///
  /// 请求系统画中画，可选传入 [width]/[height] 作为宽高比提示。返回是否成功进入。
  ///
  /// - [width], [height]: aspect-ratio hint / 宽高比提示
  ///
  /// Example / 示例:
  /// ```dart
  /// final ok = await MovaPlatform.instance.enterPip(width: 16, height: 9);
  /// ```
  Future<bool> enterPip({int? width, int? height}) => Future.value(false);

  /// PiP mode changes pushed by the platform (`true` = entered, `false` =
  /// left). Empty on platforms without a native PiP listener.
  ///
  /// 平台主动推送的画中画状态变化（`true` 进入、`false` 退出）。无原生监听的
  /// 平台为空流。
  Stream<bool> get pipChanges => const Stream<bool>.empty();

  /// Reads the system media volume as a percentage in `[0, 100]`, or `null`
  /// when the platform has no implementation.
  ///
  /// 以 `[0, 100]` 百分比读取系统媒体音量；平台无实现时返回 `null`。
  ///
  /// Example / 示例:
  /// ```dart
  /// final percent = await MovaPlatform.instance.getSystemVolume();
  /// ```
  Future<double?> getSystemVolume() => Future.value(null);

  /// Sets the system media volume to [percent] (`[0, 100]`). Returns whether
  /// the platform applied it.
  ///
  /// 将系统媒体音量设为 [percent]（`[0, 100]`）。返回平台是否应用了该值。
  ///
  /// - [percent]: target volume in `[0, 100]` / 目标音量，取值 `[0, 100]`
  ///
  /// Example / 示例:
  /// ```dart
  /// await MovaPlatform.instance.setSystemVolume(50);
  /// ```
  Future<bool> setSystemVolume(double percent) => Future.value(false);
}
