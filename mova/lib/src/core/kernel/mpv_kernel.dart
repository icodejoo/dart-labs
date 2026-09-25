import 'dart:async';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'kernel.dart';

/// A [MovaKernel] implementation backed by media_kit's `Player`.
///
/// This is the one file in the core layer allowed to depend on
/// `package:media_kit`; every other file under `lib/src/core/` must stay
/// engine-agnostic.
///
/// 基于 media_kit `Player` 实现的 [MovaKernel]。
///
/// 这是核心层中唯一允许依赖 `package:media_kit` 的文件；`lib/src/core/` 下
/// 其余所有文件都必须与具体引擎无关。
class MovaMpvKernel implements MovaKernel {
  /// Creates the media_kit-backed kernel.
  ///
  /// [player] lets callers inject an existing `Player` (e.g. for testing or
  /// custom configuration); when omitted a new `Player()` is created.
  ///
  /// [audioOnly] skips creating the `VideoController` entirely. media_kit's
  /// `Player` already starts with mpv's `--vid=no` and it is *only*
  /// `VideoController.create()` that flips it back to `vid=auto`
  /// (media_kit 1.2.6, `player/native/player/real.dart` `_create()` and
  /// `video_controller/native_video_controller/real.dart`), so not attaching
  /// one leaves libmpv decoding audio and nothing else: no decoded frame
  /// buffers, no GPU texture, no Flutter `Texture` registration. Those three
  /// are the whole of the video-side memory cost, and in audio-only mode they
  /// are zero rather than merely smaller.
  ///
  /// 创建基于 media_kit 的内核。
  ///
  /// [player] 允许调用者注入一个已存在的 `Player`（如用于测试或自定义配置）；
  /// 省略时会创建一个新的 `Player()`。
  ///
  /// [audioOnly] 表示完全跳过 `VideoController` 的创建。media_kit 的 `Player`
  /// 一创建就是 mpv 的 `--vid=no`，**只有** `VideoController.create()` 会把它
  /// 改回 `vid=auto`（media_kit 1.2.6，见 `player/native/player/real.dart` 的
  /// `_create()` 与 `video_controller/native_video_controller/real.dart`），
  /// 因此不挂接它就等于让 libmpv 只解音频：没有解码帧缓冲、没有 GPU 纹理、
  /// 没有 Flutter `Texture` 注册。这三项就是视频侧内存开销的全部，在仅音频
  /// 模式下它们是 0，而不只是变小。
  ///
  /// 升级 media_kit 时须重验"默认 `--vid=no`"这一条。
  MovaMpvKernel({Player? player, this.audioOnly = false}) : _player = player ?? Player() {
    if (!audioOnly) {
      _controller = VideoController(_player);
    }
    _widthSub = _player.stream.width.listen((w) {
      _lastWidth = w ?? 0;
      _widthSeen = true;
      _emitSize();
    });
    _heightSub = _player.stream.height.listen((h) {
      _lastHeight = h ?? 0;
      _heightSeen = true;
      _emitSize();
    });
  }

  /// One-time global media_kit init; call before creating any [MovaMpvKernel].
  ///
  /// 全局一次性 media_kit 初始化；创建任何 [MovaMpvKernel] 前调用。
  static void ensureInitialized() => MediaKit.ensureInitialized();

  /// The wrapped media_kit player instance.
  ///
  /// 被包裹的 media_kit 播放器实例。
  final Player _player;

  /// Whether this kernel was built without a video pipeline.
  ///
  /// 该内核是否在不带视频管线的形态下构造。
  final bool audioOnly;

  /// The video controller used to attach this kernel to a video widget;
  /// `null` when [audioOnly].
  ///
  /// 用于把该内核挂接到视频组件上的控制器；[audioOnly] 时为 `null`。
  VideoController? _controller;

  StreamSubscription<int?>? _widthSub;
  StreamSubscription<int?>? _heightSub;

  /// The most recently observed frame width; seeded to 0 until the first
  /// callback arrives.
  ///
  /// 最近观测到的帧宽度；首次回调到达前为 0。
  int _lastWidth = 0;

  /// The most recently observed frame height; seeded to 0 until the first
  /// callback arrives.
  ///
  /// 最近观测到的帧高度；首次回调到达前为 0。
  int _lastHeight = 0;

  /// Whether the width stream has delivered at least one value yet.
  ///
  /// 宽度流是否已至少推送过一次值。
  bool _widthSeen = false;

  /// Whether the height stream has delivered at least one value yet.
  ///
  /// 高度流是否已至少推送过一次值。
  bool _heightSeen = false;

  final StreamController<MovaSize> _sizeController = StreamController<MovaSize>.broadcast();

  /// Combines the latest cached width/height into a [MovaSize] and pushes it
  /// to listeners, but only once both dimensions have been observed at
  /// least once — this avoids emitting a bogus intermediate size (e.g.
  /// width-only) before media_kit has reported both.
  ///
  /// 将缓存的最新宽/高合并为 [MovaSize] 并推送给监听者；但只有当两个维度都已
  /// 被观测到至少一次时才会推送，以避免在 media_kit 尚未同时报告二者前推送
  /// 出错误的中间尺寸（如只有宽度）。
  void _emitSize() {
    if (!_widthSeen || !_heightSeen) return;
    _sizeController.add(MovaSize(width: _lastWidth, height: _lastHeight));
  }

  @override
  Future<void> open(String uri, {bool play = true}) => _player.open(Media(uri), play: play);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  /// Captures the current video frame as an encoded image, or `null` when
  /// there is no video pipeline to capture from.
  ///
  /// Short-circuiting here rather than letting mpv fail keeps the scrub-preview
  /// frame-extraction fallback (`MovaPreviewSource`) on its documented
  /// "extractor returned nothing → degrade gracefully" path instead of
  /// surfacing an mpv error to the host.
  ///
  /// 截取当前视频帧并编码为图片；没有视频管线可截时返回 `null`。
  ///
  /// 在此短路而不是让 mpv 自己失败，可以让拖动预览的抽帧兜底
  /// （`MovaPreviewSource`）走它既有的"抽帧器没给结果 → 平滑降级"路径，而不是把
  /// 一个 mpv 错误抛给宿主。
  @override
  Future<Uint8List?> screenshot() async =>
      audioOnly ? null : _player.screenshot(format: 'image/jpeg');

  @override
  Future<void> dispose() async {
    await _widthSub?.cancel();
    await _heightSub?.cancel();
    await _sizeController.close();
    await _player.dispose();
  }

  @override
  Stream<bool> get playing => _player.stream.playing;

  @override
  Stream<bool> get buffering => _player.stream.buffering;

  @override
  Stream<bool> get completed => _player.stream.completed;

  @override
  Stream<Duration> get position => _player.stream.position;

  @override
  Stream<Duration> get duration => _player.stream.duration;

  @override
  Stream<Duration> get buffer => _player.stream.buffer;

  @override
  Stream<MovaSize> get size => _sizeController.stream;

  @override
  Stream<Object> get error => _player.stream.error;

  @override
  Object? get renderHandle => _controller;
}
