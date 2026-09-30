import 'dart:async';

import 'mpv_event_backend.dart';

/// 泵的生命周期状态。
enum _PumpState {
  /// 初始状态。
  idle,

  /// 注册中。
  registering,

  /// 活跃（可排空事件）。
  active,

  /// 正在关闭。
  closing,

  /// 已关闭。
  closed,
}

/// 纯逻辑状态机：负责驱动原生事件排空，处理并发与销毁不变量。
class MovaMpvEventPump {
  /// 构造事件泵。
  ///
  /// [name] 用于标识此客户端。
  /// [onRestart] 当发生播放重置时回调。
  /// [onEndFile] 当发生文件结束时回调，传入原因码。
  /// 示例：`MovaMpvEventPump(backend, name: 'qoe_0', onRestart: () {}, onEndFile: (r) {})`
  MovaMpvEventPump(
    this._backend, {
    required this.name,
    required this.onRestart,
    required this.onEndFile,
  });

  final MovaMpvEventBackend _backend;
  
  /// 客户端名称。
  final String name;
  
  /// PLAYBACK_RESTART 回调。
  final void Function() onRestart;
  
  /// END_FILE 回调。
  final void Function(int reason) onEndFile;

  /// 当前状态机状态。
  _PumpState _state = _PumpState.idle;

  /// 记录启动过程的 Future。
  Future<void>? _startFuture;

  /// 记录销毁过程的 Future。
  Future<void>? _disposeFuture;

  /// 核心是否已消失 (收到 SHUTDOWN)。
  bool _coreGone = false;

  /// 客户端是否已成功创建。
  bool _clientCreated = false;

  /// 发起注册。
  ///
  /// [ready] 为等待"原生句柄可用"的 Future（生产中是 NativePlayer.handle）。
  /// 返回一个不抛异常的 Future。
  /// 示例：`await pump.start(native.handle)`
  Future<void> start(Future<void> ready) async {
    if (_state != _PumpState.idle) return; // 忽略重复调用
    _state = _PumpState.registering;
    _startFuture = _doStart(ready);
    await _startFuture;
  }

  /// 执行实际的启动流程。
  Future<void> _doStart(Future<void> ready) async {
    try {
      await ready;

      if (_state == _PumpState.closing || _state == _PumpState.closed) {
        _teardown();
        return;
      }

      if (!_backend.createClient(name)) {
        _state = _PumpState.closed;
        _teardown();
        return;
      }
      _clientCreated = true;

      if (_state == _PumpState.closing || _state == _PumpState.closed) {
        _teardown();
        return;
      }

      // 即使 restrict 部分失败，也继续 armWakeup
      _backend.restrictEvents({
        MovaMpvEventBackend.eventShutdown,
        MovaMpvEventBackend.eventEndFile,
        MovaMpvEventBackend.eventPlaybackRestart,
      });

      if (_state == _PumpState.closing || _state == _PumpState.closed) {
        _teardown();
        return;
      }

      _backend.armWakeup(_onWake);

      if (_state == _PumpState.closing || _state == _PumpState.closed) {
        _teardown();
        return;
      }

      _state = _PumpState.active;
    } catch (_) {
      _state = _PumpState.closed;
      _teardown();
    }
  }

  /// 同步、幂等地关闭泵并释放资源。
  ///
  /// 示例：`await pump.dispose()`
  Future<void> dispose() {
    if (_disposeFuture != null) return _disposeFuture!;
    
    _state = _PumpState.closing;
    _teardown();
    _state = _PumpState.closed;
    
    _disposeFuture = Future.value();
    return _disposeFuture!;
  }

  /// 内部清理方法，负责安全的释放后端资源。
  void _teardown() {
    if (_clientCreated) {
      _clientCreated = false;
      try {
        _backend.destroy();
      } catch (_) {
        // 吞掉 destroy 异常
      }
    }
  }

  /// 原生事件唤醒时的回调，负责排空事件。
  void _onWake() {
    if (_state == _PumpState.closed || _state == _PumpState.closing) return;
    if (_coreGone) return;

    while (_state == _PumpState.active && !_coreGone) {
      MovaRawEvent? event;
      try {
        event = _backend.poll();
      } catch (_) {
        // poll 抛异常，转 closed 态/停止排空、不无限重试
        _state = _PumpState.closed;
        break;
      }
      
      if (event == null) break;

      if (event.id == MovaMpvEventBackend.eventShutdown) {
        _coreGone = true;
        break;
      }

      if (event.id == MovaMpvEventBackend.eventPlaybackRestart) {
        try {
          onRestart();
        } catch (_) {}
      } else if (event.id == MovaMpvEventBackend.eventEndFile) {
        try {
          if (event.endFileReason != null) {
            onEndFile(event.endFileReason!);
          }
        } catch (_) {}
      }
    }
  }
}
