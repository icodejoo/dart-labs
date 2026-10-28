import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// 样本服务根地址（经 adb reverse 指向本机），由 --dart-define 注入。
const String base = String.fromEnvironment('BASE', defaultValue: 'http://127.0.0.1:18090');

/// 日志前缀，便于 logcat 过滤。
const String tagPrefix = 'VP8V';

/// 当前挂到界面上的引擎，null 时显示占位。
final screen = ValueNotifier<MovaApi?>(null);

/// 输出一行带墙钟（仅作人读对时）的 JSON 到 logcat。
void mark(String kind, Map<String, Object?> data) {
  // ignore: avoid_print
  print('$tagPrefix|${jsonEncode({'epoch': DateTime.now().millisecondsSinceEpoch, 'kind': kind, ...data})}');
}

/// 入口：依次验证 VP8 与 H.264 样本，各跑 3 次。
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    MovaEngine.ensureInitialized();
    runApp(MaterialApp(
        home: Scaffold(
            body: ValueListenableBuilder<MovaApi?>(
                valueListenable: screen,
                builder: (_, api, child) => api == null
                    ? const Center(child: Text('VP8 android verify'))
                    : MovaPlayer(api: api, skin: const MovaMinimalSkin())))));
    await WidgetsBinding.instance.endOfFrame;
    mark('BEGIN', {});
    for (final f in ['vp8.webm', 'h264.mp4']) {
      for (var run = 0; run < 3; run++) {
        try {
          await probe(f, run);
        } catch (e, s) {
          mark('SCRIPT_ERROR', {'file': f, 'error': '$e', 'stack': '$s'});
        }
      }
    }
    mark('END', {});
  }, (e, s) => mark('UNCAUGHT', {'error': '$e'}));
}

/// 读取 mpv 属性，失败返回 null。
Future<String?> prop(NativePlayer n, String k) async {
  try {
    return await n.getProperty(k).timeout(const Duration(seconds: 2));
  } catch (_) {
    return null;
  }
}

/// 打开一个样本，等首帧或错误，再观察 4 秒位置推进并读回解码属性。
Future<void> probe(String file, int run) async {
  final player = Player();
  final kernel = MovaMpvKernel(player: player, lazyVideo: true);
  final api = createMovaEngine(kernel: kernel, preciseFirstFrame: true);
  final native = player.platform as NativePlayer;
  var errors = 0;
  final errTexts = <String>[];
  final sub = api.events.listen((e) {
    if (e is MovaErrorEvent) {
      errors++;
      if (errTexts.length < 3) errTexts.add('${e.error}');
    }
  });
  screen.value = api;
  await WidgetsBinding.instance.endOfFrame;
  final t0 = DateTime.now();
  Object? openErr;
  try {
    mark('OPEN', {'file': file, 'run': run});
    await api.open(MovaSource('$base/$file?t=${t0.millisecondsSinceEpoch}')).timeout(const Duration(seconds: 15));
    mark('OPENED', {'file': file});
  } catch (e) {
    openErr = e;
  }
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!api.state.rendered && errors == 0 && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  mark('WAIT_DONE', {'rendered': api.state.rendered, 'errors': errors});
  final ttff = api.state.rendered ? DateTime.now().difference(t0).inMilliseconds : null;
  final p1 = player.state.position.inMilliseconds;
  await Future<void>.delayed(const Duration(seconds: 4));
  final p2 = player.state.position.inMilliseconds;
  mark('RESULT', {
    'file': file,
    'run': run,
    'openErr': openErr?.toString(),
    'rendered': api.state.rendered,
    'ttffMs': ttff,
    'size': '${api.state.width}x${api.state.height}',
    'posAdvanceMs': p2 - p1,
    'errors': errors,
    'errTexts': errTexts,
    'videoCodec': await prop(native, 'video-codec'),
    'videoFormat': await prop(native, 'video-format'),
    'hwdecCurrent': await prop(native, 'hwdec-current'),
  });
  await sub.cancel();
  screen.value = null;
  await WidgetsBinding.instance.endOfFrame;
  await api.dispose();
}
