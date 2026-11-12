import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/treeshake/check_treeshake.dart';

/// 转盘源码区名。
const String _wheelZone = 'wheel';

/// 九宫格源码区名。
const String _gridZone = 'grid';

/// 老虎机源码区名。
const String _slotZone = 'slot';

/// 扭蛋机源码区名。
const String _capsuleZone = 'capsule';

/// 数字转盘源码区名。
const String _numberZone = 'number_wheel';

/// 抽签源码区名。
const String _lotsZone = 'lots';

/// 大乐透源码区名。
const String _lottoZone = 'lotto';

/// 九宫格配置符号。
const String _gridConfig = 'GridConfig';

/// 老虎机配置符号。
const String _slotConfig = 'SlotConfig';

/// 扭蛋机配置符号。
const String _capsuleConfig = 'CapsuleConfig';

/// 数字转盘配置符号。
const String _numberConfig = 'NumberWheelConfig';

/// 抽签配置符号。
const String _lotsConfig = 'LotsConfig';

/// 大乐透配置符号。
const String _lottoConfig = 'LottoConfig';

/// 默认缓动符号。
const String _quad = 'QuadEasing';

/// sourcemap 版本字段。
const String _versionKey = 'version';

/// sourcemap 来源字段。
const String _sourcesKey = 'sources';

/// sourcemap 符号字段。
const String _namesKey = 'names';

/// sourcemap 映射字段。
const String _mappingsKey = 'mappings';

/// sourcemap 来源根路径字段。
const String _sourceRootKey = 'sourceRoot';

/// APK 夹具根节点名。
const String _rootName = 'root';

/// APK 包分组节点名。
const String _packageGroup = 'package:luckdraw';

/// APK 分组下的转盘相对库路径。
const String _relativeWheel = 'src/wheel/widget.dart';

/// 夹具中的转盘构建符号。
const String _wheelBuild = 'LuckyWheel.build';

/// Web 后端名。
const String _web = 'web';

/// APK 后端名。
const String _apk = 'apk';

/// 老虎机夹具源文件路径。
const String _slotSource = '/luckdraw/lib/src/slot/model.dart';

/// 转盘兼容转换夹具源文件路径。
const String _compatSource = '/luckdraw/lib/src/compat/wheel_compat.dart';

/// 不应进入普通玩法的注册表符号。
const String _registry = 'LuckyGameRegistry';

/// 源文件违规诊断片段。
const String _forbiddenFile = '禁止的源文件';

/// 符号违规诊断片段。
const String _forbiddenSymbol = '禁止的符号';

/// 大乐透合法使用、其它单玩法不应保留的三次缓动符号。
const String _cubic = 'CubicEasing';

/// 不带拉杆的老虎机探针名。
const String _slotProbe = 'slot_only';

/// 仅供 compat 使用的缓动名称表符号。
const String _easingNames = 'kLuckyCanvasEasingNames';

/// 不应被误认为三次缓动的前缀夹具。
const String _notCubic = 'NotCubicEasing';

/// 不应被误认为三次缓动的后缀夹具。
const String _extendedCubic = 'CubicEasingExtension';

/// 兼容转盘探针名。
const String _compatProbe = 'compat_wheel';

/// 无包引用的基线探针名。
const String _baseline = 'baseline';

/// 转盘探针名称。
const String _wheel = 'wheel_only';

/// 完整玩法探针名称。
const String _all = 'all_games';

/// 包内 core 夹具路径。
const String _coreSource = '/luckdraw/lib/src/core/easing/easing.dart';

/// 包内转盘夹具路径。
const String _wheelSource = '/luckdraw/lib/src/wheel/widget.dart';

/// APK 树子节点字段。
const String _children = 'children';

/// APK 树名字字段。
const String _name = 'n';

/// APK 字节数字段。
const String _value = 'value';

/// 合法 APK 叶节点名。
const String _apkCore = 'package:luckdraw/src/core/easing/easing.dart';

/// 第二个合法 APK 库名。
const String _apkWheel = 'package:luckdraw/src/wheel/widget.dart';

/// 两个 APK 叶节点与总和的示例字节数。
const int _coreBytes = 30, _wheelBytes = 70, _totalBytes = 100;

/// Web 预算字段。
const String _webLimit = 'maxDeltaGzipBytes';

/// APK 预算字段。
const String _apkLimit = 'maxLuckdrawBytes';

