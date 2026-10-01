// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:mova/src/platform_impl/mpv_event_backend_ffi.dart';

/// QoE 错误 prefix 分类真机验证：断网/坏 TLS/垃圾内容/截断/断流/重置。
///
/// 本机服务见 scratchpad 的 srv.py（`adb reverse tcp:8101`=HTTP、`tcp:8443`=自签 HTTPS）。
/// 断网由宿主脚本监听 logcat 的 `EPV CMD netoff|neton` 后执行 `adb shell svc`，
/// 本页轮询真实连通性确认切换生效再继续。
/// 跑法：`flutter build apk --release -t lib/main_error_prefix_verify.dart`，由宿主脚本驱动。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaMpvKernel.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('error prefix verify')))));
  Future<void>.delayed(const Duration(seconds: 1), _run);
}

/// 本机 HTTP 前缀。
const String kHttp = 'http://127.0.0.1:8101';

/// 本机自签 HTTPS 前缀。
const String kHttps = 'https://127.0.0.1:8443';

/// 每个场景重复次数。
const int kRepeats = 3;

/// 远程直播流（HTTP），用于断网中途场景。
const String kLiveHttp = 'http://icecast.radiofrance.fr/franceinter-midfi.mp3';

/// 远程直播流（HTTPS），用于开播前断网场景。
const String kLiveHttps = 'https://stream.srg-ssr.ch/m/rsj/mp3_128';

/// 仅跑名称前缀匹配的普通场景（`--dart-define=ONLY=tls`），空表示全跑。
const String kOnly = String.fromEnvironment('ONLY');

/// 输出一行带统一标签的日志。
void _out(String m) => print('EPV $m');

/// 防缓存 URL。
String _t(String u) => '$u${u.contains('?') ? '&' : '?'}t=${DateTime.now().microsecondsSinceEpoch}';

/// 探测公网是否可达（真实 TCP 连接，非墙钟）。
Future<bool> _online() async {
  try {
    final s = await Socket.connect('8.8.8.8', 53, timeout: const Duration(seconds: 2));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// 请求宿主切换网络，并轮询到真实状态一致为止。
Future<void> _setNet(bool on) async {
  _out('CMD ${on ? 'neton' : 'netoff'}');
  for (var i = 0; i < 90; i++) {
    await Future<void>.delayed(const Duration(seconds: 1));
    if (await _online() == on) {
      _out('NET ${on ? 'online' : 'offline'} confirmed after ${i + 1}s');
      return;
    }
  }
  _out('NET switch TIMEOUT want=$on');
}

/// 截断过长文本。
String _cut(Object o, [int n = 160]) {
  final s = o.toString().replaceAll('\n', ' ');
  return s.length > n ? '${s.substring(0, n)}...' : s;
}

/// 单次运行：返回后已 dispose。[waitFor] 为观察窗口，[midAction] 在首帧后执行。
Future<void> _once(
  String tag,
  int run,
  String url, {
  required Duration waitFor,
  Future<void> Function()? midAction,
}) async {
  final events = <MovaReportEvent>[];
  final k = MovaMpvKernel(
    audioOnly: true,
    observeQoeSignals: true,
    backendFactory: (n, a) => createFfiMpvEventBackend(n, a, pollInDebug: false),
  );
  final engine = createMovaEngine(
    kernel: k,
    audioOnly: true,
    options: const MovaOpts(report: MovaReportConfig(qoe: true, minStall: Duration(milliseconds: 200))),
    reporter: MovaCallbackReporter(events.add),
  );
  final t0 = DateTime.now();
  int ms(DateTime d) => d.difference(t0).inMilliseconds;
  final logSub = k.logs.listen((l) => _out('$tag#$run LOG +${ms(DateTime.now())}ms [${l.prefix}/${l.level}] ${_cut(l.text)}'));
  var mid = false;
  final evSub = engine.events.listen((e) {
    if (e is MovaErrorEvent) _out('$tag#$run ENGINE_ERROR +${ms(DateTime.now())}ms ${_cut(e.error)}');
  });
  try {
    await engine.open(MovaSource(_t(url)));
  } catch (e) {
    _out('$tag#$run OPEN_THREW ${_cut(e)}');
  }
  final deadline = t0.add(waitFor);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mid && midAction != null && events.any((e) => e.name == MovaReportName.firstFrame)) {
      mid = true;
      _out('$tag#$run MID_ACTION at +${ms(DateTime.now())}ms');
      await midAction();
    }
    // 会话已结束则提前收工。
    if (events.any((e) => e.name == MovaReportName.sessionEnd)) break;
  }
  final endedEarly = events.any((e) => e.name == MovaReportName.sessionEnd);
  await engine.dispose();
  await Future<void>.delayed(const Duration(milliseconds: 500));
  await logSub.cancel();
  await evSub.cancel();
  _out('$tag#$run SUMMARY endedBeforeDispose=$endedEarly midActionFired=$mid');
  for (final ev in events) {
    final n = ev.name;
    if (n == MovaReportName.play || n == MovaReportName.pause) continue;
    _out('$tag#$run REPORT +${ms(ev.at)}ms ${n.value} ${_cut(ev.params, 260)}');
  }
}

