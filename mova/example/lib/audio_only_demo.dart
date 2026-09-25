import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

/// Standalone manual/on-device demo for the audio-only mode. Deliberately not
/// folded into `main.dart`: this page exists so the audio path can be walked
/// on its own, with a single switch that rebuilds the engine in the other mode
/// for an A/B comparison on the same material.
///
/// Run with: `flutter run -t lib/audio_only_demo.dart -d windows` (or
/// `-d <android-device-id>`).
///
/// 仅音频模式的独立手工/真机 demo 页。刻意不塞进 `main.dart`：这个页面的意义就是
/// 让音频这条路能被单独走一遍，并用一个开关在同一条素材上重建成另一种模式做 A/B
/// 对比。
///
/// 运行：`flutter run -t lib/audio_only_demo.dart -d windows`（或 `-d <设备号>`）。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const _AudioOnlyDemoApp());
}

/// A pure-audio source (no video track at all).
///
/// 纯音频源（完全没有视频轨）。
const _audioSource = MovaSource(
  'https://file-examples.com/storage/fe0b4c5e0b6a6f0c0b0e3f7/2017/11/file_example_MP3_2MG.mp3',
  title: '纯音频素材 / audio-only material',
);

/// A source that *does* carry a video track — under `audioOnly: true` it must
/// play sound and show no picture.
///
/// 带视频轨的源——在 `audioOnly: true` 下必须只出声、不出画。
const _videoSource = MovaSource(
  'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
  title: '带视频轨素材 / material with a video track',
);

/// The demo app shell.
///
/// demo 应用外壳。
class _AudioOnlyDemoApp extends StatelessWidget {
  /// Creates the demo app.
  ///
  /// 创建 demo 应用。
  const _AudioOnlyDemoApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'mova audioOnly demo',
        theme: ThemeData.dark(useMaterial3: true),
        home: const _AudioOnlyDemoPage(),
      );
}

/// The demo page: one engine, two toggles (mode and source), rebuilt on change.
///
/// demo 页：一个引擎、两个开关（模式与素材），变更时重建引擎。
class _AudioOnlyDemoPage extends StatefulWidget {
  /// Creates the demo page.
  ///
  /// 创建 demo 页。
  const _AudioOnlyDemoPage();

  @override
  State<_AudioOnlyDemoPage> createState() => _AudioOnlyDemoPageState();
}

class _AudioOnlyDemoPageState extends State<_AudioOnlyDemoPage> {
  /// Whether the current engine was built audio-only.
  ///
  /// 当前引擎是否以仅音频形态构造。
  bool _audioOnly = true;

  /// Whether to play the source that carries a video track.
  ///
  /// 是否播放带视频轨的那条素材。
  bool _useVideoSource = false;

  /// Whether to hand `MovaPlayer` a custom cover surface instead of letting it
  /// render its black placeholder.
  ///
  /// 是否给 `MovaPlayer` 传自定义封面面，而不是让它渲染黑色占位。
  bool _useCover = true;

  /// The live engine; rebuilt whenever the mode or source changes.
  ///
  /// 当前引擎；模式或素材变更时重建。
  MovaEngine? _engine;

  /// The most recent observable signals, shown on screen so an on-device run
  /// records real values instead of relying on the eye.
  ///
  /// 最近的可观测信号，显示在屏幕上，使真机跑动记录的是真实数值而非肉眼估计。
  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  /// Disposes the old engine and builds a fresh one in the current mode.
  ///
  /// 释放旧引擎并按当前模式构造一个新的。
  void _rebuild() {
    _engine?.dispose();
    final engine = createMovaEngine(
      audioOnly: _audioOnly,
      options: MovaOpts(
        // No frames to preview in audio mode; leave it on for video so the
        // A/B comparison is against the normal video configuration.
        // 音频模式没有帧可预览；视频侧保持开启，使 A/B 对比的是常规视频配置。
        preview: MovaPreviewConfig(enabled: !_audioOnly),
      ),
    );
    _engine = engine;
    _log.clear();
    _note('engine rebuilt: audioOnly=$_audioOnly, renderHandle=${engine.renderHandle}');
    engine.events.listen((e) => _note('event: ${e.runtimeType}'));
    engine.states.listen((s) {
      if (s.width != 0 || s.height != 0) _note('size reported: ${s.width}x${s.height}');
    });
    engine.open(_useVideoSource ? _videoSource : _audioSource);
  }

  /// Appends a timestamped line to the on-screen log.
  ///
  /// 向屏幕日志追加一行带时间戳的记录。
  void _note(String line) {
    if (!mounted) {
      _log.insert(0, line);
      return;
    }
    setState(() {
      _log.insert(0, '${DateTime.now().toIso8601String().substring(11, 23)}  $line');
      if (_log.length > 40) _log.removeLast();
    });
  }

  @override
  void dispose() {
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    if (engine == null) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(title: const Text('mova · audioOnly demo')),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: MovaPlayer(
              key: ValueKey(engine),
              api: engine,
              surface: _useCover && _audioOnly ? const _CoverArt() : null,
            ),
          ),
          SwitchListTile(
            value: _audioOnly,
            title: const Text('audioOnly'),
            subtitle: Text('renderHandle = ${engine.renderHandle}'),
            onChanged: (v) => setState(() {
              _audioOnly = v;
              _rebuild();
            }),
          ),
          SwitchListTile(
            value: _useVideoSource,
            title: const Text('用带视频轨的素材 / use the source with a video track'),
            subtitle: const Text('audioOnly 下应只出声不出画 / sound only under audioOnly'),
            onChanged: (v) => setState(() {
              _useVideoSource = v;
              _rebuild();
            }),
          ),
          SwitchListTile(
            value: _useCover,
            title: const Text('用自定义封面面 / custom cover surface'),
            subtitle: const Text('关掉则看黑色占位 / off shows the black placeholder'),
            onChanged: (v) => setState(() => _useCover = v),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _log.length,
              itemBuilder: (c, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Text(_log[i], style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A stand-in for a real cover-art/lyrics/waveform panel, passed through
/// `MovaPlayer.surface` — the hook that makes a dedicated audio skin
/// unnecessary.
///
/// 真实封面/歌词/波形面的替身，经 `MovaPlayer.surface` 传入——正是这个口子让
/// 专门的音频皮肤变得不必要。
class _CoverArt extends StatelessWidget {
  /// Creates the placeholder cover art.
  ///
  /// 创建占位封面。
  const _CoverArt();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1B2A4A), Color(0xFF4A1B3A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(child: Icon(Icons.album, size: 96, color: Colors.white24)),
      );
}
