// ignore_for_file: avoid_relative_lib_imports
// 单元层：request_claims
import 'package:dio/dio.dart';
import 'package:dioman/src/request_claims.dart';
import 'package:test/test.dart';
import '../../test/support/fixtures.dart';

/// 注册本文件的单元层用例。
void main() {
  test(
      '[RequestClaims.whenDrained][claimRequest][releaseClaim] claims 已结束后回调立即执行，release 接口完成所有权',
      () {
    final options = RequestOptions(path: replayPath);
    final owner = Object();
    claimRequest(options, owner);
    releaseClaim(options, owner);
    var drained = 0;
    claimsOf(options)!.whenDrained(() => drained++);
    expect(drained, 1);
    expect(claimsOf(options)!.isFinished, isTrue);
  });
}
