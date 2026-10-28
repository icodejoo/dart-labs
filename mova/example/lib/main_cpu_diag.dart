// 诊断页：定位视频播放 CPU 占用的来源（软解/渲染/mova 自身开销）。
// 只做对照测量，不属于任何验收用例；用完即可删除。
// Diagnostic page: attribute playback CPU to decode / render / mova overhead.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mova/mova.dart';
// ignore: implementation_imports
import 'package:mova/src/core/kernel/mpv_kernel.dart';
// ignore: implementation_imports
import 'package:mova/src/platform_impl/frame_yield.dart';

/// 当前挂载的小部件；为空时显示占位文字。
final _surface = ValueNotifier<Widget?>(null);

Player? _player;
MovaEngine? _engine;
String _mode = '';

/// 探测用的 mpv 属性清单。
const _probeKeys = [
  'hwdec',
  'hwdec-current',
  'hwdec-interop',
  'current-vo',
  'video-format',
  'video-codec',
  'vd-lavc-threads',
  'video-params/hw-pixelformat',
  'video-params/pixelformat',
  'video-params/w',
  'video-params/h',
  'estimated-vf-fps',
  'container-fps',
  'frame-drop-count',
  'decoder-frame-drop-count',
  'vo-delayed-frame-count',
  'time-pos',
  'vid',
];

/// 释放上一轮播放资源。
Future<void> _stop() async {
  _surface.value = null;
  await WidgetsBinding.instance.endOfFrame;
  try {
    await _engine?.dispose();
  } catch (_) {}
  try {
    await _player?.dispose();
  } catch (_) {}
  _engine = null;
  _player = null;
  _mode = '';
}

/// 按模式开始播放。
Future<void> _run(Map<String, dynamic> a) async {
  await _stop();
  final mode = a['mode'] as String;
  final url = a['url'] as String;
  final props = <String, String>{
    for (final e in ((a['props'] as Map?) ?? {}).entries)
      '${e.key}': '${e.value}',
  };
  _mode = mode;
  if (mode == 'mk' || mode == 'mk_novid') {
    final p = Player();
    _player = p;
    for (final e in props.entries) {
      if (e.key == 'hwdec') continue; // 由 VideoController 配置接管
      await (p.platform as NativePlayer).setProperty(e.key, e.value);
    }
    if (mode == 'mk') {
      final c = VideoController(
        p,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: props['hwdec'] != 'no',
        ),
      );
      _surface.value = Video(controller: c, controls: NoVideoControls);
      await WidgetsBinding.instance.endOfFrame;
    }
    await p.open(Media(url));
    return;
  }
  // mova 系列：注入内核以便读回 native 属性，其余走生产装配。
  final p = Player();
  _player = p;
  final kernel = MovaMpvKernel(
    player: p,
    lazyVideo: true,
    mountYield: movaFrameYield,
  );
  final engine = createMovaEngine(kernel: kernel);
  _engine = engine;
  if (mode != 'mova_nomount') {
    _surface.value = MovaPlayer(
      key: ObjectKey(engine),
      api: engine,
      skin: mode == 'mova_min' ? const MovaMinimalSkin() : const MovaDefaultSkin(),
    );
    await WidgetsBinding.instance.endOfFrame;
  }
  await engine.open(
    MovaSource(url, type: MovaStreamType.vod, mpvOptions: props),
  );
}

/// 读回 mpv 属性。
Future<Map<String, Object?>> _probe() async {
  final n = _player?.platform as NativePlayer?;
  final out = <String, Object?>{'mode': _mode};
  if (n == null) return out;
  for (final k in _probeKeys) {
    try {
      out[k] = await n.getProperty(k).timeout(const Duration(seconds: 3));
    } catch (e) {
      out[k] = 'ERR';
    }
  }
  return out;
}

Future<void> _serve() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18089);
  await for (final r in server) {
    r.response.headers.contentType = ContentType.json;
    try {
      Object? body = {'pid': pid, 'mode': _mode};
      if (r.uri.path == '/run') {
        final args =
            jsonDecode(await utf8.decoder.bind(r).join())
                as Map<String, dynamic>;
        await _run(args);
      } else if (r.uri.path == '/stop') {
        await _stop();
      } else if (r.uri.path == '/probe') {
        body = {'pid': pid, 'probe': await _probe()};
      }
      r.response.write(jsonEncode(body));
    } catch (e, s) {
      r.response.statusCode = 400;
      r.response.write(jsonEncode({'error': '$e', 'stack': '$s'}));
    }
    await r.response.close();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: ValueListenableBuilder<Widget?>(
          valueListenable: _surface,
          builder: (context, w, _) =>
              w ?? const Center(child: Text('cpu diag ready :18089')),
        ),
      ),
    ),
  );
  unawaited(_serve());
}
