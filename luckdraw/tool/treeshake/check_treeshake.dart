import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'apk_support.dart';

/// TEST_STRATEGY §8.1 规定的探针；始终先构建基线。
const List<String> kTreeshakeProbes = [
  _baseline,
  _wheelProbe,
  _gridProbe,
  _slotProbe,
  _capsuleProbe,
  _numberWheelProbe,
  _lotsProbe,
  _lottoProbe,
  _compatWheel,
  _allGames,
];

/// 玩法源码区。
const List<String> _games = [
  _wheelZone,
  'grid',
  'slot',
  _capsuleZone,
  'number_wheel',
  'lots',
  _lottoZone,
];

/// 转盘源码区名。
const String _wheelZone = 'wheel';

/// 扭蛋机源码区名。
const String _capsuleZone = 'capsule';

/// 大乐透源码区名。
const String _lottoZone = 'lotto';

/// 转盘单玩法探针名。
const String _wheelProbe = 'wheel_only';

/// 九宫格单玩法探针名。
const String _gridProbe = 'grid_only';

/// 扭蛋机单玩法探针名。
const String _capsuleProbe = 'capsule_only';

/// 数字转盘单玩法探针名。
const String _numberWheelProbe = 'number_wheel_only';

/// 抽签单玩法探针名。
const String _lotsProbe = 'lots_only';

/// 大乐透单玩法探针名。
const String _lottoProbe = 'lotto_only';

/// 不带拉杆的老虎机探针名。
const String _slotProbe = 'slot_only';

/// sourcemap 来源字段。
const String _sources = 'sources';

/// sourcemap 符号字段。
const String _names = 'names';

/// APK 包分组节点名。
const String _packageGroup = 'package:luckdraw';

/// 探针命令行参数名。
const String _probeOption = 'probe';

/// 已有 APK 报告的命令行参数名。
const String _sizeJsonOption = 'size-json';

/// 预算 JSON 的根节点名。
const String _budgetLocation = 'budgets';

/// 显式关闭自动依赖解析。
const String _noPub = '--no-pub';

/// 禁止解析包示例工程。
const String _noExample = '--no-example';

/// Flutter 依赖管理子命令。
const String _pubCommand = 'pub';

/// 获取依赖的子命令。
const String _getCommand = 'get';

/// 源码 URI 的统一分隔符。
const String _slash = '/';

/// Windows 源码路径分隔符。
const String _backslash = '\\';

/// 未知探针的统一参数错误说明。
const String _unknownProbe = '未知探针';

/// 仅允许 compat 保留的上游缓动名称表。
const String _canvasEasingNames = 'kLuckyCanvasEasingNames';

/// 基线探针名。
const String _baseline = 'baseline';

/// 完整玩法探针名。
const String _allGames = 'all_games';

/// 单玩法探针后缀。
const String _onlySuffix = '_only';

/// 迁移转盘探针名。
const String _compatWheel = 'compat_wheel';

/// Web 后端名。
const String _web = 'web';

/// APK 后端名。
const String _apk = 'apk';

/// Web 预算字段。
const String _webBudget = 'maxDeltaGzipBytes';

/// APK 预算字段。
const String _apkBudget = 'maxLuckdrawBytes';

/// arm64 AOT 报告中的节点名称。
const String _apkAotName = 'libapp.so (Dart AOT)';

/// 最终报告的根节点名称。
const String _apkRootName = 'Root';

/// VM 树节点的种类字段。
const String _kind = 'k';

/// APK 报告的平台类型字段。
const String _type = 'type';

/// 本批唯一允许的 APK 架构。
const String _arm64 = 'arm64-v8a';

/// VM 数据叶节点的类型名称形状；类型集合由 VM 扩展，结构标记必须严格匹配。
final RegExp _apkDataName = RegExp(r'^<[A-Za-z][A-Za-z0-9_]*>$');

/// JSON 树子节点字段。
const String _children = 'children';

/// JSON 树名字字段。
const String _name = 'n';

/// JSON 树字节数字段。
const String _value = 'value';

/// 包库 URI 前缀；必须带斜杠，避免误识别 luckdraw_extra。
const String _packagePrefix = 'package:luckdraw/';

/// 源码文件后缀。
const String _dartSuffix = '.dart';

/// 包内源码路径的统一前缀。
const String _sourcePrefix = '/luckdraw/lib/';

/// wheel 玩法受检查的类型符号。
const Set<String> _wheelSymbols = {
  'LuckyWheel',
  'WheelBlock',
  'WheelBlockImage',
  'WheelBlockLayout',
  'WheelButton',
  'WheelButtonLayout',
  'WheelCanvasRenderer',
  'WheelConfig',
  'WheelController',
  'WheelFrame',
  'WheelGame',
  'WheelLayout',
  'WheelMotion',
  'WheelOptions',
  'WheelPainter',
  'WheelPrize',
  'WheelPrizePaintContext',
  'WheelSector',
  'WheelSectorAngles',
  'WheelStyle',
};

/// grid 玩法受检查的类型符号。
const Set<String> _gridSymbols = {
  'GridBlockLayout',
  'GridButton',
  'GridCanvasRenderer',
  'GridCell',
  'GridCellGeometry',
  'GridCellVisual',
  'GridConfig',
  'GridController',
  'GridFrame',
  'GridGame',
  'GridImage',
  'GridLayout',
  'GridMotion',
  'GridOptions',
  'GridPainter',
  'GridPrize',
  'GridStyle',
  'LuckyGrid',
};

