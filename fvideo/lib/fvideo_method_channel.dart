import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'fvideo_platform_interface.dart';

/// An implementation of [FvideoPlatform] that uses method channels.
class MethodChannelFvideo extends FvideoPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('fvideo');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
