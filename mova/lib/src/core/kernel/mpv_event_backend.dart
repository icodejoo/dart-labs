/// mpv 原始事件的值拷贝（脱离原生指针生命周期）。
class MovaRawEvent {
  /// 构造一个原始事件。
  ///
  /// [id] 对应 mpv_event_id。
  /// [endFileReason] 仅针对 END_FILE 事件，对应 mpv_end_file_reason。
  /// 示例: `const MovaRawEvent(7, endFileReason: 2)`
  const MovaRawEvent(this.id, {this.endFileReason});

  /// mpv_event_id。
  final int id;

  /// 仅 END_FILE 有值：mpv_end_file_reason。
  final int? endFileReason;
}

/// 原生事件后端端口；FFI 实现与测试假实现共用。
abstract class MovaMpvEventBackend {
  /// mpv 的 SHUTDOWN 事件 ID。
  static const int eventShutdown = 1;

  /// mpv 的 END_FILE 事件 ID。
  static const int eventEndFile = 7;

  /// mpv 的 PLAYBACK_RESTART 事件 ID。
  static const int eventPlaybackRestart = 21;

  /// 创建弱客户端。
  ///
  /// [name] 为客户端的名称。
  /// 失败返回 false。
  /// 示例：`backend.createClient('mova_qoe_1')`
  bool createClient(String name);

  /// 只保留指定事件，其余关闭。
  ///
  /// [keep] 是要保留的事件 ID 集合。
  /// 返回是否全部成功（部分失败返回 false）。
  /// 示例：`backend.restrictEvents({MovaMpvEventBackend.eventEndFile})`
  bool restrictEvents(Set<int> keep);

  /// 注册"有新事件"的通知。
  ///
  /// 此通知可能来自任意线程的投递，回到 isolate 后会调用 [onWake]。
  /// 示例：`backend.armWakeup(() => pump.wake())`
  void armWakeup(void Function() onWake);

  /// 非阻塞取一个事件（拷贝后返回）。
  ///
  /// 无事件返回 null。
  /// 示例：`final event = backend.poll()`
  MovaRawEvent? poll();

  /// 同步、幂等地注销通知并销毁客户端。
  ///
  /// 示例：`backend.destroy()`
  void destroy();
}
