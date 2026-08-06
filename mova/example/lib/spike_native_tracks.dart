import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Source matrix for the native-track spike: standard multi-bitrate HLS
/// (Mux public test stream), a single-rendition HLS (should only surface
/// `auto`), and a plain MP4 (no adaptive variants at all).
///
/// 原生 track spike 的源矩阵：标准多码率 HLS（Mux 公测源）、单码率 HLS
/// （应只出现 `auto`），以及一个普通 MP4（完全没有自适应变体）。
///
/// Fill in a real CDN HLS master URL here before running on a target
/// deployment's actual stream — the Mux source only proves the *mechanism*.
///
/// 跑到目标部署的真实流之前，先在这里补一个真实 CDN 的 HLS master 地址——
/// Mux 源只能证明*机制*本身可行。
const _spikeSources = <String, String>{
  'HLS 多码率 (Mux)': 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  'HLS 单码率': 'https://test-streams.mux.dev/pts_shift/master.m3u8',
  'MP4（无自适应）':
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
};

/// Spike page for [doc/plans/2026-08-04-quality-native-tracks-spike.md] T1–T3:
/// drives a raw media_kit [Player] directly (bypassing [MovaKernel], which does
/// not expose tracks yet) and prints `player.stream.tracks.video` /
/// `player.state.tracks.video` so a real device can confirm whether HLS
/// variants are reliably enumerated and whether `setVideoTrack` switches
/// without a visible re-buffer.
///
/// [doc/plans/2026-08-04-quality-native-tracks-spike.md] T1–T3 的探针页面：
/// 直接驱动裸的 media_kit [Player]（绕开尚未暴露 track 的 [MovaKernel]），打印
/// `player.stream.tracks.video` / `player.state.tracks.video`，供真机确认
/// HLS 变体是否被可靠枚举、`setVideoTrack` 切换是否无明显重缓冲。
///
/// Not shipped behaviour — exists only to gather the go/no-go data the plan's
/// appendix A needs.
///
/// 不是要发布的行为——只为收集计划附录 A 需要的 go/no-go 数据。
class NativeTracksSpikePage extends StatefulWidget {
  /// Creates the native-track spike page.
  ///
  /// 创建原生 track spike 页面。
  const NativeTracksSpikePage({super.key});

  @override
  State<NativeTracksSpikePage> createState() => _NativeTracksSpikePageState();
}

/// State for [NativeTracksSpikePage]; owns the raw [Player] + [VideoController]
/// and mirrors the track stream into on-screen text for a screenshot-driven
/// spike log.
///
/// [NativeTracksSpikePage] 的状态；持有裸 [Player] + [VideoController]，并把
/// track 流镜像成屏幕文字，便于靠截图记录 spike 结果。
class _NativeTracksSpikePageState extends State<NativeTracksSpikePage> {
  /// The raw media_kit player under inspection.
  ///
  /// 被检查的裸 media_kit 播放器。
  late final Player _player;

  /// The video controller `Video` widget renders through.
  ///
  /// `Video` 组件借以渲染的视频控制器。
  late final VideoController _controller;

  /// Currently selected entry in [_spikeSources].
  ///
  /// 当前选中的 [_spikeSources] 条目。
  String _currentSourceLabel = _spikeSources.keys.first;

  /// Latest `tracks.video` list, formatted for display — id/w/h/title/bitrate
  /// per entry, one per line.
  ///
  /// 最新的 `tracks.video` 列表，已格式化用于展示——每条含
  /// id/宽/高/标题/比特率，逐行排列。
  String _tracksText = '(等待流打开)';

  /// The currently active video track, per `state.track.video`.
  ///
  /// `state.track.video` 报告的当前生效视频轨。
  String _activeTrackText = '(none)';

  /// Timestamp of the last `setVideoTrack` call, used to eyeball how long a
  /// switch takes to settle by comparing against when `_activeTrackText`
  /// next updates.
  ///
  /// 最近一次 `setVideoTrack` 调用的时间戳；通过对比 `_activeTrackText`
  /// 下次更新的时间，粗略判断一次切换需要多久才稳定。
  DateTime? _lastSwitchAt;

