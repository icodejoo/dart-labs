import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// 样本与配置服务根地址（经 adb reverse 指向本机）。
const String base = String.fromEnvironment('BASE', defaultValue: 'http://127.0.0.1:18090');

/// 日志前缀，便于 logcat 过滤。
const String tagPrefix = 'VP8D';

/// 当前挂到界面上的引擎。
final screen = ValueNotifier<MovaApi?>(null);

/// raw 模式下挂到界面的视频控制器。
final rawCtl = ValueNotifier<VideoController?>(null);

/// 输出一行 JSON 到 logcat。
void mark(String kind, Map<String, Object?> data) {
  // ignore: avoid_print
  print('$tagPrefix|${jsonEncode({'epoch': DateTime.now().millisecondsSinceEpoch, 'kind': kind, ...data})}');
}

/// 从主机拉取本轮配置（JSON：file/props/logFile/useVideo）。
Future<Map<String, dynamic>> fetchCfg() async {
  final c = HttpClient();
  final r = await (await c.getUrl(Uri.parse('$base/cfg.json'))).close();
  final s = await r.transform(utf8.decoder).join();
  c.close();
  return jsonDecode(s) as Map<String, dynamic>;
}

/// 入口：按配置打开一个样本，输出心跳与结果。
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    MovaEngine.ensureInitialized();
    runApp(MaterialApp(
        home: Scaffold(
            body: ValueListenableBuilder<MovaApi?>(
                valueListenable: screen,
                builder: (_, api, child) => api != null
                    ? MovaPlayer(api: api, skin: const MovaMinimalSkin())
                    : ValueListenableBuilder<VideoController?>(
                        valueListenable: rawCtl,
                        builder: (_, c, w) => c == null ? const Center(child: Text('VP8 diag')) : Video(controller: c))))));
    await WidgetsBinding.instance.endOfFrame;
    final cfg = await fetchCfg();
    mark('CFG', cfg);
    Timer.periodic(const Duration(milliseconds: 500), (t) => mark('HB', {}));
    if (cfg['raw'] == true) {
      await rawProbe(cfg);
    } else {
      await probe(cfg);
    }
  }, (e, s) => mark('UNCAUGHT', {'error': '$e'}));
}

/// 按配置打开样本并观察。
Future<void> probe(Map<String, dynamic> cfg) async {
  final player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.v));
  final kernel = MovaMpvKernel(player: player, lazyVideo: true);
  final api = createMovaEngine(kernel: kernel, preciseFirstFrame: true);
  final native = player.platform as NativePlayer;
  player.stream.log.listen((l) => mark('MPV', {'p': l.prefix, 'lvl': l.level, 't': l.text.trim()}));
  api.events.listen((e) {
    if (e is MovaErrorEvent) mark('ERR', {'e': '${e.error}'});
  });
  screen.value = api;
  await WidgetsBinding.instance.endOfFrame;
  final props = (cfg['props'] as Map?)?.cast<String, String>() ?? {};
  for (final e in props.entries) {
    try {
      await native.setProperty(e.key, e.value);
      mark('SET', {e.key: e.value});
    } catch (x) {
      mark('SETFAIL', {e.key: '$x'});
    }
  }
  mark('OPEN', {'file': cfg['file']});
  try {
    await api.open(MovaSource('$base/${cfg['file']}?t=${DateTime.now().millisecondsSinceEpoch}')).timeout(const Duration(seconds: 15));
    mark('OPENED', {});
  } catch (e) {
    mark('OPENERR', {'e': '$e'});
  }
  for (var i = 0; i < 16; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    mark('POLL', {'rendered': api.state.rendered, 'pos': player.state.position.inMilliseconds, 'size': '${api.state.width}x${api.state.height}'});
  }
  mark('RESULT', {
    'rendered': api.state.rendered,
    'pos': player.state.position.inMilliseconds,
    'hw': await _p(native, 'hwdec-current'),
    'vc': await _p(native, 'video-codec'),
  });
  await api.dispose();
  mark('DONE', {});
}

/// 读取属性，失败返回 null。
Future<String?> _p(NativePlayer n, String k) async {
  try {
    return await n.getProperty(k).timeout(const Duration(seconds: 2));
  } catch (_) {
    return null;
  }
}

/// 绕开 mova 引擎，直接用 media_kit 打开样本并观察。
Future<void> rawProbe(Map<String, dynamic> cfg) async {
  final player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.v));
  final native = player.platform as NativePlayer;
  player.stream.log.listen((l) => mark('MPV', {'p': l.prefix, 'lvl': l.level, 't': l.text.trim()}));
  player.stream.error.listen((e) => mark('ERR', {'e': e}));
  rawCtl.value = VideoController(player);
  await WidgetsBinding.instance.endOfFrame;
  final props = (cfg['props'] as Map?)?.cast<String, String>() ?? {};
  for (final e in props.entries) {
    await native.setProperty(e.key, e.value);
    mark('SET', {e.key: e.value});
  }
  mark('OPEN', {'file': cfg['file']});
  await player.open(Media('$base/${cfg['file']}?t=${DateTime.now().millisecondsSinceEpoch}'));
  mark('OPENED', {});
  for (var i = 0; i < 16; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    mark('POLL', {'pos': player.state.position.inMilliseconds, 'w': player.state.width, 'h': player.state.height});
  }
  mark('RESULT', {'pos': player.state.position.inMilliseconds, 'w': player.state.width});
  mark('DONE', {});
}
