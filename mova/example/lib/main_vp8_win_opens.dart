import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 样本地址（本机 http 服务）。
const String base = String.fromEnvironment('BASE', defaultValue: 'http://127.0.0.1:18090');

/// 入口：纯 media_kit 在 Windows 上播 vp8，统计每轮 "Opening decoder" 次数。
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    MediaKit.ensureInitialized();
    final screen = ValueNotifier<Widget?>(null);
    runApp(MaterialApp(home: Scaffold(body: ValueListenableBuilder<Widget?>(valueListenable: screen, builder: (_, w, c) => w ?? const SizedBox()))));
    await WidgetsBinding.instance.endOfFrame;
    for (final f in ['vp8.webm', 'h264.mp4']) {
      for (var r = 0; r < 4; r++) {
        final p = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.v));
        var opens = 0;
        p.stream.log.listen((l) {
          if (l.prefix == 'vd' && l.text.contains('Opening decoder')) opens++;
        });
        final c = VideoController(p);
        screen.value = Video(controller: c, controls: NoVideoControls);
        await WidgetsBinding.instance.endOfFrame;
        await p.open(Media('$base/$f?t=${DateTime.now().millisecondsSinceEpoch}'));
        await Future<void>.delayed(const Duration(seconds: 4));
        stdout.writeln('WINOPENS|$f|run$r|opens=$opens|pos=${p.state.position.inMilliseconds}|size=${p.state.width}x${p.state.height}');
        screen.value = null;
        await WidgetsBinding.instance.endOfFrame;
        await p.dispose();
      }
    }
    stdout.writeln('WINOPENS|DONE');
    exit(0);
  }, (e, s) => stdout.writeln('WINOPENS|ERR|$e'));
}
