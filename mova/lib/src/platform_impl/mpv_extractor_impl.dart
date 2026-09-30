import 'dart:async';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

import '../core/preview/extractor.dart';

/// The default [MovaFramePuller]: a second, hidden media_kit `Player` used
/// only to decode single frames.
///
/// Reuses the libmpv/ffmpeg already bundled for playback, so preview
/// extraction adds no dependency and does not affect the planned ffmpeg
/// slimming milestone. Playback quality settings are deliberately minimal —
/// audio off, no cache, exact seeks — because these frames are only ever
/// shown as small preview thumbnails. Output is NOT downscaled at the mpv
/// layer: Task 1's spike found that neither `vf=scale` nor
/// `VideoControllerConfiguration` sizing actually shrinks what
/// `screenshot()` returns on Windows (see plan appendix A), so [extract]
/// hands back whatever resolution the source has and `width` is purely
/// advisory (cache key, UI-side target size).
///
/// Calls are serialised internally: libmpv cannot service two seek+screenshot
/// round trips on one player concurrently.
///
/// 默认的 [MovaFramePuller]：第二个隐藏的 media_kit `Player`，只用于解单帧。
///
/// 复用播放时已经打包进来的 libmpv/ffmpeg，因此预览抽帧不引入任何依赖，也不
/// 影响后续 ffmpeg 瘦身里程碑。播放相关设置刻意压到最低——关音频、不做缓存、
/// 精确 seek——因为这些帧只是拿来当小预览图用，不会被真的观看。输出**不**在
/// mpv 层缩放：Task 1 的 spike 发现 Windows 上 `vf=scale` 与
/// `VideoControllerConfiguration` 都不能真正缩小 `screenshot()` 的结果
/// （见计划附录 A），因此 [extract] 原样返回源分辨率的图，`width` 只是
/// 建议值（用于 cache key 与 UI 侧目标尺寸）。
///
/// 内部对调用做了串行化：libmpv 无法在同一个 player 上并发处理两次
/// seek + screenshot 往返。
class MovaFrameExtractor implements MovaFramePuller {
  /// Creates an extractor; the hidden player is created lazily on first use.
  ///
  /// 创建抽帧器；隐藏播放器在首次使用时才惰性创建。
  ///
  /// - [settleDelay]: extra wait after the seek has been observed to land (the
  ///   landing itself is polled) and before screenshotting /
  ///   在观察到 seek 落地（落地本身靠轮询判定）之后、截图之前的额外等待时长
  MovaFrameExtractor({this.settleDelay = const Duration(milliseconds: 60)});

  /// Extra wait after the seek has landed, before screenshotting.
  ///
  /// seek 落地之后、截图之前的额外等待时长。
  final Duration settleDelay;

  /// The hidden player, or null when released.
  ///
  /// 隐藏播放器；已释放时为 null。
  Player? _player;

  /// The hidden player's video controller; kept alive alongside [_player].
  ///
  /// 隐藏播放器的视频控制器；与 [_player] 同生共死。
  /// The media currently open on the hidden player, or null when none.
  ///
  /// 隐藏播放器当前已打开的媒体；无则为 null。
  String? _openUri;

  /// Serialises concurrent [extract] calls onto one hidden player.
  ///
  /// 把并发的 [extract] 调用串行化到同一个隐藏播放器上。
  Future<void> _queue = Future<void>.value();

  /// Whether [dispose] has already run; further calls are no-ops.
  ///
  /// [dispose] 是否已执行过；执行过后所有调用都变为空操作。
  bool _disposed = false;

