import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mova_platform_interface.dart';

/// An implementation of [MovaPlat] that uses method channels.
class MethodChannelMova extends MovaPlat {
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

  @override
  Future<bool> isPipSupported() async {
    // iOS gate (`doc/notes/2026-07-31-ios-pip-feasibility.md` §8 阶段1/阶段4/
    // SPEC 指导): the native side (`MovaPipController`, iOS 15+) can report
    // real ASBDL-PiP capability, but nothing about it has been verified on a
    // real device yet (阶段0/阶段5, both pending) — only fake test-card frames
    // have ever been wired, and never run. Keep `MovaApi.pipSupported` at
    // `false` on iOS regardless of what the native probe answers, so
    // [PipButtonComponent] keeps falling back to the in-app floating overlay
    // there until a real device confirms frame delivery, the audio session,
    // and background continuation actually work. Flip this gate (delete the
    // `Platform.isIOS` short-circuit) once that verification lands.
    //
    // iOS 网关（`doc/notes/2026-07-31-ios-pip-feasibility.md` §8 阶段1/阶段4/
    // SPEC 指导）：原生侧（`MovaPipController`，iOS 15+）能回报真实的
    // ASBDL-PiP 能力，但这一切都还没有在真机上验证过（阶段0/阶段5均待办）——
    // 目前只接好了假测试卡帧，从未真正跑过。无论原生探测回报什么，
    // `MovaApi.pipSupported` 在 iOS 上都保持 `false`，让 [PipButtonComponent]
    // 在真机验证过取帧/音频会话/后台续播确实可用之前，继续走应用内悬浮窗降级。
    // 待验证落地后翻转这道门（删掉下面 `Platform.isIOS` 的短路）。
    if (Platform.isIOS) return false;
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
