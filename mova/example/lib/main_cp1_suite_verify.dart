import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'verify_auto/auto_kit.dart';
import 'verify_auto/cp1_harness.dart';
import 'verify_auto/cp1_wakeswap_auto.dart';
import 'verify_auto/cp1_edgepause_auto.dart';
import 'verify_auto/cp1_errclass_auto.dart';
import 'verify_auto/cp1_probe_auto.dart';
import 'verify_auto/cp1_manageauto_auto.dart';
import 'verify_auto/cp1_bblock_auto.dart';
import 'verify_auto/cp1_pool_auto.dart';
import 'verify_auto/cp1_danmaku_auto.dart';

/// Small release dispatcher used only when running CP1 batches in isolation.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:18082/group'),
    );
    final parts = (await utf8.decoder.bind(await request.close()).join())
        .trim()
        .split('|');
    coverageRunsOverride = int.parse(parts[2]);
    final scene = parts[0].replaceFirst('cp1-', '');
    final scripts = <String, Cp1Script>{
      'wakeswap': runWakeswap,
      'edgepause': runEdgepause,
      'errclass': runErrclass,
      'probe': runProbe,
      'manageauto': runManageauto,
      'bblock': runBblock,
      'pool': runPool,
      'danmaku': runDanmaku,
    };
    cp1Main(scene, scripts[scene]!, automatic: true);
  } finally {
    client.close();
  }
}