/// slot 玩法受检查的类型符号。
const Set<String> _slotSymbols = {
  'LuckySlotMachine',
  'SlotAtlas',
  'SlotBlockLayout',
  'SlotCanvasRenderer',
  'SlotCellContent',
  'SlotConfig',
  'SlotController',
  'SlotFrame',
  'SlotGame',
  'SlotLayout',
  'SlotMode',
  'SlotMotion',
  'SlotOptions',
  'SlotPainter',
  'SlotPayline',
  'SlotPaylineLayer',
  'SlotPrize',
  'SlotReel',
  'SlotReelLayout',
  'SlotResult',
  'SlotStyle',
};

/// capsule 玩法受检查的类型符号。
const Set<String> _capsuleSymbols = {
  'CapsuleCanvasRenderer',
  'CapsuleConfig',
  'CapsuleController',
  'CapsuleFrame',
  'CapsuleGame',
  'CapsuleLayout',
  'CapsuleMotion',
  'CapsuleOptions',
  'CapsulePainter',
  'CapsulePictures',
  'CapsulePrize',
  'CapsuleStage',
  'CapsuleStyle',
  'LuckyCapsuleMachine',
};

/// number_wheel 玩法受检查的类型符号。
const Set<String> _numberWheelSymbols = {
  'LuckyNumberWheel',
  'NumberWheelCanvasRenderer',
  'NumberWheelConfig',
  'NumberWheelController',
  'NumberWheelFrame',
  'NumberWheelGame',
  'NumberWheelLayout',
  'NumberWheelMotion',
  'NumberWheelOptions',
  'NumberWheelPainter',
  'NumberWheelPocket',
  'NumberWheelStyle',
};

/// lots 玩法受检查的类型符号。
const Set<String> _lotsSymbols = {
  'LotsCanvasRenderer',
  'LotsConfig',
  'LotsController',
  'LotsFrame',
  'LotsGame',
  'LotsLayout',
  'LotsMotion',
  'LotsOptions',
  'LotsPainter',
  'LotsStage',
  'LotsStick',
  'LotsStyle',
  'LuckyLots',
};

/// 物理碰撞模式的类型符号；只应出现在使用它的扭蛋机与大乐透产物里。
const Set<String> _physicsSymbols = {
  'LuckyCircleWorld',
  'LuckyPhysicsDriver',
  'LuckyStirArms',
};

/// lotto 玩法受检查的类型符号。
const Set<String> _lottoSymbols = {
  'LottoCanvasRenderer',
  'LottoConfig',
  'LottoController',
  'LottoDraw',
  'LottoDrumLayout',
  'LottoFrame',
  'LottoGame',
  'LottoLayout',
  'LottoMotion',
  'LottoOptions',
  'LottoPainter',
  'LottoPool',
  'LottoResult',
  'LottoSampler',
  'LottoStyle',
  'LuckyLotto',
  'UniformLottoSampler',
};

/// 拉杆玩法的独立符号，纯老虎机探针不允许保留。
const Set<String> _leverSymbols = {
  'LuckyLeverSlotMachine',
  'LeverOptions',
  'LeverSide',
  'LeverPainter',
};

/// 默认二次缓动符号。
const String _quadSymbol = 'QuadEasing';

/// 抽签默认翻卡与大乐透飞行动画依赖的三次缓动符号。
const String _cubicSymbol = 'CubicEasing';

/// 三个互不调用的迁移转换函数。
const String _wheelConverter = 'wheelFromLuckyCanvasConfig';

/// 不允许转盘迁移探针保留的九宫格转换函数。
const String _gridConverter = 'gridFromLuckyCanvasConfig';

/// 不允许转盘迁移探针保留的老虎机转换函数。
const String _slotConverter = 'slotFromLuckyCanvasConfig';

/// compat 名称表可能引用的全部上游缓动类型。
const Set<String> _canvasEasingSymbols = {
  _quadSymbol,
  _cubicSymbol,
  'QuartEasing',
  'QuintEasing',
  'SineEasing',
  'ExpoEasing',
  'CircEasing',
};

/// 有限的受检查符号全集；不把 Flutter 或应用自有符号当作泄漏。
const Set<String> _checkedSymbols = {
  ..._canvasEasingSymbols,
  'CurveEasing',
  'LuckyGameRegistry',
  _canvasEasingNames,
  _wheelConverter,
  _gridConverter,
  _slotConverter,
  ..._leverSymbols,
  ..._wheelSymbols,
  ..._gridSymbols,
  ..._slotSymbols,
  ..._capsuleSymbols,
  ..._numberWheelSymbols,
  ..._lotsSymbols,
  ..._lottoSymbols,
  ..._physicsSymbols,
};

/// 各探针显式允许的符号；全集减去允许集就是该探针的禁符号集。
const Map<String, Set<String>> _allowedSymbols = {
  _baseline: {},
  _wheelProbe: {_quadSymbol, ..._wheelSymbols},
  _gridProbe: {_quadSymbol, ..._gridSymbols},
  _slotProbe: {_quadSymbol, ..._slotSymbols},
  _capsuleProbe: {_quadSymbol, ..._capsuleSymbols, ..._physicsSymbols},
  _numberWheelProbe: {_quadSymbol, ..._numberWheelSymbols},
  _lotsProbe: {_quadSymbol, _cubicSymbol, ..._lotsSymbols},
  _lottoProbe: {
    _quadSymbol,
    _cubicSymbol,
    ..._lottoSymbols,
    ..._physicsSymbols,
  },
  _compatWheel: {
    ..._canvasEasingSymbols,
    _canvasEasingNames,
    _wheelConverter,
    ..._wheelSymbols,
  },
  _allGames: {
    _quadSymbol,
    _cubicSymbol,
    ..._leverSymbols,
    ..._wheelSymbols,
    ..._gridSymbols,
    ..._slotSymbols,
    ..._capsuleSymbols,
    ..._numberWheelSymbols,
    ..._lotsSymbols,
    ..._lottoSymbols,
    ..._physicsSymbols,
  },
};

