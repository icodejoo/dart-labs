import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// Minimal visual probe for the avfilter-removal (FILTERS="") regression
/// check: loads an external SRT subtitle via the raw mpv `sub-file`
/// property (mova has no public subtitle API), then renders through the
/// normal mova UI. Not committed to the package — throwaway verification
/// tool per project convention.
///
/// avfilter 移除（FILTERS=""）回归验证用的极简视觉探针：mova 没有公开字幕
/// API，所以直接用 mpv 原生 `sub-file` 属性加载外挂 SRT 字幕，再走正常
/// mova UI 渲染。按项目约定不提交进包，仅一次性验证用。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const _ProbeApp());
}

/// Probe app root.
///
/// 探针应用根组件。
class _ProbeApp extends StatelessWidget {
  const _ProbeApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(theme: ThemeData.dark(), home: const _ProbePage());
  }
}

/// Page that constructs a raw media_kit [Player], sets `sub-file` via
/// the native property API, wraps it in a mova kernel/engine, and plays.
///
/// 构造裸 media_kit [Player]、用原生属性 API 设置 `sub-file`，再包进 mova
/// 内核/引擎播放的页面。
class _ProbePage extends StatefulWidget {
  const _ProbePage();

  @override
  State<_ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<_ProbePage> {
  late final Player _rawPlayer;
  late final MovaEngine _engine;
  String _status = 'init';

  static const _videoUrl =
      'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4';

  // App-private cache dir avoids Android scoped-storage permission issues
  // that block mpv from reading /sdcard/ paths directly.
  // 用 app 私有缓存目录，避开 Android 分区存储权限对 mpv 直接读 /sdcard/
  // 路径的限制。
  static const _srtContent = '''
1
00:00:00,500 --> 00:00:04,000
avfilter regression check line 1 - MOVA SUBTITLE TEST

2
00:00:04,500 --> 00:00:08,000
avfilter regression check line 2 - libass render OK

3
00:00:08,500 --> 00:00:12,000
avfilter regression check line 3 - overlay/equalizer removed, subs still work
''';

  @override
  void initState() {
    super.initState();
    _rawPlayer = Player();
    _engine = createMovaEngine(kernel: MovaMpvKernel(player: _rawPlayer));
    _start();
  }

  Future<void> _start() async {
    final tmpFile = File('${Directory.systemTemp.path}/test_subtitle.srt');
    await tmpFile.writeAsString(_srtContent);
    await _engine.open(MovaSource(_videoUrl), autoPlay: false);
    final native = _rawPlayer.platform;
    if (native is NativePlayer) {
      // mpv's runtime way to add an external subtitle is the `sub-add`
      // command, not the `sub-file` property (that one is load-time only).
      // mpv 运行时添加外挂字幕走 `sub-add` 命令，不是 `sub-file` 属性
      // （那个只在加载时生效）。
      try {
        await native.command(['sub-add', tmpFile.path, 'select']);
        await native.setProperty('sid', '1');
        await native.setProperty('sub-visibility', 'yes');
        print('AVFILTER_PROBE sub-add ok, path=${tmpFile.path}');
      } catch (e) {
        print('AVFILTER_PROBE sub-add FAILED: $e');
      }
    }
    if (native is NativePlayer) {
      final pauseVal = await native.getProperty('pause');
      print('AVFILTER_PROBE sanity pause=$pauseVal');
      final trackList = await native.getProperty('track-list');
      print('AVFILTER_PROBE track-list after sub-file: $trackList');
      final subVis = await native.getProperty('sub-visibility');
      print('AVFILTER_PROBE sub-visibility=$subVis');
      final subFilePaths = await native.getProperty('sub-file-paths');
      print('AVFILTER_PROBE sub-file-paths=$subFilePaths');
    }
    print('AVFILTER_PROBE subtitle set at ${DateTime.now()}, starting play');
    await _engine.play();
    print('AVFILTER_PROBE play() returned at ${DateTime.now()}');
    setState(() => _status = 'subtitle loaded, playing');
    // Poll sub-text every 500ms for 15s to find exactly when/if libass
    // actually renders cue text (direct evidence, not visual guesswork).
    // 每 500ms 轮询一次 sub-text，持续 15s，直接证据判断 libass 是否真正
    // 渲染出了字幕文本（比视觉猜测时机更可靠）。
    var ticks = 0;
    Timer.periodic(const Duration(milliseconds: 500), (t) async {
      ticks++;
      if (ticks > 30) {
        t.cancel();
        return;
      }
      if (native is NativePlayer) {
        final text = await native.getProperty('sub-text');
        final pos = await native.getProperty('time-pos');
        print('AVFILTER_PROBE t=$ticks pos=$pos sub-text="$text"');
      }
    });
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('avfilter probe: $_status')),
      body: MovaPlayer(api: _engine),
    );
  }
}
