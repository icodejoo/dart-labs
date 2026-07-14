import 'package:flutter/material.dart';
import 'demo_shell.dart';

void main() => runApp(const StompsocketDemoApp());

class StompsocketDemoApp extends StatelessWidget {
  const StompsocketDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_stompsocket demo',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const DemoShell(),
    );
  }
}
