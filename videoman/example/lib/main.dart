import 'package:flutter/material.dart';
import 'package:videoman/videoman.dart';

/// Example entry: init videoman core, then run the demo app.
///
/// 示例入口：初始化 videoman 内核，随后运行演示 app。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  VmController.ensureInitialized();
  runApp(const MyApp());
}

/// Demo app root.
///
/// 演示 app 根组件。
class MyApp extends StatelessWidget {
  /// Creates the demo app.
  ///
  /// 创建演示 app。
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(theme: ThemeData.dark(), home: const PlayerPage());
  }
}

/// A demo source with a display name.
///
/// 带显示名的演示源。
class _Demo {
  final String name;
  final VmSource source;
  const _Demo(this.name, this.source);
}

/// The demo sources: a plain VOD mp4 and a multi-quality HLS stream.
///
/// 演示源：普通点播 mp4 与含多清晰度的 HLS 流。
const _demos = [
  _Demo(
    'VOD · mp4',
    VmSource(
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
      title: '示例点播 mp4',
    ),
  ),
  _Demo(
    'HLS · 多清晰度',
    VmSource(
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      title: 'HLS 多清晰度示例',
    ),
  ),
];

/// A page that plays a demo source with [VmPlayer] and a source switcher.
///
/// 用 [VmPlayer] 播放演示源并提供源切换的页面。
class PlayerPage extends StatefulWidget {
  /// Creates the player page.
  ///
  /// 创建播放页面。
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

/// State for [PlayerPage]; owns the [VmController] lifecycle.
///
/// [PlayerPage] 的状态；持有 [VmController] 的生命周期。
class _PlayerPageState extends State<PlayerPage> {
  late final VmController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = VmController();
    _controller.open(_demos[_index].source);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Switches to demo source [i] and reloads its qualities.
  ///
  /// 切换到第 [i] 个演示源并重新加载其清晰度。
  Future<void> _switch(int i) async {
    setState(() => _index = i);
    await _controller.open(_demos[i].source);
    await _controller.loadQualities();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('videoman'),
        actions: [
          for (var i = 0; i < _demos.length; i++)
            TextButton(
              onPressed: i == _index ? null : () => _switch(i),
              child: Text(
                _demos[i].name,
                style: TextStyle(color: i == _index ? Colors.grey : Colors.white),
              ),
            ),
        ],
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: VmPlayer(controller: _controller),
        ),
      ),
    );
  }
}
