import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:media_kit/media_kit.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// Subtitle-format regression probe (2026-09-28 补测): verifies ASS/WebVTT
/// external subtitles (via `sub-add`) and mov_text embedded subtitles
/// (via container track auto-detection) still render correctly after the
/// avfilter-slim libmpv build. Not committed — throwaway per-project
/// convention (see main_avfilter_regression_probe.dart for the earlier
/// SRT-only pass).
///
/// 字幕格式补测探针（2026-09-28）：验证瘦身 libmpv（去 avfilter）下
/// ASS/WebVTT 外挂字幕（`sub-add`）与 mov_text 内封字幕（容器轨道自动探测）
/// 仍正常渲染。按项目约定不提交，仅一次性验证。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const _ProbeApp());
}

class _ProbeApp extends StatelessWidget {
  const _ProbeApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(theme: ThemeData.dark(), home: const _ProbePage());
  }
}

class _ProbePage extends StatefulWidget {
  const _ProbePage();

  @override
  State<_ProbePage> createState() => _ProbePageState();
}

/// Which subtitle mode is currently under test.
enum _Mode { ass, vtt, movText }

class _ProbePageState extends State<_ProbePage> {
  Player? _rawPlayer;
  MovaEngine? _engine;
  String _status = 'idle';
  _Mode? _mode;

  @override
  void initState() {
    super.initState();
    // Auto-sequence all three formats with generous gaps so each gets a
    // full 12s poll window without manual taps (device screen interaction
    // is unreliable to script reliably).
    // 自动依次跑三种格式，间隔留够每次 12s 轮询窗口，避免依赖手动点按
    // （脚本化点屏不可靠）。
    Future.delayed(const Duration(seconds: 1), _runAss);
    Future.delayed(const Duration(seconds: 20), _runVtt);
    Future.delayed(const Duration(seconds: 39), _runMovText);
  }

  Future<String> _extractAsset(String assetPath, String fileName) async {
    final bytes = await rootBundle.load(assetPath);
    final file = File('${Directory.systemTemp.path}/$fileName');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return file.path;
  }

  Future<void> _disposeCurrent() async {
    final engine = _engine;
    final player = _rawPlayer;
    _engine = null;
    _rawPlayer = null;
    if (engine != null) await engine.dispose();
    // engine.dispose() already disposes the underlying player via kernel;
    // avoid double-dispose.
    player;
  }

  Future<void> _runAss() async {
    await _disposeCurrent();
    setState(() {
      _mode = _Mode.ass;
      _status = 'loading ASS test...';
    });
    final videoPath = await _extractAsset('assets/test_video.mp4', 'probe_video.mp4');
    final assPath = await _extractAsset('assets/test_subtitle.ass', 'probe_sub.ass');
    final rawPlayer = Player();
    final engine = createMovaEngine(kernel: MovaMpvKernel(player: rawPlayer));
    _rawPlayer = rawPlayer;
    _engine = engine;
    await engine.open(MovaSource('file://$videoPath'), autoPlay: false);
    final native = rawPlayer.platform;
    if (native is NativePlayer) {
      try {
        await native.command(['sub-add', assPath, 'select']);
        await native.setProperty('sid', '1');
        await native.setProperty('sub-visibility', 'yes');
        print('SUBFMT_PROBE[ASS] sub-add ok, path=$assPath');
      } catch (e) {
        print('SUBFMT_PROBE[ASS] sub-add FAILED: $e');
      }
    }
    await engine.play();
    setState(() => _status = 'ASS playing');
    _pollSubText(native, 'ASS', 24);
  }

  Future<void> _runVtt() async {
    await _disposeCurrent();
    setState(() {
      _mode = _Mode.vtt;
      _status = 'loading WebVTT test...';
    });
    final videoPath = await _extractAsset('assets/test_video.mp4', 'probe_video2.mp4');
    final vttPath = await _extractAsset('assets/test_subtitle.vtt', 'probe_sub.vtt');
    final rawPlayer = Player();
    final engine = createMovaEngine(kernel: MovaMpvKernel(player: rawPlayer));
    _rawPlayer = rawPlayer;
    _engine = engine;
    await engine.open(MovaSource('file://$videoPath'), autoPlay: false);
    final native = rawPlayer.platform;
    if (native is NativePlayer) {
      try {
        await native.command(['sub-add', vttPath, 'select']);
        await native.setProperty('sid', '1');
        await native.setProperty('sub-visibility', 'yes');
        print('SUBFMT_PROBE[VTT] sub-add ok, path=$vttPath');
      } catch (e) {
        print('SUBFMT_PROBE[VTT] sub-add FAILED: $e');
      }
    }
    await engine.play();
    setState(() => _status = 'WebVTT playing');
    _pollSubText(native, 'VTT', 24);
  }

  Future<void> _runMovText() async {
    await _disposeCurrent();
    setState(() {
      _mode = _Mode.movText;
      _status = 'loading mov_text test...';
    });
    final videoPath = await _extractAsset(
      'assets/test_video_movtext.mp4',
      'probe_video_movtext.mp4',
    );
    final rawPlayer = Player();
    final engine = createMovaEngine(kernel: MovaMpvKernel(player: rawPlayer));
    _rawPlayer = rawPlayer;
    _engine = engine;
    await engine.open(MovaSource('file://$videoPath'), autoPlay: false);
    final native = rawPlayer.platform;
    if (native is NativePlayer) {
      // mov_text is embedded in the container; mpv should auto-detect it as
      // a sub track without sub-add. Check track-list and select it if not
      // already selected.
      final trackList = await native.getProperty('track-list');
      print('SUBFMT_PROBE[MOVTEXT] track-list after open: $trackList');
      try {
        await native.setProperty('sid', '1');
        await native.setProperty('sub-visibility', 'yes');
        print('SUBFMT_PROBE[MOVTEXT] sid=1 selected');
      } catch (e) {
        print('SUBFMT_PROBE[MOVTEXT] select sid FAILED: $e');
      }
    }
    await engine.play();
    setState(() => _status = 'mov_text playing');
    _pollSubText(native, 'MOVTEXT', 24);
  }

  void _pollSubText(dynamic native, String tag, int maxTicks) {
    var ticks = 0;
    Timer.periodic(const Duration(milliseconds: 500), (t) async {
      ticks++;
      if (ticks > maxTicks || native is! NativePlayer) {
        t.cancel();
        return;
      }
      final text = await native.getProperty('sub-text');
      final pos = await native.getProperty('time-pos');
      print('SUBFMT_PROBE[$tag] t=$ticks pos=$pos sub-text="$text"');
    });
  }

  @override
  void dispose() {
    _disposeCurrent();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('subtitle fmt probe: $_status')),
      body: Column(
        children: [
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(onPressed: _runAss, child: const Text('Run ASS')),
              ElevatedButton(onPressed: _runVtt, child: const Text('Run WebVTT')),
              ElevatedButton(onPressed: _runMovText, child: const Text('Run mov_text')),
            ],
          ),
          Expanded(
            child: _engine == null
                ? const Center(child: Text('pick a mode above'))
                : MovaPlayer(api: _engine!),
          ),
        ],
      ),
    );
  }
}
