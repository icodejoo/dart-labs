import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'overlay_types.dart';

/// 条件判断函数，接收 setContext 合并后的只读上下文。
/// 1.0 起 route、auth、when 按 AND 组合，所有已提供条件必须同时满足。
typedef OverlayPredicate = bool Function(Map<String, Object?> context);

/// 频次限制配置：所有非空限制按 AND 组合，后端成功展示时计数。
/// [session] 限制本实例次数；[total] 限制持久化累计次数；
/// [day]、[hour]、[minute] 限制本地日历周期次数并持久化；
/// [minGap] 为距最近展示的滚动最小间隔并持久化。
/// 所有配置均接受 suppress；空配置仅接受抑制，不限制次数。
class OverlayCooldown {
  /// 创建频次限制，未提供的限制不生效，各限制按 AND 组合。
  const OverlayCooldown({
    this.session,
    this.total,
    this.day,
    this.hour,
    this.minute,
    this.minGap,
  });

  /// 本管理器实例内最多展示次数。
  final int? session;

  /// 持久化累计展示次数上限。
  final int? total;

  /// 每个本地日历日的展示次数上限。
  final int? day;

  /// 每个本地日历小时的展示次数上限。
  final int? hour;

  /// 每个本地日历分钟的展示次数上限。
  final int? minute;

  /// 距最近展示的滚动最小间隔。
  final Duration? minGap;

  /// 是否有需要持久化的频次限制。
  bool get _needsPersistence =>
      total != null ||
      day != null ||
      hour != null ||
      minute != null ||
      minGap != null;
}

/// 冷却计数的可替换持久化接口，默认使用 [MemoryCooldownStorage]。
/// 应用可用 shared_preferences 等实现 [read] 和 [write]，保存完整 JSON 字符串：
///
/// ```dart
/// class PrefsCooldownStorage implements OverlayCooldownStorage {
///   Future<String?> read(String key) async =>
///       (await SharedPreferences.getInstance()).getString(key);
///   Future<void> write(String key, String value) async =>
///       (await SharedPreferences.getInstance()).setString(key, value);
/// }
/// ```
abstract class OverlayCooldownStorage {
  /// 读取 [key] 的完整存储字符串；不存在时返回 null。
  Future<String?> read(String key);

  /// 将完整的 [value] 写入 [key]，返回写入完成的 Future。
  Future<void> write(String key, String value);
}

/// 进程内冷却存储；复用同一实例时可跨管理器重建保留数据。
class MemoryCooldownStorage implements OverlayCooldownStorage {
  /// 按存储键保存的进程内字符串。
  final Map<String, String> _store = <String, String>{};

  /// 返回 [key] 对应的内存字符串，不存在时为 null。
  @override
  Future<String?> read(String key) async => _store[key];

  /// 保存 [key] 对应的完整字符串，返回完成信号。
  @override
  Future<void> write(String key, String value) async => _store[key] = value;
}

/// 单条受管弹层的只读快照，供查询及 [Layerman.clearWhere] 判断使用。
class OverlayRecord {
  /// 保存条目各字段的只读快照。
  const OverlayRecord._(
      this.id, this.slot, this.data, this.active, this.phase, this.tags);

  /// 条目的唯一标识。
  final String id;

  /// 条目所属的槽位名。
  final String slot;

  /// 条目的数据快照。
  final Object? data;

  /// 是否正占据串行槽位或活跃叠加位置，排队中为 false。
  final bool active;

  /// 条目当前的生命周期阶段。
  final OverlayPhase phase;

  /// 提交时复制的只读标签集合，默认空集合。
  final Set<String> tags;
}

/// 获得展示资格时传给 [Present] 的类型化上下文。
class PresentContext<T> {
  /// 保存展示快照、实时数据及绑定身份的关闭回调。
  const PresentContext._(
      this.id, this.slot, this.data, this.dataListenable, this._close);

  /// 本次提交的唯一标识，与 [Layerman.open] 指定或生成的 id 相同。
  final String id;

  /// 此条目所属的串行槽位名称。
  final String slot;

  /// 展示时的数据快照；提供 resolve 时为解析后的值。
  final Object? data;

  /// 实时数据通道；update 和 resolve 更新时通知，data 仍为展示时快照。
  final ValueListenable<Object?> dataListenable;

  /// 绑定本次提交身份的关闭入口。
  final void Function(T? result) _close;

  /// 请求携带结果关闭自己，遵守 beforeClose；旧条目、非 open 或守卫未决时无操作。
  void close([T? result]) => _close(result);
}

/// 由 [Present] 返回的双向后端句柄。
/// [dismissed] 必须在点击、遮罩、返回键、超时及程序关闭等任一路径完成，
/// 其结果交付给 [Layerman.open]。
/// [dismiss] 必须定向关闭本弹层：保存 Route 对象，在栈顶且无内部历史时 pop，
/// 否则 removeRoute；也可使用 SnackbarController.close() 或 CancelFunc。
class PresentedOverlay<T> {
  /// 绑定所有关闭路径的完成信号及可选定向关闭回调。
  PresentedOverlay({required this.dismissed, this.dismiss});

  /// 后端完全关闭时完成，并返回可空的关闭结果。
  final Future<T?> dismissed;

  /// 请求后端关闭并可选传递结果。推荐保存 Route 对象：栈顶且无内部历史时 pop，
  /// 否则 removeRoute；或保存 SnackbarController.close()、CancelFunc。
  /// 为 null 时编排器只能摘除条目，后端自行管理生命周期。
  final Future<void> Function([T? result])? dismiss;
}

/// 获得展示资格后调用的唯一渲染入口，每个条目至多调用一次。
/// 回调可推入路由、使用 GetX、bot_toast 或自管 OverlayEntry，
/// 返回 [PresentedOverlay] 供编排器等待及定向关闭；编排器本身不操作组件树。
typedef Present<T> = PresentedOverlay<T> Function(PresentContext<T> context);

/// 单次提交的类型化句柄；同 id 重开后，旧票的操作静默失效。
class OverlayTicket<T> {
  /// 将类型化结果与操作绑定到本次条目身份。
  OverlayTicket._(this._manager, this._entry, this._result, this._outcome)
      : id = _entry.id,
        slot = _entry.slot;

  /// 拥有此次提交的管理器。
  final Layerman _manager;

  /// 此票唯一绑定的条目身份。
  final _Entry _entry;

  /// 兼容 open 的结果通道。
  final Future<T?> _result;

  /// 携带首次结束原因的结果通道。
  final Future<OverlayOutcome<T>> _outcome;

  /// 此次提交的标识。
  final String id;

  /// 此次提交所属槽位。
  final String slot;

  /// 结束时返回结果；未出场或无结果时为 null。
  Future<T?> get result => _result;

  /// 首次结束时的结果与原因。
  Future<OverlayOutcome<T>> get outcome => _outcome;

  /// 此条目是否仍被管理器跟踪，包含排队和退场阶段。
  bool get isActive => !_manager.isDisposed && _manager._isCurrent(_entry);

  /// 以类型化的 [result] 关闭 open 条目，遵守 beforeClose；排队及解析中无操作，取消用 remove。
  void close([T? result]) {
    _manager._checkMutation();
    if (isActive) _manager._batch(() => _manager._close(_entry, result));
  }

  /// 立即移除此条目，绕过关闭守卫。
  void remove() {
    _manager._checkMutation();
    if (isActive) _manager._batch(() => _manager._remove(_entry));
  }

  /// 更新此条目数据；Map 浅合并，其余值替换。
  void update(Object? patch) {
    _manager._checkMutation();
    if (isActive) _manager.update(id, patch);
  }

  /// 此条目的实时数据通道，结束后仍可读取最后的数据。
  ValueListenable<Object?> get data => _entry.dataNotifier;
}

/// 独立的暂停来源；释放幂等，不会覆盖其他暂停来源。
class OverlayHold {
  /// 保存暂停原因、释放操作与修改检查。
  OverlayHold._(this.reason, this._release, this._check);

  /// 调用方提供的暂停原因，仅用于描述。
  final Object? reason;

  /// 释放回调；清空即表示已释放。
  VoidCallback? _release;

  /// 释放前检查管理器是否处于判断回调。
  final VoidCallback _check;

  /// 是否已经释放，管理器销毁后也为 true。
  bool get isReleased => _release == null;

  /// 释放此次暂停；重复调用或管理器销毁后无操作。
  void release() {
    _check();
    final callback = _release;
    _release = null;
    callback?.call();
  }
}

/// 擦除泛型后的内部排队及活跃条目。
class _Entry {
  /// 保存单次提交的配置、结果回调与实时数据。
  _Entry({
    required this.id,
    required this.slot,
    required this.tags,
    required this.priority,
    required this.seq,
    required this.replace,
    required this.affix,
    required this.delay,
    required this.duration,
    required this.exitDuration,
    required this.when,
    required this.route,
    required this.auth,
    required this.dismissWhenUnmet,
    required this.cooldown,
    required this.beforeClose,
    required this.resolveData,
    required this.presentBackend,
    required this.settle,
    required this.settleOutcome,
    required this.acceptsResult,
    required Object? data,
    required this.resolveTimeout,
  }) : dataNotifier = ValueNotifier<Object?>(data);

  /// 条目的唯一标识。
  final String id;

  /// 条目所属的槽位名。
  final String slot;

  /// 提交时复制的标签，调用方后续修改不影响条目。
  final Set<String> tags;

  /// 出场优先级，越大越靠前。
  final int priority;

  /// 提交序号，用于同优先级先进先出。
  final int seq;

  /// 是否处于抢占前排带。
  final bool replace;

  /// 是否保护当前条目免受抢占。
  final bool affix;

  /// 出场前的额外等待时间。
  final Duration? delay;

  /// 展示后的自动关闭时长。
  final Duration? duration;

  /// 后端关闭信号之后的退场宽限。
  final Duration? exitDuration;

  /// 额外业务条件，读取只读上下文。
  final OverlayPredicate? when;

  /// 路由资格匹配条件。
  final RouteMatcher? route;

  /// 业务认证或权限判断函数。
  final OverlayPredicate? auth;

  /// 条件失效时是否自动移除。
  final bool dismissWhenUnmet;

  /// 频次限制与抑制配置。
  final OverlayCooldown? cooldown;

  /// 显式关闭的可同步或异步守卫。
  final FutureOr<bool> Function()? beforeClose;

  /// 后端数据解析函数；返回 null 时跳过展示。
  final Future<Object?> Function()? resolveData;

  /// 调用用户的 [Present] 并绑定擦除泛型的句柄，获得资格时仅调用一次。
  final void Function() presentBackend;

  /// 展示后绑定的后端定向关闭回调。
  Future<void> Function(Object? result)? externalDismiss;

  /// 后端是否已报告关闭，或已被要求按移除路径关闭。
  bool externalDone = false;

  /// 是否已经请求过后端 dismiss；每个条目最多请求一次，避免 close 之后
  /// 又因 remove / clear / dismiss 超时再请求一次（对 popUntil、Get.back()
  /// 这类非幂等后端会误关别的弹窗）。
  bool dismissRequested = false;

  /// 仅完成一次结果 Future，类型转换由闭包负责。
  final void Function(Object? result) settle;

