import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 集成测试文件后缀。
const String integrationSuffix = '_test.dart';

/// 单次构建和执行的最长时间。
const Duration integrationTimeout = Duration(minutes: 5);

/// Windows 设备标识，同时用于后台窗口环境开关。
const String _windowsDevice = 'windows';

/// 任务卡规定的默认复跑次数。
const int _defaultRepeat = 3;

/// 参数和报告共用的设备字段。
const String _deviceKey = 'device';

/// 参数和报告共用的次数字段。
const String _repeatKey = 'repeat';

/// 参数和单次记录共用的文件字段。
const String _fileKey = 'file';

/// 单次记录和汇总共用的通过字段。
const String _passedKey = 'passed';

/// 汇总记录的总次数字段。
const String _totalKey = 'total';

/// 单次记录和汇总共用的毫秒耗时字段。
const String _elapsedKey = 'elapsedMs';

/// 汇总记录的最终结果字段。
const String _successKey = 'success';

/// 串行集成测试参数；例如 `IntegrationOptions.parse(['--repeat=3'])`。
final class IntegrationOptions {
  /// 指定设备 [device]、次数 [repeat] 和可选文件 [file]。
  const IntegrationOptions(
      {this.device = _windowsDevice, this.repeat = _defaultRepeat, this.file});

  /// 解析命令行；未知、重复或无效参数抛出 [FormatException]。
  ///
  /// [arguments] 使用 `--device=windows --repeat=3 --file=wheel_flow_test.dart`。
  /// 返回可执行配置，例如 `IntegrationOptions.parse([])` 使用 Windows 三轮。
  factory IntegrationOptions.parse(List<String> arguments) {
    final values = <String, String>{};
    for (final argument in arguments) {
      final match =
          RegExp(r'^--(device|repeat|file)=(.+)$').firstMatch(argument);
      if (match == null || values.containsKey(match[1])) {
        throw FormatException('无效或重复参数: $argument');
      }
      values[match[1]!] = match[2]!;
    }
    final repeat = int.tryParse(values[_repeatKey] ?? '$_defaultRepeat');
    final device = values[_deviceKey] ?? _windowsDevice;
    final file =
        values[_fileKey]?.replaceFirst(RegExp(r'^integration_test/'), '');
    if (repeat == null ||
        repeat <= 0 ||
        !RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(device) ||
        (file != null &&
            !RegExp(r'^[A-Za-z0-9_]+_test\.dart$').hasMatch(file))) {
      throw const FormatException('设备、次数或文件名无效');
    }
    return IntegrationOptions(device: device, repeat: repeat, file: file);
  }

  /// Flutter 设备标识，支持 windows 或 adb serial。
  final String device;

  /// 每个文件的执行次数，必须大于零。
  final int repeat;

  /// 单文件名；为空时运行所有集成测试文件。
  final String? file;
}

/// 单次真实执行记录；例如 `IntegrationRun('wheel_flow_test.dart', 1, 0, 100)`。
final class IntegrationRun {
  /// 保存 [file]、轮次 [attempt]、退出码 [exitCode] 和毫秒耗时 [elapsedMs]。
  const IntegrationRun(this.file, this.attempt, this.exitCode, this.elapsedMs,
      {this.timedOut = false});

  /// 执行文件名。
  final String file;

  /// 从一开始的轮次。
  final int attempt;

  /// 进程退出码，零表示通过。
  final int exitCode;

  /// 构建和运行总耗时，单位毫秒。
  final int elapsedMs;

  /// 是否达到五分钟限制。
  final bool timedOut;

  /// 返回可编码的记录；例如 `jsonEncode(run.toJson())`。
  Map<String, Object> toJson() => {
        _fileKey: file,
        'attempt': attempt,
        'exitCode': exitCode,
        _elapsedKey: elapsedMs,
        'timedOut': timedOut,
        _passedKey: exitCode == 0 && !timedOut,
      };
}

