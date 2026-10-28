import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

/// 默认插件的名称。
const _name = 'custom:default';

/// 顺序异常的说明文本。
const _message = 'readable ordering failure';

/// 只声明名称，保留基类释放和顺序默认行为。
class _DefaultPlugin extends DiomanPlugin {
  /// 返回测试用的插件名。
  @override
  String get name => _name;
}

/// 验证基类默认契约与顺序异常的可读说明。
void main() {
  test(
      '[DiomanPlugin.dispose][DiomanPlugin.name][DiomanPluginOrder.none] 默认释放为空操作且顺序声明无约束',
      () {
    final plugin = _DefaultPlugin();
    expect(plugin.name, _name);
    expect(plugin.ordering, same(DiomanPluginOrder.none));
    expect(plugin.ordering.before, isEmpty);
    expect(plugin.ordering.after, isEmpty);
    expect(plugin.ordering.requires, isEmpty);
    expect(plugin.dispose, returnsNormally);
    expect(plugin.dispose, returnsNormally);
    expect(Dioman.sort([plugin]).single, same(plugin));
    Dioman.validate([plugin]);
  });

  test('[DiomanPluginOrderException.message] 保存异常说明并用于字符串输出', () {
    const exception = DiomanPluginOrderException(
        DiomanPluginOrderIssue.cycle, [_name], _message);
    expect(exception.message, _message);
    expect(
        exception.toString(), 'DiomanPluginOrderException(cycle): $_message');
  });
}
