// ignore_for_file: avoid_relative_lib_imports
// 组合层：cache_normalize
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';

/// 业务失败信封里的 code。
const _failCode = 1;

/// 非信封 Map（有 code、无 data/message）里的 code 字段值。
const _plainCode = 7;

/// 测试请求路径。
const _path = '/item';

/// 业务失败的 HTTP 200 信封。
Map<String, dynamic> _failure() => {tkCode: _failCode, tkMessage: 'nope'};

/// 业务成功的 HTTP 200 信封。
Map<String, dynamic> _success() => successEnvelope();

/// 装好 key + cache(memo) + normalize 的 Dio；适配器每次都回 [body]。
({Dio dio, RecordingAdapter adapter, DiomanHandle handle}) _setup(
  Map<String, dynamic> body, {
  DiomanCache? cache,
  DiomanNormalize? normalize = const DiomanNormalize(),
  int status = 200,
}) {
  final adapter = RecordingAdapter((o, n) async => jsonBody(body, status));
  final dio = fakeDio(adapter)
    ..options.validateStatus = (s) => s != null && s < 500;
  final handle = Dioman.install(
    dio,
    key: const DiomanKey(),
    cache: cache ?? _cache(),
    normalize: normalize,
  );
  return (dio: dio, adapter: adapter, handle: handle);
}

/// 默认 memo 缓存。
DiomanCache _cache({bool Function(Response<dynamic>)? shouldStore}) =>
    DiomanCache(
      persist: _NoPersist(),
      cachePolicy: DiomanCachePolicy.memo,
      shouldStore: shouldStore,
    );

/// 不会被用到的落盘后端（只测内存层）。
class _NoPersist implements DiomanCachePersist {
  /// read 的测试实现。
  @override
  dynamic read(String key) => null;

  /// write 的测试实现。
  @override
  Future<void> write(String key, Map<String, dynamic> value) async {}

  /// remove 的测试实现。
  @override
  Future<void> remove(String key) async {}

  /// erase 的测试实现。
  @override
  Future<void> erase() async {}
}

/// 对 [path] 连发两次 GET（业务失败的 reject 吞掉），返回适配器累计被打到的次数。
Future<int> _twice(
  Dio dio,
  RecordingAdapter adapter, {
  Options? options,
  String path = _path,
}) async {
  for (var i = 0; i < 2; i++) {
    try {
      await dio.get<dynamic>(path, options: options);
    } on DioException {
      // 业务失败被 normalize 拒绝，属预期。
    }
  }
  return adapter.calls;
}

/// 请求级 cache 覆盖。
Options _cacheOpt(DiomanCacheOptions o) =>
    Options(extra: {DiomanCache.pluginName: o});

/// 请求级 normalize 覆盖。
Options _normOpt(DiomanNormalizeOptions o) =>
    Options(extra: {DiomanNormalize.pluginName: o});

