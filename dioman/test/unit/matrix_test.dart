// ignore_for_file: avoid_relative_lib_imports
import 'package:test/test.dart';
import '../accept/lib/matrix.dart';

/// 汇总测试用的报告字段与取值。
const _resultsKey = 'results',
    _scenario = 'scenario',
    _network = 'network',
    _style = 'style',
    _status = 'status',
    _normal = 'normal',
    _http = 'http',
    _business = 'business',
    _pass = '通过',
    _caseX = 'auth.x',
    _src = 'test/accept/evidence/x.json';

/// 标题编号 A，用于组合标题的断言。
const _a = 'A';

/// 本文件共用的字面量 'B'。
const _b = 'B';

/// 本文件共用的字面量 'C'。
const _c = 'C';

/// 本文件共用的字面量 'DiomanRetry.new(max)'。
const _diomanRetryNewMax = 'DiomanRetry.new(max)';

/// 本文件共用的字面量 'parameter'。
const _parameter = 'parameter';

/// 本文件共用的字面量 'DiomanRetry.custom(max)'。
const _diomanRetryCustomMax = 'DiomanRetry.custom(max)';

/// 本文件共用的字面量 'DiomanRetry.max'。
const _diomanRetryMax = 'DiomanRetry.max';

/// 本文件共用的字面量 'field'。
const _field = 'field';

/// 本文件共用的字面量 'getter'。
const _getter = 'getter';

/// 本文件共用的字面量 'class'。
const _class = 'class';

/// 本文件共用的字面量 'DiomanRetry.custom(other)'。
const _diomanRetryCustomOther = 'DiomanRetry.custom(other)';

/// 本文件共用的字面量 'apis'。
const _apis = 'apis';

/// 本文件共用的字面量 'H1'。
const _h1 = 'H1';

/// 本文件共用的字面量 'core'。
const _core = 'core';

/// 本文件共用的字面量 'X.a'。
const _xA = 'X.a';

/// 本文件共用的字面量 'row'。
const _row = 'row';

/// 本文件共用的字面量 'real-only'。
const _realOnly = 'real-only';

/// 本文件共用的字面量 'INV-cleanup'。
const _iNVCleanup = 'INV-cleanup';

/// 本文件共用的字面量 'unknown'。
const _unknown = 'unknown';

/// 本文件共用的字面量 'helper'。
const _helper = 'helper';

/// 本文件共用的字面量 'G0:new'。
const _g0New = 'G0:new';

/// 本文件共用的字面量 'G0:old'。
const _g0Old = 'G0:old';

/// 本文件共用的字面量 'lib/a.dart'。
const _libADart = 'lib/a.dart';

/// 本文件共用的字面量 'fallback();'。
const _fallback = 'fallback();';

/// 构造内存台账项。
Map<String, dynamic> _api(String api, String kind) =>
    {'api': api, 'kind': kind};

