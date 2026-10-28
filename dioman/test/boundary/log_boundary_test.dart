// ignore_for_file: avoid_relative_lib_imports
// 边界层：log
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/fixtures.dart';

/// 注册本文件的边界层用例。
void main() {
  test('[DiomanLog.writer][DiomanLogOptions.writer] log 无响应的传输错误仍包含错误类型',
      () async {
    final messages = <String>[];
    final plugin =
        DiomanLog(writer: (message, {error}) => messages.add(message));
    final handler = ErrorInterceptorHandler();
    final future = handlerCompletion(handler)..ignore();
    plugin.onError(
        DioException(
            requestOptions: RequestOptions(path: replayPath),
            type: DioExceptionType.connectionError),
        handler);
    await expectLater(future, throwsA(anything));
    expect(messages.single, contains('connectionError'));
  });
}
