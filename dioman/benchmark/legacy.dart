import 'legacy_client.dart';
import 'runner.dart';

/// 在独立 JIT 进程运行旧实现六场景。
Future<void> main() =>
    runDiomanBench(createLegacyBenchClient, 'legacy-a6a8d18');
