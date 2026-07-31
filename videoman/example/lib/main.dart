import 'package:flutter/material.dart';
import 'package:videoman/videoman.dart';

/// Example entry: init videoman core, then run the demo app.
///
/// 示例入口：初始化 videoman 内核，随后运行演示 app。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  VmEngine.ensureInitialized();
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
  _Demo(
    '自定义皮肤 · 无画中画按钮',
    VmSource(
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
      title: '自定义皮肤示例',
    ),
  ),
];

/// A skin used by the third demo entry: the default skin with the
/// picture-in-picture button patched out of the top bar.
///
/// 第三个演示入口使用的皮肤：在默认皮肤基础上，从顶栏中移除画中画按钮。
const _noPipSkin = VmDefaultSkin(patches: [VmPatch.remove('topBar/pipButton')]);

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

/// State for [PlayerPage]; owns the [VmEngine] lifecycle.
///
/// [PlayerPage] 的状态；持有 [VmEngine] 的生命周期。
class _PlayerPageState extends State<PlayerPage> {
  /// The playback facade backing every demo entry.
  ///
  /// 支撑每个演示入口的播放能力面。
  late VmEngine _engine;

  /// Index of the currently selected demo source.
  ///
  /// 当前选中的演示源下标。
  int _index = 0;

  /// Whether the scrub-preview bubble is enabled in this demo run.
  ///
  /// 本次 demo 运行中是否启用拖动预览气泡。
  bool _previewOn = true;

  @override
  void initState() {
    super.initState();
    // The demo runs on desktop/emulator over whatever connection is
    // available, so the preview network policy is relaxed to `always`;
    // production defaults to `wifiOnly`.
    //
    // demo 在桌面/模拟器上跑，网络类型不确定，故把预览网络策略放宽为
    // `always`；生产环境默认是 `wifiOnly`。
    _engine = createVmEngine(
      options: const VmOptions(
        preview: VmPreviewConfig(network: VmPreviewNetwork.always),
      ),
    );
    _engine.open(_demos[_index].source);
  }

  /// Rebuilds the engine with preview switched to [on], reopening the current
  /// demo source.
  ///
  /// 以预览开关 [on] 重建 engine，并重新打开当前演示源。
  ///
  /// - [on]: whether the preview bubble should be enabled / 是否启用预览气泡
  Future<void> _togglePreview(bool on) async {
    final old = _engine;
    setState(() {
      _previewOn = on;
      _engine = createVmEngine(
        options: VmOptions(
          preview: VmPreviewConfig(
            enabled: on,
            network: VmPreviewNetwork.always,
          ),
        ),
      );
    });
    await old.dispose();
    await _engine.open(_demos[_index].source);
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  /// Switches to demo source [i] and reloads its qualities.
  ///
  /// 切换到第 [i] 个演示源并重新加载其清晰度。
  Future<void> _switch(int i) async {
    setState(() => _index = i);
    await _engine.open(_demos[i].source);
    await _engine.loadQualities();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('videoman'),
        actions: [
          IconButton(
            tooltip: _previewOn ? '关闭预览' : '开启预览',
            icon: Icon(_previewOn ? Icons.image : Icons.image_not_supported),
            onPressed: () => _togglePreview(!_previewOn),
          ),
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
          child: VmPlayer(
            api: _engine,
            skin: _index == 2 ? _noPipSkin : const VmDefaultSkin(),
          ),
        ),
      ),
    );
  }
}
