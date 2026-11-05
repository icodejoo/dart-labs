import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/platform/ports.dart';
import 'package:mova/src/platform_impl/wiring.dart';

import '../support/fake_kernel.dart';

/// 可门控进入结果并向多个引擎广播系统状态的画中画端口。
class _Pip implements MovaPipPort, MovaPipObservable {
  /// 系统广播流。
  final controller = StreamController<bool>.broadcast(sync: true);

  /// 当前进入请求的结果。
  Completer<bool> result = Completer<bool>();

  /// 查询测试端口支持情况。
  @override
  Future<bool> isSupported() async => true;

  /// 等待测试释放进入结果。
  @override
  Future<bool> enter({int? width, int? height}) =>
      result.future;

  /// 订阅系统状态广播。
  @override
  Stream<bool> get changes => controller.stream;
}

void main() {
  test('B13 PiP 在途广播只影响请求引擎，退出后忽略后续广播', () async {
    final port = _Pip();
    final a = createMovaEngine(kernel: FakeKernel(), pip: port);
    final b = createMovaEngine(kernel: FakeKernel(), pip: port);
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
      await port.controller.close();
    });
    final entered = a.enterPip();
    port.controller.add(true);
    expect(a.state.pip, isTrue);
    expect(b.state.pip, isFalse);
    port.result.complete(true);
    expect(await entered, isTrue);
    port.controller.add(false);
    expect(a.state.pip, isFalse);
    port.controller.add(true);
    expect(a.state.pip, isFalse);
    expect(b.state.pip, isFalse);
  });

  test('B13 进入失败或抛错撤销广播资格，之后仍可重试', () async {
    final port = _Pip();
    final engine = createMovaEngine(kernel: FakeKernel(), pip: port);
    addTearDown(() async {
      await engine.dispose();
      await port.controller.close();
    });
    var entered = engine.enterPip();
    port.result.complete(false);
    expect(await entered, isFalse);
    port.controller.add(true);
    expect(engine.state.pip, isFalse);
    port.result = Completer<bool>();
    entered = engine.enterPip();
    final assertion = expectLater(entered, throwsStateError);
    port.result.completeError(StateError('failed'));
    await assertion;
    port.controller.add(true);
    expect(engine.state.pip, isFalse);
    port.result = Completer<bool>();
    entered = engine.enterPip();
    port.result.complete(true);
    expect(await entered, isTrue);
    port.controller.add(false);
    expect(engine.state.pip, isFalse);
  });
}

