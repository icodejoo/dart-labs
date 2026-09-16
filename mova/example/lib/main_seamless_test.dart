import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

/// Standalone acceptance test for seamless ad→content swap: no manual
/// clicking, no other demos mixed in. Plays content for 3s, auto-inserts an
/// ad via [MovaAdCtrl.playAdNow], ends it with [MovaAdCtrl.skip] after
/// [_adHoldDuration] (see the revision note for why this is the reliable
/// mechanism), then measures and prints the wall-clock gap between the skip
/// and the content actually resuming — the thing that shows up on screen as
/// a black frame / stall.
///
/// Run with: `flutter run -t lib/main_seamless_test.dart -d windows` (or
/// `-d <android-device-id>`).
///
/// **Revision history**: three earlier versions tried to end the ad off the
/// media itself:
/// 1. `Timer` + `seek()` near end, tuned to 2s/4s/5s holds — seeking within
///    ~100ms of a clip's real EOF reliably left the player stuck with
///    [MovaDone] never firing on the real Android device (an mpv/media_kit
///    edge case around seeking that close to the true end).
/// 2. Swapping in a long clip to get a wider window without seeking, letting
///    it reach its own natural end — its duration never resolved over a real
///    device's network within any reasonable hold window.
/// 3. A short, fast-duration MDN clip left to reach its own natural end —
///    the clip never progressed past its opening frame after 100+ seconds on
///    a real device on mobile data, even with a strong signal (confirmed via
///    `adb shell dumpsys telephony.registry`); the *content* clip (hosted on
///    `user-images.githubusercontent.com`) played fine over the same
///    connection, so this looked like a reachability problem specific to
///    MDN's CDN on that network, not a mova bug.
///
/// Landed on: don't rely on the ad media's own timeline reaching any
/// particular point at all. [MovaAdCtrl.skip] resumes content directly and
/// synchronously (see its implementation) without depending on [MovaDone] or
/// any duration/position query, so it can't get stuck on network or media
/// quirks. The ad source is also switched to the same
/// `user-images.githubusercontent.com` URL as the content, since that is the
/// one domain confirmed reachable on the test device's network.
///
/// 无缝广告→正片切换的独立验收测试：不需要手动点击，不与其他 demo 混在一起。
/// 自动播 3 秒正片→经 [MovaAdCtrl.playAdNow] 插播一段广告→[_adHoldDuration]
/// 后用 [MovaAdCtrl.skip] 结束它（可靠机制的原因见下方修订历史），测量并打印
/// 跳过那一刻到正片真正续播之间的墙钟间隔——这段间隔就是屏幕上会看到的
/// 黑屏/卡顿。
///
/// 运行：`flutter run -t lib/main_seamless_test.dart -d windows`（或
/// `-d <安卓设备id>`）。
///
/// **修订历史**：早先三版都想靠广告媒体自身的时间轴来结束广告：
/// 1. `Timer` + 末尾附近的 `seek()`，先后调过 2/4/5 秒——真机上把播放头 seek
///    到离素材真实 EOF 约 100ms 以内，会可靠地卡住播放器、`MovaDone` 永远不
///    触发（mpv/media_kit 在临近真实末尾做 seek 时的边界情况）。
/// 2. 换成长素材获得更宽窗口、不做 seek、让它自然结束——其时长在真机网络下，
///    在任何合理的持续窗口内都解析不出来。
/// 3. 一个时长能快速解析出来的短 MDN 素材，让它自然结束——真机移动网络下，
///    哪怕信号很好（用 `adb shell dumpsys telephony.registry` 确认过），
///    100 多秒了画面都没离开过开场那一帧；同一条连接下*正片*素材（托管在
///    `user-images.githubusercontent.com`）播放正常，看起来是那张网络卡对
///    MDN 这条 CDN 存在可达性问题，不是 mova 的 bug。
///
/// 最终方案：完全不依赖广告媒体自身的时间轴走到任何特定点。
/// [MovaAdCtrl.skip] 直接同步续播正片（见其实现），不依赖 `MovaDone`，也不
/// 查时长/位置，不会被网络或媒体的怪癖卡住。广告素材也换成跟正片同一个
/// `user-images.githubusercontent.com` 域名下的 URL——这是测试设备网络上
/// 唯一确认可达的域名。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const MaterialApp(home: SeamlessBlackFrameTest()));
}

/// Builds the content source with a cache-busting query parameter so each
/// run of the test fetches fresh over the network instead of hitting a CDN
/// or on-device HTTP cache from a previous run — the point of running this
/// test multiple times is to sample real network variance, which a cached
/// response would hide.
///
/// 构建带缓存清除查询参数的正片源，使测试每次运行都走真实网络请求，而不是
/// 命中上一次运行留下的 CDN 或设备端 HTTP 缓存——多次跑测的意义就是采样真实
/// 网络波动，命中缓存的响应会把这个波动藏起来。
MovaSource _buildContent() => MovaSource(
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4'
      '?t=${DateTime.now().millisecondsSinceEpoch}',
      title: '正片',
    );

