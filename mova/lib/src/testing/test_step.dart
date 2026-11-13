part of 'test_kernel.dart';

enum _Signal { ready, buffering, position, error, completed }

/// 测试内核的一步媒体行为；[after] 表示距上一步的等待时间，首步相对 open。
/// 不需要了解首帧信号组合，就绪步骤会自动发出尺寸、时长、缓冲量和首帧。
/// 示例：`[MovaTestStep.ready(), MovaTestStep.completed(after: Duration(seconds: 2))]`。
///
/// One delayed media signal; ready steps emit the complete first-frame sequence.
class MovaTestStep {
  /// Shared ready-step defaults. / 就绪步骤共用的默认值。
  static const _defaultWidth = 1280;
  static const _defaultHeight = 720;
  static const _defaultDuration = Duration(minutes: 1);

  /// Stores one signal and its payload. / 保存单个信号及其载荷。
  const MovaTestStep._(
    this._signal, {
    this.after = Duration.zero,
    this._width = _defaultWidth,
    this._height = _defaultHeight,
    this._duration = _defaultDuration,
    this._position = Duration.zero,
    this._buffering = false,
    this._error,
  });

  /// 在 [after] 后模拟首帧就绪；[width]/[height] 为帧尺寸，[duration] 为媒体时长。
  /// 返回就绪步骤；示例：`MovaTestStep.ready(duration: Duration(minutes: 2))`。
  const MovaTestStep.ready({
    Duration after = Duration.zero,
    int width = _defaultWidth,
    int height = _defaultHeight,
    Duration duration = _defaultDuration,
  }) : this._(
         _Signal.ready,
         after: after,
         width: width,
         height: height,
         duration: duration,
       );

  /// 在 [after] 后推送 [value] 缓冲状态，返回缓冲步骤。
  /// 示例：`MovaTestStep.buffering(true, after: Duration(seconds: 1))`。
  const MovaTestStep.buffering(bool value, {Duration after = Duration.zero})
    : this._(_Signal.buffering, after: after, buffering: value);

  /// 在 [after] 后推进到 [value]，返回进度步骤。
  /// 示例：`MovaTestStep.position(Duration(seconds: 10))`。
  const MovaTestStep.position(Duration value, {Duration after = Duration.zero})
    : this._(_Signal.position, after: after, position: value);

  /// 在 [after] 后推送内核 [error]，返回失败步骤；分类沿用真实播放器规则。
  /// 示例：`MovaTestStep.error('Failed to open file')`。
  const MovaTestStep.error(Object error, {Duration after = Duration.zero})
    : this._(_Signal.error, after: after, error: error);

  /// 在 [after] 后停止播放并标记结束，返回结束步骤。
  /// 示例：`MovaTestStep.completed(after: Duration(seconds: 2))`。
  const MovaTestStep.completed({Duration after = Duration.zero})
    : this._(_Signal.completed, after: after);

  /// 相对上一步的延迟；零表示异步执行，不留下定时器。
  final Duration after;
  final _Signal _signal;
  final int _width;
  final int _height;
  final Duration _duration;
  final Duration _position;
  final bool _buffering;
  final Object? _error;

  /// Pushes the signal through the kernel's existing emit methods, in order.
  ///
  /// 通过内核现有的 emit 方法按原顺序推送信号。
  void _dispatch(MovaTestKernel kernel) {
    switch (_signal) {
      case _Signal.ready:
        kernel.emitCompleted(false);
        kernel.emitSize(_width, _height);
        kernel.emitDuration(_duration);
        kernel.emitBuffer(_duration);
        kernel.emitPlaying(kernel._scriptPlayIntent);
        kernel.emitRestart();
      case _Signal.buffering:
        kernel.emitBuffering(_buffering);
      case _Signal.position:
        kernel.emitPosition(_position);
      case _Signal.error:
        kernel.emitError(_error!);
      case _Signal.completed:
        kernel.emitPlaying(false);
        kernel.emitCompleted(true);
    }
  }
}
