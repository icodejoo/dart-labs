import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'main_host_ergonomics_verify.dart' as he;
import 'main_standby_verify.dart' as standby;
import 'main_q13_mute_verify.dart' as q13;
import 'main_qoe_verify.dart' as qoe;
import 'main_qoe_video_verify.dart' as qoeVideo;
import 'main_seamless_swap_verify.dart' as swap;
import 'main_ad_orchestration_verify.dart' as ads;
import 'main_quality_switch_verify.dart' as quality;
import 'main_subtitle_formats_probe.dart' as subtitle;
import 'main_tls_matrix_verify.dart' as tls;
import 'main_whep_verify.dart' as whep;
import 'verify_auto/auto_kit.dart';

/// Runs exactly one existing feature page per process, chosen by local control.
///
/// 每个进程只运行一个现有功能验证页，通过本地控制服务选择。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse('http://127.0.0.1:18082/config'));
  final resp = await req.close();
  final config = jsonDecode(await resp.transform(utf8.decoder).join()) as Map<String, dynamic>;
  client.close(force: true);
  coverageOnlyOverride = config['only'] as String?;
  coverageRunsOverride = config['runs'] as int? ?? 5;
  switch (config['page']) {
    case 'he': he.main();
    case 'standby': standby.main();
    case 'q13': q13.main();
    case 'qoe': qoe.main();
    case 'qoeVideo': qoeVideo.main();
    case 'swap': swap.main();
    case 'ads': ads.main();
    case 'quality': quality.main();
    case 'subtitle': subtitle.main();
    case 'tls': tls.main();
    case 'whep': whep.main();
    default: throw ArgumentError('Unknown coverage page ${config['page']}');
  }
}
