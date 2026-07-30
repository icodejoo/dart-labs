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
}
