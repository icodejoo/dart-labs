import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// 样本服务根地址（经 adb reverse 指向本机），由 --dart-define 注入。
const String base = String.fromEnvironment('BASE', defaultValue: 'http://127.0.0.1:18090');

/// 每种内核的重复次数。
const int runsEach = int.fromEnvironment('RUNS', defaultValue: 12);

/// 要跑的内核，逗号分隔（mova,pure）；单独跑 pure 时 ffmpeg 日志才会归到它自己的 Player。
const String kindsDefine = String.fromEnvironment('KINDS', defaultValue: 'pure');

/// 解析后的内核列表。
final List<String> kinds = kindsDefine.split(',');

/// 日志前缀，便于 logcat 过滤。
const String tagPrefix = 'PMK';

/// 当前要挂到界面上的控件（mova 与原生各自一个）。
final screen = ValueNotifier<Widget?>(null);

/// 主线程心跳最大间隔（毫秒），每轮开头清零。
int maxGapMs = 0;

/// 上一次心跳时刻。
DateTime lastBeat = DateTime.now();

/// 输出一行 JSON 到 logcat。
void mark(String kind, Map<String, Object?> data) {
  // ignore: avoid_print
  print('$tagPrefix|${jsonEncode({'kind': kind, ...data})}');
}

/// 入口：mova 与原生 media_kit 在同一进程内交替各跑 [runsEach] 轮，抵消设备状态漂移。
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    MovaEngine.ensureInitialized();
    runApp(MaterialApp(
        home: Scaffold(
            body: ValueListenableBuilder<Widget?>(
                valueListenable: screen, builder: (_, w, child) => w ?? const Center(child: Text('pure media_kit vs mova'))))));
    await WidgetsBinding.instance.endOfFrame;
    Timer.periodic(const Duration(milliseconds: 100), (t) {
      final now = DateTime.now();
      final g = now.difference(lastBeat).inMilliseconds;
      if (g > maxGapMs) maxGapMs = g;
      lastBeat = now;
    });
    mark('BEGIN', {});
    for (var r = 0; r < runsEach; r++) {
      for (final kind in kinds) {
        try {
          await probe(kind, r, 'vp8.webm', presize: true);
          await probe(kind, r, 'vp8.webm', presize: true, w: 320, h: 180);
          await probe(kind, r, 'vp8.webm', presize: true, w: 1920, h: 1080);
        } catch (e, s) {
          mark('SCRIPT_ERROR', {'kernel': kind, 'run': r, 'error': '$e', 'stack': '$s'});
        }
      }
    }
    mark('END', {});
  }, (e, s) => mark('UNCAUGHT', {'error': '$e'}));
}

/// 读本进程各线程累计 CPU tick（utime+stime），键为 "tid:comm"。
Map<String, int> threadTicks() {
  final out = <String, int>{};
  try {
    for (final d in Directory('/proc/self/task').listSync()) {
      final s = File('${d.path}/stat').readAsStringSync();
      final l = s.indexOf('('), r = s.lastIndexOf(')');
      final f = s.substring(r + 2).split(' ');
      out['${d.path.split('/').last}:${s.substring(l + 1, r)}'] = int.parse(f[11]) + int.parse(f[12]);
    }
  } catch (_) {}
  return out;
}

/// 采样 [ms] 毫秒内各线程 CPU 占比（单核百分比），返回前 3。
Future<List<String>> topThreads(int ms) async {
  final a = threadTicks();
  await Future<void>.delayed(Duration(milliseconds: ms));
  final b = threadTicks();
  final d = <String, double>{};
  b.forEach((k, v) => d[k] = (v - (a[k] ?? 0)) * 10 * 100 / ms);
  final l = d.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
  return l.take(3).map((e) => '${e.key}=${e.value.toStringAsFixed(0)}%').toList();
}

/// 读 mpv 属性，失败返回 null。
Future<String?> prop(NativePlayer n, String k) async {
  try {
    return await n.getProperty(k).timeout(const Duration(seconds: 2));
  } catch (_) {
    return null;
  }
}

