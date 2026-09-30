import 'dart:async';
import 'dart:ffi';

import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/media_kit.dart';
import '../core/kernel/mpv_event_backend.dart';

/// 规划应开启或关闭的事件 ID 的结果。
class MovaEventPlan {
  final Set<int> enable;
  final Set<int> disable;

  MovaEventPlan({required this.enable, required this.disable});
}

/// 纯函数，根据需要保留的事件（[keep]）规划哪些需要 enable，哪些需要 disable。
/// [SHUTDOWN] 和 [NONE] 永远不会出现在结果中。
MovaEventPlan planEventRequests(Set<int> keep) {
  final enable = <int>{};
  final disable = <int>{};
  for (final id in allEventIds()) {
    if (id == generated.mpv_event_id.MPV_EVENT_NONE || id == generated.mpv_event_id.MPV_EVENT_SHUTDOWN) {
      continue;
    }
    if (keep.contains(id)) {
      enable.add(id);
    } else {
      disable.add(id);
    }
  }
  return MovaEventPlan(enable: enable, disable: disable);
}

/// 所有已知的 mpv_event_id，用于 restrictEvents 时关闭不需要的事件。
///
/// 提取为公开纯函数方便单元测试断言覆盖完整。
List<int> allEventIds() {
  return [
    generated.mpv_event_id.MPV_EVENT_NONE,
    generated.mpv_event_id.MPV_EVENT_SHUTDOWN,
    generated.mpv_event_id.MPV_EVENT_LOG_MESSAGE,
    generated.mpv_event_id.MPV_EVENT_GET_PROPERTY_REPLY,
    generated.mpv_event_id.MPV_EVENT_SET_PROPERTY_REPLY,
    generated.mpv_event_id.MPV_EVENT_COMMAND_REPLY,
    generated.mpv_event_id.MPV_EVENT_START_FILE,
    generated.mpv_event_id.MPV_EVENT_END_FILE,
    generated.mpv_event_id.MPV_EVENT_FILE_LOADED,
    generated.mpv_event_id.MPV_EVENT_TRACKS_CHANGED,
    generated.mpv_event_id.MPV_EVENT_TRACK_SWITCHED,
    generated.mpv_event_id.MPV_EVENT_IDLE,
    generated.mpv_event_id.MPV_EVENT_PAUSE,
    generated.mpv_event_id.MPV_EVENT_UNPAUSE,
    generated.mpv_event_id.MPV_EVENT_TICK,
    generated.mpv_event_id.MPV_EVENT_SCRIPT_INPUT_DISPATCH,
    generated.mpv_event_id.MPV_EVENT_CLIENT_MESSAGE,
    generated.mpv_event_id.MPV_EVENT_VIDEO_RECONFIG,
    generated.mpv_event_id.MPV_EVENT_AUDIO_RECONFIG,
    generated.mpv_event_id.MPV_EVENT_METADATA_UPDATE,
    generated.mpv_event_id.MPV_EVENT_SEEK,
    generated.mpv_event_id.MPV_EVENT_PLAYBACK_RESTART,
    generated.mpv_event_id.MPV_EVENT_PROPERTY_CHANGE,
    generated.mpv_event_id.MPV_EVENT_CHAPTER_CHANGE,
    generated.mpv_event_id.MPV_EVENT_QUEUE_OVERFLOW,
    generated.mpv_event_id.MPV_EVENT_HOOK,
  ];
}

/// 解析 mpv 事件的纯函数，便于测试数据拷贝规则。
///
/// [id] 是事件的 ID。
/// [reasonReader] 是当需要读取原因时调用的闭包，只有 [id] 为 END_FILE 且数据不为空时才调用。
MovaRawEvent? copyEvent(int id, int? Function() reasonReader) {
  if (id == generated.mpv_event_id.MPV_EVENT_NONE) {
    return null;
  }
  int? reason;
  if (id == generated.mpv_event_id.MPV_EVENT_END_FILE) {
    reason = reasonReader();
  }
  return MovaRawEvent(id, endFileReason: reason);
}