/// 主流程。
Future<void> _run() async {
  _out('START online=${await _online()}');
  const short = Duration(seconds: 10);
  final plain = <String, String>{
    'baseline_good': '$kHttp/good.m4a',
    'http404': '$kHttp/nope.m4a',
    'http403': '$kHttp/s403',
    'http500': '$kHttp/s500',
    'garbage200': '$kHttp/garbage.mp4',
    'html200': '$kHttp/html.mp4',
    'empty200': '$kHttp/empty.mp4',
    'truncated_nomoov': '$kHttp/truncmoov.mp4',
    'refused': 'http://127.0.0.1:9/x.mp3',
    'dns_fail': 'http://nonexistent-host-mova.invalid/x.mp3',
    'tls_selfsigned_local': '$kHttps/good.m4a',
    'tls_expired_root': 'https://expired.badssl.com/',
    'tls_selfsigned_badssl_root': 'https://self-signed.badssl.com/',
    'tls_wronghost_root': 'https://wrong.host.badssl.com/',
    'tls_expired': 'https://expired.badssl.com/x.mp3',
    'tls_selfsigned_badssl': 'https://self-signed.badssl.com/x.mp3',
    'tls_wronghost': 'https://wrong.host.badssl.com/x.mp3',
  };
  for (final e in plain.entries) {
    if (kOnly.isNotEmpty && !e.key.startsWith(kOnly)) continue;
    for (var i = 1; i <= kRepeats; i++) {
      await _once(e.key, i, e.value, waitFor: short);
    }
  }
  if (kOnly.isNotEmpty) {
    _out('ALL_DONE');
    return;
  }
  // 中途断流：服务器发一部分后正常关闭 / RST。
  for (final tag in ['cutmid', 'reset']) {
    for (var i = 1; i <= kRepeats; i++) {
      await _once(tag, i, '$kHttp/$tag.m4a', waitFor: const Duration(seconds: 15));
    }
  }
  // 开播前断网。
  for (var i = 1; i <= kRepeats; i++) {
    await _setNet(false);
    await _once('netoff_before_first_frame', i, kLiveHttps, waitFor: const Duration(seconds: 15));
    await _setNet(true);
  }
  // 播放中途断网（直播流不会被预读缓存吃光）。
  for (var i = 1; i <= kRepeats; i++) {
    await _once('netoff_mid_play', i, kLiveHttp, waitFor: const Duration(seconds: 45), midAction: () async {
      await Future<void>.delayed(const Duration(seconds: 2));
      await _setNet(false);
    });
    await _setNet(true);
  }
  _out('ALL_DONE');
}
