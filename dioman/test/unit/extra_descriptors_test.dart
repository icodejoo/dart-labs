import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

/// 自定义登记项的归属插件名。
const _owner = 'custom:descriptor';

/// 自定义登记项对应的 extra 键名。
const _key = 'custom:descriptor:state';

/// 登记项的值类型描述（仅作元数据）。
const _type = 'informational type';

/// 登记项的说明文本。
const _description = '测试状态说明';

/// 验证登记描述只提供元数据，运行期不检查归属或值类型。
void main() {
  test(
      '[DiomanExtraKey.config(name)][DiomanExtraKey.description][DiomanExtraKey.kind][DiomanExtraKey.owner][DiomanExtraKey.valueType] 描述字段保存并参与注册筛选和输出',
      () {
    const config = DiomanExtraKey.config(_owner, _type, _description);
    const state = DiomanExtraKey.state(_key, _owner, _type, _description);
    const general = DiomanExtraKey(
        key: _key,
        owner: _owner,
        kind: DiomanExtraKeyKind.protocol,
        valueType: _type,
        description: _description);
    expect(config.key, _owner);
    expect(config.owner, _owner);
    expect(config.kind, DiomanExtraKeyKind.config);
    expect(state.kind, DiomanExtraKeyKind.state);
    expect(general.kind, DiomanExtraKeyKind.protocol);
    for (final item in [config, state, general]) {
      expect(item.owner, _owner);
      expect(item.valueType, _type);
      expect(item.description, _description);
      DiomanExtraKeys.register(item);
      try {
        expect(DiomanExtraKeys.ofOwner(_owner), contains(same(item)));
        expect(DiomanExtraKeys.ofKind(item.kind), contains(same(item)));
        expect(DiomanExtraKeys.lookup(item.key)!.description, _description);
        expect(DiomanExtraKeys.lookup(item.key)!.valueType, _type);
        final options =
            RequestOptions(path: '/descriptor', extra: {item.key: Object()});
        expect(options.extra[item.key], isNotNull);
        expect(DiomanExtraKeys.lookup(item.key), same(item));
      } finally {
        DiomanExtraKeys.unregister(item.key);
      }
    }
  });

  test('[DiomanSharedStateKey.toString] 诊断文本包含键名与实例数', () {
    const key = DiomanExtraKey.state(_key, _owner, _type, _description);
    for (final count in [2, 3]) {
      final conflict = DiomanSharedStateKey(key, count);
      expect(conflict.key, same(key));
      expect(conflict.toString(), '$_key x$count');
    }
  });
}
