import 'dart:convert';
import 'dart:io';

/// 本文件共用的字面量 'field'。
const _field = 'field';

/// 本文件共用的字面量 'getter'。
const _getter = 'getter';

/// 本文件共用的字面量 'setter'。
const _setter = 'setter';

/// 本文件共用的字面量 'core'。
const _core = 'core';

/// 本文件共用的空串。
const _empty = '';

/// 本文件共用的字面量 'id'。
const _id = 'id';

/// 本文件共用的字面量 'plugin'。
const _plugin = 'plugin';

/// 本文件共用的字面量 'capability'。
const _capability = 'capability';

/// 本文件共用的字面量 'tier'。
const _tier = 'tier';

/// 本文件共用的字面量 'apis'。
const _apis = 'apis';

/// 本文件共用的字面量 'real'。
const _real = 'real';

/// 本文件共用的字面量 'assumptions'。
const _assumptions = 'assumptions';

/// 本文件共用的字面量 'result'。
const _result = 'result';

/// 明确登记的外部阻塞，不表示已执行或通过。
const _blockedStatus = 'BLOCKED';

/// 行的可选字段：没有 API 可反查时直接列单测文件（仅 INV-xx 等不变量行用）。
const _unit = 'unit';

/// 本文件共用的字面量 'blocked'。
const _blocked = 'blocked';

/// 本文件共用的字面量 '\\'。
const _backslash = '\\';

/// 本文件共用的字面量 '/'。
const _slash = '/';

/// 本文件共用的字面量 '{'。
const _openBrace = '{';

/// 本文件共用的字面量 '.dart'。
const _dart = '.dart';

/// 本文件共用的字面量 'kind'。
const _kind = 'kind';

/// 本文件共用的字面量 'api'。
const _api = 'api';

/// 本文件共用的字面量 '|'。
const _pipe = '|';

/// 行为型 API 种类。
const behaviorKinds = {
  'parameter',
  _field,
  'method',
  _getter,
  _setter,
  'enumValue',
  'function',
  'constant',
};

/// 默认静态闸门前缀。
const staticGates = {'G0:', 'G2:', 'G3:', 'G5:'};

/// 总账目录。
const matrixDirectory = 'test/accept/lib';

/// 总账行，附加字段原样往返。
class MatrixRow {
  /// 用字段构造一行；例如 `MatrixRow(id: 'X.max', apis: ['X.max'])`。
  MatrixRow(
      {required this.id,
      this.plugin = _core,
      this.capability = _empty,
      this.tier,
      this.apis = const [],
      this.real = const [],
      this.assumptions = const [],
      this.result,
      this.blocked,
      this.extra = const {}});

  /// 从 [json] 读取一行；返回可写回的模型，例如 `MatrixRow.fromJson({'id':'X'})`。
  factory MatrixRow.fromJson(Map<String, dynamic> json) => MatrixRow(
        id: json[_id] as String,
        plugin: json[_plugin] as String? ?? _core,
        capability: json[_capability] as String? ?? _empty,
        tier: json[_tier] as int?,
        apis: _strings(json[_apis]),
        real: _strings(json[_real]),
        assumptions: _strings(json[_assumptions]),
        result: (json[_result] as Map?)?.cast<String, dynamic>(),
        blocked: json[_blocked] as String?,
        extra: Map.of(json),
      );

  final String id, plugin, capability;
  final int? tier;
  final List<String> apis, real, assumptions;
  final Map<String, dynamic>? result;
  final String? blocked;
  final Map<String, dynamic> extra;

  /// 返回含未知字段的 JSON 对象；例如 `jsonEncode(row.toJson())`。
  Map<String, dynamic> toJson() => {
        ...extra,
        _id: id,
        _plugin: plugin,
        _capability: capability,
        _tier: tier,
        _apis: apis,
        _real: real,
        _assumptions: assumptions,
        _result: result,
        _blocked: blocked
      };
}

/// 将可选数组转成字符串列表。
List<String> _strings(dynamic value) => (value as List? ?? []).cast<String>();

/// 从 [title] 返回方括号中的全部 id；例如 `[A × B][C]` 返回三项。
List<String> parseTitleIds(String title) => [
      for (final match in RegExp(r'\[([^\]]*)\]').allMatches(title))
        ...match[1]!.split('×').map((s) => s.trim()).where((s) => s.isNotEmpty),
    ];

