import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'videoman_platform_interface.dart';

/// An implementation of [VmPlatform] that uses method channels.
class MethodChannelVideoman extends VmPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('videoman');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<bool> isPipSupported() async {
    try {
      return await methodChannel.invokeMethod<bool>('isPipSupported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> enterPip({int? width, int? height}) async {
    try {
      final ok = await methodChannel.invokeMethod<bool>(
        'enterPip',
        {'width': width, 'height': height},
      );
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
