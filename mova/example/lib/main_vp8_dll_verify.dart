import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// 样本目录与结果输出路径，由环境变量注入（release 不读 dart-define）。
final String srcDir = Platform.environment['SRC_DIR'] ?? '';
final String outPath = Platform.environment['OUT'] ?? 'vp8_verify_out.jsonl';
final String tag = Platform.environment['TAG'] ?? 'dll';

final screen = ValueNotifier<MovaApi?>(null);
late final IOSink sink;

/// 写一行带墙钟（仅用于与外部 CPU 采样对时）的 JSON 记录。
void mark(String kind, Map<String, Object?> data) {
  final line = jsonEncode({'epoch': DateTime.now().millisecondsSinceEpoch, 'tag': tag, 'kind': kind, ...data});
  sink.writeln(line);
}

/// 入口：按环境变量 FILE/RUN/WATCH 只跑一个用例后退出进程。
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    MovaEngine.ensureInitialized();
    sink = File(outPath).openWrite();
    runApp(MaterialApp(home: Scaffold(body: ValueListenableBuilder<MovaApi?>(
      valueListenable: screen,
      builder: (_, api, child) => api == null
          ? const Center(child: Text('VP8 dll verify'))
          : MovaPlayer(api: api, skin: const MovaMinimalSkin())))));
    await WidgetsBinding.instance.endOfFrame;
    mark('BEGIN', {'pid': pid});
    try {
      await probe(Platform.environment['FILE'] ?? 'vp8.webm', int.parse(Platform.environment['RUN'] ?? '0'),
          int.parse(Platform.environment['WATCH'] ?? '6'));
    } catch (e, s) {
      mark('SCRIPT_ERROR', {'error': '$e', 'stack': '$s'});
    }
    mark('END', {});
    await sink.flush();
    await sink.close();
    exit(0);
  }, (e, s) => mark('UNCAUGHT', {'error': '$e'}));
}

/// 读取 mpv 属性，失败返回 null。
Future<String?> prop(NativePlayer n, String k) async {
  try { return await n.getProperty(k); } catch (_) { return null; }
}

/// 打开一个样本，等首帧或错误，再采样 [watch] 秒并读回属性。
Future<void> probe(String file, int run, int watch) async {
  final player = Player();
  final kernel = MovaMpvKernel(player: player, lazyVideo: true);
  final api = createMovaEngine(kernel: kernel, preciseFirstFrame: true);
  final native = player.platform as NativePlayer;
  var errors = 0, firstFrames = 0, sizeChanges = 0;
  final errTexts = <String>[];
  final sub = api.events.listen((e) {
    if (e is MovaErrorEvent) { errors++; if (errTexts.length < 3) errTexts.add('${e.error}'); }
    if (e is MovaFirstFrame) firstFrames++;
    if (e is MovaSizeChange) sizeChanges++;
  });
  screen.value = api;
  await WidgetsBinding.instance.endOfFrame;
  final t0 = DateTime.now();
  final path = '$srcDir/$file';
  mark('OPEN', {'file': file, 'run': run});
  Object? openErr;
  try { await api.open(MovaSource(path)); } catch (e) { openErr = e; }
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!api.state.rendered && errors == 0 && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  final ttff = api.state.rendered ? DateTime.now().difference(t0).inMilliseconds : null;
  final p1 = player.state.position.inMilliseconds;
  await Future<void>.delayed(Duration(seconds: watch));
  final p2 = player.state.position.inMilliseconds;
  mark('RESULT', {
    'file': file, 'run': run, 'watchSec': watch, 'openErr': '$openErr',
    'rendered': api.state.rendered, 'ttffMs': ttff,
    'videoFormat': await prop(native, 'video-format'),
    'videoCodec': await prop(native, 'video-codec'),
    'hwdecCurrent': await prop(native, 'hwdec-current'),
    'width': api.state.width, 'height': api.state.height,
    'posStart': p1, 'posEnd': p2, 'playing': api.state.playing,
    'errors': errors, 'errTexts': errTexts, 'firstFrames': firstFrames, 'sizeChanges': sizeChanges,
  });
  await sub.cancel();
  screen.value = null;
  await WidgetsBinding.instance.endOfFrame;
  // 不等待 dispose：销毁偶发卡住属 media_kit 已知行为，由进程退出回收。
}
