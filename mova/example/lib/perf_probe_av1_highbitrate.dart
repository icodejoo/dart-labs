/// In-process RSS + progress probe for a high-bitrate 1080p AV1 source on
/// Windows desktop. This validates a previously-untested gap: earlier AV1
/// verification only covered an 8s low-bitrate 720p clip, so CPU/memory
/// behaviour on longer/heavier content was unknown.
///
/// Reads `ProcessInfo.currentRss` (`dart:io`) — real resident set size from
/// the OS, sampled every 10s across the whole playback, plus every
/// `MovaProg` event (position advance) to judge stall-free progress from
/// real timestamps instead of eyeballing.
///
/// Run:
/// ```
/// flutter run -d windows --release -t lib/perf_probe_av1_highbitrate.dart --dart-define=MOVA_AV1_URI=file:///C:/path/to/av1_1080p_highbitrate.mp4
/// ```
///
/// Windows 桌面端高码率 1080p AV1 的进程内 RSS + 进度探针。此前 AV1 验证只测过
/// 8 秒低码率 720p 短片，长时长/高码率下的 CPU/内存表现是空白，本探针补上这块。
///
/// 读取 `ProcessInfo.currentRss`（`dart:io`）——来自操作系统的真实常驻内存，
/// 整个播放期每 10 秒采一次样，另外记录每个 `MovaProg` 事件（位置推进）用于基于
/// 真实时间戳判断是否流畅，而非目测。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

/// Source URI, overridable via --dart-define so the same probe file works
/// for any locally-encoded test clip.
///
/// 素材地址，可通过 --dart-define 覆盖，使同一探针文件适配任意本地编码的测试片。
const _mediaUri = String.fromEnvironment('MOVA_AV1_URI', defaultValue: '');

/// Sampling interval for RSS during playback.
///
/// 播放期内 RSS 采样间隔。
const _sampleInterval = Duration(seconds: 10);

/// Total time to let playback run before finishing the probe.
///
/// 探针结束前让播放持续运行的总时长。
const _playDuration = Duration(seconds: 75);

/// Current resident set size in MiB.
///
/// 当前常驻内存（MiB）。
double _rssMiB() => ProcessInfo.currentRss / 1024 / 1024;

/// Prints one labelled sample in a grep-friendly shape.
///
/// 以便于 grep 的格式打印一条带标签的样本。
void _log(String label, Object value) {
  // ignore: avoid_print
  print('MOVA_AV1_PERF|$label|$value');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const _ProbeApp());
}

/// Probe shell: mounts a real [MovaPlayer] so the video pipeline actually
/// decodes and composites, then samples RSS on a timer and logs every
/// progress event with a wall-clock-independent position.
///
/// 探针外壳：挂载真实 [MovaPlayer] 使视频管线真正解码并参与合成，定时采样 RSS，
/// 并记录每个进度事件（位置独立于墙钟）。
class _ProbeApp extends StatefulWidget {
  /// Creates the probe shell.
  ///
  /// 创建探针外壳。
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  MovaEngine? _engine;
  Timer? _sampleTimer;
  StreamSubscription<MovaProg>? _progSub;
  int _progCount = 0;
  Duration _lastPos = Duration.zero;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    _log('baseline_rss_mib', _rssMiB().toStringAsFixed(2));

    final engine = createMovaEngine();
    setState(() => _engine = engine);

    final uri = _mediaUri;
    if (uri.isEmpty) {
      _log('error', 'MOVA_AV1_URI not set');
      await Future<void>.delayed(const Duration(seconds: 1));
      exit(1);
    }
    _log('uri', uri);

    _progSub = engine.progress.listen((p) {
      _progCount++;
      final delta = p.position - _lastPos;
      _lastPos = p.position;
      _log(
        'prog',
        'pos=${p.position.inMilliseconds}ms delta=${delta.inMilliseconds}ms buffering=${engine.state.buffering}',
      );
    });

    await engine.open(MovaSource(uri, title: 'av1 1080p high bitrate probe'));
    await Future<void>.delayed(const Duration(seconds: 3));
    _log('size', '${engine.state.width}x${engine.state.height}');
    _log('duration_ms', engine.state.duration.inMilliseconds);
    _log('playing', engine.state.playing);
    _log('render_handle_null', (engine.renderHandle == null).toString());

    _sampleTimer = Timer.periodic(_sampleInterval, (_) {
      _log('rss_mib', _rssMiB().toStringAsFixed(2));
      _log('prog_count', _progCount);
    });

    await Future<void>.delayed(_playDuration);

    _sampleTimer?.cancel();
    _progSub?.cancel();
    _log('final_rss_mib', _rssMiB().toStringAsFixed(2));
    _log('final_prog_count', _progCount);
    _log('final_pos_ms', _lastPos.inMilliseconds);

    setState(() => _engine = null);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await engine.dispose();
    await Future<void>.delayed(const Duration(seconds: 3));
    _log('disposed_rss_mib', _rssMiB().toStringAsFixed(2));
    _log('done', 'ok');
    await stdout.flush();
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    return MaterialApp(
      home: Scaffold(
        body: engine == null
            ? const Center(child: Text('mova av1 highbitrate probe'))
            : MovaPlayer(api: engine),
      ),
    );
  }
}
