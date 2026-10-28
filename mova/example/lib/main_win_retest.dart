import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:mova/src/platform_impl/mpv_event_backend_ffi.dart';

final screen = ValueNotifier<MovaApi?>(null);
final label = ValueNotifier<String>('Windows release verification');
final rows = <Map<String, Object?>>[];
final timer = Stopwatch()..start();
String status = 'idle';
int iteration = -1;
String mode = '';
String build = const String.fromEnvironment('WIN_BUILD', defaultValue: 'fixed');

/// Records complete native and API evidence; clock labels are diagnostic only.
///
/// 保存完整原生/API证据；时钟只标注时间线，不用于续播判定。
void mark(String kind, Map<String, Object?> data) {
  rows.add({'seq': rows.length, 'ms': timer.elapsedMilliseconds,
    'kind': kind, 'build': build, 'mode': mode, 'iteration': iteration, ...data});
}

/// Polls a real condition with a safety deadline, never a playback-time estimate.
///
/// 用真实条件等待，截止时间仅防止挂死，不估算播放进度。
Future<void> until(FutureOr<bool> Function() predicate, {int seconds = 20}) async {
  final end = timer.elapsedMilliseconds + seconds * 1000;
  while (!await predicate()) {
    if (timer.elapsedMilliseconds > end) throw TimeoutException('native condition');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Starts a Windows-only release command host and visible player surface.
///
/// 启动Windows release命令接口及真实播放画面。
void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    MovaEngine.ensureInitialized();
    runApp(MaterialApp(home: Scaffold(body: Column(children: [
      ValueListenableBuilder<String>(valueListenable: label,
        builder: (_, text, child) => Text('$build — $text', style: const TextStyle(fontSize: 22))),
      Expanded(child: ValueListenableBuilder<MovaApi?>(valueListenable: screen,
        builder: (_, api, child) => api == null ? const Center(child: Text('Ready')) :
          MovaPlayer(api: api, skin: const MovaMinimalSkin()))),
    ]))));
    unawaited(serve());
  }, (e, s) => mark('UNCAUGHT', {'error': '$e', 'stack': '$s'}));
}

/// Runs isolated commands, exposing the complete journal for durable host saves.
///
/// 运行隔离命令，向宿主提供完整日志以便持续落盘。
Future<void> serve() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18093);
  await for (final req in server) {
    if (req.uri.path == '/run' && status != 'running') {
      status = 'running';
      unawaited(run(req.uri.queryParameters));
    }
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode({'status': status, 'pid': pid, 'build': build, 'rows': rows}));
    await req.response.close();
  }
}

/// Dispatches probes and retains exceptions as evidence.
///
/// 分派验证任务并将异常保留为证据。
Future<void> run(Map<String, String> args) async {
  try {
    mark('BEGIN', {'args': args});
    switch (args['case']) {
      case 'dispose': await disposeProbe();
      case 'zoom': await zoomProbe(args['value']);
      case 'hls': await hlsProbe(args['mode'] ?? 'normal', int.parse(args['count'] ?? '34'));
      case 'clear': await clear();
    }
    status = 'done';
  } catch (e, s) {
    mark('SCRIPT_ERROR', {'error': '$e', 'stack': '$s'});
    status = 'error';
  }
  mark('END', {'status': status});
}

/// Unmounts the surface before disposing only its owned engine.
///
/// 卸载画面后仅销毁当前验证引擎。
Future<void> clear() async {
  final a = screen.value;
  screen.value = null;
  await WidgetsBinding.instance.endOfFrame;
  if (a != null) await a.dispose().timeout(const Duration(seconds: 20));
}

/// Verifies each of two disposal calls on audio-only normal and enabled proxies.
///
/// 对无界面普通引擎和已启用代理逐次验证两次销毁调用。
Future<void> disposeProbe() async {
  for (final proxy in [false, true]) {
    mode = proxy ? 'cutover' : 'normal';
    MovaEngine factory() => createMovaEngine(audioOnly: true,
      options: MovaOpts(cutover: MovaCutoverConfig(enabled: proxy)));
    final MovaApi a = proxy ? MovaCutoverEngine(engineFactory: factory) : factory();
    final accepted = await a.open(const MovaSource('http://127.0.0.1:18094/vod.mp4'));
    await until(() => a.state.duration > Duration.zero);
    mark('DISPOSE_OPEN', {'accepted': accepted, 'audioOnly': a.renderHandle == null,
      'duration': a.state.duration.inMilliseconds});
    for (var call = 1; call <= 2; call++) {
      mark('DISPOSE_CALL', {'call': call});
      try {
        await a.dispose().timeout(const Duration(seconds: 20));
        mark('DISPOSE_RETURN', {'call': call, 'return': 'void completed', 'exception': null});
      } catch (e, s) { mark('DISPOSE_RETURN', {'call': call, 'exception': '$e', 'stack': '$s'}); }
    }
  }
}

/// Reads zoom from a real mounted player, including runtime NaN.
///
/// 从真实挂树播放器读回缩放值，包含运行时NaN。
Future<void> zoomProbe(String? value) async {
  mode = 'zoom';
  if (screen.value == null) {
    final a = createMovaEngine(preciseFirstFrame: true);
    screen.value = a;
    await WidgetsBinding.instance.endOfFrame;
    await a.open(const MovaSource('http://127.0.0.1:18094/vod.mp4'));
    await until(() => a.state.rendered && a.state.width > 0);
    await a.pause();
  }
  final a = screen.value!;
  final input = double.parse(value ?? '1');
  await a.setZoom(input);
  await WidgetsBinding.instance.endOfFrame;
  label.value = 'A12 input=$input state.zoom=${a.state.zoom}';
  mark('ZOOM', {'input': '$input', 'zoom': a.state.zoom, 'rendered': a.state.rendered,
    'width': a.state.width, 'height': a.state.height, 'handle': '${a.renderHandle.runtimeType}'});
}