/// 验证矩阵纯函数，不读取仓库数据。
void main() {
  test('[matrix.parseTitleIds] 组合、多括号、空标题', () {
    expect(parseTitleIds('[ A × B ][C] 标题'), [_a, _b, _c]);
    expect(parseTitleIds('没有编号'), isEmpty);
  });
  test('[matrix.titleIdsFromSource] 引号、转义、换行及相邻字符串', () {
    expect(titleIdsFromSource(r'''test('[A] "quoted"' '[B × C]', () {});
      test("[D] isn't" '\'escaped\'', () {});
      test(
        r'[E] raw', () {});
      // test('[comment]', () {});
      /* test('[block-comment]', () {}); */
      final text = "test('[string]', () {})";'''), [_a, _b, _c, 'D', 'E']);
  });
  test('[matrix.draftRows] 构造参数、命名构造和 setter 合并', () {
    final rows = draftRows([
      _api(_diomanRetryNewMax, _parameter),
      _api(_diomanRetryCustomMax, _parameter),
      _api(_diomanRetryMax, _field),
      _api(_diomanRetryMax, 'setter'),
      _api(_diomanRetryMax, _getter),
      _api('DiomanRetry', _class),
      _api('DiomanRetry.new', 'constructor'),
      _api(_diomanRetryCustomOther, _parameter),
    ], []);
    expect(rows, hasLength(2));
    expect(rows.last.id, _diomanRetryMax);
    expect(rows.last.apis,
        [_diomanRetryCustomMax, _diomanRetryMax, _diomanRetryNewMax]);
    expect(rows.first.id, _diomanRetryCustomOther);
  });
  test('[matrix.draftRows] 保留人工字段及未知 JSON 字段', () {
    final row = MatrixRow.fromJson({
      'id': _diomanRetryMax,
      'plugin': 'manual',
      'capability': '人工能力',
      'tier': 2,
      _apis: [_diomanRetryMax],
      'real': ['case'],
      'assumptions': [_h1],
      'result': {_status: 'PASS', 'source': 'evidence'},
      'blocked': '待核对',
      'future': {'keep': true}
    });
    final rows = draftRows(
        [_api(_diomanRetryNewMax, _parameter), _api(_diomanRetryMax, _field)],
        [row]);
    final expected = row.toJson()
      ..[_apis] = [_diomanRetryMax, _diomanRetryNewMax];
    expect(rows.single.toJson(), expected);
    expect(draftRows([], rows).single.toJson(), expected);
    final custom = MatrixRow(
        id: 'INV-custom', capability: '人工字段', apis: [_diomanRetryNewMax]);
    final reversed = draftRows(
        [_api(_diomanRetryNewMax, _parameter), _api(_diomanRetryMax, _getter)],
        [custom]);
    expect(reversed.single.id, custom.id);
    expect(reversed.single.capability, custom.capability);
    expect(reversed.single.apis,
        containsAll([_diomanRetryNewMax, _diomanRetryMax]));
  });
  test('[matrix.pluginForFile] 按源文件分组，install/extra 固定映射，未知归 core', () {
    expect(pluginForFile('lib/src/retry_plugin.dart'), 'retry');
    expect(pluginForFile('lib/src/timeout_plugin.dart'), 'timeout');
    expect(pluginForFile('lib/src/dioman.dart'), 'install');
    expect(pluginForFile('lib/src/plugin_order.dart'), 'install');
    expect(pluginForFile('lib/src/extra_keys.dart'), 'extra');
    expect(pluginForFile('lib/src/unknown.dart'), _core);
    expect(pluginForFile(null), _core);
  });
  test('[matrix.computeGaps] G0/G2/G3/G5 静态判定', () {
    final gaps = computeGaps(inventory: [
      _api(_xA, _field),
      _api('X.b', 'method'),
      _api('X', _class)
    ], evidenceHits: {}, rows: [
      MatrixRow(id: _row, apis: [_xA]),
      MatrixRow(id: _realOnly, tier: 3),
      MatrixRow(id: _iNVCleanup, tier: 1, apis: ['missing'])
    ], titles: {
      _unknown: {},
      _helper: {},
      _iNVCleanup: {}
    }, symbols: {
      _helper
    });
    expect(gaps, {
      'G0:row',
      'G2:X.b',
      'G2:X',
      'G3:row',
      'G3:INV-cleanup',
      'G5:unknown',
      'G5:row-api:INV-cleanup:missing'
    });
    expect(
        computeGaps(inventory: [
          _api(_xA, _field)
        ], rows: [
          MatrixRow(id: _row, tier: 1, apis: [_xA])
        ], titles: {
          _xA: {}
        }),
        isEmpty);
  });
  test('[matrix.computeGaps] G4 与真实侧 G5', () {
    final gaps = computeGaps(
        inventory: [],
        rows: [
          MatrixRow(
              id: _row,
              tier: 2,
              assumptions: [_h1],
              result: {_status: 'BLOCKED'}),
          MatrixRow(id: _realOnly, tier: 3, real: [_unknown])
        ],
        titles: {},
        full: true,
        realIds: {'orphan'},
        falsified: {_h1});
    expect(
        gaps,
        containsAll({
          'G4:row:no-real',
          'G4:row:blocked-no-reason',
          'G4:row:falsified-H1',
          'G4:real-only:no-result',
          'G5:real-unknown:unknown',
          'G5:real-orphan:orphan'
        }));
    expect(
        falsifiedAssumptions('| H1 | 假设 | 已证伪 |\n| H2 | 假设 | 未核对 |'), isEmpty,
        reason: '少于状态列的行不解析');
  });
  test('[matrix.falsifiedAssumptions] 只看状态列，支持 H1b 这类子编号', () {
    const table = '| 编号 | 假设 | 出处 | 依赖 | 核对状态 | 方法 |\n'
        '| H1 | 假设 | 出处 | 单测 | 已证伪（2026-10-28） | 方法 |\n'
        '| H1b | 假设 | 出处 | 单测 | 已证伪 | 方法 |\n'
        '| H2 | 描述里提到已证伪 | 出处 | 单测 | 未核对 | 方法 |';
    expect(falsifiedAssumptions(table), {_h1, 'H1b'});
  });
  test('[matrix.computeGaps] 无 API 的行用 unit 字段指向单测文件，文件须含用例', () {
    final gaps = computeGaps(inventory: [], rows: [
      MatrixRow(id: 'INV-ok', tier: 1, extra: {
        'unit': ['test/combo/a_test.dart']
      }),
      MatrixRow(id: 'INV-bad', tier: 1, extra: {
        'unit': ['test/combo/missing_test.dart']
      }),
    ], titles: {
      _xA: {'test/combo/a_test.dart'}
    }, symbols: {});
    expect(gaps, {
      'G3:INV-bad',
      'G5:row-unit:INV-bad:test/combo/missing_test.dart',
      'G5:$_xA'
    });
  });
  test('[matrix.computeGaps] 标题里直接写行 id 也算单测引用', () {
    final gaps = computeGaps(inventory: [], rows: [
      MatrixRow(id: 'INV-20', tier: 1)
    ], titles: {
      'INV-20': {'test/combo/x_test.dart'}
    }, symbols: {});
    expect(gaps, isEmpty);
  });
  test('[matrix.ratchet] 指定前缀的 added 与 fixed', () {
    final result = ratchet({_g0New, 'G5:ignored'}, {_g0Old, 'G1:ignored'},
        required: {'G0:'});
    expect(result.added, {_g0New});
    expect(result.fixed, {_g0Old});
  });
  test('[matrix.computeGaps] lcov 白名单按文本和文件匹配并聚合重复记录', () {
    final gaps = computeGaps(
        inventory: [],
        rows: [],
        titles: {},
        lcov:
            'SF:lib/a.dart\nDA:2,0\nDA:3,0\nDA:4,0\nSF:lib/a.dart\nDA:4,1\nSF:lib/b.dart\nDA:1,0\n',
        sourceLines: {
          _libADart: ['', '  fallback(); ', 'missing();', 'hit();'],
          'lib/b.dart': [_fallback]
        },
        whitelist: [
          {'file': _libADart, 'text': _fallback, 'reason': '兜底'}
        ]);
    expect(gaps, {'G1:lib/a.dart:missing();', 'G1:lib/b.dart:fallback();'});
  });
  test('[matrix.computeGaps] 白名单里已被测到的行报 stale，防止它将来再失守时被掩盖', () {
    final gaps = computeGaps(
        inventory: [],
        rows: [],
        titles: {},
        lcov: 'SF:lib/a.dart\nDA:1,3\n',
        sourceLines: {
          _libADart: [_fallback]
        },
        whitelist: [
          {'file': _libADart, 'text': _fallback, 'reason': '兜底'}
        ]);
    expect(gaps, {'G1:stale:lib/a.dart:fallback();'});
  });
  test('[matrix.symbolsFromSources] 认可内部模块、函数与成员', () {
    final symbols = symbolsFromSources({
      'delay': 'Future<void> cancellableDelay() {}',
      'pairwise': 'List<int> binaryPairs() => [];',
      'replay': 'class ReplayClient { Future<void> finishRecovered() {} }',
      'claims': 'class RequestClaims { void whenDrained() {} }',
      'matrix': 'void computeGaps() {}'
    });
    expect(
        symbols,
        containsAll({
          'cancellableDelay',
          'binaryPairs',
          'ReplayClient.finishRecovered',
          'RequestClaims.whenDrained',
          'matrix.computeGaps'
        }));
  });
  test('[matrix.summarizeEvidence] 按场景与网络@风格汇总，后者覆盖前者', () {
    final summary = summarizeEvidence([
      {
        _resultsKey: [
          {_scenario: _caseX, _network: _normal, _style: _http, _status: '失败'},
          {
            _scenario: _caseX,
            _network: _normal,
            _style: _business,
            _status: _pass
          },
        ]
      },
      {
        _resultsKey: [
          {_scenario: _caseX, _network: _normal, _style: _http, _status: _pass},
          {_network: _normal, _style: _http, _status: _pass},
          {
            _scenario: _caseX,
            _network: 'weak',
            _style: _http,
            _status: '跳过',
            'reasons': ['场景未声明此网络或风格；不推断未定义的正确预期']
          },
        ]
      },
    ], apiHits: [
      _b,
      _a
    ]);
    expect(summary['cases'], {
      _caseX: {
        'normal@business': _pass,
        'normal@http': _pass,
        'weak@http': notApplicable
      }
    });
    expect(summary['apiHits'], [_a, _b]);
  });
  test('[matrix.rowResult] 失败优先、有通过即 PASS、全跳过 BLOCKED，按格计数', () {
    MatrixRow row(List<String> real) => MatrixRow(id: _a, real: real);
    final cases = {
      'ok': {'n@h': _pass, 'n@b': '跳过'},
      'bad': {'n@h': '失败'},
      'skip': {'n@h': '跳过'},
      'na': {'n@h': notApplicable, 'w@h': _pass},
      'naOnly': {'n@h': notApplicable},
    };
    expect(rowResult(row(['ok']), cases, _src),
        {'status': 'PASS', 'source': _src, 'passed': 1, 'total': 2});
    expect(rowResult(row(['ok', 'bad']), cases, _src)?['status'], 'FAIL');
    expect(rowResult(row(['skip']), cases, _src)?['status'], 'BLOCKED');
    expect(rowResult(row(['missing']), cases, _src), isNull);
    expect(rowResult(row([]), cases, _src), isNull);
    expect(rowResult(row(['na']), cases, _src)?['total'], 1, reason: '不适用不计入');
    expect(rowResult(row(['naOnly']), cases, _src), isNull);
  });
}
