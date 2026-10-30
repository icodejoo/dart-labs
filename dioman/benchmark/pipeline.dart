import 'pipeline_client.dart';
import 'runner.dart';

/// 新版独立 JIT 基准入口。
Future<void> main() => runDiomanBench(createPipelineBenchClient, 'pipeline');
