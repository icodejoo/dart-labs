import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/interceptor/interceptor.dart';
import 'package:videoman/src/core/model/source.dart';

class _DenyOpen extends VmInterceptor {
  @override
  Future<bool> beforeOpen(VmSource s) async => false;
}

class _ClampSeek extends VmInterceptor {
  @override
  Future<Duration?> beforeSeek(Duration t) async =>
      t > const Duration(seconds: 10) ? const Duration(seconds: 10) : t;
}

class _CancelSeek extends VmInterceptor {
  @override
  Future<Duration?> beforeSeek(Duration t) async => null;
}

/// Test-only interceptor that records whether it was invoked, via [onReached].
///
/// Used to prove that a preceding interceptor returning `null` from
/// `beforeSeek` actually stops the chain, rather than merely asserting an
/// untouched flag.
///
/// 仅用于测试的拦截器，通过 [onReached] 记录自身是否被调用过。
///
/// 用于证明前一个拦截器的 `beforeSeek` 返回 `null` 确实会终止链条的继续执行，
/// 而不是仅仅断言一个从未被改动过的标志位。
class _ReachedSeek extends VmInterceptor {
  /// Creates the interceptor, invoking [onReached] if [beforeSeek] runs.
  ///
  /// 创建该拦截器；若 [beforeSeek] 被执行，则调用 [onReached]。
  _ReachedSeek(this.onReached);

  /// Callback invoked when [beforeSeek] actually runs.
  ///
  /// [beforeSeek] 实际被执行时调用的回调。
  final void Function() onReached;

  @override
  Future<Duration?> beforeSeek(Duration t) async {
    onReached();
    return t;
  }
}

void main() {
  test('empty chain allows everything', () async {
    final c = VmInterceptorChain(const []);
    expect(await c.beforeOpen(const VmSource('u')), isTrue);
    expect(await c.beforePlay(), isTrue);
    expect(await c.beforeSeek(const Duration(seconds: 3)), const Duration(seconds: 3));
  });

  test('a denying interceptor short-circuits beforeOpen', () async {
    final c = VmInterceptorChain([_DenyOpen()]);
    expect(await c.beforeOpen(const VmSource('u')), isFalse);
  });

  test('beforeSeek rewrites are threaded through the chain', () async {
    final c = VmInterceptorChain([_ClampSeek()]);
    expect(await c.beforeSeek(const Duration(seconds: 30)), const Duration(seconds: 10));
  });

  test('a null from beforeSeek cancels and stops the chain', () async {
    var reached = false;
    final c = VmInterceptorChain([
      _CancelSeek(),
      _ReachedSeek(() => reached = true),
    ]);
    expect(await c.beforeSeek(const Duration(seconds: 30)), isNull);
    expect(reached, isFalse);
  });
}
