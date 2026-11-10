import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pending_metrics.dart';
import 'proc_cpu.dart';

/// 有界执行一次 adb，失败保留退出码和原文。
Future<String> _adb(String serial, List<String> args) async {
  final result = await Process.run('adb', ['-s', serial, ...args])
      .timeout(const Duration(seconds: 15));
  if (result.exitCode != 0)
    throw StateError(
        'adb ${result.exitCode}: ${result.stderr}${result.stdout}');
  return result.stdout as String;
}

/// 一次 shell 调用读取 CLK_TCK、进程 stat 与全部线程 stat/comm。
String _command(int processId) => r'''set -e
printf 'HZ\t'; getconf CLK_TCK
printf 'PROCESS\t'; cat /proc/PID/stat
stats=''; comms=''
printf 'TIDS\t'
for p in /proc/PID/task/*; do
  printf '%s ' "${p##*/}"
  stats="$stats $p/stat"; comms="$comms $p/comm"
done
printf '\nSTATS\n'; cat $stats
printf 'COMMS\n'; cat $comms'''
    .replaceAll('PID', '$processId');

/// 将命令作为远端 sh 的单个参数，保留其中的换行与单引号。
String _shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// 包装访问身份；shell、run-as、su 只在窗口前探测。
List<String> _access(String mode, String packageName, String command) =>
    switch (mode) {
      'run-as' => [
          'shell',
          'run-as',
          packageName,
          'sh',
          '-c',
          _shellQuote(command)
        ],
      'su' => ['shell', 'su', '-c', _shellQuote(command)],
      _ => ['shell', command],
    };

/// 以 before/start/end 握手采集；窗口内只有开始和结束两次 adb 读取。
Future<void> main(List<String> args) async {
  if (args.length != 3) throw ArgumentError('serial package output 必填');
  final directory = Directory(args[2])..createSync(recursive: true);
  final server =
      await ServerSocket.bind(InternetAddress.loopbackIPv4, kPendingCpuPort);
  Socket? socket;
  try {
    await File('${directory.path}/server.ready').writeAsString('ready\n');
    socket = await server.first.timeout(const Duration(minutes: 4));
    final commands = StreamIterator(socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter()));

    /// 等待指定协议消息；不以固定延迟猜设备窗口。
    Future<void> expectCommand(String expected) async {
      if (!await commands.moveNext().timeout(const Duration(seconds: 45)) ||
          commands.current != expected) {
        throw StateError('期待 $expected');
      }
    }

    /// 消息写完才推进协议。
    Future<void> reply(String message) async {
      socket!.writeln(message);
      await socket.flush();
    }

    await expectCommand('before');
    final pidText = await _adb(args[0], ['shell', 'pidof', args[1]]);
    final processId = int.tryParse(pidText.trim());
    if (processId == null) throw FormatException('目标 PID 不唯一: $pidText');
    String? mode;
    final failures = <String, String>{};
    for (final candidate in ['shell', 'run-as', 'su']) {
      try {
        final probe = await _adb(
            args[0], _access(candidate, args[1], _command(processId)));
        await File('${directory.path}/probe_$candidate.txt')
            .writeAsString(probe);
        parseProcSnapshot(probe);
        mode = candidate;
        break;
      } on Object catch (error) {
        failures[candidate] = '$error';
        await File('${directory.path}/probe_$candidate.error.txt')
            .writeAsString('$error\n');
        if (error is FormatException) rethrow;
      }
    }
    await reply('ready');
    await expectCommand('start');
    final watch = Stopwatch()..start();
    final start = DateTime.now().toUtc();
    final before = await _adb(
        args[0],
        mode == null
            ? ['shell', 'dumpsys', 'cpuinfo']
            : _access(mode, args[1], _command(processId)));
    final beforeReadMicros = watch.elapsedMicroseconds;
    await File('${directory.path}/before.txt').writeAsString(before);
    await reply('started');
    await expectCommand('end');
    final elapsed = watch.elapsedMicroseconds;
    final after = await _adb(
        args[0],
        mode == null
            ? ['shell', 'dumpsys', 'cpuinfo']
            : _access(mode, args[1], _command(processId)));
    final afterReadMicros = watch.elapsedMicroseconds - elapsed;
    await File('${directory.path}/after.txt').writeAsString(after);
    final seconds = elapsed / Duration.microsecondsPerSecond;
    final report = <String, Object?>{
      'pid': processId,
      'started_at': start.toIso8601String(),
      'end_read_started_at':
          start.add(Duration(microseconds: elapsed)).toIso8601String(),
      'window_adb_calls': 2,
      'requested_steady_seconds': 5,
      'snapshot_strategy':
          'three buffered cat processes; no per-thread subprocess',
      'before_read_micros': beforeReadMicros,
      'after_read_micros': afterReadMicros,
      'access': mode,
      'access_failures': failures,
      if (mode != null) ...compareProcSnapshots(before, after, seconds),
      if (mode == null) ...{
        'method': 'dumpsys cpuinfo raw fallback',
        'valid_cpu': false,
        'seconds': seconds,
        'reason':
            '本设备 shell 无法读取目标进程线程级 CPU；run-as/su 也不可用。cpuinfo 不提供目标进程累计 CPU 时间，无法计算可信窗口增量，保留两份原文而不填零。',
      },
    };
    await File('${directory.path}/cpu.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n');
    await reply('done');
    await commands.cancel();
  } on Object catch (error) {
    await File('${directory.path}/error.txt').writeAsString('$error\n');
    stderr.writeln(error);
    socket?.writeln('error');
    if (socket != null) await socket.flush();
    exitCode = 1;
  } finally {
    socket?.destroy();
    await server.close();
  }
}
