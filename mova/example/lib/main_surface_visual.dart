import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 样本服务地址（adb reverse）。
const String base = String.fromEnvironment('BASE', defaultValue: 'http://127.0.0.1:18090');

/// 逐个样本定格一帧，输出 SHOT 标记供宿主截图。
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    MediaKit.ensureInitialized();
    final player = Player();
    final controller = VideoController(player);
    runApp(MaterialApp(home: Scaffold(backgroundColor: Colors.black, body: Center(child: Video(controller: controller, controls: NoVideoControls)))));
    await Future<void>.delayed(const Duration(seconds: 2));
    await (player.platform as NativePlayer).setProperty('vd-lavc-o', 'ndk_codec=1');
    for (final f in ['ts_1280x720', 'ts_640x480', 'ts_360x640', 'ts_1920x1080']) {
      await player.open(Media('$base/$f.webm'), play: true);
      await Future<void>.delayed(const Duration(seconds: 2));
      await player.pause();
      await player.seek(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(seconds: 2));
      // ignore: avoid_print
      print('SHOTMARK|$f');
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    // ignore: avoid_print
    print('SHOTMARK|DONE');
  }, (e, s) => print('SHOTMARK|ERR|$e'));
}