/// 单玩法占完整玩法增量体积的上限（TEST_STRATEGY §8.3）。
const double _singleGameRatio = 0.6;

/// 首轮预算校准系数（TEST_STRATEGY §8.3）。
const double _budgetMargin = 1.1;

/// 单条 Flutter 命令的最长执行时间。
const Duration _commandTimeout = Duration(minutes: 5);

/// 探针目录内的编译产物。
const String _webOutput = 'build/web/main.dart.js';

/// 临时探针的包清单文件名。
const String _pubspecFile = 'pubspec.yaml';

/// 探针主文件相对路径。
const String _mainFile = 'lib/main.dart';

/// 保留的包源码、符号与可选 APK 包字节数。
final class TreeshakeArtifact {
  /// 创建不可变的解析结果；[sources] 使用统一的包内路径。
  TreeshakeArtifact({
    required Set<String> sources,
    required Set<String> names,
    this.luckdrawBytes,
  })  : sources = Set.unmodifiable(sources),
        names = Set.unmodifiable(names);

  /// 产物中保留的 luckdraw 源文件路径。
  final Set<String> sources;

  /// 产物中保留的符号名。
  final Set<String> names;

  /// APK 中 luckdraw 子树的字节数；Web 结果为 null。
  final int? luckdrawBytes;
}

/// 校验并返回 JSON 对象；结构变化时抛出带位置的 [FormatException]。
Map<String, Object?> _object(Object? value, String location) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$location 必须是 JSON 对象');
  }
  return value;
}

/// 返回合法的非负整数字节数，否则显式失败。
int _bytes(Object? value, String location) {
  if (value is! int || value < 0) {
    throw FormatException('$location 必须是非负整数字节数');
  }
  return value;
}

/// 返回字符串数组；字段缺失、数组项类型错误均不放行。
List<String> _strings(Object? value, String location) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw FormatException('$location 必须是字符串数组');
  }
  return value.cast<String>();
}

/// 统一 URI、Windows 分隔符和点路径；仅返回本包 src 路径。
String? _sourcePath(String source) {
  var path = Uri.decodeFull(source).replaceAll(_backslash, _slash);
  if (path.startsWith(_packagePrefix)) {
    path = '$_sourcePrefix${path.substring(_packagePrefix.length)}';
  }
  final parts = <String>[];
  for (final part in path.split(_slash)) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..' && parts.isNotEmpty) {
      parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  path = '/${parts.join(_slash)}';
  final start = path.indexOf('${_sourcePrefix}src/');
  return start < 0 ? null : path.substring(start);
}

/// 解析 v3 sourcemap 的 sources/sourceRoot 与 names；无效结构抛异常。
///
/// [json] 为 JSON 原文。返回仅属于 luckdraw 的源码路径与全部符号，
/// 例如 `parseWebSourcemap(json).sources`；不依赖真实构建或文件系统。
TreeshakeArtifact parseWebSourcemap(String json) {
  final root = _object(jsonDecode(json), 'sourcemap');
  if (root['version'] != 3 || root['mappings'] is! String) {
    throw const FormatException('sourcemap 必须是含 mappings 的 v3 普通映射');
  }
  final sourceRoot = root['sourceRoot'];
  if (sourceRoot != null && sourceRoot is! String) {
    throw const FormatException('sourceRoot 必须是字符串');
  }
  final sources = <String>{};
  for (final source in _strings(root[_sources], _sources)) {
    final absolute = source.contains(':') ||
        source.startsWith(_slash) ||
        source.startsWith(_backslash);
    final path = _sourcePath(absolute || sourceRoot == null || sourceRoot == ''
        ? source
        : '$sourceRoot/$source');
    if (path != null) sources.add(path);
  }
  return TreeshakeArtifact(
    sources: sources,
    names: _strings(root[_names], _names).toSet(),
  );
}

/// 解析 APK analyze-size 的 n/children/value 树，返回包库及无重复字节和。
///
/// [json] 为原文，支持 package:luckdraw 分组和完整库 URI 节点；
/// 缺包、缺库或非法节点均抛 [FormatException]；容器体积不与子树重复累计。
/// 例：`parseApkSizeJson(json).luckdrawBytes`。
TreeshakeArtifact parseApkSizeJson(String json) {
  return _parseApkTree(json, allowMissingPackage: false);
}