/// 规范化文件路径，去掉根目录。
String _path(String path, String root) {
  final normalized = path.replaceAll(_backslash, _slash);
  final base =
      root.replaceAll(_backslash, _slash).replaceAll(RegExp(r'/$'), _empty);
  return normalized.startsWith('$base/')
      ? normalized.substring(base.length + 1)
      : normalized;
}

/// 扫描 [testDir] 的单测字面量标题，返回 id 到相对文件集合；例如 `scanTestTitles(Directory('test'))`。
Map<String, Set<String>> scanTestTitles(Directory testDir) {
  final found = <String, Set<String>>{};
  for (final file in testDir.listSync(recursive: true).whereType<File>()) {
    final path = _path(file.absolute.path, testDir.absolute.parent.path);
    if (!path.endsWith('_test.dart') || path.startsWith('test/accept/')) {
      continue;
    }
    for (final id in titleIdsFromSource(file.readAsStringSync())) {
      (found[id] ??= {}).add(path);
    }
  }
  return found;
}

/// 从 [source] 的 test 标题收集 id，支持相邻字面量；例如 `titleIdsFromSource("test('[A]', () {})")` 返回 A。
List<String> titleIdsFromSource(String source) {
  final title = RegExp(r'''\btest\(\s*((?:r?(['"])(?:\\.|(?!\2).)*\2\s*)+),''',
      dotAll: true);
  final literal = RegExp(r'''r?(['"])((?:\\.|(?!\1).)*)\1''', dotAll: true);
  final constants = <String, String>{
    for (final match in RegExp(
            r'''\bconst\s+(?:String\s+)?(\w+)\s*=\s*(['"])([^\r\n]*?)\2\s*;''')
        .allMatches(source))
      match[1]!: match[3]!,
  };
  final ids = <String>[];
  var offset = 0;
  while (offset < source.length) {
    if (source.startsWith('//', offset)) {
      final end = source.indexOf('\n', offset);
      offset = end < 0 ? source.length : end + 1;
      continue;
    }
    if (source.startsWith('/*', offset)) {
      final end = source.indexOf('*/', offset + 2);
      offset = end < 0 ? source.length : end + 2;
      continue;
    }
    final match = source.startsWith('test', offset)
        ? title.matchAsPrefix(source, offset)
        : null;
    if (match != null) {
      var value = literal.allMatches(match[1]!).map((m) => m[2]!).join();
      for (final entry in constants.entries) {
        value = value.replaceAll(r'$' + entry.key, entry.value);
      }
      ids.addAll(parseTitleIds(value));
      offset = match.end;
      continue;
    }
    final char = source[offset];
    if (char == "'" || char == '"') {
      final delimiter = source.startsWith(char * 3, offset) ? char * 3 : char;
      final raw = offset > 0 && source[offset - 1] == 'r';
      offset += delimiter.length;
      while (offset < source.length && !source.startsWith(delimiter, offset)) {
        offset += !raw && source[offset] == _backslash ? 2 : 1;
      }
      offset += delimiter.length;
    } else {
      offset++;
    }
  }
  return ids;
}

/// 从源码 [sources] 收集粗粒度符号；返回内部 id 集合，例如 `symbolsFromSources({'matrix': 'void sync() {}'})`。
Set<String> symbolsFromSources(Map<String, String> sources) {
  final result = <String>{};
  final names = RegExp(r'\b([A-Za-z_$][\w$]*)\s*(?:<[^<>;{}()]*>)?\s*\(');
  final fields = RegExp(
      r'\b(?:get|set|final|var|const|late|bool|int|String)\s+(?:[\w<>?,]+\s+)?([A-Za-z_$][\w$]*)\s*(?:[;=({]|=>)');
  for (final entry in sources.entries) {
    final source =
        entry.value.replaceAll(RegExp(r'//[^\n]*|/\*[\s\S]*?\*/'), _empty);
    final members = {
      ...names.allMatches(source).map((m) => m[1]!),
      ...fields.allMatches(source).map((m) => m[1]!)
    };
    final classes =
        RegExp(r'\b(?:class|enum|mixin)\s+(\w+)').allMatches(source);
    result.addAll(members);
    result.addAll(members.map((m) => '${entry.key}.$m'));
    for (final cls in classes) {
      result.add(cls[1]!);
      final start = source.indexOf(_openBrace, cls.end);
      if (start < 0) continue;
      var depth = 1;
      var end = start + 1;
      while (end < source.length && depth > 0) {
        if (source[end] == _openBrace) depth++;
        if (source[end] == '}') depth--;
        end++;
      }
      final body = source.substring(start, end);
      for (final member in members) {
        if (RegExp('\\b${RegExp.escape(member)}\\b').hasMatch(body)) {
          result.add('${cls[1]}.$member');
        }
      }
    }
  }
  return result;
}

