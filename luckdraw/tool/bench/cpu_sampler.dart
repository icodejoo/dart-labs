import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pending_metrics.dart';

/// 单个 adb 采样超时，失败即保留原始数据并报错。
const Duration _adbTimeout = Duration(seconds: 10);

/// 对指定设备执行一次命令；不带任何后台 adb 看护轮询。
Future<String> _adb(String serial, List<String> arguments) async {
  final process = await Process.start('adb', ['-s', serial, ...arguments]);
  final output = process.stdout.transform(utf8.decoder).join();
  final error = process.stderr.transform(utf8.decoder).join();
  try {
    final code = await process.exitCode.timeout(_adbTimeout);
    final stdoutText = await output;
    final stderrText = await error;
    if (code != 0) throw StateError('adb ${arguments.join(' ')}: $stderrText');
    return stdoutText;
  } on TimeoutException {
    process.kill();
    await process.exitCode;
    throw TimeoutException('CPU 采样 adb 超时');
  }
}

/// 顺序采集一次进程/线程快照，保留原文、时间与实际采集跨度。
Future<Map<String, Object?>> _sample(
    String serial, String packageName, Directory directory, String label,
    {int? expectedPid, Stopwatch? window}) async {
  final start = DateTime.now().toUtc();
  final offset = window?.elapsedMicroseconds;
  final cpu = await _adb(serial, ['shell', 'dumpsys', 'cpuinfo']);
  await File('${directory.path}/$label.cpuinfo.txt').writeAsString(cpu);
  final process = parsePendingCpuInfo(cpu, packageName);
  if (expectedPid != null && process.pid != expectedPid) {
    throw StateError('CPU 窗口内进程重启: $expectedPid -> ${process.pid}');
  }
  final top = await _adb(
      serial, ['shell', 'top', '-b', '-n', '1', '-H', '-p', '${process.pid}']);
  await File('${directory.path}/$label.top.txt').writeAsString(top);
  final threads = parsePendingTop(top);
  return {
    'label': label,
    'recorded_at': start.toIso8601String(),
    'offset_micros': offset,
    'end_offset_micros': window?.elapsedMicroseconds,
    'duration_micros': DateTime.now().toUtc().difference(start).inMicroseconds,
    'pid': process.pid,
    'process_cpu_percent': process.percent,
    'threads': [
      for (final thread in threads)
        {
          'tid': thread.tid,
          'name': thread.name,
          'role': thread.role,
          'cpu_percent': thread.percent,
        },
    ],
  };
}

/// 在窗口第0/1/2/3/4秒各采一次，采样挤出五秒窗口直接失败。
Future<List<Map<String, Object?>>> _window(String serial, String packageName,
    Directory directory, int pid, Stopwatch watch) async {
  final result = <Map<String, Object?>>[];
  for (var index = 0; index < kPendingCpuSamples; index++) {
    final remaining = Duration(seconds: index) - watch.elapsed;
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
    if (watch.elapsedMilliseconds >= (index + 1) * 1000) {
      throw StateError('CPU 采样错过第${index + 1}秒，不接受越窗数据');
    }
    result.add(await _sample(serial, packageName, directory, 'window_$index',
        expectedPid: pid, window: watch));
    if (watch.elapsedMilliseconds > (index + 1) * 1000) {
      throw StateError('CPU 单次采样超过一秒，无法保证五次都在窗口内');
    }
  }
  return result;
}

/// 运行一次有界 CPU 会话；设备 before/start/end 握手隔开前后与窗口采样。
Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln('用法: dart run cpu_sampler.dart <serial> <package> <output>');
    exitCode = 64;
    return;
  }
  final directory = Directory(args[2])..createSync(recursive: true);
  ServerSocket? server;
  Socket? socket;
  try {
    server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, kPendingCpuPort);
    await File('${directory.path}/server.ready').writeAsString('ready\n');
    socket = await server.first.timeout(const Duration(minutes: 4));
    final commands = StreamIterator(socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter()));

    /// 协议失配显式失败，不能用固定延迟猜测测量窗口。
    Future<void> expectCommand(String expected) async {
      if (!await commands.moveNext().timeout(const Duration(seconds: 30)) ||
          commands.current != expected) {
        throw StateError('CPU 协议期待 $expected');
      }
    }

    await expectCommand('before');
    final before = await _sample(args[0], args[1], directory, 'before');
    socket.writeln('ready');
    await socket.flush();
    await expectCommand('start');
    final watch = Stopwatch()..start();
    socket.writeln('started');
    await socket.flush();
    // 提前挂接错误处理，避免设备还在等待窗口结束时产生未处理异步错误。
    Object? samplingError;
    final sampling =
        _window(args[0], args[1], directory, before['pid']! as int, watch)
            .catchError((Object error) {
      samplingError = error;
      return <Map<String, Object?>>[];
    });
    await expectCommand('end');
    final elapsed = watch.elapsedMicroseconds;
    final samples = await sampling;
    if (samplingError != null) throw StateError('$samplingError');
    if (elapsed < Duration.microsecondsPerSecond * kPendingCpuSamples) {
      throw StateError('CPU 设备窗口不足五秒');
    }
    final after = await _sample(args[0], args[1], directory, 'after',
        expectedPid: before['pid']! as int);
    final report = <String, Object?>{
      'package': args[1],
      'window_micros': elapsed,
      'before': before,
      'samples': samples,
      'after': after,
      'note': 'cpuinfo/top 原生统计窗口见原文；非 FrameTiming 推算，无批准 CPU 预算',
    };
    validatePendingCpuWindow(report);
    await File('${directory.path}/cpu.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n');
    socket.writeln('done');
    await socket.flush();
    await commands.cancel();
  } on Object catch (error) {
    await File('${directory.path}/error.txt').writeAsString('$error\n');
    stderr.writeln(error);
    socket?.writeln('error');
    if (socket != null) await socket.flush();
    exitCode = 1;
  } finally {
    socket?.destroy();
    await server?.close();
  }
}