  /// 完成类型化的结束结果。
  final void Function(Object? result, OverlayEndReason reason) settleOutcome;

  /// 第一次结束原因，后续关闭回调不能覆盖。
  OverlayEndReason? endReason;

  /// 尚未激活的串行条目过期计时器。
  Timer? queueTimer;

  /// overlap 独立的出场延迟计时器，不占串行槽位。
  Timer? overlapDelayTimer;

  /// 实时数据通知器；退场动画可能继续监听，不主动 dispose，由 GC 回收。
  final ValueNotifier<Object?> dataNotifier;

  /// 当前数据，写入时同步通知后端。
  Object? get data => dataNotifier.value;

  /// 写入新数据并通知实时通道的监听者。
  set data(Object? value) => dataNotifier.value = value;

  /// 此条目解析的最长等待时间；null 表示不限时。
  final Duration? resolveTimeout;

  /// 等待后端完成关闭的兜底计时器。
  Timer? dismissTimer;

  /// 等待解析完成的兜底计时器。
  Timer? resolveTimer;

  /// 条目离开或解析结束时取消兜底计时器。
  void cancelTimeouts() {
    overlapDelayTimer?.cancel();
    overlapDelayTimer = null;
    queueTimer?.cancel();
    queueTimer = null;
    dismissTimer?.cancel();
    dismissTimer = null;
    resolveTimer?.cancel();
    resolveTimer = null;
  }

  /// 条目当前的生命周期阶段。
  OverlayPhase phase = OverlayPhase.pending;

  /// 接管或抢占时是否跳过间隔及延迟。
  bool skipGap = false;

  /// 是否已经消费过串行出场延迟。
  bool delayConsumed = false;

  /// 校验擦除泛型后的关闭结果。
  final bool Function(Object? result) acceptsResult;

  /// 防止异步关闭守卫重复执行。
  bool closeGuardPending = false;

  /// 每个条目的条件异常最多上报一次。
  bool conditionErrorReported = false;

  /// 首次结果是否已经交付。
  bool settled = false;

  /// 是否单独暂停此条目的时长。
  bool paused = false;

  /// 是否有暂停期间暂存的解析数据。
  bool hasHeldData = false;

  /// 自动关闭倒计时。
  Timer? durationTimer;

  /// 自动关闭倒计时的到期时间。
  DateTime? durationDeadline;

  /// 暂停期间保留的剩余展示时长。
  Duration? durationRemaining;

  /// 后端关闭后的退场宽限计时器。
  Timer? removeTimer;

  /// 是否已激活，包含解析、展示和退场。
  bool get isActive =>
      phase == OverlayPhase.open ||
      phase == OverlayPhase.closing ||
      phase == OverlayPhase.resolving;

  /// 是否已经展示，包含退场阶段。
  bool get isShown =>
      phase == OverlayPhase.open || phase == OverlayPhase.closing;
}

/// 单个槽位的串行运行状态。
class _Slot {
  /// 当前占据串行槽位的条目。
  _Entry? active;

  /// 构建期间同 id 重开保留接管优先权。
  _Entry? takeover;

  /// 是否因跨槽位占用而等待解除。
  bool waitingUnblock = false;

  /// 按出场顺序排列的等待条目。
  final List<_Entry> queue = <_Entry>[];

  /// 槽位关闭后的间隔计时器。
  Timer? gapTimer;

  /// 当前队列条目的出场延迟计时器。
  Timer? delayTimer;

  /// 串行出场延迟的属主，必须仍在此槽位队列内。
  _Entry? delayOwner;

  /// 最近一次时间冷却到期的唤醒计时器。
  Timer? cooldownTimer;

  /// 是否正在等待关闭后的间隔。
  bool gapPending = false;
}

/// 抑制到期时间的持久化键。
const _suppressedUntilKey = 'su';

/// 永久抑制的可精确 JSON 表示，等于 DateTime 最大毫秒数。
const _suppressForeverMs = 8640000000000000;

/// 按 id 持久化的冷却计数和抑制记录。
class _CooldownRecord {
  /// 初始化计数、日历桶及抑制状态。
  _CooldownRecord({
    this.total = 0,
    this.dayBucket = '',
    this.dayCount = 0,
    this.hourBucket = '',
    this.hourCount = 0,
    this.minuteBucket = '',
    this.minuteCount = 0,
    this.lastShownMs,
    this.suppressedUntilMs,
  });

  /// 解析短键 JSON，字段类型不符时抛出异常。
  factory _CooldownRecord.fromJson(Map<String, Object?> json) =>
      _CooldownRecord(
        total: (json['t'] as num?)?.toInt() ?? 0,
        dayBucket: json['db'] as String? ?? '',
        dayCount: (json['dc'] as num?)?.toInt() ?? 0,
        hourBucket: json['hb'] as String? ?? '',
        hourCount: (json['hc'] as num?)?.toInt() ?? 0,
        minuteBucket: json['mb'] as String? ?? '',
        minuteCount: (json['mc'] as num?)?.toInt() ?? 0,
        lastShownMs: (json['ls'] as num?)?.toInt(),
        suppressedUntilMs: (json[_suppressedUntilKey] as num?)?.toInt(),
      );

  /// 持久化累计展示次数上限。
  int total;

  /// 最近计数的本地日历日桶。
  String dayBucket;

  /// 当前日桶的累计展示次数。
  int dayCount;

  /// 最近计数的本地小时桶。
  String hourBucket;

  /// 当前小时桶的累计展示次数。
  int hourCount;

  /// 最近计数的本地分钟桶。
  String minuteBucket;

  /// 当前分钟桶的累计展示次数。
  int minuteCount;

  /// 最近成功展示时刻的 Unix 毫秒数。
  int? lastShownMs;

  /// 抑制到期时间；null 表示从未抑制。
  int? suppressedUntilMs;

  /// 返回可持久化的短键 JSON 记录。
  Map<String, Object?> toJson() => <String, Object?>{
        't': total,
        'db': dayBucket,
        'dc': dayCount,
        'hb': hourBucket,
        'hc': hourCount,
        'mb': minuteBucket,
        'mc': minuteCount,
        'ls': lastShownMs,
        _suppressedUntilKey: suppressedUntilMs,
      };
}

/// 统一上报引擎与存储异常，保留操作上下文。
void _reportError(Object error, StackTrace stack, String what) {
  FlutterError.reportError(FlutterErrorDetails(
    exception: error,
    stack: stack,
    library: 'layerman',
    context: ErrorDescription(what),
  ));
}

/// 将整数格式化为至少两位的十进制字符串。
String _two(int n) => n < 10 ? '0$n' : '$n';

