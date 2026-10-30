import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'scenarios.dart';

/// 每场景预热时间。
const _warmup = Duration(milliseconds: 500);

/// 每场景正式测量时间下限。
const _measurement = Duration(seconds: 2);

/// 根据传输调用数验证命中、未命中、共享，避免测到空场景。
Future<void> _verify(
    DiomanBenchScenario scenario, DiomanBenchClient client) async {
  await client.operation();
  final before = client.sends;
  await client.operation();
  final expected = scenario == DiomanBenchScenario.s4 ? 0 : 1;
  if (client.sends - before != expected) {
    throw StateError(
        '$scenario sends=${client.sends - before}, expected=$expected');
  }
}

/// 使用单调时钟采样，每个样本是一整次 operation 的端到端延迟。
Future<Map<String, Object>> _measure(
    DiomanBenchScenario scenario, DiomanBenchClient client) async {
  await _verify(scenario, client);
  final warmup = Stopwatch()..start();
  while (warmup.elapsed < _warmup) {
    await client.operation();
  }
  final latencies = <int>[];
  final sendsBefore = client.sends;
  final total = Stopwatch()..start();
  while (total.elapsed < _measurement) {
    final start = total.elapsedTicks;
    await client.operation();
    latencies.add(total.elapsedTicks - start);
  }
  total.stop();
  final elapsedTicks = total.elapsedTicks;
  final sum = latencies.fold<int>(0, (sum, ticks) => sum + ticks);
  latencies.sort();
  final microsPerTick = Duration.microsecondsPerSecond / total.frequency;
  return {
    'scenario': scenario.name.toUpperCase(),
    'operations': latencies.length,
    'requestsPerOperation':
        scenario == DiomanBenchScenario.s5 ? diomanBenchConcurrency : 1,
    'elapsedSeconds': elapsedTicks / total.frequency,
    'opsPerSecond': latencies.length * total.frequency / elapsedTicks,
    'meanMicros': sum / latencies.length * microsPerTick,
    'p99Micros': latencies[math.max(0, (latencies.length * .99).ceil() - 1)] *
        microsPerTick,
    'sends': client.sends - sendsBefore,
  };
}

/// 运行一轮；外部每次 dart run 启动新进程，不在进程内重复三轮。
Future<void> runDiomanBench(
    DiomanBenchFactory factory, String implementation) async {
  final results = <Map<String, Object>>[];
  for (final scenario in DiomanBenchScenario.values) {
    final client = await factory(scenario);
    try {
      results.add(await _measure(scenario, client));
    } finally {
      await client.dispose();
    }
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'implementation': implementation,
    'runtime': Platform.version,
    'os': Platform.operatingSystemVersion,
    'processors': Platform.numberOfProcessors,
    'mode': 'JIT (dart run)',
    'warmupMillis': _warmup.inMilliseconds,
    'measurementMillis': _measurement.inMilliseconds,
    'results': results,
  }));
}