/// 扫描 [directories] 下 Dart 内部符号；例如 `internalSymbols([Directory('lib/src')])` 返回认可的 id。
Set<String> internalSymbols(List<Directory> directories) => symbolsFromSources({
      for (final directory in directories.where((d) => d.existsSync()))
        for (final file
            in directory.listSync(recursive: true).whereType<File>())
          if (file.path.endsWith(_dart))
            file.uri.pathSegments.last.replaceAll(_dart, _empty):
                file.readAsStringSync(),
    });

/// 按归位后的源路径分组；plugins 下每个文件就是独立能力。
String pluginForFile(String? file) {
  final normalized = (file ?? _empty).replaceAll(_backslash, _slash);
  return normalized.split(_slash).last.replaceAll(_dart, _empty);
}

/// 为 [inventory] 追加未覆盖草稿，保留 [existingRows]；例如 `draftRows(inventory, [])` 返回排序矩阵。
List<MatrixRow> draftRows(
    List<Map<String, dynamic>> inventory, List<MatrixRow> existingRows) {
  final covered = existingRows.expand((r) => r.apis).toSet();
  final files = {
    for (final item in inventory) item[_api] as String: item['file'] as String?
  };
  final properties = {
    for (final item in inventory)
      if (const {_field, _getter, _setter}.contains(item[_kind]))
        item[_api] as String
  };
  final groups = <String, Set<String>>{};
  for (final item in inventory) {
    final api = item[_api] as String;
    if (!behaviorKinds.contains(item[_kind])) {
      continue;
    }
    final param = RegExp(r'^([^.]+)\.[^(]+\(([^)]+)\)$').firstMatch(api);
    final property = param == null ? api : '${param[1]}.${param[2]}';
    final id = properties.contains(property) ? property : api;
    (groups[id] ??= {}).add(api);
  }
  final rows = [...existingRows];
  for (final entry in groups.entries) {
    final missing = entry.value.difference(covered);
    if (missing.isEmpty) continue;
    // 已有人工行只补充 API 链接，保留其余字段。
    final index = rows.indexWhere(
        (r) => r.id == entry.key || r.apis.any(entry.value.contains));
    if (index >= 0) {
      final row = rows[index];
      rows[index] = MatrixRow.fromJson({
        ...row.toJson(),
        _apis: {...row.apis, ...missing}.toList()..sort()
      });
    } else {
      rows.add(MatrixRow(
          id: entry.key,
          plugin: pluginForFile(files[entry.value.first]),
          apis: missing.toList()..sort()));
    }
  }
  rows.sort((a, b) => a.plugin == b.plugin
      ? a.id.compareTo(b.id)
      : a.plugin.compareTo(b.plugin));
  return rows;
}

/// 从 [markdown] 返回已证伪 H 编号；例如 `falsifiedAssumptions('| H1 | 已证伪 |')`。
Set<String> falsifiedAssumptions(String markdown) => {
      for (final cells in markdown
          .split('\n')
          .where((line) => line.startsWith(_pipe))
          .map((line) => line.split(_pipe)))
        // 列序：编号 | 假设 | 出处 | 依赖单测 | 核对状态 …，只看状态列。
        if (cells.length > 5 && cells[5].trim().startsWith('已证伪'))
          ...RegExp(r'\bH\d+[a-z]?\b').allMatches(cells[1]).map((m) => m[0]!),
    };

