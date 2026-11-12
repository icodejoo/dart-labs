// Shared report output for the benchmark screens: print to stdout AND append
// to the file named by `XVG_MICRO_OUT` when that variable is set.
//
// The file matters on Windows: Flutter's runner reattaches stdout to the parent
// console (`AttachConsole` + reopened stdio), so a caller that pipes or
// redirects the process captures nothing. Any harness that wants to run a
// benchmark N times and aggregate needs a file to read.
//
// 基准屏幕共用的报告输出：打印到 stdout，同时在设置了 `XVG_MICRO_OUT` 时把内容
// 追加写入该文件。
//
// 文件在 Windows 上很关键：Flutter runner 会把 stdout 重新挂到父控制台
// （`AttachConsole` + 重开标准流），因此对该进程做管道/重定向的调用方什么都
// 拿不到。任何想把基准跑 N 次再汇总的外部脚本都需要一个文件来读。

import 'dart:io';

/// Report file path baked in via `--dart-define=REPORT_FILE=<path>`; used when
/// the `XVG_MICRO_OUT` environment variable is not set (an activity started
/// with `am start` on Android cannot receive environment variables).
///
/// 通过 `--dart-define=REPORT_FILE=<路径>` 编进去的报告文件路径；仅在没有设置
/// `XVG_MICRO_OUT` 环境变量时使用（Android 上 `am start` 启动的 activity
/// 收不到环境变量）。
const String _reportFileDefine = String.fromEnvironment('REPORT_FILE');

/// Resolved report file path: `XVG_MICRO_OUT` first, then `REPORT_FILE`;
/// null when neither is set (default behaviour: stdout only).
///
/// 解析后的报告文件路径：优先 `XVG_MICRO_OUT`，其次 `REPORT_FILE`；都没设则为
/// null（默认行为：只写 stdout）。
String? reportOutPath() {
  final env = Platform.environment['XVG_MICRO_OUT'];
  if (env != null && env.isNotEmpty) return env;
  return _reportFileDefine.isEmpty ? null : _reportFileDefine;
}

/// Appends [text] to [reportOutPath]'s file (creating parent dirs); no-op when
/// no path is configured.
///
/// 把 [text] 追加写入 [reportOutPath] 指向的文件（自动建父目录）；未配置路径时
/// 空操作。
void appendToReportFile(String text) {
  final outPath = reportOutPath();
  if (outPath == null) return;
  final file = File(outPath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(text, mode: FileMode.append);
}

/// Prints [text] and, when `XVG_MICRO_OUT` is set, appends it to that file.
///
/// 打印 [text]；若设置了 `XVG_MICRO_OUT`，同时追加写入该文件。
///
/// Example:
/// ```dart
/// emitReport('=== MY REPORT ===\nvalue=1\n');
/// ```
void emitReport(String text) {
  // ignore: avoid_print
  print(text);
  appendToReportFile(text);
}

const String _autoExitRaw = String.fromEnvironment('AUTOEXIT');

/// Whether a benchmark should terminate the process as soon as it has printed
/// its report, instead of waiting for the on-screen exit button. Enable with
/// `--dart-define=AUTOEXIT=1` (or `=true`), which is what lets a harness run
/// the same benchmark repeatedly unattended.
///
/// Read through [String.fromEnvironment] rather than [bool.fromEnvironment] on
/// purpose: `bool.fromEnvironment` accepts *only* the exact strings `"true"`
/// and `"false"`, so `--dart-define=AUTOEXIT=1` silently evaluates to false —
/// which cost one wasted benchmark round here, the app sitting on its exit
/// button while the harness waited forever.
///
/// 基准是否应在打印完报告后立即结束进程，而不是等界面上的退出按钮。用
/// `--dart-define=AUTOEXIT=1`（或 `=true`）开启，正是它让外部脚本可以无人值守地
/// 重复运行同一个基准。
///
/// 刻意用 [String.fromEnvironment] 而不是 [bool.fromEnvironment] 来读：
/// `bool.fromEnvironment` **只**接受 `"true"`/`"false"` 两个精确字符串，因此
/// `--dart-define=AUTOEXIT=1` 会静默求值为 false——这里为此白跑了一轮基准，
/// 应用停在退出按钮上，而外部脚本一直等下去。
const bool autoExitAfterReport = _autoExitRaw == '1' || _autoExitRaw == 'true';
