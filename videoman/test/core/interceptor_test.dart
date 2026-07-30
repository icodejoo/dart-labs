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
    final c = VmInterceptorChain([_CancelSeek(), _ClampSeek()]);
    expect(await c.beforeSeek(const Duration(seconds: 30)), isNull);
    expect(reached, isFalse);
  });
}
