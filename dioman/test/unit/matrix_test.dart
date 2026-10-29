// ignore_for_file: avoid_relative_lib_imports
import 'package:test/test.dart';
import '../accept/lib/matrix.dart';

/// 闸门工具的标题扫描及跳过语义必须支持新测试布局。
void main() {
  test('[matrix.titleIdsFromSource] 常量插值及相邻字面量被反查，注释和普通字符串忽略', () {
    final source = r'''
const title = '[INV-scan]';
// test('[ignored-comment]', () {});
final text = "test('[ignored-string]', () {})";
test('$title mask=$mask', () {});
test('[A]' '[B]', () {});
''';
    expect(titleIdsFromSource(source), ['INV-scan', 'A', 'B']);
  });
  test('[matrix.symbolsFromSources] 泛型返回值不吞掉后续函数声明', () {
    expect(
        symbolsFromSources({
          'helper':
              'List<String> check(Map<String, dynamic> input) => input.keys.toList();'
        }),
        contains('helper.check'));
  });
  test('[matrix.summarizeEvidence] 不适用不计结论，缺能力保留阻塞', () {
    final summary = summarizeEvidence([
      {
        'results': [
          {
            'scenario': 'missing',
            'network': 'normal',
            'style': 'http',
            'status': '跳过',
            'reasons': ['skipped: missing raw-business-code']
          },
          {
            'scenario': 'excluded',
            'network': 'normal',
            'style': 'http',
            'status': '跳过',
            'reasons': ['不适用：场景未声明此风格']
          },
        ]
      }
    ]);
    expect((summary['cases'] as Map)['missing'], {'normal@http': '跳过'});
    expect(
        (summary['cases'] as Map)['excluded'], {'normal@http': notApplicable});
  });
}
