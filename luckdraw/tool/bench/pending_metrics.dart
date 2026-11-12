/// 待采冷页面场景；独立于已冻结的 MET2 预算 schema。
const List<String> kPendingFirstFrames = [
  'blank_first_frame',
  'wheel_first_frame',
  'grid_first_frame',
  'slot_first_frame',
];

/// 进程 CPU 的五秒稳态场景；乐透此处只测搅拌，不混入完整开奖。
const List<String> kPendingCpuScenes = [
  'wheel_steady',
  'grid_steady',
  'slot_steady',
  'capsule_mixing',
  'lotto_draw',
];

/// 保留硬门禁失败与不确定的四个复测项目。
const List<String> kPendingRetests = [
  'slot_raster',
  'grid_steady',
  'lotto_draw',
  'lots_shaking',
];

/// 每项先取得三轮，不足两个未污染样本时最多五次启动。
const int kPendingRounds = 3;

/// 每项累计启动上限，失败尝试也计数。
const int kPendingMaxStarts = 5;

/// 五秒窗口内每秒一次，另外保留窗口前后采样。
const int kPendingCpuSamples = 5;

/// CPU 握手的 localhost 端口，窗口外用 adb reverse 转发。
const int kPendingCpuPort = 41237;

/// 主进程 CPU；不把线程墙钟忙占比充当进程测量。
final class PendingProcessCpu {
  /// 保存 cpuinfo 的 [pid] 与以单核100%为单位的 [percent]。
  const PendingProcessCpu(this.pid, this.percent);

  /// cpuinfo 行中的主进程编号。
  final int pid;

  /// cpuinfo 的进程 CPU 百分比，允许多核超过100%。
  final double percent;
}

/// 从 Android cpuinfo 文本提取精确包名主进程；缺失、重复或坏数字显式报错。
///
/// [packageName] 不匹配 `包名:子进程` 或包名前缀，例如 `com.example.app`。
PendingProcessCpu parsePendingCpuInfo(String text, String packageName) {
  final pattern = RegExp(
      '^\\s*\\+?([0-9]+(?:\\.[0-9]+)?)%\\s+(\\d+)/${RegExp.escape(packageName)}:(?=\\s|\$)',
      multiLine: true);
  final matches = pattern.allMatches(text).toList();
  if (matches.length != 1) {
    throw FormatException('cpuinfo 主进程必须唯一: $packageName');
  }
  final match = matches.single;
  final pid = int.parse(match[2]!);
  if (pid <= 0) throw const FormatException('cpuinfo PID 必须大于零');
  final percent = double.parse(match[1]!);
  if (!percent.isFinite) throw const FormatException('cpuinfo CPU 必须是有限值');
  return PendingProcessCpu(pid, percent);
}

/// 一条 top 线程采样，保留原始名称与角色。
final class PendingThreadCpu {
  /// 创建一条已解析线程结果。
  const PendingThreadCpu(this.tid, this.name, this.percent, this.role);

  /// 线程编号；top -H 没有 TID 列时使用 PID 列。
  final int tid;

  /// 包含空格的线程名也完整保留。
  final String name;

  /// 线程 CPU 百分比，使用 top 原单位。
  final double percent;

  /// `UI`、`Raster` 或 `other`，不会把其它线程计入 UI。
  final String role;
}

/// 归一化 Android 线程名；兼容 UI/Raster 与 1.ui/1.raster。
String pendingThreadRole(String name) {
  final normalized = name.trim().toLowerCase();
  if (RegExp(r'^(?:\d+\.|io\.flutter\.)?ui$').hasMatch(normalized)) {
    return 'UI';
  }
  if (RegExp(r'^(?:\d+\.|io\.flutter\.)?raster$').hasMatch(normalized)) {
    return 'Raster';
  }
  return 'other';
}

