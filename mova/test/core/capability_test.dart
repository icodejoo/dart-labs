import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../support/fake_api.dart';

/// 测试自定义能力，不要求 IMovaApi 增加方法。
abstract interface class _Marker { String get tag; }

/// 具有宿主自定义能力的底层播放器。
class _MarkedApi extends FakeMovaApi implements _Marker {
  _MarkedApi(this.tag) : super(options: const MovaOpts(cutover: MovaCutoverOpts(enabled: true)));
  @override
  final String tag;
}

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) { await Future<void>.delayed(Duration.zero); }
}

void main() {
  test('C10 direct capability keeps identity without issuing commands', () async {
    final api = _MarkedApi('direct');
    expect(movaCapabilityOf<_Marker>(api), same(api));
    expect(api.calls, isEmpty);
    await api.dispose();
  });
  test('C10 unsupported capability is null and ordinary API remains discoverable', () async {
    final api = FakeMovaApi();
    expect(movaCapabilityOf<_Marker>(api), isNull);
    expect(movaCapabilityOf<IMovaApi>(api), same(api));
    await api.dispose();
  });
  test('C10 nested proxies expose active capability and retain their own capability', () async {
    final active = _MarkedApi('nested');
    final inner = MovaCutover(movaFactory: () => active);
    final outer = MovaCutover(movaFactory: () => inner);
    expect(movaCapabilityOf<_Marker>(outer), same(active));
    expect(movaCapabilityOf<IMovaCutover>(outer), same(outer));
    expect(active.calls, isEmpty);
    await outer.dispose();
  });
  test('C10 discovery follows committed active player and ignores shadow', () async {
    final made = <_MarkedApi>[];
    final proxy = MovaCutover(movaFactory: () {
      final api = _MarkedApi('${made.length}');
      made.add(api);
      return api;
    });
    addTearDown(proxy.dispose);
    await proxy.prepare(const MovaSource('https://a/next'),
      plan: const MovaWarmPlan(trigger: MovaEagerWarm()));
    expect(made, hasLength(2));
    expect(movaCapabilityOf<_Marker>(proxy), same(made.first));
    const tick = MovaProg(position: Duration(seconds: 1), buffer: Duration(seconds: 10));
    made.last.pushProgress(tick);
    await _settle();
    made.last.pushProgress(tick);
    await _settle();
    expect(await proxy.commit(), isTrue);
    expect(movaCapabilityOf<_Marker>(proxy), same(made.last));
  });
}
