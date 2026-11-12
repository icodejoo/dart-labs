/// 缓冲快照中线程 stat 的段标记。
const String _statsMarker = 'STATS';

/// 缓冲快照中线程 comm 的段标记。
const String _commsMarker = 'COMMS';

/// 同一快照重复出现线程时的错误。
const String _duplicateThread = '重复线程';

/// Linux stat 中用于 CPU 增量计算的不可变字段。
final class ProcCpuStat {
  /// 创建已解析的进程或线程计数；单位为 CLK_TCK。
  const ProcCpuStat(this.id, this.name, this.user, this.system, this.started);

  /// 内核进程或线程编号。
  final int id;

  /// 括号中的完整 comm，允许空格和括号。
  final String name;

  /// 用户态累计节拍。
  final int user;

  /// 内核态累计节拍。
  final int system;

  /// 启动节拍，用于识别编号复用。
  final int started;
}

/// 解析 Android/Linux /proc stat；字段缺失、非整数或负数显式抛错。
ProcCpuStat parseProcCpuStat(String text) {
  final open = text.indexOf(' (');
  final close = text.lastIndexOf(') ');
  if (open < 1 || close <= open) throw const FormatException('无效 stat comm');
  final id = int.tryParse(text.substring(0, open));
  final fields = text.substring(close + 2).trim().split(RegExp(r'\s+'));
  if (id == null || id <= 0 || fields.length < 20 || fields[0].length != 1) {
    throw const FormatException('无效 stat 字段');
  }

  /// 只接收非负的累计计数。
  int counter(int index) {
    final value = int.tryParse(fields[index]);
    if (value == null || value < 0)
      throw FormatException('无效 stat 字段 ${index + 3}');
    return value;
  }

  return ProcCpuStat(id, text.substring(open + 2, close), counter(11),
      counter(12), counter(19));
}

/// 按主机读取时刻差和 [ticksPerSecond] 计算单核百分比；重启或计数倒退抛错。
double procCpuPercent(
    ProcCpuStat before, ProcCpuStat after, double seconds, int ticksPerSecond) {
  if (before.id != after.id ||
      before.started != after.started ||
      !seconds.isFinite ||
      seconds <= 0 ||
      ticksPerSecond <= 0 ||
      after.user < before.user ||
      after.system < before.system) {
    throw const FormatException('CPU 身份、时长或累计计数无效');
  }
  return (after.user + after.system - before.user - before.system) /
      seconds /
      ticksPerSecond *
      100;
}

/// 解析一次 shell 快照；必须含进程、时钟频率以及每个线程的 stat/comm。
Map<String, Object?> parseProcSnapshot(String text) {
  int? hz;
  ProcCpuStat? process;
  final threads = <int, ProcCpuStat>{};
  final names = <int, String>{};
  List<int>? ids;
  final commLines = <String>[];
  var section = '';
  for (final line in text.split(RegExp(r'\r?\n'))) {
    if (section == _commsMarker) {
      if (line.isNotEmpty) commLines.add(line);
      continue;
    }
    if (line.startsWith('TIDS\t')) {
      ids = line
          .substring(5)
          .trim()
          .split(RegExp(r'\s+'))
          .map(int.parse)
          .toList();
      continue;
    }
    if (line == _statsMarker || line == _commsMarker) {
      section = line;
      continue;
    }
    if (section == _statsMarker) {
      final stat = parseProcCpuStat(line);
      if (threads.containsKey(stat.id))
        throw const FormatException(_duplicateThread);
      threads[stat.id] = stat;
      continue;
    }
    if (line.startsWith('HZ\t')) hz = int.tryParse(line.substring(3).trim());
    if (line.startsWith('PROCESS\t'))
      process = parseProcCpuStat(line.substring(8));
    if (line.startsWith('STAT\t')) {
      final stat = parseProcCpuStat(line.substring(5));
      if (threads.containsKey(stat.id))
        throw const FormatException(_duplicateThread);
      threads[stat.id] = stat;
    }
    if (line.startsWith('COMM\t')) {
      final tail = line.substring(5);
      final tab = tail.indexOf('\t');
      if (tab < 1) throw const FormatException('无效 comm');
      final id = int.tryParse(tail.substring(0, tab));
      if (id == null) throw const FormatException('无效 comm tid');
      names[id] = tail.substring(tab + 1);
    }
  }
  if (ids != null) {
    if (ids.length != commLines.length ||
        ids.length != threads.length ||
        ids.toSet().length != ids.length ||
        ids.any((id) => !threads.containsKey(id))) {
      throw FormatException(
          '线程在快照内变化或缺少 comm，不得错配：ids=${ids.length} comm=${commLines.length} stat=${threads.length}');
    }
    for (var index = 0; index < ids.length; index++) {
      names[ids[index]] = commLines[index];
    }
  }
  if (hz == null ||
      hz <= 0 ||
      process == null ||
      threads.isEmpty ||
      threads.keys.any((id) => !names.containsKey(id))) {
    throw const FormatException('不完整 /proc 快照，不得填零');
  }
  return {'hz': hz, 'process': process, 'threads': threads, 'names': names};
}

/// 比较两个快照；新建/退出线程单列，进程合计取进程 stat，绝不按缺测线程补零。
///
/// 成功返回 `valid_cpu=true`；快照无效或计数倒退时抛出异常。
Map<String, Object?> compareProcSnapshots(
    String before, String after, double seconds) {
  final first = parseProcSnapshot(before);
  final last = parseProcSnapshot(after);
  if (first['hz'] != last['hz']) throw const FormatException('CLK_TCK 改变');
  final hz = first['hz']! as int;
  final threads = first['threads']! as Map<int, ProcCpuStat>;
  final finalThreads = last['threads']! as Map<int, ProcCpuStat>;
  final names = last['names']! as Map<int, String>;
  final values = <Map<String, Object?>>[
    for (final entry in finalThreads.entries)
      if (threads.containsKey(entry.key))
        {
          'tid': entry.key,
          'name': names[entry.key],
          'cpu_percent':
              procCpuPercent(threads[entry.key]!, entry.value, seconds, hz)
        },
  ];
  return {
    'method': '/proc stat delta; single-core percent',
    'valid_cpu': true,
    'seconds': seconds,
    'clk_tck': hz,
    'process_cpu_percent': procCpuPercent(first['process']! as ProcCpuStat,
        last['process']! as ProcCpuStat, seconds, hz),
    'threads': values,
    'new_threads':
        finalThreads.keys.where((id) => !threads.containsKey(id)).toList(),
    'exited_threads':
        threads.keys.where((id) => !finalThreads.containsKey(id)).toList(),
  };
}
