import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 实验性（可能调整）：所有 raster 缓存共享的名义 RGBA 字节账本。
final class LuckyRasterBudget {
  /// 只允许通过 [instance] 使用共享账本。
  LuckyRasterBudget._();

  /// 实验性（可能调整）：进程内共享实例，例如 `LuckyRasterBudget.instance.usedBytes`。
  static final LuckyRasterBudget instance = // imports:allow-global 跨缓存共享纹理字节账本
      LuckyRasterBudget._();

  /// 实验性（可能调整）：debug 预占失败时通知请求字节、当前占用和本次上限。
  ///
  /// null 表示不接收；关闭 assert 后不会调用，测试结束后应还原。
  static void Function(int requested, int used, int limit)? debugOnFallback;

  /// 当前已预占的名义字节数。
  int _usedBytes = 0;

  /// 实验性（可能调整）：返回全部缓存已预占的名义字节数。
  int get usedBytes => _usedBytes;

  /// 实验性（可能调整）：尝试占用非负 [bytes]，总量不超过 [limit] 才返回 true。
  ///
  /// 失败不改变账本；成功后调用方须配对 [release]，例如 `tryReserve(400, 1024)`。
  bool tryReserve(int bytes, int limit) {
    assert(bytes >= 0);
    if (_usedBytes + bytes > limit) {
      assert(() {
        debugOnFallback?.call(bytes, _usedBytes, limit);
        return true;
      }());
      return false;
    }
    _usedBytes += bytes;
    return true;
  }

  /// 实验性（可能调整）：退还非负 [bytes]，占用最小为零；无返回值。
  void release(int bytes) {
    assert(bytes >= 0);
    _usedBytes = math.max(0, _usedBytes - bytes);
  }

  /// 实验性（可能调整）：测试隔离时清零账本；须先释放所有存活缓存。
  @visibleForTesting
  void reset() => _usedBytes = 0;
}