/// 跑一轮：[kind] 为 mova 或 pure；两者用同一个 so、同一样本、同样的 mpv 属性，观察口径一致。
Future<void> probe(String kind, int run, String file, {bool presize = false, int w = 640, int h = 360}) async {
  maxGapMs = 0;
  final player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.v));
  var opens = 0, attempts = 0, decodeErr = 0, dequeueFail = 0;
  final all = <String>[];
  player.stream.log.listen((l) {
    if (all.length < 60000) all.add('${DateTime.now().toIso8601String().substring(17)} ${l.level}/${l.prefix}: ${l.text.trim()}');
    if (l.prefix == 'vd' && l.text.contains('Opening decoder')) opens++;
    if (l.text.contains('Attempting next decoding method')) attempts++;
    if (l.text.contains('Error while decoding frame')) decodeErr++;
    if (l.text.contains('Failed to dequeue output buffer')) dequeueFail++;
  });
  final errs = <String>[];
  player.stream.error.listen((e) {
    if (errs.length < 3) errs.add(e);
  });
  final native = player.platform as NativePlayer;
  MovaApi? api;
  if (kind == 'mova') {
    // 与 main_vp8_4abi_smoke 相同：懒创建控制器，挂 MovaPlayer 后再开文件。
    api = createMovaEngine(kernel: MovaMpvKernel(player: player, lazyVideo: true), preciseFirstFrame: true);
    screen.value = MovaPlayer(api: api, skin: const MovaMinimalSkin());
  } else {
    // 原生：只用 media_kit 的 Player + VideoController + Video 控件，不经过 mova。
    final controller = VideoController(player);
    screen.value = Video(controller: controller, controls: NoVideoControls);
  }
  await WidgetsBinding.instance.endOfFrame;
  await native.setProperty('vd-lavc-o', 'ndk_codec=1');
  // 实验：打开文件前先用已知尺寸触发 media_kit 的 SetSurfaceSize，让渲染面与 vo=gpu 提前就绪。
  var voBefore = '-';
  if (presize) {
    final handle = await player.handle;
    await const MethodChannel('com.alexmercerind/media_kit_video')
        .invokeMethod('VideoOutputManager.SetSurfaceSize', {'handle': handle.toString(), 'width': '$w', 'height': '$h'});
    final w0 = DateTime.now();
    while (DateTime.now().difference(w0).inMilliseconds < 3000) {
      voBefore = (await prop(native, 'vo')) ?? '-';
      if (voBefore == 'gpu') break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
  final t0 = DateTime.now();
  Object? openErr;
  try {
    final url = '$base/$file?t=${t0.millisecondsSinceEpoch}';
    if (api != null) {
      await api.open(MovaSource(url)).timeout(const Duration(seconds: 15));
    } else {
      await player.open(Media(url), play: true).timeout(const Duration(seconds: 15));
    }
  } catch (e) {
    openErr = e;
  }
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (player.state.width == null && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  final ttff = player.state.width != null ? DateTime.now().difference(t0).inMilliseconds : null;
  await Future<void>.delayed(const Duration(seconds: 1));
  final pos1s = player.state.position.inMilliseconds;
  final top = await topThreads(3000);
  final hw = await prop(native, 'hwdec-current');
  await Future<void>.delayed(const Duration(seconds: 1));
  final pos2 = player.state.position.inMilliseconds;
  // 卡死判据：渲染出来了但位置几乎没动，或解码错误成百上千。
  final hung = pos2 <= 100 || decodeErr > 100;
  mark('RESULT', {
    'kernel': kind,
    'file': file,
    'presize': presize,
    'preW': presize ? w : 0,
    'voBefore': voBefore,
    'run': run,
    'openErr': openErr?.toString(),
    'ttffMs': ttff,
    'size': '${player.state.width}x${player.state.height}',
    'posAt1sMs': pos1s,
    'posEndMs': pos2,
    'hung': hung,
    'opens': opens,
    'attemptNext': attempts,
    'decodeErr': decodeErr,
    'dequeueFail': dequeueFail,
    'errTexts': errs,
    'maxHeartbeatGapMs': maxGapMs,
    'topThreads': top,
    'hwdecCurrent': hw,
  });
  screen.value = null;
  await WidgetsBinding.instance.endOfFrame;
  if (api != null) {
    await api.dispose();
  } else {
    await player.dispose();
  }
}

/// 输出一轮的完整 mpv 日志摘要：去重计数、开头 80 行、首个解码错误前后各 30 行。
void dumpLog(int run, bool hung, List<String> all) {
  final counts = <String, int>{};
  for (final l in all) {
    final k = l.substring(l.indexOf(' ') + 1).replaceAll(RegExp(r'\d+'), '#');
    counts[k] = (counts[k] ?? 0) + 1;
  }
  final top = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  mark('LOGSUM', {'run': run, 'hung': hung, 'total': all.length, 'top': [for (final e in top.take(25)) '${e.value}x ${e.key}']});
  void lines(String tag, Iterable<String> ls) {
    var i = 0;
    for (final l in ls) {
      mark('L', {'run': run, 'tag': tag, 'i': i++, 'line': l.length > 300 ? l.substring(0, 300) : l});
    }
  }
  lines('head', all.take(80));
  final first = all.indexWhere((l) => l.contains('Error while decoding'));
  if (first >= 0) {
    lines('aroundFirstErr', all.sublist(first > 30 ? first - 30 : 0, first + 30 > all.length ? all.length : first + 30));
    lines('tail', all.sublist(all.length > 15 ? all.length - 15 : 0));
  }
}
