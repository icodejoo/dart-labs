import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

/// Visual-only probe for the ad->content seamless swap: unlike
/// [main_seamless_test.dart] (which measures the gap via [MovaState.
/// renderEpoch] but hides the video behind a full-screen log), this page
/// keeps the player full-screen with only a thin one-line status strip, so a
/// screen recording actually shows the transition frame-by-frame for visual
/// black-frame / jump-cut inspection. Timeline and skip mechanism are
/// unchanged from main_seamless_test.dart (content plays a real 3s, ad is
/// inserted and held 3s, then skip() resumes content directly).
///
/// 广告->正片无缝切换的纯视觉探针：和 [main_seamless_test.dart]（用
/// [MovaState.renderEpoch] 测间隔，但整屏是日志、画面被挡住）不同，这个页面
/// 让播放器占满全屏，只留一行细状态条，这样录屏才能真正逐帧看到切换瞬间、
/// 用于肉眼判断黑屏/跳变。时间线与 skip 机制与 main_seamless_test.dart 一致
/// （正片真实播 3 秒 -> 插播广告并持续 3 秒 -> skip() 直接续播正片）。
///
/// Run: `flutter run -t lib/main_swap_visual_probe.dart -d <device> --release`
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const MaterialApp(home: SwapVisualProbe()));
}

/// Content source, cache-busted like main_seamless_test.dart.
///
/// 正片源，同 main_seamless_test.dart 一样做缓存清除。
MovaSource _buildContent() => MovaSource(
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4'
      '?t=${DateTime.now().millisecondsSinceEpoch}',
      title: '正片',
    );

/// How long the ad is held before skip() ends it.
///
/// 广告被 skip() 结束前持续的时长。
const _adHoldDuration = Duration(seconds: 3);

/// Ad source: MDN flower.mp4 sample, same choice as main_seamless_test.dart.
///
/// 广告素材：MDN flower.mp4 样片，与 main_seamless_test.dart 一致。
final _ad = MovaAdBreak(
  kind: MovaAdBreakKind.mid,
  source: const MovaSource('https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4'),
  skippableAfter: Duration.zero,
);

/// Drives the same 3s-content -> ad -> skip timeline, but keeps the player
/// full-screen for visual recording.
///
/// 驱动同样的 3 秒正片 -> 广告 -> skip 时间线，但让播放器保持全屏以便录屏。
class SwapVisualProbe extends StatefulWidget {
  /// Creates the probe page.
  ///
  /// 创建探针页面。
  const SwapVisualProbe({super.key});

  @override
  State<SwapVisualProbe> createState() => _SwapVisualProbeState();
}

class _SwapVisualProbeState extends State<SwapVisualProbe> {
  late final MovaSwapEngine _engine;
  late final MovaAdController _controller;
  String _status = 'starting';
  Timer? _skipTimer;
  int _lastEpoch = 0;

  @override
  void initState() {
    super.initState();
    final opts = MovaOpts(
      ads: const MovaAdConfig(enabled: true),
      swap: const MovaSwapConfig(enabled: true, trigger: MovaEagerWarm()),
    );
    _engine = MovaSwapEngine(engineFactory: () => createMovaEngine(options: opts));
    _controller = MovaAdController(_engine, swap: _engine);
    _engine.states.listen((s) {
      if (s.renderEpoch != _lastEpoch) {
        _lastEpoch = s.renderEpoch;
        _mark('renderEpoch -> ${s.renderEpoch}');
      }
    });
    _mark('opening content');
    unawaited(_controller.load(_buildContent()).then((_) async {
      await _waitForRealPlayback();
      _mark('content playing, 3s then ad');
      Timer(const Duration(seconds: 3), _insertAd);
    }));
  }

  /// Same "really playing" gate as main_seamless_test.dart.
  ///
  /// 与 main_seamless_test.dart 相同的"真的在播"判定。
  Future<void> _waitForRealPlayback() {
    final completer = Completer<void>();
    late final StreamSubscription<MovaProg> sub;
    sub = _engine.progress.listen((p) {
      if (p.position > Duration.zero && !_engine.state.buffering) {
        unawaited(sub.cancel());
        completer.complete();
      }
    });
    return completer.future;
  }

  void _insertAd() {
    _mark('AD INSERTED');
    unawaited(_controller.playAdNow(_ad).then((_) async {
      await _waitForRealPlayback();
      _mark('ad playing, hold ${_adHoldDuration.inSeconds}s then SKIP');
      _skipTimer = Timer(_adHoldDuration, () {
        _mark('SKIP NOW');
        _controller.skip();
      });
    }));
  }

  @override
  void dispose() {
    _skipTimer?.cancel();
    _controller.dispose();
    _engine.dispose();
    super.dispose();
  }

  /// Prints a timestamped status line to stderr for correlating with the
  /// recording's real time, and keeps only the latest one on screen.
  ///
  /// 把带时间戳的状态行打到 stderr，用于跟录屏的真实时间对齐；屏幕上只保留
  /// 最新一条。
  void _mark(String what) {
    final line = '[+${DateTime.now().millisecondsSinceEpoch % 100000}ms] $what';
    // ignore: avoid_print
    print(line);
    if (mounted) setState(() => _status = line);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(child: MovaPlayer(api: _engine, skin: const MovaDefaultSkin())),
          Container(
            color: Colors.black,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Text(
              _status,
              style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
