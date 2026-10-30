import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 样本服务地址（adb reverse）。
const String base = String.fromEnvironment('BASE', defaultValue: 'http://127.0.0.1:18090');

/// 控件尺寸（null 表示铺满），用来模拟小窗。
final box = ValueNotifier<Size?>(null);

/// 转屏、小窗切换时统计解码器重开次数与是否持续出画。
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    MediaKit.ensureInitialized();
    final player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.v));
    var opens = 0;
    player.stream.log.listen((l) {
      if (l.prefix == 'vd' && l.text.contains('Opening decoder')) opens++;
    });
    final controller = VideoController(player);
    runApp(MaterialApp(
        home: Scaffold(
            backgroundColor: Colors.black,
            body: Align(
                alignment: Alignment.topLeft,
                child: ValueListenableBuilder<Size?>(
                    valueListenable: box,
                    builder: (_, s, c) => SizedBox(
                        width: s?.width ?? double.infinity,
                        height: s?.height ?? double.infinity,
                        child: Video(controller: controller, controls: NoVideoControls)))))));
    await Future<void>.delayed(const Duration(seconds: 2));
    await (player.platform as NativePlayer).setProperty('vd-lavc-o', 'ndk_codec=1');
    await player.setPlaylistMode(PlaylistMode.single);
    await player.open(Media('$base/vp8.webm'), play: true);
    Future<void> step(String name, Future<void> Function() act) async {
      await act();
      await Future<void>.delayed(const Duration(seconds: 3));
      final p0 = player.state.position.inMilliseconds;
      await Future<void>.delayed(const Duration(seconds: 1));
      final p1 = player.state.position.inMilliseconds;
      // ignore: avoid_print
      print('SHOTMARK|$name|opens=$opens|advance=${p1 - p0}ms|size=${player.state.width}x${player.state.height}');
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await step('s0_start', () async {});
    await step('s1_small', () async => box.value = const Size(240, 135));
    await step('s2_small_other', () async => box.value = const Size(320, 240));
    await step('s3_full', () async => box.value = null);
    await step('s4_landscape', () => SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]));
    await step('s5_small_in_land', () async => box.value = const Size(240, 135));
    await step('s6_full_land', () async => box.value = null);
    await step('s7_portrait', () => SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]));
    // ignore: avoid_print
    print('SHOTMARK|DONE');
  }, (e, s) => print('SHOTMARK|ERR|$e'));
}
