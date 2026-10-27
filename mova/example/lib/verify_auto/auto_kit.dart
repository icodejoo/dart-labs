// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

/// Shared helpers of the scripted AUTORUN mode of the verify pages (example only,
/// never shipped). Pure Dart: no Flutter, no mova imports.
///
/// 验证页脚本化 AUTORUN 模式的共用小工具（仅 example，不进发布包）。纯 Dart：不依赖 Flutter 与 mova。

/// `--dart-define=AUTORUN=true` switches a verify page into the scripted mode.
///
/// `--dart-define=AUTORUN=true` 让验证页进入脚本化模式。
const bool kAutoRun = bool.fromEnvironment('AUTORUN');

/// `--dart-define=RUNS=3`: how many times each scenario repeats (0 = not set).
///
/// `--dart-define=RUNS=3`：每个场景重复的次数（0 表示未设置）。
const int _kRunsDefine = int.fromEnvironment('RUNS', defaultValue: 0);

/// Default repetitions per scenario.
///
/// 每个场景默认重复次数。
const int kDefaultRuns = 3;

/// Optional device-coverage launcher overrides; absent for existing callers.
///
/// 覆盖验证入口的可选运行参数；原有入口不设置，行为保持不变。
int? coverageRunsOverride;
String? coverageOnlyOverride;

/// `--dart-define=LOG_FILE=<path>`: file every log line is appended to.
///
/// `--dart-define=LOG_FILE=<路径>`：每行日志追加写入的文件。
const String kLogFileDefine = String.fromEnvironment('LOG_FILE');

/// `--dart-define=ONLY=V5,V7`: run only these scenario ids (empty = all, in fixed order); see [autoOnlyRaw].
///
/// `--dart-define=ONLY=V5,V7`：只跑这些场景编号（空表示按固定顺序全跑）。
const String kOnlyDefine = String.fromEnvironment('ONLY');

/// Resolves the log file path: the `LOG_FILE` define wins, then the `MOVA_LOG`
/// environment variable (the convention of the older verify pages; the release
/// desktop build does not forward `print` to the console). Empty = no file.
///
/// 解析日志文件路径：优先 `LOG_FILE` 编译期参数，其次环境变量 `MOVA_LOG`（旧验证页的
/// 约定；release 桌面版的 `print` 不会回传控制台）。空串表示不落盘。
///
/// - [define]: value of the define / 编译期参数值
/// - [env]: process environment (injectable for tests) / 进程环境变量（可注入，便于测试）
///
/// Returns the path or an empty string / 返回路径或空串。
String resolveLogPath({String define = kLogFileDefine, Map<String, String>? env}) {
  if (define.isNotEmpty) return define;
  return (env ?? Platform.environment)['MOVA_LOG'] ?? '';
}

/// Resolves how many times each scenario repeats: the `RUNS` define, else the
/// `MOVA_RUNS` environment variable (desktop convenience: no rebuild needed), else [kDefaultRuns].
///
/// 解析每个场景重复几次：优先 `RUNS` 编译期参数，其次环境变量 `MOVA_RUNS`（桌面端方便，免重新构建），
/// 都没有则取 [kDefaultRuns]。
///
/// - [define]: value of the define (0 = unset) / 编译期参数值（0 为未设置）
/// - [env]: process environment (injectable for tests) / 进程环境变量（可注入，便于测试）
///
/// Returns a positive count / 返回正整数。
int autoRuns({int define = _kRunsDefine, Map<String, String>? env}) {
  if (coverageRunsOverride != null) return coverageRunsOverride!;
  if (define > 0) return define;
  final v = int.tryParse((env ?? Platform.environment)['MOVA_RUNS'] ?? '');
  return v != null && v > 0 ? v : kDefaultRuns;
}

/// Resolves the raw `ONLY` list: the define, else the `MOVA_ONLY` environment variable.
///
/// 解析原始 `ONLY` 列表：优先编译期参数，其次环境变量 `MOVA_ONLY`。
///
/// - [define]: value of the define / 编译期参数值
/// - [env]: process environment (injectable for tests) / 进程环境变量（可注入，便于测试）
///
/// Returns the comma separated ids (may be empty) / 返回逗号分隔的编号（可为空）。
String autoOnlyRaw({String define = kOnlyDefine, Map<String, String>? env}) =>
    coverageOnlyOverride ?? (define.isNotEmpty ? define : ((env ?? Platform.environment)['MOVA_ONLY'] ?? ''));

