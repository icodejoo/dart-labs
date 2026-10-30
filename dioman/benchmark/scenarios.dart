/// 六个跨实现共享的基线场景。
enum DiomanBenchScenario { s1, s2, s3, s4, s5, s6 }

/// 并发共享场景每组的逻辑请求数。
const diomanBenchConcurrency = 100;

/// 场景使用的客户端契约；B5/B6 只需替换构造器实现。
abstract interface class DiomanBenchClient {
  /// 执行一次操作；S5 的一次操作是一组一百个同 key 请求。
  Future<void> operation();

  /// 传输发送次数，用于在计时之外核对场景语义。
  int get sends;

  /// 回收插件、传输层及监听资源。
  Future<void> dispose();
}

/// 根据场景构造独立客户端，禁止跨场景共享状态。
typedef DiomanBenchFactory = Future<DiomanBenchClient> Function(
    DiomanBenchScenario scenario);
