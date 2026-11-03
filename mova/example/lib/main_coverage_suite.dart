import 'main_cp1_wakeswap_verify.dart' as cp1_wakeswap;
import 'main_cp1_edgepause_verify.dart' as cp1_edgepause;
import 'main_cp1_errclass_verify.dart' as cp1_errclass;
import 'main_cp1_probe_verify.dart' as cp1_probe;
import 'main_cp1_manageauto_verify.dart' as cp1_manageauto;
import 'main_cp1_bblock_verify.dart' as cp1_bblock;
import 'main_cp1_pool_verify.dart' as cp1_pool;
import 'main_cp1_danmaku_verify.dart' as cp1_danmaku;
import 'main_cp1_recovery_verify.dart' as cp1_recovery;
import 'main_cp1_dispose120_verify.dart' as cp1_dispose120;
import 'main_coverage_gap.dart' as gap;
import 'main_rerun6_coverage_api.dart' as rerun6;
import 'main_cp0_p02_verify.dart' as cp0_p02;
import 'verify_auto/s00e_trace.dart';
import 'main_cp0_pod2_verify.dart' as cp0_pod2;
import 'main_cp0_bgpause_verify.dart' as cp0_bgpause;
import 'main_cp0_pauseload_verify.dart' as cp0_pauseload;
import 'main_cp0_timeshift_verify.dart' as cp0_timeshift;
import 'main_cp0_pageview_verify.dart' as cp0_pageview;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'main_coverage_api.dart' as api;
import 'verify_auto/he_auto.dart' as he;
import 'verify_auto/keep_alive_auto.dart' as keep_alive;
import 'verify_auto/auto_kit.dart' as kit;
import 'main_q13_mute_verify.dart' as mute;
import 'main_quality_switch_verify.dart' as quality;
import 'main_observe_event_verify2.dart' as pump;
import 'main_subtitle_formats_probe.dart' as subtitles;
import 'main_review_fixes_verify2.dart' as review;
import 'main_hwdec_matrix_verify.dart' as hwdec;

/// Selects an existing verification page using the local host, keeping its
/// original event-based assertions intact.
///
/// 由本地服务选择已有验证页，复用原始事件判据。
Future<void> main() async {
  S00eBinding.ensureTracing();
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
  kit.coverageShotHandshake = parts.length > 3 && parts[3] == 'shots';
  MovaEngine.ensureInitialized();
  switch (parts.first) {
    case 'cp1-wakeswap': cp1_wakeswap.main();
    case 'cp1-edgepause': cp1_edgepause.main();
    case 'cp1-errclass': cp1_errclass.main();
    case 'cp1-probe': cp1_probe.main();
    case 'cp1-manageauto': cp1_manageauto.main();
    case 'cp1-bblock': cp1_bblock.main();
    case 'cp1-pool': cp1_pool.main();
    case 'cp1-danmaku': cp1_danmaku.main();
    case 'cp1-recovery': cp1_recovery.main();
    case 'cp1-dispose120': cp1_dispose120.main();
    case 'gap': gap.main();
    case 'rerun6': rerun6.main();

    case 'cp0-p02': cp0_p02.main();
    case 'cp0-pod2': cp0_pod2.main();
    case 'cp0-bgpause': cp0_bgpause.main();
    case 'cp0-pauseload': cp0_pauseload.main();
    case 'cp0-timeshift': cp0_timeshift.main();
    case 'cp0-pageview': cp0_pageview.main();
    case 'he': runApp(const MaterialApp(home: he.HeAutoPage()));
    case 'keepAlive': runApp(const MaterialApp(home: keep_alive.KeepAliveAutoPage()));
    case 'mute': mute.main();
    case 'quality': quality.main();
    case 'pump': pump.main();
    case 'subtitles': subtitles.main();
    case 'review': review.main([]);
    case 'hwdec': hwdec.main();
    default: api.main();
  }
}
