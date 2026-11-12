import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';
import '../support/fake_network.dart';

/// 测试共用的配置值。
const _childUrl = 'https://child.example';

/// 测试共用的配置值。
const _sharedUrl = 'https://shared.example';

/// 测试共用的配置值。
const _header = 'parent';

/// 测试共用的配置值。
const _value = 'value';

/// 验证扩展客户端的引擎复制与共享边界。
void main() {
  test(
      '[Dioman.extend(dio)][Dioman.extend(options)] 直接保留显式引擎的拦截器 adapter transformer',
      () async {
    final parent = testClient();
    final network = FakeNetwork();
    var intercepted = 0;
    final engine = Dio()..httpClientAdapter = network;
    engine.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      intercepted++;
      handler.next(request);
    }));
    final transformer = engine.transformer;
    final child =
        parent.extend(dio: engine, options: BaseOptions(baseUrl: _childUrl));
    addTearDown(child.dispose);
    expect(identical(child.dio, engine), isTrue);
    expect(identical(child.dio.httpClientAdapter, network), isTrue);
    expect(identical(child.dio.transformer, transformer), isTrue);
    expect((await child.send<Object?>('GET', '/engine')).ok, isTrue);
    expect(intercepted, 1);
    expect(engine.options.baseUrl, _childUrl);
    final shared = parent.extend(
        dio: parent.dio, options: BaseOptions(baseUrl: _sharedUrl));
    addTearDown(shared.dispose);
    expect(parent.dio.options.baseUrl, _sharedUrl);
  });
  test('[Dioman.extend][Dioman.extend(plugins)] 默认只复制 BaseOptions，不复制引擎扩展', () {
    final parent = testClient();
    final adapter = parent.dio.httpClientAdapter;
    parent.dio.interceptors.add(InterceptorsWrapper());
    final transformer = parent.dio.transformer;
    parent.dio.options.headers[_header] = _value;
    final child = parent.extend(plugins: []);
    addTearDown(child.dispose);
    expect(child.dio.httpClientAdapter, isNot(same(adapter)));
    expect(child.dio.transformer, isNot(same(transformer)));
    expect(child.dio.interceptors.length, parent.dio.interceptors.length - 1);
    child.dio.options.headers[_header] = 'child';
    expect(parent.dio.options.headers[_header], _value);
  });
}
