import 'dart:developer' as developer;

/// 编译期控制 Timeline 打点，默认关闭，可用 dart-define 开启。
const bool _traceEnabled = bool.fromEnvironment('LUCKDRAW_TIMELINE');

/// 单次 TextPainter.layout 事件名；arguments.layouts 记录调用数。
const String kLuckyTextPainterLayoutTrace = 'luckdraw.text.painter.layout';

/// 开始名为 [name] 的同步性能片段；默认构建不打点。
@pragma('vm:prefer-inline')
void luckyTraceStart(String name, {int layouts = 0}) {
  if (_traceEnabled) {
    developer.Timeline.startSync(name, // coverage:ignore-line COV-01
        arguments: {'layouts': layouts}); // coverage:ignore-line COV-02
  }
}

/// 结束最近一次性能片段；默认构建不打点。
@pragma('vm:prefer-inline')
void luckyTraceEnd() {
  if (_traceEnabled) {
    developer.Timeline.finishSync(); // coverage:ignore-line COV-01
  }
}