/// 注册本文件的组合层用例。
void main() {
  group('装了 normalize：HTTP 200 + 业务失败不入缓存', () {
    test(
        '[DiomanCache.new(shouldStore) × DiomanNormalize.isSuccess] 业务失败：两次都打到服务端',
        () async {
      final s = _setup(_failure());
      expect(await _twice(s.dio, s.adapter), 2);
    });

    test(
        '[DiomanCache.new(shouldStore) × DiomanNormalize.isSuccess] 业务成功：入缓存，命中后仍经 normalize 拆包',
        () async {
      final s = _setup(_success());
      expect(await _twice(s.dio, s.adapter), 1);
      final hit = await s.dio.get<dynamic>(_path);
      expect(hit.data, {tkV: 1}, reason: '缓存存的是原始信封，命中再经 normalize');
      expect(hit.statusMessage, 'OK (cached)');
    });

    test(
        '[DiomanCache.new(shouldStore) × DiomanNormalizeOptions.isSuccess] 请求级 isSuccess 把失败码判成功：照常缓存',
        () async {
      final s = _setup(_failure());
      final n = await _twice(s.dio, s.adapter,
          options: _normOpt(
              DiomanNormalizeOptions(isSuccess: (c) => c == _failCode)));
      expect(n, 1);
    });

    test(
        '[DiomanCache.new(shouldStore) × DiomanNormalize.isSuccess] 插件级 isSuccess 同样决定是否入缓存',
        () async {
      final s = _setup(_failure(),
          normalize: DiomanNormalize(isSuccess: (c) => c == _failCode));
      expect(await _twice(s.dio, s.adapter), 1);
    });

    test(
        '[DiomanCache.new(shouldStore) × DiomanNormalizeOptions.codeKey] 请求级 codeKey 指向成功字段：照常缓存',
        () async {
      final s = _setup({tkCode: _failCode, 'ret': 0, tkData: 1});
      final n = await _twice(s.dio, s.adapter,
          options: _normOpt(const DiomanNormalizeOptions(codeKey: 'ret')));
      expect(n, 1);
    });

    test(
        '[DiomanCache.new(shouldStore) × DiomanNormalizeOptions.enabled] normalize 请求级关闭：业务失败照常缓存',
        () async {
      final s = _setup(_failure());
      final n = await _twice(s.dio, s.adapter,
          options: _normOpt(const DiomanNormalizeOptions(enabled: false)));
      expect(n, 1);
    });

    test(
        '[DiomanCache.new(shouldStore) × DiomanNormalize.enabled] normalize 插件级关闭：业务失败照常缓存',
        () async {
      final s =
          _setup(_failure(), normalize: const DiomanNormalize(enabled: false));
      expect(await _twice(s.dio, s.adapter), 1);
    });

    test(
        '[DiomanCache.new(shouldStore) × DiomanNormalize.shouldNormalize] shouldNormalize 返回 false：照常缓存',
        () async {
      final s = _setup(_failure(),
          normalize: DiomanNormalize(shouldNormalize: (o, r) => false));
      expect(await _twice(s.dio, s.adapter), 1);
    });

    test(
        '[DiomanCache.new(shouldStore) × DiomanNormalizeOptions.shouldNormalize] 请求级 shouldNormalize 返回 false：照常缓存',
        () async {
      final s = _setup(_failure());
      final n = await _twice(s.dio, s.adapter,
          options: _normOpt(
              DiomanNormalizeOptions(shouldNormalize: (o, r) => false)));
      expect(n, 1);
    });

    test(
        '[DiomanCache.new(shouldStore) × DiomanNormalize.codeKey] 非信封 Map（只有 code）透传：照常缓存',
        () async {
      final s = _setup({tkCode: _plainCode, 'name': 'x'});
      expect(await _twice(s.dio, s.adapter), 1);
    });

    test(
        '[DiomanCache.new(shouldStore) × DiomanNormalize.shouldNormalize] 非 Map 响应透传：照常缓存',
        () async {
      final adapter = RecordingAdapter(
          (o, n) async => ResponseBody.fromString('[1,2]', 200, headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              }));
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          cache: _cache(),
          normalize: const DiomanNormalize());
      expect(await _twice(dio, adapter), 1);
    });
  });

  group('shouldStore 优先级', () {
    test(
        '[DiomanCache.new(shouldStore)] 插件级显式 shouldStore 覆盖自动接线：业务失败也按用户意愿缓存',
        () async {
      final s = _setup(_failure(), cache: _cache(shouldStore: (r) => true));
      expect(await _twice(s.dio, s.adapter), 1);
    });

    test('[DiomanCache.new(shouldStore)] 插件级 shouldStore 返回 false：业务成功也不缓存', () async {
      final s = _setup(_success(), cache: _cache(shouldStore: (r) => false));
      expect(await _twice(s.dio, s.adapter), 2);
    });

    test('[DiomanCacheOptions.shouldStore] 请求级覆盖插件级（false → true）', () async {
      final s = _setup(_success(), cache: _cache(shouldStore: (r) => false));
      final n = await _twice(s.dio, s.adapter,
          options: _cacheOpt(DiomanCacheOptions(shouldStore: (r) => true)));
      expect(n, 1);
    });

    test('[DiomanCacheOptions.shouldStore] 请求级覆盖插件级（true → false）', () async {
      final s = _setup(_success(), cache: _cache(shouldStore: (r) => true));
      final n = await _twice(s.dio, s.adapter,
          options: _cacheOpt(DiomanCacheOptions(shouldStore: (r) => false)));
      expect(n, 2);
    });

    test('[DiomanCacheOptions.shouldStore] 请求级覆盖自动接线：业务失败按请求级判定缓存', () async {
      final s = _setup(_failure());
      final n = await _twice(s.dio, s.adapter,
          options: _cacheOpt(DiomanCacheOptions(shouldStore: (r) => true)));
      expect(n, 1);
    });

    test(
        '[DiomanCache.new(shouldStore)] 2xx 检查先于 shouldStore：非 2xx 响应即便 shouldStore 返回 true 也不缓存',
        () async {
      final s = _setup({tkCode: 0},
          cache: _cache(shouldStore: (r) => true), status: 404);
      expect(await _twice(s.dio, s.adapter), 2);
    });

    test('[DiomanCache.new(shouldStore)] shouldStore 拿到的是规范化之前的原始响应', () async {
      Object? seen;
      final s = _setup(_success(), cache: _cache(shouldStore: (r) {
        seen = r.data;
        return true;
      }));
      await s.dio.get<dynamic>(_path);
      expect(seen, _success());
    });
  });

  group('没装 normalize / 动态插拔', () {
    test('[DiomanCache.new(shouldStore)] 没装 normalize：2xx 即存（行为不变）', () async {
      final s = _setup(_failure(), normalize: null);
      expect(await _twice(s.dio, s.adapter), 1);
    });

    test(
        '[DiomanHandle.append][DiomanHandle.remove] 动态 append / remove normalize 后接线跟着变',
        () async {
      final s = _setup(_failure(), normalize: null);
      // 阶段 1：没有 normalize，业务失败入缓存。
      expect(await _twice(s.dio, s.adapter), 1);

      // 阶段 2：装上 normalize，换个路径避开已有缓存，业务失败不再入缓存。
      s.handle.append(const DiomanNormalize());
      s.adapter.calls = 0;
      expect(await _twice(s.dio, s.adapter, path: '/two'), 2);

      // 阶段 3：移除 normalize，接线撤销，新路径上 2xx 即存。
      s.handle.remove<DiomanNormalize>();
      s.adapter.calls = 0;
      expect(await _twice(s.dio, s.adapter, path: '/three'), 1);
    });

    test('[DiomanHandle.insertAfter] 动态 insert normalize 到 cache 之后即生效',
        () async {
      final s = _setup(_failure(), normalize: null);
      s.handle.insertAfter(
          s.handle.plugin<DiomanCache>()!, const DiomanNormalize());
      expect(await _twice(s.dio, s.adapter), 2);
    });

    test('[DiomanHandle.dispose] dispose 撤销接线：cache 不再持有 normalize 的判定', () async {
      final s = _setup(_failure());
      final cache = s.handle.plugin<DiomanCache>()!;
      s.handle.dispose();
      s.dio.interceptors
        ..add(const DiomanKey())
        ..add(cache);
      expect(await _twice(s.dio, s.adapter), 1);
    });
  });
}
