// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// libmpv 换版（mpv v0.41 + ffmpeg n9）真机播放验证：H.264/HEVC 硬解、VP9/AV1 软解、HLS、SRT 字幕。
///
/// 素材由本机 HTTP 服务经 `adb reverse tcp:8097` 提供。输出一律走 print（logcat 里 tag=flutter，
/// 行首 V041）。跑法：`flutter run --release -t lib/main_v041_verify.dart -d <设备>`。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaMpvKernel.ensureInitialized();
  runApp(MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder<MovaEngine?>(
        valueListenable: _engineNotifier,
        builder: (_, e, __) => e == null ? const Center(child: Text('v041 verify')) : MovaPlayer(api: e),
      ),
    ),
  ));
  Future<void>.delayed(const Duration(seconds: 2), _run);
}

/// 当前被挂到界面上的引擎（挂上才会创建 VideoController，触发硬解管线）。
final ValueNotifier<MovaEngine?> _engineNotifier = ValueNotifier<MovaEngine?>(null);

/// 本机素材服务前缀。
const String kBase = 'http://127.0.0.1:8097';

/// 输出一行。
void _out(String m) => print('V041 $m');

/// 带时间戳防缓存的 URL。
String _u(String path) => '$kBase/$path?t=${DateTime.now().microsecondsSinceEpoch}';

/// 一个测试项：名字、URL、是否附加字幕。
class _Case {
  /// 构造。
  const _Case(this.name, this.url, {this.sub = false, this.playMs = 7000});

  /// 名字。
  final String name;

  /// 地址（已含时间戳）。
  final String url;

  /// 是否加载外挂 SRT。
  final bool sub;

  /// 首帧后观察时长。
  final int playMs;
}

/// 读 mpv 属性，失败返回 '?'。
Future<String> _prop(Player p, String name) async {
  try {
    final n = p.platform as NativePlayer;
    final v = await n.getProperty(name);
    return v.isEmpty ? '(empty)' : v;
  } on Object catch (e) {
    return '!$e';
  }
}

/// 跑单项。
Future<void> _runCase(_Case c) async {
  _out('=== ${c.name} ${c.url}');
  final player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.info));
  final logs = <String>[];
  int errCount = 0;
  final logSub = player.stream.log.listen((l) {
    final t = '${l.level}/${l.prefix}: ${l.text.trim()}';
    final low = t.toLowerCase();
    final isErr = l.level == 'error' || l.level == 'fatal' || low.contains('fatal');
    if (isErr) errCount++;
    if (isErr ||
        low.contains('hardware') ||
        low.contains('hwdec') ||
        low.contains('decoder') ||
        low.contains('mediacodec') ||
        low.contains('dav1d') ||
        low.contains('libplacebo') ||
        low.contains('vo/') && low.contains('using') ||
        low.contains('opengl') ||
        low.contains('videotoolbox')) {
      logs.add(t);
    }
  });
  final kernel = MovaMpvKernel(player: player, lazyVideo: true, observeQoeSignals: false);
  final engine = createMovaEngine(kernel: kernel);
  _engineNotifier.value = engine;
  final sw = Stopwatch()..start();
  int? readyMs;
  int? sizeMs;
  String size = '';
  int firstPosMs = -1;
  int? posStartWall;
  int posStartVal = 0;
  int lastPos = 0;
  int lastWall = 0;
  final evSub = engine.events.listen((e) {
    if (e is MovaReady && readyMs == null) readyMs = sw.elapsedMilliseconds;
    if (e is MovaSizeChange && e.width > 0 && sizeMs == null) {
      sizeMs = sw.elapsedMilliseconds;
      size = '${e.width}x${e.height}';
    }
    if (e is MovaErrorEvent) _out('${c.name} ERROREVENT $e');
  });
  final progSub = engine.progress.listen((p) {
    lastPos = p.position.inMilliseconds;
    lastWall = sw.elapsedMilliseconds;
    if (firstPosMs < 0 && lastPos > 0) firstPosMs = lastWall;
  });
  try {
    await engine.open(MovaSource(c.url));
    // 等首帧（SizeChange 或 position>0），最多 15s
    for (var i = 0; i < 150 && sizeMs == null && firstPosMs < 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    posStartWall = lastWall;
    posStartVal = lastPos;
    String subInfo = '';
    if (c.sub) {
      final n = player.platform as NativePlayer;
      await n.command(['sub-add', _u('sub.srt'), 'select']);
      final hits = <String>{};
      final end = sw.elapsedMilliseconds + c.playMs;
      while (sw.elapsedMilliseconds < end) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final t = await _prop(player, 'sub-text');
        if (t.isNotEmpty && t != '(empty)' && !t.startsWith('!')) hits.add(t);
      }
      subInfo = ' subTextSeen=$hits sid=${await _prop(player, 'sid')} subCodec=${await _prop(player, 'current-tracks/sub/codec')}';
    } else {
      await Future<void>.delayed(Duration(milliseconds: c.playMs));
    }
    final dWall = lastWall - posStartWall;
    final dPos = lastPos - posStartVal;
    final rate = dWall > 0 ? dPos / dWall : -1;
    final props = <String, String>{};
    for (final k in [
      'video-codec',
      'video-format',
      'hwdec-current',
      'hwdec',
      'current-vo',
      'current-ao',
      'audio-codec-name',
      'frame-drop-count',
      'decoder-frame-drop-count',
      'vo-delayed-frame-count',
      'estimated-vf-fps',
      'container-fps',
      'paused-for-cache',
      'width',
      'height',
    ]) {
      props[k] = await _prop(player, k);
    }
    _out('${c.name} RESULT readyMs=$readyMs sizeMs=$sizeMs size=$size firstPosMs=$firstPosMs '
        'dPosMs=$dPos dWallMs=$dWall rate=${rate.toStringAsFixed(3)} errLogs=$errCount$subInfo');
    _out('${c.name} PROPS $props');
    for (final l in logs.take(25)) {
      _out('${c.name} LOG $l');
    }
  } catch (e, st) {
    _out('${c.name} EXCEPTION $e\n$st');
  }
  await evSub.cancel();
  await progSub.cancel();
  _engineNotifier.value = null;
  await Future<void>.delayed(const Duration(milliseconds: 300));
  try {
    await engine.dispose().timeout(const Duration(seconds: 10));
  } on Object catch (e) {
    _out('${c.name} DISPOSE_ISSUE $e');
  }
  await logSub.cancel();
}

/// 主流程。
Future<void> _run() async {
  _out('START');
  final cases = <_Case>[
    _Case('h264', _u('h264.mp4')),
    _Case('hevc', _u('hevc.mp4')),
    _Case('vp9', _u('vp9.webm')),
    _Case('av1', _u('av1.mkv')),
    _Case('hls_local', _u('hls/index.m3u8')),
    _Case('hls_mux', 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8?t=${DateTime.now().microsecondsSinceEpoch}', playMs: 8000),
    _Case('srt', _u('h264.mp4'), sub: true, playMs: 9000),
  ];
  for (final c in cases) {
    await _runCase(c);
  }
  _out('ALL_DONE');
}
