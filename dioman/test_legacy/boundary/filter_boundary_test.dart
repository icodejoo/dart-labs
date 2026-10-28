// ignore_for_file: avoid_relative_lib_imports
// 边界层：filter
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/filter_plugin.dart';
import 'package:test/test.dart';
import '../../test/accept/lib/literals.dart';
import '../../test/support/fixtures.dart';

/// 注册本文件的边界层用例。
void main() {
  test('[DiomanFilter.onRequest] filter copies immutable body', () {
    const body = {tkEmpty6: tkEmpty, keepField: 1};
    final options = RequestOptions(path: fixturePath, data: body);
    const DiomanFilter().onRequest(options, RecordingRequestHandler());
    expect(options.data, {keepField: 1});
    expect(body.length, 2);
  });
}