/// 解析严格节点树；只有已验证过 arm64 报告的 baseline 允许无包。
TreeshakeArtifact _parseApkTree(String json,
    {required bool allowMissingPackage}) {
  final sources = <String>{};
  final names = <String>{};
  var foundPackage = false;
  var total = 0;

  /// 校验一棵完整树并返回其字节数，避免父子重复计数。
  int visit(Object? raw, String location,
      {bool inPackage = false, bool inLibrary = false, String? directory}) {
    final node = _object(raw, location);
    final name = node[_name];
    if (name is! String || name.isEmpty) {
      throw FormatException('$location.n 必须是非空字符串');
    }
    final packageNode =
        name == _packageGroup || name.startsWith(_packagePrefix);
    final belongs = inPackage || packageNode;
    if (packageNode) foundPackage = true;
    var library = inLibrary;
    if (belongs) {
      names.add(name);
      final uri = name.startsWith(_packagePrefix) || name == _packageGroup
          ? name
          : '${directory ?? _packageGroup}/$name';
      final path = _sourcePath(uri);
      if (!inLibrary && path != null && path.endsWith(_dartSuffix)) {
        library = true;
        if (!sources.add(path)) {
          throw FormatException('重复的 luckdraw 库: $path');
        }
      }
      final dataLeaf = _apkDataName.hasMatch(name) &&
          node[_kind] == 's' &&
          node['t'] == 'D' &&
          !node.containsKey(_children);
      if (!library && name != _packageGroup && !dataLeaf) {
        // vm_snapshot_analysis 用 k=p 目录逐层压缩 URI，仍要求最终到达库。
        final children = node[_children];
        if (node[_kind] != 'p' ||
            children is! List<Object?> ||
            children.isEmpty ||
            !(uri == '${_packagePrefix}src' || path != null)) {
          throw FormatException('$location 无法识别 luckdraw 库路径: $name');
        }
      }
      if (!library && !dataLeaf) directory = uri;
    }
    final rawChildren = node[_children];
    if (node.containsKey(_value)) _bytes(node[_value], '$location.value');
    var size = 0;
    if (node.containsKey(_children)) {
      if (rawChildren is! List<Object?> || rawChildren.isEmpty) {
        throw FormatException('$location.children 必须是非空节点数组');
      }
      for (var i = 0; i < rawChildren.length; i++) {
        size += visit(rawChildren[i], '$location.children[$i]',
            inPackage: belongs, inLibrary: library, directory: directory);
      }
    } else {
      size = _bytes(node[_value], '$location.value');
    }
    if (packageNode && !inPackage) total += size;
    return size;
  }

  visit(jsonDecode(json), _apk);
  if ((!foundPackage || sources.isEmpty) &&
      !(allowMissingPackage && !foundPackage && sources.isEmpty)) {
    throw const FormatException('APK JSON 未找到预期的 package:luckdraw 库子树');
  }
  return TreeshakeArtifact(
      sources: sources, names: names, luckdrawBytes: total);
}

/// APK 报告的 AOT 解析结果及两种不同口径的总字节数。
final class TreeshakeApkBuild {
  /// 创建已通过结构自检的 [artifact]、AOT 归属大小及压缩条目大小。
  const TreeshakeApkBuild(this.artifact, this.dartBytes, this.apkBytes);

  /// luckdraw 库、符号及包字节数。
  final TreeshakeArtifact artifact;

  /// arm64 AOT 子树叶节点总和（解压后可归属的 Dart 大小）。
  final int dartBytes;

  /// 报告内压缩条目大小合计，不含 ZIP 目录，不与 Dart 大小混用。
  final int apkBytes;
}

/// 严格解析 Flutter APK 报告，要求 Root/lib/arm64-v8a/libapp.so AOT 树。
///
/// [json] 为最终分析报告；[baseline] 仅在空白探针时为 true，允许没有
/// luckdraw 包，但仍完整校验 APK 类型、架构、非空 AOT 及每个树节点。
/// 返回包大小和可归属 AOT 总大小，例如 `parseApkReport(json).dartBytes`。
TreeshakeApkBuild parseApkReport(String json, {bool baseline = false}) {
  final root = _object(jsonDecode(json), 'APK report');
  if (root[_type] != _apk || root[_name] != _apkRootName) {
    throw const FormatException('必须是 type=apk 的 Root 分析报告');
  }
  _bytes(root[_value], 'Root.value');

  /// 找到唯一指定名称的直接子节点，拒绝重复及错误架构。
  Map<String, Object?> child(Map<String, Object?> node, String name) {
    final children = node[_children];
    if (children is! List<Object?>) {
      throw FormatException('$name 的父节点缺少 children');
    }
    final matches = children
        .map((raw) => _object(raw, name))
        .where((entry) => entry[_name] == name)
        .toList();
    if (matches.length != 1) throw FormatException('缺少或重复节点: $name');
    return matches.single;
  }

  final lib = child(root, 'lib');
  final arch = child(lib, _arm64);
  if ((lib[_children]! as List<Object?>).length != 1) {
    throw const FormatException('APK 必须只含 android-arm64');
  }
  final aot = child(arch, _apkAotName);
  if (aot[_children] is! List<Object?> ||
      (aot[_children]! as List<Object?>).isEmpty) {
    throw const FormatException('arm64 报告缺少非空 Dart AOT 明细');
  }
  final artifact = _parseApkTree(json, allowMissingPackage: baseline);

  /// 累加叶节点大小，不累计包含 children 的父节点 value。
  int sum(Object? raw) {
    final node = _object(raw, 'AOT');
    final children = node[_children];
    return children is List<Object?>
        ? children.fold<int>(0, (total, child) => total + sum(child))
        : _bytes(node[_value], 'AOT.value');
  }

  final dartBytes = sum(aot);
  if (dartBytes == 0) throw const FormatException('Dart AOT 总大小必须为正');

  /// AOT 节点展开后仍沿用原始压缩 value；Root.value 在 Flutter 中为零。
  int compressed(Object? raw) {
    final node = _object(raw, 'APK entries');
    final children = node[_children];
    return node[_name] == _apkAotName || children == null
        ? _bytes(node[_value], 'APK entry.value')
        : (children as List<Object?>)
            .fold<int>(0, (total, child) => total + compressed(child));
  }

  return TreeshakeApkBuild(artifact, dartBytes, compressed(root));
}

