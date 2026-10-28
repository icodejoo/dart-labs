import 'package:flutter/material.dart';

/// 鸿蒙 Flutter 最小验证应用入口。
void main() => runApp(const HelloApp());

/// 根组件：只放一个文本和一个计数按钮。
class HelloApp extends StatelessWidget {
  /// 创建根组件。
  const HelloApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: HelloPage());
}

/// 首页：显示点击次数。
class HelloPage extends StatefulWidget {
  /// 创建首页。
  const HelloPage({super.key});

  @override
  State<HelloPage> createState() => _HelloPageState();
}

class _HelloPageState extends State<HelloPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Hello HarmonyOS Flutter  count=$_count', style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => setState(() => _count++), child: const Text('+1')),
            ],
          ),
        ),
      );
}