/// Parses the `ONLY` define into a set of upper-cased ids; empty means "all".
///
/// 把 `ONLY` 参数解析成大写编号集合；空表示全部。
///
/// - [raw]: comma separated ids / 逗号分隔的编号
///
/// Returns the id set / 返回编号集合。
Set<String> parseOnly(String raw) =>
    raw.split(',').map((s) => s.trim().toUpperCase()).where((s) => s.isNotEmpty).toSet();

/// Appends tagged lines to stdout/logcat and, when a path is set, to a file.
///
/// 把带前缀的行写到 stdout/logcat，设了路径时同时追加写入文件。
///
/// Example / 示例:
/// ```dart
/// final log = AutoLog('[MOVA-HE]');
/// log.line('hello'); // prints "[MOVA-HE] hello" and appends it to the file
/// ```
class AutoLog {
  /// Creates a log with [tag]; [path] defaults to [resolveLogPath].
  ///
  /// 用 [tag] 创建日志；[path] 默认取 [resolveLogPath]。
  AutoLog(this.tag, {String? path}) : path = path ?? resolveLogPath();

  /// Fixed line prefix, e.g. `[MOVA-HE]`.
  ///
  /// 固定行前缀，如 `[MOVA-HE]`。
  final String tag;

  /// Target file; empty means stdout only.
  ///
  /// 目标文件；空表示只写 stdout。
  final String path;

  /// Writes one line (prefix added) and returns the full text; creates the file's parent directory when missing.
  ///
  /// 写一行（自动加前缀），返回完整文本；父目录不存在时自动创建。
  ///
  /// - [msg]: the message / 消息正文
  ///
  /// Returns the line as written / 返回实际写出的行。
  String line(String msg) {
    final text = '$tag $msg';
    print(text);
    if (path.isNotEmpty) {
      try {
        final f = File(path);
        if (!f.parent.existsSync()) f.parent.createSync(recursive: true);
        f.writeAsStringSync('$text\n', mode: FileMode.append, flush: true);
      } on FileSystemException catch (e) {
        print('$tag log file write failed: $e');
      }
    }
    return text;
  }
}

/// min/max/avg/median of a list of samples.
///
/// 一组样本的最小/最大/平均/中位数。
class Stats {
  /// Computes the statistics of [values] (must not be empty).
  ///
  /// 计算 [values] 的统计量（不可为空）。
  Stats(Iterable<num> values) : _sorted = (values.map((v) => v.toDouble()).toList()..sort()) {
    assert(_sorted.isNotEmpty, 'Stats needs at least one sample');
  }

  final List<double> _sorted;

  /// Sample count.
  ///
  /// 样本数。
  int get n => _sorted.length;

  /// Smallest sample.
  ///
  /// 最小值。
  double get min => _sorted.first;

  /// Largest sample.
  ///
  /// 最大值。
  double get max => _sorted.last;

  /// Arithmetic mean.
  ///
  /// 算术平均。
  double get avg => _sorted.reduce((a, b) => a + b) / n;

  /// Median (mean of the two middle samples for even counts).
  ///
  /// 中位数（偶数个样本取中间两个的平均）。
  double get median => n.isOdd ? _sorted[n ~/ 2] : (_sorted[n ~/ 2 - 1] + _sorted[n ~/ 2]) / 2;

  @override
  String toString() =>
      'n=$n min=${min.toStringAsFixed(0)} max=${max.toStringAsFixed(0)} avg=${avg.toStringAsFixed(1)} median=${median.toStringAsFixed(1)}';
}

/// Named sample series with a printable summary, one line per series.
///
/// 具名样本序列，可打印汇总，每个序列一行。
class Samples {
  final Map<String, List<double>> _data = <String, List<double>>{};

  /// Adds [value] to the series [name].
  ///
  /// 往序列 [name] 追加样本 [value]。
  void add(String name, num value) => _data.putIfAbsent(name, () => <double>[]).add(value.toDouble());

  /// The raw values of [name] (empty when unknown).
  ///
  /// [name] 的原始样本（未知则为空）。
  List<double> values(String name) => List<double>.unmodifiable(_data[name] ?? const <double>[]);

  /// One line per series: name, the raw values, then the statistics.
  ///
  /// 每个序列一行：名字、原始样本、统计量。
  ///
  /// Returns the lines in insertion order / 按插入顺序返回各行。
  List<String> summary() => [
    for (final e in _data.entries)
      '${e.key} values=[${e.value.map((v) => v.toStringAsFixed(0)).join(',')}] ${Stats(e.value)}',
  ];
}

/// An event with the monotonic time it arrived at.
///
/// 一个事件，连同它到达时的单调时间。
class Stamped<E> {
  /// Creates the pair.
  ///
  /// 创建一对。
  const Stamped(this.event, this.at);

  /// The event.
  ///
  /// 事件。
  final E event;

