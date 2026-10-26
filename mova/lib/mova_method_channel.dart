import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mova_platform_interface.dart';

/// An implementation of [MovaPlatform] that uses method channels.
class MethodChannelMova extends MovaPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('mova');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  /// Broadcasts native `pipChanged` pushes; the channel handler is installed
  /// lazily on first listen so merely constructing the plugin touches nothing.
  ///
  /// 广播原生推来的 `pipChanged`；通道处理器在首次监听时才安装，构造插件本身
  /// 不碰通道。
  late final StreamController<bool> _pipChanges = StreamController<bool>.broadcast(
    onListen: () {
      methodChannel.setMethodCallHandler((call) async {
        if (call.method == 'pipChanged' && call.arguments is bool) {
          _pipChanges.add(call.arguments as bool);
        }
      });
    },
  );

  @override
  Stream<bool> get pipChanges => _pipChanges.stream;

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

  @override
  Future<double?> getSystemVolume() async {
    try {
      return await methodChannel.invokeMethod<double>('getSystemVolume');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> setSystemVolume(double percent) async {
    try {
      final ok = await methodChannel.invokeMethod<bool>(
        'setSystemVolume',
        {'percent': percent},
      );
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
