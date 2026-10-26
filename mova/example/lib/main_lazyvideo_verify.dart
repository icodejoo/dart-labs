// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:mova/src/platform_impl/frame_yield.dart';

/// lazyVideo 时序验证：挂界面后立即 open，统计 mpv 解码器重建 / vo 重配 / seek 次数与起播耗时。
///
/// 输出一行一条，行首 `LZV`。参数（`--dart-define`）：
/// - `URLS`：逗号分隔的 `名字=地址`；
/// - `PRE_OPEN_MS`：挂界面后、open 前的等待毫秒数（0 即"立即 open"）；
/// - `ROUNDS`：每个源重复轮数。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaMpvKernel.ensureInitialized();
  runApp(MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder<MovaEngine?>(
        valueListenable: _engineNotifier,
        builder: (_, e, __) => e == null ? const Center(child: Text('lazyvideo verify')) : MovaPlayer(api: e),
      ),
    ),
  ));
  Future<void>.delayed(const Duration(seconds: 2), _run);
}

/// 当前挂到界面上的引擎。
final ValueNotifier<MovaEngine?> _engineNotifier = ValueNotifier<MovaEngine?>(null);

/// 测试源列表，格式 `名字=地址,名字=地址`。
const String kUrls = String.fromEnvironment('URLS', defaultValue: 'h264=http://127.0.0.1:8097/h264.mp4');

/// 挂界面后、open 前的等待毫秒数。
const int kPreOpenMs = int.fromEnvironment('PRE_OPEN_MS', defaultValue: 0);

/// 是否懒创建 VideoController。
const bool kLazy = bool.fromEnvironment('LAZY', defaultValue: true);

/// 是否打印 mpv 日志（前 120 行）。
const bool kDump = bool.fromEnvironment('DUMP', defaultValue: false);

/// 截图保存目录，空则不保存。
const String kShotDir = String.fromEnvironment('SHOT_DIR');

/// 每个源的轮数。
const int kRounds = int.fromEnvironment('ROUNDS', defaultValue: 3);

/// 首帧后继续观察的毫秒数。
const int kObserveMs = int.fromEnvironment('OBSERVE_MS', defaultValue: 5000);

/// 输出一行。
void _out(String m) => print('LZV $m');

/// 读 mpv 属性，失败返回 '?'。
Future<String> _prop(Player p, String name) async {
  try {
    final v = await (p.platform as NativePlayer).getProperty(name);
    return v.isEmpty ? '(empty)' : v;
  } on Object catch (e) {
    return '!$e';
  }
}

/// 跑一轮。
Future<void> _runOne(String name, String url, int round) async {
  final tag = '$name#$round';
  final player = Player(
    configuration: const PlayerConfiguration(
      logLevel: MPVLogLevel.v,
      protocolWhitelist: ['udp', 'rtp', 'tcp', 'tls', 'data', 'file', 'http', 'https', 'crypto', 'dtls'],
    ),
  );
  var decoderOpens = 0;
  var seeks = 0;
  var voSets = 0;
  var vidSets = 0;
  final timeline = <String>[];
  final sw = Stopwatch()..start();
  final dump = <String>[];
  final logSub = player.stream.log.listen((l) {
    final t = l.text.trim();
    if (kDump && dump.length < 120 && l.prefix != 'ffmpeg' && !t.startsWith('Set property: ')) {
      dump.add('${sw.elapsedMilliseconds}:${l.prefix}:$t');
    }
    if (t.startsWith('Opening decoder')) {
      final video = RegExp('h264|hevc|vp9|av1|mediacodec').hasMatch(t);
      if (video) decoderOpens++;
      timeline.add('${sw.elapsedMilliseconds}:${video ? 'vdec' : 'adec'}');
    }
    if (t.contains('hr-seek') || t.startsWith('queuing seek')) {
      seeks++;
      timeline.add('${sw.elapsedMilliseconds}:seek');
    }
    if (t.contains('Set property: vo=')) {
      voSets++;
      timeline.add('${sw.elapsedMilliseconds}:$t');
    }
    if (t.contains('Set property: vid=')) {
      vidSets++;
      timeline.add('${sw.elapsedMilliseconds}:$t');
    }
  });
  final kernel = MovaMpvKernel(player: player, lazyVideo: kLazy, mountYield: movaFrameYield, observeQoeSignals: false);
  final engine = createMovaEngine(kernel: kernel);
  _engineNotifier.value = engine;
  int? sizeMs;
  var size = '';
  var lastPos = 0;
  int firstPosMs = -1;
  engine.events.listen((e) {
    if (e is MovaSizeChange && e.width > 0 && sizeMs == null) {
      sizeMs = sw.elapsedMilliseconds;
      size = '${e.width}x${e.height}';
    }
  });
  engine.progress.listen((p) {
    lastPos = p.position.inMilliseconds;
    if (firstPosMs < 0 && lastPos > 0) firstPosMs = sw.elapsedMilliseconds;
  });
  if (kPreOpenMs > 0) await Future<void>.delayed(const Duration(milliseconds: kPreOpenMs));
  sw.reset();
  timeline.add('${sw.elapsedMilliseconds}:open');
  await engine.open(MovaSource(url.startsWith('http') ? '$url?t=${DateTime.now().microsecondsSinceEpoch}' : url));
  for (var i = 0; i < 150 && sizeMs == null && firstPosMs < 0; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await Future<void>.delayed(const Duration(milliseconds: kObserveMs));
  var shot = 0;
  try {
    final bytes = await player.screenshot(format: 'image/jpeg');
    shot = bytes?.length ?? 0;
    if (bytes != null && kShotDir.isNotEmpty) {
      await File('$kShotDir/${tag.replaceAll('#', '_')}.jpg').writeAsBytes(bytes);
    }
  } on Object catch (e) {
    _out('$tag SHOT_ERR $e');
  }
  final vid = await _prop(player, 'vid');
  final hw = await _prop(player, 'hwdec-current');
  final vo = await _prop(player, 'current-vo');
  _out('$tag RESULT firstPosMs=$firstPosMs sizeMs=$sizeMs size=$size decoderOpens=$decoderOpens seeks=$seeks '
      'voSets=$voSets vidSets=$vidSets vid=$vid vo=$vo hwdec=$hw pos=$lastPos shotBytes=$shot');
  for (final d in dump) {
    _out('$tag LOG $d');
  }
  _out('$tag TIMELINE ${timeline.join(' | ')}');
  _engineNotifier.value = null;
  await Future<void>.delayed(const Duration(milliseconds: 300));
  try {
    await engine.dispose().timeout(const Duration(seconds: 10));
  } on Object catch (e) {
    _out('$tag DISPOSE_ISSUE $e');
  }
  await logSub.cancel();
  await Future<void>.delayed(const Duration(seconds: 1));
}

/// 主流程。
Future<void> _run() async {
  _out('START preOpenMs=$kPreOpenMs');
  for (var r = 1; r <= kRounds; r++) {
    for (final item in kUrls.split(',')) {
      final i = item.indexOf('=');
      await _runOne(item.substring(0, i), item.substring(i + 1), r);
    }
  }
  _out('ALL_DONE');
  await Future<void>.delayed(const Duration(seconds: 2));
  if (!Platform.isAndroid) exit(0);
}
