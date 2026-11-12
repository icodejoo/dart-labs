import '../support/response_contract.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';


/// 验证对应主题的行为与边界。
void main() {
  test('[DiomanNotify.defaultStringify] B8 internal 默认不通知', () {
    final ctx = testContext();
    final r = scriptedResult(ctx, diomanTestInternal);
    expect(DiomanNotify.defaultStringify(r, ctx), isEmpty);
  });
}