/// 按 §8.2 检查 [probe] 的 [artifact]，返回全部违规；空列表代表通过。
///
/// 例：`checkProbe(_wheelProbe, parseWebSourcemap(json))`；
/// 未知探针抛 [ArgumentError]，必须出现的项目只检查目录。
List<String> checkProbe(String probe, TreeshakeArtifact artifact) {
  if (!kTreeshakeProbes.contains(probe)) {
    throw ArgumentError.value(probe, _probeOption, _unknownProbe);
  }
  final errors = <String>[];
  if (probe == _baseline) {
    if (artifact.sources.isNotEmpty) errors.add('baseline 保留了 luckdraw 源码');
    errors.addAll(_checkSymbols(probe, artifact.names));
    return errors;
  }
  final zones = probe == _allGames
      ? _games.toSet()
      : {
          probe == _compatWheel
              ? _wheelZone
              : probe.replaceFirst(_onlySuffix, '')
        };
  final required = {'core', ...zones, if (probe == _compatWheel) 'compat'};
  for (final zone in required) {
    if (!artifact.sources.any((path) => path.contains('/lib/src/$zone/'))) {
      errors.add('$probe 缺少源码区: $zone');
    }
  }
  final forbidden = <String>{
    for (final game in _games.where((game) => !zones.contains(game)))
      '/lib/src/$game/',
    if (probe != _compatWheel) '/lib/src/compat/',
    '/lib/src/testing/',
    if (probe != _allGames &&
        !zones.contains(_capsuleZone) &&
        !zones.contains(_lottoZone) &&
        probe != _compatWheel)
      '/lib/src/core/kinematics/',
    if (probe == _slotProbe) '/lib/src/slot/lever/',
    if (probe == _compatWheel) ...[
      '/lib/src/compat/grid_compat.dart',
      '/lib/src/compat/slot_compat.dart',
    ],
  };
  for (final path in artifact.sources) {
    if (forbidden.any(path.contains)) errors.add('$probe 禁止的源文件: $path');
  }
  errors.addAll(_checkSymbols(probe, artifact.names));
  return errors;
}

/// 对全部探针执行同一差集规则，符号只做禁止检查以容忍编译器内联。
List<String> _checkSymbols(String probe, Set<String> names) {
  final errors = <String>[];
  final symbols = _checkedSymbols.difference(_allowedSymbols[probe]!);
  for (final symbol in symbols) {
    final pattern = RegExp('(^|[^A-Za-z0-9_\$])${RegExp.escape(symbol)}'
        r'($|[^A-Za-z0-9_$])');
    for (final name in names.where(pattern.hasMatch)) {
      errors.add('$probe 禁止的符号: $name');
    }
  }
  return errors;
}

/// 解析全部探针的双后端预算；null 表示待首轮实测回填。
///
/// [json] 为 budgets.json 原文；缺条目、负数或非整数字节数均抛异常。
/// 返回以 `web`/`apk` 为键、探针名到可空字节数的映射。
Map<String, Map<String, int?>> parseBudgets(String json) {
  final root = _object(jsonDecode(json), _budgetLocation);
  final result = <String, Map<String, int?>>{};
  for (final backend in [_web, _apk]) {
    final entries = _object(root[backend], 'budgets.$backend');
    final field = backend == _web ? _webBudget : _apkBudget;
    result[backend] = {};
    for (final probe in kTreeshakeProbes) {
      final entry = _object(entries[probe], '$backend.$probe');
      if (!entry.containsKey(field)) {
        throw FormatException('$backend.$probe 缺少 $field');
      }
      final value = entry[field];
      result[backend]![probe] =
          value == null ? null : _bytes(value, '$backend.$probe.$field');
    }
  }
  return result;
}

/// 检查 [measuredBytes] 是否超过 [limit]；null 预算仅报告未校准。
///
/// 返回违规列表，例如 `checkBudget(_wheelProbe, 100, 90)` 返回一条错误。
List<String> checkBudget(String probe, int measuredBytes, int? limit) =>
    limit != null && measuredBytes > limit
        ? ['$probe 超预算: $measuredBytes > $limit bytes']
        : [];

/// 对同时采集的 gzip 增量做关系检查；缺少 all_games 时不比较。
///
/// [deltas] 的值必须减去基线；每个 *_only 必须严格低于完整玩法的 60%。
List<String> checkSizeRelations(Map<String, int> deltas) {
  final all = deltas[_allGames];
  if (all == null) return [];
  return [
    for (final entry in deltas.entries)
      if (entry.key.endsWith(_onlySuffix) &&
          entry.value >= all * _singleGameRatio)
        '${entry.key} 增量 ${entry.value} 必须 < all_games($all) × $_singleGameRatio',
  ];
}

/// 由 [rawBytes] 和 [gzipBytes] 记录一个 Web 探针的大小。
final class TreeshakeWebBuild {
  /// 创建产物解析结果与压缩前后的字节数。
  const TreeshakeWebBuild(this.artifact, this.rawBytes, this.gzipBytes);

  /// sourcemap 中的保留项目。
  final TreeshakeArtifact artifact;

  /// main.dart.js 的原始大小。
  final int rawBytes;

  /// GZipCodec(level: 9) 压缩后的大小。
  final int gzipBytes;
}

/// 返回隔离工程清单；[packageRoot] 为本包绝对路径，不添加第三方依赖。
///
/// 路径用 JSON 双引号转义，兼容 Windows、空格及 YAML 特殊字符。
String probePubspec(String packageRoot) => '''
name: luckdraw_treeshake_probe
publish_to: none
environment:
  sdk: '>=3.5.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  luckdraw:
    path: ${jsonEncode(packageRoot.replaceAll(_backslash, _slash))}
''';

