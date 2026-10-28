// ignore_for_file: avoid_relative_lib_imports
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// 封装 LiteralVisitor 测试夹具。
/// 收集代码中的完整字符串字面量，导入路径保留原样。
class LiteralVisitor extends RecursiveAstVisitor<void> {
  /// 当前文件的字面量节点。
  final literals = <StringLiteral>[];

  /// visitAdjacentStrings 的测试实现。
  /// 相邻字符串作为完整值提取，避免产生非法的常量与字面量拼接。
  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    if (node.stringValue != null) literals.add(node);
  }

  /// visitSimpleStringLiteral 的测试实现。
  /// 只处理非导入路径。
  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    AstNode? parent = node.parent;
    while (parent != null) {
      if (parent is Annotation) return;
      parent = parent.parent;
    }
    if (node.parent is! UriBasedDirective) literals.add(node);
  }
}

/// main 的测试辅助入口。
/// 为运行器及探针的重复字符串生成语义常量，可在生成 inventory 后重复运行。
void main() {
  final files = [
    ...Directory('accept/lib').listSync(recursive: true),
    ...Directory('accept/bin').listSync(recursive: true),
    ...Directory('test').listSync(recursive: true),
  ]
      .whereType<File>()
      .where((f) =>
          f.path.endsWith('.dart') &&
          !f.path.endsWith('hoist_literals.dart') &&
          !f.path.endsWith('literals.dart'))
      .toList();
  final constants = File('accept/lib/literals.dart');
  final existing = constants.existsSync() ? constants.readAsStringSync() : '';
  final existingNames = <String, String>{};
  for (final declaration in parseString(content: existing)
      .unit
      .declarations
      .whereType<TopLevelVariableDeclaration>()) {
    for (final variable in declaration.variables.variables) {
      final value = variable.initializer;
      if (value is SimpleStringLiteral) {
        existingNames[value.value] = variable.name.lexeme;
      }
    }
  }
  final counts = <String, int>{};
  final nodes = <File, List<StringLiteral>>{};
  for (final file in files) {
    final visitor = LiteralVisitor();
    parseString(content: file.readAsStringSync()).unit.accept(visitor);
    nodes[file] = visitor.literals;
    for (final node in visitor.literals) {
      counts.update(node.stringValue!, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  final names = <String, String>{};
  final used = existingNames.values.toSet();
  for (final entry in counts.entries
      .where((e) => e.value > 1 || existingNames.containsKey(e.key))) {
    if (existingNames.containsKey(entry.key)) {
      names[entry.key] = existingNames[entry.key]!;
      continue;
    }
    final words =
        entry.key.split(RegExp(r'[^a-zA-Z0-9]+')).where((s) => s.isNotEmpty);
    var name =
        'tk${words.map((s) => s[0].toUpperCase() + s.substring(1)).join()}';
    if (name == 'tk') name = 'tkEmpty';
    if (name.length > 90) name = name.substring(0, 90);
    final base = name;
    var index = 2;
    while (!used.add(name)) {
      name = '$base${index++}';
    }
    names[entry.key] = name;
  }
  if (names.isEmpty) return;
  for (final entry in nodes.entries) {
    var source = entry.key.readAsStringSync();
    var changed = false;
    for (final node in entry.value.reversed) {
      final name = names[node.stringValue!];
      if (name == null) continue;
      source = source.replaceRange(node.offset, node.end, name);
      changed = true;
    }
    if (changed) {
      final importPath =
          entry.key.path.replaceAll('\\', '/').startsWith('accept/lib/')
              ? 'literals.dart'
              : entry.key.path.replaceAll('\\', '/').startsWith('accept/bin/')
                  ? '../lib/literals.dart'
                  : '../../accept/lib/literals.dart';
      if (!RegExp(r'^part of ', multiLine: true).hasMatch(source) &&
          !source.contains("import '$importPath';")) {
        final directive = "import '$importPath';\n";
        if (source.contains('library;')) {
          source = source.replaceFirst('library;', 'library;\n$directive');
        } else {
          source = '$directive$source';
        }
      }
      entry.key.writeAsStringSync(source);
    }
  }
  final output = StringBuffer(existing);
  for (final entry in names.entries) {
    if (existingNames.containsKey(entry.key)) continue;
    output.writeln('/// 共享字面量：${entry.value}。');
    output.writeln(
        'const ${entry.value} = ${jsonEncode(entry.key).replaceAll(r'$', r'\$')};');
  }
  constants.writeAsStringSync(output.toString());
  stdout.writeln('提取 ${names.length} 个重复字符串常量');
}
