import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'main_coverage_api.dart' as api;
import 'verify_auto/he_auto.dart' as he;
import 'verify_auto/standby_auto.dart' as standby;
import 'verify_auto/auto_kit.dart' as kit;
import 'main_q13_mute_verify.dart' as mute;
import 'main_quality_switch_verify.dart' as quality;
import 'main_observe_event_verify2.dart' as pump;
import 'main_subtitle_formats_probe.dart' as subtitles;
import 'main_review_fixes_verify2.dart' as review;

/// Selects an existing verification page using the local host, keeping its
/// original event-based assertions intact.
///
/// 由本地服务选择已有验证页，复用原始事件判据。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final client = HttpClient();
  var group = 'api';
  try {
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:18082/group'));
    group = (await utf8.decoder.bind(await req.close()).join()).trim();
  } finally {
    client.close();
  }
  // ignore: avoid_print
  print('COVERAGE_SUITE group=$group');
  final parts = group.split('|');
  kit.coverageOnlyOverride = parts.length > 1 ? parts[1] : '';
  kit.coverageRunsOverride = parts.length > 2 ? int.parse(parts[2]) : 5;
  MovaEngine.ensureInitialized();
  switch (parts.first) {
    case 'he': runApp(const MaterialApp(home: he.HeAutoPage()));
    case 'standby': runApp(const MaterialApp(home: standby.StandbyAutoPage()));
    case 'mute': mute.main();
    case 'quality': quality.main();
    case 'pump': pump.main();
    case 'subtitles': subtitles.main();
    case 'review': review.main([]);
    default: api.main();
  }
}