/// 返回串行 Web 构建计划；第二步离线失败时调用方应在线重试一次。
///
/// [directory] 是系统临时目录内的独立工程绝对路径；不包含 APK/Gradle。
List<List<String>> webBuildCommands(String directory) => [
      [
        'create',
        '--platforms=web',
        '--empty',
        _noPub,
        '--project-name=luckdraw_treeshake_probe',
        directory
      ],
      [_pubCommand, _getCommand, '--offline', _noExample],
      ['build', _web, '--release', '--source-maps', _noPub],
    ];

/// Flutter 命令执行器；返回退出码，[directory] 是命令工作目录。
typedef TreeshakeCommand = Future<int> Function(
    List<String> arguments, String directory);

/// 清理自己启动的 Flutter 进程的后代；不按可执行文件名批量结束进程。
Future<void> _cleanupDescendants(int parentPid) async {
  if (!Platform.isWindows) return;
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    '\$tree = @(Get-CimInstance Win32_Process); '
        '\$owned = [System.Collections.Generic.List[int]]::new(); '
        '\$owned.Add($parentPid); '
        'do { \$added = \$false; foreach (\$item in \$tree) { '
        'if (\$owned.Contains([int]\$item.ParentProcessId) -and '
        '-not \$owned.Contains([int]\$item.ProcessId)) { '
        '\$owned.Add([int]\$item.ProcessId); \$added = \$true } } '
        '} while (\$added); '
        '\$owned | Where-Object { \$_ -ne $parentPid } | '
        'ForEach-Object { Stop-Process -Id \$_ -Force -ErrorAction SilentlyContinue }',
  ]);
  if (result.exitCode != 0) {
    throw StateError('进程后代清理失败: ${result.stderr}');
  }
}

/// 执行单条 Flutter 命令；五分钟超时结束该命令树并显式失败。
Future<int> _flutter(List<String> arguments, String directory) async {
  final process = await Process.start('flutter', arguments,
      workingDirectory: directory, runInShell: Platform.isWindows);
  final output = Future.wait([
    stdout.addStream(process.stdout),
    stderr.addStream(process.stderr),
  ]);
  try {
    return await process.exitCode.timeout(_commandTimeout);
  } on TimeoutException {
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
    }
    process.kill();
    throw StateError('Flutter 命令超过五分钟: $arguments');
  } finally {
    await _cleanupDescendants(process.pid);
    await output.timeout(const Duration(seconds: 10));
  }
}

/// 在系统临时目录串行构建一个 [probe]，成功或失败均删除隔离工程。
///
/// [packageRoot] 必须是本包目录；[command] 可注入假执行器验证流程。
/// 返回大小和 sourcemap 解析结果；失败抛异常，不进行 APK 构建。
Future<TreeshakeWebBuild> buildWebProbe({
  required String probe,
  required Directory packageRoot,
  TreeshakeCommand? command,
}) async {
  if (!kTreeshakeProbes.contains(probe)) {
    throw ArgumentError.value(probe, _probeOption, _unknownProbe);
  }
  final execute = command ?? _flutter;
  final tempRoot = Directory('${Directory.systemTemp.path}/ldts')
    ..createSync(recursive: true);
  final workspace = tempRoot.createTempSync('ts_');
  final project = Directory('${workspace.path}/probe');
  final commands = webBuildCommands(project.path);
  try {
    if (await execute(commands.first, workspace.path) != 0) {
      throw StateError('$probe 创建工程失败');
    }
    File('${project.path}/$_pubspecFile')
        .writeAsStringSync(probePubspec(packageRoot.absolute.path));
    File('${project.path}/$_mainFile').writeAsStringSync(
        File('${packageRoot.path}/tool/treeshake/probes/$probe/main.dart')
            .readAsStringSync());
    if (await execute(commands[1], project.path) != 0 &&
        await execute([_pubCommand, _getCommand, _noExample], project.path) !=
            0) {
      throw StateError('$probe pub get 离线及在线均失败');
    }
    if (await execute(commands.last, project.path) != 0) {
      throw StateError('$probe Web 构建失败');
    }
    final js = File('${project.path}/$_webOutput').readAsBytesSync();
    final artifact = parseWebSourcemap(
        File('${project.path}/$_webOutput.map').readAsStringSync());
    return TreeshakeWebBuild(
        artifact, js.length, GZipCodec(level: 9).encode(js).length);
  } finally {
    final resolved = workspace.absolute.path;
    final parent = tempRoot.absolute.path;
    if (!resolved.startsWith('$parent${Platform.pathSeparator}')) {
      throw StateError('拒绝清理系统探针目录之外的路径: $resolved');
    }
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
  }
}

/// 检查构建前可用内存；Windows 的 KiB 值必须达到 4 GiB。
Future<void> _checkApkMemory() async {
  if (!Platform.isWindows) return;
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    '(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory',
  ]);
  final free = int.tryParse('${result.stdout}'.trim());
  if (result.exitCode != 0 || free == null || free < 4 * 1024 * 1024) {
    throw StateError('APK 构建至少需要 4 GiB 空闲内存，实际 KiB=$free');
  }
  stdout.writeln('APK FreePhysicalMemory=$free KiB');
}