/// 提供 MovaMpvEventBackend 的 FFI 工厂函数。
///
/// [native] 是 [NativePlayer] 实例。
/// [handleAddress] 是其底层 handle 指针的地址。
/// [pollInDebug] 决定是否在调试模式下降级为轮询（比如热重载后原生回调可能失效）。
MovaMpvEventBackend createFfiMpvEventBackend(NativePlayer native, int handleAddress, {required bool pollInDebug}) {
  return FfiMpvEventBackend(
    native.mpv,
    Pointer<generated.mpv_handle>.fromAddress(handleAddress),
    pollInDebug: pollInDebug,
  );
}

/// 基于 `dart:ffi` 的 [MovaMpvEventBackend] 实现，封装了 mpv 的弱客户端逻辑。
class FfiMpvEventBackend implements MovaMpvEventBackend {
  /// 构造 FFI 后端。
  ///
  /// [mpv] 是生成绑定的对象。
  /// [_ctx] 是父级 mpv_handle。
  /// [pollInDebug] 如果为 true，则在调试模式使用定时器轮询以应对热重载，否则使用原生回调。
  FfiMpvEventBackend(this.mpv, this._ctx, {required this.pollInDebug});

  /// FFI 绑定接口。
  final generated.MPV mpv;
  
  /// 父客户端句柄。
  final Pointer<generated.mpv_handle> _ctx;
  
  /// 是否以 debug 轮询模式运行。
  final bool pollInDebug;

  /// 弱客户端句柄。
  Pointer<generated.mpv_handle> _client = nullptr;

  /// 原生回调监听器。
  NativeCallable<Void Function(Pointer<Void>)>? _callable;

  /// 调试模式下的轮询定时器。
  Timer? _timer;

  /// 内部状态，标识是否已经被销毁，用于保证 [destroy] 的幂等性。
  bool _destroyed = false;

  @override
  bool createClient(String name) {
    if (_destroyed) return false;
    if (_client != nullptr) return false;
    final namePtr = name.toNativeUtf8(allocator: calloc);
    try {
      _client = mpv.mpv_create_weak_client(_ctx, namePtr.cast<Int8>());
      if (_client == nullptr) {
        return false;
      }
      return true;
    } finally {
      calloc.free(namePtr);
    }
  }

  @override
  bool restrictEvents(Set<int> keep) {
    if (_client == nullptr) return false;
    bool allSuccess = true;
    final plan = planEventRequests(keep);
    for (final id in plan.enable) {
      try {
        if (mpv.mpv_request_event(_client, id, 1) < 0) allSuccess = false;
      } catch (_) {
        allSuccess = false;
      }
    }
    for (final id in plan.disable) {
      try {
        if (mpv.mpv_request_event(_client, id, 0) < 0) allSuccess = false;
      } catch (_) {
        allSuccess = false;
      }
    }
    return allSuccess;
  }

  @override
  void armWakeup(void Function() onWake) {
    if (_destroyed || _client == nullptr) return;

    if (pollInDebug) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!_destroyed) onWake();
      });
    } else {
      _callable?.close();
      _callable = NativeCallable<Void Function(Pointer<Void>)>.listener((Pointer<Void> _) {
        if (!_destroyed) onWake();
      });
      try {
        mpv.mpv_set_wakeup_callback(_client, _callable!.nativeFunction, _client.cast<Void>());
      } catch (_) {
        // 容错
      }
    }
  }

  @override
  MovaRawEvent? poll() {
    if (_destroyed || _client == nullptr) return null;
    try {
      final ev = mpv.mpv_wait_event(_client, 0);
      return copyEvent(ev.ref.event_id, () {
        if (ev.ref.data == nullptr) return null;
        return ev.ref.data.cast<generated.mpv_event_end_file>().ref.reason;
      });
    } catch (_) {
      return null;
    }
  }

  @override
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;

    if (_client != nullptr) {
      try {
        mpv.mpv_set_wakeup_callback(_client, nullptr, nullptr);
      } catch (_) {}
    }

    try {
      _callable?.close();
      _callable = null;
    } catch (_) {}

    try {
      _timer?.cancel();
      _timer = null;
    } catch (_) {}

    if (_client != nullptr) {
      try {
        mpv.mpv_destroy(_client);
      } catch (_) {}
      _client = nullptr;
    }
  }
}
