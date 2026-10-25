// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// Windows 桌面端产品路径验证（Video 控件 + ANGLE/OpenGL ES）。
///
/// 通过 `--dart-define=MODE=general|stress|long` 选择场景，输出一律走 print，行首 `WIN`。
/// - general：依次播 HTTP mp4、本地 mp4、本地 hls，各观察 [kCaseSec] 秒；
/// - stress：WHEP 起播/停止 [kRounds] 轮，每轮重建 engine；
/// - long：WHEP 单会话长跑 [kLongSec] 秒，每 30 秒采样一次。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaMpvKernel.ensureInitialized();
  if (kMode.startsWith('raw')) {
    unawaited(_runRaw());
    return;
  }
  runApp(MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder<MovaEngine?>(
        valueListenable: _engineNotifier,
        builder: (_, e, __) => e == null ? const Center(child: Text('win verify')) : MovaPlayer(api: e),
      ),
    ),
  ));
  Future<void>.delayed(const Duration(seconds: 2), _run);
}

/// 当前挂到界面上的引擎。
final ValueNotifier<MovaEngine?> _engineNotifier = ValueNotifier<MovaEngine?>(null);

/// 场景名。
const String kMode = String.fromEnvironment('MODE', defaultValue: 'general');

/// WHEP 信令地址。
const String kWhepUrl = String.fromEnvironment('WHEP_URL', defaultValue: 'whep+http://127.0.0.1:28889/test/whep');

/// HTTP mp4 地址。
const String kHttpMp4 = String.fromEnvironment('HTTP_MP4', defaultValue: 'http://127.0.0.1:28080/clip.mp4');

/// 本地 mp4 路径。
const String kFileMp4 = String.fromEnvironment('FILE_MP4', defaultValue: r'D:\tmp\win2\media\clip.mp4');

/// 本地 hls 路径（http 提供）。
const String kHlsUrl = String.fromEnvironment('HLS_URL', defaultValue: 'http://127.0.0.1:28080/hls/index.m3u8');

/// 通用场景每项观察秒数。
const int kCaseSec = int.fromEnvironment('CASE_SEC', defaultValue: 15);

/// 起播/停止轮数。
const int kRounds = int.fromEnvironment('ROUNDS', defaultValue: 5);

/// 起播/停止每轮观察秒数。
const int kRoundSec = int.fromEnvironment('ROUND_SEC', defaultValue: 8);

/// 长跑秒数。
const int kLongSec = int.fromEnvironment('LONG_SEC', defaultValue: 330);

/// 挂界面后、open 前的等待毫秒数（排查懒创建 VideoController 与立即 open 的时序）。
const int kPreOpenMs = int.fromEnvironment('PRE_OPEN_MS', defaultValue: 0);

/// 输出一行。
void _out(String m) => print('WIN $m');

/// 读 mpv 属性，失败返回 '?'。
Future<String> _prop(Player p, String name) async {
  try {
    final v = await (p.platform as NativePlayer).getProperty(name);
    return v.isEmpty ? '(empty)' : v;
  } on Object catch (e) {
    return '!$e';
  }
}

