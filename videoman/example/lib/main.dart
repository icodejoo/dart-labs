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

/// A demo source with a display name and the options it needs.
///
/// 带显示名与所需配置的演示源。
class _Demo {
  /// Label shown in the app bar.
  ///
  /// 应用栏上显示的名称。
  final String name;

  /// The media source this entry plays.
  ///
  /// 该入口播放的媒体源。
  final VmSource source;

  /// Player options this entry needs (live mode, timeshift builder, …).
  ///
  /// 该入口所需的播放器配置（直播模式、时移地址构造器等）。
  final VmOptions options;

  /// Creates a demo entry.
  ///
  /// 创建一个演示入口。
  const _Demo(this.name, this.source, {this.options = const VmOptions()});
}

/// The demo sources: VOD mp4, multi-quality HLS, a custom-skin variant, a
/// DVR-seekable live stream, and a time-shift (reopen-on-seek) live stream.
///
/// 演示源：点播 mp4、多清晰度 HLS、自定义皮肤变体、DVR 可拖直播、
/// 时移（拖动即换源）直播。
final _demos = [
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
  _Demo(
    '直播 · DVR 可拖',
    VmSource(
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      type: VmStreamType.live,
      title: '直播（DVR 窗口内可回看）',
    ),
    options: const VmOptions(
      live: VmLiveConfig(seekMode: VmLiveSeekMode.dvr),
    ),
  ),
  _Demo(
    '直播 · 时移换源',
    VmSource(
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      type: VmStreamType.live,
      title: '直播（时移：拖动即换源）',
    ),
    options: VmOptions(
      live: VmLiveConfig(
        seekMode: VmLiveSeekMode.timeshift,
        dvrWindow: const Duration(minutes: 10),
        // Demo-only: this public test stream has no timeshift endpoint, so the
        // builder just appends a query the server ignores. It exists to show
        // *where* a real deployment plugs its own URL scheme in.
        //
        // 仅用于演示：这个公开测试流没有时移接口，构造器只是拼一个服务端会忽略
        // 的查询参数。它的意义是展示真实部署应当在**哪里**接入自己的地址方案。
        urlBuilder: (uri, behind, wallClock) =>
            '$uri?begin=${wallClock.subtract(behind).millisecondsSinceEpoch}',
      ),
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
    _engine = createVmEngine(options: _optionsFor(_index));
    _engine.open(_demos[_index].source);
  }

  /// Builds the effective options for demo [i]: that demo's own `options`
  /// (live mode, timeshift builder, …) with the preview section overridden to
  /// respect [_previewOn] and relax the network policy for desktop/emulator
  /// use, where the connection type is unknown; production defaults to
  /// `wifiOnly`.
  ///
  /// 构建第 [i] 个演示的生效配置：该演示自身的 `options`（直播模式、时移地址
  /// 构造器等），并覆盖预览一节以遵循 [_previewOn]、放宽桌面/模拟器场景下
  /// 未知的网络策略；生产环境默认是 `wifiOnly`。
  ///
  /// - [i]: index into [_demos] / [_demos] 下标
  VmOptions _optionsFor(int i) => _demos[i].options.copyWith(
        preview: VmPreviewConfig(
          enabled: _previewOn,
          network: VmPreviewNetwork.always,
        ),
      );

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
      _engine = createVmEngine(options: _optionsFor(_index));
    });
    await old.dispose();
    await _engine.open(_demos[_index].source);
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  /// Switches to demo source [i], rebuilding the engine because options are
  /// construction-time.
  ///
  /// 切换到第 [i] 个演示源；因为配置是构造期参数，需要重建 engine。
  ///
  /// - [i]: index into the demo list / 演示列表下标
  Future<void> _switch(int i) async {
    final old = _engine;
    setState(() {
      _index = i;
      _engine = createVmEngine(options: _optionsFor(i));
    });
    await old.dispose();
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