  /// Time since the recorder's clock started.
  ///
  /// 自记录器时钟起算的时间。
  final Duration at;
}

class _Waiter<E> {
  _Waiter(this.test, this.done);
  final bool Function(Stamped<E>) test;
  final Completer<Stamped<E>?> done;
}

/// Records every event of a stream with a monotonic timestamp and lets a script
/// wait for a particular one (with timeout). Timestamps are the moments the
/// real events arrive, not estimates.
///
/// 记录一个流里的所有事件和单调时间戳，并让脚本等待某个特定事件（带超时）。时间戳是
/// 真实事件到达的时刻，不是估算。
///
/// Example / 示例:
/// ```dart
/// final rec = EventRecorder<String>(controller.stream);
/// final hit = await rec.wait<String>(where: (e) => e == 'ready', timeout: Duration(seconds: 5));
/// ```
class EventRecorder<E> {
  /// Starts recording [source]; share [clock] between recorders to compare times.
  ///
  /// 开始记录 [source]；多个记录器共用 [clock] 即可互相比较时间。
  EventRecorder(Stream<E> source, {Stopwatch? clock}) : clock = clock ?? (Stopwatch()..start()) {
    _sub = source.listen(_onEvent);
  }

  /// The monotonic clock stamping the events.
  ///
  /// 给事件打时间戳的单调时钟。
  final Stopwatch clock;

  /// Everything recorded so far, in arrival order.
  ///
  /// 目前记录的全部事件，按到达顺序。
  final List<Stamped<E>> log = <Stamped<E>>[];

  late final StreamSubscription<E> _sub;
  final List<_Waiter<E>> _waiters = <_Waiter<E>>[];

  /// A marker meaning "events from now on"; pass it as `from`.
  ///
  /// "从现在起的事件"的标记；传给 `from`。
  int get mark => log.length;

  void _onEvent(E e) {
    final s = Stamped<E>(e, clock.elapsed);
    log.add(s);
    for (final w in List<_Waiter<E>>.of(_waiters)) {
      if (w.test(s)) {
        _waiters.remove(w);
        w.done.complete(s);
      }
    }
  }

  /// All recorded events of type [T] from index [from] on.
  ///
  /// 从下标 [from] 起记录的所有 [T] 类型事件。
  ///
  /// - [from]: start index, see [mark] / 起始下标，见 [mark]
  /// - [where]: optional filter / 可选过滤条件
  ///
  /// Returns the matches in order / 按顺序返回匹配项。
  List<Stamped<T>> all<T extends E>({int from = 0, bool Function(T e)? where}) => [
    for (var i = from; i < log.length; i++)
      if (log[i].event is T && (where == null || where(log[i].event as T))) Stamped<T>(log[i].event as T, log[i].at),
  ];

  /// Waits for the first [T] (after index [from]) that passes [where]; looks at
  /// already recorded events first. Returns null on timeout.
  ///
  /// 等待（下标 [from] 之后）第一个满足 [where] 的 [T]；先查已记录的事件。超时返回 null。
  ///
  /// - [from]: start index, see [mark] / 起始下标，见 [mark]
  /// - [where]: optional filter / 可选过滤条件
  /// - [timeout]: give up after this long / 超过此时长放弃
  ///
  /// Returns the stamped event or null / 返回带时间戳的事件，或 null。
  Future<Stamped<T>?> wait<T extends E>({
    int from = 0,
    bool Function(T e)? where,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    bool test(Stamped<E> s) => s.event is T && (where == null || where(s.event as T));
    for (var i = from; i < log.length; i++) {
      if (test(log[i])) return Stamped<T>(log[i].event as T, log[i].at);
    }
    final w = _Waiter<E>(test, Completer<Stamped<E>?>());
    _waiters.add(w);
    final hit = await w.done.future.timeout(
      timeout,
      onTimeout: () {
        _waiters.remove(w);
        return null;
      },
    );
    return hit == null ? null : Stamped<T>(hit.event as T, hit.at);
  }

  /// Stops recording and releases pending waiters with null.
  ///
  /// 停止记录，并以 null 释放仍在等待的调用。
  Future<void> dispose() async {
    await _sub.cancel();
    for (final w in _waiters) {
      if (!w.done.isCompleted) w.done.complete(null);
    }
    _waiters.clear();
  }
}

/// Signed milliseconds from [a] to [b].
///
/// 从 [a] 到 [b] 的有符号毫秒数。
///
/// - [a]: start / 起点
/// - [b]: end / 终点
///
/// Returns `b - a` in ms / 返回 `b - a`（毫秒）。
int msBetween(Duration a, Duration b) => (b - a).inMilliseconds;
