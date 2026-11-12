import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/luckdraw.dart';

/// 用类型参数构造运行期取消结果，覆盖真实构造路径。
LuckyResult<P> _cancel<P>() => LuckyResult<P>.cancelled();

/// 验证结果字段与取消不变量。
void main() {
  group('LuckyResult', () {
    test(
        'primary constructor cancellation requires both index and prize to be null',
        () {
      final cancelled = bool.parse('true');
      final result = LuckyResult<String>(cancelled: cancelled);
      expect(result.cancelled, isTrue);
      expect(result.index, isNull);
      expect(result.prize, isNull);
      expect(() => LuckyResult<String>(prize: '奖品', cancelled: cancelled),
          throwsAssertionError);
    });
    test('keeps the selected prize and cancellation has no index or prize', () {
      final result = LuckyResult<String>(index: int.parse('1'), prize: '奖品');
      expect(result.index, 1);
      expect(result.prize, '奖品');
      expect(result.cancelled, isFalse);
      final cancelled = _cancel<String>();
      expect(cancelled.index, isNull);
      expect(cancelled.prize, isNull);
      expect(cancelled.cancelled, isTrue);
      expect(() => LuckyResult<String>(index: 0, cancelled: true),
          throwsAssertionError);
    });
  });
}
