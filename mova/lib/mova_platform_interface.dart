import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'mova_method_channel.dart';

abstract class MovaPlat extends PlatformInterface {
  /// Constructs a MovaPlat.
  MovaPlat() : super(token: _token);

  static final Object _token = Object();

  static MovaPlat _instance = MethodChannelMova();

  /// The default instance of [MovaPlat] to use.
  ///
  /// Defaults to [MethodChannelMova].
  static MovaPlat get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [MovaPlat] when
  /// they register themselves.
  static set instance(MovaPlat instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Whether this platform can enter system picture-in-picture.
  ///
  /// 本平台是否支持进入系统画中画。
  Future<bool> isPipSupported() => Future.value(false);

  /// Requests system PiP with an optional [width]/[height] aspect hint.
  /// Returns whether PiP was entered.
  ///
  /// 请求系统画中画，可选传入 [width]/[height] 作为宽高比提示。返回是否成功进入。
  Future<bool> enterPip({int? width, int? height}) => Future.value(false);

  /// Reads the system media volume as a percentage in `[0, 100]`, or `null`
  /// when the platform has no implementation.
  ///
  /// 以 `[0, 100]` 百分比读取系统媒体音量；平台无实现时返回 `null`。
  Future<double?> getSystemVolume() => Future.value(null);

  /// Sets the system media volume to [percent] (`[0, 100]`). Returns whether
  /// the platform applied it.
  ///
  /// 将系统媒体音量设为 [percent]（`[0, 100]`）。返回平台是否应用了该值。
  Future<bool> setSystemVolume(double percent) => Future.value(false);
}
