// ignore_for_file: avoid_relative_lib_imports
import 'package:test/test.dart';
import '../accept/lib/matrix.dart';

/// B7 共用字面量。
const _b7Literal0 = 'scenario';

/// B7 共用字面量。
const _b7Literal1 = 'missing';

/// B7 共用字面量。
const _b7Literal2 = 'network';

/// B7 共用字面量。
const _b7Literal3 = 'normal';

/// B7 共用字面量。
const _b7Literal4 = 'style';

/// B7 共用字面量。
const _b7Literal5 = 'http';

/// B7 共用字面量。
const _b7Literal6 = 'status';

/// B7 共用字面量。
const _b7Literal7 = '跳过';

/// B7 共用字面量。
const _b7Literal8 = 'reasons';

/// B7 共用字面量。
const _b7Literal9 = 'excluded';

/// B7 共用字面量。
const _b7Literal10 = 'cases';

/// B7 共用字面量。
const _b7Literal11 = 'normal@http';

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
            _b7Literal0: _b7Literal1,
            _b7Literal2: _b7Literal3,
            _b7Literal4: _b7Literal5,
            _b7Literal6: _b7Literal7,
            _b7Literal8: ['skipped: missing raw-business-code']
          },
          {
            _b7Literal0: _b7Literal9,
            _b7Literal2: _b7Literal3,
            _b7Literal4: _b7Literal5,
            _b7Literal6: _b7Literal7,
            _b7Literal8: ['不适用：场景未声明此风格']
          },
        ]
      }
    ]);
    expect((summary[_b7Literal10] as Map)[_b7Literal1],
        {_b7Literal11: _b7Literal7});
    expect((summary[_b7Literal10] as Map)[_b7Literal9],
        {_b7Literal11: notApplicable});
  });
  test('[matrix.rowResult] 缺真实环境只登记 BLOCKED 零执行，不伪造通过', () {
    const source = 'test/accept/evidence/external.json';
    final blocked =
        MatrixRow(id: 'connect', tier: 2, blocked: '用户态代理无法丢 SYN；解锁需要可控握手超时端点');
    expect(rowResult(blocked, {}, source),
        {_b7Literal6: 'BLOCKED', 'source': source, 'passed': 0, 'total': 0});
    expect(
        rowResult(MatrixRow(id: 'unregistered', tier: 2), {}, source), isNull);
    expect(
        rowResult(
            MatrixRow(
                id: 'absent', tier: 2, real: ['not-run'], blocked: '尚未执行'),
            {},
            source),
        isNull);
  });
}