/// Measures HLS resumption from RESTART/property reads, with actual video mounted.
///
/// 挂真实画面，用RESTART和原生属性读回测量HLS续播。
Future<void> hlsProbe(String selectedMode, int count) async {
  await clear();
  mode = selectedMode;
  final paused = mode == 'paused';
  final proxy = mode == 'cutover';
  late Player player;
  late MovaMpvKernel kernel;
  MovaEngine factory() {
    player = Player();
    kernel = MovaMpvKernel(player: player, lazyVideo: true, observeNativeEvents: true,
      backendFactory: (n, address) => createFfiMpvEventBackend(n, address, pollInDebug: false));
    return createMovaEngine(kernel: kernel, preciseFirstFrame: true,
      options: MovaOpts(cutover: MovaCutoverConfig(enabled: proxy)));
  }
  final MovaApi a = proxy ? MovaCutoverEngine(engineFactory: factory) : factory();
  final native = player.platform as NativePlayer;
  Future<int> position() async => ((double.tryParse(await native.getProperty('time-pos')) ?? -1) * 1000).round();
  var restarts = <int>[];
  var pending = Future<void>.value();
  final eventSub = a.events.listen((e) => mark('EVENT', {'type': '${e.runtimeType}',
    'position': player.state.position.inMilliseconds, 'duration': a.state.duration.inMilliseconds,
    'playing': a.state.playing, 'intent': a.state.playbackIntent, 'rendered': a.state.rendered,
    if (e is MovaErrorEvent) 'error': '${e.error}'}));
  final progressSub = player.stream.position.listen((p) => mark('NATIVE_PROGRESS', {'position': p.inMilliseconds}));
  final sub = kernel.playbackRestarts.listen((_) {
    final run = iteration;
    pending = pending.then((_) async {
      final p = await position();
      restarts.add(p);
      mark('HLS_RESTART', {'run': run, 'position': p, 'path': await native.getProperty('path'),
        'pause': await native.getProperty('pause')});
    });
  });
  screen.value = a;
  await WidgetsBinding.instance.endOfFrame;
  await a.open(MovaSource('http://127.0.0.1:18094/hls/master.m3u8?t=${DateTime.now().microsecondsSinceEpoch}'));
  await until(() async => a.state.rendered && await position() >= 8000, seconds: 40);
  await a.loadQualities();
  await until(() => a.state.qualities.where((q) => !q.isAuto).length >= 2);
  final variants = a.state.qualities.where((q) => !q.isAuto).toList()
    ..sort((a, b) => b.label.compareTo(a.label));
  mark('HLS_QUALITIES', {'qualities': variants.map((q) => {'label': q.label, 'uri': q.uri}).toList(),
    'cutoverEnabled': a.options.cutover.enabled, 'video': true});
  if (paused) await a.pause();
  for (var i = 0; i < count; i++) {
    iteration = i;
    // Reset far from EOF; every target must first have real native progress >=8s.
    // 远离EOF重设进度；每次target须先由原生读回确认至少8秒。
    if (await position() > 20000 || await position() < 8000) {
      await a.seek(const Duration(seconds: 9));
      await until(() async => (await position() - 9000).abs() <= 250);
    }
    // Wait until the engine's source progress stream catches the native readback.
    // 等引擎所读进度与原生值对齐，避免旧锚点造成验证工具误报。
    await until(() async => (player.state.position.inMilliseconds - await position()).abs() <= 100);
    await pending;
    restarts = <int>[];
    final target = await position();
    final q = variants[i % 2];
    mark('HLS_SWITCH', {'target': target, 'quality': q.label, 'uri': q.uri,
      'streamPosition': player.state.position.inMilliseconds, 'pause': await native.getProperty('pause')});
    label.value = 'F3 $mode ${i + 1}/$count target=$target ${q.label}';
    await a.switchQuality(q);
    var landed = -1;
    try {
      await until(() async {
        await pending;
        final matches = restarts.where((p) => (p - target).abs() <= 500);
        if (matches.isNotEmpty) { landed = matches.first; return true; }
        return false;
      }, seconds: 6);
    } on TimeoutException { /* Failure is retained with the complete journal. */ }
    var continued = await position();
    var continues = false;
    if (!paused && landed >= 0) {
      try {
        await until(() async { continued = await position(); return continued >= landed + 250; }, seconds: 6);
        continues = true;
      } on TimeoutException { continues = false; }
    } else if (paused) {
      continues = (continued - target).abs() <= 500 && await native.getProperty('pause') == 'yes';
    }
    await pending;
    mark('HLS_RESULT', {'target': target, 'landed': landed, 'continued': continued,
      'restarts': List<int>.of(restarts), 'resumed': landed >= 0, 'continuedOk': continues,
      'pass': landed >= 0 && continues, 'pause': await native.getProperty('pause'),
      'path': await native.getProperty('path')});
  }
  iteration = -1;
  await pending;
  await sub.cancel(); await eventSub.cancel(); await progressSub.cancel();
  await clear();
}