/// 返回本地日期的日桶键。
String _dayBucketOf(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';

/// 返回本地日期的小时桶键。
String _hourBucketOf(DateTime t) => '${_dayBucketOf(t)}T${_two(t.hour)}';

/// 返回本地日期的分钟桶键。
String _minuteBucketOf(DateTime t) => '${_hourBucketOf(t)}:${_two(t.minute)}';

/// 仅读取一次的冷却存储；读取完成后同步查询，变更后异步写回。
class _CooldownStore {
  /// 绑定冷却持久化后端及存储键。
  _CooldownStore(this._storage, this._key);

  /// 完整 JSON 表的持久化后端。
  final OverlayCooldownStorage _storage;

  /// 持久化使用的存储键。
  final String _key;

  /// 已成功解析的各 id 频次与抑制记录。
  final Map<String, _CooldownRecord> _persisted = <String, _CooldownRecord>{};

  /// 无法解析的原始记录，仅显式重置时删除。
  final _unparsed = <String, Object?>{};

  /// 当前管理器会话内的展示计数。
  final Map<String, int> _session = <String, int>{};

  /// 读取成功或失败后均允许调度继续。
  bool _hydrated = false;

  /// 等待落盘的最新快照是否有变化。
  bool _dirty = false;

  /// 保证同一存储最多只有一次写入在途。
  bool _writing = false;

  /// hydrate 前的重置墓碑，防止旧存储记录重新进入内存。
  final _resetIds = <String>{};

  /// hydrate 前是否已请求清空全部记录。
  bool _resetAll = false;

  /// 清除指定 id 或全部计数，并串行写回最新快照。
  void reset([String? id]) {
    if (id == null) {
      _session.clear();
      _persisted.clear();
      _unparsed.clear();
      if (!_hydrated) _resetAll = true;
    } else {
      _session.remove(id);
      _persisted.remove(id);
      _unparsed.remove(id);
      if (!_hydrated) _resetIds.add(id);
    }
    _flush();
  }

  /// 读取持久化计数并与内存中可能已有的记录合并。
  Future<void> hydrate() async {
    try {
      final raw = await _storage.read(_key);
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, Object?>;
        for (final entry in decoded.entries) {
          if (_resetAll || _resetIds.contains(entry.key)) continue;
          final value = entry.value;
          try {
            if (value is! Map) throw FormatException('冷却记录必须是 Map');
            final incoming =
                _CooldownRecord.fromJson(value.cast<String, Object?>());
            final current = _persisted[entry.key];
            _persisted[entry.key] =
                current == null ? incoming : _merge(current, incoming);
          } catch (error, stack) {
            _unparsed[entry.key] = value;
            _reportError(
                error, stack, 'while hydrating cooldown record "${entry.key}"');
          }
        }
      }
    } catch (error, stack) {
      _reportError(error, stack, 'while hydrating cooldown storage "$_key"');
    } finally {
      _hydrated = true;
      _resetIds.clear();
      _resetAll = false;
      if (_dirty) _flush();
    }
  }

  /// 合并累计次数、最新时间桶和最近展示时间。
  _CooldownRecord _merge(_CooldownRecord a, _CooldownRecord b) {
    /// 同桶累加，异桶保留较新桶的计数。
    int count(String ab, int ac, String bb, int bc) =>
        ab == bb ? ac + bc : (ab.compareTo(bb) > 0 ? ac : bc);

    /// 取字典序较新的日历桶。
    String bucket(String a, String b) => a.compareTo(b) >= 0 ? a : b;
    final al = a.lastShownMs;
    final bl = b.lastShownMs;
    final au = a.suppressedUntilMs;
    final bu = b.suppressedUntilMs;
    return _CooldownRecord(
      total: a.total + b.total,
      dayBucket: bucket(a.dayBucket, b.dayBucket),
      dayCount: count(a.dayBucket, a.dayCount, b.dayBucket, b.dayCount),
      hourBucket: bucket(a.hourBucket, b.hourBucket),
      hourCount: count(a.hourBucket, a.hourCount, b.hourBucket, b.hourCount),
      minuteBucket: bucket(a.minuteBucket, b.minuteBucket),
      minuteCount:
          count(a.minuteBucket, a.minuteCount, b.minuteBucket, b.minuteCount),
      lastShownMs: al == null ? bl : (bl == null || al > bl ? al : bl),
      suppressedUntilMs: au == null ? bu : (bu == null || au > bu ? au : bu),
    );
  }

  /// 直接调用存储写入；读取或写入未决时只保留脏位。
  void _flush() {
    _dirty = true;
    if (!_hydrated || _writing) return;
    _dirty = false;
    _writing = true;
    // 先放损坏原值，再用有效记录覆盖同 id：重新展示或抑制后不能写回旧的损坏值。
    final json = <String, Object?>{
      ..._unparsed,
      for (final e in _persisted.entries) e.key: e.value.toJson(),
    };

    /// 上报写入失败并允许后续脏快照继续写入。
    void onWriteError(Object error, StackTrace stack) {
      _reportError(error, stack,
          'while writing cooldown storage "$_key" (ids: ${json.keys.join(', ')})');
      _finishWrite();
    }

    try {
      _storage.write(_key, jsonEncode(json)).then(
            (_) => _finishWrite(),
            onError: onWriteError,
          );
    } catch (error, stack) {
      onWriteError(error, stack);
    }
  }

  /// 在途写入结束后补写最新快照。
  void _finishWrite() {
    _writing = false;
    if (_dirty) _flush();
  }

  /// 延长指定 id 的抑制并复用串行写入。
  void suppress(String id, Duration? duration, DateTime now) {
    final rec = _persisted.putIfAbsent(id, _CooldownRecord.new);
    final until = duration == null
        ? _suppressForeverMs
        : now.add(duration).millisecondsSinceEpoch;
    final previous = rec.suppressedUntilMs;
    if (previous == null || until > previous) rec.suppressedUntilMs = until;
    _flush();
  }

  /// 当前内存中已知的抑制是否仍有效。
  bool suppressed(String id, DateTime now) {
    final until = _persisted[id]?.suppressedUntilMs;
    return until != null &&
        (until == _suppressForeverMs || until > now.millisecondsSinceEpoch);
  }

  /// session 与永久抑制立即受阻；total 必须读取完成后才能判定。
  bool permanentlyBlocked(String id, OverlayCooldown cd) =>
      (cd.session != null && (_session[id] ?? 0) >= cd.session!) ||
      _persisted[id]?.suppressedUntilMs == _suppressForeverMs ||
      (_hydrated &&
          cd.total != null &&
          (_persisted[id]?.total ?? 0) >= cd.total!);

  /// 返回全部冷却限制是否通过，仅零等待通过。
  bool canShow(String id, OverlayCooldown cd, DateTime now) =>
      timeUntilEligible(id, cd, now) == Duration.zero;

  /// 返回抑制与时间型上限的最长等待；全部通过为零。
  /// 读取未完成、session / total 耗尽或永久抑制时为 null。
  /// 串行队列据此在时间限制解除后自动唤醒。
  Duration? timeUntilEligible(String id, OverlayCooldown cd, DateTime now) {
    now = now.toLocal();
    if (!_hydrated || permanentlyBlocked(id, cd)) return null;
    final rec = _persisted[id];
    var wait = Duration.zero;

    /// 将总等待延长到各约束的最大等待。
    void bump(Duration d) {
      if (d > wait) wait = d;
    }

    final until = rec?.suppressedUntilMs;
    if (until != null && until > now.millisecondsSinceEpoch) {
      bump(Duration(milliseconds: until - now.millisecondsSinceEpoch));
    }
    if (cd.day != null) {
      final c =
          rec != null && rec.dayBucket == _dayBucketOf(now) ? rec.dayCount : 0;
      if (c >= cd.day!) {
        final next = DateTime(now.year, now.month, now.day + 1);
        bump(next.difference(now));
      }
    }
    if (cd.hour != null) {
      final c = rec != null && rec.hourBucket == _hourBucketOf(now)
          ? rec.hourCount
          : 0;
      if (c >= cd.hour!) {
        final next = DateTime(now.year, now.month, now.day, now.hour + 1);
        bump(next.difference(now));
      }
    }
    if (cd.minute != null) {
      final c = rec != null && rec.minuteBucket == _minuteBucketOf(now)
          ? rec.minuteCount
          : 0;
      if (c >= cd.minute!) {
        final next =
            DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
        bump(next.difference(now));
      }
    }
    if (cd.minGap != null && rec?.lastShownMs != null) {
      final remain = cd.minGap!.inMilliseconds -
          (now.millisecondsSinceEpoch - rec!.lastShownMs!);
      if (remain > 0) bump(Duration(milliseconds: remain));
    }
    return wait;
  }

  /// 记录成功展示，更新会话及需要持久化的日历计数。
  void record(String id, OverlayCooldown cd, DateTime now) {
    now = now.toLocal();
    if (cd.session != null) _session[id] = (_session[id] ?? 0) + 1;
    if (!cd._needsPersistence) return;
    final rec = _persisted.putIfAbsent(id, _CooldownRecord.new);
    rec.total += 1;
    final dayB = _dayBucketOf(now);
    rec.dayCount = rec.dayBucket == dayB ? rec.dayCount + 1 : 1;
    rec.dayBucket = dayB;
    final hourB = _hourBucketOf(now);
    rec.hourCount = rec.hourBucket == hourB ? rec.hourCount + 1 : 1;
    rec.hourBucket = hourB;
    final minB = _minuteBucketOf(now);
    rec.minuteCount = rec.minuteBucket == minB ? rec.minuteCount + 1 : 1;
    rec.minuteBucket = minB;
    rec.lastShownMs = now.millisecondsSinceEpoch;
    _flush();
  }
}

/// 不负责渲染的弹层队列编排器。
/// 通过 [Present] 展示、[PresentedOverlay] 定向关闭，返回 Future 结果。
/// 支持独立槽位串行队列、优先级、抢占、affix 保护、延迟叠加、条件与冷却、
/// 数据解析、关闭守卫、两阶段退场及全局或单条目暂停时长。
class Layerman extends ChangeNotifier {
  /// 创建管理器；[gap] 默认零，[slots] 可覆盖槽位的间隔、容量及阻塞来源。
  /// [resolveTimeout] 默认 30 秒，[dismissTimeout] 默认 10 秒，null 禁用对应超时。
  /// [cooldownStorage] 默认内存存储，[storageKey] 默认 layerman:cooldown；
  /// [clock] 默认系统时钟，[pauseOnRoutes] 默认空列表。
  /// 例如 `final manager = Layerman(gap: const Duration(milliseconds: 300));`。
  Layerman({
    this.gap = Duration.zero,
    Map<String, OverlaySlotOptions> slots = const {},
    this.dismissTimeout = const Duration(seconds: 10),
    this.resolveTimeout = const Duration(seconds: 30),
    OverlayCooldownStorage? cooldownStorage,
    String storageKey = 'layerman:cooldown',
    this.clock = OverlayClock.system,
    List<RouteMatcher> pauseOnRoutes = const <RouteMatcher>[],
  })  : assert(slots.values.every(
            (options) => options.maxQueued == null || options.maxQueued! > 0)),
        assert(slots.entries.every((e) => !e.value.blockedBy.contains(e.key))),
        slots = Map<String, OverlaySlotOptions>.unmodifiable(slots),
        _pauseOnRoutes = pauseOnRoutes {
    _blockedByOf = {
      for (final e in slots.entries)
        if (e.value.blockedBy.isNotEmpty)
          e.key: Set<String>.unmodifiable(e.value.blockedBy),
    };
    _blockerSlots = _blockedByOf.values.expand((s) => s).toSet();
    _blockableSlots = _blockedByOf.keys.toSet();
    _cooldowns =
        _CooldownStore(cooldownStorage ?? MemoryCooldownStorage(), storageKey);
    _ready = _cooldowns.hydrate().then((_) => _batch(() {
          _hydrationApplied = true;
          if (isDisposed) return;
          _discardPermanentlyBlockedQueues();
          if (!_paused) {
            _applyRelease();
          } else {
            _notify();
          }
        }));
  }

  /// 当前是否处于构建帧；纯 Dart/headless 未初始化绑定时 instance 会抛出。
  bool get _inBuildPhase {
    try {
      return SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks;
    } catch (_) {
      return false;
    }
  }

  /// 判断回调的嵌套深度，期间禁止任何状态写入。
  int _judging = 0;

  /// 检查判断回调内的非法重入，必须在任何状态变化之前调用。
  void _checkMutation() {
    if (_judging > 0) throw StateError('判断函数内不能修改 Layerman');
  }

  /// 在只读判断作用域中执行回调，异常保持原传播方式。
  R _judge<R>(R Function() test) {
    _judging++;
    try {
      return test();
    } finally {
      _judging--;
    }
  }

  /// 取消 delay 属主后需在本批次容器稳定时重调度的槽位。
  final _rescheduleSlots = <String>{};

  /// 调度后仅对仍在等待的有序队尾执行容量淘汰。
  void _enforceCapacity(String name, _Slot slot) {
    final max = slots[name]?.maxQueued;
    while (max != null && slot.queue.length > max) {
      _remove(slot.queue.last, reason: OverlayEndReason.queueFull);
    }
  }

  /// 公开操作与异步状态变化的嵌套批次深度。
  int _batchDepth = 0;

  /// 当前批次是否需要通知。
  bool _notifyPending = false;

  /// 是否已经登记帧后通知。
  bool _frameNotifyPending = false;

  /// 本帧已登记调度的槽位。
  final _deferredSlots = <String>{};

  /// 是否已经登记帧后释放。
  bool _releasePending = false;

  /// 槽位到阻塞来源的不可变副本。
  late final Map<String, Set<String>> _blockedByOf;

  /// 所有可能阻塞别人的槽位。
  late final Set<String> _blockerSlots;

  /// 配置了阻塞来源的槽位。
  late final Set<String> _blockableSlots;

  /// 本批次曾释放阻塞来源，需在占用稳定后处理。
  bool _unblockPending = false;

  /// hydrate 续延已应用，区别于存储刚刚读完的微任务窗口。
  bool _hydrationApplied = false;

  /// 是否有阻塞来源正在串行或 overlap 占用；环按先激活者占用，不保证公平。
  bool _slotBlocked(String slot) =>
      (_blockedByOf[slot] ?? const <String>{}).any((name) =>
          _slots[name]?.active != null || _overlaps.any((e) => e.slot == name));

  /// 最外层批次结束前仅释放受跨槽位约束的条目。
  /// 只重排确实因阻塞而等待（waitingUnblock）的 slot，不给其他 slot 增加
  /// 条件重判的触发点；等待 hydrate 的 overlap 留在原位，保持持有顺序。
  void _releaseUnblocked() {
    while (_unblockPending && !isDisposed) {
      _unblockPending = false;
      if (_paused) continue;
      if (_inBuildPhase) {
        _deferRelease();
        continue;
      }
      for (final e in _pendingOverlaps.toList()) {
        if (_blockableSlots.contains(e.slot) &&
            !_waitingForHydrate(e) &&
            !_slotBlocked(e.slot)) {
          _pendingOverlaps.remove(e);
          _releaseOverlap(e);
        }
      }
      for (final slot in _blockableSlots) {
        final s = _slots[slot];
        if (s != null && s.waitingUnblock && !_slotBlocked(slot)) {
          _schedule(slot);
        }
      }
    }
  }

