import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'verify_auto/auto_kit.dart';
import 'verify_auto/cp3_harness.dart';
import 'verify_auto/cp3_pages_auto.dart';

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
    final scene = parts[0].replaceFirst('cp3-', '');
    final scripts = <String, Cp3Script>{
      'cp1gap': runCp1gap,
      'fullscreen': runFullscreen,
      'theme': runTheme,
      'headers': runHeaders,
      'feedplayer': runFeedplayer,
      'c04chrome': runC04chrome,
    };
    cp3Main(scene, scripts[scene]!, automatic: true);
  } finally {
    client.close(force: true);
  }
}
