/// Report event category: a user action, a playback state event, or an
/// error.
///
/// 上报事件的类别：用户操作、播放器状态事件、或错误。
enum MovaReportKind {
  /// A UI-only user action with no corresponding [MovaEvent] — e.g. opening a
  /// settings panel. Reported via [MovaApi.report].
  ///
  /// 纯 UI 语义的用户操作，没有对应的 [MovaEvent]——例如打开设置面板。经
  /// [MovaApi.report] 上报。
  action,

  /// A playback state change mova already emits on [MovaApi.events],
  /// auto-translated by the internal whitelist.
  ///
  /// mova 已在 [MovaApi.events] 上广播的播放状态变化，由内置白名单自动转换。
  event,

  /// A playback error.
  ///
  /// 播放错误。
  error,
}

/// Priority hint only — mova never schedules or batches deliveries itself;
/// the [MovaReporter] implementation decides whether to send immediately or
/// accumulate a batch.
///
/// 仅作优先级提示——mova 自身从不调度或攒批发送，具体是立即发送还是攒批，
/// 完全由 [MovaReporter] 的实现决定。
enum MovaReportPriority {
  /// Hints the host should flush this event right away (e.g. errors, playback
  /// completion) rather than let it sit in a batch.
  ///
  /// 提示宿主应尽快发送该事件（如错误、播放完成），而非留在批次里等待。
  immediate,

  /// Hints the host may accumulate this event with others before sending.
  ///
  /// 提示宿主可以把该事件与其他事件攒在一起再发送。
  batched,
}

/// Names of every action/event/error mova can currently report, plus any
/// host-defined custom name via [MovaReportName.custom].
///
/// This is a deliberately curated whitelist of built-ins, not every
/// [MovaEvent] variant — see `translateMovaEvent` (internal) for which
/// [MovaEvent]s map to which names and why high-frequency intermediate states
/// (drag-in-progress volume/brightness/zoom, buffering flaps, duration/size
/// metadata) are excluded.
///
/// Was an `enum` before 0.2.x. Hosts that `switch` on a name must switch on
/// [value] (a `String`) — Dart forbids constant patterns of a type that
/// overrides `==`. Equality/`hashCode` are by [value], so `==` comparison and
/// `Map`/`Set` keys keep working unchanged.
///
/// mova 当前可上报的全部动作/事件/错误内置名称，以及经 [MovaReportName.custom]
/// 定义的宿主自定义名称。
///
/// 这是刻意精选的内置白名单，并非每个 [MovaEvent] 子类型都在其中——具体哪些
/// [MovaEvent] 映射到哪个名称、为何排除高频中间态（拖动中的音量/亮度/缩放、
/// 缓冲抖动、时长/尺寸等元数据），见内部实现 `translateMovaEvent`。
///
/// 0.2.x 之前是 `enum`。在名称上做 `switch` 的宿主请改成对 [value]（`String`）
/// 做 switch——Dart 不允许对重写了 `==` 的类型使用常量模式。相等性/`hashCode`
/// 按 [value] 计算，因此 `==` 比较与 `Map`/`Set` 键的用法完全不变。
///
/// Example / 示例:
/// ```dart
/// api.report(const MovaReportName.custom('com.acme-fav-tap'));
/// if (e.name == MovaReportName.play) { … }
/// switch (e.name.value) { case 'play': … }
/// ```
class MovaReportName {
  /// The wire name; what analytics backends see.
  ///
  /// 上报到分析后端时看到的名字。
  final String value;

  const MovaReportName._(this.value);

  /// A host-defined name. Prefix it reverse-DNS style (CMCD's convention for
  /// custom keys) so it can never collide with a future mova built-in.
  ///
  /// 宿主自定义的名称。建议用反向 DNS 前缀（CMCD 对自定义键的约定），
  /// 以保证永远不会与 mova 未来的内置项撞名。
  const MovaReportName.custom(this.value) : assert(value != '');

  /// A new source was opened.
  ///
  /// 打开了新的媒体源。
  static const sourceChange = MovaReportName._('sourceChange');

  /// Playback started or resumed.
  ///
  /// 播放开始或恢复。
  static const play = MovaReportName._('play');

  /// Playback was paused.
  ///
  /// 播放已暂停。
  static const pause = MovaReportName._('pause');

  /// A seek was requested.
  ///
  /// 发起了一次跳转。
  static const seek = MovaReportName._('seek');

  /// A seek finished landing.
  ///
  /// 跳转完成落点。
  static const seeked = MovaReportName._('seeked');

  /// Playback reached the end of the media.
  ///
  /// 播放到达媒体末尾。
  static const done = MovaReportName._('done');

  /// A playback error occurred.
  ///
  /// 发生了播放错误。
  static const error = MovaReportName._('error');

  /// The active quality selection changed.
  ///
  /// 当前选中的清晰度发生变化。
  static const qualityChange = MovaReportName._('qualityChange');

  /// ABR downgraded the quality due to buffering pressure.
  ///
  /// 因缓冲压力，ABR 自动降低了清晰度档位。
  static const abrDownShift = MovaReportName._('abrDownShift');

  /// The fullscreen state changed.
  ///
  /// 全屏状态发生变化。
  static const fullScreenChange = MovaReportName._('fullScreenChange');

  /// The picture-in-picture state changed.
  ///
  /// 画中画状态发生变化。
  static const pipChange = MovaReportName._('pipChange');