/// 全部玩法源码区；循环使用此列表而不动态注册测试。
const List<String> _gameZones = [
  _wheelZone,
  _gridZone,
  _slotZone,
  _capsuleZone,
  _numberZone,
  _lotsZone,
  _lottoZone,
];

/// 生成小型有效 sourcemap；测试只覆盖解析，不调用编译器。
String _sourcemap({
  List<String> sources = const [_coreSource, _wheelSource],
  List<String> names = const [_quad],
  String? sourceRoot,
}) =>
    jsonEncode({
      _versionKey: 3,
      _sourcesKey: sources,
      _namesKey: names,
      _mappingsKey: '',
      if (sourceRoot != null) _sourceRootKey: sourceRoot,
    });

/// 构造小型 n/children/value APK 树，父节点体积不重复累计。
Map<String, Object?> _apkTree() => {
      _name: _rootName,
      _children: [
        {
          _name: 'libapp.so',
          _children: [
            {
              _name: _packageGroup,
              _value: _totalBytes,
              _children: [
                {_name: 'src/core/easing/easing.dart', _value: _coreBytes},
                {
                  _name: _relativeWheel,
                  _children: [
                    {_name: _wheelBuild, _value: _wheelBytes}
                  ],
                },
              ],
            },
            {_name: 'package:luckdraw_extra/src/grid/a.dart', _value: 999},
          ],
        },
      ],
    };

/// 生成双后端预算；[limit] 为 null 表示待首轮实测回填。
Map<String, Object?> _budgets([int? limit]) => {
      _web: <String, Object?>{
        for (final probe in kTreeshakeProbes) probe: {_webLimit: limit}
      },
      _apk: <String, Object?>{
        for (final probe in kTreeshakeProbes) probe: {_apkLimit: limit}
      },
    };

/// 从内存路径快速生成产物。
TreeshakeArtifact _artifact(List<String> sources,
        [List<String> names = const []]) =>
    parseWebSourcemap(_sourcemap(sources: sources, names: names));