/// 计算内存数据的缺口；[full] 开启真实侧，[lcov] 与 [sourceLines] 开启 G1。
/// 返回 gap key 集合，例如 `computeGaps(inventory: [], rows: [], titles: {})`。
Set<String> computeGaps({
  required List<Map<String, dynamic>> inventory,
  required List<MatrixRow> rows,
  required Map<String, Set<String>> titles,
  Set<String> symbols = const {},
  Set<String>? evidenceHits,
  bool full = false,
  Set<String> realIds = const {},
  Set<String> falsified = const {},
  String? lcov,
  Map<String, List<String>> sourceLines = const {},
  List<Map<String, dynamic>> whitelist = const [],
  String root = _empty,
}) {
  final gaps = <String>{};
  final apis = inventory.map((i) => i[_api] as String).toSet();
  final covered = rows.expand((r) => r.apis).toSet();
  for (final item in inventory) {
    final api = item[_api] as String;
    if (behaviorKinds.contains(item[_kind])
        ? !covered.contains(api)
        : !titles.containsKey(api) &&
            (evidenceHits == null || !evidenceHits.contains(api))) {
      gaps.add('G2:$api');
    }
  }
  // 含用例的测试文件，供没有 API 的行（INV-xx）用 unit 字段直接指向。
  final testFiles = titles.values.expand((files) => files).toSet();
  for (final row in rows) {
    if (row.tier == null) gaps.add('G0:${row.id}');
    final unit = _strings(row.extra.entries
        .firstWhere((entry) => entry.key == _unit,
            orElse: () => const MapEntry(_unit, null))
        .value);
    for (final file in unit.where((f) => !testFiles.contains(f))) {
      gaps.add('G5:row-unit:${row.id}:$file');
    }
    // 单测可以用 API id 引用，也可以直接在标题里写行 id（如 `[INV-20]`）。
    if (row.tier != 3 &&
        !row.apis.any(titles.containsKey) &&
        (titles[row.id]?.isEmpty ?? true) &&
        !unit.any(testFiles.contains)) {
      gaps.add('G3:${row.id}');
    }
    for (final api in row.apis.where((a) => !apis.contains(a))) {
      gaps.add('G5:row-api:${row.id}:$api');
    }
    if (!full) continue;
    if (row.tier == 2 || row.tier == 3) {
      if (row.real.isEmpty) gaps.add('G4:${row.id}:no-real');
      if (row.result == null) gaps.add('G4:${row.id}:no-result');
    }
    // 只要挂了真实结论就要守住：FAIL 必须被看见；BLOCKED 必须写明原因。
    if (row.result?['status'] == 'FAIL') gaps.add('G4:${row.id}:fail');
    if (row.result?['status'] == _blockedStatus &&
        (row.blocked?.trim().isEmpty ?? true)) {
      gaps.add('G4:${row.id}:blocked-no-reason');
    }
    for (final h in row.assumptions.where(falsified.contains)) {
      gaps.add('G4:${row.id}:falsified-$h');
    }
  }
  final rowIds = rows.map((r) => r.id).toSet();
  for (final id in titles.keys) {
    if (!apis.contains(id) && !rowIds.contains(id) && !symbols.contains(id)) {
      gaps.add('G5:$id');
    }
  }
  // 本地真实回环核对（`local:<测试文件>`）：文件必须存在且含用例，与验收场景分开校验。
  final allReal = rows.expand((r) => r.real).toSet();
  for (final id in allReal.where((id) => id.startsWith(localRealPrefix))) {
    if (!testFiles.contains(id.substring(localRealPrefix.length))) {
      gaps.add('G5:real-unknown:$id');
    }
  }
  if (full) {
    final used = allReal.where((id) => !id.startsWith(localRealPrefix)).toSet();
    gaps.addAll(used.difference(realIds).map((id) => 'G5:real-unknown:$id'));
    gaps.addAll(realIds.difference(used).map((id) => 'G5:real-orphan:$id'));
  }
  if (lcov != null) {
    var file = _empty;
    final allowed = {
      for (final w in whitelist)
        '${_path(w['file'] as String, root)}:${(w['text'] as String).trim()}'
    };
    final hits = <String, Map<int, int>>{};
    for (final line in const LineSplitter().convert(lcov)) {
      if (line.startsWith('SF:')) file = _path(line.substring(3), root);
      if (line.startsWith('DA:')) {
        final parts = line.substring(3).split(',');
        final number = int.parse(parts[0]);
        final counts = hits[file] ??= {};
        counts[number] = (counts[number] ?? 0) + int.parse(parts[1]);
      }
    }
    final missed = <String>{};
    for (final entry in hits.entries) {
      final lines = sourceLines[entry.key];
      if (lines == null) throw StateError('缺少 G1 源码: ${entry.key}');
      for (final hit in entry.value.entries.where((h) => h.value == 0)) {
        if (hit.key < 1 || hit.key > lines.length) {
          throw StateError('G1 行号越界: ${entry.key}:${hit.key}');
        }
        final key = '${entry.key}:${lines[hit.key - 1].trim()}';
        missed.add(key);
        if (!allowed.contains(key)) gaps.add('G1:$key');
      }
    }
    // 白名单只减不增：已被测到的行还留在白名单里，会掩盖它将来再次失守。
    for (final key in allowed.difference(missed)) {
      gaps.add('G1:stale:$key');
    }
  }
  return gaps;
}

