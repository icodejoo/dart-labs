// ignore_for_file: avoid_relative_lib_imports
// test/accept/lib 是仓库内执行器源码，按目标目录使用相对导入。
// ignore_for_file: depend_on_referenced_packages
import '../lib/literals.dart';
import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// main 的测试辅助入口。
/// 生成导出源文件的完整公开声明与构造参数清单，不把源码行覆盖伪称选项覆盖。
void main() {
  final rows = <Map<String, dynamic>>[];
  final exports = File('lib/dioman.dart').readAsStringSync();
  final exportPattern = RegExp(r"export '([^']+)'([^;]*);");
  // barrel 的 show/hide 决定哪些顶层名字是公共 API：show 只收列出的，hide 排除列出的。
  final shown = <String, Set<String>?>{}, hidden = <String, Set<String>>{};

  /// 取 [clause] 里 [keyword] 后面的名字列表。
  Set<String>? names(String clause, String keyword) {
    final m = RegExp(r'\b' + keyword + r'\b([^;]*?)(?:\b(?:show|hide)\b|$)')
        .firstMatch(clause);
    return m == null
        ? null
        : ({for (final n in m[1]!.split(',')) n.trim()}..remove(''));
  }

  for (final m in exportPattern.allMatches(exports)) {
    final path = 'lib/${m[1]}';
    shown[path] = names(m[2]!, 'show');
    hidden[path] = names(m[2]!, 'hide') ?? {};
  }
  for (final file in shown.keys.map(File.new)) {
    final parsed =
        parseString(content: file.readAsStringSync(), path: file.absolute.path);

    /// 记录可审计的声明位置。
    /// add 的测试辅助入口。
    void add(String owner, String name, String kind, AstNode node,
        {bool isStatic = false}) {
      if (name.startsWith(tkUnderscore)) return;
      // 顶层名字和类成员都按所属顶层声明判断是否导出。
      final top = owner.isEmpty ? name : owner;
      if (hidden[file.path]!.contains(top)) return;
      if (shown[file.path] != null && !shown[file.path]!.contains(top)) return;
      rows.add({
        tkApi: owner.isEmpty ? name : '$owner.$name',
        tkKind: kind,
        tkFile: file.path.replaceAll('\\', '/'),
        'line': parsed.lineInfo.getLocation(node.offset).lineNumber,
        tkStatic: isStatic,
      });
    }

    for (final declaration in parsed.unit.declarations) {
      if (declaration is ClassDeclaration) {
        final owner = declaration.namePart.typeName.lexeme;
        if (owner.startsWith(tkUnderscore)) continue;
        add(tkEmpty, owner, tkClass, declaration);
        for (final member in declaration.body.members) {
          if (member is ConstructorDeclaration) {
            add(owner, member.name?.lexeme ?? tkNew, tkConstructor, member);
            for (final p in member.parameters.parameters) {
              final name = p.name?.lexeme;
              if (name != null) {
                add(owner, '${member.name?.lexeme ?? tkNew}($name)',
                    'parameter', p);
              }
            }
          } else if (member is MethodDeclaration) {
            add(
                owner,
                member.name.lexeme,
                member.isGetter
                    ? tkGetter
                    : member.isSetter
                        ? 'setter'
                        : tkMethod,
                member,
                isStatic: member.isStatic);
          } else if (member is FieldDeclaration) {
            for (final v in member.fields.variables) {
              add(owner, v.name.lexeme, tkField, v, isStatic: member.isStatic);
            }
          }
        }
      } else if (declaration is EnumDeclaration) {
        final owner = declaration.namePart.typeName.lexeme;
        add(tkEmpty, owner, 'enum', declaration);
        for (final v in declaration.body.childEntities
            .whereType<EnumConstantDeclaration>()) {
          add(owner, v.name.lexeme, 'enumValue', v);
        }
      } else if (declaration is FunctionDeclaration) {
        add(tkEmpty, declaration.name.lexeme, 'function', declaration);
      } else if (declaration is GenericTypeAlias) {
        add(tkEmpty, declaration.name.lexeme, 'typedef', declaration);
      } else if (declaration is TopLevelVariableDeclaration) {
        for (final v in declaration.variables.variables) {
          add(tkEmpty, v.name.lexeme, 'constant', v);
        }
      }
    }
  }
  final file = File(tkAcceptApiInventoryJson);
  file.writeAsStringSync(
      const JsonEncoder.withIndent(tkJsonIndent).convert(rows));
  stdout.writeln('公开声明与参数: ${rows.length}，输出 ${file.path}');
  final generated = StringBuffer(
      "part of 'probes.dart';\n\n/// 自动生成的逐属性读取检查器，由 inventory.dart 更新。\nvoid generatedInspect(ApiEvidence e, Map<String,Object> values) {\n");
  for (final row in rows.where((r) => r[tkKind] == tkClass)) {
    final type = row[tkApi] as String;
    final fields = rows
        .where((r) =>
            (r[tkKind] == tkField || r[tkKind] == tkGetter) &&
            '${r[tkApi]}'.startsWith('$type.'))
        .toList();
    if (fields.isEmpty) continue;
    final staticFields = fields.where((r) => r[tkStatic] == true);
    for (final field in staticFields) {
      generated.writeln("  e.read('${field[tkApi]}', ${field[tkApi]});");
    }
    final instanceFields = fields.where((r) => r[tkStatic] != true).toList();
    if (instanceFields.isEmpty) continue;
    generated.writeln(
        "  if (values['$type'] is $type) {\n    final v = values['$type'] as $type;\n    final snapshot = <String,Object?>{");
    for (final field in instanceFields) {
      final name = '${field[tkApi]}'.substring(type.length + 1);
      generated.writeln("      '${field[tkApi]}':v.$name,");
    }
    generated
        .writeln("    };\n    e.mark(snapshot.keys,'property read');\n  }");
  }
  generated.writeln('}');
  File('test/accept/lib/probes_fields.dart')
      .writeAsStringSync(generated.toString());
}
