import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'fvideo_method_channel.dart';

abstract class FvideoPlatform extends PlatformInterface {
  /// Constructs a FvideoPlatform.
  FvideoPlatform() : super(token: _token);

  static final Object _token = Object();

  static FvideoPlatform _instance = MethodChannelFvideo();

  /// The default instance of [FvideoPlatform] to use.
  ///
  /// Defaults to [MethodChannelFvideo].
  static FvideoPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FvideoPlatform] when
  /// they register themselves.
  static set instance(FvideoPlatform instance) {
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
}
