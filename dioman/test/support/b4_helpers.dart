export 'b4_constants.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';

/// B4 请求路径。
const b4Path = '/b4';

/// B4 路由。
const b4Route = 'GET:$b4Path';

/// B4 假时间单位。
const b4Tick = Duration(seconds: 1);

/// B4 共用请求方法。
const b4Get = 'GET';

/// B4 共用显式键。
const b4Key = 'b4-key';

/// B4 请求选项，独立控制四个 source 插件。
DiomanCall b4Call(
        {Object? share,
        Object? cache,
        Object? mock,
        Object? offline,
        Object? key = b4Key}) =>
    DiomanCall(key: key, options: {
      DiomanShare.option: share,
      DiomanCache.option: cache,
      DiomanMock.option: mock,
      DiomanOffline.option: offline,
    });

/// 内存持久化夹具，可阻塞读写并注入异常。
class B4Persist implements DiomanCachePersist {
  /// 原始落盘条目。
  final values = <String, dynamic>{};

  /// 读取闸门。
  Completer<void>? readGate;

  /// 写入闸门。
  Completer<void>? writeGate;

  /// 删除闸门，用于取消过期清理。
  Completer<void>? removeGate;

  /// 第一笔删除开始信号。
  final removeStarted = Completer<void>();

  /// 捕获读取时的快照，复现慢旧读取。
  bool snapshot = false;

  /// 可注入的操作异常。
  Object? error;

  /// 落盘次数。
  int writes = 0;

  /// 第一笔真实落盘开始信号，测试不猜测微任务轮数。
  final writeStarted = Completer<void>();

  /// 获取快照后可延迟返回。
  @override
  Future<dynamic> read(String key) async {
    final value = values[key];
    await readGate?.future;
    if (error != null) throw error!;
    return snapshot ? value : values[key];
  }

  /// 可阻塞写入。
  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    writes++;
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeGate?.future;
    if (error != null) throw error!;
    values[key] = value;
  }

  /// 删除条目。
  @override
  Future<void> remove(String key) async {
    if (!removeStarted.isCompleted) removeStarted.complete();
    await removeGate?.future;
    if (error != null) throw error!;
    values.remove(key);
  }

  /// 清空后端。
  @override
  Future<void> erase() async {
    if (error != null) throw error!;
    values.clear();
  }
}

/// 让 Dio 的异步转换与适配器完成当前事件轮，不推进真实计时。
Future<void> b4Turn() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>(() {});
  }
}
