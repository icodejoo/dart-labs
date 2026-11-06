part of 'cacheman.dart';

/// Shared notifications and earliest-deadline flush scheduling; never stores values.
/// 共享变更通知和最早截止时间落盘调度，从不缓存读值。
class _ContainerHub with WidgetsBindingObserver {
  _ContainerHub(
      Future<void> Function() flush, void Function(Object, StackTrace) report)
      : _flush = flush,
        _report = report;

  /// Weak identity registry. / 弱引用身份注册表。
  static final _hubs = Expando<_ContainerHub>();

  /// Attaches one listener per identity. / 每个身份只挂接一个监听器。
  static _ContainerHub of(
    Object identity, {
    required VoidCallback? Function(void Function(String?)) listen,
    required bool synchronous,
    required Future<void> Function() flush,
    required void Function(Object, StackTrace) report,
  }) {
    final existing = _hubs[identity];
    if (existing != null) return existing;
    final hub = _ContainerHub(flush, report);
    _hubs[identity] = hub;
    hub._cancel = listen(hub._changed);
    hub.synchronous = synchronous && hub._cancel != null;
    return hub;
  }

  /// Underlying subscription, retained for hub lifetime. / 在 Hub 生命周期内保留底层订阅。
  VoidCallback? _cancel;

  /// Whether change notifications exist. / 是否支持变更通知。
  bool get supportsWatch => _cancel != null;

  /// Whether versions can safely maintain an incremental index. / 版本是否可安全增量维护索引。
  bool synchronous = false;

  /// Monotonic backend change version. / 单调递增的底层变更版本。
  int version = 0;

  /// Watchers indexed by actual storage key. / 按实际存储键登记监听。
  final _watchers = <String, Set<_HubWatch>>{};

  /// Pending timer and its absolute deadline. / 待执行计时器及其绝对截止时间。
  Timer? _timer;
  DateTime? _deadline;

  /// Backend flush hook. / 底层落盘原语。
  final Future<void> Function() _flush;

  /// Report to the most recent delayed writer or explicit flush caller.
  /// 向最近一次延迟写入者或主动 flush 调用者上报，避免向所有实例重复报错。
  void Function(Object, StackTrace) _report;

  /// Lifecycle registration is lazy and exists only while a flush is pending.
  /// 生命周期观察器惰性注册，仅在存在待落盘任务时保留，避免绑定长期持有 Hub。
  bool _observing = false;

  /// Dispatch active snapshot records still matching the key; clear reaches all.
  /// 分发快照中仍匹配该键的活跃记录，允许重入迁移；clear 仍通知所有活跃记录。
  void _changed(String? key) {
    version++;
    final snapshot = key == null
        ? _watchers.values.expand((set) => set).toList()
        : _watchers[key]?.toList() ?? <_HubWatch>[];
    for (final watcher in snapshot) {
      if (watcher.active && (key == null || watcher.storageKey == key)) {
        watcher.notify();
      }
    }
  }

  /// Register or migrate a watcher. / 登记或迁移监听器。
  void add(_HubWatch watcher) =>
      (_watchers[watcher.storageKey] ??= <_HubWatch>{}).add(watcher);

  /// Remove empty buckets as well. / 同时清理空分组。
  void remove(_HubWatch watcher) {
    final bucket = _watchers[watcher.storageKey];
    bucket?.remove(watcher);
    if (bucket?.isEmpty ?? false) _watchers.remove(watcher.storageKey);
  }

  /// Keep an existing earlier deadline; subsequent writes never postpone it.
  /// 保留已有的更早截止时间，后续写入不推迟落盘。
  void scheduleFlush(Duration delay, void Function(Object, StackTrace) report) {
    _report = report;
    final deadline = DateTime.now().add(delay);
    if (_deadline != null && !_deadline!.isAfter(deadline)) return;
    _timer?.cancel();
    _deadline = deadline;
    if (!_observing) {
      WidgetsFlutterBinding.ensureInitialized().addObserver(this);
      _observing = true;
    }
    _timer = Timer(delay, flushNow);
  }

  /// Queue a save now, reporting synchronous and Future failures alike.
  /// 立即排一次保存，同步异常和 Future 错误都上报。
  void flushNow([void Function(Object, StackTrace)? report]) {
    _timer?.cancel();
    _timer = null;
    _deadline = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    final reporter = report ?? _report;
    Future<void>.sync(_flush).catchError((Object error, StackTrace trace) {
      reporter(error, trace);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      flushNow();
    }
  }
}

/// Instance-owned subscription record, relocatable across namespaces.
/// 实例持有的订阅记录，可随命名空间迁移。
class _HubWatch {
  _HubWatch(this.key, this.storageKey, this.notify);

  /// Original logical key. / 原逻辑键。
  final String key;

  /// Current actual storage key. / 当前实际存储键。
  String storageKey;

  /// Safe instance callback. / 安全的实例回调。
  final VoidCallback notify;

  /// Canceled records are skipped even in an existing snapshot. / 快照内也跳过已取消记录。
  bool active = true;
}
