import 'package:flutter/material.dart';
import 'package:fvideo/fvideo.dart';

/// Example entry: init fvideo core, then run the demo app.
///
/// 示例入口：初始化 fvideo 内核，随后运行演示 app。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FvideoController.ensureInitialized();
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
    return const MaterialApp(home: PlayerPage());
  }
}

/// A page that plays a sample video with [FvideoPlayer] and its gestures.
///
/// 用 [FvideoPlayer] 及其手势层播放示例视频的页面。
class PlayerPage extends StatefulWidget {
  /// Creates the player page.
  ///
  /// 创建播放页面。
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

/// State for [PlayerPage]; owns the [FvideoController] lifecycle.
///
/// [PlayerPage] 的状态；持有 [FvideoController] 的生命周期。
class _PlayerPageState extends State<PlayerPage> {
  late final FvideoController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FvideoController();
    _controller.open(
      const FvideoSource(
        'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('fvideo P1')),
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: FvideoPlayer(controller: _controller),
        ),
      ),
    );
  }
}
