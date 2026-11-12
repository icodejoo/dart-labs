import 'dart:math' as math;

import 'lotto_config.dart';

/// 无指定号码时的抽样策略，返回 null 作废本局。
abstract interface class LottoSampler {
  /// 根据 [config] 抽取号码，随机性只来自传入的 [random]。
  LottoDraw? sample(LottoConfig config, math.Random random);
}

/// 每池无放回均匀抽样；相同种子与配置产生相同结果。
final class UniformLottoSampler implements LottoSampler {
  /// 创建无状态抽样器。
  const UniformLottoSampler();

  /// 以部分 Fisher–Yates 抽样，返回按抽出顺序排列的各池号码。
  @override
  LottoDraw sample(LottoConfig config, math.Random random) {
    config.validate();
    return LottoDraw(List.unmodifiable(config.pools.map((pool) {
      final bag = List.generate(pool.max - pool.min + 1, (i) => pool.min + i);
      for (var i = 0; i < pool.count; i++) {
        final j = i + random.nextInt(bag.length - i);
        final value = bag[i];
        bag[i] = bag[j];
        bag[j] = value;
      }
      return List<int>.unmodifiable(bag.take(pool.count));
    })));
  }
}
