import 'dart:async';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../model/quality.dart';
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
class MpvKernel implements MovaKernel {
  /// Creates the media_kit-backed kernel.
  ///
  /// [player] lets callers inject an existing `Player` (e.g. for testing or
  /// custom configuration); when omitted a new `Player()` is created.
  ///
  /// 创建基于 media_kit 的内核。
  ///
  /// [player] 允许调用者注入一个已存在的 `Player`（如用于测试或自定义配置）；
  /// 省略时会创建一个新的 `Player()`。
  MpvKernel({Player? player}) : _player = player ?? Player() {
    _controller = VideoController(_player);
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

  /// One-time global media_kit init; call before creating any [MpvKernel].
  ///
  /// 全局一次性 media_kit 初始化；创建任何 [MpvKernel] 前调用。
  static void ensureInitialized() => MediaKit.ensureInitialized();

  /// The wrapped media_kit player instance.
  ///
  /// 被包裹的 media_kit 播放器实例。
  final Player _player;

  /// The video controller used to attach this kernel to a video widget.
  ///
  /// 用于把该内核挂接到视频组件上的控制器。
  late final VideoController _controller;

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

  @override
  Future<Uint8List?> screenshot() => _player.screenshot(format: 'image/jpeg');

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
  Object get renderHandle => _controller;

  @override
  Stream<List<MovaVideoTrack>> get videoTracks =>
      _player.stream.tracks.map((t) => t.video.where((v) => v.id != 'no').map(_toMovaTrack).toList());

  @override
  Stream<MovaVideoTrack> get videoTrack => _player.stream.track
      .map((t) => t.video)
      .where((v) => v.id != 'no')
      .map(_toMovaTrack);

  @override
  Future<void> setVideoTrack(MovaVideoTrack track) =>
      _player.setVideoTrack(track.isAuto ? VideoTrack.auto() : VideoTrack(track.id, track.title, null));

  /// Converts a media_kit [VideoTrack] to the engine-agnostic
  /// [MovaVideoTrack].
  ///
  /// 把 media_kit 的 [VideoTrack] 转换为引擎无关的 [MovaVideoTrack]。
  MovaVideoTrack _toMovaTrack(VideoTrack t) => MovaVideoTrack(
        id: t.id,
        title: t.title,
        width: t.w,
        height: t.h,
        bitrate: t.bitrate,
        codec: t.codec,
      );
}