/// 解析 Android16 toybox top -b -n 1 -H 输出，支持 %CPU/CPU% 与 PID/TID。
///
/// 返回全部线程，且必须有 UI 与 Raster；列缺失、数据行损坏或角色缺失抛出
/// [FormatException]。例如 `parsePendingTop(savedText)`。
List<PendingThreadCpu> parsePendingTop(String text) {
  final lines =
      text.replaceAll(RegExp(r'\x1b\[[0-9;]*[A-Za-z]'), '').split('\n');
  final headerIndex = lines.indexWhere((line) =>
      RegExp(r'\bPID\b').hasMatch(line) &&
      (line.contains('%CPU') || line.contains('CPU%')));
  if (headerIndex < 0) throw const FormatException('top 缺少线程列头');
  final header = lines[headerIndex]
      .replaceAll('[', ' ')
      .replaceAll(']', '')
      .trim()
      .split(RegExp(r'\s+'));
  final idColumn =
      header.contains('TID') ? header.indexOf('TID') : header.indexOf('PID');
  final cpuColumn =
      header.contains('%CPU') ? header.indexOf('%CPU') : header.indexOf('CPU%');
  if (idColumn < 0 || cpuColumn < 0)
    throw const FormatException('top 缺少 PID/CPU 列');
  final nameColumn = header.indexWhere(
      (column) => const ['ARGS', 'NAME', 'CMD', 'COMMAND'].contains(column));
  if (nameColumn < 0 || nameColumn != header.length - 1) {
    throw const FormatException('top 线程名列必须位于末尾');
  }
  final result = <PendingThreadCpu>[];
  for (final line in lines.skip(headerIndex + 1)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final fields = trimmed.split(RegExp(r'\s+'));
    if (fields.length <= nameColumn) {
      throw FormatException('top 线程行缺列: $trimmed');
    }
    final tid = int.tryParse(fields[idColumn]);
    final percent = double.tryParse(fields[cpuColumn].replaceAll('%', ''));
    if (tid == null ||
        tid <= 0 ||
        percent == null ||
        !percent.isFinite ||
        percent < 0) {
      throw FormatException('top 线程行数字非法: $trimmed');
    }
    final name = fields.skip(nameColumn).join(' ');
    if (result.any((entry) => entry.tid == tid)) {
      throw FormatException('top TID 重复: $tid');
    }
    result.add(PendingThreadCpu(tid, name, percent, pendingThreadRole(name)));
  }
  if (!result.any((entry) => entry.role == 'UI') ||
      !result.any((entry) => entry.role == 'Raster')) {
    throw const FormatException('top 未同时识别 UI 与 Raster，拒绝静默漏采');
  }
  return result;
}

/// 返回三次正有限值的中位数；缺测、零或非有限值不能作为冷首帧。
double pendingFirstFrameMedian(List<double> values) {
  if (values.length != kPendingRounds ||
      values.any((value) => !value.isFinite || value <= 0)) {
    throw const FormatException('冷首帧必须有三次正有限采样');
  }
  return (List<double>.of(values)..sort())[1];
}

/// 返回玩法与空白冷首帧中位数之差；保留负差，不据此宣布预算通过。
double pendingFirstFrameIncrement(List<double> blank, List<double> game) =>
    pendingFirstFrameMedian(game) - pendingFirstFrameMedian(blank);

/// 判断是否应补样：三轮后仅未污染不足两个时补到最多五次。
///
/// [starts] 含失败尝试；不得靠替换坏轮隐藏失败或不稳定。
bool pendingNeedsStart(int starts, int valid, int clean,
    {bool retest = false}) {
  if (starts < 0 || valid < 0 || clean < 0 || valid > starts || clean > valid) {
    throw const FormatException('轮次计数非法');
  }
  return starts < kPendingMaxStarts &&
      (valid < kPendingRounds || (retest && clean < 2));
}

/// 验证一次五秒 CPU 测量的七次采样及 PID/时序，解析失败不得静默。
///
/// [data] 来自 cpu_sampler 的原始报告；所有五次窗口采样必须各在对应一秒内完成。
void validatePendingCpuWindow(Map<String, Object?> data) {
  final before = data['before']! as Map<String, Object?>;
  final after = data['after']! as Map<String, Object?>;
  final samples = data['samples']! as List<Object?>;
  final pid = before['pid'];
  final elapsed = data['window_micros']! as int;
  if (pid is! int ||
      pid <= 0 ||
      after['pid'] != pid ||
      samples.length != kPendingCpuSamples ||
      elapsed < kPendingCpuSamples * Duration.microsecondsPerSecond) {
    throw const FormatException('CPU 轮次的 PID、样本数或窗口长度不完整');
  }
  for (var index = 0; index < samples.length; index++) {
    final sample = samples[index]! as Map<String, Object?>;
    final start = sample['offset_micros']! as int;
    final end = sample['end_offset_micros']! as int;
    if (sample['pid'] != pid ||
        start < index * Duration.microsecondsPerSecond ||
        end < start ||
        end >= (index + 1) * Duration.microsecondsPerSecond) {
      throw const FormatException('CPU 样本越窗或进程重启');
    }
  }
}