  /// 原子完成一组同步状态变化，最外层结束后回收槽位并统一通知。
  R _batch<R>(R Function() action) {
    _checkMutation();
    _batchDepth++;
    try {
      return action();
    } finally {
      if (_batchDepth == 1) {
        do {
          while (_rescheduleSlots.isNotEmpty && !isDisposed) {
            final pending = _rescheduleSlots.toList();
            _rescheduleSlots.clear();
            pending.forEach(_schedule);
          }
          _releaseUnblocked();
          if (!isDisposed) {
            for (final item in _slots.entries.toList()) {
              if (!_deferredSlots.contains(item.key)) {
                _enforceCapacity(item.key, item.value);
              }
            }
          }
        } while (_rescheduleSlots.isNotEmpty && !isDisposed);
      }
      _batchDepth--;
      if (_batchDepth == 0) {
        _slots.removeWhere((_, s) =>
            s.active == null &&
            s.queue.isEmpty &&
            s.gapTimer == null &&
            s.delayTimer == null &&
            s.cooldownTimer == null &&
            !s.gapPending);
        assert(() {
          debugCheckInvariants();
          return true;
        }());
        if (_notifyPending) {
          _notifyPending = false;
          _notify();
        }
      }
    }
  }

  /// 合并批次内通知；构建中统一延至帧后，销毁后静默忽略。
  void _notify() {
    if (isDisposed) return;
    if (_batchDepth > 0) {
      _notifyPending = true;
      return;
    }
    if (_inBuildPhase) {
      if (_frameNotifyPending) return;
      _frameNotifyPending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) => _batch(() {
            if (!_frameNotifyPending) return;
            _frameNotifyPending = false;
            if (!isDisposed) _notify();
          }));
      return;
    }
    // 帧后展示产生的通知同时覆盖本帧已登记的通知。
    _frameNotifyPending = false;
    super.notifyListeners();
  }

  /// 帧后复用暂停释放判定；暂停或 hydrate 未完成时继续等待。
  void _deferRelease() {
    if (_releasePending) return;
    _releasePending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => _batch(() {
          _releasePending = false;
          if (!isDisposed) _applyRelease();
        }));
  }

  /// 测试用的当前运行时槽位数量，不包含 slots 配置。
  @visibleForTesting
  int get debugSlotCount => _slots.length;

  /// 测试专用：反转抑制、阻塞等待或 overlap 持有状态，以验证反向不变量。
  @visibleForTesting
  void debugCorruptInvariant(String kind, String id) => _batch(() {
        final e = _byId[id]!;
        switch (kind) {
          case 'i':
            _cooldowns.suppress(id, null, clock.now());
          case 'j':
            _slots[e.slot]!.waitingUnblock = true;
          case 'k':
            _detachFromActive(e);
            e.phase = OverlayPhase.pending;
            _pendingOverlaps.add(e);
        }
      });

  /// 验证容器身份、阶段、排序、计时器及销毁状态；违反时抛出 StateError。
  /// release 下也可显式调用；自动检查仅在最外层批次结束的 assert 中执行。
  @visibleForTesting
  void debugCheckInvariants() {
    final locations = <_Entry, List<String>>{};

    /// 记录容器成员并核对当前身份和阶段。
    void check(_Entry e, String container, bool pending) {
      locations.putIfAbsent(e, () => []).add(container);
      if (!_isCurrent(e)) {
        throw StateError('不变量 b：$container 中 ${e.id} 不是当前条目');
      }
      if (pending ? e.phase != OverlayPhase.pending : !e.isActive) {
        throw StateError('不变量 c：$container 中 ${e.id} 阶段 ${e.phase} 不一致');
      }
    }

    for (final item in _slots.entries) {
      final s = item.value;
      final name = item.key;
      if (s.delayTimer != null &&
          (s.delayOwner == null || !s.queue.contains(s.delayOwner))) {
        throw StateError('不变量 l：slot[$name] delay 属主不在队列');
      }
      if (s.active != null) check(s.active!, 'slot[$name].active', false);
      for (final e in s.queue) {
        check(e, 'slot[$name].queue', true);
        if (_hydrationApplied &&
            e.cooldown != null &&
            _cooldowns.permanentlyBlocked(e.id, e.cooldown!)) {
          throw StateError('不变量 i：${e.id} 永久受阻仍在串行队列');
        }
      }
      if (s.waitingUnblock &&
          !_slotBlocked(name) &&
          !_paused &&
          !_inBuildPhase &&
          !_releasePending &&
          !_deferredSlots.contains(name)) {
        throw StateError('不变量 j：slot[$name] 解除阻塞后漏调度');
      }
      for (var i = 1; i < s.queue.length; i++) {
        if (_cmp(s.queue[i - 1], s.queue[i]) > 0) {
          throw StateError(
              '不变量 d：slot[$name] 队列无序 ${s.queue[i - 1].id}, ${s.queue[i].id}');
        }
      }
      if (s.active == null &&
          s.queue.isEmpty &&
          !s.gapPending &&
          s.gapTimer == null &&
          s.delayTimer == null &&
          s.cooldownTimer == null) {
        throw StateError('不变量 f：slot[$name] 空闲但未回收');
      }
    }
    for (final e in _overlaps) {
      check(e, 'overlaps', false);
    }
    for (final e in _pendingOverlaps) {
      check(e, 'pendingOverlaps', true);
      if (!_paused &&
          !_inBuildPhase &&
          !_releasePending &&
          !_slotBlocked(e.slot) &&
          (_hydrationApplied || e.cooldown == null)) {
        throw StateError('不变量 k：${e.id} 持有的 overlap 漏释放');
      }
    }
    for (final e in _delayedOverlaps) {
      check(e, 'delayedOverlaps', true);
    }
    for (final e in _byId.values) {
      final containers = locations[e] ?? [];
      if (containers.length != 1) {
        throw StateError('不变量 a：${e.id} 必须恰在一个容器，实际 $containers');
      }
      if ((e.resolveTimer != null && e.phase != OverlayPhase.resolving) ||
          (e.dismissTimer != null && e.phase != OverlayPhase.closing) ||
          (e.removeTimer != null && e.phase != OverlayPhase.closing) ||
          (e.durationTimer != null && e.phase != OverlayPhase.open) ||
          (e.queueTimer != null &&
              !(_slots[e.slot]?.queue.contains(e) ?? false)) ||
          (e.overlapDelayTimer != null && !_delayedOverlaps.contains(e))) {
        throw StateError('不变量 e：${e.id} 的计时器与阶段 ${e.phase} 或容器不一致');
      }
    }
    if (_holds.any((hold) => hold.isReleased)) {
      throw StateError('不变量 g：holds 含已释放对象，条目 ${_byId.keys.toList()}');
    }
    if (_disposed &&
        (_byId.isNotEmpty ||
            locations.isNotEmpty ||
            _slots.isNotEmpty ||
            _holds.isNotEmpty)) {
      throw StateError('不变量 h：销毁后容器非空 ${_byId.keys.toList()}');
    }
  }

  /// 查询 [id] 在 [cooldown] 下的资格；持久化读取未完成时 wait 为 null。
  OverlayCooldownStatus cooldownStatus(String id, OverlayCooldown cooldown) {
    final now = clock.now();
    final wait = _cooldowns.timeUntilEligible(id, cooldown, now);
    return OverlayCooldownStatus(
        canShow: wait == Duration.zero,
        permanentlyBlocked: _cooldowns.permanentlyBlocked(id, cooldown),
        suppressed: _cooldowns.suppressed(id, now),
        wait: wait);
  }

  /// 抑制 [id] 之后带 cooldown 的提交；已激活条目和不带 cooldown 的提交不受影响。
  /// [duration] 为 null 时永久抑制，否则必须大于零，从 clock.now() 起计时。
  /// 重复调用只延长抑制；resetCooldown / clearCooldowns 同时清除抑制。
  /// 销毁后无操作；存储读取前调用同样有效。
  ///
  /// ```dart
  /// final r = await manager.open<String>(
  ///     id: 'promo', cooldown: const OverlayCooldown(day: 1), present: present);
  /// if (r == 'never') manager.suppress('promo');
  /// if (r == 'later') manager.suppress('promo', duration: const Duration(days: 3));
  /// ```
  void suppress(String id, {Duration? duration}) => _batch(() {
        if (isDisposed) return;
        assert(duration == null || duration > Duration.zero);
        _cooldowns.suppress(id, duration, clock.now());
        _discardPermanentlyBlockedQueues();
        final e = _byId[id];
        if (e != null &&
            !e.isActive &&
            (_slots[e.slot]?.queue.contains(e) ?? false)) {
          _schedule(e.slot);
        }
        _notify();
      });

  /// 清除 [id] 的 session、持久化计数及抑制并重调度；销毁后无操作。
  void resetCooldown(String id) => _resetCooldowns(id);

  /// 清除所有冷却计数及抑制并重调度；销毁后无操作。
  void clearCooldowns() => _resetCooldowns();

  /// 复用串行持久化写入，并给排队条目重新判定资格。
  void _resetCooldowns([String? id]) => _batch(() {
        if (isDisposed) return;
        _cooldowns.reset(id);
        if (!_paused) _applyRelease();
        _notify();
      });

  /// 移除包含 [tag] 的所有条目，绕过守卫，结束原因为 removed。
  void clearTag(String tag) =>
      clearWhere((record) => record.tags.contains(tag));

  /// 同槽前一弹层关闭后，到下一弹层调度前的间隔。
  final Duration gap;

  /// 各槽位的间隔与排队上限；未配置时使用全局默认值。
  final Map<String, OverlaySlotOptions> slots;

  /// 异步广播生命周期事件，没有监听者时不创建事件。
  final _events = StreamController<OverlayEvent>.broadcast();

  /// 入队、展示和首次结束事件；同次提交依 queued、shown、ended 顺序，展示失败无 shown。
  /// dispose 后关闭；ended 不代表退场动画结束。
  Stream<OverlayEvent> get events => _events.stream;

  /// 正在执行展示回调的条目，支持嵌套展示。
  final _presenting = <_Entry>{};

  /// present 同步结束的首次原因，在 shown 或失败之后发布。
  final _pendingEnds = <_Entry, OverlayEndReason?>{};

  /// 发布事件；展示回调中的结束事件延至展示成功或失败确定之后。
  void _emit(_Entry e, OverlayEventType type, [OverlayEndReason? reason]) {
    if (type == OverlayEventType.ended && _presenting.contains(e)) {
      _pendingEnds[e] = reason;
      return;
    }
    if (!_disposed && _events.hasListener) {
      _events.add(
          OverlayEvent(type: type, id: e.id, slot: e.slot, reason: reason));
    }
  }

  /// 尚未释放的独立暂停来源。
  final _holds = <OverlayHold>{};

  /// 当前独立暂停来源数量，不包含手动暂停和路由暂停。
  int get holdCount => _holds.length;

  /// 建立独立暂停来源；所有来源释放后才恢复，销毁后返回已释放对象。
  OverlayHold hold([Object? reason]) {
    return _batch(() {
      if (isDisposed) return OverlayHold._(reason, null, _checkMutation);
      final before = _paused;
      late final OverlayHold token;
      token = OverlayHold._(
          reason,
          () => _batch(() {
                if (isDisposed) return;
                final before = _paused;
                _holds.remove(token);
                _applyPauseTransition(before);
                _notify();
              }),
          _checkMutation);
      _holds.add(token);
      _applyPauseTransition(before);
      _notify();
      return token;
    });
  }

  /// 请求后端关闭后等待 dismissed 的时限；null 表示不限时，默认 10 秒。
  final Duration? dismissTimeout;

  /// resolve 默认等待时限；null 表示不限时，默认 30 秒。
  final Duration? resolveTimeout;

  /// 引擎时间与计时器的统一来源。
  final OverlayClock clock;

  /// 管理器使用的冷却存储。
  late final _CooldownStore _cooldowns;

  /// 持久化读取并应用调度的完成信号。
  late final Future<void> _ready;

  /// 按名称索引的运行时串行槽位。
  final Map<String, _Slot> _slots = <String, _Slot>{};

  /// 已激活的并发条目。
  final List<_Entry> _overlaps = <_Entry>[];

  /// 等待暂停解除、持久化读取或跨槽阻塞解除的并发条目。
  final List<_Entry> _pendingOverlaps = <_Entry>[];

  /// 等待出场延迟到期的 overlap 条目。
  final List<_Entry> _delayedOverlaps = <_Entry>[];

  /// 当前受管条目的唯一身份索引。
  final Map<String, _Entry> _byId = <String, _Entry>{};

  /// 合并后的条件上下文。
  final Map<String, Object?> _context = <String, Object?>{};

  /// 生成默认标识和稳定排序序号的递增计数。
  int _seqCounter = 0;

  /// 使管理器暂停新激活的路由规则。
  final List<RouteMatcher> _pauseOnRoutes;

  /// 独立的手动暂停状态，与路由和 hold 按 OR 组合，互不覆盖。
  bool _manualPaused = false;

  /// 当前路由是否匹配免打扰区，每次 setContext 时更新。
  bool _routeZonePaused = false;

  /// 手动、路由和独立暂停来源按 OR 组合的有效状态。
  bool get _paused => _manualPaused || _routeZonePaused || _holds.isNotEmpty;

  /// 持久化冷却读取并应用调度后完成；带任何 cooldown 的条目自动等待，
  /// 所以 open 前无需显式等待。
  Future<void> ready() => _ready;

  /// 最近经 [setContext] 写入的 route 值，未设置时为 null。
  /// 可通过 LayermanNavigatorObserver 自动同步，宿主无需另存镜像。
  Object? get currentRoute => _context['route'];

  /// 是否因手动暂停、路由免打扰或未释放的 hold 而冻结；各来源按 OR 组合。
  bool get isPaused => _paused;

  /// 等待中的 id；各 slot 内按 replace、优先级、FIFO 的真实出场顺序返回。
  List<String> get queuedIds => <String>[
        for (final slot in _slots.values)
          for (final e in slot.queue) e.id,
        for (final e in _pendingOverlaps) e.id,
        for (final e in _delayedOverlaps) e.id,
      ];

  /// 已展示的 id（仅 open/closing，不含 resolving），含串行与 overlap。
  List<String> get activeIds => <String>[
        for (final slot in _slots.values)
          if (slot.active != null && slot.active!.isShown) slot.active!.id,
        for (final e in _overlaps)
          if (e.isShown) e.id,
      ];

  /// 正在解析且占据槽位的 id，包含 overlap 中正在解析的条目。
  List<String> get resolvingIds => [
        for (final e in _byId.values)
          if (e.phase == OverlayPhase.resolving) e.id,
      ];

  /// 所有受管条目的快照；各 slot 内先当前条目，再按出场顺序列出队列。
  List<OverlayRecord> get records => [
        for (final s in _slots.values) ...[
          if (s.active != null) _record(s.active!),
          for (final e in s.queue) _record(e),
        ],
        for (final e in _overlaps) _record(e),
        for (final e in _pendingOverlaps) _record(e),
        for (final e in _delayedOverlaps) _record(e),
      ];

  /// 返回指定 id 的当前快照；未受管时返回 null。
  OverlayRecord? recordOf(String id) {
    final e = _byId[id];
    return e == null ? null : _record(e);
  }

  /// 将内部条目转换为只读状态快照。
  OverlayRecord _record(_Entry e) =>
      OverlayRecord._(e.id, e.slot, e.data, e.isActive, e.phase, e.tags);

  /// id 是否已展示（仅 open/closing，不含 resolving）。
  bool isShowing(String id) {
    final e = _byId[id];
    return e != null && e.isShown;
  }

  /// 从活跃和挂起容器中分离 [e]，返回它是否占据串行 active。
  bool _detachFromActive(_Entry e) {
    final s = _slots[e.slot];
    final wasActive = s != null && s.active == e;
    if (wasActive) s.active = null;
    final wasOverlap = _overlaps.remove(e);
    if ((wasActive || wasOverlap) && _blockerSlots.contains(e.slot)) {
      _unblockPending = true;
    }
    _pendingOverlaps.remove(e);
    _delayedOverlaps.remove(e);
    return wasActive;
  }

  /// 将 [partial] 合并到条件上下文并重判。
  /// 已展示条目若条件失效且 dismissWhenUnmet 为 true 则移除；
  /// 排队条目重新获得调度机会。仅 route 是保留键，auth 和 when 可读任意业务键。
  /// 例如 `manager.setContext({'user': user, 'route': '/home'});`。
  void setContext(Map<String, Object?> partial) {
    return _batch(() {
      if (isDisposed) return;
      _context.addAll(partial);
      _contextView = null;
      _updateRouteZone();
      final shown = <_Entry>[
        for (final s in _slots.values)
          if (s.active != null) s.active!,
        ..._overlaps,
      ];
      for (final e in shown) {
        if (e.isActive && e.dismissWhenUnmet && !_conditionsPass(e)) {
          _remove(e, reason: OverlayEndReason.unmet);
        }
      }
      for (final slot in _slots.keys.toList()) {
        _schedule(slot);
      }
      _notify();
    });
  }

  /// 重判路由免打扰区，仅有效暂停状态切换时冻结或恢复，保留独立的手动暂停。
  void _updateRouteZone() {
    if (_pauseOnRoutes.isEmpty) return;
    final current = _context['route'];
    final matches = _pauseOnRoutes.any((p) => _routeMatches(p, current));
    if (matches == _routeZonePaused) return;
    final before = _paused;
    _routeZonePaused = matches;
    _applyPauseTransition(before);
  }

  /// 暂停全部新激活及 duration 倒计时，close、remove、clear 仍有效。
  /// 调用 [resumeAll] 解除手动暂停，其他暂停来源仍有效。
  void pauseAll() {
    return _batch(() {
      if (isDisposed) return;
      if (_manualPaused) return;
      final before = _paused;
      _manualPaused = true;
      _applyPauseTransition(before);
    });
  }

  /// 解除手动暂停；其他暂停来源均解除后恢复剩余时长并重判等待条目。
  void resumeAll() {
    return _batch(() {
      if (isDisposed) return;
      if (!_manualPaused) return;
      final before = _paused;
      _manualPaused = false;
      _applyPauseTransition(before);
    });
  }

  /// 手动、路由和 hold 共享的边沿触发器；仅有效暂停状态变化时冻结或恢复。
  void _applyPauseTransition(bool before) {
    final after = _paused;
    if (after == before) return;
    if (after) {
      _applyFreeze();
    } else {
      _applyRelease();
    }
  }

  /// 冻结全部活跃条目的时长并取消冷却唤醒。
  void _applyFreeze() {
    for (final s in _slots.values) {
      _cancelCooldownTimer(s);
    }
    for (final e in _byId.values) {
      _freezeDuration(e);
    }
    _notify();
  }

  /// 恢复时长，释放挂起条目并重新调度串行槽位。
  void _applyRelease() {
    if (_paused || isDisposed) return;
    if (_inBuildPhase) {
      _deferRelease();
      return;
    }
    final held = List<_Entry>.of(_pendingOverlaps);
    _pendingOverlaps.clear();
    for (final e in held) {
      if (!_isCurrent(e)) continue;
      _releaseOverlap(e);
    }
    for (final e in _byId.values.toList()) {
      if (!_paused && e.phase == OverlayPhase.resolving && e.hasHeldData) {
        e.hasHeldData = false;
        _open(e);
      }
    }
    for (final e in _byId.values) {
      _thawDuration(e);
    }
    for (final slot in _slots.keys.toList()) {
      _schedule(slot);
    }
    _notify();
  }

  /// 重新判定持有的 overlap；仍暂停、等待读取或被阻塞时继续持有。
  void _releaseOverlap(_Entry e) {
    if (!_isCurrent(e)) return;
    if (_paused || _waitingForHydrate(e) || _slotBlocked(e.slot)) {
      _pendingOverlaps.add(e);
    } else {
      _admitOverlap(e);
    }
  }

  /// 暂停 [id] 的 duration 倒计时，弹层仍保持展示。
  void pause(String id) {
    return _batch(() {
      if (isDisposed) return;
      final e = _byId[id];
      if (e == null || e.paused) return;
      e.paused = true;
      _freezeDuration(e);
      _notify();
    });
  }

  /// 恢复 [id] 剩余的 duration 倒计时，全局暂停时继续等待。
  void resume(String id) {
    return _batch(() {
      if (isDisposed) return;
      final e = _byId[id];
      if (e == null || !e.paused) return;
      e.paused = false;
      _thawDuration(e);
      _notify();
    });
  }

  /// 更新 [id] 的数据并通知监听者，不改变队列。
  /// Map 与 Map 浅合并，其他组合直接替换；两者均为字符串键 Map 时保留该类型。
  /// 后端可监听 PresentContext.dataListenable；PresentContext.data 保持展示时快照。
  void update(String id, Object? patch) {
    return _batch(() {
      if (isDisposed) return;
      final e = _byId[id];
      if (e == null) return;
      final current = e.data;
      if (current is Map<String, Object?> && patch is Map<String, Object?>) {
        e.data = <String, Object?>{...current, ...patch};
      } else if (current is Map && patch is Map) {
        e.data = <Object?, Object?>{...current, ...patch};
      } else {
        e.data = patch;
      }
      _notify();
    });
  }

  /// 提交由 [present] 渲染的弹层，返回首次结束时完成的可空结果 Future。
  /// 结果来自 close 或后端 dismissed，未出场或无结果时为 null。
  ///
  /// * [present] 为唯一展示入口，获准出场后至多调用一次。
  /// * [id] 默认自动生成；复用活跃 id 为接管，复用排队 id 为覆盖。
  /// * [data] 为数据；[tags] 默认空，提交时复制为只读标签。
  /// * [slot] 默认空字符串，为独立串行槽；[priority] 越高越先，同级先进先出。
  /// * [delay] 为出场延迟：串行条目在 gap 之后再等；replace 和同 id 活跃接管跳过；
  ///   overlap 先等待再按现在或永不判定资格。
  /// * [duration] 为出场后的自动关闭时长；[expireAfter] 只限制串行激活前等待。
  /// * [mode] 默认 queue；replace 自身合格且当前条目无 affix 保护时抢占，旧项以 null 结束；
  ///   overlap 延迟后绕过队列叠加，资格不满足则丢弃。
  /// * [affix] 防止被 replace 抢占，不阻止 close、remove、clear 或同 id 接管。
  /// * [when]、[route]、[auth] 按 AND 组合；[dismissWhenUnmet] 默认 true，条件失效时移除。
  ///   判断函数内修改管理器抛 StateError，按条件不满足处理且每条目仅上报一次。
  /// * [cooldown] 限制展示频次并接受抑制，必须提供显式 id；成功展示才计数。
  /// * [resolve] 获得槽位时解析数据，null 跳过展示，非 null 成为数据。
  /// * [resolveTimeout] 为 null 时继承构造默认值，零时禁用；超时跳过且不计数。
  /// * [beforeClose] 返回 false 可否决显式 close。
  /// * [exitDuration] 为后端 dismissed 后的额外退场宽限，null 时直接推进。
  ///
  /// 例如 `final result = await manager.open<bool>(id: 'confirm', present: present);`。
  Future<T?> open<T>({
    required Present<T> present,
    String? id,
    Object? data,
    Set<String>? tags,
    String slot = '',
    int priority = 0,
    Duration? delay,
    Duration? duration,
    Duration? expireAfter,
    OverlayMode mode = OverlayMode.queue,
    bool affix = false,
    OverlayPredicate? when,
    RouteMatcher? route,
    OverlayPredicate? auth,
    bool dismissWhenUnmet = true,
    OverlayCooldown? cooldown,
    Future<T?> Function()? resolve,
    Duration? resolveTimeout,
    FutureOr<bool> Function()? beforeClose,
    Duration? exitDuration,
  }) =>
      submit<T>(
        present: present,
        id: id,
        data: data,
        tags: tags,
        slot: slot,
        priority: priority,
        delay: delay,
        duration: duration,
        expireAfter: expireAfter,
        mode: mode,
        affix: affix,
        when: when,
        route: route,
        auth: auth,
        dismissWhenUnmet: dismissWhenUnmet,
        cooldown: cooldown,
        resolve: resolve,
        resolveTimeout: resolveTimeout,
        beforeClose: beforeClose,
        exitDuration: exitDuration,
      ).result;

  /// 提交条目并返回类型化票据；参数与 open 相同。
  /// [mode] 默认串行排队；replace 抢占当前条目，overlap 在 delay 到期时判定资格。
  /// [auth] 为登录或权限判断函数；null 表示不限，例如 `(ctx) => ctx['user'] != null`。
  /// [route] 匹配字符串路由，与 [auth]、[when] 按 AND 组合；null 表示不限制。
  /// expireAfter 仅计算激活前的串行排队时间，overlap 不适用。
  /// tags 默认空集合，提交时复制，之后通过 recordOf 或 records 只读查询。
  /// 例如 `final ticket = manager.submit<bool>(id: 'confirm', present: present);`。
  OverlayTicket<T> submit<T>({
    required Present<T> present,
    String? id,
    Object? data,
    Set<String>? tags,
    String slot = '',
    int priority = 0,
    Duration? delay,
    Duration? duration,
    Duration? expireAfter,
    OverlayMode mode = OverlayMode.queue,
    bool affix = false,
    OverlayPredicate? when,
    RouteMatcher? route,
    OverlayPredicate? auth,
    bool dismissWhenUnmet = true,
    OverlayCooldown? cooldown,
    Future<T?> Function()? resolve,
    Duration? resolveTimeout,
    FutureOr<bool> Function()? beforeClose,
    Duration? exitDuration,
  }) {
    return _batch(() {
      assert(!_disposed, 'Cannot open an overlay after Layerman.dispose().');
      assert(
        cooldown == null || id != null,
        'cooldown is keyed by id: pass an explicit id. An auto-generated id '
        'changes on every open, so the cap would never apply.',
      );
      final replace = mode == OverlayMode.replace;
      final overlap = mode == OverlayMode.overlap;
      final resolvedId = id ?? 'overlay:${++_seqCounter}';
      final completer = Completer<T?>();
      final outcome = Completer<OverlayOutcome<T>>();
      late final _Entry entry;
      entry = _Entry(
        id: resolvedId,
        tags: Set<String>.unmodifiable(tags ?? const <String>{}),
        slot: slot,
        priority: priority,
        seq: ++_seqCounter,
        replace: replace,
        affix: affix,
        delay: delay,
        duration: duration,
        exitDuration: exitDuration,
        when: when,
        route: route,
        auth: auth,
        dismissWhenUnmet: dismissWhenUnmet,
        cooldown: cooldown,
        beforeClose: beforeClose,
        resolveData: resolve == null ? null : () async => await resolve(),
        resolveTimeout: resolveTimeout == Duration.zero
            ? null
            : (resolveTimeout ?? this.resolveTimeout),
        acceptsResult: (Object? r) => r is T?,
        settle: (Object? r) {
          if (!completer.isCompleted) completer.complete(r as T?);
        },
        settleOutcome: (r, reason) {
          outcome.complete(OverlayOutcome<T>(r as T?, reason));
        },
        data: data,
        presentBackend: () {
          final presented = present(
            PresentContext<T>._(
                resolvedId, slot, entry.data, entry.dataNotifier, (result) {
              _checkMutation();
              if (!isDisposed && _isCurrent(entry)) {
                _batch(() => _close(entry, result));
              }
            }),
          );
          final dismiss = presented.dismiss;
          entry.externalDismiss =
              dismiss == null ? null : (Object? r) => dismiss(r as T?);
          // present 内可能同步关闭或移除自己，句柄返回后仍须清理后端。
          if (!_isCurrent(entry) && dismiss != null) _callDismiss(entry, null);
          presented.dismissed.then(
            (T? r) => _onExternalDismissed(entry, r),
            onError: (Object _) => _onExternalDismissed(entry, null),
          );
        },
      );

      final ticket =
          OverlayTicket<T>._(this, entry, completer.future, outcome.future);
      if (isDisposed) {
        _settle(entry, null, OverlayEndReason.disposed);
        return ticket;
      }

      // 处理同 id 覆盖。
      final existing = _byId[resolvedId];
      String? freedSlot; // 被替换条目释放的串行槽位
      if (existing != null) {
        if (existing.isActive) {
          // 原地替换，旧结果为 null。
          if (_discardActive(existing, OverlayEndReason.superseded)) {
            freedSlot = existing.slot;
          }
          entry.skipGap = true;
        } else {
          _removeFromQueue(existing);
          _detachFromActive(existing);
          _byId.remove(existing.id);
          _settle(existing, null, OverlayEndReason.superseded);
        }
      }
      _byId[resolvedId] = entry;
      _emit(entry, OverlayEventType.queued);

      // 新条目转到其他槽位时，旧槽位仍需重调度。
      /// 转槽或转并发后恢复旧串行槽位。
      void rescheduleFreed() {
        if (freedSlot != null && (overlap || freedSlot != slot)) {
          _schedule(freedSlot);
        }
      }

      if (overlap) {
        if (delay != null && delay > Duration.zero) {
          _delayedOverlaps.add(entry);
          entry.overlapDelayTimer = clock.createTimer(
              delay,
              () => _batch(() {
                    entry.overlapDelayTimer = null;
                    if (!_isCurrent(entry)) return;
                    _delayedOverlaps.remove(entry);
                    _admitOverlap(entry);
                    _notify();
                  }));
        } else {
          _admitOverlap(entry);
        }
        rescheduleFreed();
        _notify();
        return ticket;
      }

      // 永久上限与槽位占用、暂停及构建阶段无关，提交时即可结束。
      if (cooldown != null &&
          _cooldowns.permanentlyBlocked(resolvedId, cooldown)) {
        _byId.remove(resolvedId);
        _settle(entry, null, _dropReason(entry));
        if (freedSlot != null) _schedule(freedSlot);
        _notify();
        return ticket;
      }

      final s = _slotFor(slot);
      // 抢占者必须自身合格、未暂停且不受跨槽阻塞。
      // affix 阻止抢占，但抢占者保留前排顺序，等待当前条目退出。
      if (replace && !_paused && !_slotBlocked(slot) && _eligible(entry)) {
        entry.skipGap = true;
        final cur = s.active;
        if (cur != null && cur.isActive && !cur.affix) {
          // 已关闭的后端不能可靠地再次展示，否则会重复副作用；
          // 因此被抢占条目以 null 结束，不重新排队。
          _discardActive(cur, OverlayEndReason.replaced);
        }
        // 抢占跳过正在等待的间隔与出场延迟，立即参与调度。
        if (s.gapPending) {
          s.gapTimer?.cancel();
          s.gapTimer = null;
          s.gapPending = false;
        }
        if (s.delayTimer != null) {
          _cancelDelayTimer(s);
        }
      }
      _enqueue(s, entry);
      if (expireAfter != null) {
        entry.queueTimer = clock.createTimer(
            expireAfter,
            () => _batch(() {
                  if (!_isCurrent(entry) ||
                      entry.phase != OverlayPhase.pending) {
                    return;
                  }
                  _remove(entry, reason: OverlayEndReason.queueExpired);
                  _schedule(slot);
                }));
      }
      if ((_inBuildPhase || _slotBlocked(slot)) &&
          _isCurrent(entry) &&
          freedSlot == slot &&
          !_paused &&
          _eligible(entry)) {
        s.takeover = entry;
      }
      if (_isCurrent(entry) &&
          !_inBuildPhase &&
          !_slotBlocked(slot) &&
          freedSlot == slot &&
          !_paused &&
          _eligible(entry)) {
        _activate(entry);
      } else {
        _schedule(slot);
      }
      rescheduleFreed();
      _notify();
      return ticket;
    });
  }

  /// 请求两阶段关闭已展示（open）的 [id]，可携带 [result]。
  /// 排队中和解析中的条目不受影响，取消它们请用 [remove]。
  /// beforeClose 返回 false 或抛错会取消；异步守卫未决时重复 close、dismiss 无操作。
  /// 结果类型不是对应 open 的 T? 时抛 [ArgumentError]，条目保持不变。
  /// 例如 `manager.close('confirm', true);`。
  void close(String id, [Object? result]) {
    return _batch(() {
      if (isDisposed) return;
      final e = _byId[id];
      if (e == null || !_closable(e)) return;
      if (e.closeGuardPending) return;
      if (!e.acceptsResult(result)) {
        throw ArgumentError.value(
            result, 'result', 'Invalid result type for overlay "$id"');
      }
      _close(e, result);
    });
  }

  /// 以 null 结果关闭已展示（open）的 [id]，等同于 close(id)。
  /// 排队及解析中的条目不受影响，取消请用 [remove]。
  void dismiss(String id) => close(id);

  /// 立即移除 [id]，不等待退场且绕过 beforeClose；未结束的结果以 null 完成。
  void remove(String id) {
    return _batch(() {
      if (isDisposed) return;
      final e = _byId[id];
      if (e == null) return;
      _remove(e);
    });
  }

  /// 清空全部槽位和叠加中的排队及活跃条目，绕过 beforeClose，未结束结果为 null。
  void clear() => _clear(OverlayEndReason.removed);

  /// 按指定原因清空所有条目，同时取消槽位和条目计时器。
  void _clear(OverlayEndReason reason) {
    return _batch(() {
      if (isDisposed && reason != OverlayEndReason.disposed) return;
      for (final s in _slots.values) {
        _cancelCooldownTimer(s);
        s.gapTimer?.cancel();
        s.gapTimer = null;
        s.gapPending = false;
        _cancelDelayTimer(s);
      }
      final all = _byId.values.toList();
      for (final e in all) {
        _remove(e, advance: false, reason: reason);
      }
      _notify();
    });
  }

  /// 移除 [test] 匹配的全部条目，绕过 beforeClose。
  /// 判断函数只能读取状态，修改管理器会抛 StateError；判断异常向调用方传播。
  /// 例如 `manager.clearWhere((r) => r.tags.contains('promo'));`。
  void clearWhere(bool Function(OverlayRecord record) test) {
    return _batch(() {
      if (isDisposed) return;
      final selected = <_Entry>[
        for (final e in _byId.values.toList())
          if (_judge(() => test(_record(e)))) e,
      ];
      // 先移除全部匹配项再推进，避免先展示匹配的排队项又立即移除。
      final freed = <String>{};
      for (final e in selected) {
        if (_remove(e, advance: false)) freed.add(e.slot);
      }
      freed.forEach(_advanceSlot);
    });
  }

  // 内部调度与生命周期实现。

  /// 获取或创建指定名称的运行时槽位。
  _Slot _slotFor(String slot) => _slots.putIfAbsent(slot, () => _Slot());

  /// 移出队列，取消属于此条目的延迟并登记批次内重调度。
  void _removeFromQueue(_Entry e) {
    final s = _slots[e.slot];
    s?.queue.remove(e);
    if (s != null && s.delayOwner == e) {
      _cancelDelayTimer(s);
      _rescheduleSlots.add(e.slot);
    }
    if (s?.takeover == e) s?.takeover = null;
  }

  /// 按固定排序键二分插入，维持真实出场顺序。
  void _enqueue(_Slot s, _Entry e) {
    var low = 0;
    var high = s.queue.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_cmp(s.queue[mid], e) <= 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    s.queue.insert(low, e);
  }

  /// 按抢占前排带、优先级降序和提交序号排序。
  int _cmp(_Entry a, _Entry b) {
    // 抢占条目形成前排带，即使被 affix 挡住而排队，
    // 也必须先于此前等待的普通条目出场。
    if (a.replace != b.replace) return a.replace ? -1 : 1;
    if (a.priority != b.priority) return b.priority - a.priority;
    return a.seq - b.seq;
  }

  /// 缓存本次上下文的不可修改快照，供所有 when 共用。
  Map<String, Object?>? _contextView;

  /// 返回条件和冷却是否同时通过。
  bool _eligible(_Entry e) => _conditionsPass(e) && _cooldownPass(e);

  /// 只读求值路由、认证与业务条件，异常每条目上报一次并视为不通过。
  bool _conditionsPass(_Entry e) {
    if (e.route != null && !_routeMatches(e.route!, _context['route'])) {
      return false;
    }
    try {
      final context =
          _contextView ??= Map<String, Object?>.unmodifiable(_context);
      return _judge(() =>
          (e.auth?.call(context) ?? true) && (e.when?.call(context) ?? true));
    } catch (error, stack) {
      if (!e.conditionErrorReported) {
        e.conditionErrorReported = true;
        _reportError(
            error, stack, 'while evaluating conditions for overlay "${e.id}"');
      }
      return false;
    }
  }

  /// 使用类型化匹配器判断当前路由，非字符串路由不匹配。
  static bool _routeMatches(RouteMatcher pattern, Object? current) =>
      pattern.matches(current);

  /// 所有带 cooldown 的条目都等待读取抑制状态。
  bool _waitingForHydrate(_Entry e) =>
      !_cooldowns._hydrated && e.cooldown != null;

  /// 抑制优先于永久上限；调用方单独保留条件不通过时的 dropped。
  OverlayEndReason _dropReason(_Entry e) {
    final cd = e.cooldown;
    if (cd == null) return OverlayEndReason.dropped;
    if (_cooldowns.suppressed(e.id, clock.now())) {
      return OverlayEndReason.suppressed;
    }
    return _cooldowns.permanentlyBlocked(e.id, cd)
        ? OverlayEndReason.capped
        : OverlayEndReason.dropped;
  }

  /// 返回条目是否通过频次限制及抑制。
  bool _cooldownPass(_Entry e) {
    final cd = e.cooldown;
    if (cd == null) return true;
    return _cooldowns.canShow(e.id, cd, clock.now());
  }

  /// 取消并清空指定槽位的冷却唤醒计时器。
  void _cancelCooldownTimer(_Slot s) {
    s.cooldownTimer?.cancel();
    s.cooldownTimer = null;
  }

  /// 取消串行出场延迟，同时清空计时器与属主。
  void _cancelDelayTimer(_Slot s) {
    s.delayTimer?.cancel();
    s.delayTimer = null;
    s.delayOwner = null;
  }

  /// hydrate 后清理所有串行队列的永久受阻项，暂停或槽位占用也不延后结算。
  void _discardPermanentlyBlockedQueues() {
    for (final s in _slots.values.toList()) {
      for (final e in s.queue.toList()) {
        final cd = e.cooldown;
        if (cd == null || !_cooldowns.permanentlyBlocked(e.id, cd)) continue;
        _removeFromQueue(e);
        if (_isCurrent(e)) _byId.remove(e.id);
        _settle(e, null, _dropReason(e));
        _notify();
      }
    }
  }

  /// 按暂停、槽位占用、跨槽阻塞、资格和延迟调度下一条目。
  void _schedule(String slot) {
    if (isDisposed) return;
    if (_inBuildPhase) {
      if (_deferredSlots.add(slot)) {
        SchedulerBinding.instance.addPostFrameCallback((_) => _batch(() {
              _deferredSlots.remove(slot);
              if (!isDisposed) _schedule(slot);
            }));
      }
      return;
    }
    if (_paused) return;
    final s = _slotFor(slot);
    s.waitingUnblock = false;
    _cancelCooldownTimer(s);
    if (s.active != null) return; // 槽位已占用
    if (s.gapPending) return; // 等待关闭后的间隔
    if (s.delayTimer != null) {
      return; // 等待本条目的出场延迟
    }
    if (s.queue.isEmpty) return;
    if (_slotBlocked(slot)) {
      s.waitingUnblock = true;
      return;
    }

    final takeover = s.takeover;
    s.takeover = null;
    _Entry? front = takeover != null &&
            _isCurrent(takeover) &&
            s.queue.contains(takeover) &&
            _eligible(takeover)
        ? takeover
        : null;
    for (var i = 0; i < s.queue.length;) {
      if (front != null) break;
      final e = s.queue[i];
      final cd = e.cooldown;
      if (cd != null && _cooldowns.permanentlyBlocked(e.id, cd)) {
        s.queue.removeAt(i);
        if (_isCurrent(e)) _byId.remove(e.id);
        _settle(e, null, _dropReason(e));
        _notify();
        if (_paused ||
            s.active != null ||
            s.gapPending ||
            s.delayTimer != null) {
          return;
        }
        continue;
      }
      i++;
      if (_eligible(e)) {
        front = e;
        break;
      }
    }
    if (front == null) {
      // 当前没有合格项。仅因时间冷却受阻的条目有确定到期时刻，
      // 设置唤醒，避免冷却结束后仍永久停在队列。
      _armCooldownWake(slot, s);
      return; // 不合格的串行条目继续等待
    }

    // 条目自己的出场延迟。
    if (!front.skipGap &&
        !front.delayConsumed &&
        front.delay != null &&
        front.delay! > Duration.zero) {
      front.delayConsumed = true;
      s.delayTimer?.cancel();
      s.delayOwner = front;
      s.delayTimer = clock.createTimer(
          front.delay!,
          () => _batch(() {
                s.delayTimer = null;
                s.delayOwner = null;
                _schedule(slot);
              }));
      return;
    }
    _activate(front);
  }

  /// 为仅受时间冷却阻挡的条目设置最近到期的单次调度唤醒。
  void _armCooldownWake(String slot, _Slot s) {
    Duration? soonest;
    for (final e in s.queue) {
      final cd = e.cooldown;
      if (cd == null) continue;
      if (!_conditionsPass(e)) {
        continue; // 条件依赖事件推动，不按时间唤醒
      }
      final w = _cooldowns.timeUntilEligible(e.id, cd, clock.now());
      if (w == null || w <= Duration.zero) continue;
      if (soonest == null || w < soonest) soonest = w;
    }
    if (soonest == null) return;
    // 稍留余量，确保唤醒时已越过冷却边界。
    s.cooldownTimer = clock.createTimer(
        soonest + const Duration(milliseconds: 16),
        () => _batch(() {
              s.cooldownTimer = null;
              _schedule(slot);
              _notify();
            }));
  }

  /// 停止排队期限并占据串行槽位，开始解析或展示。
  void _activate(_Entry e) {
    final s = _slotFor(e.slot);
    e.queueTimer?.cancel();
    e.queueTimer = null;
    _removeFromQueue(e);
    s.active = e;
    _begin(e);
  }

  /// 有解析函数时先解析，否则直接展示 [e]。
  void _begin(_Entry e) {
    final resolver = e.resolveData;
    if (resolver != null) {
      // 解析期间占据槽位，普通新提交不能打断；返回 null 则跳过展示。
      e.phase = OverlayPhase.resolving;
      final timeout = e.resolveTimeout;
      if (timeout != null) {
        e.resolveTimer = clock.createTimer(
            timeout,
            () => _batch(() {
                  if (!_isCurrent(e) || e.phase != OverlayPhase.resolving) {
                    return;
                  }
                  _reportError(
                      TimeoutException(
                          'resolve "${e.id}" 等待 $timeout', timeout),
                      StackTrace.current,
                      'while resolving overlay "${e.id}"');
                  _onResolved(e, null);
                }));
      }
      _notify();
      resolver().then(
        (data) => _onResolved(e, data),
        onError: (Object _) => _onResolved(e, null),
      );
      return;
    }
    _open(e);
  }

  /// 应用仍有效的解析结果，监听者重入后再次验证身份和阶段。
  void _onResolved(_Entry e, Object? data) {
    return _batch(() {
      if (!_isCurrent(e) || e.phase != OverlayPhase.resolving) return;
      e.resolveTimer?.cancel();
      e.resolveTimer = null;
      if (data == null) {
        // 后端要求跳过，不展示也不记冷却。
        final wasSerial = _detachFromActive(e);
        _byId.remove(e.id);
        _settle(e, null, OverlayEndReason.skipped);
        _notify();
        if (wasSerial) _schedule(e.slot);
        return;
      }
      e.data = data;
      if (isDisposed || !_isCurrent(e) || e.phase != OverlayPhase.resolving) {
        return;
      }
      if (_paused || _inBuildPhase) {
        if (_inBuildPhase) _deferRelease();
        // 冻结期间不新展示，暂存数据，恢复时复用而不重跑解析。
        e.hasHeldData = true;
        _notify();
        return;
      }
      _open(e);
    });
  }

  /// 调用后端展示，成功后发布 shown、计数并启动时长。
  void _open(_Entry e) {
    e.phase = OverlayPhase.open;
    _presenting.add(e);
    try {
      e.presentBackend();
    } catch (error, stack) {
      // 后端抛错时上报并移除条目，以 null 结束且不记冷却，继续推进队列。
      _reportError(error, stack, 'while presenting overlay "${e.id}"');
      _remove(e, reason: OverlayEndReason.failed);
      _finishPresent(e);
      return;
    }
    _emit(e, OverlayEventType.shown);
    _finishPresent(e);
    final cd = e.cooldown;
    if (cd != null) _cooldowns.record(e.id, cd, clock.now());
    if (_isCurrent(e) && _closable(e)) _startDuration(e);
    _notify();
  }

  /// 展示回调退出后交付暂存的结束事件，支持嵌套展示。
  void _finishPresent(_Entry e) {
    _presenting.remove(e);
    if (_pendingEnds.containsKey(e)) {
      final reason = _pendingEnds.remove(e);
      _emit(e, OverlayEventType.ended, reason);
    }
  }

  /// 延迟结束后复用 overlap 的一次性资格判定与挂起逻辑。
  void _admitOverlap(_Entry e) {
    final conditionsPass = _conditionsPass(e);
    final waitingForHydrate = conditionsPass && _waitingForHydrate(e);
    if (!conditionsPass || (!waitingForHydrate && !_cooldownPass(e))) {
      _byId.remove(e.id);
      _settle(
          e, null, conditionsPass ? _dropReason(e) : OverlayEndReason.dropped);
    } else if (_paused ||
        waitingForHydrate ||
        _inBuildPhase ||
        _slotBlocked(e.slot)) {
      _pendingOverlaps.add(e);
      if (_inBuildPhase) _deferRelease();
    } else {
      _openOverlap(e);
    }
  }

  /// 将并发条目加入活跃集合并开始解析或展示。
  void _openOverlap(_Entry e) {
    _overlaps.add(e);
    _begin(e);
  }

  /// 时长到期自动关闭，绕过仅约束显式 close 的 beforeClose。
  void _autoClose(_Entry e) {
    return _batch(() {
      if (_isCurrent(e) && _closable(e)) {
        _doClose(e, null, OverlayEndReason.expired);
      }
    });
  }

  /// 按剩余或完整时长启动自动关闭，全局或单项暂停时保留时长。
  void _startDuration(_Entry e) {
    // 暂停条目使用剩余时长，新展示条目使用完整 duration。
    final d = e.durationRemaining ?? e.duration;
    if (d == null) {
      e.durationRemaining = null;
      return;
    }
    if (_paused || e.paused) {
      e.durationRemaining = d; // 恢复时仍保留同一剩余时长
      return;
    }
    e.durationRemaining = null;
    e.durationDeadline = clock.now().add(d);
    e.durationTimer = clock.createTimer(d, () => _autoClose(e));
  }

  /// 取消自动关闭计时并保留非负剩余时长。
  void _freezeDuration(_Entry e) {
    final timer = e.durationTimer;
    if (timer == null) return;
    timer.cancel();
    e.durationTimer = null;
    final deadline = e.durationDeadline;
    var remaining =
        deadline == null ? Duration.zero : deadline.difference(clock.now());
    if (remaining < Duration.zero) remaining = Duration.zero;
    e.durationRemaining = remaining;
  }

  /// 仅在条目已展示且未暂停时，复用启动逻辑恢复剩余自动关闭时长。
  void _thawDuration(_Entry e) {
    if (_paused || e.paused) return;
    if (e.durationRemaining == null || e.phase != OverlayPhase.open) return;
    _startDuration(e);
  }

  /// 检查 [e] 是否仍是此 id 的当前受管对象，拒绝旧条目的异步续体。
  bool _isCurrent(_Entry e) => _byId[e.id] == e;

  /// 检查 [e] 是否已展示且仍可关闭。
  bool _closable(_Entry e) => e.phase == OverlayPhase.open;

  /// 运行关闭守卫，通过后按当前身份执行关闭。
  void _close(_Entry e, Object? result) {
    if (!_closable(e) || e.closeGuardPending) return;

    final guard = e.beforeClose;
    if (guard == null) {
      _doClose(e, result);
      return;
    }
    final FutureOr<bool> verdict;
    try {
      verdict = guard();
    } catch (_) {
      return; // 守卫抛错取消关闭
    }
    if (verdict is bool) {
      if (verdict) _doClose(e, result);
      return;
    }
    e.closeGuardPending = true;
    verdict.then(
      (ok) => _batch(() {
        e.closeGuardPending = false;
        // 守卫返回时重验当前身份及阶段，等待期间可能已被移除或替换。
        if (ok && _isCurrent(e) && _closable(e)) _doClose(e, result);
      }),
      onError: (Object _) => _batch(() {
        e.closeGuardPending = false;
        // 守卫失败取消本次关闭。
      }),
    );
  }

  /// 完成结果并请求后端关闭，必要时启动关闭超时。
  void _doClose(_Entry e, Object? result,
      [OverlayEndReason reason = OverlayEndReason.closed]) {
    e.durationTimer?.cancel();
    e.durationTimer = null;
    e.durationRemaining = null;
    _settle(e, result, reason);
    e.phase = OverlayPhase.closing;
    _notify();
    if (!_isCurrent(e)) return; // 监听者可能已移除或替换
    if (e.externalDismiss == null || e.externalDone) {
      // 后端已关闭或无法程序关闭，直接分离。
      _remove(e);
    } else if (!_callDismiss(e, result)) {
      // 后端 dismissed 信号及可选退场宽限负责移除；
      // 若关闭请求同步失败，不继续无限等待。
      _remove(e);
    } else if (_isCurrent(e) && !e.externalDone && dismissTimeout != null) {
      final timeout = dismissTimeout!;
      e.dismissTimer = clock.createTimer(
          timeout,
          () => _batch(() {
                if (!_isCurrent(e) || e.externalDone) return;
                _reportError(
                    TimeoutException('dismiss "${e.id}" 等待 $timeout', timeout),
                    StackTrace.current,
                    'while awaiting dismissed for overlay "${e.id}"');
                _remove(e);
              }));
    }
  }

  /// 后端已完全关闭，完成结果并按退场宽限推进队列。
  void _onExternalDismissed(_Entry e, Object? result) {
    return _batch(() {
      e.externalDone = true;
      e.dismissTimer?.cancel();
      e.dismissTimer = null;
      _settle(e, result, OverlayEndReason.dismissedByBackend);
      if (!_isCurrent(e)) return; // 已移除或被原地替换
      if (e.phase == OverlayPhase.open) {
        e.durationTimer?.cancel();
        e.durationTimer = null;
        e.durationRemaining = null;
        // 后端直接关闭，并非经由 close。
        e.phase = OverlayPhase.closing;
        _notify();
      }
      final grace = e.exitDuration;
      if (grace != null && grace > Duration.zero) {
        e.removeTimer?.cancel();
        e.removeTimer =
            clock.createTimer(grace, () => _batch(() => _remove(e)));
      } else {
        _remove(e);
      }
    });
  }

  /// 移除排队或活跃条目，返回其是否占据串行 active。
  /// [advance] 为 true 且释放串行占位时，按 gap 推进队列。
  bool _remove(_Entry e,
      {bool advance = true,
      OverlayEndReason reason = OverlayEndReason.removed}) {
    e.cancelTimeouts();
    e.durationTimer?.cancel();
    e.removeTimer?.cancel();
    e.durationTimer = null;
    e.removeTimer = null;

    // 只有当前 id 仍指向此对象才移除，监听者可能已重开同 id。
    if (_isCurrent(e)) _byId.remove(e.id);
    _dismissBackendBestEffort(e);

    final wasSerialActive = _detachFromActive(e);
    _removeFromQueue(e);

    _settle(e, null, reason);

    if (advance && wasSerialActive) _advanceSlot(e.slot);
    _notify();
    return wasSerialActive;
  }

  /// 串行槽位刚释放，等待 gap 后调度下一条目。
  void _advanceSlot(String slot) {
    final s = _slotFor(slot);
    final slotGap = slots[slot]?.gap ?? gap;
    if (slotGap > Duration.zero) {
      s.gapPending = true;
      s.gapTimer?.cancel();
      s.gapTimer = clock.createTimer(
          slotGap,
          () => _batch(() {
                s.gapPending = false;
                s.gapTimer = null;
                _schedule(slot);
                _notify();
              }));
    } else {
      _schedule(slot);
    }
  }

  /// 抢占时先分离旧条目，不推进槽位；由提交方完成入队并统一通知。
  /// 返回旧条目是否占据串行 active 位置。
  bool _discardActive(_Entry e, OverlayEndReason reason) {
    e.cancelTimeouts();
    e.durationTimer?.cancel();
    e.removeTimer?.cancel();
    if (_isCurrent(e)) _byId.remove(e.id);
    _dismissBackendBestEffort(e);
    final wasSerialActive = _detachFromActive(e);
    _settle(e, null, reason);
    return wasSerialActive;
  }

  /// 强制移除时尽力定向关闭仍展示的后端，不等待其完成。
  void _dismissBackendBestEffort(_Entry e) {
    if (e.externalDone) return;
    e.externalDone = true; // 晚到的关闭信号不得再次驱动移除
    if (e.externalDismiss != null) _callDismiss(e, null);
  }

  /// 请求定向关闭后端；同步或异步失败均上报而不外抛，仅同步失败返回 false。
  bool _callDismiss(_Entry e, Object? result) {
    if (e.dismissRequested) return true; // 已经请求过：不再重复调用后端
    e.dismissRequested = true;
    try {
      e.externalDismiss!(result).catchError((Object error, StackTrace stack) {
        _reportError(error, stack, 'while dismissing overlay "${e.id}"');
      });
      return true;
    } catch (error, stack) {
      _reportError(error, stack, 'while dismissing overlay "${e.id}"');
      e.externalDone = true; // 不再重复请求失败的后端
      return false;
    }
  }

  /// 仅交付一次结果与结束原因，取消超时并发布 ended。
  void _settle(_Entry e, Object? result, OverlayEndReason reason) {
    if (e.settled) return;
    e.settled = true;
    e.cancelTimeouts();
    e.endReason ??= reason;
    try {
      e.settle(result);
    } catch (error, stack) {
      _reportError(error, stack, 'while settling overlay "${e.id}"');
      result = null;
      e.settle(null);
    }
    e.settleOutcome(result, e.endReason!);
    _emit(e, OverlayEventType.ended, e.endReason);
  }

  /// 以 disposed 原因结束所有条目并释放资源；销毁中提交立即以 disposed 结束。
  @override
  void dispose() {
    _checkMutation();
    if (isDisposed) return;
    _disposing = true;
    _batch(_dispose);
    super.dispose();
  }

  /// 在统一批次中销毁所有运行时状态。
  void _dispose() {
    for (final s in _slots.values) {
      s.gapTimer?.cancel();
      s.delayTimer?.cancel();
      s.cooldownTimer?.cancel();
    }
    _clear(OverlayEndReason.disposed);
    _disposed = true;
    _rescheduleSlots.clear();
    _deferredSlots.clear();
    _releasePending = false;
    _unblockPending = false;
    _frameNotifyPending = false;
    _notifyPending = false;
    for (final token in _holds) {
      token._release = null;
    }
    _holds.clear();
    _events.close();
  }

  /// 是否已完成运行时清理。
  bool _disposed = false;

  /// 清理回调执行前即进入销毁阶段，阻止重入提交进入容器。
  bool _disposing = false;

  /// 是否已开始销毁，供异步或帧后回调避免访问已失效的管理器。
  bool get isDisposed => _disposed || _disposing;
}
