import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/lotto.dart';
import '../support/f2_lifecycle_fixtures.dart';
import '../support/lotto_fixtures.dart';

/// 大乐透释放回归。
void main() {
  test('F2 lotto dispose freezes phase result and item callbacks', () {
    final host = F2LifecycleHost<LottoResult>();
    final controller = LottoController()
      ..attach(host)
      ..configure(lottoConfig, lottoLayout());
    controller.play();
    host.clock.advanceFrames(10);
    expect(host.callbacks, greaterThan(0));
    final before = host.callbacks;
    controller.dispose();
    host.clock.advanceFrames(100);
    expect(host.callbacks, before);
    expect(host.clock.isTicking, isFalse);
    host.clock.dispose();
  });
}
