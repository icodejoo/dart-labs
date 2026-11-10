import 'package:flutter/foundation.dart';

/// 一局结果；取消结果的 index/prize 均为空。
///
/// 例如 `LuckyResult<String>(index: 0, prize: '一等奖')`。
@immutable
class LuckyResult<P> {
  /// 创建结果；[cancelled] 为 true 时须使用空的 index 和 prize。
  const LuckyResult({this.index, this.prize, this.cancelled = false})
      : assert(!cancelled || index == null && prize == null);

  /// 创建没有奖品和下标的取消结果。
  const LuckyResult.cancelled()
      : index = null,
        prize = null,
        cancelled = true;

  /// 命中的奖品下标，取消时为空。
  final int? index;

  /// 命中的奖品，取消时为空。
  final P? prize;

  /// 是否作废本局。
  final bool cancelled;
}