/// 比较 [gaps] 与 [baseline] 的 [required] 前缀；返回新增和已修复集合，例如 `ratchet({'G0:X'}, {}, required: staticGates)`。
({Set<String> added, Set<String> fixed}) ratchet(
    Set<String> gaps, Set<String> baseline,
    {required Set<String> required}) {
  /// 只保留指定闸门。
  Set<String> select(Set<String> values) =>
      values.where((g) => required.any(g.startsWith)).toSet();
  final current = select(gaps), previous = select(baseline);
  return (
    added: current.difference(previous),
    fixed: previous.difference(current)
  );
}

/// 入库证据汇总所在目录。
const evidenceDirectory = 'test/accept/evidence';

/// 验收报告里的"通过"状态。
const _passed = '通过';

/// 验收报告里的"失败"状态。
const _failed = '失败';

/// 汇总里"场景没声明这个网络/风格"的格子状态：不适用，不计入结论。
const notApplicable = '不适用';

/// 把原始验收报告压成可入库的汇总。
///
/// [reports] 为 cli/run_plugin_matrix 产出的报告对象（含 `results` 数组），
/// 按传入顺序后者覆盖前者；[apiHits] 为 api-evidence 的触达 API 名。
/// 因"场景未声明此网络或风格"而跳过的格子记为 [notApplicable]，
/// 其余跳过（如 429/503 策略）保留"跳过"，回填时算 BLOCKED。
/// 返回 `{cases: {场景id: {"网络@风格": 状态}}, apiHits: [...]}`。
/// 例：`summarizeEvidence([report])['cases']['auth.x']['normal@http'] == '通过'`。
Map<String, dynamic> summarizeEvidence(List<Map<String, dynamic>> reports,
    {Iterable<String> apiHits = const []}) {
  final cases = <String, Map<String, String>>{};
  for (final report in reports) {
    for (final raw in report['results'] as List? ?? const []) {
      final item = (raw as Map).cast<String, dynamic>();
      final id = item['scenario'] as String?;
      if (id == null) continue;
      // 场景没声明这个网络/风格，或执行器判定与 dioman 设计不适用（原因以
      // "不适用："开头），都不计入结论。
      final undeclared = (item['reasons'] as List? ?? const [])
          .any((r) => '$r'.contains('未声明') || '$r'.startsWith('不适用：'));
      (cases[id] ??= {})['${item['network']}@${item['style']}'] =
          undeclared ? notApplicable : item['status'] as String? ?? _empty;
    }
  }
  return {
    'cases': {
      for (final id in cases.keys.toList()..sort())
        id: Map.fromEntries(
            cases[id]!.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
    },
    'apiHits': apiHits.toList()..sort(),
  };
}

/// 本地真实回环核对的 real id 前缀：`local:test/boundary/x_test.dart`。
///
/// 只用于假设关乎 Dio IO 实现与 OS socket（如 H1b、H5）的行；网络条件相关的行
/// 仍须用 testkit 验收场景。这类文件属于默认 `dart test`，任何失败都过不了全量
/// 门槛，所以回填时按"通过"计一格。
const localRealPrefix = 'local:';

/// 由汇总 [cases] 推出 [row] 的最近结论；行没挂真实用例或证据里一条都没有时返回 null。
///
/// 任一格失败 → FAIL；无失败且至少一格通过 → PASS；其余（全跳过）→ BLOCKED。
/// [notApplicable] 的格子先剔除；剔除后一格不剩也返回 null。
/// 唯独明确登记外部阻塞且无 real 的②③行保留 BLOCKED、0/0，不伪造执行证据。
/// `local:` 本地真实核对各计一格"通过"（见 [localRealPrefix]）。
/// 返回 `{status, source, passed, total}`，passed/total 按格子计数（跳过计入 total）。
/// 例：`rowResult(row, cases, 'test/accept/evidence/x.json')?['status']`。
Map<String, dynamic>? rowResult(
    MatrixRow row, Map<String, dynamic> cases, String source) {
  final statuses = [
    for (final id in row.real)
      if (id.startsWith(localRealPrefix))
        _passed
      else
        ...((cases[id] as Map?)?.values.cast<String>() ?? const <String>[])
            .where((s) => s != notApplicable)
  ];
  if (statuses.isEmpty) {
    if (row.real.isNotEmpty ||
        !const {2, 3}.contains(row.tier) ||
        (row.blocked?.trim().isEmpty ?? true)) {
      return null;
    }
    return {
      'status': _blockedStatus,
      'source': source,
      'passed': 0,
      'total': 0,
    };
  }
  final passed = statuses.where((s) => s == _passed).length;
  final status = statuses.contains(_failed)
      ? 'FAIL'
      : passed > 0
          ? 'PASS'
          : _blockedStatus;
  return {
    'status': status,
    'source': source,
    'passed': passed,
    'total': statuses.length
  };
}

/// 返回 [evidenceDirectory] 下按文件名排序最新的汇总路径，没有返回 null。
String? latestEvidence(Directory root) {
  final dir = Directory('${root.path}/$evidenceDirectory');
  if (!dir.existsSync()) return null;
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .map((f) => '$evidenceDirectory/${f.uri.pathSegments.last}')
      .toList()
    ..sort();
  return files.lastOrNull;
}

/// 读取 [path] 的 JSON，不存在返回 [fallback]；例如 `readMatrixJson('missing', [])`。
dynamic readMatrixJson(String path, dynamic fallback) => File(path).existsSync()
    ? jsonDecode(File(path).readAsStringSync())
    : fallback;

/// 从 [root] 读取闸门输入，返回缺口；[full] 控制真实侧，例如 `repositoryGaps(Directory.current, rows)`。
Set<String> repositoryGaps(Directory root, List<MatrixRow> rows,
    {bool full = false, String? lcovPath}) {
  /// 将仓库相对路径解析为绝对路径。
  String at(String path) => File(path).isAbsolute ? path : '${root.path}/$path';
  // 优先用入库汇总里的 API 触达清单，干净检出也能得到一致结果；没有再退回本地产物。
  final summaryPath = latestEvidence(root);
  final summaryHits = summaryPath == null
      ? null
      : ((readMatrixJson(at(summaryPath), {}) as Map)['apiHits'] as List?)
          ?.cast<String>()
          .toSet();
  final evidence =
      readMatrixJson(at('coverage/accept/api-evidence.json'), null) as Map?;
  final realIds = <String>{};
  if (full) {
    final plan =
        readMatrixJson(at('$matrixDirectory/plugin_matrix_plan.json'), [])
            as List;
    for (final item in plan) {
      realIds.add((item['scenario'] ?? item[_id]) as String);
    }
    final scenarios = Directory('E:/workspaces/api-ws-demo/testkit/scenarios');
    if (scenarios.existsSync()) {
      for (final file in scenarios
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))) {
        final data = readMatrixJson(file.path, []) as List;
        for (final item in data) {
          if (item[_id] is String) realIds.add(item[_id] as String);
        }
      }
    }
  }
  final lcov = lcovPath == null ? null : File(at(lcovPath)).readAsStringSync();
  final sources = <String, List<String>>{};
  if (lcov != null) {
    for (final match
        in RegExp(r'^SF:(.+)$', multiLine: true).allMatches(lcov)) {
      final file = _path(match[1]!.trim(), root.absolute.path);
      sources[file] = File(at(file)).readAsLinesSync();
    }
  }
  final assumptions = File(at('test/ASSUMPTIONS.md'));
  return computeGaps(
      inventory: (readMatrixJson(at('$matrixDirectory/api-inventory.json'), [])
              as List)
          .cast<Map<String, dynamic>>(),
      rows: rows,
      titles: scanTestTitles(Directory(at('test'))),
      symbols: internalSymbols(
          [Directory(at('lib/src')), Directory(at(matrixDirectory))]),
      evidenceHits: summaryHits ??
          (evidence?['hits'] as Map?)?.keys.cast<String>().toSet(),
      full: full,
      realIds: realIds,
      falsified: assumptions.existsSync()
          ? falsifiedAssumptions(assumptions.readAsStringSync())
          : {},
      lcov: lcov,
      sourceLines: sources,
      root: root.absolute.path,
      whitelist:
          (readMatrixJson(at('$matrixDirectory/matrix-lcov-whitelist.json'), [])
                  as List)
              .cast<Map<String, dynamic>>());
}