  /// Last raw mpv log line and last open-time exception, surfaced on screen
  /// so a failure is visible without pulling logcat.
  ///
  /// 最近一条原始 mpv 日志与打开时抛出的异常，直接展示在界面上，
  /// 不用再去抓 logcat 才能看到失败原因。
  String _diagnostics = '(none)';

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.stream.log.listen((log) {
      debugPrint('mpv[${log.level}] ${log.prefix}: ${log.text}');
      if (log.level == 'error' || log.level == 'fatal') {
        setState(() => _diagnostics = 'mpv[${log.level}] ${log.prefix}: ${log.text}');
      }
    });
    _player.stream.error.listen((error) {
      debugPrint('player error: $error');
      setState(() => _diagnostics = 'player error: $error');
    });
    _player.stream.tracks.listen((tracks) {
      final lines = tracks.video
          .map((t) => 'id=${t.id} w=${t.w} h=${t.h} title=${t.title} '
              'bitrate=${t.bitrate} codec=${t.codec}')
          .join('\n');
      setState(() => _tracksText = lines.isEmpty ? '(空)' : lines);
    });
    _player.stream.track.listen((track) {
      final elapsed = _lastSwitchAt == null
          ? ''
          : ' (+${DateTime.now().difference(_lastSwitchAt!).inMilliseconds}ms)';
      setState(() {
        _activeTrackText = 'id=${track.video.id} w=${track.video.w} '
            'h=${track.video.h}$elapsed';
      });
    });
    _open(_currentSourceLabel);
  }

  /// Opens the source registered under [label] in [_spikeSources].
  ///
  /// 打开 [_spikeSources] 中注册在 [label] 下的源。
  ///
  /// - [label]: key into [_spikeSources] / [_spikeSources] 的键
  Future<void> _open(String label) async {
    setState(() {
      _currentSourceLabel = label;
      _tracksText = '(等待流打开)';
      _activeTrackText = '(none)';
      _lastSwitchAt = null;
      _diagnostics = '(none)';
    });
    try {
      await _player.open(Media(_spikeSources[label]!));
    } catch (e, st) {
      debugPrint('open() threw: $e\n$st');
      setState(() => _diagnostics = 'open() threw: $e');
    }
  }

  /// Switches to video track [id] and stamps [_lastSwitchAt] so the next
  /// `state.track.video` update can report how long it took to settle.
  ///
  /// 切换到视频轨 [id]，并记录 [_lastSwitchAt]，便于下次 `state.track.video`
  /// 更新时报告切换耗时。
  ///
  /// - [id]: the `VideoTrack.id` to switch to, or `'auto'` for ABR
  ///   / 目标切换到的 `VideoTrack.id`，或 `'auto'` 表示交还自适应
  void _switchTo(VideoTrack track) {
    _lastSwitchAt = DateTime.now();
    _player.setVideoTrack(track);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _player.state.tracks.video;
    return Scaffold(
      appBar: AppBar(title: const Text('原生 track spike')),
      body: SafeArea(
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Video(controller: _controller),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final label in _spikeSources.keys)
                    ChoiceChip(
                      label: Text(label),
                      selected: _currentSourceLabel == label,
                      onSelected: (_) => _open(label),
                    ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'tracks.video (点按钮即调用 setVideoTrack，观察画面是否卡顿/黑屏):',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      // Skip the `no` track ('disable video output') — it is
                      // not a quality variant and clicking it looks
                      // indistinguishable from a broken switch (permanent
                      // black screen with no recovery).
                      //
                      // 跳过 `no` 轨（"关闭视频输出"）——它不是清晰度变体，
                      // 点了看起来跟"切换失败"一样（永久黑屏、不会恢复）。
                      for (final t in tracks.where((t) => t.id != 'no'))
                        ElevatedButton(
                          onPressed: () => _switchTo(t),
                          child: Text(t.id == 'auto' ? 'auto' : '${t.h ?? t.bitrate ?? t.id}'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('原始 tracks.video 数据:', style: TextStyle(fontWeight: FontWeight.bold)),
                  SelectableText(_tracksText, key: const Key('spikeTracksText')),
                  const SizedBox(height: 8),
                  Text(
                    '当前 track: $_activeTrackText',
                    key: const Key('spikeActiveTrack'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    '诊断: $_diagnostics',
                    key: const Key('spikeDiagnostics'),
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