/// How long the ad is held before [MovaAdCtrl.skip] ends it; the warm-up
/// window the content gets to actually buffer over the network.
///
/// 广告被 [MovaAdCtrl.skip] 结束前持续的时长；正片借此在真实网络上实际缓冲的
/// 窗口。
const _adHoldDuration = Duration(seconds: 3);

/// [MovaAdBreak.skippableAfter]: zero, deliberately. A first attempt set
/// this a second under [_adHoldDuration] on the theory that [MovaAdCtrl.
/// adPosition] (which drives [MovaAdCtrl.canSkip]) might lag the wall clock
/// by a tick or two — but on the real device, opening this file fresh as the
/// ad had enough of its own network startup delay that `adPosition` was
/// still under the 3s bar a full second later (`canSkip=false` at the hold
/// [Timer]), silently no-op'ing [skip]. Zero removes the race outright:
/// `adPosition >= Duration.zero` holds from the first tick, so [skip] can
/// never lose this timing game regardless of how slowly the ad itself
/// starts.
///
/// [MovaAdBreak.skippableAfter]：故意设为零。第一次尝试把它设成比
/// [_adHoldDuration] 小 1 秒，理由是 [MovaAdCtrl.adPosition]（驱动
/// [MovaAdCtrl.canSkip]）可能比墙钟慢一两个 tick——但真机上，把这份文件重新
/// 当广告打开本身就有一段网络起播延迟，一秒之后 `adPosition` 依然没追上 3 秒
/// 门槛（持续 [Timer] 触发时 `canSkip=false`），[skip] 悄悄变成了空操作。
/// 设为零彻底消除这场竞争：从第一个 tick 起 `adPosition >= Duration.zero`
/// 就恒成立，不管广告自己起播多慢，[skip] 都不会再输掉这场时序竞赛。
const _skippableAfter = Duration.zero;

/// Ad clip: back to the MDN flower.mp4 sample per user request, after
/// reusing the content clip's own URL as the ad produced an inconclusive run
/// (fell back to plain `open()` within 5s, cause not yet isolated — could be
/// the shadow failing to open the same URL a second engine already has
/// open, or could still be network variance). [MovaAdCtrl.skip] (not a
/// forced seek or waiting for natural end) is what makes the ad source
/// choice safe to swap independently of the earlier MDN reachability issue.
///
/// 广告素材：按要求换回 MDN 的 flower.mp4 样片——把正片自己的 URL
/// 复用为广告后，那次跑测没有定论（5 秒内回落到了普通 `open()`，原因还没
/// 查清楚——可能是影子引擎打开一个另一个引擎已经打开着的同一个 URL 失败了，
/// 也可能仍是网络波动）。用 [MovaAdCtrl.skip]（而非强制 seek 或等自然结束）
/// 才是让广告素材可以独立于早先 MDN 可达性问题而自由更换的原因。
final _ad = MovaAdBreak(
  kind: MovaAdBreakKind.mid,
  source: const MovaSource('https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4'),
  skippableAfter: _skippableAfter,
);

/// Drives the timeline (3s content → ad → back to content) and instruments
/// the ad→content transition with wall-clock timestamps.
///
/// 驱动整条时间线（3 秒正片 → 广告 → 回正片），并给广告→正片这段切换打上
/// 墙钟时间戳。
class SeamlessBlackFrameTest extends StatefulWidget {
  /// Creates the test page.
  ///
  /// 创建测试页面。
  const SeamlessBlackFrameTest({super.key});

  @override
  State<SeamlessBlackFrameTest> createState() => _SeamlessBlackFrameTestState();
}

class _SeamlessBlackFrameTestState extends State<SeamlessBlackFrameTest> {
  late final MovaSwapEngine _engine;
  late final MovaAdCtrl _controller;
  final List<String> _log = [];
  Timer? _skipTimer;
  Stopwatch? _adGapClock;
  StreamSubscription<MovaState>? _stateSub;
  int _lastEpoch = 0;

