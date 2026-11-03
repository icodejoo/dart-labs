import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// 默认退避不能在应用上限前溢出。
void main() {
  test('[DiomanRetry.defaultDelay] 大序号和超大指数仍是正向有限时长', () {
    final result = DiomanResponse<dynamic>(
        ok: false, status: 500, request: DiomanRequest(RequestOptions()));
    for (final attempt in [46, 100, 1025, 1 << 30]) {
      final delay = DiomanRetry.defaultDelay(attempt, attempt, result);
      expect(delay, greaterThanOrEqualTo(const Duration(seconds: 10)));
      expect(delay.inMicroseconds, lessThanOrEqualTo(0x1fffffffffffff));
    }
  });
}
