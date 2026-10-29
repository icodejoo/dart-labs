import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// 样本服务根地址（经 adb reverse 指向本机），由 --dart-define 注入。
const String base = String.fromEnvironment('BASE', defaultValue: 'http://127.0.0.1:18090');

/// 本轮 ABI 标签，仅写进日志。
const String abi = String.fromEnvironment('ABI', defaultValue: '?');

/// 日志前缀，便于 logcat 过滤。
const String tagPrefix = 'SMK';

/// 当前挂到界面上的引擎。
final screen = ValueNotifier<MovaApi?>(null);

/// 主线程心跳最大间隔（毫秒），每个用例开头清零。
int maxGapMs = 0;

/// 上一次心跳时刻。
DateTime lastBeat = DateTime.now();

/// 输出一行 JSON 到 logcat。
void mark(String kind, Map<String, Object?> data) {
  // ignore: avoid_print
  print('$tagPrefix|${jsonEncode({'abi': abi, 'kind': kind, ...data})}');
}

/// 用例：样本、附加 mpv 属性、期望、重复次数。
class Case {
  /// 构造用例。
  const Case(this.name, this.file, this.props, this.runs, {this.toEnd = false, this.waitVo = false, this.coolMs = 0});

  /// 用例名。
  final String name;

  /// 样本文件名。
  final String file;

  /// 打开前设置的 mpv 属性。
  final Map<String, String> props;

  /// 重复次数。
  final int runs;

  /// 是否等播到结尾。
  final bool toEnd;

  /// 开文件前是否先等 mpv 的 vo 选项从 null 切到 gpu（渲染面真正接上）。
  final bool waitVo;

  /// 创建 Player 之前先静置的毫秒数（让上一轮的解码器充分释放）。
  final int coolMs;
}

/// 全部用例。
const cases = [
  Case('vp8_ndk', 'vp8.webm', {'vd-lavc-o': 'ndk_codec=1'}, 14),
];

/// 入口。
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    MovaEngine.ensureInitialized();
    runApp(MaterialApp(
        home: Scaffold(
            body: ValueListenableBuilder<MovaApi?>(
                valueListenable: screen,
                builder: (_, api, child) =>
                    api == null ? const Center(child: Text('4abi smoke')) : MovaPlayer(api: api, skin: const MovaMinimalSkin())))));
    await WidgetsBinding.instance.endOfFrame;
    Timer.periodic(const Duration(milliseconds: 100), (t) {
      final now = DateTime.now();
      final g = now.difference(lastBeat).inMilliseconds;
      if (g > maxGapMs) maxGapMs = g;
      lastBeat = now;
    });
    mark('BEGIN', {});
    for (final c in cases) {
      for (var r = 0; r < c.runs; r++) {
        try {
          await probe(c, r);
        } catch (e, s) {
          mark('SCRIPT_ERROR', {'case': c.name, 'error': '$e', 'stack': '$s'});
        }
      }
    }
    mark('END', {});
  }, (e, s) => mark('UNCAUGHT', {'error': '$e'}));
}

/// 读 mpv 属性，失败返回 null。
Future<String?> prop(NativePlayer n, String k) async {
  try {
    return await n.getProperty(k).timeout(const Duration(seconds: 2));
  } catch (_) {
    return null;
  }
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

/// 跑一个用例的一次：开样本，观察，输出 RESULT。
Future<void> probe(Case c, int run) async {
  if (c.coolMs > 0) await Future<void>.delayed(Duration(milliseconds: c.coolMs));
  maxGapMs = 0;
  var attempts = 0;
  var logged = 0;
  var opens = 0;
  var voAttached = false;
  final player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.v));
  player.stream.log.listen((l) {
    if (l.text.contains('Attempting next decoding method')) attempts++;
    if (l.text.contains('Opening decoder') && l.prefix == 'vd') opens++;
    if (l.text.contains('vo/gpu') || l.prefix == 'vo/gpu') voAttached = true;
    // 抓解码相关日志（每次上限 400 行），用于定位卡死。
    if (logged < 400 && RegExp(r'vd|codec|decod|mediacodec|ndk|lavc|error|fail|hwdec|video', caseSensitive: false).hasMatch('${l.prefix} ${l.text}')) {
      logged++;
      mark('MPVLOG', {'case': c.name, 'run': run, 'line': '${l.level}/${l.prefix}: ${l.text.trim()}'});
    }
  });
  final kernel = MovaMpvKernel(player: player, lazyVideo: true);
  final api = createMovaEngine(kernel: kernel, preciseFirstFrame: true);
  final native = player.platform as NativePlayer;
  final errTexts = <String>[];
  var errors = 0;
  final sub = api.events.listen((e) {
    if (e is MovaErrorEvent) {
      errors++;
      if (errTexts.length < 3) errTexts.add('${e.error}');
    }
  });
  var completed = false;
  player.stream.completed.listen((v) {
    if (v) completed = true;
  });
  screen.value = api;
  await WidgetsBinding.instance.endOfFrame;
  for (final e in c.props.entries) {
    await native.setProperty(e.key, e.value);
  }
  String? voBefore;
  var voWaitMs = 0;
  if (c.waitVo) {
    final w0 = DateTime.now();
    while (DateTime.now().difference(w0).inMilliseconds < 5000) {
      voBefore = await prop(native, 'vo');
      if (voBefore != null && voBefore != 'null' && voBefore.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    voWaitMs = DateTime.now().difference(w0).inMilliseconds;
  }
  final t0 = DateTime.now();
  Object? openErr;
  mark('OPEN', {'case': c.name, 'run': run});
  try {
    await api.open(MovaSource('$base/${c.file}?t=${t0.millisecondsSinceEpoch}')).timeout(const Duration(seconds: 15));
  } catch (e) {
    openErr = e;
  }
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!api.state.rendered && errors == 0 && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  final ttff = api.state.rendered ? DateTime.now().difference(t0).inMilliseconds : null;
  final p1 = player.state.position.inMilliseconds;
  List<String> top = [];
  var pos1s = -1;
  String? hw;
  if (c.toEnd) {
    hw = await prop(native, 'hwdec-current');
    final end = DateTime.now().add(const Duration(seconds: 90));
    while (!completed && errors == 0 && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  } else {
    await Future<void>.delayed(const Duration(seconds: 1));
    pos1s = player.state.position.inMilliseconds;
    top = await topThreads(3000);
    hw = await prop(native, 'hwdec-current');
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  final p2 = player.state.position.inMilliseconds;
  mark('RESULT', {
    'case': c.name,
    'run': run,
    'openErr': openErr?.toString(),
    'rendered': api.state.rendered,
    'ttffMs': ttff,
    'size': '${api.state.width}x${api.state.height}',
    'posStartMs': p1,
    'posAt1sMs': pos1s,
    'posEndMs': p2,
    'completed': completed,
    'errors': errors,
    'errTexts': errTexts,
    'attemptNext': attempts,
    'opens': opens,
    'voAttached': voAttached,
    'voWaitMs': voWaitMs,
    'voBefore': voBefore,
    'maxHeartbeatGapMs': maxGapMs,
    'topThreads': top,
    'videoCodec': await prop(native, 'video-codec'),
    'hwdecCurrent': hw,
  });
  await sub.cancel();
  screen.value = null;
  await WidgetsBinding.instance.endOfFrame;
  await api.dispose();
}