/// 结束带有当前工程 JVM 标记的守护进程，排除用户 IDE 和其它构建。
Future<void> _cleanupApkDaemons(String owner) async {
  final result = Platform.isWindows
      ? await Process.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'ConvertTo-Json -Compress -InputObject @(Get-CimInstance Win32_Process | '
              'Where-Object { \$_.Name -match "^java(w)?(.exe)?\$" } | '
              'Select-Object ProcessId,CommandLine)',
        ])
      : await Process.run('ps', ['-eo', 'pid=,args=']);
  if (result.exitCode != 0) throw StateError('无法检查 APK 守护进程: ${result.stderr}');
  final processes = <(int, String)>[];
  if (Platform.isWindows) {
    final decoded = jsonDecode('${result.stdout}') as List<Object?>;
    for (final raw in decoded) {
      final process = _object(raw, 'process');
      processes.add((
        process['ProcessId']! as int,
        process['CommandLine'] as String? ?? ''
      ));
    }
  } else {
    for (final line in const LineSplitter().convert('${result.stdout}')) {
      final match = RegExp(r'^\s*(\d+)\s+(.*)$').firstMatch(line);
      if (match != null) processes.add((int.parse(match[1]!), match[2]!));
    }
  }
  for (final (processId, line) in processes) {
    if (!isOwnedApkDaemon(line, owner)) continue;
    stdout.writeln('清理 APK 自有进程 PID=$processId: $line');
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/PID', '$processId', '/T', '/F']);
    } else {
      Process.killPid(processId, ProcessSignal.sigkill);
    }
  }
}

/// 串行构建独立的 arm64 [probe] 并严格解析报告；不需要设备。
///
/// [packageRoot] 是本包路径；[command] 与 [devtoolsDirectory] 可供测试注入。
/// [reportCopy] 可保留原始报告用于审计；成功失败均清理临时工程和自有进程。
Future<TreeshakeApkBuild> buildApkProbe({
  required String probe,
  required Directory packageRoot,
  TreeshakeCommand? command,
  Directory? devtoolsDirectory,
  File? reportCopy,
}) async {
  if (!kTreeshakeProbes.contains(probe)) {
    throw ArgumentError.value(probe, _probeOption, _unknownProbe);
  }
  if (command == null) await _checkApkMemory();
  final execute = command ?? _flutter;
  final tempRoot = Directory('${Directory.systemTemp.path}/ldts')
    ..createSync(recursive: true);
  final workspace = tempRoot.createTempSync('apk_');
  final owner =
      workspace.uri.pathSegments.where((part) => part.isNotEmpty).last;
  final project = Directory('${workspace.path}/probe');
  final reports = devtoolsDirectory ??
      Directory(
          '${Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME']}/.flutter-devtools');
  final roots = [reports, Directory('${project.path}/build')];
  final plan = apkBuildCommands(project.path);
  String? createdReport;
  try {
    if (await execute(plan.first, workspace.path) != 0) {
      throw StateError('$probe 创建 Android 工程失败');
    }
    File('${project.path}/$_pubspecFile')
        .writeAsStringSync(probePubspec(packageRoot.absolute.path));
    File('${project.path}/$_mainFile').writeAsStringSync(
        File('${packageRoot.path}/tool/treeshake/probes/$probe/main.dart')
            .readAsStringSync());
    final properties = File('${project.path}/android/gradle.properties');
    properties.writeAsStringSync(
        apkGradleProperties(properties.readAsStringSync(), owner));
    final analysis = File('${project.path}/analysis_options.yaml');
    final originalAnalysis =
        analysis.existsSync() ? analysis.readAsStringSync() : null;
    var dependenciesReady = false;
    for (final args in [
      plan[1],
      [_pubCommand, _getCommand, _noExample]
    ]) {
      try {
        dependenciesReady = await execute(args, project.path) == 0;
      } finally {
        if (originalAnalysis != null) {
          analysis.writeAsStringSync(originalAnalysis);
        } else if (analysis.existsSync()) {
          analysis.deleteSync();
        }
      }
      if (dependenciesReady) break;
    }
    if (!dependenciesReady) throw StateError('$probe pub get 离线及在线均失败');
    final before = apkReportSnapshot(roots);
    try {
      if (await execute(plan.last, project.path) != 0) {
        throw StateError('$probe APK 构建失败');
      }
    } finally {
      if (command == null) await _cleanupApkDaemons(owner);
    }
    createdReport = discoverApkReport(before, apkReportSnapshot(roots));
    final json = File(createdReport).readAsStringSync();
    if (command == null) stdout.writeln('$probe APK report=$createdReport');
    if (reportCopy != null) {
      reportCopy.parent.createSync(recursive: true);
      reportCopy.writeAsStringSync(json);
    }
    return parseApkReport(json, baseline: probe == _baseline);
  } finally {
    // 仅删除本次唯一发现的新报告，不触碰历史报告或并行构建的报告。
    if (createdReport != null && File(createdReport).existsSync()) {
      File(createdReport).deleteSync();
    }
    final resolved = workspace.absolute.path;
    if (!resolved
        .startsWith('${tempRoot.absolute.path}${Platform.pathSeparator}')) {
      throw StateError('拒绝清理系统探针目录之外的路径: $resolved');
    }
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
  }
}

/// 返回串行探针列表，始终先运行一次 baseline。
///
/// [selection] 为空时返回全部探针；否则接受逗号分隔的已知且不重复的名称，
/// 如 `treeshakeProbeSelection('wheel_only,grid_only')`；非法选择显式失败。
List<String> treeshakeProbeSelection(String? selection) {
  if (selection == null) return List.of(kTreeshakeProbes);
  final probes = selection.split(',');
  if (probes.toSet().length != probes.length ||
      probes.any((probe) => !kTreeshakeProbes.contains(probe))) {
    throw FormatException('未知或重复 probe: $selection');
  }
  return [_baseline, ...probes.where((probe) => probe != _baseline)];
}

