// Diagnostic-only dispatcher, usable with the archived CP0 product library.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'verify_auto/auto_kit.dart';
import 'verify_auto/keep_alive_auto.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('http://127.0.0.1:18082/group'));
    final parts = (await utf8.decoder.bind(await request.close()).join()).trim().split('|');
    if (parts.first != 'keepAlive') throw StateError('CP0 keepAlive dispatcher only');
    coverageOnlyOverride = parts[1];
    coverageRunsOverride = int.parse(parts[2]);
    coverageShotHandshake = parts.length > 3 && parts[3] == 'shots';
  } finally {
    client.close();
  }
  MovaEngine.ensureInitialized();
  runApp(const MaterialApp(home: KeepAliveAutoPage()));
}
