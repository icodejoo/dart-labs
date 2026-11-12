import 'dart:async';

import 'package:flutter/foundation.dart';

/// 条目的出场方式，与 affix 保护声明相互独立。
enum OverlayMode {
  /// 默认，串行排队。
  queue,

  /// 抢占所在 slot 的当前条目。
  replace,

  /// 绕过队列叠加；普通条件和冷却现在或永不，业务 waitUntil 可等待。
  overlap,
}

/// 条目当前所处的生命周期阶段。
enum OverlayPhase {
  /// 等待条件、冷却或槽位释放。
  pending,

  /// 已占据槽位，正在解析数据。
  resolving,

  /// 后端已展示条目。
  open,

  /// 已请求关闭，等待后端退场完成。
  closing,
}

/// 匹配上下文中的路由；非 String 路由始终不匹配。
///
/// 例如 `route: const RouteMatcher.exact('/home')` 精确匹配路径，
/// `const RouteMatcher.anyOf(['/home', '/profile'])` 匹配多个路径，
/// `RouteMatcher.regex(RegExp(r'^/user/'))` 匹配路径模式。
sealed class RouteMatcher {
  /// 供内部路由匹配器初始化。
  const RouteMatcher();

  /// 创建与 [path] 精确相等的匹配器。
  const factory RouteMatcher.exact(String path) = _ExactRoute;

  /// 创建匹配 [paths] 中任一路径的匹配器；调用方不应修改该列表。
  const factory RouteMatcher.anyOf(List<String> paths) = _AnyOfRoute;

  /// 创建使用 [pattern] 的 hasMatch 判断路径的匹配器。
  factory RouteMatcher.regex(RegExp pattern) = _RegexRoute;

  /// 返回 [route] 是否匹配；null 或非 String 值返回 false。
  bool matches(Object? route);
}

/// 精确路径匹配器。
class _ExactRoute extends RouteMatcher {
  /// 保存目标路径。
  const _ExactRoute(this.path);

  /// 必须完全相等的路径。
  final String path;

  /// 路由资格匹配条件。
  @override
  bool matches(Object? route) => route is String && route == path;
}

/// 候选路径列表匹配器。
class _AnyOfRoute extends RouteMatcher {
  /// 保存候选路径列表。
  const _AnyOfRoute(this.paths);

  /// 允许匹配的路径。
  final List<String> paths;

  /// 返回给定路由是否满足此匹配规则。
  @override
  bool matches(Object? route) => route is String && paths.contains(route);
}

/// 正则路径匹配器。
class _RegexRoute extends RouteMatcher {
  /// 保存正则表达式。
  _RegexRoute(this.pattern);

  /// 用于 hasMatch 的表达式。
  final RegExp pattern;

  /// 返回给定路由是否满足此匹配规则。
  @override
  bool matches(Object? route) => route is String && pattern.hasMatch(route);
}

/// 条目为什么结束，或为什么没有出场。
enum OverlayEndReason {
  /// 管理器主动关闭。
  closed,

  /// 后端自行关闭，例如用户点击或返回。
  dismissedByBackend,

  /// 展示时长到期。
  expired,

  /// 被 replace 条目抢占。
  replaced,

  /// 被同 id 的新提交取代。
  superseded,

  /// 被 remove、clear 或 clearWhere 移除。
  removed,

  /// 展示条件不再满足。
  unmet,

  /// 解析返回空值、抛出异常或超时。
  skipped,

  /// overlap 当前不满足条件或冷却要求。
  dropped,

  /// session 或 total 永久上限已耗尽。
  capped,

  /// 被 suppress 抑制。
  suppressed,

  /// 被业务 gate 永久拒绝。
  gated,

  /// 槽位排队已满，被挤出队尾。
  queueFull,

  /// 排队时间超过 expireAfter。
  queueExpired,

  /// 展示后端抛出异常。
  failed,

  /// 管理器已销毁。
  disposed,
}

/// 业务激活资格；与 route、auth、when 及 cooldown 按 AND 组合。
/// 只在激活前求值，不影响已解析或已展示的条目。
/// pass 允许激活，waitUntil 等待后重判，drop 永久拒绝并以 gated 结束。
/// gate 异常与 when/auth 有意共用每条目一次的上报名额；用法见 `OverlayGate`。
@immutable
class OverlayVerdict {
  /// 允许激活，仍须通过其他资格及槽位约束。
  const OverlayVerdict.pass()
      : retryAt = null,
        reason = null;

  /// 等到 [retryAt] 后自动重判；已到期的时刻视为通过，仍须满足其他激活约束。
  /// 必须按 Layerman.clock 计时，例如 `manager.clock.now().add(...)`；
  /// FakeOverlayClock 下用 DateTime.now() 会算错截止时间。
  /// 串行与 overlap 均可等待；期间 setContext 会重判，可提前通过、延后或永久拒绝。
  const OverlayVerdict.waitUntil(DateTime this.retryAt) : reason = null;

