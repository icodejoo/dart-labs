/// Capabilities injected into a plugin when it is registered.
/// Plugins hold a reference and call [requestFrame] whenever they
/// enqueue a new task and need the ticker to (re-)start.
class CountmanContext {
  const CountmanContext({required this.requestFrame});

  /// Ask the ticker to schedule the next frame.
  /// Idempotent — safe to call even when the ticker is already running.
  final void Function() requestFrame;
}

/// Plugin interface. Each instance owns its own task queue and is
/// registered once on the shared [Countman] ticker.
///
/// Lifecycle:
///   1. [onAttach] — called once by [Countman.use]; store [ctx] for later.
///   2. [tick]     — called every frame; 返回下次唤醒的微秒数。
///   3. [dispose]  — called by [Countman.destroy].
abstract interface class CountmanPlugin {
  /// 空闲标记：当前没有需要调度的活动任务。
  static const int idle = -1;

  /// 下一帧标记：需要连续逐帧处理。
  static const int nextFrame = 0;

  /// 插件的诊断名称；不同实例应使用唯一名称。
  String get name;

  /// Called once when the plugin is registered. Store [ctx.requestFrame]
  /// and call it whenever a new task is added and the ticker may be idle.
  void onAttach(CountmanContext ctx);

  /// 处理一帧，返回距下次处理的微秒数：idle、nextFrame 或正数。
  /// [elapsed] 是帧时间戳，[dt] 是活动帧间隔，休眠后的首帧为零。
  /// 例如返回 `1000000` 允许调度器休眠一秒。
  int tick(Duration elapsed, Duration dt);

  /// 注销时调用；此后可重新挂载，不代表释放资源。
  void onDetach();

  /// 永久释放插件资源；释放后不得复用。
  void dispose();
}
