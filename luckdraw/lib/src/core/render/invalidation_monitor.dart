import 'package:flutter/foundation.dart';

/// 缓存失效告警的滚动窗口。
const Duration _warningWindow = Duration(seconds: 2);

/// 窗口内触发告警所需的失效次数。
const int _warningThreshold = 8;

/// 实验性（可能调整）：仅在 debug 诊断 config 变化引起的频繁缓存失效。
final class LuckyInvalidationMonitor {
  /// 实验性（可能调整）：标记玩法 [game]；[now] 默认取系统时间，可注入测试时钟。
  ///
  /// 例如 `LuckyInvalidationMonitor('lots').recordInvalidation()`；关闭 assert 后不计数。
  LuckyInvalidationMonitor(String game, {DateTime Function()? now}) {
    assert(() {
      _game = game;
      _now = now ?? DateTime.now;
      _timestamps = [];
      return true;
    }());
  }

  /// 实验性（可能调整）：debug 告警后接收同一中文文本；null 表示不接收。
  ///
  /// 不替代 debugPrint；测试结束后应还原，关闭 assert 后不会调用。
  static ValueChanged<String>? debugOnWarning;

  /// 仅在 assert 内读取的玩法名称。
  late final String _game;

  /// 仅在 assert 内初始化和读取的时间来源。
  late final DateTime Function() _now;

  /// 仅在 assert 内持有滚动窗口内的时间戳。
  late final List<DateTime> _timestamps;

  /// 最近一次告警时间，用于保证任意两秒内至多告警一次。
  DateTime? _lastWarning;

  /// 实验性（可能调整）：记录一次因 config 不相等引起的缓存失效，无返回值。
  ///
  /// 两秒内至少八次时 debugPrint 并调用 [debugOnWarning]；关闭 assert 后无操作。
  void recordInvalidation() {
    assert(() {
      final now = _now();
      _timestamps.removeWhere((time) => now.difference(time) > _warningWindow);
      _timestamps.add(now);
      if (_timestamps.length >= _warningThreshold &&
          (_lastWarning == null ||
              now.difference(_lastWarning!) >= _warningWindow)) {
        _lastWarning = now;
        final message = 'luckdraw [$_game]：config 每次构建都不相等，缓存被反复重建；'
            '常见原因是在 build 里内联创建了 painter/闭包/缓动对象，'
            '请提升为 static final 或稳定引用。';
        debugPrint(message);
        debugOnWarning?.call(message);
      }
      return true;
    }());
  }
}