  /// 永久拒绝条目；业务拒绝一律以 [OverlayEndReason.gated] 结束。
  /// 调用方可在自己的 gate 闭包里记录具体原因。
  const OverlayVerdict.drop()
      : retryAt = null,
        reason = OverlayEndReason.gated;

  /// 与 Layerman.clock 同源的自动重判时刻；pass 或 drop 时为 null。
  final DateTime? retryAt;

  /// drop 固定为 [OverlayEndReason.gated]；pass 或 waitUntil 时为 null。
  final OverlayEndReason? reason;
}

/// 单次提交首次结束时的值与原因。
/// 可见前被关闭、超时或后端关闭，reason 仍为 closed、expired 或 dismissedByBackend，
/// 但没有 shown；可用管理器 events 判断本次提交是否出现过 shown。
@immutable
class OverlayOutcome<T> {
  /// 保存可空的 [value] 与结束 [reason]。
  const OverlayOutcome(this.value, this.reason);

  /// 关闭结果；没有结果时为 null。
  final T? value;

  /// 第一次结束的原因，之后不再改变。
  final OverlayEndReason reason;
}

/// 条目生命周期中的事件种类。
enum OverlayEventType {
  /// 提交进入管理器。
  queued,

  /// 后端已确认可见；可见前结束的条目不会产生此事件。
  shown,

  /// 首次结束。
  ended,
}

/// 异步广播的条目生命周期事件。
@immutable
class OverlayEvent {
  /// 保存事件类型、条目标识与槽位；[reason] 仅 ended 时有值。
  const OverlayEvent({
    required this.type,
    required this.id,
    required this.slot,
    this.reason,
  });

  /// 生命周期事件类型。
  final OverlayEventType type;

  /// 条目的标识，同 id 的不同提交各自发出事件。
  final String id;

  /// 条目所属槽位。
  final String slot;

  /// ended 事件的原因；其他事件为 null。
  final OverlayEndReason? reason;
}

/// 单个槽位的可选配置，未提供的字段使用全局默认行为。
@immutable
class OverlaySlotOptions {
  /// [gap] 覆盖全局间隔；[maxQueued] 限制未激活条目数，必须大于零。
  const OverlaySlotOptions({
    this.gap,
    this.maxQueued,
    this.blockedBy = const <String>{},
  });

  /// 这些 slot 被 resolving、open、closing 或 overlap 占用时，不激活本 slot 新条目。
  /// 不影响已激活条目；不存在的 slot 无效果，不能包含自己。
  /// 例如 `Layerman(slots: {'toast': OverlaySlotOptions(blockedBy: {'modal'}),
  /// 'banner': OverlaySlotOptions(blockedBy: {'modal'})})`。
  final Set<String> blockedBy;

  /// 该槽位关闭一个条目后等待的间隔。
  final Duration? gap;

  /// 排队数量上限，不包含已激活的条目。
  final int? maxQueued;
}

/// 指定冷却配置在当前时刻的资格快照。
@immutable
class OverlayCooldownStatus {
  /// [canShow] 表示全部上限通过；永久受阻或等待读取时 [wait] 为 null。
  const OverlayCooldownStatus(
      {required this.canShow,
      required this.permanentlyBlocked,
      required this.wait,
      this.suppressed = false});

  /// 当前存在未到期的抑制；抑制期间 canShow 为 false。
  final bool suppressed;

  /// 当前所有上限是否通过。
  final bool canShow;

  /// session / total 已耗尽或永久抑制，时间流逝不会解除。
  final bool permanentlyBlocked;

  /// 时间上限的最长剩余等待；可展示时为 Duration.zero。
  final Duration? wait;
}

/// 引擎读取时间与创建计时器的唯一来源。
abstract class OverlayClock {
  /// 供自定义时钟初始化。
  const OverlayClock();

  /// 系统时钟：DateTime.now 与 dart:async Timer。
  static const OverlayClock system = _SystemOverlayClock();

  /// 返回当前时间，须与计时器的时间推进同源。
  DateTime now();

  /// 创建单次计时器；返回值可用于取消等待。
  Timer createTimer(Duration duration, void Function() callback);
}

/// 使用系统时间及当前 Zone 的计时器。
class _SystemOverlayClock extends OverlayClock {
  /// 创建无状态系统时钟。
  const _SystemOverlayClock();

  /// 返回当前时钟时间。
  @override
  DateTime now() => DateTime.now();

  /// 创建单次计时器，返回可取消的 Timer。
  @override
  Timer createTimer(Duration duration, void Function() callback) =>
      Timer(duration, callback);
}