/// 验证 §8 的来源、符号、结构和预算门禁。
void main() {
  group('treeshake parsers', () {
    test('sourcemap parser lists retained luckdraw source files', () {
      final result = parseWebSourcemap(_sourcemap(sources: [
        'file:///C:/work/luckdraw/lib/src/core/easing/easing.dart',
        r'C:\work\luckdraw\lib\src\wheel\widget.dart',
        _apkWheel,
        '/work/luckdraw_extra/lib/src/grid/a.dart',
        'package:flutter/widgets.dart',
      ]));
      expect(result.sources, {_coreSource, _wheelSource});
      expect(result.names, {_quad});
      expect(result.luckdrawBytes, isNull);
      expect(() => result.sources.add('x'), throwsUnsupportedError);
      expect(checkProbe(_wheel, result), isEmpty);
    });

    test('apk size json parser finds package:luckdraw libraries', () {
      final result = parseApkSizeJson(jsonEncode(_apkTree()));
      expect(result.sources, {_coreSource, _wheelSource});
      expect(result.names, contains(_wheelBuild));
      expect(result.luckdrawBytes, _totalBytes);
      expect(checkProbe(_wheel, result), isEmpty);
    });

    test('probe assertions report forbidden files and symbols', () {
      final result = _artifact([
        _coreSource,
        _wheelSource,
        '/luckdraw/lib/src/grid/model.dart',
        _slotSource,
        _compatSource,
      ], [
        'CubicEasing.easeIn',
        _registry
      ]);
      final errors = checkProbe(_wheel, result);
      expect(errors.where((error) => error.contains(_forbiddenFile)),
          hasLength(3));
      expect(errors.where((error) => error.contains(_forbiddenSymbol)),
          hasLength(2));
      expect(errors.join(), contains(_cubic));
      expect(errors.join(), contains('src/grid/'));
    });

    test('sourcemap resolves sourceRoot encoded paths and dot segments', () {
      final result = parseWebSourcemap(_sourcemap(
        sourceRoot: 'file:///C:/work%20tree/luckdraw/lib',
        sources: [
          'src/core/../core/easing/easing.dart',
          _relativeWheel,
          _apkWheel
        ],
      ));
      expect(result.sources, {_coreSource, _wheelSource});
      expect(checkProbe(_wheel, result), isEmpty);
    });

    test('sourcemap rejects missing fields indexed maps and invalid types', () {
      for (final malformed in <Object?>[
        [],
        {},
        {_versionKey: 3, 'sections': <Object?>[]},
        {
          _versionKey: 2,
          _sourcesKey: <Object?>[],
          _namesKey: <Object?>[],
          _mappingsKey: ''
        },
        {
          _versionKey: 3,
          _sourcesKey: [1],
          _namesKey: <Object?>[],
          _mappingsKey: ''
        },
        {
          _versionKey: 3,
          _sourcesKey: <Object?>[],
          _namesKey: [null],
          _mappingsKey: ''
        },
        {
          _versionKey: 3,
          _sourcesKey: <Object?>[],
          _namesKey: <Object?>[],
          _mappingsKey: 1
        },
        {
          _versionKey: 3,
          _sourcesKey: <Object?>[],
          _namesKey: <Object?>[],
          _mappingsKey: '',
          _sourceRootKey: 1
        },
      ]) {
        expect(() => parseWebSourcemap(jsonEncode(malformed)),
            throwsFormatException,
            reason: '$malformed');
      }
      expect(() => parseWebSourcemap('{'), throwsFormatException);
    });

    test('apk parser accepts direct library nodes without double counting', () {
      final result = parseApkSizeJson(jsonEncode({
        _name: _rootName,
        _value: _totalBytes * 2,
        _children: [
          {_name: _apkCore, _value: _coreBytes},
          {_name: _apkWheel, _value: _wheelBytes},
        ],
      }));
      expect(result.luckdrawBytes, _totalBytes);
      expect(result.sources, {_coreSource, _wheelSource});
    });

    test(
        'apk parser rejects unknown schemas missing packages and invalid nodes',
        () {
      for (final malformed in <Object?>[
        [],
        {},
        {'name': _rootName, 'size': 1},
        {_name: _rootName, _value: 1},
        {_name: 'package:luckdraw_extra/src/wheel/a.dart', _value: 1},
        {_name: _packageGroup, _value: 0},
        {_name: _apkCore},
        {_name: _apkCore, _value: -1},
        {_name: _apkCore, _value: 1.5},
        {_name: _apkCore, _value: '30'},
        {_name: _apkCore, _children: <Object?>[]},
        {_name: _apkCore, _children: null},
        {_name: _apkCore, _children: <String, Object?>{}},
        {
          _name: _apkCore,
          _children: [1]
        },
        {
          _name: _apkCore,
          _children: [
            {_name: '', _value: 1}
          ]
        },
        {
          _name: _apkCore,
          _children: [
            {_name: 1, _value: 1}
          ]
        },
      ]) {
        expect(() => parseApkSizeJson(jsonEncode(malformed)),
            throwsFormatException,
            reason: '$malformed');
      }
      expect(() => parseApkSizeJson('invalid'), throwsFormatException);
    });

    test('apk parser rejects duplicate library records', () {
      expect(
          () => parseApkSizeJson(jsonEncode({
                _name: _rootName,
                _children: [
                  {_name: _apkCore, _value: 1},
                  {_name: _apkCore, _value: 1},
                ],
              })),
          throwsFormatException);
    });

    test('apk schema drift inside a partially valid package fails explicitly',
        () {
      expect(
          () => parseApkSizeJson(jsonEncode({
                _name: _packageGroup,
                _children: [
                  {_name: _apkCore, _value: _coreBytes},
                  {_name: 'unrecognized-library-shape', _value: _wheelBytes},
                ],
              })),
          throwsFormatException);
    });

    test('probe assertions require zones instead of inlined class names', () {
      expect(
          checkProbe(_wheel, _artifact([_coreSource, _wheelSource])), isEmpty);
      expect(checkProbe(_wheel, _artifact([_coreSource])).single,
          contains(_wheelZone));
      expect(checkProbe(_wheel, _artifact([_wheelSource])).single,
          contains('core'));
      expect(() => checkProbe('unknown', _artifact([])), throwsArgumentError);
    });

    test('all single game probes forbid every other game and testing', () {
      for (final game in _gameZones) {
        final own = '/luckdraw/lib/src/$game/model.dart';
        final valid = [_coreSource, own];
        expect(checkProbe('${game}_only', _artifact(valid)), isEmpty);
        for (final other in <String>[
          _wheelZone,
          _gridZone,
          _slotZone,
          _capsuleZone,
          _numberZone,
          _lotsZone,
          _lottoZone,
          'compat',
          'testing'
        ]) {
          if (game == other) continue;
          expect(
              checkProbe(
                  '${game}_only',
                  _artifact([
                    ...valid,
                    '/luckdraw/lib/src/$other/leak.dart',
                  ])),
              contains(contains(_forbiddenFile)));
        }
      }
    });

    test('kinematics is retained only by capsule and lotto single game probes',
        () {
      const kinematics = '/luckdraw/lib/src/core/kinematics/swirl.dart';
      for (final game in _gameZones) {
        final errors = checkProbe(
            '${game}_only',
            _artifact([
              _coreSource,
              '/luckdraw/lib/src/$game/model.dart',
              kinematics,
            ]));
        expect(
            errors,
            game == _capsuleZone || game == _lottoZone
                ? isEmpty
                : contains(contains(kinematics)));
      }
    });

    test('slot probe forbids lever source and lever symbol independently', () {
      const slot = _slotSource;
      expect(
          checkProbe(
              _slotProbe,
              _artifact([
                _coreSource,
                slot,
                '/luckdraw/lib/src/slot/lever/widget.dart',
              ])),
          contains(contains(_forbiddenFile)));
      expect(
          checkProbe(_slotProbe,
              _artifact([_coreSource, slot], ['LuckyLeverSlotMachine.build'])),
          contains(contains(_forbiddenSymbol)));
    });

    test('symbol checks use identifier boundaries and catch qualified names',
        () {
      const forbidden = [
        _cubic,
        'QuartEasing',
        'QuintEasing',
        'SineEasing',
        'ExpoEasing',
        'CircEasing',
        _registry,
        _easingNames
      ];
      final result = _artifact([
        _coreSource,
        _wheelSource
      ], [
        for (final symbol in forbidden) 'prefix.$symbol.method',
        _notCubic,
        _extendedCubic,
      ]);
      expect(checkProbe(_wheel, result), hasLength(forbidden.length));
      expect(
          checkProbe(
              _wheel,
              _artifact(
                  [_coreSource, _wheelSource], [_notCubic, _extendedCubic])),
          isEmpty);
    });

    test('lotto_only allows CubicEasing in sourcemap names', () {
      final artifact = parseWebSourcemap(jsonEncode({
        _versionKey: 3,
        _sourcesKey: [_coreSource, '/luckdraw/lib/src/lotto/motion.dart'],
        _namesKey: [_cubic, '$_cubic.easeOut', _quad, 'LottoMotion'],
        _mappingsKey: '',
      }));
      expect(checkProbe('lotto_only', artifact), isEmpty);
    });

    test('wheel_only rejects CubicEasing in sourcemap names', () {
      final artifact = parseWebSourcemap(jsonEncode({
        _versionKey: 3,
        _sourcesKey: [_coreSource, _wheelSource],
        _namesKey: [_cubic, '$_cubic.easeOut', _quad, _wheelBuild],
        _mappingsKey: '',
      }));
      expect(checkProbe(_wheel, artifact), [
        '$_wheel $_forbiddenSymbol: $_cubic',
        '$_wheel $_forbiddenSymbol: $_cubic.easeOut',
      ]);
    });

    test('single game symbol allowlists reject unrelated games independently',
        () {
      const gameSymbols = {
        _wheelZone: 'WheelConfig',
        _gridZone: _gridConfig,
        _slotZone: _slotConfig,
        _capsuleZone: _capsuleConfig,
        _numberZone: _numberConfig,
        _lotsZone: _lotsConfig,
        _lottoZone: _lottoConfig,
      };
      for (final game in gameSymbols.entries) {
        final probe = '${game.key}_only';
        final sources = [
          _coreSource,
          '/luckdraw/lib/src/${game.key}/model.dart',
        ];
        expect(
            checkProbe(probe, _artifact(sources, [game.value, _quad])), isEmpty,
            reason: probe);
        for (final other in gameSymbols.entries) {
          if (other.key == game.key) continue;
          expect(checkProbe(probe, _artifact(sources, [other.value])),
              ['$probe $_forbiddenSymbol: ${other.value}']);
        }
      }
    });

    test('baseline rejects checked symbols even without retained sources', () {
      expect(checkProbe(_baseline, _artifact([], [_cubic, _wheelBuild])),
          hasLength(2));
    });

    test('compat wheel allows compat easings but forbids other converters', () {
      final sources = [_coreSource, _wheelSource, _compatSource];
      expect(
          checkProbe(_compatProbe, _artifact(sources, [_cubic, _easingNames])),
          isEmpty);
      const unrelatedSymbols = [
        'gridFromLuckyCanvasConfig',
        'slotFromLuckyCanvasConfig',
        _gridConfig,
        _slotConfig,
        _capsuleConfig,
        _numberConfig,
        _lotsConfig,
        _lottoConfig,
        _registry,
      ];
      for (final symbol in unrelatedSymbols) {
        expect(checkProbe(_compatProbe, _artifact(sources, [symbol])),
            ['$_compatProbe $_forbiddenSymbol: $symbol']);
      }
      for (final converter in <String>[_gridZone, _slotZone]) {
        expect(
            checkProbe(
                _compatProbe,
                _artifact([
                  ...sources,
                  '/luckdraw/lib/src/compat/${converter}_compat.dart',
                ])),
            contains(contains(_forbiddenFile)));
      }
    });

    test('all games requires every game and excludes compat and testing', () {
      final sources = [
        _coreSource,
        for (final game in _gameZones) '/luckdraw/lib/src/$game/model.dart',
      ];
      expect(checkProbe(_all, _artifact(sources)), isEmpty);
      expect(
          checkProbe(_all,
              _artifact(sources, [_quad, _cubic, 'LuckyLeverSlotMachine'])),
          isEmpty);
      const unusedSymbols = ['QuartEasing', 'CurveEasing', _registry];
      for (final symbol in unusedSymbols) {
        expect(checkProbe(_all, _artifact(sources, [symbol])),
            ['$_all $_forbiddenSymbol: $symbol']);
      }
      expect(
          checkProbe(_all, _artifact(sources.sublist(0, sources.length - 1))),
          contains(contains('缺少源码区: lotto')));
      expect(
          checkProbe(
              _all,
              _artifact([
                ...sources,
                '/luckdraw/lib/src/compat/a.dart',
                '/luckdraw/lib/src/testing/a.dart',
              ], [
                _easingNames
              ])),
          hasLength(3));
      expect(checkProbe(_baseline, _artifact([])), isEmpty);
      expect(checkProbe(_baseline, _artifact([_coreSource])), isNotEmpty);
    });

    test('budgets accept placeholders and reject missing or malformed limits',
        () {
      final parsed = parseBudgets(jsonEncode(_budgets()));
      expect(parsed[_web]![_wheel], isNull);
      expect(parsed[_apk]!.length, kTreeshakeProbes.length);
      final calibrated = parseBudgets(jsonEncode(_budgets(_totalBytes)));
      expect(calibrated[_web]![_wheel], _totalBytes);
      for (final invalid in <Object?>[
        {},
        null,
        {_webLimit: -1},
        {_webLimit: 1.5},
        {_webLimit: '100'}
      ]) {
        final root = _budgets();
        (root[_web]! as Map<String, Object?>)[_wheel] = invalid;
        expect(() => parseBudgets(jsonEncode(root)), throwsFormatException);
      }
      expect(() => parseBudgets('{}'), throwsFormatException);
    });

    test('volume budgets fail above the limit and allow exact or null limits',
        () {
      expect(checkBudget(_wheel, _totalBytes, _totalBytes - 1).single,
          contains('超预算'));
      expect(checkBudget(_wheel, _totalBytes, _totalBytes), isEmpty);
      expect(checkBudget(_wheel, _totalBytes, null), isEmpty);
      expect(checkBudget(_wheel, -1, 0), isEmpty);
    });

    test('size relationships require each single game below sixty percent', () {
      expect(checkSizeRelations({_all: _totalBytes, _wheel: 59}), isEmpty);
      expect(checkSizeRelations({_all: _totalBytes, _wheel: 60}), hasLength(1));
      expect(
          checkSizeRelations({_all: _totalBytes, _wheel: 101}), hasLength(1));
      expect(checkSizeRelations({_wheel: 101}), isEmpty);
      expect(
          checkSizeRelations({_all: _totalBytes, _compatProbe: 101}), isEmpty);
    });

    test('checked in budgets cover both backends and every probe', () {
      final file = File('tool/treeshake/budgets.json').readAsStringSync();
      final budgets = parseBudgets(file);
      expect(file, contains('Web 首轮实测'));
      expect(budgets.keys, containsAll([_web, _apk]));
      for (final probes in budgets.values) {
        expect(probes.keys, containsAll(kTreeshakeProbes));
      }
    });
  });
}
