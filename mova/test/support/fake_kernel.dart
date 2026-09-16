import 'dart:async';
import 'dart:typed_data';

import 'package:mova/src/core/kernel/kernel.dart';

/// A test double for [MovaKernel] that records every call it receives and lets
/// tests push arbitrary state into its streams.
///
/// Used across the test suite (this task and later ones) as the single
/// shared fake kernel implementation.
///
/// [MovaKernel] 的测试替身：记录收到的每次调用，并允许测试向其流中主动推送状态。
///
/// 在整个测试套件中（本任务及后续任务）作为唯一共享的假内核实现。
class FakeKernel implements MovaKernel {
  /// Creates a fake kernel.
  ///
  /// 创建一个假内核。
  ///
  /// - [renderHandle]: the handle this fake reports; defaults to a fresh
  ///   opaque object, pass `null` to emulate an audio-only kernel /
  ///   该假对象对外报告的句柄；默认是一个新建的不透明对象，传 `null` 可模拟
  ///   仅音频内核
  ///
  /// Example / 示例:
  /// ```dart
  /// final k = FakeKernel(renderHandle: null); // audio-only / 仅音频
  /// ```
  FakeKernel({Object? renderHandle = _unset})
      : _renderHandle = identical(renderHandle, _unset) ? Object() : renderHandle;

  /// Sentinel marking "caller passed nothing", so that an explicit
  /// `renderHandle: null` stays null instead of being replaced by the default.
  ///
  /// 用于区分"调用者没传"的哨兵值，使显式传入的 `renderHandle: null` 保持为
  /// null，而不会被默认值顶替。
  static const Object _unset = Object();

  /// The stable handle this fake reports; stable identity matters because
  /// `_RenderSurface` keys itself by handle identity.
  ///
  /// 该假对象报告的稳定句柄；身份稳定很重要，因为 `_RenderSurface` 正是按句柄
  /// 身份做 key。
  final Object? _renderHandle;

  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final StreamController<bool> _buffering = StreamController<bool>.broadcast();
  final StreamController<bool> _completed = StreamController<bool>.broadcast();
  final StreamController<Duration> _position = StreamController<Duration>.broadcast();
  final StreamController<Duration> _duration = StreamController<Duration>.broadcast();
  final StreamController<Duration> _buffer = StreamController<Duration>.broadcast();
  final StreamController<MovaSize> _size = StreamController<MovaSize>.broadcast();
  final StreamController<Object> _error = StreamController<Object>.broadcast();

  /// The ordered list of method names invoked on this fake, e.g.
  /// `['open', 'play', 'seek']`.
  ///
  /// 在该假对象上被调用的方法名有序列表，例如 `['open', 'play', 'seek']`。
  final List<String> calls = <String>[];

  /// The position argument of the most recent [seek] call, or `null` if
  /// [seek] has never been called.
  ///
  /// 最近一次 [seek] 调用的位置参数；若从未调用过 [seek] 则为 `null`。
  Duration? lastSeek;

  /// The URI argument of the most recent [open] call, or `null` if [open]
  /// has never been called.
  ///
  /// 最近一次 [open] 调用的 URI 参数；若从未调用过 [open] 则为 `null`。
  String? lastUri;

  /// The `play` argument of the most recent [open] call, or `null` if
  /// [open] has never been called.
  ///
  /// 最近一次 [open] 调用的 `play` 参数；若从未调用过 [open] 则为 `null`。
  bool? lastPlay;

  /// The bytes returned by [screenshot]; settable by tests, defaults to
  /// `null`.
  ///
  /// [screenshot] 返回的字节数据；可由测试赋值，默认为 `null`。
  Uint8List? fakeShot;

  @override
  Future<void> open(String uri, {bool play = true}) async {
    calls.add('open');
    lastUri = uri;
    lastPlay = play;
  }

  @override
  Future<void> play() async {
    calls.add('play');
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek');
    lastSeek = position;
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('setVolume');
  }

  @override
  Future<void> setRate(double rate) async {
    calls.add('setRate');
  }

  @override
  Future<Uint8List?> screenshot() async {
    calls.add('screenshot');
    return fakeShot;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _playing.close();
    await _buffering.close();
    await _completed.close();
    await _position.close();
    await _duration.close();
    await _buffer.close();
    await _size.close();
    await _error.close();
  }

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Stream<bool> get buffering => _buffering.stream;

  @override
  Stream<bool> get completed => _completed.stream;

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<Duration> get duration => _duration.stream;

  @override
  Stream<Duration> get buffer => _buffer.stream;

  @override
  Stream<MovaSize> get size => _size.stream;

  @override
  Stream<Object> get error => _error.stream;

  @override
  Object? get renderHandle => _renderHandle;

  /// Pushes a playing/paused state into [playing].
  ///
  /// 向 [playing] 推送一个播放/暂停状态。
  void emitPlaying(bool value) => _playing.add(value);

  /// Pushes a buffering state into [buffering].
  ///
  /// 向 [buffering] 推送一个缓冲状态。
  void emitBuffering(bool value) => _buffering.add(value);

  /// Pushes a completed state into [completed].
  ///
  /// 向 [completed] 推送一个播放完成状态。
  void emitCompleted(bool value) => _completed.add(value);

  /// Pushes a position into [position].
  ///
  /// 向 [position] 推送一个播放进度。
  void emitPosition(Duration value) => _position.add(value);

  /// Pushes a duration into [duration].
  ///
  /// 向 [duration] 推送一个总时长。
  void emitDuration(Duration value) => _duration.add(value);

  /// Pushes a buffered position into [buffer].
  ///
  /// 向 [buffer] 推送一个已缓冲进度。
  void emitBuffer(Duration value) => _buffer.add(value);

  /// Pushes a video frame size into [size].
  ///
  /// 向 [size] 推送一个视频帧尺寸。
  void emitSize(int width, int height) => _size.add(MovaSize(width: width, height: height));

  /// Pushes an error into [error].
  ///
  /// 向 [error] 推送一个错误。
  void emitError(Object value) => _error.add(value);
}
