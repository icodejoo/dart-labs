import 'dart:async';
import 'package:layerman/layerman.dart';

/// 保留旧 widget 测试的手动 now 与 fake async Timer 语义。
class ManualNowClock extends OverlayClock {
  /// 从回调读取当前时间，计时器交由当前 Zone 驱动。
  const ManualNowClock(this.readNow);

  /// 测试维护的时间来源。
  final DateTime Function() readNow;

  @override
  DateTime now() => readNow();

  @override
  Timer createTimer(Duration duration, void Function() callback) =>
      Timer(duration, callback);
}