  /// Creates the hidden player if needed and applies the extraction-tuned mpv
  /// properties.
  ///
  /// 按需创建隐藏播放器，并应用为抽帧调优过的 mpv 属性。
  ///
  /// - [width]: target frame width in pixels / 目标帧宽度（像素）
  /// - [hwdec]: whether hardware decoding may be used / 是否允许硬件解码
  ///
  /// Returns the ready player.
  ///
  /// 返回就绪的播放器。
  Future<Player> _ensurePlayer(int width, bool hwdec) async {
    final existing = _player;
    if (existing != null) return existing;
    final player = Player();
    final native = player.platform;
    if (native is NativePlayer) {
      // 不创建 VideoController：无界面下它的初始化永远完成不了（真机实测），会让后续
      // setProperty 一直等，extract 永不返回。改为手动开视频解码（vid=auto）并把 vo
      // 设为 null——mpv 仍会解码，screenshot() 取得到帧。
      await native.setProperty('ao', 'null');
      await native.setProperty('vo', 'null');
      await native.setProperty('vid', 'auto');
      await native.setProperty('hwdec', hwdec ? 'auto' : 'no');
      await native.setProperty('hr-seek', 'yes');
      await native.setProperty('cache', 'no');
      // `width` is intentionally unused here: neither `vf=scale` nor
      // VideoControllerConfiguration sizing shrinks screenshot() output on
      // Windows (Task 1 spike, plan appendix A), so no mpv-side scaling is
      // attempted.
      //
      // `width` 在此故意不使用：Task 1 的 spike（见计划附录 A）证实
      // Windows 上 `vf=scale` 与 VideoControllerConfiguration 都不能真正
      // 缩小 screenshot() 的输出，因此不在 mpv 层做任何缩放尝试。
    }
    _player = player;
    return player;
  }

  /// Performs one extraction on the hidden player, without queueing.
  ///
  /// 在隐藏播放器上执行一次抽帧，不做排队。
  ///
  /// - [uri]: the media address / 媒体地址
  /// - [at]: the position to extract / 要抽取的位置
  /// - [width]: target width in pixels / 目标宽度（像素）
  /// - [hwdec]: whether hardware decoding may be used / 是否允许硬件解码
  ///
  /// Returns the encoded frame, or null on any failure.
  ///
  /// 返回编码后的帧；任何失败都返回 null。
  /// 以 [pollInterval] 轮询 [done]，直到为真或超过 [timeout]；异常视为"还没好"。
  ///
  /// 返回是否在超时前完成。
  Future<bool> _waitFor(
    Future<bool> Function() done, {
    Duration pollInterval = const Duration(milliseconds: 30),
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (await done()) return true;
      } on Object {
        // 属性暂不可读（媒体未加载完）——继续等。
      }
      await Future<void>.delayed(pollInterval);
    }
    return false;
  }

  Future<Uint8List?> _extractNow(
    String uri,
    Duration at, {
    required int width,
    required bool hwdec,
  }) async {
    if (_disposed) return null;
    try {
      final player = await _ensurePlayer(width, hwdec);
      final native = player.platform;
      if (_openUri != uri) {
        await player.open(Media(uri), play: false);
        _openUri = uri;
        // 时长就绪前 seek 不会落地（首帧会停在第 0 帧），先等它。
        if (native is NativePlayer) {
          final ready = await _waitFor(() async => (double.tryParse(await native.getProperty('duration')) ?? 0) > 0);
          if (!ready) return null;
        }
      }
      await player.seek(at);
      if (native is NativePlayer) {
        // 轮询 seeking/time-pos 判定 seek 真正落地，而不是固定睡一会儿（250ms 会截到
        // 相邻位置的旧帧，真机实测）。
        final target = at.inMilliseconds / 1000.0;
        await _waitFor(() async {
          if (await native.getProperty('seeking') != 'no') return false;
          final pos = double.tryParse(await native.getProperty('time-pos'));
          return pos != null && (pos - target).abs() < 0.3;
        });
      }
      await Future<void>.delayed(settleDelay);
      return await player.screenshot(format: 'image/jpeg');
    } on Object {
      return null;
    }
  }

  @override
  Future<Uint8List?> extract(
    String uri,
    Duration at, {
    required int width,
    required bool hwdec,
  }) {
    final completer = Completer<Uint8List?>();
    _queue = _queue.then((_) async {
      completer.complete(await _extractNow(uri, at, width: width, hwdec: hwdec));
    });
    return completer.future;
  }

  @override
  Future<void> release() async {
    final player = _player;
    _player = null;
    _openUri = null;
    if (player != null) {
      try {
        await player.dispose();
      } on Object {
        // Disposing a hidden helper must never surface as a playback error.
        //
        // 释放隐藏辅助播放器时的异常绝不能冒充成播放错误。
      }
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await release();
  }
}
