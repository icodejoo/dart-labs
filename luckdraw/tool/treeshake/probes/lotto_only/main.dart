import 'package:flutter/widgets.dart';
import 'package:luckdraw/lotto.dart';

/// 仅使用 lotto 入口，保留实际 Widget 与配置。
void main() {
  runApp(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: LuckyLotto(config: LottoConfig.superLotto()))));
}
