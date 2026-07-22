import 'package:cacheman/cacheman.dart';
import 'package:flutter/material.dart';
import 'demo_shell.dart';

late Cacheman cache;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cache = Cacheman();
  await cache.ensureInitialized();
  runApp(const CachemanDemoApp());
}

class CachemanDemoApp extends StatelessWidget {
  const CachemanDemoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'cacheman demo',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const DemoShell(),
      );
}