/// 一次播放：建 engine 挂界面，打开 [uri]，观察 [sec] 秒，每 [stepSec] 秒打一行，最后销毁。
Future<void> _playCase(String name, String uri, int sec, {int stepSec = 5}) async {
  final player = Player(
    configuration: const PlayerConfiguration(
      protocolWhitelist: ['udp', 'rtp', 'tcp', 'tls', 'data', 'file', 'http', 'https', 'crypto', 'dtls'],
    ),
  );
  final kernel = MovaMpvKernel(player: player, lazyVideo: true, observeQoeSignals: false);
  final engine = createMovaEngine(kernel: kernel);
  _engineNotifier.value = engine;
  final sw = Stopwatch()..start();
  var size = '';
  var lastPos = 0;
  var err = '';
  engine.events.listen((e) {
    if (e is MovaSizeChange && e.width > 0 && e.height > 0 && size.isEmpty) {
      size = '${e.width}x${e.height}';
      _out('$name size=$size @${sw.elapsedMilliseconds}ms');
    }
    if (e is MovaErrorEvent) {
      err = '$e';
      _out('$name ERROREVENT $e');
    }
  });
  engine.progress.listen((p) => lastPos = p.position.inMilliseconds);
  if (kPreOpenMs > 0) await Future<void>.delayed(const Duration(milliseconds: kPreOpenMs));
  _out('$name OPEN $uri');
  try {
    await engine.open(MovaSource(uri));
  } on Object catch (e) {
    _out('$name open threw $e');
  }
  for (var s = stepSec; s <= sec; s += stepSec) {
    await Future<void>.delayed(Duration(seconds: stepSec));
    _out('$name t+${s}s pos=$lastPos size=$size hwdec=${await _prop(player, 'hwdec-current')} '
        'acodec=${await _prop(player, 'audio-codec-name')} fps=${await _prop(player, 'estimated-vf-fps')} '
        'drop=${await _prop(player, 'frame-drop-count')}/${await _prop(player, 'decoder-frame-drop-count')} '
        'vo-delayed=${await _prop(player, 'vo-delayed-frame-count')} avsync=${await _prop(player, 'avsync')} '
        'core-idle=${await _prop(player, 'core-idle')} vid=${await _prop(player, 'vid')} vtracks=${await _prop(player, 'track-list/count')} vo=${await _prop(player, 'current-vo')}');
  }
  _out('$name RESULT pos=$lastPos size=${size.isEmpty ? "NONE" : size} err=${err.isEmpty ? "none" : err}');
  await player.stop();
  await Future<void>.delayed(const Duration(milliseconds: 500));
  _engineNotifier.value = null;
  await engine.dispose();
  await Future<void>.delayed(const Duration(seconds: 2));
  _out('$name DISPOSED');
}

/// 主流程。
Future<void> _run() async {
  _out('MODE=$kMode start');
  switch (kMode) {
    case 'stress':
      for (var i = 1; i <= kRounds; i++) {
        await _playCase('round$i', kWhepUrl, kRoundSec, stepSec: 4);
      }
    case 'long':
      await _playCase('long', kWhepUrl, kLongSec, stepSec: 30);
    default:
      await _playCase('httpmp4', kHttpMp4, kCaseSec);
      await _playCase('filemp4', kFileMp4, kCaseSec);
      await _playCase('hls', kHlsUrl, kCaseSec);
  }
  _out('ALLDONE');
  await Future<void>.delayed(const Duration(seconds: 3));
  exit(0);
}

/// 不经 mova，直接用 media_kit Player + Video 控件长跑，用来区分内存增长是否来自 mova 层。
Future<void> _runRaw() async {
  final player = Player(
    configuration: const PlayerConfiguration(
      protocolWhitelist: ['udp', 'rtp', 'tcp', 'tls', 'data', 'file', 'http', 'https', 'crypto', 'dtls'],
    ),
  );
  if (kMode == 'rawwhepnov') {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('no video')))));
  } else {
    final vc = VideoController(player, configuration: VideoControllerConfiguration(hwdec: kMode == 'rawwhepsw' ? 'no' : null));
    runApp(MaterialApp(home: Scaffold(body: Video(controller: vc))));
  }
  await Future<void>.delayed(const Duration(seconds: 2));
  final uri = kMode == 'rawfile' ? kFileMp4 : kWhepUrl;
  if (kMode == 'rawfile') await (player.platform as NativePlayer).setProperty('loop-file', 'inf');
  _out('$kMode OPEN $uri');
  await player.open(Media(uri));
  for (var s = 30; s <= kLongSec; s += 30) {
    await Future<void>.delayed(const Duration(seconds: 30));
    _out('$kMode t+${s}s pos=${player.state.position.inMilliseconds} drop=${await _prop(player, 'frame-drop-count')}/${await _prop(player, 'decoder-frame-drop-count')}');
  }
  _out('ALLDONE');
  await player.dispose();
  exit(0);
}