/// 串行构建 Web/APK 探针，或显式检查已有 APK 报告。
///
/// 无参数时依次构建十个探针；`--probe=wheel_only` 额外采集 baseline。
/// APK 使用 `--backend=apk` 自动构建；`--probe=wheel_only,grid_only` 限定集合。
/// `--update-budgets` 用实测值乘 1.1 校准本次采集的预算。
Future<void> main(List<String> args) async {
  try {
    final options = <String, String>{};
    var update = false;
    for (final arg in args) {
      if (arg == '--update-budgets') {
        update = true;
      } else {
        final match =
            RegExp(r'^--(backend|probe|size-json)=(.+)$').firstMatch(arg);
        if (match == null) throw FormatException('未知参数: $arg');
        if (options.containsKey(match[1])) {
          throw FormatException('重复参数: ${match[1]}');
        }
        options[match[1]!] = match[2]!;
      }
    }
    final backend = options['backend'] ?? _web;
    if (backend != _web && backend != _apk) {
      throw FormatException('未知 backend: $backend');
    }
    final selected = options[_probeOption];
    final selectedProbes = treeshakeProbeSelection(selected);
    final packageRoot = Directory.fromUri(Platform.script.resolve('../../'));
    final budgetFile = File('${packageRoot.path}/tool/treeshake/budgets.json');
    final budgetJson =
        _object(jsonDecode(budgetFile.readAsStringSync()), _budgetLocation);
    final budgets = parseBudgets(jsonEncode(budgetJson));
    final measured = <String, int>{};
    final errors = <String>[];
    if (backend == _apk) {
      final report = options[_sizeJsonOption];
      if (report != null) {
        if (selected == null || selected.contains(',')) {
          throw const FormatException('--size-json 必须指定 --probe');
        }
        final build = parseApkReport(File(report).readAsStringSync(),
            baseline: selected == _baseline);
        errors.addAll(checkProbe(selected, build.artifact));
        measured[selected] = build.artifact.luckdrawBytes!;
      } else {
        final probes = selectedProbes;
        final records = <String, Object?>{};
        final evidence = Directory('${packageRoot.path}/build/treeshake-apk')
          ..createSync(recursive: true);
        for (final probe in probes) {
          final watch = Stopwatch()..start();
          final build = await buildApkProbe(
              probe: probe,
              packageRoot: packageRoot,
              reportCopy: File('${evidence.path}/$probe.json'));
          final violations = checkProbe(probe, build.artifact);
          errors.addAll(violations);
          measured[probe] = build.artifact.luckdrawBytes!;
          records[probe] = {
            'measuredLuckdrawBytes': build.artifact.luckdrawBytes,
            'measuredDartAotBytes': build.dartBytes,
            'measuredCompressedEntryBytes': build.apkBytes,
            'elapsedMilliseconds': watch.elapsedMilliseconds,
            'sources': build.artifact.sources.toList()..sort(),
            'names': build.artifact.names.toList()..sort(),
            'violations': violations,
          };
          File('${evidence.path}/measurements.json').writeAsStringSync(
              '${const JsonEncoder.withIndent('  ').convert(records)}\n');
          stdout.writeln('$probe luckdraw=${build.artifact.luckdrawBytes} '
              'dartAot=${build.dartBytes} compressedEntries=${build.apkBytes}');
        }
      }
    } else {
      if (options.containsKey(_sizeJsonOption)) {
        throw const FormatException('--size-json 仅适用于 APK');
      }
      TreeshakeWebBuild? baseline;
      final probes = selectedProbes;
      for (final probe in probes) {
        final build =
            await buildWebProbe(probe: probe, packageRoot: packageRoot);
        errors.addAll(checkProbe(probe, build.artifact));
        if (probe == _baseline) baseline = build;
        final rawDelta = build.rawBytes - baseline!.rawBytes;
        final gzipDelta = build.gzipBytes - baseline.gzipBytes;
        measured[probe] = gzipDelta;
        stdout.writeln('$probe raw=${build.rawBytes} gzip=${build.gzipBytes} '
            'deltaRaw=$rawDelta deltaGzip=$gzipDelta');
      }
      errors.addAll(checkSizeRelations(measured));
    }
    for (final entry in measured.entries) {
      final limit = budgets[backend]![entry.key];
      if (!update) errors.addAll(checkBudget(entry.key, entry.value, limit));
      stdout.writeln('${entry.key}: ${entry.value} bytes; '
          'budget=${limit ?? '待首轮实测回填'}');
    }
    if (errors.isNotEmpty) throw StateError(errors.join('\n'));
    if (update) {
      final entries = _object(budgetJson[backend], backend);
      for (final entry in measured.entries) {
        if (entry.value < 0) {
          throw StateError('负增量不能自动校准预算: ${entry.key}');
        }
        _object(entries[entry.key], entry.key)[
                backend == _web ? _webBudget : _apkBudget] =
            backend == _apk
                ? apkBudgetBytes(entry.value)
                : (entry.value * _budgetMargin).ceil();
      }
      budgetFile.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(budgetJson)}\n');
    }
    stdout.writeln('PASS: treeshake $backend (${measured.length} probes)');
  } on Object catch (error) {
    stderr.writeln('FAIL: $error');
    exitCode = 1;
  }
}
