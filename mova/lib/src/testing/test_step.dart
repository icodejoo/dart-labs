part of 'test_kernel.dart';

enum _Signal { ready, buffering, position, error, completed }

/// 测试内核的一步媒体行为；[after] 表示距上一步的等待时间，首步相对 open。
/// 不需要了解首帧信号组合，就绪步骤会自动发出尺寸、时长、缓冲量和首帧。
/// 示例：`[MovaTestStep.ready(), MovaTestStep.completed(after: Duration(seconds: 2))]`。
class MovaTestStep {
  const MovaTestStep._(
    this._signal, {
    this.after = Duration.zero,
    this._width = 1280,
    this._height = 720,
    this._duration = const Duration(minutes: 1),
    this._position = Duration.zero,
    this._buffering = false,
    this._error,
  });

  /// 在 [after] 后模拟首帧就绪；[width]/[height] 为帧尺寸，[duration] 为媒体时长。
  /// 返回就绪步骤；示例：`MovaTestStep.ready(duration: Duration(minutes: 2))`。
  const MovaTestStep.ready({
    Duration after = Duration.zero,
    int width = 1280,
    int height = 720,
    Duration duration = const Duration(minutes: 1),
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

  /// 在 [after] 后推送内核 [error]，返回失败步骤；分类沿用真实引擎规则。
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

  void _dispatch({
    required void Function(int width, int height, Duration duration) ready,
    required void Function(bool) buffering,
    required void Function(Duration) position,
    required void Function(Object) error,
    required void Function() completed,
  }) {
    switch (_signal) {
      case _Signal.ready:
        ready(_width, _height, _duration);
      case _Signal.buffering:
        buffering(_buffering);
      case _Signal.position:
        position(_position);
      case _Signal.error:
        error(_error!);
      case _Signal.completed:
        completed();
    }
  }
}