  /// The in-app mini window state changed.
  ///
  /// App 内小窗状态发生变化。
  static const miniChange = MovaReportName._('miniChange');

  /// Playback caught back up to the live edge.
  ///
  /// 播放已追上直播边缘。
  static const liveEdgeReach = MovaReportName._('liveEdgeReach');

  /// The first frame actually started playing (TTFF landed).
  ///
  /// 首帧真正开始播放（TTFF 落地）。
  static const firstFrame = MovaReportName._('firstFrame');

  /// The session ended before the first frame ever arrived.
  ///
  /// 会话在首帧到达之前就结束了。
  static const startupFail = MovaReportName._('startupFail');

  /// A rebuffer (real stall) finished.
  ///
  /// 一次卡顿（真实卡住）结束。
  static const rebuffer = MovaReportName._('rebuffer');

  /// A new playback session started.
  ///
  /// 一次新的播放会话开始。
  static const sessionStart = MovaReportName._('sessionStart');

  /// A playback session ended.
  ///
  /// 一次播放会话结束。
  static const sessionEnd = MovaReportName._('sessionEnd');

  /// Periodic heartbeat during a long session.
  ///
  /// 长会话期间的周期性心跳。
  static const heartbeat = MovaReportName._('heartbeat');

  /// Every built-in name; custom names are not in here.
  ///
  /// 全部内置名称；自定义名称不在其中。
  static const List<MovaReportName> values = [
    sourceChange,
    play,
    pause,
    seek,
    seeked,
    done,
    error,
    qualityChange,
    abrDownShift,
    fullScreenChange,
    pipChange,
    miniChange,
    liveEdgeReach,
    firstFrame,
    startupFail,
    rebuffer,
    sessionStart,
    sessionEnd,
    heartbeat,
  ];

  /// Enum-source-compatible alias of [value].
  ///
  /// 与枚举写法兼容的 [value] 别名。
  String get name => value;

  @override
  bool operator ==(Object other) => other is MovaReportName && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// A single standardized report event.
///
/// 一条标准化的上报事件。
class MovaReportEvent {
  /// The event's category.
  ///
  /// 事件类别。
  final MovaReportKind kind;

  /// The event's name.
  ///
  /// 事件名称。
  final MovaReportName name;

  /// Extra structured data for this event; empty when the name alone is
  /// enough context.
  ///
  /// 事件的附加结构化数据；名称本身已足够表意时为空。
  final Map<String, dynamic> params;

  /// Priority hint for delivery scheduling; see [MovaReportPriority].
  ///
  /// 发送调度的优先级提示，见 [MovaReportPriority]。
  final MovaReportPriority priority;

  /// When this event was generated.
  ///
  /// 事件产生的时间。
  final DateTime at;

  /// The QoE session this event belongs to; `null` when the QoE layer is off
  /// or the event predates session tracking. This is the one field a host
  /// batching events for later delivery cannot reconstruct on its own — see
  /// `MovaReportConfig`/D6.
  ///
  /// 该事件所属的 QoE 会话；QoE 层关闭或事件产生于会话追踪之前时为 `null`。
  /// 这是宿主攒批延后发送时唯一无法自行重建的字段——见 `MovaReportConfig`/D6。
  final String? sessionId;

  /// Creates a report event.
  ///
  /// 创建一条上报事件。
  const MovaReportEvent({
    required this.kind,
    required this.name,
    this.params = const {},
    required this.priority,
    required this.at,
    this.sessionId,
  });
}

/// Unified reporting sink: hosts implement this to receive every report
/// event mova produces.
///
/// mova only standardizes and tags events — it never sends network requests,
/// batches, or schedules deliveries itself. Where to send, when to send, and
/// whether to batch are entirely the host's responsibility.
///
/// 统一上报出口：宿主实现本接口，接收 mova 产生的所有上报事件。
///
/// mova 只负责生成标准化事件并打标签，不做任何网络发送/批处理/调度——具体
/// 发到哪、何时发、要不要攒批，全部由实现方决定。
///
/// Example / 示例:
/// ```dart
/// final engine = createMovaEngine(
///   reporter: MovaCallbackReporter((event) {
///     myAnalyticsSdk.track(event.name.name, event.params);
///   }),
/// );
/// ```
abstract class MovaReporter {
  /// Called for every report event mova generates.
  ///
  /// [event] 是产生的一条上报事件。
  ///
  /// 每产生一条上报事件都会调用一次。
  void onReport(MovaReportEvent event);
}

/// Wraps a plain callback as a [MovaReporter] (same convenience pattern as
/// `MovaCallbackVolumePort`).
///
/// 把一个简单回调包装成 [MovaReporter]（与 `MovaCallbackVolumePort` 同一
/// 便利模式）。
///
/// Example / 示例:
/// ```dart
/// final reporter = MovaCallbackReporter((event) => print(event.name));
/// ```
class MovaCallbackReporter implements MovaReporter {
  /// The wrapped callback, invoked once per report event.
  ///
  /// 被包装的回调，每条上报事件调用一次。
  final void Function(MovaReportEvent event) onReportCallback;

  /// Creates a reporter that forwards every event to [onReportCallback].
  ///
  /// 创建一个把每条事件转发给 [onReportCallback] 的上报器。
  const MovaCallbackReporter(this.onReportCallback);

  @override
  void onReport(MovaReportEvent event) => onReportCallback(event);
}
