import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'verify_auto/auto_kit.dart';
import 'verify_auto/cp0_harness.dart';
import 'verify_auto/cp0_p02_auto.dart';
import 'verify_auto/cp0_pod2_auto.dart';
import 'verify_auto/cp0_bgpause_auto.dart';
import 'verify_auto/cp0_pauseload_auto.dart';
import 'verify_auto/cp0_timeshift_auto.dart';
import 'verify_auto/cp0_pageview_auto.dart';
import 'verify_auto/cp0_autotier_auto.dart';

/// Small release dispatcher used only when running CP0 batches in isolation.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final client=HttpClient();
  try {
    final request=await client.getUrl(Uri.parse('http://127.0.0.1:18082/group'));
    final parts=(await utf8.decoder.bind(await request.close()).join()).trim().split('|');
    coverageRunsOverride=int.parse(parts[2]);
    final scene=parts[0].replaceFirst('cp0-','');
    final scripts=<String,Cp0Script>{'p02':runP02,'pod2':runPod2,'bgpause':runBgPause,
      'pauseload':runPauseLoad,'timeshift':runTimeshift,'pageview':runPageView,'autotier':runAutoTier};
    cp0Main(scene,scripts[scene]!,automatic:true);
  } finally {client.close();}
}
