// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// TLS 严格校验真机验证：关闭/开启无 CA/开启带 CA 三种配置 x 自签/过期/合法证书三类源。
///
/// 本机服务见 scratchpad 的 srv.py（`adb reverse tcp:8443`=自签 HTTPS）。
/// 判据基于事件：出现 firstFrame 即"可播"，出现 sessionEnd 即结束并取其原因。
/// 跑法：`flutter run --release -d <设备> -t lib/main_tls_verify.dart`，用 logcat 取 `TLSV` 行。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaMpvKernel.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('tls verify')))));
  Future<void>.delayed(const Duration(seconds: 1), _run);
}

/// 系统 CA 目录（Android）。
const String kSysCaDir = '/system/etc/security/cacerts';

/// 场景观察窗口。
const Duration kWindow = Duration(seconds: 12);

/// 输出一行带统一标签的日志。
void _out(String m) => print('TLSV $m');

/// 防缓存 URL。
String _t(String u) => '$u${u.contains('?') ? '&' : '?'}t=${DateTime.now().microsecondsSinceEpoch}';

/// 把系统 CA 目录里每个文件的 PEM 块抽出来拼成一个 bundle，返回路径与证书数。
Future<(String, int)> _buildBundle() async {
  final buf = StringBuffer();
  var n = 0;
  final re = RegExp(r'-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----');
  for (final f in Directory(kSysCaDir).listSync().whereType<File>()) {
    for (final m in re.allMatches(await f.readAsString())) {
      buf.writeln(m.group(0));
      n++;
    }
  }
  final out = File('${Directory.systemTemp.path}/mova_ca_bundle.pem');
  await out.writeAsString(buf.toString());
  return (out.path, n);
}

/// 跑一个场景：[tlsVerify]/[ca] 为配置，[url] 为源。
Future<void> _once(String tag, bool tlsVerify, String? ca, String url) async {
  final events = <MovaReportEvent>[];
  final engine = createMovaEngine(
    audioOnly: true,
    tlsVerify: tlsVerify,
    tlsCaFile: ca,
    options: const MovaOpts(report: MovaReportConfig(qoe: true)),
    reporter: MovaCallbackReporter(events.add),
  );
  final t0 = DateTime.now();
  int ms(DateTime d) => d.difference(t0).inMilliseconds;
  try {
    await engine.open(MovaSource(_t(url)));
  } catch (e) {
    _out('$tag OPEN_THREW $e');
  }
  final deadline = t0.add(kWindow);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (events.any((e) => e.name == MovaReportName.sessionEnd)) break;
    // 已播到可观察位置就收工，不必等满窗口。
    if (events.any((e) => e.name == MovaReportName.firstFrame)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      break;
    }
  }
  await engine.dispose();
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final played = events.any((e) => e.name == MovaReportName.firstFrame);
  _out('$tag RESULT played=$played');
  for (final ev in events) {
    final n = ev.name;
    if (n == MovaReportName.play || n == MovaReportName.pause) continue;
    _out('$tag REPORT +${ms(ev.at)}ms ${n.value} ${ev.params}');
  }
}

/// 主流程。
Future<void> _run() async {
  final (bundle, count) = await _buildBundle();
  _out('START bundle=$bundle certs=$count');
  final urls = <String, String>{
    'selfsigned_local': 'https://127.0.0.1:8443/good.m4a',
    'expired_badssl': 'https://expired.badssl.com/x.mp3',
    'legit_srg': 'https://stream.srg-ssr.ch/m/rsj/mp3_128',
    'legit_mux_hls': 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  };
  final configs = <String, (bool, String?)>{
    'off': (false, null),
    'on_noca': (true, null),
    'on_sysca': (true, bundle),
  };
  for (final c in configs.entries) {
    for (final u in urls.entries) {
      await _once('${c.key}/${u.key}', c.value.$1, c.value.$2, u.value);
    }
  }
  _out('ALL_DONE');
}