  @override
  void initState() {
    super.initState();
    final opts = MovaOpts(
      ads: const MovaAdConfig(enabled: true),
      // Eager: start warming the content up the instant the ad starts, not
      // just its last couple of seconds — a short ad has no meaningful
      // "last couple of seconds" to speak of anyway.
      //
      // 即时触发：广告一开始播放就预热正片，而不是只在最后一两秒——短广告
      // 本来也没有多少"最后一两秒"可言。
      swap: const MovaSwapConfig(enabled: true, trigger: MovaEagerWarm()),
    );
    _engine = MovaSwapEngine(engineFactory: () => createMovaEngine(options: opts));
    _controller = MovaAdCtrl(_engine, swap: _engine);
    _controller.changes.listen((_) => _onAdChange());
    // MovaAdCtrl.changes fires the instant _playContent() *starts* (a
    // bookkeeping flag flip), not when the swap actually lands — so it
    // measures "time to decide to resume", not "time until content is
    // really back". MovaState.renderEpoch only bumps once the atomic swap
    // has actually completed (see MovaSwapEngine._commitNow), which is the
    // real signal for this test.
    //
    // MovaAdCtrl.changes 在 _playContent() *刚开始*那一刻就触发（一次记账用
    // 的标志翻转），而非切换真正落地时——所以它测的是"决定要续播的时刻"，
    // 不是"内容真的回来的时刻"。MovaState.renderEpoch 只在原子切换真正完成后
    // 才会自增（见 MovaSwapEngine._commitNow），这才是本测试要的真实信号。
    _stateSub = _engine.states.listen((s) {
      if (s.renderEpoch != _lastEpoch) {
        _lastEpoch = s.renderEpoch;
        final clock = _adGapClock;
        if (clock != null) {
          _adGapClock = null;
          _mark('renderEpoch bumped to ${s.renderEpoch} — seamless swap landed, gap: ${clock.elapsedMilliseconds}ms');
        }
      }
    });
    _mark('opening content');
    // Go through the controller's load(), not a bare engine.open(): playAdNow
    // only fires while the controller believes it is in its "content" phase,
    // and load() is what puts it there.
    //
    // 走控制器的 load()，而不是裸的 engine.open()：playAdNow 只在控制器认为
    // 自己处于"正片"阶段时才会生效，而让它进入这个阶段正是 load() 的职责。
    unawaited(_controller.load(_buildContent()).then((_) async {
      _mark('content opened — waiting for real playback to start (not just open() resolving)');
      // load()'s future resolving only means the open() call returned; the
      // clip can still be sitting in network startup/buffering with no
      // pixels moving yet. The "3 seconds of content" the user asked for
      // must be 3 seconds of *actual playback*, so the countdown starts once
      // position is really advancing, not from here.
      //
      // load() 的 future resolve 只说明 open() 调用返回了；素材完全可能还卡在
      // 网络起播/缓冲阶段，画面根本没动。用户要的"3 秒正片"必须是 3 秒
      // *真实播放*的时间，所以倒计时要等位置真的在推进之后才开始，而不是
      // 从这里开始。
      await _waitForRealPlayback();
      _mark('content really playing now, waiting 3s of real playback');
      Timer(const Duration(seconds: 3), _insertAd);
    }));
  }

  /// Completes once the engine's progress shows playback actually advancing
  /// (position past zero and not buffering) — the point past which elapsed
  /// time reflects real playback rather than network/decoder startup.
  ///
  /// 在引擎的进度显示播放确实在推进（位置过零且不在缓冲）时完成——从这一刻
  /// 起的耗时才代表真实播放时间，而非网络/解码器起播开销。
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
    _mark('inserting ad');
    unawaited(_controller.playAdNow(_ad).then((_) async {
      _mark('ad opened — waiting for it to really start playing');
      await _waitForRealPlayback();
      _mark('ad really playing now, will skip after ${_adHoldDuration.inSeconds}s of real playback');
      _skipTimer = Timer(_adHoldDuration, () {
        // Start the gap clock right here: skip() resumes content directly and
        // synchronously, so this instant — not some later media event — is
        // exactly the start of the user-facing gap.
        //
        // 计时从这里开始：skip() 会直接同步续播正片，所以这一刻——而非之后
        // 某个媒体事件——正是用户能感知到的间隔的起点。
        _adGapClock = Stopwatch()..start();
        _mark('skipping ad (canSkip=${_controller.canSkip})');
        _controller.skip();
      });
    }));
  }

  void _onAdChange() {
    // Reference only — see the doc comment on the states subscription above
    // for why this fires too early to be the real gap measurement.
    //
    // 仅供参考——为何这个时机太早、不能当作真实间隔，见上方 states 订阅处的
    // 注释。
    if (!_controller.isShowingAd) {
      _mark('MovaAdCtrl phase flipped to content (bookkeeping only, not the real gap)');
      Timer(const Duration(seconds: 5), () {
        if (_adGapClock != null) {
          _adGapClock = null;
          _mark('no renderEpoch bump within 5s — fell back to plain open(), not a seamless swap');
        }
      });
    }
  }

  @override
  void dispose() {
    _skipTimer?.cancel();
    _stateSub?.cancel();
    _controller.dispose();
    _engine.dispose();
    super.dispose();
  }

  /// Appends a timestamped line to the on-screen log and stderr.
  ///
  /// 给屏幕日志和 stderr 都追加一行带时间戳的记录。
  void _mark(String what) {
    final line = '[+${DateTime.now().millisecondsSinceEpoch % 100000}ms] $what';
    // ignore: avoid_print
    print(line);
    if (mounted) setState(() => _log.add(line));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: MovaPlayer(api: _engine, skin: const MovaDefSkin()),
            ),
            Expanded(
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                child: SingleChildScrollView(
                  reverse: true,
                  child: Text(
                    _log.join('\n'),
                    style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