/// 汇总 [runs] 与 [options]；[expectedFiles] 可指定计划全集，缺轮次不能成功。
///
/// 例如 `jsonEncode(integrationReport(options, runs))` 可写入报告文件。
Map<String, Object> integrationReport(
    IntegrationOptions options, List<IntegrationRun> runs,
    {List<String>? expectedFiles}) {
  final passed = runs.where((run) => run.exitCode == 0 && !run.timedOut).length;
  final files = expectedFiles?.toSet() ?? runs.map((run) => run.file).toSet();
  final complete = files.isNotEmpty &&
      runs.every((run) => files.contains(run.file)) &&
      files.every((file) {
        final attempts =
            runs.where((run) => run.file == file).map((run) => run.attempt);
        return attempts.length == options.repeat &&
            attempts
                .toSet()
                .containsAll(List.generate(options.repeat, (i) => i + 1));
      });
  return {
    _deviceKey: options.device,
    _repeatKey: options.repeat,
    'files': files.toList()..sort(),
    _totalKey: runs.length,
    _passedKey: passed,
    'failed': runs.length - passed,
    'passRate': runs.isEmpty ? 0.0 : passed / runs.length,
    _elapsedKey: runs.fold<int>(0, (sum, run) => sum + run.elapsedMs),
    'complete': complete,
    _successKey: complete && passed == runs.length,
    'runs': runs.map((run) => run.toJson()).toList(),
  };
}

/// 运行一轮并实时输出日志，超时仅终止本轮创建的进程树。
Future<IntegrationRun> _run(Directory example, IntegrationOptions options,
    String file, int attempt) async {
  final watch = Stopwatch()..start();
  stdout.writeln('$file [$attempt/${options.repeat}]');
  final process = await Process.start(
      Platform.isWindows ? 'flutter.bat' : 'flutter',
      ['test', 'integration_test/$file', '-d', options.device, '--no-pub'],
      workingDirectory: example.path,
      environment: options.device == _windowsDevice
          ? {'LUCKDRAW_TEST_WINDOW': '1'}
          : null,
      runInShell: Platform.isWindows);
  final output = Future.wait([
    stdout.addStream(process.stdout),
    stderr.addStream(process.stderr),
  ]);
  var timedOut = false;
  final code =
      await process.exitCode.timeout(integrationTimeout, onTimeout: () async {
    timedOut = true;
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
    } else {
      process.kill(ProcessSignal.sigkill);
    }
    return -1;
  });
  await output;
  watch.stop();
  return IntegrationRun(file, attempt, code, watch.elapsedMilliseconds,
      timedOut: timedOut);
}

/// 从包根调用；例如 `dart run tool/run_integration.dart --device=windows --repeat=3`。
///
/// [arguments] 见 [IntegrationOptions.parse]；报告写入 build/integration_report.json，
/// 任一次失败或没有测试文件时进程返回非零退出码。
Future<void> main(List<String> arguments) async {
  try {
    final options = IntegrationOptions.parse(arguments);
    final root = File.fromUri(Platform.script).parent.parent;
    final example = Directory('${root.path}/example');
    final directory = Directory('${example.path}/integration_test');
    final files = options.file == null
        ? directory
            .listSync()
            .whereType<File>()
            .map((file) => file.uri.pathSegments.last)
            .where((name) => name.endsWith(integrationSuffix))
            .toList()
        : [options.file!];
    files.sort();
    if (files.isEmpty ||
        files.any((file) => !File('${directory.path}/$file').existsSync())) {
      throw const FormatException('未找到集成测试文件');
    }
    final runs = <IntegrationRun>[];
    final reportFile = File('${root.path}/build/integration_report.json');
    reportFile.parent.createSync(recursive: true);
    for (final file in files) {
      for (var attempt = 1; attempt <= options.repeat; attempt++) {
        runs.add(await _run(example, options, file, attempt));
        reportFile.writeAsStringSync(
            '${const JsonEncoder.withIndent('  ').convert(integrationReport(options, runs, expectedFiles: files))}\n');
      }
    }
    final report = integrationReport(options, runs, expectedFiles: files);
    stdout.writeln('Integration: ${report[_passedKey]}/${report[_totalKey]}, '
        '${report[_elapsedKey]}ms; ${reportFile.path}');
    if (report[_successKey] != true) exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('Integration failed: $error');
    exitCode = 1;
  }
}
