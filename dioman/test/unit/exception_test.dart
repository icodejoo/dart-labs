// ignore_for_file: avoid_relative_lib_imports
// 单元层：exception
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';

/// 注册本文件的单元层用例。
void main() {
  group(tkDiomanNormalize, () {
    test(
        '[DiomanException.toString] DiomanException.toString() includes the code and message',
        () {
      const e = DiomanException(code: 1, message: tkBoom);
      expect(e.toString(), 'DiomanException(code: 1, message: boom)');
    });
  });

  test(
      '[DiomanExtraKey.toString][DiomanOfflineException.toString][DiomanBreakerOpenException.toString][DiomanCancel.track][DiomanCancel.untrack][DiomanCancel.cancelAll] 异常说明、extra 键说明与手动取消追踪',
      () {
    expect(
        DiomanExtraKeys.builtIn.first.toString(), contains(tkDiomanExtraKey));
    expect(const DiomanOfflineException(DiomanOfflineReason.timeout).toString(),
        contains(tkTimeout));
    expect(const DiomanBreakerOpenException(bucketKey: replayPath).toString(),
        contains(replayPath));
    final cancel = DiomanCancel();
    final first = CancelToken();
    final second = CancelToken();
    cancel.track(first);
    cancel.track(second);
    cancel.untrack(first);
    expect(cancel.cancelAll(), 1);
    expect(first.isCancelled, isFalse);
    expect(second.isCancelled, isTrue);
    cancel.dispose();
  });
}
