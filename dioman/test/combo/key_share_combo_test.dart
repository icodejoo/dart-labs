// ignore_for_file: avoid_relative_lib_imports
// 组合层：key_share
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';

/// 注册本文件的组合层用例。
void main() {
  group(tkKeyNamespace, () {
    test(
        '[DiomanKey.namespace × DiomanShare.onRequest] account switch does not join another accounts in-flight share',
        () async {
      var account = accountA;
      final enteredA = Completer<void>();
      final enteredB = Completer<void>();
      final gateA = Completer<void>();
      final gateB = Completer<void>();
      final dio = Dio();
      addTearDown(() {
        if (!gateA.isCompleted) gateA.complete();
        if (!gateB.isCompleted) gateB.complete();
        dio.close();
      });
      dio.interceptors.addAll([
        DiomanKey(namespace: () => account),
        DiomanShare(),
        InterceptorsWrapper(onRequest: (options, handler) async {
          final owner = account;
          (owner == accountA ? enteredA : enteredB).complete();
          await (owner == accountA ? gateA : gateB).future;
          handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: owner),
              true);
        }),
      ]);
      final first = dio.get<String>(fixturePath);
      await enteredA.future.timeout(namespaceTimeout);
      account = accountB;
      final second = dio.get<String>(fixturePath);
      await enteredB.future.timeout(namespaceTimeout);
      gateB.complete();
      expect((await second.timeout(namespaceTimeout)).data, accountB);
      gateA.complete();
      expect((await first.timeout(namespaceTimeout)).data, accountA);
    });
  });
}
