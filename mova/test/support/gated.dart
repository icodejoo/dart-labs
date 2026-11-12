import 'fake_api.dart';

/// 跨替身共享的严格命令日志，列表下标就是全局执行序号。
class CommandLog {
  final List<({int instance, String verb})> entries = [];

  /// 追加一次实际进入命令的记录。
  void record(int instance, String verb) =>
      entries.add((instance: instance, verb: verb));
}

/// 可直接传给真实切换引擎的工厂，保留全部实例供释放与源断言。
class GatedEngineFactory {
  final CommandLog log = CommandLog();
  final List<FakeMovaApi> engines = [];

  /// 创建带共享命令日志的引擎替身。
  FakeMovaApi create() {
    final engine = FakeMovaApi(commandLog: log);
    engines.add(engine);
    return engine;
  }
}
