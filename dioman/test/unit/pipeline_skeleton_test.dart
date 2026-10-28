import 'package:dioman/dioman.dart' show Dioman;
import 'package:test/test.dart';

/// 保留默认测试入口，后续内核批次替换为真实内核测试。
void main() {
  test('[Dioman]', () {
    expect(Dioman, isNotNull);
  });
}
