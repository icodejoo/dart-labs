import 'dart:io';

import 'src/source.dart';

/// 核心源码区。
const String _coreZone = 'core';

/// 转盘源码区。
const String _wheelZone = 'wheel';

/// 九宫格源码区。
const String _gridZone = 'grid';

/// 老虎机源码区。
const String _slotZone = 'slot';

/// 扭蛋机源码区。
const String _capsuleZone = 'capsule';

/// 数字转盘源码区。
const String _numberWheelZone = 'number_wheel';

/// 抽签源码区。
const String _lotsZone = 'lots';

/// 大乐透源码区。
const String _lottoZone = 'lotto';

/// 迁移源码区。
const String _compatZone = 'compat';

/// 测试辅助源码区。
const String _testingZone = 'testing';

/// 入口源码区。
const String _entryZone = 'entry';

/// 入口约束的规则号。
const String _entryRule = 'IMP-R5';

/// Flutter widgets 库的 URI。
const String _widgetsLibrary = 'package:flutter/widgets.dart';

/// Dart 标准库 URI 的前缀。
const String _dartPrefix = 'dart:';

/// Flutter 库 URI 的前缀。
const String _flutterPrefix = 'package:flutter/';

/// 各区允许依赖的源码区；SDK 与 Flutter 基础库另行校验。
const Map<String, Set<String>> kAllowedZoneImports = {
  _coreZone: {_coreZone},
  _wheelZone: {_coreZone, _wheelZone},
  _gridZone: {_coreZone, _gridZone},
  _slotZone: {_coreZone, _slotZone},
  _capsuleZone: {_coreZone, _capsuleZone},
  _numberWheelZone: {_coreZone, _numberWheelZone},
  _lotsZone: {_coreZone, _lotsZone},
  _lottoZone: {_coreZone, _lottoZone},
  _compatZone: {_coreZone, _wheelZone, _gridZone, _slotZone, _compatZone},
  _testingZone: {_coreZone, _testingZone},
};

/// 返回路径的源码区；直接位于 lib 的文件为入口。
String _zone(String path) {
  final parts = path.split('/');
  return parts.length == 2
      ? _entryZone
      : parts.length > 3 && parts[1] == 'src'
          ? parts[2]
          : 'unknown';
}

/// 判断该文件是否禁止依赖 widgets 层。
bool _isPure(String path) {
  if (path == 'lib/src/core/motion/clock.dart') return false;
  final parts = path.split('/');
  if (parts.length < 5) return false;
  return parts[2] == _coreZone
      ? const {'foundation', 'geometry', 'text', 'easing', 'motion', 'picker'}
          .contains(parts[3])
      : const {'model', 'layout', 'motion'}.contains(parts[3]);
}

/// 检查入口是否允许导出目标路径。
bool _entryAllows(String path, String target) {
  final name = path.substring(4, path.length - 5);
  if (name == 'luckdraw' || name == 'extend') {
    return target.startsWith('lib/src/core/');
  }
  if (name != _compatZone &&
      name != _testingZone &&
      target == 'lib/luckdraw.dart') {
    return true;
  }
  return kAllowedZoneImports.containsKey(name) &&
      target.startsWith('lib/src/$name/');
}

/// 找到 const 表中以字符串查找具体实现的位置（ARCHITECTURE §17.3）。
///
/// 仅检查构造器和静态成员引用，保留纯数值、字符串表与单项 const 别名。
Iterable<int> _implementationTables(List<SourceToken> tokens) sync* {
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i].text != 'const') continue;
    for (var j = i + 1; j + 2 < tokens.length; j++) {
      if (tokens[j].text == ';') break;
      if (tokens[j].text != ':' || !tokens[j - 1].isString) continue;
      var value = j + 1;
      if (tokens[value].text == 'const') value++;
      // 同时识别 QuadEasing()、LuckyEasings.quad 和 easing.QuadEasing()。
      if (value + 3 < tokens.length &&
          tokens[value + 1].text == '.' &&
          RegExp(r'^[a-z_]\w*$').hasMatch(tokens[value].text)) {
        value += 2;
      }
      if (value + 1 < tokens.length &&
          RegExp(r'^[A-Z]\w*$').hasMatch(tokens[value].text) &&
          const {'(', '.'}.contains(tokens[value + 1].text)) {
        yield tokens[j].offset;
      }
    }
  }
}

