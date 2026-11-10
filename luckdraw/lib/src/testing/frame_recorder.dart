import 'package:flutter/foundation.dart';

import '../core/game/frame.dart';

/// 在每次帧通知后读取一个数值，供逐帧对照使用。
final class LuckyFrameRecorder<F extends LuckyFrame> {
  /// 监听 [frameListenable]；[read] 应只读取复用的 [frame]。
  LuckyFrameRecorder(
      Listenable frameListenable, F frame, double Function(F frame) read)
      : _listenable = frameListenable,
        _frame = frame,
        _read = read {
    _listenable.addListener(_record);
  }

  /// 监听源。
  final Listenable _listenable;

  /// 帧对象。
  final F _frame;

  /// 数值读取器。
  final double Function(F frame) _read;

  /// 累计样本。
  final List<double> _values = [];

  /// 样本只读视图。
  List<double> get values => List.unmodifiable(_values);

  /// 记录当前帧。
  void _record() => _values.add(_read(_frame));

  /// 移除监听，保留已采样数值。
  void dispose() => _listenable.removeListener(_record);
}