/// 校验 [libSources] 的 IMP-R1…R12 与 §17.3 常量实现表；[pubspec] 为包清单原文。
///
/// 返回的每条违规包含相对路径、行号、规则号与该行原文；空列表表示通过。
List<String> checkImports(
    {required Map<String, String> libSources, required String pubspec}) {
  final errors = <String>[];
  for (final entry in libSources.entries) {
    final path = normalizePath(entry.key);
    final source = entry.value;
    final lines = source.split('\n');
    final zone = _zone(path);
    final tokens = sourceTokens(source, includeInterpolations: true);
    final comments = <int, String>{
      for (final token in sourceTokens(source, includeComments: true))
        if (token.text.startsWith(kLineCommentPrefix))
          sourceLine(source, token.offset): token.text,
    };
    final directiveTokens = <int>{};

    /// 在当前文件记录一条带原文的违规。
    void fail(String rule, int offset) {
      final line = sourceLine(source, offset);
      final error = '$path:$line:$rule: ${lines[line - 1].trim()}';
      if (!errors.contains(error)) errors.add(error);
    }

    if (zone == _coreZone) {
      for (final offset in _implementationTables(tokens)) {
        fail('TS-CONST-MAP', offset);
      }
    }

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.text == kPartDirective) fail('IMP-R6', token.offset);
      if (!kDartDirectives.contains(token.text)) {
        continue;
      }
      var end = i;
      while (end < tokens.length && tokens[end].text != ';') {
        end++;
      }
      if (end == tokens.length) {
        fail(_entryRule, token.offset);
        continue;
      }
      directiveTokens.addAll(List.generate(end - i + 1, (n) => i + n));
      if (zone == _entryZone &&
          (token.text != kLibraryDirective && token.text != kExportDirective ||
              token.text == kLibraryDirective && end != i + 1)) {
        fail(_entryRule, token.offset);
      }
      for (var j = i + 1; j < end; j++) {
        if (!tokens[j].isString) continue;
        final uri = tokens[j].value;
        if (uri == 'dart:mirrors' ||
            zone != _entryZone && uri.startsWith('package:luckdraw/')) {
          fail('IMP-R7', token.offset);
        }
        if (const {
          'package:flutter/material.dart',
          'package:flutter/cupertino.dart'
        }.contains(uri)) {
          fail('IMP-R10', token.offset);
        }
        if (uri == _widgetsLibrary && _isPure(path)) {
          fail('IMP-R11', token.offset);
        }
        if (token.text != kImportDirective && token.text != kExportDirective) {
          continue;
        }
        final target =
            normalizePath('${path.substring(0, path.lastIndexOf('/'))}/$uri');
        if (zone == _entryZone) {
          if (token.text != kExportDirective || !_entryAllows(path, target)) {
            fail(_entryRule, token.offset);
          }
          if (token.text == kExportDirective &&
              target != 'lib/luckdraw.dart' &&
              !tokens.sublist(j + 1, end).any((t) => t.text == 'show')) {
            fail(_entryRule, token.offset);
          }
        } else if (!uri.startsWith(_dartPrefix) &&
            !uri.startsWith(_flutterPrefix)) {
          final conformanceGame = path == 'lib/src/testing/conformance.dart' &&
              const {_wheelZone, _gridZone, _slotZone, _lotsZone}
                  .contains(_zone(target));
          final allowed = !uri.contains(':') &&
              ((kAllowedZoneImports[zone]?.contains(_zone(target)) ?? false) ||
                  conformanceGame);
          if (!allowed) {
            fail(
                switch (zone) {
                  _coreZone => 'IMP-R1',
                  _compatZone => 'IMP-R3',
                  _testingZone => 'IMP-R4',
                  _ => 'IMP-R2'
                },
                token.offset);
          }
        }
      }
      i = end;
    }
    var braces = 0;
    var parentheses = 0;
    var brackets = 0;
    var declarationStart = 0;
    for (var i = 0; i < tokens.length; i++) {
      if (directiveTokens.contains(i)) {
        declarationStart = i + 1;
        continue;
      }
      final token = tokens[i];
      final text = token.text;
      final line = comments[sourceLine(source, token.offset)] ?? '';
      final globalException =
          RegExp(r'//\s*imports:allow-global\s+\S').hasMatch(line);
      final runtimeException =
          RegExp(r'//\s*imports:allow-runtimeType\s+\S').hasMatch(line);
      if (zone == _entryZone) fail(_entryRule, token.offset);
      final typeMap = text == 'Type' &&
          i > 0 &&
          i + 1 < tokens.length &&
          tokens[i - 1].text == '<' &&
          tokens[i + 1].text == ',';
      final typeKey = RegExp(r'^[A-Z]\w*$').hasMatch(text) &&
          i + 1 < tokens.length &&
          tokens[i + 1].text == ':' &&
          braces > 0;
      if ((text == 'runtimeType' || typeMap || typeKey) && !runtimeException) {
        fail('IMP-R9', token.offset);
      }
      if (text == '=' &&
          parentheses == 0 &&
          brackets == 0 &&
          (i + 1 >= tokens.length ||
              !const {'=', '>'}.contains(tokens[i + 1].text)) &&
          (i == 0 ||
              !const {'=', '!', '>', '<', '+', '-', '?', '*'}
                  .contains(tokens[i - 1].text))) {
        final prefix =
            tokens.sublist(declarationStart, i).map((t) => t.text).toSet();
        if ((braces == 0 || prefix.contains('static')) &&
            !prefix.contains('const') &&
            !prefix.contains('typedef') &&
            !globalException) {
          fail('IMP-R8', token.offset);
        }
      }
      switch (text) {
        case '{':
          braces++;
          declarationStart = i + 1;
        case '}':
          braces--;
          declarationStart = i + 1;
        case '(':
          parentheses++;
        case ')':
          parentheses--;
        case '[':
          brackets++;
        case ']':
          brackets--;
        case ';':
          declarationStart = i + 1;
      }
    }
  }
  var flutterIndent = -1;
  final yamlLines = pubspec.split('\n');
  for (var i = 0; i < yamlLines.length; i++) {
    final line = yamlLines[i].split('#').first;
    if (line.trim().isEmpty) continue;
    final indent = line.length - line.trimLeft().length;
    if (indent == 0) {
      flutterIndent =
          RegExp(r'''^['"]?flutter['"]?\s*:''').hasMatch(line) ? 0 : -1;
    }
    if (flutterIndent == 0 &&
        RegExp(r'''(?:^|[\s,{])['"]?(assets|fonts)['"]?\s*:''')
            .hasMatch(line)) {
      errors.add('pubspec.yaml:${i + 1}:IMP-R12: ${line.trim()}');
    }
  }
  return errors;
}

/// 从包目录读取源码并执行依赖图门禁。
void main() {
  try {
    final sources = <String, String>{};
    if (Directory('lib').existsSync()) {
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith(kDartFileExtension))) {
        sources[file.path] = file.readAsStringSync();
      }
    }
    final errors = checkImports(
        libSources: sources, pubspec: File('pubspec.yaml').readAsStringSync());
    for (final error in errors) {
      stderr.writeln(error);
    }
    if (errors.isNotEmpty) {
      stderr.writeln('FAIL: ${errors.length} import violations / 依赖规则违规');
      exitCode = 1;
    } else {
      stdout.writeln(
          'PASS: ${sources.length} lib files; IMP-R1…R12 / 依赖图与静态规则通过');
    }
  } on Object catch (error) {
    stderr.writeln('FAIL: $error');
    exitCode = 1;
  }
}
